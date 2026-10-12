-- CNC MSP FORGE | AGT-RUN-01 v1.1.0 | Redraft a queued Plan after a pipeline fix 12/10/2026
-- The drafting pipeline (agent/pipeline.js v1.0.2) now prints "Not measured" for an
-- exposure row with no measured level, where it printed "undefined" (found in
-- CNC-MSP-2026-1008-001). Plans already drafted with the old text sit in the
-- practitioner queue, and msp_pipeline_rerun only accepted submissions in triage.
--
-- This migration:
--   1. lets msp_pipeline_rerun also redraft a Plan in omp_queue whose practitioner
--      review is still undecided. The undecided review row is removed (it carries no
--      decision, name or signature); the earlier stage drafts stay as the record.
--      A Plan the practitioner has decided on is never touched.
--   2. accepts the dashboard SQL editor (the database owner) as well as a forge_admin
--      session, for msp_pipeline_rerun and msp_intake_worker_kick, so IT can run them
--      without a signed-in staff session. The service role is accepted as before.
-- Nothing else changes; the next msp-intake-worker run drafts the Plan again and
-- sends a fresh "Plan drafted" notice to sales.

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
  elsif v_status <> 'triage' then
    raise exception 'engagement % is %; only a submission in triage or an undecided Plan in the review queue can be redrafted', p_reference, v_status;
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
comment on function msp_pipeline_rerun is 'forge_admin or the SQL editor: send a submission in triage, or an undecided Plan in the review queue, back for automatic drafting. The next worker run drafts it and sales get a new outcome notice.';

create or replace function msp_intake_worker_kick()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (msp_caller_is('forge_admin') or session_user in ('postgres', 'supabase_admin')) then
    raise exception 'running the intake worker requires the forge_admin role';
  end if;
  return jsonb_build_object('request_id', msp_intake_worker_call('{}'::jsonb));
end;
$$;
revoke execute on function msp_intake_worker_kick() from public, anon;
grant execute on function msp_intake_worker_kick() to authenticated;

notify pgrst, 'reload schema';
