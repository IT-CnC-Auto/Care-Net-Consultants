-- CNC MSP FORGE | ENV-01 v1.0.0, AI-01 v1.0.0 | Parameter store and AI connection 15/08/2026
-- Two things live here. First, a parameter store so the running system can be
-- retuned without a redeploy: model, effort, thresholds, schedules, ceilings.
-- Second, the ledger and the budget gate behind the AI connection, so every
-- call the assistant makes is recorded, priced, and stoppable.
--
-- Secrets never live in this table. The API key sits in Supabase secrets and the
-- service role key sits in Vercel. Where a parameter must point at a secret it
-- stores a reference, never a value, and a check constraint enforces that.

-- 1. The parameter store -------------------------------------------------------

create table msp_env_parameter (
  key           text primary key,
  value         text not null,
  value_type    text not null check (value_type in ('text','integer','decimal','boolean','date','enum')),
  allowed_values text[],
  min_value     numeric,
  max_value     numeric,
  category      text not null check (category in ('ai','agent','clinical','commercial','retention','integration')),
  description   text not null,
  updated_by    text not null default 'migration_034',
  updated_at    timestamptz not null default now(),
  -- A parameter whose name reads like a credential may only carry a reference.
  -- The pattern matches whole name segments, so ai.max_output_tokens is not
  -- mistaken for a credential while ai.api_key_ref is.
  constraint msp_env_parameter_no_secret_values check (
    key !~* '(^|[._-])(secret|password|api_key|apikey|api-key|token|private_key|credential)([._-]|$)'
    or value ~ '^(env:|vault:|supabase_secret:)'
  )
);
comment on table msp_env_parameter is
  'Runtime parameter store. Everything tunable without a redeploy: AI model and effort, agent schedule, clinical floors, commercial thresholds, spend ceilings. Never holds a secret value, only a reference to one.';
comment on column msp_env_parameter.allowed_values is
  'Permitted values for an enum parameter. Enforced by msp_env_set, not by the UI.';

create table msp_env_parameter_history (
  id          bigint generated always as identity primary key,
  key         text not null,
  old_value   text,
  new_value   text not null,
  changed_by  text not null,
  changed_at  timestamptz not null default now(),
  reason      text
);
comment on table msp_env_parameter_history is
  'Append only history of every parameter change. A tuning change is a change to how the plans come out, so it is evidence.';

create index msp_env_parameter_history_key_idx on msp_env_parameter_history(key, changed_at desc);

create or replace function msp_env_history_block_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'msp_env_parameter_history is append only';
end;
$$;

create trigger msp_env_history_no_update
  before update or delete on msp_env_parameter_history
  for each row execute function msp_env_history_block_mutation();

alter table msp_env_parameter enable row level security;
alter table msp_env_parameter_history enable row level security;

-- Any forge role may read the running configuration. Nobody writes directly:
-- writes go through msp_env_set so the history and the validation cannot be
-- bypassed.
create policy msp_env_parameter_read on msp_env_parameter
  for select to authenticated using (msp_any_forge_role());
create policy msp_env_parameter_history_read on msp_env_parameter_history
  for select to authenticated using (msp_has_role('forge_admin') or msp_has_role('forge_omp'));

-- 2. Read and write --------------------------------------------------------------

create or replace function msp_env_get(p_key text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select value from msp_env_parameter where key = p_key;
$$;
comment on function msp_env_get is 'Single parameter read. Definer so the server paths and the agent can read configuration without table grants.';

create or replace function msp_env_get_int(p_key text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select value::integer from msp_env_parameter where key = p_key and value_type = 'integer';
$$;

create or replace function msp_env_get_numeric(p_key text)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select value::numeric from msp_env_parameter
   where key = p_key and value_type in ('integer','decimal');
$$;

create or replace function msp_env_get_bool(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select value::boolean from msp_env_parameter where key = p_key and value_type = 'boolean';
$$;

-- The whole configuration for one category, as an object. This is what the AI
-- connection calls on every invocation so it never carries a hard coded model,
-- effort, ceiling or prompt version.
create or replace function msp_env_bundle(p_category text default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
    from msp_env_parameter
   where p_category is null or category = p_category;
$$;
comment on function msp_env_bundle is 'All parameters, or all parameters in one category, as a flat object. The AI connection reads its whole configuration through this in a single call.';

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
  -- coalesce so a null JWT is a refusal, never a silent pass
  if not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'changing a runtime parameter requires the forge_admin role';
  end if;

  select * into v_row from msp_env_parameter where key = p_key;
  if not found then
    raise exception 'unknown parameter %. Parameters are declared by migration, not created at runtime', p_key;
  end if;

  -- Type and range validation happens here, not in the caller. A bad value must
  -- never reach the running system.
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

  return jsonb_build_object('key', p_key, 'old_value', v_row.value, 'new_value', p_value,
                            'changed_by', v_actor, 'changed_at', now());
end;
$$;
comment on function msp_env_set is
  'The only write path into the parameter store. Validates type, enum membership and range, records history, writes an audit event. forge_admin only.';

revoke all on function msp_env_set(text, text, text) from public, anon;
grant execute on function msp_env_set(text, text, text) to authenticated;
grant execute on function msp_env_get(text), msp_env_get_int(text), msp_env_get_numeric(text),
  msp_env_get_bool(text), msp_env_bundle(text) to authenticated;

-- 3. The declared parameters -----------------------------------------------------
-- Values here are the ones the system is actually running on today. Where a value
-- is a placeholder awaiting a Care Net decision it is marked in the description
-- and carried in the confirmation register, not silently presented as settled.

insert into msp_env_parameter (key, value, value_type, allowed_values, min_value, max_value, category, description) values
  -- AI connection
  ('ai.model', 'claude-opus-5', 'enum',
   array['claude-opus-5','claude-sonnet-5','claude-haiku-4-5'], null, null, 'ai',
   'Model the assistant runs on. Change here, no redeploy.'),
  ('ai.effort', 'high', 'enum', array['low','medium','high'], null, null, 'ai',
   'Reasoning effort for assistant calls. High for anything touching a clinical or legal question.'),
  ('ai.thinking', 'adaptive', 'enum', array['adaptive','off'], null, null, 'ai',
   'Extended thinking mode. Adaptive lets the model choose its own depth per question.'),
  ('ai.max_output_tokens', '8000', 'integer', null, 512, 64000, 'ai',
   'Ceiling on a single assistant response.'),
  ('ai.enabled', 'true', 'boolean', null, null, null, 'ai',
   'Master switch. Set to false and every assistant call returns disabled without reaching the API.'),
  ('ai.api_key_ref', 'supabase_secret:ANTHROPIC_API_KEY', 'text', null, null, null, 'ai',
   'Where the API key lives. A reference only. The key itself is never stored in the database.'),
  ('ai.monthly_cost_ceiling_usd', '200', 'decimal', null, 0, 10000, 'ai',
   'Hard monthly ceiling on assistant spend. The connection refuses to call once the month exceeds it.'),
  ('ai.prompt_version', '1.0.0', 'text', null, null, null, 'ai',
   'Version of the assistant instruction set. Bumped whenever the guardrails change.'),
  ('ai.allow_client_facing', 'true', 'boolean', null, null, null, 'ai',
   'Whether the assistant may answer a client directly. When false it only serves internal actions.'),

  -- Agent schedule and behaviour
  ('agent.monthly_audit_day', '1', 'integer', null, 1, 28, 'agent',
   'Day of the month the framework audit runs. Capped at 28 so every month has one.'),
  ('agent.monthly_audit_hour_utc', '2', 'integer', null, 0, 23, 'agent',
   'Hour in UTC the framework audit runs.'),
  ('agent.currency_check_months', '12', 'integer', null, 1, 60, 'agent',
   'How old a currency check may be before the audit raises the instrument.'),
  ('agent.findings_alert_email', 'pending', 'text', null, null, null, 'agent',
   'Where audit findings are sent. Pending a Care Net address, register item CR-13.18.'),
  ('agent.autopublish_findings', 'false', 'boolean', null, null, null, 'agent',
   'Whether the agent may act on its own findings. False by design: a finding is a proposal for the practitioner, not a change.'),

  -- Clinical floors. These are legal minima and are not tuning knobs in practice.
  ('clinical.periodic_floor_months', '12', 'integer', null, 1, 36, 'clinical',
   'Maximum interval between periodic examinations. Twelve months is the regulatory floor and must not be raised without a legal basis.'),
  ('clinical.record_retention_years', '40', 'integer', null, 40, 100, 'clinical',
   'Medical surveillance record retention floor in years. Forty is the house floor, register item CR-12.4.'),
  ('clinical.noise_action_level_db', '85', 'integer', null, 80, 90, 'clinical',
   'Noise action level in dB(A). Eighty five under the Noise Induced Hearing Loss Regulations, register item CR-13.10.'),
  ('clinical.omp_release_required', 'true', 'boolean', null, null, null, 'clinical',
   'Whether a registered practitioner signature is required before release. True. The database trigger enforces this independently.'),

  -- Commercial
  ('commercial.free_medicals_threshold', '100', 'integer', null, 1, 100000, 'commercial',
   'Annual medicals at which the plan becomes free to the client. Register item CR-13.15.'),
  ('commercial.omp_review_fee_zar', '2500', 'decimal', null, 0, 100000, 'commercial',
   'Practitioner review and sign off fee. Placeholder pending confirmation, register item CR-13.17.'),
  ('commercial.pricing_status', 'indicative', 'enum', array['indicative','confirmed'], null, null, 'commercial',
   'Whether quoted prices are confirmed. While indicative every quote carries that wording.'),
  ('commercial.quote_validity_days', '30', 'integer', null, 1, 365, 'commercial',
   'How long a quotation stands.'),

  -- Integration references. References only, never values.
  ('integration.payment_gateway', 'pending', 'text', null, null, null, 'integration',
   'Payment gateway in use. Pending a Care Net decision, register item CR-13.13.'),
  ('integration.signature_provider', 'docuseal', 'text', null, null, null, 'integration',
   'Electronic signature provider for practitioner sign off.'),
  ('integration.site_base_url', 'pending', 'text', null, null, null, 'integration',
   'Canonical public base URL. Pending confirmation, register item CR-13.3.');

-- 4. The AI call ledger ----------------------------------------------------------

create table msp_ai_call_log (
  id             bigint generated always as identity primary key,
  called_at      timestamptz not null default now(),
  action         text not null,
  model          text not null,
  effort         text,
  prompt_version text,
  engagement_id  uuid,
  industry_code  text,
  actor          text not null,
  input_tokens   integer,
  output_tokens  integer,
  cost_usd       numeric(10,4),
  latency_ms     integer,
  outcome        text not null check (outcome in ('ok','refused','error','disabled','over_budget')),
  error_detail   text
);
comment on table msp_ai_call_log is
  'Every assistant call, priced and attributed. This is the cost control and the evidence trail: what was asked, on what model, at what effort, under which instruction version.';

create index msp_ai_call_log_month_idx on msp_ai_call_log(called_at desc);

alter table msp_ai_call_log enable row level security;
create policy msp_ai_call_log_read on msp_ai_call_log
  for select to authenticated using (msp_has_role('forge_admin') or msp_has_role('forge_omp'));

-- Spend so far in the current calendar month.
create or replace function msp_ai_month_spend_usd()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(cost_usd), 0)
    from msp_ai_call_log
   where called_at >= date_trunc('month', now());
$$;

-- The gate the connection calls before it spends anything. Returns the running
-- configuration together with a verdict, so the connection needs one round trip.
create or replace function msp_ai_preflight(p_action text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg jsonb := msp_env_bundle('ai');
  v_spend numeric := msp_ai_month_spend_usd();
  v_ceiling numeric := (v_cfg ->> 'ai.monthly_cost_ceiling_usd')::numeric;
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'the assistant connection requires the forge_agent or forge_admin role';
  end if;
  if (v_cfg ->> 'ai.enabled')::boolean is not true then
    return jsonb_build_object('allowed', false, 'reason', 'disabled', 'config', v_cfg);
  end if;
  if v_spend >= v_ceiling then
    return jsonb_build_object('allowed', false, 'reason', 'over_budget',
      'spend_usd', v_spend, 'ceiling_usd', v_ceiling, 'config', v_cfg);
  end if;
  return jsonb_build_object('allowed', true, 'action', p_action, 'config', v_cfg,
    'spend_usd', v_spend, 'ceiling_usd', v_ceiling);
end;
$$;
comment on function msp_ai_preflight is
  'One round trip before any assistant call: role check, master switch, monthly ceiling, and the whole running configuration. The connection carries no defaults of its own.';

create or replace function msp_ai_log(
  p_action text, p_model text, p_effort text, p_prompt_version text,
  p_outcome text, p_input_tokens integer default null, p_output_tokens integer default null,
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
    coalesce(auth.jwt() ->> 'email', auth.role(), 'assistant'), p_error)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function msp_ai_preflight(text), msp_ai_month_spend_usd() to authenticated;

-- 5. Grounding reads for the assistant --------------------------------------------
-- The assistant is never allowed to answer from its own memory of South African
-- law. It answers from rows. These two functions are the only kernel content it
-- can see, and both return verified instruments only.

create or replace function msp_ai_context_industry(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'assistant grounding reads require the forge_agent or forge_admin role';
  end if;
  select to_jsonb(p) into v from msp_public_industry_profile p where p.code = p_code;
  if v is null then
    return jsonb_build_object('found', false, 'code', p_code);
  end if;
  return v || jsonb_build_object('found', true);
end;
$$;
comment on function msp_ai_context_industry is
  'The grounding pack for one industry: verified instruments with their applicability notes, subindustries, roles, hazards, protocols. Nothing pending, nothing clinical beyond protocol names, no client data.';

create or replace function msp_ai_context_instruments()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(msp_caller_is('forge_agent'), false) and not coalesce(msp_caller_is('forge_admin'), false) then
    raise exception 'assistant grounding reads require the forge_agent or forge_admin role';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'short_name', short_name, 'citation', citation, 'status', status)
            order by short_name), '[]'::jsonb)
            from msp_legal_instrument where status = 'verified');
end;
$$;

grant execute on function msp_ai_context_industry(text), msp_ai_context_instruments() to authenticated;

-- 6. Register items opened by this work -------------------------------------------

insert into msp_confirmation_item (item_code, kind, description) values
  ('CR-13.18', 'confirm',
   'Destination address for monthly framework audit findings. Parameter agent.findings_alert_email is set to pending until Care Net confirms it.'),
  ('CR-13.19', 'confirm',
   'Monthly assistant spend ceiling. Parameter ai.monthly_cost_ceiling_usd is set to 200 US dollars as a working figure pending confirmation.')
on conflict (item_code) do nothing;
