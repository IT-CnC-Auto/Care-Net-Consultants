-- CNC MSP FORGE | SHOP-01 v1.0.0 | Packages, SLA lookup, and the OMP review fee 14/08/2026
-- The commercial journey: login or create company, automatic SLA and volume lookup,
-- package selection (plan draft, or OMP reviewed and signed), and quote breakdowns.

-- 1. Packages -------------------------------------------------------------------

create table msp_package (
  id uuid primary key default gen_random_uuid(),
  package_code text not null unique,
  name text not null,
  description text not null,
  includes_omp_review boolean not null default false,
  omp_review_fee_zar numeric,
  fee_status text not null default 'placeholder' check (fee_status in ('placeholder', 'confirmed'))
);
comment on table msp_package is 'Shop packages. The plan draft is a watermarked working document and is never a released pack; only the OMP reviewed and signed package produces a released deliverable, per the database release gate. The OMP review fee is a placeholder pending the SASOM Guideline on Occupational Medicine Fee Structures and Practices (2025 edition), accessible through the designated OMP''s SASOM membership.';

alter table msp_package enable row level security;
create policy msp_package_read on msp_package for select to authenticated, anon using (true);

insert into msp_package (package_code, name, description, includes_omp_review, omp_review_fee_zar, fee_status) values
('DRAFT_PLAN', 'Medical Surveillance Plan, working draft',
 'The full structured assessment and an engine drafted Plan against the verified regulatory kernel for your industry, delivered as a watermarked working draft for internal planning. Not a released clinical document: it carries no OMP signature and every page is marked draft.',
 false, null, 'confirmed'),
('SIGNED_PLAN', 'Medical Surveillance Plan, OMP reviewed and signed',
 'Everything in the working draft, plus review by a registered Occupational Medical Practitioner: clinical recommendations, ratification of the surveillance battery, and signature. This is the released, board ready Plan hosted with revision control.',
 true, 2500, 'placeholder');

-- 2. SLA status on client accounts ----------------------------------------------

alter table msp_client_account
  add column sla_status text not null default 'none' check (sla_status in ('none', 'active_sla'));
comment on column msp_client_account.sla_status is 'Clients under an active service level agreement receive the assessment tool as an included benefit, alongside the 100 medicals per year qualification.';

-- 3. Company lookup for the signed in journey ------------------------------------

create or replace function msp_company_lookup(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account%rowtype;
begin
  select * into v_acc
    from msp_client_account
   where lower(contact_email) = lower(btrim(p_email))
   order by created_at desc
   limit 1;

  if v_acc.id is null then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object(
    'found', true,
    'company_name', v_acc.company_name,
    'account_kind', v_acc.account_kind,
    'sla_status', v_acc.sla_status,
    'annual_medicals_estimate', coalesce(v_acc.annual_medicals_estimate, 0),
    'tool_free', v_acc.sla_status = 'active_sla' or coalesce(v_acc.annual_medicals_estimate, 0) >= 100);
end;
$$;
revoke execute on function msp_company_lookup(text) from public, anon, authenticated;
comment on function msp_company_lookup is 'Server side only: the endpoint verifies the caller''s Supabase Auth token first and passes the authenticated email, so an account status is only ever revealed to its own signed in contact.';

-- 4. Quote with package and fee breakdown ----------------------------------------

alter table msp_quote
  add column package_code text default 'SIGNED_PLAN',
  add column omp_review_fee_zar numeric default 0;

create or replace function msp_create_quote(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate msp_pricing%rowtype;
  v_pkg msp_package%rowtype;
  v_base numeric;
  v_omp numeric := 0;
  v_status text;
  v_ref text;
  v_id uuid;
  v_emp int := coalesce((p->>'employee_count')::int, 0);
  v_jobs int := coalesce((p->>'job_category_count')::int, 0);
  v_medicals int := coalesce((p->>'annual_medicals_estimate')::int, 0);
  v_free boolean;
begin
  if coalesce(p->>'company_name','') = '' or coalesce(p->>'contact_email','') = '' then
    raise exception 'company name and contact email are required';
  end if;
  if v_emp < 1 or v_jobs < 1 then
    raise exception 'employee count and job category count must be at least one';
  end if;

  select * into v_pkg from msp_package
   where package_code = upper(coalesce(p->>'package_code', 'SIGNED_PLAN'));
  if v_pkg.id is null then
    raise exception 'unknown package %', p->>'package_code';
  end if;

  select * into v_rate from msp_pricing
   where industry_code = upper(p->>'industry_code')
   order by effective_from desc limit 1;
  if v_rate.id is null then
    raise exception 'no rate card for industry %; the quote routes to a consultant', p->>'industry_code';
  end if;

  v_free := v_medicals >= 100
            or exists (select 1 from msp_client_account
                        where lower(contact_email) = lower(p->>'contact_email')
                          and sla_status = 'active_sla');

  v_base := case when v_free then 0
                 else v_rate.base_fee_zar + v_rate.per_employee_zar * v_emp + v_rate.per_job_category_zar * v_jobs end;
  if v_pkg.includes_omp_review then
    v_omp := coalesce(v_pkg.omp_review_fee_zar, 0);
  end if;

  v_status := case
    when v_base + v_omp = 0 then 'free_qualifying'
    when v_rate.status = 'confirmed' and (not v_pkg.includes_omp_review or v_pkg.fee_status = 'confirmed') then 'firm'
    else 'indicative' end;

  v_ref := 'CNC-QTE-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(nextval('msp_quote_seq')::text, 3, '0');
  insert into msp_quote (quote_reference, company_name, contact_name, contact_email,
                         industry_code, company_size, employee_count, job_category_count,
                         annual_medicals_estimate, package_code, omp_review_fee_zar,
                         price_zar, price_status)
  values (v_ref, p->>'company_name', coalesce(p->>'contact_name',''), p->>'contact_email',
          upper(p->>'industry_code'), p->>'company_size', v_emp, v_jobs,
          v_medicals, v_pkg.package_code, v_omp,
          v_base + v_omp, v_status)
  returning id into v_id;

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (null, 'webhook', 'quote_created',
          jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'package', v_pkg.package_code,
                             'base_zar', v_base, 'omp_review_fee_zar', v_omp,
                             'price_zar', v_base + v_omp, 'price_status', v_status,
                             'tool_free', v_free, 'annual_medicals_estimate', v_medicals));

  return jsonb_build_object('quote_id', v_id, 'reference', v_ref,
                            'package_code', v_pkg.package_code, 'package_name', v_pkg.name,
                            'base_zar', v_base, 'omp_review_fee_zar', v_omp,
                            'price_zar', v_base + v_omp, 'tool_free', v_free,
                            'price_status', v_status, 'valid_until', current_date + 30);
end;
$$;
revoke execute on function msp_create_quote(jsonb) from public, anon, authenticated;

-- 5. Register --------------------------------------------------------------------

insert into msp_confirmation_item (item_code, kind, description, status) values
('CR-13.17', 'confirm',
 'OMP review and sign off fee: the shop carries a placeholder of R2,500 per Plan review, marked indicative on every quote until confirmed. The authoritative source is the SASOM Guideline on Occupational Medicine Fee Structures and Practices, 2025 edition, accessible through the designated OMP''s SASOM membership (SAS1270); public sources do not publish the tariff. Confirm the fee with the OMP and commercial leadership, then set msp_package.fee_status to confirmed.',
 'open');

update msp_confirmation_item
   set description = description || ' Update 14/08/2026: the free qualification now also applies to accounts with an active service level agreement (sla_status active_sla), checked automatically at quote time alongside the 100 medicals declaration.'
 where item_code = 'CR-13.15';
