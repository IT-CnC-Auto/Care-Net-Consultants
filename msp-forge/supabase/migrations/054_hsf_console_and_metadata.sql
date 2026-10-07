-- CNC MSP FORGE | HSF-CON-01 v1.0.0 | HSF staff console and metadata removal 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 11 (Amendment 3), items 11.1 to 11.5,
-- with hsf/SIGNOFF-CRITERIA.md sections 6.1 and 6.2 for the sign off rules.
--
-- What this migration does:
--   1. Parameter hsf.signoff_register_check_max_days (30, from 1 to 365).
--   2. Content disarm (11.1): hsf_upload gains the fingerprint, size and list of
--      removed details of the cleaned copy that replaces the staged bytes. A
--      clean scan is recorded only with hsf_scan_record_clean, which carries the
--      cleaned fingerprint; the plain hsf_scan_record refuses 'clean'. Only a
--      cleaned upload is claimed for transfer, and the transfer compares the
--      server and receipt fingerprints with sha256_clean. hsf_my_uploads shows
--      the plain labels of what was removed. The write back is the one scan step
--      that changes staging, so a claimed scan is held for 30 minutes
--      (scan_claim_id, scan_claimed_at) and its cleaned fingerprint is announced
--      first (hsf_scan_write_back), which is refused once the upload has left
--      the scan; the cleanup and retention queues wait while a scan holds an
--      upload, so a deleted document is never written back into staging.
--   3. A document in transfer is never deletable by the client (11.2); a blocked
--      transfer that stopped part way returns to uploaded through the sweep, so
--      it becomes deletable again. An account has at most 5 PIN attempts an
--      hour (11.3), counted over every request that could take a PIN in that hour.
--   4. The release rules (11.4, 11.5): one function, hsf_release_rules, holds
--      every rule of the release gate. hsf_release_gate raises its first reason
--      and hsf_release_readiness lists them all without inserting anything. A
--      register check older than hsf.signoff_register_check_max_days before
--      the decision day no longer releases a File. Credentials frozen by a
--      release take a fresh register check as a dated entry of its own
--      (register_rechecks, append only under hsf_signatory_guard), so what the
--      released File relied on never changes.
--   5. Signatory expiry alerts (11.4): the staff view
--      hsf_signatory_expiry_alerts and hsf_signatory_expiry_alerts_list().
--   6. The staff console functions (11.5). Each takes the verified auth user,
--      runs for the service role only, checks hsf_user_is_staff in its body and
--      records the staff member's email (verified_by, revoked_by, created_by,
--      or the audit row). Verify, revoke and the scan reset share their body with
--      the 052 functions through internal *_by helpers. The staff email on a
--      sign off is only in its audit row, never in hsf_signoff, which the
--      client reads.
--
-- Nothing here writes file content, a PIN, a key or a token to msp_audit.
-- Migrations 047 to 053 are not edited: every changed function is redefined
-- here with create or replace, keeping security definer, the fixed search path
-- and service role only execute unless stated.

-- 1. Parameter ---------------------------------------------------------------------------------

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description, updated_by) values
  ('hsf.signoff_register_check_max_days', '30', 'integer', 1, 365, 'hsf',
   'Contract 11.4. The oldest a signatory''s public register check may be, in days before the decision day, for a safety content sign off to release a File. Credentials are checked at the point of use.',
   'migration_054')
on conflict (key) do nothing;

create or replace function hsf_signoff_register_check_max_days()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select least(365, greatest(1, coalesce(msp_env_get_int('hsf.signoff_register_check_max_days'), 30)));
$$;
comment on function hsf_signoff_register_check_max_days is 'Contract 11.4. hsf.signoff_register_check_max_days, held between 1 and 365 whatever the stored value.';

-- 2. hsf_upload: the cleaned copy (contract 11.1) ------------------------------------------------

alter table hsf_upload
  add column sha256_clean text check (sha256_clean ~ '^[0-9a-f]{64}$'),
  add column metadata_removed jsonb check (metadata_removed is null or jsonb_typeof(metadata_removed) = 'array'),
  add column cleaned_at timestamptz,
  add column size_bytes_clean bigint check (size_bytes_clean > 0);
-- The four are written together by hsf_scan_record_clean, never one without the others.
alter table hsf_upload add constraint hsf_upload_clean_complete check (
  (sha256_clean is null) = (cleaned_at is null)
  and (sha256_clean is null) = (size_bytes_clean is null)
  and (sha256_clean is null) = (metadata_removed is null));
comment on column hsf_upload.sha256_clean is 'Contract 11.1. SHA 256 of the cleaned copy that the scan pass wrote over the staged object once the structural check and the antivirus engine passed and every non essential detail was removed. The transfer compares the server and receipt fingerprints with this value; sha256_client stays as the proof of what the client sent.';
comment on column hsf_upload.metadata_removed is 'Contract 11.1. What the cleaner removed, as a json array of {code, message, label} in plain words (an empty array when there was nothing to remove). Never file content.';
comment on column hsf_upload.cleaned_at is 'Contract 11.1. When the cleaned copy was recorded (hsf_scan_record_clean).';
comment on column hsf_upload.size_bytes_clean is 'Contract 11.1. Size in bytes of the cleaned copy now held in staging.';
-- The scan pass's hold on an upload (contract 11.1). hsf_scan_claim sets both
-- claim columns; hsf_scan_write_back renews the hold and records the cleaned
-- copy it is about to write; a recorded result clears the hold.
alter table hsf_upload
  add column scan_claim_id uuid,
  add column scan_claimed_at timestamptz,
  add column scan_write_back jsonb check (scan_write_back is null or jsonb_typeof(scan_write_back) = 'object');
comment on column hsf_upload.scan_claim_id is 'Contract 11.1. Identifies the scan pass that claimed the upload (hsf_scan_claim). hsf_scan_write_back accepts the write back only from that pass.';
comment on column hsf_upload.scan_claimed_at is 'Contract 11.1. When the scan pass claimed the upload or announced its write back. For 30 minutes after it no other pass claims the upload and the cleanup and retention queues leave its staged object alone. Cleared when a scan result is recorded.';
comment on column hsf_upload.scan_write_back is 'Contract 11.1. The cleaned copy a scan pass announced before writing it over the staged object: {sha256_clean, size_bytes, metadata_removed, announced_at}. A later pass accepts staged bytes with this fingerprint as the upload''s own. Cleared when the clean result is recorded or the upload leaves the scan.';

create or replace function hsf_scan_claim_held(p_claimed_at timestamptz)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_claimed_at is not null and p_claimed_at >= now() - interval '30 minutes';
$$;
comment on function hsf_scan_claim_held is 'Contract 11.1. True while a scan pass holds an upload: claimed, or its write back announced, in the last 30 minutes.';

comment on column hsf_upload.scan_status is 'Contract 10.4 and 11.1. pending until the scan pass has run; clean when the built in structural check and the antivirus engine both passed and the cleaned copy replaced the staged bytes (recorded only by hsf_scan_record_clean, with sha256_clean); infected or harmful rejects the upload, as does a file the cleaner refused; error is retried by hsf_scan_claim up to five attempts. Only a clean upload with a cleaned fingerprint is ever claimed for transfer.';

-- 3. Security scan: a clean result carries the cleaned fingerprint (contract 11.1) ---------------

-- The 052 claim with the hold added: an upload another pass holds is not handed
-- out again, and each claimed upload gets a new claim identifier.
create or replace function hsf_scan_claim(p_limit int)
returns setof hsf_upload
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int := greatest(1, least(coalesce(p_limit, 10), 100));
begin
  return query
    with c as (
      select u.id
        from hsf_upload u
       where u.status = 'uploaded'
         and u.scan_status in ('pending','error')
         and u.scan_attempts < 5
         and u.transfer_blocked_reason is null
         and u.storage_path is not null
         and not hsf_scan_claim_held(u.scan_claimed_at)
       order by u.uploaded_at nulls last, u.created_at, u.id
       limit v_limit
       for update of u skip locked
    ), claimed as (
      update hsf_upload u
         set scan_attempts = u.scan_attempts + 1, scan_claim_id = gen_random_uuid(), scan_claimed_at = now()
        from c
       where u.id = c.id
      returning u.*
    )
    select * from claimed order by uploaded_at nulls last, created_at, id;
end;
$$;
comment on function hsf_scan_claim is 'Contract 10.4 and 11.1. The scan pass''s claim, oldest first, at most 100: uploaded rows whose scan is pending or ended in an engine error, with bytes present, not blocked, fewer than five attempts and not held by another pass (hsf_scan_claim_held). Locked with for update skip locked; each claimed row''s scan_attempts goes up by one and it gets a new scan_claim_id, held for 30 minutes.';

create or replace function hsf_scan_write_back(
  p_upload_id uuid, p_claim_id uuid, p_sha256_clean text, p_size_bytes bigint, p_metadata_removed jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_sha text := lower(btrim(coalesce(p_sha256_clean, '')));
  v_removed jsonb := coalesce(p_metadata_removed, '[]'::jsonb);
begin
  if v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'The fingerprint of the cleaned copy must be 64 hexadecimal characters.';
  end if;
  if p_size_bytes is null or p_size_bytes < 1 then
    raise exception 'The size of the cleaned copy must be given in bytes.';
  end if;
  if jsonb_typeof(v_removed) <> 'array' or jsonb_array_length(v_removed) > 50 then
    raise exception 'The removed details must be a list of at most 50 entries.';
  end if;
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.' using errcode = 'P0002';
  end if;
  -- A document the client deleted, or one that failed, has left the scan: its
  -- cleaned copy must never be written back into staging.
  if v_up.status <> 'uploaded' or v_up.scan_status not in ('pending','error') or v_up.storage_path is null then
    raise exception 'The upload is not waiting for a security scan (status %, scan %), so its cleaned copy must not be written.',
      v_up.status, v_up.scan_status;
  end if;
  if p_claim_id is null or v_up.scan_claim_id is distinct from p_claim_id then
    raise exception 'This scan pass no longer holds the upload, so its cleaned copy must not be written.';
  end if;
  update hsf_upload
     set scan_claimed_at = now(),
         scan_write_back = jsonb_build_object('sha256_clean', v_sha, 'size_bytes', p_size_bytes,
                                              'metadata_removed', v_removed, 'announced_at', now())
   where id = v_up.id;
  return jsonb_build_object('upload_id', v_up.id, 'sha256_clean', v_sha, 'held_until', now() + interval '30 minutes');
end;
$$;
comment on function hsf_scan_write_back is 'Contract 11.1. Called by the scan pass just before it writes the cleaned copy over the staged object. Accepted only while the upload is uploaded with its scan pending or error and still held by the calling pass (p_claim_id is its scan_claim_id); it then renews the 30 minute hold and records {sha256_clean, size_bytes, metadata_removed} in scan_write_back, so a later pass accepts that copy as the upload''s own bytes. Refused once the upload has left the scan (for example the client deleted it), and then nothing is written. Service role only.';

-- The 052 function, unchanged except that 'clean' is refused (a clean result is
-- recorded only by hsf_scan_record_clean) and that recording a result ends the
-- scan pass's hold.
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
  if p_result = 'clean' then
    raise exception 'A clean scan result must carry the fingerprint of the cleaned copy. Record it with hsf_scan_record_clean.';
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
           scanned_at = now(), scan_findings = v_findings, transfer_claimed_at = null,
           scan_claim_id = null, scan_claimed_at = null, scan_write_back = null
     where id = v_up.id;
    v_revoked := hsf_revoke_upload_evidence(v_up.id);
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_upload_scan_rejected',
            jsonb_build_object('upload_id', v_up.id, 'result', 'fingerprint_mismatch', 'engine', v_engine,
                               'findings', v_findings, 'evidence_revoked', v_revoked),
            v_up.file_id);
  elsif p_result in ('infected','harmful') then
    -- The plain words of the findings become the reason the client reads (a
    -- refusal by the metadata cleaner arrives here as harmful). Each message
    -- loses its closing full stop, so several read 'X; Y.' not 'X.; Y.'.
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
    update hsf_upload
       set status = 'rejected', reject_reason = v_reason, scan_status = p_result, scan_engine = v_engine,
           scanned_at = now(), scan_findings = v_findings, transfer_claimed_at = null,
           transfer_blocked_reason = null, scan_claim_id = null, scan_claimed_at = null, scan_write_back = null
     where id = v_up.id;
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
    -- the five attempts. Only inspection errors count. An announced cleaned copy
    -- stays on record: the write back may have reached staging.
    update hsf_upload
       set scan_status = 'error', scan_engine = v_engine, scanned_at = now(), scan_findings = v_findings,
           scan_claim_id = null, scan_claimed_at = null,
           scan_attempts = case
             when jsonb_array_length(v_findings) > 0
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
comment on function hsf_scan_record is 'Contract 10.4 as amended by 11.1. Records a scan result other than clean for an uploaded row whose scan is pending or error, and ends the scan pass''s hold. clean is refused: a clean result must carry the cleaned fingerprint (hsf_scan_record_clean). error: scan_status error, the upload stays uploaded for a retry; an error that only says the antivirus engine is not configured or did not answer (codes av_not_configured, av_error) gives its attempt back. error with a fingerprint_mismatch finding: the upload fails like a mismatch at transfer, with its evidence withdrawn. infected or harmful (including a file the metadata cleaner refused): the upload is rejected with ''The file failed the security scan: <plain summary of the findings>'', any transfer block cleared, its evidence withdrawn through hsf_revoke_upload_evidence, and its bytes leave through the cleanup queue. Audited as hsf_upload_scanned or hsf_upload_scan_rejected.';

create or replace function hsf_scan_record_clean(
  p_upload_id uuid, p_engine text, p_findings jsonb,
  p_sha256_clean text, p_metadata_removed jsonb, p_size_bytes bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
  v_engine text := nullif(left(btrim(coalesce(p_engine, '')), 200), '');
  v_findings jsonb := coalesce(p_findings, '[]'::jsonb);
  v_sha text := lower(btrim(coalesce(p_sha256_clean, '')));
  v_removed jsonb := coalesce(p_metadata_removed, '[]'::jsonb);
  v_clean jsonb;
  v_attempts int;
begin
  if v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'A clean scan result must carry the SHA 256 fingerprint of the cleaned copy, 64 hexadecimal characters.';
  end if;
  if jsonb_typeof(v_findings) <> 'array' or jsonb_array_length(v_findings) > 50 then
    raise exception 'The scan findings must be a list of at most 50 entries.';
  end if;
  if jsonb_typeof(v_removed) <> 'array' or jsonb_array_length(v_removed) > 50
     or exists (select 1 from jsonb_array_elements(v_removed) x
                 where jsonb_typeof(x) <> 'object'
                    or coalesce(x ->> 'code', '') !~ '^[a-z0-9_]{1,60}$'
                    or coalesce(x ->> 'message', '') ~ '^[[:space:][:cntrl:]]*$'
                    or (x ? 'label' and coalesce(x ->> 'label', '') ~ '^[[:space:][:cntrl:]]*$')) then
    raise exception 'The removed details must be a list of at most 50 entries, each with a code and a message in plain words.';
  end if;
  if p_size_bytes is null or p_size_bytes < 1 then
    raise exception 'The size of the cleaned copy must be given in bytes.';
  end if;
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.' using errcode = 'P0002';
  end if;
  if v_up.status <> 'uploaded' or v_up.scan_status not in ('pending','error') then
    raise exception 'The upload is not waiting for a security scan (status %, scan %).', v_up.status, v_up.scan_status;
  end if;
  -- The copy in staging is the one announced before the write back.
  if v_up.scan_write_back is not null and v_up.scan_write_back ->> 'sha256_clean' is distinct from v_sha then
    raise exception 'The cleaned fingerprint differs from the one announced before the write back.';
  end if;

  -- Plain words only: control characters become spaces, and a label (the short
  -- words the builder lists, for example 'author') falls back to the message.
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', x ->> 'code',
           'message', left(btrim(regexp_replace(x ->> 'message', '[[:cntrl:]]+', ' ', 'g')), 200),
           'label', left(btrim(regexp_replace(coalesce(x ->> 'label', x ->> 'message'), '[[:cntrl:]]+', ' ', 'g')), 200))
         order by o), '[]'::jsonb)
    into v_clean
    from jsonb_array_elements(v_removed) with ordinality t(x, o);

  update hsf_upload
     set scan_status = 'clean', scan_engine = v_engine, scanned_at = now(), scan_findings = v_findings,
         sha256_clean = v_sha, metadata_removed = v_clean, cleaned_at = now(), size_bytes_clean = p_size_bytes,
         scan_claim_id = null, scan_claimed_at = null, scan_write_back = null
   where id = v_up.id
  returning scan_attempts into v_attempts;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values ('hsf-mco-transfer', 'hsf_upload_scanned',
          jsonb_build_object('upload_id', v_up.id, 'result', 'clean', 'engine', v_engine, 'attempts', v_attempts,
                             'sha256_client', v_up.sha256_client, 'sha256_clean', v_sha,
                             'size_bytes_clean', p_size_bytes,
                             'metadata_removed', (select coalesce(jsonb_agg(x ->> 'code'), '[]'::jsonb)
                                                    from jsonb_array_elements(v_clean) x)),
          v_up.file_id);

  return jsonb_build_object('upload_id', v_up.id, 'status', 'uploaded', 'scan_status', 'clean',
                            'sha256_clean', v_sha, 'size_bytes_clean', p_size_bytes, 'metadata_removed', v_clean);
end;
$$;
comment on function hsf_scan_record_clean is 'Contract 11.1. Records a clean scan together with the cleaned copy the scan pass wrote over the staged object: scan_status clean, sha256_clean (64 lowercase hexadecimal characters, required), size_bytes_clean, cleaned_at and metadata_removed (a list of at most 50 {code, message, label?} entries in plain words; the label falls back to the message). Only an uploaded row whose scan is pending or error, and, when the pass announced its write back (hsf_scan_write_back), only with the announced fingerprint. Ends the scan pass''s hold. The client fingerprint stays as the proof of what the client sent. Audited as hsf_upload_scanned with both fingerprints and the removed codes.';

-- 4. Transfer: only cleaned copies move, compared with sha256_clean (contract 11.1) ---------------

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
    -- Hold: only fresh uploads that passed the scan and carry a cleaned copy;
    -- the worker records each as held and sends nothing.
    return query
      select u.*
        from hsf_upload u
       where u.status = 'uploaded'
         and u.scan_status = 'clean'
         and u.sha256_clean is not null
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
  -- is more than 30 minutes old (a worker that stopped part way), all clean
  -- and cleaned. Rows another worker has locked are skipped; the claimed rows
  -- move to transferring.
  return query
    with c as (
      select u.id
        from hsf_upload u
       where u.storage_path is not null
         and u.scan_status = 'clean'
         and u.sha256_clean is not null
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
comment on function hsf_transfer_claim is 'Contract 9.5, 10.4 and 11.1. The worker''s claim, oldest first, at most 100, of uploads that passed the security scan and carry a cleaned copy (scan_status clean and sha256_clean recorded) only. Mode hold: uploaded rows only (the worker records them held). Mode fixture or live: uploaded and held rows plus transferring rows claimed more than 30 minutes ago, locked with for update skip locked and moved to transferring. Blocked uploads and accounts without mco_transfer and document_storage consent are never returned.';

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
     and v_up.sha256_clean is not null and v_server = v_up.sha256_clean and v_receipt = v_up.sha256_clean then
    -- A transfer that was in flight when the document was deleted (the two year
    -- limit; since 11.2 never the client): MyClinicOnline now holds a copy Care
    -- Net must not lose track of. The receipt and reference are kept and the
    -- audit event asks for the deletion at MyClinicOnline; the status stays, so
    -- the worker keeps nothing and the cleanup queue removes any bytes still staged.
    update hsf_upload set mco_document_ref = v_ref, transfer_claimed_at = null where id = v_up.id;
    insert into hsf_mco_transfer (upload_id, mode, outcome, mco_document_ref, mco_receipt_sha256, error)
    values (v_up.id, p_mode, 'received', v_ref, v_receipt,
            'Received by MyClinicOnline after the document was ' || replace(v_up.status, '_', ' ')
            || ' in Care Net staging. Ask MyClinicOnline to delete it.');
    insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
    values ('hsf-mco-transfer', 'hsf_transfer_received_after_deletion',
            jsonb_build_object('upload_id', v_up.id, 'mode', p_mode, 'status', v_up.status,
                               'mco_document_ref', v_ref, 'sha256', v_up.sha256_clean,
                               'sha256_client', v_up.sha256_client,
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
    if v_up.sha256_clean is not null
       and (v_server is null or v_receipt is null
            or v_server <> v_up.sha256_clean or v_receipt <> v_up.sha256_clean) then
      -- Contract 11.1: what moves is the cleaned copy, so the server and receipt
      -- fingerprints must both equal sha256_clean. Otherwise the transfer is a
      -- mismatch and the staging copy is kept.
      v_outcome := 'hash_mismatch';
      v_error := coalesce(v_error, 'Reported as received, but the server and receipt fingerprints do not both match the cleaned copy.');
    end if;
  end if;

  -- Contract 10.4 and 11.1: nothing is held or handed to MyClinicOnline before
  -- it has passed the security scan and its cleaned copy is recorded. A
  -- mismatch or an error may still be recorded.
  if v_outcome in ('held','received') and (v_up.scan_status <> 'clean' or v_up.sha256_clean is null) then
    raise exception 'The upload has not passed the security scan with a cleaned copy (scan %).', v_up.scan_status;
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
    -- An error returns the upload to uploaded, to be claimed again and, from
    -- contract 11.2, deletable by the client again.
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
comment on function hsf_transfer_record is 'Contract 049, 9.5, 10.4 and 11.1. Accepts an upload that is uploaded, held or transferring. Appends hsf_mco_transfer and moves the upload: held to held; received with server and receipt fingerprints both equal to sha256_clean (the cleaned copy is what moves; the client fingerprint stays as the proof of what the client sent) to transferred, and the matching hsf_evidence row gains its MyClinicOnline fields; a mismatch to failed with the reason, withdrawing its evidence through hsf_revoke_upload_evidence; an error back to uploaded. held and received are refused for an upload that has not passed the security scan with a cleaned copy. A received matching sha256_clean for an upload that expired (or was deleted) while it was in flight keeps the MyClinicOnline reference and receipt, leaves the status, and is audited as hsf_transfer_received_after_deletion so the deletion at MyClinicOnline can be asked for. Audited.';

-- 5. Deletion by the client (contract 11.2 and 11.3) ------------------------------------------------

-- The signature of 052 is kept (hsf_my_uploads and the deletion functions call
-- it); the claim time no longer matters.
create or replace function hsf_upload_deletable(p_status text, p_storage_path text, p_claimed_at timestamptz)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_storage_path is not null
     -- A document on its way to MyClinicOnline may already be there, so it is
     -- never deleted here, whatever the age of the claim. An error returns it
     -- to uploaded, and then it is deletable again.
     and coalesce(p_status, '') not in ('transferring','transferred','staging_deleted','expired','client_deleted');
$$;
comment on function hsf_upload_deletable is 'Contract 10.5 as amended by 11.2. A client may delete an upload while its bytes are still in Care Net staging: any status except transferring (at any age of the claim: MyClinicOnline may already hold that copy), transferred, staging_deleted, expired and client_deleted. A transfer that errors returns the upload to uploaded, and it becomes deletable again. Once MyClinicOnline holds a document, deletion is MyClinicOnline''s process. p_claimed_at is kept for the 052 signature and not used.';

-- The 052 function with only the refusal reworded: since 11.2 a document in
-- transfer is deletable again only when the transfer stops with an error, never
-- once it has finished.
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
  -- Only the account's own uploads whose bytes are still in Care Net staging and
  -- not in transfer (contract 11.2). A document of another account and one that
  -- does not exist read the same.
  select count(*) into v_ok
    from hsf_upload u
   where u.id = any(v_ids) and u.client_account_id = v_acc.id
     and hsf_upload_deletable(u.status, u.storage_path, u.transfer_claimed_at);
  if v_ok <> cardinality(v_ids) then
    raise exception 'One or more of the chosen documents cannot be deleted here. A document that has moved to MyClinicOnline is deleted through MyClinicOnline, and a document being moved there now can be deleted only if the move stops.';
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
comment on function hsf_deletion_request_create is 'Contract 10.5 as amended by 11.2 (only the refusal wording changed: a document in transfer is deletable again only if the move stops). Opens a deletion request after the client has read the warning and ticked that it cannot be undone. Every upload must be the account''s own and still held in Care Net staging (hsf_upload_deletable); at most 50; at most 5 requests per account per hour (SQLSTATE PT429 beyond that). SMS only when hsf.deletion_sms_enabled and the sign in has a confirmed phone. Earlier open requests are cancelled. Returns {request_id, expires_at, channel, destination_hint}; the server then asks Supabase Auth to send the PIN. Audited as hsf_deletion_requested.';

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
    -- fresh set of guesses. At most 5 PIN attempts per account per hour
    -- (contract 11.3; 052 allowed 10). A PIN is tried only while its request is
    -- open, so every attempt of the last hour sits on a request that closed
    -- (expires_at) less than an hour ago, however long ago it was opened.
    if (select coalesce(sum(r.attempts), 0) from hsf_deletion_request r
         where r.client_account_id = v_row.client_account_id
           and r.expires_at > now() - interval '1 hour') >= 5 then
      return jsonb_build_object('allowed', false, 'attempts_left', greatest(0, 5 - v_row.attempts), 'status', 'rate_limited');
    end if;
    -- Counted before the server asks Supabase Auth to check the PIN.
    update hsf_deletion_request set attempts = attempts + 1 where id = v_row.id returning * into v_row;
    return jsonb_build_object('allowed', true, 'attempts_left', 5 - v_row.attempts, 'status', v_row.status);
  end if;
  return jsonb_build_object('allowed', false, 'attempts_left', greatest(0, 5 - v_row.attempts), 'status', v_row.status);
end;
$$;
comment on function hsf_deletion_request_attempt is 'Contract 10.5 as amended by 11.3. Counts one PIN attempt on the caller''s pending request before the server asks Supabase Auth to verify it. Returns {allowed, attempts_left, status}. After 10 minutes the request reads expired; after 5 attempts the next one locks it. A request whose PIN was never sent answers status pin_not_sent, and an account with 5 attempts in the last hour, over all its requests (every request open at any time in that hour, so a request opened more than an hour ago still counts), answers status rate_limited; neither counts an attempt. A request of another person raises P0002.';

-- The cleanup and retention queues of 052 wait while a scan pass holds an
-- upload (contract 11.1): the pass may still write its cleaned copy back, and a
-- removal before that write would leave the object in staging with no row
-- pointing at it. The marking functions refuse for the same reason. Nothing
-- else changes.
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
             and hsf_upload_awaits_cleanup(u.status, u.transfer_blocked_reason, u.uploaded_at, u.scan_status)
             and not hsf_scan_claim_held(u.scan_claimed_at)
           order by coalesce(u.transferred_at, u.uploaded_at, u.created_at), u.id
           limit greatest(1, least(coalesce(p_limit, 10), 100))) q;
$$;
comment on function hsf_transfer_cleanup_queue is 'Contract 9.5, 10.5 and 11.1. Staged bytes to remove, oldest first, at most 100: {upload_id, storage_path, reason} where reason is the status: transferred (the copy at MyClinicOnline is confirmed), failed, rejected (including a failed security scan) or client_deleted. A blocked upload is left out unless it was transferred or client deleted, never completed, or failed the security scan (hsf_upload_awaits_cleanup). An upload a scan pass still holds (hsf_scan_claim_held, at most 30 minutes) waits, so a cleaned copy written back late is removed too. The worker deletes the object through the Storage API and then calls hsf_mark_staging_deleted.';

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
             and u.status not in ('transferred','client_deleted','expired','staging_deleted')
             and not (u.status = 'transferring' and u.transfer_claimed_at >= now() - interval '30 minutes')
             and not hsf_scan_claim_held(u.scan_claimed_at)
             and coalesce(u.uploaded_at, u.created_at) < now() - make_interval(days => hsf_staging_retention_days())
           order by coalesce(u.uploaded_at, u.created_at), u.id
           limit greatest(1, least(coalesce(p_limit, 10), 100))) q;
$$;
comment on function hsf_retention_queue is 'Contract 10.3 and 11.1. Staged bytes older than hsf.staging_retention_days (two years), oldest first, at most 100: {upload_id, storage_path, reason: retention}. Uploads blocked by a consent withdrawal or a revoked verification are included: the two year limit overrides a block. A transfer in flight (transferring, claimed in the last 30 minutes) and an upload a scan pass holds wait. The worker deletes the object through the Storage API and then calls hsf_mark_expired.';

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
  if hsf_scan_claim_held(v_up.scan_claimed_at) then
    raise exception 'A security scan still holds this upload and may write to its staging copy. Try again after the scan.';
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
comment on function hsf_mark_staging_deleted is 'Contract 049, 9.5, 10.3, 10.5 and 11.1. After the worker has removed the bytes through the Storage API: transferred becomes staging_deleted; failed, rejected, client_deleted and expired keep their status. storage_path is cleared and staging_deleted_at set on the upload and its evidence row. The row and both fingerprints stay. Refused while a scan pass holds the upload. Audited.';

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
  if hsf_scan_claim_held(v_up.scan_claimed_at) then
    raise exception 'A security scan still holds this upload and may write to its staging copy. Try again after the scan.';
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
comment on function hsf_mark_expired is 'Contract 10.3 and 11.1. After the worker has deleted the bytes of an upload listed by hsf_retention_queue: status expired, storage_path cleared, staging_deleted_at set (on the upload and its evidence rows), the evidence withdrawn through hsf_revoke_upload_evidence. Refused for an upload younger than the limit, one in transfer, and one a scan pass holds. The row and its fingerprints stay. Audited as hsf_upload_expired.';

-- The 049 sweep, which the worker runs first on every run, now also frees a
-- blocked transfer that stopped part way (contract 11.2). A blocked upload is
-- never claimed for transfer again, so a worker that ended after the claim
-- would leave it 'transferring' for good: not deletable by the client, in no
-- queue and in no console list. After 30 minutes, the age at which
-- hsf_transfer_claim takes back an unblocked one, it returns to 'uploaded' as
-- a transfer error would; the client may delete it again, and a late receipt
-- is still recorded by hsf_transfer_record.
create or replace function hsf_sweep_stale_uploads(p_hours int default 24)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hours int := coalesce(p_hours, 24);
  v_n int;
  v_back jsonb;
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
  with back as (
    update hsf_upload
       set status = 'uploaded', transfer_claimed_at = null
     where status = 'transferring'
       and transfer_blocked_reason is not null
       and (transfer_claimed_at is null or transfer_claimed_at < now() - interval '30 minutes')
    returning id
  )
  select jsonb_agg(id order by id) into v_back from back;
  if v_back is not null then
    insert into msp_audit (actor, event_type, event_detail)
    values ('hsf-mco-transfer', 'hsf_transfer_stalled_returned',
            jsonb_build_object('upload_ids', v_back, 'returned', jsonb_array_length(v_back)));
  end if;
  return v_n;
end;
$$;
comment on function hsf_sweep_stale_uploads is 'Contract 9.5 and 11.2. Registrations still awaiting upload after p_hours (default 24) become failed with the reason ''The upload was not completed.''; their staging path then appears in hsf_transfer_cleanup_queue, so any bytes that did arrive are removed. A blocked upload whose transfer was claimed more than 30 minutes ago (a worker that stopped part way; a blocked upload is never claimed again) returns to uploaded, as a transfer error would, so the client may delete it again. Returns the number failed. Audited as hsf_uploads_swept and hsf_transfer_stalled_returned when anything moves.';

-- 6. What the client sees: the removed details (contract 11.1) --------------------------------------

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
           -- The plain labels of what the cleaner removed, each once, in the order
           -- reported; an empty list when nothing needed removing; null before
           -- the cleaned copy is recorded.
           'metadata_removed', case when u.metadata_removed is not null then
             (select coalesce(jsonb_agg(l.label order by l.first), '[]'::jsonb)
                from (select x ->> 'label' as label, min(o) as first
                        from jsonb_array_elements(u.metadata_removed) with ordinality t(x, o)
                       where coalesce(x ->> 'label', '') <> ''
                       group by x ->> 'label') l) end,
           'cleaned_at', u.cleaned_at,
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
comment on function hsf_my_uploads is 'Contract 049, 10.3 to 10.6 and 11.1. The uploads of the auth user''s company account, newest first, optionally for one File, with the scan state, the plain labels of the hidden details removed from the cleaned copy (metadata_removed, for ''Hidden details removed: author, company, location''), why an upload is blocked, whether the client may still delete it (never while a transfer is in flight), and expires_on (the date its bytes leave Care Net staging under the two year limit) while it is held in staging and not waiting for the cleanup queue.';

-- 7. The release rules, the gate and readiness (contract 11.4 and 11.5) -----------------------------

-- A fresh register check of credentials a release has frozen (contract 11.4).
-- hsf_signatory_guard (053) keeps every field of such a row as the released
-- File relied on it, so a later check is a dated entry of its own in
-- register_rechecks: appended, each later than the last, never changed or
-- removed. hsf_signatory_fit reads the latest check on or before the decision
-- day from the row's own check and these.
alter table hsf_signatory
  add column register_rechecks jsonb not null default '[]'::jsonb check (jsonb_typeof(register_rechecks) = 'array');
comment on column hsf_signatory.register_rechecks is 'Contract 11.4. Checks of the public register made after the credentials were frozen by a release: a list of {checked_on, proof_ref, recorded_by, recorded_at}, each dated after the last check on record. Appended through hsf_staff_signatory_save only; hsf_signatory_guard refuses any other change to it. register_checked_on and register_proof_ref keep the check the release relied on.';

-- The 053 guard, with the one addition of 11.4: a frozen row also accepts
-- register checks appended to register_rechecks, each with a date after the
-- last check on record and the reference of its saved proof. Nothing already
-- recorded may change.
create or replace function hsf_signatory_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mutable constant text[] := array['appointment_letter_recruitment_portal_ref','engagement_letter_recruitment_portal_ref',
                                     'register_rechecks'];
  v_old_n int;
  v_last date;
  v_e jsonb;
begin
  -- Only a row relied on by a released revision is frozen; before a release the
  -- credentials may be corrected, because the gate reads them at release time.
  if not exists (select 1
                   from hsf_signoff so
                   join hsf_release r on r.file_id = so.file_id and r.revision = so.revision
                  where so.signatory_id = old.id
                    and so.kind = 'safety_content' and so.decision = 'approved') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'hsf_signatory: these credentials support a released File and cannot be deleted';
  end if;
  if (to_jsonb(new) - v_mutable) is distinct from (to_jsonb(old) - v_mutable) then
    raise exception 'hsf_signatory: these credentials support a released File and are frozen; record a renewal or a correction as a new signatory row';
  end if;
  if (old.appointment_letter_recruitment_portal_ref is not null
      and new.appointment_letter_recruitment_portal_ref is distinct from old.appointment_letter_recruitment_portal_ref)
     or (old.engagement_letter_recruitment_portal_ref is not null
      and new.engagement_letter_recruitment_portal_ref is distinct from old.engagement_letter_recruitment_portal_ref) then
    raise exception 'hsf_signatory: a recruitment portal reference on credentials that support a released File is set once and never changed';
  end if;
  if new.register_rechecks is distinct from old.register_rechecks then
    v_old_n := jsonb_array_length(old.register_rechecks);
    if jsonb_array_length(new.register_rechecks) <= v_old_n
       or exists (select 1 from jsonb_array_elements(old.register_rechecks) with ordinality t(x, o)
                   where x is distinct from new.register_rechecks -> (o::int - 1)) then
      raise exception 'hsf_signatory: a register check on credentials that support a released File is appended, never changed or removed';
    end if;
    select max(d) into v_last
      from (select old.register_checked_on as d
            union all
            select (x ->> 'checked_on')::date from jsonb_array_elements(old.register_rechecks) x) c;
    for v_e in select x from jsonb_array_elements(new.register_rechecks) with ordinality t(x, o)
                where o > v_old_n order by o loop
      if jsonb_typeof(v_e) <> 'object' or coalesce(v_e ->> 'checked_on', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
         or length(btrim(coalesce(v_e ->> 'proof_ref', ''))) = 0
         or (v_last is not null and (v_e ->> 'checked_on')::date <= v_last) then
        raise exception 'hsf_signatory: a register check appended to credentials that support a released File needs a date after the last check and the reference of its saved proof';
      end if;
      v_last := (v_e ->> 'checked_on')::date;
    end loop;
  end if;
  return new;
end;
$$;
revoke execute on function hsf_signatory_guard() from public, anon, authenticated;
comment on function hsf_signatory_guard is 'Contract 10.8 and 11.4. Freezes a hsf_signatory row once an approved safety_content sign off that relies on it has released a File revision: no delete, and no change except adding each recruitment portal reference once and appending register checks to register_rechecks (each dated after the last check on record, with its proof; nothing recorded changes). Before a release the row may be corrected.';

-- Every register check on record for a signatory: the one on the credential
-- row (with its proof) and each one appended since.
create or replace function hsf_signatory_register_checks(p_signatory_id uuid)
returns table (checked_on date, proof_ref text)
language sql
stable
security definer
set search_path = public
as $$
  select s.register_checked_on, s.register_proof_ref
    from hsf_signatory s
   where s.id = p_signatory_id and s.register_checked_on is not null
     and length(btrim(coalesce(s.register_proof_ref, ''))) > 0
  union all
  select (x ->> 'checked_on')::date, x ->> 'proof_ref'
    from hsf_signatory s
    cross join jsonb_array_elements(s.register_rechecks) x
   where s.id = p_signatory_id;
$$;
comment on function hsf_signatory_register_checks is 'Contract 11.4. The register checks on record for a signatory: the credential row''s own (with saved proof) and every one appended to register_rechecks. Internal.';

-- The 053 function with the register check age rule of 11.4 added after the
-- check that the register was not checked after the decision. The check read is
-- the latest on record on or before the decision day.
create or replace function hsf_signatory_fit(p_signoff_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_so hsf_signoff;
  v_sig hsf_signatory;
  v_industry uuid;
  v_type text;
  v_allowed text;
  v_day date;
  v_max int := hsf_signoff_register_check_max_days();
  v_chk date;
  v_after date;
begin
  select * into v_so from hsf_signoff where id = p_signoff_id;
  if v_so.id is null then
    return 'the sign off does not exist';
  end if;
  if v_so.kind <> 'safety_content' then
    return 'the sign off is not a safety content sign off';
  end if;
  if v_so.decision is distinct from 'approved' then
    return 'the safety content sign off is not approved';
  end if;
  if v_so.signatory_id is null then
    return 'no signatory credentials are recorded on the safety content sign off';
  end if;
  select * into v_sig from hsf_signatory where id = v_so.signatory_id;
  select f.industry_id into v_industry from hsf_file f where f.id = v_so.file_id;
  -- The decision date is the South African calendar day of decided_at.
  v_day := (v_so.decided_at at time zone 'Africa/Johannesburg')::date;

  if v_sig.category like 'Can %' then
    return format('%s is a candidate category (%s %s) and never signs a File alone',
                  v_sig.full_name, v_sig.registration_body, v_sig.category);
  end if;

  -- The rows of the File's industry; an industry with none takes the general rows.
  if exists (select 1 from hsf_signoff_rule r where r.industry_id = v_industry) then
    select min(r.file_type),
           string_agg(r.registration_body || ' ' || r.category, ', ' order by r.registration_body, r.category)
      into v_type, v_allowed
      from hsf_signoff_rule r where r.industry_id = v_industry;
  else
    select min(r.file_type),
           string_agg(r.registration_body || ' ' || r.category, ', ' order by r.registration_body, r.category)
      into v_type, v_allowed
      from hsf_signoff_rule r where r.industry_id is null;
  end if;
  if not exists (select 1 from hsf_signoff_rule r
                  where r.registration_body = v_sig.registration_body and r.category = v_sig.category
                    and ((r.industry_id = v_industry)
                         or (r.industry_id is null
                             and not exists (select 1 from hsf_signoff_rule x where x.industry_id = v_industry)))) then
    return format('%s %s may not sign the safety content of a %s File; allowed: %s',
                  v_sig.registration_body, v_sig.category, v_type, coalesce(v_allowed, 'none recorded'));
  end if;

  if v_sig.registration_expires_on < v_day then
    return format('the registration of %s (%s %s) expired on %s, before the decision on %s',
                  v_sig.full_name, v_sig.registration_body, v_sig.registration_number,
                  to_char(v_sig.registration_expires_on, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  select max(c.checked_on) filter (where c.checked_on <= v_day), min(c.checked_on) filter (where c.checked_on > v_day)
    into v_chk, v_after
    from hsf_signatory_register_checks(v_sig.id) c;
  if v_chk is null and v_after is null then
    return format('the check of the %s public register for %s is not recorded (date and saved proof)',
                  v_sig.registration_body, v_sig.full_name);
  end if;
  if v_chk is null then
    return format('the %s register was checked on %s, after the decision on %s',
                  v_sig.registration_body, to_char(v_after, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  -- Contract 11.4: credentials are checked at the point of use. A check exactly
  -- v_max days before the decision day still counts; one day more does not.
  if v_chk < v_day - v_max then
    return format('the %s register was last checked for %s on %s, more than %s days before the decision on %s',
                  v_sig.registration_body, v_sig.full_name, to_char(v_chk, 'DD/MM/YYYY'),
                  v_max, to_char(v_day, 'DD/MM/YYYY'));
  end if;
  if v_sig.appointment_letter_ref is null or v_sig.appointment_letter_date is null then
    return format('the appointment letter of %s is not on record', v_sig.full_name);
  end if;
  if v_sig.appointment_letter_date > v_day then
    return format('the appointment letter of %s is dated %s, after the decision on %s',
                  v_sig.full_name, to_char(v_sig.appointment_letter_date, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  if v_sig.engagement_letter_ref is null or v_sig.engagement_letter_date is null then
    return format('the engagement letter of %s is not on record', v_sig.full_name);
  end if;
  if v_sig.engagement_letter_date > v_day then
    return format('the engagement letter of %s is dated %s, after the decision on %s',
                  v_sig.full_name, to_char(v_sig.engagement_letter_date, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  return null;
end;
$$;
revoke execute on function hsf_signatory_fit(uuid) from public, anon, authenticated;
grant execute on function hsf_signatory_fit(uuid) to service_role;
comment on function hsf_signatory_fit is 'Contract 10.8 and 11.4 (SIGNOFF-CRITERIA 6.2). Null when an approved safety_content sign off can release its File revision; otherwise the first reason it cannot, in words: no credentials, a candidate category, a body or category that does not fit the File''s industry by hsf_signoff_rule, a registration expired on the decision date, no register check, none on or before the decision, or the latest one on or before it (the credential row''s own or one appended to register_rechecks) more than hsf.signoff_register_check_max_days before it, or a missing appointment or engagement letter (or one dated after the decision). The decision date is the South African calendar day of decided_at. Used by hsf_release_rules; service role only.';

-- The one statement of what a release needs. Each unmet rule is one entry
-- {code, gate, reason}: gate is the message hsf_release_gate raises (the 053
-- wording, kept), reason the plain words the staff console shows. The order is
-- the gate's order, so the gate raises the first entry.
create or replace function hsf_release_rules(p_file_id uuid, p_revision int)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_so record;
  v_reason text;
  v_first text;
  v_any boolean := false;
  v_fits boolean := false;
  v_unverified text;
  v_out jsonb := '[]'::jsonb;
begin
  -- 1. Safety content (SIGNOFF-CRITERIA 6.2): an approved sign off whose
  -- signatory fits. The latest decision's reason is reported when none fits.
  for v_so in select s.id from hsf_signoff s
               where s.file_id = p_file_id and s.revision = p_revision
                 and s.kind = 'safety_content' and s.decision = 'approved'
               order by s.decided_at desc, s.id loop
    v_any := true;
    v_reason := hsf_signatory_fit(v_so.id);
    if v_reason is null then
      v_fits := true;
      exit;
    end if;
    v_first := coalesce(v_first, v_reason);
  end loop;
  if not v_any then
    v_out := v_out || jsonb_build_object('code', 'safety_content_missing',
      'gate', 'hsf_release_gate: safety_content sign off is not approved for this File revision',
      'reason', 'No approved safety content sign off by a registered practitioner is recorded for this revision.');
  elsif not v_fits then
    v_out := v_out || jsonb_build_object('code', 'safety_content_unfit',
      'gate', 'hsf_release_gate: the safety content sign off cannot release this File: ' || v_first,
      'reason', 'The safety content sign off cannot release this File: ' || v_first || '.');
  end if;
  -- 2. The client's section 16(2) acceptance. The chief executive's
  -- acknowledgement is recorded, not a gate; the OMP is not a File signatory.
  if not exists (select 1 from hsf_signoff s
                  where s.file_id = p_file_id and s.revision = p_revision
                    and s.kind = 'client_16_2_acceptance' and s.decision = 'approved') then
    v_out := v_out || jsonb_build_object('code', 'client_acceptance_missing',
      'gate', 'hsf_release_gate: client_16_2_acceptance sign off is not approved for this File revision',
      'reason', 'The client''s section 16(2) acceptance is not approved for this revision.');
  end if;
  -- 3. Contract 9.3, unchanged from 047: hsf_element_citable (migration 050) is
  -- the single definition of an instrument a File element may cite: verified,
  -- not held, not superseded, scope safety or both, and a provision pinned past
  -- 'awaiting verification'. Every instrument an item's element names must pass it.
  select string_agg(distinct li.short_name, ', ' order by li.short_name) into v_unverified
    from hsf_file_item fi
    join hsf_element_instrument ei on ei.element_id = fi.element_id
    join msp_legal_instrument li on li.id = ei.instrument_id
   where fi.file_id = p_file_id
     and not (hsf_element_citable(fi.element_id) ? li.short_name);
  if v_unverified is not null then
    v_out := v_out || jsonb_build_object('code', 'instruments_not_citable',
      'gate', 'hsf_release_gate: the File cites instruments that are not verified for a File: ' || v_unverified,
      'reason', 'The File cites instruments not yet verified for a File: ' || v_unverified || '.');
  end if;
  return v_out;
end;
$$;
comment on function hsf_release_rules is 'SPEC B4.5 and B11.2 as amended by contract 10.8, 11.4 and 11.5, and contract 9.3. Every rule a release of a File revision must meet, as a list of the unmet ones in the gate''s order, each {code, gate, reason}: (1) an approved safety_content sign off that hsf_signatory_fit accepts (safety_content_missing or safety_content_unfit); (2) an approved client_16_2_acceptance (client_acceptance_missing); (3) every instrument the File''s elements name citable for a File by hsf_element_citable (instruments_not_citable). An empty list means the revision may be released. The one source of hsf_release_gate and hsf_release_readiness; writes nothing. Service role only.';

create or replace function hsf_release_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rules jsonb := hsf_release_rules(new.file_id, new.revision);
begin
  if jsonb_array_length(v_rules) > 0 then
    raise exception '%', v_rules -> 0 ->> 'gate';
  end if;
  return new;
end;
$$;
revoke execute on function hsf_release_gate() from public, anon, authenticated;
comment on function hsf_release_gate is 'SPEC B4.5 and B11.2 as amended by contract 10.8, 11.4 and 11.5, and contract 9.3. Refuses a release insert with the first unmet rule of hsf_release_rules: (1) an approved safety_content sign off that hsf_signatory_fit accepts: body and category fit the File''s industry by hsf_signoff_rule, registration not expired on the decision date, register check recorded, not after the decision and not more than hsf.signoff_register_check_max_days before it, appointment and engagement letters on record; (2) an approved client_16_2_acceptance; and (3) every instrument the File''s elements name citable for a File by hsf_element_citable. The OMP is not a File signatory and the chief executive acknowledgement is not a gate. Enforced in the database; the parameter hsf.release_required is display only and does not relax it.';

create or replace function hsf_release_readiness(p_file_id uuid, p_revision int)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_file hsf_file;
  v_rev int;
  v_rules jsonb;
begin
  select f.* into v_file from hsf_file f where f.id = p_file_id;
  if v_file.id is null then
    raise exception 'That File was not found.' using errcode = 'P0002';
  end if;
  v_rev := coalesce(p_revision, v_file.revision);
  if v_rev < 1 then
    raise exception 'The revision must be a whole number from 1.';
  end if;
  v_rules := hsf_release_rules(v_file.id, v_rev);
  return jsonb_build_object(
    'file_id', v_file.id, 'revision', v_rev,
    'ready', jsonb_array_length(v_rules) = 0,
    'missing', coalesce((select jsonb_agg(x ->> 'reason' order by o)
                           from jsonb_array_elements(v_rules) with ordinality t(x, o)), '[]'::jsonb),
    'released', exists (select 1 from hsf_release r where r.file_id = v_file.id and r.revision = v_rev));
end;
$$;
comment on function hsf_release_readiness is 'Contract 11.5. Whether a File revision (the File''s current revision when p_revision is null) may be released: {file_id, revision, ready, missing: [plain reasons], released}. Runs exactly the rules of hsf_release_gate (hsf_release_rules) and inserts nothing. A missing File raises P0002. Service role only.';

-- 8. Signatory expiry alerts (contract 11.4) --------------------------------------------------------

-- Signatories whose registration has expired or expires within 60 days of the
-- South African calendar day, with the Files they signed (approved safety
-- content) that are not yet released. A registration already renewed (a later
-- row with the same body and number) is listed only while an unreleased File
-- still rests on it.
create or replace view hsf_signatory_expiry_alerts as
select s.id as signatory_id,
       s.full_name,
       s.registration_body,
       s.category,
       s.registration_number,
       s.registration_expires_on,
       (s.registration_expires_on - t.today) as days_to_expiry,
       (s.registration_expires_on < t.today) as expired,
       exists (select 1 from hsf_signatory n
                where n.registration_body = s.registration_body and n.registration_number = s.registration_number
                  and n.registration_expires_on > s.registration_expires_on) as renewed,
       coalesce(uf.files, '[]'::jsonb) as unreleased_files
  from hsf_signatory s
  cross join (select (now() at time zone 'Africa/Johannesburg')::date as today) t
  left join lateral (
    select jsonb_agg(jsonb_build_object('file_id', f.id, 'reference', f.reference, 'revision', so.revision,
                                        'company_name', a.company_name, 'decided_at', so.decided_at)
                     order by so.decided_at, f.reference) as files
      from hsf_signoff so
      join hsf_file f on f.id = so.file_id
      join msp_client_account a on a.id = f.client_account_id
     where so.signatory_id = s.id and so.kind = 'safety_content' and so.decision = 'approved'
       and not exists (select 1 from hsf_release r where r.file_id = so.file_id and r.revision = so.revision)) uf on true
 where s.registration_expires_on <= t.today + 60
   and (uf.files is not null
        or not exists (select 1 from hsf_signatory n
                        where n.registration_body = s.registration_body and n.registration_number = s.registration_number
                          and n.registration_expires_on > s.registration_expires_on))
   and hsf_is_staff();
comment on view hsf_signatory_expiry_alerts is 'Contract 11.4. Safety content signatories whose registration has expired or expires within 60 days (South African calendar day), with days_to_expiry, whether a renewal is recorded, and the Files they signed that are not yet released (unreleased_files). A renewed registration is listed only while an unreleased File rests on it. Staff only (forge_admin, forge_omp, forge_safety_reviewer); nobody else sees a row.';
revoke all on hsf_signatory_expiry_alerts from public, anon, authenticated;
grant select on hsf_signatory_expiry_alerts to authenticated;

create or replace function hsf_signatory_expiry_alerts_list()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'signatory_id', s.id, 'full_name', s.full_name, 'registration_body', s.registration_body,
           'category', s.category, 'registration_number', s.registration_number,
           'registration_expires_on', s.registration_expires_on,
           'days_to_expiry', s.registration_expires_on - t.today,
           'expired', s.registration_expires_on < t.today,
           'renewed', exists (select 1 from hsf_signatory n
                               where n.registration_body = s.registration_body and n.registration_number = s.registration_number
                                 and n.registration_expires_on > s.registration_expires_on),
           'unreleased_files', coalesce(uf.files, '[]'::jsonb))
         order by s.registration_expires_on, s.full_name, s.id), '[]'::jsonb)
    from hsf_signatory s
    cross join (select (now() at time zone 'Africa/Johannesburg')::date as today) t
    left join lateral (
      select jsonb_agg(jsonb_build_object('file_id', f.id, 'reference', f.reference, 'revision', so.revision,
                                          'company_name', a.company_name, 'decided_at', so.decided_at)
                       order by so.decided_at, f.reference) as files
        from hsf_signoff so
        join hsf_file f on f.id = so.file_id
        join msp_client_account a on a.id = f.client_account_id
       where so.signatory_id = s.id and so.kind = 'safety_content' and so.decision = 'approved'
         and not exists (select 1 from hsf_release r where r.file_id = so.file_id and r.revision = so.revision)) uf on true
   where s.registration_expires_on <= t.today + 60
     and (uf.files is not null
          or not exists (select 1 from hsf_signatory n
                          where n.registration_body = s.registration_body and n.registration_number = s.registration_number
                            and n.registration_expires_on > s.registration_expires_on));
$$;
comment on function hsf_signatory_expiry_alerts_list is 'Contract 11.4. The rows of hsf_signatory_expiry_alerts for the service role (scheduled alerts and the staff console), soonest expiry first.';

-- 9. Sign off rows record who entered them (contract 11.5) --------------------------------------------

alter table hsf_signoff
  add column if not exists document_ref text check (document_ref is null or length(btrim(document_ref)) between 1 and 200);
comment on column hsf_signoff.document_ref is 'Contract 11.5. Reference of the signed document the decision rests on: required through the staff console for the client section 16(2) acceptance and the chief executive acknowledgement, optional for the safety content sign off.';

-- Who entered a decision is staff attribution, which the client must not read:
-- the client reads its File's hsf_signoff rows (047 policy hsf_signoff_read),
-- so the staff email is kept only as the actor of the hsf_signoff_recorded
-- audit row (msp_audit, which only forge_admin and forge_omp read), where the
-- console reads it.

-- 10. Staff console: helpers (never callable from outside) --------------------------------------------

-- The staff check every console function runs in its body, whatever the API
-- checked before. Returns the email recorded as the actor.
create or replace function hsf_staff_email(p_auth_user uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_auth_user is null or not coalesce(hsf_user_is_staff(p_auth_user), false) then
    raise exception 'This needs a Care Net staff role.' using errcode = '42501';
  end if;
  return coalesce(nullif(btrim(hsf_user_email(p_auth_user)), ''), 'staff ' || p_auth_user::text);
end;
$$;
comment on function hsf_staff_email is 'Contract 11.5. Raises 42501 unless the auth user carries a forge staff role (hsf_user_is_staff); otherwise returns the staff member''s email, recorded as verified_by, revoked_by, created_by, the recorded_by of an appended register check, or the audit actor. Internal: called only by the console functions.';

create or replace function hsf_staff_text(p_value text, p_label text, p_max int, p_required boolean)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v text := nullif(btrim(coalesce(p_value, '')), '');
begin
  if v is null then
    if p_required then
      raise exception '% is required.', p_label;
    end if;
    return null;
  end if;
  if length(v) > p_max or v ~ '[[:cntrl:]]' then
    raise exception '% must be 1 to % printable characters.', p_label, p_max;
  end if;
  return v;
end;
$$;
comment on function hsf_staff_text is 'Contract 11.5. One text field of a console form: trimmed, null when blank (refused with ''<label> is required.'' when required), and refused when longer than p_max or carrying control characters. Internal.';

create or replace function hsf_staff_date(p_value text, p_label text)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare
  v text := nullif(btrim(coalesce(p_value, '')), '');
begin
  if v is null then
    return null;
  end if;
  if v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception '% must be a date written as YYYY-MM-DD.', p_label;
  end if;
  begin
    return v::date;
  exception when others then
    raise exception '% is not a real date.', p_label;
  end;
end;
$$;
comment on function hsf_staff_date is 'Contract 11.5. One date field of a console form, written YYYY-MM-DD; null when blank; a plain refusal otherwise. Internal.';

-- The bodies of the 052 verify, revoke and scan reset, with the actor passed
-- in: the 052 functions pass the JWT email (or service_role), the console
-- functions the staff email. Nobody calls these directly.
create or replace function hsf_verify_client_by(p_actor text, p_client_account_id uuid, p_method text, p_evidence_ref text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_ref text := btrim(coalesce(p_evidence_ref, ''));
  v_row hsf_client_verification;
begin
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
  -- A verification after a revocation clears the revocation fields; the audit
  -- trail keeps both events. Uploads blocked by the revocation stay blocked.
  insert into hsf_client_verification (client_account_id, status, method, evidence_ref, requested_at, verified_by, verified_at)
  values (v_acc.id, 'verified', p_method, v_ref, now(), p_actor, now())
  on conflict (client_account_id) do update
     set status = 'verified', method = excluded.method, evidence_ref = excluded.evidence_ref,
         verified_by = excluded.verified_by, verified_at = excluded.verified_at,
         revoked_by = null, revoked_at = null, revoke_reason = null
  returning * into v_row;
  insert into msp_audit (actor, event_type, event_detail)
  values (p_actor, 'hsf_client_verified',
          jsonb_build_object('client_account_id', v_acc.id, 'method', p_method, 'evidence_ref', v_ref));
  return jsonb_build_object('client_account_id', v_row.client_account_id, 'status', v_row.status,
                            'method', v_row.method, 'verified_by', v_row.verified_by, 'verified_at', v_row.verified_at);
end;
$$;
comment on function hsf_verify_client_by is 'Contract 10.2 and 11.5. The body of hsf_verify_client with the actor passed in (verified_by and the audit actor). Internal: called by hsf_verify_client and hsf_staff_verify_client after their permission checks.';

create or replace function hsf_revoke_client_verification_by(p_actor text, p_client_account_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_row hsf_client_verification;
  v_blocked int := 0;
begin
  if v_reason = '' or length(v_reason) > 500 then
    raise exception 'Give the reason for the revocation, in 1 to 500 characters.';
  end if;
  select v.* into v_row from hsf_client_verification v where v.client_account_id = p_client_account_id for update;
  if v_row.client_account_id is null or v_row.status <> 'verified' then
    raise exception 'That company account is not verified.';
  end if;
  update hsf_client_verification
     set status = 'revoked', revoked_by = p_actor, revoked_at = now(), revoke_reason = v_reason
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
  values (p_actor, 'hsf_client_verification_revoked',
          jsonb_build_object('client_account_id', v_row.client_account_id, 'reason', v_reason,
                             'blocked_uploads', v_blocked));
  return jsonb_build_object('client_account_id', v_row.client_account_id, 'status', v_row.status,
                            'revoked_at', v_row.revoked_at, 'blocked_uploads', v_blocked);
end;
$$;
comment on function hsf_revoke_client_verification_by is 'Contract 10.2 and 11.5. The body of hsf_revoke_client_verification with the actor passed in (revoked_by and the audit actor). Internal: called by hsf_revoke_client_verification and hsf_staff_revoke_client after their permission checks.';

create or replace function hsf_scan_reset_by(p_actor text, p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_up hsf_upload;
begin
  select u.* into v_up from hsf_upload u where u.id = p_upload_id for update;
  if v_up.id is null then
    raise exception 'That upload was not found.' using errcode = 'P0002';
  end if;
  if v_up.status <> 'uploaded' or v_up.scan_status not in ('pending','error') or v_up.storage_path is null then
    raise exception 'Only an uploaded document still waiting for its security scan can be scanned again (status %, scan %).',
      v_up.status, v_up.scan_status;
  end if;
  update hsf_upload set scan_attempts = 0 where id = v_up.id;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (p_actor, 'hsf_upload_scan_reset',
          jsonb_build_object('upload_id', v_up.id, 'attempts_before', v_up.scan_attempts,
                             'scan_status', v_up.scan_status),
          v_up.file_id);
  return jsonb_build_object('upload_id', v_up.id, 'scan_status', v_up.scan_status, 'scan_attempts', 0);
end;
$$;
comment on function hsf_scan_reset_by is 'Contract 10.4 and 11.5. The body of hsf_scan_reset with the actor passed in (the audit actor). Internal: called by hsf_scan_reset and hsf_staff_scan_reset after their permission checks.';

-- The 052 functions, now thin: the same permission check and actor, then the shared body.
create or replace function hsf_verify_client(p_client_account_id uuid, p_method text, p_evidence_ref text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (coalesce(auth.role() = 'service_role', false) or coalesce(hsf_is_staff(), false)) then
    raise exception 'Verifying a client needs a Care Net staff role.' using errcode = '42501';
  end if;
  return hsf_verify_client_by(coalesce(nullif(btrim(auth.jwt() ->> 'email'), ''),
                                       case when auth.role() = 'service_role' then 'service_role' end, 'staff'),
                              p_client_account_id, p_method, p_evidence_ref);
end;
$$;
comment on function hsf_verify_client is 'Contract 10.2. Marks a company account verified as a Care Net Consultants client, with the method and a required evidence reference. The service role or a signed in forge staff member (hsf_is_staff, which includes forge_admin), checked in the body; verified_by is the staff email from the JWT or service_role. A declined account is refused. Uploads blocked by an earlier revocation stay blocked. Audited as hsf_client_verified. The body is hsf_verify_client_by, shared with the staff console (contract 11.5).';

create or replace function hsf_revoke_client_verification(p_client_account_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (coalesce(auth.role() = 'service_role', false) or coalesce(hsf_is_staff(), false)) then
    raise exception 'Revoking a client verification needs a Care Net staff role.' using errcode = '42501';
  end if;
  return hsf_revoke_client_verification_by(coalesce(nullif(btrim(auth.jwt() ->> 'email'), ''),
                                                    case when auth.role() = 'service_role' then 'service_role' end, 'staff'),
                                           p_client_account_id, p_reason);
end;
$$;
comment on function hsf_revoke_client_verification is 'Contract 10.2. Revokes a verification with a reason. The account''s untransferred uploads are not deleted: they get transfer_blocked_reason = ''client verification revoked'' and are never scanned or claimed for transfer. The service role or forge staff, checked in the body. Audited as hsf_client_verification_revoked. The body is hsf_revoke_client_verification_by, shared with the staff console (contract 11.5).';

create or replace function hsf_scan_reset(p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (coalesce(auth.role() = 'service_role', false) or coalesce(hsf_is_staff(), false)) then
    raise exception 'Resetting a security scan needs a Care Net staff role.' using errcode = '42501';
  end if;
  return hsf_scan_reset_by(coalesce(nullif(btrim(auth.jwt() ->> 'email'), ''),
                                    case when auth.role() = 'service_role' then 'service_role' end, 'staff'),
                           p_upload_id);
end;
$$;
comment on function hsf_scan_reset is 'Contract 10.4. Gives an uploaded document whose scan is pending or error its five scan attempts back, for example after an inspection fault was fixed; hsf_staging_alerts lists the documents that used all five. The service role or forge staff, checked in the body. Audited as hsf_upload_scan_reset. The body is hsf_scan_reset_by, shared with the staff console (contract 11.5).';

-- 11. Staff console: clients to verify (contract 11.5) --------------------------------------------------

create or replace function hsf_staff_verification_list(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform hsf_staff_email(p_auth_user);
  return (select coalesce(jsonb_agg(jsonb_build_object(
             'client_account_id', v.client_account_id, 'company_name', a.company_name,
             'contact_email', a.contact_email, 'account_kind', a.account_kind, 'status', v.status,
             'requested_at', v.requested_at, 'method', v.method, 'evidence_ref', v.evidence_ref,
             'verified_by', v.verified_by, 'verified_at', v.verified_at,
             'revoked_by', v.revoked_by, 'revoked_at', v.revoked_at, 'revoke_reason', v.revoke_reason)
           -- Requests waiting first, then verified, then revoked; newest request first.
           order by case v.status when 'requested' then 1 when 'verified' then 2 else 3 end,
                    v.requested_at desc, v.client_account_id), '[]'::jsonb)
            from hsf_client_verification v
            join msp_client_account a on a.id = v.client_account_id);
end;
$$;
comment on function hsf_staff_verification_list is 'Contract 11.5. The requested, verified and revoked company accounts with company name, contact email, requested_at, method, evidence reference and who verified or revoked them, requests waiting first. Staff only (checked in the body); service role only.';

create or replace function hsf_staff_verify_client(p_auth_user uuid, p_client_account_id uuid, p_method text, p_evidence_ref text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return hsf_verify_client_by(hsf_staff_email(p_auth_user), p_client_account_id, p_method, p_evidence_ref);
end;
$$;
comment on function hsf_staff_verify_client is 'Contract 11.5. hsf_verify_client for the staff console: staff only (checked in the body), verified_by and the audit actor are the staff member''s email. Service role only.';

create or replace function hsf_staff_revoke_client(p_auth_user uuid, p_client_account_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return hsf_revoke_client_verification_by(hsf_staff_email(p_auth_user), p_client_account_id, p_reason);
end;
$$;
comment on function hsf_staff_revoke_client is 'Contract 11.5. hsf_revoke_client_verification for the staff console: staff only (checked in the body), revoked_by and the audit actor are the staff member''s email. Nothing is deleted; the account''s untransferred uploads are blocked. Service role only.';

-- 12. Staff console: scans and staging (contract 11.5) -------------------------------------------------

create or replace function hsf_staff_scan_list(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform hsf_staff_email(p_auth_user);
  -- No file names, as in the staging alerts: the company, the File and the
  -- department identify the document for the staff member.
  return jsonb_build_object(
    'scans', (select coalesce(jsonb_agg(jsonb_build_object(
                'upload_id', u.id, 'client_account_id', u.client_account_id, 'company_name', a.company_name,
                'file_id', u.file_id, 'department_code', u.department_code, 'section_code', u.section_code,
                'mime_type', u.mime_type, 'size_bytes', u.size_bytes, 'uploaded_at', u.uploaded_at,
                'scan_status', u.scan_status, 'scan_attempts', u.scan_attempts, 'scanned_at', u.scanned_at,
                'scan_engine', u.scan_engine, 'scan_findings', u.scan_findings,
                'scan_exhausted', u.scan_attempts >= 5,
                'transfer_blocked_reason', u.transfer_blocked_reason)
              order by u.uploaded_at nulls last, u.created_at, u.id), '[]'::jsonb)
                from hsf_upload u
                join msp_client_account a on a.id = u.client_account_id
               where u.status = 'uploaded' and u.scan_status in ('pending','error') and u.storage_path is not null),
    'staging_alerts', hsf_staging_alerts_list());
end;
$$;
comment on function hsf_staff_scan_list is 'Contract 11.5. {scans, staging_alerts}: the uploaded documents whose security scan is pending or ended in an error, with attempts, the last findings and whether all five attempts are used (scan_exhausted), and the staging alerts with expires_on (hsf_staging_alerts_list). No file names. Staff only (checked in the body); service role only.';

create or replace function hsf_staff_scan_reset(p_auth_user uuid, p_upload_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return hsf_scan_reset_by(hsf_staff_email(p_auth_user), p_upload_id);
end;
$$;
comment on function hsf_staff_scan_reset is 'Contract 11.5. hsf_scan_reset for the staff console: staff only (checked in the body), audited with the staff member''s email. Service role only.';

-- 13. Staff console: signatories (contract 11.5) --------------------------------------------------------

create or replace function hsf_staff_signatory_list(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Africa/Johannesburg')::date;
  v_max int := hsf_signoff_register_check_max_days();
begin
  perform hsf_staff_email(p_auth_user);
  return (select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object(
             -- Relied on by a released revision: only the recruitment portal
             -- references may still be added (hsf_signatory_guard), and a
             -- fresh register check is recorded as a dated check of its own.
             'frozen', exists (select 1 from hsf_signoff so
                                 join hsf_release r on r.file_id = so.file_id and r.revision = so.revision
                                where so.signatory_id = s.id and so.kind = 'safety_content' and so.decision = 'approved'),
             'expired', s.registration_expires_on < v_today,
             'days_to_expiry', s.registration_expires_on - v_today,
             -- The latest register check on record, from the row or appended since.
             'register_checked_on', lc.checked_on,
             'register_proof_ref', lc.proof_ref,
             'register_checks', (select count(*) from hsf_signatory_register_checks(s.id)),
             'register_check_age_days', v_today - lc.checked_on,
             'register_check_current', lc.checked_on is not null and lc.checked_on >= v_today - v_max,
             'register_check_max_days', v_max,
             'letters_on_record', s.appointment_letter_ref is not null and s.engagement_letter_ref is not null,
             'signoffs', (select count(*) from hsf_signoff so where so.signatory_id = s.id))
           order by s.full_name, s.registration_expires_on desc, s.id), '[]'::jsonb)
            from hsf_signatory s
            left join lateral (select c.checked_on, c.proof_ref from hsf_signatory_register_checks(s.id) c
                                order by c.checked_on desc limit 1) lc on true);
end;
$$;
comment on function hsf_staff_signatory_list is 'Contract 11.4 and 11.5. Every signatory credential record with every 053 field, plus frozen (relied on by a released revision), expired and days_to_expiry, the latest register check on record (register_checked_on and register_proof_ref, from the row or register_rechecks, with the number of checks), its age and whether it is within hsf.signoff_register_check_max_days today, that number of days (register_check_max_days, so the console states the limit the release gate applies), whether both letters are on record, and the number of sign offs. Staff only (checked in the body); service role only.';

create or replace function hsf_staff_signatory_save(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_by text := hsf_staff_email(p_auth_user);
  v_today date := (now() at time zone 'Africa/Johannesburg')::date;
  v_id_txt text;
  v_old hsf_signatory;
  v_row hsf_signatory;
  v_name text;
  v_body text;
  v_cat text;
  v_num text;
  v_exp date;
  v_chk date;
  v_proof text;
  v_appt_ref text;
  v_appt_date date;
  v_appt_portal text;
  v_eng_ref text;
  v_eng_date date;
  v_eng_portal text;
  v_changed jsonb;
  v_frozen boolean := false;
  v_last date;
  v_last_proof text;
  v_recheck boolean := false;
  v_rechecks jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'The signatory details are missing.';
  end if;
  v_name := hsf_staff_text(p ->> 'full_name', 'The full name', 200, true);
  v_body := hsf_staff_text(p ->> 'registration_body', 'The registering body', 20, true);
  if v_body not in ('SACPCMP','SAIOSH') then
    raise exception 'The registering body must be SACPCMP or SAIOSH.';
  end if;
  v_cat := hsf_staff_text(p ->> 'category', 'The category', 40, true);
  if v_body = 'SACPCMP' and v_cat not in ('Pr CHSA','CHSM','CHSO','Can CHSA','Can CHSM','Can CHSO') then
    raise exception 'A SACPCMP category must be Pr CHSA, CHSM, CHSO, Can CHSA, Can CHSM or Can CHSO.';
  end if;
  if v_body = 'SAIOSH' and v_cat not in ('TechSAIOSH','GradSAIOSH','CMSAIOSH') then
    raise exception 'A SAIOSH designation must be TechSAIOSH, GradSAIOSH or CMSAIOSH.';
  end if;
  v_num := hsf_staff_text(p ->> 'registration_number', 'The registration number', 100, true);
  v_exp := hsf_staff_date(p ->> 'registration_expires_on', 'The registration expiry date');
  if v_exp is null then
    raise exception 'The registration expiry date is required.';
  end if;
  v_chk := hsf_staff_date(p ->> 'register_checked_on', 'The register check date');
  v_proof := hsf_staff_text(p ->> 'register_proof_ref', 'The reference of the saved register proof', 200, false);
  if (v_chk is null) <> (v_proof is null) then
    raise exception 'Record the register check date and the reference of its saved proof together.';
  end if;
  if v_chk > v_today then
    raise exception 'The register check date cannot be in the future.';
  end if;
  v_appt_ref := hsf_staff_text(p ->> 'appointment_letter_ref', 'The appointment letter reference', 200, false);
  v_appt_date := hsf_staff_date(p ->> 'appointment_letter_date', 'The appointment letter date');
  if (v_appt_ref is null) <> (v_appt_date is null) then
    raise exception 'Record the appointment letter reference and its date together.';
  end if;
  v_appt_portal := hsf_staff_text(p ->> 'appointment_letter_recruitment_portal_ref', 'The appointment letter recruitment portal reference', 200, false);
  v_eng_ref := hsf_staff_text(p ->> 'engagement_letter_ref', 'The engagement letter reference', 200, false);
  v_eng_date := hsf_staff_date(p ->> 'engagement_letter_date', 'The engagement letter date');
  if (v_eng_ref is null) <> (v_eng_date is null) then
    raise exception 'Record the engagement letter reference and its date together.';
  end if;
  v_eng_portal := hsf_staff_text(p ->> 'engagement_letter_recruitment_portal_ref', 'The engagement letter recruitment portal reference', 200, false);

  v_id_txt := nullif(btrim(coalesce(p ->> 'id', '')), '');
  begin
    if v_id_txt is null then
      insert into hsf_signatory (full_name, registration_body, category, registration_number, registration_expires_on,
                                 register_checked_on, register_proof_ref,
                                 appointment_letter_ref, appointment_letter_date, appointment_letter_recruitment_portal_ref,
                                 engagement_letter_ref, engagement_letter_date, engagement_letter_recruitment_portal_ref,
                                 created_by)
      values (v_name, v_body, v_cat, v_num, v_exp, v_chk, v_proof,
              v_appt_ref, v_appt_date, v_appt_portal, v_eng_ref, v_eng_date, v_eng_portal, v_by)
      returning * into v_row;
    else
      if v_id_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception 'That signatory was not found.' using errcode = 'P0002';
      end if;
      select s.* into v_old from hsf_signatory s where s.id = v_id_txt::uuid for update;
      if v_old.id is null then
        raise exception 'That signatory was not found.' using errcode = 'P0002';
      end if;
      -- Credentials a release relied on keep the register check it relied on
      -- (hsf_signatory_guard). The console shows their latest check; a later
      -- date with its proof is appended as a register check of its own, and
      -- the row itself is saved with the check it already holds.
      v_frozen := exists (select 1 from hsf_signoff so
                            join hsf_release r on r.file_id = so.file_id and r.revision = so.revision
                           where so.signatory_id = v_old.id and so.kind = 'safety_content' and so.decision = 'approved');
      if v_frozen then
        select c.checked_on, c.proof_ref into v_last, v_last_proof
          from hsf_signatory_register_checks(v_old.id) c order by c.checked_on desc limit 1;
        if v_chk is distinct from v_last or v_proof is distinct from v_last_proof then
          if v_chk is null or (v_last is not null and v_chk <= v_last) then
            raise exception 'A new register check on credentials that support a released File must be dated after the last one on record (%), with the reference of its saved proof.',
              coalesce(to_char(v_last, 'DD/MM/YYYY'), 'none');
          end if;
          v_recheck := true;
        end if;
        v_rechecks := v_old.register_rechecks || case when v_recheck then jsonb_build_array(jsonb_build_object(
                        'checked_on', v_chk, 'proof_ref', v_proof, 'recorded_by', v_by, 'recorded_at', now())) else '[]'::jsonb end;
        v_chk := v_old.register_checked_on;
        v_proof := v_old.register_proof_ref;
      end if;
      update hsf_signatory
         set full_name = v_name, registration_body = v_body, category = v_cat, registration_number = v_num,
             registration_expires_on = v_exp, register_checked_on = v_chk, register_proof_ref = v_proof,
             appointment_letter_ref = v_appt_ref, appointment_letter_date = v_appt_date,
             appointment_letter_recruitment_portal_ref = v_appt_portal,
             engagement_letter_ref = v_eng_ref, engagement_letter_date = v_eng_date,
             engagement_letter_recruitment_portal_ref = v_eng_portal,
             register_rechecks = coalesce(v_rechecks, register_rechecks)
       where id = v_old.id
      returning * into v_row;
    end if;
  exception
    when unique_violation then
      raise exception 'A signatory with this registering body, registration number and expiry date is already recorded.';
    when raise_exception then
      -- The 053 freeze (hsf_signatory_guard), in the console's plain words.
      if sqlerrm like 'hsf_signatory: %frozen%' then
        raise exception 'These credentials support a released File and cannot be changed. Record a renewal or a correction as a new signatory.';
      elsif sqlerrm like 'hsf_signatory: %set once%' then
        raise exception 'A recruitment portal reference on credentials that support a released File is set once and never changed.';
      end if;
      raise;
  end;

  -- The fields a correction changed, by name (the values are in the row).
  select coalesce(jsonb_agg(n.key order by n.key), '[]'::jsonb) into v_changed
    from jsonb_each(to_jsonb(v_row)) n
   where v_old.id is not null and n.key not in ('id','created_by','created_at')
     and n.value is distinct from to_jsonb(v_old) -> n.key;
  insert into msp_audit (actor, event_type, event_detail)
  values (v_by, 'hsf_signatory_saved',
          jsonb_build_object('signatory_id', v_row.id, 'action', case when v_old.id is null then 'created' else 'corrected' end,
                             'registration_body', v_row.registration_body, 'category', v_row.category,
                             'registration_number', v_row.registration_number, 'changed', v_changed,
                             'register_checked_on', case when v_recheck then p ->> 'register_checked_on' end));
  -- The reply shows the latest register check on record, as the list does.
  select c.checked_on, c.proof_ref into v_last, v_last_proof
    from hsf_signatory_register_checks(v_row.id) c order by c.checked_on desc limit 1;
  return to_jsonb(v_row) || jsonb_build_object(
    'action', case when v_old.id is null then 'created' when v_recheck and v_changed = '["register_rechecks"]'::jsonb then 'register_checked' else 'corrected' end,
    'register_checked_on', v_last, 'register_proof_ref', v_last_proof);
end;
$$;
comment on function hsf_staff_signatory_save is 'Contract 11.5. Creates a hsf_signatory row (p without id; created_by is the staff email) or corrects one (p.id), with every 053 field: full name, registering body and category, registration number and expiry, register check date with the saved proof reference, and the appointment and engagement letters (reference, date and recruitment portal reference each). Plain refusals for a missing or malformed field, a category of the other body, a pair given half, a register check in the future, a duplicate registration period, and the 053 freeze of credentials that support a released File. On frozen credentials a register check dated after the last one on record, with its proof, is appended to register_rechecks with the staff email (action register_checked) and the row keeps the check the release relied on; an earlier or equal date with other proof is refused. Audited as hsf_signatory_saved with the names of the changed fields. Staff only (checked in the body); service role only.';

-- 14. Staff console: sign offs and readiness (contract 11.5) ---------------------------------------------

create or replace function hsf_staff_signoff_record(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_by text := hsf_staff_email(p_auth_user);
  v_file hsf_file;
  v_rev int;
  v_kind text;
  v_decision text;
  v_at timestamptz;
  v_at_txt text;
  v_sig hsf_signatory;
  v_sig_txt text;
  v_scope text;
  v_name text;
  v_doc text;
  v_id uuid;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'The sign off details are missing.';
  end if;
  if coalesce(p ->> 'file_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'That File was not found.' using errcode = 'P0002';
  end if;
  select f.* into v_file from hsf_file f where f.id = (p ->> 'file_id')::uuid;
  if v_file.id is null then
    raise exception 'That File was not found.' using errcode = 'P0002';
  end if;
  if nullif(btrim(coalesce(p ->> 'revision', '')), '') is null then
    v_rev := v_file.revision;
  elsif btrim(p ->> 'revision') ~ '^[0-9]{1,6}$' and (btrim(p ->> 'revision'))::int between 1 and v_file.revision then
    v_rev := (btrim(p ->> 'revision'))::int;
  else
    raise exception 'The revision must be a whole number from 1 to %.', v_file.revision;
  end if;
  if exists (select 1 from hsf_release r where r.file_id = v_file.id and r.revision = v_rev) then
    raise exception 'Revision % of this File is already released. A sign off cannot be added to it.', v_rev;
  end if;

  v_kind := btrim(coalesce(p ->> 'kind', ''));
  if v_kind = 'omp_medical' then
    raise exception 'The Occupational Medical Practitioner does not sign a File. File the signed medical surveillance plan in Section E as evidence instead.';
  end if;
  if v_kind not in ('safety_content','client_16_2_acceptance','ceo_16_1_acknowledgement') then
    raise exception 'The sign off must be safety_content, client_16_2_acceptance or ceo_16_1_acknowledgement.';
  end if;
  v_decision := btrim(coalesce(p ->> 'decision', ''));
  if v_decision not in ('approved','amended','rejected') then
    raise exception 'The decision must be approved, amended or rejected.';
  end if;
  v_at_txt := nullif(btrim(coalesce(p ->> 'decided_at', '')), '');
  if v_at_txt is null then
    raise exception 'The date of the decision is required.';
  end if;
  begin
    v_at := v_at_txt::timestamptz;
  exception when others then
    raise exception 'The date of the decision is not a real date and time.';
  end;
  if v_at > now() + interval '5 minutes' then
    raise exception 'The date of the decision cannot be in the future.';
  end if;

  if v_kind = 'safety_content' then
    v_sig_txt := nullif(btrim(coalesce(p ->> 'signatory_id', '')), '');
    if v_sig_txt is null then
      raise exception 'Choose the signatory whose credentials this sign off rests on.';
    end if;
    if v_sig_txt ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select s.* into v_sig from hsf_signatory s where s.id = v_sig_txt::uuid;
    end if;
    if v_sig.id is null then
      raise exception 'That signatory was not found.' using errcode = 'P0002';
    end if;
    v_scope := hsf_staff_text(p ->> 'scope', 'The scope of the sign off', 500, true);
    v_doc := hsf_staff_text(p ->> 'document_ref', 'The reference of the signed document', 200, false);
  else
    v_name := hsf_staff_text(p ->> 'signatory_name', 'The name of the person who signed', 200, true);
    v_doc := hsf_staff_text(p ->> 'document_ref',
                            case when v_kind = 'client_16_2_acceptance' then 'The reference of the signed acceptance document'
                                 else 'The reference of the signed acknowledgement document' end, 200, true);
  end if;

  -- The safety content signatory's name, body and number are copied from the
  -- credential record by hsf_signoff_guard (053).
  insert into hsf_signoff (file_id, revision, kind, decision, signatory_id, signatory_name, scope, decided_at, document_ref)
  values (v_file.id, v_rev, v_kind, v_decision, v_sig.id, v_name, v_scope, v_at, v_doc)
  returning id into v_id;
  insert into msp_audit (actor, event_type, event_detail, hsf_file_id)
  values (v_by, 'hsf_signoff_recorded',
          jsonb_build_object('signoff_id', v_id, 'revision', v_rev, 'kind', v_kind, 'decision', v_decision,
                             'decided_at', v_at, 'signatory_id', v_sig.id, 'document_ref', v_doc),
          v_file.id);
  return jsonb_build_object('signoff_id', v_id, 'file_id', v_file.id, 'revision', v_rev, 'kind', v_kind,
                            'decision', v_decision, 'decided_at', v_at, 'recorded_by', v_by,
                            'signatory_fit', case when v_kind = 'safety_content' and v_decision = 'approved'
                                                  then hsf_signatory_fit(v_id) end,
                            'readiness', hsf_release_readiness(v_file.id, v_rev));
end;
$$;
comment on function hsf_staff_signoff_record is 'Contract 11.5. Records one sign off decision (approved, amended or rejected, with decided_at) on a File revision not yet released (the current revision when none is given): safety_content with signatory_id and scope (and an optional document reference), or client_16_2_acceptance and ceo_16_1_acknowledgement with the name of the person who signed and the reference of the signed document. omp_medical is refused: the OMP signs the medical surveillance plan, which is Section E evidence. The staff email is the actor of the hsf_signoff_recorded audit row (never a column of hsf_signoff, which the client reads) and is returned as recorded_by. Returns the new sign off with, for an approved safety content sign off, hsf_signatory_fit (null when it fits), and the release readiness. Audited as hsf_signoff_recorded. Staff only (checked in the body); service role only.';

create or replace function hsf_staff_file_list(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform hsf_staff_email(p_auth_user);
  return (select coalesce(jsonb_agg(jsonb_build_object(
             'file_id', f.id, 'reference', f.reference, 'company_name', a.company_name,
             'industry_code', i.code, 'industry_name', i.name, 'status', f.status, 'revision', f.revision,
             'compliance_pct', f.compliance_pct, 'created_at', f.created_at,
             -- The latest decision of each kind on the current revision.
             'signoffs', (select coalesce(jsonb_object_agg(k.kind, k.latest), '{}'::jsonb)
                            from (select distinct on (s.kind) s.kind,
                                         jsonb_build_object('signoff_id', s.id, 'decision', s.decision,
                                                            'decided_at', s.decided_at, 'signatory_name', s.signatory_name,
                                                            'recorded_by', (select a.actor from msp_audit a
                                                                             where a.hsf_file_id = s.file_id
                                                                               and a.event_type = 'hsf_signoff_recorded'
                                                                               and a.event_detail ->> 'signoff_id' = s.id::text
                                                                             limit 1)) as latest
                                    from hsf_signoff s
                                   where s.file_id = f.id and s.revision = f.revision and s.decision is not null
                                   order by s.kind, s.decided_at desc, s.id desc) k),
             'readiness', hsf_release_readiness(f.id, f.revision))
           order by f.created_at desc, f.id), '[]'::jsonb)
            from (select * from hsf_file order by created_at desc, id limit 500) f
            join msp_client_account a on a.id = f.client_account_id
            join msp_industry i on i.id = f.industry_id);
end;
$$;
comment on function hsf_staff_file_list is 'Contract 11.5. The Files, newest first (at most 500), with company, industry, status, current revision, compliance figure, the latest decision of each sign off kind on that revision (with recorded_by, the actor of its hsf_signoff_recorded audit row), and its release readiness (hsf_release_readiness). Staff only (checked in the body); service role only.';

create or replace function hsf_staff_signatory_alerts(p_auth_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform hsf_staff_email(p_auth_user);
  return hsf_signatory_expiry_alerts_list();
end;
$$;
comment on function hsf_staff_signatory_alerts is 'Contract 11.4 and 11.5. The signatory expiry alerts (hsf_signatory_expiry_alerts_list) for the staff console. Staff only (checked in the body); service role only.';

-- 15. Execute rights ------------------------------------------------------------------------------------

do $$
declare
  f text;
begin
  -- Service role only.
  foreach f in array array[
    'hsf_signoff_register_check_max_days()',
    'hsf_scan_claim(int)',
    'hsf_scan_write_back(uuid, uuid, text, bigint, jsonb)',
    'hsf_scan_record(uuid, text, text, jsonb)',
    'hsf_scan_record_clean(uuid, text, jsonb, text, jsonb, bigint)',
    'hsf_transfer_claim(int)',
    'hsf_transfer_record(uuid, text, text, text, text, text, text)',
    'hsf_transfer_cleanup_queue(int)',
    'hsf_retention_queue(int)',
    'hsf_mark_staging_deleted(uuid)',
    'hsf_mark_expired(uuid)',
    'hsf_sweep_stale_uploads(int)',
    'hsf_upload_deletable(text, text, timestamptz)',
    'hsf_deletion_request_create(uuid, uuid[], text, boolean)',
    'hsf_deletion_request_attempt(uuid, uuid)',
    'hsf_my_uploads(uuid, uuid)',
    'hsf_release_rules(uuid, int)',
    'hsf_release_readiness(uuid, int)',
    'hsf_signatory_expiry_alerts_list()',
    'hsf_staff_verification_list(uuid)',
    'hsf_staff_verify_client(uuid, uuid, text, text)',
    'hsf_staff_revoke_client(uuid, uuid, text)',
    'hsf_staff_scan_list(uuid)',
    'hsf_staff_scan_reset(uuid, uuid)',
    'hsf_staff_signatory_list(uuid)',
    'hsf_staff_signatory_save(uuid, jsonb)',
    'hsf_staff_signoff_record(uuid, jsonb)',
    'hsf_staff_file_list(uuid)',
    'hsf_staff_signatory_alerts(uuid)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  -- Internal: reached only through the security definer functions above.
  foreach f in array array[
    'hsf_staff_email(uuid)',
    'hsf_scan_claim_held(timestamptz)',
    'hsf_signatory_register_checks(uuid)',
    'hsf_staff_text(text, text, int, boolean)',
    'hsf_staff_date(text, text)',
    'hsf_verify_client_by(text, uuid, text, text)',
    'hsf_revoke_client_verification_by(text, uuid, text)',
    'hsf_scan_reset_by(text, uuid)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated, service_role', f);
  end loop;
end;
$$;
