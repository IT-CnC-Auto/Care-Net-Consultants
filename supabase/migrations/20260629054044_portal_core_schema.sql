
-- ===== ENUMS =====
create type public.app_role as enum ('owner','administrator','department_member');
create type public.app_department as enum ('directors','operations','finance','sales','corporate_governance','hr_and_people','it_and_ai','marketing');

-- ===== TRIGGER FUNCTION =====
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $fn$
begin
  new.updated_at = now();
  return new;
end;
$fn$;

-- ===== TABLES =====
create table public.user_profiles (
  id uuid primary key default gen_random_uuid() references auth.users(id),
  full_name text not null,
  email text not null unique,
  photo_path text,
  personal_details jsonb default '{}'::jsonb,
  is_active boolean not null default true,
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  job_title text,
  mfa_enrolled boolean not null default false
);
comment on table public.user_profiles is 'Portal user profiles. POPIA: personal_details column is RLS-protected and visible only to the record owner and admin/owner roles.';
comment on column public.user_profiles.photo_path is 'Storage object path in private profile-photos bucket. Never expose directly — serve via signed URL from server-side route.';
comment on column public.user_profiles.personal_details is 'POPIA-protected JSONB. Recommended fields: phone_number, employee_number. Do NOT store ID numbers, medical info, or financial data here.';

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id),
  role public.app_role not null default 'department_member',
  department public.app_department,
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_roles_user_id_fkey_profiles foreign key (user_id) references public.user_profiles(id)
);
comment on table public.user_roles is 'Role and department assignments. One record per user. RLS enforced: only owner/administrator can write.';

create table public.finance_snapshot (
  id text primary key default 'current'::text,
  invoices jsonb not null default '[]'::jsonb,
  pl_report jsonb not null default '{}'::jsonb,
  period_from date,
  period_to date,
  synced_at timestamptz not null default now()
);

-- ===== HELPER FUNCTIONS =====
create or replace function public.current_user_department()
returns public.app_department language sql stable security definer as $fn$
  select department from public.user_roles where user_id = auth.uid() limit 1;
$fn$;
create or replace function public.current_user_role()
returns public.app_role language sql stable security definer as $fn$
  select role from public.user_roles where user_id = auth.uid() limit 1;
$fn$;
create or replace function public.is_admin_or_owner()
returns boolean language sql stable security definer as $fn$
  select exists (select 1 from public.user_roles where user_id = auth.uid() and role in ('owner','administrator'));
$fn$;

-- ===== TRIGGERS =====
create trigger trg_user_profiles_updated_at before update on public.user_profiles for each row execute function public.handle_updated_at();
create trigger trg_user_roles_updated_at before update on public.user_roles for each row execute function public.handle_updated_at();

-- ===== RLS =====
alter table public.user_profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.finance_snapshot enable row level security;

create policy profiles_admin_full_access on public.user_profiles as permissive for all to authenticated using (is_admin_or_owner()) with check (is_admin_or_owner());
create policy profiles_member_select_own on public.user_profiles as permissive for select to authenticated using (id = auth.uid());
create policy profiles_member_update_own on public.user_profiles as permissive for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy roles_admin_delete on public.user_roles as permissive for delete to authenticated using (is_admin_or_owner());
create policy roles_admin_insert on public.user_roles as permissive for insert to authenticated with check (is_admin_or_owner());
create policy roles_admin_select_all on public.user_roles as permissive for select to authenticated using (is_admin_or_owner());
create policy roles_member_select_own on public.user_roles as permissive for select to authenticated using (user_id = auth.uid());
create policy roles_update on public.user_roles as permissive for update to public using (is_admin_or_owner()) with check (
  case when role = any (array['administrator'::public.app_role,'owner'::public.app_role])
       then current_user_role() = 'owner'::public.app_role
       else is_admin_or_owner() end
);

create policy "Anon can upsert finance snapshot" on public.finance_snapshot as permissive for all to public using (true) with check (true);
create policy "Portal can read finance snapshot" on public.finance_snapshot as permissive for select to public using (true);
