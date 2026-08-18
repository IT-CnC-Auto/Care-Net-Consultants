alter table public.sales_pipeline_opportunity
  add column if not exists invoice_contact_key text;
comment on column public.sales_pipeline_opportunity.invoice_contact_key is
  'Xero contact id backing the invoice signal; dedup key when duplicate open leads share one company (CNC-IT-SAL-006).';
