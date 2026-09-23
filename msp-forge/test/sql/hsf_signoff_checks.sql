-- CNC MSP FORGE | HSF-REV-02 File sign off checks | local test harness only.
-- Proves migration 053 (build contract section 10.8, hsf/SIGNOFF-CRITERIA.md
-- sections 3 to 6) against a replayed database: the OMP is no longer a File
-- signatory, the chief executive acknowledgement is recorded but not a gate, the
-- signatory credentials and letters, the sign off rule by industry, and every
-- refusal of the redefined release gate, ending with releases that pass. Never
-- applied to Supabase. Everything runs in one transaction that is rolled back,
-- so the fictitious accounts, Files, practitioners and sign offs never persist.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_signoff_checks.sql
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

-- Runs p_sql and passes only when it succeeds.
create function pg_temp.accepts(p_name text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise notice 'ok   %', p_name;
exception when others then
  raise exception 'CHECK FAILED: % (refused with "%")', p_name, sqlerrm;
end $$;

create temp table ctx (k text primary key, v text);
create function pg_temp.ctx(p_k text) returns text language sql as $$ select v from ctx where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$
  insert into ctx values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
-- The role checks below run as authenticated, which still reads and writes the context.
grant select, insert, update on ctx to anon, authenticated;

-- A fictitious practitioner. Null dates leave the register check or a letter
-- unrecorded; every reference is a fixture path, never a real document.
create function pg_temp.sig(p_k text, p_body text, p_category text, p_expires date,
                            p_checked date, p_appointed date, p_engaged date) returns void language plpgsql as $$
declare
  v_id uuid;
begin
  insert into hsf_signatory (full_name, registration_body, category, registration_number, registration_expires_on,
                             register_checked_on, register_proof_ref,
                             appointment_letter_ref, appointment_letter_date,
                             engagement_letter_ref, engagement_letter_date, created_by)
  values ('Practitioner ' || p_k, p_body, p_category, 'FIXTURE-' || upper(p_k), p_expires,
          p_checked, case when p_checked is not null then 'fixture/register/' || p_k || '.pdf' end,
          case when p_appointed is not null then 'fixture/appointment/' || p_k || '.pdf' end, p_appointed,
          case when p_engaged is not null then 'fixture/engagement/' || p_k || '.pdf' end, p_engaged,
          'hsf_signoff_checks')
  returning id into v_id;
  perform pg_temp.put(p_k, v_id::text);
end $$;

-- An approved safety content sign off by a practitioner on a File revision; returns its id.
create function pg_temp.safety(p_file text, p_revision int, p_sig text, p_at timestamptz) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into hsf_signoff (file_id, revision, kind, decision, signatory_id, scope, decided_at)
  values (pg_temp.ctx(p_file)::uuid, p_revision, 'safety_content', 'approved', pg_temp.ctx(p_sig)::uuid,
          'Sections A to O of revision ' || p_revision, p_at)
  returning id into v_id;
  return v_id;
end $$;

create function pg_temp.accept(p_file text, p_revision int, p_kind text, p_decision text) returns void language sql as $$
  insert into hsf_signoff (file_id, revision, kind, decision, signatory_name, decided_at)
  values (pg_temp.ctx(p_file)::uuid, p_revision, p_kind, p_decision, 'Fixture appointee', '2026-09-23 12:00:00+02') $$;

create function pg_temp.release_sql(p_file text, p_revision int) returns text language sql as $$
  select format('insert into hsf_release (file_id, revision, pdf_path, evidence_index_path) values (%L, %s, ''x.pdf'', ''x.csv'')',
                pg_temp.ctx(p_file), p_revision) $$;

-- The decision day of every sign off below is 23/09/2026 (South African time).
select pg_temp.put('at', '2026-09-23 10:00:00+02');

-- Fixtures: one fictitious company, and a general industry (manufacturing), a
-- construction and a mining File. The general File carries one item, HSF-A-01,
-- whose instrument is not yet citable, so the citability rule is proved too.
insert into auth.users (id, email) values ('51511111-1111-4111-8111-111111111111', 'signoff.client@example.invalid');
insert into msp_client_account (id, company_name, contact_name, contact_email, auth_user_id) values
  ('5aaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Signoff Test Company (Pty) Ltd', 'Signoff Tester', 'signoff.client@example.invalid',
   '51511111-1111-4111-8111-111111111111');
insert into hsf_file (id, client_account_id, industry_id, regime, scope)
select '5f000001-0000-4000-8000-000000000001', '5aaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa', id, 'OHSA', '{}'::jsonb from msp_industry where code = 'MANU';
insert into hsf_file (id, client_account_id, industry_id, regime, scope)
select '5f000002-0000-4000-8000-000000000002', '5aaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa', id, 'OHSA', '{}'::jsonb from msp_industry where code = 'CONSTR';
insert into hsf_file (id, client_account_id, industry_id, regime, scope)
select '5f000003-0000-4000-8000-000000000003', '5aaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa', id, 'MHSA', '{}'::jsonb from msp_industry where code = 'MINING';
insert into hsf_file_item (file_id, element_id)
select '5f000001-0000-4000-8000-000000000001', id from hsf_element where code = 'HSF-A-01';
select pg_temp.put('gen', '5f000001-0000-4000-8000-000000000001');
select pg_temp.put('con', '5f000002-0000-4000-8000-000000000002');
select pg_temp.put('min', '5f000003-0000-4000-8000-000000000003');

-- key, body, category, expiry, register checked, appointment letter, engagement letter
select pg_temp.sig('grad',     'SAIOSH',  'GradSAIOSH', '2027-06-30', '2026-09-20', '2026-09-01', '2026-09-01');
select pg_temp.sig('cms',      'SAIOSH',  'CMSAIOSH',   '2027-06-30', '2026-09-20', '2026-09-01', '2026-09-01');
select pg_temp.sig('tech',     'SAIOSH',  'TechSAIOSH', '2027-06-30', '2026-09-20', '2026-09-01', '2026-09-01');
select pg_temp.sig('chso',     'SACPCMP', 'CHSO',       '2027-06-30', '2026-09-20', '2026-09-01', '2026-09-01');
select pg_temp.sig('chsm',     'SACPCMP', 'CHSM',       '2027-06-30', '2026-09-20', '2026-09-01', '2026-09-01');
select pg_temp.sig('cand',     'SACPCMP', 'Can CHSM',   '2027-06-30', '2026-09-20', '2026-09-01', '2026-09-01');
select pg_temp.sig('expired',  'SAIOSH',  'GradSAIOSH', '2026-09-22', '2026-09-20', '2026-09-01', '2026-09-01');
select pg_temp.sig('lastday',  'SAIOSH',  'CMSAIOSH',   '2026-09-23', '2026-09-20', '2026-09-01', '2026-09-01');
select pg_temp.sig('nocheck',  'SAIOSH',  'GradSAIOSH', '2027-06-30', null,         '2026-09-01', '2026-09-01');
select pg_temp.sig('latechk',  'SAIOSH',  'GradSAIOSH', '2027-06-30', '2026-09-24', '2026-09-01', '2026-09-01');
select pg_temp.sig('noappt',   'SAIOSH',  'GradSAIOSH', '2027-06-30', '2026-09-20', null,         '2026-09-01');
select pg_temp.sig('noeng',    'SAIOSH',  'GradSAIOSH', '2027-06-30', '2026-09-20', '2026-09-01', null);
select pg_temp.sig('lateappt', 'SAIOSH',  'GradSAIOSH', '2027-06-30', '2026-09-20', '2026-09-24', '2026-09-01');
select pg_temp.sig('lateeng',  'SAIOSH',  'GradSAIOSH', '2027-06-30', '2026-09-20', '2026-09-01', '2026-09-24');

-- 1. Objects, comments, definer settings and grants -------------------------------------------

select pg_temp.ok('hsf_signatory and hsf_signoff_rule exist with RLS enabled',
  (select count(*) from pg_class where relname in ('hsf_signatory','hsf_signoff_rule') and relkind = 'r' and relrowsecurity) = 2);
select pg_temp.ok('the kind check keeps omp_medical for history and adds ceo_16_1_acknowledgement',
  (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'hsf_signoff'::regclass and conname = 'hsf_signoff_kind_check')
    ~ 'omp_medical' and
  (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'hsf_signoff'::regclass and conname = 'hsf_signoff_kind_check')
    ~ 'ceo_16_1_acknowledgement');
select pg_temp.ok('hsf_signatory holds the credentials and both letters, each with a nullable recruitment portal reference',
  (select count(*) from information_schema.columns where table_name = 'hsf_signatory' and column_name in
     ('full_name','registration_body','category','registration_number','registration_expires_on','register_checked_on',
      'register_proof_ref','appointment_letter_ref','appointment_letter_date','appointment_letter_recruitment_portal_ref',
      'engagement_letter_ref','engagement_letter_date','engagement_letter_recruitment_portal_ref')) = 13
  and (select bool_and(is_nullable = 'YES') from information_schema.columns
        where table_name = 'hsf_signatory' and column_name like '%recruitment_portal_ref'));
select pg_temp.ok('no identity number column is stored for a signatory (SIGNOFF-CRITERIA 6.3)',
  not exists (select 1 from information_schema.columns
               where table_name = 'hsf_signatory' and column_name ~* '(^|_)(id_?(number|no)|identity|rsa_id|passport)'));
select pg_temp.ok('hsf_signoff gains signatory_id and scope',
  (select count(*) from information_schema.columns where table_name = 'hsf_signoff' and column_name in ('signatory_id','scope')) = 2);
select pg_temp.ok('every new table, column, function and trigger carries a comment',
  obj_description('hsf_signatory'::regclass, 'pg_class') is not null
  and obj_description('hsf_signoff_rule'::regclass, 'pg_class') is not null
  and not exists (select 1 from information_schema.columns c
                   where c.table_name in ('hsf_signatory','hsf_signoff_rule') and c.column_name not in ('id','created_at')
                     and col_description(('public.' || c.table_name)::regclass, c.ordinal_position) is null)
  and col_description('hsf_signoff'::regclass, (select attnum from pg_attribute where attrelid = 'hsf_signoff'::regclass and attname = 'signatory_id')) is not null
  and col_description('hsf_signoff'::regclass, (select attnum from pg_attribute where attrelid = 'hsf_signoff'::regclass and attname = 'scope')) is not null
  and not exists (select 1 from pg_proc where proname in ('hsf_signatory_guard','hsf_signoff_guard','hsf_signatory_sync','hsf_signatory_fit','hsf_release_gate')
                    and obj_description(oid, 'pg_proc') is null)
  and (select count(*) from pg_trigger where tgname in ('hsf_signatory_guard','hsf_signoff_guard','hsf_signatory_sync')
         and obj_description(oid, 'pg_trigger') is not null) = 3);
select pg_temp.ok('the sign off functions are security definer with search_path public',
  (select count(*) from pg_proc
    where proname in ('hsf_signatory_guard','hsf_signoff_guard','hsf_signatory_sync','hsf_signatory_fit','hsf_release_gate')
      and prosecdef and proconfig @> array['search_path=public']) = 5);
select pg_temp.ok('neither anon nor authenticated may execute them; the service role may run hsf_signatory_fit',
  not exists (select 1 from pg_proc p cross join (values ('anon'), ('authenticated')) r(role)
               where p.proname in ('hsf_signatory_guard','hsf_signoff_guard','hsf_signatory_sync','hsf_signatory_fit','hsf_release_gate')
                 and has_function_privilege(r.role, p.oid, 'execute'))
  and has_function_privilege('service_role', 'hsf_signatory_fit(uuid)', 'execute'));
select pg_temp.ok('the release gate trigger of 047 is still in place',
  exists (select 1 from pg_trigger where tgname = 'hsf_release_gate' and tgrelid = 'hsf_release'::regclass and not tgisinternal));
select pg_temp.ok('grants as 047: anon holds nothing, authenticated reads only, the service role holds all',
  not exists (select 1 from (values ('hsf_signatory'), ('hsf_signoff_rule')) t(n)
               where has_table_privilege('anon', t.n, 'select') or has_table_privilege('anon', t.n, 'insert')
                  or has_table_privilege('authenticated', t.n, 'insert') or has_table_privilege('authenticated', t.n, 'update')
                  or has_table_privilege('authenticated', t.n, 'delete') or not has_table_privilege('authenticated', t.n, 'select')
                  or not has_table_privilege('service_role', t.n, 'insert')));

-- 2. The rule table (SIGNOFF-CRITERIA section 5) ------------------------------------------------

select pg_temp.ok('13 rule rows: 3 construction, 5 mining, 5 general',
  (select count(*) from hsf_signoff_rule) = 13
  and (select count(*) from hsf_signoff_rule where file_type = 'construction') = 3
  and (select count(*) from hsf_signoff_rule where file_type = 'mining') = 5
  and (select count(*) from hsf_signoff_rule where file_type = 'general') = 5);
select pg_temp.ok('construction: SACPCMP Pr CHSA, CHSM and CHSO on the CONSTR industry',
  (select string_agg(r.registration_body || ' ' || r.category, ', ' order by r.category)
     from hsf_signoff_rule r join msp_industry i on i.id = r.industry_id where i.code = 'CONSTR')
  = 'SACPCMP CHSM, SACPCMP CHSO, SACPCMP Pr CHSA');
select pg_temp.ok('mining: the general list on the MINING industry, every row a practitioner review',
  (select string_agg(r.registration_body || ' ' || r.category, ', ' order by r.registration_body, r.category)
     from hsf_signoff_rule r join msp_industry i on i.id = r.industry_id where i.code = 'MINING' and r.practitioner_review)
  = 'SACPCMP CHSM, SACPCMP Pr CHSA, SAIOSH CMSAIOSH, SAIOSH GradSAIOSH, SAIOSH TechSAIOSH');
select pg_temp.ok('general: no industry, SACPCMP Pr CHSA and CHSM and SAIOSH CMSAIOSH, GradSAIOSH, TechSAIOSH, not a practitioner review',
  (select string_agg(r.registration_body || ' ' || r.category, ', ' order by r.registration_body, r.category)
     from hsf_signoff_rule r where r.industry_id is null and not r.practitioner_review)
  = 'SACPCMP CHSM, SACPCMP Pr CHSA, SAIOSH CMSAIOSH, SAIOSH GradSAIOSH, SAIOSH TechSAIOSH');
select pg_temp.ok('no candidate category is listed anywhere',
  not exists (select 1 from hsf_signoff_rule where category like 'Can %'));
select pg_temp.refuses('a candidate category cannot be added to the rule table',
  $q$insert into hsf_signoff_rule (file_type, registration_body, category, note) values ('general', 'SACPCMP', 'Can CHSM', 'x')$q$,
  'hsf_signoff_rule_(no_candidates|category_fits_body)');
select pg_temp.refuses('a general rule row cannot name an industry',
  $q$insert into hsf_signoff_rule (file_type, industry_id, registration_body, category, note)
     select 'general', id, 'SACPCMP', 'CHSO', 'x' from msp_industry where code = 'MANU'$q$,
  'hsf_signoff_rule_general_has_no_industry');

-- 3. Signatory credentials ------------------------------------------------------------------------

select pg_temp.refuses('a category of the other body is refused (SAIOSH CHSM)',
  $q$insert into hsf_signatory (full_name, registration_body, category, registration_number, registration_expires_on)
     values ('Fixture', 'SAIOSH', 'CHSM', 'FIXTURE-X1', '2027-01-01')$q$, 'hsf_signatory_category_fits_body');
select pg_temp.refuses('an unknown registering body is refused',
  $q$insert into hsf_signatory (full_name, registration_body, category, registration_number, registration_expires_on)
     values ('Fixture', 'NEBOSH', 'CHSM', 'FIXTURE-X2', '2027-01-01')$q$, 'hsf_signatory_(registration_body_check|category_fits_body)');
select pg_temp.refuses('a register check date without its saved proof is refused',
  $q$insert into hsf_signatory (full_name, registration_body, category, registration_number, registration_expires_on, register_checked_on)
     values ('Fixture', 'SAIOSH', 'CMSAIOSH', 'FIXTURE-X3', '2027-01-01', '2026-09-20')$q$, 'hsf_signatory_register_check_pair');
select pg_temp.refuses('an appointment letter reference without its date is refused',
  $q$insert into hsf_signatory (full_name, registration_body, category, registration_number, registration_expires_on, appointment_letter_ref)
     values ('Fixture', 'SAIOSH', 'CMSAIOSH', 'FIXTURE-X4', '2027-01-01', 'fixture/a.pdf')$q$, 'hsf_signatory_appointment_letter_pair');
select pg_temp.refuses('an engagement letter date without its reference is refused',
  $q$insert into hsf_signatory (full_name, registration_body, category, registration_number, registration_expires_on, engagement_letter_date)
     values ('Fixture', 'SAIOSH', 'CMSAIOSH', 'FIXTURE-X5', '2027-01-01', '2026-09-01')$q$, 'hsf_signatory_engagement_letter_pair');

-- 4. Sign off kinds -------------------------------------------------------------------------------

select pg_temp.refuses('a new omp_medical sign off is refused: the OMP signed plan is Section E evidence',
  format($q$insert into hsf_signoff (file_id, revision, kind, decision, signatory_name, registration_number, decided_at)
            values (%L, 1, 'omp_medical', 'approved', 'Fixture OMP', 'FIXTURE-MP', now())$q$, pg_temp.ctx('gen')),
  'not a File signatory.*Section E as evidence');
select pg_temp.refuses('a pending omp_medical sign off is refused too',
  format($q$insert into hsf_signoff (file_id, revision, kind) values (%L, 1, 'omp_medical')$q$, pg_temp.ctx('gen')),
  'not a File signatory');
insert into hsf_signoff (id, file_id, revision, kind) values ('5c000001-0000-4000-8000-000000000001', pg_temp.ctx('gen')::uuid, 90, 'client_16_2_acceptance');
select pg_temp.refuses('an existing sign off cannot be turned into omp_medical',
  $q$update hsf_signoff set kind = 'omp_medical' where id = '5c000001-0000-4000-8000-000000000001'$q$, 'not a File signatory');
-- A row from before 053 (written here with the guard off, as history would be) stays valid.
alter table hsf_signoff disable trigger hsf_signoff_guard;
insert into hsf_signoff (id, file_id, revision, kind, decision, signatory_name, registration_body, registration_number, decided_at)
values ('5c000002-0000-4000-8000-000000000002', pg_temp.ctx('gen')::uuid, 13, 'omp_medical', 'approved', 'Fixture OMP', 'HPCSA', 'FIXTURE-MP', now());
alter table hsf_signoff enable trigger hsf_signoff_guard;
select pg_temp.accepts('a historical omp_medical row keeps its place under the kind check (its note can still be updated)',
  $q$update hsf_signoff set notes = '{"history": true}'::jsonb where id = '5c000002-0000-4000-8000-000000000002'$q$);
select pg_temp.accepts('a chief executive acknowledgement is recorded without a registration number',
  format($q$insert into hsf_signoff (file_id, revision, kind, decision, signatory_name, decided_at)
            values (%L, 12, 'ceo_16_1_acknowledgement', 'approved', 'Fixture chief executive', now())$q$, pg_temp.ctx('gen')));
select pg_temp.refuses('a decided safety content sign off without signatory credentials is refused',
  format($q$insert into hsf_signoff (file_id, revision, kind, decision, signatory_name, registration_number, scope, decided_at)
            values (%L, 1, 'safety_content', 'approved', 'Fixture', 'FIXTURE-N', 'Sections A to O', now())$q$, pg_temp.ctx('gen')),
  'hsf_signoff_safety_decision_complete');
select pg_temp.refuses('a decided safety content sign off without a scope is refused',
  format($q$insert into hsf_signoff (file_id, revision, kind, decision, signatory_id, decided_at)
            values (%L, 1, 'safety_content', 'approved', %L, now())$q$, pg_temp.ctx('gen'), pg_temp.ctx('grad')),
  'hsf_signoff_safety_decision_complete');
select pg_temp.refuses('only a safety content sign off carries a signatory',
  format($q$insert into hsf_signoff (file_id, revision, kind, decision, signatory_id, signatory_name, decided_at)
            values (%L, 1, 'client_16_2_acceptance', 'approved', %L, 'Fixture appointee', now())$q$, pg_temp.ctx('gen'), pg_temp.ctx('grad')),
  'hsf_signoff_signatory_is_safety');
insert into hsf_signoff (id, file_id, revision, kind, signatory_id, signatory_name, registration_body, registration_number)
values ('5c000003-0000-4000-8000-000000000003', pg_temp.ctx('gen')::uuid, 2, 'safety_content', pg_temp.ctx('grad')::uuid, 'Someone else', 'SACPCMP', 'WRONG');
select pg_temp.ok('the sign off copies name, body and number from its credential record',
  (select signatory_name = 'Practitioner grad' and registration_body = 'SAIOSH' and registration_number = 'FIXTURE-GRAD'
     from hsf_signoff where id = '5c000003-0000-4000-8000-000000000003'));

-- 5. The release gate: every refusal (general industry File) -----------------------------------------

select pg_temp.refuses('release refused with no sign offs',
  pg_temp.release_sql('gen', 1), '^hsf_release_gate: safety_content sign off is not approved for this File revision$');
-- Revision 2 holds only the pending sign off above, and a rejected one.
insert into hsf_signoff (file_id, revision, kind, decision, signatory_id, scope, decided_at)
values (pg_temp.ctx('gen')::uuid, 2, 'safety_content', 'rejected', pg_temp.ctx('grad')::uuid, 'Sections A to O', pg_temp.ctx('at')::timestamptz);
select pg_temp.refuses('release refused while the safety content sign off is pending or rejected',
  pg_temp.release_sql('gen', 2), 'safety_content sign off is not approved');

select pg_temp.safety('gen', 3, 'chso', pg_temp.ctx('at')::timestamptz);
select pg_temp.accept('gen', 3, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused: a construction category (SACPCMP CHSO) does not fit a general industry File',
  pg_temp.release_sql('gen', 3),
  'SACPCMP CHSO may not sign the safety content of a general File; allowed: SACPCMP CHSM, SACPCMP Pr CHSA, SAIOSH CMSAIOSH, SAIOSH GradSAIOSH, SAIOSH TechSAIOSH$');

select pg_temp.safety('gen', 4, 'cand', pg_temp.ctx('at')::timestamptz);
select pg_temp.accept('gen', 4, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused: a candidate category never signs alone',
  pg_temp.release_sql('gen', 4), 'candidate category \(SACPCMP Can CHSM\) and never signs a File alone');

select pg_temp.safety('gen', 5, 'expired', pg_temp.ctx('at')::timestamptz);
select pg_temp.accept('gen', 5, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused: the registration expired before the decision date',
  pg_temp.release_sql('gen', 5), 'registration of Practitioner expired \(SAIOSH FIXTURE-EXPIRED\) expired on 22/09/2026, before the decision on 23/09/2026');

-- 23:30 UTC on 22/09 is 01:30 on 23/09 in South Africa: the registration has expired by then.
select pg_temp.safety('gen', 6, 'expired', '2026-09-22 23:30:00+00');
select pg_temp.accept('gen', 6, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused: the decision date is the South African calendar day',
  pg_temp.release_sql('gen', 6), 'expired on 22/09/2026, before the decision on 23/09/2026');

select pg_temp.safety('gen', 7, 'nocheck', pg_temp.ctx('at')::timestamptz);
select pg_temp.accept('gen', 7, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused: the register check is missing',
  pg_temp.release_sql('gen', 7), 'check of the SAIOSH public register for Practitioner nocheck is not recorded');

select pg_temp.safety('gen', 8, 'latechk', pg_temp.ctx('at')::timestamptz);
select pg_temp.accept('gen', 8, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused: the register was checked after the decision',
  pg_temp.release_sql('gen', 8), 'SAIOSH register was checked on 24/09/2026, after the decision on 23/09/2026');

select pg_temp.safety('gen', 9, 'noappt', pg_temp.ctx('at')::timestamptz);
select pg_temp.accept('gen', 9, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused: the appointment letter is missing',
  pg_temp.release_sql('gen', 9), 'appointment letter of Practitioner noappt is not on record');

select pg_temp.safety('gen', 10, 'noeng', pg_temp.ctx('at')::timestamptz);
select pg_temp.accept('gen', 10, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused: the engagement letter is missing',
  pg_temp.release_sql('gen', 10), 'engagement letter of Practitioner noeng is not on record');

select pg_temp.safety('gen', 11, 'lateappt', pg_temp.ctx('at')::timestamptz);
select pg_temp.safety('gen', 11, 'lateeng', pg_temp.ctx('at')::timestamptz - interval '1 hour');
select pg_temp.accept('gen', 11, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused: letters dated after the decision do not count (the latest decision''s reason is given)',
  pg_temp.release_sql('gen', 11), 'appointment letter of Practitioner lateappt is dated 24/09/2026, after the decision on 23/09/2026');
select pg_temp.ok('hsf_signatory_fit names the engagement letter dated after the decision',
  hsf_signatory_fit((select id from hsf_signoff where file_id = pg_temp.ctx('gen')::uuid and revision = 11
                       and signatory_id = pg_temp.ctx('lateeng')::uuid))
  = 'the engagement letter of Practitioner lateeng is dated 24/09/2026, after the decision on 23/09/2026');

-- Revision 12: a fitting practitioner, but the client has not accepted. The
-- chief executive acknowledgement (recorded above) does not stand in for it.
select pg_temp.safety('gen', 12, 'grad', pg_temp.ctx('at')::timestamptz);
select pg_temp.refuses('release refused without the client section 16(2) acceptance, even with the chief executive acknowledgement',
  pg_temp.release_sql('gen', 12), '^hsf_release_gate: client_16_2_acceptance sign off is not approved for this File revision$');
select pg_temp.accept('gen', 12, 'client_16_2_acceptance', 'rejected');
select pg_temp.refuses('release refused while the client acceptance is rejected',
  pg_temp.release_sql('gen', 12), 'client_16_2_acceptance sign off is not approved');

-- Revision 13: fitting practitioner and client acceptance, no chief executive
-- acknowledgement and only the historical OMP row. The citability rule of 047
-- and 050 still refuses: HSF-A-01 names the OHS Act, awaiting verification.
select pg_temp.safety('gen', 13, 'cms', pg_temp.ctx('at')::timestamptz);
select pg_temp.accept('gen', 13, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('release refused while the File cites an instrument not verified for a File (citability kept)',
  pg_temp.release_sql('gen', 13), 'the File cites instruments that are not verified for a File: OHS Act');

-- Pin the provision and move the scope inside this transaction, as hsf_core_checks does.
update hsf_element_instrument set provision = 'Check provision (rolled back)'
 where element_id = (select id from hsf_element where code = 'HSF-A-01')
   and instrument_id in (select id from msp_legal_instrument where short_name = 'OHS Act');
update msp_legal_instrument set scope = 'both' where short_name = 'OHS Act' and status = 'verified';

select pg_temp.accepts('release accepted: fitting, current, register checked and appointed practitioner, client acceptance, citable instruments',
  pg_temp.release_sql('gen', 13));
select pg_temp.ok('neither the OMP nor the chief executive was needed for that release',
  not exists (select 1 from hsf_signoff where file_id = pg_temp.ctx('gen')::uuid and revision = 13 and kind = 'ceo_16_1_acknowledgement')
  and exists (select 1 from hsf_release where file_id = pg_temp.ctx('gen')::uuid and revision = 13));

-- Revision 14: the registration expires on the decision day itself (still
-- current), and a later candidate decision does not undo an earlier fitting one.
select pg_temp.safety('gen', 14, 'lastday', pg_temp.ctx('at')::timestamptz);
select pg_temp.safety('gen', 14, 'cand', pg_temp.ctx('at')::timestamptz + interval '1 hour');
select pg_temp.accept('gen', 14, 'client_16_2_acceptance', 'approved');
select pg_temp.accepts('release accepted: a registration that expires on the decision day is current, and one fitting approval suffices',
  pg_temp.release_sql('gen', 14));

-- 6. Construction and mining Files ---------------------------------------------------------------------

-- hsf_signatory_fit is stable, so it reads the sign off in a statement after the insert.
select pg_temp.put('so_con_cms', pg_temp.safety('con', 1, 'cms', pg_temp.ctx('at')::timestamptz)::text);
select pg_temp.put('so_con_chso', pg_temp.safety('con', 2, 'chso', pg_temp.ctx('at')::timestamptz)::text);
select pg_temp.put('so_min_chso', pg_temp.safety('min', 1, 'chso', pg_temp.ctx('at')::timestamptz)::text);
select pg_temp.put('so_min_tech', pg_temp.safety('min', 2, 'tech', pg_temp.ctx('at')::timestamptz)::text);
select pg_temp.put('so_gen_chsm', pg_temp.safety('gen', 15, 'chsm', pg_temp.ctx('at')::timestamptz)::text);
select pg_temp.ok('construction: SAIOSH CMSAIOSH may not sign',
  hsf_signatory_fit(pg_temp.ctx('so_con_cms')::uuid)
  = 'SAIOSH CMSAIOSH may not sign the safety content of a construction File; allowed: SACPCMP CHSM, SACPCMP CHSO, SACPCMP Pr CHSA');
select pg_temp.accept('con', 1, 'client_16_2_acceptance', 'approved');
select pg_temp.refuses('construction release refused with a SAIOSH signatory only',
  pg_temp.release_sql('con', 1), 'may not sign the safety content of a construction File');
select pg_temp.ok('construction: SACPCMP CHSO fits',
  hsf_signatory_fit(pg_temp.ctx('so_con_chso')::uuid) is null);
select pg_temp.accept('con', 2, 'client_16_2_acceptance', 'approved');
select pg_temp.accepts('construction release accepted with a SACPCMP CHSO and the client acceptance',
  pg_temp.release_sql('con', 2));

select pg_temp.ok('mining: SACPCMP CHSO may not sign',
  hsf_signatory_fit(pg_temp.ctx('so_min_chso')::uuid)
  = 'SACPCMP CHSO may not sign the safety content of a mining File; allowed: SACPCMP CHSM, SACPCMP Pr CHSA, SAIOSH CMSAIOSH, SAIOSH GradSAIOSH, SAIOSH TechSAIOSH');
select pg_temp.ok('mining: SAIOSH TechSAIOSH fits (as a practitioner review)',
  hsf_signatory_fit(pg_temp.ctx('so_min_tech')::uuid) is null);
select pg_temp.ok('general: SACPCMP CHSM fits',
  hsf_signatory_fit(pg_temp.ctx('so_gen_chsm')::uuid) is null);

-- 7. Credentials after a release ----------------------------------------------------------------------

select pg_temp.accepts('before any release, a credential record may be corrected',
  format($q$update hsf_signatory set full_name = 'Practitioner tech corrected' where id = %L$q$, pg_temp.ctx('tech')));
select pg_temp.ok('the correction reaches its unreleased sign off',
  (select signatory_name from hsf_signoff where file_id = pg_temp.ctx('min')::uuid and revision = 2) = 'Practitioner tech corrected');
select pg_temp.refuses('credentials that support a released File are frozen',
  format($q$update hsf_signatory set registration_expires_on = '2030-01-01' where id = %L$q$, pg_temp.ctx('chso')), 'frozen');
select pg_temp.refuses('credentials that support a released File cannot be deleted',
  format($q$delete from hsf_signatory where id = %L$q$, pg_temp.ctx('chso')), 'cannot be deleted');
select pg_temp.accepts('the recruitment portal reference of a letter may be added once after the release',
  format($q$update hsf_signatory set appointment_letter_recruitment_portal_ref = 'FIXTURE-PORTAL-1' where id = %L$q$, pg_temp.ctx('chso')));
select pg_temp.refuses('and is never changed afterwards',
  format($q$update hsf_signatory set appointment_letter_recruitment_portal_ref = 'FIXTURE-PORTAL-2' where id = %L$q$, pg_temp.ctx('chso')),
  'set once and never changed');

-- 8. Row Level Security as the web tier would see it -------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "51511111-1111-4111-8111-111111111111", "role": "authenticated"}', true);
select pg_temp.put('client_sigs', (select count(*) from hsf_signatory)::text);
select pg_temp.put('client_rules', (select count(*) from hsf_signoff_rule)::text);
select pg_temp.put('client_signoffs', (select count(*) from hsf_signoff)::text);
select set_config('request.jwt.claims', '{"sub": "51522222-2222-4222-8222-222222222222", "role": "authenticated", "app_metadata": {"msp_roles": ["forge_safety_reviewer"]}}', true);
select pg_temp.put('staff_sigs', (select count(*) from hsf_signatory)::text);
reset role;
select set_config('request.jwt.claims', '', true);

select pg_temp.ok('a client reads no signatory credentials', pg_temp.ctx('client_sigs') = '0');
select pg_temp.ok('a client reads the rule table', pg_temp.ctx('client_rules') = '13');
select pg_temp.ok('a client reads the sign offs of its own Files (047 policy unchanged)',
  pg_temp.ctx('client_signoffs')::int = (select count(*) from hsf_signoff where file_id in
    (pg_temp.ctx('gen')::uuid, pg_temp.ctx('con')::uuid, pg_temp.ctx('min')::uuid)));
select pg_temp.ok('staff read every signatory', pg_temp.ctx('staff_sigs')::int = (select count(*) from hsf_signatory));

do $$ begin raise notice 'hsf_signoff_checks: all checks passed. Rolling back the test data.'; end $$;
rollback;
