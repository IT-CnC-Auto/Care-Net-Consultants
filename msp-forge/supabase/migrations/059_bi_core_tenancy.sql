-- CNC HSF FORGE | BI-CORE-01 v1.0.0 | Bee-Inspect core: tenants, companies, users, roles, identity, audit 26/09/2026
-- Built to hsf/BUILD-CONTRACT.md 16 (Amendment 8) and sections 3, 5 (B3, B4, B8),
-- 6 and 8 of hsf/BEE-INSPECT-BUILD-PROMPT.md, phase P3 (backend).
--
-- Bee-Inspect is the paid inspection and risk assessment product. Its company is
-- the File's company: msp_client_account (migration 009), never a copy. Every new
-- object is prefixed bi_ so it stays apart from the msp_ and hsf_ objects; none of
-- these names exists in migrations 001 to 058 (checked at the top of this file,
-- which refuses to run over an existing bi_ object).
--
-- What this migration does:
--   1. bi_tenant: the subscribing organisation (a consultancy or an employer
--      doing its own inspections), with its voice note policy (recommended or
--      strict) and the welcome allowance.
--   2. bi_company: the Bee-Inspect onboarding record of a File company
--      (msp_client_account), one row per company: legal and trading names,
--      registration, CIPC, s16(1), s16(2) and POPIA contacts, logo path and the
--      status Not started, In review, Active, Blocked. Start Inspection needs
--      Active (enforced in 060).
--   3. bi_company_subscription: a tenant's paid line on a company (base R299,00
--      or extra company R199,00 a month, excluding VAT), with its monthly AI
--      Wallet value and storage. Auditors see only companies their tenant holds
--      an active line on.
--   4. bi_app_user and bi_role_assignment: a person's Bee-Inspect profile (one
--      tenant each) and roles inspector, assistant, company_admin and ops.
--      Ops is Care Net staff: hsf_is_staff() (migration 047) or an ops
--      assignment, which only the service role can grant.
--   5. bi_inspector_profile, bi_inspector_qualification, bi_fica_record: the
--      inspector's path Identity, FICA, Qualifications, Competence review,
--      Cleared | Restricted | Assistant only, and the company and inspector FICA
--      documents (storage paths only). No authenticated policy reads these
--      tables: every read goes through bi_fica_list or bi_qualification_list,
--      which audit each row they return (prompt section 8).
--   6. bi_consent_record: Bee-Inspect consents (terms, privacy, location, voice,
--      identifiable people in photos, FICA processing, marketing with double opt
--      in). hsf_consent (049) is not reused: its kinds are the File's three
--      POPIA consents under HSF-CONSENT-1.0, which contract section 3 forbids
--      changing.
--   7. bi_audit_log: append only audit trail of Bee-Inspect (actor, tenant,
--      company, event, object). Written only by security definer functions.
--   8. bi_feature_flag: bee_inspect_ads and welcome_hook, both off by default,
--      with optional per tenant overrides.
--   9. bi_rate_event and bi_rate_allow: a small database rate limiter for claim
--      codes, sign in helpers and AI actions.
--  10. bi_step_up: a recorded step up MFA assertion (method, time, assurance
--      level) that signing, top ups over R499,00, bulk export and Bee-Matched
--      engagement consume.
--  11. Parameters in msp_env_parameter (category commercial): bi.vat_mode
--      'to_be_confirmed', bi.markup_default 3.0, bi.step_up_window_minutes 10.
--
-- POPIA: Bee-Inspect holds health and safety inspection and risk assessment data
-- only. No bi_ table may hold clinical medical results; bi_clinical_column_check
-- (migration 063) lists any column whose name reads like one and the checks fail
-- on it. MyClinicOnline remains the medicals system.
--
-- Access (every table): RLS on; everything revoked from public and anon; the
-- service role has all; authenticated reads through policies built on
-- bi_my_roles and bi_is_ops. Nothing here is written by a client directly.
--
-- Not applied to the live project. Migrations 001 to 058 are unchanged.

-- 0. Refuse to run over an existing bi_ object --------------------------------------

do $$
declare
  v text;
begin
  select string_agg(c.relname, ', ') into v
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname like 'bi\_%';
  if v is not null then
    raise exception '059: bi_ relations already exist (%); Bee-Inspect migrations run once', v;
  end if;
  select string_agg(p.proname, ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'bi\_%';
  if v is not null then
    raise exception '059: bi_ functions already exist (%); Bee-Inspect migrations run once', v;
  end if;
end;
$$;

-- 1. Shared trigger helpers ----------------------------------------------------------

create function bi_is_client_session()
returns boolean
language sql
stable
set search_path = ''
as $$
  -- A statement a client sent through the API runs as anon or authenticated. A
  -- statement inside a security definer function runs as the function owner,
  -- and an Edge Function runs as service_role; both are trusted paths.
  select current_user in ('anon', 'authenticated');
$$;
comment on function bi_is_client_session is 'BI-CORE-01. True when the current statement comes straight from a client (role anon or authenticated), false inside a security definer function or for the service role. Guards use it to keep protected columns (status, seals, ownership) to the trusted paths.';

create function bi_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.row_version := coalesce(old.row_version, 0) + 1;
  end if;
  return new;
end;
$$;
comment on function bi_touch is 'BI-CORE-01. Sets updated_at and increments row_version on update. Offline sync sends the row_version it last saw and updates only where it still matches (conflict safe sync).';

create function bi_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append only', tg_table_name;
end;
$$;
comment on function bi_append_only is 'BI-CORE-01. Refuses every update and delete on an append only table.';

-- 2. Tenants and companies --------------------------------------------------------------

create table bi_tenant (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 200),
  voice_note_policy text not null default 'recommended' check (voice_note_policy in ('recommended','strict')),
  white_label_name text check (white_label_name is null or length(btrim(white_label_name)) between 1 and 120),
  logo_path text,
  welcome_inspections_left int not null default 0 check (welcome_inspections_left between 0 and 1),
  status text not null default 'active' check (status in ('active','suspended','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1
);
comment on table bi_tenant is 'BI-CORE-01 (prompt section 6, tenant). The organisation that subscribes to Bee-Inspect: a consultancy whose competent persons inspect client companies, or an employer inspecting itself. voice_note_policy recommended or strict (B5: strict needs a voice note on every Fail and blocks a report with a missing voice note). The locked report footer is never a tenant setting.';
create trigger bi_tenant_touch before update on bi_tenant for each row execute function bi_touch();

create table bi_company (
  client_account_id uuid primary key references msp_client_account(id),
  legal_name text not null check (length(btrim(legal_name)) between 1 and 200),
  trading_name text,
  registration_number text,
  cipc_status text check (cipc_status in ('not_checked','in_business','deregistered','in_deregistration','unknown')),
  s16_1_contact text,
  s16_2_contact text,
  popia_contact text,
  logo_path text,
  prefilled_from_file boolean not null default false,
  onboarding_status text not null default 'not_started'
    check (onboarding_status in ('not_started','in_review','active','blocked')),
  blocked_reason text,
  activated_at timestamptz,
  activated_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  constraint bi_company_blocked_reason check (onboarding_status <> 'blocked' or length(btrim(coalesce(blocked_reason, ''))) >= 5),
  constraint bi_company_active_stamp check (onboarding_status <> 'active' or activated_at is not null)
);
comment on table bi_company is 'BI-CORE-01 (prompt B4). The Bee-Inspect onboarding record of a File company. The company itself is msp_client_account (the File''s company); this row adds only what Bee-Inspect needs before a first inspection. onboarding_status Not started, In review, Active, Blocked; Start Inspection needs Active. Pre filled from the File profile where it exists (prefilled_from_file). Paths only, never document bytes.';
create trigger bi_company_touch before update on bi_company for each row execute function bi_touch();

create table bi_company_subscription (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  plan_code text not null check (plan_code in ('base','extra_company')),
  status text not null default 'active' check (status in ('trial','active','past_due','cancelled')),
  price_cents bigint not null check (price_cents >= 0),
  wallet_monthly_cents bigint not null check (wallet_monthly_cents >= 0),
  storage_bytes bigint not null check (storage_bytes > 0),
  vat_mode text not null default 'to_be_confirmed' check (vat_mode in ('to_be_confirmed','exclusive','inclusive')),
  source text not null default 'manual' check (source in ('revenuecat','ozow','manual','welcome')),
  external_ref text,
  started_on date not null default current_date,
  current_period_start date not null default current_date,
  current_period_end date not null default (current_date + interval '1 month')::date,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  check (current_period_end > current_period_start)
);
comment on table bi_company_subscription is 'BI-CORE-01 (prompt B8). A tenant''s paid line on one company: base (R299,00 a month, first company, R150,00 AI Wallet a month, 10 GB) or extra_company (R199,00 a month, R100,00 AI Wallet a month, 10 GB). Amounts in cents, excluding VAT; vat_mode stays to_be_confirmed until Chantelle confirms {{vat_inclusive}}. A tenant holds at most one live base line and one live line per company.';
create unique index bi_company_subscription_live_idx on bi_company_subscription(tenant_id, client_account_id)
  where status in ('trial','active','past_due');
create unique index bi_company_subscription_one_base_idx on bi_company_subscription(tenant_id)
  where plan_code = 'base' and status in ('trial','active','past_due');
create index bi_company_subscription_company_idx on bi_company_subscription(client_account_id);
create trigger bi_company_subscription_touch before update on bi_company_subscription for each row execute function bi_touch();

-- 3. People and roles ---------------------------------------------------------------------

create table bi_app_user (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id),
  tenant_id uuid not null references bi_tenant(id),
  display_name text not null check (length(btrim(display_name)) between 1 and 200),
  email text,
  mobile_e164 text check (mobile_e164 is null or mobile_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  mobile_verified_at timestamptz,
  mfa_enrolled_at timestamptz,
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1
);
comment on table bi_app_user is 'BI-CORE-01 (prompt section 6, app_user). A person''s Bee-Inspect profile on the same Supabase Auth user as the File. One tenant per person. MFA is mandatory for inspectors (B3): mfa_enrolled_at is set once Supabase Auth reports a verified factor.';
create trigger bi_app_user_touch before update on bi_app_user for each row execute function bi_touch();

create table bi_role_assignment (
  id uuid primary key default gen_random_uuid(),
  app_user_id uuid not null references bi_app_user(id),
  tenant_id uuid references bi_tenant(id),
  client_account_id uuid references msp_client_account(id),
  role text not null check (role in ('inspector','assistant','company_admin','ops')),
  granted_by text not null,
  granted_at timestamptz not null default now(),
  revoked_by text,
  revoked_at timestamptz,
  constraint bi_role_scope check (
    (role = 'ops' and tenant_id is null and client_account_id is null)
    or (role = 'company_admin' and tenant_id is not null and client_account_id is not null)
    or (role in ('inspector','assistant') and tenant_id is not null)),
  constraint bi_role_revoke_pair check ((revoked_at is null) = (revoked_by is null))
);
comment on table bi_role_assignment is 'BI-CORE-01. Roles: inspector (the competent person or auditor), assistant (captures, never signs, sees no money, FICA or qualifications), company_admin (manages one company: sites tree, users, wallet caps, report library) and ops (Care Net staff; granted by the service role only). An inspector or assistant row with no company covers every company its tenant holds a live line on. Revoked, never deleted.';
create unique index bi_role_assignment_live_idx on bi_role_assignment
  (app_user_id, role, coalesce(client_account_id, '00000000-0000-0000-0000-000000000000'::uuid)) where revoked_at is null;
create index bi_role_assignment_user_idx on bi_role_assignment(app_user_id) where revoked_at is null;

create function bi_role_assignment_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'bi_role_assignment rows are revoked, never deleted';
  end if;
  if tg_op = 'INSERT' then
    if new.role <> 'ops' and new.tenant_id is distinct from (select u.tenant_id from bi_app_user u where u.id = new.app_user_id) then
      raise exception 'bi_role_assignment: the role must be in the person''s own tenant';
    end if;
    return new;
  end if;
  if (to_jsonb(new) - array['revoked_by','revoked_at']) is distinct from (to_jsonb(old) - array['revoked_by','revoked_at'])
     or old.revoked_at is not null then
    raise exception 'bi_role_assignment: only a revocation may be recorded, once';
  end if;
  return new;
end;
$$;
create trigger bi_role_assignment_guard before insert or update or delete on bi_role_assignment
  for each row execute function bi_role_assignment_guard();

-- 4. Inspector clearance, qualifications and FICA ------------------------------------------

create table bi_inspector_profile (
  app_user_id uuid primary key references bi_app_user(id),
  status text not null default 'identity'
    check (status in ('identity','fica','qualifications','competence_review','cleared','restricted','assistant_only')),
  id_document_kind text check (id_document_kind in ('sa_id','passport')),
  id_last4 text check (id_last4 ~ '^[0-9A-Z]{4}$'),
  kyc_vendor_ref text,
  liveness_passed_at timestamptz,
  competence_scope text[] not null default '{}',
  declarations_accepted_at timestamptz,
  cleared_by text,
  cleared_at timestamptz,
  restricted_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  constraint bi_inspector_cleared_stamp check (status <> 'cleared' or (cleared_at is not null and cleared_by is not null and liveness_passed_at is not null and declarations_accepted_at is not null)),
  constraint bi_inspector_restricted_reason check (status <> 'restricted' or length(btrim(coalesce(restricted_reason, ''))) >= 5)
);
comment on table bi_inspector_profile is 'BI-CORE-01 (prompt B4). Inspector clearance path: identity, fica, qualifications, competence_review, then cleared, restricted or assistant_only. Only a cleared inspector whose competence_scope covers the template category signs a report (061). An expired qualification makes a cleared inspector restricted (bi_qualification_expiry_run). The identity document is held by {{kyc_vendor}}; only its kind, the last four characters and the vendor reference are kept here.';
comment on column bi_inspector_profile.competence_scope is 'Template categories this person may sign for (for example scaffolds, ladders, lifting, electrical, fire, ppe, chemicals, general). Set at competence review.';
create trigger bi_inspector_profile_touch before update on bi_inspector_profile for each row execute function bi_touch();

create table bi_inspector_qualification (
  id uuid primary key default gen_random_uuid(),
  app_user_id uuid not null references bi_app_user(id),
  qual_type text not null check (length(btrim(qual_type)) between 2 and 120),
  issuer text not null check (length(btrim(issuer)) between 2 and 200),
  number text not null check (length(btrim(number)) between 1 and 80),
  issued_on date,
  expires_on date,
  document_path text,
  ocr_assisted boolean not null default false,
  status text not null default 'pending' check (status in ('pending','verified','rejected','expired')),
  verified_by text,
  verified_at timestamptz,
  alert_60_at timestamptz,
  alert_30_at timestamptz,
  alert_7_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  check (expires_on is null or issued_on is null or expires_on > issued_on),
  check (status <> 'verified' or (verified_by is not null and verified_at is not null))
);
comment on table bi_inspector_qualification is 'BI-CORE-01 (prompt B4). A qualification or registration of an inspector: type, issuer, number, expiry, the stored certificate path (never the bytes) and whether OCR helped read it. Alerts at 60, 30 and 7 days before expiry; expiry makes the inspector restricted. Every read by a person is audited (bi_qualification_list); no policy lets a client read the table directly.';
create index bi_inspector_qualification_user_idx on bi_inspector_qualification(app_user_id);
create trigger bi_inspector_qualification_touch before update on bi_inspector_qualification for each row execute function bi_touch();

create table bi_fica_record (
  id uuid primary key default gen_random_uuid(),
  subject_kind text not null check (subject_kind in ('company','inspector')),
  client_account_id uuid references msp_client_account(id),
  app_user_id uuid references bi_app_user(id),
  document_kind text not null check (document_kind in ('cipc_registration','proof_of_address','id_document','bank_confirmation','fica_pack','director_list','other')),
  document_path text not null,
  sha256 text check (sha256 ~ '^[0-9a-f]{64}$'),
  status text not null default 'submitted' check (status in ('submitted','in_review','accepted','rejected','expired')),
  reviewed_by text,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  constraint bi_fica_subject check (
    (subject_kind = 'company' and client_account_id is not null and app_user_id is null)
    or (subject_kind = 'inspector' and app_user_id is not null and client_account_id is null))
);
comment on table bi_fica_record is 'BI-CORE-01 (prompt B4). FICA documents of a company or an inspector, by storage path and fingerprint only. Every read by a person is audited (bi_fica_list); no policy lets a client read the table directly.';
create index bi_fica_record_company_idx on bi_fica_record(client_account_id);
create index bi_fica_record_user_idx on bi_fica_record(app_user_id);
create trigger bi_fica_record_touch before update on bi_fica_record for each row execute function bi_touch();

-- 5. Consent ---------------------------------------------------------------------------------

create table bi_consent_record (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id),
  client_account_id uuid references msp_client_account(id),
  consent_kind text not null check (consent_kind in
    ('terms','privacy','location','voice_recording','identifiable_people','fica_processing','marketing')),
  granted boolean not null,
  wording_version text not null check (wording_version ~ '^BI-[A-Z]+-[0-9]+\.[0-9]+$'),
  granted_at timestamptz not null default now(),
  confirmed_at timestamptz,
  withdrawn_at timestamptz,
  constraint bi_consent_marketing_double_opt_in check (consent_kind <> 'marketing' or granted = false or confirmed_at is not null or withdrawn_at is not null)
);
comment on table bi_consent_record is 'BI-CORE-01 (prompt sections 3 and 8). Bee-Inspect consents, one row per decision. marketing is separate, never pre ticked and needs a double opt in (confirmed_at). identifiable_people covers photos in which a person can be recognised. Append only apart from confirmed_at and withdrawn_at, each set once. Wording versions are BI-<NAME>-<n.n> and are still to be written (open question in docs/bee-inspect/p3).';
create index bi_consent_record_user_idx on bi_consent_record(auth_user_id, consent_kind);

create function bi_consent_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'bi_consent_record is append only';
  end if;
  if (to_jsonb(new) - array['confirmed_at','withdrawn_at']) is distinct from (to_jsonb(old) - array['confirmed_at','withdrawn_at'])
     or (old.confirmed_at is not null and new.confirmed_at is distinct from old.confirmed_at)
     or (old.withdrawn_at is not null and new.withdrawn_at is distinct from old.withdrawn_at) then
    raise exception 'bi_consent_record: only confirmed_at and withdrawn_at may be set, once each';
  end if;
  return new;
end;
$$;
create trigger bi_consent_guard before update or delete on bi_consent_record for each row execute function bi_consent_guard();

-- 6. Audit ---------------------------------------------------------------------------------

create table bi_audit_log (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_auth_user uuid,
  actor_label text not null,
  tenant_id uuid,
  client_account_id uuid,
  event text not null check (event ~ '^[a-z][a-z0-9_]{2,63}$'),
  object_kind text,
  object_id uuid,
  detail jsonb not null default '{}'::jsonb
);
comment on table bi_audit_log is 'BI-CORE-01 (prompt B5 and section 8). Append only audit trail of Bee-Inspect: every FICA and qualification read, clearance, sign off, issue, wallet movement, claim code, role change and Section F filing. Written only by security definer functions (bi_audit); no client writes.';
create index bi_audit_log_company_idx on bi_audit_log(client_account_id, occurred_at);
create index bi_audit_log_object_idx on bi_audit_log(object_id);
create trigger bi_audit_log_append_only before update or delete on bi_audit_log for each row execute function bi_append_only();

create function bi_audit(p_actor uuid, p_event text, p_tenant uuid, p_company uuid,
                         p_object_kind text, p_object_id uuid, p_detail jsonb default '{}'::jsonb)
returns void
language sql
security definer
set search_path = public
as $$
  insert into bi_audit_log (actor_auth_user, actor_label, tenant_id, client_account_id, event, object_kind, object_id, detail)
  values (p_actor,
          coalesce((select u.email from auth.users u where u.id = p_actor), case when p_actor is null then 'system' else 'user' end),
          p_tenant, p_company, p_event, p_object_kind, p_object_id, coalesce(p_detail, '{}'::jsonb));
$$;
comment on function bi_audit is 'BI-CORE-01. Appends one bi_audit_log row. The actor label is the auth email, or system for scheduled runs. Server side only.';

-- 7. Feature flags ----------------------------------------------------------------------------

create table bi_feature_flag (
  key text not null check (key ~ '^[a-z][a-z0-9_]{2,63}$'),
  tenant_id uuid references bi_tenant(id),
  enabled boolean not null default false,
  description text not null,
  updated_by text not null default 'migration_059',
  updated_at timestamptz not null default now()
);
comment on table bi_feature_flag is 'BI-CORE-01 (prompt section 3.9). Feature flags of the app and Edge Functions: one global row per key (tenant_id null), optionally overridden per tenant. bee_inspect_ads and welcome_hook are off by default. The File site keeps its own flags in vercel/js/flags.js.';
create unique index bi_feature_flag_key_idx on bi_feature_flag(key, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid));

insert into bi_feature_flag (key, enabled, description) values
  ('bee_inspect_ads', false, 'Bee-Inspect banners and pages on the File site, and the app''s own prompts to subscribe. Off until the Director switches it on (the File site flag in vercel/js/flags.js decides the site).'),
  ('welcome_hook', false, 'Welcome offer: one free template inspection and R20,00 in the AI Wallet for a new tenant. Off until the Director decides (prompt section 12).');

create function bi_flag_enabled(p_key text, p_tenant uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select f.enabled from bi_feature_flag f where f.key = p_key and p_tenant is not null and f.tenant_id = p_tenant),
    (select f.enabled from bi_feature_flag f where f.key = p_key and f.tenant_id is null),
    false);
$$;
comment on function bi_flag_enabled is 'BI-CORE-01. The flag for a tenant: its own override, else the global row, else off.';

-- 8. Rate limits ----------------------------------------------------------------------------------

create table bi_rate_event (
  id bigint generated always as identity primary key,
  bucket text not null check (bucket ~ '^[a-z][a-z0-9_]{2,40}$'),
  key_hash text not null check (key_hash ~ '^[0-9a-f]{64}$'),
  occurred_at timestamptz not null default now()
);
comment on table bi_rate_event is 'BI-CORE-01 (prompt section 8, rate limits on auth, claim codes and AI). One row per counted attempt, keyed by a SHA 256 of the caller key (never the key itself). Written only by bi_rate_allow.';
create index bi_rate_event_idx on bi_rate_event(bucket, key_hash, occurred_at);

create function bi_rate_allow(p_bucket text, p_key text, p_limit int, p_window_seconds int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text := encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex');
begin
  perform pg_advisory_xact_lock(hashtext('bi_rate:' || p_bucket), hashtext(v_hash));
  if (select count(*) from bi_rate_event
       where bucket = p_bucket and key_hash = v_hash
         and occurred_at > now() - make_interval(secs => greatest(1, p_window_seconds))) >= greatest(1, p_limit) then
    return false;
  end if;
  insert into bi_rate_event (bucket, key_hash) values (p_bucket, v_hash);
  return true;
end;
$$;
comment on function bi_rate_allow is 'BI-CORE-01. Counts one attempt in a bucket for a key and answers false once p_limit attempts arrived in the last p_window_seconds. The key is stored only as its SHA 256.';

-- 9. Step up MFA ------------------------------------------------------------------------------

create table bi_step_up (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id),
  purpose text not null check (purpose in ('signoff','issue','bee_matched','bulk_export','topup_over_499')),
  method text not null check (method in ('totp','phone')),
  aal text not null check (aal = 'aal2'),
  asserted_at timestamptz not null,
  session_ref text not null check (session_ref ~ '^[0-9a-f]{64}$'),
  report_id uuid,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  check (asserted_at <= created_at + interval '1 minute')
);
comment on table bi_step_up is 'BI-CORE-01 (prompt B3). A recorded step up MFA assertion: the person re verified a TOTP or SMS factor (Supabase Auth amr method totp or phone, assurance level aal2) at asserted_at. session_ref is the SHA 256 of the session id, never the token. Consumed once, by a signature (061) or another protected action. Written only by bi_step_up_record.';
create index bi_step_up_user_idx on bi_step_up(auth_user_id, asserted_at);

create function bi_step_up_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'bi_step_up is append only';
  end if;
  if (to_jsonb(new) - 'consumed_at') is distinct from (to_jsonb(old) - 'consumed_at') or old.consumed_at is not null then
    raise exception 'bi_step_up: only consumed_at may be set, once';
  end if;
  return new;
end;
$$;
create trigger bi_step_up_guard before update or delete on bi_step_up for each row execute function bi_step_up_guard();

-- 10. Parameters -------------------------------------------------------------------------------

insert into msp_env_parameter (key, value, value_type, allowed_values, min_value, max_value, category, description, updated_by) values
  ('bi.vat_mode', 'to_be_confirmed', 'enum', array['to_be_confirmed','exclusive','inclusive'], null, null, 'commercial',
   'Bee-Inspect: how stored amounts relate to VAT. Every amount is stored excluding VAT; to_be_confirmed until Chantelle confirms {{vat_inclusive}}.',
   'migration_059'),
  ('bi.markup_default', '3.0', 'decimal', null, 1, 10, 'commercial',
   'Bee-Inspect AI Wallet markup: price = (tokens x model rate + audio minutes x transcription rate) x fx x markup (prompt B8). Default 3.0.',
   'migration_059'),
  ('bi.step_up_window_minutes', '10', 'integer', null, 1, 60, 'commercial',
   'Bee-Inspect: how many minutes a step up MFA assertion stays valid for an in app signature, a top up over R499,00, a bulk export or a Bee-Matched engagement.',
   'migration_059')
on conflict (key) do nothing;

-- 11. Access helpers ------------------------------------------------------------------------------

create function bi_is_ops()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and (hsf_is_staff()
          or exists (select 1 from bi_role_assignment a join bi_app_user u on u.id = a.app_user_id
                      where u.auth_user_id = auth.uid() and u.status = 'active'
                        and a.role = 'ops' and a.revoked_at is null));
$$;
comment on function bi_is_ops is 'BI-CORE-01. Care Net staff: the existing File staff check hsf_is_staff() (forge_admin, forge_omp, forge_safety_reviewer in app_metadata) or a live ops assignment. Ops read everything; they write only through functions.';

create function bi_user_is_ops(p_auth_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_auth_user is not null
     and (hsf_user_is_staff(p_auth_user)
          or exists (select 1 from bi_role_assignment a join bi_app_user u on u.id = a.app_user_id
                      where u.auth_user_id = p_auth_user and u.status = 'active'
                        and a.role = 'ops' and a.revoked_at is null));
$$;
comment on function bi_user_is_ops is 'BI-CORE-01. bi_is_ops for a verified auth user id passed by an Edge Function (hsf_user_is_staff, migration 051, or a live ops assignment).';

create function bi_subscription_live(p_tenant uuid, p_company uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from bi_company_subscription s
                  where s.tenant_id = p_tenant and s.client_account_id = p_company
                    and s.status in ('trial','active','past_due'));
$$;
comment on function bi_subscription_live is 'BI-CORE-01. True when the tenant holds a live line (trial, active or past due) on the company.';

create function bi_user_roles(p_auth_user uuid, p_tenant uuid, p_company uuid)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(distinct a.role order by a.role), '{}'::text[])
    from bi_role_assignment a
    join bi_app_user u on u.id = a.app_user_id
   where p_auth_user is not null
     and u.auth_user_id = p_auth_user and u.status = 'active'
     and a.revoked_at is null
     and a.role <> 'ops'
     and a.tenant_id = p_tenant
     and u.tenant_id = p_tenant
     and (a.client_account_id = p_company
          or (a.client_account_id is null and a.role in ('inspector','assistant')))
     and (a.role = 'company_admin' or bi_subscription_live(p_tenant, p_company));
$$;
comment on function bi_user_roles is 'BI-CORE-01. The roles a person holds on a company within a tenant. Inspector and assistant roles count only while the tenant holds a live line on the company (auditors see only companies they are subscribed to); company_admin counts for its own company.';

create function bi_my_roles(p_tenant uuid, p_company uuid)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select bi_user_roles(auth.uid(), p_tenant, p_company);
$$;
comment on function bi_my_roles is 'BI-CORE-01. bi_user_roles for the signed in person (RLS helper).';

create function bi_my_tenant()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select u.tenant_id from bi_app_user u where u.auth_user_id = auth.uid() and u.status = 'active';
$$;
comment on function bi_my_tenant is 'BI-CORE-01. The tenant of the signed in person, or null.';

create function bi_my_app_user_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select u.id from bi_app_user u where u.auth_user_id = auth.uid() and u.status = 'active';
$$;
comment on function bi_my_app_user_id is 'BI-CORE-01. The Bee-Inspect profile id of the signed in person, or null. Security definer so policies and guards can use it without reading bi_app_user under its own policy (no recursion).';

create function bi_my_tenant_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from bi_role_assignment a join bi_app_user u on u.id = a.app_user_id
                  where u.auth_user_id = auth.uid() and u.status = 'active' and a.revoked_at is null
                    and a.role in ('inspector','company_admin'));
$$;
comment on function bi_my_tenant_manager is 'BI-CORE-01. True when the signed in person is an inspector or company admin (who may see the people of their tenant).';

create function bi_user_active_in_tenant(p_app_user_id uuid, p_tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from bi_app_user u where u.id = p_app_user_id and u.tenant_id = p_tenant and u.status = 'active');
$$;
comment on function bi_user_active_in_tenant is 'BI-CORE-01. True when the profile is active in the tenant (used by the guards whatever the caller can read).';

create function bi_can(p_tenant uuid, p_company uuid, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- One definition of every RLS decision, so the policies stay short and agree.
  select case p_action
    when 'read_capture' then bi_is_ops() or bi_my_roles(p_tenant, p_company) && array['inspector','assistant','company_admin']
    when 'write_capture' then bi_my_roles(p_tenant, p_company) && array['inspector']
    when 'write_capture_assistant' then bi_my_roles(p_tenant, p_company) && array['inspector','assistant']
    when 'read_report_draft' then bi_is_ops() or bi_my_roles(p_tenant, p_company) && array['inspector','company_admin']
    when 'read_report_issued' then bi_is_ops() or bi_my_roles(p_tenant, p_company) && array['inspector','assistant','company_admin']
    when 'read_wallet' then bi_is_ops() or bi_my_roles(p_tenant, p_company) && array['inspector','company_admin']
    when 'manage_company' then bi_my_roles(p_tenant, p_company) && array['company_admin']
    else false end;
$$;
comment on function bi_can is 'BI-CORE-01. RLS decisions: read_capture (ops, inspector, assistant, company_admin), write_capture (inspector), write_capture_assistant (inspector, assistant), read_report_draft (ops, inspector, company_admin), read_report_issued (adds assistant), read_wallet (ops, inspector, company_admin), manage_company (company_admin). Other tenants and anon: nothing.';

create function bi_can_company(p_company uuid, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- Company level rows (the sites tree, equipment, the onboarding record) are
  -- shared by every tenant with a live line on the company; the signed in
  -- person's own tenant decides.
  select bi_can(bi_my_tenant(), p_company, p_action);
$$;
comment on function bi_can_company is 'BI-CORE-01. bi_can for company level rows (sites tree, equipment, bi_company), evaluated in the signed in person''s tenant.';

-- 12. Row Level Security --------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['bi_tenant','bi_company','bi_company_subscription','bi_app_user','bi_role_assignment',
                           'bi_inspector_profile','bi_inspector_qualification','bi_fica_record','bi_consent_record',
                           'bi_audit_log','bi_feature_flag','bi_rate_event','bi_step_up'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;

grant select on bi_tenant, bi_company, bi_company_subscription, bi_app_user, bi_role_assignment,
                bi_inspector_profile, bi_consent_record, bi_audit_log, bi_feature_flag to authenticated;

create policy bi_tenant_read on bi_tenant for select to authenticated
  using (bi_is_ops() or id = bi_my_tenant());
create policy bi_company_read on bi_company for select to authenticated
  using (bi_can_company(client_account_id, 'read_capture'));
create policy bi_company_subscription_read on bi_company_subscription for select to authenticated
  using (bi_can(tenant_id, client_account_id, 'read_wallet'));
create policy bi_app_user_read on bi_app_user for select to authenticated
  using (bi_is_ops() or auth_user_id = auth.uid() or (tenant_id = bi_my_tenant() and bi_my_tenant_manager()));
create policy bi_role_assignment_read on bi_role_assignment for select to authenticated
  using (bi_is_ops() or app_user_id = bi_my_app_user_id()
         or (client_account_id is not null and bi_can(tenant_id, client_account_id, 'manage_company')));
create policy bi_inspector_profile_read on bi_inspector_profile for select to authenticated
  using (bi_is_ops() or app_user_id = bi_my_app_user_id());
create policy bi_consent_record_read on bi_consent_record for select to authenticated
  using (bi_is_ops() or auth_user_id = auth.uid());
create policy bi_audit_log_read on bi_audit_log for select to authenticated
  using (bi_is_ops() or (client_account_id is not null and bi_can_company(client_account_id, 'manage_company')));
create policy bi_feature_flag_read on bi_feature_flag for select to authenticated
  using (tenant_id is null or tenant_id = bi_my_tenant() or bi_is_ops());
-- bi_inspector_qualification, bi_fica_record, bi_rate_event and bi_step_up: no
-- authenticated policy at all. Qualifications and FICA are read through the
-- audited functions below; rate and step up rows are server side only.

-- 13. Functions (server side: service role only unless stated) ---------------------------------

create function bi_app_user_of(p_auth_user uuid)
returns bi_app_user
language sql
stable
security definer
set search_path = public
as $$
  select u.* from bi_app_user u where p_auth_user is not null and u.auth_user_id = p_auth_user and u.status = 'active';
$$;
comment on function bi_app_user_of is 'BI-CORE-01. The active Bee-Inspect profile of an auth user, or null.';

create function bi_step_up_record(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_method text := p ->> 'method';
  v_aal text := p ->> 'aal';
  v_at timestamptz;
  v_ref text := p ->> 'session_ref';
  v_purpose text := p ->> 'purpose';
  v_id uuid;
begin
  if p_auth_user is null or not exists (select 1 from auth.users where id = p_auth_user) then
    raise exception 'bi_step_up_record: unknown user' using errcode = '28000';
  end if;
  if v_aal is distinct from 'aal2' or v_method not in ('totp','phone') then
    raise exception 'Step up verification needs a second factor (an authenticator code or an SMS code).' using errcode = '28000';
  end if;
  begin
    v_at := to_timestamp((p ->> 'asserted_epoch')::double precision);
  exception when others then
    raise exception 'bi_step_up_record: asserted_epoch must be a number of seconds' using errcode = '22023';
  end;
  if v_at > now() + interval '1 minute' or v_at < now() - make_interval(mins => coalesce(msp_env_get_int('bi.step_up_window_minutes'), 10)) then
    raise exception 'The second factor was verified too long ago. Please verify it again.' using errcode = '28000';
  end if;
  if v_ref is null or v_ref !~ '^[0-9a-f]{64}$' then
    raise exception 'bi_step_up_record: session_ref must be a SHA 256 hex' using errcode = '22023';
  end if;
  insert into bi_step_up (auth_user_id, purpose, method, aal, asserted_at, session_ref, report_id)
  values (p_auth_user, v_purpose, v_method, v_aal, v_at, v_ref, nullif(p ->> 'report_id', '')::uuid)
  returning id into v_id;
  perform bi_audit(p_auth_user, 'step_up_recorded', (bi_app_user_of(p_auth_user)).tenant_id, null, 'step_up', v_id,
                   jsonb_build_object('purpose', v_purpose, 'method', v_method));
  return jsonb_build_object('step_up_id', v_id, 'purpose', v_purpose, 'asserted_at', v_at);
end;
$$;
comment on function bi_step_up_record is 'BI-CORE-01 (prompt B3). Records a step up MFA assertion after the Edge Function has verified the caller''s JWT: p = {purpose, method (the amr method: totp or phone), aal (must be aal2), asserted_epoch (the amr timestamp), session_ref (SHA 256 of the session id), report_id?}. Refuses an assertion older than bi.step_up_window_minutes. Audited.';

create function bi_fica_list(p_auth_user uuid, p_client_account_id uuid, p_app_user_id uuid)
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
  if (p_client_account_id is null) = (p_app_user_id is null) then
    raise exception 'bi_fica_list: name a company or an inspector' using errcode = '22023';
  end if;
  if not v_ops then
    if p_app_user_id is not null and (v_me.id is null or v_me.id <> p_app_user_id) then
      raise exception 'Not permitted.' using errcode = '42501';
    end if;
    if p_client_account_id is not null
       and not ('company_admin' = any(bi_user_roles(p_auth_user, v_me.tenant_id, p_client_account_id))) then
      raise exception 'Not permitted.' using errcode = '42501';
    end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'subject_kind', f.subject_kind, 'document_kind', f.document_kind,
           'document_path', f.document_path, 'status', f.status, 'reviewed_at', f.reviewed_at, 'created_at', f.created_at)
           order by f.created_at), '[]'::jsonb)
    into v_rows
    from bi_fica_record f
   where (p_client_account_id is not null and f.client_account_id = p_client_account_id)
      or (p_app_user_id is not null and f.app_user_id = p_app_user_id);
  -- Prompt section 8: every FICA read is audited, one row per record returned.
  insert into bi_audit_log (actor_auth_user, actor_label, tenant_id, client_account_id, event, object_kind, object_id, detail)
  select p_auth_user, coalesce((select email from auth.users where id = p_auth_user), 'user'), v_me.tenant_id,
         f.client_account_id, 'fica_read', 'fica_record', f.id, jsonb_build_object('as_ops', v_ops)
    from bi_fica_record f
   where (p_client_account_id is not null and f.client_account_id = p_client_account_id)
      or (p_app_user_id is not null and f.app_user_id = p_app_user_id);
  return v_rows;
end;
$$;
comment on function bi_fica_list is 'BI-CORE-01 (prompt section 8). The only read path to FICA records for a person: ops, the inspector for their own records, or the company_admin for their company. Each record returned is audited as fica_read.';

create function bi_qualification_list(p_auth_user uuid, p_app_user_id uuid)
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
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'qual_type', q.qual_type, 'issuer', q.issuer, 'number', q.number,
           'issued_on', q.issued_on, 'expires_on', q.expires_on, 'status', q.status, 'document_path', q.document_path)
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
comment on function bi_qualification_list is 'BI-CORE-01 (prompt section 8). The only read path to qualifications for a person: ops or the inspector themself. Each record returned is audited as qualification_read.';

create function bi_company_set_status(p_auth_user uuid, p_client_account_id uuid, p_status text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c bi_company;
begin
  if not bi_user_is_ops(p_auth_user) then
    raise exception 'Only Care Net can change a company''s onboarding status.' using errcode = '42501';
  end if;
  select * into v_c from bi_company where client_account_id = p_client_account_id for update;
  if v_c.client_account_id is null then
    raise exception 'That company was not found.' using errcode = 'P0002';
  end if;
  update bi_company
     set onboarding_status = p_status,
         blocked_reason = case when p_status = 'blocked' then p_reason end,
         activated_at = case when p_status = 'active' then coalesce(activated_at, now()) else activated_at end,
         activated_by = case when p_status = 'active' then coalesce((select email from auth.users where id = p_auth_user), 'ops') else activated_by end
   where client_account_id = p_client_account_id;
  perform bi_audit(p_auth_user, 'company_status_set', null, p_client_account_id, 'company', p_client_account_id,
                   jsonb_build_object('from', v_c.onboarding_status, 'to', p_status));
  return jsonb_build_object('client_account_id', p_client_account_id, 'onboarding_status', p_status);
end;
$$;
comment on function bi_company_set_status is 'BI-CORE-01 (prompt B4). Ops moves a company through Not started, In review, Active, Blocked (a block needs a reason). Audited.';

create function bi_inspector_set_status(p_auth_user uuid, p_app_user_id uuid, p_status text, p jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old bi_inspector_profile;
  v_scope text[];
begin
  if not bi_user_is_ops(p_auth_user) then
    raise exception 'Only Care Net clears an inspector.' using errcode = '42501';
  end if;
  select * into v_old from bi_inspector_profile where app_user_id = p_app_user_id for update;
  if v_old.app_user_id is null then
    raise exception 'That inspector was not found.' using errcode = 'P0002';
  end if;
  if p_status = 'cleared' and exists (select 1 from bi_inspector_qualification q
                                        where q.app_user_id = p_app_user_id and q.status = 'expired') then
    raise exception 'An expired qualification must be renewed before clearance.';
  end if;
  if p ? 'competence_scope' then
    select coalesce(array_agg(x), '{}') into v_scope from jsonb_array_elements_text(p -> 'competence_scope') x;
  end if;
  update bi_inspector_profile
     set status = p_status,
         competence_scope = coalesce(v_scope, competence_scope),
         cleared_at = case when p_status = 'cleared' then now() else cleared_at end,
         cleared_by = case when p_status = 'cleared' then coalesce((select email from auth.users where id = p_auth_user), 'ops') else cleared_by end,
         restricted_reason = case when p_status = 'restricted' then p ->> 'reason' else null end
   where app_user_id = p_app_user_id;
  perform bi_audit(p_auth_user, 'inspector_status_set', (select tenant_id from bi_app_user where id = p_app_user_id), null,
                   'inspector_profile', p_app_user_id, jsonb_build_object('from', v_old.status, 'to', p_status));
  return jsonb_build_object('app_user_id', p_app_user_id, 'status', p_status);
end;
$$;
comment on function bi_inspector_set_status is 'BI-CORE-01 (prompt B4). Ops moves an inspector along Identity, FICA, Qualifications, Competence review, Cleared | Restricted | Assistant only, and sets the competence scope. Clearance is refused while a qualification is expired. Audited.';

create function bi_role_grant(p_auth_user uuid, p_app_user_id uuid, p_role text, p_client_account_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target bi_app_user;
  v_me bi_app_user;
  v_id uuid;
  v_ops boolean := bi_user_is_ops(p_auth_user) or p_auth_user is null;
begin
  select * into v_target from bi_app_user where id = p_app_user_id;
  if v_target.id is null then
    raise exception 'That person was not found.' using errcode = 'P0002';
  end if;
  if p_role = 'ops' then
    if p_auth_user is not null then
      raise exception 'Only the service role grants ops.' using errcode = '42501';
    end if;
  elsif not v_ops then
    -- A company admin grants inspector, assistant or company_admin on their own
    -- company, within their own tenant.
    v_me := bi_app_user_of(p_auth_user);
    if p_client_account_id is null or v_me.id is null or v_me.tenant_id <> v_target.tenant_id
       or not ('company_admin' = any(bi_user_roles(p_auth_user, v_me.tenant_id, p_client_account_id))) then
      raise exception 'Not permitted.' using errcode = '42501';
    end if;
  end if;
  insert into bi_role_assignment (app_user_id, tenant_id, client_account_id, role, granted_by)
  values (p_app_user_id, case when p_role = 'ops' then null else v_target.tenant_id end,
          case when p_role = 'ops' then null else p_client_account_id end, p_role,
          coalesce((select email from auth.users where id = p_auth_user), 'service_role'))
  returning id into v_id;
  perform bi_audit(p_auth_user, 'role_granted', v_target.tenant_id, p_client_account_id, 'role_assignment', v_id,
                   jsonb_build_object('role', p_role, 'app_user_id', p_app_user_id));
  return jsonb_build_object('role_assignment_id', v_id);
end;
$$;
comment on function bi_role_grant is 'BI-CORE-01. Grants a role. Ops only through the service role (p_auth_user null); ops staff grant any other role; a company admin grants inspector, assistant or company_admin on their own company in their own tenant. Audited.';

create function bi_role_revoke(p_auth_user uuid, p_role_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_a bi_role_assignment;
  v_me bi_app_user;
begin
  select * into v_a from bi_role_assignment where id = p_role_assignment_id and revoked_at is null for update;
  if v_a.id is null then
    raise exception 'That role was not found.' using errcode = 'P0002';
  end if;
  if p_auth_user is not null and not bi_user_is_ops(p_auth_user) then
    v_me := bi_app_user_of(p_auth_user);
    if v_a.role = 'ops' or v_a.client_account_id is null or v_me.id is null
       or not ('company_admin' = any(bi_user_roles(p_auth_user, v_me.tenant_id, v_a.client_account_id))) then
      raise exception 'Not permitted.' using errcode = '42501';
    end if;
  end if;
  update bi_role_assignment set revoked_at = now(),
         revoked_by = coalesce((select email from auth.users where id = p_auth_user), 'service_role')
   where id = v_a.id;
  perform bi_audit(p_auth_user, 'role_revoked', v_a.tenant_id, v_a.client_account_id, 'role_assignment', v_a.id,
                   jsonb_build_object('role', v_a.role));
  return jsonb_build_object('role_assignment_id', v_a.id, 'revoked', true);
end;
$$;
comment on function bi_role_revoke is 'BI-CORE-01. Revokes a role (never deletes). Same callers as bi_role_grant. Audited.';

-- 14. Grants on functions ----------------------------------------------------------------------------

do $$
declare
  f text;
begin
  -- RLS helpers: the policies run them for authenticated.
  foreach f in array array['bi_is_ops()','bi_my_roles(uuid, uuid)','bi_my_tenant()','bi_can(uuid, uuid, text)',
                           'bi_can_company(uuid, text)','bi_my_app_user_id()','bi_my_tenant_manager()',
                           'bi_user_active_in_tenant(uuid, uuid)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  -- Server side only.
  foreach f in array array['bi_audit(uuid, text, uuid, uuid, text, uuid, jsonb)','bi_flag_enabled(text, uuid)',
                           'bi_rate_allow(text, text, int, int)','bi_user_is_ops(uuid)','bi_subscription_live(uuid, uuid)',
                           'bi_user_roles(uuid, uuid, uuid)','bi_app_user_of(uuid)','bi_step_up_record(uuid, jsonb)',
                           'bi_fica_list(uuid, uuid, uuid)','bi_qualification_list(uuid, uuid)',
                           'bi_company_set_status(uuid, uuid, text, text)','bi_inspector_set_status(uuid, uuid, text, jsonb)',
                           'bi_role_grant(uuid, uuid, text, uuid)','bi_role_revoke(uuid, uuid)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array['bi_touch()','bi_append_only()','bi_role_assignment_guard()',
                           'bi_consent_guard()','bi_step_up_guard()'] loop
    execute format('revoke execute on function %s from public, anon', f);
  end loop;
end;
$$;
-- Guards run as the client (so they can tell a client from a trusted path) and
-- call this helper, so authenticated keeps execute on it.
revoke execute on function bi_is_client_session() from public, anon;
grant execute on function bi_is_client_session() to authenticated, service_role;

notify pgrst, 'reload schema';
