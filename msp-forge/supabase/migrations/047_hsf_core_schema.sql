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
  select coalesce(max(substring(reference from '(\d{3})$')::int), 0) + 1 into v_n
    from hsf_file
   where reference like v_prefix || '%';
  return v_prefix || lpad(v_n::text, 3, '0');
end;
$$;
revoke execute on function hsf_next_reference() from public, anon, authenticated;
comment on function hsf_next_reference is 'CNC-HSF-YYYY-MMDD-NNN. NNN = highest existing number for the day + 1 (gap safe, the migration 041 pattern). Advisory lock serialises concurrent Files.';

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
comment on table hsf_release is 'HSF-REV-01. A released File revision. The hsf_release_gate trigger refuses the insert unless all three sign offs are approved and nothing in the File cites an unverified instrument.';

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
  select string_agg(distinct li.short_name, ', ' order by li.short_name) into v_unverified
    from hsf_file_item fi
    join hsf_element_instrument ei on ei.element_id = fi.element_id
    join msp_legal_instrument li on li.id = ei.instrument_id
   where fi.file_id = new.file_id and li.status <> 'verified';
  if v_unverified is not null then
    raise exception 'hsf_release_gate: the File cites instruments that are not verified: %', v_unverified;
  end if;
  return new;
end;
$$;
revoke execute on function hsf_release_gate() from public, anon, authenticated;
comment on function hsf_release_gate is 'SPEC B4.5 and B11.2. Enforced in the database; the parameter hsf.release_required is display only and does not relax it.';

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
