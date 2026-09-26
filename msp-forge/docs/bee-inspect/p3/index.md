# Bee-Inspect P3: backend

Bee-Inspect P3 (hsf/BEE-INSPECT-BUILD-PROMPT.md sections 6 and 7, phase P3, applied under hsf/BUILD-CONTRACT.md 16), 26/09/2026. Data model, Row Level Security, Edge Functions with labelled stubs for every unknown vendor, and a fictitious demonstration seed. Not committed, not deployed, nothing applied to the live Supabase project or to Vercel. Migrations 001 to 058 are byte identical.

## STOP items

1. [Migration list](#migrations)
2. [RLS results per role](#row-level-security-results)
3. [Edge Functions, stub status and settings](#edge-functions)
4. [Open questions](#open-questions)

## How Bee-Inspect joins the free File

- The Bee-Inspect company is the File's company, `msp_client_account`. `bi_company` holds only the Bee-Inspect onboarding record of that same row (primary key `client_account_id`); nothing about the company is copied.
- The tenant (`bi_tenant`) is whoever pays: a consultancy whose competent persons inspect client companies, or an employer inspecting itself. A tenant holds a paid line per company (`bi_company_subscription`): base R299,00 a month or extra company R199,00 a month, excluding VAT.
- An Issued report files itself into the company's File, in the same transaction that issues it (`bi_hsf_section_f_sync`): the template names its Section F register (for example scaffolds to HSF-F-01, ladders HSF-F-02, lifting HSF-F-03, portable electrical HSF-F-04, fire HSF-F-06, PPE HSF-F-11, hazardous chemicals HSF-F-12); that File item receives a new `hsf_evidence` version (source `engine_generated`, the PDF fingerprint, "Bee-Inspect report signed by <name>"), turns from outstanding to uploaded, and the File's compliance figure is recomputed and audited in `msp_audit`, exactly as a client upload does. The link is kept in the new `bi_report_file_link`, so no File table is altered. When the element is not on the File the report is still listed in Section F (`section_only`); when the company has no File yet the link waits (`no_file`) and the hsf-section-f-sync function files it later. A withdrawn report has its evidence revoked. `bi_section_f_reports` gives the builder's Section F "Inspection reports" list (title, site, date, signed by, status).

## Migrations

All five are new files; none alters an applied table. Every object is `bi_` prefixed. 059 begins with a guard that refuses to run if any `bi_` table or function already exists, so a name clash on live stops the migration instead of mixing objects. Checked against 001 to 058: no `bi_` table, view, function, parameter (`bi.*`), bucket (`bi-evidence`, `bi-reports`) or trigger name exists there. Replay: `bash test/sql/replay.sh` (the local database has no pgvector; replay.sh rewrites `extensions.vector(1536)` to `real[]`, as for msp_precedent).

| File | Objects | Purpose |
| --- | --- | --- |
| 059_bi_core_tenancy.sql | `bi_tenant`, `bi_company`, `bi_company_subscription`, `bi_app_user`, `bi_role_assignment`, `bi_inspector_profile`, `bi_inspector_qualification`, `bi_fica_record`, `bi_consent_record`, `bi_audit_log`, `bi_feature_flag`, `bi_rate_event`, `bi_step_up`; helpers `bi_is_ops`, `bi_user_is_ops`, `bi_user_roles`, `bi_my_roles`, `bi_can`, `bi_can_company`, `bi_my_app_user_id`, `bi_subscription_live`, `bi_flag_enabled`, `bi_rate_allow`, `bi_audit`; functions `bi_step_up_record`, `bi_fica_list`, `bi_qualification_list`, `bi_company_set_status`, `bi_inspector_set_status`, `bi_role_grant`, `bi_role_revoke`; parameters `bi.vat_mode` (to_be_confirmed), `bi.markup_default` (3.0), `bi.step_up_window_minutes` (10) | Tenancy and roles (inspector, assistant, company_admin, ops); company onboarding status Not started, In review, Active, Blocked; inspector path Identity, FICA, Qualifications, Competence review, Cleared, Restricted, Assistant only; FICA and qualification reads only through functions that audit every row read; append only audit trail; flags `bee_inspect_ads` and `welcome_hook`, both off; rate limiter; step up MFA record |
| 060_bi_sites_inspection_engine.sql | `bi_site`, `bi_department` (File department codes), `bi_building`, `bi_room`, `bi_template`, `bi_template_item`, `bi_inspection`, `bi_inspection_area`, `bi_equipment`, `bi_finding`, `bi_photo`, `bi_voice_note`, `bi_voice_transcript`, `bi_risk`, `bi_corrective_action`, view `bi_risk_register`; `bi_fail_rule_violations`, `bi_inspection_submit`, `bi_inspection_set_status`, `bi_risk_band`, `bi_risk_score`, `bi_risk_top_control`, `bi_evidence_seal`, `bi_schedule_reminders_run`, `bi_ncr_escalation_run` | Sites tree (company, site, department, building or zone, room or area); templates mapped to Section F registers; findings Pass, Fail, N/A, Observe; the Fail rule at submit (photo and corrective action, plus a voice note under the strict policy); sealed photo and voice note evidence (GPS, time, inspector, fingerprint; paths only); VN numbering and versioned transcript corrections; 5 x 5 inherent and residual risk with the hierarchy of controls; corrective actions with closure evidence and escalation; legal hold; conflict safe offline sync (row_version) |
| 061_bi_reports_signatures_kernels.sql | `bi_kernel_version`, `bi_kernel_doc`, `bi_kernel_chunk` (embedding `extensions.vector(1536)`), `bi_report`, `bi_report_version`, `bi_signature`, `bi_report_file_link`, `bi_transfer_package`; guard `bi_report_guard`; `bi_report_save_draft`, `bi_report_request_signoff`, `bi_report_assign_reviewer`, `bi_report_sign`, `bi_report_issue`, `bi_report_withdraw`, `bi_report_share_create`, `bi_hsf_section_f_sync`, `bi_hsf_section_f_sync_pending`, `bi_section_f_reports`, `bi_transfer_package_store` | Report kernel store; versioned report JSON (AI drafts must carry "Assistive draft. Competent person sign off required."; every claim a kernel reference); the Issued guard; Section F filing; secure share link (token shown once, 1 to 30 days); MCO package `supabase_stored` (`mco_ingested` reserved and refused) |
| 062_bi_wallet_billing_usage.sql | `bi_rate_card`, `bi_wallet`, `bi_wallet_ledger`, `bi_usage_event`, `bi_iap_receipt`, `bi_storage_meter`; `bi_price_cents`, `bi_charge_rule_cents`, `bi_storage_level`, `bi_wallet_estimate`, `bi_wallet_charge`, `bi_wallet_credit`, `bi_wallet_grant_included`, `bi_wallet_topup_apply`, `bi_wallet_expire_lots`, `bi_wallet_balance`, `bi_wallet_set_cap`, `bi_wallet_set_autotopup`, `bi_autotopup_queue`, `bi_iap_apply`, `bi_welcome_hook_grant`, `bi_storage_status`, `bi_storage_gate` (trigger), `bi_storage_meter_run` | AI Wallet in rand (cents, excluding VAT); price and charge rules; included value rolls one month, purchased lasts 12 months, oldest expiry spent first; top ups and automatic top up; store receipts once per event; photo tagging free to 50 per report; 10 GB per line with 80% and 95% warnings and new photos and voice notes refused at 100% |
| 063_bi_ads_claims_mco_popia.sql | `bi_ad_config`, `bi_ad_dismissal`, `bi_claim_code`, `bi_attribution`, `bi_mco_node`; `bi_banner_state`, `bi_claim_code_create`, `bi_claim_code_redeem`, `bi_attribution_record`, `bi_mco_register`, `bi_qualification_expiry_run`, `bi_clinical_column_check`; buckets `bi-evidence`, `bi-reports` (private, no storage policy) | Banner tenant toggle and per person dismissals (the P1 stubs); claim codes (hash only, 10 minutes, single use, rate limited); conversion attribution (hsf_attribution_event of 058 holds no person and only attribution_seen, so it does not fit; banner events are still mirrored to hsf_ad_event of 057 without the person); MCO nodes `registered_local`; qualification expiry run; POPIA clinical column check |

Rows written into applied tables, always through their existing rules and never by altering them: `hsf_evidence` (insert, revocation), `hsf_file_item` (status outstanding or expired to uploaded, and back on withdrawal), `hsf_file.compliance_pct` (through `hsf_compute_compliance`), `msp_audit` (filing rows), `msp_env_parameter` (three `bi.*` rows), `storage.buckets` (two rows), `hsf_ad_event` (through `hsf_ad_event_record`).

### Money, worked in rand

The AI rates are placeholders in the rate card until `{{rate_card}}` is confirmed, so every AI estimate answers `rate_card_pending` today (capture and template reports keep working). The worked numbers below use TEST rates inside the checks only.

| Case | Numbers | Result |
| --- | --- | --- |
| Price | 200 000 tokens in at $0.20 per million, 20 000 out at $0.50, 10 minutes at $0.006, fx 18,50, markup 3,0 | $0.11 x 18,50 x 3,0 = R6,105, charged R6,11 |
| Charge rule | estimate R5,00; actual R6,00, R6,25, R6,26 | R6,00; R6,25; R5,00 (more than 25% above) |
| Draft | estimate R21,09, actual R22,76 | R22,76 charged, from the included value first |
| Photo tagging | 40 photos, then 30 more on the same report | free; 10 free and 20 charged (28 cents at the test rates) |
| Shortfall | two R59,94 actions against R100,00 | R59,94 and R40,06 charged, R19,88 carried by Care Net, balance never below R0,00 |
| Top ups | R99, R249, R499, R999 | R99,00, R260,00, R550,00, R1 150,00 of value, 12 months |
| Seed wallet | R150,00 included less R11,80, plus a R249,00 top up | R398,20 available |

## Row Level Security results

RLS is on for all 47 `bi_` tables; anon has no privilege on any `bi_` table, view or function; no client may insert, update or delete the wallet ledger, signatures, reports or report versions, the audit log, usage events, receipts, claim codes, step ups, qualifications or FICA records. Ops is Care Net staff through the existing `hsf_is_staff()` (forge_admin, forge_omp, forge_safety_reviewer) or an ops assignment only the service role can grant.

Rows each role reads, from `test/sql/bi_rls_checks.sql` (the seed plus two more fictitious tenants: "other" has a line on another company only; "third" has its own line on the Rietvlei company). "denied" means no privilege at all: those tables are read only through audited functions or the service role.

| Table | Inspector | Assistant | Company admin | Ops | Other tenant | Third tenant, same company | Anon |
| --- | --- | --- | --- | --- | --- | --- | --- |
| bi_inspection | 2 | 2 | 2 | 4 | 1 (own) | 1 (own) | denied |
| bi_finding | 6 | 6 | 6 | 6 | 0 | 0 | denied |
| bi_photo | 3 | 3 | 3 | 3 | 0 | 0 | denied |
| bi_voice_note | 2 | 2 | 2 | 2 | 0 | 0 | denied |
| bi_risk | 3 | 3 | 3 | 3 | 0 | 0 | denied |
| bi_corrective_action | 2 | 2 | 2 | 2 | 0 | 0 | denied |
| bi_site (sites tree) | 1 | 1 | 1 | 2 | 1 (own company) | 1 (shared company) | denied |
| bi_company | 1 | 1 | 1 | 2 | 1 (own) | 1 | denied |
| bi_report (Issued) | 1 | 1 | 1 | 1 | 0 | 0 | denied |
| bi_report_version | 1 | 1 | 1 | 1 | 0 | 0 | denied |
| bi_signature | 1 | 1 | 1 | 1 | 0 | 0 | denied |
| bi_report_file_link | 1 | 1 | 1 | 1 | 0 | 0 | denied |
| bi_wallet | 1 | 0 | 1 | 1 | 0 | 0 | denied |
| bi_wallet_ledger | 3 | 0 | 3 | 3 | 0 | 0 | denied |
| bi_usage_event | 1 | 0 | 1 | 1 | 0 | 0 | denied |
| bi_audit_log | 0 | 0 | 8 (company rows) | 9 (all) | 0 | 0 | denied |
| bi_app_user | 3 (tenant) | 1 (self) | 3 (tenant) | 5 | 1 (self) | 1 (self) | denied |
| bi_template (library) | 7 | 7 | 7 | 7 | 7 | 7 | denied |
| bi_inspector_qualification | denied | denied | denied | denied | denied | denied | denied |
| bi_fica_record | denied | denied | denied | denied | denied | denied | denied |
| bi_claim_code | denied | denied | denied | denied | denied | denied | denied |

Writes, also proved there: the inspector records findings, opens inspections in their own name only and cannot submit directly (functions only); the assistant records findings and photos in their own name but not risks or inspections; the company admin edits the sites tree but records no findings; another tenant writes nothing into this tenant's inspection and cannot open an inspection on a company it holds no line on; ops reads everything and captures nothing directly; a submitted inspection's capture is read only; a lapsed line removes every read of that company. The company admin reads the company FICA pack and the inspector their own qualifications only through `bi_fica_list` and `bi_qualification_list`, and every record read is audited (`fica_read`, `qualification_read`); the assistant and other tenants are refused.

## Edge Functions

Deno TypeScript entry points `supabase/functions/<name>/index.ts`, each a few lines over a plain ES module handler in `supabase/functions/_shared/bi/handlers/<name>.js` (the hsf-mco-transfer style), with shared pure logic in `supabase/functions/_shared/bi/` (pricing.js, risk.js, claim-code.js, report.js, validate.js, http.js). Validation uses a small hand written validator with zod's shape (`v.object`, `safeParse`, `parse`), because `npm:zod` cannot be imported by both Deno and node --test without the network at test time. Every function reads `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` (platform); only the other settings are listed. Names only; values belong in Supabase secrets.

| Function | Caller | Status | Settings it needs |
| --- | --- | --- | --- |
| claim-code-create | signed in | Working | BI_CLAIM_LINK_BASE (optional, the address the QR opens) |
| claim-code-redeem | the phone, not signed in | Working (Supabase Auth one time sign in token) | none |
| hsf-events | not built | The Vercel `/api/hsf-events` (vercel/api/hsf-events.js) is the implementation; server side conversion events go to `bi_attribution` through the database functions | none |
| report-draft | signed in inspector | Working template draft; AI path runs only with its settings (estimate, one xAI call, charge) | XAI_API_KEY, XAI_MODEL_QUALITY, XAI_BASE_URL (optional) |
| transcribe | service | Stub, 501 | TRANSCRIBE_PROVIDER, TRANSCRIBE_API_KEY |
| wallet-estimate | signed in | Working | none |
| wallet-charge | service | Working, idempotent | none |
| revenuecat-webhook | RevenueCat | Working once configured; 501 until then; unmapped products recorded as rejected | REVENUECAT_WEBHOOK_AUTH, BI_RC_PRODUCT_MAP |
| ozow-notify | Ozow | Stub that rejects every notification, 501 | OZOW_SITE_CODE, OZOW_PRIVATE_KEY, OZOW_API_KEY |
| autotopup-run | cron (hourly) | Queue working; charging is a stub, 501 when wallets are due | SAVED_CARD_GATEWAY, SAVED_CARD_API_KEY |
| storage-meter | cron (daily) | Working; warnings returned, not sent | EMAIL_PLATFORM, EMAIL_API_KEY (pending) |
| docuseal-webhook | DocuSeal | Working once configured; 501 until then; ignores submissions that are not Bee-Inspect | DOCUSEAL_WEBHOOK_SECRET |
| kyc-webhook | KYC vendor | Stub, 501 | KYC_VENDOR, KYC_WEBHOOK_SECRET |
| qualification-expiry | cron (daily) | Working; alerts returned, not sent | EMAIL_PLATFORM, EMAIL_API_KEY (pending) |
| schedule-reminders | cron (daily) | Working; reminders returned, not sent | EXPO_ACCESS_TOKEN, EMAIL_PLATFORM (pending) |
| ncr-escalation | cron (daily) | Working; escalations returned, not sent | EMAIL_PLATFORM (pending) |
| hsf-section-f-sync | service or cron (hourly) | Working (retry; filing itself happens on issue) | none |
| mco-register | service | Working, local only (`registered_local`) | none |
| mco-export | service | Stub, 501, never calls MyClinicOnline | MCO_BASE_URL, MCO_API_TOKEN |

No cron schedule is created by the migrations: the cron functions are scheduled in the Supabase dashboard (or pg_cron with pg_net) when P5 goes live, with the service role key as the bearer token.

## Seed

`supabase/seed/bee_inspect_demo.sql` (not a migration, never for live; staging only on the Director's word; run with `psql --single-transaction`; idempotent). Everything is fictitious and marked so: tenant Rietvlei Civils and Building (strict voice note policy) and its File company, base line, a cleared inspector, an assistant, a company admin who is the File contact, a site with two departments, a building and a yard zone, three rooms, four tagged items of equipment, the seven library templates mapped to Section F registers, a demonstration kernel whose chunks say they are not legal text, the company's Construction File, one scaffold inspection with six findings (two Fail, each with photo, corrective action and voice note), three risks, two corrective actions, transcripts with a correction, a report drafted, signed after a step up and Issued, filed into HSF-F-01 and packaged for MCO, MCO nodes, and a wallet with its included value, a R249,00 top up and one demonstration charge.

## Tests

| Suite | Result |
| --- | --- |
| `bash test/sql/replay.sh` | 001 to 063 replay cleanly |
| test/sql/bi_rls_checks.sql | all checks passed (RLS per role, reads and writes, audited FICA and qualification reads, role grants) |
| test/sql/bi_engine_checks.sql | all checks passed (seed, Fail rule strict and recommended, Start Inspection needs Active, Issued guard in every way it can refuse, Section F linked, section only, no File then filed on retry, idempotent, withdrawal, append only, seals, legal hold, templates, MCO reservations, risk bands, recurrence, reminders, NCR escalation, qualification expiry) |
| test/sql/bi_wallet_checks.sql | all checks passed (worked numbers, charge rule, refusals, FIFO, idempotency, shortfall, automatic top up, receipts, expiry, welcome hook, storage gate) |
| test/sql/bi_claim_checks.sql | all checks passed (hash only, 10 minutes, single use, rate limits, attribution) |
| test/sql/bi_popia_checks.sql | all checks passed (no clinical columns and the probe is caught, every object documented, private buckets, flags off, File tables untouched) |
| the eleven existing check files | all pass after 059 to 063 |
| test/api/bi-shared.test.mjs, test/api/bi-edge-functions.test.mjs | 54 tests, all pass (fetch mocked, no network) |
| `node --test` (whole repository) | see BUILD-STATE.md |

Deno itself is not installed in the build environment, so the TypeScript entry points were not type checked with `deno check`; they only import and call the tested handlers.

## Open questions

Inputs of the prompt's section 12 still missing (each has a labelled stub):

- `{{email_platform}}`: every alert (storage, qualification expiry, reminders, NCR escalation) is returned by its function but not sent.
- `{{store_publisher}}`, the Apple and Google developer accounts, `{{apple_team_id}}`, `{{android_sha256}}`: needed for the stores, RevenueCat products and app links (the Director is registering them, contract 16.4).
- RevenueCat product identifiers: `BI_RC_PRODUCT_MAP` maps them to the rate card codes once they exist.
- `{{saved_card_gateway}}`: automatic top up queues but charges nothing.
- `{{kyc_vendor}}`: identity and liveness.
- `{{kernel_source}}`: the kernel store is empty on live; the seed's chunks are demonstration only. The embedding model and dimension (1536 is assumed, as msp_precedent) and the similarity index come with it.
- `{{bee_matched_url}}`: reviewer engagement is recorded (`bi_report_assign_reviewer`); the portal link stays the WhatsApp fallback until the page is live.
- `{{rate_card}}`: the xAI rates, the transcription rate, the fx source and storage pack prices; every AI estimate answers `rate_card_pending` until ops enters confirmed rows.
- `{{vat_inclusive}}`: all amounts are stored excluding VAT with `bi.vat_mode` = `to_be_confirmed`.
- `{{export_page_decision}}`: unchanged (AD-09 parked).
- `{{mco_endpoint}}`: MCO nodes and report packages stay in Supabase; `linked` and `mco_ingested` are refused by the database.
- `{{hsf_file_table}}`: answered by the build: `hsf_file`, `hsf_file_item` and `hsf_evidence` (migration 047), through `bi_report_file_link`.
- welcome_hook: built, off.
- Also needed: the transcription vendor; Ozow's notification specification for Care Net's account (the hash check is not guessed); the Telnyx SMS set up for step up by SMS; the wording of the Bee-Inspect consents (the table expects versions such as BI-TERMS-1.0; the seed uses 0.1 placeholders).

Decisions made in the build, for the Director's confirmation:

1. An Issued Bee-Inspect report counts as evidence on its Section F element and raises the File's compliance figure (engine_generated evidence with the PDF fingerprint); a withdrawn report takes it away again. Recorded as contract 16.7.
2. Risk bands on the 5 x 5 matrix: 1 to 4 low, 5 to 9 medium, 10 to 15 high, 16 to 25 extreme, to be confirmed against Care Net's methodology.
3. Step up MFA is valid 10 minutes for an in app signature (parameter) and 24 hours for DocuSeal (the signer verifies in the app before DocuSeal opens); a rooted or jailbroken device cannot sign; the signer confirms the photos and voice notes.
4. An estimate must fit the balance. If an action's actual cost is more than the balance left when it is charged (two actions at once), the balance goes to R0,00 and the rest is recorded as a shortfall that Care Net carries, never charged later.
5. Storage is metered per company line (tenant and company): 10 GB each. Evidence captured offline before the line filled still syncs; evidence captured after is refused.
6. One tenant per person; an inspector or assistant role without a company covers every company the tenant holds a line on; the sites tree of a company is shared by every tenant with a line on it, while inspections, reports and wallets are the tenant's own.
7. The company admin may read the tenant's draft reports of their company as well as Issued ones; assistants see Issued reports only and no money, FICA or qualifications.
8. Voice notes are numbered VN-1, VN-2 by the database per inspection (offline devices do not decide the number).
9. Signing and issuing are separate: a signature is recorded on the version signed; the report becomes Issued only when the renderer has stored the PDF and JSON (P5), and the guard checks the signer again at that moment.

Not done in P3 (by design or waiting): the PDF renderer, kernel loading and retrieval by embedding (P5); signed upload and download URLs for photos, voice notes and reports (the buckets have no client policy; P4 adds a function); an Edge Function around `bi_step_up_record` (the SQL and the JWT helper `stepUpFromClaims` exist; P4 wires it with the app's MFA screens); wiring the File site's banner hooks and Section F list to `bi_banner_state` and `bi_section_f_reports` through the Vercel API (P5 or P6); onboarding, FICA upload and role management endpoints (P4 and P6 web desk); cron schedules; `deno check`.
