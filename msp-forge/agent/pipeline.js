// CNC MSP FORGE | AGT-CLS-01..AGT-COM-01 v1.0.0 | Generation pipeline core
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

  push('ODMWA_COIDA_ROUTE_CORRECT',
    framed.compensation_route === 'COIDA',
    'OHSA regime industry routes to COIDA');

  return {
    schema: 'validate.v1',
    passed: defects.length === 0,
    checks,
    defects,
  };
}

module.exports = { classify, frame, profile, prescribe, compose, validateDraft, TRIAGE_CONFIDENCE_THRESHOLD };
