-- CNC MSP FORGE | KRN-LEG-02 v1.1.0 | Legislation currency release 16/09/2026
-- Kernel learning update per SOP-KERNEL-AGENT.md section 3 leg 2, worked from the
-- Care Net Consultants OH Value Chain Regulatory Instrument Pack dated 15/09/2026
-- (primary Gazette texts, dual URL corroborated, currency checked on that date) on
-- the MD's instruction of 16/09/2026 relayed by Odendaal. Documentary verification by
-- the IT maintenance agent, subject to OMP ratification of release 1.1.0.
--
-- What changes:
--   1. The noise transition scheduled by RULE-NOISE-TRANSITION is executed in the
--      kernel: the NIHL Regulations, 2003 are superseded (repealed 06/09/2026 by
--      regulation 18 of the Noise Exposure Regulations, 2024) and every protocol
--      that cited them now cites the 2024 Regulations.
--   2. The Physical Agents Regulations, 2024 (GN 5952, GG 52226) enter as verified
--      with the Table 1 values read from the Gazette text; the Environmental
--      Regulations for Workplaces, 1987 are superseded (repealed 06/09/2026 by
--      regulation 21); heat and vibration citations move across; the 2024
--      Regulations are mapped to every industry.
--   3. The Code of Practice for Audiometry and SANS 10083 leave pending: verified
--      (the Code from the Gazette bundle, SANS 10083:2023 Ed 6.01 from the licensed
--      copy CNC now holds). SANS 451:2008 (spirometry, licensed copy) enters verified.
--   4. Circular Instruction 171 (COIDA, hearing loss disablement), POPIA, the Health
--      Professions Act and the Nursing Act enter as verified instruments. The
--      Asbestos Abatement Regulations, 2020 enter as verified and are mapped to the
--      industries where asbestos work occurs.
--   5. Currency checks of 15/09/2026 are appended to the pack instruments already
--      verified (OHS Act, Construction, HCA, HBA, Lead, GAR, GSR incl. the 2025
--      amendment notice, COIDA, EEA, NER).
--   6. Register: CR-12.3 and CR-13.9 appended; CR-14.1 to CR-14.5 opened. Release
--      1.1.0 cut for OMP ratification; learning update logged.
-- Idempotent: every insert is guarded by not exists, every update is keyed by name.
-- Repository and database must agree: commit this file and apply it in one action.

-- 0. Preflight ------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from msp_legal_instrument where short_name = 'Noise Exposure Regulations, 2024' and status = 'verified') then
    raise exception 'preflight: Noise Exposure Regulations, 2024 must be verified before the transition can execute';
  end if;
  if exists (select 1 from msp_kernel_version where semver = '1.1.0') then
    raise exception 'preflight: kernel release 1.1.0 already exists; migration 042 has been applied';
  end if;
end $$;

-- 1. Noise transition executed --------------------------------------------------

update msp_legal_instrument
   set status = 'superseded',
       amendment_history = coalesce(amendment_history, '') || ' Repealed with effect from 06/09/2026 by regulation 18 of the Noise Exposure Regulations, 2024 (GN 5953, GG 52226). Superseded in the kernel on 16/09/2026; retained for packs generated before the transition date and for legacy compensation claims. Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.1.7): repeal effective.'
 where short_name = 'NIHL Regulations, 2003'
   and status = 'verified';

update msp_test_protocol
   set legal_basis_id = (select id from msp_legal_instrument where short_name = 'Noise Exposure Regulations, 2024' and status = 'verified')
 where legal_basis_id = (select id from msp_legal_instrument where short_name = 'NIHL Regulations, 2003');

update msp_hazard
   set oel_instrument = 'Noise Exposure Regulations, 2024 (GN 5953, GG 52226, 6 March 2025), the sole operative noise instrument from 06/09/2026: 85 dB(A) noise rating limit retained; action level of 82 dB(A) continuous and 135 dB(C) impulse where ototoxic chemical or whole body vibration co exposure exists; audiometry per the Code of Practice for Audiometry published with the Regulations',
       oel_basis = '8 hour rating level, the noise rating limit (regulation 1 definitions)'
 where code = 'A';

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Transition complete: from 06/09/2026 the sole operative noise instrument; the NIHL Regulations, 2003 are repealed. Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.1.3, gov.za and labour.gov.za texts): in force, no amendment located.',
       review_due = greatest(coalesce(review_due, current_date), date '2027-09-15')
 where short_name = 'Noise Exposure Regulations, 2024';

update msp_kernel_rule
   set description = description || ' Transition executed in the kernel on 16/09/2026: the NIHL Regulations, 2003 row is superseded and every audiometry protocol cites the Noise Exposure Regulations, 2024. The engagement date test remains for packs dated before 06/09/2026.'
 where rule_code = 'RULE-NOISE-TRANSITION';

update msp_industry_instrument ii
   set applicability_note = 'Repealed 06/09/2026 by the Noise Exposure Regulations, 2024; cited only in packs dated before the transition'
  from msp_legal_instrument li
 where li.id = ii.instrument_id and li.short_name = 'NIHL Regulations, 2003';

-- Every industry that carried the 2003 Regulations must carry the 2024 Regulations.
insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select ii.industry_id,
       (select id from msp_legal_instrument where short_name = 'Noise Exposure Regulations, 2024' and status = 'verified'),
       'Operative noise instrument from 06/09/2026: noise exposure risk assessment, monitoring, hearing conservation, medical screening and surveillance, audiometry per the Code of Practice'
  from msp_industry_instrument ii
  join msp_legal_instrument old on old.id = ii.instrument_id and old.short_name = 'NIHL Regulations, 2003'
 where not exists (
   select 1 from msp_industry_instrument x
    join msp_legal_instrument n on n.id = x.instrument_id and n.short_name = 'Noise Exposure Regulations, 2024'
   where x.industry_id = ii.industry_id);

-- 2. Physical Agents Regulations, 2024 in; Environmental Regulations, 1987 out ---

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
select
 'Physical Agents Regulations, 2024',
 'Physical Agents Regulations, 2024, GN 5952, Government Gazette 52226, 6 March 2025, made under section 43 of the Occupational Health and Safety Act 85 of 1993. Cover cold stress, heat stress, illumination, indoor air quality, vibration and occupational non-ionising radiation: exposure risk assessment (regulation 6), exposure monitoring (regulation 7), medical screening and medical surveillance (regulation 8), records kept for 40 years (regulation 18).',
 'regulation', 'GN 5952, GG 52226', '2025-03-06',
 'Promulgated 6 March 2025 with GN 5953 (Noise Exposure Regulations, 2024) and GN 5954 (General Safety Regulations amendment). Regulation 21 repeals the Environmental Regulations for Workplaces, 1987 (GN R.2281 of 16 October 1987) 18 months after promulgation, with effect from 06/09/2026. Table 1 values read from the Gazette text: heat stress WBGT index action level 27 and occupational exposure limit 30 degrees Celsius (1 hour); hand arm vibration action value 2,5 and exposure limit 5 metres per square second (8 hours); whole body vibration action value 0,5 and exposure limit 1,15 metres per square second (8 hours); ultraviolet radiation 0,1 microwatt per square centimetre.',
 'GN 5952 in Government Gazette 52226 of 6 March 2025, Gazette text (gov.za mirror of GG 52226 held in the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026, 01-Acts-and-Regulations/PAR-2024-GN5952-GG52226.pdf)',
 'Department of Employment and Labour publication of the 2025 OHS regulation set (labour.gov.za); CNC pack INDEX item 2.1.5 dual URL check across gov.za and labour.gov.za',
 'Currency check 15/09/2026: in force; regulation 21 repeal of the Environmental Regulations for Workplaces, 1987 effective 06/09/2026; no amendment located',
 current_date,
 'Claude Code maintenance agent (IT), documentary verification against the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026, subject to OMP ratification',
 '2027-09-15', 'verified'
where not exists (select 1 from msp_legal_instrument where full_citation ilike '%Physical Agents Regulations, 2024%');

update msp_legal_instrument
   set status = 'superseded',
       amendment_history = coalesce(amendment_history, '') || ' Repealed with effect from 06/09/2026 by regulation 21 of the Physical Agents Regulations, 2024 (GN 5952, GG 52226). Superseded in the kernel on 16/09/2026; retained for packs generated before the transition date. Currency check 15/09/2026 (CNC regulatory instrument pack, LIVE_FETCH_LOG): repeal effective.'
 where short_name = 'Environmental Regulations for Workplaces, 1987'
   and status = 'verified';

-- Heat stress citations move to the 2024 Regulations (regulation 10 and Table 1).
update msp_test_protocol
   set legal_basis_id = (select id from msp_legal_instrument where short_name = 'Physical Agents Regulations, 2024' and status = 'verified')
 where legal_basis_id = (select id from msp_legal_instrument where short_name = 'Environmental Regulations for Workplaces, 1987');

update msp_hazard
   set oel_value = 30,
       oel_unit = 'WBGT index, degrees Celsius',
       oel_basis = 'Occupational exposure limit for heat stress, wet bulb globe temperature index, 1 hour reference period; action level 27 (Physical Agents Regulations, 2024, Table 1)',
       oel_instrument = 'Physical Agents Regulations, 2024, GN 5952, GG 52226, regulation 10 (heat stress) and Table 1; replaces the Environmental Regulations for Workplaces, 1987 from 06/09/2026',
       verification_status = 'verified'
 where code = 'H';

-- Vibration: the 2024 Regulations are the specific instrument (regulation 13). The
-- hazard carries two limits (hand arm and whole body), so the numeric field stays
-- null and exceedance assessment stays with the OMP; the values are recorded.
update msp_test_protocol
   set legal_basis_id = (select id from msp_legal_instrument where short_name = 'Physical Agents Regulations, 2024' and status = 'verified')
 where test_name = 'Vibration and musculoskeletal screen'
   and hazard_id = (select id from msp_hazard where code = 'G');

update msp_hazard
   set oel_basis = 'Physical Agents Regulations, 2024, Table 1: hand arm vibration action value 2,5 and exposure limit 5 metres per square second (8 hours); whole body vibration action value 0,5 and exposure limit 1,15 metres per square second (8 hours). Two limits on one hazard key, so the numeric field stays null and the exceedance assessment is the OMP determination against the applicable limit',
       oel_instrument = 'Physical Agents Regulations, 2024, GN 5952, GG 52226, regulation 13 (vibration) and Table 1; Ergonomics Regulations, 2019 for the musculoskeletal effect'
 where code = 'G';

-- Non-ionising radiation (ultraviolet) protocol without a basis gains one.
update msp_test_protocol
   set legal_basis_id = (select id from msp_legal_instrument where short_name = 'Physical Agents Regulations, 2024' and status = 'verified')
 where legal_basis_id is null
   and hazard_id = (select id from msp_hazard where code = 'L')
   and test_name ilike '%ultraviolet%';

update msp_hazard
   set oel_instrument = oel_instrument || '; occupational non-ionising radiation including ultraviolet per the Physical Agents Regulations, 2024, regulation 14 and Table 1 (ultraviolet 0,1 microwatt per square centimetre)'
 where code = 'L'
   and oel_instrument not ilike '%Physical Agents Regulations, 2024%';

update msp_industry_instrument ii
   set applicability_note = 'Repealed 06/09/2026 by the Physical Agents Regulations, 2024; cited only in packs dated before the transition'
  from msp_legal_instrument li
 where li.id = ii.instrument_id and li.short_name = 'Environmental Regulations for Workplaces, 1987';

-- The 2024 Regulations apply to every industry (thermal environment, illumination,
-- indoor air quality, vibration and non-ionising radiation are not sector specific).
insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id,
       (select id from msp_legal_instrument where short_name = 'Physical Agents Regulations, 2024' and status = 'verified'),
       'Cold stress, heat stress, illumination, indoor air quality, vibration and non-ionising radiation: exposure risk assessment, monitoring and medical surveillance under regulation 8; replaces the Environmental Regulations for Workplaces, 1987 from 06/09/2026'
  from msp_industry i
 where not exists (
   select 1 from msp_industry_instrument x
    join msp_legal_instrument n on n.id = x.instrument_id and n.short_name = 'Physical Agents Regulations, 2024'
   where x.industry_id = i.id);

-- 3. Code of Practice for Audiometry and the SANS standards ---------------------

do $$
declare
  v_id uuid;
begin
  select id into v_id from msp_legal_instrument
   where short_name = 'Code of Practice for Audiometry, 2025' and status = 'pending' limit 1;
  if v_id is not null then
    update msp_legal_instrument
       set full_citation = 'Code of Practice for Audiometry with Explanatory Notes, published with the Noise Exposure Regulations, 2024 (GN 5953, Government Gazette 52226, 6 March 2025) and incorporated under regulation 15 of those Regulations; governs baseline, periodic, diagnostic and exit audiometry, audiometer calibration (electro acoustic, biological and daily checks) and the acoustic test environment',
           gazette_reference = 'GG 52226, published with GN 5953',
           effective_date = '2025-03-06'
     where id = v_id;
    perform msp_verify_instrument(
      v_id,
      'Code of Practice for Audiometry, Gazette text in Government Gazette 52226 following GN 5953 (gov.za mirror in the CNC regulatory instrument pack of 15/09/2026, 01-Acts-and-Regulations/PAR-2024-GN5952-GG52226.pdf from its page 114) and the Department of Employment and Labour bundle NER-2024-CoP-Audiometry-Explanatory-labour.pdf',
      'Department of Employment and Labour publication of the Noise Exposure Regulations bundle with the Code and Explanatory Notes (labour.gov.za); CNC pack INDEX item 2.1.4',
      'Currency check 15/09/2026: in force and incorporated under the Noise Exposure Regulations, 2024, which became the sole operative noise instrument on 06/09/2026',
      'Published 6 March 2025 with the Noise Exposure Regulations, 2024. Governs audiometric method from the transition date 06/09/2026.',
      'Claude Code maintenance agent (IT), documentary verification against the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026, subject to OMP ratification',
      '2027-09-15');
  end if;

  select id into v_id from msp_legal_instrument
   where short_name = 'SANS 10083' and status = 'pending' limit 1;
  if v_id is not null then
    update msp_legal_instrument
       set short_name = 'SANS 10083:2023',
           full_citation = 'SANS 10083:2023 Edition 6.1, The measurement and assessment of occupational noise for hearing conservation purposes (SABS, approved 4 November 2023, replaces edition 6 of 2021), the measurement standard for noise exposure monitoring under the Noise Exposure Regulations, 2024',
           gazette_reference = 'SABS ISBN 978-626-0-42488-6',
           effective_date = '2023-11-04'
     where id = v_id;
    perform msp_verify_instrument(
      v_id,
      'SANS 10083:2023 Edition 6.1, licensed copy held by Care Net Consultants (supplied by the MD 16/09/2026; copyright SABS, not reproduced)',
      'SABS store product metadata read live 15/09/2026 (store.sabs.co.za: edition 6.01, approved 4 November 2023, ISBN 978-626-0-42488-6); CNC pack SANS_CATALOGUE.md section 1.1',
      'Currency check 15/09/2026: edition 6.01 of 2023 is the current edition on the SABS store and replaces edition 6 of 2021',
      'Edition 6.1 approved 4 November 2023 replaces edition 6 of 2021. Referenced by the Noise Exposure Regulations, 2024 for noise measurement.',
      'Claude Code maintenance agent (IT), documentary verification against the licensed copy and the SABS store, subject to OMP ratification',
      '2027-09-15');
  end if;
end $$;

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
select
 'SANS 451:2008',
 'SANS 451:2008 Edition 1, Spirometry: generation of acceptable and repeatable spirograms (SABS), the method standard for lung function testing in the Care Net medical examinations matrix',
 'sans', 'SABS ISBN 978-0-626-21783-9', '2008-01-01',
 'Edition 1 of 2008. No later edition located on the SABS store at the check date.',
 'SANS 451:2008 Edition 1, licensed copy held by Care Net Consultants (supplied by the MD 16/09/2026; copyright SABS, not reproduced)',
 'Care Net Consultants medical examinations matrix (published service definition citing SANS 451 for spirometry); SABS store listing',
 'Currency check 15/09/2026: edition 1 of 2008 current; no replacement edition located',
 current_date,
 'Claude Code maintenance agent (IT), documentary verification against the licensed copy and the SABS store, subject to OMP ratification',
 '2027-09-15', 'verified'
where not exists (select 1 from msp_legal_instrument where full_citation ilike '%SANS 451%');

-- Audiometry code and SANS 10083 travel with the Noise Exposure Regulations; SANS 451 with every industry.
insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select ii.industry_id, c.id, 'Audiometric method, calibration and test environment for every audiometry protocol under the Noise Exposure Regulations, 2024'
  from msp_industry_instrument ii
  join msp_legal_instrument n on n.id = ii.instrument_id and n.short_name = 'Noise Exposure Regulations, 2024'
  join msp_legal_instrument c on c.short_name = 'Code of Practice for Audiometry, 2025' and c.status = 'verified'
 where not exists (select 1 from msp_industry_instrument x where x.industry_id = ii.industry_id and x.instrument_id = c.id);

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select ii.industry_id, s.id, 'Noise measurement and assessment standard for exposure monitoring under the Noise Exposure Regulations, 2024'
  from msp_industry_instrument ii
  join msp_legal_instrument n on n.id = ii.instrument_id and n.short_name = 'Noise Exposure Regulations, 2024'
  join msp_legal_instrument s on s.short_name = 'SANS 10083:2023' and s.status = 'verified'
 where not exists (select 1 from msp_industry_instrument x where x.industry_id = ii.industry_id and x.instrument_id = s.id);

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, s.id, 'Spirometry method standard for every lung function test in the programme'
  from msp_industry i
  join msp_legal_instrument s on s.short_name = 'SANS 451:2008' and s.status = 'verified'
 where not exists (select 1 from msp_industry_instrument x where x.industry_id = i.id and x.instrument_id = s.id);

-- 4. New verified instruments from the pack ---------------------------------------

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
select
 'Circular Instruction 171 (COIDA)',
 'Circular Instruction No. 171 under the Compensation for Occupational Injuries and Diseases Act 130 of 1993: the determination of permanent disablement resulting from hearing loss caused by exposure to excessive noise and trauma (GN 422, Government Gazette 22296, 16 May 2001); the percentage loss of hearing (PLH) method for noise induced hearing loss claims',
 'circular', 'GN 422, GG 22296', '2001-05-16',
 'In force and in use for PLH determination at the check date.',
 'Circular Instruction 171 text (third party PDF mirror held in the CNC regulatory instrument pack of 15/09/2026, 02-COIDA-Compensation/Instruction-171-PLH.pdf)',
 'SAFLII consolidated regulation text of Circular Instruction 171; Compensation Fund practice; CNC pack INDEX item 2.2.4',
 'Currency check 15/09/2026: in force; still applied to noise induced hearing loss claims; no replacement instruction located',
 current_date,
 'Claude Code maintenance agent (IT), documentary verification against the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026, subject to OMP ratification',
 '2027-09-15', 'verified'
where not exists (select 1 from msp_legal_instrument where full_citation ilike '%Circular Instruction No. 171%' or short_name ilike '%Instruction 171%');

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
select
 'POPIA',
 'Protection of Personal Information Act 4 of 2013 (Government Gazette 37067, 26 November 2013): health information is special personal information (section 26); processing by medical practitioners and for employment purposes under sections 27 and 32; the lawful basis for the POPIA notice, consent and retention blocks in every Plan',
 'act', null, '2020-07-01',
 'Main processing provisions commenced 1 July 2020; in force at the check date.',
 'Act text as published (gov.za mirror held in the CNC regulatory instrument pack of 15/09/2026, 01-Acts-and-Regulations/POPIA-Act-4-of-2013.pdf)',
 'Information Regulator publications (inforegulator.org.za); CNC pack INDEX item 2.3.1',
 'Currency check 15/09/2026: in force; no amendment affecting health information processing located',
 current_date,
 'Claude Code maintenance agent (IT), documentary verification against the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026, subject to OMP ratification',
 '2027-09-15', 'verified'
where not exists (select 1 from msp_legal_instrument where full_citation ilike '%Protection of Personal Information Act%');

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
select
 'Health Professions Act',
 'Health Professions Act 56 of 1974 (enacted as the Medical, Dental and Supplementary Health Service Professions Act; Government Gazette of 16 October 1974), as amended: registration, scope and professional conduct of medical practitioners including the Designated Occupational Medical Practitioner, under the Health Professions Council of South Africa',
 'act', null, '1974-10-16',
 'Original 1974 text verified; the Act has been amended repeatedly and the consolidated text is administered by the HPCSA. In force at the check date.',
 'Act text as published (gov.za mirror held in the CNC regulatory instrument pack of 15/09/2026, 01-Acts-and-Regulations/Health-Professions-Act-56-of-1974.pdf)',
 'HPCSA published legislation and ethical rules (hpcsa.co.za); CNC pack INDEX item 2.3.2',
 'Currency check 15/09/2026: in force, as amended',
 current_date,
 'Claude Code maintenance agent (IT), documentary verification against the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026, subject to OMP ratification',
 '2027-09-15', 'verified'
where not exists (select 1 from msp_legal_instrument where full_citation ilike '%Health Professions Act 56 of 1974%');

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
select
 'Nursing Act',
 'Nursing Act 33 of 2005 (Government Gazette 28883, 29 May 2006): registration and practice of nurses, including occupational health nurse practitioners who conduct examinations under the programme, under the South African Nursing Council',
 'act', 'GG 28883', '2006-05-29',
 'In force at the check date.',
 'Act text as published (gov.za mirror held in the CNC regulatory instrument pack of 15/09/2026, 01-Acts-and-Regulations/Nursing-Act-33-of-2005.pdf)',
 'South African Nursing Council published legislation (sanc.co.za); CNC pack INDEX item 2.3.3',
 'Currency check 15/09/2026: in force',
 current_date,
 'Claude Code maintenance agent (IT), documentary verification against the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026, subject to OMP ratification',
 '2027-09-15', 'verified'
where not exists (select 1 from msp_legal_instrument where full_citation ilike '%Nursing Act 33 of 2005%');

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
select
 'Asbestos Abatement Regulations, 2020',
 'Asbestos Abatement Regulations, 2020, GN R.1196, Government Gazette 43893, 10 November 2020, made under the Occupational Health and Safety Act 85 of 1993, as amended by GN R.2092 of 20 May 2022 (Government Gazette 46380): asbestos risk assessment, inventory and management plan, air monitoring, medical surveillance of exposed employees, and 40 year record keeping',
 'regulation', 'GN R.1196, GG 43893', '2020-11-10',
 'Amended by GN R.2092 of 20 May 2022 (amendment text catalogued, not held in the pack). In force at the check date.',
 'GN R.1196 Gazette text (gov.za mirror held in the CNC regulatory instrument pack of 15/09/2026, 01-Acts-and-Regulations/Asbestos-Abatement-Regs-2020-GG43893.pdf)',
 'lawlibrary.org.za consolidated text and the 2022 amendment notice (akn/za/act/gn/2022/r2092); CNC pack INDEX items 2.1.9 and 2.1.10',
 'Currency check 15/09/2026: in force as amended 2022; no later amendment located',
 current_date,
 'Claude Code maintenance agent (IT), documentary verification against the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026, subject to OMP ratification',
 '2027-09-15', 'verified'
where not exists (select 1 from msp_legal_instrument where full_citation ilike '%Asbestos Abatement Regulations%');

-- Maps: COIDA circular travels with the noise instrument; POPIA, the practitioner
-- Acts go to every industry; asbestos to the industries where asbestos work occurs.
insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select ii.industry_id, c.id, 'Percentage loss of hearing determination for noise induced hearing loss compensation claims'
  from msp_industry_instrument ii
  join msp_legal_instrument n on n.id = ii.instrument_id and n.short_name = 'Noise Exposure Regulations, 2024'
  join msp_legal_instrument c on c.short_name = 'Circular Instruction 171 (COIDA)' and c.status = 'verified'
 where not exists (select 1 from msp_industry_instrument x where x.industry_id = ii.industry_id and x.instrument_id = c.id);

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
  from msp_industry i
  join (values
    ('POPIA', 'Lawful processing of employee health information; the POPIA notice, consent and retention blocks in the Plan'),
    ('Health Professions Act', 'Registration and conduct of the Designated Occupational Medical Practitioner who approves the Plan and determines fitness'),
    ('Nursing Act', 'Registration and practice of the occupational health nurse practitioners who conduct examinations')
  ) as m(short_name, note) on true
  join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
 where not exists (select 1 from msp_industry_instrument x where x.industry_id = i.id and x.instrument_id = li.id);

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id,
       'Applies where asbestos containing materials are present, disturbed or removed: risk assessment, inventory, air monitoring and medical surveillance of exposed employees; the battery is set by the OMP per engagement (CR-14.3)'
  from msp_industry i
  join msp_legal_instrument li on li.short_name = 'Asbestos Abatement Regulations, 2020' and li.status = 'verified'
 where i.code in ('CONSTR', 'MANU', 'MINING', 'WASTE', 'UTIL', 'GOV', 'PETRO')
   and not exists (select 1 from msp_industry_instrument x where x.industry_id = i.id and x.instrument_id = li.id);

-- 5. Currency checks appended to pack instruments already verified ----------------

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.1.1 and 2.1.2, gov.za and labour.gov.za texts): in force, as amended.',
       review_due = greatest(coalesce(review_due, current_date), date '2027-09-15')
 where short_name = 'OHS Act' and status = 'verified';

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.1.15): in force.',
       review_due = greatest(coalesce(review_due, current_date), date '2027-09-15')
 where short_name = 'Construction Regulations, 2014' and status = 'verified';

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.1.8, gov.za and lawlibrary.org.za texts): in force.',
       review_due = greatest(coalesce(review_due, current_date), date '2027-09-15')
 where short_name = 'HCA Regulations, 2021' and status = 'verified';

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.1.13, GN R.1887 in GG 46051 of 16 March 2022): in force; records including the risk assessment kept a minimum of 40 years.',
       review_due = greatest(coalesce(review_due, current_date), date '2027-09-15')
 where short_name = 'HBA Regulations, 2022' and status = 'verified';

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.1.11 and 2.1.12): in force. A Draft Lead Regulation was published for comment on 1 March 2024 (GN R.4437, GG 50203) and is not promulgated; the 2001 Regulations remain the operative instrument (standing watch CR-14.2).',
       review_due = greatest(coalesce(review_due, current_date), date '2027-03-15')
 where short_name = 'Lead Regulations, 2001' and status = 'verified';

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.1.14): in force.',
       review_due = greatest(coalesce(review_due, current_date), date '2027-09-15')
 where short_name = 'General Administrative Regulations, 2003' and status = 'verified';

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Amended by GN 5954 in Government Gazette 52226 of 6 March 2025 (notice regarding amendment to the General Safety Regulations, published with the Noise Exposure and Physical Agents Regulations). Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.1.6): in force as amended.',
       review_due = greatest(coalesce(review_due, current_date), date '2027-09-15')
 where short_name = 'General Safety Regulations, 1986' and status = 'verified';

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.2.1 to 2.2.3): Amendment Act 10 of 2022 (GG 48431, 17 April 2023) commenced by Proclamation 306 of 2026 (GG 53990, 23 January 2026) on 23 January 2026 for all sections except section 1(g) and part of 1(h), on 1 February 2026 for sections 3 to 6, and on 1 April 2026 for sections 19(a) and (b), 20(c), 28(c), 36(1), 50(3), 52 and 54(1) and (2); the excepted definitions remain uncommenced.'
 where short_name = 'COIDA' and status = 'verified';

update msp_legal_instrument
   set amendment_history = coalesce(amendment_history, '') || ' Currency check 15/09/2026 (CNC regulatory instrument pack, INDEX 2.3.4): section 7 in force, unchanged.',
       review_due = greatest(coalesce(review_due, current_date), date '2027-09-15')
 where short_name = 'EEA section 7' and status = 'verified';

-- 6. Register ----------------------------------------------------------------------

update msp_confirmation_item
   set description = description || ' Update 16/09/2026: Care Net now holds licensed copies of SANS 10083:2023 Edition 6.1 (noise measurement) and SANS 451:2008 Edition 1 (spirometry), both verified into the kernel. SANS 10182:2006 (audiometric acoustic environment) and SANS 10154-1 and 10154-2:2012 (audiometer verification) remain catalogue entries only, editions confirmed on the SABS store 15/09/2026, licensed copies not yet held.'
 where item_code = 'CR-12.3';

update msp_confirmation_item
   set description = description || ' Update 16/09/2026: the General Safety Regulations, 1986 (with the 2025 amendment notice), the General Administrative Regulations, 2003 and the Driven Machinery Regulations are verified; the General Machinery Regulations remain pending and uncitable, with the draft General Machinery Regulation, 2025 replacement on the standing watch.'
 where item_code = 'CR-13.9';

insert into msp_confirmation_item (item_code, kind, description, status)
select v.code, v.kind, v.descr, 'open'
  from (values
    ('CR-14.1', 'confirm',
     'Kernel release 1.1.0 (16/09/2026): the noise transition executed (NIHL Regulations, 2003 superseded, audiometry cites the Noise Exposure Regulations, 2024), the Physical Agents Regulations, 2024 verified with Table 1 values and mapped to every industry, the Environmental Regulations for Workplaces, 1987 superseded, the Code of Practice for Audiometry, SANS 10083:2023 and SANS 451:2008 verified, Circular Instruction 171, POPIA, the Health Professions Act, the Nursing Act and the Asbestos Abatement Regulations, 2020 verified. Documentary verification by the IT maintenance agent against the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026. OMP ratification of release 1.1.0 required (Dr C. P. Green-Thompson, HPCSA MP 0195952).'),
    ('CR-14.2', 'confirm',
     'Standing watch: the Draft Lead Regulation published for comment on 1 March 2024 (GN R.4437, GG 50203) is not promulgated; the Lead Regulations, 2001 remain operative. When promulgated, verify the new instrument, move the C-PB hazard and the two lead protocols across, and supersede the 2001 row. Review due 15/03/2027 on the 2001 row.'),
    ('CR-14.3', 'confirm',
     'Asbestos Abatement Regulations, 2020 are verified and mapped to Construction, Manufacturing, Mining, Waste, Utilities, Government and Petrochemical, but no asbestos specific test protocol exists in the kernel: asbestos exposed categories currently receive the hazard C chemical battery. The OMP to confirm the asbestos medical surveillance battery (respiratory questionnaire, spirometry, chest radiograph per the OMP protocol) and its interval before a protocol row is added.'),
    ('CR-14.4', 'confirm',
     'Physical Agents Regulations, 2024: hazard H (heat stress) now carries the verified WBGT limit of 30 and action level 27 from Table 1, so measured heat exposures are assessed by the engine. Hazard G (vibration) carries two limits (hand arm 5, whole body 1,15 metres per square second, action values 2,5 and 0,5) on one hazard key, so its numeric field stays null and exceedance stays with the OMP. Confirm whether hazard G should split into G-HAV and G-WBV so the engine can assess vibration exceedances.'),
    ('CR-14.5', 'confirm',
     'Compensation Fund guidance in the pack (CompEasy employer and health care provider claim registration manuals, COIDA Service Book version 23) is reference material for the claims process and is not entered as kernel instruments; the claims workflow narrative in packs may cite COIDA and Circular Instruction 171 only. Confirm whether the assistant should carry the CompEasy process as a client explanation.')
  ) as v(code, kind, descr)
 where not exists (select 1 from msp_confirmation_item c where c.item_code = v.code);

-- 7. Release 1.1.0 and the learning update record ----------------------------------

insert into msp_kernel_version (semver, change_summary, kernel_counts, created_by)
values ('1.1.0',
        'Legislation currency release 16/09/2026 from the CNC OH Value Chain Regulatory Instrument Pack of 15/09/2026: noise transition executed (NIHL 2003 superseded, NER 2024 cited by every audiometry protocol); Physical Agents Regulations, 2024 verified with Table 1 values and mapped to all industries; Environmental Regulations for Workplaces, 1987 superseded; Code of Practice for Audiometry, SANS 10083:2023 and SANS 451:2008 verified; Circular Instruction 171, POPIA, Health Professions Act, Nursing Act and Asbestos Abatement Regulations, 2020 verified; currency checks appended to ten instruments; register items CR-14.1 to CR-14.5 opened. Subject to OMP ratification.',
        msp_kernel_counts(),
        'Claude Code maintenance agent (IT), migration 042');

insert into msp_kernel_agent_run (kind, report, outcome)
values ('learning_update',
        jsonb_build_object(
          'run_on', current_date,
          'source', 'CNC OH Value Chain Regulatory Instrument Pack, 15/09/2026',
          'superseded', jsonb_build_array('NIHL Regulations, 2003', 'Environmental Regulations for Workplaces, 1987'),
          'verified_new', jsonb_build_array('Physical Agents Regulations, 2024', 'Code of Practice for Audiometry, 2025', 'SANS 10083:2023', 'SANS 451:2008', 'Circular Instruction 171 (COIDA)', 'POPIA', 'Health Professions Act', 'Nursing Act', 'Asbestos Abatement Regulations, 2020'),
          'currency_checked', jsonb_build_array('OHS Act', 'Construction Regulations, 2014', 'HCA Regulations, 2021', 'HBA Regulations, 2022', 'Lead Regulations, 2001', 'General Administrative Regulations, 2003', 'General Safety Regulations, 1986', 'COIDA', 'EEA section 7', 'Noise Exposure Regulations, 2024'),
          'register_opened', jsonb_build_array('CR-14.1', 'CR-14.2', 'CR-14.3', 'CR-14.4', 'CR-14.5'),
          'release', '1.1.0',
          'counts', msp_kernel_counts()),
        'findings');

insert into msp_audit (actor, event_type, event_detail)
values ('Claude Code maintenance agent (IT), migration 042', 'kernel_release',
        jsonb_build_object('semver', '1.1.0', 'summary', 'Legislation currency release 16/09/2026; OMP ratification pending', 'counts', msp_kernel_counts()));

-- 8. Gates -----------------------------------------------------------------------------

do $$
declare
  v_bad int;
  v_missing int;
  v_dash int;
begin
  select count(*) into v_bad
    from msp_test_protocol p
    join msp_legal_instrument li on li.id = p.legal_basis_id
   where li.status <> 'verified';
  if v_bad > 0 then
    raise exception 'gate: % protocols still cite a non verified instrument', v_bad;
  end if;

  select count(*) into v_missing
    from msp_industry i
   where not exists (
     select 1 from msp_industry_instrument ii
      join msp_legal_instrument li on li.id = ii.instrument_id
     where ii.industry_id = i.id and li.short_name = 'Physical Agents Regulations, 2024');
  if v_missing > 0 then
    raise exception 'gate: % industries without the Physical Agents Regulations, 2024 mapping', v_missing;
  end if;

  select count(*) into v_missing
    from msp_industry_instrument ii
    join msp_legal_instrument old on old.id = ii.instrument_id and old.short_name = 'NIHL Regulations, 2003'
   where not exists (
     select 1 from msp_industry_instrument x
      join msp_legal_instrument n on n.id = x.instrument_id and n.short_name = 'Noise Exposure Regulations, 2024'
     where x.industry_id = ii.industry_id);
  if v_missing > 0 then
    raise exception 'gate: % industries carry the 2003 noise regulations without the 2024 successor', v_missing;
  end if;

  select count(*) into v_dash
    from msp_legal_instrument
   where amendment_history ~ '—|–' or full_citation ~ '—|–' or source_one ~ '—|–' or source_two ~ '—|–' or source_three ~ '—|–';
  if v_dash > 0 then
    raise exception 'gate: dash punctuation found in % instrument rows', v_dash;
  end if;

  raise notice 'migration 042 applied: release 1.1.0, counts %', msp_kernel_counts();
end $$;
