-- CNC-IT-SAL icon enrichment (MD request 22/07/2026, relayed via Odendaal)
-- Additive only: classification flags computed at sync time from a read-only
-- Nexus RPC. No existing column or data is modified.
alter table public.sales_pipeline_opportunity
  add column if not exists is_existing_client boolean,
  add column if not exists client_evidence text
    check (client_evidence in ('mco','xero','mco+xero'));

comment on column public.sales_pipeline_opportunity.is_existing_client is
  'True when the opportunity company name-matches a Nexus integration_company row with MCO or Xero evidence. Computed read-only by sync-pipeline-from-nexus; NULL = not yet classified.';
comment on column public.sales_pipeline_opportunity.client_evidence is
  'Which systems evidence the client relationship: mco, xero, or mco+xero. NULL when is_existing_client is false or unclassified.';
