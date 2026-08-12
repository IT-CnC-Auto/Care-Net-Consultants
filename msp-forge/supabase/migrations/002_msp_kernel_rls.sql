-- CNC MSP FORGE | KRN-RLS-01 v1.0.0 | Row Level Security for the Cognitive Kernel
-- Phase 1 migration 002. RLS on every table, deny by default. Roles are carried
-- as an msp_roles array in the JWT app_metadata claim. The service role key
-- (server side only) bypasses RLS for the build and runtime service paths.
-- Anonymous access is denied everywhere: no policy exists for anon.

create or replace function msp_has_role(required text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' -> 'msp_roles') ? required,
    false
  );
$$;
comment on function msp_has_role is 'True when the requesting JWT carries the named role in app_metadata.msp_roles. Roles: forge_agent, forge_verifier, forge_omp, forge_admin.';

create or replace function msp_any_forge_role()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select public.msp_has_role('forge_agent')
      or public.msp_has_role('forge_verifier')
      or public.msp_has_role('forge_omp')
      or public.msp_has_role('forge_admin');
$$;

-- Enable RLS on every kernel table
alter table msp_industry            enable row level security;
alter table msp_subindustry         enable row level security;
alter table msp_job_role            enable row level security;
alter table msp_hazard              enable row level security;
alter table msp_job_hazard          enable row level security;
alter table msp_legal_instrument    enable row level security;
alter table msp_test_protocol       enable row level security;
alter table msp_industry_instrument enable row level security;
alter table msp_kernel_rule         enable row level security;
alter table msp_kernel_exclusion    enable row level security;
alter table msp_confirmation_item   enable row level security;

-- Kernel content: readable by every forge role, writable by the verifier only.
-- There is no DELETE policy on any kernel table: kernel rows are excluded or
-- superseded through status, never deleted, so the citation trail survives.

create policy msp_industry_read on msp_industry
  for select to authenticated using (msp_any_forge_role());
create policy msp_industry_write on msp_industry
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_industry_update on msp_industry
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_subindustry_read on msp_subindustry
  for select to authenticated using (msp_any_forge_role());
create policy msp_subindustry_write on msp_subindustry
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_subindustry_update on msp_subindustry
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_job_role_read on msp_job_role
  for select to authenticated using (msp_any_forge_role());
create policy msp_job_role_write on msp_job_role
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_job_role_update on msp_job_role
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_hazard_read on msp_hazard
  for select to authenticated using (msp_any_forge_role());
create policy msp_hazard_write on msp_hazard
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_hazard_update on msp_hazard
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_job_hazard_read on msp_job_hazard
  for select to authenticated using (msp_any_forge_role());
create policy msp_job_hazard_write on msp_job_hazard
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_job_hazard_update on msp_job_hazard
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_legal_instrument_read on msp_legal_instrument
  for select to authenticated using (msp_any_forge_role());
create policy msp_legal_instrument_write on msp_legal_instrument
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_legal_instrument_update on msp_legal_instrument
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_test_protocol_read on msp_test_protocol
  for select to authenticated using (msp_any_forge_role());
create policy msp_test_protocol_write on msp_test_protocol
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_test_protocol_update on msp_test_protocol
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_industry_instrument_read on msp_industry_instrument
  for select to authenticated using (msp_any_forge_role());
create policy msp_industry_instrument_write on msp_industry_instrument
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_industry_instrument_update on msp_industry_instrument
  for update to authenticated using (msp_has_role('forge_verifier'));

create policy msp_kernel_rule_read on msp_kernel_rule
  for select to authenticated using (msp_any_forge_role());
create policy msp_kernel_rule_write on msp_kernel_rule
  for insert to authenticated with check (msp_has_role('forge_verifier'));
create policy msp_kernel_rule_update on msp_kernel_rule
  for update to authenticated using (msp_has_role('forge_verifier'));

-- The exclusion register is append only for the verifier: no update policy.
create policy msp_kernel_exclusion_read on msp_kernel_exclusion
  for select to authenticated using (msp_any_forge_role());
create policy msp_kernel_exclusion_write on msp_kernel_exclusion
  for insert to authenticated with check (msp_has_role('forge_verifier'));

-- The confirmation register: read by every forge role, maintained by admin and verifier.
create policy msp_confirmation_item_read on msp_confirmation_item
  for select to authenticated using (msp_any_forge_role());
create policy msp_confirmation_item_write on msp_confirmation_item
  for insert to authenticated
  with check (msp_has_role('forge_admin') or msp_has_role('forge_verifier'));
create policy msp_confirmation_item_update on msp_confirmation_item
  for update to authenticated
  using (msp_has_role('forge_admin') or msp_has_role('forge_verifier'));
