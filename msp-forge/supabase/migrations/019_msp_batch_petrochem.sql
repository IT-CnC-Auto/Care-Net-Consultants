-- CNC MSP FORGE | TAX-BAT-10 v1.0.0 | Phase 6 batch 10: Petrochemical and fuel retail
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('MHI Regulations, 2022',
 'Major Hazard Installation Regulations, 2022, GN R.2989, Regulation Gazette 11536, Government Gazette 47970, in operation 31 January 2023, made under section 43 of the Occupational Health and Safety Act 85 of 1993, repealing the Major Hazard Installation Regulations, 2001 (GN R.692 of 30 July 2001). The Regulations govern risk assessments, emergency plans, and duties at installations holding threshold quantities of hazardous substances. They prescribe no standing medical battery: worker surveillance at major hazard installations rests on the HCA and companion OHSA instruments and the lawful testing basis is EEA section 7, with these Regulations anchoring the installation risk context.',
 'regulation', 'GN R.2989, RG 11536, GG 47970; in operation 31 January 2023', '2023-01-31',
 'Promulgated 31 January 2023 with immediate repeal of the 2001 Regulations; correction notice GN 3420, GG 48627, 19 May 2023. In force August 2026.',
 'Promulgation notice text as published (department notification PDF) and the official gov.za regulations publication',
 'Attorney commentaries (ENS, Lexology, and Mondaq records) confirming GN R.2989, RG 11536, GG 47970, in operation 31 January 2023, repealing GN R.692 of 30 July 2001',
 'Currency check 13/08/2026: in force; correction notice GN 3420 of 19 May 2023 recorded',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- Petrochemical and fuel retail industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('PETRO', 'Petrochemical and fuel retail', 'SIC major divisions 3 and 6, Coke, refined petroleum products and fuel trade', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('PETRO', 'PETRO-BULK',   'Refining, terminals and depots',        'Batch 10 role map seeded; gate check below'),
  ('PETRO', 'PETRO-RETAIL', 'Service stations and convenience',      'Batch 10 role map seeded; gate check below'),
  ('PETRO', 'PETRO-GAS',    'LPG and industrial gases distribution', 'Batch 10 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('PETRO-BULK', 'Process Operator (refinery and terminal)', 'Process unit and terminal operation with benzene and hydrocarbon exposure', 'Plant rounds in heat and noise, valve and sampling work', 'Alarm vigilance across shifts, permit to work discipline', 'Plant operation competency'),
  ('PETRO-BULK', 'Tank Farm Operator', 'Tank gauging, switching, and tank entry support', 'Gantry and stair access, occasional confined entry support', 'Gas test discipline, spill response', 'Confined space entry competency where applicable'),
  ('PETRO-BULK', 'Loading Gantry Operator', 'Road and rail tanker loading operations', 'Gantry climbing, hose and arm handling', 'Loading sequence precision, vapour control discipline', 'None beyond induction'),
  ('PETRO-BULK', 'Fuel Tanker Driver (bulk)', 'Bulk fuel delivery from depot to site', 'Prolonged driving, hose handling at offloading', 'Route vigilance, dangerous goods discipline, no uncontrolled hypoglycaemic risk', 'PrDP with dangerous goods category'),
  ('PETRO-BULK', 'Instrument and Electrical Technician (plant)', 'Instrumented systems and electrical maintenance in classified zones', 'Plant access, fine panel work', 'Intrinsic safety discipline, fault diagnosis', 'Trade certification'),
  ('PETRO-BULK', 'Laboratory Analyst (fuels)', 'Fuel quality testing with solvent handling', 'Bench work with sample handling', 'Analytical precision, fume control discipline', 'None beyond induction'),
  ('PETRO-RETAIL', 'Petrol Attendant', 'Forecourt fuelling and customer service', 'Standing forecourt shifts with fuel vapour exposure', 'Vehicle and customer vigilance, spill response', 'None beyond induction'),
  ('PETRO-RETAIL', 'Forecourt Supervisor', 'Forecourt operations and offloading supervision', 'Forecourt rounds across shifts', 'Offloading supervision discipline, incident response', 'None beyond induction'),
  ('PETRO-RETAIL', 'Convenience Store Assistant', 'Store service including food preparation areas', 'Standing shifts, stock handling', 'Till accuracy, food hygiene discipline', 'None beyond induction'),
  ('PETRO-RETAIL', 'Car Wash Attendant', 'Vehicle washing and valet services', 'Sustained wet work with detergents', 'Chemical label discipline', 'None beyond induction'),
  ('PETRO-RETAIL', 'Site Maintenance Handyman', 'Forecourt and building maintenance', 'Ladder work, pump and canopy maintenance', 'Electrical and permit discipline', 'None beyond induction'),
  ('PETRO-GAS', 'LPG Filling Plant Operator', 'Cylinder and bulk LPG filling operations', 'Cylinder handling at rate, filling carousel work', 'Leak detection vigilance, filling mass precision', 'None beyond induction'),
  ('PETRO-GAS', 'Cylinder Handler and Yard Worker', 'Cylinder loading, stacking, and yard logistics', 'Sustained heavy cylinder handling', 'Stacking and segregation discipline', 'None beyond induction'),
  ('PETRO-GAS', 'Gas Tanker Driver', 'Bulk LPG and industrial gas delivery', 'Prolonged driving, hose and coupling work', 'Route vigilance, dangerous goods discipline, no uncontrolled hypoglycaemic risk', 'PrDP with dangerous goods category'),
  ('PETRO-GAS', 'Cylinder Inspector and Tester', 'Cylinder inspection, testing, and revalidation', 'Test bay handling, valve work', 'Defect recognition, test discipline', 'None beyond induction'),
  ('PETRO-GAS', 'Industrial Gases Production Technician', 'Air separation and gas production plant operation', 'Plant rounds with cryogenic systems', 'Cryogenic and pressure discipline, alarm vigilance', 'Plant operation competency')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('PETRO-BULK', 'Process Operator (refinery and terminal)', 'C', 'High', 'Benzene and hydrocarbon process exposure with HCA biological monitoring'),
  ('PETRO-BULK', 'Process Operator (refinery and terminal)', 'A', 'Moderate', 'Process unit noise'),
  ('PETRO-BULK', 'Process Operator (refinery and terminal)', 'H', 'Moderate', 'Process unit heat'),
  ('PETRO-BULK', 'Process Operator (refinery and terminal)', 'K', 'Moderate', 'Continuous shift operation'),
  ('PETRO-BULK', 'Tank Farm Operator', 'C', 'High', 'Tank farm hydrocarbon and vapour exposure'),
  ('PETRO-BULK', 'Tank Farm Operator', 'F', 'Moderate', 'Tank entry support work'),
  ('PETRO-BULK', 'Tank Farm Operator', 'E', 'Moderate', 'Gantry and tank stair access'),
  ('PETRO-BULK', 'Loading Gantry Operator', 'C', 'Moderate', 'Loading vapour exposure'),
  ('PETRO-BULK', 'Loading Gantry Operator', 'I', 'Moderate', 'Hose and loading arm handling'),
  ('PETRO-BULK', 'Loading Gantry Operator', 'E', 'Moderate', 'Gantry top access'),
  ('PETRO-BULK', 'Fuel Tanker Driver (bulk)', 'J', 'High', 'Dangerous goods bulk fuel driving with PrDP requirement'),
  ('PETRO-BULK', 'Fuel Tanker Driver (bulk)', 'C', 'Moderate', 'Fuel vapour exposure at loading and offloading'),
  ('PETRO-BULK', 'Fuel Tanker Driver (bulk)', 'K', 'Moderate', 'Early and night delivery windows'),
  ('PETRO-BULK', 'Instrument and Electrical Technician (plant)', 'M', 'High', 'Electrical work in classified zones'),
  ('PETRO-BULK', 'Instrument and Electrical Technician (plant)', 'C', 'Moderate', 'Process area chemical exposure'),
  ('PETRO-BULK', 'Laboratory Analyst (fuels)', 'C', 'Moderate', 'Solvent and fuel sample handling'),
  ('PETRO-RETAIL', 'Petrol Attendant', 'C', 'Moderate', 'Forecourt fuel vapour exposure including benzene context'),
  ('PETRO-RETAIL', 'Petrol Attendant', 'H', 'Moderate', 'Outdoor forecourt work'),
  ('PETRO-RETAIL', 'Petrol Attendant', 'K', 'Moderate', 'Rotating forecourt shifts'),
  ('PETRO-RETAIL', 'Forecourt Supervisor', 'C', 'Moderate', 'Forecourt and offloading vapour exposure'),
  ('PETRO-RETAIL', 'Forecourt Supervisor', 'K', 'Moderate', 'Shift supervision'),
  ('PETRO-RETAIL', 'Convenience Store Assistant', 'K', 'Moderate', 'Extended trading hours'),
  ('PETRO-RETAIL', 'Convenience Store Assistant', 'I', 'Moderate', 'Stock handling and standing shifts'),
  ('PETRO-RETAIL', 'Convenience Store Assistant', 'D', 'Low', 'Food preparation area work under R638 of 2018'),
  ('PETRO-RETAIL', 'Car Wash Attendant', 'C', 'Moderate', 'Detergent and degreaser wet work'),
  ('PETRO-RETAIL', 'Car Wash Attendant', 'I', 'Moderate', 'Sustained washing and valet work'),
  ('PETRO-RETAIL', 'Site Maintenance Handyman', 'M', 'Moderate', 'Pump and canopy electrical maintenance'),
  ('PETRO-RETAIL', 'Site Maintenance Handyman', 'E', 'Moderate', 'Ladder and canopy access'),
  ('PETRO-GAS', 'LPG Filling Plant Operator', 'C', 'High', 'LPG filling exposure with leak risk'),
  ('PETRO-GAS', 'LPG Filling Plant Operator', 'A', 'Moderate', 'Filling carousel noise'),
  ('PETRO-GAS', 'LPG Filling Plant Operator', 'I', 'Moderate', 'Cylinder handling at rate'),
  ('PETRO-GAS', 'Cylinder Handler and Yard Worker', 'I', 'High', 'Sustained heavy cylinder handling'),
  ('PETRO-GAS', 'Cylinder Handler and Yard Worker', 'C', 'Moderate', 'Yard LPG exposure'),
  ('PETRO-GAS', 'Gas Tanker Driver', 'J', 'High', 'Dangerous goods gas driving with PrDP requirement'),
  ('PETRO-GAS', 'Gas Tanker Driver', 'C', 'Moderate', 'Coupling and transfer exposure'),
  ('PETRO-GAS', 'Gas Tanker Driver', 'K', 'Moderate', 'Long haul delivery windows'),
  ('PETRO-GAS', 'Cylinder Inspector and Tester', 'C', 'Moderate', 'Residual gas and valve work'),
  ('PETRO-GAS', 'Cylinder Inspector and Tester', 'A', 'Moderate', 'Test bay noise'),
  ('PETRO-GAS', 'Industrial Gases Production Technician', 'C', 'Moderate', 'Process gas exposure'),
  ('PETRO-GAS', 'Industrial Gases Production Technician', 'M', 'Moderate', 'Plant electrical systems'),
  ('PETRO-GAS', 'Industrial Gases Production Technician', 'H', 'Moderate', 'Cryogenic cold exposure as thermal stress'),
  ('PETRO-GAS', 'Industrial Gases Production Technician', 'K', 'Moderate', 'Continuous plant shifts')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('PETRO', 'OHS Act', 'Framework Act for petrochemical and fuel workplaces'),
  ('PETRO', 'MHI Regulations, 2022', 'Major hazard installation risk assessment and emergency plan context for refineries, terminals, and gas plants'),
  ('PETRO', 'HCA Regulations, 2021', 'Benzene and hydrocarbon exposure with biological monitoring per the BEI annexure'),
  ('PETRO', 'General Safety Regulations, 1986', 'First aid, PPE, and elevated position duties'),
  ('PETRO', 'Electrical Machinery and Installation Regulations', 'Classified zone electrical work context'),
  ('PETRO', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for process units and filling plants'),
  ('PETRO', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('PETRO', 'Environmental Regulations for Workplaces, 1987', 'Process heat and cryogenic thermal environments'),
  ('PETRO', 'Ergonomics Regulations, 2019', 'Cylinder and hose handling surveillance'),
  ('PETRO', 'Driven Machinery Regulations', 'Terminal and yard lifting machine operator certificates'),
  ('PETRO', 'NRTA PrDP medical', 'Dangerous goods driving categories'),
  ('PETRO', 'Food Premises Hygiene Regulations, R638 of 2018', 'Convenience store food preparation areas'),
  ('PETRO', 'BCEA night work Code', 'Continuous plant shifts and forecourt night trading'),
  ('PETRO', 'COIDA', 'Compensation route for petrochemical injuries and diseases'),
  ('PETRO', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('PETRO', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('PETRO', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('PETRO', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['PETRO-BULK','PETRO-RETAIL','PETRO-GAS']) loop
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
   set description = description || ' Update 13/08/2026 batch 10: benzene biological monitoring for process and forecourt exposure anchors to the HCA Regulations, 2021 BEI annexure with values applied from the annexure at examination; no memorised benzene values are stored. The MHI Regulations, 2022 anchor installation risk context only and prescribe no medical battery.'
 where item_code = 'CR-12.1';
