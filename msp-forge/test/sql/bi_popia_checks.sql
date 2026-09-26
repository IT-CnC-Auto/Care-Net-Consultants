-- CNC HSF FORGE | BI-OPS-01, Bee-Inspect POPIA and naming checks | local test harness only.
-- Bee-Inspect holds health and safety inspection and risk assessment data only;
-- clinical medical results stay in MyClinicOnline (hsf/BEE-INSPECT-BUILD-PROMPT.md
-- section 3.4). Proves that no bi_ column reads like a clinical medical item (and
-- that the check would catch one), that every bi_ object is documented, that the
-- Bee-Inspect objects of 059 to 063 are all bi_ prefixed and apart from the msp_
-- and hsf_ objects, and that the storage buckets are private. Rolled back.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/bi_popia_checks.sql

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

select pg_temp.ok('no bi_ column reads like a clinical medical result (bi_clinical_column_check is empty)',
  not exists (select 1 from bi_clinical_column_check()));
select pg_temp.ok('the check does not mistake submitted_at for bmi or duration_seconds for anything clinical',
  exists (select 1 from information_schema.columns where table_name = 'bi_inspection' and column_name = 'submitted_at'));

create table public.bi_zz_probe (id int, blood_pressure text, hearing_threshold_db int, fitness_outcome text, note text);
select pg_temp.ok('the check catches clinical columns in a new bi_ table (probe: blood_pressure, hearing_threshold_db, fitness_outcome)',
  (select array_agg(column_name order by column_name) from bi_clinical_column_check() where table_name = 'bi_zz_probe')
    = array['blood_pressure','fitness_outcome','hearing_threshold_db']);
drop table public.bi_zz_probe;

select pg_temp.ok('every bi_ table and view carries a comment',
  not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'public' and c.relkind in ('r','v') and c.relname like 'bi\_%' and obj_description(c.oid, 'pg_class') is null));
select pg_temp.ok('Bee-Inspect created 47 bi_ tables and one view',
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'bi\_%') = 47
  and (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'v' and c.relname like 'bi\_%') = 1);
select pg_temp.ok('the Bee-Inspect parameters are bi. prefixed and hold no secret value',
  (select count(*) from msp_env_parameter where key like 'bi.%') = 3
  and not exists (select 1 from msp_env_parameter where key like 'bi.%' and key ~* '(secret|password|api_key|token)'));
select pg_temp.ok('the bi-evidence and bi-reports buckets are private, and no storage policy opens them',
  (select bool_and(not public) from storage.buckets where id in ('bi-evidence','bi-reports'))
  and (select count(*) from storage.buckets where id in ('bi-evidence','bi-reports')) = 2
  and not exists (select 1 from pg_policies where schemaname = 'storage' and (qual ilike '%bi-%' or with_check ilike '%bi-%')));
select pg_temp.ok('the feature flags start off: bee_inspect_ads and welcome_hook',
  (select bool_and(not enabled) from bi_feature_flag where key in ('bee_inspect_ads','welcome_hook') and tenant_id is null)
  and (select count(*) from bi_feature_flag where tenant_id is null) = 2);
select pg_temp.ok('Bee-Inspect never writes a person into the File''s banner tables (057 and 058 keep their columns)',
  (select array_agg(column_name::text order by ordinal_position) from information_schema.columns where table_name = 'hsf_ad_event')
    = array['id','occurred_at','event','ad_id','variant','page','industry','f_band']
  and (select count(*) from information_schema.columns where table_name = 'hsf_attribution_event') = 9);
select pg_temp.ok('no File table (hsf_) gained a column from the Bee-Inspect migrations',
  not exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name like 'hsf\_%' and c.column_name like 'bi\_%'));

do $$ begin raise notice 'bi_popia_checks: all checks passed. Rolling back the test data.'; end $$;
rollback;
