create table if not exists public.sales_pipeline_opportunity (
  autohive_opportunity_id      text primary key,
  autohive_pipeline_id         text,
  autohive_pipeline_stage_id   text,
  pipeline_name                text,
  stage_name                   text,
  stage_position               integer,
  stage_probability            numeric,
  canonical_name               text,
  company_name                 text,
  monetary_value               numeric not null default 0,
  status                       text    not null default 'open',
  source                       text,
  autohive_assigned_to         text,
  autohive_created_at          timestamptz,
  autohive_updated_at          timestamptz,
  last_stage_change_at         timestamptz,
  last_status_change_at        timestamptz,
  nexus_synced_at              timestamptz,                       -- freshness carried from Nexus/GHL
  portal_synced_at             timestamptz not null default now() -- when the bridge last wrote this row
);

comment on table public.sales_pipeline_opportunity is
  'Portal-side read model of the Sales pipeline. Synced read-only from CNC Nexus (dvanjuwmflvjvwtjjtds.integration_pipeline_opportunity) by the sync-pipeline-from-nexus edge function every 15 min. POPIA: contact email/phone deliberately excluded (not needed by the Sales dashboard). Do not write directly — the bridge owns this table.';

alter table public.sales_pipeline_opportunity enable row level security;

-- Portal reads it (mirrors finance_snapshot's public SELECT). Writes are service-role only (bridge bypasses RLS).
create policy "Portal can read sales pipeline"
  on public.sales_pipeline_opportunity
  for select to public using (true);

create index if not exists idx_sales_pipeline_stage    on public.sales_pipeline_opportunity (stage_position);
create index if not exists idx_sales_pipeline_status   on public.sales_pipeline_opportunity (status);
create index if not exists idx_sales_pipeline_assigned on public.sales_pipeline_opportunity (autohive_assigned_to);
