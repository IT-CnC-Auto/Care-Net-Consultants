-- CNC MSP FORGE | COM-02 v1.1.0 | Self service pricing stops at 100 people 13/10/2026
-- The site has quoted in writing above 100 people since 07/10/2026 (shop.html,
-- QUOTE_ABOVE), but the database behind it still priced any headcount up to
-- 100,000. Through the public lookup that exposed the band edge at 150/151, where
-- the fee falls from R22,500.00 to R18,120.00 (150 x R150 against 151 x R120),
-- and every quote above 100 people was stored with an automatic "firm" figure the
-- page tells the visitor a sales executive will write. IT told the MD on 12/10/2026
-- that the lookup would stop at 100.
--
-- This migration:
--   1. adds commercial.public_fee_max_people (100), the one place the ceiling lives;
--   2. msp_public_review_fee answers ok false, reason written_quote, above it;
--   3. msp_create_quote stores no figure above it: price_status written_quote,
--      price and review fee left empty for the sales executive; the response says
--      written_quote true. At or below 100 nothing changes;
--   4. msp_quote.price_zar may be empty only on a written quotation (check added);
--   5. the DRAFT_PLAN package description stops promising that the marking lifts for
--      Care Net clients (MD ruling of 12/10/2026, migration 069); no page reads it.
-- msp_review_fee itself is unchanged; the 9/10 and 50/51 band steps wait for the
-- new band table.

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('commercial.public_fee_max_people', '100', 'integer', 1, 100000, 'commercial',
   'Largest headcount the website calculator and the self service quotation price automatically. Above it a sales executive quotes in writing.')
on conflict (key) do nothing;

insert into msp_env_parameter_history (key, old_value, new_value, changed_by, reason)
select 'commercial.public_fee_max_people', null, '100', 'migration_070', 'Self service pricing stops at 100 people, matching the site'
 where not exists (select 1 from msp_env_parameter_history where key = 'commercial.public_fee_max_people');

alter table msp_quote alter column price_zar drop not null;
alter table msp_quote drop constraint if exists msp_quote_price_status_check;
alter table msp_quote add constraint msp_quote_price_status_check
  check (price_status in ('indicative', 'firm', 'free_qualifying', 'written_quote'));
alter table msp_quote drop constraint if exists msp_quote_price_present;
alter table msp_quote add constraint msp_quote_price_present
  check (price_zar is not null or price_status = 'written_quote');

create or replace function msp_public_review_fee(p_people int)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_max int := coalesce(msp_env_get_int('commercial.public_fee_max_people'), 100);
begin
  if p_people is null or p_people < 1 or p_people > 100000 then
    return jsonb_build_object('ok', false, 'reason', 'headcount out of range');
  end if;
  if p_people > v_max then
    return jsonb_build_object('ok', false, 'reason', 'written_quote', 'max_people', v_max);
  end if;
  return jsonb_build_object('ok', true, 'people', p_people, 'fee_zar', msp_review_fee(p_people));
end;
$$;
comment on function msp_public_review_fee is
  'Calculator endpoint for the website. Deliberately anonymous: it answers for one headcount up to commercial.public_fee_max_people and never discloses the bands behind the answer. Above the ceiling it answers written_quote.';

create or replace function msp_create_quote(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pkg msp_package%rowtype;
  v_omp numeric := 0;
  v_status text;
  v_ref text;
  v_id uuid;
  v_emp int := coalesce((p->>'employee_count')::int, 0);
  v_jobs int := coalesce((p->>'job_category_count')::int, 0);
  v_medicals int := coalesce((p->>'annual_medicals_estimate')::int, 0);
  v_client boolean;
  v_max int := coalesce(msp_env_get_int('commercial.public_fee_max_people'), 100);
begin
  if coalesce(p->>'company_name','') = '' or coalesce(p->>'contact_email','') = '' then
    raise exception 'company name and contact email are required';
  end if;
  if v_emp < 1 then
    raise exception 'the headcount to be covered must be at least one';
  end if;

  select * into v_pkg from msp_package
   where package_code = upper(coalesce(p->>'package_code', 'SIGNED_PLAN'));
  if v_pkg.id is null then
    raise exception 'unknown package %', p->>'package_code';
  end if;

  v_client := v_medicals >= msp_env_get_int('commercial.free_medicals_threshold')
            or exists (select 1 from msp_client_account
                        where lower(contact_email) = lower(p->>'contact_email')
                          and sla_status = 'active_sla');

  -- Above the self service ceiling the site promises a written quotation, so no
  -- automatic figure is stored: a sales executive prices it from the sites, shifts
  -- and job categories.
  if v_emp > v_max then
    v_omp := null;
    v_status := 'written_quote';
  else
    if v_pkg.includes_omp_review then
      v_omp := msp_review_fee(v_emp);
    end if;
    v_status := case when v_omp = 0 then 'free_qualifying' else 'firm' end;
  end if;

  v_ref := 'CNC-QTE-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(nextval('msp_quote_seq')::text, 3, '0');
  insert into msp_quote (quote_reference, company_name, contact_name, contact_email,
                         industry_code, company_size, employee_count, job_category_count,
                         annual_medicals_estimate, package_code, omp_review_fee_zar,
                         price_zar, price_status)
  values (v_ref, p->>'company_name', p->>'contact_name', p->>'contact_email',
          upper(coalesce(p->>'industry_code','OTHER')), p->>'company_size', v_emp, v_jobs,
          v_medicals, v_pkg.package_code, v_omp, v_omp, v_status)
  returning id into v_id;

  insert into msp_audit (actor, event_type, event_detail)
  values ('msp_create_quote', 'quote_created',
          jsonb_build_object('reference', v_ref, 'package', v_pkg.package_code,
                             'people', v_emp, 'review_fee_zar', v_omp,
                             'price_status', v_status, 'care_net_client', v_client));

  return jsonb_build_object('quote_id', v_id, 'reference', v_ref,
                            'package_name', v_pkg.name,
                            'plan_zar', 0,
                            'written_quote', v_status = 'written_quote',
                            'omp_review_fee_zar', v_omp,
                            'price_zar', v_omp,
                            'price_status', v_status,
                            'care_net_client', v_client,
                            'valid_until', (current_date + msp_env_get_int('commercial.quote_validity_days'))::text);
end;
$$;

update msp_package
   set description = 'The full assessment and your Medical Surveillance Plan drafted against the verified law for your industry, delivered as your working copy and marked planning only on every page, until a practitioner reviews it and signs.'
 where package_code = 'DRAFT_PLAN' and description ilike '%watermark lifts%';

notify pgrst, 'reload schema';
