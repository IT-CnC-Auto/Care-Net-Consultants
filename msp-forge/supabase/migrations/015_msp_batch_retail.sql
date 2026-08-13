-- CNC MSP FORGE | TAX-BAT-06 v1.0.0 | Phase 6 batch 6: Retail and wholesale
-- Documentary verification 13/08/2026, subject to OMP ratification.

-- 1. Promote the Driven Machinery Regulations from pending to verified (closes the DMR leg of CR-13.9)

update msp_legal_instrument
   set full_citation = 'Driven Machinery Regulations, 2015, promulgated 24 June 2015 under GNR 539, 540 and 542 of 2015 in Government Gazettes 38904 and 38905, made under the Occupational Health and Safety Act 85 of 1993. Regulation 18 (lifting machines) requires that lifting machines are operated only by persons who are trained, certified competent, authorised in writing, and in possession of a medical certificate of fitness.',
       gazette_reference = 'GNR 539, 540 and 542 of 2015; GG 38904 and 38905; 24 June 2015',
       effective_date = '2015-06-24'
 where short_name = 'Driven Machinery Regulations' and status = 'pending';

select msp_verify_instrument(
  (select id from msp_legal_instrument where short_name = 'Driven Machinery Regulations'),
  'Consolidated regulation text, SAFLII dmr2015283, and the Department of Employment and Labour published regulation PDF; regulation 18 lifting machine operator medical certificate of fitness provision confirmed in both',
  'Attorney promulgation notices (Lexology and Mondaq records of GNR 539, 540 and 542 of 2015, Government Gazettes 38904 and 38905, 24 June 2015) and the gazette record aggregator entry for the 2017 Guidelines',
  'Currency check 13/08/2026: in force; Guidelines for the Driven Machinery Regulations published 31 March 2017 (GG 40734); National Code of Practice for the Training Providers of Lifting Machine Operators, 2024 incorporated into the Regulations',
  'Promulgated 24 June 2015, replacing the Driven Machinery Regulations of 1988. Guidelines published 31 March 2017 (GG 40734). The 2024 National Code of Practice for the Training Providers of Lifting Machine Operators has been incorporated into the Regulations. In force August 2026.',
  'Claude Code build agent, documentary verification, subject to OMP ratification',
  '2027-08-13');

update msp_hazard
   set oel_instrument = 'National Road Traffic Act 93 of 1996, PrDP medical fitness provisions; Driven Machinery Regulations, 2015, regulation 18 medical certificate of fitness for lifting machine operators'
 where code = 'J';

-- 2. Lifting machine operator protocol (hazard J, dual justification with EEA section 7)

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id,
       'Lifting machine operator medical certificate of fitness',
       'clinical', true, 12, true,
       'Operators of forklifts, reach trucks, cranes, and other lifting machines: regulation 18 of the Driven Machinery Regulations, 2015 requires a medical certificate of fitness alongside training, competency certification, and written authorisation. The examination addresses vision, hearing, musculoskeletal capacity, and conditions with sudden incapacity potential, against the inherent requirements of the operating role per Employment Equity Act section 7.',
       null,
       (select id from msp_legal_instrument where short_name = 'Driven Machinery Regulations' and status = 'verified')
from msp_hazard h where h.code = 'J';

-- 3. Retail and wholesale industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('RETAIL', 'Retail and wholesale', 'SIC major division 6, Wholesale and retail trade', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('RETAIL', 'RET-STORE', 'Retail stores',                'Batch 6 role map seeded; gate check below'),
  ('RETAIL', 'RET-WHOLE', 'Wholesale and distribution',   'Batch 6 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('RET-STORE', 'Cashier and Front End Assistant', 'Point of sale operation and customer service', 'Prolonged standing, repetitive scanning and packing', 'Sustained attention, cash accuracy, customer interaction', 'None beyond induction'),
  ('RET-STORE', 'Shelf Packer and Merchandiser', 'Stock replenishment including night fill', 'Repetitive lifting, reaching, and trolley work', 'Planogram accuracy, instruction following', 'None beyond induction'),
  ('RET-STORE', 'Butchery Worker', 'Meat cutting, processing, and cold room work', 'Carcass handling, band saw and blade work, cold room exposure', 'Blade and machine discipline, hygiene discipline', 'None beyond induction'),
  ('RET-STORE', 'Bakery Worker', 'In store baking and dough production', 'Flour and ingredient handling, oven work, early shifts', 'Recipe and allergen discipline', 'None beyond induction'),
  ('RET-STORE', 'Fresh Produce and Cold Chain Assistant', 'Produce preparation and cold chain management', 'Cold room rotation, wet preparation work', 'Stock rotation vigilance, hygiene discipline', 'None beyond induction'),
  ('RET-STORE', 'Receiving and Stockroom Assistant', 'Goods receiving and back of store handling', 'Sustained heavy manual handling, pallet breakdown', 'Receiving accuracy, vehicle and dock awareness', 'None beyond induction'),
  ('RET-WHOLE', 'Forklift Operator (warehouse)', 'Counterbalance forklift operation in the distribution centre', 'Mounting and dismounting, sustained seated operation, load judgement', 'Depth perception, load stability judgement, pedestrian vigilance, no condition with sudden incapacity potential', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015'),
  ('RET-WHOLE', 'Reach Truck and VNA Operator', 'Reach truck and very narrow aisle operation including man up units', 'Elevated cab operation, sustained head up posture', 'Height and clearance judgement, no vertigo in man up operation', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015'),
  ('RET-WHOLE', 'Warehouse Order Picker', 'Case picking to voice or scanner instruction', 'Sustained repetitive lifting at rate, trolley and pallet work', 'Pick accuracy under rate pressure', 'None beyond induction'),
  ('RET-WHOLE', 'Distribution Driver', 'Delivery vehicle operation to stores and customers', 'Prolonged driving, tail lift and hand unloading', 'Route vigilance, reaction time, no uncontrolled hypoglycaemic risk', 'PrDP for the applicable vehicle class'),
  ('RET-WHOLE', 'Cold Store Worker', 'Order assembly inside chilled and frozen chambers', 'Sustained work at deep freeze temperatures with PPE burden', 'Cold exposure self monitoring, instruction following', 'None beyond induction'),
  ('RET-WHOLE', 'Loading Bay Controller', 'Dock scheduling, vehicle marshalling, and load checking', 'Dock walking, occasional handling', 'Vehicle and pedestrian separation vigilance', 'None beyond induction')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('RET-STORE', 'Cashier and Front End Assistant', 'I', 'Moderate', 'Repetitive scanning and prolonged standing'),
  ('RET-STORE', 'Cashier and Front End Assistant', 'K', 'Moderate', 'Extended retail trading hours'),
  ('RET-STORE', 'Shelf Packer and Merchandiser', 'I', 'Moderate', 'Repetitive lifting and reaching'),
  ('RET-STORE', 'Shelf Packer and Merchandiser', 'K', 'Moderate', 'Night fill shifts'),
  ('RET-STORE', 'Butchery Worker', 'D', 'Moderate', 'Raw meat and sharps exposure'),
  ('RET-STORE', 'Butchery Worker', 'I', 'Moderate', 'Carcass and block handling'),
  ('RET-STORE', 'Butchery Worker', 'A', 'Moderate', 'Band saw and grinder noise'),
  ('RET-STORE', 'Butchery Worker', 'H', 'Moderate', 'Cold room thermal exposure'),
  ('RET-STORE', 'Bakery Worker', 'B', 'Moderate', 'Flour dust as a respiratory sensitiser context'),
  ('RET-STORE', 'Bakery Worker', 'H', 'Moderate', 'Oven heat'),
  ('RET-STORE', 'Bakery Worker', 'I', 'Moderate', 'Dough and tray handling'),
  ('RET-STORE', 'Bakery Worker', 'K', 'Moderate', 'Early production shifts'),
  ('RET-STORE', 'Fresh Produce and Cold Chain Assistant', 'H', 'Moderate', 'Cold room rotation'),
  ('RET-STORE', 'Fresh Produce and Cold Chain Assistant', 'I', 'Moderate', 'Crate and pallet handling'),
  ('RET-STORE', 'Receiving and Stockroom Assistant', 'I', 'High', 'Sustained heavy goods handling'),
  ('RET-STORE', 'Receiving and Stockroom Assistant', 'A', 'Low', 'Dock and compactor noise'),
  ('RET-WHOLE', 'Forklift Operator (warehouse)', 'J', 'High', 'Lifting machine operation under the Driven Machinery Regulations, 2015'),
  ('RET-WHOLE', 'Forklift Operator (warehouse)', 'A', 'Moderate', 'Warehouse plant noise'),
  ('RET-WHOLE', 'Forklift Operator (warehouse)', 'K', 'Moderate', 'Distribution centre shifts'),
  ('RET-WHOLE', 'Reach Truck and VNA Operator', 'J', 'High', 'Lifting machine operation under the Driven Machinery Regulations, 2015'),
  ('RET-WHOLE', 'Reach Truck and VNA Operator', 'E', 'Moderate', 'Man up elevated cab operation'),
  ('RET-WHOLE', 'Reach Truck and VNA Operator', 'K', 'Moderate', 'Distribution centre shifts'),
  ('RET-WHOLE', 'Warehouse Order Picker', 'I', 'High', 'Repetitive case picking at rate'),
  ('RET-WHOLE', 'Warehouse Order Picker', 'K', 'Moderate', 'Shift picking operations'),
  ('RET-WHOLE', 'Distribution Driver', 'J', 'High', 'Professional driving with PrDP requirement'),
  ('RET-WHOLE', 'Distribution Driver', 'I', 'Moderate', 'Tail lift and hand unloading'),
  ('RET-WHOLE', 'Distribution Driver', 'K', 'Moderate', 'Early and night delivery windows'),
  ('RET-WHOLE', 'Cold Store Worker', 'H', 'High', 'Sustained deep freeze thermal stress'),
  ('RET-WHOLE', 'Cold Store Worker', 'I', 'Moderate', 'Order assembly handling'),
  ('RET-WHOLE', 'Cold Store Worker', 'K', 'Moderate', 'Cold chain shift work'),
  ('RET-WHOLE', 'Loading Bay Controller', 'I', 'Moderate', 'Load checking and occasional handling'),
  ('RET-WHOLE', 'Loading Bay Controller', 'A', 'Moderate', 'Dock vehicle and plant noise')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('RETAIL', 'OHS Act', 'Framework Act for retail and wholesale workplaces'),
  ('RETAIL', 'Driven Machinery Regulations', 'Forklift, reach truck, and lifting machine operator medical certificate of fitness per regulation 18'),
  ('RETAIL', 'Ergonomics Regulations, 2019', 'Repetitive handling, checkout, and picking work surveillance'),
  ('RETAIL', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for butchery, bakery, and dock plant'),
  ('RETAIL', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('RETAIL', 'HCA Regulations, 2021', 'Cleaning chemicals and bakery ingredient dust context'),
  ('RETAIL', 'HBA Regulations, 2022', 'Butchery raw product and general biological exposure'),
  ('RETAIL', 'Environmental Regulations for Workplaces, 1987', 'Cold chain and oven thermal environments'),
  ('RETAIL', 'NRTA PrDP medical', 'Distribution driving categories'),
  ('RETAIL', 'BCEA night work Code', 'Night fill, early production, and distribution shifts'),
  ('RETAIL', 'COIDA', 'Compensation route for retail and wholesale injuries and diseases'),
  ('RETAIL', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('RETAIL', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('RETAIL', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('RETAIL', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['RET-STORE','RET-WHOLE']) loop
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

-- 4. Register updates

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 6: the Driven Machinery Regulations, 2015 are now triple verified (GNR 539, 540 and 542 of 2015, GG 38904 and 38905, 24 June 2015) and the regulation 18 lifting machine operator medical certificate of fitness anchors a dedicated hazard J protocol. The General Safety, General Administrative, and General Machinery Regulations remain open on this item.'
 where item_code = 'CR-13.9';

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 6: retail bakery flour dust is carried under hazard B as a respiratory sensitiser context pending a substance specific OEL confirmation; butchery and cold chain biological exposure is carried under the HBA framework.'
 where item_code = 'CR-12.1';
