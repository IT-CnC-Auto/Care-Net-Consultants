#!/usr/bin/env node
// Bee-Inspect | the offline kernel bundle for the phone app.
//
// Reads the Care Net Cognitive Kernel as it stands in this repository and
// writes the bundle the app reads offline:
//
//   apps/mobile/assets/kernel/kernel-bundle.json
//   supabase/seed/bee_inspect_kernel_templates.sql   (the same templates for the
//                                                      server, loaded by the SQL
//                                                      checks; never applied here)
//
// Sources (nothing is typed in by hand except the place type table below,
// whose every rule points at kernel codes):
//   supabase/migrations 001 to 064, replayed into a scratch database:
//     msp_industry, msp_subindustry (hsf_public_subindustry), hsf_trigger
//     (hsf_public_trigger), hsf_department, hsf_section, hsf_element,
//     hsf_element_industry (the SPEC B7 overlays and their "switched on"
//     triggers), hsf_element_instrument with msp_legal_instrument,
//     hsf_appointment_type, msp_kernel_version (the kernel release).
//   hsf/guidance/guidance.json (what to submit, common gaps, suggested
//     department, per element).
//   vercel/hsf/samples/*.js (one fictitious sample company per industry, with
//     the triggers a completed assessment for that operation raised).
//   vercel/hsf/pricing.js (the industry codes the File site prices).
//   hsf/sample-file/instruments.json (instrument status, cross checked).
//
// Every item in the bundle carries `src`, the source id it came from (for
// example "hsf_element:HSF-F-02#what_to_submit[0]"). The app tests check that
// every source id resolves in the repository and that nothing is invented.
// Where the kernel holds no value (a legal interval, a retention period) the
// bundle says so and the app shows "Set by your competent person".
//
// Run from msp-forge/ (needs the local Postgres of test/sql/replay.sh):
//   node apps/mobile/scripts/build-kernel-bundle.mjs            fresh replay into cnc_kernel_bundle, then write
//   node apps/mobile/scripts/build-kernel-bundle.mjs --db cnc_test   reuse a replayed database
//   node apps/mobile/scripts/build-kernel-bundle.mjs --check    rebuild and compare, write nothing (exit 1 on drift)
// Postgres: host /tmp, port 55432 (PGHOST, PGPORT override), user postgres.

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const OUT_JSON = path.join(ROOT, 'apps', 'mobile', 'assets', 'kernel', 'kernel-bundle.json');
const OUT_SQL = path.join(ROOT, 'supabase', 'seed', 'bee_inspect_kernel_templates.sql');
const MIGRATIONS = path.join(ROOT, 'supabase', 'migrations');
const BUNDLE_SCHEMA = 'bee-inspect.kernel-bundle.v1';
const LAST_KERNEL_MIGRATION = 64;

const args = process.argv.slice(2);
const CHECK = args.includes('--check');
const dbArg = args.indexOf('--db');
const DB = dbArg >= 0 ? args[dbArg + 1] : 'cnc_kernel_bundle';
const PGHOST = process.env.PGHOST || '/tmp';
const PGPORT = process.env.PGPORT || '55432';

function psql(db, sql, input) {
  return execFileSync('psql', ['-h', PGHOST, '-p', PGPORT, '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1', '-q', '-At', ...(sql ? ['-c', sql] : ['-f', '-'])], {
    input,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function replay() {
  process.stderr.write(`Replaying migrations 001 to ${String(LAST_KERNEL_MIGRATION).padStart(3, '0')} into ${DB} ...\n`);
  psql('postgres', `drop database if exists ${DB}`);
  psql('postgres', `create database ${DB}`);
  psql(DB, null, readFileSync(path.join(ROOT, 'test', 'sql', '00_supabase_stub.sql'), 'utf8'));
  for (const f of readdirSync(MIGRATIONS).filter((n) => /^\d{3}_.*\.sql$/.test(n)).sort()) {
    if (Number(f.slice(0, 3)) > LAST_KERNEL_MIGRATION) continue;
    // pgvector is not installed locally; the precedent embedding column becomes real[] (as replay.sh does).
    const sql = readFileSync(path.join(MIGRATIONS, f), 'utf8').replace(/extensions\.vector\(\d*\)/g, 'real[]');
    psql(DB, null, sql);
  }
}

function q(sql) {
  const out = psql(DB, `select coalesce(json_agg(t), '[]'::json) from (${sql}) t`).trim();
  return JSON.parse(out || '[]');
}

// ---------------------------------------------------------------------------
// House rules for visible text (hsf/BUILD-CONTRACT.md 7 and 15; the same
// checks as hsf/build_samples.py): no section, regulation, annexure or gazette
// numbers other than OHS Act 16(1), 16(2) and 37(2); no internal system names;
// no dash punctuation; never "compliant" or "guarantee".
const ALLOWED_NUMBERS = /\b(?:[Ss]ection |s)?(?:16\((?:1|2)\)|37\(2\))/g;
const NUMBERED = /\b(?:[Ss]ections? \d|[Rr]egulations? \d|[Aa]nnexure \d|GNR? ?\d|GN R|GG \d|R\.? ?\d{3})/;
const INTERNAL = /\bFORGE\b|sharepoint|\bCursor\b|\b(?:msp|hsf|bi)_[a-z_]+|\bRULE-[A-Z]|\bsandbox\b|,\s*,/i;
const BANNED = /\bcompliant\b|\bguarantee/i;
const DASHES = /[‐-―]|\s-\s/;
const BASIS_WORDS = [
  ['Food Premises Hygiene Regulations, R638 of 2018', 'Food Premises Hygiene Regulations, 2018'],
  ['EEA section 7', 'EEA, medical testing provision'],
  ['Construction Regulations, 2014, Annexure 3', 'Construction Regulations, 2014, medical certificate of fitness provision'],
];
// Medical surveillance stays with the occupational health practitioner and
// MyClinicOnline (prompt section 3.4): no Section E element and no element
// about fitness examinations becomes an inspection line.
const CLINICAL = /\b(?:medical|fitness|examination|examinations|immunisation|surveillance|clinical|cholinesterase|audiometr|diagnos)/i;

function plain(text, where) {
  let t = text;
  for (const [a, b] of BASIS_WORDS) t = t.split(a).join(b);
  const probe = t.replace(ALLOWED_NUMBERS, '');
  const problems = [];
  if (NUMBERED.test(probe)) problems.push('a provision number');
  if (INTERNAL.test(t)) problems.push('an internal name');
  if (BANNED.test(t)) problems.push('a banned word');
  if (DASHES.test(t)) problems.push('dash punctuation');
  if (problems.length) throw new Error(`House rule broken (${problems.join(', ')}) in ${where}: ${t}`);
  return t;
}

// Deterministic ids (UUID shaped, version 5 style) so the app, the seed SQL and
// the server agree on every template and item id without a lookup.
function uid(name) {
  const h = createHash('sha256').update('bee-inspect-kernel:' + name).digest('hex');
  const variant = ((parseInt(h[16], 16) & 0x3) | 0x8).toString(16);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-5${h.slice(13, 16)}-${variant}${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

// ---------------------------------------------------------------------------
// Place types. The Director's list (27/09/2026). Which types the app offers for
// an industry follows the kernel: an industry code, a subindustry code, or a
// trigger the industry's overlay or its sample assessment raises. Every code
// named here is checked against the kernel below; `why` is shown to people.
const PLACE_TYPES = [
  { code: 'site', label: 'Site', icon: 'map-marker-radius-outline', root: true, rule: { always: true }, why: 'Every industry' },
  { code: 'office', label: 'Office', icon: 'office-building-outline', root: true, rule: { always: true }, why: 'Every industry' },
  { code: 'branch', label: 'Branch', icon: 'store-marker-outline', root: true, rule: { always: true }, why: 'Every industry' },
  { code: 'factory_plant', label: 'Factory or plant', icon: 'factory', root: true, rule: { industries: ['MANU', 'UTIL', 'PETRO'], triggers: ['T-MACHINERY'] }, why: 'Manufacturing, utilities and petrochemical industries, and wherever machinery needs guarding' },
  { code: 'warehouse', label: 'Warehouse', icon: 'warehouse', root: true, rule: { triggers: ['T-STACKING'], subindustries: ['TRANS-WARE', 'RET-WHOLE'] }, why: 'Where goods are stacked and stored' },
  { code: 'workshop', label: 'Workshop', icon: 'hammer-wrench', root: true, rule: { triggers: ['T-MACHINERY', 'T-HOTWORK', 'T-MOBILEPLANT'] }, why: 'Where machinery, hot work or mobile plant is maintained' },
  { code: 'farm', label: 'Farm', icon: 'barn', root: true, rule: { industries: ['AGRI'] }, why: 'Agriculture and forestry' },
  { code: 'mine_section', label: 'Mine or quarry section', icon: 'pickaxe', root: true, rule: { industries: ['MINING'], triggers: ['T-MINING'] }, why: 'Mines and quarries under the Mine Health and Safety Act' },
  { code: 'school_campus', label: 'School campus', icon: 'school-outline', root: true, rule: { industries: ['EDU'] }, why: 'Education' },
  { code: 'clinic_lab', label: 'Clinic or laboratory', icon: 'flask-outline', root: true, rule: { industries: ['HEALTH', 'EDU'] }, why: 'Healthcare and laboratories, and education laboratories (Education overlay)' },
  { code: 'retail_store', label: 'Retail store', icon: 'storefront-outline', root: true, rule: { industries: ['RETAIL'], subindustries: ['PETRO-RETAIL'] }, why: 'Retail, and service stations and convenience stores' },
  { code: 'depot', label: 'Depot', icon: 'truck-cargo-container', root: true, rule: { industries: ['TRANS', 'GOV', 'WASTE'], subindustries: ['PETRO-BULK', 'PETRO-GAS'] }, why: 'Transport, municipal, waste and fuel depots' },
  { code: 'vehicle_fleet', label: 'Vehicle or fleet', icon: 'truck-outline', root: true, rule: { triggers: ['T-PRDP', 'T-MOBILEPLANT'] }, why: 'Where drivers need a professional driving permit or mobile plant is used' },
  { code: 'construction_project', label: 'Construction project', icon: 'crane', root: true, rule: { triggers: ['T-CONSTR'] }, why: 'Where construction work is carried on' },
  { code: 'department', label: 'Department', icon: 'account-group-outline', root: false, rule: { always: true }, why: 'Every industry' },
  { code: 'building_block', label: 'Building or block', icon: 'office-building', root: false, rule: { always: true }, why: 'Every industry' },
  { code: 'floor', label: 'Floor', icon: 'layers-outline', root: false, rule: { always: true }, why: 'Every industry' },
  { code: 'room_area', label: 'Room or area', icon: 'door', root: false, rule: { always: true }, why: 'Every industry' },
];
const UNIT_TYPES = ['workshop', 'warehouse', 'mine_section', 'clinic_lab', 'vehicle_fleet', 'construction_project', 'factory_plant', 'retail_store'];
const CONTAINERS = ['department', 'building_block', 'floor', 'room_area'];
const CHILDREN = {
  site: [...CONTAINERS, ...UNIT_TYPES],
  office: ['department', 'building_block', 'floor', 'room_area', 'vehicle_fleet'],
  branch: [...CONTAINERS, ...UNIT_TYPES],
  factory_plant: [...CONTAINERS, 'workshop', 'warehouse', 'vehicle_fleet', 'clinic_lab'],
  warehouse: ['department', 'floor', 'room_area', 'vehicle_fleet'],
  workshop: ['department', 'room_area', 'vehicle_fleet'],
  farm: [...CONTAINERS, 'workshop', 'warehouse', 'vehicle_fleet', 'factory_plant'],
  mine_section: [...CONTAINERS, 'mine_section', 'workshop', 'warehouse', 'vehicle_fleet', 'factory_plant', 'clinic_lab'],
  school_campus: [...CONTAINERS, 'clinic_lab', 'workshop', 'vehicle_fleet'],
  clinic_lab: ['department', 'floor', 'room_area'],
  retail_store: [...CONTAINERS, 'warehouse', 'vehicle_fleet'],
  depot: [...CONTAINERS, 'workshop', 'warehouse', 'vehicle_fleet'],
  vehicle_fleet: ['vehicle_fleet'],
  construction_project: [...CONTAINERS, 'workshop', 'vehicle_fleet'],
  department: ['department', 'building_block', 'floor', 'room_area', 'workshop', 'warehouse', 'clinic_lab', 'vehicle_fleet'],
  building_block: ['floor', 'room_area', 'department', 'workshop', 'clinic_lab', 'warehouse'],
  floor: ['room_area', 'department'],
  room_area: [],
};
const PLACE_MAX_DEPTH = 8;

// Template category (what an inspector's competence scope must cover to sign),
// from migration 060's comment on bi_template: HSF-F-01 scaffolds, F-02 ladders,
// F-03 lifting, F-04 and F-05 electrical, F-06 fire, F-11 PPE, F-12 chemicals.
const REGISTER_CATEGORY = { 'HSF-F-01': 'scaffolds', 'HSF-F-02': 'ladders', 'HSF-F-03': 'lifting', 'HSF-F-04': 'electrical', 'HSF-F-05': 'electrical', 'HSF-F-06': 'fire', 'HSF-F-11': 'ppe', 'HSF-F-12': 'chemicals' };
const INDUSTRY_CATEGORY = { CONSTR: 'construction', MANU: 'manufacturing', MINING: 'mining', AGRI: 'agriculture', HEALTH: 'clinics' };

// Review intervals the element library holds as a cadence; "statutory" and
// "annual" wait for a verified legal interval, so the app shows "Set by your
// competent person" for them (guidance: the File library shows a legal
// interval only once Care Net has verified one).
const CADENCE = { daily: 'Daily', monthly: 'Monthly', before_use: 'Before each use', on_change: 'When anything changes', per_event: 'Each time it is used', per_project: 'Each project', on_expiry: 'Before it expires' };
// Retention classes of SPEC B6.1.4 in plain words; no period is invented.
const RETENTION = {
  LIFE: 'For the life of the File; the period after that is set by your competent person',
  INST: 'As the legal instrument sets it, still being confirmed; until then set by your competent person',
  'HSF-5': 'Set by your competent person',
};

// ---------------------------------------------------------------------------

function readSamples() {
  const dir = path.join(ROOT, 'vercel', 'hsf', 'samples');
  const out = {};
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.js')).sort()) {
    const text = readFileSync(path.join(dir, f), 'utf8');
    const json = text.slice(text.indexOf('=') + 1).trim().replace(/;\s*$/, '');
    const s = JSON.parse(json);
    out[s.code] = { file: `vercel/hsf/samples/${f}`, slug: s.slug, company: s.company, scope: s.scope, sites: s.sites, headcount: s.headcount, regime: s.regime, triggers: s.triggers };
  }
  return out;
}

function pricingCodes() {
  const text = readFileSync(path.join(ROOT, 'vercel', 'hsf', 'pricing.js'), 'utf8');
  return [...text.matchAll(/"code":\s*"([A-Z]+)"/g)].map((m) => m[1]);
}

function build() {
  const guidance = JSON.parse(readFileSync(path.join(ROOT, 'hsf', 'guidance', 'guidance.json'), 'utf8'));
  const instrumentsJson = JSON.parse(readFileSync(path.join(ROOT, 'hsf', 'sample-file', 'instruments.json'), 'utf8'));
  const samples = readSamples();
  const priced = pricingCodes();

  const [kv] = q(`select semver, change_summary, kernel_counts from msp_kernel_version
                   order by string_to_array(semver, '.')::int[] desc limit 1`);
  // The release date as the release itself states it ("... release 16/09/2026 ..."); the
  // table's released_on is only the day the migration ran, so it is not used.
  const rel = /release (\d{2})\/(\d{2})\/(\d{4})/.exec(kv.change_summary);
  kv.released_on = rel ? `${rel[3]}-${rel[2]}-${rel[1]}` : null;
  const industries = q(`select code, name, sic_reference, regulatory_regime as regime from msp_industry order by code`);
  const subs = q(`select code, name, industry_code, selectable from hsf_public_subindustry order by industry_code, name`);
  const triggers = q(`select code, description from hsf_public_trigger order by code`);
  const departments = q(`select code, name from hsf_department order by ordinal`);
  const sections = q(`select code, name from hsf_section order by ordinal`);
  const elements = q(`select e.code, e.section_code, e.name, e.evidence_type, e.review_interval, e.trigger_code, e.retention_rule,
                             e.responsible_role, a.name as responsible_appointment, e.basis_state, e.universal
                        from hsf_element e left join hsf_appointment_type a on a.code = e.responsible_appointment
                       where e.status = 'active' order by e.code`);
  const overlays = q(`select e.code as element_code, i.code as industry_code, s.code as subindustry_code, ei.applicability, ei.overlay_note
                        from hsf_element_industry ei join hsf_element e on e.id = ei.element_id
                        join msp_industry i on i.id = ei.industry_id left join msp_subindustry s on s.id = ei.subindustry_id
                       order by i.code, e.code`);
  const basis = q(`select e.code as element_code, li.short_name, li.status
                     from hsf_element_instrument ei join hsf_element e on e.id = ei.element_id
                     join msp_legal_instrument li on li.id = ei.instrument_id order by e.code, li.short_name`);

  if (industries.length !== 17) throw new Error(`The kernel holds ${industries.length} industries, not 17.`);
  const industryCodes = new Set(industries.map((i) => i.code));
  for (const c of priced) if (!industryCodes.has(c)) throw new Error(`pricing.js prices ${c}, which the kernel does not hold.`);
  for (const c of industryCodes) if (!samples[c]) throw new Error(`No sample company for ${c} in vercel/hsf/samples.`);
  const triggerCodes = new Set(triggers.map((t) => t.code));
  const subCodes = new Set(subs.map((s) => s.code));
  for (const pt of PLACE_TYPES) {
    for (const c of pt.rule.industries ?? []) if (!industryCodes.has(c)) throw new Error(`Place type ${pt.code} names unknown industry ${c}`);
    for (const c of pt.rule.triggers ?? []) if (!triggerCodes.has(c)) throw new Error(`Place type ${pt.code} names unknown trigger ${c}`);
    for (const c of pt.rule.subindustries ?? []) if (!subCodes.has(c)) throw new Error(`Place type ${pt.code} names unknown subindustry ${c}`);
    if (!CHILDREN[pt.code]) throw new Error(`No child rule for ${pt.code}`);
  }

  const elementBy = new Map(elements.map((e) => [e.code, e]));
  const sectionName = new Map(sections.map((s) => [s.code, s.name]));
  const instrumentStatus = new Map(instrumentsJson.instruments.map((i) => [i.short_name, i.status]));
  const basisBy = new Map();
  for (const b of basis) {
    if (!b.element_code.startsWith('HSF-F-')) continue; // only the registers show a basis
    if (!basisBy.has(b.element_code)) basisBy.set(b.element_code, []);
    // Cross check with the published instrument export where it lists the instrument.
    const exported = instrumentStatus.get(b.short_name);
    if (exported && exported !== b.status) throw new Error(`Instrument status differs for ${b.short_name}: ${b.status} against ${exported}`);
    basisBy.get(b.element_code).push({ name: plain(b.short_name, `instrument of ${b.element_code}`), status: b.status, src: `msp_legal_instrument:${b.short_name}` });
  }

  // Triggers per industry: those the overlay switches on (SPEC B7, parsed from
  // the overlay note "through T-X, T-Y") and those the industry's sample
  // assessment raised.
  const overlayTriggers = {};
  const overlayAdditions = {};
  const overlaySwitched = {};
  for (const o of overlays) {
    overlayTriggers[o.industry_code] ??= new Set();
    overlayAdditions[o.industry_code] ??= [];
    overlaySwitched[o.industry_code] ??= [];
    for (const m of o.overlay_note.matchAll(/T-[A-Z-]+[A-Z]/g)) overlayTriggers[o.industry_code].add(m[0]);
    if (o.element_code.startsWith('HSF-OV-')) overlayAdditions[o.industry_code].push(o);
    else overlaySwitched[o.industry_code].push(o);
  }

  const guidanceFor = (code) => guidance.elements[code] ?? null;
  const intervalOf = (e) => (CADENCE[e.review_interval] ? { cadence: CADENCE[e.review_interval], src: `hsf_element:${e.code}#review_interval` } : { cadence: null, set_by: 'competent_person', src: `hsf_element:${e.code}#review_interval` });
  const retentionOf = (e) => ({ class: e.retention_rule ?? 'HSF-5', text: RETENTION[e.retention_rule] ?? RETENTION['HSF-5'], src: `hsf_element:${e.code}#retention_rule` });

  // Section F register templates: one per Section F element, with the element's
  // "what to submit" lines as records to see and its common gaps as the gaps to
  // look for (guidance HSF-GUIDE-1.0).
  const templates = [];
  const excluded = [];
  for (const e of elements.filter((x) => x.section_code === 'F')) {
    const g = guidanceFor(e.code);
    if (!g) throw new Error(`No guidance for ${e.code}`);
    const code = `REG-${e.code.slice(4)}`;
    const items = [];
    (g.what_to_submit ?? []).forEach((t, i) => items.push({ section: 'Records to see', prompt: plain(t, `${e.code} what_to_submit`), src: `guidance:${e.code}#what_to_submit[${i}]` }));
    (g.common_gaps ?? []).forEach((t, i) => items.push({ section: 'Gaps to look for (Pass means not found)', prompt: plain(t, `${e.code} common_gaps`), src: `guidance:${e.code}#common_gaps[${i}]` }));
    for (const it of items) if (CLINICAL.test(it.prompt)) throw new Error(`A clinical line would reach an inspection: ${it.prompt}`);
    templates.push({
      id: uid(`template:${code}`),
      code,
      kind: 'register',
      name: plain(e.name, e.code),
      category: REGISTER_CATEGORY[e.code] ?? 'general',
      section_f_element_code: e.code,
      industry_code: null,
      trigger_code: e.trigger_code,
      responsible: e.responsible_appointment ?? e.responsible_role ?? null,
      interval: intervalOf(e),
      retention: retentionOf(e),
      basis: basisBy.get(e.code) ?? [],
      basis_state: e.basis_state,
      description: plain(g.why, `${e.code} why`),
      suggested_department: g.suggested_department ?? null,
      src: `hsf_element:${e.code}`,
      items: items.map((it, i) => ({ id: uid(`item:${code}:${i + 1}`), ordinal: i + 1, section_label: it.section, prompt: it.prompt, kernel_ref: e.code, src: it.src })),
    });
  }

  // Industry walkthroughs: the overlay's own additions (SPEC B7) and the
  // library elements it switches on outside Section F (the registers above
  // cover F), minus anything about medical fitness or surveillance.
  for (const ind of industries) {
    const rows = [...(overlayAdditions[ind.code] ?? []), ...(overlaySwitched[ind.code] ?? []).filter((o) => !o.element_code.startsWith('HSF-F-'))];
    const items = [];
    const seen = new Set();
    for (const o of rows) {
      const e = elementBy.get(o.element_code);
      if (!e || seen.has(e.code)) continue;
      seen.add(e.code);
      if (e.section_code === 'E' || CLINICAL.test(e.name)) {
        excluded.push({ element: e.code, industry: ind.code, reason: 'Medical fitness and surveillance stay with the occupational health practitioner; no clinical line in Bee-Inspect.', src: `hsf_element:${e.code}` });
        continue;
      }
      items.push({
        section: e.code.startsWith('HSF-OV-') ? `${ind.name}: ${sectionName.get(e.section_code)}` : sectionName.get(e.section_code),
        prompt: plain(e.name, e.code),
        ref: e.code,
        conditional: o.applicability === 'conditional',
        src: `hsf_element_industry:${e.code}@${ind.code}`,
      });
    }
    const code = `IND-${ind.code}`;
    templates.push({
      id: uid(`template:${code}`),
      code,
      kind: 'industry',
      name: `${ind.name} walkthrough`,
      category: INDUSTRY_CATEGORY[ind.code] ?? 'general',
      section_f_element_code: null,
      industry_code: ind.code,
      trigger_code: null,
      responsible: null,
      interval: { cadence: null, set_by: 'competent_person', src: `msp_industry:${ind.code}` },
      retention: { class: 'HSF-5', text: RETENTION['HSF-5'], src: `msp_industry:${ind.code}` },
      basis: [],
      basis_state: 'awaiting',
      description: `The industry specific checks of the ${ind.name} overlay in the Care Net kernel. It files with the inspection record; Section F registers are inspected with their own templates.`,
      suggested_department: null,
      src: `msp_industry:${ind.code}`,
      items: items.map((it, i) => ({ id: uid(`item:${code}:${i + 1}`), ordinal: i + 1, section_label: plain(it.section, code), prompt: it.prompt, kernel_ref: it.ref, conditional: it.conditional, src: it.src })),
    });
  }

  const registerApplies = (t, trig) => t.kind === 'register' && (!t.trigger_code || trig.has(t.trigger_code));
  const placeTypeApplies = (pt, indCode, trig, subCodesOfInd) =>
    !!pt.rule.always ||
    (pt.rule.industries ?? []).includes(indCode) ||
    (pt.rule.triggers ?? []).some((c) => trig.has(c)) ||
    (pt.rule.subindustries ?? []).some((c) => subCodesOfInd.includes(c));

  const bundleIndustries = industries.map((ind) => {
    const sample = samples[ind.code];
    const overlay = [...(overlayTriggers[ind.code] ?? [])].sort();
    const typical = [...sample.triggers].sort();
    const trig = new Set([...overlay, ...typical]);
    const indSubs = subs.filter((s) => s.industry_code === ind.code);
    const placeTypes = PLACE_TYPES.filter((pt) => placeTypeApplies(pt, ind.code, trig, indSubs.map((s) => s.code))).map((pt) => pt.code);
    const tpl = templates.filter((t) => t.industry_code === ind.code || registerApplies(t, trig));
    // Suggested departments: the File departments the guidance suggests for the
    // elements this industry's templates rest on, most frequent first; Health
    // and safety always leads.
    const count = new Map();
    for (const t of tpl) {
      const refs = t.kind === 'register' ? [t.section_f_element_code] : t.items.map((it) => it.kernel_ref);
      for (const r of refs) {
        const d = guidanceFor(r)?.suggested_department;
        if (d) count.set(d, (count.get(d) ?? 0) + 1);
      }
    }
    const depts = ['SHE', ...[...count.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([d]) => d).filter((d) => d !== 'SHE')].slice(0, 5);
    // Suggestions: the types the industry itself names first (by its rule, or a
    // type whose first word is a word of the industry's own name, such as
    // "Construction project" for Construction or "Office" for Office and
    // professional services), then those its subindustries name, then those its
    // triggers call for. With none of the first two kinds, a site leads.
    const nameWords = new Set(ind.name.toLowerCase().split(/[^a-z]+/));
    const namesIt = (c) => nameWords.has(PLACE_TYPES.find((p) => p.code === c).label.toLowerCase().split(' ')[0]);
    const rank = (c) => {
      const r = PLACE_TYPES.find((p) => p.code === c).rule;
      return r.industries?.includes(ind.code) || namesIt(c) ? 0 : r.subindustries?.some((x) => indSubs.some((s) => s.code === x)) ? 1 : 2;
    };
    let specific = placeTypes
      .filter((c) => PLACE_TYPES.find((p) => p.code === c).root && (!PLACE_TYPES.find((p) => p.code === c).rule.always || namesIt(c)))
      .sort((a, c) => rank(a) - rank(c));
    if (!specific.some((c) => rank(c) < 2)) specific = ['site', ...specific];
    return {
      code: ind.code,
      name: ind.name,
      regime: ind.regime,
      sic_reference: ind.sic_reference,
      src: `msp_industry:${ind.code}`,
      subindustries: indSubs.map((s) => ({ code: s.code, name: s.name, selectable: s.selectable, src: `msp_subindustry:${s.code}` })),
      triggers: {
        overlay: overlay.map((c) => ({ code: c, src: `hsf_element_industry:*@${ind.code}` })),
        typical: typical.map((c) => ({ code: c, src: `${sample.file}#triggers` })),
      },
      place_types: placeTypes,
      suggested_places: specific.slice(0, 5).map((c) => ({ place_type: c, src: `place_type:${c}` })),
      suggested_departments: depts.map((d) => ({ code: d, src: 'guidance:*#suggested_department' })),
      template_codes: tpl.map((t) => t.code),
      sample_company: { name: sample.company, scope: sample.scope, sites: sample.sites, headcount: sample.headcount, src: `${sample.file}#company` },
    };
  });

  const bundle = {
    schema: BUNDLE_SCHEMA,
    kernel: {
      name: 'Care Net Cognitive Kernel',
      version: kv.semver,
      released_on: kv.released_on,
      bundle_built_on: new Date().toISOString().slice(0, 10),
      ratified: false,
      guidance_version: guidance.meta.version,
      counts: kv.kernel_counts,
      src: `msp_kernel_version:${kv.semver}`,
      note: 'Offline copy for the Bee-Inspect app. Refreshed from the kernel service when it is connected. Legal intervals and retention periods show only where the kernel holds a verified value; otherwise your competent person sets them.',
    },
    limits: { place_max_depth: PLACE_MAX_DEPTH },
    departments: departments.map((d) => ({ code: d.code, name: d.name, src: `hsf_department:${d.code}` })),
    triggers: triggers.map((t) => ({ code: t.code, description: plain(t.description, t.code), src: `hsf_trigger:${t.code}` })),
    place_types: PLACE_TYPES.map((pt) => ({ ...pt, children: CHILDREN[pt.code], src: `place_type:${pt.code}` })),
    industries: bundleIndustries,
    templates,
    excluded,
  };
  return bundle;
}

// ---------------------------------------------------------------------------
// The same templates as SQL for the server (bi_template, bi_template_item and
// the 065 mapping tables). Idempotent; loaded by test/sql/bi_places_checks.sql.
function sqlText(s) {
  return s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
}

function seedSql(b) {
  const lines = [];
  lines.push('-- CNC HSF FORGE | BI-KRN-TPL | Bee-Inspect kernel templates (seed) | GENERATED, do not edit.');
  lines.push(`-- Written by apps/mobile/scripts/build-kernel-bundle.mjs from the Care Net kernel ${b.kernel.version} (release of ${b.kernel.released_on})`);
  lines.push('-- and hsf/guidance/guidance.json, the same templates as apps/mobile/assets/kernel/kernel-bundle.json.');
  lines.push('-- Needs migration 065. Idempotent (on conflict do nothing). Not applied to any Supabase project.');
  lines.push('');
  lines.push('insert into bi_template (id, tenant_id, code, version, name, category, section_f_element_code, description, status, industry_code, template_kind, kernel_version) values');
  lines.push(
    b.templates
      .map((t) => `  (${sqlText(t.id)}, null, ${sqlText(t.code)}, 1, ${sqlText(t.name)}, ${sqlText(t.category)}, ${sqlText(t.section_f_element_code)}, ${sqlText(t.description)}, 'draft', ${sqlText(t.industry_code)}, ${sqlText(t.kind)}, ${sqlText(b.kernel.version)})`)
      .join(',\n') + '\non conflict do nothing;',
  );
  lines.push('');
  lines.push('insert into bi_template_item (id, template_id, ordinal, section_label, prompt, kernel_ref, source_ref) values');
  const items = [];
  for (const t of b.templates) for (const it of t.items) items.push(`  (${sqlText(it.id)}, ${sqlText(t.id)}, ${it.ordinal}, ${sqlText(it.section_label)}, ${sqlText(it.prompt)}, ${sqlText(it.kernel_ref)}, ${sqlText(it.src)})`);
  lines.push(items.join(',\n') + '\non conflict do nothing;');
  lines.push('');
  lines.push('insert into bi_template_industry (template_id, industry_code, source_ref) values');
  const ti = [];
  for (const ind of b.industries) for (const code of ind.template_codes) ti.push(`  (${sqlText(b.templates.find((t) => t.code === code).id)}, ${sqlText(ind.code)}, ${sqlText('kernel-bundle:' + ind.code)})`);
  lines.push(ti.join(',\n') + '\non conflict do nothing;');
  lines.push('');
  lines.push('insert into bi_place_type_industry (place_type, industry_code, source_ref) values');
  const pti = [];
  for (const ind of b.industries) for (const pt of ind.place_types) pti.push(`  (${sqlText(pt)}, ${sqlText(ind.code)}, ${sqlText('kernel-bundle:' + ind.code)})`);
  lines.push(pti.join(',\n') + '\non conflict do nothing;');
  lines.push('');
  lines.push("update bi_template set status = 'published' where tenant_id is null and kernel_version = " + sqlText(b.kernel.version) + " and status = 'draft';");
  lines.push('');
  return lines.join('\n');
}

// ---------------------------------------------------------------------------

if (dbArg < 0) replay();
const bundle = build();
const json = JSON.stringify(bundle, null, 1) + '\n';
const sql = seedSql(bundle);

if (CHECK) {
  // The build date is the only field allowed to differ.
  const undated = (t) => t.replace(/"bundle_built_on": "[^"]*"/, '');
  const same = existsSync(OUT_JSON) && undated(readFileSync(OUT_JSON, 'utf8')) === undated(json) && existsSync(OUT_SQL) && readFileSync(OUT_SQL, 'utf8') === sql;
  process.stdout.write(same ? 'kernel bundle is current\n' : 'kernel bundle differs from the kernel: run the build\n');
  process.exit(same ? 0 : 1);
}
mkdirSync(path.dirname(OUT_JSON), { recursive: true });
writeFileSync(OUT_JSON, json);
writeFileSync(OUT_SQL, sql);
const counts = bundle.industries.map((i) => `${i.code}: ${i.subindustries.length} subindustries, ${new Set([...i.triggers.overlay, ...i.triggers.typical].map((t) => t.code)).size} triggers, ${i.place_types.length} place types, ${i.template_codes.length} templates (${bundle.templates.find((t) => t.code === `IND-${i.code}`).items.length} walkthrough checks)`);
process.stdout.write(`Wrote ${path.relative(ROOT, OUT_JSON)} (kernel ${bundle.kernel.version}, ${bundle.templates.length} templates, ${bundle.templates.reduce((s, t) => s + t.items.length, 0)} checklist lines)\n${counts.join('\n')}\nWrote ${path.relative(ROOT, OUT_SQL)}\n`);
