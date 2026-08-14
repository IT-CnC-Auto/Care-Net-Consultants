-- CNC MSP FORGE | TAX-BAT-15 v1.0.0 | Phase 6 batch 15: held subindustry completion, Mining commodities and Hospitals
-- No new instrument: roles seed against the verified corpus (MHSA set from batch 2, healthcare set from batch 4). Documentary basis 13/08/2026, subject to OMP ratification.

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('MIN-COAL', 'Continuous Miner Operator', 'Continuous miner operation at the coal face', 'Sustained operation in coal dust and noise', 'Face condition judgement, methane awareness', 'Competency per the mine''s code of practice'),
  ('MIN-COAL', 'Underground Coal Miner', 'Face work, roof support, and section labour', 'Heavy underground labour in dust and heat', 'Strata and gas awareness, instruction following', 'Competency per the mine''s code of practice'),
  ('MIN-COAL', 'Shaft and Belt Attendant', 'Conveyor and shaft infrastructure attendance', 'Belt route walking, spillage clearing', 'Belt and nip point vigilance', 'None beyond induction'),
  ('MIN-COAL', 'Surface Coal Plant Operator', 'Washing and screening plant operation', 'Plant rounds in dust and noise', 'Plant condition vigilance', 'None beyond induction'),
  ('MIN-COAL', 'Coal Mine Overseer', 'Section supervision and statutory inspections', 'Underground travel across sections', 'Statutory inspection discipline, gas awareness', 'Statutory certificate per the MHSA framework'),
  ('MIN-PLAT', 'Rock Drill Operator', 'Hand held rock drilling in stopes', 'Sustained drilling under vibration in heat', 'Drilling pattern precision, strata awareness', 'Competency per the mine''s code of practice'),
  ('MIN-PLAT', 'Stoping Crew Worker', 'Stope preparation, support, and cleaning', 'Heavy stope labour in heat and dust', 'Strata awareness, instruction following', 'Competency per the mine''s code of practice'),
  ('MIN-PLAT', 'Winch and Rigging Operator', 'Scraper winch and rigging operation', 'Winch operation and rope work', 'Signal discipline, rope condition vigilance', 'Competency per the mine''s code of practice'),
  ('MIN-PLAT', 'Underground LHD Operator', 'Load haul dump operation underground', 'Sustained machine operation in confined drives', 'Clearance judgement, pedestrian vigilance', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('MIN-PLAT', 'Ventilation and Gas Test Assistant', 'Ventilation measurement and gas testing rounds', 'Underground travel with instruments', 'Gas test discipline, reporting accuracy', 'Gas testing competency'),
  ('MIN-CHROME', 'Drill Rig Operator (chrome)', 'Mechanised drilling underground', 'Rig operation in dust and noise', 'Drilling pattern precision', 'Competency per the mine''s code of practice'),
  ('MIN-CHROME', 'Underground Crew Worker (chrome)', 'Development and stoping crew labour', 'Heavy underground labour', 'Strata awareness, instruction following', 'Competency per the mine''s code of practice'),
  ('MIN-CHROME', 'Chrome LHD Operator', 'Load haul dump operation', 'Sustained machine operation', 'Clearance judgement, pedestrian vigilance', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('MIN-CHROME', 'Concentrator Plant Operator', 'Crushing and concentration plant operation', 'Plant rounds in noise and dust', 'Plant condition vigilance, spillage response', 'None beyond induction'),
  ('MIN-CHROME', 'Sampler and Grade Controller', 'Ore sampling and grade control', 'Sampling rounds underground and on plant', 'Sampling protocol precision', 'None beyond induction'),
  ('MIN-DIAMOND', 'Open Pit Excavator Operator', 'Excavator and haul loading in the pit', 'Sustained plant operation on pit terrain', 'Bench and edge judgement, pedestrian vigilance', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('MIN-DIAMOND', 'Treatment Plant Operator (diamond)', 'Crushing, DMS, and recovery plant operation', 'Plant rounds in noise', 'Recovery security discipline, plant vigilance', 'None beyond induction'),
  ('MIN-DIAMOND', 'Drill and Blast Assistant', 'Drilling support and blast preparation', 'Heavy pit labour in dust and noise', 'Blast exclusion discipline', 'Blasting assistant competency'),
  ('MIN-DIAMOND', 'Dewatering and Pump Attendant', 'Pit and plant dewatering systems', 'Pump station rounds including sump access', 'Pump condition vigilance', 'None beyond induction'),
  ('MIN-DIAMOND', 'Pit Technician and Surveyor', 'Survey and geotechnical monitoring', 'Pit walking in weather', 'Measurement precision, edge discipline', 'None beyond induction'),
  ('HLTH-HOSP', 'Professional Nurse (ward)', 'Ward nursing across shifts', 'Patient handling and sustained ward rounds', 'Clinical vigilance across night shifts, medication accuracy', 'SANC registration'),
  ('HLTH-HOSP', 'Hospital Cleaner and Ward Assistant', 'Clinical area cleaning and patient support', 'Cleaning with infectious and sharps risk', 'Segregation and hygiene discipline', 'None beyond induction'),
  ('HLTH-HOSP', 'Theatre and CSSD Technician', 'Theatre support and instrument sterilisation', 'Instrument handling with disinfectant exposure', 'Sterility discipline, tracking accuracy', 'None beyond induction'),
  ('HLTH-HOSP', 'Radiographer', 'Diagnostic imaging under SAHPRA licence', 'Patient positioning work', 'Imaging protocol precision, dose discipline', 'HPCSA radiography registration'),
  ('HLTH-HOSP', 'Hospital Porter', 'Patient and equipment movement', 'Sustained patient transfer and trolley work', 'Patient dignity and handling discipline', 'None beyond induction'),
  ('HLTH-HOSP', 'Hospital Food Services Worker', 'Patient meal preparation and distribution', 'Kitchen work with heat and trolley rounds', 'Therapeutic diet accuracy, hygiene discipline', 'None beyond induction')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('MIN-COAL', 'Continuous Miner Operator', 'B', 'High', 'Coal face dust with pneumoconiosis and ODMWA routing'),
  ('MIN-COAL', 'Continuous Miner Operator', 'A', 'High', 'Continuous miner noise'),
  ('MIN-COAL', 'Continuous Miner Operator', 'K', 'Moderate', 'Continuous mining shifts'),
  ('MIN-COAL', 'Underground Coal Miner', 'B', 'High', 'Coal dust exposure with ODMWA routing'),
  ('MIN-COAL', 'Underground Coal Miner', 'I', 'High', 'Heavy underground labour'),
  ('MIN-COAL', 'Underground Coal Miner', 'A', 'Moderate', 'Section machinery noise'),
  ('MIN-COAL', 'Underground Coal Miner', 'H', 'Moderate', 'Underground heat'),
  ('MIN-COAL', 'Shaft and Belt Attendant', 'A', 'Moderate', 'Conveyor drive noise'),
  ('MIN-COAL', 'Shaft and Belt Attendant', 'B', 'Moderate', 'Belt route coal dust'),
  ('MIN-COAL', 'Shaft and Belt Attendant', 'K', 'Moderate', 'Continuous mining shifts'),
  ('MIN-COAL', 'Surface Coal Plant Operator', 'B', 'Moderate', 'Washing plant coal dust'),
  ('MIN-COAL', 'Surface Coal Plant Operator', 'A', 'Moderate', 'Screening plant noise'),
  ('MIN-COAL', 'Surface Coal Plant Operator', 'J', 'Moderate', 'Plant mobile equipment operation'),
  ('MIN-COAL', 'Coal Mine Overseer', 'B', 'Moderate', 'Section travel dust exposure'),
  ('MIN-COAL', 'Coal Mine Overseer', 'A', 'Moderate', 'Section machinery noise'),
  ('MIN-COAL', 'Coal Mine Overseer', 'K', 'Moderate', 'Statutory shift coverage'),
  ('MIN-PLAT', 'Rock Drill Operator', 'A', 'High', 'Rock drill noise'),
  ('MIN-PLAT', 'Rock Drill Operator', 'B', 'High', 'Silica bearing rock dust with ODMWA routing'),
  ('MIN-PLAT', 'Rock Drill Operator', 'G', 'High', 'Hand arm vibration from rock drills'),
  ('MIN-PLAT', 'Rock Drill Operator', 'H', 'High', 'Deep level stope heat'),
  ('MIN-PLAT', 'Stoping Crew Worker', 'I', 'High', 'Heavy stope labour'),
  ('MIN-PLAT', 'Stoping Crew Worker', 'B', 'High', 'Stope dust exposure with ODMWA routing'),
  ('MIN-PLAT', 'Stoping Crew Worker', 'H', 'High', 'Deep level stope heat'),
  ('MIN-PLAT', 'Stoping Crew Worker', 'A', 'Moderate', 'Stope machinery noise'),
  ('MIN-PLAT', 'Winch and Rigging Operator', 'A', 'Moderate', 'Winch operation noise'),
  ('MIN-PLAT', 'Winch and Rigging Operator', 'I', 'Moderate', 'Rope and rigging handling'),
  ('MIN-PLAT', 'Winch and Rigging Operator', 'K', 'Moderate', 'Continuous mining shifts'),
  ('MIN-PLAT', 'Underground LHD Operator', 'J', 'High', 'LHD operation under the Driven Machinery Regulations, 2015'),
  ('MIN-PLAT', 'Underground LHD Operator', 'A', 'Moderate', 'LHD cab noise'),
  ('MIN-PLAT', 'Underground LHD Operator', 'B', 'Moderate', 'Drive dust exposure'),
  ('MIN-PLAT', 'Ventilation and Gas Test Assistant', 'F', 'Moderate', 'Poorly ventilated area testing'),
  ('MIN-PLAT', 'Ventilation and Gas Test Assistant', 'B', 'Moderate', 'Underground dust exposure'),
  ('MIN-PLAT', 'Ventilation and Gas Test Assistant', 'K', 'Moderate', 'Shift coverage rounds'),
  ('MIN-CHROME', 'Drill Rig Operator (chrome)', 'A', 'High', 'Drill rig noise'),
  ('MIN-CHROME', 'Drill Rig Operator (chrome)', 'B', 'High', 'Drilling dust with ODMWA routing'),
  ('MIN-CHROME', 'Drill Rig Operator (chrome)', 'G', 'Moderate', 'Rig vibration exposure'),
  ('MIN-CHROME', 'Underground Crew Worker (chrome)', 'I', 'High', 'Heavy development labour'),
  ('MIN-CHROME', 'Underground Crew Worker (chrome)', 'B', 'High', 'Development dust with ODMWA routing'),
  ('MIN-CHROME', 'Underground Crew Worker (chrome)', 'A', 'Moderate', 'Section machinery noise'),
  ('MIN-CHROME', 'Underground Crew Worker (chrome)', 'H', 'Moderate', 'Underground heat'),
  ('MIN-CHROME', 'Chrome LHD Operator', 'J', 'High', 'LHD operation under the Driven Machinery Regulations, 2015'),
  ('MIN-CHROME', 'Chrome LHD Operator', 'A', 'Moderate', 'LHD cab noise'),
  ('MIN-CHROME', 'Chrome LHD Operator', 'B', 'Moderate', 'Drive dust exposure'),
  ('MIN-CHROME', 'Concentrator Plant Operator', 'A', 'Moderate', 'Crusher and mill noise'),
  ('MIN-CHROME', 'Concentrator Plant Operator', 'B', 'Moderate', 'Concentrator dust'),
  ('MIN-CHROME', 'Concentrator Plant Operator', 'C', 'Moderate', 'Reagent handling in concentration'),
  ('MIN-CHROME', 'Sampler and Grade Controller', 'B', 'Moderate', 'Sampling dust exposure'),
  ('MIN-CHROME', 'Sampler and Grade Controller', 'A', 'Moderate', 'Plant and section noise'),
  ('MIN-DIAMOND', 'Open Pit Excavator Operator', 'J', 'High', 'Pit excavator operation under the Driven Machinery Regulations, 2015'),
  ('MIN-DIAMOND', 'Open Pit Excavator Operator', 'A', 'Moderate', 'Excavator cab noise'),
  ('MIN-DIAMOND', 'Open Pit Excavator Operator', 'B', 'Moderate', 'Pit dust exposure'),
  ('MIN-DIAMOND', 'Treatment Plant Operator (diamond)', 'A', 'Moderate', 'Crushing and DMS plant noise'),
  ('MIN-DIAMOND', 'Treatment Plant Operator (diamond)', 'B', 'Moderate', 'Treatment plant dust'),
  ('MIN-DIAMOND', 'Treatment Plant Operator (diamond)', 'I', 'Moderate', 'Plant rounds and spillage work'),
  ('MIN-DIAMOND', 'Drill and Blast Assistant', 'A', 'High', 'Drilling noise'),
  ('MIN-DIAMOND', 'Drill and Blast Assistant', 'B', 'High', 'Drilling dust with ODMWA routing'),
  ('MIN-DIAMOND', 'Drill and Blast Assistant', 'I', 'Moderate', 'Heavy pit labour'),
  ('MIN-DIAMOND', 'Dewatering and Pump Attendant', 'F', 'Moderate', 'Sump and pump station access'),
  ('MIN-DIAMOND', 'Dewatering and Pump Attendant', 'D', 'Moderate', 'Pit water biological context'),
  ('MIN-DIAMOND', 'Dewatering and Pump Attendant', 'A', 'Moderate', 'Pump station noise'),
  ('MIN-DIAMOND', 'Pit Technician and Surveyor', 'H', 'Moderate', 'Pit walking in heat'),
  ('MIN-DIAMOND', 'Pit Technician and Surveyor', 'B', 'Moderate', 'Pit dust exposure'),
  ('MIN-DIAMOND', 'Pit Technician and Surveyor', 'J', 'Moderate', 'Pit road driving'),
  ('HLTH-HOSP', 'Professional Nurse (ward)', 'D', 'High', 'Patient contact blood, body fluid, and tuberculosis exposure'),
  ('HLTH-HOSP', 'Professional Nurse (ward)', 'I', 'High', 'Patient handling load'),
  ('HLTH-HOSP', 'Professional Nurse (ward)', 'K', 'High', 'Continuous ward night shifts'),
  ('HLTH-HOSP', 'Hospital Cleaner and Ward Assistant', 'D', 'High', 'Clinical cleaning infectious and sharps exposure'),
  ('HLTH-HOSP', 'Hospital Cleaner and Ward Assistant', 'C', 'Moderate', 'Disinfectant use'),
  ('HLTH-HOSP', 'Hospital Cleaner and Ward Assistant', 'I', 'Moderate', 'Sustained cleaning rounds'),
  ('HLTH-HOSP', 'Theatre and CSSD Technician', 'D', 'High', 'Instrument decontamination exposure'),
  ('HLTH-HOSP', 'Theatre and CSSD Technician', 'C', 'Moderate', 'Sterilant and disinfectant chemical exposure'),
  ('HLTH-HOSP', 'Theatre and CSSD Technician', 'K', 'Moderate', 'Theatre list and callout shifts'),
  ('HLTH-HOSP', 'Radiographer', 'L', 'High', 'Ionising radiation work under SAHPRA licence dose monitoring'),
  ('HLTH-HOSP', 'Radiographer', 'K', 'Moderate', 'Imaging callout shifts'),
  ('HLTH-HOSP', 'Radiographer', 'D', 'Moderate', 'Patient contact exposure'),
  ('HLTH-HOSP', 'Hospital Porter', 'I', 'High', 'Sustained patient transfer work'),
  ('HLTH-HOSP', 'Hospital Porter', 'D', 'Moderate', 'Patient contact exposure'),
  ('HLTH-HOSP', 'Hospital Porter', 'K', 'Moderate', 'Continuous hospital shifts'),
  ('HLTH-HOSP', 'Hospital Food Services Worker', 'D', 'Moderate', 'Food handling under R638 of 2018 in a clinical setting'),
  ('HLTH-HOSP', 'Hospital Food Services Worker', 'H', 'Moderate', 'Kitchen heat'),
  ('HLTH-HOSP', 'Hospital Food Services Worker', 'I', 'Moderate', 'Trolley rounds and pot handling')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['MIN-COAL','MIN-PLAT','MIN-CHROME','MIN-DIAMOND','HLTH-HOSP']) loop
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
    update msp_subindustry
       set selectable = true,
           notes = 'Batch 15 role map seeded; gate passed'
     where code = v_code;
    raise notice 'batch gate: % enabled (% roles)', v_code, v_roles;
  end loop;
end $$;

-- Register updates

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 15: coal, platinum, chrome, and diamond role maps route dust disease surveillance through the ODMWA and Medical Bureau for Occupational Diseases pathway per the kernel routing rule, with each mine''s mandatory code of practice medical standards tightening the battery at review. Hospital roles carry the healthcare protocol set (tuberculosis screening, hepatitis B immunity verification, and SAHPRA licensed dose monitoring for radiographers).'
 where item_code = 'CR-12.1';
