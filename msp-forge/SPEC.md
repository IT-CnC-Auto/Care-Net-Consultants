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


---
---

# PART B. CNC HSF FORGE: SYSTEM SPECIFICATION

Document Reference: CNC-HSF-FORGE-SPEC-V1.0-2026 | Version 1.0 | Date of Issue: 23/09/2026 | Classification: INTERNAL

Prepared under the CNC HSF FORGE Master Build Prompt V1.0 (CNC-HSF-FORGE-V1.0-2026, held in this repository as HSF-FORGE-BUILD-PROMPT.md). Phase 1 deliverable. Part A above (the MSP FORGE specification) stands in full; Part B extends it and never contradicts it. No build work for HSF FORGE proceeds until the Director approves this Part.

---

## B1. DOCUMENT CONTROL

B1.1 Author governance. Authored by Claude Code acting as occupational health and safety systems architect and document engineer for Care Net Consultants (Pty) Ltd, under the direction of the Director.

B1.2 Version history.

| Version | Date | Change |
| --- | --- | --- |
| 1.0 | 23/09/2026 | Initial Phase 1 specification for HSF FORGE |

B1.3 Canonical ancestors. This Part extends and never contradicts:
B1.3.1 Part A of this document (CNC-MSP-FORGE-SPEC-V1.0-2026).
B1.3.2 SOP-KERNEL-AGENT.md v1.1.0 (the kernel discipline, the parameter store, the assistant connection, backup and rebuild).
B1.3.3 The Cognitive Kernel as it stands in the live project, read on 23/09/2026 (see B1.4).
B1.3.4 The cnc-letterhead skill and the cnc-msp-dualbrand skill for document geometry.

B1.4 Baseline reconciliation. The Master Build Prompt describes the kernel as holding 31 verified instruments with the noise transition executed in release 1.1.0. A read only query of the live project on 23/09/2026 found:
B1.4.1 The live kernel is on release 1.0.0. Release 1.1.0 (repository migration 042_msp_legislation_currency_2026_09.sql) is committed to main but has not been applied to the live project.
B1.4.2 Consequently the NIHL Regulations, 2003 are still marked verified in the live kernel with a review date of 06/09/2026, now passed; the Physical Agents Regulations, 2024 are absent; the Environmental Regulations for Workplaces, 1987 are still marked verified although repealed with effect from 06/09/2026 (per migration 042). Plans drafted today can therefore cite a repealed instrument. This is recorded as HSF-7 and is blocking for Phase 2.
B1.4.3 The live kernel carries three pending duplicate rows (General Administrative Regulations, General Machinery Regulations, General Safety Regulations) alongside their verified dated counterparts. Hygiene item HSF-8.
B1.4.4 The Asbestos Abatement Regulations, 2020 amendment notice is recorded as GN R.2092 in migration 042 and as GN R.11435 in the live register and the published register release 1.0.0. One of them is wrong. HSF-9; neither is cited by HSF FORGE until resolved.
B1.4.5 Every element in this Part that concerns lighting, ventilation, thermal environment or vibration names the Physical Agents Regulations, 2024 as its candidate basis, not the Environmental Regulations for Workplaces, 1987, because the latter is repealed. The prompt's references to the 1987 Regulations are read that way.

B1.5 Register. SA British English; rand as R4 250,00; legal style numbering from 1; no dash or hyphen punctuation in prose (identifiers such as HSF-A-01 and official instrument names keep their natural form); staff are sales executives; secrets never in the repository or the database.

B1.6 What this Part does not do. It cites no provision number, gazette number or commencement date that has not passed the three checks. Where an element needs a provision, the element library names the instrument and describes the provision in words; the number is pinned in Phase 2 through the verification workflow. Basis state H means the instrument is held verified for medical scope and must be re verified for the File's provision; basis state C means the instrument is a Section 5 candidate and is uncitable until verified.

---

## B2. SYSTEM OVERVIEW

B2.1 HSF FORGE builds a Health and Safety File for a client engagement: every element that applies to the client's industry, subindustry, sites and activities, each carrying its duty in plain words, its instrument and provision, the responsible appointment, the evidence required, the review interval, the retention period and its current status, with a gap report, a compliance figure and an audit pack an inspector can read without the system.

B2.2 Engagement flow.
B2.2.1 The client signs in through the existing journey (msp_client_signon, msp_client_start_assessment). The File assessment reuses the MSP intake and asks only File specific questions (B9.1).
B2.2.2 The skeleton generator resolves the regime (OHSA or MHSA), the industry overlay and the intake triggers into a set of applicable elements and writes one hsf_file_item per element.
B2.2.3 The evidence pass links MCO medicals and training (Phase 5; fixture until HSF-3 closes), the MSP released Plan, intake appointments and certificates; everything else is outstanding.
B2.2.4 The gap report and compliance figure are computed in the database (B9.4).
B2.2.5 The medical section routes to the OMP queue; the safety sections route to the safety review queue for the professional the Director names (HSF-1). Release needs both approvals and the client's section 16(2) acceptance, enforced by trigger.
B2.2.6 After release the File stays live: expiries, MCO updates, change notifications and kernel releases open revisions.
B2.2.7 Every action writes to msp_audit with the file reference (B4.9).

B2.3 Governance boundaries, as build constraints.
B2.3.1 The engine assembles, evidences, flags and reports. It never decides that a workplace is safe, never certifies competence, never determines fitness for duty and never adjudicates under labour law.
B2.3.2 The OMP signs the medical surveillance content (Section E) and nothing else. Safety content is signed by the person the law names for it; the Care Net countersignatory for safety content and their registered capacity is HSF-1, open, owned by the Director, required before Phase 6.
B2.3.3 The employer is always the payer; HPCSA Booklet 11 applies to every medical element (kernel rule RULE-HPCSA-PAYER).
B2.3.4 Regime routing is a kernel rule: MINING routes to the MHSA and ODMWA; every other industry to the OHS Act and COIDA.
B2.3.5 Locked templates TPL-LIA-01, TPL-POP-01 and a new TPL-SGN-02 (File sign off blocks, B3.2) are inserted verbatim.
B2.3.6 WARDEN ring fence holds: no AutoHive, Glass Castle or Think Tank SA content, branding, agents or copy. The CRM is AutoHive CRM by name only.

---

## B3. COMPONENT MANIFEST

B3.1 Anchors follow the Part A convention. Token estimates are engineering estimates for build and review, not commitments.

| Anchor | Component | Phase | Est. tokens |
| --- | --- | --- | --- |
| HSF-SPEC-01 | This Part B | 1 | 60,000 |
| HSF-SCH-01 | Library tables: hsf_section, hsf_element, hsf_element_instrument, hsf_element_industry, hsf_appointment_type, hsf_training_requirement | 2 | 15,000 |
| HSF-SEED-01 | Element library seed (every row of B6 and B7) | 2 | 40,000 |
| HSF-VER-xx | Instrument verification batches, one anchor per batch (B8.3) | 2 | 15,000 per batch |
| HSF-KRN-01 | Kernel extension: msp_legal_instrument.scope, File rules in msp_kernel_rule, msp_industry_instrument safety scope | 3 | 12,000 |
| HSF-RUL-01 | Rules: regime routing, construction layering, MHI thresholds, appointment ratios, retention | 3 | 18,000 |
| HSF-AUD-01 | Monthly audit agent extended to the safety scope | 3 | 6,000 |
| HSF-FIX-01 | Seventeen industry fixtures and the rules test harness | 3 | 20,000 |
| HSF-ENG-01 | Engagement tables: hsf_file, hsf_file_item, hsf_evidence, hsf_appointment, hsf_person, hsf_revision | 4 | 15,000 |
| HSF-INT-01 | File assessment (assess form extension, intake mapping) | 4 | 20,000 |
| HSF-GEN-01 | Skeleton generator (hsf_generate_file) | 4 | 18,000 |
| HSF-GAP-01 | Gap report and compliance figure functions and views | 4 | 10,000 |
| HSF-DOC-01 | Document factory templates for the File, evidence index and gap report | 4 | 30,000 |
| HSF-MCO-01 | MCO adapter interface, fixture and pending integration marker | 4 (interface), 5 (live) | 12,000 |
| HSF-MCO-02 | MCO person matching, medical and training evidence flow, expiry handling | 5 | 20,000 |
| HSF-REV-01 | Dual review queue, signatures, release gate, revisions | 6 | 20,000 |
| HSF-PACK-01 | Audit pack export (PDF plus evidence index) | 6 | 15,000 |
| HSF-WEB-01 | Build your File page, account panel items, public element library, extended register | 7 | 30,000 |

B3.2 Locked templates.

| Anchor | Template | Source |
| --- | --- | --- |
| TPL-LIA-01 | Limitation of liability block | Part A, unchanged |
| TPL-POP-01 | Confidentiality and POPIA block | Part A, unchanged |
| TPL-SGN-02 | File sign off blocks: OMP (Section E only), safety content signatory (per HSF-1), client section 16(2) acceptance | To be drafted and approved by the Director before Phase 4; placeholder until then |
| TPL-HSF-01 | File scope and limitation note (the engine assembles and flags; named people decide and sign) | To be drafted and approved by the Director before Phase 4 |

---

## B4. DATA MODEL

B4.1 Design rules. Row Level Security on every table; revoke from public and anon; grant by role through msp_has_role; security definer functions for every write path from the web tier; the engine writes under the service context. Library tables are readable by every forge role and writable by forge_verifier. Engagement tables are scoped to the client account (msp_client_account.auth_user_id for the client, forge_admin and the reviewer roles for staff). Every threshold, ratio, interval and commercial figure is a row in msp_env_parameter (B5.4), never a constant.

B4.2 New roles. forge_safety_reviewer (safety review queue read and decision insert), alongside the existing forge_agent, forge_verifier, forge_omp, forge_admin.

B4.3 Library tables (HSF-SCH-01).

```sql
create table hsf_section (
  code text primary key check (code ~ '^[A-O]$'),   -- A to O
  ordinal int unique not null check (ordinal between 1 and 15),
  name text not null,
  description text not null,
  signatory_kind text not null check (signatory_kind in ('omp','safety'))  -- E is omp, every other section safety
);

create table hsf_appointment_type (
  code text primary key,                  -- APP-01 to APP-nn
  name text not null,
  instrument_id uuid references msp_legal_instrument(id),
  provision text not null,
  competence_requirement text not null,
  ratio_rule text,                        -- msp_kernel_rule code where the law sets a ratio (first aiders, representatives)
  regime text not null default 'BOTH' check (regime in ('OHSA','MHSA','BOTH'))
);

create table hsf_element (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,              -- HSF-A-01, HSF-B-APP-07, HSF-OV-CONSTR-03
  section_code text not null references hsf_section(code),
  name text not null,
  duty text not null,                     -- the duty in plain words
  evidence_type text not null check (evidence_type in
    ('document','register','certificate','appointment','plan','report','permit',
     'minutes','training_record','medical_certificate','licence','agreement','log')),
  responsible_appointment text references hsf_appointment_type(code),
  responsible_role text,                  -- where no statutory appointment owns it (e.g. chief executive)
  review_interval text not null check (review_interval in
    ('annual','on_change','per_event','per_project','monthly','daily','before_use','on_expiry','statutory')),
  review_interval_param text,             -- msp_env_parameter key where the interval is numeric
  retention_rule text,                    -- msp_kernel_rule code (RULE-RETAIN-*) or null while HSF-5 is open
  regime text not null default 'BOTH' check (regime in ('OHSA','MHSA','BOTH')),
  mhsa_equivalent_id uuid references hsf_element(id),  -- regime routing: the MHSA element that replaces an OHSA one
  universal boolean not null default true,
  trigger_code text,                      -- intake trigger that switches a conditional element on (B9.2)
  mco_source text check (mco_source in ('mco_medical','mco_training')),
  basis_state text not null default 'awaiting'
    check (basis_state in ('verified','awaiting')),  -- verified only when at least one linked instrument is verified
  status text not null default 'active' check (status in ('active','retired')),
  created_at timestamptz default now()
);

create table hsf_element_instrument (
  element_id uuid references hsf_element(id),
  instrument_id uuid references msp_legal_instrument(id),
  provision text not null,                -- pinned in Phase 2; 'awaiting verification' until then
  primary key (element_id, instrument_id)
);

create table hsf_element_industry (
  element_id uuid references hsf_element(id),
  industry_id uuid references msp_industry(id),
  subindustry_id uuid references msp_subindustry(id),   -- null means the whole industry
  applicability text not null check (applicability in ('mandatory','conditional','emphasis')),
  overlay_note text not null,
  unique (element_id, industry_id, subindustry_id)
);

create table hsf_training_requirement (
  id uuid primary key default gen_random_uuid(),
  job_role_id uuid references msp_job_role(id),
  appointment_code text references hsf_appointment_type(code),
  competency text not null,
  unit_standard_or_course text,           -- SAQA unit standard reference once verified (candidate: Skills Development Act)
  renewal_months int check (renewal_months is null or renewal_months > 0),
  renewal_param text,
  instrument_id uuid references msp_legal_instrument(id),
  check (job_role_id is not null or appointment_code is not null)
);
```

B4.4 Engagement tables (HSF-ENG-01).

```sql
create table hsf_file (
  id uuid primary key default gen_random_uuid(),
  reference text unique not null,         -- CNC-HSF-YYYY-MMDD-NNN, gap safe as msp_next_reference
  client_account_id uuid not null references msp_client_account(id),
  engagement_id uuid references msp_engagement(id),      -- the MSP engagement, where one exists
  parent_file_id uuid references hsf_file(id),           -- construction layering: contractor file under the principal contractor file
  industry_id uuid not null references msp_industry(id),
  subindustry_id uuid references msp_subindustry(id),
  regime text not null check (regime in ('OHSA','MHSA')),
  scope jsonb not null,                   -- sites, activities, dates, contract or project reference
  revision int not null default 1,
  status text not null default 'draft' check (status in
    ('draft','generating','in_review','approved','released','live','superseded','archived')),
  compliance_pct numeric(5,2),            -- cached; recomputed by hsf_compute_compliance
  created_at timestamptz default now()
);

create table hsf_file_item (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  element_id uuid not null references hsf_element(id),
  site_ref text,                          -- per site elements carry one item per site
  status text not null default 'outstanding' check (status in
    ('linked_mco','uploaded','outstanding','not_applicable','expired')),
  reason text,                            -- written reason, required when not_applicable
  responsible_person text,
  due_date date,
  updated_at timestamptz default now(),
  constraint na_needs_reason check (status <> 'not_applicable' or length(btrim(coalesce(reason,''))) >= 10),
  unique (file_id, element_id, site_ref)
);

create table hsf_evidence (
  id uuid primary key default gen_random_uuid(),
  file_item_id uuid not null references hsf_file_item(id),
  version int not null,
  supersedes_id uuid references hsf_evidence(id),
  source text not null check (source in ('mco_medical','mco_training','client_upload','engine_generated')),
  mco_record_ref text,                    -- MCO record identifier; required when source is mco_*
  storage_path text,                      -- Storage bucket hsf_evidence, private, file prefixed
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),   -- hashed on receipt
  supplied_by text not null,
  supplied_at timestamptz not null default now(),
  valid_from date,
  valid_to date,
  revoked_at timestamptz,                 -- MCO revocation; the row itself is never deleted
  unique (file_item_id, version),
  check (source not like 'mco_%' or mco_record_ref is not null)
);
-- trigger: update and delete refused on hsf_evidence except setting revoked_at once.
-- A replacement is a new row with version + 1 and supersedes_id; nothing is ever deleted.

create table hsf_person (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  mco_person_ref text,                    -- MCO's own person identifier (HSF-3); never matched on name alone
  employee_number text,
  display_name text not null,
  id_last4 text check (id_last4 ~ '^[0-9]{4}$'),   -- last four digits only, as Part A 8.2
  job_role_id uuid references msp_job_role(id),
  work_restriction text,                  -- the placement restriction the employer may hold; never a diagnosis
  unique (file_id, mco_person_ref)
);

create table hsf_appointment (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  appointment_code text not null references hsf_appointment_type(code),
  person_id uuid references hsf_person(id),
  appointee_name text not null,
  appointed_on date,
  accepted_on date,
  acceptance_evidence_id uuid references hsf_evidence(id),
  competence_evidence_id uuid references hsf_evidence(id)
);

create table hsf_revision (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  revision int not null,
  trigger_kind text not null check (trigger_kind in
    ('change_notification','risk_assessment_update','new_appointment','expiry','kernel_release','client_request')),
  summary text not null,
  opened_at timestamptz default now(),
  closed_at timestamptz,
  unique (file_id, revision)
);
```

B4.5 Review and release (HSF-REV-01), mirroring msp_omp_review and msp_release.

```sql
create table hsf_signoff (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  revision int not null,
  kind text not null check (kind in ('omp_medical','safety_content','client_16_2_acceptance')),
  decision text check (decision in ('approved','amended','rejected')),
  signatory_name text,
  registration_body text,                 -- HPCSA for the OMP; per HSF-1 for safety; null for the client appointee
  registration_number text,
  decided_at timestamptz,
  notes jsonb,
  constraint decision_complete check (decision is null or
    (signatory_name is not null and decided_at is not null
     and (kind = 'client_16_2_acceptance' or registration_number is not null)))
);

create table hsf_release (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references hsf_file(id),
  revision int not null,
  pdf_path text not null,
  evidence_index_path text not null,
  released_at timestamptz default now(),
  unique (file_id, revision)
);
-- trigger hsf_release_gate, before insert: raise unless, for this file and revision,
-- (1) an omp_medical signoff is approved, (2) a safety_content signoff is approved,
-- (3) a client_16_2_acceptance is approved, and (4) no hsf_file_item of the file
-- cites through its element an instrument whose status is not verified.
-- Enforced in the database; hsf_env parameter hsf.release_required does not relax it.
```

B4.6 MCO link on the client account: `alter table msp_client_account add column mco_company_ref text unique;` Null until HSF-3 closes; the adapter refuses to run for an account without it.

B4.7 Storage. One private bucket hsf_evidence, paths prefixed with the file id, signed short expiry URLs only, no personal data in URL parameters (Part A 4.5.3).

B4.8 Public views (Phase 7). hsf_public_element_library: universal elements with section, name, duty and the short names of verified instruments only, anonymous read, no client data. msp_public_instrument_register gains the scope column once B5.1 lands.

B4.9 Decision on HSF-4 (audit): the shared msp_audit table, extended with a nullable `hsf_file_id uuid references hsf_file(id)` and an index. Reasons: 4.9.1 one append only mechanism (the msp_audit_block_mutation trigger and the revoked grants) already proven, instead of a second one to prove; 4.9.2 kernel events (a release, a verification, a supersession) affect Plans and Files alike and belong in one timeline; 4.9.3 the data subject export (Part A 8.4) and the backup procedure already cover msp_audit; 4.9.4 the existing read policy filters by role and the new column only narrows it. A check keeps the two references honest: an audit row may carry engagement_id, hsf_file_id, both or neither (kernel events).

---

## B5. KERNEL EXTENSION (HSF-KRN-01, HSF-RUL-01)

B5.1 msp_legal_instrument gains `scope text not null default 'medical' check (scope in ('medical','safety','both'))`. Held instruments move to both once re verified for their File provisions; Section 5 candidates enter as scope safety (or both), status pending.

B5.2 msp_industry_instrument gains `scope` with the same values, so an industry map can carry an instrument for safety without implying a medical duty.

B5.3 File rules as msp_kernel_rule rows (condition and effect as jsonb, never prose):

| Rule code | Purpose |
| --- | --- |
| RULE-HSF-REGIME | MINING routes every element to its MHSA equivalent (hsf_element.mhsa_equivalent_id) and to ODMWA for lung disease; all other industries route to the OHS Act and COIDA |
| RULE-HSF-CONSTR-LAYER | Construction work creates a principal contractor File with a child File per contractor; the contractor register item of the parent is complete only when each child File carries its section 37(2) agreement, letter of good standing and appointments |
| RULE-HSF-CONSTR-NOTIFY | Construction work above the notification or permit thresholds switches on the notification element and the client specification and plan elements (thresholds pinned in Phase 2 and held as parameters) |
| RULE-HSF-MHI | Holdings of listed substances at or above threshold switch on the MHI elements (thresholds pinned in Phase 2 and held as parameters) |
| RULE-HSF-RATIO-FA | First aider ratio per headcount per site (pinned in Phase 2, parameter hsf.ratio.first_aiders) |
| RULE-HSF-RATIO-HSR | Health and safety representative ratio per headcount, and the committee trigger (pinned in Phase 2, parameters hsf.ratio.hsr and hsf.threshold.committee) |
| RULE-HSF-RATIO-FAC | Facilities Regulations ratios for sanitation and change facilities (pinned in Phase 2) |
| RULE-RETAIN-* | One rule per record class carrying its retention period and the instrument that sets it; the 40 year house floor for medical surveillance records of hazardous exposure applies where the instrument sets none for medical records; other classes wait on HSF-5 |
| RULE-HSF-EXPIRY | An item whose governing evidence has valid_to before today, or revoked_at set, flips to expired and opens a revision item |
| RULE-HSF-KERNEL-REV | A kernel release that supersedes or amends an instrument cited by a live File opens a revision on that File |

B5.4 Parameters (msp_env_parameter, group hsf, with history). hsf.ratio.first_aiders, hsf.ratio.hsr, hsf.threshold.committee, hsf.threshold.constr_notify, hsf.threshold.mhi (json), hsf.expiry_warning_days (working value 60), hsf.compliance_scope (whether not_applicable items leave the denominator; working value true), hsf.release_required (display only; the trigger is independent), hsf.commercial.* (reserved, empty until HSF-2). Values marked pinned in Phase 2 are loaded only after the governing provision is verified.

B5.5 Monthly audit agent (HSF-AUD-01). msp_kernel_monthly_audit gains three checks: instruments with scope safety or both on the watchdog; hsf_element rows whose basis_state is verified but whose instruments are no longer all verified; live Files citing an instrument released since their last revision.

---

## B6. THE UNIVERSAL ELEMENT LIBRARY

B6.1 Reading the tables.
B6.1.1 Code: the hsf_element.code. Applies: U means every File; a trigger code means the element switches on when the intake raises that trigger (B9.2).
B6.1.2 Basis: the instrument by kernel short name or candidate name, with the provision in words. H means held, to be re verified in full scope; C means Section 5 candidate. No provision numbers are given in this Part (B1.6).
B6.1.3 Evidence and Review use the enumerations of B4.3. Responsible names the appointment code (B6.3) or role.
B6.1.4 Retention: MED40 means the 40 year house floor for medical surveillance records (kernel); INST means the instrument sets it, pinned in Phase 2; HSF-5 means no instrument sets it and a decision is required; LIFE means the life of the File plus the HSF-5 period.
B6.1.5 Every element in these tables is loaded with basis_state awaiting. It moves to verified only when every instrument it cites is verified (Phase 2 gate).

B6.2 Section A: Legal and administrative

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-A-01 | Company legal identity, registration, VAT and the physical address of every site | OHS Act, general duty of the employer (H) | document | Chief executive | on_change | LIFE | U |
| HSF-A-02 | Scope of the File: sites, activities, dates, contract or project reference | OHS Act, general duty (H); Construction Regulations, 2014, health and safety file provision (H) | document | APP-00 | on_change | LIFE | U |
| HSF-A-03 | COIDA letter of good standing, with expiry | COIDA, letter of good standing provision (H) | certificate | Chief executive | on_expiry | INST | U |
| HSF-A-04 | Copy of the OHS Act and its regulations available at the workplace; MHSA equivalent for mines | OHS Act, availability of the Act provision (C: section to pin); MHSA equivalent (H) | document | APP-00 | on_change | LIFE | U |
| HSF-A-05 | Notification of construction work to the Department of Employment and Labour, with acknowledgement | Construction Regulations, 2014, notification provision (H) | document | Client or client's agent | per_project | INST | T-CONSTR-NOTIFY |
| HSF-A-06 | Client health and safety specification | Construction Regulations, 2014, client duties (H) | document | Client or client's agent | per_project | INST | T-CONSTR |
| HSF-A-07 | Contractor health and safety plan with the client's written approval | Construction Regulations, 2014, principal contractor and contractor duties (H) | plan | APP-01 | per_project | INST | T-CONSTR |
| HSF-A-08 | Section 37(2) agreement with every mandatary and every contractor | OHS Act section 37 (C) | agreement | Chief executive | on_change | LIFE | T-CONTRACTORS |
| HSF-A-09 | Contractor register: each contractor, its File, letter of good standing and appointments | OHS Act section 37 (C); Construction Regulations, 2014 (H) | register | APP-00 | on_change | LIFE | T-CONTRACTORS |
| HSF-A-10 | Legal register for the industry, drawn from the kernel and dated | OHS Act, general duty (H); kernel release notes | register | APP-00 | monthly | LIFE | U |
| HSF-A-11 | Document control procedure and the File's own revision history | OHS Act, general duty (H); Construction Regulations, 2014, health and safety file provision (H) | document | APP-00 | on_change | LIFE | U |

B6.3 Section B: Policy, organisation and appointments

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-B-01 | Health and safety policy signed by the chief executive, dated, displayed, reviewed annually | OHS Act section 7 (C) | document | Chief executive | annual | LIFE | U |
| HSF-B-02 | Section 16(1) chief executive responsibility acknowledged | OHS Act section 16 (C) | document | Chief executive | on_change | LIFE | U |
| HSF-B-03 | Section 16(2) assignment in writing, accepted in writing, with its scope | OHS Act section 16 (C) | appointment | Chief executive | on_change | LIFE | U |
| HSF-B-04 | Health and safety representatives designated in writing after consultation, in the statutory ratio, with training evidence | OHS Act sections 17 and 18 (C); General Administrative Regulations, 2003, representatives provision (H) | appointment | APP-00 | on_change | LIFE | T-HSR |
| HSF-B-05 | Health and safety committee: constitution, membership, minutes | OHS Act sections 19 and 20 (C); General Administrative Regulations, 2003, committee provision (H) | minutes | APP-00 | monthly | LIFE | T-COMMITTEE |
| HSF-B-06 | Statutory appointments, one item per applicable appointment type (B6.3.1), each in writing, signed, accepted, with competence evidence | Per appointment type | appointment | Per appointment type | on_change | LIFE | Per appointment trigger |
| HSF-B-07 | Organogram of the health and safety structure with every appointee in post | OHS Act section 16 (C) | document | APP-00 | on_change | LIFE | U |
| HSF-B-08 | Roles and responsibilities per appointment and per kernel job role | OHS Act, general duty (H); kernel role library | document | APP-00 | on_change | LIFE | U |

B6.3.1 Appointment types (hsf_appointment_type). Each applicable type yields one HSF-B-06 item. Basis state follows the instrument named. APP-00 is the section 16(2) assignee, used as the default responsible person for File administration.

| Code | Appointment | Candidate basis (provision to pin) | Trigger |
| --- | --- | --- | --- |
| APP-00 | Section 16(2) assignee | OHS Act section 16 (C) | U |
| APP-01 | Construction manager | Construction Regulations, 2014 (H) | T-CONSTR |
| APP-02 | Assistant construction manager | Construction Regulations, 2014 (H) | T-CONSTR |
| APP-03 | Construction health and safety officer | Construction Regulations, 2014 (H) | T-CONSTR |
| APP-04 | Construction supervisor | Construction Regulations, 2014 (H) | T-CONSTR |
| APP-05 | Risk assessor | Construction Regulations, 2014 (H); HCA Regulations, 2021 (H) | U |
| APP-06 | Fall protection planner | Construction Regulations, 2014 (H) | T-HEIGHT |
| APP-07 | Scaffold supervisor | Construction Regulations, 2014 (H) | T-SCAFFOLD |
| APP-08 | Scaffold inspector | Construction Regulations, 2014 (H) | T-SCAFFOLD |
| APP-09 | Excavation supervisor | Construction Regulations, 2014 (H) | T-EXCAVATION |
| APP-10 | Demolition supervisor | Construction Regulations, 2014 (H) | T-DEMOLITION |
| APP-11 | Temporary works designer | Construction Regulations, 2014 (H) | T-TEMPWORKS |
| APP-12 | Temporary works supervisor | Construction Regulations, 2014 (H) | T-TEMPWORKS |
| APP-13 | Construction vehicle and mobile plant operator | Construction Regulations, 2014 (H) | T-MOBILEPLANT |
| APP-14 | Construction vehicle and mobile plant supervisor | Construction Regulations, 2014 (H) | T-MOBILEPLANT |
| APP-15 | Electrical installation supervisor | Electrical Machinery and Installation Regulations (H) | T-ELEC |
| APP-16 | Construction electrical appointee | Construction Regulations, 2014 (H) | T-CONSTR and T-ELEC |
| APP-17 | Lifting machine and lifting tackle inspector | Driven Machinery Regulations (H) | T-LIFTING |
| APP-18 | Lifting machine operator | Driven Machinery Regulations (H) | T-LIFTING |
| APP-19 | General machinery supervisor | General Machinery Regulations, 1988 (H) | T-MACHINERY |
| APP-20 | Pressure equipment supervisor | Pressure Equipment Regulations, 2009 (C) | T-PRESSURE |
| APP-21 | Hazardous chemical agent controller | HCA Regulations, 2021 (H) | T-HCA |
| APP-22 | Ladder inspector | General Safety Regulations, 1986 (H) | T-LADDERS |
| APP-23 | Stacking and storage supervisor | General Safety Regulations, 1986 (H) | T-STACKING |
| APP-24 | First aiders in the statutory ratio | General Safety Regulations, 1986 (H); RULE-HSF-RATIO-FA | U |
| APP-25 | Fire equipment inspector | Candidate: SANS 10400 T part and local fire by laws (C) | U |
| APP-26 | Fire team | Candidate: Fire Brigade Services Act and local fire by laws (C) | U |
| APP-27 | Emergency coordinator | OHS Act, general duty (H) | U |
| APP-28 | Evacuation wardens | OHS Act, general duty (H) | U |
| APP-29 | Incident investigator | General Administrative Regulations, 2003, investigation provision (H) | U |
| APP-30 | Confined space supervisor | General Safety Regulations, 1986 (H) | T-CONFINED |
| APP-31 | Explosive powered tool operator | Candidate: explosive powered tools regulations (C) | T-EPT |
| APP-32 | Explosive powered tool issuer | Candidate: explosive powered tools regulations (C) | T-EPT |
| APP-33 | Hot work supervisor | General Safety Regulations, 1986 (H) | T-HOTWORK |
| APP-34 | Asbestos work supervisor | Asbestos Abatement Regulations, 2020 (H; see HSF-9) | T-ASBESTOS |
| APP-35 | Lead work supervisor | Lead Regulations, 2001 (H) | T-LEAD |
| APP-36 | Noise zone controller | Noise Exposure Regulations, 2024 (H) | T-NOISE |
| APP-37 | Radiation protection officer | Hazardous Substances Act (radiation control) (H) | T-RADIATION |
| APP-38 | Food safety and hygiene supervisor | Food Premises Hygiene Regulations, R638 of 2018 (H) | T-FOOD |
| APP-39 | Driver and professional driving permit holder | NRTA PrDP medical (H); National Road Traffic Act in full (C) | T-PRDP |
| APP-40 | Mine manager and MHSA statutory appointees | MHSA in full (C) | T-MINING |

B6.4 Section C: Risk management

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-C-01 | Baseline hazard identification and risk assessment per site and activity, signed by the risk assessor, with review date | OHS Act, general duty (H); Construction Regulations, 2014, risk assessment provision (H) | report | APP-05 | annual | INST | U |
| HSF-C-02 | Issue based risk assessments for every change, incident, new task or new substance | OHS Act, general duty (H) | report | APP-05 | per_event | INST | U |
| HSF-C-03 | Continuous, task based and daily or shift pre task assessments | OHS Act, general duty (H) | log | Supervisor | daily | HSF-5 | T-TASKRA |
| HSF-C-04 | Hazard register mapped to the kernel hazard taxonomy per job role | OHS Act, general duty (H); kernel hazard library | register | APP-05 | on_change | LIFE | U |
| HSF-C-05 | Hierarchy of control evidence: eliminated, substituted, engineered, administered, then protected | OHS Act, general duty (H); HCA Regulations, 2021, control provision (H) | report | APP-05 | annual | LIFE | U |
| HSF-C-06 | Safe work procedures and method statements for routine and high risk tasks | OHS Act, general duty (H); Construction Regulations, 2014 (H) | document | APP-00 | on_change | LIFE | U |
| HSF-C-07 | Fall protection plan | Construction Regulations, 2014, fall protection provision (H) | plan | APP-06 | per_project | INST | T-HEIGHT |
| HSF-C-08 | Traffic management plan where vehicles and people share space | Construction Regulations, 2014 (H); General Safety Regulations, 1986 (H) | plan | APP-00 | on_change | LIFE | T-TRAFFIC |
| HSF-C-09 | Lifting plans for lifting operations that require one | Driven Machinery Regulations (H) | plan | APP-17 | per_event | INST | T-LIFTING |
| HSF-C-10 | Excavation plan | Construction Regulations, 2014, excavation provision (H) | plan | APP-09 | per_project | INST | T-EXCAVATION |
| HSF-C-11 | Demolition plan | Construction Regulations, 2014, demolition provision (H) | plan | APP-10 | per_project | INST | T-DEMOLITION |
| HSF-C-12 | Confined space plan | General Safety Regulations, 1986, confined spaces provision (H) | plan | APP-30 | per_event | INST | T-CONFINED |
| HSF-C-13 | Hot work plan | General Safety Regulations, 1986 (H) | plan | APP-33 | per_event | INST | T-HOTWORK |
| HSF-C-14 | Ergonomic risk assessment | Ergonomics Regulations, 2019 (H) | report | APP-05 | statutory | INST | U |
| HSF-C-15 | Noise zoning and noise risk assessment | Noise Exposure Regulations, 2024 (H; HSF-7) | report | APP-36 | statutory | INST | T-NOISE |
| HSF-C-16 | Hazardous chemical agent risk and exposure assessment | HCA Regulations, 2021 (H) | report | APP-21 | statutory | INST | T-HCA |
| HSF-C-17 | Asbestos risk assessment, inventory and management plan | Asbestos Abatement Regulations, 2020 (H; HSF-9) | report | APP-34 | statutory | INST | T-ASBESTOS |
| HSF-C-18 | Lead risk assessment | Lead Regulations, 2001 (H) | report | APP-35 | statutory | INST | T-LEAD |
| HSF-C-19 | Hazardous biological agent risk assessment | HBA Regulations, 2022 (H) | report | APP-05 | statutory | INST | T-HBA |
| HSF-C-20 | Psychosocial and fatigue risk assessment | BCEA night work Code (H); BCEA in full (C) | report | APP-05 | annual | HSF-5 | T-SHIFT or T-VIOLENCE |
| HSF-C-21 | Major hazard installation risk assessment | MHI Regulations, 2022 (H) | report | APP-00 | statutory | INST | T-MHI |
| HSF-C-22 | Physical agents exposure risk assessment (heat, cold, illumination, indoor air, vibration, non ionising radiation) | Physical Agents Regulations, 2024 (C until HSF-7 closes) | report | APP-05 | statutory | INST | U |

B6.5 Section D: Training and competence

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-D-01 | Training needs analysis per job role from the kernel's statutory competency requirements | OHS Act, information and training duty (C: section 13); Skills Development Act (C) | report | APP-00 | annual | LIFE | U |
| HSF-D-02 | Training matrix: every person, every requirement, date, expiry, evidence (from MCO where Care Net delivered) | OHS Act, information and training duty (C) | register | APP-00 | monthly | LIFE | U |
| HSF-D-03 | Site, company and visitor induction records | OHS Act, information and training duty (C); Construction Regulations, 2014 (H) | training_record | APP-00 | per_event | HSF-5 | U |
| HSF-D-04 | Statutory and safety critical training records, one item per applicable course (B6.5.1) | Per course | training_record | APP-00 | on_expiry | HSF-5 | Per course trigger |
| HSF-D-05 | Licences and permits held by persons, one item per applicable class (B6.5.2) | Per class | licence | APP-00 | on_expiry | HSF-5 | Per class trigger |
| HSF-D-06 | Toolbox talk register and attendance | OHS Act, information and training duty (C) | register | Supervisor | per_event | HSF-5 | U |
| HSF-D-07 | Competency assessment records where a role requires assessment rather than attendance | Skills Development Act (C) | training_record | APP-00 | on_expiry | HSF-5 | U |

B6.5.1 Courses (HSF-D-04 items; hsf_training_requirement rows, MCO source mco_training): D04-01 health and safety representative; D04-02 first aid; D04-03 fire fighting; D04-04 working at height and fall arrest (T-HEIGHT); D04-05 scaffold erection and inspection (T-SCAFFOLD); D04-06 confined space entry (T-CONFINED); D04-07 lifting machine and lifting tackle operation (T-LIFTING); D04-08 forklift and mobile plant (T-MOBILEPLANT); D04-09 hazard identification and risk assessment; D04-10 incident investigation; D04-11 hazardous chemical handling (T-HCA); D04-12 asbestos awareness (T-ASBESTOS); D04-13 lead awareness (T-LEAD); D04-14 hearing conservation (T-NOISE); D04-15 ergonomics; D04-16 emergency evacuation; D04-17 food handler hygiene (T-FOOD); D04-18 and onward: industry competencies from B7. Basis for each: the instrument that requires it (H or C as in B6.3.1) read with the Skills Development Act and SETA unit standards (C). Unit standard numbers are entered only after verification.

B6.5.2 Licence classes (HSF-D-05 items): D05-01 professional driving permit (NRTA PrDP medical, H; T-PRDP); D05-02 plant and machinery operator certificates (Driven Machinery Regulations, H; T-LIFTING or T-MOBILEPLANT); D05-03 electrical wireman and installation registration (Electrical Installation Regulations, 2009 wireman provisions, C; T-ELEC); D05-04 gas practitioner registration (Pressure Equipment Regulations, 2009, C; T-LPG); D05-05 explosives licence (Explosives Regulations, C; T-EXPLOSIVES); D05-06 firearm competency (Firearms Control Act, C; T-ARMED); D05-07 PSIRA registration and grade (Private Security Industry Regulation Act, C; T-SECURITY); D05-08 and onward: industry licences from B7.

B6.6 Section E: Medical surveillance and fitness (signed by the OMP only)

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-E-01 | The released Medical Surveillance Plan from MSP FORGE | Kernel instruments per the Plan (H) | document | OMP | annual | MED40 | U |
| HSF-E-02 | Certificates of fitness per employee per protocol: baseline, periodic, exit (MCO) | HCA, HBA, Noise Exposure, Lead, Ergonomics Regulations per protocol (H) | medical_certificate | OMP | on_expiry | MED40 | U |
| HSF-E-03 | Construction Regulations Annexure 3 medical certificates of fitness (MCO) | Construction Regulations, 2014, Annexure 3 (H) | medical_certificate | APP-01 | on_expiry | MED40 | T-CONSTR |
| HSF-E-04 | Professional driving permit medicals (MCO) | NRTA PrDP medical (H) | medical_certificate | OMP | on_expiry | MED40 | T-PRDP |
| HSF-E-05 | Mine certificate of fitness per the mandatory Code of Practice (MCO) | MHSA (H); Fitness to Perform Work Guideline (MHSA) (H) | medical_certificate | OMP | on_expiry | MED40 | T-MINING |
| HSF-E-06 | Statutory examinations required by specific regulations, one item per applicable class: lead, asbestos, hazardous chemical agents, hazardous biological agents, noise, radiation, heights, confined space, night work, food handling (MCO) | Lead Regulations, 2001; Asbestos Abatement Regulations, 2020; HCA Regulations, 2021; HBA Regulations, 2022; Noise Exposure Regulations, 2024; Hazardous Substances Act (radiation control); Construction Regulations, 2014; General Safety Regulations, 1986; BCEA night work Code; Food Premises Hygiene Regulations, R638 of 2018 (all H) | medical_certificate | OMP | statutory | MED40 | Per class trigger |
| HSF-E-07 | Fitness restrictions reflected in job placement, without clinical detail beyond what the employer may hold | EEA section 7 (H); Code of Good Practice on Employment of Persons with Disabilities (C) | register | OMP | per_event | MED40 | U |
| HSF-E-08 | Occupational disease reporting and referral records | COIDA (H); ODMWA (H) for mines | report | OMP | per_event | MED40 | U |
| HSF-E-09 | First aid: box contents and inspection, first aider list, treatment register | General Safety Regulations, 1986, first aid provision (H) | register | APP-24 | monthly | HSF-5 | U |
| HSF-E-10 | Confidentiality and POPIA handling of every medical record: what the employer holds, what Care Net holds, and the lawful basis for each | POPIA in full (C in live kernel; see HSF-7); HPCSA Booklet 1 (H) | document | OMP | annual | LIFE | U |

B6.7 Section F: Registers and inspections

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-F-01 | Scaffold register and inspection records | Construction Regulations, 2014, scaffolding provision (H) | register | APP-08 | statutory | INST | T-SCAFFOLD |
| HSF-F-02 | Ladder register and inspections | General Safety Regulations, 1986 (H) | register | APP-22 | statutory | HSF-5 | T-LADDERS |
| HSF-F-03 | Lifting machines and lifting tackle register with load tests and inspections | Driven Machinery Regulations (H) | register | APP-17 | statutory | INST | T-LIFTING |
| HSF-F-04 | Portable electrical tools and equipment register with inspections | Electrical Machinery and Installation Regulations (H); Construction Regulations, 2014 (H) | register | APP-15 | statutory | HSF-5 | U |
| HSF-F-05 | Electrical installation certificate of compliance and installation inspection register | Electrical Machinery and Installation Regulations (H); Electrical Installation Regulations, 2009 read with SANS 10142 (C) | certificate | APP-15 | statutory | INST | U |
| HSF-F-06 | Fire equipment register with service dates | Candidate: SANS 10400 T part and local fire by laws (C) | register | APP-25 | statutory | HSF-5 | U |
| HSF-F-07 | Emergency lighting and signage inspections | Candidate: SANS 10400 (C) | register | APP-25 | statutory | HSF-5 | U |
| HSF-F-08 | Pressure equipment register with inspections and certificates | Pressure Equipment Regulations, 2009 (C) | register | APP-20 | statutory | INST | T-PRESSURE |
| HSF-F-09 | Vehicle and mobile plant register with daily checks and maintenance | Construction Regulations, 2014 (H); Driven Machinery Regulations (H) | register | APP-14 | daily | HSF-5 | T-MOBILEPLANT |
| HSF-F-10 | Excavation inspection register | Construction Regulations, 2014 (H) | register | APP-09 | daily | INST | T-EXCAVATION |
| HSF-F-11 | Personal protective equipment issue register and inspection | General Safety Regulations, 1986, PPE provision (H) | register | APP-00 | on_change | HSF-5 | U |
| HSF-F-12 | Hazardous chemical agent register with safety data sheets, quantities and storage | HCA Regulations, 2021 (H) | register | APP-21 | on_change | INST | T-HCA |
| HSF-F-13 | Asbestos inventory and register | Asbestos Abatement Regulations, 2020 (H; HSF-9) | register | APP-34 | statutory | INST | T-ASBESTOS |
| HSF-F-14 | Machine guarding inspection register | General Machinery Regulations, 1988 (H) | register | APP-19 | statutory | HSF-5 | T-MACHINERY |
| HSF-F-15 | Housekeeping and walkabout inspection records | Construction Regulations, 2014 (H); OHS Act, general duty (H) | log | Supervisor | monthly | HSF-5 | U |
| HSF-F-16 | Stacking and storage inspections | General Safety Regulations, 1986 (H) | log | APP-23 | monthly | HSF-5 | T-STACKING |
| HSF-F-17 | Fall arrest equipment register and inspections | Construction Regulations, 2014 (H) | register | APP-06 | before_use | HSF-5 | T-HEIGHT |
| HSF-F-18 | Confined space register | General Safety Regulations, 1986 (H) | register | APP-30 | on_change | HSF-5 | T-CONFINED |
| HSF-F-19 | Explosive powered tool register | Candidate: explosive powered tools regulations (C) | register | APP-32 | per_event | HSF-5 | T-EPT |
| HSF-F-20 | Welfare facilities inspection | Facilities Regulations, 2004 (H) | log | APP-00 | monthly | HSF-5 | U |
| HSF-F-21 | Lighting, ventilation and thermal environment measurements | Physical Agents Regulations, 2024 (C until HSF-7 closes) | report | APP-05 | statutory | INST | U |
| HSF-F-22 | Waste register | NEM Waste Act (H) | register | APP-00 | monthly | INST | T-WASTE |

B6.8 Section G: Permits and controls

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-G-01 | Permit to work system and permit register | OHS Act, general duty (H) | register | APP-00 | on_change | HSF-5 | T-PTW |
| HSF-G-02 | Hot work permits | General Safety Regulations, 1986 (H) | permit | APP-33 | per_event | HSF-5 | T-HOTWORK |
| HSF-G-03 | Confined space entry permits | General Safety Regulations, 1986 (H) | permit | APP-30 | per_event | HSF-5 | T-CONFINED |
| HSF-G-04 | Excavation permits and service clearances | Construction Regulations, 2014 (H) | permit | APP-09 | per_event | HSF-5 | T-EXCAVATION |
| HSF-G-05 | Working at height permits | Construction Regulations, 2014 (H) | permit | APP-06 | per_event | HSF-5 | T-HEIGHT |
| HSF-G-06 | Electrical isolation, lockout and tagout records | Electrical Machinery and Installation Regulations (H) | log | APP-15 | per_event | HSF-5 | T-ELEC |
| HSF-G-07 | Lifting operation permits | Driven Machinery Regulations (H) | permit | APP-17 | per_event | HSF-5 | T-LIFTING |
| HSF-G-08 | Demolition permits | Construction Regulations, 2014 (H) | permit | APP-10 | per_event | HSF-5 | T-DEMOLITION |
| HSF-G-09 | Road closure and traffic accommodation approvals | Candidate: National Road Traffic Act in full (C) | permit | APP-00 | per_event | HSF-5 | T-ROADWORKS |
| HSF-G-10 | Radiation work authorisations | Hazardous Substances Act (radiation control) (H) | licence | APP-37 | on_expiry | INST | T-RADIATION |

B6.9 Section H: Emergency preparedness

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-H-01 | Emergency plan per site: roles, assembly points, contacts, routes | OHS Act, general duty (H); Construction Regulations, 2014 (H) | plan | APP-27 | annual | LIFE | U |
| HSF-H-02 | Emergency drills: schedule, records, findings, corrective actions | OHS Act, general duty (H) | report | APP-27 | statutory | HSF-5 | U |
| HSF-H-03 | Fire risk assessment and fire plan | Candidate: SANS 10400 T part, Fire Brigade Services Act, local fire by laws (C) | plan | APP-25 | annual | LIFE | U |
| HSF-H-04 | Medical emergency arrangements and nearest facilities | General Safety Regulations, 1986, first aid provision (H) | document | APP-24 | annual | LIFE | U |
| HSF-H-05 | Spill response | HCA Regulations, 2021 (H); NEMA instruments (C) | plan | APP-21 | annual | LIFE | T-HCA |
| HSF-H-06 | MHI emergency plan and public information duty | MHI Regulations, 2022 (H) | plan | APP-00 | statutory | INST | T-MHI |
| HSF-H-07 | Security emergency procedures | Candidate: Private Security Industry Regulation Act (C) | document | APP-27 | annual | LIFE | T-SECURITY |
| HSF-H-08 | Disaster management interface for emergency planning | Candidate: Disaster Management Act (C) | document | APP-27 | annual | LIFE | T-MHI |

B6.10 Section I: Incident management

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-I-01 | Incident and near miss reporting procedure | General Administrative Regulations, 2003 (H) | document | APP-00 | annual | LIFE | U |
| HSF-I-02 | Incident register | General Administrative Regulations, 2003, recording provision (H) | register | APP-29 | per_event | INST | U |
| HSF-I-03 | Section 24 reporting and the Annexure 1 recording | OHS Act section 24 (C); General Administrative Regulations, 2003 (H) | report | APP-00 | per_event | INST | U |
| HSF-I-04 | Investigation reports with root cause and corrective action | General Administrative Regulations, 2003, investigation provision (H) | report | APP-29 | per_event | INST | U |
| HSF-I-05 | COIDA claim records and employer's reports of accidents and diseases | COIDA in full (C for the reporting forms) | report | APP-00 | per_event | INST | U |
| HSF-I-06 | Occupational disease notifications | COIDA (H); ODMWA (H) for mines | report | OMP | per_event | MED40 | U |
| HSF-I-07 | Corrective and preventive action register with closure evidence | OHS Act, general duty (H) | register | APP-00 | monthly | HSF-5 | U |

B6.11 Section J: Occupational hygiene

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-J-01 | Occupational hygiene survey programme | HCA Regulations, 2021 (H); Physical Agents Regulations, 2024 (C) | plan | APP-05 | annual | LIFE | U |
| HSF-J-02 | Noise survey by an approved inspection authority and the noise zone map | Noise Exposure Regulations, 2024 (H; HSF-7) | report | APP-36 | statutory | INST | T-NOISE |
| HSF-J-03 | Hazardous chemical agent exposure monitoring by an approved inspection authority | HCA Regulations, 2021 (H) | report | APP-21 | statutory | INST (kernel: 30 years air monitoring) | T-HCA |
| HSF-J-04 | Illumination survey | Physical Agents Regulations, 2024 (C until HSF-7 closes) | report | APP-05 | statutory | INST | U |
| HSF-J-05 | Ventilation and thermal survey | Physical Agents Regulations, 2024 (C until HSF-7 closes) | report | APP-05 | statutory | INST | T-THERMAL |
| HSF-J-06 | Asbestos air monitoring | Asbestos Abatement Regulations, 2020 (H; HSF-9) | report | APP-34 | statutory | INST | T-ASBESTOS |
| HSF-J-07 | Lead air monitoring | Lead Regulations, 2001 (H) | report | APP-35 | statutory | INST | T-LEAD |
| HSF-J-08 | Biological monitoring results as they bear on controls, held under medical confidentiality (aggregate only in the File) | Lead Regulations, 2001; HCA Regulations, 2021 (H) | report | OMP | statutory | MED40 | T-HCA or T-LEAD |

B6.12 Section K: Contractors, visitors and the public

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-K-01 | Contractor selection criteria and evaluation | Construction Regulations, 2014 (H); OHS Act section 37 (C) | document | APP-00 | per_project | LIFE | T-CONTRACTORS |
| HSF-K-02 | Section 37(2) agreements and contractor Files (cross reference HSF-A-08) | OHS Act section 37 (C) | agreement | APP-00 | on_change | LIFE | T-CONTRACTORS |
| HSF-K-03 | Contractor inductions, permits and daily coordination records | Construction Regulations, 2014 (H) | log | APP-00 | daily | HSF-5 | T-CONTRACTORS |
| HSF-K-04 | Visitor control and induction | OHS Act section 9 (C) | log | APP-00 | per_event | HSF-5 | U |
| HSF-K-05 | Public protection: hoarding, signage, public liability evidence | OHS Act section 9 (C); Construction Regulations, 2014 (H) | document | APP-00 | per_project | HSF-5 | T-PUBLIC |

B6.13 Section L: Communication and consultation

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-L-01 | Committee minutes and action tracking (cross reference HSF-B-05) | OHS Act section 20 (C) | minutes | APP-00 | monthly | LIFE | T-COMMITTEE |
| HSF-L-02 | Representative inspection reports and recommendations | OHS Act section 18 (C) | report | APP-00 | monthly | HSF-5 | T-HSR |
| HSF-L-03 | Toolbox talks (cross reference HSF-D-06) | OHS Act section 13 (C) | register | Supervisor | per_event | HSF-5 | U |
| HSF-L-04 | Notices displayed: Act and regulations, appointments, emergency numbers, policy | OHS Act (C: display provisions); General Administrative Regulations, 2003 (H) | log | APP-00 | annual | HSF-5 | U |
| HSF-L-05 | Change notification records to Care Net for medical surveillance and to the client for construction work | OHS Act, general duty (H); Construction Regulations, 2014 (H) | log | APP-00 | per_event | LIFE | U |

B6.14 Section M: Environment, welfare and facilities

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-M-01 | Facilities Regulations compliance: sanitation, drinking water, change rooms, eating places, in the statutory ratios | Facilities Regulations, 2004 (H); RULE-HSF-RATIO-FAC | report | APP-00 | annual | HSF-5 | U |
| HSF-M-02 | Physical environment compliance: lighting, ventilation, thermal, housekeeping | Physical Agents Regulations, 2024 (C until HSF-7 closes) | report | APP-00 | annual | INST | U |
| HSF-M-03 | Environmental management where NEM Waste Act or other environmental law applies | NEM Waste Act (H); NEMA and its instruments (C) | document | APP-00 | annual | INST | T-WASTE or T-ENVIRO |
| HSF-M-04 | Waste manifests and licensed disposal evidence | NEM Waste Act (H) | register | APP-00 | per_event | INST | T-WASTE |
| HSF-M-05 | Workplace smoking controls | Candidate: Tobacco Products Control Act (C) | document | APP-00 | annual | HSF-5 | U |

B6.15 Section N: Audit, review and improvement

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-N-01 | Internal audit schedule and reports | OHS Act, general duty (H); Construction Regulations, 2014, audit provision (H) | report | APP-00 | statutory | HSF-5 | U |
| HSF-N-02 | External audit reports (client, principal contractor, certification body, inspector) | Construction Regulations, 2014 (H) | report | APP-00 | per_event | HSF-5 | U |
| HSF-N-03 | Management review records | OHS Act section 16 (C) | minutes | Chief executive | annual | HSF-5 | U |
| HSF-N-04 | Objectives and targets with measurement | OHS Act section 7 (C) | report | Chief executive | annual | HSF-5 | U |
| HSF-N-05 | Non conformance and corrective action log with closure evidence | OHS Act, general duty (H) | register | APP-00 | monthly | HSF-5 | U |
| HSF-N-06 | Kernel legislation release notes applied to this File, with date and change | Kernel release (msp_kernel_version) | log | Engine | per_event | LIFE | U |

B6.16 Section O: Records and retention

| Code | Element | Basis | Evidence | Responsible | Review | Retention | Applies |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HSF-O-01 | Retention schedule per record type, from the instrument that sets it, including the 40 year retention for medical surveillance records of hazardous exposure | RULE-RETAIN-*; HCA, HBA, Lead, Asbestos Regulations (H) | document | APP-00 | annual | LIFE | U |
| HSF-O-02 | Storage location and access control per record type | POPIA (C in live kernel) | document | APP-00 | annual | LIFE | U |
| HSF-O-03 | POPIA operator agreement between the client and Care Net for the records Care Net holds | POPIA operator provisions (C) | agreement | Chief executive | on_change | LIFE | U |

B6.17 Library count. Universal element rows: A 11, B 8 (plus 41 appointment types), C 22, D 7 (plus 17 courses and 7 licence classes), E 10 (with 10 examination classes), F 22, G 10, H 8, I 7, J 8, K 5, L 5, M 5, N 6, O 3. Total 137 element rows before appointment, course, licence and examination items; every row carries at least one named instrument, and every row is awaiting verification at load.

---

## B7. THE SEVENTEEN INDUSTRY OVERLAYS

B7.1 Each overlay switches universal elements on (listed by trigger) and adds rows coded HSF-OV-<industry>-nn. Overlays never remove a universal element; a universal element that does not apply is marked not_applicable with a written reason on the File. Additions carry the same columns as B6; only code, element, candidate basis and state are shown here, and the remaining columns are set at seed time in Phase 2 by the same rules.

B7.2 AGRI Agriculture and forestry. Switches on: T-HCA, T-HBA, T-MACHINERY, T-THERMAL, T-PRDP, T-ARMED where game and stock protection applies.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-AGRI-01 | Pesticide and organophosphate handling procedure and register | HCA Regulations, 2021 (H) |
| HSF-OV-AGRI-02 | Cholinesterase surveillance (Section E, MCO) | HCA Regulations, 2021 (H) |
| HSF-OV-AGRI-03 | Tractor and implement guarding inspections | General Machinery Regulations, 1988 (H) |
| HSF-OV-AGRI-04 | Chainsaw and forestry harvesting competencies | Skills Development Act (C) |
| HSF-OV-AGRI-05 | Zoonosis controls | HBA Regulations, 2022 (H) |
| HSF-OV-AGRI-06 | Child labour prohibition on hazardous work | Regulations on Hazardous Work by Children, 2010 (C) |
| HSF-OV-AGRI-07 | Seasonal worker induction | OHS Act section 13 (C) |
| HSF-OV-AGRI-08 | Heat exposure controls | Physical Agents Regulations, 2024 (C until HSF-7) |
| HSF-OV-AGRI-09 | Remote site emergency response | OHS Act, general duty (H) |

B7.3 CLEAN Cleaning and hygiene services. Switches on: T-HCA, T-HEIGHT, T-CONFINED, T-HBA, T-SHIFT, T-CONTRACTORS.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-CLEAN-01 | Safety data sheets held at every client site | HCA Regulations, 2021 (H) |
| HSF-OV-CLEAN-02 | Facade and high level cleaning method statements | Construction Regulations, 2014 (H) where construction work; General Safety Regulations, 1986 (H) |
| HSF-OV-CLEAN-03 | Tank and duct confined space entry | General Safety Regulations, 1986 (H) |
| HSF-OV-CLEAN-04 | Biological agent exposure in healthcare and sanitation cleaning | HBA Regulations, 2022 (H) |
| HSF-OV-CLEAN-05 | Lone worker and night work controls | BCEA night work Code (H) |
| HSF-OV-CLEAN-06 | Multi site client induction records | OHS Act section 9 (C) |

B7.4 CONSTR Construction. The Construction Regulations, 2014 apply in full. Switches on: T-CONSTR and every construction trigger raised by the intake; RULE-HSF-CONSTR-LAYER models the principal contractor and contractor Files.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-CONSTR-01 | Construction work permit where the thresholds require it | Construction Regulations, 2014 (H) |
| HSF-OV-CONSTR-02 | Designer duties record | Construction Regulations, 2014 (H) |
| HSF-OV-CONSTR-03 | Structures inspections | Construction Regulations, 2014 (H) |
| HSF-OV-CONSTR-04 | Suspended platforms register and inspections | Construction Regulations, 2014 (H) |
| HSF-OV-CONSTR-05 | Use and temporary storage of flammables | Construction Regulations, 2014 (H) |
| HSF-OV-CONSTR-06 | Water environments controls | Construction Regulations, 2014 (H) |
| HSF-OV-CONSTR-07 | Fire precautions on construction sites | Construction Regulations, 2014 (H) |
| HSF-OV-CONSTR-08 | Health and safety file handover to the client on completion | Construction Regulations, 2014 (H) |
| HSF-OV-CONSTR-09 | Annexure 3 certificate for every person on site (Section E, MCO) | Construction Regulations, 2014 (H) |

B7.5 EDU Education. Switches on: T-HCA (laboratories), T-FOOD, T-PRDP, T-HBA.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-EDU-01 | Laboratory and workshop chemical controls | HCA Regulations, 2021 (H) |
| HSF-OV-EDU-02 | Playground and sports equipment inspections | OHS Act section 9 (C) |
| HSF-OV-EDU-03 | Learner transport and professional driving permits | NRTA PrDP medical (H) |
| HSF-OV-EDU-04 | Immunisation and biological agent controls in early childhood settings | HBA Regulations, 2022 (H) |
| HSF-OV-EDU-05 | Emergency plan accounting for learners | OHS Act section 9 (C) |
| HSF-OV-EDU-06 | Child protection interface, referenced only, never adjudicated | Reference only; no citation |

B7.6 GOV Government and municipal. Switches on: T-CONSTR for public works, T-CONFINED, T-PRDP, T-CONTRACTORS.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-GOV-01 | Water and wastewater confined space controls | General Safety Regulations, 1986 (H) |
| HSF-OV-GOV-02 | Emergency and traffic services fitness (Section E, MCO) | EEA section 7 (H) |
| HSF-OV-GOV-03 | Fleet management register | National Road Traffic Act in full (C) |
| HSF-OV-GOV-04 | Public facility fire and evacuation | Candidate: SANS 10400 T part (C) |
| HSF-OV-GOV-05 | Multi department appointment structure under one accounting officer | OHS Act section 16 (C) |
| HSF-OV-GOV-06 | Contractor procurement under section 37(2) | OHS Act section 37 (C) |

B7.7 HEALTH Healthcare and laboratories. Switches on: T-HBA, T-RADIATION, T-SHIFT, T-VIOLENCE, T-HCA.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-HEALTH-01 | Immunisation and post exposure protocols (Section E, MCO) | HBA Regulations, 2022 (H) |
| HSF-OV-HEALTH-02 | Sharps and healthcare risk waste | National Health Act and the Health Care Waste regulations (C); NEM Waste Act (H) |
| HSF-OV-HEALTH-03 | Radiation protection officer, dose records | Hazardous Substances Act (radiation control) (H) |
| HSF-OV-HEALTH-04 | Cytotoxic and anaesthetic gas controls | HCA Regulations, 2021 (H) |
| HSF-OV-HEALTH-05 | Patient handling ergonomics | Ergonomics Regulations, 2019 (H) |
| HSF-OV-HEALTH-06 | Violence and psychosocial controls | OHS Act, general duty (H) |
| HSF-OV-HEALTH-07 | Laboratory biosafety level controls | HBA Regulations, 2022 (H) |
| HSF-OV-HEALTH-08 | Clinical workplace professional registration interface, reference only | Nursing Act, Health Professions Act, SAHPRA (C, reference only) |

B7.8 HOSP Hospitality and food service. Switches on: T-FOOD, T-LPG, T-SHIFT, T-VIOLENCE, T-HCA.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-HOSP-01 | Food Premises Hygiene Regulations compliance in full | Food Premises Hygiene Regulations, R638 of 2018 (H); Foodstuffs, Cosmetics and Disinfectants Act (C) |
| HSF-OV-HOSP-02 | Food handler fitness (Section E, MCO) | Food Premises Hygiene Regulations, R638 of 2018 (H) |
| HSF-OV-HOSP-03 | Kitchen fire and gas installation certificates | Pressure Equipment Regulations, 2009 (C) |
| HSF-OV-HOSP-04 | Slips and burns controls | OHS Act, general duty (H) |
| HSF-OV-HOSP-05 | Pool and lifeguard requirements where applicable | Candidate: local by laws (C) |
| HSF-OV-HOSP-06 | Housekeeping chemical handling | HCA Regulations, 2021 (H) |

B7.9 MANU Manufacturing. Switches on: T-MACHINERY, T-PRESSURE, T-LIFTING, T-ELEC, T-HCA, T-NOISE, T-CONFINED, T-MOBILEPLANT, T-LEAD, T-ASBESTOS where legacy plant exists, T-FOOD where food is made.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-MANU-01 | Guarding in full per machine class | General Machinery Regulations, 1988 (H) |
| HSF-OV-MANU-02 | Process specific chemical controls: solvents, welding fume, isocyanates | HCA Regulations, 2021 (H) |
| HSF-OV-MANU-03 | Ergonomics on production lines | Ergonomics Regulations, 2019 (H) |
| HSF-OV-MANU-04 | Confined space in vessels | General Safety Regulations, 1986 (H) |
| HSF-OV-MANU-05 | Forklift competencies | Driven Machinery Regulations (H) |
| HSF-OV-MANU-06 | Dangerous goods storage and transport | National Road Traffic Act in full, SANS 10231 and 10232 (C) |

B7.10 MINING Mining. RULE-HSF-REGIME replaces the OHS Act elements with their MHSA equivalents; ODMWA governs lung disease.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-MINING-01 | Employer duties under the MHSA | MHSA in full (C) |
| HSF-OV-MINING-02 | Mandatory Codes of Practice per DMRE guideline: fitness to perform work | Fitness to Perform Work Guideline (MHSA) (H) |
| HSF-OV-MINING-03 | Mandatory Code of Practice: noise | DMRE guideline (C) |
| HSF-OV-MINING-04 | Mandatory Code of Practice: airborne pollutants | DMRE guideline (C) |
| HSF-OV-MINING-05 | Mandatory Code of Practice: thermal stress | DMRE guideline (C) |
| HSF-OV-MINING-06 | Mandatory Code of Practice: fatigue | DMRE guideline (C) |
| HSF-OV-MINING-07 | Mandatory Code of Practice: trackless mobile machinery | DMRE guideline (C) |
| HSF-OV-MINING-08 | Mandatory Code of Practice: fall of ground | DMRE guideline (C) |
| HSF-OV-MINING-09 | Mandatory Code of Practice: emergency preparedness | DMRE guideline (C) |
| HSF-OV-MINING-10 | Certificate of fitness system (Section E, MCO) | MHSA (H) |
| HSF-OV-MINING-11 | ODMWA benefit examinations | ODMWA (H) |
| HSF-OV-MINING-12 | Mine health and safety representatives and committees | MHSA in full (C) |
| HSF-OV-MINING-13 | Explosives controls | Explosives Regulations (C) |
| HSF-OV-MINING-14 | Winding and lifting plant | MHSA regulations (C) |
| HSF-OV-MINING-15 | Ventilation and rescue | MHSA regulations (C) |
| HSF-OV-MINING-16 | Mine Health and Safety Inspectorate reporting | MHSA in full (C) |

B7.11 OFFICE Office and professional services. Switches on: T-SHIFT for contact centres.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-OFFICE-01 | Display screen work ergonomics | Ergonomics Regulations, 2019 (H) |
| HSF-OV-OFFICE-02 | Contact centre night work and acoustic exposure | BCEA night work Code (H); Noise Exposure Regulations, 2024 (H) |
| HSF-OV-OFFICE-03 | Lone working and travel | OHS Act, general duty (H) |
| HSF-OV-OFFICE-04 | Psychosocial hazards | OHS Act, general duty (H) |

B7.12 PETRO Petrochemical and fuel retail. Switches on: T-MHI, T-HCA, T-HOTWORK, T-CONFINED, T-ELEC, T-LPG, T-WASTE, T-PTW.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-PETRO-01 | MHI Regulations in full where thresholds are met | MHI Regulations, 2022 (H) |
| HSF-OV-PETRO-02 | Electrical zoning and intrinsically safe equipment | Electrical Machinery and Installation Regulations (H) |
| HSF-OV-PETRO-03 | Dangerous goods transport | National Road Traffic Act in full, SANS 10231 and 10232 (C) |
| HSF-OV-PETRO-04 | Forecourt and tank farm emergency plans | MHI Regulations, 2022 (H) |
| HSF-OV-PETRO-05 | Static and grounding controls | Electrical Machinery and Installation Regulations (H) |
| HSF-OV-PETRO-06 | Environmental spill controls | NEMA instruments (C) |

B7.13 RETAIL Retail and wholesale. Switches on: T-STACKING, T-MOBILEPLANT, T-TRAFFIC, T-PRDP, T-FOOD, T-VIOLENCE.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-RETAIL-01 | Racking inspections | General Safety Regulations, 1986 (H) |
| HSF-OV-RETAIL-02 | Loading dock traffic management | General Safety Regulations, 1986 (H) |
| HSF-OV-RETAIL-03 | Cold room and heat exposure | Physical Agents Regulations, 2024 (C until HSF-7) |
| HSF-OV-RETAIL-04 | Security and robbery exposure controls | OHS Act, general duty (H) |
| HSF-OV-RETAIL-05 | Fire and evacuation for public spaces | Candidate: SANS 10400 T part (C) |

B7.14 SEC Security services. Switches on: T-SECURITY, T-ARMED where armed, T-SHIFT, T-VIOLENCE, T-PRDP.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-SEC-01 | PSIRA registration and grades | Private Security Industry Regulation Act and PSIRA training regulations (C) |
| HSF-OV-SEC-02 | Firearm competency and Firearms Control Act compliance | Firearms Control Act (C) |
| HSF-OV-SEC-03 | Cash in transit vehicle and route controls | Firearms Control Act (C); National Road Traffic Act in full (C) |
| HSF-OV-SEC-04 | Post incident support | OHS Act, general duty (H) |
| HSF-OV-SEC-05 | Canine unit controls | OHS Act, general duty (H) |
| HSF-OV-SEC-06 | Control room ergonomics | Ergonomics Regulations, 2019 (H) |
| HSF-OV-SEC-07 | Lone posting emergency procedures | OHS Act, general duty (H) |

B7.15 TEL Telecommunications and tower work. Switches on: T-HEIGHT, T-ELEC, T-CONFINED, T-LIFTING, T-PRDP, T-CONSTR where towers are built.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-TEL-01 | Tower rescue plans | Construction Regulations, 2014 (H) |
| HSF-OV-TEL-02 | Radio frequency exposure controls | Physical Agents Regulations, 2024, non ionising radiation (C until HSF-7) |
| HSF-OV-TEL-03 | Manhole and data centre plant confined space | General Safety Regulations, 1986 (H) |
| HSF-OV-TEL-04 | Remote site emergency response | OHS Act, general duty (H) |

B7.16 TRANS Transport and logistics. Switches on: T-PRDP, T-STACKING, T-MOBILEPLANT, T-SHIFT.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-TRANS-01 | Fleet compliance under the National Road Traffic Act in full, operator cards and roadworthiness | National Road Traffic Act in full (C) |
| HSF-OV-TRANS-02 | Dangerous goods where carried | National Road Traffic Act, SANS 10231 and 10232 (C) |
| HSF-OV-TRANS-03 | Driver fatigue management | BCEA in full (C) |
| HSF-OV-TRANS-04 | Rail safety critical fitness (Section E, MCO) | SANS 3000-4 (RSR) (H); Railway Safety Regulator Act and SANS 3000 series (C) |
| HSF-OV-TRANS-05 | Port work regime | Merchant Shipping Act and Ports Act (C) |
| HSF-OV-TRANS-06 | Aviation ground handling regime | Civil Aviation Act and regulations (C) |
| HSF-OV-TRANS-07 | Loading and securing of loads | National Road Traffic Act in full (C) |

B7.17 UTIL Utilities and energy. Switches on: T-ELEC, T-HEIGHT, T-CONFINED, T-HCA, T-CONSTR for renewable installation, T-PUBLIC.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-UTIL-01 | Electrical Machinery and Installation Regulations in full for generation and distribution | Electrical Machinery and Installation Regulations (H) |
| HSF-OV-UTIL-02 | Switching and isolation procedures | Electrical Machinery and Installation Regulations (H) |
| HSF-OV-UTIL-03 | Chlorine and chemical dosing controls | HCA Regulations, 2021 (H) |
| HSF-OV-UTIL-04 | Arc flash controls | Electrical Machinery and Installation Regulations (H) |
| HSF-OV-UTIL-05 | Public safety near assets | OHS Act section 9 (C) |
| HSF-OV-UTIL-06 | Environmental authorisations | NEMA instruments (C) |

B7.18 WASTE Waste management. Switches on: T-WASTE, T-HBA, T-CONFINED, T-MOBILEPLANT, T-TRAFFIC, T-HCA, T-PRDP.

| Code | Addition | Candidate basis |
| --- | --- | --- |
| HSF-OV-WASTE-01 | NEM Waste Act licences and manifests | NEM Waste Act (H) |
| HSF-OV-WASTE-02 | Hazardous and healthcare risk waste handling | NEM Waste Act (H); Health Care Waste regulations (C) |
| HSF-OV-WASTE-03 | Immunisation for biological agent exposure (Section E, MCO) | HBA Regulations, 2022 (H) |
| HSF-OV-WASTE-04 | Landfill gas and confined space | General Safety Regulations, 1986 (H); HCA Regulations, 2021 (H) |
| HSF-OV-WASTE-05 | Reversing vehicle traffic management | General Safety Regulations, 1986 (H) |
| HSF-OV-WASTE-06 | Needle stick and sharps controls | HBA Regulations, 2022 (H) |
| HSF-OV-WASTE-07 | Dust and silica at transfer stations | HCA Regulations, 2021 (H) |
| HSF-OV-WASTE-08 | Environmental monitoring | NEMA instruments (C) |

B7.19 Overlay count: 119 addition rows across seventeen industries.

---

## B8. INSTRUMENT VERIFICATION PLAN (PHASE 2)

B8.1 Every instrument in B6 and B7 marked C enters msp_legal_instrument with status pending and scope safety or both. Every instrument marked H is re verified in full scope for the provisions the File cites, and its scope moves to both. Nothing is cited until it passes gate a (primary text), gate b (independent corroboration) and gate c (currency on the day).

B8.2 Precondition. HSF-7 must close first: the live kernel must be brought to release 1.1.0 (migration 042 applied or superseded by a reviewed successor), so that the File never inherits a repealed noise or environmental instrument.

B8.3 Batches (HSF-VER-xx), each with the batch record the SOP requires:

| Batch | Instruments | Serves |
| --- | --- | --- |
| HSF-VER-01 | OHS Act sections 7, 8, 9, 13, 14, 16 to 20, 24, 25, 37, 38; General Administrative Regulations, 2003 in full; General Safety Regulations, 1986 in full; Facilities Regulations, 2004 in full; Physical Agents Regulations, 2024; COIDA in full; POPIA in full | Every File |
| HSF-VER-02 | Construction Regulations, 2014 in full; Driven Machinery Regulations in full; Electrical Machinery and Installation Regulations with the Electrical Installation Regulations, 2009 and SANS 10142; Pressure Equipment Regulations, 2009; explosive powered tools regulations | CONSTR, TEL, UTIL, MANU |
| HSF-VER-03 | General Machinery Regulations (and the 2025 replacement watch); HCA, HBA, Lead, Asbestos, Noise, Ergonomics Regulations in full scope; Lift, Escalator and Passenger Conveyor Regulations, 2010 | MANU, HEALTH, WASTE, AGRI |
| HSF-VER-04 | MHSA in full with regulations and the DMRE mandatory Code guidelines; ODMWA in full; Explosives Regulations | MINING |
| HSF-VER-05 | National Road Traffic Act in full with SANS 10231 and 10232; Railway Safety Regulator Act and SANS 3000 series; Civil Aviation Act; Merchant Shipping Act and Ports Act | TRANS, PETRO, RETAIL |
| HSF-VER-06 | Private Security Industry Regulation Act and PSIRA training regulations; Firearms Control Act | SEC |
| HSF-VER-07 | National Health Act and Health Care Waste regulations; Nursing Act, Health Professions Act, SAHPRA provisions (reference only); Foodstuffs, Cosmetics and Disinfectants Act | HEALTH, HOSP |
| HSF-VER-08 | NEMA and its air, water and hazardous waste instruments; NEM Waste Act in full; MHI Regulations, 2022 in full; Disaster Management Act | PETRO, WASTE, UTIL |
| HSF-VER-09 | National Building Regulations and Building Standards Act with SANS 10400 T part; Fire Brigade Services Act; BCEA in full; Labour Relations Act (reference only); Tobacco Products Control Act; Regulations on Hazardous Work by Children, 2010; Diving Regulations, 2009; Skills Development Act and SETA unit standards; EEA section 7 with the Code of Good Practice on Employment of Persons with Disabilities | Cross industry |

B8.4 Scope decisions for release 1.0 of the File (HSF-6) may move any batch out of scope; an out of scope instrument stays pending and every element that depends only on it stays awaiting and shows as such in the File.

B8.5 Gate for Phase 2: every hsf_element row has basis_state verified, or is explicitly awaiting with the candidate instrument named in hsf_element_instrument.

---

## B9. GENERATION CONTRACT

B9.1 File assessment. Reuses msp_intake company, sites, workforce and job categories. Adds only: activities and high risk work (raising the T codes), contractors, appointments in post, equipment classes held, chemicals held, existing certificates, whether medicals and training were done with Care Net, and scope (sites, dates, project reference). Nothing already asked by MSP FORGE is asked twice.

B9.2 Trigger vocabulary (hsf_element.trigger_code). T-CONSTR, T-CONSTR-NOTIFY, T-CONTRACTORS, T-HSR, T-COMMITTEE, T-HEIGHT, T-SCAFFOLD, T-EXCAVATION, T-DEMOLITION, T-TEMPWORKS, T-MOBILEPLANT, T-ELEC, T-LIFTING, T-MACHINERY, T-PRESSURE, T-HCA, T-HBA, T-LADDERS, T-STACKING, T-CONFINED, T-EPT, T-HOTWORK, T-ASBESTOS, T-LEAD, T-NOISE, T-RADIATION, T-FOOD, T-PRDP, T-MINING, T-TASKRA, T-TRAFFIC, T-SHIFT, T-VIOLENCE, T-MHI, T-THERMAL, T-WASTE, T-ENVIRO, T-PTW, T-ROADWORKS, T-SECURITY, T-ARMED, T-LPG, T-EXPLOSIVES, T-PUBLIC. Triggers are raised by intake answers and by the kernel (for example a job role whose hazard profile includes noise raises T-NOISE). The mapping from answer to trigger is data, loaded in Phase 3 and tested per industry fixture.

B9.3 Skeleton generation (hsf_generate_file, security definer, service context). 3.1 resolve regime by RULE-HSF-REGIME; 3.2 select universal elements with trigger null or raised, swapping OHSA elements for their MHSA equivalents under MHSA; 3.3 add overlay rows for the industry and subindustry; 3.4 expand per appointment, per course, per licence class, per examination class and per site; 3.5 write hsf_file_item rows as outstanding; 3.6 evidence pass (MCO, MSP release, intake); 3.7 compute compliance; 3.8 audit. A File never contains an item whose element cites a non verified instrument as its only basis without that item showing the basis as awaiting, and the release gate refuses such a File.

B9.4 Compliance figure.
Per section s: compliance(s) = (items in s with status linked_mco or uploaded) divided by (items in s whose status is not not_applicable), times 100. Outstanding and expired count against. Overall is the same ratio across all sections, not the mean of the section figures, so a large section weighs by its size.
Worked example: Section F with 20 items, of which 3 not_applicable, 11 uploaded, 2 linked_mco, 3 outstanding, 1 expired. Denominator 20 minus 3 = 17. Numerator 11 plus 2 = 13. Compliance 13 divided by 17 = 0,7647, shown as 76,5 per cent. If the expired item is renewed, 14 divided by 17 = 82,4 per cent.
Whether not_applicable leaves the denominator is the parameter hsf.compliance_scope (working value true). Weighting by risk is not built in release 1.0.

B9.5 Gap report: every item not linked_mco or uploaded, grouped by section, with element, duty, basis, responsible person, due date and, for expired items, the renewal path (MCO booking for medicals and training, upload for everything else).

B9.6 Evidence integrity. On receipt the file bytes are hashed (SHA 256) before storage; hsf_evidence is append only; replacement creates version n plus 1; the File's evidence index lists every version with its hash, supplier and dates.

---

## B10. MCO ADAPTER INTERFACE (HSF-MCO-01)

B10.1 Status: PENDING INTEGRATION. The MCO interface contract (CR-13.12, HSF-3) is not in hand. No MCO endpoint is named or assumed. Phase 4 builds against this interface and a fixture; Phase 5 begins only when the contract arrives.

B10.2 The interface the engine depends on:

```ts
// HSF-MCO-01 | adapter contract the engine depends on. The live implementation
// is written in Phase 5 against the MCO contract; until then FixtureMcoAdapter
// (test/fixtures/mco/) is the only implementation.
interface McoAdapter {
  company(mcoCompanyRef: string): Promise<{ ref: string; name: string } | null>;
  people(mcoCompanyRef: string): Promise<McoPerson[]>;
  medicals(mcoCompanyRef: string, since?: string): Promise<McoMedical[]>;
  training(mcoCompanyRef: string, since?: string): Promise<McoTraining[]>;
}
interface McoPerson   { personRef: string; employeeNumber?: string; displayName: string; idLast4?: string }
interface McoMedical  { recordRef: string; personRef: string; protocolCode: string; kind: 'baseline'|'periodic'|'exit'|'annexure3'|'prdp'|'mine_cof';
                        issuedOn: string; expiresOn?: string; outcome: 'fit'|'fit_with_restrictions'|'unfit'|'pending';
                        workRestriction?: string; practitionerName: string; practitionerRegNo: string; revoked?: boolean;
                        documentSha256?: string }
interface McoTraining { recordRef: string; personRef: string; provider: string; courseOrUnitStandard: string;
                        completedOn: string; expiresOn?: string; certificateRef: string; revoked?: boolean }
```

B10.3 Matching. People match on McoPerson.personRef only, never on name. An MCO person with no hsf_person row is offered to the client to confirm; an hsf_person with no MCO match stays unmatched and its items show outstanding with upload offered.

B10.4 Flow. A medical or training record becomes hsf_evidence with source mco_medical or mco_training, mco_record_ref set, valid_to from expiresOn, and the item goes linked_mco. A later revoked record sets revoked_at and the item flips to expired (RULE-HSF-EXPIRY). Clinical detail never crosses: only outcome, work restriction, dates and practitioner identity, which is what the employer may hold.

B10.5 Fixture. test/fixtures/mco/ holds one synthetic company per industry with people, medicals (including one expired and one revoked) and training. The Phase 5 gate is proven against the live adapter; the Phase 4 gate against the fixture.

---

## B11. REVIEW, RELEASE AND THE LIVING FILE

B11.1 Section E routes to the existing OMP queue (review.html) as a File review item. Sections A to D and F to O route to a safety review queue under forge_safety_reviewer.
B11.2 Release requires, for the same revision: omp_medical approved, safety_content approved, client_16_2_acceptance approved, and no item citing a non verified instrument. The hsf_release_gate trigger enforces it; the application cannot bypass it.
B11.3 Output: the File on the Care Net letterhead geometry with the dual brand band (cnc-letterhead, cnc-msp-dualbrand), the evidence index, the gap report and the audit pack (PDF plus evidence index). Watermark and release rules follow the MSP model unless the Director rules otherwise (HSF-2).
B11.4 Living File: a nightly job applies RULE-HSF-EXPIRY with hsf.expiry_warning_days notice; MCO updates, change notifications and kernel releases open hsf_revision rows; the account panel shows the compliance figure and the outstanding list.

---

## B12. CONFIRMATION REGISTER, HSF FORGE

B12.1 These items enter msp_confirmation_item in Phase 2.

| Code | Kind | Item | Owner | Status |
| --- | --- | --- | --- | --- |
| HSF-1 | confirm | Who signs safety content for Care Net, in what registered capacity, and who signs for construction Files. Director's instruction 23/09/2026: a registered Health and Safety Manager signs the safety content. Further instruction 23/09/2026: Occupational Medical Practitioners do not sign Files (the OMP signed plan stays Section E evidence); a competent health and safety practitioner signs the safety content, with a registering body and category that fit the File type, under the rule in hsf/SIGNOFF-CRITERIA.md; the signatory must have an appointment letter and an engagement letter on record, each linkable from the recruitment portal Care Net is building. Built as migration 053 (contract 10.8). Director's answer 23/09/2026 (contract 11.4): credentials are checked at the point of use, so the release gate also refuses a register check more than hsf.signoff_register_check_max_days (30) before the decision day, and staff are alerted to registrations that expire within 60 days (hsf_signatory_expiry_alerts). Staff record signatories and sign offs and see release readiness in the staff console (vercel/hsf-staff.html, contract 11.5). Built in migration 054 (B14.9). Still open: the named signatories and their registration numbers (SACPCMP for construction Files), before Phase 6, and the review of hsf/SIGNOFF-CRITERIA.md section 5 by the attorney and a registered practitioner | Director | Decided 23/09/2026; built in 053 and 054 |
| HSF-2 | confirm | Commercial model for the File. Director's instruction 23/09/2026: the File is free to build for every client; sign off by a registered Health and Safety Manager is priced at the researched market average (hsf/PRICING-RESEARCH.md, published through vercel/hsf/pricing.js), and Care Net clients pay that average less 25%. Amounts are published on health-and-safety-file.html, a deliberate departure from the MSP no price rule. Still open: the watermark rule for the File, and moving the figures and the 25% into msp_env_parameter in Phase 4 | Director | Partly resolved 23/09/2026 |
| HSF-3 | confirm | MCO interface contract for medicals and training, and the person identifier to match on (extends CR-13.12) | Director and MCO owner | Open, required before Phase 5 |
| HSF-4 | decision | Audit table: shared msp_audit with hsf_file_id (B4.9) | Build | Resolved in this Part, subject to Director approval |
| HSF-5 | confirm | Retention where an instrument sets none (every row marked HSF-5 in B6) | OMP and Director | Open |
| HSF-6 | confirm | Which Section 5 candidates, and therefore which B8.3 batches, are out of scope for File release 1.0 | Director | Open |
| HSF-7 | confirm | Live kernel is on release 1.0.0; migration 042 (release 1.1.0: noise transition, Physical Agents Regulations, 2024, Environmental Regulations for Workplaces, 1987 superseded) is in the repository but not applied. NIHL Regulations, 2003 remain verified in live past their 06/09/2026 repeal date. Apply 042 (with OMP ratification) or supersede it with a reviewed successor | Director and OMP | Open, blocking Phase 2; affects MSP FORGE today |
| HSF-8 | confirm | Live kernel carries pending duplicates of the General Administrative, General Machinery and General Safety Regulations beside the verified dated rows; exclude the duplicates through the hygiene sweep | Build, forge_verifier | Open |
| HSF-9 | confirm | Asbestos Abatement Regulations, 2020 amendment notice: GN R.2092 (migration 042) or GN R.11435 (live register and published register 1.0.0); verify against the Gazette and correct whichever is wrong | Build, forge_verifier | Open |
| HSF-10 | confirm | Published register PDF (vercel/downloads/CNC-Legislation-Register-v1.0.0.pdf): cross reference offsets do not match the file bytes; regenerate at the next register release. Closed 23/09/2026 (contract 10.9): the PDF was removed, its old address and the CSV's redirect to /shop.html#law (vercel.json and server/serve.js), and the CSV is kept as the seed source at hsf/sources/ | Build | Closed 23/09/2026 |
| HSF-11 | confirm | CNC OHS Industry Kernel (23/09/2026) marks MHSA, the Fitness to Perform Work Guideline, NRTA PrDP, SANS 3000-4, the Hazardous Substances Act, the Driven Machinery Regulations and the Electrical Machinery and Installation Regulations as catalogue or unverified (text not held on disk); the live kernel marks them verified. Decide the rule for HSF FORGE (recommended: text held on file before a File cites it) and fetch the seven bodies. Also open: the mining basis for protocols 4 and 5 (MHSA surveillance and ODMWA benefit examinations). See kernel/OHS-KERNEL-RECONCILIATION.md | Director and OMP | Open |
| HSF-12 | confirm | Physical Agents Regulations amendment GN 7149, GG 54177, 20 February 2026, named in the kernel pack, is in neither the live kernel nor migration 042. Fetch and verify before heat and vibration values are relied on | Build, forge_verifier | Open |
| HSF-13 | confirm | Instruments the live kernel holds that the pack does not: Ergonomics Regulations, 2019 (basis of protocols 16 and 17 in live), Facilities Regulations, 2004, General Machinery Regulations, 1988, MHI Regulations, 2022, NEM Waste Act, HPCSA Booklets 1, 10 and 11, BCEA night work Code, R638 of 2018. Add them to the pack or record why not | Director | Open |
| HSF-14 | confirm | Food handler fitness: live cites the Food Premises Hygiene Regulations, R638 of 2018; the pack cites municipal by laws and SASOHN guidance only. Agree one basis | OMP | Open |
| HSF-15 | confirm | HCA instrument title: "2020" in the pack, "2021" in the live kernel, GN R280 dated 29 March 2021 in both. Confirm the Gazette title and align | Build, forge_verifier | Open |
| HSF-16 | confirm | The pack's ten templates map to File elements (reconciliation section 9) and become engine generated evidence templates in Phase 4, after the OMP and attorney review the pack itself requires | Director, OMP and attorney | Open |
| HSF-17 | confirm | Google Tag Manager container ID for www.carenetconsultants.co.za. It could not be read from the build environment, so vercel/js/cnc-config.js holds null and tracking stays off until the ID is confirmed | Director | Pending |
| HSF-18 | confirm | Grok bot connection (B14.4): a kernel API key issued by a forge_admin through msp_api_client_issue once 050 is applied; the xAI model, tool calling and retention details read from xAI's own pages; xAI recorded as an operator in the privacy notice | Director, Odendaal, Information Officer | Open |
| HSF-19 | confirm | Company uploads before MCO is connected: whether uploads open while the transfer worker is in hold mode, the longest stay in Supabase staging, whether an upload waits for Care Net's approval of the account, and malware scanning of staged files. Director's decision 23/09/2026: uploads open when Odendaal has finished the backend and Cassandra and the designer have finished the front end (hsf.uploads_open, off until then); two years at most in the private bucket; only verified Care Net clients upload; every upload is always scanned for viruses, malware and harmful metadata; MCO builds the transfer protocol and files stay in Supabase staging until then (hsf/MCO-TRANSFER-REQUIREMENTS.md is Care Net's proposal). Built in migration 052 (B14.8). Director's answer 23/09/2026 (contract 11.1): the scan also removes all non essential metadata; the cleaned copy replaces the staged bytes, and only a cleaned copy with its own fingerprint (sha256_clean) moves to MCO. Built in migration 054 with supabase/functions/_shared/metadata-clean.js (B14.9). Retention (contract 11.7): the two year limit stays until the Director has audited what the report builder can do. Still needed live: an antivirus engine (HSF_AV_ENDPOINT and HSF_AV_TOKEN as Supabase secrets) | Director, Information Officer | Decided 23/09/2026; built in 052 and 054; the two year limit stands until the Director's audit of the report builder |
| HSF-20 | confirm | Consent withdrawal: withdrawing storage or transfer consent blocks that company's untransferred uploads and nothing is deleted automatically. Director's decision 23/09/2026: blocked documents stay blocked; the company may delete its own staged documents after an irreversibility warning and a one time PIN by email or SMS (sent and checked by Supabase Auth); the two year limit still applies. Built in migration 052 (B14.8). Director's answers 23/09/2026: a document on its way to MCO (status transferring) can never be deleted by the company, whatever the age of the claim; it becomes deletable again only if the transfer stops and returns it to uploaded (contract 11.2); and an account has at most 5 PIN attempts an hour across its deletion requests, with 5 per request (contract 11.3). Built in migration 054 (B14.9). Still open: whether withdrawing the authority to share should block staged documents too | Director, Information Officer, attorney | Decided 23/09/2026 in part; built in 052 and 054 |
| HSF-21 | confirm | Application of migrations 047 to 052 to the live project, after HSF-7. Nothing is applied without the Director's explicit approval | Director | Open |
| HSF-22 | decision | Seven build decisions from the review fix round (B14.6). Approved by the Director 23/09/2026; B14.6.1 and B14.6.2 are now read with the launch controls (B14.8): a blocked upload's bytes wait for the company's deletion or the two year limit | Build | Approved 23/09/2026 |
| HSF-23 | confirm | Legislation copy still to settle: (a) the register release 1.0.0 PDF and CSV are linked from no page but remain reachable at their addresses and list repealed instruments as verified (hsf/build_seed.py reads that CSV, so change the generator before deleting it); (b) form/fields.json and form/assess.html still carry the old noise and asbestos labels; (c) element names in 048 and the B6 tables still carry section and annexure numbers; (d) static pages name the Noise Exposure and Physical Agents Regulations, 2024 as the replacing instruments while contract section 7 reserves that for after HSF-7 closes. Done 23/09/2026 (contract 10.9): (a) both files removed, their addresses redirect to /shop.html#law, and the CSV moved to hsf/sources/ as the seed source; (b) the noise item names the Noise Exposure Regulations, 2024 and the asbestos item reads "Work with asbestos", and form/onboarding_form.docx was regenerated to match; (c) hsf/build_seed.py rewrites element names in plain words, refuses any surviving number other than 16(2) and 37(2), and 048 was regenerated. Still open: the B6 tables of this Part keep their provision numbers as the generator's source, and item (d) | Build, forge_verifier | Partly resolved 23/09/2026 |
| HSF-24 | confirm | Local test stub: it does not copy hosted Supabase's default function privileges, so service_role cannot run msp_client_signon on a plain local replay. Either the stub adds the default privileges or migration 043 grants service_role explicitly | Build | Open |

---

## B13. PHASE GATES, HSF FORGE

| Phase | Scope | Gate | Status |
| --- | --- | --- | --- |
| 1 | This Part B | Director approval of the specification | Delivered, awaiting approval |
| 2 | Element library load and instrument verification | Every element verified or explicitly awaiting with candidate named | Blocked on Phase 1 gate and HSF-7 |
| 3 | Kernel rules, audit agent extension | Rules tested against seventeen fixtures | Blocked on Phase 2 gate |
| 4 | Intake, generation, gap report, compliance, templates, MCO interface with fixture | Complete File for a fictitious company in each of seventeen industries, nothing missing, nothing unverified cited | Blocked on Phase 3 gate, TPL-SGN-02 and TPL-HSF-01 |
| 5 | MCO linking | Evidence from MCO in a test File without upload; revoked or expired record flips its item | Blocked on Phase 4 gate and HSF-3 |
| 6 | Review and release | Release impossible without the three approvals, proven at the database layer | Blocked on Phase 5 gate and HSF-1 |
| 7 | Site and journey | Build your File page, account panel, public element library, extended register; Lighthouse 100 on every category, mobile and desktop; house register; no price | Blocked on Phase 6 gate |

END OF PART B. Phase 1 stops here pending the Director's approval.

---

## B14. ADDENDUM 23/09/2026: PORTAL, BUILDER, UPLOADS, MCO TRANSFER AND KERNEL API

B14.1 **Status.** Built on the Director's instruction of 23/09/2026, ahead of the B13 gates. It does not open any gate. Migrations 047 to 051 are in the repository and replay cleanly into an empty database; none is applied to the live project (HSF-21). Nothing is deployed to Vercel. The binding build contract is hsf/BUILD-CONTRACT.md, with Amendment 1 (section 9) from the review round.

B14.2 **What was built.**

B14.2.1 Database: the File engine schema and element library (047, 048: 256 elements, 41 appointment types, 49 triggers, 34 element classes), consent, uploads and the MCO transfer (049), the kernel API with currency holds (050), and File generation and compliance (051).

B14.2.2 Server: vercel/api/hsf-consent.js, hsf-upload.js, hsf-file.js, kernel.js and portal-summary.js on vercel/lib/auth.js, with server/serve.js so the same handlers run outside Vercel when the portal moves to MCO hosting.

B14.2.3 Worker: supabase/functions/hsf-mco-transfer with the MCO adapter in hold, fixture and live modes. Live is a placeholder until HSF-3; the worker runs in hold mode, so documents stay in staging.

B14.2.4 Front end: the portal (vercel/portal.html), the File builder with drag and drop per department (vercel/hsf-builder.html), shared configuration, tracking, sign in and designer asset scripts under vercel/js/, and all existing pages brought onto the same tracking and call to action code. DESIGNER-ASSETS.md lists every asset slot per page with size, ratio and format.

B14.2.5 Documentation: HSF-PORTAL-ARCHITECTURE.md (target architecture, document lifecycle, POPIA analysis, open items), KERNEL-API.md with vercel/kernel-api/openapi.yaml, and the Grok pack under grok/.

B14.3 **Document lifecycle.** A company gives three separate consents (document storage, MCO transfer, authority to share; version HSF-CONSENT-1.0) before any upload. Files go to the private Supabase Storage bucket hsf-staging through a signed upload URL, with a SHA-256 fingerprint computed in the browser and again on the server. The worker sends a document to MCO and deletes the staging copy only when the browser, server and MCO receipt fingerprints all match. A mismatch revokes the evidence, and the bytes leave staging through the cleanup queue. "Supabase Secrets" in the instruction is read as private Supabase Storage: secrets hold keys, never documents.

B14.4 **Kernel API and the Grok bot.** A read only API over verified kernel content, with no client data. Keys are issued only by a forge_admin, shown once and stored as a SHA-256 hash; every call is logged and rate limited. A currency hold withholds an instrument from every public view, API answer and File citation while its row still reads verified. Odendaal connects the bot with grok/kernel-tools.json and grok/bridge-example.mjs (HSF-18).

B14.5 **Legislation references.** A reference is shown only once it has passed the kernel's three checks (B1.6, verified through the B8 plan). No new reading of the Gazette was possible, because the build environment cannot reach gov.za or carenetconsultants.co.za. File citations therefore show "Awaiting verification" until the Phase 2 re verification, and the website pages carry no section or regulation number apart from the two OHS Act references already on the site, sections 16(2) and 37(2).

B14.6 **Build decisions from the review fix round (HSF-22).**

B14.6.1 An upload blocked by a consent withdrawal stays blocked even if consent is given again; staff decide what happens to it.

B14.6.2 The cleanup queue skips blocked uploads, so their bytes are never deleted automatically.

B14.6.3 hsf_transfer_queue is kept as a read only listing; the worker claims work through hsf_transfer_claim.

B14.6.4 Cleanup rows give the upload status (transferred, failed or rejected) as the reason.

B14.6.5 Compound triggers ("A and B", "A or B") are left out of hsf_public_trigger, because generation refuses them.

B14.6.6 Every File release is refused until the Phase 2 provisions are pinned and instrument scope is set (contract 9.3).

B14.6.7 test/sql/hsf_core_checks.sql runs only after a full replay, because the 047 release gate calls a function defined in 050.

B14.7 **Proof on the local replay (23/09/2026).** Replay of 001 to 051 clean; HSF core checks 81 of 81; HSF flow checks 237 passed; node tests 149 of 149; end to end flow 52 of 52; builder browser drive 25 of 25; all fifteen pages clean at 1280 and 390 pixels wide. None of this was run against the live project.

B14.8 **Launch controls round (23/09/2026).** Built from the Director's decisions of 23/09/2026 under hsf/BUILD-CONTRACT.md section 10 (Amendment 2), in migration 052_hsf_launch_controls.sql with the worker, the server and the builder. Like the rest of B14 it opens no gate, and 052 is not applied to the live project (HSF-21).

B14.8.1 Upload gate. The parameter hsf.uploads_open stays false until the Director switches it on, once Odendaal has finished the backend and Cassandra and the designer have finished the front end. Consent, File generation and item status work while it is closed (HSF-19).

B14.8.2 Client verification. Only a company Care Net has verified as a client uploads; the account's own approval is not enough. The builder asks for verification; a sales executive or forge_admin verifies with a method and an evidence reference, or revokes with a reason, which blocks the account's untransferred uploads without deleting them (HSF-19).

B14.8.3 Two year limit. The parameter hsf.staging_retention_days (730, at most 730) limits the stay in the private bucket. Older bytes are deleted by the worker, blocked uploads included, the upload becomes expired and its evidence is withdrawn. The builder shows the date each staged document leaves (HSF-19).

B14.8.4 Security scan. Every upload is scanned before it can be held or moved: a built in structural check (scan-core.js) for mismatched types, PDF active content, Office macros, ActiveX, embedded objects and outside links, CSV formula injection and image location metadata, and a mandatory antivirus engine at HSF_AV_ENDPOINT with HSF_AV_TOKEN. Without the engine nothing transfers. A failed scan rejects the upload and withdraws its evidence; staff give a stuck scan a fresh start with hsf_scan_reset (HSF-19).

B14.8.5 Deletion by the company. A company deletes its own documents still in Care Net staging after the warning "Deleting is permanent. Care Net cannot recover a deleted document, and any File item it supported will return to outstanding.", a tick that it cannot be undone, and a one time PIN by email or SMS that Supabase Auth sends and checks (vercel/api/hsf-delete.js); Care Net never generates or stores a PIN. SMS needs an SMS provider in Supabase Auth and hsf.deletion_sms_enabled. Blocked uploads after a consent withdrawal are shown with their reason and may be deleted this way (HSF-20). Two limits built here await the Director's confirmation: a transfer in flight cannot be deleted for 30 minutes, and an account has at most 10 PIN attempts per hour.

B14.8.6 MCO transfer protocol. MCO builds it; documents stay in Supabase staging in hold mode until then. hsf/MCO-TRANSFER-REQUIREMENTS.md is Care Net's proposal, awaiting MCO's design (HSF-3).

B14.8.7 Legislation clean up. The register release 1.0.0 PDF was removed and its CSV moved to hsf/sources/; both old addresses redirect to /shop.html#law (HSF-10 closed). The onboarding form labels were updated and element names in 048 carry no provision numbers other than 16(2) and 37(2) (HSF-23 (a) to (c)). The Grok bridge runs on the latest Grok model when XAI_MODEL is auto or unset (KERNEL-API.md section 1.3).

B14.8.8 Adversarial review of the round found 8 issues; all were fixed with regression checks.

B14.8.9 Proof on the local replay (23/09/2026). Replay of 001 to 052 clean; HSF core checks 81, flow checks 239 and launch checks 199, all passing; node tests 218 of 218; end to end worker run 38 of 38; builder browser drive 180 of 180 at desktop and phone width. None of this was run against the live project.

B14.8.10 Still needed live before uploads open: the antivirus engine and its two Supabase secrets; the Supabase Auth email template carrying {{ .Token }} so the email holds the PIN; an SMS provider and hsf.deletion_sms_enabled if SMS PINs are wanted; a staff route to see and reset stuck scans and to verify clients (HSF-PORTAL-ARCHITECTURE.md section 8.2).

B14.9 **Console and metadata round (23/09/2026).** Built from the Director's answers of 23/09/2026 on the launch controls under hsf/BUILD-CONTRACT.md section 11 (Amendment 3), in migration 054_hsf_console_and_metadata.sql with the worker, the server, the builder and a new staff console. It follows migration 053_hsf_signoff_rule.sql (the File sign off rule of contract 10.8, HSF-1). Like the rest of B14 it opens no gate, and neither 053 nor 054 is applied to the live project (HSF-21). Migrations 047 to 053 were not edited.

B14.9.1 Metadata removed before a document leaves staging (contract 11.1). After the structural check and the antivirus engine, the scan pass removes every non essential hidden detail (supabase/functions/_shared/metadata-clean.js) and writes the cleaned copy over the staged object at the same path; the original bytes are not kept. Pictures lose EXIF, XMP, IPTC, thumbnails and comments; Word and Excel files lose their author, company, manager, custom properties, comments and thumbnail; PDF files have their document information and XMP metadata blanked in place at the same length. A PDF whose details the cleaner cannot reach or that is encrypted, an older .doc or .xls file and anything it cannot parse are refused with a plain reason and the upload is rejected, never passed as it is. A clean result is recorded only with hsf_scan_record_clean, which carries the fingerprint of the cleaned copy (sha256_clean); only such an upload is claimed for transfer, and the transfer and the staging deletion compare the server and receipt fingerprints with sha256_clean, while the browser fingerprint stays on record as the proof of what the company sent. The write back is announced first (hsf_scan_write_back) under a 30 minute hold on the upload, so a document the company deleted is never written back into staging. The builder shows "Hidden details removed: <labels>" (HSF-19).

B14.9.2 Never deleted in transit (contract 11.2). A document on its way to MyClinicOnline (status transferring) can never be deleted by the company, whatever the age of the claim. If the transfer errors, or a blocked transfer stops part way and the sweep returns it after 30 minutes, the upload is back to uploaded and deletable again. This replaces the 30 minute window of B14.8.5 (HSF-20).

B14.9.3 PIN attempts (contract 11.3). At most 5 PIN attempts per account per hour over all its deletion requests, and 5 per request. This replaces the 10 an hour of B14.8.5 (HSF-20).

B14.9.4 Credentials checked at the point of use (contract 11.4). The parameter hsf.signoff_register_check_max_days (30, from 1 to 365) sets the oldest a signatory's register check may be before the decision day; the release gate refuses an older one. A fresh check of credentials frozen by a release is appended as a dated entry of its own. The staff view hsf_signatory_expiry_alerts and hsf_signatory_expiry_alerts_list() list registrations that expire within 60 days or have expired, with the unreleased Files they signed (hsf/SIGNOFF-CRITERIA.md section 6, HSF-1).

B14.9.5 Staff console (contract 11.5). vercel/hsf-staff.html with vercel/api/hsf-staff.js, in four tabs: clients to verify, scans and staging, signatories, and sign offs and readiness. The API admits only a signed in person with a forge staff role (403 for anyone else), and every write goes through a service role function that checks the staff role again and records the staff member's email. hsf_release_rules is the one statement of the release rules: hsf_release_gate raises its first reason and hsf_release_readiness lists them all without recording anything. An OMP sign off of a File is refused. The page works with the keyboard and at 390 pixels wide, confirms revocation and scan resets inside the page, and shows fictitious rows marked Sample with ?demo=1.

B14.9.6 Grok setup (contract 11.6). grok/setup.mjs checks the bot host's Node version, settings, the kernel API and the xAI model list, and writes XAI_MODEL to grok/.env (or leaves it auto with --auto; --check writes nothing). The model rule is shared with the bridge in grok/model-pick.mjs, and grok/.gitignore keeps .env out of the repository (KERNEL-API.md, HSF-18).

B14.9.7 Retention (contract 11.7). The two year limit in staging stays until the Director has audited what the report builder can do (HSF-19).

B14.9.8 The findings of the review of this round were fixed with regression checks, including the refusal to write a cleaned copy back once the upload has left the scan.

B14.9.9 Proof on the local replay (23/09/2026). Replay of 001 to 054 clean; HSF core checks 82 of 82; flow checks 239, launch checks 202, sign off checks 66 and console checks 157, all passing; node tests 305 of 305; end to end worker run 54 of 54; staff console browser drive 208 of 208, and a browser drive of the console against the local database 229 of 229 at 1280 and 390 pixels wide; the designer asset manifest builds with 16 pages and 211 assets and no warning for the staff console. backup/cognitive_kernel_rebuild.sql, regenerated with 054, replays into a fresh database and passes the same five check files. None of this was run against the live project.

B14.9.10 Still needed live before uploads open: the antivirus engine and its two Supabase secrets; the Supabase Auth email template carrying {{ .Token }}; an SMS provider and hsf.deletion_sms_enabled if SMS PINs are wanted; a forge staff role (forge_admin, forge_omp or forge_safety_reviewer, the roles hsf_user_is_staff accepts) granted to each person who will use the console, including whoever verifies clients, since there is no separate sales executive role; the named signatories with their letters and register checks (HSF-PORTAL-ARCHITECTURE.md section 8.2).
