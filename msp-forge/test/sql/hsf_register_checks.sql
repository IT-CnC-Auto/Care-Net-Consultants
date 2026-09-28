-- CNC MSP FORGE | HSF-NAME-01 step 4, File only company registration checks | local test harness only.
-- Proves step 4 of migration 056 (build contract section 15) against a replayed
-- database. A company registered from the Health and Safety File builder
-- (hsf_client_register, which /api/signon calls when the body carries source
-- 'hsf') gets its company account and nothing of the Medical Surveillance Plan:
-- no approval, no assessment token in msp_form_access, no client_self_approved
-- or form_access_granted audit row. The account, left an applicant, links to its
-- signed in contact (hsf_link_account, what lib/auth.js requireUser calls), gives
-- its consent, generates a File, asks for verification and, once verified with
-- uploads open, registers an upload; the portal summary shows it with no Plan.
-- If that contact later chooses the Plan, msp_client_start_assessment (what
-- /api/company-lookup calls on the Plan landing) approves the account and issues
-- one token, as for any account, and the File stays linked. msp_client_signon,
-- the Plan landing's path, is unchanged. Running 056 a second time changes no
-- row and leaves the function as it was. Every check is about the rows this file
-- makes, or compares a count with what the database held before it ran, so the
-- file also passes on a database where hsf_client_register has run before (the
-- audit trail is append only). Never applied to Supabase. Everything
-- runs in one transaction that is rolled back, so the fictitious auth users,
-- company accounts and Files it creates never persist.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_register_checks.sql
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
-- runs as its own statement, so it sees what the action wrote.
create function pg_temp.act(p_k text, p_sql text) returns void language plpgsql as $$
declare
  v jsonb;
begin
  execute p_sql into v;
  perform pg_temp.put(p_k, v::text);
end $$;
create function pg_temp.r(p_k text) returns jsonb language sql as $$ select v::jsonb from ctx where k = p_k $$;

-- Nothing of the Plan for one account: still an applicant with no approver, no
-- assessment token, and no Plan sign on or approval in the audit trail.
create function pg_temp.no_plan(p_acc uuid) returns boolean language sql as $$
  select exists (select 1 from msp_client_account a where a.id = p_acc
                   and a.account_kind = 'applicant' and a.approved_by is null and a.approved_at is null)
     and not exists (select 1 from msp_form_access fa where fa.client_account_id = p_acc)
     and not exists (select 1 from msp_audit x
                      where x.event_type in ('client_signon', 'client_signon_repeat', 'client_self_approved')
                        and x.event_detail ->> 'client_account_id' = p_acc::text)
$$;

-- What the Plan side holds before any registration here, to show none is added.
select pg_temp.put('fa_before', (select count(*) from msp_form_access)::text);
select pg_temp.put('granted_before', (select count(*) from msp_audit where event_type = 'form_access_granted')::text);
select pg_temp.put('approved_before', (select count(*) from msp_audit where event_type = 'client_self_approved')::text);
-- The same for File registrations and this file's own fixture email, so the checks
-- hold on a database where hsf_client_register has run before (msp_audit is append only).
select pg_temp.put('register_audit_before', (select count(*) from msp_audit where event_type like 'hsf_client_register%')::text);
select pg_temp.put('reg_accounts_before', (select count(*) from msp_client_account where lower(contact_email) = 'reg.client@example.invalid')::text);

-- 1. The function, its settings and its grant -----------------------------------------------

select pg_temp.ok('hsf_client_register(jsonb) returns jsonb and is security definer with search_path=public',
  exists (select 1 from pg_proc p where p.oid = 'hsf_client_register(jsonb)'::regprocedure
            and p.prorettype = 'jsonb'::regtype and p.prosecdef
            and exists (select 1 from unnest(p.proconfig) c where c = 'search_path=public')));
select pg_temp.ok('hsf_client_register is service role only (public, anon and authenticated refused, as msp_client_signon)',
  has_function_privilege('service_role', 'hsf_client_register(jsonb)', 'execute')
  and not has_function_privilege('public', 'hsf_client_register(jsonb)', 'execute')
  and not has_function_privilege('anon', 'hsf_client_register(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'hsf_client_register(jsonb)', 'execute')
  and not has_function_privilege('anon', 'msp_client_signon(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'msp_client_signon(jsonb)', 'execute'));
select pg_temp.ok('its body never reaches the Plan: no msp_client_start_assessment, msp_grant_access, msp_form_access or approval',
  (select p.prosrc !~* 'msp_client_start_assessment|msp_grant_access|msp_form_access|approv|token'
          and p.prosrc !~* 'set[[:space:]][^;]*account_kind'
     from pg_proc p where p.oid = 'hsf_client_register(jsonb)'::regprocedure));

-- 2. The same validation as msp_client_signon -----------------------------------------------

select pg_temp.refuses('a registration without a company name is refused',
  $q$select hsf_client_register('{"company_name":"  ","contact_name":"Reg Tester","contact_email":"reg.client@example.invalid"}'::jsonb)$q$, 'required');
select pg_temp.refuses('a registration without a contact name is refused',
  $q$select hsf_client_register('{"company_name":"Register Test Scaffolding (Pty) Ltd","contact_email":"reg.client@example.invalid"}'::jsonb)$q$, 'required');
select pg_temp.refuses('a registration without an email is refused',
  $q$select hsf_client_register('{"company_name":"Register Test Scaffolding (Pty) Ltd","contact_name":"Reg Tester","contact_email":" "}'::jsonb)$q$, 'required');
select pg_temp.refuses('a contact number over 40 characters is refused',
  format('select hsf_client_register(%L::jsonb)', jsonb_build_object('company_name', 'Register Test Scaffolding (Pty) Ltd',
         'contact_name', 'Reg Tester', 'contact_email', 'reg.client@example.invalid', 'contact_number', repeat('1', 41))), 'too long');
select pg_temp.ok('the refusals wrote no account and no audit row',
  (select count(*) from msp_client_account where lower(contact_email) = 'reg.client@example.invalid') = pg_temp.ctx('reg_accounts_before')::bigint
  and (select count(*) from msp_audit where event_type like 'hsf_client_register%') = pg_temp.ctx('register_audit_before')::bigint);

-- 3. A new registration: the account, and nothing of the Plan --------------------------------

select pg_temp.act('reg1', $q$select hsf_client_register('{"company_name":"  Register Test Scaffolding (Pty) Ltd ","contact_name":" Reg Tester ","contact_email":"  Reg.Client@Example.INVALID ","contact_number":" +27 10 000 0001 ","notes":"Registered from the Health and Safety File builder"}'::jsonb)$q$);
select pg_temp.put('acc', pg_temp.r('reg1') ->> 'reference');

select pg_temp.ok('the answer carries status, reference, existing, company_name, contact_number and declined, and nothing else (no token)',
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.r('reg1')) k)
    = array['company_name', 'contact_number', 'declined', 'existing', 'reference', 'status']);
select pg_temp.ok('a new registration is received, not existing, not declined, with the trimmed details',
  pg_temp.r('reg1') ->> 'status' = 'received'
  and pg_temp.r('reg1') -> 'existing' = 'false'::jsonb
  and pg_temp.r('reg1') -> 'declined' = 'false'::jsonb
  and pg_temp.r('reg1') ->> 'company_name' = 'Register Test Scaffolding (Pty) Ltd'
  and pg_temp.r('reg1') ->> 'contact_number' = '+27 10 000 0001');
select pg_temp.ok('the account holds the details, the email in lower case, and no auth user yet',
  exists (select 1 from msp_client_account a where a.id = pg_temp.ctx('acc')::uuid
            and a.company_name = 'Register Test Scaffolding (Pty) Ltd' and a.contact_name = 'Reg Tester'
            and a.contact_email = 'reg.client@example.invalid' and a.contact_number = '+27 10 000 0001'
            and a.notes = 'Registered from the Health and Safety File builder' and a.auth_user_id is null));
select pg_temp.ok('the account is not approved and has no Plan assessment token (msp_form_access)',
  pg_temp.no_plan(pg_temp.ctx('acc')::uuid));
select pg_temp.ok('no assessment token, access grant or approval was made anywhere',
  (select count(*) from msp_form_access) = pg_temp.ctx('fa_before')::bigint
  and (select count(*) from msp_audit where event_type = 'form_access_granted') = pg_temp.ctx('granted_before')::bigint
  and (select count(*) from msp_audit where event_type = 'client_self_approved') = pg_temp.ctx('approved_before')::bigint);
select pg_temp.ok('audited once as hsf_client_register, with the account, company and email',
  (select count(*) = 1 from msp_audit x where x.event_type = 'hsf_client_register' and x.actor = 'signon'
      and x.event_detail ->> 'client_account_id' = pg_temp.ctx('acc')
      and x.event_detail ->> 'company' = 'Register Test Scaffolding (Pty) Ltd'
      and x.event_detail ->> 'email' = 'reg.client@example.invalid'));

-- 4. A repeat registration: the same account, only a missing number filled in ----------------

select pg_temp.act('reg2', $q$select hsf_client_register('{"company_name":"Another Name (Pty) Ltd","contact_name":"Someone Else","contact_email":" REG.client@example.invalid","contact_number":"+27 10 000 0009","notes":"Something else"}'::jsonb)$q$);
select pg_temp.ok('a repeat is existing, with the same reference and the account''s own company name and number',
  pg_temp.r('reg2') -> 'existing' = 'true'::jsonb
  and pg_temp.r('reg2') ->> 'reference' = pg_temp.ctx('acc')
  and pg_temp.r('reg2') ->> 'company_name' = 'Register Test Scaffolding (Pty) Ltd'
  and pg_temp.r('reg2') ->> 'contact_number' = '+27 10 000 0001'
  and pg_temp.r('reg2') -> 'declined' = 'false'::jsonb
  and not pg_temp.r('reg2') ? 'token');
select pg_temp.ok('a repeat makes no second account and changes no detail of the first',
  (select count(*) = 1 from msp_client_account where lower(contact_email) = 'reg.client@example.invalid')
  and exists (select 1 from msp_client_account a where a.id = pg_temp.ctx('acc')::uuid
                and a.company_name = 'Register Test Scaffolding (Pty) Ltd' and a.contact_name = 'Reg Tester'
                and a.contact_number = '+27 10 000 0001' and a.notes = 'Registered from the Health and Safety File builder'));
select pg_temp.ok('a repeat is audited as hsf_client_register_repeat and still starts nothing of the Plan',
  (select count(*) = 1 from msp_audit x where x.event_type = 'hsf_client_register_repeat'
      and x.event_detail ->> 'client_account_id' = pg_temp.ctx('acc')
      and x.event_detail ->> 'email' = 'reg.client@example.invalid')
  and pg_temp.no_plan(pg_temp.ctx('acc')::uuid));

select pg_temp.act('reg3', $q$select hsf_client_register('{"company_name":"Numberless Test Co (Pty) Ltd","contact_name":"No Number","contact_email":"no.number@example.invalid"}'::jsonb)$q$);
select pg_temp.ok('a registration without a number answers a null number',
  pg_temp.r('reg3') -> 'contact_number' = 'null'::jsonb
  and (select contact_number is null from msp_client_account where id = (pg_temp.r('reg3') ->> 'reference')::uuid));
select pg_temp.act('reg4', $q$select hsf_client_register('{"company_name":"Numberless Test Co (Pty) Ltd","contact_name":"No Number","contact_email":"no.number@example.invalid","contact_number":" 010 000 0002 "}'::jsonb)$q$);
select pg_temp.act('reg5', $q$select hsf_client_register('{"company_name":"Numberless Test Co (Pty) Ltd","contact_name":"No Number","contact_email":"no.number@example.invalid","contact_number":"010 000 0003"}'::jsonb)$q$);
select pg_temp.ok('a repeat fills in a missing number once, and never overwrites it',
  pg_temp.r('reg4') ->> 'contact_number' = '010 000 0002'
  and pg_temp.r('reg5') ->> 'contact_number' = '010 000 0002'
  and (select contact_number = '010 000 0002' from msp_client_account where id = (pg_temp.r('reg3') ->> 'reference')::uuid)
  and pg_temp.no_plan((pg_temp.r('reg3') ->> 'reference')::uuid));

-- 5. A declined account is answered declined and left as it is --------------------------------

insert into msp_client_account (id, company_name, contact_name, contact_email, account_kind) values
  ('d0d0d0d0-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Declined Register Test (Pty) Ltd', 'Declined Tester', 'declined.reg@example.invalid', 'declined');
select pg_temp.act('reg_d', $q$select hsf_client_register('{"company_name":"Declined Register Test (Pty) Ltd","contact_name":"Declined Tester","contact_email":"Declined.Reg@example.invalid"}'::jsonb)$q$);
select pg_temp.ok('a declined account answers declined, existing, and stays declined with no token',
  pg_temp.r('reg_d') -> 'declined' = 'true'::jsonb
  and pg_temp.r('reg_d') -> 'existing' = 'true'::jsonb
  and pg_temp.r('reg_d') ->> 'reference' = 'd0d0d0d0-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and (select account_kind = 'declined' and approved_at is null from msp_client_account where id = 'd0d0d0d0-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
  and not exists (select 1 from msp_form_access where client_account_id = 'd0d0d0d0-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));

-- 6. The File works for the unapproved account ------------------------------------------------
-- A fictitious Supabase auth user with the registered email, confirmed (the builder
-- registers only once the sign in link has been opened).

insert into auth.users (id, email, email_confirmed_at) values
  ('77777777-7777-4777-8777-777777777777', 'Reg.Client@example.invalid', now());
select pg_temp.put('u', '77777777-7777-4777-8777-777777777777');

select pg_temp.ok('hsf_link_account links the File only account to its signed in contact',
  hsf_link_account(pg_temp.ctx('u')::uuid) = pg_temp.ctx('acc')::uuid);
select pg_temp.ok('the account now carries the auth user and is still not approved',
  (select auth_user_id = pg_temp.ctx('u')::uuid from msp_client_account where id = pg_temp.ctx('acc')::uuid)
  and pg_temp.no_plan(pg_temp.ctx('acc')::uuid));
select pg_temp.ok('consent status finds the account and its company name',
  (select s ->> 'client_account_id' = pg_temp.ctx('acc') and s ->> 'company_name' = 'Register Test Scaffolding (Pty) Ltd'
          and s ->> 'complete' = 'false'
     from hsf_consent_status(pg_temp.ctx('u')::uuid) s));
select pg_temp.ok('all three consents are recorded for the unapproved account',
  (select s ->> 'complete' = 'true'
     from hsf_record_consent(pg_temp.ctx('u')::uuid, array['document_storage', 'mco_transfer', 'authority_to_share'],
                             hsf_consent_wording_version()) s));

do $$
declare
  r jsonb;
begin
  r := hsf_generate_file(pg_temp.ctx('u')::uuid, jsonb_build_object(
         'industry_code', 'OFFICE', 'triggers', jsonb_build_array('T-ELEC'),
         'scope', jsonb_build_object('sites', jsonb_build_array(jsonb_build_object('name', 'Register test head office')))));
  perform pg_temp.put('file', r ->> 'file_id');
  perform pg_temp.ok('the unapproved account generates a File with a CNC-HSF reference and items',
    r ->> 'reference' ~ '^CNC-HSF-[0-9]{4}-[0-9]{4}-[0-9]{3}$' and (r ->> 'items')::int > 0);
end $$;
select pg_temp.ok('the File is a draft owned by the account, listed and readable for its contact',
  exists (select 1 from hsf_file f where f.id = pg_temp.ctx('file')::uuid and f.status = 'draft'
            and f.client_account_id = pg_temp.ctx('acc')::uuid)
  and (select jsonb_array_length(l) = 1 and l -> 0 ->> 'file_id' = pg_temp.ctx('file')
         from hsf_my_files(pg_temp.ctx('u')::uuid) l)
  and hsf_file_detail(pg_temp.ctx('u')::uuid, pg_temp.ctx('file')::uuid) is not null);
select pg_temp.ok('the unapproved account may ask to be verified for uploads',
  hsf_request_client_verification(pg_temp.ctx('u')::uuid) ->> 'status' = 'requested');

-- Uploads open and the account verified by the service role, as a sales executive would.
update msp_env_parameter set value = 'true' where key = 'hsf.uploads_open';
select set_config('request.jwt.claims', '{"role": "service_role"}', true);
select pg_temp.ok('a sales executive can verify the unapproved account',
  hsf_verify_client(pg_temp.ctx('acc')::uuid, 'client_register', 'REGISTER-TEST-1') ->> 'status' = 'verified');
select set_config('request.jwt.claims', '', true);
select pg_temp.ok('the upload gate is open for the account: uploads open, verified, consent complete',
  (select g ->> 'uploads_open' = 'true' and g ->> 'client_verified' = 'true' and g ->> 'consent_complete' = 'true'
     from hsf_upload_gate(pg_temp.ctx('u')::uuid) g));
select pg_temp.act('up', format('select hsf_register_upload(%L, %L::jsonb)', pg_temp.ctx('u'),
  jsonb_build_object('file_id', pg_temp.ctx('file'), 'department_code', 'SHE', 'section_code', 'A',
                     'original_name', 'Register test document.pdf', 'mime_type', 'application/pdf', 'size_bytes', 1024,
                     'sha256', encode(extensions.digest('hsf register test document', 'sha256'), 'hex'))));
select pg_temp.ok('the unapproved account registers an upload into its File',
  exists (select 1 from hsf_upload u where u.id = (pg_temp.r('up') ->> 'upload_id')::uuid
            and u.client_account_id = pg_temp.ctx('acc')::uuid and u.status = 'awaiting_upload'));
select pg_temp.act('ps', format('select hsf_portal_summary(%L)', pg_temp.ctx('u')));
select pg_temp.ok('the portal summary shows the account as an applicant with its File and no Plan',
  pg_temp.r('ps') -> 'account' ->> 'account_kind' = 'applicant'
  and pg_temp.r('ps') -> 'account' -> 'approved_at' = 'null'::jsonb
  and pg_temp.r('ps') -> 'plans' = '[]'::jsonb
  and jsonb_array_length(pg_temp.r('ps') -> 'files') = 1);
select pg_temp.ok('after the whole File journey the account is still not approved and has no Plan token',
  pg_temp.no_plan(pg_temp.ctx('acc')::uuid)
  and (select count(*) from msp_form_access) = pg_temp.ctx('fa_before')::bigint);

-- 7. The Plan still works for the same company, if and when its contact chooses it ------------
-- /api/company-lookup on the Plan landing: msp_company_lookup, then msp_client_start_assessment.

select pg_temp.ok('msp_company_lookup finds the account as an applicant (the lookup changes nothing)',
  (select l ->> 'found' = 'true' and l ->> 'account_kind' = 'applicant'
          and l ->> 'company_name' = 'Register Test Scaffolding (Pty) Ltd'
     from msp_company_lookup('reg.client@example.invalid') l)
  and pg_temp.no_plan(pg_temp.ctx('acc')::uuid));
select pg_temp.act('start1', $q$select msp_client_start_assessment('  REG.Client@example.invalid ')$q$);
select pg_temp.ok('msp_client_start_assessment approves on demand and returns a token, as for any account',
  pg_temp.r('start1') ->> 'found' = 'true' and pg_temp.r('start1') ->> 'declined' = 'false'
  and pg_temp.r('start1') ->> 'account_kind' = 'approved_client'
  and pg_temp.r('start1') ->> 'company_name' = 'Register Test Scaffolding (Pty) Ltd'
  and pg_temp.r('start1') ->> 'token' ~ '^[0-9a-f]{48}$');
select pg_temp.ok('the account is now an approved client (self service), still linked to its contact',
  exists (select 1 from msp_client_account a where a.id = pg_temp.ctx('acc')::uuid
            and a.account_kind = 'approved_client' and a.approved_by = 'self-service' and a.approved_at is not null
            and a.auth_user_id = pg_temp.ctx('u')::uuid));
select pg_temp.ok('one live assessment token for the account, issued as approved_client',
  (select count(*) = 1 from msp_form_access fa where fa.client_account_id = pg_temp.ctx('acc')::uuid)
  and exists (select 1 from msp_form_access fa where fa.client_account_id = pg_temp.ctx('acc')::uuid
                and fa.token = pg_temp.r('start1') ->> 'token' and fa.granted_via = 'approved_client'
                and fa.used_by_intake is null and fa.expires_at > now()
                and fa.company_name = 'Register Test Scaffolding (Pty) Ltd'));
select pg_temp.ok('the Plan start is audited: client_self_approved once for the account, one access grant',
  (select count(*) = 1 from msp_audit x where x.event_type = 'client_self_approved'
      and x.event_detail ->> 'client_account_id' = pg_temp.ctx('acc'))
  and (select count(*) from msp_audit where event_type = 'form_access_granted') = pg_temp.ctx('granted_before')::bigint + 1);
select pg_temp.act('start2', $q$select msp_client_start_assessment('reg.client@example.invalid')$q$);
select pg_temp.ok('a second start reuses the same token and approves nothing again',
  pg_temp.r('start2') ->> 'token' = pg_temp.r('start1') ->> 'token'
  and (select count(*) = 1 from msp_form_access fa where fa.client_account_id = pg_temp.ctx('acc')::uuid)
  and (select count(*) = 1 from msp_audit x where x.event_type = 'client_self_approved'
         and x.event_detail ->> 'client_account_id' = pg_temp.ctx('acc')));
select pg_temp.ok('the File is untouched by the Plan start: still listed for the contact',
  (select jsonb_array_length(l) = 1 and l -> 0 ->> 'file_id' = pg_temp.ctx('file') from hsf_my_files(pg_temp.ctx('u')::uuid) l)
  and hsf_portal_summary(pg_temp.ctx('u')::uuid) -> 'account' ->> 'account_kind' = 'approved_client');
select pg_temp.ok('a later File registration of the same email changes nothing of the Plan start',
  (select r -> 'existing' = 'true'::jsonb and not r ? 'token'
     from hsf_client_register('{"company_name":"Register Test Scaffolding (Pty) Ltd","contact_name":"Reg Tester","contact_email":"reg.client@example.invalid"}'::jsonb) r));
select pg_temp.ok('the account and its single token are as the Plan start left them',
  (select account_kind = 'approved_client' from msp_client_account where id = pg_temp.ctx('acc')::uuid)
  and (select count(*) = 1 from msp_form_access fa where fa.client_account_id = pg_temp.ctx('acc')::uuid));
select pg_temp.ok('a declined account still gets no Plan start',
  (select s ->> 'declined' = 'true' and s -> 'token' is null from msp_client_start_assessment('declined.reg@example.invalid') s)
  and not exists (select 1 from msp_form_access where client_account_id = 'd0d0d0d0-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));

-- 8. The Plan landing's own path (msp_client_signon) is unchanged ------------------------------

select pg_temp.act('plan', $q$select msp_client_signon('{"company_name":"Plan Landing Test (Pty) Ltd","contact_name":"Plan Tester","contact_email":"plan.landing@example.invalid"}'::jsonb)$q$);
select pg_temp.ok('msp_client_signon still approves at once and returns the assessment token (the Plan landing)',
  pg_temp.r('plan') ->> 'account_kind' = 'approved_client'
  and pg_temp.r('plan') ->> 'token' ~ '^[0-9a-f]{48}$'
  and exists (select 1 from msp_form_access fa where fa.client_account_id = (pg_temp.r('plan') ->> 'reference')::uuid
                and fa.token = pg_temp.r('plan') ->> 'token')
  and exists (select 1 from msp_audit x where x.event_type = 'client_signon'
                and x.event_detail ->> 'client_account_id' = pg_temp.r('plan') ->> 'reference'));

-- 9. 056 is idempotent: a second run changes no row and leaves the function as it was ---------

-- Only the accounts this transaction made (their ids are in ctx), never every
-- example.invalid account in the database.
create temp table own_accounts as
  select unnest(array[pg_temp.ctx('acc')::uuid, (pg_temp.r('reg3') ->> 'reference')::uuid,
                      'd0d0d0d0-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid, (pg_temp.r('plan') ->> 'reference')::uuid]) as id;
create temp table before_rerun as
  select 'account ' || a.id::text as k, a.xmin::text as x from msp_client_account a join own_accounts o on o.id = a.id
  union all select 'function', md5(concat_ws('|', p.prosrc, p.proconfig::text, p.proacl::text, p.prosecdef::text, obj_description(p.oid, 'pg_proc')))
    from pg_proc p where p.oid = 'hsf_client_register(jsonb)'::regprocedure;
\ir ../../supabase/migrations/056_hsf_file_naming.sql
select pg_temp.ok('running 056 again rewrites no account and leaves hsf_client_register, its grant and comment as they were',
  (select count(*) from before_rerun) = 5
  and (select count(*) = 5 from before_rerun b
         join (select 'account ' || a.id::text as k, a.xmin::text as x from msp_client_account a join own_accounts o on o.id = a.id
               union all select 'function', md5(concat_ws('|', p.prosrc, p.proconfig::text, p.proacl::text, p.prosecdef::text, obj_description(p.oid, 'pg_proc')))
                 from pg_proc p where p.oid = 'hsf_client_register(jsonb)'::regprocedure) a
           on a.k = b.k and a.x = b.x));

rollback;
\echo 'hsf_register_checks: all checks passed'
