-- CNC MSP FORGE | local test harness only. Stands in for the Supabase platform
-- objects the migrations expect (roles, auth, storage, cron, extensions), so the
-- migrations can be replayed into a plain PostgreSQL 16. Never applied to Supabase.
do $$ begin
  -- Roles belong to the whole cluster and survive a database drop, so create them only once.
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema extensions;
create extension pgcrypto with schema extensions;
create schema auth;
-- email_confirmed_at and raw_app_meta_data mirror the Supabase columns that
-- hsf_link_account (confirmed email) and hsf_user_is_staff (msp_roles) read;
-- phone and phone_confirmed_at those the deletion PIN by SMS reads (migration 052).
create table auth.users (id uuid primary key default gen_random_uuid(), email text,
  email_confirmed_at timestamptz, raw_app_meta_data jsonb, phone text, phone_confirmed_at timestamptz);
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid $$;
create function auth.role() returns text language sql stable as $$
  select coalesce(auth.jwt() ->> 'role', 'anon') $$;
create schema cron;
create table cron.job (jobid bigserial primary key, jobname text unique, schedule text, command text);
create function cron.schedule(p_name text, p_expr text, p_cmd text) returns bigint language sql as $$
  insert into cron.job (jobname, schedule, command) values (p_name, p_expr, p_cmd)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
  returning jobid $$;
create function cron.unschedule(p_name text) returns boolean language sql as $$
  with d as (delete from cron.job where jobname = p_name returning 1) select exists (select 1 from d) $$;
create schema storage;
create table storage.buckets (id text primary key, name text not null, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now());
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text, owner uuid, metadata jsonb, created_at timestamptz default now());
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
grant usage on schema auth, storage, extensions to anon, authenticated, service_role;
