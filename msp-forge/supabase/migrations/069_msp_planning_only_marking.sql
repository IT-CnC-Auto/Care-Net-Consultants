-- CNC MSP FORGE | DOC-GEN-01 v1.2.0 | The Plan is marked planning only until a practitioner signs 13/10/2026
-- MD ruling of 12/10/2026: every unsigned Plan is marked PLANNING ONLY, and the
-- marking states that no Occupational Medical Practitioner has reviewed or signed
-- it. It is a clinical statement, not a commercial one, so it lifts only on a
-- practitioner's approval and signature, never because of volume or an SLA.
--
-- This migration:
--   1. msp_create_quote: the flag watermark_free (set at 100 or more medicals a
--      year or an active SLA, with no signature in the condition) becomes
--      care_net_client. Same test; it now states a fact and grants nothing. What
--      such a client receives instead is the MD's call. No page or document read
--      watermark_free (the calculator applies its own test), and none of the five
--      quotes so far carried it as true.
--   2. msp_plan_signoff(reference): the practitioner sign off record the Plan
--      renderer (factory/render_pack.js v1.2.0) needs before it may leave the
--      marking off. Server side only. "signed" is true only for an approved
--      decision carrying the practitioner's name, HPCSA number, signature and
--      signing time.

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
                             'price_status', v_status, 'care_net_client', v_client));

  return jsonb_build_object('quote_id', v_id, 'reference', v_ref,
                            'package_name', v_pkg.name,
                            'plan_zar', 0,
                            'omp_review_fee_zar', v_omp,
                            'price_zar', v_omp,
                            'price_status', v_status,
                            'care_net_client', v_client,
                            'valid_until', (current_date + msp_env_get_int('commercial.quote_validity_days'))::text);
end;
$$;

create or replace function msp_plan_signoff(p_reference text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eng uuid;
  r msp_omp_review%rowtype;
begin
  select id into v_eng from msp_engagement where reference = p_reference;
  if v_eng is null then raise exception 'no engagement %', p_reference; end if;
  select * into r from msp_omp_review
   where engagement_id = v_eng and decision is not null
   order by decided_at desc nulls last limit 1;
  return jsonb_build_object(
    'reference', p_reference,
    'review_id', r.id,
    'decision', r.decision,
    'omp_name', r.omp_name,
    'omp_hpcsa_number', r.omp_hpcsa_number,
    'decided_at', r.decided_at,
    'signature_name', r.signature_name,
    'signed_at', r.signed_at,
    'signed', coalesce(r.decision = 'approved'
                       and nullif(trim(r.omp_name), '') is not null
                       and nullif(trim(r.omp_hpcsa_number), '') is not null
                       and nullif(trim(r.signature_name), '') is not null
                       and r.signed_at is not null, false));
end;
$$;
revoke execute on function msp_plan_signoff(text) from public, anon, authenticated;
comment on function msp_plan_signoff is 'Server side only: the latest practitioner decision on a Plan. signed = approved with name, HPCSA number, signature and signing time; only then may the Plan be rendered without the PLANNING ONLY marking.';

notify pgrst, 'reload schema';
