// @ts-nocheck
// CNC MSP FORGE | AGT-RUN-01 v1.0.0 | msp-intake-worker 08/10/2026
//
// Called by pg_cron every five minutes (migration 066), or on demand by a
// forge_admin through msp_intake_worker_kick. One run:
//   1. drafts up to agent.pipeline_batch_size clean submissions with the
//      deterministic pipeline (agent/pipeline.js, inlined below; no AI), writes
//      each stage to msp_draft and queues the Plan for the practitioner, or
//      halts it for a person with the reasons;
//   2. sends what is owed, once per engagement per kind: new submission and
//      drafting outcome to sales; review request and one overdue reminder to the
//      practitioner (only once integration.msp_notify_omp_to holds an address).
//
// Request: POST, header x-msp-worker-key (the Vault secret msp_worker_key).
// Body (all optional): { "dry_run": true }        compute and report, write and send nothing
//                      { "mode": "notify" }       notifications only
//                      { "mode": "pipeline" }     drafting only
//                      { "mode": "preflight", "scope": "industry" | "all" }
//                         runs the pipeline on a fictitious TEST intake for every
//                         industry (or every selectable area of work) and reports
//                         which would draft cleanly; writes and sends nothing.
//
// Secrets (already set on ahp-production for auth-send-email): GRAPH_TENANT_ID,
// GRAPH_CLIENT_ID, GRAPH_CLIENT_SECRET, MAIL_SENDER. The platform injects
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. Deploy with JWT verification OFF:
// the worker key is the gate.
//
// No clinical data: submissions hold roles, hazards and exposure levels, never a
// person's results, and mails carry company and contact details only.

const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
const SERVICE_KEY = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
const TENANT_ID = (Deno.env.get("GRAPH_TENANT_ID") ?? "").trim();
const CLIENT_ID = (Deno.env.get("GRAPH_CLIENT_ID") ?? "").trim();
const CLIENT_SECRET = (Deno.env.get("GRAPH_CLIENT_SECRET") ?? "").trim();
const MAIL_SENDER = (Deno.env.get("MAIL_SENDER") ?? "").trim();
const MAX_MAILS_PER_RUN = 25;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function rpc(fn, args = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${fn} ${res.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

let cachedToken = null;
async function graphToken() {
  if (cachedToken) return cachedToken;
  const res = await fetch(`https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: CLIENT_ID, client_secret: CLIENT_SECRET,
      scope: "https://graph.microsoft.com/.default", grant_type: "client_credentials" }),
  });
  if (!res.ok) throw new Error(`graph token ${res.status}: ${(await res.text()).slice(0, 200)}`);
  cachedToken = (await res.json()).access_token;
  return cachedToken;
}

async function graphSend(to, cc, subject, html) {
  const token = await graphToken();
  const addr = (a) => ({ emailAddress: { address: a } });
  const res = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(MAIL_SENDER)}/sendMail`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: { subject, body: { contentType: "HTML", content: html },
        toRecipients: to.map(addr), ccRecipients: cc.map(addr) },
      saveToSentItems: true,
    }),
  });
  if (res.status !== 202) throw new Error(`sendMail ${res.status}: ${(await res.text()).slice(0, 200)}`);
}

function todaySast() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Johannesburg" }).format(new Date());
}

async function draftClaimed(item) {
  try {
    const kernel = await rpc("msp_pipeline_kernel", { p_subindustry_code: item.intake.subindustry_code || "" });
    const result = runPipeline(PIPELINE, kernel, item.intake, item.reference, todaySast());
    const saved = await rpc("msp_pipeline_persist", { p_engagement_id: item.engagement_id, p_result: result });
    return { reference: item.reference, outcome: result.outcome, status: saved.status, summary: result.summary };
  } catch (err) {
    const message = String(err && err.message || err).slice(0, 500);
    try {
      const saved = await rpc("msp_pipeline_persist", { p_engagement_id: item.engagement_id,
        p_result: { outcome: "error", error: message, model_used: MODEL_USED } });
      return { reference: item.reference, outcome: "error", status: saved.status, error: message };
    } catch (err2) {
      return { reference: item.reference, outcome: "error", status: "unrecorded", error: `${message} | ${err2.message}` };
    }
  }
}

async function preflight(scope) {
  const rows = await fetch(`${SUPABASE_URL}/rest/v1/msp_subindustry?select=code,name,selectable,msp_industry(code,name,regulatory_regime)&order=code`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  }).then((r) => r.json());
  const selectable = rows.filter((r) => r.selectable);
  const picks = scope === "all" ? selectable
    : Object.values(selectable.reduce((acc, r) => { const k = r.msp_industry.code; if (!acc[k]) acc[k] = r; return acc; }, {}));
  const out = [];
  for (const sub of picks) {
    try {
      const kernel = await rpc("msp_pipeline_kernel", { p_subindustry_code: sub.code });
      const intake = preflightIntake(kernel, sub.code);
      const r = runPipeline(PIPELINE, kernel, intake, "CNC-MSP-PREFLIGHT", todaySast());
      out.push({ industry: sub.msp_industry.code, regime: sub.msp_industry.regulatory_regime, subindustry: sub.code,
        outcome: r.outcome, jobs: intake.jobs.length, summary: r.summary,
        failed_checks: r.defects.map((d) => d.defect_code) });
    } catch (err) {
      out.push({ industry: sub.msp_industry.code, subindustry: sub.code, outcome: "error", error: String(err.message || err).slice(0, 300) });
    }
  }
  return { checked: out.length, clean: out.filter((x) => x.outcome === "queued").length, results: out };
}

async function notify(due, dryRun) {
  const s = due.settings || {};
  const salesTo = emails(s.sales_to), salesCc = emails(s.sales_cc), ompTo = emails(s.omp_to);
  const site = siteBase(s.site_url);
  const plan = [];
  for (const e of due.intake_received || []) plan.push({ e, kind: "intake_received", to: salesTo, cc: salesCc, mail: renderIntakeMail(e, site) });
  for (const e of due.pipeline_result || []) plan.push({ e, kind: "pipeline_result", to: salesTo, cc: salesCc, mail: renderResultMail(e, site, ompTo.length > 0, s.review_days) });
  if (ompTo.length) {
    for (const e of due.omp_review_requested || []) plan.push({ e, kind: "omp_review_requested", to: ompTo, cc: salesTo, mail: renderOmpMail(e, site, s.review_days) });
    for (const e of due.omp_review_overdue || []) plan.push({ e, kind: "omp_review_overdue", to: ompTo, cc: [...salesTo, ...salesCc], mail: renderOverdueMail(e, site, s.review_days) });
  }
  const report = { planned: plan.length, sent: 0, failed: [], skipped_no_recipient: 0, held_for_next_run: 0, items: [] };
  for (const [i, p] of plan.entries()) {
    if (i >= MAX_MAILS_PER_RUN) { report.held_for_next_run++; continue; }
    if (!p.to.length) { report.skipped_no_recipient++; continue; }
    report.items.push({ kind: p.kind, reference: p.e.reference, to: p.to, subject: p.mail.subject });
    if (dryRun) continue;
    try {
      await graphSend(p.to, p.cc.filter((c) => !p.to.includes(c)), p.mail.subject, p.mail.html);
      await rpc("msp_notify_record", { p_engagement_id: p.e.engagement_id, p_kind: p.kind,
        p_recipients: [...p.to, ...p.cc].join(", "), p_subject: p.mail.subject });
      report.sent++;
    } catch (err) {
      report.failed.push({ kind: p.kind, reference: p.e.reference, error: String(err.message || err).slice(0, 200) });
    }
  }
  return report;
}

Deno.serve(async (req) => {
  if (req.method === "GET") return json({ ok: true, fn: "msp-intake-worker", version: WORKER_VERSION,
    secrets: { graph: !!(TENANT_ID && CLIENT_ID && CLIENT_SECRET), sender: !!MAIL_SENDER, service: !!SERVICE_KEY } });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const key = req.headers.get("x-msp-worker-key") || "";
  try {
    if (!(await rpc("msp_worker_key_check", { p_key: key }))) return json({ error: "unauthorised" }, 401);
  } catch (err) {
    return json({ error: "key check failed", detail: String(err.message || err).slice(0, 200) }, 500);
  }
  const body = await req.json().catch(() => ({}));
  const dryRun = body.dry_run === true;
  const mode = ["all", "notify", "pipeline", "preflight"].includes(body.mode) ? body.mode : "all";
  const started = Date.now();
  try {
    if (mode === "preflight") return json({ mode, version: WORKER_VERSION, ...(await preflight(body.scope)) });
    let due = await rpc("msp_notify_due");
    const out = { mode, dry_run: dryRun, version: WORKER_VERSION, drafted: [], notifications: null };
    if ((mode === "all" || mode === "pipeline") && due.settings && due.settings.auto_run && !dryRun) {
      const claimed = await rpc("msp_pipeline_claim", { p_limit: due.settings.batch || 3 });
      for (const item of claimed || []) out.drafted.push(await draftClaimed(item));
      if (out.drafted.length) due = await rpc("msp_notify_due");
    }
    if (mode === "all" || mode === "notify") out.notifications = await notify(due, dryRun);
    out.ms = Date.now() - started;
    return json(out);
  } catch (err) {
    return json({ error: "worker failed", detail: String(err.message || err).slice(0, 500), ms: Date.now() - started }, 500);
  }
});

// ============================== CORE START ==============================
// Pure JavaScript from here to CORE END: no Deno, no network. The Node test
// (msp-forge/test/intake-worker.test.mjs) loads this region on its own.

const WORKER_VERSION = "1.0.0";
const MODEL_USED = "deterministic pipeline.js (no AI), msp-intake-worker " + WORKER_VERSION;

const PIPELINE = (() => {
  const module = { exports: {} };
  /* PIPELINE START: generated from msp-forge/agent/pipeline.js by build.mjs, do not edit here */
// CNC MSP FORGE | AGT-CLS-01..AGT-COM-01 v1.0.1 | Generation pipeline core
// v1.0.1 (08/10/2026): ODMWA_COIDA_ROUTE_CORRECT checks the route against the
// industry's regime instead of demanding COIDA everywhere (mining halted).
// Pure, deterministic stage functions mapping intake variables through the
// Cognitive Kernel's per industry regulatory frame into the structured
// document placeholder draft. The kernel is the only source of legal truth:
// every citation in the output is a verified instrument row reference, every
// number traces to intake data or kernel data, and anything unresolved routes
// to the OMP queue instead of being printed.
//
// At runtime these functions are hosted by the Agent SDK worker; in build
// verification they run against a kernel snapshot and a stored intake, so the
// tested logic is the production logic.

const FLOOR_MONTHS = 12;
const TRIAGE_CONFIDENCE_THRESHOLD = 0.85; // CR-13.7

// ---------------------------------------------------------------- CLASSIFY --
function classify(intake, kernel) {
  const sub = kernel.subindustries.find(s => s.code === intake.subindustry_code);
  const industry = sub ? kernel.industries.find(i => i.id === sub.industry_id) : null;
  const exactMatch = !!(sub && industry && sub.selectable);
  const confidence = exactMatch ? 1.0 : 0.0;
  return {
    schema: 'classify.v1',
    industry_code: industry ? industry.code : intake.industry_code,
    subindustry_code: sub ? sub.code : intake.subindustry_code,
    confidence,
    rationale: exactMatch
      ? `Client selected governed code ${sub.code} (${sub.name}); exact match against the verified taxonomy.`
      : `No selectable taxonomy match for ${intake.subindustry_code}; routed to triage.`,
    triage: confidence < TRIAGE_CONFIDENCE_THRESHOLD,
  };
}

// ------------------------------------------------------------------- FRAME --
function frame(intake, kernel, classification, engagementDate) {
  const industry = kernel.industries.find(i => i.code === classification.industry_code);
  const instruments = [];
  const triggered = [];

  const noiseTransitionDate = '2026-09-06';
  const preTransition = engagementDate < noiseTransitionDate;

  for (const map of kernel.industry_instruments.filter(m => m.industry_id === industry.id)) {
    const inst = kernel.instruments.find(x => x.id === map.instrument_id);
    if (!inst || inst.status !== 'verified') continue;

    // RULE-NOISE-TRANSITION: the operative noise instrument depends on the
    // engagement date; the successor is always disclosed during transition.
    if (inst.short_name === 'NIHL Regulations, 2003' && !preTransition) continue;
    let applicability = map.applicability_note;
    if (inst.short_name === 'NIHL Regulations, 2003' && preTransition) {
      applicability += '. Operative at the date of this Plan; repealed with effect from 06/09/2026 by the Noise Exposure Regulations, 2024, regulation 18. This Plan will be read against the 2024 Regulations from that date.';
    }
    instruments.push({ instrument_id: inst.id, short_name: inst.short_name, full_citation: inst.full_citation, applicability });
  }

  // TRIGGER-NIGHTWORK
  if (intake.shift_night_work) {
    triggered.push({ rule_code: 'TRIGGER-NIGHTWORK', trigger_source: 'shift_night_work' });
  }
  // TRIGGER-PRDP
  if ((intake.jobs || []).some(j => (j.hazard_codes || []).includes('J'))) {
    triggered.push({ rule_code: 'TRIGGER-PRDP', trigger_source: 'job hazard code J' });
  }

  // ROUTE-ODMWA-COIDA, from the kernel rule, keyed on regulatory regime.
  const route = industry.regulatory_regime === 'OHSA'
    ? 'COIDA'
    : 'ODMWA for compensable lung disease, COIDA otherwise';

  return {
    schema: 'frame.v1',
    industry_id: industry.id,
    compensation_route: route,
    instruments,
    triggered_additions: triggered,
  };
}

// ----------------------------------------------------------------- PROFILE --
function parseNumeric(s) {
  if (s === null || s === undefined) return null;
  const m = String(s).replace(',', '.').match(/-?\d+(\.\d+)?/);
  return m ? parseFloat(m[0]) : null;
}

function matchHazardForExposure(text, hazards) {
  const t = text.toLowerCase();
  if (t.includes('noise')) return hazards.find(h => h.code === 'A');
  if (t.includes('silica') || t.includes('dust')) return hazards.find(h => h.code === 'B');
  if (t.includes('vibration')) return hazards.find(h => h.code === 'G');
  if (t.includes('heat') || t.includes('wbgt')) return hazards.find(h => h.code === 'H');
  if (t.includes('fume') || t.includes('chemical') || t.includes('solvent') || t.includes('manganese') || t.includes('lead')) return hazards.find(h => h.code === 'C');
  return null;
}

function likelihoodFor(rating, exceeded) {
  const r = (rating || '').toLowerCase();
  let base = r.includes('high') ? 4 : r.includes('moderate') ? 3 : 2;
  if (exceeded) base = Math.min(5, base + 1);
  return base;
}

function severityFor(hazardCode) {
  // Severity of the unmitigated health outcome per hazard family, a clinical
  // governance default reviewed by the OMP with the draft.
  const high = ['B', 'C', 'E', 'L']; // irreversible disease or fatal event potential
  const mid = ['A', 'G', 'F', 'M', 'J', 'D'];
  if (high.includes(hazardCode)) return 4;
  if (mid.includes(hazardCode)) return 3;
  return 2;
}

function controlAdequacy(job, hazardCode) {
  if (['A', 'B', 'C'].includes(hazardCode)) {
    const fit = (job.rpe_fit_tested || '').toLowerCase();
    if (fit.startsWith('y')) return 'adequate';
    if (job.rpe_issued && !fit.startsWith('y')) return 'partial';
    return job.existing_controls ? 'partial' : 'unknown';
  }
  return job.existing_controls ? 'partial' : 'unknown';
}

function residual(likelihood, severity, adequacy) {
  const score = likelihood * severity;
  const adj = adequacy === 'adequate' ? -3 : adequacy === 'partial' ? 0 : 2;
  const s = score + adj;
  if (s >= 16) return 'critical';
  if (s >= 10) return 'high';
  if (s >= 5) return 'moderate';
  return 'low';
}

function profile(intake, kernel) {
  const exceedances = (intake.exposures || []).map(e => {
    const hazard = matchHazardForExposure(e.hazard_location || '', kernel.hazards);
    const measured = parseNumeric(e.measured_level);
    let assessment = 'unresolved';
    let oel_source = 'unresolved';
    if (hazard && hazard.verification_status === 'verified' && hazard.oel_value !== null && measured !== null) {
      oel_source = 'kernel';
      const oel = parseFloat(hazard.oel_value);
      assessment = measured > oel * 1.5 ? 'significantly_exceeds'
        : measured > oel ? 'exceeds'
        : measured > oel * 0.9 ? 'borderline'
        : 'within';
    } else if (e.stated_oel) {
      oel_source = 'intake_stated';
      const statedOel = parseNumeric(e.stated_oel);
      if (measured !== null && statedOel !== null) {
        assessment = measured > statedOel * 1.5 ? 'significantly_exceeds'
          : measured > statedOel ? 'exceeds'
          : measured > statedOel * 0.9 ? 'borderline'
          : 'within';
      }
    }
    return {
      hazard_location: e.hazard_location,
      measured: `${e.measured_level} ${e.unit || ''}`.trim(),
      hazard_id: hazard ? hazard.id : null,
      hazard_code: hazard ? hazard.code : null,
      kernel_oel: hazard && hazard.verification_status === 'verified' && hazard.oel_value !== null
        ? `${hazard.oel_value} ${hazard.oel_unit}, ${hazard.oel_basis}` : null,
      stated_oel: e.stated_oel || null,
      oel_source,
      assessment,
      date_measured: e.date_measured || null,
    };
  });

  const exceededCodes = new Set(exceedances
    .filter(x => ['exceeds', 'significantly_exceeds', 'borderline'].includes(x.assessment))
    .map(x => x.hazard_code)
    .filter(Boolean));

  const jobs = (intake.jobs || []).map(j => {
    const kernelRole = kernel.roles.find(r =>
      r.title.toLowerCase().replace(/[^a-z]/g, '') === j.title.toLowerCase().replace(/[^a-z]/g, '')
      || j.title.toLowerCase().includes(r.title.toLowerCase().split('/')[0].trim().toLowerCase()));
    const hazards = (j.hazard_codes || []).map(code => {
      const h = kernel.hazards.find(x => x.code === code);
      const kernelMap = kernelRole
        ? kernel.job_hazards.find(m => m.job_role_id === kernelRole.id && m.hazard_id === (h && h.id))
        : null;
      return {
        code,
        hazard_id: h ? h.id : null,
        name: h ? h.name : code,
        exposure_rating: kernelMap ? kernelMap.typical_exposure_rating : 'Moderate',
        rationale: kernelMap
          ? kernelMap.rationale
          : `Client reported hazard ${code} for this category; kernel typical rating pending role mapping, defaulted protectively to Moderate.`,
      };
    });
    const risk_matrix = hazards.map(h => {
      const exceeded = exceededCodes.has(h.code);
      const L = likelihoodFor(h.exposure_rating, exceeded);
      const S = severityFor(h.code);
      const adequacy = controlAdequacy(j, h.code);
      return {
        hazard_code: h.code,
        hazard_name: h.name,
        likelihood: L,
        severity: S,
        exposure_rating: h.exposure_rating,
        control_adequacy: adequacy,
        residual_risk: residual(L, S, adequacy),
        rationale: `${h.rationale}${exceeded ? ' Measured exposure for this hazard family exceeds or borders the applicable limit (see quantified exposure table).' : ''} Control adequacy reflects the reported RPE and control status.`,
      };
    });
    return {
      title: j.title,
      headcount: j.headcount,
      duties: j.duties,
      kernel_role_id: kernelRole ? kernelRole.id : null,
      chronic_flag: !!j.chronic_flag,
      inherent_requirements: {
        physical: j.physical_demands || (kernelRole ? kernelRole.inherent_physical_demands : null),
        sensory_cognitive: j.sensory_cognitive_demands || (kernelRole ? kernelRole.inherent_sensory_cognitive_demands : null),
        statutory: j.statutory_requirement || (kernelRole ? kernelRole.statutory_competency_requirement : null),
      },
      rpe: {
        issued: j.rpe_issued, fit_tested: j.rpe_fit_tested,
        fit_test_interval: j.rpe_fit_test_interval, other_ppe: j.other_ppe,
      },
      hazards,
      risk_matrix,
    };
  });

  return {
    schema: 'profile.v1',
    jobs,
    exceedances,
    chemical_register: intake.chemicals || [],
  };
}

// --------------------------------------------------------------- PRESCRIBE --
function prescribe(intake, kernel, prof, framed) {
  const ompNotes = [];
  const exceededCodes = new Set(prof.exceedances
    .filter(x => ['exceeds', 'significantly_exceeds', 'borderline'].includes(x.assessment))
    .map(x => x.hazard_code).filter(Boolean));

  const programmes = prof.jobs.map(job => {
    const codes = job.hazards.map(h => h.code);
    if (intake.shift_night_work && !codes.includes('K')) codes.push('K');

    const batteries = { baseline: [], periodic: [], exit: [], biological_monitoring: [] };
    for (const code of codes) {
      const hazard = kernel.hazards.find(h => h.code === code);
      if (!hazard) continue;
      for (const p of kernel.protocols.filter(x => x.hazard_id === hazard.id)) {
        const basis = p.legal_basis_id ? kernel.instruments.find(i => i.id === p.legal_basis_id) : null;
        const hazJust = `Exposure justification: ${hazard.name} identified for this category in the OREP${exceededCodes.has(code) ? ', with a measured exceedance recorded' : ''}.`;
        const eeaJust = `Inherent requirement justification (Employment Equity Act 55 of 1998, section 7): ${job.inherent_requirements.physical || 'the physical demands of the role'}; ${job.inherent_requirements.sensory_cognitive || 'the sensory and cognitive demands of the role'}${job.inherent_requirements.statutory ? '; statutory requirement: ' + job.inherent_requirements.statutory : ''}.`;
        const entry = {
          protocol_id: p.id,
          test_name: p.test_name,
          test_type: p.test_type,
          legal_basis: basis ? basis.short_name : null,
          legal_basis_id: basis ? basis.id : null,
          hazard_justification: hazJust,
          eea_s7_justification: eeaJust,
        };
        if (p.test_type === 'biological_monitoring') {
          const unresolved = !p.biological_reference || p.biological_reference.includes('[CONFIRM]');
          if (unresolved) {
            ompNotes.push({
              note_kind: 'unresolved_value',
              detail: `${job.title}: ${p.test_name} is clinically indicated for hazard ${code}, but the biological reference values are not yet kernel verified. The requirement is stated in principle in the draft; the reference values route to the OMP for confirmation and are not printed.`,
            });
          }
          batteries.biological_monitoring.push({ ...entry, reference_status: unresolved ? 'unresolved' : 'kernel_verified' });
          continue;
        }
        if (p.baseline_required) batteries.baseline.push(entry);
        const tightened = exceededCodes.has(code);
        batteries.periodic.push({
          ...entry,
          interval_months: Math.min(p.periodic_interval_months, FLOOR_MONTHS),
          interval_basis: tightened
            ? `Twelve month floor, treated as a minimum and not a ceiling for this category because a measured exceedance is recorded (kernel rule RULE-EXCEEDANCE-TIGHTEN); the OMP may shorten the interval.`
            : basis
              ? `Twelve month floor per house rule, consistent with ${basis.short_name}.`
              : 'Twelve month floor per house rule.',
        });
        if (p.exit_required) batteries.exit.push(entry);
      }
    }

    if (job.chronic_flag) {
      ompNotes.push({
        note_kind: 'clinical_flag',
        detail: `${job.title}: the client flagged, at aggregate category level only, possible chronic conditions with sudden incapacity potential. Enhanced screening (for example HbA1c, hypoglycaemia awareness) is for the Designated OMP to apply on an individual clinical basis; no individual is named anywhere in this engagement.`,
      });
    }

    if (batteries.exit.length === 0) {
      // Exit medicals are never omitted: fall back to a general exit medical.
      batteries.exit.push({
        protocol_id: null,
        test_name: 'Exit medical examination',
        test_type: 'clinical',
        legal_basis: null,
        hazard_justification: 'End of exposure health status record.',
        eea_s7_justification: 'Establishes health status at termination of the exposure period.',
      });
    }

    return {
      job_title: job.title,
      headcount: job.headcount,
      baseline: batteries.baseline,
      periodic: batteries.periodic,
      exit: batteries.exit,
      transfer: [{ test_name: 'Transfer examination', detail: 'On movement to a role with a different exposure profile or capability requirement, the receiving role battery applies.' }],
      return_to_work: [{ test_name: 'Return to work examination', detail: 'Following occupational injury, illness, or prolonged absence, before resumption of duties.' }],
      trigger_exams: [{ test_name: 'Trigger examination', detail: 'On a change in the OREP, new reported symptoms, or a significant workplace incident.' }],
      biological_monitoring: batteries.biological_monitoring,
    };
  });

  return { schema: 'prescribe.v1', programmes, omp_notes: ompNotes };
}

// ----------------------------------------------------------------- COMPOSE --
// The placeholder map: every {variable} the Document Factory resolves when it
// renders the designed pack. Locked template blocks are referenced by anchor
// and inserted verbatim at render time, never paraphrased here.
function compose(intake, kernel, classification, framed, prof, prescribed, engagement) {
  const industry = kernel.industries.find(i => i.code === classification.industry_code);
  const sub = kernel.subindustries.find(s => s.code === classification.subindustry_code);

  const placeholders = {
    reference: engagement.reference,
    version: '1.0',
    date_of_issue: engagement.date_of_issue,
    classification_banner: 'CLASSIFICATION: CLIENT',
    client_name: intake.company_registered_name,
    client_trading_name: intake.company_trading_name,
    client_registration_number: intake.company_registration_number,
    client_address: intake.company_head_office_address,
    sites_covered: (intake.sites || []).map(s => s.name).join('; '),
    workforce_covered: `Approximately ${intake.workforce_total} employees across ${(intake.jobs || []).length} job categories`,
    client_contact: intake.delivery_contact_name,
    industry_name: industry ? industry.name : null,
    subindustry_name: sub ? sub.name : null,
    compensation_route: framed.compensation_route,
    care_net_service_line: 'Occupational Medical Surveillance Programme design and implementation',
    omp_name_placeholder: '[Designated OMP per CR-12.7, inserted at OMP approval]',
    ra_reference: intake.ra_conducted_by
      ? `risk assessment dated ${intake.ra_date || 'as supplied'}, conducted by ${intake.ra_conducted_by}${intake.ra_assessor_accreditation ? ' (' + intake.ra_assessor_accreditation + ')' : ''}, next review ${intake.ra_next_review_date || 'as advised'}`
      : null,
    footer_line: 'Proudly prepared by the Care Net Consultants Team. Your Partner in Workplace Health.',
  };

  const sections = [
    { section_no: '1', heading: 'Introduction and Purpose of this Plan', blocks: [
      { kind: 'paragraph', text: `This Medical Surveillance Plan has been prepared by Care Net Consultants (Pty) Ltd for ${placeholders.client_name}. The Plan sets out the occupational risk exposures associated with the Client's business and workforce, the job categories affected, the medical assessments Care Net will perform in respect of each exposure, and the interval at which each assessment will be repeated. It is reviewed annually, or sooner on any material change to operations, plant, materials, workforce composition, legislation, or guidance.` },
    ]},
    { section_no: '2', heading: 'Business Overview', blocks: [
      { kind: 'paragraph', text: `${placeholders.client_name} operates in ${placeholders.subindustry_name || placeholders.industry_name}, with ${placeholders.workforce_covered.toLowerCase()}, at the following sites: ${placeholders.sites_covered}. ${intake.company_core_industry_freetext}.` },
      { kind: 'questionnaire_context', items: [
        intake.shift_night_work ? 'Employees work rotating shifts or night work; the Code of Good Practice: Arrangement of Working Time medical requirement applies and is included in the WASP.' : 'No employees currently work night shifts or rotating shifts that trigger the Code of Good Practice: Arrangement of Working Time medical requirement. This is revisited if night work is introduced.',
        intake.chronic_flag_present ? `At an aggregate, job category level, the Client flagged the following categories as possibly including employees with chronic conditions that could cause sudden incapacity: ${intake.chronic_flag_categories}. No individual has been identified to Care Net. The Designated OMP will apply enhanced screening where clinically indicated on an individual basis.` : null,
        intake.third_party_cert_required ? `Third party certificate requirement recorded: ${intake.third_party_cert_detail}. Incorporated into the applicable category intervals, which are only ever tightened by such requirements.` : null,
        `POPIA: the Client has confirmed employees will be informed of the programme and their rights before first examination, and has elected ${intake.popia_use_cnc_forms ? "to use Care Net's standard POPIA notice and consent forms" : 'to provide its own POPIA notice and consent forms'}.`,
      ].filter(Boolean) },
    ]},
    { section_no: '3', heading: 'Regulatory Framework Applicable to this Industry', blocks: [
      { kind: 'paragraph', text: `The medical surveillance activities in this Plan support the Client's compliance with the following instruments applicable to ${placeholders.subindustry_name || placeholders.industry_name}. The list reflects the regulatory framework relevant to the exposures identified for this Client and is not an exhaustive statement of all legal obligations. Compensation route: ${placeholders.compensation_route}.` },
      { kind: 'table', table: { name: 'regulatory_frame', rows: framed.instruments.map(i => ({ instrument: i.full_citation, applicability: i.applicability })) } },
    ]},
    { section_no: '4', heading: 'Basis of this Plan and Source of Risk Information', blocks: [
      { kind: 'locked_template', template_anchor: 'TPL-LIA-01' },
      { kind: 'paragraph', text: placeholders.ra_reference ? `Reference risk assessment relied upon for this Plan: ${placeholders.ra_reference}.` : 'The Client has not yet supplied a current risk assessment reference; this Plan is based on the questionnaire disclosures and must be reviewed against the risk assessment when supplied.' },
    ]},
    { section_no: '5', heading: 'Job Descriptions and Occupational Risk Exposure Profile (OREP)', blocks: [
      { kind: 'table', table: { name: 'orep_jobs', rows: prof.jobs.map(j => ({ job_title: j.title, headcount: j.headcount, duties: j.duties, hazards: j.hazards.map(h => `${h.code}: ${h.name}`).join('; '), exposure_rating: j.hazards.map(h => h.exposure_rating).join('; ') })) } },
      { kind: 'table', table: { name: 'quantified_exposures', rows: prof.exceedances.map(x => ({ hazard_location: x.hazard_location, measured: x.measured, oel: x.kernel_oel || (x.stated_oel ? `${x.stated_oel} (client stated, not kernel verified)` : 'not established'), assessment: x.assessment, date: x.date_measured })) } },
      { kind: 'table', table: { name: 'risk_matrix', rows: prof.jobs.flatMap(j => j.risk_matrix.map(r => ({ job_title: j.title, ...r }))) } },
      { kind: 'table', table: { name: 'inherent_requirements', rows: prof.jobs.map(j => ({ job_title: j.title, physical: j.inherent_requirements.physical, sensory_cognitive: j.inherent_requirements.sensory_cognitive, statutory: j.inherent_requirements.statutory })) } },
      { kind: 'table', table: { name: 'chemical_register', rows: prof.chemical_register } },
      ...(prof.exceedances.some(x => ['exceeds', 'significantly_exceeds', 'borderline'].includes(x.assessment))
        ? [{ kind: 'locked_template', template_anchor: 'TPL-CGN-01' }] : []),
    ]},
    { section_no: '6', heading: 'Worker Allocated Surveillance Programme (WASP): Tests and Intervals', blocks: [
      { kind: 'table', table: { name: 'wasp', rows: prescribed.programmes.map(p => ({
          job_title: p.job_title,
          baseline: p.baseline.map(t => t.test_name).join('; '),
          periodic: p.periodic.map(t => `${t.test_name} (${t.interval_months} months)`).join('; '),
          exit: p.exit.map(t => t.test_name).join('; '),
          biological_monitoring: p.biological_monitoring.map(t => `${t.test_name}${t.reference_status === 'unresolved' ? ' (reference values under OMP confirmation)' : ''}`).join('; ') || 'None indicated',
        })) } },
      { kind: 'locked_template', template_anchor: 'TPL-EXA-01' },
      { kind: 'table', table: { name: 'rpe_status', rows: prof.jobs.map(j => ({ job_title: j.title, rpe_issued: j.rpe.issued || 'Not applicable', rpe_fit_tested: j.rpe.fit_tested || 'Not applicable', implication: (j.rpe.issued && !(j.rpe.fit_tested || '').toLowerCase().startsWith('y')) ? 'Until fit testing is confirmed, RPE is not relied upon as a full control; the periodic interval is treated as a minimum, not a ceiling, and fit testing is recommended as a priority.' : 'No interval adjustment.' })) } },
    ]},
    { section_no: '7', heading: 'Roles and Responsibilities', blocks: [
      { kind: 'paragraph', text: 'Responsibilities follow the canonical allocation: Client management provides accurate and current risk information and acts on fitness recommendations; the Client SHE or HR representative maintains the employee to job category register; Care Net Occupational Health Practitioners conduct examinations and maintain confidentiality; the Designated Occupational Medical Practitioner approves this Plan and manages complex fitness determinations; the health and safety representative facilitates communication; employees attend examinations and report new symptoms. The employer is the payer for all examinations under this programme.' },
    ]},
    { section_no: '8', heading: 'Annexure A: Employee to Job Category Register', blocks: [
      { kind: 'paragraph', text: 'The register links each employee to a job category and therefore to the OREP and WASP applicable to them. Only the last four digits of each identity number are recorded, in line with Care Net data minimisation practice under POPIA. The register template is issued with this Plan and maintained by the Client SHE or HR representative.' },
    ]},
    { section_no: '9', heading: 'Confidentiality and Protection of Personal Information', blocks: [
      { kind: 'locked_template', template_anchor: 'TPL-POP-01' },
    ]},
    { section_no: '10', heading: 'Review and Validity of this Plan', blocks: [
      { kind: 'paragraph', text: 'This Plan is reviewed by the Designated Occupational Medical Practitioner at least annually, and immediately upon a change in processes, plant, or materials, the introduction of a new job category, a change in applicable legislation or guidance, or notification of an updated risk assessment. In particular, the noise instrument transition of 6 September 2026 is a scheduled review trigger for this Plan.' },
    ]},
    { section_no: '11', heading: 'Sign Off', blocks: [
      { kind: 'locked_template', template_anchor: 'TPL-SGN-01' },
    ]},
  ];

  return {
    schema: 'compose.v1',
    placeholders,
    sections,
    locked_blocks: ['TPL-LIA-01', 'TPL-POP-01', 'TPL-SGN-01', 'TPL-EXA-01'],
    omp_notes: prescribed.omp_notes,
  };
}

// ---------------------------------------------------------------- VALIDATE --
function validateDraft(composeOut, framed, prescribed, kernel) {
  const checks = [];
  const defects = [];
  const push = (code, pass, detail) => {
    checks.push({ check_code: code, result: pass ? 'pass' : 'fail', detail });
    if (!pass) defects.push({ defect_code: code, blocking: true, detail: { detail } });
  };

  const verifiedIds = new Set(kernel.instruments.filter(i => i.status === 'verified').map(i => i.id));
  push('CITATIONS_RESOLVE_VERIFIED',
    framed.instruments.every(i => verifiedIds.has(i.instrument_id)),
    `${framed.instruments.length} instruments in frame, all must resolve to verified kernel rows`);

  push('INTERVALS_HAVE_BASIS',
    prescribed.programmes.every(p => p.periodic.every(t => t.interval_months <= 12 && t.interval_basis)),
    'every periodic interval at or below the twelve month floor with a stated basis');

  push('EXIT_MEDICALS_PRESENT',
    prescribed.programmes.every(p => p.exit.length > 0),
    'exit assessments present for every category');

  push('DUAL_JUSTIFICATION_PRESENT',
    prescribed.programmes.every(p => [...p.baseline, ...p.periodic].every(t => t.hazard_justification && t.eea_s7_justification)),
    'every test justified against the hazard and against the inherent job requirement');

  const clientText = JSON.stringify({ placeholders: composeOut.placeholders, sections: composeOut.sections });
  push('NO_CONFIRM_ASSUMPTION_TAGS',
    !clientText.includes('[CONFIRM]') && !clientText.includes('ASSUMPTION:'),
    'no CONFIRM or ASSUMPTION tag survives into the client draft');

  push('PROSE_RULE_HOLDS',
    !clientText.includes('—') && !clientText.includes(' - '),
    'no em dash and no spaced hyphen punctuation in client facing prose');

  push('NO_INDIVIDUAL_CLINICAL_DETAIL',
    !/\d{13}/.test(clientText),
    'no identity number pattern in the draft');

  push('LOCKED_BLOCKS_PRESENT_VERBATIM',
    ['TPL-LIA-01', 'TPL-POP-01', 'TPL-SGN-01'].every(a =>
      composeOut.sections.some(s => s.blocks.some(b => b.kind === 'locked_template' && b.template_anchor === a))),
    'liability, POPIA, and sign off locked templates referenced for verbatim insertion');

  // The route must match the industry's regime, the same rule FRAME applies.
  // Until 08/10/2026 this check demanded COIDA for every industry, so every
  // MHSA or dual regime Plan (mining and quarrying) failed its own validation.
  const routeIndustry = kernel.industries.find(i => i.id === framed.industry_id);
  const expectedRoute = routeIndustry && routeIndustry.regulatory_regime === 'OHSA'
    ? 'COIDA'
    : 'ODMWA for compensable lung disease, COIDA otherwise';
  push('ODMWA_COIDA_ROUTE_CORRECT',
    !!routeIndustry && framed.compensation_route === expectedRoute,
    'compensation route matches the regime: OHSA routes to COIDA; MHSA and dual regime route compensable lung disease to ODMWA, COIDA otherwise');

  return {
    schema: 'validate.v1',
    passed: defects.length === 0,
    checks,
    defects,
  };
}

module.exports = { classify, frame, profile, prescribe, compose, validateDraft, TRIAGE_CONFIDENCE_THRESHOLD };
  /* PIPELINE END */
  return module.exports;
})();

function runPipeline(P, kernel, intake, reference, dateOfIssue) {
  const stages = {};
  if (!kernel) {
    return { outcome: "triage", model_used: MODEL_USED, stages,
      defects: [{ stage: "classify", defect_code: "AREA_OF_WORK_UNKNOWN", blocking: true,
        detail: { detail: `Area of work ${intake.subindustry_code || "(blank)"} is not in the framework.` } }],
      summary: { halted_at: "classify", reason: `Area of work ${intake.subindustry_code || "(blank)"} is not in the framework.` } };
  }
  const classification = P.classify(intake, kernel);
  stages.classify = classification;
  if (classification.triage) {
    return { outcome: "triage", model_used: MODEL_USED, stages,
      defects: [{ stage: "classify", defect_code: "CLASSIFY_TRIAGE", blocking: true,
        detail: { detail: classification.rationale, confidence: classification.confidence } }],
      summary: { halted_at: "classify", reason: classification.rationale } };
  }
  const framed = P.frame(intake, kernel, classification, dateOfIssue);
  stages.frame = framed;
  const prof = P.profile(intake, kernel);
  stages.profile = prof;
  const prescribed = P.prescribe(intake, kernel, prof, framed);
  stages.prescribe = prescribed;
  const composed = P.compose(intake, kernel, classification, framed, prof, prescribed, { reference, date_of_issue: dateOfIssue });
  stages.compose = composed;
  const validation = P.validateDraft(composed, framed, prescribed, kernel);
  stages.validate = validation;
  const summary = {
    industry: classification.industry_code, subindustry: classification.subindustry_code,
    instruments: framed.instruments.length,
    triggers: framed.triggered_additions.map((t) => t.rule_code),
    jobs: prof.jobs.length,
    risk_rows: prof.jobs.reduce((a, j) => a + j.risk_matrix.length, 0),
    exposures_at_or_above_limit: prof.exceedances.filter((x) => ["exceeds", "significantly_exceeds", "borderline"].includes(x.assessment)).length,
    programmes: prescribed.programmes.length,
    omp_notes: (composed.omp_notes || prescribed.omp_notes || []).length,
    checks_passed: validation.checks.filter((c) => c.result === "pass").length,
    checks_total: validation.checks.length,
    kernel_release: kernel.kernel_release || null,
  };
  if (!validation.passed) {
    return { outcome: "triage", model_used: MODEL_USED, stages,
      defects: validation.defects.map((d) => ({ stage: "validate", ...d })),
      summary: { ...summary, halted_at: "validate" } };
  }
  return { outcome: "queued", model_used: MODEL_USED, stages, defects: [], summary };
}

// A fictitious intake for one area of work, built from the kernel's own roles,
// used only by preflight. Nothing here is ever written to the database.
function preflightIntake(kernel, subCode) {
  const sub = kernel.subindustries.find((s) => s.code === subCode);
  const industry = sub ? kernel.industries.find((i) => i.id === sub.industry_id) : null;
  const roles = sub ? kernel.roles.filter((r) => r.subindustry_id === sub.id).slice(0, 3) : [];
  const codeOf = (id) => (kernel.hazards.find((h) => h.id === id) || {}).code;
  const jobs = (roles.length ? roles : [{ id: null, title: "General Worker", duties_summary: "General duties" }]).map((r) => {
    const codes = kernel.job_hazards.filter((m) => m.job_role_id === r.id).map((m) => codeOf(m.hazard_id)).filter(Boolean);
    return { title: r.title, duties: r.duties_summary, headcount: 10, hazard_codes: codes.length ? codes : ["A"],
      rpe_issued: "None", rpe_fit_tested: "Not applicable", rpe_fit_test_interval: null, other_ppe: null,
      existing_controls: "Standard controls", physical_demands: null, sensory_cognitive_demands: null,
      statutory_requirement: null, chronic_flag: false };
  });
  return {
    schema_version: "intake.v1", validation_status: "valid", triage_reason: null,
    industry_code: industry ? industry.code : null, subindustry_code: subCode, industry_other_detail: null,
    company_registered_name: "TEST Preflight Company (Pty) Ltd", company_trading_name: "TEST Preflight",
    company_registration_number: "2020/000000/07", company_vat_number: null,
    company_head_office_address: "1 Test Street, Midrand, 1685", company_years_operating: 5,
    company_core_industry_freetext: "Fictitious company used to check the drafting pipeline.",
    workforce_total: jobs.length * 10, employees_under_18: false, pregnancy_exposed_roles: false,
    jobs, sites: [{ name: "TEST Site", address: "1 Test Street, Midrand, 1685", activity: "Operations", headcount: jobs.length * 10 }],
    exposures: [], chemicals: [],
    shift_night_work: false, shift_pattern_detail: null, nightwork_medical_current: false, nightwork_medical_interval: null,
    ra_exists: true, ra_date: "2026-03-01", ra_conducted_by: "TEST Assessor", ra_assessor_accreditation: null, ra_next_review_date: "2027-03-01",
    hygiene_results_exist: false, hygiene_date: null, hygiene_conducted_by: null,
    current_medicals_exist: false, current_tests_detail: null, current_provider: null, records_format: null,
    coida_registered: true, coida_class_tariff_number: null, coida_claims_3yr: false, injuries_3yr: false,
    enforcement_notice_3yr: false, enforcement_notice_detail: null, incident_history_detail: null,
    third_party_cert_required: false, third_party_cert_detail: null, certificate_format_preference: null,
    hs_committee_present: true, outstanding_referrals: false, modified_duties_current: false,
    process_change_since_ra: false, process_change_detail: null, chronic_flag_present: false, chronic_flag_categories: null,
    hazard_additional_detail: null, employees_informed_before_exam: true,
    information_officer_name: "TEST Information Officer", information_officer_contact: "it@carenetconsultants.co.za",
    delivery_contact_name: "TEST Contact", delivery_contact_email: "it@carenetconsultants.co.za",
    declarant_full_name: "TEST Declarant", declarant_position: "SHE Officer", declarant_company: "TEST Preflight Company (Pty) Ltd",
    declaration_date: "2026-10-08", consent_processing: true, consent_marketing: false, popia_use_cnc_forms: true,
    consent_wording_version: "popia.v1", docuseal_submission_id: "PREFLIGHT", brand_colour_hex: null,
  };
}

function emails(v) {
  return String(v || "").split(/[,;\s]+/).map((x) => x.trim().toLowerCase())
    .filter((x) => /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/.test(x));
}

function siteBase(v) {
  const s = String(v || "").trim();
  return /^https:\/\//.test(s) ? s.replace(/\/$/, "") : "https://medicalsurveillance.carenetconsultants.co.za";
}

function esc(v) {
  return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function sast(iso) {
  if (!iso) return "";
  return new Intl.DateTimeFormat("en-GB", { timeZone: "Africa/Johannesburg", day: "2-digit", month: "2-digit",
    year: "numeric", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(iso)) + " SAST";
}

function shell(heading, inner) {
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F2F2F2;padding:20px 0"><tr><td align="center">`
    + `<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;font-family:Arial,Helvetica,sans-serif;color:#1E1E1E;font-size:14px;line-height:1.5">`
    + `<tr><td style="height:5px;background:#ED1B24;line-height:5px;font-size:0">&nbsp;</td></tr>`
    + `<tr><td style="padding:24px 28px 8px 28px"><p style="margin:0;font-size:11px;letter-spacing:1px;color:#ED1B24;font-weight:bold">MEDICAL SURVEILLANCE PLAN</p>`
    + `<h1 style="margin:6px 0 0 0;font-size:19px;font-family:Montserrat,Arial,sans-serif">${esc(heading)}</h1></td></tr>`
    + `<tr><td style="padding:12px 28px 24px 28px">${inner}</td></tr>`
    + `<tr><td style="padding:16px 28px;background:#F2F2F2;border-top:1px solid #E2E2E2;font-size:11px;color:#787878">`
    + `Sent automatically by the Medical Surveillance Plan service. Care Net Consultants (Pty) Ltd. Internal notice: company and contact details only, no clinical information.`
    + `</td></tr></table></td></tr></table>`;
}

function rows(pairs) {
  return `<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;margin:8px 0 14px 0">`
    + pairs.filter(([, v]) => v !== null && v !== undefined && v !== "").map(([k, v]) =>
      `<tr><td style="padding:6px 10px 6px 0;color:#555;width:170px;vertical-align:top;border-bottom:1px solid #EEE">${esc(k)}</td>`
      + `<td style="padding:6px 0;vertical-align:top;border-bottom:1px solid #EEE">${v}</td></tr>`).join("")
    + `</table>`;
}

function button(href, label) {
  return `<p style="margin:16px 0 4px 0"><a href="${esc(href)}" style="display:inline-block;background:#ED1B24;color:#ffffff;text-decoration:none;padding:11px 22px;font-weight:bold;border-radius:5px">${esc(label)}</a></p>`;
}

function companyLine(e) {
  return esc(e.company) + (e.trading_name && e.trading_name !== e.company ? ` <span style="color:#777">(trading as ${esc(e.trading_name)})</span>` : "");
}

function contactLine(e) {
  const parts = [esc(e.contact_name), e.contact_position ? esc(e.contact_position) : null,
    e.contact_email ? `<a href="mailto:${esc(e.contact_email)}">${esc(e.contact_email)}</a>` : null].filter(Boolean);
  return parts.join(", ");
}

function renderIntakeMail(e, site) {
  const clean = e.validation_status !== "triage";
  const status = clean
    ? "Clean. Drafting starts automatically within five minutes."
    : `Needs a person (triage)${e.triage_reason ? ": " + esc(e.triage_reason) : "."}`;
  const inner = `<p style="margin:0 0 6px 0">A company has finished the Medical Surveillance Plan assessment.</p>`
    + rows([["Reference", `<strong>${esc(e.reference)}</strong>`], ["Company", companyLine(e)],
      ["Industry", esc(e.industry_name || e.industry_code)], ["Area of work", esc(e.subindustry_name || e.subindustry_code)],
      ["People covered", esc(e.workforce_total)], ["Job categories", esc(e.job_categories)], ["Sites", esc(e.sites)],
      ["Contact", contactLine(e)], ["Received", esc(sast(e.created_at))], ["Status", status]])
    + `<p style="margin:0">${clean
      ? "You will get a second notice when the Plan is drafted, or if drafting needs a person."
      : "Nothing is drafted until a person resolves the triage reason. Open the submission in the staff tool."}</p>`
    + button(`${site}/review.html`, "Open the staff tool");
  return { subject: `New Plan submission: ${e.reference}, ${e.company}${clean ? "" : " (triage)"}`,
    html: shell("New submission received", inner) };
}

function describeDefect(d) {
  const detail = d && d.detail && (d.detail.detail || d.detail.error) ? `: ${d.detail.detail || d.detail.error}` : "";
  return `${esc(d.code || d.defect_code)}${esc(detail)}`;
}

function renderResultMail(e, site, ompConfigured, reviewDays) {
  if (e.status === "omp_queue") {
    const clock = ompConfigured
      ? `The reviewing practitioner has been asked to review it within ${esc(reviewDays)} days.`
      : "No reviewing practitioner is named yet, so the review clock has not started. The Plan waits in the queue until one is.";
    const inner = `<p style="margin:0 0 6px 0">The Plan for this submission has been drafted and passed every automatic check. It is waiting for practitioner review.</p>`
      + rows([["Reference", `<strong>${esc(e.reference)}</strong>`], ["Company", companyLine(e)],
        ["Industry", esc(e.industry_name || e.industry_code)], ["Area of work", esc(e.subindustry_name || e.subindustry_code)],
        ["People covered", esc(e.workforce_total)], ["Contact", contactLine(e)], ["Practitioner review", clock]])
      + `<p style="margin:0">Nothing reaches the client until a registered Occupational Medical Practitioner has reviewed and signed the Plan.</p>`
      + button(`${site}/review.html`, "Open the review queue");
    return { subject: `Plan drafted, waiting for practitioner review: ${e.reference}, ${e.company}`,
      html: shell("Plan drafted", inner) };
  }
  const defects = (e.defects || []).map((d) => `<li style="margin:0 0 4px 0">${describeDefect(d)}</li>`).join("");
  const inner = `<p style="margin:0 0 6px 0">Drafting stopped for this submission and needs a person before the Plan can go to the practitioner.</p>`
    + rows([["Reference", `<strong>${esc(e.reference)}</strong>`], ["Company", companyLine(e)],
      ["Industry", esc(e.industry_name || e.industry_code)], ["Area of work", esc(e.subindustry_name || e.subindustry_code)],
      ["Contact", contactLine(e)]])
    + `<p style="margin:0 0 4px 0;font-weight:bold">Why it stopped</p><ul style="margin:0 0 12px 18px;padding:0">${defects || "<li>No reason was recorded. IT will look.</li>"}</ul>`
    + `<p style="margin:0">Once the cause is fixed, a forge_admin can send it back for drafting with msp_pipeline_rerun, and it is drafted again within five minutes.</p>`
    + button(`${site}/review.html`, "Open the staff tool");
  return { subject: `Plan drafting needs a person: ${e.reference}, ${e.company}`, html: shell("Drafting stopped", inner) };
}

function renderOmpMail(e, site, reviewDays) {
  const inner = `<p style="margin:0 0 6px 0">A Medical Surveillance Plan is ready for your review and signature.</p>`
    + rows([["Reference", `<strong>${esc(e.reference)}</strong>`], ["Company", companyLine(e)],
      ["Industry", esc(e.industry_name || e.industry_code)], ["Area of work", esc(e.subindustry_name || e.subindustry_code)],
      ["People covered", esc(e.workforce_total)], ["Review window", `${esc(reviewDays)} days from this notice`]])
    + `<p style="margin:0">The Plan sets out the programme per job category: hazards, tests, intervals and their legal basis. It holds no individual clinical results. Sign in with your practitioner account to approve, amend or return it.</p>`
    + button(`${site}/review.html`, "Review the Plan");
  return { subject: `Plan ready for your review: ${e.reference}, ${e.company}`, html: shell("Plan ready for review", inner) };
}

function renderOverdueMail(e, site, reviewDays) {
  const inner = `<p style="margin:0 0 6px 0">This Plan has waited longer than the ${esc(reviewDays)} day review window.</p>`
    + rows([["Reference", `<strong>${esc(e.reference)}</strong>`], ["Company", companyLine(e)],
      ["Sent for review", esc(sast(e.omp_requested_at))], ["Contact", contactLine(e)]])
    + `<p style="margin:0">This reminder is sent once. Sales are copied so the client can be kept informed.</p>`
    + button(`${site}/review.html`, "Review the Plan");
  return { subject: `Review overdue: ${e.reference}, ${e.company}`, html: shell("Review overdue", inner) };
}
// =============================== CORE END ===============================
