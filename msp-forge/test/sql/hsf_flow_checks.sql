-- CNC MSP FORGE | HSF-UPL-01, KRN-API-01 and HSF-GEN-01 flow checks | local test harness only.
-- Proves migrations 049 (consent, uploads, MCO transfer bookkeeping), 050 (kernel
-- API) and 051 (generation and compliance), with Amendment 1 of the build
-- contract (sections 9.1 to 9.8), against a replayed database. Migration 052
-- (Amendment 2, launch controls) is in force here: the flow opens uploads,
-- verifies its accounts and runs the scan pass before any transfer, and
-- hsf_launch_checks.sql proves those controls. Never applied to Supabase.
-- Everything runs in one transaction that is rolled back, so the fictitious
-- auth users, company accounts and Files it creates never persist.
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
-- The SQLSTATE a statement raises, or null when it succeeds.
create function pg_temp.sqlstate_of(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlstate;
end $$;

-- Migration 052 (contract 10.4): an upload moves only after the scan pass has
-- recorded it clean. This runs the pass for the named uploads, as the worker would.
create function pg_temp.scan_clean(variadic p_keys text[]) returns void language plpgsql as $$
declare
  k text;
begin
  perform 1 from hsf_scan_claim(100);
  foreach k in array p_keys loop
    perform hsf_scan_record(pg_temp.ctx(k)::uuid, 'clean', 'flow test engine', '[]'::jsonb);
  end loop;
end $$;

-- The role checks below run as anon and authenticated, which still read the context.
grant select on ctx to anon, authenticated;

-- A fictitious signed in client, a second client, and a staff user. The upload
-- fingerprints are SHA 256 values of fixed test strings, never real documents.
-- The first client's company account is made the way production makes it: a
-- landing page sign on (msp_client_signon, a typed email and no sign in) and a
-- Supabase auth user with a confirmed email, joined by hsf_link_account
-- (contract 9.1). The second account is a plain fixture.
insert into auth.users (id, email, email_confirmed_at) values
  ('11111111-1111-4111-8111-111111111111', 'flow.client@example.invalid', now()),
  ('22222222-2222-4222-8222-222222222222', 'other.client@example.invalid', now()),
  ('33333333-3333-4333-8333-333333333333', 'no.account@example.invalid', now());
insert into msp_client_account (id, company_name, contact_name, contact_email, account_kind, auth_user_id) values
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Other Test Company (Pty) Ltd', 'Other Tester', 'other.client@example.invalid', 'applicant', '22222222-2222-4222-8222-222222222222');

select pg_temp.put('u1', '11111111-1111-4111-8111-111111111111');
select pg_temp.put('u2', '22222222-2222-4222-8222-222222222222');
select pg_temp.put('u3', '33333333-3333-4333-8333-333333333333');
select pg_temp.act('signon', $q$select msp_client_signon('{"company_name":"Flow Test Civils (Pty) Ltd","contact_name":"Flow Tester","contact_email":"  Flow.Client@Example.INVALID "}'::jsonb)$q$);
select pg_temp.put('acc1', pg_temp.r('signon') ->> 'reference');
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
    'hsf_my_files(uuid)', 'hsf_file_detail(uuid, uuid)', 'hsf_set_item_status(uuid, uuid, text, text)',
    'hsf_link_account(uuid)', 'hsf_transfer_mode()', 'hsf_transfer_claim(int)', 'hsf_transfer_cleanup_queue(int)',
    'hsf_sweep_stale_uploads(int)', 'hsf_staging_alerts_list()', 'hsf_portal_summary(uuid)'] loop
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
    'hsf_my_files(uuid)', 'hsf_file_detail(uuid, uuid)', 'hsf_set_item_status(uuid, uuid, text, text)',
    'hsf_link_account(uuid)', 'hsf_transfer_mode()', 'hsf_transfer_claim(int)', 'hsf_transfer_cleanup_queue(int)',
    'hsf_sweep_stale_uploads(int)', 'hsf_staging_alerts_list()', 'hsf_portal_summary(uuid)',
    'hsf_element_citable(uuid)'] loop
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

  -- The worker reads its mode through hsf_transfer_mode, never msp_env_get (contract 9.5).
  if has_function_privilege('anon', 'msp_env_get(text)', 'execute')
     or has_function_privilege('authenticated', 'msp_env_get(text)', 'execute') then
    raise exception 'CHECK FAILED: msp_env_get is executable by anon or authenticated';
  end if;
  raise notice 'ok   msp_env_get stays internal; the worker uses hsf_transfer_mode';

  -- hsf_element_citable backs the public element library, so anon may run it; it
  -- returns published short names only.
  if not has_function_privilege('anon', 'hsf_element_citable(uuid)', 'execute')
     or has_function_privilege('public', 'hsf_element_citable(uuid)', 'execute') then
    raise exception 'CHECK FAILED: hsf_element_citable is not executable by anon';
  end if;
  raise notice 'ok   hsf_element_citable is executable by anon for the public element library';
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
select pg_temp.ok('the two builder views are readable by anon (contract 9.7)',
  has_table_privilege('anon', 'hsf_public_trigger', 'select')
  and has_table_privilege('anon', 'hsf_public_subindustry', 'select'));
select pg_temp.ok('the staging alerts view is not readable by anon or public',
  not has_table_privilege('anon', 'hsf_staging_alerts', 'select')
  and not has_table_privilege('public', 'hsf_staging_alerts', 'select')
  and has_table_privilege('authenticated', 'hsf_staging_alerts', 'select'));
select pg_temp.ok('hsf_upload carries transfer_blocked_reason and transfer_claimed_at (contract 9.5)',
  (select count(*) = 2 from information_schema.columns
    where table_name = 'hsf_upload' and column_name in ('transfer_blocked_reason','transfer_claimed_at')));
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
select pg_temp.ok('hsf.files_per_account_per_day defaults to 20 (contract 9.6)',
  msp_env_get_int('hsf.files_per_account_per_day') = 20
  and (select category from msp_env_parameter where key = 'hsf.files_per_account_per_day') = 'hsf');
select pg_temp.ok('hsf_transfer_mode reads hold', hsf_transfer_mode() = 'hold');

-- 1b. Account linking (contract 9.1) -----------------------------------------------------------

select pg_temp.ok('the sign on made an approved account with the email in lower case and no auth user',
  exists (select 1 from msp_client_account where id = pg_temp.ctx('acc1')::uuid
            and contact_email = 'flow.client@example.invalid' and account_kind = 'approved_client'
            and auth_user_id is null and company_name = 'Flow Test Civils (Pty) Ltd'));
select pg_temp.ok('before linking, the signed in person has no company account',
  (select s -> 'client_account_id' = 'null'::jsonb from hsf_consent_status(pg_temp.ctx('u1')::uuid) s));
select pg_temp.ok('hsf_link_account links the account of the confirmed email',
  hsf_link_account(pg_temp.ctx('u1')::uuid) = pg_temp.ctx('acc1')::uuid);
select pg_temp.ok('the account now carries the auth user, and consent status finds it',
  (select auth_user_id = pg_temp.ctx('u1')::uuid from msp_client_account where id = pg_temp.ctx('acc1')::uuid)
  and (select s ->> 'client_account_id' = pg_temp.ctx('acc1') from hsf_consent_status(pg_temp.ctx('u1')::uuid) s));
select pg_temp.ok('a second call returns the same account and links nothing new',
  hsf_link_account(pg_temp.ctx('u1')::uuid) = pg_temp.ctx('acc1')::uuid
  and (select count(*) = 1 from msp_audit where event_type = 'client_auth_linked'
         and event_detail ->> 'client_account_id' = pg_temp.ctx('acc1')
         and event_detail ->> 'auth_user_id' = pg_temp.ctx('u1')));
select pg_temp.ok('an already linked account is returned for its own user (fixture account B)',
  hsf_link_account(pg_temp.ctx('u2')::uuid) = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid);
select pg_temp.ok('a user whose email has no account links nothing', hsf_link_account(pg_temp.ctx('u3')::uuid) is null
  and hsf_link_account(null) is null);

insert into auth.users (id, email, email_confirmed_at) values
  ('44444444-4444-4444-8444-444444444444', 'unconfirmed.client@example.invalid', null),
  ('55555555-5555-4555-8555-555555555555', 'declined.client@example.invalid', now()),
  ('66666666-6666-4666-8666-666666666666', 'two.accounts@example.invalid', now());
insert into msp_client_account (id, company_name, contact_name, contact_email, account_kind, created_at) values
  ('44444444-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Unconfirmed Test Company (Pty) Ltd', 'Unconfirmed Tester', 'unconfirmed.client@example.invalid', 'approved_client', now()),
  ('55555555-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Declined Test Company (Pty) Ltd', 'Declined Tester', 'declined.client@example.invalid', 'declined', now()),
  ('66666666-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Older Test Company (Pty) Ltd', 'Two Tester', 'two.accounts@example.invalid', 'approved_client', now() - interval '2 days'),
  ('66666666-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Newer Test Company (Pty) Ltd', 'Two Tester', 'Two.Accounts@example.invalid', 'applicant', now() - interval '1 day'),
  ('66666666-cccc-4ccc-8ccc-cccccccccccc', 'Newest Declined Test Company (Pty) Ltd', 'Two Tester', 'two.accounts@example.invalid', 'declined', now());
select pg_temp.ok('an unconfirmed email links nothing',
  hsf_link_account('44444444-4444-4444-8444-444444444444') is null
  and (select auth_user_id is null from msp_client_account where id = '44444444-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));
select pg_temp.ok('a declined account is never linked',
  hsf_link_account('55555555-5555-4555-8555-555555555555') is null
  and (select auth_user_id is null from msp_client_account where id = '55555555-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));
select pg_temp.ok('the latest account that is not declined is linked',
  hsf_link_account('66666666-6666-4666-8666-666666666666') = '66666666-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid
  and (select auth_user_id is null from msp_client_account where id = '66666666-cccc-4ccc-8ccc-cccccccccccc')
  and (select auth_user_id is null from msp_client_account where id = '66666666-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));
select pg_temp.ok('hsf_evidence.upload_id references hsf_upload',
  exists (select 1 from pg_constraint where conname = 'hsf_evidence_upload_fk' and confrelid = 'hsf_upload'::regclass));

-- 2. Consent ---------------------------------------------------------------------------------

-- Migration 052 (contract 10.1 and 10.2): uploads stay closed until the Director
-- opens them, and only verified Care Net Consultants clients upload. This flow
-- runs with uploads open and both accounts verified by the service role;
-- hsf_launch_checks.sql proves the gate, the verification and the refusal order.
update msp_env_parameter set value = 'true' where key = 'hsf.uploads_open';
select set_config('request.jwt.claims', '{"role": "service_role"}', true);
select pg_temp.ok('both test accounts are verified as Care Net Consultants clients (migration 052)',
  hsf_verify_client(pg_temp.ctx('acc1')::uuid, 'client_register', 'FLOW-TEST-REGISTER-1') ->> 'status' = 'verified'
  and hsf_verify_client('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'client_register', 'FLOW-TEST-REGISTER-2') ->> 'status' = 'verified');
select set_config('request.jwt.claims', '', true);

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

select pg_temp.scan_clean('up_a', 'up_b', 'up_c');
select pg_temp.ok('the scan pass recorded A, B and C clean (migration 052)',
  (select count(*) = 3 from hsf_upload where scan_status = 'clean'
      and id in (pg_temp.ctx('up_a')::uuid, pg_temp.ctx('up_b')::uuid, pg_temp.ctx('up_c')::uuid)));

select pg_temp.ok('the transfer queue holds the three uploaded files, oldest first',
  (select count(*) = 3 from hsf_transfer_queue(10) q
    where q.id in (pg_temp.ctx('up_a')::uuid, pg_temp.ctx('up_b')::uuid, pg_temp.ctx('up_c')::uuid))
  and (select count(*) = 1 from hsf_transfer_queue(1)));

select pg_temp.refuses('staging deletion refused before a transfer',
  format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_a')), 'only a transferred');
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
  format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_a')), 'only a transferred');
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
select pg_temp.ok('a failed upload keeps its staged bytes until the cleanup queue removes them (contract 9.5)',
  exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
           where x ->> 'upload_id' = pg_temp.ctx('up_b') and x ->> 'reason' = 'failed'
             and x ->> 'storage_path' = (select storage_path from hsf_upload where id = pg_temp.ctx('up_b')::uuid)));
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''error'', null, null, null, ''Adapter timed out'')', pg_temp.ctx('up_c')));
select pg_temp.ok('an error outcome returns an upload to uploaded',
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
-- Contract 9.2: another account's File, a missing File and no user all read as
-- null (404 at the API, the same answer whether or not the File exists); a
-- missing or foreign item raises P0002, which the API also answers with 404.
select pg_temp.ok('hsf_file_detail is null for another account''s File',
  hsf_file_detail(pg_temp.ctx('u2')::uuid, pg_temp.ctx('file_c')::uuid) is null);
select pg_temp.ok('hsf_file_detail is null without a user and for a File that does not exist',
  hsf_file_detail(null, pg_temp.ctx('file_c')::uuid) is null
  and hsf_file_detail(pg_temp.ctx('u1')::uuid, gen_random_uuid()) is null);
select pg_temp.ok('hsf_set_item_status raises P0002 for a missing item and for another account''s item',
  pg_temp.sqlstate_of(format('select hsf_set_item_status(%L, %L, ''outstanding'', null)', pg_temp.ctx('u1'), gen_random_uuid())) = 'P0002'
  and pg_temp.sqlstate_of(format('select hsf_set_item_status(%L, %L, ''not_applicable'', ''Not carried on at this site'')',
                                 pg_temp.ctx('u2'), pg_temp.ctx('item_na'))) = 'P0002');

-- Staff (forge roles in app metadata) may read any File.
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
select pg_temp.ok('the withdrawal blocks the untransferred upload E and deletes nothing (contract 9.5)',
  (select transfer_blocked_reason = 'consent withdrawn' and status = 'uploaded' and storage_path is not null
     from hsf_upload where id = pg_temp.ctx('up_e')::uuid)
  and (select count(*) = 1 from hsf_upload where transfer_blocked_reason is not null)
  and (select (event_detail ->> 'blocked_uploads')::int = 1 from msp_audit
        where event_type = 'hsf_consent_withdrawn' and event_detail ->> 'kind' = 'document_storage'));
select pg_temp.ok('the client sees why E is not moving',
  (select x ->> 'transfer_blocked_reason' = 'consent withdrawn'
     from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx('u1')::uuid)) x where x ->> 'upload_id' = pg_temp.ctx('up_e')));
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
select pg_temp.ok('consent can be given again and is complete again, but E stays blocked until staff decide',
  pg_temp.r('r') ->> 'complete' = 'true'
  and not exists (select 1 from hsf_transfer_queue(100) q where q.id = pg_temp.ctx('up_e')::uuid)
  and not exists (select 1 from hsf_transfer_claim(100) q where q.id = pg_temp.ctx('up_e')::uuid)
  and (select transfer_blocked_reason = 'consent withdrawn' from hsf_upload where id = pg_temp.ctx('up_e')::uuid));

-- 8b. Claim, mismatch, cleanup, sweep and alerts (contract 9.5) ------------------------------------

do $$
declare
  r jsonb;
begin
  perform pg_temp.put('pct_before_f', (select coalesce(compliance_pct, 0)::text from hsf_file where id = pg_temp.ctx('file_c')::uuid));
  perform pg_temp.put('audit_before_f', (select count(*)::text from msp_audit
                                          where event_type = 'hsf_compliance_computed' and hsf_file_id = pg_temp.ctx('file_c')::uuid));
  perform pg_temp.put('sha_f', encode(extensions.digest('hsf flow test document f', 'sha256'), 'hex'));
  perform pg_temp.put('sha_g', encode(extensions.digest('hsf flow test document g', 'sha256'), 'hex'));
  -- Upload F: element HSF-A-05 of the CONSTR File, later a fingerprint mismatch.
  r := hsf_register_upload(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'file_id', pg_temp.ctx('file_c'), 'element_code', 'HSF-A-05', 'department_code', 'SHE',
         'original_name', 'Baseline risk assessment.pdf', 'mime_type', 'application/pdf',
         'size_bytes', 4096, 'sha256', pg_temp.ctx('sha_f')));
  perform pg_temp.put('up_f', r ->> 'upload_id');
  -- Upload G: a general document that goes to held, then is claimed in fixture mode.
  r := hsf_register_upload(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'department_code', 'OPS', 'original_name', 'Plant register.csv', 'mime_type', 'text/csv',
         'size_bytes', 64, 'sha256', pg_temp.ctx('sha_g')));
  perform pg_temp.put('up_g', r ->> 'upload_id');
  -- Upload H: registered, never completed.
  r := hsf_register_upload(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'department_code', 'OPS', 'original_name', 'Abandoned.pdf', 'mime_type', 'application/pdf',
         'size_bytes', 64, 'sha256', pg_temp.ctx('sha_g')));
  perform pg_temp.put('up_h', r ->> 'upload_id');
end $$;

select pg_temp.act('r', format('select hsf_mark_uploaded(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('up_f')));
select pg_temp.ok('an element upload recomputes and caches the compliance figure, and audits the change',
  pg_temp.r('r') ->> 'status' = 'uploaded'
  and (select compliance_pct = (hsf_compliance_figures(id) -> 'overall' ->> 'pct')::numeric
              and compliance_pct > pg_temp.ctx('pct_before_f')::numeric
         from hsf_file where id = pg_temp.ctx('file_c')::uuid)
  and (select count(*) = pg_temp.ctx('audit_before_f')::int + 1 from msp_audit
        where event_type = 'hsf_compliance_computed' and hsf_file_id = pg_temp.ctx('file_c')::uuid));
select pg_temp.act('r', format('select hsf_mark_uploaded(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('up_g')));
select pg_temp.scan_clean('up_f', 'up_g');

-- The claim runs as its own statement (pg_temp.act), so the checks see what it wrote.
create function pg_temp.claim_ids() returns jsonb language sql as $$
  select coalesce(jsonb_agg(q.id::text order by q.id::text), '[]'::jsonb) from hsf_transfer_claim(100) q $$;
create function pg_temp.ids(variadic p text[]) returns jsonb language sql as $$
  select jsonb_agg(x order by x) from unnest(p) x $$;
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('hold mode: the claim returns only uploaded rows (F and G), skips the blocked E, and moves nothing',
  pg_temp.r('claim') = pg_temp.ids(pg_temp.ctx('up_f'), pg_temp.ctx('up_g'))
  and (select bool_and(status = 'uploaded' and transfer_claimed_at is null) from hsf_upload
        where id in (pg_temp.ctx('up_f')::uuid, pg_temp.ctx('up_g')::uuid)));
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''hold'', ''held'', null, null, null, null)', pg_temp.ctx('up_g')));
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('hold mode: a held row is not claimed again',
  pg_temp.r('r') ->> 'status' = 'held' and pg_temp.r('claim') = pg_temp.ids(pg_temp.ctx('up_f')));

update msp_env_parameter set value = 'fixture' where key = 'hsf.mco_transfer_mode';
-- Everything in this transaction shares one now(), so give the two uploads
-- distinct ages: G is the older.
update hsf_upload set uploaded_at = now() - interval '2 minutes' where id = pg_temp.ctx('up_g')::uuid;
update hsf_upload set uploaded_at = now() - interval '1 minute' where id = pg_temp.ctx('up_f')::uuid;
select pg_temp.ok('hsf_transfer_mode reads fixture after the parameter changes', hsf_transfer_mode() = 'fixture');
select pg_temp.act('claim', 'select coalesce(jsonb_agg(q.id::text), ''[]''::jsonb) from hsf_transfer_claim(100) q');
select pg_temp.ok('fixture mode: the claim takes uploaded and held rows (G then F, oldest first) and marks them transferring',
  pg_temp.r('claim') = jsonb_build_array(pg_temp.ctx('up_g'), pg_temp.ctx('up_f'))
  and (select bool_and(status = 'transferring' and transfer_claimed_at is not null) from hsf_upload
        where id in (pg_temp.ctx('up_f')::uuid, pg_temp.ctx('up_g')::uuid))
  and not exists (select 1 from hsf_upload where id = pg_temp.ctx('up_e')::uuid and status = 'transferring'));
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('fixture mode: rows another worker claimed in the last 30 minutes are skipped',
  pg_temp.r('claim') = '[]'::jsonb);
update hsf_upload set transfer_claimed_at = now() - interval '31 minutes' where id = pg_temp.ctx('up_g')::uuid;
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('fixture mode: a claim older than 30 minutes is taken again',
  pg_temp.r('claim') = pg_temp.ids(pg_temp.ctx('up_g'))
  and (select transfer_claimed_at > now() - interval '1 minute' from hsf_upload where id = pg_temp.ctx('up_g')::uuid));
select pg_temp.ok('the claim takes row locks with skip locked, so parallel workers never share a row',
  pg_get_functiondef('hsf_transfer_claim(int)'::regprocedure) ~* 'for update of u skip locked');

select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''hash_mismatch'', %L, null, null, %L)',
                               pg_temp.ctx('up_f'), pg_temp.ctx('sha_g'), 'The staged file does not match the browser fingerprint.'));
select pg_temp.ok('a mismatch on an element upload fails the upload and revokes its evidence row',
  pg_temp.r('r') ->> 'status' = 'failed'
  and (select status = 'failed' and transfer_claimed_at is null from hsf_upload where id = pg_temp.ctx('up_f')::uuid)
  and (select count(*) = 1 from hsf_evidence where upload_id = pg_temp.ctx('up_f')::uuid and revoked_at is not null)
  and not exists (select 1 from hsf_evidence where upload_id = pg_temp.ctx('up_f')::uuid and revoked_at is null));
select pg_temp.ok('the File item returns to outstanding and the compliance figure returns to what it was',
  (select fi.status = 'outstanding' from hsf_upload u join hsf_file_item fi on fi.id = u.file_item_id where u.id = pg_temp.ctx('up_f')::uuid)
  and (select compliance_pct = pg_temp.ctx('pct_before_f')::numeric from hsf_file where id = pg_temp.ctx('file_c')::uuid)
  and (hsf_compliance_figures(pg_temp.ctx('file_c')::uuid) -> 'overall' ->> 'evidenced')::int = 1);

-- A second document on HSF-A-06, which already holds evidence version 1 from A.
do $$
declare
  r jsonb;
begin
  r := hsf_register_upload(pg_temp.ctx('u1')::uuid, jsonb_build_object(
         'file_id', pg_temp.ctx('file_c'), 'element_code', 'HSF-A-06', 'department_code', 'SHE',
         'original_name', 'Client spec v3.pdf', 'mime_type', 'application/pdf',
         'size_bytes', 2048, 'sha256', pg_temp.ctx('sha_f')));
  perform pg_temp.put('up_i', r ->> 'upload_id');
end $$;
select pg_temp.act('r', format('select hsf_mark_uploaded(%L, %L)', pg_temp.ctx('u1'), pg_temp.ctx('up_i')));
select pg_temp.ok('a second complete on one item appends version 2, superseding version 1',
  exists (select 1 from hsf_evidence e2 join hsf_evidence e1 on e1.id = e2.supersedes_id
           where e2.upload_id = pg_temp.ctx('up_i')::uuid and e2.version = 2
             and e1.upload_id = pg_temp.ctx('up_a')::uuid and e1.version = 1));
select pg_temp.ok('completes on one item are serialised: the item row is locked before the version is chosen',
  (select position('from hsf_file_item where id = v_up.file_item_id for update' in d) between 1 and position('max(e.version)' in d)
     from pg_get_functiondef('hsf_mark_uploaded(uuid, uuid)'::regprocedure) d));
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''hash_mismatch'', %L, null, null, null)',
                               pg_temp.ctx('up_i'), pg_temp.ctx('sha_g')));
select pg_temp.ok('a mismatch on version 2 leaves the item uploaded on the unrevoked version 1',
  (select fi.status = 'uploaded' from hsf_upload u join hsf_file_item fi on fi.id = u.file_item_id where u.id = pg_temp.ctx('up_i')::uuid)
  and (select revoked_at is not null from hsf_evidence where upload_id = pg_temp.ctx('up_i')::uuid)
  and (select revoked_at is null from hsf_evidence where upload_id = pg_temp.ctx('up_a')::uuid));

select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''error'', null, null, null, ''Adapter timed out'')', pg_temp.ctx('up_g')));
select pg_temp.ok('an error on a transferring upload returns it to uploaded',
  pg_temp.r('r') ->> 'status' = 'uploaded'
  and (select status = 'uploaded' and transfer_claimed_at is null from hsf_upload where id = pg_temp.ctx('up_g')::uuid));
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('the returned upload is claimed again', pg_temp.r('claim') = pg_temp.ids(pg_temp.ctx('up_g')));
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, %L, %L, null)',
                               pg_temp.ctx('up_g'), pg_temp.ctx('sha_g'), 'FIXTURE-' || pg_temp.ctx('up_g'), pg_temp.ctx('sha_g')));
select pg_temp.ok('a received transferring upload is transferred',
  pg_temp.r('r') ->> 'status' = 'transferred');

select pg_temp.ok('the cleanup queue lists transferred, failed and rejected uploads that still hold bytes, with the reason',
  (select jsonb_object_agg(x ->> 'upload_id', x ->> 'reason') from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x)
  = jsonb_build_object(pg_temp.ctx('up_b'), 'failed', pg_temp.ctx('up_c'), 'failed', pg_temp.ctx('up_d'), 'rejected',
                       pg_temp.ctx('up_f'), 'failed', pg_temp.ctx('up_i'), 'failed', pg_temp.ctx('up_g'), 'transferred')
  and not exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x where x ->> 'storage_path' is null));

-- A blocked upload that ends failed keeps its bytes for the decision (contract 9.5).
update hsf_upload set status = 'failed', reject_reason = 'Flow test, rolled back.' where id = pg_temp.ctx('up_e')::uuid;
select pg_temp.ok('the cleanup queue leaves out an upload blocked by a consent withdrawal',
  not exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x where x ->> 'upload_id' = pg_temp.ctx('up_e')));
update hsf_upload set status = 'uploaded', reject_reason = null where id = pg_temp.ctx('up_e')::uuid;

select pg_temp.act('r', format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_b')));
select pg_temp.ok('staging deletion of a failed upload keeps it failed and clears the path',
  pg_temp.r('r') ->> 'status' = 'failed'
  and (select status = 'failed' and storage_path is null and staging_deleted_at is not null
         from hsf_upload where id = pg_temp.ctx('up_b')::uuid));
select pg_temp.refuses('a failed upload cannot be removed from staging twice',
  format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_b')), 'already been removed');
select pg_temp.act('r', format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_d')));
select pg_temp.ok('staging deletion of a rejected upload keeps it rejected',
  pg_temp.r('r') ->> 'status' = 'rejected'
  and (select status = 'rejected' and storage_path is null from hsf_upload where id = pg_temp.ctx('up_d')::uuid));
select pg_temp.act('r', format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_f')));
select pg_temp.ok('the revoked evidence row of a failed element upload records the staging deletion too',
  exists (select 1 from hsf_evidence where upload_id = pg_temp.ctx('up_f')::uuid and revoked_at is not null
            and storage_path is null and staging_deleted_at is not null));
select pg_temp.act('r', format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_g')));
select pg_temp.ok('staging deletion of a transferred upload moves it to staging_deleted; the queue shrinks',
  pg_temp.r('r') ->> 'status' = 'staging_deleted'
  and (select jsonb_array_length(hsf_transfer_cleanup_queue(100)) = 2));

select pg_temp.ok('the sweep leaves a fresh registration alone', hsf_sweep_stale_uploads(24) = 0
  and (select status = 'awaiting_upload' from hsf_upload where id = pg_temp.ctx('up_h')::uuid));
update hsf_upload set created_at = now() - interval '25 hours' where id = pg_temp.ctx('up_h')::uuid;
select pg_temp.act('r', 'select to_jsonb(hsf_sweep_stale_uploads())');
select pg_temp.ok('the sweep fails a registration older than 24 hours with the contract reason',
  pg_temp.r('r') = '1'::jsonb
  and (select status = 'failed' and reject_reason = 'The upload was not completed.' and storage_path is not null
         from hsf_upload where id = pg_temp.ctx('up_h')::uuid)
  and exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
               where x ->> 'upload_id' = pg_temp.ctx('up_h') and x ->> 'reason' = 'failed')
  and exists (select 1 from msp_audit where event_type = 'hsf_uploads_swept' and (event_detail ->> 'failed')::int = 1));
select pg_temp.refuses('the sweep refuses an age below one hour',
  'select hsf_sweep_stale_uploads(0)', 'between 1 and 8760');

update hsf_upload set uploaded_at = now() - interval '15 days' where id = pg_temp.ctx('up_e')::uuid;
select pg_temp.ok('staging alerts list the upload held in staging for longer than hsf.staging_alert_days',
  (select array_agg(x ->> 'upload_id') = array[pg_temp.ctx('up_e')]
          and bool_and((x ->> 'days_in_staging')::int >= 14 and x ->> 'transfer_blocked_reason' = 'consent withdrawn'
                       and not (x ? 'original_name'))
     from jsonb_array_elements(hsf_staging_alerts_list()) x));
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "33333333-3333-4333-8333-333333333333", "role": "authenticated", "app_metadata": {"msp_roles": ["forge_omp"]}}', true);
select count(*) as alerts_staff, bool_and(upload_id::text = pg_temp.ctx('up_e')) as alerts_staff_e from hsf_staging_alerts \gset
select set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select count(*) as alerts_client from hsf_staging_alerts \gset
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('staff read the alert through hsf_staging_alerts; a client reads none',
  :'alerts_staff' = '1' and :'alerts_staff_e' = 't' and :'alerts_client' = '0');
set local role anon;
select pg_temp.refuses('anon cannot read the staging alerts', 'select count(*) from hsf_staging_alerts', 'permission denied');
reset role;
update msp_env_parameter set value = 'hold' where key = 'hsf.mco_transfer_mode';

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
select pg_temp.ok('every seeded hold names the repeal (HSF-7) or the notice number conflict (HSF-9)',
  not exists (select 1 from msp_instrument_currency_hold h
               where not (h.reason ilike '%06/09/2026%' or h.reason ilike '%HSF-9%')));
select pg_temp.ok('the Asbestos Abatement Regulations, 2020 are held, citing GN R.2092 against GN R.11435 (contract 9.4)',
  exists (select 1 from msp_instrument_currency_hold h join msp_legal_instrument li on li.id = h.instrument_id
           where li.short_name = 'Asbestos Abatement Regulations, 2020' and li.status = 'verified'
             and h.reason like '%GN R.2092%' and h.reason like '%GN R.11435%' and h.reason like '%HSF-9%'));
select pg_temp.ok('the held Asbestos Abatement Regulations, 2020 leave the register, every industry profile and the kernel reads',
  exists (select 1 from msp_industry_instrument ii join msp_legal_instrument li on li.id = ii.instrument_id
           where li.short_name = 'Asbestos Abatement Regulations, 2020')
  and not exists (select 1 from kernel_citable_instrument where short_name = 'Asbestos Abatement Regulations, 2020')
  and not exists (select 1 from msp_public_instrument_register where short_name = 'Asbestos Abatement Regulations, 2020')
  and not exists (select 1 from msp_public_industry_profile p, json_array_elements(p.instruments) x
                   where x ->> 'name' = 'Asbestos Abatement Regulations, 2020')
  and kernel_api_instruments()::text not like '%"Asbestos Abatement Regulations, 2020"%'
  and not exists (select 1 from jsonb_array_elements(kernel_api_search('asbestos abatement') -> 'data') x where x ->> 'kind' = 'instrument'));
select pg_temp.ok('the framework statistics count only instruments that are not held',
  (select instruments from msp_public_framework_stats) = (select count(*) from kernel_citable_instrument)
  and (select count(*) from msp_public_instrument_register) = (select count(*) from kernel_citable_instrument));

-- Contract 9.3: what a File element may cite. The seed links every element with
-- the provision 'awaiting verification' and held instruments carry scope medical,
-- so nothing is citable for a File until the Phase 2 re verification.
select pg_temp.ok('until the Phase 2 re verification no element cites anything (every basis awaits verification)',
  not exists (select 1 from hsf_public_element_library where json_array_length(citable) > 0)
  and not exists (select 1 from hsf_element e where jsonb_array_length(hsf_element_citable(e.id)) > 0));
select pg_temp.put('el_a06', (select id::text from hsf_element where code = 'HSF-A-06'));
select pg_temp.put('stats_before', (select instruments::text from msp_public_framework_stats));
update hsf_element_instrument set provision = 'Check provision (rolled back)'
 where element_id = pg_temp.ctx('el_a06')::uuid
   and instrument_id in (select id from msp_legal_instrument where short_name = 'Construction Regulations, 2014' and status = 'verified');
select pg_temp.ok('a pinned provision alone is not enough: an instrument of scope medical stays awaiting',
  hsf_element_citable(pg_temp.ctx('el_a06')::uuid) = '[]'::jsonb
  and (select awaiting::jsonb ? 'Construction Regulations, 2014' from hsf_public_element_library where code = 'HSF-A-06'));
update msp_legal_instrument set scope = 'both' where short_name = 'Construction Regulations, 2014' and status = 'verified';
select pg_temp.ok('verified, not held, scope both and a pinned provision: citable in the library, the File detail and the kernel API',
  hsf_element_citable(pg_temp.ctx('el_a06')::uuid) = '["Construction Regulations, 2014"]'::jsonb
  and (select citable::jsonb ? 'Construction Regulations, 2014' and not (awaiting::jsonb ? 'Construction Regulations, 2014')
         from hsf_public_element_library where code = 'HSF-A-06')
  and exists (select 1 from jsonb_array_elements(hsf_file_detail(pg_temp.ctx('u1')::uuid, pg_temp.ctx('file_c')::uuid) -> 'sections') sec,
                            jsonb_array_elements(sec -> 'items') i
               where i ->> 'element_code' = 'HSF-A-06' and i -> 'citable' ? 'Construction Regulations, 2014'
                 and not (i -> 'awaiting' ? 'Construction Regulations, 2014'))
  and exists (select 1 from jsonb_array_elements(kernel_api_elements('CONSTR') -> 'data') x
               where x ->> 'code' = 'HSF-A-06' and x -> 'citable' ? 'Construction Regulations, 2014'));
select pg_temp.ok('the other elements that name it still await verification (their provisions are not pinned)',
  not exists (select 1 from hsf_public_element_library where code <> 'HSF-A-06' and json_array_length(citable) > 0));

-- A hold removes a verified instrument from citation everywhere, at once.
insert into msp_instrument_currency_hold (instrument_id, reason, held_by)
select id, 'Flow test hold, rolled back.', 'hsf_flow_checks' from msp_legal_instrument
 where short_name = 'Construction Regulations, 2014' and status = 'verified';
select pg_temp.ok('a held instrument leaves kernel_citable_instrument',
  not exists (select 1 from kernel_citable_instrument where short_name = 'Construction Regulations, 2014'));
select pg_temp.ok('a held instrument moves from citable to awaiting in the element library and the File detail',
  (select not (citable::jsonb ? 'Construction Regulations, 2014') and awaiting::jsonb ? 'Construction Regulations, 2014'
     from hsf_public_element_library where code = 'HSF-A-06')
  and hsf_element_citable(pg_temp.ctx('el_a06')::uuid) = '[]'::jsonb
  and exists (select 1 from jsonb_array_elements(hsf_file_detail(pg_temp.ctx('u1')::uuid, pg_temp.ctx('file_c')::uuid) -> 'sections') sec,
                            jsonb_array_elements(sec -> 'items') i
               where i ->> 'element_code' = 'HSF-A-06' and i -> 'awaiting' ? 'Construction Regulations, 2014'
                 and not (i -> 'citable' ? 'Construction Regulations, 2014')));
select pg_temp.ok('a held instrument leaves the public register, the industry profile and the framework statistics',
  not exists (select 1 from msp_public_instrument_register where short_name = 'Construction Regulations, 2014')
  and not exists (select 1 from msp_public_industry_profile p, json_array_elements(p.instruments) x
                   where p.code = 'CONSTR' and x ->> 'name' = 'Construction Regulations, 2014')
  and (select instruments = pg_temp.ctx('stats_before')::bigint - 1 from msp_public_framework_stats));
set local role anon;
select pg_temp.ok('anon sees the hold too: the register and the CONSTR profile leave it out',
  not exists (select 1 from msp_public_instrument_register where short_name = 'Construction Regulations, 2014')
  and not exists (select 1 from msp_public_industry_profile p, json_array_elements(p.instruments) x
                   where p.code = 'CONSTR' and x ->> 'name' = 'Construction Regulations, 2014'));
reset role;
select pg_temp.ok('a held instrument is not a basis in the kernel API',
  not (kernel_api_instruments('CONSTR')::text like '%"short_name": "Construction Regulations, 2014"%')
  and not exists (select 1 from jsonb_array_elements(kernel_api_elements('CONSTR') -> 'data') x
                   where x -> 'citable' ? 'Construction Regulations, 2014')
  and not ((kernel_api_industry('CONSTR') -> 'data' -> 'instruments') @> '[{"short_name":"Construction Regulations, 2014"}]')
  and not exists (select 1 from jsonb_array_elements(kernel_api_search('Construction Regulations') -> 'data') x
                   where x ->> 'kind' = 'instrument' and x ->> 'name' = 'Construction Regulations, 2014'));
delete from msp_instrument_currency_hold where held_by = 'hsf_flow_checks';
select pg_temp.ok('with the hold lifted the register, the profile and the element cite it again',
  exists (select 1 from msp_public_instrument_register where short_name = 'Construction Regulations, 2014')
  and exists (select 1 from msp_public_industry_profile p, json_array_elements(p.instruments) x
               where p.code = 'CONSTR' and x ->> 'name' = 'Construction Regulations, 2014')
  and hsf_element_citable(pg_temp.ctx('el_a06')::uuid) ? 'Construction Regulations, 2014');
update hsf_element_instrument set provision = 'awaiting verification'
 where element_id = pg_temp.ctx('el_a06')::uuid and provision = 'Check provision (rolled back)';
select pg_temp.ok('a provision back at awaiting verification is not citable, while the register keeps the instrument',
  hsf_element_citable(pg_temp.ctx('el_a06')::uuid) = '[]'::jsonb
  and exists (select 1 from kernel_citable_instrument where short_name = 'Construction Regulations, 2014'));
update msp_legal_instrument set scope = 'medical' where short_name = 'Construction Regulations, 2014' and status = 'verified';

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
select count(*) as anon_triggers, count(*) filter (where code ~ ' (and|or) ') as anon_compound,
       bool_and(description <> '') as anon_described from hsf_public_trigger \gset
select count(*) as anon_subs, count(*) filter (where selectable) as anon_subs_selectable,
       count(*) filter (where industry_code = 'CONSTR') as anon_subs_constr from hsf_public_subindustry \gset
reset role;
select pg_temp.ok('anon reads the builder views: the 44 activity triggers (no compound rows) and every subindustry with its industry (contract 9.7)',
  :'anon_triggers' = '44' and :'anon_compound' = '0' and :'anon_described' = 't'
  and :'anon_subs'::bigint = (select count(*) from msp_subindustry)
  and :'anon_subs_selectable'::bigint = (select count(*) from msp_subindustry where selectable)
  and :'anon_subs_constr'::bigint = (select count(*) from msp_subindustry s join msp_industry i on i.id = s.industry_id where i.code = 'CONSTR')
  and :'anon_subs_constr'::bigint > 0);
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

-- 12. Daily File limit and references past 999 (contract 9.6) ---------------------------------------

select pg_temp.put('files_today_acc1', (select count(*)::text from hsf_file
                                          where client_account_id = pg_temp.ctx('acc1')::uuid and created_at >= current_date));
update msp_env_parameter set value = pg_temp.ctx('files_today_acc1') where key = 'hsf.files_per_account_per_day';
select pg_temp.refuses('generate refused once the account has built hsf.files_per_account_per_day Files today',
  format('select hsf_generate_file(%L, %L::jsonb)', pg_temp.ctx('u1'),
         '{"industry_code":"OFFICE","triggers":[],"scope":{"sites":[{"name":"Limit test"}]}}'), 'daily limit');
select pg_temp.ok('the refusal wrote no File',
  (select count(*) = pg_temp.ctx('files_today_acc1')::int from hsf_file where client_account_id = pg_temp.ctx('acc1')::uuid));
update msp_env_parameter set value = '20' where key = 'hsf.files_per_account_per_day';
select pg_temp.ok('another account is not held back by the first account''s limit',
  (hsf_generate_file(pg_temp.ctx('u2')::uuid,
     '{"industry_code":"OFFICE","triggers":[],"scope":{"sites":[{"name":"Second office"}]}}'::jsonb) ->> 'file_id') is not null);

-- The 999th File of the day is followed by the 1000th, never by a repeat of 100.
insert into hsf_file (client_account_id, industry_id, regime, scope, reference)
select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', i.id, 'OHSA', '{"sites":[{"name":"Reference test"}]}'::jsonb,
       'CNC-HSF-' || to_char(current_date, 'YYYY-MMDD') || '-999'
  from msp_industry i where i.code = 'OFFICE';
select pg_temp.ok('after -999 the next reference is -1000',
  hsf_next_reference() = 'CNC-HSF-' || to_char(current_date, 'YYYY-MMDD') || '-1000');
select pg_temp.act('r', format('select hsf_generate_file(%L, %L::jsonb)', pg_temp.ctx('u2'),
                               '{"industry_code":"OFFICE","triggers":[],"scope":{"sites":[{"name":"Reference test two"}]}}'));
select pg_temp.ok('generation past 999 succeeds with -1000, and the next is -1001',
  pg_temp.r('r') ->> 'reference' = 'CNC-HSF-' || to_char(current_date, 'YYYY-MMDD') || '-1000'
  and hsf_next_reference() = 'CNC-HSF-' || to_char(current_date, 'YYYY-MMDD') || '-1001');

-- 13. Portal summary (contract 9.8) ---------------------------------------------------------------

-- The sign on gave account 1 an assessment token; an intake consumes it, which
-- makes the engagement one of the account's Plans. Fictitious rows only.
insert into msp_client (id, registered_name) values ('77777777-7777-4777-8777-777777777777', 'Flow Test Civils (Pty) Ltd');
insert into msp_engagement (id, client_id, reference, status, industry_id)
select '77777777-eeee-4eee-8eee-eeeeeeeeeeee', '77777777-7777-4777-8777-777777777777', 'FLOW-TEST-MSP-1', 'drafting', i.id
  from msp_industry i where i.code = 'CONSTR';
insert into msp_intake (id, engagement_id, docuseal_submission_id, raw_payload, schema_version, validation_status)
values ('77777777-dddd-4ddd-8ddd-dddddddddddd', '77777777-eeee-4eee-8eee-eeeeeeeeeeee', 'flow-test', '{}'::jsonb, 'flow-test', 'valid');
update msp_form_access set used_by_intake = '77777777-dddd-4ddd-8ddd-dddddddddddd'
 where client_account_id = pg_temp.ctx('acc1')::uuid and used_by_intake is null;
insert into msp_quote (quote_reference, company_name, contact_name, contact_email, industry_code, employee_count,
                       job_category_count, price_zar, price_status, package_code) values
  ('FLOW-TEST-QTE-1', 'Flow Test Civils (Pty) Ltd', 'Flow Tester', 'Flow.Client@example.invalid', 'CONSTR', 64, 4, 4250.00, 'indicative', 'SIGNED_PLAN'),
  ('FLOW-TEST-QTE-2', 'Other Test Company (Pty) Ltd', 'Other Tester', 'other.client@example.invalid', 'OFFICE', 10, 1, 1000.00, 'indicative', 'SIGNED_PLAN');
insert into hsf_signoff (file_id, revision, kind) values (pg_temp.ctx('file_c')::uuid, 1, 'safety_content');

select pg_temp.put('tokens_before', (select count(*)::text from msp_form_access));
select pg_temp.act('ps', format('select hsf_portal_summary(%L)', pg_temp.ctx('u1')));
select pg_temp.ok('portal summary: the four keys, and the account with id, company, kind and approval time',
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.r('ps')) k) = array['account','files','plans','quotes']
  and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.r('ps') -> 'account') k)
      = array['account_kind','approved_at','client_account_id','company_name']
  and pg_temp.r('ps') -> 'account' ->> 'client_account_id' = pg_temp.ctx('acc1')
  and pg_temp.r('ps') -> 'account' ->> 'account_kind' = 'approved_client'
  and pg_temp.r('ps') -> 'account' ->> 'approved_at' is not null);
select pg_temp.ok('portal summary: the Plan from the engagement whose intake used the account''s token',
  jsonb_array_length(pg_temp.r('ps') -> 'plans') = 1
  and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.r('ps') -> 'plans' -> 0) k)
      = array['created_at','engagement_id','industry_code','reference','revision','status']
  and pg_temp.r('ps') -> 'plans' -> 0 ->> 'reference' = 'FLOW-TEST-MSP-1'
  and pg_temp.r('ps') -> 'plans' -> 0 ->> 'industry_code' = 'CONSTR'
  and (pg_temp.r('ps') -> 'plans' -> 0 ->> 'revision')::int = 1);
select pg_temp.ok('portal summary: quotes by the account''s contact email only',
  jsonb_array_length(pg_temp.r('ps') -> 'quotes') = 1
  and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.r('ps') -> 'quotes' -> 0) k)
      = array['created_at','package_code','price_status','price_zar','quote_reference','valid_until']
  and pg_temp.r('ps') -> 'quotes' -> 0 ->> 'quote_reference' = 'FLOW-TEST-QTE-1'
  and (pg_temp.r('ps') -> 'quotes' -> 0 ->> 'price_zar')::numeric = 4250);
select pg_temp.ok('portal summary: the account''s Files with compliance and the sign offs of the current revision',
  jsonb_array_length(pg_temp.r('ps') -> 'files') = (select count(*) from hsf_file where client_account_id = pg_temp.ctx('acc1')::uuid)
  and exists (select 1 from jsonb_array_elements(pg_temp.r('ps') -> 'files') f
               where f ->> 'file_id' = pg_temp.ctx('file_c') and f ->> 'industry_code' = 'CONSTR'
                 and f ->> 'status' = 'draft' and (f ->> 'revision')::int = 1 and (f ->> 'compliance_pct')::numeric > 0
                 and f -> 'signoffs' = '[{"kind": "safety_content", "decision": null, "decided_at": null}]'::jsonb)
  and not exists (select 1 from jsonb_array_elements(pg_temp.r('ps') -> 'files') f
                   where (select array_agg(k order by k) from jsonb_object_keys(f) k)
                         <> array['compliance_pct','file_id','industry_code','reference','revision','signoffs','status']));
select pg_temp.ok('portal summary mints no token, returns none, and is read only',
  (select count(*) = pg_temp.ctx('tokens_before')::int from msp_form_access)
  and not exists (select 1 from msp_form_access fa where pg_temp.r('ps')::text like '%' || fa.token || '%')
  and (select provolatile = 's' from pg_proc where oid = 'hsf_portal_summary(uuid)'::regprocedure));
select pg_temp.ok('portal summary for a person with no company account is empty',
  hsf_portal_summary(pg_temp.ctx('u3')::uuid)
    = '{"account": null, "plans": [], "quotes": [], "files": []}'::jsonb
  and hsf_portal_summary(null) = '{"account": null, "plans": [], "quotes": [], "files": []}'::jsonb);
select pg_temp.ok('portal summary shows another account nothing of account 1',
  (select not (x::text like '%FLOW-TEST-MSP-1%') and not (x::text like '%FLOW-TEST-QTE-1%')
          and not (x::text like '%' || pg_temp.ctx('file_c') || '%')
     from hsf_portal_summary(pg_temp.ctx('u2')::uuid) x));

\echo 'All HSF flow checks passed. Rolling back the test data.'
rollback;
