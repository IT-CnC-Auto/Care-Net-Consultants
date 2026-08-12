-- CNC MSP FORGE | KRN-SCH-01 v1.0.0 | Cognitive Kernel schema
-- Phase 1 migration 001. Additive only: every object is msp_ prefixed and
-- coexists with the host project schema. Applied to project ahp-production
-- per confirmation register item CR-13.1.

create table msp_industry (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  sic_reference text,
  regulatory_regime text not null check (regulatory_regime in ('OHSA','MHSA','DUAL')),
  created_at timestamptz default now()
);
comment on table msp_industry is 'Cognitive Kernel industry taxonomy. The taxonomy is data, not code: extending it is an insert, never a deploy.';

create table msp_subindustry (
  id uuid primary key default gen_random_uuid(),
  industry_id uuid not null references msp_industry(id),
  code text unique not null,
  name text not null,
  selectable boolean not null default false,
  notes text
);
comment on column msp_subindustry.selectable is 'True only when the subindustry role, hazard, and protocol map has passed kernel verification. The DocuSeal picker lists selectable rows only (Phase 6 gate).';

create table msp_job_role (
  id uuid primary key default gen_random_uuid(),
  subindustry_id uuid not null references msp_subindustry(id),
  title text not null,
  duties_summary text not null,
  inherent_physical_demands text,
  inherent_sensory_cognitive_demands text,
  statutory_competency_requirement text
);

create table msp_hazard (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  category text not null check (category in ('physical','chemical','biological','ergonomic','psychosocial')),
  oel_value numeric,
  oel_unit text,
  oel_basis text,
  oel_instrument text,
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified','verified','excluded'))
);
comment on table msp_hazard is 'Canonical hazard key A to O, extensible. An OEL is stored only with its citing instrument; unverified values never print in a released pack.';

create table msp_job_hazard (
  job_role_id uuid references msp_job_role(id),
  hazard_id uuid references msp_hazard(id),
  typical_exposure_rating text not null,
  rationale text not null,
  primary key (job_role_id, hazard_id)
);

create table msp_legal_instrument (
  id uuid primary key default gen_random_uuid(),
  short_name text not null,
  full_citation text not null,
  instrument_type text not null
    check (instrument_type in ('act','regulation','code','hpcsa','sans','guideline','circular')),
  gazette_reference text,
  effective_date date,
  amendment_history text,
  source_one text not null,
  source_two text not null,
  source_three text not null,
  verified_on date,
  verified_by text,
  review_due date,
  status text not null default 'pending'
    check (status in ('pending','verified','excluded','superseded')),
  constraint msp_instrument_verified_complete
    check (status <> 'verified'
           or (verified_on is not null and verified_by is not null and review_due is not null))
);
comment on table msp_legal_instrument is 'Triple verification protocol: source_one is the primary instrument (gate a), source_two an authoritative corroboration (gate b), source_three the currency check record (gate c). A source that cannot pass all three gates is excluded, not padded.';

create table msp_test_protocol (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references msp_hazard(id),
  test_name text not null,
  test_type text not null check (test_type in ('clinical','biological_monitoring','biological_effect')),
  baseline_required boolean not null default true,
  periodic_interval_months int not null check (periodic_interval_months >= 1),
  exit_required boolean not null default true,
  trigger_conditions text,
  biological_reference text,
  legal_basis_id uuid references msp_legal_instrument(id),
  constraint msp_interval_floor_citation
    check (periodic_interval_months <= 12 or legal_basis_id is not null)
);
comment on constraint msp_interval_floor_citation on msp_test_protocol is 'Twelve months is the periodic floor. A longer interval exists only with an instrument citation, and exceedances tighten, never loosen.';

create table msp_industry_instrument (
  industry_id uuid references msp_industry(id),
  instrument_id uuid references msp_legal_instrument(id),
  applicability_note text,
  primary key (industry_id, instrument_id)
);

create table msp_kernel_rule (
  id uuid primary key default gen_random_uuid(),
  rule_code text unique not null,
  description text not null,
  condition_expr jsonb not null,
  effect jsonb not null,
  instrument_id uuid references msp_legal_instrument(id),
  status text not null default 'pending' check (status in ('pending','verified','excluded'))
);
comment on table msp_kernel_rule is 'Routing and trigger rules encoded as data, not prose: ODMWA versus COIDA routing, night work trigger, PrDP trigger, noise instrument transition.';

create table msp_kernel_exclusion (
  id uuid primary key default gen_random_uuid(),
  candidate_citation text not null,
  failed_gate text not null check (failed_gate in ('a','b','c')),
  reason text not null,
  excluded_on date not null default current_date,
  excluded_by text not null
);
comment on table msp_kernel_exclusion is 'The exclusion register. An honest gap beats a confident guess.';

create table msp_confirmation_item (
  id uuid primary key default gen_random_uuid(),
  item_code text unique not null,
  kind text not null check (kind in ('confirm','assumption')),
  description text not null,
  status text not null default 'open' check (status in ('open','resolved','excluded')),
  resolution text,
  resolved_by text,
  resolved_on date
);
comment on table msp_confirmation_item is 'The consolidated confirmation register. No item is resolved by guesswork, and no released pack carries an open item.';

create index msp_subindustry_industry_idx on msp_subindustry(industry_id);
create index msp_job_role_subindustry_idx on msp_job_role(subindustry_id);
create index msp_test_protocol_hazard_idx on msp_test_protocol(hazard_id);
create index msp_job_hazard_hazard_idx on msp_job_hazard(hazard_id);
