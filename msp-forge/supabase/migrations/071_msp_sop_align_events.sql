-- CNC MSP FORGE | AGT-RUN-01 v1.1.0 | Build A: align the intake flow to the MSP Journey SOP 13/10/2026
-- Source: the MD's "Medical Surveillance Plan: Journey, System and Decisions" (internal
-- draft, 12/10/2026), IT gap analysis CNC-IT-MSP-019 item A.
--
-- This migration:
--   1. adds the status awaiting_booking. A Plan that drafts cleanly now waits there
--      for the booking or deposit (SOP step 8) instead of going straight to the
--      practitioner queue; the practitioner sees it only after payment (SOP step 16,
--      a later build). Triage is unchanged.
--   2. adds msp_event, the events table of SOP section 04 and the portability
--      contract of section 08: every event is written as a JSON row before any
--      outside call, with its delivery outcome (pending, sent, failed, abandoned),
--      the error text and the attempt count. It is also the queue for the sales mails.
--   3. writes intake.submitted when an intake is saved (deferred trigger, so the
--      sites and job categories are in place), and plan.drafted or plan.draft_failed
--      when drafting finishes (msp_pipeline_persist).
--   4. retries failed sends: agent.event_retry_max attempts (5), the gap doubling from
--      agent.event_retry_gap_minutes (10, 20, 40, 80 minutes). After the last attempt
--      the event is abandoned and IT is told (msp-intake-worker v1.1.0).
--   5. moves the Plans already waiting in the practitioner queue with no practitioner
--      decision to awaiting_booking, except the August Horizon sample, which stays as
--      the review tool's demonstration Plan. Their undecided review rows carry no
--      decision, name or signature and are removed; the audit keeps the move.
--   6. gives the sales mail the contact number from the sign on account, where one
--      exists (msp_notify_engagement).
--   7. lets a Plan awaiting booking be sent back for drafting (msp_pipeline_rerun).
-- Practitioner notices stay on msp_notification and stay switched off until a
-- practitioner is named. msp_notification keeps its history; new sales mails are
-- recorded in msp_event only.

-- 1. Status ----------------------------------------------------------------------
alter table msp_engagement drop constraint if exists msp_engagement_status_check;
alter table msp_engagement add constraint msp_engagement_status_check
  check (status in ('intake','triage','classifying','drafting','validating','awaiting_booking',
                    'omp_queue','approved','released','rejected','archived'));

-- 2. Retry settings ----------------------------------------------------------------
insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('agent.event_retry_max', '5', 'integer', 1, 20, 'agent',
   'How many times a failed send (sales mail) is attempted before the event is abandoned and IT is told.'),
  ('agent.event_retry_gap_minutes', '10', 'integer', 1, 1440, 'agent',
   'Minutes before the first retry of a failed send; each further retry waits twice as long.')
on conflict (key) do nothing;

insert into msp_env_parameter_history (key, old_value, new_value, changed_by, reason)
select k, null, v, 'migration_071', 'Event retries (SOP section 04)'
  from (values ('agent.event_retry_max', '5'), ('agent.event_retry_gap_minutes', '10')) as x(k, v)
 where not exists (select 1 from msp_env_parameter_history h where h.key = x.k);

-- 3. The events table ----------------------------------------------------------------
create table if not exists msp_event (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id) on delete cascade,
  reference text not null,
  event_type text not null check (event_type in (
    'intake.submitted', 'plan.drafted', 'plan.draft_failed', 'booking.confirmed', 'plan.released',
    'quote.requested', 'quote.issued', 'payment.confirmed', 'review.sent', 'review.corrected',
    'review.signed', 'billing.omp_claimable', 'mco.file_filed')),
  dedupe_key text not null default '',
  payload jsonb not null,
  occurred_at timestamptz not null default now(),
  delivery text not null default 'none' check (delivery in ('none', 'pending', 'sent', 'failed', 'abandoned')),
  channel text check (channel in ('email')),
  recipients text,
  subject text,
  attempts int not null default 0,
  last_error text,
  next_attempt_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (engagement_id, event_type, dedupe_key)
);
create index if not exists msp_event_due_idx on msp_event (next_attempt_at) where delivery in ('pending', 'failed');
comment on table msp_event is 'SOP section 04 and 08: one JSON row per event, written before any outside call, with its delivery outcome, error and attempts. Also the queue for the sales mails. A retry carries the same row, so one event is never mailed twice.';
alter table msp_event enable row level security;
drop policy if exists msp_event_staff_read on msp_event;
create policy msp_event_staff_read on msp_event for select to authenticated using (msp_has_role('forge_admin'));

-- 4. intake.submitted ------------------------------------------------------------------
create or replace function msp_event_capture_intake(p_engagement_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into msp_event (engagement_id, reference, event_type, payload, occurred_at, delivery, channel)
  select e.id, e.reference, 'intake.submitted',
         jsonb_build_object('reference', e.reference, 'company_id', e.client_id, 'company_name', c.registered_name,
                            'industry', i.raw_payload->>'industry_code', 'subindustry', i.raw_payload->>'subindustry_code',
                            'headcount', nullif(regexp_replace(coalesce(i.raw_payload->>'workforce_total', ''), '\D', '', 'g'), '')::int,
                            'status', case when i.validation_status = 'triage' then 'triage' else 'clean' end,
                            'consent_version', i.raw_payload->>'consent_wording_version',
                            'submitted_at', i.received_at),
         coalesce(i.received_at, now()), 'pending', 'email'
    from msp_engagement e
    join msp_client c on c.id = e.client_id
    join lateral (select * from msp_intake x where x.engagement_id = e.id order by x.received_at desc limit 1) i on true
   where e.id = p_engagement_id
  on conflict (engagement_id, event_type, dedupe_key) do nothing
  returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function msp_event_capture_intake(uuid) from public, anon, authenticated;

create or replace function msp_event_intake_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform msp_event_capture_intake(new.engagement_id);
  return null;
end;
$$;
revoke execute on function msp_event_intake_trigger() from public, anon, authenticated;

drop trigger if exists msp_intake_event on msp_intake;
create constraint trigger msp_intake_event
  after insert on msp_intake
  deferrable initially deferred
  for each row execute function msp_event_intake_trigger();

-- Safety net, run by the worker each pass: any engagement with an intake and no
-- intake.submitted event gets one.
create or replace function msp_event_capture()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n int := 0;
  r record;
begin
  for r in select e.id from msp_engagement e
            where exists (select 1 from msp_intake i where i.engagement_id = e.id)
              and not exists (select 1 from msp_event v where v.engagement_id = e.id and v.event_type = 'intake.submitted')
  loop
    if msp_event_capture_intake(r.id) is not null then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end;
$$;
revoke execute on function msp_event_capture() from public, anon, authenticated;

-- 5. The outcome of one send -------------------------------------------------------
create or replace function msp_event_result(p_event_id uuid, p_ok boolean, p_recipients text, p_subject text, p_error text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v msp_event%rowtype;
  v_max int := coalesce(msp_env_get_int('agent.event_retry_max'), 5);
  v_gap int := coalesce(msp_env_get_int('agent.event_retry_gap_minutes'), 10);
begin
  select * into v from msp_event where id = p_event_id for update;
  if v.id is null then raise exception 'no event %', p_event_id; end if;
  if v.delivery not in ('pending', 'failed') then
    return jsonb_build_object('event_id', v.id, 'delivery', v.delivery, 'attempts', v.attempts, 'changed', false);
  end if;
  v.attempts := v.attempts + 1;
  if p_ok then
    update msp_event set delivery = 'sent', attempts = v.attempts, sent_at = now(), next_attempt_at = null,
                         last_error = null, recipients = left(p_recipients, 500), subject = left(p_subject, 300)
     where id = v.id;
    insert into msp_audit (engagement_id, actor, event_type, event_detail)
    values (v.engagement_id, 'msp-intake-worker', 'notification_sent',
            jsonb_build_object('event', v.event_type, 'event_id', v.id, 'recipients', left(p_recipients, 500)));
    return jsonb_build_object('event_id', v.id, 'delivery', 'sent', 'attempts', v.attempts, 'changed', true);
  end if;
  if v.attempts >= v_max then
    update msp_event set delivery = 'abandoned', attempts = v.attempts, next_attempt_at = null,
                         last_error = left(p_error, 500), recipients = left(p_recipients, 500), subject = left(p_subject, 300)
     where id = v.id;
    insert into msp_audit (engagement_id, actor, event_type, event_detail)
    values (v.engagement_id, 'msp-intake-worker', 'notification_abandoned',
            jsonb_build_object('event', v.event_type, 'event_id', v.id, 'attempts', v.attempts, 'error', left(p_error, 500)));
    return jsonb_build_object('event_id', v.id, 'delivery', 'abandoned', 'attempts', v.attempts, 'changed', true, 'abandoned', true);
  end if;
  update msp_event set delivery = 'failed', attempts = v.attempts, last_error = left(p_error, 500),
                       next_attempt_at = now() + make_interval(mins => v_gap * (2 ^ (v.attempts - 1))::int),
                       recipients = left(p_recipients, 500), subject = left(p_subject, 300)
   where id = v.id;
  return jsonb_build_object('event_id', v.id, 'delivery', 'failed', 'attempts', v.attempts, 'changed', true);
end;
$$;
revoke execute on function msp_event_result(uuid, boolean, text, text, text) from public, anon, authenticated;
comment on function msp_event_result is 'Server side only: records the outcome of one send. Failed sends wait agent.event_retry_gap_minutes, doubling; after agent.event_retry_max attempts the event is abandoned.';

-- 6. The past, already announced, is recorded as sent and never mailed again ----------
insert into msp_event (engagement_id, reference, event_type, dedupe_key, payload, occurred_at, delivery, channel, recipients, subject, attempts, sent_at)
select e.id, e.reference, 'intake.submitted', '',
       jsonb_build_object('reference', e.reference, 'company_id', e.client_id, 'company_name', c.registered_name,
                          'industry', i.raw_payload->>'industry_code', 'subindustry', i.raw_payload->>'subindustry_code',
                          'headcount', nullif(regexp_replace(coalesce(i.raw_payload->>'workforce_total', ''), '\D', '', 'g'), '')::int,
                          'status', case when i.validation_status = 'triage' then 'triage' else 'clean' end,
                          'consent_version', i.raw_payload->>'consent_wording_version',
                          'submitted_at', i.received_at, 'backfilled_from', 'msp_notification'),
       coalesce(i.received_at, e.created_at), 'sent', 'email', n.recipients, n.subject, 1, n.created_at
  from msp_engagement e
  join msp_client c on c.id = e.client_id
  join msp_notification n on n.engagement_id = e.id and n.kind = 'intake_received'
  left join lateral (select * from msp_intake x where x.engagement_id = e.id order by x.received_at desc limit 1) i on true
on conflict (engagement_id, event_type, dedupe_key) do nothing;

insert into msp_event (engagement_id, reference, event_type, dedupe_key, payload, occurred_at, delivery, channel, recipients, subject, attempts, sent_at)
select e.id, e.reference, 'plan.drafted', coalesce(d.id::text, 'backfill'),
       jsonb_build_object('reference', e.reference, 'plan_id', d.id, 'checks_passed', e.status = 'omp_queue',
                          'drafted_at', d.created_at, 'backfilled_from', 'msp_notification'),
       coalesce(d.created_at, n.created_at), 'sent', 'email', n.recipients, n.subject, 1, n.created_at
  from msp_engagement e
  join msp_notification n on n.engagement_id = e.id and n.kind = 'pipeline_result'
  left join lateral (select x.id, x.created_at from msp_draft x where x.engagement_id = e.id and x.stage = 'compose'
                      order by x.created_at desc limit 1) d on true
on conflict (engagement_id, event_type, dedupe_key) do nothing;

-- 7. Plans already in the practitioner queue wait for the booking instead -----------
with moved as (
  update msp_engagement e set status = 'awaiting_booking'
   where e.status = 'omp_queue'
     and e.reference <> 'CNC-MSP-2026-0812-001'
     and not exists (select 1 from msp_omp_review r where r.engagement_id = e.id and r.decision is not null)
  returning e.id
), removed as (
  delete from msp_omp_review r using moved m
   where r.engagement_id = m.id and r.decision is null
  returning r.engagement_id
)
insert into msp_audit (engagement_id, actor, event_type, event_detail)
select m.id, 'migration_071', 'status_moved',
       jsonb_build_object('from', 'omp_queue', 'to', 'awaiting_booking', 'reason', 'SOP: practitioner review follows payment',
                          'undecided_reviews_removed', (select count(*) from removed x where x.engagement_id = m.id))
  from moved m;

-- 8. Functions brought in line ----------------------------------------------------
create or replace function msp_pipeline_persist(p_engagement_id uuid, p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_outcome text := coalesce(p_result->>'outcome', 'error');
  v_model text := coalesce(p_result->>'model_used', 'deterministic pipeline');
  v_stage text;
  v_draft uuid;
  v_compose uuid;
  v_validate uuid;
  v_checks_passed boolean;
  v_attempts int;
  v_cls jsonb := p_result #> '{stages,classify}';
  d jsonb;
begin
  select status, pipeline_attempts into v_status, v_attempts from msp_engagement where id = p_engagement_id for update;
  if v_status is null then raise exception 'engagement % not found', p_engagement_id; end if;
  if v_status <> 'classifying' then
    raise exception 'engagement % is %, not claimed for drafting', p_engagement_id, v_status;
  end if;

  if v_outcome = 'error' then
    v_attempts := v_attempts + 1;
    update msp_engagement
       set status = case when v_attempts >= 3 then 'triage' else 'intake' end,
           pipeline_attempts = v_attempts, pipeline_claimed_at = null
     where id = p_engagement_id;
    if v_attempts >= 3 then
      insert into msp_defect (engagement_id, stage, defect_code, detail, blocking)
      values (p_engagement_id, 'pipeline', 'PIPELINE_ERROR',
              jsonb_build_object('error', left(coalesce(p_result->>'error', 'unknown'), 500), 'attempts', v_attempts), true);
      insert into msp_event (engagement_id, reference, event_type, dedupe_key, payload, delivery, channel)
      select e.id, e.reference, 'plan.draft_failed', 'attempt-' || v_attempts,
             jsonb_build_object('reference', e.reference, 'attempts', v_attempts,
                                'error', left(coalesce(p_result->>'error', 'unknown'), 500), 'failed_at', now()),
             'pending', 'email'
        from msp_engagement e where e.id = p_engagement_id
      on conflict (engagement_id, event_type, dedupe_key) do nothing;
    end if;
    insert into msp_audit (engagement_id, actor, event_type, event_detail)
    values (p_engagement_id, 'msp-intake-worker', 'pipeline_error',
            jsonb_build_object('attempts', v_attempts, 'error', left(coalesce(p_result->>'error', 'unknown'), 500)));
    return jsonb_build_object('status', case when v_attempts >= 3 then 'triage' else 'intake' end, 'attempts', v_attempts);
  end if;

  foreach v_stage in array array['classify','frame','profile','prescribe','compose','validate'] loop
    if p_result->'stages' ? v_stage then
      insert into msp_draft (engagement_id, stage, stage_output, schema_version, model_used)
      values (p_engagement_id, v_stage, p_result->'stages'->v_stage,
              coalesce(p_result->'stages'->v_stage->>'schema', v_stage || '.v1'), v_model)
      returning id into v_draft;
      if v_stage = 'compose' then v_compose := v_draft; end if;
      if v_stage = 'validate' then v_validate := v_draft; end if;
    end if;
  end loop;

  for d in select * from jsonb_array_elements(coalesce(p_result->'defects', '[]'::jsonb)) loop
    insert into msp_defect (engagement_id, stage, defect_code, detail, blocking)
    values (p_engagement_id, coalesce(d->>'stage', 'validate'), coalesce(d->>'defect_code', 'UNSPECIFIED'),
            coalesce(d->'detail', '{}'::jsonb), coalesce((d->>'blocking')::boolean, true));
  end loop;

  update msp_engagement
     set industry_id = coalesce((select i.id from msp_industry i where i.code = v_cls->>'industry_code'), industry_id),
         subindustry_id = coalesce((select s.id from msp_subindustry s where s.code = v_cls->>'subindustry_code'), subindustry_id),
         classification_confidence = coalesce((v_cls->>'confidence')::numeric, classification_confidence),
         pipeline_claimed_at = null
   where id = p_engagement_id;

  -- A clean Plan waits for the booking or deposit (SOP step 8); it reaches the
  -- practitioner only after payment (SOP step 16), not on drafting.
  v_checks_passed := v_outcome = 'queued';
  if v_checks_passed then
    if v_compose is null then raise exception 'a queued result must carry the compose stage'; end if;
    update msp_engagement set status = 'awaiting_booking' where id = p_engagement_id;
  else
    update msp_engagement set status = 'triage' where id = p_engagement_id;
  end if;

  insert into msp_event (engagement_id, reference, event_type, dedupe_key, payload, delivery, channel)
  select e.id, e.reference, 'plan.drafted', coalesce(v_compose, v_validate, gen_random_uuid())::text,
         jsonb_build_object('reference', e.reference, 'plan_id', v_compose,
                            'framework_version', p_result #>> '{summary,kernel_release}',
                            'rules_version', p_result #>> '{summary,pipeline_version}',
                            'prompt_version', null,
                            'checks_passed', v_checks_passed,
                            'checks', (p_result #>> '{summary,checks_passed}')::int,
                            'checks_total', (p_result #>> '{summary,checks_total}')::int,
                            'drafted_at', now()),
         'pending', 'email'
    from msp_engagement e where e.id = p_engagement_id
  on conflict (engagement_id, event_type, dedupe_key) do nothing;

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (p_engagement_id, 'msp-intake-worker', 'pipeline_completed',
          jsonb_build_object('outcome', v_outcome, 'status', case when v_checks_passed then 'awaiting_booking' else 'triage' end, 'model_used', v_model,
                             'defects', jsonb_array_length(coalesce(p_result->'defects', '[]'::jsonb))));
  return jsonb_build_object('status', case when v_checks_passed then 'awaiting_booking' else 'triage' end,
                            'plan_id', v_compose);
end;
$$;
revoke execute on function msp_pipeline_persist(uuid, jsonb) from public, anon, authenticated;
comment on function msp_pipeline_persist is 'Server side only: writes one pipeline run (stage drafts, defects, status, plan.drafted event) for a claimed engagement. A clean Plan waits at awaiting_booking.';

create or replace function msp_notify_engagement(p_engagement_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'engagement_id', e.id, 'reference', e.reference, 'status', e.status, 'created_at', e.created_at,
    'company', c.registered_name, 'trading_name', c.trading_name,
    'industry_code', i.raw_payload->>'industry_code', 'industry_name', ind.name,
    'subindustry_code', i.raw_payload->>'subindustry_code', 'subindustry_name', s.name,
    'validation_status', i.validation_status, 'triage_reason', i.triage_reason,
    'workforce_total', i.raw_payload->>'workforce_total',
    'job_categories', (select count(*) from msp_intake_job_category j where j.intake_id = i.id),
    'sites', (select count(*) from msp_intake_site st where st.intake_id = i.id),
    'contact_name', coalesce(i.raw_payload->>'delivery_contact_name', i.raw_payload->>'declarant_full_name'),
    'contact_email', i.raw_payload->>'delivery_contact_email',
    'contact_position', i.raw_payload->>'declarant_position',
    'contact_number', (select a.contact_number from msp_client_account a
                        where lower(btrim(a.contact_email)) in (lower(btrim(i.raw_payload->>'delivery_contact_email')),
                                                                lower(btrim(i.raw_payload->>'information_officer_contact')))
                          and nullif(btrim(a.contact_number), '') is not null
                        order by a.created_at desc limit 1),
    'review_id', (select r.id from msp_omp_review r where r.engagement_id = e.id and r.decision is null
                   order by r.id limit 1),
    'defects', (select coalesce(jsonb_agg(jsonb_build_object('stage', df.stage, 'code', df.defect_code,
                   'detail', df.detail) order by df.created_at), '[]') from msp_defect df where df.engagement_id = e.id),
    'omp_requested_at', (select n.created_at from msp_notification n where n.engagement_id = e.id
                          and n.kind = 'omp_review_requested' and n.status = 'sent'))
  from msp_engagement e
  join msp_client c on c.id = e.client_id
  left join lateral (select * from msp_intake x where x.engagement_id = e.id order by x.received_at desc limit 1) i on true
  left join msp_subindustry s on s.code = i.raw_payload->>'subindustry_code'
  left join msp_industry ind on ind.id = s.industry_id
  where e.id = p_engagement_id;
$$;
revoke execute on function msp_notify_engagement(uuid) from public, anon, authenticated;

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

create or replace function msp_notify_due()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days int := coalesce(msp_env_get_int('agent.omp_review_days'), 5);
begin
  return jsonb_build_object(
    'settings', jsonb_build_object(
      'sales_to', msp_env_get('integration.msp_notify_sales_to'),
      'sales_cc', msp_env_get('integration.msp_notify_sales_cc'),
      'sales_bcc', msp_env_get('integration.msp_notify_sales_bcc'),
      'omp_to', msp_env_get('integration.msp_notify_omp_to'),
      'site_url', msp_env_get('integration.site_base_url'),
      'auto_run', coalesce(msp_env_get_bool('agent.pipeline_auto_run'), true),
      'batch', coalesce(msp_env_get_int('agent.pipeline_batch_size'), 3),
      'review_days', v_days,
      'retry_max', coalesce(msp_env_get_int('agent.event_retry_max'), 5),
      'retry_gap_minutes', coalesce(msp_env_get_int('agent.event_retry_gap_minutes'), 10)),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('event_id', ev.id, 'event_type', ev.event_type,
                   'attempts', ev.attempts, 'payload', ev.payload,
                   'engagement', msp_notify_engagement(ev.engagement_id)) order by ev.created_at), '[]')
        from msp_event ev
       where ev.channel = 'email'
         and (ev.delivery = 'pending' or (ev.delivery = 'failed' and ev.next_attempt_at <= now()))),
    'omp_review_requested', (select coalesce(jsonb_agg(msp_notify_engagement(e.id) order by e.created_at), '[]')
        from msp_engagement e
       where e.status = 'omp_queue'
         and exists (select 1 from msp_omp_review r where r.engagement_id = e.id and r.decision is null)
         and not exists (select 1 from msp_notification n where n.engagement_id = e.id and n.kind = 'omp_review_requested')),
    'omp_review_overdue', (select coalesce(jsonb_agg(msp_notify_engagement(e.id) order by e.created_at), '[]')
        from msp_engagement e
        join msp_notification n on n.engagement_id = e.id and n.kind = 'omp_review_requested' and n.status = 'sent'
       where e.status = 'omp_queue'
         and n.created_at < now() - make_interval(days => v_days)
         and exists (select 1 from msp_omp_review r where r.engagement_id = e.id and r.decision is null)
         and not exists (select 1 from msp_notification o where o.engagement_id = e.id and o.kind = 'omp_review_overdue')));
end;
$$;
revoke execute on function msp_notify_due() from public, anon, authenticated;
comment on function msp_notify_due is 'Server side only: settings, sales events due for sending (msp_event), and practitioner notices owed (msp_notification).';

notify pgrst, 'reload schema';
