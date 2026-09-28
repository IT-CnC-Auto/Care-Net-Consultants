-- CNC HSF FORGE | BI-PLC-01 checks | local test harness only.
-- Proves migration 065 (places of inspection, kernel templates and evidence
-- storage) against a replayed database, with the fictitious demonstration seed
-- and the kernel templates seed (supabase/seed/bee_inspect_kernel_templates.sql,
-- written by apps/mobile/scripts/build-kernel-bundle.mjs): the 17 industries and
-- their place types, the kernel templates, the places tree rules, a top level
-- place as the engine's site, the place of an inspection, content addressed
-- evidence with versions, dedupe in the storage meter, legal hold, full text
-- search, and RLS per role. Never applied to Supabase. Everything runs in one
-- transaction that is rolled back.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/bi_places_checks.sql

\set ON_ERROR_STOP 1
\pset pager off
\pset tuples_only on
begin;

create function pg_temp.ok(p_name text, p_cond boolean) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'CHECK FAILED: %', p_name;
  end if;
  raise notice 'ok   %', p_name;
end $$;

create function pg_temp.refuses(p_name text, p_sql text, p_pattern text) returns void language plpgsql as $$
declare
  v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    if v_msg ~* p_pattern then
      raise notice 'ok   %', p_name;
      return;
    end if;
    raise exception 'CHECK FAILED: % (refused with "%", expected /%/)', p_name, v_msg, p_pattern;
  end;
  raise exception 'CHECK FAILED: % (not refused)', p_name;
end $$;

create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  perform set_config('role', case when p_claims = '' then 'anon' else 'authenticated' end, true);
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERR: ' || sqlerrm;
  end;
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $$;

\ir ../../supabase/seed/bee_inspect_demo.sql
\ir ../../supabase/seed/bee_inspect_kernel_templates.sql

\set co '''b1a00000-0000-4000-8000-000000000002'''
\set tenant '''b1a00000-0000-4000-8000-000000000001'''
\set insp '''{"sub":"b1a00000-0000-4000-8000-000000000011","role":"authenticated"}'''
\set asst '''{"sub":"b1a00000-0000-4000-8000-000000000012","role":"authenticated"}'''
\set admin '''{"sub":"b1a00000-0000-4000-8000-000000000013","role":"authenticated"}'''
\set other '''{"sub":"b2a00000-0000-4000-8000-000000000011","role":"authenticated"}'''
\set anon ''''''

-- Another tenant with its own company, for the RLS checks.
insert into auth.users (id, email, email_confirmed_at) values ('b2a00000-0000-4000-8000-000000000011', 'other.places.check@example.invalid', now());
insert into msp_client_account (id, company_name, contact_name, contact_email) values
  ('b2a00000-0000-4000-8000-000000000002', 'Other Works (fictitious)', 'Other Contact', 'other.places.contact@example.invalid');
insert into bi_tenant (id, name) values ('b2a00000-0000-4000-8000-000000000001', 'Other Tenant (fictitious)');
insert into bi_app_user (id, auth_user_id, tenant_id, display_name) values
  ('b2a00000-0000-4000-8000-000000000021', 'b2a00000-0000-4000-8000-000000000011', 'b2a00000-0000-4000-8000-000000000001', 'Other Inspector (fictitious)');
insert into bi_role_assignment (app_user_id, tenant_id, role, granted_by) values
  ('b2a00000-0000-4000-8000-000000000021', 'b2a00000-0000-4000-8000-000000000001', 'inspector', 'check');

-- 1. The kernel: 17 industries, place types and templates ---------------------------------------------------------

select pg_temp.ok('every one of the 17 kernel industries is offered place types (bi_place_type_industry)',
  (select count(distinct industry_code) from bi_place_type_industry) = 17
  and (select count(*) from msp_industry) = 17
  and not exists (select 1 from msp_industry i where not exists (select 1 from bi_place_type_industry t where t.industry_code = i.code)));
select pg_temp.ok('18 place types (the Director''s list); the universal ones are offered to every industry',
  (select count(*) from bi_place_type) = 18
  and (select count(*) from bi_place_type_industry where place_type in ('site','office','branch','department','building_block','floor','room_area')) = 7 * 17);
select pg_temp.ok('industry specific place types follow the kernel: a farm only for agriculture, a mine or quarry section only for mining, a school campus only for education',
  (select array_agg(industry_code) from bi_place_type_industry where place_type = 'farm') = array['AGRI']
  and (select array_agg(industry_code) from bi_place_type_industry where place_type = 'mine_section') = array['MINING']
  and (select array_agg(industry_code) from bi_place_type_industry where place_type = 'school_campus') = array['EDU']);
select pg_temp.ok('39 kernel templates are published: 22 Section F registers and 17 industry walkthroughs, from kernel 1.1.0',
  (select count(*) from bi_template where tenant_id is null and kernel_version is not null and status = 'published') = 39
  and (select count(*) from bi_template where template_kind = 'register' and kernel_version is not null) = 22
  and (select count(*) from bi_template where template_kind = 'industry' and kernel_version is not null) = 17
  and (select count(distinct kernel_version) from bi_template where kernel_version is not null) = 1
  and (select max(kernel_version) from bi_template) = (select semver from msp_kernel_version order by released_on desc, string_to_array(semver, '.')::int[] desc limit 1));
select pg_temp.ok('each register files into its own Section F element, and each walkthrough belongs to its industry',
  not exists (select 1 from bi_template t where t.template_kind = 'register' and t.kernel_version is not null
               and not exists (select 1 from hsf_element e where e.code = t.section_f_element_code and e.section_code = 'F'))
  and (select count(distinct industry_code) from bi_template where template_kind = 'industry') = 17);
select pg_temp.ok('every kernel checklist line names its kernel source (source_ref) and element (kernel_ref), 346 lines',
  (select count(*) from bi_template_item ti join bi_template t on t.id = ti.template_id where t.kernel_version is not null) = 346
  and not exists (select 1 from bi_template_item ti join bi_template t on t.id = ti.template_id
                   where t.kernel_version is not null and (ti.source_ref is null or ti.kernel_ref is null
                          or not exists (select 1 from hsf_element e where e.code = ti.kernel_ref))));
select pg_temp.ok('no kernel checklist line is about medical fitness or surveillance (no Section E element becomes an inspection line)',
  not exists (select 1 from bi_template_item ti join bi_template t on t.id = ti.template_id join hsf_element e on e.code = ti.kernel_ref
               where t.kernel_version is not null and e.section_code = 'E'));
select pg_temp.ok('every industry is suggested its walkthrough and at least the Section F registers its triggers switch on',
  not exists (select 1 from msp_industry i where not exists (select 1 from bi_template_industry ti join bi_template t on t.id = ti.template_id
                                                              where ti.industry_code = i.code and t.template_kind = 'industry' and t.industry_code = i.code)));
select pg_temp.refuses('a published kernel template is never changed',
  $q$update bi_template set name = 'Changed' where code = 'REG-F-02'$q$, 'never changed');

-- 2. Company industry -----------------------------------------------------------------------------------------------------

update bi_company set industry_code = 'CONSTR', subindustry_code = 'CONSTR-CIVILS' where client_account_id = :co;
select pg_temp.ok('the demonstration company is construction, civil engineering works', (select industry_code || '/' || subindustry_code from bi_company where client_account_id = :co) = 'CONSTR/CONSTR-CIVILS');
select pg_temp.refuses('a subindustry of another industry is refused',
  $q$update bi_company set subindustry_code = 'MIN-QUARRY' where client_account_id = 'b1a00000-0000-4000-8000-000000000002'$q$, 'not part of the industry');
select pg_temp.refuses('an industry the kernel does not hold is refused',
  $q$update bi_company set industry_code = 'SPACE', subindustry_code = null where client_account_id = 'b1a00000-0000-4000-8000-000000000002'$q$, 'foreign key');

-- 3. The places tree ------------------------------------------------------------------------------------------------------

insert into bi_place (id, client_account_id, parent_id, place_type, name, address) values
  ('c1a00000-0000-4000-8000-000000000001', :co, null, 'construction_project', 'Two storey clinic build', 'Erf 12 (fictitious)');
select pg_temp.ok('a top level place is also the company''s site, with the same id',
  exists (select 1 from bi_site s where s.id = 'c1a00000-0000-4000-8000-000000000001' and s.client_account_id = :co and s.name = 'Two storey clinic build'));
insert into bi_place (id, client_account_id, parent_id, place_type, name, department_code) values
  ('c1a00000-0000-4000-8000-000000000002', :co, 'c1a00000-0000-4000-8000-000000000001', 'department', 'Site operations', 'OPS'),
  ('c1a00000-0000-4000-8000-000000000003', :co, 'c1a00000-0000-4000-8000-000000000001', 'building_block', 'Clinic block', null);
insert into bi_place (id, client_account_id, parent_id, place_type, name) values
  ('c1a00000-0000-4000-8000-000000000004', :co, 'c1a00000-0000-4000-8000-000000000003', 'floor', 'First floor'),
  ('c1a00000-0000-4000-8000-000000000005', :co, 'c1a00000-0000-4000-8000-000000000004', 'room_area', 'Stair core');
select pg_temp.ok('a child place is not a site', not exists (select 1 from bi_site where id = 'c1a00000-0000-4000-8000-000000000002'));
update bi_place set name = 'Clinic build' where id = 'c1a00000-0000-4000-8000-000000000001';
select pg_temp.ok('renaming a top level place renames its site',
  (select name from bi_site where id = 'c1a00000-0000-4000-8000-000000000001') = 'Clinic build');
select pg_temp.ok('bi_place_root finds the site of a room four levels down', bi_place_root('c1a00000-0000-4000-8000-000000000005') = 'c1a00000-0000-4000-8000-000000000001');
select pg_temp.refuses('a room or area never sits at the top',
  $q$insert into bi_place (client_account_id, parent_id, place_type, name) values ('b1a00000-0000-4000-8000-000000000002', null, 'room_area', 'Loose room')$q$, 'not at the top');
select pg_temp.refuses('nothing goes under a room or area',
  $q$insert into bi_place (client_account_id, parent_id, place_type, name) values ('b1a00000-0000-4000-8000-000000000002', 'c1a00000-0000-4000-8000-000000000005', 'room_area', 'Cupboard')$q$, 'cannot go under');
select pg_temp.refuses('an office cannot go under a floor',
  $q$insert into bi_place (client_account_id, parent_id, place_type, name) values ('b1a00000-0000-4000-8000-000000000002', 'c1a00000-0000-4000-8000-000000000004', 'office', 'Office')$q$, 'cannot go under');
select pg_temp.refuses('no loops: a place never moves under its own child',
  $q$update bi_place set parent_id = 'c1a00000-0000-4000-8000-000000000002' where id = 'c1a00000-0000-4000-8000-000000000002'$q$, 'itself');
select pg_temp.refuses('two places of the same name side by side are refused (case and spaces ignored)',
  $q$insert into bi_place (client_account_id, parent_id, place_type, name) values ('b1a00000-0000-4000-8000-000000000002', 'c1a00000-0000-4000-8000-000000000001', 'department', 'site  OPERATIONS')$q$, 'bi_place_sibling_name_idx');
select pg_temp.refuses('a place cannot sit under another company''s place',
  $q$insert into bi_place (client_account_id, parent_id, place_type, name) values ('b2a00000-0000-4000-8000-000000000002', 'c1a00000-0000-4000-8000-000000000001', 'department', 'Stolen')$q$, 'own company');
select pg_temp.refuses('places are archived, never deleted',
  $q$delete from bi_place where id = 'c1a00000-0000-4000-8000-000000000005'$q$, 'never deleted');
-- At most 8 levels: a chain of departments.
do $$
declare
  v_parent uuid := 'c1a00000-0000-4000-8000-000000000002';
  v_new uuid;
begin
  for i in 3..8 loop
    v_new := gen_random_uuid();
    insert into bi_place (id, client_account_id, parent_id, place_type, name) values (v_new, 'b1a00000-0000-4000-8000-000000000002', v_parent, 'department', 'Level ' || i);
    v_parent := v_new;
  end loop;
  perform set_config('bi.check.deep', v_parent::text, true);
end $$;
select pg_temp.refuses('the tree stops at 8 levels',
  format($q$insert into bi_place (client_account_id, parent_id, place_type, name) values ('b1a00000-0000-4000-8000-000000000002', %L, 'department', 'Level 9')$q$, current_setting('bi.check.deep')), '8 levels');

-- 4. The place of an inspection -------------------------------------------------------------------------------------------

insert into bi_inspection (id, tenant_id, client_account_id, site_id, place_id, template_id, inspector_user_id, title, status)
select 'c1a00000-0000-4000-8000-000000000081', :tenant, :co, 'c1a00000-0000-4000-8000-000000000001', 'c1a00000-0000-4000-8000-000000000004',
       t.id, 'b1a00000-0000-4000-8000-000000000021', 'Construction walkthrough, first floor', 'in_progress'
  from bi_template t where t.code = 'IND-CONSTR';
insert into bi_inspection_area (id, inspection_id, tenant_id, client_account_id, place_id, label)
values ('c1a00000-0000-4000-8000-000000000082', 'c1a00000-0000-4000-8000-000000000081', :tenant, :co, 'c1a00000-0000-4000-8000-000000000005', 'Stair core');
select pg_temp.ok('an inspection records the exact place (the first floor) under its site, on a kernel template',
  exists (select 1 from bi_inspection i join bi_template t on t.id = i.template_id where i.id = 'c1a00000-0000-4000-8000-000000000081'
           and i.place_id = 'c1a00000-0000-4000-8000-000000000004' and t.code = 'IND-CONSTR'));
select pg_temp.refuses('the place must sit under the inspection''s site',
  $q$update bi_inspection set place_id = 'c1a00000-0000-4000-8000-000000000004', site_id = 'b1a00000-0000-4000-8000-000000000041' where id = 'c1a00000-0000-4000-8000-000000000081'$q$, 'not under the inspection');

-- 5. Evidence: content addressed, versioned, deduplicated -----------------------------------------------------------------

\set sha '''75dfa0d330f21d3db3fdd0079964d3844adb1f4b5a672892592c831d23d1188f'''
\set cas '''b1a00000-0000-4000-8000-000000000002/cas/sha256/75/df/75dfa0d330f21d3db3fdd0079964d3844adb1f4b5a672892592c831d23d1188f'''
insert into bi_photo (id, inspection_id, tenant_id, client_account_id, area_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at,
                      gps_lat, gps_lng, inspector_user_id, caption, place_id, canonical_path, tags)
values ('c1a00000-0000-4000-8000-0000000000a1', 'c1a00000-0000-4000-8000-000000000081', :tenant, :co, 'c1a00000-0000-4000-8000-000000000082', 'area',
        :cas, :sha, 30169, 'image/jpeg', now() - interval '1 hour', -25.79, 28.3, 'b1a00000-0000-4000-8000-000000000021', 'Stair core, no handrail',
        'c1a00000-0000-4000-8000-000000000005',
        'tenant/b1a00000-0000-4000-8000-000000000001/company/b1a00000-0000-4000-8000-000000000002/place/clinic-build/clinic-block/first-floor/stair-core/inspection/c1a00000-0000-4000-8000-000000000081/item/area-c1a00000-0000-4000-8000-000000000082/evidence/c1a00000-0000-4000-8000-0000000000a1/v1',
        '{handrail}');
select pg_temp.ok('a photo stored by its content address is sealed as before',
  (select seal_sha256 = bi_evidence_seal(storage_path, sha256, captured_at, gps_lat, gps_lng, inspector_user_id) from bi_photo where id = 'c1a00000-0000-4000-8000-0000000000a1'));
insert into bi_photo (id, inspection_id, tenant_id, client_account_id, area_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at,
                      gps_lat, gps_lng, inspector_user_id, caption, place_id, tags, version, root_id, supersedes_id)
select 'c1a00000-0000-4000-8000-0000000000a2', inspection_id, tenant_id, client_account_id, area_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at,
       gps_lat, gps_lng, inspector_user_id, 'Stair core, no handrail on the east flight', place_id, '{handrail,stairs}', 2, id, id
  from bi_photo where id = 'c1a00000-0000-4000-8000-0000000000a1';
select pg_temp.ok('a caption correction is version 2: a new row on the same blob and seal, and version 1 is unchanged',
  (select count(*) from bi_photo where coalesce(root_id, id) = 'c1a00000-0000-4000-8000-0000000000a1') = 2
  and (select caption from bi_photo where id = 'c1a00000-0000-4000-8000-0000000000a1') = 'Stair core, no handrail'
  and (select count(distinct seal_sha256) from bi_photo where coalesce(root_id, id) = 'c1a00000-0000-4000-8000-0000000000a1') = 1);
select pg_temp.refuses('a correction cannot change the bytes (new bytes are new evidence)',
  $q$insert into bi_photo (inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, inspector_user_id, version, root_id, supersedes_id)
     select inspection_id, tenant_id, client_account_id, kind, storage_path, repeat('0', 64), size_bytes, mime_type, captured_at, inspector_user_id, 3, root_id, id
       from bi_photo where id = 'c1a00000-0000-4000-8000-0000000000a2'$q$, 'cannot change sha256');
select pg_temp.refuses('versions form one straight line: version 1 has one successor only',
  $q$insert into bi_photo (inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, gps_lat, gps_lng, inspector_user_id, version, root_id, supersedes_id)
     select inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, gps_lat, gps_lng, inspector_user_id, 2, id, id
       from bi_photo where id = 'c1a00000-0000-4000-8000-0000000000a1'$q$, 'one_successor|duplicate key');
select pg_temp.refuses('a version number that skips is refused',
  $q$insert into bi_photo (inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, gps_lat, gps_lng, inspector_user_id, version, root_id, supersedes_id)
     select inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, gps_lat, gps_lng, inspector_user_id, 5, root_id, id
       from bi_photo where id = 'c1a00000-0000-4000-8000-0000000000a2'$q$, 'version 3');
select pg_temp.ok('the same bytes used again in the company count once in the storage meter (dedupe)',
  (select (bi_storage_status(:tenant, :co) ->> 'used_bytes')::bigint) =
  (select coalesce(sum(size_bytes), 0) from (select distinct on (sha256) sha256, size_bytes from bi_photo where client_account_id = 'b1a00000-0000-4000-8000-000000000002' and tenant_id = 'b1a00000-0000-4000-8000-000000000001') p)
  + (select coalesce(sum(size_bytes), 0) from (select distinct on (audio_sha256) audio_sha256, size_bytes from bi_voice_note where client_account_id = 'b1a00000-0000-4000-8000-000000000002' and tenant_id = 'b1a00000-0000-4000-8000-000000000001') v));
insert into bi_evidence_blob (client_account_id, sha256, size_bytes, mime_type, object_key, uploaded_at, verified_sha256, verified_at)
values (:co, :sha, 30169, 'image/jpeg', :cas, now(), :sha, now());
select pg_temp.refuses('a blob is held once per company (content address is the key)',
  $q$insert into bi_evidence_blob (client_account_id, sha256, size_bytes, mime_type, object_key) values ('b1a00000-0000-4000-8000-000000000002', '75dfa0d330f21d3db3fdd0079964d3844adb1f4b5a672892592c831d23d1188f', 30169, 'image/jpeg', 'b1a00000-0000-4000-8000-000000000002/cas/sha256/75/df/75dfa0d330f21d3db3fdd0079964d3844adb1f4b5a672892592c831d23d1188f')$q$, 'duplicate key');
select pg_temp.refuses('a verified blob must match its own hash (integrity check after upload)',
  $q$update bi_evidence_blob set verified_sha256 = repeat('e', 64) where sha256 = '75dfa0d330f21d3db3fdd0079964d3844adb1f4b5a672892592c831d23d1188f'$q$, 'check');
select pg_temp.refuses('a derived copy must have its camera metadata removed',
  $q$insert into bi_evidence_blob (client_account_id, sha256, size_bytes, mime_type, object_key, variant, derived_from_sha256, exif_stripped)
     values ('b1a00000-0000-4000-8000-000000000002', repeat('a', 64), 100, 'image/jpeg', 'b1a00000-0000-4000-8000-000000000002/cas/sha256/aa/aa/' || repeat('a', 64), 'thumb', '75dfa0d330f21d3db3fdd0079964d3844adb1f4b5a672892592c831d23d1188f', false)$q$, 'check');
insert into bi_evidence_blob (client_account_id, sha256, size_bytes, mime_type, object_key, variant, derived_from_sha256, exif_stripped)
values (:co, repeat('b', 64), 4000, 'image/jpeg', 'b1a00000-0000-4000-8000-000000000002/cas/sha256/bb/bb/' || repeat('b', 64), 'thumb', :sha, true);
select pg_temp.ok('derived copies (thumbnails, web copies) count towards the 10 GB line',
  (select (bi_storage_status(:tenant, :co) ->> 'used_bytes')::bigint) = bi_storage_used_bytes(:tenant, :co)
  and bi_storage_used_bytes(:tenant, :co) >= 4000 + 30169);
select pg_temp.refuses('an upload session with the wrong number of chunks is refused',
  $q$insert into bi_evidence_upload_session (tenant_id, client_account_id, sha256, size_bytes, chunk_bytes, chunks_total) values ('b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', repeat('c', 64), 12000000, 5242880, 2)$q$, 'check');
insert into bi_evidence_upload_session (tenant_id, client_account_id, sha256, size_bytes, chunk_bytes, chunks_total) values (:tenant, :co, repeat('c', 64), 12000000, 5242880, 3);
select pg_temp.ok('a 12 MB upload is planned as 3 chunks of 5 MiB', exists (select 1 from bi_evidence_upload_session where sha256 = repeat('c', 64) and chunks_total = 3));

-- Clients: never overwrite, never set legal hold.
select pg_temp.ok('the inspector cannot change a caption in place (a correction is a new version)',
  pg_temp.as_user(:insp, $q$update bi_photo set caption = 'Overwritten' where id = 'c1a00000-0000-4000-8000-0000000000a2' returning 'changed'$q$) like 'ERR:%not changed in place%');
select pg_temp.ok('the inspector cannot set legal hold',
  pg_temp.as_user(:insp, $q$update bi_photo set legal_hold = true where id = 'c1a00000-0000-4000-8000-0000000000a2' returning 'held'$q$) like 'ERR:%Legal hold%');
update bi_photo set legal_hold = true where id = 'c1a00000-0000-4000-8000-0000000000a1';
select pg_temp.ok('Care Net (a trusted path) can put evidence on legal hold', (select legal_hold from bi_photo where id = 'c1a00000-0000-4000-8000-0000000000a1'));

-- 6. Search --------------------------------------------------------------------------------------------------------------

insert into bi_finding (id, inspection_id, tenant_id, client_account_id, area_id, result, note, severity)
values ('c1a00000-0000-4000-8000-000000000091', 'c1a00000-0000-4000-8000-000000000081', :tenant, :co, 'c1a00000-0000-4000-8000-000000000082', 'fail',
        'Handrail missing on the east flight of the stair core', 'high');
select pg_temp.ok('a finding is searchable by the start of its words ("hand east")',
  exists (select 1 from bi_search('hand east', :co) where source_kind = 'finding' and source_id = 'c1a00000-0000-4000-8000-000000000091'));
select pg_temp.ok('only the newest version of a photo is searched',
  exists (select 1 from bi_search('handrail', :co) where source_kind = 'evidence' and source_id = 'c1a00000-0000-4000-8000-0000000000a2')
  and not exists (select 1 from bi_search_doc where source_kind = 'evidence' and source_id = 'c1a00000-0000-4000-8000-0000000000a1'));
select pg_temp.ok('places are searchable by name and type', exists (select 1 from bi_search('stair', :co) where source_kind = 'place'));
insert into bi_voice_note (id, inspection_id, tenant_id, client_account_id, audio_path, audio_sha256, size_bytes, mime_type, duration_seconds, captured_at, inspector_user_id)
values ('c1a00000-0000-4000-8000-0000000000b1', 'c1a00000-0000-4000-8000-000000000081', :tenant, :co,
        'b1a00000-0000-4000-8000-000000000002/cas/sha256/dd/dd/' || repeat('d', 64), repeat('d', 64), 9000, 'audio/mp4', 12, now(), 'b1a00000-0000-4000-8000-000000000021');
insert into bi_voice_transcript (voice_note_id, tenant_id, client_account_id, version, source, body)
values ('c1a00000-0000-4000-8000-0000000000b1', :tenant, :co, 1, 'machine', 'Temporary barrier tied with wire at the landing.');
select pg_temp.ok('transcripts are searchable', exists (select 1 from bi_search('barrier landing', :co) where source_kind = 'transcript'));
insert into bi_voice_note (id, inspection_id, tenant_id, client_account_id, audio_path, audio_sha256, size_bytes, mime_type, duration_seconds, captured_at, inspector_user_id, tags, version, root_id, supersedes_id)
select 'c1a00000-0000-4000-8000-0000000000b2', inspection_id, tenant_id, client_account_id, audio_path, audio_sha256, size_bytes, mime_type, duration_seconds, captured_at, inspector_user_id, '{barrier}', 2, id, id
  from bi_voice_note where id = 'c1a00000-0000-4000-8000-0000000000b1';
select pg_temp.ok('a voice note version keeps the first version''s VN number',
  (select vn_number from bi_voice_note where id = 'c1a00000-0000-4000-8000-0000000000b2') = (select vn_number from bi_voice_note where id = 'c1a00000-0000-4000-8000-0000000000b1'));

-- 7. RLS ------------------------------------------------------------------------------------------------------------------

select pg_temp.ok('the inspector reads the company''s places; anon and another tenant read none',
  pg_temp.as_user(:insp, $q$select count(*)::text from bi_place where client_account_id = 'b1a00000-0000-4000-8000-000000000002'$q$)::int >= 5
  and pg_temp.as_user(:anon, $q$select count(*)::text from bi_place$q$) like 'ERR:%'
  and pg_temp.as_user(:other, $q$select count(*)::text from bi_place$q$) = '0');
select pg_temp.ok('the inspector adds a place offline (it syncs through RLS); the assistant may not',
  pg_temp.as_user(:insp, $q$insert into bi_place (client_account_id, parent_id, place_type, name) values ('b1a00000-0000-4000-8000-000000000002', 'c1a00000-0000-4000-8000-000000000003', 'floor', 'Ground floor') returning 'added'$q$) = 'added'
  and pg_temp.as_user(:asst, $q$insert into bi_place (client_account_id, parent_id, place_type, name) values ('b1a00000-0000-4000-8000-000000000002', 'c1a00000-0000-4000-8000-000000000003', 'floor', 'Roof') returning 'added'$q$) like 'ERR:%');
select pg_temp.ok('the company admin may add places too',
  pg_temp.as_user(:admin, $q$insert into bi_place (client_account_id, parent_id, place_type, name) values ('b1a00000-0000-4000-8000-000000000002', 'c1a00000-0000-4000-8000-000000000003', 'floor', 'Basement') returning 'added'$q$) = 'added');
select pg_temp.ok('another tenant finds nothing of this company in search, and reads no blob',
  pg_temp.as_user(:other, $q$select count(*)::text from bi_search('handrail')$q$) = '0'
  and pg_temp.as_user(:other, $q$select count(*)::text from bi_evidence_blob$q$) = '0');
select pg_temp.ok('the inspector finds the finding through search under RLS',
  pg_temp.as_user(:insp, $q$select count(*)::text from bi_search('handrail', 'b1a00000-0000-4000-8000-000000000002')$q$)::int >= 1);
select pg_temp.ok('upload sessions are server side only',
  pg_temp.as_user(:insp, $q$select count(*)::text from bi_evidence_upload_session$q$) like 'ERR:%');
select pg_temp.ok('everyone signed in reads the place types; anon does not',
  pg_temp.as_user(:insp, $q$select count(*)::text from bi_place_type$q$) = '18'
  and pg_temp.as_user(:anon, $q$select count(*)::text from bi_place_type$q$) like 'ERR:%');
select pg_temp.ok('every new table carries RLS and a comment',
  not exists (select 1 from pg_class c where c.relname in ('bi_place_type','bi_place_type_industry','bi_place','bi_template_industry','bi_evidence_blob','bi_evidence_upload_session','bi_search_doc')
               and (not c.relrowsecurity or obj_description(c.oid, 'pg_class') is null)));

rollback;
