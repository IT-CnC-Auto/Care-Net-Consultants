-- CNC MSP FORGE | TAX-BAT-12 v1.0.0 | Phase 6 batch 12: Education
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('General Administrative Regulations, 2003',
 'General Administrative Regulations, 2003, GNR 929, Government Gazette 25129, 25 June 2003, made under section 43 of the Occupational Health and Safety Act 85 of 1993 after consultation with the Advisory Council for Occupational Health and Safety, repealing GNR 1449 of 6 September 1996. The Regulations govern incident reporting and recording, health and safety representatives and committees, and administrative duties. They prescribe no standing medical battery: the incident recording duties they impose feed the surveillance programme''s review triggers.',
 'regulation', 'GNR 929, GG 25129, 25 June 2003', '2003-06-25',
 'Published 25 June 2003, repealing the 1996 General Administrative Regulations (GNR 1449). In force August 2026.',
 'Full regulation texts, SAFLII gar2003335 and the published regulation PDFs',
 'ILO NATLEX record for GNR 929 and the gazette archive copy of Government Gazette 25129 of 25 June 2003',
 'Currency check 13/08/2026: in force under the OHS Act with no repeal recorded',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- Education industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('EDU', 'Education', 'SIC major division 9, Community, social and personal services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('EDU', 'EDU-SCHOOL',   'Schools and early childhood',        'Batch 12 role map seeded; gate check below'),
  ('EDU', 'EDU-TERTIARY', 'Tertiary and training providers',    'Batch 12 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('EDU-SCHOOL', 'Educator (classroom)', 'Classroom teaching in a congregate setting', 'Sustained standing and voice load', 'Classroom management, learner safeguarding vigilance', 'SACE registration'),
  ('EDU-SCHOOL', 'Early Childhood Practitioner', 'Care and education of young children', 'Child lifting, floor level work', 'Constant supervision vigilance, hygiene discipline', 'ECD qualification per the sector framework'),
  ('EDU-SCHOOL', 'School Groundsman and Caretaker', 'Grounds, sports field, and building upkeep', 'Sustained grounds labour with powered equipment', 'Equipment and learner separation discipline', 'None beyond induction'),
  ('EDU-SCHOOL', 'School Feeding Scheme Cook', 'Preparation of learner meals', 'Kitchen work with pot handling and heat', 'Food hygiene discipline, portion management', 'None beyond induction'),
  ('EDU-SCHOOL', 'School Transport Driver', 'Learner transport on scheduled routes', 'Prolonged route driving with learner supervision', 'Route vigilance, learner conduct management, no uncontrolled hypoglycaemic risk', 'PrDP for passenger transport'),
  ('EDU-TERTIARY', 'Lecturer and Trainer', 'Lecturing and skills training delivery', 'Sustained standing and voice load', 'Curriculum delivery, assessment integrity', 'None beyond induction'),
  ('EDU-TERTIARY', 'Teaching Laboratory Technician', 'Preparation and supervision of teaching laboratories', 'Bench work with chemical and specimen handling', 'Preparation precision, laboratory discipline', 'None beyond induction'),
  ('EDU-TERTIARY', 'Workshop Instructor (trades training)', 'Practical trades instruction in workshops', 'Demonstration work on machinery and welding bays', 'Machine guarding discipline, trainee supervision vigilance', 'Trade certification'),
  ('EDU-TERTIARY', 'Residence Caretaker', 'Student residence upkeep and supervision', 'Cleaning and maintenance rounds', 'Resident welfare vigilance', 'None beyond induction'),
  ('EDU-TERTIARY', 'Campus Maintenance Artisan', 'Campus building and services maintenance', 'Ladder access, manual trade work', 'Trade fault diagnosis', 'Trade certification')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('EDU-SCHOOL', 'Educator (classroom)', 'I', 'Moderate', 'Sustained standing and voice load'),
  ('EDU-SCHOOL', 'Educator (classroom)', 'D', 'Moderate', 'Congregate setting communicable disease context'),
  ('EDU-SCHOOL', 'Early Childhood Practitioner', 'D', 'Moderate', 'Young child contact communicable disease context'),
  ('EDU-SCHOOL', 'Early Childhood Practitioner', 'I', 'Moderate', 'Child lifting and floor level work'),
  ('EDU-SCHOOL', 'School Groundsman and Caretaker', 'I', 'High', 'Sustained grounds labour'),
  ('EDU-SCHOOL', 'School Groundsman and Caretaker', 'A', 'Moderate', 'Mower and brush cutter noise'),
  ('EDU-SCHOOL', 'School Groundsman and Caretaker', 'C', 'Moderate', 'Herbicide and cleaning chemical use'),
  ('EDU-SCHOOL', 'School Groundsman and Caretaker', 'H', 'Moderate', 'Outdoor grounds work in heat'),
  ('EDU-SCHOOL', 'School Feeding Scheme Cook', 'D', 'Moderate', 'Food handling under R638 of 2018'),
  ('EDU-SCHOOL', 'School Feeding Scheme Cook', 'H', 'Moderate', 'Kitchen heat'),
  ('EDU-SCHOOL', 'School Feeding Scheme Cook', 'I', 'Moderate', 'Pot and stock handling'),
  ('EDU-SCHOOL', 'School Transport Driver', 'J', 'High', 'Learner transport with passenger PrDP requirement'),
  ('EDU-SCHOOL', 'School Transport Driver', 'K', 'Moderate', 'Early route starts'),
  ('EDU-TERTIARY', 'Lecturer and Trainer', 'I', 'Moderate', 'Sustained standing and voice load'),
  ('EDU-TERTIARY', 'Teaching Laboratory Technician', 'C', 'Moderate', 'Teaching laboratory chemical handling'),
  ('EDU-TERTIARY', 'Teaching Laboratory Technician', 'D', 'Moderate', 'Specimen and culture handling'),
  ('EDU-TERTIARY', 'Workshop Instructor (trades training)', 'A', 'Moderate', 'Workshop machinery noise'),
  ('EDU-TERTIARY', 'Workshop Instructor (trades training)', 'M', 'Moderate', 'Electrical demonstration work'),
  ('EDU-TERTIARY', 'Workshop Instructor (trades training)', 'B', 'Moderate', 'Grinding and welding particulate'),
  ('EDU-TERTIARY', 'Workshop Instructor (trades training)', 'I', 'Moderate', 'Demonstration and setup handling'),
  ('EDU-TERTIARY', 'Residence Caretaker', 'I', 'Moderate', 'Cleaning and maintenance rounds'),
  ('EDU-TERTIARY', 'Residence Caretaker', 'C', 'Moderate', 'Cleaning chemical use'),
  ('EDU-TERTIARY', 'Campus Maintenance Artisan', 'E', 'Moderate', 'Ladder and roof access'),
  ('EDU-TERTIARY', 'Campus Maintenance Artisan', 'M', 'Moderate', 'Building electrical maintenance'),
  ('EDU-TERTIARY', 'Campus Maintenance Artisan', 'I', 'Moderate', 'Manual trade work')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('EDU', 'OHS Act', 'Framework Act for education workplaces'),
  ('EDU', 'General Administrative Regulations, 2003', 'Incident reporting and health and safety representative duties'),
  ('EDU', 'General Safety Regulations, 1986', 'First aid, PPE, and elevated position duties'),
  ('EDU', 'HBA Regulations, 2022', 'Congregate setting and teaching laboratory biological exposure'),
  ('EDU', 'HCA Regulations, 2021', 'Teaching laboratory and grounds chemicals'),
  ('EDU', 'Food Premises Hygiene Regulations, R638 of 2018', 'Feeding scheme and residence kitchen food handling'),
  ('EDU', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for workshops and grounds equipment'),
  ('EDU', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('EDU', 'Ergonomics Regulations, 2019', 'Grounds labour and workstation surveillance'),
  ('EDU', 'Environmental Regulations for Workplaces, 1987', 'Kitchen heat and outdoor grounds work'),
  ('EDU', 'NRTA PrDP medical', 'Learner transport passenger driving categories'),
  ('EDU', 'BCEA night work Code', 'Early transport and residence duty patterns'),
  ('EDU', 'COIDA', 'Compensation route for education sector injuries and diseases'),
  ('EDU', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('EDU', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('EDU', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('EDU', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['EDU-SCHOOL','EDU-TERTIARY']) loop
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
   set description = description || ' Update 13/08/2026 batch 12: the General Administrative Regulations, 2003 (GNR 929, GG 25129, 25 June 2003) are now triple verified. All four instrument legs of this item (General Safety, General Administrative, General Machinery, and Driven Machinery Regulations) are verified and the item is resolved, subject only to the General Machinery replacement draft held on the watchdog.',
       status = 'resolved',
       resolution = 'All four regulation legs triple verified across batches 6, 9, 11, and 12; General Machinery 2025 replacement draft on the verification watchdog.',
       resolved_by = 'Claude Code build agent, documentary verification, subject to OMP ratification',
       resolved_on = '2026-08-13'
 where item_code = 'CR-13.9';
