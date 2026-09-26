-- CNC MSP FORGE | HSF-LCH-01 v1.0.0 | HSF launch controls: upload gate, client verification, retention, scanning, client deletion 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 10 (Amendment 2), items 10.1 to 10.6.
--
-- What this migration does:
--   1. Parameters hsf.uploads_open (false), hsf.staging_retention_days (730) and
--      hsf.deletion_sms_enabled (false), category hsf.
--   2. hsf_upload gains the statuses expired and client_deleted and the security
--      scan columns (scan_status, scan_engine, scanned_at, scan_findings,
--      scan_attempts).
--   3. hsf_client_verification: a company account uploads only once Care Net has
--      verified it as a Care Net Consultants client (account_kind alone is not
--      enough, because migration 040 self approves).
--   4. hsf_deletion_request: a client deletes their own staged documents only
--      after a warning, an acknowledgement and a one time PIN that Supabase Auth
--      sends and checks. Care Net never generates or stores a PIN. A request
--      is confirmable only once its own PIN was sent (pin_sent_at); a request
--      whose PIN could not be sent is cancelled. An upload whose transfer is in
--      flight is not deletable until the 30 minute reclaim window has passed.
--   5. One helper, hsf_revoke_upload_evidence, withdraws the evidence an upload
--      supplied (the hash mismatch path of 049), and is reused by the scan
--      rejection, the two year expiry and the client deletion.
--   6. hsf_register_upload refuses, in this order: no account, declined, uploads
--      closed, not verified, consents, then the checks of 049.
--   7. The scan pass (hsf_scan_claim, hsf_scan_record, hsf_scan_reset);
--      hsf_transfer_claim and hsf_transfer_record move only uploads that passed
--      the scan. An antivirus outage does not use up the five scan attempts; a
--      fingerprint mismatch at the scan fails the upload.
--   8. The two year limit (hsf_retention_queue, hsf_mark_expired), which also
--      applies to uploads blocked by a consent withdrawal; the staging alerts
--      and hsf_my_uploads show the expiry date.
--   9. The cleanup queue and hsf_mark_staging_deleted take client_deleted and
--      expired uploads; the queue also takes transferred, never completed and
--      scan rejected bytes whether blocked or not (hsf_upload_awaits_cleanup).
--      A receipt from MyClinicOnline that arrives after the client deleted the
--      upload is kept and audited, so the deletion at MyClinicOnline can follow.
--
-- Nothing here writes file content, a PIN, a key or a token to msp_audit.
-- Migrations 047 to 051 are not edited: every changed function is redefined
-- here with create or replace, keeping security definer, the fixed search path
-- and service role only execute unless stated.

-- 1. Parameters -----------------------------------------------------------------------------

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description, updated_by) values
  ('hsf.uploads_open', 'false', 'boolean', null, null, 'hsf',
   'Opens company uploads in the File builder. Stays off until the backend (Odendaal) and the front end (Cassandra and the designer) are signed off.',
   'migration_052'),
  ('hsf.staging_retention_days', '730', 'integer', 1, 730, 'hsf',
   'Contract 10.3. The longest a document may stay in Care Net staging, in days (two years). Older staged bytes are deleted, including those of uploads blocked by a consent withdrawal.',
   'migration_052'),
  ('hsf.deletion_sms_enabled', 'false', 'boolean', null, null, 'hsf',
   'Contract 10.5. Offers the deletion PIN by SMS as well as by email. Needs an SMS provider configured in Supabase Auth, and the person needs a confirmed phone number.',
   'migration_052')
on conflict (key) do nothing;

-- 2. hsf_upload: new statuses and the security scan -------------------------------------------
-- The 049 status check is replaced by one that keeps every existing value and
-- adds expired (two year limit reached, bytes deleted) and client_deleted (the
-- client deleted it with a PIN; the bytes leave through the cleanup queue).
do $$
declare
  v_name text;
begin
  select c.conname into v_name
    from pg_constraint c
   where c.conrelid = 'public.hsf_upload'::regclass
     and c.contype = 'c'
     and pg_get_constraintdef(c.oid) ilike '%awaiting_upload%';
  if v_name is not null then
    execute format('alter table hsf_upload drop constraint %I', v_name);
  end if;
end;
$$;
alter table hsf_upload add constraint hsf_upload_status_check check (status in
  ('awaiting_upload','uploaded','verified','held','transferring','transferred','staging_deleted',
   'rejected','failed','expired','client_deleted'));
alter table hsf_upload add constraint hsf_upload_expired_no_bytes
  check (status <> 'expired' or (storage_path is null and staging_deleted_at is not null));

alter table hsf_upload
  add column scan_status text not null default 'pending'
    check (scan_status in ('pending','clean','infected','harmful','error')),
  add column scan_engine text,
  add column scanned_at timestamptz,
  add column scan_findings jsonb,
  add column scan_attempts int not null default 0 check (scan_attempts >= 0);
comment on column hsf_upload.scan_status is 'Contract 10.4. pending until the scan pass has run; clean when the built in structural check and the antivirus engine both passed; infected or harmful rejects the upload; error is retried by hsf_scan_claim up to five attempts. Only a clean upload is ever claimed for transfer.';
comment on column hsf_upload.scan_engine is 'Contract 10.4. The antivirus engine and version that answered, as the worker reported it.';
comment on column hsf_upload.scanned_at is 'Contract 10.4. When the last scan result was recorded.';
comment on column hsf_upload.scan_findings is 'Contract 10.4. The findings of the last scan as a json array of {code, message} in plain words. Never file content.';
comment on column hsf_upload.scan_attempts is 'Contract 10.4. How many times hsf_scan_claim has handed the upload to the scan pass. After five an upload that still reads pending or error is not claimed again.';
create index hsf_upload_scan_idx on hsf_upload(uploaded_at, created_at)
  where status = 'uploaded' and scan_status in ('pending','error');

comment on table hsf_upload is 'HSF-UPL-01. One row per document a client drops into the builder. The bytes sit in the private hsf-staging bucket at <client_account_id>/<upload_id>/<safe_name> until they are transferred to MyClinicOnline and removed; the row, with the browser and server SHA 256 fingerprints, stays for the audit trail. Lifecycle: awaiting_upload, uploaded (then scanned), held, transferred, staging_deleted; or rejected, failed, expired (two year limit, contract 10.3) and client_deleted (deleted by the client with a PIN, contract 10.5).';

-- 3. Client verification (contract 10.2) ----------------------------------------------------

create table hsf_client_verification (
  client_account_id uuid primary key references msp_client_account(id),
  status text not null default 'requested' check (status in ('requested','verified','revoked')),
  method text check (method in ('mco_company_ref','client_register','sales_executive')),
  evidence_ref text,
  requested_at timestamptz not null default now(),
  verified_by text,
  verified_at timestamptz,
  revoked_by text,
  revoked_at timestamptz,
  revoke_reason text,
  check (status <> 'verified' or (method is not null and evidence_ref is not null
                                  and verified_by is not null and verified_at is not null)),
  check (status <> 'revoked' or (revoked_by is not null and revoked_at is not null and revoke_reason is not null))
);
comment on table hsf_client_verification is 'HSF-LCH-01, contract 10.2. Whether Care Net has confirmed that a company account is a Care Net Consultants client. Only a verified account may upload documents. The method (MyClinicOnline company reference, client register or a sales executive) and the evidence reference are recorded; every change is audited. A revocation blocks the account''s untransferred uploads and deletes nothing.';
comment on column hsf_client_verification.evidence_ref is 'What the verification rests on, for example the MyClinicOnline company reference or the client register number. Required to verify.';

alter table hsf_client_verification enable row level security;
revoke all on hsf_client_verification from public, anon, authenticated;
grant select on hsf_client_verification to authenticated;
grant all on hsf_client_verification to service_role;
create policy hsf_client_verification_read on hsf_client_verification
  for select to authenticated using (hsf_is_staff());

-- 4. Deletion requests (contract 10.5) --------------------------------------------------------

create table hsf_deletion_request (
  id uuid primary key default gen_random_uuid(),
  client_account_id uuid not null references msp_client_account(id),
  auth_user_id uuid not null,
  upload_ids uuid[] not null check (cardinality(upload_ids) between 1 and 50),
  channel text not null check (channel in ('email','sms')),
  acknowledged_irreversible boolean not null check (acknowledged_irreversible),
  status text not null default 'pending' check (status in ('pending','confirmed','expired','cancelled','locked')),
  attempts int not null default 0 check (attempts between 0 and 5),
  requested_at timestamptz not null default now(),
  expires_at timestamptz not null,
  pin_sent_at timestamptz,
  confirmed_at timestamptz,
  check (expires_at = requested_at + interval '10 minutes'),
  check (status <> 'confirmed' or confirmed_at is not null)
);
comment on table hsf_deletion_request is 'HSF-LCH-01, contract 10.5. One request by a client to delete their own staged documents permanently. The client has read the warning and ticked that it cannot be undone; Supabase Auth sends and checks the one time PIN, so no PIN is held here. A request lasts 10 minutes and allows 5 PIN attempts, then it is locked.';
comment on column hsf_deletion_request.pin_sent_at is 'When Supabase Auth accepted the request to send this request''s PIN. Set only after that acceptance; a request without it can take no PIN attempt and cannot be confirmed, so a PIN sent for another request or a sign in code never confirms it.';
create index hsf_deletion_request_account_idx on hsf_deletion_request(client_account_id, requested_at desc);

alter table hsf_deletion_request enable row level security;
revoke all on hsf_deletion_request from public, anon, authenticated;
grant select on hsf_deletion_request to authenticated;
grant all on hsf_deletion_request to service_role;
create policy hsf_deletion_request_read on hsf_deletion_request
  for select to authenticated using (hsf_is_staff());

-- 5. Internal helpers (never callable from outside) --------------------------------------------

create or replace function hsf_staging_retention_days()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select least(730, greatest(1, coalesce(msp_env_get_int('hsf.staging_retention_days'), 730)));
$$;
comment on function hsf_staging_retention_days is 'Contract 10.3. hsf.staging_retention_days, held between 1 and 730 whatever the stored value.';

create or replace function hsf_upload_deletable(p_status text, p_storage_path text, p_claimed_at timestamptz)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_storage_path is not null
     and coalesce(p_status, '') not in ('transferred','staging_deleted','expired','client_deleted')
     -- A transfer in flight may already have reached MyClinicOnline, so it is not
     -- deleted here until the worker's 30 minute reclaim window has passed.
     and not (coalesce(p_status, '') = 'transferring'
              and p_claimed_at is not null and p_claimed_at >= now() - interval '30 minutes');
$$;
comment on function hsf_upload_deletable is 'Contract 10.5. A client may delete an upload while its bytes are still in Care Net staging: any status except transferred, staging_deleted, expired and client_deleted, and not while a transfer is in flight (transferring and claimed in the last 30 minutes), because MyClinicOnline may already hold that copy. Once MyClinicOnline holds a document, deletion is MyClinicOnline''s process.';

-- Failed and rejected bytes are never a document, so they leave staging through
-- the cleanup queue. A block (consent withdrawn, verification revoked) keeps
-- them only while they may still be the client's document: bytes that never
-- completed, and bytes the security scan rejected, go whatever the block.
-- Transferred bytes go too: the copy at MyClinicOnline is confirmed.
create or replace function hsf_upload_awaits_cleanup(p_status text, p_blocked text, p_uploaded_at timestamptz, p_scan_status text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_status, '') in ('transferred','client_deleted')
      or (coalesce(p_status, '') in ('failed','rejected')
          and (p_blocked is null or p_uploaded_at is null or coalesce(p_scan_status, '') in ('infected','harmful')));
$$;
comment on function hsf_upload_awaits_cleanup is 'Contract 9.5, 10.4 and 10.5. True for an upload whose staged bytes the cleanup queue removes: transferred and client_deleted rows whether blocked or not; failed and rejected rows that are not blocked, never completed, or failed the security scan.';

-- The hash mismatch path of 049, as one helper: bytes that are no longer
-- evidence (fingerprint mismatch, failed scan, two year limit, client deletion)
-- withdraw the evidence row written at completion, return the File item to
-- outstanding when no other unrevoked evidence holds it, and recompute the
-- compliance figure.
create or replace function hsf_revoke_upload_evidence(p_upload_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_revoked int := 0;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id;
  if v_up.id is null then
    return 0;
  end if;
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
  return v_revoked;
end;
$$;
comment on function hsf_revoke_upload_evidence is 'Contract 9.5 and 10.3 to 10.5. The one evidence withdrawal for an upload whose bytes are no longer evidence: revokes its unrevoked hsf_evidence rows, returns the File item to outstanding when no other unrevoked evidence holds it, and recomputes the compliance figure. Returns the number of rows revoked. Used by hsf_transfer_record (mismatch), hsf_scan_record, hsf_mark_expired and hsf_deletion_request_confirm.';

create or replace function hsf_client_verified(p_client_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from hsf_client_verification v
                  where v.client_account_id = p_client_account_id and v.status = 'verified');
$$;
comment on function hsf_client_verified is 'Contract 10.2. True when Care Net has verified the company account as a Care Net Consultants client and not revoked it.';

-- 6. Client verification ---------------------------------------------------------------------

create or replace function hsf_request_client_verification(p_auth_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_row hsf_client_verification;
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before asking for verification.';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'This company account cannot be verified. Please WhatsApp a sales executive.';
  end if;
  select v.* into v_row from hsf_client_verification v where v.client_account_id = v_acc.id for update;
  if v_row.client_account_id is null or v_row.status = 'revoked' then
    -- A new request, or a request again after a revocation. The revocation
    -- details stay on the row for the sales executive who reviews it.
    insert into hsf_client_verification (client_account_id, status, requested_at)
    values (v_acc.id, 'requested', now())
    on conflict (client_account_id) do update set status = 'requested', requested_at = now()
    returning * into v_row;
    insert into msp_audit (actor, event_type, event_detail)
    values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_client_verification_requested',
            jsonb_build_object('client_account_id', v_acc.id));
  end if;
  return jsonb_build_object('client_account_id', v_row.client_account_id, 'status', v_row.status,
                            'requested_at', v_row.requested_at, 'verified_at', v_row.verified_at);
end;
$$;
comment on function hsf_request_client_verification is 'Contract 10.2. Creates, or returns, the verification request of the auth user''s company account. An account whose verification was revoked may ask again (the revocation details stay on the row). A declined account is refused. Audited as hsf_client_verification_requested when a request is made.';

create or replace function hsf_verify_client(p_client_account_id uuid, p_method text, p_evidence_ref text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_ref text := btrim(coalesce(p_evidence_ref, ''));
  v_by text;
  v_row hsf_client_verification;
begin
  if not (coalesce(auth.role() = 'service_role', false) or coalesce(hsf_is_staff(), false)) then
    raise exception 'Verifying a client needs a Care Net staff role.' using errcode = '42501';
  end if;
  select a.* into v_acc from msp_client_account a where a.id = p_client_account_id;
  if v_acc.id is null then
    raise exception 'That company account was not found.' using errcode = 'P0002';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'A declined company account cannot be verified.';
  end if;
  if p_method is null or p_method not in ('mco_company_ref','client_register','sales_executive') then
    raise exception 'The verification method must be mco_company_ref, client_register or sales_executive.';
  end if;
  if v_ref = '' or length(v_ref) > 200 or v_ref ~ '[[:cntrl:]]' then
    raise exception 'Record what the verification rests on (for example the MyClinicOnline company reference or the client register number), in 1 to 200 characters.';
  end if;
  v_by := coalesce(nullif(btrim(auth.jwt() ->> 'email'), ''),
                   case when auth.role() = 'service_role' then 'service_role' end, 'staff');
  -- A verification after a revocation clears the revocation fields; the audit
  -- trail keeps both events. Uploads blocked by the revocation stay blocked.
  insert into hsf_client_verification (client_account_id, status, method, evidence_ref, requested_at, verified_by, verified_at)
  values (v_acc.id, 'verified', p_method, v_ref, now(), v_by, now())
  on conflict (client_account_id) do update
     set status = 'verified', method = excluded.method, evidence_ref = excluded.evidence_ref,
         verified_by = excluded.verified_by, verified_at = excluded.verified_at,
         revoked_by = null, revoked_at = null, revoke_reason = null
  returning * into v_row;
  insert into msp_audit (actor, event_type, event_detail)
  values (v_by, 'hsf_client_verified',
          jsonb_build_object('client_account_id', v_acc.id, 'method', p_method, 'evidence_ref', v_ref));
  return jsonb_build_object('client_account_id', v_row.client_account_id, 'status', v_row.status,
                            'method', v_row.method, 'verified_by', v_row.verified_by, 'verified_at', v_row.verified_at);
end;
$$;
comment on function hsf_verify_client is 'Contract 10.2. Marks a company account verified as a Care Net Consultants client, with the method and a required evidence reference. The service role or a signed in forge staff member (hsf_is_staff, which includes forge_admin), checked in the body; verified_by is the staff email from the JWT or service_role. A declined account is refused. Uploads blocked by an earlier revocation stay blocked. Audited as hsf_client_verified.';

create or replace function hsf_revoke_client_verification(p_client_account_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_by text;
  v_row hsf_client_verification;
  v_blocked int := 0;
begin
  if not (coalesce(auth.role() = 'service_role', false) or coalesce(hsf_is_staff(), false)) then
    raise exception 'Revoking a client verification needs a Care Net staff role.' using errcode = '42501';
  end if;
  if v_reason = '' or length(v_reason) > 500 then
    raise exception 'Give the reason for the revocation, in 1 to 500 characters.';
  end if;
  select v.* into v_row from hsf_client_verification v where v.client_account_id = p_client_account_id for update;
  if v_row.client_account_id is null or v_row.status <> 'verified' then
    raise exception 'That company account is not verified.';
  end if;
  v_by := coalesce(nullif(btrim(auth.jwt() ->> 'email'), ''),
                   case when auth.role() = 'service_role' then 'service_role' end, 'staff');
  update hsf_client_verification
     set status = 'revoked', revoked_by = v_by, revoked_at = now(), revoke_reason = v_reason
   where client_account_id = v_row.client_account_id
  returning * into v_row;
  -- Nothing is deleted: untransferred uploads are blocked from the scan and the
  -- transfer claim, as after a consent withdrawal.
  update hsf_upload
     set transfer_blocked_reason = 'client verification revoked'
   where client_account_id = v_row.client_account_id
     and transfer_blocked_reason is null
     and status in ('awaiting_upload','uploaded','verified','held','transferring');
  get diagnostics v_blocked = row_count;
  insert into msp_audit (actor, event_type, event_detail)
  values (v_by, 'hsf_client_verification_revoked',
          jsonb_build_object('client_account_id', v_row.client_account_id, 'reason', v_reason,
                             'blocked_uploads', v_blocked));
  return jsonb_build_object('client_account_id', v_row.client_account_id, 'status', v_row.status,
                            'revoked_at', v_row.revoked_at, 'blocked_uploads', v_blocked);
end;
$$;
comment on function hsf_revoke_client_verification is 'Contract 10.2. Revokes a verification with a reason. The account''s untransferred uploads are not deleted: they get transfer_blocked_reason = ''client verification revoked'' and are never scanned or claimed for transfer. The service role or forge staff, checked in the body. Audited as hsf_client_verification_revoked.';

-- 7. The upload gate and registration ------------------------------------------------------------

create or replace function hsf_upload_gate(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_status text;
  v_phone_ok boolean;
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is not null then
    select v.status into v_status from hsf_client_verification v where v.client_account_id = v_acc.id;
  end if;
  select (to_jsonb(u) ->> 'phone') is not null and (to_jsonb(u) ->> 'phone_confirmed_at') is not null
    into v_phone_ok
    from auth.users u where u.id = p_auth_user;
  return jsonb_build_object(
    'uploads_open', coalesce(msp_env_get_bool('hsf.uploads_open'), false),
    'client_verified', coalesce(v_status = 'verified', false),
    'verification_requested', coalesce(v_status = 'requested', false),
    'consent_complete', v_acc.id is not null and hsf_consent_complete(v_acc.id),
    'deletion_sms_available', coalesce(msp_env_get_bool('hsf.deletion_sms_enabled'), false) and coalesce(v_phone_ok, false));
end;
$$;
comment on function hsf_upload_gate is 'Contract 10.1. What the builder needs to show before an upload: {uploads_open, client_verified, verification_requested, consent_complete}, plus deletion_sms_available (hsf.deletion_sms_enabled and a confirmed phone on the sign in), which tells the builder whether to offer the deletion PIN by SMS.';

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
  -- Contract 10.2: no account, declined, uploads closed (10.1), not verified,
  -- consents, then the checks of 049.
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'Register your company account before uploading documents.';
  end if;
  if v_acc.account_kind = 'declined' then
    raise exception 'This company account cannot upload documents. Please WhatsApp a sales executive.';
  end if;
  if not coalesce(msp_env_get_bool('hsf.uploads_open'), false) then
    raise exception 'Document uploads open soon. Your File can be built now, and uploads will open once Care Net has finished testing.';
  end if;
  if not hsf_client_verified(v_acc.id) then
    raise exception 'Uploads are for verified Care Net Consultants clients. Ask for verification in the builder, or WhatsApp a sales executive.';
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
comment on function hsf_register_upload is 'Contract 049, 10.1 and 10.2. Registers one upload before the bytes move. Refuses, in this order: no company account, a declined account, uploads closed (hsf.uploads_open), an account not verified as a Care Net Consultants client, incomplete consent; then department, section, File and element, and type and size against hsf.upload_allowed_mime and hsf.upload_max_bytes. Returns the staging bucket and path for the signed upload URL. Audited (never the file name or content).';

-- 8. Security scan and transfer --------------------------------------------------------------------

create or replace function hsf_scan_claim(p_limit int)
returns setof hsf_upload
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int := greatest(1, least(coalesce(p_limit, 10), 100));
begin
  -- Uploads whose bytes have arrived and wait for a scan (or a retry after an
  -- engine error), oldest first. Rows another worker has locked are skipped;
  -- every claimed row counts one attempt, at most five.
  return query
    with c as (
      select u.id
        from hsf_upload u
       where u.status = 'uploaded'
         and u.scan_status in ('pending','error')
         and u.scan_attempts < 5
         and u.transfer_blocked_reason is null
         and u.storage_path is not null
       order by u.uploaded_at nulls last, u.created_at, u.id
       limit v_limit
       for update of u skip locked
    ), claimed as (
      update hsf_upload u
         set scan_attempts = u.scan_attempts + 1
        from c
       where u.id = c.id
      returning u.*
    )
    select * from claimed order by uploaded_at nulls last, created_at, id;
end;
$$;
comment on function hsf_scan_claim is 'Contract 10.4. The scan pass''s claim, oldest first, at most 100: uploaded rows whose scan is pending or ended in an engine error, with bytes present, not blocked, and fewer than five attempts. Locked with for update skip locked; each claimed row''s scan_attempts goes up by one.';

create or replace function hsf_scan_record(p_upload_id uuid, p_result text, p_engine text, p_findings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_engine text := nullif(left(btrim(coalesce(p_engine, '')), 200), '');
  v_findings jsonb := coalesce(p_findings, '[]'::jsonb);
  v_summary text;
  v_reason text;
  v_status text;
  v_revoked int := 0;
  v_attempts int;
begin
  if p_result is null or p_result not in ('clean','infected','harmful','error') then
    raise exception 'Unknown scan result: %', coalesce(p_result, 'none');
  end if;
  if jsonb_typeof(v_findings) <> 'array' or jsonb_array_length(v_findings) > 50 then
    raise exception 'The scan findings must be a list of at most 50 entries.';
  end if;
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.' using errcode = 'P0002';
  end if;
  if v_up.status <> 'uploaded' or v_up.scan_status not in ('pending','error') then
    raise exception 'The upload is not waiting for a security scan (status %, scan %).', v_up.status, v_up.scan_status;
  end if;

  if p_result = 'error' and exists (select 1 from jsonb_array_elements(v_findings) f
                                     where jsonb_typeof(f) = 'object' and f ->> 'code' = 'fingerprint_mismatch') then
    -- The stored bytes are not the bytes fingerprinted in the browser: like the
    -- mismatch at transfer (contract 9.5) the upload fails, its evidence is
    -- withdrawn and its bytes leave through the cleanup queue. No retry.
    v_status := 'failed';
    v_reason := 'The stored file does not match the fingerprint taken when it was uploaded.';
    update hsf_upload
       set status = 'failed', reject_reason = v_reason, scan_status = 'error', scan_engine = v_engine,
           scanned_at = now(), scan_findings = v_findings, transfer_claimed_at = null
     where id = v_up.id;
    v_revoked := hsf_revoke_upload_evidence(v_up.id);
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_upload_scan_rejected',
            jsonb_build_object('upload_id', v_up.id, 'result', 'fingerprint_mismatch', 'engine', v_engine,
                               'findings', v_findings, 'evidence_revoked', v_revoked),
            v_up.file_id);
  elsif p_result in ('infected','harmful') then
    -- The plain words of the findings become the reason the client reads. Each
    -- message loses its closing full stop, so several read 'X; Y.' not 'X.; Y.'.
    select string_agg(m, '; ' order by m) into v_summary
      from (select distinct left(regexp_replace(regexp_replace(btrim(f ->> 'message'), '[[:cntrl:]]+', ' ', 'g'),
                                                '[.[:space:]]+$', ''), 200) as m
              from jsonb_array_elements(v_findings) f
             where jsonb_typeof(f) = 'object' and coalesce(f ->> 'message', '') !~ '^[.[:space:][:cntrl:]]*$') x;
    v_summary := coalesce(left(v_summary, 400),
                          case when p_result = 'infected' then 'the antivirus engine found malicious software'
                               else 'the file carries content that could cause harm' end);
    v_reason := 'The file failed the security scan: ' || v_summary;
    if v_reason !~ '[.!?]$' then
      v_reason := v_reason || '.';
    end if;
    v_status := 'rejected';
    -- Harmful bytes are not a document waiting on a consent or verification
    -- decision, so a block set while the scan ran is cleared: the cleanup queue
    -- removes them either way.
    update hsf_upload
       set status = 'rejected', reject_reason = v_reason, scan_status = p_result, scan_engine = v_engine,
           scanned_at = now(), scan_findings = v_findings, transfer_claimed_at = null,
           transfer_blocked_reason = null
     where id = v_up.id;
    -- The bytes are not evidence; they leave through hsf_transfer_cleanup_queue.
    v_revoked := hsf_revoke_upload_evidence(v_up.id);
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_upload_scan_rejected',
            jsonb_build_object('upload_id', v_up.id, 'result', p_result, 'engine', v_engine,
                               'findings', v_findings, 'evidence_revoked', v_revoked),
            v_up.file_id);
  else
    v_status := 'uploaded';
    -- An antivirus engine that is not configured or did not answer says nothing
    -- about the file, so that attempt is given back: an outage never uses up
    -- the five attempts. Only inspection errors count.
    update hsf_upload
       set scan_status = p_result, scan_engine = v_engine, scanned_at = now(), scan_findings = v_findings,
           scan_attempts = case
             when p_result = 'error' and jsonb_array_length(v_findings) > 0
                  and not exists (select 1 from jsonb_array_elements(v_findings) f
                                   where jsonb_typeof(f) <> 'object'
                                      or coalesce(f ->> 'code', '') not in ('av_not_configured','av_error'))
             then greatest(0, scan_attempts - 1)
             else scan_attempts end
     where id = v_up.id
    returning scan_attempts into v_attempts;
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_upload_scanned',
            jsonb_build_object('upload_id', v_up.id, 'result', p_result, 'engine', v_engine,
                               'attempts', v_attempts),
            v_up.file_id);
  end if;

  return jsonb_build_object('upload_id', v_up.id, 'status', v_status, 'scan_status', p_result,
                            'reject_reason', v_reason, 'evidence_revoked', v_revoked);
end;
$$;
comment on function hsf_scan_record is 'Contract 10.4. Records the scan result of an uploaded row whose scan is pending or error. clean: scan_status clean, the upload may now be claimed for transfer. error: scan_status error, the upload stays uploaded for a retry; an error that only says the antivirus engine is not configured or did not answer (codes av_not_configured, av_error) gives its attempt back. error with a fingerprint_mismatch finding: the upload fails like a mismatch at transfer, with its evidence withdrawn. infected or harmful: the upload is rejected with ''The file failed the security scan: <plain summary of the findings>'', any transfer block cleared, its evidence withdrawn through hsf_revoke_upload_evidence, and its bytes leave through the cleanup queue. Audited as hsf_upload_scanned or hsf_upload_scan_rejected.';

create or replace function hsf_scan_reset(p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_by text;
begin
  if not (coalesce(auth.role() = 'service_role', false) or coalesce(hsf_is_staff(), false)) then
    raise exception 'Resetting a security scan needs a Care Net staff role.' using errcode = '42501';
  end if;
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.' using errcode = 'P0002';
  end if;
  if v_up.status <> 'uploaded' or v_up.scan_status not in ('pending','error') or v_up.storage_path is null then
    raise exception 'Only an uploaded document still waiting for its security scan can be scanned again (status %, scan %).',
      v_up.status, v_up.scan_status;
  end if;
  v_by := coalesce(nullif(btrim(auth.jwt() ->> 'email'), ''),
                   case when auth.role() = 'service_role' then 'service_role' end, 'staff');
  update hsf_upload set scan_attempts = 0 where id = v_up.id;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (v_by, 'hsf_upload_scan_reset',
          jsonb_build_object('upload_id', v_up.id, 'attempts_before', v_up.scan_attempts,
                             'scan_status', v_up.scan_status),
          v_up.file_id);
  return jsonb_build_object('upload_id', v_up.id, 'scan_status', v_up.scan_status, 'scan_attempts', 0);
end;
$$;
comment on function hsf_scan_reset is 'Contract 10.4. Gives an uploaded document whose scan is pending or error its five scan attempts back, for example after an inspection fault was fixed; hsf_staging_alerts lists the documents that used all five. The service role or forge staff, checked in the body. Audited as hsf_upload_scan_reset.';

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
    -- Hold: only fresh uploads that passed the scan; the worker records each as
    -- held and sends nothing.
    return query
      select u.*
        from hsf_upload u
       where u.status = 'uploaded'
         and u.scan_status = 'clean'
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
  -- is more than 30 minutes old (a worker that stopped part way), all clean.
  -- Rows another worker has locked are skipped; the claimed rows move to
  -- transferring.
  return query
    with c as (
      select u.id
        from hsf_upload u
       where u.storage_path is not null
         and u.scan_status = 'clean'
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
comment on function hsf_transfer_claim is 'Contract 9.5 and 10.4. The worker''s claim, oldest first, at most 100, of uploads that passed the security scan (scan_status clean) only. Mode hold: uploaded rows only (the worker records them held). Mode fixture or live: uploaded and held rows plus transferring rows claimed more than 30 minutes ago, locked with for update skip locked and moved to transferring. Blocked uploads and accounts without mco_transfer and document_storage consent are never returned.';

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
  if v_up.status in ('client_deleted','expired') and p_outcome = 'received' and p_mode <> 'hold'
     and v_ref is not null and v_server is not null and v_receipt is not null
     and v_server = v_up.sha256_client and v_receipt = v_up.sha256_client then
    -- A transfer that was in flight when the client deleted the document (or the
    -- two year limit took it): MyClinicOnline now holds a copy Care Net must not
    -- lose track of. The receipt and reference are kept and the audit event asks
    -- for the deletion at MyClinicOnline; the status stays, so the worker keeps
    -- nothing and the cleanup queue removes any bytes still staged.
    update hsf_upload set mco_document_ref = v_ref, transfer_claimed_at = null where id = v_up.id;
    insert into hsf_mco_transfer (upload_id, mode, outcome, mco_document_ref, mco_receipt_sha256, error)
    values (v_up.id, p_mode, 'received', v_ref, v_receipt,
            'Received by MyClinicOnline after the document was ' || replace(v_up.status, '_', ' ')
            || ' in Care Net staging. Ask MyClinicOnline to delete it.');
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_transfer_received_after_deletion',
            jsonb_build_object('upload_id', v_up.id, 'mode', p_mode, 'status', v_up.status,
                               'mco_document_ref', v_ref, 'sha256', v_up.sha256_client,
                               'action_needed', 'Ask MyClinicOnline to delete this document.'),
            v_up.file_id);
    return jsonb_build_object('upload_id', v_up.id, 'outcome', 'received', 'status', v_up.status,
                              'mco_document_ref', v_ref, 'mco_deletion_needed', true);
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

  -- Contract 10.4: nothing is held or handed to MyClinicOnline before it has
  -- passed the security scan. A mismatch or an error may still be recorded.
  if v_outcome in ('held','received') and v_up.scan_status <> 'clean' then
    raise exception 'The upload has not passed the security scan (scan %).', v_up.scan_status;
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
    -- Bytes that failed the fingerprint check are not evidence (contract 9.5).
    v_revoked := hsf_revoke_upload_evidence(v_up.id);
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
comment on function hsf_transfer_record is 'Contract 049, 9.5 and 10.4. Accepts an upload that is uploaded, held or transferring. Appends hsf_mco_transfer and moves the upload: held to held; received with server, browser and receipt fingerprints equal to transferred (and the matching hsf_evidence row gains its MyClinicOnline fields); a mismatch to failed with the reason, withdrawing its evidence through hsf_revoke_upload_evidence; an error back to uploaded. held and received are refused for an upload that has not passed the security scan. A received with three matching fingerprints for an upload the client deleted (or the two year limit expired) while it was in flight keeps the MyClinicOnline reference and receipt, leaves the status, and is audited as hsf_transfer_received_after_deletion so the deletion at MyClinicOnline can be asked for. Audited.';

-- 9. Two year limit, cleanup and what the client and staff see -----------------------------------

create or replace function hsf_retention_queue(p_limit int)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('upload_id', q.id, 'storage_path', q.storage_path, 'reason', 'retention')
                            order by q.since, q.id), '[]'::jsonb)
    from (select u.id, u.storage_path, coalesce(u.uploaded_at, u.created_at) as since
            from hsf_upload u
           where u.storage_path is not null
             -- Transferred and client deleted bytes already leave through the
             -- cleanup queue. Blocked uploads are included on purpose: the two
             -- year limit overrides a block.
             and u.status not in ('transferred','client_deleted','expired','staging_deleted')
             -- Not while a transfer is in flight: MyClinicOnline may already hold it.
             and not (u.status = 'transferring' and u.transfer_claimed_at >= now() - interval '30 minutes')
             and coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days => hsf_staging_retention_days())
           order by coalesce(u.uploaded_at, u.created_at), u.id
           limit greatest(1, least(coalesce(p_limit, 10), 100))) q;
$$;
comment on function hsf_retention_queue is 'Contract 10.3. Staged bytes older than hsf.staging_retention_days (two years), oldest first, at most 100: {upload_id, storage_path, reason: retention}. Uploads blocked by a consent withdrawal or a revoked verification are included: the two year limit overrides a block. A transfer in flight (transferring, claimed in the last 30 minutes) waits. The worker deletes the object through the Storage API and then calls hsf_mark_expired.';

create or replace function hsf_mark_expired(p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_days int := hsf_staging_retention_days();
  v_revoked int := 0;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.' using errcode = 'P0002';
  end if;
  if v_up.storage_path is null or v_up.status in ('transferred','client_deleted','expired','staging_deleted') then
    raise exception 'That upload holds no bytes under the staging limit (status %).', v_up.status;
  end if;
  if coalesce(v_up.uploaded_at, v_up.created_at) >= now() - make_interval(days => v_days) then
    raise exception 'That upload has not reached the % day staging limit.', v_days;
  end if;
  if v_up.status = 'transferring' and v_up.transfer_claimed_at >= now() - interval '30 minutes' then
    raise exception 'That upload is being transferred to MyClinicOnline. Try again after the transfer.';
  end if;
  update hsf_upload
     set status = 'expired', storage_path = null, staging_deleted_at = now(), transfer_claimed_at = null
   where id = v_up.id;
  v_revoked := hsf_revoke_upload_evidence(v_up.id);
  update hsf_evidence
     set staging_deleted_at = now(), storage_path = null
   where upload_id = v_up.id and staging_deleted_at is null;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values ('hsf-mco-transfer', 'hsf_upload_expired',
          jsonb_build_object('upload_id', v_up.id, 'status_before', v_up.status, 'retention_days', v_days,
                             'transfer_blocked_reason', v_up.transfer_blocked_reason,
                             'sha256', v_up.sha256_client, 'evidence_revoked', v_revoked),
          v_up.file_id);
  return jsonb_build_object('upload_id', v_up.id, 'status', 'expired', 'evidence_revoked', v_revoked);
end;
$$;
comment on function hsf_mark_expired is 'Contract 10.3. After the worker has deleted the bytes of an upload listed by hsf_retention_queue: status expired, storage_path cleared, staging_deleted_at set (on the upload and its evidence rows), the evidence withdrawn through hsf_revoke_upload_evidence. Refused for an upload younger than the limit. The row and its fingerprints stay. Audited as hsf_upload_expired.';

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
  if v_up.status not in ('transferred','failed','rejected','client_deleted','expired') then
    raise exception 'Only a transferred, failed, rejected, client deleted or expired upload can be removed from staging (status %).', v_up.status;
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
comment on function hsf_mark_staging_deleted is 'Contract 049, 9.5, 10.3 and 10.5. After the worker has removed the bytes through the Storage API: transferred becomes staging_deleted; failed, rejected, client_deleted and expired keep their status. storage_path is cleared and staging_deleted_at set on the upload and its evidence row. The row and both fingerprints stay. Audited.';

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
             -- After a consent withdrawal or a revoked verification no document
             -- is deleted automatically: a blocked upload's bytes wait for the
             -- client's deletion or the two year limit. Transferred and client
             -- deleted bytes, bytes that never completed and bytes the scan
             -- rejected go, blocked or not (hsf_upload_awaits_cleanup).
             and hsf_upload_awaits_cleanup(u.status, u.transfer_blocked_reason, u.uploaded_at, u.scan_status)
           order by coalesce(u.transferred_at, u.uploaded_at, u.created_at), u.id
           limit greatest(1, least(coalesce(p_limit, 10), 100))) q;
$$;
comment on function hsf_transfer_cleanup_queue is 'Contract 9.5 and 10.5. Staged bytes to remove, oldest first, at most 100: {upload_id, storage_path, reason} where reason is the status: transferred (the copy at MyClinicOnline is confirmed), failed, rejected (including a failed security scan) or client_deleted. A blocked upload is left out unless it was transferred or client deleted, never completed, or failed the security scan (hsf_upload_awaits_cleanup). The worker deletes the object through the Storage API and then calls hsf_mark_staging_deleted.';

-- Staging alerts (contract 9.5 and 10.3): the 049 view with expires_on and
-- scan_exhausted added as its last columns, now also listing uploads within 30
-- days of the two year limit and uploads whose security scan used all five
-- attempts (staff give them a fresh start with hsf_scan_reset).
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
       u.transfer_blocked_reason,
       (coalesce(u.uploaded_at, u.created_at) + make_interval(days =>
          least(730, greatest(1, coalesce((select p.value::int from msp_env_parameter p where p.key = 'hsf.staging_retention_days'), 730)))))::date
         as expires_on,
       (u.status = 'uploaded' and u.scan_status = 'error' and u.scan_attempts >= 5) as scan_exhausted
  from hsf_upload u
  join msp_client_account a on a.id = u.client_account_id
 where u.storage_path is not null
   and u.status <> 'awaiting_upload'
   and (coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days =>
          coalesce((select p.value::int from msp_env_parameter p where p.key = 'hsf.staging_alert_days'), 14))
        or coalesce(u.uploaded_at, u.created_at) + make_interval(days =>
          least(730, greatest(1, coalesce((select p.value::int from msp_env_parameter p where p.key = 'hsf.staging_retention_days'), 730))))
          < now() + interval '30 days'
        or (u.status = 'uploaded' and u.scan_status = 'error' and u.scan_attempts >= 5))
   and hsf_is_staff();
comment on view hsf_staging_alerts is 'Contract 9.5 and 10.3. Uploads holding bytes in the hsf-staging bucket for longer than hsf.staging_alert_days, or within 30 days of the two year limit, or whose security scan ended in an error five times (scan_exhausted, cleared with hsf_scan_reset), with the date the bytes expire (expires_on). Staff only (forge_admin, forge_omp, forge_safety_reviewer); nobody else sees a row. No file names.';
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
           'transfer_blocked_reason', u.transfer_blocked_reason,
           'expires_on', (coalesce(u.uploaded_at, u.created_at) + make_interval(days => r.days))::date,
           'scan_exhausted', (u.status = 'uploaded' and u.scan_status = 'error' and u.scan_attempts >= 5))
         order by coalesce(u.uploaded_at, u.created_at), u.id), '[]'::jsonb)
    from hsf_upload u
    join msp_client_account a on a.id = u.client_account_id
    cross join (select hsf_staging_retention_days() as days) r
   where u.storage_path is not null
     and u.status <> 'awaiting_upload'
     and (coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days =>
            coalesce(msp_env_get_int('hsf.staging_alert_days'), 14))
          or coalesce(u.uploaded_at, u.created_at) + make_interval(days => r.days) < now() + interval '30 days'
          or (u.status = 'uploaded' and u.scan_status = 'error' and u.scan_attempts >= 5));
$$;
comment on function hsf_staging_alerts_list is 'Contract 9.5 and 10.3. The rows of hsf_staging_alerts for the service role (scheduled alerts), oldest first, with expires_on and scan_exhausted.';

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
           'scan_status', u.scan_status,
           'scanned_at', u.scanned_at,
           'deletable', hsf_upload_deletable(u.status, u.storage_path, u.transfer_claimed_at),
           -- Only for bytes that stay until the client deletes them or the limit;
           -- bytes the cleanup queue removes on its next run have no such date.
           'expires_on', case when u.storage_path is not null
                               and u.status not in ('transferred','staging_deleted','expired','client_deleted')
                               and not hsf_upload_awaits_cleanup(u.status, u.transfer_blocked_reason, u.uploaded_at, u.scan_status)
                              then (coalesce(u.uploaded_at, u.created_at) + make_interval(days => r.days))::date end,
           'created_at', u.created_at,
           'uploaded_at', u.uploaded_at,
           'transferred_at', u.transferred_at,
           'staging_deleted_at', u.staging_deleted_at,
           'mco_document_ref', u.mco_document_ref)
         order by u.created_at desc, u.id), '[]'::jsonb)
    from hsf_upload u
    join msp_client_account a on a.id = u.client_account_id
    cross join (select hsf_staging_retention_days() as days) r
    left join hsf_file_item fi on fi.id = u.file_item_id
    left join hsf_element e on e.id = fi.element_id
   where p_auth_user is not null
     and a.auth_user_id = p_auth_user
     and (p_file_id is null or u.file_id = p_file_id);
$$;
comment on function hsf_my_uploads is 'Contract 049, 10.3 to 10.6. The uploads of the auth user''s company account, newest first, optionally for one File, with the scan state, why an upload is blocked, whether the client may still delete it (not while a transfer is in flight), and expires_on (the date its bytes leave Care Net staging under the two year limit) while it is held in staging and not waiting for the cleanup queue.';

-- 10. Deletion by the client (contract 10.5) --------------------------------------------------------

create or replace function hsf_deletion_request_create(p_auth_user uuid, p_upload_ids uuid[], p_channel text, p_acknowledged boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_ids uuid[];
  v_email text;
  v_phone text;
  v_phone_ok boolean;
  v_hint text;
  v_recent int;
  v_ok int;
  v_row hsf_deletion_request;
begin
  v_acc := hsf_account_of(p_auth_user);
  if v_acc.id is null then
    raise exception 'No company account is linked to this sign in.';
  end if;
  if p_acknowledged is distinct from true then
    raise exception 'Tick that you understand deleting cannot be undone before asking for a PIN.';
  end if;
  if p_channel is null or p_channel not in ('email','sms') then
    raise exception 'Choose email or SMS for the PIN.';
  end if;

  select nullif(btrim(u.email), ''), nullif(btrim(to_jsonb(u) ->> 'phone'), ''),
         (to_jsonb(u) ->> 'phone_confirmed_at') is not null
    into v_email, v_phone, v_phone_ok
    from auth.users u where u.id = p_auth_user;
  if p_channel = 'email' then
    if v_email is null then
      raise exception 'This sign in has no email address for the PIN.';
    end if;
    -- The first character and the domain only, for example f***@example.co.za.
    v_hint := left(v_email, 1) || '***@' || split_part(v_email, '@', 2);
  else
    if not coalesce(msp_env_get_bool('hsf.deletion_sms_enabled'), false)
       or v_phone is null or not coalesce(v_phone_ok, false) then
      raise exception 'A PIN by SMS is not available for this sign in. Choose email.';
    end if;
    v_hint := 'number ending ' || right(regexp_replace(v_phone, '[^0-9]', '', 'g'), 4);
  end if;

  select array_agg(distinct x order by x) into v_ids from unnest(coalesce(p_upload_ids, '{}'::uuid[])) x where x is not null;
  if v_ids is null then
    raise exception 'Choose at least one document to delete.';
  end if;
  if cardinality(v_ids) > 50 then
    raise exception 'Delete at most 50 documents at a time.';
  end if;
  -- Only the account's own uploads whose bytes are still in Care Net staging. A
  -- document of another account and one that does not exist read the same.
  select count(*) into v_ok
    from hsf_upload u
   where u.id = any(v_ids) and u.client_account_id = v_acc.id
     and hsf_upload_deletable(u.status, u.storage_path, u.transfer_claimed_at);
  if v_ok <> cardinality(v_ids) then
    raise exception 'One or more of the chosen documents cannot be deleted here. A document that has moved to MyClinicOnline is deleted through MyClinicOnline, and a document being moved there now can be deleted again once the move has finished or stopped.';
  end if;

  -- Each request sends a PIN, so an account may ask at most 5 times an hour.
  -- SQLSTATE PT429 is the rate limit refusal (429 at the API).
  perform pg_advisory_xact_lock(hashtext('hsf_deletion_request'), hashtext(v_acc.id::text));
  select count(*) into v_recent
    from hsf_deletion_request r
   where r.client_account_id = v_acc.id and r.requested_at > now() - interval '1 hour';
  if v_recent >= 5 then
    raise exception 'Too many deletion requests in the last hour. Please try again later.' using errcode = 'PT429';
  end if;

  -- A new PIN replaces the last one, so earlier open requests are cancelled.
  update hsf_deletion_request set status = 'cancelled'
   where client_account_id = v_acc.id and status = 'pending';

  insert into hsf_deletion_request (client_account_id, auth_user_id, upload_ids, channel, acknowledged_irreversible,
                                    requested_at, expires_at)
  values (v_acc.id, p_auth_user, v_ids, p_channel, true, now(), now() + interval '10 minutes')
  returning * into v_row;

  insert into msp_audit (actor, event_type, event_detail)
  values (coalesce(v_email, 'client'), 'hsf_deletion_requested',
          jsonb_build_object('request_id', v_row.id, 'client_account_id', v_acc.id, 'channel', p_channel,
                             'upload_ids', to_jsonb(v_ids)));

  return jsonb_build_object('request_id', v_row.id, 'expires_at', v_row.expires_at, 'channel', v_row.channel,
                            'destination_hint', v_hint);
end;
$$;
comment on function hsf_deletion_request_create is 'Contract 10.5. Opens a deletion request after the client has read the warning and ticked that it cannot be undone. Every upload must be the account''s own and still held in Care Net staging (hsf_upload_deletable); at most 50; at most 5 requests per account per hour (SQLSTATE PT429 beyond that). SMS only when hsf.deletion_sms_enabled and the sign in has a confirmed phone. Earlier open requests are cancelled. Returns {request_id, expires_at, channel, destination_hint}; the server then asks Supabase Auth to send the PIN. Audited as hsf_deletion_requested.';

create or replace function hsf_deletion_request_pin_sent(p_auth_user uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row hsf_deletion_request;
begin
  select r.* into v_row from hsf_deletion_request r where r.id = p_request_id for update;
  if v_row.id is null or p_auth_user is null or v_row.auth_user_id <> p_auth_user then
    raise exception 'That deletion request was not found.' using errcode = 'P0002';
  end if;
  if v_row.status <> 'pending' or v_row.expires_at <= now() or v_row.pin_sent_at is not null then
    raise exception 'This deletion request is no longer open. Start again to receive a new PIN.';
  end if;
  update hsf_deletion_request set pin_sent_at = now() where id = v_row.id returning * into v_row;
  return jsonb_build_object('request_id', v_row.id, 'pin_sent_at', v_row.pin_sent_at);
end;
$$;
comment on function hsf_deletion_request_pin_sent is 'Contract 10.5. Called by the server only after Supabase Auth accepted the request to send the PIN for this deletion request: records pin_sent_at, without which no PIN attempt is counted and nothing is confirmed. Once per request.';

create or replace function hsf_deletion_request_cancel(p_auth_user uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row hsf_deletion_request;
begin
  select r.* into v_row from hsf_deletion_request r where r.id = p_request_id for update;
  if v_row.id is null or p_auth_user is null or v_row.auth_user_id <> p_auth_user then
    raise exception 'That deletion request was not found.' using errcode = 'P0002';
  end if;
  if v_row.status = 'pending' then
    update hsf_deletion_request set status = 'cancelled' where id = v_row.id returning * into v_row;
    insert into msp_audit (actor, event_type, event_detail)
    values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_deletion_request_cancelled',
            jsonb_build_object('request_id', v_row.id, 'client_account_id', v_row.client_account_id));
  end if;
  return jsonb_build_object('request_id', v_row.id, 'status', v_row.status);
end;
$$;
comment on function hsf_deletion_request_cancel is 'Contract 10.5. Cancels the caller''s pending deletion request, for example when Supabase Auth could not send its PIN, so a request whose PIN never went out can never be confirmed. Audited as hsf_deletion_request_cancelled.';

create or replace function hsf_deletion_request_attempt(p_auth_user uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row hsf_deletion_request;
  v_acc uuid;
begin
  -- The account lock first, in the same order as hsf_deletion_request_create
  -- (advisory lock, then rows), so the two never wait on each other.
  select r.client_account_id into v_acc from hsf_deletion_request r where r.id = p_request_id;
  if v_acc is not null then
    perform pg_advisory_xact_lock(hashtext('hsf_deletion_request'), hashtext(v_acc::text));
  end if;
  select r.* into v_row from hsf_deletion_request r where r.id = p_request_id for update;
  if v_row.id is null or p_auth_user is null or v_row.auth_user_id <> p_auth_user then
    raise exception 'That deletion request was not found.' using errcode = 'P0002';
  end if;
  if v_row.status = 'pending' and v_row.expires_at <= now() then
    update hsf_deletion_request set status = 'expired' where id = v_row.id returning * into v_row;
  elsif v_row.status = 'pending' and v_row.pin_sent_at is null then
    -- No PIN went out for this request, so no PIN can be checked against it.
    return jsonb_build_object('allowed', false, 'attempts_left', greatest(0, 5 - v_row.attempts), 'status', 'pin_not_sent');
  elsif v_row.status = 'pending' and v_row.attempts >= 5 then
    update hsf_deletion_request set status = 'locked' where id = v_row.id returning * into v_row;
    insert into msp_audit (actor, event_type, event_detail)
    values (coalesce(hsf_user_email(p_auth_user), 'client'), 'hsf_deletion_request_locked',
            jsonb_build_object('request_id', v_row.id, 'client_account_id', v_row.client_account_id));
  elsif v_row.status = 'pending' then
    -- Also counted per account: a new request within the hour does not bring a
    -- fresh set of guesses. At most 10 PIN attempts per account per hour.
    if (select coalesce(sum(r.attempts), 0) from hsf_deletion_request r
         where r.client_account_id = v_row.client_account_id
           and r.requested_at > now() - interval '1 hour') >= 10 then
      return jsonb_build_object('allowed', false, 'attempts_left', greatest(0, 5 - v_row.attempts), 'status', 'rate_limited');
    end if;
    -- Counted before the server asks Supabase Auth to check the PIN.
    update hsf_deletion_request set attempts = attempts + 1 where id = v_row.id returning * into v_row;
    return jsonb_build_object('allowed', true, 'attempts_left', 5 - v_row.attempts, 'status', v_row.status);
  end if;
  return jsonb_build_object('allowed', false, 'attempts_left', greatest(0, 5 - v_row.attempts), 'status', v_row.status);
end;
$$;
comment on function hsf_deletion_request_attempt is 'Contract 10.5. Counts one PIN attempt on the caller''s pending request before the server asks Supabase Auth to verify it. Returns {allowed, attempts_left, status}. After 10 minutes the request reads expired; after 5 attempts the next one locks it. A request whose PIN was never sent answers status pin_not_sent, and an account with 10 attempts in the last hour answers status rate_limited; neither counts an attempt. A request of another person raises P0002.';

create or replace function hsf_deletion_request_confirm(p_auth_user uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row hsf_deletion_request;
  v_up hsf_upload;
  v_email text := coalesce(hsf_user_email(p_auth_user), 'client');
  v_revoked int;
  v_n int := 0;
begin
  select r.* into v_row from hsf_deletion_request r where r.id = p_request_id for update;
  if v_row.id is null or p_auth_user is null or v_row.auth_user_id <> p_auth_user then
    raise exception 'That deletion request was not found.' using errcode = 'P0002';
  end if;
  if v_row.status <> 'pending' or v_row.expires_at <= now() then
    raise exception 'This deletion request is no longer open. Start again to receive a new PIN.';
  end if;
  if v_row.pin_sent_at is null or v_row.attempts < 1 then
    -- The server sends this request's PIN, counts an attempt and verifies the
    -- PIN before it confirms.
    raise exception 'The PIN has not been checked for this deletion request.';
  end if;

  -- Every document must still be deletable; otherwise nothing is deleted.
  perform 1 from hsf_upload u where u.id = any(v_row.upload_ids) order by u.id for update;
  if (select count(*) from hsf_upload u
       where u.id = any(v_row.upload_ids) and u.client_account_id = v_row.client_account_id
         and hsf_upload_deletable(u.status, u.storage_path, u.transfer_claimed_at)) <> cardinality(v_row.upload_ids) then
    raise exception 'One or more of the chosen documents can no longer be deleted here. Start again.';
  end if;

  for v_up in select u.* from hsf_upload u where u.id = any(v_row.upload_ids) order by u.id loop
    update hsf_upload
       set status = 'client_deleted', transfer_blocked_reason = null, transfer_claimed_at = null
     where id = v_up.id;
    v_revoked := hsf_revoke_upload_evidence(v_up.id);
    -- The fingerprints, never the bytes or the file name.
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values (v_email, 'hsf_upload_client_deleted',
            jsonb_build_object('upload_id', v_up.id, 'request_id', v_row.id, 'status_before', v_up.status,
                               'sha256_client', v_up.sha256_client, 'sha256_server', v_up.sha256_server,
                               'evidence_revoked', v_revoked),
            v_up.file_id);
    v_n := v_n + 1;
  end loop;

  update hsf_deletion_request set status = 'confirmed', confirmed_at = now() where id = v_row.id;
  return jsonb_build_object('request_id', v_row.id, 'status', 'confirmed', 'deleted', v_n,
                            'upload_ids', to_jsonb(v_row.upload_ids));
end;
$$;
comment on function hsf_deletion_request_confirm is 'Contract 10.5. Called only after the server has verified the PIN with Supabase Auth. The caller''s request must be pending, unexpired, have had its PIN sent (pin_sent_at) and be attempted. Every chosen upload becomes client_deleted (block cleared, so the cleanup queue removes its bytes), its evidence is withdrawn through hsf_revoke_upload_evidence and the compliance figure recomputed. All or nothing. Audited per upload as hsf_upload_client_deleted with the fingerprints, never the bytes.';

-- 11. Execute rights --------------------------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'hsf_staging_retention_days()',
    'hsf_upload_deletable(text, text, timestamptz)',
    'hsf_upload_awaits_cleanup(text, text, timestamptz, text)',
    'hsf_revoke_upload_evidence(uuid)',
    'hsf_client_verified(uuid)',
    'hsf_request_client_verification(uuid)',
    'hsf_upload_gate(uuid)',
    'hsf_register_upload(uuid, jsonb)',
    'hsf_scan_claim(int)',
    'hsf_scan_record(uuid, text, text, jsonb)',
    'hsf_transfer_claim(int)',
    'hsf_transfer_record(uuid, text, text, text, text, text, text)',
    'hsf_retention_queue(int)',
    'hsf_mark_expired(uuid)',
    'hsf_mark_staging_deleted(uuid)',
    'hsf_transfer_cleanup_queue(int)',
    'hsf_staging_alerts_list()',
    'hsf_my_uploads(uuid, uuid)',
    'hsf_deletion_request_create(uuid, uuid[], text, boolean)',
    'hsf_deletion_request_pin_sent(uuid, uuid)',
    'hsf_deletion_request_cancel(uuid, uuid)',
    'hsf_deletion_request_attempt(uuid, uuid)',
    'hsf_deletion_request_confirm(uuid, uuid)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- Verify, revoke and the scan reset: the service role, or signed in forge staff
-- (checked in the body).
revoke execute on function hsf_verify_client(uuid, text, text) from public, anon;
revoke execute on function hsf_revoke_client_verification(uuid, text) from public, anon;
revoke execute on function hsf_scan_reset(uuid) from public, anon;
grant execute on function hsf_verify_client(uuid, text, text) to authenticated, service_role;
grant execute on function hsf_revoke_client_verification(uuid, text) to authenticated, service_role;
grant execute on function hsf_scan_reset(uuid) to authenticated, service_role;
