# CNC MSP FORGE | Build State | 15/08/2026

This document records the state of the engine at the completion of the phased build. It is the companion to SPEC.md (the system specification) and the migrations directory (the applied history).

## Phase status

| Phase | Scope | Status |
| --- | --- | --- |
| 0 | System specification (SPEC.md) | Complete |
| 1 | Legal kernel: schema, RLS, triple verification workflow, Construction seed | Complete |
| 2 | Intake: engagement schema, ingest path, HTML assessment form | Complete |
| 3 | Agent: deterministic pipeline, classify to validate, draft of record | Complete |
| 4 | Document factory: dual brand DOCX rendering with geometry verification | Complete |
| 5 | POPIA and OMP hardening: release gate, review workflow, data subject rights, recommendations, signature, gated landing, quote engine, revisions | Complete |
| 6 | Taxonomy scale out: sixteen batches | Complete |

## Kernel state

- 31 triple verified legal instruments; 4 instruments remain pending and are uncitable by design (they never appear in a deliverable), and one duplicate record (FCD Act R638, 2018) is retired through a hygiene sweep in favour of the fuller batch 7 record.
- Register closures on 14/08/2026: the Noise Exposure Regulations, 2024 values are confirmed (85 dB(A) rating limit retained; 82 dB(A) continuous and 135 dB(C) impulse action level for ototoxic or vibration co exposure), the PrDP medical provision is pinned to NRTR 2000 regulations 115 to 117, COIDA Circular Instructions 171 to 180 are recorded, and record retention is resolved per class (HCA air monitoring 30 years, HBA 40 years, 40 year house floor for medical surveillance records).
- Instrument sweep: the Driven Machinery, General Safety, General Administrative, and Environmental Regulations are backfilled onto the industry maps that predate their verification, and a gate now proves every industry citing lifting machine work carries the DMR mapping.
- Post scale out regression 14/08/2026: refreshed Construction kernel snapshot, pipeline validation 9 of 9, dual brand render, geometry verification 16 of 16 (agent/kernel_snapshot_constr.json is the committed snapshot; agent/draft.json is the revision 2 draft of record).
- 17 industries, 56 subindustries, all 56 selectable after passing the batch gate (at least five roles, no unmapped roles, no unprotocolled hazards outside the narrative codes O and N).
- 316 job roles, 851 role to hazard mappings, 31 test protocols, every protocol carrying dual justification (hazard basis plus EEA section 7) and exit medical requirement.
- Register: 24 confirmation items resolved or closed with documentary basis; open items are all external dependencies listed below.
- The verification watchdog (msp_verification_due) tracks review dates; the nearest material events are the noise instrument transition on 06/09/2026 (automated by kernel rule RULE-NOISE-TRANSITION with confirmed values: 85 dB(A) rating limit retained, 82 dB(A) continuous and 135 dB(C) impulse co exposure action level added) and the draft General Machinery Regulation, 2025 replacement process.

## Clinical governance

- Care Net screens and does not diagnose. Every generated pack is a draft until a registered Occupational Medical Practitioner approves it; the release gate is enforced in the database (msp_release_gate trigger) and cannot be bypassed by the application.
- The OMP review interface (review.html) supports recommendations, decisions with HPCSA number capture, and canvas signature.
- Designated OMP configured: Dr C. P. Green-Thompson, HPCSA MP 0195952, SASOM SAS1270.
- The employer is always the payer (HPCSA Booklet 11 perverse incentive rule, enforced as kernel rule RULE-HPCSA-PAYER).
- ODMWA versus COIDA routing is a kernel rule; mining dust disease surveillance routes through the Medical Bureau for Occupational Diseases pathway.
- The twelve month periodic floor holds everywhere; longer intervals require an instrument citation (database constraint msp_interval_floor_citation).

## Commercial path

- Landing page (index.html): CNC client sign on with consultant approval, or instant quotation across all 17 industries.
- Quotes are marked indicative while pricing rows are placeholders (see open items).
- Single use tokens gate the assessment form; the intake endpoint re checks server side.
- Revision numbers increment per engagement; MCO hosting awaits the integration below.

## Open items that need Care Net (not buildable from here)

| Item | What is needed |
| --- | --- |
| CR-13.14 | Retired 11/09/2026: the Plan is free to build, so there is no rate card. Replaced by the review bands in the parameter store (migration 045) |
| CR-13.13 | Payment gateway selection and credentials |
| CR-13.12 | MyClinicOnline API or filing mechanism for hosted packs, revisions, and the in app review link |
| CR-12.7 follow up | Supabase Auth user with the forge_omp role so the OMP can approve the pilot pack |
| Vercel env | SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, DOCUSEAL_WEBHOOK_SECRET, ADMIN_ACTION_SECRET per vercel/README.md |
| CR-13.11 | LibreOffice in the production factory path for PDF and raster verification |
| CR-12.3 | Licensed SANS editions (audiometry, noise measurement, spirometry) |
| CR-12.5 | DPA status for DocuSeal, Vercel, Supabase, Anthropic as POPIA operators |
| CR-12.6 | CNC Information Officer name and privacy contact |
| CR-13.3 / CR-13.4 | CNC contact line details and the standalone CNC logo mark source asset |
| CR-13.5 / CR-13.6 | Classification banner values and the Ubuntu closing line decision |
| CR-13.18 | Destination address for monthly framework audit findings (parameter agent.findings_alert_email) |
| CR-13.19 | Confirmation of the monthly assistant spend ceiling (parameter ai.monthly_cost_ceiling_usd, working figure 200 US dollars) |
| Supabase secret | ANTHROPIC_API_KEY in the project's function secrets, so the assistant connection can answer |

## Standing disciplines

British English throughout; no dash punctuation in prose (statute names keep their official hyphens; enforced by the pipeline PROSE_RULE_HOLDS check); ZAR amounts in comma format; Arial; CNC palette #ED1B24 and #1A1A1A; OREP and WASP terminology; locked liability, POPIA, and sign off blocks rendered verbatim from templates.json and never paraphrased; deliverables never carry CONFIRM or ASSUMPTION tags (unresolved items route to the OMP queue); the WARDEN ring fence holds (the CRM is referenced as AutoHive CRM by name only).

## CNC HSF FORGE (Health and Safety File engine) | 23/09/2026

Commissioned by HSF-FORGE-BUILD-PROMPT.md (CNC-HSF-FORGE-V1.0-2026). Specification is Part B of SPEC.md.

| Phase | Scope | Status |
| --- | --- | --- |
| 1 | Specification (SPEC.md Part B): manifest, data model, 137 universal elements, 41 appointment types, 119 overlay additions, verification batches, generation contract, MCO adapter interface, register HSF-1 to HSF-10 | Delivered, awaiting Director approval |
| 2 | Element library load and instrument verification | Blocked on the Phase 1 gate and HSF-7 |
| 3 to 7 | Rules, generation, MCO linking, review and release, site | Not started |

Found on 23/09/2026 by a read only query of the live project, and recorded in SPEC.md B1.4 and B12:

- HSF-7 (blocking, and affecting MSP FORGE today): the live kernel is on release 1.0.0. Migration 042 (release 1.1.0, the noise transition and the Physical Agents Regulations, 2024) is in this repository but not applied to the live project, so the NIHL Regulations, 2003 remain verified in live past their repeal on 06/09/2026 and the Environmental Regulations for Workplaces, 1987 remain verified although repealed. The "Kernel state" section above describes the repository, not the live project, on this point.
- HSF-8: pending duplicate rows for the General Administrative, General Machinery and General Safety Regulations in live.
- HSF-9: conflicting amendment notice numbers for the Asbestos Abatement Regulations, 2020 (GN R.2092 in migration 042; GN R.11435 in the live and published register).
- HSF-10: the published register PDF has cross reference offsets that do not match its bytes.

MCO integration for HSF FORGE is PENDING INTEGRATION (HSF-3, extends CR-13.12). No MCO endpoint is assumed.

### HSF FORGE website work ahead of the gates | 23/09/2026

On the Director's instruction, built while the legislation and kernel are loaded:

- vercel/health-and-safety-file.html: the Build your File page on the shared shell. The File is free to build for every client; sign off by a registered Health and Safety Manager is priced at the researched market average. Care Net clients: first 25% less (23/09/2026), replaced on 24/09/2026 by a flat R4 000,00 excluding VAT, free above 100 medicals a year, and free for the whole site and its subcontractors above 500 (contract 15.2). Amounts are published here by instruction (HSF-2 partly resolved).
- vercel/hsf/pricing.js with hsf/PRICING-RESEARCH.md: market research of 23/09/2026. Only two averages are supported by published prices: a construction File (8 prices, 7 providers, R5 802,50) and a general business File (3 prices, 2 providers, R8 630,00). No provider publishes a price for a single industry outside construction, or a separate sign off price; every industry row says which average applies. The research could read search summaries only, not the pages themselves, so the figures need a manual check before go live.
- vercel/hsf-sample.html with vercel/hsf/samples/*.js: seventeen fictitious sample Files (compliance matrix, training and medical matrix, gap report) generated by hsf/build_samples.py from SPEC.md Part B and kernel role titles.
- Links from index.html and shop.html. The site menu is unchanged: a sixth item does not fit the desktop header.

### CNC OHS Industry Kernel received | 23/09/2026

The Director's OHS Legal Compliance Kernel pack (sandbox until OMP and attorney review) is held verbatim in kernel/cnc-ohs-industry-kernel/ and reconciled against the live kernel in kernel/OHS-KERNEL-RECONCILIATION.md. Industries, role counts (316) and the thirty protocols agree. The pack independently confirms HSF-7: the live kernel still cites the repealed NIHL Regulations, 2003 and Environmental Regulations, 1987. New register items HSF-11 to HSF-16. The sample Files now take their Section E protocols and basis strengths from the pack, and "POPIA compliant" is gone from the site per the pack's rule.

### Portal, File builder, uploads, MCO transfer and kernel API | 23/09/2026

Built on the Director's instruction ahead of the gates; recorded as SPEC.md B14. It opens no gate.

- Migrations 047 to 051 (File engine, element library, consent and uploads, MCO transfer, kernel API with currency holds, File generation) are in the repository and replay cleanly. None is applied to the live project (HSF-21), and 048 refuses to run until 042 is applied (HSF-7).
- Server handlers for consent, uploads, Files, the kernel API and the portal summary; the MCO transfer worker in hold mode until HSF-3; the portal and File builder with drag and drop per department; every page on the shared tracking and call to action code; DESIGNER-ASSETS.md for the designer.
- Adversarial review of the build found 25 confirmed findings; all are fixed under contract Amendment 1 (hsf/BUILD-CONTRACT.md section 9). Seven build decisions from that round need the Director's confirmation (HSF-22, SPEC B14.6).
- Proof on the local replay: core checks 81 of 81, flow checks 237 passed, node tests 149 of 149, end to end flow 52 of 52, builder browser drive 25 of 25, fifteen pages clean at desktop and phone width.
- backup/cognitive_kernel_rebuild.sql and backup/MANIFEST.md regenerated with 047 to 051 and proved by a replay into an empty database. SOP-KERNEL-AGENT.md v1.2.0 adds the kernel API, the Grok bot and HSF FORGE (section 8).
- Waiting on Care Net: GTM container ID (HSF-17), Grok key and xAI details (HSF-18), uploads before MCO and staging limits (HSF-19), consent withdrawal (HSF-20), live application (HSF-21), legislation copy items (HSF-23), and the MCO contract (HSF-3).

### Launch controls from the Director's decisions | 23/09/2026

Built under hsf/BUILD-CONTRACT.md section 10 (Amendment 2) and recorded as SPEC.md B14.8. It opens no gate.

- Migration 052_hsf_launch_controls.sql (in the repository, replayed locally, not applied): uploads stay closed until hsf.uploads_open is switched on, once Odendaal has finished the backend and Cassandra and the designer the front end; only companies Care Net has verified as clients upload; staged documents stay at most two years (hsf.staging_retention_days, 730), blocked ones included; every upload is scanned before it can be held or moved; a company may delete its own staged documents after a warning and a PIN by email or SMS that Supabase Auth sends and checks; a receipt from MyClinicOnline that arrives after a deletion is kept and audited so the deletion at MyClinicOnline can follow.
- Worker: supabase/functions/_shared/scan-core.js (structural checks plus a mandatory antivirus engine) and a run order of mode, sweep, scan, transfer claim, cleanup, retention. Server: vercel/api/hsf-delete.js, and hsf-upload.js reads the upload gate and takes verification requests. The builder shows the gate, the scan state, the date each document leaves staging and blocked uploads with their reason, and runs the deletion journey.
- MCO builds the transfer protocol; documents stay in Supabase staging in hold mode until then. hsf/MCO-TRANSFER-REQUIREMENTS.md is Care Net's proposal for the MCO team.
- Legislation clean up: the register release 1.0.0 PDF removed and its CSV moved to hsf/sources/, with both old addresses redirecting to /shop.html#law (HSF-10 closed); the noise and asbestos labels updated in the form and form/onboarding_form.docx regenerated; element names in 048 without provision numbers other than 16(2) and 37(2). The Grok bridge picks the latest Grok model when XAI_MODEL is auto or unset.
- Adversarial review found 8 issues; all fixed with regression checks. Proof on the local replay: replay of 001 to 052 clean; core checks 81, flow checks 239, launch checks 199; node tests 218 of 218; end to end worker run 38 of 38; builder browser drive 180 of 180 at desktop and phone width.
- Register: HSF-1 decided (OMPs do not sign Files; a competent health and safety practitioner signs under hsf/SIGNOFF-CRITERIA.md, with appointment and engagement letters; migration 053 in progress), HSF-19 decided, HSF-20 decided in part, HSF-22 approved, HSF-23 items (a) to (c) done.
- Waiting on Care Net: an antivirus engine with HSF_AV_ENDPOINT and HSF_AV_TOKEN as Supabase secrets; the Supabase Auth email template carrying {{ .Token }}; an SMS provider and hsf.deletion_sms_enabled for SMS PINs; a staff route to see and reset stuck scans and to verify clients; the Director's confirmation that a transfer in flight cannot be deleted for 30 minutes and that an account has at most 10 PIN attempts an hour (HSF-PORTAL-ARCHITECTURE.md section 8).

### File sign off rule (migration 053) | 23/09/2026

On the Director's instruction, OMPs no longer sign Health and Safety Files (hsf/SIGNOFF-CRITERIA.md). Migration 053 (unapplied) makes release need an approved safety content sign off by a registered practitioner whose body and category fit the File's industry (SACPCMP for construction; SACPCMP or SAIOSH elsewhere; mining as a practitioner review), with a current registration, a register check and both an appointment letter and an engagement letter on record (each linkable later from the recruitment portal), plus the client's section 16(2) acceptance. The OMP signed plan is Section E evidence. Proof: replay 001 to 053, core 82, flow, launch and sign off checks (66) pass; node 218 of 218. Open: the rule in SIGNOFF-CRITERIA section 5 awaits the attorney and a registered practitioner; no screen yet records signatories.

### Staff console and metadata removal (migration 054) | 23/09/2026

Built under hsf/BUILD-CONTRACT.md section 11 (Amendment 3), the Director's answers of 23/09/2026 on the launch controls, and recorded as SPEC.md B14.9. It opens no gate.

- Migration 054_hsf_console_and_metadata.sql (in the repository, replayed locally, not applied; 047 to 053 not edited): every upload now has all non essential metadata removed after the security scan, and the cleaned copy replaces the staged bytes (supabase/functions/_shared/metadata-clean.js); only a cleaned copy, with its own fingerprint sha256_clean, is claimed for transfer, and the transfer and staging deletion compare against it. Files the cleaner cannot clean (older .doc and .xls, a PDF whose details it cannot reach, anything it cannot parse) are rejected with a plain reason. The builder shows "Hidden details removed".
- A document on its way to MyClinicOnline can never be deleted by the company; it becomes deletable again only if the transfer stops. At most 5 PIN attempts per account per hour.
- Sign off credentials are checked at the point of use: a register check more than hsf.signoff_register_check_max_days (30) before the decision day no longer releases a File, and hsf_signatory_expiry_alerts lists registrations expiring within 60 days with the unreleased Files they signed (hsf/SIGNOFF-CRITERIA.md section 6).
- Staff console: vercel/hsf-staff.html with vercel/api/hsf-staff.js (clients to verify, scans and staging, signatories, sign offs and readiness), staff only, every write recording the staff member's email. The release gate and the readiness check share one set of rules (hsf_release_rules).
- grok/setup.mjs for Odendaal checks the bot host and chooses the Grok model, sharing its rule with the bridge through grok/model-pick.mjs; grok/.gitignore keeps .env out of the repository.
- The two year limit in staging stays until the Director has audited what the report builder can do (HSF-19).
- Review findings of the round fixed with regression checks. Proof on the local replay: replay of 001 to 054 clean; core checks 82 of 82, flow 239, launch 202, sign off 66 and console 157, all passing; node tests 305 of 305; end to end worker run 54 of 54; staff console browser drives 208 of 208 and, against the local database at 1280 and 390 pixels wide, 229 of 229. backup/cognitive_kernel_rebuild.sql and backup/MANIFEST.md regenerated with 054 and proved by a replay into a fresh database with all five check files passing.
- Register: HSF-1, HSF-19 and HSF-20 updated. Waiting on Care Net: the antivirus engine and its secrets, the Supabase Auth email template carrying {{ .Token }}, the SMS provider if wanted, forge staff roles for the people who will use the console, and the named signatories with their letters and register checks.

### Live Supabase project updated | 24/09/2026

On the Director's instruction ("allow Grok bot access", confirmed as "apply to live now"): migrations 042 (legislation currency, kernel release 1.1.0, OMP ratification of the release still required) and 047 to 055 (File engine, consent and uploads, MCO transfer, kernel API, generation, launch controls, sign off rule, staff console and metadata removal, guidance) applied to the live project. Each file was fetched by the database itself from GitHub at commit 7cc7393, its MD5 checked against the tested local copy before it ran, applied as one transaction and logged in supabase_migrations.schema_migrations. Name clash check first: no object of these migrations existed on live except the three public register views they are meant to redefine; no Bee kernel object touched. Live counts match the local replay. Uploads stay closed (hsf.uploads_open false) and MCO transfer stays in hold mode. HSF-7 is closed on live. Still open: the kernel key (Odendaal issues it in the SQL editor straight into the bot host), Vercel Preview environment variables for /api/kernel, OMP ratification of release 1.1.0.


### File kept apart from the Plan; Care Net client sign off price | 24/09/2026

Contract 15 (Director's instructions of 24/09/2026), built, reviewed adversarially twice, fixed and rechecked:
- No File page (health-and-safety-file, hsf-builder, hsf-sample, hsf-staff, legislation) links, navigates or submits to a Plan page. The logo goes to /health-and-safety-file; the legislation link goes to /legislation; "Build my Plan" is gone. test/api/file-separation.test.js (static) and test/browser/file-links.mjs (Chromium crawl, also run by node --test when Chromium is present) fail on any Plan link.
- Company registration happens inside the builder, signed in only, through /api/signon with source 'hsf', which calls the new hsf_client_register (migration 056): it records the company account and never approves it for the Plan or mints a Plan assessment token. The Plan starts only if the contact later chooses it on the Plan landing. /api/signon v1.4.0 also stops answering an existing account's details or token to anyone but its own signed in contact.
- Wording: the File never says the Plan feeds it; the Plan is named only as a separate Care Net product filed in Section E as evidence, signed by the OMP, who does not sign the File. Element HSF-E-01 no longer names an internal system. The portal offers "Register my company for a File" with the Plan as a separate choice.
- Pricing: Care Net client sign off R4 000,00 excluding VAT; free above 100 medicals a year; whole site and subcontractors free above 500; a sales executive verifies the volume (vercel/hsf/pricing.js).
- Migration 056 (element name, guidance rows, hsf_client_register) applied to live on 24/09/2026 on the Director's confirmation: fetched by the database from GitHub at commit 977ef21, MD5 checked against the tested copy, run as one transaction and logged as 20260924091000. Live check: HSF-E-01 renamed, no MSP FORGE or double comma left in elements or guidance, hsf_client_register present, callable by the service role only.

### Bee-Inspect P1 banners | 24/09/2026

Built under hsf/BUILD-CONTRACT.md 16.3 (hsf/BEE-INSPECT-BUILD-PROMPT.md A1, A2, A4). Not committed, not deployed, nothing applied to live.

- Flag: vercel/js/flags.js (window.CNC_FLAGS). bee_inspect_ads is on for *.vercel.app, localhost and 127.0.0.1 and off everywhere else until the Director switches it on; ?flags=bee_inspect_ads:0|1 overrides; welcome_hook off. Loaded in <head> so banner room is decided before first paint (html.cnc-ads-on).
- Copy, prices and links: vercel/hsf/ads.js (R299,00 a month, extra company R199,00 a month, "VAT to be confirmed"). Banner: vercel/js/cnc-ad.js with vercel/css/cnc-ad.css, 14 959 bytes together (budget 15 KB). Reserved height, below the fold filled by IntersectionObserver, at most two per screen, dismiss for 14 days (AD-01 and AD-05 fold to a strip with Show), subscriber and tenant hooks fed by stubs, counts and industry code only. Loaded on hsf-builder, health-and-safety-file and portal only.
- Placements: AD-01 top of Section F (gaps wording), AD-02 First File guide Section F step, AD-03 gap report after the Section F gaps, AD-04 compliance strip (desktop only), AD-05 twin of the Bee-Matched box, AD-06 health-and-safety-file below "Two ways", AD-07 after Section F in the demonstration, AD-08 portal Files card. Never on loading, sign in, registration, consent, error or setup, never in the consent panel. AD-09 and AD-10 parked. Screenshots: docs/bee-inspect/p1/.
- Tracking: POST /api/hsf-events (vercel/api/hsf-events.js) into hsf_ad_event through hsf_ad_event_record (migration 057, service role only, RLS on with no policy, append only, flood cap). Six fields only, no user, cookie or address. Until 057 is applied the endpoint answers 202 and drops the event.
- Stubs and open inputs: every primary call to action is WhatsApp with a prefilled message until P2 builds /bee-inspect; "See a sample report" withheld until P2; "Open Bee-Inspect" has no address (P3/P4); VAT pending Chantelle ({{vat_inclusive}}); QR with claim code parked (P3); subscriber state and tenant hide/rebrand stubbed until P3 (company_subscription, ad_config); ad_config and ad_dismissal tables left to P3; welcome_hook off.
- Proof: test/api/bee-inspect-ads.test.js (15), test/sql/hsf_ads_checks.sql (35), test/browser/bee-inspect-ads.mjs (174 checks at 1280 and 390, including layout shift flag on against off and the demonstration File flow), existing suites and test/browser/file-links.mjs passing; migrations 001 to 056 unchanged. hsf_core_checks.sql leaves hsf_ad_event to its own check file, as for earlier migrations.

### Migration 057 applied to live | 25/09/2026
On the Director's "yes": 057 (hsf_ad_event, hsf_ad_event_record, hsf_ad_event_summary) fetched from GitHub at 7bb499d, MD5 checked, applied in one transaction, logged as 20260925090000. Live check: RLS on, no anon read or execute, service role execute only. P1 accepted; P2 started.

### Bee-Inspect P2 site pages | 25/09/2026
Built under hsf/BUILD-CONTRACT.md 16 (hsf/BEE-INSPECT-BUILD-PROMPT.md A3). Not committed, not deployed, nothing applied to live. Details, Lighthouse table and screenshots: docs/bee-inspect/p2/index.md.

- Pages on the File shell (File menu plus Bee-Inspect and Get the app, logo to /health-and-safety-file, no Plan link): /bee-inspect (vercel/bee-inspect.html), /bee-inspect/sample-report (vercel/bee-inspect/sample-report.html, watermarked, view only, fictitious Rietvlei Civils and Building, eight pages each with the locked Care Net footer), /get-app (router stub, store addresses null), /claim/{code} (vercel.json rewrite to claim.html, shape check only, code never echoed, noindex, no referrer). Shared: css/cnc-bee.css, js/cnc-bee.js. noindex unless bee_inspect_ads is on for the host (flags.js removes `<meta data-noindex-unless>`); claim always noindex.
- One price source: vercel/hsf/ads.js (plans, AI Wallet in rand, top ups, storage, "VAT to be confirmed"). P1 banners now open /bee-inspect with the UTM rules; AD-01 adds See a sample report. WhatsApp stays as the product page fallback.
- File pages: flagged menu and footer items (css/cnc-header.css), flags.js now also on hsf-sample, hsf-staff and legislation; ?industry= variants on health-and-safety-file (flag gated, preselects CONSTR, MANU, AGRI, HOSP, TRANS, CLEAN, SEC); js/cnc-utm.js keeps utm_* in sessionStorage, puts them on the sign in return address, and the builder sends attribution_seen once at sign in.
- Builder: Section F "Inspection reports" list under AD-01 (flagged; live list is the empty stub until P3; demonstration shows two fictitious Issued reports linking to the sample report).
- Migration 058_hsf_bee_inspect_attribution.sql (new table hsf_attribution_event, hsf_attribution_record, hsf_attribution_summary; 057 could not hold UTM tags). Not applied anywhere but the local replay. /api/hsf-events routes attribution_seen to it and drops it (202) until 058 is applied.
- App link files not published (no placeholder ids): templates in docs/bee-inspect/p2/app-links-templates.md. Store badges, smart app banner and desktop QR with claim code stay parked (contract 16.4, P3).
- Proof: test/api/bee-inspect-pages.test.js, test/sql/hsf_attribution_checks.sql, test/browser/bee-inspect-pages.mjs; P1 tests updated for the switch to /bee-inspect; the new pages added to the File separation, File pages and link crawl checks; hsf_core_checks.sql leaves hsf_attribution_event to its own check file. Migrations 001 to 057 unchanged.

### Official bee, Africa pattern and the Expo link | 25/09/2026
- Bee and pattern (hsf/BUILD-CONTRACT.md 16.5, commit ed76edd): the banners, the /bee-inspect hero and /get-app show the official AutoHive gold bee, New-Site_Bee_Icon_Gold.webp, in place of the drawn bee; /bee-inspect, /get-app and /claim/{code} carry the main site's faded Africa page break. Screenshots in docs/bee-inspect/p1 and p2 were refreshed with stand ins, as neither image host can be reached from the build environment. Not deployed; nothing applied to live.
- Expo link completed from the Director's PC (commit 2ed1820): eas init linked msp-forge/apps/mobile to the Expo project @care-net-consultants/care-net-consultants (ID c292cf70-a15c-4b64-8925-fbd1c238d2d4), owned by the care-net-consultants account, of which the Director is Owner. app.json now carries owner care-net-consultants, slug care-net-consultants (overwritten to match the Expo project) and Android package com.carenetconsultants.carenetconsultants, which becomes permanent once the app is in the Play Store; eas.json holds the development, preview and production profiles; the lockfile's name is corrected to bee-inspect-mobile. The first Android preview build (internal distribution, keystore generated and held by EAS, build 05bf585d-708f-4916-b49c-613f2a197546) finished on 25/09/2026: the Expo starter app named Bee-Inspect, as P4 has not started. The build environment itself still has no EXPO_TOKEN and its network policy blocks api.expo.dev.
- Open: the real bee and page break are still to be seen on the staging preview; no Lighthouse run is recorded for this change; iOS builds wait for the Apple Developer account (contract 16.4); the app icons and splash screen wait for the bee's vector master. On 25/09/2026 the Director reported that the images of www.carenetconsultants.co.za do not load in Chrome, Firefox or Edge. That site is a separate Vercel project (carenet-website, built from ckruger-carenet/carenet-website, last deployed 14/09/2026 with its images moved to img.carenetcdn.com); the cause could not be confirmed from the build environment, and the Bee-Inspect bee loads from the same image host.

### Migration 058 applied to live; P2 accepted | 26/09/2026
On the Director's "correct": 058 (hsf_attribution_event, hsf_attribution_record, hsf_attribution_summary) fetched from GitHub at 2ffa521, MD5 checked, applied in one transaction, logged as 20260926090000. Live check: RLS on, no anon read or execute, service role only. P2 accepted; P3 (Bee-Inspect backend) started.

### Bee-Inspect P3 backend | 26/09/2026
Built under hsf/BUILD-CONTRACT.md 16 (hsf/BEE-INSPECT-BUILD-PROMPT.md sections 6 and 7). Not committed, not deployed, nothing applied to live. Details, migration list, RLS table, Edge Functions and open questions: docs/bee-inspect/p3/index.md.

- Migrations 059 to 063 (47 `bi_` tables, one view; none alters an applied table; 059 refuses to run over an existing `bi_` object): tenancy and roles (inspector, assistant, company_admin, ops through hsf_is_staff), the company is the File's msp_client_account; sites tree and inspection engine with the Fail rule, sealed evidence and 5 x 5 risk; reports, signatures with step up MFA, the Issued guard, kernels (pgvector) and Section F filing into the File through hsf_evidence (engine_generated) and the new bi_report_file_link; AI Wallet in rand with the B8 rules, receipts, storage gate; banner config, claim codes (hash only, 10 minutes, single use), attribution, MCO nodes and packages (supabase_stored only), qualification expiry, POPIA clinical column check, private buckets bi-evidence and bi-reports.
- Edge Functions: 18 thin Deno entry points over tested handlers in supabase/functions/_shared/bi/; stubs answering 501 for transcription, Ozow (rejects), KYC, MCO export and saved card charging; hsf-events stays the Vercel endpoint.
- Seed: supabase/seed/bee_inspect_demo.sql, fictitious Rietvlei Civils and Building with one Issued report filed into HSF-F-01 and a wallet; never for live.
- Proof: replay 001 to 063 clean; five new check files (bi_rls, bi_engine, bi_wallet, bi_claim, bi_popia) and the eleven existing ones pass; node tests 600 of 600 (546 before plus 54 new); migrations 001 to 058 byte identical.
- Waiting on Care Net: the section 12 inputs (email platform, store accounts, saved card gateway, KYC vendor, kernel source, rate card and fx, VAT, MCO endpoint, welcome_hook), the transcription vendor, Ozow's notification specification, RevenueCat product ids, consent wordings, and confirmation of the nine build decisions listed in docs/bee-inspect/p3/index.md.
