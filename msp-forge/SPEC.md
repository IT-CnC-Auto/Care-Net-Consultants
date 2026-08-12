# CNC MSP FORGE: SYSTEM SPECIFICATION

Document Reference: CNC-MSP-FORGE-SPEC-V1.0-2026 | Version 1.0 | Date of Issue: 12/08/2026 | Classification: INTERNAL

Prepared under the CNC MSP FORGE Master Build Prompt V1.0 (CNC-MSP-FORGE-V1.0-2026). Phase 0 deliverable. This document is the complete system specification and stops at the Phase 0 gate. No build work proceeds until this specification is approved.

---

## 1. DOCUMENT CONTROL

1.1 Author governance. This specification is authored by Claude Code acting as clinical systems architect and document engineer for Care Net Consultants (Pty) Ltd, under the direction of the Director, who holds a BCom, a Postgraduate qualification in Taxation, an MBA, a Professional Masters in Artificial Intelligence, and is a Candidate Doctorate in Artificial Intelligence.

1.2 Version history.

| Version | Date | Change |
| --- | --- | --- |
| 1.0 | 12/08/2026 | Initial Phase 0 specification |

1.3 Canonical ancestors. This specification extends and never contradicts:
1.3.1 Medical Surveillance Plan, CNC-RPT-2026-0812-001, Version 1.1 (structure verified against the source document on 12/08/2026: classification banner, client metadata table, eleven numbered sections, OREP in Section 5, WASP in Section 6, dual sign off in Section 11).
1.3.2 Medical Surveillance Plan Client Information Questionnaire, CNC-QST-2026-0812-001, Version 1.2 (structure verified against the source document on 12/08/2026: nine numbered sections, hazard reference key A to O, declaration block).
1.3.3 The cnc-letterhead skill v1.0.0 (geometry values verified against the skill on 12/08/2026).

1.4 Reconciliation note. The Master Build Prompt describes the canonical questionnaire as having seven sections. The verified V1.2 instrument has nine: Company and Site Details, Regulatory and Compliance Context, Existing Risk Assessment and Occupational Hygiene Information, Workforce Profile, Job Categories and Exposure Identification, Current Medical Surveillance Arrangements, Incident and Occupational Disease History, Data Protection and Consent, and Declaration. The DocuSeal form specified in Section 5 of this document is a superset of all nine, extended with the industry picker, branding and delivery, and unbundled POPIA consent sections. Nothing from the canonical instrument is dropped.

1.5 Register. British English, South African register, ZAR with comma separation, legal style numbering, no dash or hyphen punctuation in prose, official instrument names retain their natural form.

---

## 2. SYSTEM OVERVIEW

2.1 CNC MSP FORGE converts a completed client onboarding form into a board ready Medical Surveillance Pack, correct to South African occupational health legislation per industry and subindustry, dual branded on the client letterhead position with CNC co branding, and POPIA compliant at every layer.

2.2 Engagement flow.
2.2.1 CNC sends the client the DocuSeal onboarding form (Subsystem A).
2.2.2 On submission, the DocuSeal webhook fires to a Vercel endpoint, which validates the payload against a JSON schema, normalises it, and writes it to Supabase under Row Level Security. Failed validation routes to human triage, never to silent correction.
2.2.3 The Generation Agent (Subsystem C) classifies the client into industry and subindustry, retrieves the regulatory frame, hazard map, and test protocols from the Cognitive Kernel (Subsystem B), and drafts the pack as structured data.
2.2.4 The Document Factory (Subsystem D) renders the dual branded DOCX, verifies geometry at pixel level, and produces the PDF.
2.2.5 The draft enters the OMP review queue. Only on recorded OMP approval is the pack released, routed for dual DocuSeal sign off, and archived.
2.2.6 Every step is logged to the append only audit table (Subsystem E).

2.3 Stack lock. Supabase (Postgres, RLS on every table, Auth, Storage, Edge Functions), Vercel (hosting, API routes, webhook receivers, background functions), DocuSeal (intake and signature, via MCP), the docx Node.js library with Python and Pillow pixel verification, soffice headless for PDF. No substitutions without confirmed instruction.

2.4 Governance boundaries, restated as build constraints.
2.4.1 CNC screens and provides preventive care and does not diagnose. The engine drafts; a registered Occupational Medical Practitioner approves. Release without recorded OMP approval is impossible at the database layer.
2.4.2 The agent never determines individual fitness for duty, never names a medical condition for a named person, and never adjudicates matters of legal consequence under South African labour law.
2.4.3 Mining lung disease follows the ODMWA route; all other sectors follow COIDA. The routing is a kernel rule, not prose.
2.4.4 The employer is always the payer. Charging receiving specialists for referrals is prohibited under HPCSA perverse incentive rules.
2.4.5 The limitation of liability block, the POPIA blocks, and the sign off blocks are inserted verbatim from locked templates and are never paraphrased by the agent.
2.4.6 WARDEN ring fence: no AutoHive, Glass Castle, or Think Tank SA content, branding, agents, or copy anywhere in this system. The CRM, where referenced, is AutoHive CRM by name only.

---

## 3. COMPONENT MANIFEST

3.1 Every component is anchored, versioned, and patchable. A revision targets one anchor, bumps that component version, and leaves every other component unchanged. Token estimates are build time estimates for generation and review of that component, stated to guide phase budgeting; they are engineering estimates, not commitments.

| Anchor | Component | Subsystem | Phase | Est. tokens |
| --- | --- | --- | --- | --- |
| KRN-SCH-01 | Kernel schema migration (taxonomy, hazards, protocols, instruments) | B | 1 | 12,000 |
| KRN-RLS-01 | RLS policies, roles, and grants for all kernel tables | B | 1 | 8,000 |
| KRN-VER-01 | Triple verification workflow (states, gates, exclusion register) | B | 1 | 10,000 |
| KRN-ING-01 | Ingestion tooling (instrument loader, verification recorder) | B | 1 | 15,000 |
| KRN-SEED-01 | Pilot industry seed: Construction, verified | B | 1 | 25,000 |
| KRN-PREC-01 | Precedent store (msp_precedent, pgvector, chunker, embedder) | B | 2 | 12,000 |
| FRM-DSL-01 | DocuSeal template build (field schema per Section 5) | A | 2 | 15,000 |
| FRM-WHK-01 | Vercel webhook receiver, JSON schema validation, triage routing | A | 2 | 12,000 |
| FRM-INT-01 | Intake persistence layer (normalised intake tables, mapping) | A | 2 | 10,000 |
| AGT-SDK-01 | Agent runtime scaffold (Claude Agent SDK, Vercel background function) | C | 3 | 12,000 |
| AGT-CLS-01 | CLASSIFY stage and schema | C | 3 | 8,000 |
| AGT-FRA-01 | FRAME stage and schema | C | 3 | 8,000 |
| AGT-PRO-01 | PROFILE stage and schema (OREP, exceedance, risk matrix) | C | 3 | 15,000 |
| AGT-PRE-01 | PRESCRIBE stage and schema (WASP, intervals, biological monitoring) | C | 3 | 15,000 |
| AGT-COM-01 | COMPOSE stage and schema (narrative, locked template insertion) | C | 3 | 12,000 |
| AGT-VAL-01 | VALIDATE stage, Sonnet audit agent, defect filing | C | 3 | 12,000 |
| AGT-QUE-01 | QUEUE stage, OMP queue writer | C | 3 | 6,000 |
| DOC-SKL-01 | cnc-msp-dualbrand skill (SKILL.md, image pipeline, geometry) | D | 4 | 15,000 |
| DOC-GEN-01 | DOCX generator (cover, control block, TOC, sections, annexures) | D | 4 | 30,000 |
| DOC-VER-01 | verify_geometry.py extension (logo boxes, clear space, collision) | D | 4 | 10,000 |
| DOC-PDF-01 | PDF conversion and artefact filing to Storage | D | 4 | 5,000 |
| DOC-SIG-01 | DocuSeal signature envelope for dual sign off | D | 4 | 6,000 |
| POP-AUD-01 | Append only msp_audit table, triggers, write paths | E | 5 | 8,000 |
| POP-OMP-01 | OMP review queue interface and database release gate | E | 5 | 18,000 |
| POP-REG-01 | Confirmation and exclusion registers surfaced in review interface | E | 5 | 8,000 |
| POP-DSR-01 | Data subject rights tooling (export, correction, deletion cascades) | E | 5 | 12,000 |
| POP-CON-01 | Consent record storage, wording versions, withdrawal mechanism | E | 5 | 6,000 |
| TAX-BAT-xx | Taxonomy scale out batches, one anchor per industry batch | B | 6 | 20,000 per batch |

3.2 Locked templates (content components, versioned like code, never paraphrased at generation time).

| Anchor | Template | Source |
| --- | --- | --- |
| TPL-LIA-01 | Limitation of liability compliance block and client acknowledgement | Verbatim from CNC-RPT-2026-0812-001 Section 4 and 11.2 |
| TPL-POP-01 | Confidentiality and POPIA section and POPIA note | Verbatim from CNC-RPT-2026-0812-001 Section 9 |
| TPL-SGN-01 | Dual sign off blocks (OMP approval, client acknowledgement) | Verbatim from CNC-RPT-2026-0812-001 Section 11 |
| TPL-EXA-01 | Examination type taxonomy table | Verbatim from CNC-RPT-2026-0812-001 Section 6.1 |
| TPL-CGN-01 | Compliance note pattern (surveillance detects early effect, does not substitute for control at source) | Verbatim from CNC-RPT-2026-0812-001 Section 5.2 note, generalised placeholders only |

---

## 4. SUPABASE SCHEMA

4.1 Design rules. Every table carries RLS. Kernel tables are readable by the agent role and writable only by the verifier role. Engagement tables are scoped to the engagement. The audit table is append only, enforced by revoking UPDATE and DELETE and by trigger. Release is gated in the database: a release row cannot exist without a matching approved OMP review row, enforced by foreign key and check trigger, not by the UI.

4.2 Cognitive Kernel tables (Subsystem B).

```sql
-- KRN-SCH-01
create table msp_industry (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,            -- e.g. CONSTR
  name text not null,                   -- e.g. Construction
  sic_reference text,                   -- SIC major division reference
  regulatory_regime text not null check (regulatory_regime in ('OHSA','MHSA','DUAL')),
  created_at timestamptz default now()
);

create table msp_subindustry (
  id uuid primary key default gen_random_uuid(),
  industry_id uuid not null references msp_industry(id),
  code text unique not null,            -- e.g. CONSTR-CIVILS
  name text not null,
  selectable boolean not null default false,  -- true only when the batch is kernel verified (Phase 6 gate)
  notes text
);

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
  code text unique not null,            -- A..O per canonical key, extensible
  name text not null,
  category text not null check (category in ('physical','chemical','biological','ergonomic','psychosocial')),
  oel_value numeric,
  oel_unit text,
  oel_basis text,                       -- e.g. 8 hour TWA
  oel_instrument text,                  -- citing regulation and schedule
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified','verified','excluded'))
);

create table msp_job_hazard (
  job_role_id uuid references msp_job_role(id),
  hazard_id uuid references msp_hazard(id),
  typical_exposure_rating text not null, -- Low|Moderate|High and blends
  rationale text not null,
  primary key (job_role_id, hazard_id)
);

create table msp_test_protocol (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references msp_hazard(id),
  test_name text not null,              -- audiometry, spirometry, chest X-ray, HbA1c...
  test_type text not null check (test_type in ('clinical','biological_monitoring','biological_effect')),
  baseline_required boolean not null default true,
  periodic_interval_months int not null check (periodic_interval_months >= 1),
  exit_required boolean not null default true,
  trigger_conditions text,
  biological_reference text,            -- reference values, [CONFIRM] until verified
  legal_basis_id uuid references msp_legal_instrument(id),
  -- an interval longer than the twelve month floor requires an instrument citation
  constraint interval_floor_citation
    check (periodic_interval_months <= 12 or legal_basis_id is not null)
);

create table msp_legal_instrument (
  id uuid primary key default gen_random_uuid(),
  short_name text not null,             -- e.g. NIHL Regulations
  full_citation text not null,
  instrument_type text not null
    check (instrument_type in ('act','regulation','code','hpcsa','sans','guideline','circular')),
  gazette_reference text,
  effective_date date,
  amendment_history text,
  source_one text not null,             -- gate (a): primary instrument
  source_two text not null,             -- gate (b): authoritative corroboration
  source_three text not null,           -- gate (c): currency check record
  verified_on date,
  verified_by text,
  review_due date,
  status text not null default 'pending'
    check (status in ('pending','verified','excluded','superseded')),
  -- a verified row must carry verifier, date, and review due date
  constraint verified_complete
    check (status <> 'verified' or (verified_on is not null and verified_by is not null and review_due is not null))
);

create table msp_industry_instrument (
  industry_id uuid references msp_industry(id),
  instrument_id uuid references msp_legal_instrument(id),
  applicability_note text,
  primary key (industry_id, instrument_id)
);

-- KRN-VER-01: kernel routing rules encoded as data, not prose (e.g. ODMWA versus COIDA)
create table msp_kernel_rule (
  id uuid primary key default gen_random_uuid(),
  rule_code text unique not null,       -- e.g. ROUTE-ODMWA-COIDA, TRIGGER-NIGHTWORK, TRIGGER-PRDP
  description text not null,
  condition_expr jsonb not null,        -- structured condition over intake and taxonomy fields
  effect jsonb not null,                -- structured effect (add instrument, set route, add battery)
  instrument_id uuid references msp_legal_instrument(id),
  status text not null default 'pending' check (status in ('pending','verified','excluded'))
);

-- KRN-VER-01: exclusion register
create table msp_kernel_exclusion (
  id uuid primary key default gen_random_uuid(),
  candidate_citation text not null,
  failed_gate text not null check (failed_gate in ('a','b','c')),
  reason text not null,
  excluded_on date not null default current_date,
  excluded_by text not null
);

-- KRN-PREC-01: precedent store (house style and depth, never legal truth)
create table msp_precedent (
  id uuid primary key default gen_random_uuid(),
  source_name text not null,
  source_type text not null check (source_type in ('industry_guide','academy_metadata','approved_plan')),
  industry_id uuid references msp_industry(id),
  chunk_index int not null,
  content text not null,
  embedding vector(1536),
  ingested_at timestamptz default now()
);
```

4.3 Engagement and intake tables (Subsystems A and E).

```sql
-- FRM-INT-01
create table msp_client (
  id uuid primary key default gen_random_uuid(),
  registered_name text not null,
  trading_name text,
  registration_number text,
  vat_number text,
  head_office_address text,
  created_at timestamptz default now()
);

create table msp_engagement (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references msp_client(id),
  reference text unique not null,       -- CNC-MSP-YYYY-MMDD-NNN
  status text not null default 'intake'
    check (status in ('intake','triage','classifying','drafting','validating',
                      'omp_queue','approved','released','rejected','archived')),
  industry_id uuid references msp_industry(id),
  subindustry_id uuid references msp_subindustry(id),
  classification_confidence numeric,
  created_at timestamptz default now()
);

create table msp_intake (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  docuseal_submission_id text not null,
  raw_payload jsonb not null,           -- validated payload as received, no special personal information by design
  schema_version text not null,
  received_at timestamptz default now(),
  validation_status text not null check (validation_status in ('valid','triage')),
  triage_reason text
);

create table msp_intake_site (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  site_name text not null,
  site_address text,
  activity text,
  headcount int
);

create table msp_intake_job_category (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  row_no int not null,
  title text not null,
  headcount int,
  duties text,
  hazard_codes text[],                  -- subset of the A to O key
  existing_controls text,
  physical_demands text,
  sensory_cognitive_demands text,
  statutory_requirement text,
  chronic_flag boolean not null default false,  -- aggregate flag only, no individual ever named
  rpe_issued text,
  rpe_fit_tested text,
  rpe_fit_test_interval text,
  other_ppe text
);

create table msp_intake_exposure (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  hazard_location text not null,
  measured_level text not null,
  unit text,
  stated_oel text,
  date_measured date
);

create table msp_intake_chemical (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  substance_name text not null,
  sds_reference text,
  task_process text,
  frequency text,
  quantity_per_use text,
  controls text
);

create table msp_intake_file (
  id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references msp_intake(id),
  file_kind text not null check (file_kind in ('risk_assessment','hygiene_report','sds','client_logo','other')),
  storage_path text not null,
  original_filename text,
  uploaded_at timestamptz default now()
);

-- POP-CON-01
create table msp_consent (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  consent_kind text not null check (consent_kind in ('processing','marketing','popia_forms_election')),
  granted boolean not null,
  wording_version text not null,
  granted_at timestamptz not null,
  withdrawal_contact text not null,
  withdrawn_at timestamptz
);
```

4.4 Draft, review, release, and audit tables (Subsystems C, D, E).

```sql
-- AGT stages write one row per stage output
create table msp_draft (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  stage text not null check (stage in ('classify','frame','profile','prescribe','compose','validate')),
  stage_output jsonb not null,          -- validated against the stage schema before insert
  schema_version text not null,
  model_used text not null,
  created_at timestamptz default now()
);

create table msp_defect (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  stage text not null,
  defect_code text not null,            -- e.g. CITATION-UNRESOLVED, INTERVAL-NO-BASIS, PROSE-RULE
  detail jsonb not null,
  blocking boolean not null default true,
  created_at timestamptz default now()
);

-- POP-OMP-01: the release gate lives here, in the database
create table msp_omp_review (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  draft_id uuid not null references msp_draft(id),
  decision text check (decision in ('approved','amended','rejected')),
  omp_name text,
  omp_hpcsa_number text,
  decided_at timestamptz,
  amendment_notes jsonb,
  constraint decision_complete
    check (decision is null or (omp_name is not null and omp_hpcsa_number is not null and decided_at is not null))
);

create table msp_release (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  omp_review_id uuid not null references msp_omp_review(id),
  docx_path text not null,
  pdf_path text not null,
  docuseal_envelope_id text,
  released_at timestamptz default now()
);
-- trigger: before insert on msp_release, assert the referenced msp_omp_review row
-- has decision = 'approved'; otherwise raise. Enforced in the database, not the UI.

create table msp_document (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references msp_engagement(id),
  artefact_kind text not null check (artefact_kind in ('docx','pdf','signature_envelope','geometry_report')),
  storage_path text not null,
  version int not null,
  created_at timestamptz default now()
);

-- POP-AUD-01: append only, UPDATE and DELETE revoked, trigger blocks both
create table msp_audit (
  id bigint generated always as identity primary key,
  engagement_id uuid,
  actor text not null,                  -- system|agent|audit_agent|omp:<name>|webhook|admin
  event_type text not null,             -- intake_received, classified, kernel_citation_used, draft_created,
                                        -- defect_filed, omp_decision, release, export, deletion, consent
  event_detail jsonb not null,
  created_at timestamptz default now()
);

-- POP-REG-01: consolidated confirmation register (Section 9 items live here)
create table msp_confirmation_item (
  id uuid primary key default gen_random_uuid(),
  item_code text unique not null,       -- e.g. CR-12.1
  kind text not null check (kind in ('confirm','assumption')),
  description text not null,
  status text not null default 'open' check (status in ('open','resolved','excluded')),
  resolution text,
  resolved_by text,
  resolved_on date
);
```

4.5 RLS policy outline (KRN-RLS-01, full policies delivered in Phase 1).
4.5.1 Roles: forge_agent (kernel read, engagement scoped read and write on drafts), forge_verifier (kernel write), forge_omp (review queue read and write, decision insert), forge_admin (registers, triage), forge_webhook (intake insert only), forge_service (Document Factory, Storage paths).
4.5.2 Every engagement scoped table policy filters on engagement_id membership for the requesting role. Kernel tables are world readable inside the project and writable only by forge_verifier. msp_audit accepts INSERT from all roles and nothing else. Anonymous access is denied everywhere.
4.5.3 Storage buckets: intake_uploads (webhook write, agent read), packs (service write, OMP read, released copies readable by delivery flow), all private, engagement prefixed paths, no personal data in URL parameters (signed URLs only, short expiry).

---

## 5. DOCUSEAL FIELD SCHEMA

5.1 Field naming. Stable snake_case, mapping one to one onto the intake tables. Repeating structures use indexed prefixes with fixed capacity: sites site_1 to site_6, contacts contact_1 to contact_3, exposures exposure_1 to exposure_8, jobs job_1 to job_12, chemicals chem_1 to chem_10, RPE rows rpe_1 to rpe_8. Overflow beyond capacity is handled by file attachment and flagged for triage. Field types: text, textarea, select, multiselect, checkbox, date, number, file.

5.2 Section 1. Company and site details.

| Field | Type | Required |
| --- | --- | --- |
| company_registered_name | text | yes |
| company_trading_name | text | no |
| company_registration_number | text | yes |
| company_vat_number | text | no |
| company_head_office_address | textarea | yes |
| site_n_name, site_n_address, site_n_activity, site_n_headcount | text, textarea, text, number | site_1 yes |
| company_core_industry_freetext | text | yes |
| company_years_operating | number | yes |
| contact_n_role, contact_n_name, contact_n_position, contact_n_email, contact_n_phone | text | contact_1 yes |

5.3 Section 2. Regulatory and compliance context.

| Field | Type | Required |
| --- | --- | --- |
| reg_ohsa, reg_construction, reg_mhsa, reg_hca, reg_nihl, reg_asbestos, reg_lead, reg_hba, reg_ergonomics, reg_nrta_prdp, reg_nightwork_code | checkbox | no |
| reg_other_detail | textarea | no |
| coida_registered | select yes/no | yes |
| coida_class_tariff_number | text | no |
| enforcement_notice_3yr | select yes/no | yes |
| enforcement_notice_detail | textarea | conditional |
| third_party_cert_required | select yes/no | yes |
| third_party_cert_detail (party, format, validity period) | textarea | conditional |

5.4 Section 3. Risk assessment and hygiene evidence.

| Field | Type | Required |
| --- | --- | --- |
| ra_exists | select yes/no | yes |
| ra_date, ra_conducted_by, ra_assessor_accreditation, ra_next_review_date | date, text, text, date | conditional |
| ra_file | file | conditional |
| hygiene_results_exist | select yes/no | yes |
| hygiene_date, hygiene_conducted_by | date, text | conditional |
| hygiene_file | file | conditional |
| exposure_n_hazard_location, exposure_n_measured_level, exposure_n_unit, exposure_n_oel, exposure_n_date | text, text, text, text, date | no |
| process_change_since_ra | select yes/no | yes |
| process_change_detail | textarea | conditional |
| sds_files | file, multiple | no |

5.5 Section 4. Workforce profile.

| Field | Type | Required |
| --- | --- | --- |
| workforce_total | number | yes |
| workforce_permanent, workforce_contract, workforce_temporary, workforce_other | number | no |
| shift_night_work | select yes/no | yes |
| shift_pattern_detail | textarea | conditional |
| nightwork_medical_current, nightwork_medical_interval | select yes/no, text | conditional |
| employees_under_18 | select yes/no | yes |
| pregnancy_exposed_roles | select yes/no | yes |
| hs_committee_present | select yes/no | yes |
| chronic_flag_present | select yes/no | yes |
| chronic_flag_categories | textarea, aggregate categories only, form text states no individual is ever named | conditional |

5.6 Section 5. Job categories (one indexed block per category, hazard key A to O displayed on form).

| Field | Type | Required |
| --- | --- | --- |
| job_n_title | text | job_1 yes |
| job_n_headcount | number | job_1 yes |
| job_n_duties | textarea | job_1 yes |
| job_n_hazards | multiselect A to O | job_1 yes |
| job_n_controls | textarea | no |
| job_n_physical_demands, job_n_sensory_cognitive_demands, job_n_statutory_requirement | textarea | no |
| job_n_rpe_issued, job_n_rpe_fit_tested, job_n_rpe_fit_test_interval, job_n_other_ppe | text | no |
| chem_n_name, chem_n_sds_ref, chem_n_task, chem_n_frequency, chem_n_quantity, chem_n_controls | text | no |
| hazard_additional_detail | textarea | no |

5.7 Section 6. Current medical surveillance arrangements (carried from canonical Section 6).

| Field | Type | Required |
| --- | --- | --- |
| current_medicals_exist | select yes/no | yes |
| current_provider, last_cycle_date, current_tests_detail | text, date, textarea | conditional |
| outstanding_referrals | select yes/no | yes |
| records_format | text | no |

5.8 Section 7. Incident and occupational disease history (carried from canonical Section 7).

| Field | Type | Required |
| --- | --- | --- |
| injuries_3yr, coida_claims_3yr, modified_duties_current | select yes/no | yes |
| incident_history_detail | textarea | conditional |

5.9 Section 8. Industry and subindustry selection (new).

| Field | Type | Required |
| --- | --- | --- |
| industry_code | select, options generated from msp_industry | yes |
| subindustry_code | select, options generated from msp_subindustry where selectable | yes |
| industry_other_detail | textarea, selecting Other routes the engagement to human triage and never auto generates | conditional |

5.10 Section 9. Branding and delivery (new).

| Field | Type | Required |
| --- | --- | --- |
| client_logo | file, PNG or SVG, minimum 600 px wide stated on form, transparent background preferred | yes |
| brand_colour_hex | text | no |
| certificate_format_preference | textarea | no |
| delivery_contact_name, delivery_contact_email | text | yes |

5.11 Section 10. POPIA notices and consent, unbundled (extends canonical Section 8).

| Field | Type | Required |
| --- | --- | --- |
| information_officer_name, information_officer_contact | text | yes |
| employees_informed_before_exam | select yes/no | yes |
| consent_processing | checkbox, wording states the specific purpose of designing the medical surveillance programme, the withdrawal contact, and cites the Protection of Personal Information Act 4 of 2013 by full name | yes |
| consent_marketing | checkbox, separate, default off | no |
| popia_forms_election | select: use Care Net standard forms, or provide own | yes |

5.12 Section 11. Declaration. The canonical declaration wording (accuracy, reliance, duty to notify of change) carried verbatim, followed by the DocuSeal signature, full name, position, company, and date fields.

5.13 Hard rule. No field requests special personal information about an identifiable individual. No clinical data flows through this form. Aggregate job category flags only. The webhook validator rejects any payload pattern that appears to contain an identity number or a named individual medical detail in the chronic flag fields and routes it to triage with the offending field masked in logs.

---

## 6. AGENT PIPELINE CONTRACT

6.1 Runtime. Claude Agent SDK (TypeScript), deployed as a Vercel background function triggered by the intake webhook. Drafting pass on an Opus class model; independent validation pass on a Sonnet class model as the audit agent. Supabase is the agent's memory; the kernel is its only source of legal truth. Each stage emits JSON validated against the stage schema before the next stage runs; a validation failure files a defect and halts the pipeline.

6.2 Honesty contract, enforced in schema. Every legal citation field is a kernel row reference (instrument_id), never free text. Every numeric threshold carries a source discriminator: kernel, intake, or unresolved. Unresolved items carry omp_note and are excluded from the rendered draft; they are routed to the OMP queue. The agent presents two readings when intake is ambiguous and selects the more protective default, recording the choice in omp_notes.

6.3 Stage schemas (contract skeletons; full JSON Schema files delivered in Phase 3 as AGT-CLS-01 through AGT-QUE-01).

6.3.1 CLASSIFY output.

```json
{
  "$id": "classify.v1",
  "type": "object",
  "required": ["engagement_id", "industry_code", "subindustry_code", "confidence", "rationale", "triage"],
  "properties": {
    "engagement_id": {"type": "string", "format": "uuid"},
    "industry_code": {"type": "string"},
    "subindustry_code": {"type": "string"},
    "confidence": {"type": "number", "minimum": 0, "maximum": 1},
    "rationale": {"type": "string"},
    "triage": {"type": "boolean", "description": "true when confidence is below 0.85 or the client selected Other; halts the pipeline"}
  }
}
```

6.3.2 FRAME output.

```json
{
  "$id": "frame.v1",
  "type": "object",
  "required": ["engagement_id", "instruments", "compensation_route", "triggered_additions"],
  "properties": {
    "engagement_id": {"type": "string", "format": "uuid"},
    "instruments": {"type": "array", "items": {
      "type": "object",
      "required": ["instrument_id", "applicability"],
      "properties": {
        "instrument_id": {"type": "string", "format": "uuid", "description": "must resolve to msp_legal_instrument with status verified"},
        "applicability": {"type": "string"}
      }
    }},
    "compensation_route": {"type": "string", "enum": ["COIDA", "ODMWA", "DUAL"], "description": "set by kernel rule ROUTE-ODMWA-COIDA, never by prose reasoning"},
    "triggered_additions": {"type": "array", "items": {
      "type": "object",
      "required": ["rule_code", "instrument_id", "trigger_source"],
      "properties": {
        "rule_code": {"type": "string"},
        "instrument_id": {"type": "string", "format": "uuid"},
        "trigger_source": {"type": "string", "description": "the intake field that fired the rule, e.g. shift_night_work"}
      }
    }}
  }
}
```

6.3.3 PROFILE output (OREP).

```json
{
  "$id": "profile.v1",
  "type": "object",
  "required": ["engagement_id", "jobs", "exceedances", "chemical_register"],
  "properties": {
    "engagement_id": {"type": "string", "format": "uuid"},
    "jobs": {"type": "array", "items": {
      "type": "object",
      "required": ["intake_job_id", "kernel_role_id", "title", "headcount", "duties",
                   "hazards", "inherent_requirements", "risk_matrix"],
      "properties": {
        "intake_job_id": {"type": "string", "format": "uuid"},
        "kernel_role_id": {"type": ["string", "null"], "format": "uuid"},
        "title": {"type": "string"},
        "headcount": {"type": "integer"},
        "duties": {"type": "string"},
        "hazards": {"type": "array", "items": {
          "type": "object",
          "required": ["hazard_id", "exposure_rating", "rationale"],
          "properties": {
            "hazard_id": {"type": "string", "format": "uuid"},
            "exposure_rating": {"type": "string"},
            "rationale": {"type": "string"}
          }
        }},
        "inherent_requirements": {"type": "object",
          "required": ["physical", "sensory_cognitive", "statutory"],
          "properties": {
            "physical": {"type": "string"},
            "sensory_cognitive": {"type": "string"},
            "statutory": {"type": "string"}
          }
        },
        "risk_matrix": {"type": "array", "items": {
          "type": "object",
          "required": ["hazard_id", "likelihood", "severity", "exposure_rating",
                       "control_adequacy", "residual_risk", "rationale"],
          "properties": {
            "hazard_id": {"type": "string", "format": "uuid"},
            "likelihood": {"type": "integer", "minimum": 1, "maximum": 5},
            "severity": {"type": "integer", "minimum": 1, "maximum": 5},
            "exposure_rating": {"type": "string"},
            "control_adequacy": {"type": "string", "enum": ["adequate", "partial", "inadequate", "unknown"]},
            "residual_risk": {"type": "string", "enum": ["low", "moderate", "high", "critical"]},
            "rationale": {"type": "string", "description": "every number traces to intake data or kernel data"}
          }
        }}
      }
    }},
    "exceedances": {"type": "array", "items": {
      "type": "object",
      "required": ["intake_exposure_id", "hazard_id", "measured", "oel_source", "assessment"],
      "properties": {
        "intake_exposure_id": {"type": "string", "format": "uuid"},
        "hazard_id": {"type": ["string", "null"], "format": "uuid"},
        "measured": {"type": "string"},
        "oel_source": {"type": "string", "enum": ["kernel", "intake_stated", "unresolved"]},
        "assessment": {"type": "string", "enum": ["within", "borderline", "exceeds", "significantly_exceeds", "unresolved"]}
      }
    }},
    "chemical_register": {"type": "array", "items": {"type": "object"}}
  }
}
```

6.3.4 PRESCRIBE output (WASP).

```json
{
  "$id": "prescribe.v1",
  "type": "object",
  "required": ["engagement_id", "programmes"],
  "properties": {
    "engagement_id": {"type": "string", "format": "uuid"},
    "programmes": {"type": "array", "items": {
      "type": "object",
      "required": ["job_title", "baseline", "periodic", "exit", "transfer", "return_to_work", "trigger_exams", "biological_monitoring"],
      "properties": {
        "job_title": {"type": "string"},
        "baseline": {"type": "array", "items": {"$ref": "#/$defs/test"}},
        "periodic": {"type": "array", "items": {"$ref": "#/$defs/periodic_test"}},
        "exit": {"type": "array", "items": {"$ref": "#/$defs/test"}, "minItems": 1,
                 "description": "exit medicals are never omitted"},
        "transfer": {"type": "array", "items": {"$ref": "#/$defs/test"}},
        "return_to_work": {"type": "array", "items": {"$ref": "#/$defs/test"}},
        "trigger_exams": {"type": "array", "items": {"$ref": "#/$defs/test"}},
        "biological_monitoring": {"type": "array", "items": {"$ref": "#/$defs/bio_test"}}
      }
    }},
    "$defs": {
      "test": {
        "type": "object",
        "required": ["protocol_id", "test_name", "hazard_justification", "eea_s7_justification"],
        "properties": {
          "protocol_id": {"type": "string", "format": "uuid", "description": "must resolve to msp_test_protocol"},
          "test_name": {"type": "string"},
          "hazard_justification": {"type": "string"},
          "eea_s7_justification": {"type": "string", "description": "the inherent job requirement this test serves"}
        }
      },
      "periodic_test": {
        "allOf": [{"$ref": "#/$defs/test"}],
        "required": ["interval_months", "interval_basis"],
        "properties": {
          "interval_months": {"type": "integer", "minimum": 1},
          "interval_basis": {"type": "string",
            "description": "twelve months is the floor; a longer interval requires instrument_id citation; exceedances tighten, never loosen"}
        }
      },
      "bio_test": {
        "allOf": [{"$ref": "#/$defs/test"}],
        "required": ["reference_status"],
        "properties": {
          "reference_status": {"type": "string", "enum": ["kernel_verified", "unresolved"],
            "description": "unresolved reference values route to the OMP queue and are not printed"}
        }
      }
    }
  }
}
```

6.3.5 COMPOSE output.

```json
{
  "$id": "compose.v1",
  "type": "object",
  "required": ["engagement_id", "sections", "locked_blocks", "omp_notes"],
  "properties": {
    "engagement_id": {"type": "string", "format": "uuid"},
    "sections": {"type": "array", "items": {
      "type": "object",
      "required": ["section_no", "heading", "blocks"],
      "properties": {
        "section_no": {"type": "string"},
        "heading": {"type": "string"},
        "blocks": {"type": "array", "items": {
          "type": "object",
          "required": ["kind"],
          "properties": {
            "kind": {"type": "string", "enum": ["paragraph", "table", "list", "locked_template", "annexure"]},
            "text": {"type": "string"},
            "table": {"type": "object"},
            "template_anchor": {"type": "string", "description": "e.g. TPL-LIA-01, inserted verbatim at render"}
          }
        }}
      }
    }},
    "locked_blocks": {"type": "array", "items": {"type": "string"},
      "description": "every locked template anchor that must appear; VALIDATE asserts presence"},
    "omp_notes": {"type": "array", "items": {
      "type": "object",
      "required": ["note_kind", "detail"],
      "properties": {
        "note_kind": {"type": "string", "enum": ["unresolved_value", "ambiguity_resolved_protective", "clinical_flag"]},
        "detail": {"type": "string"}
      }
    }}
  }
}
```

6.3.6 VALIDATE output.

```json
{
  "$id": "validate.v1",
  "type": "object",
  "required": ["engagement_id", "passed", "checks", "defects"],
  "properties": {
    "engagement_id": {"type": "string", "format": "uuid"},
    "passed": {"type": "boolean"},
    "checks": {"type": "array", "items": {
      "type": "object",
      "required": ["check_code", "result"],
      "properties": {
        "check_code": {"type": "string", "enum": [
          "CITATIONS_RESOLVE_VERIFIED", "INTERVALS_HAVE_BASIS", "ODMWA_COIDA_ROUTE_CORRECT",
          "NO_INDIVIDUAL_CLINICAL_DETAIL", "NO_CONFIRM_ASSUMPTION_TAGS", "PROSE_RULE_HOLDS",
          "BRITISH_ENGLISH_HOLDS", "NUMBERS_TRACE_TO_SOURCE", "LOCKED_BLOCKS_PRESENT_VERBATIM",
          "EXIT_MEDICALS_PRESENT", "DUAL_JUSTIFICATION_PRESENT", "ZAR_FORMAT_HOLDS"
        ]},
        "result": {"type": "string", "enum": ["pass", "fail"]},
        "detail": {"type": "string"}
      }
    }},
    "defects": {"type": "array", "items": {
      "type": "object",
      "required": ["defect_code", "blocking", "detail"],
      "properties": {
        "defect_code": {"type": "string"},
        "blocking": {"type": "boolean"},
        "detail": {"type": "object"}
      }
    }}
  }
}
```

6.3.7 QUEUE output: writes the validated draft reference to msp_omp_review with decision null, sets engagement status omp_queue, and records the diff friendly section structure so the OMP amends sections, not the whole document. No schema beyond the insert contract; the queue row is the handover.

6.4 Failure semantics. Any stage schema failure, any VALIDATE blocking defect, or any CLASSIFY triage flag halts the pipeline, files defects, sets the engagement status accordingly, and logs to msp_audit. Nothing renders and nothing releases from a failed pipeline.

---

## 7. DUAL BRANDING SKILL OUTLINE: cnc-msp-dualbrand

7.1 Delivery. A new skill folder cnc-msp-dualbrand with SKILL.md and valid YAML frontmatter, extending cnc-letterhead v1.0.0. The letterhead skill remains the base layer for page geometry: A4 (11,906 by 16,838 DXA), margins per the letterhead specification (left and right 1,440 DXA; first page top 2,520 DXA, subsequent 1,440 DXA; bottom 2,700 DXA), header first page only, footer all pages, pixel verification before any pack ships.

7.2 SKILL.md contents.
7.2.1 Frontmatter: name cnc-msp-dualbrand, version 1.0.0, description with triggers (dual branded MSP pack, client co branded document, MSP FORGE render).
7.2.2 Header band specification: CNC logo fixed left, occupying the letterhead header position; client logo right aligned within the header band, proportionally scaled to the CNC logo cap height band; minimum clear space between marks of at least one CNC logo cap height; exact EMU and DXA values derived from the letterhead specification at Phase 4 and locked into the skill.
7.2.3 Client logo pipeline (prepare_client_logo.py, Pillow): accept PNG or SVG (SVG rasterised at 300 DPI), normalise transparency, validate minimum 600 px width, scale proportionally to the cap height band, pad to the clear space rule. Lossless corrections applied automatically; lossy cases (low resolution, opaque background that cannot be cleanly keyed, extreme aspect ratio) route to human review with the reason stated.
7.2.4 Footer: the letterhead footer image on every page, plus the locked footer line on every page and the cover: Proudly prepared by the Care Net Consultants Team. Your Partner in Workplace Health. Page numbers in the footer safe zone defined by the letterhead skill.
7.2.5 Geometry verification: verify_geometry.py extended to assert both logo bounding boxes, the clear space between them, footer line presence, page number presence, and zero collision with body text, failing the build on any violation. Construction over correction: the layout is enforced structurally.
7.2.6 Brand constants: red #ED1B24, charcoal #1A1A1A, white, Arial throughout, table shading via ShadingType.CLEAR, table headers charcoal with white text, accent rules in red.

7.3 Pack render order (DOC-GEN-01): branded cover (client name, title, CNC-MSP-YYYY-MMDD-NNN reference, version, date, classification banner), document control block (version history, author governance, OMP approval record, next review date), table of contents accurate to three levels with page numbers, executive summary written last and never exceeding two pages, Sections 1 to 11 per the canonical Plan V1.1 structure enriched with the full risk matrix per job in the OREP, the biological monitoring schedule and examination type taxonomy in the WASP, the Regulatory Frame annexure listing every applicable instrument with full citation from the kernel, then annexures: employee to job category register template (last four ID digits only), chemical register extract, RPE and fit testing register, twelve month surveillance calendar, and the source list drawn from verified kernel rows presented once at the end with no in text citations.

---

## 8. POPIA COMPLIANCE LAYER SPECIFICATION

8.1 Lawful basis and purpose limitation. All intake data is processed for the sole specified purpose of designing the medical surveillance programme. Marketing repurposing requires the separate, default off marketing consent. Consent records persist in msp_consent with timestamp, wording version, and withdrawal mechanism.

8.2 Data minimisation. No full identity numbers anywhere (registers carry last four digits only). No individual clinical detail stored or printed. No special personal information through the public form; aggregate job category flags only, with webhook pattern rejection per 5.13.

8.3 Security safeguards. RLS on every table per 4.5, engagement scoped access, encrypted storage, HTTPS only, signed short expiry URLs, no personal data in URL parameters. Register of Operators covering DocuSeal, Vercel, Supabase, and Anthropic, each requiring a Data Processing Agreement (CR-12.5, open). Cross border transfer disclosed in the CNC privacy policy per POPIA section 72.

8.4 Data subject rights. Engagement export function (PDF or CSV of everything held), correction workflow, deletion workflow cascading through Storage subject to the audit retention rules. Retention periods per record class resolve through the confirmation register (CR-12.4) before production; occupational health records carry long statutory retention and never default to short cycles.

8.5 Audit. msp_audit is append only and records every classification, kernel citation used, agent draft, OMP decision, and release, so any pack can be reconstructed and defended line by line.

8.6 The Information Officer is named in every pack's POPIA block and in the system privacy notice (CR-12.6, open).

---

## 9. CONSOLIDATED CONFIRMATION REGISTER

9.1 The register is data (msp_confirmation_item) surfaced in the Phase 5 review interface. Opening state:

| Code | Kind | Item | Status |
| --- | --- | --- | --- |
| CR-12.1 | CONFIRM | Exact OEL values and schedules per hazard at kernel ingestion | Open |
| CR-12.2 | CONFIRM | COIDA Circular Instruction numbers and current versions | Open |
| CR-12.3 | CONFIRM | SANS standard numbers and editions for audiometry, noise, and spirometry method | Open |
| CR-12.4 | CONFIRM | Statutory retention periods per occupational health record class | Open |
| CR-12.5 | CONFIRM | DPA status for DocuSeal, Vercel, Supabase, and Anthropic as operators | Open |
| CR-12.6 | CONFIRM | CNC Information Officer name and privacy contact for the POPIA blocks | Open |
| CR-12.7 | CONFIRM | Designated OMP name and HPCSA practice number per engagement | Open |
| CR-12.8 | ASSUMPTION | Location and format of existing CNC industry guides and academy metadata for precedent ingestion | Open |
| CR-12.9 | ASSUMPTION | Availability of helena-copywriting skill assets in the build environment; if absent the voice rules of Master Prompt Section 9.1 govern directly (current environment check: not present; voice rules govern) | Open |
| CR-12.10 | ASSUMPTION | DocuSeal plan supports required file upload field types and webhook payloads at production volume | Open |
| CR-13.1 | CONFIRM | Target Supabase project (existing CNC project or new dedicated project) before Phase 1 migration | Open |
| CR-13.2 | CONFIRM | Target Vercel team and project for webhook receiver and agent runtime before Phase 2 | Open |
| CR-13.3 | CONFIRM | CNC telephone and email for the questionnaire contact line (placeholders [Telephone] and [Email] in canonical V1.2) | Open |
| CR-13.4 | CONFIRM | Source assets for the CNC logo mark used in the dual brand header band (the letterhead images are full width strips; a standalone mark may be needed for cap height matching) | Open |
| CR-13.5 | CONFIRM | Classification banner values for generated packs (canonical uses CLASSIFICATION: CLIENT) | Open |
| CR-13.6 | CONFIRM | Whether the Ubuntu closing line, I am because we are, carries into generated packs alongside the locked footer line (both appear in canonical artefacts) | Open |
| CR-13.7 | ASSUMPTION | CLASSIFY triage confidence threshold set at 0.85 pending calibration in Phase 3 | Open |

9.2 Resolution discipline. No item is resolved by guesswork. CONFIRM items resolve only against verified kernel rows or explicit confirmed instruction. Final client deliverables never carry CONFIRM or ASSUMPTION tags; unresolved items route to the OMP review queue instead of being printed.

---

## 10. PHASE GATES

| Phase | Scope | Gate deliverable | Status |
| --- | --- | --- | --- |
| 0 | This specification | SPEC approved | Delivered, awaiting approval |
| 1 | Kernel foundation, RLS, verification workflow, Construction seed | Verified pilot kernel | Blocked on Phase 0 gate and CR-13.1 |
| 2 | DocuSeal template, webhook, intake persistence, synthetic end to end test | Valid synthetic intake in Supabase | Blocked on Phase 1 gate and CR-13.2 |
| 3 | Generation Agent pipeline, validated structured draft for pilot industry | Draft passes VALIDATE | Blocked on Phase 2 gate |
| 4 | Document Factory, cnc-msp-dualbrand, pilot pack rendered and pixel verified | Pilot pack DOCX, PDF, envelope | Blocked on Phase 3 gate and CR-13.4 |
| 5 | POPIA hardening, OMP queue, audit, registers in review interface | Release gate enforced in database | Blocked on Phase 4 gate |
| 6 | Taxonomy scale out in verified batches | Each batch selectable only when verified | Blocked on Phase 5 gate, per batch |

END OF SPECIFICATION. Phase 0 stops here pending approval.
