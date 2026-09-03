-- Phase 1 · Rules engine and AI layer

create table agent (
  key text primary key,                       -- documentation, booking, follow_up, allocation, capture, translate
  name text not null,
  scope text not null,                        -- what it may read
  report_table text not null,                 -- the only table it writes to directly
  reads_untrusted_input boolean not null default false,
  model text,                                 -- xAI model id [CONFIRM]
  prompt_version text not null default 'v1'
);

create table rule (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  ref text not null,                          -- R-01 ...
  name text not null,
  trigger text not null,                      -- mco_task_created | mco_type:Medicals Due | non_arrival | subtask_drafts_email | load_above_capacity | expiry_known | capture
  agent_key text references agent(key),
  action text not null,
  guard text,
  owner_id uuid references person(id),
  enabled boolean not null default true,      -- kill switch
  threshold_medicals int,                     -- R-02, [CONFIRM 20]
  last_fired_at timestamptz,
  runs_30d int not null default 0,
  created_at timestamptz not null default now(),
  unique (tenant_id, ref)
);

create table rule_run (
  id bigserial primary key,
  rule_id uuid references rule(id),
  at timestamptz not null default now(),
  trigger_ref text,
  outcome text not null,                      -- created | allocated | held_for_signature | skipped | error
  detail jsonb not null default '{}'::jsonb
);

create table agent_run (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  agent_key text not null references agent(key),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  input_ref text,                             -- MCO id, meeting id
  input_chars int,
  output jsonb,
  model text,
  prompt_version text,
  tokens_in int,
  tokens_out int,
  accepted_by uuid references person(id),
  rejected_by uuid references person(id),
  reversible_until timestamptz not null default now() + interval '24 hours',
  error text
);

create table agent_report (                     -- capture agent writes here and nowhere else
  id bigserial primary key,
  agent_key text not null references agent(key),
  agent_run_id uuid references agent_run(id),
  at timestamptz not null default now(),
  body jsonb not null
);

create table integration_sync (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  connector text not null,                    -- mco | graph_mail | graph_calendar | fireflies | teams_transcript | sharepoint | zoom | translator | grok
  status text not null default 'ok',          -- ok | failed | paused
  last_run_at timestamptz,
  last_ok_at timestamptz,
  detail jsonb not null default '{}'::jsonb,
  unique (tenant_id, connector)
);

create table notification_pref (
  person_id uuid primary key references person(id),
  daily_digest_hour int not null default 7,    -- Africa/Johannesburg
  exceptions_to_teams boolean not null default true,
  realtime boolean not null default false
);

create table graph_subscription (
  id uuid primary key default gen_random_uuid(),
  person_id uuid references person(id),
  resource text not null,
  subscription_id text unique,
  client_state text not null,
  expires_at timestamptz not null
);

-- agent memory, small
create table agent_memory (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  client_id uuid references client(id),
  kind text not null,                          -- fact | preference | pattern
  text text not null,
  embedding vector(1536),
  source_ref text,
  created_at timestamptz not null default now()
);

alter table agent enable row level security;
alter table rule enable row level security;
alter table rule_run enable row level security;
alter table agent_run enable row level security;
alter table agent_report enable row level security;
alter table integration_sync enable row level security;
alter table notification_pref enable row level security;
alter table graph_subscription enable row level security;
alter table agent_memory enable row level security;

create policy agent_read on agent for select using (true);
create policy rule_read on rule for select using (tenant_id = current_tenant_id());
create policy rule_write on rule for update using (tenant_id = current_tenant_id() and is_manager_or_above());
create policy rule_run_read on rule_run for select using (is_manager_or_above());
create policy agent_run_read on agent_run for select using (tenant_id = current_tenant_id());
create policy integration_read on integration_sync for select using (tenant_id = current_tenant_id());
create policy notif_rw on notification_pref for all using (person_id = current_person_id()) with check (person_id = current_person_id());
create policy memory_read on agent_memory for select using (tenant_id = current_tenant_id() and is_manager_or_above());

insert into agent (key, name, scope, report_table, reads_untrusted_input, model, prompt_version) values
 ('documentation', 'Documentation agent', 'MCO rows, client, journey', 'task', false, 'grok-4-fast', 'v3.2'),
 ('booking', 'Booking agent, 30 to 90 days', 'MCO Medicals Due rows, clinic calendar', 'task', false, 'grok-4-fast', 'v3.2'),
 ('follow_up', 'Follow up agent', 'overdue and non arrival rows', 'approval', false, 'grok-4-fast', 'v3.2'),
 ('allocation', 'Allocation rule', 'person load, client history', 'approval', false, null, 'v1'),
 ('capture', 'Capture agent', 'transcripts, flagged email, Teams messages', 'agent_report', true, 'grok-4-fast', 'v1.4'),
 ('translate', 'Translator', 'task and draft text', 'translation', false, null, 'v1');

-- 15 minute MCO sync and 07:00 digest through pg_cron calling Edge Functions.
-- Set app.settings.functions_url and app.settings.service_key with:
--   alter database postgres set app.settings.functions_url = 'https://<ref>.functions.supabase.co';
create or replace function call_edge(fn text, body jsonb default '{}'::jsonb) returns void language plpgsql security definer as $$
declare url text := current_setting('app.settings.functions_url', true);
        key text := current_setting('app.settings.service_key', true);
begin
  if url is null then return; end if;
  perform net.http_post(url := url || '/' || fn, headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || key), body := body);
end $$;
create extension if not exists pg_net;
select cron.schedule('mco-sync-15m', '*/15 * * * *', $$select call_edge('mco-sync')$$);
select cron.schedule('daily-digest-0700-sast', '0 5 * * *', $$select call_edge('digest')$$);
select cron.schedule('sla-predict-hourly', '20 * * * *', $$select call_edge('mco-sync', '{"mode":"sla"}'::jsonb)$$);

-- Phase 2 schedules
select cron.schedule('teams-exceptions-hourly', '40 * * * *', $$select call_edge('teams-exceptions')$$);
select cron.schedule('graph-subscriptions-renew', '0 */12 * * *', $$select call_edge('graph-mail-flag', '{"renew":true}'::jsonb)$$);
