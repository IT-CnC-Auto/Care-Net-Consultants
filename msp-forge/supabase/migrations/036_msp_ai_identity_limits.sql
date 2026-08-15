-- CNC MSP FORGE | AI-02 v1.0.0 | Caller identity and rate limits for the assistant 15/08/2026
-- The connection runs on the service context so it can read the parameter store
-- and write the ledger, which means the database can no longer see who asked.
-- The connection therefore passes the real caller through, and the ledger records
-- that person rather than the service. Rate limits are per caller and per hour,
-- and both ceilings are parameters like everything else.

insert into msp_env_parameter (key, value, value_type, min_value, max_value, category, description) values
  ('ai.client_hourly_limit', '20', 'integer', 0, 500, 'ai',
   'Assistant calls one client account may make in an hour. Zero switches client access off entirely.'),
  ('ai.staff_hourly_limit', '120', 'integer', 0, 5000, 'ai',
   'Assistant calls one member of staff may make in an hour.')
on conflict (key) do nothing;

-- How many calls this caller has already made in the window.
create or replace function msp_ai_recent_calls(p_actor text, p_minutes int default 60)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from msp_ai_call_log
   where actor = p_actor
     and outcome in ('ok','refused','error')
     and called_at >= now() - make_interval(mins => p_minutes);
$$;

-- The ledger write, now carrying the real caller. The previous signature is
-- dropped rather than overloaded so there is never any doubt which one ran.
drop function if exists msp_ai_log(text, text, text, text, text, integer, integer, numeric, integer, uuid, text, text);

create or replace function msp_ai_log(
  p_action text, p_model text, p_effort text, p_prompt_version text,
  p_outcome text, p_actor text,
  p_input_tokens integer default null, p_output_tokens integer default null,
  p_cost_usd numeric default null, p_latency_ms integer default null,
  p_engagement_id uuid default null, p_industry_code text default null,
  p_error text default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'logging an assistant call requires the forge_agent or forge_admin role';
  end if;
  insert into msp_ai_call_log (action, model, effort, prompt_version, outcome,
    input_tokens, output_tokens, cost_usd, latency_ms, engagement_id, industry_code,
    actor, error_detail)
  values (p_action, p_model, p_effort, p_prompt_version, p_outcome,
    p_input_tokens, p_output_tokens, p_cost_usd, p_latency_ms, p_engagement_id, p_industry_code,
    coalesce(nullif(p_actor, ''), auth.jwt() ->> 'email', auth.role(), 'assistant'), p_error)
  returning id into v_id;
  return v_id;
end;
$$;
comment on function msp_ai_log is
  'Writes one row to the assistant call ledger. The caller is passed in explicitly because the connection runs on the service context and would otherwise record itself.';

-- Is this Supabase Auth user a client account we recognise, and which one.
create or replace function msp_ai_client_identity(p_auth_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'resolving a client identity requires the forge_agent or forge_admin role';
  end if;
  select jsonb_build_object('found', true, 'account_id', id, 'company_name', company_name,
                            'sla_status', sla_status)
    into v
    from msp_client_account where auth_user_id = p_auth_user_id;
  return coalesce(v, jsonb_build_object('found', false));
end;
$$;

grant execute on function msp_ai_recent_calls(text, int), msp_ai_client_identity(uuid) to authenticated;

-- A read only view of the ledger for the admin page: this month, by action.
create or replace function msp_ai_usage_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(msp_has_role('forge_admin'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'the assistant usage summary requires the forge_admin role';
  end if;
  return jsonb_build_object(
    'month_spend_usd', msp_ai_month_spend_usd(),
    'ceiling_usd', msp_env_get_numeric('ai.monthly_cost_ceiling_usd'),
    'by_action', (select coalesce(jsonb_agg(jsonb_build_object(
        'action', action, 'calls', calls, 'cost_usd', cost_usd, 'ok', ok_calls)
        order by cost_usd desc), '[]'::jsonb)
      from (select action, count(*) as calls, coalesce(sum(cost_usd), 0) as cost_usd,
                   count(*) filter (where outcome = 'ok') as ok_calls
              from msp_ai_call_log
             where called_at >= date_trunc('month', now())
             group by action) t),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object(
        'at', called_at, 'action', action, 'actor', actor, 'outcome', outcome,
        'cost_usd', cost_usd, 'latency_ms', latency_ms)
        order by called_at desc), '[]'::jsonb)
      from (select * from msp_ai_call_log order by called_at desc limit 25) r));
end;
$$;

grant execute on function msp_ai_usage_summary() to authenticated;
