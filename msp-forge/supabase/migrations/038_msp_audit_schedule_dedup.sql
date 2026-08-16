-- CNC MSP FORGE | AGT-SCH-02 v1.0.0 | One audit job, not two 15/08/2026
-- Migration 035 created the parameter driven job msp_monthly_audit without
-- checking for the job an earlier session had already created by hand,
-- msp-kernel-monthly-audit. Both were live, so the framework audit would have
-- run twice on the first of the month, at 02:00 and again at 06:00, writing two
-- rows to msp_kernel_agent_run. Harmless but wrong, and only one of them
-- answered to the parameters.
--
-- The parameter driven job is kept. The hand made one is removed here, and
-- msp_agent_reschedule now clears any legacy name as well as its own, so a
-- reschedule can never leave a second job behind.

select cron.unschedule('msp-kernel-monthly-audit')
 where exists (select 1 from cron.job where jobname = 'msp-kernel-monthly-audit');

create or replace function msp_agent_reschedule()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day  int := msp_env_get_int('agent.monthly_audit_day');
  v_hour int := msp_env_get_int('agent.monthly_audit_hour_utc');
  v_expr text;
  v_legacy text;
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'rescheduling the agent requires the forge_admin role';
  end if;
  v_expr := format('0 %s %s * *', v_hour, v_day);

  -- Clear every audit job this system has ever used, by any name, so a
  -- reschedule leaves exactly one behind.
  for v_legacy in
    select jobname from cron.job
     where jobname in ('msp_monthly_audit', 'msp-kernel-monthly-audit')
  loop
    perform cron.unschedule(v_legacy);
  end loop;

  perform cron.schedule('msp_monthly_audit', v_expr, 'select msp_kernel_monthly_audit();');

  insert into msp_audit (actor, event_type, event_detail)
  values (coalesce(auth.jwt() ->> 'email', auth.role(), 'msp_agent_reschedule'),
          'agent_rescheduled',
          jsonb_build_object('job', 'msp_monthly_audit', 'schedule', v_expr));

  return jsonb_build_object('job', 'msp_monthly_audit', 'schedule', v_expr,
                            'day', v_day, 'hour_utc', v_hour);
end;
$$;

revoke all on function msp_agent_reschedule() from public, anon;
grant execute on function msp_agent_reschedule() to authenticated;
