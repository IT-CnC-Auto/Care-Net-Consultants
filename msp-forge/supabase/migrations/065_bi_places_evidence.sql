-- CNC HSF FORGE | BI-PLC-01 v1.0.0 | Bee-Inspect places of inspection, kernel templates and evidence storage 27/09/2026
-- Built to the Director's instruction of 27/09/2026 (Bee-Inspect for all 17 kernel
-- industries; register a company, then its places, then its people; the most
-- advanced way of storing photos and inspections, kept simple), hsf/BUILD-CONTRACT.md
-- 16 and hsf/BEE-INSPECT-BUILD-PROMPT.md B5, B8 and section 8. Design notes:
-- docs/bee-inspect/p4/evidence-storage.md.
--
-- What this migration does (additive; 001 to 064 are unchanged):
--   1. The kernel industry and subindustry of a Bee-Inspect company
--      (bi_company.industry_code, subindustry_code; msp_industry and
--      msp_subindustry codes), with the subindustry checked against the industry.
--   2. Place types (bi_place_type: the Director's list, which types may sit at the
--      top and which under each type) and the types each industry is offered
--      (bi_place_type_industry, loaded from the kernel bundle seed).
--   3. bi_place: the company's places of inspection as a flexible tree of typed
--      nodes (site, office, farm, mine or quarry section, clinic or laboratory,
--      department, building, floor, room or area ...). bi_place_guard keeps the
--      tree rules (same company, allowed type under the parent, no loops, at most
--      8 levels, sibling names unique, archived never deleted). A top level place
--      is also the company's bi_site with the same id, so inspections, equipment
--      and the rest of the engine keep working unchanged.
--   4. Kernel templates: bi_template gains industry_code, template_kind and
--      kernel_version; bi_template_item gains source_ref (the kernel source id of
--      the line); bi_template_industry maps templates to industries. The templates
--      themselves are the seed supabase/seed/bee_inspect_kernel_templates.sql,
--      written by apps/mobile/scripts/build-kernel-bundle.mjs.
--   5. bi_inspection.place_id and bi_inspection_area.place_id: the exact place
--      inspected and walked, checked to be the company's and under the site.
--   6. Evidence storage: content addressed blobs (bi_evidence_blob, one row per
--      company and SHA 256, the bytes stored once), resumable chunked upload
--      sessions (bi_evidence_upload_session, server side only), and on
--      bi_photo and bi_voice_note: versions (version, root_id, supersedes_id; a
--      correction is a new row, never an overwrite), the canonical path, the
--      place, the template item, the device, tags, the retention class, legal
--      hold and the metadata sidecar's hash. Storage paths may now be the company
--      scoped content address (<company>/cas/sha256/ab/cd/<hash>); versions share
--      their blob, so the unique path rule gives way to a unique version rule.
--      Used storage counts every distinct blob once (dedupe).
--   7. Search: bi_search_doc, a full text index (tsvector, GIN) over findings,
--      transcripts, evidence metadata and places, kept by triggers, read under
--      RLS; bi_search runs a prefix query.
--
-- POPIA: health and safety inspection and risk assessment data only; no
-- clinical data (bi_clinical_column_check, 063, still applies to every column).
-- RLS on every new table; nothing for anon. Not applied to any Supabase project.

-- 1. Kernel industry of a company --------------------------------------------------------------

alter table bi_company add column industry_code text references msp_industry(code);
alter table bi_company add column subindustry_code text references msp_subindustry(code);
comment on column bi_company.industry_code is 'BI-PLC-01. The Care Net kernel industry (msp_industry.code, 17 industries): decides the places, templates and suggestions offered.';
comment on column bi_company.subindustry_code is 'BI-PLC-01. The kernel subindustry (msp_subindustry.code); must belong to industry_code.';

create function bi_company_kernel_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.subindustry_code is not null then
    if new.industry_code is null then
      raise exception 'A subindustry needs its industry';
    end if;
    if not exists (select 1 from msp_subindustry s join msp_industry i on i.id = s.industry_id
                    where s.code = new.subindustry_code and i.code = new.industry_code) then
      raise exception 'The subindustry % is not part of the industry %', new.subindustry_code, new.industry_code;
    end if;
  end if;
  return new;
end;
$$;
create trigger bi_company_kernel_guard before insert or update of industry_code, subindustry_code on bi_company
  for each row execute function bi_company_kernel_guard();

-- 2. Place types ----------------------------------------------------------------------------------

create table bi_place_type (
  code text primary key check (code ~ '^[a-z][a-z_]{1,40}$'),
  label text not null check (length(btrim(label)) between 2 and 60),
  root_allowed boolean not null,
  allowed_children text[] not null default '{}',
  ordinal int not null unique check (ordinal >= 1)
);
comment on table bi_place_type is 'BI-PLC-01. The kinds of place a company is inspected at (the Director''s list, 27/09/2026). root_allowed: may sit at the top of the tree (and so is also a bi_site). allowed_children: the types that may sit under it. The same table is in the app''s kernel bundle (apps/mobile/assets/kernel/kernel-bundle.json, place_types), checked by the app tests.';

insert into bi_place_type (code, label, root_allowed, allowed_children, ordinal) values
  ('site', 'Site', true, '{department,building_block,floor,room_area,workshop,warehouse,mine_section,clinic_lab,vehicle_fleet,construction_project,factory_plant,retail_store}', 1),
  ('office', 'Office', true, '{department,building_block,floor,room_area,vehicle_fleet}', 2),
  ('branch', 'Branch', true, '{department,building_block,floor,room_area,workshop,warehouse,mine_section,clinic_lab,vehicle_fleet,construction_project,factory_plant,retail_store}', 3),
  ('factory_plant', 'Factory or plant', true, '{department,building_block,floor,room_area,workshop,warehouse,vehicle_fleet,clinic_lab}', 4),
  ('warehouse', 'Warehouse', true, '{department,floor,room_area,vehicle_fleet}', 5),
  ('workshop', 'Workshop', true, '{department,room_area,vehicle_fleet}', 6),
  ('farm', 'Farm', true, '{department,building_block,floor,room_area,workshop,warehouse,vehicle_fleet,factory_plant}', 7),
  ('mine_section', 'Mine or quarry section', true, '{department,building_block,floor,room_area,mine_section,workshop,warehouse,vehicle_fleet,factory_plant,clinic_lab}', 8),
  ('school_campus', 'School campus', true, '{department,building_block,floor,room_area,clinic_lab,workshop,vehicle_fleet}', 9),
  ('clinic_lab', 'Clinic or laboratory', true, '{department,floor,room_area}', 10),
  ('retail_store', 'Retail store', true, '{department,building_block,floor,room_area,warehouse,vehicle_fleet}', 11),
  ('depot', 'Depot', true, '{department,building_block,floor,room_area,workshop,warehouse,vehicle_fleet}', 12),
  ('vehicle_fleet', 'Vehicle or fleet', true, '{vehicle_fleet}', 13),
  ('construction_project', 'Construction project', true, '{department,building_block,floor,room_area,workshop,vehicle_fleet}', 14),
  ('department', 'Department', false, '{department,building_block,floor,room_area,workshop,warehouse,clinic_lab,vehicle_fleet}', 15),
  ('building_block', 'Building or block', false, '{floor,room_area,department,workshop,clinic_lab,warehouse}', 16),
  ('floor', 'Floor', false, '{room_area,department}', 17),
  ('room_area', 'Room or area', false, '{}', 18);

create table bi_place_type_industry (
  place_type text not null references bi_place_type(code),
  industry_code text not null references msp_industry(code),
  source_ref text not null,
  primary key (place_type, industry_code)
);
comment on table bi_place_type_industry is 'BI-PLC-01. The place types offered to a company of an industry, as the kernel bundle derives them from the kernel (industry, subindustry and trigger codes). Loaded by supabase/seed/bee_inspect_kernel_templates.sql. A company may still use any type; this list only shapes what is offered.';

-- 3. Places of inspection --------------------------------------------------------------------------

create table bi_place (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  parent_id uuid references bi_place(id),
  place_type text not null references bi_place_type(code),
  custom_type_label text check (custom_type_label is null or length(btrim(custom_type_label)) between 1 and 60),
  name text not null check (length(btrim(name)) between 1 and 200),
  address text,
  gps_lat numeric(9,6) check (gps_lat between -90 and 90),
  gps_lng numeric(9,6) check (gps_lng between -180 and 180),
  responsible_person text check (responsible_person is null or length(btrim(responsible_person)) between 2 and 200),
  headcount int check (headcount is null or headcount between 0 and 9999999),
  department_code text references hsf_department(code),
  linked_department_ids uuid[] not null default '{}',
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  check ((gps_lat is null) = (gps_lng is null))
);
comment on table bi_place is 'BI-PLC-01. A place of inspection of a company: one typed node of a flexible tree (bi_place_type). A top level place is also the company''s bi_site with the same id (bi_place_site_sync). Archived, never deleted. headcount is a whole number, as hsf_generate_file takes it.';
create index bi_place_company_idx on bi_place(client_account_id);
create index bi_place_parent_idx on bi_place(parent_id);
create unique index bi_place_sibling_name_idx on bi_place(client_account_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(regexp_replace(btrim(name), '\s+', ' ', 'g')))
  where archived_at is null;

create function bi_place_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_parent bi_place;
  v_type bi_place_type;
  v_parent_type bi_place_type;
  v_depth int := 1;
  v_cursor uuid;
begin
  if tg_op = 'DELETE' then
    raise exception 'Places are archived, never deleted';
  end if;
  select * into v_type from bi_place_type where code = new.place_type;
  if new.parent_id is null then
    if not v_type.root_allowed then
      raise exception 'A % sits under a site or another place, not at the top', lower(v_type.label);
    end if;
  else
    select * into v_parent from bi_place where id = new.parent_id;
    if v_parent.id is null then
      raise exception 'The place it belongs under was not found';
    end if;
    if v_parent.client_account_id <> new.client_account_id then
      raise exception 'A place stays with its own company';
    end if;
    if v_parent.archived_at is not null and new.archived_at is null then
      raise exception 'The place it belongs under is archived';
    end if;
    select * into v_parent_type from bi_place_type where code = v_parent.place_type;
    if not (new.place_type = any (v_parent_type.allowed_children)) then
      raise exception 'A % cannot go under a %', lower(v_type.label), lower(v_parent_type.label);
    end if;
    -- No loops and at most 8 levels: walk up from the parent.
    v_cursor := new.parent_id;
    while v_cursor is not null loop
      if v_cursor = new.id then
        raise exception 'A place cannot sit under itself or one of its own places';
      end if;
      v_depth := v_depth + 1;
      if v_depth > 8 then
        raise exception 'Keep the tree to 8 levels';
      end if;
      select parent_id into v_cursor from bi_place where id = v_cursor;
    end loop;
  end if;
  if tg_op = 'UPDATE' and new.client_account_id is distinct from old.client_account_id then
    raise exception 'A place never moves to another company';
  end if;
  return new;
end;
$$;
comment on function bi_place_guard is 'BI-PLC-01. The places tree rules: a top level place is a type allowed at the top; a child is a type its parent allows; parent and child share the company; no loops; at most 8 levels; never deleted and never moved to another company. Sibling names are unique by bi_place_sibling_name_idx. The same rules as apps/mobile/src/lib/places.ts.';
create trigger bi_place_guard before insert or update or delete on bi_place for each row execute function bi_place_guard();
create trigger bi_place_touch before update on bi_place for each row execute function bi_touch();

-- A top level place is also the company's site (the engine's bi_site), with the same id.
create function bi_place_site_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.parent_id is null then
    insert into bi_site (id, client_account_id, name, address, gps_lat, gps_lng, archived_at)
    values (new.id, new.client_account_id, new.name, new.address, new.gps_lat, new.gps_lng, new.archived_at)
    on conflict (id) do update
       set name = excluded.name, address = excluded.address, gps_lat = excluded.gps_lat, gps_lng = excluded.gps_lng,
           archived_at = excluded.archived_at
     where bi_site.client_account_id = excluded.client_account_id;
  end if;
  return null;
end;
$$;
comment on function bi_place_site_sync is 'BI-PLC-01. Keeps a bi_site with the same id for every top level place, so inspections (site_id), equipment and the rest of the engine keep working. Security definer: the site follows the place, whoever wrote it.';
create trigger bi_place_site_sync after insert or update of name, address, gps_lat, gps_lng, archived_at, parent_id on bi_place
  for each row execute function bi_place_site_sync();

-- 4. Kernel templates -----------------------------------------------------------------------------

alter table bi_template add column industry_code text references msp_industry(code);
alter table bi_template add column template_kind text not null default 'tenant' check (template_kind in ('register','industry','tenant'));
alter table bi_template add column kernel_version text;
alter table bi_template_item add column source_ref text;
comment on column bi_template.template_kind is 'BI-PLC-01. register: a Section F register template from the kernel (available to every industry); industry: an industry walkthrough from the kernel overlay; tenant: a template a tenant made.';
comment on column bi_template.kernel_version is 'BI-PLC-01. The Care Net kernel release the template was built from (msp_kernel_version.semver).';
comment on column bi_template_item.source_ref is 'BI-PLC-01. Where the line comes from in the kernel, for example guidance:HSF-F-02#common_gaps[1] or hsf_element_industry:HSF-OV-MINING-03@MINING. Nothing on a kernel template is typed in by hand.';

create table bi_template_industry (
  template_id uuid not null references bi_template(id),
  industry_code text not null references msp_industry(code),
  source_ref text not null,
  primary key (template_id, industry_code)
);
comment on table bi_template_industry is 'BI-PLC-01. The kernel templates suggested to an industry: its walkthrough and the Section F registers its triggers switch on. Every Section F register stays available to every industry.';

-- 5. The place inspected ---------------------------------------------------------------------------

alter table bi_inspection add column place_id uuid references bi_place(id);
alter table bi_inspection_area add column place_id uuid references bi_place(id);
create index bi_inspection_place_idx on bi_inspection(place_id);

create function bi_place_root(p_place uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  with recursive up as (
    select id, parent_id from bi_place where id = p_place
    union all
    select p.id, p.parent_id from bi_place p join up on p.id = up.parent_id
  )
  select id from up where parent_id is null limit 1;
$$;
comment on function bi_place_root is 'BI-PLC-01. The top level place (the site) a place sits under.';

create function bi_inspection_place_check()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_company uuid;
begin
  if new.place_id is null then
    return new;
  end if;
  if tg_table_name = 'bi_inspection' then
    if not exists (select 1 from bi_place p where p.id = new.place_id and p.client_account_id = new.client_account_id and p.archived_at is null) then
      raise exception 'The place is not a live place of this company';
    end if;
    if bi_place_root(new.place_id) is distinct from new.site_id then
      raise exception 'The place is not under the inspection''s site';
    end if;
  else
    select i.client_account_id into v_company from bi_inspection i where i.id = new.inspection_id;
    if not exists (select 1 from bi_place p where p.id = new.place_id and p.client_account_id = v_company) then
      raise exception 'The area''s place belongs to another company';
    end if;
  end if;
  return new;
end;
$$;
create trigger bi_inspection_place_check before insert or update of place_id, site_id on bi_inspection for each row execute function bi_inspection_place_check();
create trigger bi_inspection_area_place_check before insert or update of place_id on bi_inspection_area for each row execute function bi_inspection_place_check();

-- 6. Evidence storage -------------------------------------------------------------------------------

create table bi_evidence_blob (
  client_account_id uuid not null references msp_client_account(id),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes bigint not null check (size_bytes > 0),
  mime_type text not null,
  object_key text not null check (object_key ~ '^[0-9a-f-]{36}/cas/sha256/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{64}$'),
  variant text not null default 'original' check (variant in ('original','thumb','web')),
  derived_from_sha256 text check (derived_from_sha256 is null or derived_from_sha256 ~ '^[0-9a-f]{64}$'),
  exif_stripped boolean not null default false,
  uploaded_at timestamptz,
  verified_sha256 text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (client_account_id, sha256),
  check ((variant = 'original') = (derived_from_sha256 is null)),
  check (variant = 'original' or exif_stripped),
  check (verified_at is null or verified_sha256 = sha256),
  check (object_key = client_account_id::text || '/cas/sha256/' || substr(sha256, 1, 2) || '/' || substr(sha256, 3, 2) || '/' || sha256)
);
comment on table bi_evidence_blob is 'BI-PLC-01. Content addressed evidence bytes in the private bi-evidence bucket, one row per company and SHA 256 (deduplicated per company, never across companies). The original is immutable; thumb and web are derived copies with the camera metadata removed. verified_sha256 is the hash the server computed after the upload, and must equal the key. Written by the upload functions (service role) only.';

create table bi_evidence_upload_session (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 52428800),
  chunk_bytes int not null check (chunk_bytes between 262144 and 16777216),
  chunks_total int not null check (chunks_total >= 1),
  chunks_received int[] not null default '{}',
  status text not null default 'open' check (status in ('open','assembled','verified','failed','expired')),
  created_by uuid references bi_app_user(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  check (chunks_total = ceil(size_bytes::numeric / chunk_bytes))
);
comment on table bi_evidence_upload_session is 'BI-PLC-01. A resumable, chunked upload of one blob: the phone sends the chunks not yet received, the server assembles them, hashes the result and marks the session verified only when the hash matches. Server side only (evidence-upload-session, -chunk, -complete; stubs until the staging backend exists).';
create index bi_evidence_upload_session_blob_idx on bi_evidence_upload_session(client_account_id, sha256);

-- Versions, place, item, tags, retention, legal hold and sidecar on photos and voice notes.
do $$
declare
  t text;
begin
  foreach t in array array['bi_photo','bi_voice_note'] loop
    execute format('alter table %I add column version int not null default 1 check (version >= 1)', t);
    execute format('alter table %I add column root_id uuid references %I(id)', t, t);
    execute format('alter table %I add column supersedes_id uuid references %I(id)', t, t);
    execute format('alter table %I add column canonical_path text check (canonical_path is null or canonical_path ~ ''^tenant/[^/]+/company/[^/]+/place/.+/inspection/[^/]+/item/[^/]+/evidence/[^/]+/v[0-9]+$'')', t);
    execute format('alter table %I add column place_id uuid references bi_place(id)', t);
    execute format('alter table %I add column template_item_id uuid references bi_template_item(id)', t);
    execute format('alter table %I add column device_id text', t);
    execute format('alter table %I add column tags text[] not null default ''{}''', t);
    execute format('alter table %I add column retention_class text', t);
    execute format('alter table %I add column legal_hold boolean not null default false', t);
    execute format('alter table %I add column sidecar_sha256 text check (sidecar_sha256 is null or sidecar_sha256 ~ ''^[0-9a-f]{64}$'')', t);
    execute format('alter table %I add constraint %I check ((version = 1) = (supersedes_id is null) and (supersedes_id is null) = (root_id is null))', t, t || '_version_shape');
    execute format('create unique index %I on %I(supersedes_id) where supersedes_id is not null', t || '_one_successor_idx', t);
    execute format('create unique index %I on %I(coalesce(root_id, id), version)', t || '_version_idx', t);
  end loop;
end;
$$;

-- Content addressed paths: the company scoped address is allowed, and versions share it.
alter table bi_photo drop constraint bi_photo_storage_path_check;
alter table bi_photo drop constraint bi_photo_storage_path_key;
alter table bi_photo add constraint bi_photo_storage_path_check
  check (storage_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$' or storage_path ~ '^[0-9a-f-]{36}/cas/sha256/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{64}$');
alter table bi_voice_note drop constraint bi_voice_note_audio_path_check;
alter table bi_voice_note drop constraint bi_voice_note_audio_path_key;
alter table bi_voice_note add constraint bi_voice_note_audio_path_check
  check (audio_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$' or audio_path ~ '^[0-9a-f-]{36}/cas/sha256/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{64}$');
-- A voice note keeps its VN number through its versions: one number per first version.
alter table bi_voice_note drop constraint bi_voice_note_inspection_id_vn_number_key;
create unique index bi_voice_note_vn_number_idx on bi_voice_note(inspection_id, vn_number) where supersedes_id is null;

create function bi_evidence_version_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_prev jsonb;
  v_new jsonb := to_jsonb(new);
  k text;
begin
  if tg_op = 'UPDATE' then
    if bi_is_client_session() then
      -- Never overwrite: a correction is a new version (a new row).
      foreach k in array array['caption','annotations','tags','canonical_path','place_id','template_item_id','version','root_id','supersedes_id','sidecar_sha256','retention_class','device_id'] loop
        if v_new ? k and (v_new -> k) is distinct from (to_jsonb(old) -> k) then
          raise exception '% is not changed in place: save a correction as a new version', k;
        end if;
      end loop;
      if new.legal_hold is distinct from old.legal_hold then
        raise exception 'Legal hold is set by Care Net or the company admin only';
      end if;
    end if;
    return new;
  end if;
  -- INSERT
  if bi_is_client_session() and new.legal_hold then
    raise exception 'Legal hold is set by Care Net or the company admin only';
  end if;
  if new.supersedes_id is null then
    return new;
  end if;
  execute format('select to_jsonb(x) from %I x where x.id = $1', tg_table_name) into v_prev using new.supersedes_id;
  if v_prev is null then
    raise exception 'The version it corrects was not found';
  end if;
  if (v_prev ->> 'inspection_id') is distinct from (v_new ->> 'inspection_id') then
    raise exception 'A version stays with its inspection';
  end if;
  foreach k in array case when tg_table_name = 'bi_photo'
      then array['sha256','size_bytes','mime_type','captured_at','gps_lat','gps_lng','inspector_user_id','storage_path']
      else array['audio_sha256','size_bytes','mime_type','duration_seconds','captured_at','gps_lat','gps_lng','inspector_user_id','audio_path'] end
  loop
    if (v_new -> k) is distinct from (v_prev -> k) then
      raise exception 'A correction cannot change %; changed bytes are new evidence', k;
    end if;
  end loop;
  if new.version <> (v_prev ->> 'version')::int + 1 then
    raise exception 'A correction is version % of this evidence, not %', (v_prev ->> 'version')::int + 1, new.version;
  end if;
  if new.root_id is distinct from coalesce((v_prev ->> 'root_id')::uuid, (v_prev ->> 'id')::uuid) then
    raise exception 'A correction points at the first version of its evidence';
  end if;
  if tg_table_name = 'bi_voice_note' then
    -- The capture guard numbered it as a new note; a version keeps the first version's number.
    new.vn_number := (v_prev ->> 'vn_number')::int;
  end if;
  return new;
end;
$$;
comment on function bi_evidence_version_guard is 'BI-PLC-01. Evidence is never overwritten. A client cannot change a photo''s or voice note''s caption, markers, tags, path, place or version fields in place, nor set legal hold; a correction is a new row with supersedes_id, version = previous + 1, root_id = the first version, and the same bytes, capture time, GPS and inspector (so the same blob and the same seal). One successor per version (a straight chain).';
create trigger bi_photo_version_guard before insert or update on bi_photo for each row execute function bi_evidence_version_guard();
create trigger bi_voice_note_version_guard before insert or update on bi_voice_note for each row execute function bi_evidence_version_guard();

-- Used storage counts each distinct blob once (dedupe), plus the derived copies.
create or replace function bi_storage_used_bytes(p_tenant uuid, p_company uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select (coalesce((select sum(size_bytes) from (select distinct on (sha256) sha256, size_bytes from bi_photo
                                                  where tenant_id = p_tenant and client_account_id = p_company) p), 0)
        + coalesce((select sum(size_bytes) from (select distinct on (audio_sha256) audio_sha256, size_bytes from bi_voice_note
                                                  where tenant_id = p_tenant and client_account_id = p_company) v), 0)
        + coalesce((select sum(size_bytes) from bi_evidence_blob where client_account_id = p_company and variant <> 'original'), 0))::bigint;
$$;
comment on function bi_storage_used_bytes is 'BI-PLC-01 (replaces BI-WAL-01). Bytes of a company line: every distinct photo and voice note blob once (versions and repeats share their bytes), plus the derived thumbnails and web copies.';

-- 7. Search ----------------------------------------------------------------------------------------------

create table bi_search_doc (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  source_kind text not null check (source_kind in ('finding','transcript','evidence','place')),
  source_id uuid not null,
  place_id uuid,
  inspection_id uuid,
  title text not null default '',
  body text not null default '',
  tags text[] not null default '{}',
  tsv tsvector not null default ''::tsvector,
  updated_at timestamptz not null default now(),
  unique (source_kind, source_id)
);
comment on table bi_search_doc is 'BI-PLC-01. The full text index of Bee-Inspect: findings (item and note), transcripts (latest version), evidence metadata (caption, tags, markers, path) and places. tsv weights the title (A), tags (B) and body (C). Kept by triggers; read under RLS; queried with bi_search. The phone keeps the same documents in SQLite FTS5.';
create index bi_search_doc_tsv_idx on bi_search_doc using gin(tsv);
create index bi_search_doc_company_idx on bi_search_doc(client_account_id);

create function bi_search_doc_tsv()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.tsv := setweight(to_tsvector('english', coalesce(new.title, '')), 'A')
          || setweight(to_tsvector('english', array_to_string(new.tags, ' ')), 'B')
          || setweight(to_tsvector('english', coalesce(new.body, '')), 'C');
  new.updated_at := now();
  return new;
end;
$$;
create trigger bi_search_doc_tsv before insert or update on bi_search_doc for each row execute function bi_search_doc_tsv();

create function bi_search_index()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_body text;
  v_tags text[] := '{}';
  v_kind text;
  v_place uuid;
  v_insp uuid;
  v_tenant uuid;
  v_company uuid;
  v_source uuid := new.id;
begin
  if tg_table_name = 'bi_finding' then
    v_kind := 'finding';
    select coalesce(ti.prompt, 'Finding') into v_title from (select 1) x left join bi_template_item ti on ti.id = new.template_item_id;
    v_body := coalesce(new.note, '');
    v_tags := array[case new.result when 'na' then 'n/a' else new.result end] || case when new.severity is null then '{}'::text[] else array[new.severity] end;
    select a.place_id into v_place from bi_inspection_area a where a.id = new.area_id;
    v_insp := new.inspection_id; v_tenant := new.tenant_id; v_company := new.client_account_id;
  elsif tg_table_name = 'bi_voice_transcript' then
    v_kind := 'transcript';
    v_source := new.voice_note_id;
    select 'Voice note VN-' || coalesce(vn.vn_number::text, ''), vn.place_id, vn.inspection_id, vn.tags into v_title, v_place, v_insp, v_tags
      from bi_voice_note vn where vn.id = new.voice_note_id;
    v_body := new.body; v_tenant := new.tenant_id; v_company := new.client_account_id;
  elsif tg_table_name = 'bi_photo' then
    v_kind := 'evidence';
    v_title := coalesce(new.caption, 'Photo');
    v_body := coalesce(new.canonical_path, '') || ' ' || coalesce((select string_agg(a ->> 'label', ' ') from jsonb_array_elements(new.annotations) a), '');
    v_tags := new.tags || array['photo', replace(new.kind, '_', ' ')];
    v_place := new.place_id; v_insp := new.inspection_id; v_tenant := new.tenant_id; v_company := new.client_account_id;
    -- Only the newest version is searched: the version it supersedes leaves the index.
    if new.supersedes_id is not null then
      delete from bi_search_doc where source_kind = 'evidence' and source_id = new.supersedes_id;
    end if;
  else -- bi_place
    v_kind := 'place';
    v_title := new.name;
    v_body := coalesce(new.address, '') || ' ' || coalesce(new.responsible_person, '');
    v_tags := array[(select t.label from bi_place_type t where t.code = new.place_type)] || case when new.custom_type_label is null then '{}'::text[] else array[new.custom_type_label] end;
    v_place := new.id; v_company := new.client_account_id;
    if new.archived_at is not null then
      delete from bi_search_doc where source_kind = 'place' and source_id = new.id;
      return null;
    end if;
  end if;
  insert into bi_search_doc (tenant_id, client_account_id, source_kind, source_id, place_id, inspection_id, title, body, tags)
  values (v_tenant, v_company, v_kind, v_source, v_place, v_insp, coalesce(v_title, ''), coalesce(v_body, ''), coalesce(v_tags, '{}'))
  on conflict (source_kind, source_id) do update
     set title = excluded.title, body = excluded.body, tags = excluded.tags, place_id = excluded.place_id, inspection_id = excluded.inspection_id;
  return null;
end;
$$;
comment on function bi_search_index is 'BI-PLC-01. Keeps bi_search_doc current from findings, transcripts (the latest version replaces the text), photos (only the newest version is searched) and places (archived places leave the index).';
create trigger bi_finding_search after insert or update of note, result, severity on bi_finding for each row execute function bi_search_index();
create trigger bi_voice_transcript_search after insert on bi_voice_transcript for each row execute function bi_search_index();
create trigger bi_photo_search after insert on bi_photo for each row execute function bi_search_index();
create trigger bi_place_search after insert or update of name, address, responsible_person, custom_type_label, archived_at on bi_place for each row execute function bi_search_index();

create function bi_search_query(p_text text)
returns tsquery
language sql
immutable
set search_path = public
as $$
  -- Every word as a prefix, all of them required: "toe bo" finds "toe boards".
  select case when count(*) = 0 then null
              else to_tsquery('english', string_agg(quote_literal(w) || ':*', ' & ')) end
    from regexp_split_to_table(lower(coalesce(p_text, '')), '[^a-z0-9]+') w
   where length(w) > 0;
$$;

create function bi_search(p_query text, p_company uuid default null, p_limit int default 50)
returns table (source_kind text, source_id uuid, place_id uuid, inspection_id uuid, title text, rank real)
language sql
stable
security invoker
set search_path = public
as $$
  -- Security invoker: the caller's RLS on bi_search_doc decides what is found.
  select d.source_kind, d.source_id, d.place_id, d.inspection_id, d.title, ts_rank(d.tsv, q) as rank
    from bi_search_doc d, (select bi_search_query(p_query) as q) x
   where x.q is not null and d.tsv @@ x.q and (p_company is null or d.client_account_id = p_company)
   order by rank desc, d.updated_at desc
   limit greatest(1, least(p_limit, 200));
$$;
comment on function bi_search is 'BI-PLC-01. Full text search over what the caller may read (RLS), every word a prefix, best first.';

-- 8. Row Level Security -------------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['bi_place_type','bi_place_type_industry','bi_place','bi_template_industry',
                           'bi_evidence_blob','bi_evidence_upload_session','bi_search_doc'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;

grant select on bi_place_type, bi_place_type_industry, bi_template_industry, bi_place, bi_evidence_blob, bi_search_doc to authenticated;
grant insert, update on bi_place to authenticated;

-- Reference lists: any signed in person may read them.
create policy bi_place_type_read on bi_place_type for select to authenticated using (true);
create policy bi_place_type_industry_read on bi_place_type_industry for select to authenticated using (true);
create policy bi_template_industry_read on bi_template_industry for select to authenticated
  using (exists (select 1 from bi_template t where t.id = template_id
                  and (bi_is_ops() or (t.status = 'published' and (t.tenant_id is null or t.tenant_id = bi_my_tenant())))));
-- Places: like the sites tree (read by anyone with a role on the company; written by an inspector or the company admin).
create policy bi_place_read on bi_place for select to authenticated using (bi_can_company(client_account_id, 'read_capture'));
create policy bi_place_insert on bi_place for insert to authenticated
  with check (bi_can_company(client_account_id, 'write_capture') or bi_can_company(client_account_id, 'manage_company'));
create policy bi_place_update on bi_place for update to authenticated
  using (bi_can_company(client_account_id, 'write_capture') or bi_can_company(client_account_id, 'manage_company'))
  with check (bi_can_company(client_account_id, 'write_capture') or bi_can_company(client_account_id, 'manage_company'));
-- Blobs and the search index: read where the evidence may be read; written by the server only.
create policy bi_evidence_blob_read on bi_evidence_blob for select to authenticated using (bi_can_company(client_account_id, 'read_capture'));
create policy bi_search_doc_read on bi_search_doc for select to authenticated
  using (case when tenant_id is null then bi_can_company(client_account_id, 'read_capture') else bi_can(tenant_id, client_account_id, 'read_capture') end);
-- bi_evidence_upload_session: no authenticated policy at all (service role only).

do $$
declare
  f text;
begin
  foreach f in array array['bi_place_guard()','bi_place_site_sync()','bi_company_kernel_guard()','bi_inspection_place_check()',
                           'bi_evidence_version_guard()','bi_search_doc_tsv()','bi_search_index()'] loop
    execute format('revoke execute on function %s from public, anon', f);
  end loop;
  foreach f in array array['bi_place_root(uuid)','bi_search_query(text)','bi_search(text, uuid, int)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
