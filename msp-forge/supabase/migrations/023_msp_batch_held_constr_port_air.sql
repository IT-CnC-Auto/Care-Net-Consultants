-- CNC MSP FORGE | TAX-BAT-14 v1.0.0 | Phase 6 batch 14: held subindustry completion, Construction extras, Ports, Aviation ground handling
-- No new instrument: roles seed against the verified corpus. Documentary basis 13/08/2026, subject to OMP ratification.

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('CONSTR-DEMO', 'Demolition Worker', 'Structural demolition and material breaking', 'Heavy breaking labour in dust', 'Structural collapse awareness, exclusion discipline', 'None beyond induction'),
  ('CONSTR-DEMO', 'Demolition Machine Operator', 'Excavator and breaker plant operation', 'Sustained plant operation on unstable ground', 'Machine stability judgement, drop zone vigilance', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('CONSTR-DEMO', 'Burner and Cutter (demolition)', 'Torch cutting of structural steel', 'Cutting work in awkward positions', 'Hot work permit discipline', 'Hot work competency'),
  ('CONSTR-DEMO', 'Salvage and Strip Out Worker', 'Internal strip out and material salvage', 'Sustained manual strip out labour', 'Material identification, exclusion discipline', 'None beyond induction'),
  ('CONSTR-DEMO', 'Demolition Supervisor', 'Demolition sequence and exclusion zone control', 'Site rounds on demolition terrain', 'Sequence control, exclusion zone command', 'None beyond induction'),
  ('CONSTR-ELEC', 'Construction Electrician', 'Electrical installation on construction sites', 'Ladder and platform work, cable pulling', 'Electrical discipline, no condition with sudden incapacity potential', 'Wireman''s licence as applicable'),
  ('CONSTR-ELEC', 'Cable Jointer (construction)', 'MV and LV cable jointing', 'Trench and chamber work, fine jointing', 'Jointing precision, isolation discipline', 'Jointing competency'),
  ('CONSTR-ELEC', 'Overhead Line Constructor', 'Overhead line stringing and pole erection', 'Pole climbing, conductor stringing', 'No vertigo, live line discipline', 'Line work competency; heights certification'),
  ('CONSTR-ELEC', 'Electrical Construction Assistant', 'Cable pulling and installation support', 'Sustained pulling and carrying labour', 'Instruction following, isolation awareness', 'None beyond induction'),
  ('CONSTR-ELEC', 'Solar Installation Technician (rooftop)', 'Rooftop photovoltaic installation', 'Roof work with panel carriage', 'Roof edge discipline, DC electrical discipline', 'Working at heights certification'),
  ('CONSTR-ROADS', 'Asphalt Paver Operator', 'Asphalt paving train operation', 'Sustained work over hot asphalt', 'Paving line precision, crew coordination', 'None beyond induction'),
  ('CONSTR-ROADS', 'Roadworks Labourer', 'Road construction and reinstatement labour', 'Heavy road labour in heat and dust', 'Traffic vigilance', 'None beyond induction'),
  ('CONSTR-ROADS', 'Roller and Compaction Operator', 'Compaction plant operation', 'Sustained plant operation', 'Compaction pattern precision, pedestrian vigilance', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('CONSTR-ROADS', 'Traffic Accommodation Officer', 'Temporary traffic control at roadworks', 'Prolonged standing point duty in weather', 'Sustained traffic vigilance', 'None beyond induction'),
  ('CONSTR-ROADS', 'Kerb and Concrete Worker', 'Kerb laying and concrete finishing', 'Heavy kerb handling, screeding work', 'Finish quality discipline', 'None beyond induction'),
  ('TRANS-PORT', 'Stevedore', 'Vessel loading and discharge work', 'Heavy cargo handling on quay and vessel', 'Load and crane separation vigilance', 'None beyond induction'),
  ('TRANS-PORT', 'Container Crane Operator', 'Ship to shore crane operation', 'Elevated cab operation with sustained downward focus', 'Depth and spreader judgement, no vertigo, no condition with sudden incapacity potential', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015'),
  ('TRANS-PORT', 'Straddle Carrier Operator', 'Container yard carrier operation', 'Elevated cab yard operation across shifts', 'Yard traffic vigilance, stack judgement', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015'),
  ('TRANS-PORT', 'Marine Terminal General Worker', 'Quay side lashing, tallying support, and housekeeping', 'Manual lashing and quay labour', 'Vessel and plant separation vigilance', 'None beyond induction'),
  ('TRANS-PORT', 'Port Checker and Tally Clerk', 'Cargo checking and documentation', 'Quay side walking across shifts', 'Tally accuracy, yard traffic vigilance', 'None beyond induction'),
  ('TRANS-AVGH', 'Ramp Agent and Baggage Handler', 'Aircraft loading and baggage handling on the ramp', 'Sustained baggage handling in ramp noise', 'Aircraft movement vigilance, hearing protection discipline', 'Airside induction and permit'),
  ('TRANS-AVGH', 'Ground Support Equipment Operator', 'Tug, loader, and GSE operation airside', 'Sustained equipment operation among aircraft', 'Aircraft clearance judgement, no condition with sudden incapacity potential', 'Airside driving permit; lifting machine operator certification where applicable'),
  ('TRANS-AVGH', 'Aircraft Fueller', 'Aircraft refuelling operations', 'Hose and coupling handling, fuel exposure', 'Fuelling procedure discipline, bonding discipline', 'Airside driving permit'),
  ('TRANS-AVGH', 'Air Cargo Warehouse Agent', 'Cargo build up, breakdown, and screening', 'Sustained cargo handling at rate', 'Dangerous goods recognition, screening vigilance', 'Dangerous goods awareness category as applicable'),
  ('TRANS-AVGH', 'Airside Crew Transport Driver', 'Crew and staff transport airside', 'Airside route driving across shifts', 'Aircraft and vehicle separation vigilance', 'Airside driving permit; PrDP for passenger transport')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('CONSTR-DEMO', 'Demolition Worker', 'B', 'High', 'Demolition dust with crystalline silica'),
  ('CONSTR-DEMO', 'Demolition Worker', 'I', 'High', 'Heavy breaking labour'),
  ('CONSTR-DEMO', 'Demolition Worker', 'A', 'Moderate', 'Breaker and plant noise'),
  ('CONSTR-DEMO', 'Demolition Machine Operator', 'J', 'High', 'Demolition plant operation under the Driven Machinery Regulations, 2015'),
  ('CONSTR-DEMO', 'Demolition Machine Operator', 'A', 'Moderate', 'Breaker plant noise'),
  ('CONSTR-DEMO', 'Demolition Machine Operator', 'B', 'Moderate', 'Cab penetrating demolition dust'),
  ('CONSTR-DEMO', 'Burner and Cutter (demolition)', 'C', 'Moderate', 'Cutting fume including coated steel'),
  ('CONSTR-DEMO', 'Burner and Cutter (demolition)', 'A', 'Moderate', 'Cutting operations noise'),
  ('CONSTR-DEMO', 'Burner and Cutter (demolition)', 'B', 'Moderate', 'Cutting particulate'),
  ('CONSTR-DEMO', 'Salvage and Strip Out Worker', 'I', 'High', 'Sustained strip out labour'),
  ('CONSTR-DEMO', 'Salvage and Strip Out Worker', 'B', 'Moderate', 'Strip out dust'),
  ('CONSTR-DEMO', 'Demolition Supervisor', 'B', 'Moderate', 'Site dust exposure on rounds'),
  ('CONSTR-DEMO', 'Demolition Supervisor', 'E', 'Moderate', 'Partial structure access'),
  ('CONSTR-ELEC', 'Construction Electrician', 'M', 'High', 'Construction electrical installation'),
  ('CONSTR-ELEC', 'Construction Electrician', 'E', 'Moderate', 'Ladder and platform work'),
  ('CONSTR-ELEC', 'Cable Jointer (construction)', 'M', 'High', 'MV jointing work'),
  ('CONSTR-ELEC', 'Cable Jointer (construction)', 'F', 'Moderate', 'Joint bay and chamber work'),
  ('CONSTR-ELEC', 'Overhead Line Constructor', 'E', 'High', 'Pole and tower stringing work'),
  ('CONSTR-ELEC', 'Overhead Line Constructor', 'M', 'High', 'Line construction near live networks'),
  ('CONSTR-ELEC', 'Overhead Line Constructor', 'H', 'Moderate', 'Outdoor line work in heat'),
  ('CONSTR-ELEC', 'Electrical Construction Assistant', 'I', 'Moderate', 'Cable pulling labour'),
  ('CONSTR-ELEC', 'Electrical Construction Assistant', 'M', 'Moderate', 'Installation support near live work'),
  ('CONSTR-ELEC', 'Solar Installation Technician (rooftop)', 'E', 'High', 'Roof installation work'),
  ('CONSTR-ELEC', 'Solar Installation Technician (rooftop)', 'M', 'Moderate', 'DC string work'),
  ('CONSTR-ELEC', 'Solar Installation Technician (rooftop)', 'H', 'Moderate', 'Roof work in heat'),
  ('CONSTR-ROADS', 'Asphalt Paver Operator', 'H', 'High', 'Hot asphalt heat load'),
  ('CONSTR-ROADS', 'Asphalt Paver Operator', 'C', 'Moderate', 'Bitumen fume exposure'),
  ('CONSTR-ROADS', 'Asphalt Paver Operator', 'A', 'Moderate', 'Paving train noise'),
  ('CONSTR-ROADS', 'Roadworks Labourer', 'I', 'High', 'Heavy road construction labour'),
  ('CONSTR-ROADS', 'Roadworks Labourer', 'B', 'Moderate', 'Road construction dust'),
  ('CONSTR-ROADS', 'Roadworks Labourer', 'H', 'Moderate', 'Roadworks in heat'),
  ('CONSTR-ROADS', 'Roller and Compaction Operator', 'J', 'Moderate', 'Compaction plant operation under the Driven Machinery Regulations, 2015'),
  ('CONSTR-ROADS', 'Roller and Compaction Operator', 'A', 'Moderate', 'Compaction plant noise'),
  ('CONSTR-ROADS', 'Traffic Accommodation Officer', 'H', 'Moderate', 'Prolonged outdoor point duty'),
  ('CONSTR-ROADS', 'Traffic Accommodation Officer', 'I', 'Moderate', 'Prolonged standing duty'),
  ('CONSTR-ROADS', 'Traffic Accommodation Officer', 'A', 'Moderate', 'Roadworks plant noise'),
  ('CONSTR-ROADS', 'Kerb and Concrete Worker', 'I', 'High', 'Heavy kerb and concrete handling'),
  ('CONSTR-ROADS', 'Kerb and Concrete Worker', 'B', 'Moderate', 'Concrete cutting dust'),
  ('TRANS-PORT', 'Stevedore', 'I', 'High', 'Heavy vessel cargo handling'),
  ('TRANS-PORT', 'Stevedore', 'A', 'Moderate', 'Quay side plant noise'),
  ('TRANS-PORT', 'Stevedore', 'K', 'Moderate', 'Vessel driven shift work'),
  ('TRANS-PORT', 'Container Crane Operator', 'J', 'High', 'Ship to shore crane operation under the Driven Machinery Regulations, 2015'),
  ('TRANS-PORT', 'Container Crane Operator', 'E', 'Moderate', 'Elevated cab access and operation'),
  ('TRANS-PORT', 'Container Crane Operator', 'K', 'Moderate', 'Continuous terminal shifts'),
  ('TRANS-PORT', 'Straddle Carrier Operator', 'J', 'High', 'Straddle carrier operation under the Driven Machinery Regulations, 2015'),
  ('TRANS-PORT', 'Straddle Carrier Operator', 'A', 'Moderate', 'Yard plant noise'),
  ('TRANS-PORT', 'Straddle Carrier Operator', 'K', 'Moderate', 'Continuous terminal shifts'),
  ('TRANS-PORT', 'Marine Terminal General Worker', 'I', 'Moderate', 'Lashing and quay labour'),
  ('TRANS-PORT', 'Marine Terminal General Worker', 'A', 'Moderate', 'Quay side plant noise'),
  ('TRANS-PORT', 'Marine Terminal General Worker', 'H', 'Moderate', 'Outdoor quay work in heat'),
  ('TRANS-PORT', 'Port Checker and Tally Clerk', 'K', 'Moderate', 'Vessel driven shift work'),
  ('TRANS-PORT', 'Port Checker and Tally Clerk', 'I', 'Moderate', 'Sustained quay side walking'),
  ('TRANS-AVGH', 'Ramp Agent and Baggage Handler', 'A', 'High', 'Aircraft ramp noise'),
  ('TRANS-AVGH', 'Ramp Agent and Baggage Handler', 'I', 'High', 'Sustained baggage handling'),
  ('TRANS-AVGH', 'Ramp Agent and Baggage Handler', 'K', 'High', 'Continuous flight schedule shifts'),
  ('TRANS-AVGH', 'Ground Support Equipment Operator', 'J', 'High', 'GSE operation with lifting machine certification where applicable'),
  ('TRANS-AVGH', 'Ground Support Equipment Operator', 'A', 'High', 'Aircraft ramp noise'),
  ('TRANS-AVGH', 'Ground Support Equipment Operator', 'K', 'Moderate', 'Continuous flight schedule shifts'),
  ('TRANS-AVGH', 'Aircraft Fueller', 'C', 'Moderate', 'Jet fuel exposure'),
  ('TRANS-AVGH', 'Aircraft Fueller', 'J', 'Moderate', 'Airside bowser driving'),
  ('TRANS-AVGH', 'Aircraft Fueller', 'A', 'Moderate', 'Ramp noise during fuelling'),
  ('TRANS-AVGH', 'Air Cargo Warehouse Agent', 'I', 'High', 'Sustained cargo build up handling'),
  ('TRANS-AVGH', 'Air Cargo Warehouse Agent', 'K', 'Moderate', 'Freighter schedule shifts'),
  ('TRANS-AVGH', 'Airside Crew Transport Driver', 'J', 'Moderate', 'Airside passenger driving with PrDP requirement'),
  ('TRANS-AVGH', 'Airside Crew Transport Driver', 'K', 'Moderate', 'Continuous flight schedule shifts'),
  ('TRANS-AVGH', 'Airside Crew Transport Driver', 'A', 'Moderate', 'Ramp noise on airside routes')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['CONSTR-DEMO','CONSTR-ELEC','CONSTR-ROADS','TRANS-PORT','TRANS-AVGH']) loop
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
           notes = 'Batch 14 role map seeded; gate passed'
     where code = v_code;
    raise notice 'batch gate: % enabled (% roles)', v_code, v_roles;
  end loop;
end $$;

-- Register updates

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 14: ports and aviation ground handling are seeded as shore side and airside ground roles only. Seafarer medical fitness (Merchant Shipping Act, SAMSA regime) and aircrew medical certification (Civil Aviation Act, SACAA regime) are separate licensing regimes outside this programme''s scope and are not represented as CNC protocols. Demolition role maps exclude asbestos abatement work: the Asbestos Abatement Regulations remain unverified and asbestos work routes to the OMP queue until that instrument passes verification.'
 where item_code = 'CR-12.1';
