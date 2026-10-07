-- CNC HSF FORGE | HSF-ADS-02, Bee-Inspect attribution checks | local test harness only.
-- Proves migration 058 (hsf/BUILD-CONTRACT.md 16, Bee-Inspect P2) against a
-- replayed database: hsf_attribution_event holds only the event, the page, the
-- five campaign tags and the time (no person, company, address or cookie);
-- nobody but the service role reads or writes it; hsf_attribution_record refuses
-- anything it does not know (an email address never fits a tag) and drops a
-- flood; the table is append only; the summary counts; 057 is untouched; and
-- running 058 again changes nothing. Never applied to Supabase. Everything runs
-- in one transaction that is rolled back.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_attribution_checks.sql

\set ON_ERROR_STOP 1
\pset pager off
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

-- 1. Shape and access -----------------------------------------------------------------

select pg_temp.ok('hsf_attribution_event holds only the event, page, five campaign tags and time',
  (select array_agg(column_name::text order by ordinal_position) from information_schema.columns
    where table_schema = 'public' and table_name = 'hsf_attribution_event')
  = array['id','occurred_at','event','page','utm_source','utm_medium','utm_campaign','utm_content','utm_term']);
select pg_temp.ok('hsf_ad_event (057) keeps its eight columns',
  (select array_agg(column_name::text order by ordinal_position) from information_schema.columns
    where table_schema = 'public' and table_name = 'hsf_ad_event')
  = array['id','occurred_at','event','ad_id','variant','page','industry','f_band']);
select pg_temp.ok('row level security is on, with no policy',
  (select relrowsecurity from pg_class where oid = 'public.hsf_attribution_event'::regclass)
  and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'hsf_attribution_event'));
select pg_temp.ok('anon and authenticated can neither read nor write hsf_attribution_event',
  not has_table_privilege('anon', 'public.hsf_attribution_event', 'select')
  and not has_table_privilege('anon', 'public.hsf_attribution_event', 'insert')
  and not has_table_privilege('authenticated', 'public.hsf_attribution_event', 'select')
  and not has_table_privilege('authenticated', 'public.hsf_attribution_event', 'insert'));
select pg_temp.ok('only the service role may execute hsf_attribution_record and hsf_attribution_summary',
  has_function_privilege('service_role', 'hsf_attribution_record(jsonb)', 'execute')
  and has_function_privilege('service_role', 'hsf_attribution_summary(int)', 'execute')
  and not has_function_privilege('anon', 'hsf_attribution_record(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'hsf_attribution_record(jsonb)', 'execute')
  and not has_function_privilege('anon', 'hsf_attribution_summary(int)', 'execute')
  and not has_function_privilege('authenticated', 'hsf_attribution_summary(int)', 'execute'));
select pg_temp.ok('both functions are security definer with a fixed search_path',
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=public'])
     from pg_proc p where p.oid in ('hsf_attribution_record(jsonb)'::regprocedure, 'hsf_attribution_summary(int)'::regprocedure)));

-- 2. Recording --------------------------------------------------------------------------

select pg_temp.ok('a first sign in from a banner link is recorded',
  (hsf_attribution_record('{"event":"attribution_seen","page":"/hsf-builder","utm_source":"hsf_builder","utm_medium":"in_product_banner","utm_campaign":"bee_inspect_addon","utm_content":"AD-01_gaps"}') ->> 'accepted')::boolean);
select pg_temp.ok('and stored exactly as sent',
  exists (select 1 from hsf_attribution_event where page = '/hsf-builder' and utm_source = 'hsf_builder' and utm_medium = 'in_product_banner'
            and utm_campaign = 'bee_inspect_addon' and utm_content = 'AD-01_gaps' and utm_term is null and event = 'attribution_seen'));
select pg_temp.ok('one tag alone is enough; empty tags are stored as null',
  (hsf_attribution_record('{"event":"attribution_seen","page":"/hsf-builder","utm_campaign":"spring.2026","utm_source":"","utm_term":null}') ->> 'accepted')::boolean);
select pg_temp.ok('and stored with nulls',
  exists (select 1 from hsf_attribution_event where utm_campaign = 'spring.2026' and utm_source is null and utm_term is null));

-- 3. Refusals ---------------------------------------------------------------------------

select pg_temp.refuses('an unknown key (an email) is refused',
  $q$select hsf_attribution_record('{"event":"attribution_seen","page":"/hsf-builder","utm_source":"x","email":"a@b.co.za"}')$q$, 'unknown key');
select pg_temp.refuses('an email address in a tag is refused',
  $q$select hsf_attribution_record('{"event":"attribution_seen","page":"/hsf-builder","utm_term":"someone@example.co.za"}')$q$, 'bad utm_term');
select pg_temp.refuses('a tag with spaces or markup is refused',
  $q$select hsf_attribution_record('{"event":"attribution_seen","page":"/hsf-builder","utm_source":"<b>x</b>"}')$q$, 'bad utm_source');
select pg_temp.refuses('a tag longer than 64 characters is refused',
  $q$select hsf_attribution_record(jsonb_build_object('event','attribution_seen','page','/hsf-builder','utm_content', repeat('a', 65)))$q$, 'bad utm_content');
select pg_temp.refuses('no tag at all is refused',
  $q$select hsf_attribution_record('{"event":"attribution_seen","page":"/hsf-builder","utm_source":""}')$q$, 'no campaign tag');
select pg_temp.refuses('a banner event is not an attribution',
  $q$select hsf_attribution_record('{"event":"ad_click","page":"/hsf-builder","utm_source":"x"}')$q$, 'unknown event');
select pg_temp.refuses('a Plan page is refused',
  $q$select hsf_attribution_record('{"event":"attribution_seen","page":"/shop","utm_source":"x"}')$q$, 'unknown page');
select pg_temp.refuses('a value that is not text is refused',
  $q$select hsf_attribution_record('{"event":"attribution_seen","page":"/hsf-builder","utm_source":1}')$q$, 'must be text');
select pg_temp.refuses('null is refused', $q$select hsf_attribution_record(null)$q$, 'an object is required');
select pg_temp.refuses('a direct insert without a tag is refused by the table itself',
  $q$insert into hsf_attribution_event (page) values ('/hsf-builder')$q$, 'check constraint');

-- 4. Append only ------------------------------------------------------------------------

select pg_temp.refuses('an attribution is never changed',
  $q$update hsf_attribution_event set utm_source = 'y'$q$, 'append only');
select pg_temp.refuses('an attribution is never deleted',
  $q$delete from hsf_attribution_event$q$, 'append only');

-- 5. Summary ----------------------------------------------------------------------------

select pg_temp.ok('the summary counts per source, medium, campaign and content',
  exists (select 1 from jsonb_array_elements(hsf_attribution_summary(30)) e
           where e ->> 'utm_content' = 'AD-01_gaps' and (e ->> 'count')::int >= 1));
select pg_temp.ok('the summary window is bounded',
  jsonb_typeof(hsf_attribution_summary(0)) = 'array' and jsonb_typeof(hsf_attribution_summary(null)) = 'array');

-- 6. A flood is dropped -----------------------------------------------------------------

insert into hsf_attribution_event (page, utm_source) select '/hsf-builder', 'flood' from generate_series(1, 600);
create temp table flood_count as select count(*) as n from hsf_attribution_event;
select pg_temp.ok('after 600 in a minute the next is dropped',
  (hsf_attribution_record('{"event":"attribution_seen","page":"/hsf-builder","utm_source":"x"}') ->> 'accepted')::boolean = false);
select pg_temp.ok('and not stored', (select count(*) from hsf_attribution_event) = (select n from flood_count));

-- 7. Running 058 again ------------------------------------------------------------------

create temp table before_rerun as
  select 'rows' as k, count(*)::text as x from hsf_attribution_event
  union all select 'fn ' || p.oid::regprocedure::text, md5(concat_ws('|', p.prosrc, p.proconfig::text, p.proacl::text, p.prosecdef::text))
    from pg_proc p where p.oid in ('hsf_attribution_record(jsonb)'::regprocedure, 'hsf_attribution_summary(int)'::regprocedure);
\ir ../../supabase/migrations/058_hsf_bee_inspect_attribution.sql
select pg_temp.ok('running 058 again keeps every row, function and grant and the single guard trigger',
  (select count(*) = 3 from before_rerun b
     join (select 'rows' as k, count(*)::text as x from hsf_attribution_event
           union all select 'fn ' || p.oid::regprocedure::text, md5(concat_ws('|', p.prosrc, p.proconfig::text, p.proacl::text, p.prosecdef::text))
             from pg_proc p where p.oid in ('hsf_attribution_record(jsonb)'::regprocedure, 'hsf_attribution_summary(int)'::regprocedure)) a
       on a.k = b.k and a.x is not distinct from b.x)
  and (select count(*) from pg_trigger where tgrelid = 'public.hsf_attribution_event'::regclass and not tgisinternal) = 1);

rollback;
\echo 'hsf_attribution_checks: all checks passed'
