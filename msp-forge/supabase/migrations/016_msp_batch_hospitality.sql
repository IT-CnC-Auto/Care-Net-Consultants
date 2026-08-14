-- CNC MSP FORGE | TAX-BAT-07 v1.0.0 | Phase 6 batch 7: Hospitality and food service
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('Food Premises Hygiene Regulations, R638 of 2018',
 'Regulations Governing General Hygiene Requirements for Food Premises, the Transport of Food and Related Matters, R638 of 2018, Government Gazette 41730, 22 June 2018, made under the Foodstuffs, Cosmetics and Disinfectants Act 54 of 1972. The Regulations require that no person suffering from a communicable or infectious condition in a transmissible form handles food, and govern the health, hygiene, and protective clothing of food handlers.',
 'regulation', 'R638, GG 41730, 22 June 2018', '2018-06-22',
 'Promulgated 22 June 2018, repealing and replacing R962 of 2012; Certificates of Acceptability issued under the repealed regulations expired 22 June 2019. In force August 2026 as the operative national food premises hygiene standard. This is a food safety instrument: it excludes symptomatic handlers from food work rather than prescribing an occupational medical battery, and the lawful basis for any fitness testing remains EEA section 7.',
 'Full regulation texts republished by food safety practitioners (ASC and Food Consulting Services), food handler definition and communicable condition exclusion confirmed',
 'Gazette record aggregator entry GGN 41730 00638 of 22 June 2018 under the Foodstuffs, Cosmetics and Disinfectants Act 54 of 1972, and the trade press gazettal record of the R962 replacement',
 'Currency check 13/08/2026: 2026 compliance and Certificate of Acceptability guides confirm R638 remains the operative standard',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- Food handler protocol (hazard D, exclusion regime under R638, dual justification with EEA section 7)

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id,
       'Food handler fitness assessment (communicable condition screening)',
       'clinical', true, 12, true,
       'Food handlers per the R638 of 2018 definition: the Regulations exclude any person with a communicable or infectious condition in a transmissible form from handling food. The assessment screens fitness to handle food (skin, gastrointestinal, and respiratory communicable condition screen with symptom declaration) against the inherent requirements of the role per Employment Equity Act section 7. Care Net screens and does not diagnose; symptomatic exclusion and return to work rest with the OMP''s written protocol.',
       null,
       (select id from msp_legal_instrument where short_name = 'Food Premises Hygiene Regulations, R638 of 2018')
from msp_hazard h where h.code = 'D';

-- Hospitality and food service industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('HOSP', 'Hospitality and food service', 'SIC major division 6, Catering and accommodation services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('HOSP', 'HOSP-ACCOM', 'Hotels and accommodation',   'Batch 7 role map seeded; gate check below'),
  ('HOSP', 'HOSP-FOOD',  'Restaurants and catering',   'Batch 7 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('HOSP-FOOD', 'Head Chef and Sous Chef', 'Kitchen leadership and service line cooking', 'Sustained standing in kitchen heat, pan and pot handling', 'Service coordination under pressure, allergen and hygiene discipline', 'None beyond induction'),
  ('HOSP-FOOD', 'Line Cook', 'Station cooking on the service line', 'Sustained standing, heat and burn exposure, repetitive preparation', 'Order accuracy under rate pressure, hygiene discipline', 'None beyond induction'),
  ('HOSP-FOOD', 'Kitchen Assistant and Dishwasher', 'Preparation support, pot wash, and kitchen cleaning', 'Wet work with detergents, heavy pot handling, heat and steam', 'Chemical label discipline, hygiene discipline', 'None beyond induction'),
  ('HOSP-FOOD', 'Waiter and Front of House Server', 'Table service and guest interaction', 'Prolonged standing and walking, tray carriage', 'Order accuracy, guest interaction composure', 'None beyond induction'),
  ('HOSP-FOOD', 'Catering and Events Cook', 'Off site preparation and service for functions', 'Load in and load out handling, mobile kitchen heat', 'Menu execution across venues, hygiene discipline in temporary kitchens', 'Driving licence where applicable'),
  ('HOSP-FOOD', 'Fast Food Counter Assistant', 'Counter service, fryer operation, and closing shifts', 'Standing shifts, fryer heat and oil handling', 'Rate pressure accuracy, hygiene discipline', 'None beyond induction'),
  ('HOSP-ACCOM', 'Room Attendant and Housekeeper', 'Guest room servicing and deep cleaning', 'Sustained repetitive bending, lifting, and trolley work with cleaning chemicals', 'Room standard vigilance, chemical label discipline', 'None beyond induction'),
  ('HOSP-ACCOM', 'Laundry Worker', 'On premise laundry processing', 'Heat and steam exposure, sustained linen handling', 'Machine and chemical discipline', 'None beyond induction'),
  ('HOSP-ACCOM', 'Hotel Maintenance Technician', 'Building, plant, and room maintenance', 'Ladder access, electrical and plumbing work', 'Fault diagnosis, electrical discipline', 'Wireman''s licence where applicable'),
  ('HOSP-ACCOM', 'Porter and Concierge Assistant', 'Luggage handling and guest assistance', 'Repetitive luggage lifting and carriage', 'Guest interaction composure', 'None beyond induction'),
  ('HOSP-ACCOM', 'Night Auditor and Front Office Assistant', 'Overnight reception and daily reconciliation', 'Sedentary night duty', 'Sustained overnight vigilance, reconciliation accuracy', 'None beyond induction'),
  ('HOSP-ACCOM', 'Pool and Leisure Attendant', 'Pool water treatment and leisure area supervision', 'Chemical dosing, outdoor supervision', 'Dosing precision, guest safety vigilance', 'None beyond induction')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('HOSP-FOOD', 'Head Chef and Sous Chef', 'H', 'Moderate', 'Service line kitchen heat'),
  ('HOSP-FOOD', 'Head Chef and Sous Chef', 'I', 'Moderate', 'Sustained standing and pot handling'),
  ('HOSP-FOOD', 'Head Chef and Sous Chef', 'K', 'Moderate', 'Split and evening service shifts'),
  ('HOSP-FOOD', 'Head Chef and Sous Chef', 'D', 'Moderate', 'Food handling under R638 of 2018'),
  ('HOSP-FOOD', 'Line Cook', 'H', 'Moderate', 'Station heat and burn exposure'),
  ('HOSP-FOOD', 'Line Cook', 'I', 'Moderate', 'Repetitive preparation work'),
  ('HOSP-FOOD', 'Line Cook', 'K', 'Moderate', 'Evening and weekend service'),
  ('HOSP-FOOD', 'Line Cook', 'D', 'Moderate', 'Food handling under R638 of 2018'),
  ('HOSP-FOOD', 'Kitchen Assistant and Dishwasher', 'C', 'Moderate', 'Detergent and sanitiser wet work'),
  ('HOSP-FOOD', 'Kitchen Assistant and Dishwasher', 'I', 'Moderate', 'Heavy pot and crate handling'),
  ('HOSP-FOOD', 'Kitchen Assistant and Dishwasher', 'H', 'Moderate', 'Pot wash heat and steam'),
  ('HOSP-FOOD', 'Kitchen Assistant and Dishwasher', 'D', 'Moderate', 'Food area work under R638 of 2018'),
  ('HOSP-FOOD', 'Waiter and Front of House Server', 'I', 'Moderate', 'Prolonged standing and tray carriage'),
  ('HOSP-FOOD', 'Waiter and Front of House Server', 'K', 'Moderate', 'Evening and weekend service'),
  ('HOSP-FOOD', 'Waiter and Front of House Server', 'D', 'Low', 'Plated food contact under R638 of 2018'),
  ('HOSP-FOOD', 'Catering and Events Cook', 'H', 'Moderate', 'Mobile kitchen heat'),
  ('HOSP-FOOD', 'Catering and Events Cook', 'I', 'Moderate', 'Load in and load out handling'),
  ('HOSP-FOOD', 'Catering and Events Cook', 'K', 'Moderate', 'Event driven irregular hours'),
  ('HOSP-FOOD', 'Catering and Events Cook', 'D', 'Moderate', 'Food handling under R638 of 2018'),
  ('HOSP-FOOD', 'Catering and Events Cook', 'J', 'Low', 'Driving to event venues'),
  ('HOSP-FOOD', 'Fast Food Counter Assistant', 'K', 'Moderate', 'Late closing shifts'),
  ('HOSP-FOOD', 'Fast Food Counter Assistant', 'I', 'Moderate', 'Standing counter shifts'),
  ('HOSP-FOOD', 'Fast Food Counter Assistant', 'H', 'Moderate', 'Fryer heat and oil handling'),
  ('HOSP-FOOD', 'Fast Food Counter Assistant', 'D', 'Moderate', 'Food handling under R638 of 2018'),
  ('HOSP-ACCOM', 'Room Attendant and Housekeeper', 'I', 'High', 'Sustained repetitive room servicing'),
  ('HOSP-ACCOM', 'Room Attendant and Housekeeper', 'C', 'Moderate', 'Cleaning chemical use'),
  ('HOSP-ACCOM', 'Laundry Worker', 'H', 'Moderate', 'Laundry heat and steam'),
  ('HOSP-ACCOM', 'Laundry Worker', 'I', 'Moderate', 'Sustained linen handling'),
  ('HOSP-ACCOM', 'Laundry Worker', 'C', 'Moderate', 'Laundry chemical handling'),
  ('HOSP-ACCOM', 'Laundry Worker', 'A', 'Moderate', 'Laundry plant noise'),
  ('HOSP-ACCOM', 'Hotel Maintenance Technician', 'M', 'Moderate', 'Building electrical maintenance'),
  ('HOSP-ACCOM', 'Hotel Maintenance Technician', 'E', 'Moderate', 'Ladder and roof access'),
  ('HOSP-ACCOM', 'Hotel Maintenance Technician', 'C', 'Low', 'Maintenance chemical use'),
  ('HOSP-ACCOM', 'Porter and Concierge Assistant', 'I', 'Moderate', 'Repetitive luggage handling'),
  ('HOSP-ACCOM', 'Night Auditor and Front Office Assistant', 'K', 'High', 'Standing overnight duty'),
  ('HOSP-ACCOM', 'Pool and Leisure Attendant', 'C', 'Moderate', 'Chlorine and dosing chemical handling'),
  ('HOSP-ACCOM', 'Pool and Leisure Attendant', 'D', 'Low', 'Pool water biological context')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('HOSP', 'OHS Act', 'Framework Act for hospitality workplaces'),
  ('HOSP', 'Food Premises Hygiene Regulations, R638 of 2018', 'Food handler health, hygiene, and communicable condition exclusion'),
  ('HOSP', 'HCA Regulations, 2021', 'Kitchen, laundry, and pool treatment chemicals'),
  ('HOSP', 'HBA Regulations, 2022', 'Food area and pool water biological context'),
  ('HOSP', 'Environmental Regulations for Workplaces, 1987', 'Kitchen and laundry thermal environments'),
  ('HOSP', 'Ergonomics Regulations, 2019', 'Housekeeping, kitchen, and portering surveillance'),
  ('HOSP', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for laundry and kitchen plant'),
  ('HOSP', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('HOSP', 'Electrical Machinery and Installation Regulations', 'Hotel maintenance electrical work context'),
  ('HOSP', 'BCEA night work Code', 'Night audit, closing shifts, and split shifts'),
  ('HOSP', 'COIDA', 'Compensation route for hospitality injuries and diseases'),
  ('HOSP', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('HOSP', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('HOSP', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('HOSP', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['HOSP-ACCOM','HOSP-FOOD']) loop
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
   set description = description || ' Update 13/08/2026 batch 7: food handler screening is an exclusion regime under R638 of 2018 (a food safety instrument under the Foodstuffs, Cosmetics and Disinfectants Act 54 of 1972), not an occupational medical battery; the lawful testing basis remains EEA section 7 and Care Net screens fitness to handle food without diagnosing.'
 where item_code = 'CR-12.1';
