-- CNC MSP FORGE | HSF-LCH-01 launch controls checks | local test harness only.
-- Proves migration 052 (build contract section 10, Amendment 2, items 10.1 to
-- 10.6) against a replayed database: the upload gate, client verification, the
-- security scan, the two year staging limit and deletion by the client with a
-- PIN. Never applied to Supabase. Everything runs in one transaction that is
-- rolled back, so the fictitious auth users, company accounts, Files and
-- uploads it creates never persist.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_launch_checks.sql
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

-- Runs p_sql and passes only when it is refused with exactly p_message.
create function pg_temp.refuses_exactly(p_name text, p_sql text, p_message text) returns void language plpgsql as $$
declare
  v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
  end;
  if v_msg is distinct from p_message then
    raise exception 'CHECK FAILED: % (refused with "%", expected exactly "%")', p_name, coalesce(v_msg, 'no refusal'), p_message;
  end if;
  raise notice 'ok   % (refused: %)', p_name, v_msg;
end $$;

create temp table ctx (k text primary key, v text);
create function pg_temp.ctx(p_k text) returns text language sql as $$ select v from ctx where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$
  insert into ctx values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
-- Runs an action and keeps its jsonb reply under p_k, so the checks that follow,
-- as their own statements, see what the action wrote.
create function pg_temp.act(p_k text, p_sql text) returns void language plpgsql as $$
declare
  v jsonb;
begin
  execute p_sql into v;
  perform pg_temp.put(p_k, v::text);
end $$;
create function pg_temp.r(p_k text) returns jsonb language sql as $$ select v::jsonb from ctx where k = p_k $$;
-- The SQLSTATE a statement raises, or null when it succeeds.
create function pg_temp.sqlstate_of(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlstate;
end $$;
-- Registers and completes one upload for a user; returns the upload id.
create function pg_temp.upload(p_user text, p jsonb) returns text language plpgsql as $$
declare
  v_id text;
begin
  v_id := hsf_register_upload(pg_temp.ctx(p_user)::uuid, p) ->> 'upload_id';
  perform hsf_mark_uploaded(pg_temp.ctx(p_user)::uuid, v_id::uuid);
  return v_id;
end $$;
-- The ids a claim returns, sorted, as a json array.
create function pg_temp.scan_ids() returns jsonb language sql as $$
  select coalesce(jsonb_agg(q.id::text order by q.id::text), '[]'::jsonb) from hsf_scan_claim(100) q $$;
create function pg_temp.claim_ids() returns jsonb language sql as $$
  select coalesce(jsonb_agg(q.id::text order by q.id::text), '[]'::jsonb) from hsf_transfer_claim(100) q $$;
create function pg_temp.ids(variadic p text[]) returns jsonb language sql as $$
  select jsonb_agg(x order by x) from unnest(p) x $$;
create function pg_temp.status_of(p_k text) returns text language sql as $$
  select status from hsf_upload where id = pg_temp.ctx(p_k)::uuid $$;

-- The role checks below run as anon and authenticated, which still read and write the context.
grant select, insert, update on ctx to anon, authenticated;

-- Fictitious people and company accounts. Client A (approved_client, which is
-- not enough on its own), client B (applicant), a declined account, a person
-- without an account, and a forge_admin. The fingerprints are SHA 256 values of
-- fixed test strings, never real documents.
insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data, phone, phone_confirmed_at) values
  ('a1111111-1111-4111-8111-111111111111', 'launch.client@example.invalid', now(), null, '27600000001', now()),
  ('a2222222-2222-4222-8222-222222222222', 'launch.other@example.invalid', now(), null, null, null),
  ('a3333333-3333-4333-8333-333333333333', 'launch.admin@example.invalid', now(), '{"msp_roles":["forge_admin"]}', null, null),
  ('a4444444-4444-4444-8444-444444444444', 'launch.declined@example.invalid', now(), null, null, null),
  ('a5555555-5555-4555-8555-555555555555', 'launch.nobody@example.invalid', now(), null, null, null);
insert into msp_client_account (id, company_name, contact_name, contact_email, account_kind, auth_user_id) values
  ('aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Launch Test Civils (Pty) Ltd', 'Launch Tester', 'launch.client@example.invalid', 'approved_client', 'a1111111-1111-4111-8111-111111111111'),
  ('aaaa2222-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Launch Other Company (Pty) Ltd', 'Other Tester', 'launch.other@example.invalid', 'applicant', 'a2222222-2222-4222-8222-222222222222'),
  ('aaaa4444-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Launch Declined Company (Pty) Ltd', 'Declined Tester', 'launch.declined@example.invalid', 'declined', 'a4444444-4444-4444-8444-444444444444');

select pg_temp.put('u1', 'a1111111-1111-4111-8111-111111111111');
select pg_temp.put('u2', 'a2222222-2222-4222-8222-222222222222');
select pg_temp.put('u3', 'a3333333-3333-4333-8333-333333333333');
select pg_temp.put('u4', 'a4444444-4444-4444-8444-444444444444');
select pg_temp.put('u5', 'a5555555-5555-4555-8555-555555555555');
select pg_temp.put('acc1', 'aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.put('acc2', 'aaaa2222-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.put('acc4', 'aaaa4444-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select pg_temp.put('sha_a', encode(extensions.digest('hsf launch test document a', 'sha256'), 'hex'));
select pg_temp.put('sha_b', encode(extensions.digest('hsf launch test document b', 'sha256'), 'hex'));
select pg_temp.put('reg_ok', jsonb_build_object('department_code', 'SHE', 'original_name', 'Site plan.pdf',
  'mime_type', 'application/pdf', 'size_bytes', 1024, 'sha256', pg_temp.ctx('sha_a'))::text);
select pg_temp.put('msg_closed', 'Document uploads open soon. Your File can be built now, and uploads will open once Care Net has finished testing.');
select pg_temp.put('msg_unverified', 'Uploads are for verified Care Net Consultants clients. Ask for verification in the builder, or WhatsApp a sales executive.');

-- 1. Objects, grants, definer settings and parameters ------------------------------------------

do $$
declare
  f text;
  v_fn regprocedure;
begin
  foreach f in array array[
    'hsf_staging_retention_days()', 'hsf_upload_deletable(text, text, timestamptz)',
    'hsf_upload_awaits_cleanup(text, text, timestamptz, text)', 'hsf_revoke_upload_evidence(uuid)',
    'hsf_client_verified(uuid)', 'hsf_request_client_verification(uuid)', 'hsf_upload_gate(uuid)',
    'hsf_register_upload(uuid, jsonb)', 'hsf_scan_claim(int)', 'hsf_scan_record(uuid, text, text, jsonb)',
    'hsf_transfer_claim(int)', 'hsf_transfer_record(uuid, text, text, text, text, text, text)',
    'hsf_retention_queue(int)', 'hsf_mark_expired(uuid)', 'hsf_mark_staging_deleted(uuid)',
    'hsf_transfer_cleanup_queue(int)', 'hsf_staging_alerts_list()', 'hsf_my_uploads(uuid, uuid)',
    'hsf_deletion_request_create(uuid, uuid[], text, boolean)', 'hsf_deletion_request_pin_sent(uuid, uuid)',
    'hsf_deletion_request_cancel(uuid, uuid)', 'hsf_deletion_request_attempt(uuid, uuid)',
    'hsf_deletion_request_confirm(uuid, uuid)'] loop
    v_fn := f::regprocedure;
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception 'CHECK FAILED: % is executable by anon or authenticated', f;
    end if;
    if not has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'CHECK FAILED: % is not executable by the service role', f;
    end if;
  end loop;
  raise notice 'ok   every 052 function other than verify and revoke is service role only';

  foreach f in array array['hsf_verify_client(uuid, text, text)', 'hsf_revoke_client_verification(uuid, text)',
                           'hsf_scan_reset(uuid)'] loop
    v_fn := f::regprocedure;
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('public', v_fn, 'execute')
       or not has_function_privilege('authenticated', v_fn, 'execute')
       or not has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'CHECK FAILED: % grants are not authenticated and service role only', f;
    end if;
  end loop;
  raise notice 'ok   verify, revoke and the scan reset run for authenticated (staff checked inside) and the service role, never anon';

  foreach f in array array[
    'hsf_staging_retention_days()', 'hsf_revoke_upload_evidence(uuid)', 'hsf_client_verified(uuid)',
    'hsf_request_client_verification(uuid)', 'hsf_verify_client(uuid, text, text)',
    'hsf_revoke_client_verification(uuid, text)', 'hsf_upload_gate(uuid)', 'hsf_register_upload(uuid, jsonb)',
    'hsf_scan_claim(int)', 'hsf_scan_record(uuid, text, text, jsonb)', 'hsf_transfer_claim(int)',
    'hsf_transfer_record(uuid, text, text, text, text, text, text)', 'hsf_retention_queue(int)',
    'hsf_mark_expired(uuid)', 'hsf_mark_staging_deleted(uuid)', 'hsf_transfer_cleanup_queue(int)',
    'hsf_staging_alerts_list()', 'hsf_my_uploads(uuid, uuid)',
    'hsf_deletion_request_create(uuid, uuid[], text, boolean)', 'hsf_deletion_request_pin_sent(uuid, uuid)',
    'hsf_deletion_request_cancel(uuid, uuid)', 'hsf_deletion_request_attempt(uuid, uuid)',
    'hsf_deletion_request_confirm(uuid, uuid)', 'hsf_scan_reset(uuid)'] loop
    if not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                     and exists (select 1 from unnest(p.proconfig) c where c = 'search_path=public')) then
      raise exception 'CHECK FAILED: % is not security definer with search_path=public', f;
    end if;
    if obj_description(f::regprocedure, 'pg_proc') is null then
      raise exception 'CHECK FAILED: % has no comment', f;
    end if;
  end loop;
  raise notice 'ok   every 052 function with data access is security definer with search_path=public and commented';
end $$;

select pg_temp.ok('both 052 tables have Row Level Security on and a comment',
  (select count(*) = 2 and bool_and(c.relrowsecurity) and bool_and(obj_description(c.oid, 'pg_class') is not null)
     from pg_class c where c.relname in ('hsf_client_verification','hsf_deletion_request')
      and c.relnamespace = 'public'::regnamespace));
select pg_temp.ok('the 052 tables: no privilege for anon or public, select only for authenticated, all for the service role',
  not exists (select 1 from unnest(array['hsf_client_verification','hsf_deletion_request']) t,
                            unnest(array['select','insert','update','delete']) p
               where has_table_privilege('anon', t, p) or has_table_privilege('public', t, p)
                  or (p <> 'select' and has_table_privilege('authenticated', t, p))
                  or not has_table_privilege('service_role', t, p))
  and has_table_privilege('authenticated', 'hsf_client_verification', 'select'));
select pg_temp.ok('hsf_upload status check keeps every 049 value and adds expired and client_deleted',
  (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'hsf_upload_status_check'
     and c.conrelid = 'hsf_upload'::regclass)
  ~ all (array['awaiting_upload','''uploaded''','''verified''','''held''','''transferring''','''transferred''',
               'staging_deleted','rejected','failed','expired','client_deleted']));
select pg_temp.ok('hsf_upload carries the scan columns, scan_status defaults to pending and scan_attempts to 0',
  (select count(*) = 5 from information_schema.columns where table_name = 'hsf_upload'
      and column_name in ('scan_status','scan_engine','scanned_at','scan_findings','scan_attempts'))
  and (select column_default like '''pending''%' and is_nullable = 'NO' from information_schema.columns
        where table_name = 'hsf_upload' and column_name = 'scan_status')
  and (select column_default = '0' and is_nullable = 'NO' from information_schema.columns
        where table_name = 'hsf_upload' and column_name = 'scan_attempts')
  and (select bool_and(col_description('hsf_upload'::regclass, a.attnum) is not null) from pg_attribute a
        where a.attrelid = 'hsf_upload'::regclass and a.attname like 'scan\_%'));
select pg_temp.ok('the three 052 parameters exist in category hsf with the contract values',
  msp_env_get_bool('hsf.uploads_open') = false
  and msp_env_get_int('hsf.staging_retention_days') = 730
  and msp_env_get_bool('hsf.deletion_sms_enabled') = false
  and (select count(*) = 3 from msp_env_parameter where category = 'hsf'
        and key in ('hsf.uploads_open','hsf.staging_retention_days','hsf.deletion_sms_enabled'))
  and (select min_value = 1 and max_value = 730 from msp_env_parameter where key = 'hsf.staging_retention_days')
  and (select description = 'Opens company uploads in the File builder. Stays off until the backend (Odendaal) and the front end (Cassandra and the designer) are signed off.'
         from msp_env_parameter where key = 'hsf.uploads_open'));
select pg_temp.ok('the evidence withdrawal is one helper: the mismatch, scan, expiry and deletion paths all call it',
  (select bool_and(pg_get_functiondef(f::regprocedure) ~ 'hsf_revoke_upload_evidence\(v_up\.id\)'
                   and pg_get_functiondef(f::regprocedure) !~* 'update hsf_evidence set revoked_at')
     from unnest(array['hsf_transfer_record(uuid, text, text, text, text, text, text)', 'hsf_scan_record(uuid, text, text, jsonb)',
                       'hsf_mark_expired(uuid)', 'hsf_deletion_request_confirm(uuid, uuid)']) f));

-- 2. Uploads closed (contract 10.1) and the refusal order -------------------------------------------

select pg_temp.ok('the gate for a new client: closed, not verified, nothing requested, consent incomplete',
  hsf_upload_gate(pg_temp.ctx('u1')::uuid) = '{"uploads_open": false, "client_verified": false, "verification_requested": false,
    "consent_complete": false, "deletion_sms_available": false}'::jsonb);
select pg_temp.ok('the gate for a person without an account reads all false',
  (select not (g ->> 'uploads_open')::boolean and not (g ->> 'client_verified')::boolean
          and not (g ->> 'consent_complete')::boolean from hsf_upload_gate(pg_temp.ctx('u5')::uuid) g));

select pg_temp.refuses('order 1: no account comes first, even while uploads are closed',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u5'), pg_temp.ctx('reg_ok')), 'register your company account');
select pg_temp.refuses('order 2: a declined account comes before uploads closed',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u4'), pg_temp.ctx('reg_ok')), 'cannot upload documents');
select pg_temp.refuses_exactly('order 3: uploads closed, with the exact contract words, before verification and consent',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'), pg_temp.ctx('reg_ok')), pg_temp.ctx('msg_closed'));

-- Consent, File generation and item status still work while uploads are closed.
select pg_temp.ok('consent is recorded while uploads are closed',
  hsf_record_consent(pg_temp.ctx('u1')::uuid, array['document_storage','mco_transfer','authority_to_share'], 'HSF-CONSENT-1.0') ->> 'complete' = 'true');
do $$
declare
  r jsonb;
begin
  r := hsf_generate_file(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'industry_code', 'CONSTR',
         'triggers', jsonb_build_array('T-CONSTR', 'T-CONSTR-NOTIFY', 'T-HEIGHT', 'T-ELEC', 'T-CONTRACTORS'),
         'scope', jsonb_build_object('sites', jsonb_build_array(jsonb_build_object('name', 'Launch test site')))));
  perform pg_temp.put('file_c', r ->> 'file_id');
  perform pg_temp.ok('a File is generated while uploads are closed', (r ->> 'items')::int > 0);
  perform pg_temp.put('item_a06', (select fi.id::text from hsf_file_item fi join hsf_element e on e.id = fi.element_id
                                    where fi.file_id = (r ->> 'file_id')::uuid and e.code = 'HSF-A-06'));
  perform pg_temp.put('item_a05', (select fi.id::text from hsf_file_item fi join hsf_element e on e.id = fi.element_id
                                    where fi.file_id = (r ->> 'file_id')::uuid and e.code = 'HSF-A-05'));
  perform pg_temp.put('item_a07', (select fi.id::text from hsf_file_item fi join hsf_element e on e.id = fi.element_id
                                    where fi.file_id = (r ->> 'file_id')::uuid and e.code = 'HSF-A-07'));
end $$;
select pg_temp.ok('item status is set while uploads are closed',
  hsf_set_item_status(pg_temp.ctx('u1')::uuid, pg_temp.ctx('item_a07')::uuid, 'not_applicable', 'Not carried on at this site.') ->> 'status' = 'not_applicable');
select pg_temp.refuses_exactly('with consent complete, uploads closed still refuses',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'), pg_temp.ctx('reg_ok')), pg_temp.ctx('msg_closed'));

-- The Director opens uploads through msp_env_set as forge_admin; nobody else can.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "a1111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select pg_temp.refuses('a client cannot open uploads',
  'select msp_env_set(''hsf.uploads_open'', ''true'', ''launch test'')', 'forge_admin');
select set_config('request.jwt.claims', '{"sub": "a3333333-3333-4333-8333-333333333333", "role": "authenticated", "email": "launch.admin@example.invalid", "app_metadata": {"msp_roles": ["forge_admin"]}}', true);
select pg_temp.refuses('the retention limit cannot be raised past two years',
  'select msp_env_set(''hsf.staging_retention_days'', ''731'', ''launch test'')', 'ceiling');
select pg_temp.ok('forge_admin opens uploads through msp_env_set',
  msp_env_set('hsf.uploads_open', 'true', 'Launch test: backend and front end signed off') ->> 'new_value' = 'true');
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('the gate reads open and the change is in the parameter history',
  (hsf_upload_gate(pg_temp.ctx('u1')::uuid) ->> 'uploads_open')::boolean
  and exists (select 1 from msp_env_parameter_history where key = 'hsf.uploads_open' and new_value = 'true'));

select pg_temp.refuses('order 1 again with uploads open: no account',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u5'), pg_temp.ctx('reg_ok')), 'register your company account');
select pg_temp.refuses('order 2 again with uploads open: declined',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u4'), pg_temp.ctx('reg_ok')), 'cannot upload documents');
select pg_temp.refuses_exactly('order 4: an approved_client that is not verified is refused, with the exact contract words',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'), pg_temp.ctx('reg_ok')), pg_temp.ctx('msg_unverified'));
select pg_temp.refuses_exactly('order 4 before 5: an unverified account without consent hears about verification first',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u2'), pg_temp.ctx('reg_ok')), pg_temp.ctx('msg_unverified'));

-- 3. Client verification (contract 10.2) ------------------------------------------------------------

select pg_temp.act('r', format('select hsf_request_client_verification(%L)', pg_temp.ctx('u1')));
select pg_temp.ok('a client asks for verification: status requested, audited',
  pg_temp.r('r') ->> 'status' = 'requested' and pg_temp.r('r') ->> 'client_account_id' = pg_temp.ctx('acc1')
  and (select count(*) = 1 from msp_audit where event_type = 'hsf_client_verification_requested'
         and event_detail ->> 'client_account_id' = pg_temp.ctx('acc1')));
select pg_temp.act('r', format('select hsf_request_client_verification(%L)', pg_temp.ctx('u1')));
select pg_temp.ok('asking again returns the same request and audits nothing new',
  pg_temp.r('r') ->> 'status' = 'requested'
  and (select count(*) = 1 from hsf_client_verification where client_account_id = pg_temp.ctx('acc1')::uuid)
  and (select count(*) = 1 from msp_audit where event_type = 'hsf_client_verification_requested'));
select pg_temp.ok('the gate shows the request',
  (hsf_upload_gate(pg_temp.ctx('u1')::uuid) ->> 'verification_requested')::boolean
  and not (hsf_upload_gate(pg_temp.ctx('u1')::uuid) ->> 'client_verified')::boolean);
select pg_temp.refuses('a person without an account cannot ask for verification',
  format('select hsf_request_client_verification(%L)', pg_temp.ctx('u5')), 'register your company account');
select pg_temp.refuses('a declined account cannot ask for verification',
  format('select hsf_request_client_verification(%L)', pg_temp.ctx('u4')), 'cannot be verified');
select pg_temp.refuses_exactly('a request alone does not open uploads',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'), pg_temp.ctx('reg_ok')), pg_temp.ctx('msg_unverified'));

set local role anon;
select pg_temp.refuses('anon cannot verify a client',
  format('select hsf_verify_client(%L, ''client_register'', ''REG-1'')', pg_temp.ctx('acc1')), 'permission denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "a1111111-1111-4111-8111-111111111111", "role": "authenticated", "email": "launch.client@example.invalid"}', true);
select pg_temp.refuses('a client cannot verify their own account',
  format('select hsf_verify_client(%L, ''client_register'', ''REG-1'')', pg_temp.ctx('acc1')), 'staff role');
select pg_temp.ok('the refusal to a client carries SQLSTATE 42501 (403 at the API)',
  pg_temp.sqlstate_of(format('select hsf_verify_client(%L, ''client_register'', ''REG-1'')', pg_temp.ctx('acc1'))) = '42501');
select pg_temp.refuses('a client cannot revoke a verification',
  format('select hsf_revoke_client_verification(%L, ''No longer a client'')', pg_temp.ctx('acc1')), 'staff role');
select count(*) as verif_rows_client from hsf_client_verification \gset
select set_config('request.jwt.claims', '{"sub": "a3333333-3333-4333-8333-333333333333", "role": "authenticated", "email": "launch.admin@example.invalid", "app_metadata": {"msp_roles": ["forge_admin"]}}', true);
select count(*) as verif_rows_staff from hsf_client_verification \gset
select pg_temp.refuses('verification needs an evidence reference',
  format('select hsf_verify_client(%L, ''client_register'', ''   '')', pg_temp.ctx('acc1')), 'rests on');
select pg_temp.refuses('verification needs a known method',
  format('select hsf_verify_client(%L, ''website'', ''REG-1'')', pg_temp.ctx('acc1')), 'mco_company_ref, client_register or sales_executive');
select pg_temp.ok('an unknown account raises P0002',
  pg_temp.sqlstate_of(format('select hsf_verify_client(%L, ''client_register'', ''REG-1'')', gen_random_uuid())) = 'P0002');
select pg_temp.refuses('a declined account cannot be verified',
  format('select hsf_verify_client(%L, ''sales_executive'', ''Call on 23/09/2026'')', pg_temp.ctx('acc4')), 'declined');
select pg_temp.act('r', format('select hsf_verify_client(%L, ''mco_company_ref'', ''  MCO-COMPANY-TEST-1 '')', pg_temp.ctx('acc1')));
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('staff read the verification table through RLS; a client reads none',
  :'verif_rows_staff' = '1' and :'verif_rows_client' = '0');
select pg_temp.ok('a forge_admin verifies client A: method, trimmed evidence, verified_by from the JWT email',
  pg_temp.r('r') ->> 'status' = 'verified'
  and exists (select 1 from hsf_client_verification where client_account_id = pg_temp.ctx('acc1')::uuid
                and status = 'verified' and method = 'mco_company_ref' and evidence_ref = 'MCO-COMPANY-TEST-1'
                and verified_by = 'launch.admin@example.invalid' and verified_at is not null)
  and exists (select 1 from msp_audit where event_type = 'hsf_client_verified' and actor = 'launch.admin@example.invalid'
                and event_detail ->> 'client_account_id' = pg_temp.ctx('acc1')));
select set_config('request.jwt.claims', '{"role": "service_role"}', true);
select pg_temp.act('r', format('select hsf_verify_client(%L, ''client_register'', ''REG-LAUNCH-2'')', pg_temp.ctx('acc2')));
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('the service role verifies client B without a prior request; verified_by is service_role',
  pg_temp.r('r') ->> 'verified_by' = 'service_role'
  and hsf_client_verified(pg_temp.ctx('acc2')::uuid) and hsf_client_verified(pg_temp.ctx('acc1')::uuid)
  and not hsf_client_verified(pg_temp.ctx('acc4')::uuid));
select pg_temp.ok('the gate shows client A verified with consent complete',
  (select (g ->> 'client_verified')::boolean and not (g ->> 'verification_requested')::boolean
          and (g ->> 'consent_complete')::boolean from hsf_upload_gate(pg_temp.ctx('u1')::uuid) g));
select pg_temp.refuses('order 5: a verified account without consent hears about consent',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u2'), pg_temp.ctx('reg_ok')), 'three consents');
select pg_temp.refuses('order 6: then the 049 checks (department)',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u1'),
         (pg_temp.ctx('reg_ok')::jsonb || '{"department_code":"NOPE"}')::text), 'department');
select pg_temp.ok('no upload row was written by any refusal', not exists (select 1 from hsf_upload));
select pg_temp.ok('the refusal order in the function body is account, declined, closed, verified, consent, department',
  (select position('Register your company account before uploading' in d) < position('cannot upload documents' in d)
      and position('cannot upload documents' in d) < position('Document uploads open soon' in d)
      and position('Document uploads open soon' in d) < position('Uploads are for verified' in d)
      and position('Uploads are for verified' in d) < position('All three consents' in d)
      and position('All three consents' in d) < position('Choose the department' in d)
     from pg_get_functiondef('hsf_register_upload(uuid, jsonb)'::regprocedure) d));

select pg_temp.ok('client B records consent', hsf_record_consent(pg_temp.ctx('u2')::uuid,
  array['document_storage','mco_transfer','authority_to_share'], 'HSF-CONSENT-1.0') ->> 'complete' = 'true');

-- 4. Security scan (contract 10.4) ------------------------------------------------------------------

do $$
begin
  -- A: element HSF-A-06 of the File (holds evidence). B, C, D: general documents.
  -- E: client B's. F: registered, never completed.
  perform pg_temp.put('up_a', pg_temp.upload('u1', jsonb_build_object('file_id', pg_temp.ctx('file_c'), 'element_code', 'HSF-A-06',
    'department_code', 'SHE', 'original_name', 'Client spec.pdf', 'mime_type', 'application/pdf', 'size_bytes', 2048, 'sha256', pg_temp.ctx('sha_a'))));
  perform pg_temp.put('up_b', pg_temp.upload('u1', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_c', pg_temp.upload('u1', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_d', pg_temp.upload('u1', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_e', pg_temp.upload('u2', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_f', hsf_register_upload(pg_temp.ctx('u1')::uuid, pg_temp.ctx('reg_ok')::jsonb) ->> 'upload_id');
end $$;
-- Everything in this transaction shares one now(), so give the uploads distinct ages: A is the oldest.
update hsf_upload set uploaded_at = now() - interval '5 minutes' where id = pg_temp.ctx('up_a')::uuid;
update hsf_upload set uploaded_at = now() - interval '4 minutes' where id = pg_temp.ctx('up_b')::uuid;
update hsf_upload set uploaded_at = now() - interval '3 minutes' where id = pg_temp.ctx('up_c')::uuid;
update hsf_upload set uploaded_at = now() - interval '2 minutes' where id = pg_temp.ctx('up_d')::uuid;
update hsf_upload set uploaded_at = now() - interval '1 minute' where id = pg_temp.ctx('up_e')::uuid;

select pg_temp.ok('a verified client with consent uploads once uploads are open; every new upload waits for the scan',
  (select count(*) = 6 and bool_and(scan_status = 'pending' and scan_attempts = 0) from hsf_upload)
  and pg_temp.status_of('up_a') = 'uploaded' and pg_temp.status_of('up_f') = 'awaiting_upload');
select pg_temp.ok('the builder sees the scan state of each upload',
  (select bool_and(x ->> 'scan_status' = 'pending') and count(*) = 5
     from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u1')::uuid)) x));

select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('hold mode: the transfer claim returns no unscanned upload', pg_temp.r('claim') = '[]'::jsonb);
update msp_env_parameter set value = 'fixture' where key = 'hsf.mco_transfer_mode';
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('fixture mode: the transfer claim returns no unscanned upload and moves nothing',
  pg_temp.r('claim') = '[]'::jsonb and not exists (select 1 from hsf_upload where status = 'transferring'));
update msp_env_parameter set value = 'hold' where key = 'hsf.mco_transfer_mode';
select pg_temp.refuses('an unscanned upload cannot be recorded held',
  format('select hsf_transfer_record(%L, ''hold'', ''held'', null, null, null, null)', pg_temp.ctx('up_b')), 'security scan');
select pg_temp.refuses('an unscanned upload cannot be recorded received',
  format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, ''FIXTURE-X'', %L, null)',
         pg_temp.ctx('up_b'), pg_temp.ctx('sha_a'), pg_temp.ctx('sha_a')), 'security scan');

select pg_temp.act('scan', 'select coalesce(jsonb_agg(q.id::text), ''[]''::jsonb) from hsf_scan_claim(100) q');
select pg_temp.ok('the scan claim takes uploaded, pending rows with bytes, oldest first, and skips the unfinished F',
  pg_temp.r('scan') = jsonb_build_array(pg_temp.ctx('up_a'), pg_temp.ctx('up_b'), pg_temp.ctx('up_c'),
                                        pg_temp.ctx('up_d'), pg_temp.ctx('up_e'))
  and (select bool_and(scan_attempts = 1) from hsf_upload where status = 'uploaded')
  and (select scan_attempts = 0 from hsf_upload where id = pg_temp.ctx('up_f')::uuid));
select pg_temp.ok('the scan claim respects its limit', (select count(*) = 2 from hsf_scan_claim(2)));
select pg_temp.ok('the scan claim takes row locks with skip locked, so parallel workers never share a row',
  pg_get_functiondef('hsf_scan_claim(int)'::regprocedure) ~* 'for update of u skip locked');

select pg_temp.refuses('an unknown scan result is refused',
  format('select hsf_scan_record(%L, ''fine'', null, null)', pg_temp.ctx('up_b')), 'unknown scan result');
select pg_temp.refuses('scan findings must be a list',
  format('select hsf_scan_record(%L, ''clean'', null, ''{"a":1}''::jsonb)', pg_temp.ctx('up_b')), 'must be a list');
select pg_temp.refuses('an upload that has not arrived cannot be scanned',
  format('select hsf_scan_record(%L, ''clean'', null, null)', pg_temp.ctx('up_f')), 'not waiting for a security scan');

select pg_temp.act('r', format('select hsf_scan_record(%L, ''clean'', ''ClamAV test 1.0'', ''[]''::jsonb)', pg_temp.ctx('up_b')));
select pg_temp.ok('clean: scan_status clean, the upload stays uploaded, engine and time recorded, audited',
  pg_temp.r('r') ->> 'scan_status' = 'clean' and pg_temp.r('r') ->> 'status' = 'uploaded'
  and exists (select 1 from hsf_upload where id = pg_temp.ctx('up_b')::uuid and status = 'uploaded'
                and scan_status = 'clean' and scan_engine = 'ClamAV test 1.0' and scanned_at is not null)
  and exists (select 1 from msp_audit where event_type = 'hsf_upload_scanned' and event_detail ->> 'upload_id' = pg_temp.ctx('up_b')));
select pg_temp.refuses('a clean upload is not scanned again',
  format('select hsf_scan_record(%L, ''infected'', null, null)', pg_temp.ctx('up_b')), 'not waiting for a security scan');
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('hold mode: only the clean upload is claimed',
  pg_temp.r('claim') = pg_temp.ids(pg_temp.ctx('up_b')));
select pg_temp.ok('in hold mode a clean upload still becomes held',
  hsf_transfer_record(pg_temp.ctx('up_b')::uuid, 'hold', 'held', null, null, null, null) ->> 'status' = 'held');

select pg_temp.act('r', format('select hsf_scan_record(%L, ''error'', ''ClamAV test 1.0'', %L::jsonb)', pg_temp.ctx('up_c'),
                               '[{"code":"engine_timeout","message":"The antivirus engine did not answer."}]'));
select pg_temp.ok('error: scan_status error, the upload stays uploaded and is not claimed for transfer',
  pg_temp.r('r') ->> 'scan_status' = 'error'
  and (select status = 'uploaded' and scan_status = 'error' from hsf_upload where id = pg_temp.ctx('up_c')::uuid)
  and not exists (select 1 from hsf_transfer_claim(100) q where q.id = pg_temp.ctx('up_c')::uuid));
update hsf_upload set scan_attempts = 4 where id = pg_temp.ctx('up_c')::uuid;
select pg_temp.act('scan', 'select pg_temp.scan_ids()');
select pg_temp.ok('an engine error is retried: C is claimed again, its fifth attempt',
  pg_temp.r('scan') ? pg_temp.ctx('up_c')
  and (select scan_attempts = 5 from hsf_upload where id = pg_temp.ctx('up_c')::uuid));
select pg_temp.act('scan', 'select pg_temp.scan_ids()');
select pg_temp.ok('after five attempts the upload is not claimed for a scan again',
  not (pg_temp.r('scan') ? pg_temp.ctx('up_c')) and pg_temp.r('scan') ? pg_temp.ctx('up_a'));

select pg_temp.put('pct_before_a', (select coalesce(compliance_pct, 0)::text from hsf_file where id = pg_temp.ctx('file_c')::uuid));
select pg_temp.ok('before the scan, A holds evidence and its File item is uploaded',
  (select status = 'uploaded' from hsf_file_item where id = pg_temp.ctx('item_a06')::uuid)
  and exists (select 1 from hsf_evidence where upload_id = pg_temp.ctx('up_a')::uuid and revoked_at is null)
  and pg_temp.ctx('pct_before_a')::numeric > 0);
select pg_temp.act('r', format('select hsf_scan_record(%L, ''infected'', ''ClamAV test 1.0'', %L::jsonb)', pg_temp.ctx('up_a'),
  '[{"code":"virus","message":"A known virus was found (Eicar-Test-Signature)"}]'));
select pg_temp.ok('infected: the upload is rejected with the plain reason the builder shows',
  pg_temp.r('r') ->> 'status' = 'rejected'
  and (select status = 'rejected' and scan_status = 'infected'
              and reject_reason = 'The file failed the security scan: A known virus was found (Eicar-Test-Signature).'
              and scan_findings -> 0 ->> 'code' = 'virus'
         from hsf_upload where id = pg_temp.ctx('up_a')::uuid));
select pg_temp.ok('infected: the evidence row is revoked, the item returns to outstanding and the figure is recomputed',
  (select count(*) = 1 from hsf_evidence where upload_id = pg_temp.ctx('up_a')::uuid and revoked_at is not null)
  and (select status = 'outstanding' from hsf_file_item where id = pg_temp.ctx('item_a06')::uuid)
  and (select coalesce(compliance_pct, 0) < pg_temp.ctx('pct_before_a')::numeric
              and coalesce(compliance_pct, 0) = coalesce((hsf_compliance_figures(id) -> 'overall' ->> 'pct')::numeric, 0)
         from hsf_file where id = pg_temp.ctx('file_c')::uuid));
select pg_temp.ok('infected: audited as hsf_upload_scan_rejected against the File, and the bytes are queued for removal',
  exists (select 1 from msp_audit where event_type = 'hsf_upload_scan_rejected' and hsf_file_id = pg_temp.ctx('file_c')::uuid
            and event_detail ->> 'upload_id' = pg_temp.ctx('up_a') and (event_detail ->> 'evidence_revoked')::int = 1)
  and exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
               where x ->> 'upload_id' = pg_temp.ctx('up_a') and x ->> 'reason' = 'rejected'));
-- Several findings join into one reason; the worker's messages end in a full
-- stop, which is dropped before the join. Undone at once, so D is rejected below.
savepoint s_join;
select pg_temp.ok('harmful with several findings: one reason reading ''X; Y.'', never ''X.; Y.''',
  hsf_scan_record(pg_temp.ctx('up_d')::uuid, 'harmful', 'CNC structural check', '[{"code":"pdf_javascript","message":"The PDF contains JavaScript."},
    {"code":"pdf_launch","message":"The PDF can start another program."}]'::jsonb) ->> 'reject_reason'
  = 'The file failed the security scan: The PDF can start another program; The PDF contains JavaScript.');
rollback to savepoint s_join;
select pg_temp.act('r', format('select hsf_scan_record(%L, ''harmful'', null, %L::jsonb)', pg_temp.ctx('up_d'), '[{"code":"pdf_js"}]'));
select pg_temp.ok('harmful without plain words: rejected with the default reason',
  (select status = 'rejected' and scan_status = 'harmful'
          and reject_reason = 'The file failed the security scan: the file carries content that could cause harm.'
     from hsf_upload where id = pg_temp.ctx('up_d')::uuid));
select pg_temp.ok('the builder shows the failed scan and its reason',
  (select x ->> 'scan_status' = 'infected' and x ->> 'reject_reason' like 'The file failed the security scan: %'
     from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u1')::uuid)) x where x ->> 'upload_id' = pg_temp.ctx('up_a')));
select pg_temp.ok('scanning never touched a transfer claim: nothing is transferring',
  not exists (select 1 from hsf_upload where status = 'transferring'));

-- E (client B) passes, so both accounts have clean staged uploads for what follows.
select pg_temp.ok('client B''s upload passes the scan',
  hsf_scan_record(pg_temp.ctx('up_e')::uuid, 'clean', 'ClamAV test 1.0', null) ->> 'scan_status' = 'clean');

-- 5. Revoking a verification blocks and deletes nothing (contract 10.2) ------------------------------

do $$
begin
  -- G: a fresh, unscanned upload of client B, blocked by the revocation below.
  perform pg_temp.put('up_g', pg_temp.upload('u2', pg_temp.ctx('reg_ok')::jsonb));
end $$;
select set_config('request.jwt.claims', '{"role": "service_role"}', true);
select pg_temp.refuses('a revocation needs a reason',
  format('select hsf_revoke_client_verification(%L, ''  '')', pg_temp.ctx('acc2')), 'reason');
select pg_temp.refuses('an account that is not verified cannot be revoked',
  format('select hsf_revoke_client_verification(%L, ''Not a client'')', pg_temp.ctx('acc4')), 'not verified');
select pg_temp.act('r', format('select hsf_revoke_client_verification(%L, ''Contract ended on 22/09/2026'')', pg_temp.ctx('acc2')));
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('revocation: status revoked with who, when and why, audited',
  pg_temp.r('r') ->> 'status' = 'revoked' and (pg_temp.r('r') ->> 'blocked_uploads')::int = 2
  and exists (select 1 from hsf_client_verification where client_account_id = pg_temp.ctx('acc2')::uuid and status = 'revoked'
                and revoked_by = 'service_role' and revoked_at is not null and revoke_reason = 'Contract ended on 22/09/2026')
  and exists (select 1 from msp_audit where event_type = 'hsf_client_verification_revoked'
                and event_detail ->> 'client_account_id' = pg_temp.ctx('acc2')));
select pg_temp.ok('revocation blocks the account''s untransferred uploads and deletes nothing',
  (select bool_and(transfer_blocked_reason = 'client verification revoked' and storage_path is not null and status = 'uploaded')
     from hsf_upload where client_account_id = pg_temp.ctx('acc2')::uuid)
  and not exists (select 1 from hsf_upload where client_account_id = pg_temp.ctx('acc1')::uuid and transfer_blocked_reason is not null));
select pg_temp.ok('blocked uploads are neither scanned, claimed for transfer nor queued for cleanup',
  not exists (select 1 from hsf_scan_claim(100) q where q.client_account_id = pg_temp.ctx('acc2')::uuid)
  and not exists (select 1 from hsf_transfer_claim(100) q where q.client_account_id = pg_temp.ctx('acc2')::uuid)
  and not exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
                   where x ->> 'upload_id' in (pg_temp.ctx('up_e'), pg_temp.ctx('up_g'))));
select pg_temp.refuses_exactly('a revoked account cannot register uploads',
  format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u2'), pg_temp.ctx('reg_ok')), pg_temp.ctx('msg_unverified'));
select pg_temp.ok('a revoked account may ask again: status requested, the revocation details kept',
  hsf_request_client_verification(pg_temp.ctx('u2')::uuid) ->> 'status' = 'requested'
  and (select revoke_reason is not null from hsf_client_verification where client_account_id = pg_temp.ctx('acc2')::uuid));
select set_config('request.jwt.claims', '{"role": "service_role"}', true);
select pg_temp.act('r', format('select hsf_verify_client(%L, ''sales_executive'', ''Confirmed by a sales executive on 23/09/2026'')', pg_temp.ctx('acc2')));
select pg_temp.ok('verification again clears the revocation fields',
  pg_temp.r('r') ->> 'status' = 'verified'
  and (select revoked_at is null and revoke_reason is null from hsf_client_verification where client_account_id = pg_temp.ctx('acc2')::uuid));
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('the uploads blocked by the revocation stay blocked after verification again',
  (select bool_and(transfer_blocked_reason = 'client verification revoked') from hsf_upload
    where client_account_id = pg_temp.ctx('acc2')::uuid));

-- 6. Two year staging limit (contract 10.3) --------------------------------------------------------

select pg_temp.ok('nothing is past the limit yet', hsf_retention_queue(100) = '[]'::jsonb);
select pg_temp.ok('the builder shows the expiry date of a staged upload: uploaded plus 730 days',
  (select (x ->> 'expires_on')::date = ((select uploaded_at from hsf_upload where id = pg_temp.ctx('up_b')::uuid) + interval '730 days')::date
          and (x ->> 'deletable')::boolean
     from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u1')::uuid)) x where x ->> 'upload_id' = pg_temp.ctx('up_b')));

do $$
begin
  -- H: an element upload (HSF-A-05) of client A that reaches the limit.
  perform pg_temp.put('up_h', pg_temp.upload('u1', jsonb_build_object('file_id', pg_temp.ctx('file_c'), 'element_code', 'HSF-A-05',
    'department_code', 'SHE', 'original_name', 'Risk assessment.pdf', 'mime_type', 'application/pdf', 'size_bytes', 4096, 'sha256', pg_temp.ctx('sha_b'))));
  perform pg_temp.put('pct_before_h', (select coalesce(compliance_pct, 0)::text from hsf_file where id = pg_temp.ctx('file_c')::uuid));
end $$;
select pg_temp.ok('H holds evidence and its File item is uploaded',
  (select status = 'uploaded' from hsf_file_item where id = pg_temp.ctx('item_a05')::uuid));
update hsf_upload set uploaded_at = now() - interval '731 days' where id in (pg_temp.ctx('up_h')::uuid, pg_temp.ctx('up_g')::uuid);
update hsf_upload set uploaded_at = now() - interval '729 days' where id = pg_temp.ctx('up_c')::uuid;
select pg_temp.ok('the retention queue lists the two uploads past 730 days, including the blocked G',
  (select jsonb_agg(x ->> 'upload_id' order by x ->> 'upload_id') from jsonb_array_elements(hsf_retention_queue(100)) x)
    = pg_temp.ids(pg_temp.ctx('up_h'), pg_temp.ctx('up_g'))
  and (select bool_and(x ->> 'reason' = 'retention' and x ->> 'storage_path' is not null)
         from jsonb_array_elements(hsf_retention_queue(100)) x)
  and (select transfer_blocked_reason = 'client verification revoked' from hsf_upload where id = pg_temp.ctx('up_g')::uuid));
select pg_temp.ok('the retention queue respects its limit', jsonb_array_length(hsf_retention_queue(1)) = 1);
select pg_temp.refuses('an upload younger than the limit is not expired',
  format('select hsf_mark_expired(%L)', pg_temp.ctx('up_c')), 'not reached the 730 day');

select pg_temp.act('r', format('select hsf_mark_expired(%L)', pg_temp.ctx('up_h')));
select pg_temp.ok('mark_expired: status expired, path cleared, staging_deleted_at set, row and fingerprint kept',
  pg_temp.r('r') ->> 'status' = 'expired'
  and exists (select 1 from hsf_upload where id = pg_temp.ctx('up_h')::uuid and status = 'expired'
                and storage_path is null and staging_deleted_at is not null and sha256_client = pg_temp.ctx('sha_b')));
select pg_temp.ok('mark_expired: evidence revoked and marked removed from staging, item outstanding, figure recomputed',
  exists (select 1 from hsf_evidence where upload_id = pg_temp.ctx('up_h')::uuid and revoked_at is not null
            and storage_path is null and staging_deleted_at is not null)
  and (select status = 'outstanding' from hsf_file_item where id = pg_temp.ctx('item_a05')::uuid)
  and (select coalesce(compliance_pct, 0) < pg_temp.ctx('pct_before_h')::numeric from hsf_file where id = pg_temp.ctx('file_c')::uuid));
select pg_temp.ok('mark_expired is audited as hsf_upload_expired with the fingerprint',
  exists (select 1 from msp_audit where event_type = 'hsf_upload_expired' and hsf_file_id = pg_temp.ctx('file_c')::uuid
            and event_detail ->> 'upload_id' = pg_temp.ctx('up_h') and event_detail ->> 'sha256' = pg_temp.ctx('sha_b')));
select pg_temp.act('r', format('select hsf_mark_expired(%L)', pg_temp.ctx('up_g')));
select pg_temp.ok('the two year limit overrides a block: the blocked G expires too',
  pg_temp.r('r') ->> 'status' = 'expired' and pg_temp.status_of('up_g') = 'expired');
select pg_temp.refuses('an expired upload cannot be expired twice',
  format('select hsf_mark_expired(%L)', pg_temp.ctx('up_h')), 'holds no bytes');
select pg_temp.refuses('an expired upload holds no staged copy to remove',
  format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_h')), 'already been removed');
select pg_temp.ok('the retention queue is empty again; the builder shows no expiry date for an expired upload',
  hsf_retention_queue(100) = '[]'::jsonb
  and (select x -> 'expires_on' = 'null'::jsonb and not (x ->> 'deletable')::boolean
         from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u1')::uuid)) x where x ->> 'upload_id' = pg_temp.ctx('up_h')));
select pg_temp.refuses('an expired upload row cannot be given its bytes back',
  format('update hsf_upload set storage_path = ''x/y/z.pdf'' where id = %L', pg_temp.ctx('up_h')), 'hsf_upload_expired_no_bytes');

-- Alerts: past hsf.staging_alert_days, or within 30 days of the limit, with expires_on.
select pg_temp.ok('staging alerts carry expires_on; C (729 days) is listed with its expiry date',
  (select (x ->> 'expires_on')::date = ((select uploaded_at from hsf_upload where id = pg_temp.ctx('up_c')::uuid) + interval '730 days')::date
     from jsonb_array_elements(hsf_staging_alerts_list()) x where x ->> 'upload_id' = pg_temp.ctx('up_c'))
  and exists (select 1 from information_schema.columns where table_name = 'hsf_staging_alerts' and column_name = 'expires_on'));
update msp_env_parameter set value = '40' where key = 'hsf.staging_retention_days';
update hsf_upload set uploaded_at = now() - interval '12 days' where id = pg_temp.ctx('up_b')::uuid;
update hsf_upload set uploaded_at = now() - interval '5 days' where id = pg_temp.ctx('up_e')::uuid;
select pg_temp.ok('an upload within 30 days of the limit is alerted before hsf.staging_alert_days is reached',
  exists (select 1 from jsonb_array_elements(hsf_staging_alerts_list()) x
           where x ->> 'upload_id' = pg_temp.ctx('up_b') and (x ->> 'days_in_staging')::int = 12
             and (x ->> 'expires_on')::date = ((select uploaded_at from hsf_upload where id = pg_temp.ctx('up_b')::uuid) + interval '40 days')::date)
  and not exists (select 1 from jsonb_array_elements(hsf_staging_alerts_list()) x where x ->> 'upload_id' = pg_temp.ctx('up_e')));
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "a3333333-3333-4333-8333-333333333333", "role": "authenticated", "app_metadata": {"msp_roles": ["forge_admin"]}}', true);
select count(*) filter (where upload_id::text = pg_temp.ctx('up_b') and expires_on is not null) as alert_view_b from hsf_staging_alerts \gset
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('staff see the same alert, with expires_on, in hsf_staging_alerts', :'alert_view_b' = '1');
update msp_env_parameter set value = '9999' where key = 'hsf.staging_retention_days';
select pg_temp.ok('an out of range stored limit is held to 730 days', (select hsf_staging_retention_days() = 730));
update msp_env_parameter set value = '730' where key = 'hsf.staging_retention_days';
update hsf_upload set uploaded_at = now() - interval '4 minutes' where id = pg_temp.ctx('up_b')::uuid;
update hsf_upload set uploaded_at = now() - interval '1 minute' where id = pg_temp.ctx('up_e')::uuid;

-- 7. Deletion by the client with a PIN (contract 10.5) and after withdrawal (10.6) --------------------

do $$
begin
  -- I: an element upload (HSF-A-05) for the deletion. J: a general upload that
  -- a consent withdrawal will block. K: a general upload that transfers.
  perform pg_temp.put('up_i', pg_temp.upload('u1', jsonb_build_object('file_id', pg_temp.ctx('file_c'), 'element_code', 'HSF-A-05',
    'department_code', 'SHE', 'original_name', 'Risk assessment v2.pdf', 'mime_type', 'application/pdf', 'size_bytes', 4096, 'sha256', pg_temp.ctx('sha_b'))));
  perform pg_temp.put('up_j', pg_temp.upload('u1', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_k', pg_temp.upload('u1', pg_temp.ctx('reg_ok')::jsonb));
  perform hsf_scan_record(pg_temp.ctx('up_k')::uuid, 'clean', 'ClamAV test 1.0', null);
end $$;
update msp_env_parameter set value = 'fixture' where key = 'hsf.mco_transfer_mode';
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('fixture mode: only clean uploads are claimed (B and K), never the unscanned I and J',
  pg_temp.r('claim') = pg_temp.ids(pg_temp.ctx('up_b'), pg_temp.ctx('up_k')));
select pg_temp.ok('K is received at MyClinicOnline',
  hsf_transfer_record(pg_temp.ctx('up_k')::uuid, 'fixture', 'received', pg_temp.ctx('sha_a'), 'FIXTURE-K', pg_temp.ctx('sha_a'), null) ->> 'status' = 'transferred');
select pg_temp.ok('an engine error returns B to uploaded', hsf_transfer_record(pg_temp.ctx('up_b')::uuid, 'fixture', 'error', null, null, null, 'Test') ->> 'status' = 'uploaded');
update msp_env_parameter set value = 'hold' where key = 'hsf.mco_transfer_mode';

-- Contract 10.6: a withdrawal blocks, and the blocked upload stays deletable.
select pg_temp.act('r', format('select hsf_withdraw_consent(%L, ''mco_transfer'')', pg_temp.ctx('u1')));
select pg_temp.ok('withdrawing mco_transfer blocks A''s untransferred uploads',
  pg_temp.r('r') ->> 'mco_transfer' = 'false'
  and (select transfer_blocked_reason = 'consent withdrawn' from hsf_upload where id = pg_temp.ctx('up_j')::uuid));
select pg_temp.ok('the builder shows the blocked upload with its reason and offers deletion; the transferred K is not deletable',
  (select x ->> 'transfer_blocked_reason' = 'consent withdrawn' and (x ->> 'deletable')::boolean
     from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u1')::uuid)) x where x ->> 'upload_id' = pg_temp.ctx('up_j'))
  and (select not (x ->> 'deletable')::boolean
     from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u1')::uuid)) x where x ->> 'upload_id' = pg_temp.ctx('up_k')));
select pg_temp.ok('the two year limit still applies to the blocked J',
  (select (x ->> 'expires_on') is not null from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u1')::uuid)) x
    where x ->> 'upload_id' = pg_temp.ctx('up_j')));

-- Refusals when opening a request.
select pg_temp.refuses('a person without an account cannot ask to delete',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u5'), pg_temp.ctx('up_j')), 'no company account');
select pg_temp.refuses('the irreversible warning must be acknowledged',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', false)', pg_temp.ctx('u1'), pg_temp.ctx('up_j')), 'cannot be undone');
select pg_temp.refuses('an unacknowledged request is refused when the tick is missing altogether',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', null)', pg_temp.ctx('u1'), pg_temp.ctx('up_j')), 'cannot be undone');
select pg_temp.refuses('the channel must be email or SMS',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''whatsapp'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_j')), 'email or sms');
select pg_temp.refuses('SMS is refused while hsf.deletion_sms_enabled is false, even with a confirmed phone',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''sms'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_j')), 'not available');
select pg_temp.refuses('at least one document must be chosen',
  format('select hsf_deletion_request_create(%L, array[]::uuid[], ''email'', true)', pg_temp.ctx('u1')), 'at least one');
select pg_temp.refuses('at most 50 documents per request',
  format('select hsf_deletion_request_create(%L, %L::uuid[], ''email'', true)', pg_temp.ctx('u1'),
         (select array_agg(gen_random_uuid()) from generate_series(1, 51))::text), 'at most 50');
select pg_temp.refuses('another account''s upload cannot be chosen',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_e')), 'cannot be deleted here');
select pg_temp.refuses('an upload that does not exist reads the same',
  format('select hsf_deletion_request_create(%L, array[%L, %L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_j'), gen_random_uuid()), 'cannot be deleted here');
select pg_temp.refuses('a document at MyClinicOnline is deleted through MyClinicOnline',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_k')), 'deleted through MyClinicOnline');
select pg_temp.refuses('an expired upload cannot be chosen',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_h')), 'cannot be deleted here');
select pg_temp.ok('the cleanup removes the bytes of the rejected D',
  hsf_mark_staging_deleted(pg_temp.ctx('up_d')::uuid) ->> 'status' = 'rejected');
select pg_temp.refuses('a rejected upload whose bytes are already removed cannot be chosen',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_d')), 'cannot be deleted here');
select pg_temp.ok('no refusal wrote a request', not exists (select 1 from hsf_deletion_request));

-- Request 1: I (element upload), J (blocked) and A (rejected by the scan, bytes still staged), duplicates folded.
select pg_temp.act('req1', format('select hsf_deletion_request_create(%L, array[%L, %L, %L, %L]::uuid[], ''email'', true)',
  pg_temp.ctx('u1'), pg_temp.ctx('up_i'), pg_temp.ctx('up_j'), pg_temp.ctx('up_a'), pg_temp.ctx('up_i')));
select pg_temp.ok('a request opens with the email hint, the channel and a 10 minute expiry',
  pg_temp.r('req1') ->> 'channel' = 'email' and pg_temp.r('req1') ->> 'destination_hint' = 'l***@example.invalid'
  and exists (select 1 from hsf_deletion_request r where r.id = (pg_temp.r('req1') ->> 'request_id')::uuid
                and r.status = 'pending' and r.attempts = 0 and r.acknowledged_irreversible
                and cardinality(r.upload_ids) = 3 and r.expires_at = r.requested_at + interval '10 minutes'
                and r.client_account_id = pg_temp.ctx('acc1')::uuid and r.auth_user_id = pg_temp.ctx('u1')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_deletion_requested'
                and event_detail ->> 'request_id' = pg_temp.r('req1') ->> 'request_id'));
select pg_temp.put('req1', pg_temp.r('req1') ->> 'request_id');
-- Until Supabase Auth has accepted to send this request's PIN, no PIN counts:
-- a PIN sent for an earlier request, or a sign in code, never confirms it.
select pg_temp.act('r', format('select hsf_deletion_request_attempt(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req1')));
select pg_temp.ok('before its PIN is sent, a request takes no attempt (status pin_not_sent) and counts nothing',
  pg_temp.r('r') = '{"allowed": false, "attempts_left": 5, "status": "pin_not_sent"}'::jsonb
  and (select attempts = 0 and pin_sent_at is null from hsf_deletion_request where id = pg_temp.ctx('req1')::uuid));
select pg_temp.refuses('confirming before the PIN is sent is refused',
  format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req1')), 'not been checked');
select pg_temp.ok('the server records that the PIN was sent',
  hsf_deletion_request_pin_sent(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req1')::uuid) ->> 'pin_sent_at' is not null);
select pg_temp.refuses('the PIN of a request is recorded as sent once only',
  format('select hsf_deletion_request_pin_sent(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req1')), 'no longer open');
select pg_temp.ok('another person cannot record a PIN as sent or cancel the request (P0002)',
  pg_temp.sqlstate_of(format('select hsf_deletion_request_pin_sent(%L, %L)', pg_temp.ctx('u2'), pg_temp.ctx('req1'))) = 'P0002'
  and pg_temp.sqlstate_of(format('select hsf_deletion_request_cancel(%L, %L)', pg_temp.ctx('u2'), pg_temp.ctx('req1'))) = 'P0002');
select pg_temp.refuses('confirming before any PIN attempt is refused',
  format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req1')), 'not been checked');
select pg_temp.ok('another person''s attempt or confirm raises P0002 (404 at the API)',
  pg_temp.sqlstate_of(format('select hsf_deletion_request_attempt(%L, %L)', pg_temp.ctx('u2'), pg_temp.ctx('req1'))) = 'P0002'
  and pg_temp.sqlstate_of(format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u2'), pg_temp.ctx('req1'))) = 'P0002'
  and pg_temp.sqlstate_of(format('select hsf_deletion_request_attempt(%L, %L)', pg_temp.ctx('u1'), gen_random_uuid())) = 'P0002');
select pg_temp.act('r', format('select hsf_deletion_request_attempt(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req1')));
select pg_temp.ok('an attempt is counted before the PIN is checked: allowed, four left',
  pg_temp.r('r') = '{"allowed": true, "attempts_left": 4, "status": "pending"}'::jsonb);

-- A document that moves to MyClinicOnline between request and confirm stops the
-- whole confirmation: all or nothing.
update hsf_upload set status = 'transferred', mco_document_ref = 'FIXTURE-TEST', transferred_at = now() where id = pg_temp.ctx('up_a')::uuid;
select pg_temp.refuses('a confirmation is all or nothing: one document no longer deletable refuses it',
  format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req1')), 'no longer be deleted');
select pg_temp.ok('nothing was deleted by the refused confirmation',
  pg_temp.status_of('up_i') = 'uploaded' and pg_temp.status_of('up_j') = 'uploaded'
  and (select status = 'pending' from hsf_deletion_request where id = pg_temp.ctx('req1')::uuid));
update hsf_upload set status = 'rejected', mco_document_ref = null, transferred_at = null where id = pg_temp.ctx('up_a')::uuid;

select pg_temp.put('pct_before_i', (select coalesce(compliance_pct, 0)::text from hsf_file where id = pg_temp.ctx('file_c')::uuid));
select pg_temp.act('r', format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req1')));
select pg_temp.ok('confirm: the request is confirmed and three documents are deleted',
  pg_temp.r('r') ->> 'status' = 'confirmed' and (pg_temp.r('r') ->> 'deleted')::int = 3
  and (select status = 'confirmed' and confirmed_at is not null from hsf_deletion_request where id = pg_temp.ctx('req1')::uuid));
select pg_temp.ok('confirm: each upload is client_deleted with the block cleared; bytes wait for the cleanup',
  (select bool_and(status = 'client_deleted' and transfer_blocked_reason is null and storage_path is not null)
     from hsf_upload where id in (pg_temp.ctx('up_i')::uuid, pg_temp.ctx('up_j')::uuid, pg_temp.ctx('up_a')::uuid)));
select pg_temp.ok('confirm: the evidence of I is revoked, the item returns to outstanding, the figure is recomputed',
  exists (select 1 from hsf_evidence where upload_id = pg_temp.ctx('up_i')::uuid and revoked_at is not null)
  and (select status = 'outstanding' from hsf_file_item where id = pg_temp.ctx('item_a05')::uuid)
  and (select coalesce(compliance_pct, 0) < pg_temp.ctx('pct_before_i')::numeric from hsf_file where id = pg_temp.ctx('file_c')::uuid));
select pg_temp.ok('confirm: audited per upload with the fingerprints, never a file name',
  (select count(*) = 3 from msp_audit where event_type = 'hsf_upload_client_deleted'
      and event_detail ->> 'request_id' = pg_temp.ctx('req1') and event_detail ->> 'sha256_client' is not null)
  and not exists (select 1 from msp_audit where event_type in ('hsf_upload_client_deleted','hsf_deletion_requested')
                   and event_detail::text ilike '%.pdf%'));
select pg_temp.ok('the cleanup queue lists the deleted uploads with reason client_deleted, including the one that was blocked',
  (select count(*) = 3 and bool_and(x ->> 'reason' = 'client_deleted')
     from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
    where x ->> 'upload_id' in (pg_temp.ctx('up_i'), pg_temp.ctx('up_j'), pg_temp.ctx('up_a'))));
update hsf_upload set transfer_blocked_reason = 'consent withdrawn' where id = pg_temp.ctx('up_j')::uuid;
select pg_temp.ok('a client_deleted upload is queued for cleanup even if it carries a block',
  exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
           where x ->> 'upload_id' = pg_temp.ctx('up_j') and x ->> 'reason' = 'client_deleted'));
update hsf_upload set uploaded_at = now() - interval '800 days' where id = pg_temp.ctx('up_j')::uuid;
select pg_temp.ok('a client deleted upload past the limit is left to the cleanup queue, not the retention queue',
  not exists (select 1 from jsonb_array_elements(hsf_retention_queue(100)) x where x ->> 'upload_id' = pg_temp.ctx('up_j')));
select pg_temp.act('r', format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_j')));
select pg_temp.ok('staging deletion keeps client_deleted and clears the path',
  pg_temp.r('r') ->> 'status' = 'client_deleted'
  and (select status = 'client_deleted' and storage_path is null and staging_deleted_at is not null
         from hsf_upload where id = pg_temp.ctx('up_j')::uuid));
select pg_temp.ok('staging deletion of I keeps client_deleted',
  hsf_mark_staging_deleted(pg_temp.ctx('up_i')::uuid) ->> 'status' = 'client_deleted');
select pg_temp.ok('the evidence row of I is revoked and removed from staging',
  exists (select 1 from hsf_evidence where upload_id = pg_temp.ctx('up_i')::uuid and revoked_at is not null
            and staging_deleted_at is not null and storage_path is null));
select pg_temp.refuses('a confirmed request cannot be confirmed again',
  format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req1')), 'no longer open');
select pg_temp.refuses('a client deleted upload cannot be chosen again',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_i')), 'cannot be deleted here');
select pg_temp.refuses('a client deleted upload is not transferred',
  format('select hsf_transfer_record(%L, ''fixture'', ''error'', null, null, null, null)', pg_temp.ctx('up_a')), 'not waiting for transfer');
select pg_temp.refuses('a client deleted upload is not scanned',
  format('select hsf_scan_record(%L, ''clean'', null, null)', pg_temp.ctx('up_j')), 'not waiting for a security scan');

-- Five attempts, then locked.
select pg_temp.act('req2', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b')));
select pg_temp.put('req2', pg_temp.r('req2') ->> 'request_id');
select hsf_deletion_request_pin_sent(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req2')::uuid);
do $$
declare
  r jsonb;
  i int;
begin
  for i in 1..5 loop
    r := hsf_deletion_request_attempt(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req2')::uuid);
    if not (r ->> 'allowed')::boolean or (r ->> 'attempts_left')::int <> 5 - i then
      raise exception 'CHECK FAILED: attempt % answered %', i, r;
    end if;
  end loop;
  perform pg_temp.put('r', hsf_deletion_request_attempt(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req2')::uuid)::text);
end $$;
select pg_temp.ok('five attempts are allowed, then the request locks',
  pg_temp.r('r') = '{"allowed": false, "attempts_left": 0, "status": "locked"}'::jsonb
  and (select status = 'locked' and attempts = 5 from hsf_deletion_request where id = pg_temp.ctx('req2')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_deletion_request_locked'
                and event_detail ->> 'request_id' = pg_temp.ctx('req2')));
select pg_temp.ok('a locked request stays locked and allows nothing',
  hsf_deletion_request_attempt(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req2')::uuid) ->> 'allowed' = 'false');
select pg_temp.refuses('a locked request cannot be confirmed',
  format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req2')), 'no longer open');
select pg_temp.ok('B was not deleted', pg_temp.status_of('up_b') = 'uploaded');

-- Expiry after 10 minutes.
select pg_temp.act('req3', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b')));
select pg_temp.put('req3', pg_temp.r('req3') ->> 'request_id');
select hsf_deletion_request_pin_sent(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req3')::uuid);
select pg_temp.ok('the attempt on a live request is allowed',
  hsf_deletion_request_attempt(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req3')::uuid) ->> 'allowed' = 'true');
update hsf_deletion_request set requested_at = now() - interval '11 minutes', expires_at = now() - interval '1 minute'
 where id = pg_temp.ctx('req3')::uuid;
select pg_temp.refuses('an expired request cannot be confirmed, even after a PIN attempt',
  format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req3')), 'no longer open');
select pg_temp.act('r', format('select hsf_deletion_request_attempt(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req3')));
select pg_temp.ok('an attempt after 10 minutes marks the request expired and allows nothing',
  pg_temp.r('r') ->> 'allowed' = 'false' and pg_temp.r('r') ->> 'status' = 'expired'
  and (select status = 'expired' and attempts = 1 from hsf_deletion_request where id = pg_temp.ctx('req3')::uuid));

-- A new request cancels the open one, because a new PIN replaces the last.
select pg_temp.act('req4', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b')));
select pg_temp.act('req5', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b')));
select pg_temp.ok('a new request cancels the earlier open one',
  (select status = 'cancelled' from hsf_deletion_request where id = (pg_temp.r('req4') ->> 'request_id')::uuid)
  and (select status = 'pending' from hsf_deletion_request where id = (pg_temp.r('req5') ->> 'request_id')::uuid));

-- At most 5 requests per account per hour (SQLSTATE PT429, 429 at the API).
select pg_temp.ok('five requests were made in the last hour', (select count(*) = 5 from hsf_deletion_request
  where client_account_id = pg_temp.ctx('acc1')::uuid and requested_at > now() - interval '1 hour'));
select pg_temp.ok('a sixth request within the hour is refused with SQLSTATE PT429',
  pg_temp.sqlstate_of(format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b'))) = 'PT429');
select pg_temp.refuses('the rate limit refusal is in plain words',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b')), 'too many deletion requests');
select pg_temp.ok('the limit is per account: client B may still ask',
  (select count(*) = 0 from hsf_deletion_request where client_account_id = pg_temp.ctx('acc2')::uuid)
  and hsf_deletion_request_create(pg_temp.ctx('u2')::uuid, array[pg_temp.ctx('up_e')::uuid], 'email', true) ->> 'channel' = 'email');
update hsf_deletion_request set requested_at = requested_at - interval '61 minutes', expires_at = expires_at - interval '61 minutes'
 where client_account_id = pg_temp.ctx('acc1')::uuid;
select pg_temp.ok('after an hour client A may ask again',
  hsf_deletion_request_create(pg_temp.ctx('u1')::uuid, array[pg_temp.ctx('up_b')::uuid], 'email', true) ->> 'channel' = 'email');

-- SMS only with the parameter on and a confirmed phone.
update msp_env_parameter set value = 'true' where key = 'hsf.deletion_sms_enabled';
select pg_temp.ok('with SMS enabled the gate offers it to a person with a confirmed phone, not to one without',
  (hsf_upload_gate(pg_temp.ctx('u1')::uuid) ->> 'deletion_sms_available')::boolean
  and not (hsf_upload_gate(pg_temp.ctx('u2')::uuid) ->> 'deletion_sms_available')::boolean);
select pg_temp.act('r', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''sms'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b')));
select pg_temp.ok('an SMS request shows only the last four digits',
  pg_temp.r('r') ->> 'channel' = 'sms' and pg_temp.r('r') ->> 'destination_hint' = 'number ending 0001');
select pg_temp.refuses('SMS is refused for a person without a confirmed phone',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''sms'', true)', pg_temp.ctx('u2'), pg_temp.ctx('up_e')), 'not available');
update auth.users set phone_confirmed_at = null where id = pg_temp.ctx('u1')::uuid;
select pg_temp.refuses('SMS is refused once the phone is no longer confirmed',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''sms'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b')), 'not available');
update msp_env_parameter set value = 'false' where key = 'hsf.deletion_sms_enabled';

-- A request whose PIN could not be sent is cancelled and can never be confirmed.
select pg_temp.act('req6', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b')));
select pg_temp.put('req6', pg_temp.r('req6') ->> 'request_id');
select pg_temp.act('r', format('select hsf_deletion_request_cancel(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req6')));
select pg_temp.ok('cancel: the request reads cancelled, audited, and takes no attempt',
  pg_temp.r('r') ->> 'status' = 'cancelled'
  and hsf_deletion_request_attempt(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req6')::uuid) ->> 'allowed' = 'false'
  and exists (select 1 from msp_audit where event_type = 'hsf_deletion_request_cancelled'
                and event_detail ->> 'request_id' = pg_temp.ctx('req6')));
select pg_temp.refuses('a cancelled request cannot be confirmed',
  format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req6')), 'no longer open');
select pg_temp.refuses('a cancelled request cannot have a PIN recorded as sent',
  format('select hsf_deletion_request_pin_sent(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('req6')), 'no longer open');

-- PIN attempts also count per account: a new request does not bring fresh guesses.
select pg_temp.act('req7', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u1'), pg_temp.ctx('up_b')));
select pg_temp.put('req7', pg_temp.r('req7') ->> 'request_id');
select hsf_deletion_request_pin_sent(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req7')::uuid);
update hsf_deletion_request set attempts = 5
 where client_account_id = pg_temp.ctx('acc1')::uuid and requested_at > now() - interval '1 hour'
   and id <> pg_temp.ctx('req7')::uuid;
select pg_temp.ok('ten PIN attempts in the hour on the account: the next is refused as rate_limited and not counted',
  (select sum(attempts) >= 10 from hsf_deletion_request
    where client_account_id = pg_temp.ctx('acc1')::uuid and requested_at > now() - interval '1 hour')
  and hsf_deletion_request_attempt(pg_temp.ctx('u1')::uuid, pg_temp.ctx('req7')::uuid)
      = '{"allowed": false, "attempts_left": 5, "status": "rate_limited"}'::jsonb
  and (select attempts = 0 and status = 'pending' from hsf_deletion_request where id = pg_temp.ctx('req7')::uuid));

-- The table itself holds the rules.
select pg_temp.refuses('a request row without the acknowledgement is refused by the table',
  format('insert into hsf_deletion_request (client_account_id, auth_user_id, upload_ids, channel, acknowledged_irreversible, expires_at)
          values (%L, %L, array[%L]::uuid[], ''email'', false, now() + interval ''10 minutes'')',
         pg_temp.ctx('acc1'), pg_temp.ctx('u1'), pg_temp.ctx('up_b')), 'check constraint');
select pg_temp.refuses('a request row cannot carry more than five attempts',
  format('update hsf_deletion_request set attempts = 6 where id = %L', pg_temp.ctx('req2')), 'check constraint');
select pg_temp.refuses('a request row cannot outlive 10 minutes',
  format('update hsf_deletion_request set expires_at = requested_at + interval ''1 hour'' where id = %L', pg_temp.ctx('req2')), 'check constraint');
select pg_temp.refuses('a request row cannot name 51 uploads',
  format('insert into hsf_deletion_request (client_account_id, auth_user_id, upload_ids, channel, acknowledged_irreversible, requested_at, expires_at)
          values (%L, %L, %L::uuid[], ''email'', true, now(), now() + interval ''10 minutes'')',
         pg_temp.ctx('acc1'), pg_temp.ctx('u1'), (select array_agg(gen_random_uuid()) from generate_series(1, 51))::text), 'check constraint');
select pg_temp.ok('an upload row is still never deleted', pg_temp.sqlstate_of(
  format('delete from hsf_upload where id = %L', pg_temp.ctx('up_i'))) is not null
  and exists (select 1 from hsf_upload where id = pg_temp.ctx('up_i')::uuid));

-- 8. Fix round: scan outages, in flight transfers, blocks and the cleanup ----------------------------
-- Client B (verified again, consents given) supplies fresh uploads.

do $$
begin
  perform pg_temp.put('up_s1', pg_temp.upload('u2', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_s2', pg_temp.upload('u2', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_t1', pg_temp.upload('u2', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_t2', pg_temp.upload('u2', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_t3', pg_temp.upload('u2', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_v1', pg_temp.upload('u2', pg_temp.ctx('reg_ok')::jsonb));
  perform pg_temp.put('up_w1', hsf_register_upload(pg_temp.ctx('u2')::uuid, pg_temp.ctx('reg_ok')::jsonb) ->> 'upload_id');
end $$;

-- An antivirus outage never uses up the five scan attempts.
do $$
declare
  i int;
begin
  for i in 1..6 loop
    if not exists (select 1 from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_s1')::uuid) then
      raise exception 'CHECK FAILED: S1 was not claimed for its scan on round %', i;
    end if;
    perform hsf_scan_record(pg_temp.ctx('up_s1')::uuid, 'error', 'CNC structural check',
      case when i % 2 = 0 then '[{"code":"av_not_configured","message":"Antivirus engine not configured"}]'::jsonb
           else '[{"code":"av_error","message":"The antivirus scan could not finish."}]'::jsonb end);
  end loop;
end $$;
select pg_temp.ok('six engine outages in a row: S1 keeps its attempts and is still claimed for a scan',
  (select scan_status = 'error' and scan_attempts = 0 and status = 'uploaded' from hsf_upload where id = pg_temp.ctx('up_s1')::uuid)
  and exists (select 1 from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_s1')::uuid));
update hsf_upload set scan_attempts = 0 where id = pg_temp.ctx('up_s1')::uuid;

-- Five inspection errors use the attempts up; staff see it and give a fresh start.
do $$
declare
  i int;
begin
  for i in 1..5 loop
    perform hsf_scan_claim(100);
    perform hsf_scan_record(pg_temp.ctx('up_s1')::uuid, 'error', 'CNC structural check',
      '[{"code":"could_not_inspect","message":"The file could not be checked: the archive directory is damaged."}]'::jsonb);
  end loop;
end $$;
select pg_temp.ok('five inspection errors: S1 is no longer claimed, and the staging alerts list it as scan_exhausted',
  (select scan_attempts = 5 from hsf_upload where id = pg_temp.ctx('up_s1')::uuid)
  and not exists (select 1 from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_s1')::uuid)
  and exists (select 1 from jsonb_array_elements(hsf_staging_alerts_list()) x
               where x ->> 'upload_id' = pg_temp.ctx('up_s1') and (x ->> 'scan_exhausted')::boolean)
  and exists (select 1 from information_schema.columns where table_name = 'hsf_staging_alerts' and column_name = 'scan_exhausted'));
select pg_temp.refuses('the scan reset needs the service role or forge staff',
  format('select hsf_scan_reset(%L)', pg_temp.ctx('up_s1')), 'staff role');
select set_config('request.jwt.claims', '{"role": "service_role"}', true);
select pg_temp.act('r', format('select hsf_scan_reset(%L)', pg_temp.ctx('up_s1')));
select pg_temp.refuses('a clean upload cannot be reset',
  format('select hsf_scan_reset(%L)', pg_temp.ctx('up_b')), 'still waiting for its security scan');
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('the scan reset gives S1 its attempts back, it is claimed again, audited',
  pg_temp.r('r') ->> 'scan_attempts' = '0'
  and exists (select 1 from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_s1')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_upload_scan_reset' and actor = 'service_role'
                and event_detail ->> 'upload_id' = pg_temp.ctx('up_s1') and (event_detail ->> 'attempts_before')::int = 5));

-- A fingerprint mismatch at the scan fails the upload; it is not retried.
select pg_temp.act('r', format('select hsf_scan_record(%L, ''error'', ''CNC structural check'', %L::jsonb)', pg_temp.ctx('up_s2'),
  '[{"code":"fingerprint_mismatch","message":"The stored file does not match the fingerprint taken when it was uploaded."}]'));
select pg_temp.ok('fingerprint mismatch at the scan: the upload fails with the reason, audited, and its bytes are queued for removal',
  pg_temp.r('r') ->> 'status' = 'failed'
  and (select status = 'failed' and reject_reason = 'The stored file does not match the fingerprint taken when it was uploaded.'
         from hsf_upload where id = pg_temp.ctx('up_s2')::uuid)
  and not exists (select 1 from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_s2')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_upload_scan_rejected' and event_detail ->> 'upload_id' = pg_temp.ctx('up_s2'))
  and exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
               where x ->> 'upload_id' = pg_temp.ctx('up_s2') and x ->> 'reason' = 'failed'));
select pg_temp.ok('the builder gets no staging expiry date for bytes the cleanup removes next',
  (select x -> 'expires_on' = 'null'::jsonb from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u2')::uuid)) x
    where x ->> 'upload_id' = pg_temp.ctx('up_s2')));

-- A block set while the scan runs does not keep harmful bytes in staging.
update hsf_upload set transfer_blocked_reason = 'consent withdrawn' where id = pg_temp.ctx('up_v1')::uuid;
select pg_temp.act('r', format('select hsf_scan_record(%L, ''infected'', ''ClamAV test 1.0'', %L::jsonb)', pg_temp.ctx('up_v1'),
  '[{"code":"malware","message":"The antivirus scan found a known threat."}]'));
select pg_temp.ok('a blocked upload rejected by the scan loses the block and is queued for removal',
  (select status = 'rejected' and transfer_blocked_reason is null from hsf_upload where id = pg_temp.ctx('up_v1')::uuid)
  and exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
               where x ->> 'upload_id' = pg_temp.ctx('up_v1') and x ->> 'reason' = 'rejected')
  and (select x -> 'expires_on' = 'null'::jsonb from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u2')::uuid)) x
        where x ->> 'upload_id' = pg_temp.ctx('up_v1')));
update hsf_upload set status = 'rejected', transfer_blocked_reason = 'consent withdrawn' where id = pg_temp.ctx('up_v1')::uuid;
select pg_temp.ok('scan rejected bytes are queued for removal even if a block is set afterwards',
  exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x where x ->> 'upload_id' = pg_temp.ctx('up_v1')));

-- A blocked registration that never completed is swept and its bytes removed.
update hsf_upload set transfer_blocked_reason = 'client verification revoked', created_at = now() - interval '2 days'
 where id = pg_temp.ctx('up_w1')::uuid;
select pg_temp.ok('the sweep fails the blocked, never completed W1',
  hsf_sweep_stale_uploads(24) >= 1 and pg_temp.status_of('up_w1') = 'failed');
select pg_temp.ok('a blocked upload that never completed is queued for removal',
  exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
           where x ->> 'upload_id' = pg_temp.ctx('up_w1') and x ->> 'reason' = 'failed'));
select pg_temp.ok('a blocked failed upload that did complete still waits for the client or the two year limit',
  (select not hsf_upload_awaits_cleanup('failed', 'consent withdrawn', now(), 'clean')));

-- A transfer in flight: not deletable, not expired, and a late receipt is kept.
do $$
begin
  perform hsf_scan_record(pg_temp.ctx('up_t1')::uuid, 'clean', 'ClamAV test 1.0', null);
  perform hsf_scan_record(pg_temp.ctx('up_t2')::uuid, 'clean', 'ClamAV test 1.0', null);
  perform hsf_scan_record(pg_temp.ctx('up_t3')::uuid, 'clean', 'ClamAV test 1.0', null);
end $$;
update msp_env_parameter set value = 'fixture' where key = 'hsf.mco_transfer_mode';
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
update msp_env_parameter set value = 'hold' where key = 'hsf.mco_transfer_mode';
select pg_temp.ok('fixture mode: T1, T2 and T3 are claimed and transferring',
  pg_temp.r('claim') ?& array[pg_temp.ctx('up_t1'), pg_temp.ctx('up_t2'), pg_temp.ctx('up_t3')]
  and pg_temp.status_of('up_t1') = 'transferring' and pg_temp.status_of('up_t2') = 'transferring');
select pg_temp.ok('a transfer in flight is not deletable in the builder',
  (select not (x ->> 'deletable')::boolean from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u2')::uuid)) x
    where x ->> 'upload_id' = pg_temp.ctx('up_t1')));
select pg_temp.refuses('a transfer in flight cannot be chosen for deletion',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u2'), pg_temp.ctx('up_t1')), 'being moved there now');
-- T3's claim is over 30 minutes old when the client asks, then a worker claims it again.
update hsf_upload set transfer_claimed_at = now() - interval '31 minutes' where id = pg_temp.ctx('up_t3')::uuid;
select pg_temp.act('req8', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u2'), pg_temp.ctx('up_t3')));
select pg_temp.put('req8', pg_temp.r('req8') ->> 'request_id');
select hsf_deletion_request_pin_sent(pg_temp.ctx('u2')::uuid, pg_temp.ctx('req8')::uuid);
select hsf_deletion_request_attempt(pg_temp.ctx('u2')::uuid, pg_temp.ctx('req8')::uuid);
update hsf_upload set transfer_claimed_at = now() - interval '1 minute' where id = pg_temp.ctx('up_t3')::uuid;
select pg_temp.refuses('a request whose document was claimed for transfer after the request cannot be confirmed',
  format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('u2'), pg_temp.ctx('req8')), 'no longer be deleted');

update hsf_upload set uploaded_at = now() - interval '3 years' where id = pg_temp.ctx('up_t2')::uuid;
select pg_temp.ok('a transfer in flight is not taken by the two year limit',
  not exists (select 1 from jsonb_array_elements(hsf_retention_queue(100)) x where x ->> 'upload_id' = pg_temp.ctx('up_t2')));
select pg_temp.refuses('a transfer in flight cannot be expired',
  format('select hsf_mark_expired(%L)', pg_temp.ctx('up_t2')), 'being transferred');

-- A transfer that stopped part way (claimed over 30 minutes ago) is deletable
-- again; if MyClinicOnline answers after the deletion, its receipt is kept.
update hsf_upload set transfer_claimed_at = now() - interval '31 minutes' where id = pg_temp.ctx('up_t1')::uuid;
select pg_temp.ok('a stopped transfer, claimed over 30 minutes ago, is deletable again',
  (select (x ->> 'deletable')::boolean from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u2')::uuid)) x
    where x ->> 'upload_id' = pg_temp.ctx('up_t1')));
select pg_temp.act('req9', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('u2'), pg_temp.ctx('up_t1')));
select pg_temp.put('req9', pg_temp.r('req9') ->> 'request_id');
select hsf_deletion_request_pin_sent(pg_temp.ctx('u2')::uuid, pg_temp.ctx('req9')::uuid);
select hsf_deletion_request_attempt(pg_temp.ctx('u2')::uuid, pg_temp.ctx('req9')::uuid);
select pg_temp.ok('the client deletes the stopped transfer',
  hsf_deletion_request_confirm(pg_temp.ctx('u2')::uuid, pg_temp.ctx('req9')::uuid) ->> 'status' = 'confirmed'
  and pg_temp.status_of('up_t1') = 'client_deleted');
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, ''FIXTURE-LATE'', %L, null)',
  pg_temp.ctx('up_t1'), pg_temp.ctx('sha_a'), pg_temp.ctx('sha_a')));
select pg_temp.ok('a receipt after the deletion keeps the MyClinicOnline reference and asks for the deletion there',
  pg_temp.r('r') ->> 'status' = 'client_deleted' and (pg_temp.r('r') ->> 'mco_deletion_needed')::boolean
  and (select status = 'client_deleted' and mco_document_ref = 'FIXTURE-LATE' from hsf_upload where id = pg_temp.ctx('up_t1')::uuid)
  and exists (select 1 from hsf_mco_transfer where upload_id = pg_temp.ctx('up_t1')::uuid and outcome = 'received'
                and mco_document_ref = 'FIXTURE-LATE' and mco_receipt_sha256 = pg_temp.ctx('sha_a'))
  and exists (select 1 from msp_audit where event_type = 'hsf_transfer_received_after_deletion'
                and event_detail ->> 'upload_id' = pg_temp.ctx('up_t1') and event_detail ->> 'mco_document_ref' = 'FIXTURE-LATE')
  and exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
               where x ->> 'upload_id' = pg_temp.ctx('up_t1') and x ->> 'reason' = 'client_deleted'));
select pg_temp.refuses('a late receipt whose fingerprints do not match is refused as before',
  format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, ''FIXTURE-LATE'', %L, null)',
         pg_temp.ctx('up_t1'), pg_temp.ctx('sha_b'), pg_temp.ctx('sha_b')), 'not waiting for transfer');

-- A consent withdrawn while the transfer is in flight: once received, the
-- staging copy still leaves (the copy at MyClinicOnline is confirmed).
update hsf_upload set transfer_blocked_reason = 'consent withdrawn' where id = pg_temp.ctx('up_t2')::uuid;
select pg_temp.ok('a blocked transfer in flight that is received becomes transferred',
  hsf_transfer_record(pg_temp.ctx('up_t2')::uuid, 'fixture', 'received', pg_temp.ctx('sha_a'), 'FIXTURE-T2', pg_temp.ctx('sha_a'), null)
    ->> 'status' = 'transferred');
select pg_temp.ok('its staged bytes are queued for removal even though it carries a block',
  exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
           where x ->> 'upload_id' = pg_temp.ctx('up_t2') and x ->> 'reason' = 'transferred'));

do $$ begin raise notice 'hsf_launch_checks: all checks passed. Rolling back the test data.'; end $$;
rollback;
