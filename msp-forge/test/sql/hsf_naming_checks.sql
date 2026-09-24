-- CNC MSP FORGE | HSF-NAME-01 naming checks | local test harness only.
-- Proves migration 056 (build contract section 15, Amendment 7) against a
-- replayed database: element HSF-E-01 reads as the signed Medical Surveillance
-- Plan, a separate Care Net product signed by the OMP, filed as evidence; no
-- visible library or guidance text carries "MSP FORGE", "HSF FORGE", another
-- internal platform name or a doubled comma; no guidance gives the OMP a sign
-- off of the File or says the Plan is built from the File's own risk
-- assessment (separation review F1 and F2); the guidance the database serves
-- (055 plus the updates after it) is exactly hsf/guidance/guidance.json; every
-- element name matches hsf/guidance/worklist.json; and running 056 a second
-- time changes no row. Never applied to Supabase. Everything runs in one
-- transaction that is rolled back.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/hsf_naming_checks.sql
--
-- Every check prints "ok" as a notice; the first failure raises an exception that
-- stops the script with a non zero exit.

\set ON_ERROR_STOP 1
\pset pager off
-- The committed sources, read from msp-forge/ (or found through git from anywhere in the repository).
\set guidance_json `cat hsf/guidance/guidance.json 2>/dev/null || cat "$(git rev-parse --show-toplevel 2>/dev/null)/msp-forge/hsf/guidance/guidance.json" 2>/dev/null || echo null`
\set worklist_json `cat hsf/guidance/worklist.json 2>/dev/null || cat "$(git rev-parse --show-toplevel 2>/dev/null)/msp-forge/hsf/guidance/worklist.json" 2>/dev/null || echo null`
begin;

-- 0. Harness ------------------------------------------------------------------------------

create function pg_temp.ok(p_name text, p_cond boolean) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'CHECK FAILED: %', p_name;
  end if;
  raise notice 'ok   %', p_name;
end $$;

-- True when a visible text names an internal system or carries a doubled comma.
create function pg_temp.internal(p text) returns boolean language sql immutable as $$
  select coalesce(p ~ '(MSP|HSF) FORGE|\mFORGE\M|\mCursor\M|,[[:space:]]*,' or p ~* 'sharepoint', false)
$$;

-- True when a text gives the OMP a sign off of the File or of a section. The OMP
-- signs the separate Medical Surveillance Plan only (hsf/SIGNOFF-CRITERIA.md 2.4).
create function pg_temp.omp_signoff(p text) returns boolean language sql immutable as $$
  select coalesce(p ~* 'signed off by (the |its |your )?(OMP|occupational medical practitioner)\M|\m(OMP|occupational medical practitioner)( only)? signs? off\M', false)
$$;

create temp table expected (what text primary key, doc jsonb);
insert into expected values ('guidance', :'guidance_json'::jsonb), ('worklist', :'worklist_json'::jsonb);
select pg_temp.ok('the committed guidance.json and worklist.json were read (run from msp-forge/)',
  (select bool_and(jsonb_typeof(doc) = 'object') from expected));

select pg_temp.ok('the pattern catches what it must and lets plain text through',
  pg_temp.internal('from MSP FORGE') and pg_temp.internal('the HSF FORGE builder') and pg_temp.internal('its OMP,, covering')
  and pg_temp.internal('filed in SharePoint') and pg_temp.internal('a , , b')
  and not pg_temp.internal('signed by its OMP, covering welders') and not pg_temp.internal('forged certificates'));

-- 1. HSF-E-01: the signed Medical Surveillance Plan, filed as evidence -----------------------

select pg_temp.ok('HSF-E-01 carries its new name',
  (select name from hsf_element where code = 'HSF-E-01')
    = 'The signed Medical Surveillance Plan, a separate Care Net product signed by the OMP, filed as evidence');
select pg_temp.ok('HSF-E-01 carries its new description (duty)',
  (select duty from hsf_element where code = 'HSF-E-01')
    = 'The Medical Surveillance Plan is a separate Care Net product, signed by the Occupational Medical Practitioner (OMP). The signed Plan is filed in Section E as evidence; clinical records stay with the occupational health practitioner.');
select pg_temp.ok('HSF-E-01 stays a Section E document the OMP holds, reviewed yearly, for every File',
  (select section_code = 'E' and evidence_type = 'document' and responsible_role = 'OMP' and review_interval = 'annual'
          and universal and status = 'active' from hsf_element where code = 'HSF-E-01'));
select pg_temp.ok('HSF-E-01 guidance example: one comma after "signed by its OMP"',
  (select example from hsf_element_guidance where element_code = 'HSF-E-01')
    = 'Example: Ndlovu Engineering in Middelburg files its Medical Surveillance Plan, a separate Care Net product signed by its OMP, covering welders for noise and fumes and stores staff for manual handling only.');

set local role anon;
select pg_temp.ok('a visitor (anon) reads the new name and description in the public element library',
  (select name like 'The signed Medical Surveillance Plan, a separate Care Net product%' and duty like '%separate Care Net product%'
          and not pg_temp.internal(name) and not pg_temp.internal(duty)
     from hsf_public_element_library where code = 'HSF-E-01'));
select pg_temp.ok('a visitor (anon) reads the corrected example in the public guidance',
  (select guidance #>> '{elements,HSF-E-01,example}' from hsf_public_guidance) like '%signed by its OMP, covering welders%');
reset role;

-- 2. No visible library or guidance text names an internal system -------------------------

select pg_temp.ok('no element name or description names an internal system or has a doubled comma',
  not exists (select 1 from hsf_element where pg_temp.internal(name) or pg_temp.internal(duty)));
select pg_temp.ok('no section, department, trigger, appointment type or class text does either',
  not exists (select 1 from hsf_section where pg_temp.internal(name) or pg_temp.internal(description))
  and not exists (select 1 from hsf_department where pg_temp.internal(name))
  and not exists (select 1 from hsf_trigger where pg_temp.internal(description))
  and not exists (select 1 from hsf_appointment_type where pg_temp.internal(name) or pg_temp.internal(competence_requirement))
  and not exists (select 1 from hsf_element_class where pg_temp.internal(name)));
select pg_temp.ok('no guidance row does either, in any table',
  not exists (select 1 from hsf_element_guidance where pg_temp.internal(concat_ws(' ', what_to_submit::text, why, example, common_gaps::text)))
  and not exists (select 1 from hsf_appointment_guidance where pg_temp.internal(concat_ws(' ', what_to_submit::text, why, example, common_gaps::text)))
  and not exists (select 1 from hsf_class_guidance where pg_temp.internal(concat_ws(' ', what_to_submit::text, why, example, common_gaps::text)))
  and not exists (select 1 from hsf_section_guidance where pg_temp.internal(concat_ws(' ', intro, what_goes_here::text, first_file_tips::text)))
  and not exists (select 1 from hsf_guidance_meta where pg_temp.internal(concat_ws(' ', note, first_file_intro, first_file_order::text, before_you_start::text))));
select pg_temp.ok('the OMP sign off pattern catches what it must and lets the Plan signature through',
  pg_temp.omp_signoff('and this section is signed off by the OMP only.') and pg_temp.omp_signoff('the OMP signs off the File')
  and not pg_temp.omp_signoff('The occupational medical practitioner (OMP) signs that Plan; the OMP does not sign your File.')
  and not pg_temp.omp_signoff('a separate Care Net product signed by the OMP'));
select pg_temp.ok('no guidance gives the OMP a sign off of the File or of a section (the OMP signs only the separate Plan)',
  not pg_temp.omp_signoff((select guidance::text from hsf_public_guidance))
  and not exists (select 1 from hsf_section_guidance where pg_temp.omp_signoff(concat_ws(' ', intro, what_goes_here::text, first_file_tips::text)))
  and not exists (select 1 from hsf_element where pg_temp.omp_signoff(concat_ws(' ', name, duty))));
select pg_temp.ok('the Section E intro says the OMP signs the Plan, filed as evidence, and not the File',
  (select intro from hsf_section_guidance where section_code = 'E')
    like '%Medical Surveillance Plan, a separate Care Net product filed here as evidence. The occupational medical practitioner (OMP) signs that Plan; the OMP does not sign your File.%');
select pg_temp.ok('no guidance says the Plan follows from, or is built from, the File''s own risk assessment',
  (select guidance::text from hsf_public_guidance) !~* 'follows from the exposures|built from the exposures|Only certificates of fitness \(the outcome\) go in the File|based on the exposures your risk assessment found');

select pg_temp.ok('the public guidance document and element library are clean as a visitor reads them',
  not pg_temp.internal((select guidance::text from hsf_public_guidance))
  and not exists (select 1 from hsf_public_element_library where pg_temp.internal(name) or pg_temp.internal(duty) or pg_temp.internal(section_name)));

-- 3. The database serves exactly the committed sources ------------------------------------

select pg_temp.ok('hsf_public_guidance equals hsf/guidance/guidance.json (055 plus every later update)',
  (select guidance from hsf_public_guidance) = (select doc from expected where what = 'guidance'));
select pg_temp.ok('every element name in the library equals its name in hsf/guidance/worklist.json',
  (select count(*) from hsf_element) = (select jsonb_array_length(doc -> 'elements') from expected where what = 'worklist')
  and not exists (
    select 1 from expected x, jsonb_array_elements(x.doc -> 'elements') w
      left join hsf_element e on e.code = w ->> 'code'
     where x.what = 'worklist' and e.name is distinct from w ->> 'name'));

-- 4. 056 is idempotent: a second run changes no row ---------------------------------------

create temp table before_rerun as
  select 'element' as k, xmin::text as x from hsf_element where code = 'HSF-E-01'
  union all select 'guidance', xmin::text from hsf_element_guidance where element_code = 'HSF-E-01';
\ir ../../supabase/migrations/056_hsf_file_naming.sql
select pg_temp.ok('running 056 again rewrites neither the element nor its guidance row',
  (select count(*) = 2 from before_rerun b
     join (select 'element' as k, xmin::text as x from hsf_element where code = 'HSF-E-01'
           union all select 'guidance', xmin::text from hsf_element_guidance where element_code = 'HSF-E-01') a
       on a.k = b.k and a.x = b.x));

rollback;
\echo 'hsf_naming_checks: all checks passed'
