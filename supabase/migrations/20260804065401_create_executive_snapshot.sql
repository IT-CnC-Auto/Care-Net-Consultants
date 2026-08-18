-- Executive overview snapshot for the Directors page.
-- One curated row (id='current') per reporting month, updated by IT/Finance.
-- Read model only: the portal never writes it.

create or replace function public.is_exec_reader()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.role in ('owner','administrator') or ur.department = 'directors')
  );
$$;

revoke all on function public.is_exec_reader() from public, anon;
grant execute on function public.is_exec_reader() to authenticated;

create table public.executive_snapshot (
  id                   text primary key default 'current',
  period_label         text not null,
  period_from          date not null,
  period_to            date not null,
  report_ref           text,
  status_note          text,
  source_note          text,
  generated_on         date,
  working_days_total   int  not null,
  working_days_elapsed int  not null,
  public_holidays      int  not null default 0,
  core_sales           numeric not null,
  upselling            numeric,
  breakeven_target     numeric,
  targets              jsonb not null default '[]'::jsonb,
  regions              jsonb not null default '[]'::jsonb,
  prior_year_daily_avg numeric,
  cash_accounts        jsonb not null default '[]'::jsonb,
  cash_all_accounts    numeric,
  cash_note            text,
  cash_as_at           date,
  updated_at           timestamptz not null default now()
);

comment on table public.executive_snapshot is
  'Directors-page executive overview (CNC-RPT series). Single row id=current. Directors Only: RLS restricts SELECT to owner/administrator roles or the directors department via is_exec_reader(). Writes via service role or SQL editor only. Amounts are ZAR excl VAT unless noted; derived figures (% of break even, projection, daily rate, regional shares) are computed by the portal from these raw inputs.';

alter table public.executive_snapshot enable row level security;

create policy "Exec readers can read snapshot"
  on public.executive_snapshot
  for select
  to authenticated
  using (public.is_exec_reader());

revoke insert, update, delete, truncate on public.executive_snapshot from anon, authenticated;
