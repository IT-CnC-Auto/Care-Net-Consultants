-- CNC MSP FORGE | AGT-RUN-01 v1.0.0 | Submissions no longer wait for someone to look 08/10/2026
-- Cassandra's trial-run note (08/10/2026): a finished assessment lands in the
-- database and nothing else happens. No mail to sales, no draft, nothing for the
-- practitioner. The drafting pipeline only ran from a terminal.
--
-- This migration is the database half of the fix. The other half is the edge
-- function msp-intake-worker, which pg_cron calls every five minutes:
--   1. sales are told about every new submission (reference, company, industry,
--      clean or triage), once per engagement;
--   2. every clean submission at status 'intake' is drafted by the same
--      deterministic pipeline (agent/pipeline.js, no AI in the drafting path),
--      written stage by stage to msp_draft, and either queued for the
--      practitioner (msp_omp_review, status omp_queue) or halted for a person
--      (status triage, reasons in msp_defect); sales are told the outcome;
--   3. the practitioner is told when a Plan enters the queue, and practitioner
--      and sales are told once when it has waited longer than the review window.
--      Practitioner mail stays switched off until integration.msp_notify_omp_to
--      carries a real address: no practitioner is nominated yet.
--
-- Rules
--   * One mail per engagement per kind, ever (msp_notification, unique). A mail
--     that fails is not recorded and is retried on the next run.
--   * Engagements that existed two days before this migration are recorded as
--     already announced, so the first run does not mail the past.
--   * The worker authenticates with a key that lives only in Vault
--     (msp_worker_key). pg_cron reads it from Vault; the worker checks it through
--     msp_worker_key_check. It never appears in this file, in the parameter
--     store, or in the function's settings.
--   * Every function here is server side only (service role), except
--     msp_intake_worker_kick, which a forge_admin may call to run the worker now.
--   * No clinical data anywhere: the intake holds roles, hazards and exposure
--     levels, never a person's results.

create extension if not exists pg_net with schema extensions;

-- 1. Settings, editable from settings.html like every other parameter ----------
insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('integration.msp_notify_sales_to', 'salesdesk@carenetconsultants.co.za', 'text', null, null, 'integration',
   'Who is told about every new Medical Surveillance Plan submission and its drafting outcome. Comma separated.'),
  ('integration.msp_notify_sales_cc', 'it@carenetconsultants.co.za', 'text', null, null, 'integration',
   'Copy on the sales notifications. IT during the trial runs; set to pending to send no copy.'),
  ('integration.msp_notify_omp_to', 'pending', 'text', null, null, 'integration',
   'The practitioner who reviews and signs Plans. While pending, no practitioner mail is sent and the review clock does not start.'),
  ('integration.msp_worker_url', 'https://pboebfnujzffgwctsplw.supabase.co/functions/v1/msp-intake-worker', 'text', null, null, 'integration',
   'Address of the msp-intake-worker edge function that pg_cron calls.'),
  ('agent.pipeline_auto_run', 'true', 'boolean', null, null, 'agent',
   'Draft every clean submission automatically. Set to false to stop drafting; notifications still go out.'),
  ('agent.pipeline_batch_size', '3', 'integer', 1, 20, 'agent',
   'How many submissions one worker run drafts at most.'),
  ('agent.omp_review_days', '5', 'integer', 1, 60, 'agent',
   'Calendar days a practitioner has to review a Plan, counted from the practitioner notification, before practitioner and sales are reminded once.')
on conflict (key) do nothing;

-- 2. Pipeline bookkeeping on the engagement -------------------------------------
alter table msp_engagement add column if not exists pipeline_claimed_at timestamptz;
alter table msp_engagement add column if not exists pipeline_attempts int not null default 0;
comment on column msp_engagement.pipeline_claimed_at is 'When msp-intake-worker took this engagement for drafting. A claim older than 30 minutes is treated as abandoned and retried.';
comment on column msp_engagement.pipeline_attempts is 'Drafting attempts that ended in an error. After three the engagement goes to triage.';

-- 3. The notification register ---------------------------------------------------
create table if not exists msp_notification (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id) on delete cascade,
  kind text not null check (kind in ('intake_received','pipeline_result','omp_review_requested','omp_review_overdue')),
  recipients text not null,
  subject text not null,
  status text not null default 'sent' check (status in ('sent','bootstrap')),
  created_at timestamptz not null default now(),
  unique (engagement_id, kind)
);
comment on table msp_notification is 'One row per engagement per notification kind, written after the mail was accepted. Bootstrap rows mark engagements that predate the automation.';
alter table msp_notification enable row level security;
revoke all on msp_notification from public, anon, authenticated;
create policy msp_notification_read on msp_notification
  for select to authenticated using (msp_has_role('forge_admin'));

-- Do not announce the past.
insert into msp_notification (engagement_id, kind, recipients, subject, status)
select e.id, k.kind, 'bootstrap', 'Existed before the automation (migration 066)', 'bootstrap'
  from msp_engagement e
 cross join (values ('intake_received'), ('pipeline_result')) as k(kind)
 where e.created_at < now() - interval '2 days'
on conflict (engagement_id, kind) do nothing;
-- Plans already waiting for a practitioner (the August Horizon sample) are not
-- re-announced when a practitioner is named.
insert into msp_notification (engagement_id, kind, recipients, subject, status)
select e.id, k.kind, 'bootstrap', 'Existed before the automation (migration 066)', 'bootstrap'
  from msp_engagement e
 cross join (values ('omp_review_requested'), ('omp_review_overdue')) as k(kind)
 where e.status = 'omp_queue'
on conflict (engagement_id, kind) do nothing;

-- 4. The worker key, generated inside the database and kept in Vault ----------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'msp_worker_key') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(24), 'hex'), 'msp_worker_key',
      'Shared key between pg_cron and the msp-intake-worker edge function (migration 066).');
  end if;
end $$;

create or replace function msp_worker_key_check(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(length(p_key) >= 32
     and p_key = (select decrypted_secret from vault.decrypted_secrets where name = 'msp_worker_key'), false);
$$;
revoke execute on function msp_worker_key_check(text) from public, anon, authenticated;
comment on function msp_worker_key_check is 'Server side only: true when the key matches the Vault secret msp_worker_key.';

-- 5. The kernel, in the shape agent/pipeline.js reads ---------------------------
-- One industry (the one the submission's area of work belongs to), its areas of
-- work, their roles and role hazards; every hazard, instrument and protocol.
-- An instrument is reported 'verified' only when it is verified AND carries no
-- currency hold, the same rule as kernel_citable_instrument.
create or replace function msp_pipeline_kernel(p_subindustry_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ind uuid;
begin
  select s.industry_id into v_ind from msp_subindustry s where s.code = p_subindustry_code;
  if v_ind is null then
    return null;
  end if;
  return jsonb_build_object(
    'industries', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'code', i.code, 'name', i.name,
                     'regulatory_regime', i.regulatory_regime)), '[]') from msp_industry i where i.id = v_ind),
    'subindustries', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'name', s.name,
                     'industry_id', s.industry_id, 'selectable', s.selectable) order by s.code), '[]')
                     from msp_subindustry s where s.industry_id = v_ind),
    'roles', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'subindustry_id', r.subindustry_id,
                     'title', r.title, 'duties_summary', r.duties_summary,
                     'inherent_physical_demands', r.inherent_physical_demands,
                     'inherent_sensory_cognitive_demands', r.inherent_sensory_cognitive_demands,
                     'statutory_competency_requirement', r.statutory_competency_requirement) order by r.title), '[]')
                     from msp_job_role r join msp_subindustry s on s.id = r.subindustry_id where s.industry_id = v_ind),
    'job_hazards', (select coalesce(jsonb_agg(jsonb_build_object('job_role_id', jh.job_role_id, 'hazard_id', jh.hazard_id,
                     'typical_exposure_rating', jh.typical_exposure_rating, 'rationale', jh.rationale)), '[]')
                     from msp_job_hazard jh join msp_job_role r on r.id = jh.job_role_id
                     join msp_subindustry s on s.id = r.subindustry_id where s.industry_id = v_ind),
    'hazards', (select coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'code', h.code, 'name', h.name,
                     'category', h.category, 'oel_value', h.oel_value, 'oel_unit', h.oel_unit, 'oel_basis', h.oel_basis,
                     'oel_instrument', h.oel_instrument, 'verification_status', h.verification_status) order by h.code), '[]')
                     from msp_hazard h),
    'instruments', (select coalesce(jsonb_agg(jsonb_build_object('id', li.id, 'short_name', li.short_name,
                     'full_citation', li.full_citation,
                     'status', case when li.status = 'verified'
                                     and not exists (select 1 from msp_instrument_currency_hold ch where ch.instrument_id = li.id)
                                    then 'verified'
                                    when li.status = 'verified' then 'currency_hold'
                                    else li.status end) order by li.short_name), '[]')
                     from msp_legal_instrument li),
    'industry_instruments', (select coalesce(jsonb_agg(jsonb_build_object('industry_id', ii.industry_id,
                     'instrument_id', ii.instrument_id, 'applicability_note', ii.applicability_note)), '[]')
                     from msp_industry_instrument ii where ii.industry_id = v_ind),
    'protocols', (select coalesce(jsonb_agg(jsonb_build_object('id', tp.id, 'hazard_id', tp.hazard_id,
                     'test_name', tp.test_name, 'test_type', tp.test_type, 'baseline_required', tp.baseline_required,
                     'periodic_interval_months', tp.periodic_interval_months, 'exit_required', tp.exit_required,
                     'biological_reference', tp.biological_reference, 'legal_basis_id', tp.legal_basis_id)
                     order by tp.test_name), '[]')
                     from msp_test_protocol tp),
    'kernel_release', (select v.semver from msp_kernel_version v order by v.released_on desc, v.semver desc limit 1)
  );
end;
$$;
revoke execute on function msp_pipeline_kernel(text) from public, anon, authenticated;
comment on function msp_pipeline_kernel is 'Server side only: the kernel slice agent/pipeline.js needs for one area of work, citable instruments only.';

-- 6. Claim submissions for drafting ----------------------------------------------
create or replace function msp_pipeline_claim(p_limit int default 3)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_out jsonb := '[]'::jsonb;
  r record;
begin
  for r in
    select e.id, e.reference, i.id as intake_id, i.raw_payload, i.received_at
      from msp_engagement e
      join lateral (select * from msp_intake x where x.engagement_id = e.id
                     order by x.received_at desc limit 1) i on true
     where i.validation_status = 'valid'
       and (e.status = 'intake'
            or (e.status = 'classifying' and e.pipeline_claimed_at < now() - interval '30 minutes'))
     order by e.created_at
     limit greatest(1, least(coalesce(p_limit, 3), 20))
     for update of e skip locked
  loop
    update msp_engagement set status = 'classifying', pipeline_claimed_at = now() where id = r.id;
    insert into msp_audit (engagement_id, actor, event_type, event_detail)
    values (r.id, 'msp-intake-worker', 'pipeline_claimed', jsonb_build_object('intake_id', r.intake_id));
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'engagement_id', r.id, 'reference', r.reference, 'intake_id', r.intake_id,
      'received_at', r.received_at, 'intake', r.raw_payload));
  end loop;
  return v_out;
end;
$$;
revoke execute on function msp_pipeline_claim(int) from public, anon, authenticated;
comment on function msp_pipeline_claim is 'Server side only: takes up to p_limit clean submissions at status intake (or abandoned claims) for drafting.';

-- 7. Persist one pipeline run -----------------------------------------------------
-- p_result: { outcome: queued | triage | error,
--             model_used, stages: { classify, frame, profile, prescribe, compose, validate },
--             defects: [ { stage, defect_code, blocking, detail } ], error }
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
  v_review uuid;
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

  if v_outcome = 'queued' then
    if v_compose is null then raise exception 'a queued result must carry the compose stage'; end if;
    insert into msp_omp_review (engagement_id, draft_id) values (p_engagement_id, v_compose) returning id into v_review;
    update msp_engagement set status = 'omp_queue' where id = p_engagement_id;
  else
    update msp_engagement set status = 'triage' where id = p_engagement_id;
  end if;

  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (p_engagement_id, 'msp-intake-worker', 'pipeline_completed',
          jsonb_build_object('outcome', v_outcome, 'review_id', v_review, 'model_used', v_model,
                             'defects', jsonb_array_length(coalesce(p_result->'defects', '[]'::jsonb))));
  return jsonb_build_object('status', case when v_outcome = 'queued' then 'omp_queue' else 'triage' end,
                            'review_id', v_review);
end;
$$;
revoke execute on function msp_pipeline_persist(uuid, jsonb) from public, anon, authenticated;
comment on function msp_pipeline_persist is 'Server side only: writes one pipeline run (stage drafts, defects, review queue entry, status) for a claimed engagement.';

-- 8. What needs announcing ---------------------------------------------------------
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
      'omp_to', msp_env_get('integration.msp_notify_omp_to'),
      'site_url', msp_env_get('integration.site_base_url'),
      'auto_run', coalesce(msp_env_get_bool('agent.pipeline_auto_run'), true),
      'batch', coalesce(msp_env_get_int('agent.pipeline_batch_size'), 3),
      'review_days', v_days),
    'intake_received', (select coalesce(jsonb_agg(msp_notify_engagement(e.id) order by e.created_at), '[]')
        from msp_engagement e
       where exists (select 1 from msp_intake i where i.engagement_id = e.id)
         and not exists (select 1 from msp_notification n where n.engagement_id = e.id and n.kind = 'intake_received')),
    'pipeline_result', (select coalesce(jsonb_agg(msp_notify_engagement(e.id) order by e.created_at), '[]')
        from msp_engagement e
       where e.status in ('omp_queue', 'triage')
         and exists (select 1 from msp_audit a where a.engagement_id = e.id and a.event_type in ('pipeline_completed','pipeline_error'))
         and not exists (select 1 from msp_notification n where n.engagement_id = e.id and n.kind = 'pipeline_result')),
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
comment on function msp_notify_due is 'Server side only: settings plus every engagement owed a notification, by kind.';

create or replace function msp_notify_record(p_engagement_id uuid, p_kind text, p_recipients text, p_subject text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into msp_notification (engagement_id, kind, recipients, subject)
  values (p_engagement_id, p_kind, left(p_recipients, 500), left(p_subject, 300))
  on conflict (engagement_id, kind) do nothing;
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (p_engagement_id, 'msp-intake-worker', 'notification_sent',
          jsonb_build_object('kind', p_kind, 'recipients', left(p_recipients, 500)));
end;
$$;
revoke execute on function msp_notify_record(uuid, text, text, text) from public, anon, authenticated;

-- Send a halted submission back for drafting once its cause is fixed. The old
-- stage drafts and defects stay as the record of the earlier attempt.
create or replace function msp_pipeline_rerun(p_reference text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_status text;
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'sending a Plan back for drafting requires the forge_admin role';
  end if;
  select id, status into v_id, v_status from msp_engagement where reference = p_reference for update;
  if v_id is null then raise exception 'no engagement %', p_reference; end if;
  if v_status <> 'triage' then
    raise exception 'engagement % is %; only a submission in triage can be sent back for drafting', p_reference, v_status;
  end if;
  update msp_intake set validation_status = 'valid'
   where id = (select id from msp_intake where engagement_id = v_id order by received_at desc limit 1);
  update msp_engagement set status = 'intake', pipeline_attempts = 0, pipeline_claimed_at = null where id = v_id;
  delete from msp_notification where engagement_id = v_id and kind = 'pipeline_result';
  insert into msp_audit (engagement_id, actor, event_type, event_detail)
  values (v_id, 'admin', 'pipeline_rerun_requested', jsonb_build_object('from_status', v_status));
  return jsonb_build_object('reference', p_reference, 'status', 'intake');
end;
$$;
revoke execute on function msp_pipeline_rerun(text) from public, anon;
grant execute on function msp_pipeline_rerun(text) to authenticated;
comment on function msp_pipeline_rerun is 'forge_admin: send a submission in triage back for automatic drafting after its cause is fixed. The next worker run drafts it and sales get a new outcome notice.';

-- 9. Run the worker: on a schedule, or now ------------------------------------------
create or replace function msp_intake_worker_call(p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := msp_env_get('integration.msp_worker_url');
  v_key text := (select decrypted_secret from vault.decrypted_secrets where name = 'msp_worker_key');
begin
  if v_url is null or v_key is null then
    raise exception 'msp-intake-worker is not configured (url or Vault key missing)';
  end if;
  return net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-msp-worker-key', v_key),
    body := coalesce(p_body, '{}'::jsonb),
    timeout_milliseconds := 120000);
end;
$$;
revoke execute on function msp_intake_worker_call(jsonb) from public, anon, authenticated;

-- A forge_admin can press "run now" (a button in the staff tool, when Cassandra adds one).
create or replace function msp_intake_worker_kick()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not msp_caller_is('forge_admin') then
    raise exception 'running the intake worker requires the forge_admin role';
  end if;
  return jsonb_build_object('request_id', msp_intake_worker_call('{}'::jsonb));
end;
$$;
revoke execute on function msp_intake_worker_kick() from public, anon;
grant execute on function msp_intake_worker_kick() to authenticated;
comment on function msp_intake_worker_kick is 'forge_admin: run msp-intake-worker now instead of waiting for the five minute schedule. Returns the pg_net request id.';

do $$
begin
  if exists (select 1 from cron.job where jobname = 'msp-intake-worker') then
    perform cron.unschedule('msp-intake-worker');
  end if;
  perform cron.schedule('msp-intake-worker', '*/5 * * * *', 'select msp_intake_worker_call(''{}''::jsonb);');
end $$;

notify pgrst, 'reload schema';
