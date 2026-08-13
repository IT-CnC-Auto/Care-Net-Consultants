-- CNC MSP FORGE | TAX-BAT-13 v1.0.0 | Phase 6 batch 13: Office and professional services
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('Facilities Regulations, 2004',
 'Facilities Regulations, 2004, GNR 924, 3 August 2004, made under the Occupational Health and Safety Act 85 of 1993, replacing the Facilities Regulations, 1990. The Regulations govern workplace sanitation, drinking water (SABS 241 compliant), washing facilities, seating, and changing rooms. They prescribe no standing medical battery: they anchor the workplace welfare context for sedentary and service workforces.',
 'regulation', 'GNR 924, 3 August 2004', '2004-08-03',
 'Promulgated 3 August 2004, replacing the Facilities Regulations, 1990. In force August 2026.',
 'Full regulation texts as published (safety practitioner PDF and workinfo consolidated version)',
 'Official gov.za notice record for the Facilities Regulations of 3 August 2004 and the compliance register entry',
 'Currency check 13/08/2026: in force under the OHS Act with no repeal recorded',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- Office and professional services industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('OFFICE', 'Office and professional services', 'SIC major division 8, Financial intermediation, insurance, real estate and business services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('OFFICE', 'OFF-CORP', 'Corporate and professional offices', 'Batch 13 role map seeded; gate check below'),
  ('OFFICE', 'OFF-CALL', 'Contact centres',                    'Batch 13 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('OFF-CORP', 'Office Administrator', 'Administration and document management', 'Sustained workstation work', 'Documentation accuracy', 'None beyond induction'),
  ('OFF-CORP', 'Professional Consultant (field)', 'Client work with site and travel days', 'Route driving to client sites, workstation work', 'Client engagement, deadline management', 'Driving licence'),
  ('OFF-CORP', 'Office Services and Facilities Assistant', 'Office logistics, storage, and event setup', 'Furniture and stock handling, ladder use for minor tasks', 'Facility coordination', 'None beyond induction'),
  ('OFF-CORP', 'Driver and Messenger', 'Document and parcel runs', 'Daily urban driving, parcel carriage', 'Route vigilance', 'Driving licence'),
  ('OFF-CORP', 'In House Cleaner', 'Office cleaning and kitchen service', 'Repetitive cleaning with chemical use', 'Chemical label discipline', 'None beyond induction'),
  ('OFF-CALL', 'Contact Centre Agent', 'Inbound and outbound customer contact with headset use', 'Sustained seated headset work across shifts', 'Sustained call concentration, conflict de escalation', 'None beyond induction'),
  ('OFF-CALL', 'Contact Centre Team Leader', 'Team supervision and escalation handling', 'Sustained workstation work across shifts', 'Coaching under service pressure', 'None beyond induction'),
  ('OFF-CALL', 'Workforce Management Planner', 'Roster and volume forecasting', 'Sustained workstation work', 'Forecast accuracy', 'None beyond induction'),
  ('OFF-CALL', 'IT Support Technician', 'Desktop and infrastructure support with standby duty', 'Under desk and server room work, equipment handling', 'Fault diagnosis, standby alertness', 'None beyond induction'),
  ('OFF-CALL', 'Learning and Quality Coach', 'Agent training and call quality assessment', 'Sustained workstation and headset monitoring work', 'Assessment consistency', 'None beyond induction')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('OFF-CORP', 'Office Administrator', 'I', 'Moderate', 'Sustained workstation ergonomic load'),
  ('OFF-CORP', 'Professional Consultant (field)', 'J', 'Moderate', 'Client site route driving'),
  ('OFF-CORP', 'Professional Consultant (field)', 'I', 'Moderate', 'Workstation and travel ergonomic load'),
  ('OFF-CORP', 'Office Services and Facilities Assistant', 'I', 'Moderate', 'Furniture and stock handling'),
  ('OFF-CORP', 'Driver and Messenger', 'J', 'Moderate', 'Daily urban driving'),
  ('OFF-CORP', 'Driver and Messenger', 'I', 'Moderate', 'Parcel carriage'),
  ('OFF-CORP', 'In House Cleaner', 'C', 'Moderate', 'Cleaning chemical use'),
  ('OFF-CORP', 'In House Cleaner', 'I', 'Moderate', 'Repetitive cleaning work'),
  ('OFF-CALL', 'Contact Centre Agent', 'K', 'High', 'International hours and night shift patterns'),
  ('OFF-CALL', 'Contact Centre Agent', 'I', 'Moderate', 'Sustained seated workstation load'),
  ('OFF-CALL', 'Contact Centre Agent', 'A', 'Moderate', 'Headset acoustic exposure context'),
  ('OFF-CALL', 'Contact Centre Team Leader', 'K', 'Moderate', 'Shift supervision'),
  ('OFF-CALL', 'Contact Centre Team Leader', 'I', 'Moderate', 'Sustained workstation load'),
  ('OFF-CALL', 'Workforce Management Planner', 'I', 'Moderate', 'Sustained workstation load'),
  ('OFF-CALL', 'IT Support Technician', 'I', 'Moderate', 'Under desk and equipment handling'),
  ('OFF-CALL', 'IT Support Technician', 'K', 'Moderate', 'Standby and change window duty'),
  ('OFF-CALL', 'Learning and Quality Coach', 'I', 'Moderate', 'Sustained workstation and headset load'),
  ('OFF-CALL', 'Learning and Quality Coach', 'A', 'Low', 'Headset monitoring exposure context')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('OFFICE', 'OHS Act', 'Framework Act for office workplaces'),
  ('OFFICE', 'Facilities Regulations, 2004', 'Workplace sanitation, drinking water, and seating duties'),
  ('OFFICE', 'Ergonomics Regulations, 2019', 'Workstation and display screen surveillance'),
  ('OFFICE', 'General Administrative Regulations, 2003', 'Incident reporting and health and safety representative duties'),
  ('OFFICE', 'General Safety Regulations, 1986', 'First aid and PPE duties'),
  ('OFFICE', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026; headset acoustic context'),
  ('OFFICE', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('OFFICE', 'HCA Regulations, 2021', 'Cleaning chemical context'),
  ('OFFICE', 'NRTA PrDP medical', 'Messenger and field driving categories where applicable'),
  ('OFFICE', 'BCEA night work Code', 'Contact centre international hours and night shifts'),
  ('OFFICE', 'COIDA', 'Compensation route for office sector injuries and diseases'),
  ('OFFICE', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('OFFICE', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('OFFICE', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('OFFICE', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['OFF-CORP','OFF-CALL']) loop
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
   set description = description || ' Update 13/08/2026 batch 13: contact centre headset acoustic exposure is carried under hazard A as a context rating; audiometric surveillance applies where the exposure assessment confirms the noise rating limit is approached, per the operative noise instrument.'
 where item_code = 'CR-12.1';
