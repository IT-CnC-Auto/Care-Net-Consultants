-- Care Net Cognitive Kernel | full rebuild script | generated 14/08/2026
-- Concatenation of every migration in order. Replaying this into an empty
-- Supabase project rebuilds the entire kernel, workflows, policies, and seed
-- content. Canonical source: supabase/migrations/ in this repository.


------------------------------------------------------------------------------
-- 001_msp_kernel_schema.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | KRN-SCH-01 v1.0.0 | Cognitive Kernel schema
-- Phase 1 migration 001. Additive only: every object is msp_ prefixed and
-- coexists with the host project schema. Applied to project ahp-production
-- per confirmation register item CR-13.1.

create table msp_industry (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  sic_reference text,
  regulatory_regime text not null check (regulatory_regime in ('OHSA','MHSA','DUAL')),
  created_at timestamptz default now()
);
comment on table msp_industry is 'Cognitive Kernel industry taxonomy. The taxonomy is data, not code: extending it is an insert, never a deploy.';

create table msp_subindustry (
  id uuid primary key default gen_random_uuid(),
  industry_id uuid not null references msp_industry(id),
  code text unique not null,
  name text not null,
  selectable boolean not null default false,
  notes text
);
comment on column msp_subindustry.selectable is 'True only when the subindustry role, hazard, and protocol map has passed kernel verification. The DocuSeal picker lists selectable rows only (Phase 6 gate).';

create table msp_job_role (
  id uuid primary key default gen_random_uuid(),
  subindustry_id uuid not null references msp_subindustry(id),
  title text not null,
  duties_summary text not null,
  inherent_physical_demands text,
  inherent_sensory_cognitive_demands text,
  statutory_competency_requirement text
);

create table msp_hazard (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  category text not null check (category in ('physical','chemical','biological','ergonomic','psychosocial')),
  oel_value numeric,
  oel_unit text,
  oel_basis text,
  oel_instrument text,
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified','verified','excluded'))
);
comment on table msp_hazard is 'Canonical hazard key A to O, extensible. An OEL is stored only with its citing instrument; unverified values never print in a released pack.';

create table msp_job_hazard (
  job_role_id uuid references msp_job_role(id),
  hazard_id uuid references msp_hazard(id),
  typical_exposure_rating text not null,
  rationale text not null,
  primary key (job_role_id, hazard_id)
);

create table msp_legal_instrument (
  id uuid primary key default gen_random_uuid(),
  short_name text not null,
  full_citation text not null,
  instrument_type text not null
    check (instrument_type in ('act','regulation','code','hpcsa','sans','guideline','circular')),
  gazette_reference text,
  effective_date date,
  amendment_history text,
  source_one text not null,
  source_two text not null,
  source_three text not null,
  verified_on date,
  verified_by text,
  review_due date,
  status text not null default 'pending'
    check (status in ('pending','verified','excluded','superseded')),
  constraint msp_instrument_verified_complete
    check (status <> 'verified'
           or (verified_on is not null and verified_by is not null and review_due is not null))
);
comment on table msp_legal_instrument is 'Triple verification protocol: source_one is the primary instrument (gate a), source_two an authoritative corroboration (gate b), source_three the currency check record (gate c). A source that cannot pass all three gates is excluded, not padded.';

create table msp_test_protocol (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references msp_hazard(id),
  test_name text not null,
  test_type text not null check (test_type in ('clinical','biological_monitoring','biological_effect')),
  baseline_required boolean not null default true,
  periodic_interval_months int not null check (periodic_interval_months >= 1),
  exit_required boolean not null default true,
  trigger_conditions text,
  biological_reference text,
  legal_basis_id uuid references msp_legal_instrument(id),
  constraint msp_interval_floor_citation
    check (periodic_interval_months <= 12 or legal_basis_id is not null)
);
comment on constraint msp_interval_floor_citation on msp_test_protocol is 'Twelve months is the periodic floor. A longer interval exists only with an instrument citation, and exceedances tighten, never loosen.';

create table msp_industry_instrument (
  industry_id uuid references msp_industry(id),
  instrument_id uuid references msp_legal_instrument(id),
  applicability_note text,
  primary key (industry_id, instrument_id)
);

create table msp_kernel_rule (
  id uuid primary key default gen_random_uuid(),
  rule_code text unique not null,
  description text not null,
  condition_expr jsonb not null,
  effect jsonb not null,
  instrument_id uuid references msp_legal_instrument(id),
  status text not null default 'pending' check (status in ('pending','verified','excluded'))
);
comment on table msp_kernel_rule is 'Routing and trigger rules encoded as data, not prose: ODMWA versus COIDA routing, night work trigger, PrDP trigger, noise instrument transition.';

create table msp_kernel_exclusion (
  id uuid primary key default gen_random_uuid(),
  candidate_citation text not null,
  failed_gate text not null check (failed_gate in ('a','b','c')),
  reason text not null,
  excluded_on date not null default current_date,
  excluded_by text not null
);
comment on table msp_kernel_exclusion is 'The exclusion register. An honest gap beats a confident guess.';

create table msp_confirmation_item (
  id uuid primary key default gen_random_uuid(),
  item_code text unique not null,
  kind text not null check (kind in ('confirm','assumption')),
  description text not null,
  status text not null default 'open' check (status in ('open','resolved','excluded')),
  resolution text,
  resolved_by text,
  resolved_on date
);
comment on table msp_confirmation_item is 'The consolidated confirmation register. No item is resolved by guesswork, and no released pack carries an open item.';

create index msp_subindustry_industry_idx on msp_subindustry(industry_id);
create index msp_job_role_subindustry_idx on msp_job_role(subindustry_id);
create index msp_test_protocol_hazard_idx on msp_test_protocol(hazard_id);
create index msp_job_hazard_hazard_idx on msp_job_hazard(hazard_id);


------------------------------------------------------------------------------
-- 002_msp_kernel_rls.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | KRN-RLS-01 v1.0.0 | Row Level Security for the Cognitive Kernel
-- Phase 1 migration 002. RLS on every table, deny by default. Roles are carried
-- as an msp_roles array in the JWT app_metadata claim. The service role key
-- (server side only) bypasses RLS for the build and runtime service paths.
-- Anonymous access is denied everywhere: no policy exists for anon.

create or replace function msp_has_role(required text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' -> 'msp_roles') ? required,
    false
  );
$$;
comment on function msp_has_role is 'True when the requesting JWT carries the named role in app_metadata.msp_roles. Roles: forge_agent, forge_verifier, forge_omp, forge_admin.';

create or replace function msp_any_forge_role()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select public.msp_has_role('forge_agent')
      or public.msp_has_role('forge_verifier')
      or public.msp_has_role('forge_omp')
      or public.msp_has_role('forge_admin');
$$;

-- Enable RLS on every kernel table
alter table msp_industry            enable row level security;
alter table msp_subindustry         enable row level security;
alter table msp_job_role            enable row level security;
alter table msp_hazard              enable row level security;
alter table msp_job_hazard          enable row level security;
alter table msp_legal_instrument    enable row level security;
alter table msp_test_protocol       enable row level security;
alter table msp_industry_instrument enable row level security;
alter table msp_kernel_rule         enable row level security;
alter table msp_kernel_exclusion    enable row level security;
alter table msp_confirmation_item   enable row level security;

-- Kernel content: readable by every forge role, writable by the verifier only.
-- There is no DELETE policy on any kernel table: kernel rows are excluded or
-- superseded through status, never deleted, so the citation trail survives.

create policy msp_industry_read on msp_industry
  for select to authenticated using (msp_any_forge_role());
create policy msp_industry_write on msp_industry
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_industry_update on msp_industry
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_subindustry_read on msp_subindustry
  for select to authenticated using (msp_any_forge_role());
create policy msp_subindustry_write on msp_subindustry
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_subindustry_update on msp_subindustry
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_job_role_read on msp_job_role
  for select to authenticated using (msp_any_forge_role());
create policy msp_job_role_write on msp_job_role
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_job_role_update on msp_job_role
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_hazard_read on msp_hazard
  for select to authenticated using (msp_any_forge_role());
create policy msp_hazard_write on msp_hazard
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_hazard_update on msp_hazard
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_job_hazard_read on msp_job_hazard
  for select to authenticated using (msp_any_forge_role());
create policy msp_job_hazard_write on msp_job_hazard
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_job_hazard_update on msp_job_hazard
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_legal_instrument_read on msp_legal_instrument
  for select to authenticated using (msp_any_forge_role());
create policy msp_legal_instrument_write on msp_legal_instrument
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_legal_instrument_update on msp_legal_instrument
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_test_protocol_read on msp_test_protocol
  for select to authenticated using (msp_any_forge_role());
create policy msp_test_protocol_write on msp_test_protocol
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_test_protocol_update on msp_test_protocol
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_industry_instrument_read on msp_industry_instrument
  for select to authenticated using (msp_any_forge_role());
create policy msp_industry_instrument_write on msp_industry_instrument
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_industry_instrument_update on msp_industry_instrument
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_kernel_rule_read on msp_kernel_rule
  for select to authenticated using (msp_any_forge_role());
create policy msp_kernel_rule_write on msp_kernel_rule
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_kernel_rule_update on msp_kernel_rule
  for update to authenticated using (msp_has_role('forge_verifier'));

-- The exclusion register is append only for the verifier: no update policy.
create policy msp_kernel_exclusion_read on msp_kernel_exclusion
  for select to authenticated using (msp_any_forge_role());
create policy msp_kernel_exclusion_write on msp_kernel_exclusion
  for insert to authenticated with check (msp_has_role('forge_verifier'));

-- The confirmation register: read by every forge role, maintained by admin and verifier.
create policy msp_confirmation_item_read on msp_confirmation_item
  for select to authenticated using (msp_any_forge_role());
create policy msp_confirmation_item_write on msp_confirmation_item
  for insert to authenticated
  with check (msp_has_role('forge_admin') or msp_has_role('forge_verifier'));
create policy msp_confirmation_item_update on msp_confirmation_item
  for update to authenticated
  using (msp_has_role('forge_admin') or msp_has_role('forge_verifier'));


------------------------------------------------------------------------------
-- 003_msp_kernel_verification.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | KRN-VER-01 v1.0.1 | Triple verification workflow
-- v1.0.1: msp_verification_due view runs as security invoker so kernel RLS applies.
-- Phase 1 migration 003. The workflow is enforced in the database:
-- an instrument becomes verified only through msp_verify_instrument, which
-- asserts all three gates; a failed candidate is excluded through
-- msp_exclude_instrument, which records the register entry and the reason.

-- Gate discipline:
--   gate a: primary instrument located (the Act, Regulation, Gazette notice,
--           HPCSA booklet, SANS standard, or peer reviewed guideline itself)
--   gate b: second authoritative corroboration
--   gate c: currency check confirming not amended, repealed, or superseded,
--           with the amendment history recorded

create or replace function msp_ingest_instrument(
  p_short_name text,
  p_full_citation text,
  p_instrument_type text,
  p_gazette_reference text default null,
  p_effective_date date default null
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into msp_legal_instrument
    (short_name, full_citation, instrument_type, gazette_reference, effective_date,
     source_one, source_two, source_three, status)
  values
    (p_short_name, p_full_citation, p_instrument_type, p_gazette_reference, p_effective_date,
     '[CONFIRM] pending gate a', '[CONFIRM] pending gate b', '[CONFIRM] pending gate c', 'pending')
  returning id into v_id;
  return v_id;
end;
$$;
comment on function msp_ingest_instrument is 'Stage an instrument as pending. It carries CONFIRM markers until verification and can never be cited by the agent while pending.';

create or replace function msp_verify_instrument(
  p_id uuid,
  p_source_one text,
  p_source_two text,
  p_source_three text,
  p_amendment_history text,
  p_verified_by text,
  p_review_due date
) returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if coalesce(btrim(p_source_one), '') = '' or p_source_one like '[CONFIRM]%' then
    raise exception 'Gate a not satisfied: primary instrument source is required';
  end if;
  if coalesce(btrim(p_source_two), '') = '' or p_source_two like '[CONFIRM]%' then
    raise exception 'Gate b not satisfied: authoritative corroboration is required';
  end if;
  if coalesce(btrim(p_source_three), '') = '' or p_source_three like '[CONFIRM]%' then
    raise exception 'Gate c not satisfied: currency check record is required';
  end if;
  if p_review_due is null or p_review_due <= current_date then
    raise exception 'A verified instrument requires a future review due date';
  end if;

  update msp_legal_instrument
     set source_one = p_source_one,
         source_two = p_source_two,
         source_three = p_source_three,
         amendment_history = p_amendment_history,
         verified_on = current_date,
         verified_by = p_verified_by,
         review_due = p_review_due,
         status = 'verified'
   where id = p_id
     and status in ('pending','verified');

  if not found then
    raise exception 'Instrument % is not in a verifiable state', p_id;
  end if;
end;
$$;

create or replace function msp_exclude_instrument(
  p_id uuid,
  p_failed_gate text,
  p_reason text,
  p_excluded_by text
) returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_citation text;
begin
  select full_citation into v_citation from msp_legal_instrument where id = p_id;
  if v_citation is null then
    raise exception 'Instrument % not found', p_id;
  end if;

  update msp_legal_instrument set status = 'excluded' where id = p_id;

  insert into msp_kernel_exclusion (candidate_citation, failed_gate, reason, excluded_by)
  values (v_citation, p_failed_gate, p_reason, p_excluded_by);
end;
$$;
comment on function msp_exclude_instrument is 'A source that cannot pass all three gates is excluded, not padded, and logged in the exclusion register with the reason.';

-- Currency watchdog view: instruments whose review date has arrived, or which
-- carry a recorded supersession horizon, surface here for the verifier queue.
create or replace view msp_verification_due
with (security_invoker = on) as
select id, short_name, full_citation, status, verified_on, review_due,
       amendment_history
  from msp_legal_instrument
 where status = 'verified'
   and review_due <= current_date + interval '60 days';
comment on view msp_verification_due is 'Verified instruments within sixty days of their review due date. The noise regulation transition of 06/09/2026 is the founding example.';


------------------------------------------------------------------------------
-- 004_msp_seed_construction.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | KRN-SEED-01 v1.0.0 | Construction pilot industry seed
-- Phase 1 migration 004. Documentary verification performed 12/08/2026 by the
-- build agent against primary web sources, recorded per the triple gate
-- protocol and subject to OMP ratification. Values that could not be verified
-- remain unverified or pending and are never citable by the Generation Agent.

-- 1. Verified legal instruments -------------------------------------------------

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('OHS Act',
 'Occupational Health and Safety Act 85 of 1993',
 'act', null, '1994-01-01',
 'Amended over time, including by the Occupational Health and Safety Amendment Act 181 of 1993. In force August 2026.',
 'Consolidated Act text, SAFLII and lawlibrary.org.za consolidations of Act 85 of 1993',
 'Department of Employment and Labour published Act and regulations, labour.gov.za Document Centre',
 'Currency check 12/08/2026: in force, administered by the Department of Employment and Labour; no repeal or supersession',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('Construction Regulations, 2014',
 'Construction Regulations, 2014, GN R.84, Government Gazette 37305, 7 February 2014, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.84, GG 37305', '2014-02-07',
 'In force August 2026. Annexure 3 prescribes the Medical Certificate of Fitness for construction work, valid for one year from date of issue.',
 'GN R.84 Government Gazette 37305 regulation text, acts.co.za and gazette source',
 'Department of Employment and Labour Construction Regulations guidance and Occupational Health Southern Africa analysis of the Annexure 3 certificate',
 'Currency check 12/08/2026: in force, no amendment affecting medical surveillance provisions located',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('NIHL Regulations, 2003',
 'Noise-Induced Hearing Loss Regulations, 2003, GN R.307 of 7 March 2003, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.307, 7 March 2003', '2003-03-07',
 'REPEAL PENDING: regulation 18 of the Noise Exposure Regulations, 2024 repeals these Regulations 18 months after promulgation of 6 March 2025, that is with effect from 6 September 2026. In force until that date. Noise rating limit 85 dB(A) 8 hour rating level. Audiometric testing required for exposed employees.',
 'GN R.307 gazette text, lawlibrary.org.za akn/za/act/gn/2003/r307',
 'Department of Employment and Labour published regulation and Code of Practice for Audiometry, labour.gov.za; SAFLII consolidated regulation',
 'Currency check 12/08/2026: still in force; repeal effective 06/09/2026 per Noise Exposure Regulations, 2024 regulation 18; review scheduled at that horizon',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2026-09-06', 'verified'),

('Noise Exposure Regulations, 2024',
 'Noise Exposure Regulations, 2024, GN 5953, Government Gazette 52226, 6 March 2025, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN 5953, GG 52226', '2025-03-06',
 'Promulgated 6 March 2025 with Notices 5952 and 5954 (Physical Agents Regulations, 2024 and amendment of the General Safety Regulations). Repeals the Noise-Induced Hearing Loss Regulations, 2003 with effect from 6 September 2026. Accompanied by a new Code of Practice for Audiometry. Operative noise instrument from 06/09/2026.',
 'GN 5953 Government Gazette 52226 regulation text, lawlibrary.org.za akn/za/act/gn/2025/5953',
 'ENSafrica and Occupational Health Southern Africa journal analyses of the Noise Exposure Regulations, 2024 promulgation and transition',
 'Currency check 12/08/2026: promulgated and within the 18 month transition window; becomes sole operative noise instrument 06/09/2026',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-03-06', 'verified'),

('HCA Regulations, 2021',
 'Regulations for Hazardous Chemical Agents, 2021, GN R.280, Government Gazette 44348 (Regulation Gazette 11263), 29 March 2021, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.280, GG 44348, RG 11263', '2021-03-29',
 'Replaced the Hazardous Chemical Substances Regulations, 1995. Annexure tables list occupational exposure limits including respirable crystalline silica at 0.1 mg per cubic metre, 8 hour TWA. Medical surveillance duties for exposed employees.',
 'GN R.280 gazette text, gov.za gazette 44348 and lawlibrary.org.za akn/za/act/gn/2021/r280',
 'Department of Employment and Labour published regulation text, labour.gov.za; NIOH regulation launch material',
 'Currency check 12/08/2026: in force; silica OEL 0.1 mg per cubic metre confirmed across sources',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('Ergonomics Regulations, 2019',
 'Ergonomics Regulations, 2019, GN R.1589, Government Gazette 42894, 6 December 2019, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.1589, GG 42894', '2019-12-06',
 'In force August 2026. Requires an ergonomics programme including risk assessment, hierarchy of controls, training, and medical surveillance overseen by an occupational medicine practitioner, with baseline, periodic, and finding driven examinations.',
 'GN R.1589 gazette text, lawlibrary.org.za akn/za/act/gn/2019/r1589 and gov.za notice of 6 December 2019',
 'Occupational Health Southern Africa journal review of the Ergonomics Regulations, 2019; ENSafrica published regulation text',
 'Currency check 12/08/2026: in force, no amendment located',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('COIDA',
 'Compensation for Occupational Injuries and Diseases Act 130 of 1993, as amended by the Compensation for Occupational Injuries and Diseases Amendment Act 10 of 2022',
 'act', null, '1994-03-01',
 'Amendment Act 10 of 2022 brought into operation in phases by Proclamation 306 of 2026: 23 January 2026, 1 February 2026, and 1 April 2026. Post traumatic stress disorder formally recognised as an occupational disease. Employer conveyance and work related training injuries brought within scope. Three year prescription period for claims.',
 'Consolidated Act text, SAFLII; Amendment Act 10 of 2022, gov.za',
 'Bowmans, Cliffe Dekker Hofmeyr, and ENSafrica commencement analyses, January to March 2026',
 'Currency check 12/08/2026: amendments in force per phased 2026 commencement; Circular Instruction numbers for scheduled diseases remain open in the confirmation register (CR-12.2)',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-02-01', 'verified'),

('EEA section 7',
 'Employment Equity Act 55 of 1998, section 7 (medical testing)',
 'act', null, '1999-08-09',
 'Section 7(1): medical testing of an employee is prohibited unless legislation permits or requires it, or it is justifiable in the light of medical facts, employment conditions, social policy, the fair distribution of employee benefits, or the inherent requirements of a job. Section 7(2): HIV status testing only where the Labour Court determines it justifiable under section 50(4). Section unchanged by the Employment Equity Amendment Act 4 of 2022.',
 'Consolidated Act text, SAFLII eea1998240',
 'Department of Employment and Labour EEA summary; University and practitioner analyses of section 7 medical testing',
 'Currency check 12/08/2026: in force; 2022 amendment did not alter section 7',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('BCEA night work Code',
 'Basic Conditions of Employment Act 75 of 1997, section 17(3), read with the Code of Good Practice on the Arrangement of Working Time',
 'code', null, '1998-12-01',
 'Section 17(3)(b): an employee performing regular night work is entitled to a medical examination at commencement of regular night work and at regular intervals thereafter, at the employer''s expense. The Code guides frequency by health status, nature of work, and working hours.',
 'Code of Good Practice on the Arrangement of Working Time, labour.gov.za published text; SAFLII consolidated regulation',
 'Worklaw and practitioner analyses of BCEA section 17 night work medical requirements',
 'Currency check 12/08/2026: in force, no replacement code located',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('NRTA PrDP medical',
 'National Road Traffic Act 93 of 1996, read with the National Road Traffic Regulations, Professional Driving Permit medical fitness provisions',
 'act', null, '2000-08-01',
 'Professional Driving Permit applications require a medical certificate on the prescribed form, not older than two months at the time of application, assessing vision, hearing, cardiovascular, neurological, and general fitness. The precise regulation number for the PrDP medical provision is held open in the confirmation register (CR-13.8).',
 'Consolidated Act text, SAFLII nrta1996189',
 'RTMC and NaTIS prescribed medical certificate guidance; practitioner PrDP requirement summaries',
 'Currency check 12/08/2026: in force; PrDP medical requirement current',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('HPCSA Booklet 1',
 'HPCSA General Ethical Guidelines for the Health Care Professions, Booklet 1, December 2021 revision',
 'hpcsa', null, '2021-12-01',
 'Current HPCSA ethical baseline for all registered practitioners. December 2021 revision current at check date.',
 'HPCSA published Booklet 1, hpcsa.co.za professional practice guidelines',
 'HPCSA guideline update notices and professional body mirrors of the December 2021 revision set',
 'Currency check 12/08/2026: December 2021 revision remains the published version',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('HPCSA Booklet 10',
 'HPCSA General Ethical Guidelines for Good Practice in Telehealth, Booklet 10, revised December 2021',
 'hpcsa', null, '2021-12-01',
 'Telehealth guidance revised December 2021. Telehealth is not equivalent to face to face care and must not be introduced solely to cut costs or as a perverse incentive.',
 'HPCSA published Booklet 10 Telehealth December 2021, hpcsa.co.za',
 'Peer reviewed telehealth practice guidance for South African practitioners; professional body mirrors',
 'Currency check 12/08/2026: December 2021 revision remains the published version',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified'),

('HPCSA Booklet 11',
 'HPCSA Guidelines on Over Servicing, Perverse Incentives and Related Matters, Booklet 11',
 'hpcsa', null, '2021-12-01',
 'Prohibits perverse incentives including charging or benefit arrangements around referrals. Kernel rule RULE-HPCSA-PAYER encodes the house consequence: the employer is the payer and receiving specialists are never charged for referrals.',
 'HPCSA published Booklet 11, hpcsa.co.za professional practice guidelines',
 'Professional indemnity and practitioner analyses of the HPCSA perverse incentive guidance',
 'Currency check 12/08/2026: current published version',
 '2026-08-12',
 'Claude Code build agent, documentary verification, subject to OMP ratification',
 '2027-08-12', 'verified');

-- Staged, not verified: located but not yet taken through all three gates.
select msp_ingest_instrument('General Safety Regulations', 'General Safety Regulations made under the Occupational Health and Safety Act 85 of 1993, as amended by GN 5954 of 6 March 2025', 'regulation', null, null);
select msp_ingest_instrument('General Administrative Regulations', 'General Administrative Regulations made under the Occupational Health and Safety Act 85 of 1993', 'regulation', null, null);
select msp_ingest_instrument('General Machinery Regulations', 'General Machinery Regulations made under the Occupational Health and Safety Act 85 of 1993', 'regulation', null, null);
select msp_ingest_instrument('Driven Machinery Regulations', 'Driven Machinery Regulations made under the Occupational Health and Safety Act 85 of 1993', 'regulation', null, null);
select msp_ingest_instrument('Code of Practice for Audiometry, 2025', 'Code of Practice for Audiometry accompanying the Noise Exposure Regulations, 2024', 'code', null, null);
select msp_ingest_instrument('SANS 10083', 'SANS 10083, measurement and assessment of occupational noise for hearing conservation purposes, edition to be confirmed (CR-12.3)', 'sans', null, null);

-- 2. Industry and subindustries -------------------------------------------------

insert into msp_industry (code, name, sic_reference, regulatory_regime)
values ('CONSTR', 'Construction', 'SIC major division 5, Construction', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, s.selectable, s.notes
from msp_industry i,
     (values
       ('CONSTR-BUILD',  'Building construction',       false, 'Role and hazard map to be enabled in a Phase 6 batch; shares the civils role family'),
       ('CONSTR-CIVILS', 'Civil engineering works',     true,  'Pilot subindustry, verified against the canonical example plan CNC-RPT-2026-0812-001'),
       ('CONSTR-ROADS',  'Roadworks',                   false, 'Phase 6 batch'),
       ('CONSTR-DEMO',   'Demolition',                  false, 'Phase 6 batch'),
       ('CONSTR-ELEC',   'Electrical construction',     false, 'Phase 6 batch')
     ) as s(code, name, selectable, notes)
where i.code = 'CONSTR';

-- 3. Canonical hazard key A to O ------------------------------------------------

insert into msp_hazard (code, name, category, oel_value, oel_unit, oel_basis, oel_instrument, verification_status)
values
('A', 'Noise (plant, tools, machinery)', 'physical', 85, 'dB(A)',
 '8 hour rating level, the noise rating limit',
 'Noise-Induced Hearing Loss Regulations, 2003, GN R.307, in force to 05/09/2026; successor value under the Noise Exposure Regulations, 2024 held in CR-13.10 pending confirmation',
 'verified'),
('B', 'Dust, respirable crystalline silica', 'chemical', 0.1, 'mg/m3',
 '8 hour time weighted average',
 'Regulations for Hazardous Chemical Agents, 2021, GN R.280, Annexure exposure limit tables',
 'verified'),
('C', 'Hazardous chemicals (agent specific)', 'chemical', null, null,
 'Agent specific limits per the HCA Regulations, 2021 Annexure tables; resolved per named agent at engagement time',
 'Regulations for Hazardous Chemical Agents, 2021, GN R.280',
 'unverified'),
('D', 'Biological agents', 'biological', null, null, null,
 'Hazardous Biological Agents Regulations, staged for a later verification batch',
 'unverified'),
('E', 'Working at height (above 1.5m)', 'physical', null, null, null,
 'Construction Regulations, 2014, GN R.84, working at height and Annexure 3 fitness certification',
 'unverified'),
('F', 'Confined spaces', 'physical', null, null, null,
 'General Safety Regulations, staged pending verification',
 'unverified'),
('G', 'Vibration, hand arm and whole body', 'physical', null, null,
 'No verified South African occupational exposure limit located for whole body vibration; action values from international guidance are not citable and client measurements are assessed by the OMP',
 'Physical Agents Regulations, 2024 staged for verification; Ergonomics Regulations, 2019 for musculoskeletal effect',
 'unverified'),
('H', 'Heat and thermal stress', 'physical', null, null,
 'WBGT based assessment; limit values pending verification of the Environmental Regulations for Workplaces',
 'Environmental Regulations for Workplaces, staged pending verification',
 'unverified'),
('I', 'Manual handling and ergonomic strain', 'ergonomic', null, null, null,
 'Ergonomics Regulations, 2019, GN R.1589',
 'unverified'),
('J', 'Driving (licence and PrDP class per notes)', 'physical', null, null, null,
 'National Road Traffic Act 93 of 1996, PrDP medical fitness provisions',
 'unverified'),
('K', 'Shift or night work', 'psychosocial', null, null, null,
 'Basic Conditions of Employment Act 75 of 1997 section 17(3), Code of Good Practice on the Arrangement of Working Time',
 'unverified'),
('L', 'Ionising or non ionising radiation', 'physical', null, null, null,
 'Agent specific instruments staged for a later verification batch',
 'unverified'),
('M', 'Electrical hazard', 'physical', null, null, null,
 'Electrical Installation and Electrical Machinery Regulations, staged for a later verification batch',
 'unverified'),
('N', 'Psychosocial hazard', 'psychosocial', null, null, null,
 'COIDA as amended recognises post traumatic stress disorder as an occupational disease from the 2026 commencement',
 'unverified'),
('O', 'Other (specify in notes)', 'physical', null, null, null,
 'Placeholder key per the canonical questionnaire; never maps to a protocol without OMP direction',
 'unverified');

-- 4. Pilot job roles (canonical example, CONSTR-CIVILS) --------------------------

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Site Manager / Supervisor',
        'Site oversight, inspection, coordination of trades',
        'Regular walking across uneven site terrain; occasional ladder access',
        'Sustained attention, verbal communication',
        'None beyond general induction'),
       ('General Labourer',
        'Manual labour, material handling, demolition and site clearing',
        'Frequent manual lifting up to 25kg, repetitive bending',
        'Basic instruction following',
        'None beyond general induction'),
       ('Scaffolder / Heights Worker',
        'Erecting, altering, and dismantling scaffolding and access structures',
        'Climbing, working from unprotected edges, carrying loads at height',
        'Spatial awareness, balance, no vertigo',
        'Working at heights competency certificate'),
       ('Plant Operator',
        'Operating heavy earthmoving, lifting, and compaction machinery',
        'Prolonged sitting, foot and hand coordination under vibration',
        'Sustained visual attention, depth perception',
        'Plant operator certificate for the relevant class'),
       ('Welder / Steel Fabricator',
        'Cutting, welding, and fabricating structural steelwork',
        'Sustained awkward postures, fine motor control',
        'Colour vision for weld inspection, sustained attention near arc and heat',
        'Trade certification as applicable'),
       ('Concrete and Cement Worker',
        'Mixing, placing, and finishing concrete; formwork erection',
        'Frequent manual handling, kneeling, repetitive strain',
        'Basic instruction following',
        'None beyond general induction'),
       ('Electrician (site)',
        'Electrical installation, testing, and maintenance',
        'Working in restricted and confined access, occasional heights',
        'Fine motor control, colour vision for wiring',
        'Wireman''s licence; heights certificate if applicable'),
       ('Driver / Plant and Materials Transport',
        'Transporting materials, plant, and equipment between sites',
        'Prolonged sitting, reversing and manoeuvring in confined yards',
        'Sustained visual attention, reaction time, no uncontrolled hypoglycaemic risk',
        'Valid driving licence; PrDP where required')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'CONSTR-CIVILS';

-- 5. Job to hazard map ----------------------------------------------------------

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('Site Manager / Supervisor', 'A', 'Low', 'Incidental plant noise during site oversight'),
  ('Site Manager / Supervisor', 'B', 'Low', 'Incidental dust during site inspection'),
  ('Site Manager / Supervisor', 'E', 'Low to Moderate', 'Occasional exposure above 1.5m during site inspection'),
  ('Site Manager / Supervisor', 'H', 'Low', 'Outdoor sun exposure'),
  ('General Labourer', 'A', 'Moderate', 'Noise from surrounding plant and tools'),
  ('General Labourer', 'B', 'Moderate', 'Cement and concrete dust including respirable crystalline silica'),
  ('General Labourer', 'I', 'Moderate', 'Manual handling strain from material handling and site clearing'),
  ('General Labourer', 'H', 'Moderate', 'Heat and sun exposure in outdoor work'),
  ('Scaffolder / Heights Worker', 'E', 'High', 'Working at height above 1.5m with fall risk'),
  ('Scaffolder / Heights Worker', 'G', 'Moderate', 'Hand arm vibration from power tools'),
  ('Scaffolder / Heights Worker', 'A', 'Moderate', 'Noise from power tools and surrounding plant'),
  ('Plant Operator', 'G', 'Moderate to High', 'Whole body vibration from earthmoving and compaction machinery'),
  ('Plant Operator', 'A', 'High', 'Plant and compaction area noise; client measurements in the canonical example exceeded the rating limit'),
  ('Plant Operator', 'C', 'Moderate', 'Diesel exhaust fumes'),
  ('Plant Operator', 'I', 'Moderate', 'Prolonged sitting and postural strain'),
  ('Welder / Steel Fabricator', 'C', 'High', 'Welding fume including manganese oxide'),
  ('Welder / Steel Fabricator', 'L', 'Moderate', 'Ultraviolet radiation from arc welding'),
  ('Welder / Steel Fabricator', 'A', 'Moderate to High', 'Fabrication bay noise'),
  ('Concrete and Cement Worker', 'B', 'High', 'Cement and concrete dust, respirable crystalline silica'),
  ('Concrete and Cement Worker', 'C', 'Moderate', 'Wet cement skin contact, dermatitis and burns'),
  ('Concrete and Cement Worker', 'I', 'Moderate', 'Frequent manual handling and repetitive strain'),
  ('Electrician (site)', 'M', 'Moderate', 'Electrical installation, testing, and maintenance'),
  ('Electrician (site)', 'E', 'Low to Moderate', 'Occasional work at height above 1.5m'),
  ('Electrician (site)', 'F', 'Low', 'Occasional confined space work'),
  ('Driver / Plant and Materials Transport', 'J', 'Moderate', 'Professional driving with PrDP regulated fitness requirement'),
  ('Driver / Plant and Materials Transport', 'G', 'Moderate', 'Prolonged driving vibration'),
  ('Driver / Plant and Materials Transport', 'I', 'Moderate', 'Musculoskeletal strain and fatigue')
) as m(title, hazard_code, rating, rationale)
join msp_job_role jr on jr.title = m.title
join msp_subindustry s on s.id = jr.subindustry_id and s.code = 'CONSTR-CIVILS'
join msp_hazard h on h.code = m.hazard_code;

-- 6. Test protocols per hazard --------------------------------------------------

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id, p.test_name, p.test_type, p.baseline, p.interval_months, p.exit,
       p.triggers, p.bio_ref, li.id
from (values
  ('A', 'Audiometry', 'clinical', true, 12, true,
   'Exposure at or above the 85 dB(A) noise rating limit, or as directed by the OMP. Baseline within the statutory window at commencement of exposure.',
   null, 'NIHL Regulations, 2003'),
  ('B', 'Spirometry', 'clinical', true, 12, true,
   'Respirable crystalline silica or other respirable dust exposure per the OREP.',
   null, 'HCA Regulations, 2021'),
  ('B', 'Respiratory symptom questionnaire', 'clinical', true, 12, true,
   'Administered with spirometry for dust exposed categories.',
   null, 'HCA Regulations, 2021'),
  ('B', 'Chest X-ray per silica protocol', 'clinical', true, 12, true,
   'Where clinically indicated by the OMP for silica exposed workers, tightened on exceedance; reading per the OMP''s protocol.',
   null, 'HCA Regulations, 2021'),
  ('C', 'Occupational chemical exposure medical assessment', 'clinical', true, 12, true,
   'Battery tailored by the OMP to the specific agents in the engagement chemical register.',
   null, 'HCA Regulations, 2021'),
  ('C', 'Dermatological screen', 'clinical', true, 12, true,
   'Skin contact hazards, including wet cement dermatitis and burns risk.',
   null, 'HCA Regulations, 2021'),
  ('C', 'Biological monitoring for specific agents', 'biological_monitoring', true, 12, true,
   'Where the hazard demands it, for example manganese exposure in welding fume or solvent metabolite monitoring.',
   '[CONFIRM] Agent specific biological reference values are not yet kernel verified and route to the OMP queue; never printed unresolved.',
   'HCA Regulations, 2021'),
  ('E', 'Heights medical (cardiovascular, neurological, vision, blood pressure, BMI, vertigo and balance screen)', 'clinical', true, 12, true,
   'All work above 1.5m. The Construction Regulations Annexure 3 certificate is valid for one year, and third party validity requirements from the intake can only tighten this.',
   null, 'Construction Regulations, 2014'),
  ('F', 'Confined space medical (cardiorespiratory fitness, spirometry, claustrophobia screen)', 'clinical', true, 12, true,
   'Confined space entry duties per the OREP.',
   null, null),
  ('G', 'Vibration and musculoskeletal screen', 'clinical', true, 12, true,
   'Hand arm or whole body vibration exposure; assessment of client measured levels is an OMP determination while no verified South African limit is in the kernel.',
   null, 'Ergonomics Regulations, 2019'),
  ('H', 'Heat stress tolerance assessment', 'clinical', true, 12, true,
   'Work in WBGT exceedance areas or sustained outdoor summer work.',
   null, null),
  ('I', 'Musculoskeletal and ergonomic assessment', 'clinical', true, 12, true,
   'Manual handling, repetitive strain, and postural risk categories per the ergonomics risk assessment.',
   null, 'Ergonomics Regulations, 2019'),
  ('J', 'PrDP statutory medical and vision screen', 'clinical', true, 12, true,
   'Professional driving duties. The prescribed certificate must be current per licensing authority requirements, and the surveillance interval never exceeds the annual floor.',
   null, 'NRTA PrDP medical'),
  ('K', 'Night work medical examination', 'clinical', true, 12, true,
   'At commencement of regular night work and periodically thereafter, at the employer''s expense, per BCEA section 17(3) and the Code of Good Practice.',
   null, 'BCEA night work Code'),
  ('L', 'Vision screening including colour vision, and skin surveillance for ultraviolet exposure', 'clinical', true, 12, true,
   'Arc welding and other radiation exposure categories.',
   null, null),
  ('M', 'General medical with cardiovascular and vision screen (electrical work)', 'clinical', true, 12, true,
   'Electrical work fitness per the inherent requirements of the role.',
   null, null)
) as p(hazard_code, test_name, test_type, baseline, interval_months, exit, triggers, bio_ref, basis_short_name)
join msp_hazard h on h.code = p.hazard_code
left join msp_legal_instrument li
  on li.short_name = p.basis_short_name and li.status = 'verified';

-- 7. Industry to instrument map -------------------------------------------------

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('OHS Act', 'Framework Act for all construction workplaces'),
  ('Construction Regulations, 2014', 'Core sector regulation: heights, excavations, scaffolding, Annexure 3 medical certificate of fitness'),
  ('NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026'),
  ('Noise Exposure Regulations, 2024', 'Successor noise instrument, sole operative instrument from 06/09/2026'),
  ('HCA Regulations, 2021', 'Silica, cement, welding fume, diesel exhaust, solvents, and the chemical register'),
  ('Ergonomics Regulations, 2019', 'Manual handling, vibration effect, and postural risk surveillance'),
  ('COIDA', 'Compensation route for all construction occupational injuries and diseases'),
  ('EEA section 7', 'Lawful basis for every medical test, justified against the inherent requirements of each job'),
  ('BCEA night work Code', 'Applies where the intake reports regular night work'),
  ('NRTA PrDP medical', 'Applies to professional driving categories'),
  ('HPCSA Booklet 1', 'Ethical baseline for all examinations under the programme'),
  ('HPCSA Booklet 10', 'Governs any telehealth component of the programme'),
  ('HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(short_name, note)
  on true
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
where i.code = 'CONSTR';

-- 8. Kernel rules ---------------------------------------------------------------

insert into msp_kernel_rule (rule_code, description, condition_expr, effect, instrument_id, status)
values
('ROUTE-ODMWA-COIDA',
 'Compensation routing. Mining lung disease follows the ODMWA route; all other sectors and conditions follow COIDA. Encoded as data so the FRAME stage sets the route without prose reasoning.',
 '{"field": "industry.regulatory_regime", "cases": {"OHSA": "COIDA", "MHSA": "ODMWA for compensable lung disease, COIDA otherwise", "DUAL": "ODMWA for compensable lung disease, COIDA otherwise"}}',
 '{"set": "compensation_route"}',
 (select id from msp_legal_instrument where short_name = 'COIDA'),
 'verified'),
('TRIGGER-NIGHTWORK',
 'Regular night work in the intake adds the BCEA Code instrument and the hazard K night work medical to every affected category.',
 '{"field": "intake.shift_night_work", "equals": true}',
 '{"add_instrument": "BCEA night work Code", "add_hazard_protocols": "K"}',
 (select id from msp_legal_instrument where short_name = 'BCEA night work Code'),
 'verified'),
('TRIGGER-PRDP',
 'Any job category carrying hazard code J adds the NRTA instrument and the PrDP statutory battery for that category.',
 '{"field": "job.hazard_codes", "contains": "J"}',
 '{"add_instrument": "NRTA PrDP medical", "add_hazard_protocols": "J"}',
 (select id from msp_legal_instrument where short_name = 'NRTA PrDP medical'),
 'verified'),
('RULE-NOISE-TRANSITION',
 'Noise instrument transition. Packs generated before 06/09/2026 cite the NIHL Regulations, 2003 as operative and disclose the transition to the Noise Exposure Regulations, 2024; packs generated on or after that date cite the 2024 Regulations alone.',
 '{"field": "engagement.created_at", "before": "2026-09-06", "then": "NIHL Regulations, 2003 operative with transition disclosure", "else": "Noise Exposure Regulations, 2024 operative"}',
 '{"select_noise_instrument": true}',
 (select id from msp_legal_instrument where short_name = 'Noise Exposure Regulations, 2024'),
 'verified'),
('RULE-EXCEEDANCE-TIGHTEN',
 'A measured exposure at or above the applicable OEL can only tighten a surveillance interval, never loosen it, and always carries the compliance note that surveillance detects early effect but does not substitute for controlling exposure at source.',
 '{"field": "exceedance.assessment", "in": ["exceeds", "significantly_exceeds", "borderline"]}',
 '{"interval_policy": "tighten_only", "insert_template": "TPL-CGN-01"}',
 null,
 'verified'),
('RULE-HPCSA-PAYER',
 'The employer is always the payer. Charging receiving specialists for referrals is prohibited under the HPCSA perverse incentive rules.',
 '{"always": true}',
 '{"assert": "employer_is_payer", "prohibit": "charges_to_receiving_specialist"}',
 (select id from msp_legal_instrument where short_name = 'HPCSA Booklet 11'),
 'verified');

-- 9. Confirmation register ------------------------------------------------------

insert into msp_confirmation_item (item_code, kind, description, status, resolution, resolved_by, resolved_on)
values
('CR-12.1', 'confirm', 'Exact OEL values and schedules per hazard at kernel ingestion. Noise 85 dB(A) and respirable crystalline silica 0.1 mg/m3 verified 12/08/2026; all other values remain open.', 'open', null, null, null),
('CR-12.2', 'confirm', 'COIDA Circular Instruction numbers and current versions for NIHL, occupational lung disease, work related upper limb disorders, PTSD, and occupationally acquired infections.', 'open', null, null, null),
('CR-12.3', 'confirm', 'SANS standard numbers and editions for audiometry, noise measurement, and spirometry method, including the 2025 Code of Practice for Audiometry accompanying the Noise Exposure Regulations, 2024.', 'open', null, null, null),
('CR-12.4', 'confirm', 'Statutory retention periods per occupational health record class. Long retention presumed, never defaulted to short cycles.', 'open', null, null, null),
('CR-12.5', 'confirm', 'DPA status for DocuSeal, Vercel, Supabase, and Anthropic as POPIA operators.', 'open', null, null, null),
('CR-12.6', 'confirm', 'CNC Information Officer name and privacy contact for the POPIA blocks.', 'open', null, null, null),
('CR-12.7', 'confirm', 'Designated OMP name and HPCSA practice number per engagement.', 'open', null, null, null),
('CR-12.8', 'assumption', 'Location and format of existing CNC industry guides and academy metadata for precedent ingestion (Phase 2).', 'open', null, null, null),
('CR-12.9', 'assumption', 'Availability of helena-copywriting skill assets in the build environment.', 'resolved',
 'Checked 12/08/2026: not present in the build environment. The voice rules of Master Prompt Section 9.1 govern directly.', 'Build session', '2026-08-12'),
('CR-12.10', 'assumption', 'DocuSeal plan supports the required file upload field types and webhook payloads at production volume. Tested in Phase 2.', 'open', null, null, null),
('CR-13.1', 'confirm', 'Target Supabase project for the kernel and engagement schema.', 'resolved',
 'Resolved 12/08/2026: single project ahp-production (pboebfnujzffgwctsplw) in the account; msp_ prefixed additive schema applied; Care Net Consultants is Tenant 001 on that platform. Revisit only if a dedicated project is later mandated.', 'Build session under user run approval', '2026-08-12'),
('CR-13.2', 'confirm', 'Target Vercel team and project for the webhook receiver and agent runtime before Phase 2.', 'open', null, null, null),
('CR-13.3', 'confirm', 'CNC telephone and email for the questionnaire contact line (placeholders in canonical V1.2).', 'open', null, null, null),
('CR-13.4', 'confirm', 'Source assets for the CNC logo mark used in the dual brand header band.', 'open', null, null, null),
('CR-13.5', 'confirm', 'Classification banner values for generated packs (canonical uses CLASSIFICATION: CLIENT).', 'open', null, null, null),
('CR-13.6', 'confirm', 'Whether the Ubuntu closing line, I am because we are, carries into generated packs alongside the locked footer line.', 'open', null, null, null),
('CR-13.7', 'assumption', 'CLASSIFY triage confidence threshold set at 0.85 pending calibration in Phase 3.', 'open', null, null, null),
('CR-13.8', 'confirm', 'Precise National Road Traffic Regulations provision number for the PrDP medical certificate requirement.', 'open', null, null, null),
('CR-13.9', 'confirm', 'Verification of the General Safety, General Administrative, General Machinery, and Driven Machinery Regulations before any pack cites them.', 'open', null, null, null),
('CR-13.10', 'confirm', 'Noise rating limit value under the Noise Exposure Regulations, 2024 before the 06/09/2026 transition, so hazard A citation swaps correctly.', 'open', null, null, null);


------------------------------------------------------------------------------
-- 005_msp_intake_schema.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | FRM-INT-01 v1.0.0 | Engagement and intake schema
-- Phase 2 migration 005. Also delivers the append only msp_audit table
-- (anchor POP-AUD-01, brought forward so every intake event is logged from
-- the first webhook; Phase 5 hardens and surfaces it) and the msp_precedent
-- store (KRN-PREC-01, table only; ingestion awaits CR-12.8).

create table msp_client (
  id uuid primary key default gen_random_uuid(),
  registered_name text not null,
  trading_name text,
  registration_number text,
  vat_number text,
  head_office_address text,
  created_at timestamptz default now()
);

create table msp_engagement (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references msp_client(id),
  reference text unique not null,
  status text not null default 'intake'
    check (status in ('intake','triage','classifying','drafting','validating',
                      'omp_queue','approved','released','rejected','archived')),
  industry_id uuid references msp_industry(id),
  subindustry_id uuid references msp_subindustry(id),
  classification_confidence numeric,
  created_at timestamptz default now()
);
comment on column msp_engagement.reference is 'CNC-MSP-YYYY-MMDD-NNN per the house document naming convention.';

create table msp_intake (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  docuseal_submission_id text not null,
  raw_payload jsonb not null,
  schema_version text not null,
  received_at timestamptz default now(),
  validation_status text not null check (validation_status in ('valid','triage')),
  triage_reason text
);
comment on column msp_intake.raw_payload is 'Validated payload as received. By design the form carries no special personal information about identifiable individuals; the webhook validator rejects patterns that look like identity numbers or named clinical detail and masks the offending field in logs.';

create table msp_intake_site (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  site_name text not null,
  site_address text,
  activity text,
  headcount int
);

create table msp_intake_job_category (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  row_no int not null,
  title text not null,
  headcount int,
  duties text,
  hazard_codes text[],
  existing_controls text,
  physical_demands text,
  sensory_cognitive_demands text,
  statutory_requirement text,
  chronic_flag boolean not null default false,
  rpe_issued text,
  rpe_fit_tested text,
  rpe_fit_test_interval text,
  other_ppe text
);
comment on column msp_intake_job_category.chronic_flag is 'Aggregate flag per job category only. No individual is ever named, enforced at the form, the validator, and here.';

create table msp_intake_exposure (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  hazard_location text not null,
  measured_level text not null,
  unit text,
  stated_oel text,
  date_measured date
);

create table msp_intake_chemical (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  substance_name text not null,
  sds_reference text,
  task_process text,
  frequency text,
  quantity_per_use text,
  controls text
);

create table msp_intake_file (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  file_kind text not null check (file_kind in ('risk_assessment','hygiene_report','sds','client_logo','other')),
  storage_path text not null,
  original_filename text,
  uploaded_at timestamptz default now()
);

create table msp_consent (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  consent_kind text not null check (consent_kind in ('processing','marketing','popia_forms_election')),
  granted boolean not null,
  wording_version text not null,
  granted_at timestamptz not null,
  withdrawal_contact text not null,
  withdrawn_at timestamptz
);
comment on table msp_consent is 'Unbundled POPIA consent records: processing consent (required, specific purpose), marketing consent (separate, default off), and the POPIA forms election. Stored with timestamp, wording version, and withdrawal mechanism.';

-- POP-AUD-01 (brought forward): append only audit log.
create table msp_audit (
  id bigint generated always as identity primary key,
  engagement_id uuid,
  actor text not null,
  event_type text not null,
  event_detail jsonb not null,
  created_at timestamptz default now()
);
comment on table msp_audit is 'Append only. Every classification, kernel citation, draft, OMP decision, and release lands here so any pack can be reconstructed and defended line by line.';

create or replace function msp_audit_block_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'msp_audit is append only';
end;
$$;

create trigger msp_audit_no_update
  before update or delete on msp_audit
  for each row execute function msp_audit_block_mutation();

revoke update, delete on msp_audit from authenticated, anon;

-- KRN-PREC-01: precedent store, table only in Phase 2. Ingestion of CNC
-- industry guides, academy metadata, and approved plans awaits CR-12.8.
create table msp_precedent (
  id uuid primary key default gen_random_uuid(),
  source_name text not null,
  source_type text not null check (source_type in ('industry_guide','academy_metadata','approved_plan')),
  industry_id uuid references msp_industry(id),
  chunk_index int not null,
  content text not null,
  embedding extensions.vector(1536),
  ingested_at timestamptz default now()
);
comment on table msp_precedent is 'Precedent material for house style and depth. The agent cites the kernel for law and this store for style. Never a source of legal truth.';

-- Row Level Security -----------------------------------------------------------

alter table msp_client              enable row level security;
alter table msp_engagement          enable row level security;
alter table msp_intake              enable row level security;
alter table msp_intake_site         enable row level security;
alter table msp_intake_job_category enable row level security;
alter table msp_intake_exposure     enable row level security;
alter table msp_intake_chemical     enable row level security;
alter table msp_intake_file         enable row level security;
alter table msp_consent             enable row level security;
alter table msp_audit               enable row level security;
alter table msp_precedent           enable row level security;

-- Engagement scoped data: forge roles read; agent and admin write during the
-- pipeline; the webhook path runs server side under the service role, which
-- bypasses RLS by design and never reaches the browser.

create policy msp_client_read on msp_client
  for select to authenticated using (msp_any_forge_role());
create policy msp_client_write on msp_client
  for insert to authenticated
  with check (msp_has_role('forge_agent') or msp_has_role('forge_admin'));

create policy msp_engagement_read on msp_engagement
  for select to authenticated using (msp_any_forge_role());
create policy msp_engagement_write on msp_engagement
  for insert to authenticated
  with check (msp_has_role('forge_agent') or msp_has_role('forge_admin'));
create policy msp_engagement_update on msp_engagement
  for update to authenticated
  using (msp_has_role('forge_agent') or msp_has_role('forge_admin') or msp_has_role('forge_omp'));

create policy msp_intake_read on msp_intake
  for select to authenticated using (msp_any_forge_role());
create policy msp_intake_site_read on msp_intake_site
  for select to authenticated using (msp_any_forge_role());
create policy msp_intake_job_category_read on msp_intake_job_category
  for select to authenticated using (msp_any_forge_role());
create policy msp_intake_exposure_read on msp_intake_exposure
  for select to authenticated using (msp_any_forge_role());
create policy msp_intake_chemical_read on msp_intake_chemical
  for select to authenticated using (msp_any_forge_role());
create policy msp_intake_file_read on msp_intake_file
  for select to authenticated using (msp_any_forge_role());
create policy msp_consent_read on msp_consent
  for select to authenticated
  using (msp_has_role('forge_admin') or msp_has_role('forge_omp'));

create policy msp_audit_read on msp_audit
  for select to authenticated
  using (msp_has_role('forge_admin') or msp_has_role('forge_omp'));
create policy msp_audit_insert on msp_audit
  for insert to authenticated with check (msp_any_forge_role());

create policy msp_precedent_read on msp_precedent
  for select to authenticated using (msp_any_forge_role());
create policy msp_precedent_write on msp_precedent
  for insert to authenticated with check (msp_has_role('forge_verifier'));

create index msp_engagement_client_idx on msp_engagement(client_id);
create index msp_intake_engagement_idx on msp_intake(engagement_id);
create index msp_intake_job_category_intake_idx on msp_intake_job_category(intake_id);
create index msp_audit_engagement_idx on msp_audit(engagement_id);


------------------------------------------------------------------------------
-- 006_msp_ingest_intake.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | FRM-INT-01 v1.1.0 | Transactional intake ingest
-- Phase 2 migration 006. One controlled write path for a validated intake:
-- the Vercel webhook handler calls this RPC after JSON schema validation, and
-- the synthetic end to end test calls the same function, so test and
-- production exercise identical persistence code. Executable by the service
-- role only; revoked from every client facing role.

create sequence if not exists msp_engagement_ref_seq;

create or replace function msp_next_reference()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  -- Serialise reference numbering per day so CNC-MSP-YYYY-MMDD-NNN stays gapless
  -- enough for filing while remaining collision free under concurrency.
  perform pg_advisory_xact_lock(hashtext('msp_engagement_reference'));
  select count(*) + 1 into v_n
    from msp_engagement
   where created_at::date = current_date;
  return 'CNC-MSP-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(v_n::text, 3, '0');
end;
$$;

create or replace function msp_ingest_intake(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client_id uuid;
  v_engagement_id uuid;
  v_intake_id uuid;
  v_reference text;
  v_status text;
  v_triage_reason text;
  v_job jsonb;
  v_site jsonb;
  v_exp jsonb;
  v_chem jsonb;
  v_row int := 0;
begin
  -- Defence in depth: the webhook validator runs first, but core invariants
  -- are re-asserted here so no caller can bypass them.
  if coalesce(p->>'company_registered_name', '') = '' then
    raise exception 'company_registered_name is required';
  end if;
  if coalesce(p->>'docuseal_submission_id', '') = '' then
    raise exception 'docuseal_submission_id is required';
  end if;
  if jsonb_array_length(coalesce(p->'jobs', '[]'::jsonb)) = 0 then
    raise exception 'at least one job category is required';
  end if;
  if (p::text) ~ '\d{13}' then
    raise exception 'payload rejected: contains a thirteen digit sequence resembling a South African identity number';
  end if;
  if coalesce((p->>'consent_processing')::boolean, false) is distinct from true then
    raise exception 'processing consent is required before intake persistence';
  end if;

  v_status := coalesce(p->>'validation_status', 'valid');
  v_triage_reason := p->>'triage_reason';

  insert into msp_client (registered_name, trading_name, registration_number, vat_number, head_office_address)
  values (p->>'company_registered_name',
          nullif(p->>'company_trading_name',''),
          nullif(p->>'company_registration_number',''),
          nullif(p->>'company_vat_number',''),
          nullif(p->>'company_head_office_address',''))
  returning id into v_client_id;

  v_reference := msp_next_reference();

  insert into msp_engagement (client_id, reference, status)
  values (v_client_id, v_reference, case when v_status = 'triage' then 'triage' else 'intake' end)
  returning id into v_engagement_id;

  insert into msp_intake (engagement_id, docuseal_submission_id, raw_payload, schema_version, validation_status, triage_reason)
  values (v_engagement_id, p->>'docuseal_submission_id', p, coalesce(p->>'schema_version','intake.v1'), v_status, v_triage_reason)
  returning id into v_intake_id;

  for v_site in select * from jsonb_array_elements(coalesce(p->'sites','[]'::jsonb)) loop
    insert into msp_intake_site (intake_id, site_name, site_address, activity, headcount)
    values (v_intake_id,
            coalesce(v_site->>'name','Unnamed site'),
            v_site->>'address', v_site->>'activity',
            nullif(v_site->>'headcount','')::int);
  end loop;

  for v_job in select * from jsonb_array_elements(p->'jobs') loop
    v_row := v_row + 1;
    insert into msp_intake_job_category
      (intake_id, row_no, title, headcount, duties, hazard_codes, existing_controls,
       physical_demands, sensory_cognitive_demands, statutory_requirement,
       chronic_flag, rpe_issued, rpe_fit_tested, rpe_fit_test_interval, other_ppe)
    values
      (v_intake_id, v_row,
       v_job->>'title',
       nullif(v_job->>'headcount','')::int,
       v_job->>'duties',
       case when v_job ? 'hazard_codes'
            then array(select jsonb_array_elements_text(v_job->'hazard_codes'))
            else null end,
       v_job->>'existing_controls',
       v_job->>'physical_demands',
       v_job->>'sensory_cognitive_demands',
       v_job->>'statutory_requirement',
       coalesce((v_job->>'chronic_flag')::boolean, false),
       v_job->>'rpe_issued', v_job->>'rpe_fit_tested',
       v_job->>'rpe_fit_test_interval', v_job->>'other_ppe');
  end loop;

  for v_exp in select * from jsonb_array_elements(coalesce(p->'exposures','[]'::jsonb)) loop
    insert into msp_intake_exposure (intake_id, hazard_location, measured_level, unit, stated_oel, date_measured)
    values (v_intake_id,
            coalesce(v_exp->>'hazard_location','Unspecified'),
            coalesce(v_exp->>'measured_level',''),
            v_exp->>'unit', v_exp->>'stated_oel',
            nullif(v_exp->>'date_measured','')::date);
  end loop;

  for v_chem in select * from jsonb_array_elements(coalesce(p->'chemicals','[]'::jsonb)) loop
    insert into msp_intake_chemical (intake_id, substance_name, sds_reference, task_process, frequency, quantity_per_use, controls)
    values (v_intake_id,
            coalesce(v_chem->>'substance_name','Unspecified'),
            v_chem->>'sds_reference', v_chem->>'task_process',
            v_chem->>'frequency', v_chem->>'quantity_per_use', v_chem->>'controls');
  end loop;

  -- Unbundled POPIA consent records. Processing consent is asserted above;
  -- marketing consent defaults to false and is stored either way as a record
  -- of what was and was not granted.
  insert into msp_consent (engagement_id, consent_kind, granted, wording_version, granted_at, withdrawal_contact)
  values
    (v_engagement_id, 'processing', true,
     coalesce(p->>'consent_wording_version','popia.v1'), now(),
     coalesce(p->>'information_officer_contact','Care Net Consultants Information Officer')),
    (v_engagement_id, 'marketing', coalesce((p->>'consent_marketing')::boolean, false),
     coalesce(p->>'consent_wording_version','popia.v1'), now(),
     coalesce(p->>'information_officer_contact','Care Net Consultants Information Officer')),
    (v_engagement_id, 'popia_forms_election', coalesce((p->>'popia_use_cnc_forms')::boolean, true),
     coalesce(p->>'consent_wording_version','popia.v1'), now(),
     coalesce(p->>'information_officer_contact','Care Net Consultants Information Officer'));

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_engagement_id, 'webhook', 'intake_received',
          jsonb_build_object(
            'docuseal_submission_id', p->>'docuseal_submission_id',
            'schema_version', coalesce(p->>'schema_version','intake.v1'),
            'validation_status', v_status,
            'triage_reason', v_triage_reason,
            'job_count', jsonb_array_length(p->'jobs'),
            'reference', v_reference));

  return jsonb_build_object(
    'engagement_id', v_engagement_id,
    'intake_id', v_intake_id,
    'reference', v_reference,
    'status', case when v_status = 'triage' then 'triage' else 'intake' end);
end;
$$;

-- The controlled write path is server side only.
revoke execute on function msp_ingest_intake(jsonb) from public, anon, authenticated;
revoke execute on function msp_next_reference() from public, anon, authenticated;


------------------------------------------------------------------------------
-- 007_msp_draft_review.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | AGT-QUE-01 v1.0.0 and POP-OMP-01 v0.1.0 | Draft, review, release
-- Phase 3 migration 007. Stage outputs, validation defects, the OMP review
-- queue, and the release gate. The gate is a database trigger: a release row
-- cannot exist without a matching approved OMP review. Enforced here, not in
-- any UI. Phase 5 delivers the review interface on top of these tables.

create table msp_draft (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  stage text not null check (stage in ('classify','frame','profile','prescribe','compose','validate')),
  stage_output jsonb not null,
  schema_version text not null,
  model_used text not null,
  created_at timestamptz default now()
);

create table msp_defect (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  stage text not null,
  defect_code text not null,
  detail jsonb not null,
  blocking boolean not null default true,
  created_at timestamptz default now()
);

create table msp_omp_review (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  draft_id uuid not null references msp_draft(id),
  decision text check (decision in ('approved','amended','rejected')),
  omp_name text,
  omp_hpcsa_number text,
  decided_at timestamptz,
  amendment_notes jsonb,
  constraint msp_omp_decision_complete
    check (decision is null
           or (omp_name is not null and omp_hpcsa_number is not null and decided_at is not null))
);
comment on table msp_omp_review is 'The engine drafts; a registered Occupational Medical Practitioner approves. A decision row must carry the OMP name, HPCSA practice number, and timestamp.';

create table msp_release (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  omp_review_id uuid not null references msp_omp_review(id),
  docx_path text not null,
  pdf_path text not null,
  docuseal_envelope_id text,
  released_at timestamptz default now()
);

create or replace function msp_release_gate()
returns trigger
language plpgsql
as $$
declare
  v_decision text;
begin
  select decision into v_decision from msp_omp_review where id = new.omp_review_id;
  if v_decision is distinct from 'approved' then
    raise exception 'release blocked: OMP review % is not approved', new.omp_review_id;
  end if;
  return new;
end;
$$;

create trigger msp_release_requires_approval
  before insert on msp_release
  for each row execute function msp_release_gate();
comment on trigger msp_release_requires_approval on msp_release is 'No pack releases without recorded OMP approval. Enforced in the database, not the UI.';

create table msp_document (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  artefact_kind text not null check (artefact_kind in ('docx','pdf','signature_envelope','geometry_report')),
  storage_path text not null,
  version int not null,
  created_at timestamptz default now()
);

alter table msp_draft      enable row level security;
alter table msp_defect     enable row level security;
alter table msp_omp_review enable row level security;
alter table msp_release    enable row level security;
alter table msp_document   enable row level security;

create policy msp_draft_read on msp_draft
  for select to authenticated using (msp_any_forge_role());
create policy msp_draft_write on msp_draft
  for insert to authenticated with check (msp_has_role('forge_agent'));

create policy msp_defect_read on msp_defect
  for select to authenticated using (msp_any_forge_role());
create policy msp_defect_write on msp_defect
  for insert to authenticated with check (msp_has_role('forge_agent'));

create policy msp_omp_review_read on msp_omp_review
  for select to authenticated
  using (msp_has_role('forge_omp') or msp_has_role('forge_admin') or msp_has_role('forge_agent'));
create policy msp_omp_review_queue on msp_omp_review
  for insert to authenticated with check (msp_has_role('forge_agent'));
create policy msp_omp_review_decide on msp_omp_review
  for update to authenticated using (msp_has_role('forge_omp'));

create policy msp_release_read on msp_release
  for select to authenticated
  using (msp_has_role('forge_omp') or msp_has_role('forge_admin'));
create policy msp_release_write on msp_release
  for insert to authenticated with check (msp_has_role('forge_admin'));

create policy msp_document_read on msp_document
  for select to authenticated using (msp_any_forge_role());
create policy msp_document_write on msp_document
  for insert to authenticated
  with check (msp_has_role('forge_agent') or msp_has_role('forge_admin'));

create index msp_draft_engagement_idx on msp_draft(engagement_id);
create index msp_omp_review_engagement_idx on msp_omp_review(engagement_id);


------------------------------------------------------------------------------
-- 008_msp_omp_workflow.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | POP-OMP-01 v1.0.0, POP-DSR-01 v1.0.0 | OMP workflow and data subject rights
-- Phase 5 migration 008. The OMP decision path, the release path behind the
-- database gate, the engagement export for data subject access, and the
-- erasure workflow that respects occupational health record retention.
-- Every function asserts the caller's role itself: the UI is never trusted.

create or replace function msp_caller_is(p_role text)
returns boolean
language sql
stable
set search_path = public
as $$
  select auth.role() = 'service_role' or msp_has_role(p_role);
$$;
comment on function msp_caller_is is 'Role gate for workflow functions: the named forge role, or the server side service context.';

-- OMP decision: approve, amend, or reject. Recorded with name, HPCSA practice
-- number, and timestamp. Release remains impossible without an approved row.
create or replace function msp_omp_decide(
  p_review_id uuid,
  p_decision text,
  p_omp_name text,
  p_omp_hpcsa_number text,
  p_amendment_notes jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng uuid;
begin
  if not msp_caller_is('forge_omp') then
    raise exception 'only the Designated OMP may record a decision';
  end if;
  if p_decision not in ('approved','amended','rejected') then
    raise exception 'decision must be approved, amended, or rejected';
  end if;
  if coalesce(btrim(p_omp_name),'') = '' or coalesce(btrim(p_omp_hpcsa_number),'') = '' then
    raise exception 'a decision must carry the OMP name and HPCSA practice number';
  end if;

  update msp_omp_review
     set decision = p_decision,
         omp_name = p_omp_name,
         omp_hpcsa_number = p_omp_hpcsa_number,
         decided_at = now(),
         amendment_notes = p_amendment_notes
   where id = p_review_id and decision is null
   returning engagement_id into v_eng;

  if v_eng is null then
    raise exception 'review % not found or already decided', p_review_id;
  end if;

  update msp_engagement
     set status = case p_decision when 'approved' then 'approved'
                                  when 'rejected' then 'rejected'
                                  else 'omp_queue' end
   where id = v_eng;

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng, 'omp:' || p_omp_name, 'omp_decision',
          jsonb_build_object('review_id', p_review_id, 'decision', p_decision,
                             'hpcsa_number', p_omp_hpcsa_number,
                             'amendment_notes', p_amendment_notes));

  return jsonb_build_object('review_id', p_review_id, 'decision', p_decision, 'engagement_id', v_eng);
end;
$$;

-- Release: only possible against an approved review; the msp_release gate
-- trigger enforces this even if this function is bypassed.
create or replace function msp_release_pack(
  p_review_id uuid,
  p_docx_path text,
  p_pdf_path text,
  p_envelope_id text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng uuid;
  v_release uuid;
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'only forge_admin may release';
  end if;
  select engagement_id into v_eng from msp_omp_review where id = p_review_id;
  insert into msp_release (engagement_id, omp_review_id, docx_path, pdf_path, docuseal_envelope_id)
  values (v_eng, p_review_id, p_docx_path, p_pdf_path, p_envelope_id)
  returning id into v_release;
  update msp_engagement set status = 'released' where id = v_eng;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng, 'admin', 'release',
          jsonb_build_object('release_id', v_release, 'review_id', p_review_id,
                             'docx', p_docx_path, 'pdf', p_pdf_path));
  return v_release;
end;
$$;

-- Data subject access: everything held for an engagement, one JSON document.
create or replace function msp_engagement_export(p_engagement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'only forge_admin may export';
  end if;
  select jsonb_build_object(
    'engagement', (select to_jsonb(e) from msp_engagement e where e.id = p_engagement_id),
    'client', (select to_jsonb(c) from msp_client c join msp_engagement e on e.client_id = c.id where e.id = p_engagement_id),
    'intake', (select jsonb_agg(to_jsonb(i)) from msp_intake i where i.engagement_id = p_engagement_id),
    'sites', (select jsonb_agg(to_jsonb(s)) from msp_intake_site s join msp_intake i on i.id = s.intake_id where i.engagement_id = p_engagement_id),
    'job_categories', (select jsonb_agg(to_jsonb(j)) from msp_intake_job_category j join msp_intake i on i.id = j.intake_id where i.engagement_id = p_engagement_id),
    'exposures', (select jsonb_agg(to_jsonb(x)) from msp_intake_exposure x join msp_intake i on i.id = x.intake_id where i.engagement_id = p_engagement_id),
    'chemicals', (select jsonb_agg(to_jsonb(c)) from msp_intake_chemical c join msp_intake i on i.id = c.intake_id where i.engagement_id = p_engagement_id),
    'consents', (select jsonb_agg(to_jsonb(c)) from msp_consent c where c.engagement_id = p_engagement_id),
    'drafts', (select jsonb_agg(jsonb_build_object('stage', d.stage, 'schema_version', d.schema_version, 'created_at', d.created_at, 'stage_output', d.stage_output)) from msp_draft d where d.engagement_id = p_engagement_id),
    'reviews', (select jsonb_agg(to_jsonb(r)) from msp_omp_review r where r.engagement_id = p_engagement_id),
    'documents', (select jsonb_agg(to_jsonb(d)) from msp_document d where d.engagement_id = p_engagement_id),
    'audit', (select jsonb_agg(to_jsonb(a) order by a.id) from msp_audit a where a.engagement_id = p_engagement_id),
    'exported_at', now()
  ) into v;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (p_engagement_id, 'admin', 'export', jsonb_build_object('kind', 'data_subject_access_export'));
  return v;
end;
$$;

-- Erasure workflow. Occupational health records carry long statutory
-- retention (CR-12.4, open in the confirmation register), so erasure of an
-- engagement that has a released pack is refused unless the retention
-- override is explicitly asserted with a reason. Erasure removes intake
-- content and pseudonymises the client while keeping the audit skeleton and
-- consent records as proof of processing history.
create or replace function msp_engagement_erase(
  p_engagement_id uuid,
  p_reason text,
  p_retention_override boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_released int;
  v_client uuid;
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'only forge_admin may erase';
  end if;
  if coalesce(btrim(p_reason),'') = '' then
    raise exception 'an erasure requires a stated reason';
  end if;

  select count(*) into v_released from msp_release where engagement_id = p_engagement_id;
  if v_released > 0 and not p_retention_override then
    raise exception 'erasure refused: engagement has a released pack and occupational health records carry statutory retention (CR-12.4); assert the retention override only on documented legal advice';
  end if;

  select client_id into v_client from msp_engagement where id = p_engagement_id;
  if v_client is null then
    raise exception 'engagement % not found', p_engagement_id;
  end if;

  delete from msp_intake_site      where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  delete from msp_intake_job_category where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  delete from msp_intake_exposure  where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  delete from msp_intake_chemical  where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  delete from msp_intake_file      where intake_id in (select id from msp_intake where engagement_id = p_engagement_id);
  update msp_intake
     set raw_payload = jsonb_build_object('erased', true, 'erased_at', now(), 'reason', p_reason)
   where engagement_id = p_engagement_id;
  update msp_client
     set registered_name = 'ERASED ' || left(v_client::text, 8),
         trading_name = null, registration_number = null,
         vat_number = null, head_office_address = null
   where id = v_client;
  update msp_engagement set status = 'archived' where id = p_engagement_id;

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (p_engagement_id, 'admin', 'erasure',
          jsonb_build_object('reason', p_reason, 'retention_override', p_retention_override));

  return jsonb_build_object('engagement_id', p_engagement_id, 'erased', true);
end;
$$;

-- The review queue view for the interface: one row per undecided draft with
-- its OMP notes surfaced.
create or replace view msp_review_queue
with (security_invoker = on) as
select r.id as review_id, e.reference, c.registered_name as client,
       e.status, r.draft_id, d.stage_output -> 'omp_notes' as omp_notes,
       d.stage_output -> 'placeholders' as placeholders,
       e.created_at
  from msp_omp_review r
  join msp_engagement e on e.id = r.engagement_id
  join msp_client c on c.id = e.client_id
  join msp_draft d on d.id = r.draft_id
 where r.decision is null;

grant execute on function msp_omp_decide(uuid, text, text, text, jsonb) to authenticated;
grant execute on function msp_release_pack(uuid, text, text, text) to authenticated;
grant execute on function msp_engagement_export(uuid) to authenticated;
grant execute on function msp_engagement_erase(uuid, text, boolean) to authenticated;
revoke execute on function msp_omp_decide(uuid, text, text, text, jsonb) from anon, public;
revoke execute on function msp_release_pack(uuid, text, text, text) from anon, public;
revoke execute on function msp_engagement_export(uuid) from anon, public;
revoke execute on function msp_engagement_erase(uuid, text, boolean) from anon, public;


------------------------------------------------------------------------------
-- 009_msp_commercial_clinical.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | POP-OMP-01 v1.1.0, FRM-GATE-01 v1.0.0 | Clinical recommendations,
-- review signature, commercial gating, pricing, quotes, and revisions.
-- Phase 5B migration 009.

-- 1. Clinical recommendation area and signature on the review ------------------

create table msp_omp_recommendation (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references msp_omp_review(id),
  engagement_id uuid not null references msp_engagement(id),
  recommendation text not null,
  category text not null default 'general'
    check (category in ('general','controls','surveillance','referral_pathway','fit_testing','follow_up')),
  made_by text not null,
  hpcsa_number text,
  created_at timestamptz default now()
);
comment on table msp_omp_recommendation is 'The recommendation area: the reviewing health professional records recommendations against a draft without, or alongside, a decision. Recommendations are programme level and never name an individual or a diagnosis.';

alter table msp_omp_review
  add column if not exists signature_name text,
  add column if not exists signature_image text,
  add column if not exists signed_at timestamptz;
comment on column msp_omp_review.signature_image is 'Data URL of the drawn or typed signature applied in the review interface at decision time. The DocuSeal envelope remains the formal dual sign off channel for the released pack.';

alter table msp_omp_recommendation enable row level security;
create policy msp_omp_recommendation_read on msp_omp_recommendation
  for select to authenticated using (msp_any_forge_role());
create policy msp_omp_recommendation_write on msp_omp_recommendation
  for insert to authenticated with check (msp_has_role('forge_omp'));

create or replace function msp_omp_recommend(
  p_review_id uuid,
  p_recommendation text,
  p_category text,
  p_made_by text,
  p_hpcsa_number text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng uuid; v_id uuid;
begin
  if not msp_caller_is('forge_omp') then
    raise exception 'only the reviewing health professional may record a recommendation';
  end if;
  if coalesce(btrim(p_recommendation),'') = '' or coalesce(btrim(p_made_by),'') = '' then
    raise exception 'a recommendation requires text and the professional''s name';
  end if;
  select engagement_id into v_eng from msp_omp_review where id = p_review_id;
  if v_eng is null then raise exception 'review % not found', p_review_id; end if;
  insert into msp_omp_recommendation (review_id, engagement_id, recommendation, category, made_by, hpcsa_number)
  values (p_review_id, p_recommendation, coalesce(nullif(p_category,''),'general'), p_made_by, p_hpcsa_number)
  returning id into v_id;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng, 'omp:' || p_made_by, 'omp_recommendation',
          jsonb_build_object('review_id', p_review_id, 'recommendation_id', v_id, 'category', p_category));
  return v_id;
end;
$$;
grant execute on function msp_omp_recommend(uuid, text, text, text, text) to authenticated;
revoke execute on function msp_omp_recommend(uuid, text, text, text, text) from anon, public;

create or replace function msp_omp_sign(
  p_review_id uuid,
  p_signature_name text,
  p_signature_image text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_eng uuid;
begin
  if not msp_caller_is('forge_omp') then
    raise exception 'only the reviewing health professional may sign';
  end if;
  update msp_omp_review
     set signature_name = p_signature_name, signature_image = p_signature_image, signed_at = now()
   where id = p_review_id
   returning engagement_id into v_eng;
  if v_eng is null then raise exception 'review % not found', p_review_id; end if;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng, 'omp:' || p_signature_name, 'omp_signature_applied',
          jsonb_build_object('review_id', p_review_id));
end;
$$;
grant execute on function msp_omp_sign(uuid, text, text) to authenticated;
revoke execute on function msp_omp_sign(uuid, text, text) from anon, public;

-- 2. Client accounts and the approval gate -------------------------------------

create table msp_client_account (
  id uuid primary key default gen_random_uuid(),
  company_name text not null,
  contact_name text not null,
  contact_email text not null,
  account_kind text not null default 'applicant'
    check (account_kind in ('applicant','approved_client','declined')),
  approved_by text,
  approved_at timestamptz,
  notes text,
  created_at timestamptz default now()
);
comment on table msp_client_account is 'Landing page sign on. An approved CNC client receives the assessment as a client benefit; everyone else follows the quote and payment path.';

alter table msp_client_account enable row level security;
create policy msp_client_account_read on msp_client_account
  for select to authenticated using (msp_has_role('forge_admin'));
create policy msp_client_account_update on msp_client_account
  for update to authenticated using (msp_has_role('forge_admin'));

-- 3. Pricing and quotes --------------------------------------------------------

create table msp_pricing (
  id uuid primary key default gen_random_uuid(),
  industry_code text not null references msp_industry(code),
  base_fee_zar numeric not null,
  per_employee_zar numeric not null,
  per_job_category_zar numeric not null,
  status text not null default 'placeholder' check (status in ('placeholder','confirmed')),
  effective_from date default current_date,
  unique (industry_code, effective_from)
);
comment on table msp_pricing is 'Industry rate card. Rows carry status placeholder until CNC confirms commercial rates (CR-13.14); a placeholder priced quote is always marked indicative.';

create table msp_quote (
  id uuid primary key default gen_random_uuid(),
  quote_reference text unique not null,
  company_name text not null,
  contact_name text not null,
  contact_email text not null,
  industry_code text not null,
  company_size text,
  employee_count int not null,
  job_category_count int not null,
  price_zar numeric not null,
  price_status text not null check (price_status in ('indicative','firm')),
  status text not null default 'quoted'
    check (status in ('quoted','accepted','paid','expired','waived_client_benefit')),
  payment_reference text,
  created_at timestamptz default now(),
  valid_until date default current_date + 30
);

alter table msp_pricing enable row level security;
alter table msp_quote enable row level security;
create policy msp_pricing_read on msp_pricing
  for select to authenticated using (msp_any_forge_role());
create policy msp_pricing_write on msp_pricing
  for insert to authenticated with check (msp_has_role('forge_admin'));
create policy msp_pricing_update on msp_pricing
  for update to authenticated using (msp_has_role('forge_admin'));
create policy msp_quote_read on msp_quote
  for select to authenticated using (msp_has_role('forge_admin'));
create policy msp_quote_update on msp_quote
  for update to authenticated using (msp_has_role('forge_admin'));

create sequence if not exists msp_quote_seq;

create or replace function msp_create_quote(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate msp_pricing%rowtype;
  v_price numeric;
  v_ref text;
  v_id uuid;
  v_emp int := coalesce((p->>'employee_count')::int, 0);
  v_jobs int := coalesce((p->>'job_category_count')::int, 0);
begin
  if coalesce(p->>'company_name','') = '' or coalesce(p->>'contact_email','') = '' then
    raise exception 'company name and contact email are required';
  end if;
  if v_emp < 1 or v_jobs < 1 then
    raise exception 'employee count and job category count must be at least one';
  end if;
  select * into v_rate from msp_pricing
   where industry_code = upper(p->>'industry_code')
   order by effective_from desc limit 1;
  if v_rate.id is null then
    raise exception 'no rate card for industry %; the quote routes to a consultant', p->>'industry_code';
  end if;
  v_price := v_rate.base_fee_zar + v_rate.per_employee_zar * v_emp + v_rate.per_job_category_zar * v_jobs;
  v_ref := 'CNC-QTE-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(nextval('msp_quote_seq')::text, 3, '0');
  insert into msp_quote (quote_reference, company_name, contact_name, contact_email,
                         industry_code, company_size, employee_count, job_category_count,
                         price_zar, price_status)
  values (v_ref, p->>'company_name', coalesce(p->>'contact_name',''), p->>'contact_email',
          upper(p->>'industry_code'), p->>'company_size', v_emp, v_jobs,
          v_price, case when v_rate.status = 'confirmed' then 'firm' else 'indicative' end)
  returning id into v_id;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (null, 'webhook', 'quote_created',
          jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'price_zar', v_price,
                             'price_status', case when v_rate.status = 'confirmed' then 'firm' else 'indicative' end));
  return jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'price_zar', v_price,
                            'price_status', case when v_rate.status = 'confirmed' then 'firm' else 'indicative' end,
                            'valid_until', current_date + 30);
end;
$$;
revoke execute on function msp_create_quote(jsonb) from public, anon, authenticated;

-- 4. Form access tokens --------------------------------------------------------

create table msp_form_access (
  id uuid primary key default gen_random_uuid(),
  token text unique not null default encode(extensions.gen_random_bytes(24), 'hex'),
  granted_via text not null check (granted_via in ('approved_client','paid_quote','manual')),
  quote_id uuid references msp_quote(id),
  client_account_id uuid references msp_client_account(id),
  company_name text not null,
  used_by_intake uuid references msp_intake(id),
  expires_at timestamptz not null default now() + interval '60 days',
  created_at timestamptz default now()
);
comment on table msp_form_access is 'One token, one assessment. Issued on client approval or on payment confirmation; consumed by the intake that uses it.';

alter table msp_form_access enable row level security;
create policy msp_form_access_read on msp_form_access
  for select to authenticated using (msp_has_role('forge_admin'));

create or replace function msp_grant_access(
  p_granted_via text,
  p_company_name text,
  p_quote_id uuid default null,
  p_client_account_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_token text; v_id uuid;
begin
  insert into msp_form_access (granted_via, company_name, quote_id, client_account_id)
  values (p_granted_via, p_company_name, p_quote_id, p_client_account_id)
  returning id, token into v_id, v_token;
  if p_quote_id is not null then
    update msp_quote set status = 'paid' where id = p_quote_id and status in ('quoted','accepted');
  end if;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (null, 'system', 'form_access_granted',
          jsonb_build_object('access_id', v_id, 'granted_via', p_granted_via, 'company', p_company_name));
  return jsonb_build_object('access_id', v_id, 'token', v_token);
end;
$$;
revoke execute on function msp_grant_access(text, text, uuid, uuid) from public, anon, authenticated;

create or replace function msp_check_access(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v msp_form_access%rowtype;
begin
  select * into v from msp_form_access where token = p_token;
  if v.id is null then return jsonb_build_object('valid', false, 'reason', 'unknown token'); end if;
  if v.used_by_intake is not null then return jsonb_build_object('valid', false, 'reason', 'token already used'); end if;
  if v.expires_at < now() then return jsonb_build_object('valid', false, 'reason', 'token expired'); end if;
  return jsonb_build_object('valid', true, 'company_name', v.company_name, 'access_id', v.id);
end;
$$;
revoke execute on function msp_check_access(text) from public, anon, authenticated;

-- 5. Revisions -----------------------------------------------------------------

alter table msp_engagement add column if not exists revision int not null default 1;
comment on column msp_engagement.revision is 'Pack revision number. A change notification or updated risk assessment increments the revision; every render records its revision in msp_document.version and the reference carries Rev N from revision 2 onward. Secure hosting of released revisions in MyClinicOnline awaits the MCO integration (CR-13.12).';

-- 6. Placeholder rate card and register items ----------------------------------

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status)
values ('CONSTR', 4500, 35, 450, 'placeholder');

insert into msp_confirmation_item (item_code, kind, description, status) values
('CR-13.12', 'confirm', 'MyClinicOnline integration: API or filing mechanism for hosting released packs and revisions in MCO, and for surfacing the review interface link per company inside the MCO application.', 'open'),
('CR-13.13', 'confirm', 'Payment gateway selection and credentials for the quote path (the host platform ah_payment table is gateway agnostic, Peach referenced). Until wired, payment confirmation is a manual forge_admin action.', 'open'),
('CR-13.14', 'confirm', 'CNC commercial rate card per industry. The seeded Construction row (R4,500 base, R35 per employee, R450 per job category) is a PLACEHOLDER; every quote priced from it is marked indicative and states so.', 'open');


------------------------------------------------------------------------------
-- 010_msp_batch_manufacturing.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | TAX-BAT-01 v1.0.0 | Phase 6 batch 1: Manufacturing
-- Documentary verification 13/08/2026, subject to OMP ratification. The batch
-- gate at the end of this migration enables selectable subindustries only
-- where the role, hazard, and protocol map is structurally complete, and
-- fails the migration loudly otherwise.

-- 1. Newly verified instruments -------------------------------------------------

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('HBA Regulations, 2022',
 'Regulations for Hazardous Biological Agents, 2022, GN R.1887 of 16 March 2022, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.1887, 16 March 2022', '2022-03-16',
 'In force August 2026. Requires a documented medical surveillance system overseen by an occupational health practitioner where the HBA risk assessment indicates exposure risk with an identifiable disease or effect and a detection technique; all tests per a written medical protocol.',
 'GN R.1887 regulation text, lawlibrary.org.za akn/za/act/gn/2022/r1887 and SAFLII consolidated',
 'Bowmans regulatory analysis and Occupational Health Southern Africa journal review of the 2022 HBA Regulations',
 'Currency check 13/08/2026: in force, no amendment located',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('Lead Regulations, 2001',
 'Lead Regulations, 2001, GN R.236, Government Gazette 23175, 28 February 2002, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.236, GG 23175', '2002-02-28',
 'In force August 2026. Airborne occupational exposure limit for lead 0.15 mg per cubic metre. Medical surveillance with biological monitoring: medical removal at a blood lead of 60 micrograms per decilitre (or 10 micrograms ZPP per gram haemoglobin); for women capable of procreation, removal at 40 and return at 30 micrograms per decilitre.',
 'Consolidated regulation text, SAFLII lr2001148',
 'University occupational medicine teaching note on the Lead Regulations and pathology practice guidance on occupational lead exposure surveillance',
 'Currency check 13/08/2026: in force, no amendment located; reference values corroborated across sources',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('Asbestos Abatement Regulations, 2020',
 'Asbestos Abatement Regulations, 2020, GN R.1196, Government Gazette 43893, 10 November 2020, as amended by GN R.11435, Government Gazette 46380, 20 May 2022, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.1196, GG 43893; amended GN R.11435, GG 46380', '2020-11-10',
 'In force August 2026 as amended 2022. Governs identification, inventory, risk assessment, management plans, notification, and control of asbestos work, with medical surveillance duties for exposed employees.',
 'GN R.1196 gazette text, Department of Employment and Labour published PDF and lawlibrary.org.za akn/za/act/gn/2020/r1196',
 'SAIOSH regulatory notice on the 2020 Regulations and practitioner analyses of the 2022 amendment',
 'Currency check 13/08/2026: in force as amended 20/05/2022',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('FCD Act R638, 2018',
 'Foodstuffs, Cosmetics and Disinfectants Act 54 of 1972, read with the Regulations Governing General Hygiene Requirements for Food Premises, the Transport of Food and Related Matters, GN R.638 of 22 June 2018',
 'regulation', 'GN R.638, 22 June 2018', '2018-06-22',
 'In force August 2026, having replaced R.962. Requires a Certificate of Acceptability for food premises, a person in charge, and trained food handlers, and excludes persons with specified communicable conditions from handling food. The food handler fitness assessment in this kernel serves that exclusion; R.638 prescribes condition based exclusion rather than a fixed certificate interval, so the annual interval is the house floor, not a statutory citation.',
 'GN R.638 regulation text, Department of Health published PDF and gov.za notice',
 'FAO legislative database record and food safety compliance practitioner guidance on R.638',
 'Currency check 13/08/2026: in force, national hygiene standard for food premises',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('Environmental Regulations for Workplaces, 1987',
 'Environmental Regulations for Workplaces, 1987, GN R.2281 of 16 October 1987, made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.2281, 16 October 1987', '1987-10-16',
 'In force August 2026. Regulation 2(4): the time weighted average WBGT index shall not exceed 30. Regulation 5(4): where the average WBGT index exceeds 30, workers must be certified fit for work in hot environments, with acclimatisation, hydration, training, and first aid duties on the employer.',
 'GN R.2281 regulation text, SAFLII erfw428 and lawlibrary.org.za akn/za/act/gn/1987/r2281',
 'Department of Employment and Labour published regulation and university occupational hygiene teaching material on heat stress evaluation',
 'Currency check 13/08/2026: in force, no repeal located; the Physical Agents Regulations, 2024 remain staged pending verification of any overlap',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- 2. Hazard upgrades from the verification pass ---------------------------------

update msp_hazard
   set oel_value = 30, oel_unit = 'WBGT index', oel_basis = 'time weighted average WBGT index, regulation 2(4)',
       oel_instrument = 'Environmental Regulations for Workplaces, 1987, GN R.2281; fitness certification for hot work per regulation 5(4)',
       verification_status = 'verified'
 where code = 'H';

insert into msp_hazard (code, name, category, oel_value, oel_unit, oel_basis, oel_instrument, verification_status)
values ('C-PB', 'Lead and inorganic lead compounds', 'chemical', 0.15, 'mg/m3',
        '8 hour time weighted average, Lead Regulations occupational exposure limit',
        'Lead Regulations, 2001, GN R.236', 'verified');

-- 3. New test protocols ---------------------------------------------------------

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id, p.test_name, p.test_type, true, 12, true, p.triggers, p.bio_ref, li.id
from (values
  ('D', 'Food handler fitness assessment', 'clinical',
   'Food handling duties. Serves the communicable condition exclusion under R.638: a person with a specified communicable condition, sores, or discharging lesions must not handle food. Annual interval is the house floor; exclusion applies immediately on presentation.',
   null, 'FCD Act R638, 2018'),
  ('D', 'Occupational biological agent surveillance per written medical protocol', 'clinical',
   'Where the HBA risk assessment indicates exposure risk with an identifiable disease or effect and a detection technique, per the 2022 Regulations; battery set by the OMP protocol.',
   null, 'HBA Regulations, 2022'),
  ('C-PB', 'Blood lead biological monitoring', 'biological_monitoring',
   'All lead exposed employees per the Lead Regulations. Medical removal and return per the verified reference values; women capable of procreation carry the lower removal threshold.',
   'Verified per the Lead Regulations, 2001: medical removal at blood lead 60 micrograms per decilitre (or 10 micrograms ZPP per gram haemoglobin); for women capable of procreation, removal at 40 and return at 30 micrograms per decilitre. Application per individual is the OMP''s clinical determination.',
   'Lead Regulations, 2001'),
  ('C-PB', 'Lead exposure clinical examination (neurological, renal, haematological screen)', 'clinical',
   'All lead exposed employees per the Lead Regulations, alongside blood lead monitoring.',
   null, 'Lead Regulations, 2001')
) as p(hazard_code, test_name, test_type, triggers, bio_ref, basis_short_name)
join msp_hazard h on h.code = p.hazard_code
join msp_legal_instrument li on li.short_name = p.basis_short_name and li.status = 'verified';

-- The heat protocol gains its verified statutory basis.
update msp_test_protocol
   set legal_basis_id = (select id from msp_legal_instrument where short_name = 'Environmental Regulations for Workplaces, 1987'),
       trigger_conditions = 'Work in environments where the time weighted average WBGT index approaches or exceeds 30, per regulations 2(4) and 5(4): fitness certification for hot work, with acclimatisation and hydration duties on the employer. Cold chain work is assessed under the same thermal stress battery.'
 where test_name = 'Heat stress tolerance assessment';

-- 4. Manufacturing taxonomy -----------------------------------------------------

insert into msp_industry (code, name, sic_reference, regulatory_regime)
values ('MANU', 'Manufacturing', 'SIC major division 3, Manufacturing', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i,
     (values
       ('MANU-FOOD',    'Food and beverage manufacturing', 'Batch 1 role map seeded; gate check below'),
       ('MANU-METAL',   'Metals and foundries',            'Batch 1 role map seeded; gate check below'),
       ('MANU-CHEM',    'Chemical manufacturing',          'Role map in a later batch'),
       ('MANU-AUTO',    'Automotive manufacturing',        'Role map in a later batch'),
       ('MANU-TEX',     'Textiles',                        'Role map in a later batch'),
       ('MANU-PLASTIC', 'Plastics',                        'Role map in a later batch'),
       ('MANU-WOOD',    'Wood and furniture',              'Role map in a later batch')
     ) as s(code, name, notes)
where i.code = 'MANU';

-- Food and beverage roles
insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Production Line Operator', 'Operating and monitoring processing and packaging lines', 'Standing for full shifts, repetitive upper limb work', 'Sustained attention, line speed vigilance', 'None beyond induction and food safety training'),
       ('Food Handler / Process Worker', 'Direct handling of ingredients and product', 'Standing, repetitive handling, wet work', 'Hygiene discipline, instruction following', 'Food handler training per R.638'),
       ('Cold Chain / Freezer Worker', 'Work in chillers and freezer stores', 'Cold tolerance, manual handling in low temperatures', 'Instruction following under thermal stress', 'None beyond induction'),
       ('Boiler and Utilities Operator', 'Operating steam boilers, compressors, and plant utilities', 'Heat exposure, plant room access, occasional confined entry', 'Gauge and alarm vigilance', 'Boiler attendance certification as applicable'),
       ('Hygiene and Sanitation Worker', 'Cleaning and sanitising plant with detergents and disinfectants', 'Manual work with chemical handling, wet work', 'Chemical handling discipline', 'None beyond induction and chemical handling training'),
       ('Forklift and Warehouse Operator', 'Materials movement by forklift and pallet truck in stores and yards', 'Prolonged sitting, mounting and dismounting', 'Depth perception, sustained visual attention, no uncontrolled hypoglycaemic risk', 'Forklift operator certification'),
       ('Maintenance Artisan', 'Mechanical and electrical maintenance across the plant', 'Awkward postures, work at height, tool vibration', 'Fine motor control, fault diagnosis', 'Trade certification; wireman''s licence where applicable'),
       ('Shift Supervisor', 'Supervision of production shifts including night shift', 'Walking the floor for full shifts', 'Sustained attention, decision making under pressure', 'None beyond induction')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'MANU-FOOD';

-- Metals and foundries roles
insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Furnace Operator', 'Operating melting and heat treatment furnaces', 'Sustained hot work, heavy manual tasks', 'Vigilance near molten metal, heat discipline', 'Furnace operation competency'),
       ('Foundry Moulder and Caster', 'Sand moulding, pouring, and casting', 'Heavy manual handling in heat and dust', 'Coordination during pours', 'None beyond induction'),
       ('Welder and Fabricator', 'Welding and fabricating steel product', 'Sustained awkward postures, fine motor control', 'Colour vision for weld inspection, attention near arc', 'Trade certification as applicable'),
       ('Machinist', 'Operating lathes, mills, and CNC machines with cutting fluids', 'Standing, repetitive setup work', 'Precision, measurement discipline', 'Trade or operator certification'),
       ('Smelter and Battery Plant Worker', 'Lead smelting, refining, or battery manufacture', 'Heavy manual work in heat with lead exposure', 'Hygiene discipline for lead control', 'None beyond induction and lead awareness training'),
       ('Grinder and Finisher', 'Fettling, grinding, and finishing castings', 'Vibrating tool work, dust exposure', 'Sustained attention with PPE burden', 'None beyond induction'),
       ('Overhead Crane Operator', 'Operating overhead and gantry cranes', 'Cab access climbing, sustained sitting', 'Depth perception, load judgement, no uncontrolled hypoglycaemic risk', 'Crane operator certification'),
       ('Production Supervisor', 'Supervision of foundry and machine shop production', 'Walking the floor, occasional hot area entry', 'Sustained attention, incident response', 'None beyond induction')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'MANU-METAL';

-- Job to hazard maps
insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('MANU-FOOD', 'Production Line Operator', 'A', 'Moderate', 'Packaging and processing line noise'),
  ('MANU-FOOD', 'Production Line Operator', 'I', 'Moderate', 'Repetitive upper limb work at line speed'),
  ('MANU-FOOD', 'Production Line Operator', 'K', 'Moderate', 'Rotating shifts in continuous production'),
  ('MANU-FOOD', 'Food Handler / Process Worker', 'D', 'Moderate', 'Direct food handling; communicable condition exclusion applies'),
  ('MANU-FOOD', 'Food Handler / Process Worker', 'I', 'Moderate', 'Repetitive handling and wet work'),
  ('MANU-FOOD', 'Food Handler / Process Worker', 'C', 'Low', 'Sanitiser and detergent contact'),
  ('MANU-FOOD', 'Cold Chain / Freezer Worker', 'H', 'Moderate', 'Thermal stress in chillers and freezer stores'),
  ('MANU-FOOD', 'Cold Chain / Freezer Worker', 'I', 'Moderate', 'Manual handling in low temperatures'),
  ('MANU-FOOD', 'Boiler and Utilities Operator', 'H', 'Moderate', 'Boiler house heat'),
  ('MANU-FOOD', 'Boiler and Utilities Operator', 'A', 'Moderate', 'Plant room noise'),
  ('MANU-FOOD', 'Boiler and Utilities Operator', 'F', 'Low', 'Occasional confined entry to plant'),
  ('MANU-FOOD', 'Hygiene and Sanitation Worker', 'C', 'Moderate', 'Detergent, sanitiser, and disinfectant handling'),
  ('MANU-FOOD', 'Hygiene and Sanitation Worker', 'D', 'Moderate', 'Cleaning of soiled areas and drains'),
  ('MANU-FOOD', 'Hygiene and Sanitation Worker', 'I', 'Moderate', 'Manual cleaning work'),
  ('MANU-FOOD', 'Forklift and Warehouse Operator', 'J', 'Moderate', 'Forklift operation; site driving fitness'),
  ('MANU-FOOD', 'Forklift and Warehouse Operator', 'G', 'Low', 'Whole body vibration on industrial floors'),
  ('MANU-FOOD', 'Maintenance Artisan', 'A', 'Moderate', 'Plant and tool noise'),
  ('MANU-FOOD', 'Maintenance Artisan', 'G', 'Moderate', 'Hand tool vibration'),
  ('MANU-FOOD', 'Maintenance Artisan', 'M', 'Moderate', 'Electrical maintenance'),
  ('MANU-FOOD', 'Maintenance Artisan', 'E', 'Low', 'Occasional work at height'),
  ('MANU-FOOD', 'Shift Supervisor', 'K', 'Moderate', 'Night shift supervision'),
  ('MANU-FOOD', 'Shift Supervisor', 'A', 'Low', 'Floor noise during supervision'),
  ('MANU-METAL', 'Furnace Operator', 'H', 'High', 'Sustained hot work at melting and heat treatment furnaces'),
  ('MANU-METAL', 'Furnace Operator', 'A', 'High', 'Furnace and plant noise'),
  ('MANU-METAL', 'Furnace Operator', 'C', 'Moderate', 'Metal fume exposure'),
  ('MANU-METAL', 'Foundry Moulder and Caster', 'B', 'High', 'Foundry sand: respirable crystalline silica'),
  ('MANU-METAL', 'Foundry Moulder and Caster', 'H', 'High', 'Radiant heat during pours'),
  ('MANU-METAL', 'Foundry Moulder and Caster', 'I', 'Moderate', 'Heavy manual handling'),
  ('MANU-METAL', 'Welder and Fabricator', 'C', 'High', 'Welding fume including metal oxides'),
  ('MANU-METAL', 'Welder and Fabricator', 'L', 'Moderate', 'Ultraviolet radiation from arc welding'),
  ('MANU-METAL', 'Welder and Fabricator', 'A', 'Moderate', 'Fabrication noise'),
  ('MANU-METAL', 'Machinist', 'C', 'Moderate', 'Cutting fluid mist and skin contact'),
  ('MANU-METAL', 'Machinist', 'A', 'Moderate', 'Machine shop noise'),
  ('MANU-METAL', 'Machinist', 'I', 'Moderate', 'Repetitive setup and standing work'),
  ('MANU-METAL', 'Smelter and Battery Plant Worker', 'C-PB', 'High', 'Lead exposure in smelting, refining, or battery manufacture'),
  ('MANU-METAL', 'Smelter and Battery Plant Worker', 'H', 'High', 'Smelter heat'),
  ('MANU-METAL', 'Smelter and Battery Plant Worker', 'A', 'Moderate', 'Plant noise'),
  ('MANU-METAL', 'Grinder and Finisher', 'A', 'High', 'Grinding and fettling noise'),
  ('MANU-METAL', 'Grinder and Finisher', 'G', 'High', 'Vibrating tool work'),
  ('MANU-METAL', 'Grinder and Finisher', 'B', 'Moderate', 'Casting dust during fettling'),
  ('MANU-METAL', 'Overhead Crane Operator', 'J', 'Moderate', 'Crane operation; load and depth judgement'),
  ('MANU-METAL', 'Overhead Crane Operator', 'A', 'Moderate', 'Overhead plant noise'),
  ('MANU-METAL', 'Production Supervisor', 'A', 'Moderate', 'Floor noise during supervision'),
  ('MANU-METAL', 'Production Supervisor', 'H', 'Low', 'Occasional hot area entry'),
  ('MANU-METAL', 'Production Supervisor', 'B', 'Low', 'Incidental foundry dust')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

-- 5. Building construction: clone the verified civils role family ----------------

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select b.id, r.title, r.duties_summary, r.inherent_physical_demands,
       r.inherent_sensory_cognitive_demands, r.statutory_competency_requirement
from msp_job_role r
join msp_subindustry c on c.id = r.subindustry_id and c.code = 'CONSTR-CIVILS'
join msp_subindustry b on b.code = 'CONSTR-BUILD';

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select nb.id, jh.hazard_id, jh.typical_exposure_rating, jh.rationale
from msp_job_hazard jh
join msp_job_role rc on rc.id = jh.job_role_id
join msp_subindustry c on c.id = rc.subindustry_id and c.code = 'CONSTR-CIVILS'
join msp_subindustry b on b.code = 'CONSTR-BUILD'
join msp_job_role nb on nb.subindustry_id = b.id and nb.title = rc.title;

-- 6. Industry to instrument map for Manufacturing --------------------------------

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('OHS Act', 'Framework Act for all manufacturing workplaces'),
  ('HCA Regulations, 2021', 'Chemical agents across processing, cleaning, cutting fluids, fume, and dust'),
  ('NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026'),
  ('Noise Exposure Regulations, 2024', 'Successor noise instrument, sole operative instrument from 06/09/2026'),
  ('Ergonomics Regulations, 2019', 'Line work, manual handling, and repetitive strain surveillance'),
  ('Environmental Regulations for Workplaces, 1987', 'Thermal stress: WBGT limit and hot work fitness certification; applied to cold chain work by the same battery'),
  ('HBA Regulations, 2022', 'Biological agents in food handling, sanitation, and effluent areas'),
  ('FCD Act R638, 2018', 'Food handler exclusion and hygiene duties in food and beverage manufacturing'),
  ('Lead Regulations, 2001', 'Lead exposed processes: smelting, refining, battery manufacture; blood lead surveillance with verified removal values'),
  ('Asbestos Abatement Regulations, 2020', 'Legacy asbestos in older plant and buildings; applies on identification per the inventory and management plan duties'),
  ('COIDA', 'Compensation route for all manufacturing occupational injuries and diseases'),
  ('EEA section 7', 'Lawful basis for every medical test, justified against the inherent requirements of each job'),
  ('BCEA night work Code', 'Continuous production shifts and night work medicals'),
  ('NRTA PrDP medical', 'Professional driving categories where public road driving applies'),
  ('HPCSA Booklet 1', 'Ethical baseline for all examinations under the programme'),
  ('HPCSA Booklet 10', 'Governs any telehealth component of the programme'),
  ('HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(short_name, note) on true
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
where i.code = 'MANU';

-- 7. Pricing placeholder for Manufacturing (CR-13.14 remains open) ---------------

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status)
values ('MANU', 4500, 35, 450, 'placeholder');

-- 8. Batch gate: enable only structurally complete subindustries -----------------

do $$
declare
  v_code text;
  v_roles int;
  v_unmapped int;
  v_unprotocolled int;
begin
  for v_code in select unnest(array['MANU-FOOD','MANU-METAL','CONSTR-BUILD']) loop
    select count(*) into v_roles
      from msp_job_role r join msp_subindustry s on s.id = r.subindustry_id
     where s.code = v_code;
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
    if v_roles < 5 then
      raise exception 'batch gate: % has only % roles (minimum 5)', v_code, v_roles;
    end if;
    if v_unmapped > 0 then
      raise exception 'batch gate: % has % roles without a hazard map', v_code, v_unmapped;
    end if;
    if v_unprotocolled > 0 then
      raise exception 'batch gate: % uses % hazard codes without any test protocol', v_code, v_unprotocolled;
    end if;
    update msp_subindustry set selectable = true where code = v_code;
    raise notice 'batch gate: % enabled (% roles, complete maps)', v_code, v_roles;
  end loop;
end $$;

-- 9. Register updates ------------------------------------------------------------

update msp_confirmation_item
   set description = description || ' Update 13/08/2026: lead OEL 0.15 mg/m3, blood lead removal values, and the WBGT 30 limit verified; noise, silica, lead, and WBGT now carry verified values. All other OELs remain open.'
 where item_code = 'CR-12.1';

update msp_confirmation_item
   set description = description || ' Update 13/08/2026: Driven Machinery Regulations medical fitness provision could not be corroborated in the documentary pass; DMR stays pending and uncitable. Lifting operator medicals rest on EEA section 7 inherent requirements and the house floor meanwhile.'
 where item_code = 'CR-13.9';


------------------------------------------------------------------------------
-- 011_msp_batch_mining.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | TAX-BAT-02 v1.0.0 | Phase 6 batch 2: Mining
-- The MHSA regime enters the kernel: statutory fitness to perform work,
-- ODMWA compensation routing for mining lung disease, and the first
-- subindustries under the DUAL compensation logic. Documentary verification
-- 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('MHSA',
 'Mine Health and Safety Act 29 of 1996, section 13 medical surveillance provisions',
 'act', null, '1997-01-15',
 'In force August 2026. Section 13: the employer must establish and maintain a system of medical surveillance of employees exposed to health hazards, consisting of an initial medical examination and further examinations at appropriate intervals; persons working at a mine must be declared medically fit before performing work.',
 'Consolidated Act text, SAFLII mhasa1996192 and the Mine Health and Safety Council published Act and Regulations booklet',
 'DMRE published guidance and university occupational health teaching material on MHSA medical surveillance',
 'Currency check 13/08/2026: in force, administered by the DMRE; no repeal located',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('Fitness to Perform Work Guideline (MHSA)',
 'Guideline for the Compilation of a Mandatory Code of Practice on the Minimum Standards of Fitness to Perform Work at a Mine, GN R.147, Government Gazette 39656, 5 February 2016, effective 30 June 2016, DMRE reference DMR 16/3/2/3-A3',
 'guideline', 'GN R.147, GG 39656; DMR 16/3/2/3-A3', '2016-06-30',
 'First issued 1 March 2003, last revised 30 June 2013, gazetted 5 February 2016 with effect from 30 June 2016. Guides Occupational Medical Practitioners in determining fitness to perform specified work at a mine; every mine must compile its mandatory Code of Practice on these minimum standards.',
 'DMRE published guideline PDF, dmre.gov.za mandatory Codes of Practice resource centre',
 'gov.za gazette notice record and industry mandatory Code of Practice registers referencing the guideline',
 'Currency check 13/08/2026: effective instrument for mandatory Codes of Practice on fitness to perform work; no successor located',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified'),

('ODMWA',
 'Occupational Diseases in Mines and Works Act 78 of 1973',
 'act', null, '1973-10-01',
 'In force August 2026, last substantively amended 1994 and further amended by the National Health Insurance Act 20 of 2023 (currency watch). Administered by the Medical Bureau for Occupational Diseases under the Department of Health: certification of compensable cardio respiratory organ disease in miners and ex miners, benefit medical examinations (two yearly for ex miners at accredited facilities), and lump sum compensation by degree of impairment. Mining lung disease routes here; all other conditions route to COIDA.',
 'Consolidated Act text, SAFLII odimawa1973385 and gov.za Act record',
 'NICD compensation systems guidance and the occupational lung disease collaboration compensation framework material on MBOD benefit examinations',
 'Currency check 13/08/2026: in force; NHI Act 20 of 2023 amendment recorded for review at the next verification cycle',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-02-13', 'verified');

-- Statutory mine fitness as a mapped hazard so every mining role composes the
-- certificate of fitness battery through the existing engine.
insert into msp_hazard (code, name, category, oel_value, oel_unit, oel_basis, oel_instrument, verification_status)
values ('Q', 'Statutory fitness to perform work at a mine', 'physical', null, null,
        'Not an exposure limit: a statutory fitness determination under MHSA section 13 and the mine''s mandatory Code of Practice',
        'Mine Health and Safety Act 29 of 1996 section 13; Fitness to Perform Work Guideline, GN R.147',
        'unverified');

insert into msp_test_protocol
  (hazard_id, test_name, test_type, baseline_required, periodic_interval_months,
   exit_required, trigger_conditions, biological_reference, legal_basis_id)
select h.id, p.test_name, 'clinical', true, 12, true, p.triggers, null, li.id
from (values
  ('Q', 'Mine certificate of fitness examination (initial, periodic, and exit per the mandatory Code of Practice)',
   'All persons performing work at a mine, per MHSA section 13 and the mine''s mandatory Code of Practice on minimum standards of fitness. Initial examination and fitness declaration before work begins; periodic at least annually; exit examination on termination of service at the mine.',
   'Fitness to Perform Work Guideline (MHSA)'),
  ('B', 'ODMWA benefit examination battery: chest X-ray with lung function for dust exposed mine workers',
   'Dust exposed mine workers under the ODMWA certification system. In service surveillance at least annually; on exit, the benefit examination record supports MBOD certification, and ex miners remain entitled to two yearly benefit medical examinations at accredited facilities.',
   'ODMWA'),
  ('H', 'Heat tolerance screening for hot underground workings',
   'Underground work in hot workings per the mine''s thermal management programme and mandatory Code of Practice; screening and acclimatisation before placement in hot workings and on return after absence.',
   'MHSA')
) as p(hazard_code, test_name, triggers, basis_short_name)
join msp_hazard h on h.code = p.hazard_code
join msp_legal_instrument li on li.short_name = p.basis_short_name and li.status = 'verified';

insert into msp_industry (code, name, sic_reference, regulatory_regime)
values ('MINING', 'Mining', 'SIC major division 2, Mining and quarrying', 'MHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i,
     (values
       ('MIN-GOLD',    'Gold mining',        'Batch 2 role map seeded; gate check below'),
       ('MIN-QUARRY',  'Quarrying',          'Batch 2 role map seeded; gate check below'),
       ('MIN-PLAT',    'Platinum mining',    'Role map in a later batch'),
       ('MIN-COAL',    'Coal mining',        'Role map in a later batch'),
       ('MIN-CHROME',  'Chrome mining',      'Role map in a later batch'),
       ('MIN-DIAMOND', 'Diamond mining',     'Role map in a later batch')
     ) as s(code, name, notes)
where i.code = 'MINING';

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Rock Drill Operator', 'Operating pneumatic and hydraulic rock drills at the face', 'Heavy sustained physical work in heat and confined stopes', 'Vigilance for ground conditions under noise and heat load', 'Mine certificate of fitness; heat tolerance clearance for hot workings'),
       ('Stoping and Development Crew', 'Face preparation, support installation, cleaning and sweeping', 'Heavy manual work in heat, awkward postures underground', 'Instruction following under demanding conditions', 'Mine certificate of fitness'),
       ('Winding Engine Driver', 'Operating the winder conveying persons and material', 'Sustained seated vigilance', 'Unimpaired vision and hearing, sustained concentration, no condition with sudden incapacity potential', 'Winding engine driver certificate; mine certificate of fitness'),
       ('LHD and Locomotive Operator', 'Operating load haul dump machines and underground locomotives', 'Whole body vibration, sustained operation underground', 'Depth perception, reaction time, no uncontrolled hypoglycaemic risk', 'Operator competency; mine certificate of fitness'),
       ('Shaft Timberman and Support Crew', 'Installing and maintaining shaft and excavation support', 'Climbing, rigging, heavy manual handling in shafts', 'Spatial awareness, no vertigo', 'Working at heights competency; mine certificate of fitness'),
       ('Underground Miner (blasting certificate)', 'Supervising the working place, charging up and blasting', 'Extensive underground travel, work in heat and dust', 'Judgement under pressure, gas testing vigilance', 'Blasting certificate; mine certificate of fitness'),
       ('Metallurgical Plant Operator', 'Operating surface gold plant including cyanidation circuits', 'Plant rounds, chemical handling', 'Chemical handling discipline, alarm response', 'Plant competency; mine certificate of fitness'),
       ('Occupational Hygiene Assistant', 'Dust, heat, and ventilation measurements underground', 'Extensive underground travel', 'Measurement discipline and recording accuracy', 'Mine certificate of fitness')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'MIN-GOLD';

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s,
     (values
       ('Quarry Supervisor', 'Supervision of quarry benches, plant, and loading operations', 'Walking benches and plant areas', 'Sustained attention, incident response', 'Mine certificate of fitness'),
       ('Blaster (surface)', 'Drilling pattern checks, charging, and surface blasting', 'Manual work on benches in weather', 'Judgement under pressure, exclusion discipline', 'Blasting certificate for surface excavations; mine certificate of fitness'),
       ('Drill Rig Operator', 'Operating production drill rigs on benches', 'Vibration, dust exposure at the collar', 'Sustained visual attention', 'Operator competency; mine certificate of fitness'),
       ('Excavator and Loader Operator', 'Loading blasted rock to trucks', 'Whole body vibration, prolonged sitting', 'Depth perception, load judgement', 'Operator competency; mine certificate of fitness'),
       ('Dump Truck Driver', 'Hauling rock from benches to the crusher', 'Prolonged sitting, mounting and dismounting', 'Sustained visual attention, reaction time, no uncontrolled hypoglycaemic risk', 'Operator competency; PrDP where public roads are used; mine certificate of fitness'),
       ('Crusher Plant Operator', 'Operating crushing and screening plant', 'Plant rounds with dust and noise exposure', 'Alarm vigilance, lockout discipline', 'Plant competency; mine certificate of fitness'),
       ('Workshop Artisan', 'Maintaining mobile plant and fixed equipment', 'Heavy component handling, tool vibration', 'Fine motor control, fault diagnosis', 'Trade certification; mine certificate of fitness')
     ) as r(title, duties, phys, sens, statreq)
where s.code = 'MIN-QUARRY';

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('MIN-GOLD', 'Rock Drill Operator', 'B', 'High', 'Silica bearing rock dust at the face'),
  ('MIN-GOLD', 'Rock Drill Operator', 'A', 'High', 'Rock drill noise'),
  ('MIN-GOLD', 'Rock Drill Operator', 'G', 'High', 'Hand arm vibration from drilling'),
  ('MIN-GOLD', 'Rock Drill Operator', 'H', 'High', 'Hot underground workings'),
  ('MIN-GOLD', 'Rock Drill Operator', 'Q', 'High', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'B', 'High', 'Silica bearing dust in stopes and development ends'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'A', 'Moderate to High', 'Working near drilling and scraper operations'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'I', 'High', 'Heavy manual work in confined stopes'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'H', 'High', 'Hot underground workings'),
  ('MIN-GOLD', 'Stoping and Development Crew', 'Q', 'High', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Winding Engine Driver', 'A', 'Moderate', 'Winder house noise'),
  ('MIN-GOLD', 'Winding Engine Driver', 'K', 'Moderate', 'Shift operation of the winder'),
  ('MIN-GOLD', 'Winding Engine Driver', 'Q', 'High', 'Safety critical statutory fitness: persons conveyance'),
  ('MIN-GOLD', 'LHD and Locomotive Operator', 'G', 'High', 'Whole body vibration underground'),
  ('MIN-GOLD', 'LHD and Locomotive Operator', 'A', 'High', 'Machine noise in confined excavations'),
  ('MIN-GOLD', 'LHD and Locomotive Operator', 'C', 'Moderate', 'Diesel particulate exposure underground'),
  ('MIN-GOLD', 'LHD and Locomotive Operator', 'Q', 'High', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Shaft Timberman and Support Crew', 'E', 'High', 'Work in shafts with fall risk'),
  ('MIN-GOLD', 'Shaft Timberman and Support Crew', 'I', 'High', 'Heavy support material handling'),
  ('MIN-GOLD', 'Shaft Timberman and Support Crew', 'B', 'Moderate', 'Shaft dust'),
  ('MIN-GOLD', 'Shaft Timberman and Support Crew', 'Q', 'High', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Underground Miner (blasting certificate)', 'B', 'High', 'Dust across working places'),
  ('MIN-GOLD', 'Underground Miner (blasting certificate)', 'A', 'Moderate to High', 'Working place noise'),
  ('MIN-GOLD', 'Underground Miner (blasting certificate)', 'H', 'High', 'Hot underground workings'),
  ('MIN-GOLD', 'Underground Miner (blasting certificate)', 'Q', 'High', 'Statutory fitness including blasting duties'),
  ('MIN-GOLD', 'Metallurgical Plant Operator', 'C', 'High', 'Cyanide and process chemical exposure in the gold plant'),
  ('MIN-GOLD', 'Metallurgical Plant Operator', 'A', 'Moderate', 'Milling and plant noise'),
  ('MIN-GOLD', 'Metallurgical Plant Operator', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-GOLD', 'Occupational Hygiene Assistant', 'B', 'Moderate', 'Underground travel through dusty workings'),
  ('MIN-GOLD', 'Occupational Hygiene Assistant', 'H', 'Moderate', 'Measurement rounds in hot workings'),
  ('MIN-GOLD', 'Occupational Hygiene Assistant', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Quarry Supervisor', 'B', 'Moderate', 'Bench and plant dust'),
  ('MIN-QUARRY', 'Quarry Supervisor', 'A', 'Moderate', 'Plant and blasting noise'),
  ('MIN-QUARRY', 'Quarry Supervisor', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Blaster (surface)', 'B', 'Moderate', 'Drilling and blasting dust'),
  ('MIN-QUARRY', 'Blaster (surface)', 'A', 'High', 'Blasting operations noise'),
  ('MIN-QUARRY', 'Blaster (surface)', 'Q', 'High', 'Statutory fitness including blasting duties'),
  ('MIN-QUARRY', 'Drill Rig Operator', 'B', 'High', 'Silica dust at the drill collar'),
  ('MIN-QUARRY', 'Drill Rig Operator', 'A', 'High', 'Drill rig noise'),
  ('MIN-QUARRY', 'Drill Rig Operator', 'G', 'Moderate', 'Rig vibration'),
  ('MIN-QUARRY', 'Drill Rig Operator', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Excavator and Loader Operator', 'G', 'Moderate to High', 'Whole body vibration on benches'),
  ('MIN-QUARRY', 'Excavator and Loader Operator', 'A', 'Moderate', 'Machine noise'),
  ('MIN-QUARRY', 'Excavator and Loader Operator', 'B', 'Moderate', 'Loading dust'),
  ('MIN-QUARRY', 'Excavator and Loader Operator', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Dump Truck Driver', 'J', 'Moderate', 'Haul road driving; PrDP where public roads are used'),
  ('MIN-QUARRY', 'Dump Truck Driver', 'G', 'Moderate', 'Haul road vibration'),
  ('MIN-QUARRY', 'Dump Truck Driver', 'B', 'Moderate', 'Haul road dust'),
  ('MIN-QUARRY', 'Dump Truck Driver', 'Q', 'High', 'Safety critical statutory fitness'),
  ('MIN-QUARRY', 'Crusher Plant Operator', 'B', 'High', 'Crushing and screening dust'),
  ('MIN-QUARRY', 'Crusher Plant Operator', 'A', 'High', 'Crusher noise'),
  ('MIN-QUARRY', 'Crusher Plant Operator', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine'),
  ('MIN-QUARRY', 'Workshop Artisan', 'A', 'Moderate', 'Workshop noise'),
  ('MIN-QUARRY', 'Workshop Artisan', 'G', 'Moderate', 'Tool vibration'),
  ('MIN-QUARRY', 'Workshop Artisan', 'M', 'Moderate', 'Electrical maintenance'),
  ('MIN-QUARRY', 'Workshop Artisan', 'Q', 'Moderate', 'Statutory fitness to perform work at a mine')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('MHSA', 'Framework Act: section 13 medical surveillance and fitness declaration before work'),
  ('Fitness to Perform Work Guideline (MHSA)', 'The mine''s mandatory Code of Practice on minimum standards of fitness governs every certificate of fitness under this Plan'),
  ('ODMWA', 'Compensation route for compensable mining lung disease via MBOD certification; all other conditions route to COIDA'),
  ('COIDA', 'Compensation route for occupational injuries and non ODMWA diseases at the mine'),
  ('NIHL Regulations, 2003', 'Noise instrument reference to 05/09/2026; mine noise duties under MHSA regulations are read with the mine Code of Practice'),
  ('Noise Exposure Regulations, 2024', 'Successor OHSA side noise instrument from 06/09/2026, for works not under MHSA'),
  ('Ergonomics Regulations, 2019', 'Applied by analogy for surface works under OHSA; underground ergonomic risk managed under the mine Code of Practice'),
  ('EEA section 7', 'Lawful basis for every medical test, justified against the inherent requirements of each job'),
  ('BCEA night work Code', 'Continuous mining shifts and night work medicals'),
  ('NRTA PrDP medical', 'Professional driving categories using public roads'),
  ('HPCSA Booklet 1', 'Ethical baseline for all examinations under the programme'),
  ('HPCSA Booklet 10', 'Governs any telehealth component of the programme'),
  ('HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(short_name, note) on true
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
where i.code = 'MINING';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status)
values ('MINING', 6500, 45, 550, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['MIN-GOLD','MIN-QUARRY']) loop
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

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 2: mining exposure limits under the MHSA regulations (dust, noise, thermal for underground workings) remain open; the kernel applies the mine Code of Practice and OMP determination meanwhile. ODMWA amendment by the NHI Act 20 of 2023 is on the currency watch for the next verification cycle.'
 where item_code = 'CR-12.1';

------------------------------------------------------------------------------
-- 012_msp_batch_transport.sql
------------------------------------------------------------------------------

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


------------------------------------------------------------------------------
-- 013_msp_batch_agri_health.sql
------------------------------------------------------------------------------

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

------------------------------------------------------------------------------
-- 014_msp_batch_util_sec_clean.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | TAX-BAT-05 v1.0.0 | Phase 6 batch 5: Utilities and energy, Security services, Cleaning and hygiene
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('Electrical Machinery and Installation Regulations',
 'Electrical Machinery Regulations, 2011, GN R.250, Government Gazette 34154, in operation 1 July 2011, read with the Electrical Installation Regulations, 2009, GN R.242, Government Gazette 31975, in operation 1 May 2009, both made under the Occupational Health and Safety Act 85 of 1993',
 'regulation', 'GN R.250, GG 34154; GN R.242, GG 31975', '2011-07-01',
 'In force August 2026. The Machinery Regulations apply to users who generate, transmit, or distribute electricity to the point of supply; the Installation Regulations govern electrical installation work and registered person requirements. Neither prescribes a standing medical battery: electrical work fitness rests on Employment Equity Act section 7 inherent requirements, with these Regulations anchoring the hazard and competency context.',
 'Consolidated regulation texts, SAFLII emr2011295 and eir342; Department of Employment and Labour published PDFs',
 'Electrical Conformance Board standards incorporation record and policy database entries for both Regulations',
 'Currency check 13/08/2026: both in force, standards incorporation amendments recorded',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

update msp_hazard
   set oel_instrument = 'Electrical Machinery Regulations, 2011, GN R.250 and Electrical Installation Regulations, 2009, GN R.242; fitness for electrical work per EEA section 7 inherent requirements'
 where code = 'M';

update msp_test_protocol
   set legal_basis_id = (select id from msp_legal_instrument where short_name = 'Electrical Machinery and Installation Regulations'),
       trigger_conditions = 'Electrical work fitness per the inherent requirements of the role, in the hazard context of the Electrical Machinery and Installation Regulations. The Regulations anchor the hazard; the lawful testing basis is EEA section 7.'
 where test_name = 'General medical with cardiovascular and vision screen (electrical work)';

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('UTIL', 'Utilities and energy', 'SIC major division 4, Electricity, gas and water supply', 'OHSA'),
('SEC', 'Security services', 'SIC major division 9, Community, social and personal services', 'OHSA'),
('CLEAN', 'Cleaning and hygiene services', 'SIC major division 9, Community, social and personal services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('UTIL', 'UTIL-GEN',   'Power generation',        'Batch 5 role map seeded; gate check below'),
  ('UTIL', 'UTIL-WATER', 'Water and wastewater',    'Batch 5 role map seeded; gate check below'),
  ('UTIL', 'UTIL-RENEW', 'Renewable energy',        'Batch 5 role map seeded; gate check below'),
  ('SEC',  'SEC-GUARD',  'Guarding services',       'Batch 5 role map seeded; gate check below'),
  ('SEC',  'SEC-ARMED',  'Armed response and cash in transit', 'Batch 5 role map seeded; gate check below'),
  ('CLEAN','CLEAN-COMM', 'Commercial cleaning',     'Batch 5 role map seeded; gate check below'),
  ('CLEAN','CLEAN-SPEC', 'Specialised hygiene services', 'Batch 5 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('UTIL-GEN', 'Plant Operator (power station)', 'Operating boilers, turbines, and auxiliary plant', 'Plant rounds in heat and noise, stair and ladder access', 'Alarm vigilance across shifts', 'Plant operation competency'),
  ('UTIL-GEN', 'Electrical Operator (HV switching)', 'High voltage switching and isolation', 'Substation access, switching operations', 'Switching precision, no condition with sudden incapacity potential', 'HV switching authorisation'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'Coal, ash, and dust plant operations', 'Heavy manual work in dust and heat', 'Instruction following under PPE burden', 'None beyond induction'),
  ('UTIL-GEN', 'Line Worker (transmission and distribution)', 'Overhead line construction and fault work', 'Pole and tower climbing, live line discipline', 'Spatial awareness at height, no vertigo', 'Line work competency; heights certification'),
  ('UTIL-GEN', 'Instrument and Control Technician', 'Maintaining control and protection systems', 'Plant access, fine work in panels', 'Fine motor control, fault diagnosis', 'Trade certification'),
  ('UTIL-GEN', 'Shift Charge Engineer', 'Shift control of generation plant', 'Control room duty across nights', 'Sustained concentration, incident command', 'Engineering certification'),
  ('UTIL-WATER', 'Process Controller (water treatment)', 'Dosing, filtration, and disinfection operations', 'Plant rounds with chemical handling', 'Dosing precision, alarm vigilance', 'Water care competency'),
  ('UTIL-WATER', 'Wastewater Plant Operator', 'Screening, digestion, and sludge operations', 'Manual work with sewage contact', 'Process vigilance, hygiene discipline', 'Water care competency'),
  ('UTIL-WATER', 'Chlorination Technician', 'Chlorine gas and hypochlorite systems', 'Cylinder handling, confined dosing rooms', 'Leak response discipline', 'Chlorine handling competency'),
  ('UTIL-WATER', 'Sewer Network Worker', 'Sewer maintenance including confined entry', 'Confined space entry, heavy manual work', 'Gas test discipline, escape procedure', 'Confined space entry competency'),
  ('UTIL-WATER', 'Pump Station Attendant', 'Operating and maintaining pump stations', 'Station access, occasional confined entry', 'Mechanical vigilance', 'None beyond induction'),
  ('UTIL-RENEW', 'Wind Turbine Technician', 'Turbine maintenance at hub height', 'Tower climbing, rescue readiness, work at extreme height', 'No vertigo, self rescue competence, sustained concentration', 'GWO or equivalent heights and rescue certification'),
  ('UTIL-RENEW', 'Solar Plant Technician', 'PV plant maintenance and DC work', 'Field work in heat, panel handling', 'DC electrical discipline', 'Electrical competency'),
  ('UTIL-RENEW', 'Substation Electrician (renewables)', 'Plant substation and inverter maintenance', 'Substation access, switching support', 'Fine motor control, switching discipline', 'Wireman''s licence as applicable'),
  ('UTIL-RENEW', 'Site Operations Controller', 'Monitoring and dispatch of plant output', 'Control room duty', 'Sustained attention across shifts', 'None beyond induction'),
  ('UTIL-RENEW', 'Vegetation and Civils Worker', 'Site clearing and civil maintenance', 'Manual outdoor work in heat', 'Instruction following', 'None beyond induction'),
  ('SEC-GUARD', 'Security Officer (site guarding)', 'Access control and patrols across shifts', 'Standing posts, patrol walking, night duty', 'Vigilance across night shifts, incident composure', 'PSIRA registration'),
  ('SEC-GUARD', 'Control Room Operator', 'CCTV monitoring and alarm dispatch', 'Sedentary night duty', 'Sustained visual vigilance, dispatch precision', 'PSIRA registration'),
  ('SEC-GUARD', 'Retail Security Officer', 'In store loss prevention', 'Standing shifts with public interaction', 'Conflict management composure', 'PSIRA registration'),
  ('SEC-GUARD', 'Site Security Supervisor', 'Supervision of guard rosters and posts', 'Site rounds across shifts', 'Roster management, incident response', 'PSIRA registration'),
  ('SEC-GUARD', 'Events Security Officer', 'Crowd management at events', 'Prolonged standing, physical positioning', 'Crowd vigilance, de escalation', 'PSIRA registration'),
  ('SEC-ARMED', 'Armed Response Officer', 'Vehicle response to alarms', 'Rapid response driving and approach work', 'Firearm discipline, threat judgement, no uncontrolled hypoglycaemic risk', 'PSIRA registration; firearm competency'),
  ('SEC-ARMED', 'Cash in Transit Crew Member', 'Cash movement and vehicle protection', 'Load carriage under threat vigilance', 'Sustained threat vigilance, firearm discipline', 'PSIRA registration; firearm competency'),
  ('SEC-ARMED', 'CIT Driver', 'Armoured vehicle operation', 'Prolonged driving under vigilance', 'Reaction time, route vigilance, no uncontrolled hypoglycaemic risk', 'PSIRA registration; PrDP; firearm competency'),
  ('SEC-ARMED', 'Tactical Support Officer', 'High risk escort and support duty', 'Load bearing tactical work', 'Composure under threat, firearm discipline', 'PSIRA registration; firearm competency'),
  ('SEC-ARMED', 'Armoury Controller', 'Firearm issue, storage, and inspection', 'Standing armoury duty', 'Procedural precision, firearm discipline', 'PSIRA registration; firearm competency'),
  ('CLEAN-COMM', 'Commercial Cleaner', 'Office and facility cleaning', 'Repetitive cleaning work with chemical use', 'Chemical label discipline', 'None beyond induction'),
  ('CLEAN-COMM', 'Industrial Cleaner', 'Plant and warehouse deep cleaning', 'Heavy cleaning work, machine use', 'Machine and chemical discipline', 'None beyond induction'),
  ('CLEAN-COMM', 'High Level Cleaning Operative', 'Facade and high level cleaning', 'Rope access or platform work at height', 'No vertigo, access equipment discipline', 'Working at heights certification; rope access as applicable'),
  ('CLEAN-COMM', 'Cleaning Team Supervisor', 'Supervision of cleaning teams and chemicals', 'Site rounds', 'Team coordination, chemical control', 'None beyond induction'),
  ('CLEAN-COMM', 'Carpet and Floor Care Operative', 'Machine scrubbing, stripping, and sealing', 'Machine handling, wet work', 'Machine and slip discipline', 'None beyond induction'),
  ('CLEAN-SPEC', 'Healthcare Cleaning Operative', 'Clinical area cleaning and waste segregation', 'Cleaning with infectious and sharps risk', 'Segregation discipline', 'None beyond induction'),
  ('CLEAN-SPEC', 'Hygiene Services Technician', 'Washroom hygiene installations and servicing', 'Route servicing with chemical handling', 'Route discipline', 'Driving licence'),
  ('CLEAN-SPEC', 'Pest Control Operator', 'Structural pest control application', 'Application work in roof voids and confined areas', 'Label and exclusion discipline', 'Registered pest control operator'),
  ('CLEAN-SPEC', 'Biohazard Remediation Operative', 'Trauma and biohazard scene cleaning', 'Full PPE decontamination work', 'Procedure discipline under distressing scenes', 'None beyond induction'),
  ('CLEAN-SPEC', 'Sanitation Tanker Operator', 'Servicing chemical toilets and grease traps', 'Hose handling, tanker operation', 'Hygiene and route discipline', 'Driving licence; PrDP where applicable')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('UTIL-GEN', 'Plant Operator (power station)', 'A', 'High', 'Turbine hall and boiler plant noise'),
  ('UTIL-GEN', 'Plant Operator (power station)', 'H', 'Moderate', 'Boiler plant heat'),
  ('UTIL-GEN', 'Plant Operator (power station)', 'K', 'Moderate', 'Continuous shift operation'),
  ('UTIL-GEN', 'Electrical Operator (HV switching)', 'M', 'High', 'High voltage switching duty'),
  ('UTIL-GEN', 'Electrical Operator (HV switching)', 'K', 'Moderate', 'Shift switching duty'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'B', 'Moderate', 'Coal and ash dust'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'A', 'Moderate', 'Plant noise'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'H', 'Moderate', 'Boiler area heat'),
  ('UTIL-GEN', 'Boiler and Ash Plant Worker', 'I', 'Moderate', 'Heavy plant labour'),
  ('UTIL-GEN', 'Line Worker (transmission and distribution)', 'E', 'High', 'Pole and tower work at height'),
  ('UTIL-GEN', 'Line Worker (transmission and distribution)', 'M', 'High', 'Live and switched line work'),
  ('UTIL-GEN', 'Line Worker (transmission and distribution)', 'H', 'Moderate', 'Outdoor line work in heat'),
  ('UTIL-GEN', 'Instrument and Control Technician', 'M', 'Moderate', 'Panel and instrument electrical work'),
  ('UTIL-GEN', 'Instrument and Control Technician', 'A', 'Moderate', 'Plant noise during rounds'),
  ('UTIL-GEN', 'Shift Charge Engineer', 'K', 'Moderate', 'Night shift plant control'),
  ('UTIL-GEN', 'Shift Charge Engineer', 'A', 'Low', 'Control room adjacency to plant'),
  ('UTIL-WATER', 'Process Controller (water treatment)', 'C', 'Moderate', 'Dosing chemical handling'),
  ('UTIL-WATER', 'Process Controller (water treatment)', 'D', 'Moderate', 'Raw water contact'),
  ('UTIL-WATER', 'Wastewater Plant Operator', 'D', 'High', 'Sewage biological exposure'),
  ('UTIL-WATER', 'Wastewater Plant Operator', 'C', 'Moderate', 'Process chemical handling'),
  ('UTIL-WATER', 'Wastewater Plant Operator', 'I', 'Moderate', 'Screen and sludge labour'),
  ('UTIL-WATER', 'Chlorination Technician', 'C', 'High', 'Chlorine gas systems'),
  ('UTIL-WATER', 'Chlorination Technician', 'F', 'Moderate', 'Dosing room confined access'),
  ('UTIL-WATER', 'Sewer Network Worker', 'F', 'High', 'Sewer confined space entry'),
  ('UTIL-WATER', 'Sewer Network Worker', 'D', 'High', 'Sewage biological exposure'),
  ('UTIL-WATER', 'Sewer Network Worker', 'I', 'High', 'Heavy sewer maintenance work'),
  ('UTIL-WATER', 'Pump Station Attendant', 'A', 'Moderate', 'Pump hall noise'),
  ('UTIL-WATER', 'Pump Station Attendant', 'F', 'Low', 'Occasional wet well access'),
  ('UTIL-RENEW', 'Wind Turbine Technician', 'E', 'High', 'Hub height access and rescue readiness'),
  ('UTIL-RENEW', 'Wind Turbine Technician', 'M', 'Moderate', 'Turbine electrical systems'),
  ('UTIL-RENEW', 'Wind Turbine Technician', 'I', 'Moderate', 'Tower climbing load'),
  ('UTIL-RENEW', 'Solar Plant Technician', 'H', 'High', 'Field work in solar resource heat'),
  ('UTIL-RENEW', 'Solar Plant Technician', 'M', 'Moderate', 'DC string and inverter work'),
  ('UTIL-RENEW', 'Substation Electrician (renewables)', 'M', 'High', 'Substation and inverter electrical work'),
  ('UTIL-RENEW', 'Site Operations Controller', 'K', 'Moderate', 'Shift monitoring duty'),
  ('UTIL-RENEW', 'Vegetation and Civils Worker', 'I', 'Moderate', 'Manual site maintenance'),
  ('UTIL-RENEW', 'Vegetation and Civils Worker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('SEC-GUARD', 'Security Officer (site guarding)', 'K', 'High', 'Rotating night guarding'),
  ('SEC-GUARD', 'Security Officer (site guarding)', 'N', 'Moderate', 'Confrontation exposure'),
  ('SEC-GUARD', 'Security Officer (site guarding)', 'I', 'Moderate', 'Prolonged standing and patrols'),
  ('SEC-GUARD', 'Control Room Operator', 'K', 'High', 'Night control room vigilance'),
  ('SEC-GUARD', 'Control Room Operator', 'N', 'Low', 'Incident monitoring load'),
  ('SEC-GUARD', 'Retail Security Officer', 'N', 'Moderate', 'Public confrontation exposure'),
  ('SEC-GUARD', 'Retail Security Officer', 'I', 'Moderate', 'Standing shifts'),
  ('SEC-GUARD', 'Site Security Supervisor', 'K', 'Moderate', 'Shift supervision'),
  ('SEC-GUARD', 'Events Security Officer', 'N', 'Moderate', 'Crowd confrontation exposure'),
  ('SEC-GUARD', 'Events Security Officer', 'A', 'Moderate', 'Event sound exposure'),
  ('SEC-ARMED', 'Armed Response Officer', 'N', 'High', 'Armed confrontation exposure'),
  ('SEC-ARMED', 'Armed Response Officer', 'J', 'High', 'Response driving'),
  ('SEC-ARMED', 'Armed Response Officer', 'K', 'Moderate', 'Night response shifts'),
  ('SEC-ARMED', 'Cash in Transit Crew Member', 'N', 'High', 'Attack risk exposure'),
  ('SEC-ARMED', 'Cash in Transit Crew Member', 'I', 'Moderate', 'Cash load carriage'),
  ('SEC-ARMED', 'CIT Driver', 'J', 'High', 'Armoured vehicle operation under threat'),
  ('SEC-ARMED', 'CIT Driver', 'N', 'High', 'Attack risk exposure'),
  ('SEC-ARMED', 'Tactical Support Officer', 'N', 'High', 'High risk escort duty'),
  ('SEC-ARMED', 'Tactical Support Officer', 'I', 'Moderate', 'Tactical load bearing'),
  ('SEC-ARMED', 'Armoury Controller', 'N', 'Low', 'Firearm custody responsibility'),
  ('CLEAN-COMM', 'Commercial Cleaner', 'C', 'Moderate', 'Cleaning chemical use'),
  ('CLEAN-COMM', 'Commercial Cleaner', 'I', 'Moderate', 'Repetitive cleaning work'),
  ('CLEAN-COMM', 'Commercial Cleaner', 'K', 'Moderate', 'Early and late shift cleaning'),
  ('CLEAN-COMM', 'Industrial Cleaner', 'C', 'Moderate', 'Industrial cleaning agents'),
  ('CLEAN-COMM', 'Industrial Cleaner', 'I', 'High', 'Heavy deep cleaning work'),
  ('CLEAN-COMM', 'Industrial Cleaner', 'A', 'Moderate', 'Cleaning machinery noise'),
  ('CLEAN-COMM', 'High Level Cleaning Operative', 'E', 'High', 'Facade work at height'),
  ('CLEAN-COMM', 'High Level Cleaning Operative', 'C', 'Moderate', 'Cleaning chemical use at height'),
  ('CLEAN-COMM', 'Cleaning Team Supervisor', 'C', 'Low', 'Chemical control supervision'),
  ('CLEAN-COMM', 'Carpet and Floor Care Operative', 'C', 'Moderate', 'Strippers and sealants'),
  ('CLEAN-COMM', 'Carpet and Floor Care Operative', 'I', 'Moderate', 'Machine handling'),
  ('CLEAN-SPEC', 'Healthcare Cleaning Operative', 'D', 'High', 'Clinical infectious and sharps exposure'),
  ('CLEAN-SPEC', 'Healthcare Cleaning Operative', 'C', 'Moderate', 'Disinfectant use'),
  ('CLEAN-SPEC', 'Hygiene Services Technician', 'D', 'Moderate', 'Washroom service exposure'),
  ('CLEAN-SPEC', 'Hygiene Services Technician', 'C', 'Moderate', 'Hygiene chemical handling'),
  ('CLEAN-SPEC', 'Hygiene Services Technician', 'J', 'Moderate', 'Route driving'),
  ('CLEAN-SPEC', 'Pest Control Operator', 'C', 'High', 'Pesticide application including organophosphates'),
  ('CLEAN-SPEC', 'Pest Control Operator', 'F', 'Moderate', 'Roof void and confined area access'),
  ('CLEAN-SPEC', 'Biohazard Remediation Operative', 'D', 'High', 'Trauma scene biological exposure'),
  ('CLEAN-SPEC', 'Biohazard Remediation Operative', 'N', 'Moderate', 'Distressing scene exposure'),
  ('CLEAN-SPEC', 'Sanitation Tanker Operator', 'D', 'High', 'Sewage and waste exposure'),
  ('CLEAN-SPEC', 'Sanitation Tanker Operator', 'J', 'Moderate', 'Tanker route driving')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('UTIL', 'OHS Act', 'Framework Act for utility workplaces'),
  ('UTIL', 'Electrical Machinery and Installation Regulations', 'Generation, transmission, distribution, and installation work'),
  ('UTIL', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026'),
  ('UTIL', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('UTIL', 'HCA Regulations, 2021', 'Treatment chemicals, chlorine, fuels, and coal dust context'),
  ('UTIL', 'HBA Regulations, 2022', 'Sewage and raw water biological exposure'),
  ('UTIL', 'Environmental Regulations for Workplaces, 1987', 'Boiler plant and field heat; hot work fitness certification'),
  ('UTIL', 'Ergonomics Regulations, 2019', 'Plant labour and climbing work surveillance'),
  ('UTIL', 'Construction Regulations, 2014', 'Applies to construction phases of utility projects including work at height certification'),
  ('UTIL', 'COIDA', 'Compensation route for utility injuries and diseases'),
  ('UTIL', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('UTIL', 'BCEA night work Code', 'Continuous shift operation'),
  ('UTIL', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('UTIL', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer'),
  ('SEC', 'OHS Act', 'Framework Act for security workplaces'),
  ('SEC', 'BCEA night work Code', 'Night guarding and response shifts: the central working time instrument for this sector'),
  ('SEC', 'NRTA PrDP medical', 'Response and CIT driving categories'),
  ('SEC', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements, including firearm duty fitness'),
  ('SEC', 'COIDA', 'Compensation route including PTSD as an occupational disease per the 2026 amendments'),
  ('SEC', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 where applicable'),
  ('SEC', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('SEC', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('SEC', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer'),
  ('CLEAN', 'OHS Act', 'Framework Act for cleaning service workplaces'),
  ('CLEAN', 'HCA Regulations, 2021', 'Cleaning chemicals and pest control products, with cholinesterase monitoring for organophosphate applicators'),
  ('CLEAN', 'HBA Regulations, 2022', 'Healthcare, biohazard, and sanitation biological exposure'),
  ('CLEAN', 'Ergonomics Regulations, 2019', 'Repetitive cleaning work surveillance'),
  ('CLEAN', 'Construction Regulations, 2014', 'Work at height certification for high level cleaning'),
  ('CLEAN', 'COIDA', 'Compensation route for cleaning service injuries and diseases'),
  ('CLEAN', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('CLEAN', 'BCEA night work Code', 'Early and late shift cleaning'),
  ('CLEAN', 'NRTA PrDP medical', 'Route service driving where applicable'),
  ('CLEAN', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('CLEAN', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('UTIL', 4500, 35, 450, 'placeholder'),
('SEC', 4500, 35, 450, 'placeholder'),
('CLEAN', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['UTIL-GEN','UTIL-WATER','UTIL-RENEW','SEC-GUARD','SEC-ARMED','CLEAN-COMM','CLEAN-SPEC']) loop
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
   set description = description || ' Update 13/08/2026 batch 5: electrical work carries no statutory standing medical battery; the Electrical Machinery Regulations 2011 and Electrical Installation Regulations 2009 anchor the hazard and competency context and the lawful testing basis is EEA section 7. Armed duty and firearm fitness likewise rest on EEA section 7 inherent requirements read with PSIRA registration and firearm competency as statutory competencies, not medical instruments.'
 where item_code = 'CR-12.1';


------------------------------------------------------------------------------
-- 015_msp_batch_retail.sql
------------------------------------------------------------------------------

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


------------------------------------------------------------------------------
-- 016_msp_batch_hospitality.sql
------------------------------------------------------------------------------

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


------------------------------------------------------------------------------
-- 017_msp_batch_waste.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | TAX-BAT-08 v1.0.0 | Phase 6 batch 8: Waste management
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('NEM Waste Act',
 'National Environmental Management: Waste Act 59 of 2008, Government Gazette 32000, in operation 1 July 2009. The Act governs waste management licensing, the duty of care for waste holders, and healthcare risk waste control. It prescribes no standing occupational medical battery: waste worker surveillance rests on the OHSA instrument set and the lawful testing basis is EEA section 7, with this Act anchoring the sector duty of care context.',
 'act', 'Act 59 of 2008, GG 32000; in operation 1 July 2009', '2009-07-01',
 'Amended by Act 14 of 2013, Act 25 of 2014, Act 26 of 2014 (GG 37714, with effect from 2 June 2014), and Act 2 of 2022; consolidated text current to 30 June 2023 on the national law library. In force August 2026.',
 'Consolidated Act texts, SAFLII nemwa2008394 and the official gov.za Act publication',
 'National law library consolidated version at 30 June 2023 and the UNEP legislation record confirming commencement 1 July 2009, GG 32000',
 'Currency check 13/08/2026: in force with the 2013, 2014, and 2022 amendment chain recorded',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- Waste management industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('WASTE', 'Waste management', 'SIC major division 9, Community, social and personal services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('WASTE', 'WASTE-COLL', 'Collection and street cleansing',      'Batch 8 role map seeded; gate check below'),
  ('WASTE', 'WASTE-SITE', 'Landfill and transfer stations',       'Batch 8 role map seeded; gate check below'),
  ('WASTE', 'WASTE-REC',  'Recycling and materials recovery',     'Batch 8 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('WASTE-COLL', 'Refuse Truck Driver', 'Compaction vehicle operation on collection rounds', 'Prolonged urban driving with frequent stops', 'Crew and pedestrian vigilance, reaction time, no uncontrolled hypoglycaemic risk', 'PrDP for the applicable vehicle class'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'Bin and bag loading on collection rounds', 'Sustained heavy lifting at pace, running boards work', 'Traffic vigilance, crew coordination', 'None beyond induction'),
  ('WASTE-COLL', 'Street Sweeper and Litter Picker', 'Street cleansing and litter collection', 'Sustained walking and sweeping, sharps risk handling', 'Traffic vigilance, sharps discipline', 'None beyond induction'),
  ('WASTE-COLL', 'Skip and Roll On Truck Driver', 'Skip placement and exchange operations', 'Hook and chain work, load securing', 'Load stability judgement, site manoeuvring', 'PrDP for the applicable vehicle class'),
  ('WASTE-COLL', 'Illegal Dumping Response Worker', 'Clearing uncontrolled dumping sites', 'Heavy mixed waste handling of unknown composition', 'Hazard recognition in uncharacterised waste', 'None beyond induction'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'Compactor, dozer, and landfill plant operation', 'Sustained plant operation on waste body surfaces', 'Machine stability judgement, site traffic vigilance, no condition with sudden incapacity potential', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('WASTE-SITE', 'Weighbridge Operator', 'Vehicle weighing and load documentation', 'Sedentary control room duty', 'Documentation accuracy, vehicle queue management', 'None beyond induction'),
  ('WASTE-SITE', 'Landfill General Worker', 'Cover material work, litter fencing, and site labour', 'Heavy outdoor labour on the waste body', 'Site traffic vigilance, instruction following', 'None beyond induction'),
  ('WASTE-SITE', 'Transfer Station Operator', 'Waste transfer, pushing, and loading operations', 'Plant and floor work in the transfer hall', 'Traffic and plant separation vigilance', 'None beyond induction'),
  ('WASTE-SITE', 'Leachate and Gas System Technician', 'Leachate pumping and landfill gas system maintenance', 'Sump and manifold access including confined entry', 'Gas test discipline, escape procedure', 'Confined space entry competency'),
  ('WASTE-REC',  'Materials Recovery Sorting Line Picker', 'Manual sorting on the recovery line', 'Sustained repetitive picking with sharps risk', 'Material recognition at rate, sharps discipline', 'None beyond induction'),
  ('WASTE-REC',  'Baler and Compactor Operator', 'Baling and compacting recovered materials', 'Bale handling, machine feeding', 'Machine guarding discipline', 'None beyond induction'),
  ('WASTE-REC',  'E Waste Dismantling Technician', 'Manual dismantling of electronic waste', 'Repetitive dismantling with lead and cadmium bearing components', 'Component recognition, hygiene discipline', 'None beyond induction'),
  ('WASTE-REC',  'Buy Back Centre Assistant', 'Receiving, weighing, and sorting recyclables', 'Sustained handling of mixed recyclables', 'Grading accuracy, sharps discipline', 'None beyond induction'),
  ('WASTE-REC',  'Healthcare Risk Waste Handler', 'Collection and processing of healthcare risk waste', 'Container handling in full PPE', 'Segregation and containment discipline', 'None beyond induction')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('WASTE-COLL', 'Refuse Truck Driver', 'J', 'High', 'Professional collection round driving with PrDP requirement'),
  ('WASTE-COLL', 'Refuse Truck Driver', 'K', 'Moderate', 'Early morning collection shifts'),
  ('WASTE-COLL', 'Refuse Truck Driver', 'D', 'Moderate', 'Waste stream biological contact'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'I', 'High', 'Sustained heavy loading at pace'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'D', 'High', 'Direct waste handling with sharps risk'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'K', 'Moderate', 'Early morning collection shifts'),
  ('WASTE-COLL', 'Refuse Collection Loader', 'H', 'Moderate', 'Outdoor rounds in heat'),
  ('WASTE-COLL', 'Street Sweeper and Litter Picker', 'I', 'Moderate', 'Sustained sweeping and walking'),
  ('WASTE-COLL', 'Street Sweeper and Litter Picker', 'D', 'Moderate', 'Litter and sharps handling'),
  ('WASTE-COLL', 'Street Sweeper and Litter Picker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('WASTE-COLL', 'Skip and Roll On Truck Driver', 'J', 'High', 'Skip vehicle operation with PrDP requirement'),
  ('WASTE-COLL', 'Skip and Roll On Truck Driver', 'I', 'Moderate', 'Hook, chain, and load securing work'),
  ('WASTE-COLL', 'Illegal Dumping Response Worker', 'D', 'High', 'Uncharacterised waste biological exposure'),
  ('WASTE-COLL', 'Illegal Dumping Response Worker', 'I', 'High', 'Heavy mixed waste clearance'),
  ('WASTE-COLL', 'Illegal Dumping Response Worker', 'C', 'Moderate', 'Unknown chemical containers in dumped waste'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'J', 'High', 'Landfill plant operation under the Driven Machinery Regulations, 2015'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'B', 'Moderate', 'Cover material and site dust'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'A', 'Moderate', 'Plant cab noise'),
  ('WASTE-SITE', 'Landfill Compactor and Plant Operator', 'D', 'Moderate', 'Waste body biological context'),
  ('WASTE-SITE', 'Weighbridge Operator', 'K', 'Moderate', 'Extended site operating hours'),
  ('WASTE-SITE', 'Weighbridge Operator', 'A', 'Low', 'Vehicle queue noise'),
  ('WASTE-SITE', 'Landfill General Worker', 'D', 'High', 'Waste body biological exposure'),
  ('WASTE-SITE', 'Landfill General Worker', 'B', 'Moderate', 'Site and cover material dust'),
  ('WASTE-SITE', 'Landfill General Worker', 'I', 'High', 'Heavy site labour'),
  ('WASTE-SITE', 'Landfill General Worker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('WASTE-SITE', 'Transfer Station Operator', 'D', 'Moderate', 'Transfer hall waste contact'),
  ('WASTE-SITE', 'Transfer Station Operator', 'A', 'Moderate', 'Transfer hall plant noise'),
  ('WASTE-SITE', 'Transfer Station Operator', 'I', 'Moderate', 'Pushing and loading work'),
  ('WASTE-SITE', 'Leachate and Gas System Technician', 'C', 'Moderate', 'Landfill gas and leachate chemical exposure'),
  ('WASTE-SITE', 'Leachate and Gas System Technician', 'D', 'Moderate', 'Leachate biological exposure'),
  ('WASTE-SITE', 'Leachate and Gas System Technician', 'F', 'Moderate', 'Sump and chamber confined entry'),
  ('WASTE-REC',  'Materials Recovery Sorting Line Picker', 'D', 'High', 'Mixed waste sorting with sharps risk'),
  ('WASTE-REC',  'Materials Recovery Sorting Line Picker', 'I', 'High', 'Sustained repetitive picking at rate'),
  ('WASTE-REC',  'Materials Recovery Sorting Line Picker', 'A', 'Moderate', 'Recovery hall plant noise'),
  ('WASTE-REC',  'Baler and Compactor Operator', 'A', 'Moderate', 'Baler plant noise'),
  ('WASTE-REC',  'Baler and Compactor Operator', 'I', 'Moderate', 'Bale handling'),
  ('WASTE-REC',  'E Waste Dismantling Technician', 'C', 'High', 'Lead and cadmium bearing component dismantling'),
  ('WASTE-REC',  'E Waste Dismantling Technician', 'I', 'Moderate', 'Repetitive dismantling work'),
  ('WASTE-REC',  'Buy Back Centre Assistant', 'I', 'Moderate', 'Mixed recyclables handling'),
  ('WASTE-REC',  'Buy Back Centre Assistant', 'D', 'Moderate', 'Contaminated recyclables contact'),
  ('WASTE-REC',  'Healthcare Risk Waste Handler', 'D', 'High', 'Healthcare risk waste with sharps and infectious exposure'),
  ('WASTE-REC',  'Healthcare Risk Waste Handler', 'C', 'Moderate', 'Disinfection chemical handling'),
  ('WASTE-REC',  'Healthcare Risk Waste Handler', 'I', 'Moderate', 'Container handling in full PPE')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('WASTE', 'OHS Act', 'Framework Act for waste management workplaces'),
  ('WASTE', 'NEM Waste Act', 'Sector duty of care, licensing, and healthcare risk waste control context'),
  ('WASTE', 'HBA Regulations, 2022', 'Waste stream, leachate, and healthcare risk waste biological exposure'),
  ('WASTE', 'HCA Regulations, 2021', 'Landfill gas, e waste heavy metals, and disinfection chemicals'),
  ('WASTE', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for plant and recovery halls'),
  ('WASTE', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('WASTE', 'Ergonomics Regulations, 2019', 'Collection loading and sorting line surveillance'),
  ('WASTE', 'Environmental Regulations for Workplaces, 1987', 'Outdoor heat and confined space atmospheres'),
  ('WASTE', 'Driven Machinery Regulations', 'Landfill plant and lifting machine operator medical certificates of fitness'),
  ('WASTE', 'NRTA PrDP medical', 'Collection and skip vehicle driving categories'),
  ('WASTE', 'BCEA night work Code', 'Early morning collection shifts'),
  ('WASTE', 'COIDA', 'Compensation route for waste sector injuries and diseases'),
  ('WASTE', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('WASTE', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('WASTE', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('WASTE', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['WASTE-COLL','WASTE-SITE','WASTE-REC']) loop
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
   set description = description || ' Update 13/08/2026 batch 8: healthcare risk waste handling is carried under the HBA framework with hepatitis B immunity verification; the SANS 10248 healthcare risk waste standard remains open under the SANS editions item. E waste dismantling feeds the lead biological monitoring protocol where exposure assessment confirms lead bearing work.'
 where item_code = 'CR-12.1';


------------------------------------------------------------------------------
-- 018_msp_batch_telecoms.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | TAX-BAT-09 v1.0.0 | Phase 6 batch 9: Telecommunications and tower work
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('General Safety Regulations, 1986',
 'General Safety Regulations, 1986, GNR 1031, Government Gazette 10252, 30 May 1986, made under the Machinery and Occupational Safety Act 6 of 1983 and kept in force under the Occupational Health and Safety Act 85 of 1993. The Regulations govern first aid provision, personal protective equipment, work in elevated positions, ladders, and general workplace safety duties. They prescribe no standing medical battery: fitness for the work they govern rests on EEA section 7 inherent requirements.',
 'regulation', 'GNR 1031, GG 10252, 30 May 1986', '1986-05-30',
 'Published 30 May 1986 under the Machinery and Occupational Safety Act 6 of 1983; carried into force under section 44 of the Occupational Health and Safety Act 85 of 1993. In force August 2026 with amendments to the first aid and PPE provisions recorded in the consolidated texts.',
 'Full regulation texts, national law library source file 1986-r1031 and the Acts Online consolidated version',
 'ILO NATLEX record for GNR 1031 confirming publication GG 10252, 30 May 1986, and the SAFLII historical regulation record',
 'Currency check 13/08/2026: in force under the OHS Act with no repeal recorded',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-08-13', 'verified');

-- Telecommunications and tower work industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('TEL', 'Telecommunications and tower work', 'SIC major division 7, Transport, storage and communication', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('TEL', 'TEL-TOWER', 'Tower construction and rigging',        'Batch 9 role map seeded; gate check below'),
  ('TEL', 'TEL-FIELD', 'Field network services',                'Batch 9 role map seeded; gate check below'),
  ('TEL', 'TEL-DC',    'Data centres and network operations',   'Batch 9 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('TEL-TOWER', 'Tower Rigger and Climber', 'Mast and tower climbing for construction and maintenance, working near live antennas within controlled radio frequency exclusion zones', 'Sustained climbing with tool and equipment load, rescue readiness', 'No vertigo, self rescue competence, exclusion zone discipline', 'Working at heights and rescue certification'),
  ('TEL-TOWER', 'Antenna and RF Technician', 'Antenna installation, alignment, and radio frequency testing at height within controlled exclusion zones', 'Tower climbing with test equipment', 'Alignment precision at height, exclusion zone discipline', 'Working at heights certification'),
  ('TEL-TOWER', 'Tower Civils and Foundation Worker', 'Foundation, plinth, and compound civils at tower sites', 'Heavy site labour, concrete and excavation work', 'Instruction following, site discipline', 'None beyond induction'),
  ('TEL-TOWER', 'Site Power and Generator Technician', 'Site power, rectifier, and generator installation and service', 'Component lifting, fuel handling, site driving between installations', 'Electrical discipline, fault diagnosis, no condition with sudden incapacity potential', 'Electrical competency; driving licence'),
  ('TEL-TOWER', 'Tower Crew Supervisor', 'Crew supervision across tower sites', 'Site access climbing, extensive route driving', 'Rescue plan command, crew coordination', 'Working at heights certification; driving licence'),
  ('TEL-FIELD', 'Fibre Splicer and Jointer', 'Fibre splicing in manholes, chambers, and joint boxes', 'Chamber access including confined entry, fine splicing work', 'Fine motor precision, gas test discipline in chambers', 'Confined space entry competency where applicable'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'Trenching, duct laying, and reinstatement', 'Sustained excavation labour in heat and dust', 'Traffic and services awareness', 'None beyond induction'),
  ('TEL-FIELD', 'Aerial Line Installer', 'Aerial fibre and cable installation on poles', 'Pole climbing and ladder work, roadside working', 'No vertigo, traffic vigilance', 'Working at heights certification; driving licence'),
  ('TEL-FIELD', 'Customer Premises Installer', 'Home and business installations including roof access', 'Ladder and roof access, equipment carriage, route driving', 'Customer interaction, roof edge discipline', 'Driving licence'),
  ('TEL-FIELD', 'Network Field Technician', 'Street cabinet and exchange maintenance with standby callouts', 'Route driving, cabinet work at roadside', 'Fault diagnosis, standby alertness', 'Driving licence'),
  ('TEL-DC',    'Data Centre Operations Technician', 'Shift operation of data centre infrastructure', 'Plant hall rounds across continuous shifts', 'Alarm vigilance, change control discipline', 'None beyond induction'),
  ('TEL-DC',    'HVAC and Mechanical Plant Technician', 'Cooling and mechanical plant maintenance', 'Plant room work, component handling', 'Mechanical fault diagnosis', 'Trade certification'),
  ('TEL-DC',    'UPS and Battery Technician', 'UPS, rectifier, and battery string maintenance', 'Battery handling, live DC plant work', 'Electrical discipline, no condition with sudden incapacity potential', 'Electrical competency'),
  ('TEL-DC',    'Network Operations Centre Analyst', 'Continuous network monitoring and incident dispatch', 'Sedentary night duty', 'Sustained overnight vigilance, incident triage', 'None beyond induction'),
  ('TEL-DC',    'Structured Cabling and Racking Technician', 'Rack installation and structured cabling', 'Repetitive overhead and under floor cabling work', 'Cable management precision', 'None beyond induction')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('TEL-TOWER', 'Tower Rigger and Climber', 'E', 'High', 'Mast and tower work at extreme height with rescue readiness'),
  ('TEL-TOWER', 'Tower Rigger and Climber', 'I', 'High', 'Sustained climbing under tool and equipment load'),
  ('TEL-TOWER', 'Tower Rigger and Climber', 'H', 'Moderate', 'Exposed outdoor tower work in heat'),
  ('TEL-TOWER', 'Antenna and RF Technician', 'E', 'High', 'Antenna work at height'),
  ('TEL-TOWER', 'Antenna and RF Technician', 'M', 'Moderate', 'Antenna feeder and site electrical work'),
  ('TEL-TOWER', 'Tower Civils and Foundation Worker', 'I', 'High', 'Heavy foundation and compound labour'),
  ('TEL-TOWER', 'Tower Civils and Foundation Worker', 'B', 'Moderate', 'Excavation and concrete dust'),
  ('TEL-TOWER', 'Tower Civils and Foundation Worker', 'H', 'Moderate', 'Outdoor civils in heat'),
  ('TEL-TOWER', 'Site Power and Generator Technician', 'M', 'High', 'Site power and rectifier electrical work'),
  ('TEL-TOWER', 'Site Power and Generator Technician', 'C', 'Moderate', 'Fuel and battery electrolyte handling'),
  ('TEL-TOWER', 'Site Power and Generator Technician', 'J', 'Moderate', 'Route driving between sites'),
  ('TEL-TOWER', 'Tower Crew Supervisor', 'E', 'Moderate', 'Site access climbing for supervision'),
  ('TEL-TOWER', 'Tower Crew Supervisor', 'J', 'Moderate', 'Extensive route driving'),
  ('TEL-TOWER', 'Tower Crew Supervisor', 'K', 'Moderate', 'Outage and callout windows'),
  ('TEL-FIELD', 'Fibre Splicer and Jointer', 'F', 'Moderate', 'Manhole and chamber confined entry'),
  ('TEL-FIELD', 'Fibre Splicer and Jointer', 'I', 'Moderate', 'Sustained kneeling splicing work'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'I', 'High', 'Sustained excavation labour'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'B', 'Moderate', 'Trenching dust'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'H', 'Moderate', 'Outdoor trenching in heat'),
  ('TEL-FIELD', 'Trenching and Duct Crew Worker', 'A', 'Moderate', 'Compaction and cutting plant noise'),
  ('TEL-FIELD', 'Aerial Line Installer', 'E', 'High', 'Pole and ladder work'),
  ('TEL-FIELD', 'Aerial Line Installer', 'M', 'Moderate', 'Work near powered services'),
  ('TEL-FIELD', 'Aerial Line Installer', 'J', 'Moderate', 'Roadside route driving'),
  ('TEL-FIELD', 'Customer Premises Installer', 'E', 'Moderate', 'Ladder and roof access'),
  ('TEL-FIELD', 'Customer Premises Installer', 'J', 'Moderate', 'Daily route driving'),
  ('TEL-FIELD', 'Customer Premises Installer', 'I', 'Moderate', 'Equipment carriage and installation work'),
  ('TEL-FIELD', 'Network Field Technician', 'J', 'Moderate', 'Route driving with standby callouts'),
  ('TEL-FIELD', 'Network Field Technician', 'M', 'Moderate', 'Cabinet and exchange electrical work'),
  ('TEL-FIELD', 'Network Field Technician', 'K', 'Moderate', 'Standby and callout duty'),
  ('TEL-DC',    'Data Centre Operations Technician', 'K', 'High', 'Continuous shift operation'),
  ('TEL-DC',    'Data Centre Operations Technician', 'A', 'Moderate', 'Plant hall noise'),
  ('TEL-DC',    'Data Centre Operations Technician', 'M', 'Moderate', 'Power infrastructure rounds'),
  ('TEL-DC',    'HVAC and Mechanical Plant Technician', 'A', 'Moderate', 'Chiller and plant room noise'),
  ('TEL-DC',    'HVAC and Mechanical Plant Technician', 'I', 'Moderate', 'Component and filter handling'),
  ('TEL-DC',    'HVAC and Mechanical Plant Technician', 'M', 'Moderate', 'Plant electrical maintenance'),
  ('TEL-DC',    'UPS and Battery Technician', 'C', 'Moderate', 'Battery electrolyte and lithium system handling'),
  ('TEL-DC',    'UPS and Battery Technician', 'M', 'High', 'Live DC plant work'),
  ('TEL-DC',    'Network Operations Centre Analyst', 'K', 'High', 'Standing overnight monitoring duty'),
  ('TEL-DC',    'Structured Cabling and Racking Technician', 'I', 'Moderate', 'Overhead and under floor cabling work'),
  ('TEL-DC',    'Structured Cabling and Racking Technician', 'K', 'Moderate', 'Change window night work')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('TEL', 'OHS Act', 'Framework Act for telecommunications workplaces'),
  ('TEL', 'General Safety Regulations, 1986', 'First aid, PPE, elevated positions, and ladder duties for tower and field crews'),
  ('TEL', 'Construction Regulations, 2014', 'Tower construction phases and work at height fitness certification'),
  ('TEL', 'Electrical Machinery and Installation Regulations', 'Site power, rectifier, and data centre electrical work'),
  ('TEL', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for plant halls and construction plant'),
  ('TEL', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('TEL', 'HCA Regulations, 2021', 'Fuels, battery electrolyte, and lithium system context'),
  ('TEL', 'Ergonomics Regulations, 2019', 'Climbing load, trenching, and cabling work surveillance'),
  ('TEL', 'Environmental Regulations for Workplaces, 1987', 'Outdoor heat and chamber atmospheres'),
  ('TEL', 'Driven Machinery Regulations', 'Crane and lifting operations in tower construction'),
  ('TEL', 'NRTA PrDP medical', 'Route driving categories where applicable'),
  ('TEL', 'BCEA night work Code', 'Continuous data centre shifts and standby callouts'),
  ('TEL', 'COIDA', 'Compensation route for telecommunications injuries and diseases'),
  ('TEL', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('TEL', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('TEL', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('TEL', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['TEL-TOWER','TEL-FIELD','TEL-DC']) loop
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
   set description = description || ' Update 13/08/2026 batch 9: the General Safety Regulations, 1986 (GNR 1031, GG 10252, 30 May 1986) are now triple verified, closing a second leg of this item; the General Administrative and General Machinery Regulations remain open.'
 where item_code = 'CR-13.9';

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 9: radio frequency electromagnetic field exposure carries no South African statutory occupational exposure limit; tower and antenna roles carry the exclusion zone discipline in the role narrative per international guidance, and hazard L with its dose monitoring protocol remains reserved for ionising sources under SAHPRA licensing. Should an RF instrument be promulgated, the tower role maps tighten accordingly.'
 where item_code = 'CR-12.1';


------------------------------------------------------------------------------
-- 019_msp_batch_petrochem.sql
------------------------------------------------------------------------------

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


------------------------------------------------------------------------------
-- 020_msp_batch_government.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | TAX-BAT-11 v1.0.0 | Phase 6 batch 11: Government and municipal
-- Documentary verification 13/08/2026, subject to OMP ratification.

insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, gazette_reference, effective_date,
   amendment_history, source_one, source_two, source_three,
   verified_on, verified_by, review_due, status)
values
('General Machinery Regulations, 1988',
 'General Machinery Regulations, 1988, GNR 1521, Government Gazette 11443, 5 August 1988, made under the Machinery and Occupational Safety Act 6 of 1983 and kept in force under the Occupational Health and Safety Act 85 of 1993. The Regulations govern machinery supervision, safeguarding, and operation duties for machinery classes not covered by other regulations. They prescribe no standing medical battery: fitness for machinery work rests on EEA section 7 inherent requirements.',
 'regulation', 'GNR 1521, GG 11443, 5 August 1988', '1988-08-05',
 'Published 5 August 1988 under the Machinery and Occupational Safety Act 6 of 1983; carried into force under section 44 of the Occupational Health and Safety Act 85 of 1993. Currency watch: a draft General Machinery Regulation, 2025 was published for public comment (GN 6532, GG 53210, August 2025) with the intention of replacing these Regulations; in force August 2026 pending that process.',
 'Full regulation text, SAFLII gmr272 consolidated version and the published regulation PDF',
 'ILO NATLEX record for GNR 1521 and the Sabinet legislation record confirming GG 11443, 5 August 1988',
 'Currency check 13/08/2026: in force; replacement draft GN 6532, GG 53210 (2025) noted for the verification watchdog',
 '2026-08-13', 'Claude Code build agent, documentary verification, subject to OMP ratification', '2027-02-13', 'verified');

-- Government and municipal industry

insert into msp_industry (code, name, sic_reference, regulatory_regime) values
('GOV', 'Government and municipal', 'SIC major division 9, Community, social and personal services', 'OHSA');

insert into msp_subindustry (industry_id, code, name, selectable, notes)
select i.id, s.code, s.name, false, s.notes
from msp_industry i
join (values
  ('GOV', 'GOV-ADMIN', 'Administration and community facilities', 'Batch 11 role map seeded; gate check below'),
  ('GOV', 'GOV-WORKS', 'Public works and technical services',     'Batch 11 role map seeded; gate check below'),
  ('GOV', 'GOV-EMERG', 'Emergency and traffic services',          'Batch 11 role map seeded; gate check below')
) as s(icode, code, name, notes) on i.code = s.icode;

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('GOV-ADMIN', 'Municipal Office Administrator', 'Administration, records, and counter services', 'Sustained workstation work', 'Documentation accuracy, public interaction', 'None beyond induction'),
  ('GOV-ADMIN', 'Community Hall and Facility Caretaker', 'Facility opening, cleaning, and minor maintenance', 'Cleaning work with chemical use, furniture handling', 'Facility security vigilance', 'None beyond induction'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'Parks maintenance, mowing, and brush cutting', 'Sustained outdoor labour with powered equipment', 'Equipment and public separation discipline', 'None beyond induction'),
  ('GOV-ADMIN', 'Library and Community Centre Assistant', 'Library services and community programmes', 'Shelving and trolley work', 'Cataloguing accuracy, public interaction', 'None beyond induction'),
  ('GOV-ADMIN', 'Cemetery Worker', 'Grave preparation and grounds maintenance', 'Heavy excavation and grounds labour', 'Procedural dignity, instruction following', 'None beyond induction'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'Pothole repair, verge, and roadworks maintenance', 'Heavy road labour with traffic exposure', 'Traffic vigilance, flag and cone discipline', 'None beyond induction'),
  ('GOV-WORKS', 'Water and Sanitation Artisan', 'Water and sewer reticulation maintenance', 'Excavation and chamber work with sewage contact', 'Gas test discipline, isolation discipline', 'Confined space entry competency where applicable'),
  ('GOV-WORKS', 'Municipal Electrician', 'Public lighting and building electrical maintenance', 'Pole and ladder work, live testing', 'Electrical discipline, no condition with sudden incapacity potential', 'Wireman''s licence as applicable'),
  ('GOV-WORKS', 'Municipal Plant Operator', 'Grader, TLB, and municipal plant operation', 'Sustained plant operation on works sites', 'Machine stability judgement, pedestrian vigilance', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('GOV-WORKS', 'Building Maintenance Artisan', 'Municipal building repairs across trades', 'Ladder access, manual trade work', 'Trade fault diagnosis', 'Trade certification'),
  ('GOV-WORKS', 'Stormwater and Drainage Worker', 'Stormwater culvert and drainage maintenance', 'Culvert entry, heavy debris clearance', 'Gas test discipline in culverts, weather awareness', 'Confined space entry competency where applicable'),
  ('GOV-EMERG', 'Firefighter', 'Structural and veld fire response with breathing apparatus', 'Load bearing work in extreme heat under SCBA, casualty carriage', 'Command discipline under stress, no condition with sudden incapacity potential', 'Firefighter and breathing apparatus certification'),
  ('GOV-EMERG', 'Traffic Officer', 'Traffic enforcement and point duty', 'Prolonged outdoor standing and patrol driving', 'Sustained traffic vigilance, incident composure', 'Traffic officer diploma; driving licence'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'Pre hospital emergency care and patient transport', 'Patient lifting and carriage, response driving', 'Clinical protocol execution under pressure, no uncontrolled hypoglycaemic risk', 'HPCSA emergency care registration; PrDP'),
  ('GOV-EMERG', 'Fire Control Room Operator', 'Emergency call taking and dispatch', 'Sedentary shift duty', 'Sustained call vigilance, dispatch precision', 'None beyond induction'),
  ('GOV-EMERG', 'Disaster Management Officer', 'Disaster risk coordination and incident response', 'Field deployment during incidents, route driving', 'Multi agency coordination, incident command support', 'Driving licence')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('GOV-ADMIN', 'Municipal Office Administrator', 'I', 'Moderate', 'Sustained workstation ergonomic load'),
  ('GOV-ADMIN', 'Community Hall and Facility Caretaker', 'C', 'Moderate', 'Cleaning chemical use'),
  ('GOV-ADMIN', 'Community Hall and Facility Caretaker', 'I', 'Moderate', 'Furniture and equipment handling'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'I', 'High', 'Sustained grounds labour'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'A', 'Moderate', 'Mower and brush cutter noise'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('GOV-ADMIN', 'Parks and Recreation Worker', 'C', 'Moderate', 'Herbicide application'),
  ('GOV-ADMIN', 'Library and Community Centre Assistant', 'I', 'Moderate', 'Shelving and trolley work'),
  ('GOV-ADMIN', 'Cemetery Worker', 'I', 'High', 'Grave excavation labour'),
  ('GOV-ADMIN', 'Cemetery Worker', 'D', 'Moderate', 'Interment biological context'),
  ('GOV-ADMIN', 'Cemetery Worker', 'H', 'Moderate', 'Outdoor work in heat'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'I', 'High', 'Heavy road repair labour'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'A', 'Moderate', 'Compaction and cutting plant noise'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'B', 'Moderate', 'Road cutting and patching dust'),
  ('GOV-WORKS', 'Roads Maintenance Worker', 'H', 'Moderate', 'Roadworks in heat'),
  ('GOV-WORKS', 'Water and Sanitation Artisan', 'D', 'High', 'Sewer reticulation biological exposure'),
  ('GOV-WORKS', 'Water and Sanitation Artisan', 'F', 'Moderate', 'Valve chamber and manhole entry'),
  ('GOV-WORKS', 'Water and Sanitation Artisan', 'C', 'Moderate', 'Treatment chemical contact'),
  ('GOV-WORKS', 'Municipal Electrician', 'M', 'High', 'Public lighting and building electrical work'),
  ('GOV-WORKS', 'Municipal Electrician', 'E', 'Moderate', 'Pole and ladder access'),
  ('GOV-WORKS', 'Municipal Plant Operator', 'J', 'High', 'Municipal plant operation under the Driven Machinery Regulations, 2015'),
  ('GOV-WORKS', 'Municipal Plant Operator', 'A', 'Moderate', 'Plant cab noise'),
  ('GOV-WORKS', 'Municipal Plant Operator', 'B', 'Moderate', 'Works site dust'),
  ('GOV-WORKS', 'Building Maintenance Artisan', 'E', 'Moderate', 'Ladder and roof access'),
  ('GOV-WORKS', 'Building Maintenance Artisan', 'I', 'Moderate', 'Manual trade work'),
  ('GOV-WORKS', 'Building Maintenance Artisan', 'M', 'Moderate', 'Building electrical maintenance'),
  ('GOV-WORKS', 'Stormwater and Drainage Worker', 'F', 'Moderate', 'Culvert and chamber entry'),
  ('GOV-WORKS', 'Stormwater and Drainage Worker', 'D', 'High', 'Stormwater and debris biological exposure'),
  ('GOV-WORKS', 'Stormwater and Drainage Worker', 'I', 'High', 'Heavy debris clearance'),
  ('GOV-EMERG', 'Firefighter', 'H', 'High', 'Structural fire heat under breathing apparatus'),
  ('GOV-EMERG', 'Firefighter', 'I', 'High', 'Load bearing rescue and hose work'),
  ('GOV-EMERG', 'Firefighter', 'E', 'Moderate', 'Aerial appliance and roof work'),
  ('GOV-EMERG', 'Firefighter', 'C', 'Moderate', 'Combustion product exposure'),
  ('GOV-EMERG', 'Firefighter', 'K', 'High', 'Continuous shift and callout duty'),
  ('GOV-EMERG', 'Traffic Officer', 'J', 'Moderate', 'Patrol and pursuit driving'),
  ('GOV-EMERG', 'Traffic Officer', 'H', 'Moderate', 'Prolonged outdoor point duty'),
  ('GOV-EMERG', 'Traffic Officer', 'K', 'Moderate', 'Rotating enforcement shifts'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'D', 'High', 'Patient contact blood and body fluid exposure'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'I', 'High', 'Patient lifting and carriage'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'K', 'High', 'Continuous shift response duty'),
  ('GOV-EMERG', 'Ambulance Emergency Care Worker', 'J', 'High', 'Emergency response driving with PrDP requirement'),
  ('GOV-EMERG', 'Fire Control Room Operator', 'K', 'High', 'Standing overnight dispatch duty'),
  ('GOV-EMERG', 'Disaster Management Officer', 'K', 'Moderate', 'Incident activation duty'),
  ('GOV-EMERG', 'Disaster Management Officer', 'J', 'Moderate', 'Field deployment driving')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('GOV', 'OHS Act', 'Framework Act for municipal workplaces'),
  ('GOV', 'General Machinery Regulations, 1988', 'Municipal plant rooms, pump stations, and machinery supervision'),
  ('GOV', 'General Safety Regulations, 1986', 'First aid, PPE, and elevated position duties'),
  ('GOV', 'Driven Machinery Regulations', 'Municipal plant and lifting machine operator certificates'),
  ('GOV', 'Electrical Machinery and Installation Regulations', 'Public lighting and building electrical work'),
  ('GOV', 'HBA Regulations, 2022', 'Sewer, stormwater, cemetery, and patient contact biological exposure'),
  ('GOV', 'HCA Regulations, 2021', 'Herbicides, treatment chemicals, and combustion products'),
  ('GOV', 'NIHL Regulations, 2003', 'Operative noise instrument to 05/09/2026 for plant and grounds equipment'),
  ('GOV', 'Noise Exposure Regulations, 2024', 'Successor noise instrument from 06/09/2026'),
  ('GOV', 'Ergonomics Regulations, 2019', 'Road labour, patient handling, and workstation surveillance'),
  ('GOV', 'Environmental Regulations for Workplaces, 1987', 'Outdoor heat, fire heat, and confined atmospheres'),
  ('GOV', 'NRTA PrDP medical', 'Emergency response and municipal driving categories'),
  ('GOV', 'BCEA night work Code', 'Emergency services continuous shifts'),
  ('GOV', 'COIDA', 'Compensation route including PTSD as an occupational disease per the 2026 amendments for emergency personnel'),
  ('GOV', 'EEA section 7', 'Lawful basis for every medical test against inherent job requirements'),
  ('GOV', 'HPCSA Booklet 1', 'Ethical baseline for all examinations'),
  ('GOV', 'HPCSA Booklet 11', 'Perverse incentive prohibition; the employer is the payer')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified';

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status) values
('GOV', 4500, 35, 450, 'placeholder');

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['GOV-ADMIN','GOV-WORKS','GOV-EMERG']) loop
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
   set description = description || ' Update 13/08/2026 batch 11: the General Machinery Regulations, 1988 (GNR 1521, GG 11443, 5 August 1988) are now triple verified, closing a third leg of this item; the General Administrative Regulations remain open. A replacement draft General Machinery Regulation, 2025 (GN 6532, GG 53210) is in public comment and is held on the verification watchdog.'
 where item_code = 'CR-13.9';

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 11: firefighter and emergency care fitness rests on EEA section 7 inherent requirements read with service certification; no national statutory firefighter medical standard is stored, and any municipal or SANS 10090 aligned standard supplied by the client tightens the role protocol at review. Emergency services psychosocial load is carried in the OREP narrative with COIDA PTSD recognition noted.'
 where item_code = 'CR-12.1';


------------------------------------------------------------------------------
-- 021_msp_batch_education.sql
------------------------------------------------------------------------------

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


------------------------------------------------------------------------------
-- 022_msp_batch_office.sql
------------------------------------------------------------------------------

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


------------------------------------------------------------------------------
-- 023_msp_batch_held_constr_port_air.sql
------------------------------------------------------------------------------

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


------------------------------------------------------------------------------
-- 024_msp_batch_held_mining_hosp.sql
------------------------------------------------------------------------------

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


------------------------------------------------------------------------------
-- 025_msp_batch_held_manufacturing.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | TAX-BAT-16 v1.0.0 | Phase 6 batch 16: held subindustry completion, Manufacturing lines
-- No new instrument: roles seed against the verified corpus. Documentary basis 13/08/2026, subject to OMP ratification.

insert into msp_job_role (subindustry_id, title, duties_summary,
  inherent_physical_demands, inherent_sensory_cognitive_demands, statutory_competency_requirement)
select s.id, r.title, r.duties, r.phys, r.sens, r.statreq
from msp_subindustry s
join (values
  ('MANU-CHEM', 'Chemical Process Operator', 'Batch and continuous chemical process operation', 'Plant rounds with chemical handling', 'Process vigilance, permit discipline', 'Plant operation competency'),
  ('MANU-CHEM', 'Batch Blender and Mixer', 'Weighing, charging, and blending of chemical batches', 'Bag and drum charging, mixer operation', 'Formulation precision, exposure control discipline', 'None beyond induction'),
  ('MANU-CHEM', 'Chemical Warehouse and Drum Handler', 'Raw material and finished goods handling', 'Sustained drum and pallet handling, forklift operation', 'Segregation discipline, spill response', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('MANU-CHEM', 'Plant Laboratory Analyst', 'In process and quality testing', 'Bench work with sample handling', 'Analytical precision, fume control discipline', 'None beyond induction'),
  ('MANU-CHEM', 'Effluent Plant Operator', 'Effluent treatment and neutralisation', 'Dosing work with sump and tank access', 'Dosing precision, gas test discipline', 'Confined space entry competency where applicable'),
  ('MANU-AUTO', 'Assembly Line Operator', 'Vehicle and component assembly at takt', 'Sustained repetitive assembly at rate', 'Sequence accuracy under rate pressure', 'None beyond induction'),
  ('MANU-AUTO', 'Spray Booth Painter', 'Primer and topcoat spraying in booths', 'Spray work in supplied air or filtered PPE', 'Coating quality discipline, respirator discipline', 'None beyond induction'),
  ('MANU-AUTO', 'Body Shop Welder', 'Spot and MIG welding of body components', 'Sustained welding in fixtures', 'Weld quality discipline, fume control discipline', 'Welding competency'),
  ('MANU-AUTO', 'Press Shop Operator', 'Stamping press operation and die changes', 'Press feeding and die handling', 'Guarding discipline, press vigilance', 'None beyond induction'),
  ('MANU-AUTO', 'Quality Inspector (automotive)', 'In process and final inspection', 'Sustained standing inspection work', 'Defect recognition consistency', 'None beyond induction'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'Spinning frame and loom operation', 'Machine patrolling in noise and fibre dust', 'Thread break vigilance', 'None beyond induction'),
  ('MANU-TEX', 'Dye House Operator', 'Dyeing and chemical finishing processes', 'Wet work with dye and auxiliary chemicals in heat', 'Recipe precision, chemical discipline', 'None beyond induction'),
  ('MANU-TEX', 'Cutting and Sewing Machinist', 'Cutting and machine sewing at rate', 'Sustained repetitive machine work', 'Seam accuracy under rate pressure', 'None beyond induction'),
  ('MANU-TEX', 'Finishing and Pressing Operator', 'Pressing, steaming, and final finishing', 'Steam pressing in heat', 'Finish quality discipline', 'None beyond induction'),
  ('MANU-TEX', 'Textile Warehouse Assistant', 'Roll and bale handling', 'Sustained roll and bale handling', 'Stock rotation accuracy', 'None beyond induction'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'Mould setting and process optimisation', 'Mould handling, work at hot barrels', 'Process fault diagnosis, guarding discipline', 'None beyond induction'),
  ('MANU-PLASTIC', 'Extrusion Operator', 'Extrusion line operation', 'Line patrolling and die work', 'Line condition vigilance', 'None beyond induction'),
  ('MANU-PLASTIC', 'Granulation and Recycling Operator', 'Regrind and granulation operations', 'Feeding and bagging granulate', 'Feed control discipline', 'None beyond induction'),
  ('MANU-PLASTIC', 'Assembly and Finishing Operator (plastics)', 'Trimming, assembly, and packing', 'Sustained repetitive finishing at rate', 'Finish accuracy under rate pressure', 'None beyond induction'),
  ('MANU-PLASTIC', 'Material Handler (plastics)', 'Polymer and masterbatch logistics', 'Bag and octabin handling, forklift operation', 'Material identification accuracy', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable'),
  ('MANU-WOOD', 'Machine Woodworker', 'Saw, planer, and moulder operation', 'Timber feeding in dust and noise', 'Guarding and kickback discipline', 'None beyond induction'),
  ('MANU-WOOD', 'CNC Router Operator', 'CNC routing and nesting operations', 'Panel loading, machine supervision', 'Programme verification discipline', 'None beyond induction'),
  ('MANU-WOOD', 'Furniture Assembler', 'Component assembly and fitting', 'Sustained assembly handling', 'Fit quality discipline', 'None beyond induction'),
  ('MANU-WOOD', 'Wood Spray Finisher', 'Staining, sealing, and lacquer spraying', 'Booth spray work', 'Coating discipline, respirator discipline', 'None beyond induction'),
  ('MANU-WOOD', 'Timber Yard Worker', 'Timber receiving, stacking, and despatch', 'Heavy timber handling, forklift operation', 'Stack stability judgement', 'Lifting machine operator certification per the Driven Machinery Regulations, 2015 where applicable')
) as r(sub_code, title, duties, phys, sens, statreq) on s.code = r.sub_code;

insert into msp_job_hazard (job_role_id, hazard_id, typical_exposure_rating, rationale)
select jr.id, h.id, m.rating, m.rationale
from (values
  ('MANU-CHEM', 'Chemical Process Operator', 'C', 'High', 'Process chemical exposure with HCA biological monitoring where indicated'),
  ('MANU-CHEM', 'Chemical Process Operator', 'A', 'Moderate', 'Process plant noise'),
  ('MANU-CHEM', 'Chemical Process Operator', 'K', 'Moderate', 'Continuous process shifts'),
  ('MANU-CHEM', 'Batch Blender and Mixer', 'C', 'High', 'Charging and blending exposure peaks'),
  ('MANU-CHEM', 'Batch Blender and Mixer', 'I', 'Moderate', 'Bag and drum charging'),
  ('MANU-CHEM', 'Chemical Warehouse and Drum Handler', 'C', 'Moderate', 'Drummed chemical handling'),
  ('MANU-CHEM', 'Chemical Warehouse and Drum Handler', 'I', 'High', 'Sustained drum and pallet handling'),
  ('MANU-CHEM', 'Chemical Warehouse and Drum Handler', 'J', 'Moderate', 'Forklift operation under the Driven Machinery Regulations, 2015'),
  ('MANU-CHEM', 'Plant Laboratory Analyst', 'C', 'Moderate', 'Solvent and reagent handling'),
  ('MANU-CHEM', 'Effluent Plant Operator', 'C', 'Moderate', 'Neutralisation chemical handling'),
  ('MANU-CHEM', 'Effluent Plant Operator', 'D', 'Moderate', 'Effluent biological exposure'),
  ('MANU-CHEM', 'Effluent Plant Operator', 'F', 'Moderate', 'Sump and tank access'),
  ('MANU-AUTO', 'Assembly Line Operator', 'I', 'High', 'Sustained repetitive assembly at takt'),
  ('MANU-AUTO', 'Assembly Line Operator', 'A', 'Moderate', 'Assembly hall noise'),
  ('MANU-AUTO', 'Assembly Line Operator', 'K', 'Moderate', 'Production shift patterns'),
  ('MANU-AUTO', 'Spray Booth Painter', 'C', 'High', 'Isocyanate containing coating exposure with sensitiser surveillance'),
  ('MANU-AUTO', 'Spray Booth Painter', 'B', 'Moderate', 'Sanding and overspray particulate'),
  ('MANU-AUTO', 'Spray Booth Painter', 'A', 'Moderate', 'Booth and tool noise'),
  ('MANU-AUTO', 'Body Shop Welder', 'C', 'Moderate', 'Welding fume exposure'),
  ('MANU-AUTO', 'Body Shop Welder', 'A', 'Moderate', 'Body shop noise'),
  ('MANU-AUTO', 'Body Shop Welder', 'B', 'Moderate', 'Welding particulate'),
  ('MANU-AUTO', 'Body Shop Welder', 'M', 'Moderate', 'Welding electrical systems'),
  ('MANU-AUTO', 'Press Shop Operator', 'A', 'High', 'Stamping press noise'),
  ('MANU-AUTO', 'Press Shop Operator', 'I', 'Moderate', 'Press feeding and die handling'),
  ('MANU-AUTO', 'Press Shop Operator', 'G', 'Moderate', 'Press vibration exposure'),
  ('MANU-AUTO', 'Quality Inspector (automotive)', 'I', 'Moderate', 'Sustained standing inspection'),
  ('MANU-AUTO', 'Quality Inspector (automotive)', 'A', 'Moderate', 'Production hall noise'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'A', 'High', 'Loom and frame noise'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'B', 'Moderate', 'Cotton and fibre dust with byssinosis context'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'I', 'Moderate', 'Machine patrolling and piecing'),
  ('MANU-TEX', 'Spinning and Weaving Machine Operator', 'K', 'Moderate', 'Continuous mill shifts'),
  ('MANU-TEX', 'Dye House Operator', 'C', 'High', 'Dye and auxiliary chemical exposure'),
  ('MANU-TEX', 'Dye House Operator', 'H', 'Moderate', 'Dye house heat and steam'),
  ('MANU-TEX', 'Dye House Operator', 'I', 'Moderate', 'Wet fabric handling'),
  ('MANU-TEX', 'Cutting and Sewing Machinist', 'I', 'High', 'Sustained repetitive machine sewing'),
  ('MANU-TEX', 'Cutting and Sewing Machinist', 'A', 'Moderate', 'Machine floor noise'),
  ('MANU-TEX', 'Finishing and Pressing Operator', 'H', 'Moderate', 'Steam pressing heat'),
  ('MANU-TEX', 'Finishing and Pressing Operator', 'I', 'Moderate', 'Sustained pressing work'),
  ('MANU-TEX', 'Finishing and Pressing Operator', 'C', 'Moderate', 'Finishing chemical exposure'),
  ('MANU-TEX', 'Textile Warehouse Assistant', 'I', 'Moderate', 'Roll and bale handling'),
  ('MANU-TEX', 'Textile Warehouse Assistant', 'B', 'Moderate', 'Fibre dust in storage'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'H', 'Moderate', 'Hot barrel and mould work'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'C', 'Moderate', 'Polymer fume at purging'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'A', 'Moderate', 'Moulding hall noise'),
  ('MANU-PLASTIC', 'Injection Moulding Machine Setter', 'I', 'Moderate', 'Mould handling'),
  ('MANU-PLASTIC', 'Extrusion Operator', 'A', 'Moderate', 'Extrusion line noise'),
  ('MANU-PLASTIC', 'Extrusion Operator', 'C', 'Moderate', 'Polymer fume at the die'),
  ('MANU-PLASTIC', 'Extrusion Operator', 'K', 'Moderate', 'Continuous line shifts'),
  ('MANU-PLASTIC', 'Granulation and Recycling Operator', 'A', 'Moderate', 'Granulator noise'),
  ('MANU-PLASTIC', 'Granulation and Recycling Operator', 'B', 'Moderate', 'Regrind dust'),
  ('MANU-PLASTIC', 'Granulation and Recycling Operator', 'I', 'Moderate', 'Feeding and bagging work'),
  ('MANU-PLASTIC', 'Assembly and Finishing Operator (plastics)', 'I', 'High', 'Sustained repetitive finishing at rate'),
  ('MANU-PLASTIC', 'Assembly and Finishing Operator (plastics)', 'K', 'Moderate', 'Production shift patterns'),
  ('MANU-PLASTIC', 'Material Handler (plastics)', 'I', 'Moderate', 'Bag and octabin handling'),
  ('MANU-PLASTIC', 'Material Handler (plastics)', 'J', 'Moderate', 'Forklift operation under the Driven Machinery Regulations, 2015'),
  ('MANU-WOOD', 'Machine Woodworker', 'B', 'High', 'Hardwood and softwood dust with sensitiser context'),
  ('MANU-WOOD', 'Machine Woodworker', 'A', 'High', 'Saw and moulder noise'),
  ('MANU-WOOD', 'Machine Woodworker', 'I', 'Moderate', 'Timber feeding work'),
  ('MANU-WOOD', 'CNC Router Operator', 'B', 'Moderate', 'Routing dust'),
  ('MANU-WOOD', 'CNC Router Operator', 'A', 'Moderate', 'Router noise'),
  ('MANU-WOOD', 'Furniture Assembler', 'I', 'High', 'Sustained assembly handling'),
  ('MANU-WOOD', 'Furniture Assembler', 'A', 'Moderate', 'Workshop noise'),
  ('MANU-WOOD', 'Wood Spray Finisher', 'C', 'High', 'Lacquer and solvent spray exposure'),
  ('MANU-WOOD', 'Wood Spray Finisher', 'B', 'Moderate', 'Sanding dust'),
  ('MANU-WOOD', 'Timber Yard Worker', 'I', 'High', 'Heavy timber handling'),
  ('MANU-WOOD', 'Timber Yard Worker', 'B', 'Moderate', 'Yard timber dust'),
  ('MANU-WOOD', 'Timber Yard Worker', 'J', 'Moderate', 'Forklift operation under the Driven Machinery Regulations, 2015')
) as m(sub_code, title, hazard_code, rating, rationale)
join msp_subindustry s on s.code = m.sub_code
join msp_job_role jr on jr.subindustry_id = s.id and jr.title = m.title
join msp_hazard h on h.code = m.hazard_code;

do $$
declare
  v_code text; v_roles int; v_unmapped int; v_unprotocolled int;
begin
  for v_code in select unnest(array['MANU-CHEM','MANU-AUTO','MANU-TEX','MANU-PLASTIC','MANU-WOOD']) loop
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
           notes = 'Batch 16 role map seeded; gate passed'
     where code = v_code;
    raise notice 'batch gate: % enabled (% roles)', v_code, v_roles;
  end loop;
end $$;

-- Register updates

update msp_confirmation_item
   set description = description || ' Update 13/08/2026 batch 16: isocyanate spray painting and wood dust carry respiratory sensitiser surveillance under the HCA framework with spirometry emphasis; cotton dust carries the byssinosis context. Substance specific OEL confirmations for isocyanates, wood dust, and cotton dust remain open under the OEL item and values are applied from the HCA annexure at examination.'
 where item_code = 'CR-12.1';


------------------------------------------------------------------------------
-- 026_msp_register_closures.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | REG-CLS-01 v1.0.0 | Register closures from documentary verification 14/08/2026
-- Closes CR-13.10, CR-13.8, CR-12.2, CR-12.4; appends findings to CR-12.3. Subject to OMP ratification.

-- 1. Noise Exposure Regulations, 2024: confirmed gazette details and values (closes CR-13.10)

update msp_legal_instrument
   set gazette_reference = 'GN 5953, GG 52226, 6 March 2025; NIHL Regulations, 2003 repealed 18 months from publication (06/09/2026)',
       amendment_history = coalesce(amendment_history, '') || ' Confirmed 14/08/2026: published with the Physical Agents Regulations, 2024 and the Code of Practice for Audiometry with explanatory notes. The 85 dB(A) noise rating limit is retained, and a new action level of 82 dB(A) for continuous noise and 135 dB(C) for impulse noise applies where there is concomitant exposure to ototoxic chemical agents or whole body vibration. An exemption notice process under regulation 8(3) is recorded in 2025 to 2026 practice.'
 where short_name = 'Noise Exposure Regulations, 2024';

update msp_hazard
   set oel_instrument = 'Noise-Induced Hearing Loss Regulations, 2003, GN R.307, in force to 05/09/2026; from 06/09/2026 the Noise Exposure Regulations, 2024 (GN 5953, GG 52226) retain the 85 dB(A) noise rating limit and add an action level of 82 dB(A) continuous and 135 dB(C) impulse where ototoxic chemical or whole body vibration co exposure exists'
 where code = 'A';

update msp_kernel_rule
   set description = 'From 06/09/2026 noise citations swap from the NIHL Regulations, 2003 to the Noise Exposure Regulations, 2024. The 85 dB(A) noise rating limit carries over unchanged; the 2024 Regulations add an 82 dB(A) continuous and 135 dB(C) impulse action level for co exposure with ototoxic chemical agents or whole body vibration, which tightens surveillance triggers and never loosens them. The Code of Practice for Audiometry published with the 2024 Regulations governs audiometric method from the transition date.'
 where rule_code = 'RULE-NOISE-TRANSITION';

update msp_confirmation_item
   set description = description || ' Resolved 14/08/2026: the Noise Exposure Regulations, 2024 (GN 5953, GG 52226, 6 March 2025) retain the 85 dB(A) noise rating limit and add an 82 dB(A) continuous and 135 dB(C) impulse action level for ototoxic or vibration co exposure. Hazard A citation, transition rule, and audiometry code references updated.',
       status = 'resolved',
       resolution = 'NER 2024 values confirmed from the gazetted text and legal commentaries; 85 dB(A) retained, 82 dB(A) and 135 dB(C) co exposure action level added; kernel updated.',
       resolved_by = 'Claude Code build agent, documentary verification, subject to OMP ratification',
       resolved_on = '2026-08-14'
 where item_code = 'CR-13.10';

-- 2. PrDP medical provision (closes CR-13.8)

update msp_legal_instrument
   set full_citation = 'National Road Traffic Act 93 of 1996, Chapter 13 professional driving permits, read with the National Road Traffic Regulations, 2000 (GNR 225 of 17 March 2000), regulations 115 to 117: regulation 115 sets the categories of drivers requiring a professional driving permit, and regulation 117(b) disqualifies an applicant who is not medically fit, evidenced by the prescribed medical certificate form completed by a registered health practitioner.'
 where short_name = 'NRTA PrDP medical';

update msp_confirmation_item
   set description = description || ' Resolved 14/08/2026: the PrDP medical requirement sits in the National Road Traffic Regulations, 2000 (GNR 225 of 17 March 2000), regulations 115 to 117, with regulation 117(b) as the medical fitness disqualification and the prescribed medical certificate form as the evidence instrument.',
       status = 'resolved',
       resolution = 'NRTR 2000 regulations 115 to 117 confirmed from the published regulation text, the official medical certificate form, and the official PrDP service description.',
       resolved_by = 'Claude Code build agent, documentary verification, subject to OMP ratification',
       resolved_on = '2026-08-14'
 where item_code = 'CR-13.8';

-- 3. COIDA circular instructions (closes CR-12.2)

update msp_confirmation_item
   set description = description || ' Resolved 14/08/2026: Circular Instruction 171 (determination of permanent disablement from noise induced hearing loss, 2001) and Circular Instruction 172 (post traumatic stress disorder, in effect 1 April 2003) verified from the full instruction texts. The occupational disease series is recorded as CI 173 mesothelioma, CI 174 occupational lung cancer, CI 175 byssinosis, CI 176 occupational asthma, CI 177 irritant induced asthma, CI 178 pulmonary tuberculosis in healthcare workers, CI 179 pulmonary tuberculosis with silica dust exposure, and CI 180 work related upper limb disorders. Current version status per instruction remains subject to Compensation Fund publication practice and is checked at citation time.',
       status = 'resolved',
       resolution = 'CI 171 and CI 172 verified from full texts; CI 173 to 180 series recorded from corroborating academic and practice sources; per citation currency check retained.',
       resolved_by = 'Claude Code build agent, documentary verification, subject to OMP ratification',
       resolved_on = '2026-08-14'
 where item_code = 'CR-12.2';

-- 4. Retention periods (closes CR-12.4 with the documented per class framework)

update msp_confirmation_item
   set description = description || ' Resolved 14/08/2026 per record class: the HCA Regulations, 2021 require air monitoring records kept 30 years and investigation records 3 years, and removed the explicit medical surveillance retention clause of the 1995 Regulations; the HBA Regulations, 2022 require records including the risk assessment kept a minimum of 40 years. Care Net house policy therefore retains all medical surveillance records for 40 years, adopting the longest applicable statutory period as the floor per the tighten never loosen principle. ODMWA and MHSA record classes follow the Medical Bureau for Occupational Diseases and mine code of practice requirements where those apply.',
       status = 'resolved',
       resolution = 'HCA 30 year air monitoring and HBA 40 year record duties verified; 40 year house floor adopted for medical surveillance records pending OMP ratification.',
       resolved_by = 'Claude Code build agent, documentary verification, subject to OMP ratification',
       resolved_on = '2026-08-14'
 where item_code = 'CR-12.4';

-- 5. SANS item: append the audiometry code finding, item stays open for licensed editions

update msp_confirmation_item
   set description = description || ' Update 14/08/2026: the Code of Practice for Audiometry with explanatory notes is published with the Noise Exposure Regulations, 2024 by the Department of Employment and Labour and governs audiometric method from 06/09/2026. SANS edition numbers themselves still require licensed copies and this item stays open for them.'
 where item_code = 'CR-12.3';


------------------------------------------------------------------------------
-- 027_msp_constr_instrument_backfill.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | REG-CLS-02 v1.0.0 | Construction industry instrument backfill 14/08/2026
-- Instruments verified in later batches that apply to Construction but were never joined to it.

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('CONSTR', 'Driven Machinery Regulations', 'Crane, hoist, and lifting machine operator medical certificates of fitness per regulation 18'),
  ('CONSTR', 'General Safety Regulations, 1986', 'First aid, PPE, elevated positions, and ladder duties on construction sites'),
  ('CONSTR', 'General Administrative Regulations, 2003', 'Incident reporting and health and safety representative duties'),
  ('CONSTR', 'Environmental Regulations for Workplaces, 1987', 'Outdoor and hot work thermal environments; fitness certification for hot work per regulation 5(4)')
) as m(icode, short_name, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = m.short_name and li.status = 'verified'
where not exists (
  select 1 from msp_industry_instrument x
   where x.industry_id = i.id and x.instrument_id = li.id
);

update msp_confirmation_item
   set description = description || ' Update 14/08/2026: the Construction industry instrument map is backfilled with the Driven Machinery Regulations, General Safety Regulations, 1986, General Administrative Regulations, 2003, and Environmental Regulations for Workplaces, 1987, all verified in later batches and applicable to construction work. Future instrument verifications must sweep existing industry maps as part of the batch pattern.'
 where item_code = 'CR-12.1';


------------------------------------------------------------------------------
-- 028_msp_dmr_industry_sweep.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | REG-CLS-03 v1.0.0 | Driven Machinery Regulations industry map sweep 14/08/2026
-- Industries whose role maps cite lifting machine operation but predate the DMR verification.

insert into msp_industry_instrument (industry_id, instrument_id, applicability_note)
select i.id, li.id, m.note
from msp_industry i
join (values
  ('MANU',   'Forklift and lifting machine operator medical certificates of fitness per regulation 18'),
  ('MINING', 'Surface lifting machine operator medical certificates of fitness per regulation 18, alongside the MHSA regime underground'),
  ('TRANS',  'Forklift, reach truck, crane, and terminal lifting machine operator medical certificates of fitness per regulation 18')
) as m(icode, note) on i.code = m.icode
join msp_legal_instrument li on li.short_name = 'Driven Machinery Regulations' and li.status = 'verified'
where not exists (
  select 1 from msp_industry_instrument x
   where x.industry_id = i.id and x.instrument_id = li.id
);

do $$
declare v_missing int;
begin
  select count(*) into v_missing
    from (
      select distinct i.id
        from msp_job_role r
        join msp_subindustry s on s.id = r.subindustry_id
        join msp_industry i on i.id = s.industry_id
       where r.statutory_competency_requirement ilike '%Driven Machinery%'
          or exists (select 1 from msp_job_hazard jh where jh.job_role_id = r.id and jh.rationale ilike '%Driven Machinery%')
    ) ri
   where not exists (
      select 1 from msp_industry_instrument ii
       join msp_legal_instrument li on li.id = ii.instrument_id and li.short_name = 'Driven Machinery Regulations'
      where ii.industry_id = ri.id);
  if v_missing > 0 then
    raise exception 'DMR sweep gate: % industries still cite lifting machine work without the instrument mapping', v_missing;
  end if;
  raise notice 'DMR sweep gate: all citing industries mapped';
end $$;


------------------------------------------------------------------------------
-- 029_msp_r638_dedup.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | REG-CLS-04 v1.0.0 | R638 instrument and protocol deduplication 14/08/2026
-- Batch 7 introduced a second R638 instrument alongside the batch 1 'FCD Act R638, 2018' row,
-- and a second food handler protocol. One instrument, one protocol: the fuller batch 7 rows win.

do $$
declare
  v_old uuid; v_new uuid; v_old_protocol uuid; v_refs int;
begin
  select id into v_old from msp_legal_instrument where short_name = 'FCD Act R638, 2018';
  select id into v_new from msp_legal_instrument where short_name = 'Food Premises Hygiene Regulations, R638 of 2018';
  if v_old is null or v_new is null then
    raise notice 'R638 dedup: nothing to do';
    return;
  end if;

  select id into v_old_protocol
    from msp_test_protocol
   where legal_basis_id = v_old and test_name = 'Food handler fitness assessment';

  -- Guard: the old protocol must be unreferenced by any stored draft stage output.
  if v_old_protocol is not null then
    select count(*) into v_refs from msp_draft where stage_output::text like '%' || v_old_protocol || '%';
    if v_refs > 0 then
      raise exception 'R638 dedup: old protocol % is referenced by % draft rows', v_old_protocol, v_refs;
    end if;
    delete from msp_test_protocol where id = v_old_protocol;
  end if;

  -- Repoint industry maps that still cite the old instrument, skipping industries already on the new one.
  update msp_industry_instrument ii
     set instrument_id = v_new
   where ii.instrument_id = v_old
     and not exists (select 1 from msp_industry_instrument x
                      where x.industry_id = ii.industry_id and x.instrument_id = v_new);
  delete from msp_industry_instrument where instrument_id = v_old;

  -- Repoint any remaining protocol bases, then retire the duplicate instrument through the exclusion log.
  update msp_test_protocol set legal_basis_id = v_new where legal_basis_id = v_old;

  -- Not routed through msp_exclude_instrument: the exclusion register records gate
  -- failures (a, b, c) and this is a duplication, not a verification failure.
  update msp_legal_instrument
     set status = 'excluded',
         amendment_history = coalesce(amendment_history, '') || ' Retired 14/08/2026 as a duplicate of the Food Premises Hygiene Regulations, R638 of 2018 record; all references repointed. Not a verification failure.'
   where id = v_old;

  insert into msp_audit (actor, event_type, event_detail)
  values ('Claude Code build agent', 'kernel_hygiene',
          jsonb_build_object('action', 'instrument_dedup',
                             'retired_instrument', 'FCD Act R638, 2018',
                             'surviving_instrument', 'Food Premises Hygiene Regulations, R638 of 2018',
                             'reason', 'duplicate record, references repointed, duplicate protocol removed'));

  raise notice 'R638 dedup complete: % retired in favour of %', v_old, v_new;
end $$;

update msp_confirmation_item
   set description = description || ' Update 14/08/2026: the duplicate FCD Act R638, 2018 instrument row from batch 1 is retired in favour of the fuller batch 7 Food Premises Hygiene Regulations record; the MANU industry map and the food handler protocol are deduplicated so a pack never prescribes the same assessment twice.'
 where item_code = 'CR-12.1';


------------------------------------------------------------------------------
-- 030_msp_cognitive_kernel_product.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | KRN-PROD-01 v1.0.0 | Cognitive Kernel productisation 14/08/2026
-- Version control, monthly agent harness, OMP industry review queue, client auth linkage,
-- and the 100 medicals per year free qualification rule. A Care Net Consultants product.

-- 1. Kernel version control ----------------------------------------------------

create table msp_kernel_version (
  id uuid primary key default gen_random_uuid(),
  semver text not null unique,
  released_on date not null default current_date,
  change_summary text not null,
  kernel_counts jsonb not null,
  omp_ratified boolean not null default false,
  ratified_by text,
  ratified_on date,
  created_by text not null
);
comment on table msp_kernel_version is 'Cognitive Kernel release register. Every content release gets a semver row; OMP ratification is recorded per release and the release is not citable as ratified until it is.';

alter table msp_kernel_version enable row level security;
create policy msp_kernel_version_read on msp_kernel_version
  for select to authenticated using (true);

create or replace function msp_kernel_counts()
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'instruments_verified', (select count(*) from msp_legal_instrument where status = 'verified'),
    'instruments_pending',  (select count(*) from msp_legal_instrument where status = 'pending'),
    'instruments_excluded', (select count(*) from msp_legal_instrument where status = 'excluded'),
    'industries',           (select count(*) from msp_industry),
    'subindustries',        (select count(*) from msp_subindustry),
    'selectable',           (select count(*) from msp_subindustry where selectable),
    'roles',                (select count(*) from msp_job_role),
    'hazard_links',         (select count(*) from msp_job_hazard),
    'protocols',            (select count(*) from msp_test_protocol),
    'register_open',        (select count(*) from msp_confirmation_item where status = 'open'),
    'register_resolved',    (select count(*) from msp_confirmation_item where status = 'resolved'));
$$;

create or replace function msp_kernel_release(p_semver text, p_summary text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'kernel release requires the forge_admin role';
  end if;
  insert into msp_kernel_version (semver, change_summary, kernel_counts, created_by)
  values (p_semver, p_summary, msp_kernel_counts(), 'msp_kernel_release');
  insert into msp_audit (actor, event_type, event_detail)
  values ('msp_kernel_release', 'kernel_release',
          jsonb_build_object('semver', p_semver, 'summary', p_summary));
  return jsonb_build_object('semver', p_semver, 'counts', msp_kernel_counts());
end;
$$;
revoke execute on function msp_kernel_release(text, text) from public, anon;

insert into msp_kernel_version (semver, change_summary, kernel_counts, created_by)
values ('1.0.0',
        'First complete release of the Care Net Cognitive Kernel: migrations 001 to 029. Full South African taxonomy (17 industries, 56 selectable subindustries), 31 triple verified instruments, deduplicated protocol set, register closures for the NER 2024 noise values, PrDP provision, COIDA circular instructions, and retention framework. Subject to OMP ratification per release.',
        msp_kernel_counts(),
        'Claude Code build agent');

-- 2. Monthly agent harness: continuous learning and correctness audit -----------

create table msp_kernel_agent_run (
  id uuid primary key default gen_random_uuid(),
  run_on timestamptz not null default now(),
  kind text not null check (kind in ('monthly_audit', 'learning_update')),
  report jsonb not null,
  outcome text not null check (outcome in ('clean', 'findings', 'failed'))
);
comment on table msp_kernel_agent_run is 'Every run of the Cognitive Kernel maintenance agent lands here: the scheduled monthly correctness audit, and each learning update the agent applies after verification.';

alter table msp_kernel_agent_run enable row level security;
create policy msp_kernel_agent_run_read on msp_kernel_agent_run
  for select to authenticated using (msp_has_role('forge_omp') or msp_has_role('forge_admin') or msp_has_role('forge_verifier'));

create or replace function msp_kernel_monthly_audit()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_due jsonb;
  v_unprotocolled int;
  v_dash int := 0;
  v_rec record;
  v_cnt int;
  v_report jsonb;
  v_outcome text;
begin
  select coalesce(jsonb_agg(jsonb_build_object('short_name', short_name, 'review_due', review_due)), '[]'::jsonb)
    into v_due from msp_verification_due;

  select count(*) into v_unprotocolled
    from msp_hazard h
   where not exists (select 1 from msp_test_protocol tp where tp.hazard_id = h.id)
     and h.code not in ('O','N');

  for v_rec in
    select table_name, column_name
      from information_schema.columns
     where table_schema = 'public' and table_name like 'msp\_%'
       and data_type in ('text', 'character varying')
  loop
    execute format('select count(*) from %I where %I ~ ''—|–''', v_rec.table_name, v_rec.column_name) into v_cnt;
    v_dash := v_dash + v_cnt;
  end loop;

  v_report := jsonb_build_object(
    'counts', msp_kernel_counts(),
    'verification_due', v_due,
    'unprotocolled_hazards', v_unprotocolled,
    'dash_violations', v_dash,
    'current_version', (select semver from msp_kernel_version order by released_on desc, semver desc limit 1));

  v_outcome := case when jsonb_array_length(v_due) > 0 or v_unprotocolled > 0 or v_dash > 0
                    then 'findings' else 'clean' end;

  insert into msp_kernel_agent_run (kind, report, outcome) values ('monthly_audit', v_report, v_outcome);
  insert into msp_audit (actor, event_type, event_detail)
  values ('kernel maintenance agent', 'kernel_monthly_audit', v_report || jsonb_build_object('outcome', v_outcome));

  return v_report || jsonb_build_object('outcome', v_outcome);
end;
$$;
revoke execute on function msp_kernel_monthly_audit() from public, anon;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('msp-kernel-monthly-audit', '0 6 1 * *', 'select msp_kernel_monthly_audit()');
    raise notice 'monthly audit scheduled: first day of each month, 06:00 UTC';
  else
    raise notice 'pg_cron not installed: schedule msp_kernel_monthly_audit() via the dashboard or the maintenance agent';
  end if;
exception when others then
  raise notice 'cron scheduling skipped: %', sqlerrm;
end $$;

-- 3. OMP industry review queue: demos and ratification across the taxonomy ------

create table msp_omp_industry_review (
  id uuid primary key default gen_random_uuid(),
  industry_code text not null unique,
  industry_name text not null,
  status text not null default 'pending'
    check (status in ('pending', 'demo_run', 'approved', 'changes_requested')),
  reviewed_by text,
  hpcsa_number text,
  reviewed_on date,
  notes text
);
comment on table msp_omp_industry_review is 'The OMP reviews every industry: run the demo pack, test the prescriptions, then approve or request changes. Kernel recommendations deploy per industry only once its row is approved.';

alter table msp_omp_industry_review enable row level security;
create policy msp_omp_industry_review_read on msp_omp_industry_review
  for select to authenticated using (true);

insert into msp_omp_industry_review (industry_code, industry_name)
select code, name from msp_industry order by code;

create or replace function msp_omp_review_industry(
  p_industry_code text, p_status text, p_reviewed_by text, p_hpcsa_number text, p_notes text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not msp_caller_is('forge_omp') then
    raise exception 'industry review requires the forge_omp role';
  end if;
  if p_status in ('approved', 'changes_requested')
     and (coalesce(btrim(p_reviewed_by), '') = '' or coalesce(btrim(p_hpcsa_number), '') = '') then
    raise exception 'an approval or change request requires the reviewing OMP name and HPCSA number';
  end if;
  update msp_omp_industry_review
     set status = p_status, reviewed_by = p_reviewed_by, hpcsa_number = p_hpcsa_number,
         reviewed_on = current_date, notes = p_notes
   where industry_code = upper(p_industry_code);
  if not found then
    raise exception 'unknown industry code %', p_industry_code;
  end if;
  insert into msp_audit (actor, event_type, event_detail)
  values (p_reviewed_by, 'omp_industry_review',
          jsonb_build_object('industry_code', upper(p_industry_code), 'status', p_status, 'hpcsa_number', p_hpcsa_number));
  return jsonb_build_object('industry_code', upper(p_industry_code), 'status', p_status);
end;
$$;
revoke execute on function msp_omp_review_industry(text, text, text, text, text) from public, anon;

-- 4. Client accounts linked to Supabase Auth ------------------------------------

alter table msp_client_account
  add column auth_user_id uuid unique references auth.users(id),
  add column annual_medicals_estimate int;

create policy msp_client_account_own on msp_client_account
  for select to authenticated using (auth_user_id = auth.uid());

comment on column msp_client_account.auth_user_id is 'Supabase Auth linkage: every client contact becomes an auth user so packs, revisions, and the review journey are served under their own login.';
comment on column msp_client_account.annual_medicals_estimate is 'Self declared occupational medicals per year with Care Net; at or above the free qualification threshold the assessment tool is free, verified by a consultant before the waiver is confirmed.';

-- 5. The 100 medicals per year free qualification rule --------------------------

alter table msp_quote add column annual_medicals_estimate int;

create or replace function msp_create_quote(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate msp_pricing%rowtype;
  v_price numeric;
  v_status text;
  v_ref text;
  v_id uuid;
  v_emp int := coalesce((p->>'employee_count')::int, 0);
  v_jobs int := coalesce((p->>'job_category_count')::int, 0);
  v_medicals int := coalesce((p->>'annual_medicals_estimate')::int, 0);
begin
  if coalesce(p->>'company_name','') = '' or coalesce(p->>'contact_email','') = '' then
    raise exception 'company name and contact email are required';
  end if;
  if v_emp < 1 or v_jobs < 1 then
    raise exception 'employee count and job category count must be at least one';
  end if;
  select * into v_rate from msp_pricing
   where industry_code = upper(p->>'industry_code')
   order by effective_from desc limit 1;
  if v_rate.id is null then
    raise exception 'no rate card for industry %; the quote routes to a consultant', p->>'industry_code';
  end if;
  if v_medicals >= 100 then
    v_price := 0;
    v_status := 'free_qualifying';
  else
    v_price := v_rate.base_fee_zar + v_rate.per_employee_zar * v_emp + v_rate.per_job_category_zar * v_jobs;
    v_status := case when v_rate.status = 'confirmed' then 'firm' else 'indicative' end;
  end if;
  v_ref := 'CNC-QTE-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(nextval('msp_quote_seq')::text, 3, '0');
  insert into msp_quote (quote_reference, company_name, contact_name, contact_email,
                         industry_code, company_size, employee_count, job_category_count,
                         annual_medicals_estimate, price_zar, price_status)
  values (v_ref, p->>'company_name', coalesce(p->>'contact_name',''), p->>'contact_email',
          upper(p->>'industry_code'), p->>'company_size', v_emp, v_jobs,
          v_medicals, v_price, v_status)
  returning id into v_id;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (null, 'webhook', 'quote_created',
          jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'price_zar', v_price,
                             'price_status', v_status, 'annual_medicals_estimate', v_medicals));
  return jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'price_zar', v_price,
                            'price_status', v_status, 'valid_until', current_date + 30);
end;
$$;
revoke execute on function msp_create_quote(jsonb) from public, anon, authenticated;

-- 6. Register entries ------------------------------------------------------------

insert into msp_confirmation_item (item_code, kind, description, status) values
('CR-13.15', 'confirm',
 'Free qualification rule: a client declaring 100 or more occupational medicals per year with Care Net receives the assessment tool free (quote priced at zero, status free_qualifying). The declaration is self reported at quote time and a consultant verifies the medicals volume before the waiver is confirmed on the invoice. Confirm the threshold and the verification workflow with commercial leadership.',
 'open'),
('CR-13.16', 'confirm',
 'Cognitive Kernel maintenance agent: the monthly audit function is in place and scheduled where pg_cron is available; the learning update leg requires a standing Claude agent session (or scheduled cloud session) wired to the Supabase project per SOP-KERNEL-AGENT.md. Confirm the agent schedule and the OMP ratification cadence per kernel release.',
 'open');


------------------------------------------------------------------------------
-- 031_msp_shop_journey.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | SHOP-01 v1.0.0 | Packages, SLA lookup, and the OMP review fee 14/08/2026
-- The commercial journey: login or create company, automatic SLA and volume lookup,
-- package selection (plan draft, or OMP reviewed and signed), and quote breakdowns.

-- 1. Packages -------------------------------------------------------------------

create table msp_package (
  id uuid primary key default gen_random_uuid(),
  package_code text not null unique,
  name text not null,
  description text not null,
  includes_omp_review boolean not null default false,
  omp_review_fee_zar numeric,
  fee_status text not null default 'placeholder' check (fee_status in ('placeholder', 'confirmed'))
);
comment on table msp_package is 'Shop packages. The plan draft is a watermarked working document and is never a released pack; only the OMP reviewed and signed package produces a released deliverable, per the database release gate. The OMP review fee is a placeholder pending the SASOM Guideline on Occupational Medicine Fee Structures and Practices (2025 edition), accessible through the designated OMP''s SASOM membership.';

alter table msp_package enable row level security;
create policy msp_package_read on msp_package for select to authenticated, anon using (true);

insert into msp_package (package_code, name, description, includes_omp_review, omp_review_fee_zar, fee_status) values
('DRAFT_PLAN', 'Medical Surveillance Plan, working draft',
 'The full structured assessment and an engine drafted Plan against the verified regulatory kernel for your industry, delivered as a watermarked working draft for internal planning. Not a released clinical document: it carries no OMP signature and every page is marked draft.',
 false, null, 'confirmed'),
('SIGNED_PLAN', 'Medical Surveillance Plan, OMP reviewed and signed',
 'Everything in the working draft, plus review by a registered Occupational Medical Practitioner: clinical recommendations, ratification of the surveillance battery, and signature. This is the released, board ready Plan hosted with revision control.',
 true, 2500, 'placeholder');

-- 2. SLA status on client accounts ----------------------------------------------

alter table msp_client_account
  add column sla_status text not null default 'none' check (sla_status in ('none', 'active_sla'));
comment on column msp_client_account.sla_status is 'Clients under an active service level agreement receive the assessment tool as an included benefit, alongside the 100 medicals per year qualification.';

-- 3. Company lookup for the signed in journey ------------------------------------

create or replace function msp_company_lookup(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account%rowtype;
begin
  select * into v_acc
    from msp_client_account
   where lower(contact_email) = lower(btrim(p_email))
   order by created_at desc
   limit 1;

  if v_acc.id is null then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object(
    'found', true,
    'company_name', v_acc.company_name,
    'account_kind', v_acc.account_kind,
    'sla_status', v_acc.sla_status,
    'annual_medicals_estimate', coalesce(v_acc.annual_medicals_estimate, 0),
    'tool_free', v_acc.sla_status = 'active_sla' or coalesce(v_acc.annual_medicals_estimate, 0) >= 100);
end;
$$;
revoke execute on function msp_company_lookup(text) from public, anon, authenticated;
comment on function msp_company_lookup is 'Server side only: the endpoint verifies the caller''s Supabase Auth token first and passes the authenticated email, so an account status is only ever revealed to its own signed in contact.';

-- 4. Quote with package and fee breakdown ----------------------------------------

alter table msp_quote
  add column package_code text default 'SIGNED_PLAN',
  add column omp_review_fee_zar numeric default 0;

create or replace function msp_create_quote(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate msp_pricing%rowtype;
  v_pkg msp_package%rowtype;
  v_base numeric;
  v_omp numeric := 0;
  v_status text;
  v_ref text;
  v_id uuid;
  v_emp int := coalesce((p->>'employee_count')::int, 0);
  v_jobs int := coalesce((p->>'job_category_count')::int, 0);
  v_medicals int := coalesce((p->>'annual_medicals_estimate')::int, 0);
  v_free boolean;
begin
  if coalesce(p->>'company_name','') = '' or coalesce(p->>'contact_email','') = '' then
    raise exception 'company name and contact email are required';
  end if;
  if v_emp < 1 or v_jobs < 1 then
    raise exception 'employee count and job category count must be at least one';
  end if;

  select * into v_pkg from msp_package
   where package_code = upper(coalesce(p->>'package_code', 'SIGNED_PLAN'));
  if v_pkg.id is null then
    raise exception 'unknown package %', p->>'package_code';
  end if;

  select * into v_rate from msp_pricing
   where industry_code = upper(p->>'industry_code')
   order by effective_from desc limit 1;
  if v_rate.id is null then
    raise exception 'no rate card for industry %; the quote routes to a consultant', p->>'industry_code';
  end if;

  v_free := v_medicals >= 100
            or exists (select 1 from msp_client_account
                        where lower(contact_email) = lower(p->>'contact_email')
                          and sla_status = 'active_sla');

  v_base := case when v_free then 0
                 else v_rate.base_fee_zar + v_rate.per_employee_zar * v_emp + v_rate.per_job_category_zar * v_jobs end;
  if v_pkg.includes_omp_review then
    v_omp := coalesce(v_pkg.omp_review_fee_zar, 0);
  end if;

  v_status := case
    when v_base + v_omp = 0 then 'free_qualifying'
    when v_rate.status = 'confirmed' and (not v_pkg.includes_omp_review or v_pkg.fee_status = 'confirmed') then 'firm'
    else 'indicative' end;

  v_ref := 'CNC-QTE-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(nextval('msp_quote_seq')::text, 3, '0');
  insert into msp_quote (quote_reference, company_name, contact_name, contact_email,
                         industry_code, company_size, employee_count, job_category_count,
                         annual_medicals_estimate, package_code, omp_review_fee_zar,
                         price_zar, price_status)
  values (v_ref, p->>'company_name', coalesce(p->>'contact_name',''), p->>'contact_email',
          upper(p->>'industry_code'), p->>'company_size', v_emp, v_jobs,
          v_medicals, v_pkg.package_code, v_omp,
          v_base + v_omp, v_status)
  returning id into v_id;

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (null, 'webhook', 'quote_created',
          jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'package', v_pkg.package_code,
                             'base_zar', v_base, 'omp_review_fee_zar', v_omp,
                             'price_zar', v_base + v_omp, 'price_status', v_status,
                             'tool_free', v_free, 'annual_medicals_estimate', v_medicals));

  return jsonb_build_object('quote_id', v_id, 'reference', v_ref,
                            'package_code', v_pkg.package_code, 'package_name', v_pkg.name,
                            'base_zar', v_base, 'omp_review_fee_zar', v_omp,
                            'price_zar', v_base + v_omp, 'tool_free', v_free,
                            'price_status', v_status, 'valid_until', current_date + 30);
end;
$$;
revoke execute on function msp_create_quote(jsonb) from public, anon, authenticated;

-- 5. Register --------------------------------------------------------------------

insert into msp_confirmation_item (item_code, kind, description, status) values
('CR-13.17', 'confirm',
 'OMP review and sign off fee: the shop carries a placeholder of R2,500 per Plan review, marked indicative on every quote until confirmed. The authoritative source is the SASOM Guideline on Occupational Medicine Fee Structures and Practices, 2025 edition, accessible through the designated OMP''s SASOM membership (SAS1270); public sources do not publish the tariff. Confirm the fee with the OMP and commercial leadership, then set msp_package.fee_status to confirmed.',
 'open');

update msp_confirmation_item
   set description = description || ' Update 14/08/2026: the free qualification now also applies to accounts with an active service level agreement (sla_status active_sla), checked automatically at quote time alongside the 100 medicals declaration.'
 where item_code = 'CR-13.15';


------------------------------------------------------------------------------
-- 032_msp_quote_status_fix.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | SHOP-02 v1.0.0 | Quote status constraint fix 14/08/2026
-- The msp_quote price_status check predates the free qualification rule and
-- rejected free_qualifying rows; caught by the shop journey test before any
-- client hit it.

alter table msp_quote drop constraint msp_quote_price_status_check;
alter table msp_quote add constraint msp_quote_price_status_check
  check (price_status in ('indicative', 'firm', 'free_qualifying'));

