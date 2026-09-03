-- Phase 0 · Foundation
-- Care Net tasks module. One tenant per Care Net entity, one Task table for every module.
-- British English in comments. Every table carries tenant_id, created_at, updated_at, created_by.

create extension if not exists pgcrypto;
create extension if not exists pg_cron;
create extension if not exists vector;

-- ---------------------------------------------------------------- enums
create type role_key as enum ('franchise_director', 'sales_manager', 'sales_consultant', 'information_officer', 'agent');
create type task_status as enum ('new', 'in_progress', 'awaiting_approval', 'completed', 'overdue', 'on_hold');
create type task_priority as enum ('low', 'normal', 'high');
create type task_source as enum ('mco', 'grok', 'manual', 'crm', 'capture');
create type journey_stage as enum ('prospect', 'quote', 'onboard', 'schedule', 'clinic_day', 'certificates', 'invoice', 'renewal');
create type module_key as enum ('sales', 'clinic_operations', 'finance', 'hr_compliance');
create type approval_kind as enum ('allocation', 'outbound_email', 'threshold', 'reassignment', 'captured_task', 'schedule_block', 'close_from_mco');
create type approval_state as enum ('pending', 'approved', 'rejected', 'expired');
create type capture_channel as enum ('fireflies', 'outlook_flag', 'teams_message', 'teams_transcript', 'zoom_transcript', 'stt_fallback');

-- ---------------------------------------------------------------- tenancy and people
create table tenant (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  legal_name text not null,
  territory text,
  information_officer text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table person (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  auth_user_id uuid unique,                       -- auth.users.id once the person signs in with Entra
  email text unique not null,
  full_name text not null,
  initials text not null,
  role role_key not null,
  manager_id uuid references person(id),          -- parent in the oversight tree
  capacity_open_parents int not null default 12,  -- rule R-07 threshold
  language text not null default 'en',            -- preferred reading language, ISO 639-1
  is_service_account boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index person_manager_idx on person(manager_id);

-- ---------------------------------------------------------------- clients
create table client (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  name text not null,
  industry text,
  sites text[] default '{}',
  employees_on_surveillance int,
  mco_client_ref text,                            -- MyClinicOnline client reference
  crm_contact_ref text,                           -- AutoHive CRM id. Contact email and phone live there, never here.
  sharepoint_site_id text,
  sharepoint_drive_id text,
  account_owner_id uuid references person(id),
  oversight_id uuid references person(id),
  client_source text,                             -- recorded at first contact, carried on every task
  client_source_recorded_at date,
  current_stage journey_stage not null default 'prospect',
  contract_renewal date,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table client_contact (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  client_id uuid not null references client(id) on delete cascade,
  display_name text not null,                     -- short form only, for example "Thabo N."
  role text,
  crm_contact_ref text,                           -- email and phone are fetched from AutoHive CRM on demand
  is_primary boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- governance
create table audit_log (
  id bigserial primary key,
  tenant_id uuid not null,
  at timestamptz not null default now(),
  actor_person_id uuid,
  actor_kind text not null default 'person',      -- person | agent | system
  action text not null,
  entity text not null,
  entity_id uuid,
  detail jsonb not null default '{}'::jsonb
);
create index audit_log_entity_idx on audit_log(entity, entity_id);

create table consent_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id),
  subject_ref text not null,                      -- meeting id, contact ref. Never a health record.
  purpose text not null,                          -- recording_notice | processing | marketing
  wording text not null,                          -- exact wording shown
  policy_version text not null,
  given boolean not null,
  given_at timestamptz not null default now(),
  created_by uuid references person(id)
);

create table dead_letter (
  id bigserial primary key,
  tenant_id uuid,
  at timestamptz not null default now(),
  function_name text not null,
  payload jsonb,
  error text,
  retry_count int not null default 0,
  resolved boolean not null default false
);

-- ---------------------------------------------------------------- helpers
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create trigger tenant_updated before update on tenant for each row execute function set_updated_at();
create trigger person_updated before update on person for each row execute function set_updated_at();
create trigger client_updated before update on client for each row execute function set_updated_at();

-- current person for the signed in user
create or replace function current_person_id() returns uuid language sql stable security definer as $$
  select id from person where auth_user_id = auth.uid() limit 1
$$;

create or replace function current_role() returns role_key language sql stable security definer as $$
  select role from person where auth_user_id = auth.uid() limit 1
$$;

create or replace function current_tenant_id() returns uuid language sql stable security definer as $$
  select tenant_id from person where auth_user_id = auth.uid() limit 1
$$;

-- every person below me in the oversight tree, plus me
create or replace function my_subtree() returns setof uuid language sql stable security definer as $$
  with recursive tree as (
    select id from person where id = current_person_id()
    union all
    select p.id from person p join tree t on p.manager_id = t.id
  )
  select id from tree
$$;

-- can the signed in person see rows owned by owner_id
create or replace function can_see(owner_id uuid) returns boolean language sql stable security definer as $$
  select current_role() = 'franchise_director'
      or owner_id in (select my_subtree())
$$;

create or replace function is_manager_or_above() returns boolean language sql stable as $$
  select current_role() in ('franchise_director', 'sales_manager')
$$;

-- ---------------------------------------------------------------- RLS
alter table tenant enable row level security;
alter table person enable row level security;
alter table client enable row level security;
alter table client_contact enable row level security;
alter table audit_log enable row level security;
alter table consent_record enable row level security;
alter table dead_letter enable row level security;

create policy tenant_read on tenant for select using (id = current_tenant_id());

create policy person_read on person for select using (tenant_id = current_tenant_id());
create policy person_admin on person for all using (current_role() = 'franchise_director') with check (current_role() = 'franchise_director');

create policy client_read on client for select using (
  tenant_id = current_tenant_id() and (is_manager_or_above() or can_see(account_owner_id))
);
create policy client_write on client for all using (tenant_id = current_tenant_id() and is_manager_or_above())
  with check (tenant_id = current_tenant_id() and is_manager_or_above());

create policy client_contact_read on client_contact for select using (
  exists (select 1 from client c where c.id = client_id and (is_manager_or_above() or can_see(c.account_owner_id)))
);

create policy audit_read on audit_log for select using (
  tenant_id = current_tenant_id() and current_role() in ('franchise_director', 'sales_manager', 'information_officer')
);
create policy consent_read on consent_record for select using (
  tenant_id = current_tenant_id() and current_role() in ('franchise_director', 'information_officer')
);
create policy dead_letter_read on dead_letter for select using (current_role() in ('franchise_director', 'sales_manager'));

-- service role bypasses RLS for Edge Functions. Never ship the service key to the browser.
