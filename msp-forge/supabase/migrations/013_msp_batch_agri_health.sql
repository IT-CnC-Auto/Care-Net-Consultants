-- CNC MSP FORGE | TAX-BAT-04 v1.0.0 | Phase 6 batch 4: Agriculture and forestry, Healthcare and laboratories
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('Hazardous Substances Act (radiation control)',
 'Hazardous Substances Act 15 of 1973, Group III and Group IV hazardous substances provisions for ionising radiation, administered by the SAHPRA Radiation Control programme',
 'act', null, '1973-04-01',
 'In force August 2026. Electronic generators of ionising radiation are Group III and radioactive sources Group IV hazardous substances; regulatory control, licensing, personal dose monitoring, and radiation worker protection run through SAHPRA Radiation Control (formerly the Department of Health Directorate Radiation Control), including the published radiation monitoring requirements guideline. Dose limits and monitoring conditions are applied from the licence and the SAHPRA guideline at examination time, never from memory.',
 'Consolidated Act text, SAFLII hsa1973238 and gov.za Act record',
 'SAHPRA Radiation Control programme pages and the published SAHPRA radiation monitoring requirements guideline; peer reviewed South African radiation protection legislation reviews',
 'Currency check 13/08/2026: in force; regulatory mandate transferred to SAHPRA; no repeal located',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- Hazard L gains its verified instrument anchor (dose limit values stay with the licence).
update msp_hazard
   set oel_instrument = 'Hazardous Substances Act 15 of 1973, SAHPRA Radiation Control licensing and dose monitoring framework; dose limits per licence conditions'
 where code = 'L';

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id, p.test_name, p.test_type, true, 12, true, p.triggers, p.bio_ref, li.id
from (values
  ('C', 'Cholinesterase biological effect monitoring (plasma and erythrocyte) for organophosphate pesticide exposure', 'biological_effect',
   'Employees applying or mixing organophosphate pesticides, per the HCA Regulations, 2021 biological monitoring provisions. Pre season individual baseline, in season monitoring per the spraying programme, and removal on significant depression per the OMP''s protocol.',
   'Per the biological exposure indices annexure of the HCA Regulations, 2021, applied from the annexure at examination; interpretation against the individual pre exposure baseline is the OMP''s clinical determination.',
   'HCA Regulations, 2021'),
  ('D', 'Occupational tuberculosis screening (symptom screen with investigation per written protocol)', 'clinical',
   'Healthcare, laboratory, and congregate setting workers with occupational tuberculosis exposure risk per the HBA risk assessment; annual floor with immediate investigation on symptoms or contact.',
   null, 'HBA Regulations, 2022'),
  ('D', 'Hepatitis B immunity verification and vaccination pathway', 'clinical',
   'Blood and body fluid exposed workers per the HBA risk assessment: immunity verified at baseline, vaccination pathway where non immune, and the post exposure framework stated in the written medical protocol.',
   null, 'HBA Regulations, 2022'),
  ('D', 'Zoonosis surveillance per written medical protocol', 'clinical',
   'Livestock, dairy, poultry, and veterinary exposed workers per the HBA risk assessment; agent list and battery per the written medical protocol for the holding.',
   null, 'HBA Regulations, 2022'),
  ('L', 'Radiation worker medical surveillance linked to personal dose monitoring', 'clinical',
   'Workers under SAHPRA licensed radiation sources and generators: surveillance linked to the personal dose monitoring record, with fitness review on any dose investigation level per the licence and the SAHPRA monitoring guideline.',
   null, 'Hazardous Substances Act (radiation control)')
) as p(hazard_code, test_name, test_type, triggers, bio_ref, basis_short_name)
join msp_hazard h on h.code = p.hazard_code
join msp_legal_instrument li on li.short_name = p.basis_short_name and li.status = 'verified';

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('AGRI', 'Agriculture and forestry', 'SIC major division 1, Agriculture, hunting, forestry and fishing', 'OHSA'),
('HEALTH', 'Healthcare and laboratories', 'SIC major division 9, Community, social and personal services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('AGRI', 'AGRI-CROP',   'Crop farming',              'Batch 4 role map seeded; gate check below'),
  ('AGRI', 'AGRI-LIVE',   'Livestock farming',         'Batch 4 role map seeded; gate check below'),
  ('AGRI', 'AGRI-FOREST', 'Forestry',                  'Batch 4 role map seeded; gate check below'),
  ('HEALTH', 'HLTH-CLINIC', 'Clinics and practices',   'Batch 4 role map seeded; gate check below'),
  ('HEALTH', 'HLTH-LAB',    'Laboratories',            'Batch 4 role map seeded; gate check below'),
  ('HEALTH', 'HLTH-HOSP',   'Hospitals',               'Role map in a later batch')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('AGRI-CROP', 'Tractor and Implement Operator', 'Field operations with tractors and implements', 'Prolonged sitting under vibration, implement coupling', 'Sustained visual attention, terrain judgement', 'Tractor competency; PrDP where public roads are used'),
  ('AGRI-CROP', 'Pesticide Applicator', 'Mixing, loading, and applying crop protection products', 'Knapsack and boom application work in heat', 'Label discipline, exposure control vigilance', 'Pest control operator registration as applicable'),
  ('AGRI-CROP', 'Field Worker and Harvester', 'Planting, weeding, and harvest work', 'Sustained stooping, lifting, and carrying in heat', 'Instruction following', 'None beyond induction'),
  ('AGRI-CROP', 'Irrigation Worker', 'Moving and maintaining irrigation lines and pumps', 'Wet manual work, pump house access', 'Basic mechanical vigilance', 'None beyond induction'),
  ('AGRI-CROP', 'Packhouse Worker', 'Grading and packing produce on lines', 'Standing shifts, repetitive upper limb work', 'Grading accuracy at rate', 'None beyond induction'),
  ('AGRI-CROP', 'Farm Workshop Mechanic', 'Maintaining tractors, implements, and pumps', 'Heavy component handling, tool vibration', 'Fault diagnosis, fine motor control', 'Trade competency'),
  ('AGRI-CROP', 'Farm Supervisor', 'Supervising field and packhouse teams', 'Extensive walking in heat', 'Sustained attention, team coordination', 'None beyond induction'),
  ('AGRI-LIVE', 'Livestock Handler', 'Handling cattle and small stock in kraals and crushes', 'Heavy animal handling with injury exposure', 'Animal behaviour vigilance', 'None beyond induction'),
  ('AGRI-LIVE', 'Dairy Parlour Worker', 'Milking operations across early shifts', 'Repetitive udder preparation, wet work, early hours', 'Hygiene discipline', 'None beyond induction'),
  ('AGRI-LIVE', 'Poultry House Worker', 'Broiler and layer house operations', 'Organic dust exposure, sustained bending and catching', 'Biosecurity discipline', 'None beyond induction'),
  ('AGRI-LIVE', 'Veterinary Assistant', 'Assisting with treatments, sampling, and post mortems', 'Animal restraint, sharps use', 'Clinical procedure discipline', 'None beyond induction'),
  ('AGRI-LIVE', 'Feed Mill Operator', 'Milling and mixing animal feed', 'Bag handling, mill house access', 'Machine and dust control vigilance', 'None beyond induction'),
  ('AGRI-LIVE', 'Livestock Farm Supervisor', 'Supervising handling, dosing, and dipping programmes', 'Extensive outdoor work', 'Programme coordination, remedy handling discipline', 'None beyond induction'),
  ('AGRI-FOREST', 'Chainsaw Operator', 'Felling, delimbing, and crosscutting', 'Sustained chainsaw work on slopes', 'Felling judgement, escape route discipline', 'Chainsaw competency certification'),
  ('AGRI-FOREST', 'Harvester Machine Operator', 'Mechanised felling and extraction', 'Prolonged operation under vibration', 'Sustained visual attention, terrain judgement', 'Machine competency'),
  ('AGRI-FOREST', 'Silviculture Worker', 'Planting, tending, and herbicide application', 'Sustained manual work on slopes in heat', 'Herbicide label discipline', 'None beyond induction'),
  ('AGRI-FOREST', 'Log Truck Driver', 'Timber haulage from compartments to mills', 'Load securing, prolonged driving on gravel', 'Sustained visual attention, reaction time, no uncontrolled hypoglycaemic risk', 'PrDP goods'),
  ('AGRI-FOREST', 'Fire Crew Member', 'Fire prevention and suppression duty', 'Arduous work in extreme heat with load carriage', 'Composure and instruction following under emergency conditions', 'Firefighting competency; arduous duty fitness'),
  ('AGRI-FOREST', 'Forestry Supervisor', 'Supervising harvesting and silviculture teams', 'Extensive walking on slopes', 'Team coordination, hazard vigilance', 'None beyond induction'),
  ('HLTH-CLINIC', 'Occupational Health Nurse', 'Clinical examinations, screening, and immunisation', 'Clinic work with sharps use', 'Clinical accuracy, confidentiality discipline', 'SANC registration'),
  ('HLTH-CLINIC', 'Medical Practitioner', 'Consultations and clinical procedures', 'Clinical work with sharps use', 'Clinical judgement', 'HPCSA registration'),
  ('HLTH-CLINIC', 'Phlebotomist', 'Specimen collection', 'Repetitive venepuncture with sharps use', 'Fine motor control, patient handling', 'Registration as applicable'),
  ('HLTH-CLINIC', 'Radiographer', 'Diagnostic imaging', 'Patient positioning and transfer', 'Imaging precision, radiation protection discipline', 'HPCSA registration; radiation worker status under the SAHPRA licence'),
  ('HLTH-CLINIC', 'Healthcare Cleaner and Waste Handler', 'Cleaning clinical areas and handling healthcare risk waste', 'Manual cleaning with chemical use and sharps risk', 'Segregation and hygiene discipline', 'None beyond induction'),
  ('HLTH-CLINIC', 'Practice Administrator', 'Reception, records, and scheduling', 'Sedentary administrative work', 'Confidentiality discipline, sustained concentration', 'None beyond induction'),
  ('HLTH-LAB', 'Medical Technologist', 'Diagnostic testing across disciplines', 'Bench work with specimen handling', 'Analytical precision', 'HPCSA registration'),
  ('HLTH-LAB', 'Microbiology Technologist', 'Culture and identification of pathogens', 'Bench work at biosafety cabinets', 'Aseptic technique discipline', 'HPCSA registration'),
  ('HLTH-LAB', 'Histology Technician', 'Tissue processing with fixatives and stains', 'Bench work with chemical handling', 'Fine motor precision', 'Registration as applicable'),
  ('HLTH-LAB', 'Specimen Reception Clerk', 'Receiving, sorting, and registering specimens', 'Repetitive handling of specimen containers', 'Recording accuracy', 'None beyond induction'),
  ('HLTH-LAB', 'Laboratory Courier', 'Specimen collection and transport between sites', 'Driving with specimen load handling', 'Traffic vigilance, cold chain discipline', 'Driving licence; PrDP where applicable'),
  ('HLTH-LAB', 'Washup and Autoclave Operator', 'Decontamination, washup, and sterilisation', 'Steam and heat exposure, manual loading', 'Cycle verification discipline', 'None beyond induction')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('AGRI-CROP', 'Tractor and Implement Operator', 'G', 'Moderate to High', 'Whole body vibration across field operations'),
  ('AGRI-CROP', 'Tractor and Implement Operator', 'A', 'Moderate', 'Tractor and implement noise'),
  ('AGRI-CROP', 'Tractor and Implement Operator', 'J', 'Moderate', 'Machine operation and road transfers'),
  ('AGRI-CROP', 'Tractor and Implement Operator', 'H', 'Moderate', 'Outdoor work in heat'),
  ('AGRI-CROP', 'Pesticide Applicator', 'C', 'High', 'Organophosphate and other crop protection product exposure'),
  ('AGRI-CROP', 'Pesticide Applicator', 'H', 'Moderate', 'Application work in heat under PPE burden'),
  ('AGRI-CROP', 'Field Worker and Harvester', 'I', 'High', 'Sustained stooping and carrying'),
  ('AGRI-CROP', 'Field Worker and Harvester', 'H', 'High', 'Field work in summer heat'),
  ('AGRI-CROP', 'Irrigation Worker', 'I', 'Moderate', 'Line moving and pump work'),
  ('AGRI-CROP', 'Irrigation Worker', 'D', 'Low', 'Contact with untreated water sources'),
  ('AGRI-CROP', 'Packhouse Worker', 'I', 'Moderate', 'Repetitive packing at rate'),
  ('AGRI-CROP', 'Packhouse Worker', 'A', 'Moderate', 'Packline noise'),
  ('AGRI-CROP', 'Packhouse Worker', 'K', 'Moderate', 'Seasonal shift work'),
  ('AGRI-CROP', 'Farm Workshop Mechanic', 'A', 'Moderate', 'Workshop noise'),
  ('AGRI-CROP', 'Farm Workshop Mechanic', 'G', 'Moderate', 'Tool vibration'),
  ('AGRI-CROP', 'Farm Workshop Mechanic', 'C', 'Moderate', 'Fuels, oils, and solvents'),
  ('AGRI-CROP', 'Farm Workshop Mechanic', 'M', 'Low', 'Electrical repairs'),
  ('AGRI-CROP', 'Farm Supervisor', 'H', 'Moderate', 'Extensive outdoor supervision'),
  ('AGRI-LIVE', 'Livestock Handler', 'D', 'High', 'Zoonotic exposure in handling and dipping'),
  ('AGRI-LIVE', 'Livestock Handler', 'I', 'High', 'Heavy animal handling'),
  ('AGRI-LIVE', 'Livestock Handler', 'H', 'Moderate', 'Outdoor kraal work'),
  ('AGRI-LIVE', 'Dairy Parlour Worker', 'D', 'Moderate', 'Zoonotic exposure in milking'),
  ('AGRI-LIVE', 'Dairy Parlour Worker', 'I', 'Moderate', 'Repetitive parlour work'),
  ('AGRI-LIVE', 'Dairy Parlour Worker', 'K', 'Moderate', 'Early hours milking shifts'),
  ('AGRI-LIVE', 'Poultry House Worker', 'D', 'High', 'Organic dust and zoonotic exposure in poultry houses'),
  ('AGRI-LIVE', 'Poultry House Worker', 'C', 'Moderate', 'Ammonia and disinfectant exposure'),
  ('AGRI-LIVE', 'Poultry House Worker', 'I', 'Moderate', 'Catching and bending work'),
  ('AGRI-LIVE', 'Veterinary Assistant', 'D', 'High', 'Clinical zoonotic and sharps exposure'),
  ('AGRI-LIVE', 'Veterinary Assistant', 'I', 'Moderate', 'Animal restraint'),
  ('AGRI-LIVE', 'Feed Mill Operator', 'A', 'Moderate', 'Mill noise'),
  ('AGRI-LIVE', 'Feed Mill Operator', 'C', 'Moderate', 'Organic feed dust per the HCA framework'),
  ('AGRI-LIVE', 'Feed Mill Operator', 'I', 'Moderate', 'Bag handling'),
  ('AGRI-LIVE', 'Livestock Farm Supervisor', 'D', 'Moderate', 'Programme supervision with animal contact'),
  ('AGRI-LIVE', 'Livestock Farm Supervisor', 'C', 'Moderate', 'Dip and remedy handling supervision'),
  ('AGRI-FOREST', 'Chainsaw Operator', 'G', 'High', 'Sustained chainsaw hand arm vibration'),
  ('AGRI-FOREST', 'Chainsaw Operator', 'A', 'High', 'Chainsaw noise'),
  ('AGRI-FOREST', 'Chainsaw Operator', 'I', 'High', 'Felling work on slopes'),
  ('AGRI-FOREST', 'Harvester Machine Operator', 'G', 'Moderate to High', 'Whole body vibration in mechanised harvesting'),
  ('AGRI-FOREST', 'Harvester Machine Operator', 'A', 'Moderate', 'Machine noise'),
  ('AGRI-FOREST', 'Harvester Machine Operator', 'J', 'Moderate', 'Machine operation on extraction routes'),
  ('AGRI-FOREST', 'Silviculture Worker', 'I', 'High', 'Sustained planting and tending work'),
  ('AGRI-FOREST', 'Silviculture Worker', 'C', 'Moderate', 'Herbicide application'),
  ('AGRI-FOREST', 'Silviculture Worker', 'H', 'Moderate', 'Slope work in heat'),
  ('AGRI-FOREST', 'Log Truck Driver', 'J', 'High', 'Timber haulage on gravel routes'),
  ('AGRI-FOREST', 'Log Truck Driver', 'G', 'Moderate', 'Route vibration'),
  ('AGRI-FOREST', 'Fire Crew Member', 'H', 'High', 'Arduous suppression work in extreme heat'),
  ('AGRI-FOREST', 'Fire Crew Member', 'N', 'Moderate', 'Emergency duty psychological load'),
  ('AGRI-FOREST', 'Fire Crew Member', 'C', 'Moderate', 'Smoke exposure'),
  ('AGRI-FOREST', 'Forestry Supervisor', 'H', 'Moderate', 'Extensive slope walking'),
  ('HLTH-CLINIC', 'Occupational Health Nurse', 'D', 'High', 'Tuberculosis and blood borne exposure with sharps use'),
  ('HLTH-CLINIC', 'Occupational Health Nurse', 'N', 'Moderate', 'Clinical workload and confidentiality burden'),
  ('HLTH-CLINIC', 'Medical Practitioner', 'D', 'High', 'Clinical infectious exposure with sharps use'),
  ('HLTH-CLINIC', 'Medical Practitioner', 'N', 'Moderate', 'Clinical decision load'),
  ('HLTH-CLINIC', 'Phlebotomist', 'D', 'High', 'Sharps and blood borne exposure'),
  ('HLTH-CLINIC', 'Radiographer', 'L', 'Moderate', 'Occupational ionising radiation under the SAHPRA licence'),
  ('HLTH-CLINIC', 'Radiographer', 'D', 'Moderate', 'Patient contact infectious exposure'),
  ('HLTH-CLINIC', 'Radiographer', 'I', 'Moderate', 'Patient positioning and transfer'),
  ('HLTH-CLINIC', 'Healthcare Cleaner and Waste Handler', 'D', 'High', 'Healthcare risk waste and sharps exposure'),
  ('HLTH-CLINIC', 'Healthcare Cleaner and Waste Handler', 'C', 'Moderate', 'Disinfectant and detergent handling'),
  ('HLTH-CLINIC', 'Healthcare Cleaner and Waste Handler', 'I', 'Moderate', 'Manual cleaning work'),
  ('HLTH-CLINIC', 'Practice Administrator', 'N', 'Low', 'Front desk load'),
  ('HLTH-CLINIC', 'Practice Administrator', 'K', 'Low', 'Extended clinic hours'),
  ('HLTH-LAB', 'Medical Technologist', 'D', 'High', 'Specimen borne infectious exposure'),
  ('HLTH-LAB', 'Medical Technologist', 'C', 'Moderate', 'Reagent and solvent handling'),
  ('HLTH-LAB', 'Microbiology Technologist', 'D', 'High', 'Culture of pathogens at the bench'),
  ('HLTH-LAB', 'Histology Technician', 'C', 'High', 'Formaldehyde and stain exposure'),
  ('HLTH-LAB', 'Histology Technician', 'D', 'Moderate', 'Fresh tissue handling'),
  ('HLTH-LAB', 'Specimen Reception Clerk', 'D', 'Moderate', 'Specimen container handling'),
  ('HLTH-LAB', 'Specimen Reception Clerk', 'I', 'Moderate', 'Repetitive sorting'),
  ('HLTH-LAB', 'Laboratory Courier', 'D', 'Moderate', 'Specimen transport'),
  ('HLTH-LAB', 'Laboratory Courier', 'J', 'Moderate', 'Route driving'),
  ('HLTH-LAB', 'Washup and Autoclave Operator', 'D', 'Moderate', 'Pre decontamination handling'),
  ('HLTH-LAB', 'Washup and Autoclave Operator', 'H', 'Moderate', 'Steam and autoclave heat')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('AGRI', 'OHS Act', 'Framework Act for farming and forestry workplaces'),
  ('AGRI', 'HCA Regulations, 2021', 'Crop protection products including organophosphates, with cholinesterase biological effect monitoring per the Regulations'),
  ('AGRI', 'HBA Regulations, 2022', 'Zoonotic and organic biological exposure across livestock, dairy, and poultry'),
  ('AGRI', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026'),
  ('AGRI', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('AGRI', 'Ergonomics Regulations, 2019', 'Field, packhouse, and forestry manual work surveillance'),
  ('AGRI', 'Environmental Regulations for Workplaces, 1987', 'Heat stress in field, forestry, and fire duty; hot work fitness certification'),
  ('AGRI', 'NRTA PrDP medical', 'Professional driving including timber haulage'),
  ('AGRI', 'COIDA', 'Compensation route for agricultural and forestry injuries and diseases'),
  ('AGRI', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('AGRI', 'BCEA night work Code', 'Early hours milking and seasonal shift work'),
  ('AGRI', 'HPCSA Booklet 1', 'Ethical baseline for all examinations under the programme'),
  ('AGRI', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer'),
  ('HEALTH', 'OHS Act', 'Framework Act for healthcare and laboratory workplaces'),
  ('HEALTH', 'HBA Regulations, 2022', 'The central instrument: tuberculosis, blood borne, and specimen borne exposure with written medical protocols'),
  ('HEALTH', 'Hazardous Substances Act (radiation control)', 'Radiation workers under SAHPRA licensing and personal dose monitoring'),
  ('HEALTH', 'HCA Regulations, 2021', 'Disinfectants, formaldehyde, and laboratory reagents'),
  ('HEALTH', 'Ergonomics Regulations, 2019', 'Patient handling and repetitive bench work surveillance'),
  ('HEALTH', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 where plant rooms apply'),
  ('HEALTH', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('HEALTH', 'COIDA', 'Compensation route including occupationally acquired infections'),
  ('HEALTH', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('HEALTH', 'BCEA night work Code', 'Extended hours and call arrangements'),
  ('HEALTH', 'HPCSA Booklet 1', 'Ethical baseline for all examinations under the programme'),
  ('HEALTH', 'HPCSA Booklet 10', 'Telehealth guidance for clinical services'),
  ('HEALTH', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('AGRI', 4500, 35, 450, 'placeholder'),
('HEALTH', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['AGRI-CROP','AGRI-LIVE','AGRI-FOREST','HLTH-CLINIC','HLTH-LAB']) loop
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
   set description = description || ' Update 13/08/2026 batch 4: cholinesterase biological effect monitoring anchored to the HCA Regulations 2021 BEI annexure (values applied from the annexure at examination); radiation dose limits anchored to SAHPRA licence conditions. Hazard N (psychosocial) carries no dedicated screening protocol pending an instrument basis; psychosocial load is noted in the OREP narrative meanwhile.'
 where item_code = 'CR-12.1';