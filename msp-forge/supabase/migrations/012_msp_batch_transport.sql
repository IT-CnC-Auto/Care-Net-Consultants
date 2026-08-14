-- CNC MSP FORGE | TAX-BAT-03 v1.0.0 | Phase 6 batch 3: Transport and logistics
-- Documentary verification 13/08/2026, subject to OMP ratification.
-- Applied to ahp-production as msp_batch_transport (version 20260813150130);
-- this file is the repository copy of the applied SQL.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('SANS 3000-4 (RSR)',
 'SANS 3000-4:2011, Railway Safety Management, Human Factors Management, applied as a Railway Safety Regulator regulatory tool for medical fitness in safety critical railway occupations',
 'sans', 'SANS 3000-4:2011', '2011-01-01',
 'In force August 2026 as an RSR regulatory tool. Governs human factors management including medical fitness for safety critical railway occupations, with guidance on conditions and medications incompatible with safety critical duty. Clause level values are applied from the standard itself at examination time; the kernel cites the instrument, not memorised clause values.',
 'Railway Safety Regulator regulatory tools register, rsr.org.za, listing SANS 3000-4 Human Factors Management 2011',
 'Industry railway association references and published extracts of the standard''s medical fitness content',
 'Currency check 13/08/2026: listed as a current RSR regulatory tool; no successor edition located',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

insert into msp_hazard (code, name, category, oel_value, oel_unit, oel_basis, oel_instrument, verification_status)
values ('R', 'Safety critical railway occupation', 'physical', null, null,
        'Not an exposure limit: a fitness determination for safety critical railway duty per the RSR human factors framework',
        'SANS 3000-4:2011 as a Railway Safety Regulator regulatory tool',
        'unverified');

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id,
       'Railway safety critical medical fitness examination per SANS 3000-4',
       'clinical', true, 12, true,
       'Safety critical railway occupations per the operator''s safety management system: vision, hearing, cardiovascular, neurological, and medication review per the standard. Interval at the annual floor; the operator''s safety management system may require more frequent examination and can only tighten.',
       null, li.id
from msp_hazard h
join msp_legal_instrument li on li.short_name = 'SANS 3000-4 (RSR)'
where h.code = 'R';

insert into msp_industry (code, name, sic_reference, regulatory_regime)
values ('TRANS', 'Transport and logistics', 'SIC major division 7, Transport, storage and communication', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i,
     (values
       ('TRANS-ROAD', 'Road freight',              'Batch 3 role map seeded; gate check below'),
       ('TRANS-WARE', 'Warehousing',               'Batch 3 role map seeded; gate check below'),
       ('TRANS-RAIL', 'Rail operations',           'Batch 3 role map seeded; gate check below'),
       ('TRANS-PORT', 'Ports and terminals',       'Maritime medical instruments await verification'),
       ('TRANS-AVGH', 'Aviation ground handling',  'Aviation instruments await verification')
     ) as s(code, name, notes)
where i.code = 'TRANS';

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Long Haul Truck Driver', 'Interprovincial freight driving on extended schedules', 'Prolonged sitting, load securing, fatigue exposure', 'Sustained visual attention, reaction time, no uncontrolled hypoglycaemic risk', 'PrDP goods; dangerous goods PrDP where applicable'),
       ('Local Delivery Driver', 'Urban and regional delivery driving with frequent stops', 'Repeated mounting and dismounting, parcel handling', 'Traffic vigilance, route management', 'PrDP goods'),
       ('Tanker Driver (dangerous goods)', 'Bulk fuel and chemical transport', 'Prolonged driving, coupling and decanting duties', 'Hazard discipline, emergency response readiness, no uncontrolled hypoglycaemic risk', 'Dangerous goods PrDP; hazchem competency'),
       ('Forklift Operator', 'Loading and offloading freight by forklift', 'Prolonged sitting, mounting and dismounting', 'Depth perception, sustained visual attention', 'Forklift operator certification'),
       ('Loading Bay Worker', 'Manual loading, strapping, and tarping of freight', 'Heavy manual handling, work at deck height', 'Instruction following around moving vehicles', 'None beyond induction'),
       ('Diesel Workshop Mechanic', 'Servicing and repairing the truck fleet', 'Heavy component handling, tool vibration, pit work', 'Fault diagnosis, fine motor control', 'Trade certification'),
       ('Transport Controller', 'Fleet scheduling and night shift control room duty', 'Sedentary control room work', 'Sustained attention across night shifts', 'None beyond induction'),
       ('Depot Supervisor', 'Supervision of yard, loading, and dispatch operations', 'Walking the yard among moving vehicles', 'Sustained attention, incident response', 'None beyond induction')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'TRANS-ROAD';

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Reach Truck and Forklift Operator', 'Racking put away and retrieval at height', 'Prolonged sitting, sustained neck extension', 'Depth perception at height, sustained visual attention', 'Forklift and reach truck certification'),
       ('Order Picker', 'Picking and packing orders across shifts', 'Repetitive lifting and carrying, sustained walking', 'Accuracy under rate pressure', 'None beyond induction'),
       ('Cold Store Worker', 'Picking and stock work in chilled and frozen chambers', 'Cold tolerance, manual handling in low temperatures', 'Instruction following under thermal stress', 'None beyond induction'),
       ('Receiving and Dispatch Clerk', 'Checking and recording freight movements', 'Standing at bays, occasional handling', 'Recording accuracy', 'None beyond induction'),
       ('Warehouse Shift Supervisor', 'Supervision of continuous shift operations', 'Walking the floor for full shifts', 'Sustained attention, night shift decision making', 'None beyond induction'),
       ('Hygiene and Housekeeping Worker', 'Cleaning of racking, floors, and welfare areas', 'Manual cleaning work with chemical handling', 'Chemical handling discipline', 'None beyond induction')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'TRANS-WARE';

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Train Driver', 'Driving freight and shunting consists', 'Sustained seated vigilance across shifts', 'Unimpaired vision including colour vision, hearing, reaction time, no condition with sudden incapacity potential', 'Train driver certification; railway safety critical fitness per SANS 3000-4'),
       ('Shunter and Yard Official', 'Coupling, uncoupling, and yard train movements', 'Walking ballast, climbing between vehicles', 'Signal recognition, spatial awareness around moving stock', 'Yard competency; railway safety critical fitness per SANS 3000-4'),
       ('Track Maintenance Worker', 'Permanent way inspection and maintenance', 'Heavy manual track work in weather', 'Lookout discipline, train approach vigilance', 'Track safety competency; railway safety critical fitness per SANS 3000-4'),
       ('Signalling Technician', 'Installing and maintaining signalling and train control equipment', 'Trackside access, mast climbing, electrical work', 'Colour vision for wiring and aspects, fine motor control', 'Trade certification; railway safety critical fitness per SANS 3000-4'),
       ('Rolling Stock Artisan', 'Maintaining locomotives and wagons in the depot', 'Heavy component handling, pit and roof access', 'Fault diagnosis, fine motor control', 'Trade certification'),
       ('Train Control Officer', 'Authorising train movements from the control centre', 'Sedentary control room work across night shifts', 'Sustained concentration, communication precision, no condition with sudden incapacity potential', 'Train control certification; railway safety critical fitness per SANS 3000-4')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'TRANS-RAIL';

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('TRANS-ROAD', 'Long Haul Truck Driver', 'J', 'High', 'Extended professional driving with fatigue exposure'),
  ('TRANS-ROAD', 'Long Haul Truck Driver', 'G', 'Moderate', 'Whole body vibration over long distances'),
  ('TRANS-ROAD', 'Long Haul Truck Driver', 'K', 'Moderate', 'Night driving schedules'),
  ('TRANS-ROAD', 'Long Haul Truck Driver', 'I', 'Moderate', 'Load securing and prolonged sitting'),
  ('TRANS-ROAD', 'Local Delivery Driver', 'J', 'Moderate', 'Urban professional driving'),
  ('TRANS-ROAD', 'Local Delivery Driver', 'I', 'Moderate', 'Frequent parcel handling'),
  ('TRANS-ROAD', 'Tanker Driver (dangerous goods)', 'J', 'High', 'Dangerous goods driving'),
  ('TRANS-ROAD', 'Tanker Driver (dangerous goods)', 'C', 'Moderate', 'Fuel and chemical vapour exposure at decanting'),
  ('TRANS-ROAD', 'Tanker Driver (dangerous goods)', 'K', 'Moderate', 'Scheduled night operation'),
  ('TRANS-ROAD', 'Forklift Operator', 'J', 'Moderate', 'Forklift operation'),
  ('TRANS-ROAD', 'Forklift Operator', 'G', 'Low', 'Yard surface vibration'),
  ('TRANS-ROAD', 'Loading Bay Worker', 'I', 'High', 'Heavy manual loading'),
  ('TRANS-ROAD', 'Loading Bay Worker', 'E', 'Low', 'Work at deck height'),
  ('TRANS-ROAD', 'Diesel Workshop Mechanic', 'A', 'Moderate', 'Workshop noise'),
  ('TRANS-ROAD', 'Diesel Workshop Mechanic', 'G', 'Moderate', 'Tool vibration'),
  ('TRANS-ROAD', 'Diesel Workshop Mechanic', 'C', 'Moderate', 'Diesel, oils, and solvent exposure'),
  ('TRANS-ROAD', 'Diesel Workshop Mechanic', 'M', 'Low', 'Vehicle electrical work'),
  ('TRANS-ROAD', 'Transport Controller', 'K', 'Moderate', 'Night shift control room duty'),
  ('TRANS-ROAD', 'Depot Supervisor', 'A', 'Low', 'Yard noise'),
  ('TRANS-ROAD', 'Depot Supervisor', 'K', 'Moderate', 'Shift supervision'),
  ('TRANS-WARE', 'Reach Truck and Forklift Operator', 'J', 'Moderate', 'Materials handling equipment operation'),
  ('TRANS-WARE', 'Reach Truck and Forklift Operator', 'I', 'Moderate', 'Sustained postural load at height work'),
  ('TRANS-WARE', 'Order Picker', 'I', 'High', 'Repetitive lifting at rate'),
  ('TRANS-WARE', 'Order Picker', 'K', 'Moderate', 'Shift picking operations'),
  ('TRANS-WARE', 'Cold Store Worker', 'H', 'Moderate', 'Thermal stress in frozen chambers'),
  ('TRANS-WARE', 'Cold Store Worker', 'I', 'Moderate', 'Manual handling in cold'),
  ('TRANS-WARE', 'Receiving and Dispatch Clerk', 'I', 'Low', 'Occasional handling at bays'),
  ('TRANS-WARE', 'Warehouse Shift Supervisor', 'K', 'Moderate', 'Night shift supervision'),
  ('TRANS-WARE', 'Warehouse Shift Supervisor', 'A', 'Low', 'Floor noise'),
  ('TRANS-WARE', 'Hygiene and Housekeeping Worker', 'C', 'Moderate', 'Cleaning chemical handling'),
  ('TRANS-WARE', 'Hygiene and Housekeeping Worker', 'I', 'Moderate', 'Manual cleaning work'),
  ('TRANS-RAIL', 'Train Driver', 'R', 'High', 'Safety critical railway occupation'),
  ('TRANS-RAIL', 'Train Driver', 'K', 'Moderate', 'Shift driving rosters'),
  ('TRANS-RAIL', 'Train Driver', 'A', 'Moderate', 'Locomotive cab noise'),
  ('TRANS-RAIL', 'Shunter and Yard Official', 'R', 'High', 'Safety critical yard duties among moving stock'),
  ('TRANS-RAIL', 'Shunter and Yard Official', 'I', 'Moderate', 'Coupling and yard walking'),
  ('TRANS-RAIL', 'Shunter and Yard Official', 'K', 'Moderate', 'Shift yard operations'),
  ('TRANS-RAIL', 'Track Maintenance Worker', 'R', 'High', 'Safety critical trackside work'),
  ('TRANS-RAIL', 'Track Maintenance Worker', 'I', 'High', 'Heavy track work'),
  ('TRANS-RAIL', 'Track Maintenance Worker', 'A', 'Moderate', 'Track machinery noise'),
  ('TRANS-RAIL', 'Track Maintenance Worker', 'H', 'Moderate', 'Outdoor work in weather'),
  ('TRANS-RAIL', 'Signalling Technician', 'R', 'High', 'Safety critical signalling work'),
  ('TRANS-RAIL', 'Signalling Technician', 'M', 'Moderate', 'Electrical signalling equipment'),
  ('TRANS-RAIL', 'Signalling Technician', 'E', 'Moderate', 'Mast and gantry climbing'),
  ('TRANS-RAIL', 'Rolling Stock Artisan', 'A', 'Moderate', 'Depot noise'),
  ('TRANS-RAIL', 'Rolling Stock Artisan', 'G', 'Moderate', 'Tool vibration'),
  ('TRANS-RAIL', 'Rolling Stock Artisan', 'E', 'Moderate', 'Roof access on rolling stock'),
  ('TRANS-RAIL', 'Train Control Officer', 'R', 'High', 'Safety critical movement authorisation'),
  ('TRANS-RAIL', 'Train Control Officer', 'K', 'Moderate', 'Night shift control duty')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('OHS Act', 'Framework Act for depots, warehouses, and rail workplaces'),
  ('NRTA PrDP medical', 'Statutory driver fitness for goods and dangerous goods professional driving'),
  ('SANS 3000-4 (RSR)', 'Medical fitness for safety critical railway occupations per the RSR human factors framework'),
  ('NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026'),
  ('Noise Exposure Regulations, 2024', 'Successor noise instrument, sole operative instrument from 06/09/2026'),
  ('HCA Regulations, 2021', 'Diesel exhaust, fuels, solvents, and cleaning chemicals'),
  ('Ergonomics Regulations, 2019', 'Picking, loading, and driving postural risk surveillance'),
  ('Environmental Regulations for Workplaces, 1987', 'Thermal stress including cold store work assessed by the same battery'),
  ('COIDA', 'Compensation route for all transport occupational injuries and diseases'),
  ('EEA section 7', 'Lawful basis for every medical test, justified against the inherent requirements of each job'),
  ('BCEA night work Code', 'Night driving, night picking, and control room shifts'),
  ('HPCSA Booklet 1', 'Ethical baseline for all examinations under the programme'),
  ('HPCSA Booklet 10', 'Governs any telehealth component of the programme'),
  ('HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(short_name, note) on true
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
where i.code = 'TRANS';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status)
values ('TRANS', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['TRANS-ROAD','TRANS-WARE','TRANS-RAIL']) loop
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
