-- CNC MSP FORGE | HSF-SCH-01 and HSF-SEED-01 checks | local test harness only.
-- Proves migrations 047 (core schema) and 048 (library seed) against a replayed
-- database. Never applied to Supabase. Everything runs in one transaction that
-- is rolled back, so the test data it creates never persists.
--
-- Usage (from msp-forge/). The release gate of 047 calls hsf_element_citable,
-- which migration 050 defines (contract 9.3), and migration 053 redefines the
-- gate with the sign off rule (contract 10.8), so replay every migration first:
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_core_checks.sql
--
-- Exact before and after comparison of the kernel instrument rows (optional):
--   test/sql/replay.sh 47
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -c "create table hsf_check_instrument_before as
--     select id, md5(to_jsonb(li)::text) as row_md5, status from msp_legal_instrument li"
--   for n in 048 049 050 051; do psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 \
--     -f supabase/migrations/${n}_*.sql; done
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_core_checks.sql
-- Without the snapshot table the check falls back to the status counts that
-- migrations 001 to 046 leave behind.
--
-- The script prints every check and ends with an error when any check fails.

\set ON_ERROR_STOP 1
\pset pager off
begin;

create temp table hsf_check (n serial primary key, name text not null, expected text, actual text, pass boolean not null);

create temp view hsf_check_candidate as
select li.* from msp_legal_instrument li
 where li.status = 'pending' and li.scope = 'safety'
   and li.source_one = 'Gate a pending' and li.source_two = 'Gate b pending' and li.source_three = 'Gate c pending';

-- 1. Library counts ------------------------------------------------------------------

insert into hsf_check (name, expected, actual, pass)
select v.name, v.expected::text, v.actual::text, v.expected = v.actual
  from (values
    ('hsf_section rows (A to O)', 15, (select count(*)::int from hsf_section)),
    ('hsf_section E signed by the OMP, the rest by safety', 15, (select count(*)::int from hsf_section where signatory_kind = case when code = 'E' then 'omp' else 'safety' end)),
    ('hsf_department rows', 9, (select count(*)::int from hsf_department)),
    ('hsf_trigger vocabulary rows (SPEC B9.2)', 44, (select count(*)::int from hsf_trigger where code !~ ' (and|or) ')),
    ('hsf_trigger compound rows used by the library', 5, (select count(*)::int from hsf_trigger where code ~ ' (and|or) ')),
    ('hsf_appointment_type rows (APP-00 to APP-40)', 41, (select count(*)::int from hsf_appointment_type)),
    ('hsf_appointment_type rows with an instrument', 41, (select count(*)::int from hsf_appointment_type where instrument_id is not null)),
    ('hsf_element universal rows (SPEC B6.17)', 137, (select count(*)::int from hsf_element where universal)),
    ('hsf_element overlay rows (SPEC B7.19)', 119, (select count(*)::int from hsf_element where not universal)),
    ('hsf_element total', 256, (select count(*)::int from hsf_element)),
    ('hsf_element rows not awaiting (must be none at load)', 0, (select count(*)::int from hsf_element where basis_state <> 'awaiting')),
    ('hsf_element_class courses (B6.5.1)', 17, (select count(*)::int from hsf_element_class where kind = 'course')),
    ('hsf_element_class licence classes (B6.5.2)', 7, (select count(*)::int from hsf_element_class where kind = 'licence')),
    ('hsf_element_class examination classes (HSF-E-06)', 10, (select count(*)::int from hsf_element_class where kind = 'examination')),
    ('hsf_element_industry overlay addition rows', 119, (select count(*)::int from hsf_element_industry x join hsf_element e on e.id = x.element_id where not e.universal)),
    ('hsf_element_industry overlay rows on the right industry', 119, (select count(*)::int from hsf_element_industry x join hsf_element e on e.id = x.element_id join msp_industry i on i.id = x.industry_id where not e.universal and e.code like 'HSF-OV-' || i.code || '-%')),
    ('hsf_element_industry kernel pack protocol rows (HSF-E-06, one per industry)', 17, (select count(*)::int from hsf_element_industry x join hsf_element e on e.id = x.element_id where e.code = 'HSF-E-06' and x.applicability = 'emphasis')),
    ('hsf_element_industry rows switched on by overlays', 1, (select sign(count(*))::int from hsf_element_industry x join hsf_element e on e.id = x.element_id where e.universal and e.code <> 'HSF-E-06')),
    ('hsf_training_requirement rows (not seeded until Phase 3)', 0, (select count(*)::int from hsf_training_requirement))
  ) as v(name, expected, actual);

-- 2. Instrument links ------------------------------------------------------------------

insert into hsf_check (name, expected, actual, pass)
select v.name, v.expected::text, v.actual::text, v.expected = v.actual
  from (values
    ('hsf_element_instrument links not reading awaiting verification', 0, (select count(*)::int from hsf_element_instrument where provision <> 'awaiting verification')),
    ('elements with no instrument link, other than E-01, N-06 and OV-EDU-06 (kernel data or reference only by design)', 0,
      (select count(*)::int from hsf_element e where not exists (select 1 from hsf_element_instrument x where x.element_id = e.id)
          and e.code not in ('HSF-E-01','HSF-N-06','HSF-OV-EDU-06'))),
    ('elements linked to a superseded or excluded instrument', 0,
      (select count(*)::int from hsf_element_instrument x join msp_legal_instrument li on li.id = x.instrument_id where li.status in ('superseded','excluded'))),
    ('elements linked to a pending duplicate of a dated regulation (HSF-8)', 0,
      (select count(*)::int from hsf_element_instrument x join msp_legal_instrument li on li.id = x.instrument_id
        where li.short_name in ('General Administrative Regulations','General Machinery Regulations','General Safety Regulations'))),
    ('HSF-A-01 cites the OHS Act', 1, (select count(*)::int from hsf_element_instrument x join hsf_element e on e.id = x.element_id join msp_legal_instrument li on li.id = x.instrument_id where e.code = 'HSF-A-01' and li.short_name = 'OHS Act')),
    ('HSF-F-08 cites the Pressure Equipment Regulations, 2009 candidate', 1, (select count(*)::int from hsf_element_instrument x join hsf_element e on e.id = x.element_id join hsf_check_candidate c on c.id = x.instrument_id where e.code = 'HSF-F-08' and c.short_name = 'Pressure Equipment Regulations, 2009')),
    ('HSF-E-06 cites its ten examination instruments', 10, (select count(*)::int from hsf_element_instrument x join hsf_element e on e.id = x.element_id where e.code = 'HSF-E-06'))
  ) as v(name, expected, actual);

-- 3. Candidate instruments ---------------------------------------------------------------

insert into hsf_check (name, expected, actual, pass)
select v.name, v.expected::text, v.actual::text, v.expected = v.actual
  from (values
    ('pending candidate instruments (scope safety, gates a to c pending)', 36, (select count(*)::int from hsf_check_candidate)),
    ('candidates cited by no element, appointment type or class', 0,
      (select count(*)::int from hsf_check_candidate c
        where not exists (select 1 from hsf_element_instrument x where x.instrument_id = c.id)
          and not exists (select 1 from hsf_appointment_type a where a.instrument_id = c.id)
          and not exists (select 1 from hsf_element_class k where k.instrument_id = c.id))),
    ('candidates with a short_name the kernel already held', 0,
      (select count(*)::int from hsf_check_candidate c where exists (select 1 from msp_legal_instrument li where li.short_name = c.short_name and li.id <> c.id))),
    ('candidates visible in the public register (must be none)', 0,
      (select count(*)::int from msp_public_instrument_register r join hsf_check_candidate c on c.short_name = r.short_name)),
    ('candidate short names with dash punctuation (house rule)', 0,
      (select count(*)::int from hsf_check_candidate where short_name ~ ('[' || chr(8211) || chr(8212) || ']') or short_name ~ ' - '))
  ) as v(name, expected, actual);

-- 4. Existing instrument rows are untouched ---------------------------------------------

insert into hsf_check (name, expected, actual, pass)
select v.name, v.expected, v.actual, v.expected = v.actual
  from (values
    ('pre existing instruments by status (baseline of migrations 001 to 046)',
     'excluded 1, pending 3, superseded 2, verified 37',
     (select string_agg(status || ' ' || n, ', ' order by status)
        from (select status, count(*) as n from msp_legal_instrument li
               where li.id not in (select id from hsf_check_candidate) group by status) s)),
    ('pre existing instruments not on scope medical (047 default; 048 must not touch them)', '0',
     (select count(*)::text from msp_legal_instrument li where li.id not in (select id from hsf_check_candidate) and li.scope <> 'medical'))
  ) as v(name, expected, actual);

do $$
begin
  if to_regclass('public.hsf_check_instrument_before') is not null then
    insert into hsf_check (name, expected, actual, pass)
    select 'snapshot: instrument rows changed or removed by 048', '0', count(*)::text, count(*) = 0
      from hsf_check_instrument_before b
     where not exists (select 1 from msp_legal_instrument li
                        where li.id = b.id and md5(to_jsonb(li)::text) = b.row_md5);
    insert into hsf_check (name, expected, actual, pass)
    select 'snapshot: rows added by 048 that are not pending safety candidates', '0', count(*)::text, count(*) = 0
      from msp_legal_instrument li
     where li.id not in (select id from hsf_check_instrument_before)
       and li.id not in (select id from hsf_check_candidate);
  else
    insert into hsf_check (name, expected, actual, pass)
    values ('snapshot comparison skipped (no hsf_check_instrument_before table)', 'skipped', 'skipped', true);
  end if;
end;
$$;

-- 5. Idempotency: running 048 again changes nothing -----------------------------------------

create temp table hsf_check_state as
select 'instrument' as t, md5(string_agg(md5(to_jsonb(li)::text), '' order by li.id)) as h, count(*) as n from msp_legal_instrument li
union all select 'element', md5(string_agg(md5(to_jsonb(e)::text), '' order by e.code)), count(*) from hsf_element e
union all select 'link', null, count(*) from hsf_element_instrument
union all select 'industry', null, count(*) from hsf_element_industry
union all select 'appointment', md5(string_agg(md5(to_jsonb(a)::text), '' order by a.code)), count(*) from hsf_appointment_type a
union all select 'class', null, count(*) from hsf_element_class
union all select 'trigger', null, count(*) from hsf_trigger;

\ir ../../supabase/migrations/048_hsf_library_seed.sql

insert into hsf_check (name, expected, actual, pass)
select 'second run of 048 leaves ' || s.t || ' unchanged', coalesce(s.h, s.n::text), coalesce(c.h, c.n::text),
       s.n = c.n and s.h is not distinct from c.h
  from hsf_check_state s
  join (select 'instrument' as t, md5(string_agg(md5(to_jsonb(li)::text), '' order by li.id)) as h, count(*) as n from msp_legal_instrument li
        union all select 'element', md5(string_agg(md5(to_jsonb(e)::text), '' order by e.code)), count(*) from hsf_element e
        union all select 'link', null, count(*) from hsf_element_instrument
        union all select 'industry', null, count(*) from hsf_element_industry
        union all select 'appointment', md5(string_agg(md5(to_jsonb(a)::text), '' order by a.code)), count(*) from hsf_appointment_type a
        union all select 'class', null, count(*) from hsf_element_class
        union all select 'trigger', null, count(*) from hsf_trigger) c on c.t = s.t;

-- 6. Grants and Row Level Security ------------------------------------------------------------

create temp table hsf_check_tables as
select c.relname::text as t,
       c.relname in ('hsf_file','hsf_file_item','hsf_evidence','hsf_person','hsf_appointment',
                     'hsf_revision','hsf_signoff','hsf_release') as engagement,
       c.relrowsecurity as rls, c.relacl
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'hsf\_%'
   and c.relname not like 'hsf\_check%'
   -- The 047 tables only; 049 adds hsf_consent, hsf_upload and hsf_mco_transfer, checked in hsf_flow_checks.sql,
   -- 052 adds hsf_client_verification and hsf_deletion_request, checked in hsf_launch_checks.sql,
   -- and 053 adds hsf_signatory and hsf_signoff_rule, checked in hsf_signoff_checks.sql.
   and c.relname not in ('hsf_consent', 'hsf_upload', 'hsf_mco_transfer', 'hsf_client_verification', 'hsf_deletion_request',
                         'hsf_signatory', 'hsf_signoff_rule');

insert into hsf_check (name, expected, actual, pass)
select v.name, v.expected::text, v.actual::text, v.expected = v.actual
  from (values
    ('hsf tables found', 17, (select count(*)::int from hsf_check_tables)),
    ('hsf tables without RLS enabled', 0, (select count(*)::int from hsf_check_tables where not rls)),
    ('engagement tables anon can select', 0, (select count(*)::int from hsf_check_tables where engagement and has_table_privilege('anon', t, 'select'))),
    ('hsf tables anon holds any privilege on', 0, (select count(*)::int from hsf_check_tables
        where has_table_privilege('anon', t, 'select') or has_table_privilege('anon', t, 'insert')
           or has_table_privilege('anon', t, 'update') or has_table_privilege('anon', t, 'delete'))),
    ('hsf tables with a grant to public', 0, (select count(*)::int from hsf_check_tables k
        where k.relacl is not null and exists (select 1 from aclexplode(k.relacl) a where a.grantee = 0))),
    ('hsf tables authenticated can write', 0, (select count(*)::int from hsf_check_tables
        where has_table_privilege('authenticated', t, 'insert') or has_table_privilege('authenticated', t, 'update')
           or has_table_privilege('authenticated', t, 'delete') or has_table_privilege('authenticated', t, 'truncate'))),
    ('hsf tables authenticated can read (RLS then filters)', 17, (select count(*)::int from hsf_check_tables where has_table_privilege('authenticated', t, 'select'))),
    ('hsf_next_reference executable by anon or authenticated', 0,
      (select (has_function_privilege('anon', 'hsf_next_reference()', 'execute')::int + has_function_privilege('authenticated', 'hsf_next_reference()', 'execute')::int))),
    ('msp_audit.hsf_file_id column present', 1, (select count(*)::int from information_schema.columns where table_name = 'msp_audit' and column_name = 'hsf_file_id')),
    ('msp_legal_instrument.scope and msp_industry_instrument.scope present', 2,
      (select count(*)::int from information_schema.columns where table_name in ('msp_legal_instrument','msp_industry_instrument') and column_name = 'scope')),
    ('msp_client_account.mco_company_ref present', 1, (select count(*)::int from information_schema.columns where table_name = 'msp_client_account' and column_name = 'mco_company_ref'))
  ) as v(name, expected, actual);

-- 7. Engagement fixtures (rolled back at the end) ---------------------------------------------

create or replace function pg_temp.hsf_try(p_name text, p_sql text, p_expect_ok boolean) returns void
language plpgsql as $$
declare
  v_ok boolean := true;
  v_err text;
begin
  begin
    execute p_sql;
  exception when others then
    v_ok := false;
    v_err := sqlerrm;
  end;
  insert into hsf_check (name, expected, actual, pass)
  values (p_name, case when p_expect_ok then 'accepted' else 'refused' end,
          case when v_ok then 'accepted' else 'refused: ' || v_err end, v_ok = p_expect_ok);
end;
$$;


insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'client.a@example.invalid'),
  ('00000000-0000-4000-8000-00000000000b', 'client.b@example.invalid');
insert into msp_client_account (id, company_name, contact_name, contact_email, auth_user_id) values
  ('00000000-0000-4000-8000-0000000000aa', 'Fictitious Company A (Pty) Ltd', 'Contact A', 'client.a@example.invalid', '00000000-0000-4000-8000-00000000000a'),
  ('00000000-0000-4000-8000-0000000000bb', 'Fictitious Company B (Pty) Ltd', 'Contact B', 'client.b@example.invalid', '00000000-0000-4000-8000-00000000000b');
insert into hsf_file (id, client_account_id, industry_id, regime, scope)
select '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000aa', id, 'OHSA', '{"sites": [{"name": "Test site"}]}'::jsonb
  from msp_industry where code = 'CONSTR';
insert into hsf_file (id, client_account_id, industry_id, regime, scope)
select '00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-0000000000aa', id, 'OHSA', '{}'::jsonb
  from msp_industry where code = 'CONSTR';
insert into hsf_file_item (id, file_id, element_id)
select '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1', id from hsf_element where code = 'HSF-A-01';
insert into hsf_evidence (id, file_item_id, version, source, storage_path, sha256, supplied_by)
values ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000c1', 1, 'client_upload',
        '00000000-0000-4000-8000-0000000000aa/upload/test.pdf', repeat('ab', 32), 'client.a@example.invalid');
insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
values ('hsf_core_checks', 'hsf_check', '{}'::jsonb, '00000000-0000-4000-8000-0000000000f1');

insert into hsf_check (name, expected, actual, pass)
select 'hsf_file references are CNC-HSF-YYYY-MMDD-NNN, gap safe and sequential',
       'CNC-HSF-' || to_char(current_date, 'YYYY-MMDD') || '-001, -002',
       string_agg(reference, ', ' order by reference),
       string_agg(reference, ', ' order by reference) =
         'CNC-HSF-' || to_char(current_date, 'YYYY-MMDD') || '-001, CNC-HSF-' || to_char(current_date, 'YYYY-MMDD') || '-002'
  from hsf_file;

select pg_temp.hsf_try('not_applicable without a ten character reason is refused',
  $q$update hsf_file_item set status = 'not_applicable', reason = 'short' where id = '00000000-0000-4000-8000-0000000000c1'$q$, false);
select pg_temp.hsf_try('not_applicable with a written reason is accepted',
  $q$update hsf_file_item set status = 'not_applicable', reason = 'No such activity at this site' where id = '00000000-0000-4000-8000-0000000000c1'$q$, true);
update hsf_file_item set status = 'outstanding', reason = null where id = '00000000-0000-4000-8000-0000000000c1';

-- 8. hsf_evidence append only guard -------------------------------------------------------------


select pg_temp.hsf_try('evidence: changing the hash is refused',
  $q$update hsf_evidence set sha256 = repeat('cd', 32) where id = '00000000-0000-4000-8000-0000000000e1'$q$, false);
select pg_temp.hsf_try('evidence: delete is refused',
  $q$delete from hsf_evidence where id = '00000000-0000-4000-8000-0000000000e1'$q$, false);
select pg_temp.hsf_try('evidence: clearing storage_path without the staging deletion is refused',
  $q$update hsf_evidence set storage_path = null where id = '00000000-0000-4000-8000-0000000000e1'$q$, false);
select pg_temp.hsf_try('evidence: staging deletion while storage_path is kept is refused',
  $q$update hsf_evidence set staging_deleted_at = now() where id = '00000000-0000-4000-8000-0000000000e1'$q$, false);
select pg_temp.hsf_try('evidence: mco_document_ref alone (without transferred_at) is refused',
  $q$update hsf_evidence set mco_document_ref = 'FIXTURE-1' where id = '00000000-0000-4000-8000-0000000000e1'$q$, false);
select pg_temp.hsf_try('evidence: recording the transfer once is accepted',
  $q$update hsf_evidence set mco_document_ref = 'FIXTURE-1', transferred_at = now() where id = '00000000-0000-4000-8000-0000000000e1'$q$, true);
select pg_temp.hsf_try('evidence: changing the transfer record is refused',
  $q$update hsf_evidence set mco_document_ref = 'FIXTURE-2' where id = '00000000-0000-4000-8000-0000000000e1'$q$, false);
select pg_temp.hsf_try('evidence: staging deletion with storage_path null is accepted',
  $q$update hsf_evidence set staging_deleted_at = now(), storage_path = null where id = '00000000-0000-4000-8000-0000000000e1'$q$, true);
select pg_temp.hsf_try('evidence: a second staging deletion is refused',
  $q$update hsf_evidence set staging_deleted_at = now() + interval '1 day' where id = '00000000-0000-4000-8000-0000000000e1'$q$, false);
select pg_temp.hsf_try('evidence: setting revoked_at once is accepted',
  $q$update hsf_evidence set revoked_at = now() where id = '00000000-0000-4000-8000-0000000000e1'$q$, true);
select pg_temp.hsf_try('evidence: clearing revoked_at is refused',
  $q$update hsf_evidence set revoked_at = null where id = '00000000-0000-4000-8000-0000000000e1'$q$, false);
select pg_temp.hsf_try('evidence: changing the supplier is refused',
  $q$update hsf_evidence set supplied_by = 'someone else' where id = '00000000-0000-4000-8000-0000000000e1'$q$, false);

-- 9. Release gate -----------------------------------------------------------------------------

select pg_temp.hsf_try('release: refused with no sign offs',
  $q$insert into hsf_release (file_id, revision, pdf_path, evidence_index_path) values ('00000000-0000-4000-8000-0000000000f1', 1, 'x.pdf', 'x.csv')$q$, false);
-- Contract 10.8 (migration 053): the OMP is not a File signatory, and the
-- safety content sign off carries a registered practitioner's credentials that
-- fit the File (a construction File here). hsf_signoff_checks.sql proves each
-- refusal of the sign off rule; this file keeps to the release gate's order.
select pg_temp.hsf_try('release: a new omp_medical sign off is refused (contract 10.8)',
  $q$insert into hsf_signoff (file_id, revision, kind, decision, signatory_name, registration_number, decided_at) values ('00000000-0000-4000-8000-0000000000f1', 1, 'omp_medical', 'approved', 'Test OMP', 'TEST-0001', now())$q$, false);
insert into hsf_signatory (id, full_name, registration_body, category, registration_number, registration_expires_on,
                           register_checked_on, register_proof_ref, appointment_letter_ref, appointment_letter_date,
                           engagement_letter_ref, engagement_letter_date)
values ('00000000-0000-4000-8000-0000000000d1', 'Test safety signatory', 'SACPCMP', 'CHSM', 'TEST-0002', current_date + 365,
        current_date - 1, 'fixture/register-check.pdf', 'fixture/appointment.pdf', current_date - 30,
        'fixture/engagement.pdf', current_date - 30);
insert into hsf_signoff (file_id, revision, kind, decision, signatory_id, scope, decided_at) values
  ('00000000-0000-4000-8000-0000000000f1', 1, 'safety_content', 'approved', '00000000-0000-4000-8000-0000000000d1', 'Sections A to O, revision 1', now());
select pg_temp.hsf_try('release: refused without the client section 16(2) acceptance',
  $q$insert into hsf_release (file_id, revision, pdf_path, evidence_index_path) values ('00000000-0000-4000-8000-0000000000f1', 1, 'x.pdf', 'x.csv')$q$, false);
insert into hsf_signoff (file_id, revision, kind, decision, signatory_name, decided_at) values
  ('00000000-0000-4000-8000-0000000000f1', 1, 'client_16_2_acceptance', 'approved', 'Test appointee', now());
-- Contract 9.3: HSF-A-01 names the OHS Act, verified but seeded with scope medical
-- and provision 'awaiting verification', so it is not yet citable for a File.
select pg_temp.hsf_try('release: refused while the element''s provision is awaiting verification (contract 9.3)',
  $q$insert into hsf_release (file_id, revision, pdf_path, evidence_index_path) values ('00000000-0000-4000-8000-0000000000f1', 1, 'x.pdf', 'x.csv')$q$, false);
update hsf_element_instrument set provision = 'Check provision (rolled back)'
 where element_id = (select id from hsf_element where code = 'HSF-A-01')
   and instrument_id in (select id from msp_legal_instrument where short_name = 'OHS Act');
select pg_temp.hsf_try('release: refused while the instrument''s scope is medical only (contract 9.3)',
  $q$insert into hsf_release (file_id, revision, pdf_path, evidence_index_path) values ('00000000-0000-4000-8000-0000000000f1', 1, 'x.pdf', 'x.csv')$q$, false);
update msp_legal_instrument set scope = 'both' where short_name = 'OHS Act' and status = 'verified';
select pg_temp.hsf_try('release: accepted with the safety content and client approvals and every instrument citable for a File',
  $q$insert into hsf_release (file_id, revision, pdf_path, evidence_index_path) values ('00000000-0000-4000-8000-0000000000f1', 1, 'x.pdf', 'x.csv')$q$, true);
insert into hsf_file_item (file_id, element_id)
select '00000000-0000-4000-8000-0000000000f1', id from hsf_element where code = 'HSF-F-08';
insert into hsf_signoff (file_id, revision, kind, decision, signatory_id, scope, signatory_name, registration_number, decided_at) values
  ('00000000-0000-4000-8000-0000000000f1', 2, 'safety_content', 'approved', '00000000-0000-4000-8000-0000000000d1', 'Sections A to O, revision 2', null, null, now()),
  ('00000000-0000-4000-8000-0000000000f1', 2, 'client_16_2_acceptance', 'approved', null, null, 'Test appointee', null, now());
select pg_temp.hsf_try('release: refused when an item cites a pending candidate instrument',
  $q$insert into hsf_release (file_id, revision, pdf_path, evidence_index_path) values ('00000000-0000-4000-8000-0000000000f1', 2, 'x.pdf', 'x.csv')$q$, false);

-- 10. Row Level Security as the web tier would see it --------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}', true);
select (select count(*) from hsf_file) as a_files, (select count(*) from hsf_file_item) as a_items,
       (select count(*) from hsf_evidence) as a_evidence, (select count(*) from hsf_element) as a_library \gset
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}', true);
select (select count(*) from hsf_file) as b_files, (select count(*) from hsf_evidence) as b_evidence \gset
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated", "app_metadata": {"msp_roles": ["forge_safety_reviewer"]}}', true);
select (select count(*) from hsf_file) as s_files \gset
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated", "app_metadata": {"msp_roles": ["forge_agent"]}}', true);
select (select count(*) from hsf_file) as g_files \gset
reset role;
select set_config('request.jwt.claims', '', true);

insert into hsf_check (name, expected, actual, pass) values
  ('RLS: client A reads its own two Files', '2', :'a_files', :'a_files' = '2'),
  ('RLS: client A reads the items of its Files', '2', :'a_items', :'a_items' = '2'),
  ('RLS: client A reads the evidence of its Files', '1', :'a_evidence', :'a_evidence' = '1'),
  ('RLS: an authenticated client reads the element library', '256', :'a_library', :'a_library' = '256'),
  ('RLS: client B reads none of client A''s Files', '0', :'b_files', :'b_files' = '0'),
  ('RLS: client B reads none of client A''s evidence', '0', :'b_evidence', :'b_evidence' = '0'),
  ('RLS: forge_safety_reviewer reads every File', '2', :'s_files', :'s_files' = '2'),
  ('RLS: forge_agent (not a File reader) reads no Files', '0', :'g_files', :'g_files' = '0');

-- Result --------------------------------------------------------------------------------------

select n, case when pass then 'PASS' else 'FAIL' end as result, name, expected, actual from hsf_check order by n;

do $$
declare
  v_fail int;
  v_total int;
begin
  select count(*) filter (where not pass), count(*) into v_fail, v_total from hsf_check;
  if v_fail > 0 then
    raise exception 'hsf_core_checks: % of % checks failed', v_fail, v_total;
  end if;
  raise notice 'hsf_core_checks: all % checks passed', v_total;
end;
$$;

rollback;
