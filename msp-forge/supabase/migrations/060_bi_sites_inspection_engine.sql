-- CNC HSF FORGE | BI-ENG-01 v1.0.0 | Bee-Inspect sites tree and inspection engine 26/09/2026
-- Built to hsf/BUILD-CONTRACT.md 16 and hsf/BEE-INSPECT-BUILD-PROMPT.md B5 and
-- section 6, phase P3.
--
-- What this migration does:
--   1. The sites tree of a company: bi_site, bi_department, bi_building,
--      bi_room (Company, Site or Factory, Department, Building or Zone, Room or
--      Area). Department rows may carry a File department code (hsf_department,
--      migration 047) so the same codes serve both products.
--   2. Templates mapped to Section F registers: bi_template (with
--      section_f_element_code, an hsf_element code such as HSF-F-01 scaffolds)
--      and bi_template_item.
--   3. The inspection engine: bi_inspection, bi_inspection_area, bi_equipment,
--      bi_finding (Pass, Fail, N/A, Observe), bi_photo (sealed GPS, time and
--      inspector; storage path only), bi_voice_note (audio path is the source of
--      truth) with bi_voice_transcript (versioned corrections, append only),
--      bi_risk (5 x 5 inherent and residual, hierarchy of controls) and
--      bi_corrective_action (owner, due date, closure evidence, escalation).
--   4. The Fail rule, enforced by a trigger whenever an inspection becomes
--      submitted: every Fail finding needs a photo and a corrective action, and
--      a voice note too when the tenant's policy is strict.
--   5. Scheduled runs for the cron Edge Functions: bi_schedule_reminders_run
--      and bi_ncr_escalation_run.
--
-- Offline first sync: every capture row takes its id from the device (uuid),
-- carries row_version (incremented on every update by bi_touch) and is updated
-- by the app only where the row_version it last saw still matches, so two
-- devices never overwrite each other silently. Ownership columns (tenant,
-- company) are copied from the parent by triggers and cannot be supplied.
--
-- POPIA: health and safety inspection and risk assessment data only. Free text
-- (notes, captions, transcripts) is about the workplace, never a person's
-- health; clinical results belong in MyClinicOnline. See bi_clinical_column_check
-- (063).
--
-- Access: RLS on every table; nothing for anon. Clients read through bi_can and
-- write capture rows directly (offline sync) where the policy allows; status
-- changes, seals and escalation go through the trusted paths only
-- (bi_is_client_session). Not applied to the live project.

-- 1. Sites tree ---------------------------------------------------------------------------

create table bi_site (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  name text not null check (length(btrim(name)) between 1 and 200),
  address text,
  gps_lat numeric(9,6) check (gps_lat between -90 and 90),
  gps_lng numeric(9,6) check (gps_lng between -180 and 180),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1
);
comment on table bi_site is 'BI-ENG-01 (prompt B5). A site or factory of a company (msp_client_account). Shared by every tenant with a live line on the company. Archived, never deleted.';
create index bi_site_company_idx on bi_site(client_account_id);

create table bi_department (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  site_id uuid not null references bi_site(id),
  department_code text references hsf_department(code),
  name text not null check (length(btrim(name)) between 1 and 200),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1
);
comment on table bi_department is 'BI-ENG-01. A department on a site. department_code, where given, is a File department (hsf_department: EXEC, HR, SHE, OPS, ENG, PROC, OH, TRAIN, FAC).';
create index bi_department_site_idx on bi_department(site_id);

create table bi_building (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  site_id uuid not null references bi_site(id),
  department_id uuid not null references bi_department(id),
  name text not null check (length(btrim(name)) between 1 and 200),
  kind text not null default 'building' check (kind in ('building','zone')),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1
);
comment on table bi_building is 'BI-ENG-01. A building or zone under a department. site_id and client_account_id are copied from the department.';
create index bi_building_department_idx on bi_building(department_id);

create table bi_room (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  site_id uuid not null references bi_site(id),
  building_id uuid not null references bi_building(id),
  name text not null check (length(btrim(name)) between 1 and 200),
  kind text not null default 'room' check (kind in ('room','area')),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1
);
comment on table bi_room is 'BI-ENG-01. A room or area in a building or zone: the unit an inspector walks.';
create index bi_room_building_idx on bi_room(building_id);

create function bi_tree_inherit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_company uuid;
  v_site uuid;
begin
  if tg_table_name = 'bi_department' then
    select s.client_account_id, s.id into v_company, v_site from bi_site s where s.id = new.site_id;
  elsif tg_table_name = 'bi_building' then
    select d.client_account_id, d.site_id into v_company, v_site from bi_department d where d.id = new.department_id;
    new.site_id := v_site;
  elsif tg_table_name = 'bi_room' then
    select b.client_account_id, b.site_id into v_company, v_site from bi_building b where b.id = new.building_id;
    new.site_id := v_site;
  end if;
  if v_company is null then
    raise exception '%: the parent was not found', tg_table_name;
  end if;
  if tg_op = 'UPDATE' and new.client_account_id is distinct from old.client_account_id and v_company <> old.client_account_id then
    raise exception '%: a row cannot move to another company', tg_table_name;
  end if;
  new.client_account_id := v_company;
  return new;
end;
$$;
comment on function bi_tree_inherit is 'BI-ENG-01. Copies the company (and site) from the parent in the sites tree, so a client can never place a row under another company.';

create trigger bi_department_inherit before insert or update on bi_department for each row execute function bi_tree_inherit();
create trigger bi_building_inherit before insert or update on bi_building for each row execute function bi_tree_inherit();
create trigger bi_room_inherit before insert or update on bi_room for each row execute function bi_tree_inherit();
create trigger bi_site_touch before update on bi_site for each row execute function bi_touch();
create trigger bi_department_touch before update on bi_department for each row execute function bi_touch();
create trigger bi_building_touch before update on bi_building for each row execute function bi_touch();
create trigger bi_room_touch before update on bi_room for each row execute function bi_touch();

-- 2. Templates ------------------------------------------------------------------------------

create table bi_template (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references bi_tenant(id),
  code text not null check (code ~ '^[A-Z][A-Z0-9-]{2,40}$'),
  version int not null default 1 check (version >= 1),
  name text not null check (length(btrim(name)) between 1 and 200),
  category text not null check (category in ('scaffolds','ladders','lifting','electrical','fire','ppe','chemicals',
    'construction','manufacturing','mining','agriculture','clinics','mobiles','general')),
  section_f_element_code text references hsf_element(code),
  description text,
  status text not null default 'draft' check (status in ('draft','published','retired')),
  created_at timestamptz not null default now()
);
comment on table bi_template is 'BI-ENG-01 (prompt B5). An inspection template. tenant_id null is Care Net''s library; a tenant may hold its own. section_f_element_code maps the template to its Section F register in the File (for example HSF-F-01 scaffolds, HSF-F-02 ladders, HSF-F-03 lifting, HSF-F-04 and HSF-F-05 electrical, HSF-F-06 fire, HSF-F-11 PPE, HSF-F-12 chemicals); an Issued report files there (bi_hsf_section_f_sync, 061). category is what an inspector''s competence scope must cover to sign.';
create unique index bi_template_code_idx on bi_template(coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code, version);

create table bi_template_item (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references bi_template(id),
  ordinal int not null check (ordinal >= 1),
  section_label text,
  prompt text not null check (length(btrim(prompt)) between 3 and 500),
  guidance text,
  kernel_ref text,
  unique (template_id, ordinal)
);
comment on table bi_template_item is 'BI-ENG-01. One checklist line of a template. kernel_ref names the kernel chunk (bi_kernel_chunk.ref) the line rests on, once the kernel is loaded ({{kernel_source}}).';

create function bi_template_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'bi_template' then
    if old.status = 'draft' then
      return coalesce(new, old);
    end if;
    if tg_op = 'UPDATE' and old.status = 'published' and new.status = 'retired'
       and (to_jsonb(new) - 'status') = (to_jsonb(old) - 'status') then
      return new;
    end if;
    raise exception 'A published template is never changed: publish a new version instead';
  end if;
  -- bi_template_item: only while its template is a draft (both templates on a move).
  if exists (select 1 from bi_template t
              where t.id in (case when tg_op <> 'DELETE' then new.template_id end,
                             case when tg_op <> 'INSERT' then old.template_id end)
                and t.status <> 'draft') then
    raise exception 'A published template is never changed: publish a new version instead';
  end if;
  return coalesce(new, old);
end;
$$;
create trigger bi_template_guard before update or delete on bi_template for each row execute function bi_template_guard();
create trigger bi_template_item_guard before insert or update or delete on bi_template_item for each row execute function bi_template_guard();

-- 3. Inspections --------------------------------------------------------------------------

create table bi_inspection (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  site_id uuid not null references bi_site(id),
  template_id uuid not null references bi_template(id),
  inspector_user_id uuid not null references bi_app_user(id),
  title text not null check (length(btrim(title)) between 1 and 200),
  status text not null default 'planned' check (status in ('planned','in_progress','submitted','closed','cancelled')),
  voice_note_policy text not null default 'recommended' check (voice_note_policy in ('recommended','strict')),
  scheduled_for date,
  recurrence text not null default 'none' check (recurrence in ('none','weekly','monthly','quarterly','annually')),
  series_id uuid,
  reminder_sent_at timestamptz,
  started_at timestamptz,
  submitted_at timestamptz,
  closed_at timestamptz,
  cancelled_reason text,
  legal_hold boolean not null default false,
  retention_until date,
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  check (recurrence = 'none' or scheduled_for is not null),
  check (status <> 'cancelled' or length(btrim(coalesce(cancelled_reason, ''))) >= 5)
);
comment on table bi_inspection is 'BI-ENG-01 (prompt B5). One inspection or risk assessment walk of a site by an inspector of a tenant, on a template. voice_note_policy is copied from the tenant when the inspection is created. A client may create it planned or in progress and start it; submit, close and cancel go through functions. Starting needs the company Active (B4) and the tenant''s live line on it. legal_hold stops any deletion of its photos and voice notes; retention_until is set by the retention policy once decided.';
create index bi_inspection_company_idx on bi_inspection(client_account_id, tenant_id);
create index bi_inspection_schedule_idx on bi_inspection(status, scheduled_for);

create function bi_inspection_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_client boolean := bi_is_client_session();
  v_tpl bi_template;
  v_viol jsonb;
  v_me uuid;
begin
  if tg_op = 'DELETE' then
    raise exception 'Inspections are cancelled, never deleted';
  end if;
  if tg_op = 'INSERT' then
    if not exists (select 1 from bi_site s where s.id = new.site_id and s.client_account_id = new.client_account_id and s.archived_at is null) then
      raise exception 'The site is not a live site of this company';
    end if;
    select * into v_tpl from bi_template where id = new.template_id;
    if v_tpl.id is null or v_tpl.status <> 'published' or (v_tpl.tenant_id is not null and v_tpl.tenant_id <> new.tenant_id) then
      raise exception 'The template is not a published template of this tenant or of Care Net''s library';
    end if;
    if not exists (select 1 from bi_company c where c.client_account_id = new.client_account_id and c.onboarding_status = 'active') then
      raise exception 'Start Inspection opens once the company''s onboarding is Active';
    end if;
    if not bi_subscription_live(new.tenant_id, new.client_account_id) then
      raise exception 'The tenant has no live Bee-Inspect line on this company';
    end if;
    if not bi_user_active_in_tenant(new.inspector_user_id, new.tenant_id) then
      raise exception 'The inspector must be an active person of the tenant';
    end if;
    new.voice_note_policy := (select t.voice_note_policy from bi_tenant t where t.id = new.tenant_id);
    new.series_id := coalesce(new.series_id, new.id);
    if v_client then
      v_me := bi_my_app_user_id();
      if new.inspector_user_id is distinct from v_me then
        raise exception 'An inspector creates inspections in their own name';
      end if;
      if new.status not in ('planned','in_progress') or new.submitted_at is not null or new.closed_at is not null
         or new.legal_hold or new.reminder_sent_at is not null then
        raise exception 'A new inspection starts planned or in progress';
      end if;
    end if;
    if new.status = 'in_progress' then
      new.started_at := coalesce(new.started_at, now());
    end if;
    return new;
  end if;

  -- UPDATE
  if v_client then
    if old.status in ('submitted','closed','cancelled') then
      raise exception 'A submitted, closed or cancelled inspection is read only';
    end if;
    if new.tenant_id is distinct from old.tenant_id or new.client_account_id is distinct from old.client_account_id
       or new.inspector_user_id is distinct from old.inspector_user_id or new.voice_note_policy is distinct from old.voice_note_policy
       or new.template_id is distinct from old.template_id or new.series_id is distinct from old.series_id
       or new.submitted_at is distinct from old.submitted_at or new.closed_at is distinct from old.closed_at
       or new.legal_hold is distinct from old.legal_hold or new.retention_until is distinct from old.retention_until
       or new.reminder_sent_at is distinct from old.reminder_sent_at then
      raise exception 'These inspection fields change only through Bee-Inspect functions';
    end if;
    if new.status is distinct from old.status and not (old.status = 'planned' and new.status = 'in_progress') then
      raise exception 'Submit, close and cancel go through Bee-Inspect functions';
    end if;
  end if;
  if new.status = 'in_progress' and old.status = 'planned' then
    new.started_at := coalesce(new.started_at, now());
  end if;
  if new.status = 'submitted' and old.status <> 'submitted' then
    if old.status not in ('planned','in_progress') then
      raise exception 'Only a planned or in progress inspection is submitted';
    end if;
    v_viol := bi_fail_rule_violations(new.id);
    if jsonb_array_length(v_viol) > 0 then
      raise exception 'Fail rule: % Fail finding(s) still need a photo and a corrective action%', jsonb_array_length(v_viol),
        case when new.voice_note_policy = 'strict' then ' and a voice note (strict policy)' else '' end
        using detail = v_viol::text, errcode = '23514';
    end if;
    new.submitted_at := coalesce(new.submitted_at, now());
  end if;
  return new;
end;
$$;
comment on function bi_inspection_guard is 'BI-ENG-01. Insert: live site of the company, published template of the tenant or the library, company Active, live line, active inspector of the tenant, voice policy copied from the tenant; a client creates only in their own name, planned or in progress. Update: a client may only edit an open inspection''s own fields and start it; submitting (any path) enforces the Fail rule (bi_fail_rule_violations).';
create trigger bi_inspection_guard before insert or update or delete on bi_inspection for each row execute function bi_inspection_guard();
create trigger bi_inspection_touch before update on bi_inspection for each row execute function bi_touch();

create table bi_inspection_area (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references bi_inspection(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  room_id uuid references bi_room(id),
  label text not null check (length(btrim(label)) between 1 and 200),
  ordinal int not null default 1 check (ordinal >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1
);
comment on table bi_inspection_area is 'BI-ENG-01. A room or area walked in an inspection (room_id from the sites tree, or a label only for an ad hoc area).';
create index bi_inspection_area_inspection_idx on bi_inspection_area(inspection_id);

create table bi_equipment (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  site_id uuid references bi_site(id),
  tag_code text not null check (tag_code ~ '^[A-Za-z0-9._:/-]{3,120}$'),
  kind text not null check (length(btrim(kind)) between 2 and 120),
  description text,
  serial_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  unique (client_account_id, tag_code)
);
comment on table bi_equipment is 'BI-ENG-01 (prompt B5). Equipment tagged by QR code or barcode (tag_code), per company. Findings and photos point to it.';

create table bi_finding (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references bi_inspection(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  area_id uuid not null references bi_inspection_area(id),
  template_item_id uuid references bi_template_item(id),
  equipment_id uuid references bi_equipment(id),
  result text not null check (result in ('pass','fail','na','observe')),
  note text,
  severity text check (severity in ('low','medium','high','critical')),
  captured_by uuid references bi_app_user(id),
  captured_at timestamptz not null default now(),
  gps_lat numeric(9,6) check (gps_lat between -90 and 90),
  gps_lng numeric(9,6) check (gps_lng between -180 and 180),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1
);
comment on table bi_finding is 'BI-ENG-01 (prompt B5). A checklist finding: pass, fail, na (not applicable) or observe. A Fail needs a photo and a corrective action (and a voice note under the strict policy) before the inspection can be submitted.';
create index bi_finding_inspection_idx on bi_finding(inspection_id);

create table bi_photo (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references bi_inspection(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  area_id uuid references bi_inspection_area(id),
  finding_id uuid references bi_finding(id),
  equipment_id uuid references bi_equipment(id),
  kind text not null check (kind in ('area','equipment','risk_close_up','closure_evidence','other')),
  storage_path text not null unique check (storage_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$'),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 26214400),
  mime_type text not null check (mime_type in ('image/jpeg','image/png','image/heic','image/webp')),
  captured_at timestamptz not null,
  gps_lat numeric(9,6) check (gps_lat between -90 and 90),
  gps_lng numeric(9,6) check (gps_lng between -180 and 180),
  gps_accuracy_m numeric(8,2),
  inspector_user_id uuid not null references bi_app_user(id),
  seal_sha256 text,
  caption text,
  annotations jsonb not null default '[]'::jsonb check (jsonb_typeof(annotations) = 'array'),
  identifiable_people boolean not null default false,
  people_consent_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  constraint bi_photo_people_consent check (not identifiable_people or length(btrim(coalesce(people_consent_ref, ''))) >= 3)
);
comment on table bi_photo is 'BI-ENG-01 (prompt B5, section 8). A photo by storage path only (private bucket bi-evidence, path <client_account_id>/<inspection_id>/<file>), never bytes. GPS, capture time, inspector and fingerprint are sealed at insert (seal_sha256) and never change. A photo in which a person can be recognised needs a consent reference. Deletion is refused under legal hold.';
comment on column bi_photo.seal_sha256 is 'SHA 256 of storage_path|sha256|captured_at (UTC, ISO)|gps_lat|gps_lng|inspector_user_id, computed by the database at insert (bi_evidence_seal). Proves the evidence fields were not altered.';
create index bi_photo_inspection_idx on bi_photo(inspection_id);
create index bi_photo_finding_idx on bi_photo(finding_id);

create table bi_voice_note (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references bi_inspection(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  area_id uuid references bi_inspection_area(id),
  finding_id uuid references bi_finding(id),
  vn_number int,
  audio_path text not null unique check (audio_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$'),
  audio_sha256 text not null check (audio_sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 52428800),
  mime_type text not null check (mime_type in ('audio/mp4','audio/m4a','audio/aac','audio/mpeg','audio/wav','audio/webm')),
  duration_seconds int not null check (duration_seconds between 1 and 3600),
  captured_at timestamptz not null,
  gps_lat numeric(9,6) check (gps_lat between -90 and 90),
  gps_lng numeric(9,6) check (gps_lng between -180 and 180),
  inspector_user_id uuid not null references bi_app_user(id),
  seal_sha256 text,
  transcript_status text not null default 'pending' check (transcript_status in ('pending','transcribed','failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  unique (inspection_id, vn_number)
);
comment on table bi_voice_note is 'BI-ENG-01 (prompt B5). A voice note on an item or section, captured offline, GPS and time stamped. The audio (private bucket bi-evidence, path only) is the source of truth; transcripts are versions in bi_voice_transcript. vn_number (VN-1, VN-2 ...) is given by the database per inspection and is how the report footnotes it (VN-12).';
create index bi_voice_note_inspection_idx on bi_voice_note(inspection_id);

create table bi_voice_transcript (
  id uuid primary key default gen_random_uuid(),
  voice_note_id uuid not null references bi_voice_note(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  version int not null,
  source text not null check (source in ('machine','correction')),
  body text not null check (length(body) <= 20000),
  created_by uuid references bi_app_user(id),
  created_at timestamptz not null default now(),
  unique (voice_note_id, version)
);
comment on table bi_voice_transcript is 'BI-ENG-01 (prompt B5). Versioned transcripts of a voice note: version 1 is usually the machine transcript, each correction is a new version by a person. Append only; the latest version is what the report uses; the audio stays the source of truth.';
create trigger bi_voice_transcript_append_only before update or delete on bi_voice_transcript for each row execute function bi_append_only();

create table bi_risk (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references bi_inspection(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  area_id uuid references bi_inspection_area(id),
  finding_id uuid references bi_finding(id),
  hazard text not null check (length(btrim(hazard)) between 3 and 500),
  consequence text,
  inherent_likelihood int not null check (inherent_likelihood between 1 and 5),
  inherent_severity int not null check (inherent_severity between 1 and 5),
  controls jsonb not null default '[]'::jsonb,
  residual_likelihood int check (residual_likelihood between 1 and 5),
  residual_severity int check (residual_severity between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  constraint bi_risk_controls_shape check (jsonb_typeof(controls) = 'array'
    and not jsonb_path_exists(controls, '$[*] ? (!(@.level == "elimination" || @.level == "substitution" || @.level == "engineering" || @.level == "administrative" || @.level == "ppe"))')),
  constraint bi_risk_residual_pair check ((residual_likelihood is null) = (residual_severity is null)),
  constraint bi_risk_residual_not_above check (residual_likelihood is null or residual_likelihood * residual_severity <= inherent_likelihood * inherent_severity)
);
comment on table bi_risk is 'BI-ENG-01 (prompt B5). A risk on the 5 x 5 matrix: likelihood and severity 1 to 5 before (inherent) and after (residual) the controls, which are listed on the hierarchy of controls (elimination, substitution, engineering, administrative, ppe). Scores and bands come from bi_risk_score and bi_risk_band (the same rule as supabase/functions/_shared/bi/risk.js). Residual never above inherent.';
create index bi_risk_inspection_idx on bi_risk(inspection_id);

create table bi_corrective_action (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references bi_inspection(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  finding_id uuid references bi_finding(id),
  risk_id uuid references bi_risk(id),
  description text not null check (length(btrim(description)) between 5 and 2000),
  owner_name text not null check (length(btrim(owner_name)) between 2 and 200),
  owner_user_id uuid references bi_app_user(id),
  due_on date not null,
  status text not null default 'open' check (status in ('open','in_progress','closed','overdue','escalated')),
  escalation_level int not null default 0 check (escalation_level between 0 and 3),
  escalated_at timestamptz,
  closure_note text,
  closure_evidence_photo_id uuid references bi_photo(id),
  closed_at timestamptz,
  closed_by uuid references bi_app_user(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  constraint bi_ca_closure check (status <> 'closed' or (closed_at is not null
    and (closure_evidence_photo_id is not null or length(btrim(coalesce(closure_note, ''))) >= 10)))
);
comment on table bi_corrective_action is 'BI-ENG-01 (prompt B5). A corrective action (the NCR board): owner, due date, closure with evidence (a closure photo or a note of at least ten characters). Overdue actions are escalated by bi_ncr_escalation_run: level 1 overdue, level 2 after 7 days (company admin), level 3 after 14 days (Care Net ops).';
create index bi_corrective_action_inspection_idx on bi_corrective_action(inspection_id);
create index bi_corrective_action_due_idx on bi_corrective_action(status, due_on);

create function bi_fail_rule_violations(p_inspection_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('finding_id', f.id, 'missing', m.missing) order by f.captured_at, f.id), '[]'::jsonb)
    from bi_finding f
    join bi_inspection i on i.id = f.inspection_id
    cross join lateral (
      select jsonb_agg(x) filter (where x is not null) as missing
        from (values
          (case when not exists (select 1 from bi_photo p where p.finding_id = f.id) then 'photo' end),
          (case when not exists (select 1 from bi_corrective_action c where c.finding_id = f.id) then 'corrective_action' end),
          (case when i.voice_note_policy = 'strict'
                     and not exists (select 1 from bi_voice_note v where v.finding_id = f.id) then 'voice_note' end)
        ) as t(x)) m
   where f.inspection_id = p_inspection_id
     and f.result = 'fail'
     and m.missing is not null;
$$;
comment on function bi_fail_rule_violations is 'BI-ENG-01 (prompt B5). Every Fail finding of the inspection that lacks a photo, a corrective action, or (strict policy) a voice note, with what is missing. Empty array when the Fail rule holds.';

-- 4. Capture guards -----------------------------------------------------------------------

create function bi_evidence_seal(p_path text, p_sha text, p_at timestamptz, p_lat numeric, p_lng numeric, p_inspector uuid)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(extensions.digest(concat_ws('|', p_path, p_sha,
           to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
           coalesce(p_lat::text, ''), coalesce(p_lng::text, ''), p_inspector::text), 'sha256'), 'hex');
$$;
comment on function bi_evidence_seal is 'BI-ENG-01. The seal of a photo or voice note: SHA 256 of path|fingerprint|capture time (UTC)|lat|lng|inspector.';

create function bi_capture_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_client boolean := bi_is_client_session();
  v_insp bi_inspection;
  v_after_submit_ok boolean := false;
  v_me uuid;
  v_new jsonb;
  v_old jsonb;
  k text;
begin
  if tg_op = 'DELETE' then
    if tg_table_name = 'bi_voice_transcript' then
      raise exception 'bi_voice_transcript is append only';
    end if;
    select * into v_insp from bi_inspection where id = (to_jsonb(old) ->> 'inspection_id')::uuid;
    if v_client then
      raise exception '% rows are not deleted by the app', tg_table_name;
    end if;
    if v_insp.legal_hold then
      raise exception 'Legal hold: evidence of this inspection cannot be deleted';
    end if;
    return old;
  end if;

  if tg_table_name = 'bi_voice_transcript' then
    select vn.inspection_id into v_insp.id from bi_voice_note vn where vn.id = new.voice_note_id;
    select * into v_insp from bi_inspection where id = v_insp.id;
  else
    select * into v_insp from bi_inspection where id = (to_jsonb(new) ->> 'inspection_id')::uuid;
  end if;
  if v_insp.id is null then
    raise exception '%: the inspection was not found', tg_table_name;
  end if;
  if tg_op = 'UPDATE' and tg_table_name <> 'bi_voice_transcript' then
    if (to_jsonb(new) ->> 'inspection_id') is distinct from (to_jsonb(old) ->> 'inspection_id') then
      raise exception '%: a row cannot move to another inspection', tg_table_name;
    end if;
  end if;
  -- Ownership always comes from the inspection, never from the client.
  new.tenant_id := v_insp.tenant_id;
  new.client_account_id := v_insp.client_account_id;

  -- Rows that point at an area, finding or risk must point inside the same inspection.
  v_new := to_jsonb(new);
  if v_new ? 'area_id' and v_new ->> 'area_id' is not null
     and not exists (select 1 from bi_inspection_area a where a.id = (v_new ->> 'area_id')::uuid and a.inspection_id = v_insp.id) then
    raise exception '%: the area belongs to another inspection', tg_table_name;
  end if;
  if tg_table_name <> 'bi_finding' and v_new ? 'finding_id' and v_new ->> 'finding_id' is not null
     and not exists (select 1 from bi_finding f where f.id = (v_new ->> 'finding_id')::uuid and f.inspection_id = v_insp.id) then
    raise exception '%: the finding belongs to another inspection', tg_table_name;
  end if;
  if v_new ? 'risk_id' and v_new ->> 'risk_id' is not null
     and not exists (select 1 from bi_risk r where r.id = (v_new ->> 'risk_id')::uuid and r.inspection_id = v_insp.id) then
    raise exception '%: the risk belongs to another inspection', tg_table_name;
  end if;
  if v_new ? 'equipment_id' and v_new ->> 'equipment_id' is not null
     and not exists (select 1 from bi_equipment e where e.id = (v_new ->> 'equipment_id')::uuid and e.client_account_id = v_insp.client_account_id) then
    raise exception '%: the equipment belongs to another company', tg_table_name;
  end if;

  -- Sealed evidence: computed at insert, never changed on any path.
  if tg_table_name in ('bi_photo','bi_voice_note') then
    if tg_op = 'INSERT' then
      if tg_table_name = 'bi_photo' then
        new.seal_sha256 := bi_evidence_seal(new.storage_path, new.sha256, new.captured_at, new.gps_lat, new.gps_lng, new.inspector_user_id);
      else
        new.seal_sha256 := bi_evidence_seal(new.audio_path, new.audio_sha256, new.captured_at, new.gps_lat, new.gps_lng, new.inspector_user_id);
        perform pg_advisory_xact_lock(hashtext('bi_vn'), hashtext(v_insp.id::text));
        new.vn_number := coalesce((select max(vn.vn_number) from bi_voice_note vn where vn.inspection_id = v_insp.id), 0) + 1;
      end if;
    else
      v_old := to_jsonb(old);
      v_new := to_jsonb(new);
      foreach k in array case when tg_table_name = 'bi_photo'
          then array['storage_path','sha256','size_bytes','mime_type','captured_at','gps_lat','gps_lng','gps_accuracy_m','inspector_user_id','seal_sha256']
          else array['audio_path','audio_sha256','size_bytes','mime_type','duration_seconds','captured_at','gps_lat','gps_lng','inspector_user_id','seal_sha256','vn_number'] end loop
        if v_new -> k is distinct from v_old -> k then
          raise exception '%: % is sealed evidence and never changes', tg_table_name, k;
        end if;
      end loop;
    end if;
  end if;

  if tg_table_name = 'bi_voice_transcript' then
    perform pg_advisory_xact_lock(hashtext('bi_vt'), hashtext(new.voice_note_id::text));
    new.version := coalesce((select max(t.version) from bi_voice_transcript t where t.voice_note_id = new.voice_note_id), 0) + 1;
  end if;

  if v_client then
    -- Each table's own columns are read only inside its own branch: PL/pgSQL
    -- resolves every field of an expression, so a shared expression would fail
    -- on a table without that column.
    v_me := bi_my_app_user_id();
    if tg_table_name in ('bi_photo','bi_voice_note') and tg_op = 'INSERT' then
      if new.inspector_user_id is distinct from v_me then
        raise exception '%: evidence is captured in the name of the person signed in', tg_table_name;
      end if;
    end if;
    if tg_table_name = 'bi_finding' and tg_op = 'INSERT' then
      new.captured_by := v_me;
    end if;
    if tg_table_name = 'bi_voice_transcript' then
      if new.source <> 'correction' then
        raise exception 'Only a person''s correction is added by the app; machine transcripts come from the transcription service';
      end if;
      new.created_by := v_me;
    end if;
    if tg_table_name = 'bi_corrective_action' then
      if tg_op = 'UPDATE' then
        if new.escalation_level is distinct from old.escalation_level or new.escalated_at is distinct from old.escalated_at
           or (new.status in ('overdue','escalated') and new.status is distinct from old.status) then
          raise exception 'Escalation is set by the overdue run only';
        end if;
        if new.status = 'closed' and old.status <> 'closed' then
          new.closed_by := v_me;
          new.closed_at := coalesce(new.closed_at, now());
        end if;
      else
        if new.escalation_level <> 0 or new.status not in ('open','in_progress') then
          raise exception 'A new corrective action starts open';
        end if;
      end if;
      v_after_submit_ok := true;
    end if;
    if tg_table_name = 'bi_photo' then
      if new.kind = 'closure_evidence' then
        v_after_submit_ok := true;
      end if;
    end if;
    if v_insp.status = 'cancelled' then
      raise exception 'The inspection is cancelled';
    end if;
    if v_insp.status in ('submitted','closed') and not v_after_submit_ok then
      raise exception 'The inspection is submitted: its capture is read only';
    end if;
  end if;
  return new;
end;
$$;
comment on function bi_capture_guard is 'BI-ENG-01. On every capture table: ownership copied from the inspection; area, finding, risk and equipment must belong to the same inspection or company; photo and voice note evidence sealed at insert and never changed; voice notes numbered VN-n and transcripts versioned by the database. For a client: evidence only in their own name, transcripts only as corrections, escalation never, and nothing but corrective actions and closure photos after submission. Deletion only on a trusted path and never under legal hold.';

do $$
declare
  t text;
begin
  foreach t in array array['bi_inspection_area','bi_finding','bi_photo','bi_voice_note','bi_voice_transcript','bi_risk','bi_corrective_action'] loop
    execute format('create trigger %I before insert or update or delete on %I for each row execute function bi_capture_guard()', t || '_guard', t);
  end loop;
  foreach t in array array['bi_inspection_area','bi_finding','bi_photo','bi_voice_note','bi_risk','bi_corrective_action','bi_equipment'] loop
    execute format('create trigger %I before update on %I for each row execute function bi_touch()', t || '_touch', t);
  end loop;
end;
$$;

-- 5. Risk matrix -------------------------------------------------------------------------------

create function bi_risk_band(p_score int)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_score is null then null
    when p_score < 1 or p_score > 25 then null
    when p_score <= 4 then 'low'
    when p_score <= 9 then 'medium'
    when p_score <= 15 then 'high'
    else 'extreme' end;
$$;
comment on function bi_risk_band is 'BI-ENG-01. Band of a 5 x 5 score (likelihood x severity): 1 to 4 low, 5 to 9 medium, 10 to 15 high, 16 to 25 extreme. Care Net''s working bands, to be confirmed against the Care Net methodology (open question); mirrored in supabase/functions/_shared/bi/risk.js.';

create function bi_risk_score(p_likelihood int, p_severity int)
returns int
language sql
immutable
set search_path = ''
as $$
  select case when p_likelihood between 1 and 5 and p_severity between 1 and 5 then p_likelihood * p_severity end;
$$;

create function bi_risk_top_control(p_controls jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select l from (values (1,'elimination'),(2,'substitution'),(3,'engineering'),(4,'administrative'),(5,'ppe')) h(o, l)
   where exists (select 1 from jsonb_array_elements(coalesce(p_controls, '[]'::jsonb)) c where c ->> 'level' = h.l)
   order by o limit 1;
$$;
comment on function bi_risk_top_control is 'BI-ENG-01. The highest level of the hierarchy of controls among a risk''s controls (elimination first, ppe last), or null.';

create view bi_risk_register with (security_invoker = true) as
select r.id, r.inspection_id, r.tenant_id, r.client_account_id, r.area_id, r.finding_id, r.hazard, r.consequence,
       r.inherent_likelihood, r.inherent_severity,
       bi_risk_score(r.inherent_likelihood, r.inherent_severity) as inherent_score,
       bi_risk_band(bi_risk_score(r.inherent_likelihood, r.inherent_severity)) as inherent_band,
       r.residual_likelihood, r.residual_severity,
       bi_risk_score(r.residual_likelihood, r.residual_severity) as residual_score,
       bi_risk_band(bi_risk_score(r.residual_likelihood, r.residual_severity)) as residual_band,
       bi_risk_top_control(r.controls) as top_control, r.controls
  from bi_risk r;
comment on view bi_risk_register is 'BI-ENG-01. Risks with their inherent and residual scores, bands and top control. security_invoker, so bi_risk RLS applies.';

-- 6. Submit, close, cancel ----------------------------------------------------------------------

create function bi_inspection_submit(p_auth_user uuid, p_inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_i bi_inspection;
  v_me bi_app_user;
begin
  select * into v_i from bi_inspection where id = p_inspection_id for update;
  v_me := bi_app_user_of(p_auth_user);
  if v_i.id is null or v_me.id is null or not ('inspector' = any(bi_user_roles(p_auth_user, v_i.tenant_id, v_i.client_account_id))) then
    raise exception 'That inspection was not found.' using errcode = 'P0002';
  end if;
  update bi_inspection set status = 'submitted' where id = v_i.id;
  perform bi_audit(p_auth_user, 'inspection_submitted', v_i.tenant_id, v_i.client_account_id, 'inspection', v_i.id, '{}'::jsonb);
  return jsonb_build_object('inspection_id', v_i.id, 'status', 'submitted');
end;
$$;
comment on function bi_inspection_submit is 'BI-ENG-01. An inspector of the company submits an inspection; the guard enforces the Fail rule (SQLSTATE 23514 with the findings in the detail). Audited.';

create function bi_inspection_set_status(p_auth_user uuid, p_inspection_id uuid, p_status text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_i bi_inspection;
begin
  select * into v_i from bi_inspection where id = p_inspection_id for update;
  if v_i.id is null or not (bi_user_is_ops(p_auth_user) or 'inspector' = any(bi_user_roles(p_auth_user, v_i.tenant_id, v_i.client_account_id))) then
    raise exception 'That inspection was not found.' using errcode = 'P0002';
  end if;
  if p_status = 'closed' and v_i.status <> 'submitted' then
    raise exception 'Only a submitted inspection is closed.';
  elsif p_status = 'cancelled' and v_i.status not in ('planned','in_progress') then
    raise exception 'Only a planned or in progress inspection is cancelled.';
  elsif p_status not in ('closed','cancelled') then
    raise exception 'Use bi_inspection_submit to submit.';
  end if;
  update bi_inspection set status = p_status,
         closed_at = case when p_status = 'closed' then now() else closed_at end,
         cancelled_reason = case when p_status = 'cancelled' then p_reason else cancelled_reason end
   where id = v_i.id;
  perform bi_audit(p_auth_user, 'inspection_' || p_status, v_i.tenant_id, v_i.client_account_id, 'inspection', v_i.id,
                   jsonb_build_object('reason', p_reason));
  return jsonb_build_object('inspection_id', v_i.id, 'status', p_status);
end;
$$;
comment on function bi_inspection_set_status is 'BI-ENG-01. Closes a submitted inspection or cancels an open one (with a reason). Inspector of the company or ops. Audited.';

-- 7. Scheduled runs (called by the cron Edge Functions) --------------------------------------------

create function bi_schedule_reminders_run(p_today date default current_date, p_days_ahead int default 3)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reminders jsonb;
  v_overdue jsonb;
  v_created int := 0;
  r record;
  v_next date;
begin
  with due as (
    update bi_inspection i set reminder_sent_at = now()
     where i.status = 'planned' and i.reminder_sent_at is null
       and i.scheduled_for between p_today and p_today + greatest(0, p_days_ahead)
    returning i.id, i.tenant_id, i.client_account_id, i.inspector_user_id, i.scheduled_for, i.title)
  select coalesce(jsonb_agg(to_jsonb(due) order by scheduled_for), '[]'::jsonb) into v_reminders from due;

  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'tenant_id', i.tenant_id, 'client_account_id', i.client_account_id,
           'inspector_user_id', i.inspector_user_id, 'scheduled_for', i.scheduled_for, 'days_overdue', p_today - i.scheduled_for)
           order by i.scheduled_for), '[]'::jsonb)
    into v_overdue
    from bi_inspection i where i.status in ('planned','in_progress') and i.scheduled_for < p_today;

  -- Recurring inspections: when the latest of a series is submitted or closed,
  -- the next one is planned.
  for r in
    select i.* from bi_inspection i
     where i.recurrence <> 'none' and i.status in ('submitted','closed')
       and not exists (select 1 from bi_inspection n where n.series_id = i.series_id and n.scheduled_for > i.scheduled_for)
  loop
    v_next := (r.scheduled_for + case r.recurrence when 'weekly' then interval '7 days' when 'monthly' then interval '1 month'
                                    when 'quarterly' then interval '3 months' else interval '1 year' end)::date;
    begin
      insert into bi_inspection (tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status,
                                 scheduled_for, recurrence, series_id)
      values (r.tenant_id, r.client_account_id, r.site_id, r.template_id, r.inspector_user_id, r.title, 'planned',
              v_next, r.recurrence, r.series_id);
      v_created := v_created + 1;
    exception when others then
      -- The company may no longer be Active or the line may have lapsed: the
      -- series stops quietly and the run carries on.
      perform bi_audit(null, 'recurrence_skipped', r.tenant_id, r.client_account_id, 'inspection', r.id,
                       jsonb_build_object('reason', left(sqlerrm, 200)));
    end;
  end loop;

  return jsonb_build_object('reminders', v_reminders, 'overdue', v_overdue, 'recurring_created', v_created);
end;
$$;
comment on function bi_schedule_reminders_run is 'BI-ENG-01 (prompt B5, schedules and recurring inspections). For schedule-reminders (cron): marks and returns planned inspections due within p_days_ahead (each reminded once), returns the overdue list, and plans the next inspection of every recurring series whose latest inspection is submitted or closed. Service role only.';

create function bi_ncr_escalation_run(p_today date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_out jsonb;
begin
  with moved as (
    update bi_corrective_action c
       set escalation_level = x.level,
           status = case when x.level = 1 then 'overdue' else 'escalated' end,
           escalated_at = now()
      from (select c2.id,
                   case when c2.due_on <= p_today - 14 then 3
                        when c2.due_on <= p_today - 7 then 2
                        else 1 end as level
              from bi_corrective_action c2
             where c2.status <> 'closed' and c2.due_on < p_today) x
     where c.id = x.id and x.level > c.escalation_level
    returning c.id, c.tenant_id, c.client_account_id, c.inspection_id, c.owner_name, c.due_on, c.escalation_level)
  select coalesce(jsonb_agg(to_jsonb(moved) order by due_on), '[]'::jsonb) into v_out from moved;
  if jsonb_array_length(v_out) > 0 then
    perform bi_audit(null, 'ncr_escalated', null, null, 'corrective_action', null, jsonb_build_object('count', jsonb_array_length(v_out)));
  end if;
  return jsonb_build_object('escalated', v_out);
end;
$$;
comment on function bi_ncr_escalation_run is 'BI-ENG-01 (prompt B5, overdue escalation). For ncr-escalation (cron): open actions past due become overdue (level 1), 7 days past due escalated to the company admin (level 2), 14 days to Care Net ops (level 3). Each level is raised once. Returns the moved actions. Service role only.';

-- 8. Row Level Security -------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['bi_site','bi_department','bi_building','bi_room','bi_template','bi_template_item','bi_inspection',
                           'bi_inspection_area','bi_equipment','bi_finding','bi_photo','bi_voice_note','bi_voice_transcript',
                           'bi_risk','bi_corrective_action'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant all on %I to service_role', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
  -- Sites tree: read by anyone with a role on the company; written by an inspector or the company admin.
  foreach t in array array['bi_site','bi_department','bi_building','bi_room'] loop
    execute format('grant insert, update on %I to authenticated', t);
    execute format('create policy %I on %I for select to authenticated using (bi_can_company(client_account_id, %L))', t || '_read', t, 'read_capture');
    execute format('create policy %I on %I for insert to authenticated with check (bi_can_company(client_account_id, %L) or bi_can_company(client_account_id, %L))', t || '_insert', t, 'write_capture', 'manage_company');
    execute format('create policy %I on %I for update to authenticated using (bi_can_company(client_account_id, %L) or bi_can_company(client_account_id, %L)) with check (bi_can_company(client_account_id, %L) or bi_can_company(client_account_id, %L))',
                   t || '_update', t, 'write_capture', 'manage_company', 'write_capture', 'manage_company');
  end loop;
  -- Capture by the inspector only: inspection, areas, risks, corrective actions.
  foreach t in array array['bi_inspection','bi_inspection_area','bi_risk','bi_corrective_action'] loop
    execute format('grant insert, update on %I to authenticated', t);
    execute format('create policy %I on %I for select to authenticated using (bi_can(tenant_id, client_account_id, %L))', t || '_read', t, 'read_capture');
    execute format('create policy %I on %I for insert to authenticated with check (bi_can(tenant_id, client_account_id, %L))', t || '_insert', t, 'write_capture');
    execute format('create policy %I on %I for update to authenticated using (bi_can(tenant_id, client_account_id, %L)) with check (bi_can(tenant_id, client_account_id, %L))', t || '_update', t, 'write_capture', 'write_capture');
  end loop;
  -- Capture by the inspector or an assistant: findings, photos, voice notes, transcript corrections.
  foreach t in array array['bi_finding','bi_photo','bi_voice_note','bi_voice_transcript'] loop
    execute format('grant insert, update on %I to authenticated', t);
    execute format('create policy %I on %I for select to authenticated using (bi_can(tenant_id, client_account_id, %L))', t || '_read', t, 'read_capture');
    execute format('create policy %I on %I for insert to authenticated with check (bi_can(tenant_id, client_account_id, %L))', t || '_insert', t, 'write_capture_assistant');
    execute format('create policy %I on %I for update to authenticated using (bi_can(tenant_id, client_account_id, %L)) with check (bi_can(tenant_id, client_account_id, %L))', t || '_update', t, 'write_capture_assistant', 'write_capture_assistant');
  end loop;
end;
$$;
revoke update on bi_voice_transcript from authenticated;

grant insert, update on bi_equipment to authenticated;
create policy bi_equipment_read on bi_equipment for select to authenticated using (bi_can_company(client_account_id, 'read_capture'));
create policy bi_equipment_insert on bi_equipment for insert to authenticated with check (bi_can_company(client_account_id, 'write_capture_assistant'));
create policy bi_equipment_update on bi_equipment for update to authenticated
  using (bi_can_company(client_account_id, 'write_capture_assistant')) with check (bi_can_company(client_account_id, 'write_capture_assistant'));

create policy bi_template_read on bi_template for select to authenticated
  using (bi_is_ops() or (status = 'published' and (tenant_id is null or tenant_id = bi_my_tenant())));
create policy bi_template_item_read on bi_template_item for select to authenticated
  using (exists (select 1 from bi_template t where t.id = template_id
                  and (bi_is_ops() or (t.status = 'published' and (t.tenant_id is null or t.tenant_id = bi_my_tenant())))));

grant select on bi_risk_register to authenticated, service_role;
revoke all on bi_risk_register from public, anon;

do $$
declare
  f text;
begin
  foreach f in array array['bi_fail_rule_violations(uuid)','bi_inspection_submit(uuid, uuid)',
                           'bi_inspection_set_status(uuid, uuid, text, text)','bi_schedule_reminders_run(date, int)',
                           'bi_ncr_escalation_run(date)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  -- Pure helpers used by the view, the guards and the checks.
  foreach f in array array['bi_risk_band(int)','bi_risk_score(int, int)','bi_risk_top_control(jsonb)',
                           'bi_evidence_seal(text, text, timestamptz, numeric, numeric, uuid)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  foreach f in array array['bi_tree_inherit()','bi_template_guard()','bi_inspection_guard()','bi_capture_guard()'] loop
    execute format('revoke execute on function %s from public, anon', f);
  end loop;
end;
$$;
-- The inspection guard runs as the client and asks whether the tenant holds a
-- live line (a yes or no, nothing more).
grant execute on function bi_subscription_live(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
