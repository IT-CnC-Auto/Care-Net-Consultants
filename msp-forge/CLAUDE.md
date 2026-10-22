# CLAUDE.md | CNC MSP Forge | Handover | 22/10/2026

This file explains what has been built in this repo, how the parts fit together, and how to run them. It is written for Quintis (MCO) and for any Claude Code session working in `msp-forge/`. The companion documents are `SPEC.md` (system specification), `BUILD-STATE.md` (phase status at 15/08/2026) and `supabase/migrations/` (the applied history). Where this file and the code disagree, the code wins.

Items marked **(inferred)** were deduced from the code, not stated in a document. Check them before relying on them.

## 1. What this is

MSP Forge is Care Net Consultants' engine for producing South African occupational health **Medical Surveillance Plans** (the Plan). In short:

1. A client signs on, gets a quote and completes an online assessment.
2. A deterministic pipeline drafts the Plan against a triple verified legal and OHS kernel held in Supabase Postgres.
3. The document factory renders a dual branded DOCX (Care Net and the client's logo), marked PLANNING ONLY.
4. A registered Occupational Medical Practitioner (OMP) reviews, recommends and signs.
5. A database gate refuses release until an approved OMP review exists.

The same repo also holds:

* **HSF Forge:** a Health and Safety File builder and portal, with uploads designed to transfer to MCO (`SPEC.md` Part B, `HSF-PORTAL-ARCHITECTURE.md`).
* **Kernel API:** a read only API over the kernel, plus a Grok bot pack (`KERNEL-API.md`, `grok/`).
* **Bee-Inspect:** Supabase `bi_` schema and an Expo mobile app (`apps/mobile/`, `docs/bee-inspect/`).
* **Employee Operations App:** a separate static front end prototype in `../Care Net Employee Operations App/`. It has no backend and is not live.

## 2. Direction agreed for MCO (October 2026)

* The Medical Surveillance Plan will **live in MCO**. Clients are directed to MCO, Care Net reviews internally first, and the doctors sign off in MCO.
* First target: Care Net's own Plan, set up and running on MCO. OMPs and their pricing come after that. Barteldt negotiates OMP pricing.
* Many clients will use the tool on its own to work out which medicals their company needs, without OMP sign off.
* Clients who want OMP sign off book a **Surveillance Plan Review** through a JC on MCO. Pricing sits in Xero. The signed Plan is released to the client only once it is **signed, invoiced and paid**.

What exists today for this: the OMP review, sign and release gate in Supabase (section 4, steps 7 to 9). What does not exist yet: Plan hosting or filing in MCO (open item CR-13.12), the release email, and any Xero link. Section 10 lists the MCO work.

## 3. Directory map (`msp-forge/`)

| Folder | Purpose |
| --- | --- |
| `agent/` | The drafting pipeline (`pipeline.js`), CLI runner, Construction kernel snapshot, draft of record |
| `factory/` | Document factory: DOCX renderer, locked templates, OMP config, brand assets, PLANNING ONLY marking, sample PDF |
| `skills/cnc-msp-dualbrand/` | Brand and geometry standard (`SKILL.md`), `verify_geometry.py`, `prepare_client_logo.py` |
| `form/` | `fields.json` (single source of truth for intake fields), generated `schema.json`, HTML and DOCX form builders |
| `kernel/` | `INGESTION.md` (verification workflow), `OHS-KERNEL-RECONCILIATION.md`, the Director's sandbox kernel pack |
| `supabase/` | 74 migrations (001 to 074), 23 edge functions plus `_shared`, 2 seed files |
| `vercel/` | Static site (about 20 pages), 17 serverless API handlers, `lib/` (auth, db, validate), `vercel.json`, `kernel-api/openapi.yaml` |
| `server/serve.js` | Dependency free Node host that mimics Vercel. The stated path for hosting the web layer inside MCO |
| `grok/` | xAI Grok bot pack that reads the kernel API |
| `hsf/` | HSF contract, MCO transfer requirements, sign off criteria, pricing research, generators |
| `test/` | SQL replay harness, Node tests, browser drives |
| `apps/mobile/` | Bee-Inspect Expo app (has its own `CLAUDE.md`) |
| `backup/` | Concatenated rebuild SQL and `MANIFEST.md` |
| `WIRING.html` | Wiring snapshot at 15/08/2026, covers migrations 001 to 038 only, so it is stale |

## 4. End to end flow for a Plan

1. **Sign on and quote.** `vercel/index.html` and `shop.html` call `/api/signon` (`msp_client_account`, `msp_client_signon`, migration 039) and `/api/quote` (`msp_create_quote`). Above 100 people the quote becomes a written quote (migration 070).
2. **Intake.** The client opens a single use token link to `assess.html`. `/api/access-check` gates it, `/api/draft` saves progress, `/api/intake` submits. `lib/validate.js` validates: a run that looks like an SA ID number, or a failed rule, sends the submission to triage, and missing consent stores nothing. Everything is written through one RPC, `msp_ingest_intake` (migration 006), into `msp_engagement`, `msp_intake`, `msp_intake_site`, `msp_intake_job_category`, `msp_intake_exposure`, `msp_intake_chemical`, `msp_consent` and `msp_audit`. References look like `CNC-MSP-YYYY-MMDD-NNN`. The older DocuSeal route (`/api/docuseal-webhook`) uses the same RPC.
3. **Drafting.** pg_cron calls the edge function `msp-intake-worker` every 5 minutes (migration 066). It runs the pipeline (classify, frame, profile, prescribe, compose, validate) and writes to `msp_draft` and `msp_defect`. A clean draft moves to `awaiting_booking`, a failure to `triage` (migration 071). Events go to `msp_event`, and sales mails go out through Microsoft Graph.
4. **Triage correction.** `msp_triage_correct`, `msp_triage_close`, `msp_triage_cases`, `msp_pipeline_rerun` (migrations 067, 072).
5. **Booking and deposit gate.** `msp_booking_confirm`, one time sales links (`msp_booking_link_*`), `msp_client_booking_choice`. Status moves to `booking_confirmed` (migration 074).
6. **Render.** Edge function `msp-plan-render` (migration 073) uses `factory/render_core.js` and stores files in private buckets `msp-factory` and `msp-plans`, recorded in `msp_document`. PDF conversion goes through SharePoint and Graph and only runs once `integration.msp_pdf_site` is granted.
7. **OMP review.** `vercel/review.html` calls `msp_omp_decide`, `msp_omp_recommend` and `msp_omp_sign` (canvas signature and HPCSA number), writing to `msp_omp_review` and `msp_omp_recommendation` (migrations 007, 008).
8. **Sign off marking.** `msp_plan_signoff(reference)` (migration 069). The PLANNING ONLY marking lifts only when that record shows an approved, signed decision.
9. **Release gate.** Trigger `msp_release_requires_approval` calls `msp_release_gate()` on `msp_release` and refuses any insert without an approved `msp_omp_review` (`supabase/migrations/007_msp_draft_review.sql`). `msp_release_pack` exists (migration 008) but no page calls it yet.
10. **Delivery.** The release email is a later build. Until then IT sends the rendered Plan by hand.

## 5. The brain (kernel and agent)

### Kernel schema (prefix `msp_`)

`msp_legal_instrument` (status pending, verified, excluded, superseded), `msp_industry`, `msp_subindustry`, `msp_job_role`, `msp_hazard` (with OEL and its instrument), `msp_job_hazard`, `msp_test_protocol`, `msp_industry_instrument`, `msp_kernel_rule`, `msp_kernel_exclusion`, `msp_confirmation_item`, `msp_kernel_version`, `msp_kernel_agent_run`, `msp_omp_industry_review`, `msp_instrument_currency_hold`, `msp_precedent` (migrations 001, 003, 030, 050).

Content at 15/08/2026 (`BUILD-STATE.md`): 17 industries, 56 subindustries, 316 roles, 851 role to hazard maps, 31 test protocols (the reconciliation doc and `backup/MANIFEST.md` say 30), 31 verified legal instruments.

The database enforces rules such as a 12 month periodic floor, RULE-NOISE-TRANSITION, RULE-HPCSA-PAYER and ODMWA or COIDA routing.

### Triple verification (`kernel/INGESTION.md`, migration 003)

* `msp_ingest_instrument` stages a pending row.
* `msp_verify_instrument` asserts gate a (primary text), gate b (corroboration) and gate c (currency), with a future review date.
* `msp_exclude_instrument` records a failure. `msp_verification_due` is the 60 day watchdog.
* Currency holds (migration 050) withhold an instrument even while it reads verified.
* Only instruments in the view `kernel_citable_instrument` can appear in a Plan. Pending instruments are uncitable by design.

### Versioning and the monthly audit (`SOP-KERNEL-AGENT.md`)

* `msp_kernel_release(semver, summary)` (forge_admin only), with OMP ratification fields.
* `msp_kernel_monthly_audit()` runs from pg_cron job `msp_monthly_audit`.
* Kernel updates are done in a Claude Code session following the SOP. Every change is a new migration file.

### The drafting pipeline (`agent/pipeline.js` v1.0.2)

* **Deterministic. No AI writes any part of a Plan.** `SPEC.md` section 6.1 still describes LLM drafting; the code has replaced that.
* Exports `classify`, `frame`, `profile`, `prescribe`, `compose`, `validateDraft`. Confidence below 0.85 sends the case to triage.
* `validateDraft` runs 10 checks (the docs still say 9): `CITATIONS_RESOLVE_VERIFIED`, `INTERVALS_HAVE_BASIS`, `EXIT_MEDICALS_PRESENT`, `DUAL_JUSTIFICATION_PRESENT`, `NO_CONFIRM_ASSUMPTION_TAGS`, `PROSE_RULE_HOLDS`, `NO_MISSING_VALUE_TEXT`, `NO_INDIVIDUAL_CLINICAL_DETAIL`, `LOCKED_BLOCKS_PRESENT_VERBATIM`, `ODMWA_COIDA_ROUTE_CORRECT`.
* `supabase/functions/msp-intake-worker/build.mjs` copies `pipeline.js` into the edge function. `test/intake-worker.test.mjs` fails if the two drift. **Change `agent/pipeline.js`, then rebuild the worker.**

Run it locally (this overwrites `agent/draft.json`, so work on a copy):

```
node agent/run_pipeline.js agent/kernel_snapshot_constr.json test/normalised_synthetic.json CNC-MSP-2026-0812-001 2026-08-12
```

On 22/10/2026 this ran with all 10 checks passing.

### Where AI is used (assist only, never drafting)

* **`msp-assistant`** edge function (Anthropic). Actions: `industry_brief`, `triage_other`, `explain_plan`, `monthly_watch`. Answers only from rows returned by `msp_ai_context_*`, has a spend ceiling, and logs to `msp_ai_call_log`. Model set by parameter `ai.model`.
* **`grok/`**: an external Grok Q&A bot that reads `GET /api/kernel`. Keys (prefix `cnck_`) are issued by `msp_api_client_issue`, stored hashed in `msp_api_client`, limited to 600 calls per hour.

Runtime parameters live in `msp_env_parameter`, writable only by forge_admin through `msp_env_set`, with history in `msp_env_parameter_history`.

## 6. Document factory and templates

**Inputs:** a draft JSON (shape of `agent/draft.json`), `factory/templates.json`, `factory/config.json` (designated OMP), `factory/assets/` (CNC header and footer banners, client logo, PLANNING ONLY marking).

**Locked templates** (`factory/templates.json`, inserted verbatim, never paraphrased):

| ID | Block |
| --- | --- |
| `TPL-LIA-01` | Liability |
| `TPL-POP-01` | POPIA |
| `TPL-SGN-01` | Sign off |
| `TPL-EXA-01` | Exam types |
| `TPL-CGN-01` | Exceedance note |

**Renderers:**

* `factory/render_core.js` v1.3.0: `buildPlan(docx, draft, inp)`. Pure, shared by the CLI and the `msp-plan-render` edge function.
* `factory/render_pack.js`: the CLI. `node render_pack.js <draft.json> <out.docx>`. Set `MSP_SIGNOFF=<signoff.json>` for a signed, unmarked Plan, and `MSP_CLIENT_LOGO` or `MSP_CLIENT_LOGO_SIZE` to change the client logo. Needs `docx@9.10.0` on `NODE_PATH`; no package.json declares it yet.
* `factory/make_marking.py` (Pillow) draws the marking. `factory/render_sample_pdf.py` (ReportLab) builds the public watermarked sample.
* Example output: `factory/CNC-MSP-2026-0812-001_Medical_Surveillance_Plan_DRAFT.docx`.

**Brand rules** (`skills/cnc-msp-dualbrand/SKILL.md`): CNC banner left, client logo right (max 130 px in a 102 px band), Arial, red #ED1B24 and charcoal #1A1A1A. Locked footer: "Proudly prepared by the Care Net Consultants Team. Your Partner in Workplace Health." The base `cnc-letterhead` skill is referenced but is not in this repo; letterhead assets are in `hsf/examples/letterhead`.

**Geometry check:** `python3 skills/cnc-msp-dualbrand/scripts/verify_geometry.py <pack.docx>` checks header and footer extents, clear space, footer line, page field, margins and locked anchors (16 of 16 documented). A raster check needs LibreOffice (open item CR-13.11).

**Intake form templates:** `form/fields.json` feeds `build_form_html.js` (the assess page) and `build_form_docx.js` (DocuSeal DOCX and `schema.json`). Field names match the database columns and placeholders.

**HSF examples:** `hsf/build_examples.mjs` turns `hsf/examples/*.json` into `vercel/examples/*.docx` and `.pdf`.

## 7. Supabase

* Project URL: `https://pboebfnujzffgwctsplw.supabase.co`. This is shared with other Care Net and AutoHive systems **(inferred from `WIRING.html` and migration headers)**. Check the live migration list in `supabase_migrations.schema_migrations` before applying anything.
* Migrations, in groups:
  * 001 to 009: kernel, RLS, verification, Construction seed, intake, drafting and review, OMP workflow, commercial.
  * 010 to 029: industry batches and hygiene.
  * 030 to 046: productisation, shop, public views, parameters and AI, cron, sign on, legislation currency, public register.
  * 047 to 058: HSF engine, consent, uploads and MCO transfer, kernel API, launch controls, sign off rule, console, guidance, attribution.
  * 059 to 065: Bee-Inspect (`bi_`). **Not applied to live.**
  * 066 to 074: intake automation, redraft, mail Bcc, PLANNING ONLY marking, fee cap, events, triage correction, server render, booking gate. Live status not recorded in the docs.
* **RLS:** on for every table, deny by default, no anon policies. Roles come from JWT `app_metadata.msp_roles`: forge_agent, forge_verifier, forge_omp, forge_admin, forge_safety_reviewer, checked by `msp_has_role()` and `msp_any_forge_role()` (migration 002). All writes go through SECURITY DEFINER RPCs that check the role inside the function. Anon can read only `msp_public_industry_profile`, `msp_public_framework_stats` and the register view.
* **Release gates:** `msp_release_gate` for Plans. `hsf_release_gate` and `hsf_release_rules` for Files (migrations 053, 054).
* **Edge functions:**
  * `msp-intake-worker`: drafting and notifications.
  * `msp-plan-render`: server side DOCX and PDF.
  * `msp-assistant`: the AI assistant.
  * `hsf-mco-transfer`: scan, strip metadata, transfer to MCO (currently in hold mode).
  * Bee-Inspect functions (thin wrappers over `_shared/bi/handlers/`), several still 501 stubs.
  * Shared: `mco-adapter.js`, `transfer-core.js`, `scan-core.js`, `metadata-clean.js`.
* **Secret names** (values live in Supabase secrets or Vault, never in the repo): `ANTHROPIC_API_KEY`, `GRAPH_TENANT_ID`, `GRAPH_CLIENT_ID`, `GRAPH_CLIENT_SECRET`, `MAIL_SENDER`, `HSF_AV_ENDPOINT`, `HSF_AV_TOKEN`, `MCO_BASE_URL`, `MCO_API_TOKEN`, `SB_URL`, `SB_SERVICE_ROLE_KEY`. Vault secret `msp_worker_key` gates the workers. `HSF_SCAN_ALLOW_FIXTURE` and `HSF_MCO_ALLOW_FIXTURE` must stay unset in production.

## 8. Web layer (`vercel/`)

* Vercel projects `cnc-msp-forge` (production) and `cnc-msp-forge-staging`, root `msp-forge/vercel` (`STAGING.md`). Node 18 or later. No build step.
* Pages:
  * Plan: index, shop, assess, account, review (OMP), settings (admin), medical-surveillance-plans, industry, method, how-it-works, sample.
  * File: health-and-safety-file, hsf-builder, hsf-sample, hsf-staff, legislation, portal.
  * Bee-Inspect: bee-inspect, claim, get-app.
* API routes: access-check, company-lookup, docuseal-webhook, draft, intake, kernel, kernel-stats, payment-confirm (manual until a payment gateway exists), portal-summary, quote, signon, hsf-consent, hsf-delete, hsf-events, hsf-file, hsf-staff, hsf-upload.
* Env var names: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ADMIN_ACTION_SECRET`, `DOCUSEAL_WEBHOOK_SECRET`. For hosting in MCO through `server/serve.js`: `MCO_BASE_URL`, `MCO_API_TOKEN`, `PORT`, `HOST`, `SERVE_QUIET`.
* The Supabase publishable (anon) key appears in several pages and `vercel/js/cnc-config.js`. It is public by design; RLS protects the data.

## 9. Running and testing

| What | Command |
| --- | --- |
| Local web host | `node server/serve.js --port 3000` |
| API and MCO tests | `node --test test/api/*.test.js test/api/*.test.mjs test/mco/*.test.mjs` |
| Worker and pipeline copy in sync | `node test/intake-worker.test.mjs` |
| Validator synthetic cases | `node test/run_synthetic.js` |
| Render tests | `NODE_PATH=<dir with docx@9.10.0>/node_modules node test/plan-render.test.mjs` (and `test/render-marking.test.mjs`) |
| SQL replay | Local PostgreSQL 16 on socket `/tmp`, port 55432, user postgres. `bash test/sql/replay.sh`, then `psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/<name>_checks.sql` |
| Browser checks | `test/browser/*.mjs` (Playwright, Chromium) |
| Mobile | `cd apps/mobile && npm test && npx tsc --noEmit && npx expo lint` |

State on 22/10/2026: 604 Node tests, 601 pass, 3 fail. All three are test expectations that lag the latest copy changes:

* `test/api/bee-inspect-pages.test.js:252` expects "MyClinicOnline", but the page now says "My Clinic Online".
* `test/api/file-separation.test.js:660` and `:677` still expect `pilot.html`, which was renamed to `how-it-works.html` on 22/10/2026.

## 10. MCO integration: what exists and what is open

`hsf/MCO-TRANSFER-REQUIREMENTS.md` is Care Net's **proposal**. MCO designs the real protocol. No MCO endpoint is known yet, `mco-adapter.js` uses a placeholder path, and the transfer worker runs in hold mode (`hsf.mco_transfer_mode`).

The proposal, for HSF documents:

* One document per request: uploadId (idempotency key), bytes up to 25 MB, mimeType, fileName, sha256, clientAccountId, departmentCode, sectionCode.
* MCO returns its reference and a sha256 recomputed over the stored bytes. Care Net deletes its staging copy only on a three way hash match.
* Proposed error codes: unauthorised, company_not_matched, unsupported_type, too_large, fingerprint_mismatch, conflict, security_refused, rate_limited, unavailable, invalid_request.
* Never match on names. HTTPS with signed requests or mTLS preferred over a bearer token.
* POPIA operator terms, data location and breach notice. Retention by record class: 40 year floor for medical surveillance records.
* No deletion on request once a document is in transit or at MCO (Director's rule).
* Section 14 lists twelve questions for MCO.

The read side adapter (`McoAdapter`: company, people, medicals, training) and SSO options are in `SPEC.md` B10 and `HSF-PORTAL-ARCHITECTURE.md` section 7. The fixtures folder that B10.5 cites (`test/fixtures/mco/`) does not exist.

**Open for the Plan moving into MCO:**

1. Where the Plan lives in MCO and how it is filed (CR-13.12).
2. How MCO calls the Forge: review queue, OMP sign off and release (today `review.html` and the `msp_omp_*` RPCs).
3. Booking the Surveillance Plan Review as a JC on MCO, and how "invoiced and paid" in Xero reaches the release gate. Today payment is confirmed by hand (`/api/payment-confirm`).
4. The release email or MCO delivery that replaces IT sending the Plan by hand.
5. SSO and roles: no `forge_omp` user exists yet.

## 11. Other open items

* OMP: practitioner mail off until `integration.msp_notify_omp_to` is set. All 17 `msp_omp_industry_review` rows pending. OMP ratification of kernel release 1.1.0.
* PDF needs the SharePoint `Sites.Selected` grant.
* Payment gateway (CR-13.13), LibreOffice (CR-13.11), licensed SANS (CR-12.3), DPAs (CR-12.5), Information Officer (CR-12.6), antivirus engine, SMS provider.
* 4 or 5 legal instruments still pending (documents differ), including the General Machinery Regulations.
* HSF Forge: phase 1 awaits approval, phases 2 to 7 blocked. The sign off rule awaits the attorney.
* Bee-Inspect: migrations 059 to 065 not applied, app not on a device.
* Docs out of date: "9 of 9" checks (there are 10), `WIRING.html`, and `SPEC.md` 6.1 on AI drafting.

## 12. Rules for working in this repo

* SA British English. Dates DD/MM/YYYY. Rand as R4 250,00.
* No dash punctuation (em or en dash) in any client facing text. The validator check `PROSE_RULE_HOLDS` enforces this in Plans. No emoji in mails.
* Locked template blocks are inserted verbatim. No CONFIRM or ASSUMPTION tags in a deliverable.
* Care Net screens and does not diagnose. The employer pays. No individual clinical detail in a Plan. ODMWA or COIDA routing comes from the kernel rule only.
* POPIA: never collect or store SA ID numbers (validators refuse them). Never claim "POPIA compliant" on the site.
* Secrets never go in the repo or in a table. Only `supabase_secret:` references.
* Migrations are additive and prefixed (`msp_`, `hsf_`, `bi_`). Never edit an applied migration. Nothing is applied to live without the Director's approval.
* Keep Care Net separate from AutoHive content. The CRM is named "AutoHive CRM" only.

## 13. Repo notes

* Remote: `IT-CnC-Auto/care-net-consultants`, branch `main`. `STAGING.md` refers to an earlier home, `Barteldt/Care-Net-Consultants`, with staging built from branch `claude/build-run-mitkxf`.
* No root package.json. Node dependencies are per folder (`vercel/`, `apps/mobile/`).
* Personal data in the repo: `Care Net Employee Operations App/uploads/Operations_nhf6c7lv9fs.pdf` (staff names and roles) and `factory/config.json` (the designated OMP's name and HPCSA and SASOM numbers). All other samples, seeds and tests use fictitious companies.
