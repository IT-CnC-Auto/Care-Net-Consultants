-- CNC MSP FORGE | AGT-RUN-01 v1.0.2 | Blind copy on MSP notifications 12/10/2026
-- IT, 12/10/2026: the sales notices now copy the Sales Director and the Managing
-- Director in Cc (parameter changed in the SQL editor the same day, history rows
-- written). IT still needs every mail, without being named on it.
--
-- This migration:
--   1. adds integration.msp_notify_sales_bcc (it@ by default; pending = none), with a
--      history row, and brings the Cc description up to date;
--   2. passes it to the worker through msp_notify_due (settings.sales_bcc).
-- msp-intake-worker v1.0.2 sends the Bcc on every mail, sales and practitioner, and
-- records it in msp_notification.recipients after a " | bcc " marker. An older worker
-- ignores the new setting, so the order of migration and deploy does not matter.

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('integration.msp_notify_sales_bcc', 'it@carenetconsultants.co.za', 'text', null, null, 'integration',
   'Blind copy on every Medical Surveillance Plan notification, sales and practitioner. IT by default; set to pending to send none. Comma separated.')
on conflict (key) do nothing;

insert into msp_env_parameter_history (key, old_value, new_value, changed_by, reason)
select 'integration.msp_notify_sales_bcc', null, 'it@carenetconsultants.co.za', 'migration_068', 'IT in blind copy on MSP notifications'
 where not exists (select 1 from msp_env_parameter_history where key = 'integration.msp_notify_sales_bcc');

update msp_env_parameter
   set description = 'Copy on the sales notifications (Sales Director and Managing Director from 12/10/2026). Comma separated; set to pending to send no copy.'
 where key = 'integration.msp_notify_sales_cc';

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

notify pgrst, 'reload schema';
