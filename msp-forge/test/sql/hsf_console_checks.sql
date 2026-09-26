-- CNC MSP FORGE | HSF-CON-01 console and metadata checks | local test harness only.
-- Proves migration 054 (build contract section 11, Amendment 3, items 11.1 to
-- 11.5) against a replayed database: a clean scan carries the cleaned copy's
-- fingerprint and the transfer compares with it, a document in transfer is
-- never deletable, five PIN attempts an hour per account, the register check
-- age rule on its boundary days, one set of release rules for the gate and the
-- readiness check, the signatory expiry alerts and every staff console
-- function, including that a person without a staff role is refused by each.
-- Also the review round fixes: the scan hold and the announced write back
-- (a deleted document is never written back into staging), a blocked transfer
-- that stopped part way, attempts counted over every request open in the hour,
-- no staff email in the client readable hsf_signoff, and a fresh register check
-- on frozen credentials.
-- Never applied to Supabase. Everything runs in one transaction that is rolled
-- back, so the fictitious people, accounts, Files and uploads never persist.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_console_checks.sql
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
-- The error message a statement raises, or null when it succeeds.
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end $$;
-- Registers and completes one general upload for a user, fingerprinted with
-- p_sha; keeps its id under p_k.
create function pg_temp.upload(p_k text, p_user text, p_sha text) returns void language plpgsql as $$
declare
  v_id text;
begin
  v_id := hsf_register_upload(pg_temp.ctx(p_user)::uuid, jsonb_build_object(
            'department_code', 'SHE', 'original_name', 'Console test ' || p_k || '.pdf',
            'mime_type', 'application/pdf', 'size_bytes', 2048, 'sha256', p_sha)) ->> 'upload_id';
  perform hsf_mark_uploaded(pg_temp.ctx(p_user)::uuid, v_id::uuid);
  perform pg_temp.put(p_k, v_id);
end $$;
-- The scan pass's clean record for an upload: its cleaned copy is fingerprinted
-- p_sha_clean and nothing is listed as removed.
create function pg_temp.clean(p_k text, p_sha_clean text) returns jsonb language sql as $$
  select hsf_scan_record_clean(pg_temp.ctx(p_k)::uuid, 'ClamAV test 1.0', '[]'::jsonb, p_sha_clean, '[]'::jsonb, 1900) $$;
create function pg_temp.claim_ids() returns jsonb language sql as $$
  select coalesce(jsonb_agg(q.id::text order by q.id::text), '[]'::jsonb) from hsf_transfer_claim(100) q $$;
create function pg_temp.ids(variadic p text[]) returns jsonb language sql as $$
  select jsonb_agg(x order by x) from unnest(p) x $$;
create function pg_temp.status_of(p_k text) returns text language sql as $$
  select status from hsf_upload where id = pg_temp.ctx(p_k)::uuid $$;
create function pg_temp.mine(p_user text, p_k text) returns jsonb language sql as $$
  select x from jsonb_array_elements(hsf_my_uploads(pg_temp.ctx(p_user)::uuid)) x where x ->> 'upload_id' = pg_temp.ctx(p_k) $$;
create function pg_temp.release_sql(p_file text, p_revision int) returns text language sql as $$
  select format('insert into hsf_release (file_id, revision, pdf_path, evidence_index_path) values (%L, %s, ''x.pdf'', ''x.csv'')',
                pg_temp.ctx(p_file), p_revision) $$;
-- One staff console sign off, recorded as the forge_safety_reviewer.
create function pg_temp.signoff(p_file text, p_revision int, p_kind text, p_decision text, p_extra jsonb) returns jsonb language sql as $$
  select hsf_staff_signoff_record(pg_temp.ctx('s1')::uuid,
           jsonb_build_object('file_id', pg_temp.ctx(p_file), 'revision', p_revision, 'kind', p_kind,
                              'decision', p_decision, 'decided_at', pg_temp.ctx('dec')) || coalesce(p_extra, '{}'::jsonb)) $$;
-- A signatory saved through the console by the forge_safety_reviewer; the
-- register was checked p_check_age days before the decision day.
create function pg_temp.signatory(p_k text, p_category text, p_check_age int) returns void language plpgsql as $$
declare
  v_day date := pg_temp.ctx('day')::date;
begin
  perform pg_temp.put(p_k, hsf_staff_signatory_save(pg_temp.ctx('s1')::uuid, jsonb_build_object(
    'full_name', 'Practitioner ' || p_k, 'registration_body', 'SAIOSH', 'category', p_category,
    'registration_number', 'FIXTURE-CON-' || upper(p_k), 'registration_expires_on', (v_day + 365)::text,
    'register_checked_on', (v_day - p_check_age)::text, 'register_proof_ref', 'fixture/register-' || p_k || '.pdf',
    'appointment_letter_ref', 'fixture/appointment-' || p_k || '.pdf', 'appointment_letter_date', (v_day - 60)::text,
    'engagement_letter_ref', 'fixture/engagement-' || p_k || '.pdf', 'engagement_letter_date', (v_day - 60)::text)) ->> 'id');
end $$;

-- The role checks below run as authenticated, which still reads the context.
grant select, insert, update on ctx to authenticated;

-- Fictitious people: a client with an approved company account (not enough on
-- its own), a forge_safety_reviewer and a forge_admin, a person with only a
-- non HSF forge role, and a person with nothing. The fingerprints are SHA 256
-- values of fixed test strings, never real documents.
insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data) values
  ('c1111111-1111-4111-8111-111111111111', 'console.client@example.invalid', now(), null),
  ('c2222222-2222-4222-8222-222222222222', 'console.reviewer@example.invalid', now(), '{"msp_roles":["forge_safety_reviewer"]}'),
  ('c3333333-3333-4333-8333-333333333333', 'console.admin@example.invalid', now(), '{"msp_roles":["forge_admin"]}'),
  ('c4444444-4444-4444-8444-444444444444', 'console.agent@example.invalid', now(), '{"msp_roles":["forge_agent"]}'),
  ('c5555555-5555-4555-8555-555555555555', 'console.nobody@example.invalid', now(), null);
insert into msp_client_account (id, company_name, contact_name, contact_email, account_kind, auth_user_id) values
  ('cccc1111-cccc-4ccc-8ccc-cccccccccccc', 'Console Test Works (Pty) Ltd', 'Console Tester', 'console.client@example.invalid',
   'approved_client', 'c1111111-1111-4111-8111-111111111111');

select pg_temp.put('c1', 'c1111111-1111-4111-8111-111111111111');
select pg_temp.put('s1', 'c2222222-2222-4222-8222-222222222222');
select pg_temp.put('s2', 'c3333333-3333-4333-8333-333333333333');
select pg_temp.put('n1', 'c4444444-4444-4444-8444-444444444444');
select pg_temp.put('n2', 'c5555555-5555-4555-8555-555555555555');
select pg_temp.put('acc1', 'cccc1111-cccc-4ccc-8ccc-cccccccccccc');
select pg_temp.put('s1_email', 'console.reviewer@example.invalid');
select pg_temp.put('s2_email', 'console.admin@example.invalid');
do $$
declare
  k text;
begin
  foreach k in array array['a','b','c','d','h','k','l','p','q','r','s','t','x'] loop
    perform pg_temp.put('sha_' || k, encode(extensions.digest('hsf console test document ' || k, 'sha256'), 'hex'));
    perform pg_temp.put('clean_' || k, encode(extensions.digest('hsf console test cleaned copy ' || k, 'sha256'), 'hex'));
  end loop;
end $$;

-- Two general industry (manufacturing) Files. F1 carries no items, so only
-- the sign off rules decide its release; F2 carries HSF-A-01, whose instrument
-- is not yet citable for a File, so every rule of the gate is unmet there.
insert into hsf_file (id, client_account_id, industry_id, regime, scope, revision)
select 'cf000001-0000-4000-8000-000000000001', 'cccc1111-cccc-4ccc-8ccc-cccccccccccc', id, 'OHSA', '{}'::jsonb, 4
  from msp_industry where code = 'MANU';
insert into hsf_file (id, client_account_id, industry_id, regime, scope)
select 'cf000002-0000-4000-8000-000000000002', 'cccc1111-cccc-4ccc-8ccc-cccccccccccc', id, 'OHSA', '{}'::jsonb
  from msp_industry where code = 'MANU';
insert into hsf_file_item (file_id, element_id)
select 'cf000002-0000-4000-8000-000000000002', id from hsf_element where code = 'HSF-A-01';
select pg_temp.put('f1', 'cf000001-0000-4000-8000-000000000001');
select pg_temp.put('f2', 'cf000002-0000-4000-8000-000000000002');

-- Every sign off below is decided an hour ago; its decision day is the South
-- African calendar day of that moment.
select pg_temp.put('dec', (now() - interval '1 hour')::text);
select pg_temp.put('day', ((now() - interval '1 hour') at time zone 'Africa/Johannesburg')::date::text);
select pg_temp.put('today', (now() at time zone 'Africa/Johannesburg')::date::text);

-- 1. Objects, grants, definer settings, comments and the parameter ---------------------------------

do $$
declare
  f text;
  v_fn regprocedure;
begin
  foreach f in array array[
    'hsf_signoff_register_check_max_days()', 'hsf_scan_record(uuid, text, text, jsonb)',
    'hsf_scan_claim(int)', 'hsf_scan_write_back(uuid, uuid, text, bigint, jsonb)',
    'hsf_transfer_cleanup_queue(int)', 'hsf_retention_queue(int)', 'hsf_mark_staging_deleted(uuid)',
    'hsf_mark_expired(uuid)', 'hsf_sweep_stale_uploads(int)',
    'hsf_scan_record_clean(uuid, text, jsonb, text, jsonb, bigint)', 'hsf_transfer_claim(int)',
    'hsf_transfer_record(uuid, text, text, text, text, text, text)', 'hsf_upload_deletable(text, text, timestamptz)',
    'hsf_deletion_request_create(uuid, uuid[], text, boolean)', 'hsf_deletion_request_attempt(uuid, uuid)',
    'hsf_my_uploads(uuid, uuid)', 'hsf_signatory_fit(uuid)',
    'hsf_release_rules(uuid, int)', 'hsf_release_readiness(uuid, int)', 'hsf_signatory_expiry_alerts_list()',
    'hsf_staff_verification_list(uuid)', 'hsf_staff_verify_client(uuid, uuid, text, text)',
    'hsf_staff_revoke_client(uuid, uuid, text)', 'hsf_staff_scan_list(uuid)', 'hsf_staff_scan_reset(uuid, uuid)',
    'hsf_staff_signatory_list(uuid)', 'hsf_staff_signatory_save(uuid, jsonb)', 'hsf_staff_signoff_record(uuid, jsonb)',
    'hsf_staff_file_list(uuid)', 'hsf_staff_signatory_alerts(uuid)'] loop
    v_fn := f::regprocedure;
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception 'CHECK FAILED: % is executable by anon or authenticated', f;
    end if;
    if not has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'CHECK FAILED: % is not executable by the service role', f;
    end if;
  end loop;
  raise notice 'ok   every new or redefined 054 function is service role only';

  foreach f in array array[
    'hsf_staff_email(uuid)', 'hsf_staff_text(text, text, int, boolean)', 'hsf_staff_date(text, text)',
    'hsf_verify_client_by(text, uuid, text, text)', 'hsf_revoke_client_verification_by(text, uuid, text)',
    'hsf_scan_reset_by(text, uuid)', 'hsf_scan_claim_held(timestamptz)', 'hsf_signatory_register_checks(uuid)'] loop
    v_fn := f::regprocedure;
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute')
       or has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'CHECK FAILED: the internal % is executable from outside', f;
    end if;
  end loop;
  raise notice 'ok   the internal helpers (staff check, form fields, the shared *_by bodies) are not executable by anyone outside';

  foreach f in array array['hsf_verify_client(uuid, text, text)', 'hsf_revoke_client_verification(uuid, text)',
                           'hsf_scan_reset(uuid)'] loop
    v_fn := f::regprocedure;
    if has_function_privilege('anon', v_fn, 'execute') or not has_function_privilege('authenticated', v_fn, 'execute')
       or not has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'CHECK FAILED: % lost its 052 grants', f;
    end if;
  end loop;
  raise notice 'ok   the 052 verify, revoke and scan reset keep their grants (authenticated with staff checked inside, service role)';

  foreach f in array array[
    'hsf_signoff_register_check_max_days()', 'hsf_scan_record(uuid, text, text, jsonb)',
    'hsf_scan_claim(int)', 'hsf_scan_write_back(uuid, uuid, text, bigint, jsonb)',
    'hsf_transfer_cleanup_queue(int)', 'hsf_retention_queue(int)', 'hsf_mark_staging_deleted(uuid)',
    'hsf_mark_expired(uuid)', 'hsf_sweep_stale_uploads(int)', 'hsf_signatory_register_checks(uuid)',
    'hsf_signatory_guard()',
    'hsf_scan_record_clean(uuid, text, jsonb, text, jsonb, bigint)', 'hsf_transfer_claim(int)',
    'hsf_transfer_record(uuid, text, text, text, text, text, text)', 'hsf_deletion_request_attempt(uuid, uuid)',
    'hsf_deletion_request_create(uuid, uuid[], text, boolean)', 'hsf_my_uploads(uuid, uuid)', 'hsf_signatory_fit(uuid)',
    'hsf_release_rules(uuid, int)', 'hsf_release_gate()',
    'hsf_release_readiness(uuid, int)', 'hsf_signatory_expiry_alerts_list()', 'hsf_staff_email(uuid)',
    'hsf_verify_client_by(text, uuid, text, text)', 'hsf_revoke_client_verification_by(text, uuid, text)',
    'hsf_scan_reset_by(text, uuid)', 'hsf_verify_client(uuid, text, text)', 'hsf_revoke_client_verification(uuid, text)',
    'hsf_scan_reset(uuid)', 'hsf_staff_verification_list(uuid)', 'hsf_staff_verify_client(uuid, uuid, text, text)',
    'hsf_staff_revoke_client(uuid, uuid, text)', 'hsf_staff_scan_list(uuid)', 'hsf_staff_scan_reset(uuid, uuid)',
    'hsf_staff_signatory_list(uuid)', 'hsf_staff_signatory_save(uuid, jsonb)', 'hsf_staff_signoff_record(uuid, jsonb)',
    'hsf_staff_file_list(uuid)', 'hsf_staff_signatory_alerts(uuid)'] loop
    if not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                     and exists (select 1 from unnest(p.proconfig) c where c = 'search_path=public')) then
      raise exception 'CHECK FAILED: % is not security definer with search_path=public', f;
    end if;
    if obj_description(f::regprocedure, 'pg_proc') is null then
      raise exception 'CHECK FAILED: % has no comment', f;
    end if;
  end loop;
  raise notice 'ok   every 054 function with data access is security definer with search_path=public and commented';
end $$;

select pg_temp.ok('the helpers without data access carry a comment and a fixed search path',
  (select bool_and(obj_description(f::regprocedure, 'pg_proc') is not null
                   and exists (select 1 from pg_proc p, unnest(p.proconfig) c where p.oid = f::regprocedure and c = 'search_path=public'))
     from unnest(array['hsf_staff_text(text, text, int, boolean)', 'hsf_staff_date(text, text)',
                       'hsf_upload_deletable(text, text, timestamptz)', 'hsf_scan_claim_held(timestamptz)']) f));
select pg_temp.ok('the parameter hsf.signoff_register_check_max_days exists in category hsf: 30, from 1 to 365',
  msp_env_get_int('hsf.signoff_register_check_max_days') = 30
  and (select category = 'hsf' and min_value = 1 and max_value = 365 and value_type = 'integer' and description is not null
         from msp_env_parameter where key = 'hsf.signoff_register_check_max_days')
  and hsf_signoff_register_check_max_days() = 30);
select pg_temp.ok('hsf_upload carries the four cleaned copy columns, each commented',
  (select count(*) = 4 from information_schema.columns where table_name = 'hsf_upload'
      and column_name in ('sha256_clean','metadata_removed','cleaned_at','size_bytes_clean'))
  and (select bool_and(col_description('hsf_upload'::regclass, a.attnum) is not null) from pg_attribute a
        where a.attrelid = 'hsf_upload'::regclass and a.attname in ('sha256_clean','metadata_removed','cleaned_at','size_bytes_clean')));
select pg_temp.ok('hsf_signoff carries document_ref, commented, and no column for the staff email (the client reads hsf_signoff)',
  (select count(*) = 1 from pg_attribute a where a.attrelid = 'hsf_signoff'::regclass and not a.attisdropped
      and a.attname in ('document_ref','recorded_by') and col_description(a.attrelid, a.attnum) is not null)
  and not exists (select 1 from pg_attribute a where a.attrelid = 'hsf_signoff'::regclass and not a.attisdropped
                   and a.attname = 'recorded_by'));
select pg_temp.ok('hsf_upload carries the scan hold columns, and hsf_signatory the appended register checks, each commented',
  (select count(*) = 3 from pg_attribute a where a.attrelid = 'hsf_upload'::regclass
      and a.attname in ('scan_claim_id','scan_claimed_at','scan_write_back') and col_description(a.attrelid, a.attnum) is not null)
  and (select col_description(a.attrelid, a.attnum) is not null from pg_attribute a
        where a.attrelid = 'hsf_signatory'::regclass and a.attname = 'register_rechecks'));
select pg_temp.ok('the expiry alerts view is commented; authenticated may select (staff filtered inside), anon may not',
  obj_description('hsf_signatory_expiry_alerts'::regclass, 'pg_class') is not null
  and has_table_privilege('authenticated', 'hsf_signatory_expiry_alerts', 'select')
  and not has_table_privilege('anon', 'hsf_signatory_expiry_alerts', 'select')
  and not has_table_privilege('authenticated', 'hsf_signatory_expiry_alerts', 'insert'));
select pg_temp.ok('the gate and the readiness check share one rules function, and neither repeats a rule',
  pg_get_functiondef('hsf_release_gate()'::regprocedure) ~ 'hsf_release_rules\(new\.file_id, new\.revision\)'
  and pg_get_functiondef('hsf_release_readiness(uuid, int)'::regprocedure) ~ 'hsf_release_rules\('
  and pg_get_functiondef('hsf_release_rules(uuid, int)'::regprocedure) ~ 'hsf_signatory_fit\('
  and pg_get_functiondef('hsf_release_rules(uuid, int)'::regprocedure) ~ 'hsf_element_citable\('
  and (select bool_and(pg_get_functiondef(f::regprocedure) !~ '(hsf_signatory_fit|hsf_element_citable|client_16_2_acceptance)')
         from unnest(array['hsf_release_gate()', 'hsf_release_readiness(uuid, int)']) f));
select pg_temp.ok('the 052 verify, revoke and scan reset share their bodies with the console functions',
  pg_get_functiondef('hsf_verify_client(uuid, text, text)'::regprocedure) ~ 'hsf_verify_client_by\('
  and pg_get_functiondef('hsf_staff_verify_client(uuid, uuid, text, text)'::regprocedure) ~ 'hsf_verify_client_by\(hsf_staff_email\(p_auth_user\)'
  and pg_get_functiondef('hsf_revoke_client_verification(uuid, text)'::regprocedure) ~ 'hsf_revoke_client_verification_by\('
  and pg_get_functiondef('hsf_staff_revoke_client(uuid, uuid, text)'::regprocedure) ~ 'hsf_revoke_client_verification_by\(hsf_staff_email\(p_auth_user\)'
  and pg_get_functiondef('hsf_scan_reset(uuid)'::regprocedure) ~ 'hsf_scan_reset_by\('
  and pg_get_functiondef('hsf_staff_scan_reset(uuid, uuid)'::regprocedure) ~ 'hsf_scan_reset_by\(hsf_staff_email\(p_auth_user\)');
select pg_temp.ok('every staff console function checks the staff role in its body',
  (select bool_and(pg_get_functiondef(f::regprocedure) ~ 'hsf_staff_email\(p_auth_user\)')
     from unnest(array['hsf_staff_verification_list(uuid)', 'hsf_staff_verify_client(uuid, uuid, text, text)',
                       'hsf_staff_revoke_client(uuid, uuid, text)', 'hsf_staff_scan_list(uuid)', 'hsf_staff_scan_reset(uuid, uuid)',
                       'hsf_staff_signatory_list(uuid)', 'hsf_staff_signatory_save(uuid, jsonb)',
                       'hsf_staff_signoff_record(uuid, jsonb)', 'hsf_staff_file_list(uuid)', 'hsf_staff_signatory_alerts(uuid)']) f)
  and pg_get_functiondef('hsf_staff_email(uuid)'::regprocedure) ~ 'hsf_user_is_staff\(p_auth_user\)');

-- 2. Nobody without a staff role reaches a console function (contract 11.5) -------------------------

select pg_temp.put('audit_before', (select count(*) from msp_audit)::text);
select pg_temp.put('sig_before', (select count(*) from hsf_signatory)::text);
do $$
declare
  u text;
  c text;
  v_state text;
  v_calls text[];
begin
  foreach u in array array[pg_temp.ctx('c1'), pg_temp.ctx('n1'), pg_temp.ctx('n2'), gen_random_uuid()::text, null] loop
    -- Valid arguments throughout, so only the role decides.
    v_calls := array[
      format('select hsf_staff_verification_list(%L)', u),
      format('select hsf_staff_verify_client(%L, %L, ''client_register'', ''REG-CON-1'')', u, pg_temp.ctx('acc1')),
      format('select hsf_staff_revoke_client(%L, %L, ''Not a client'')', u, pg_temp.ctx('acc1')),
      format('select hsf_staff_scan_list(%L)', u),
      format('select hsf_staff_scan_reset(%L, %L)', u, gen_random_uuid()),
      format('select hsf_staff_signatory_list(%L)', u),
      format('select hsf_staff_signatory_save(%L, %L::jsonb)', u, jsonb_build_object(
        'full_name', 'Refused Practitioner', 'registration_body', 'SAIOSH', 'category', 'CMSAIOSH',
        'registration_number', 'FIXTURE-REFUSED', 'registration_expires_on', '2030-01-01')),
      format('select hsf_staff_signoff_record(%L, %L::jsonb)', u, jsonb_build_object(
        'file_id', pg_temp.ctx('f1'), 'kind', 'client_16_2_acceptance', 'decision', 'approved',
        'decided_at', pg_temp.ctx('dec'), 'signatory_name', 'Refused appointee', 'document_ref', 'fixture/refused.pdf')),
      format('select hsf_staff_file_list(%L)', u),
      format('select hsf_staff_signatory_alerts(%L)', u)];
    foreach c in array v_calls loop
      v_state := pg_temp.sqlstate_of(c);
      if v_state is distinct from '42501' then
        raise exception 'CHECK FAILED: % answered SQLSTATE % for a person without a staff role (%)', c, coalesce(v_state, 'none'), coalesce(u, 'null');
      end if;
    end loop;
  end loop;
  raise notice 'ok   all ten staff console functions refuse (SQLSTATE 42501) a client, a non HSF forge role, a person with no role, an unknown user and no user';
end $$;
select pg_temp.refuses_exactly('the refusal is in plain words and names no staff role',
  format('select hsf_staff_file_list(%L)', pg_temp.ctx('c1')), 'This needs a Care Net staff role.');
select pg_temp.ok('the refused calls wrote nothing: no audit row, no signatory, no sign off, no verification',
  (select count(*) from msp_audit) = pg_temp.ctx('audit_before')::int
  and (select count(*) from hsf_signatory) = pg_temp.ctx('sig_before')::int
  and not exists (select 1 from hsf_signoff where file_id = pg_temp.ctx('f1')::uuid)
  and not exists (select 1 from hsf_client_verification where client_account_id = pg_temp.ctx('acc1')::uuid));
select pg_temp.ok('both staff roles pass the check (forge_safety_reviewer and forge_admin)',
  jsonb_typeof(hsf_staff_file_list(pg_temp.ctx('s1')::uuid)) = 'array'
  and jsonb_typeof(hsf_staff_file_list(pg_temp.ctx('s2')::uuid)) = 'array');

-- 3. Clients to verify ---------------------------------------------------------------------------------

select hsf_request_client_verification(pg_temp.ctx('c1')::uuid);
select pg_temp.act('list', format('select hsf_staff_verification_list(%L)', pg_temp.ctx('s1')));
select pg_temp.ok('the verification list shows the request with company, contact email and requested_at',
  (select x ->> 'status' = 'requested' and x ->> 'company_name' = 'Console Test Works (Pty) Ltd'
          and x ->> 'contact_email' = 'console.client@example.invalid' and x ->> 'requested_at' is not null
          and x ? 'method' and x ? 'evidence_ref'
     from jsonb_array_elements(pg_temp.r('list')) x where x ->> 'client_account_id' = pg_temp.ctx('acc1')));
select pg_temp.refuses('the console refuses an unknown verification method',
  format('select hsf_staff_verify_client(%L, %L, ''website'', ''REG-CON-1'')', pg_temp.ctx('s1'), pg_temp.ctx('acc1')),
  'mco_company_ref, client_register or sales_executive');
select pg_temp.refuses('the console refuses a verification with no evidence reference',
  format('select hsf_staff_verify_client(%L, %L, ''client_register'', ''  '')', pg_temp.ctx('s1'), pg_temp.ctx('acc1')), 'rests on');
select pg_temp.ok('the console answers P0002 for an unknown company account',
  pg_temp.sqlstate_of(format('select hsf_staff_verify_client(%L, %L, ''client_register'', ''REG-CON-1'')',
                             pg_temp.ctx('s1'), gen_random_uuid())) = 'P0002');
select pg_temp.act('r', format('select hsf_staff_verify_client(%L, %L, ''client_register'', ''REG-CON-1'')', pg_temp.ctx('s1'), pg_temp.ctx('acc1')));
select pg_temp.ok('a staff verification records the staff email in verified_by and as the audit actor',
  pg_temp.r('r') ->> 'status' = 'verified' and pg_temp.r('r') ->> 'verified_by' = pg_temp.ctx('s1_email')
  and (select verified_by = pg_temp.ctx('s1_email') and method = 'client_register' and evidence_ref = 'REG-CON-1'
         from hsf_client_verification where client_account_id = pg_temp.ctx('acc1')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_client_verified' and actor = pg_temp.ctx('s1_email')
                and event_detail ->> 'client_account_id' = pg_temp.ctx('acc1')));

-- Uploads open and consent given, so the account can upload.
update msp_env_parameter set value = 'true' where key = 'hsf.uploads_open';
update msp_env_parameter set value = 'hold' where key = 'hsf.mco_transfer_mode';
select hsf_record_consent(pg_temp.ctx('c1')::uuid, array['document_storage','mco_transfer','authority_to_share'], 'HSF-CONSENT-1.0');
select pg_temp.upload('up_v', 'c1', pg_temp.ctx('sha_x'));

select pg_temp.refuses('a staff revocation needs a reason',
  format('select hsf_staff_revoke_client(%L, %L, '' '')', pg_temp.ctx('s2'), pg_temp.ctx('acc1')), 'reason');
select pg_temp.act('r', format('select hsf_staff_revoke_client(%L, %L, ''Contract under review'')', pg_temp.ctx('s2'), pg_temp.ctx('acc1')));
select pg_temp.ok('a staff revocation records the staff email in revoked_by and the audit, blocks and deletes nothing',
  pg_temp.r('r') ->> 'status' = 'revoked' and (pg_temp.r('r') ->> 'blocked_uploads')::int = 1
  and (select revoked_by = pg_temp.ctx('s2_email') and revoke_reason = 'Contract under review'
         from hsf_client_verification where client_account_id = pg_temp.ctx('acc1')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_client_verification_revoked' and actor = pg_temp.ctx('s2_email'))
  and (select status = 'uploaded' and storage_path is not null and transfer_blocked_reason = 'client verification revoked'
         from hsf_upload where id = pg_temp.ctx('up_v')::uuid));
select pg_temp.act('r', format('select hsf_staff_verify_client(%L, %L, ''sales_executive'', ''Confirmed by a sales executive'')', pg_temp.ctx('s2'), pg_temp.ctx('acc1')));
select pg_temp.ok('verified again by the forge_admin, whose email is recorded',
  (select status = 'verified' and verified_by = pg_temp.ctx('s2_email') and revoked_by is null
     from hsf_client_verification where client_account_id = pg_temp.ctx('acc1')::uuid));
select pg_temp.ok('the verification list now reads verified, with the method and evidence',
  (select x ->> 'status' = 'verified' and x ->> 'method' = 'sales_executive' and x ->> 'verified_by' = pg_temp.ctx('s2_email')
     from jsonb_array_elements(hsf_staff_verification_list(pg_temp.ctx('s1')::uuid)) x
    where x ->> 'client_account_id' = pg_temp.ctx('acc1')));

-- 4. A clean scan carries the cleaned copy (contract 11.1) ----------------------------------------------

do $$
begin
  perform pg_temp.upload('up_a', 'c1', pg_temp.ctx('sha_a'));
  perform pg_temp.upload('up_b', 'c1', pg_temp.ctx('sha_b'));
  perform pg_temp.upload('up_c', 'c1', pg_temp.ctx('sha_c'));
  perform pg_temp.upload('up_d', 'c1', pg_temp.ctx('sha_d'));
  perform pg_temp.upload('up_l', 'c1', pg_temp.ctx('sha_l'));
  perform pg_temp.upload('up_x', 'c1', pg_temp.ctx('sha_x'));
end $$;
select pg_temp.put('removed', '[{"code":"docprops_creator","message":"The author name was removed.","label":"author"},
  {"code":"app_company","message":"The company name was removed.","label":"company"},
  {"code":"exif_gps","message":"Location details were removed.","label":"location"},
  {"code":"docprops_last_modified_by","message":"The name of the last editor was removed.","label":"author"},
  {"code":"docx_comments","message":"Comments"}]');

select pg_temp.refuses('the plain scan record refuses a clean result (054): a clean result must carry the cleaned fingerprint',
  format('select hsf_scan_record(%L, ''clean'', ''ClamAV test 1.0'', ''[]''::jsonb)', pg_temp.ctx('up_a')),
  'must carry the fingerprint of the cleaned copy');
select pg_temp.refuses('a clean record without the cleaned fingerprint is refused',
  format('select hsf_scan_record_clean(%L, ''ClamAV test 1.0'', null, null, ''[]''::jsonb, 1900)', pg_temp.ctx('up_a')),
  'fingerprint of the cleaned copy');
select pg_temp.refuses('a clean record with a malformed cleaned fingerprint is refused',
  format('select hsf_scan_record_clean(%L, ''ClamAV test 1.0'', null, ''abc123'', ''[]''::jsonb, 1900)', pg_temp.ctx('up_a')),
  '64 hexadecimal characters');
select pg_temp.refuses('the removed details must be a list',
  format('select hsf_scan_record_clean(%L, null, null, %L, ''{"a":1}''::jsonb, 1900)', pg_temp.ctx('up_a'), pg_temp.ctx('clean_a')),
  'removed details must be a list');
select pg_temp.refuses('each removed detail needs a code and a message',
  format('select hsf_scan_record_clean(%L, null, null, %L, ''[{"code":"exif_gps"}]''::jsonb, 1900)', pg_temp.ctx('up_a'), pg_temp.ctx('clean_a')),
  'each with a code and a message');
select pg_temp.refuses('the scan findings must still be a list',
  format('select hsf_scan_record_clean(%L, null, ''{"a":1}''::jsonb, %L, ''[]''::jsonb, 1900)', pg_temp.ctx('up_a'), pg_temp.ctx('clean_a')),
  'findings must be a list');
select pg_temp.refuses('the size of the cleaned copy is required',
  format('select hsf_scan_record_clean(%L, null, null, %L, ''[]''::jsonb, 0)', pg_temp.ctx('up_a'), pg_temp.ctx('clean_a')),
  'size of the cleaned copy');
select pg_temp.ok('an unknown upload answers P0002',
  pg_temp.sqlstate_of(format('select hsf_scan_record_clean(%L, null, null, %L, ''[]''::jsonb, 1900)', gen_random_uuid(), pg_temp.ctx('clean_a'))) = 'P0002');
select pg_temp.ok('the refusals wrote nothing: A is still pending with no cleaned copy',
  (select scan_status = 'pending' and sha256_clean is null and cleaned_at is null and metadata_removed is null
     from hsf_upload where id = pg_temp.ctx('up_a')::uuid)
  and pg_temp.mine('c1', 'up_a') -> 'metadata_removed' = 'null'::jsonb);

select pg_temp.act('r', format('select hsf_scan_record_clean(%L, ''ClamAV test 1.0'', ''[]''::jsonb, %L, %L::jsonb, 1900)',
                               pg_temp.ctx('up_a'), upper(pg_temp.ctx('clean_a')), pg_temp.ctx('removed')));
select pg_temp.ok('clean with the cleaned copy: scan clean, fingerprint (lower case), size, time and removed details recorded',
  pg_temp.r('r') ->> 'scan_status' = 'clean' and pg_temp.r('r') ->> 'status' = 'uploaded'
  and (select status = 'uploaded' and scan_status = 'clean' and scan_engine = 'ClamAV test 1.0'
              and sha256_clean = pg_temp.ctx('clean_a') and sha256_client = pg_temp.ctx('sha_a')
              and size_bytes_clean = 1900 and size_bytes = 2048 and cleaned_at is not null
              and jsonb_array_length(metadata_removed) = 5
         from hsf_upload where id = pg_temp.ctx('up_a')::uuid));
select pg_temp.ok('clean is audited with both fingerprints and the codes removed, never content',
  exists (select 1 from msp_audit where event_type = 'hsf_upload_scanned' and event_detail ->> 'upload_id' = pg_temp.ctx('up_a')
            and event_detail ->> 'result' = 'clean' and event_detail ->> 'sha256_clean' = pg_temp.ctx('clean_a')
            and event_detail ->> 'sha256_client' = pg_temp.ctx('sha_a')
            and event_detail -> 'metadata_removed' = '["docprops_creator","app_company","exif_gps","docprops_last_modified_by","docx_comments"]'::jsonb));
select pg_temp.ok('the builder reads the removed details as plain labels, each once, in order; a label falls back to the message',
  pg_temp.mine('c1', 'up_a') -> 'metadata_removed' = '["author","company","location","Comments"]'::jsonb
  and pg_temp.mine('c1', 'up_a') ->> 'cleaned_at' is not null);
select pg_temp.refuses('a cleaned upload is not scanned again',
  format('select hsf_scan_record_clean(%L, null, null, %L, ''[]''::jsonb, 1900)', pg_temp.ctx('up_a'), pg_temp.ctx('clean_a')),
  'not waiting for a security scan');
select pg_temp.refuses('the four cleaned copy columns are written together or not at all',
  format('update hsf_upload set sha256_clean = %L where id = %L', pg_temp.ctx('clean_b'), pg_temp.ctx('up_b')),
  'hsf_upload_clean_complete');

select pg_temp.clean('up_b', pg_temp.ctx('clean_b'));
select pg_temp.clean('up_c', pg_temp.ctx('clean_c'));
select pg_temp.clean('up_d', pg_temp.ctx('clean_d'));
select pg_temp.clean('up_x', pg_temp.ctx('clean_x'));
select pg_temp.ok('nothing removed reads as an empty list in the builder',
  pg_temp.mine('c1', 'up_b') -> 'metadata_removed' = '[]'::jsonb);
-- L stands for a row marked clean before 054, with no cleaned copy.
update hsf_upload set scan_status = 'clean', scanned_at = now() where id = pg_temp.ctx('up_l')::uuid;

-- 5. Only cleaned copies move, compared with sha256_clean (contract 11.1) --------------------------------

select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('hold mode: only uploads with a cleaned copy are claimed, never the clean row without one (L)',
  pg_temp.r('claim') = pg_temp.ids(pg_temp.ctx('up_a'), pg_temp.ctx('up_b'), pg_temp.ctx('up_c'), pg_temp.ctx('up_d'), pg_temp.ctx('up_x')));
select pg_temp.refuses('a clean row without a cleaned copy cannot be recorded held',
  format('select hsf_transfer_record(%L, ''hold'', ''held'', null, null, null, null)', pg_temp.ctx('up_l')),
  'has not passed the security scan with a cleaned copy');
update msp_env_parameter set value = 'fixture' where key = 'hsf.mco_transfer_mode';
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('fixture mode: the cleaned uploads are claimed and transferring, L is not',
  pg_temp.r('claim') = pg_temp.ids(pg_temp.ctx('up_a'), pg_temp.ctx('up_b'), pg_temp.ctx('up_c'), pg_temp.ctx('up_d'), pg_temp.ctx('up_x'))
  and pg_temp.status_of('up_l') = 'uploaded');
select pg_temp.refuses('a clean row without a cleaned copy cannot be recorded received',
  format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, ''FIXTURE-L'', %L, null)',
         pg_temp.ctx('up_l'), pg_temp.ctx('sha_l'), pg_temp.ctx('sha_l')), 'has not passed the security scan with a cleaned copy');

select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, ''FIXTURE-A'', %L, null)',
                               pg_temp.ctx('up_a'), pg_temp.ctx('sha_a'), pg_temp.ctx('sha_a')));
select pg_temp.ok('received with the client fingerprint (the bytes before cleaning) is a mismatch: A fails and keeps its bytes',
  pg_temp.r('r') ->> 'outcome' = 'hash_mismatch' and pg_temp.r('r') ->> 'status' = 'failed'
  and (select status = 'failed' and mco_document_ref is null and storage_path is not null
              and reject_reason like '%cleaned copy%' from hsf_upload where id = pg_temp.ctx('up_a')::uuid));
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, ''FIXTURE-C'', %L, null)',
                               pg_temp.ctx('up_c'), pg_temp.ctx('clean_c'), pg_temp.ctx('sha_c')));
select pg_temp.ok('a receipt fingerprint that is not the cleaned copy''s is a mismatch, even with the right server fingerprint',
  pg_temp.r('r') ->> 'outcome' = 'hash_mismatch' and pg_temp.status_of('up_c') = 'failed');
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, ''FIXTURE-B'', %L, null)',
                               pg_temp.ctx('up_b'), upper(pg_temp.ctx('clean_b')), pg_temp.ctx('clean_b')));
select pg_temp.ok('server and receipt both equal to sha256_clean: B is transferred, the client fingerprint stays as proof',
  pg_temp.r('r') ->> 'status' = 'transferred' and pg_temp.r('r') ->> 'mco_document_ref' = 'FIXTURE-B'
  and (select status = 'transferred' and sha256_server = pg_temp.ctx('clean_b') and sha256_client = pg_temp.ctx('sha_b')
              and sha256_clean = pg_temp.ctx('clean_b') from hsf_upload where id = pg_temp.ctx('up_b')::uuid)
  and exists (select 1 from hsf_mco_transfer where upload_id = pg_temp.ctx('up_b')::uuid and outcome = 'received'
                and mco_receipt_sha256 = pg_temp.ctx('clean_b')));

-- The late receipt backstop stays: X expires while in flight, then MyClinicOnline answers.
update hsf_upload set uploaded_at = now() - interval '3 years', transfer_claimed_at = now() - interval '31 minutes'
 where id = pg_temp.ctx('up_x')::uuid;
select pg_temp.ok('an upload whose transfer stopped long ago reaches the two year limit and expires',
  hsf_mark_expired(pg_temp.ctx('up_x')::uuid) ->> 'status' = 'expired');
select pg_temp.refuses('a late receipt carrying the client fingerprint does not match the cleaned copy and is refused',
  format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, ''FIXTURE-X'', %L, null)',
         pg_temp.ctx('up_x'), pg_temp.ctx('sha_x'), pg_temp.ctx('sha_x')), 'not waiting for transfer');
select pg_temp.act('r', format('select hsf_transfer_record(%L, ''fixture'', ''received'', %L, ''FIXTURE-X'', %L, null)',
                               pg_temp.ctx('up_x'), pg_temp.ctx('clean_x'), pg_temp.ctx('clean_x')));
select pg_temp.ok('a late receipt matching sha256_clean is kept and asks for the deletion at MyClinicOnline',
  (pg_temp.r('r') ->> 'mco_deletion_needed')::boolean and pg_temp.r('r') ->> 'status' = 'expired'
  and (select mco_document_ref = 'FIXTURE-X' from hsf_upload where id = pg_temp.ctx('up_x')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_transfer_received_after_deletion'
                and event_detail ->> 'upload_id' = pg_temp.ctx('up_x') and event_detail ->> 'sha256' = pg_temp.ctx('clean_x')));

-- 6. A document in transfer is never deletable by the client (contract 11.2) ------------------------------

select pg_temp.ok('hsf_upload_deletable: transferring is refused at any age of the claim, uploaded with bytes is not',
  not hsf_upload_deletable('transferring', 'p', now())
  and not hsf_upload_deletable('transferring', 'p', now() - interval '31 minutes')
  and not hsf_upload_deletable('transferring', 'p', now() - interval '2 days')
  and not hsf_upload_deletable('transferring', 'p', null)
  and hsf_upload_deletable('uploaded', 'p', null) and hsf_upload_deletable('held', 'p', null)
  and not hsf_upload_deletable('uploaded', null, null));
update hsf_upload set transfer_claimed_at = now() - interval '2 hours' where id = pg_temp.ctx('up_d')::uuid;
select pg_temp.ok('D, in transfer with a claim two hours old, reads not deletable in the builder',
  pg_temp.status_of('up_d') = 'transferring' and not (pg_temp.mine('c1', 'up_d') ->> 'deletable')::boolean);
select pg_temp.refuses('D cannot be chosen for deletion, and the client reads that it can be deleted only if the move stops',
  format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('c1'), pg_temp.ctx('up_d')),
  'cannot be deleted here.*being moved there now can be deleted only if the move stops\.$');
select hsf_transfer_record(pg_temp.ctx('up_d')::uuid, 'fixture', 'error', null, null, null, 'Adapter timed out');
select pg_temp.ok('the transfer errors: D returns to uploaded and is deletable again',
  pg_temp.status_of('up_d') = 'uploaded' and (pg_temp.mine('c1', 'up_d') ->> 'deletable')::boolean);
select pg_temp.act('req1', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('c1'), pg_temp.ctx('up_d')));
select pg_temp.put('req1', pg_temp.r('req1') ->> 'request_id');
select pg_temp.ok('a deletion request for D opens', pg_temp.ctx('req1') is not null);
-- Claimed again before the client confirms: the confirmation is refused.
select pg_temp.act('claim', 'select pg_temp.claim_ids()');
select pg_temp.ok('the worker claims D again', pg_temp.r('claim') = pg_temp.ids(pg_temp.ctx('up_d')));

-- A blocked upload whose transfer stopped part way (review finding F2): a
-- blocked upload is never claimed again, so no transfer error returns it. The
-- sweep does, once the claim is older than 30 minutes.
select pg_temp.upload('up_s', 'c1', pg_temp.ctx('sha_s'));
select pg_temp.clean('up_s', pg_temp.ctx('clean_s'));
update hsf_upload set status = 'transferring', transfer_claimed_at = now() - interval '2 hours',
                      transfer_blocked_reason = 'client verification revoked'
 where id = pg_temp.ctx('up_s')::uuid;
select pg_temp.ok('a blocked transfer that stopped two hours ago is not deletable, not claimed and in no queue before the sweep',
  not (pg_temp.mine('c1', 'up_s') ->> 'deletable')::boolean
  and not exists (select 1 from hsf_transfer_claim(100) q where q.id = pg_temp.ctx('up_s')::uuid)
  and not exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x where x ->> 'upload_id' = pg_temp.ctx('up_s')));
select hsf_sweep_stale_uploads(24);
select pg_temp.ok('the sweep returns it to uploaded, still blocked, deletable again, audited',
  (select status = 'uploaded' and transfer_claimed_at is null and transfer_blocked_reason = 'client verification revoked'
     from hsf_upload where id = pg_temp.ctx('up_s')::uuid)
  and (pg_temp.mine('c1', 'up_s') ->> 'deletable')::boolean
  and exists (select 1 from msp_audit where event_type = 'hsf_transfer_stalled_returned'
                and event_detail -> 'upload_ids' ? pg_temp.ctx('up_s')));
update hsf_upload set status = 'transferring', transfer_claimed_at = now() - interval '5 minutes' where id = pg_temp.ctx('up_s')::uuid;
select hsf_sweep_stale_uploads(24);
select pg_temp.ok('a blocked transfer claimed five minutes ago is left in flight by the sweep',
  pg_temp.status_of('up_s') = 'transferring');
update hsf_upload set status = 'uploaded', transfer_claimed_at = null where id = pg_temp.ctx('up_s')::uuid;

-- 7. Five PIN attempts an hour per account (contract 11.3) --------------------------------------------------

select hsf_deletion_request_pin_sent(pg_temp.ctx('c1')::uuid, pg_temp.ctx('req1')::uuid);
do $$
declare
  r jsonb;
  i int;
begin
  for i in 1..4 loop
    r := hsf_deletion_request_attempt(pg_temp.ctx('c1')::uuid, pg_temp.ctx('req1')::uuid);
    if not (r ->> 'allowed')::boolean or (r ->> 'attempts_left')::int <> 5 - i then
      raise exception 'CHECK FAILED: attempt % answered %', i, r;
    end if;
  end loop;
  raise notice 'ok   four PIN attempts on one request are allowed';
end $$;
select pg_temp.refuses('the request whose document is in transfer again cannot be confirmed',
  format('select hsf_deletion_request_confirm(%L, %L)', pg_temp.ctx('c1'), pg_temp.ctx('req1')), 'no longer be deleted');
select hsf_transfer_record(pg_temp.ctx('up_d')::uuid, 'fixture', 'error', null, null, null, 'Adapter timed out');
-- A new request (a new PIN) does not bring fresh guesses.
select pg_temp.act('req2', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('c1'), pg_temp.ctx('up_d')));
select pg_temp.put('req2', pg_temp.r('req2') ->> 'request_id');
select hsf_deletion_request_pin_sent(pg_temp.ctx('c1')::uuid, pg_temp.ctx('req2')::uuid);
select pg_temp.act('r', format('select hsf_deletion_request_attempt(%L, %L)', pg_temp.ctx('c1'), pg_temp.ctx('req2')));
select pg_temp.ok('the fifth attempt of the hour on the account is allowed, on the new request',
  pg_temp.r('r') = '{"allowed": true, "attempts_left": 4, "status": "pending"}'::jsonb);
select pg_temp.act('r', format('select hsf_deletion_request_attempt(%L, %L)', pg_temp.ctx('c1'), pg_temp.ctx('req2')));
select pg_temp.ok('the sixth attempt of the hour is refused as rate_limited and not counted (052 allowed ten)',
  pg_temp.r('r') = '{"allowed": false, "attempts_left": 4, "status": "rate_limited"}'::jsonb
  and (select attempts = 1 and status = 'pending' from hsf_deletion_request where id = pg_temp.ctx('req2')::uuid));
-- Review finding SEC-4: a request opened just over an hour ago may have taken
-- its guesses well inside the hour (a PIN is tried until the request closes, 10
-- minutes after it opened), so it still counts.
update hsf_deletion_request set requested_at = requested_at - interval '61 minutes', expires_at = expires_at - interval '61 minutes'
 where id = pg_temp.ctx('req1')::uuid;
select pg_temp.ok('a request opened 61 minutes ago, closed 51 minutes ago, still counts: the next attempt is rate_limited',
  hsf_deletion_request_attempt(pg_temp.ctx('c1')::uuid, pg_temp.ctx('req2')::uuid)
  = '{"allowed": false, "attempts_left": 4, "status": "rate_limited"}'::jsonb);
update hsf_deletion_request set requested_at = requested_at - interval '10 minutes', expires_at = expires_at - interval '10 minutes'
 where id = pg_temp.ctx('req1')::uuid;
select pg_temp.ok('attempts older than an hour no longer count: the next attempt is allowed',
  hsf_deletion_request_attempt(pg_temp.ctx('c1')::uuid, pg_temp.ctx('req2')::uuid)
  = '{"allowed": true, "attempts_left": 3, "status": "pending"}'::jsonb);
select pg_temp.ok('with the PIN checked, the client deletes D',
  hsf_deletion_request_confirm(pg_temp.ctx('c1')::uuid, pg_temp.ctx('req2')::uuid) ->> 'status' = 'confirmed'
  and pg_temp.status_of('up_d') = 'client_deleted');

-- 8. Scans and staging in the console ----------------------------------------------------------------------

-- The scan pass holds what it claims, and announces its write back (review
-- finding F3: an overlapping run must not scan the upload again and read the
-- cleaned copy as a fingerprint mismatch).
select pg_temp.upload('up_h', 'c1', pg_temp.ctx('sha_h'));
select pg_temp.act('scan', 'select coalesce(jsonb_agg(to_jsonb(q) - ''storage_path''), ''[]''::jsonb) from hsf_scan_claim(100) q');
select pg_temp.put('claim_h', (select x ->> 'scan_claim_id' from jsonb_array_elements(pg_temp.r('scan')) x where x ->> 'id' = pg_temp.ctx('up_h')));
select pg_temp.ok('a scan claim hands out H with a claim identifier and holds it',
  pg_temp.ctx('claim_h') is not null
  and (select scan_claim_id::text = pg_temp.ctx('claim_h') and hsf_scan_claim_held(scan_claimed_at) and scan_attempts = 1
         from hsf_upload where id = pg_temp.ctx('up_h')::uuid));
select pg_temp.ok('an overlapping run does not claim H again while the first pass holds it',
  not exists (select 1 from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_h')::uuid)
  and (select scan_attempts = 1 from hsf_upload where id = pg_temp.ctx('up_h')::uuid));
select pg_temp.refuses('a write back under another claim is refused',
  format('select hsf_scan_write_back(%L, %L, %L, 1800, ''[]''::jsonb)', pg_temp.ctx('up_h'), gen_random_uuid(), pg_temp.ctx('clean_h')),
  'no longer holds the upload');
select pg_temp.refuses('a write back without a claim is refused',
  format('select hsf_scan_write_back(%L, null, %L, 1800, ''[]''::jsonb)', pg_temp.ctx('up_h'), pg_temp.ctx('clean_h')),
  'no longer holds the upload');
select pg_temp.refuses('a write back needs the cleaned fingerprint',
  format('select hsf_scan_write_back(%L, %L, ''abc'', 1800, ''[]''::jsonb)', pg_temp.ctx('up_h'), pg_temp.ctx('claim_h')),
  '64 hexadecimal characters');
update hsf_upload set scan_claimed_at = now() - interval '20 minutes' where id = pg_temp.ctx('up_h')::uuid;
select pg_temp.act('r', format('select hsf_scan_write_back(%L, %L, %L, 1800, %L::jsonb)', pg_temp.ctx('up_h'), pg_temp.ctx('claim_h'),
                               pg_temp.ctx('clean_h'), '[{"code":"author","message":"author"}]'));
select pg_temp.ok('the write back of the holding pass is accepted: the hold is renewed and the cleaned copy announced',
  pg_temp.r('r') ->> 'sha256_clean' = pg_temp.ctx('clean_h')
  and (select scan_claimed_at > now() - interval '1 minute' and scan_write_back ->> 'sha256_clean' = pg_temp.ctx('clean_h')
              and (scan_write_back ->> 'size_bytes')::int = 1800 and scan_status = 'pending'
         from hsf_upload where id = pg_temp.ctx('up_h')::uuid));
select pg_temp.refuses('a clean record with a fingerprint other than the announced one is refused',
  format('select hsf_scan_record_clean(%L, null, null, %L, ''[]''::jsonb, 1800)', pg_temp.ctx('up_h'), pg_temp.ctx('clean_a')),
  'differs from the one announced');
select pg_temp.clean('up_h', pg_temp.ctx('clean_h'));
select pg_temp.ok('the clean record ends the hold and clears the announcement',
  (select scan_status = 'clean' and sha256_clean = pg_temp.ctx('clean_h') and scan_claim_id is null and scan_claimed_at is null
          and scan_write_back is null from hsf_upload where id = pg_temp.ctx('up_h')::uuid));
-- An error recorded after an announcement keeps it, so the next pass accepts the cleaned copy.
select pg_temp.upload('up_t', 'c1', pg_temp.ctx('sha_t'));
select pg_temp.put('claim_t', (select q.scan_claim_id::text from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_t')::uuid));
select hsf_scan_write_back(pg_temp.ctx('up_t')::uuid, pg_temp.ctx('claim_t')::uuid, pg_temp.ctx('clean_t'), 1700, '[]'::jsonb);
select hsf_scan_record(pg_temp.ctx('up_t')::uuid, 'error', 'CNC structural check',
                       '[{"code":"write_back_failed","message":"The file could not be saved to staging after its hidden details were removed."}]'::jsonb);
select pg_temp.ok('an error ends the hold but keeps the announced copy, and the next pass claims T with it',
  (select scan_claimed_at is null and scan_write_back ->> 'sha256_clean' = pg_temp.ctx('clean_t') from hsf_upload where id = pg_temp.ctx('up_t')::uuid)
  and (select q.scan_write_back ->> 'sha256_clean' = pg_temp.ctx('clean_t') from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_t')::uuid));
select hsf_scan_record(pg_temp.ctx('up_t')::uuid, 'harmful', 'CNC structural check', '[{"code":"empty_file","message":"The file is empty."}]'::jsonb);
select pg_temp.ok('a rejection ends the hold and clears the announcement; an empty file reads as a plain reason',
  (select status = 'rejected' and scan_claim_id is null and scan_write_back is null
          and reject_reason = 'The file failed the security scan: The file is empty.' from hsf_upload where id = pg_temp.ctx('up_t')::uuid));

-- Review finding SEC-1: the client deletes K while the scan waits on the
-- antivirus engine. The pass must not write the cleaned copy back, and the
-- cleanup must not remove the object while a pass could still write it, or
-- the object would stay in staging with no row pointing at it.
select pg_temp.upload('up_k', 'c1', pg_temp.ctx('sha_k'));
select pg_temp.put('claim_k', (select q.scan_claim_id::text from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_k')::uuid));
select pg_temp.act('req9', format('select hsf_deletion_request_create(%L, array[%L]::uuid[], ''email'', true)', pg_temp.ctx('c1'), pg_temp.ctx('up_k')));
select pg_temp.put('req9', pg_temp.r('req9') ->> 'request_id');
select hsf_deletion_request_pin_sent(pg_temp.ctx('c1')::uuid, pg_temp.ctx('req9')::uuid);
select pg_temp.ok('K, held by a scan pass, is still deleted by the client with a checked PIN',
  (hsf_deletion_request_attempt(pg_temp.ctx('c1')::uuid, pg_temp.ctx('req9')::uuid) ->> 'allowed')::boolean
  and hsf_deletion_request_confirm(pg_temp.ctx('c1')::uuid, pg_temp.ctx('req9')::uuid) ->> 'status' = 'confirmed'
  and pg_temp.status_of('up_k') = 'client_deleted');
select pg_temp.refuses('the scan pass''s write back for the deleted K is refused, so nothing is written back',
  format('select hsf_scan_write_back(%L, %L, %L, 1800, ''[]''::jsonb)', pg_temp.ctx('up_k'), pg_temp.ctx('claim_k'), pg_temp.ctx('clean_k')),
  'not waiting for a security scan \(status client_deleted, scan pending\), so its cleaned copy must not be written');
select pg_temp.ok('while the pass holds K, the cleanup queue leaves its object alone',
  not exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x where x ->> 'upload_id' = pg_temp.ctx('up_k')));
select pg_temp.refuses('and its object cannot be marked removed',
  format('select hsf_mark_staging_deleted(%L)', pg_temp.ctx('up_k')), 'security scan still holds this upload');
update hsf_upload set scan_claimed_at = now() - interval '31 minutes' where id = pg_temp.ctx('up_k')::uuid;
select pg_temp.ok('once the hold ends, K is queued with its path and marked removed after the deletion',
  exists (select 1 from jsonb_array_elements(hsf_transfer_cleanup_queue(100)) x
           where x ->> 'upload_id' = pg_temp.ctx('up_k') and x ->> 'reason' = 'client_deleted' and x ->> 'storage_path' is not null)
  and hsf_mark_staging_deleted(pg_temp.ctx('up_k')::uuid) ->> 'status' = 'client_deleted');
-- The two year limit waits for a pass that holds an old upload too.
select pg_temp.upload('up_r', 'c1', pg_temp.ctx('sha_r'));
update hsf_upload set uploaded_at = now() - interval '3 years' where id = pg_temp.ctx('up_r')::uuid;
select pg_temp.ok('a scan pass claims R, past the two year limit',
  exists (select 1 from hsf_scan_claim(100) q where q.id = pg_temp.ctx('up_r')::uuid));
select pg_temp.ok('while the pass holds R it is not in the retention queue and cannot expire',
  not exists (select 1 from jsonb_array_elements(hsf_retention_queue(100)) x where x ->> 'upload_id' = pg_temp.ctx('up_r'))
  and pg_temp.error_of(format('select hsf_mark_expired(%L)', pg_temp.ctx('up_r'))) like 'A security scan still holds this upload%');
update hsf_upload set scan_claimed_at = now() - interval '31 minutes' where id = pg_temp.ctx('up_r')::uuid;
select pg_temp.ok('once the hold ends it is queued and expires',
  exists (select 1 from jsonb_array_elements(hsf_retention_queue(100)) x where x ->> 'upload_id' = pg_temp.ctx('up_r'))
  and hsf_mark_expired(pg_temp.ctx('up_r')::uuid) ->> 'status' = 'expired');

select pg_temp.upload('up_p', 'c1', pg_temp.ctx('sha_p'));
select pg_temp.upload('up_q', 'c1', pg_temp.ctx('sha_q'));
select hsf_scan_record(pg_temp.ctx('up_q')::uuid, 'error', 'CNC structural check',
                       '[{"code":"could_not_inspect","message":"The file could not be checked."}]'::jsonb);
update hsf_upload set scan_attempts = 5 where id = pg_temp.ctx('up_q')::uuid;
select pg_temp.act('scan', format('select hsf_staff_scan_list(%L)', pg_temp.ctx('s1')));
select pg_temp.ok('the scan list shows pending and error scans with attempts, findings and the exhausted flag, no file names',
  (select x ->> 'scan_status' = 'pending' and not (x ->> 'scan_exhausted')::boolean
     from jsonb_array_elements(pg_temp.r('scan') -> 'scans') x where x ->> 'upload_id' = pg_temp.ctx('up_p'))
  and (select x ->> 'scan_status' = 'error' and (x ->> 'scan_exhausted')::boolean and (x ->> 'scan_attempts')::int = 5
              and x -> 'scan_findings' -> 0 ->> 'code' = 'could_not_inspect'
              and x ->> 'company_name' = 'Console Test Works (Pty) Ltd'
     from jsonb_array_elements(pg_temp.r('scan') -> 'scans') x where x ->> 'upload_id' = pg_temp.ctx('up_q'))
  and not exists (select 1 from jsonb_array_elements(pg_temp.r('scan') -> 'scans') x
                   where x ->> 'upload_id' in (pg_temp.ctx('up_b'), pg_temp.ctx('up_l')) or x ? 'original_name'));
select pg_temp.ok('the scan list carries the staging alerts with expires_on (Q used all five attempts)',
  jsonb_typeof(pg_temp.r('scan') -> 'staging_alerts') = 'array'
  and (select x ->> 'expires_on' is not null and (x ->> 'scan_exhausted')::boolean
         from jsonb_array_elements(pg_temp.r('scan') -> 'staging_alerts') x where x ->> 'upload_id' = pg_temp.ctx('up_q')));
select pg_temp.refuses('the console scan reset refuses a document that is not waiting for its scan',
  format('select hsf_staff_scan_reset(%L, %L)', pg_temp.ctx('s1'), pg_temp.ctx('up_b')), 'still waiting for its security scan');
select pg_temp.ok('the console scan reset answers P0002 for an unknown upload',
  pg_temp.sqlstate_of(format('select hsf_staff_scan_reset(%L, %L)', pg_temp.ctx('s1'), gen_random_uuid())) = 'P0002');
select pg_temp.act('r', format('select hsf_staff_scan_reset(%L, %L)', pg_temp.ctx('s1'), pg_temp.ctx('up_q')));
select pg_temp.ok('the console scan reset gives Q its attempts back, audited with the staff email',
  pg_temp.r('r') ->> 'scan_attempts' = '0'
  and (select scan_attempts = 0 from hsf_upload where id = pg_temp.ctx('up_q')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_upload_scan_reset' and actor = pg_temp.ctx('s1_email')
                and event_detail ->> 'upload_id' = pg_temp.ctx('up_q') and (event_detail ->> 'attempts_before')::int = 5));

-- 9. Signatories in the console ------------------------------------------------------------------------------

select pg_temp.put('sig_ok', jsonb_build_object(
  'full_name', 'Practitioner form', 'registration_body', 'SAIOSH', 'category', 'GradSAIOSH',
  'registration_number', 'FIXTURE-CON-FORM', 'registration_expires_on', (pg_temp.ctx('day')::date + 365)::text,
  'register_checked_on', (pg_temp.ctx('day')::date - 3)::text, 'register_proof_ref', 'fixture/register-form.pdf',
  'appointment_letter_ref', 'fixture/appointment-form.pdf', 'appointment_letter_date', (pg_temp.ctx('day')::date - 60)::text,
  'engagement_letter_ref', 'fixture/engagement-form.pdf', 'engagement_letter_date', (pg_temp.ctx('day')::date - 60)::text)::text);
create function pg_temp.sig_with(p_patch jsonb) returns text language sql as $$
  select format('select hsf_staff_signatory_save(%L, %L::jsonb)', pg_temp.ctx('s1'), (pg_temp.ctx('sig_ok')::jsonb || p_patch)::text) $$;

select pg_temp.refuses_exactly('the full name is required', pg_temp.sig_with('{"full_name": "  "}'), 'The full name is required.');
select pg_temp.refuses_exactly('an unknown registering body is refused in plain words',
  pg_temp.sig_with('{"registration_body": "NEBOSH"}'), 'The registering body must be SACPCMP or SAIOSH.');
select pg_temp.refuses('a category of the other body is refused in plain words',
  pg_temp.sig_with('{"category": "CHSM"}'), '^A SAIOSH designation must be TechSAIOSH, GradSAIOSH or CMSAIOSH\.$');
select pg_temp.refuses('the registration expiry is required',
  pg_temp.sig_with('{"registration_expires_on": ""}'), '^The registration expiry date is required\.$');
select pg_temp.refuses('a date in another format is refused',
  pg_temp.sig_with('{"registration_expires_on": "30/06/2027"}'), 'must be a date written as YYYY-MM-DD');
select pg_temp.refuses('a date that does not exist is refused',
  pg_temp.sig_with('{"appointment_letter_date": "2026-02-30"}'), 'The appointment letter date is not a real date');
select pg_temp.refuses('a register check date without its proof is refused',
  pg_temp.sig_with('{"register_proof_ref": null}'), 'register check date and the reference of its saved proof together');
select pg_temp.refuses('a register check in the future is refused',
  pg_temp.sig_with(jsonb_build_object('register_checked_on', (pg_temp.ctx('today')::date + 2)::text)), 'cannot be in the future');
select pg_temp.refuses('an engagement letter reference without its date is refused',
  pg_temp.sig_with('{"engagement_letter_date": null}'), 'engagement letter reference and its date together');
select pg_temp.refuses('a reference with a control character is refused',
  pg_temp.sig_with(jsonb_build_object('register_proof_ref', 'fixture/' || chr(10) || 'x.pdf')), 'printable characters');

select pg_temp.act('sig', pg_temp.sig_with('{}'));
select pg_temp.put('sig_form', pg_temp.r('sig') ->> 'id');
select pg_temp.ok('a signatory is created with every 053 field and created_by the staff email, audited',
  pg_temp.r('sig') ->> 'action' = 'created'
  and (select created_by = pg_temp.ctx('s1_email') and category = 'GradSAIOSH' and register_proof_ref = 'fixture/register-form.pdf'
              and appointment_letter_ref is not null and engagement_letter_date is not null
              and appointment_letter_recruitment_portal_ref is null
         from hsf_signatory where id = pg_temp.ctx('sig_form')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_signatory_saved' and actor = pg_temp.ctx('s1_email')
                and event_detail ->> 'signatory_id' = pg_temp.ctx('sig_form') and event_detail ->> 'action' = 'created'));
select pg_temp.refuses_exactly('the same registration period cannot be recorded twice',
  pg_temp.sig_with('{}'), 'A signatory with this registering body, registration number and expiry date is already recorded.');
select pg_temp.act('sig', pg_temp.sig_with(jsonb_build_object('id', pg_temp.ctx('sig_form'), 'full_name', 'Practitioner form corrected',
                                                              'category', 'CMSAIOSH')));
select pg_temp.ok('a correction updates the row and audits the names of the changed fields with the staff email',
  pg_temp.r('sig') ->> 'action' = 'corrected'
  and (select full_name = 'Practitioner form corrected' and category = 'CMSAIOSH' from hsf_signatory where id = pg_temp.ctx('sig_form')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_signatory_saved' and actor = pg_temp.ctx('s1_email')
                and event_detail ->> 'action' = 'corrected' and event_detail -> 'changed' = '["category","full_name"]'::jsonb));
select pg_temp.ok('correcting an unknown signatory answers P0002',
  pg_temp.sqlstate_of(pg_temp.sig_with(jsonb_build_object('id', gen_random_uuid()))) = 'P0002'
  and pg_temp.sqlstate_of(pg_temp.sig_with('{"id": "not-a-uuid"}')) = 'P0002');

-- 10. The register check age rule and the release rules (contract 11.4, 11.5) ---------------------------------

select pg_temp.signatory('sig30', 'CMSAIOSH', 30);
select pg_temp.signatory('sig31', 'GradSAIOSH', 31);
select pg_temp.signatory('sig0', 'TechSAIOSH', 0);

-- F1 revision 1: the register was checked 31 days before the decision day.
select pg_temp.act('so', $q$select pg_temp.signoff('f1', 1, 'safety_content', 'approved',
  jsonb_build_object('signatory_id', pg_temp.ctx('sig31'), 'scope', 'Sections A to O'))$q$);
select pg_temp.ok('31 days: the console names the rule when the sign off is recorded',
  pg_temp.r('so') ->> 'signatory_fit' like 'the SAIOSH register was last checked for Practitioner sig31 on %, more than 30 days before the decision on %'
  and pg_temp.r('so') ->> 'signatory_fit' like '%' || to_char(pg_temp.ctx('day')::date - 31, 'DD/MM/YYYY') || '%');
select pg_temp.signoff('f1', 1, 'client_16_2_acceptance', 'approved',
  '{"signatory_name": "Fixture appointee", "document_ref": "fixture/acceptance-f1-1.pdf"}'::jsonb);
select pg_temp.refuses('31 days before the decision day: the release is refused',
  pg_temp.release_sql('f1', 1),
  '^hsf_release_gate: the safety content sign off cannot release this File: the SAIOSH register was last checked for Practitioner sig31 on .*, more than 30 days before the decision on ');
select pg_temp.ok('the gate raises exactly the first rule hsf_release_rules lists',
  pg_temp.error_of(pg_temp.release_sql('f1', 1)) = hsf_release_rules(pg_temp.ctx('f1')::uuid, 1) -> 0 ->> 'gate'
  and hsf_release_rules(pg_temp.ctx('f1')::uuid, 1) -> 0 ->> 'code' = 'safety_content_unfit');
select pg_temp.act('ready', format('select hsf_release_readiness(%L, 1)', pg_temp.ctx('f1')));
select pg_temp.ok('readiness says not ready and gives the same rule in plain words',
  not (pg_temp.r('ready') ->> 'ready')::boolean and not (pg_temp.r('ready') ->> 'released')::boolean
  and jsonb_array_length(pg_temp.r('ready') -> 'missing') = 1
  and pg_temp.r('ready') -> 'missing' ->> 0 like 'The safety content sign off cannot release this File: the SAIOSH register was last checked for Practitioner sig31 on %, more than 30 days before the decision on %.');

-- F1 revision 2: checked exactly 30 days before the decision day.
select pg_temp.act('so', $q$select pg_temp.signoff('f1', 2, 'safety_content', 'approved',
  jsonb_build_object('signatory_id', pg_temp.ctx('sig30'), 'scope', 'Sections A to O'))$q$);
select pg_temp.ok('30 days: the sign off fits, and without the client acceptance the readiness names only that',
  pg_temp.r('so') -> 'signatory_fit' = 'null'::jsonb
  and pg_temp.r('so') -> 'readiness' -> 'missing' = '["The client''s section 16(2) acceptance is not approved for this revision."]'::jsonb);
select pg_temp.act('so', $q$select pg_temp.signoff('f1', 2, 'client_16_2_acceptance', 'approved',
  '{"signatory_name": "Fixture appointee", "document_ref": "fixture/acceptance-f1-2.pdf"}'::jsonb)$q$);
select pg_temp.ok('the sign off reply carries the readiness: ready',
  (pg_temp.r('so') -> 'readiness' ->> 'ready')::boolean and pg_temp.r('so') -> 'readiness' -> 'missing' = '[]'::jsonb);
select pg_temp.put('rel_before', (select count(*) from hsf_release)::text);
select pg_temp.put('so_before', (select count(*) from hsf_signoff)::text);
select pg_temp.ok('readiness writes nothing',
  (hsf_release_readiness(pg_temp.ctx('f1')::uuid, 2) ->> 'ready')::boolean
  and (hsf_release_readiness(pg_temp.ctx('f2')::uuid, null) ->> 'revision')::int = 1
  and (select count(*) from hsf_release) = pg_temp.ctx('rel_before')::int
  and (select count(*) from hsf_signoff) = pg_temp.ctx('so_before')::int);
select pg_temp.ok('exactly 30 days before the decision day: the release is accepted',
  pg_temp.sqlstate_of(pg_temp.release_sql('f1', 2)) is null);
select pg_temp.ok('after the release, readiness reads released',
  (hsf_release_readiness(pg_temp.ctx('f1')::uuid, 2) ->> 'released')::boolean);

-- F1 revision 3: checked on the decision day itself.
select pg_temp.signoff('f1', 3, 'safety_content', 'approved',
  jsonb_build_object('signatory_id', pg_temp.ctx('sig0'), 'scope', 'Sections A to O'));
select pg_temp.signoff('f1', 3, 'client_16_2_acceptance', 'approved',
  '{"signatory_name": "Fixture appointee", "document_ref": "fixture/acceptance-f1-3.pdf"}'::jsonb);
select pg_temp.ok('a register check on the decision day itself counts',
  (hsf_release_readiness(pg_temp.ctx('f1')::uuid, 3) ->> 'ready')::boolean);

-- The parameter moves the boundary, and is held between 1 and 365.
update msp_env_parameter set value = '31' where key = 'hsf.signoff_register_check_max_days';
select pg_temp.ok('with the parameter at 31, the check 31 days before now counts',
  (hsf_release_readiness(pg_temp.ctx('f1')::uuid, 1) ->> 'ready')::boolean);
update msp_env_parameter set value = '29' where key = 'hsf.signoff_register_check_max_days';
select pg_temp.ok('with the parameter at 29, the check 30 days before no longer counts; the check on the day still does',
  hsf_signatory_fit((select id from hsf_signoff where file_id = pg_temp.ctx('f1')::uuid and revision = 2
                       and kind = 'safety_content')) like '%more than 29 days before the decision%'
  and (hsf_release_readiness(pg_temp.ctx('f1')::uuid, 3) ->> 'ready')::boolean);
update msp_env_parameter set value = '0' where key = 'hsf.signoff_register_check_max_days';
select pg_temp.ok('a stored value under 1 reads as 1', hsf_signoff_register_check_max_days() = 1);
update msp_env_parameter set value = '1000' where key = 'hsf.signoff_register_check_max_days';
select pg_temp.ok('a stored value over 365 reads as 365', hsf_signoff_register_check_max_days() = 365);
update msp_env_parameter set value = '30' where key = 'hsf.signoff_register_check_max_days';

-- F2: nothing recorded, and an instrument that is not citable. Readiness lists
-- every unmet rule in the gate's order; the gate raises the first.
select pg_temp.act('ready', format('select hsf_release_readiness(%L, 1)', pg_temp.ctx('f2')));
select pg_temp.ok('readiness lists all three unmet rules in plain words, in the gate''s order',
  pg_temp.r('ready') -> 'missing' = jsonb_build_array(
    'No approved safety content sign off by a registered practitioner is recorded for this revision.',
    'The client''s section 16(2) acceptance is not approved for this revision.',
    'The File cites instruments not yet verified for a File: OHS Act.')
  and not (pg_temp.r('ready') ->> 'ready')::boolean);
select pg_temp.ok('the rules carry their codes, and the gate raises the first with the 053 wording',
  (select jsonb_agg(x ->> 'code') from jsonb_array_elements(hsf_release_rules(pg_temp.ctx('f2')::uuid, 1)) x)
    = '["safety_content_missing","client_acceptance_missing","instruments_not_citable"]'::jsonb
  and pg_temp.error_of(pg_temp.release_sql('f2', 1)) = 'hsf_release_gate: safety_content sign off is not approved for this File revision');
select pg_temp.ok('readiness answers P0002 for an unknown File',
  pg_temp.sqlstate_of(format('select hsf_release_readiness(%L, 1)', gen_random_uuid())) = 'P0002');

-- 11. Sign offs through the console (contract 11.5) --------------------------------------------------------

select pg_temp.refuses_exactly('omp_medical is refused in plain words',
  $q$select pg_temp.signoff('f1', 4, 'omp_medical', 'approved', '{"signatory_name": "Fixture OMP", "document_ref": "x.pdf"}'::jsonb)$q$,
  'The Occupational Medical Practitioner does not sign a File. File the signed medical surveillance plan in Section E as evidence instead.');
select pg_temp.refuses('an unknown kind is refused',
  $q$select pg_temp.signoff('f1', 4, 'director_signoff', 'approved', '{}'::jsonb)$q$, 'must be safety_content, client_16_2_acceptance or ceo_16_1_acknowledgement');
select pg_temp.refuses('an unknown decision is refused',
  $q$select pg_temp.signoff('f1', 4, 'client_16_2_acceptance', 'noted', '{"signatory_name": "A", "document_ref": "x.pdf"}'::jsonb)$q$,
  'must be approved, amended or rejected');
select pg_temp.refuses('a decision in the future is refused',
  format('select hsf_staff_signoff_record(%L, %L::jsonb)', pg_temp.ctx('s1'), jsonb_build_object(
    'file_id', pg_temp.ctx('f1'), 'kind', 'client_16_2_acceptance', 'decision', 'approved',
    'decided_at', (now() + interval '2 days')::text, 'signatory_name', 'A', 'document_ref', 'x.pdf')), 'cannot be in the future');
select pg_temp.refuses('a decision date that is not a date is refused',
  format('select hsf_staff_signoff_record(%L, %L::jsonb)', pg_temp.ctx('s1'), jsonb_build_object(
    'file_id', pg_temp.ctx('f1'), 'kind', 'client_16_2_acceptance', 'decision', 'approved',
    'decided_at', 'yesterday afternoon', 'signatory_name', 'A', 'document_ref', 'x.pdf')), 'not a real date');
select pg_temp.refuses('a safety content sign off needs its signatory',
  $q$select pg_temp.signoff('f1', 4, 'safety_content', 'approved', '{"scope": "Sections A to O"}'::jsonb)$q$, 'Choose the signatory');
select pg_temp.ok('an unknown signatory answers P0002',
  pg_temp.sqlstate_of($q$select pg_temp.signoff('f1', 4, 'safety_content', 'approved',
    jsonb_build_object('signatory_id', gen_random_uuid(), 'scope', 'Sections A to O'))$q$) = 'P0002');
select pg_temp.refuses('a safety content sign off needs its scope',
  $q$select pg_temp.signoff('f1', 4, 'safety_content', 'approved', jsonb_build_object('signatory_id', pg_temp.ctx('sig30')))$q$,
  'The scope of the sign off is required');
select pg_temp.refuses('the client acceptance needs the reference of the signed acceptance document',
  $q$select pg_temp.signoff('f1', 4, 'client_16_2_acceptance', 'approved', '{"signatory_name": "Fixture appointee"}'::jsonb)$q$,
  'The reference of the signed acceptance document is required');
select pg_temp.refuses('the chief executive acknowledgement needs the name of the person who signed',
  $q$select pg_temp.signoff('f1', 4, 'ceo_16_1_acknowledgement', 'approved', '{"document_ref": "fixture/ack.pdf"}'::jsonb)$q$,
  'The name of the person who signed is required');
select pg_temp.refuses('a revision beyond the File''s current revision is refused',
  $q$select pg_temp.signoff('f1', 5, 'client_16_2_acceptance', 'approved', '{"signatory_name": "A", "document_ref": "x.pdf"}'::jsonb)$q$,
  'whole number from 1 to 4');
select pg_temp.refuses('a released revision takes no new sign off',
  $q$select pg_temp.signoff('f1', 2, 'client_16_2_acceptance', 'rejected', '{"signatory_name": "A", "document_ref": "x.pdf"}'::jsonb)$q$,
  'Revision 2 of this File is already released');
select pg_temp.ok('an unknown File answers P0002',
  pg_temp.sqlstate_of(format('select hsf_staff_signoff_record(%L, %L::jsonb)', pg_temp.ctx('s1'),
    jsonb_build_object('file_id', gen_random_uuid(), 'kind', 'client_16_2_acceptance'))) = 'P0002');

select pg_temp.act('so', format('select hsf_staff_signoff_record(%L, %L::jsonb)', pg_temp.ctx('s2'), jsonb_build_object(
  'file_id', pg_temp.ctx('f1'), 'kind', 'ceo_16_1_acknowledgement', 'decision', 'approved', 'decided_at', pg_temp.ctx('dec'),
  'signatory_name', 'Fixture chief executive', 'document_ref', 'fixture/acknowledgement-f1-4.pdf')));
select pg_temp.ok('without a revision the current one is used; recorded_by and the audit carry the staff email',
  (pg_temp.r('so') ->> 'revision')::int = 4 and pg_temp.r('so') ->> 'recorded_by' = pg_temp.ctx('s2_email')
  and pg_temp.r('so') -> 'signatory_fit' = 'null'::jsonb
  and (select document_ref = 'fixture/acknowledgement-f1-4.pdf'
              and signatory_name = 'Fixture chief executive' and kind = 'ceo_16_1_acknowledgement'
              and to_jsonb(so)::text not like '%' || pg_temp.ctx('s2_email') || '%'
         from hsf_signoff so where id = (pg_temp.r('so') ->> 'signoff_id')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_signoff_recorded' and actor = pg_temp.ctx('s2_email')
                and hsf_file_id = pg_temp.ctx('f1')::uuid and event_detail ->> 'signoff_id' = pg_temp.r('so') ->> 'signoff_id'));
select pg_temp.ok('the chief executive acknowledgement is recorded, not a gate: revision 4 still misses the two required sign offs',
  pg_temp.r('so') -> 'readiness' -> 'missing' = jsonb_build_array(
    'No approved safety content sign off by a registered practitioner is recorded for this revision.',
    'The client''s section 16(2) acceptance is not approved for this revision.'));
select pg_temp.ok('a safety content sign off copies the signatory''s name, body and number (053) and records the scope',
  (select signatory_name = 'Practitioner sig30' and registration_body = 'SAIOSH' and registration_number = 'FIXTURE-CON-SIG30'
          and scope = 'Sections A to O'
     from hsf_signoff where file_id = pg_temp.ctx('f1')::uuid and revision = 2 and kind = 'safety_content'));

-- Review finding SEC-3: the client whose account owns the File reads its sign
-- offs, and never the email of the staff member who entered them.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "c1111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select pg_temp.put('client_signoffs', (select coalesce(jsonb_agg(to_jsonb(so)), '[]'::jsonb)::text from hsf_signoff so));
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('the client reads the sign offs of its File with their document references, and no staff email',
  jsonb_array_length(pg_temp.ctx('client_signoffs')::jsonb) >= 4
  and pg_temp.ctx('client_signoffs') like '%fixture/acknowledgement-f1-4.pdf%'
  and pg_temp.ctx('client_signoffs') not like '%' || pg_temp.ctx('s1_email') || '%'
  and pg_temp.ctx('client_signoffs') not like '%' || pg_temp.ctx('s2_email') || '%'
  and not exists (select 1 from jsonb_array_elements(pg_temp.ctx('client_signoffs')::jsonb) x where x ? 'recorded_by'));

-- Credentials relied on by the release of revision 2 are frozen (053), in plain words.
select pg_temp.refuses_exactly('the console refuses to change frozen credentials, in plain words',
  pg_temp.sig_with(jsonb_build_object('id', pg_temp.ctx('sig30'), 'full_name', 'Practitioner sig30', 'category', 'CMSAIOSH',
    'registration_number', 'FIXTURE-CON-SIG30', 'register_checked_on', (pg_temp.ctx('day')::date - 1)::text)),
  'These credentials support a released File and cannot be changed. Record a renewal or a correction as a new signatory.');
select pg_temp.put('sig30_form', (select (to_jsonb(s) - 'id' - 'created_by' - 'created_at')::text from hsf_signatory s where s.id = pg_temp.ctx('sig30')::uuid));
select pg_temp.ok('the recruitment portal reference of a letter is added once after the release',
  hsf_staff_signatory_save(pg_temp.ctx('s1')::uuid, pg_temp.ctx('sig30_form')::jsonb
    || jsonb_build_object('id', pg_temp.ctx('sig30'), 'appointment_letter_recruitment_portal_ref', 'FIXTURE-PORTAL-1'))
    ->> 'appointment_letter_recruitment_portal_ref' = 'FIXTURE-PORTAL-1');
select pg_temp.refuses_exactly('and is never changed afterwards',
  format('select hsf_staff_signatory_save(%L, %L::jsonb)', pg_temp.ctx('s1'), (pg_temp.ctx('sig30_form')::jsonb
    || jsonb_build_object('id', pg_temp.ctx('sig30'), 'appointment_letter_recruitment_portal_ref', 'FIXTURE-PORTAL-2'))::text),
  'A recruitment portal reference on credentials that support a released File is set once and never changed.');

select pg_temp.act('list', format('select hsf_staff_signatory_list(%L)', pg_temp.ctx('s1')));
select pg_temp.ok('the signatory list shows every field, frozen, the register check age and whether it is current',
  (select (x ->> 'frozen')::boolean and not (x ->> 'expired')::boolean and (x ->> 'signoffs')::int = 1
          and (x ->> 'register_check_age_days')::int = pg_temp.ctx('today')::date - (pg_temp.ctx('day')::date - 30)
          and (x ->> 'letters_on_record')::boolean and x ? 'engagement_letter_recruitment_portal_ref'
          and x ->> 'appointment_letter_recruitment_portal_ref' = 'FIXTURE-PORTAL-1'
     from jsonb_array_elements(pg_temp.r('list')) x where x ->> 'id' = pg_temp.ctx('sig30'))
  and (select not (x ->> 'frozen')::boolean and not (x ->> 'register_check_current')::boolean
     from jsonb_array_elements(pg_temp.r('list')) x where x ->> 'id' = pg_temp.ctx('sig31'))
  and (select (x ->> 'register_check_current')::boolean
     from jsonb_array_elements(pg_temp.r('list')) x where x ->> 'id' = pg_temp.ctx('sig_form')));

-- Review finding F1: a fresh register check on credentials a release froze.
-- The check the release relied on stays on the row; the new one is appended,
-- dated, with the staff email, and the release rules read it.
select pg_temp.put('sig30_form', (select (to_jsonb(s) - 'id' - 'created_by' - 'created_at' - 'register_rechecks')::text
                                    from hsf_signatory s where s.id = pg_temp.ctx('sig30')::uuid));
update msp_env_parameter set value = '29' where key = 'hsf.signoff_register_check_max_days';
select pg_temp.put('so30', (select id::text from hsf_signoff where file_id = pg_temp.ctx('f1')::uuid and revision = 2 and kind = 'safety_content'));
select pg_temp.ok('with the limit at 29 days, the old check of sig30 no longer fits a decision on the decision day',
  hsf_signatory_fit(pg_temp.ctx('so30')::uuid) like '%more than 29 days before the decision%');
select pg_temp.refuses_exactly('a register check dated on or before the last one is refused in plain words',
  format('select hsf_staff_signatory_save(%L, %L::jsonb)', pg_temp.ctx('s1'), (pg_temp.ctx('sig30_form')::jsonb
    || jsonb_build_object('id', pg_temp.ctx('sig30'), 'register_proof_ref', 'fixture/register-sig30-again.pdf'))::text),
  format('A new register check on credentials that support a released File must be dated after the last one on record (%s), with the reference of its saved proof.',
         to_char(pg_temp.ctx('day')::date - 30, 'DD/MM/YYYY')));
select pg_temp.act('sig', format('select hsf_staff_signatory_save(%L, %L::jsonb)', pg_temp.ctx('s1'), (pg_temp.ctx('sig30_form')::jsonb
    || jsonb_build_object('id', pg_temp.ctx('sig30'), 'register_checked_on', pg_temp.ctx('day'),
                          'register_proof_ref', 'fixture/register-sig30-recheck.pdf'))::text));
select pg_temp.ok('a later register check is appended: the row keeps the check the release relied on',
  pg_temp.r('sig') ->> 'action' = 'register_checked'
  and pg_temp.r('sig') ->> 'register_checked_on' = pg_temp.ctx('day')
  and (select register_checked_on = pg_temp.ctx('day')::date - 30 and register_proof_ref = 'fixture/register-sig30.pdf'
              and jsonb_array_length(register_rechecks) = 1
              and register_rechecks -> 0 ->> 'checked_on' = pg_temp.ctx('day')
              and register_rechecks -> 0 ->> 'proof_ref' = 'fixture/register-sig30-recheck.pdf'
              and register_rechecks -> 0 ->> 'recorded_by' = pg_temp.ctx('s1_email')
         from hsf_signatory where id = pg_temp.ctx('sig30')::uuid)
  and exists (select 1 from msp_audit where event_type = 'hsf_signatory_saved' and actor = pg_temp.ctx('s1_email')
                and event_detail ->> 'signatory_id' = pg_temp.ctx('sig30') and event_detail -> 'changed' = '["register_rechecks"]'::jsonb));
select pg_temp.ok('the release rules read the latest check on or before the decision day: sig30 fits again',
  hsf_signatory_fit(pg_temp.ctx('so30')::uuid) is null);
select pg_temp.act('list', format('select hsf_staff_signatory_list(%L)', pg_temp.ctx('s1')));
select pg_temp.ok('the list shows the latest check, its age and the limit the gate applies (29 days here)',
  (select x ->> 'register_checked_on' = pg_temp.ctx('day') and x ->> 'register_proof_ref' = 'fixture/register-sig30-recheck.pdf'
          and (x ->> 'register_checks')::int = 2 and (x ->> 'register_check_current')::boolean
          and (x ->> 'register_check_max_days')::int = 29
     from jsonb_array_elements(pg_temp.r('list')) x where x ->> 'id' = pg_temp.ctx('sig30')));
update msp_env_parameter set value = '30' where key = 'hsf.signoff_register_check_max_days';
select pg_temp.ok('saving the form again with the check it shows changes nothing',
  hsf_staff_signatory_save(pg_temp.ctx('s1')::uuid, (select (x - 'frozen' - 'expired' - 'days_to_expiry' - 'register_checks'
      - 'register_check_age_days' - 'register_check_current' - 'register_check_max_days' - 'letters_on_record' - 'signoffs')
    from jsonb_array_elements(pg_temp.r('list')) x where x ->> 'id' = pg_temp.ctx('sig30'))) ->> 'action' = 'corrected'
  and (select jsonb_array_length(register_rechecks) = 1 from hsf_signatory where id = pg_temp.ctx('sig30')::uuid));
select pg_temp.refuses('the database refuses a register check that is changed or removed',
  format('update hsf_signatory set register_rechecks = ''[]''::jsonb where id = %L', pg_temp.ctx('sig30')), 'appended, never changed or removed');
select pg_temp.refuses('the database refuses an appended check dated before the last one',
  format('update hsf_signatory set register_rechecks = register_rechecks || %L::jsonb where id = %L',
         jsonb_build_array(jsonb_build_object('checked_on', pg_temp.ctx('day')::date - 1, 'proof_ref', 'x.pdf')), pg_temp.ctx('sig30')),
  'needs a date after the last check');

-- 12. Files and readiness in the console ----------------------------------------------------------------

select pg_temp.act('files', format('select hsf_staff_file_list(%L)', pg_temp.ctx('s1')));
select pg_temp.ok('the File list shows company, industry, revision, compliance, the latest sign offs and readiness',
  (select x ->> 'company_name' = 'Console Test Works (Pty) Ltd' and x ->> 'industry_code' = 'MANU' and x ? 'industry_name'
          and (x ->> 'revision')::int = 4 and x ? 'compliance_pct' and x ->> 'reference' is not null
          and x -> 'signoffs' -> 'ceo_16_1_acknowledgement' ->> 'decision' = 'approved'
          and x -> 'signoffs' -> 'ceo_16_1_acknowledgement' ->> 'recorded_by' = pg_temp.ctx('s2_email')
          and not x -> 'signoffs' ? 'safety_content'
          and x -> 'readiness' = hsf_release_readiness(pg_temp.ctx('f1')::uuid, 4)
     from jsonb_array_elements(pg_temp.r('files')) x where x ->> 'file_id' = pg_temp.ctx('f1'))
  and (select not (x -> 'readiness' ->> 'ready')::boolean and jsonb_array_length(x -> 'readiness' -> 'missing') = 3
     from jsonb_array_elements(pg_temp.r('files')) x where x ->> 'file_id' = pg_temp.ctx('f2')));

-- 13. Signatory expiry alerts (contract 11.4) --------------------------------------------------------------

-- Registrations relative to today (South African day): 60 days out (listed), 61
-- days out (not), expired yesterday (listed), an old period renewed with nothing
-- unreleased (not listed) and one renewed with an unreleased File (listed).
insert into hsf_signatory (id, full_name, registration_body, category, registration_number, registration_expires_on)
values
  ('c5000060-0000-4000-8000-000000000060', 'Alert sixty', 'SAIOSH', 'CMSAIOSH', 'FIXTURE-ALERT-60', pg_temp.ctx('today')::date + 60),
  ('c5000061-0000-4000-8000-000000000061', 'Alert sixty one', 'SAIOSH', 'CMSAIOSH', 'FIXTURE-ALERT-61', pg_temp.ctx('today')::date + 61),
  ('c5000001-0000-4000-8000-000000000001', 'Alert expired', 'SAIOSH', 'GradSAIOSH', 'FIXTURE-ALERT-EXP', pg_temp.ctx('today')::date - 1),
  ('c5000002-0000-4000-8000-000000000002', 'Alert renewed', 'SACPCMP', 'CHSM', 'FIXTURE-ALERT-REN', pg_temp.ctx('today')::date - 400),
  ('c5000003-0000-4000-8000-000000000003', 'Alert renewed', 'SACPCMP', 'CHSM', 'FIXTURE-ALERT-REN', pg_temp.ctx('today')::date + 300),
  ('c5000004-0000-4000-8000-000000000004', 'Alert pending', 'SAIOSH', 'TechSAIOSH', 'FIXTURE-ALERT-PEN', pg_temp.ctx('today')::date - 10),
  ('c5000005-0000-4000-8000-000000000005', 'Alert pending', 'SAIOSH', 'TechSAIOSH', 'FIXTURE-ALERT-PEN', pg_temp.ctx('today')::date + 700);
-- Alert pending's old period signed F2 revision 1 (not released) and the
-- released F1 revision 2; alert sixty signed the released F1 revision 2 only.
insert into hsf_signoff (file_id, revision, kind, decision, signatory_id, scope, decided_at) values
  (pg_temp.ctx('f2')::uuid, 1, 'safety_content', 'approved', 'c5000004-0000-4000-8000-000000000004', 'Sections A to O', now() - interval '20 days'),
  (pg_temp.ctx('f1')::uuid, 2, 'safety_content', 'approved', 'c5000004-0000-4000-8000-000000000004', 'Sections A to O', now() - interval '20 days'),
  (pg_temp.ctx('f1')::uuid, 2, 'safety_content', 'approved', 'c5000060-0000-4000-8000-000000000060', 'Sections A to O', now() - interval '2 days');
select pg_temp.act('alerts', 'select hsf_signatory_expiry_alerts_list()');
select pg_temp.ok('alerts: 60 days out, expired, and a renewed period an unreleased File rests on; not 61 days out or a renewed period with nothing pending',
  (select jsonb_agg(x ->> 'registration_number' order by x ->> 'registration_number') from jsonb_array_elements(pg_temp.r('alerts')) x
    where x ->> 'registration_number' like 'FIXTURE-ALERT-%')
  = '["FIXTURE-ALERT-60","FIXTURE-ALERT-EXP","FIXTURE-ALERT-PEN"]'::jsonb);
select pg_temp.ok('an alert carries the days to expiry and whether it has expired or been renewed',
  (select (x ->> 'days_to_expiry')::int = 60 and not (x ->> 'expired')::boolean and not (x ->> 'renewed')::boolean
     from jsonb_array_elements(pg_temp.r('alerts')) x where x ->> 'signatory_id' = 'c5000060-0000-4000-8000-000000000060')
  and (select (x ->> 'days_to_expiry')::int = -1 and (x ->> 'expired')::boolean
     from jsonb_array_elements(pg_temp.r('alerts')) x where x ->> 'signatory_id' = 'c5000001-0000-4000-8000-000000000001')
  and (select (x ->> 'renewed')::boolean and (x ->> 'expired')::boolean
     from jsonb_array_elements(pg_temp.r('alerts')) x where x ->> 'signatory_id' = 'c5000004-0000-4000-8000-000000000004'));
select pg_temp.ok('the unreleased Files are listed with reference, revision and company; a released revision is not',
  (select jsonb_array_length(x -> 'unreleased_files') = 1 and x -> 'unreleased_files' -> 0 ->> 'file_id' = pg_temp.ctx('f2')
          and (x -> 'unreleased_files' -> 0 ->> 'revision')::int = 1
          and x -> 'unreleased_files' -> 0 ->> 'company_name' = 'Console Test Works (Pty) Ltd'
          and x -> 'unreleased_files' -> 0 ->> 'reference' is not null
     from jsonb_array_elements(pg_temp.r('alerts')) x where x ->> 'signatory_id' = 'c5000004-0000-4000-8000-000000000004')
  and (select x -> 'unreleased_files' = '[]'::jsonb
     from jsonb_array_elements(pg_temp.r('alerts')) x where x ->> 'signatory_id' = 'c5000060-0000-4000-8000-000000000060'));
select pg_temp.ok('the console alerts are the same list',
  hsf_staff_signatory_alerts(pg_temp.ctx('s2')::uuid) = hsf_signatory_expiry_alerts_list());

-- The view as the web tier would see it.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "c1111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select pg_temp.put('client_alerts', (select count(*) from hsf_signatory_expiry_alerts)::text);
select set_config('request.jwt.claims', '{"sub": "c2222222-2222-4222-8222-222222222222", "role": "authenticated", "app_metadata": {"msp_roles": ["forge_safety_reviewer"]}}', true);
select pg_temp.put('staff_alerts', (select count(*) from hsf_signatory_expiry_alerts)::text);
select pg_temp.put('staff_pending', (select unreleased_files::text from hsf_signatory_expiry_alerts
                                      where signatory_id = 'c5000004-0000-4000-8000-000000000004'));
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('a client reads no expiry alert',  pg_temp.ctx('client_alerts') = '0');
select pg_temp.ok('staff read every alert through the view, with the unreleased Files',
  pg_temp.ctx('staff_alerts')::int = jsonb_array_length(hsf_signatory_expiry_alerts_list())
  and pg_temp.ctx('staff_pending')::jsonb -> 0 ->> 'file_id' = pg_temp.ctx('f2'));

do $$ begin raise notice 'hsf_console_checks: all checks passed. Rolling back the test data.'; end $$;
rollback;
