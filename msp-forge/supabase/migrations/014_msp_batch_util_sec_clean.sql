-- CNC MSP FORGE | TAX-BAT-05 v1.0.0 | Phase 6 batch 5: Utilities and energy, Security services, Cleaning and hygiene
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('Electrical Machinery and Installation Regulations',
 'Electrical Machinery Regulations, 2011, GN R.250, Government Gazette 34154, in operation 1 July 2011, read with the Electrical Installation Regulations, 2009, GN R.242, Government Gazette 31975, in operation 1 May 2009, both made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.250, GG 34154; GN R.242, GG 31975', '2011-07-01',
 'In force August 2026. The Machinery Regulations apply to users who generate, transmit, or distribute electricity to the point of supply; the Installation Regulations govern electrical installation work and registered person requirements. Neither prescribes a standing medical battery: electrical work fitness rests on Employment Equity Act section 7 inherent requirements, with these Regulations anchoring the hazard and competency context.',
 'Consolidated regulation texts, SAFLII emr2011295 and eir342; Department of Employment and Labour published PDFs',
 'Electrical Conformance Board standards incorporation record and policy database entries for both Regulations',
 'Currency check 13/08/2026: both in force, standards incorporation amendments recorded',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

update msp_hazard
   set oel_instrument = 'Electrical Machinery Regulations, 2011, GN R.250 and Electrical Installation Regulations, 2009, GN R.242; fitness for electrical work per EEA section 7 inherent requirements'
 where code = 'M';

update msp_test_protocol
   set legal_basis_id = (select id from msp_legal_instrument where short_name = 'Electrical Machinery and Installation Regulations'),
       trigger_conditions = 'Electrical work fitness per the inherent requirements of the role, in the hazard context of the Electrical Machinery and Installation Regulations. The Regulations anchor the hazard; the lawful testing basis is EEA section 7.'
 where test_name = 'General medical with cardiovascular and vision screen (electrical work)';

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('UTIL', 'Utilities and energy', 'SIC major division 4, Electricity, gas and water supply', 'OHSA'),
('SEC', 'Security services', 'SIC major division 9, Community, social and personal services', 'OHSA'),
('CLEAN', 'Cleaning and hygiene services', 'SIC major division 9, Community, social and personal services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('UTIL', 'UTIL-GEN',   'Power generation',        'Batch 5 role map seeded; gate check below'),
  ('UTIL', 'UTIL-WATER', 'Water and wastewater',    'Batch 5 role map seeded; gate check below'),
  ('UTIL', 'UTIL-RENEW', 'Renewable energy',        'Batch 5 role map seeded; gate check below'),
  ('SEC',  'SEC-GUARD',  'Guarding services',       'Batch 5 role map seeded; gate check below'),
  ('SEC',  'SEC-ARMED',  'Armed response and cash in transit', 'Batch 5 role map seeded; gate check below'),
  ('CLEAN','CLEAN-COMM', 'Commercial cleaning',     'Batch 5 role map seeded; gate check below'),
  ('CLEAN','CLEAN-SPEC', 'Specialised hygiene services', 'Batch 5 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('UTIL-GEN', 'Plant Operator (power station)', 'Operating boilers, turbines, and auxiliary plant', 'Plant rounds in heat and noise, stair and ladder access', 'Alarm vigilance across shifts', 'Plant operation competency'),
  ('UTIL-GEN', 'Electrical Operator (HV switching)', 'High voltage switching and isolation', 'Substation access, switching operations', 'Switching precision, no condition with sudden incapacity potential', 'HV switching authorisation'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'Coal, ash, and dust plant operations', 'Heavy manual work in dust and heat', 'Instruction following under PPE burden', 'None beyond induction'),
  ('UTIL-GEN', 'Line Worker (transmission and distribution)', 'Overhead line construction and fault work', 'Pole and tower climbing, live line discipline', 'Spatial awareness at height, no vertigo', 'Line work competency; heights certification'),
  ('UTIL-GEN', 'Instrument and Control Technician', 'Maintaining control and protection systems', 'Plant access, fine work in panels', 'Fine motor control, fault diagnosis', 'Trade certification'),
  ('UTIL-GEN', 'Shift Charge Engineer', 'Shift control of generation plant', 'Control room duty across nights', 'Sustained concentration, incident command', 'Engineering certification'),
  ('UTIL-WATER', 'Process Controller (water treatment)', 'Dosing, filtration, and disinfection operations', 'Plant rounds with chemical handling', 'Dosing precision, alarm vigilance', 'Water care competency'),
  ('UTIL-WATER', 'Wastewater Plant Operator', 'Screening, digestion, and sludge operations', 'Manual work with sewage contact', 'Process vigilance, hygiene discipline', 'Water care competency'),
  ('UTIL-WATER', 'Chlorination Technician', 'Chlorine gas and hypochlorite systems', 'Cylinder handling, confined dosing rooms', 'Leak response discipline', 'Chlorine handling competency'),
  ('UTIL-WATER', 'Sewer Network Worker', 'Sewer maintenance including confined entry', 'Confined space entry, heavy manual work', 'Gas test discipline, escape procedure', 'Confined space entry competency'),
  ('UTIL-WATER', 'Pump Station Attendant', 'Operating and maintaining pump stations', 'Station access, occasional confined entry', 'Mechanical vigilance', 'None beyond induction'),
  ('UTIL-RENEW', 'Wind Turbine Technician', 'Turbine maintenance at hub height', 'Tower climbing, rescue readiness, work at extreme height', 'No vertigo, self rescue competence, sustained concentration', 'GWO or equivalent heights and rescue certification'),
  ('UTIL-RENEW', 'Solar Plant Technician', 'PV plant maintenance and DC work', 'Field work in heat, panel handling', 'DC electrical discipline', 'Electrical competency'),
  ('UTIL-RENEW', 'Substation Electrician (renewables)', 'Plant substation and inverter maintenance', 'Substation access, switching support', 'Fine motor control, switching discipline', 'Wireman''s licence as applicable'),
  ('UTIL-RENEW', 'Site Operations Controller', 'Monitoring and dispatch of plant output', 'Control room duty', 'Sustained attention across shifts', 'None beyond induction'),
  ('UTIL-RENEW', 'Vegetation and Civils Worker', 'Site clearing and civil maintenance', 'Manual outdoor work in heat', 'Instruction following', 'None beyond induction'),
  ('SEC-GUARD', 'Security Officer (site guarding)', 'Access control and patrols across shifts', 'Standing posts, patrol walking, night duty', 'Vigilance across night shifts, incident composure', 'PSIRA registration'),
  ('SEC-GUARD', 'Control Room Operator', 'CCTV monitoring and alarm dispatch', 'Sedentary night duty', 'Sustained visual vigilance, dispatch precision', 'PSIRA registration'),
  ('SEC-GUARD', 'Retail Security Officer', 'In store loss prevention', 'Standing shifts with public interaction', 'Conflict management composure', 'PSIRA registration'),
  ('SEC-GUARD', 'Site Security Supervisor', 'Supervision of guard rosters and posts', 'Site rounds across shifts', 'Roster management, incident response', 'PSIRA registration'),
  ('SEC-GUARD', 'Events Security Officer', 'Crowd management at events', 'Prolonged standing, physical positioning', 'Crowd vigilance, de escalation', 'PSIRA registration'),
  ('SEC-ARMED', 'Armed Response Officer', 'Vehicle response to alarms', 'Rapid response driving and approach work', 'Firearm discipline, threat judgement, no uncontrolled hypoglycaemic risk', 'PSIRA registration; firearm competency'),
  ('SEC-ARMED', 'Cash in Transit Crew Member', 'Cash movement and vehicle protection', 'Load carriage under threat vigilance', 'Sustained threat vigilance, firearm discipline', 'PSIRA registration; firearm competency'),
  ('SEC-ARMED', 'CIT Driver', 'Armoured vehicle operation', 'Prolonged driving under vigilance', 'Reaction time, route vigilance, no uncontrolled hypoglycaemic risk', 'PSIRA registration; PrDP; firearm competency'),
  ('SEC-ARMED', 'Tactical Support Officer', 'High risk escort and support duty', 'Load bearing tactical work', 'Composure under threat, firearm discipline', 'PSIRA registration; firearm competency'),
  ('SEC-ARMED', 'Armoury Controller', 'Firearm issue, storage, and inspection', 'Standing armoury duty', 'Procedural precision, firearm discipline', 'PSIRA registration; firearm competency'),
  ('CLEAN-COMM', 'Commercial Cleaner', 'Office and facility cleaning', 'Repetitive cleaning work with chemical use', 'Chemical label discipline', 'None beyond induction'),
  ('CLEAN-COMM', 'Industrial Cleaner', 'Plant and warehouse deep cleaning', 'Heavy cleaning work, machine use', 'Machine and chemical discipline', 'None beyond induction'),
  ('CLEAN-COMM', 'High Level Cleaning Operative', 'Facade and high level cleaning', 'Rope access or platform work at height', 'No vertigo, access equipment discipline', 'Working at heights certification; rope access as applicable'),
  ('CLEAN-COMM', 'Cleaning Team Supervisor', 'Supervision of cleaning teams and chemicals', 'Site rounds', 'Team coordination, chemical control', 'None beyond induction'),
  ('CLEAN-COMM', 'Carpet and Floor Care Operative', 'Machine scrubbing, stripping, and sealing', 'Machine handling, wet work', 'Machine and slip discipline', 'None beyond induction'),
  ('CLEAN-SPEC', 'Healthcare Cleaning Operative', 'Clinical area cleaning and waste segregation', 'Cleaning with infectious and sharps risk', 'Segregation discipline', 'None beyond induction'),
  ('CLEAN-SPEC', 'Hygiene Services Technician', 'Washroom hygiene installations and servicing', 'Route servicing with chemical handling', 'Route discipline', 'Driving licence'),
  ('CLEAN-SPEC', 'Pest Control Operator', 'Structural pest control application', 'Application work in roof voids and confined areas', 'Label and exclusion discipline', 'Registered pest control operator'),
  ('CLEAN-SPEC', 'Biohazard Remediation Operative', 'Trauma and biohazard scene cleaning', 'Full PPE decontamination work', 'Procedure discipline under distressing scenes', 'None beyond induction'),
  ('CLEAN-SPEC', 'Sanitation Tanker Operator', 'Servicing chemical toilets and grease traps', 'Hose handling, tanker operation', 'Hygiene and route discipline', 'Driving licence; PrDP where applicable')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('UTIL-GEN', 'Plant Operator (power station)', 'A', 'High', 'Turbine hall and boiler plant noise'),
  ('UTIL-GEN', 'Plant Operator (power station)', 'H', 'Moderate', 'Boiler plant heat'),
  ('UTIL-GEN', 'Plant Operator (power station)', 'K', 'Moderate', 'Continuous shift operation'),
  ('UTIL-GEN', 'Electrical Operator (HV switching)', 'M', 'High', 'High voltage switching duty'),
  ('UTIL-GEN', 'Electrical Operator (HV switching)', 'K', 'Moderate', 'Shift switching duty'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'B', 'Moderate', 'Coal and ash dust'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'A', 'Moderate', 'Plant noise'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'H', 'Moderate', 'Boiler area heat'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'I', 'Moderate', 'Heavy plant labour'),
  ('UTIL-GEN', 'Line Worker (transmission and distribution)', 'E', 'High', 'Pole and tower work at height'),
  ('UTIL-GEN', 'Line Worker (transmission and distribution)', 'M', 'High', 'Live and switched line work'),
  ('UTIL-GEN', 'Line Worker (transmission and distribution)', 'H', 'Moderate', 'Outdoor line work in heat'),
  ('UTIL-GEN', 'Instrument and Control Technician', 'M', 'Moderate', 'Panel and instrument electrical work'),
  ('UTIL-GEN', 'Instrument and Control Technician', 'A', 'Moderate', 'Plant noise during rounds'),
  ('UTIL-GEN', 'Shift Charge Engineer', 'K', 'Moderate', 'Night shift plant control'),
  ('UTIL-GEN', 'Shift Charge Engineer', 'A', 'Low', 'Control room adjacency to plant'),
  ('UTIL-WATER', 'Process Controller (water treatment)', 'C', 'Moderate', 'Dosing chemical handling'),
  ('UTIL-WATER', 'Process Controller (water treatment)', 'D', 'Moderate', 'Raw water contact'),
  ('UTIL-WATER', 'Wastewater Plant Operator', 'D', 'High', 'Sewage biological exposure'),
  ('UTIL-WATER', 'Wastewater Plant Operator', 'C', 'Moderate', 'Process chemical handling'),
  ('UTIL-WATER', 'Wastewater Plant Operator', 'I', 'Moderate', 'Screen and sludge labour'),
  ('UTIL-WATER', 'Chlorination Technician', 'C', 'High', 'Chlorine gas systems'),
  ('UTIL-WATER', 'Chlorination Technician', 'F', 'Moderate', 'Dosing room confined access'),
  ('UTIL-WATER', 'Sewer Network Worker', 'F', 'High', 'Sewer confined space entry'),
  ('UTIL-WATER', 'Sewer Network Worker', 'D', 'High', 'Sewage biological exposure'),
  ('UTIL-WATER', 'Sewer Network Worker', 'I', 'High', 'Heavy sewer maintenance work'),
  ('UTIL-WATER', 'Pump Station Attendant', 'A', 'Moderate', 'Pump hall noise'),
  ('UTIL-WATER', 'Pump Station Attendant', 'F', 'Low', 'Occasional wet well access'),
  ('UTIL-RENEW', 'Wind Turbine Technician', 'E', 'High', 'Hub height access and rescue readiness'),
  ('UTIL-RENEW', 'Wind Turbine Technician', 'M', 'Moderate', 'Turbine electrical systems'),
  ('UTIL-RENEW', 'Wind Turbine Technician', 'I', 'Moderate', 'Tower climbing load'),
  ('UTIL-RENEW', 'Solar Plant Technician', 'H', 'High', 'Field work in solar resource heat'),
  ('UTIL-RENEW', 'Solar Plant Technician', 'M', 'Moderate', 'DC string and inverter work'),
  ('UTIL-RENEW', 'Substation Electrician (renewables)', 'M', 'High', 'Substation and inverter electrical work'),
  ('UTIL-RENEW', 'Site Operations Controller', 'K', 'Moderate', 'Shift monitoring duty'),
  ('UTIL-RENEW', 'Vegetation and Civils Worker', 'I', 'Moderate', 'Manual site maintenance'),
  ('UTIL-RENEW', 'Vegetation and Civils Worker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('SEC-GUARD', 'Security Officer (site guarding)', 'K', 'High', 'Rotating night guarding'),
  ('SEC-GUARD', 'Security Officer (site guarding)', 'N', 'Moderate', 'Confrontation exposure'),
  ('SEC-GUARD', 'Security Officer (site guarding)', 'I', 'Moderate', 'Prolonged standing and patrols'),
  ('SEC-GUARD', 'Control Room Operator', 'K', 'High', 'Night control room vigilance'),
  ('SEC-GUARD', 'Control Room Operator', 'N', 'Low', 'Incident monitoring load'),
  ('SEC-GUARD', 'Retail Security Officer', 'N', 'Moderate', 'Public confrontation exposure'),
  ('SEC-GUARD', 'Retail Security Officer', 'I', 'Moderate', 'Standing shifts'),
  ('SEC-GUARD', 'Site Security Supervisor', 'K', 'Moderate', 'Shift supervision'),
  ('SEC-GUARD', 'Events Security Officer', 'N', 'Moderate', 'Crowd confrontation exposure'),
  ('SEC-GUARD', 'Events Security Officer', 'A', 'Moderate', 'Event sound exposure'),
  ('SEC-ARMED', 'Armed Response Officer', 'N', 'High', 'Armed confrontation exposure'),
  ('SEC-ARMED', 'Armed Response Officer', 'J', 'High', 'Response driving'),
  ('SEC-ARMED', 'Armed Response Officer', 'K', 'Moderate', 'Night response shifts'),
  ('SEC-ARMED', 'Cash in Transit Crew Member', 'N', 'High', 'Attack risk exposure'),
  ('SEC-ARMED', 'Cash in Transit Crew Member', 'I', 'Moderate', 'Cash load carriage'),
  ('SEC-ARMED', 'CIT Driver', 'J', 'High', 'Armoured vehicle operation under threat'),
  ('SEC-ARMED', 'CIT Driver', 'N', 'High', 'Attack risk exposure'),
  ('SEC-ARMED', 'Tactical Support Officer', 'N', 'High', 'High risk escort duty'),
  ('SEC-ARMED', 'Tactical Support Officer', 'I', 'Moderate', 'Tactical load bearing'),
  ('SEC-ARMED', 'Armoury Controller', 'N', 'Low', 'Firearm custody responsibility'),
  ('CLEAN-COMM', 'Commercial Cleaner', 'C', 'Moderate', 'Cleaning chemical use'),
  ('CLEAN-COMM', 'Commercial Cleaner', 'I', 'Moderate', 'Repetitive cleaning work'),
  ('CLEAN-COMM', 'Commercial Cleaner', 'K', 'Moderate', 'Early and late shift cleaning'),
  ('CLEAN-COMM', 'Industrial Cleaner', 'C', 'Moderate', 'Industrial cleaning agents'),
  ('CLEAN-COMM', 'Industrial Cleaner', 'I', 'High', 'Heavy deep cleaning work'),
  ('CLEAN-COMM', 'Industrial Cleaner', 'A', 'Moderate', 'Cleaning machinery noise'),
  ('CLEAN-COMM', 'High Level Cleaning Operative', 'E', 'High', 'Facade work at height'),
  ('CLEAN-COMM', 'High Level Cleaning Operative', 'C', 'Moderate', 'Cleaning chemical use at height'),
  ('CLEAN-COMM', 'Cleaning Team Supervisor', 'C', 'Low', 'Chemical control supervision'),
  ('CLEAN-COMM', 'Carpet and Floor Care Operative', 'C', 'Moderate', 'Strippers and sealants'),
  ('CLEAN-COMM', 'Carpet and Floor Care Operative', 'I', 'Moderate', 'Machine handling'),
  ('CLEAN-SPEC', 'Healthcare Cleaning Operative', 'D', 'High', 'Clinical infectious and sharps exposure'),
  ('CLEAN-SPEC', 'Healthcare Cleaning Operative', 'C', 'Moderate', 'Disinfectant use'),
  ('CLEAN-SPEC', 'Hygiene Services Technician', 'D', 'Moderate', 'Washroom service exposure'),
  ('CLEAN-SPEC', 'Hygiene Services Technician', 'C', 'Moderate', 'Hygiene chemical handling'),
  ('CLEAN-SPEC', 'Hygiene Services Technician', 'J', 'Moderate', 'Route driving'),
  ('CLEAN-SPEC', 'Pest Control Operator', 'C', 'High', 'Pesticide application including organophosphates'),
  ('CLEAN-SPEC', 'Pest Control Operator', 'F', 'Moderate', 'Roof void and confined area access'),
  ('CLEAN-SPEC', 'Biohazard Remediation Operative', 'D', 'High', 'Trauma scene biological exposure'),
  ('CLEAN-SPEC', 'Biohazard Remediation Operative', 'N', 'Moderate', 'Distressing scene exposure'),
  ('CLEAN-SPEC', 'Sanitation Tanker Operator', 'D', 'High', 'Sewage and waste exposure'),
  ('CLEAN-SPEC', 'Sanitation Tanker Operator', 'J', 'Moderate', 'Tanker route driving')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('UTIL', 'OHS Act', 'Framework Act for utility workplaces'),
  ('UTIL', 'Electrical Machinery and Installation Regulations', 'Generation, transmission, distribution, and installation work'),
  ('UTIL', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026'),
  ('UTIL', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('UTIL', 'HCA Regulations, 2021', 'Treatment chemicals, chlorine, fuels, and coal dust context'),
  ('UTIL', 'HBA Regulations, 2022', 'Sewage and raw water biological exposure'),
  ('UTIL', 'Environmental Regulations for Workplaces, 1987', 'Boiler plant and field heat; hot work fitness certification'),
  ('UTIL', 'Ergonomics Regulations, 2019', 'Plant labour and climbing work surveillance'),
  ('UTIL', 'Construction Regulations, 2014', 'Applies to construction phases of utility projects including work at height certification'),
  ('UTIL', 'COIDA', 'Compensation route for utility injuries and diseases'),
  ('UTIL', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('UTIL', 'BCEA night work Code', 'Continuous shift operation'),
  ('UTIL', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('UTIL', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer'),
  ('SEC', 'OHS Act', 'Framework Act for security workplaces'),
  ('SEC', 'BCEA night work Code', 'Night guarding and response shifts: the central working time instrument for this sector'),
  ('SEC', 'NRTA PrDP medical', 'Response and CIT driving categories'),
  ('SEC', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements, including firearm duty fitness'),
  ('SEC', 'COIDA', 'Compensation route including PTSD as an occupational disease per the 2026 amendments'),
  ('SEC', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 where applicable'),
  ('SEC', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('SEC', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('SEC', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer'),
  ('CLEAN', 'OHS Act', 'Framework Act for cleaning service workplaces'),
  ('CLEAN', 'HCA Regulations, 2021', 'Cleaning chemicals and pest control products, with cholinesterase monitoring for organophosphate applicators'),
  ('CLEAN', 'HBA Regulations, 2022', 'Healthcare, biohazard, and sanitation biological exposure'),
  ('CLEAN', 'Ergonomics Regulations, 2019', 'Repetitive cleaning work surveillance'),
  ('CLEAN', 'Construction Regulations, 2014', 'Work at height certification for high level cleaning'),
  ('CLEAN', 'COIDA', 'Compensation route for cleaning service injuries and diseases'),
  ('CLEAN', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('CLEAN', 'BCEA night work Code', 'Early and late shift cleaning'),
  ('CLEAN', 'NRTA PrDP medical', 'Route service driving where applicable'),
  ('CLEAN', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('CLEAN', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('UTIL', 4500, 35, 450, 'placeholder'),
('SEC', 4500, 35, 450, 'placeholder'),
('CLEAN', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['UTIL-GEN','UTIL-WATER','UTIL-RENEW','SEC-GUARD','SEC-ARMED','CLEAN-COMM','CLEAN-SPEC']) loop
    select count(*) into v_roles
      from msp_job_role r join msp_subindustry s on s.id = r.subindustry_id where s.code = v_code;
    select count(*) into v_unmapped
      from msp_job_role r join msp_subindustry s on s.id = r.subindustry_id
     where s.code = v_code
       and not exists (select 1 from msp_job_hazard jh where jh.job_role_id = r.id);
    select count(distinct h.code) into v_unprotocolled
      from msp_job_hazard jh
      join msp_job_role r on r.id = jh.job_role_id
      join msp_subindustry s on s.id = r.subindustry_id
      join msp_hazard h on h.id = jh.hazard_id
     where s.code = v_code
       and not exists (select 1 from msp_test_protocol tp where tp.hazard_id = h.id)
       and h.code not in ('O','N');
    if v_roles < 5 then raise exception 'batch gate: % has only % roles', v_code, v_roles; end if;
    if v_unmapped > 0 then raise exception 'batch gate: % has % unmapped roles', v_code, v_unmapped; end if;
    if v_unprotocolled > 0 then raise exception 'batch gate: % has % unprotocolled hazards', v_code, v_unprotocolled; end if;
    update msp_subindustry set selectable = true where code = v_code;
    raise notice 'batch gate: % enabled (% roles)', v_code, v_roles;
  end loop;
end $$;

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 5: electrical work carries no statutory standing medical battery; the Electrical Machinery Regulations 2011 and Electrical Installation Regulations 2009 anchor the hazard and competency context and the lawful testing basis is EEA section 7. Armed duty and firearm fitness likewise rest on EEA section 7 inherent requirements read with PSIRA registration and firearm competency as statutory competencies, not medical instruments.'
 where item_code = 'CR-12.1';
