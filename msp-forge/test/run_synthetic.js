// CNC MSP FORGE | FRM-WHK-01 test harness | Synthetic end to end intake
// Runs the production validator over a synthetic DocuSeal submission shaped
// like the canonical Horizon Construction and Civils example, plus three
// negative cases. Emits the normalised payload for persistence through
// msp_ingest_intake, the same RPC the deployed webhook calls.

const { validateIntake } = require('../vercel/lib/validate');
const fs = require('fs');
const path = require('path');

const SELECTABLE = ['CONSTR-CIVILS'];

function ds(values, id) {
  return {
    event_type: 'form.completed',
    data: { id, values: Object.entries(values).map(([field, value]) => ({ field, value })) },
  };
}

const base = {
  company_registered_name: 'Horizon Construction and Civils (Pty) Ltd',
  company_trading_name: 'Horizon Civils',
  company_registration_number: '2015/123456/07',
  company_vat_number: '4123456789',
  company_head_office_address: '12 Contractor Way, Longmeadow Business Estate, Modderfontein, Gauteng, 1609',
  company_core_industry_freetext: 'Building and civil construction contracting',
  company_years_operating: '11',
  site_1_name: 'Head office and yard',
  site_1_address: 'Modderfontein, Gauteng',
  site_1_activity: 'Administration, workshop, fabrication bay',
  site_1_headcount: '25',
  site_2_name: 'Project site: N3 interchange upgrade',
  site_2_address: 'Gauteng region',
  site_2_activity: 'Civil works, earthworks, structures',
  site_2_headcount: '60',
  contact_1_role: 'SHE Officer',
  contact_1_name: 'J. Naidoo',
  contact_1_position: 'SHE Officer',
  contact_1_email: 'she@horizoncivils.example',
  contact_1_phone: '011 555 0100',
  reg_ohsa: 'true',
  reg_construction: 'true',
  reg_noise: 'true',
  reg_hca: 'true',
  reg_ergonomics: 'true',
  reg_nrta_prdp: 'true',
  coida_registered: 'true',
  coida_class_tariff_number: 'Class V, 0500',
  enforcement_notice_3yr: '',
  third_party_cert_required: 'true',
  third_party_cert_detail: 'Principal contractor requires heights fitness certificates valid no longer than 12 months',
  ra_exists: 'true',
  ra_date: '2026-05-10',
  ra_conducted_by: 'SafeWork AIA (Pty) Ltd',
  ra_assessor_accreditation: 'SANAS accredited Approved Inspection Authority',
  ra_next_review_date: '2027-05-10',
  hygiene_results_exist: 'true',
  hygiene_date: '2026-06-15',
  hygiene_conducted_by: 'SafeWork AIA (Pty) Ltd',
  exposure_1_hazard_location: 'Noise, plant and compaction area',
  exposure_1_measured_level: '92',
  exposure_1_unit: 'dB(A) 8 hour TWA',
  exposure_1_stated_oel: '85 dB(A)',
  exposure_1_date_measured: '2026-06-15',
  exposure_2_hazard_location: 'Respirable crystalline silica, concrete cutting and grinding',
  exposure_2_measured_level: '0.15',
  exposure_2_unit: 'mg/m3 8 hour TWA',
  exposure_2_stated_oel: '0.1 mg/m3',
  exposure_2_date_measured: '2026-06-15',
  exposure_3_hazard_location: 'Welding fume as manganese, fabrication bay',
  exposure_3_measured_level: '0.18',
  exposure_3_unit: 'mg/m3 8 hour TWA',
  exposure_3_stated_oel: '0.02 mg/m3',
  exposure_3_date_measured: '2026-06-15',
  workforce_total: '85',
  workforce_permanent: '70',
  workforce_contract: '15',
  shift_night_work: '',
  employees_under_18: '',
  pregnancy_exposed_roles: '',
  hs_committee_present: 'true',
  chronic_flag_present: 'true',
  chronic_flag_categories: 'Plant Operator; Driver / Plant and Materials Transport',
  job_1_title: 'Site Manager / Supervisor',
  job_1_headcount: '6',
  job_1_duties: 'Site oversight, inspection, coordination of trades',
  job_1_hazards: 'A, B, E, H',
  job_2_title: 'General Labourer',
  job_2_headcount: '30',
  job_2_duties: 'Manual labour, material handling, site clearing',
  job_2_hazards: 'A, B, I, H',
  job_2_rpe_issued: 'P2 dust mask',
  job_2_rpe_fit_tested: 'No',
  job_3_title: 'Scaffolder / Heights Worker',
  job_3_headcount: '12',
  job_3_duties: 'Erecting and dismantling scaffolding and access structures',
  job_3_hazards: 'E, G, A',
  job_3_statutory_requirement: 'Working at heights competency certificate',
  job_4_title: 'Plant Operator',
  job_4_headcount: '10',
  job_4_duties: 'Operating excavators, TLBs, rollers',
  job_4_hazards: 'G, A, C, I',
  job_5_title: 'Welder / Steel Fabricator',
  job_5_headcount: '8',
  job_5_duties: 'Cutting, welding, fabricating structural steel',
  job_5_hazards: 'C, L, A',
  job_5_rpe_issued: 'Half mask with P3 filter',
  job_5_rpe_fit_tested: 'Yes',
  job_5_rpe_fit_test_interval: 'Annually',
  job_6_title: 'Concrete and Cement Worker',
  job_6_headcount: '12',
  job_6_duties: 'Mixing, placing, finishing concrete',
  job_6_hazards: 'B, C, I',
  job_6_rpe_issued: 'P2 dust mask',
  job_6_rpe_fit_tested: 'No',
  job_7_title: 'Driver / Plant and Materials Transport',
  job_7_headcount: '5',
  job_7_duties: 'Transporting materials and plant between sites',
  job_7_hazards: 'J, G, I',
  job_7_statutory_requirement: 'PrDP',
  chem_1_substance_name: 'Diesel (plant fuel)',
  chem_1_sds_reference: 'SDS-DSL-01',
  chem_1_task_process: 'Refuelling of plant',
  chem_1_frequency: 'Daily',
  chem_1_controls: 'Bunded storage, spill kit, gloves',
  chem_2_substance_name: 'Welding consumables, manganese containing electrodes',
  chem_2_sds_reference: 'SDS-WLD-02',
  chem_2_task_process: 'Structural steel welding',
  chem_2_frequency: 'Daily in fabrication bay',
  chem_2_controls: 'Local extraction, RPE, welding curtains',
  industry_code: 'CONSTR',
  subindustry_code: 'CONSTR-CIVILS',
  brand_colour_hex: '#003366',
  delivery_contact_name: 'J. Naidoo',
  delivery_contact_email: 'she@horizoncivils.example',
  information_officer_name: 'A. Botha',
  information_officer_contact: 'privacy@horizoncivils.example',
  employees_informed_before_exam: 'true',
  consent_processing: 'true',
  consent_marketing: '',
  popia_use_cnc_forms: 'true',
  declarant_full_name: 'J. Naidoo',
  declarant_position: 'SHE Officer',
  declarant_company: 'Horizon Construction and Civils (Pty) Ltd',
  declaration_date: '2026-08-12',
};

const cases = [
  { name: 'happy path (canonical Horizon profile)', payload: ds(base, 'SYN-0001'), expect: { ok: true, triage: false } },
  { name: 'identity number guard', payload: ds({ ...base, chronic_flag_categories: 'Plant Operator, ID 8001015009087' }, 'SYN-0002'), expect: { ok: false } },
  { name: 'no processing consent', payload: ds({ ...base, consent_processing: '' }, 'SYN-0003'), expect: { ok: false } },
  { name: 'OTHER industry routes to triage', payload: ds({ ...base, industry_code: 'OTHER', subindustry_code: 'OTHER', industry_other_detail: 'Underwater basket weaving' }, 'SYN-0004'), expect: { ok: true, triage: true } },
];

let failures = 0;
for (const c of cases) {
  const r = validateIntake(c.payload, SELECTABLE);
  const okMatch = r.ok === c.expect.ok;
  const triageMatch = c.expect.triage === undefined || r.triage === c.expect.triage;
  const pass = okMatch && triageMatch;
  if (!pass) failures++;
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${c.name}  ok=${r.ok} triage=${r.triage}`);
  if (!pass) console.log('   detail:', JSON.stringify({ rejections: r.rejections, triageReasons: r.triageReasons }, null, 2));
}

const happy = validateIntake(cases[0].payload, SELECTABLE);
fs.writeFileSync(path.join(__dirname, 'normalised_synthetic.json'), JSON.stringify(happy.normalised, null, 2));
console.log(`\nnormalised payload written: jobs=${happy.normalised.jobs.length} sites=${happy.normalised.sites.length} exposures=${happy.normalised.exposures.length} chemicals=${happy.normalised.chemicals.length}`);
console.log('chronic flags:', happy.normalised.jobs.filter(j => j.chronic_flag).map(j => j.title).join(' | '));
process.exit(failures ? 1 : 0);
