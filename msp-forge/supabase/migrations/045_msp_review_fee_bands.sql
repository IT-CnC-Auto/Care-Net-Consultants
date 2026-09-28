-- CNC MSP FORGE | COM-02 v1.0.0 | The Plan is free, the review is banded 11/09/2026
-- Applied to the live project on 11/09/2026 (recorded there as 039_msp_review_fee_bands).
-- Numbered 045 in this repository because 039 to 044 were taken by the sign on,
-- self service, reference, legislation currency, contact number and draft work
-- that reached main first. The order of application in the live project was
-- 039 fee bands (11/09), then 040 self service (11/09) onward; nothing here
-- depends on those and nothing there depends on this.
-- The commercial model changes. The Plan itself is no longer priced from a rate
-- card: a company builds it at no charge and receives it watermarked. The only
-- charge is the practitioner review that lifts it into a document you can put in
-- front of an auditor or an inspector, and that is calculated per person on the
-- report with a floor for small jobs and a lower rate for large ones.
--
-- No price is published anywhere. The only number a visitor ever sees is the one
-- the calculator returns for the headcount they entered.

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('commercial.omp_review_rate_zar', '150', 'decimal', 0, 10000, 'commercial',
   'Practitioner review, rand per person on the report, standard rate.'),
  ('commercial.omp_review_rate_high_zar', '120', 'decimal', 0, 10000, 'commercial',
   'Practitioner review, rand per person, for reports above the high volume threshold.'),
  ('commercial.omp_review_high_threshold', '150', 'integer', 1, 100000, 'commercial',
   'Headcount above which the lower per person rate applies.'),
  ('commercial.omp_review_mid_threshold', '50', 'integer', 1, 100000, 'commercial',
   'Upper bound of the middle band, which carries a smaller surcharge.'),
  ('commercial.omp_review_small_threshold', '10', 'integer', 1, 100000, 'commercial',
   'Headcount below which the small job surcharge applies.'),
  ('commercial.omp_review_surcharge_small_zar', '1000', 'decimal', 0, 100000, 'commercial',
   'Surcharge added below the small threshold, because a short report still takes the practitioner a full sitting.'),
  ('commercial.omp_review_surcharge_mid_zar', '500', 'decimal', 0, 100000, 'commercial',
   'Surcharge added across the middle band.')
on conflict (key) do nothing;

-- The calculation, in one place, reading the bands every time so a change to a
-- parameter changes the next quotation with nothing redeployed.
create or replace function msp_review_fee(p_people int)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rate      numeric := msp_env_get_numeric('commercial.omp_review_rate_zar');
  v_rate_high numeric := msp_env_get_numeric('commercial.omp_review_rate_high_zar');
  v_high      int     := msp_env_get_int('commercial.omp_review_high_threshold');
  v_mid       int     := msp_env_get_int('commercial.omp_review_mid_threshold');
  v_small     int     := msp_env_get_int('commercial.omp_review_small_threshold');
  v_sur_small numeric := msp_env_get_numeric('commercial.omp_review_surcharge_small_zar');
  v_sur_mid   numeric := msp_env_get_numeric('commercial.omp_review_surcharge_mid_zar');
begin
  if p_people is null or p_people < 1 then
    raise exception 'the review fee needs a headcount of at least one';
  end if;
  if p_people > v_high then
    return round(p_people * v_rate_high, 2);
  elsif p_people > v_mid then
    return round(p_people * v_rate, 2);
  elsif p_people >= v_small then
    return round(p_people * v_rate + v_sur_mid, 2);
  else
    return round(p_people * v_rate + v_sur_small, 2);
  end if;
end;
$$;
comment on function msp_review_fee is
  'Practitioner review fee for a report covering this many people. Bands live in the parameter store, not in this function.';

-- The public face of the calculator. It returns the answer for the headcount
-- asked about and nothing else: no rate, no band table, no price list.
create or replace function msp_public_review_fee(p_people int)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_people is null or p_people < 1 or p_people > 100000 then
    return jsonb_build_object('ok', false, 'reason', 'headcount out of range');
  end if;
  return jsonb_build_object('ok', true, 'people', p_people, 'fee_zar', msp_review_fee(p_people));
end;
$$;
comment on function msp_public_review_fee is
  'Calculator endpoint for the website. Deliberately anonymous: it answers for one headcount and never discloses the bands behind the answer.';

revoke all on function msp_public_review_fee(int) from public;
grant execute on function msp_public_review_fee(int) to anon, authenticated;
revoke all on function msp_review_fee(int) from public, anon, authenticated;

-- Packages restated. The Plan is free; the review is what is bought.
alter table msp_package drop constraint if exists msp_package_fee_status_check;
alter table msp_package add constraint msp_package_fee_status_check
  check (fee_status in ('placeholder', 'confirmed', 'calculated'));

update msp_package set
  name = 'Your Plan, free to build',
  description = 'The full assessment and your Medical Surveillance Plan drafted against the verified law for your industry, delivered watermarked as your working copy. The watermark lifts for Care Net clients and when medicals are booked with Care Net.',
  omp_review_fee_zar = 0,
  fee_status = 'confirmed'
 where package_code = 'DRAFT_PLAN';

update msp_package set
  name = 'Reviewed and signed by the practitioner',
  description = 'Your Plan read line by line and signed by a registered Occupational Medical Practitioner, which is what makes it defensible in front of an auditor, an inspector or a client. Charged per person on the report.',
  omp_review_fee_zar = null,
  fee_status = 'calculated'
 where package_code = 'SIGNED_PLAN';

-- The quotation follows the same model: the Plan costs nothing, the review is
-- banded on headcount, and the free qualification now only ever affects the
-- watermark, because there is no longer a Plan price to waive.
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
  v_free boolean;
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

  v_free := v_medicals >= msp_env_get_int('commercial.free_medicals_threshold')
            or exists (select 1 from msp_client_account
                        where lower(contact_email) = lower(p->>'contact_email')
                          and sla_status = 'active_sla');

  if v_pkg.includes_omp_review then
    v_omp := msp_review_fee(v_emp);
  end if;

  v_status := case when v_omp = 0 then 'free_qualifying' else 'firm' end;

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
                             'price_status', v_status, 'watermark_free', v_free));

  return jsonb_build_object('quote_id', v_id, 'reference', v_ref,
                            'package_name', v_pkg.name,
                            'plan_zar', 0,
                            'omp_review_fee_zar', v_omp,
                            'price_zar', v_omp,
                            'price_status', v_status,
                            'watermark_free', v_free,
                            'valid_until', (current_date + msp_env_get_int('commercial.quote_validity_days'))::text);
end;
$$;
