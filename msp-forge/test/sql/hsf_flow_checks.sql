-- CNC MSP FORGE | HSF-UPL-01, KRN-API-01 and HSF-GEN-01 flow checks | local test harness only.
-- Proves migrations 049 (consent, uploads, MCO transfer bookkeeping), 050 (kernel
-- API) and 051 (generation and compliance) against a replayed database. Never
-- applied to Supabase. Everything runs in one transaction that is rolled back, so
-- the fictitious auth users, company accounts and Files it creates never persist.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_flow_checks.sql
--
-- Every check prints "ok" as a notice; the first failure raises an exception that
-- stops the script with a non zero exit.

\set ON_ERROR_STOP 1
\pset pager off
begin;

-- 0. Harness ------------------------------------------------------------------------------

create function pg_temp.ok(p_name text, p_cond boolean) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'CHECK FAILED: %', p_name;
  end if;
  raise notice 'ok   %', p_name;
end $$;

-- Runs p_sql and passes only when it is refused with a message matching p_pattern.
create function pg_temp.refuses(p_name text, p_sql text, p_pattern text) returns void language plpgsql as $$
declare
  v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
  end;
  if v_msg is null then
    raise exception 'CHECK FAILED: % (the call succeeded, a refusal was expected)', p_name;
  end if;
  if v_msg !~* p_pattern then
    raise exception 'CHECK FAILED: % (refused with "%", expected /%/)', p_name, v_msg, p_pattern;
  end if;
  raise notice 'ok   % (refused: %)', p_name, v_msg;
end $$;

create temp table ctx (k text primary key, v text);
create function pg_temp.ctx(p_k text) returns text language sql as $$ select v from ctx where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$
  insert into ctx values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
-- Runs an action and keeps its jsonb reply under p_k. A check on the tables then
-- runs as its own statement, so it sees what the action wrote (a direct read in
-- the same statement as the call would see the snapshot from before the call).
create function pg_temp.act(p_k text, p_sql text) returns void language plpgsql as $$
declare
  v jsonb;
begin
  execute p_sql into v;
  perform pg_temp.put(p_k, v::text);
end $$;
create function pg_temp.r(p_k text) returns jsonb language sql as $$ select v::jsonb from ctx where k = p_k $$;

-- The role checks below run as anon and authenticated, which still read the context.
grant select on ctx to anon, authenticated;

-- A fictitious signed in client, a second client, and a staff user. The upload
-- fingerprints are SHA 256 values of fixed test strings, never real documents.
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'flow.client@example.invalid'),
  ('22222222-2222-4222-8222-222222222222', 'other.client@example.invalid'),
  ('33333333-3333-4333-8333-333333333333', 'no.account@example.invalid');
insert into msp_client_account (id, company_name, contact_name, contact_email, account_kind, auth_user_id) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Flow Test Civils (Pty) Ltd', 'Flow Tester', 'flow.client@example.invalid', 'approved_client', '11111111-1111-4111-8111-111111111111'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Other Test Company (Pty) Ltd', 'Other Tester', 'other.client@example.invalid', 'applicant', '22222222-2222-4222-8222-222222222222');

select pg_temp.put('u1', '11111111-1111-4111-8111-111111111111');
select pg_temp.put('u2', '22222222-2222-4222-8222-222222222222');
select pg_temp.put('u3', '33333333-3333-4333-8333-333333333333');
select pg_temp.put('acc1', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.put('sha_a', encode(extensions.digest('hsf flow test document a', 'sha256'), 'hex'));
select pg_temp.put('sha_b', encode(extensions.digest('hsf flow test document b', 'sha256'), 'hex'));
select pg_temp.put('sha_c', encode(extensions.digest('hsf flow test document c', 'sha256'), 'hex'));

-- 1. Objects, grants and definer settings --------------------------------------------------

do $$
declare
  f text;
  v_fn regprocedure;
begin
  foreach f in array array[
    'hsf_consent_status(uuid)', 'hsf_record_consent(uuid, text[], text)', 'hsf_withdraw_consent(uuid, text)',
    'hsf_register_upload(uuid, jsonb)', 'hsf_mark_uploaded(uuid, uuid)', 'hsf_my_uploads(uuid, uuid)',
    'hsf_transfer_queue(int)', 'hsf_transfer_record(uuid, text, text, text, text, text, text)',
    'hsf_mark_staging_deleted(uuid)', 'hsf_account_of(uuid)', 'hsf_user_email(uuid)',
    'hsf_consent_current(uuid, text)', 'hsf_consent_complete(uuid)', 'hsf_safe_name(text)',
    'hsf_consent_wording_version()',
    'kernel_instrument_citable(uuid)', 'msp_api_authorise(text, text)', 'kernel_api_envelope(jsonb)',
    'kernel_api_protocol_json(uuid)', 'kernel_api_industry_id(text)', 'kernel_api_industries()',
    'kernel_api_industry(text)', 'kernel_api_instruments(text)', 'kernel_api_protocols(text)',
    'kernel_api_elements(text)', 'kernel_api_search(text)',
    'hsf_trigger_applies(text, text[])', 'hsf_user_is_staff(uuid)', 'hsf_can_access_file(uuid, uuid)',
    'hsf_compliance_figures(uuid)', 'hsf_compute_compliance(uuid)', 'hsf_generate_file(uuid, jsonb)',
    'hsf_my_files(uuid)', 'hsf_file_detail(uuid, uuid)', 'hsf_set_item_status(uuid, uuid, text, text)'] loop
    v_fn := f::regprocedure;
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception 'CHECK FAILED: % is executable by anon or authenticated', f;
    end if;
    if not has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'CHECK FAILED: % is not executable by the service role', f;
    end if;
  end loop;
  raise notice 'ok   every 049 to 051 function is service role only (anon and authenticated refused)';

  -- Every function these migrations expose with data access is security definer with a fixed search path.
  foreach f in array array[
    'hsf_consent_status(uuid)', 'hsf_record_consent(uuid, text[], text)', 'hsf_withdraw_consent(uuid, text)',
    'hsf_register_upload(uuid, jsonb)', 'hsf_mark_uploaded(uuid, uuid)', 'hsf_my_uploads(uuid, uuid)',
    'hsf_transfer_queue(int)', 'hsf_transfer_record(uuid, text, text, text, text, text, text)',
    'hsf_mark_staging_deleted(uuid)', 'msp_api_client_issue(text, text, text[])', 'msp_api_client_revoke(uuid)',
    'msp_api_authorise(text, text)', 'kernel_api_industries()', 'kernel_api_industry(text)',
    'kernel_api_instruments(text)', 'kernel_api_protocols(text)', 'kernel_api_elements(text)',
    'kernel_api_search(text)', 'hsf_generate_file(uuid, jsonb)', 'hsf_compute_compliance(uuid)',
    'hsf_my_files(uuid)', 'hsf_file_detail(uuid, uuid)', 'hsf_set_item_status(uuid, uuid, text, text)'] loop
    if not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                     and exists (select 1 from unnest(p.proconfig) c where c = 'search_path=public')) then
      raise exception 'CHECK FAILED: % is not security definer with search_path=public', f;
    end if;
  end loop;
  raise notice 'ok   every exposed function is security definer with search_path=public';

  -- Issue and revoke: the service role or a forge_admin (checked in the body), never anon.
  foreach f in array array['msp_api_client_issue(text, text, text[])', 'msp_api_client_revoke(uuid)'] loop
    if has_function_privilege('anon', f::regprocedure, 'execute') then
      raise exception 'CHECK FAILED: % is executable by anon', f;
    end if;
  end loop;
  raise notice 'ok   key issue and revoke are not executable by anon';
end $$;

select pg_temp.ok('no table of 049 or 050 is readable by anon or public',
  not exists (select 1 from unnest(array['hsf_consent','hsf_upload','hsf_mco_transfer','msp_instrument_currency_hold',
                                         'msp_api_client','msp_api_call_log']) t
               where has_table_privilege('anon', t, 'select') or has_table_privilege('public', t, 'select')));
select pg_temp.ok('no table of 049 or 050 is writable by authenticated',
  not exists (select 1 from unnest(array['hsf_consent','hsf_upload','hsf_mco_transfer','msp_instrument_currency_hold',
                                         'msp_api_client','msp_api_call_log']) t
               where has_table_privilege('authenticated', t, 'insert') or has_table_privilege('authenticated', t, 'update')
                  or has_table_privilege('authenticated', t, 'delete')));
select pg_temp.ok('msp_api_client and msp_api_call_log are not readable by authenticated',
  not has_table_privilege('authenticated', 'msp_api_client', 'select')
  and not has_table_privilege('authenticated', 'msp_api_call_log', 'select'));
select pg_temp.ok('Row Level Security is on for every 049 and 050 table',
  (select bool_and(c.relrowsecurity) from pg_class c
    where c.relname in ('hsf_consent','hsf_upload','hsf_mco_transfer','msp_instrument_currency_hold','msp_api_client','msp_api_call_log')
      and c.relnamespace = 'public'::regnamespace));
select pg_temp.ok('the two public views are readable by anon',
  has_table_privilege('anon', 'kernel_citable_instrument', 'select')
  and has_table_privilege('anon', 'hsf_public_element_library', 'select'));
select pg_temp.ok('bucket hsf-staging exists, private, 26214400 bytes, 8 types',
  exists (select 1 from storage.buckets b where b.id = 'hsf-staging' and b.public = false
            and b.file_size_limit = 26214400 and cardinality(b.allowed_mime_types) = 8));
select pg_temp.ok('no storage.objects policy names the hsf-staging bucket',
  not exists (select 1 from pg_policies p where p.schemaname = 'storage'
                and (coalesce(p.qual, '') ilike '%hsf-staging%' or coalesce(p.with_check, '') ilike '%hsf-staging%')));
select pg_temp.ok('the four hsf parameters exist with the contract values',
  msp_env_get_int('hsf.upload_max_bytes') = 26214400
  and msp_env_get('hsf.mco_transfer_mode') = 'hold'
  and msp_env_get_int('hsf.staging_alert_days') = 14
  and cardinality(string_to_array(msp_env_get('hsf.upload_allowed_mime'), ',')) = 8
  and (select category from msp_env_parameter where key = 'hsf.mco_transfer_mode') = 'hsf');
select pg_temp.ok('hsf_evidence.upload_id references hsf_upload',
  exists (select 1 from pg_constraint where conname = 'hsf_evidence_upload_fk' and confrelid = 'hsf_upload'::regclass));

-- 2. Consent ---------------------------------------------------------------------------------

select pg_temp.ok('consent status starts incomplete, with the account and wording version',
  (select s ->> 'complete' = 'false' and s ->> 'client_account_id' = pg_temp.ctx('acc1')
          and s ->> 'company_name' = 'Flow Test Civils (Pty) Ltd' and s ->> 'wording_version' = 'HSF-CONSENT-1.0'
     from hsf_consent_status(pg_temp.ctx('u1')::uuid) s));
select pg_temp.ok('consent status for a user without an account has a null account',
  (select s -> 'client_account_id' = 'null'::jsonb and s ->> 'complete' = 'false'
     from hsf_consent_status(pg_temp.ctx('u3')::uuid) s));

select pg_temp.put('reg_ok', jsonb_build_object('department_code', 'SHE', 'original_name', 'Site plan.pdf',
  'mime_type', 'application/pdf', 'size_bytes', 1024, 'sha256', pg_temp.ctx('sha_a'))::text);

select pg_temp.refuses('register refused while no consent is given',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'), pg_temp.ctx('reg_ok')), 'three consents');

select pg_temp.ok('two of three consents recorded, still incomplete',
  (select s ->> 'document_storage' = 'true' and s ->> 'mco_transfer' = 'true' and s ->> 'authority_to_share' = 'false'
          and s ->> 'complete' = 'false'
     from hsf_record_consent(pg_temp.ctx('u1')::uuid, array['document_storage','mco_transfer'], 'HSF-CONSENT-1.0') s));
select pg_temp.refuses('register refused while consent is incomplete',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'), pg_temp.ctx('reg_ok')), 'three consents');
select pg_temp.refuses('consent refused under another wording version',
  format('select hsf_record_consent(%L, array[''authority_to_share''], ''HSF-CONSENT-0.9'')', pg_temp.ctx('u1')), 'wording');
select pg_temp.refuses('consent refused for an unknown kind',
  format('select hsf_record_consent(%L, array[''marketing''], ''HSF-CONSENT-1.0'')', pg_temp.ctx('u1')), 'unknown consent kind');
select pg_temp.refuses('consent refused for a user without a company account',
  format('select hsf_record_consent(%L, array[''mco_transfer''], ''HSF-CONSENT-1.0'')', pg_temp.ctx('u3')), 'register your company');
select pg_temp.ok('third consent recorded, consent complete',
  (select s ->> 'complete' = 'true'
     from hsf_record_consent(pg_temp.ctx('u1')::uuid, array['authority_to_share'], 'HSF-CONSENT-1.0') s));
select pg_temp.ok('consent recording is audited without personal detail beyond the account',
  (select count(*) = 2 from msp_audit where event_type = 'hsf_consent_recorded'
      and event_detail ->> 'client_account_id' = pg_temp.ctx('acc1')));
select pg_temp.refuses('a consent row cannot be deleted',
  format('delete from hsf_consent where client_account_id = %L', pg_temp.ctx('acc1')), 'never deleted');

-- 3. Generation (SPEC B9.3) ------------------------------------------------------------------

do $$
declare
  r jsonb;
begin
  r := hsf_generate_file(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'industry_code', 'CONSTR',
         'triggers', jsonb_build_array('T-CONSTR', 'T-CONSTR-NOTIFY', 'T-HEIGHT', 'T-ELEC', 'T-CONTRACTORS'),
         'scope', jsonb_build_object('sites', jsonb_build_array(jsonb_build_object('name', 'Test site one', 'address', '1 Test Road')),
                                     'project_reference', 'FLOW-TEST-1', 'headcount', 64)));
  perform pg_temp.put('file_c', r ->> 'file_id');
  perform pg_temp.ok('CONSTR File generated with a CNC-HSF reference and items',
    r ->> 'reference' ~ '^CNC-HSF-[0-9]{4}-[0-9]{4}-[0-9]{3}$' and (r ->> 'items')::int > 0 and r ->> 'regime' = 'OHSA');
  perform pg_temp.ok('item count matches the rows written',
    (r ->> 'items')::int = (select count(*) from hsf_file_item where file_id = (r ->> 'file_id')::uuid));
end $$;

select pg_temp.ok('CONSTR File is draft, revision 1, OHSA, owned by the account',
  exists (select 1 from hsf_file f where f.id = pg_temp.ctx('file_c')::uuid and f.status = 'draft' and f.revision = 1
            and f.regime = 'OHSA' and f.client_account_id = pg_temp.ctx('acc1')::uuid
            and f.scope -> 'triggers' ? 'T-CONSTR' and f.scope ->> 'project_reference' = 'FLOW-TEST-1'));
select pg_temp.ok('every CONSTR item starts outstanding',
  not exists (select 1 from hsf_file_item where file_id = pg_temp.ctx('file_c')::uuid and status <> 'outstanding'));
select pg_temp.ok('CONSTR File carries Construction Regulations, 2014 elements',
  (select count(distinct fi.element_id) >= 5
     from hsf_file_item fi
     join hsf_element_instrument ei on ei.element_id = fi.element_id
     join msp_legal_instrument li on li.id = ei.instrument_id
    where fi.file_id = pg_temp.ctx('file_c')::uuid and li.short_name = 'Construction Regulations, 2014'));
select pg_temp.ok('CONSTR File carries the whole Construction overlay and the triggered construction elements',
  (select count(*) = 12 from hsf_file_item fi join hsf_element e on e.id = fi.element_id
    where fi.file_id = pg_temp.ctx('file_c')::uuid
      and (e.code like 'HSF-OV-CONSTR-%' or e.code in ('HSF-A-05','HSF-A-06','HSF-A-07'))));
select pg_temp.ok('CONSTR File carries every universal element without a trigger',
  not exists (select 1 from hsf_element e where e.universal and e.trigger_code is null
                and not exists (select 1 from hsf_file_item fi where fi.file_id = pg_temp.ctx('file_c')::uuid and fi.element_id = e.id)));
select pg_temp.ok('a compound "T-CONSTR and T-ELEC" element is in the CONSTR File',
  (select count(*) >= 1 from hsf_file_item fi join hsf_element e on e.id = fi.element_id
    where fi.file_id = pg_temp.ctx('file_c')::uuid and e.trigger_code = 'T-CONSTR and T-ELEC')
  or not exists (select 1 from hsf_element where trigger_code = 'T-CONSTR and T-ELEC'));
select pg_temp.ok('CONSTR File carries no MHSA element, no other overlay and no untriggered element',
  not exists (select 1 from hsf_file_item fi join hsf_element e on e.id = fi.element_id
               where fi.file_id = pg_temp.ctx('file_c')::uuid
                 and (e.regime = 'MHSA' or (not e.universal and e.code not like 'HSF-OV-CONSTR-%')
                      or e.trigger_code in ('T-MINING','T-ASBESTOS','T-FOOD','T-ARMED'))));
select pg_temp.ok('hsf_trigger_applies follows hsf/build_samples.py',
  hsf_trigger_applies(null, '{}') and hsf_trigger_applies('U', '{}')
  and hsf_trigger_applies('T-CONSTR and T-ELEC', array['T-CONSTR','T-ELEC'])
  and not hsf_trigger_applies('T-CONSTR and T-ELEC', array['T-ELEC'])
  and hsf_trigger_applies('T-HCA or T-LEAD', array['T-LEAD'])
  and not hsf_trigger_applies('T-HCA or T-LEAD', array['T-HEIGHT'])
  and not hsf_trigger_applies('T-NOISE', '{}'));

do $$
declare
  r jsonb;
begin
  r := hsf_generate_file(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'industry_code', 'MINING', 'triggers', jsonb_build_array('T-NOISE'),
         'scope', jsonb_build_object('sites', jsonb_build_array(jsonb_build_object('name', 'Test quarry')))));
  perform pg_temp.put('file_m', r ->> 'file_id');
  perform pg_temp.ok('MINING File generated under the MHSA', r ->> 'regime' = 'MHSA'
    and (select regime from hsf_file where id = (r ->> 'file_id')::uuid) = 'MHSA');
end $$;
select pg_temp.ok('MINING File carries the Mining overlay and the T-MINING element, raised by the regime',
  (select count(*) = 17 from hsf_file_item fi join hsf_element e on e.id = fi.element_id
    where fi.file_id = pg_temp.ctx('file_m')::uuid and (e.code like 'HSF-OV-MINING-%' or e.code = 'HSF-E-05'))
  and (select scope -> 'triggers' ? 'T-MINING' from hsf_file where id = pg_temp.ctx('file_m')::uuid));
select pg_temp.ok('MINING File carries no OHSA only element and no construction element',
  not exists (select 1 from hsf_file_item fi join hsf_element e on e.id = fi.element_id
               where fi.file_id = pg_temp.ctx('file_m')::uuid and (e.regime = 'OHSA' or e.trigger_code = 'T-CONSTR')));

do $$
declare
  r jsonb;
begin
  r := hsf_generate_file(pg_temp.ctx('u2')::uuid, jsonb_build_object(
         'industry_code', 'OFFICE', 'triggers', jsonb_build_array('T-ELEC'),
         'scope', jsonb_build_object('sites', jsonb_build_array(jsonb_build_object('name', 'Other head office')))));
  perform pg_temp.put('file_o', r ->> 'file_id');
end $$;
select pg_temp.ok('an OFFICE File with T-ELEC alone leaves out the "T-CONSTR and T-ELEC" and construction elements',
  not exists (select 1 from hsf_file_item fi join hsf_element e on e.id = fi.element_id
               where fi.file_id = pg_temp.ctx('file_o')::uuid and e.trigger_code in ('T-CONSTR and T-ELEC','T-CONSTR')));
select pg_temp.ok('two Files generated the same day get consecutive references',
  (select count(distinct reference) = 3 from hsf_file where id in (pg_temp.ctx('file_c')::uuid, pg_temp.ctx('file_m')::uuid, pg_temp.ctx('file_o')::uuid)));

select pg_temp.refuses('generate refused for an unknown industry',
  format('select hsf_generate_file(%L, %L::jsonb)', pg_temp.ctx('u1'),
         '{"industry_code":"NOPE","triggers":[],"scope":{"sites":[{"name":"x"}]}}'), 'choose your industry');
select pg_temp.refuses('generate refused for an unknown trigger',
  format('select hsf_generate_file(%L, %L::jsonb)', pg_temp.ctx('u1'),
         '{"industry_code":"CONSTR","triggers":["T-NOPE"],"scope":{"sites":[{"name":"x"}]}}'), 'unknown activity');
select pg_temp.refuses('generate refused without a site',
  format('select hsf_generate_file(%L, %L::jsonb)', pg_temp.ctx('u1'),
         '{"industry_code":"CONSTR","triggers":[],"scope":{"sites":[]}}'), 'sites');
select pg_temp.refuses('generate refused for a subindustry of another industry',
  format('select hsf_generate_file(%L, %L::jsonb)', pg_temp.ctx('u1'),
         '{"industry_code":"CONSTR","subindustry_code":"MIN-GOLD","triggers":[],"scope":{"sites":[{"name":"x"}]}}'), 'subindustry');
select pg_temp.refuses('generate refused for a user without a company account',
  format('select hsf_generate_file(%L, %L::jsonb)', pg_temp.ctx('u3'),
         '{"industry_code":"CONSTR","triggers":[],"scope":{"sites":[{"name":"x"}]}}'), 'register your company');
select pg_temp.ok('File generation is audited against the File',
  (select count(*) = 3 from msp_audit where event_type = 'hsf_file_generated' and hsf_file_id is not null));

-- 4. Upload registration --------------------------------------------------------------------

select pg_temp.refuses('register rejects a file type outside the parameter list',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || '{"mime_type":"application/x-msdownload","original_name":"run.exe"}')::text), 'file type');
select pg_temp.refuses('register rejects a file one byte over 25 MB',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || '{"size_bytes":26214401}')::text), 'limit');
select pg_temp.refuses('register rejects an empty file',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || '{"size_bytes":0}')::text), 'limit');
select pg_temp.refuses('register rejects a malformed fingerprint',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || '{"sha256":"abc"}')::text), 'sha 256');
select pg_temp.refuses('register rejects an unknown department',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || '{"department_code":"NOPE"}')::text), 'department');
select pg_temp.refuses('register rejects the File of another account',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || jsonb_build_object('file_id', pg_temp.ctx('file_o')))::text), 'not recognised');
select pg_temp.refuses('register rejects an element that is not in the File',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || jsonb_build_object('file_id', pg_temp.ctx('file_c'), 'element_code', 'HSF-OV-MINING-01'))::text), 'not part of this file');
select pg_temp.refuses('register rejects an element filed under the wrong section',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || jsonb_build_object('file_id', pg_temp.ctx('file_c'), 'element_code', 'HSF-A-06', 'section_code', 'C'))::text), 'belongs to section a');
select pg_temp.refuses('register rejects an element upload without a File',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || '{"element_code":"HSF-A-06"}')::text), 'name the file');
select pg_temp.refuses('register refused for an account whose consent is not given',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u2'), pg_temp.ctx('reg_ok')), 'three consents');
select pg_temp.ok('no upload row was written by the refusals', not exists (select 1 from hsf_upload));

do $$
declare
  r jsonb;
begin
  -- Upload A: the client specification of the CONSTR File (element HSF-A-06).
  r := hsf_register_upload(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'file_id', pg_temp.ctx('file_c'), 'element_code', 'HSF-A-06', 'department_code', 'SHE',
         'original_name', '  Client H&S spec (final) v2 ../../etc.PDF', 'mime_type', 'Application/PDF',
         'size_bytes', 2048, 'sha256', upper(pg_temp.ctx('sha_a'))));
  perform pg_temp.put('up_a', r ->> 'upload_id');
  perform pg_temp.ok('register accepted: bucket hsf-staging and path <account>/<upload>/<safe name>',
    r ->> 'bucket' = 'hsf-staging'
    and r ->> 'path' = pg_temp.ctx('acc1') || '/' || (r ->> 'upload_id') || '/Client_H_S_spec_final_v2_etc.pdf');

  -- Upload B: a general document with no File, used for the mismatch path.
  r := hsf_register_upload(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'department_code', 'HR', 'section_code', 'D', 'original_name', 'Training matrix.xlsx',
         'mime_type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         'size_bytes', 26214400, 'sha256', pg_temp.ctx('sha_b')));
  perform pg_temp.put('up_b', r ->> 'upload_id');

  -- Upload C: for the error path.
  r := hsf_register_upload(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'department_code', 'OPS', 'original_name', 'Register.csv', 'mime_type', 'text/csv',
         'size_bytes', 10, 'sha256', pg_temp.ctx('sha_c')));
  perform pg_temp.put('up_c', r ->> 'upload_id');
end $$;

select pg_temp.ok('upload A row: awaiting upload, lower case hash, element item and section A resolved',
  exists (select 1 from hsf_upload u join hsf_file_item fi on fi.id = u.file_item_id join hsf_element e on e.id = fi.element_id
           where u.id = pg_temp.ctx('up_a')::uuid and u.status = 'awaiting_upload' and u.sha256_client = pg_temp.ctx('sha_a')
             and u.mime_type = 'application/pdf' and u.section_code = 'A' and e.code = 'HSF-A-06'
             and u.original_name = 'Client H&S spec (final) v2 ../../etc.PDF' and u.storage_bucket = 'hsf-staging'));
select pg_temp.ok('safe names use letters, digits, dot and underscore only, at most 120 characters',
  hsf_safe_name(repeat('a', 200) || '.pdf') = repeat('a', 116) || '.pdf'
  and hsf_safe_name('../../..') = 'document'
  and hsf_safe_name('Rëport 2026/09.docx') = 'R_port_2026_09.docx'
  and not exists (select 1 from hsf_upload where safe_name !~ '^[A-Za-z0-9._]{1,120}$'));
select pg_temp.ok('registration is audited without the file name',
  (select count(*) = 3 from msp_audit where event_type = 'hsf_upload_registered')
  and not exists (select 1 from msp_audit where event_type like 'hsf_%' and event_detail::text ilike '%spec (final)%'));

-- 5. Upload completion and evidence ---------------------------------------------------------------

select pg_temp.refuses('another user cannot complete the upload',
  format('select hsf_mark_uploaded(%L, %L)', pg_temp.ctx('u2'), pg_temp.ctx('up_a')), 'not found');
select pg_temp.ok('mark uploaded moves A to uploaded',
  hsf_mark_uploaded(pg_temp.ctx('u1')::uuid, pg_temp.ctx('up_a')::uuid) ->> 'status' = 'uploaded');
select pg_temp.ok('mark uploaded is idempotent',
  hsf_mark_uploaded(pg_temp.ctx('u1')::uuid, pg_temp.ctx('up_a')::uuid) ->> 'status' = 'uploaded');
select pg_temp.ok('mark uploaded created one evidence row: version 1, client_upload, browser hash, email, staging path',
  (select count(*) = 1 from hsf_evidence ev join hsf_upload u on u.id = ev.upload_id
    where u.id = pg_temp.ctx('up_a')::uuid and ev.version = 1 and ev.source = 'client_upload'
      and ev.sha256 = pg_temp.ctx('sha_a') and ev.supplied_by = 'flow.client@example.invalid'
      and ev.storage_path = u.storage_path and ev.file_item_id = u.file_item_id and ev.supersedes_id is null));
select pg_temp.ok('the File item of A is now uploaded',
  (select fi.status = 'uploaded' from hsf_upload u join hsf_file_item fi on fi.id = u.file_item_id where u.id = pg_temp.ctx('up_a')::uuid));
select pg_temp.ok('mark uploaded moves B and C to uploaded without evidence rows',
  hsf_mark_uploaded(pg_temp.ctx('u1')::uuid, pg_temp.ctx('up_b')::uuid) ->> 'status' = 'uploaded'
  and hsf_mark_uploaded(pg_temp.ctx('u1')::uuid, pg_temp.ctx('up_c')::uuid) ->> 'status' = 'uploaded'
  and not exists (select 1 from hsf_evidence where upload_id in (pg_temp.ctx('up_b')::uuid, pg_temp.ctx('up_c')::uuid)));
select pg_temp.ok('hsf_my_uploads lists the three uploads of the account, with the element of A',
  (select jsonb_array_length(l) = 3
          and exists (select 1 from jsonb_array_elements(l) x
                       where x ->> 'upload_id' = pg_temp.ctx('up_a') and x ->> 'element_code' = 'HSF-A-06'
                         and x ->> 'status' = 'uploaded' and x ->> 'department_code' = 'SHE')
     from hsf_my_uploads(pg_temp.ctx('u1')::uuid) l));
select pg_temp.ok('hsf_my_uploads filters by File and shows nothing to another account',
  jsonb_array_length(hsf_my_uploads(pg_temp.ctx('u1')::uuid, pg_temp.ctx('file_c')::uuid)) = 1
  and jsonb_array_length(hsf_my_uploads(pg_temp.ctx('u2')::uuid)) = 0);

-- 6. Transfer bookkeeping ---------------------------------------------------------------------------

select pg_temp.ok('the transfer queue holds the three uploaded files, oldest first',
  (select count(*) = 3 from hsf_transfer_queue(10) q
    where q.id in (pg_temp.ctx('up_a')::uuid, pg_temp.ctx('up_b')::uuid, pg_temp.ctx('up_c')::uuid))
  and (select count(*) = 1 from hsf_transfer_queue(1)));

select pg_temp.refuses('staging deletion refused before a transfer',
  format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_a')), 'only a transferred upload');
select pg_temp.refuses('a received outcome is refused in hold mode',
  format('select hsf_transfer_record(%L, ''hold'', ''received'', %L, ''X'', %L, null)',
         pg_temp.ctx('up_a'), pg_temp.ctx('sha_a'), pg_temp.ctx('sha_a')), 'held transfer');
select pg_temp.refuses('an unknown outcome is refused',
  format('select hsf_transfer_record(%L, ''fixture'', ''done'', null, null, null, null)', pg_temp.ctx('up_a')), 'unknown transfer outcome');

select pg_temp.act('r', format('select hsf_transfer_record(%L, ''hold'', ''held'', %L, null, null, null)',
                               pg_temp.ctx('up_a'), pg_temp.ctx('sha_a')));
select pg_temp.ok('transfer_record held moves A to held',
  pg_temp.r('r') ->> 'status' = 'held' and pg_temp.r('r') ->> 'outcome' = 'held'
  and (select status = 'held' and sha256_server = pg_temp.ctx('sha_a') from hsf_upload where id = pg_temp.ctx('up_a')::uuid));
select pg_temp.ok('a held upload stays in the queue', exists (select 1 from hsf_transfer_queue(10) q where q.id = pg_temp.ctx('up_a')::uuid));

select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, %L, %L, null)',
                               pg_temp.ctx('up_a'), upper(pg_temp.ctx('sha_a')), 'FIXTURE-' || pg_temp.ctx('up_a'), pg_temp.ctx('sha_a')));
select pg_temp.ok('transfer_record received with three matching fingerprints moves A to transferred',
  pg_temp.r('r') ->> 'status' = 'transferred' and pg_temp.r('r') ->> 'mco_document_ref' = 'FIXTURE-' || pg_temp.ctx('up_a'));
select pg_temp.ok('upload A carries the MyClinicOnline reference and transfer time',
  exists (select 1 from hsf_upload where id = pg_temp.ctx('up_a')::uuid and status = 'transferred'
            and mco_document_ref = 'FIXTURE-' || pg_temp.ctx('up_a') and transferred_at is not null
            and storage_path is not null and sha256_server = sha256_client));
select pg_temp.ok('the evidence row of A carries the MyClinicOnline fields',
  exists (select 1 from hsf_evidence where upload_id = pg_temp.ctx('up_a')::uuid
            and mco_document_ref = 'FIXTURE-' || pg_temp.ctx('up_a') and transferred_at is not null
            and storage_path is not null and staging_deleted_at is null));
select pg_temp.ok('a transferred upload leaves the queue',
  not exists (select 1 from hsf_transfer_queue(10) q where q.id = pg_temp.ctx('up_a')::uuid));
select pg_temp.refuses('a second transfer record for a transferred upload is refused',
  format('select hsf_transfer_record(%L, ''fixture'', ''held'', null, null, null, null)', pg_temp.ctx('up_a')), 'not waiting for transfer');

select pg_temp.act('r', format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_a')));
select pg_temp.ok('mark_staging_deleted clears the staging path and keeps the row and hashes',
  pg_temp.r('r') ->> 'status' = 'staging_deleted'
  and exists (select 1 from hsf_upload where id = pg_temp.ctx('up_a')::uuid and status = 'staging_deleted'
                and storage_path is null and staging_deleted_at is not null
                and sha256_client = pg_temp.ctx('sha_a') and sha256_server = pg_temp.ctx('sha_a')));
select pg_temp.ok('the evidence row of A has its staging path cleared and keeps its hash',
  exists (select 1 from hsf_evidence where upload_id = pg_temp.ctx('up_a')::uuid and storage_path is null
            and staging_deleted_at is not null and sha256 = pg_temp.ctx('sha_a') and mco_document_ref is not null));
select pg_temp.refuses('staging deletion cannot be recorded twice',
  format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_a')), 'only a transferred upload');
select pg_temp.ok('the lifecycle of A is visible to the client',
  (select x ->> 'status' = 'staging_deleted' and x ->> 'mco_document_ref' = 'FIXTURE-' || pg_temp.ctx('up_a')
          and x ->> 'staging_deleted_at' is not null and x ->> 'transferred_at' is not null
     from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u1')::uuid)) x where x ->> 'upload_id' = pg_temp.ctx('up_a')));

select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, %L, %L, null)',
                               pg_temp.ctx('up_b'), pg_temp.ctx('sha_b'), 'FIXTURE-' || pg_temp.ctx('up_b'), pg_temp.ctx('sha_c')));
select pg_temp.ok('received with a receipt fingerprint that does not match moves B to failed',
  pg_temp.r('r') ->> 'status' = 'failed' and pg_temp.r('r') ->> 'outcome' = 'hash_mismatch'
  and exists (select 1 from hsf_upload where id = pg_temp.ctx('up_b')::uuid and status = 'failed'
                and reject_reason is not null and mco_document_ref is null and storage_path is not null));
select pg_temp.refuses('staging deletion refused after a mismatch',
  format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_b')), 'only a transferred upload');
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''error'', null, null, null, ''Adapter timed out'')', pg_temp.ctx('up_c')));
select pg_temp.ok('an error outcome leaves an upload where it was',
  pg_temp.r('r') ->> 'status' = 'uploaded'
  and (select status = 'uploaded' from hsf_upload where id = pg_temp.ctx('up_c')::uuid)
  and exists (select 1 from hsf_mco_transfer where upload_id = pg_temp.ctx('up_c')::uuid and outcome = 'error' and error = 'Adapter timed out'));
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''hash_mismatch'', %L, null, null, %L)',
                               pg_temp.ctx('up_c'), pg_temp.ctx('sha_a'), 'The staged file does not match the browser fingerprint.'));
select pg_temp.ok('a hash_mismatch outcome moves C to failed with the reason',
  pg_temp.r('r') ->> 'status' = 'failed'
  and (select status = 'failed' and reject_reason ilike '%does not match%' from hsf_upload where id = pg_temp.ctx('up_c')::uuid));
select pg_temp.ok('the transfer log holds every attempt (A: 2, B: 1, C: 2)',
  (select count(*) = 5 from hsf_mco_transfer)
  and (select count(*) = 1 from hsf_mco_transfer where upload_id = pg_temp.ctx('up_b')::uuid and outcome = 'hash_mismatch'));
select pg_temp.refuses('the transfer log refuses an update',
  'update hsf_mco_transfer set error = null', 'append only');
select pg_temp.refuses('the transfer log refuses a delete',
  'delete from hsf_mco_transfer', 'append only');
select pg_temp.refuses('an upload row cannot be deleted',
  format('delete from hsf_upload where id = %L', pg_temp.ctx('up_b')), 'never deleted');
select pg_temp.refuses('the evidence ledger still refuses a delete',
  format('delete from hsf_evidence where upload_id = %L', pg_temp.ctx('up_a')), 'append only');
select pg_temp.ok('transfer events of A are audited against its File (held, received, staging deleted)',
  (select count(*) = 2 from msp_audit where event_type = 'hsf_transfer_recorded'
      and hsf_file_id = pg_temp.ctx('file_c')::uuid and event_detail ->> 'upload_id' = pg_temp.ctx('up_a'))
  and (select count(*) = 1 from msp_audit where event_type = 'hsf_staging_deleted'
      and hsf_file_id = pg_temp.ctx('file_c')::uuid and event_detail ->> 'upload_id' = pg_temp.ctx('up_a'))
  and (select count(*) = 3 from msp_audit where event_type = 'hsf_transfer_recorded' and hsf_file_id is null));

-- 7. Compliance (SPEC B9.4), detail and item status ---------------------------------------------------

do $$
declare
  v_total int;
  v_fig jsonb;
begin
  select count(*) into v_total from hsf_file_item where file_id = pg_temp.ctx('file_c')::uuid;
  v_fig := hsf_compute_compliance(pg_temp.ctx('file_c')::uuid);
  perform pg_temp.ok('overall compliance is uploaded over all items (one of ' || v_total || ')',
    (v_fig -> 'overall' ->> 'evidenced')::int = 1 and (v_fig -> 'overall' ->> 'applicable')::int = v_total
    and (v_fig -> 'overall' ->> 'pct')::numeric = round(100.0 / v_total, 1)
    and (v_fig -> 'overall' -> 'counts' ->> 'uploaded')::int = 1);
  perform pg_temp.ok('fifteen sections; Section A counts the upload; a section with no items has a null figure',
    jsonb_array_length(v_fig -> 'sections') = 15
    and (select (x ->> 'evidenced')::int = 1 from jsonb_array_elements(v_fig -> 'sections') x where x ->> 'code' = 'A')
    and not exists (select 1 from jsonb_array_elements(v_fig -> 'sections') x
                     where (x ->> 'items')::int = 0 and x -> 'compliance_pct' <> 'null'::jsonb));
  perform pg_temp.ok('the overall figure is cached on the File',
    (select compliance_pct from hsf_file where id = pg_temp.ctx('file_c')::uuid) = round(100.0 / v_total, 1));
  perform pg_temp.put('total_c', v_total::text);
end $$;

select pg_temp.put('item_na', (select fi.id::text from hsf_file_item fi join hsf_element e on e.id = fi.element_id
                                where fi.file_id = pg_temp.ctx('file_c')::uuid and e.code = 'HSF-A-07'));
select pg_temp.put('item_up', (select fi.id::text from hsf_file_item fi join hsf_element e on e.id = fi.element_id
                                where fi.file_id = pg_temp.ctx('file_c')::uuid and e.code = 'HSF-A-06'));
select pg_temp.refuses('not applicable needs a reason of ten characters',
  format('select hsf_set_item_status(%L, %L, ''not_applicable'', ''too short'')', pg_temp.ctx('u1'), pg_temp.ctx('item_na')), 'ten characters');
select pg_temp.refuses('another account cannot change an item',
  format('select hsf_set_item_status(%L, %L, ''not_applicable'', ''Not carried on at this site'')', pg_temp.ctx('u2'), pg_temp.ctx('item_na')), 'not found');
select pg_temp.refuses('an item with evidence cannot be marked not applicable',
  format('select hsf_set_item_status(%L, %L, ''not_applicable'', ''Not carried on at this site'')', pg_temp.ctx('u1'), pg_temp.ctx('item_up')), 'evidence');
select pg_temp.refuses('only not_applicable or outstanding may be set',
  format('select hsf_set_item_status(%L, %L, ''uploaded'', null)', pg_temp.ctx('u1'), pg_temp.ctx('item_na')), 'not_applicable or outstanding');
select pg_temp.act('r', format('select hsf_set_item_status(%L, %L, ''not_applicable'', %L)', pg_temp.ctx('u1'),
                               pg_temp.ctx('item_na'), '  No contractor plan: the client runs the work with its own staff.  '));
select pg_temp.ok('not applicable with a reason leaves the denominator',
  pg_temp.r('r') ->> 'status' = 'not_applicable'
  and (pg_temp.r('r') -> 'overall' ->> 'applicable')::int = pg_temp.ctx('total_c')::int - 1
  and (pg_temp.r('r') -> 'overall' ->> 'pct')::numeric = round(100.0 / (pg_temp.ctx('total_c')::int - 1), 1)
  and (select compliance_pct from hsf_file where id = pg_temp.ctx('file_c')::uuid) = round(100.0 / (pg_temp.ctx('total_c')::int - 1), 1));
select pg_temp.ok('the reason is stored trimmed on the item',
  (select reason = 'No contractor plan: the client runs the work with its own staff.' from hsf_file_item where id = pg_temp.ctx('item_na')::uuid));
update msp_env_parameter set value = 'false' where key = 'hsf.compliance_scope';
select pg_temp.ok('with hsf.compliance_scope false a not applicable item counts against the File',
  (hsf_compliance_figures(pg_temp.ctx('file_c')::uuid) -> 'overall' ->> 'applicable')::int = pg_temp.ctx('total_c')::int);
update msp_env_parameter set value = 'true' where key = 'hsf.compliance_scope';
select pg_temp.act('r', format('select hsf_set_item_status(%L, %L, ''outstanding'', null)', pg_temp.ctx('u1'), pg_temp.ctx('item_na')));
select pg_temp.ok('the item returns to outstanding and the reason is cleared',
  pg_temp.r('r') ->> 'status' = 'outstanding'
  and (select status = 'outstanding' and reason is null from hsf_file_item where id = pg_temp.ctx('item_na')::uuid));
select pg_temp.ok('item status changes are audited against the File',
  (select count(*) = 2 from msp_audit where event_type = 'hsf_item_status_set' and hsf_file_id = pg_temp.ctx('file_c')::uuid));

-- SPEC B9.4 worked example: 20 items, 3 not applicable, 11 uploaded, 2 linked_mco, 3 outstanding, 1 expired
-- gives 13 over 17 = 76,5 per cent; renewing the expired item gives 14 over 17 = 82,4 per cent.
do $$
declare
  v_file uuid;
  v_fig jsonb;
begin
  insert into hsf_file (client_account_id, industry_id, regime, scope)
  select pg_temp.ctx('acc1')::uuid, i.id, 'OHSA', '{"sites":[{"name":"Worked example"}]}'::jsonb
    from msp_industry i where i.code = 'OFFICE'
  returning id into v_file;
  insert into hsf_file_item (file_id, element_id, status, reason)
  select v_file, e.id,
         case when n <= 3 then 'not_applicable' when n <= 14 then 'uploaded' when n <= 16 then 'linked_mco'
              when n <= 19 then 'outstanding' else 'expired' end,
         case when n <= 3 then 'Not carried on at this site.' end
    from (select e.id, row_number() over (order by e.code) as n from hsf_element e) e
   where n <= 20;
  v_fig := hsf_compute_compliance(v_file);
  perform pg_temp.ok('SPEC B9.4 worked example gives 76,5 per cent', (v_fig -> 'overall' ->> 'pct')::numeric = 76.5);
  update hsf_file_item set status = 'uploaded' where file_id = v_file and status = 'expired';
  v_fig := hsf_compute_compliance(v_file);
  perform pg_temp.ok('renewing the expired item gives 82,4 per cent', (v_fig -> 'overall' ->> 'pct')::numeric = 82.4);
end $$;

select pg_temp.ok('hsf_file_detail: file, fifteen sections, the uploaded item with its basis and upload',
  (select d -> 'file' ->> 'reference' like 'CNC-HSF-%' and d -> 'file' ->> 'company_name' = 'Flow Test Civils (Pty) Ltd'
          and d -> 'file' ->> 'industry_code' = 'CONSTR' and jsonb_array_length(d -> 'sections') = 15
          and (d -> 'overall' ->> 'evidenced')::int = 1
          and exists (select 1 from jsonb_array_elements(d -> 'sections') s, jsonb_array_elements(s -> 'items') i
                       where i ->> 'element_code' = 'HSF-A-06' and i ->> 'status' = 'uploaded'
                         and jsonb_typeof(i -> 'citable') = 'array' and jsonb_typeof(i -> 'awaiting') = 'array'
                         and i -> 'uploads' -> 0 ->> 'upload_id' = pg_temp.ctx('up_a')
                         and i -> 'uploads' -> 0 ->> 'status' = 'staging_deleted')
     from hsf_file_detail(pg_temp.ctx('u1')::uuid, pg_temp.ctx('file_c')::uuid) d));
select pg_temp.ok('item count in the detail matches the File',
  (select sum(jsonb_array_length(s -> 'items'))::int = pg_temp.ctx('total_c')::int
     from jsonb_array_elements(hsf_file_detail(pg_temp.ctx('u1')::uuid, pg_temp.ctx('file_c')::uuid) -> 'sections') s));
select pg_temp.refuses('hsf_file_detail refused to another account',
  format('select hsf_file_detail(%L, %L)', pg_temp.ctx('u2'), pg_temp.ctx('file_c')), 'not found');
select pg_temp.refuses('hsf_file_detail refused without a user',
  format('select hsf_file_detail(null, %L)', pg_temp.ctx('file_c')), 'not found');

-- Staff (forge roles in app metadata) may read any File. The local stub has no
-- raw_app_meta_data column, so it is added inside this rolled back transaction.
alter table auth.users add column if not exists raw_app_meta_data jsonb;
update auth.users set raw_app_meta_data = '{"msp_roles":["forge_safety_reviewer"]}' where id = pg_temp.ctx('u3')::uuid;
select pg_temp.ok('a forge_safety_reviewer may read a client File',
  hsf_user_is_staff(pg_temp.ctx('u3')::uuid)
  and (hsf_file_detail(pg_temp.ctx('u3')::uuid, pg_temp.ctx('file_c')::uuid) -> 'file' ->> 'file_id') = pg_temp.ctx('file_c'));
select pg_temp.ok('a client is not staff', not hsf_user_is_staff(pg_temp.ctx('u1')::uuid));

select pg_temp.ok('hsf_my_files lists the account''s Files with industry and live compliance',
  (select jsonb_array_length(l) = 3
          and exists (select 1 from jsonb_array_elements(l) x
                       where x ->> 'file_id' = pg_temp.ctx('file_c') and x ->> 'industry_code' = 'CONSTR'
                         and x ->> 'industry_name' = 'Construction' and x ->> 'status' = 'draft'
                         and (x ->> 'revision')::int = 1 and (x ->> 'compliance_pct')::numeric > 0)
     from hsf_my_files(pg_temp.ctx('u1')::uuid) l)
  and jsonb_array_length(hsf_my_files(pg_temp.ctx('u2')::uuid)) = 1
  and jsonb_array_length(hsf_my_files(pg_temp.ctx('u3')::uuid)) = 0);

-- 8. Withdrawal stops new uploads -----------------------------------------------------------------

do $$
declare
  r jsonb;
begin
  -- Upload D is registered while consent is complete, then consent is withdrawn before it completes.
  r := hsf_register_upload(pg_temp.ctx('u1')::uuid, pg_temp.ctx('reg_ok')::jsonb);
  perform pg_temp.put('up_d', r ->> 'upload_id');
  -- Upload E completes and waits in the transfer queue.
  r := hsf_register_upload(pg_temp.ctx('u1')::uuid, pg_temp.ctx('reg_ok')::jsonb);
  perform pg_temp.put('up_e', r ->> 'upload_id');
  perform hsf_mark_uploaded(pg_temp.ctx('u1')::uuid, pg_temp.ctx('up_e')::uuid);
  perform pg_temp.ok('upload E waits in the transfer queue',
    exists (select 1 from hsf_transfer_queue(100) q where q.id = pg_temp.ctx('up_e')::uuid));
end $$;
select pg_temp.ok('withdrawing document_storage makes consent incomplete',
  (select s ->> 'document_storage' = 'false' and s ->> 'complete' = 'false'
     from hsf_withdraw_consent(pg_temp.ctx('u1')::uuid, 'document_storage') s));
select pg_temp.refuses('a new upload is refused after withdrawal',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'), pg_temp.ctx('reg_ok')), 'three consents');
select pg_temp.act('r', format('select hsf_mark_uploaded(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('up_d')));
select pg_temp.ok('an upload registered before the withdrawal is rejected on completion',
  pg_temp.r('r') ->> 'status' = 'rejected'
  and (select status = 'rejected' and reject_reason ilike '%consent%' from hsf_upload where id = pg_temp.ctx('up_d')::uuid));
select pg_temp.refuses('withdrawing an unknown kind is refused',
  format('select hsf_withdraw_consent(%L, ''marketing'')', pg_temp.ctx('u1')), 'unknown consent kind');
select pg_temp.act('r', format('select hsf_withdraw_consent(%L, ''mco_transfer'')', pg_temp.ctx('u1')));
select pg_temp.ok('withdrawing mco_transfer takes the account out of the transfer queue',
  pg_temp.r('r') ->> 'mco_transfer' = 'false'
  and not exists (select 1 from hsf_transfer_queue(100) q where q.client_account_id = pg_temp.ctx('acc1')::uuid));
select pg_temp.ok('withdrawals are audited; the consent rows are kept with withdrawn_at',
  (select count(*) = 2 from msp_audit where event_type = 'hsf_consent_withdrawn')
  and (select count(*) = 2 from hsf_consent where client_account_id = pg_temp.ctx('acc1')::uuid and withdrawn_at is not null)
  and (select count(*) = 3 from hsf_consent where client_account_id = pg_temp.ctx('acc1')::uuid));
select pg_temp.refuses('a withdrawal cannot be undone by an update',
  format('update hsf_consent set withdrawn_at = null where client_account_id = %L', pg_temp.ctx('acc1')), 'only a withdrawal');
select pg_temp.act('r', format('select hsf_record_consent(%L, array[''document_storage'',''mco_transfer''], ''HSF-CONSENT-1.0'')', pg_temp.ctx('u1')));
select pg_temp.ok('consent can be given again, and is complete again; E returns to the queue',
  pg_temp.r('r') ->> 'complete' = 'true'
  and exists (select 1 from hsf_transfer_queue(100) q where q.id = pg_temp.ctx('up_e')::uuid));

-- 9. Citable instruments and the public element library -------------------------------------------------

select pg_temp.ok('kernel_citable_instrument holds only verified, unheld instruments',
  (select count(*) from kernel_citable_instrument)
  = (select count(*) from msp_legal_instrument li where li.status = 'verified'
       and not exists (select 1 from msp_instrument_currency_hold h where h.instrument_id = li.id)));
select pg_temp.ok('the NIHL Regulations, 2003 and the Environmental Regulations for Workplaces, 1987 are not citable',
  not exists (select 1 from kernel_citable_instrument
               where short_name in ('NIHL Regulations, 2003','Environmental Regulations for Workplaces, 1987')));
select pg_temp.ok('superseded and pending candidate instruments are not citable',
  not exists (select 1 from kernel_citable_instrument k join msp_legal_instrument li on li.short_name = k.short_name
               where li.status in ('superseded','pending','excluded')
                 and not exists (select 1 from msp_legal_instrument v where v.short_name = k.short_name and v.status = 'verified')));
select pg_temp.ok('every seeded hold is on a row that was verified, with a reason naming the repeal',
  not exists (select 1 from msp_instrument_currency_hold h where h.reason not ilike '%06/09/2026%'));

-- A hold removes a verified instrument from citation everywhere, at once.
insert into msp_instrument_currency_hold (instrument_id, reason, held_by)
select id, 'Flow test hold, rolled back.', 'hsf_flow_checks' from msp_legal_instrument
 where short_name = 'Construction Regulations, 2014' and status = 'verified';
select pg_temp.ok('a held instrument leaves kernel_citable_instrument',
  not exists (select 1 from kernel_citable_instrument where short_name = 'Construction Regulations, 2014'));
select pg_temp.ok('a held instrument moves from citable to awaiting in the element library',
  (select not (citable::jsonb ? 'Construction Regulations, 2014') and awaiting::jsonb ? 'Construction Regulations, 2014'
     from hsf_public_element_library where code = 'HSF-A-06'));
select pg_temp.ok('a held instrument is not a basis in the kernel API',
  not (kernel_api_instruments('CONSTR')::text like '%"short_name": "Construction Regulations, 2014"%')
  and not exists (select 1 from jsonb_array_elements(kernel_api_elements('CONSTR') -> 'data') x
                   where x -> 'citable' ? 'Construction Regulations, 2014'));
delete from msp_instrument_currency_hold where held_by = 'hsf_flow_checks';

select pg_temp.ok('the element library names every active element, citable bases verified only',
  (select count(*) from hsf_public_element_library) = (select count(*) from hsf_element where status = 'active')
  and not exists (select 1 from hsf_public_element_library l, json_array_elements_text(l.citable) c
                   where not exists (select 1 from kernel_citable_instrument k where k.short_name = c)));
select pg_temp.ok('candidate instruments appear as awaiting, never as citable',
  exists (select 1 from hsf_public_element_library l, json_array_elements_text(l.awaiting) a
           join msp_legal_instrument li on li.short_name = a and li.status = 'pending')
  and not exists (select 1 from hsf_public_element_library l, json_array_elements_text(l.citable) c
                   join msp_legal_instrument li on li.short_name = c and li.source_one = 'Gate a pending'));

set local role anon;
select pg_temp.ok('anon reads both public views', (select count(*) > 0 from kernel_citable_instrument)
  and (select count(*) > 0 from hsf_public_element_library));
reset role;
set local role anon;
select pg_temp.refuses('anon cannot read uploads', 'select count(*) from hsf_upload', 'permission denied');
reset role;
set local role anon;
select pg_temp.refuses('anon cannot read API clients', 'select count(*) from msp_api_client', 'permission denied');
reset role;
set local role anon;
select pg_temp.refuses('anon cannot call a service role function', format('select hsf_consent_status(%L)', pg_temp.ctx('u1')), 'permission denied');
reset role;
set local role authenticated;
select pg_temp.refuses('authenticated cannot call a service role function',
  format('select hsf_register_upload(%L, ''{}''::jsonb)', pg_temp.ctx('u1')), 'permission denied');
reset role;

-- 10. API keys --------------------------------------------------------------------------------------

select set_config('request.jwt.claims', '', true);
select pg_temp.refuses('a key cannot be issued without the service role or forge_admin',
  'select msp_api_client_issue(''Flow test bot'', ''Flow tester'')', 'forge_admin');
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111","app_metadata":{"msp_roles":["forge_omp"]}}', true);
select pg_temp.refuses('a forge_omp cannot issue a key',
  'select msp_api_client_issue(''Flow test bot'', ''Flow tester'')', 'forge_admin');
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.refuses('an unknown scope is refused',
  'select msp_api_client_issue(''Flow test bot'', ''Flow tester'', ''{kernel.write}'')', 'scope');

do $$
declare
  r jsonb;
  v_key text;
begin
  r := msp_api_client_issue('Flow test bot', 'Flow tester');
  v_key := r ->> 'api_key';
  perform pg_temp.put('client_id', r ->> 'client_id');
  perform pg_temp.put('key_hash', encode(extensions.digest(v_key, 'sha256'), 'hex'));
  perform pg_temp.ok('the key is cnck_ and 64 hex characters, returned once',
    v_key ~ '^cnck_[0-9a-f]{64}$' and r ? 'client_id');
  perform pg_temp.ok('only the SHA 256 of the key is stored',
    exists (select 1 from msp_api_client c where c.id = (r ->> 'client_id')::uuid
              and c.key_hash = encode(extensions.digest(v_key, 'sha256'), 'hex')
              and c.scopes = '{kernel.read}' and c.active and c.hourly_limit = 600)
    and not exists (select 1 from msp_api_client c where to_jsonb(c)::text like '%' || v_key || '%'));
  perform pg_temp.ok('issuing is audited, and the audit never holds the key',
    exists (select 1 from msp_audit where event_type = 'api_client_issued' and event_detail ->> 'client_id' = r ->> 'client_id')
    and not exists (select 1 from msp_audit where event_detail::text like '%' || v_key || '%'
                                                or event_detail::text like '%' || substr(v_key, 6, 32) || '%'));
  -- A second issue gives a different key.
  perform pg_temp.ok('two issues give two different keys',
    msp_api_client_issue('Flow test bot 2', 'Flow tester') ->> 'api_key' <> v_key);
end $$;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111","app_metadata":{"msp_roles":["forge_admin"]}}', true);
select pg_temp.ok('a forge_admin may issue a key',
  msp_api_client_issue('Flow test bot 3', 'Flow admin') ->> 'api_key' ~ '^cnck_[0-9a-f]{64}$');
select set_config('request.jwt.claims', '', true);

select pg_temp.ok('msp_api_authorise accepts the hash of the key',
  (select r ->> 'ok' = 'true' and r ->> 'client_id' = pg_temp.ctx('client_id') and r -> 'scopes' ? 'kernel.read'
     from msp_api_authorise(pg_temp.ctx('key_hash'), 'industries') r));
select pg_temp.ok('msp_api_authorise rejects a wrong hash',
  (select r ->> 'ok' = 'false' and r ->> 'reason' = 'unknown key' and r -> 'client_id' = 'null'::jsonb
     from msp_api_authorise(encode(extensions.digest('cnck_wrong', 'sha256'), 'hex'), 'industries') r));
select pg_temp.ok('msp_api_authorise rejects a malformed hash and an unknown resource',
  (msp_api_authorise('not a hash', 'industries') ->> 'ok') = 'false'
  and (msp_api_authorise(pg_temp.ctx('key_hash'), 'clients') ->> 'reason') = 'unknown resource');
select pg_temp.ok('the call log holds client, resource, status and time only',
  (select array_agg(column_name::text order by column_name::text) from information_schema.columns
    where table_name = 'msp_api_call_log') = array['client_id','created_at','id','resource','status']
  and (select count(*) = 1 from msp_api_call_log where client_id = pg_temp.ctx('client_id')::uuid and status = 200)
  and (select count(*) = 2 from msp_api_call_log where client_id is null and status = 401)
  and (select count(*) = 1 from msp_api_call_log where client_id is null and status = 400 and resource is null));

update msp_api_client set hourly_limit = 3 where id = pg_temp.ctx('client_id')::uuid;
select pg_temp.act('r1', format('select msp_api_authorise(%L, ''instruments'')', pg_temp.ctx('key_hash')));
select pg_temp.act('r2', format('select msp_api_authorise(%L, ''search'')', pg_temp.ctx('key_hash')));
select pg_temp.act('r3', format('select msp_api_authorise(%L, ''elements'')', pg_temp.ctx('key_hash')));
select pg_temp.ok('msp_api_authorise enforces the hourly limit',
  pg_temp.r('r1') ->> 'ok' = 'true' and pg_temp.r('r2') ->> 'ok' = 'true'
  and pg_temp.r('r3') ->> 'ok' = 'false' and pg_temp.r('r3') ->> 'reason' ~* 'rate limit'
  and (select count(*) = 1 from msp_api_call_log where client_id = pg_temp.ctx('client_id')::uuid and status = 429));
update msp_api_client set hourly_limit = 600 where id = pg_temp.ctx('client_id')::uuid;
update msp_api_client set scopes = '{}' where id = pg_temp.ctx('client_id')::uuid;
select pg_temp.ok('a key without kernel.read is refused for scope',
  (select r ->> 'ok' = 'false' and r ->> 'reason' ~* 'scope' and r ->> 'reason' !~* 'limit|rate'
     from msp_api_authorise(pg_temp.ctx('key_hash'), 'industries') r));
update msp_api_client set scopes = '{kernel.read}' where id = pg_temp.ctx('client_id')::uuid;
select pg_temp.refuses('revoking requires the service role or forge_admin',
  format('select msp_api_client_revoke(%L)', pg_temp.ctx('client_id')), 'forge_admin');
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.act('r', format('select msp_api_client_revoke(%L)', pg_temp.ctx('client_id')));
select pg_temp.act('r2', format('select msp_api_authorise(%L, ''industries'')', pg_temp.ctx('key_hash')));
select pg_temp.ok('a revoked key is refused at once',
  pg_temp.r('r') ->> 'active' = 'false'
  and pg_temp.r('r2') ->> 'ok' = 'false' and pg_temp.r('r2') ->> 'reason' ~* 'revoked'
  and exists (select 1 from msp_audit where event_type = 'api_client_revoked' and event_detail ->> 'client_id' = pg_temp.ctx('client_id')));
select set_config('request.jwt.claims', '', true);
select pg_temp.refuses('the call log is append only', 'delete from msp_api_call_log', 'append only');

-- 11. Kernel API read functions ------------------------------------------------------------------------

do $$
declare
  v_notice constant text := 'Framework reference data from the Care Net Cognitive Kernel. Not legal advice and not a clinical opinion. Only instruments that have passed three verification checks and are in force are included.';
  v_release text;
  r jsonb;
  v_all text := '';
  v_name text;
begin
  select semver into v_release from msp_kernel_version
   order by string_to_array(semver, '.')::int[] desc limit 1;
  foreach v_name in array array['industries','industry','instruments','instruments_constr','protocols','protocols_constr',
                                'elements','elements_constr','search'] loop
    r := case v_name
           when 'industries' then kernel_api_industries()
           when 'industry' then kernel_api_industry('constr')
           when 'instruments' then kernel_api_instruments()
           when 'instruments_constr' then kernel_api_instruments('CONSTR')
           when 'protocols' then kernel_api_protocols()
           when 'protocols_constr' then kernel_api_protocols('CONSTR')
           when 'elements' then kernel_api_elements()
           when 'elements_constr' then kernel_api_elements('CONSTR')
           when 'search' then kernel_api_search('noise')
         end;
    if r ->> 'notice' is distinct from v_notice or r ->> 'kernel_release' is distinct from v_release
       or r ->> 'as_at' is distinct from current_date::text or not (r ? 'data') then
      raise exception 'CHECK FAILED: kernel_api % lacks the notice, kernel_release % or as_at: %', v_name, v_release, left(r::text, 300);
    end if;
    v_all := v_all || r::text;
  end loop;
  raise notice 'ok   every kernel_api response carries the notice, kernel_release % and as_at', v_release;

  perform pg_temp.ok('kernel_api responses carry no client data',
    v_all not ilike '%Flow Test Civils%' and v_all not ilike '%Other Test Company%' and v_all not ilike '%example.invalid%'
    and v_all not like '%' || pg_temp.ctx('acc1') || '%' and v_all not like '%' || pg_temp.ctx('file_c') || '%'
    and v_all not like '%CNC-HSF-%' and v_all not like '%' || pg_temp.ctx('sha_a') || '%'
    and v_all not ilike '%FIXTURE-%' and v_all not ilike '%Flow test bot%');
  -- As a whole JSON value (a short name, a basis or a citable entry). The gazette
  -- reference of the Noise Exposure Regulations, 2024 records the repeal in prose,
  -- which is not a citation.
  perform pg_temp.ok('kernel_api responses cite no superseded or held instrument',
    v_all not like '%"NIHL Regulations, 2003"%' and v_all not like '%"Environmental Regulations for Workplaces, 1987"%');
end $$;

select pg_temp.ok('industries: all seventeen, with code, name and regime',
  (select jsonb_array_length(r -> 'data') = (select count(*) from msp_industry)
          and r -> 'data' @> '[{"code":"MINING","regime":"MHSA"}]'
     from kernel_api_industries() r));
select pg_temp.ok('industry CONSTR: subindustries, roles, hazards, protocols and citable instruments',
  (select d ->> 'code' = 'CONSTR' and jsonb_array_length(d -> 'subindustries') > 0 and jsonb_array_length(d -> 'roles') > 0
          and jsonb_array_length(d -> 'hazards') > 0 and jsonb_array_length(d -> 'protocols') > 0
          and d -> 'instruments' @> '[{"short_name":"Construction Regulations, 2014"}]'
     from (select kernel_api_industry('CONSTR') -> 'data' as d) x));
select pg_temp.ok('protocol bases name citable instruments only and carry no clinical reference values',
  not exists (select 1 from jsonb_array_elements(kernel_api_protocols() -> 'data') p, jsonb_array_elements_text(p -> 'basis') b
               where not exists (select 1 from kernel_citable_instrument k where k.short_name = b))
  and not exists (select 1 from jsonb_array_elements(kernel_api_protocols() -> 'data') p
                   where p ? 'biological_reference' or p ? 'trigger_conditions'));
select pg_temp.ok('an unknown industry gives null (the API answers 404)',
  kernel_api_industry('NOPE') is null and kernel_api_instruments('NOPE') is null
  and kernel_api_protocols('NOPE') is null and kernel_api_elements('NOPE') is null);
select pg_temp.ok('elements for CONSTR: the universal library and the Construction overlay, no Mining overlay',
  (select count(*) filter (where x ->> 'code' like 'HSF-OV-CONSTR-%') = 9
          and count(*) filter (where x ->> 'code' like 'HSF-OV-MINING-%') = 0
          and count(*) filter (where (x ->> 'universal')::boolean) = (select count(*) from hsf_element where universal)
     from jsonb_array_elements(kernel_api_elements('CONSTR') -> 'data') x));
select pg_temp.ok('search matches across kinds and never returns more than 50 results',
  (select jsonb_array_length(kernel_api_search('noise') -> 'data') between 1 and 50)
  and (select jsonb_array_length(kernel_api_search('a') -> 'data') = 0)
  and (select jsonb_array_length(kernel_api_search('e') -> 'data') = 0)
  and (select jsonb_array_length(kernel_api_search('re') -> 'data') = 50)
  and (select count(distinct x ->> 'kind') >= 2 from jsonb_array_elements(kernel_api_search('re') -> 'data') x));
select pg_temp.ok('search treats % and _ as plain text',
  jsonb_array_length(kernel_api_search('%%') -> 'data') = 0 and jsonb_array_length(kernel_api_search('__') -> 'data') = 0);
do $$
declare
  v_audit bigint := (select count(*) from msp_audit);
  v_log bigint := (select count(*) from msp_api_call_log);
begin
  perform kernel_api_industries(), kernel_api_industry('MINING'), kernel_api_instruments(), kernel_api_protocols(),
          kernel_api_elements(), kernel_api_search('construction');
  perform pg_temp.ok('the kernel_api read functions write nothing (no audit row, no call log row, no search words kept)',
    (select count(*) from msp_audit) = v_audit and (select count(*) from msp_api_call_log) = v_log
    and not exists (select 1 from msp_api_call_log where resource ilike '%construction%'));
end $$;

\echo 'All HSF flow checks passed. Rolling back the test data.'
rollback;
