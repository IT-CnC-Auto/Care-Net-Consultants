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
