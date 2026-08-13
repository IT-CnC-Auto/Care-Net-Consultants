-- CNC MSP FORGE | TAX-BAT-01 v1.0.0 | Phase 6 batch 1: Manufacturing
-- Documentary verification 13/08/2026, subject to OMP ratification. The batch
-- gate at the end of this migration enables selectable subindustries only
-- where the role, hazard, and protocol map is structurally complete, and
-- fails the migration loudly otherwise.

-- 1. Newly verified instruments -------------------------------------------------

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('HBA Regulations, 2022',
 'Regulations for Hazardous Biological Agents, 2022, GN R.1887 of 16 March 2022, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.1887, 16 March 2022', '2022-03-16',
 'In force August 2026. Requires a documented medical surveillance system overseen by an occupational health practitioner where the HBA risk assessment indicates exposure risk with an identifiable disease or effect and a detection technique; all tests per a written medical protocol.',
 'GN R.1887 regulation text, lawlibrary.org.za akn/za/act/gn/2022/r1887 and SAFLII consolidated',
 'Bowmans regulatory analysis and Occupational Health Southern Africa journal review of the 2022 HBA Regulations',
 'Currency check 13/08/2026: in force, no amendment located',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('Lead Regulations, 2001',
 'Lead Regulations, 2001, GN R.236, Government Gazette 23175, 28 February 2002, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.236, GG 23175', '2002-02-28',
 'In force August 2026. Airborne occupational exposure limit for lead 0.15 mg per cubic metre. Medical surveillance with biological monitoring: medical removal at a blood lead of 60 micrograms per decilitre (or 10 micrograms ZPP per gram haemoglobin); for women capable of procreation, removal at 40 and return at 30 micrograms per decilitre.',
 'Consolidated regulation text, SAFLII lr2001148',
 'University occupational medicine teaching note on the Lead Regulations and pathology practice guidance on occupational lead exposure surveillance',
 'Currency check 13/08/2026: in force, no amendment located; reference values corroborated across sources',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('Asbestos Abatement Regulations, 2020',
 'Asbestos Abatement Regulations, 2020, GN R.1196, Government Gazette 43893, 10 November 2020, as amended by GN R.11435, Government Gazette 46380, 20 May 2022, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.1196, GG 43893; amended GN R.11435, GG 46380', '2020-11-10',
 'In force August 2026 as amended 2022. Governs identification, inventory, risk assessment, management plans, notification, and control of asbestos work, with medical surveillance duties for exposed employees.',
 'GN R.1196 gazette text, Department of Employment and Labour published PDF and lawlibrary.org.za akn/za/act/gn/2020/r1196',
 'SAIOSH regulatory notice on the 2020 Regulations and practitioner analyses of the 2022 amendment',
 'Currency check 13/08/2026: in force as amended 20/05/2022',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('FCD Act R638, 2018',
 'Foodstuffs, Cosmetics and Disinfectants Act 54 of 1972, read with the Regulations Governing General Hygiene Requirements for Food Premises, the Transport of Food and Related Matters, GN R.638 of 22 June 2018',
 'regulation', 'GN R.638, 22 June 2018', '2018-06-22',
 'In force August 2026, having replaced R.962. Requires a Certificate of Acceptability for food premises, a person in charge, and trained food handlers, and excludes persons with specified communicable conditions from handling food. The food handler fitness assessment in this kernel serves that exclusion; R.638 prescribes condition based exclusion rather than a fixed certificate interval, so the annual interval is the house floor, not a statutory citation.',
 'GN R.638 regulation text, Department of Health published PDF and gov.za notice',
 'FAO legislative database record and food safety compliance practitioner guidance on R.638',
 'Currency check 13/08/2026: in force, national hygiene standard for food premises',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('Environmental Regulations for Workplaces, 1987',
 'Environmental Regulations for Workplaces, 1987, GN R.2281 of 16 October 1987, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.2281, 16 October 1987', '1987-10-16',
 'In force August 2026. Regulation 2(4): the time weighted average WBGT index shall not exceed 30. Regulation 5(4): where the average WBGT index exceeds 30, workers must be certified fit for work in hot environments, with acclimatisation, hydration, training, and first aid duties on the employer.',
 'GN R.2281 regulation text, SAFLII erfw428 and lawlibrary.org.za akn/za/act/gn/1987/r2281',
 'Department of Employment and Labour published regulation and university occupational hygiene teaching material on heat stress evaluation',
 'Currency check 13/08/2026: in force, no repeal located; the Physical Agents Regulations, 2024 remain staged pending verification of any overlap',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- 2. Hazard upgrades from the verification pass ---------------------------------

update msp_hazard
   set oel_value = 30, oel_unit = 'WBGT index', oel_basis = 'time weighted average WBGT index, regulation 2(4)',
       oel_instrument = 'Environmental Regulations for Workplaces, 1987, GN R.2281; fitness certification for hot work per regulation 5(4)',
       verification_status = 'verified'
 where code = 'H';

insert into msp_hazard (code, name, category, oel_value, oel_unit, oel_basis, oel_instrument, verification_status)
values ('C-PB', 'Lead and inorganic lead compounds', 'chemical', 0.15, 'mg/m3',
        '8 hour time weighted average, Lead Regulations occupational exposure limit',
        'Lead Regulations, 2001, GN R.236', 'verified');

-- 3. New test protocols ---------------------------------------------------------

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id, p.test_name, p.test_type, true, 12, true, p.triggers, p.bio_ref, li.id
from (values
  ('D', 'Food handler fitness assessment', 'clinical',
   'Food handling duties. Serves the communicable condition exclusion under R.638: a person with a specified communicable condition, sores, or discharging lesions must not handle food. Annual interval is the house floor; exclusion applies immediately on presentation.',
   null, 'FCD Act R638, 2018'),
  ('D', 'Occupational biological agent surveillance per written medical protocol', 'clinical',
   'Where the HBA risk assessment indicates exposure risk with an identifiable disease or effect and a detection technique, per the 2022 Regulations; battery set by the OMP protocol.',
   null, 'HBA Regulations, 2022'),
  ('C-PB', 'Blood lead biological monitoring', 'biological_monitoring',
   'All lead exposed employees per the Lead Regulations. Medical removal and return per the verified reference values; women capable of procreation carry the lower removal threshold.',
   'Verified per the Lead Regulations, 2001: medical removal at blood lead 60 micrograms per decilitre (or 10 micrograms ZPP per gram haemoglobin); for women capable of procreation, removal at 40 and return at 30 micrograms per decilitre. Application per individual is the OMP''s clinical determination.',
   'Lead Regulations, 2001'),
  ('C-PB', 'Lead exposure clinical examination (neurological, renal, haematological screen)', 'clinical',
   'All lead exposed employees per the Lead Regulations, alongside blood lead monitoring.',
   null, 'Lead Regulations, 2001')
) as p(hazard_code, test_name, test_type, triggers, bio_ref, basis_short_name)
join msp_hazard h on h.code = p.hazard_code
join msp_legal_instrument li on li.short_name = p.basis_short_name and li.status = 'verified';

-- The heat protocol gains its verified statutory basis.
update msp_test_protocol
   set legal_basis_id = (select id from msp_legal_instrument where short_name = 'Environmental Regulations for Workplaces, 1987'),
       trigger_conditions = 'Work in environments where the time weighted average WBGT index approaches or exceeds 30, per regulations 2(4) and 5(4): fitness certification for hot work, with acclimatisation and hydration duties on the employer. Cold chain work is assessed under the same thermal stress battery.'
 where test_name = 'Heat stress tolerance assessment';

-- 4. Manufacturing taxonomy -----------------------------------------------------

insert into msp_industry (code, name, sic_reference, regulatory_regime)
values ('MANU', 'Manufacturing', 'SIC major division 3, Manufacturing', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i,
     (values
       ('MANU-FOOD',    'Food and beverage manufacturing', 'Batch 1 role map seeded; gate check below'),
       ('MANU-METAL',   'Metals and foundries',            'Batch 1 role map seeded; gate check below'),
       ('MANU-CHEM',    'Chemical manufacturing',          'Role map in a later batch'),
       ('MANU-AUTO',    'Automotive manufacturing',        'Role map in a later batch'),
       ('MANU-TEX',     'Textiles',                        'Role map in a later batch'),
       ('MANU-PLASTIC', 'Plastics',                        'Role map in a later batch'),
       ('MANU-WOOD',    'Wood and furniture',              'Role map in a later batch')
     ) as s(code, name, notes)
where i.code = 'MANU';

-- Food and beverage roles
insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Production Line Operator', 'Operating and monitoring processing and packaging lines', 'Standing for full shifts, repetitive upper limb work', 'Sustained attention, line speed vigilance', 'None beyond induction and food safety training'),
       ('Food Handler / Process Worker', 'Direct handling of ingredients and product', 'Standing, repetitive handling, wet work', 'Hygiene discipline, instruction following', 'Food handler training per R.638'),
       ('Cold Chain / Freezer Worker', 'Work in chillers and freezer stores', 'Cold tolerance, manual handling in low temperatures', 'Instruction following under thermal stress', 'None beyond induction'),
       ('Boiler and Utilities Operator', 'Operating steam boilers, compressors, and plant utilities', 'Heat exposure, plant room access, occasional confined entry', 'Gauge and alarm vigilance', 'Boiler attendance certification as applicable'),
       ('Hygiene and Sanitation Worker', 'Cleaning and sanitising plant with detergents and disinfectants', 'Manual work with chemical handling, wet work', 'Chemical handling discipline', 'None beyond induction and chemical handling training'),
       ('Forklift and Warehouse Operator', 'Materials movement by forklift and pallet truck in stores and yards', 'Prolonged sitting, mounting and dismounting', 'Depth perception, sustained visual attention, no uncontrolled hypoglycaemic risk', 'Forklift operator certification'),
       ('Maintenance Artisan', 'Mechanical and electrical maintenance across the plant', 'Awkward postures, work at height, tool vibration', 'Fine motor control, fault diagnosis', 'Trade certification; wireman''s licence where applicable'),
       ('Shift Supervisor', 'Supervision of production shifts including night shift', 'Walking the floor for full shifts', 'Sustained attention, decision making under pressure', 'None beyond induction')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'MANU-FOOD';

-- Metals and foundries roles
insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Furnace Operator', 'Operating melting and heat treatment furnaces', 'Sustained hot work, heavy manual tasks', 'Vigilance near molten metal, heat discipline', 'Furnace operation competency'),
       ('Foundry Moulder and Caster', 'Sand moulding, pouring, and casting', 'Heavy manual handling in heat and dust', 'Coordination during pours', 'None beyond induction'),
       ('Welder and Fabricator', 'Welding and fabricating steel product', 'Sustained awkward postures, fine motor control', 'Colour vision for weld inspection, attention near arc', 'Trade certification as applicable'),
       ('Machinist', 'Operating lathes, mills, and CNC machines with cutting fluids', 'Standing, repetitive setup work', 'Precision, measurement discipline', 'Trade or operator certification'),
       ('Smelter and Battery Plant Worker', 'Lead smelting, refining, or battery manufacture', 'Heavy manual work in heat with lead exposure', 'Hygiene discipline for lead control', 'None beyond induction and lead awareness training'),
       ('Grinder and Finisher', 'Fettling, grinding, and finishing castings', 'Vibrating tool work, dust exposure', 'Sustained attention with PPE burden', 'None beyond induction'),
       ('Overhead Crane Operator', 'Operating overhead and gantry cranes', 'Cab access climbing, sustained sitting', 'Depth perception, load judgement, no uncontrolled hypoglycaemic risk', 'Crane operator certification'),
       ('Production Supervisor', 'Supervision of foundry and machine shop production', 'Walking the floor, occasional hot area entry', 'Sustained attention, incident response', 'None beyond induction')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'MANU-METAL';

-- Job to hazard maps
insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('MANU-FOOD', 'Production Line Operator', 'A', 'Moderate', 'Packaging and processing line noise'),
  ('MANU-FOOD', 'Production Line Operator', 'I', 'Moderate', 'Repetitive upper limb work at line speed'),
  ('MANU-FOOD', 'Production Line Operator', 'K', 'Moderate', 'Rotating shifts in continuous production'),
  ('MANU-FOOD', 'Food Handler / Process Worker', 'D', 'Moderate', 'Direct food handling; communicable condition exclusion applies'),
  ('MANU-FOOD', 'Food Handler / Process Worker', 'I', 'Moderate', 'Repetitive handling and wet work'),
  ('MANU-FOOD', 'Food Handler / Process Worker', 'C', 'Low', 'Sanitiser and detergent contact'),
  ('MANU-FOOD', 'Cold Chain / Freezer Worker', 'H', 'Moderate', 'Thermal stress in chillers and freezer stores'),
  ('MANU-FOOD', 'Cold Chain / Freezer Worker', 'I', 'Moderate', 'Manual handling in low temperatures'),
  ('MANU-FOOD', 'Boiler and Utilities Operator', 'H', 'Moderate', 'Boiler house heat'),
  ('MANU-FOOD', 'Boiler and Utilities Operator', 'A', 'Moderate', 'Plant room noise'),
  ('MANU-FOOD', 'Boiler and Utilities Operator', 'F', 'Low', 'Occasional confined entry to plant'),
  ('MANU-FOOD', 'Hygiene and Sanitation Worker', 'C', 'Moderate', 'Detergent, sanitiser, and disinfectant handling'),
  ('MANU-FOOD', 'Hygiene and Sanitation Worker', 'D', 'Moderate', 'Cleaning of soiled areas and drains'),
  ('MANU-FOOD', 'Hygiene and Sanitation Worker', 'I', 'Moderate', 'Manual cleaning work'),
  ('MANU-FOOD', 'Forklift and Warehouse Operator', 'J', 'Moderate', 'Forklift operation; site driving fitness'),
  ('MANU-FOOD', 'Forklift and Warehouse Operator', 'G', 'Low', 'Whole body vibration on industrial floors'),
  ('MANU-FOOD', 'Maintenance Artisan', 'A', 'Moderate', 'Plant and tool noise'),
  ('MANU-FOOD', 'Maintenance Artisan', 'G', 'Moderate', 'Hand tool vibration'),
  ('MANU-FOOD', 'Maintenance Artisan', 'M', 'Moderate', 'Electrical maintenance'),
  ('MANU-FOOD', 'Maintenance Artisan', 'E', 'Low', 'Occasional work at height'),
  ('MANU-FOOD', 'Shift Supervisor', 'K', 'Moderate', 'Night shift supervision'),
  ('MANU-FOOD', 'Shift Supervisor', 'A', 'Low', 'Floor noise during supervision'),
  ('MANU-METAL', 'Furnace Operator', 'H', 'High', 'Sustained hot work at melting and heat treatment furnaces'),
  ('MANU-METAL', 'Furnace Operator', 'A', 'High', 'Furnace and plant noise'),
  ('MANU-METAL', 'Furnace Operator', 'C', 'Moderate', 'Metal fume exposure'),
  ('MANU-METAL', 'Foundry Moulder and Caster', 'B', 'High', 'Foundry sand: respirable crystalline silica'),
  ('MANU-METAL', 'Foundry Moulder and Caster', 'H', 'High', 'Radiant heat during pours'),
  ('MANU-METAL', 'Foundry Moulder and Caster', 'I', 'Moderate', 'Heavy manual handling'),
  ('MANU-METAL', 'Welder and Fabricator', 'C', 'High', 'Welding fume including metal oxides'),
  ('MANU-METAL', 'Welder and Fabricator', 'L', 'Moderate', 'Ultraviolet radiation from arc welding'),
  ('MANU-METAL', 'Welder and Fabricator', 'A', 'Moderate', 'Fabrication noise'),
  ('MANU-METAL', 'Machinist', 'C', 'Moderate', 'Cutting fluid mist and skin contact'),
  ('MANU-METAL', 'Machinist', 'A', 'Moderate', 'Machine shop noise'),
  ('MANU-METAL', 'Machinist', 'I', 'Moderate', 'Repetitive setup and standing work'),
  ('MANU-METAL', 'Smelter and Battery Plant Worker', 'C-PB', 'High', 'Lead exposure in smelting, refining, or battery manufacture'),
  ('MANU-METAL', 'Smelter and Battery Plant Worker', 'H', 'High', 'Smelter heat'),
  ('MANU-METAL', 'Smelter and Battery Plant Worker', 'A', 'Moderate', 'Plant noise'),
  ('MANU-METAL', 'Grinder and Finisher', 'A', 'High', 'Grinding and fettling noise'),
  ('MANU-METAL', 'Grinder and Finisher', 'G', 'High', 'Vibrating tool work'),
  ('MANU-METAL', 'Grinder and Finisher', 'B', 'Moderate', 'Casting dust during fettling'),
  ('MANU-METAL', 'Overhead Crane Operator', 'J', 'Moderate', 'Crane operation; load and depth judgement'),
  ('MANU-METAL', 'Overhead Crane Operator', 'A', 'Moderate', 'Overhead plant noise'),
  ('MANU-METAL', 'Production Supervisor', 'A', 'Moderate', 'Floor noise during supervision'),
  ('MANU-METAL', 'Production Supervisor', 'H', 'Low', 'Occasional hot area entry'),
  ('MANU-METAL', 'Production Supervisor', 'B', 'Low', 'Incidental foundry dust')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

-- 5. Building construction: clone the verified civils role family ----------------

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select b.id, r.title, r.duties_summary, r.inherent_physical_demands,
       r.inherent_sensory_cognitive_demands, r.statutory_competency_requirement
from msp_job_role r
join msp_subindustry c on c.id = r.subindustry_id and c.code = 'CONSTR-CIVILS'
join msp_subindustry b on b.code = 'CONSTR-BUILD';

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select nb.id, jh.hazard_id, jh.typical_exposure_rating, jh.rationale
from msp_job_hazard jh
join msp_job_role rc on rc.id = jh.job_role_id
join msp_subindustry c on c.id = rc.subindustry_id and c.code = 'CONSTR-CIVILS'
join msp_subindustry b on b.code = 'CONSTR-BUILD'
join msp_job_role nb on nb.subindustry_id = b.id and nb.title = rc.title;

-- 6. Industry to instrument map for Manufacturing --------------------------------

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('OHS Act', 'Framework Act for all manufacturing workplaces'),
  ('HCA Regulations, 2021', 'Chemical agents across processing, cleaning, cutting fluids, fume, and dust'),
  ('NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026'),
  ('Noise Exposure Regulations, 2024', 'Successor noise instrument, sole operative instrument from 06/09/2026'),
  ('Ergonomics Regulations, 2019', 'Line work, manual handling, and repetitive strain surveillance'),
  ('Environmental Regulations for Workplaces, 1987', 'Thermal stress: WBGT limit and hot work fitness certification; applied to cold chain work by the same battery'),
  ('HBA Regulations, 2022', 'Biological agents in food handling, sanitation, and effluent areas'),
  ('FCD Act R638, 2018', 'Food handler exclusion and hygiene duties in food and beverage manufacturing'),
  ('Lead Regulations, 2001', 'Lead exposed processes: smelting, refining, battery manufacture; blood lead surveillance with verified removal values'),
  ('Asbestos Abatement Regulations, 2020', 'Legacy asbestos in older plant and buildings; applies on identification per the inventory and management plan duties'),
  ('COIDA', 'Compensation route for all manufacturing occupational injuries and diseases'),
  ('EEA section 7', 'Lawful basis for every medical test, justified against the inherent requirements of each job'),
  ('BCEA night work Code', 'Continuous production shifts and night work medicals'),
  ('NRTA PrDP medical', 'Professional driving categories where public road driving applies'),
  ('HPCSA Booklet 1', 'Ethical baseline for all examinations under the programme'),
  ('HPCSA Booklet 10', 'Governs any telehealth component of the programme'),
  ('HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(short_name, note) on true
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
where i.code = 'MANU';

-- 7. Pricing placeholder for Manufacturing (CR-13.14 remains open) ---------------

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status)
values ('MANU', 4500, 35, 450, 'placeholder');

-- 8. Batch gate: enable only structurally complete subindustries -----------------

do $$
declare
  v_code text;
  v_roles int;
  v_unmapped int;
  v_unprotocolled int;
begin
  for v_code in select unnest(array['MANU-FOOD','MANU-METAL','CONSTR-BUILD']) loop
    select count(*) into v_roles
      from msp_job_role r join msp_subindustry s on s.id = r.subindustry_id
     where s.code = v_code;
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
    if v_roles < 5 then
      raise exception 'batch gate: % has only % roles (minimum 5)', v_code, v_roles;
    end if;
    if v_unmapped > 0 then
      raise exception 'batch gate: % has % roles without a hazard map', v_code, v_unmapped;
    end if;
    if v_unprotocolled > 0 then
      raise exception 'batch gate: % uses % hazard codes without any test protocol', v_code, v_unprotocolled;
    end if;
    update msp_subindustry set selectable = true where code = v_code;
    raise notice 'batch gate: % enabled (% roles, complete maps)', v_code, v_roles;
  end loop;
end $$;

-- 9. Register updates ------------------------------------------------------------

update msp_confirmation_item
   set description = description || ' Update 13/08/2026: lead OEL 0.15 mg/m3, blood lead removal values, and the WBGT 30 limit verified; noise, silica, lead, and WBGT now carry verified values. All other OELs remain open.'
 where item_code = 'CR-12.1';

update msp_confirmation_item
   set description = description || ' Update 13/08/2026: Driven Machinery Regulations medical fitness provision could not be corroborated in the documentary pass; DMR stays pending and uncitable. Lifting operator medicals rest on EEA section 7 inherent requirements and the house floor meanwhile.'
 where item_code = 'CR-13.9';
