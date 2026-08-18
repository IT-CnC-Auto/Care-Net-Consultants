-- CNC-IT-SAL-005 · task-aggregate columns on the pipeline snapshot
alter table public.sales_pipeline_opportunity
  add column if not exists open_task_count            integer,
  add column if not exists completed_task_count       integer,
  add column if not exists last_completed_task_due_at timestamptz,
  add column if not exists tasks_synced_at            timestamptz;

comment on column public.sales_pipeline_opportunity.last_completed_task_due_at is
  'Max due_date among COMPLETED GHL tasks for this opportunity''s contact. GHL exposes no completion timestamp; due date is the recency proxy for completed work (CNC-IT-SAL-005).';
