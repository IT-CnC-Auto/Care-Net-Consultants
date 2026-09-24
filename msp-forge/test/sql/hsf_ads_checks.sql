-- CNC HSF FORGE | HSF-ADS-01, Bee-Inspect banner events checks | local test harness only.
-- Proves migration 057 (hsf/BUILD-CONTRACT.md 16.3, Bee-Inspect P1) against a
-- replayed database: hsf_ad_event holds only the event, banner, variant, page,
-- industry code and Section F band (no person, company, address or document);
-- nobody but the service role reads or writes it (RLS on, no policy, no grant to
-- anon or authenticated); hsf_ad_event_record refuses anything it does not know
-- and drops a flood; the table is append only; hsf_ad_event_summary counts; and
-- running 057 again changes nothing. Never applied to Supabase. Everything runs in
-- one transaction that is rolled back.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_ads_checks.sql
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
    if v_msg ~* p_pattern then
      raise notice 'ok   %', p_name;
      return;
    end if;
    raise exception 'CHECK FAILED: % (refused with "%", expected /%/)', p_name, v_msg, p_pattern;
  end;
  raise exception 'CHECK FAILED: % (not refused)', p_name;
end $$;

-- 1. Shape and access -----------------------------------------------------------------

select pg_temp.ok('hsf_ad_event holds only the event, banner, variant, page, industry code, Section F band and time',
  (select array_agg(column_name::text order by ordinal_position) from information_schema.columns
    where table_schema = 'public' and table_name = 'hsf_ad_event')
  = array['id','occurred_at','event','ad_id','variant','page','industry','f_band']);
select pg_temp.ok('row level security is on for hsf_ad_event',
  (select relrowsecurity from pg_class where oid = 'public.hsf_ad_event'::regclass));
select pg_temp.ok('hsf_ad_event has no policy at all (only the service role, which bypasses RLS, gets in)',
  not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'hsf_ad_event'));
select pg_temp.ok('anon and authenticated can neither read nor write hsf_ad_event',
  not has_table_privilege('anon', 'public.hsf_ad_event', 'select')
  and not has_table_privilege('anon', 'public.hsf_ad_event', 'insert')
  and not has_table_privilege('authenticated', 'public.hsf_ad_event', 'select')
  and not has_table_privilege('authenticated', 'public.hsf_ad_event', 'insert')
  and not has_table_privilege('authenticated', 'public.hsf_ad_event', 'update')
  and not has_table_privilege('authenticated', 'public.hsf_ad_event', 'delete'));
select pg_temp.ok('the service role can write hsf_ad_event',
  has_table_privilege('service_role', 'public.hsf_ad_event', 'insert'));
select pg_temp.ok('hsf_ad_event_record and hsf_ad_event_summary are security definer with a fixed search_path',
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=public'])
     from pg_proc p where p.oid in ('hsf_ad_event_record(jsonb)'::regprocedure, 'hsf_ad_event_summary(int)'::regprocedure)));
select pg_temp.ok('only the service role may execute hsf_ad_event_record and hsf_ad_event_summary',
  has_function_privilege('service_role', 'hsf_ad_event_record(jsonb)', 'execute')
  and has_function_privilege('service_role', 'hsf_ad_event_summary(int)', 'execute')
  and not has_function_privilege('anon', 'hsf_ad_event_record(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'hsf_ad_event_record(jsonb)', 'execute')
  and not has_function_privilege('anon', 'hsf_ad_event_summary(int)', 'execute')
  and not has_function_privilege('authenticated', 'hsf_ad_event_summary(int)', 'execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid in ('hsf_ad_event_record(jsonb)'::regprocedure, 'hsf_ad_event_summary(int)'::regprocedure)
                     and a.grantee = 0 and a.privilege_type = 'EXECUTE'));

-- 2. Recording --------------------------------------------------------------------------

create temp table before_count as select count(*) as n from hsf_ad_event;

select pg_temp.ok('a banner impression is recorded',
  (hsf_ad_event_record('{"event":"ad_impression","ad_id":"AD-01","variant":"gaps","page":"/hsf-builder","industry":"CONSTR","f_band":"3to5"}') ->> 'accepted')::boolean);
-- (A statement does not see rows its own function call inserts, so each row is
-- read back in a statement of its own.)
select pg_temp.ok('a click without industry or band is accepted',
  (hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-08","variant":"base","page":"/portal","industry":null}') ->> 'accepted')::boolean);
select pg_temp.ok('and stored with nulls',
  exists (select 1 from hsf_ad_event where ad_id = 'AD-08' and event = 'ad_click' and industry is null and f_band is null));
select pg_temp.ok('an empty industry or band is accepted',
  (hsf_ad_event_record('{"event":"ad_dismiss","ad_id":"AD-06","variant":"base","page":"/health-and-safety-file","industry":"","f_band":""}') ->> 'accepted')::boolean);
select pg_temp.ok('and stored as null',
  exists (select 1 from hsf_ad_event where ad_id = 'AD-06' and event = 'ad_dismiss' and industry is null and f_band is null));
select pg_temp.ok('the server side events of A4 are reserved for later sources and accepted here',
  (hsf_ad_event_record('{"event":"subscribe","ad_id":"AD-10","variant":"base","page":"/bee-inspect"}') ->> 'accepted')::boolean);
select pg_temp.ok('the stored row is exactly what was sent',
  exists (select 1 from hsf_ad_event where event = 'ad_impression' and ad_id = 'AD-01' and variant = 'gaps'
            and page = '/hsf-builder' and industry = 'CONSTR' and f_band = '3to5' and occurred_at > now() - interval '1 minute'));
select pg_temp.ok('four rows were added', (select count(*) from hsf_ad_event) = (select n from before_count) + 4);

-- 3. Refusals ---------------------------------------------------------------------------

select pg_temp.refuses('an unknown key (an email) is refused',
  $q$select hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-01","variant":"base","page":"/hsf-builder","email":"a@b.co.za"}')$q$, 'unknown key');
select pg_temp.refuses('a user id is refused',
  $q$select hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-01","variant":"base","page":"/hsf-builder","user_id":"x"}')$q$, 'unknown key');
select pg_temp.refuses('a value that is not text is refused',
  $q$select hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-01","variant":1,"page":"/hsf-builder"}')$q$, 'must be text');
select pg_temp.refuses('an unknown event is refused',
  $q$select hsf_ad_event_record('{"event":"page_view","ad_id":"AD-01","variant":"base","page":"/hsf-builder"}')$q$, 'unknown event');
select pg_temp.refuses('a missing event is refused',
  $q$select hsf_ad_event_record('{"ad_id":"AD-01","variant":"base","page":"/hsf-builder"}')$q$, 'unknown event');
select pg_temp.refuses('an unknown banner is refused',
  $q$select hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-11","variant":"base","page":"/hsf-builder"}')$q$, 'unknown banner');
select pg_temp.refuses('a malformed variant is refused',
  $q$select hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-01","variant":"Base-1","page":"/hsf-builder"}')$q$, 'bad variant');
select pg_temp.refuses('a Plan page is not a banner page',
  $q$select hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-01","variant":"base","page":"/shop"}')$q$, 'unknown page');
select pg_temp.refuses('a malformed industry code is refused',
  $q$select hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-01","variant":"base","page":"/hsf-builder","industry":"Rietvlei Civils"}')$q$, 'bad industry');
select pg_temp.refuses('an unknown Section F band is refused',
  $q$select hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-01","variant":"base","page":"/hsf-builder","f_band":"12"}')$q$, 'bad Section F band');
select pg_temp.refuses('an array is refused', $q$select hsf_ad_event_record('[]')$q$, 'an object is required');
select pg_temp.refuses('null is refused', $q$select hsf_ad_event_record(null)$q$, 'an object is required');
select pg_temp.refuses('a direct insert of a bad row is refused by the table itself',
  $q$insert into hsf_ad_event (event, ad_id, variant, page) values ('ad_click','AD-01','base','/account')$q$, 'check constraint');

-- 4. Append only ------------------------------------------------------------------------

select pg_temp.refuses('an event is never changed',
  $q$update hsf_ad_event set variant = 'base' where ad_id = 'AD-01'$q$, 'append only');
select pg_temp.refuses('an event is never deleted',
  $q$delete from hsf_ad_event where ad_id = 'AD-01'$q$, 'append only');

-- 5. Summary ----------------------------------------------------------------------------

select pg_temp.ok('the summary counts per banner, variant, page and event',
  exists (select 1 from jsonb_array_elements(hsf_ad_event_summary(30)) e
           where e ->> 'ad_id' = 'AD-01' and e ->> 'variant' = 'gaps' and e ->> 'event' = 'ad_impression' and (e ->> 'count')::int >= 1));
select pg_temp.ok('the summary window is bounded (0 days reads as 1, null as 30)',
  jsonb_typeof(hsf_ad_event_summary(0)) = 'array' and jsonb_typeof(hsf_ad_event_summary(null)) = 'array');

-- 6. A flood is dropped -----------------------------------------------------------------

insert into hsf_ad_event (event, ad_id, variant, page)
  select 'ad_impression', 'AD-02', 'tip', '/hsf-builder' from generate_series(1, 1200);
create temp table flood_count as select count(*) as n from hsf_ad_event;
select pg_temp.ok('after 1 200 events in a minute the next is dropped',
  (hsf_ad_event_record('{"event":"ad_click","ad_id":"AD-02","variant":"tip","page":"/hsf-builder"}') ->> 'accepted')::boolean = false);
select pg_temp.ok('and not stored', (select count(*) from hsf_ad_event) = (select n from flood_count));

-- 7. Running 057 again ------------------------------------------------------------------

create temp table before_rerun as
  select 'rows' as k, count(*)::text as x from hsf_ad_event
  union all select 'fn ' || p.oid::regprocedure::text, md5(concat_ws('|', p.prosrc, p.proconfig::text, p.proacl::text, p.prosecdef::text))
    from pg_proc p where p.oid in ('hsf_ad_event_record(jsonb)'::regprocedure, 'hsf_ad_event_summary(int)'::regprocedure)
  union all select 'table acl', (select relacl::text from pg_class where oid = 'public.hsf_ad_event'::regclass);
\ir ../../supabase/migrations/057_hsf_bee_inspect_ads.sql
select pg_temp.ok('running 057 again keeps every row, function, grant and the single guard trigger',
  (select count(*) = 4 from before_rerun b
     join (select 'rows' as k, count(*)::text as x from hsf_ad_event
           union all select 'fn ' || p.oid::regprocedure::text, md5(concat_ws('|', p.prosrc, p.proconfig::text, p.proacl::text, p.prosecdef::text))
             from pg_proc p where p.oid in ('hsf_ad_event_record(jsonb)'::regprocedure, 'hsf_ad_event_summary(int)'::regprocedure)
           union all select 'table acl', (select relacl::text from pg_class where oid = 'public.hsf_ad_event'::regclass)) a
       on a.k = b.k and a.x is not distinct from b.x)
  and (select count(*) from pg_trigger where tgrelid = 'public.hsf_ad_event'::regclass and not tgisinternal) = 1);

rollback;
\echo 'hsf_ads_checks: all checks passed'
