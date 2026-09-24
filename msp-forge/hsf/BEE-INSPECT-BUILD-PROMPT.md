# Bee-Inspect build prompt (received from the Director, 24/09/2026)

Freeze label: Bee-Inspect-Build-P0-20260924B. Supersedes Bee-Inspect-Master-P0-20260924, Addenda A to D and Bee-Inspect-Build-P0-20260924. Held here as received; hsf/BUILD-CONTRACT.md section 16 records how it is applied in this repository. Where this prompt and the contract differ on house rules (rand format, no internal names, legal numbering, the File never linking into the Medical Surveillance Plan), the contract wins.

RACI: Barteld = product; Odendaal = backend; Cassandra = UI; Chantelle = pricing and VAT; builder = build.
Copy rule: no em dashes. Plain South African English. Adult to Adult (Helena / PIF).
Brand: CNC red #ED1B24; deep red #B7141A; ink #0F0F0F; gold #F0A32B; Bebas Neue; Inter / Montserrat; African pattern strip; gold bee icon.

## 0. Product split (locked)
Two products, one account, one Free Safety File.
1. FREE HEALTH AND SAFETY FILE (web). Care Net's free File builder. The employer builds the File, drops in documents, tracks gaps. No site walk required. Remains free. (Done.)
2. BEE-INSPECT (paid phone app + web desk). The Health and Safety risk assessment and inspection tool. A competent person takes their phone on site, walks the workplace room by room, captures findings, photos, voice notes and risks, and builds a legal inspection / risk assessment report. Grok drafts the report. The competent person reviews and signs. Every Issued report files automatically into Section F (Registers and inspections) of that same free File.
Do not merge these into one app. Do not charge for the File. Do not let unsigned AI drafts become Issued.

## 1. Mission (a new subsection)
A. Update the existing Free Safety File site so it clearly sells Bee-Inspect as the add-on, with banners and a product page, without breaking any existing flow.
B. Build Bee-Inspect: offline first iOS and Android app, plus a Next.js web desk, on the same Supabase project as the File.
C. Ship in phases. One pull request per phase. Stop at each STOP and report.

## 2. What exists today (verified on staging; do not rebuild)
Staging: https://cnc-msp-forge-staging-git-cl-f1797f-auto-hive-wesite-developers.vercel.app
Stack of the File site: static HTML + vanilla JS + CSS on Vercel. Supabase magic link auth and staging uploads. No React, no Next.js, no bundler on this site. Keep it that way for Part A.
Routes: / · /health-and-safety-file · /hsf-builder · /hsf-builder?demo=1 · /hsf-sample · /portal · /shop · /sample · /method · /pilot · /assess · /industry
Builder states: st-loading · st-signin · st-noaccount · st-consent · st-setup · st-file · st-error
Consent: three POPIA checkboxes, version HSF-CONSENT-1.0. MCO not connected yet; files hold at staging.
File view: compliance figure, counts (Uploaded, Linked from MyClinicOnline, Outstanding, Expired, Not applicable), Sign off readiness with Bee-Matched recruit box, tabs Sections | Gap report | Uploads, guide HSF-GUIDE-1.0, 15 section cards A to O with dropzones (PDF/Word/Excel/CSV/JPEG/PNG, max 25 MB) and department dropdown (EXEC, HR, SHE, OPS, ENG, PROC, OH, TRAIN, FAC).
Sections: A Legal and admin · B Policy, organisation, appointments · C Risk · D Training · E Medical surveillance · F Registers and inspections · G Permits · H Emergency · I Incidents · J Occupational hygiene · K Contractors and visitors · L Communication · M Environment and welfare · N Audit and review · O Records and retention
Not built: download / export page. WhatsApp fallback wa.me/27600702723. Bee-Matched portal URL still null.
Assets: /hsf/guidance.js · /hsf/pricing.js · /hsf/samples/construction.js · /js/cnc-*.js · /css/cnc-*.css · /api/hsf-*

## 3. Non negotiables
1. Do not change consent wording, consent version, upload rules, MCO transfer logic or demo behaviour unless a task below says so. Run the existing File flow end to end before and after each phase.
2. POPIA: the File holds special personal information. No third party ad pixels or tag managers on /hsf-builder or /portal. First party events only. Marketing consent separate, unticked, double opt in.
3. AI assists. Humans decide. Nothing is Issued without a competent person's signature and step up MFA.
4. Health and safety inspection and risk assessment data only. No clinical medical results in Bee-Inspect. MyClinicOnline remains the medicals system.
5. Every report page carries the locked footer: CNC logo + "This report is powered by Care Net Consultants Development House (Pty) Ltd". Tenants cannot remove it.
6. Row Level Security on every table. Service role only inside Edge Functions.
7. Public pages: Lighthouse 100 (all four), WCAG 2.1 AA, no layout shift from banners, valid schema.org where relevant.
8. Secrets only in Vercel, Supabase and EAS env settings. Never in the repo.
9. Feature flags for everything new (flags.js on the site, feature_flag table in the app).

## 4. Part A: update the Free Safety File site

### A1. Banner component (vanilla JS)
Create /js/cnc-ad.js + /css/cnc-ad.css (under 15 KB combined) and /hsf/ads.js (copy, prices, links beside /hsf/pricing.js).
Anatomy: gold bee · eyebrow "BEE-INSPECT · ADD-ON" · Bebas Neue headline · one body line · price · primary .btn · ghost secondary · desktop QR with claim code · mobile deep link · dismiss.
Rules: reserve height · lazy load below the fold · on device QR · real buttons, focus ring, aria labels · reduced motion · max 2 Bee-Inspect banners per screen · dismiss hides 14 days (AD-01 and AD-05 collapse, never vanish) · subscribers see "Open Bee-Inspect" · per tenant hide/rebrand toggle · never on st-signin, st-noaccount, st-consent, st-error or inside the consent panel · never block upload, consent or sign off.
Targeting uses only section status counts and industry. Never read document contents.

### A2. Banner placements
| Id | Where | When | Core copy |
|---|---|---|---|
| AD-01 | Section F card (top when expanded) | Always; stronger if F has Outstanding/Expired | "INSPECT IT ON YOUR PHONE. FILE IT HERE." Body: Bee-Inspect walks the site, captures evidence, drafts the risk assessment report for a competent person to sign. Signed reports land in Section F. From R299 pm, extra company R199. CTA Add Bee-Inspect / See a sample report. Has gaps: "{{n}} INSPECTION RECORDS OUTSTANDING" |
| AD-02 | First File guide, Section F step | Guide open | Tip: Bee-Inspect can do these inspections. How it works |
| AD-03 | Gap report tab | F gaps > 0 | "CLOSE {{n}} GAPS IN SECTION F" CTA Turn gaps into a checklist |
| AD-04 | Compliance strip (desktop) | Outstanding + Expired > 0 | "{{n}} outstanding items can be inspected with Bee-Inspect" |
| AD-05 | Sign off readiness, twin beside Bee-Matched | Always | Bee-Matched finds the competent person. Bee-Inspect is their tool on site. |
| AD-06 | /health-and-safety-file | Always | "THE FILE IS FREE. THE RISK ASSESSMENT IS BEE-INSPECT." |
| AD-07 | Demo mode | ?demo=1 | "THIS IS WHERE BEE-INSPECT FILLS SECTION F" |
| AD-08 | /portal Files side | Signed in with a File | "YOUR FILE IS BUILT. KEEP IT CURRENT." |
| AD-09 | Export success page | PARKED until {{export_page_decision}} | Card + QR |
| AD-10 | File ready / nurture email | Marketing consent only | Deep link to get the app |
Mobile: AD-01, AD-03, AD-05 inline; AD-04 hidden.
Welcome hook (flag welcome_hook, default OFF): first template inspection free + R20 AI Wallet.

### A3. New site pages
/bee-inspect product page (hero, 4 steps, features, pricing from pricing.js, sample report, FAQ + FAQPage schema, store badges, desktop QR, WhatsApp fallback) · /bee-inspect/sample-report (watermarked, view only like /hsf-sample) · /get-app smart router (store or open app; desktop shows QR + claim code) · /claim/{code} Universal / App Link target with deferred deep link · /.well-known/apple-app-site-association and assetlinks.json ({{apple_team_id}}, {{android_sha256}}) · Nav + footer: Bee-Inspect, Get the app, store badges · Industry variants: /health-and-safety-file?industry=construction|manufacturing|agriculture|food|logistics|cleaning|security · Smart app banner on mobile web (not inside the builder canvas) · Keep UTM through magic link; store on first sign in · Section F: new "Inspection reports" list (title, site, date, signed by, status). Empty state = AD-01.

### A4. First party tracking
UTMs: utm_source=hsf_builder · utm_medium=in_product_banner · utm_campaign=bee_inspect_addon · utm_content={{ad_id}}_{{variant}}
POST /api/hsf-events to Supabase: ad_impression, ad_click, ad_dismiss, ad_qr_shown, claim_code_created, claim_code_scanned, install, trial_start, subscribe.
Ad platform conversions server side from landing, /bee-inspect and store installs only.

## 5. Part B: Bee-Inspect app (the phone in the competent person's hand)

B1. Repo layout (beside the static site; do not move the site): /apps/mobile Expo (React Native) + TypeScript + Expo Router; /apps/web Next.js App Router on Vercel (auditor desk, company admin, billing, wallet); /packages/shared (types, zod, risk matrix, pricing maths, report schema); /supabase (migrations, RLS, Edge Functions, seed). Static File site stays. Shares Supabase auth. Reads Section F reports from Supabase.

B2. Stack. Mobile: current stable Expo SDK · expo-sqlite offline + sync queue · camera · GPS · audio · barcode/QR · secure storage · biometrics · EAS Build/Submit/Updates · push. Payments: RevenueCat (store subs + wallet top ups) · Ozow (web billing) · {{saved_card_gateway}} for auto top up (Ozow tokenisation if available, else Paystack). Also: xAI Grok via Edge Functions only · transcription on sync · DocuSeal · Telnyx SMS OTP · {{email_platform}} · Branch deferred deep links (never Firebase Dynamic Links) · Sentry. Publisher: {{store_publisher}} (default Care Net Consultants Development House (Pty) Ltd).

B3. Auth. Same Supabase project as the File. Google · Microsoft · email/password · magic link · tenant SSO. MFA mandatory for inspectors (TOTP and/or Telnyx SMS). Step up MFA before Issued, sign off, Bee-Matched engagement, bulk export, top ups over R499. Reset by email or SMS to a verified mobile. Lockout + cool down. Biometric unlock after first MFA (full MFA again after 7 days or reinstall). Rooted/jailbroken: warn and block Issued. Claim code: desktop QR, one time code (10 min, single use), phone signs into the same account and File.

B4. Onboarding and FICA (company + inspector). Company (before first inspection on that company): legal/trading name, registration, CIPC, FICA pack, sites, s16(1)/s16(2) contacts, POPIA contact, optional client logo. Pre fill from Free Safety File profile. Status Not started, In review, Active, Blocked. Start Inspection disabled until Active. Inspector: SA ID/passport + liveness ({{kyc_vendor}}) + verified mobile · FICA · qualifications (type, issuer, number, expiry, OCR assist) · competence scope · declarations. Status path: Identity, FICA, Qualifications, Competence review, Cleared | Restricted | Assistant only. Expiry alerts 60/30/7 days. Expired becomes Restricted.

B5. On site (inspection + risk assessment engine). Hierarchy: Company, Site/Factory, Department, Building/Zone, Room/Area. Per area: checklist findings Pass / Fail / N/A / Observe; photos (area, equipment, risk close up; sealed GPS, time, inspector id) + annotate; equipment tags (QR/barcode); 5x5 risk matrix, inherent and residual, hierarchy of controls; corrective actions (owner, due, closure evidence, overdue escalation). Fail requires photo + corrective action (+ voice note if Strict). Voice notes on every item and section: GPS/time stamped, offline, transcript editable, audio is source of truth, versioned corrections. Tenant policy Recommended or Strict. Templates mapped to Section F registers (scaffolds, ladders, lifting, electrical, fire, PPE, chemicals) plus construction, manufacturing, mining, agriculture, clinics, mobiles, general workplace. Schedules, recurring inspections, overdue dashboard. Append only audit trail. Full offline capture, conflict safe sync.

B6. Grok drafts the report. Kernel store (pgvector): SA OHS Act and regulations, Construction Regulations, ISO 45001 mapping, Care Net methodology, tenant procedures. Versioned (kernel_version). Source: {{kernel_source}}. Edge Function report-draft: findings + photo captions + all voice transcripts + risks, retrieve kernels, Grok fast for tagging/passes, Grok quality for final draft, cache system prompt and chunks, keep prompts under 200k tokens. Output: structured JSON, then PDF. Every legal claim cites a kernel ref. Voice notes footnoted (VN-12). Preview: "Voice notes: N accounted for, 0 missing" (Strict blocks if any missing). Every draft labelled: "Assistive draft. Competent person sign off required." PDF: client logo cover · executive summary · risk heat map · areas · findings + photos · equipment · risk register extract · corrective actions · legal references · voice note index · locked CNC footer every page.

B7. Sign off and Bee-Matched. Cleared for scope: sign in app (DocuSeal or in app + step up MFA). Not cleared: "Find a competent person", Bee-Matched ({{bee_matched_url}}, WhatsApp until live), engagement letter, reviewer confirms photos + voice notes, signs. Unsigned = Draft or Awaiting sign off only. Issued = PDF + JSON in Supabase + appears in Free Safety File Section F + secure share link with expiry.

B8. Pricing, AI Wallet, storage. Base R299 pm: one auditor, first company, unlimited inspections and template reports, R150 AI Wallet / month, 10 GB. Extra company R199 pm: R100 AI Wallet / month, 10 GB. VAT: {{vat_inclusive}} (Chantelle). AI Wallet in rand (never show tokens). Cost preview before each AI action; charge actual after. Price = (tokens x model rate + audio min x transcription rate) x fx x markup (default 3.0). If actual > estimate + 25%, charge the estimate. Included value rolls 1 month; purchased lasts 12 months. Top ups: R99 · R249 (R260) · R499 (R550) · R999 (R1,150). Auto top up opt in: +R99 when below R20. Company wallet + spend caps. At R0, capture and template reports still work. Usage statement + CSV. Photo tagging free to 50 per report. Storage: 10 GB free per company line; packs at {{rate_card}}; warn 80/95%; at 100% block new photos/voice (view/sync continue). welcome_hook flag (default OFF): 1 free template inspection + R20 wallet.

B9. MCO bridge. Now: register company/site/department nodes · push report package to Supabase · status supabase_stored. Later: inspect_package_v1.json + artifacts.zip · status mco_ingested. Stub {{mco_endpoint}}; do not call MCO until it exists.

B10. Web desk (Next.js, apps/web). Auditor: portfolio, schedules, NCR board, report review/sign off, wallet, storage, Ozow billing, usage. Company admin: sites tree, departments, users/roles, company wallet/caps, white label logo, report library. Ops (Care Net only): rate card, kernels, markup, flags, funnel dashboard, Wire-up Console (every screen, RpcName, request/response JSON, roles, fixtures, WireState Unspecified to Live).

## 6. Data model (Supabase migrations, RLS on all)
tenant · company · company_subscription · site · department · building · room · app_user · role_assignment · inspector_profile · inspector_qualification · fica_record · consent_record · attribution · claim_code · template · template_item · inspection · inspection_area · finding · photo · equipment · risk · corrective_action · voice_note · report · report_version · signature · kernel_doc · kernel_chunk · kernel_version · wallet · wallet_ledger · usage_event · rate_card · iap_receipt · ad_config · ad_event · ad_dismissal · mco_node · transfer_package · feature_flag · audit_log
Link to existing HSF tables: {{hsf_file_table}} and Section F. Read schema first; extend; never duplicate.

## 7. Edge Functions
claim-code-create · claim-code-redeem · hsf-events · report-draft · transcribe · wallet-estimate · wallet-charge · revenuecat-webhook · ozow-notify · autotopup-run · storage-meter · docuseal-webhook · kyc-webhook · qualification-expiry (cron) · schedule-reminders (cron) · ncr-escalation (cron) · hsf-section-f-sync · mco-register · mco-export. Zod inputs. Idempotency on payments/webhooks. Unit tests each.

## 8. Security and POPIA
RLS per tenant/company · auditors see only subscribed companies · signed URLs · consent for identifiable people in photos · GPS sealed in evidence · retention + legal hold · audit every FICA/qualification read · rate limits on auth, claim codes, AI · dependency + secret scanning in CI.

## 9. Done means
Playwright: File flow before/after · every banner state · no banners on forbidden states · Lighthouse CI 100. Unit: pricing maths, wallet cap, risk matrix, report schema. RLS tests per role (inspector, assistant, company admin, ops, other tenant). Maestro/Detox: offline inspection with photos + voice, sync, claim code sign in, draft, sign off, Issued appears in Section F. RevenueCat sandbox, wallet credit. Seed staging demo tenant: Rietvlei Civils and Building (fictitious).

## 10. Phases (one PR each)
P1 Site banners (A1, A2, A4) behind flag bee_inspect_ads. STOP: staging preview URL + screenshots of every placement, desktop and mobile.
P2 Site pages (A3). STOP: preview + Lighthouse report.
P3 Backend (sections 6 and 7) with stubs for unknown vendors + seed. STOP: migration list, RLS results, open questions.
P4 Mobile core: auth/MFA/claim code, onboarding/FICA, sites tree, offline canvas, photos, voice, sync. STOP: EAS internal builds (TestFlight + Play internal) if store accounts exist, else Expo dev build.
P5 Reports and money: kernels, report-draft, PDF, sign off, Bee-Matched link, wallet, IAP, Ozow, storage, Section F sync. STOP: sample Issued PDF from demo tenant + wallet statement.
P6 Web desk + Ops (B10), funnel dashboard, Wire-up Console, MCO exporter. STOP: store submission checklist (listing copy, screenshots, privacy labels, data safety).

## 11. Accounts (for the owner, not for the builder to open)
Required before P4 store builds: Apple Developer · Google Play Console · Expo/EAS · RevenueCat · Branch. Likely already available: Vercel · Supabase · Ozow · Telnyx · DocuSeal · xAI. Before real charges/SMS: {{email_platform}} · {{kyc_vendor}} · transcription · Sentry · {{saved_card_gateway}} if auto top up. Builder: use stubs and env placeholders; never commit secrets.

## 12. Open inputs (ask; do not guess)
{{forge_repo}} · {{email_platform}} · {{store_publisher}} and whether Apple/Google accounts exist · {{apple_team_id}} · {{android_sha256}} · {{saved_card_gateway}} · {{kyc_vendor}} · {{kernel_source}} · {{bee_matched_url}} · {{rate_card}} · {{vat_inclusive}} · {{export_page_decision}} · {{mco_endpoint}} · {{hsf_file_table}} · welcome_hook on or off.
When an input is missing: build a clearly labelled stub, list it in the PR description, continue.

## 13. Start here
1. Confirm repo access to {{forge_repo}}. 2. Implement P1 banners only. 3. Stop with staging preview and screenshots. Do not start mobile or Next.js desk until P1 is accepted.
