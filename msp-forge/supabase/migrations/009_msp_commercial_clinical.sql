-- CNC MSP FORGE | POP-OMP-01 v1.1.0, FRM-GATE-01 v1.0.0 | Clinical recommendations,
-- review signature, commercial gating, pricing, quotes, and revisions.
-- Phase 5B migration 009.

-- 1. Clinical recommendation area and signature on the review ------------------

create table msp_omp_recommendation (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references msp_omp_review(id),
  engagement_id uuid not null references msp_engagement(id),
  recommendation text not null,
  category text not null default 'general'
    check (category in ('general','controls','surveillance','referral_pathway','fit_testing','follow_up')),
  made_by text not null,
  hpcsa_number text,
  created_at timestamptz default now()
);
comment on table msp_omp_recommendation is 'The recommendation area: the reviewing health professional records recommendations against a draft without, or alongside, a decision. Recommendations are programme level and never name an individual or a diagnosis.';

alter table msp_omp_review
  add column if not exists signature_name text,
  add column if not exists signature_image text,
  add column if not exists signed_at timestamptz;
comment on column msp_omp_review.signature_image is 'Data URL of the drawn or typed signature applied in the review interface at decision time. The DocuSeal envelope remains the formal dual sign off channel for the released pack.';

alter table msp_omp_recommendation enable row level security;
create policy msp_omp_recommendation_read on msp_omp_recommendation
  for select to authenticated using (msp_any_forge_role());
create policy msp_omp_recommendation_write on msp_omp_recommendation
  for insert to authenticated with check (msp_has_role('forge_omp'));

create or replace function msp_omp_recommend(
  p_review_id uuid,
  p_recommendation text,
  p_category text,
  p_made_by text,
  p_hpcsa_number text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng uuid; v_id uuid;
begin
  if not msp_caller_is('forge_omp') then
    raise exception 'only the reviewing health professional may record a recommendation';
  end if;
  if coalesce(btrim(p_recommendation),'') = '' or coalesce(btrim(p_made_by),'') = '' then
    raise exception 'a recommendation requires text and the professional''s name';
  end if;
  select engagement_id into v_eng from msp_omp_review where id = p_review_id;
  if v_eng is null then raise exception 'review % not found', p_review_id; end if;
  insert into msp_omp_recommendation (review_id, engagement_id, recommendation, category, made_by, hpcsa_number)
  values (p_review_id, p_recommendation, coalesce(nullif(p_category,''),'general'), p_made_by, p_hpcsa_number)
  returning id into v_id;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng, 'omp:' || p_made_by, 'omp_recommendation',
          jsonb_build_object('review_id', p_review_id, 'recommendation_id', v_id, 'category', p_category));
  return v_id;
end;
$$;
grant execute on function msp_omp_recommend(uuid, text, text, text, text) to authenticated;
revoke execute on function msp_omp_recommend(uuid, text, text, text, text) from anon, public;

create or replace function msp_omp_sign(
  p_review_id uuid,
  p_signature_name text,
  p_signature_image text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_eng uuid;
begin
  if not msp_caller_is('forge_omp') then
    raise exception 'only the reviewing health professional may sign';
  end if;
  update msp_omp_review
     set signature_name = p_signature_name, signature_image = p_signature_image, signed_at = now()
   where id = p_review_id
   returning engagement_id into v_eng;
  if v_eng is null then raise exception 'review % not found', p_review_id; end if;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng, 'omp:' || p_signature_name, 'omp_signature_applied',
          jsonb_build_object('review_id', p_review_id));
end;
$$;
grant execute on function msp_omp_sign(uuid, text, text) to authenticated;
revoke execute on function msp_omp_sign(uuid, text, text) from anon, public;

-- 2. Client accounts and the approval gate -------------------------------------

create table msp_client_account (
  id uuid primary key default gen_random_uuid(),
  company_name text not null,
  contact_name text not null,
  contact_email text not null,
  account_kind text not null default 'applicant'
    check (account_kind in ('applicant','approved_client','declined')),
  approved_by text,
  approved_at timestamptz,
  notes text,
  created_at timestamptz default now()
);
comment on table msp_client_account is 'Landing page sign on. An approved CNC client receives the assessment as a client benefit; everyone else follows the quote and payment path.';

alter table msp_client_account enable row level security;
create policy msp_client_account_read on msp_client_account
  for select to authenticated using (msp_has_role('forge_admin'));
create policy msp_client_account_update on msp_client_account
  for update to authenticated using (msp_has_role('forge_admin'));

-- 3. Pricing and quotes --------------------------------------------------------

create table msp_pricing (
  id uuid primary key default gen_random_uuid(),
  industry_code text not null references msp_industry(code),
  base_fee_zar numeric not null,
  per_employee_zar numeric not null,
  per_job_category_zar numeric not null,
  status text not null default 'placeholder' check (status in ('placeholder','confirmed')),
  effective_from date default current_date,
  unique (industry_code, effective_from)
);
comment on table msp_pricing is 'Industry rate card. Rows carry status placeholder until CNC confirms commercial rates (CR-13.14); a placeholder priced quote is always marked indicative.';

create table msp_quote (
  id uuid primary key default gen_random_uuid(),
  quote_reference text unique not null,
  company_name text not null,
  contact_name text not null,
  contact_email text not null,
  industry_code text not null,
  company_size text,
  employee_count int not null,
  job_category_count int not null,
  price_zar numeric not null,
  price_status text not null check (price_status in ('indicative','firm')),
  status text not null default 'quoted'
    check (status in ('quoted','accepted','paid','expired','waived_client_benefit')),
  payment_reference text,
  created_at timestamptz default now(),
  valid_until date default current_date + 30
);

alter table msp_pricing enable row level security;
alter table msp_quote enable row level security;
create policy msp_pricing_read on msp_pricing
  for select to authenticated using (msp_any_forge_role());
create policy msp_pricing_write on msp_pricing
  for insert to authenticated with check (msp_has_role('forge_admin'));
create policy msp_pricing_update on msp_pricing
  for update to authenticated using (msp_has_role('forge_admin'));
create policy msp_quote_read on msp_quote
  for select to authenticated using (msp_has_role('forge_admin'));
create policy msp_quote_update on msp_quote
  for update to authenticated using (msp_has_role('forge_admin'));

create sequence if not exists msp_quote_seq;

create or replace function msp_create_quote(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate msp_pricing%rowtype;
  v_price numeric;
  v_ref text;
  v_id uuid;
  v_emp int := coalesce((p->>'employee_count')::int, 0);
  v_jobs int := coalesce((p->>'job_category_count')::int, 0);
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
  v_price := v_rate.base_fee_zar + v_rate.per_employee_zar * v_emp + v_rate.per_job_category_zar * v_jobs;
  v_ref := 'CNC-QTE-' || to_char(current_date, 'YYYY-MMDD') || '-' || lpad(nextval('msp_quote_seq')::text, 3, '0');
  insert into msp_quote (quote_reference, company_name, contact_name, contact_email,
                         industry_code, company_size, employee_count, job_category_count,
                         price_zar, price_status)
  values (v_ref, p->>'company_name', coalesce(p->>'contact_name',''), p->>'contact_email',
          upper(p->>'industry_code'), p->>'company_size', v_emp, v_jobs,
          v_price, case when v_rate.status = 'confirmed' then 'firm' else 'indicative' end)
  returning id into v_id;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (null, 'webhook', 'quote_created',
          jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'price_zar', v_price,
                             'price_status', case when v_rate.status = 'confirmed' then 'firm' else 'indicative' end));
  return jsonb_build_object('quote_id', v_id, 'reference', v_ref, 'price_zar', v_price,
                            'price_status', case when v_rate.status = 'confirmed' then 'firm' else 'indicative' end,
                            'valid_until', current_date + 30);
end;
$$;
revoke execute on function msp_create_quote(jsonb) from public, anon, authenticated;

-- 4. Form access tokens --------------------------------------------------------

create table msp_form_access (
  id uuid primary key default gen_random_uuid(),
  token text unique not null default encode(extensions.gen_random_bytes(24), 'hex'),
  granted_via text not null check (granted_via in ('approved_client','paid_quote','manual')),
  quote_id uuid references msp_quote(id),
  client_account_id uuid references msp_client_account(id),
  company_name text not null,
  used_by_intake uuid references msp_intake(id),
  expires_at timestamptz not null default now() + interval '60 days',
  created_at timestamptz default now()
);
comment on table msp_form_access is 'One token, one assessment. Issued on client approval or on payment confirmation; consumed by the intake that uses it.';

alter table msp_form_access enable row level security;
create policy msp_form_access_read on msp_form_access
  for select to authenticated using (msp_has_role('forge_admin'));

create or replace function msp_grant_access(
  p_granted_via text,
  p_company_name text,
  p_quote_id uuid default null,
  p_client_account_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_token text; v_id uuid;
begin
  insert into msp_form_access (granted_via, company_name, quote_id, client_account_id)
  values (p_granted_via, p_company_name, p_quote_id, p_client_account_id)
  returning id, token into v_id, v_token;
  if p_quote_id is not null then
    update msp_quote set status = 'paid' where id = p_quote_id and status in ('quoted','accepted');
  end if;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (null, 'system', 'form_access_granted',
          jsonb_build_object('access_id', v_id, 'granted_via', p_granted_via, 'company', p_company_name));
  return jsonb_build_object('access_id', v_id, 'token', v_token);
end;
$$;
revoke execute on function msp_grant_access(text, text, uuid, uuid) from public, anon, authenticated;

create or replace function msp_check_access(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v msp_form_access%rowtype;
begin
  select * into v from msp_form_access where token = p_token;
  if v.id is null then return jsonb_build_object('valid', false, 'reason', 'unknown token'); end if;
  if v.used_by_intake is not null then return jsonb_build_object('valid', false, 'reason', 'token already used'); end if;
  if v.expires_at < now() then return jsonb_build_object('valid', false, 'reason', 'token expired'); end if;
  return jsonb_build_object('valid', true, 'company_name', v.company_name, 'access_id', v.id);
end;
$$;
revoke execute on function msp_check_access(text) from public, anon, authenticated;

-- 5. Revisions -----------------------------------------------------------------

alter table msp_engagement add column if not exists revision int not null default 1;
comment on column msp_engagement.revision is 'Pack revision number. A change notification or updated risk assessment increments the revision; every render records its revision in msp_document.version and the reference carries Rev N from revision 2 onward. Secure hosting of released revisions in MyClinicOnline awaits the MCO integration (CR-13.12).';

-- 6. Placeholder rate card and register items ----------------------------------

insert into msp_pricing (industry_code, base_fee_zar, per_employee_zar, per_job_category_zar, status)
values ('CONSTR', 4500, 35, 450, 'placeholder');

insert into msp_confirmation_item (item_code, kind, description, status) values
('CR-13.12', 'confirm', 'MyClinicOnline integration: API or filing mechanism for hosting released packs and revisions in MCO, and for surfacing the review interface link per company inside the MCO application.', 'open'),
('CR-13.13', 'confirm', 'Payment gateway selection and credentials for the quote path (the host platform ah_payment table is gateway agnostic, Peach referenced). Until wired, payment confirmation is a manual forge_admin action.', 'open'),
('CR-13.14', 'confirm', 'CNC commercial rate card per industry. The seeded Construction row (R4,500 base, R35 per employee, R450 per job category) is a PLACEHOLDER; every quote priced from it is marked indicative and states so.', 'open');
