-- CNC MSP FORGE | AGT-SCH-01 v1.0.0 | Live scheduling from the parameter store 15/08/2026
-- The monthly framework audit now runs on a real schedule, and the schedule is
-- read from the parameter store rather than written into a cron string by hand.
-- Change agent.monthly_audit_day and the job moves. Nothing is redeployed.
--
-- The audit itself is pure SQL and needs no network and no secret, so it is
-- scheduled directly. The assistant assisted watch needs an outbound call and
-- therefore a key, so it is scheduled only when Care Net has placed that key in
-- the vault. Until then the function says so plainly and schedules nothing.

-- Model prices, so the call ledger can be priced without a redeploy when rates
-- move. United States dollars per million tokens.
insert into msp_env_parameter (key, value, value_type, category, description) values
  ('ai.price_table_json',
   '{"claude-opus-5":{"in":5.00,"out":25.00},"claude-sonnet-5":{"in":3.00,"out":15.00},"claude-haiku-4-5":{"in":1.00,"out":5.00}}',
   'text', 'ai',
   'Published token prices in United States dollars per million tokens, used to price the call ledger. Update here when rates change.'),
  ('ai.actions_enabled',
   'explain_plan,industry_brief,triage_other,monthly_watch',
   'text', 'ai',
   'Comma separated list of assistant actions the connection will serve. Remove one to switch it off without a redeploy.')
on conflict (key) do nothing;

-- Rebuild the cron entry for the monthly framework audit from the parameters.
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
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'rescheduling the agent requires the forge_admin role';
  end if;
  v_expr := format('0 %s %s * *', v_hour, v_day);

  perform cron.unschedule('msp_monthly_audit')
    where exists (select 1 from cron.job where jobname = 'msp_monthly_audit');

  perform cron.schedule('msp_monthly_audit', v_expr, 'select msp_kernel_monthly_audit();');

  insert into msp_audit (actor, event_type, event_detail)
  values (coalesce(auth.jwt() ->> 'email', auth.role(), 'msp_agent_reschedule'),
          'agent_rescheduled',
          jsonb_build_object('job', 'msp_monthly_audit', 'schedule', v_expr));

  return jsonb_build_object('job', 'msp_monthly_audit', 'schedule', v_expr,
                            'day', v_day, 'hour_utc', v_hour);
end;
$$;
comment on function msp_agent_reschedule is
  'Rebuilds the monthly audit cron entry from agent.monthly_audit_day and agent.monthly_audit_hour_utc. Called automatically whenever either parameter changes.';

-- Make the schedule parameters genuinely live: changing one moves the job in the
-- same call. A scheduling failure is recorded but never blocks the parameter
-- change itself, because the stored configuration is the source of truth and the
-- schedule can always be rebuilt from it.
create or replace function msp_env_after_change(p_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_key in ('agent.monthly_audit_day', 'agent.monthly_audit_hour_utc') then
    begin
      perform msp_agent_reschedule();
    exception when others then
      insert into msp_audit (actor, event_type, event_detail)
      values ('msp_env_after_change', 'agent_reschedule_failed',
              jsonb_build_object('key', p_key, 'error', sqlerrm));
    end;
  end if;
end;
$$;

-- msp_env_set gains the one line that calls the hook. Everything else is as it
-- was in migration 034.
create or replace function msp_env_set(p_key text, p_value text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row msp_env_parameter%rowtype;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.role(), 'unknown');
  v_num numeric;
begin
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'changing a runtime parameter requires the forge_admin role';
  end if;

  select * into v_row from msp_env_parameter where key = p_key;
  if not found then
    raise exception 'unknown parameter %. Parameters are declared by migration, not created at runtime', p_key;
  end if;

  if v_row.value_type = 'integer' then
    if p_value !~ '^-?\d+$' then
      raise exception 'parameter % expects an integer, got %', p_key, p_value;
    end if;
    v_num := p_value::numeric;
  elsif v_row.value_type = 'decimal' then
    if p_value !~ '^-?\d+(\.\d+)?$' then
      raise exception 'parameter % expects a decimal, got %', p_key, p_value;
    end if;
    v_num := p_value::numeric;
  elsif v_row.value_type = 'boolean' then
    if lower(p_value) not in ('true','false') then
      raise exception 'parameter % expects true or false, got %', p_key, p_value;
    end if;
  elsif v_row.value_type = 'date' then
    begin
      perform p_value::date;
    exception when others then
      raise exception 'parameter % expects a date in YYYY-MM-DD form, got %', p_key, p_value;
    end;
  elsif v_row.value_type = 'enum' then
    if v_row.allowed_values is null or not (p_value = any(v_row.allowed_values)) then
      raise exception 'parameter % expects one of %, got %',
        p_key, array_to_string(v_row.allowed_values, ', '), p_value;
    end if;
  end if;

  if v_num is not null then
    if v_row.min_value is not null and v_num < v_row.min_value then
      raise exception 'parameter % has a floor of %, got %', p_key, v_row.min_value, p_value;
    end if;
    if v_row.max_value is not null and v_num > v_row.max_value then
      raise exception 'parameter % has a ceiling of %, got %', p_key, v_row.max_value, p_value;
    end if;
  end if;

  update msp_env_parameter
     set value = p_value, updated_by = v_actor, updated_at = now()
   where key = p_key;

  insert into msp_env_parameter_history (key, old_value, new_value, changed_by, reason)
  values (p_key, v_row.value, p_value, v_actor, p_reason);

  insert into msp_audit (actor, event_type, event_detail)
  values (v_actor, 'env_parameter_change',
          jsonb_build_object('key', p_key, 'from', v_row.value, 'to', p_value, 'reason', p_reason));

  perform msp_env_after_change(p_key);

  return jsonb_build_object('key', p_key, 'old_value', v_row.value, 'new_value', p_value,
                            'changed_by', v_actor, 'changed_at', now());
end;
$$;

-- What is actually scheduled right now. Readable by any forge role so the admin
-- page can show the truth rather than a claim.
create or replace function msp_agent_schedule_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(msp_any_forge_role(), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'reading the agent schedule requires a forge role';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'job', jobname, 'schedule', schedule, 'command', command, 'active', active)), '[]'::jsonb)
            from cron.job where jobname like 'msp\_%');
end;
$$;

grant execute on function msp_agent_reschedule(), msp_agent_schedule_status() to authenticated;

-- Put the audit on the schedule the parameters currently describe.
select cron.schedule('msp_monthly_audit', '0 2 1 * *', 'select msp_kernel_monthly_audit();');
