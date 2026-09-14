// CNC MSP FORGE | FRM-WHK-01 v1.0.1 | Intake validation and normalisation
// Pure module: no network, no environment. Used identically by the Vercel
// webhook handler and the synthetic end to end test, so the tested code path
// is the production code path.

const HAZARD_KEY = 'ABCDEFGHIJKLMNO'.split('');
const SCHEMA_VERSION = 'intake.v1';

// A thirteen digit run anywhere in the payload resembles a South African
// identity number. The form must never carry one; such a payload routes to
// triage with the offending field masked, never silently corrected.
const ID_PATTERN = /\d{13}/;

function coerceBool(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'string') return ['true', 'yes', 'on', '1', 'checked'].includes(v.trim().toLowerCase());
  return false;
}

function coerceInt(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = parseInt(String(v).replace(/[^\d-]/g, ''), 10);
  return Number.isFinite(n) ? n : null;
}

function parseHazardCodes(v) {
  if (!v) return { codes: [], invalid: [] };
  const parts = String(v).toUpperCase().split(/[\s,;/]+/).filter(Boolean);
  const codes = [];
  const invalid = [];
  for (const p of parts) {
    if (HAZARD_KEY.includes(p)) { if (!codes.includes(p)) codes.push(p); }
    else invalid.push(p);
  }
  return { codes, invalid };
}

// DocuSeal form.completed webhooks carry data.values as [{field, value}].
// A flat object is also accepted so tests and replays are simple.
function flattenSubmission(payload) {
  const data = payload && payload.data ? payload.data : payload;
  const out = {};
  if (data && Array.isArray(data.values)) {
    for (const { field, value } of data.values) out[field] = value;
    out.docuseal_submission_id = String(data.id ?? data.submission_id ?? '');
  } else if (data && typeof data === 'object') {
    Object.assign(out, data);
    out.docuseal_submission_id = String(out.docuseal_submission_id ?? '');
  }
  return out;
}

function collectRepeats(flat, prefix, count, fields) {
  const rows = [];
  for (let i = 1; i <= count; i++) {
    const row = {};
    let any = false;
    for (const f of fields) {
      const v = flat[`${prefix}_${i}_${f}`];
      if (v !== undefined && v !== null && String(v).trim() !== '') {
        row[f] = typeof v === 'string' ? v.trim() : v;
        any = true;
      }
    }
    if (any) rows.push(row);
  }
  return rows;
}

/**
 * Validate and normalise a DocuSeal submission payload.
 * @param payload raw webhook body (DocuSeal shape or flat object)
 * @param selectableSubindustries array of governed subindustry codes currently selectable
 * @returns { ok, normalised, triage, triageReasons, rejections }
 *   rejections: hard failures; nothing may be persisted (for example no consent)
 *   triage: persist, but route to human triage instead of generation
 */
function validateIntake(payload, selectableSubindustries) {
  const flat = flattenSubmission(payload);
  const triageReasons = [];
  const rejections = [];

  const required = [
    'company_registered_name', 'company_registration_number', 'company_head_office_address',
    'company_core_industry_freetext', 'company_years_operating',
    'workforce_total', 'industry_code', 'subindustry_code',
    'delivery_contact_name', 'delivery_contact_email',
    'information_officer_name', 'information_officer_contact',
    'declarant_full_name', 'declarant_position', 'declarant_company',
  ];
  for (const f of required) {
    const v = flat[f];
    if (v === undefined || v === null || String(v).trim() === '') {
      triageReasons.push(`required field missing: ${f}`);
    }
  }

  if (!flat.docuseal_submission_id) rejections.push('missing DocuSeal submission id');

  // POPIA hard gate: without processing consent, nothing is persisted.
  if (!coerceBool(flat.consent_processing)) {
    rejections.push('processing consent not granted; intake must not be persisted');
  }
  if (!coerceBool(flat.employees_informed_before_exam)) {
    triageReasons.push('client has not confirmed employees will be informed before first examination');
  }

  // Identity number guard, with the offending field masked in any log.
  for (const [k, v] of Object.entries(flat)) {
    if (typeof v === 'string' && ID_PATTERN.test(v)) {
      rejections.push(`field ${k} contains a thirteen digit sequence resembling an identity number; payload rejected, field masked`);
    }
  }

  // Governed industry picker: OTHER or an unknown code never auto generates.
  const sub = String(flat.subindustry_code || '').trim().toUpperCase();
  if (sub === 'OTHER' || String(flat.industry_code || '').trim().toUpperCase() === 'OTHER') {
    triageReasons.push('industry selection is OTHER; routed to human triage, never auto generated');
  } else if (!selectableSubindustries.includes(sub)) {
    triageReasons.push(`subindustry code ${sub || '(empty)'} is not in the governed selectable list`);
  }

  const sites = collectRepeats(flat, 'site', 4, ['name', 'address', 'activity', 'headcount'])
    .map(s => ({ ...s, headcount: coerceInt(s.headcount) }));

  const jobsRaw = collectRepeats(flat, 'job', 10, [
    'title', 'headcount', 'duties', 'hazards', 'controls', 'physical_demands',
    'sensory_cognitive_demands', 'statutory_requirement',
    'rpe_issued', 'rpe_fit_tested', 'rpe_fit_test_interval', 'other_ppe',
  ]);
  const jobs = [];
  for (const j of jobsRaw) {
    if (!j.title) { triageReasons.push('job category block without a title'); continue; }
    const { codes, invalid } = parseHazardCodes(j.hazards);
    if (invalid.length) triageReasons.push(`job ${j.title}: unknown hazard codes ${invalid.join(', ')}`);
    if (!codes.length) triageReasons.push(`job ${j.title}: no valid hazard codes`);
    jobs.push({
      title: j.title,
      headcount: coerceInt(j.headcount),
      duties: j.duties || '',
      hazard_codes: codes,
      existing_controls: j.controls || null,
      physical_demands: j.physical_demands || null,
      sensory_cognitive_demands: j.sensory_cognitive_demands || null,
      statutory_requirement: j.statutory_requirement || null,
      chronic_flag: false,
      rpe_issued: j.rpe_issued || null,
      rpe_fit_tested: j.rpe_fit_tested || null,
      rpe_fit_test_interval: j.rpe_fit_test_interval || null,
      other_ppe: j.other_ppe || null,
    });
  }
  // The ingest function refuses an intake without a job category, so this is a
  // rejection the client can fix, not a triage case (it surfaced as a 500 on 14/09/2026).
  if (!jobs.length) rejections.push('no job categories supplied');

  // Aggregate chronic condition flag: mark the named categories, never a person.
  if (coerceBool(flat.chronic_flag_present) && flat.chronic_flag_categories) {
    const catText = String(flat.chronic_flag_categories).toLowerCase();
    for (const job of jobs) {
      if (catText.includes(job.title.toLowerCase())) job.chronic_flag = true;
    }
  }

  const exposures = collectRepeats(flat, 'exposure', 6,
    ['hazard_location', 'measured_level', 'unit', 'stated_oel', 'date_measured']);
  const chemicals = collectRepeats(flat, 'chem', 8,
    ['substance_name', 'sds_reference', 'task_process', 'frequency', 'quantity_per_use', 'controls']);

  const triage = triageReasons.length > 0;
  const normalised = {
    schema_version: SCHEMA_VERSION,
    docuseal_submission_id: String(flat.docuseal_submission_id || ''),
    validation_status: triage ? 'triage' : 'valid',
    triage_reason: triage ? triageReasons.join('; ') : null,

    company_registered_name: flat.company_registered_name || null,
    company_trading_name: flat.company_trading_name || null,
    company_registration_number: flat.company_registration_number || null,
    company_vat_number: flat.company_vat_number || null,
    company_head_office_address: flat.company_head_office_address || null,
    company_core_industry_freetext: flat.company_core_industry_freetext || null,
    company_years_operating: coerceInt(flat.company_years_operating),

    industry_code: String(flat.industry_code || '').trim().toUpperCase() || null,
    subindustry_code: sub || null,
    industry_other_detail: flat.industry_other_detail || null,

    workforce_total: coerceInt(flat.workforce_total),
    shift_night_work: coerceBool(flat.shift_night_work),
    employees_under_18: coerceBool(flat.employees_under_18),
    pregnancy_exposed_roles: coerceBool(flat.pregnancy_exposed_roles),
    hs_committee_present: coerceBool(flat.hs_committee_present),
    chronic_flag_present: coerceBool(flat.chronic_flag_present),
    chronic_flag_categories: flat.chronic_flag_categories || null,

    coida_registered: coerceBool(flat.coida_registered),
    coida_class_tariff_number: flat.coida_class_tariff_number || null,
    enforcement_notice_3yr: coerceBool(flat.enforcement_notice_3yr),
    enforcement_notice_detail: flat.enforcement_notice_detail || null,
    third_party_cert_required: coerceBool(flat.third_party_cert_required),
    third_party_cert_detail: flat.third_party_cert_detail || null,

    ra_exists: coerceBool(flat.ra_exists),
    ra_date: flat.ra_date || null,
    ra_conducted_by: flat.ra_conducted_by || null,
    ra_assessor_accreditation: flat.ra_assessor_accreditation || null,
    ra_next_review_date: flat.ra_next_review_date || null,
    hygiene_results_exist: coerceBool(flat.hygiene_results_exist),
    hygiene_date: flat.hygiene_date || null,
    hygiene_conducted_by: flat.hygiene_conducted_by || null,
    process_change_since_ra: coerceBool(flat.process_change_since_ra),
    process_change_detail: flat.process_change_detail || null,

    current_medicals_exist: coerceBool(flat.current_medicals_exist),
    current_provider: flat.current_provider || null,
    current_tests_detail: flat.current_tests_detail || null,
    outstanding_referrals: coerceBool(flat.outstanding_referrals),
    records_format: flat.records_format || null,

    injuries_3yr: coerceBool(flat.injuries_3yr),
    coida_claims_3yr: coerceBool(flat.coida_claims_3yr),
    modified_duties_current: coerceBool(flat.modified_duties_current),
    incident_history_detail: flat.incident_history_detail || null,

    brand_colour_hex: flat.brand_colour_hex || null,
    certificate_format_preference: flat.certificate_format_preference || null,
    delivery_contact_name: flat.delivery_contact_name || null,
    delivery_contact_email: flat.delivery_contact_email || null,

    information_officer_name: flat.information_officer_name || null,
    information_officer_contact: flat.information_officer_contact || null,
    employees_informed_before_exam: coerceBool(flat.employees_informed_before_exam),
    consent_processing: coerceBool(flat.consent_processing),
    consent_marketing: coerceBool(flat.consent_marketing),
    popia_use_cnc_forms: coerceBool(flat.popia_use_cnc_forms),
    consent_wording_version: 'popia.v1',

    declarant_full_name: flat.declarant_full_name || null,
    declarant_position: flat.declarant_position || null,
    declarant_company: flat.declarant_company || null,
    declaration_date: flat.declaration_date || null,

    sites, jobs, exposures, chemicals,
    nightwork_medical_current: coerceBool(flat.nightwork_medical_current),
    nightwork_medical_interval: flat.nightwork_medical_interval || null,
    shift_pattern_detail: flat.shift_pattern_detail || null,
    hazard_additional_detail: flat.hazard_additional_detail || null,
  };

  return {
    ok: rejections.length === 0,
    rejections,
    triage,
    triageReasons,
    normalised: rejections.length === 0 ? normalised : null,
  };
}

module.exports = { validateIntake, flattenSubmission, parseHazardCodes, coerceBool, coerceInt, SCHEMA_VERSION };
