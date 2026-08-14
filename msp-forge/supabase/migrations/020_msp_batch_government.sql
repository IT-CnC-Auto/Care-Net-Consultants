-- CNC MSP FORGE | TAX-BAT-11 v1.0.0 | Phase 6 batch 11: Government and municipal
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('General Machinery Regulations, 1988',
 'General Machinery Regulations, 1988, GNR 1521, Government Gazette 11443, 5 August 1988, made under the Machinery and Occupational Safety Act 6 of 1983 and kept in force under the Occupational Health and Safety Act 85 of 1993. The Regulations govern machinery supervision, safeguarding, and operation duties for machinery classes not covered by other regulations. They prescribe no standing medical battery: fitness for machinery work rests on EEA section 7 inherent requirements.',
 'regulation', 'GNR 1521, GG 11443, 5 August 1988', '1988-08-05',
 'Published 5 August 1988 under the Machinery and Occupational Safety Act 6 of 1983; carried into force under section 44 of the Occupational Health and Safety Act 85 of 1993. Currency watch: a draft General Machinery Regulation, 2025 was published for public comment (GN 6532, GG 53210, August 2025) with the intention of replacing these Regulations; in force August 2026 pending that process.',
 'Full regulation text, SAFLII gmr272 consolidated version and the published regulation PDF',
 'ILO NATLEX record for GNR 1521 and the Sabinet legislation record confirming GG 11443, 5 August 1988',
 'Currency check 13/08/2026: in force; replacement draft GN 6532, GG 53210 (2025) noted for the verification watchdog',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-02-13', 'verified');

-- Government and municipal industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('GOV', 'Government and municipal', 'SIC major division 9, Community, social and personal services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('GOV', 'GOV-ADMIN', 'Administration and community facilities', 'Batch 11 role map seeded; gate check below'),
  ('GOV', 'GOV-WORKS', 'Public works and technical services',     'Batch 11 role map seeded; gate check below'),
  ('GOV', 'GOV-EMERG', 'Emergency and traffic services',          'Batch 11 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('GOV-ADMIN', 'Municipal Office Administrator', 'Administration, records, and counter services', 'Sustained workstation work', 'Documentation accuracy, public interaction', 'None beyond induction'),
  ('GOV-ADMIN', 'Community Hall and Facility Caretaker', 'Facility opening, cleaning, and minor maintenance', 'Cleaning work with chemical use, furniture handling', 'Facility security vigilance', 'None beyond induction'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'Parks maintenance, mowing, and brush cutting', 'Sustained outdoor labour with powered equipment', 'Equipment and public separation discipline', 'None beyond induction'),
  ('GOV-ADMIN', 'Library and Community Centre Assistant', 'Library services and community programmes', 'Shelving and trolley work', 'Cataloguing accuracy, public interaction', 'None beyond induction'),
  ('GOV-ADMIN', 'Cemetery Worker', 'Grave preparation and grounds maintenance', 'Heavy excavation and grounds labour', 'Procedural dignity, instruction following', 'None beyond induction'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'Pothole repair, verge, and roadworks maintenance', 'Heavy road labour with traffic exposure', 'Traffic vigilance, flag and cone discipline', 'None beyond induction'),
  ('GOV-WORKS', 'Water and Sanitation Artisan', 'Water and sewer reticulation maintenance', 'Excavation and chamber work with sewage contact', 'Gas test discipline, isolation discipline', 'Confined space entry competency where applicable'),
  ('GOV-WORKS', 'Municipal Electrician', 'Public lighting and building electrical maintenance', 'Pole and ladder work, live testing', 'Electrical discipline, no condition with sudden incapacity potential', 'Wireman''s licence as applicable'),
  ('GOV-WORKS', 'Municipal Plant Operator', 'Grader, TLB, and municipal plant operation', 'Sustained plant operation on works sites', 'Machine stability judgement, pedestrian vigilance', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('GOV-WORKS', 'Building Maintenance Artisan', 'Municipal building repairs across trades', 'Ladder access, manual trade work', 'Trade fault diagnosis', 'Trade certification'),
  ('GOV-WORKS', 'Stormwater and Drainage Worker', 'Stormwater culvert and drainage maintenance', 'Culvert entry, heavy debris clearance', 'Gas test discipline in culverts, weather awareness', 'Confined space entry competency where applicable'),
  ('GOV-EMERG', 'Firefighter', 'Structural and veld fire response with breathing apparatus', 'Load bearing work in extreme heat under SCBA, casualty carriage', 'Command discipline under stress, no condition with sudden incapacity potential', 'Firefighter and breathing apparatus certification'),
  ('GOV-EMERG', 'Traffic Officer', 'Traffic enforcement and point duty', 'Prolonged outdoor standing and patrol driving', 'Sustained traffic vigilance, incident composure', 'Traffic officer diploma; driving licence'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'Pre hospital emergency care and patient transport', 'Patient lifting and carriage, response driving', 'Clinical protocol execution under pressure, no uncontrolled hypoglycaemic risk', 'HPCSA emergency care registration; PrDP'),
  ('GOV-EMERG', 'Fire Control Room Operator', 'Emergency call taking and dispatch', 'Sedentary shift duty', 'Sustained call vigilance, dispatch precision', 'None beyond induction'),
  ('GOV-EMERG', 'Disaster Management Officer', 'Disaster risk coordination and incident response', 'Field deployment during incidents, route driving', 'Multi agency coordination, incident command support', 'Driving licence')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('GOV-ADMIN', 'Municipal Office Administrator', 'I', 'Moderate', 'Sustained workstation ergonomic load'),
  ('GOV-ADMIN', 'Community Hall and Facility Caretaker', 'C', 'Moderate', 'Cleaning chemical use'),
  ('GOV-ADMIN', 'Community Hall and Facility Caretaker', 'I', 'Moderate', 'Furniture and equipment handling'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'I', 'High', 'Sustained grounds labour'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'A', 'Moderate', 'Mower and brush cutter noise'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'C', 'Moderate', 'Herbicide application'),
  ('GOV-ADMIN', 'Library and Community Centre Assistant', 'I', 'Moderate', 'Shelving and trolley work'),
  ('GOV-ADMIN', 'Cemetery Worker', 'I', 'High', 'Grave excavation labour'),
  ('GOV-ADMIN', 'Cemetery Worker', 'D', 'Moderate', 'Interment biological context'),
  ('GOV-ADMIN', 'Cemetery Worker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'I', 'High', 'Heavy road repair labour'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'A', 'Moderate', 'Compaction and cutting plant noise'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'B', 'Moderate', 'Road cutting and patching dust'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'H', 'Moderate', 'Roadworks in heat'),
  ('GOV-WORKS', 'Water and Sanitation Artisan', 'D', 'High', 'Sewer reticulation biological exposure'),
  ('GOV-WORKS', 'Water and Sanitation Artisan', 'F', 'Moderate', 'Valve chamber and manhole entry'),
  ('GOV-WORKS', 'Water and Sanitation Artisan', 'C', 'Moderate', 'Treatment chemical contact'),
  ('GOV-WORKS', 'Municipal Electrician', 'M', 'High', 'Public lighting and building electrical work'),
  ('GOV-WORKS', 'Municipal Electrician', 'E', 'Moderate', 'Pole and ladder access'),
  ('GOV-WORKS', 'Municipal Plant Operator', 'J', 'High', 'Municipal plant operation under the Driven Machinery Regulations, 2015'),
  ('GOV-WORKS', 'Municipal Plant Operator', 'A', 'Moderate', 'Plant cab noise'),
  ('GOV-WORKS', 'Municipal Plant Operator', 'B', 'Moderate', 'Works site dust'),
  ('GOV-WORKS', 'Building Maintenance Artisan', 'E', 'Moderate', 'Ladder and roof access'),
  ('GOV-WORKS', 'Building Maintenance Artisan', 'I', 'Moderate', 'Manual trade work'),
  ('GOV-WORKS', 'Building Maintenance Artisan', 'M', 'Moderate', 'Building electrical maintenance'),
  ('GOV-WORKS', 'Stormwater and Drainage Worker', 'F', 'Moderate', 'Culvert and chamber entry'),
  ('GOV-WORKS', 'Stormwater and Drainage Worker', 'D', 'High', 'Stormwater and debris biological exposure'),
  ('GOV-WORKS', 'Stormwater and Drainage Worker', 'I', 'High', 'Heavy debris clearance'),
  ('GOV-EMERG', 'Firefighter', 'H', 'High', 'Structural fire heat under breathing apparatus'),
  ('GOV-EMERG', 'Firefighter', 'I', 'High', 'Load bearing rescue and hose work'),
  ('GOV-EMERG', 'Firefighter', 'E', 'Moderate', 'Aerial appliance and roof work'),
  ('GOV-EMERG', 'Firefighter', 'C', 'Moderate', 'Combustion product exposure'),
  ('GOV-EMERG', 'Firefighter', 'K', 'High', 'Continuous shift and callout duty'),
  ('GOV-EMERG', 'Traffic Officer', 'J', 'Moderate', 'Patrol and pursuit driving'),
  ('GOV-EMERG', 'Traffic Officer', 'H', 'Moderate', 'Prolonged outdoor point duty'),
  ('GOV-EMERG', 'Traffic Officer', 'K', 'Moderate', 'Rotating enforcement shifts'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'D', 'High', 'Patient contact blood and body fluid exposure'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'I', 'High', 'Patient lifting and carriage'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'K', 'High', 'Continuous shift response duty'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'J', 'High', 'Emergency response driving with PrDP requirement'),
  ('GOV-EMERG', 'Fire Control Room Operator', 'K', 'High', 'Standing overnight dispatch duty'),
  ('GOV-EMERG', 'Disaster Management Officer', 'K', 'Moderate', 'Incident activation duty'),
  ('GOV-EMERG', 'Disaster Management Officer', 'J', 'Moderate', 'Field deployment driving')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('GOV', 'OHS Act', 'Framework Act for municipal workplaces'),
  ('GOV', 'General Machinery Regulations, 1988', 'Municipal plant rooms, pump stations, and machinery supervision'),
  ('GOV', 'General Safety Regulations, 1986', 'First aid, PPE, and elevated position duties'),
  ('GOV', 'Driven Machinery Regulations', 'Municipal plant and lifting machine operator certificates'),
  ('GOV', 'Electrical Machinery and Installation Regulations', 'Public lighting and building electrical work'),
  ('GOV', 'HBA Regulations, 2022', 'Sewer, stormwater, cemetery, and patient contact biological exposure'),
  ('GOV', 'HCA Regulations, 2021', 'Herbicides, treatment chemicals, and combustion products'),
  ('GOV', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for plant and grounds equipment'),
  ('GOV', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('GOV', 'Ergonomics Regulations, 2019', 'Road labour, patient handling, and workstation surveillance'),
  ('GOV', 'Environmental Regulations for Workplaces, 1987', 'Outdoor heat, fire heat, and confined atmospheres'),
  ('GOV', 'NRTA PrDP medical', 'Emergency response and municipal driving categories'),
  ('GOV', 'BCEA night work Code', 'Emergency services continuous shifts'),
  ('GOV', 'COIDA', 'Compensation route including PTSD as an occupational disease per the 2026 amendments for emergency personnel'),
  ('GOV', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('GOV', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('GOV', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('GOV', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['GOV-ADMIN','GOV-WORKS','GOV-EMERG']) loop
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

-- Register updates

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 11: the General Machinery Regulations, 1988 (GNR 1521, GG 11443, 5 August 1988) are now triple verified, closing a third leg of this item; the General Administrative Regulations remain open. A replacement draft General Machinery Regulation, 2025 (GN 6532, GG 53210) is in public comment and is held on the verification watchdog.'
 where item_code = 'CR-13.9';

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 11: firefighter and emergency care fitness rests on EEA section 7 inherent requirements read with service certification; no national statutory firefighter medical standard is stored, and any municipal or SANS 10090 aligned standard supplied by the client tightens the role protocol at review. Emergency services psychosocial load is carried in the OREP narrative with COIDA PTSD recognition noted.'
 where item_code = 'CR-12.1';
