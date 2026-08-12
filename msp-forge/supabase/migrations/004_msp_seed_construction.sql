-- CNC MSP FORGE | KRN-SEED-01 v1.0.0 | Construction pilot industry seed
-- Phase 1 migration 004. Documentary verification performed 12/08/2026 by the
-- build agent against primary web sources, recorded per the triple gate
-- protocol and subject to OMP ratification. Values that could not be verified
-- remain unverified or pending and are never citable by the Generation Agent.

-- 1. Verified legal instruments -------------------------------------------------

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('OHS Act',
 'Occupational Health and Safety Act 85 of 1993',
 'act', null, '1994-01-01',
 'Amended over time, including by the Occupational Health and Safety Amendment Act 181 of 1993. In force August 2026.',
 'Consolidated Act text, SAFLII and lawlibrary.org.za consolidations of Act 85 of 1993',
 'Department of Employment and Labour published Act and regulations, labour.gov.za Document Centre',
 'Currency check 12/08/2026: in force, administered by the Department of Employment and Labour; no repeal or supersession',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('Construction Regulations, 2014',
 'Construction Regulations, 2014, GN R.84, Government Gazette 37305, 7 February 2014, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.84, GG 37305', '2014-02-07',
 'In force August 2026. Annexure 3 prescribes the Medical Certificate of Fitness for construction work, valid for one year from date of issue.',
 'GN R.84 Government Gazette 37305 regulation text, acts.co.za and gazette source',
 'Department of Employment and Labour Construction Regulations guidance and Occupational Health Southern Africa analysis of the Annexure 3 certificate',
 'Currency check 12/08/2026: in force, no amendment affecting medical surveillance provisions located',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('NIHL Regulations, 2003',
 'Noise-Induced Hearing Loss Regulations, 2003, GN R.307 of 7 March 2003, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.307, 7 March 2003', '2003-03-07',
 'REPEAL PENDING: regulation 18 of the Noise Exposure Regulations, 2024 repeals these Regulations 18 months after promulgation of 6 March 2025, that is with effect from 6 September 2026. In force until that date. Noise rating limit 85 dB(A) 8 hour rating level. Audiometric testing required for exposed employees.',
 'GN R.307 gazette text, lawlibrary.org.za akn/za/act/gn/2003/r307',
 'Department of Employment and Labour published regulation and Code of Practice for Audiometry, labour.gov.za; SAFLII consolidated regulation',
 'Currency check 12/08/2026: still in force; repeal effective 06/09/2026 per Noise Exposure Regulations, 2024 regulation 18; review scheduled at that horizon',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2026-09-06', 'verified'),

('Noise Exposure Regulations, 2024',
 'Noise Exposure Regulations, 2024, GN 5953, Government Gazette 52226, 6 March 2025, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN 5953, GG 52226', '2025-03-06',
 'Promulgated 6 March 2025 with Notices 5952 and 5954 (Physical Agents Regulations, 2024 and amendment of the General Safety Regulations). Repeals the Noise-Induced Hearing Loss Regulations, 2003 with effect from 6 September 2026. Accompanied by a new Code of Practice for Audiometry. Operative noise instrument from 06/09/2026.',
 'GN 5953 Government Gazette 52226 regulation text, lawlibrary.org.za akn/za/act/gn/2025/5953',
 'ENSafrica and Occupational Health Southern Africa journal analyses of the Noise Exposure Regulations, 2024 promulgation and transition',
 'Currency check 12/08/2026: promulgated and within the 18 month transition window; becomes sole operative noise instrument 06/09/2026',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-03-06', 'verified'),

('HCA Regulations, 2021',
 'Regulations for Hazardous Chemical Agents, 2021, GN R.280, Government Gazette 44348 (Regulation Gazette 11263), 29 March 2021, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.280, GG 44348, RG 11263', '2021-03-29',
 'Replaced the Hazardous Chemical Substances Regulations, 1995. Annexure tables list occupational exposure limits including respirable crystalline silica at 0.1 mg per cubic metre, 8 hour TWA. Medical surveillance duties for exposed employees.',
 'GN R.280 gazette text, gov.za gazette 44348 and lawlibrary.org.za akn/za/act/gn/2021/r280',
 'Department of Employment and Labour published regulation text, labour.gov.za; NIOH regulation launch material',
 'Currency check 12/08/2026: in force; silica OEL 0.1 mg per cubic metre confirmed across sources',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('Ergonomics Regulations, 2019',
 'Ergonomics Regulations, 2019, GN R.1589, Government Gazette 42894, 6 December 2019, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.1589, GG 42894', '2019-12-06',
 'In force August 2026. Requires an ergonomics programme including risk assessment, hierarchy of controls, training, and medical surveillance overseen by an occupational medicine practitioner, with baseline, periodic, and finding driven examinations.',
 'GN R.1589 gazette text, lawlibrary.org.za akn/za/act/gn/2019/r1589 and gov.za notice of 6 December 2019',
 'Occupational Health Southern Africa journal review of the Ergonomics Regulations, 2019; ENSafrica published regulation text',
 'Currency check 12/08/2026: in force, no amendment located',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('COIDA',
 'Compensation for Occupational Injuries and Diseases Act 130 of 1993, as amended by the Compensation for Occupational Injuries and Diseases Amendment Act 10 of 2022',
 'act', null, '1994-03-01',
 'Amendment Act 10 of 2022 brought into operation in phases by Proclamation 306 of 2026: 23 January 2026, 1 February 2026, and 1 April 2026. Post traumatic stress disorder formally recognised as an occupational disease. Employer conveyance and work related training injuries brought within scope. Three year prescription period for claims.',
 'Consolidated Act text, SAFLII; Amendment Act 10 of 2022, gov.za',
 'Bowmans, Cliffe Dekker Hofmeyr, and ENSafrica commencement analyses, January to March 2026',
 'Currency check 12/08/2026: amendments in force per phased 2026 commencement; Circular Instruction numbers for scheduled diseases remain open in the confirmation register (CR-12.2)',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-02-01', 'verified'),

('EEA section 7',
 'Employment Equity Act 55 of 1998, section 7 (medical testing)',
 'act', null, '1999-08-09',
 'Section 7(1): medical testing of an employee is prohibited unless legislation permits or requires it, or it is justifiable in the light of medical facts, employment conditions, social policy, the fair distribution of employee benefits, or the inherent requirements of a job. Section 7(2): HIV status testing only where the Labour Court determines it justifiable under section 50(4). Section unchanged by the Employment Equity Amendment Act 4 of 2022.',
 'Consolidated Act text, SAFLII eea1998240',
 'Department of Employment and Labour EEA summary; University and practitioner analyses of section 7 medical testing',
 'Currency check 12/08/2026: in force; 2022 amendment did not alter section 7',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('BCEA night work Code',
 'Basic Conditions of Employment Act 75 of 1997, section 17(3), read with the Code of Good Practice on the Arrangement of Working Time',
 'code', null, '1998-12-01',
 'Section 17(3)(b): an employee performing regular night work is entitled to a medical examination at commencement of regular night work and at regular intervals thereafter, at the employer''s expense. The Code guides frequency by health status, nature of work, and working hours.',
 'Code of Good Practice on the Arrangement of Working Time, labour.gov.za published text; SAFLII consolidated regulation',
 'Worklaw and practitioner analyses of BCEA section 17 night work medical requirements',
 'Currency check 12/08/2026: in force, no replacement code located',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('NRTA PrDP medical',
 'National Road Traffic Act 93 of 1996, read with the National Road Traffic Regulations, Professional Driving Permit medical fitness provisions',
 'act', null, '2000-08-01',
 'Professional Driving Permit applications require a medical certificate on the prescribed form, not older than two months at the time of application, assessing vision, hearing, cardiovascular, neurological, and general fitness. The precise regulation number for the PrDP medical provision is held open in the confirmation register (CR-13.8).',
 'Consolidated Act text, SAFLII nrta1996189',
 'RTMC and NaTIS prescribed medical certificate guidance; practitioner PrDP requirement summaries',
 'Currency check 12/08/2026: in force; PrDP medical requirement current',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('HPCSA Booklet 1',
 'HPCSA General Ethical Guidelines for the Health Care Professions, Booklet 1, December 2021 revision',
 'hpcsa', null, '2021-12-01',
 'Current HPCSA ethical baseline for all registered practitioners. December 2021 revision current at check date.',
 'HPCSA published Booklet 1, hpcsa.co.za professional practice guidelines',
 'HPCSA guideline update notices and professional body mirrors of the December 2021 revision set',
 'Currency check 12/08/2026: December 2021 revision remains the published version',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('HPCSA Booklet 10',
 'HPCSA General Ethical Guidelines for Good Practice in Telehealth, Booklet 10, revised December 2021',
 'hpcsa', null, '2021-12-01',
 'Telehealth guidance revised December 2021. Telehealth is not equivalent to face to face care and must not be introduced solely to cut costs or as a perverse incentive.',
 'HPCSA published Booklet 10 Telehealth December 2021, hpcsa.co.za',
 'Peer reviewed telehealth practice guidance for South African practitioners; professional body mirrors',
 'Currency check 12/08/2026: December 2021 revision remains the published version',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('HPCSA Booklet 11',
 'HPCSA Guidelines on Over Servicing, Perverse Incentives and Related Matters, Booklet 11',
 'hpcsa', null, '2021-12-01',
 'Prohibits perverse incentives including charging or benefit arrangements around referrals. Kernel rule RULE-HPCSA-PAYER encodes the house consequence: the employer is the payer and receiving specialists are never charged for referrals.',
 'HPCSA published Booklet 11, hpcsa.co.za professional practice guidelines',
 'Professional indemnity and practitioner analyses of the HPCSA perverse incentive guidance',
 'Currency check 12/08/2026: current published version',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified');

-- Staged, not verified: located but not yet taken through all three gates.
select msp_ingest_instrument('General Safety Regulations', 'General Safety Regulations made under the Occupational Health and Safety Act 85 of 1993, as amended by GN 5954 of 6 March 2025', 'regulation', null, null);
select msp_ingest_instrument('General Administrative Regulations', 'General Administrative Regulations made under the Occupational Health and Safety Act 85 of 1993', 'regulation', null, null);
select msp_ingest_instrument('General Machinery Regulations', 'General Machinery Regulations made under the Occupational Health and Safety Act 85 of 1993', 'regulation', null, null);
select msp_ingest_instrument('Driven Machinery Regulations', 'Driven Machinery Regulations made under the Occupational Health and Safety Act 85 of 1993', 'regulation', null, null);
select msp_ingest_instrument('Code of Practice for Audiometry, 2025', 'Code of Practice for Audiometry accompanying the Noise Exposure Regulations, 2024', 'code', null, null);
select msp_ingest_instrument('SANS 10083', 'SANS 10083, measurement and assessment of occupational noise for hearing conservation purposes, edition to be confirmed (CR-12.3)', 'sans', null, null);

-- 2. Industry and subindustries -------------------------------------------------

insert into msp_industry (code, name, sic_reference, regulatory_regime)
values ('CONSTR', 'Construction', 'SIC major division 5, Construction', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, s.selectable, s.notes
from msp_industry i,
     (values
       ('CONSTR-BUILD',  'Building construction',       false, 'Role and hazard map to be enabled in a Phase 6 batch; shares the civils role family'),
       ('CONSTR-CIVILS', 'Civil engineering works',     true,  'Pilot subindustry, verified against the canonical example plan CNC-RPT-2026-0812-001'),
       ('CONSTR-ROADS',  'Roadworks',                   false, 'Phase 6 batch'),
       ('CONSTR-DEMO',   'Demolition',                  false, 'Phase 6 batch'),
       ('CONSTR-ELEC',   'Electrical construction',     false, 'Phase 6 batch')
     ) as s(code, name, selectable, notes)
where i.code = 'CONSTR';

-- 3. Canonical hazard key A to O ------------------------------------------------

insert into msp_hazard (code, name, category, oel_value, oel_unit, oel_basis, oel_instrument, verification_status)
values
('A', 'Noise (plant, tools, machinery)', 'physical', 85, 'dB(A)',
 '8 hour rating level, the noise rating limit',
 'Noise-Induced Hearing Loss Regulations, 2003, GN R.307, in force to 05/09/2026; successor value under the Noise Exposure Regulations, 2024 held in CR-13.10 pending confirmation',
 'verified'),
('B', 'Dust, respirable crystalline silica', 'chemical', 0.1, 'mg/m3',
 '8 hour time weighted average',
 'Regulations for Hazardous Chemical Agents, 2021, GN R.280, Annexure exposure limit tables',
 'verified'),
('C', 'Hazardous chemicals (agent specific)', 'chemical', null, null,
 'Agent specific limits per the HCA Regulations, 2021 Annexure tables; resolved per named agent at engagement time',
 'Regulations for Hazardous Chemical Agents, 2021, GN R.280',
 'unverified'),
('D', 'Biological agents', 'biological', null, null, null,
 'Hazardous Biological Agents Regulations, staged for a later verification batch',
 'unverified'),
('E', 'Working at height (above 1.5m)', 'physical', null, null, null,
 'Construction Regulations, 2014, GN R.84, working at height and Annexure 3 fitness certification',
 'unverified'),
('F', 'Confined spaces', 'physical', null, null, null,
 'General Safety Regulations, staged pending verification',
 'unverified'),
('G', 'Vibration, hand arm and whole body', 'physical', null, null,
 'No verified South African occupational exposure limit located for whole body vibration; action values from international guidance are not citable and client measurements are assessed by the OMP',
 'Physical Agents Regulations, 2024 staged for verification; Ergonomics Regulations, 2019 for musculoskeletal effect',
 'unverified'),
('H', 'Heat and thermal stress', 'physical', null, null,
 'WBGT based assessment; limit values pending verification of the Environmental Regulations for Workplaces',
 'Environmental Regulations for Workplaces, staged pending verification',
 'unverified'),
('I', 'Manual handling and ergonomic strain', 'ergonomic', null, null, null,
 'Ergonomics Regulations, 2019, GN R.1589',
 'unverified'),
('J', 'Driving (licence and PrDP class per notes)', 'physical', null, null, null,
 'National Road Traffic Act 93 of 1996, PrDP medical fitness provisions',
 'unverified'),
('K', 'Shift or night work', 'psychosocial', null, null, null,
 'Basic Conditions of Employment Act 75 of 1997 section 17(3), Code of Good Practice on the Arrangement of Working Time',
 'unverified'),
('L', 'Ionising or non ionising radiation', 'physical', null, null, null,
 'Agent specific instruments staged for a later verification batch',
 'unverified'),
('M', 'Electrical hazard', 'physical', null, null, null,
 'Electrical Installation and Electrical Machinery Regulations, staged for a later verification batch',
 'unverified'),
('N', 'Psychosocial hazard', 'psychosocial', null, null, null,
 'COIDA as amended recognises post traumatic stress disorder as an occupational disease from the 2026 commencement',
 'unverified'),
('O', 'Other (specify in notes)', 'physical', null, null, null,
 'Placeholder key per the canonical questionnaire; never maps to a protocol without OMP direction',
 'unverified');

-- 4. Pilot job roles (canonical example, CONSTR-CIVILS) --------------------------

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Site Manager / Supervisor',
        'Site oversight, inspection, coordination of trades',
        'Regular walking across uneven site terrain; occasional ladder access',
        'Sustained attention, verbal communication',
        'None beyond general induction'),
       ('General Labourer',
        'Manual labour, material handling, demolition and site clearing',
        'Frequent manual lifting up to 25kg, repetitive bending',
        'Basic instruction following',
        'None beyond general induction'),
       ('Scaffolder / Heights Worker',
        'Erecting, altering, and dismantling scaffolding and access structures',
        'Climbing, working from unprotected edges, carrying loads at height',
        'Spatial awareness, balance, no vertigo',
        'Working at heights competency certificate'),
       ('Plant Operator',
        'Operating heavy earthmoving, lifting, and compaction machinery',
        'Prolonged sitting, foot and hand coordination under vibration',
        'Sustained visual attention, depth perception',
        'Plant operator certificate for the relevant class'),
       ('Welder / Steel Fabricator',
        'Cutting, welding, and fabricating structural steelwork',
        'Sustained awkward postures, fine motor control',
        'Colour vision for weld inspection, sustained attention near arc and heat',
        'Trade certification as applicable'),
       ('Concrete and Cement Worker',
        'Mixing, placing, and finishing concrete; formwork erection',
        'Frequent manual handling, kneeling, repetitive strain',
        'Basic instruction following',
        'None beyond general induction'),
       ('Electrician (site)',
        'Electrical installation, testing, and maintenance',
        'Working in restricted and confined access, occasional heights',
        'Fine motor control, colour vision for wiring',
        'Wireman''s licence; heights certificate if applicable'),
       ('Driver / Plant and Materials Transport',
        'Transporting materials, plant, and equipment between sites',
        'Prolonged sitting, reversing and manoeuvring in confined yards',
        'Sustained visual attention, reaction time, no uncontrolled hypoglycaemic risk',
        'Valid driving licence; PrDP where required')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'CONSTR-CIVILS';

-- 5. Job to hazard map ----------------------------------------------------------

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('Site Manager / Supervisor', 'A', 'Low', 'Incidental plant noise during site oversight'),
  ('Site Manager / Supervisor', 'B', 'Low', 'Incidental dust during site inspection'),
  ('Site Manager / Supervisor', 'E', 'Low to Moderate', 'Occasional exposure above 1.5m during site inspection'),
  ('Site Manager / Supervisor', 'H', 'Low', 'Outdoor sun exposure'),
  ('General Labourer', 'A', 'Moderate', 'Noise from surrounding plant and tools'),
  ('General Labourer', 'B', 'Moderate', 'Cement and concrete dust including respirable crystalline silica'),
  ('General Labourer', 'I', 'Moderate', 'Manual handling strain from material handling and site clearing'),
  ('General Labourer', 'H', 'Moderate', 'Heat and sun exposure in outdoor work'),
  ('Scaffolder / Heights Worker', 'E', 'High', 'Working at height above 1.5m with fall risk'),
  ('Scaffolder / Heights Worker', 'G', 'Moderate', 'Hand arm vibration from power tools'),
  ('Scaffolder / Heights Worker', 'A', 'Moderate', 'Noise from power tools and surrounding plant'),
  ('Plant Operator', 'G', 'Moderate to High', 'Whole body vibration from earthmoving and compaction machinery'),
  ('Plant Operator', 'A', 'High', 'Plant and compaction area noise; client measurements in the canonical example exceeded the rating limit'),
  ('Plant Operator', 'C', 'Moderate', 'Diesel exhaust fumes'),
  ('Plant Operator', 'I', 'Moderate', 'Prolonged sitting and postural strain'),
  ('Welder / Steel Fabricator', 'C', 'High', 'Welding fume including manganese oxide'),
  ('Welder / Steel Fabricator', 'L', 'Moderate', 'Ultraviolet radiation from arc welding'),
  ('Welder / Steel Fabricator', 'A', 'Moderate to High', 'Fabrication bay noise'),
  ('Concrete and Cement Worker', 'B', 'High', 'Cement and concrete dust, respirable crystalline silica'),
  ('Concrete and Cement Worker', 'C', 'Moderate', 'Wet cement skin contact, dermatitis and burns'),
  ('Concrete and Cement Worker', 'I', 'Moderate', 'Frequent manual handling and repetitive strain'),
  ('Electrician (site)', 'M', 'Moderate', 'Electrical installation, testing, and maintenance'),
  ('Electrician (site)', 'E', 'Low to Moderate', 'Occasional work at height above 1.5m'),
  ('Electrician (site)', 'F', 'Low', 'Occasional confined space work'),
  ('Driver / Plant and Materials Transport', 'J', 'Moderate', 'Professional driving with PrDP regulated fitness requirement'),
  ('Driver / Plant and Materials Transport', 'G', 'Moderate', 'Prolonged driving vibration'),
  ('Driver / Plant and Materials Transport', 'I', 'Moderate', 'Musculoskeletal strain and fatigue')
) as m(title, hazard_code, rating, rationale)
join msp_job_role jr on jr.title = m.title
join msp_subindustry s on s.id = jr.subindustry_id and s.code = 'CONSTR-CIVILS'
join msp_hazard h on h.code = m.hazard_code;

-- 6. Test protocols per hazard --------------------------------------------------

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id, p.test_name, p.test_type, p.baseline, p.interval_months, p.exit,
       p.triggers, p.bio_ref, li.id
from (values
  ('A', 'Audiometry', 'clinical', true, 12, true,
   'Exposure at or above the 85 dB(A) noise rating limit, or as directed by the OMP. Baseline within the statutory window at commencement of exposure.',
   null, 'NIHL Regulations, 2003'),
  ('B', 'Spirometry', 'clinical', true, 12, true,
   'Respirable crystalline silica or other respirable dust exposure per the OREP.',
   null, 'HCA Regulations, 2021'),
  ('B', 'Respiratory symptom questionnaire', 'clinical', true, 12, true,
   'Administered with spirometry for dust exposed categories.',
   null, 'HCA Regulations, 2021'),
  ('B', 'Chest X-ray per silica protocol', 'clinical', true, 12, true,
   'Where clinically indicated by the OMP for silica exposed workers, tightened on exceedance; reading per the OMP''s protocol.',
   null, 'HCA Regulations, 2021'),
  ('C', 'Occupational chemical exposure medical assessment', 'clinical', true, 12, true,
   'Battery tailored by the OMP to the specific agents in the engagement chemical register.',
   null, 'HCA Regulations, 2021'),
  ('C', 'Dermatological screen', 'clinical', true, 12, true,
   'Skin contact hazards, including wet cement dermatitis and burns risk.',
   null, 'HCA Regulations, 2021'),
  ('C', 'Biological monitoring for specific agents', 'biological_monitoring', true, 12, true,
   'Where the hazard demands it, for example manganese exposure in welding fume or solvent metabolite monitoring.',
   '[CONFIRM] Agent specific biological reference values are not yet kernel verified and route to the OMP queue; never printed unresolved.',
   'HCA Regulations, 2021'),
  ('E', 'Heights medical (cardiovascular, neurological, vision, blood pressure, BMI, vertigo and balance screen)', 'clinical', true, 12, true,
   'All work above 1.5m. The Construction Regulations Annexure 3 certificate is valid for one year, and third party validity requirements from the intake can only tighten this.',
   null, 'Construction Regulations, 2014'),
  ('F', 'Confined space medical (cardiorespiratory fitness, spirometry, claustrophobia screen)', 'clinical', true, 12, true,
   'Confined space entry duties per the OREP.',
   null, null),
  ('G', 'Vibration and musculoskeletal screen', 'clinical', true, 12, true,
   'Hand arm or whole body vibration exposure; assessment of client measured levels is an OMP determination while no verified South African limit is in the kernel.',
   null, 'Ergonomics Regulations, 2019'),
  ('H', 'Heat stress tolerance assessment', 'clinical', true, 12, true,
   'Work in WBGT exceedance areas or sustained outdoor summer work.',
   null, null),
  ('I', 'Musculoskeletal and ergonomic assessment', 'clinical', true, 12, true,
   'Manual handling, repetitive strain, and postural risk categories per the ergonomics risk assessment.',
   null, 'Ergonomics Regulations, 2019'),
  ('J', 'PrDP statutory medical and vision screen', 'clinical', true, 12, true,
   'Professional driving duties. The prescribed certificate must be current per licensing authority requirements, and the surveillance interval never exceeds the annual floor.',
   null, 'NRTA PrDP medical'),
  ('K', 'Night work medical examination', 'clinical', true, 12, true,
   'At commencement of regular night work and periodically thereafter, at the employer''s expense, per BCEA section 17(3) and the Code of Good Practice.',
   null, 'BCEA night work Code'),
  ('L', 'Vision screening including colour vision, and skin surveillance for ultraviolet exposure', 'clinical', true, 12, true,
   'Arc welding and other radiation exposure categories.',
   null, null),
  ('M', 'General medical with cardiovascular and vision screen (electrical work)', 'clinical', true, 12, true,
   'Electrical work fitness per the inherent requirements of the role.',
   null, null)
) as p(hazard_code, test_name, test_type, baseline, interval_months, exit, triggers, bio_ref, basis_short_name)
join msp_hazard h on h.code = p.hazard_code
left join msp_legal_instrument li
  on li.short_name = p.basis_short_name and li.status = 'verified';

-- 7. Industry to instrument map -------------------------------------------------

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('OHS Act', 'Framework Act for all construction workplaces'),
  ('Construction Regulations, 2014', 'Core sector regulation: heights, excavations, scaffolding, Annexure 3 medical certificate of fitness'),
  ('NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026'),
  ('Noise Exposure Regulations, 2024', 'Successor noise instrument, sole operative instrument from 06/09/2026'),
  ('HCA Regulations, 2021', 'Silica, cement, welding fume, diesel exhaust, solvents, and the chemical register'),
  ('Ergonomics Regulations, 2019', 'Manual handling, vibration effect, and postural risk surveillance'),
  ('COIDA', 'Compensation route for all construction occupational injuries and diseases'),
  ('EEA section 7', 'Lawful basis for every medical test, justified against the inherent requirements of each job'),
  ('BCEA night work Code', 'Applies where the intake reports regular night work'),
  ('NRTA PrDP medical', 'Applies to professional driving categories'),
  ('HPCSA Booklet 1', 'Ethical baseline for all examinations under the programme'),
  ('HPCSA Booklet 10', 'Governs any telehealth component of the programme'),
  ('HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(short_name, note)
  on true
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
where i.code = 'CONSTR';

-- 8. Kernel rules ---------------------------------------------------------------

insert into msp_kernel_rule (rule_code, description, condition_expr, effect, instrument_id, status)
values
('ROUTE-ODMWA-COIDA',
 'Compensation routing. Mining lung disease follows the ODMWA route; all other sectors and conditions follow COIDA. Encoded as data so the FRAME stage sets the route without prose reasoning.',
 '{"field": "industry.regulatory_regime", "cases": {"OHSA": "COIDA", "MHSA": "ODMWA for compensable lung disease, COIDA otherwise", "DUAL": "ODMWA for compensable lung disease, COIDA otherwise"}}',
 '{"set": "compensation_route"}',
 (select id from msp_legal_instrument where short_name = 'COIDA'),
 'verified'),
('TRIGGER-NIGHTWORK',
 'Regular night work in the intake adds the BCEA Code instrument and the hazard K night work medical to every affected category.',
 '{"field": "intake.shift_night_work", "equals": true}',
 '{"add_instrument": "BCEA night work Code", "add_hazard_protocols": "K"}',
 (select id from msp_legal_instrument where short_name = 'BCEA night work Code'),
 'verified'),
('TRIGGER-PRDP',
 'Any job category carrying hazard code J adds the NRTA instrument and the PrDP statutory battery for that category.',
 '{"field": "job.hazard_codes", "contains": "J"}',
 '{"add_instrument": "NRTA PrDP medical", "add_hazard_protocols": "J"}',
 (select id from msp_legal_instrument where short_name = 'NRTA PrDP medical'),
 'verified'),
('RULE-NOISE-TRANSITION',
 'Noise instrument transition. Packs generated before 06/09/2026 cite the NIHL Regulations, 2003 as operative and disclose the transition to the Noise Exposure Regulations, 2024; packs generated on or after that date cite the 2024 Regulations alone.',
 '{"field": "engagement.created_at", "before": "2026-09-06", "then": "NIHL Regulations, 2003 operative with transition disclosure", "else": "Noise Exposure Regulations, 2024 operative"}',
 '{"select_noise_instrument": true}',
 (select id from msp_legal_instrument where short_name = 'Noise Exposure Regulations, 2024'),
 'verified'),
('RULE-EXCEEDANCE-TIGHTEN',
 'A measured exposure at or above the applicable OEL can only tighten a surveillance interval, never loosen it, and always carries the compliance note that surveillance detects early effect but does not substitute for controlling exposure at source.',
 '{"field": "exceedance.assessment", "in": ["exceeds", "significantly_exceeds", "borderline"]}',
 '{"interval_policy": "tighten_only", "insert_template": "TPL-CGN-01"}',
 null,
 'verified'),
('RULE-HPCSA-PAYER',
 'The employer is always the payer. Charging receiving specialists for referrals is prohibited under the HPCSA perverse incentive rules.',
 '{"always": true}',
 '{"assert": "employer_is_payer", "prohibit": "charges_to_receiving_specialist"}',
 (select id from msp_legal_instrument where short_name = 'HPCSA Booklet 11'),
 'verified');

-- 9. Confirmation register ------------------------------------------------------

insert into msp_confirmation_item (item_code, kind, description, status, resolution, resolved_by, resolved_on)
values
('CR-12.1', 'confirm', 'Exact OEL values and schedules per hazard at kernel ingestion. Noise 85 dB(A) and respirable crystalline silica 0.1 mg/m3 verified 12/08/2026; all other values remain open.', 'open', null, null, null),
('CR-12.2', 'confirm', 'COIDA Circular Instruction numbers and current versions for NIHL, occupational lung disease, work related upper limb disorders, PTSD, and occupationally acquired infections.', 'open', null, null, null),
('CR-12.3', 'confirm', 'SANS standard numbers and editions for audiometry, noise measurement, and spirometry method, including the 2025 Code of Practice for Audiometry accompanying the Noise Exposure Regulations, 2024.', 'open', null, null, null),
('CR-12.4', 'confirm', 'Statutory retention periods per occupational health record class. Long retention presumed, never defaulted to short cycles.', 'open', null, null, null),
('CR-12.5', 'confirm', 'DPA status for DocuSeal, Vercel, Supabase, and Anthropic as POPIA operators.', 'open', null, null, null),
('CR-12.6', 'confirm', 'CNC Information Officer name and privacy contact for the POPIA blocks.', 'open', null, null, null),
('CR-12.7', 'confirm', 'Designated OMP name and HPCSA practice number per engagement.', 'open', null, null, null),
('CR-12.8', 'assumption', 'Location and format of existing CNC industry guides and academy metadata for precedent ingestion (Phase 2).', 'open', null, null, null),
('CR-12.9', 'assumption', 'Availability of helena-copywriting skill assets in the build environment.', 'resolved',
 'Checked 12/08/2026: not present in the build environment. The voice rules of Master Prompt Section 9.1 govern directly.', 'Build session', '2026-08-12'),
('CR-12.10', 'assumption', 'DocuSeal plan supports the required file upload field types and webhook payloads at production volume. Tested in Phase 2.', 'open', null, null, null),
('CR-13.1', 'confirm', 'Target Supabase project for the kernel and engagement schema.', 'resolved',
 'Resolved 12/08/2026: single project ahp-production (pboebfnujzffgwctsplw) in the account; msp_ prefixed additive schema applied; Care Net Consultants is Tenant 001 on that platform. Revisit only if a dedicated project is later mandated.', 'Build session under user run approval', '2026-08-12'),
('CR-13.2', 'confirm', 'Target Vercel team and project for the webhook receiver and agent runtime before Phase 2.', 'open', null, null, null),
('CR-13.3', 'confirm', 'CNC telephone and email for the questionnaire contact line (placeholders in canonical V1.2).', 'open', null, null, null),
('CR-13.4', 'confirm', 'Source assets for the CNC logo mark used in the dual brand header band.', 'open', null, null, null),
('CR-13.5', 'confirm', 'Classification banner values for generated packs (canonical uses CLASSIFICATION: CLIENT).', 'open', null, null, null),
('CR-13.6', 'confirm', 'Whether the Ubuntu closing line, I am because we are, carries into generated packs alongside the locked footer line.', 'open', null, null, null),
('CR-13.7', 'assumption', 'CLASSIFY triage confidence threshold set at 0.85 pending calibration in Phase 3.', 'open', null, null, null),
('CR-13.8', 'confirm', 'Precise National Road Traffic Regulations provision number for the PrDP medical certificate requirement.', 'open', null, null, null),
('CR-13.9', 'confirm', 'Verification of the General Safety, General Administrative, General Machinery, and Driven Machinery Regulations before any pack cites them.', 'open', null, null, null),
('CR-13.10', 'confirm', 'Noise rating limit value under the Noise Exposure Regulations, 2024 before the 06/09/2026 transition, so hazard A citation swaps correctly.', 'open', null, null, null);
