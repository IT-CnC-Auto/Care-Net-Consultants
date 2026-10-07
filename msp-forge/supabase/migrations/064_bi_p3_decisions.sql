-- CNC HSF FORGE | BI-DEC-01 v1.0.0 | Bee-Inspect P3 decisions locked by the Director 27/09/2026
-- Built to hsf/BUILD-CONTRACT.md 15.2, 16.7 and 16.8 (binding) and
-- hsf/BEE-INSPECT-P3-DECISIONS.md (freeze label Bee-Inspect-P3-Decisions-P0-20260927).
--
-- Migrations 059 to 063 are kept exactly as the P3 record; every change the
-- decisions make is here. Like them, this migration is not applied anywhere
-- but the local replay (contract 16.8: no Bee-Inspect staging project exists
-- yet). Migrations 001 to 063 are unchanged.
--
-- What this migration does:
--   1. Parameters (msp_env_parameter, category commercial): the free digital
--      Safety File thresholds bi.free_file.client_medicals_threshold (50) and
--      bi.free_file.site_medicals_threshold (500), how long a verified count
--      stays current (bi.free_file.count_max_age_days, 92, a build default),
--      the DocuSeal step up window (bi.step_up_docuseal_window_minutes, 1 440 =
--      24 hours; the app keeps bi.step_up_window_minutes, 10) and the minimum
--      margin (bi.margin.minimum_pct, 20). bi.markup_default may no longer go
--      below 1,25 (the markup that still leaves 20%).
--   2. Risk bands (decision 1.2): 1 to 4 Low (green), 5 to 9 Medium (amber),
--      10 to 15 High (orange), 16 to 25 Extreme (red). 060 already has these
--      cut points; this adds the label and colour to every score
--      (bi_risk_band_label, bi_risk_band_colour, bi_risk_assess, and four new
--      columns on bi_risk_register).
--   3. Free digital Safety File eligibility (decision 1.1, contract 16.8):
--      bi_medicals_volume (verified rolling 12 month counts per company and
--      per site, from occupational health, MCO or a sales executive, with the
--      evidence reference and the audit row), bi_site_subcontractor (a site's
--      registered subcontractor companies, each an msp_client_account) and
--      bi_free_file_eligible(company, site). The Care Net client flag is the
--      File's own: hsf_client_verified (migration 052). bi_hsf_section_f_sync
--      (061) is replaced: an Issued report of an eligible company files as
--      before (evidence, item uploaded, compliance recomputed); otherwise its
--      link waits as awaiting_eligibility with no evidence and no change to the
--      compliance figure, and the retry run files it once eligibility is
--      confirmed. Contract 15.2 (sign off price tiers 100 and 500) is not
--      touched.
--   4. Step up (decision 1.5): the Issued guard and bi_report_sign read both
--      windows from the parameters (no literal 1 440 any more).
--   5. Accounts and settings (decision section 2): several authorised persons
--      per company with their role (16(1), 16(2) and the H&S roles,
--      bi_authorised_person), their qualifications, professional
--      registrations and certificates with the certificate path and expiry
--      (bi_person_credential, private bucket bi-credentials), the credential
--      kind on inspector qualifications, POPIA consent purposes that default to
--      Not given (bi_consent_purpose, bi_consent_status, bi_consent_decide,
--      bi_consent_withdraw), and the dual gate before Issue: FICA and KYC
--      cleared and a qualification cleared (bi_signer_gate, enforced by the
--      Issued guard and at signing).
--   6. AI Wallet overspend (decision 1.3): bi_subsidy_ledger, append only, one
--      row per shortfall Care Net carries (reason, estimate, actual,
--      shortfall, job, user, company), written inside bi_wallet_charge
--      (replaced) when the balance runs out, which leaves the wallet at R0,00.
--      Top ups never look at subsidies. bi_wallet_estimate (replaced) also
--      returns the remaining balance and estimate_exceeds_balance.
--   7. Minimum margin 20% (decision 1.4): landed cost components on every
--      rate card row (model tokens, voice minutes, storage, SMS, gateway fee,
--      app store cut, KYC, transcription), per channel fees on the products
--      sold through Ozow web, the Apple App Store, Google Play or a saved card
--      (bi_rate_card_channel), bi_margin_check(), and guards that refuse to
--      activate a rate card row, a channel or a subscription price below the
--      floor. Every landed cost stays to_be_confirmed until the rate card is
--      known ({{rate_card}}), so nothing fails spuriously.
--   8. Export (decision 1.7): bi_super_user (an explicit assignment that only
--      the service role grants, and only to Care Net staff) and bi_export,
--      which only a super user may call (with a fresh step up) and which
--      writes bi_audit_log for every export and every refusal (who, what, row
--      count, when).
--
-- POPIA: bi_medicals_volume holds a number of medicals and where the number
-- came from, never a person or a result; its columns are named so that
-- bi_clinical_column_check (063) stays empty.
--
-- Access: RLS on every new table; nothing for anon; clients read through
-- policies and write nothing directly; every function is server side (service
-- role) unless it is a pure helper the policies and views need.

-- 0. Order and once only ---------------------------------------------------------------------------

do $$
begin
  if to_regclass('public.bi_report_file_link') is null or to_regprocedure('public.bi_hsf_section_f_sync(uuid)') is null
     or to_regprocedure('public.bi_wallet_charge(uuid, jsonb)') is null then
    raise exception '064: migrations 059 to 063 must run first';
  end if;
  if to_regclass('public.bi_subsidy_ledger') is not null then
    raise exception '064: already applied (bi_subsidy_ledger exists); Bee-Inspect migrations run once';
  end if;
end;
$$;

-- 1. Parameters ---------------------------------------------------------------------------------------

insert into msp_env_parameter (key, value, value_type, allowed_values, min_value, max_value, category, description, updated_by) values
  ('bi.free_file.client_medicals_threshold', '50', 'integer', null, 0, 1000000, 'commercial',
   'Bee-Inspect free digital Safety File, rule A (contract 16.8): a verified Care Net Consultants client (hsf_client_verified) with MORE THAN this many verified medicals in the rolling 12 months is eligible. 50 (Director, 27/09/2026). Separate from the sign off price tiers of contract 15.2.',
   'migration_064'),
  ('bi.free_file.site_medicals_threshold', '500', 'integer', null, 0, 10000000, 'commercial',
   'Bee-Inspect free digital Safety File, rule B (contract 16.8): a site with MORE THAN this many verified medicals in the rolling 12 months is eligible for that site, and so is every subcontractor registered on it. 500 (Director, 27/09/2026). Separate from contract 15.2.',
   'migration_064'),
  ('bi.free_file.count_max_age_days', '92', 'integer', null, 1, 366, 'commercial',
   'Bee-Inspect free digital Safety File: a verified rolling 12 month count stays current for this many days after the date it was counted to; after that a fresh count from MCO, occupational health or a sales executive is needed. Build default 92 days, for the Director''s confirmation.',
   'migration_064'),
  ('bi.step_up_docuseal_window_minutes', '1440', 'integer', null, 10, 1440, 'commercial',
   'Bee-Inspect: how many minutes a step up MFA assertion stays valid for signing through DocuSeal: 1 440 (24 hours, Director 27/09/2026). The in app window is bi.step_up_window_minutes (10).',
   'migration_064'),
  ('bi.margin.minimum_pct', '20', 'integer', null, 20, 90, 'commercial',
   'Bee-Inspect minimum margin after all costs (Director, 27/09/2026): sell price excluding VAT >= total landed cost x 100 / (100 less minimum_pct), that is landed cost / 0,80 at 20%. The floor of this parameter is 20: it can be raised, never lowered.',
   'migration_064')
on conflict (key) do nothing;

update msp_env_parameter
   set min_value = 1.25,
       description = 'Bee-Inspect AI Wallet markup: price = (tokens x model rate + audio minutes x transcription rate) x fx x markup (prompt B8). Default 3.0. Never below 1,25, the markup that still leaves the 20% minimum margin (decision 1.4).',
       updated_by = 'migration_064', updated_at = now()
 where key = 'bi.markup_default';
update msp_env_parameter
   set description = 'Bee-Inspect: how many minutes a step up MFA assertion stays valid in the app: an in app signature, a top up over R499,00, a bulk export or a Bee-Matched engagement. 10 (Director, 27/09/2026). DocuSeal signing uses bi.step_up_docuseal_window_minutes (24 hours).',
       updated_by = 'migration_064', updated_at = now()
 where key = 'bi.step_up_window_minutes';

-- 2. Shared helpers -----------------------------------------------------------------------------------

create function bi_format_rand(p_cents bigint)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_cents is null then null else
    (case when p_cents < 0 then '-' else '' end) || 'R'
    || regexp_replace((abs(p_cents) / 100)::text, '(\d)(?=(\d{3})+$)', '\1 ', 'g')
    || ',' || lpad((abs(p_cents) % 100)::text, 2, '0') end;
$$;
comment on function bi_format_rand is 'BI-DEC-01. Cents as rand in the house format: 400000 is R4 000,00. The same as formatRand in supabase/functions/_shared/bi/pricing.js. Used in the wording of refusals.';

create function bi_no_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% rows are ended or revoked, never deleted', tg_table_name;
end;
$$;
comment on function bi_no_delete is 'BI-DEC-01. Refuses a delete on a table whose rows are ended or revoked instead.';

-- 3. Risk bands: number, label and colour ---------------------------------------------------------------

comment on function bi_risk_band is 'BI-ENG-01, locked by BI-DEC-01 (decision 1.2, 27/09/2026). Band of a 5 x 5 score (likelihood x severity): 1 to 4 low, 5 to 9 medium, 10 to 15 high, 16 to 25 extreme. No other cut points. The label and colour come from bi_risk_band_label and bi_risk_band_colour; mirrored in supabase/functions/_shared/bi/risk.js.';

create function bi_risk_band_label(p_score int)
returns text
language sql
immutable
set search_path = public
as $$
  select case bi_risk_band(p_score) when 'low' then 'Low' when 'medium' then 'Medium'
                                    when 'high' then 'High' when 'extreme' then 'Extreme' end;
$$;
comment on function bi_risk_band_label is 'BI-DEC-01 (decision 1.2). The label shown beside every score: Low (1 to 4), Medium (5 to 9), High (10 to 15), Extreme (16 to 25).';

create function bi_risk_band_colour(p_band text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_band when 'low' then 'green' when 'medium' then 'amber' when 'high' then 'orange' when 'extreme' then 'red' end;
$$;
comment on function bi_risk_band_colour is 'BI-DEC-01 (decision 1.2). The colour token of a band: low green, medium amber, high orange, extreme red. The shades are in supabase/functions/_shared/bi/risk.js (BAND_TOKENS), shared by the app and the site.';

create function bi_risk_assess(p_likelihood int, p_severity int)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case when s.score is null then null else
    jsonb_build_object('likelihood', p_likelihood, 'severity', p_severity, 'score', s.score,
                       'band', bi_risk_band(s.score), 'label', bi_risk_band_label(s.score),
                       'colour', bi_risk_band_colour(bi_risk_band(s.score))) end
    from (select bi_risk_score(p_likelihood, p_severity) as score) s;
$$;
comment on function bi_risk_assess is 'BI-DEC-01 (decision 1.2). A 5 x 5 rating with its score, band, label and colour together, so the label is never shown without the number or the number without the label.';

create or replace view bi_risk_register with (security_invoker = true) as
select r.id, r.inspection_id, r.tenant_id, r.client_account_id, r.area_id, r.finding_id, r.hazard, r.consequence,
       r.inherent_likelihood, r.inherent_severity,
       bi_risk_score(r.inherent_likelihood, r.inherent_severity) as inherent_score,
       bi_risk_band(bi_risk_score(r.inherent_likelihood, r.inherent_severity)) as inherent_band,
       r.residual_likelihood, r.residual_severity,
       bi_risk_score(r.residual_likelihood, r.residual_severity) as residual_score,
       bi_risk_band(bi_risk_score(r.residual_likelihood, r.residual_severity)) as residual_band,
       bi_risk_top_control(r.controls) as top_control, r.controls,
       bi_risk_band_label(bi_risk_score(r.inherent_likelihood, r.inherent_severity)) as inherent_band_label,
       bi_risk_band_colour(bi_risk_band(bi_risk_score(r.inherent_likelihood, r.inherent_severity))) as inherent_band_colour,
       bi_risk_band_label(bi_risk_score(r.residual_likelihood, r.residual_severity)) as residual_band_label,
       bi_risk_band_colour(bi_risk_band(bi_risk_score(r.residual_likelihood, r.residual_severity))) as residual_band_colour
  from bi_risk r;
comment on view bi_risk_register is 'BI-ENG-01 and BI-DEC-01. Risks with their inherent and residual scores, bands, labels (Low, Medium, High, Extreme) and colours (green, amber, orange, red), and the top control. security_invoker, so bi_risk RLS applies.';

-- 4. Free digital Safety File eligibility (contract 16.8) -------------------------------------------------

create table bi_medicals_volume (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  site_id uuid references bi_site(id),
  counted_from date not null,
  counted_to date not null,
  volume_12m int not null check (volume_12m >= 0),
  source text not null check (source in ('occupational_health','mco','sales_executive_verified')),
  evidence_ref text not null check (length(btrim(evidence_ref)) between 3 and 200 and evidence_ref !~ '[[:cntrl:]]'),
  verified_by text not null check (length(btrim(verified_by)) between 2 and 200),
  verified_at timestamptz not null default now(),
  audit_log_id bigint not null references bi_audit_log(id),
  created_at timestamptz not null default now(),
  constraint bi_medicals_volume_window check (counted_to >= counted_from and counted_from >= (counted_to - interval '12 months')::date),
  constraint bi_medicals_volume_not_future check (counted_to <= verified_at::date)
);
comment on table bi_medicals_volume is 'BI-DEC-01 (decision 1.1, contract 16.8). A verified count of the medicals done for a company (site_id null) or one of its sites in a window of at most 12 months ending counted_to: the rolling 12 month count as at counted_to. source occupational_health or mco (the source of truth, fed by the service role) or sales_executive_verified (until MCO is connected, a Care Net sales executive records the count with its evidence, never the client''s own declaration). Every row carries its evidence reference, who verified it and when, and the bi_audit_log row written with it. Append only: a newer count supersedes an older one. A number and its source only: no person and no clinical result. Written only by bi_medicals_volume_record.';
comment on column bi_medicals_volume.volume_12m is 'Number of medicals in the window counted_from to counted_to (at most 12 months).';
comment on column bi_medicals_volume.counted_to is 'The date the rolling 12 month count runs to. The count is current for bi.free_file.count_max_age_days after it.';
comment on column bi_medicals_volume.audit_log_id is 'The bi_audit_log row (event medicals_volume_verified) written in the same transaction.';
create index bi_medicals_volume_company_idx on bi_medicals_volume(client_account_id, site_id, counted_to desc);
create trigger bi_medicals_volume_append_only before update or delete on bi_medicals_volume for each row execute function bi_append_only();

create table bi_site_subcontractor (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references bi_site(id),
  principal_account_id uuid not null references msp_client_account(id),
  subcontractor_account_id uuid not null references msp_client_account(id),
  subcontractor_site_id uuid references bi_site(id),
  evidence_ref text not null check (length(btrim(evidence_ref)) between 3 and 200 and evidence_ref !~ '[[:cntrl:]]'),
  registered_by text not null,
  registered_at timestamptz not null default now(),
  ended_by text,
  ended_at timestamptz,
  end_reason text,
  constraint bi_site_subcontractor_not_self check (subcontractor_account_id <> principal_account_id),
  constraint bi_site_subcontractor_end_pair check ((ended_at is null) = (ended_by is null) and (ended_at is null or length(btrim(coalesce(end_reason, ''))) >= 5))
);
comment on table bi_site_subcontractor is 'BI-DEC-01 (decision 1.1, contract 16.8). The site registry of subcontractors: each row registers one subcontractor company (an msp_client_account, never a copy) on a site of its principal. subcontractor_site_id is the subcontractor''s own bi_site for its work there (a Bee-Inspect inspection is always on a site of its own company), so its reports find the registration. While the principal is eligible for the site, the subcontractor''s digital Safety File is free for that site. Registered and ended by Care Net (ops) or the service role, with an evidence reference; ended, never deleted.';
create unique index bi_site_subcontractor_live_idx on bi_site_subcontractor(site_id, subcontractor_account_id) where ended_at is null;
create index bi_site_subcontractor_sub_idx on bi_site_subcontractor(subcontractor_account_id) where ended_at is null;

create function bi_site_subcontractor_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'bi_site_subcontractor rows are ended, never deleted';
  end if;
  if (to_jsonb(new) - array['ended_by','ended_at','end_reason']) is distinct from (to_jsonb(old) - array['ended_by','ended_at','end_reason'])
     or old.ended_at is not null then
    raise exception 'bi_site_subcontractor: only an ending may be recorded, once';
  end if;
  return new;
end;
$$;
create trigger bi_site_subcontractor_guard before update or delete on bi_site_subcontractor
  for each row execute function bi_site_subcontractor_guard();

create function bi_medicals_volume_current(p_company uuid, p_site uuid, p_as_at date default current_date)
returns bi_medicals_volume
language sql
stable
security definer
set search_path = public
as $$
  select m.* from bi_medicals_volume m
   where m.client_account_id = p_company
     and m.site_id is not distinct from p_site
     and m.counted_to <= p_as_at
     and m.counted_to > p_as_at - coalesce(msp_env_get_int('bi.free_file.count_max_age_days'), 92)
   order by m.counted_to desc, m.audit_log_id desc
   limit 1;
$$;
comment on function bi_medicals_volume_current is 'BI-DEC-01. The latest verified rolling 12 month count of a company (p_site null) or of one of its sites that is still current on p_as_at (counted to within bi.free_file.count_max_age_days), or null. Latest means the latest counted_to, then the latest recorded (audit order).';

create function bi_free_file_direct(p_company uuid, p_site uuid, p_as_at date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_client_t int := coalesce(msp_env_get_int('bi.free_file.client_medicals_threshold'), 50);
  v_site_t int := coalesce(msp_env_get_int('bi.free_file.site_medicals_threshold'), 500);
  v_verified boolean := coalesce(hsf_client_verified(p_company), false);
  v_co bi_medicals_volume;
  v_si bi_medicals_volume;
  v_reason text;
begin
  v_co := bi_medicals_volume_current(p_company, null, p_as_at);
  if p_site is not null then
    v_si := bi_medicals_volume_current(p_company, p_site, p_as_at);
  end if;
  -- Rule A: the File's own Care Net client flag (052) and more than the client threshold.
  -- Rule B: a site of the company with more than the site threshold.
  v_reason := case when v_verified and coalesce(v_co.volume_12m, 0) > v_client_t then 'care_net_client_over_50'
                   when coalesce(v_si.volume_12m, 0) > v_site_t then 'big_site_over_500' end;
  return jsonb_build_object(
    'reason', v_reason,
    'client_verified', v_verified,
    'company', case when v_co.id is null then null else jsonb_build_object('volume_12m', v_co.volume_12m, 'counted_from', v_co.counted_from,
                 'counted_to', v_co.counted_to, 'source', v_co.source, 'evidence_ref', v_co.evidence_ref, 'verified_at', v_co.verified_at) end,
    'site', case when v_si.id is null then null else jsonb_build_object('site_id', p_site, 'volume_12m', v_si.volume_12m, 'counted_from', v_si.counted_from,
                 'counted_to', v_si.counted_to, 'source', v_si.source, 'evidence_ref', v_si.evidence_ref, 'verified_at', v_si.verified_at) end);
end;
$$;
comment on function bi_free_file_direct is 'BI-DEC-01. Rules A and B for a company on its own (no subcontractor route): care_net_client_over_50, big_site_over_500 or null, with the counts used.';

create function bi_free_file_eligible(p_company uuid, p_site uuid default null, p_as_at date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_direct jsonb := bi_free_file_direct(p_company, p_site, p_as_at);
  v_reason text := v_direct ->> 'reason';
  v_sub jsonb;
  v_p jsonb;
  r record;
begin
  -- Subcontractor route: a live registration of this company on a site whose
  -- principal is eligible there (rule A or B), for that site only.
  if v_reason is null and p_site is not null then
    for r in
      select s.* from bi_site_subcontractor s
       where s.subcontractor_account_id = p_company and s.ended_at is null
         and s.registered_at::date <= p_as_at
         and (s.subcontractor_site_id = p_site or s.site_id = p_site)
       order by s.registered_at, s.id
    loop
      v_p := bi_free_file_direct(r.principal_account_id, r.site_id, p_as_at);
      if v_p ->> 'reason' is not null then
        v_reason := 'subcontractor_of_eligible_site';
        v_sub := jsonb_build_object('registration_id', r.id, 'principal_account_id', r.principal_account_id,
                   'principal_site_id', r.site_id, 'principal_reason', v_p ->> 'reason',
                   'principal_company', v_p -> 'company', 'principal_site', v_p -> 'site');
        exit;
      end if;
    end loop;
  end if;
  return jsonb_build_object(
    'eligible', v_reason is not null,
    'reason', coalesce(v_reason, 'not_eligible'),
    'as_at', p_as_at,
    'client_account_id', p_company,
    'site_id', p_site,
    'client_verified', (v_direct ->> 'client_verified')::boolean,
    'counts', jsonb_build_object('company', v_direct -> 'company', 'site', v_direct -> 'site', 'subcontractor', v_sub),
    'thresholds', jsonb_build_object(
      'client_medicals_more_than', coalesce(msp_env_get_int('bi.free_file.client_medicals_threshold'), 50),
      'site_medicals_more_than', coalesce(msp_env_get_int('bi.free_file.site_medicals_threshold'), 500),
      'count_max_age_days', coalesce(msp_env_get_int('bi.free_file.count_max_age_days'), 92)));
end;
$$;
comment on function bi_free_file_eligible is 'BI-DEC-01 (decision 1.1, contract 16.8). Whether a company qualifies for the free digital Safety File (for a site, when given) as at a date: {eligible, reason, counts, thresholds, as_at, client_verified}. reason care_net_client_over_50 (rule A: hsf_client_verified and more than bi.free_file.client_medicals_threshold verified medicals in the rolling 12 months), big_site_over_500 (rule B: the site has more than bi.free_file.site_medicals_threshold), subcontractor_of_eligible_site (the company is registered on a site whose principal is eligible there by rule A or B; for that site only) or not_eligible. The reason codes name the thresholds the Director set; the values are the parameters. Counts come only from bi_medicals_volume (verified sources), never from the client''s declaration.';

create function bi_medicals_volume_record(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid := nullif(p ->> 'client_account_id', '')::uuid;
  v_site uuid := nullif(p ->> 'site_id', '')::uuid;
  v_to date;
  v_from date;
  v_volume int;
  v_source text := p ->> 'source';
  v_ref text := btrim(coalesce(p ->> 'evidence_ref', ''));
  v_by text;
  v_id uuid := gen_random_uuid();
  v_audit bigint;
begin
  if p_auth_user is not null and not hsf_user_is_staff(p_auth_user) then
    raise exception 'Only Care Net records a verified medicals count.' using errcode = '42501';
  end if;
  v_by := case when p_auth_user is null then btrim(coalesce(p ->> 'verified_by', '')) else hsf_user_email(p_auth_user) end;
  if coalesce(v_by, '') = '' then
    raise exception 'Name who verified the count (verified_by).' using errcode = '22023';
  end if;
  if v_company is null or not exists (select 1 from msp_client_account where id = v_company) then
    raise exception 'That company was not found.' using errcode = 'P0002';
  end if;
  if v_site is not null and not exists (select 1 from bi_site s where s.id = v_site and s.client_account_id = v_company) then
    raise exception 'That site is not a site of this company.' using errcode = '22023';
  end if;
  if v_source is null or v_source not in ('occupational_health','mco','sales_executive_verified') then
    raise exception 'The source must be occupational_health, mco or sales_executive_verified.' using errcode = '22023';
  end if;
  begin
    v_to := coalesce(nullif(p ->> 'counted_to', '')::date, current_date);
    v_from := coalesce(nullif(p ->> 'counted_from', '')::date, (v_to - interval '12 months')::date + 1);
    v_volume := (p ->> 'volume_12m')::int;
  exception when others then
    raise exception 'counted_to and counted_from are dates and volume_12m a whole number.' using errcode = '22023';
  end;
  if v_volume is null or v_volume < 0 then
    raise exception 'volume_12m must be a whole number of zero or more.' using errcode = '22023';
  end if;
  if v_to > current_date then
    raise exception 'A count cannot run into the future.' using errcode = '22023';
  end if;
  if v_ref = '' or length(v_ref) not between 3 and 200 or v_ref ~ '[[:cntrl:]]' then
    raise exception 'Record what the count rests on (the MCO or occupational health reference, or the sales executive''s evidence), in 3 to 200 characters.' using errcode = '22023';
  end if;
  insert into bi_audit_log (actor_auth_user, actor_label, client_account_id, event, object_kind, object_id, detail)
  values (p_auth_user, coalesce(hsf_user_email(p_auth_user), 'service_role'), v_company, 'medicals_volume_verified', 'medicals_volume', v_id,
          jsonb_build_object('site_id', v_site, 'counted_from', v_from, 'counted_to', v_to, 'volume_12m', v_volume,
                             'source', v_source, 'evidence_ref', v_ref, 'verified_by', v_by))
  returning id into v_audit;
  insert into bi_medicals_volume (id, client_account_id, site_id, counted_from, counted_to, volume_12m, source, evidence_ref, verified_by, audit_log_id)
  values (v_id, v_company, v_site, v_from, v_to, v_volume, v_source, v_ref, v_by, v_audit);
  return jsonb_build_object('medicals_volume_id', v_id, 'audit_log_id', v_audit,
                            'eligibility', bi_free_file_eligible(v_company, v_site));
end;
$$;
comment on function bi_medicals_volume_record is 'BI-DEC-01 (contract 16.8). Records a verified rolling 12 month medicals count for a company or one of its sites: p = {client_account_id, site_id?, counted_to? (today), counted_from? (12 months before), volume_12m, source, evidence_ref, verified_by? (service role only; a staff caller is recorded by email)}. Callers: the service role (the MCO or occupational health feed, or ops tooling) or Care Net staff (hsf_user_is_staff): never the client, so a self declaration alone never counts. Audited in bi_audit_log (medicals_volume_verified) in the same transaction. Returns the new eligibility. Service role only.';

create function bi_site_subcontractor_register(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site bi_site;
  v_sub uuid := nullif(p ->> 'subcontractor_account_id', '')::uuid;
  v_sub_site uuid := nullif(p ->> 'subcontractor_site_id', '')::uuid;
  v_ref text := btrim(coalesce(p ->> 'evidence_ref', ''));
  v_id uuid;
begin
  if p_auth_user is not null and not bi_user_is_ops(p_auth_user) then
    raise exception 'Only Care Net registers a subcontractor on a site.' using errcode = '42501';
  end if;
  select * into v_site from bi_site where id = nullif(p ->> 'site_id', '')::uuid and archived_at is null;
  if v_site.id is null then
    raise exception 'That site was not found.' using errcode = 'P0002';
  end if;
  if v_sub is null or not exists (select 1 from msp_client_account where id = v_sub) then
    raise exception 'That subcontractor company was not found.' using errcode = 'P0002';
  end if;
  if v_sub = v_site.client_account_id then
    raise exception 'The principal is not its own subcontractor.' using errcode = '22023';
  end if;
  if v_sub_site is not null and not exists (select 1 from bi_site s where s.id = v_sub_site and s.client_account_id = v_sub) then
    raise exception 'subcontractor_site_id must be a site of the subcontractor company.' using errcode = '22023';
  end if;
  if length(v_ref) not between 3 and 200 or v_ref ~ '[[:cntrl:]]' then
    raise exception 'Record what the registration rests on (for example the principal''s contractor register), in 3 to 200 characters.' using errcode = '22023';
  end if;
  insert into bi_site_subcontractor (site_id, principal_account_id, subcontractor_account_id, subcontractor_site_id, evidence_ref, registered_by)
  values (v_site.id, v_site.client_account_id, v_sub, v_sub_site, v_ref, coalesce(hsf_user_email(p_auth_user), 'service_role'))
  returning id into v_id;
  perform bi_audit(p_auth_user, 'site_subcontractor_registered', null, v_site.client_account_id, 'site_subcontractor', v_id,
                   jsonb_build_object('site_id', v_site.id, 'subcontractor_account_id', v_sub, 'subcontractor_site_id', v_sub_site, 'evidence_ref', v_ref));
  return jsonb_build_object('registration_id', v_id, 'site_id', v_site.id, 'principal_account_id', v_site.client_account_id,
                            'subcontractor_account_id', v_sub, 'eligibility', bi_free_file_eligible(v_sub, coalesce(v_sub_site, v_site.id)));
end;
$$;
comment on function bi_site_subcontractor_register is 'BI-DEC-01 (contract 16.8). Registers a subcontractor company on a site of its principal: p = {site_id, subcontractor_account_id, subcontractor_site_id?, evidence_ref}. Care Net ops or the service role only, so a principal cannot hand free Files to companies on its own word. Audited. Service role only.';

create function bi_site_subcontractor_end(p_auth_user uuid, p_registration_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_site_subcontractor;
begin
  if p_auth_user is not null and not bi_user_is_ops(p_auth_user) then
    raise exception 'Only Care Net ends a subcontractor registration.' using errcode = '42501';
  end if;
  select * into v_r from bi_site_subcontractor where id = p_registration_id and ended_at is null for update;
  if v_r.id is null then
    raise exception 'That registration was not found.' using errcode = 'P0002';
  end if;
  update bi_site_subcontractor set ended_at = now(), ended_by = coalesce(hsf_user_email(p_auth_user), 'service_role'), end_reason = btrim(p_reason)
   where id = v_r.id;
  perform bi_audit(p_auth_user, 'site_subcontractor_ended', null, v_r.principal_account_id, 'site_subcontractor', v_r.id,
                   jsonb_build_object('reason', p_reason));
  return jsonb_build_object('registration_id', v_r.id, 'ended', true);
end;
$$;
comment on function bi_site_subcontractor_end is 'BI-DEC-01. Ends a subcontractor registration with a reason (at least five characters). Reports already filed stay filed. Care Net ops or the service role. Audited. Service role only.';

-- The link waits as awaiting_eligibility; the eligibility it was filed on is kept with it.
alter table bi_report_file_link drop constraint bi_report_file_link_status_check;
alter table bi_report_file_link add constraint bi_report_file_link_status_check
  check (status in ('linked','section_only','no_file','awaiting_eligibility','revoked'));
alter table bi_report_file_link add column eligibility_reason text
  check (eligibility_reason in ('care_net_client_over_50','big_site_over_500','subcontractor_of_eligible_site','not_eligible'));
alter table bi_report_file_link add column eligibility jsonb;
comment on table bi_report_file_link is 'BI-RPT-01 and BI-DEC-01 (prompt B7, contract 16.8). Where an Issued report sits in the company''s free File. linked: filed as evidence on the Section F element its template maps to. section_only: the File has no such element, so the report is listed in Section F without an element. no_file: the company has no File yet; a later run files it. awaiting_eligibility: the company is not (yet) eligible for the free digital Safety File for the report''s site, so the report is listed in Section F without evidence and without raising the compliance figure; the retry run files it once eligibility is confirmed. revoked: the report was withdrawn. eligibility_reason and eligibility record the answer of bi_free_file_eligible at the last attempt. Written only by bi_hsf_section_f_sync and bi_report_withdraw.';
comment on column bi_report_file_link.eligibility is 'The answer of bi_free_file_eligible (reason, counts, thresholds, as_at) when the link was last written.';

create or replace function bi_hsf_section_f_sync(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_report;
  v_link bi_report_file_link;
  v_file_id uuid;
  v_element text;
  v_site uuid;
  v_item hsf_file_item;
  v_version int;
  v_prev uuid;
  v_ev uuid;
  v_signer text;
  v_status text;
  v_elig jsonb;
  v_reason text;
begin
  select * into v_r from bi_report where id = p_report_id;
  if v_r.id is null or v_r.status <> 'issued' then
    raise exception 'Only an Issued report is filed into Section F.' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtext('bi_section_f'), hashtext(p_report_id::text));
  select * into v_link from bi_report_file_link where report_id = p_report_id;
  if v_link.report_id is not null and v_link.status in ('linked','section_only','revoked') then
    return jsonb_build_object('report_id', p_report_id, 'status', v_link.status, 'file_id', v_link.file_id,
                              'element_code', v_link.element_code, 'eligibility_reason', v_link.eligibility_reason, 'already', true);
  end if;

  -- The company's current File: the newest that is not superseded or archived.
  select f.id into v_file_id from hsf_file f
   where f.client_account_id = v_r.client_account_id and f.status not in ('superseded','archived')
   order by f.created_at desc, f.id limit 1;
  select t.section_f_element_code, i.site_id into v_element, v_site
    from bi_inspection i join bi_template t on t.id = i.template_id where i.id = v_r.inspection_id;

  -- Contract 16.8: only an eligible company's Issued report raises Section F
  -- and the compliance figure.
  v_elig := bi_free_file_eligible(v_r.client_account_id, v_site);
  v_reason := v_elig ->> 'reason';

  if not coalesce((v_elig ->> 'eligible')::boolean, false) then
    v_status := 'awaiting_eligibility';
    if v_file_id is not null then
      select fi.* into v_item from hsf_file_item fi join hsf_element e on e.id = fi.element_id
       where fi.file_id = v_file_id and e.code = v_element and e.section_code = 'F'
       order by fi.site_ref nulls first, fi.id limit 1;
    end if;
  elsif v_file_id is null then
    v_status := 'no_file';
  else
    select fi.* into v_item from hsf_file_item fi join hsf_element e on e.id = fi.element_id
     where fi.file_id = v_file_id and e.code = v_element and e.section_code = 'F'
     order by fi.site_ref nulls first, fi.id limit 1
     for update of fi;
    if v_item.id is null then
      v_status := 'section_only';
    else
      v_status := 'linked';
      select u.display_name into v_signer from bi_signature s join bi_app_user u on u.id = s.signer_user_id
       where s.report_id = v_r.id and s.report_version_id = v_r.issued_version_id order by s.signed_at desc limit 1;
      select coalesce(max(e.version), 0) + 1 into v_version from hsf_evidence e where e.file_item_id = v_item.id;
      select e.id into v_prev from hsf_evidence e where e.file_item_id = v_item.id order by e.version desc limit 1;
      -- The same append only evidence ledger a client upload writes (049),
      -- source engine_generated: the fingerprint is the Issued PDF's.
      insert into hsf_evidence (file_item_id, version, supersedes_id, source, storage_path, sha256, supplied_by, valid_from)
      values (v_item.id, v_version, v_prev, 'engine_generated', null, v_r.pdf_sha256,
              'Bee-Inspect report signed by ' || coalesce(v_signer, 'a competent person'), v_r.issued_at::date)
      returning id into v_ev;
      if v_item.status in ('outstanding','expired') then
        update hsf_file_item set status = 'uploaded', reason = null where id = v_item.id;
      end if;
      perform hsf_compute_compliance(v_file_id);
    end if;
  end if;

  insert into bi_report_file_link (report_id, client_account_id, file_id, file_item_id, element_code, evidence_id, status,
                                   eligibility_reason, eligibility)
  values (v_r.id, v_r.client_account_id, v_file_id, v_item.id, v_element, v_ev, v_status, v_reason, v_elig)
  on conflict (report_id) do update
     set file_id = excluded.file_id, file_item_id = excluded.file_item_id, element_code = excluded.element_code,
         evidence_id = excluded.evidence_id, status = excluded.status,
         eligibility_reason = excluded.eligibility_reason, eligibility = excluded.eligibility,
         attempts = bi_report_file_link.attempts + 1, synced_at = now();

  if v_status in ('linked','section_only') then
    update bi_report set section_f_synced_at = now() where id = v_r.id;
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('bee-inspect', 'bi_report_filed_section_f',
            jsonb_build_object('report_id', v_r.id, 'element_code', v_element, 'status', v_status,
                               'evidence_version', v_version, 'sha256', v_r.pdf_sha256, 'eligibility_reason', v_reason), v_file_id);
  elsif v_status = 'awaiting_eligibility' and v_file_id is not null
        and (v_link.status is distinct from 'awaiting_eligibility' or v_link.file_id is distinct from v_file_id) then
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('bee-inspect', 'bi_report_awaiting_eligibility',
            jsonb_build_object('report_id', v_r.id, 'element_code', v_element, 'sha256', v_r.pdf_sha256), v_file_id);
  end if;
  perform bi_audit(null, 'section_f_sync', v_r.tenant_id, v_r.client_account_id, 'report', v_r.id,
                   jsonb_build_object('status', v_status, 'file_id', v_file_id, 'element_code', v_element, 'eligibility_reason', v_reason));
  return jsonb_build_object('report_id', v_r.id, 'status', v_status, 'file_id', v_file_id, 'element_code', v_element,
                            'evidence_id', v_ev, 'eligibility', v_elig, 'already', false);
end;
$$;
comment on function bi_hsf_section_f_sync is 'BI-RPT-01, replaced by BI-DEC-01 (contract 16.8). Files an Issued report into the company''s current File when the company is eligible for the free digital Safety File for the report''s site (bi_free_file_eligible): a new hsf_evidence version (engine_generated, the PDF fingerprint, supplied by "Bee-Inspect report signed by <name>") on the Section F element its template maps to, the item set to uploaded when it was outstanding or expired, compliance recomputed and audited in msp_audit against the File (linked); section_only when the element is not on the File; no_file when there is no File yet. When the company is not eligible the link is stored as awaiting_eligibility: no evidence, no item change and no compliance change (the File audit notes it once). The eligibility answer is kept on the link. Idempotent. Runs automatically when a report becomes Issued.';

create or replace function bi_hsf_section_f_sync_pending(p_limit int default 25)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_out jsonb := '[]'::jsonb;
  v_waiting int;
begin
  for r in
    select b.id from bi_report b
      join bi_inspection i on i.id = b.inspection_id
      left join bi_report_file_link l on l.report_id = b.id
     where b.status = 'issued'
       and (l.report_id is null or l.status = 'no_file'
            or (l.status = 'awaiting_eligibility'
                and coalesce((bi_free_file_eligible(b.client_account_id, i.site_id) ->> 'eligible')::boolean, false)))
     order by b.issued_at limit greatest(1, least(coalesce(p_limit, 25), 200))
  loop
    v_out := v_out || jsonb_build_array(bi_hsf_section_f_sync(r.id));
  end loop;
  select count(*) into v_waiting from bi_report_file_link l join bi_report b on b.id = l.report_id
   where l.status = 'awaiting_eligibility' and b.status = 'issued';
  return jsonb_build_object('processed', jsonb_array_length(v_out), 'results', v_out, 'awaiting_eligibility', v_waiting);
end;
$$;
comment on function bi_hsf_section_f_sync_pending is 'BI-RPT-01, replaced by BI-DEC-01. For the hsf-section-f-sync Edge Function (hourly): files every Issued report not yet filed: no link, no File at the last attempt, or awaiting eligibility and now eligible (a report still not eligible is left as it is, so the run writes nothing for it). Returns how many were processed and how many still await eligibility. Service role only.';

create or replace function bi_section_f_reports(p_auth_user uuid, p_file_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'report_id', r.id, 'title', r.title, 'site', s.name, 'date', r.issued_at,
           'signed_by', (select u.display_name from bi_signature g join bi_app_user u on u.id = g.signer_user_id
                          where g.report_id = r.id and g.report_version_id = r.issued_version_id order by g.signed_at desc limit 1),
           'status', r.status, 'element_code', l.element_code, 'filing', l.status, 'eligibility_reason', l.eligibility_reason)
         order by r.issued_at desc), '[]'::jsonb)
    from bi_report_file_link l
    join bi_report r on r.id = l.report_id
    join bi_inspection i on i.id = r.inspection_id
    join bi_site s on s.id = i.site_id
   where l.file_id = p_file_id and l.status in ('linked','section_only','awaiting_eligibility')
     and hsf_can_access_file(p_auth_user, p_file_id);
$$;
comment on function bi_section_f_reports is 'BI-RPT-01 and BI-DEC-01 (prompt A3). The Section F "Inspection reports" list of a File for its owner or staff: title, site, date, signed by, status and filing (linked, section_only or awaiting_eligibility, which the page shows as awaiting eligibility for the free File). Service role only (the File site''s API calls it after verifying the user).';

-- 5. Step up windows and the dual gate ---------------------------------------------------------------

create function bi_step_up_window_minutes(p_channel text)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select case when p_channel = 'docuseal' then coalesce(msp_env_get_int('bi.step_up_docuseal_window_minutes'), 1440)
              else coalesce(msp_env_get_int('bi.step_up_window_minutes'), 10) end;
$$;
comment on function bi_step_up_window_minutes is 'BI-DEC-01 (decision 1.5). How long a step up MFA assertion stays valid: docuseal reads bi.step_up_docuseal_window_minutes (1 440, 24 hours); in_app and every other purpose read bi.step_up_window_minutes (10).';

create function bi_signer_gate(p_app_user_id uuid, p_company uuid, p_category text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_company boolean;
  v_kyc boolean;
  v_fica boolean;
  v_scope boolean;
  v_current boolean;
  v_missing text[] := '{}';
begin
  -- FICA and KYC: the company's onboarding is Active (Care Net reviewed its
  -- FICA pack), the signer passed the identity and liveness check and has an
  -- accepted FICA record of their own.
  v_company := exists (select 1 from bi_company c where c.client_account_id = p_company and c.onboarding_status = 'active');
  v_kyc := exists (select 1 from bi_inspector_profile ip where ip.app_user_id = p_app_user_id and ip.liveness_passed_at is not null);
  v_fica := exists (select 1 from bi_fica_record f where f.subject_kind = 'inspector' and f.app_user_id = p_app_user_id and f.status = 'accepted');
  -- Qualification: cleared for the template category with nothing expired,
  -- and at least one verified qualification or professional registration in date.
  v_scope := bi_signer_cleared(p_app_user_id, p_category);
  v_current := exists (select 1 from bi_inspector_qualification q
                        where q.app_user_id = p_app_user_id and q.status = 'verified'
                          and q.credential_kind in ('qualification','professional_registration')
                          and (q.expires_on is null or q.expires_on >= current_date));
  if not v_company then v_missing := v_missing || 'company_onboarding'::text; end if;
  if not v_kyc then v_missing := v_missing || 'kyc_liveness'::text; end if;
  if not v_fica then v_missing := v_missing || 'fica_record'::text; end if;
  if not v_scope then v_missing := v_missing || 'competence_scope'::text; end if;
  if not v_current then v_missing := v_missing || 'current_qualification'::text; end if;
  return jsonb_build_object('fica_kyc_cleared', v_company and v_kyc and v_fica,
                            'qualification_cleared', v_scope and v_current,
                            'ok', cardinality(v_missing) = 0,
                            'missing', to_jsonb(v_missing));
end;
$$;
comment on function bi_signer_gate is 'BI-DEC-01 (decision section 2, the dual gate before Issue). fica_kyc_cleared: the company''s onboarding is Active, the signer passed the identity and liveness check and holds an accepted FICA record. qualification_cleared: the signer is cleared for the template category with no expired qualification (bi_signer_cleared) and holds at least one verified qualification or professional registration that is in date. ok only when both are cleared; missing names what is not.';

create or replace function bi_report_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_sig bi_signature;
  v_step bi_step_up;
  v_insp bi_inspection;
  v_cat text;
  v_ver bi_report_version;
  v_counts jsonb;
  v_window int;
  v_gate jsonb;
begin
  if tg_op = 'DELETE' then
    raise exception 'Reports are withdrawn, never deleted';
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'draft' or new.issued_at is not null or new.issued_version_id is not null then
      raise exception 'A report starts as a draft';
    end if;
    select * into v_insp from bi_inspection where id = new.inspection_id;
    new.tenant_id := v_insp.tenant_id;
    new.client_account_id := v_insp.client_account_id;
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id or new.client_account_id is distinct from old.client_account_id
     or new.inspection_id is distinct from old.inspection_id then
    raise exception 'A report never moves to another inspection, tenant or company';
  end if;

  if old.status in ('issued','withdrawn') then
    -- An Issued report changes only by withdrawal, its Section F filing time and its share link.
    if (to_jsonb(new) - array['status','withdrawn_reason','section_f_synced_at','share_token_hash','share_expires_at','updated_at'])
       is distinct from (to_jsonb(old) - array['status','withdrawn_reason','section_f_synced_at','share_token_hash','share_expires_at','updated_at']) then
      raise exception 'An Issued report is never edited';
    end if;
    if new.status is distinct from old.status and not (old.status = 'issued' and new.status = 'withdrawn'
         and length(btrim(coalesce(new.withdrawn_reason, ''))) >= 10) then
      raise exception 'An Issued report can only be withdrawn, with a reason';
    end if;
    return new;
  end if;

  if new.status = 'withdrawn' then
    raise exception 'Only an Issued report is withdrawn';
  end if;
  if new.status = 'awaiting_signoff' and old.status = 'draft' and new.current_version_id is null then
    raise exception 'A report needs a version before sign off';
  end if;
  if new.status in ('draft','awaiting_signoff') then
    if new.issued_at is not null or new.issued_version_id is not null then
      raise exception 'Only an Issued report carries an issue date';
    end if;
    return new;
  end if;

  -- new.status = 'issued'
  if old.status <> 'awaiting_signoff' then
    raise exception 'A report is Issued only from Awaiting sign off';
  end if;
  select * into v_ver from bi_report_version where id = new.current_version_id and report_id = new.id;
  if v_ver.id is null then
    raise exception 'Issued refused: the report has no current version';
  end if;
  select s.* into v_sig from bi_signature s
   where s.report_id = new.id and s.report_version_id = v_ver.id
   order by s.signed_at desc limit 1;
  if v_sig.id is null then
    raise exception 'Issued refused: no competent person has signed this version. Unsigned reports stay Draft or Awaiting sign off.'
      using errcode = '42501';
  end if;
  select * into v_insp from bi_inspection where id = new.inspection_id;
  select t.category into v_cat from bi_template t where t.id = v_insp.template_id;
  if not bi_signer_cleared(v_sig.signer_user_id, v_cat) then
    raise exception 'Issued refused: the signer is not a cleared competent person for %', v_cat using errcode = '42501';
  end if;
  -- The dual gate (decision section 2): FICA and KYC cleared and a qualification cleared.
  v_gate := bi_signer_gate(v_sig.signer_user_id, new.client_account_id, v_cat);
  if not coalesce((v_gate ->> 'ok')::boolean, false) then
    raise exception 'Issued refused: FICA and KYC and a current qualification must both be cleared first (missing: %)',
      array_to_string(array(select jsonb_array_elements_text(v_gate -> 'missing')), ', ') using errcode = '42501';
  end if;
  select * into v_step from bi_step_up where id = v_sig.step_up_id;
  v_window := bi_step_up_window_minutes(v_sig.channel);
  if v_step.id is null or v_step.purpose <> 'signoff' or v_step.aal <> 'aal2'
     or v_step.auth_user_id <> (select u.auth_user_id from bi_app_user u where u.id = v_sig.signer_user_id)
     or v_step.asserted_at > v_sig.signed_at + interval '1 minute'
     or v_step.asserted_at < v_sig.signed_at - make_interval(mins => v_window) then
    raise exception 'Issued refused: the signature has no valid step up MFA assertion' using errcode = '42501';
  end if;
  if jsonb_array_length(bi_report_claim_problems(v_ver.content)) > 0 then
    raise exception 'Issued refused: every legal claim must carry a kernel reference';
  end if;
  v_counts := bi_report_voice_counts(new.inspection_id, v_ver.content);
  if v_insp.voice_note_policy = 'strict' and (v_counts ->> 'missing')::int > 0 then
    raise exception 'Issued refused: % voice note(s) missing from the report (strict policy)', v_counts ->> 'missing';
  end if;
  if v_insp.status not in ('submitted','closed') then
    raise exception 'Issued refused: the inspection is not submitted';
  end if;
  if new.pdf_path is null or new.pdf_sha256 is null or new.json_path is null then
    raise exception 'Issued refused: the PDF and JSON must be stored first';
  end if;
  new.issued_version_id := v_ver.id;
  new.issued_at := coalesce(new.issued_at, now());
  return new;
end;
$$;
comment on function bi_report_guard is 'BI-RPT-01, replaced by BI-DEC-01. The Issued guard. Insert only as a draft. Issued only from Awaiting sign off with: a signature on the current version by a cleared inspector whose scope covers the template category and with no expired qualification; the dual gate cleared (bi_signer_gate: FICA and KYC, and a current qualification); a step up MFA assertion (purpose signoff, aal2, same person) at most bi_step_up_window_minutes before signing (bi.step_up_window_minutes, 10, in the app; bi.step_up_docuseal_window_minutes, 1 440, for DocuSeal); every claim cited from a released kernel; under the strict policy no voice note missing; a submitted inspection; the PDF and JSON stored. An Issued report is never edited; it may only be withdrawn with a reason.';

create or replace function bi_report_sign(p_auth_user uuid, p_report_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r bi_report;
  v_me bi_app_user;
  v_step bi_step_up;
  v_role text;
  v_cat text;
  v_channel text := coalesce(p ->> 'channel', 'in_app');
  v_integrity text := coalesce(p ->> 'device_integrity', 'unknown');
  v_window int;
  v_gate jsonb;
  v_id uuid;
begin
  select * into v_r from bi_report where id = p_report_id for update;
  v_me := bi_app_user_of(p_auth_user);
  if v_r.id is null or v_me.id is null then
    raise exception 'That report was not found.' using errcode = 'P0002';
  end if;
  if v_r.reviewer_user_id = v_me.id then
    v_role := 'reviewer';
  elsif 'inspector' = any(bi_user_roles(p_auth_user, v_r.tenant_id, v_r.client_account_id)) then
    v_role := 'inspector';
  else
    raise exception 'That report was not found.' using errcode = 'P0002';
  end if;
  if v_r.status <> 'awaiting_signoff' then
    raise exception 'Only a report Awaiting sign off is signed.';
  end if;
  if v_integrity = 'compromised' then
    raise exception 'This device looks rooted or jailbroken, so it cannot sign. Please sign on another device.' using errcode = '42501';
  end if;
  if coalesce((p ->> 'confirm_photos')::boolean, false) is false or coalesce((p ->> 'confirm_voice_notes')::boolean, false) is false then
    raise exception 'Confirm that you reviewed the photos and the voice notes before signing.';
  end if;
  select t.category into v_cat from bi_inspection i join bi_template t on t.id = i.template_id where i.id = v_r.inspection_id;
  if not bi_signer_cleared(v_me.id, v_cat) then
    raise exception 'You are not cleared to sign % reports. Find a competent person through Bee-Matched.', v_cat using errcode = '42501';
  end if;
  v_gate := bi_signer_gate(v_me.id, v_r.client_account_id, v_cat);
  if not coalesce((v_gate ->> 'ok')::boolean, false) then
    raise exception 'Care Net must clear your FICA and KYC and a current qualification before you sign (missing: %).',
      array_to_string(array(select jsonb_array_elements_text(v_gate -> 'missing')), ', ') using errcode = '42501';
  end if;
  select * into v_step from bi_step_up where id = nullif(p ->> 'step_up_id', '')::uuid for update;
  v_window := bi_step_up_window_minutes(v_channel);
  if v_step.id is null or v_step.auth_user_id <> p_auth_user or v_step.purpose <> 'signoff' or v_step.consumed_at is not null
     or v_step.asserted_at < now() - make_interval(mins => v_window) then
    raise exception 'Verify your second factor again before signing.' using errcode = '28000';
  end if;
  update bi_step_up set consumed_at = now() where id = v_step.id;
  insert into bi_signature (report_id, report_version_id, signer_user_id, signer_role, channel, docuseal_submission_ref, step_up_id,
                            device_integrity, confirmed_photos, confirmed_voice_notes, qualification_ids)
  values (v_r.id, v_r.current_version_id, v_me.id, v_role, v_channel, nullif(p ->> 'docuseal_submission_ref', ''), v_step.id,
          v_integrity, true, true,
          coalesce((select array_agg(q.id) from bi_inspector_qualification q where q.app_user_id = v_me.id and q.status = 'verified'), '{}'))
  returning id into v_id;
  perform bi_audit(p_auth_user, 'report_signed', v_r.tenant_id, v_r.client_account_id, 'report', v_r.id,
                   jsonb_build_object('signature_id', v_id, 'role', v_role, 'channel', v_channel, 'version_id', v_r.current_version_id,
                                      'step_up_window_minutes', v_window));
  return jsonb_build_object('report_id', v_r.id, 'signature_id', v_id, 'status', v_r.status);
end;
$$;
comment on function bi_report_sign is 'BI-RPT-01, replaced by BI-DEC-01 (decision 1.5 and the dual gate). Records a competent person''s signature on the current version of a report Awaiting sign off: the company''s inspector or the engaged reviewer, cleared for the template category, with the dual gate cleared (bi_signer_gate), on a device that is not rooted or jailbroken, having confirmed the photos and voice notes, with an unconsumed step up assertion (purpose signoff) recorded within bi.step_up_window_minutes in the app (10) or bi.step_up_docuseal_window_minutes through DocuSeal (1 440, 24 hours), which it consumes. Does not issue: issuing needs the PDF (bi_report_issue). Audited.';

-- 6. Accounts and settings: authorised persons, credentials, consents ------------------------------------

alter table bi_inspector_qualification add column credential_kind text not null default 'qualification'
  check (credential_kind in ('qualification','professional_registration','licence','accreditation'));
comment on column bi_inspector_qualification.credential_kind is 'BI-DEC-01 (decision section 2). qualification, professional_registration (for example SACPCMP or SAIOSH registration), licence or accreditation. document_path is the certificate upload (private bucket bi-credentials) and expires_on its expiry.';

create table bi_authorised_person (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  full_name text not null check (length(btrim(full_name)) between 2 and 200),
  role text not null check (role in ('s16_1','s16_2','hs_manager','hs_officer','hs_representative','hs_committee_member',
    'construction_manager','construction_supervisor','construction_hs_officer','first_aider','fire_marshal',
    'incident_investigator','risk_assessor','competent_person','other')),
  role_title text check (role_title is null or length(btrim(role_title)) between 2 and 200),
  app_user_id uuid references bi_app_user(id),
  email text check (email is null or email ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  mobile_e164 text check (mobile_e164 is null or mobile_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  appointment_letter_path text check (appointment_letter_path is null or appointment_letter_path ~ '^[0-9a-f-]{36}/appointments/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$'),
  appointed_on date,
  ended_on date,
  status text not null default 'active' check (status in ('active','ended')),
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  constraint bi_authorised_person_dates check (ended_on is null or appointed_on is null or ended_on >= appointed_on),
  constraint bi_authorised_person_ended check (status <> 'ended' or ended_on is not null),
  constraint bi_authorised_person_other_title check (role <> 'other' or role_title is not null)
);
comment on table bi_authorised_person is 'BI-DEC-01 (decision section 2, advanced H&S settings). The authorised persons of a company, as many as it has, one row per appointment: s16_1 (the chief executive officer under section 16(1) of the OHS Act, one live per company), s16_2 (a person designated under section 16(2)), and the H&S roles: hs_manager, hs_officer, hs_representative (section 17), hs_committee_member (section 19), construction_manager, construction_supervisor and construction_hs_officer (Construction Regulations), first_aider, fire_marshal, incident_investigator, risk_assessor, competent_person, other (with role_title). app_user_id links the person when they use Bee-Inspect. The appointment letter is a path in the private bucket bi-credentials. Ended, never deleted. Written only by bi_authorised_person_save.';
create unique index bi_authorised_person_one_ceo_idx on bi_authorised_person(client_account_id) where role = 's16_1' and status = 'active';
create index bi_authorised_person_company_idx on bi_authorised_person(client_account_id, status);
create trigger bi_authorised_person_touch before update on bi_authorised_person for each row execute function bi_touch();
create trigger bi_authorised_person_no_delete before delete on bi_authorised_person for each row execute function bi_no_delete();

create table bi_person_credential (
  id uuid primary key default gen_random_uuid(),
  authorised_person_id uuid not null references bi_authorised_person(id),
  client_account_id uuid not null references msp_client_account(id),
  credential_kind text not null check (credential_kind in ('qualification','professional_registration','licence','certificate','accreditation')),
  title text not null check (length(btrim(title)) between 2 and 200),
  issuer text not null check (length(btrim(issuer)) between 2 and 200),
  number text check (number is null or length(btrim(number)) between 1 and 80),
  issued_on date,
  expires_on date,
  certificate_path text check (certificate_path is null or certificate_path ~ '^[0-9a-f-]{36}/credentials/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$'),
  certificate_sha256 text check (certificate_sha256 is null or certificate_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null default 'pending' check (status in ('pending','verified','rejected','expired')),
  verified_by text,
  verified_at timestamptz,
  review_note text,
  alert_60_at timestamptz,
  alert_30_at timestamptz,
  alert_7_at timestamptz,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  check (expires_on is null or issued_on is null or expires_on > issued_on),
  check (status <> 'verified' or (verified_by is not null and verified_at is not null))
);
comment on table bi_person_credential is 'BI-DEC-01 (decision section 2). A qualification, professional registration, licence, certificate or accreditation of an authorised person: title, issuer or registering body, number, issue and expiry dates, and the certificate upload by path and fingerprint only (private bucket bi-credentials, path <client_account_id>/credentials/<credential id>/<file>). pending until Care Net verifies it; expired by the expiry run, with alerts at 60, 30 and 7 days. Every read by a person is audited (bi_person_credential_list); no policy lets a client read the table directly.';
create index bi_person_credential_person_idx on bi_person_credential(authorised_person_id);
create trigger bi_person_credential_touch before update on bi_person_credential for each row execute function bi_touch();
create trigger bi_person_credential_no_delete before delete on bi_person_credential for each row execute function bi_no_delete();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('bi-credentials', 'bi-credentials', false, 10485760, array['application/pdf','image/jpeg','image/png'])
on conflict (id) do nothing;

create function bi_safe_file_name(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select left(coalesce(nullif(regexp_replace(regexp_replace(coalesce(p_name, ''), '[^A-Za-z0-9._]+', '_', 'g'), '^[._]+', ''), ''), 'document'), 120);
$$;
comment on function bi_safe_file_name is 'BI-DEC-01. A file name reduced to letters, digits, dot and underscore (at most 120 characters), as hsf_register_upload does for the File.';

create function bi_manages_company(p_auth_user uuid, p_company uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select bi_user_is_ops(p_auth_user)
      or 'company_admin' = any(bi_user_roles(p_auth_user, (bi_app_user_of(p_auth_user)).tenant_id, p_company));
$$;
comment on function bi_manages_company is 'BI-DEC-01. Care Net ops, or the company admin of the company in their own tenant.';

create function bi_authorised_person_save(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid := nullif(p ->> 'client_account_id', '')::uuid;
  v_id uuid := nullif(p ->> 'id', '')::uuid;
  v_old bi_authorised_person;
  v_by text := coalesce(hsf_user_email(p_auth_user), 'service_role');
  v_letter text;
begin
  if v_company is null or not (p_auth_user is null or bi_manages_company(p_auth_user, v_company)) then
    raise exception 'Not permitted.' using errcode = '42501';
  end if;
  if nullif(p ->> 'app_user_id', '') is not null
     and not exists (select 1 from bi_app_user u where u.id = (p ->> 'app_user_id')::uuid and u.status = 'active') then
    raise exception 'That Bee-Inspect user was not found.' using errcode = 'P0002';
  end if;
  if v_id is null then
    v_id := gen_random_uuid();
  else
    select * into v_old from bi_authorised_person where id = v_id and client_account_id = v_company for update;
    if v_old.id is null then
      raise exception 'That authorised person was not found.' using errcode = 'P0002';
    end if;
  end if;
  if nullif(p ->> 'appointment_letter_name', '') is not null then
    v_letter := v_company || '/appointments/' || v_id || '/' || bi_safe_file_name(p ->> 'appointment_letter_name');
  end if;
  begin
    if v_old.id is null then
      insert into bi_authorised_person (id, client_account_id, full_name, role, role_title, app_user_id, email, mobile_e164,
                                        appointment_letter_path, appointed_on, created_by)
      values (v_id, v_company, btrim(p ->> 'full_name'), p ->> 'role', nullif(btrim(coalesce(p ->> 'role_title', '')), ''),
              nullif(p ->> 'app_user_id', '')::uuid, nullif(lower(btrim(coalesce(p ->> 'email', ''))), ''), nullif(p ->> 'mobile_e164', ''),
              v_letter, nullif(p ->> 'appointed_on', '')::date, v_by);
    else
      update bi_authorised_person
         set full_name = coalesce(nullif(btrim(coalesce(p ->> 'full_name', '')), ''), full_name),
             role_title = case when p ? 'role_title' then nullif(btrim(coalesce(p ->> 'role_title', '')), '') else role_title end,
             app_user_id = case when p ? 'app_user_id' then nullif(p ->> 'app_user_id', '')::uuid else app_user_id end,
             email = case when p ? 'email' then nullif(lower(btrim(coalesce(p ->> 'email', ''))), '') else email end,
             mobile_e164 = case when p ? 'mobile_e164' then nullif(p ->> 'mobile_e164', '') else mobile_e164 end,
             appointment_letter_path = coalesce(v_letter, appointment_letter_path),
             appointed_on = case when p ? 'appointed_on' then nullif(p ->> 'appointed_on', '')::date else appointed_on end,
             ended_on = case when p ->> 'status' = 'ended' then coalesce(nullif(p ->> 'ended_on', '')::date, current_date) else ended_on end,
             status = case when p ->> 'status' = 'ended' then 'ended' else status end
       where id = v_id;
    end if;
  exception when unique_violation then
    raise exception 'This company already has a live section 16(1) person. End that appointment first.' using errcode = '23505';
  end;
  perform bi_audit(p_auth_user, 'authorised_person_saved', null, v_company, 'authorised_person', v_id,
                   jsonb_build_object('role', coalesce(p ->> 'role', v_old.role), 'new', v_old.id is null, 'status', coalesce(p ->> 'status', 'active')));
  return jsonb_build_object('authorised_person_id', v_id, 'appointment_letter_bucket', case when v_letter is not null then 'bi-credentials' end,
                            'appointment_letter_path', v_letter);
end;
$$;
comment on function bi_authorised_person_save is 'BI-DEC-01 (decision section 2). Adds or edits an authorised person of a company: p = {client_account_id, id? (edit), full_name, role, role_title?, app_user_id?, email?, mobile_e164?, appointed_on?, appointment_letter_name? (returns the upload path in bi-credentials), status? (ended, with ended_on)}. The role of an appointment never changes (end it and add a new one). Company admin of the company or Care Net ops (or the service role). Audited. Service role only.';

create function bi_person_credential_save(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_person bi_authorised_person;
  v_id uuid := gen_random_uuid();
  v_path text;
begin
  select * into v_person from bi_authorised_person where id = nullif(p ->> 'authorised_person_id', '')::uuid;
  if v_person.id is null or not (p_auth_user is null or bi_manages_company(p_auth_user, v_person.client_account_id)) then
    raise exception 'That authorised person was not found.' using errcode = 'P0002';
  end if;
  if nullif(p ->> 'certificate_name', '') is not null then
    v_path := v_person.client_account_id || '/credentials/' || v_id || '/' || bi_safe_file_name(p ->> 'certificate_name');
  end if;
  insert into bi_person_credential (id, authorised_person_id, client_account_id, credential_kind, title, issuer, number,
                                    issued_on, expires_on, certificate_path, certificate_sha256, created_by)
  values (v_id, v_person.id, v_person.client_account_id, p ->> 'credential_kind', btrim(p ->> 'title'), btrim(p ->> 'issuer'),
          nullif(btrim(coalesce(p ->> 'number', '')), ''), nullif(p ->> 'issued_on', '')::date, nullif(p ->> 'expires_on', '')::date,
          v_path, nullif(p ->> 'certificate_sha256', ''), coalesce(hsf_user_email(p_auth_user), 'service_role'));
  perform bi_audit(p_auth_user, 'credential_added', null, v_person.client_account_id, 'person_credential', v_id,
                   jsonb_build_object('authorised_person_id', v_person.id, 'kind', p ->> 'credential_kind'));
  return jsonb_build_object('credential_id', v_id, 'status', 'pending', 'certificate_bucket', case when v_path is not null then 'bi-credentials' end,
                            'certificate_path', v_path);
end;
$$;
comment on function bi_person_credential_save is 'BI-DEC-01 (decision section 2). Adds a qualification, professional registration, licence, certificate or accreditation of an authorised person, status pending: p = {authorised_person_id, credential_kind, title, issuer, number?, issued_on?, expires_on?, certificate_name? (returns the upload path in bi-credentials), certificate_sha256?}. A renewed certificate is a new row. Company admin or Care Net ops. Audited. Service role only.';

create function bi_credential_verify(p_auth_user uuid, p_kind text, p_id uuid, p_status text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_by text;
  v_company uuid;
begin
  if not (p_auth_user is null or bi_user_is_ops(p_auth_user)) then
    raise exception 'Only Care Net verifies a qualification or registration.' using errcode = '42501';
  end if;
  if p_status not in ('verified','rejected') then
    raise exception 'The outcome is verified or rejected.' using errcode = '22023';
  end if;
  v_by := coalesce(hsf_user_email(p_auth_user), 'service_role');
  if p_kind = 'authorised_person' then
    update bi_person_credential set status = p_status, verified_by = case when p_status = 'verified' then v_by end,
           verified_at = case when p_status = 'verified' then now() end, review_note = p_note
     where id = p_id and status in ('pending','verified','rejected')
    returning client_account_id into v_company;
  elsif p_kind = 'inspector' then
    update bi_inspector_qualification set status = p_status, verified_by = case when p_status = 'verified' then v_by end,
           verified_at = case when p_status = 'verified' then now() end
     where id = p_id and status in ('pending','verified','rejected');
  else
    raise exception 'The credential kind is authorised_person or inspector.' using errcode = '22023';
  end if;
  if not found then
    raise exception 'That credential was not found.' using errcode = 'P0002';
  end if;
  perform bi_audit(p_auth_user, 'credential_' || p_status, null, v_company, p_kind || '_credential', p_id, jsonb_build_object('note', p_note));
  return jsonb_build_object('credential_id', p_id, 'status', p_status);
end;
$$;
comment on function bi_credential_verify is 'BI-DEC-01. Care Net ops (or the service role) verifies or rejects an authorised person''s credential (p_kind authorised_person) or an inspector''s qualification or registration (p_kind inspector). An expired credential is renewed as a new row. Audited. Service role only.';

create function bi_person_credential_list(p_auth_user uuid, p_company uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ops boolean := bi_user_is_ops(p_auth_user);
  v_rows jsonb;
begin
  if not bi_manages_company(p_auth_user, p_company) then
    raise exception 'Not permitted.' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'authorised_person_id', c.authorised_person_id, 'person', ap.full_name,
           'role', ap.role, 'credential_kind', c.credential_kind, 'title', c.title, 'issuer', c.issuer, 'number', c.number,
           'issued_on', c.issued_on, 'expires_on', c.expires_on, 'certificate_path', c.certificate_path, 'status', c.status)
           order by ap.full_name, c.expires_on nulls last), '[]'::jsonb)
    into v_rows
    from bi_person_credential c join bi_authorised_person ap on ap.id = c.authorised_person_id
   where c.client_account_id = p_company;
  insert into bi_audit_log (actor_auth_user, actor_label, client_account_id, event, object_kind, object_id, detail)
  select p_auth_user, coalesce((select email from auth.users where id = p_auth_user), 'user'), p_company,
         'credential_read', 'person_credential', c.id, jsonb_build_object('as_ops', v_ops)
    from bi_person_credential c where c.client_account_id = p_company;
  return v_rows;
end;
$$;
comment on function bi_person_credential_list is 'BI-DEC-01 (prompt section 8 applied to authorised persons). The only read path to authorised persons'' credentials for a person: the company admin of the company or Care Net ops. Each record returned is audited as credential_read. Service role only.';

create function bi_person_credential_expiry_run(p_today date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alerts jsonb;
  v_expired jsonb;
begin
  with due as (
    select c.id, c.authorised_person_id, c.client_account_id, c.title, c.expires_on, (c.expires_on - p_today) as days,
           case when c.expires_on - p_today <= 7 and c.alert_7_at is null then 7
                when c.expires_on - p_today <= 30 and c.alert_30_at is null then 30
                when c.expires_on - p_today <= 60 and c.alert_60_at is null then 60 end as threshold
      from bi_person_credential c
     where c.status = 'verified' and c.expires_on is not null and c.expires_on >= p_today and c.expires_on - p_today <= 60),
  marked as (
    update bi_person_credential c
       set alert_60_at = coalesce(c.alert_60_at, now()),
           alert_30_at = case when d.threshold <= 30 then coalesce(c.alert_30_at, now()) else c.alert_30_at end,
           alert_7_at = case when d.threshold <= 7 then coalesce(c.alert_7_at, now()) else c.alert_7_at end
      from due d where d.id = c.id and d.threshold is not null
    returning c.id, c.authorised_person_id, c.client_account_id, d.title, d.expires_on, d.days, d.threshold)
  select coalesce(jsonb_agg(to_jsonb(marked) order by expires_on), '[]'::jsonb) into v_alerts from marked;

  with gone as (
    update bi_person_credential c set status = 'expired'
     where c.status = 'verified' and c.expires_on < p_today
    returning c.id, c.authorised_person_id, c.client_account_id, c.title, c.expires_on)
  select coalesce(jsonb_agg(to_jsonb(gone)), '[]'::jsonb) into v_expired from gone;
  return jsonb_build_object('alerts', v_alerts, 'expired', v_expired);
end;
$$;
comment on function bi_person_credential_expiry_run is 'BI-DEC-01. Authorised persons'' credentials: alerts at 60, 30 and 7 days before expiry (each once) and lapsed credentials marked expired. Called by bi_qualification_expiry_run. Service role only.';

create or replace function bi_qualification_expiry_run(p_today date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alerts jsonb;
  v_expired jsonb;
  v_restricted jsonb;
  v_credentials jsonb;
begin
  -- Alerts at 60, 30 and 7 days before expiry, each sent once.
  with due as (
    select q.id, q.app_user_id, q.qual_type, q.expires_on, (q.expires_on - p_today) as days,
           case when q.expires_on - p_today <= 7 and q.alert_7_at is null then 7
                when q.expires_on - p_today <= 30 and q.alert_30_at is null then 30
                when q.expires_on - p_today <= 60 and q.alert_60_at is null then 60 end as threshold
      from bi_inspector_qualification q
     where q.status = 'verified' and q.expires_on is not null and q.expires_on >= p_today and q.expires_on - p_today <= 60),
  marked as (
    update bi_inspector_qualification q
       set alert_60_at = coalesce(q.alert_60_at, now()),
           alert_30_at = case when d.threshold <= 30 then coalesce(q.alert_30_at, now()) else q.alert_30_at end,
           alert_7_at = case when d.threshold <= 7 then coalesce(q.alert_7_at, now()) else q.alert_7_at end
      from due d where d.id = q.id and d.threshold is not null
    returning q.id, q.app_user_id, d.qual_type, d.expires_on, d.days, d.threshold)
  select coalesce(jsonb_agg(to_jsonb(marked) order by expires_on), '[]'::jsonb) into v_alerts from marked;

  -- Expired: the qualification is marked expired and a cleared inspector becomes restricted.
  with gone as (
    update bi_inspector_qualification q set status = 'expired'
     where q.status = 'verified' and q.expires_on < p_today
    returning q.id, q.app_user_id, q.qual_type, q.expires_on)
  select coalesce(jsonb_agg(to_jsonb(gone)), '[]'::jsonb) into v_expired from gone;

  with r as (
    update bi_inspector_profile p
       set status = 'restricted',
           restricted_reason = 'A qualification expired: ' || (select string_agg(q.qual_type || ' on ' || to_char(q.expires_on, 'DD/MM/YYYY'), ', ')
                                                               from bi_inspector_qualification q
                                                              where q.app_user_id = p.app_user_id and q.status = 'expired')
     where p.status = 'cleared'
       and exists (select 1 from bi_inspector_qualification q where q.app_user_id = p.app_user_id and q.status = 'expired')
    returning p.app_user_id)
  select coalesce(jsonb_agg(r.app_user_id), '[]'::jsonb) into v_restricted from r;

  v_credentials := bi_person_credential_expiry_run(p_today);

  if jsonb_array_length(v_alerts) + jsonb_array_length(v_expired) + jsonb_array_length(v_restricted)
     + jsonb_array_length(v_credentials -> 'alerts') + jsonb_array_length(v_credentials -> 'expired') > 0 then
    perform bi_audit(null, 'qualification_expiry_run', null, null, 'inspector_qualification', null,
                     jsonb_build_object('alerts', jsonb_array_length(v_alerts), 'expired', jsonb_array_length(v_expired),
                                        'restricted', v_restricted,
                                        'credential_alerts', jsonb_array_length(v_credentials -> 'alerts'),
                                        'credentials_expired', jsonb_array_length(v_credentials -> 'expired')));
  end if;
  return jsonb_build_object('alerts', v_alerts, 'expired', v_expired, 'restricted', v_restricted, 'credentials', v_credentials);
end;
$$;
comment on function bi_qualification_expiry_run is 'BI-OPS-01, replaced by BI-DEC-01 (prompt B4, qualification-expiry cron). Marks and returns the 60, 30 and 7 day alerts (each once), marks lapsed qualifications expired and makes a cleared inspector with an expired qualification restricted, with the reason; now also runs the authorised persons'' credentials (key credentials). Audited as a system run. Service role only.';

create or replace function bi_qualification_list(p_auth_user uuid, p_app_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me bi_app_user;
  v_ops boolean := bi_user_is_ops(p_auth_user);
  v_rows jsonb;
begin
  v_me := bi_app_user_of(p_auth_user);
  if not v_ops and (v_me.id is null or v_me.id <> p_app_user_id) then
    raise exception 'Not permitted.' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'qual_type', q.qual_type, 'credential_kind', q.credential_kind,
           'issuer', q.issuer, 'number', q.number, 'issued_on', q.issued_on, 'expires_on', q.expires_on, 'status', q.status,
           'document_path', q.document_path)
           order by q.expires_on nulls last), '[]'::jsonb)
    into v_rows
    from bi_inspector_qualification q where q.app_user_id = p_app_user_id;
  insert into bi_audit_log (actor_auth_user, actor_label, tenant_id, event, object_kind, object_id, detail)
  select p_auth_user, coalesce((select email from auth.users where id = p_auth_user), 'user'), v_me.tenant_id,
         'qualification_read', 'inspector_qualification', q.id, jsonb_build_object('as_ops', v_ops)
    from bi_inspector_qualification q where q.app_user_id = p_app_user_id;
  return v_rows;
end;
$$;
comment on function bi_qualification_list is 'BI-CORE-01, replaced by BI-DEC-01 (adds credential_kind). The only read path to qualifications and professional registrations for a person: ops or the inspector themself. Each record returned is audited as qualification_read.';

create table bi_consent_purpose (
  code text primary key,
  label text not null,
  description text not null,
  ordinal int not null unique check (ordinal >= 1),
  default_state text not null default 'not_given' check (default_state = 'not_given'),
  needs_double_opt_in boolean not null default false
);
comment on table bi_consent_purpose is 'BI-DEC-01 (decision section 2, POPIA consents as purpose chips). One row per purpose a person decides on, in the order the app shows them. Every purpose starts Not given (default_state is always not_given): nothing is pre ticked, and no decision means Not given. The codes are exactly the consent kinds of bi_consent_record. Wording versions are still to be written.';

insert into bi_consent_purpose (code, label, description, ordinal, needs_double_opt_in) values
  ('terms', 'Terms of use', 'Using Bee-Inspect under its terms.', 1, false),
  ('privacy', 'Privacy notice', 'How Care Net processes your information under POPIA.', 2, false),
  ('location', 'Location on evidence', 'Recording where a photo or voice note was taken.', 3, false),
  ('voice_recording', 'Voice notes', 'Recording and transcribing voice notes about the workplace.', 4, false),
  ('identifiable_people', 'People in photos', 'Photos in which a person can be recognised.', 5, false),
  ('fica_processing', 'FICA and identity checks', 'Processing FICA documents and identity checks.', 6, false),
  ('marketing', 'Marketing messages', 'News and offers from Care Net. Needs a second confirmation.', 7, true);

create function bi_consent_status(p_auth_user uuid, p_company uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', cp.code, 'label', cp.label, 'needs_double_opt_in', cp.needs_double_opt_in,
           'state', case when d.id is null or not d.granted then 'not_given'
                         when d.withdrawn_at is not null then 'withdrawn'
                         else 'given' end,
           'wording_version', d.wording_version, 'decided_at', d.granted_at, 'withdrawn_at', d.withdrawn_at)
         order by cp.ordinal), '[]'::jsonb)
    from bi_consent_purpose cp
    left join lateral (
      select c.* from bi_consent_record c
       where c.auth_user_id = p_auth_user and c.consent_kind = cp.code
         and (p_company is null or c.client_account_id is null or c.client_account_id = p_company)
       order by c.granted_at desc, c.id desc limit 1) d on true;
$$;
comment on function bi_consent_status is 'BI-DEC-01 (decision section 2). Every consent purpose for a person (and company, when given) with its state: not_given (the default: no decision, or a decision not to give it), given, or withdrawn. Service role only.';

create function bi_consent_decide(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind text := p ->> 'kind';
  v_granted boolean;
  v_company uuid := nullif(p ->> 'client_account_id', '')::uuid;
  v_confirmed boolean := coalesce((p ->> 'confirmed')::boolean, false);
  v_id uuid;
begin
  if p_auth_user is null or not exists (select 1 from auth.users where id = p_auth_user) then
    raise exception 'Sign in first.' using errcode = '28000';
  end if;
  if v_kind is null or not exists (select 1 from bi_consent_purpose where code = v_kind) then
    raise exception 'Unknown consent purpose.' using errcode = '22023';
  end if;
  begin
    v_granted := (p ->> 'granted')::boolean;
  exception when others then
    v_granted := null;
  end;
  if v_granted is null then
    raise exception 'granted must be true or false.' using errcode = '22023';
  end if;
  if v_company is not null and v_company is distinct from (hsf_account_of(p_auth_user)).id
     and cardinality(bi_user_roles(p_auth_user, (bi_app_user_of(p_auth_user)).tenant_id, v_company)) = 0 then
    raise exception 'Not permitted.' using errcode = '42501';
  end if;
  if v_kind = 'marketing' and v_granted and not v_confirmed then
    raise exception 'Marketing needs the second confirmation (double opt in) before it is given.' using errcode = '22023';
  end if;
  insert into bi_consent_record (auth_user_id, client_account_id, consent_kind, granted, wording_version, confirmed_at)
  values (p_auth_user, v_company, v_kind, v_granted, p ->> 'wording_version',
          case when v_kind = 'marketing' and v_granted then now() end)
  returning id into v_id;
  perform bi_audit(p_auth_user, 'consent_decided', (bi_app_user_of(p_auth_user)).tenant_id, v_company, 'consent_record', v_id,
                   jsonb_build_object('kind', v_kind, 'granted', v_granted, 'wording_version', p ->> 'wording_version'));
  return bi_consent_status(p_auth_user, v_company);
end;
$$;
comment on function bi_consent_decide is 'BI-DEC-01 (decision section 2). Records one consent decision by a person: p = {kind, granted, wording_version (BI-<NAME>-<n.n>), client_account_id? (their File company or a company they hold a role on), confirmed? (marketing: the double opt in)}. Returns every purpose''s state. Audited. Service role only.';

create function bi_consent_withdraw(p_auth_user uuid, p_kind text, p_company uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select c.id into v_id from bi_consent_record c
   where c.auth_user_id = p_auth_user and c.consent_kind = p_kind and c.granted and c.withdrawn_at is null
     and (p_company is null or c.client_account_id is null or c.client_account_id = p_company)
   order by c.granted_at desc, c.id desc limit 1
   for update;
  if v_id is null then
    raise exception 'There is no given consent to withdraw.' using errcode = 'P0002';
  end if;
  update bi_consent_record set withdrawn_at = now() where id = v_id;
  perform bi_audit(p_auth_user, 'consent_withdrawn', (bi_app_user_of(p_auth_user)).tenant_id, p_company, 'consent_record', v_id,
                   jsonb_build_object('kind', p_kind));
  return bi_consent_status(p_auth_user, p_company);
end;
$$;
comment on function bi_consent_withdraw is 'BI-DEC-01. Withdraws the latest given consent of a purpose. Audited. Service role only.';

-- 7. AI Wallet: subsidy ledger, charge and estimate ----------------------------------------------------

create table bi_subsidy_ledger (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  reason text not null check (reason in ('balance_exhausted','estimate_cap')),
  job_id uuid not null references bi_usage_event(id),
  job_kind text not null,
  report_id uuid references bi_report(id),
  inspection_id uuid references bi_inspection(id),
  wallet_id uuid not null references bi_wallet(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  user_id uuid references auth.users(id),
  estimate_cents bigint not null check (estimate_cents >= 0),
  actual_cents bigint not null check (actual_cents >= 0),
  billable_cents bigint not null check (billable_cents >= 0),
  charged_cents bigint not null check (charged_cents >= 0),
  shortfall_cents bigint not null check (shortfall_cents > 0),
  unique (job_id, reason)
);
comment on table bi_subsidy_ledger is 'BI-DEC-01 (decision 1.3). Append only ledger of what Care Net carries on AI actions, one row per shortfall: balance_exhausted (the charge was more than the balance left: the wallet went to R0,00 and Care Net carries the rest, never charged later) and estimate_cap (the actual was more than 25% above the estimate, so the estimate was billed and Care Net carries the difference). estimate, actual, billable (after the estimate cap), charged (what the wallet paid) and shortfall in cents excluding VAT; job_id is the usage event, with its report and inspection. A subsidy never blocks a top up. Written only by bi_wallet_charge.';
comment on column bi_subsidy_ledger.job_id is 'The AI action: the bi_usage_event charged (its report_id and inspection_id are copied here).';
comment on column bi_subsidy_ledger.user_id is 'The person who ran the AI action (auth user).';
create index bi_subsidy_ledger_wallet_idx on bi_subsidy_ledger(wallet_id, created_at);
create index bi_subsidy_ledger_company_idx on bi_subsidy_ledger(client_account_id, created_at);
create trigger bi_subsidy_ledger_append_only before update or delete on bi_subsidy_ledger for each row execute function bi_append_only();

create or replace function bi_wallet_charge(p_usage_event_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_e bi_usage_event;
  v_key text := p ->> 'idempotency_key';
  v_tin bigint := coalesce((p ->> 'tokens_in')::bigint, 0);
  v_tout bigint := coalesce((p ->> 'tokens_out')::bigint, 0);
  v_sec bigint := coalesce((p ->> 'audio_seconds')::bigint, 0);
  v_actual bigint;
  v_charge bigint;
  v_left bigint;
  v_take bigint;
  v_n int := 0;
  r record;
  v_chargeable int;
  v_subsidy bigint := 0;
begin
  select * into v_e from bi_usage_event where id = p_usage_event_id for update;
  if v_e.id is null then
    raise exception 'That usage event was not found.' using errcode = 'P0002';
  end if;
  if v_e.status = 'charged' then
    if v_e.charge_key is distinct from v_key then
      raise exception 'This usage event was already charged under another key.' using errcode = '23505';
    end if;
    return jsonb_build_object('usage_event_id', v_e.id, 'estimate_cents', v_e.estimate_cents, 'actual_cents', v_e.actual_cents,
                              'charged_cents', v_e.charged_cents, 'shortfall_cents', v_e.shortfall_cents,
                              'subsidy_cents', coalesce((select sum(s.shortfall_cents) from bi_subsidy_ledger s where s.job_id = v_e.id), 0),
                              'available_cents', bi_wallet_available_cents(v_e.wallet_id), 'repeat', true);
  end if;
  if v_e.status <> 'estimated' then
    raise exception 'A refused estimate is never charged.';
  end if;
  if v_key is null or length(v_key) < 8 then
    raise exception 'bi_wallet_charge: an idempotency key of at least 8 characters is required' using errcode = '22023';
  end if;
  if least(v_tin, v_tout, v_sec) < 0 then
    raise exception 'bi_wallet_charge: negative quantity' using errcode = '22023';
  end if;
  if v_e.kind = 'photo_tag' then
    v_chargeable := v_e.photos - v_e.free_photos;
    v_tin := v_tin * v_chargeable;
    v_tout := v_tout * v_chargeable;
    v_sec := 0;
  end if;
  if v_e.estimate_cents = 0 and v_tin = 0 and v_tout = 0 and v_sec = 0 then
    v_actual := 0;
  elsif v_e.usd_zar is null then
    v_actual := v_e.estimate_cents;
  else
    v_actual := bi_price_cents(v_tin, v_tout, v_sec, v_e.rate_in, v_e.rate_out, v_e.rate_minute, v_e.usd_zar, v_e.markup);
  end if;
  -- The estimate cap is kept: an actual more than 25% above the estimate bills the estimate.
  v_charge := bi_charge_rule_cents(v_e.estimate_cents, v_actual);

  -- Spend the oldest expiry first; every row names the lot it spends.
  perform pg_advisory_xact_lock(hashtext('bi_wallet'), hashtext(v_e.wallet_id::text));
  v_left := v_charge;
  for r in select * from bi_wallet_lots(v_e.wallet_id) l where l.expires_at > now() and l.remaining_cents > 0 order by l.expires_at, l.lot_id loop
    exit when v_left <= 0;
    v_take := least(v_left, r.remaining_cents);
    v_n := v_n + 1;
    insert into bi_wallet_ledger (wallet_id, entry_kind, amount_cents, lot_id, idempotency_key, usage_event_id, note)
    values (v_e.wallet_id, 'charge', -v_take, r.lot_id, v_key || ':' || v_n, v_e.id, v_e.kind);
    v_left := v_left - v_take;
  end loop;

  -- Decision 1.3: the balance ran out, so every lot is now spent (R0,00) and
  -- Care Net carries the rest; the estimate cap difference is carried too.
  if v_left > 0 then
    insert into bi_subsidy_ledger (reason, job_id, job_kind, report_id, inspection_id, wallet_id, tenant_id, client_account_id, user_id,
                                   estimate_cents, actual_cents, billable_cents, charged_cents, shortfall_cents)
    values ('balance_exhausted', v_e.id, v_e.kind, v_e.report_id, v_e.inspection_id, v_e.wallet_id, v_e.tenant_id, v_e.client_account_id,
            v_e.auth_user_id, v_e.estimate_cents, v_actual, v_charge, v_charge - v_left, v_left);
    v_subsidy := v_subsidy + v_left;
  end if;
  if v_actual > v_charge then
    insert into bi_subsidy_ledger (reason, job_id, job_kind, report_id, inspection_id, wallet_id, tenant_id, client_account_id, user_id,
                                   estimate_cents, actual_cents, billable_cents, charged_cents, shortfall_cents)
    values ('estimate_cap', v_e.id, v_e.kind, v_e.report_id, v_e.inspection_id, v_e.wallet_id, v_e.tenant_id, v_e.client_account_id,
            v_e.auth_user_id, v_e.estimate_cents, v_actual, v_charge, v_charge - v_left, v_actual - v_charge);
    v_subsidy := v_subsidy + (v_actual - v_charge);
  end if;

  update bi_usage_event
     set status = 'charged', act_tokens_in = v_tin, act_tokens_out = v_tout, act_audio_seconds = v_sec,
         actual_cents = v_actual, charged_cents = v_charge, shortfall_cents = v_left, charge_key = v_key, charged_at = now()
   where id = v_e.id;
  perform bi_audit(v_e.auth_user_id, 'wallet_charged', v_e.tenant_id, v_e.client_account_id, 'usage_event', v_e.id,
                   jsonb_build_object('estimate_cents', v_e.estimate_cents, 'actual_cents', v_actual, 'charged_cents', v_charge,
                                      'shortfall_cents', v_left, 'subsidy_cents', v_subsidy));
  return jsonb_build_object('usage_event_id', v_e.id, 'estimate_cents', v_e.estimate_cents, 'actual_cents', v_actual,
                            'charged_cents', v_charge, 'shortfall_cents', v_left, 'subsidy_cents', v_subsidy,
                            'available_cents', bi_wallet_available_cents(v_e.wallet_id), 'repeat', false);
end;
$$;
comment on function bi_wallet_charge is 'BI-WAL-01, replaced by BI-DEC-01 (decision 1.3). Charges an estimated usage event after the AI action with the actual quantities, using the rates copied at the estimate: the actual price, or the estimate when the actual is more than 25% above it. Spends the oldest expiring lots first. When the balance runs out the wallet is left at R0,00 and the shortfall is written to bi_subsidy_ledger (balance_exhausted), carried by Care Net and never charged later; the estimate cap difference is written there too (estimate_cap). Idempotent on the charge key; a repeat returns the first result. Service role only.';

create or replace function bi_wallet_estimate(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_w bi_wallet;
  v_kind text := p ->> 'kind';
  v_model text;
  v_rc bi_rate_card;
  v_fx bi_rate_card;
  v_markup numeric := coalesce(msp_env_get_numeric('bi.markup_default'), 3.0);
  v_tin bigint := coalesce((p ->> 'tokens_in')::bigint, 0);
  v_tout bigint := coalesce((p ->> 'tokens_out')::bigint, 0);
  v_sec bigint := coalesce((p ->> 'audio_seconds')::bigint, 0);
  v_photos int := coalesce((p ->> 'photos')::int, 0);
  v_report uuid := nullif(p ->> 'report_id', '')::uuid;
  v_free int := 0;
  v_chargeable int;
  v_est bigint := 0;
  v_avail bigint;
  v_spent bigint;
  v_reason text;
  v_key text := p ->> 'idempotency_key';
  v_id uuid;
  v_existing bi_usage_event;
begin
  select * into v_existing from bi_usage_event where estimate_key = v_key;
  if v_existing.id is not null then
    v_avail := bi_wallet_available_cents(v_existing.wallet_id);
    return jsonb_build_object('usage_event_id', v_existing.id, 'estimate_cents', v_existing.estimate_cents,
      'allowed', v_existing.status = 'estimated', 'reason', v_existing.refusal_reason, 'free_photos', v_existing.free_photos,
      'available_cents', v_avail, 'remaining_balance_cents', v_avail,
      'balance_after_cents', greatest(v_avail - v_existing.estimate_cents, 0),
      'estimate_exceeds_balance', v_existing.estimate_cents > v_avail, 'repeat', true);
  end if;
  select * into v_w from bi_wallet where id = nullif(p ->> 'wallet_id', '')::uuid;
  if v_w.id is null or not (bi_user_is_ops(p_auth_user)
       or bi_user_roles(p_auth_user, v_w.tenant_id, v_w.client_account_id) && array['inspector','company_admin']) then
    raise exception 'That wallet was not found.' using errcode = 'P0002';
  end if;
  if v_kind not in ('ai_draft','ai_tagging','transcription','photo_tag') or least(v_tin, v_tout, v_sec, v_photos) < 0 then
    raise exception 'bi_wallet_estimate: unknown kind or negative quantity' using errcode = '22023';
  end if;
  if v_key is null or length(v_key) < 8 then
    raise exception 'bi_wallet_estimate: an idempotency key of at least 8 characters is required' using errcode = '22023';
  end if;
  v_model := case v_kind when 'transcription' then 'transcription'
                         when 'ai_draft' then coalesce(p ->> 'model_code', 'ai_quality')
                         else coalesce(p ->> 'model_code', 'ai_fast') end;
  if v_model not in ('ai_fast','ai_quality','transcription') then
    raise exception 'bi_wallet_estimate: unknown model code' using errcode = '22023';
  end if;
  v_rc := bi_rate_card_current(v_model);
  v_fx := bi_rate_card_current('fx_usd_zar');

  if v_kind = 'photo_tag' then
    -- Free for the first 50 photos of a report; tokens are per photo.
    v_free := least(v_photos, greatest(0, 50 - case when v_report is null then 0 else bi_photo_tags_used(v_report) end));
    v_chargeable := v_photos - v_free;
    v_tin := v_tin * v_chargeable;
    v_tout := v_tout * v_chargeable;
    v_sec := 0;
  end if;

  if v_tin = 0 and v_tout = 0 and v_sec = 0 then
    v_est := 0;
  elsif v_rc.status is distinct from 'confirmed' or v_fx.status is distinct from 'confirmed' or v_fx.usd_zar is null
        or (v_model <> 'transcription' and (v_rc.usd_per_mtok_in is null or v_rc.usd_per_mtok_out is null))
        or (v_model = 'transcription' and v_rc.usd_per_minute is null) then
    v_reason := 'rate_card_pending';
  else
    v_est := bi_price_cents(v_tin, v_tout, v_sec, v_rc.usd_per_mtok_in, v_rc.usd_per_mtok_out, v_rc.usd_per_minute, v_fx.usd_zar, v_markup);
  end if;

  v_avail := bi_wallet_available_cents(v_w.id);
  if v_reason is null and v_w.status = 'frozen' and v_est > 0 then
    v_reason := 'wallet_frozen';
  end if;
  if v_reason is null and v_w.monthly_spend_cap_cents is not null and v_est > 0 then
    select coalesce(-sum(l.amount_cents), 0) into v_spent from bi_wallet_ledger l
     where l.wallet_id = v_w.id and l.entry_kind = 'charge' and l.created_at >= date_trunc('month', now());
    if v_spent + v_est > v_w.monthly_spend_cap_cents then
      v_reason := 'spend_cap';
    end if;
  end if;
  if v_reason is null and v_est > v_avail then
    v_reason := 'wallet_empty';
  end if;

  insert into bi_usage_event (wallet_id, tenant_id, client_account_id, auth_user_id, report_id, inspection_id, kind, model_code,
                              est_tokens_in, est_tokens_out, est_audio_seconds, photos, free_photos,
                              rate_in, rate_out, rate_minute, usd_zar, markup, estimate_cents, status, refusal_reason, estimate_key)
  values (v_w.id, v_w.tenant_id, v_w.client_account_id, p_auth_user, v_report, nullif(p ->> 'inspection_id', '')::uuid, v_kind, v_model,
          v_tin, v_tout, v_sec, v_photos, v_free,
          v_rc.usd_per_mtok_in, v_rc.usd_per_mtok_out, v_rc.usd_per_minute, v_fx.usd_zar, v_markup, v_est,
          case when v_reason is null then 'estimated' else 'refused' end, v_reason, v_key)
  returning id into v_id;
  return jsonb_build_object('usage_event_id', v_id, 'estimate_cents', v_est, 'available_cents', v_avail,
                            'remaining_balance_cents', v_avail, 'balance_after_cents', greatest(v_avail - v_est, 0),
                            'estimate_exceeds_balance', v_est > v_avail,
                            'allowed', v_reason is null, 'reason', v_reason, 'free_photos', v_free,
                            'vat_mode', coalesce(msp_env_get('bi.vat_mode'), 'to_be_confirmed'), 'repeat', false);
end;
$$;
comment on function bi_wallet_estimate is 'BI-WAL-01, replaced by BI-DEC-01 (decision 1.3: always show the remaining balance before a run; warn when the estimate exceeds it). The cost preview before an AI action, in cents: p = {wallet_id, kind (ai_draft, ai_tagging, transcription, photo_tag), model_code?, tokens_in, tokens_out, audio_seconds, photos, report_id?, inspection_id?, idempotency_key}. Returns remaining_balance_cents (what the wallet holds now), balance_after_cents and estimate_exceeds_balance (the warning) with every answer. For photo_tag the tokens are per photo and the first 50 photos of a report are free. Refused with a reason: rate_card_pending, wallet_frozen, spend_cap or wallet_empty (the estimate is more than the balance: top up first; capture and template reports still work). Idempotent on the key. Inspector or company admin of the line, or ops.';

-- 8. Minimum margin 20% (decision 1.4) ------------------------------------------------------------------

create function bi_landed_cost_sum(p_components jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum((e.value #>> '{}')::bigint), 0)::bigint
    from jsonb_each(case when jsonb_typeof(p_components) = 'object' then p_components else '{}'::jsonb end) e
   where jsonb_typeof(e.value) = 'number' and (e.value #>> '{}') ~ '^[0-9]{1,15}$';
$$;
comment on function bi_landed_cost_sum is 'BI-DEC-01. The total of a rate card row''s landed cost components, in cents.';

create function bi_landed_components_valid(p_components jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p_components) = 'object'
     and not exists (select 1 from jsonb_each(p_components) e
                      where e.key not in ('model_tokens','voice_minutes','storage','sms','gateway_fee','app_store_cut','kyc','transcription')
                         or jsonb_typeof(e.value) <> 'number' or (e.value #>> '{}') !~ '^[0-9]{1,15}$');
$$;
comment on function bi_landed_components_valid is 'BI-DEC-01. Landed cost components are an object of whole cents (zero or more) under these keys only: model_tokens, voice_minutes, storage, sms, gateway_fee, app_store_cut, kyc, transcription.';

create function bi_margin_floor_cents(p_landed_cents bigint, p_min_pct int default null)
returns bigint
language sql
stable
set search_path = public
as $$
  -- The smallest sell price excluding VAT that keeps the margin: landed x 100 / (100 less pct), rounded up to the cent.
  select case when p_landed_cents is null then null else
    (p_landed_cents * 100 + (100 - x.pct) - 1) / (100 - x.pct) end
    from (select coalesce(p_min_pct, msp_env_get_int('bi.margin.minimum_pct'), 20) as pct) x;
$$;
comment on function bi_margin_floor_cents is 'BI-DEC-01 (decision 1.4). The lowest sell price excluding VAT for a landed cost: landed / 0,80 at the 20% minimum (bi.margin.minimum_pct), rounded up to the cent. Landed R80,00 gives R100,00; landed R80,01 gives R100,02. Same as marginFloorCents in supabase/functions/_shared/bi/pricing.js.';

create function bi_margin_ok(p_sell_cents bigint, p_landed_cents bigint, p_min_pct int default null)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_sell_cents * (100 - x.pct) >= p_landed_cents * 100
    from (select coalesce(p_min_pct, msp_env_get_int('bi.margin.minimum_pct'), 20) as pct) x;
$$;
comment on function bi_margin_ok is 'BI-DEC-01 (decision 1.4). True when sell excluding VAT >= landed cost / 0,80 (at 20%), in whole cents with no rounding: sell x 80 >= landed x 100.';

create function bi_channel_landed_cents(p_landed_cents bigint, p_price_cents bigint, p_store_cut_bps int, p_gateway_fee_bps int, p_gateway_fee_fixed_cents bigint)
returns bigint
language sql
immutable
set search_path = ''
as $$
  -- The channel's percentage fees are rounded up to the cent (the cautious side).
  select p_landed_cents
       + (coalesce(p_price_cents, 0) * (coalesce(p_store_cut_bps, 0) + coalesce(p_gateway_fee_bps, 0)) + 9999) / 10000
       + coalesce(p_gateway_fee_fixed_cents, 0);
$$;
comment on function bi_channel_landed_cents is 'BI-DEC-01. Landed cost of a product sold through a channel: its landed cost components plus the channel''s store cut and gateway fee (basis points of the price, rounded up) and fixed gateway fee.';

alter table bi_rate_card add column landed_cost_components jsonb not null default '{}'::jsonb;
alter table bi_rate_card add constraint bi_rate_card_landed_components_shape check (bi_landed_components_valid(landed_cost_components));
alter table bi_rate_card add column landed_cost_status text not null default 'to_be_confirmed'
  check (landed_cost_status in ('to_be_confirmed','confirmed'));
alter table bi_rate_card add column landed_cost_cents bigint generated always as (bi_landed_cost_sum(landed_cost_components)) stored;
comment on column bi_rate_card.landed_cost_components is 'BI-DEC-01 (decision 1.4). The landed cost of one unit of the product line, in cents excluding VAT, by component: model_tokens, voice_minutes, storage, sms, gateway_fee, app_store_cut, kyc, transcription. For a product sold on more than one channel leave gateway_fee and app_store_cut out and set them per channel (bi_rate_card_channel). Placeholder (empty, to_be_confirmed) until {{rate_card}} is confirmed.';
comment on column bi_rate_card.landed_cost_status is 'to_be_confirmed until ops enters the confirmed components; only a confirmed landed cost is held to the margin floor, so the placeholders fail nothing.';
comment on column bi_rate_card.landed_cost_cents is 'The total of landed_cost_components (generated).';

create table bi_rate_card_channel (
  id uuid primary key default gen_random_uuid(),
  code text not null check (code ~ '^[a-z][a-z0-9_]{2,40}$'),
  channel text not null check (channel in ('ozow_web','apple_app_store','google_play','saved_card','manual_invoice')),
  sell_ex_vat_cents bigint check (sell_ex_vat_cents is null or sell_ex_vat_cents >= 0),
  store_cut_bps int not null default 0 check (store_cut_bps between 0 and 10000),
  gateway_fee_bps int not null default 0 check (gateway_fee_bps between 0 and 10000),
  gateway_fee_fixed_cents bigint not null default 0 check (gateway_fee_fixed_cents >= 0),
  status text not null default 'to_be_confirmed' check (status in ('to_be_confirmed','confirmed','disabled')),
  preferred boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (code, channel)
);
comment on table bi_rate_card_channel is 'BI-DEC-01 (decision 1.4). The channels a rate card product is sold through (plans, top ups, automatic top up, storage packs): Ozow web billing, the Apple App Store and Google Play (through RevenueCat), a saved card, or a manual invoice, with each channel''s store cut and gateway fee (basis points of the price and a fixed amount) and its sell price excluding VAT when it differs from the rate card. A confirmed channel whose fees take the landed cost below the margin floor is refused; for top ups, Ozow web is preferred wherever the Apple or Google cut would break the floor (Director, 27/09/2026), which bi_margin_check says per product. to_be_confirmed until {{rate_card}} is known. Written by ops through the service role.';
-- bi_touch (059) also bumps row_version, which this table does not carry.
create function bi_touch_updated()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
comment on function bi_touch_updated is 'BI-DEC-01. Sets updated_at on update (for tables without row_version).';
create trigger bi_rate_card_channel_touch before update on bi_rate_card_channel for each row execute function bi_touch_updated();

insert into bi_rate_card_channel (code, channel, status, note)
select r.code, c.channel, 'to_be_confirmed',
       case when r.kind = 'topup' and c.channel = 'ozow_web'
            then 'Preferred for top ups wherever the Apple or Google cut would break the 20% margin floor (Director, 27/09/2026). Fees to be confirmed ({{rate_card}}).'
            else 'Fees to be confirmed ({{rate_card}}).' end
  from (select distinct code, kind from bi_rate_card where kind in ('plan','topup','storage_pack')) r
 cross join (values ('ozow_web'), ('apple_app_store'), ('google_play')) c(channel)
union all
select 'auto_topup', 'saved_card', 'to_be_confirmed', 'Automatic top up through the saved card gateway ({{saved_card_gateway}}). Fees to be confirmed ({{rate_card}}).';

create function bi_rate_card_margin_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_landed bigint := bi_landed_cost_sum(new.landed_cost_components);
  v_ch_landed bigint;
  ch record;
begin
  -- The generated landed_cost_cents is computed after BEFORE triggers, so the sum is taken here.
  if new.landed_cost_status = 'confirmed' and v_landed <= 0 then
    raise exception 'Enter the landed cost components before confirming the landed cost of %.', new.code using errcode = '23514';
  end if;
  if new.status = 'confirmed' and new.landed_cost_status = 'confirmed' and new.price_cents is not null then
    if not bi_margin_ok(new.price_cents, v_landed) then
      raise exception 'Below the margin floor: % sells at % excluding VAT against a landed cost of %; the lowest price is %.',
        new.code, bi_format_rand(new.price_cents), bi_format_rand(v_landed), bi_format_rand(bi_margin_floor_cents(v_landed))
        using errcode = '23514';
    end if;
    for ch in select c.* from bi_rate_card_channel c where c.code = new.code and c.status = 'confirmed' loop
      v_ch_landed := bi_channel_landed_cents(v_landed, coalesce(ch.sell_ex_vat_cents, new.price_cents), ch.store_cut_bps, ch.gateway_fee_bps, ch.gateway_fee_fixed_cents);
      if not bi_margin_ok(coalesce(ch.sell_ex_vat_cents, new.price_cents), v_ch_landed) then
        raise exception 'Below the margin floor on %: % through % costs % landed; the lowest price there is %.%',
          ch.channel, new.code, ch.channel, bi_format_rand(v_ch_landed), bi_format_rand(bi_margin_floor_cents(v_ch_landed)),
          case when new.kind in ('topup','auto_topup') and ch.channel in ('apple_app_store','google_play')
               then ' Disable this channel and sell the top up through Ozow web.' else '' end
          using errcode = '23514';
      end if;
    end loop;
  end if;
  return new;
end;
$$;
comment on function bi_rate_card_margin_guard is 'BI-DEC-01 (decision 1.4). Refuses a rate card row that is confirmed (active) with a confirmed landed cost below the margin floor, on its own or through any confirmed channel; refuses confirming a landed cost with no components. Placeholder landed costs (to_be_confirmed) pass.';
create trigger bi_rate_card_margin_guard before insert or update on bi_rate_card for each row execute function bi_rate_card_margin_guard();

create function bi_rate_card_channel_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_rc bi_rate_card;
  v_sell bigint;
  v_landed bigint;
begin
  if tg_op = 'DELETE' then
    raise exception 'Channel rows are disabled, never deleted';
  end if;
  if new.status = 'confirmed' then
    v_rc := bi_rate_card_current(new.code);
    if v_rc.id is not null and v_rc.landed_cost_status = 'confirmed' and v_rc.price_cents is not null then
      v_sell := coalesce(new.sell_ex_vat_cents, v_rc.price_cents);
      v_landed := bi_channel_landed_cents(bi_landed_cost_sum(v_rc.landed_cost_components), v_sell, new.store_cut_bps, new.gateway_fee_bps, new.gateway_fee_fixed_cents);
      if not bi_margin_ok(v_sell, v_landed) then
        raise exception 'Below the margin floor on %: % sells at % and costs % landed there; the lowest price there is %.%',
          new.channel, new.code, bi_format_rand(v_sell), bi_format_rand(v_landed), bi_format_rand(bi_margin_floor_cents(v_landed)),
          case when v_rc.kind in ('topup','auto_topup') and new.channel in ('apple_app_store','google_play')
               then ' Sell this top up through Ozow web instead.' else ' Raise the price or leave the channel disabled.' end
          using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end;
$$;
comment on function bi_rate_card_channel_guard is 'BI-DEC-01 (decision 1.4). Refuses confirming (activating) a channel whose store cut and gateway fees take the product below the margin floor, naming Ozow web for a top up. A channel of a product whose landed cost is still to be confirmed passes.';
create trigger bi_rate_card_channel_guard before insert or update or delete on bi_rate_card_channel for each row execute function bi_rate_card_channel_guard();

create function bi_subscription_price_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_rc bi_rate_card;
  v_landed bigint;
begin
  if new.status in ('active','past_due') and new.source <> 'welcome'
     and (tg_op = 'INSERT' or new.price_cents is distinct from old.price_cents or new.status is distinct from old.status) then
    v_rc := bi_rate_card_current(new.plan_code);
    if v_rc.id is not null and v_rc.landed_cost_status = 'confirmed' then
      v_landed := bi_landed_cost_sum(v_rc.landed_cost_components);
      if not bi_margin_ok(new.price_cents, v_landed) then
        raise exception 'Below the margin floor: the % line at % excluding VAT costs % landed; the lowest price is %.',
          new.plan_code, bi_format_rand(new.price_cents), bi_format_rand(v_landed), bi_format_rand(bi_margin_floor_cents(v_landed))
          using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end;
$$;
comment on function bi_subscription_price_guard is 'BI-DEC-01 (decision 1.4). Refuses activating a subscription line at a price below the margin floor of its plan''s confirmed landed cost (a trial or welcome line is not a price). Placeholder landed costs pass.';
create trigger bi_company_subscription_price_guard before insert or update on bi_company_subscription
  for each row execute function bi_subscription_price_guard();

create function bi_margin_check()
returns table (code text, kind text, channel text, sell_ex_vat_cents bigint, landed_cost_cents bigint, floor_cents bigint,
               margin_pct numeric, result text, advice text)
language sql
stable
security definer
set search_path = public
as $$
  with cur as (
    select distinct on (r.code) r.*
      from bi_rate_card r
     where r.status <> 'retired' and r.effective_from <= current_date and r.price_cents is not null
     order by r.code, r.effective_from desc, r.created_at desc),
  lines as (
    select c.code, c.kind, null::text as channel, c.price_cents as sell, bi_landed_cost_sum(c.landed_cost_components) as landed,
           c.landed_cost_status as lstatus, 'confirmed'::text as cstatus
      from cur c
    union all
    select c.code, c.kind, ch.channel, coalesce(ch.sell_ex_vat_cents, c.price_cents),
           bi_channel_landed_cents(bi_landed_cost_sum(c.landed_cost_components), coalesce(ch.sell_ex_vat_cents, c.price_cents),
                                   ch.store_cut_bps, ch.gateway_fee_bps, ch.gateway_fee_fixed_cents),
           c.landed_cost_status, ch.status
      from cur c join bi_rate_card_channel ch on ch.code = c.code
     where ch.status <> 'disabled'),
  judged as (
    select l.*, bi_margin_floor_cents(l.landed) as floor,
           case when l.lstatus <> 'confirmed' or l.cstatus = 'to_be_confirmed' then 'to_be_confirmed'
                when bi_margin_ok(l.sell, l.landed) then 'ok' else 'below_floor' end as res
      from lines l)
  select j.code, j.kind, j.channel, j.sell, j.landed, j.floor,
         case when j.sell > 0 then round(100.0 * (j.sell - j.landed) / j.sell, 1) end,
         j.res,
         case when j.res = 'below_floor' and j.kind in ('topup','auto_topup') and j.channel in ('apple_app_store','google_play')
                   and exists (select 1 from judged o where o.code = j.code and o.channel = 'ozow_web' and o.res = 'ok')
              then 'Sell this top up through Ozow web: the app store cut breaks the margin floor.'
              when j.res = 'below_floor' then 'Raise the price or lower the landed cost: the sell price excluding VAT is below the margin floor.'
              when j.res = 'to_be_confirmed' then 'Landed cost or channel fees to be confirmed ({{rate_card}}).'
              else null end
    from judged j
  union all
  select 'bi.markup_default', 'ai_markup', null, round(100 * x.m)::bigint, 100::bigint, bi_margin_floor_cents(100),
         round(100.0 * (x.m - 1) / x.m, 1),
         case when bi_margin_ok(round(100 * x.m)::bigint, 100) then 'ok' else 'below_floor' end,
         'AI actions sell at vendor cost x markup (per R1,00 of vendor cost here); the markup must be at least 1,25 for a 20% margin.'
    from (select coalesce(msp_env_get_numeric('bi.markup_default'), 3.0) as m) x
   order by 1, 3 nulls first;
$$;
comment on function bi_margin_check is 'BI-DEC-01 (decision 1.4). Every price on the rate card in force (plans, top ups, automatic top up, storage packs), on its own and per channel, and the AI markup, against the minimum margin: result ok, below_floor (sell excluding VAT < landed cost / 0,80) or to_be_confirmed (landed cost or channel fees not confirmed yet, never counted as a failure), with the floor, the margin and advice (Ozow web for a top up whose app store cut breaks the floor). Service role only.';

create function bi_topup_channels(p_code text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('channel', m.channel, 'result', m.result,
           'offer', m.result <> 'below_floor',
           'preferred', m.channel = 'ozow_web' and exists (select 1 from bi_margin_check() b
                         where b.code = p_code and b.channel in ('apple_app_store','google_play') and b.result = 'below_floor'),
           'advice', m.advice) order by m.channel), '[]'::jsonb)
    from bi_margin_check() m
   where m.code = p_code and m.channel is not null;
$$;
comment on function bi_topup_channels is 'BI-DEC-01 (decision 1.4). For the app''s top up screen: the channels of a product, whether to offer each (not below the floor) and whether Ozow web is preferred because an app store cut breaks the floor. Service role only.';

-- 9. Export: super users only, every export audited (decision 1.7) ---------------------------------------

create table bi_super_user (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id),
  reason text not null check (length(btrim(reason)) between 5 and 500),
  granted_by text not null,
  granted_at timestamptz not null default now(),
  revoked_by text,
  revoked_at timestamptz,
  check ((revoked_at is null) = (revoked_by is null))
);
comment on table bi_super_user is 'BI-DEC-01 (decision 1.7). The explicit Bee-Inspect super user assignment. A super user is Care Net staff (hsf_user_is_staff: forge_admin, forge_omp or forge_safety_reviewer) AND holds a live row here; only a super user may export. Granted and revoked only by the service role, never by a client; revoked, never deleted.';
create unique index bi_super_user_live_idx on bi_super_user(auth_user_id) where revoked_at is null;

create function bi_super_user_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'bi_super_user rows are revoked, never deleted';
  end if;
  if (to_jsonb(new) - array['revoked_by','revoked_at']) is distinct from (to_jsonb(old) - array['revoked_by','revoked_at'])
     or old.revoked_at is not null then
    raise exception 'bi_super_user: only a revocation may be recorded, once';
  end if;
  return new;
end;
$$;
create trigger bi_super_user_guard before update or delete on bi_super_user for each row execute function bi_super_user_guard();

create function bi_is_super_user(p_auth_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_auth_user is not null
     and hsf_user_is_staff(p_auth_user)
     and exists (select 1 from bi_super_user s where s.auth_user_id = p_auth_user and s.revoked_at is null);
$$;
comment on function bi_is_super_user is 'BI-DEC-01 (decision 1.7). True only for Care Net staff (hsf_user_is_staff) with a live bi_super_user assignment. Staff without the assignment, and assignees who are no longer staff, are not super users.';

create function bi_super_user_grant(p_target uuid, p_reason text, p_granted_by text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not hsf_user_is_staff(p_target) then
    raise exception 'Only Care Net staff can be a Bee-Inspect super user.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_granted_by, ''))) < 2 then
    raise exception 'Name who granted the assignment.' using errcode = '22023';
  end if;
  insert into bi_super_user (auth_user_id, reason, granted_by) values (p_target, btrim(p_reason), btrim(p_granted_by))
  on conflict (auth_user_id) where revoked_at is null do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from bi_super_user where auth_user_id = p_target and revoked_at is null;
  else
    perform bi_audit(null, 'super_user_granted', null, null, 'super_user', v_id,
                     jsonb_build_object('auth_user_id', p_target, 'reason', p_reason, 'granted_by', p_granted_by));
  end if;
  return jsonb_build_object('super_user_id', v_id, 'auth_user_id', p_target);
end;
$$;
comment on function bi_super_user_grant is 'BI-DEC-01 (decision 1.7). Grants the super user assignment to a Care Net staff member, with a reason and who granted it. Service role only (no client and no staff JWT can call it). Idempotent. Audited.';

create function bi_super_user_revoke(p_target uuid, p_revoked_by text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  update bi_super_user set revoked_at = now(), revoked_by = coalesce(nullif(btrim(p_revoked_by), ''), 'service_role')
   where auth_user_id = p_target and revoked_at is null
  returning id into v_id;
  if v_id is null then
    raise exception 'That person holds no super user assignment.' using errcode = 'P0002';
  end if;
  perform bi_audit(null, 'super_user_revoked', null, null, 'super_user', v_id, jsonb_build_object('auth_user_id', p_target, 'revoked_by', p_revoked_by));
  return jsonb_build_object('super_user_id', v_id, 'revoked', true);
end;
$$;
comment on function bi_super_user_revoke is 'BI-DEC-01 (decision 1.7). Revokes a super user assignment. Service role only. Audited.';

create function bi_export(p_auth_user uuid, p_kind text, p jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := nullif(p ->> 'tenant_id', '')::uuid;
  v_company uuid := nullif(p ->> 'client_account_id', '')::uuid;
  v_from date := coalesce(nullif(p ->> 'from', '')::date, date '2000-01-01');
  v_to date := coalesce(nullif(p ->> 'to', '')::date, current_date);
  v_limit int := greatest(1, least(coalesce(nullif(p ->> 'limit', '')::int, 5000), 50000));
  v_step bi_step_up;
  v_rows jsonb;
  v_count int;
  v_filters jsonb;
begin
  if p_kind is null or p_kind not in ('inspections','findings','risk_register','corrective_actions','reports','section_f_links',
                                      'wallet_ledger','usage_events','subsidy_ledger','audit_log','medicals_volume','margin_check') then
    raise exception 'Unknown export.' using errcode = '22023';
  end if;
  v_filters := jsonb_strip_nulls(jsonb_build_object('tenant_id', v_tenant, 'client_account_id', v_company, 'from', v_from, 'to', v_to, 'limit', v_limit));
  -- Decision 1.7: super users only. A refusal is audited too.
  if not bi_is_super_user(p_auth_user) then
    perform bi_audit(p_auth_user, 'export_denied', v_tenant, v_company, 'export', null,
                     jsonb_build_object('what', p_kind, 'reason', 'not_super_user', 'filters', v_filters));
    return jsonb_build_object('ok', false, 'reason', 'not_permitted', 'message', 'Only a Bee-Inspect super user can export.');
  end if;
  select * into v_step from bi_step_up where id = nullif(p ->> 'step_up_id', '')::uuid for update;
  if v_step.id is null or v_step.auth_user_id <> p_auth_user or v_step.purpose <> 'bulk_export' or v_step.consumed_at is not null
     or v_step.asserted_at < now() - make_interval(mins => bi_step_up_window_minutes('in_app')) then
    perform bi_audit(p_auth_user, 'export_denied', v_tenant, v_company, 'export', null,
                     jsonb_build_object('what', p_kind, 'reason', 'step_up', 'filters', v_filters));
    return jsonb_build_object('ok', false, 'reason', 'step_up_required', 'message', 'Verify your second factor again before exporting.');
  end if;
  update bi_step_up set consumed_at = now() where id = v_step.id;

  if p_kind = 'inspections' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select i.id, i.tenant_id, i.client_account_id, i.site_id, i.template_id, i.title, i.status, i.voice_note_policy,
             i.scheduled_for, i.started_at, i.submitted_at, i.closed_at, i.created_at
        from bi_inspection i
       where (v_tenant is null or i.tenant_id = v_tenant) and (v_company is null or i.client_account_id = v_company)
         and i.created_at::date between v_from and v_to
       order by i.created_at, i.id limit v_limit) x;
  elsif p_kind = 'findings' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select f.id, f.inspection_id, f.tenant_id, f.client_account_id, f.area_id, f.template_item_id, f.equipment_id, f.result,
             f.note, f.severity, f.captured_at
        from bi_finding f
       where (v_tenant is null or f.tenant_id = v_tenant) and (v_company is null or f.client_account_id = v_company)
         and f.captured_at::date between v_from and v_to
       order by f.captured_at, f.id limit v_limit) x;
  elsif p_kind = 'risk_register' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select rr.id, rr.inspection_id, rr.tenant_id, rr.client_account_id, rr.hazard, rr.consequence,
             rr.inherent_likelihood, rr.inherent_severity, rr.inherent_score, rr.inherent_band_label,
             rr.residual_likelihood, rr.residual_severity, rr.residual_score, rr.residual_band_label, rr.top_control
        from bi_risk_register rr join bi_risk r on r.id = rr.id
       where (v_tenant is null or rr.tenant_id = v_tenant) and (v_company is null or rr.client_account_id = v_company)
         and r.created_at::date between v_from and v_to
       order by r.created_at, rr.id limit v_limit) x;
  elsif p_kind = 'corrective_actions' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select c.id, c.inspection_id, c.tenant_id, c.client_account_id, c.finding_id, c.risk_id, c.description, c.owner_name,
             c.due_on, c.status, c.escalation_level, c.closed_at, c.created_at
        from bi_corrective_action c
       where (v_tenant is null or c.tenant_id = v_tenant) and (v_company is null or c.client_account_id = v_company)
         and c.created_at::date between v_from and v_to
       order by c.created_at, c.id limit v_limit) x;
  elsif p_kind = 'reports' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select b.id, b.inspection_id, b.tenant_id, b.client_account_id, b.title, b.status, b.issued_at, b.pdf_sha256,
             l.status as filing, l.element_code, l.eligibility_reason
        from bi_report b left join bi_report_file_link l on l.report_id = b.id
       where (v_tenant is null or b.tenant_id = v_tenant) and (v_company is null or b.client_account_id = v_company)
         and b.created_at::date between v_from and v_to
       order by b.created_at, b.id limit v_limit) x;
  elsif p_kind = 'section_f_links' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select l.report_id, l.client_account_id, l.file_id, l.element_code, l.status, l.eligibility_reason, l.attempts, l.synced_at
        from bi_report_file_link l join bi_report b on b.id = l.report_id
       where (v_tenant is null or b.tenant_id = v_tenant) and (v_company is null or l.client_account_id = v_company)
         and l.synced_at::date between v_from and v_to
       order by l.synced_at, l.report_id limit v_limit) x;
  elsif p_kind = 'wallet_ledger' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select l.id, l.wallet_id, w.tenant_id, w.client_account_id, l.entry_kind, l.amount_cents, l.lot_id, l.expires_at, l.note, l.created_at
        from bi_wallet_ledger l join bi_wallet w on w.id = l.wallet_id
       where (v_tenant is null or w.tenant_id = v_tenant) and (v_company is null or w.client_account_id = v_company)
         and l.created_at::date between v_from and v_to
       order by l.created_at, l.id limit v_limit) x;
  elsif p_kind = 'usage_events' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select u.id, u.wallet_id, u.tenant_id, u.client_account_id, u.report_id, u.kind, u.model_code, u.estimate_cents, u.actual_cents,
             u.charged_cents, u.shortfall_cents, u.status, u.refusal_reason, u.created_at, u.charged_at
        from bi_usage_event u
       where (v_tenant is null or u.tenant_id = v_tenant) and (v_company is null or u.client_account_id = v_company)
         and u.created_at::date between v_from and v_to
       order by u.created_at, u.id limit v_limit) x;
  elsif p_kind = 'subsidy_ledger' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select s.id, s.created_at, s.reason, s.job_id, s.job_kind, s.report_id, s.wallet_id, s.tenant_id, s.client_account_id, s.user_id,
             s.estimate_cents, s.actual_cents, s.billable_cents, s.charged_cents, s.shortfall_cents
        from bi_subsidy_ledger s
       where (v_tenant is null or s.tenant_id = v_tenant) and (v_company is null or s.client_account_id = v_company)
         and s.created_at::date between v_from and v_to
       order by s.created_at, s.id limit v_limit) x;
  elsif p_kind = 'audit_log' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select a.id, a.occurred_at, a.actor_label, a.tenant_id, a.client_account_id, a.event, a.object_kind, a.object_id, a.detail
        from bi_audit_log a
       where (v_tenant is null or a.tenant_id = v_tenant) and (v_company is null or a.client_account_id = v_company)
         and a.occurred_at::date between v_from and v_to
       order by a.occurred_at, a.id limit v_limit) x;
  elsif p_kind = 'medicals_volume' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
      select m.id, m.client_account_id, m.site_id, m.counted_from, m.counted_to, m.volume_12m, m.source, m.evidence_ref,
             m.verified_by, m.verified_at
        from bi_medicals_volume m
       where (v_company is null or m.client_account_id = v_company) and m.verified_at::date between v_from and v_to
       order by m.verified_at, m.id limit v_limit) x;
  else -- margin_check
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (select * from bi_margin_check() limit v_limit) x;
  end if;
  v_count := jsonb_array_length(v_rows);
  -- Who (actor), what, how many rows and when (occurred_at) for every export.
  perform bi_audit(p_auth_user, 'export', v_tenant, v_company, 'export', v_step.id,
                   jsonb_build_object('what', p_kind, 'row_count', v_count, 'filters', v_filters, 'step_up_id', v_step.id));
  return jsonb_build_object('ok', true, 'kind', p_kind, 'row_count', v_count, 'exported_at', now(), 'rows', v_rows);
end;
$$;
comment on function bi_export is 'BI-DEC-01 (decision 1.7, the export page). The only export path: p_kind inspections, findings, risk_register, corrective_actions, reports, section_f_links, wallet_ledger, usage_events, subsidy_ledger, audit_log, medicals_volume or margin_check; p = {step_up_id (a fresh bulk_export step up, consumed), tenant_id?, client_account_id?, from?, to?, limit? (5 000, at most 50 000)}. Only a super user (bi_is_super_user) exports; anyone else gets ok false and the refusal is audited (export_denied). Every export is audited in bi_audit_log: who (actor), what, row_count and when (occurred_at). FICA records, qualifications and credentials are never exported (they are read only through their audited functions). Service role only.';

-- 10. Row Level Security and grants ---------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['bi_medicals_volume','bi_site_subcontractor','bi_authorised_person','bi_person_credential',
                           'bi_consent_purpose','bi_subsidy_ledger','bi_rate_card_channel','bi_super_user'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;
grant select on bi_medicals_volume, bi_site_subcontractor, bi_authorised_person, bi_consent_purpose, bi_subsidy_ledger,
                bi_rate_card_channel, bi_super_user to authenticated;

create policy bi_medicals_volume_read on bi_medicals_volume for select to authenticated
  using (bi_is_ops() or bi_can_company(client_account_id, 'manage_company'));
create policy bi_site_subcontractor_read on bi_site_subcontractor for select to authenticated
  using (bi_is_ops() or bi_can_company(principal_account_id, 'read_capture') or bi_can_company(subcontractor_account_id, 'manage_company'));
create policy bi_authorised_person_read on bi_authorised_person for select to authenticated
  using (bi_can_company(client_account_id, 'read_report_draft'));
create policy bi_consent_purpose_read on bi_consent_purpose for select to authenticated using (true);
create policy bi_subsidy_ledger_read on bi_subsidy_ledger for select to authenticated
  using (bi_can(tenant_id, client_account_id, 'read_wallet'));
create policy bi_rate_card_channel_read on bi_rate_card_channel for select to authenticated using (bi_is_ops());
create policy bi_super_user_read on bi_super_user for select to authenticated using (bi_is_ops() or auth_user_id = auth.uid());
-- bi_person_credential: no authenticated policy (read only through bi_person_credential_list, audited).

-- Landed costs are Care Net's own figures: clients keep reading the prices and
-- values of plans, top ups and storage packs, never the cost columns.
revoke select on bi_rate_card from authenticated;
grant select (id, code, kind, label, price_cents, value_cents, wallet_monthly_cents, storage_bytes, threshold_cents,
              usd_per_mtok_in, usd_per_mtok_out, usd_per_minute, usd_zar, status, effective_from, notes, created_at)
  on bi_rate_card to authenticated;

do $$
declare
  f text;
begin
  -- Server side only.
  foreach f in array array['bi_medicals_volume_current(uuid, uuid, date)','bi_free_file_direct(uuid, uuid, date)',
                           'bi_free_file_eligible(uuid, uuid, date)','bi_medicals_volume_record(uuid, jsonb)',
                           'bi_site_subcontractor_register(uuid, jsonb)','bi_site_subcontractor_end(uuid, uuid, text)',
                           'bi_signer_gate(uuid, uuid, text)','bi_manages_company(uuid, uuid)',
                           'bi_authorised_person_save(uuid, jsonb)','bi_person_credential_save(uuid, jsonb)',
                           'bi_credential_verify(uuid, text, uuid, text, text)','bi_person_credential_list(uuid, uuid)',
                           'bi_person_credential_expiry_run(date)','bi_consent_status(uuid, uuid)','bi_consent_decide(uuid, jsonb)',
                           'bi_consent_withdraw(uuid, text, uuid)','bi_margin_check()','bi_topup_channels(text)',
                           'bi_is_super_user(uuid)','bi_super_user_grant(uuid, text, text)','bi_super_user_revoke(uuid, text)',
                           'bi_export(uuid, text, jsonb)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  -- Pure helpers the view (security_invoker), the guards and the checks use.
  foreach f in array array['bi_format_rand(bigint)','bi_risk_band_label(int)','bi_risk_band_colour(text)','bi_risk_assess(int, int)',
                           'bi_step_up_window_minutes(text)','bi_safe_file_name(text)','bi_landed_cost_sum(jsonb)',
                           'bi_landed_components_valid(jsonb)','bi_margin_floor_cents(bigint, int)','bi_margin_ok(bigint, bigint, int)',
                           'bi_channel_landed_cents(bigint, bigint, int, int, bigint)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  foreach f in array array['bi_no_delete()','bi_touch_updated()','bi_site_subcontractor_guard()','bi_rate_card_margin_guard()',
                           'bi_rate_card_channel_guard()','bi_subscription_price_guard()','bi_super_user_guard()'] loop
    execute format('revoke execute on function %s from public, anon', f);
  end loop;
end;
$$;

-- Safety net: no bi_ function is executable by anon or through PUBLIC.
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'bi\_%' and has_function_privilege('anon', p.oid, 'execute')
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
