-- CNC MSP FORGE | ENV-02 v1.0.0 | Grant lockdown on the parameter store and the assistant 15/08/2026
-- Postgres grants execute on a new function to PUBLIC by default, which means the
-- anonymous web role could call every helper added in migrations 034 to 036. The
-- guarded ones would have refused, but the small readers had no guard because
-- they are internal plumbing. The advisor flagged all of them and it is right.
--
-- The rule applied here: a function is reachable from the outside only if a
-- person or the assistant connection genuinely needs to call it, and every one
-- that is reachable checks the caller's role in its own body. Everything else is
-- revoked from PUBLIC and stays callable only inside the definer functions that
-- use it, which run as the owner.
--
-- Staff still read the running configuration the proper way, by selecting from
-- msp_env_parameter under its row level security policy.

-- 1. Internal plumbing. Nothing outside the database calls these.
revoke all on function msp_env_get(text)          from public, anon, authenticated;
revoke all on function msp_env_get_int(text)      from public, anon, authenticated;
revoke all on function msp_env_get_numeric(text)  from public, anon, authenticated;
revoke all on function msp_env_get_bool(text)     from public, anon, authenticated;
revoke all on function msp_env_bundle(text)       from public, anon, authenticated;
revoke all on function msp_env_after_change(text) from public, anon, authenticated;
revoke all on function msp_ai_month_spend_usd()   from public, anon, authenticated;

-- 2. Called only by the assistant connection, which runs on the service context.
revoke all on function msp_ai_preflight(text)           from public, anon, authenticated;
revoke all on function msp_ai_context_industry(text)    from public, anon, authenticated;
revoke all on function msp_ai_context_instruments()     from public, anon, authenticated;
revoke all on function msp_ai_recent_calls(text, int)   from public, anon, authenticated;
revoke all on function msp_ai_client_identity(uuid)     from public, anon, authenticated;
revoke all on function msp_ai_log(text, text, text, text, text, text, integer, integer, numeric, integer, uuid, text, text)
  from public, anon, authenticated;

grant execute on function msp_ai_preflight(text)         to service_role;
grant execute on function msp_ai_context_industry(text)  to service_role;
grant execute on function msp_ai_context_instruments()   to service_role;
grant execute on function msp_ai_recent_calls(text, int) to service_role;
grant execute on function msp_ai_client_identity(uuid)   to service_role;
grant execute on function msp_ai_log(text, text, text, text, text, text, integer, integer, numeric, integer, uuid, text, text)
  to service_role;

-- 3. Called by a signed in person on the settings page. Each one checks the
-- caller's role in its own body before it does anything.
revoke all on function msp_env_set(text, text, text) from public, anon;
revoke all on function msp_ai_usage_summary()        from public, anon;
revoke all on function msp_agent_reschedule()        from public, anon;
revoke all on function msp_agent_schedule_status()   from public, anon;

grant execute on function msp_env_set(text, text, text) to authenticated;
grant execute on function msp_ai_usage_summary()        to authenticated;
grant execute on function msp_agent_reschedule()        to authenticated;
grant execute on function msp_agent_schedule_status()   to authenticated;

-- 4. The history guard trigger had a mutable search path. It only ever raises,
-- but a trigger function with an open search path is still a foothold.
create or replace function msp_env_history_block_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'msp_env_parameter_history is append only';
end;
$$;
