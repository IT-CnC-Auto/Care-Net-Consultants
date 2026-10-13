-- CNC MSP FORGE | AGT-RUN-01 v1.2.0 | Audited triage correction 13/10/2026
-- The MD, 12/10/2026: a submission in triage had no way out for sales. Re-running bad
-- data only fails the checks again (CNC-MSP-2026-1008-001 was fixed by hand), and
-- CNC-MSP-2026-1012-001 waits because the hazard letters were typed "A." and "E.".
-- IT agreed an audited correction step on the back end, with the buttons on the staff
-- review page from the front end, ahead of the booking gate.
--
-- This migration:
--   1. msp_intake_correction: who corrected what, when and why, field by field, old
--      value and new. The client's own submission is never altered: a correction
--      writes a new intake version, and drafting always reads the latest one.
--   2. msp_intake_triage_reasons(payload): the intake validator's triage rules
--      (vercel/lib/validate.js) in SQL, so a correction is held to the same test as a
--      fresh submission. Keep the two in step.
--   3. msp_triage_cases(): for the staff page, every submission in triage or awaiting
--      booking with its reasons, defects, latest payload and correction count.
--   4. msp_triage_correct(reference, changes, reason): applies field corrections,
--      refuses them if the corrected intake would still fail the checks or carries an
--      identity number, or if a job the form flagged for unreadable hazard letters is
--      not corrected, records them, writes the new intake version with its sites,
--      job categories, exposures and chemicals, and sends the submission back for
--      drafting (msp_pipeline_rerun). The next worker run drafts it and sales get the
--      outcome mail.
--   5. msp_pipeline_rerun refuses a submission the form held back: the stored payload
--      can be missing what the form could not read, so it goes through the correction.
--   6. msp_triage_close(reference, outcome, reason): ends a submission that will not
--      proceed (rejected or archived), with the reason recorded.
-- All three staff functions accept a forge_admin session or the SQL editor. Consent,
-- declaration and identity fields can never be corrected: they record what the
-- client agreed to.

-- 1. The correction record ---------------------------------------------------------
create table if not exists msp_intake_correction (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id) on delete cascade,
  reference text not null,
  from_intake_id uuid not null references msp_intake(id),
  to_intake_id uuid not null references msp_intake(id),
  from_status text not null,
  corrected_by text not null,
  corrected_at timestamptz not null default now(),
  reason text not null check (length(btrim(reason)) >= 5),
  changes jsonb not null
);
comment on table msp_intake_correction is 'Audited corrections to a submission. The client''s intake row is never changed: each correction writes a new intake version (to_intake_id) and records every field''s old and new value here.';
alter table msp_intake_correction enable row level security;
drop policy if exists msp_intake_correction_staff_read on msp_intake_correction;
create policy msp_intake_correction_staff_read on msp_intake_correction for select to authenticated using (msp_has_role('forge_admin'));

-- 2. The validator's triage rules, for a corrected payload --------------------------
create or replace function msp_intake_triage_reasons(p jsonb)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_out text[] := '{}';
  f text;
  j jsonb;
  c text;
  v_valid int;
  v_sub text := upper(btrim(coalesce(p->>'subindustry_code', '')));
begin
  foreach f in array array['company_registered_name', 'company_registration_number', 'company_head_office_address',
    'company_core_industry_freetext', 'company_years_operating', 'workforce_total', 'industry_code', 'subindustry_code',
    'delivery_contact_name', 'delivery_contact_email', 'information_officer_name', 'information_officer_contact',
    'declarant_full_name', 'declarant_position', 'declarant_company'] loop
    if nullif(btrim(coalesce(p->>f, '')), '') is null then v_out := v_out || ('required field missing: ' || f); end if;
  end loop;
  if lower(coalesce(p->>'employees_informed_before_exam', '')) not in ('true', 'yes', 'on', '1', 'checked') then
    v_out := v_out || 'client has not confirmed employees will be informed before first examination'::text;
  end if;
  if v_sub = 'OTHER' or upper(btrim(coalesce(p->>'industry_code', ''))) = 'OTHER' then
    v_out := v_out || 'industry selection is OTHER; routed to human triage, never auto generated'::text;
  elsif not exists (select 1 from msp_subindustry s where s.code = v_sub and s.selectable) then
    v_out := v_out || ('subindustry code ' || coalesce(nullif(v_sub, ''), '(empty)') || ' is not in the governed selectable list');
  end if;
  if jsonb_typeof(p->'jobs') <> 'array' or jsonb_array_length(p->'jobs') = 0 then
    v_out := v_out || 'no job categories supplied'::text;
  else
    for j in select * from jsonb_array_elements(p->'jobs') loop
      if nullif(btrim(coalesce(j->>'title', '')), '') is null then
        v_out := v_out || 'job category block without a title'::text;
        continue;
      end if;
      v_valid := 0;
      if jsonb_typeof(j->'hazard_codes') = 'array' then
        for c in select jsonb_array_elements_text(j->'hazard_codes') loop
          if c ~ '^[A-O]$' then v_valid := v_valid + 1;
          else v_out := v_out || ('job ' || (j->>'title') || ': unknown hazard codes ' || c); end if;
        end loop;
      end if;
      if v_valid = 0 then v_out := v_out || ('job ' || (j->>'title') || ': no valid hazard codes'); end if;
    end loop;
  end if;
  return v_out;
end;
$$;
revoke execute on function msp_intake_triage_reasons(jsonb) from public, anon, authenticated;
comment on function msp_intake_triage_reasons is 'Server side only: the triage rules of vercel/lib/validate.js applied to a stored payload. Keep in step with validate.js.';

-- Sites, job categories, exposures and chemicals for an intake version. A copy of the
-- loops in msp_ingest_intake (migration 006); keep the two in step.
create or replace function msp_intake_children(p_intake_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site jsonb;
  v_job jsonb;
  v_exp jsonb;
  v_chem jsonb;
  v_row int := 0;
begin
  for v_site in select * from jsonb_array_elements(coalesce(p->'sites', '[]'::jsonb)) loop
    insert into msp_intake_site (intake_id, site_name, site_address, activity, headcount)
    values (p_intake_id, coalesce(v_site->>'name', 'Unnamed site'), v_site->>'address', v_site->>'activity',
            nullif(v_site->>'headcount', '')::int);
  end loop;
  for v_job in select * from jsonb_array_elements(coalesce(p->'jobs', '[]'::jsonb)) loop
    v_row := v_row + 1;
    insert into msp_intake_job_category
      (intake_id, row_no, title, headcount, duties, hazard_codes, existing_controls,
       physical_demands, sensory_cognitive_demands, statutory_requirement,
       chronic_flag, rpe_issued, rpe_fit_tested, rpe_fit_test_interval, other_ppe)
    values
      (p_intake_id, v_row, v_job->>'title', nullif(v_job->>'headcount', '')::int, v_job->>'duties',
       case when v_job ? 'hazard_codes' then array(select jsonb_array_elements_text(v_job->'hazard_codes')) else null end,
       v_job->>'existing_controls', v_job->>'physical_demands', v_job->>'sensory_cognitive_demands',
       v_job->>'statutory_requirement', coalesce((v_job->>'chronic_flag')::boolean, false),
       v_job->>'rpe_issued', v_job->>'rpe_fit_tested', v_job->>'rpe_fit_test_interval', v_job->>'other_ppe');
  end loop;
  for v_exp in select * from jsonb_array_elements(coalesce(p->'exposures', '[]'::jsonb)) loop
    insert into msp_intake_exposure (intake_id, hazard_location, measured_level, unit, stated_oel, date_measured)
    values (p_intake_id, coalesce(v_exp->>'hazard_location', 'Unspecified'), coalesce(v_exp->>'measured_level', ''),
            v_exp->>'unit', v_exp->>'stated_oel', nullif(v_exp->>'date_measured', '')::date);
  end loop;
  for v_chem in select * from jsonb_array_elements(coalesce(p->'chemicals', '[]'::jsonb)) loop
    insert into msp_intake_chemical (intake_id, substance_name, sds_reference, task_process, frequency, quantity_per_use, controls)
    values (p_intake_id, coalesce(v_chem->>'substance_name', 'Unspecified'), v_chem->>'sds_reference', v_chem->>'task_process',
            v_chem->>'frequency', v_chem->>'quantity_per_use', v_chem->>'controls');
  end loop;
end;
$$;
revoke execute on function msp_intake_children(uuid, jsonb) from public, anon, authenticated;

create or replace function msp_staff_actor()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case when session_user in ('postgres', 'supabase_admin') then 'it:sql-editor'
              else coalesce('staff:' || nullif(auth.jwt()->>'email', ''), 'staff') end;
$$;
revoke execute on function msp_staff_actor() from public, anon, authenticated;

-- 3. The cases a person can act on ----------------------------------------------------
create or replace function msp_triage_cases()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (msp_caller_is('forge_admin') or session_user in ('postgres', 'supabase_admin')) then
    raise exception 'the triage cases are for forge_admin staff';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'reference', e.reference, 'status', e.status, 'created_at', e.created_at,
      'company', c.registered_name, 'intake_id', i.id, 'intake_version_at', i.received_at,
      'triage_reason', i.triage_reason,
      'open_reasons', to_jsonb(msp_intake_triage_reasons(i.raw_payload)),
      'defects', (select coalesce(jsonb_agg(jsonb_build_object('stage', d.stage, 'code', d.defect_code, 'detail', d.detail,
                    'at', d.created_at) order by d.created_at), '[]') from msp_defect d where d.engagement_id = e.id),
      'corrections', (select count(*) from msp_intake_correction x where x.engagement_id = e.id),
      'payload', i.raw_payload) order by e.created_at), '[]')
    from msp_engagement e
    join msp_client c on c.id = e.client_id
    join lateral (select * from msp_intake x where x.engagement_id = e.id order by x.received_at desc limit 1) i on true
   where e.status in ('triage', 'awaiting_booking'));
end;
$$;
revoke execute on function msp_triage_cases() from public, anon;
grant execute on function msp_triage_cases() to authenticated;
comment on function msp_triage_cases is 'forge_admin or the SQL editor: submissions in triage or awaiting booking, with the validator reasons that still apply, drafting defects, the latest payload and the number of corrections.';

-- 4. Correct and send back for drafting -----------------------------------------------
-- p_changes: [ { "path": ["jobs", 0, "hazard_codes"], "value": ["A", "E"] }, ... ]
create or replace function msp_triage_correct(p_reference text, p_changes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng msp_engagement%rowtype;
  v_old msp_intake%rowtype;
  v_payload jsonb;
  v_new_intake uuid;
  v_corr uuid;
  v_log jsonb := '[]'::jsonb;
  v_path text[];
  v_val jsonb;
  v_prev jsonb;
  v_codes text[];
  v_raw text[];
  v_seg text;
  v_title text;
  v_jidx text;
  v_reasons text[];
  ch jsonb;
  c text;
begin
  if not (msp_caller_is('forge_admin') or session_user in ('postgres', 'supabase_admin')) then
    raise exception 'correcting a submission requires the forge_admin role';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'say why the submission is being corrected (at least five characters)';
  end if;
  if jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then
    raise exception 'changes must be a non empty array of {path, value}';
  end if;

  select * into v_eng from msp_engagement where reference = p_reference for update;
  if v_eng.id is null then raise exception 'no engagement %', p_reference; end if;
  if v_eng.status not in ('triage', 'awaiting_booking') then
    raise exception 'engagement % is %; only a submission in triage or a Plan awaiting booking can be corrected', p_reference, v_eng.status;
  end if;
  select * into v_old from msp_intake where engagement_id = v_eng.id order by received_at desc limit 1;
  v_payload := v_old.raw_payload;

  for ch in select * from jsonb_array_elements(p_changes) loop
    if jsonb_typeof(ch->'path') <> 'array' or jsonb_array_length(ch->'path') = 0 or not (ch ? 'value') then
      raise exception 'each change needs a path (array) and a value';
    end if;
    v_path := array(select jsonb_array_elements_text(ch->'path'));
    if v_path[1] in ('consent_processing', 'consent_marketing', 'consent_wording_version', 'popia_use_cnc_forms',
                     'declarant_full_name', 'declarant_position', 'declarant_company', 'declaration_date',
                     'docuseal_submission_id', 'schema_version', 'validation_status', 'triage_reason')
       or v_path[1] like 'consent%' then
      raise exception 'field % records what the client declared or consented to and cannot be corrected', v_path[1];
    end if;
    v_prev := v_payload #> v_path;
    if v_prev is null and array_length(v_path, 1) > 1 then
      raise exception 'path % does not exist in the submission', array_to_string(v_path, '.');
    end if;
    v_val := ch->'value';
    if v_val::text ~ '\d{13}' then
      raise exception 'a corrected value contains a thirteen digit sequence resembling an identity number';
    end if;
    if v_path[array_length(v_path, 1)] = 'hazard_codes' then
      v_codes := '{}';
      -- Letters as an array or as typed text ("A., E" or "A,E"); punctuation and case are ignored.
      v_raw := case jsonb_typeof(v_val)
                 when 'array' then array(select jsonb_array_elements_text(v_val))
                 when 'string' then regexp_split_to_array(v_val #>> '{}', '[\s,;/]+')
                 else '{}'::text[] end;
      foreach c in array v_raw loop
        c := upper(regexp_replace(coalesce(c, ''), '[^A-Za-z]', '', 'g'));
        if c = '' then continue; end if;
        if c !~ '^[A-O]$' then raise exception 'hazard letter % is not on the key (A to O)', c; end if;
        if not c = any(v_codes) then v_codes := v_codes || c; end if;
      end loop;
      if coalesce(array_length(v_codes, 1), 0) = 0 then raise exception 'at least one hazard letter is needed'; end if;
      v_val := to_jsonb(v_codes);
    end if;
    v_payload := jsonb_set(v_payload, v_path, v_val, true);
    v_log := v_log || jsonb_build_array(jsonb_build_object('path', to_jsonb(v_path), 'old', v_prev, 'new', v_val));
  end loop;

  -- The form drops hazard letters it cannot read (validate.js keeps only A to O), so the
  -- stored job can look complete while missing a hazard: CNC-MSP-2026-1012-001 kept F and
  -- lost the typed "A." and "E.". Every job the form flagged must have its letters
  -- corrected explicitly here, or the Plan would be drafted without those hazards.
  if v_old.validation_status = 'triage' and v_old.triage_reason is not null then
    foreach v_seg in array string_to_array(v_old.triage_reason, '; ') loop
      if v_seg ~ '^job .+: unknown hazard codes ' then
        v_title := substring(v_seg from '^job (.+): unknown hazard codes ');
        select (j.o - 1)::text into v_jidx
          from jsonb_array_elements(v_old.raw_payload->'jobs') with ordinality j(v, o)
         where j.v->>'title' = v_title order by j.o limit 1;
        if not exists (select 1 from jsonb_array_elements(v_log) l
                        where l->'path' = jsonb_build_array('jobs', v_jidx, 'hazard_codes')) then
          raise exception 'job "%" had hazard letters the form could not read (%); correct jobs.%.hazard_codes in this correction',
            v_title, substring(v_seg from 'unknown hazard codes (.*)$'), coalesce(v_jidx, '?');
        end if;
      end if;
    end loop;
  end if;

  v_payload := jsonb_set(jsonb_set(v_payload, '{validation_status}', '"valid"'), '{triage_reason}', 'null');
  v_reasons := msp_intake_triage_reasons(v_payload);
  if coalesce(array_length(v_reasons, 1), 0) > 0 then
    raise exception 'the corrected submission would still go to triage: %', array_to_string(v_reasons, '; ');
  end if;

  insert into msp_intake (engagement_id, docuseal_submission_id, raw_payload, schema_version, validation_status, triage_reason)
  values (v_eng.id, v_old.docuseal_submission_id, v_payload, v_old.schema_version, 'valid', null)
  returning id into v_new_intake;
  perform msp_intake_children(v_new_intake, v_payload);

  insert into msp_intake_correction (engagement_id, reference, from_intake_id, to_intake_id, from_status, corrected_by, reason, changes)
  values (v_eng.id, v_eng.reference, v_old.id, v_new_intake, v_eng.status, msp_staff_actor(), btrim(p_reason), v_log)
  returning id into v_corr;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng.id, msp_staff_actor(), 'intake_corrected',
          jsonb_build_object('correction_id', v_corr, 'from_intake', v_old.id, 'to_intake', v_new_intake,
                             'fields', jsonb_array_length(v_log), 'reason', btrim(p_reason)));

  perform msp_pipeline_rerun(p_reference);
  return jsonb_build_object('reference', p_reference, 'correction_id', v_corr, 'intake_id', v_new_intake,
                            'status', 'intake', 'changes', v_log);
end;
$$;
revoke execute on function msp_triage_correct(text, jsonb, text) from public, anon;
grant execute on function msp_triage_correct(text, jsonb, text) to authenticated;
comment on function msp_triage_correct is 'forge_admin or the SQL editor: correct fields of a submission in triage or awaiting booking, with a reason. Refused if the result would still fail the intake checks. Writes a new intake version, records old and new values in msp_intake_correction, and sends the submission back for drafting.';

-- 5. Redraft refuses a submission the form held back ------------------------------------
create or replace function msp_pipeline_rerun(p_reference text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_status text;
  v_removed int := 0;
begin
  if not (msp_caller_is('forge_admin') or session_user in ('postgres', 'supabase_admin')) then
    raise exception 'sending a Plan back for drafting requires the forge_admin role';
  end if;
  select id, status into v_id, v_status from msp_engagement where reference = p_reference for update;
  if v_id is null then raise exception 'no engagement %', p_reference; end if;

  -- Held by the form checks: a plain redraft would draft the data as stored, which may
  -- have lost what the form could not read. Correct it with msp_triage_correct instead.
  if exists (select 1 from msp_intake x where x.id = (select id from msp_intake where engagement_id = v_id order by received_at desc limit 1)
               and x.validation_status = 'triage') then
    raise exception 'engagement % was held by the form checks (%); correct it with msp_triage_correct, which sends it back for drafting',
      p_reference, (select triage_reason from msp_intake where engagement_id = v_id order by received_at desc limit 1);
  end if;

  if v_status = 'omp_queue' then
    if exists (select 1 from msp_omp_review where engagement_id = v_id and decision is not null) then
      raise exception 'engagement % has a practitioner decision; it cannot be redrafted', p_reference;
    end if;
    delete from msp_omp_review where engagement_id = v_id and decision is null;
    get diagnostics v_removed = row_count;
  elsif v_status not in ('triage', 'awaiting_booking') then
    raise exception 'engagement % is %; only a submission in triage, a Plan awaiting booking or an undecided Plan in the review queue can be redrafted', p_reference, v_status;
  end if;

  update msp_intake set validation_status = 'valid'
   where id = (select id from msp_intake where engagement_id = v_id order by received_at desc limit 1);
  update msp_engagement set status = 'intake', pipeline_attempts = 0, pipeline_claimed_at = null where id = v_id;
  delete from msp_notification where engagement_id = v_id and kind in ('pipeline_result', 'omp_review_requested', 'omp_review_overdue');
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_id, case when session_user in ('postgres', 'supabase_admin') then 'it:sql-editor' else 'admin' end,
          'pipeline_rerun_requested',
          jsonb_build_object('from_status', v_status, 'undecided_reviews_removed', v_removed));
  return jsonb_build_object('reference', p_reference, 'status', 'intake', 'from_status', v_status,
                            'undecided_reviews_removed', v_removed);
end;
$$;
revoke execute on function msp_pipeline_rerun(text) from public, anon;
grant execute on function msp_pipeline_rerun(text) to authenticated;

-- 6. A submission that will not proceed -------------------------------------------------
create or replace function msp_triage_close(p_reference text, p_outcome text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng msp_engagement%rowtype;
begin
  if not (msp_caller_is('forge_admin') or session_user in ('postgres', 'supabase_admin')) then
    raise exception 'closing a submission requires the forge_admin role';
  end if;
  if p_outcome not in ('rejected', 'archived') then
    raise exception 'outcome must be rejected (will not be drafted) or archived (duplicate or withdrawn)';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'say why the submission is being closed (at least five characters)';
  end if;
  select * into v_eng from msp_engagement where reference = p_reference for update;
  if v_eng.id is null then raise exception 'no engagement %', p_reference; end if;
  if v_eng.status not in ('triage', 'awaiting_booking', 'intake') then
    raise exception 'engagement % is %; only a submission in triage, intake or awaiting booking can be closed here', p_reference, v_eng.status;
  end if;
  update msp_engagement set status = p_outcome where id = v_eng.id;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng.id, msp_staff_actor(), 'engagement_closed',
          jsonb_build_object('from_status', v_eng.status, 'outcome', p_outcome, 'reason', btrim(p_reason)));
  return jsonb_build_object('reference', p_reference, 'status', p_outcome, 'from_status', v_eng.status);
end;
$$;
revoke execute on function msp_triage_close(text, text, text) from public, anon;
grant execute on function msp_triage_close(text, text, text) to authenticated;
comment on function msp_triage_close is 'forge_admin or the SQL editor: end a submission that will not proceed (rejected or archived), with the reason in the audit.';

notify pgrst, 'reload schema';
