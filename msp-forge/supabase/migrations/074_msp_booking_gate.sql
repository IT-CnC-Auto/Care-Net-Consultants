-- CNC MSP FORGE | AGT-RUN-01 v1.3.0 | Build D: the booking or deposit gate 14/10/2026
-- MSP Journey SOP steps 7 and 8: a Plan is drafted at once but released only once the
-- client's medicals are booked with Care Net or a booking deposit is paid. Sales confirm
-- it, and the system records booking.confirmed with who confirmed it and the evidence.
-- The MD (12/10/2026): hand confirmation is workable for now if it is recorded with who
-- and what evidence, and it needs an end (a date or a weekly volume, still to be named).
--
-- This migration:
--   1. status booking_confirmed: the gate has passed, the Plan is ready for release. The
--      release email (gap analysis item E) is a later build; until then IT sends the Plan
--      rendered by msp-plan-render. A Plan that drafts cleanly after its booking was
--      confirmed goes straight to booking_confirmed (msp_pipeline_persist).
--   2. msp_booking_confirm_core: one rule for every route. Evidence is required, identity
--      numbers are refused, a booking is confirmed once per submission, and the hand
--      confirmation end (agent.booking_hand_confirm_until, a date, and
--      agent.booking_hand_confirm_weekly_max, a count) is enforced once the MD names it.
--      It writes booking.confirmed (payload: reference, type, confirmed_by, evidence_ref,
--      confirmed_at, method) and mails sales through the event queue.
--   3. three routes in:
--      a. msp_booking_confirm(reference, type, evidence, note): forge_admin or the SQL editor;
--      b. a one-time link for the sales desk: msp_booking_link_issue (server side, called by
--         the worker for the "Plan drafted" mail once integration.msp_booking_page names the
--         confirmation page), msp_booking_link_inspect and msp_booking_link_confirm (anon,
--         the token is the key; the page acts only when Confirm is pressed, so a mail
--         scanner opening the link changes nothing). Tokens are stored as sha256 only.
--      c. msp_client_booking_choice(reference, choice, note): the signed-in client's three
--         on-screen answers (booked, deposit, call_me). It records client.booking_choice and
--         mails sales; it does not pass the gate (the SOP: "we will confirm it with you").
--   4. msp_pipeline_rerun, msp_triage_correct, msp_triage_cases and msp_triage_close treat
--      booking_confirmed like awaiting_booking; msp_notify_due passes the booking page
--      setting to the worker.

-- 1. Status and event types ----------------------------------------------------------
alter table msp_engagement drop constraint if exists msp_engagement_status_check;
alter table msp_engagement add constraint msp_engagement_status_check
  check (status in ('intake','triage','classifying','drafting','validating','awaiting_booking','booking_confirmed',
                    'omp_queue','approved','released','rejected','archived'));

alter table msp_event drop constraint if exists msp_event_event_type_check;
alter table msp_event add constraint msp_event_event_type_check check (event_type in (
  'intake.submitted', 'plan.drafted', 'plan.draft_failed', 'booking.confirmed', 'client.booking_choice', 'plan.released',
  'quote.requested', 'quote.issued', 'payment.confirmed', 'review.sent', 'review.corrected',
  'review.signed', 'billing.omp_claimable', 'mco.file_filed'));

-- 2. Settings ---------------------------------------------------------------------------
insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('agent.booking_hand_confirm_until', 'pending', 'text', null, null, 'agent',
   'Last day (YYYY-MM-DD) on which sales may confirm a booking or deposit by hand. pending = no end set yet (the MD to name a date or a weekly volume).'),
  ('agent.booking_hand_confirm_weekly_max', '0', 'integer', 0, 10000, 'agent',
   'Most bookings or deposits that may be confirmed by hand in any seven days. 0 = no limit set yet.'),
  ('integration.msp_booking_page', 'pending', 'text', null, null, 'integration',
   'Address of the page on the MSP site where sales confirm a booking from the one-time link (the link adds ?t=<token>). pending = no link in the mail yet.'),
  ('agent.booking_link_days', '30', 'integer', 1, 90, 'agent',
   'Days a one-time booking confirmation link stays valid.')
on conflict (key) do nothing;

insert into msp_env_parameter_history (key, old_value, new_value, changed_by, reason)
select k, null, v, 'migration_074', 'Booking or deposit gate (item D)'
  from (values ('agent.booking_hand_confirm_until', 'pending'), ('agent.booking_hand_confirm_weekly_max', '0'),
               ('integration.msp_booking_page', 'pending'), ('agent.booking_link_days', '30')) as x(k, v)
 where not exists (select 1 from msp_env_parameter_history h where h.key = x.k);

-- 3. One-time links ---------------------------------------------------------------------
create table if not exists msp_booking_link (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id) on delete cascade,
  reference text not null,
  token_hash text not null unique,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by text,
  event_id uuid references msp_event(id) on delete set null
);
comment on table msp_booking_link is 'One-time links for the sales desk to confirm a booking or deposit. Only the sha256 of each token is stored; the token itself lives in the mail.';
alter table msp_booking_link enable row level security;

-- 4. The one rule -------------------------------------------------------------------------
create or replace function msp_booking_confirm_core(p_engagement_id uuid, p_type text, p_evidence_ref text,
                                                    p_confirmed_by text, p_method text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eng msp_engagement%rowtype;
  v_prev msp_event%rowtype;
  v_until text := btrim(coalesce(msp_env_get('agent.booking_hand_confirm_until'), 'pending'));
  v_max int := coalesce(msp_env_get_int('agent.booking_hand_confirm_weekly_max'), 0);
  v_week int;
  v_event uuid;
  v_new_status text;
begin
  select * into v_eng from msp_engagement where id = p_engagement_id for update;
  if v_eng.id is null then raise exception 'no engagement %', p_engagement_id; end if;
  if p_type not in ('booking', 'deposit') then raise exception 'type must be booking or deposit'; end if;
  if length(btrim(coalesce(p_evidence_ref, ''))) < 3 then
    raise exception 'give the evidence: the booking number, deposit reference or invoice number (at least three characters)';
  end if;
  if length(btrim(coalesce(p_confirmed_by, ''))) < 2 then raise exception 'say who is confirming'; end if;
  if (coalesce(p_evidence_ref, '') || ' ' || coalesce(p_note, '') || ' ' || coalesce(p_confirmed_by, '')) ~ '\d{13}' then
    raise exception 'the evidence or note contains a thirteen digit sequence resembling an identity number';
  end if;
  if v_eng.status not in ('intake', 'classifying', 'triage', 'awaiting_booking') then
    raise exception 'engagement % is %; a booking can be confirmed only before the gate has passed', v_eng.reference, v_eng.status;
  end if;
  select * into v_prev from msp_event where engagement_id = v_eng.id and event_type = 'booking.confirmed';
  if v_prev.id is not null then
    raise exception 'the booking for % was already confirmed on % by %', v_eng.reference,
      to_char(v_prev.occurred_at at time zone 'Africa/Johannesburg', 'DD/MM/YYYY HH24:MI'), v_prev.payload->>'confirmed_by';
  end if;

  -- The end of hand confirmation, once the MD names it.
  if v_until !~* '^pending$' and v_until <> '' then
    if v_until !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'agent.booking_hand_confirm_until must be YYYY-MM-DD or pending'; end if;
    if (now() at time zone 'Africa/Johannesburg')::date > v_until::date then
      raise exception 'hand confirmation of bookings ended on %; the booking must reach the system from MCO or the payment provider', v_until;
    end if;
  end if;
  if v_max > 0 then
    select count(*) into v_week from msp_event
     where event_type = 'booking.confirmed' and occurred_at > now() - interval '7 days';
    if v_week >= v_max then
      raise exception 'the weekly limit of % hand-confirmed bookings is reached (agent.booking_hand_confirm_weekly_max)', v_max;
    end if;
  end if;

  insert into msp_event (engagement_id, reference, event_type, payload, delivery, channel)
  values (v_eng.id, v_eng.reference, 'booking.confirmed',
          jsonb_build_object('reference', v_eng.reference, 'type', p_type, 'confirmed_by', btrim(p_confirmed_by),
                             'evidence_ref', btrim(p_evidence_ref), 'confirmed_at', now(), 'method', p_method,
                             'note', nullif(btrim(coalesce(p_note, '')), '')),
          'pending', 'email')
  returning id into v_event;

  v_new_status := case when v_eng.status = 'awaiting_booking' then 'booking_confirmed' else v_eng.status end;
  update msp_engagement set status = v_new_status where id = v_eng.id;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng.id, btrim(p_confirmed_by), 'booking_confirmed',
          jsonb_build_object('event_id', v_event, 'type', p_type, 'evidence_ref', btrim(p_evidence_ref), 'method', p_method,
                             'from_status', v_eng.status, 'status', v_new_status));
  return jsonb_build_object('reference', v_eng.reference, 'event_id', v_event, 'type', p_type, 'status', v_new_status,
                            'gate', case when v_new_status = 'booking_confirmed' then 'passed'
                                         else 'confirmed ahead of drafting; the Plan passes the gate when it drafts cleanly' end);
end;
$$;
revoke execute on function msp_booking_confirm_core(uuid, text, text, text, text, text) from public, anon, authenticated;

-- 5a. Staff ---------------------------------------------------------------------------------
create or replace function msp_booking_confirm(p_reference text, p_type text, p_evidence_ref text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not (msp_caller_is('forge_admin') or session_user in ('postgres', 'supabase_admin')) then
    raise exception 'confirming a booking requires the forge_admin role';
  end if;
  select id into v_id from msp_engagement where reference = p_reference;
  if v_id is null then raise exception 'no engagement %', p_reference; end if;
  return msp_booking_confirm_core(v_id, p_type, p_evidence_ref, msp_staff_actor(), 'staff', p_note);
end;
$$;
revoke execute on function msp_booking_confirm(text, text, text, text) from public, anon;
grant execute on function msp_booking_confirm(text, text, text, text) to authenticated;
comment on function msp_booking_confirm is 'forge_admin or the SQL editor: record that the medicals are booked or the deposit paid (with evidence), passing the booking gate.';

-- 5b. The one-time link -------------------------------------------------------------------------
create or replace function msp_booking_link_issue(p_engagement_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_ref text;
begin
  if btrim(coalesce(msp_env_get('integration.msp_booking_page'), 'pending')) ~* '^(pending)?$' then
    return null;
  end if;
  select reference into v_ref from msp_engagement where id = p_engagement_id;
  if v_ref is null then raise exception 'no engagement %', p_engagement_id; end if;
  v_token := encode(extensions.gen_random_bytes(24), 'hex');
  insert into msp_booking_link (engagement_id, reference, token_hash, expires_at)
  values (p_engagement_id, v_ref, encode(extensions.digest(v_token, 'sha256'), 'hex'),
          now() + make_interval(days => coalesce(msp_env_get_int('agent.booking_link_days'), 30)));
  return v_token;
end;
$$;
revoke execute on function msp_booking_link_issue(uuid) from public, anon, authenticated;

create or replace function msp_booking_link_inspect(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  l msp_booking_link%rowtype;
  v_status text;
  v_company text;
  v_done jsonb;
begin
  select * into l from msp_booking_link where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if l.id is null then return jsonb_build_object('ok', false, 'reason', 'not_recognised'); end if;
  select e.status, c.registered_name into v_status, v_company
    from msp_engagement e join msp_client c on c.id = e.client_id where e.id = l.engagement_id;
  select jsonb_build_object('type', payload->>'type', 'confirmed_by', payload->>'confirmed_by', 'confirmed_at', occurred_at)
    into v_done from msp_event where engagement_id = l.engagement_id and event_type = 'booking.confirmed';
  return jsonb_build_object('ok', v_done is null and l.used_at is null and l.expires_at > now()
                                  and v_status in ('intake', 'classifying', 'triage', 'awaiting_booking'),
    'reason', case when v_done is not null then 'already_confirmed' when l.used_at is not null then 'used'
                   when l.expires_at <= now() then 'expired'
                   when v_status not in ('intake', 'classifying', 'triage', 'awaiting_booking') then 'not_open' else null end,
    'reference', l.reference, 'company', v_company, 'expires_at', l.expires_at, 'confirmed', v_done);
end;
$$;
revoke execute on function msp_booking_link_inspect(text) from public;
grant execute on function msp_booking_link_inspect(text) to anon, authenticated;
comment on function msp_booking_link_inspect is 'For the booking confirmation page: what a one-time link refers to (reference, company) and whether it can still be used. Changes nothing.';

create or replace function msp_booking_link_confirm(p_token text, p_type text, p_evidence_ref text, p_confirmed_by text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  l msp_booking_link%rowtype;
  v_out jsonb;
begin
  select * into l from msp_booking_link
   where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex') for update;
  if l.id is null then raise exception 'this link is not recognised'; end if;
  if l.used_at is not null then raise exception 'this link has already been used'; end if;
  if l.expires_at <= now() then raise exception 'this link has expired; ask IT for a new one'; end if;
  v_out := msp_booking_confirm_core(l.engagement_id, p_type, p_evidence_ref, 'link:' || btrim(coalesce(p_confirmed_by, '')), 'link');
  update msp_booking_link set used_at = now(), used_by = btrim(p_confirmed_by), event_id = (v_out->>'event_id')::uuid where id = l.id;
  return v_out;
end;
$$;
revoke execute on function msp_booking_link_confirm(text, text, text, text) from public;
grant execute on function msp_booking_link_confirm(text, text, text, text) to anon, authenticated;
comment on function msp_booking_link_confirm is 'For the booking confirmation page, on Confirm only: records the booking or deposit through the one-time link, with the name of the person confirming and the evidence.';

-- 5c. The client's answer on screen ---------------------------------------------------------------
create or replace function msp_client_booking_choice(p_reference text, p_choice text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc msp_client_account;
  v_eng msp_engagement%rowtype;
  v_event uuid;
begin
  if p_choice not in ('booked', 'deposit', 'call_me') then raise exception 'choice must be booked, deposit or call_me'; end if;
  if coalesce(p_note, '') ~ '\d{13}' then raise exception 'the note contains a thirteen digit sequence resembling an identity number'; end if;
  v_acc := hsf_account_of(auth.uid());
  if v_acc.id is null then raise exception 'sign in first'; end if;
  select e.* into v_eng from msp_engagement e
   where e.reference = p_reference
     and e.id in (select it.engagement_id from msp_form_access fa join msp_intake it on it.id = fa.used_by_intake
                   where fa.client_account_id = v_acc.id);
  if v_eng.id is null then raise exception 'no submission % on your account', p_reference; end if;
  insert into msp_event (engagement_id, reference, event_type, dedupe_key, payload, delivery, channel)
  values (v_eng.id, v_eng.reference, 'client.booking_choice', p_choice,
          jsonb_build_object('reference', v_eng.reference, 'choice', p_choice, 'client_account_id', v_acc.id,
                             'note', nullif(left(btrim(coalesce(p_note, '')), 500), ''), 'chosen_at', now()),
          'pending', 'email')
  on conflict (engagement_id, event_type, dedupe_key) do nothing
  returning id into v_event;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_eng.id, 'client:' || v_acc.id, 'client_booking_choice',
          jsonb_build_object('choice', p_choice, 'event_id', v_event, 'repeat', v_event is null));
  return jsonb_build_object('reference', v_eng.reference, 'choice', p_choice, 'recorded', true,
                            'sales_told', v_event is not null);
end;
$$;
revoke execute on function msp_client_booking_choice(text, text, text) from public, anon;
grant execute on function msp_client_booking_choice(text, text, text) to authenticated;
comment on function msp_client_booking_choice is 'The signed-in client''s answer on the after-submit screen: booked, deposit or call_me, for a submission on their own account. Sales are mailed once per answer; the gate passes only when sales confirm.';

-- 6. Functions brought in line -------------------------------------------------------------------------
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
    -- SOP: "drafted moves straight to released when the booking is already confirmed".
    -- Release itself is a later build, so the gate's pass is recorded as booking_confirmed.
    update msp_engagement
       set status = case when exists (select 1 from msp_event b where b.engagement_id = p_engagement_id
                                        and b.event_type = 'booking.confirmed')
                         then 'booking_confirmed' else 'awaiting_booking' end
     where id = p_engagement_id;
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
          jsonb_build_object('outcome', v_outcome, 'status', (select status from msp_engagement where id = p_engagement_id), 'model_used', v_model,
                             'defects', jsonb_array_length(coalesce(p_result->'defects', '[]'::jsonb))));
  return jsonb_build_object('status', (select status from msp_engagement where id = p_engagement_id),
                            'plan_id', v_compose);
end;
$$;
revoke execute on function msp_pipeline_persist(uuid, jsonb) from public, anon, authenticated;

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
      'booking_page', msp_env_get('integration.msp_booking_page'),
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
  elsif v_status not in ('triage', 'awaiting_booking', 'booking_confirmed') then
    raise exception 'engagement % is %; only a submission in triage, a Plan awaiting or past the booking gate, or an undecided Plan in the review queue can be redrafted', p_reference, v_status;
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
  if v_eng.status not in ('triage', 'awaiting_booking', 'booking_confirmed') then
    raise exception 'engagement % is %; only a submission in triage or a Plan awaiting or past the booking gate can be corrected', p_reference, v_eng.status;
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
   where e.status in ('triage', 'awaiting_booking', 'booking_confirmed'));
end;
$$;
revoke execute on function msp_triage_cases() from public, anon;
grant execute on function msp_triage_cases() to authenticated;

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
  if v_eng.status not in ('triage', 'awaiting_booking', 'booking_confirmed', 'intake') then
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

notify pgrst, 'reload schema';
