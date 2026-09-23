-- Care Net medical surveillance framework | full rebuild script | regenerated 23/09/2026
-- Concatenation of every migration in order. Canonical source: supabase/migrations/.
-- The assistant edge function lives at supabase/functions/msp-assistant/index.ts.


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

------------------------------------------------------------------------------
-- 033_msp_public_industry_profile.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | PUB-01 v1.0.0 | Public industry profile view 14/08/2026
-- Marketing surface for the website industry pages. This view is deliberately
-- readable by anon: it carries only content Care Net publishes on its own site.
--
-- What it exposes: industry and subindustry names, the short names and
-- applicability notes of VERIFIED instruments, hazard names, protocol names, and
-- job role titles with counts.
-- What it never exposes: client or engagement data, intake responses, drafts,
-- OMP reviews, the confirmation register, pending or excluded instruments, and
-- the exposure values and clinical reference ranges inside the protocols.
--
-- The view runs with the owner's rights so the anon role never touches the
-- protected kernel tables directly. Any advisor notice about a definer view on
-- this object is expected and accepted: publication is the purpose.

create or replace view msp_public_industry_profile as
select
  i.code,
  i.name,
  i.regulatory_regime as regime,
  (select count(*) from msp_subindustry s where s.industry_id = i.id and s.selectable) as subindustry_count,
  (select count(*) from msp_job_role r
     join msp_subindustry s on s.id = r.subindustry_id
    where s.industry_id = i.id) as role_count,
  (select coalesce(json_agg(json_build_object('name', s.name, 'roles',
            (select coalesce(json_agg(r.title order by r.title), '[]'::json)
               from msp_job_role r where r.subindustry_id = s.id)) order by s.name), '[]'::json)
     from msp_subindustry s where s.industry_id = i.id and s.selectable) as subindustries,
  (select coalesce(json_agg(json_build_object('name', li.short_name, 'note', ii.applicability_note)
            order by li.short_name), '[]'::json)
     from msp_industry_instrument ii
     join msp_legal_instrument li on li.id = ii.instrument_id
    where ii.industry_id = i.id and li.status = 'verified') as instruments,
  (select coalesce(json_agg(distinct h.name), '[]'::json)
     from msp_job_hazard jh
     join msp_job_role r on r.id = jh.job_role_id
     join msp_subindustry s on s.id = r.subindustry_id
     join msp_hazard h on h.id = jh.hazard_id
    where s.industry_id = i.id) as hazards,
  (select coalesce(json_agg(distinct tp.test_name), '[]'::json)
     from msp_job_hazard jh
     join msp_job_role r on r.id = jh.job_role_id
     join msp_subindustry s on s.id = r.subindustry_id
     join msp_test_protocol tp on tp.hazard_id = jh.hazard_id
    where s.industry_id = i.id) as protocols
from msp_industry i;

comment on view msp_public_industry_profile is
  'Public marketing surface for the website industry pages. Aggregate, non clinical, no client data. Readable by anon on purpose.';

grant select on msp_public_industry_profile to anon, authenticated;

-- Public framework statistics for the website. Same principle: aggregate counts
-- and the released version only, nothing clinical, nothing about any client.

create or replace view msp_public_framework_stats as
select
  (select semver from msp_kernel_version order by released_on desc, semver desc limit 1) as version,
  (select count(*) from msp_legal_instrument where status = 'verified') as instruments,
  (select count(*) from msp_industry) as industries,
  (select count(*) from msp_subindustry where selectable) as subindustries,
  (select count(*) from msp_job_role) as roles,
  (select count(*) from msp_test_protocol) as protocols;

comment on view msp_public_framework_stats is
  'Public marketing statistics for the website. Aggregate only. Readable by anon on purpose.';

grant select on msp_public_framework_stats to anon, authenticated;

------------------------------------------------------------------------------
-- 034_msp_env_parameters_ai.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | ENV-01 v1.0.0, AI-01 v1.0.0 | Parameter store and AI connection 15/08/2026
-- Two things live here. First, a parameter store so the running system can be
-- retuned without a redeploy: model, effort, thresholds, schedules, ceilings.
-- Second, the ledger and the budget gate behind the AI connection, so every
-- call the assistant makes is recorded, priced, and stoppable.
--
-- Secrets never live in this table. The API key sits in Supabase secrets and the
-- service role key sits in Vercel. Where a parameter must point at a secret it
-- stores a reference, never a value, and a check constraint enforces that.

-- 1. The parameter store -------------------------------------------------------

create table msp_env_parameter (
  key           text primary key,
  value         text not null,
  value_type    text not null check (value_type in ('text','integer','decimal','boolean','date','enum')),
  allowed_values text[],
  min_value     numeric,
  max_value     numeric,
  category      text not null check (category in ('ai','agent','clinical','commercial','retention','integration')),
  description   text not null,
  updated_by    text not null default 'migration_034',
  updated_at    timestamptz not null default now(),
  -- A parameter whose name reads like a credential may only carry a reference.
  -- The pattern matches whole name segments, so ai.max_output_tokens is not
  -- mistaken for a credential while ai.api_key_ref is.
  constraint msp_env_parameter_no_secret_values check (
    key !~* '(^|[._-])(secret|password|api_key|apikey|api-key|token|private_key|credential)([._-]|$)'
    or value ~ '^(env:|vault:|supabase_secret:)'
  )
);
comment on table msp_env_parameter is
  'Runtime parameter store. Everything tunable without a redeploy: AI model and effort, agent schedule, clinical floors, commercial thresholds, spend ceilings. Never holds a secret value, only a reference to one.';
comment on column msp_env_parameter.allowed_values is
  'Permitted values for an enum parameter. Enforced by msp_env_set, not by the UI.';

create table msp_env_parameter_history (
  id          bigint generated always as identity primary key,
  key         text not null,
  old_value   text,
  new_value   text not null,
  changed_by  text not null,
  changed_at  timestamptz not null default now(),
  reason      text
);
comment on table msp_env_parameter_history is
  'Append only history of every parameter change. A tuning change is a change to how the plans come out, so it is evidence.';

create index msp_env_parameter_history_key_idx on msp_env_parameter_history(key, changed_at desc);

create or replace function msp_env_history_block_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'msp_env_parameter_history is append only';
end;
$$;

create trigger msp_env_history_no_update
  before update or delete on msp_env_parameter_history
  for each row execute function msp_env_history_block_mutation();

alter table msp_env_parameter enable row level security;
alter table msp_env_parameter_history enable row level security;

-- Any forge role may read the running configuration. Nobody writes directly:
-- writes go through msp_env_set so the history and the validation cannot be
-- bypassed.
create policy msp_env_parameter_read on msp_env_parameter
  for select to authenticated using (msp_any_forge_role());
create policy msp_env_parameter_history_read on msp_env_parameter_history
  for select to authenticated using (msp_has_role('forge_admin') or msp_has_role('forge_omp'));

-- 2. Read and write --------------------------------------------------------------

create or replace function msp_env_get(p_key text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select value from msp_env_parameter where key = p_key;
$$;
comment on function msp_env_get is 'Single parameter read. Definer so the server paths and the agent can read configuration without table grants.';

create or replace function msp_env_get_int(p_key text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select value::integer from msp_env_parameter where key = p_key and value_type = 'integer';
$$;

create or replace function msp_env_get_numeric(p_key text)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select value::numeric from msp_env_parameter
   where key = p_key and value_type in ('integer','decimal');
$$;

create or replace function msp_env_get_bool(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select value::boolean from msp_env_parameter where key = p_key and value_type = 'boolean';
$$;

-- The whole configuration for one category, as an object. This is what the AI
-- connection calls on every invocation so it never carries a hard coded model,
-- effort, ceiling or prompt version.
create or replace function msp_env_bundle(p_category text default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
    from msp_env_parameter
   where p_category is null or category = p_category;
$$;
comment on function msp_env_bundle is 'All parameters, or all parameters in one category, as a flat object. The AI connection reads its whole configuration through this in a single call.';

create or replace function msp_env_set(p_key text, p_value text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row msp_env_parameter%rowtype;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.role(), 'unknown');
  v_num numeric;
begin
  -- coalesce so a null JWT is a refusal, never a silent pass
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'changing a runtime parameter requires the forge_admin role';
  end if;

  select * into v_row from msp_env_parameter where key = p_key;
  if not found then
    raise exception 'unknown parameter %. Parameters are declared by migration, not created at runtime', p_key;
  end if;

  -- Type and range validation happens here, not in the caller. A bad value must
  -- never reach the running system.
  if v_row.value_type = 'integer' then
    if p_value !~ '^-?\d+$' then
      raise exception 'parameter % expects an integer, got %', p_key, p_value;
    end if;
    v_num := p_value::numeric;
  elsif v_row.value_type = 'decimal' then
    if p_value !~ '^-?\d+(\.\d+)?$' then
      raise exception 'parameter % expects a decimal, got %', p_key, p_value;
    end if;
    v_num := p_value::numeric;
  elsif v_row.value_type = 'boolean' then
    if lower(p_value) not in ('true','false') then
      raise exception 'parameter % expects true or false, got %', p_key, p_value;
    end if;
  elsif v_row.value_type = 'date' then
    begin
      perform p_value::date;
    exception when others then
      raise exception 'parameter % expects a date in YYYY-MM-DD form, got %', p_key, p_value;
    end;
  elsif v_row.value_type = 'enum' then
    if v_row.allowed_values is null or not (p_value = any(v_row.allowed_values)) then
      raise exception 'parameter % expects one of %, got %',
        p_key, array_to_string(v_row.allowed_values, ', '), p_value;
    end if;
  end if;

  if v_num is not null then
    if v_row.min_value is not null and v_num < v_row.min_value then
      raise exception 'parameter % has a floor of %, got %', p_key, v_row.min_value, p_value;
    end if;
    if v_row.max_value is not null and v_num > v_row.max_value then
      raise exception 'parameter % has a ceiling of %, got %', p_key, v_row.max_value, p_value;
    end if;
  end if;

  update msp_env_parameter
     set value = p_value, updated_by = v_actor, updated_at = now()
   where key = p_key;

  insert into msp_env_parameter_history (key, old_value, new_value, changed_by, reason)
  values (p_key, v_row.value, p_value, v_actor, p_reason);

  insert into msp_audit (actor, event_type, event_detail)
  values (v_actor, 'env_parameter_change',
          jsonb_build_object('key', p_key, 'from', v_row.value, 'to', p_value, 'reason', p_reason));

  return jsonb_build_object('key', p_key, 'old_value', v_row.value, 'new_value', p_value,
                            'changed_by', v_actor, 'changed_at', now());
end;
$$;
comment on function msp_env_set is
  'The only write path into the parameter store. Validates type, enum membership and range, records history, writes an audit event. forge_admin only.';

revoke all on function msp_env_set(text, text, text) from public, anon;
grant execute on function msp_env_set(text, text, text) to authenticated;
grant execute on function msp_env_get(text), msp_env_get_int(text), msp_env_get_numeric(text),
  msp_env_get_bool(text), msp_env_bundle(text) to authenticated;

-- 3. The declared parameters -----------------------------------------------------
-- Values here are the ones the system is actually running on today. Where a value
-- is a placeholder awaiting a Care Net decision it is marked in the description
-- and carried in the confirmation register, not silently presented as settled.

insert into msp_env_parameter (key, value, value_type, allowed_values, min_value, max_value, category, description) values
  -- AI connection
  ('ai.model', 'claude-opus-5', 'enum',
   array['claude-opus-5','claude-sonnet-5','claude-haiku-4-5'], null, null, 'ai',
   'Model the assistant runs on. Change here, no redeploy.'),
  ('ai.effort', 'high', 'enum', array['low','medium','high'], null, null, 'ai',
   'Reasoning effort for assistant calls. High for anything touching a clinical or legal question.'),
  ('ai.thinking', 'adaptive', 'enum', array['adaptive','off'], null, null, 'ai',
   'Extended thinking mode. Adaptive lets the model choose its own depth per question.'),
  ('ai.max_output_tokens', '8000', 'integer', null, 512, 64000, 'ai',
   'Ceiling on a single assistant response.'),
  ('ai.enabled', 'true', 'boolean', null, null, null, 'ai',
   'Master switch. Set to false and every assistant call returns disabled without reaching the API.'),
  ('ai.api_key_ref', 'supabase_secret:ANTHROPIC_API_KEY', 'text', null, null, null, 'ai',
   'Where the API key lives. A reference only. The key itself is never stored in the database.'),
  ('ai.monthly_cost_ceiling_usd', '200', 'decimal', null, 0, 10000, 'ai',
   'Hard monthly ceiling on assistant spend. The connection refuses to call once the month exceeds it.'),
  ('ai.prompt_version', '1.0.0', 'text', null, null, null, 'ai',
   'Version of the assistant instruction set. Bumped whenever the guardrails change.'),
  ('ai.allow_client_facing', 'true', 'boolean', null, null, null, 'ai',
   'Whether the assistant may answer a client directly. When false it only serves internal actions.'),

  -- Agent schedule and behaviour
  ('agent.monthly_audit_day', '1', 'integer', null, 1, 28, 'agent',
   'Day of the month the framework audit runs. Capped at 28 so every month has one.'),
  ('agent.monthly_audit_hour_utc', '2', 'integer', null, 0, 23, 'agent',
   'Hour in UTC the framework audit runs.'),
  ('agent.currency_check_months', '12', 'integer', null, 1, 60, 'agent',
   'How old a currency check may be before the audit raises the instrument.'),
  ('agent.findings_alert_email', 'pending', 'text', null, null, null, 'agent',
   'Where audit findings are sent. Pending a Care Net address, register item CR-13.18.'),
  ('agent.autopublish_findings', 'false', 'boolean', null, null, null, 'agent',
   'Whether the agent may act on its own findings. False by design: a finding is a proposal for the practitioner, not a change.'),

  -- Clinical floors. These are legal minima and are not tuning knobs in practice.
  ('clinical.periodic_floor_months', '12', 'integer', null, 1, 36, 'clinical',
   'Maximum interval between periodic examinations. Twelve months is the regulatory floor and must not be raised without a legal basis.'),
  ('clinical.record_retention_years', '40', 'integer', null, 40, 100, 'clinical',
   'Medical surveillance record retention floor in years. Forty is the house floor, register item CR-12.4.'),
  ('clinical.noise_action_level_db', '85', 'integer', null, 80, 90, 'clinical',
   'Noise action level in dB(A). Eighty five under the Noise Induced Hearing Loss Regulations, register item CR-13.10.'),
  ('clinical.omp_release_required', 'true', 'boolean', null, null, null, 'clinical',
   'Whether a registered practitioner signature is required before release. True. The database trigger enforces this independently.'),

  -- Commercial
  ('commercial.free_medicals_threshold', '100', 'integer', null, 1, 100000, 'commercial',
   'Annual medicals at which the plan becomes free to the client. Register item CR-13.15.'),
  ('commercial.omp_review_fee_zar', '2500', 'decimal', null, 0, 100000, 'commercial',
   'Practitioner review and sign off fee. Placeholder pending confirmation, register item CR-13.17.'),
  ('commercial.pricing_status', 'indicative', 'enum', array['indicative','confirmed'], null, null, 'commercial',
   'Whether quoted prices are confirmed. While indicative every quote carries that wording.'),
  ('commercial.quote_validity_days', '30', 'integer', null, 1, 365, 'commercial',
   'How long a quotation stands.'),

  -- Integration references. References only, never values.
  ('integration.payment_gateway', 'pending', 'text', null, null, null, 'integration',
   'Payment gateway in use. Pending a Care Net decision, register item CR-13.13.'),
  ('integration.signature_provider', 'docuseal', 'text', null, null, null, 'integration',
   'Electronic signature provider for practitioner sign off.'),
  ('integration.site_base_url', 'pending', 'text', null, null, null, 'integration',
   'Canonical public base URL. Pending confirmation, register item CR-13.3.');

-- 4. The AI call ledger ----------------------------------------------------------

create table msp_ai_call_log (
  id             bigint generated always as identity primary key,
  called_at      timestamptz not null default now(),
  action         text not null,
  model          text not null,
  effort         text,
  prompt_version text,
  engagement_id  uuid,
  industry_code  text,
  actor          text not null,
  input_tokens   integer,
  output_tokens  integer,
  cost_usd       numeric(10,4),
  latency_ms     integer,
  outcome        text not null check (outcome in ('ok','refused','error','disabled','over_budget')),
  error_detail   text
);
comment on table msp_ai_call_log is
  'Every assistant call, priced and attributed. This is the cost control and the evidence trail: what was asked, on what model, at what effort, under which instruction version.';

create index msp_ai_call_log_month_idx on msp_ai_call_log(called_at desc);

alter table msp_ai_call_log enable row level security;
create policy msp_ai_call_log_read on msp_ai_call_log
  for select to authenticated using (msp_has_role('forge_admin') or msp_has_role('forge_omp'));

-- Spend so far in the current calendar month.
create or replace function msp_ai_month_spend_usd()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(cost_usd), 0)
    from msp_ai_call_log
   where called_at >= date_trunc('month', now());
$$;

-- The gate the connection calls before it spends anything. Returns the running
-- configuration together with a verdict, so the connection needs one round trip.
create or replace function msp_ai_preflight(p_action text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg jsonb := msp_env_bundle('ai');
  v_spend numeric := msp_ai_month_spend_usd();
  v_ceiling numeric := (v_cfg ->> 'ai.monthly_cost_ceiling_usd')::numeric;
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'the assistant connection requires the forge_agent or forge_admin role';
  end if;
  if (v_cfg ->> 'ai.enabled')::boolean is not true then
    return jsonb_build_object('allowed', false, 'reason', 'disabled', 'config', v_cfg);
  end if;
  if v_spend >= v_ceiling then
    return jsonb_build_object('allowed', false, 'reason', 'over_budget',
      'spend_usd', v_spend, 'ceiling_usd', v_ceiling, 'config', v_cfg);
  end if;
  return jsonb_build_object('allowed', true, 'action', p_action, 'config', v_cfg,
    'spend_usd', v_spend, 'ceiling_usd', v_ceiling);
end;
$$;
comment on function msp_ai_preflight is
  'One round trip before any assistant call: role check, master switch, monthly ceiling, and the whole running configuration. The connection carries no defaults of its own.';

create or replace function msp_ai_log(
  p_action text, p_model text, p_effort text, p_prompt_version text,
  p_outcome text, p_input_tokens integer default null, p_output_tokens integer default null,
  p_cost_usd numeric default null, p_latency_ms integer default null,
  p_engagement_id uuid default null, p_industry_code text default null,
  p_error text default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'logging an assistant call requires the forge_agent or forge_admin role';
  end if;
  insert into msp_ai_call_log (action, model, effort, prompt_version, outcome,
    input_tokens, output_tokens, cost_usd, latency_ms, engagement_id, industry_code,
    actor, error_detail)
  values (p_action, p_model, p_effort, p_prompt_version, p_outcome,
    p_input_tokens, p_output_tokens, p_cost_usd, p_latency_ms, p_engagement_id, p_industry_code,
    coalesce(auth.jwt() ->> 'email', auth.role(), 'assistant'), p_error)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function msp_ai_preflight(text), msp_ai_month_spend_usd() to authenticated;

-- 5. Grounding reads for the assistant --------------------------------------------
-- The assistant is never allowed to answer from its own memory of South African
-- law. It answers from rows. These two functions are the only kernel content it
-- can see, and both return verified instruments only.

create or replace function msp_ai_context_industry(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'assistant grounding reads require the forge_agent or forge_admin role';
  end if;
  select to_jsonb(p) into v from msp_public_industry_profile p where p.code = p_code;
  if v is null then
    return jsonb_build_object('found', false, 'code', p_code);
  end if;
  return v || jsonb_build_object('found', true);
end;
$$;
comment on function msp_ai_context_industry is
  'The grounding pack for one industry: verified instruments with their applicability notes, subindustries, roles, hazards, protocols. Nothing pending, nothing clinical beyond protocol names, no client data.';

create or replace function msp_ai_context_instruments()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'assistant grounding reads require the forge_agent or forge_admin role';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'short_name', short_name, 'citation', citation, 'status', status)
            order by short_name), '[]'::jsonb)
            from msp_legal_instrument where status = 'verified');
end;
$$;

grant execute on function msp_ai_context_industry(text), msp_ai_context_instruments() to authenticated;

-- 6. Register items opened by this work -------------------------------------------

insert into msp_confirmation_item (item_code, kind, description) values
  ('CR-13.18', 'confirm',
   'Destination address for monthly framework audit findings. Parameter agent.findings_alert_email is set to pending until Care Net confirms it.'),
  ('CR-13.19', 'confirm',
   'Monthly assistant spend ceiling. Parameter ai.monthly_cost_ceiling_usd is set to 200 US dollars as a working figure pending confirmation.')
on conflict (item_code) do nothing;

------------------------------------------------------------------------------
-- 035_msp_agent_schedule.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | AGT-SCH-01 v1.0.0 | Live scheduling from the parameter store 15/08/2026
-- The monthly framework audit now runs on a real schedule, and the schedule is
-- read from the parameter store rather than written into a cron string by hand.
-- Change agent.monthly_audit_day and the job moves. Nothing is redeployed.
--
-- The audit itself is pure SQL and needs no network and no secret, so it is
-- scheduled directly. The assistant assisted watch needs an outbound call and
-- therefore a key, so it is scheduled only when Care Net has placed that key in
-- the vault. Until then the function says so plainly and schedules nothing.

-- Model prices, so the call ledger can be priced without a redeploy when rates
-- move. United States dollars per million tokens.
insert into msp_env_parameter (key, value, value_type, category, description) values
  ('ai.price_table_json',
   '{"claude-opus-5":{"in":5.00,"out":25.00},"claude-sonnet-5":{"in":3.00,"out":15.00},"claude-haiku-4-5":{"in":1.00,"out":5.00}}',
   'text', 'ai',
   'Published token prices in United States dollars per million tokens, used to price the call ledger. Update here when rates change.'),
  ('ai.actions_enabled',
   'explain_plan,industry_brief,triage_other,monthly_watch',
   'text', 'ai',
   'Comma separated list of assistant actions the connection will serve. Remove one to switch it off without a redeploy.')
on conflict (key) do nothing;

-- Rebuild the cron entry for the monthly framework audit from the parameters.
create or replace function msp_agent_reschedule()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day  int := msp_env_get_int('agent.monthly_audit_day');
  v_hour int := msp_env_get_int('agent.monthly_audit_hour_utc');
  v_expr text;
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'rescheduling the agent requires the forge_admin role';
  end if;
  v_expr := format('0 %s %s * *', v_hour, v_day);

  perform cron.unschedule('msp_monthly_audit')
    where exists (select 1 from cron.job where jobname = 'msp_monthly_audit');

  perform cron.schedule('msp_monthly_audit', v_expr, 'select msp_kernel_monthly_audit();');

  insert into msp_audit (actor, event_type, event_detail)
  values (coalesce(auth.jwt() ->> 'email', auth.role(), 'msp_agent_reschedule'),
          'agent_rescheduled',
          jsonb_build_object('job', 'msp_monthly_audit', 'schedule', v_expr));

  return jsonb_build_object('job', 'msp_monthly_audit', 'schedule', v_expr,
                            'day', v_day, 'hour_utc', v_hour);
end;
$$;
comment on function msp_agent_reschedule is
  'Rebuilds the monthly audit cron entry from agent.monthly_audit_day and agent.monthly_audit_hour_utc. Called automatically whenever either parameter changes.';

-- Make the schedule parameters genuinely live: changing one moves the job in the
-- same call. A scheduling failure is recorded but never blocks the parameter
-- change itself, because the stored configuration is the source of truth and the
-- schedule can always be rebuilt from it.
create or replace function msp_env_after_change(p_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_key in ('agent.monthly_audit_day', 'agent.monthly_audit_hour_utc') then
    begin
      perform msp_agent_reschedule();
    exception when others then
      insert into msp_audit (actor, event_type, event_detail)
      values ('msp_env_after_change', 'agent_reschedule_failed',
              jsonb_build_object('key', p_key, 'error', sqlerrm));
    end;
  end if;
end;
$$;

-- msp_env_set gains the one line that calls the hook. Everything else is as it
-- was in migration 034.
create or replace function msp_env_set(p_key text, p_value text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row msp_env_parameter%rowtype;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.role(), 'unknown');
  v_num numeric;
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'changing a runtime parameter requires the forge_admin role';
  end if;

  select * into v_row from msp_env_parameter where key = p_key;
  if not found then
    raise exception 'unknown parameter %. Parameters are declared by migration, not created at runtime', p_key;
  end if;

  if v_row.value_type = 'integer' then
    if p_value !~ '^-?\d+$' then
      raise exception 'parameter % expects an integer, got %', p_key, p_value;
    end if;
    v_num := p_value::numeric;
  elsif v_row.value_type = 'decimal' then
    if p_value !~ '^-?\d+(\.\d+)?$' then
      raise exception 'parameter % expects a decimal, got %', p_key, p_value;
    end if;
    v_num := p_value::numeric;
  elsif v_row.value_type = 'boolean' then
    if lower(p_value) not in ('true','false') then
      raise exception 'parameter % expects true or false, got %', p_key, p_value;
    end if;
  elsif v_row.value_type = 'date' then
    begin
      perform p_value::date;
    exception when others then
      raise exception 'parameter % expects a date in YYYY-MM-DD form, got %', p_key, p_value;
    end;
  elsif v_row.value_type = 'enum' then
    if v_row.allowed_values is null or not (p_value = any(v_row.allowed_values)) then
      raise exception 'parameter % expects one of %, got %',
        p_key, array_to_string(v_row.allowed_values, ', '), p_value;
    end if;
  end if;

  if v_num is not null then
    if v_row.min_value is not null and v_num < v_row.min_value then
      raise exception 'parameter % has a floor of %, got %', p_key, v_row.min_value, p_value;
    end if;
    if v_row.max_value is not null and v_num > v_row.max_value then
      raise exception 'parameter % has a ceiling of %, got %', p_key, v_row.max_value, p_value;
    end if;
  end if;

  update msp_env_parameter
     set value = p_value, updated_by = v_actor, updated_at = now()
   where key = p_key;

  insert into msp_env_parameter_history (key, old_value, new_value, changed_by, reason)
  values (p_key, v_row.value, p_value, v_actor, p_reason);

  insert into msp_audit (actor, event_type, event_detail)
  values (v_actor, 'env_parameter_change',
          jsonb_build_object('key', p_key, 'from', v_row.value, 'to', p_value, 'reason', p_reason));

  perform msp_env_after_change(p_key);

  return jsonb_build_object('key', p_key, 'old_value', v_row.value, 'new_value', p_value,
                            'changed_by', v_actor, 'changed_at', now());
end;
$$;

-- What is actually scheduled right now. Readable by any forge role so the admin
-- page can show the truth rather than a claim.
create or replace function msp_agent_schedule_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(msp_any_forge_role(), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'reading the agent schedule requires a forge role';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'job', jobname, 'schedule', schedule, 'command', command, 'active', active)), '[]'::jsonb)
            from cron.job where jobname like 'msp\_%');
end;
$$;

grant execute on function msp_agent_reschedule(), msp_agent_schedule_status() to authenticated;

-- Put the audit on the schedule the parameters currently describe.
select cron.schedule('msp_monthly_audit', '0 2 1 * *', 'select msp_kernel_monthly_audit();');

------------------------------------------------------------------------------
-- 036_msp_ai_identity_limits.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | AI-02 v1.0.0 | Caller identity and rate limits for the assistant 15/08/2026
-- The connection runs on the service context so it can read the parameter store
-- and write the ledger, which means the database can no longer see who asked.
-- The connection therefore passes the real caller through, and the ledger records
-- that person rather than the service. Rate limits are per caller and per hour,
-- and both ceilings are parameters like everything else.

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('ai.client_hourly_limit', '20', 'integer', 0, 500, 'ai',
   'Assistant calls one client account may make in an hour. Zero switches client access off entirely.'),
  ('ai.staff_hourly_limit', '120', 'integer', 0, 5000, 'ai',
   'Assistant calls one member of staff may make in an hour.')
on conflict (key) do nothing;

-- How many calls this caller has already made in the window.
create or replace function msp_ai_recent_calls(p_actor text, p_minutes int default 60)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from msp_ai_call_log
   where actor = p_actor
     and outcome in ('ok','refused','error')
     and called_at >= now() - make_interval(mins => p_minutes);
$$;

-- The ledger write, now carrying the real caller. The previous signature is
-- dropped rather than overloaded so there is never any doubt which one ran.
drop function if exists msp_ai_log(text, text, text, text, text, integer, integer, numeric, integer, uuid, text, text);

create or replace function msp_ai_log(
  p_action text, p_model text, p_effort text, p_prompt_version text,
  p_outcome text, p_actor text,
  p_input_tokens integer default null, p_output_tokens integer default null,
  p_cost_usd numeric default null, p_latency_ms integer default null,
  p_engagement_id uuid default null, p_industry_code text default null,
  p_error text default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'logging an assistant call requires the forge_agent or forge_admin role';
  end if;
  insert into msp_ai_call_log (action, model, effort, prompt_version, outcome,
    input_tokens, output_tokens, cost_usd, latency_ms, engagement_id, industry_code,
    actor, error_detail)
  values (p_action, p_model, p_effort, p_prompt_version, p_outcome,
    p_input_tokens, p_output_tokens, p_cost_usd, p_latency_ms, p_engagement_id, p_industry_code,
    coalesce(nullif(p_actor, ''), auth.jwt() ->> 'email', auth.role(), 'assistant'), p_error)
  returning id into v_id;
  return v_id;
end;
$$;
comment on function msp_ai_log is
  'Writes one row to the assistant call ledger. The caller is passed in explicitly because the connection runs on the service context and would otherwise record itself.';

-- Is this Supabase Auth user a client account we recognise, and which one.
create or replace function msp_ai_client_identity(p_auth_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'resolving a client identity requires the forge_agent or forge_admin role';
  end if;
  select jsonb_build_object('found', true, 'account_id', id, 'company_name', company_name,
                            'sla_status', sla_status)
    into v
    from msp_client_account where auth_user_id = p_auth_user_id;
  return coalesce(v, jsonb_build_object('found', false));
end;
$$;

grant execute on function msp_ai_recent_calls(text, int), msp_ai_client_identity(uuid) to authenticated;

-- A read only view of the ledger for the admin page: this month, by action.
create or replace function msp_ai_usage_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(msp_has_role('forge_admin'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'the assistant usage summary requires the forge_admin role';
  end if;
  return jsonb_build_object(
    'month_spend_usd', msp_ai_month_spend_usd(),
    'ceiling_usd', msp_env_get_numeric('ai.monthly_cost_ceiling_usd'),
    'by_action', (select coalesce(jsonb_agg(jsonb_build_object(
        'action', action, 'calls', calls, 'cost_usd', cost_usd, 'ok', ok_calls)
        order by cost_usd desc), '[]'::jsonb)
      from (select action, count(*) as calls, coalesce(sum(cost_usd), 0) as cost_usd,
                   count(*) filter (where outcome = 'ok') as ok_calls
              from msp_ai_call_log
             where called_at >= date_trunc('month', now())
             group by action) t),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object(
        'at', called_at, 'action', action, 'actor', actor, 'outcome', outcome,
        'cost_usd', cost_usd, 'latency_ms', latency_ms)
        order by called_at desc), '[]'::jsonb)
      from (select * from msp_ai_call_log order by called_at desc limit 25) r));
end;
$$;

grant execute on function msp_ai_usage_summary() to authenticated;

------------------------------------------------------------------------------
-- 037_msp_env_ai_grant_lockdown.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | ENV-02 v1.0.0 | Grant lockdown on the parameter store and the assistant 15/08/2026
-- Postgres grants execute on a new function to PUBLIC by default, which means the
-- anonymous web role could call every helper added in migrations 034 to 036. The
-- guarded ones would have refused, but the small readers had no guard because
-- they are internal plumbing. The advisor flagged all of them and it is right.
--
-- The rule applied here: a function is reachable from the outside only if a
-- person or the assistant connection genuinely needs to call it, and every one
-- that is reachable checks the caller's role in its own body. Everything else is
-- revoked from PUBLIC and stays callable only inside the definer functions that
-- use it, which run as the owner.
--
-- Staff still read the running configuration the proper way, by selecting from
-- msp_env_parameter under its row level security policy.

-- 1. Internal plumbing. Nothing outside the database calls these.
revoke all on function msp_env_get(text)          from public, anon, authenticated;
revoke all on function msp_env_get_int(text)      from public, anon, authenticated;
revoke all on function msp_env_get_numeric(text)  from public, anon, authenticated;
revoke all on function msp_env_get_bool(text)     from public, anon, authenticated;
revoke all on function msp_env_bundle(text)       from public, anon, authenticated;
revoke all on function msp_env_after_change(text) from public, anon, authenticated;
revoke all on function msp_ai_month_spend_usd()   from public, anon, authenticated;

-- 2. Called only by the assistant connection, which runs on the service context.
revoke all on function msp_ai_preflight(text)           from public, anon, authenticated;
revoke all on function msp_ai_context_industry(text)    from public, anon, authenticated;
revoke all on function msp_ai_context_instruments()     from public, anon, authenticated;
revoke all on function msp_ai_recent_calls(text, int)   from public, anon, authenticated;
revoke all on function msp_ai_client_identity(uuid)     from public, anon, authenticated;
revoke all on function msp_ai_log(text, text, text, text, text, text, integer, integer, numeric, integer, uuid, text, text)
  from public, anon, authenticated;

grant execute on function msp_ai_preflight(text)         to service_role;
grant execute on function msp_ai_context_industry(text)  to service_role;
grant execute on function msp_ai_context_instruments()   to service_role;
grant execute on function msp_ai_recent_calls(text, int) to service_role;
grant execute on function msp_ai_client_identity(uuid)   to service_role;
grant execute on function msp_ai_log(text, text, text, text, text, text, integer, integer, numeric, integer, uuid, text, text)
  to service_role;

-- 3. Called by a signed in person on the settings page. Each one checks the
-- caller's role in its own body before it does anything.
revoke all on function msp_env_set(text, text, text) from public, anon;
revoke all on function msp_ai_usage_summary()        from public, anon;
revoke all on function msp_agent_reschedule()        from public, anon;
revoke all on function msp_agent_schedule_status()   from public, anon;

grant execute on function msp_env_set(text, text, text) to authenticated;
grant execute on function msp_ai_usage_summary()        to authenticated;
grant execute on function msp_agent_reschedule()        to authenticated;
grant execute on function msp_agent_schedule_status()   to authenticated;

-- 4. The history guard trigger had a mutable search path. It only ever raises,
-- but a trigger function with an open search path is still a foothold.
create or replace function msp_env_history_block_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'msp_env_parameter_history is append only';
end;
$$;

------------------------------------------------------------------------------
-- 038_msp_audit_schedule_dedup.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | AGT-SCH-02 v1.0.0 | One audit job, not two 15/08/2026
-- Migration 035 created the parameter driven job msp_monthly_audit without
-- checking for the job an earlier session had already created by hand,
-- msp-kernel-monthly-audit. Both were live, so the framework audit would have
-- run twice on the first of the month, at 02:00 and again at 06:00, writing two
-- rows to msp_kernel_agent_run. Harmless but wrong, and only one of them
-- answered to the parameters.
--
-- The parameter driven job is kept. The hand made one is removed here, and
-- msp_agent_reschedule now clears any legacy name as well as its own, so a
-- reschedule can never leave a second job behind.

select cron.unschedule('msp-kernel-monthly-audit')
 where exists (select 1 from cron.job where jobname = 'msp-kernel-monthly-audit');

create or replace function msp_agent_reschedule()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day  int := msp_env_get_int('agent.monthly_audit_day');
  v_hour int := msp_env_get_int('agent.monthly_audit_hour_utc');
  v_expr text;
  v_legacy text;
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'rescheduling the agent requires the forge_admin role';
  end if;
  v_expr := format('0 %s %s * *', v_hour, v_day);

  -- Clear every audit job this system has ever used, by any name, so a
  -- reschedule leaves exactly one behind.
  for v_legacy in
    select jobname from cron.job
     where jobname in ('msp_monthly_audit', 'msp-kernel-monthly-audit')
  loop
    perform cron.unschedule(v_legacy);
  end loop;

  perform cron.schedule('msp_monthly_audit', v_expr, 'select msp_kernel_monthly_audit();');

  insert into msp_audit (actor, event_type, event_detail)
  values (coalesce(auth.jwt() ->> 'email', auth.role(), 'msp_agent_reschedule'),
          'agent_rescheduled',
          jsonb_build_object('job', 'msp_monthly_audit', 'schedule', v_expr));

  return jsonb_build_object('job', 'msp_monthly_audit', 'schedule', v_expr,
                            'day', v_day, 'hour_utc', v_hour);
end;
$$;

revoke all on function msp_agent_reschedule() from public, anon;
grant execute on function msp_agent_reschedule() to authenticated;

------------------------------------------------------------------------------
-- 039_msp_client_signon.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | FRM-GATE-01 v1.1.0 | Client sign-on write path 09/09/2026
-- Defect: signon.js was the only endpoint writing with a raw PostgREST table
-- insert. msp_client_account (migration 009) has RLS enabled with SELECT and
-- UPDATE policies but NO INSERT policy, so the applicant row could never be
-- written and every company registration failed with the generic
-- "sign on could not be recorded". Every other write path in this build goes
-- through a security definer function; this brings sign-on into line.
--
-- The function also makes re-submission idempotent: a repeat sign-on for an
-- email that already has an account returns that account instead of dead-ending,
-- so a second attempt never errors.

create or replace function msp_client_signon(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company text := btrim(coalesce(p->>'company_name',''));
  v_contact text := btrim(coalesce(p->>'contact_name',''));
  v_email   text := lower(btrim(coalesce(p->>'contact_email','')));
  v_notes   text := nullif(btrim(coalesce(p->>'notes','')), '');
  v_id uuid;
  v_kind text;
begin
  if v_company = '' or v_contact = '' or v_email = '' then
    raise exception 'company name, contact name, and email are required';
  end if;

  select id, account_kind into v_id, v_kind
    from msp_client_account
   where lower(contact_email) = v_email
   order by created_at desc
   limit 1;

  if v_id is not null then
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_signon_repeat',
            jsonb_build_object('client_account_id', v_id, 'email', v_email));
    return jsonb_build_object('status', 'received', 'reference', v_id,
                             'account_kind', v_kind, 'existing', true);
  end if;

  insert into msp_client_account (company_name, contact_name, contact_email, notes)
  values (v_company, v_contact, v_email, v_notes)
  returning id, account_kind into v_id, v_kind;

  insert into msp_audit (actor, event_type, event_detail)
  values ('signon', 'client_signon',
          jsonb_build_object('client_account_id', v_id, 'company', v_company, 'email', v_email));

  return jsonb_build_object('status', 'received', 'reference', v_id,
                           'account_kind', v_kind, 'existing', false);
end;
$$;

-- Mirror the grant pattern of the other server-side RPCs (msp_company_lookup,
-- msp_create_quote): callable only by the service role that the Vercel
-- endpoints authenticate with, never by a browser.
revoke execute on function msp_client_signon(jsonb) from public, anon, authenticated;

comment on function msp_client_signon is 'Server side only: records a landing-page company sign-on as an applicant (account_kind defaults to applicant; a forge_admin approves in the review interface). Idempotent on contact_email. Replaces the raw table insert that RLS refused.';

------------------------------------------------------------------------------
-- 040_msp_self_service_access.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | FRM-GATE-01 v1.2.0 | Self-service assessment access 11/09/2026
-- MD ruling (31/08/2026, restated 11/09/2026): the Medical Surveillance Plan is free
-- for every client who books medicals, and the OMP sign-off is the paid tier. The
-- consultant approval gate on client accounts therefore no longer serves a purpose,
-- and in practice it had no user interface at all: msp_grant_access is server-side
-- only and settings.html has no client-accounts tab, so every registration stalled
-- at "your registration is with a consultant for approval".
--
-- This migration removes the wait:
--   1. msp_client_start_assessment(p_email) approves the account on demand and
--      returns a live single-use assessment token, reusing an unused, unexpired
--      token when one already exists so a page refresh never mints a second one.
--   2. msp_client_signon now returns that token in the same call, so a client who
--      has just registered is handed their assessment link immediately.
--
-- Nothing in the schema changes. account_kind keeps its enum (applicant,
-- approved_client, declined); declined accounts are still refused; the token,
-- expiry and one-token-one-assessment rule from migration 009 are unchanged.

create or replace function msp_client_start_assessment(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account%rowtype;
  v_token text;
  v_grant jsonb;
begin
  select * into v_acc
    from msp_client_account
   where lower(contact_email) = lower(btrim(coalesce(p_email, '')))
   order by created_at desc
   limit 1;

  if v_acc.id is null then
    return jsonb_build_object('found', false);
  end if;

  if v_acc.account_kind = 'declined' then
    return jsonb_build_object('found', true, 'declined', true,
                              'company_name', v_acc.company_name);
  end if;

  -- Self-service approval: the account is approved the moment it asks to start.
  if v_acc.account_kind <> 'approved_client' then
    update msp_client_account
       set account_kind = 'approved_client',
           approved_by  = 'self-service',
           approved_at  = now()
     where id = v_acc.id;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_self_approved',
            jsonb_build_object('client_account_id', v_acc.id, 'company', v_acc.company_name));
  end if;

  -- Reuse a live token if one exists; otherwise mint one through the existing grant path.
  select token into v_token
    from msp_form_access
   where client_account_id = v_acc.id
     and used_by_intake is null
     and expires_at > now()
   order by created_at desc
   limit 1;

  if v_token is null then
    v_grant := msp_grant_access('approved_client', v_acc.company_name, null, v_acc.id);
    v_token := v_grant->>'token';
  end if;

  return jsonb_build_object(
    'found', true,
    'declined', false,
    'company_name', v_acc.company_name,
    'account_kind', 'approved_client',
    'sla_status', v_acc.sla_status,
    'tool_free', true,
    'token', v_token);
end;
$$;
revoke execute on function msp_client_start_assessment(text) from public, anon, authenticated;
comment on function msp_client_start_assessment is 'Server side only: approves the signed-in contact''s account on demand and returns a live single-use assessment token (reusing an unused, unexpired one). Replaces the manual consultant approval step per the MD ruling of 31/08/2026.';

create or replace function msp_client_signon(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company text := btrim(coalesce(p->>'company_name',''));
  v_contact text := btrim(coalesce(p->>'contact_name',''));
  v_email   text := lower(btrim(coalesce(p->>'contact_email','')));
  v_notes   text := nullif(btrim(coalesce(p->>'notes','')), '');
  v_id uuid;
  v_existing boolean := false;
  v_start jsonb;
begin
  if v_company = '' or v_contact = '' or v_email = '' then
    raise exception 'company name, contact name, and email are required';
  end if;

  select id into v_id
    from msp_client_account
   where lower(contact_email) = v_email
   order by created_at desc
   limit 1;

  if v_id is not null then
    v_existing := true;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_signon_repeat',
            jsonb_build_object('client_account_id', v_id, 'email', v_email));
  else
    insert into msp_client_account (company_name, contact_name, contact_email, notes)
    values (v_company, v_contact, v_email, v_notes)
    returning id into v_id;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_signon',
            jsonb_build_object('client_account_id', v_id, 'company', v_company, 'email', v_email));
  end if;

  v_start := msp_client_start_assessment(v_email);

  return jsonb_build_object(
    'status', 'received',
    'reference', v_id,
    'existing', v_existing,
    'company_name', v_start->>'company_name',
    'account_kind', v_start->>'account_kind',
    'declined', coalesce((v_start->>'declined')::boolean, false),
    'token', v_start->>'token');
end;
$$;
revoke execute on function msp_client_signon(jsonb) from public, anon, authenticated;
comment on function msp_client_signon is 'Server side only: records a landing-page company sign-on, approves it immediately (self-service, MD ruling 31/08/2026) and returns the assessment token. Idempotent on contact_email.';

notify pgrst, 'reload schema';

------------------------------------------------------------------------------
-- 041_msp_gap_safe_reference.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | FRM-INT-01 v1.1.1 | Gap-safe engagement reference 14/09/2026
-- Defect: msp_next_reference (migration 006) numbered a day's engagements as
-- count(today) + 1. After any deletion the count falls behind the highest number
-- in use, the next intake is assigned a reference that already exists, and
-- msp_ingest_intake fails on the unique reference (seen 14/09/2026 after a
-- test-data clear: CNC-MSP-2026-0914-003 assigned twice).
-- Fix: next number = highest existing number for the day + 1. The advisory lock
-- still serialises concurrent intakes so two submissions never share a number.

create or replace function msp_next_reference()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text := 'CNC-MSP-' || to_char(current_date, 'YYYY-MMDD') || '-';
  v_n int;
begin
  perform pg_advisory_xact_lock(hashtext('msp_engagement_reference'));
  select coalesce(max(substring(reference from '(\d{3})$')::int), 0) + 1 into v_n
    from msp_engagement
   where reference like v_prefix || '%';
  return v_prefix || lpad(v_n::text, 3, '0');
end;
$$;
revoke execute on function msp_next_reference() from public, anon, authenticated;
comment on function msp_next_reference is 'CNC-MSP-YYYY-MMDD-NNN. NNN = highest existing number for the day + 1 (gap-safe; count+1 collided after a test-data deletion on 14/09/2026). Advisory lock serialises concurrent intakes.';

------------------------------------------------------------------------------
-- 042_msp_legislation_currency_2026_09.sql
------------------------------------------------------------------------------

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

------------------------------------------------------------------------------
-- 043_msp_client_contact_number.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | FRM-GATE-01 v1.3.0 | Client contact number 16/09/2026
-- Cassandra's back-end ask 3 (16/09/2026): the landing page now collects a contact
-- number with the company name and contact person, but the client record had no
-- column for it, so the front end has been carrying it inside notes as
-- "Contact number: +27 ...". That is readable by a consultant but cannot be
-- searched, sorted or dialled from.
--
-- This migration:
--   1. adds msp_client_account.contact_number (free text, trimmed; the front end
--      already validates the shape, and numbers arrive in several formats);
--   2. teaches msp_client_signon to read p->>'contact_number', store it on a new
--      account, fill it in on a repeat sign-on when the account has none, and
--      return it;
--   3. backfills the column from any note that still carries the interim wording.
-- notes stays as it is for anything else a consultant wants to record.

alter table msp_client_account add column if not exists contact_number text;
comment on column msp_client_account.contact_number is 'Client contact telephone number as given on the landing page (free text, trimmed). Added 16/09/2026.';

-- Backfill from the interim "Contact number: ..." note written by the landing page
-- between 16/09/2026 and this migration. The note is left in place.
update msp_client_account
   set contact_number = btrim(substring(notes from 'Contact number:\s*([^;\n]+)'))
 where contact_number is null
   and notes ~ 'Contact number:\s*\S';

create or replace function msp_client_signon(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company text := btrim(coalesce(p->>'company_name',''));
  v_contact text := btrim(coalesce(p->>'contact_name',''));
  v_email   text := lower(btrim(coalesce(p->>'contact_email','')));
  v_notes   text := nullif(btrim(coalesce(p->>'notes','')), '');
  v_number  text := nullif(btrim(coalesce(p->>'contact_number','')), '');
  v_id uuid;
  v_existing boolean := false;
  v_start jsonb;
begin
  if v_company = '' or v_contact = '' or v_email = '' then
    raise exception 'company name, contact name, and email are required';
  end if;
  if v_number is not null and length(v_number) > 40 then
    raise exception 'contact number is too long';
  end if;

  select id into v_id
    from msp_client_account
   where lower(contact_email) = v_email
   order by created_at desc
   limit 1;

  if v_id is not null then
    v_existing := true;
    -- A repeat sign-on may bring a number the account never had.
    if v_number is not null then
      update msp_client_account
         set contact_number = v_number
       where id = v_id and contact_number is null;
    end if;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_signon_repeat',
            jsonb_build_object('client_account_id', v_id, 'email', v_email));
  else
    insert into msp_client_account (company_name, contact_name, contact_email, contact_number, notes)
    values (v_company, v_contact, v_email, v_number, v_notes)
    returning id into v_id;
    insert into msp_audit (actor, event_type, event_detail)
    values ('signon', 'client_signon',
            jsonb_build_object('client_account_id', v_id, 'company', v_company, 'email', v_email));
  end if;

  v_start := msp_client_start_assessment(v_email);

  return jsonb_build_object(
    'status', 'received',
    'reference', v_id,
    'existing', v_existing,
    'company_name', v_start->>'company_name',
    'contact_number', (select contact_number from msp_client_account where id = v_id),
    'account_kind', v_start->>'account_kind',
    'declined', coalesce((v_start->>'declined')::boolean, false),
    'token', v_start->>'token');
end;
$$;
revoke execute on function msp_client_signon(jsonb) from public, anon, authenticated;
comment on function msp_client_signon is 'Server side only: records a landing-page company sign-on (company, contact, email, optional contact_number, notes), approves it immediately (self-service, MD ruling 31/08/2026) and returns the assessment token. Idempotent on contact_email.';

notify pgrst, 'reload schema';

------------------------------------------------------------------------------
-- 044_msp_intake_draft.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | FRM-DRAFT-01 v1.0.0 | Server-side assessment drafts 16/09/2026
-- Cassandra's back-end ask 4 (16/09/2026): the assessment page saves a draft in the
-- visitor's browser (cnc-journey.js), which holds up on one machine but cannot
-- follow the same emailed link to a second one. This migration gives a draft a
-- home on the server, one row per access token, so the link opens the
-- part-finished assessment anywhere and the browser copy becomes the fallback.
--
-- Rules
--   * The access token is the only key. A draft can be saved or read only while
--     msp_check_access says the token is live (unknown, used or expired tokens are
--     refused with the same reasons the assessment page already shows).
--   * One row per token; saving again replaces the payload.
--   * The payload is the form's own field map plus the repeat-block counts, the
--     section the client was on and the running answer count. The server does not
--     interpret it. Size is capped at 256 KB (a full assessment is well under 50 KB).
--   * When the token is consumed by a submission the draft is deleted by trigger,
--     so nothing lingers once the intake exists. msp_draft_purge() removes drafts
--     whose token has expired; run it from the agent schedule or by hand.
--   * POPIA: a draft holds company details, named contacts and workplace hazards,
--     never clinical results (the form forbids them). RLS is on with no policies,
--     so only the service role (the Vercel endpoints) can touch the table.

create table if not exists msp_intake_draft (
  id uuid primary key default gen_random_uuid(),
  access_id uuid not null unique references msp_form_access(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  step int not null default 1,
  filled int not null default 0,
  company text,
  saved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint msp_intake_draft_payload_size check (pg_column_size(payload) <= 262144)
);
comment on table msp_intake_draft is 'Part-finished assessment answers, one row per live access token, saved from assess.html so the same emailed link resumes on any machine. Deleted when the token is consumed. Service role only.';
alter table msp_intake_draft enable row level security;
revoke all on msp_intake_draft from public, anon, authenticated;

-- Save (upsert) a draft against a live token.
create or replace function msp_draft_save(p_token text, p_payload jsonb, p_step int default 1, p_filled int default 0, p_company text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_check jsonb;
  v_access uuid;
  v_saved timestamptz;
begin
  v_check := msp_check_access(p_token);
  if not coalesce((v_check->>'valid')::boolean, false) then
    return jsonb_build_object('saved', false, 'reason', v_check->>'reason');
  end if;
  v_access := (v_check->>'access_id')::uuid;

  insert into msp_intake_draft (access_id, payload, step, filled, company, saved_at)
  values (v_access, coalesce(p_payload, '{}'::jsonb), greatest(coalesce(p_step, 1), 1),
          greatest(coalesce(p_filled, 0), 0), nullif(btrim(coalesce(p_company, '')), ''), now())
  on conflict (access_id) do update
     set payload  = excluded.payload,
         step     = excluded.step,
         filled   = excluded.filled,
         company  = coalesce(excluded.company, msp_intake_draft.company),
         saved_at = now()
  returning saved_at into v_saved;

  return jsonb_build_object('saved', true, 'saved_at', v_saved);
end;
$$;
revoke execute on function msp_draft_save(text, jsonb, int, int, text) from public, anon, authenticated;
comment on function msp_draft_save is 'Server side only: upserts the part-finished assessment for a live access token. Refuses unknown, used or expired tokens with the msp_check_access reason.';

-- Read a draft back for a live token.
create or replace function msp_draft_get(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_check jsonb;
  d msp_intake_draft%rowtype;
begin
  v_check := msp_check_access(p_token);
  if not coalesce((v_check->>'valid')::boolean, false) then
    return jsonb_build_object('found', false, 'valid', false, 'reason', v_check->>'reason');
  end if;

  select * into d from msp_intake_draft where access_id = (v_check->>'access_id')::uuid;
  if d.id is null then
    return jsonb_build_object('found', false, 'valid', true, 'company_name', v_check->>'company_name');
  end if;

  return jsonb_build_object(
    'found', true, 'valid', true,
    'company_name', v_check->>'company_name',
    'payload', d.payload, 'step', d.step, 'filled', d.filled,
    'company', d.company, 'saved_at', d.saved_at);
end;
$$;
revoke execute on function msp_draft_get(text) from public, anon, authenticated;
comment on function msp_draft_get is 'Server side only: returns the saved draft for a live access token, or found=false.';

-- Discard a draft (the Discard button).
create or replace function msp_draft_clear(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  delete from msp_intake_draft d
   using msp_form_access f
   where f.id = d.access_id and f.token = p_token;
  get diagnostics v_n = row_count;
  return jsonb_build_object('cleared', v_n > 0);
end;
$$;
revoke execute on function msp_draft_clear(text) from public, anon, authenticated;

-- A consumed token has no draft to keep.
create or replace function msp_intake_draft_on_consume()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.used_by_intake is not null and old.used_by_intake is null then
    delete from msp_intake_draft where access_id = new.id;
  end if;
  return new;
end;
$$;
drop trigger if exists msp_form_access_consume_draft on msp_form_access;
create trigger msp_form_access_consume_draft
  after update of used_by_intake on msp_form_access
  for each row execute function msp_intake_draft_on_consume();

-- Housekeeping: drafts whose token has expired.
create or replace function msp_draft_purge()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  delete from msp_intake_draft d
   using msp_form_access f
   where f.id = d.access_id and f.expires_at < now();
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke execute on function msp_draft_purge() from public, anon, authenticated;

notify pgrst, 'reload schema';

------------------------------------------------------------------------------
-- 045_msp_review_fee_bands.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | COM-02 v1.0.0 | The Plan is free, the review is banded 11/09/2026
-- Applied to the live project on 11/09/2026 (recorded there as 039_msp_review_fee_bands).
-- Numbered 045 in this repository because 039 to 044 were taken by the sign on,
-- self service, reference, legislation currency, contact number and draft work
-- that reached main first. The order of application in the live project was
-- 039 fee bands (11/09), then 040 self service (11/09) onward; nothing here
-- depends on those and nothing there depends on this.
-- The commercial model changes. The Plan itself is no longer priced from a rate
-- card: a company builds it at no charge and receives it watermarked. The only
-- charge is the practitioner review that lifts it into a document you can put in
-- front of an auditor or an inspector, and that is calculated per person on the
-- report with a floor for small jobs and a lower rate for large ones.
--
-- No price is published anywhere. The only number a visitor ever sees is the one
-- the calculator returns for the headcount they entered.

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('commercial.omp_review_rate_zar', '150', 'decimal', 0, 10000, 'commercial',
   'Practitioner review, rand per person on the report, standard rate.'),
  ('commercial.omp_review_rate_high_zar', '120', 'decimal', 0, 10000, 'commercial',
   'Practitioner review, rand per person, for reports above the high volume threshold.'),
  ('commercial.omp_review_high_threshold', '150', 'integer', 1, 100000, 'commercial',
   'Headcount above which the lower per person rate applies.'),
  ('commercial.omp_review_mid_threshold', '50', 'integer', 1, 100000, 'commercial',
   'Upper bound of the middle band, which carries a smaller surcharge.'),
  ('commercial.omp_review_small_threshold', '10', 'integer', 1, 100000, 'commercial',
   'Headcount below which the small job surcharge applies.'),
  ('commercial.omp_review_surcharge_small_zar', '1000', 'decimal', 0, 100000, 'commercial',
   'Surcharge added below the small threshold, because a short report still takes the practitioner a full sitting.'),
  ('commercial.omp_review_surcharge_mid_zar', '500', 'decimal', 0, 100000, 'commercial',
   'Surcharge added across the middle band.')
on conflict (key) do nothing;

-- The calculation, in one place, reading the bands every time so a change to a
-- parameter changes the next quotation with nothing redeployed.
create or replace function msp_review_fee(p_people int)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rate      numeric := msp_env_get_numeric('commercial.omp_review_rate_zar');
  v_rate_high numeric := msp_env_get_numeric('commercial.omp_review_rate_high_zar');
  v_high      int     := msp_env_get_int('commercial.omp_review_high_threshold');
  v_mid       int     := msp_env_get_int('commercial.omp_review_mid_threshold');
  v_small     int     := msp_env_get_int('commercial.omp_review_small_threshold');
  v_sur_small numeric := msp_env_get_numeric('commercial.omp_review_surcharge_small_zar');
  v_sur_mid   numeric := msp_env_get_numeric('commercial.omp_review_surcharge_mid_zar');
begin
  if p_people is null or p_people < 1 then
    raise exception 'the review fee needs a headcount of at least one';
  end if;
  if p_people > v_high then
    return round(p_people * v_rate_high, 2);
  elsif p_people > v_mid then
    return round(p_people * v_rate, 2);
  elsif p_people >= v_small then
    return round(p_people * v_rate + v_sur_mid, 2);
  else
    return round(p_people * v_rate + v_sur_small, 2);
  end if;
end;
$$;
comment on function msp_review_fee is
  'Practitioner review fee for a report covering this many people. Bands live in the parameter store, not in this function.';

-- The public face of the calculator. It returns the answer for the headcount
-- asked about and nothing else: no rate, no band table, no price list.
create or replace function msp_public_review_fee(p_people int)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_people is null or p_people < 1 or p_people > 100000 then
    return jsonb_build_object('ok', false, 'reason', 'headcount out of range');
  end if;
  return jsonb_build_object('ok', true, 'people', p_people, 'fee_zar', msp_review_fee(p_people));
end;
$$;
comment on function msp_public_review_fee is
  'Calculator endpoint for the website. Deliberately anonymous: it answers for one headcount and never discloses the bands behind the answer.';

revoke all on function msp_public_review_fee(int) from public;
grant execute on function msp_public_review_fee(int) to anon, authenticated;
revoke all on function msp_review_fee(int) from public, anon, authenticated;

-- Packages restated. The Plan is free; the review is what is bought.
alter table msp_package drop constraint if exists msp_package_fee_status_check;
alter table msp_package add constraint msp_package_fee_status_check
  check (fee_status in ('placeholder', 'confirmed', 'calculated'));

update msp_package set
  name = 'Your Plan, free to build',
  description = 'The full assessment and your Medical Surveillance Plan drafted against the verified law for your industry, delivered watermarked as your working copy. The watermark lifts for Care Net clients and when medicals are booked with Care Net.',
  omp_review_fee_zar = 0,
  fee_status = 'confirmed'
 where package_code = 'DRAFT_PLAN';

update msp_package set
  name = 'Reviewed and signed by the practitioner',
  description = 'Your Plan read line by line and signed by a registered Occupational Medical Practitioner, which is what makes it defensible in front of an auditor, an inspector or a client. Charged per person on the report.',
  omp_review_fee_zar = null,
  fee_status = 'calculated'
 where package_code = 'SIGNED_PLAN';

-- The quotation follows the same model: the Plan costs nothing, the review is
-- banded on headcount, and the free qualification now only ever affects the
-- watermark, because there is no longer a Plan price to waive.
create or replace function msp_create_quote(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pkg msp_package%rowtype;
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
  if v_emp < 1 then
    raise exception 'the headcount to be covered must be at least one';
  end if;

  select * into v_pkg from msp_package
   where package_code = upper(coalesce(p->>'package_code', 'SIGNED_PLAN'));
  if v_pkg.id is null then
    raise exception 'unknown package %', p->>'package_code';
  end if;

  v_free := v_medicals >= msp_env_get_int('commercial.free_medicals_threshold')
            or exists (select 1 from msp_client_account
                        where lower(contact_email) = lower(p->>'contact_email')
                          and sla_status = 'active_sla');

  if v_pkg.includes_omp_review then
    v_omp := msp_review_fee(v_emp);
  end if;

  v_status := case when v_omp = 0 then 'free_qualifying' else 'firm' end;

  v_ref := 'CNC-QTE-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(nextval('msp_quote_seq')::text, 3, '0');
  insert into msp_quote (quote_reference, company_name, contact_name, contact_email,
                         industry_code, company_size, employee_count, job_category_count,
                         annual_medicals_estimate, package_code, omp_review_fee_zar,
                         price_zar, price_status)
  values (v_ref, p->>'company_name', p->>'contact_name', p->>'contact_email',
          upper(coalesce(p->>'industry_code','OTHER')), p->>'company_size', v_emp, v_jobs,
          v_medicals, v_pkg.package_code, v_omp, v_omp, v_status)
  returning id into v_id;

  insert into msp_audit (actor, event_type, event_detail)
  values ('msp_create_quote', 'quote_created',
          jsonb_build_object('reference', v_ref, 'package', v_pkg.package_code,
                             'people', v_emp, 'review_fee_zar', v_omp,
                             'price_status', v_status, 'watermark_free', v_free));

  return jsonb_build_object('quote_id', v_id, 'reference', v_ref,
                            'package_name', v_pkg.name,
                            'plan_zar', 0,
                            'omp_review_fee_zar', v_omp,
                            'price_zar', v_omp,
                            'price_status', v_status,
                            'watermark_free', v_free,
                            'valid_until', (current_date + msp_env_get_int('commercial.quote_validity_days'))::text);
end;
$$;

------------------------------------------------------------------------------
-- 046_msp_public_instrument_register.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | KRN-PUB-02 v1.0.0 | Public legislation register 20/09/2026
-- Applied to the live project on 20/09/2026 (recorded there as
-- 040_msp_public_instrument_register). The website's Build your Plan page shows
-- the industries covered and every legal instrument the engine drafts from, with
-- its full citation, so a visitor can see what the Plan is built on before they
-- build one. This view is that register: verified instruments only, with the
-- industries each one applies to, readable by the anonymous key like the other
-- msp_public_* views. Nothing pending, nothing internal, nothing about clients.

create or replace view msp_public_instrument_register as
select li.short_name,
       li.full_citation,
       li.instrument_type,
       li.gazette_reference,
       li.effective_date,
       li.amendment_history,
       li.verified_on,
       li.review_due,
       (select coalesce(json_agg(json_build_object('code', i.code, 'name', i.name) order by i.name), '[]'::json)
          from msp_industry_instrument ii
          join msp_industry i on i.id = ii.industry_id
         where ii.instrument_id = li.id) as industries
  from msp_legal_instrument li
 where li.status = 'verified'
 order by li.short_name;

comment on view msp_public_instrument_register is
  'The legislation register as published on the website: verified instruments with full citation and the industries each applies to. Anonymous read.';

grant select on msp_public_instrument_register to anon, authenticated;

------------------------------------------------------------------------------
-- 047_hsf_core_schema.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | HSF-SCH-01 v1.0.0 | HSF FORGE core schema 23/09/2026
-- Anchors HSF-SCH-01 (library), HSF-ENG-01 (engagement), HSF-REV-01 (review and
-- release) and HSF-KRN-01 (kernel scope). Built to hsf/BUILD-CONTRACT.md section 3
-- (047) and SPEC.md Part B, B4.3 to B4.9, B5.1 and B5.2. Additive only: every new
-- object is hsf_ prefixed; the kernel gains two scope columns and msp_audit gains
-- a nullable file reference.
--
-- Access model (contract section 3):
--   Library tables: select for authenticated; no write policy, so only the
--   service role (and security definer functions owned by the migration role)
--   write them.
--   Engagement tables: a client reads the rows of its own account
--   (msp_client_account.auth_user_id = auth.uid()); staff read with forge_admin,
--   forge_omp or forge_safety_reviewer (JWT app_metadata roles, checked with
--   msp_has_role from migration 002; no database role is created). Writes go
--   through security definer functions only (migrations 049 and 051).
--   Everything is revoked from anon and public.
--
-- Two additive departures from the letter of SPEC B4.3, both needed to hold data
-- that SPEC B6 defines and the seed (048) loads:
--   1. hsf_appointment_type.trigger_code (B6.3.1 gives every appointment type a
--      trigger; B4.3 had no column for it).
--   2. hsf_element_class: the course (B6.5.1), licence class (B6.5.2) and
--      examination class (B6.6, HSF-E-06) items that B9.3.4 expands per File.
--      hsf_training_requirement stays as B4.3 wrote it and is not seeded, because
--      its check needs a job role or an appointment and B6.5.1 names neither.

-- 1. Kernel extension (B5.1, B5.2) ---------------------------------------------

alter table msp_legal_instrument
  add column if not exists scope text not null default 'medical'
    check (scope in ('medical','safety','both'));
comment on column msp_legal_instrument.scope is
  'HSF-KRN-01 (SPEC B5.1). medical: held for Medical Surveillance Plans. safety: a Health and Safety File candidate. both: re verified in full scope for the File provisions it serves. Held instruments move to both only after re verification; candidates enter as safety, status pending.';

alter table msp_industry_instrument
  add column if not exists scope text not null default 'medical'
    check (scope in ('medical','safety','both'));
comment on column msp_industry_instrument.scope is
  'HSF-KRN-01 (SPEC B5.2). Lets an industry map carry an instrument for safety without implying a medical duty.';

-- B4.8: the published register gains the scope column now that B5.1 has landed.
-- Same definition as migration 046, with scope appended as the last column.
-- Migration 050 redefines it once more with the currency hold predicate
-- (contract 9.4), after msp_instrument_currency_hold exists.
create or replace view msp_public_instrument_register as
select li.short_name,
       li.full_citation,
       li.instrument_type,
       li.gazette_reference,
       li.effective_date,
       li.amendment_history,
       li.verified_on,
       li.review_due,
       (select coalesce(json_agg(json_build_object('code', i.code, 'name', i.name) order by i.name), '[]'::json)
          from msp_industry_instrument ii
          join msp_industry i on i.id = ii.industry_id
         where ii.instrument_id = li.id) as industries,
       li.scope
  from msp_legal_instrument li
 where li.status = 'verified'
 order by li.short_name;
grant select on msp_public_instrument_register to anon, authenticated;

-- 2. Library tables (HSF-SCH-01, B4.3) ------------------------------------------

create table hsf_section (
  code text primary key check (code ~ '^[A-O]$'),
  ordinal int unique not null check (ordinal between 1 and 15),
  name text not null,
  description text not null,
  signatory_kind text not null check (signatory_kind in ('omp','safety'))
);
comment on table hsf_section is 'HSF-SCH-01. The fifteen sections of the Health and Safety File, A to O. Section E is signed by the OMP; every other section by the safety content signatory (HSF-1).';

create table hsf_department (
  code text primary key,
  name text not null,
  ordinal int unique not null check (ordinal >= 1)
);
comment on table hsf_department is 'Contract section 2. The company department a client files an upload under. Every upload carries a department code and a File section code.';

create table hsf_trigger (
  code text primary key,
  description text not null
);
comment on table hsf_trigger is 'SPEC B9.2 trigger vocabulary. An intake answer or a kernel fact raises a trigger, which switches a conditional element on. Compound rows (A or B, A and B) carry the expressions the library itself uses; the generator evaluates them as hsf/build_samples.py does.';

create table hsf_appointment_type (
  code text primary key,
  name text not null,
  instrument_id uuid references msp_legal_instrument(id),
  provision text not null,
  competence_requirement text not null,
  ratio_rule text,
  regime text not null default 'BOTH' check (regime in ('OHSA','MHSA','BOTH')),
  trigger_code text references hsf_trigger(code)
);
comment on table hsf_appointment_type is 'HSF-SCH-01 (SPEC B6.3.1). Statutory appointment types, APP-00 to APP-40. Each applicable type yields one HSF-B-06 item. instrument_id is the first basis named; hsf_element_instrument carries the full basis of HSF-B-06.';
comment on column hsf_appointment_type.trigger_code is 'Additive to SPEC B4.3: the B6.3.1 trigger. Null means every File (U).';
comment on column hsf_appointment_type.ratio_rule is 'msp_kernel_rule code where the law sets a ratio (for example RULE-HSF-RATIO-FA). The rule itself is loaded in Phase 3 (HSF-RUL-01).';

create table hsf_element (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  section_code text not null references hsf_section(code),
  name text not null,
  duty text not null,
  evidence_type text not null check (evidence_type in
    ('document','register','certificate','appointment','plan','report','permit',
     'minutes','training_record','medical_certificate','licence','agreement','log')),
  responsible_appointment text references hsf_appointment_type(code),
  responsible_role text,
  review_interval text not null check (review_interval in
    ('annual','on_change','per_event','per_project','monthly','daily','before_use','on_expiry','statutory')),
  review_interval_param text,
  retention_rule text,
  regime text not null default 'BOTH' check (regime in ('OHSA','MHSA','BOTH')),
  mhsa_equivalent_id uuid references hsf_element(id),
  universal boolean not null default true,
  trigger_code text references hsf_trigger(code),
  mco_source text check (mco_source in ('mco_medical','mco_training')),
  basis_state text not null default 'awaiting'
    check (basis_state in ('verified','awaiting')),
  status text not null default 'active' check (status in ('active','retired')),
  created_at timestamptz default now()
);
comment on table hsf_element is 'HSF-SCH-01. The element library: SPEC B6 universal elements (universal true) and B7 industry overlay additions (universal false). basis_state moves to verified only when every instrument the element cites is verified (Phase 2 gate).';
comment on column hsf_element.trigger_code is 'SPEC B9.2 trigger that switches the element on. Null means every File (U), including the per appointment, per course and per class elements that expand through hsf_appointment_type and hsf_element_class.';
comment on column hsf_element.retention_rule is 'msp_kernel_rule code (RULE-RETAIN-*) once HSF-RUL-01 lands. Until then the seed holds the SPEC B6.1.4 retention class (MED40, INST, LIFE); null means the retention is open under HSF-5.';

create table hsf_element_instrument (
  element_id uuid references hsf_element(id),
  instrument_id uuid references msp_legal_instrument(id),
  provision text not null,
  primary key (element_id, instrument_id)
);
comment on table hsf_element_instrument is 'HSF-SCH-01. The instruments an element cites. provision reads awaiting verification until Phase 2 pins it through the three gates.';

create table hsf_element_industry (
  element_id uuid references hsf_element(id),
  industry_id uuid references msp_industry(id),
  subindustry_id uuid references msp_subindustry(id),
  applicability text not null check (applicability in ('mandatory','conditional','emphasis')),
  overlay_note text not null,
  unique (element_id, industry_id, subindustry_id)
);
comment on table hsf_element_industry is 'HSF-SCH-01 (SPEC B7). Industry overlays: the additions of each industry, the universal elements each overlay switches on, and the surveillance protocols the kernel pack emphasises. A null subindustry means the whole industry.';

create table hsf_training_requirement (
  id uuid primary key default gen_random_uuid(),
  job_role_id uuid references msp_job_role(id),
  appointment_code text references hsf_appointment_type(code),
  competency text not null,
  unit_standard_or_course text,
  renewal_months int check (renewal_months is null or renewal_months > 0),
  renewal_param text,
  instrument_id uuid references msp_legal_instrument(id),
  check (job_role_id is not null or appointment_code is not null)
);
comment on table hsf_training_requirement is 'HSF-SCH-01. Statutory competency per kernel job role or per appointment type. Unit standard numbers are entered only after verification. Loaded in Phase 3 once the role mapping is data.';

create table hsf_element_class (
  code text primary key,
  element_code text not null references hsf_element(code),
  kind text not null check (kind in ('course','licence','examination')),
  ordinal int not null check (ordinal >= 1),
  name text not null,
  trigger_code text references hsf_trigger(code),
  instrument_id uuid references msp_legal_instrument(id),
  provision text not null default 'awaiting verification',
  mco_source text check (mco_source in ('mco_medical','mco_training')),
  unique (element_code, ordinal)
);
comment on table hsf_element_class is 'Additive to SPEC B4.3. The items an element expands into per File (B9.3.4): courses D04-nn under HSF-D-04 (B6.5.1), licence classes D05-nn under HSF-D-05 (B6.5.2), examination classes E06-nn under HSF-E-06 (B6.6). A null trigger means every File.';

-- 3. Gap safe File reference ------------------------------------------------------

create or replace function hsf_next_reference()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text := 'CNC-HSF-' || to_char(current_date, 'YYYY-MMDD') || '-';
  v_n int;
begin
  perform pg_advisory_xact_lock(hashtext('hsf_file_reference'));
  -- Three digits or more: the thousandth File of a day is NNNN, never a
  -- truncated repeat of an earlier number (contract 9.6).
  select coalesce(max(substring(reference from '(\d{3,})$')::int), 0) + 1 into v_n
    from hsf_file
   where reference like v_prefix || '%';
  return v_prefix || lpad(v_n::text, greatest(3, length(v_n::text)), '0');
end;
$$;
revoke execute on function hsf_next_reference() from public, anon, authenticated;
comment on function hsf_next_reference is 'CNC-HSF-YYYY-MMDD-NNN. NNN = highest existing number for the day + 1 (gap safe, the migration 041 pattern), at least three digits and never truncated (1000 follows 999). Advisory lock serialises concurrent Files.';

-- 4. Engagement tables (HSF-ENG-01, B4.4) ----------------------------------------

create table hsf_file (
  id uuid primary key default gen_random_uuid(),
  reference text unique not null default hsf_next_reference(),
  client_account_id uuid not null references msp_client_account(id),
  engagement_id uuid references msp_engagement(id),
  parent_file_id uuid references hsf_file(id),
  industry_id uuid not null references msp_industry(id),
  subindustry_id uuid references msp_subindustry(id),
  regime text not null check (regime in ('OHSA','MHSA')),
  scope jsonb not null,
  revision int not null default 1,
  status text not null default 'draft' check (status in
    ('draft','generating','in_review','approved','released','live','superseded','archived')),
  compliance_pct numeric(5,2),
  created_at timestamptz default now()
);
comment on table hsf_file is 'HSF-ENG-01. One Health and Safety File per client engagement scope. reference is CNC-HSF-YYYY-MMDD-NNN from hsf_next_reference(). parent_file_id models construction layering (RULE-HSF-CONSTR-LAYER). compliance_pct is cached by hsf_compute_compliance.';

create table hsf_file_item (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  element_id uuid not null references hsf_element(id),
  site_ref text,
  status text not null default 'outstanding' check (status in
    ('linked_mco','uploaded','outstanding','not_applicable','expired')),
  reason text,
  responsible_person text,
  due_date date,
  updated_at timestamptz default now(),
  constraint na_needs_reason check (status <> 'not_applicable' or length(btrim(coalesce(reason,''))) >= 10),
  unique (file_id, element_id, site_ref)
);
comment on table hsf_file_item is 'HSF-ENG-01. One row per applicable element (per site where the element is per site). not_applicable needs a written reason of at least ten characters.';

create table hsf_evidence (
  id uuid primary key default gen_random_uuid(),
  file_item_id uuid not null references hsf_file_item(id),
  version int not null,
  supersedes_id uuid references hsf_evidence(id),
  source text not null check (source in ('mco_medical','mco_training','client_upload','engine_generated')),
  mco_record_ref text,
  storage_path text,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  supplied_by text not null,
  supplied_at timestamptz not null default now(),
  valid_from date,
  valid_to date,
  revoked_at timestamptz,
  upload_id uuid,
  mco_document_ref text,
  transferred_at timestamptz,
  staging_deleted_at timestamptz,
  unique (file_item_id, version),
  check (source not like 'mco_%' or mco_record_ref is not null)
);
comment on table hsf_evidence is 'HSF-ENG-01. Append only evidence ledger. A replacement is a new row with version n + 1 and supersedes_id; nothing is ever deleted. The only permitted updates are one way: revoked_at once; mco_document_ref with transferred_at once; staging_deleted_at once together with storage_path set to null (contract section 3).';
comment on column hsf_evidence.storage_path is 'Path in the private hsf-staging bucket while the bytes are held by Care Net; null once the bytes have been transferred to MyClinicOnline and removed from staging. The row and its hash stay for the audit trail.';
comment on column hsf_evidence.upload_id is 'The hsf_upload row the bytes arrived through. The foreign key is added in migration 049, which creates hsf_upload.';

create or replace function hsf_evidence_guard()
returns trigger
language plpgsql
as $$
declare
  v_mutable constant text[] := array['revoked_at','mco_document_ref','transferred_at','staging_deleted_at','storage_path'];
begin
  if tg_op = 'DELETE' then
    raise exception 'hsf_evidence is append only: delete refused';
  end if;
  if (to_jsonb(new) - v_mutable) is distinct from (to_jsonb(old) - v_mutable) then
    raise exception 'hsf_evidence is append only: only revocation, the MyClinicOnline transfer record and the staging deletion may be recorded';
  end if;
  if new.revoked_at is distinct from old.revoked_at
     and (old.revoked_at is not null or new.revoked_at is null) then
    raise exception 'hsf_evidence: revoked_at is set once and never cleared';
  end if;
  if (new.mco_document_ref is distinct from old.mco_document_ref
      or new.transferred_at is distinct from old.transferred_at)
     and (old.mco_document_ref is not null or old.transferred_at is not null
          or new.mco_document_ref is null or new.transferred_at is null) then
    raise exception 'hsf_evidence: mco_document_ref and transferred_at are set once, together';
  end if;
  if new.staging_deleted_at is distinct from old.staging_deleted_at
     and (old.staging_deleted_at is not null or new.staging_deleted_at is null
          or new.storage_path is not null) then
    raise exception 'hsf_evidence: staging_deleted_at is set once, together with storage_path set to null';
  end if;
  if new.storage_path is distinct from old.storage_path
     and not (new.storage_path is null and old.staging_deleted_at is null and new.staging_deleted_at is not null) then
    raise exception 'hsf_evidence: storage_path changes only to null when the staging deletion is recorded';
  end if;
  return new;
end;
$$;
comment on function hsf_evidence_guard is 'Append only guard for hsf_evidence: refuses delete and every update other than the one way transitions named in the contract.';

create trigger hsf_evidence_append_only
  before update or delete on hsf_evidence
  for each row execute function hsf_evidence_guard();

create table hsf_person (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  mco_person_ref text,
  employee_number text,
  display_name text not null,
  id_last4 text check (id_last4 ~ '^[0-9]{4}$'),
  job_role_id uuid references msp_job_role(id),
  work_restriction text,
  unique (file_id, mco_person_ref)
);
comment on table hsf_person is 'HSF-ENG-01. People on a File. Matched to MyClinicOnline on mco_person_ref only, never on name (B10.3). Last four identity digits only. work_restriction is the placement restriction an employer may hold, never a diagnosis.';

create table hsf_appointment (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  appointment_code text not null references hsf_appointment_type(code),
  person_id uuid references hsf_person(id),
  appointee_name text not null,
  appointed_on date,
  accepted_on date,
  acceptance_evidence_id uuid references hsf_evidence(id),
  competence_evidence_id uuid references hsf_evidence(id)
);
comment on table hsf_appointment is 'HSF-ENG-01. Statutory appointments in post on a File, each with its acceptance and competence evidence.';

create table hsf_revision (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  revision int not null,
  trigger_kind text not null check (trigger_kind in
    ('change_notification','risk_assessment_update','new_appointment','expiry','kernel_release','client_request')),
  summary text not null,
  opened_at timestamptz default now(),
  closed_at timestamptz,
  unique (file_id, revision)
);
comment on table hsf_revision is 'HSF-ENG-01. The living File: every revision, why it opened and when it closed.';

-- 5. Review and release (HSF-REV-01, B4.5) ---------------------------------------

create table hsf_signoff (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  revision int not null,
  kind text not null check (kind in ('omp_medical','safety_content','client_16_2_acceptance')),
  decision text check (decision in ('approved','amended','rejected')),
  signatory_name text,
  registration_body text,
  registration_number text,
  decided_at timestamptz,
  notes jsonb,
  constraint decision_complete check (decision is null or
    (signatory_name is not null and decided_at is not null
     and (kind = 'client_16_2_acceptance' or registration_number is not null)))
);
comment on table hsf_signoff is 'HSF-REV-01. The three sign offs a release needs: the OMP for Section E only, the safety content signatory (HSF-1) and the client section 16(2) acceptance.';

create table hsf_release (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  revision int not null,
  pdf_path text not null,
  evidence_index_path text not null,
  released_at timestamptz default now(),
  unique (file_id, revision)
);
comment on table hsf_release is 'HSF-REV-01. A released File revision. The hsf_release_gate trigger refuses the insert unless all three sign offs are approved and every instrument the File''s elements name is citable for a File (hsf_element_citable, contract 9.3).';

create or replace function hsf_release_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind text;
  v_unverified text;
begin
  foreach v_kind in array array['omp_medical','safety_content','client_16_2_acceptance'] loop
    if not exists (select 1 from hsf_signoff s
                    where s.file_id = new.file_id and s.revision = new.revision
                      and s.kind = v_kind and s.decision = 'approved') then
      raise exception 'hsf_release_gate: % sign off is not approved for this File revision', v_kind;
    end if;
  end loop;
  -- Contract 9.3: hsf_element_citable (migration 050) is the single definition of
  -- an instrument a File element may cite: verified, not held, not superseded,
  -- scope safety or both, and a provision pinned past 'awaiting verification'.
  -- Every instrument an item's element names must pass it.
  select string_agg(distinct li.short_name, ', ' order by li.short_name) into v_unverified
    from hsf_file_item fi
    join hsf_element_instrument ei on ei.element_id = fi.element_id
    join msp_legal_instrument li on li.id = ei.instrument_id
   where fi.file_id = new.file_id
     and not (hsf_element_citable(fi.element_id) ? li.short_name);
  if v_unverified is not null then
    raise exception 'hsf_release_gate: the File cites instruments that are not verified for a File: %', v_unverified;
  end if;
  return new;
end;
$$;
revoke execute on function hsf_release_gate() from public, anon, authenticated;
comment on function hsf_release_gate is 'SPEC B4.5 and B11.2, contract 9.3. Three approved sign offs, and every instrument the File''s elements name citable for a File by hsf_element_citable (defined in migration 050; resolved when the trigger runs). Enforced in the database; the parameter hsf.release_required is display only and does not relax it.';

create trigger hsf_release_gate
  before insert on hsf_release
  for each row execute function hsf_release_gate();

create or replace function hsf_file_item_touch()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger hsf_file_item_touch
  before update on hsf_file_item
  for each row execute function hsf_file_item_touch();

-- 6. Client account and audit extensions (B4.6, B4.9) ----------------------------

alter table msp_client_account add column if not exists mco_company_ref text unique;
comment on column msp_client_account.mco_company_ref is 'SPEC B4.6. The MyClinicOnline company reference. Null until the MCO interface contract arrives (HSF-3); the adapter refuses to run for an account without it.';

alter table msp_audit add column if not exists hsf_file_id uuid references hsf_file(id);
create index if not exists msp_audit_hsf_file_idx on msp_audit(hsf_file_id);
comment on column msp_audit.hsf_file_id is 'SPEC B4.9 (HSF-4). The Health and Safety File an audit row concerns. A row may carry engagement_id, hsf_file_id, both or neither (kernel events); the msp_audit append only trigger and the existing read policy apply unchanged.';

-- 7. Indexes ----------------------------------------------------------------------

create index hsf_element_section_idx on hsf_element(section_code);
create index hsf_element_trigger_idx on hsf_element(trigger_code);
create index hsf_element_instrument_instrument_idx on hsf_element_instrument(instrument_id);
create index hsf_element_industry_industry_idx on hsf_element_industry(industry_id);
create index hsf_element_class_element_idx on hsf_element_class(element_code);
create index hsf_file_client_idx on hsf_file(client_account_id);
create index hsf_file_parent_idx on hsf_file(parent_file_id);
create index hsf_file_item_file_idx on hsf_file_item(file_id);
create index hsf_file_item_element_idx on hsf_file_item(element_id);
create index hsf_evidence_item_idx on hsf_evidence(file_item_id);
create index hsf_evidence_upload_idx on hsf_evidence(upload_id);
create index hsf_person_file_idx on hsf_person(file_id);
create index hsf_appointment_file_idx on hsf_appointment(file_id);
create index hsf_revision_file_idx on hsf_revision(file_id);
create index hsf_signoff_file_idx on hsf_signoff(file_id, revision);

-- 8. Row Level Security -------------------------------------------------------------

create or replace function hsf_is_staff()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select public.msp_has_role('forge_admin')
      or public.msp_has_role('forge_omp')
      or public.msp_has_role('forge_safety_reviewer');
$$;
comment on function hsf_is_staff is 'True for the staff roles that read Health and Safety File engagement data: forge_admin, forge_omp, forge_safety_reviewer.';

create or replace function hsf_can_read_file(p_file_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select hsf_is_staff()
      or exists (select 1
                   from hsf_file f
                   join msp_client_account a on a.id = f.client_account_id
                  where f.id = p_file_id
                    and auth.uid() is not null
                    and a.auth_user_id = auth.uid());
$$;
revoke execute on function hsf_can_read_file(uuid) from public, anon;
grant execute on function hsf_can_read_file(uuid) to authenticated;
comment on function hsf_can_read_file is 'RLS helper: staff, or the client contact whose account owns the File. Security definer so the policy can see msp_client_account without widening its own policies.';

create or replace function hsf_can_read_item(p_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from hsf_file_item fi
                  where fi.id = p_item_id and hsf_can_read_file(fi.file_id));
$$;
revoke execute on function hsf_can_read_item(uuid) from public, anon;
grant execute on function hsf_can_read_item(uuid) to authenticated;
comment on function hsf_can_read_item is 'RLS helper for hsf_evidence: readable when the File of the item is readable.';

revoke execute on function hsf_is_staff() from public, anon;
grant execute on function hsf_is_staff() to authenticated;

do $$
declare
  t text;
begin
  -- Library tables: authenticated read, no writes except the service role.
  foreach t in array array['hsf_section','hsf_department','hsf_trigger','hsf_appointment_type',
                           'hsf_element','hsf_element_instrument','hsf_element_industry',
                           'hsf_training_requirement','hsf_element_class'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_read', t);
  end loop;
  -- Engagement tables: own account or staff; writes only through security definer functions.
  foreach t in array array['hsf_file','hsf_file_item','hsf_evidence','hsf_person','hsf_appointment',
                           'hsf_revision','hsf_signoff','hsf_release'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;

create policy hsf_file_read on hsf_file
  for select to authenticated using (hsf_can_read_file(id));
create policy hsf_file_item_read on hsf_file_item
  for select to authenticated using (hsf_can_read_file(file_id));
create policy hsf_evidence_read on hsf_evidence
  for select to authenticated using (hsf_can_read_item(file_item_id));
create policy hsf_person_read on hsf_person
  for select to authenticated using (hsf_can_read_file(file_id));
create policy hsf_appointment_read on hsf_appointment
  for select to authenticated using (hsf_can_read_file(file_id));
create policy hsf_revision_read on hsf_revision
  for select to authenticated using (hsf_can_read_file(file_id));
create policy hsf_signoff_read on hsf_signoff
  for select to authenticated using (hsf_can_read_file(file_id));
create policy hsf_release_read on hsf_release
  for select to authenticated using (hsf_can_read_file(file_id));

grant execute on function hsf_next_reference() to service_role;

------------------------------------------------------------------------------
-- 048_hsf_library_seed.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | HSF-SEED-01 v1.0.0 | HSF FORGE element library seed 23/09/2026
-- GENERATED by hsf/build_seed.py from SPEC.md Part B (B6, B6.3.1, B6.5.1, B6.5.2,
-- B7, B9.2) and the CNC OHS Industry Kernel pack protocols. Do not edit by hand:
-- change the SPEC or the generator and run  python3 hsf/build_seed.py
--
-- Loads: 15 sections, 9 departments, 49 triggers (44 vocabulary, 5 compound),
-- 41 appointment types, 256 elements (137 universal, 119 overlay), 34 element classes,
-- 298 element industry rows, 354 element instrument links, and 36 candidate
-- instruments entered as status pending, scope safety, gates a to c pending.
-- Every element is awaiting verification; every link reads awaiting verification.
-- Names are in plain words: no provision numbers other than section 16(2) and
-- section 37(2) until Phase 2 pins them (contract 10.9(c)).
-- Idempotent. Never updates or deletes an existing msp_legal_instrument row:
-- candidates are inserted only where no row carries the same short_name.

-- 0. Precondition (SPEC B8.2, HSF-7): the held instruments the library cites must
--    be in the kernel, or their links would be silently lost. Refuse otherwise.
do $$
declare
  v_missing text;
begin
  select string_agg(n, '; ' order by n) into v_missing
    from unnest(array[
      'Asbestos Abatement Regulations, 2020',
      'BCEA night work Code',
      'COIDA',
      'Construction Regulations, 2014',
      'Driven Machinery Regulations',
      'EEA section 7',
      'Electrical Machinery and Installation Regulations',
      'Ergonomics Regulations, 2019',
      'Facilities Regulations, 2004',
      'Fitness to Perform Work Guideline (MHSA)',
      'Food Premises Hygiene Regulations, R638 of 2018',
      'General Administrative Regulations, 2003',
      'General Machinery Regulations, 1988',
      'General Safety Regulations, 1986',
      'HBA Regulations, 2022',
      'HCA Regulations, 2021',
      'HPCSA Booklet 1',
      'Hazardous Substances Act (radiation control)',
      'Health Professions Act',
      'Lead Regulations, 2001',
      'MHI Regulations, 2022',
      'MHSA',
      'NEM Waste Act',
      'NRTA PrDP medical',
      'Noise Exposure Regulations, 2024',
      'Nursing Act',
      'ODMWA',
      'OHS Act',
      'POPIA',
      'Physical Agents Regulations, 2024',
      'SANS 3000-4 (RSR)'
    ]) as n
   where not exists (select 1 from msp_legal_instrument li where li.short_name = n);
  if v_missing is not null then
    raise exception 'HSF seed refused: the kernel does not hold %. Apply migration 042 (release 1.1.0) first (HSF-7).', v_missing;
  end if;
end;
$$;

-- 1. Sections A to O --------------------------------------------------------------
insert into hsf_section (code, ordinal, name, description, signatory_kind) values
  ('A', 1, 'Legal and administrative', 'Company identity, the scope of the File, letters of good standing, construction notifications, contractor agreements and the dated legal register.', 'safety'),
  ('B', 2, 'Policy, organisation and appointments', 'The health and safety policy, chief executive responsibility, the section 16(2) assignment, representatives, the committee and every statutory appointment.', 'safety'),
  ('C', 3, 'Risk management', 'Baseline, issue based and task based risk assessments, the hazard register, the hierarchy of control, safe work procedures and activity plans.', 'safety'),
  ('D', 4, 'Training and competence', 'Training needs, the training matrix, inductions, statutory training records, licences and competency assessments.', 'safety'),
  ('E', 5, 'Medical surveillance and fitness', 'The Medical Surveillance Plan, certificates of fitness, statutory examinations and the handling of medical records. Signed by the occupational medical practitioner only.', 'omp'),
  ('F', 6, 'Registers and inspections', 'Registers of equipment, installations and workplaces, with their inspection records.', 'safety'),
  ('G', 7, 'Permits and controls', 'The permit to work system and the permits issued for high risk work.', 'safety'),
  ('H', 8, 'Emergency preparedness', 'Emergency plans, drills, fire arrangements, medical emergency arrangements and spill response.', 'safety'),
  ('I', 9, 'Incident management', 'Incident reporting, the incident register, investigations, COIDA records and corrective actions.', 'safety'),
  ('J', 10, 'Occupational hygiene', 'Occupational hygiene surveys and exposure monitoring.', 'safety'),
  ('K', 11, 'Contractors, visitors and the public', 'Contractor selection and control, visitor control and the protection of the public.', 'safety'),
  ('L', 12, 'Communication and consultation', 'Committee minutes, representative inspections, toolbox talks, notices and change notifications.', 'safety'),
  ('M', 13, 'Environment, welfare and facilities', 'Welfare facilities, the physical environment, environmental management and waste.', 'safety'),
  ('N', 14, 'Audit, review and improvement', 'Internal and external audits, management review, objectives and corrective actions.', 'safety'),
  ('O', 15, 'Records and retention', 'The retention schedule, storage and access control, and the POPIA operator agreement.', 'safety')
on conflict (code) do nothing;

-- 2. Departments (contract section 2) -------------------------------------------------
insert into hsf_department (code, name, ordinal) values
  ('EXEC', 'Executive and legal', 1),
  ('HR', 'Human resources', 2),
  ('SHE', 'Health and safety', 3),
  ('OPS', 'Operations', 4),
  ('ENG', 'Engineering and maintenance', 5),
  ('PROC', 'Procurement and contractors', 6),
  ('OH', 'Occupational health and medical', 7),
  ('TRAIN', 'Training and development', 8),
  ('FAC', 'Facilities and security', 9)
on conflict (code) do nothing;

-- 3. Triggers (SPEC B9.2), then the compound expressions the library uses --------------
insert into hsf_trigger (code, description) values
  ('T-CONSTR', 'Construction work is carried on'),
  ('T-CONSTR-NOTIFY', 'Construction work at or above the notification or permit thresholds (thresholds pinned in Phase 2)'),
  ('T-CONTRACTORS', 'Contractors or mandataries work for the employer'),
  ('T-HSR', 'The workforce requires designated health and safety representatives'),
  ('T-COMMITTEE', 'A health and safety committee is required'),
  ('T-HEIGHT', 'Work at height'),
  ('T-SCAFFOLD', 'Scaffolding is erected or used'),
  ('T-EXCAVATION', 'Excavation work'),
  ('T-DEMOLITION', 'Demolition work'),
  ('T-TEMPWORKS', 'Temporary works'),
  ('T-MOBILEPLANT', 'Construction vehicles, forklifts or other mobile plant'),
  ('T-ELEC', 'Electrical installations or electrical work'),
  ('T-LIFTING', 'Lifting machines and lifting tackle'),
  ('T-MACHINERY', 'Machinery that needs guarding and supervision'),
  ('T-PRESSURE', 'Pressure equipment'),
  ('T-HCA', 'Hazardous chemical agents are used, stored or produced'),
  ('T-HBA', 'Exposure to hazardous biological agents'),
  ('T-LADDERS', 'Ladders are used'),
  ('T-STACKING', 'Goods are stacked and stored'),
  ('T-CONFINED', 'Confined spaces are entered'),
  ('T-EPT', 'Explosive powered tools are used'),
  ('T-HOTWORK', 'Hot work such as welding, cutting or grinding'),
  ('T-ASBESTOS', 'Asbestos is present or may be disturbed'),
  ('T-LEAD', 'Work with lead'),
  ('T-NOISE', 'Noise exposure identified by the risk assessment'),
  ('T-RADIATION', 'Ionising radiation sources'),
  ('T-FOOD', 'Food is prepared, handled or served'),
  ('T-PRDP', 'Drivers who need a professional driving permit'),
  ('T-MINING', 'A mine, under the Mine Health and Safety Act regime'),
  ('T-TASKRA', 'Task based and daily pre task risk assessments are needed'),
  ('T-TRAFFIC', 'Vehicles and people share space'),
  ('T-SHIFT', 'Shift or night work'),
  ('T-VIOLENCE', 'Exposure to violence or aggression'),
  ('T-MHI', 'Holdings of listed substances at or above the major hazard installation thresholds (pinned in Phase 2)'),
  ('T-THERMAL', 'Heat or cold exposure'),
  ('T-WASTE', 'Waste is generated, handled or disposed of'),
  ('T-ENVIRO', 'Other environmental law applies'),
  ('T-PTW', 'A permit to work system is needed'),
  ('T-ROADWORKS', 'Work on or next to public roads'),
  ('T-SECURITY', 'Private security services are provided'),
  ('T-ARMED', 'Armed security or firearms are carried'),
  ('T-LPG', 'Liquefied petroleum gas installations'),
  ('T-EXPLOSIVES', 'Explosives are used'),
  ('T-PUBLIC', 'Members of the public may be affected by the work'),
  ('T-CONSTR and T-ELEC', 'Compound: raised when all of T-CONSTR, T-ELEC are raised'),
  ('T-HCA or T-LEAD', 'Compound: raised when any of T-HCA, T-LEAD is raised'),
  ('T-LIFTING or T-MOBILEPLANT', 'Compound: raised when any of T-LIFTING, T-MOBILEPLANT is raised'),
  ('T-SHIFT or T-VIOLENCE', 'Compound: raised when any of T-SHIFT, T-VIOLENCE is raised'),
  ('T-WASTE or T-ENVIRO', 'Compound: raised when any of T-WASTE, T-ENVIRO is raised')
on conflict (code) do nothing;

-- 4. Candidate instruments (SPEC B8.1): pending, scope safety, uncitable until gates a, b and c pass
insert into msp_legal_instrument
  (short_name, full_citation, instrument_type, source_one, source_two, source_three, status, scope)
select v.short_name, v.full_citation, v.instrument_type, 'Gate a pending', 'Gate b pending', 'Gate c pending', 'pending', 'safety'
  from (values
    ('BCEA', 'BCEA (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Civil Aviation Act', 'Civil Aviation Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Civil Aviation Regulations', 'Civil Aviation Regulations (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('Code of Good Practice on Employment of Persons with Disabilities', 'Code of Good Practice on Employment of Persons with Disabilities (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'code'),
    ('DMRE mandatory Code guidelines', 'DMRE mandatory Code guidelines (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'guideline'),
    ('Disaster Management Act', 'Disaster Management Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Electrical Installation Regulations, 2009', 'Electrical Installation Regulations, 2009 (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('Explosive powered tools regulations', 'Explosive powered tools regulations (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('Explosives Regulations', 'Explosives Regulations (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('Fire Brigade Services Act', 'Fire Brigade Services Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Firearms Control Act', 'Firearms Control Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Foodstuffs, Cosmetics and Disinfectants Act', 'Foodstuffs, Cosmetics and Disinfectants Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Health Care Waste regulations', 'Health Care Waste regulations (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('Local by laws', 'Local by laws (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('Local fire by laws', 'Local fire by laws (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('MHSA regulations', 'MHSA regulations (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('Merchant Shipping Act', 'Merchant Shipping Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('NEMA and its instruments', 'NEMA and its instruments (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('National Health Act', 'National Health Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('National Road Traffic Act', 'National Road Traffic Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('PSIRA training regulations', 'PSIRA training regulations (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('Ports Act', 'Ports Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Pressure Equipment Regulations, 2009', 'Pressure Equipment Regulations, 2009 (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('Private Security Industry Regulation Act', 'Private Security Industry Regulation Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Railway Safety Regulator Act', 'Railway Safety Regulator Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Regulations on Hazardous Work by Children, 2010', 'Regulations on Hazardous Work by Children, 2010 (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'regulation'),
    ('SAHPRA provisions', 'SAHPRA provisions (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('SANS 10142', 'SANS 10142 (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'sans'),
    ('SANS 10231', 'SANS 10231 (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'sans'),
    ('SANS 10232', 'SANS 10232 (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'sans'),
    ('SANS 10400', 'SANS 10400 (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'sans'),
    ('SANS 10400 T part', 'SANS 10400 T part (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'sans'),
    ('SANS 3000 series', 'SANS 3000 series (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'sans'),
    ('SETA unit standards', 'SETA unit standards (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'guideline'),
    ('Skills Development Act', 'Skills Development Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act'),
    ('Tobacco Products Control Act', 'Tobacco Products Control Act (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)', 'act')
       ) as v(short_name, full_citation, instrument_type)
 where not exists (select 1 from msp_legal_instrument li where li.short_name = v.short_name);

-- 5. Appointment types (SPEC B6.3.1) --------------------------------------------------
insert into hsf_appointment_type (code, name, instrument_id, provision, competence_requirement, ratio_rule, regime, trigger_code)
select v.code, v.name, (select li.id from msp_legal_instrument li where li.short_name = v.short_name order by case li.status when 'verified' then 0 when 'pending' then 1 when 'superseded' then 2 else 3 end, li.verified_on desc nulls last, li.id limit 1),
       'awaiting verification',
       'Pending: the competence requirement is pinned from the governing provision in Phase 2 (SPEC B8).',
       v.ratio_rule, v.regime, v.trigger_code
  from (values
    ('APP-00', 'Section 16(2) assignee', 'OHS Act', null, 'BOTH', null),
    ('APP-01', 'Construction manager', 'Construction Regulations, 2014', null, 'BOTH', 'T-CONSTR'),
    ('APP-02', 'Assistant construction manager', 'Construction Regulations, 2014', null, 'BOTH', 'T-CONSTR'),
    ('APP-03', 'Construction health and safety officer', 'Construction Regulations, 2014', null, 'BOTH', 'T-CONSTR'),
    ('APP-04', 'Construction supervisor', 'Construction Regulations, 2014', null, 'BOTH', 'T-CONSTR'),
    ('APP-05', 'Risk assessor', 'Construction Regulations, 2014', null, 'BOTH', null),
    ('APP-06', 'Fall protection planner', 'Construction Regulations, 2014', null, 'BOTH', 'T-HEIGHT'),
    ('APP-07', 'Scaffold supervisor', 'Construction Regulations, 2014', null, 'BOTH', 'T-SCAFFOLD'),
    ('APP-08', 'Scaffold inspector', 'Construction Regulations, 2014', null, 'BOTH', 'T-SCAFFOLD'),
    ('APP-09', 'Excavation supervisor', 'Construction Regulations, 2014', null, 'BOTH', 'T-EXCAVATION'),
    ('APP-10', 'Demolition supervisor', 'Construction Regulations, 2014', null, 'BOTH', 'T-DEMOLITION'),
    ('APP-11', 'Temporary works designer', 'Construction Regulations, 2014', null, 'BOTH', 'T-TEMPWORKS'),
    ('APP-12', 'Temporary works supervisor', 'Construction Regulations, 2014', null, 'BOTH', 'T-TEMPWORKS'),
    ('APP-13', 'Construction vehicle and mobile plant operator', 'Construction Regulations, 2014', null, 'BOTH', 'T-MOBILEPLANT'),
    ('APP-14', 'Construction vehicle and mobile plant supervisor', 'Construction Regulations, 2014', null, 'BOTH', 'T-MOBILEPLANT'),
    ('APP-15', 'Electrical installation supervisor', 'Electrical Machinery and Installation Regulations', null, 'BOTH', 'T-ELEC'),
    ('APP-16', 'Construction electrical appointee', 'Construction Regulations, 2014', null, 'BOTH', 'T-CONSTR and T-ELEC'),
    ('APP-17', 'Lifting machine and lifting tackle inspector', 'Driven Machinery Regulations', null, 'BOTH', 'T-LIFTING'),
    ('APP-18', 'Lifting machine operator', 'Driven Machinery Regulations', null, 'BOTH', 'T-LIFTING'),
    ('APP-19', 'General machinery supervisor', 'General Machinery Regulations, 1988', null, 'BOTH', 'T-MACHINERY'),
    ('APP-20', 'Pressure equipment supervisor', 'Pressure Equipment Regulations, 2009', null, 'BOTH', 'T-PRESSURE'),
    ('APP-21', 'Hazardous chemical agent controller', 'HCA Regulations, 2021', null, 'BOTH', 'T-HCA'),
    ('APP-22', 'Ladder inspector', 'General Safety Regulations, 1986', null, 'BOTH', 'T-LADDERS'),
    ('APP-23', 'Stacking and storage supervisor', 'General Safety Regulations, 1986', null, 'BOTH', 'T-STACKING'),
    ('APP-24', 'First aiders in the statutory ratio', 'General Safety Regulations, 1986', 'RULE-HSF-RATIO-FA', 'BOTH', null),
    ('APP-25', 'Fire equipment inspector', 'SANS 10400 T part', null, 'BOTH', null),
    ('APP-26', 'Fire team', 'Fire Brigade Services Act', null, 'BOTH', null),
    ('APP-27', 'Emergency coordinator', 'OHS Act', null, 'BOTH', null),
    ('APP-28', 'Evacuation wardens', 'OHS Act', null, 'BOTH', null),
    ('APP-29', 'Incident investigator', 'General Administrative Regulations, 2003', null, 'BOTH', null),
    ('APP-30', 'Confined space supervisor', 'General Safety Regulations, 1986', null, 'BOTH', 'T-CONFINED'),
    ('APP-31', 'Explosive powered tool operator', 'Explosive powered tools regulations', null, 'BOTH', 'T-EPT'),
    ('APP-32', 'Explosive powered tool issuer', 'Explosive powered tools regulations', null, 'BOTH', 'T-EPT'),
    ('APP-33', 'Hot work supervisor', 'General Safety Regulations, 1986', null, 'BOTH', 'T-HOTWORK'),
    ('APP-34', 'Asbestos work supervisor', 'Asbestos Abatement Regulations, 2020', null, 'BOTH', 'T-ASBESTOS'),
    ('APP-35', 'Lead work supervisor', 'Lead Regulations, 2001', null, 'BOTH', 'T-LEAD'),
    ('APP-36', 'Noise zone controller', 'Noise Exposure Regulations, 2024', null, 'BOTH', 'T-NOISE'),
    ('APP-37', 'Radiation protection officer', 'Hazardous Substances Act (radiation control)', null, 'BOTH', 'T-RADIATION'),
    ('APP-38', 'Food safety and hygiene supervisor', 'Food Premises Hygiene Regulations, R638 of 2018', null, 'BOTH', 'T-FOOD'),
    ('APP-39', 'Driver and professional driving permit holder', 'NRTA PrDP medical', null, 'BOTH', 'T-PRDP'),
    ('APP-40', 'Mine manager and MHSA statutory appointees', 'MHSA', null, 'MHSA', 'T-MINING')
       ) as v(code, name, short_name, ratio_rule, regime, trigger_code)
on conflict (code) do nothing;

-- 6. Elements: SPEC B6 universal (137), then B7 overlay additions (119) ------------------
insert into hsf_element (code, section_code, name, duty, evidence_type, responsible_appointment, responsible_role,
                         review_interval, retention_rule, regime, universal, trigger_code, mco_source, basis_state)
select v.code, v.section_code, v.name, v.duty, v.evidence_type, v.responsible_appointment, v.responsible_role,
       v.review_interval, v.retention_rule, v.regime, v.universal, v.trigger_code, v.mco_source, 'awaiting'
  from (values
    ('HSF-A-01', 'A', 'Company legal identity, registration, VAT and the physical address of every site', 'Company legal identity, registration, VAT and the physical address of every site', 'document', null, 'Chief executive', 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-A-02', 'A', 'Scope of the File: sites, activities, dates, contract or project reference', 'Scope of the File: sites, activities, dates, contract or project reference', 'document', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-A-03', 'A', 'COIDA letter of good standing, with expiry', 'COIDA letter of good standing, with expiry', 'certificate', null, 'Chief executive', 'on_expiry', 'INST', 'BOTH', true, null, null),
    ('HSF-A-04', 'A', 'Copy of the OHS Act and its regulations available at the workplace; MHSA equivalent for mines', 'Copy of the OHS Act and its regulations available at the workplace; MHSA equivalent for mines', 'document', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-A-05', 'A', 'Notification of construction work to the Department of Employment and Labour, with acknowledgement', 'Notification of construction work to the Department of Employment and Labour, with acknowledgement', 'document', null, 'Client or client''s agent', 'per_project', 'INST', 'BOTH', true, 'T-CONSTR-NOTIFY', null),
    ('HSF-A-06', 'A', 'Client health and safety specification', 'Client health and safety specification', 'document', null, 'Client or client''s agent', 'per_project', 'INST', 'BOTH', true, 'T-CONSTR', null),
    ('HSF-A-07', 'A', 'Contractor health and safety plan with the client''s written approval', 'Contractor health and safety plan with the client''s written approval', 'plan', 'APP-01', null, 'per_project', 'INST', 'BOTH', true, 'T-CONSTR', null),
    ('HSF-A-08', 'A', 'Section 37(2) agreement with every mandatary and every contractor', 'Section 37(2) agreement with every mandatary and every contractor', 'agreement', null, 'Chief executive', 'on_change', 'LIFE', 'BOTH', true, 'T-CONTRACTORS', null),
    ('HSF-A-09', 'A', 'Contractor register: each contractor, its File, letter of good standing and appointments', 'Contractor register: each contractor, its File, letter of good standing and appointments', 'register', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, 'T-CONTRACTORS', null),
    ('HSF-A-10', 'A', 'Legal register for the industry, drawn from the kernel and dated', 'Legal register for the industry, drawn from the kernel and dated', 'register', 'APP-00', null, 'monthly', 'LIFE', 'BOTH', true, null, null),
    ('HSF-A-11', 'A', 'Document control procedure and the File''s own revision history', 'Document control procedure and the File''s own revision history', 'document', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-B-01', 'B', 'Health and safety policy signed by the chief executive, dated, displayed, reviewed annually', 'Health and safety policy signed by the chief executive, dated, displayed, reviewed annually', 'document', null, 'Chief executive', 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-B-02', 'B', 'Chief executive responsibility acknowledged', 'Chief executive responsibility acknowledged', 'document', null, 'Chief executive', 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-B-03', 'B', 'Section 16(2) assignment in writing, accepted in writing, with its scope', 'Section 16(2) assignment in writing, accepted in writing, with its scope', 'appointment', null, 'Chief executive', 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-B-04', 'B', 'Health and safety representatives designated in writing after consultation, in the statutory ratio, with training evidence', 'Health and safety representatives designated in writing after consultation, in the statutory ratio, with training evidence', 'appointment', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, 'T-HSR', null),
    ('HSF-B-05', 'B', 'Health and safety committee: constitution, membership, minutes', 'Health and safety committee: constitution, membership, minutes', 'minutes', 'APP-00', null, 'monthly', 'LIFE', 'BOTH', true, 'T-COMMITTEE', null),
    ('HSF-B-06', 'B', 'Statutory appointments, one item per applicable appointment type (B6.3.1), each in writing, signed, accepted, with competence evidence', 'Statutory appointments, one item per applicable appointment type (B6.3.1), each in writing, signed, accepted, with competence evidence', 'appointment', null, 'Per appointment type', 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-B-07', 'B', 'Organogram of the health and safety structure with every appointee in post', 'Organogram of the health and safety structure with every appointee in post', 'document', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-B-08', 'B', 'Roles and responsibilities per appointment and per kernel job role', 'Roles and responsibilities per appointment and per kernel job role', 'document', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-C-01', 'C', 'Baseline hazard identification and risk assessment per site and activity, signed by the risk assessor, with review date', 'Baseline hazard identification and risk assessment per site and activity, signed by the risk assessor, with review date', 'report', 'APP-05', null, 'annual', 'INST', 'BOTH', true, null, null),
    ('HSF-C-02', 'C', 'Issue based risk assessments for every change, incident, new task or new substance', 'Issue based risk assessments for every change, incident, new task or new substance', 'report', 'APP-05', null, 'per_event', 'INST', 'BOTH', true, null, null),
    ('HSF-C-03', 'C', 'Continuous, task based and daily or shift pre task assessments', 'Continuous, task based and daily or shift pre task assessments', 'log', null, 'Supervisor', 'daily', null, 'BOTH', true, 'T-TASKRA', null),
    ('HSF-C-04', 'C', 'Hazard register mapped to the kernel hazard taxonomy per job role', 'Hazard register mapped to the kernel hazard taxonomy per job role', 'register', 'APP-05', null, 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-C-05', 'C', 'Hierarchy of control evidence: eliminated, substituted, engineered, administered, then protected', 'Hierarchy of control evidence: eliminated, substituted, engineered, administered, then protected', 'report', 'APP-05', null, 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-C-06', 'C', 'Safe work procedures and method statements for routine and high risk tasks', 'Safe work procedures and method statements for routine and high risk tasks', 'document', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-C-07', 'C', 'Fall protection plan', 'Fall protection plan', 'plan', 'APP-06', null, 'per_project', 'INST', 'BOTH', true, 'T-HEIGHT', null),
    ('HSF-C-08', 'C', 'Traffic management plan where vehicles and people share space', 'Traffic management plan where vehicles and people share space', 'plan', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, 'T-TRAFFIC', null),
    ('HSF-C-09', 'C', 'Lifting plans for lifting operations that require one', 'Lifting plans for lifting operations that require one', 'plan', 'APP-17', null, 'per_event', 'INST', 'BOTH', true, 'T-LIFTING', null),
    ('HSF-C-10', 'C', 'Excavation plan', 'Excavation plan', 'plan', 'APP-09', null, 'per_project', 'INST', 'BOTH', true, 'T-EXCAVATION', null),
    ('HSF-C-11', 'C', 'Demolition plan', 'Demolition plan', 'plan', 'APP-10', null, 'per_project', 'INST', 'BOTH', true, 'T-DEMOLITION', null),
    ('HSF-C-12', 'C', 'Confined space plan', 'Confined space plan', 'plan', 'APP-30', null, 'per_event', 'INST', 'BOTH', true, 'T-CONFINED', null),
    ('HSF-C-13', 'C', 'Hot work plan', 'Hot work plan', 'plan', 'APP-33', null, 'per_event', 'INST', 'BOTH', true, 'T-HOTWORK', null),
    ('HSF-C-14', 'C', 'Ergonomic risk assessment', 'Ergonomic risk assessment', 'report', 'APP-05', null, 'statutory', 'INST', 'BOTH', true, null, null),
    ('HSF-C-15', 'C', 'Noise zoning and noise risk assessment', 'Noise zoning and noise risk assessment', 'report', 'APP-36', null, 'statutory', 'INST', 'BOTH', true, 'T-NOISE', null),
    ('HSF-C-16', 'C', 'Hazardous chemical agent risk and exposure assessment', 'Hazardous chemical agent risk and exposure assessment', 'report', 'APP-21', null, 'statutory', 'INST', 'BOTH', true, 'T-HCA', null),
    ('HSF-C-17', 'C', 'Asbestos risk assessment, inventory and management plan', 'Asbestos risk assessment, inventory and management plan', 'report', 'APP-34', null, 'statutory', 'INST', 'BOTH', true, 'T-ASBESTOS', null),
    ('HSF-C-18', 'C', 'Lead risk assessment', 'Lead risk assessment', 'report', 'APP-35', null, 'statutory', 'INST', 'BOTH', true, 'T-LEAD', null),
    ('HSF-C-19', 'C', 'Hazardous biological agent risk assessment', 'Hazardous biological agent risk assessment', 'report', 'APP-05', null, 'statutory', 'INST', 'BOTH', true, 'T-HBA', null),
    ('HSF-C-20', 'C', 'Psychosocial and fatigue risk assessment', 'Psychosocial and fatigue risk assessment', 'report', 'APP-05', null, 'annual', null, 'BOTH', true, 'T-SHIFT or T-VIOLENCE', null),
    ('HSF-C-21', 'C', 'Major hazard installation risk assessment', 'Major hazard installation risk assessment', 'report', 'APP-00', null, 'statutory', 'INST', 'BOTH', true, 'T-MHI', null),
    ('HSF-C-22', 'C', 'Physical agents exposure risk assessment (heat, cold, illumination, indoor air, vibration, non ionising radiation)', 'Physical agents exposure risk assessment (heat, cold, illumination, indoor air, vibration, non ionising radiation)', 'report', 'APP-05', null, 'statutory', 'INST', 'BOTH', true, null, null),
    ('HSF-D-01', 'D', 'Training needs analysis per job role from the kernel''s statutory competency requirements', 'Training needs analysis per job role from the kernel''s statutory competency requirements', 'report', 'APP-00', null, 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-D-02', 'D', 'Training matrix: every person, every requirement, date, expiry, evidence (from MCO where Care Net delivered)', 'Training matrix: every person, every requirement, date, expiry, evidence (from MCO where Care Net delivered)', 'register', 'APP-00', null, 'monthly', 'LIFE', 'BOTH', true, null, null),
    ('HSF-D-03', 'D', 'Site, company and visitor induction records', 'Site, company and visitor induction records', 'training_record', 'APP-00', null, 'per_event', null, 'BOTH', true, null, null),
    ('HSF-D-04', 'D', 'Statutory and safety critical training records, one item per applicable course (B6.5.1)', 'Statutory and safety critical training records, one item per applicable course (B6.5.1)', 'training_record', 'APP-00', null, 'on_expiry', null, 'BOTH', true, null, 'mco_training'),
    ('HSF-D-05', 'D', 'Licences and permits held by persons, one item per applicable class (B6.5.2)', 'Licences and permits held by persons, one item per applicable class (B6.5.2)', 'licence', 'APP-00', null, 'on_expiry', null, 'BOTH', true, null, null),
    ('HSF-D-06', 'D', 'Toolbox talk register and attendance', 'Toolbox talk register and attendance', 'register', null, 'Supervisor', 'per_event', null, 'BOTH', true, null, null),
    ('HSF-D-07', 'D', 'Competency assessment records where a role requires assessment rather than attendance', 'Competency assessment records where a role requires assessment rather than attendance', 'training_record', 'APP-00', null, 'on_expiry', null, 'BOTH', true, null, null),
    ('HSF-E-01', 'E', 'The released Medical Surveillance Plan from MSP FORGE', 'The released Medical Surveillance Plan from MSP FORGE', 'document', null, 'OMP', 'annual', 'MED40', 'BOTH', true, null, null),
    ('HSF-E-02', 'E', 'Certificates of fitness per employee per protocol: baseline, periodic, exit (MCO)', 'Certificates of fitness per employee per protocol: baseline, periodic, exit (MCO)', 'medical_certificate', null, 'OMP', 'on_expiry', 'MED40', 'BOTH', true, null, 'mco_medical'),
    ('HSF-E-03', 'E', 'Construction Regulations medical certificates of fitness (MCO)', 'Construction Regulations medical certificates of fitness (MCO)', 'medical_certificate', 'APP-01', null, 'on_expiry', 'MED40', 'BOTH', true, 'T-CONSTR', 'mco_medical'),
    ('HSF-E-04', 'E', 'Professional driving permit medicals (MCO)', 'Professional driving permit medicals (MCO)', 'medical_certificate', null, 'OMP', 'on_expiry', 'MED40', 'BOTH', true, 'T-PRDP', 'mco_medical'),
    ('HSF-E-05', 'E', 'Mine certificate of fitness per the mandatory Code of Practice (MCO)', 'Mine certificate of fitness per the mandatory Code of Practice (MCO)', 'medical_certificate', null, 'OMP', 'on_expiry', 'MED40', 'BOTH', true, 'T-MINING', 'mco_medical'),
    ('HSF-E-06', 'E', 'Statutory examinations required by specific regulations, one item per applicable class: lead, asbestos, hazardous chemical agents, hazardous biological agents, noise, radiation, heights, confined space, night work, food handling (MCO)', 'Statutory examinations required by specific regulations, one item per applicable class: lead, asbestos, hazardous chemical agents, hazardous biological agents, noise, radiation, heights, confined space, night work, food handling (MCO)', 'medical_certificate', null, 'OMP', 'statutory', 'MED40', 'BOTH', true, null, 'mco_medical'),
    ('HSF-E-07', 'E', 'Fitness restrictions reflected in job placement, without clinical detail beyond what the employer may hold', 'Fitness restrictions reflected in job placement, without clinical detail beyond what the employer may hold', 'register', null, 'OMP', 'per_event', 'MED40', 'BOTH', true, null, null),
    ('HSF-E-08', 'E', 'Occupational disease reporting and referral records', 'Occupational disease reporting and referral records', 'report', null, 'OMP', 'per_event', 'MED40', 'BOTH', true, null, null),
    ('HSF-E-09', 'E', 'First aid: box contents and inspection, first aider list, treatment register', 'First aid: box contents and inspection, first aider list, treatment register', 'register', 'APP-24', null, 'monthly', null, 'BOTH', true, null, null),
    ('HSF-E-10', 'E', 'Confidentiality and POPIA handling of every medical record: what the employer holds, what Care Net holds, and the lawful basis for each', 'Confidentiality and POPIA handling of every medical record: what the employer holds, what Care Net holds, and the lawful basis for each', 'document', null, 'OMP', 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-F-01', 'F', 'Scaffold register and inspection records', 'Scaffold register and inspection records', 'register', 'APP-08', null, 'statutory', 'INST', 'BOTH', true, 'T-SCAFFOLD', null),
    ('HSF-F-02', 'F', 'Ladder register and inspections', 'Ladder register and inspections', 'register', 'APP-22', null, 'statutory', null, 'BOTH', true, 'T-LADDERS', null),
    ('HSF-F-03', 'F', 'Lifting machines and lifting tackle register with load tests and inspections', 'Lifting machines and lifting tackle register with load tests and inspections', 'register', 'APP-17', null, 'statutory', 'INST', 'BOTH', true, 'T-LIFTING', null),
    ('HSF-F-04', 'F', 'Portable electrical tools and equipment register with inspections', 'Portable electrical tools and equipment register with inspections', 'register', 'APP-15', null, 'statutory', null, 'BOTH', true, null, null),
    ('HSF-F-05', 'F', 'Electrical installation certificate of compliance and installation inspection register', 'Electrical installation certificate of compliance and installation inspection register', 'certificate', 'APP-15', null, 'statutory', 'INST', 'BOTH', true, null, null),
    ('HSF-F-06', 'F', 'Fire equipment register with service dates', 'Fire equipment register with service dates', 'register', 'APP-25', null, 'statutory', null, 'BOTH', true, null, null),
    ('HSF-F-07', 'F', 'Emergency lighting and signage inspections', 'Emergency lighting and signage inspections', 'register', 'APP-25', null, 'statutory', null, 'BOTH', true, null, null),
    ('HSF-F-08', 'F', 'Pressure equipment register with inspections and certificates', 'Pressure equipment register with inspections and certificates', 'register', 'APP-20', null, 'statutory', 'INST', 'BOTH', true, 'T-PRESSURE', null),
    ('HSF-F-09', 'F', 'Vehicle and mobile plant register with daily checks and maintenance', 'Vehicle and mobile plant register with daily checks and maintenance', 'register', 'APP-14', null, 'daily', null, 'BOTH', true, 'T-MOBILEPLANT', null),
    ('HSF-F-10', 'F', 'Excavation inspection register', 'Excavation inspection register', 'register', 'APP-09', null, 'daily', 'INST', 'BOTH', true, 'T-EXCAVATION', null),
    ('HSF-F-11', 'F', 'Personal protective equipment issue register and inspection', 'Personal protective equipment issue register and inspection', 'register', 'APP-00', null, 'on_change', null, 'BOTH', true, null, null),
    ('HSF-F-12', 'F', 'Hazardous chemical agent register with safety data sheets, quantities and storage', 'Hazardous chemical agent register with safety data sheets, quantities and storage', 'register', 'APP-21', null, 'on_change', 'INST', 'BOTH', true, 'T-HCA', null),
    ('HSF-F-13', 'F', 'Asbestos inventory and register', 'Asbestos inventory and register', 'register', 'APP-34', null, 'statutory', 'INST', 'BOTH', true, 'T-ASBESTOS', null),
    ('HSF-F-14', 'F', 'Machine guarding inspection register', 'Machine guarding inspection register', 'register', 'APP-19', null, 'statutory', null, 'BOTH', true, 'T-MACHINERY', null),
    ('HSF-F-15', 'F', 'Housekeeping and walkabout inspection records', 'Housekeeping and walkabout inspection records', 'log', null, 'Supervisor', 'monthly', null, 'BOTH', true, null, null),
    ('HSF-F-16', 'F', 'Stacking and storage inspections', 'Stacking and storage inspections', 'log', 'APP-23', null, 'monthly', null, 'BOTH', true, 'T-STACKING', null),
    ('HSF-F-17', 'F', 'Fall arrest equipment register and inspections', 'Fall arrest equipment register and inspections', 'register', 'APP-06', null, 'before_use', null, 'BOTH', true, 'T-HEIGHT', null),
    ('HSF-F-18', 'F', 'Confined space register', 'Confined space register', 'register', 'APP-30', null, 'on_change', null, 'BOTH', true, 'T-CONFINED', null),
    ('HSF-F-19', 'F', 'Explosive powered tool register', 'Explosive powered tool register', 'register', 'APP-32', null, 'per_event', null, 'BOTH', true, 'T-EPT', null),
    ('HSF-F-20', 'F', 'Welfare facilities inspection', 'Welfare facilities inspection', 'log', 'APP-00', null, 'monthly', null, 'BOTH', true, null, null),
    ('HSF-F-21', 'F', 'Lighting, ventilation and thermal environment measurements', 'Lighting, ventilation and thermal environment measurements', 'report', 'APP-05', null, 'statutory', 'INST', 'BOTH', true, null, null),
    ('HSF-F-22', 'F', 'Waste register', 'Waste register', 'register', 'APP-00', null, 'monthly', 'INST', 'BOTH', true, 'T-WASTE', null),
    ('HSF-G-01', 'G', 'Permit to work system and permit register', 'Permit to work system and permit register', 'register', 'APP-00', null, 'on_change', null, 'BOTH', true, 'T-PTW', null),
    ('HSF-G-02', 'G', 'Hot work permits', 'Hot work permits', 'permit', 'APP-33', null, 'per_event', null, 'BOTH', true, 'T-HOTWORK', null),
    ('HSF-G-03', 'G', 'Confined space entry permits', 'Confined space entry permits', 'permit', 'APP-30', null, 'per_event', null, 'BOTH', true, 'T-CONFINED', null),
    ('HSF-G-04', 'G', 'Excavation permits and service clearances', 'Excavation permits and service clearances', 'permit', 'APP-09', null, 'per_event', null, 'BOTH', true, 'T-EXCAVATION', null),
    ('HSF-G-05', 'G', 'Working at height permits', 'Working at height permits', 'permit', 'APP-06', null, 'per_event', null, 'BOTH', true, 'T-HEIGHT', null),
    ('HSF-G-06', 'G', 'Electrical isolation, lockout and tagout records', 'Electrical isolation, lockout and tagout records', 'log', 'APP-15', null, 'per_event', null, 'BOTH', true, 'T-ELEC', null),
    ('HSF-G-07', 'G', 'Lifting operation permits', 'Lifting operation permits', 'permit', 'APP-17', null, 'per_event', null, 'BOTH', true, 'T-LIFTING', null),
    ('HSF-G-08', 'G', 'Demolition permits', 'Demolition permits', 'permit', 'APP-10', null, 'per_event', null, 'BOTH', true, 'T-DEMOLITION', null),
    ('HSF-G-09', 'G', 'Road closure and traffic accommodation approvals', 'Road closure and traffic accommodation approvals', 'permit', 'APP-00', null, 'per_event', null, 'BOTH', true, 'T-ROADWORKS', null),
    ('HSF-G-10', 'G', 'Radiation work authorisations', 'Radiation work authorisations', 'licence', 'APP-37', null, 'on_expiry', 'INST', 'BOTH', true, 'T-RADIATION', null),
    ('HSF-H-01', 'H', 'Emergency plan per site: roles, assembly points, contacts, routes', 'Emergency plan per site: roles, assembly points, contacts, routes', 'plan', 'APP-27', null, 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-H-02', 'H', 'Emergency drills: schedule, records, findings, corrective actions', 'Emergency drills: schedule, records, findings, corrective actions', 'report', 'APP-27', null, 'statutory', null, 'BOTH', true, null, null),
    ('HSF-H-03', 'H', 'Fire risk assessment and fire plan', 'Fire risk assessment and fire plan', 'plan', 'APP-25', null, 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-H-04', 'H', 'Medical emergency arrangements and nearest facilities', 'Medical emergency arrangements and nearest facilities', 'document', 'APP-24', null, 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-H-05', 'H', 'Spill response', 'Spill response', 'plan', 'APP-21', null, 'annual', 'LIFE', 'BOTH', true, 'T-HCA', null),
    ('HSF-H-06', 'H', 'MHI emergency plan and public information duty', 'MHI emergency plan and public information duty', 'plan', 'APP-00', null, 'statutory', 'INST', 'BOTH', true, 'T-MHI', null),
    ('HSF-H-07', 'H', 'Security emergency procedures', 'Security emergency procedures', 'document', 'APP-27', null, 'annual', 'LIFE', 'BOTH', true, 'T-SECURITY', null),
    ('HSF-H-08', 'H', 'Disaster management interface for emergency planning', 'Disaster management interface for emergency planning', 'document', 'APP-27', null, 'annual', 'LIFE', 'BOTH', true, 'T-MHI', null),
    ('HSF-I-01', 'I', 'Incident and near miss reporting procedure', 'Incident and near miss reporting procedure', 'document', 'APP-00', null, 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-I-02', 'I', 'Incident register', 'Incident register', 'register', 'APP-29', null, 'per_event', 'INST', 'BOTH', true, null, null),
    ('HSF-I-03', 'I', 'Incident reporting to the inspector and incident recording', 'Incident reporting to the inspector and incident recording', 'report', 'APP-00', null, 'per_event', 'INST', 'BOTH', true, null, null),
    ('HSF-I-04', 'I', 'Investigation reports with root cause and corrective action', 'Investigation reports with root cause and corrective action', 'report', 'APP-29', null, 'per_event', 'INST', 'BOTH', true, null, null),
    ('HSF-I-05', 'I', 'COIDA claim records and employer''s reports of accidents and diseases', 'COIDA claim records and employer''s reports of accidents and diseases', 'report', 'APP-00', null, 'per_event', 'INST', 'BOTH', true, null, null),
    ('HSF-I-06', 'I', 'Occupational disease notifications', 'Occupational disease notifications', 'report', null, 'OMP', 'per_event', 'MED40', 'BOTH', true, null, null),
    ('HSF-I-07', 'I', 'Corrective and preventive action register with closure evidence', 'Corrective and preventive action register with closure evidence', 'register', 'APP-00', null, 'monthly', null, 'BOTH', true, null, null),
    ('HSF-J-01', 'J', 'Occupational hygiene survey programme', 'Occupational hygiene survey programme', 'plan', 'APP-05', null, 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-J-02', 'J', 'Noise survey by an approved inspection authority and the noise zone map', 'Noise survey by an approved inspection authority and the noise zone map', 'report', 'APP-36', null, 'statutory', 'INST', 'BOTH', true, 'T-NOISE', null),
    ('HSF-J-03', 'J', 'Hazardous chemical agent exposure monitoring by an approved inspection authority', 'Hazardous chemical agent exposure monitoring by an approved inspection authority', 'report', 'APP-21', null, 'statutory', 'INST', 'BOTH', true, 'T-HCA', null),
    ('HSF-J-04', 'J', 'Illumination survey', 'Illumination survey', 'report', 'APP-05', null, 'statutory', 'INST', 'BOTH', true, null, null),
    ('HSF-J-05', 'J', 'Ventilation and thermal survey', 'Ventilation and thermal survey', 'report', 'APP-05', null, 'statutory', 'INST', 'BOTH', true, 'T-THERMAL', null),
    ('HSF-J-06', 'J', 'Asbestos air monitoring', 'Asbestos air monitoring', 'report', 'APP-34', null, 'statutory', 'INST', 'BOTH', true, 'T-ASBESTOS', null),
    ('HSF-J-07', 'J', 'Lead air monitoring', 'Lead air monitoring', 'report', 'APP-35', null, 'statutory', 'INST', 'BOTH', true, 'T-LEAD', null),
    ('HSF-J-08', 'J', 'Biological monitoring results as they bear on controls, held under medical confidentiality (aggregate only in the File)', 'Biological monitoring results as they bear on controls, held under medical confidentiality (aggregate only in the File)', 'report', null, 'OMP', 'statutory', 'MED40', 'BOTH', true, 'T-HCA or T-LEAD', null),
    ('HSF-K-01', 'K', 'Contractor selection criteria and evaluation', 'Contractor selection criteria and evaluation', 'document', 'APP-00', null, 'per_project', 'LIFE', 'BOTH', true, 'T-CONTRACTORS', null),
    ('HSF-K-02', 'K', 'Section 37(2) agreements and contractor Files (cross reference HSF-A-08)', 'Section 37(2) agreements and contractor Files (cross reference HSF-A-08)', 'agreement', 'APP-00', null, 'on_change', 'LIFE', 'BOTH', true, 'T-CONTRACTORS', null),
    ('HSF-K-03', 'K', 'Contractor inductions, permits and daily coordination records', 'Contractor inductions, permits and daily coordination records', 'log', 'APP-00', null, 'daily', null, 'BOTH', true, 'T-CONTRACTORS', null),
    ('HSF-K-04', 'K', 'Visitor control and induction', 'Visitor control and induction', 'log', 'APP-00', null, 'per_event', null, 'BOTH', true, null, null),
    ('HSF-K-05', 'K', 'Public protection: hoarding, signage, public liability evidence', 'Public protection: hoarding, signage, public liability evidence', 'document', 'APP-00', null, 'per_project', null, 'BOTH', true, 'T-PUBLIC', null),
    ('HSF-L-01', 'L', 'Committee minutes and action tracking (cross reference HSF-B-05)', 'Committee minutes and action tracking (cross reference HSF-B-05)', 'minutes', 'APP-00', null, 'monthly', 'LIFE', 'BOTH', true, 'T-COMMITTEE', null),
    ('HSF-L-02', 'L', 'Representative inspection reports and recommendations', 'Representative inspection reports and recommendations', 'report', 'APP-00', null, 'monthly', null, 'BOTH', true, 'T-HSR', null),
    ('HSF-L-03', 'L', 'Toolbox talks (cross reference HSF-D-06)', 'Toolbox talks (cross reference HSF-D-06)', 'register', null, 'Supervisor', 'per_event', null, 'BOTH', true, null, null),
    ('HSF-L-04', 'L', 'Notices displayed: Act and regulations, appointments, emergency numbers, policy', 'Notices displayed: Act and regulations, appointments, emergency numbers, policy', 'log', 'APP-00', null, 'annual', null, 'BOTH', true, null, null),
    ('HSF-L-05', 'L', 'Change notification records to Care Net for medical surveillance and to the client for construction work', 'Change notification records to Care Net for medical surveillance and to the client for construction work', 'log', 'APP-00', null, 'per_event', 'LIFE', 'BOTH', true, null, null),
    ('HSF-M-01', 'M', 'Facilities Regulations compliance: sanitation, drinking water, change rooms, eating places, in the statutory ratios', 'Facilities Regulations compliance: sanitation, drinking water, change rooms, eating places, in the statutory ratios', 'report', 'APP-00', null, 'annual', null, 'BOTH', true, null, null),
    ('HSF-M-02', 'M', 'Physical environment compliance: lighting, ventilation, thermal, housekeeping', 'Physical environment compliance: lighting, ventilation, thermal, housekeeping', 'report', 'APP-00', null, 'annual', 'INST', 'BOTH', true, null, null),
    ('HSF-M-03', 'M', 'Environmental management where NEM Waste Act or other environmental law applies', 'Environmental management where NEM Waste Act or other environmental law applies', 'document', 'APP-00', null, 'annual', 'INST', 'BOTH', true, 'T-WASTE or T-ENVIRO', null),
    ('HSF-M-04', 'M', 'Waste manifests and licensed disposal evidence', 'Waste manifests and licensed disposal evidence', 'register', 'APP-00', null, 'per_event', 'INST', 'BOTH', true, 'T-WASTE', null),
    ('HSF-M-05', 'M', 'Workplace smoking controls', 'Workplace smoking controls', 'document', 'APP-00', null, 'annual', null, 'BOTH', true, null, null),
    ('HSF-N-01', 'N', 'Internal audit schedule and reports', 'Internal audit schedule and reports', 'report', 'APP-00', null, 'statutory', null, 'BOTH', true, null, null),
    ('HSF-N-02', 'N', 'External audit reports (client, principal contractor, certification body, inspector)', 'External audit reports (client, principal contractor, certification body, inspector)', 'report', 'APP-00', null, 'per_event', null, 'BOTH', true, null, null),
    ('HSF-N-03', 'N', 'Management review records', 'Management review records', 'minutes', null, 'Chief executive', 'annual', null, 'BOTH', true, null, null),
    ('HSF-N-04', 'N', 'Objectives and targets with measurement', 'Objectives and targets with measurement', 'report', null, 'Chief executive', 'annual', null, 'BOTH', true, null, null),
    ('HSF-N-05', 'N', 'Non conformance and corrective action log with closure evidence', 'Non conformance and corrective action log with closure evidence', 'register', 'APP-00', null, 'monthly', null, 'BOTH', true, null, null),
    ('HSF-N-06', 'N', 'Kernel legislation release notes applied to this File, with date and change', 'Kernel legislation release notes applied to this File, with date and change', 'log', null, 'Engine', 'per_event', 'LIFE', 'BOTH', true, null, null),
    ('HSF-O-01', 'O', 'Retention schedule per record type, from the instrument that sets it, including the 40 year retention for medical surveillance records of hazardous exposure', 'Retention schedule per record type, from the instrument that sets it, including the 40 year retention for medical surveillance records of hazardous exposure', 'document', 'APP-00', null, 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-O-02', 'O', 'Storage location and access control per record type', 'Storage location and access control per record type', 'document', 'APP-00', null, 'annual', 'LIFE', 'BOTH', true, null, null),
    ('HSF-O-03', 'O', 'POPIA operator agreement between the client and Care Net for the records Care Net holds', 'POPIA operator agreement between the client and Care Net for the records Care Net holds', 'agreement', null, 'Chief executive', 'on_change', 'LIFE', 'BOTH', true, null, null),
    ('HSF-OV-AGRI-01', 'C', 'Pesticide and organophosphate handling procedure and register', 'Pesticide and organophosphate handling procedure and register', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-AGRI-02', 'E', 'Cholinesterase surveillance', 'Cholinesterase surveillance', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, 'mco_medical'),
    ('HSF-OV-AGRI-03', 'C', 'Tractor and implement guarding inspections', 'Tractor and implement guarding inspections', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-AGRI-04', 'D', 'Chainsaw and forestry harvesting competencies', 'Chainsaw and forestry harvesting competencies', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-AGRI-05', 'C', 'Zoonosis controls', 'Zoonosis controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-AGRI-06', 'C', 'Child labour prohibition on hazardous work', 'Child labour prohibition on hazardous work', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-AGRI-07', 'C', 'Seasonal worker induction', 'Seasonal worker induction', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-AGRI-08', 'C', 'Heat exposure controls', 'Heat exposure controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-AGRI-09', 'C', 'Remote site emergency response', 'Remote site emergency response', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CLEAN-01', 'C', 'Safety data sheets held at every client site', 'Safety data sheets held at every client site', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CLEAN-02', 'C', 'Facade and high level cleaning method statements', 'Facade and high level cleaning method statements', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CLEAN-03', 'C', 'Tank and duct confined space entry', 'Tank and duct confined space entry', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CLEAN-04', 'C', 'Biological agent exposure in healthcare and sanitation cleaning', 'Biological agent exposure in healthcare and sanitation cleaning', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CLEAN-05', 'C', 'Lone worker and night work controls', 'Lone worker and night work controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CLEAN-06', 'C', 'Multi site client induction records', 'Multi site client induction records', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CONSTR-01', 'C', 'Construction work permit where the thresholds require it', 'Construction work permit where the thresholds require it', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CONSTR-02', 'C', 'Designer duties record', 'Designer duties record', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CONSTR-03', 'C', 'Structures inspections', 'Structures inspections', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CONSTR-04', 'C', 'Suspended platforms register and inspections', 'Suspended platforms register and inspections', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CONSTR-05', 'C', 'Use and temporary storage of flammables', 'Use and temporary storage of flammables', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CONSTR-06', 'C', 'Water environments controls', 'Water environments controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CONSTR-07', 'C', 'Fire precautions on construction sites', 'Fire precautions on construction sites', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CONSTR-08', 'C', 'Health and safety file handover to the client on completion', 'Health and safety file handover to the client on completion', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-CONSTR-09', 'E', 'Medical certificate of fitness for every person on site', 'Medical certificate of fitness for every person on site', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, 'mco_medical'),
    ('HSF-OV-EDU-01', 'C', 'Laboratory and workshop chemical controls', 'Laboratory and workshop chemical controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-EDU-02', 'C', 'Playground and sports equipment inspections', 'Playground and sports equipment inspections', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-EDU-03', 'C', 'Learner transport and professional driving permits', 'Learner transport and professional driving permits', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-EDU-04', 'C', 'Immunisation and biological agent controls in early childhood settings', 'Immunisation and biological agent controls in early childhood settings', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-EDU-05', 'C', 'Emergency plan accounting for learners', 'Emergency plan accounting for learners', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-EDU-06', 'C', 'Child protection interface, referenced only, never adjudicated', 'Child protection interface, referenced only, never adjudicated', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-GOV-01', 'C', 'Water and wastewater confined space controls', 'Water and wastewater confined space controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-GOV-02', 'E', 'Emergency and traffic services fitness', 'Emergency and traffic services fitness', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, 'mco_medical'),
    ('HSF-OV-GOV-03', 'C', 'Fleet management register', 'Fleet management register', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-GOV-04', 'C', 'Public facility fire and evacuation', 'Public facility fire and evacuation', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-GOV-05', 'C', 'Multi department appointment structure under one accounting officer', 'Multi department appointment structure under one accounting officer', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-GOV-06', 'C', 'Contractor procurement under section 37(2)', 'Contractor procurement under section 37(2)', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HEALTH-01', 'E', 'Immunisation and post exposure protocols', 'Immunisation and post exposure protocols', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, 'mco_medical'),
    ('HSF-OV-HEALTH-02', 'C', 'Sharps and healthcare risk waste', 'Sharps and healthcare risk waste', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HEALTH-03', 'C', 'Radiation protection officer, dose records', 'Radiation protection officer, dose records', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HEALTH-04', 'C', 'Cytotoxic and anaesthetic gas controls', 'Cytotoxic and anaesthetic gas controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HEALTH-05', 'C', 'Patient handling ergonomics', 'Patient handling ergonomics', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HEALTH-06', 'C', 'Violence and psychosocial controls', 'Violence and psychosocial controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HEALTH-07', 'C', 'Laboratory biosafety level controls', 'Laboratory biosafety level controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HEALTH-08', 'C', 'Clinical workplace professional registration interface, reference only', 'Clinical workplace professional registration interface, reference only', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HOSP-01', 'C', 'Food Premises Hygiene Regulations compliance in full', 'Food Premises Hygiene Regulations compliance in full', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HOSP-02', 'E', 'Food handler fitness', 'Food handler fitness', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, 'mco_medical'),
    ('HSF-OV-HOSP-03', 'C', 'Kitchen fire and gas installation certificates', 'Kitchen fire and gas installation certificates', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HOSP-04', 'C', 'Slips and burns controls', 'Slips and burns controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HOSP-05', 'C', 'Pool and lifeguard requirements where applicable', 'Pool and lifeguard requirements where applicable', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-HOSP-06', 'C', 'Housekeeping chemical handling', 'Housekeeping chemical handling', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-MANU-01', 'C', 'Guarding in full per machine class', 'Guarding in full per machine class', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-MANU-02', 'C', 'Process specific chemical controls: solvents, welding fume, isocyanates', 'Process specific chemical controls: solvents, welding fume, isocyanates', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-MANU-03', 'C', 'Ergonomics on production lines', 'Ergonomics on production lines', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-MANU-04', 'C', 'Confined space in vessels', 'Confined space in vessels', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-MANU-05', 'D', 'Forklift competencies', 'Forklift competencies', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-MANU-06', 'C', 'Dangerous goods storage and transport', 'Dangerous goods storage and transport', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-MINING-01', 'C', 'Employer duties under the MHSA', 'Employer duties under the MHSA', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-02', 'C', 'Mandatory Codes of Practice per DMRE guideline: fitness to perform work', 'Mandatory Codes of Practice per DMRE guideline: fitness to perform work', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-03', 'C', 'Mandatory Code of Practice: noise', 'Mandatory Code of Practice: noise', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-04', 'C', 'Mandatory Code of Practice: airborne pollutants', 'Mandatory Code of Practice: airborne pollutants', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-05', 'C', 'Mandatory Code of Practice: thermal stress', 'Mandatory Code of Practice: thermal stress', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-06', 'C', 'Mandatory Code of Practice: fatigue', 'Mandatory Code of Practice: fatigue', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-07', 'C', 'Mandatory Code of Practice: trackless mobile machinery', 'Mandatory Code of Practice: trackless mobile machinery', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-08', 'C', 'Mandatory Code of Practice: fall of ground', 'Mandatory Code of Practice: fall of ground', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-09', 'C', 'Mandatory Code of Practice: emergency preparedness', 'Mandatory Code of Practice: emergency preparedness', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-10', 'E', 'Certificate of fitness system', 'Certificate of fitness system', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, 'mco_medical'),
    ('HSF-OV-MINING-11', 'C', 'ODMWA benefit examinations', 'ODMWA benefit examinations', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-12', 'C', 'Mine health and safety representatives and committees', 'Mine health and safety representatives and committees', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-13', 'C', 'Explosives controls', 'Explosives controls', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-14', 'C', 'Winding and lifting plant', 'Winding and lifting plant', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-15', 'C', 'Ventilation and rescue', 'Ventilation and rescue', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-MINING-16', 'C', 'Mine Health and Safety Inspectorate reporting', 'Mine Health and Safety Inspectorate reporting', 'document', 'APP-00', null, 'annual', 'INST', 'MHSA', false, null, null),
    ('HSF-OV-OFFICE-01', 'C', 'Display screen work ergonomics', 'Display screen work ergonomics', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-OFFICE-02', 'C', 'Contact centre night work and acoustic exposure', 'Contact centre night work and acoustic exposure', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-OFFICE-03', 'C', 'Lone working and travel', 'Lone working and travel', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-OFFICE-04', 'C', 'Psychosocial hazards', 'Psychosocial hazards', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-PETRO-01', 'C', 'MHI Regulations in full where thresholds are met', 'MHI Regulations in full where thresholds are met', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-PETRO-02', 'C', 'Electrical zoning and intrinsically safe equipment', 'Electrical zoning and intrinsically safe equipment', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-PETRO-03', 'C', 'Dangerous goods transport', 'Dangerous goods transport', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-PETRO-04', 'C', 'Forecourt and tank farm emergency plans', 'Forecourt and tank farm emergency plans', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-PETRO-05', 'C', 'Static and grounding controls', 'Static and grounding controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-PETRO-06', 'C', 'Environmental spill controls', 'Environmental spill controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-RETAIL-01', 'C', 'Racking inspections', 'Racking inspections', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-RETAIL-02', 'C', 'Loading dock traffic management', 'Loading dock traffic management', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-RETAIL-03', 'C', 'Cold room and heat exposure', 'Cold room and heat exposure', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-RETAIL-04', 'C', 'Security and robbery exposure controls', 'Security and robbery exposure controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-RETAIL-05', 'C', 'Fire and evacuation for public spaces', 'Fire and evacuation for public spaces', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-SEC-01', 'D', 'PSIRA registration and grades', 'PSIRA registration and grades', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-SEC-02', 'D', 'Firearm competency and Firearms Control Act compliance', 'Firearm competency and Firearms Control Act compliance', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-SEC-03', 'C', 'Cash in transit vehicle and route controls', 'Cash in transit vehicle and route controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-SEC-04', 'C', 'Post incident support', 'Post incident support', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-SEC-05', 'C', 'Canine unit controls', 'Canine unit controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-SEC-06', 'C', 'Control room ergonomics', 'Control room ergonomics', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-SEC-07', 'C', 'Lone posting emergency procedures', 'Lone posting emergency procedures', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TEL-01', 'C', 'Tower rescue plans', 'Tower rescue plans', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TEL-02', 'C', 'Radio frequency exposure controls', 'Radio frequency exposure controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TEL-03', 'C', 'Manhole and data centre plant confined space', 'Manhole and data centre plant confined space', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TEL-04', 'C', 'Remote site emergency response', 'Remote site emergency response', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TRANS-01', 'C', 'Fleet compliance under the National Road Traffic Act in full, operator cards and roadworthiness', 'Fleet compliance under the National Road Traffic Act in full, operator cards and roadworthiness', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TRANS-02', 'C', 'Dangerous goods where carried', 'Dangerous goods where carried', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TRANS-03', 'C', 'Driver fatigue management', 'Driver fatigue management', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TRANS-04', 'E', 'Rail safety critical fitness', 'Rail safety critical fitness', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, 'mco_medical'),
    ('HSF-OV-TRANS-05', 'C', 'Port work regime', 'Port work regime', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TRANS-06', 'C', 'Aviation ground handling regime', 'Aviation ground handling regime', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-TRANS-07', 'C', 'Loading and securing of loads', 'Loading and securing of loads', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-UTIL-01', 'C', 'Electrical Machinery and Installation Regulations in full for generation and distribution', 'Electrical Machinery and Installation Regulations in full for generation and distribution', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-UTIL-02', 'C', 'Switching and isolation procedures', 'Switching and isolation procedures', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-UTIL-03', 'C', 'Chlorine and chemical dosing controls', 'Chlorine and chemical dosing controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-UTIL-04', 'C', 'Arc flash controls', 'Arc flash controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-UTIL-05', 'C', 'Public safety near assets', 'Public safety near assets', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-UTIL-06', 'C', 'Environmental authorisations', 'Environmental authorisations', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-WASTE-01', 'D', 'NEM Waste Act licences and manifests', 'NEM Waste Act licences and manifests', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-WASTE-02', 'C', 'Hazardous and healthcare risk waste handling', 'Hazardous and healthcare risk waste handling', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-WASTE-03', 'E', 'Immunisation for biological agent exposure', 'Immunisation for biological agent exposure', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, 'mco_medical'),
    ('HSF-OV-WASTE-04', 'C', 'Landfill gas and confined space', 'Landfill gas and confined space', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-WASTE-05', 'C', 'Reversing vehicle traffic management', 'Reversing vehicle traffic management', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-WASTE-06', 'C', 'Needle stick and sharps controls', 'Needle stick and sharps controls', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-WASTE-07', 'C', 'Dust and silica at transfer stations', 'Dust and silica at transfer stations', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null),
    ('HSF-OV-WASTE-08', 'C', 'Environmental monitoring', 'Environmental monitoring', 'document', 'APP-00', null, 'annual', 'INST', 'OHSA', false, null, null)
       ) as v(code, section_code, name, duty, evidence_type, responsible_appointment, responsible_role,
              review_interval, retention_rule, regime, universal, trigger_code, mco_source)
on conflict (code) do nothing;

-- 7. Element classes: courses (B6.5.1), licence classes (B6.5.2), examination classes (HSF-E-06)
insert into hsf_element_class (code, element_code, kind, ordinal, name, trigger_code, instrument_id, provision, mco_source)
select v.code, v.element_code, v.kind, v.ordinal, v.name, v.trigger_code,
       case when v.short_name is null then null else (select li.id from msp_legal_instrument li where li.short_name = v.short_name order by case li.status when 'verified' then 0 when 'pending' then 1 when 'superseded' then 2 else 3 end, li.verified_on desc nulls last, li.id limit 1) end,
       'awaiting verification', v.mco_source
  from (values
    ('D04-01', 'HSF-D-04', 'course', 1, 'Health and safety representative', null, null, 'mco_training'),
    ('D04-02', 'HSF-D-04', 'course', 2, 'First aid', null, null, 'mco_training'),
    ('D04-03', 'HSF-D-04', 'course', 3, 'Fire fighting', null, null, 'mco_training'),
    ('D04-04', 'HSF-D-04', 'course', 4, 'Working at height and fall arrest', 'T-HEIGHT', null, 'mco_training'),
    ('D04-05', 'HSF-D-04', 'course', 5, 'Scaffold erection and inspection', 'T-SCAFFOLD', null, 'mco_training'),
    ('D04-06', 'HSF-D-04', 'course', 6, 'Confined space entry', 'T-CONFINED', null, 'mco_training'),
    ('D04-07', 'HSF-D-04', 'course', 7, 'Lifting machine and lifting tackle operation', 'T-LIFTING', null, 'mco_training'),
    ('D04-08', 'HSF-D-04', 'course', 8, 'Forklift and mobile plant', 'T-MOBILEPLANT', null, 'mco_training'),
    ('D04-09', 'HSF-D-04', 'course', 9, 'Hazard identification and risk assessment', null, null, 'mco_training'),
    ('D04-10', 'HSF-D-04', 'course', 10, 'Incident investigation', null, null, 'mco_training'),
    ('D04-11', 'HSF-D-04', 'course', 11, 'Hazardous chemical handling', 'T-HCA', null, 'mco_training'),
    ('D04-12', 'HSF-D-04', 'course', 12, 'Asbestos awareness', 'T-ASBESTOS', null, 'mco_training'),
    ('D04-13', 'HSF-D-04', 'course', 13, 'Lead awareness', 'T-LEAD', null, 'mco_training'),
    ('D04-14', 'HSF-D-04', 'course', 14, 'Hearing conservation', 'T-NOISE', null, 'mco_training'),
    ('D04-15', 'HSF-D-04', 'course', 15, 'Ergonomics', null, null, 'mco_training'),
    ('D04-16', 'HSF-D-04', 'course', 16, 'Emergency evacuation', null, null, 'mco_training'),
    ('D04-17', 'HSF-D-04', 'course', 17, 'Food handler hygiene', 'T-FOOD', null, 'mco_training'),
    ('D05-01', 'HSF-D-05', 'licence', 1, 'Professional driving permit', 'T-PRDP', 'NRTA PrDP medical', null),
    ('D05-02', 'HSF-D-05', 'licence', 2, 'Plant and machinery operator certificates', 'T-LIFTING or T-MOBILEPLANT', 'Driven Machinery Regulations', null),
    ('D05-03', 'HSF-D-05', 'licence', 3, 'Electrical wireman and installation registration', 'T-ELEC', 'Electrical Installation Regulations, 2009', null),
    ('D05-04', 'HSF-D-05', 'licence', 4, 'Gas practitioner registration', 'T-LPG', 'Pressure Equipment Regulations, 2009', null),
    ('D05-05', 'HSF-D-05', 'licence', 5, 'Explosives licence', 'T-EXPLOSIVES', 'Explosives Regulations', null),
    ('D05-06', 'HSF-D-05', 'licence', 6, 'Firearm competency', 'T-ARMED', 'Firearms Control Act', null),
    ('D05-07', 'HSF-D-05', 'licence', 7, 'PSIRA registration and grade', 'T-SECURITY', 'Private Security Industry Regulation Act', null),
    ('E06-01', 'HSF-E-06', 'examination', 1, 'Lead', 'T-LEAD', 'Lead Regulations, 2001', 'mco_medical'),
    ('E06-02', 'HSF-E-06', 'examination', 2, 'Asbestos', 'T-ASBESTOS', 'Asbestos Abatement Regulations, 2020', 'mco_medical'),
    ('E06-03', 'HSF-E-06', 'examination', 3, 'Hazardous chemical agents', 'T-HCA', 'HCA Regulations, 2021', 'mco_medical'),
    ('E06-04', 'HSF-E-06', 'examination', 4, 'Hazardous biological agents', 'T-HBA', 'HBA Regulations, 2022', 'mco_medical'),
    ('E06-05', 'HSF-E-06', 'examination', 5, 'Noise', 'T-NOISE', 'Noise Exposure Regulations, 2024', 'mco_medical'),
    ('E06-06', 'HSF-E-06', 'examination', 6, 'Radiation', 'T-RADIATION', 'Hazardous Substances Act (radiation control)', 'mco_medical'),
    ('E06-07', 'HSF-E-06', 'examination', 7, 'Heights', 'T-HEIGHT', 'Construction Regulations, 2014', 'mco_medical'),
    ('E06-08', 'HSF-E-06', 'examination', 8, 'Confined space', 'T-CONFINED', 'General Safety Regulations, 1986', 'mco_medical'),
    ('E06-09', 'HSF-E-06', 'examination', 9, 'Night work', 'T-SHIFT', 'BCEA night work Code', 'mco_medical'),
    ('E06-10', 'HSF-E-06', 'examination', 10, 'Food handling', 'T-FOOD', 'Food Premises Hygiene Regulations, R638 of 2018', 'mco_medical')
       ) as v(code, element_code, kind, ordinal, name, trigger_code, short_name, mco_source)
on conflict (code) do nothing;

-- 8. Element instrument links (provision awaiting verification until Phase 2) -------------
insert into hsf_element_instrument (element_id, instrument_id, provision)
select e.id, i.id, 'awaiting verification'
  from (values
    ('HSF-A-01', 'OHS Act'),
    ('HSF-A-02', 'OHS Act'),
    ('HSF-A-02', 'Construction Regulations, 2014'),
    ('HSF-A-03', 'COIDA'),
    ('HSF-A-04', 'OHS Act'),
    ('HSF-A-04', 'MHSA'),
    ('HSF-A-05', 'Construction Regulations, 2014'),
    ('HSF-A-06', 'Construction Regulations, 2014'),
    ('HSF-A-07', 'Construction Regulations, 2014'),
    ('HSF-A-08', 'OHS Act'),
    ('HSF-A-09', 'OHS Act'),
    ('HSF-A-09', 'Construction Regulations, 2014'),
    ('HSF-A-10', 'OHS Act'),
    ('HSF-A-11', 'OHS Act'),
    ('HSF-A-11', 'Construction Regulations, 2014'),
    ('HSF-B-01', 'OHS Act'),
    ('HSF-B-02', 'OHS Act'),
    ('HSF-B-03', 'OHS Act'),
    ('HSF-B-04', 'OHS Act'),
    ('HSF-B-04', 'General Administrative Regulations, 2003'),
    ('HSF-B-05', 'OHS Act'),
    ('HSF-B-05', 'General Administrative Regulations, 2003'),
    ('HSF-B-06', 'OHS Act'),
    ('HSF-B-06', 'Construction Regulations, 2014'),
    ('HSF-B-06', 'HCA Regulations, 2021'),
    ('HSF-B-06', 'Electrical Machinery and Installation Regulations'),
    ('HSF-B-06', 'Driven Machinery Regulations'),
    ('HSF-B-06', 'General Machinery Regulations, 1988'),
    ('HSF-B-06', 'Pressure Equipment Regulations, 2009'),
    ('HSF-B-06', 'General Safety Regulations, 1986'),
    ('HSF-B-06', 'SANS 10400 T part'),
    ('HSF-B-06', 'Local fire by laws'),
    ('HSF-B-06', 'Fire Brigade Services Act'),
    ('HSF-B-06', 'General Administrative Regulations, 2003'),
    ('HSF-B-06', 'Explosive powered tools regulations'),
    ('HSF-B-06', 'Asbestos Abatement Regulations, 2020'),
    ('HSF-B-06', 'Lead Regulations, 2001'),
    ('HSF-B-06', 'Noise Exposure Regulations, 2024'),
    ('HSF-B-06', 'Hazardous Substances Act (radiation control)'),
    ('HSF-B-06', 'Food Premises Hygiene Regulations, R638 of 2018'),
    ('HSF-B-06', 'NRTA PrDP medical'),
    ('HSF-B-06', 'National Road Traffic Act'),
    ('HSF-B-06', 'MHSA'),
    ('HSF-B-07', 'OHS Act'),
    ('HSF-B-08', 'OHS Act'),
    ('HSF-C-01', 'OHS Act'),
    ('HSF-C-01', 'Construction Regulations, 2014'),
    ('HSF-C-02', 'OHS Act'),
    ('HSF-C-03', 'OHS Act'),
    ('HSF-C-04', 'OHS Act'),
    ('HSF-C-05', 'OHS Act'),
    ('HSF-C-05', 'HCA Regulations, 2021'),
    ('HSF-C-06', 'OHS Act'),
    ('HSF-C-06', 'Construction Regulations, 2014'),
    ('HSF-C-07', 'Construction Regulations, 2014'),
    ('HSF-C-08', 'Construction Regulations, 2014'),
    ('HSF-C-08', 'General Safety Regulations, 1986'),
    ('HSF-C-09', 'Driven Machinery Regulations'),
    ('HSF-C-10', 'Construction Regulations, 2014'),
    ('HSF-C-11', 'Construction Regulations, 2014'),
    ('HSF-C-12', 'General Safety Regulations, 1986'),
    ('HSF-C-13', 'General Safety Regulations, 1986'),
    ('HSF-C-14', 'Ergonomics Regulations, 2019'),
    ('HSF-C-15', 'Noise Exposure Regulations, 2024'),
    ('HSF-C-16', 'HCA Regulations, 2021'),
    ('HSF-C-17', 'Asbestos Abatement Regulations, 2020'),
    ('HSF-C-18', 'Lead Regulations, 2001'),
    ('HSF-C-19', 'HBA Regulations, 2022'),
    ('HSF-C-20', 'BCEA night work Code'),
    ('HSF-C-20', 'BCEA'),
    ('HSF-C-21', 'MHI Regulations, 2022'),
    ('HSF-C-22', 'Physical Agents Regulations, 2024'),
    ('HSF-D-01', 'OHS Act'),
    ('HSF-D-01', 'Skills Development Act'),
    ('HSF-D-02', 'OHS Act'),
    ('HSF-D-03', 'OHS Act'),
    ('HSF-D-03', 'Construction Regulations, 2014'),
    ('HSF-D-04', 'Skills Development Act'),
    ('HSF-D-04', 'SETA unit standards'),
    ('HSF-D-05', 'NRTA PrDP medical'),
    ('HSF-D-05', 'Driven Machinery Regulations'),
    ('HSF-D-05', 'Electrical Installation Regulations, 2009'),
    ('HSF-D-05', 'Pressure Equipment Regulations, 2009'),
    ('HSF-D-05', 'Explosives Regulations'),
    ('HSF-D-05', 'Firearms Control Act'),
    ('HSF-D-05', 'Private Security Industry Regulation Act'),
    ('HSF-D-06', 'OHS Act'),
    ('HSF-D-07', 'Skills Development Act'),
    ('HSF-E-02', 'HCA Regulations, 2021'),
    ('HSF-E-02', 'HBA Regulations, 2022'),
    ('HSF-E-02', 'Noise Exposure Regulations, 2024'),
    ('HSF-E-02', 'Lead Regulations, 2001'),
    ('HSF-E-02', 'Ergonomics Regulations, 2019'),
    ('HSF-E-03', 'Construction Regulations, 2014'),
    ('HSF-E-04', 'NRTA PrDP medical'),
    ('HSF-E-05', 'MHSA'),
    ('HSF-E-05', 'Fitness to Perform Work Guideline (MHSA)'),
    ('HSF-E-06', 'Lead Regulations, 2001'),
    ('HSF-E-06', 'Asbestos Abatement Regulations, 2020'),
    ('HSF-E-06', 'HCA Regulations, 2021'),
    ('HSF-E-06', 'HBA Regulations, 2022'),
    ('HSF-E-06', 'Noise Exposure Regulations, 2024'),
    ('HSF-E-06', 'Hazardous Substances Act (radiation control)'),
    ('HSF-E-06', 'Construction Regulations, 2014'),
    ('HSF-E-06', 'General Safety Regulations, 1986'),
    ('HSF-E-06', 'BCEA night work Code'),
    ('HSF-E-06', 'Food Premises Hygiene Regulations, R638 of 2018'),
    ('HSF-E-07', 'EEA section 7'),
    ('HSF-E-07', 'Code of Good Practice on Employment of Persons with Disabilities'),
    ('HSF-E-08', 'COIDA'),
    ('HSF-E-08', 'ODMWA'),
    ('HSF-E-09', 'General Safety Regulations, 1986'),
    ('HSF-E-10', 'POPIA'),
    ('HSF-E-10', 'HPCSA Booklet 1'),
    ('HSF-F-01', 'Construction Regulations, 2014'),
    ('HSF-F-02', 'General Safety Regulations, 1986'),
    ('HSF-F-03', 'Driven Machinery Regulations'),
    ('HSF-F-04', 'Electrical Machinery and Installation Regulations'),
    ('HSF-F-04', 'Construction Regulations, 2014'),
    ('HSF-F-05', 'Electrical Machinery and Installation Regulations'),
    ('HSF-F-05', 'Electrical Installation Regulations, 2009'),
    ('HSF-F-05', 'SANS 10142'),
    ('HSF-F-06', 'SANS 10400 T part'),
    ('HSF-F-06', 'Local fire by laws'),
    ('HSF-F-07', 'SANS 10400'),
    ('HSF-F-08', 'Pressure Equipment Regulations, 2009'),
    ('HSF-F-09', 'Construction Regulations, 2014'),
    ('HSF-F-09', 'Driven Machinery Regulations'),
    ('HSF-F-10', 'Construction Regulations, 2014'),
    ('HSF-F-11', 'General Safety Regulations, 1986'),
    ('HSF-F-12', 'HCA Regulations, 2021'),
    ('HSF-F-13', 'Asbestos Abatement Regulations, 2020'),
    ('HSF-F-14', 'General Machinery Regulations, 1988'),
    ('HSF-F-15', 'Construction Regulations, 2014'),
    ('HSF-F-15', 'OHS Act'),
    ('HSF-F-16', 'General Safety Regulations, 1986'),
    ('HSF-F-17', 'Construction Regulations, 2014'),
    ('HSF-F-18', 'General Safety Regulations, 1986'),
    ('HSF-F-19', 'Explosive powered tools regulations'),
    ('HSF-F-20', 'Facilities Regulations, 2004'),
    ('HSF-F-21', 'Physical Agents Regulations, 2024'),
    ('HSF-F-22', 'NEM Waste Act'),
    ('HSF-G-01', 'OHS Act'),
    ('HSF-G-02', 'General Safety Regulations, 1986'),
    ('HSF-G-03', 'General Safety Regulations, 1986'),
    ('HSF-G-04', 'Construction Regulations, 2014'),
    ('HSF-G-05', 'Construction Regulations, 2014'),
    ('HSF-G-06', 'Electrical Machinery and Installation Regulations'),
    ('HSF-G-07', 'Driven Machinery Regulations'),
    ('HSF-G-08', 'Construction Regulations, 2014'),
    ('HSF-G-09', 'National Road Traffic Act'),
    ('HSF-G-10', 'Hazardous Substances Act (radiation control)'),
    ('HSF-H-01', 'OHS Act'),
    ('HSF-H-01', 'Construction Regulations, 2014'),
    ('HSF-H-02', 'OHS Act'),
    ('HSF-H-03', 'SANS 10400 T part'),
    ('HSF-H-03', 'Fire Brigade Services Act'),
    ('HSF-H-03', 'Local fire by laws'),
    ('HSF-H-04', 'General Safety Regulations, 1986'),
    ('HSF-H-05', 'HCA Regulations, 2021'),
    ('HSF-H-05', 'NEMA and its instruments'),
    ('HSF-H-06', 'MHI Regulations, 2022'),
    ('HSF-H-07', 'Private Security Industry Regulation Act'),
    ('HSF-H-08', 'Disaster Management Act'),
    ('HSF-I-01', 'General Administrative Regulations, 2003'),
    ('HSF-I-02', 'General Administrative Regulations, 2003'),
    ('HSF-I-03', 'OHS Act'),
    ('HSF-I-03', 'General Administrative Regulations, 2003'),
    ('HSF-I-04', 'General Administrative Regulations, 2003'),
    ('HSF-I-05', 'COIDA'),
    ('HSF-I-06', 'COIDA'),
    ('HSF-I-06', 'ODMWA'),
    ('HSF-I-07', 'OHS Act'),
    ('HSF-J-01', 'HCA Regulations, 2021'),
    ('HSF-J-01', 'Physical Agents Regulations, 2024'),
    ('HSF-J-02', 'Noise Exposure Regulations, 2024'),
    ('HSF-J-03', 'HCA Regulations, 2021'),
    ('HSF-J-04', 'Physical Agents Regulations, 2024'),
    ('HSF-J-05', 'Physical Agents Regulations, 2024'),
    ('HSF-J-06', 'Asbestos Abatement Regulations, 2020'),
    ('HSF-J-07', 'Lead Regulations, 2001'),
    ('HSF-J-08', 'Lead Regulations, 2001'),
    ('HSF-J-08', 'HCA Regulations, 2021'),
    ('HSF-K-01', 'Construction Regulations, 2014'),
    ('HSF-K-01', 'OHS Act'),
    ('HSF-K-02', 'OHS Act'),
    ('HSF-K-03', 'Construction Regulations, 2014'),
    ('HSF-K-04', 'OHS Act'),
    ('HSF-K-05', 'OHS Act'),
    ('HSF-K-05', 'Construction Regulations, 2014'),
    ('HSF-L-01', 'OHS Act'),
    ('HSF-L-02', 'OHS Act'),
    ('HSF-L-03', 'OHS Act'),
    ('HSF-L-04', 'OHS Act'),
    ('HSF-L-04', 'General Administrative Regulations, 2003'),
    ('HSF-L-05', 'OHS Act'),
    ('HSF-L-05', 'Construction Regulations, 2014'),
    ('HSF-M-01', 'Facilities Regulations, 2004'),
    ('HSF-M-02', 'Physical Agents Regulations, 2024'),
    ('HSF-M-03', 'NEM Waste Act'),
    ('HSF-M-03', 'NEMA and its instruments'),
    ('HSF-M-04', 'NEM Waste Act'),
    ('HSF-M-05', 'Tobacco Products Control Act'),
    ('HSF-N-01', 'OHS Act'),
    ('HSF-N-01', 'Construction Regulations, 2014'),
    ('HSF-N-02', 'Construction Regulations, 2014'),
    ('HSF-N-03', 'OHS Act'),
    ('HSF-N-04', 'OHS Act'),
    ('HSF-N-05', 'OHS Act'),
    ('HSF-O-01', 'HCA Regulations, 2021'),
    ('HSF-O-01', 'HBA Regulations, 2022'),
    ('HSF-O-01', 'Lead Regulations, 2001'),
    ('HSF-O-01', 'Asbestos Abatement Regulations, 2020'),
    ('HSF-O-02', 'POPIA'),
    ('HSF-O-03', 'POPIA'),
    ('HSF-OV-AGRI-01', 'HCA Regulations, 2021'),
    ('HSF-OV-AGRI-02', 'HCA Regulations, 2021'),
    ('HSF-OV-AGRI-03', 'General Machinery Regulations, 1988'),
    ('HSF-OV-AGRI-04', 'Skills Development Act'),
    ('HSF-OV-AGRI-05', 'HBA Regulations, 2022'),
    ('HSF-OV-AGRI-06', 'Regulations on Hazardous Work by Children, 2010'),
    ('HSF-OV-AGRI-07', 'OHS Act'),
    ('HSF-OV-AGRI-08', 'Physical Agents Regulations, 2024'),
    ('HSF-OV-AGRI-09', 'OHS Act'),
    ('HSF-OV-CLEAN-01', 'HCA Regulations, 2021'),
    ('HSF-OV-CLEAN-02', 'Construction Regulations, 2014'),
    ('HSF-OV-CLEAN-02', 'General Safety Regulations, 1986'),
    ('HSF-OV-CLEAN-03', 'General Safety Regulations, 1986'),
    ('HSF-OV-CLEAN-04', 'HBA Regulations, 2022'),
    ('HSF-OV-CLEAN-05', 'BCEA night work Code'),
    ('HSF-OV-CLEAN-06', 'OHS Act'),
    ('HSF-OV-CONSTR-01', 'Construction Regulations, 2014'),
    ('HSF-OV-CONSTR-02', 'Construction Regulations, 2014'),
    ('HSF-OV-CONSTR-03', 'Construction Regulations, 2014'),
    ('HSF-OV-CONSTR-04', 'Construction Regulations, 2014'),
    ('HSF-OV-CONSTR-05', 'Construction Regulations, 2014'),
    ('HSF-OV-CONSTR-06', 'Construction Regulations, 2014'),
    ('HSF-OV-CONSTR-07', 'Construction Regulations, 2014'),
    ('HSF-OV-CONSTR-08', 'Construction Regulations, 2014'),
    ('HSF-OV-CONSTR-09', 'Construction Regulations, 2014'),
    ('HSF-OV-EDU-01', 'HCA Regulations, 2021'),
    ('HSF-OV-EDU-02', 'OHS Act'),
    ('HSF-OV-EDU-03', 'NRTA PrDP medical'),
    ('HSF-OV-EDU-04', 'HBA Regulations, 2022'),
    ('HSF-OV-EDU-05', 'OHS Act'),
    ('HSF-OV-GOV-01', 'General Safety Regulations, 1986'),
    ('HSF-OV-GOV-02', 'EEA section 7'),
    ('HSF-OV-GOV-03', 'National Road Traffic Act'),
    ('HSF-OV-GOV-04', 'SANS 10400 T part'),
    ('HSF-OV-GOV-05', 'OHS Act'),
    ('HSF-OV-GOV-06', 'OHS Act'),
    ('HSF-OV-HEALTH-01', 'HBA Regulations, 2022'),
    ('HSF-OV-HEALTH-02', 'National Health Act'),
    ('HSF-OV-HEALTH-02', 'Health Care Waste regulations'),
    ('HSF-OV-HEALTH-02', 'NEM Waste Act'),
    ('HSF-OV-HEALTH-03', 'Hazardous Substances Act (radiation control)'),
    ('HSF-OV-HEALTH-04', 'HCA Regulations, 2021'),
    ('HSF-OV-HEALTH-05', 'Ergonomics Regulations, 2019'),
    ('HSF-OV-HEALTH-06', 'OHS Act'),
    ('HSF-OV-HEALTH-07', 'HBA Regulations, 2022'),
    ('HSF-OV-HEALTH-08', 'Nursing Act'),
    ('HSF-OV-HEALTH-08', 'Health Professions Act'),
    ('HSF-OV-HEALTH-08', 'SAHPRA provisions'),
    ('HSF-OV-HOSP-01', 'Food Premises Hygiene Regulations, R638 of 2018'),
    ('HSF-OV-HOSP-01', 'Foodstuffs, Cosmetics and Disinfectants Act'),
    ('HSF-OV-HOSP-02', 'Food Premises Hygiene Regulations, R638 of 2018'),
    ('HSF-OV-HOSP-03', 'Pressure Equipment Regulations, 2009'),
    ('HSF-OV-HOSP-04', 'OHS Act'),
    ('HSF-OV-HOSP-05', 'Local by laws'),
    ('HSF-OV-HOSP-06', 'HCA Regulations, 2021'),
    ('HSF-OV-MANU-01', 'General Machinery Regulations, 1988'),
    ('HSF-OV-MANU-02', 'HCA Regulations, 2021'),
    ('HSF-OV-MANU-03', 'Ergonomics Regulations, 2019'),
    ('HSF-OV-MANU-04', 'General Safety Regulations, 1986'),
    ('HSF-OV-MANU-05', 'Driven Machinery Regulations'),
    ('HSF-OV-MANU-06', 'National Road Traffic Act'),
    ('HSF-OV-MANU-06', 'SANS 10231'),
    ('HSF-OV-MANU-06', 'SANS 10232'),
    ('HSF-OV-MINING-01', 'MHSA'),
    ('HSF-OV-MINING-02', 'Fitness to Perform Work Guideline (MHSA)'),
    ('HSF-OV-MINING-03', 'DMRE mandatory Code guidelines'),
    ('HSF-OV-MINING-04', 'DMRE mandatory Code guidelines'),
    ('HSF-OV-MINING-05', 'DMRE mandatory Code guidelines'),
    ('HSF-OV-MINING-06', 'DMRE mandatory Code guidelines'),
    ('HSF-OV-MINING-07', 'DMRE mandatory Code guidelines'),
    ('HSF-OV-MINING-08', 'DMRE mandatory Code guidelines'),
    ('HSF-OV-MINING-09', 'DMRE mandatory Code guidelines'),
    ('HSF-OV-MINING-10', 'MHSA'),
    ('HSF-OV-MINING-11', 'ODMWA'),
    ('HSF-OV-MINING-12', 'MHSA'),
    ('HSF-OV-MINING-13', 'Explosives Regulations'),
    ('HSF-OV-MINING-14', 'MHSA regulations'),
    ('HSF-OV-MINING-15', 'MHSA regulations'),
    ('HSF-OV-MINING-16', 'MHSA'),
    ('HSF-OV-OFFICE-01', 'Ergonomics Regulations, 2019'),
    ('HSF-OV-OFFICE-02', 'BCEA night work Code'),
    ('HSF-OV-OFFICE-02', 'Noise Exposure Regulations, 2024'),
    ('HSF-OV-OFFICE-03', 'OHS Act'),
    ('HSF-OV-OFFICE-04', 'OHS Act'),
    ('HSF-OV-PETRO-01', 'MHI Regulations, 2022'),
    ('HSF-OV-PETRO-02', 'Electrical Machinery and Installation Regulations'),
    ('HSF-OV-PETRO-03', 'National Road Traffic Act'),
    ('HSF-OV-PETRO-03', 'SANS 10231'),
    ('HSF-OV-PETRO-03', 'SANS 10232'),
    ('HSF-OV-PETRO-04', 'MHI Regulations, 2022'),
    ('HSF-OV-PETRO-05', 'Electrical Machinery and Installation Regulations'),
    ('HSF-OV-PETRO-06', 'NEMA and its instruments'),
    ('HSF-OV-RETAIL-01', 'General Safety Regulations, 1986'),
    ('HSF-OV-RETAIL-02', 'General Safety Regulations, 1986'),
    ('HSF-OV-RETAIL-03', 'Physical Agents Regulations, 2024'),
    ('HSF-OV-RETAIL-04', 'OHS Act'),
    ('HSF-OV-RETAIL-05', 'SANS 10400 T part'),
    ('HSF-OV-SEC-01', 'Private Security Industry Regulation Act'),
    ('HSF-OV-SEC-01', 'PSIRA training regulations'),
    ('HSF-OV-SEC-02', 'Firearms Control Act'),
    ('HSF-OV-SEC-03', 'Firearms Control Act'),
    ('HSF-OV-SEC-03', 'National Road Traffic Act'),
    ('HSF-OV-SEC-04', 'OHS Act'),
    ('HSF-OV-SEC-05', 'OHS Act'),
    ('HSF-OV-SEC-06', 'Ergonomics Regulations, 2019'),
    ('HSF-OV-SEC-07', 'OHS Act'),
    ('HSF-OV-TEL-01', 'Construction Regulations, 2014'),
    ('HSF-OV-TEL-02', 'Physical Agents Regulations, 2024'),
    ('HSF-OV-TEL-03', 'General Safety Regulations, 1986'),
    ('HSF-OV-TEL-04', 'OHS Act'),
    ('HSF-OV-TRANS-01', 'National Road Traffic Act'),
    ('HSF-OV-TRANS-02', 'National Road Traffic Act'),
    ('HSF-OV-TRANS-02', 'SANS 10231'),
    ('HSF-OV-TRANS-02', 'SANS 10232'),
    ('HSF-OV-TRANS-03', 'BCEA'),
    ('HSF-OV-TRANS-04', 'SANS 3000-4 (RSR)'),
    ('HSF-OV-TRANS-04', 'Railway Safety Regulator Act'),
    ('HSF-OV-TRANS-04', 'SANS 3000 series'),
    ('HSF-OV-TRANS-05', 'Merchant Shipping Act'),
    ('HSF-OV-TRANS-05', 'Ports Act'),
    ('HSF-OV-TRANS-06', 'Civil Aviation Act'),
    ('HSF-OV-TRANS-06', 'Civil Aviation Regulations'),
    ('HSF-OV-TRANS-07', 'National Road Traffic Act'),
    ('HSF-OV-UTIL-01', 'Electrical Machinery and Installation Regulations'),
    ('HSF-OV-UTIL-02', 'Electrical Machinery and Installation Regulations'),
    ('HSF-OV-UTIL-03', 'HCA Regulations, 2021'),
    ('HSF-OV-UTIL-04', 'Electrical Machinery and Installation Regulations'),
    ('HSF-OV-UTIL-05', 'OHS Act'),
    ('HSF-OV-UTIL-06', 'NEMA and its instruments'),
    ('HSF-OV-WASTE-01', 'NEM Waste Act'),
    ('HSF-OV-WASTE-02', 'NEM Waste Act'),
    ('HSF-OV-WASTE-02', 'Health Care Waste regulations'),
    ('HSF-OV-WASTE-03', 'HBA Regulations, 2022'),
    ('HSF-OV-WASTE-04', 'General Safety Regulations, 1986'),
    ('HSF-OV-WASTE-04', 'HCA Regulations, 2021'),
    ('HSF-OV-WASTE-05', 'General Safety Regulations, 1986'),
    ('HSF-OV-WASTE-06', 'HBA Regulations, 2022'),
    ('HSF-OV-WASTE-07', 'HCA Regulations, 2021'),
    ('HSF-OV-WASTE-08', 'NEMA and its instruments')
       ) as v(code, short_name)
  join hsf_element e on e.code = v.code
  cross join lateral (select li.id from msp_legal_instrument li where li.short_name = v.short_name order by case li.status when 'verified' then 0 when 'pending' then 1 when 'superseded' then 2 else 3 end, li.verified_on desc nulls last, li.id limit 1) i
on conflict (element_id, instrument_id) do nothing;

-- 9. Element industry rows: overlay additions, universal elements each overlay switches on,
--    and the kernel pack surveillance protocols per industry (HSF-E-06 emphasis).
insert into hsf_element_industry (element_id, industry_id, subindustry_id, applicability, overlay_note)
select e.id, i.id, null, v.applicability, v.overlay_note
  from (values
    ('HSF-A-06', 'CONSTR', 'mandatory', 'Switched on by the Construction overlay through T-CONSTR and every construction trigger raised by the intake.'),
    ('HSF-A-06', 'GOV', 'conditional', 'Switched on by the Government and municipal overlay through T-CONSTR for public works.'),
    ('HSF-A-06', 'TEL', 'conditional', 'Switched on by the Telecommunications and tower work overlay through T-CONSTR where towers are built.'),
    ('HSF-A-06', 'UTIL', 'conditional', 'Switched on by the Utilities and energy overlay through T-CONSTR for renewable installation.'),
    ('HSF-A-07', 'CONSTR', 'mandatory', 'Switched on by the Construction overlay through T-CONSTR and every construction trigger raised by the intake.'),
    ('HSF-A-07', 'GOV', 'conditional', 'Switched on by the Government and municipal overlay through T-CONSTR for public works.'),
    ('HSF-A-07', 'TEL', 'conditional', 'Switched on by the Telecommunications and tower work overlay through T-CONSTR where towers are built.'),
    ('HSF-A-07', 'UTIL', 'conditional', 'Switched on by the Utilities and energy overlay through T-CONSTR for renewable installation.'),
    ('HSF-A-08', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-CONTRACTORS.'),
    ('HSF-A-08', 'GOV', 'mandatory', 'Switched on by the Government and municipal overlay through T-CONTRACTORS.'),
    ('HSF-A-09', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-CONTRACTORS.'),
    ('HSF-A-09', 'GOV', 'mandatory', 'Switched on by the Government and municipal overlay through T-CONTRACTORS.'),
    ('HSF-C-07', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-HEIGHT.'),
    ('HSF-C-07', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-HEIGHT.'),
    ('HSF-C-07', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-HEIGHT.'),
    ('HSF-C-08', 'RETAIL', 'mandatory', 'Switched on by the Retail and wholesale overlay through T-TRAFFIC.'),
    ('HSF-C-08', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-TRAFFIC.'),
    ('HSF-C-09', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-LIFTING.'),
    ('HSF-C-09', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-LIFTING.'),
    ('HSF-C-12', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-CONFINED.'),
    ('HSF-C-12', 'GOV', 'mandatory', 'Switched on by the Government and municipal overlay through T-CONFINED.'),
    ('HSF-C-12', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-CONFINED.'),
    ('HSF-C-12', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-CONFINED.'),
    ('HSF-C-12', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-CONFINED.'),
    ('HSF-C-12', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-CONFINED.'),
    ('HSF-C-12', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-CONFINED.'),
    ('HSF-C-13', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-HOTWORK.'),
    ('HSF-C-15', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-NOISE.'),
    ('HSF-C-16', 'AGRI', 'mandatory', 'Switched on by the Agriculture and forestry overlay through T-HCA.'),
    ('HSF-C-16', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-HCA.'),
    ('HSF-C-16', 'EDU', 'conditional', 'Switched on by the Education overlay through T-HCA for laboratories.'),
    ('HSF-C-16', 'HEALTH', 'mandatory', 'Switched on by the Healthcare and laboratories overlay through T-HCA.'),
    ('HSF-C-16', 'HOSP', 'mandatory', 'Switched on by the Hospitality and food service overlay through T-HCA.'),
    ('HSF-C-16', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-HCA.'),
    ('HSF-C-16', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-HCA.'),
    ('HSF-C-16', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-HCA.'),
    ('HSF-C-16', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-HCA.'),
    ('HSF-C-17', 'MANU', 'conditional', 'Switched on by the Manufacturing overlay through T-ASBESTOS where legacy plant exists.'),
    ('HSF-C-18', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-LEAD.'),
    ('HSF-C-19', 'AGRI', 'mandatory', 'Switched on by the Agriculture and forestry overlay through T-HBA.'),
    ('HSF-C-19', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-HBA.'),
    ('HSF-C-19', 'EDU', 'mandatory', 'Switched on by the Education overlay through T-HBA.'),
    ('HSF-C-19', 'HEALTH', 'mandatory', 'Switched on by the Healthcare and laboratories overlay through T-HBA.'),
    ('HSF-C-19', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-HBA.'),
    ('HSF-C-20', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-SHIFT.'),
    ('HSF-C-20', 'HEALTH', 'mandatory', 'Switched on by the Healthcare and laboratories overlay through T-SHIFT, T-VIOLENCE.'),
    ('HSF-C-20', 'HOSP', 'mandatory', 'Switched on by the Hospitality and food service overlay through T-SHIFT, T-VIOLENCE.'),
    ('HSF-C-20', 'OFFICE', 'conditional', 'Switched on by the Office and professional services overlay through T-SHIFT for contact centres.'),
    ('HSF-C-20', 'RETAIL', 'mandatory', 'Switched on by the Retail and wholesale overlay through T-VIOLENCE.'),
    ('HSF-C-20', 'SEC', 'mandatory', 'Switched on by the Security services overlay through T-SHIFT, T-VIOLENCE.'),
    ('HSF-C-20', 'TRANS', 'mandatory', 'Switched on by the Transport and logistics overlay through T-SHIFT.'),
    ('HSF-C-21', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-MHI.'),
    ('HSF-E-03', 'CONSTR', 'mandatory', 'Switched on by the Construction overlay through T-CONSTR and every construction trigger raised by the intake.'),
    ('HSF-E-03', 'GOV', 'conditional', 'Switched on by the Government and municipal overlay through T-CONSTR for public works.'),
    ('HSF-E-03', 'TEL', 'conditional', 'Switched on by the Telecommunications and tower work overlay through T-CONSTR where towers are built.'),
    ('HSF-E-03', 'UTIL', 'conditional', 'Switched on by the Utilities and energy overlay through T-CONSTR for renewable installation.'),
    ('HSF-E-04', 'AGRI', 'mandatory', 'Switched on by the Agriculture and forestry overlay through T-PRDP.'),
    ('HSF-E-04', 'EDU', 'mandatory', 'Switched on by the Education overlay through T-PRDP.'),
    ('HSF-E-04', 'GOV', 'mandatory', 'Switched on by the Government and municipal overlay through T-PRDP.'),
    ('HSF-E-04', 'RETAIL', 'mandatory', 'Switched on by the Retail and wholesale overlay through T-PRDP.'),
    ('HSF-E-04', 'SEC', 'mandatory', 'Switched on by the Security services overlay through T-PRDP.'),
    ('HSF-E-04', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-PRDP.'),
    ('HSF-E-04', 'TRANS', 'mandatory', 'Switched on by the Transport and logistics overlay through T-PRDP.'),
    ('HSF-E-04', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-PRDP.'),
    ('HSF-E-05', 'MINING', 'mandatory', 'Switched on by the Mining overlay through T-MINING.'),
    ('HSF-E-06', 'AGRI', 'emphasis', 'Kernel pack surveillance protocols for Agriculture and forestry. Often: Audiometry, Cholinesterase monitoring for pesticide exposure, Zoonosis surveillance per written medical protocol, Heat stress tolerance assessment, Musculoskeletal and ergonomic assessment, Dermatological screen, Vision screening with colour vision and UV skin surveillance. Only if the risk assessment confirms exposure: Spirometry, Respiratory symptom questionnaire, Biological monitoring for specific chemical agents, Confined space medical, Night work medical examination, Biological agent surveillance per written medical protocol. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'CLEAN', 'emphasis', 'Kernel pack surveillance protocols for Cleaning and hygiene services. Often: Dermatological screen, Biological agent surveillance per written medical protocol, Musculoskeletal and ergonomic assessment, Hepatitis B immunity verification and vaccination pathway. Only if the risk assessment confirms exposure: Occupational chemical exposure medical assessment, Biological monitoring for specific chemical agents, Night work medical examination, Respiratory symptom questionnaire, Occupational tuberculosis screening. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'CONSTR', 'emphasis', 'Kernel pack surveillance protocols for Construction. Often: General construction fitness, Audiometry, Heights medical with vertigo and balance screen, Musculoskeletal and ergonomic assessment, Vision screening with colour vision and UV skin surveillance, Heat stress tolerance assessment, Lifting machine operator certificate of fitness, Vibration and musculoskeletal screen, General medical for electrical work. Only if the risk assessment confirms exposure: Spirometry, Respiratory symptom questionnaire, Chest X ray per silica protocol, Confined space medical, Blood lead biological monitoring, Lead exposure clinical examination, Dermatological screen, Night work medical examination. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'EDU', 'emphasis', 'Kernel pack surveillance protocols for Education. Often: General fitness for the inherent requirements of the job, Food handler fitness assessment, Occupational tuberculosis screening, Biological agent surveillance per written medical protocol. Only if the risk assessment confirms exposure: Audiometry, Spirometry, Occupational chemical exposure medical assessment, Dermatological screen, Night work medical examination. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'GOV', 'emphasis', 'Kernel pack surveillance protocols for Government and municipal. Often: Audiometry, Vision screening with colour vision and UV skin surveillance, Night work medical examination, Musculoskeletal and ergonomic assessment, Heat stress tolerance assessment, PrDP statutory medical and vision screen. Only if the risk assessment confirms exposure: Biological agent surveillance per written medical protocol, Confined space medical, Heights medical with vertigo and balance screen, Occupational chemical exposure medical assessment, Spirometry. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'HEALTH', 'emphasis', 'Kernel pack surveillance protocols for Healthcare and laboratories. Often: Biological agent surveillance per written medical protocol, Occupational tuberculosis screening, Hepatitis B immunity verification and vaccination pathway, Night work medical examination, Dermatological screen, Musculoskeletal and ergonomic assessment. Only if the risk assessment confirms exposure: Radiation worker surveillance with dose monitoring, Occupational chemical exposure medical assessment, Spirometry, Vision screening with colour vision and UV skin surveillance, Audiometry. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'HOSP', 'emphasis', 'Kernel pack surveillance protocols for Hospitality and food service. Often: Food handler fitness assessment, Dermatological screen, Musculoskeletal and ergonomic assessment, Night work medical examination. Only if the risk assessment confirms exposure: Heat stress tolerance assessment, Biological agent surveillance per written medical protocol, Hepatitis B immunity verification and vaccination pathway, Vision screening with colour vision and UV skin surveillance. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'MANU', 'emphasis', 'Kernel pack surveillance protocols for Manufacturing. Often: Audiometry, Spirometry, Respiratory symptom questionnaire, Occupational chemical exposure medical assessment, Biological monitoring for specific chemical agents, Dermatological screen, Vibration and musculoskeletal screen, Musculoskeletal and ergonomic assessment, Vision screening with colour vision and UV skin surveillance, Night work medical examination, Lifting machine operator certificate of fitness, Heat stress tolerance assessment. Only if the risk assessment confirms exposure: Blood lead biological monitoring, Lead exposure clinical examination, Confined space medical, Cholinesterase monitoring for pesticide exposure, Food handler fitness assessment, Biological agent surveillance per written medical protocol. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'MINING', 'emphasis', 'Kernel pack surveillance protocols for Mining. Often: Mine certificate of fitness examination, Dust disease examination battery for mine workers, Chest X ray per silica protocol, Heat tolerance screening for hot underground workings, Audiometry, Spirometry, Respiratory symptom questionnaire, Vision screening with colour vision and UV skin surveillance. Only if the risk assessment confirms exposure: Vibration and musculoskeletal screen, Biological monitoring for specific chemical agents, Radiation worker surveillance with dose monitoring, Confined space medical, Night work medical examination. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'OFFICE', 'emphasis', 'Kernel pack surveillance protocols for Office and professional services. Often: Musculoskeletal and ergonomic assessment, Vision screening with colour vision and UV skin surveillance. Only if the risk assessment confirms exposure: Night work medical examination, Audiometry. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'PETRO', 'emphasis', 'Kernel pack surveillance protocols for Petrochemical and fuel retail. Often: Occupational chemical exposure medical assessment, Biological monitoring for specific chemical agents, Spirometry, Respiratory symptom questionnaire, Audiometry, Confined space medical, Night work medical examination, Vision screening with colour vision and UV skin surveillance, Heat stress tolerance assessment, Dermatological screen. Only if the risk assessment confirms exposure: Blood lead biological monitoring, Lead exposure clinical examination, Radiation worker surveillance with dose monitoring, Heights medical with vertigo and balance screen, Lifting machine operator certificate of fitness. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'RETAIL', 'emphasis', 'Kernel pack surveillance protocols for Retail and wholesale. Often: Musculoskeletal and ergonomic assessment, Vision screening with colour vision and UV skin surveillance, Lifting machine operator certificate of fitness, Food handler fitness assessment. Only if the risk assessment confirms exposure: Night work medical examination, Audiometry, Heat stress tolerance assessment, PrDP statutory medical and vision screen, Hepatitis B immunity verification and vaccination pathway, Biological agent surveillance per written medical protocol. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'SEC', 'emphasis', 'Kernel pack surveillance protocols for Security services. Often: Night work medical examination, Vision screening with colour vision and UV skin surveillance, Musculoskeletal and ergonomic assessment, General fitness for the inherent requirements of the job. Only if the risk assessment confirms exposure: PrDP statutory medical and vision screen, Heat stress tolerance assessment, Audiometry, Heights medical with vertigo and balance screen. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'TEL', 'emphasis', 'Kernel pack surveillance protocols for Telecommunications and tower work. Often: Heights medical with vertigo and balance screen, Vision screening with colour vision and UV skin surveillance, Musculoskeletal and ergonomic assessment, Confined space medical, Heat stress tolerance assessment, General medical for electrical work. Only if the risk assessment confirms exposure: Audiometry, Night work medical examination, Radiation worker surveillance with dose monitoring, Spirometry. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'TRANS', 'emphasis', 'Kernel pack surveillance protocols for Transport and logistics. Often: PrDP statutory medical and vision screen, Vision screening with colour vision and UV skin surveillance, Audiometry, Vibration and musculoskeletal screen, Musculoskeletal and ergonomic assessment, Night work medical examination, Lifting machine operator certificate of fitness. Only if the risk assessment confirms exposure: Railway safety critical fitness examination, Confined space medical, Biological monitoring for specific chemical agents, Occupational chemical exposure medical assessment, Heat stress tolerance assessment, Spirometry. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'UTIL', 'emphasis', 'Kernel pack surveillance protocols for Utilities and energy. Often: Audiometry, Confined space medical, General medical for electrical work, Heights medical with vertigo and balance screen, Vision screening with colour vision and UV skin surveillance, Night work medical examination, Biological agent surveillance per written medical protocol, Heat stress tolerance assessment, Musculoskeletal and ergonomic assessment. Only if the risk assessment confirms exposure: Biological monitoring for specific chemical agents, Spirometry, Radiation worker surveillance with dose monitoring, Cholinesterase monitoring for pesticide exposure. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-E-06', 'WASTE', 'emphasis', 'Kernel pack surveillance protocols for Waste management. Often: Biological agent surveillance per written medical protocol, Hepatitis B immunity verification and vaccination pathway, Dermatological screen, Audiometry, Musculoskeletal and ergonomic assessment, Tetanus status within the OMP protocol, Vision screening with colour vision and UV skin surveillance, Heat stress tolerance assessment. Only if the risk assessment confirms exposure: Blood lead biological monitoring, Lead exposure clinical examination, Spirometry, Respiratory symptom questionnaire, Occupational tuberculosis screening, Night work medical examination, Confined space medical, Biological monitoring for specific chemical agents. The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'),
    ('HSF-F-03', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-LIFTING.'),
    ('HSF-F-03', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-LIFTING.'),
    ('HSF-F-08', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-PRESSURE.'),
    ('HSF-F-09', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-MOBILEPLANT.'),
    ('HSF-F-09', 'RETAIL', 'mandatory', 'Switched on by the Retail and wholesale overlay through T-MOBILEPLANT.'),
    ('HSF-F-09', 'TRANS', 'mandatory', 'Switched on by the Transport and logistics overlay through T-MOBILEPLANT.'),
    ('HSF-F-09', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-MOBILEPLANT.'),
    ('HSF-F-12', 'AGRI', 'mandatory', 'Switched on by the Agriculture and forestry overlay through T-HCA.'),
    ('HSF-F-12', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-HCA.'),
    ('HSF-F-12', 'EDU', 'conditional', 'Switched on by the Education overlay through T-HCA for laboratories.'),
    ('HSF-F-12', 'HEALTH', 'mandatory', 'Switched on by the Healthcare and laboratories overlay through T-HCA.'),
    ('HSF-F-12', 'HOSP', 'mandatory', 'Switched on by the Hospitality and food service overlay through T-HCA.'),
    ('HSF-F-12', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-HCA.'),
    ('HSF-F-12', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-HCA.'),
    ('HSF-F-12', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-HCA.'),
    ('HSF-F-12', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-HCA.'),
    ('HSF-F-13', 'MANU', 'conditional', 'Switched on by the Manufacturing overlay through T-ASBESTOS where legacy plant exists.'),
    ('HSF-F-14', 'AGRI', 'mandatory', 'Switched on by the Agriculture and forestry overlay through T-MACHINERY.'),
    ('HSF-F-14', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-MACHINERY.'),
    ('HSF-F-16', 'RETAIL', 'mandatory', 'Switched on by the Retail and wholesale overlay through T-STACKING.'),
    ('HSF-F-16', 'TRANS', 'mandatory', 'Switched on by the Transport and logistics overlay through T-STACKING.'),
    ('HSF-F-17', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-HEIGHT.'),
    ('HSF-F-17', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-HEIGHT.'),
    ('HSF-F-17', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-HEIGHT.'),
    ('HSF-F-18', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-CONFINED.'),
    ('HSF-F-18', 'GOV', 'mandatory', 'Switched on by the Government and municipal overlay through T-CONFINED.'),
    ('HSF-F-18', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-CONFINED.'),
    ('HSF-F-18', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-CONFINED.'),
    ('HSF-F-18', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-CONFINED.'),
    ('HSF-F-18', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-CONFINED.'),
    ('HSF-F-18', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-CONFINED.'),
    ('HSF-F-22', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-WASTE.'),
    ('HSF-F-22', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-WASTE.'),
    ('HSF-G-01', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-PTW.'),
    ('HSF-G-02', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-HOTWORK.'),
    ('HSF-G-03', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-CONFINED.'),
    ('HSF-G-03', 'GOV', 'mandatory', 'Switched on by the Government and municipal overlay through T-CONFINED.'),
    ('HSF-G-03', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-CONFINED.'),
    ('HSF-G-03', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-CONFINED.'),
    ('HSF-G-03', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-CONFINED.'),
    ('HSF-G-03', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-CONFINED.'),
    ('HSF-G-03', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-CONFINED.'),
    ('HSF-G-05', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-HEIGHT.'),
    ('HSF-G-05', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-HEIGHT.'),
    ('HSF-G-05', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-HEIGHT.'),
    ('HSF-G-06', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-ELEC.'),
    ('HSF-G-06', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-ELEC.'),
    ('HSF-G-06', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-ELEC.'),
    ('HSF-G-06', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-ELEC.'),
    ('HSF-G-07', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-LIFTING.'),
    ('HSF-G-07', 'TEL', 'mandatory', 'Switched on by the Telecommunications and tower work overlay through T-LIFTING.'),
    ('HSF-G-10', 'HEALTH', 'mandatory', 'Switched on by the Healthcare and laboratories overlay through T-RADIATION.'),
    ('HSF-H-05', 'AGRI', 'mandatory', 'Switched on by the Agriculture and forestry overlay through T-HCA.'),
    ('HSF-H-05', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-HCA.'),
    ('HSF-H-05', 'EDU', 'conditional', 'Switched on by the Education overlay through T-HCA for laboratories.'),
    ('HSF-H-05', 'HEALTH', 'mandatory', 'Switched on by the Healthcare and laboratories overlay through T-HCA.'),
    ('HSF-H-05', 'HOSP', 'mandatory', 'Switched on by the Hospitality and food service overlay through T-HCA.'),
    ('HSF-H-05', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-HCA.'),
    ('HSF-H-05', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-HCA.'),
    ('HSF-H-05', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-HCA.'),
    ('HSF-H-05', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-HCA.'),
    ('HSF-H-06', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-MHI.'),
    ('HSF-H-07', 'SEC', 'mandatory', 'Switched on by the Security services overlay through T-SECURITY.'),
    ('HSF-H-08', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-MHI.'),
    ('HSF-J-02', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-NOISE.'),
    ('HSF-J-03', 'AGRI', 'mandatory', 'Switched on by the Agriculture and forestry overlay through T-HCA.'),
    ('HSF-J-03', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-HCA.'),
    ('HSF-J-03', 'EDU', 'conditional', 'Switched on by the Education overlay through T-HCA for laboratories.'),
    ('HSF-J-03', 'HEALTH', 'mandatory', 'Switched on by the Healthcare and laboratories overlay through T-HCA.'),
    ('HSF-J-03', 'HOSP', 'mandatory', 'Switched on by the Hospitality and food service overlay through T-HCA.'),
    ('HSF-J-03', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-HCA.'),
    ('HSF-J-03', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-HCA.'),
    ('HSF-J-03', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-HCA.'),
    ('HSF-J-03', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-HCA.'),
    ('HSF-J-05', 'AGRI', 'mandatory', 'Switched on by the Agriculture and forestry overlay through T-THERMAL.'),
    ('HSF-J-06', 'MANU', 'conditional', 'Switched on by the Manufacturing overlay through T-ASBESTOS where legacy plant exists.'),
    ('HSF-J-07', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-LEAD.'),
    ('HSF-J-08', 'AGRI', 'mandatory', 'Switched on by the Agriculture and forestry overlay through T-HCA.'),
    ('HSF-J-08', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-HCA.'),
    ('HSF-J-08', 'EDU', 'conditional', 'Switched on by the Education overlay through T-HCA for laboratories.'),
    ('HSF-J-08', 'HEALTH', 'mandatory', 'Switched on by the Healthcare and laboratories overlay through T-HCA.'),
    ('HSF-J-08', 'HOSP', 'mandatory', 'Switched on by the Hospitality and food service overlay through T-HCA.'),
    ('HSF-J-08', 'MANU', 'mandatory', 'Switched on by the Manufacturing overlay through T-HCA, T-LEAD.'),
    ('HSF-J-08', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-HCA.'),
    ('HSF-J-08', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-HCA.'),
    ('HSF-J-08', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-HCA.'),
    ('HSF-K-01', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-CONTRACTORS.'),
    ('HSF-K-01', 'GOV', 'mandatory', 'Switched on by the Government and municipal overlay through T-CONTRACTORS.'),
    ('HSF-K-02', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-CONTRACTORS.'),
    ('HSF-K-02', 'GOV', 'mandatory', 'Switched on by the Government and municipal overlay through T-CONTRACTORS.'),
    ('HSF-K-03', 'CLEAN', 'mandatory', 'Switched on by the Cleaning and hygiene services overlay through T-CONTRACTORS.'),
    ('HSF-K-03', 'GOV', 'mandatory', 'Switched on by the Government and municipal overlay through T-CONTRACTORS.'),
    ('HSF-K-05', 'UTIL', 'mandatory', 'Switched on by the Utilities and energy overlay through T-PUBLIC.'),
    ('HSF-M-03', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-WASTE.'),
    ('HSF-M-03', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-WASTE.'),
    ('HSF-M-04', 'PETRO', 'mandatory', 'Switched on by the Petrochemical and fuel retail overlay through T-WASTE.'),
    ('HSF-M-04', 'WASTE', 'mandatory', 'Switched on by the Waste management overlay through T-WASTE.'),
    ('HSF-OV-AGRI-01', 'AGRI', 'mandatory', 'Addition of the Agriculture and forestry overlay (SPEC B7).'),
    ('HSF-OV-AGRI-02', 'AGRI', 'mandatory', 'Addition of the Agriculture and forestry overlay (SPEC B7).'),
    ('HSF-OV-AGRI-03', 'AGRI', 'mandatory', 'Addition of the Agriculture and forestry overlay (SPEC B7).'),
    ('HSF-OV-AGRI-04', 'AGRI', 'mandatory', 'Addition of the Agriculture and forestry overlay (SPEC B7).'),
    ('HSF-OV-AGRI-05', 'AGRI', 'mandatory', 'Addition of the Agriculture and forestry overlay (SPEC B7).'),
    ('HSF-OV-AGRI-06', 'AGRI', 'mandatory', 'Addition of the Agriculture and forestry overlay (SPEC B7).'),
    ('HSF-OV-AGRI-07', 'AGRI', 'mandatory', 'Addition of the Agriculture and forestry overlay (SPEC B7).'),
    ('HSF-OV-AGRI-08', 'AGRI', 'mandatory', 'Addition of the Agriculture and forestry overlay (SPEC B7).'),
    ('HSF-OV-AGRI-09', 'AGRI', 'mandatory', 'Addition of the Agriculture and forestry overlay (SPEC B7).'),
    ('HSF-OV-CLEAN-01', 'CLEAN', 'mandatory', 'Addition of the Cleaning and hygiene services overlay (SPEC B7).'),
    ('HSF-OV-CLEAN-02', 'CLEAN', 'mandatory', 'Addition of the Cleaning and hygiene services overlay (SPEC B7).'),
    ('HSF-OV-CLEAN-03', 'CLEAN', 'mandatory', 'Addition of the Cleaning and hygiene services overlay (SPEC B7).'),
    ('HSF-OV-CLEAN-04', 'CLEAN', 'mandatory', 'Addition of the Cleaning and hygiene services overlay (SPEC B7).'),
    ('HSF-OV-CLEAN-05', 'CLEAN', 'mandatory', 'Addition of the Cleaning and hygiene services overlay (SPEC B7).'),
    ('HSF-OV-CLEAN-06', 'CLEAN', 'mandatory', 'Addition of the Cleaning and hygiene services overlay (SPEC B7).'),
    ('HSF-OV-CONSTR-01', 'CONSTR', 'mandatory', 'Addition of the Construction overlay (SPEC B7).'),
    ('HSF-OV-CONSTR-02', 'CONSTR', 'mandatory', 'Addition of the Construction overlay (SPEC B7).'),
    ('HSF-OV-CONSTR-03', 'CONSTR', 'mandatory', 'Addition of the Construction overlay (SPEC B7).'),
    ('HSF-OV-CONSTR-04', 'CONSTR', 'mandatory', 'Addition of the Construction overlay (SPEC B7).'),
    ('HSF-OV-CONSTR-05', 'CONSTR', 'mandatory', 'Addition of the Construction overlay (SPEC B7).'),
    ('HSF-OV-CONSTR-06', 'CONSTR', 'mandatory', 'Addition of the Construction overlay (SPEC B7).'),
    ('HSF-OV-CONSTR-07', 'CONSTR', 'mandatory', 'Addition of the Construction overlay (SPEC B7).'),
    ('HSF-OV-CONSTR-08', 'CONSTR', 'mandatory', 'Addition of the Construction overlay (SPEC B7).'),
    ('HSF-OV-CONSTR-09', 'CONSTR', 'mandatory', 'Addition of the Construction overlay (SPEC B7).'),
    ('HSF-OV-EDU-01', 'EDU', 'mandatory', 'Addition of the Education overlay (SPEC B7).'),
    ('HSF-OV-EDU-02', 'EDU', 'mandatory', 'Addition of the Education overlay (SPEC B7).'),
    ('HSF-OV-EDU-03', 'EDU', 'mandatory', 'Addition of the Education overlay (SPEC B7).'),
    ('HSF-OV-EDU-04', 'EDU', 'mandatory', 'Addition of the Education overlay (SPEC B7).'),
    ('HSF-OV-EDU-05', 'EDU', 'mandatory', 'Addition of the Education overlay (SPEC B7).'),
    ('HSF-OV-EDU-06', 'EDU', 'mandatory', 'Addition of the Education overlay (SPEC B7).'),
    ('HSF-OV-GOV-01', 'GOV', 'mandatory', 'Addition of the Government and municipal overlay (SPEC B7).'),
    ('HSF-OV-GOV-02', 'GOV', 'mandatory', 'Addition of the Government and municipal overlay (SPEC B7).'),
    ('HSF-OV-GOV-03', 'GOV', 'mandatory', 'Addition of the Government and municipal overlay (SPEC B7).'),
    ('HSF-OV-GOV-04', 'GOV', 'mandatory', 'Addition of the Government and municipal overlay (SPEC B7).'),
    ('HSF-OV-GOV-05', 'GOV', 'mandatory', 'Addition of the Government and municipal overlay (SPEC B7).'),
    ('HSF-OV-GOV-06', 'GOV', 'mandatory', 'Addition of the Government and municipal overlay (SPEC B7).'),
    ('HSF-OV-HEALTH-01', 'HEALTH', 'mandatory', 'Addition of the Healthcare and laboratories overlay (SPEC B7).'),
    ('HSF-OV-HEALTH-02', 'HEALTH', 'mandatory', 'Addition of the Healthcare and laboratories overlay (SPEC B7).'),
    ('HSF-OV-HEALTH-03', 'HEALTH', 'mandatory', 'Addition of the Healthcare and laboratories overlay (SPEC B7).'),
    ('HSF-OV-HEALTH-04', 'HEALTH', 'mandatory', 'Addition of the Healthcare and laboratories overlay (SPEC B7).'),
    ('HSF-OV-HEALTH-05', 'HEALTH', 'mandatory', 'Addition of the Healthcare and laboratories overlay (SPEC B7).'),
    ('HSF-OV-HEALTH-06', 'HEALTH', 'mandatory', 'Addition of the Healthcare and laboratories overlay (SPEC B7).'),
    ('HSF-OV-HEALTH-07', 'HEALTH', 'mandatory', 'Addition of the Healthcare and laboratories overlay (SPEC B7).'),
    ('HSF-OV-HEALTH-08', 'HEALTH', 'mandatory', 'Addition of the Healthcare and laboratories overlay (SPEC B7).'),
    ('HSF-OV-HOSP-01', 'HOSP', 'mandatory', 'Addition of the Hospitality and food service overlay (SPEC B7).'),
    ('HSF-OV-HOSP-02', 'HOSP', 'mandatory', 'Addition of the Hospitality and food service overlay (SPEC B7).'),
    ('HSF-OV-HOSP-03', 'HOSP', 'mandatory', 'Addition of the Hospitality and food service overlay (SPEC B7).'),
    ('HSF-OV-HOSP-04', 'HOSP', 'mandatory', 'Addition of the Hospitality and food service overlay (SPEC B7).'),
    ('HSF-OV-HOSP-05', 'HOSP', 'mandatory', 'Addition of the Hospitality and food service overlay (SPEC B7).'),
    ('HSF-OV-HOSP-06', 'HOSP', 'mandatory', 'Addition of the Hospitality and food service overlay (SPEC B7).'),
    ('HSF-OV-MANU-01', 'MANU', 'mandatory', 'Addition of the Manufacturing overlay (SPEC B7).'),
    ('HSF-OV-MANU-02', 'MANU', 'mandatory', 'Addition of the Manufacturing overlay (SPEC B7).'),
    ('HSF-OV-MANU-03', 'MANU', 'mandatory', 'Addition of the Manufacturing overlay (SPEC B7).'),
    ('HSF-OV-MANU-04', 'MANU', 'mandatory', 'Addition of the Manufacturing overlay (SPEC B7).'),
    ('HSF-OV-MANU-05', 'MANU', 'mandatory', 'Addition of the Manufacturing overlay (SPEC B7).'),
    ('HSF-OV-MANU-06', 'MANU', 'mandatory', 'Addition of the Manufacturing overlay (SPEC B7).'),
    ('HSF-OV-MINING-01', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-02', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-03', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-04', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-05', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-06', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-07', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-08', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-09', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-10', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-11', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-12', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-13', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-14', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-15', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-MINING-16', 'MINING', 'mandatory', 'Addition of the Mining overlay (SPEC B7).'),
    ('HSF-OV-OFFICE-01', 'OFFICE', 'mandatory', 'Addition of the Office and professional services overlay (SPEC B7).'),
    ('HSF-OV-OFFICE-02', 'OFFICE', 'mandatory', 'Addition of the Office and professional services overlay (SPEC B7).'),
    ('HSF-OV-OFFICE-03', 'OFFICE', 'mandatory', 'Addition of the Office and professional services overlay (SPEC B7).'),
    ('HSF-OV-OFFICE-04', 'OFFICE', 'mandatory', 'Addition of the Office and professional services overlay (SPEC B7).'),
    ('HSF-OV-PETRO-01', 'PETRO', 'mandatory', 'Addition of the Petrochemical and fuel retail overlay (SPEC B7).'),
    ('HSF-OV-PETRO-02', 'PETRO', 'mandatory', 'Addition of the Petrochemical and fuel retail overlay (SPEC B7).'),
    ('HSF-OV-PETRO-03', 'PETRO', 'mandatory', 'Addition of the Petrochemical and fuel retail overlay (SPEC B7).'),
    ('HSF-OV-PETRO-04', 'PETRO', 'mandatory', 'Addition of the Petrochemical and fuel retail overlay (SPEC B7).'),
    ('HSF-OV-PETRO-05', 'PETRO', 'mandatory', 'Addition of the Petrochemical and fuel retail overlay (SPEC B7).'),
    ('HSF-OV-PETRO-06', 'PETRO', 'mandatory', 'Addition of the Petrochemical and fuel retail overlay (SPEC B7).'),
    ('HSF-OV-RETAIL-01', 'RETAIL', 'mandatory', 'Addition of the Retail and wholesale overlay (SPEC B7).'),
    ('HSF-OV-RETAIL-02', 'RETAIL', 'mandatory', 'Addition of the Retail and wholesale overlay (SPEC B7).'),
    ('HSF-OV-RETAIL-03', 'RETAIL', 'mandatory', 'Addition of the Retail and wholesale overlay (SPEC B7).'),
    ('HSF-OV-RETAIL-04', 'RETAIL', 'mandatory', 'Addition of the Retail and wholesale overlay (SPEC B7).'),
    ('HSF-OV-RETAIL-05', 'RETAIL', 'mandatory', 'Addition of the Retail and wholesale overlay (SPEC B7).'),
    ('HSF-OV-SEC-01', 'SEC', 'mandatory', 'Addition of the Security services overlay (SPEC B7).'),
    ('HSF-OV-SEC-02', 'SEC', 'mandatory', 'Addition of the Security services overlay (SPEC B7).'),
    ('HSF-OV-SEC-03', 'SEC', 'mandatory', 'Addition of the Security services overlay (SPEC B7).'),
    ('HSF-OV-SEC-04', 'SEC', 'mandatory', 'Addition of the Security services overlay (SPEC B7).'),
    ('HSF-OV-SEC-05', 'SEC', 'mandatory', 'Addition of the Security services overlay (SPEC B7).'),
    ('HSF-OV-SEC-06', 'SEC', 'mandatory', 'Addition of the Security services overlay (SPEC B7).'),
    ('HSF-OV-SEC-07', 'SEC', 'mandatory', 'Addition of the Security services overlay (SPEC B7).'),
    ('HSF-OV-TEL-01', 'TEL', 'mandatory', 'Addition of the Telecommunications and tower work overlay (SPEC B7).'),
    ('HSF-OV-TEL-02', 'TEL', 'mandatory', 'Addition of the Telecommunications and tower work overlay (SPEC B7).'),
    ('HSF-OV-TEL-03', 'TEL', 'mandatory', 'Addition of the Telecommunications and tower work overlay (SPEC B7).'),
    ('HSF-OV-TEL-04', 'TEL', 'mandatory', 'Addition of the Telecommunications and tower work overlay (SPEC B7).'),
    ('HSF-OV-TRANS-01', 'TRANS', 'mandatory', 'Addition of the Transport and logistics overlay (SPEC B7).'),
    ('HSF-OV-TRANS-02', 'TRANS', 'mandatory', 'Addition of the Transport and logistics overlay (SPEC B7).'),
    ('HSF-OV-TRANS-03', 'TRANS', 'mandatory', 'Addition of the Transport and logistics overlay (SPEC B7).'),
    ('HSF-OV-TRANS-04', 'TRANS', 'mandatory', 'Addition of the Transport and logistics overlay (SPEC B7).'),
    ('HSF-OV-TRANS-05', 'TRANS', 'mandatory', 'Addition of the Transport and logistics overlay (SPEC B7).'),
    ('HSF-OV-TRANS-06', 'TRANS', 'mandatory', 'Addition of the Transport and logistics overlay (SPEC B7).'),
    ('HSF-OV-TRANS-07', 'TRANS', 'mandatory', 'Addition of the Transport and logistics overlay (SPEC B7).'),
    ('HSF-OV-UTIL-01', 'UTIL', 'mandatory', 'Addition of the Utilities and energy overlay (SPEC B7).'),
    ('HSF-OV-UTIL-02', 'UTIL', 'mandatory', 'Addition of the Utilities and energy overlay (SPEC B7).'),
    ('HSF-OV-UTIL-03', 'UTIL', 'mandatory', 'Addition of the Utilities and energy overlay (SPEC B7).'),
    ('HSF-OV-UTIL-04', 'UTIL', 'mandatory', 'Addition of the Utilities and energy overlay (SPEC B7).'),
    ('HSF-OV-UTIL-05', 'UTIL', 'mandatory', 'Addition of the Utilities and energy overlay (SPEC B7).'),
    ('HSF-OV-UTIL-06', 'UTIL', 'mandatory', 'Addition of the Utilities and energy overlay (SPEC B7).'),
    ('HSF-OV-WASTE-01', 'WASTE', 'mandatory', 'Addition of the Waste management overlay (SPEC B7).'),
    ('HSF-OV-WASTE-02', 'WASTE', 'mandatory', 'Addition of the Waste management overlay (SPEC B7).'),
    ('HSF-OV-WASTE-03', 'WASTE', 'mandatory', 'Addition of the Waste management overlay (SPEC B7).'),
    ('HSF-OV-WASTE-04', 'WASTE', 'mandatory', 'Addition of the Waste management overlay (SPEC B7).'),
    ('HSF-OV-WASTE-05', 'WASTE', 'mandatory', 'Addition of the Waste management overlay (SPEC B7).'),
    ('HSF-OV-WASTE-06', 'WASTE', 'mandatory', 'Addition of the Waste management overlay (SPEC B7).'),
    ('HSF-OV-WASTE-07', 'WASTE', 'mandatory', 'Addition of the Waste management overlay (SPEC B7).'),
    ('HSF-OV-WASTE-08', 'WASTE', 'mandatory', 'Addition of the Waste management overlay (SPEC B7).')
       ) as v(code, industry_code, applicability, overlay_note)
  join hsf_element e on e.code = v.code
  join msp_industry i on i.code = v.industry_code
 where not exists (select 1 from hsf_element_industry x
                    where x.element_id = e.id and x.industry_id = i.id and x.subindustry_id is null);

------------------------------------------------------------------------------
-- 049_hsf_consent_uploads_transfer.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | HSF-UPL-01 v1.0.0 | HSF consent, staging uploads and MCO transfer bookkeeping 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 3 (049) and section 1 (constants).
--
-- What this migration does:
--   1. hsf_consent: three separate POPIA consents per company account
--      (document_storage, mco_transfer, authority_to_share), wording version
--      HSF-CONSENT-1.0. A consent row is never deleted; withdrawal stamps
--      withdrawn_at once.
--   2. hsf_upload: one row per file a client drops into the builder. The bytes
--      live in the private Storage bucket hsf-staging (never in the Secrets
--      store, which holds credentials) until the transfer worker has handed them
--      to MyClinicOnline, then the bytes are removed and the row stays, with both
--      SHA 256 fingerprints, for the audit trail.
--   3. hsf_mco_transfer: the append only log of every transfer attempt.
--   4. The hsf-staging bucket (private, 25 MB, the contract mime list) with no
--      storage.objects policy for anon or authenticated: service role only.
--   5. Parameters hsf.upload_max_bytes, hsf.upload_allowed_mime,
--      hsf.mco_transfer_mode and hsf.staging_alert_days (category hsf).
--   6. The functions the web tier and the transfer worker call. Every one is
--      security definer with a fixed search path and is executable by the
--      service role only; the web tier verifies the person's access token first
--      and passes their auth user id.
--   7. Contract 9.1 and 9.5 (Amendment 1): hsf_link_account links a signed in
--      person to the company account of their confirmed email; the worker reads
--      its mode through hsf_transfer_mode, claims work with hsf_transfer_claim,
--      removes staged bytes listed by hsf_transfer_cleanup_queue, and stale
--      registrations are swept by hsf_sweep_stale_uploads. Uploads older than
--      hsf.staging_alert_days show in hsf_staging_alerts for staff. A withdrawn
--      mco_transfer or document_storage consent blocks the account's
--      untransferred uploads; nothing is deleted automatically.
--
-- Nothing here writes file content, a key or a token to msp_audit. The MCO
-- interface contract is pending (HSF-3): no MCO endpoint is named here.

-- 1. Parameter category -------------------------------------------------------------
-- Migration 034 limited msp_env_parameter.category to six values. The contract
-- files the HSF parameters under 'hsf', so the check gains that one value.
do $$
declare
  v_name text;
begin
  select c.conname into v_name
    from pg_constraint c
   where c.conrelid = 'public.msp_env_parameter'::regclass
     and c.contype = 'c'
     and pg_get_constraintdef(c.oid) ilike '%category%';
  if v_name is not null then
    execute format('alter table msp_env_parameter drop constraint %I', v_name);
  end if;
end;
$$;
alter table msp_env_parameter add constraint msp_env_parameter_category_check
  check (category in ('ai','agent','clinical','commercial','retention','integration','hsf'));

insert into msp_env_parameter (key, value, value_type, allowed_values, min_value, max_value, category, description, updated_by) values
  ('hsf.upload_max_bytes', '26214400', 'integer', null, 1, 26214400, 'hsf',
   'Largest file a client may upload into the Health and Safety File builder, in bytes (25 MB). The hsf-staging bucket enforces the same ceiling, so this can be lowered here but not raised past it.',
   'migration_049'),
  ('hsf.upload_allowed_mime', 'application/pdf,image/jpeg,image/png,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/msword,application/vnd.ms-excel,text/csv', 'text', null, null, null, 'hsf',
   'Comma separated file types the builder accepts (PDF, JPEG, PNG, Word, Excel and CSV). Any type added here must also be added to the hsf-staging bucket.',
   'migration_049'),
  ('hsf.mco_transfer_mode', 'hold', 'enum', array['hold','fixture','live'], null, null, 'hsf',
   'How the transfer worker treats staged uploads. hold: keep them in Care Net staging and send nothing. fixture: test adapter only. live: pending the MyClinicOnline interface contract (HSF-3).',
   'migration_049'),
  ('hsf.staging_alert_days', '14', 'integer', null, 1, 365, 'hsf',
   'Days an upload may wait in Care Net staging before staff are alerted to move it to MyClinicOnline.',
   'migration_049')
on conflict (key) do nothing;

-- 2. Tables -------------------------------------------------------------------------

create table hsf_consent (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  auth_user_id uuid not null,
  consent_kind text not null check (consent_kind in ('document_storage','mco_transfer','authority_to_share')),
  granted boolean not null,
  wording_version text not null,
  granted_at timestamptz not null default now(),
  withdrawn_at timestamptz
);
comment on table hsf_consent is 'HSF-UPL-01. Unbundled POPIA consents for the Health and Safety File builder: document_storage (Care Net holds the documents in its secure staging store), mco_transfer (the documents move to MyClinicOnline), authority_to_share (the person may share them for the company). A consent is current when the latest row of its kind is granted and not withdrawn. Rows are never deleted; withdrawal stamps withdrawn_at once.';
create index hsf_consent_account_idx on hsf_consent(client_account_id, consent_kind, granted_at desc);

create table hsf_upload (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  auth_user_id uuid not null,
  file_id uuid references hsf_file(id),
  file_item_id uuid references hsf_file_item(id),
  section_code text references hsf_section(code),
  department_code text not null references hsf_department(code),
  original_name text not null,
  safe_name text not null check (safe_name ~ '^[A-Za-z0-9._]{1,120}$'),
  mime_type text not null,
  size_bytes bigint not null check (size_bytes > 0),
  sha256_client text not null check (sha256_client ~ '^[0-9a-f]{64}$'),
  sha256_server text check (sha256_server ~ '^[0-9a-f]{64}$'),
  storage_bucket text not null default 'hsf-staging',
  storage_path text,
  status text not null default 'awaiting_upload' check (status in
    ('awaiting_upload','uploaded','verified','held','transferring','transferred','staging_deleted','rejected','failed')),
  reject_reason text,
  mco_document_ref text,
  transfer_blocked_reason text,
  transfer_claimed_at timestamptz,
  created_at timestamptz not null default now(),
  uploaded_at timestamptz,
  verified_at timestamptz,
  transferred_at timestamptz,
  staging_deleted_at timestamptz,
  check (status <> 'staging_deleted' or (storage_path is null and staging_deleted_at is not null)),
  check (status not in ('transferred','staging_deleted') or (mco_document_ref is not null and transferred_at is not null))
);
comment on table hsf_upload is 'HSF-UPL-01. One row per document a client drops into the builder. The bytes sit in the private hsf-staging bucket at <client_account_id>/<upload_id>/<safe_name> until they are transferred to MyClinicOnline and removed; the row, with the browser and server SHA 256 fingerprints, stays for the audit trail. Lifecycle: awaiting_upload, uploaded, held, transferred, staging_deleted (or rejected, failed).';
create index hsf_upload_account_idx on hsf_upload(client_account_id, created_at desc);
create index hsf_upload_file_idx on hsf_upload(file_id);
create index hsf_upload_item_idx on hsf_upload(file_item_id);
create index hsf_upload_queue_idx on hsf_upload(status, uploaded_at) where status in ('uploaded','held','transferring');
create index hsf_upload_staged_idx on hsf_upload(status) where storage_path is not null;
comment on column hsf_upload.transfer_blocked_reason is 'Contract 9.5. Set to ''consent withdrawn'' on every untransferred upload of the account when its mco_transfer or document_storage consent is withdrawn. A blocked upload is never claimed for transfer. Nothing is deleted automatically: what happens to the staged bytes is a Director and Information Officer decision (register item).';
comment on column hsf_upload.transfer_claimed_at is 'Contract 9.5. When hsf_transfer_claim last moved the upload to transferring. A transferring upload claimed more than 30 minutes ago is claimed again.';

create table hsf_mco_transfer (
  id bigint generated always as identity primary key,
  upload_id uuid not null references hsf_upload(id),
  mode text not null check (mode in ('hold','fixture','live')),
  outcome text not null check (outcome in ('held','received','hash_mismatch','error')),
  mco_document_ref text,
  mco_receipt_sha256 text check (mco_receipt_sha256 ~ '^[0-9a-f]{64}$'),
  error text,
  created_at timestamptz not null default now()
);
comment on table hsf_mco_transfer is 'HSF-UPL-01. Append only log of every attempt to move a staged upload to MyClinicOnline: the mode, the outcome, the MyClinicOnline reference and receipt fingerprint when received, and a short error text. Never the file content.';
create index hsf_mco_transfer_upload_idx on hsf_mco_transfer(upload_id, created_at);

-- The evidence ledger (047) records the upload it came through.
alter table hsf_evidence
  add constraint hsf_evidence_upload_fk foreign key (upload_id) references hsf_upload(id);

-- 3. Guards -------------------------------------------------------------------------

create or replace function hsf_mco_transfer_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'hsf_mco_transfer is append only';
end;
$$;
create trigger hsf_mco_transfer_append_only
  before update or delete on hsf_mco_transfer
  for each row execute function hsf_mco_transfer_guard();

create or replace function hsf_consent_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'hsf_consent rows are never deleted; withdraw the consent instead';
  end if;
  if (to_jsonb(new) - 'withdrawn_at') is distinct from (to_jsonb(old) - 'withdrawn_at')
     or old.withdrawn_at is not null or new.withdrawn_at is null then
    raise exception 'hsf_consent: only a withdrawal may be recorded, once';
  end if;
  return new;
end;
$$;
create trigger hsf_consent_append_only
  before update or delete on hsf_consent
  for each row execute function hsf_consent_guard();

create or replace function hsf_upload_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'hsf_upload rows are kept for the audit trail and are never deleted';
end;
$$;
create trigger hsf_upload_no_delete
  before delete on hsf_upload
  for each row execute function hsf_upload_guard();

revoke execute on function hsf_mco_transfer_guard() from public, anon, authenticated;
revoke execute on function hsf_consent_guard() from public, anon, authenticated;
revoke execute on function hsf_upload_guard() from public, anon, authenticated;

-- 4. Row Level Security ---------------------------------------------------------------

create or replace function hsf_can_read_account(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select hsf_is_staff()
      or exists (select 1 from msp_client_account a
                  where a.id = p_account_id
                    and auth.uid() is not null
                    and a.auth_user_id = auth.uid());
$$;
revoke execute on function hsf_can_read_account(uuid) from public, anon;
grant execute on function hsf_can_read_account(uuid) to authenticated;
comment on function hsf_can_read_account is 'RLS helper: staff, or the client contact of the account.';

do $$
declare
  t text;
begin
  foreach t in array array['hsf_consent','hsf_upload','hsf_mco_transfer'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;

create policy hsf_consent_read on hsf_consent
  for select to authenticated using (hsf_can_read_account(client_account_id));
create policy hsf_upload_read on hsf_upload
  for select to authenticated using (hsf_can_read_account(client_account_id));
create policy hsf_mco_transfer_read on hsf_mco_transfer
  for select to authenticated using (
    exists (select 1 from hsf_upload u where u.id = upload_id and hsf_can_read_account(u.client_account_id)));

-- 5. Storage bucket -------------------------------------------------------------------
-- Private, encrypted at rest by the platform, 25 MB, the contract mime list. No
-- storage.objects policy is created for this bucket: anon and authenticated
-- cannot read, list or write it; the service role signs one upload URL per
-- registered upload and the transfer worker reads and removes the object.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('hsf-staging', 'hsf-staging', false, 26214400, array[
  'application/pdf','image/jpeg','image/png',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/msword','application/vnd.ms-excel','text/csv'])
on conflict (id) do nothing;

-- 6. Internal helpers (never callable from outside) -------------------------------------

create or replace function hsf_consent_wording_version()
returns text
language sql
immutable
set search_path = public
as $$ select 'HSF-CONSENT-1.0'::text $$;
comment on function hsf_consent_wording_version is 'The current consent wording version (contract section 1). A consent recorded under any other version is refused.';

create or replace function hsf_account_of(p_auth_user uuid)
returns msp_client_account
language sql
stable
security definer
set search_path = public
as $$
  select a.* from msp_client_account a where p_auth_user is not null and a.auth_user_id = p_auth_user limit 1;
$$;
comment on function hsf_account_of is 'The company account whose contact is this auth user, or null.';

-- Contract 9.1. Company accounts are created by msp_client_signon from a typed
-- email, without a sign in, so they carry no auth user. The web tier calls this
-- once per request after it has verified the access token: an account already
-- linked to the person is returned; otherwise the latest account that is not
-- declined, has no auth user yet and whose contact email equals the person's
-- confirmed Supabase email is linked and returned. An unconfirmed email links
-- nothing.
create or replace function hsf_link_account(p_auth_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_email text;
begin
  if p_auth_user is null then
    return null;
  end if;
  -- One link at a time per person, so two parallel requests never race.
  perform pg_advisory_xact_lock(hashtext('hsf_link_account'), hashtext(p_auth_user::text));
  select a.id into v_id from msp_client_account a where a.auth_user_id = p_auth_user;
  if v_id is not null then
    return v_id;
  end if;
  select lower(btrim(u.email)) into v_email
    from auth.users u
   where u.id = p_auth_user and u.email_confirmed_at is not null;
  if coalesce(v_email, '') = '' then
    return null;
  end if;
  select a.id into v_id
    from msp_client_account a
   where lower(btrim(a.contact_email)) = v_email
     and a.auth_user_id is null
     and a.account_kind <> 'declined'
   order by a.created_at desc, a.id desc
   limit 1
   for update;
  if v_id is null then
    return null;
  end if;
  update msp_client_account set auth_user_id = p_auth_user where id = v_id and auth_user_id is null;
  if not found then
    return (select a.id from msp_client_account a where a.auth_user_id = p_auth_user);
  end if;
  insert into msp_audit (actor, event_type, event_detail)
  values (v_email, 'client_auth_linked',
          jsonb_build_object('client_account_id', v_id, 'auth_user_id', p_auth_user));
  return v_id;
end;
$$;
comment on function hsf_link_account is 'Contract 9.1. Returns the company account linked to the auth user, linking on first use the latest non declined account with no auth user whose contact email equals the user''s confirmed email. Null when there is none. Service role only; vercel/lib/auth.js requireUser calls it after verifying the token. Audited as client_auth_linked.';

create or replace function hsf_user_email(p_auth_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select u.email from auth.users u where u.id = p_auth_user),
                  (select a.contact_email from msp_client_account a where a.auth_user_id = p_auth_user limit 1));
$$;
comment on function hsf_user_email is 'The email of the auth user, used as the audit actor and as hsf_evidence.supplied_by.';

create or replace function hsf_consent_current(p_account_id uuid, p_kind text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select c.granted and c.withdrawn_at is null
                     from hsf_consent c
                    where c.client_account_id = p_account_id and c.consent_kind = p_kind
                    order by c.granted_at desc, c.id desc
                    limit 1), false);
$$;
comment on function hsf_consent_current is 'True when the latest consent row of this kind for the account is granted and not withdrawn.';

create or replace function hsf_consent_complete(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select hsf_consent_current(p_account_id, 'document_storage')
     and hsf_consent_current(p_account_id, 'mco_transfer')
     and hsf_consent_current(p_account_id, 'authority_to_share');
$$;

create or replace function hsf_safe_name(p_name text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v text := btrim(coalesce(p_name, ''));
  v_ext text;
  v_base text;
begin
  -- The extension (letters and digits after the last dot) is kept in lower case.
  -- In the rest of the name every run of anything but a letter or a digit becomes
  -- one underscore, so the only dot left is the one before the extension and no
  -- path segment such as .. can survive.
  v_ext := lower(substring(v from '\.([A-Za-z0-9]{1,10})$'));
  v_base := case when v_ext is null then v else left(v, length(v) - length(v_ext) - 1) end;
  v_base := btrim(regexp_replace(v_base, '[^A-Za-z0-9]+', '_', 'g'), '_');
  if v_base = '' then
    v_base := 'document';
  end if;
  if v_ext is null then
    return left(v_base, 120);
  end if;
  return btrim(left(v_base, 120 - length(v_ext) - 1), '_') || '.' || v_ext;
end;
$$;
comment on function hsf_safe_name is 'Storage safe file name: letters, digits, dot and underscore only, at most 120 characters, extension kept.';

do $$
declare
  f text;
begin
  foreach f in array array['hsf_consent_wording_version()','hsf_account_of(uuid)','hsf_user_email(uuid)',
                           'hsf_consent_current(uuid, text)','hsf_consent_complete(uuid)','hsf_safe_name(text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- 7. Consent ----------------------------------------------------------------------------

create or replace function hsf_consent_status(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_ds boolean := false;
  v_mt boolean := false;
  v_as boolean := false;
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is not null then
    v_ds := hsf_consent_current(v_acc.id, 'document_storage');
    v_mt := hsf_consent_current(v_acc.id, 'mco_transfer');
    v_as := hsf_consent_current(v_acc.id, 'authority_to_share');
  end if;
  return jsonb_build_object(
    'client_account_id', v_acc.id,
    'company_name', v_acc.company_name,
    'wording_version', hsf_consent_wording_version(),
    'document_storage', v_ds,
    'mco_transfer', v_mt,
    'authority_to_share', v_as,
    'complete', v_ds and v_mt and v_as);
end;
$$;
comment on function hsf_consent_status is 'Contract 049. The three builder consents of the auth user''s company account. true means the latest row of that kind is granted and not withdrawn; complete means all three.';

create or replace function hsf_record_consent(p_auth_user uuid, p_kinds text[], p_wording_version text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_kind text;
  v_kinds text[];
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before giving consent.';
  end if;
  if p_wording_version is distinct from hsf_consent_wording_version() then
    raise exception 'The consent wording has changed. Please read the current wording (%) and give your consent again.', hsf_consent_wording_version();
  end if;
  select array_agg(distinct k order by k) into v_kinds from unnest(coalesce(p_kinds, '{}'::text[])) k;
  if v_kinds is null then
    raise exception 'Choose at least one consent to record.';
  end if;
  foreach v_kind in array v_kinds loop
    if v_kind is null or v_kind not in ('document_storage','mco_transfer','authority_to_share') then
      raise exception 'Unknown consent kind: %', coalesce(v_kind, 'none');
    end if;
  end loop;
  foreach v_kind in array v_kinds loop
    insert into hsf_consent (client_account_id, auth_user_id, consent_kind, granted, wording_version, granted_at)
    values (v_acc.id, p_auth_user, v_kind, true, p_wording_version, clock_timestamp());
  end loop;
  insert into msp_audit (actor, event_type, event_detail)
  values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_consent_recorded',
          jsonb_build_object('client_account_id', v_acc.id, 'kinds', to_jsonb(v_kinds),
                             'wording_version', p_wording_version));
  return hsf_consent_status(p_auth_user);
end;
$$;
comment on function hsf_record_consent is 'Contract 049. Records one granted row per consent kind under the current wording version. Refuses unknown kinds and any other wording version. Audited.';

create or replace function hsf_withdraw_consent(p_auth_user uuid, p_kind text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_id uuid;
  v_blocked int := 0;
begin
  if p_kind is null or p_kind not in ('document_storage','mco_transfer','authority_to_share') then
    raise exception 'Unknown consent kind: %', coalesce(p_kind, 'none');
  end if;
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'No company account is linked to this sign in.';
  end if;
  select c.id into v_id
    from hsf_consent c
   where c.client_account_id = v_acc.id and c.consent_kind = p_kind
   order by c.granted_at desc, c.id desc
   limit 1;
  if v_id is not null then
    update hsf_consent set withdrawn_at = clock_timestamp()
     where id = v_id and granted and withdrawn_at is null;
    if found then
      -- Contract 9.5: without storage or transfer consent nothing more moves.
      -- Untransferred uploads are blocked from the transfer claim; nothing is
      -- deleted automatically (Director and Information Officer decision).
      if p_kind in ('mco_transfer','document_storage') then
        update hsf_upload
           set transfer_blocked_reason = 'consent withdrawn'
         where client_account_id = v_acc.id
           and transfer_blocked_reason is null
           and status in ('uploaded','verified','held','transferring');
        get diagnostics v_blocked = row_count;
      end if;
      insert into msp_audit (actor, event_type, event_detail)
      values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_consent_withdrawn',
              jsonb_build_object('client_account_id', v_acc.id, 'kind', p_kind, 'blocked_uploads', v_blocked));
    end if;
  end if;
  return hsf_consent_status(p_auth_user);
end;
$$;
comment on function hsf_withdraw_consent is 'Contract 049 and 9.5. Withdraws one consent. New uploads stop at once. Withdrawing mco_transfer or document_storage sets transfer_blocked_reason = ''consent withdrawn'' on the account''s untransferred uploads, which are then never claimed for transfer; a later consent does not lift the block, and nothing is deleted automatically. Audited.';

-- 8. Uploads ----------------------------------------------------------------------------

create or replace function hsf_register_upload(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_file hsf_file;
  v_item_id uuid;
  v_element_section text;
  v_section text := nullif(btrim(coalesce(p ->> 'section_code', '')), '');
  v_dept text := nullif(btrim(coalesce(p ->> 'department_code', '')), '');
  v_element text := nullif(btrim(coalesce(p ->> 'element_code', '')), '');
  v_name text := btrim(coalesce(p ->> 'original_name', ''));
  v_mime text := lower(btrim(coalesce(p ->> 'mime_type', '')));
  v_size_txt text := btrim(coalesce(p ->> 'size_bytes', ''));
  v_size bigint;
  v_sha text := lower(btrim(coalesce(p ->> 'sha256', '')));
  v_max bigint;
  v_allowed text[];
  v_id uuid := gen_random_uuid();
  v_safe text;
  v_path text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'The upload details are missing.';
  end if;
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before uploading documents.';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'This company account cannot upload documents. Please WhatsApp a sales executive.';
  end if;
  if not hsf_consent_complete(v_acc.id) then
    raise exception 'All three consents are needed before any document is uploaded.';
  end if;

  if v_dept is null or not exists (select 1 from hsf_department d where d.code = v_dept) then
    raise exception 'Choose the department this document belongs to.';
  end if;
  if v_section is not null and not exists (select 1 from hsf_section s where s.code = v_section) then
    raise exception 'The File section must be a letter from A to O.';
  end if;

  if nullif(p ->> 'file_id', '') is not null then
    if (p ->> 'file_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'The File is not recognised.';
    end if;
    select f.* into v_file from hsf_file f where f.id = (p ->> 'file_id')::uuid;
    if v_file.id is null or v_file.client_account_id <> v_acc.id then
      raise exception 'The File is not recognised.';
    end if;
  end if;
  if v_element is not null then
    if v_file.id is null then
      raise exception 'An element upload must name the File it belongs to.';
    end if;
    select fi.id, e.section_code into v_item_id, v_element_section
      from hsf_file_item fi
      join hsf_element e on e.id = fi.element_id
     where fi.file_id = v_file.id and e.code = v_element
     order by fi.site_ref nulls first
     limit 1;
    if v_item_id is null then
      raise exception 'That element is not part of this File.';
    end if;
    if v_section is null then
      v_section := v_element_section;
    elsif v_section <> v_element_section then
      raise exception 'That element belongs to Section %, not Section %.', v_element_section, v_section;
    end if;
  end if;

  if v_name = '' or length(v_name) > 255 or v_name ~ '[[:cntrl:]]' then
    raise exception 'The file name must be between 1 and 255 printable characters.';
  end if;
  v_allowed := array(select lower(btrim(x)) from unnest(string_to_array(coalesce(msp_env_get('hsf.upload_allowed_mime'), ''), ',')) x
                      where btrim(x) <> '');
  if v_mime = '' or not (v_mime = any(v_allowed)) then
    raise exception 'That file type is not accepted. Upload a PDF, JPEG, PNG, Word, Excel or CSV file.';
  end if;
  if v_size_txt !~ '^[0-9]{1,15}$' then
    raise exception 'The file size is not valid.';
  end if;
  v_size := v_size_txt::bigint;
  v_max := coalesce(msp_env_get_int('hsf.upload_max_bytes'), 26214400);
  if v_size < 1 or v_size > v_max then
    raise exception 'The file is larger than the % MB limit.', round(v_max / 1048576.0, 1);
  end if;
  if v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'The SHA 256 fingerprint must be 64 hexadecimal characters.';
  end if;

  v_safe := hsf_safe_name(v_name);
  v_path := v_acc.id::text || '/' || v_id::text || '/' || v_safe;

  insert into hsf_upload (id, client_account_id, auth_user_id, file_id, file_item_id, section_code, department_code,
                          original_name, safe_name, mime_type, size_bytes, sha256_client, storage_bucket, storage_path)
  values (v_id, v_acc.id, p_auth_user, v_file.id, v_item_id, v_section, v_dept,
          v_name, v_safe, v_mime, v_size, v_sha, 'hsf-staging', v_path);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_upload_registered',
          jsonb_build_object('upload_id', v_id, 'client_account_id', v_acc.id, 'department_code', v_dept,
                             'section_code', v_section, 'element_code', v_element, 'mime_type', v_mime,
                             'size_bytes', v_size),
          v_file.id);

  return jsonb_build_object('upload_id', v_id, 'bucket', 'hsf-staging', 'path', v_path);
end;
$$;
comment on function hsf_register_upload is 'Contract 049. Registers one upload before the bytes move: consent complete, account not declined, department, section, File and element checked, type and size against hsf.upload_allowed_mime and hsf.upload_max_bytes. Returns the staging bucket and path for the signed upload URL. Audited (never the file name or content).';

create or replace function hsf_mark_uploaded(p_auth_user uuid, p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_email text;
  v_version int;
  v_prev uuid;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null or p_auth_user is null or v_up.auth_user_id <> p_auth_user then
    raise exception 'That upload was not found.';
  end if;
  if v_up.status <> 'awaiting_upload' then
    return jsonb_build_object('upload_id', v_up.id, 'status', v_up.status);
  end if;
  v_email := coalesce(hsf_user_email(p_auth_user), 'client');

  -- A consent withdrawn between registration and completion stops the upload.
  if not hsf_consent_complete(v_up.client_account_id) then
    update hsf_upload
       set status = 'rejected', reject_reason = 'Consent was withdrawn before the upload completed.'
     where id = v_up.id;
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values (v_email, 'hsf_upload_rejected',
            jsonb_build_object('upload_id', v_up.id, 'reason', 'consent_withdrawn'), v_up.file_id);
    return jsonb_build_object('upload_id', v_up.id, 'status', 'rejected');
  end if;

  update hsf_upload set status = 'uploaded', uploaded_at = now() where id = v_up.id;

  if v_up.file_item_id is not null then
    -- Serialise completes on one File item, so two uploads never pick the same
    -- evidence version (the second waits, then reads the committed maximum).
    perform 1 from hsf_file_item where id = v_up.file_item_id for update;
    select coalesce(max(e.version), 0) + 1 into v_version from hsf_evidence e where e.file_item_id = v_up.file_item_id;
    select e.id into v_prev from hsf_evidence e
     where e.file_item_id = v_up.file_item_id order by e.version desc limit 1;
    insert into hsf_evidence (file_item_id, version, supersedes_id, source, storage_path, sha256, supplied_by, upload_id)
    values (v_up.file_item_id, v_version, v_prev, 'client_upload', v_up.storage_path, v_up.sha256_client, v_email, v_up.id);
    update hsf_file_item set status = 'uploaded', reason = null where id = v_up.file_item_id;
    -- Keeps hsf_file.compliance_pct current and audits the change (migration 051).
    perform hsf_compute_compliance(v_up.file_id);
  end if;

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (v_email, 'hsf_upload_completed',
          jsonb_build_object('upload_id', v_up.id, 'file_item_id', v_up.file_item_id,
                             'evidence_version', v_version, 'sha256', v_up.sha256_client),
          v_up.file_id);

  return jsonb_build_object('upload_id', v_up.id, 'status', 'uploaded');
end;
$$;
comment on function hsf_mark_uploaded is 'Contract 049 and 9.5. awaiting_upload to uploaded, by the uploading person only. For an element upload it locks the File item, appends the hsf_evidence row (version n + 1, source client_upload, the browser hash), sets the item to uploaded and recomputes the compliance figure. A consent withdrawn in between rejects the upload instead. Audited.';

create or replace function hsf_my_uploads(p_auth_user uuid, p_file_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'upload_id', u.id,
           'file_id', u.file_id,
           'original_name', u.original_name,
           'department_code', u.department_code,
           'section_code', u.section_code,
           'element_code', e.code,
           'size_bytes', u.size_bytes,
           'mime_type', u.mime_type,
           'status', u.status,
           'reject_reason', u.reject_reason,
           'transfer_blocked_reason', u.transfer_blocked_reason,
           'created_at', u.created_at,
           'uploaded_at', u.uploaded_at,
           'transferred_at', u.transferred_at,
           'staging_deleted_at', u.staging_deleted_at,
           'mco_document_ref', u.mco_document_ref)
         order by u.created_at desc, u.id), '[]'::jsonb)
    from hsf_upload u
    join msp_client_account a on a.id = u.client_account_id
    left join hsf_file_item fi on fi.id = u.file_item_id
    left join hsf_element e on e.id = fi.element_id
   where p_auth_user is not null
     and a.auth_user_id = p_auth_user
     and (p_file_id is null or u.file_id = p_file_id);
$$;
comment on function hsf_my_uploads is 'Contract 049. The uploads of the auth user''s company account, newest first, optionally for one File.';

-- 9. Transfer worker ---------------------------------------------------------------------

create or replace function hsf_transfer_queue(p_limit int)
returns setof hsf_upload
language sql
stable
security definer
set search_path = public
as $$
  select u.*
    from hsf_upload u
   where u.status in ('uploaded','held')
     and u.storage_path is not null
     and u.transfer_blocked_reason is null
     and hsf_consent_current(u.client_account_id, 'mco_transfer')
     and hsf_consent_current(u.client_account_id, 'document_storage')
   order by u.uploaded_at nulls last, u.created_at, u.id
   limit greatest(1, least(coalesce(p_limit, 10), 100));
$$;
comment on function hsf_transfer_queue is 'Contract 049. A read only listing of uploads waiting for MyClinicOnline (uploaded or held), oldest first, at most 100; blocked uploads and accounts without mco_transfer and document_storage consent are skipped. The worker no longer reads it: it claims work with hsf_transfer_claim (contract 9.5).';

create or replace function hsf_transfer_mode()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case when v in ('hold','fixture','live') then v else 'hold' end
    from (select msp_env_get('hsf.mco_transfer_mode') as v) x;
$$;
comment on function hsf_transfer_mode is 'Contract 9.5. The transfer mode from hsf.mco_transfer_mode: hold, fixture or live; anything else reads as hold. Service role only; the worker calls this instead of msp_env_get.';

create or replace function hsf_transfer_claim(p_limit int)
returns setof hsf_upload
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text := hsf_transfer_mode();
  v_limit int := greatest(1, least(coalesce(p_limit, 10), 100));
begin
  if v_mode = 'hold' then
    -- Hold: only fresh uploads; the worker records each as held and sends nothing.
    return query
      select u.*
        from hsf_upload u
       where u.status = 'uploaded'
         and u.storage_path is not null
         and u.transfer_blocked_reason is null
         and hsf_consent_current(u.client_account_id, 'mco_transfer')
         and hsf_consent_current(u.client_account_id, 'document_storage')
       order by u.uploaded_at nulls last, u.created_at, u.id
       limit v_limit
       for update of u skip locked;
    return;
  end if;
  -- Fixture or live: uploaded and held rows, and transferring rows whose claim
  -- is more than 30 minutes old (a worker that stopped part way). Rows another
  -- worker has locked are skipped; the claimed rows move to transferring.
  return query
    with c as (
      select u.id
        from hsf_upload u
       where u.storage_path is not null
         and u.transfer_blocked_reason is null
         and (u.status in ('uploaded','held')
              or (u.status = 'transferring'
                  and (u.transfer_claimed_at is null or u.transfer_claimed_at < now() - interval '30 minutes')))
         and hsf_consent_current(u.client_account_id, 'mco_transfer')
         and hsf_consent_current(u.client_account_id, 'document_storage')
       order by u.uploaded_at nulls last, u.created_at, u.id
       limit v_limit
       for update of u skip locked
    ), claimed as (
      update hsf_upload u
         set status = 'transferring', transfer_claimed_at = now()
        from c
       where u.id = c.id
      returning u.*
    )
    select * from claimed order by uploaded_at nulls last, created_at, id;
end;
$$;
comment on function hsf_transfer_claim is 'Contract 9.5. The worker''s claim, oldest first, at most 100. Mode hold: uploaded rows only (the worker records them held). Mode fixture or live: uploaded and held rows plus transferring rows claimed more than 30 minutes ago, locked with for update skip locked and moved to transferring. Blocked uploads and accounts without mco_transfer and document_storage consent are never returned.';

create or replace function hsf_transfer_record(
  p_upload_id uuid, p_mode text, p_outcome text, p_server_sha256 text,
  p_mco_ref text, p_receipt_sha256 text, p_error text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_server text := nullif(lower(btrim(coalesce(p_server_sha256, ''))), '');
  v_receipt text := nullif(lower(btrim(coalesce(p_receipt_sha256, ''))), '');
  v_ref text := nullif(btrim(coalesce(p_mco_ref, '')), '');
  v_error text := nullif(left(btrim(coalesce(p_error, '')), 500), '');
  v_outcome text := p_outcome;
  v_status text;
  v_revoked int := 0;
begin
  if p_mode is null or p_mode not in ('hold','fixture','live') then
    raise exception 'Unknown transfer mode: %', coalesce(p_mode, 'none');
  end if;
  if p_outcome is null or p_outcome not in ('held','received','hash_mismatch','error') then
    raise exception 'Unknown transfer outcome: %', coalesce(p_outcome, 'none');
  end if;
  if v_server is not null and v_server !~ '^[0-9a-f]{64}$' then
    raise exception 'The server fingerprint must be 64 hexadecimal characters.';
  end if;
  if v_receipt is not null and v_receipt !~ '^[0-9a-f]{64}$' then
    raise exception 'The receipt fingerprint must be 64 hexadecimal characters.';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'The MyClinicOnline reference is too long.';
  end if;

  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.';
  end if;
  if v_up.status not in ('uploaded','held','transferring') then
    raise exception 'The upload is not waiting for transfer (status %).', v_up.status;
  end if;

  if p_outcome = 'received' then
    if p_mode = 'hold' then
      raise exception 'A held transfer cannot be recorded as received.';
    end if;
    if v_ref is null then
      raise exception 'A received transfer needs the MyClinicOnline reference.';
    end if;
    if v_server is null or v_receipt is null
       or v_server <> v_up.sha256_client or v_receipt <> v_up.sha256_client then
      -- The database runs the same check as the worker: without three matching
      -- fingerprints the transfer is a mismatch and the staging copy is kept.
      v_outcome := 'hash_mismatch';
      v_error := coalesce(v_error, 'Reported as received, but the browser, server and receipt fingerprints do not all match.');
    end if;
  end if;

  if v_outcome = 'held' then
    v_status := 'held';
    update hsf_upload
       set status = 'held', sha256_server = coalesce(v_server, sha256_server), transfer_claimed_at = null
     where id = v_up.id;
  elsif v_outcome = 'received' then
    v_status := 'transferred';
    update hsf_upload
       set status = 'transferred', sha256_server = v_server, mco_document_ref = v_ref,
           transferred_at = now(), verified_at = coalesce(verified_at, now()), transfer_claimed_at = null
     where id = v_up.id;
    update hsf_evidence
       set mco_document_ref = v_ref, transferred_at = now()
     where upload_id = v_up.id and mco_document_ref is null and transferred_at is null;
  elsif v_outcome = 'hash_mismatch' then
    v_status := 'failed';
    update hsf_upload
       set status = 'failed', sha256_server = coalesce(v_server, sha256_server),
           reject_reason = coalesce(v_error, 'The fingerprints do not match.'), transfer_claimed_at = null
     where id = v_up.id;
    -- Bytes that failed the fingerprint check are not evidence (contract 9.5):
    -- revoke the evidence row written at completion, return the item to
    -- outstanding when no other unrevoked evidence holds it, and recompute.
    if v_up.file_item_id is not null then
      perform 1 from hsf_file_item where id = v_up.file_item_id for update;
    end if;
    update hsf_evidence set revoked_at = now()
     where upload_id = v_up.id and revoked_at is null;
    get diagnostics v_revoked = row_count;
    if v_up.file_item_id is not null then
      update hsf_file_item fi
         set status = 'outstanding', reason = null
       where fi.id = v_up.file_item_id
         and fi.status = 'uploaded'
         and not exists (select 1 from hsf_evidence e where e.file_item_id = fi.id and e.revoked_at is null);
    end if;
    if v_up.file_id is not null then
      perform hsf_compute_compliance(v_up.file_id);
    end if;
  else
    -- An error returns the upload to uploaded, to be claimed again (contract 9.5).
    v_status := 'uploaded';
    update hsf_upload set status = 'uploaded', transfer_claimed_at = null where id = v_up.id;
  end if;

  insert into hsf_mco_transfer (upload_id, mode, outcome, mco_document_ref, mco_receipt_sha256, error)
  values (v_up.id, p_mode, v_outcome, v_ref, v_receipt, v_error);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values ('hsf-mco-transfer', 'hsf_transfer_recorded',
          jsonb_build_object('upload_id', v_up.id, 'mode', p_mode, 'reported_outcome', p_outcome,
                             'outcome', v_outcome, 'status', v_status, 'mco_document_ref', v_ref,
                             'evidence_revoked', v_revoked),
          v_up.file_id);

  return jsonb_build_object('upload_id', v_up.id, 'outcome', v_outcome, 'status', v_status,
                            'mco_document_ref', case when v_status = 'transferred' then v_ref end);
end;
$$;
comment on function hsf_transfer_record is 'Contract 049 and 9.5. Accepts an upload that is uploaded, held or transferring. Appends hsf_mco_transfer and moves the upload: held to held; received with server, browser and receipt fingerprints equal to transferred (and the matching hsf_evidence row gains its MyClinicOnline fields); a mismatch to failed with the reason, revoking the upload''s evidence row, returning the File item to outstanding when no other unrevoked evidence holds it, and recomputing the compliance figure; an error back to uploaded. Audited.';

create or replace function hsf_mark_staging_deleted(p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_status text;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.';
  end if;
  if v_up.status not in ('transferred','failed','rejected') then
    raise exception 'Only a transferred, failed or rejected upload can be removed from staging (status %).', v_up.status;
  end if;
  if v_up.storage_path is null then
    raise exception 'The staging copy of this upload has already been removed.';
  end if;
  v_status := case when v_up.status = 'transferred' then 'staging_deleted' else v_up.status end;
  update hsf_upload
     set status = v_status, storage_path = null, staging_deleted_at = now()
   where id = v_up.id;
  update hsf_evidence
     set staging_deleted_at = now(), storage_path = null
   where upload_id = v_up.id and staging_deleted_at is null;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values ('hsf-mco-transfer', 'hsf_staging_deleted',
          jsonb_build_object('upload_id', v_up.id, 'status', v_status, 'mco_document_ref', v_up.mco_document_ref),
          v_up.file_id);
  return jsonb_build_object('upload_id', v_up.id, 'status', v_status);
end;
$$;
comment on function hsf_mark_staging_deleted is 'Contract 049 and 9.5. After the worker has removed the bytes through the Storage API: transferred becomes staging_deleted; failed and rejected keep their status. storage_path is cleared and staging_deleted_at set on the upload and its evidence row. The row and both fingerprints stay. Audited.';

create or replace function hsf_transfer_cleanup_queue(p_limit int)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('upload_id', q.id, 'storage_path', q.storage_path, 'reason', q.status)
                            order by q.since, q.id), '[]'::jsonb)
    from (select u.id, u.storage_path, u.status,
                 coalesce(u.transferred_at, u.uploaded_at, u.created_at) as since
            from hsf_upload u
           where u.storage_path is not null
             and u.status in ('transferred','failed','rejected')
             -- After a consent withdrawal nothing is deleted automatically: a
             -- blocked upload's bytes wait for the Director and Information
             -- Officer decision.
             and u.transfer_blocked_reason is null
           order by coalesce(u.transferred_at, u.uploaded_at, u.created_at), u.id
           limit greatest(1, least(coalesce(p_limit, 10), 100))) q;
$$;
comment on function hsf_transfer_cleanup_queue is 'Contract 9.5. Staged bytes to remove, oldest first, at most 100: {upload_id, storage_path, reason} where reason is the status, transferred (the copy at MyClinicOnline is confirmed), failed or rejected. Uploads blocked by a consent withdrawal are left out (nothing is deleted automatically). The worker deletes the object through the Storage API and then calls hsf_mark_staging_deleted.';

create or replace function hsf_sweep_stale_uploads(p_hours int default 24)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hours int := coalesce(p_hours, 24);
  v_n int;
begin
  if v_hours < 1 or v_hours > 8760 then
    raise exception 'The sweep age must be between 1 and 8760 hours.';
  end if;
  update hsf_upload
     set status = 'failed', reject_reason = 'The upload was not completed.'
   where status = 'awaiting_upload'
     and created_at < now() - make_interval(hours => v_hours);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into msp_audit (actor, event_type, event_detail)
    values ('hsf-mco-transfer', 'hsf_uploads_swept', jsonb_build_object('failed', v_n, 'older_than_hours', v_hours));
  end if;
  return v_n;
end;
$$;
comment on function hsf_sweep_stale_uploads is 'Contract 9.5. Registrations still awaiting upload after p_hours (default 24) become failed with the reason ''The upload was not completed.''. Their staging path then appears in hsf_transfer_cleanup_queue, so any bytes that did arrive are removed. Audited when anything moves.';

-- Staging alerts (contract 9.5): uploads still holding bytes in Care Net staging
-- longer than hsf.staging_alert_days. Staff read the view (it filters on the
-- forge staff roles, so a client or anon sees nothing); the service role reads
-- hsf_staging_alerts_list(). The two carry the same rows.
create or replace view hsf_staging_alerts as
select u.id as upload_id,
       u.client_account_id,
       a.company_name,
       u.file_id,
       u.status,
       u.department_code,
       u.section_code,
       u.size_bytes,
       coalesce(u.uploaded_at, u.created_at) as staged_since,
       floor(extract(epoch from now() - coalesce(u.uploaded_at, u.created_at)) / 86400)::int as days_in_staging,
       u.transfer_blocked_reason
  from hsf_upload u
  join msp_client_account a on a.id = u.client_account_id
 where u.storage_path is not null
   and u.status <> 'awaiting_upload'
   and coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days =>
         coalesce((select p.value::int from msp_env_parameter p where p.key = 'hsf.staging_alert_days'), 14))
   and hsf_is_staff();
comment on view hsf_staging_alerts is 'Contract 9.5. Uploads holding bytes in the hsf-staging bucket for longer than hsf.staging_alert_days. Staff only (forge_admin, forge_omp, forge_safety_reviewer); nobody else sees a row. No file names.';
revoke all on hsf_staging_alerts from public, anon, authenticated;
grant select on hsf_staging_alerts to authenticated;

create or replace function hsf_staging_alerts_list()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'upload_id', u.id, 'client_account_id', u.client_account_id, 'company_name', a.company_name,
           'file_id', u.file_id, 'status', u.status, 'department_code', u.department_code,
           'section_code', u.section_code, 'size_bytes', u.size_bytes,
           'staged_since', coalesce(u.uploaded_at, u.created_at),
           'days_in_staging', floor(extract(epoch from now() - coalesce(u.uploaded_at, u.created_at)) / 86400)::int,
           'transfer_blocked_reason', u.transfer_blocked_reason)
         order by coalesce(u.uploaded_at, u.created_at), u.id), '[]'::jsonb)
    from hsf_upload u
    join msp_client_account a on a.id = u.client_account_id
   where u.storage_path is not null
     and u.status <> 'awaiting_upload'
     and coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days =>
           coalesce(msp_env_get_int('hsf.staging_alert_days'), 14));
$$;
comment on function hsf_staging_alerts_list is 'Contract 9.5. The rows of hsf_staging_alerts for the service role (scheduled alerts), oldest first.';

-- 10. Execute rights: service role only ------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'hsf_consent_status(uuid)',
    'hsf_record_consent(uuid, text[], text)',
    'hsf_withdraw_consent(uuid, text)',
    'hsf_register_upload(uuid, jsonb)',
    'hsf_mark_uploaded(uuid, uuid)',
    'hsf_my_uploads(uuid, uuid)',
    'hsf_transfer_queue(int)',
    'hsf_transfer_record(uuid, text, text, text, text, text, text)',
    'hsf_mark_staging_deleted(uuid)',
    'hsf_link_account(uuid)',
    'hsf_transfer_mode()',
    'hsf_transfer_claim(int)',
    'hsf_transfer_cleanup_queue(int)',
    'hsf_sweep_stale_uploads(int)',
    'hsf_staging_alerts_list()'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

------------------------------------------------------------------------------
-- 050_kernel_api.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | KRN-API-01 v1.0.0 | Cognitive Kernel read API for approved clients 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 3 (050) and section 7. The database side
-- of GET /api/kernel (vercel/api/kernel.js), which the Grok bot and other
-- approved servers call with a cnck_ key.
--
-- What this migration does:
--   1. msp_instrument_currency_hold: a hold removes an instrument from citation
--      even while its kernel row still reads verified. A hold only ever tightens.
--      Seeded for the NIHL Regulations, 2003 and the Environmental Regulations
--      for Workplaces, 1987 wherever those rows are still verified (HSF-7), and
--      for the Asbestos Abatement Regulations, 2020 (HSF-9, contract 9.4).
--   2. kernel_citable_instrument: the one definition of "citable" for the
--      register (verified through the three gates, not superseded, not held).
--      Public read. The public register, industry profile and framework
--      statistics views are redefined here so that a held instrument leaves
--      them too (contract 9.4).
--   3. hsf_element_citable (contract 9.3): the one definition of an instrument
--      a File element may cite, used by hsf_public_element_library,
--      hsf_file_detail, kernel_api_elements and the release gate.
--      hsf_public_element_library (SPEC B4.8): the element library with those
--      bases only and every other named instrument still awaiting
--      verification. Public read.
--   4. msp_api_client and msp_api_call_log: keys are stored as a SHA 256 hash
--      only; the log holds the client, the resource, the status and the time,
--      never a request body, a search term or an IP address.
--   5. Key issue and revoke (service role or forge_admin), authorisation with an
--      hourly limit (service role), and the kernel_api_* read functions (service
--      role). The read functions touch kernel and library tables only, never
--      client, engagement, upload, consent or audit data.

-- 1. Currency holds -------------------------------------------------------------------

create table msp_instrument_currency_hold (
  instrument_id uuid primary key references msp_legal_instrument(id),
  reason text not null,
  held_by text not null,
  held_on date not null default current_date
);
comment on table msp_instrument_currency_hold is 'KRN-API-01. Instruments withheld from citation although their kernel row may still read verified, for example after a repeal the live kernel has not yet recorded. A hold only ever tightens: it removes an instrument from kernel_citable_instrument and from every API and File basis.';

alter table msp_instrument_currency_hold enable row level security;
revoke all on msp_instrument_currency_hold from public, anon, authenticated;
grant select on msp_instrument_currency_hold to authenticated;
grant all on msp_instrument_currency_hold to service_role;
create policy msp_instrument_currency_hold_read on msp_instrument_currency_hold
  for select to authenticated using (msp_any_forge_role() or hsf_is_staff());

with seeded as (
  insert into msp_instrument_currency_hold (instrument_id, reason, held_by)
  select li.id, v.reason, 'migration_050'
    from (values
      ('NIHL Regulations, 2003',
       'Repealed with effect from 06/09/2026 by the Noise Exposure Regulations, 2024, as recorded in the CNC OHS Industry Kernel (23/09/2026) and in migration 042. Held from citation until the kernel row is superseded (HSF-7).'),
      ('Environmental Regulations for Workplaces, 1987',
       'Repealed with effect from 06/09/2026 by the Physical Agents Regulations, 2024, as recorded in the CNC OHS Industry Kernel (23/09/2026) and in migration 042. Held from citation until the kernel row is superseded (HSF-7).'),
      ('Asbestos Abatement Regulations, 2020',
       'The amendment notice number conflicts: GN R.2092 against GN R.11435. Held from citation until the amendment reference is verified (register HSF-9).')
    ) as v(short_name, reason)
    join msp_legal_instrument li on li.short_name = v.short_name
   where li.status = 'verified'
  on conflict (instrument_id) do nothing
  returning instrument_id, reason
)
insert into msp_audit (actor, event_type, event_detail)
select 'migration_050', 'kernel_currency_hold',
       jsonb_build_object('instruments', jsonb_agg(li.short_name order by li.short_name),
                          'holds', jsonb_agg(jsonb_build_object('short_name', li.short_name, 'reason', s.reason)
                                             order by li.short_name))
  from seeded s join msp_legal_instrument li on li.id = s.instrument_id
having count(*) > 0;

-- 2. Citable instruments -------------------------------------------------------------------

create or replace function kernel_instrument_citable(p_instrument_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from msp_legal_instrument li
                  where li.id = p_instrument_id
                    and li.status = 'verified'
                    and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id));
$$;
comment on function kernel_instrument_citable is 'The single definition of citable: status verified (gates a, b and c passed; a superseded row is never verified) and no currency hold.';

create or replace view kernel_citable_instrument as
select li.short_name,
       li.full_citation,
       li.instrument_type,
       li.gazette_reference,
       li.effective_date,
       li.verified_on,
       li.review_due,
       li.scope,
       (select coalesce(json_agg(json_build_object('code', i.code, 'name', i.name) order by i.code), '[]'::json)
          from msp_industry_instrument ii
          join msp_industry i on i.id = ii.industry_id
         where ii.instrument_id = li.id) as industries
  from msp_legal_instrument li
 where li.status = 'verified'
   and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id)
 order by li.short_name;
comment on view kernel_citable_instrument is 'KRN-API-01. Instruments a page or the kernel API may name as a basis: verified three ways, in force, not superseded, not held. A File element cites through hsf_element_citable, which also needs scope safety or both and a verified provision (contract 9.3). Public read on purpose; it carries only what Care Net publishes.';
grant select on kernel_citable_instrument to anon, authenticated;

-- Contract 9.4: the published views leave out held instruments too. Same column
-- lists as migrations 047 (register) and 033 (industry profile, framework
-- statistics); only the hold predicate is added. The predicate is written inline
-- because a view's function calls are checked against the caller, and anon may
-- not execute kernel_instrument_citable. The views run with the owner's rights,
-- so anon needs no grant on msp_instrument_currency_hold.
create or replace view msp_public_instrument_register as
select li.short_name,
       li.full_citation,
       li.instrument_type,
       li.gazette_reference,
       li.effective_date,
       li.amendment_history,
       li.verified_on,
       li.review_due,
       (select coalesce(json_agg(json_build_object('code', i.code, 'name', i.name) order by i.name), '[]'::json)
          from msp_industry_instrument ii
          join msp_industry i on i.id = ii.industry_id
         where ii.instrument_id = li.id) as industries,
       li.scope
  from msp_legal_instrument li
 where li.status = 'verified'
   and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id)
 order by li.short_name;
comment on view msp_public_instrument_register is
  'The legislation register as published on the website: verified instruments that are not under a currency hold, with full citation, the industries each applies to and the scope. Anonymous read.';
grant select on msp_public_instrument_register to anon, authenticated;

create or replace view msp_public_industry_profile as
select
  i.code,
  i.name,
  i.regulatory_regime as regime,
  (select count(*) from msp_subindustry s where s.industry_id = i.id and s.selectable) as subindustry_count,
  (select count(*) from msp_job_role r
     join msp_subindustry s on s.id = r.subindustry_id
    where s.industry_id = i.id) as role_count,
  (select coalesce(json_agg(json_build_object('name', s.name, 'roles',
            (select coalesce(json_agg(r.title order by r.title), '[]'::json)
               from msp_job_role r where r.subindustry_id = s.id)) order by s.name), '[]'::json)
     from msp_subindustry s where s.industry_id = i.id and s.selectable) as subindustries,
  (select coalesce(json_agg(json_build_object('name', li.short_name, 'note', ii.applicability_note)
            order by li.short_name), '[]'::json)
     from msp_industry_instrument ii
     join msp_legal_instrument li on li.id = ii.instrument_id
    where ii.industry_id = i.id and li.status = 'verified'
      and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id)) as instruments,
  (select coalesce(json_agg(distinct h.name), '[]'::json)
     from msp_job_hazard jh
     join msp_job_role r on r.id = jh.job_role_id
     join msp_subindustry s on s.id = r.subindustry_id
     join msp_hazard h on h.id = jh.hazard_id
    where s.industry_id = i.id) as hazards,
  (select coalesce(json_agg(distinct tp.test_name), '[]'::json)
     from msp_job_hazard jh
     join msp_job_role r on r.id = jh.job_role_id
     join msp_subindustry s on s.id = r.subindustry_id
     join msp_test_protocol tp on tp.hazard_id = jh.hazard_id
    where s.industry_id = i.id) as protocols
from msp_industry i;
comment on view msp_public_industry_profile is
  'Public marketing surface for the website industry pages. Aggregate, non clinical, no client data; instruments are verified and not under a currency hold. Readable by anon on purpose.';
grant select on msp_public_industry_profile to anon, authenticated;

create or replace view msp_public_framework_stats as
select
  (select semver from msp_kernel_version order by released_on desc, semver desc limit 1) as version,
  (select count(*) from msp_legal_instrument li
    where li.status = 'verified'
      and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id)) as instruments,
  (select count(*) from msp_industry) as industries,
  (select count(*) from msp_subindustry where selectable) as subindustries,
  (select count(*) from msp_job_role) as roles,
  (select count(*) from msp_test_protocol) as protocols;
comment on view msp_public_framework_stats is
  'Public marketing statistics for the website. Aggregate only; the instrument count leaves out held instruments. Readable by anon on purpose.';
grant select on msp_public_framework_stats to anon, authenticated;

-- 3. File citations and the public element library (contract 9.3, SPEC B4.8) -------------------

create or replace function hsf_element_citable(p_element_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(distinct li.short_name order by li.short_name), '[]'::jsonb)
    from hsf_element_instrument ei
    join msp_legal_instrument li on li.id = ei.instrument_id
   where ei.element_id = p_element_id
     and li.status = 'verified'
     and li.scope in ('safety','both')
     and lower(btrim(ei.provision)) <> 'awaiting verification'
     and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id);
$$;
comment on function hsf_element_citable is 'Contract 9.3. The one definition of what a Health and Safety File element may cite: instruments that are verified (never superseded), not under a currency hold, of scope safety or both, and linked with a provision pinned past ''awaiting verification''. Returns the short names as a json array. Used by hsf_public_element_library, hsf_file_detail, kernel_api_elements and hsf_release_gate. Until the Phase 2 re verification every element shows its instruments as awaiting verification, which is the truthful state.';
-- The public views call it, and a view's function calls are checked against the
-- caller, so anon and authenticated may execute it. It returns published short
-- names only.
revoke execute on function hsf_element_citable(uuid) from public;
grant execute on function hsf_element_citable(uuid) to anon, authenticated, service_role;

create or replace view hsf_public_element_library as
select e.section_code,
       s.name as section_name,
       e.code,
       e.name,
       e.duty,
       e.universal,
       c.citable::json as citable,
       (select coalesce(json_agg(distinct li.short_name order by li.short_name), '[]'::json)
          from hsf_element_instrument ei
          join msp_legal_instrument li on li.id = ei.instrument_id
         where ei.element_id = e.id
           and li.status in ('pending','verified')
           and not (c.citable ? li.short_name)) as awaiting
  from hsf_element e
  join hsf_section s on s.code = e.section_code
  cross join lateral (select hsf_element_citable(e.id) as citable) c
 where e.status = 'active'
 order by s.ordinal, e.code;
comment on view hsf_public_element_library is 'SPEC B4.8 and contract 9.3. The Health and Safety File element library: section, name, duty, the instruments the element may cite (hsf_element_citable) and every other instrument named for it that is still awaiting verification (never to be cited as a basis). No client data. Public read on purpose.';
grant select on hsf_public_element_library to anon, authenticated;

-- 4. API clients and the call log -------------------------------------------------------------

create table msp_api_client (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 120),
  owner text not null check (length(btrim(owner)) between 1 and 120),
  key_prefix text not null,
  key_hash text unique not null check (key_hash ~ '^[0-9a-f]{64}$'),
  scopes text[] not null default '{kernel.read}',
  active boolean not null default true,
  hourly_limit int not null default 600 check (hourly_limit between 1 and 100000),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
comment on table msp_api_client is 'KRN-API-01. Approved servers that may read the kernel API. Only the SHA 256 hash of a key is kept; the key itself is shown once at issue and never stored. key_prefix is the first characters of the key so staff can tell keys apart.';

create table msp_api_call_log (
  id bigint generated always as identity primary key,
  client_id uuid references msp_api_client(id),
  resource text,
  status int not null,
  created_at timestamptz not null default now()
);
comment on table msp_api_call_log is 'KRN-API-01. Append only log of every authorisation: the client (null for an unknown key), the resource, the status and the time. No request bodies, no search words, no IP addresses.';
create index msp_api_call_log_client_idx on msp_api_call_log(client_id, created_at desc);

create or replace function msp_api_call_log_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'msp_api_call_log is append only';
end;
$$;
create trigger msp_api_call_log_append_only
  before update or delete on msp_api_call_log
  for each row execute function msp_api_call_log_guard();
revoke execute on function msp_api_call_log_guard() from public, anon, authenticated;

alter table msp_api_client enable row level security;
alter table msp_api_call_log enable row level security;
revoke all on msp_api_client from public, anon, authenticated;
revoke all on msp_api_call_log from public, anon, authenticated;
grant all on msp_api_client to service_role;
grant all on msp_api_call_log to service_role;

-- 5. Issue, revoke, authorise -------------------------------------------------------------------

create or replace function msp_api_client_issue(p_name text, p_owner text, p_scopes text[] default '{kernel.read}')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_id uuid;
  v_scopes text[];
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.role(), 'unknown');
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'Issuing a kernel API key requires the forge_admin role.';
  end if;
  if length(btrim(coalesce(p_name, ''))) not between 1 and 120 or length(btrim(coalesce(p_owner, ''))) not between 1 and 120 then
    raise exception 'A key needs a name and an owner of 1 to 120 characters.';
  end if;
  select array_agg(distinct s order by s) into v_scopes from unnest(coalesce(p_scopes, '{kernel.read}'::text[])) s;
  if v_scopes is null or not (v_scopes <@ array['kernel.read']) then
    raise exception 'Unknown scope. The only scope is kernel.read.';
  end if;

  v_key := 'cnck_' || encode(extensions.gen_random_bytes(32), 'hex');
  insert into msp_api_client (name, owner, key_prefix, key_hash, scopes)
  values (btrim(p_name), btrim(p_owner), left(v_key, 12), encode(extensions.digest(v_key, 'sha256'), 'hex'), v_scopes)
  returning id into v_id;

  insert into msp_audit (actor, event_type, event_detail)
  values (v_actor, 'api_client_issued',
          jsonb_build_object('client_id', v_id, 'name', btrim(p_name), 'owner', btrim(p_owner), 'scopes', to_jsonb(v_scopes)));

  -- The only time the key exists outside the caller: it is returned once and never stored.
  return jsonb_build_object('client_id', v_id, 'api_key', v_key);
end;
$$;
comment on function msp_api_client_issue is 'KRN-API-01. Issues a kernel API key: cnck_ followed by 32 random bytes in hex, returned once. Only its SHA 256 hash is stored. Service role or forge_admin. Audited without the key.';

create or replace function msp_api_client_revoke(p_client_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.role(), 'unknown');
  v_row msp_api_client;
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'Revoking a kernel API key requires the forge_admin role.';
  end if;
  update msp_api_client
     set active = false, revoked_at = coalesce(revoked_at, now())
   where id = p_client_id
  returning * into v_row;
  if v_row.id is null then
    raise exception 'That API client was not found.';
  end if;
  insert into msp_audit (actor, event_type, event_detail)
  values (v_actor, 'api_client_revoked', jsonb_build_object('client_id', v_row.id, 'name', v_row.name));
  return jsonb_build_object('client_id', v_row.id, 'active', v_row.active, 'revoked_at', v_row.revoked_at);
end;
$$;
comment on function msp_api_client_revoke is 'KRN-API-01. Stops a key at once. Service role or forge_admin. Audited.';

create or replace function msp_api_authorise(p_key_hash text, p_resource text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text := lower(btrim(coalesce(p_key_hash, '')));
  v_resource text := left(coalesce(p_resource, ''), 40);
  v_client msp_api_client;
  v_calls int;
  v_reason text;
  v_status int;
begin
  if v_resource not in ('industries','industry','instruments','protocols','elements','search') then
    v_reason := 'unknown resource';
    v_status := 400;
    v_resource := null;
  end if;
  if v_reason is null and v_hash ~ '^[0-9a-f]{64}$' then
    -- The row lock serialises concurrent calls on one key, so the hourly count is exact.
    select c.* into v_client from msp_api_client c where c.key_hash = v_hash for update;
  end if;
  if v_reason is null and v_client.id is null then
    v_reason := 'unknown key';
    v_status := 401;
  elsif v_reason is null and (not v_client.active or v_client.revoked_at is not null) then
    v_reason := 'key revoked or inactive';
    v_status := 401;
  elsif v_reason is null and not ('kernel.read' = any(v_client.scopes)) then
    v_reason := 'scope kernel.read missing';
    v_status := 403;
  elsif v_reason is null then
    select count(*) into v_calls
      from msp_api_call_log l
     where l.client_id = v_client.id and l.status = 200 and l.created_at > now() - interval '1 hour';
    if v_calls >= v_client.hourly_limit then
      v_reason := 'hourly rate limit reached';
      v_status := 429;
    else
      v_status := 200;
    end if;
  end if;

  insert into msp_api_call_log (client_id, resource, status) values (v_client.id, v_resource, v_status);

  return jsonb_build_object('ok', v_status = 200,
                            'client_id', case when v_status in (200, 403, 429) then v_client.id end,
                            'scopes', case when v_status = 200 then to_jsonb(v_client.scopes) else '[]'::jsonb end,
                            'reason', v_reason);
end;
$$;
comment on function msp_api_authorise is 'KRN-API-01. Checks a key hash for a resource: known, active, not revoked, scope kernel.read, and fewer authorised calls in the last hour than the key''s hourly_limit. Logs the call (client, resource, status, time only). Service role only.';

-- 6. Read functions ---------------------------------------------------------------------------

create or replace function kernel_api_envelope(p_data jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when p_data is null then null else jsonb_build_object(
    'kernel_release', (select v.semver from msp_kernel_version v
                        order by string_to_array(regexp_replace(v.semver, '[^0-9.]', '', 'g'), '.')::int[] desc nulls last,
                                 v.released_on desc
                        limit 1),
    'as_at', current_date,
    'notice', 'Framework reference data from the Care Net Cognitive Kernel. Not legal advice and not a clinical opinion. Only instruments that have passed three verification checks and are in force are included.',
    'data', p_data) end;
$$;
comment on function kernel_api_envelope is 'Wraps every kernel API payload with kernel_release, as_at and the notice. A null payload stays null (the API answers 404).';

create or replace function kernel_api_protocol_json(p_protocol_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
           'name', tp.test_name,
           'test_type', tp.test_type,
           'hazard', h.name,
           'periodic_interval_months', tp.periodic_interval_months,
           'basis', case when tp.legal_basis_id is not null and kernel_instrument_citable(tp.legal_basis_id)
                         then jsonb_build_array(li.short_name) else '[]'::jsonb end)
    from msp_test_protocol tp
    join msp_hazard h on h.id = tp.hazard_id
    left join msp_legal_instrument li on li.id = tp.legal_basis_id
   where tp.id = p_protocol_id;
$$;
comment on function kernel_api_protocol_json is 'One protocol as the API shows it: name, type, hazard, interval and a basis of citable instruments only. Exposure values and clinical reference ranges are not included.';

create or replace function kernel_api_industry_id(p_code text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select i.id from msp_industry i where i.code = upper(btrim(coalesce(p_code, '')));
$$;

create or replace function kernel_api_industries()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select kernel_api_envelope(coalesce(
    (select jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name, 'regime', i.regulatory_regime) order by i.code)
       from msp_industry i), '[]'::jsonb));
$$;
comment on function kernel_api_industries is 'KRN-API-01. Every industry in the kernel: code, name, regime.';

create or replace function kernel_api_instruments(p_industry text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_industry uuid;
begin
  if nullif(btrim(coalesce(p_industry, '')), '') is not null then
    v_industry := kernel_api_industry_id(p_industry);
    if v_industry is null then
      return null;
    end if;
  end if;
  return kernel_api_envelope(coalesce(
    (select jsonb_agg(to_jsonb(k) order by k.short_name)
       from kernel_citable_instrument k
      where v_industry is null
         or exists (select 1 from json_array_elements(k.industries) x
                     where x ->> 'code' = (select code from msp_industry where id = v_industry))),
    '[]'::jsonb));
end;
$$;
comment on function kernel_api_instruments is 'KRN-API-01. Citable instruments, all or those mapped to one industry. Null for an unknown industry.';

create or replace function kernel_api_protocols(p_industry text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_industry uuid;
begin
  if nullif(btrim(coalesce(p_industry, '')), '') is not null then
    v_industry := kernel_api_industry_id(p_industry);
    if v_industry is null then
      return null;
    end if;
  end if;
  return kernel_api_envelope(coalesce(
    (select jsonb_agg(kernel_api_protocol_json(tp.id) order by tp.test_name, h.name, tp.id)
       from msp_test_protocol tp
       join msp_hazard h on h.id = tp.hazard_id
      where v_industry is null
         or exists (select 1 from msp_job_hazard jh
                      join msp_job_role r on r.id = jh.job_role_id
                      join msp_subindustry s on s.id = r.subindustry_id
                     where jh.hazard_id = tp.hazard_id and s.industry_id = v_industry and s.selectable)),
    '[]'::jsonb));
end;
$$;
comment on function kernel_api_protocols is 'KRN-API-01. Medical surveillance protocols, all or those an industry''s roles call for, with citable bases only. Null for an unknown industry.';

create or replace function kernel_api_elements(p_industry text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_industry uuid;
begin
  if nullif(btrim(coalesce(p_industry, '')), '') is not null then
    v_industry := kernel_api_industry_id(p_industry);
    if v_industry is null then
      return null;
    end if;
  end if;
  return kernel_api_envelope(coalesce(
    (select jsonb_agg(to_jsonb(l) order by s.ordinal, l.code)
       from hsf_public_element_library l
       join hsf_section s on s.code = l.section_code
       join hsf_element e on e.code = l.code
      where v_industry is null
         or e.universal
         or exists (select 1 from hsf_element_industry x where x.element_id = e.id and x.industry_id = v_industry)),
    '[]'::jsonb));
end;
$$;
comment on function kernel_api_elements is 'KRN-API-01. Health and Safety File elements with citable bases only and awaiting candidates named: all, or the universal elements plus the overlay of one industry. Null for an unknown industry.';

create or replace function kernel_api_industry(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ind msp_industry;
begin
  select i.* into v_ind from msp_industry i where i.id = kernel_api_industry_id(p_code);
  if v_ind.id is null then
    return null;
  end if;
  return kernel_api_envelope(jsonb_build_object(
    'code', v_ind.code,
    'name', v_ind.name,
    'regime', v_ind.regulatory_regime,
    'subindustries', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', s.code, 'name', s.name,
               'roles', coalesce((select jsonb_agg(r.title order by r.title) from msp_job_role r where r.subindustry_id = s.id), '[]'::jsonb))
             order by s.name)
        from msp_subindustry s where s.industry_id = v_ind.id and s.selectable), '[]'::jsonb),
    'roles', coalesce((
      select jsonb_agg(distinct r.title order by r.title)
        from msp_job_role r join msp_subindustry s on s.id = r.subindustry_id
       where s.industry_id = v_ind.id and s.selectable), '[]'::jsonb),
    'hazards', coalesce((
      select jsonb_agg(distinct h.name order by h.name)
        from msp_job_hazard jh
        join msp_job_role r on r.id = jh.job_role_id
        join msp_subindustry s on s.id = r.subindustry_id
        join msp_hazard h on h.id = jh.hazard_id
       where s.industry_id = v_ind.id and s.selectable), '[]'::jsonb),
    'protocols', coalesce((kernel_api_protocols(v_ind.code) -> 'data'), '[]'::jsonb),
    'instruments', coalesce((kernel_api_instruments(v_ind.code) -> 'data'), '[]'::jsonb)));
end;
$$;
comment on function kernel_api_industry is 'KRN-API-01. One industry: its selectable subindustries with role titles, roles, hazards, protocols with citable bases only, and its citable instruments. Null for an unknown code.';

create or replace function kernel_api_search(p_q text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q text := btrim(regexp_replace(coalesce(p_q, ''), '\s+', ' ', 'g'));
  v_pat text;
begin
  if length(v_q) < 2 or length(v_q) > 100 then
    return kernel_api_envelope('[]'::jsonb);
  end if;
  v_pat := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return kernel_api_envelope(coalesce((
    select jsonb_agg(jsonb_build_object('kind', m.kind, 'name', m.name, 'code', m.code) order by m.rank, m.name, m.code)
      from (
        select * from (
          select 1 as rank, 'instrument'::text as kind, k.short_name as name, null::text as code
            from kernel_citable_instrument k
           where k.short_name ilike v_pat or k.full_citation ilike v_pat
          union
          select 2, 'protocol', tp.test_name, null
            from msp_test_protocol tp where tp.test_name ilike v_pat
          union
          select 3, 'role', r.title, i.code
            from msp_job_role r
            join msp_subindustry s on s.id = r.subindustry_id and s.selectable
            join msp_industry i on i.id = s.industry_id
           where r.title ilike v_pat
          union
          select 4, 'element', l.name, l.code
            from hsf_public_element_library l where l.name ilike v_pat
        ) u
        order by rank, name, code
        limit 50
      ) m), '[]'::jsonb));
end;
$$;
comment on function kernel_api_search is 'KRN-API-01. Case insensitive match over citable instrument, protocol, role and element names; at most 50 results. The search text is not logged.';

-- 7. Execute rights ----------------------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'kernel_instrument_citable(uuid)',
    'msp_api_authorise(text, text)',
    'kernel_api_envelope(jsonb)',
    'kernel_api_protocol_json(uuid)',
    'kernel_api_industry_id(text)',
    'kernel_api_industries()',
    'kernel_api_industry(text)',
    'kernel_api_instruments(text)',
    'kernel_api_protocols(text)',
    'kernel_api_elements(text)',
    'kernel_api_search(text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- Issue and revoke: the service role, or a signed in forge_admin (checked in the body).
revoke execute on function msp_api_client_issue(text, text, text[]) from public, anon;
revoke execute on function msp_api_client_revoke(uuid) from public, anon;
grant execute on function msp_api_client_issue(text, text, text[]) to authenticated, service_role;
grant execute on function msp_api_client_revoke(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 051_hsf_generate_and_compliance.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | HSF-GEN-01 v1.0.0 | HSF skeleton generation, compliance and the client read paths 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 3 (051) and SPEC.md Part B, B9.3 and B9.4.
--
-- What this migration does:
--   1. hsf_trigger_applies: the trigger rule of hsf/build_samples.py (U, compound
--      "A and B" and "A or B", plain codes).
--   2. hsf_generate_file: writes the skeleton of a File (hsf_file, draft,
--      revision 1, and one outstanding hsf_file_item per applicable element).
--      Generating a skeleton holds no documents, so no consent is needed for it;
--      consent is needed for uploads only (049).
--   3. hsf_compute_compliance (SPEC B9.4): linked_mco or uploaded over every
--      item not marked not applicable, per section and overall; the overall is
--      the ratio across all items, not a mean of sections. Cached on hsf_file.
--   4. hsf_my_files, hsf_file_detail and hsf_set_item_status for the web tier.
--   5. Contract 9.2, 9.6, 9.7 and 9.8 (Amendment 1): a File the caller may not
--      see reads as null and a foreign item raises P0002 (both 404 at the API);
--      at most hsf.files_per_account_per_day Files per account per day; the
--      builder's anon views hsf_public_trigger and hsf_public_subindustry; and
--      hsf_portal_summary for the portal (read only, mints no token).
--
-- All functions are security definer with a fixed search path and executable by
-- the service role only. The web tier verifies the person's access token and
-- passes their auth user id. Every write is audited in msp_audit with the File.
--
-- Not built in this release (open, see the build report): per appointment, per
-- course, per licence class, per examination class and per site expansion of
-- items (B9.3.4), and the MCO and MSP evidence pass (B9.3.6). One item is written
-- per element, with site_ref null.

-- 1. Parameter (SPEC B9.4) --------------------------------------------------------------

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description, updated_by) values
  ('hsf.compliance_scope', 'true', 'boolean', null, null, 'hsf',
   'SPEC B9.4. true: an item marked not applicable (with its written reason) leaves the denominator of the compliance figure. false: it counts against the File.',
   'migration_051'),
  ('hsf.files_per_account_per_day', '20', 'integer', 1, 1000, 'hsf',
   'Contract 9.6. The most Health and Safety Files one company account may generate in a day. Keeps one account from filling the File tables.',
   'migration_051')
on conflict (key) do nothing;

-- 2. Helpers --------------------------------------------------------------------------------

create or replace function hsf_trigger_applies(p_trigger text, p_raised text[])
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  t text := btrim(coalesce(p_trigger, ''));
  v_raised text[] := coalesce(p_raised, '{}'::text[]);
begin
  if t = '' or t = 'U' or t like 'Per %' then
    return true;
  end if;
  if t like '% and %' then
    return (select bool_and(btrim(x) = any(v_raised)) from unnest(string_to_array(t, ' and ')) x);
  end if;
  if t like '% or %' then
    return (select bool_or(btrim(x) = any(v_raised)) from unnest(string_to_array(t, ' or ')) x);
  end if;
  return t = any(v_raised);
end;
$$;
comment on function hsf_trigger_applies is 'The trigger rule of hsf/build_samples.py: null, U or Per ... always applies; A and B needs every code raised; A or B needs one; a plain code needs itself.';

create or replace function hsf_user_is_staff(p_auth_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- The web tier passes the verified auth user id; staff roles live in the user's
  -- app metadata (msp_roles), the same claim msp_has_role reads from the JWT.
  select coalesce((select (to_jsonb(u) -> 'raw_app_meta_data' -> 'msp_roles')
                            ?| array['forge_admin','forge_omp','forge_safety_reviewer']
                     from auth.users u where u.id = p_auth_user), false);
$$;
comment on function hsf_user_is_staff is 'True when the auth user carries forge_admin, forge_omp or forge_safety_reviewer in app_metadata.msp_roles.';

create or replace function hsf_can_access_file(p_auth_user uuid, p_file_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_auth_user is not null
     and (exists (select 1 from hsf_file f join msp_client_account a on a.id = f.client_account_id
                   where f.id = p_file_id and a.auth_user_id = p_auth_user)
          or (hsf_user_is_staff(p_auth_user) and exists (select 1 from hsf_file f where f.id = p_file_id)));
$$;
comment on function hsf_can_access_file is 'The owning client account''s contact, or staff.';

-- The figures only, without writing the cache: used by the read paths.
create or replace function hsf_compliance_figures(p_file_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with scope as (
    select coalesce(msp_env_get_bool('hsf.compliance_scope'), true) as na_leaves
  ),
  items as (
    select e.section_code, fi.status
      from hsf_file_item fi join hsf_element e on e.id = fi.element_id
     where fi.file_id = p_file_id
  ),
  per_section as (
    select s.code, s.name, s.ordinal,
           count(i.status) as items,
           count(i.status) filter (where i.status <> 'not_applicable' or not sc.na_leaves) as applicable,
           count(i.status) filter (where i.status in ('linked_mco','uploaded')) as evidenced
      from hsf_section s
      cross join scope sc
      left join items i on i.section_code = s.code
     group by s.code, s.name, s.ordinal
  ),
  overall as (
    select sum(items)::int as items, sum(applicable)::int as applicable, sum(evidenced)::int as evidenced
      from per_section
  )
  select jsonb_build_object(
    'file_id', p_file_id,
    'overall', jsonb_build_object(
      'pct', case when o.applicable > 0 then round(100.0 * o.evidenced / o.applicable, 1) end,
      'items', o.items, 'applicable', o.applicable, 'evidenced', o.evidenced,
      'counts', coalesce((select jsonb_object_agg(c.status, c.n)
                            from (select status, count(*) as n from items group by status) c), '{}'::jsonb)),
    'sections', (select jsonb_agg(jsonb_build_object(
                          'code', p.code, 'name', p.name, 'items', p.items, 'applicable', p.applicable,
                          'evidenced', p.evidenced,
                          'compliance_pct', case when p.applicable > 0 then round(100.0 * p.evidenced / p.applicable, 1) end)
                        order by p.ordinal)
                   from per_section p))
    from overall o;
$$;
comment on function hsf_compliance_figures is 'SPEC B9.4 figures for a File without writing the cache: per section and overall, linked_mco or uploaded over every item not marked not applicable (hsf.compliance_scope). A section with nothing applicable has a null figure.';

do $$
declare
  f text;
begin
  foreach f in array array['hsf_trigger_applies(text, text[])','hsf_user_is_staff(uuid)',
                           'hsf_can_access_file(uuid, uuid)','hsf_compliance_figures(uuid)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- 3. Compliance (cached) ---------------------------------------------------------------------

create or replace function hsf_compute_compliance(p_file_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old numeric;
  v_fig jsonb;
  v_pct numeric;
begin
  select f.compliance_pct into v_old from hsf_file f where f.id = p_file_id for update;
  if not found then
    raise exception 'That File was not found.' using errcode = 'P0002';
  end if;
  v_fig := hsf_compliance_figures(p_file_id);
  v_pct := (v_fig -> 'overall' ->> 'pct')::numeric;
  if v_pct is distinct from v_old then
    update hsf_file set compliance_pct = v_pct where id = p_file_id;
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-engine', 'hsf_compliance_computed',
            jsonb_build_object('from', v_old, 'to', v_pct, 'overall', v_fig -> 'overall'), p_file_id);
  end if;
  return v_fig;
end;
$$;
comment on function hsf_compute_compliance is 'SPEC B9.4. Computes the compliance figures of a File and caches the overall figure on hsf_file.compliance_pct. A change of the cached figure is audited.';

-- 4. Generation (SPEC B9.3) ------------------------------------------------------------------

create or replace function hsf_generate_file(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_ind msp_industry;
  v_sub msp_subindustry;
  v_regime text;
  v_triggers text[];
  v_bad text;
  v_scope jsonb;
  v_site jsonb;
  v_file_id uuid;
  v_reference text;
  v_items int;
  v_headcount text;
  v_daily int;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'The File details are missing.';
  end if;
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before building a File.';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'This company account cannot build a File. Please WhatsApp a sales executive.';
  end if;

  select i.* into v_ind from msp_industry i where i.code = upper(btrim(coalesce(p ->> 'industry_code', '')));
  if v_ind.id is null then
    raise exception 'Choose your industry.';
  end if;
  if nullif(btrim(coalesce(p ->> 'subindustry_code', '')), '') is not null then
    select s.* into v_sub from msp_subindustry s
     where s.code = upper(btrim(p ->> 'subindustry_code')) and s.industry_id = v_ind.id;
    if v_sub.id is null then
      raise exception 'The subindustry is not part of the chosen industry.';
    end if;
  end if;

  -- Triggers: every code must be in the SPEC B9.2 vocabulary (or U).
  if p ? 'triggers' and jsonb_typeof(p -> 'triggers') not in ('array','null') then
    raise exception 'Activities must be a list of trigger codes.';
  end if;
  select coalesce(array_agg(distinct t order by t), '{}'::text[]) into v_triggers
    from jsonb_array_elements_text(case when jsonb_typeof(p -> 'triggers') = 'array' then p -> 'triggers' else '[]'::jsonb end) t;
  select string_agg(t, ', ' order by t) into v_bad
    from unnest(v_triggers) t
   where t <> 'U' and not exists (select 1 from hsf_trigger g where g.code = t and g.code !~ ' (and|or) ');
  if v_bad is not null then
    raise exception 'Unknown activity code: %', v_bad;
  end if;

  -- RULE-HSF-REGIME: a mine is under the Mine Health and Safety Act, every other
  -- industry under the OHS Act. The mine regime is a kernel fact and raises T-MINING.
  v_regime := case when v_ind.code = 'MINING' then 'MHSA' else 'OHSA' end;
  if v_regime = 'MHSA' and not ('T-MINING' = any(v_triggers)) then
    v_triggers := array_append(v_triggers, 'T-MINING');
  end if;

  -- Scope: at least one site with a name.
  if jsonb_typeof(p -> 'scope') <> 'object' or jsonb_typeof(p -> 'scope' -> 'sites') <> 'array'
     or jsonb_array_length(p -> 'scope' -> 'sites') < 1 then
    raise exception 'Tell us which sites the File covers.';
  end if;
  for v_site in select value from jsonb_array_elements(p -> 'scope' -> 'sites') loop
    if jsonb_typeof(v_site) <> 'object' or length(btrim(coalesce(v_site ->> 'name', ''))) not between 1 and 200 then
      raise exception 'Every site needs a name of up to 200 characters.';
    end if;
  end loop;
  v_headcount := p -> 'scope' ->> 'headcount';
  if v_headcount is not null and v_headcount !~ '^[0-9]{1,7}$' then
    raise exception 'The headcount must be a whole number.';
  end if;
  v_scope := jsonb_strip_nulls(jsonb_build_object(
    'sites', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                       'name', btrim(s ->> 'name'),
                       'address', nullif(btrim(coalesce(s ->> 'address', '')), ''))))
                from jsonb_array_elements(p -> 'scope' -> 'sites') s),
    'project_reference', nullif(btrim(coalesce(p -> 'scope' ->> 'project_reference', '')), ''),
    'headcount', v_headcount::int,
    'triggers', to_jsonb(v_triggers)));

  -- Contract 9.6: a daily ceiling per account. The account row lock makes two
  -- parallel requests count one after the other.
  perform 1 from msp_client_account where id = v_acc.id for update;
  v_daily := greatest(1, coalesce(msp_env_get_int('hsf.files_per_account_per_day'), 20));
  if (select count(*) from hsf_file f where f.client_account_id = v_acc.id and f.created_at >= current_date) >= v_daily then
    raise exception 'This company has already built % Files today, which is the daily limit. Please try again tomorrow or WhatsApp a sales executive.', v_daily;
  end if;

  insert into hsf_file (client_account_id, industry_id, subindustry_id, regime, scope, revision, status)
  values (v_acc.id, v_ind.id, v_sub.id, v_regime, v_scope, 1, 'draft')
  returning id, reference into v_file_id, v_reference;

  -- B9.3.2 and B9.3.3: universal elements whose trigger is raised, the industry
  -- overlay (and the universal elements the overlay makes mandatory), filtered
  -- to the regime; under the MHSA an element with an MHSA equivalent is swapped.
  insert into hsf_file_item (file_id, element_id, status)
  select distinct v_file_id,
         case when v_regime = 'MHSA' and e.mhsa_equivalent_id is not null then e.mhsa_equivalent_id else e.id end,
         'outstanding'
    from hsf_element e
   where e.status = 'active'
     and e.regime in ('BOTH', v_regime)
     and ((e.universal and hsf_trigger_applies(e.trigger_code, v_triggers))
          or exists (select 1 from hsf_element_industry x
                      where x.element_id = e.id
                        and x.industry_id = v_ind.id
                        and (x.subindustry_id is null or x.subindustry_id = v_sub.id)
                        and x.applicability = 'mandatory'));
  get diagnostics v_items = row_count;

  perform hsf_compute_compliance(v_file_id);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_file_generated',
          jsonb_build_object('reference', v_reference, 'industry_code', v_ind.code, 'subindustry_code', v_sub.code,
                             'regime', v_regime, 'triggers', to_jsonb(v_triggers), 'items', v_items),
          v_file_id);

  return jsonb_build_object('file_id', v_file_id, 'reference', v_reference, 'regime', v_regime, 'items', v_items);
end;
$$;
comment on function hsf_generate_file is 'Contract 051, 9.6 and SPEC B9.3. Writes a draft File (revision 1) with one outstanding item per applicable element: universal elements whose trigger applies, the industry overlay, the regime filter (MHSA for MINING, else OHSA). No consent needed: the skeleton holds no documents. Refuses more than hsf.files_per_account_per_day Files per account per day. Audited.';

-- 5. Read paths ---------------------------------------------------------------------------------

create or replace function hsf_my_files(p_auth_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'file_id', f.id,
           'reference', f.reference,
           'industry_code', i.code,
           'industry_name', i.name,
           'regime', f.regime,
           'status', f.status,
           'revision', f.revision,
           'compliance_pct', (hsf_compliance_figures(f.id) -> 'overall' ->> 'pct')::numeric,
           'created_at', f.created_at)
         order by f.created_at desc, f.reference desc), '[]'::jsonb)
    from hsf_file f
    join msp_client_account a on a.id = f.client_account_id
    join msp_industry i on i.id = f.industry_id
   where p_auth_user is not null and a.auth_user_id = p_auth_user;
$$;
comment on function hsf_my_files is 'Contract 051. The Files of the auth user''s company account, newest first, with the compliance figure computed live.';

create or replace function hsf_file_detail(p_auth_user uuid, p_file_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_fig jsonb;
  v_file jsonb;
  v_sections jsonb;
begin
  -- Contract 9.2: a File that does not exist and a File of another account read
  -- the same, as null, which the web tier answers with 404.
  if not hsf_can_access_file(p_auth_user, p_file_id) then
    return null;
  end if;
  v_fig := hsf_compliance_figures(p_file_id);

  select jsonb_build_object(
           'id', f.id, 'file_id', f.id, 'reference', f.reference,
           'company_name', a.company_name,
           'industry_code', i.code, 'industry_name', i.name,
           'subindustry_code', s.code, 'subindustry_name', s.name,
           'regime', f.regime, 'scope', f.scope, 'status', f.status, 'revision', f.revision,
           'compliance_pct', (v_fig -> 'overall' ->> 'pct')::numeric, 'created_at', f.created_at)
    into v_file
    from hsf_file f
    join msp_client_account a on a.id = f.client_account_id
    join msp_industry i on i.id = f.industry_id
    left join msp_subindustry s on s.id = f.subindustry_id
   where f.id = p_file_id;

  select jsonb_agg(jsonb_build_object(
           'code', sec.code,
           'name', sec.name,
           'compliance_pct', (select (x ->> 'compliance_pct')::numeric
                                from jsonb_array_elements(v_fig -> 'sections') x where x ->> 'code' = sec.code),
           'items', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'item_id', fi.id,
                      'element_code', e.code,
                      'name', e.name,
                      'duty', e.duty,
                      'evidence_type', e.evidence_type,
                      'review_interval', e.review_interval,
                      'status', fi.status,
                      'reason', fi.reason,
                      'responsible_person', coalesce(fi.responsible_person, e.responsible_role, apt.name),
                      'due_date', fi.due_date,
                      'site_ref', fi.site_ref,
                      'citable', coalesce(to_jsonb(l.citable), '[]'::jsonb),
                      'awaiting', coalesce(to_jsonb(l.awaiting), '[]'::jsonb),
                      'uploads', coalesce((
                        select jsonb_agg(jsonb_build_object(
                                 'upload_id', u.id, 'original_name', u.original_name, 'status', u.status,
                                 'department_code', u.department_code, 'created_at', u.created_at)
                               order by u.created_at desc, u.id)
                          from hsf_upload u where u.file_item_id = fi.id), '[]'::jsonb))
                    order by e.code, fi.site_ref nulls first)
               from hsf_file_item fi
               join hsf_element e on e.id = fi.element_id
               left join hsf_appointment_type apt on apt.code = e.responsible_appointment
               left join hsf_public_element_library l on l.code = e.code
              where fi.file_id = p_file_id and e.section_code = sec.code), '[]'::jsonb))
         order by sec.ordinal)
    into v_sections
    from hsf_section sec;

  return jsonb_build_object('file', v_file, 'sections', v_sections, 'overall', v_fig -> 'overall');
end;
$$;
comment on function hsf_file_detail is 'Contract 051, 9.2 and 9.3. The File, its fifteen sections with their items (basis: the short names hsf_element_citable allows, through hsf_public_element_library, and the instruments still awaiting verification; uploads) and the overall figure. The owning client account or staff only; null for a File that does not exist or is not the caller''s.';

create or replace function hsf_set_item_status(p_auth_user uuid, p_item_id uuid, p_status text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item hsf_file_item;
  v_reason text := nullif(btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g')), '');
  v_fig jsonb;
begin
  select fi.* into v_item from hsf_file_item fi where fi.id = p_item_id for update;
  if v_item.id is null or not hsf_can_access_file(p_auth_user, v_item.file_id) then
    raise exception 'That File item was not found.' using errcode = 'P0002';  -- 404 at the API (contract 9.2)
  end if;
  if p_status is null or p_status not in ('not_applicable','outstanding') then
    raise exception 'The status must be not_applicable or outstanding.';
  end if;
  if p_status = 'not_applicable' then
    if v_reason is null or length(v_reason) < 10 then
      raise exception 'Give a reason of at least ten characters for marking the item not applicable.';
    end if;
    if length(v_reason) > 1000 then
      raise exception 'The reason must be at most 1000 characters.';
    end if;
  end if;
  if v_item.status in ('uploaded','linked_mco') then
    raise exception 'Evidence is already held for this item, so its status cannot be changed here.';
  end if;
  if p_status = 'outstanding' and v_item.status not in ('not_applicable','outstanding') then
    raise exception 'Only an item marked not applicable can be returned to outstanding.';
  end if;

  update hsf_file_item
     set status = p_status,
         reason = case when p_status = 'not_applicable' then v_reason else null end
   where id = v_item.id;

  v_fig := hsf_compute_compliance(v_item.file_id);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_item_status_set',
          jsonb_build_object('item_id', v_item.id, 'from', v_item.status, 'to', p_status,
                             'reason', case when p_status = 'not_applicable' then v_reason end),
          v_item.file_id);

  return jsonb_build_object('item_id', v_item.id, 'status', p_status,
                            'reason', case when p_status = 'not_applicable' then v_reason end,
                            'overall', v_fig -> 'overall');
end;
$$;
comment on function hsf_set_item_status is 'Contract 051. Marks an item not applicable with a written reason of at least ten characters, or returns it to outstanding. Not for an item that already holds evidence. The owning client account or staff. Recomputes the compliance figure. Audited.';

-- 6. Builder support views (contract 9.7) -----------------------------------------------------------
-- Anon read, like the other msp_public_* views: the builder's setup form lists
-- the activity triggers and the subindustries before anyone signs in. The
-- compound trigger rows (A and B, A or B) are library expressions, not choices,
-- and hsf_generate_file refuses them, so they are left out.

create or replace view hsf_public_trigger as
select t.code, t.description
  from hsf_trigger t
 where t.code !~ ' (and|or) '
 order by t.code;
comment on view hsf_public_trigger is 'Contract 9.7. The SPEC B9.2 activity triggers a client may raise when generating a File: code and description. Public read on purpose.';
grant select on hsf_public_trigger to anon, authenticated;

create or replace view hsf_public_subindustry as
select s.code, s.name, i.code as industry_code, s.selectable
  from msp_subindustry s
  join msp_industry i on i.id = s.industry_id
 order by i.code, s.name;
comment on view hsf_public_subindustry is 'Contract 9.7. Subindustries with their industry code and whether a client may choose them. Public read on purpose; names only.';
grant select on hsf_public_subindustry to anon, authenticated;

-- 7. Portal summary (contract 9.8) ---------------------------------------------------------------------

create or replace function hsf_portal_summary(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
begin
  -- Read only (stable): it never approves an account and never mints or returns
  -- an assessment token, unlike msp_client_start_assessment.
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    return jsonb_build_object('account', null, 'plans', '[]'::jsonb, 'quotes', '[]'::jsonb, 'files', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'account', jsonb_build_object(
      'client_account_id', v_acc.id,
      'company_name', v_acc.company_name,
      'account_kind', v_acc.account_kind,
      'approved_at', v_acc.approved_at),
    -- Plans: engagements whose intake consumed an assessment token of the account.
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
               'engagement_id', e.id,
               'reference', e.reference,
               'status', e.status,
               'industry_code', i.code,
               'revision', e.revision,
               'created_at', e.created_at)
             order by e.created_at desc, e.reference desc)
        from msp_engagement e
        left join msp_industry i on i.id = e.industry_id
       where e.id in (select it.engagement_id
                        from msp_form_access fa
                        join msp_intake it on it.id = fa.used_by_intake
                       where fa.client_account_id = v_acc.id)), '[]'::jsonb),
    -- Quotes: by the account's contact email.
    'quotes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'quote_reference', q.quote_reference,
               'package_code', q.package_code,
               'price_zar', q.price_zar,
               'price_status', q.price_status,
               'valid_until', q.valid_until,
               'created_at', q.created_at)
             order by q.created_at desc, q.quote_reference desc)
        from msp_quote q
       where lower(btrim(q.contact_email)) = lower(btrim(v_acc.contact_email))), '[]'::jsonb),
    'files', coalesce((
      select jsonb_agg(jsonb_build_object(
               'file_id', f.id,
               'reference', f.reference,
               'industry_code', i.code,
               'status', f.status,
               'revision', f.revision,
               'compliance_pct', (hsf_compliance_figures(f.id) -> 'overall' ->> 'pct')::numeric,
               'signoffs', coalesce((
                 select jsonb_agg(jsonb_build_object('kind', so.kind, 'decision', so.decision, 'decided_at', so.decided_at)
                                  order by so.kind, so.decided_at nulls last)
                   from hsf_signoff so
                  where so.file_id = f.id and so.revision = f.revision), '[]'::jsonb))
             order by f.created_at desc, f.reference desc)
        from hsf_file f
        join msp_industry i on i.id = f.industry_id
       where f.client_account_id = v_acc.id), '[]'::jsonb));
end;
$$;
comment on function hsf_portal_summary is 'Contract 9.8. The portal''s view of the signed in person''s company: the account, its Medical Surveillance Plans (engagements whose intake used an assessment token of the account), its quotations (by contact email) and its Health and Safety Files with compliance and the sign offs of the current revision. Read only; mints no token. Service role only; GET /api/portal-summary calls it after requireUser.';

-- 8. Execute rights: service role only -------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'hsf_compute_compliance(uuid)',
    'hsf_generate_file(uuid, jsonb)',
    'hsf_my_files(uuid)',
    'hsf_file_detail(uuid, uuid)',
    'hsf_set_item_status(uuid, uuid, text, text)',
    'hsf_portal_summary(uuid)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

------------------------------------------------------------------------------
-- 052_hsf_launch_controls.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | HSF-LCH-01 v1.0.0 | HSF launch controls: upload gate, client verification, retention, scanning, client deletion 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 10 (Amendment 2), items 10.1 to 10.6.
--
-- What this migration does:
--   1. Parameters hsf.uploads_open (false), hsf.staging_retention_days (730) and
--      hsf.deletion_sms_enabled (false), category hsf.
--   2. hsf_upload gains the statuses expired and client_deleted and the security
--      scan columns (scan_status, scan_engine, scanned_at, scan_findings,
--      scan_attempts).
--   3. hsf_client_verification: a company account uploads only once Care Net has
--      verified it as a Care Net Consultants client (account_kind alone is not
--      enough, because migration 040 self approves).
--   4. hsf_deletion_request: a client deletes their own staged documents only
--      after a warning, an acknowledgement and a one time PIN that Supabase Auth
--      sends and checks. Care Net never generates or stores a PIN. A request
--      is confirmable only once its own PIN was sent (pin_sent_at); a request
--      whose PIN could not be sent is cancelled. An upload whose transfer is in
--      flight is not deletable until the 30 minute reclaim window has passed.
--   5. One helper, hsf_revoke_upload_evidence, withdraws the evidence an upload
--      supplied (the hash mismatch path of 049), and is reused by the scan
--      rejection, the two year expiry and the client deletion.
--   6. hsf_register_upload refuses, in this order: no account, declined, uploads
--      closed, not verified, consents, then the checks of 049.
--   7. The scan pass (hsf_scan_claim, hsf_scan_record, hsf_scan_reset);
--      hsf_transfer_claim and hsf_transfer_record move only uploads that passed
--      the scan. An antivirus outage does not use up the five scan attempts; a
--      fingerprint mismatch at the scan fails the upload.
--   8. The two year limit (hsf_retention_queue, hsf_mark_expired), which also
--      applies to uploads blocked by a consent withdrawal; the staging alerts
--      and hsf_my_uploads show the expiry date.
--   9. The cleanup queue and hsf_mark_staging_deleted take client_deleted and
--      expired uploads; the queue also takes transferred, never completed and
--      scan rejected bytes whether blocked or not (hsf_upload_awaits_cleanup).
--      A receipt from MyClinicOnline that arrives after the client deleted the
--      upload is kept and audited, so the deletion at MyClinicOnline can follow.
--
-- Nothing here writes file content, a PIN, a key or a token to msp_audit.
-- Migrations 047 to 051 are not edited: every changed function is redefined
-- here with create or replace, keeping security definer, the fixed search path
-- and service role only execute unless stated.

-- 1. Parameters -----------------------------------------------------------------------------

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description, updated_by) values
  ('hsf.uploads_open', 'false', 'boolean', null, null, 'hsf',
   'Opens company uploads in the File builder. Stays off until the backend (Odendaal) and the front end (Cassandra and the designer) are signed off.',
   'migration_052'),
  ('hsf.staging_retention_days', '730', 'integer', 1, 730, 'hsf',
   'Contract 10.3. The longest a document may stay in Care Net staging, in days (two years). Older staged bytes are deleted, including those of uploads blocked by a consent withdrawal.',
   'migration_052'),
  ('hsf.deletion_sms_enabled', 'false', 'boolean', null, null, 'hsf',
   'Contract 10.5. Offers the deletion PIN by SMS as well as by email. Needs an SMS provider configured in Supabase Auth, and the person needs a confirmed phone number.',
   'migration_052')
on conflict (key) do nothing;

-- 2. hsf_upload: new statuses and the security scan -------------------------------------------
-- The 049 status check is replaced by one that keeps every existing value and
-- adds expired (two year limit reached, bytes deleted) and client_deleted (the
-- client deleted it with a PIN; the bytes leave through the cleanup queue).
do $$
declare
  v_name text;
begin
  select c.conname into v_name
    from pg_constraint c
   where c.conrelid = 'public.hsf_upload'::regclass
     and c.contype = 'c'
     and pg_get_constraintdef(c.oid) ilike '%awaiting_upload%';
  if v_name is not null then
    execute format('alter table hsf_upload drop constraint %I', v_name);
  end if;
end;
$$;
alter table hsf_upload add constraint hsf_upload_status_check check (status in
  ('awaiting_upload','uploaded','verified','held','transferring','transferred','staging_deleted',
   'rejected','failed','expired','client_deleted'));
alter table hsf_upload add constraint hsf_upload_expired_no_bytes
  check (status <> 'expired' or (storage_path is null and staging_deleted_at is not null));

alter table hsf_upload
  add column scan_status text not null default 'pending'
    check (scan_status in ('pending','clean','infected','harmful','error')),
  add column scan_engine text,
  add column scanned_at timestamptz,
  add column scan_findings jsonb,
  add column scan_attempts int not null default 0 check (scan_attempts >= 0);
comment on column hsf_upload.scan_status is 'Contract 10.4. pending until the scan pass has run; clean when the built in structural check and the antivirus engine both passed; infected or harmful rejects the upload; error is retried by hsf_scan_claim up to five attempts. Only a clean upload is ever claimed for transfer.';
comment on column hsf_upload.scan_engine is 'Contract 10.4. The antivirus engine and version that answered, as the worker reported it.';
comment on column hsf_upload.scanned_at is 'Contract 10.4. When the last scan result was recorded.';
comment on column hsf_upload.scan_findings is 'Contract 10.4. The findings of the last scan as a json array of {code, message} in plain words. Never file content.';
comment on column hsf_upload.scan_attempts is 'Contract 10.4. How many times hsf_scan_claim has handed the upload to the scan pass. After five an upload that still reads pending or error is not claimed again.';
create index hsf_upload_scan_idx on hsf_upload(uploaded_at, created_at)
  where status = 'uploaded' and scan_status in ('pending','error');

comment on table hsf_upload is 'HSF-UPL-01. One row per document a client drops into the builder. The bytes sit in the private hsf-staging bucket at <client_account_id>/<upload_id>/<safe_name> until they are transferred to MyClinicOnline and removed; the row, with the browser and server SHA 256 fingerprints, stays for the audit trail. Lifecycle: awaiting_upload, uploaded (then scanned), held, transferred, staging_deleted; or rejected, failed, expired (two year limit, contract 10.3) and client_deleted (deleted by the client with a PIN, contract 10.5).';

-- 3. Client verification (contract 10.2) ----------------------------------------------------

create table hsf_client_verification (
  client_account_id uuid primary key references msp_client_account(id),
  status text not null default 'requested' check (status in ('requested','verified','revoked')),
  method text check (method in ('mco_company_ref','client_register','sales_executive')),
  evidence_ref text,
  requested_at timestamptz not null default now(),
  verified_by text,
  verified_at timestamptz,
  revoked_by text,
  revoked_at timestamptz,
  revoke_reason text,
  check (status <> 'verified' or (method is not null and evidence_ref is not null
                                  and verified_by is not null and verified_at is not null)),
  check (status <> 'revoked' or (revoked_by is not null and revoked_at is not null and revoke_reason is not null))
);
comment on table hsf_client_verification is 'HSF-LCH-01, contract 10.2. Whether Care Net has confirmed that a company account is a Care Net Consultants client. Only a verified account may upload documents. The method (MyClinicOnline company reference, client register or a sales executive) and the evidence reference are recorded; every change is audited. A revocation blocks the account''s untransferred uploads and deletes nothing.';
comment on column hsf_client_verification.evidence_ref is 'What the verification rests on, for example the MyClinicOnline company reference or the client register number. Required to verify.';

alter table hsf_client_verification enable row level security;
revoke all on hsf_client_verification from public, anon, authenticated;
grant select on hsf_client_verification to authenticated;
grant all on hsf_client_verification to service_role;
create policy hsf_client_verification_read on hsf_client_verification
  for select to authenticated using (hsf_is_staff());

-- 4. Deletion requests (contract 10.5) --------------------------------------------------------

create table hsf_deletion_request (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  auth_user_id uuid not null,
  upload_ids uuid[] not null check (cardinality(upload_ids) between 1 and 50),
  channel text not null check (channel in ('email','sms')),
  acknowledged_irreversible boolean not null check (acknowledged_irreversible),
  status text not null default 'pending' check (status in ('pending','confirmed','expired','cancelled','locked')),
  attempts int not null default 0 check (attempts between 0 and 5),
  requested_at timestamptz not null default now(),
  expires_at timestamptz not null,
  pin_sent_at timestamptz,
  confirmed_at timestamptz,
  check (expires_at = requested_at + interval '10 minutes'),
  check (status <> 'confirmed' or confirmed_at is not null)
);
comment on table hsf_deletion_request is 'HSF-LCH-01, contract 10.5. One request by a client to delete their own staged documents permanently. The client has read the warning and ticked that it cannot be undone; Supabase Auth sends and checks the one time PIN, so no PIN is held here. A request lasts 10 minutes and allows 5 PIN attempts, then it is locked.';
comment on column hsf_deletion_request.pin_sent_at is 'When Supabase Auth accepted the request to send this request''s PIN. Set only after that acceptance; a request without it can take no PIN attempt and cannot be confirmed, so a PIN sent for another request or a sign in code never confirms it.';
create index hsf_deletion_request_account_idx on hsf_deletion_request(client_account_id, requested_at desc);

alter table hsf_deletion_request enable row level security;
revoke all on hsf_deletion_request from public, anon, authenticated;
grant select on hsf_deletion_request to authenticated;
grant all on hsf_deletion_request to service_role;
create policy hsf_deletion_request_read on hsf_deletion_request
  for select to authenticated using (hsf_is_staff());

-- 5. Internal helpers (never callable from outside) --------------------------------------------

create or replace function hsf_staging_retention_days()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select least(730, greatest(1, coalesce(msp_env_get_int('hsf.staging_retention_days'), 730)));
$$;
comment on function hsf_staging_retention_days is 'Contract 10.3. hsf.staging_retention_days, held between 1 and 730 whatever the stored value.';

create or replace function hsf_upload_deletable(p_status text, p_storage_path text, p_claimed_at timestamptz)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_storage_path is not null
     and coalesce(p_status, '') not in ('transferred','staging_deleted','expired','client_deleted')
     -- A transfer in flight may already have reached MyClinicOnline, so it is not
     -- deleted here until the worker's 30 minute reclaim window has passed.
     and not (coalesce(p_status, '') = 'transferring'
              and p_claimed_at is not null and p_claimed_at >= now() - interval '30 minutes');
$$;
comment on function hsf_upload_deletable is 'Contract 10.5. A client may delete an upload while its bytes are still in Care Net staging: any status except transferred, staging_deleted, expired and client_deleted, and not while a transfer is in flight (transferring and claimed in the last 30 minutes), because MyClinicOnline may already hold that copy. Once MyClinicOnline holds a document, deletion is MyClinicOnline''s process.';

-- Failed and rejected bytes are never a document, so they leave staging through
-- the cleanup queue. A block (consent withdrawn, verification revoked) keeps
-- them only while they may still be the client's document: bytes that never
-- completed, and bytes the security scan rejected, go whatever the block.
-- Transferred bytes go too: the copy at MyClinicOnline is confirmed.
create or replace function hsf_upload_awaits_cleanup(p_status text, p_blocked text, p_uploaded_at timestamptz, p_scan_status text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_status, '') in ('transferred','client_deleted')
      or (coalesce(p_status, '') in ('failed','rejected')
          and (p_blocked is null or p_uploaded_at is null or coalesce(p_scan_status, '') in ('infected','harmful')));
$$;
comment on function hsf_upload_awaits_cleanup is 'Contract 9.5, 10.4 and 10.5. True for an upload whose staged bytes the cleanup queue removes: transferred and client_deleted rows whether blocked or not; failed and rejected rows that are not blocked, never completed, or failed the security scan.';

-- The hash mismatch path of 049, as one helper: bytes that are no longer
-- evidence (fingerprint mismatch, failed scan, two year limit, client deletion)
-- withdraw the evidence row written at completion, return the File item to
-- outstanding when no other unrevoked evidence holds it, and recompute the
-- compliance figure.
create or replace function hsf_revoke_upload_evidence(p_upload_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_revoked int := 0;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id;
  if v_up.id is null then
    return 0;
  end if;
  if v_up.file_item_id is not null then
    perform 1 from hsf_file_item where id = v_up.file_item_id for update;
  end if;
  update hsf_evidence set revoked_at = now()
   where upload_id = v_up.id and revoked_at is null;
  get diagnostics v_revoked = row_count;
  if v_up.file_item_id is not null then
    update hsf_file_item fi
       set status = 'outstanding', reason = null
     where fi.id = v_up.file_item_id
       and fi.status = 'uploaded'
       and not exists (select 1 from hsf_evidence e where e.file_item_id = fi.id and e.revoked_at is null);
  end if;
  if v_up.file_id is not null then
    perform hsf_compute_compliance(v_up.file_id);
  end if;
  return v_revoked;
end;
$$;
comment on function hsf_revoke_upload_evidence is 'Contract 9.5 and 10.3 to 10.5. The one evidence withdrawal for an upload whose bytes are no longer evidence: revokes its unrevoked hsf_evidence rows, returns the File item to outstanding when no other unrevoked evidence holds it, and recomputes the compliance figure. Returns the number of rows revoked. Used by hsf_transfer_record (mismatch), hsf_scan_record, hsf_mark_expired and hsf_deletion_request_confirm.';

create or replace function hsf_client_verified(p_client_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from hsf_client_verification v
                  where v.client_account_id = p_client_account_id and v.status = 'verified');
$$;
comment on function hsf_client_verified is 'Contract 10.2. True when Care Net has verified the company account as a Care Net Consultants client and not revoked it.';

-- 6. Client verification ---------------------------------------------------------------------

create or replace function hsf_request_client_verification(p_auth_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_row hsf_client_verification;
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before asking for verification.';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'This company account cannot be verified. Please WhatsApp a sales executive.';
  end if;
  select v.* into v_row from hsf_client_verification v where v.client_account_id = v_acc.id for update;
  if v_row.client_account_id is null or v_row.status = 'revoked' then
    -- A new request, or a request again after a revocation. The revocation
    -- details stay on the row for the sales executive who reviews it.
    insert into hsf_client_verification (client_account_id, status, requested_at)
    values (v_acc.id, 'requested', now())
    on conflict (client_account_id) do update set status = 'requested', requested_at = now()
    returning * into v_row;
    insert into msp_audit (actor, event_type, event_detail)
    values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_client_verification_requested',
            jsonb_build_object('client_account_id', v_acc.id));
  end if;
  return jsonb_build_object('client_account_id', v_row.client_account_id, 'status', v_row.status,
                            'requested_at', v_row.requested_at, 'verified_at', v_row.verified_at);
end;
$$;
comment on function hsf_request_client_verification is 'Contract 10.2. Creates, or returns, the verification request of the auth user''s company account. An account whose verification was revoked may ask again (the revocation details stay on the row). A declined account is refused. Audited as hsf_client_verification_requested when a request is made.';

create or replace function hsf_verify_client(p_client_account_id uuid, p_method text, p_evidence_ref text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_ref text := btrim(coalesce(p_evidence_ref, ''));
  v_by text;
  v_row hsf_client_verification;
begin
  if not (coalesce(auth.role() = 'service_role', false) or coalesce(hsf_is_staff(), false)) then
    raise exception 'Verifying a client needs a Care Net staff role.' using errcode = '42501';
  end if;
  select a.* into v_acc from msp_client_account a where a.id = p_client_account_id;
  if v_acc.id is null then
    raise exception 'That company account was not found.' using errcode = 'P0002';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'A declined company account cannot be verified.';
  end if;
  if p_method is null or p_method not in ('mco_company_ref','client_register','sales_executive') then
    raise exception 'The verification method must be mco_company_ref, client_register or sales_executive.';
  end if;
  if v_ref = '' or length(v_ref) > 200 or v_ref ~ '[[:cntrl:]]' then
    raise exception 'Record what the verification rests on (for example the MyClinicOnline company reference or the client register number), in 1 to 200 characters.';
  end if;
  v_by := coalesce(nullif(btrim(auth.jwt() ->> 'email'), ''),
                   case when auth.role() = 'service_role' then 'service_role' end, 'staff');
  -- A verification after a revocation clears the revocation fields; the audit
  -- trail keeps both events. Uploads blocked by the revocation stay blocked.
  insert into hsf_client_verification (client_account_id, status, method, evidence_ref, requested_at, verified_by, verified_at)
  values (v_acc.id, 'verified', p_method, v_ref, now(), v_by, now())
  on conflict (client_account_id) do update
     set status = 'verified', method = excluded.method, evidence_ref = excluded.evidence_ref,
         verified_by = excluded.verified_by, verified_at = excluded.verified_at,
         revoked_by = null, revoked_at = null, revoke_reason = null
  returning * into v_row;
  insert into msp_audit (actor, event_type, event_detail)
  values (v_by, 'hsf_client_verified',
          jsonb_build_object('client_account_id', v_acc.id, 'method', p_method, 'evidence_ref', v_ref));
  return jsonb_build_object('client_account_id', v_row.client_account_id, 'status', v_row.status,
                            'method', v_row.method, 'verified_by', v_row.verified_by, 'verified_at', v_row.verified_at);
end;
$$;
comment on function hsf_verify_client is 'Contract 10.2. Marks a company account verified as a Care Net Consultants client, with the method and a required evidence reference. The service role or a signed in forge staff member (hsf_is_staff, which includes forge_admin), checked in the body; verified_by is the staff email from the JWT or service_role. A declined account is refused. Uploads blocked by an earlier revocation stay blocked. Audited as hsf_client_verified.';

create or replace function hsf_revoke_client_verification(p_client_account_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_by text;
  v_row hsf_client_verification;
  v_blocked int := 0;
begin
  if not (coalesce(auth.role() = 'service_role', false) or coalesce(hsf_is_staff(), false)) then
    raise exception 'Revoking a client verification needs a Care Net staff role.' using errcode = '42501';
  end if;
  if v_reason = '' or length(v_reason) > 500 then
    raise exception 'Give the reason for the revocation, in 1 to 500 characters.';
  end if;
  select v.* into v_row from hsf_client_verification v where v.client_account_id = p_client_account_id for update;
  if v_row.client_account_id is null or v_row.status <> 'verified' then
    raise exception 'That company account is not verified.';
  end if;
  v_by := coalesce(nullif(btrim(auth.jwt() ->> 'email'), ''),
                   case when auth.role() = 'service_role' then 'service_role' end, 'staff');
  update hsf_client_verification
     set status = 'revoked', revoked_by = v_by, revoked_at = now(), revoke_reason = v_reason
   where client_account_id = v_row.client_account_id
  returning * into v_row;
  -- Nothing is deleted: untransferred uploads are blocked from the scan and the
  -- transfer claim, as after a consent withdrawal.
  update hsf_upload
     set transfer_blocked_reason = 'client verification revoked'
   where client_account_id = v_row.client_account_id
     and transfer_blocked_reason is null
     and status in ('awaiting_upload','uploaded','verified','held','transferring');
  get diagnostics v_blocked = row_count;
  insert into msp_audit (actor, event_type, event_detail)
  values (v_by, 'hsf_client_verification_revoked',
          jsonb_build_object('client_account_id', v_row.client_account_id, 'reason', v_reason,
                             'blocked_uploads', v_blocked));
  return jsonb_build_object('client_account_id', v_row.client_account_id, 'status', v_row.status,
                            'revoked_at', v_row.revoked_at, 'blocked_uploads', v_blocked);
end;
$$;
comment on function hsf_revoke_client_verification is 'Contract 10.2. Revokes a verification with a reason. The account''s untransferred uploads are not deleted: they get transfer_blocked_reason = ''client verification revoked'' and are never scanned or claimed for transfer. The service role or forge staff, checked in the body. Audited as hsf_client_verification_revoked.';

-- 7. The upload gate and registration ------------------------------------------------------------

create or replace function hsf_upload_gate(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_status text;
  v_phone_ok boolean;
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is not null then
    select v.status into v_status from hsf_client_verification v where v.client_account_id = v_acc.id;
  end if;
  select (to_jsonb(u) ->> 'phone') is not null and (to_jsonb(u) ->> 'phone_confirmed_at') is not null
    into v_phone_ok
    from auth.users u where u.id = p_auth_user;
  return jsonb_build_object(
    'uploads_open', coalesce(msp_env_get_bool('hsf.uploads_open'), false),
    'client_verified', coalesce(v_status = 'verified', false),
    'verification_requested', coalesce(v_status = 'requested', false),
    'consent_complete', v_acc.id is not null and hsf_consent_complete(v_acc.id),
    'deletion_sms_available', coalesce(msp_env_get_bool('hsf.deletion_sms_enabled'), false) and coalesce(v_phone_ok, false));
end;
$$;
comment on function hsf_upload_gate is 'Contract 10.1. What the builder needs to show before an upload: {uploads_open, client_verified, verification_requested, consent_complete}, plus deletion_sms_available (hsf.deletion_sms_enabled and a confirmed phone on the sign in), which tells the builder whether to offer the deletion PIN by SMS.';

create or replace function hsf_register_upload(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_file hsf_file;
  v_item_id uuid;
  v_element_section text;
  v_section text := nullif(btrim(coalesce(p ->> 'section_code', '')), '');
  v_dept text := nullif(btrim(coalesce(p ->> 'department_code', '')), '');
  v_element text := nullif(btrim(coalesce(p ->> 'element_code', '')), '');
  v_name text := btrim(coalesce(p ->> 'original_name', ''));
  v_mime text := lower(btrim(coalesce(p ->> 'mime_type', '')));
  v_size_txt text := btrim(coalesce(p ->> 'size_bytes', ''));
  v_size bigint;
  v_sha text := lower(btrim(coalesce(p ->> 'sha256', '')));
  v_max bigint;
  v_allowed text[];
  v_id uuid := gen_random_uuid();
  v_safe text;
  v_path text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'The upload details are missing.';
  end if;
  -- Contract 10.2: no account, declined, uploads closed (10.1), not verified,
  -- consents, then the checks of 049.
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before uploading documents.';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'This company account cannot upload documents. Please WhatsApp a sales executive.';
  end if;
  if not coalesce(msp_env_get_bool('hsf.uploads_open'), false) then
    raise exception 'Document uploads open soon. Your File can be built now, and uploads will open once Care Net has finished testing.';
  end if;
  if not hsf_client_verified(v_acc.id) then
    raise exception 'Uploads are for verified Care Net Consultants clients. Ask for verification in the builder, or WhatsApp a sales executive.';
  end if;
  if not hsf_consent_complete(v_acc.id) then
    raise exception 'All three consents are needed before any document is uploaded.';
  end if;

  if v_dept is null or not exists (select 1 from hsf_department d where d.code = v_dept) then
    raise exception 'Choose the department this document belongs to.';
  end if;
  if v_section is not null and not exists (select 1 from hsf_section s where s.code = v_section) then
    raise exception 'The File section must be a letter from A to O.';
  end if;

  if nullif(p ->> 'file_id', '') is not null then
    if (p ->> 'file_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'The File is not recognised.';
    end if;
    select f.* into v_file from hsf_file f where f.id = (p ->> 'file_id')::uuid;
    if v_file.id is null or v_file.client_account_id <> v_acc.id then
      raise exception 'The File is not recognised.';
    end if;
  end if;
  if v_element is not null then
    if v_file.id is null then
      raise exception 'An element upload must name the File it belongs to.';
    end if;
    select fi.id, e.section_code into v_item_id, v_element_section
      from hsf_file_item fi
      join hsf_element e on e.id = fi.element_id
     where fi.file_id = v_file.id and e.code = v_element
     order by fi.site_ref nulls first
     limit 1;
    if v_item_id is null then
      raise exception 'That element is not part of this File.';
    end if;
    if v_section is null then
      v_section := v_element_section;
    elsif v_section <> v_element_section then
      raise exception 'That element belongs to Section %, not Section %.', v_element_section, v_section;
    end if;
  end if;

  if v_name = '' or length(v_name) > 255 or v_name ~ '[[:cntrl:]]' then
    raise exception 'The file name must be between 1 and 255 printable characters.';
  end if;
  v_allowed := array(select lower(btrim(x)) from unnest(string_to_array(coalesce(msp_env_get('hsf.upload_allowed_mime'), ''), ',')) x
                      where btrim(x) <> '');
  if v_mime = '' or not (v_mime = any(v_allowed)) then
    raise exception 'That file type is not accepted. Upload a PDF, JPEG, PNG, Word, Excel or CSV file.';
  end if;
  if v_size_txt !~ '^[0-9]{1,15}$' then
    raise exception 'The file size is not valid.';
  end if;
  v_size := v_size_txt::bigint;
  v_max := coalesce(msp_env_get_int('hsf.upload_max_bytes'), 26214400);
  if v_size < 1 or v_size > v_max then
    raise exception 'The file is larger than the % MB limit.', round(v_max / 1048576.0, 1);
  end if;
  if v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'The SHA 256 fingerprint must be 64 hexadecimal characters.';
  end if;

  v_safe := hsf_safe_name(v_name);
  v_path := v_acc.id::text || '/' || v_id::text || '/' || v_safe;

  insert into hsf_upload (id, client_account_id, auth_user_id, file_id, file_item_id, section_code, department_code,
                          original_name, safe_name, mime_type, size_bytes, sha256_client, storage_bucket, storage_path)
  values (v_id, v_acc.id, p_auth_user, v_file.id, v_item_id, v_section, v_dept,
          v_name, v_safe, v_mime, v_size, v_sha, 'hsf-staging', v_path);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_upload_registered',
          jsonb_build_object('upload_id', v_id, 'client_account_id', v_acc.id, 'department_code', v_dept,
                             'section_code', v_section, 'element_code', v_element, 'mime_type', v_mime,
                             'size_bytes', v_size),
          v_file.id);

  return jsonb_build_object('upload_id', v_id, 'bucket', 'hsf-staging', 'path', v_path);
end;
$$;
comment on function hsf_register_upload is 'Contract 049, 10.1 and 10.2. Registers one upload before the bytes move. Refuses, in this order: no company account, a declined account, uploads closed (hsf.uploads_open), an account not verified as a Care Net Consultants client, incomplete consent; then department, section, File and element, and type and size against hsf.upload_allowed_mime and hsf.upload_max_bytes. Returns the staging bucket and path for the signed upload URL. Audited (never the file name or content).';

-- 8. Security scan and transfer --------------------------------------------------------------------

create or replace function hsf_scan_claim(p_limit int)
returns setof hsf_upload
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int := greatest(1, least(coalesce(p_limit, 10), 100));
begin
  -- Uploads whose bytes have arrived and wait for a scan (or a retry after an
  -- engine error), oldest first. Rows another worker has locked are skipped;
  -- every claimed row counts one attempt, at most five.
  return query
    with c as (
      select u.id
        from hsf_upload u
       where u.status = 'uploaded'
         and u.scan_status in ('pending','error')
         and u.scan_attempts < 5
         and u.transfer_blocked_reason is null
         and u.storage_path is not null
       order by u.uploaded_at nulls last, u.created_at, u.id
       limit v_limit
       for update of u skip locked
    ), claimed as (
      update hsf_upload u
         set scan_attempts = u.scan_attempts + 1
        from c
       where u.id = c.id
      returning u.*
    )
    select * from claimed order by uploaded_at nulls last, created_at, id;
end;
$$;
comment on function hsf_scan_claim is 'Contract 10.4. The scan pass''s claim, oldest first, at most 100: uploaded rows whose scan is pending or ended in an engine error, with bytes present, not blocked, and fewer than five attempts. Locked with for update skip locked; each claimed row''s scan_attempts goes up by one.';

create or replace function hsf_scan_record(p_upload_id uuid, p_result text, p_engine text, p_findings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_engine text := nullif(left(btrim(coalesce(p_engine, '')), 200), '');
  v_findings jsonb := coalesce(p_findings, '[]'::jsonb);
  v_summary text;
  v_reason text;
  v_status text;
  v_revoked int := 0;
  v_attempts int;
begin
  if p_result is null or p_result not in ('clean','infected','harmful','error') then
    raise exception 'Unknown scan result: %', coalesce(p_result, 'none');
  end if;
  if jsonb_typeof(v_findings) <> 'array' or jsonb_array_length(v_findings) > 50 then
    raise exception 'The scan findings must be a list of at most 50 entries.';
  end if;
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.' using errcode = 'P0002';
  end if;
  if v_up.status <> 'uploaded' or v_up.scan_status not in ('pending','error') then
    raise exception 'The upload is not waiting for a security scan (status %, scan %).', v_up.status, v_up.scan_status;
  end if;

  if p_result = 'error' and exists (select 1 from jsonb_array_elements(v_findings) f
                                     where jsonb_typeof(f) = 'object' and f ->> 'code' = 'fingerprint_mismatch') then
    -- The stored bytes are not the bytes fingerprinted in the browser: like the
    -- mismatch at transfer (contract 9.5) the upload fails, its evidence is
    -- withdrawn and its bytes leave through the cleanup queue. No retry.
    v_status := 'failed';
    v_reason := 'The stored file does not match the fingerprint taken when it was uploaded.';
    update hsf_upload
       set status = 'failed', reject_reason = v_reason, scan_status = 'error', scan_engine = v_engine,
           scanned_at = now(), scan_findings = v_findings, transfer_claimed_at = null
     where id = v_up.id;
    v_revoked := hsf_revoke_upload_evidence(v_up.id);
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_upload_scan_rejected',
            jsonb_build_object('upload_id', v_up.id, 'result', 'fingerprint_mismatch', 'engine', v_engine,
                               'findings', v_findings, 'evidence_revoked', v_revoked),
            v_up.file_id);
  elsif p_result in ('infected','harmful') then
    -- The plain words of the findings become the reason the client reads. Each
    -- message loses its closing full stop, so several read 'X; Y.' not 'X.; Y.'.
    select string_agg(m, '; ' order by m) into v_summary
      from (select distinct left(regexp_replace(regexp_replace(btrim(f ->> 'message'), '[[:cntrl:]]+', ' ', 'g'),
                                                '[.[:space:]]+$', ''), 200) as m
              from jsonb_array_elements(v_findings) f
             where jsonb_typeof(f) = 'object' and coalesce(f ->> 'message', '') !~ '^[.[:space:][:cntrl:]]*$') x;
    v_summary := coalesce(left(v_summary, 400),
                          case when p_result = 'infected' then 'the antivirus engine found malicious software'
                               else 'the file carries content that could cause harm' end);
    v_reason := 'The file failed the security scan: ' || v_summary;
    if v_reason !~ '[.!?]$' then
      v_reason := v_reason || '.';
    end if;
    v_status := 'rejected';
    -- Harmful bytes are not a document waiting on a consent or verification
    -- decision, so a block set while the scan ran is cleared: the cleanup queue
    -- removes them either way.
    update hsf_upload
       set status = 'rejected', reject_reason = v_reason, scan_status = p_result, scan_engine = v_engine,
           scanned_at = now(), scan_findings = v_findings, transfer_claimed_at = null,
           transfer_blocked_reason = null
     where id = v_up.id;
    -- The bytes are not evidence; they leave through hsf_transfer_cleanup_queue.
    v_revoked := hsf_revoke_upload_evidence(v_up.id);
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_upload_scan_rejected',
            jsonb_build_object('upload_id', v_up.id, 'result', p_result, 'engine', v_engine,
                               'findings', v_findings, 'evidence_revoked', v_revoked),
            v_up.file_id);
  else
    v_status := 'uploaded';
    -- An antivirus engine that is not configured or did not answer says nothing
    -- about the file, so that attempt is given back: an outage never uses up
    -- the five attempts. Only inspection errors count.
    update hsf_upload
       set scan_status = p_result, scan_engine = v_engine, scanned_at = now(), scan_findings = v_findings,
           scan_attempts = case
             when p_result = 'error' and jsonb_array_length(v_findings) > 0
                  and not exists (select 1 from jsonb_array_elements(v_findings) f
                                   where jsonb_typeof(f) <> 'object'
                                      or coalesce(f ->> 'code', '') not in ('av_not_configured','av_error'))
             then greatest(0, scan_attempts - 1)
             else scan_attempts end
     where id = v_up.id
    returning scan_attempts into v_attempts;
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_upload_scanned',
            jsonb_build_object('upload_id', v_up.id, 'result', p_result, 'engine', v_engine,
                               'attempts', v_attempts),
            v_up.file_id);
  end if;

  return jsonb_build_object('upload_id', v_up.id, 'status', v_status, 'scan_status', p_result,
                            'reject_reason', v_reason, 'evidence_revoked', v_revoked);
end;
$$;
comment on function hsf_scan_record is 'Contract 10.4. Records the scan result of an uploaded row whose scan is pending or error. clean: scan_status clean, the upload may now be claimed for transfer. error: scan_status error, the upload stays uploaded for a retry; an error that only says the antivirus engine is not configured or did not answer (codes av_not_configured, av_error) gives its attempt back. error with a fingerprint_mismatch finding: the upload fails like a mismatch at transfer, with its evidence withdrawn. infected or harmful: the upload is rejected with ''The file failed the security scan: <plain summary of the findings>'', any transfer block cleared, its evidence withdrawn through hsf_revoke_upload_evidence, and its bytes leave through the cleanup queue. Audited as hsf_upload_scanned or hsf_upload_scan_rejected.';

create or replace function hsf_scan_reset(p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_by text;
begin
  if not (coalesce(auth.role() = 'service_role', false) or coalesce(hsf_is_staff(), false)) then
    raise exception 'Resetting a security scan needs a Care Net staff role.' using errcode = '42501';
  end if;
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.' using errcode = 'P0002';
  end if;
  if v_up.status <> 'uploaded' or v_up.scan_status not in ('pending','error') or v_up.storage_path is null then
    raise exception 'Only an uploaded document still waiting for its security scan can be scanned again (status %, scan %).',
      v_up.status, v_up.scan_status;
  end if;
  v_by := coalesce(nullif(btrim(auth.jwt() ->> 'email'), ''),
                   case when auth.role() = 'service_role' then 'service_role' end, 'staff');
  update hsf_upload set scan_attempts = 0 where id = v_up.id;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (v_by, 'hsf_upload_scan_reset',
          jsonb_build_object('upload_id', v_up.id, 'attempts_before', v_up.scan_attempts,
                             'scan_status', v_up.scan_status),
          v_up.file_id);
  return jsonb_build_object('upload_id', v_up.id, 'scan_status', v_up.scan_status, 'scan_attempts', 0);
end;
$$;
comment on function hsf_scan_reset is 'Contract 10.4. Gives an uploaded document whose scan is pending or error its five scan attempts back, for example after an inspection fault was fixed; hsf_staging_alerts lists the documents that used all five. The service role or forge staff, checked in the body. Audited as hsf_upload_scan_reset.';

create or replace function hsf_transfer_claim(p_limit int)
returns setof hsf_upload
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text := hsf_transfer_mode();
  v_limit int := greatest(1, least(coalesce(p_limit, 10), 100));
begin
  if v_mode = 'hold' then
    -- Hold: only fresh uploads that passed the scan; the worker records each as
    -- held and sends nothing.
    return query
      select u.*
        from hsf_upload u
       where u.status = 'uploaded'
         and u.scan_status = 'clean'
         and u.storage_path is not null
         and u.transfer_blocked_reason is null
         and hsf_consent_current(u.client_account_id, 'mco_transfer')
         and hsf_consent_current(u.client_account_id, 'document_storage')
       order by u.uploaded_at nulls last, u.created_at, u.id
       limit v_limit
       for update of u skip locked;
    return;
  end if;
  -- Fixture or live: uploaded and held rows, and transferring rows whose claim
  -- is more than 30 minutes old (a worker that stopped part way), all clean.
  -- Rows another worker has locked are skipped; the claimed rows move to
  -- transferring.
  return query
    with c as (
      select u.id
        from hsf_upload u
       where u.storage_path is not null
         and u.scan_status = 'clean'
         and u.transfer_blocked_reason is null
         and (u.status in ('uploaded','held')
              or (u.status = 'transferring'
                  and (u.transfer_claimed_at is null or u.transfer_claimed_at < now() - interval '30 minutes')))
         and hsf_consent_current(u.client_account_id, 'mco_transfer')
         and hsf_consent_current(u.client_account_id, 'document_storage')
       order by u.uploaded_at nulls last, u.created_at, u.id
       limit v_limit
       for update of u skip locked
    ), claimed as (
      update hsf_upload u
         set status = 'transferring', transfer_claimed_at = now()
        from c
       where u.id = c.id
      returning u.*
    )
    select * from claimed order by uploaded_at nulls last, created_at, id;
end;
$$;
comment on function hsf_transfer_claim is 'Contract 9.5 and 10.4. The worker''s claim, oldest first, at most 100, of uploads that passed the security scan (scan_status clean) only. Mode hold: uploaded rows only (the worker records them held). Mode fixture or live: uploaded and held rows plus transferring rows claimed more than 30 minutes ago, locked with for update skip locked and moved to transferring. Blocked uploads and accounts without mco_transfer and document_storage consent are never returned.';

create or replace function hsf_transfer_record(
  p_upload_id uuid, p_mode text, p_outcome text, p_server_sha256 text,
  p_mco_ref text, p_receipt_sha256 text, p_error text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_server text := nullif(lower(btrim(coalesce(p_server_sha256, ''))), '');
  v_receipt text := nullif(lower(btrim(coalesce(p_receipt_sha256, ''))), '');
  v_ref text := nullif(btrim(coalesce(p_mco_ref, '')), '');
  v_error text := nullif(left(btrim(coalesce(p_error, '')), 500), '');
  v_outcome text := p_outcome;
  v_status text;
  v_revoked int := 0;
begin
  if p_mode is null or p_mode not in ('hold','fixture','live') then
    raise exception 'Unknown transfer mode: %', coalesce(p_mode, 'none');
  end if;
  if p_outcome is null or p_outcome not in ('held','received','hash_mismatch','error') then
    raise exception 'Unknown transfer outcome: %', coalesce(p_outcome, 'none');
  end if;
  if v_server is not null and v_server !~ '^[0-9a-f]{64}$' then
    raise exception 'The server fingerprint must be 64 hexadecimal characters.';
  end if;
  if v_receipt is not null and v_receipt !~ '^[0-9a-f]{64}$' then
    raise exception 'The receipt fingerprint must be 64 hexadecimal characters.';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'The MyClinicOnline reference is too long.';
  end if;

  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.';
  end if;
  if v_up.status in ('client_deleted','expired') and p_outcome = 'received' and p_mode <> 'hold'
     and v_ref is not null and v_server is not null and v_receipt is not null
     and v_server = v_up.sha256_client and v_receipt = v_up.sha256_client then
    -- A transfer that was in flight when the client deleted the document (or the
    -- two year limit took it): MyClinicOnline now holds a copy Care Net must not
    -- lose track of. The receipt and reference are kept and the audit event asks
    -- for the deletion at MyClinicOnline; the status stays, so the worker keeps
    -- nothing and the cleanup queue removes any bytes still staged.
    update hsf_upload set mco_document_ref = v_ref, transfer_claimed_at = null where id = v_up.id;
    insert into hsf_mco_transfer (upload_id, mode, outcome, mco_document_ref, mco_receipt_sha256, error)
    values (v_up.id, p_mode, 'received', v_ref, v_receipt,
            'Received by MyClinicOnline after the document was ' || replace(v_up.status, '_', ' ')
            || ' in Care Net staging. Ask MyClinicOnline to delete it.');
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_transfer_received_after_deletion',
            jsonb_build_object('upload_id', v_up.id, 'mode', p_mode, 'status', v_up.status,
                               'mco_document_ref', v_ref, 'sha256', v_up.sha256_client,
                               'action_needed', 'Ask MyClinicOnline to delete this document.'),
            v_up.file_id);
    return jsonb_build_object('upload_id', v_up.id, 'outcome', 'received', 'status', v_up.status,
                              'mco_document_ref', v_ref, 'mco_deletion_needed', true);
  end if;
  if v_up.status not in ('uploaded','held','transferring') then
    raise exception 'The upload is not waiting for transfer (status %).', v_up.status;
  end if;

  if p_outcome = 'received' then
    if p_mode = 'hold' then
      raise exception 'A held transfer cannot be recorded as received.';
    end if;
    if v_ref is null then
      raise exception 'A received transfer needs the MyClinicOnline reference.';
    end if;
    if v_server is null or v_receipt is null
       or v_server <> v_up.sha256_client or v_receipt <> v_up.sha256_client then
      -- The database runs the same check as the worker: without three matching
      -- fingerprints the transfer is a mismatch and the staging copy is kept.
      v_outcome := 'hash_mismatch';
      v_error := coalesce(v_error, 'Reported as received, but the browser, server and receipt fingerprints do not all match.');
    end if;
  end if;

  -- Contract 10.4: nothing is held or handed to MyClinicOnline before it has
  -- passed the security scan. A mismatch or an error may still be recorded.
  if v_outcome in ('held','received') and v_up.scan_status <> 'clean' then
    raise exception 'The upload has not passed the security scan (scan %).', v_up.scan_status;
  end if;

  if v_outcome = 'held' then
    v_status := 'held';
    update hsf_upload
       set status = 'held', sha256_server = coalesce(v_server, sha256_server), transfer_claimed_at = null
     where id = v_up.id;
  elsif v_outcome = 'received' then
    v_status := 'transferred';
    update hsf_upload
       set status = 'transferred', sha256_server = v_server, mco_document_ref = v_ref,
           transferred_at = now(), verified_at = coalesce(verified_at, now()), transfer_claimed_at = null
     where id = v_up.id;
    update hsf_evidence
       set mco_document_ref = v_ref, transferred_at = now()
     where upload_id = v_up.id and mco_document_ref is null and transferred_at is null;
  elsif v_outcome = 'hash_mismatch' then
    v_status := 'failed';
    update hsf_upload
       set status = 'failed', sha256_server = coalesce(v_server, sha256_server),
           reject_reason = coalesce(v_error, 'The fingerprints do not match.'), transfer_claimed_at = null
     where id = v_up.id;
    -- Bytes that failed the fingerprint check are not evidence (contract 9.5).
    v_revoked := hsf_revoke_upload_evidence(v_up.id);
  else
    -- An error returns the upload to uploaded, to be claimed again (contract 9.5).
    v_status := 'uploaded';
    update hsf_upload set status = 'uploaded', transfer_claimed_at = null where id = v_up.id;
  end if;

  insert into hsf_mco_transfer (upload_id, mode, outcome, mco_document_ref, mco_receipt_sha256, error)
  values (v_up.id, p_mode, v_outcome, v_ref, v_receipt, v_error);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values ('hsf-mco-transfer', 'hsf_transfer_recorded',
          jsonb_build_object('upload_id', v_up.id, 'mode', p_mode, 'reported_outcome', p_outcome,
                             'outcome', v_outcome, 'status', v_status, 'mco_document_ref', v_ref,
                             'evidence_revoked', v_revoked),
          v_up.file_id);

  return jsonb_build_object('upload_id', v_up.id, 'outcome', v_outcome, 'status', v_status,
                            'mco_document_ref', case when v_status = 'transferred' then v_ref end);
end;
$$;
comment on function hsf_transfer_record is 'Contract 049, 9.5 and 10.4. Accepts an upload that is uploaded, held or transferring. Appends hsf_mco_transfer and moves the upload: held to held; received with server, browser and receipt fingerprints equal to transferred (and the matching hsf_evidence row gains its MyClinicOnline fields); a mismatch to failed with the reason, withdrawing its evidence through hsf_revoke_upload_evidence; an error back to uploaded. held and received are refused for an upload that has not passed the security scan. A received with three matching fingerprints for an upload the client deleted (or the two year limit expired) while it was in flight keeps the MyClinicOnline reference and receipt, leaves the status, and is audited as hsf_transfer_received_after_deletion so the deletion at MyClinicOnline can be asked for. Audited.';

-- 9. Two year limit, cleanup and what the client and staff see -----------------------------------

create or replace function hsf_retention_queue(p_limit int)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('upload_id', q.id, 'storage_path', q.storage_path, 'reason', 'retention')
                            order by q.since, q.id), '[]'::jsonb)
    from (select u.id, u.storage_path, coalesce(u.uploaded_at, u.created_at) as since
            from hsf_upload u
           where u.storage_path is not null
             -- Transferred and client deleted bytes already leave through the
             -- cleanup queue. Blocked uploads are included on purpose: the two
             -- year limit overrides a block.
             and u.status not in ('transferred','client_deleted','expired','staging_deleted')
             -- Not while a transfer is in flight: MyClinicOnline may already hold it.
             and not (u.status = 'transferring' and u.transfer_claimed_at >= now() - interval '30 minutes')
             and coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days => hsf_staging_retention_days())
           order by coalesce(u.uploaded_at, u.created_at), u.id
           limit greatest(1, least(coalesce(p_limit, 10), 100))) q;
$$;
comment on function hsf_retention_queue is 'Contract 10.3. Staged bytes older than hsf.staging_retention_days (two years), oldest first, at most 100: {upload_id, storage_path, reason: retention}. Uploads blocked by a consent withdrawal or a revoked verification are included: the two year limit overrides a block. A transfer in flight (transferring, claimed in the last 30 minutes) waits. The worker deletes the object through the Storage API and then calls hsf_mark_expired.';

create or replace function hsf_mark_expired(p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_days int := hsf_staging_retention_days();
  v_revoked int := 0;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.' using errcode = 'P0002';
  end if;
  if v_up.storage_path is null or v_up.status in ('transferred','client_deleted','expired','staging_deleted') then
    raise exception 'That upload holds no bytes under the staging limit (status %).', v_up.status;
  end if;
  if coalesce(v_up.uploaded_at, v_up.created_at) >= now() - make_interval(days => v_days) then
    raise exception 'That upload has not reached the % day staging limit.', v_days;
  end if;
  if v_up.status = 'transferring' and v_up.transfer_claimed_at >= now() - interval '30 minutes' then
    raise exception 'That upload is being transferred to MyClinicOnline. Try again after the transfer.';
  end if;
  update hsf_upload
     set status = 'expired', storage_path = null, staging_deleted_at = now(), transfer_claimed_at = null
   where id = v_up.id;
  v_revoked := hsf_revoke_upload_evidence(v_up.id);
  update hsf_evidence
     set staging_deleted_at = now(), storage_path = null
   where upload_id = v_up.id and staging_deleted_at is null;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values ('hsf-mco-transfer', 'hsf_upload_expired',
          jsonb_build_object('upload_id', v_up.id, 'status_before', v_up.status, 'retention_days', v_days,
                             'transfer_blocked_reason', v_up.transfer_blocked_reason,
                             'sha256', v_up.sha256_client, 'evidence_revoked', v_revoked),
          v_up.file_id);
  return jsonb_build_object('upload_id', v_up.id, 'status', 'expired', 'evidence_revoked', v_revoked);
end;
$$;
comment on function hsf_mark_expired is 'Contract 10.3. After the worker has deleted the bytes of an upload listed by hsf_retention_queue: status expired, storage_path cleared, staging_deleted_at set (on the upload and its evidence rows), the evidence withdrawn through hsf_revoke_upload_evidence. Refused for an upload younger than the limit. The row and its fingerprints stay. Audited as hsf_upload_expired.';

create or replace function hsf_mark_staging_deleted(p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_status text;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.';
  end if;
  if v_up.status not in ('transferred','failed','rejected','client_deleted','expired') then
    raise exception 'Only a transferred, failed, rejected, client deleted or expired upload can be removed from staging (status %).', v_up.status;
  end if;
  if v_up.storage_path is null then
    raise exception 'The staging copy of this upload has already been removed.';
  end if;
  v_status := case when v_up.status = 'transferred' then 'staging_deleted' else v_up.status end;
  update hsf_upload
     set status = v_status, storage_path = null, staging_deleted_at = now()
   where id = v_up.id;
  update hsf_evidence
     set staging_deleted_at = now(), storage_path = null
   where upload_id = v_up.id and staging_deleted_at is null;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values ('hsf-mco-transfer', 'hsf_staging_deleted',
          jsonb_build_object('upload_id', v_up.id, 'status', v_status, 'mco_document_ref', v_up.mco_document_ref),
          v_up.file_id);
  return jsonb_build_object('upload_id', v_up.id, 'status', v_status);
end;
$$;
comment on function hsf_mark_staging_deleted is 'Contract 049, 9.5, 10.3 and 10.5. After the worker has removed the bytes through the Storage API: transferred becomes staging_deleted; failed, rejected, client_deleted and expired keep their status. storage_path is cleared and staging_deleted_at set on the upload and its evidence row. The row and both fingerprints stay. Audited.';

create or replace function hsf_transfer_cleanup_queue(p_limit int)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('upload_id', q.id, 'storage_path', q.storage_path, 'reason', q.status)
                            order by q.since, q.id), '[]'::jsonb)
    from (select u.id, u.storage_path, u.status,
                 coalesce(u.transferred_at, u.uploaded_at, u.created_at) as since
            from hsf_upload u
           where u.storage_path is not null
             -- After a consent withdrawal or a revoked verification no document
             -- is deleted automatically: a blocked upload's bytes wait for the
             -- client's deletion or the two year limit. Transferred and client
             -- deleted bytes, bytes that never completed and bytes the scan
             -- rejected go, blocked or not (hsf_upload_awaits_cleanup).
             and hsf_upload_awaits_cleanup(u.status, u.transfer_blocked_reason, u.uploaded_at, u.scan_status)
           order by coalesce(u.transferred_at, u.uploaded_at, u.created_at), u.id
           limit greatest(1, least(coalesce(p_limit, 10), 100))) q;
$$;
comment on function hsf_transfer_cleanup_queue is 'Contract 9.5 and 10.5. Staged bytes to remove, oldest first, at most 100: {upload_id, storage_path, reason} where reason is the status: transferred (the copy at MyClinicOnline is confirmed), failed, rejected (including a failed security scan) or client_deleted. A blocked upload is left out unless it was transferred or client deleted, never completed, or failed the security scan (hsf_upload_awaits_cleanup). The worker deletes the object through the Storage API and then calls hsf_mark_staging_deleted.';

-- Staging alerts (contract 9.5 and 10.3): the 049 view with expires_on and
-- scan_exhausted added as its last columns, now also listing uploads within 30
-- days of the two year limit and uploads whose security scan used all five
-- attempts (staff give them a fresh start with hsf_scan_reset).
create or replace view hsf_staging_alerts as
select u.id as upload_id,
       u.client_account_id,
       a.company_name,
       u.file_id,
       u.status,
       u.department_code,
       u.section_code,
       u.size_bytes,
       coalesce(u.uploaded_at, u.created_at) as staged_since,
       floor(extract(epoch from now() - coalesce(u.uploaded_at, u.created_at)) / 86400)::int as days_in_staging,
       u.transfer_blocked_reason,
       (coalesce(u.uploaded_at, u.created_at) + make_interval(days =>
          least(730, greatest(1, coalesce((select p.value::int from msp_env_parameter p where p.key = 'hsf.staging_retention_days'), 730)))))::date
         as expires_on,
       (u.status = 'uploaded' and u.scan_status = 'error' and u.scan_attempts >= 5) as scan_exhausted
  from hsf_upload u
  join msp_client_account a on a.id = u.client_account_id
 where u.storage_path is not null
   and u.status <> 'awaiting_upload'
   and (coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days =>
          coalesce((select p.value::int from msp_env_parameter p where p.key = 'hsf.staging_alert_days'), 14))
        or coalesce(u.uploaded_at, u.created_at) + make_interval(days =>
          least(730, greatest(1, coalesce((select p.value::int from msp_env_parameter p where p.key = 'hsf.staging_retention_days'), 730))))
          < now() + interval '30 days'
        or (u.status = 'uploaded' and u.scan_status = 'error' and u.scan_attempts >= 5))
   and hsf_is_staff();
comment on view hsf_staging_alerts is 'Contract 9.5 and 10.3. Uploads holding bytes in the hsf-staging bucket for longer than hsf.staging_alert_days, or within 30 days of the two year limit, or whose security scan ended in an error five times (scan_exhausted, cleared with hsf_scan_reset), with the date the bytes expire (expires_on). Staff only (forge_admin, forge_omp, forge_safety_reviewer); nobody else sees a row. No file names.';
revoke all on hsf_staging_alerts from public, anon, authenticated;
grant select on hsf_staging_alerts to authenticated;

create or replace function hsf_staging_alerts_list()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'upload_id', u.id, 'client_account_id', u.client_account_id, 'company_name', a.company_name,
           'file_id', u.file_id, 'status', u.status, 'department_code', u.department_code,
           'section_code', u.section_code, 'size_bytes', u.size_bytes,
           'staged_since', coalesce(u.uploaded_at, u.created_at),
           'days_in_staging', floor(extract(epoch from now() - coalesce(u.uploaded_at, u.created_at)) / 86400)::int,
           'transfer_blocked_reason', u.transfer_blocked_reason,
           'expires_on', (coalesce(u.uploaded_at, u.created_at) + make_interval(days => r.days))::date,
           'scan_exhausted', (u.status = 'uploaded' and u.scan_status = 'error' and u.scan_attempts >= 5))
         order by coalesce(u.uploaded_at, u.created_at), u.id), '[]'::jsonb)
    from hsf_upload u
    join msp_client_account a on a.id = u.client_account_id
    cross join (select hsf_staging_retention_days() as days) r
   where u.storage_path is not null
     and u.status <> 'awaiting_upload'
     and (coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days =>
            coalesce(msp_env_get_int('hsf.staging_alert_days'), 14))
          or coalesce(u.uploaded_at, u.created_at) + make_interval(days => r.days) < now() + interval '30 days'
          or (u.status = 'uploaded' and u.scan_status = 'error' and u.scan_attempts >= 5));
$$;
comment on function hsf_staging_alerts_list is 'Contract 9.5 and 10.3. The rows of hsf_staging_alerts for the service role (scheduled alerts), oldest first, with expires_on and scan_exhausted.';

create or replace function hsf_my_uploads(p_auth_user uuid, p_file_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'upload_id', u.id,
           'file_id', u.file_id,
           'original_name', u.original_name,
           'department_code', u.department_code,
           'section_code', u.section_code,
           'element_code', e.code,
           'size_bytes', u.size_bytes,
           'mime_type', u.mime_type,
           'status', u.status,
           'reject_reason', u.reject_reason,
           'transfer_blocked_reason', u.transfer_blocked_reason,
           'scan_status', u.scan_status,
           'scanned_at', u.scanned_at,
           'deletable', hsf_upload_deletable(u.status, u.storage_path, u.transfer_claimed_at),
           -- Only for bytes that stay until the client deletes them or the limit;
           -- bytes the cleanup queue removes on its next run have no such date.
           'expires_on', case when u.storage_path is not null
                               and u.status not in ('transferred','staging_deleted','expired','client_deleted')
                               and not hsf_upload_awaits_cleanup(u.status, u.transfer_blocked_reason, u.uploaded_at, u.scan_status)
                              then (coalesce(u.uploaded_at, u.created_at) + make_interval(days => r.days))::date end,
           'created_at', u.created_at,
           'uploaded_at', u.uploaded_at,
           'transferred_at', u.transferred_at,
           'staging_deleted_at', u.staging_deleted_at,
           'mco_document_ref', u.mco_document_ref)
         order by u.created_at desc, u.id), '[]'::jsonb)
    from hsf_upload u
    join msp_client_account a on a.id = u.client_account_id
    cross join (select hsf_staging_retention_days() as days) r
    left join hsf_file_item fi on fi.id = u.file_item_id
    left join hsf_element e on e.id = fi.element_id
   where p_auth_user is not null
     and a.auth_user_id = p_auth_user
     and (p_file_id is null or u.file_id = p_file_id);
$$;
comment on function hsf_my_uploads is 'Contract 049, 10.3 to 10.6. The uploads of the auth user''s company account, newest first, optionally for one File, with the scan state, why an upload is blocked, whether the client may still delete it (not while a transfer is in flight), and expires_on (the date its bytes leave Care Net staging under the two year limit) while it is held in staging and not waiting for the cleanup queue.';

-- 10. Deletion by the client (contract 10.5) --------------------------------------------------------

create or replace function hsf_deletion_request_create(p_auth_user uuid, p_upload_ids uuid[], p_channel text, p_acknowledged boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_ids uuid[];
  v_email text;
  v_phone text;
  v_phone_ok boolean;
  v_hint text;
  v_recent int;
  v_ok int;
  v_row hsf_deletion_request;
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'No company account is linked to this sign in.';
  end if;
  if p_acknowledged is distinct from true then
    raise exception 'Tick that you understand deleting cannot be undone before asking for a PIN.';
  end if;
  if p_channel is null or p_channel not in ('email','sms') then
    raise exception 'Choose email or SMS for the PIN.';
  end if;

  select nullif(btrim(u.email), ''), nullif(btrim(to_jsonb(u) ->> 'phone'), ''),
         (to_jsonb(u) ->> 'phone_confirmed_at') is not null
    into v_email, v_phone, v_phone_ok
    from auth.users u where u.id = p_auth_user;
  if p_channel = 'email' then
    if v_email is null then
      raise exception 'This sign in has no email address for the PIN.';
    end if;
    -- The first character and the domain only, for example f***@example.co.za.
    v_hint := left(v_email, 1) || '***@' || split_part(v_email, '@', 2);
  else
    if not coalesce(msp_env_get_bool('hsf.deletion_sms_enabled'), false)
       or v_phone is null or not coalesce(v_phone_ok, false) then
      raise exception 'A PIN by SMS is not available for this sign in. Choose email.';
    end if;
    v_hint := 'number ending ' || right(regexp_replace(v_phone, '[^0-9]', '', 'g'), 4);
  end if;

  select array_agg(distinct x order by x) into v_ids from unnest(coalesce(p_upload_ids, '{}'::uuid[])) x where x is not null;
  if v_ids is null then
    raise exception 'Choose at least one document to delete.';
  end if;
  if cardinality(v_ids) > 50 then
    raise exception 'Delete at most 50 documents at a time.';
  end if;
  -- Only the account's own uploads whose bytes are still in Care Net staging. A
  -- document of another account and one that does not exist read the same.
  select count(*) into v_ok
    from hsf_upload u
   where u.id = any(v_ids) and u.client_account_id = v_acc.id
     and hsf_upload_deletable(u.status, u.storage_path, u.transfer_claimed_at);
  if v_ok <> cardinality(v_ids) then
    raise exception 'One or more of the chosen documents cannot be deleted here. A document that has moved to MyClinicOnline is deleted through MyClinicOnline, and a document being moved there now can be deleted again once the move has finished or stopped.';
  end if;

  -- Each request sends a PIN, so an account may ask at most 5 times an hour.
  -- SQLSTATE PT429 is the rate limit refusal (429 at the API).
  perform pg_advisory_xact_lock(hashtext('hsf_deletion_request'), hashtext(v_acc.id::text));
  select count(*) into v_recent
    from hsf_deletion_request r
   where r.client_account_id = v_acc.id and r.requested_at > now() - interval '1 hour';
  if v_recent >= 5 then
    raise exception 'Too many deletion requests in the last hour. Please try again later.' using errcode = 'PT429';
  end if;

  -- A new PIN replaces the last one, so earlier open requests are cancelled.
  update hsf_deletion_request set status = 'cancelled'
   where client_account_id = v_acc.id and status = 'pending';

  insert into hsf_deletion_request (client_account_id, auth_user_id, upload_ids, channel, acknowledged_irreversible,
                                    requested_at, expires_at)
  values (v_acc.id, p_auth_user, v_ids, p_channel, true, now(), now() + interval '10 minutes')
  returning * into v_row;

  insert into msp_audit (actor, event_type, event_detail)
  values (coalesce(v_email, 'client'), 'hsf_deletion_requested',
          jsonb_build_object('request_id', v_row.id, 'client_account_id', v_acc.id, 'channel', p_channel,
                             'upload_ids', to_jsonb(v_ids)));

  return jsonb_build_object('request_id', v_row.id, 'expires_at', v_row.expires_at, 'channel', v_row.channel,
                            'destination_hint', v_hint);
end;
$$;
comment on function hsf_deletion_request_create is 'Contract 10.5. Opens a deletion request after the client has read the warning and ticked that it cannot be undone. Every upload must be the account''s own and still held in Care Net staging (hsf_upload_deletable); at most 50; at most 5 requests per account per hour (SQLSTATE PT429 beyond that). SMS only when hsf.deletion_sms_enabled and the sign in has a confirmed phone. Earlier open requests are cancelled. Returns {request_id, expires_at, channel, destination_hint}; the server then asks Supabase Auth to send the PIN. Audited as hsf_deletion_requested.';

create or replace function hsf_deletion_request_pin_sent(p_auth_user uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row hsf_deletion_request;
begin
  select r.* into v_row from hsf_deletion_request r where r.id = p_request_id for update;
  if v_row.id is null or p_auth_user is null or v_row.auth_user_id <> p_auth_user then
    raise exception 'That deletion request was not found.' using errcode = 'P0002';
  end if;
  if v_row.status <> 'pending' or v_row.expires_at <= now() or v_row.pin_sent_at is not null then
    raise exception 'This deletion request is no longer open. Start again to receive a new PIN.';
  end if;
  update hsf_deletion_request set pin_sent_at = now() where id = v_row.id returning * into v_row;
  return jsonb_build_object('request_id', v_row.id, 'pin_sent_at', v_row.pin_sent_at);
end;
$$;
comment on function hsf_deletion_request_pin_sent is 'Contract 10.5. Called by the server only after Supabase Auth accepted the request to send the PIN for this deletion request: records pin_sent_at, without which no PIN attempt is counted and nothing is confirmed. Once per request.';

create or replace function hsf_deletion_request_cancel(p_auth_user uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row hsf_deletion_request;
begin
  select r.* into v_row from hsf_deletion_request r where r.id = p_request_id for update;
  if v_row.id is null or p_auth_user is null or v_row.auth_user_id <> p_auth_user then
    raise exception 'That deletion request was not found.' using errcode = 'P0002';
  end if;
  if v_row.status = 'pending' then
    update hsf_deletion_request set status = 'cancelled' where id = v_row.id returning * into v_row;
    insert into msp_audit (actor, event_type, event_detail)
    values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_deletion_request_cancelled',
            jsonb_build_object('request_id', v_row.id, 'client_account_id', v_row.client_account_id));
  end if;
  return jsonb_build_object('request_id', v_row.id, 'status', v_row.status);
end;
$$;
comment on function hsf_deletion_request_cancel is 'Contract 10.5. Cancels the caller''s pending deletion request, for example when Supabase Auth could not send its PIN, so a request whose PIN never went out can never be confirmed. Audited as hsf_deletion_request_cancelled.';

create or replace function hsf_deletion_request_attempt(p_auth_user uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row hsf_deletion_request;
  v_acc uuid;
begin
  -- The account lock first, in the same order as hsf_deletion_request_create
  -- (advisory lock, then rows), so the two never wait on each other.
  select r.client_account_id into v_acc from hsf_deletion_request r where r.id = p_request_id;
  if v_acc is not null then
    perform pg_advisory_xact_lock(hashtext('hsf_deletion_request'), hashtext(v_acc::text));
  end if;
  select r.* into v_row from hsf_deletion_request r where r.id = p_request_id for update;
  if v_row.id is null or p_auth_user is null or v_row.auth_user_id <> p_auth_user then
    raise exception 'That deletion request was not found.' using errcode = 'P0002';
  end if;
  if v_row.status = 'pending' and v_row.expires_at <= now() then
    update hsf_deletion_request set status = 'expired' where id = v_row.id returning * into v_row;
  elsif v_row.status = 'pending' and v_row.pin_sent_at is null then
    -- No PIN went out for this request, so no PIN can be checked against it.
    return jsonb_build_object('allowed', false, 'attempts_left', greatest(0, 5 - v_row.attempts), 'status', 'pin_not_sent');
  elsif v_row.status = 'pending' and v_row.attempts >= 5 then
    update hsf_deletion_request set status = 'locked' where id = v_row.id returning * into v_row;
    insert into msp_audit (actor, event_type, event_detail)
    values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_deletion_request_locked',
            jsonb_build_object('request_id', v_row.id, 'client_account_id', v_row.client_account_id));
  elsif v_row.status = 'pending' then
    -- Also counted per account: a new request within the hour does not bring a
    -- fresh set of guesses. At most 10 PIN attempts per account per hour.
    if (select coalesce(sum(r.attempts), 0) from hsf_deletion_request r
         where r.client_account_id = v_row.client_account_id
           and r.requested_at > now() - interval '1 hour') >= 10 then
      return jsonb_build_object('allowed', false, 'attempts_left', greatest(0, 5 - v_row.attempts), 'status', 'rate_limited');
    end if;
    -- Counted before the server asks Supabase Auth to check the PIN.
    update hsf_deletion_request set attempts = attempts + 1 where id = v_row.id returning * into v_row;
    return jsonb_build_object('allowed', true, 'attempts_left', 5 - v_row.attempts, 'status', v_row.status);
  end if;
  return jsonb_build_object('allowed', false, 'attempts_left', greatest(0, 5 - v_row.attempts), 'status', v_row.status);
end;
$$;
comment on function hsf_deletion_request_attempt is 'Contract 10.5. Counts one PIN attempt on the caller''s pending request before the server asks Supabase Auth to verify it. Returns {allowed, attempts_left, status}. After 10 minutes the request reads expired; after 5 attempts the next one locks it. A request whose PIN was never sent answers status pin_not_sent, and an account with 10 attempts in the last hour answers status rate_limited; neither counts an attempt. A request of another person raises P0002.';

create or replace function hsf_deletion_request_confirm(p_auth_user uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row hsf_deletion_request;
  v_up hsf_upload;
  v_email text := coalesce(hsf_user_email(p_auth_user), 'client');
  v_revoked int;
  v_n int := 0;
begin
  select r.* into v_row from hsf_deletion_request r where r.id = p_request_id for update;
  if v_row.id is null or p_auth_user is null or v_row.auth_user_id <> p_auth_user then
    raise exception 'That deletion request was not found.' using errcode = 'P0002';
  end if;
  if v_row.status <> 'pending' or v_row.expires_at <= now() then
    raise exception 'This deletion request is no longer open. Start again to receive a new PIN.';
  end if;
  if v_row.pin_sent_at is null or v_row.attempts < 1 then
    -- The server sends this request's PIN, counts an attempt and verifies the
    -- PIN before it confirms.
    raise exception 'The PIN has not been checked for this deletion request.';
  end if;

  -- Every document must still be deletable; otherwise nothing is deleted.
  perform 1 from hsf_upload u where u.id = any(v_row.upload_ids) order by u.id for update;
  if (select count(*) from hsf_upload u
       where u.id = any(v_row.upload_ids) and u.client_account_id = v_row.client_account_id
         and hsf_upload_deletable(u.status, u.storage_path, u.transfer_claimed_at)) <> cardinality(v_row.upload_ids) then
    raise exception 'One or more of the chosen documents can no longer be deleted here. Start again.';
  end if;

  for v_up in select u.* from hsf_upload u where u.id = any(v_row.upload_ids) order by u.id loop
    update hsf_upload
       set status = 'client_deleted', transfer_blocked_reason = null, transfer_claimed_at = null
     where id = v_up.id;
    v_revoked := hsf_revoke_upload_evidence(v_up.id);
    -- The fingerprints, never the bytes or the file name.
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values (v_email, 'hsf_upload_client_deleted',
            jsonb_build_object('upload_id', v_up.id, 'request_id', v_row.id, 'status_before', v_up.status,
                               'sha256_client', v_up.sha256_client, 'sha256_server', v_up.sha256_server,
                               'evidence_revoked', v_revoked),
            v_up.file_id);
    v_n := v_n + 1;
  end loop;

  update hsf_deletion_request set status = 'confirmed', confirmed_at = now() where id = v_row.id;
  return jsonb_build_object('request_id', v_row.id, 'status', 'confirmed', 'deleted', v_n,
                            'upload_ids', to_jsonb(v_row.upload_ids));
end;
$$;
comment on function hsf_deletion_request_confirm is 'Contract 10.5. Called only after the server has verified the PIN with Supabase Auth. The caller''s request must be pending, unexpired, have had its PIN sent (pin_sent_at) and be attempted. Every chosen upload becomes client_deleted (block cleared, so the cleanup queue removes its bytes), its evidence is withdrawn through hsf_revoke_upload_evidence and the compliance figure recomputed. All or nothing. Audited per upload as hsf_upload_client_deleted with the fingerprints, never the bytes.';

-- 11. Execute rights --------------------------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'hsf_staging_retention_days()',
    'hsf_upload_deletable(text, text, timestamptz)',
    'hsf_upload_awaits_cleanup(text, text, timestamptz, text)',
    'hsf_revoke_upload_evidence(uuid)',
    'hsf_client_verified(uuid)',
    'hsf_request_client_verification(uuid)',
    'hsf_upload_gate(uuid)',
    'hsf_register_upload(uuid, jsonb)',
    'hsf_scan_claim(int)',
    'hsf_scan_record(uuid, text, text, jsonb)',
    'hsf_transfer_claim(int)',
    'hsf_transfer_record(uuid, text, text, text, text, text, text)',
    'hsf_retention_queue(int)',
    'hsf_mark_expired(uuid)',
    'hsf_mark_staging_deleted(uuid)',
    'hsf_transfer_cleanup_queue(int)',
    'hsf_staging_alerts_list()',
    'hsf_my_uploads(uuid, uuid)',
    'hsf_deletion_request_create(uuid, uuid[], text, boolean)',
    'hsf_deletion_request_pin_sent(uuid, uuid)',
    'hsf_deletion_request_cancel(uuid, uuid)',
    'hsf_deletion_request_attempt(uuid, uuid)',
    'hsf_deletion_request_confirm(uuid, uuid)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- Verify, revoke and the scan reset: the service role, or signed in forge staff
-- (checked in the body).
revoke execute on function hsf_verify_client(uuid, text, text) from public, anon;
revoke execute on function hsf_revoke_client_verification(uuid, text) from public, anon;
revoke execute on function hsf_scan_reset(uuid) from public, anon;
grant execute on function hsf_verify_client(uuid, text, text) to authenticated, service_role;
grant execute on function hsf_revoke_client_verification(uuid, text) to authenticated, service_role;
grant execute on function hsf_scan_reset(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 053_hsf_signoff_rule.sql
------------------------------------------------------------------------------

-- CNC MSP FORGE | HSF-REV-02 v1.0.0 | HSF File sign off: who may sign, and what release checks 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 10.8, with hsf/SIGNOFF-CRITERIA.md
-- sections 3 to 6 as the rule. Amends SPEC B4.5 (review and release).
--
-- What this migration does:
--   1. The Occupational Medical Practitioner is no longer a File signatory
--      (SIGNOFF-CRITERIA 2.4, 3.1, 3.2). The value omp_medical stays allowed in
--      the kind check so earlier rows keep their history, but a new omp_medical
--      row is refused: the OMP signed medical surveillance plan is Section E
--      evidence, not a sign off. The release gate no longer asks for it.
--   2. New kind ceo_16_1_acknowledgement: the chief executive's acknowledgement,
--      recorded and never a release gate (SIGNOFF-CRITERIA 3.3, section 4).
--   3. hsf_signatory: the credential record of a safety content signatory
--      (SIGNOFF-CRITERIA 6.1 and 6.1.1). A safety_content sign off references
--      it through hsf_signoff.signatory_id; the sign off keeps its own scope.
--   4. hsf_signoff_rule: which registering body and category may sign the
--      safety content of a File, by industry (SIGNOFF-CRITERIA section 5).
--   5. hsf_signatory_fit: the one definition of whether a safety content sign
--      off can release its File (SIGNOFF-CRITERIA 6.2), and hsf_release_gate
--      redefined to use it. The citability rule of 047 and 050 is kept exactly.
--
-- Design choice: a separate hsf_signatory table rather than credential columns
-- on hsf_signoff. The credentials belong to the practitioner, not to one File:
-- one practitioner signs many Files and revisions, and the register check and
-- the two letters are recorded once and reused. A renewal is a new row with its
-- new expiry, and a row relied on by a released revision is frozen, so every
-- release keeps the credentials it was decided on. hsf_signoff stays one narrow
-- row per decision, and the client acceptance and chief executive rows carry no
-- practitioner columns. No identity number is stored (SIGNOFF-CRITERIA 6.3).
--
-- Migrations 047 to 052 are not edited: every changed function is redefined
-- here with create or replace, keeping security definer, the fixed search path
-- and service role only execute. The hsf_release_gate trigger of 047 stays and
-- calls the redefined function.

-- 1. hsf_signatory (SIGNOFF-CRITERIA 6.1, 6.1.1, 6.3) -------------------------------------------

create table hsf_signatory (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(btrim(full_name)) > 0),
  registration_body text not null check (registration_body in ('SACPCMP','SAIOSH')),
  category text not null,
  registration_number text not null check (length(btrim(registration_number)) > 0),
  registration_expires_on date not null,
  register_checked_on date,
  register_proof_ref text,
  appointment_letter_ref text,
  appointment_letter_date date,
  appointment_letter_recruitment_portal_ref text,
  engagement_letter_ref text,
  engagement_letter_date date,
  engagement_letter_recruitment_portal_ref text,
  created_by text not null default 'service_role',
  created_at timestamptz not null default now(),
  constraint hsf_signatory_category_fits_body check (
    (registration_body = 'SACPCMP' and category in ('Pr CHSA','CHSM','CHSO','Can CHSA','Can CHSM','Can CHSO'))
    or (registration_body = 'SAIOSH' and category in ('TechSAIOSH','GradSAIOSH','CMSAIOSH'))),
  constraint hsf_signatory_register_check_pair check ((register_checked_on is null) = (register_proof_ref is null)),
  constraint hsf_signatory_appointment_letter_pair check ((appointment_letter_ref is null) = (appointment_letter_date is null)),
  constraint hsf_signatory_engagement_letter_pair check ((engagement_letter_ref is null) = (engagement_letter_date is null)),
  unique (registration_body, registration_number, registration_expires_on)
);
comment on table hsf_signatory is 'HSF-REV-02, contract 10.8 (SIGNOFF-CRITERIA 6.1, 6.1.1, 6.3). The credential record of a registered health and safety practitioner who signs the safety content of a File: registering body and category, registration number and expiry, the public register check with its saved proof, and the appointment and engagement letters. One row per registration period: a renewal is a new row. A row relied on by a released File revision is frozen (hsf_signatory_guard). No identity number is stored; the registration number identifies the practitioner. Staff read; writes by the service role only.';
comment on column hsf_signatory.full_name is 'The practitioner''s full name as it appears on the register of the body.';
comment on column hsf_signatory.registration_number is 'The registration or membership number with the body. It identifies the practitioner; no identity number is stored (SIGNOFF-CRITERIA 6.3).';
comment on column hsf_signatory.registration_body is 'SACPCMP (the statutory body for construction health and safety) or SAIOSH (a professional body; its designations are voluntary).';
comment on column hsf_signatory.category is 'SACPCMP: Pr CHSA, CHSM, CHSO and the candidate categories Can CHSA, Can CHSM, Can CHSO. SAIOSH: TechSAIOSH, GradSAIOSH, CMSAIOSH. Candidate categories are recorded but never sign a File alone (hsf_signoff_rule lists none).';
comment on column hsf_signatory.registration_expires_on is 'The expiry or renewal date of the registration or designation. A sign off decided after this date cannot release a File.';
comment on column hsf_signatory.register_checked_on is 'The date the public register of the body was checked for this registration. Must be on or before the decision date of a sign off that releases a File.';
comment on column hsf_signatory.register_proof_ref is 'Reference to the saved proof of the register check (for example a stored screenshot or PDF). Recorded together with register_checked_on.';
comment on column hsf_signatory.appointment_letter_ref is 'Document reference of the written appointment letter. Recorded together with appointment_letter_date; a missing letter refuses the release.';
comment on column hsf_signatory.appointment_letter_date is 'Date of the appointment letter. Must be on or before the decision date of a sign off that releases a File.';
comment on column hsf_signatory.appointment_letter_recruitment_portal_ref is 'Record identifier of the appointment letter in Care Net''s recruitment portal, once the portal exposes it. Null until then; the letter is uploaded and referenced by hand meanwhile. May be added after a release.';
comment on column hsf_signatory.engagement_letter_ref is 'Document reference of the engagement letter. Recorded together with engagement_letter_date; a missing letter refuses the release.';
comment on column hsf_signatory.engagement_letter_date is 'Date of the engagement letter. Must be on or before the decision date of a sign off that releases a File.';
comment on column hsf_signatory.engagement_letter_recruitment_portal_ref is 'Record identifier of the engagement letter in Care Net''s recruitment portal, once the portal exposes it. Null until then. May be added after a release.';
comment on column hsf_signatory.created_by is 'Who recorded the credentials: a staff email or service_role.';

create or replace function hsf_signatory_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mutable constant text[] := array['appointment_letter_recruitment_portal_ref','engagement_letter_recruitment_portal_ref'];
begin
  -- Only a row relied on by a released revision is frozen; before a release the
  -- credentials may be corrected, because the gate reads them at release time.
  if not exists (select 1
                   from hsf_signoff so
                   join hsf_release r on r.file_id = so.file_id and r.revision = so.revision
                  where so.signatory_id = old.id
                    and so.kind = 'safety_content' and so.decision = 'approved') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'hsf_signatory: these credentials support a released File and cannot be deleted';
  end if;
  if (to_jsonb(new) - v_mutable) is distinct from (to_jsonb(old) - v_mutable) then
    raise exception 'hsf_signatory: these credentials support a released File and are frozen; record a renewal or a correction as a new signatory row';
  end if;
  if (old.appointment_letter_recruitment_portal_ref is not null
      and new.appointment_letter_recruitment_portal_ref is distinct from old.appointment_letter_recruitment_portal_ref)
     or (old.engagement_letter_recruitment_portal_ref is not null
      and new.engagement_letter_recruitment_portal_ref is distinct from old.engagement_letter_recruitment_portal_ref) then
    raise exception 'hsf_signatory: a recruitment portal reference on credentials that support a released File is set once and never changed';
  end if;
  return new;
end;
$$;
revoke execute on function hsf_signatory_guard() from public, anon, authenticated;
comment on function hsf_signatory_guard is 'Contract 10.8. Freezes a hsf_signatory row once an approved safety_content sign off that relies on it has released a File revision: no delete, and no change except adding each recruitment portal reference once. Before a release the row may be corrected.';

create trigger hsf_signatory_guard
  before update or delete on hsf_signatory
  for each row execute function hsf_signatory_guard();
comment on trigger hsf_signatory_guard on hsf_signatory is 'Contract 10.8. Freezes credentials relied on by a released File revision (hsf_signatory_guard).';

-- 2. hsf_signoff: kinds, the signatory reference and the scope -----------------------------------

alter table hsf_signoff drop constraint if exists hsf_signoff_kind_check;
alter table hsf_signoff add constraint hsf_signoff_kind_check check (kind in
  ('omp_medical','safety_content','client_16_2_acceptance','ceo_16_1_acknowledgement'));

alter table hsf_signoff drop constraint if exists decision_complete;
alter table hsf_signoff add constraint decision_complete check (decision is null or
  (signatory_name is not null and decided_at is not null
   and (kind in ('client_16_2_acceptance','ceo_16_1_acknowledgement') or registration_number is not null)));

alter table hsf_signoff
  add column if not exists signatory_id uuid references hsf_signatory(id),
  add column if not exists scope text;
alter table hsf_signoff add constraint hsf_signoff_signatory_is_safety
  check (signatory_id is null or kind = 'safety_content');
alter table hsf_signoff add constraint hsf_signoff_safety_decision_complete
  check (kind <> 'safety_content' or decision is null
         or (signatory_id is not null and length(btrim(coalesce(scope, ''))) > 0));
create index if not exists hsf_signoff_signatory_idx on hsf_signoff(signatory_id);

comment on table hsf_signoff is 'HSF-REV-01, amended by HSF-REV-02 (contract 10.8, SIGNOFF-CRITERIA section 4). The sign offs of a File revision. Release needs an approved safety_content sign off by a registered practitioner whose body and category fit the File (hsf_signoff_rule) and an approved client_16_2_acceptance. ceo_16_1_acknowledgement is recorded, not a gate. omp_medical is kept for history only: new rows are refused, because the OMP signed medical surveillance plan is Section E evidence, not a File sign off.';
comment on column hsf_signoff.kind is 'safety_content (registered practitioner, required), client_16_2_acceptance (the client''s section 16(2) appointee, required), ceo_16_1_acknowledgement (the client''s chief executive, recorded, not a gate). omp_medical: history only, refused for new rows.';
comment on column hsf_signoff.signatory_id is 'Contract 10.8. The credential record (hsf_signatory) of the practitioner who decides a safety_content sign off. Required once a safety_content row carries a decision; only safety_content rows carry it. signatory_name, registration_body and registration_number are copied from it.';
comment on column hsf_signoff.scope is 'SIGNOFF-CRITERIA 6.1. The scope of the sign off in words (for example the sections and sites it covers). Required once a safety_content row carries a decision.';

create or replace function hsf_signoff_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sig hsf_signatory;
begin
  if new.kind = 'omp_medical' and (tg_op = 'INSERT' or old.kind is distinct from 'omp_medical') then
    raise exception 'hsf_signoff: the Occupational Medical Practitioner is not a File signatory. File the OMP signed medical surveillance plan in Section E as evidence instead';
  end if;
  if new.signatory_id is not null then
    select * into v_sig from hsf_signatory where id = new.signatory_id;
    new.signatory_name := v_sig.full_name;
    new.registration_body := v_sig.registration_body;
    new.registration_number := v_sig.registration_number;
  end if;
  return new;
end;
$$;
revoke execute on function hsf_signoff_guard() from public, anon, authenticated;
comment on function hsf_signoff_guard is 'Contract 10.8. Refuses a new omp_medical sign off (the OMP signed plan is Section E evidence) and copies the signatory name, registering body and registration number of a safety_content sign off from its hsf_signatory row, so the two never disagree.';

create trigger hsf_signoff_guard
  before insert or update on hsf_signoff
  for each row execute function hsf_signoff_guard();
comment on trigger hsf_signoff_guard on hsf_signoff is 'Contract 10.8. Refuses new omp_medical sign offs and copies the safety content signatory''s name, body and number (hsf_signoff_guard).';

create or replace function hsf_signatory_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Reached only for a row that is not frozen (hsf_signatory_guard), so every
  -- sign off it touches is of a revision not yet released.
  if (new.full_name, new.registration_body, new.registration_number)
     is distinct from (old.full_name, old.registration_body, old.registration_number) then
    update hsf_signoff
       set signatory_name = new.full_name,
           registration_body = new.registration_body,
           registration_number = new.registration_number
     where signatory_id = new.id;
  end if;
  return null;
end;
$$;
revoke execute on function hsf_signatory_sync() from public, anon, authenticated;
comment on function hsf_signatory_sync is 'Contract 10.8. After a correction to a hsf_signatory row that is not yet frozen, copies the corrected name, body and registration number onto the sign offs that reference it, so hsf_signoff never disagrees with its credential record.';

create trigger hsf_signatory_sync
  after update on hsf_signatory
  for each row execute function hsf_signatory_sync();
comment on trigger hsf_signatory_sync on hsf_signatory is 'Contract 10.8. Keeps the copied signatory fields of unreleased sign offs in step with a corrected credential record (hsf_signatory_sync).';

-- 3. hsf_signoff_rule (SIGNOFF-CRITERIA section 5) -------------------------------------------------

create table hsf_signoff_rule (
  id uuid primary key default gen_random_uuid(),
  file_type text not null check (file_type in ('construction','mining','general')),
  industry_id uuid references msp_industry(id),
  registration_body text not null check (registration_body in ('SACPCMP','SAIOSH')),
  category text not null,
  practitioner_review boolean not null default false,
  note text not null,
  constraint hsf_signoff_rule_general_has_no_industry check ((file_type = 'general') = (industry_id is null)),
  constraint hsf_signoff_rule_no_candidates check (category not like 'Can %'),
  constraint hsf_signoff_rule_category_fits_body check (
    (registration_body = 'SACPCMP' and category in ('Pr CHSA','CHSM','CHSO'))
    or (registration_body = 'SAIOSH' and category in ('TechSAIOSH','GradSAIOSH','CMSAIOSH'))),
  unique nulls not distinct (industry_id, registration_body, category)
);
comment on table hsf_signoff_rule is 'HSF-REV-02, contract 10.8 (SIGNOFF-CRITERIA section 5, a design inference for confirmation by the attorney and a registered practitioner). Which registering body and category may sign the safety content of a File. Rows with an industry apply to Files of that industry; the rows with no industry (file_type general) apply to every industry that has none of its own. Candidate categories are never listed, so they never sign alone.';
comment on column hsf_signoff_rule.file_type is 'construction (the CONSTR industry), mining (the MINING industry) or general (every other industry, industry_id null).';
comment on column hsf_signoff_rule.industry_id is 'The industry the row applies to (msp_industry). Null for the general rows, which apply to every industry without rows of its own.';
comment on column hsf_signoff_rule.registration_body is 'SACPCMP or SAIOSH.';
comment on column hsf_signoff_rule.category is 'A registered category or designation that may sign: SACPCMP Pr CHSA, CHSM, CHSO; SAIOSH CMSAIOSH, GradSAIOSH, TechSAIOSH. Never a candidate category.';
comment on column hsf_signoff_rule.practitioner_review is 'True where the File is a practitioner review and is never presented as a sign off under the mining regime (SIGNOFF-CRITERIA section 5, mining).';
comment on column hsf_signoff_rule.note is 'Why the row is allowed, in words, as SIGNOFF-CRITERIA section 5 gives it.';

insert into hsf_signoff_rule (file_type, industry_id, registration_body, category, practitioner_review, note)
select 'construction', i.id, 'SACPCMP', c.category, false, c.note
  from msp_industry i
  cross join (values
    ('Pr CHSA', 'Registered construction health and safety agent; needed where the client needs a registered agent (construction work permit projects).'),
    ('CHSM', 'Registered construction health and safety manager.'),
    ('CHSO', 'Registered construction health and safety officer.')) as c(category, note)
 where i.code = 'CONSTR';

insert into hsf_signoff_rule (file_type, industry_id, registration_body, category, practitioner_review, note)
select 'mining', i.id, c.body, c.category, true, c.note
  from msp_industry i
  cross join (values
    ('SACPCMP', 'Pr CHSA', 'As general industry; the File is a practitioner review.'),
    ('SACPCMP', 'CHSM', 'As general industry; the File is a practitioner review.'),
    ('SAIOSH', 'CMSAIOSH', 'As general industry; the File is a practitioner review.'),
    ('SAIOSH', 'GradSAIOSH', 'As general industry; the File is a practitioner review.'),
    ('SAIOSH', 'TechSAIOSH', 'As general industry; the File is a practitioner review.')) as c(body, category, note)
 where i.code = 'MINING';

insert into hsf_signoff_rule (file_type, industry_id, registration_body, category, practitioner_review, note) values
  ('general', null, 'SACPCMP', 'Pr CHSA', false, 'Registered construction health and safety agent.'),
  ('general', null, 'SACPCMP', 'CHSM', false, 'Registered health and safety manager: Care Net''s standard (HSF-1).'),
  ('general', null, 'SAIOSH', 'CMSAIOSH', false, 'SAIOSH chartered member.'),
  ('general', null, 'SAIOSH', 'GradSAIOSH', false, 'SAIOSH graduate member.'),
  ('general', null, 'SAIOSH', 'TechSAIOSH', false, 'SAIOSH technical member.');

do $$
declare
  v_n int;
begin
  select count(*) into v_n from hsf_signoff_rule;
  if v_n <> 13 then
    raise exception '053: expected 13 hsf_signoff_rule rows (3 construction, 5 mining, 5 general), found %; is the CONSTR or MINING industry missing?', v_n;
  end if;
end;
$$;

-- 4. hsf_signatory_fit and the release gate (SIGNOFF-CRITERIA 6.2) -------------------------------

create or replace function hsf_signatory_fit(p_signoff_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_so hsf_signoff;
  v_sig hsf_signatory;
  v_industry uuid;
  v_type text;
  v_allowed text;
  v_day date;
begin
  select * into v_so from hsf_signoff where id = p_signoff_id;
  if v_so.id is null then
    return 'the sign off does not exist';
  end if;
  if v_so.kind <> 'safety_content' then
    return 'the sign off is not a safety content sign off';
  end if;
  if v_so.decision is distinct from 'approved' then
    return 'the safety content sign off is not approved';
  end if;
  if v_so.signatory_id is null then
    return 'no signatory credentials are recorded on the safety content sign off';
  end if;
  select * into v_sig from hsf_signatory where id = v_so.signatory_id;
  select f.industry_id into v_industry from hsf_file f where f.id = v_so.file_id;
  -- The decision date is the South African calendar day of decided_at.
  v_day := (v_so.decided_at at time zone 'Africa/Johannesburg')::date;

  if v_sig.category like 'Can %' then
    return format('%s is a candidate category (%s %s) and never signs a File alone',
                  v_sig.full_name, v_sig.registration_body, v_sig.category);
  end if;

  -- The rows of the File's industry; an industry with none takes the general rows.
  if exists (select 1 from hsf_signoff_rule r where r.industry_id = v_industry) then
    select min(r.file_type),
           string_agg(r.registration_body || ' ' || r.category, ', ' order by r.registration_body, r.category)
      into v_type, v_allowed
      from hsf_signoff_rule r where r.industry_id = v_industry;
  else
    select min(r.file_type),
           string_agg(r.registration_body || ' ' || r.category, ', ' order by r.registration_body, r.category)
      into v_type, v_allowed
      from hsf_signoff_rule r where r.industry_id is null;
  end if;
  if not exists (select 1 from hsf_signoff_rule r
                  where r.registration_body = v_sig.registration_body and r.category = v_sig.category
                    and ((r.industry_id = v_industry)
                         or (r.industry_id is null
                             and not exists (select 1 from hsf_signoff_rule x where x.industry_id = v_industry)))) then
    return format('%s %s may not sign the safety content of a %s File; allowed: %s',
                  v_sig.registration_body, v_sig.category, v_type, coalesce(v_allowed, 'none recorded'));
  end if;

  if v_sig.registration_expires_on < v_day then
    return format('the registration of %s (%s %s) expired on %s, before the decision on %s',
                  v_sig.full_name, v_sig.registration_body, v_sig.registration_number,
                  to_char(v_sig.registration_expires_on, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  if v_sig.register_checked_on is null or length(btrim(coalesce(v_sig.register_proof_ref, ''))) = 0 then
    return format('the check of the %s public register for %s is not recorded (date and saved proof)',
                  v_sig.registration_body, v_sig.full_name);
  end if;
  if v_sig.register_checked_on > v_day then
    return format('the %s register was checked on %s, after the decision on %s',
                  v_sig.registration_body, to_char(v_sig.register_checked_on, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  if v_sig.appointment_letter_ref is null or v_sig.appointment_letter_date is null then
    return format('the appointment letter of %s is not on record', v_sig.full_name);
  end if;
  if v_sig.appointment_letter_date > v_day then
    return format('the appointment letter of %s is dated %s, after the decision on %s',
                  v_sig.full_name, to_char(v_sig.appointment_letter_date, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  if v_sig.engagement_letter_ref is null or v_sig.engagement_letter_date is null then
    return format('the engagement letter of %s is not on record', v_sig.full_name);
  end if;
  if v_sig.engagement_letter_date > v_day then
    return format('the engagement letter of %s is dated %s, after the decision on %s',
                  v_sig.full_name, to_char(v_sig.engagement_letter_date, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  return null;
end;
$$;
revoke execute on function hsf_signatory_fit(uuid) from public, anon, authenticated;
grant execute on function hsf_signatory_fit(uuid) to service_role;
comment on function hsf_signatory_fit is 'Contract 10.8 (SIGNOFF-CRITERIA 6.2). Null when an approved safety_content sign off can release its File revision; otherwise the first reason it cannot, in words: no credentials, a candidate category, a body or category that does not fit the File''s industry by hsf_signoff_rule, a registration expired on the decision date, no register check (or one after the decision), or a missing appointment or engagement letter (or one dated after the decision). The decision date is the South African calendar day of decided_at. Used by hsf_release_gate; service role only.';

create or replace function hsf_release_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_so record;
  v_reason text;
  v_first text;
  v_any boolean := false;
  v_fits boolean := false;
  v_unverified text;
begin
  -- 1. Safety content (SIGNOFF-CRITERIA 6.2): an approved sign off whose
  -- signatory fits. The latest decision's reason is reported when none fits.
  for v_so in select s.id from hsf_signoff s
               where s.file_id = new.file_id and s.revision = new.revision
                 and s.kind = 'safety_content' and s.decision = 'approved'
               order by s.decided_at desc, s.id loop
    v_any := true;
    v_reason := hsf_signatory_fit(v_so.id);
    if v_reason is null then
      v_fits := true;
      exit;
    end if;
    v_first := coalesce(v_first, v_reason);
  end loop;
  if not v_any then
    raise exception 'hsf_release_gate: safety_content sign off is not approved for this File revision';
  end if;
  if not v_fits then
    raise exception 'hsf_release_gate: the safety content sign off cannot release this File: %', v_first;
  end if;
  -- 2. The client's section 16(2) acceptance. The chief executive's
  -- acknowledgement is recorded, not a gate; the OMP is not a File signatory.
  if not exists (select 1 from hsf_signoff s
                  where s.file_id = new.file_id and s.revision = new.revision
                    and s.kind = 'client_16_2_acceptance' and s.decision = 'approved') then
    raise exception 'hsf_release_gate: client_16_2_acceptance sign off is not approved for this File revision';
  end if;
  -- 3. Contract 9.3, unchanged from 047: hsf_element_citable (migration 050) is
  -- the single definition of an instrument a File element may cite: verified,
  -- not held, not superseded, scope safety or both, and a provision pinned past
  -- 'awaiting verification'. Every instrument an item's element names must pass it.
  select string_agg(distinct li.short_name, ', ' order by li.short_name) into v_unverified
    from hsf_file_item fi
    join hsf_element_instrument ei on ei.element_id = fi.element_id
    join msp_legal_instrument li on li.id = ei.instrument_id
   where fi.file_id = new.file_id
     and not (hsf_element_citable(fi.element_id) ? li.short_name);
  if v_unverified is not null then
    raise exception 'hsf_release_gate: the File cites instruments that are not verified for a File: %', v_unverified;
  end if;
  return new;
end;
$$;
revoke execute on function hsf_release_gate() from public, anon, authenticated;
comment on function hsf_release_gate is 'SPEC B4.5 and B11.2 as amended by contract 10.8, and contract 9.3. Release needs (1) an approved safety_content sign off that hsf_signatory_fit accepts: body and category fit the File''s industry by hsf_signoff_rule, registration not expired on the decision date, register check recorded, appointment and engagement letters on record; (2) an approved client_16_2_acceptance; and (3) every instrument the File''s elements name citable for a File by hsf_element_citable. The OMP is not a File signatory and the chief executive acknowledgement is not a gate. Enforced in the database; the parameter hsf.release_required is display only and does not relax it.';

comment on table hsf_release is 'HSF-REV-01, amended by contract 10.8. A released File revision. The hsf_release_gate trigger refuses the insert unless an approved safety content sign off by a fitting, current, register checked and appointed practitioner and the client section 16(2) acceptance are on record, and every instrument the File''s elements name is citable for a File (hsf_element_citable, contract 9.3).';

comment on table hsf_section is 'HSF-SCH-01. The fifteen sections of the Health and Safety File, A to O. signatory_kind omp marks Section E, whose medical surveillance plan and certificates the OMP signs and the File holds as evidence; the OMP does not sign the File (contract 10.8). The safety content of every section is signed by a registered practitioner (hsf_signoff_rule).';

-- 5. Row Level Security and grants (as 047) ---------------------------------------------------------

alter table hsf_signatory enable row level security;
revoke all on hsf_signatory from public, anon, authenticated;
grant select on hsf_signatory to authenticated;
grant all on hsf_signatory to service_role;
create policy hsf_signatory_read on hsf_signatory
  for select to authenticated using (hsf_is_staff());

-- The rule table is reference data, like the 047 library tables: any signed in
-- person may read which body and category may sign; only the service role writes.
alter table hsf_signoff_rule enable row level security;
revoke all on hsf_signoff_rule from public, anon, authenticated;
grant select on hsf_signoff_rule to authenticated;
grant all on hsf_signoff_rule to service_role;
create policy hsf_signoff_rule_read on hsf_signoff_rule
  for select to authenticated using (true);
