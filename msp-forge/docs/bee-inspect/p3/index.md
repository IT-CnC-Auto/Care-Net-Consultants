# Bee-Inspect P3: backend

Bee-Inspect P3 (hsf/BEE-INSPECT-BUILD-PROMPT.md sections 6 and 7, phase P3, applied under hsf/BUILD-CONTRACT.md 16), 26/09/2026. Data model, Row Level Security, Edge Functions with labelled stubs for every unknown vendor, and a fictitious demonstration seed. Not committed, not deployed, nothing applied to the live Supabase project or to Vercel. Migrations 001 to 058 are byte identical.

**P3 accepted; decisions locked (27/09/2026).** The Director's decisions (hsf/BEE-INSPECT-P3-DECISIONS.md, contract 16.8) are applied in one new migration, `064_bi_p3_decisions.sql`; 059 to 063 are kept exactly as the P3 record, so 001 to 063 are byte identical. See [Decisions (locked 27/09/2026)](#decisions-locked-27092026).

## STOP items

1. [Migration list](#migrations)
2. [RLS results per role](#row-level-security-results)
3. [Edge Functions, stub status and settings](#edge-functions)
4. [Open questions](#open-questions)
5. [Decisions (locked 27/09/2026)](#decisions-locked-27092026)

## How Bee-Inspect joins the free File

- The Bee-Inspect company is the File's company, `msp_client_account`. `bi_company` holds only the Bee-Inspect onboarding record of that same row (primary key `client_account_id`); nothing about the company is copied.
- The tenant (`bi_tenant`) is whoever pays: a consultancy whose competent persons inspect client companies, or an employer inspecting itself. A tenant holds a paid line per company (`bi_company_subscription`): base R299,00 a month or extra company R199,00 a month, excluding VAT.
- An Issued report files itself into the company's File, in the same transaction that issues it (`bi_hsf_section_f_sync`): the template names its Section F register (for example scaffolds to HSF-F-01, ladders HSF-F-02, lifting HSF-F-03, portable electrical HSF-F-04, fire HSF-F-06, PPE HSF-F-11, hazardous chemicals HSF-F-12); that File item receives a new `hsf_evidence` version (source `engine_generated`, the PDF fingerprint, "Bee-Inspect report signed by <name>"), turns from outstanding to uploaded, and the File's compliance figure is recomputed and audited in `msp_audit`, exactly as a client upload does. The link is kept in the new `bi_report_file_link`, so no File table is altered. When the element is not on the File the report is still listed in Section F (`section_only`); when the company has no File yet the link waits (`no_file`) and the hsf-section-f-sync function files it later. A withdrawn report has its evidence revoked. `bi_section_f_reports` gives the builder's Section F "Inspection reports" list (title, site, date, signed by, status).
- Since 064 (contract 16.8) the filing above happens only when the company is eligible for the free digital Safety File for the report's site (`bi_free_file_eligible`): rule A, a verified Care Net client (the File's own `hsf_client_verified`, migration 052) with more than 50 verified medicals in the rolling 12 months; rule B, a site with more than 500; or a subcontractor registered on a site whose principal is eligible there. Otherwise the Issued report is stored and its link waits as `awaiting_eligibility`: listed in Section F, no evidence, no change to the item or the compliance figure (the File audit notes it once). The hourly retry files it once a verified count makes the company eligible. The link keeps the eligibility answer it was filed on.

## Migrations

059 to 063 are the P3 record; 064 applies the locked decisions and alters only 059 to 063 objects (never an applied table). All six are new files; none alters an applied table. Every object is `bi_` prefixed. 059 begins with a guard that refuses to run if any `bi_` table or function already exists, so a name clash on live stops the migration instead of mixing objects. Checked against 001 to 058: no `bi_` table, view, function, parameter (`bi.*`), bucket (`bi-evidence`, `bi-reports`) or trigger name exists there. Replay: `bash test/sql/replay.sh` (the local database has no pgvector; replay.sh rewrites `extensions.vector(1536)` to `real[]`, as for msp_precedent).

| File | Objects | Purpose |
| --- | --- | --- |
| 059_bi_core_tenancy.sql | `bi_tenant`, `bi_company`, `bi_company_subscription`, `bi_app_user`, `bi_role_assignment`, `bi_inspector_profile`, `bi_inspector_qualification`, `bi_fica_record`, `bi_consent_record`, `bi_audit_log`, `bi_feature_flag`, `bi_rate_event`, `bi_step_up`; helpers `bi_is_ops`, `bi_user_is_ops`, `bi_user_roles`, `bi_my_roles`, `bi_can`, `bi_can_company`, `bi_my_app_user_id`, `bi_subscription_live`, `bi_flag_enabled`, `bi_rate_allow`, `bi_audit`; functions `bi_step_up_record`, `bi_fica_list`, `bi_qualification_list`, `bi_company_set_status`, `bi_inspector_set_status`, `bi_role_grant`, `bi_role_revoke`; parameters `bi.vat_mode` (to_be_confirmed), `bi.markup_default` (3.0), `bi.step_up_window_minutes` (10) | Tenancy and roles (inspector, assistant, company_admin, ops); company onboarding status Not started, In review, Active, Blocked; inspector path Identity, FICA, Qualifications, Competence review, Cleared, Restricted, Assistant only; FICA and qualification reads only through functions that audit every row read; append only audit trail; flags `bee_inspect_ads` and `welcome_hook`, both off; rate limiter; step up MFA record |
| 060_bi_sites_inspection_engine.sql | `bi_site`, `bi_department` (File department codes), `bi_building`, `bi_room`, `bi_template`, `bi_template_item`, `bi_inspection`, `bi_inspection_area`, `bi_equipment`, `bi_finding`, `bi_photo`, `bi_voice_note`, `bi_voice_transcript`, `bi_risk`, `bi_corrective_action`, view `bi_risk_register`; `bi_fail_rule_violations`, `bi_inspection_submit`, `bi_inspection_set_status`, `bi_risk_band`, `bi_risk_score`, `bi_risk_top_control`, `bi_evidence_seal`, `bi_schedule_reminders_run`, `bi_ncr_escalation_run` | Sites tree (company, site, department, building or zone, room or area); templates mapped to Section F registers; findings Pass, Fail, N/A, Observe; the Fail rule at submit (photo and corrective action, plus a voice note under the strict policy); sealed photo and voice note evidence (GPS, time, inspector, fingerprint; paths only); VN numbering and versioned transcript corrections; 5 x 5 inherent and residual risk with the hierarchy of controls; corrective actions with closure evidence and escalation; legal hold; conflict safe offline sync (row_version) |
| 061_bi_reports_signatures_kernels.sql | `bi_kernel_version`, `bi_kernel_doc`, `bi_kernel_chunk` (embedding `extensions.vector(1536)`), `bi_report`, `bi_report_version`, `bi_signature`, `bi_report_file_link`, `bi_transfer_package`; guard `bi_report_guard`; `bi_report_save_draft`, `bi_report_request_signoff`, `bi_report_assign_reviewer`, `bi_report_sign`, `bi_report_issue`, `bi_report_withdraw`, `bi_report_share_create`, `bi_hsf_section_f_sync`, `bi_hsf_section_f_sync_pending`, `bi_section_f_reports`, `bi_transfer_package_store` | Report kernel store; versioned report JSON (AI drafts must carry "Assistive draft. Competent person sign off required."; every claim a kernel reference); the Issued guard; Section F filing; secure share link (token shown once, 1 to 30 days); MCO package `supabase_stored` (`mco_ingested` reserved and refused) |
| 062_bi_wallet_billing_usage.sql | `bi_rate_card`, `bi_wallet`, `bi_wallet_ledger`, `bi_usage_event`, `bi_iap_receipt`, `bi_storage_meter`; `bi_price_cents`, `bi_charge_rule_cents`, `bi_storage_level`, `bi_wallet_estimate`, `bi_wallet_charge`, `bi_wallet_credit`, `bi_wallet_grant_included`, `bi_wallet_topup_apply`, `bi_wallet_expire_lots`, `bi_wallet_balance`, `bi_wallet_set_cap`, `bi_wallet_set_autotopup`, `bi_autotopup_queue`, `bi_iap_apply`, `bi_welcome_hook_grant`, `bi_storage_status`, `bi_storage_gate` (trigger), `bi_storage_meter_run` | AI Wallet in rand (cents, excluding VAT); price and charge rules; included value rolls one month, purchased lasts 12 months, oldest expiry spent first; top ups and automatic top up; store receipts once per event; photo tagging free to 50 per report; 10 GB per line with 80% and 95% warnings and new photos and voice notes refused at 100% |
| 064_bi_p3_decisions.sql | `bi_medicals_volume`, `bi_site_subcontractor`, `bi_authorised_person`, `bi_person_credential`, `bi_consent_purpose`, `bi_subsidy_ledger`, `bi_rate_card_channel`, `bi_super_user`; new columns `bi_report_file_link.eligibility_reason` and `eligibility` (status `awaiting_eligibility` added), `bi_inspector_qualification.credential_kind`, `bi_rate_card.landed_cost_components`, `landed_cost_status`, `landed_cost_cents`; four columns on `bi_risk_register`; `bi_free_file_eligible`, `bi_free_file_direct`, `bi_medicals_volume_current`, `bi_medicals_volume_record`, `bi_site_subcontractor_register`, `bi_site_subcontractor_end`, `bi_risk_band_label`, `bi_risk_band_colour`, `bi_risk_assess`, `bi_step_up_window_minutes`, `bi_signer_gate`, `bi_authorised_person_save`, `bi_person_credential_save`, `bi_credential_verify`, `bi_person_credential_list`, `bi_person_credential_expiry_run`, `bi_consent_status`, `bi_consent_decide`, `bi_consent_withdraw`, `bi_margin_floor_cents`, `bi_margin_ok`, `bi_landed_cost_sum`, `bi_channel_landed_cents`, `bi_margin_check`, `bi_topup_channels`, `bi_is_super_user`, `bi_super_user_grant`, `bi_super_user_revoke`, `bi_export`, guards on the rate card, its channels and subscription prices; replaced: `bi_hsf_section_f_sync`, `bi_hsf_section_f_sync_pending`, `bi_section_f_reports`, `bi_report_guard`, `bi_report_sign`, `bi_wallet_estimate`, `bi_wallet_charge`, `bi_qualification_list`, `bi_qualification_expiry_run`; parameters `bi.free_file.client_medicals_threshold` (50), `bi.free_file.site_medicals_threshold` (500), `bi.free_file.count_max_age_days` (92), `bi.step_up_docuseal_window_minutes` (1 440), `bi.margin.minimum_pct` (20); private bucket `bi-credentials` | The locked decisions: free digital Safety File eligibility and the awaiting eligibility filing; risk band labels and colours; the subsidy ledger and the balance warning; the 20% minimum margin; step up windows as parameters; export for super users only, audited; authorised persons, credentials, consent purposes defaulting to Not given, and the dual gate before Issue |
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
| Balance warning (064) | the W2 draft estimate R21,09 against R398,20 | remaining balance R398,20, after the run R377,11, no warning; an estimate above the balance is refused with estimate_exceeds_balance |
| Subsidy (064) | the second R59,94 charge against R40,06 left | wallet R0,00; subsidy row balance_exhausted: estimate R59,94, actual R59,94, wallet paid R40,06, Care Net carries R19,88, with the job, user and company |
| Estimate cap subsidy (064) | estimate R11,10, actual R22,20 | R11,10 billed; subsidy row estimate_cap R11,10 |
| Top up after a subsidy (064) | R99,00 and an Ozow R249,00 into the subsidised wallet | both applied: R458,00 available |
| Margin floor (064) | landed R80,00 | sell excluding VAT at least R100,00: R99,99 refused, R100,00 accepted; landed R80,01 needs R100,02 |
| Top up channels (064) | topup_99 at R99,00 whose value costs R60,00 | Apple at 30% (R89,70 landed, floor R112,13) refused, naming Ozow web; Ozow web at 2,5% plus R2,00 (R64,48 landed) and a 15% store cut (R74,85) accepted |

## Row Level Security results

RLS is on for all 55 `bi_` tables (47 in 059 to 063, 8 in 064); anon has no privilege on any `bi_` table, view or function; no client may insert, update or delete the wallet ledger, signatures, reports or report versions, the audit log, usage events, receipts, claim codes, step ups, qualifications or FICA records. Ops is Care Net staff through the existing `hsf_is_staff()` (forge_admin, forge_omp, forge_safety_reviewer) or an ops assignment only the service role can grant.

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
| bi_audit_log | 0 | 0 | 9 (company rows) | 10 (all) | 0 | 0 | denied |
| bi_app_user | 3 (tenant) | 1 (self) | 3 (tenant) | 5 | 1 (self) | 1 (self) | denied |
| bi_template (library) | 7 | 7 | 7 | 7 | 7 | 7 | denied |
| bi_inspector_qualification | denied | denied | denied | denied | denied | denied | denied |
| bi_fica_record | denied | denied | denied | denied | denied | denied | denied |
| bi_claim_code | denied | denied | denied | denied | denied | denied | denied |
| bi_medicals_volume (064) | 0 | 0 | 1 | 1 | 0 | 0 | denied |
| bi_site_subcontractor (064) | 0 | 0 | 0 | 0 | 0 | 0 | denied |
| bi_authorised_person (064) | 3 | 0 | 3 | 3 | 0 | 3 (shared company) | denied |
| bi_person_credential (064) | denied | denied | denied | denied | denied | denied | denied |
| bi_subsidy_ledger (064, one test row) | 1 | 0 | 1 | 1 | 0 | 0 | denied |
| bi_rate_card_channel (064) | 0 | 0 | 0 | 22 | 0 | 0 | denied |
| bi_super_user (064) | 0 | 0 | 0 | 0 | 0 | 0 | denied |
| bi_consent_purpose (064) | 7 | 7 | 7 | 7 | 7 | 7 | denied |

Since 064: nobody but the service role writes the new tables; clients read the prices of the rate card but never its landed cost columns (column grants), and authorised persons' credentials only through `bi_person_credential_list` (each row read audited as credential_read). The export rule and the authorised persons flows are proved in the same file (sections 7 and 8).

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
| wallet-estimate | signed in | Working; since 064 also the remaining balance, the balance after the run and the warning when the estimate exceeds the balance, in rand | none |
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
| hsf-section-f-sync | service or cron (hourly) | Working (retry; filing itself happens on issue; since 064 it also files reports awaiting eligibility once the company is eligible, and counts those still waiting) | none |
| mco-register | service | Working, local only (`registered_local`) | none |
| mco-export | service | Stub, 501, never calls MyClinicOnline | MCO_BASE_URL, MCO_API_TOKEN |

No cron schedule is created by the migrations: the cron functions are scheduled in the Supabase dashboard (or pg_cron with pg_net) when P5 goes live, with the service role key as the bearer token.

## Seed

`supabase/seed/bee_inspect_demo.sql` (not a migration, never for live; staging only on the Director's word; run with `psql --single-transaction`; idempotent). Everything is fictitious and marked so: tenant Rietvlei Civils and Building (strict voice note policy) and its File company, base line, a cleared inspector, an assistant, a company admin who is the File contact, a site with two departments, a building and a yard zone, three rooms, four tagged items of equipment, the seven library templates mapped to Section F registers, a demonstration kernel whose chunks say they are not legal text, the company's Construction File, one scaffold inspection with six findings (two Fail, each with photo, corrective action and voice note), three risks, two corrective actions, transcripts with a correction, a report drafted, signed after a step up and Issued, filed into HSF-F-01 and packaged for MCO, MCO nodes, and a wallet with its included value, a R249,00 top up and one demonstration charge. Since 064 the company is also a verified Care Net client with a verified count of 64 medicals in the rolling 12 months (recorded before the report is Issued, so it files into HSF-F-01), and has three authorised persons (16(1), 16(2) and a construction H&S officer with a professional registration on file).

## Tests

| Suite | Result |
| --- | --- |
| `bash test/sql/replay.sh` | 001 to 064 replay cleanly |
| test/sql/bi_rls_checks.sql | all checks passed (RLS per role, reads and writes, audited FICA and qualification reads, role grants) |
| test/sql/bi_engine_checks.sql | all checks passed (seed, Fail rule strict and recommended, Start Inspection needs Active, Issued guard in every way it can refuse, Section F linked, section only, no File then filed on retry, idempotent, withdrawal, append only, seals, legal hold, templates, MCO reservations, risk bands, recurrence, reminders, NCR escalation, qualification expiry) |
| test/sql/bi_wallet_checks.sql | all checks passed (worked numbers, charge rule, refusals, FIFO, idempotency, shortfall, automatic top up, receipts, expiry, welcome hook, storage gate) |
| test/sql/bi_claim_checks.sql | all checks passed (hash only, 10 minutes, single use, rate limits, attribution) |
| test/sql/bi_popia_checks.sql | all checks passed (no clinical columns and the probe is caught, every object documented, private buckets, flags off, File tables untouched; 064: 55 tables and 8 parameters, the medicals count holds no clinical column, consent purposes default Not given, double opt in for marketing, decisions and withdrawals audited) |
| 064 in the files above | eligibility rule A (50 is not enough, 51 is), rule B (500 is not enough, 612 is, that site only), subcontractor (registered by Care Net only, that site only, ended), not eligible then awaiting then filed with the compliance figure unchanged while waiting, counts older than 92 days; bands at 4, 5, 9, 10, 15, 16 with labels and colours; dual gate at signing and again at issue; DocuSeal 24 hours and in app 10 minutes, both parameters; subsidy rows and top ups after a subsidy; margin worked numbers, channels and guards; export refused to non super users and audited, then allowed with a fresh step up and audited with the row count |
| the eleven existing check files | all pass after 059 to 063 |
| test/api/bi-shared.test.mjs, test/api/bi-edge-functions.test.mjs | 62 tests, all pass (fetch mocked, no network); 064 adds band labels and colour tokens with contrast, margin worked numbers and channel advice, step up windows, parameter parity with the SQL, the balance warning in rand |
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
- `{{bee_matched_url}}`: answered (decision 1.8): https://www.carenetconsultants.co.za/bee_matched_Recruitment, held in vercel/js/cnc-config.js as recruitmentPortalFutureUrl; recruitmentPortalUrl stays null (WhatsApp fallback) until the Director says the page is live.
- `{{rate_card}}`: the xAI rates, the transcription rate, the fx source and storage pack prices, and now the landed cost components of every product line and the fees of each channel (064); every AI estimate answers `rate_card_pending` and every landed cost stays `to_be_confirmed` until ops enters confirmed rows.
- `{{vat_inclusive}}`: all amounts are stored excluding VAT with `bi.vat_mode` = `to_be_confirmed`.
- `{{export_page_decision}}`: answered (decision 1.7): super users only, every export audited (`bi_export`, 064). The export page itself (AD-09) is still to be built on top of it.
- `{{mco_endpoint}}`: MCO nodes and report packages stay in Supabase; `linked` and `mco_ingested` are refused by the database.
- `{{hsf_file_table}}`: answered by the build: `hsf_file`, `hsf_file_item` and `hsf_evidence` (migration 047), through `bi_report_file_link`.
- welcome_hook: built, off.
- Also needed: the transcription vendor; Ozow's notification specification for Care Net's account (the hash check is not guessed); the Telnyx SMS set up for step up by SMS; the wording of the Bee-Inspect consents (the table expects versions such as BI-TERMS-1.0; the seed uses 0.1 placeholders).

Decisions made in the build (P3), as recorded on 26/09/2026. The Director's answers of 27/09/2026 are in the next section; 1, 2, 3 and 4 are superseded or confirmed there, 5 to 9 stand.

1. An Issued Bee-Inspect report counts as evidence on its Section F element and raises the File's compliance figure; a withdrawn report takes it away again. Recorded as contract 16.7. **Narrowed by decision 1.1:** only for an eligible company.
2. Risk bands on the 5 x 5 matrix: 1 to 4 low, 5 to 9 medium, 10 to 15 high, 16 to 25 extreme. **Confirmed by decision 1.2.**
3. Step up MFA is valid 10 minutes for an in app signature (parameter) and 24 hours for DocuSeal; a rooted or jailbroken device cannot sign; the signer confirms the photos and voice notes. **Confirmed by decision 1.5** (both windows are now parameters).
4. An estimate must fit the balance; a shortfall at charge time is carried by Care Net. **Confirmed and extended by decision 1.3** (subsidy ledger).
5. Storage is metered per company line (tenant and company): 10 GB each. Evidence captured offline before the line filled still syncs; evidence captured after is refused.
6. One tenant per person; an inspector or assistant role without a company covers every company the tenant holds a line on; the sites tree of a company is shared by every tenant with a line on it, while inspections, reports and wallets are the tenant's own.
7. The company admin may read the tenant's draft reports of their company as well as Issued ones; assistants see Issued reports only and no money, FICA or qualifications.
8. Voice notes are numbered VN-1, VN-2 by the database per inspection (offline devices do not decide the number).
9. Signing and issuing are separate: a signature is recorded on the version signed; the report becomes Issued only when the renderer has stored the PDF and JSON (P5), and the guard checks the signer again at that moment.

Not done in P3 (by design or waiting): the PDF renderer, kernel loading and retrieval by embedding (P5); signed upload and download URLs for photos, voice notes and reports (the buckets have no client policy; P4 adds a function); an Edge Function around `bi_step_up_record` (the SQL and the JWT helper `stepUpFromClaims` exist; P4 wires it with the app's MFA screens); wiring the File site's banner hooks and Section F list to `bi_banner_state` and `bi_section_f_reports` through the Vercel API (P5 or P6); onboarding, FICA upload and role management endpoints (P4 and P6 web desk); cron schedules; `deno check`.

## Decisions (locked 27/09/2026)

Source: hsf/BEE-INSPECT-P3-DECISIONS.md (freeze label Bee-Inspect-P3-Decisions-P0-20260927), applied under contract 16.8 in `supabase/migrations/064_bi_p3_decisions.sql`. Nothing is applied to the live project (1.6: there is no Bee-Inspect staging project yet; 059 to 064 stay unapplied until one exists or P4 needs them live behind a flag with a backup, each on the Director's confirmation).

| Decision | How it is applied |
| --- | --- |
| 1.1 Free digital Safety File and Section F | `bi_free_file_eligible(company, site)` answers eligible, reason (`care_net_client_over_50`, `big_site_over_500`, `subcontractor_of_eligible_site` or `not_eligible`), the counts and the thresholds, as at a date. The Care Net client flag is the File's own `hsf_client_verified` (052). Counts come only from `bi_medicals_volume` (occupational health, MCO or a sales executive's verified count, each with its evidence reference, verified by, verified at and its audit row; never the client's own declaration). The thresholds are parameters (50 and 500), not literals. Subcontractors are registered on a site by Care Net (`bi_site_subcontractor`). `bi_hsf_section_f_sync` files as before only when eligible; otherwise `awaiting_eligibility`, and the retry run files it once eligible. Contract 15.2 (sign off price: free above 100 a year; site and subcontractors above 500) is unchanged. |
| 1.2 Risk bands | 1 to 4 Low (green), 5 to 9 Medium (amber), 10 to 15 High (orange), 16 to 25 Extreme (red), the same in 060, `risk.js` and now the site: the P2 sample report (vercel/bee-inspect/sample-report.html) said "10 to 14 high, 15 to 25 very high" and is corrected (15 is High; Very high is Extreme). The label always travels with the score: `bi_risk_assess`, the new `bi_risk_register` label and colour columns, `assessRisk` and `describeRisk` in `risk.js`. Colour tokens for the app and the site: `BAND_TOKENS` in supabase/functions/_shared/bi/risk.js (fills of the sample report, text at least 7:1, accents at least 4.5:1 on white). |
| 1.3 AI Wallet overspend | `bi_wallet_charge` leaves the wallet at R0,00 and writes `bi_subsidy_ledger` (append only): reason, estimate, actual, billable, charged, shortfall, job (the usage event with its report and inspection), user, company, time. Top ups never look at subsidies (proved: a R99,00 and an Ozow R249,00 top up land in a subsidised wallet). The estimate cap is kept. `bi_wallet_estimate` always returns `remaining_balance_cents`, `balance_after_cents` and the warning `estimate_exceeds_balance`; the wallet-estimate function shows them in rand. |
| 1.4 Minimum margin 20% | Landed cost components on every rate card row (model tokens, voice minutes, storage, SMS, gateway fee, app store cut, KYC, transcription) and per channel fees in `bi_rate_card_channel` (Ozow web, Apple App Store, Google Play, saved card, manual invoice). `bi_margin_check()` flags any price with sell excluding VAT below landed cost / 0,80 (the percentage is `bi.margin.minimum_pct`, never below 20); guards refuse activating a rate card row, a channel or a subscription price below the floor; the Ozow web row of every top up carries the preference note, and `bi_margin_check` and `bi_topup_channels` advise Ozow web where an app store cut breaks the floor. `bi.markup_default` can no longer go below 1,25. Every landed cost is `to_be_confirmed` until `{{rate_card}}`, so nothing fails spuriously. |
| 1.5 Step up | 10 minutes in the app (`bi.step_up_window_minutes`), 24 hours for DocuSeal (`bi.step_up_docuseal_window_minutes`, 1 440): both the Issued guard and `bi_report_sign` read the parameters (the literal 1 440 of 061 is gone). `STEP_UP_WINDOW_MINUTES` and `stepUpFresh` in http.js for the app. |
| 1.6 Migrations | Unapplied, as above. |
| 1.7 Export | `bi_export` is the only export path and only a super user may use it: Care Net staff (`hsf_user_is_staff`) with a live `bi_super_user` assignment that only the service role grants, plus a fresh bulk export step up (consumed). Every export writes `bi_audit_log` (who, what, row count, when, filters) and so does every refusal (`export_denied`). FICA, qualifications and credentials are never exported. |
| 1.8 Bee-Matched | https://www.carenetconsultants.co.za/bee_matched_Recruitment in vercel/js/cnc-config.js (`recruitmentPortalFutureUrl`, comment updated); `recruitmentPortalUrl` stays null. The guard test now allows exactly this address and still refuses any other. vercel/hsf/ads.js and hsf/appointments held no address. |
| 1.9, 1.10 Vendors and MCO | Unchanged: wired when keys and the MCO spec exist. |
| Section 2 Accounts and settings | Several authorised persons per company, one row per appointment with its role (16(1), one live per company; 16(2); H&S manager, officer, representative, committee member; construction manager, supervisor and H&S officer; first aider; fire marshal; incident investigator; risk assessor; competent person; other) and appointment letter path (`bi_authorised_person`); their qualifications, professional registrations, licences and certificates with the certificate path in the private bucket `bi-credentials` and expiry, alerts at 60, 30 and 7 days (`bi_person_credential`); `credential_kind` on inspector qualifications (professional_registration and so on); consent purposes (`bi_consent_purpose`) that start Not given, with `bi_consent_status`, `bi_consent_decide` (marketing only with the double opt in) and `bi_consent_withdraw`; the dual gate before Issue (`bi_signer_gate`): FICA and KYC cleared (company onboarding Active, the signer's liveness check and an accepted FICA record) and a qualification cleared (cleared for the scope, nothing expired, at least one verified qualification or registration in date), checked at signing and again by the Issued guard. |

Build decisions in 064, for the Director's confirmation:

1. A verified count stays current for 92 days after the date it was counted to (`bi.free_file.count_max_age_days`), so the rolling 12 months are refreshed at least quarterly (MCO monthly, or a sales executive).
2. A subcontractor shares its principal's eligibility for that site when the principal is eligible there by rule A or rule B (contract 16.8: "the site's registered subcontractors share the site's eligibility for that site"). Registration is by Care Net only, with an evidence reference.
3. The subsidy ledger also records the estimate cap difference (reason `estimate_cap`: actual more than 25% above the estimate, the estimate billed), so the ledger shows everything Care Net carries on AI actions.
4. An estimate above the balance is still refused (`wallet_empty`) with the warning `estimate_exceeds_balance`; Care Net carries only what a run costs beyond the balance at charge time.
5. The dual gate's FICA part includes the company's onboarding being Active (Care Net reviewed its FICA pack), besides the signer's own FICA and KYC.
6. An export needs a fresh bulk export step up (10 minutes), as prompt B3 foresaw, and a refusal is audited rather than raised.
7. Landed costs are Care Net's own figures: clients keep reading the rate card prices but not its cost columns.

Also noticed, not changed: the File's example baseline risk assessment (hsf/examples/C-baseline-risk-assessment-extract.json, generated by hsf/build_examples.mjs) uses its own three band scheme (1 to 6 low, 8 to 12 medium, 15 to 25 high). It is a File example, not Bee-Inspect, and regenerating the examples is a separate task if the Director wants the locked bands there too.
