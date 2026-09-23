-- CNC MSP FORGE | local test harness only. Stands in for the Supabase platform
-- objects the migrations expect (roles, auth, storage, cron, extensions), so the
-- migrations can be replayed into a plain PostgreSQL 16. Never applied to Supabase.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema extensions;
create extension pgcrypto with schema extensions;
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
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
