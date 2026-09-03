-- Phase 1 · Task engine
-- One Task table. A subtask is a task with parent_id. A checklist item is a single tick under a task.

create table template (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  key text not null,                     -- renewal_ladder, discovery_to_close, proposal_checklist, onboarding_handover, non_arrival_recovery
  name text not null,
  version int not null default 1,
  module module_key not null default 'sales',
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, key, version)
);

create table template_item (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references template(id) on delete cascade,
  position int not null,
  title text not null,
  stage journey_stage,
  offset_days int not null default 0,     -- relative to the parent start, negative allowed for ladders (days before expiry)
  duration_days int not null default 1,
  default_role role_key,                  -- who normally does it
  depends_on_position int,                -- start after finish of this sibling
  agent_key text,                         -- which agent drafts it
  requires_signature boolean not null default false
);

create table task (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  ref text unique,                        -- TSK-2026-1187, set by trigger
  module module_key not null default 'sales',
  parent_id uuid references task(id) on delete cascade,
  client_id uuid references client(id),
  title text not null,
  description text,
  task_type text,                         -- MCO type name kept verbatim: Medicals Due, Non Arrival ...
  stage journey_stage,
  status task_status not null default 'new',
  priority task_priority not null default 'normal',
  source task_source not null default 'manual',
  source_ref text,                        -- MCO id, meeting id, message id
  source_url text,
  assignee_id uuid references person(id),
  signer_id uuid references person(id),   -- the named human who signs gated steps on this task
  template_id uuid references template(id),
  template_item_id uuid references template_item(id),
  client_source text,                     -- copied from client at creation, carried downstream
  language text not null default 'en',
  due_date date,
  start_date date,
  completed_at timestamptz,
  pinned boolean not null default false,  -- pinned scheduling block never moves
  rank_score numeric,                     -- Today ranking
  rank_reason text,                       -- visible explanation
  sla_breach_probability numeric,         -- 0 to 1, predicted
  sla_due_at timestamptz,
  medical_count int,                      -- counts only, never names
  drafted_by_agent boolean not null default false,
  created_by uuid references person(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index task_parent_idx on task(parent_id);
create index task_assignee_idx on task(assignee_id, status);
create index task_client_idx on task(client_id);
create index task_due_idx on task(due_date);
create trigger task_updated before update on task for each row execute function set_updated_at();

create sequence task_ref_seq start 1001;
create or replace function task_set_ref() returns trigger language plpgsql as $$
begin
  if new.ref is null then
    new.ref := 'TSK-' || to_char(now(), 'YYYY') || '-' || nextval('task_ref_seq');
  end if;
  if new.client_source is null and new.client_id is not null then
    select client_source into new.client_source from client where id = new.client_id;
  end if;
  return new;
end $$;
create trigger task_ref before insert on task for each row execute function task_set_ref();

create table checklist_item (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references task(id) on delete cascade,
  position int not null,
  title text not null,
  ticked boolean not null default false,
  ticked_by uuid references person(id),
  ticked_at timestamptz
);

create table task_dependency (
  id uuid primary key default gen_random_uuid(),
  predecessor_id uuid not null references task(id) on delete cascade,
  successor_id uuid not null references task(id) on delete cascade,
  kind text not null default 'finish_to_start',
  unique (predecessor_id, successor_id)
);

create table task_comment (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references task(id) on delete cascade,
  author_id uuid references person(id),
  author_kind text not null default 'person',
  body text not null,
  created_at timestamptz not null default now()
);

create table time_entry (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references task(id) on delete cascade,
  person_id uuid not null references person(id),
  minutes int not null,
  kind text not null default 'focus',    -- focus | manual
  started_at timestamptz not null default now()
);

create table task_document (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references task(id) on delete cascade,
  name text not null,
  sharepoint_item_id text,
  web_url text,
  created_by uuid references person(id),
  created_at timestamptz not null default now()
);

-- recurring obligations, for example the renewal ladder
create table recurrence_rule (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  client_id uuid references client(id),
  template_id uuid not null references template(id),
  anchor_date date not null,              -- MCO expiry date
  generated boolean not null default false,
  confirmed_by uuid references person(id),-- tagged [CONFIRM] until the account owner accepts the calendar once
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- approvals (human gates)
create table approval (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  kind approval_kind not null,
  state approval_state not null default 'pending',
  task_id uuid references task(id) on delete cascade,
  requested_by_agent text,                -- agent key
  approver_id uuid references person(id), -- the named human
  title text not null,
  detail text,
  payload jsonb not null default '{}'::jsonb,  -- draft email, proposed assignee, proposed tasks
  options jsonb not null default '[]'::jsonb,  -- alternative actions
  decided_by uuid references person(id),
  decided_at timestamptz,
  decision text,
  created_at timestamptz not null default now()
);
create index approval_open_idx on approval(approver_id, state);

-- ---------------------------------------------------------------- captured items
create table captured_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  channel capture_channel not null,
  source_ref text not null,               -- meeting id, message id
  source_url text,
  client_id uuid references client(id),
  proposed_for uuid references person(id),
  extract text,                           -- short extract, retention 90 days [CONFIRM]
  extract_language text default 'en',
  proposed_tasks jsonb not null default '[]'::jsonb,
  health_lines_dropped int not null default 0,
  approval_id uuid references approval(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '90 days'
);

create table translation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  entity text not null,                   -- task | captured_item | approval
  entity_id uuid not null,
  field text not null,
  source_language text not null,
  target_language text not null,
  source_text text not null,
  translated_text text not null,
  provider text not null default 'azure_translator',
  created_at timestamptz not null default now(),
  unique (entity, entity_id, field, target_language)
);

-- ---------------------------------------------------------------- MyClinicOnline landing table
create table mco_task (
  id bigserial primary key,
  tenant_id uuid references tenant(id),
  mco_id text unique not null,
  task_type text not null,
  status text not null,
  created_at_mco timestamptz,
  due_date date,
  created_by_name text,
  assigned_user_name text,
  assigned_user_email text,
  client_name text,
  description text,                       -- as MCO sends it. Names inside are scrubbed by mco-sync before any agent sees them.
  medical_count int,
  window_from date,
  window_to date,
  raw jsonb,
  synced_at timestamptz not null default now(),
  processed_at timestamptz,
  portal_task_id uuid references task(id)
);

-- ---------------------------------------------------------------- SLA
create table sla_policy (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  task_type text not null,
  hours_to_resolve int not null,
  escalate_to role_key not null default 'sales_manager'
);

-- ---------------------------------------------------------------- RLS
alter table template enable row level security;
alter table template_item enable row level security;
alter table task enable row level security;
alter table checklist_item enable row level security;
alter table task_dependency enable row level security;
alter table task_comment enable row level security;
alter table time_entry enable row level security;
alter table task_document enable row level security;
alter table recurrence_rule enable row level security;
alter table approval enable row level security;
alter table captured_item enable row level security;
alter table translation enable row level security;
alter table mco_task enable row level security;
alter table sla_policy enable row level security;

create policy template_read on template for select using (tenant_id = current_tenant_id());
create policy template_item_read on template_item for select using (exists (select 1 from template t where t.id = template_id and t.tenant_id = current_tenant_id()));
create policy template_write on template for all using (tenant_id = current_tenant_id() and is_manager_or_above()) with check (tenant_id = current_tenant_id() and is_manager_or_above());

-- a person sees own tasks, tasks owned by their subtree, and tasks they sign for or watch
create policy task_read on task for select using (
  tenant_id = current_tenant_id() and (
    is_manager_or_above() or can_see(assignee_id) or signer_id = current_person_id() or created_by = current_person_id()
  )
);
create policy task_insert on task for insert with check (tenant_id = current_tenant_id() and current_role() <> 'information_officer');
create policy task_update on task for update using (
  tenant_id = current_tenant_id() and (is_manager_or_above() or assignee_id = current_person_id() or signer_id = current_person_id())
);

create policy checklist_rw on checklist_item for all using (exists (select 1 from task t where t.id = task_id)) with check (exists (select 1 from task t where t.id = task_id));
create policy dependency_rw on task_dependency for all using (exists (select 1 from task t where t.id = successor_id)) with check (exists (select 1 from task t where t.id = successor_id));
create policy comment_rw on task_comment for all using (exists (select 1 from task t where t.id = task_id)) with check (exists (select 1 from task t where t.id = task_id));
create policy time_rw on time_entry for all using (person_id = current_person_id() or is_manager_or_above()) with check (person_id = current_person_id());
create policy document_rw on task_document for all using (exists (select 1 from task t where t.id = task_id)) with check (exists (select 1 from task t where t.id = task_id));
create policy recurrence_read on recurrence_rule for select using (tenant_id = current_tenant_id());

create policy approval_read on approval for select using (
  tenant_id = current_tenant_id() and (approver_id = current_person_id() or is_manager_or_above() or exists (select 1 from task t where t.id = task_id))
);
create policy approval_decide on approval for update using (
  tenant_id = current_tenant_id() and (approver_id = current_person_id() or is_manager_or_above())
);

create policy captured_read on captured_item for select using (
  tenant_id = current_tenant_id() and (proposed_for = current_person_id() or is_manager_or_above())
);
create policy translation_read on translation for select using (tenant_id = current_tenant_id());
create policy mco_read on mco_task for select using (is_manager_or_above());
create policy sla_read on sla_policy for select using (tenant_id = current_tenant_id());

-- ---------------------------------------------------------------- views
create or replace view v_task_progress as
select t.id as task_id,
       count(s.id) as subtasks,
       count(s.id) filter (where s.status = 'completed') as subtasks_done
from task t left join task s on s.parent_id = t.id
group by t.id;

create or replace view v_person_load as
select p.id as person_id, p.full_name, p.capacity_open_parents,
       count(t.id) filter (where t.parent_id is null and t.status not in ('completed')) as open_parents,
       count(t.id) filter (where t.status = 'overdue') as overdue
from person p left join task t on t.assignee_id = p.id
group by p.id;

-- overdue sweep: status becomes overdue when due passes. Run by pg_cron hourly.
create or replace function mark_overdue() returns int language plpgsql security definer as $$
declare n int;
begin
  update task set status = 'overdue' where status in ('new', 'in_progress') and due_date < current_date;
  get diagnostics n = row_count;
  return n;
end $$;
select cron.schedule('mark-overdue-hourly', '5 * * * *', $$select mark_overdue()$$);
