-- CNC MSP FORGE | HSF-UPL-01 v1.0.0 | HSF consent, staging uploads and MCO transfer bookkeeping 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 3 (049) and section 1 (constants).
--
-- What this migration does:
--   1. hsf_consent: three separate POPIA consents per company account
--      (document_storage, mco_transfer, authority_to_share), wording version
--      HSF-CONSENT-1.0. A consent row is never deleted; withdrawal stamps
--      withdrawn_at once.
--   2. hsf_upload: one row per file a client drops into the builder. The bytes
--      live in the private Storage bucket hsf-staging (never in the Secrets
--      store, which holds credentials) until the transfer worker has handed them
--      to MyClinicOnline, then the bytes are removed and the row stays, with both
--      SHA 256 fingerprints, for the audit trail.
--   3. hsf_mco_transfer: the append only log of every transfer attempt.
--   4. The hsf-staging bucket (private, 25 MB, the contract mime list) with no
--      storage.objects policy for anon or authenticated: service role only.
--   5. Parameters hsf.upload_max_bytes, hsf.upload_allowed_mime,
--      hsf.mco_transfer_mode and hsf.staging_alert_days (category hsf).
--   6. The functions the web tier and the transfer worker call. Every one is
--      security definer with a fixed search path and is executable by the
--      service role only; the web tier verifies the person's access token first
--      and passes their auth user id.
--   7. Contract 9.1 and 9.5 (Amendment 1): hsf_link_account links a signed in
--      person to the company account of their confirmed email; the worker reads
--      its mode through hsf_transfer_mode, claims work with hsf_transfer_claim,
--      removes staged bytes listed by hsf_transfer_cleanup_queue, and stale
--      registrations are swept by hsf_sweep_stale_uploads. Uploads older than
--      hsf.staging_alert_days show in hsf_staging_alerts for staff. A withdrawn
--      mco_transfer or document_storage consent blocks the account's
--      untransferred uploads; nothing is deleted automatically.
--
-- Nothing here writes file content, a key or a token to msp_audit. The MCO
-- interface contract is pending (HSF-3): no MCO endpoint is named here.

-- 1. Parameter category -------------------------------------------------------------
-- Migration 034 limited msp_env_parameter.category to six values. The contract
-- files the HSF parameters under 'hsf', so the check gains that one value.
do $$
declare
  v_name text;
begin
  select c.conname into v_name
    from pg_constraint c
   where c.conrelid = 'public.msp_env_parameter'::regclass
     and c.contype = 'c'
     and pg_get_constraintdef(c.oid) ilike '%category%';
  if v_name is not null then
    execute format('alter table msp_env_parameter drop constraint %I', v_name);
  end if;
end;
$$;
alter table msp_env_parameter add constraint msp_env_parameter_category_check
  check (category in ('ai','agent','clinical','commercial','retention','integration','hsf'));

insert into msp_env_parameter (key, value, value_type, allowed_values, min_value, max_value, category, description, updated_by) values
  ('hsf.upload_max_bytes', '26214400', 'integer', null, 1, 26214400, 'hsf',
   'Largest file a client may upload into the Health and Safety File builder, in bytes (25 MB). The hsf-staging bucket enforces the same ceiling, so this can be lowered here but not raised past it.',
   'migration_049'),
  ('hsf.upload_allowed_mime', 'application/pdf,image/jpeg,image/png,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/msword,application/vnd.ms-excel,text/csv', 'text', null, null, null, 'hsf',
   'Comma separated file types the builder accepts (PDF, JPEG, PNG, Word, Excel and CSV). Any type added here must also be added to the hsf-staging bucket.',
   'migration_049'),
  ('hsf.mco_transfer_mode', 'hold', 'enum', array['hold','fixture','live'], null, null, 'hsf',
   'How the transfer worker treats staged uploads. hold: keep them in Care Net staging and send nothing. fixture: test adapter only. live: pending the MyClinicOnline interface contract (HSF-3).',
   'migration_049'),
  ('hsf.staging_alert_days', '14', 'integer', null, 1, 365, 'hsf',
   'Days an upload may wait in Care Net staging before staff are alerted to move it to MyClinicOnline.',
   'migration_049')
on conflict (key) do nothing;

-- 2. Tables -------------------------------------------------------------------------

create table hsf_consent (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  auth_user_id uuid not null,
  consent_kind text not null check (consent_kind in ('document_storage','mco_transfer','authority_to_share')),
  granted boolean not null,
  wording_version text not null,
  granted_at timestamptz not null default now(),
  withdrawn_at timestamptz
);
comment on table hsf_consent is 'HSF-UPL-01. Unbundled POPIA consents for the Health and Safety File builder: document_storage (Care Net holds the documents in its secure staging store), mco_transfer (the documents move to MyClinicOnline), authority_to_share (the person may share them for the company). A consent is current when the latest row of its kind is granted and not withdrawn. Rows are never deleted; withdrawal stamps withdrawn_at once.';
create index hsf_consent_account_idx on hsf_consent(client_account_id, consent_kind, granted_at desc);

create table hsf_upload (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  auth_user_id uuid not null,
  file_id uuid references hsf_file(id),
  file_item_id uuid references hsf_file_item(id),
  section_code text references hsf_section(code),
  department_code text not null references hsf_department(code),
  original_name text not null,
  safe_name text not null check (safe_name ~ '^[A-Za-z0-9._]{1,120}$'),
  mime_type text not null,
  size_bytes bigint not null check (size_bytes > 0),
  sha256_client text not null check (sha256_client ~ '^[0-9a-f]{64}$'),
  sha256_server text check (sha256_server ~ '^[0-9a-f]{64}$'),
  storage_bucket text not null default 'hsf-staging',
  storage_path text,
  status text not null default 'awaiting_upload' check (status in
    ('awaiting_upload','uploaded','verified','held','transferring','transferred','staging_deleted','rejected','failed')),
  reject_reason text,
  mco_document_ref text,
  transfer_blocked_reason text,
  transfer_claimed_at timestamptz,
  created_at timestamptz not null default now(),
  uploaded_at timestamptz,
  verified_at timestamptz,
  transferred_at timestamptz,
  staging_deleted_at timestamptz,
  check (status <> 'staging_deleted' or (storage_path is null and staging_deleted_at is not null)),
  check (status not in ('transferred','staging_deleted') or (mco_document_ref is not null and transferred_at is not null))
);
comment on table hsf_upload is 'HSF-UPL-01. One row per document a client drops into the builder. The bytes sit in the private hsf-staging bucket at <client_account_id>/<upload_id>/<safe_name> until they are transferred to MyClinicOnline and removed; the row, with the browser and server SHA 256 fingerprints, stays for the audit trail. Lifecycle: awaiting_upload, uploaded, held, transferred, staging_deleted (or rejected, failed).';
create index hsf_upload_account_idx on hsf_upload(client_account_id, created_at desc);
create index hsf_upload_file_idx on hsf_upload(file_id);
create index hsf_upload_item_idx on hsf_upload(file_item_id);
create index hsf_upload_queue_idx on hsf_upload(status, uploaded_at) where status in ('uploaded','held','transferring');
create index hsf_upload_staged_idx on hsf_upload(status) where storage_path is not null;
comment on column hsf_upload.transfer_blocked_reason is 'Contract 9.5. Set to ''consent withdrawn'' on every untransferred upload of the account when its mco_transfer or document_storage consent is withdrawn. A blocked upload is never claimed for transfer. Nothing is deleted automatically: what happens to the staged bytes is a Director and Information Officer decision (register item).';
comment on column hsf_upload.transfer_claimed_at is 'Contract 9.5. When hsf_transfer_claim last moved the upload to transferring. A transferring upload claimed more than 30 minutes ago is claimed again.';

create table hsf_mco_transfer (
  id bigint generated always as identity primary key,
  upload_id uuid not null references hsf_upload(id),
  mode text not null check (mode in ('hold','fixture','live')),
  outcome text not null check (outcome in ('held','received','hash_mismatch','error')),
  mco_document_ref text,
  mco_receipt_sha256 text check (mco_receipt_sha256 ~ '^[0-9a-f]{64}$'),
  error text,
  created_at timestamptz not null default now()
);
comment on table hsf_mco_transfer is 'HSF-UPL-01. Append only log of every attempt to move a staged upload to MyClinicOnline: the mode, the outcome, the MyClinicOnline reference and receipt fingerprint when received, and a short error text. Never the file content.';
create index hsf_mco_transfer_upload_idx on hsf_mco_transfer(upload_id, created_at);

-- The evidence ledger (047) records the upload it came through.
alter table hsf_evidence
  add constraint hsf_evidence_upload_fk foreign key (upload_id) references hsf_upload(id);

-- 3. Guards -------------------------------------------------------------------------

create or replace function hsf_mco_transfer_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'hsf_mco_transfer is append only';
end;
$$;
create trigger hsf_mco_transfer_append_only
  before update or delete on hsf_mco_transfer
  for each row execute function hsf_mco_transfer_guard();

create or replace function hsf_consent_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'hsf_consent rows are never deleted; withdraw the consent instead';
  end if;
  if (to_jsonb(new) - 'withdrawn_at') is distinct from (to_jsonb(old) - 'withdrawn_at')
     or old.withdrawn_at is not null or new.withdrawn_at is null then
    raise exception 'hsf_consent: only a withdrawal may be recorded, once';
  end if;
  return new;
end;
$$;
create trigger hsf_consent_append_only
  before update or delete on hsf_consent
  for each row execute function hsf_consent_guard();

create or replace function hsf_upload_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'hsf_upload rows are kept for the audit trail and are never deleted';
end;
$$;
create trigger hsf_upload_no_delete
  before delete on hsf_upload
  for each row execute function hsf_upload_guard();

revoke execute on function hsf_mco_transfer_guard() from public, anon, authenticated;
revoke execute on function hsf_consent_guard() from public, anon, authenticated;
revoke execute on function hsf_upload_guard() from public, anon, authenticated;

-- 4. Row Level Security ---------------------------------------------------------------

create or replace function hsf_can_read_account(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select hsf_is_staff()
      or exists (select 1 from msp_client_account a
                  where a.id = p_account_id
                    and auth.uid() is not null
                    and a.auth_user_id = auth.uid());
$$;
revoke execute on function hsf_can_read_account(uuid) from public, anon;
grant execute on function hsf_can_read_account(uuid) to authenticated;
comment on function hsf_can_read_account is 'RLS helper: staff, or the client contact of the account.';

do $$
declare
  t text;
begin
  foreach t in array array['hsf_consent','hsf_upload','hsf_mco_transfer'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;

create policy hsf_consent_read on hsf_consent
  for select to authenticated using (hsf_can_read_account(client_account_id));
create policy hsf_upload_read on hsf_upload
  for select to authenticated using (hsf_can_read_account(client_account_id));
create policy hsf_mco_transfer_read on hsf_mco_transfer
  for select to authenticated using (
    exists (select 1 from hsf_upload u where u.id = upload_id and hsf_can_read_account(u.client_account_id)));

-- 5. Storage bucket -------------------------------------------------------------------
-- Private, encrypted at rest by the platform, 25 MB, the contract mime list. No
-- storage.objects policy is created for this bucket: anon and authenticated
-- cannot read, list or write it; the service role signs one upload URL per
-- registered upload and the transfer worker reads and removes the object.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('hsf-staging', 'hsf-staging', false, 26214400, array[
  'application/pdf','image/jpeg','image/png',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/msword','application/vnd.ms-excel','text/csv'])
on conflict (id) do nothing;

-- 6. Internal helpers (never callable from outside) -------------------------------------

create or replace function hsf_consent_wording_version()
returns text
language sql
immutable
set search_path = public
as $$ select 'HSF-CONSENT-1.0'::text $$;
comment on function hsf_consent_wording_version is 'The current consent wording version (contract section 1). A consent recorded under any other version is refused.';

create or replace function hsf_account_of(p_auth_user uuid)
returns msp_client_account
language sql
stable
security definer
set search_path = public
as $$
  select a.* from msp_client_account a where p_auth_user is not null and a.auth_user_id = p_auth_user limit 1;
$$;
comment on function hsf_account_of is 'The company account whose contact is this auth user, or null.';

-- Contract 9.1. Company accounts are created by msp_client_signon from a typed
-- email, without a sign in, so they carry no auth user. The web tier calls this
-- once per request after it has verified the access token: an account already
-- linked to the person is returned; otherwise the latest account that is not
-- declined, has no auth user yet and whose contact email equals the person's
-- confirmed Supabase email is linked and returned. An unconfirmed email links
-- nothing.
create or replace function hsf_link_account(p_auth_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_email text;
begin
  if p_auth_user is null then
    return null;
  end if;
  -- One link at a time per person, so two parallel requests never race.
  perform pg_advisory_xact_lock(hashtext('hsf_link_account'), hashtext(p_auth_user::text));
  select a.id into v_id from msp_client_account a where a.auth_user_id = p_auth_user;
  if v_id is not null then
    return v_id;
  end if;
  select lower(btrim(u.email)) into v_email
    from auth.users u
   where u.id = p_auth_user and u.email_confirmed_at is not null;
  if coalesce(v_email, '') = '' then
    return null;
  end if;
  select a.id into v_id
    from msp_client_account a
   where lower(btrim(a.contact_email)) = v_email
     and a.auth_user_id is null
     and a.account_kind <> 'declined'
   order by a.created_at desc, a.id desc
   limit 1
   for update;
  if v_id is null then
    return null;
  end if;
  update msp_client_account set auth_user_id = p_auth_user where id = v_id and auth_user_id is null;
  if not found then
    return (select a.id from msp_client_account a where a.auth_user_id = p_auth_user);
  end if;
  insert into msp_audit (actor, event_type, event_detail)
  values (v_email, 'client_auth_linked',
          jsonb_build_object('client_account_id', v_id, 'auth_user_id', p_auth_user));
  return v_id;
end;
$$;
comment on function hsf_link_account is 'Contract 9.1. Returns the company account linked to the auth user, linking on first use the latest non declined account with no auth user whose contact email equals the user''s confirmed email. Null when there is none. Service role only; vercel/lib/auth.js requireUser calls it after verifying the token. Audited as client_auth_linked.';

create or replace function hsf_user_email(p_auth_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select u.email from auth.users u where u.id = p_auth_user),
                  (select a.contact_email from msp_client_account a where a.auth_user_id = p_auth_user limit 1));
$$;
comment on function hsf_user_email is 'The email of the auth user, used as the audit actor and as hsf_evidence.supplied_by.';

create or replace function hsf_consent_current(p_account_id uuid, p_kind text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select c.granted and c.withdrawn_at is null
                     from hsf_consent c
                    where c.client_account_id = p_account_id and c.consent_kind = p_kind
                    order by c.granted_at desc, c.id desc
                    limit 1), false);
$$;
comment on function hsf_consent_current is 'True when the latest consent row of this kind for the account is granted and not withdrawn.';

create or replace function hsf_consent_complete(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select hsf_consent_current(p_account_id, 'document_storage')
     and hsf_consent_current(p_account_id, 'mco_transfer')
     and hsf_consent_current(p_account_id, 'authority_to_share');
$$;

create or replace function hsf_safe_name(p_name text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v text := btrim(coalesce(p_name, ''));
  v_ext text;
  v_base text;
begin
  -- The extension (letters and digits after the last dot) is kept in lower case.
  -- In the rest of the name every run of anything but a letter or a digit becomes
  -- one underscore, so the only dot left is the one before the extension and no
  -- path segment such as .. can survive.
  v_ext := lower(substring(v from '\.([A-Za-z0-9]{1,10})$'));
  v_base := case when v_ext is null then v else left(v, length(v) - length(v_ext) - 1) end;
  v_base := btrim(regexp_replace(v_base, '[^A-Za-z0-9]+', '_', 'g'), '_');
  if v_base = '' then
    v_base := 'document';
  end if;
  if v_ext is null then
    return left(v_base, 120);
  end if;
  return btrim(left(v_base, 120 - length(v_ext) - 1), '_') || '.' || v_ext;
end;
$$;
comment on function hsf_safe_name is 'Storage safe file name: letters, digits, dot and underscore only, at most 120 characters, extension kept.';

do $$
declare
  f text;
begin
  foreach f in array array['hsf_consent_wording_version()','hsf_account_of(uuid)','hsf_user_email(uuid)',
                           'hsf_consent_current(uuid, text)','hsf_consent_complete(uuid)','hsf_safe_name(text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- 7. Consent ----------------------------------------------------------------------------

create or replace function hsf_consent_status(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_ds boolean := false;
  v_mt boolean := false;
  v_as boolean := false;
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is not null then
    v_ds := hsf_consent_current(v_acc.id, 'document_storage');
    v_mt := hsf_consent_current(v_acc.id, 'mco_transfer');
    v_as := hsf_consent_current(v_acc.id, 'authority_to_share');
  end if;
  return jsonb_build_object(
    'client_account_id', v_acc.id,
    'company_name', v_acc.company_name,
    'wording_version', hsf_consent_wording_version(),
    'document_storage', v_ds,
    'mco_transfer', v_mt,
    'authority_to_share', v_as,
    'complete', v_ds and v_mt and v_as);
end;
$$;
comment on function hsf_consent_status is 'Contract 049. The three builder consents of the auth user''s company account. true means the latest row of that kind is granted and not withdrawn; complete means all three.';

create or replace function hsf_record_consent(p_auth_user uuid, p_kinds text[], p_wording_version text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_kind text;
  v_kinds text[];
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before giving consent.';
  end if;
  if p_wording_version is distinct from hsf_consent_wording_version() then
    raise exception 'The consent wording has changed. Please read the current wording (%) and give your consent again.', hsf_consent_wording_version();
  end if;
  select array_agg(distinct k order by k) into v_kinds from unnest(coalesce(p_kinds, '{}'::text[])) k;
  if v_kinds is null then
    raise exception 'Choose at least one consent to record.';
  end if;
  foreach v_kind in array v_kinds loop
    if v_kind is null or v_kind not in ('document_storage','mco_transfer','authority_to_share') then
      raise exception 'Unknown consent kind: %', coalesce(v_kind, 'none');
    end if;
  end loop;
  foreach v_kind in array v_kinds loop
    insert into hsf_consent (client_account_id, auth_user_id, consent_kind, granted, wording_version, granted_at)
    values (v_acc.id, p_auth_user, v_kind, true, p_wording_version, clock_timestamp());
  end loop;
  insert into msp_audit (actor, event_type, event_detail)
  values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_consent_recorded',
          jsonb_build_object('client_account_id', v_acc.id, 'kinds', to_jsonb(v_kinds),
                             'wording_version', p_wording_version));
  return hsf_consent_status(p_auth_user);
end;
$$;
comment on function hsf_record_consent is 'Contract 049. Records one granted row per consent kind under the current wording version. Refuses unknown kinds and any other wording version. Audited.';

create or replace function hsf_withdraw_consent(p_auth_user uuid, p_kind text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_id uuid;
  v_blocked int := 0;
begin
  if p_kind is null or p_kind not in ('document_storage','mco_transfer','authority_to_share') then
    raise exception 'Unknown consent kind: %', coalesce(p_kind, 'none');
  end if;
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'No company account is linked to this sign in.';
  end if;
  select c.id into v_id
    from hsf_consent c
   where c.client_account_id = v_acc.id and c.consent_kind = p_kind
   order by c.granted_at desc, c.id desc
   limit 1;
  if v_id is not null then
    update hsf_consent set withdrawn_at = clock_timestamp()
     where id = v_id and granted and withdrawn_at is null;
    if found then
      -- Contract 9.5: without storage or transfer consent nothing more moves.
      -- Untransferred uploads are blocked from the transfer claim; nothing is
      -- deleted automatically (Director and Information Officer decision).
      if p_kind in ('mco_transfer','document_storage') then
        update hsf_upload
           set transfer_blocked_reason = 'consent withdrawn'
         where client_account_id = v_acc.id
           and transfer_blocked_reason is null
           and status in ('uploaded','verified','held','transferring');
        get diagnostics v_blocked = row_count;
      end if;
      insert into msp_audit (actor, event_type, event_detail)
      values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_consent_withdrawn',
              jsonb_build_object('client_account_id', v_acc.id, 'kind', p_kind, 'blocked_uploads', v_blocked));
    end if;
  end if;
  return hsf_consent_status(p_auth_user);
end;
$$;
comment on function hsf_withdraw_consent is 'Contract 049 and 9.5. Withdraws one consent. New uploads stop at once. Withdrawing mco_transfer or document_storage sets transfer_blocked_reason = ''consent withdrawn'' on the account''s untransferred uploads, which are then never claimed for transfer; a later consent does not lift the block, and nothing is deleted automatically. Audited.';

-- 8. Uploads ----------------------------------------------------------------------------

create or replace function hsf_register_upload(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_file hsf_file;
  v_item_id uuid;
  v_element_section text;
  v_section text := nullif(btrim(coalesce(p ->> 'section_code', '')), '');
  v_dept text := nullif(btrim(coalesce(p ->> 'department_code', '')), '');
  v_element text := nullif(btrim(coalesce(p ->> 'element_code', '')), '');
  v_name text := btrim(coalesce(p ->> 'original_name', ''));
  v_mime text := lower(btrim(coalesce(p ->> 'mime_type', '')));
  v_size_txt text := btrim(coalesce(p ->> 'size_bytes', ''));
  v_size bigint;
  v_sha text := lower(btrim(coalesce(p ->> 'sha256', '')));
  v_max bigint;
  v_allowed text[];
  v_id uuid := gen_random_uuid();
  v_safe text;
  v_path text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'The upload details are missing.';
  end if;
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before uploading documents.';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'This company account cannot upload documents. Please WhatsApp a sales executive.';
  end if;
  if not hsf_consent_complete(v_acc.id) then
    raise exception 'All three consents are needed before any document is uploaded.';
  end if;

  if v_dept is null or not exists (select 1 from hsf_department d where d.code = v_dept) then
    raise exception 'Choose the department this document belongs to.';
  end if;
  if v_section is not null and not exists (select 1 from hsf_section s where s.code = v_section) then
    raise exception 'The File section must be a letter from A to O.';
  end if;

  if nullif(p ->> 'file_id', '') is not null then
    if (p ->> 'file_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'The File is not recognised.';
    end if;
    select f.* into v_file from hsf_file f where f.id = (p ->> 'file_id')::uuid;
    if v_file.id is null or v_file.client_account_id <> v_acc.id then
      raise exception 'The File is not recognised.';
    end if;
  end if;
  if v_element is not null then
    if v_file.id is null then
      raise exception 'An element upload must name the File it belongs to.';
    end if;
    select fi.id, e.section_code into v_item_id, v_element_section
      from hsf_file_item fi
      join hsf_element e on e.id = fi.element_id
     where fi.file_id = v_file.id and e.code = v_element
     order by fi.site_ref nulls first
     limit 1;
    if v_item_id is null then
      raise exception 'That element is not part of this File.';
    end if;
    if v_section is null then
      v_section := v_element_section;
    elsif v_section <> v_element_section then
      raise exception 'That element belongs to Section %, not Section %.', v_element_section, v_section;
    end if;
  end if;

  if v_name = '' or length(v_name) > 255 or v_name ~ '[[:cntrl:]]' then
    raise exception 'The file name must be between 1 and 255 printable characters.';
  end if;
  v_allowed := array(select lower(btrim(x)) from unnest(string_to_array(coalesce(msp_env_get('hsf.upload_allowed_mime'), ''), ',')) x
                      where btrim(x) <> '');
  if v_mime = '' or not (v_mime = any(v_allowed)) then
    raise exception 'That file type is not accepted. Upload a PDF, JPEG, PNG, Word, Excel or CSV file.';
  end if;
  if v_size_txt !~ '^[0-9]{1,15}$' then
    raise exception 'The file size is not valid.';
  end if;
  v_size := v_size_txt::bigint;
  v_max := coalesce(msp_env_get_int('hsf.upload_max_bytes'), 26214400);
  if v_size < 1 or v_size > v_max then
    raise exception 'The file is larger than the % MB limit.', round(v_max / 1048576.0, 1);
  end if;
  if v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'The SHA 256 fingerprint must be 64 hexadecimal characters.';
  end if;

  v_safe := hsf_safe_name(v_name);
  v_path := v_acc.id::text || '/' || v_id::text || '/' || v_safe;

  insert into hsf_upload (id, client_account_id, auth_user_id, file_id, file_item_id, section_code, department_code,
                          original_name, safe_name, mime_type, size_bytes, sha256_client, storage_bucket, storage_path)
  values (v_id, v_acc.id, p_auth_user, v_file.id, v_item_id, v_section, v_dept,
          v_name, v_safe, v_mime, v_size, v_sha, 'hsf-staging', v_path);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_upload_registered',
          jsonb_build_object('upload_id', v_id, 'client_account_id', v_acc.id, 'department_code', v_dept,
                             'section_code', v_section, 'element_code', v_element, 'mime_type', v_mime,
                             'size_bytes', v_size),
          v_file.id);

  return jsonb_build_object('upload_id', v_id, 'bucket', 'hsf-staging', 'path', v_path);
end;
$$;
comment on function hsf_register_upload is 'Contract 049. Registers one upload before the bytes move: consent complete, account not declined, department, section, File and element checked, type and size against hsf.upload_allowed_mime and hsf.upload_max_bytes. Returns the staging bucket and path for the signed upload URL. Audited (never the file name or content).';

create or replace function hsf_mark_uploaded(p_auth_user uuid, p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_email text;
  v_version int;
  v_prev uuid;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null or p_auth_user is null or v_up.auth_user_id <> p_auth_user then
    raise exception 'That upload was not found.';
  end if;
  if v_up.status <> 'awaiting_upload' then
    return jsonb_build_object('upload_id', v_up.id, 'status', v_up.status);
  end if;
  v_email := coalesce(hsf_user_email(p_auth_user), 'client');

  -- A consent withdrawn between registration and completion stops the upload.
  if not hsf_consent_complete(v_up.client_account_id) then
    update hsf_upload
       set status = 'rejected', reject_reason = 'Consent was withdrawn before the upload completed.'
     where id = v_up.id;
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values (v_email, 'hsf_upload_rejected',
            jsonb_build_object('upload_id', v_up.id, 'reason', 'consent_withdrawn'), v_up.file_id);
    return jsonb_build_object('upload_id', v_up.id, 'status', 'rejected');
  end if;

  update hsf_upload set status = 'uploaded', uploaded_at = now() where id = v_up.id;

  if v_up.file_item_id is not null then
    -- Serialise completes on one File item, so two uploads never pick the same
    -- evidence version (the second waits, then reads the committed maximum).
    perform 1 from hsf_file_item where id = v_up.file_item_id for update;
    select coalesce(max(e.version), 0) + 1 into v_version from hsf_evidence e where e.file_item_id = v_up.file_item_id;
    select e.id into v_prev from hsf_evidence e
     where e.file_item_id = v_up.file_item_id order by e.version desc limit 1;
    insert into hsf_evidence (file_item_id, version, supersedes_id, source, storage_path, sha256, supplied_by, upload_id)
    values (v_up.file_item_id, v_version, v_prev, 'client_upload', v_up.storage_path, v_up.sha256_client, v_email, v_up.id);
    update hsf_file_item set status = 'uploaded', reason = null where id = v_up.file_item_id;
    -- Keeps hsf_file.compliance_pct current and audits the change (migration 051).
    perform hsf_compute_compliance(v_up.file_id);
  end if;

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (v_email, 'hsf_upload_completed',
          jsonb_build_object('upload_id', v_up.id, 'file_item_id', v_up.file_item_id,
                             'evidence_version', v_version, 'sha256', v_up.sha256_client),
          v_up.file_id);

  return jsonb_build_object('upload_id', v_up.id, 'status', 'uploaded');
end;
$$;
comment on function hsf_mark_uploaded is 'Contract 049 and 9.5. awaiting_upload to uploaded, by the uploading person only. For an element upload it locks the File item, appends the hsf_evidence row (version n + 1, source client_upload, the browser hash), sets the item to uploaded and recomputes the compliance figure. A consent withdrawn in between rejects the upload instead. Audited.';

create or replace function hsf_my_uploads(p_auth_user uuid, p_file_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'upload_id', u.id,
           'file_id', u.file_id,
           'original_name', u.original_name,
           'department_code', u.department_code,
           'section_code', u.section_code,
           'element_code', e.code,
           'size_bytes', u.size_bytes,
           'mime_type', u.mime_type,
           'status', u.status,
           'reject_reason', u.reject_reason,
           'transfer_blocked_reason', u.transfer_blocked_reason,
           'created_at', u.created_at,
           'uploaded_at', u.uploaded_at,
           'transferred_at', u.transferred_at,
           'staging_deleted_at', u.staging_deleted_at,
           'mco_document_ref', u.mco_document_ref)
         order by u.created_at desc, u.id), '[]'::jsonb)
    from hsf_upload u
    join msp_client_account a on a.id = u.client_account_id
    left join hsf_file_item fi on fi.id = u.file_item_id
    left join hsf_element e on e.id = fi.element_id
   where p_auth_user is not null
     and a.auth_user_id = p_auth_user
     and (p_file_id is null or u.file_id = p_file_id);
$$;
comment on function hsf_my_uploads is 'Contract 049. The uploads of the auth user''s company account, newest first, optionally for one File.';

-- 9. Transfer worker ---------------------------------------------------------------------

create or replace function hsf_transfer_queue(p_limit int)
returns setof hsf_upload
language sql
stable
security definer
set search_path = public
as $$
  select u.*
    from hsf_upload u
   where u.status in ('uploaded','held')
     and u.storage_path is not null
     and u.transfer_blocked_reason is null
     and hsf_consent_current(u.client_account_id, 'mco_transfer')
     and hsf_consent_current(u.client_account_id, 'document_storage')
   order by u.uploaded_at nulls last, u.created_at, u.id
   limit greatest(1, least(coalesce(p_limit, 10), 100));
$$;
comment on function hsf_transfer_queue is 'Contract 049. A read only listing of uploads waiting for MyClinicOnline (uploaded or held), oldest first, at most 100; blocked uploads and accounts without mco_transfer and document_storage consent are skipped. The worker no longer reads it: it claims work with hsf_transfer_claim (contract 9.5).';

create or replace function hsf_transfer_mode()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case when v in ('hold','fixture','live') then v else 'hold' end
    from (select msp_env_get('hsf.mco_transfer_mode') as v) x;
$$;
comment on function hsf_transfer_mode is 'Contract 9.5. The transfer mode from hsf.mco_transfer_mode: hold, fixture or live; anything else reads as hold. Service role only; the worker calls this instead of msp_env_get.';

create or replace function hsf_transfer_claim(p_limit int)
returns setof hsf_upload
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text := hsf_transfer_mode();
  v_limit int := greatest(1, least(coalesce(p_limit, 10), 100));
begin
  if v_mode = 'hold' then
    -- Hold: only fresh uploads; the worker records each as held and sends nothing.
    return query
      select u.*
        from hsf_upload u
       where u.status = 'uploaded'
         and u.storage_path is not null
         and u.transfer_blocked_reason is null
         and hsf_consent_current(u.client_account_id, 'mco_transfer')
         and hsf_consent_current(u.client_account_id, 'document_storage')
       order by u.uploaded_at nulls last, u.created_at, u.id
       limit v_limit
       for update of u skip locked;
    return;
  end if;
  -- Fixture or live: uploaded and held rows, and transferring rows whose claim
  -- is more than 30 minutes old (a worker that stopped part way). Rows another
  -- worker has locked are skipped; the claimed rows move to transferring.
  return query
    with c as (
      select u.id
        from hsf_upload u
       where u.storage_path is not null
         and u.transfer_blocked_reason is null
         and (u.status in ('uploaded','held')
              or (u.status = 'transferring'
                  and (u.transfer_claimed_at is null or u.transfer_claimed_at < now() - interval '30 minutes')))
         and hsf_consent_current(u.client_account_id, 'mco_transfer')
         and hsf_consent_current(u.client_account_id, 'document_storage')
       order by u.uploaded_at nulls last, u.created_at, u.id
       limit v_limit
       for update of u skip locked
    ), claimed as (
      update hsf_upload u
         set status = 'transferring', transfer_claimed_at = now()
        from c
       where u.id = c.id
      returning u.*
    )
    select * from claimed order by uploaded_at nulls last, created_at, id;
end;
$$;
comment on function hsf_transfer_claim is 'Contract 9.5. The worker''s claim, oldest first, at most 100. Mode hold: uploaded rows only (the worker records them held). Mode fixture or live: uploaded and held rows plus transferring rows claimed more than 30 minutes ago, locked with for update skip locked and moved to transferring. Blocked uploads and accounts without mco_transfer and document_storage consent are never returned.';

create or replace function hsf_transfer_record(
  p_upload_id uuid, p_mode text, p_outcome text, p_server_sha256 text,
  p_mco_ref text, p_receipt_sha256 text, p_error text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_server text := nullif(lower(btrim(coalesce(p_server_sha256, ''))), '');
  v_receipt text := nullif(lower(btrim(coalesce(p_receipt_sha256, ''))), '');
  v_ref text := nullif(btrim(coalesce(p_mco_ref, '')), '');
  v_error text := nullif(left(btrim(coalesce(p_error, '')), 500), '');
  v_outcome text := p_outcome;
  v_status text;
  v_revoked int := 0;
begin
  if p_mode is null or p_mode not in ('hold','fixture','live') then
    raise exception 'Unknown transfer mode: %', coalesce(p_mode, 'none');
  end if;
  if p_outcome is null or p_outcome not in ('held','received','hash_mismatch','error') then
    raise exception 'Unknown transfer outcome: %', coalesce(p_outcome, 'none');
  end if;
  if v_server is not null and v_server !~ '^[0-9a-f]{64}$' then
    raise exception 'The server fingerprint must be 64 hexadecimal characters.';
  end if;
  if v_receipt is not null and v_receipt !~ '^[0-9a-f]{64}$' then
    raise exception 'The receipt fingerprint must be 64 hexadecimal characters.';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'The MyClinicOnline reference is too long.';
  end if;

  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.';
  end if;
  if v_up.status not in ('uploaded','held','transferring') then
    raise exception 'The upload is not waiting for transfer (status %).', v_up.status;
  end if;

  if p_outcome = 'received' then
    if p_mode = 'hold' then
      raise exception 'A held transfer cannot be recorded as received.';
    end if;
    if v_ref is null then
      raise exception 'A received transfer needs the MyClinicOnline reference.';
    end if;
    if v_server is null or v_receipt is null
       or v_server <> v_up.sha256_client or v_receipt <> v_up.sha256_client then
      -- The database runs the same check as the worker: without three matching
      -- fingerprints the transfer is a mismatch and the staging copy is kept.
      v_outcome := 'hash_mismatch';
      v_error := coalesce(v_error, 'Reported as received, but the browser, server and receipt fingerprints do not all match.');
    end if;
  end if;

  if v_outcome = 'held' then
    v_status := 'held';
    update hsf_upload
       set status = 'held', sha256_server = coalesce(v_server, sha256_server), transfer_claimed_at = null
     where id = v_up.id;
  elsif v_outcome = 'received' then
    v_status := 'transferred';
    update hsf_upload
       set status = 'transferred', sha256_server = v_server, mco_document_ref = v_ref,
           transferred_at = now(), verified_at = coalesce(verified_at, now()), transfer_claimed_at = null
     where id = v_up.id;
    update hsf_evidence
       set mco_document_ref = v_ref, transferred_at = now()
     where upload_id = v_up.id and mco_document_ref is null and transferred_at is null;
  elsif v_outcome = 'hash_mismatch' then
    v_status := 'failed';
    update hsf_upload
       set status = 'failed', sha256_server = coalesce(v_server, sha256_server),
           reject_reason = coalesce(v_error, 'The fingerprints do not match.'), transfer_claimed_at = null
     where id = v_up.id;
    -- Bytes that failed the fingerprint check are not evidence (contract 9.5):
    -- revoke the evidence row written at completion, return the item to
    -- outstanding when no other unrevoked evidence holds it, and recompute.
    if v_up.file_item_id is not null then
      perform 1 from hsf_file_item where id = v_up.file_item_id for update;
    end if;
    update hsf_evidence set revoked_at = now()
     where upload_id = v_up.id and revoked_at is null;
    get diagnostics v_revoked = row_count;
    if v_up.file_item_id is not null then
      update hsf_file_item fi
         set status = 'outstanding', reason = null
       where fi.id = v_up.file_item_id
         and fi.status = 'uploaded'
         and not exists (select 1 from hsf_evidence e where e.file_item_id = fi.id and e.revoked_at is null);
    end if;
    if v_up.file_id is not null then
      perform hsf_compute_compliance(v_up.file_id);
    end if;
  else
    -- An error returns the upload to uploaded, to be claimed again (contract 9.5).
    v_status := 'uploaded';
    update hsf_upload set status = 'uploaded', transfer_claimed_at = null where id = v_up.id;
  end if;

  insert into hsf_mco_transfer (upload_id, mode, outcome, mco_document_ref, mco_receipt_sha256, error)
  values (v_up.id, p_mode, v_outcome, v_ref, v_receipt, v_error);

  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values ('hsf-mco-transfer', 'hsf_transfer_recorded',
          jsonb_build_object('upload_id', v_up.id, 'mode', p_mode, 'reported_outcome', p_outcome,
                             'outcome', v_outcome, 'status', v_status, 'mco_document_ref', v_ref,
                             'evidence_revoked', v_revoked),
          v_up.file_id);

  return jsonb_build_object('upload_id', v_up.id, 'outcome', v_outcome, 'status', v_status,
                            'mco_document_ref', case when v_status = 'transferred' then v_ref end);
end;
$$;
comment on function hsf_transfer_record is 'Contract 049 and 9.5. Accepts an upload that is uploaded, held or transferring. Appends hsf_mco_transfer and moves the upload: held to held; received with server, browser and receipt fingerprints equal to transferred (and the matching hsf_evidence row gains its MyClinicOnline fields); a mismatch to failed with the reason, revoking the upload''s evidence row, returning the File item to outstanding when no other unrevoked evidence holds it, and recomputing the compliance figure; an error back to uploaded. Audited.';

create or replace function hsf_mark_staging_deleted(p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_status text;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.';
  end if;
  if v_up.status not in ('transferred','failed','rejected') then
    raise exception 'Only a transferred, failed or rejected upload can be removed from staging (status %).', v_up.status;
  end if;
  if v_up.storage_path is null then
    raise exception 'The staging copy of this upload has already been removed.';
  end if;
  v_status := case when v_up.status = 'transferred' then 'staging_deleted' else v_up.status end;
  update hsf_upload
     set status = v_status, storage_path = null, staging_deleted_at = now()
   where id = v_up.id;
  update hsf_evidence
     set staging_deleted_at = now(), storage_path = null
   where upload_id = v_up.id and staging_deleted_at is null;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values ('hsf-mco-transfer', 'hsf_staging_deleted',
          jsonb_build_object('upload_id', v_up.id, 'status', v_status, 'mco_document_ref', v_up.mco_document_ref),
          v_up.file_id);
  return jsonb_build_object('upload_id', v_up.id, 'status', v_status);
end;
$$;
comment on function hsf_mark_staging_deleted is 'Contract 049 and 9.5. After the worker has removed the bytes through the Storage API: transferred becomes staging_deleted; failed and rejected keep their status. storage_path is cleared and staging_deleted_at set on the upload and its evidence row. The row and both fingerprints stay. Audited.';

create or replace function hsf_transfer_cleanup_queue(p_limit int)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('upload_id', q.id, 'storage_path', q.storage_path, 'reason', q.status)
                            order by q.since, q.id), '[]'::jsonb)
    from (select u.id, u.storage_path, u.status,
                 coalesce(u.transferred_at, u.uploaded_at, u.created_at) as since
            from hsf_upload u
           where u.storage_path is not null
             and u.status in ('transferred','failed','rejected')
             -- After a consent withdrawal nothing is deleted automatically: a
             -- blocked upload's bytes wait for the Director and Information
             -- Officer decision.
             and u.transfer_blocked_reason is null
           order by coalesce(u.transferred_at, u.uploaded_at, u.created_at), u.id
           limit greatest(1, least(coalesce(p_limit, 10), 100))) q;
$$;
comment on function hsf_transfer_cleanup_queue is 'Contract 9.5. Staged bytes to remove, oldest first, at most 100: {upload_id, storage_path, reason} where reason is the status, transferred (the copy at MyClinicOnline is confirmed), failed or rejected. Uploads blocked by a consent withdrawal are left out (nothing is deleted automatically). The worker deletes the object through the Storage API and then calls hsf_mark_staging_deleted.';

create or replace function hsf_sweep_stale_uploads(p_hours int default 24)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hours int := coalesce(p_hours, 24);
  v_n int;
begin
  if v_hours < 1 or v_hours > 8760 then
    raise exception 'The sweep age must be between 1 and 8760 hours.';
  end if;
  update hsf_upload
     set status = 'failed', reject_reason = 'The upload was not completed.'
   where status = 'awaiting_upload'
     and created_at < now() - make_interval(hours => v_hours);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into msp_audit (actor, event_type, event_detail)
    values ('hsf-mco-transfer', 'hsf_uploads_swept', jsonb_build_object('failed', v_n, 'older_than_hours', v_hours));
  end if;
  return v_n;
end;
$$;
comment on function hsf_sweep_stale_uploads is 'Contract 9.5. Registrations still awaiting upload after p_hours (default 24) become failed with the reason ''The upload was not completed.''. Their staging path then appears in hsf_transfer_cleanup_queue, so any bytes that did arrive are removed. Audited when anything moves.';

-- Staging alerts (contract 9.5): uploads still holding bytes in Care Net staging
-- longer than hsf.staging_alert_days. Staff read the view (it filters on the
-- forge staff roles, so a client or anon sees nothing); the service role reads
-- hsf_staging_alerts_list(). The two carry the same rows.
create or replace view hsf_staging_alerts as
select u.id as upload_id,
       u.client_account_id,
       a.company_name,
       u.file_id,
       u.status,
       u.department_code,
       u.section_code,
       u.size_bytes,
       coalesce(u.uploaded_at, u.created_at) as staged_since,
       floor(extract(epoch from now() - coalesce(u.uploaded_at, u.created_at)) / 86400)::int as days_in_staging,
       u.transfer_blocked_reason
  from hsf_upload u
  join msp_client_account a on a.id = u.client_account_id
 where u.storage_path is not null
   and u.status <> 'awaiting_upload'
   and coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days =>
         coalesce((select p.value::int from msp_env_parameter p where p.key = 'hsf.staging_alert_days'), 14))
   and hsf_is_staff();
comment on view hsf_staging_alerts is 'Contract 9.5. Uploads holding bytes in the hsf-staging bucket for longer than hsf.staging_alert_days. Staff only (forge_admin, forge_omp, forge_safety_reviewer); nobody else sees a row. No file names.';
revoke all on hsf_staging_alerts from public, anon, authenticated;
grant select on hsf_staging_alerts to authenticated;

create or replace function hsf_staging_alerts_list()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'upload_id', u.id, 'client_account_id', u.client_account_id, 'company_name', a.company_name,
           'file_id', u.file_id, 'status', u.status, 'department_code', u.department_code,
           'section_code', u.section_code, 'size_bytes', u.size_bytes,
           'staged_since', coalesce(u.uploaded_at, u.created_at),
           'days_in_staging', floor(extract(epoch from now() - coalesce(u.uploaded_at, u.created_at)) / 86400)::int,
           'transfer_blocked_reason', u.transfer_blocked_reason)
         order by coalesce(u.uploaded_at, u.created_at), u.id), '[]'::jsonb)
    from hsf_upload u
    join msp_client_account a on a.id = u.client_account_id
   where u.storage_path is not null
     and u.status <> 'awaiting_upload'
     and coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days =>
           coalesce(msp_env_get_int('hsf.staging_alert_days'), 14));
$$;
comment on function hsf_staging_alerts_list is 'Contract 9.5. The rows of hsf_staging_alerts for the service role (scheduled alerts), oldest first.';

-- 10. Execute rights: service role only ------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'hsf_consent_status(uuid)',
    'hsf_record_consent(uuid, text[], text)',
    'hsf_withdraw_consent(uuid, text)',
    'hsf_register_upload(uuid, jsonb)',
    'hsf_mark_uploaded(uuid, uuid)',
    'hsf_my_uploads(uuid, uuid)',
    'hsf_transfer_queue(int)',
    'hsf_transfer_record(uuid, text, text, text, text, text, text)',
    'hsf_mark_staging_deleted(uuid)',
    'hsf_link_account(uuid)',
    'hsf_transfer_mode()',
    'hsf_transfer_claim(int)',
    'hsf_transfer_cleanup_queue(int)',
    'hsf_sweep_stale_uploads(int)',
    'hsf_staging_alerts_list()'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;
