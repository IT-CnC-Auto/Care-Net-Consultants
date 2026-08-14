-- CNC MSP FORGE | TAX-BAT-02 v1.0.0 | Phase 6 batch 2: Mining
-- The MHSA regime enters the kernel: statutory fitness to perform work,
-- ODMWA compensation routing for mining lung disease, and the first
-- subindustries under the DUAL compensation logic. Documentary verification
-- 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('MHSA',
 'Mine Health and Safety Act 29 of 1996, section 13 medical surveillance provisions',
 'act', null, '1997-01-15',
 'In force August 2026. Section 13: the employer must establish and maintain a system of medical surveillance of employees exposed to health hazards, consisting of an initial medical examination and further examinations at appropriate intervals; persons working at a mine must be declared medically fit before performing work.',
 'Consolidated Act text, SAFLII mhasa1996192 and the Mine Health and Safety Council published Act and Regulations booklet',
 'DMRE published guidance and university occupational health teaching material on MHSA medical surveillance',
 'Currency check 13/08/2026: in force, administered by the DMRE; no repeal located',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('Fitness to Perform Work Guideline (MHSA)',
 'Guideline for the Compilation of a Mandatory Code of Practice on the Minimum Standards of Fitness to Perform Work at a Mine, GN R.147, Government Gazette 39656, 5 February 2016, effective 30 June 2016, DMRE reference DMR 16/3/2/3-A3',
 'guideline', 'GN R.147, GG 39656; DMR 16/3/2/3-A3', '2016-06-30',
 'First issued 1 March 2003, last revised 30 June 2013, gazetted 5 February 2016 with effect from 30 June 2016. Guides Occupational Medical Practitioners in determining fitness to perform specified work at a mine; every mine must compile its mandatory Code of Practice on these minimum standards.',
 'DMRE published guideline PDF, dmre.gov.za mandatory Codes of Practice resource centre',
 'gov.za gazette notice record and industry mandatory Code of Practice registers referencing the guideline',
 'Currency check 13/08/2026: effective instrument for mandatory Codes of Practice on fitness to perform work; no successor located',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('ODMWA',
 'Occupational Diseases in Mines and Works Act 78 of 1973',
 'act', null, '1973-10-01',
 'In force August 2026, last substantively amended 1994 and further amended by the National Health Insurance Act 20 of 2023 (currency watch). Administered by the Medical Bureau for Occupational Diseases under the Department of Health: certification of compensable cardio respiratory organ disease in miners and ex miners, benefit medical examinations (two yearly for ex miners at accredited facilities), and lump sum compensation by degree of impairment. Mining lung disease routes here; all other conditions route to COIDA.',
 'Consolidated Act text, SAFLII odimawa1973385 and gov.za Act record',
 'NICD compensation systems guidance and the occupational lung disease collaboration compensation framework material on MBOD benefit examinations',
 'Currency check 13/08/2026: in force; NHI Act 20 of 2023 amendment recorded for review at the next verification cycle',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-02-13', 'verified');

-- Statutory mine fitness as a mapped hazard so every mining role composes the
-- certificate of fitness battery through the existing engine.
insert into msp_hazard (code, name, category, oel_value, oel_unit, oel_basis, oel_instrument, verification_status)
values ('Q', 'Statutory fitness to perform work at a mine', 'physical', null, null,
        'Not an exposure limit: a statutory fitness determination under MHSA section 13 and the mine''s mandatory Code of Practice',
        'Mine Health and Safety Act 29 of 1996 section 13; Fitness to Perform Work Guideline, GN R.147',
        'unverified');

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id, p.test_name, 'clinical', true, 12, true, p.triggers, null, li.id
from (values
  ('Q', 'Mine certificate of fitness examination (initial, periodic, and exit per the mandatory Code of Practice)',
   'All persons performing work at a mine, per MHSA section 13 and the mine''s mandatory Code of Practice on minimum standards of fitness. Initial examination and fitness declaration before work begins; periodic at least annually; exit examination on termination of service at the mine.',
   'Fitness to Perform Work Guideline (MHSA)'),
  ('B', 'ODMWA benefit examination battery: chest X-ray with lung function for dust exposed mine workers',
   'Dust exposed mine workers under the ODMWA certification system. In service surveillance at least annually; on exit, the benefit examination record supports MBOD certification, and ex miners remain entitled to two yearly benefit medical examinations at accredited facilities.',
   'ODMWA'),
  ('H', 'Heat tolerance screening for hot underground workings',
   'Underground work in hot workings per the mine''s thermal management programme and mandatory Code of Practice; screening and acclimatisation before placement in hot workings and on return after absence.',
   'MHSA')
) as p(hazard_code, test_name, triggers, basis_short_name)
join msp_hazard h on h.code = p.hazard_code
join msp_legal_instrument li on li.short_name = p.basis_short_name and li.status = 'verified';

insert into msp_industry (code, name, sic_reference, regulatory_regime)
values ('MINING', 'Mining', 'SIC major division 2, Mining and quarrying', 'MHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i,
     (values
       ('MIN-GOLD',    'Gold mining',        'Batch 2 role map seeded; gate check below'),
       ('MIN-QUARRY',  'Quarrying',          'Batch 2 role map seeded; gate check below'),
       ('MIN-PLAT',    'Platinum mining',    'Role map in a later batch'),
       ('MIN-COAL',    'Coal mining',        'Role map in a later batch'),
       ('MIN-CHROME',  'Chrome mining',      'Role map in a later batch'),
       ('MIN-DIAMOND', 'Diamond mining',     'Role map in a later batch')
     ) as s(code, name, notes)
where i.code = 'MINING';

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Rock Drill Operator', 'Operating pneumatic and hydraulic rock drills at the face', 'Heavy sustained physical work in heat and confined stopes', 'Vigilance for ground conditions under noise and heat load', 'Mine certificate of fitness; heat tolerance clearance for hot workings'),
       ('Stoping and Development Crew', 'Face preparation, support installation, cleaning and sweeping', 'Heavy manual work in heat, awkward postures underground', 'Instruction following under demanding conditions', 'Mine certificate of fitness'),
       ('Winding Engine Driver', 'Operating the winder conveying persons and material', 'Sustained seated vigilance', 'Unimpaired vision and hearing, sustained concentration, no condition with sudden incapacity potential', 'Winding engine driver certificate; mine certificate of fitness'),
       ('LHD and Locomotive Operator', 'Operating load haul dump machines and underground locomotives', 'Whole body vibration, sustained operation underground', 'Depth perception, reaction time, no uncontrolled hypoglycaemic risk', 'Operator competency; mine certificate of fitness'),
       ('Shaft Timberman and Support Crew', 'Installing and maintaining shaft and excavation support', 'Climbing, rigging, heavy manual handling in shafts', 'Spatial awareness, no vertigo', 'Working at heights competency; mine certificate of fitness'),
       ('Underground Miner (blasting certificate)', 'Supervising the working place, charging up and blasting', 'Extensive underground travel, work in heat and dust', 'Judgement under pressure, gas testing vigilance', 'Blasting certificate; mine certificate of fitness'),
       ('Metallurgical Plant Operator', 'Operating surface gold plant including cyanidation circuits', 'Plant rounds, chemical handling', 'Chemical handling discipline, alarm response', 'Plant competency; mine certificate of fitness'),
       ('Occupational Hygiene Assistant', 'Dust, heat, and ventilation measurements underground', 'Extensive underground travel', 'Measurement discipline and recording accuracy', 'Mine certificate of fitness')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'MIN-GOLD';

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Quarry Supervisor', 'Supervision of quarry benches, plant, and loading operations', 'Walking benches and plant areas', 'Sustained attention, incident response', 'Mine certificate of fitness'),
       ('Blaster (surface)', 'Drilling pattern checks, charging, and surface blasting', 'Manual work on benches in weather', 'Judgement under pressure, exclusion discipline', 'Blasting certificate for surface excavations; mine certificate of fitness'),
       ('Drill Rig Operator', 'Operating production drill rigs on benches', 'Vibration, dust exposure at the collar', 'Sustained visual attention', 'Operator competency; mine certificate of fitness'),
       ('Excavator and Loader Operator', 'Loading blasted rock to trucks', 'Whole body vibration, prolonged sitting', 'Depth perception, load judgement', 'Operator competency; mine certificate of fitness'),
       ('Dump Truck Driver', 'Hauling rock from benches to the crusher', 'Prolonged sitting, mounting and dismounting', 'Sustained visual attention, reaction time, no uncontrolled hypoglycaemic risk', 'Operator competency; PrDP where public roads are used; mine certificate of fitness'),
       ('Crusher Plant Operator', 'Operating crushing and screening plant', 'Plant rounds with dust and noise exposure', 'Alarm vigilance, lockout discipline', 'Plant competency; mine certificate of fitness'),
       ('Workshop Artisan', 'Maintaining mobile plant and fixed equipment', 'Heavy component handling, tool vibration', 'Fine motor control, fault diagnosis', 'Trade certification; mine certificate of fitness')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'MIN-QUARRY';

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('MIN-GOLD', 'Rock Drill Operator', 'B', 'High', 'Silica bearing rock dust at the face'),
  ('MIN-GOLD', 'Rock Drill Operator', 'A', 'High', 'Rock drill noise'),
  ('MIN-GOLD', 'Rock Drill Operator', 'G', 'High', 'Hand arm vibration from drilling'),
  ('MIN-GOLD', 'Rock Drill Operator', 'H', 'High', 'Hot underground workings'),
  ('MIN-GOLD', 'Rock Drill Operator', 'Q', 'High', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'B', 'High', 'Silica bearing dust in stopes and development ends'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'A', 'Moderate to High', 'Working near drilling and scraper operations'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'I', 'High', 'Heavy manual work in confined stopes'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'H', 'High', 'Hot underground workings'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'Q', 'High', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Winding Engine Driver', 'A', 'Moderate', 'Winder house noise'),
  ('MIN-GOLD', 'Winding Engine Driver', 'K', 'Moderate', 'Shift operation of the winder'),
  ('MIN-GOLD', 'Winding Engine Driver', 'Q', 'High', 'Safety critical statutory fitness: persons conveyance'),
  ('MIN-GOLD', 'LHD and Locomotive Operator', 'G', 'High', 'Whole body vibration underground'),
  ('MIN-GOLD', 'LHD and Locomotive Operator', 'A', 'High', 'Machine noise in confined excavations'),
  ('MIN-GOLD', 'LHD and Locomotive Operator', 'C', 'Moderate', 'Diesel particulate exposure underground'),
  ('MIN-GOLD', 'LHD and Locomotive Operator', 'Q', 'High', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Shaft Timberman and Support Crew', 'E', 'High', 'Work in shafts with fall risk'),
  ('MIN-GOLD', 'Shaft Timberman and Support Crew', 'I', 'High', 'Heavy support material handling'),
  ('MIN-GOLD', 'Shaft Timberman and Support Crew', 'B', 'Moderate', 'Shaft dust'),
  ('MIN-GOLD', 'Shaft Timberman and Support Crew', 'Q', 'High', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Underground Miner (blasting certificate)', 'B', 'High', 'Dust across working places'),
  ('MIN-GOLD', 'Underground Miner (blasting certificate)', 'A', 'Moderate to High', 'Working place noise'),
  ('MIN-GOLD', 'Underground Miner (blasting certificate)', 'H', 'High', 'Hot underground workings'),
  ('MIN-GOLD', 'Underground Miner (blasting certificate)', 'Q', 'High', 'Statutory fitness including blasting duties'),
  ('MIN-GOLD', 'Metallurgical Plant Operator', 'C', 'High', 'Cyanide and process chemical exposure in the gold plant'),
  ('MIN-GOLD', 'Metallurgical Plant Operator', 'A', 'Moderate', 'Milling and plant noise'),
  ('MIN-GOLD', 'Metallurgical Plant Operator', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Occupational Hygiene Assistant', 'B', 'Moderate', 'Underground travel through dusty workings'),
  ('MIN-GOLD', 'Occupational Hygiene Assistant', 'H', 'Moderate', 'Measurement rounds in hot workings'),
  ('MIN-GOLD', 'Occupational Hygiene Assistant', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Quarry Supervisor', 'B', 'Moderate', 'Bench and plant dust'),
  ('MIN-QUARRY', 'Quarry Supervisor', 'A', 'Moderate', 'Plant and blasting noise'),
  ('MIN-QUARRY', 'Quarry Supervisor', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Blaster (surface)', 'B', 'Moderate', 'Drilling and blasting dust'),
  ('MIN-QUARRY', 'Blaster (surface)', 'A', 'High', 'Blasting operations noise'),
  ('MIN-QUARRY', 'Blaster (surface)', 'Q', 'High', 'Statutory fitness including blasting duties'),
  ('MIN-QUARRY', 'Drill Rig Operator', 'B', 'High', 'Silica dust at the drill collar'),
  ('MIN-QUARRY', 'Drill Rig Operator', 'A', 'High', 'Drill rig noise'),
  ('MIN-QUARRY', 'Drill Rig Operator', 'G', 'Moderate', 'Rig vibration'),
  ('MIN-QUARRY', 'Drill Rig Operator', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Excavator and Loader Operator', 'G', 'Moderate to High', 'Whole body vibration on benches'),
  ('MIN-QUARRY', 'Excavator and Loader Operator', 'A', 'Moderate', 'Machine noise'),
  ('MIN-QUARRY', 'Excavator and Loader Operator', 'B', 'Moderate', 'Loading dust'),
  ('MIN-QUARRY', 'Excavator and Loader Operator', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Dump Truck Driver', 'J', 'Moderate', 'Haul road driving; PrDP where public roads are used'),
  ('MIN-QUARRY', 'Dump Truck Driver', 'G', 'Moderate', 'Haul road vibration'),
  ('MIN-QUARRY', 'Dump Truck Driver', 'B', 'Moderate', 'Haul road dust'),
  ('MIN-QUARRY', 'Dump Truck Driver', 'Q', 'High', 'Safety critical statutory fitness'),
  ('MIN-QUARRY', 'Crusher Plant Operator', 'B', 'High', 'Crushing and screening dust'),
  ('MIN-QUARRY', 'Crusher Plant Operator', 'A', 'High', 'Crusher noise'),
  ('MIN-QUARRY', 'Crusher Plant Operator', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Workshop Artisan', 'A', 'Moderate', 'Workshop noise'),
  ('MIN-QUARRY', 'Workshop Artisan', 'G', 'Moderate', 'Tool vibration'),
  ('MIN-QUARRY', 'Workshop Artisan', 'M', 'Moderate', 'Electrical maintenance'),
  ('MIN-QUARRY', 'Workshop Artisan', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('MHSA', 'Framework Act: section 13 medical surveillance and fitness declaration before work'),
  ('Fitness to Perform Work Guideline (MHSA)', 'The mine''s mandatory Code of Practice on minimum standards of fitness governs every certificate of fitness under this Plan'),
  ('ODMWA', 'Compensation route for compensable mining lung disease via MBOD certification; all other conditions route to COIDA'),
  ('COIDA', 'Compensation route for occupational injuries and non ODMWA diseases at the mine'),
  ('NIHL Regulations, 2003', 'Noise instrument reference to 05/09/2026; mine noise duties under MHSA regulations are read with the mine Code of Practice'),
  ('Noise Exposure Regulations, 2024', 'Successor OHSA side noise instrument from 06/09/2026, for works not under MHSA'),
  ('Ergonomics Regulations, 2019', 'Applied by analogy for surface works under OHSA; underground ergonomic risk managed under the mine Code of Practice'),
  ('EEA section 7', 'Lawful basis for every medical test, justified against the inherent requirements of each job'),
  ('BCEA night work Code', 'Continuous mining shifts and night work medicals'),
  ('NRTA PrDP medical', 'Professional driving categories using public roads'),
  ('HPCSA Booklet 1', 'Ethical baseline for all examinations under the programme'),
  ('HPCSA Booklet 10', 'Governs any telehealth component of the programme'),
  ('HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(short_name, note) on true
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
where i.code = 'MINING';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status)
values ('MINING', 6500, 45, 550, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['MIN-GOLD','MIN-QUARRY']) loop
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
       and h.code not in ('O');
    if v_roles < 5 then raise exception 'batch gate: % has only % roles', v_code, v_roles; end if;
    if v_unmapped > 0 then raise exception 'batch gate: % has % unmapped roles', v_code, v_unmapped; end if;
    if v_unprotocolled > 0 then raise exception 'batch gate: % has % unprotocolled hazards', v_code, v_unprotocolled; end if;
    update msp_subindustry set selectable = true where code = v_code;
    raise notice 'batch gate: % enabled (% roles)', v_code, v_roles;
  end loop;
end $$;

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 2: mining exposure limits under the MHSA regulations (dust, noise, thermal for underground workings) remain open; the kernel applies the mine Code of Practice and OMP determination meanwhile. ODMWA amendment by the NHI Act 20 of 2023 is on the currency watch for the next verification cycle.'
 where item_code = 'CR-12.1';