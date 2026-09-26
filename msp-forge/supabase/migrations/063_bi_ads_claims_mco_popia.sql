-- CNC HSF FORGE | BI-OPS-01 v1.0.0 | Bee-Inspect banners config, claim codes, attribution, MCO nodes, expiry and POPIA check 26/09/2026
-- Built to hsf/BUILD-CONTRACT.md 16 and hsf/BEE-INSPECT-BUILD-PROMPT.md A1, A4,
-- B3, B4, B9 and sections 6 and 8, phase P3.
--
-- What this migration does:
--   1. bi_ad_config (the per tenant hide or rebrand toggle that P1 left as a
--      stub in vercel/js/cnc-ad.js) and bi_ad_dismissal (a dismissal kept per
--      signed in person, 14 days, AD-01 and AD-05 fold instead of vanishing).
--      bi_banner_state gives the File site the subscriber state ("Open
--      Bee-Inspect"), the tenant toggle and the dismissals in one call.
--   2. bi_claim_code: the desktop QR one time code (B3). Only the SHA 256 of
--      the code is stored (the Edge Function makes the code and hashes it with
--      supabase/functions/_shared/bi/claim-code.js); it expires 10 minutes
--      after it is made and is redeemed once.
--   3. bi_attribution: Bee-Inspect conversion events of a signed in person
--      (claim_code_created, claim_code_scanned, install, trial_start,
--      subscribe) with the campaign tags known at the time. hsf_attribution_event
--      (058) is not reused: it deliberately holds no person and only the event
--      attribution_seen, and it is applied to live. Banner events of the
--      server side sources still go to hsf_ad_event (057) through
--      hsf_ad_event_record when the banner id is known.
--   4. bi_mco_node (B9): company, site and department nodes registered locally
--      for MyClinicOnline, status registered_local; linked is reserved until
--      {{mco_endpoint}} exists.
--   5. bi_qualification_expiry_run: alerts at 60, 30 and 7 days, and an expired
--      qualification makes a cleared inspector restricted (B4).
--   6. bi_clinical_column_check: POPIA guard. Bee-Inspect holds no clinical
--      medical results; the check lists any bi_ column whose name reads like
--      one, and test/sql/bi_popia_checks.sql fails on any hit.
--   7. Private storage buckets bi-evidence (photos and voice notes) and
--      bi-reports (Issued PDF and JSON). No storage policy grants anything to
--      anon or authenticated: uploads and downloads use signed URLs the Edge
--      Functions issue with the service role.
-- Not applied to the live project.

-- 1. Banner configuration and dismissals ------------------------------------------------------

create table bi_ad_config (
  tenant_id uuid primary key references bi_tenant(id),
  hide_banners boolean not null default false,
  rebrand_name text check (rebrand_name is null or length(btrim(rebrand_name)) between 1 and 80),
  rebrand_logo_path text,
  updated_by text not null,
  updated_at timestamptz not null default now()
);
comment on table bi_ad_config is 'BI-OPS-01 (prompt A1). The per tenant banner toggle: hide the Bee-Inspect banners for the tenant''s people, or show them under the tenant''s own name and logo. The locked report footer is not affected. Written by ops through the service role.';

create table bi_ad_dismissal (
  auth_user_id uuid not null references auth.users(id),
  ad_id text not null check (ad_id ~ '^AD-(0[1-9]|10)$'),
  dismissed_until timestamptz not null,
  collapsed boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (auth_user_id, ad_id),
  check (dismissed_until <= created_at + interval '15 days'),
  check (not collapsed or ad_id in ('AD-01','AD-05'))
);
comment on table bi_ad_dismissal is 'BI-OPS-01 (prompt A1). A banner dismissed by a signed in person, for 14 days (AD-01 and AD-05 fold to a strip instead: collapsed). The person writes only their own rows.';

create function bi_banner_state(p_auth_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select u.* from bi_app_user u where u.auth_user_id = p_auth_user and u.status = 'active'),
  acc as (select a.id from msp_client_account a where p_auth_user is not null and a.auth_user_id = p_auth_user)
  select jsonb_build_object(
    'subscriber', exists (select 1 from me join bi_company_subscription s on s.tenant_id = me.tenant_id and s.status in ('trial','active','past_due'))
                  or exists (select 1 from acc join bi_company_subscription s on s.client_account_id = acc.id and s.status in ('trial','active','past_due')),
    'hide_banners', coalesce((select c.hide_banners from bi_ad_config c join me on me.tenant_id = c.tenant_id), false),
    'rebrand_name', (select c.rebrand_name from bi_ad_config c join me on me.tenant_id = c.tenant_id),
    'flag_on', bi_flag_enabled('bee_inspect_ads', (select tenant_id from me)),
    'dismissed', coalesce((select jsonb_agg(jsonb_build_object('ad_id', d.ad_id, 'until', d.dismissed_until, 'collapsed', d.collapsed) order by d.ad_id)
                             from bi_ad_dismissal d where d.auth_user_id = p_auth_user and d.dismissed_until > now()), '[]'::jsonb));
$$;
comment on function bi_banner_state is 'BI-OPS-01 (prompt A1). For the File site''s banner hooks: whether the signed in person is a subscriber (their tenant, or their File company, holds a live line), the tenant''s hide and rebrand toggle, the database flag and the live dismissals. Service role only.';

-- 2. Claim codes -------------------------------------------------------------------------------

create table bi_claim_code (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  auth_user_id uuid not null references auth.users(id),
  client_account_id uuid references msp_client_account(id),
  file_id uuid references hsf_file(id),
  ad_id text check (ad_id ~ '^AD-(0[1-9]|10)$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  redeemed_device text check (redeemed_device is null or length(redeemed_device) <= 120),
  constraint bi_claim_code_ten_minutes check (expires_at > created_at and expires_at <= created_at + interval '10 minutes')
);
comment on table bi_claim_code is 'BI-OPS-01 (prompt B3). The one time claim code a desktop shows as a QR so the phone signs in to the same account and File. Only the SHA 256 of the code is kept; it expires 10 minutes after it is made and is redeemed once (bi_claim_code_guard). Server side only.';
create index bi_claim_code_user_idx on bi_claim_code(auth_user_id, created_at);

create function bi_claim_code_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'bi_claim_code rows are never deleted';
  end if;
  if (to_jsonb(new) - array['redeemed_at','redeemed_device']) is distinct from (to_jsonb(old) - array['redeemed_at','redeemed_device'])
     or old.redeemed_at is not null then
    raise exception 'A claim code is redeemed once and never changes';
  end if;
  return new;
end;
$$;
create trigger bi_claim_code_guard before update or delete on bi_claim_code for each row execute function bi_claim_code_guard();

-- 3. Attribution --------------------------------------------------------------------------------

create table bi_attribution (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  auth_user_id uuid references auth.users(id),
  tenant_id uuid references bi_tenant(id),
  event text not null check (event in ('claim_code_created','claim_code_scanned','install','trial_start','subscribe')),
  ad_id text check (ad_id ~ '^AD-(0[1-9]|10)$'),
  utm_source text check (utm_source ~ '^[A-Za-z0-9._-]{1,64}$'),
  utm_medium text check (utm_medium ~ '^[A-Za-z0-9._-]{1,64}$'),
  utm_campaign text check (utm_campaign ~ '^[A-Za-z0-9._-]{1,64}$'),
  utm_content text check (utm_content ~ '^[A-Za-z0-9._-]{1,64}$')
);
comment on table bi_attribution is 'BI-OPS-01 (prompt A4, section 6 attribution). Server side conversion events of a signed in person with the campaign tags known then. Append only. First party only: nothing is sent to an ad platform from here.';
create trigger bi_attribution_append_only before update or delete on bi_attribution for each row execute function bi_append_only();

create function bi_attribution_record(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_key text;
begin
  for v_key in select jsonb_object_keys(coalesce(p, '{}'::jsonb)) loop
    if v_key not in ('event','ad_id','utm_source','utm_medium','utm_campaign','utm_content','page','variant') then
      raise exception 'bi_attribution_record: unknown key %', v_key using errcode = '22023';
    end if;
  end loop;
  insert into bi_attribution (auth_user_id, tenant_id, event, ad_id, utm_source, utm_medium, utm_campaign, utm_content)
  values (p_auth_user, (bi_app_user_of(p_auth_user)).tenant_id, p ->> 'event', nullif(p ->> 'ad_id', ''),
          nullif(p ->> 'utm_source', ''), nullif(p ->> 'utm_medium', ''), nullif(p ->> 'utm_campaign', ''), nullif(p ->> 'utm_content', ''))
  returning id into v_id;
  -- Mirror to the banner funnel (057) when the banner is known, without a person.
  if p ->> 'ad_id' is not null and p ->> 'page' is not null then
    begin
      perform hsf_ad_event_record(jsonb_build_object('event', p ->> 'event', 'ad_id', p ->> 'ad_id',
                'variant', coalesce(p ->> 'variant', 'server'), 'page', p ->> 'page'));
    exception when others then
      null;  -- the banner funnel is best effort; the attribution row stands
    end;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
comment on function bi_attribution_record is 'BI-OPS-01 (prompt A4). Records a server side conversion event (claim_code_created, claim_code_scanned, install, trial_start, subscribe) and mirrors it, without the person, to hsf_ad_event when the banner id and page are known. Service role only.';

create function bi_claim_code_create(p_auth_user uuid, p_code_hash text, p jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_file uuid := nullif(p ->> 'file_id', '')::uuid;
  v_id uuid;
  v_exp timestamptz := now() + interval '10 minutes';
begin
  if p_auth_user is null or not exists (select 1 from auth.users where id = p_auth_user) then
    raise exception 'Sign in first.' using errcode = '28000';
  end if;
  if p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'bi_claim_code_create: the code hash must be SHA 256 hex' using errcode = '22023';
  end if;
  if not bi_rate_allow('claim_create', p_auth_user::text, 5, 600) then
    raise exception 'Too many claim codes. Please wait a few minutes.' using errcode = '53400';
  end if;
  v_acc := hsf_account_of(p_auth_user);
  if v_file is not null and not hsf_can_access_file(p_auth_user, v_file) then
    raise exception 'That File was not found.' using errcode = 'P0002';
  end if;
  insert into bi_claim_code (code_hash, auth_user_id, client_account_id, file_id, ad_id, expires_at)
  values (p_code_hash, p_auth_user, v_acc.id, v_file, nullif(p ->> 'ad_id', ''), v_exp)
  returning id into v_id;
  perform bi_attribution_record(p_auth_user, jsonb_strip_nulls(jsonb_build_object('event', 'claim_code_created',
            'ad_id', p ->> 'ad_id', 'page', p ->> 'page', 'utm_source', p ->> 'utm_source', 'utm_medium', p ->> 'utm_medium',
            'utm_campaign', p ->> 'utm_campaign', 'utm_content', p ->> 'utm_content')));
  perform bi_audit(p_auth_user, 'claim_code_created', null, v_acc.id, 'claim_code', v_id, '{}'::jsonb);
  return jsonb_build_object('claim_id', v_id, 'expires_at', v_exp);
end;
$$;
comment on function bi_claim_code_create is 'BI-OPS-01 (prompt B3). Stores the SHA 256 of a new claim code for the signed in person (and their File company and File), valid 10 minutes. At most 5 codes per person in 10 minutes. Records claim_code_created. Service role only; the plain code never reaches the database.';

create function bi_claim_code_redeem(p_code_hash text, p jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c bi_claim_code;
begin
  if not bi_rate_allow('claim_redeem', coalesce(p ->> 'caller_key', 'unknown'), 10, 600) then
    return jsonb_build_object('ok', false, 'reason', 'rate');
  end if;
  if p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  select * into v_c from bi_claim_code where code_hash = p_code_hash for update;
  if v_c.id is null then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if v_c.redeemed_at is not null then
    return jsonb_build_object('ok', false, 'reason', 'used');
  end if;
  if v_c.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;
  update bi_claim_code set redeemed_at = now(), redeemed_device = left(nullif(p ->> 'device', ''), 120) where id = v_c.id;
  perform bi_attribution_record(v_c.auth_user_id, jsonb_strip_nulls(jsonb_build_object('event', 'claim_code_scanned', 'ad_id', v_c.ad_id,
            'page', case when v_c.ad_id is not null then '/bee-inspect' end)));
  perform bi_audit(v_c.auth_user_id, 'claim_code_redeemed', null, v_c.client_account_id, 'claim_code', v_c.id, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'auth_user_id', v_c.auth_user_id,
                            'email', (select u.email from auth.users u where u.id = v_c.auth_user_id),
                            'client_account_id', v_c.client_account_id, 'file_id', v_c.file_id);
end;
$$;
comment on function bi_claim_code_redeem is 'BI-OPS-01 (prompt B3). Redeems a claim code by its SHA 256, once, within 10 minutes: answers ok with the account to sign the phone in to, or invalid, used, expired or rate (10 attempts per caller key in 10 minutes). The Edge Function then asks Supabase Auth for a one time sign in token for that account. Service role only.';

-- 4. MyClinicOnline nodes ---------------------------------------------------------------------------

create table bi_mco_node (
  id uuid primary key default gen_random_uuid(),
  node_kind text not null check (node_kind in ('company','site','department')),
  client_account_id uuid not null references msp_client_account(id),
  site_id uuid references bi_site(id),
  department_id uuid references bi_department(id),
  status text not null default 'registered_local' check (status in ('registered_local','linked')),
  mco_ref text,
  registered_at timestamptz not null default now(),
  linked_at timestamptz,
  check ((node_kind = 'company') = (site_id is null and department_id is null)),
  check ((node_kind = 'site') = (site_id is not null and department_id is null)),
  check ((node_kind = 'department') = (department_id is not null))
);
comment on table bi_mco_node is 'BI-OPS-01 (prompt B9). A company, site or department node registered for MyClinicOnline. Now: registered_local in Supabase only. linked (with the MyClinicOnline reference) is reserved and refused until {{mco_endpoint}} exists.';
create unique index bi_mco_node_idx on bi_mco_node(node_kind, client_account_id,
  coalesce(site_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid));

create function bi_mco_node_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'bi_mco_node rows are never deleted';
  end if;
  if new.status = 'linked' or new.mco_ref is not null then
    raise exception 'Linking to MyClinicOnline is reserved until the endpoint exists ({{mco_endpoint}})';
  end if;
  return new;
end;
$$;
create trigger bi_mco_node_guard before insert or update or delete on bi_mco_node for each row execute function bi_mco_node_guard();

create function bi_mco_register(p_client_account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int;
begin
  if not exists (select 1 from bi_company where client_account_id = p_client_account_id) then
    raise exception 'That company is not onboarded to Bee-Inspect.' using errcode = 'P0002';
  end if;
  insert into bi_mco_node (node_kind, client_account_id) values ('company', p_client_account_id) on conflict do nothing;
  insert into bi_mco_node (node_kind, client_account_id, site_id)
  select 'site', s.client_account_id, s.id from bi_site s where s.client_account_id = p_client_account_id and s.archived_at is null
  on conflict do nothing;
  insert into bi_mco_node (node_kind, client_account_id, site_id, department_id)
  select 'department', d.client_account_id, d.site_id, d.id from bi_department d where d.client_account_id = p_client_account_id and d.archived_at is null
  on conflict do nothing;
  select count(*) into v_n from bi_mco_node where client_account_id = p_client_account_id;
  perform bi_audit(null, 'mco_nodes_registered', null, p_client_account_id, 'company', p_client_account_id, jsonb_build_object('nodes', v_n));
  return jsonb_build_object('client_account_id', p_client_account_id, 'nodes', v_n, 'status', 'registered_local',
    'note', 'MyClinicOnline is not called: the endpoint is still to be supplied.');
end;
$$;
comment on function bi_mco_register is 'BI-OPS-01 (prompt B9, mco-register). Registers the company, its live sites and departments as MyClinicOnline nodes, locally (registered_local). Idempotent. MyClinicOnline is never called. Service role only.';

-- 5. Qualification expiry -----------------------------------------------------------------------------

create function bi_qualification_expiry_run(p_today date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alerts jsonb;
  v_expired jsonb;
  v_restricted jsonb;
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

  if jsonb_array_length(v_alerts) + jsonb_array_length(v_expired) + jsonb_array_length(v_restricted) > 0 then
    perform bi_audit(null, 'qualification_expiry_run', null, null, 'inspector_qualification', null,
                     jsonb_build_object('alerts', jsonb_array_length(v_alerts), 'expired', jsonb_array_length(v_expired),
                                        'restricted', v_restricted));
  end if;
  return jsonb_build_object('alerts', v_alerts, 'expired', v_expired, 'restricted', v_restricted);
end;
$$;
comment on function bi_qualification_expiry_run is 'BI-OPS-01 (prompt B4, qualification-expiry cron). Marks and returns the 60, 30 and 7 day alerts (each once), marks lapsed qualifications expired and makes a cleared inspector with an expired qualification restricted, with the reason. Audited as a system run. Service role only.';

-- 6. POPIA: no clinical medical data in Bee-Inspect --------------------------------------------------------

create function bi_clinical_column_check()
returns table (table_name text, column_name text)
language sql
stable
security definer
set search_path = public
as $$
  -- Whole name parts only, so submitted_at is not mistaken for bmi.
  select c.table_name::text, c.column_name::text
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name like 'bi\_%'
     and c.column_name ~* ('(^|_)(diagnosis|diagnoses|diagnostic|clinical|medical|medicals|blood|bp|audiometry|audiogram|'
                          || 'spirometry|fev1|fvc|hba1c|glucose|cholesterol|hiv|tb|tuberculosis|xray|urine|urinalysis|icd10|'
                          || 'medication|pregnancy|pregnant|disability|illness|fitness|bmi|hearing|vision|lung|drug|drugs|'
                          || 'surveillance|omp|certificate_of_fitness)(_|$)');
$$;
comment on function bi_clinical_column_check is 'BI-OPS-01 (prompt section 3.4, POPIA). Bee-Inspect holds health and safety inspection and risk assessment data only; clinical medical results stay in MyClinicOnline. Lists any column of a bi_ table or view whose name reads like a clinical medical item. Must return no rows; test/sql/bi_popia_checks.sql fails otherwise, so a future migration cannot add one unnoticed.';

-- 7. Storage buckets ----------------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('bi-evidence', 'bi-evidence', false, 52428800,
   array['image/jpeg','image/png','image/heic','image/webp','audio/mp4','audio/m4a','audio/aac','audio/mpeg','audio/wav','audio/webm']),
  ('bi-reports', 'bi-reports', false, 52428800, array['application/pdf','application/json','application/zip'])
on conflict (id) do nothing;

-- 8. Row Level Security ------------------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['bi_ad_config','bi_ad_dismissal','bi_claim_code','bi_attribution','bi_mco_node'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;
grant select on bi_ad_config, bi_mco_node, bi_attribution to authenticated;
grant select, insert, update, delete on bi_ad_dismissal to authenticated;

create policy bi_ad_config_read on bi_ad_config for select to authenticated using (bi_is_ops() or tenant_id = bi_my_tenant());
create policy bi_ad_dismissal_own on bi_ad_dismissal for all to authenticated
  using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
create policy bi_attribution_read on bi_attribution for select to authenticated using (bi_is_ops());
create policy bi_mco_node_read on bi_mco_node for select to authenticated using (bi_can_company(client_account_id, 'read_capture'));
-- bi_claim_code: no authenticated policy (server side only).

do $$
declare
  f text;
begin
  foreach f in array array['bi_banner_state(uuid)','bi_attribution_record(uuid, jsonb)','bi_claim_code_create(uuid, text, jsonb)',
                           'bi_claim_code_redeem(text, jsonb)','bi_mco_register(uuid)','bi_qualification_expiry_run(date)',
                           'bi_clinical_column_check()'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array['bi_claim_code_guard()','bi_mco_node_guard()'] loop
    execute format('revoke execute on function %s from public, anon', f);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
