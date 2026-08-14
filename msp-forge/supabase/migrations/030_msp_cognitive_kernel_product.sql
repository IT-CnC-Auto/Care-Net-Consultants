-- CNC MSP FORGE | KRN-PROD-01 v1.0.0 | Cognitive Kernel productisation 14/08/2026
-- Version control, monthly agent harness, OMP industry review queue, client auth linkage,
-- and the 100 medicals per year free qualification rule. A Care Net Consultants product.

-- 1. Kernel version control ----------------------------------------------------

create table msp_kernel_version (
  id uuid primary key default gen_random_uuid(),
  semver text not null unique,
  released_on date not null default current_date,
  change_summary text not null,
  kernel_counts jsonb not null,
  omp_ratified boolean not null default false,
  ratified_by text,
  ratified_on date,
  created_by text not null
);
comment on table msp_kernel_version is 'Cognitive Kernel release register. Every content release gets a semver row; OMP ratification is recorded per release and the release is not citable as ratified until it is.';

alter table msp_kernel_version enable row level security;
create policy msp_kernel_version_read on msp_kernel_version
  for select to authenticated using (true);

create or replace function msp_kernel_counts()
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'instruments_verified', (select count(*) from msp_legal_instrument where status = 'verified'),
    'instruments_pending',  (select count(*) from msp_legal_instrument where status = 'pending'),
    'instruments_excluded', (select count(*) from msp_legal_instrument where status = 'excluded'),
    'industries',           (select count(*) from msp_industry),
    'subindustries',        (select count(*) from msp_subindustry),
    'selectable',           (select count(*) from msp_subindustry where selectable),
    'roles',                (select count(*) from msp_job_role),
    'hazard_links',         (select count(*) from msp_job_hazard),
    'protocols',            (select count(*) from msp_test_protocol),
    'register_open',        (select count(*) from msp_confirmation_item where status = 'open'),
    'register_resolved',    (select count(*) from msp_confirmation_item where status = 'resolved'));
$$;

create or replace function msp_kernel_release(p_semver text, p_summary text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'kernel release requires the forge_admin role';
  end if;
  insert into msp_kernel_version (semver, change_summary, kernel_counts, created_by)
  values (p_semver, p_summary, msp_kernel_counts(), 'msp_kernel_release');
  insert into msp_audit (actor, event_type, event_detail)
  values ('msp_kernel_release', 'kernel_release',
          jsonb_build_object('semver', p_semver, 'summary', p_summary));
  return jsonb_build_object('semver', p_semver, 'counts', msp_kernel_counts());
end;
$$;
revoke execute on function msp_kernel_release(text, text) from public, anon;

insert into msp_kernel_version (semver, change_summary, kernel_counts, created_by)
values ('1.0.0',
        'First complete release of the Care Net Cognitive Kernel: migrations 001 to 029. Full South African taxonomy (17 industries, 56 selectable subindustries), 31 triple verified instruments, deduplicated protocol set, register closures for the NER 2024 noise values, PrDP provision, COIDA circular instructions, and retention framework. Subject to OMP ratification per release.',
        msp_kernel_counts(),
        'Claude Code build agent');

-- 2. Monthly agent harness: continuous learning and correctness audit -----------

create table msp_kernel_agent_run (
  id uuid primary key default gen_random_uuid(),
  run_on timestamptz not null default now(),
  kind text not null check (kind in ('monthly_audit', 'learning_update')),
  report jsonb not null,
  outcome text not null check (outcome in ('clean', 'findings', 'failed'))
);
comment on table msp_kernel_agent_run is 'Every run of the Cognitive Kernel maintenance agent lands here: the scheduled monthly correctness audit, and each learning update the agent applies after verification.';

alter table msp_kernel_agent_run enable row level security;
create policy msp_kernel_agent_run_read on msp_kernel_agent_run
  for select to authenticated using (msp_has_role('forge_omp') or msp_has_role('forge_admin') or msp_has_role('forge_verifier'));

create or replace function msp_kernel_monthly_audit()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_due jsonb;
  v_unprotocolled int;
  v_dash int := 0;
  v_rec record;
  v_cnt int;
  v_report jsonb;
  v_outcome text;
begin
  select coalesce(jsonb_agg(jsonb_build_object('short_name', short_name, 'review_due', review_due)), '[]'::jsonb)
    into v_due from msp_verification_due;

  select count(*) into v_unprotocolled
    from msp_hazard h
   where not exists (select 1 from msp_test_protocol tp where tp.hazard_id = h.id)
     and h.code not in ('O','N');

  for v_rec in
    select table_name, column_name
      from information_schema.columns
     where table_schema = 'public' and table_name like 'msp\_%'
       and data_type in ('text', 'character varying')
  loop
    execute format('select count(*) from %I where %I ~ ''—|–''', v_rec.table_name, v_rec.column_name) into v_cnt;
    v_dash := v_dash + v_cnt;
  end loop;

  v_report := jsonb_build_object(
    'counts', msp_kernel_counts(),
    'verification_due', v_due,
    'unprotocolled_hazards', v_unprotocolled,
    'dash_violations', v_dash,
    'current_version', (select semver from msp_kernel_version order by released_on desc, semver desc limit 1));

  v_outcome := case when jsonb_array_length(v_due) > 0 or v_unprotocolled > 0 or v_dash > 0
                    then 'findings' else 'clean' end;

  insert into msp_kernel_agent_run (kind, report, outcome) values ('monthly_audit', v_report, v_outcome);
  insert into msp_audit (actor, event_type, event_detail)
  values ('kernel maintenance agent', 'kernel_monthly_audit', v_report || jsonb_build_object('outcome', v_outcome));

  return v_report || jsonb_build_object('outcome', v_outcome);
end;
$$;
revoke execute on function msp_kernel_monthly_audit() from public, anon;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('msp-kernel-monthly-audit', '0 6 1 * *', 'select msp_kernel_monthly_audit()');
    raise notice 'monthly audit scheduled: first day of each month, 06:00 UTC';
  else
    raise notice 'pg_cron not installed: schedule msp_kernel_monthly_audit() via the dashboard or the maintenance agent';
  end if;
exception when others then
  raise notice 'cron scheduling skipped: %', sqlerrm;
end $$;

-- 3. OMP industry review queue: demos and ratification across the taxonomy ------

create table msp_omp_industry_review (
  id uuid primary key default gen_random_uuid(),
  industry_code text not null unique,
  industry_name text not null,
  status text not null default 'pending'
    check (status in ('pending', 'demo_run', 'approved', 'changes_requested')),
  reviewed_by text,
  hpcsa_number text,
  reviewed_on date,
  notes text
);
comment on table msp_omp_industry_review is 'The OMP reviews every industry: run the demo pack, test the prescriptions, then approve or request changes. Kernel recommendations deploy per industry only once its row is approved.';

alter table msp_omp_industry_review enable row level security;
create policy msp_omp_industry_review_read on msp_omp_industry_review
  for select to authenticated using (true);

insert into msp_omp_industry_review (industry_code, industry_name)
select code, name from msp_industry order by code;

create or replace function msp_omp_review_industry(
  p_industry_code text, p_status text, p_reviewed_by text, p_hpcsa_number text, p_notes text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not msp_caller_is('forge_omp') then
    raise exception 'industry review requires the forge_omp role';
  end if;
  if p_status in ('approved', 'changes_requested')
     and (coalesce(btrim(p_reviewed_by), '') = '' or coalesce(btrim(p_hpcsa_number), '') = '') then
    raise exception 'an approval or change request requires the reviewing OMP name and HPCSA number';
  end if;
  update msp_omp_industry_review
     set status = p_status, reviewed_by = p_reviewed_by, hpcsa_number = p_hpcsa_number,
         reviewed_on = current_date, notes = p_notes
   where industry_code = upper(p_industry_code);
  if not found then
    raise exception 'unknown industry code %', p_industry_code;
  end if;
  insert into msp_audit (actor, event_type, event_detail)
  values (p_reviewed_by, 'omp_industry_review',
          jsonb_build_object('industry_code', upper(p_industry_code), 'status', p_status, 'hpcsa_number', p_hpcsa_number));
  return jsonb_build_object('industry_code', upper(p_industry_code), 'status', p_status);
end;
$$;
revoke execute on function msp_omp_review_industry(text, text, text, text, text) from public, anon;

-- 4. Client accounts linked to Supabase Auth ------------------------------------

alter table msp_client_account
  add column auth_user_id uuid unique references auth.users(id),
  add column annual_medicals_estimate int;

create policy msp_client_account_own on msp_client_account
  for select to authenticated using (auth_user_id = auth.uid());

comment on column msp_client_account.auth_user_id is 'Supabase Auth linkage: every client contact becomes an auth user so packs, revisions, and the review journey are served under their own login.';
comment on column msp_client_account.annual_medicals_estimate is 'Self declared occupational medicals per year with Care Net; at or above the free qualification threshold the assessment tool is free, verified by a consultant before the waiver is confirmed.';

-- 5. The 100 medicals per year free qualification rule --------------------------

alter table msp_quote add column annual_medicals_estimate int;

create or replace function msp_create_quote(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate msp_pricing%rowtype;
  v_price numeric;
  v_status text;
  v_ref text;
  v_id uuid;
  v_emp int := coalesce((p->>'employee_count')::int, 0);
  v_jobs int := coalesce((p->>'job_category_count')::int, 0);
  v_medicals int := coalesce((p->>'annual_medicals_estimate')::int, 0);
begin
  if coalesce(p->>'company_name','') = '' or coalesce(p->>'contact_email','') = '' then
    raise exception 'company name and contact email are required';
  end if;
  if v_emp < 1 or v_jobs < 1 then
    raise exception 'employee count and job category count must be at least one';
  end if;
  select * into v_rate from msp_pricing
   where industry_code = upper(p->>'industry_code')
   order by effective_from desc limit 1;
  if v_rate.id is null then
    raise exception 'no rate card for industry %; the quote routes to a consultant', p->>'industry_code';
  end if;
  if v_medicals >= 100 then
    v_price := 0;
    v_status := 'free_qualifying';
  else
    v_price := v_rate.base_fee_zar + v_rate.per_employee_zar * v_emp + v_rate.per_job_category_zar * v_jobs;
    v_status := case when v_rate.status = 'confirmed' then 'firm' else 'indicative' end;
  end if;
  v_ref := 'CNC-QTE-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(nextval('msp_quote_seq')::text, 3, '0');
  insert into msp_quote (quote_reference, company_name, contact_name, contact_email,
                         industry_code, company_size, employee_count, job_category_count,
                         annual_medicals_estimate, price_zar, price_status)
  values (v_ref, p->>'company_name', coalesce(p->>'contact_name',''), p->>'contact_email',
          upper(p->>'industry_code'), p->>'company_size', v_emp, v_jobs,
          v_medicals, v_price, v_status)
  returning id into v_id;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (null, 'webhook', 'quote_created',
          jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'price_zar', v_price,
                             'price_status', v_status, 'annual_medicals_estimate', v_medicals));
  return jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'price_zar', v_price,
                            'price_status', v_status, 'valid_until', current_date + 30);
end;
$$;
revoke execute on function msp_create_quote(jsonb) from public, anon, authenticated;

-- 6. Register entries ------------------------------------------------------------

insert into msp_confirmation_item (item_code, kind, description, status) values
('CR-13.15', 'confirm',
 'Free qualification rule: a client declaring 100 or more occupational medicals per year with Care Net receives the assessment tool free (quote priced at zero, status free_qualifying). The declaration is self reported at quote time and a consultant verifies the medicals volume before the waiver is confirmed on the invoice. Confirm the threshold and the verification workflow with commercial leadership.',
 'open'),
('CR-13.16', 'confirm',
 'Cognitive Kernel maintenance agent: the monthly audit function is in place and scheduled where pg_cron is available; the learning update leg requires a standing Claude agent session (or scheduled cloud session) wired to the Supabase project per SOP-KERNEL-AGENT.md. Confirm the agent schedule and the OMP ratification cadence per kernel release.',
 'open');
