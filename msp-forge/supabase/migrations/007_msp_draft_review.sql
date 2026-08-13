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
