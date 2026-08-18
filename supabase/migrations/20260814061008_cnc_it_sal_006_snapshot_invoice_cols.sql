-- CNC-IT-SAL-006 · invoice-signal columns on the pipeline snapshot
alter table public.sales_pipeline_opportunity
  add column if not exists invoiced_since_lead_count integer,
  add column if not exists invoiced_since_lead_total numeric(14,2),
  add column if not exists last_invoice_date         date,
  add column if not exists invoices_synced_at        timestamptz;

comment on column public.sales_pipeline_opportunity.invoiced_since_lead_count is
  'Count of Xero AUTHORISED/PAID invoices dated on/after this lead''s creation, for the name-matched Xero contact (CNC-IT-SAL-006). Strongest conversion evidence available to the Daily Brief.';
