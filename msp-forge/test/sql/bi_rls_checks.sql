-- CNC HSF FORGE | BI-CORE-01 to BI-DEC-01, Bee-Inspect Row Level Security checks | local test harness only.
-- Proves migrations 059 to 064 (hsf/BUILD-CONTRACT.md 16 and 16.8, Bee-Inspect P3 and its
-- locked decisions: the export rule, accounts and settings, the new tables) against a
-- replayed database, per role: inspector, assistant, company admin, ops (Care Net
-- staff), an inspector of another tenant with no line on the company, an
-- inspector of a third tenant with its own line on the same company, and anon.
-- Loads the fictitious demonstration seed inside the transaction. Never applied
-- to Supabase. Everything runs in one transaction that is rolled back.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/bi_rls_checks.sql

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

-- Runs one statement as a client (authenticated with the given JWT claims, or
-- anon when the claims are empty) and returns its single value, or ERR: <message>.
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

create function pg_temp.jwt(p_sub text, p_staff boolean default false) returns text language sql as $$
  select json_build_object('sub', p_sub, 'role', 'authenticated',
           'app_metadata', case when p_staff then json_build_object('msp_roles', json_build_array('forge_admin')) else '{}'::json end)::text $$;

\ir ../../supabase/seed/bee_inspect_demo.sql

-- Fixtures: two more fictitious tenants and a second company ------------------------------------------

insert into auth.users (id, email, email_confirmed_at) values
  ('b2a00000-0000-4000-8000-000000000011', 'other.inspector.check@example.invalid', now()),
  ('b2a00000-0000-4000-8000-000000000012', 'third.inspector.check@example.invalid', now()),
  ('b2a00000-0000-4000-8000-000000000013', 'ops.staff.check@example.invalid', now());
update auth.users set raw_app_meta_data = '{"msp_roles":["forge_admin"]}' where id = 'b2a00000-0000-4000-8000-000000000013';
insert into msp_client_account (id, company_name, contact_name, contact_email) values
  ('b2a00000-0000-4000-8000-000000000002', 'Other Works (fictitious)', 'Other Contact', 'other.contact.check@example.invalid');
insert into bi_tenant (id, name) values
  ('b2a00000-0000-4000-8000-000000000001', 'Other Tenant (fictitious)'),
  ('b3a00000-0000-4000-8000-000000000001', 'Third Tenant (fictitious)');
insert into bi_company (client_account_id, legal_name, onboarding_status, activated_at, activated_by) values
  ('b2a00000-0000-4000-8000-000000000002', 'Other Works (fictitious)', 'active', now(), 'check');
insert into bi_company_subscription (tenant_id, client_account_id, plan_code, price_cents, wallet_monthly_cents, storage_bytes) values
  ('b2a00000-0000-4000-8000-000000000001', 'b2a00000-0000-4000-8000-000000000002', 'base', 29900, 15000, 10737418240),
  ('b3a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'base', 29900, 15000, 10737418240);
insert into bi_app_user (id, auth_user_id, tenant_id, display_name) values
  ('b2a00000-0000-4000-8000-000000000021', 'b2a00000-0000-4000-8000-000000000011', 'b2a00000-0000-4000-8000-000000000001', 'Other Inspector (fictitious)'),
  ('b3a00000-0000-4000-8000-000000000021', 'b2a00000-0000-4000-8000-000000000012', 'b3a00000-0000-4000-8000-000000000001', 'Third Inspector (fictitious)');
insert into bi_role_assignment (app_user_id, tenant_id, role, granted_by) values
  ('b2a00000-0000-4000-8000-000000000021', 'b2a00000-0000-4000-8000-000000000001', 'inspector', 'check'),
  ('b3a00000-0000-4000-8000-000000000021', 'b3a00000-0000-4000-8000-000000000001', 'inspector', 'check');
insert into bi_site (id, client_account_id, name) values
  ('b2a00000-0000-4000-8000-000000000041', 'b2a00000-0000-4000-8000-000000000002', 'Other Site (fictitious)');
insert into bi_inspection (id, tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status) values
  ('b2a00000-0000-4000-8000-000000000081', 'b2a00000-0000-4000-8000-000000000001', 'b2a00000-0000-4000-8000-000000000002',
   'b2a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000062', 'b2a00000-0000-4000-8000-000000000021', 'Other ladder check', 'in_progress'),
  ('b3a00000-0000-4000-8000-000000000081', 'b3a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002',
   'b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000065', 'b3a00000-0000-4000-8000-000000000021', 'Third tenant fire check', 'in_progress'),
  -- An open inspection of the demonstration tenant for the write checks.
  ('b1a00000-0000-4000-8000-0000000000e1', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002',
   'b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000062', 'b1a00000-0000-4000-8000-000000000021', 'Ladder check (open)', 'in_progress');
insert into bi_inspection_area (id, inspection_id, tenant_id, client_account_id, label) values
  ('b1a00000-0000-4000-8000-0000000000e2', 'b1a00000-0000-4000-8000-0000000000e1', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'Workshop');

-- A subsidy row on the seed wallet (decision 1.3), for the read checks.
insert into bi_subsidy_ledger (reason, job_id, job_kind, wallet_id, tenant_id, client_account_id, user_id, estimate_cents, actual_cents,
                               billable_cents, charged_cents, shortfall_cents)
select 'balance_exhausted', u.id, u.kind, u.wallet_id, u.tenant_id, u.client_account_id, u.auth_user_id, 1234, 1180, 1180, 1000, 180
  from bi_usage_event u where u.estimate_key = 'demo:estimate:0001';

\set insp '''{"sub":"b1a00000-0000-4000-8000-000000000011","role":"authenticated"}'''
\set asst '''{"sub":"b1a00000-0000-4000-8000-000000000012","role":"authenticated"}'''
\set admin '''{"sub":"b1a00000-0000-4000-8000-000000000013","role":"authenticated"}'''
\set other '''{"sub":"b2a00000-0000-4000-8000-000000000011","role":"authenticated"}'''
\set third '''{"sub":"b2a00000-0000-4000-8000-000000000012","role":"authenticated"}'''
\set ops '''{"sub":"b2a00000-0000-4000-8000-000000000013","role":"authenticated","app_metadata":{"msp_roles":["forge_admin"]}}'''
\set anon ''''''

-- 1. Every bi_ table has RLS on and nothing for anon --------------------------------------------------

select pg_temp.ok('RLS is on for every bi_ table',
  not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'bi\_%' and not c.relrowsecurity));
select pg_temp.ok('anon holds no privilege on any bi_ table or view',
  not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'public' and c.relkind in ('r','v') and c.relname like 'bi\_%'
                 and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
                      or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'))));
select pg_temp.ok('anon may execute no bi_ function',
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname like 'bi\_%' and has_function_privilege('anon', p.oid, 'execute')));
select pg_temp.ok('authenticated cannot insert, update or delete wallet_ledger, signature, report, report_version, audit_log, usage_event, iap_receipt, claim_code, step_up, rate_event',
  not exists (select 1 from unnest(array['bi_wallet_ledger','bi_signature','bi_report','bi_report_version','bi_audit_log','bi_usage_event',
                                         'bi_iap_receipt','bi_claim_code','bi_step_up','bi_rate_event','bi_wallet','bi_transfer_package',
                                         'bi_report_file_link','bi_inspector_qualification','bi_fica_record','bi_company_subscription',
                                         'bi_role_assignment','bi_inspector_profile','bi_rate_card','bi_storage_meter']) t
               where has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update')
                  or has_table_privilege('authenticated', 'public.' || t, 'delete')));
select pg_temp.ok('authenticated cannot read FICA, qualifications, claim codes, receipts, step ups or rate events directly (audited functions only)',
  not exists (select 1 from unnest(array['bi_inspector_qualification','bi_fica_record','bi_claim_code','bi_iap_receipt','bi_step_up','bi_rate_event',
                                         'bi_transfer_package']) t
               where has_table_privilege('authenticated', 'public.' || t, 'select')));
select pg_temp.ok('server side bi_ functions are not executable by authenticated',
  not has_function_privilege('authenticated', 'bi_wallet_charge(uuid, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'bi_report_sign(uuid, uuid, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'bi_report_issue(uuid, text, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'bi_hsf_section_f_sync(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'bi_claim_code_redeem(text, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'bi_fica_list(uuid, uuid, uuid)', 'execute')
  and has_function_privilege('service_role', 'bi_wallet_charge(uuid, jsonb)', 'execute'));
select pg_temp.ok('every bi_ security definer function fixes its search_path',
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname like 'bi\_%' and p.prosecdef
                 and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')));

-- 2. Reads per role -----------------------------------------------------------------------------------

create temp table rls_matrix (tbl text, role text, got text);
insert into rls_matrix
select t.tbl, r.role, pg_temp.as_user(r.claims, format('select count(*)::text from %I', t.tbl))
  from (values ('bi_inspection'),('bi_finding'),('bi_photo'),('bi_voice_note'),('bi_risk'),('bi_corrective_action'),('bi_site'),
               ('bi_report'),('bi_report_version'),('bi_signature'),('bi_wallet'),('bi_wallet_ledger'),('bi_usage_event'),
               ('bi_audit_log'),('bi_template'),('bi_company'),('bi_inspector_qualification'),('bi_fica_record'),('bi_claim_code'),
               ('bi_report_file_link'),('bi_app_user'),('bi_medicals_volume'),('bi_site_subcontractor'),('bi_authorised_person'),
               ('bi_person_credential'),('bi_subsidy_ledger'),('bi_rate_card_channel'),('bi_super_user'),('bi_consent_purpose')) t(tbl)
  cross join (values ('inspector', :insp), ('assistant', :asst), ('company_admin', :admin), ('ops', :ops),
                     ('other_tenant', :other), ('third_tenant_same_company', :third), ('anon', :anon)) r(role, claims);

-- Print the matrix (docs/bee-inspect/p3/index.md carries it).
select tbl, string_agg(role || '=' || case when got like 'ERR:%' then 'denied' else got end, '  ' order by role) as counts
  from rls_matrix group by tbl order by tbl;

create function pg_temp.cell(p_tbl text, p_role text) returns text language sql as $$
  select case when got like 'ERR:%' then 'denied' else got end from rls_matrix where tbl = p_tbl and role = p_role $$;

select pg_temp.ok('inspector reads the one demonstration inspection plus the open one (2)', pg_temp.cell('bi_inspection', 'inspector') = '2');
select pg_temp.ok('assistant reads the same inspections (2)', pg_temp.cell('bi_inspection', 'assistant') = '2');
select pg_temp.ok('company admin reads the tenant''s inspections of the company (2)', pg_temp.cell('bi_inspection', 'company_admin') = '2');
select pg_temp.ok('ops reads every inspection (4)', pg_temp.cell('bi_inspection', 'ops') = '4');
select pg_temp.ok('other tenant reads only its own inspection (1)', pg_temp.cell('bi_inspection', 'other_tenant') = '1');
select pg_temp.ok('a third tenant with its own line on the same company reads only its own inspection (1)', pg_temp.cell('bi_inspection', 'third_tenant_same_company') = '1');
select pg_temp.ok('anon is denied inspections', pg_temp.cell('bi_inspection', 'anon') = 'denied');
select pg_temp.ok('findings: inspector 6, assistant 6, admin 6, other tenant 0, third tenant 0',
  pg_temp.cell('bi_finding','inspector') = '6' and pg_temp.cell('bi_finding','assistant') = '6' and pg_temp.cell('bi_finding','company_admin') = '6'
  and pg_temp.cell('bi_finding','other_tenant') = '0' and pg_temp.cell('bi_finding','third_tenant_same_company') = '0');
select pg_temp.ok('photos and voice notes: other tenants 0',
  pg_temp.cell('bi_photo','inspector') = '3' and pg_temp.cell('bi_photo','other_tenant') = '0' and pg_temp.cell('bi_photo','third_tenant_same_company') = '0'
  and pg_temp.cell('bi_voice_note','inspector') = '2' and pg_temp.cell('bi_voice_note','other_tenant') = '0');
select pg_temp.ok('the sites tree is shared by tenants with a live line on the company, not by others',
  pg_temp.cell('bi_site','inspector') = '1' and pg_temp.cell('bi_site','third_tenant_same_company') = '1'
  and pg_temp.cell('bi_site','other_tenant') = '1' and pg_temp.cell('bi_site','ops') = '2');
select pg_temp.ok('Issued report: inspector, assistant, company admin and ops read it; other tenants do not',
  pg_temp.cell('bi_report','inspector') = '1' and pg_temp.cell('bi_report','assistant') = '1' and pg_temp.cell('bi_report','company_admin') = '1'
  and pg_temp.cell('bi_report','ops') = '1' and pg_temp.cell('bi_report','other_tenant') = '0' and pg_temp.cell('bi_report','third_tenant_same_company') = '0');
select pg_temp.ok('wallet and ledger: inspector and company admin read them; assistant and other tenants do not',
  pg_temp.cell('bi_wallet','inspector') = '1' and pg_temp.cell('bi_wallet','company_admin') = '1' and pg_temp.cell('bi_wallet','assistant') = '0'
  and pg_temp.cell('bi_wallet','other_tenant') = '0' and pg_temp.cell('bi_wallet_ledger','inspector') = '3'
  and pg_temp.cell('bi_wallet_ledger','assistant') = '0' and pg_temp.cell('bi_usage_event','assistant') = '0');
select pg_temp.ok('audit log: company admin reads the company''s rows; inspector, assistant and other tenants read none; ops reads all',
  pg_temp.cell('bi_audit_log','company_admin')::int > 0 and pg_temp.cell('bi_audit_log','inspector') = '0'
  and pg_temp.cell('bi_audit_log','assistant') = '0' and pg_temp.cell('bi_audit_log','other_tenant') = '0'
  and pg_temp.cell('bi_audit_log','ops')::int >= pg_temp.cell('bi_audit_log','company_admin')::int);
select pg_temp.ok('qualifications, FICA and claim codes are denied to every client role, ops included (audited functions only)',
  (select bool_and(got like 'ERR:%') from rls_matrix where tbl in ('bi_inspector_qualification','bi_fica_record','bi_claim_code')));
select pg_temp.ok('the published library templates are readable by every signed in person (7), not by anon',
  pg_temp.cell('bi_template','inspector') = '7' and pg_temp.cell('bi_template','other_tenant') = '7' and pg_temp.cell('bi_template','anon') = 'denied');
select pg_temp.ok('Section F link: readable by the File owner (company admin) and the inspector; not by other tenants',
  pg_temp.cell('bi_report_file_link','company_admin') = '1' and pg_temp.cell('bi_report_file_link','inspector') = '1'
  and pg_temp.cell('bi_report_file_link','other_tenant') = '0');

select pg_temp.ok('064: verified medicals counts: the company admin and ops read the company''s count; inspectors, assistants and other tenants do not',
  pg_temp.cell('bi_medicals_volume','company_admin') = '1' and pg_temp.cell('bi_medicals_volume','ops') = '1'
  and pg_temp.cell('bi_medicals_volume','inspector') = '0' and pg_temp.cell('bi_medicals_volume','assistant') = '0'
  and pg_temp.cell('bi_medicals_volume','other_tenant') = '0' and pg_temp.cell('bi_medicals_volume','anon') = 'denied');
select pg_temp.ok('064: authorised persons (3 in the seed): inspector, company admin, ops and the third tenant with a line read them; the assistant and other tenants do not',
  pg_temp.cell('bi_authorised_person','inspector') = '3' and pg_temp.cell('bi_authorised_person','company_admin') = '3'
  and pg_temp.cell('bi_authorised_person','ops') = '3' and pg_temp.cell('bi_authorised_person','third_tenant_same_company') = '3'
  and pg_temp.cell('bi_authorised_person','assistant') = '0' and pg_temp.cell('bi_authorised_person','other_tenant') = '0');
select pg_temp.ok('064: authorised persons'' credentials are denied to every client role (audited function only)',
  (select bool_and(got like 'ERR:%') from rls_matrix where tbl = 'bi_person_credential'));
select pg_temp.ok('064: the subsidy ledger follows the wallet: inspector, company admin and ops read it; the assistant and other tenants do not',
  pg_temp.cell('bi_subsidy_ledger','inspector') = '1' and pg_temp.cell('bi_subsidy_ledger','company_admin') = '1'
  and pg_temp.cell('bi_subsidy_ledger','ops') = '1' and pg_temp.cell('bi_subsidy_ledger','assistant') = '0'
  and pg_temp.cell('bi_subsidy_ledger','other_tenant') = '0' and pg_temp.cell('bi_subsidy_ledger','third_tenant_same_company') = '0');
select pg_temp.ok('064: channel fees are ops only (22 rows); nobody else reads them',
  pg_temp.cell('bi_rate_card_channel','ops') = '22' and pg_temp.cell('bi_rate_card_channel','inspector') = '0'
  and pg_temp.cell('bi_rate_card_channel','company_admin') = '0' and pg_temp.cell('bi_rate_card_channel','anon') = 'denied');
select pg_temp.ok('064: the consent purposes (7) are readable by every signed in person, not by anon',
  pg_temp.cell('bi_consent_purpose','assistant') = '7' and pg_temp.cell('bi_consent_purpose','other_tenant') = '7' and pg_temp.cell('bi_consent_purpose','anon') = 'denied');
select pg_temp.ok('064: no client may insert, update or delete any of the new tables',
  not exists (select 1 from unnest(array['bi_medicals_volume','bi_site_subcontractor','bi_authorised_person','bi_person_credential','bi_consent_purpose',
                                         'bi_subsidy_ledger','bi_rate_card_channel','bi_super_user']) t
               where has_table_privilege('authenticated', 'public.' || t, 'insert') or has_table_privilege('authenticated', 'public.' || t, 'update')
                  or has_table_privilege('authenticated', 'public.' || t, 'delete')));
select pg_temp.ok('064: clients still read the prices of the rate card but never its landed cost columns',
  pg_temp.as_user(:insp, 'select count(*)::text from (select code, price_cents, value_cents from bi_rate_card) x')::int > 0
  and pg_temp.as_user(:insp, 'select count(*)::text from (select landed_cost_cents from bi_rate_card) x') like 'ERR:%permission denied%'
  and pg_temp.as_user(:ops, 'select count(*)::text from (select landed_cost_components from bi_rate_card) x') like 'ERR:%permission denied%');

-- 3. Writes per role ----------------------------------------------------------------------------------

select pg_temp.ok('inspector records a finding on an open inspection',
  pg_temp.as_user(:insp, $q$insert into bi_finding (inspection_id, tenant_id, client_account_id, area_id, result) values
    ('b1a00000-0000-4000-8000-0000000000e1', 'b2a00000-0000-4000-8000-000000000001', 'b2a00000-0000-4000-8000-000000000002',
     'b1a00000-0000-4000-8000-0000000000e2', 'pass') returning client_account_id::text$q$) = 'b1a00000-0000-4000-8000-000000000002');
select pg_temp.ok('the ownership a client supplies is ignored: the finding carries the inspection''s tenant and company',
  (select count(*) from bi_finding where inspection_id = 'b1a00000-0000-4000-8000-0000000000e1'
     and tenant_id = 'b1a00000-0000-4000-8000-000000000001' and captured_by = 'b1a00000-0000-4000-8000-000000000021') = 1);
select pg_temp.ok('assistant records a finding',
  pg_temp.as_user(:asst, $q$insert into bi_finding (inspection_id, tenant_id, client_account_id, area_id, result, note) values
    ('b1a00000-0000-4000-8000-0000000000e1', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002',
     'b1a00000-0000-4000-8000-0000000000e2', 'observe', 'check') returning 'ok'$q$) = 'ok');
select pg_temp.ok('assistant cannot record a risk (inspector only)',
  pg_temp.as_user(:asst, $q$insert into bi_risk (inspection_id, tenant_id, client_account_id, hazard, inherent_likelihood, inherent_severity) values
    ('b1a00000-0000-4000-8000-0000000000e1', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'Trip hazard', 2, 2) returning 'ok'$q$) like 'ERR:%row-level security%');
select pg_temp.ok('assistant cannot create an inspection',
  pg_temp.as_user(:asst, $q$insert into bi_inspection (tenant_id, client_account_id, site_id, template_id, inspector_user_id, title) values
    ('b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041',
     'b1a00000-0000-4000-8000-000000000062', 'b1a00000-0000-4000-8000-000000000022', 'x') returning 'ok'$q$) like 'ERR:%');
select pg_temp.ok('company admin cannot record findings',
  pg_temp.as_user(:admin, $q$insert into bi_finding (inspection_id, tenant_id, client_account_id, area_id, result) values
    ('b1a00000-0000-4000-8000-0000000000e1', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002',
     'b1a00000-0000-4000-8000-0000000000e2', 'pass') returning 'ok'$q$) like 'ERR:%row-level security%');
select pg_temp.ok('company admin adds a room to the sites tree of their company',
  pg_temp.as_user(:admin, $q$insert into bi_room (client_account_id, site_id, building_id, name) values
    ('b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041', 'b1a00000-0000-4000-8000-000000000044', 'Tool store') returning 'ok'$q$) = 'ok');
select pg_temp.ok('another tenant cannot write into this tenant''s inspection',
  pg_temp.as_user(:other, $q$insert into bi_finding (inspection_id, tenant_id, client_account_id, area_id, result) values
    ('b1a00000-0000-4000-8000-0000000000e1', 'b2a00000-0000-4000-8000-000000000001', 'b2a00000-0000-4000-8000-000000000002',
     'b1a00000-0000-4000-8000-0000000000e2', 'pass') returning 'ok'$q$) like 'ERR:%');
select pg_temp.ok('an inspector cannot open an inspection on a company their tenant holds no line on',
  pg_temp.as_user(:other, $q$insert into bi_inspection (tenant_id, client_account_id, site_id, template_id, inspector_user_id, title) values
    ('b2a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041',
     'b1a00000-0000-4000-8000-000000000062', 'b2a00000-0000-4000-8000-000000000021', 'x') returning 'ok'$q$) like 'ERR:%');
select pg_temp.ok('an inspector opens an inspection in their own name',
  pg_temp.as_user(:insp, $q$insert into bi_inspection (tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status) values
    ('b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041',
     'b1a00000-0000-4000-8000-000000000066', 'b1a00000-0000-4000-8000-000000000021', 'PPE walk', 'in_progress') returning voice_note_policy$q$) = 'strict');
select pg_temp.ok('but never in someone else''s name',
  pg_temp.as_user(:insp, $q$insert into bi_inspection (tenant_id, client_account_id, site_id, template_id, inspector_user_id, title) values
    ('b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000041',
     'b1a00000-0000-4000-8000-000000000066', 'b1a00000-0000-4000-8000-000000000022', 'x') returning 'ok'$q$) like 'ERR:%own name%');
select pg_temp.ok('a client cannot submit an inspection directly (functions only)',
  pg_temp.as_user(:insp, $q$update bi_inspection set status = 'submitted' where id = 'b1a00000-0000-4000-8000-0000000000e1' returning 'ok'$q$) like 'ERR:%functions%');
select pg_temp.ok('a client cannot edit a submitted inspection''s findings',
  pg_temp.as_user(:insp, $q$update bi_finding set note = 'changed' where id = 'b1a00000-0000-4000-8000-000000000091' returning 'ok'$q$) like 'ERR:%read only%');
select pg_temp.ok('a client cannot write the ledger, a signature, a report status or the audit log',
  pg_temp.as_user(:insp, $q$insert into bi_wallet_ledger (wallet_id, entry_kind, amount_cents, expires_at, idempotency_key) select id, 'topup_credit', 100000, now() + interval '1 year', 'hack:0000001' from bi_wallet limit 1 returning 'ok'$q$) like 'ERR:%permission denied%'
  and pg_temp.as_user(:insp, $q$update bi_report set status = 'draft' returning 'ok'$q$) like 'ERR:%permission denied%'
  and pg_temp.as_user(:insp, $q$insert into bi_audit_log (actor_label, event) values ('x', 'forged_event') returning 'ok'$q$) like 'ERR:%permission denied%'
  and pg_temp.as_user(:insp, $q$delete from bi_signature returning 'ok'$q$) like 'ERR:%permission denied%');
select pg_temp.ok('a client cannot capture a photo in another inspector''s name',
  pg_temp.as_user(:asst, $q$insert into bi_photo (inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, inspector_user_id)
    values ('b1a00000-0000-4000-8000-0000000000e1', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'area',
            'b1a00000-0000-4000-8000-000000000002/b1a00000-0000-4000-8000-0000000000e1/x.jpg', repeat('a', 64), 10, 'image/jpeg', now(),
            'b1a00000-0000-4000-8000-000000000021') returning 'ok'$q$) like 'ERR:%person signed in%');
select pg_temp.ok('an assistant captures a photo in their own name',
  pg_temp.as_user(:asst, $q$insert into bi_photo (inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, inspector_user_id)
    values ('b1a00000-0000-4000-8000-0000000000e1', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002', 'area',
            'b1a00000-0000-4000-8000-000000000002/b1a00000-0000-4000-8000-0000000000e1/y.jpg', repeat('b', 64), 10, 'image/jpeg', now(),
            'b1a00000-0000-4000-8000-000000000022') returning (seal_sha256 is not null)::text$q$) = 'true');
select pg_temp.ok('ops (Care Net staff) reads everything but captures nothing directly',
  pg_temp.as_user(:ops, $q$insert into bi_finding (inspection_id, tenant_id, client_account_id, area_id, result) values
    ('b1a00000-0000-4000-8000-0000000000e1', 'b1a00000-0000-4000-8000-000000000001', 'b1a00000-0000-4000-8000-000000000002',
     'b1a00000-0000-4000-8000-0000000000e2', 'pass') returning 'ok'$q$) like 'ERR:%row-level security%');
select pg_temp.ok('a person writes only their own banner dismissals',
  pg_temp.as_user(:insp, $q$insert into bi_ad_dismissal (auth_user_id, ad_id, dismissed_until) values ('b1a00000-0000-4000-8000-000000000011', 'AD-03', now() + interval '14 days') returning 'ok'$q$) = 'ok'
  and pg_temp.as_user(:insp, $q$insert into bi_ad_dismissal (auth_user_id, ad_id, dismissed_until) values ('b1a00000-0000-4000-8000-000000000012', 'AD-03', now() + interval '14 days') returning 'ok'$q$) like 'ERR:%row-level security%');

-- 4. A lapsed line closes the door ---------------------------------------------------------------------

update bi_company_subscription set status = 'cancelled', cancelled_at = now()
 where tenant_id = 'b3a00000-0000-4000-8000-000000000001';
select pg_temp.ok('when the third tenant''s line lapses its inspector sees nothing of the company any more',
  pg_temp.as_user(:third, 'select count(*)::text from bi_inspection') = '0'
  and pg_temp.as_user(:third, 'select count(*)::text from bi_site') = '0');

-- 5. Audited reads of FICA and qualifications ---------------------------------------------------------------

select pg_temp.ok('the company admin reads the company FICA pack through bi_fica_list',
  jsonb_array_length(bi_fica_list('b1a00000-0000-4000-8000-000000000013', 'b1a00000-0000-4000-8000-000000000002', null)) = 1);
select pg_temp.ok('and each record read is audited as fica_read',
  (select count(*) from bi_audit_log where event = 'fica_read' and actor_auth_user = 'b1a00000-0000-4000-8000-000000000013') = 1);
do $$
begin
  perform bi_fica_list('b1a00000-0000-4000-8000-000000000012', 'b1a00000-0000-4000-8000-000000000002', null);
  raise exception 'CHECK FAILED: assistant read FICA';
exception when insufficient_privilege then
  raise notice 'ok   bi_fica_list refuses the assistant (42501)';
end $$;
select pg_temp.ok('the inspector reads their own qualifications; ops reads them',
  jsonb_array_length(bi_qualification_list('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-000000000021')) = 1
  and jsonb_array_length(bi_qualification_list('b2a00000-0000-4000-8000-000000000013', 'b1a00000-0000-4000-8000-000000000021')) = 1);
select pg_temp.ok('both reads are audited as qualification_read',
  (select count(*) from bi_audit_log where event = 'qualification_read') = 2);
do $$
begin
  perform bi_qualification_list('b2a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-000000000021');
  raise exception 'CHECK FAILED: another tenant read qualifications';
exception when insufficient_privilege then
  raise notice 'ok   bi_qualification_list refuses another tenant''s inspector (42501)';
end $$;

-- 6. Roles are granted and revoked only by the right people ---------------------------------------------------

do $$
begin
  perform bi_role_grant('b1a00000-0000-4000-8000-000000000013', 'b1a00000-0000-4000-8000-000000000022', 'ops', null);
  raise exception 'CHECK FAILED: a company admin granted ops';
exception when insufficient_privilege then
  raise notice 'ok   a company admin cannot grant ops';
end $$;
select pg_temp.ok('a company admin grants inspector on their own company',
  bi_role_grant('b1a00000-0000-4000-8000-000000000013', 'b1a00000-0000-4000-8000-000000000022', 'inspector', 'b1a00000-0000-4000-8000-000000000002') ? 'role_assignment_id');
select pg_temp.ok('role rows are revoked, never deleted or edited',
  (select count(*) from bi_role_assignment) > 0);
do $$
begin
  delete from bi_role_assignment where app_user_id = 'b1a00000-0000-4000-8000-000000000022';
  raise exception 'CHECK FAILED: a role row was deleted';
exception when others then
  if sqlerrm like 'CHECK FAILED%' then raise; end if;
  raise notice 'ok   deleting a role row is refused';
end $$;


-- 7. Export: super users only, every export audited (decision 1.7) ----------------------------------------------

select pg_temp.ok('the export and super user functions are not executable by authenticated (service role only)',
  not has_function_privilege('authenticated', 'bi_export(uuid, text, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'bi_super_user_grant(uuid, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'bi_super_user_revoke(uuid, text)', 'execute')
  and has_function_privilege('service_role', 'bi_export(uuid, text, jsonb)', 'execute'));
select pg_temp.ok('an inspector is refused an export',
  bi_export('b1a00000-0000-4000-8000-000000000011', 'inspections', '{}') @> '{"ok": false, "reason": "not_permitted"}');
select pg_temp.ok('Care Net staff without the explicit super user assignment are refused too',
  bi_export('b2a00000-0000-4000-8000-000000000013', 'inspections', '{}') @> '{"ok": false, "reason": "not_permitted"}');
select pg_temp.ok('both refusals are audited as export_denied, with who, what and when',
  (select count(*) from bi_audit_log where event = 'export_denied' and detail ->> 'what' = 'inspections' and detail ->> 'reason' = 'not_super_user'
     and actor_auth_user in ('b1a00000-0000-4000-8000-000000000011','b2a00000-0000-4000-8000-000000000013') and occurred_at is not null) = 2);
select pg_temp.refuses('the super user assignment is for Care Net staff only',
  $q$select bi_super_user_grant('b1a00000-0000-4000-8000-000000000011', 'Export for the board pack', 'service_role (check)')$q$, 'Only Care Net staff');
select pg_temp.ok('the service role grants the assignment to a staff member',
  bi_super_user_grant('b2a00000-0000-4000-8000-000000000013', 'Monthly export for Care Net finance (check)', 'Director (check)') ? 'super_user_id');
select pg_temp.ok('staff flag plus the assignment makes a super user; the inspector is not one',
  bi_is_super_user('b2a00000-0000-4000-8000-000000000013') and not bi_is_super_user('b1a00000-0000-4000-8000-000000000011'));
select pg_temp.ok('without a fresh bulk export step up the super user is refused, and that is audited',
  bi_export('b2a00000-0000-4000-8000-000000000013', 'inspections', '{}') @> '{"ok": false, "reason": "step_up_required"}');
select pg_temp.ok('the step up refusal is in the audit log',
  exists (select 1 from bi_audit_log where event = 'export_denied' and detail ->> 'reason' = 'step_up' and actor_auth_user = 'b2a00000-0000-4000-8000-000000000013'));
select (bi_step_up_record('b2a00000-0000-4000-8000-000000000013', jsonb_build_object('purpose', 'bulk_export', 'method', 'totp', 'aal', 'aal2',
          'asserted_epoch', extract(epoch from now()), 'session_ref', repeat('e', 64))) ->> 'step_up_id') as xsu \gset
select bi_export('b2a00000-0000-4000-8000-000000000013', 'inspections', jsonb_build_object('step_up_id', :'xsu')) as xp \gset
select pg_temp.ok('with the step up the super user exports every inspection',
  (:'xp'::jsonb ->> 'ok')::boolean and (:'xp'::jsonb ->> 'row_count')::int = (select count(*) from bi_inspection)
  and jsonb_array_length(:'xp'::jsonb -> 'rows') = (select count(*) from bi_inspection));
select pg_temp.ok('the export is audited: who (the staff email), what, how many rows and when',
  exists (select 1 from bi_audit_log where event = 'export' and actor_auth_user = 'b2a00000-0000-4000-8000-000000000013'
            and actor_label = 'ops.staff.check@example.invalid' and detail ->> 'what' = 'inspections'
            and (detail ->> 'row_count')::int = (:'xp'::jsonb ->> 'row_count')::int and occurred_at is not null));
select pg_temp.ok('the step up is consumed by the export and cannot be used again',
  bi_export('b2a00000-0000-4000-8000-000000000013', 'audit_log', jsonb_build_object('step_up_id', :'xsu')) @> '{"ok": false, "reason": "step_up_required"}');
select (bi_step_up_record('b2a00000-0000-4000-8000-000000000013', jsonb_build_object('purpose', 'bulk_export', 'method', 'totp', 'aal', 'aal2',
          'asserted_epoch', extract(epoch from now()), 'session_ref', repeat('d', 64))) ->> 'step_up_id') as xsu2 \gset
select pg_temp.ok('a filtered export (the subsidy ledger of the demonstration company) returns its rows and audits the count',
  bi_export('b2a00000-0000-4000-8000-000000000013', 'subsidy_ledger',
            jsonb_build_object('step_up_id', :'xsu2', 'client_account_id', 'b1a00000-0000-4000-8000-000000000002')) @> '{"ok": true, "row_count": 1}');
select pg_temp.ok('and that export is audited with its filter',
  exists (select 1 from bi_audit_log where event = 'export' and detail ->> 'what' = 'subsidy_ledger' and (detail ->> 'row_count')::int = 1
            and detail -> 'filters' ->> 'client_account_id' = 'b1a00000-0000-4000-8000-000000000002'));
select pg_temp.refuses('an unknown export is refused', $q$select bi_export('b2a00000-0000-4000-8000-000000000013', 'fica_records', '{}')$q$, 'Unknown export');
update auth.users set raw_app_meta_data = null where id = 'b2a00000-0000-4000-8000-000000000013';
select pg_temp.ok('an assignee who is no longer Care Net staff is not a super user',
  not bi_is_super_user('b2a00000-0000-4000-8000-000000000013'));
update auth.users set raw_app_meta_data = '{"msp_roles":["forge_admin"]}' where id = 'b2a00000-0000-4000-8000-000000000013';
select pg_temp.ok('the service role revokes the assignment; no longer a super user',
  (bi_super_user_revoke('b2a00000-0000-4000-8000-000000000013', 'Director (check)') ->> 'revoked')::boolean);
select pg_temp.ok('revoked means refused', not bi_is_super_user('b2a00000-0000-4000-8000-000000000013'));
select pg_temp.refuses('a super user assignment is revoked, never deleted', $q$delete from bi_super_user$q$, 'never deleted');

-- 8. Accounts and settings: authorised persons and their credentials (decision section 2) ----------------------

select bi_authorised_person_save('b1a00000-0000-4000-8000-000000000013', jsonb_build_object('client_account_id', 'b1a00000-0000-4000-8000-000000000002',
         'full_name', 'Thabo Molefe (fictitious)', 'role', 's16_2', 'role_title', 'Site Manager', 'appointment_letter_name', '16(2) letter.pdf',
         'appointed_on', current_date)) as ap \gset
select pg_temp.ok('the company admin adds a second section 16(2) person; the appointment letter goes to the private bucket bi-credentials',
  :'ap'::jsonb ->> 'appointment_letter_bucket' = 'bi-credentials'
  and :'ap'::jsonb ->> 'appointment_letter_path' = 'b1a00000-0000-4000-8000-000000000002/appointments/' || (:'ap'::jsonb ->> 'authorised_person_id') || '/16_2_letter.pdf');
select pg_temp.ok('several authorised persons per company, each with a role (16(1), 16(2) twice and a construction H&S officer)',
  (select array_agg(role order by role) from bi_authorised_person where client_account_id = 'b1a00000-0000-4000-8000-000000000002' and status = 'active')
    = array['construction_hs_officer','s16_1','s16_2','s16_2']);
select pg_temp.refuses('only one live section 16(1) person per company',
  $q$select bi_authorised_person_save('b1a00000-0000-4000-8000-000000000013', '{"client_account_id":"b1a00000-0000-4000-8000-000000000002","full_name":"Second Chief (fictitious)","role":"s16_1"}')$q$,
  'already has a live section 16\(1\) person');
select pg_temp.refuses('the assistant cannot add an authorised person',
  $q$select bi_authorised_person_save('b1a00000-0000-4000-8000-000000000012', '{"client_account_id":"b1a00000-0000-4000-8000-000000000002","full_name":"Someone (fictitious)","role":"first_aider"}')$q$, 'Not permitted');
select pg_temp.refuses('another tenant''s inspector cannot add one either',
  $q$select bi_authorised_person_save('b2a00000-0000-4000-8000-000000000011', '{"client_account_id":"b1a00000-0000-4000-8000-000000000002","full_name":"Someone (fictitious)","role":"first_aider"}')$q$, 'Not permitted');
select bi_person_credential_save('b1a00000-0000-4000-8000-000000000013', jsonb_build_object('authorised_person_id', :'ap'::jsonb ->> 'authorised_person_id',
         'credential_kind', 'qualification', 'title', 'SAMTRAC (fictitious)', 'issuer', 'NOSA (demonstration record)', 'number', 'DEMO-SAM-01',
         'issued_on', current_date - 30, 'expires_on', current_date + 700, 'certificate_name', 'samtrac certificate.pdf')) as cr \gset
select pg_temp.ok('a qualification with its certificate upload path and expiry, pending until Care Net verifies it',
  :'cr'::jsonb ->> 'status' = 'pending' and :'cr'::jsonb ->> 'certificate_bucket' = 'bi-credentials'
  and :'cr'::jsonb ->> 'certificate_path' like 'b1a00000-0000-4000-8000-000000000002/credentials/%/samtrac_certificate.pdf'
  and (select expires_on = current_date + 700 from bi_person_credential where id = (:'cr'::jsonb ->> 'credential_id')::uuid));
select pg_temp.refuses('only Care Net verifies a credential',
  $q$select bi_credential_verify('b1a00000-0000-4000-8000-000000000013', 'authorised_person', '$q$ || (:'cr'::jsonb ->> 'credential_id') || $q$', 'verified')$q$, 'Only Care Net');
select pg_temp.ok('ops verifies it', bi_credential_verify('b2a00000-0000-4000-8000-000000000013', 'authorised_person', (:'cr'::jsonb ->> 'credential_id')::uuid, 'verified') ->> 'status' = 'verified');
select pg_temp.ok('the company admin reads the credentials through bi_person_credential_list (2), each read audited as credential_read',
  jsonb_array_length(bi_person_credential_list('b1a00000-0000-4000-8000-000000000013', 'b1a00000-0000-4000-8000-000000000002')) = 2);
select pg_temp.ok('two credential_read audit rows', (select count(*) from bi_audit_log where event = 'credential_read' and actor_auth_user = 'b1a00000-0000-4000-8000-000000000013') = 2);
select pg_temp.refuses('the inspector cannot read the company''s credentials',
  $q$select bi_person_credential_list('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-000000000002')$q$, 'Not permitted');
update bi_person_credential set expires_on = current_date - 1 where id = 'b1a00000-0000-4000-8000-00000000003d';
select pg_temp.ok('the expiry run reports a lapsed credential',
  jsonb_array_length(bi_qualification_expiry_run(current_date) -> 'credentials' -> 'expired') = 1);
select pg_temp.ok('and marks it expired', (select status from bi_person_credential where id = 'b1a00000-0000-4000-8000-00000000003d') = 'expired');
select pg_temp.ok('an inspector''s qualification carries its credential kind (qualification by default; professional_registration allowed)',
  (select credential_kind from bi_inspector_qualification where id = 'b1a00000-0000-4000-8000-000000000027') = 'qualification'
  and (bi_qualification_list('b1a00000-0000-4000-8000-000000000011', 'b1a00000-0000-4000-8000-000000000021') -> 0 ->> 'credential_kind') = 'qualification');
select pg_temp.ok('the company admin ends an appointment',
  bi_authorised_person_save('b1a00000-0000-4000-8000-000000000013', jsonb_build_object('client_account_id', 'b1a00000-0000-4000-8000-000000000002',
    'id', :'ap'::jsonb ->> 'authorised_person_id', 'status', 'ended')) ? 'authorised_person_id');
select pg_temp.ok('it reads ended, with the date', (select status = 'ended' and ended_on = current_date from bi_authorised_person where id = (:'ap'::jsonb ->> 'authorised_person_id')::uuid));
select pg_temp.refuses('deleting an authorised person is refused', $q$delete from bi_authorised_person$q$, 'never deleted');

do $$ begin raise notice 'bi_rls_checks: all checks passed. Rolling back the test data.'; end $$;
rollback;
