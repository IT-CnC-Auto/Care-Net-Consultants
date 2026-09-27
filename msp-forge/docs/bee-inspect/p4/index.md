# Bee-Inspect P4: the phone app

Bee-Inspect P4 (hsf/BEE-INSPECT-BUILD-PROMPT.md sections 0, 3, 5 B3 to B8 and 10 P4; decisions in hsf/BEE-INSPECT-P3-DECISIONS.md; contract 16.5 to 16.8), 27/09/2026. The Expo phone app in `apps/mobile` (Expo SDK 57, React Native 0.86, Expo Router, TypeScript), linked to the Expo project @care-net-consultants/care-net-consultants. Not committed, not pushed, nothing sent to Supabase, Vercel or EAS. Only `apps/mobile/` and this folder were changed; no `packages/shared/` was needed (see Design notes).

**What was tested, honestly:** unit tests (Jest), the type check, lint, a web export, and a scripted walk through of the demo in headless Chromium at 390 x 844 (the screenshots below). **No phone or emulator was used**, no development or preview build was made (this sandbox has no EXPO_TOKEN and cannot reach api.expo.dev), and live mode was never run against a Supabase project (migrations 059 to 063 are not applied anywhere, contract 16.8). Camera, barcode scanning, GPS, biometrics, SQLite and the secure store were exercised only as far as the web preview allows; on the web the store is the browser's localStorage and scanning falls back to typing.

## STOP items (phase P4)

1. [What was built](#what-was-built)
2. [How to run it and make a build](#how-to-run-it-and-make-a-build)
3. [Checks run and results](#checks-run-and-results)
4. [Stubs](#stubs) and [server pieces the app still needs](#server-pieces-the-app-still-needs)
5. [Screenshots](#screenshots)
6. [Open items](#open-items)

The store builds of the P4 STOP (TestFlight and Play internal) wait for the Apple and Google accounts (contract 16.4). The Android preview build below needs only the Expo account.

## What was built

| Area | What the app does | Where |
| --- | --- | --- |
| App shell and brand | Expo Router with a root stack guarded by sign in phase (`Stack.Protected`), native tabs on iOS and Android (`NativeTabs`: Home, Sites, Wallet, Account) and a bottom tab bar on the web preview; Care Net red #ED1B24, deep red #B7141A, ink #0F0F0F, gold #F0A32B; Bebas Neue headings and Inter body, bundled as TTF (converted from the File site's own `vercel/fonts` WOFF2 files with fontTools, SIL Open Font License 1.1). Every colour, size and font is a token in one file. Solid buttons use deep red because white on CNC red is below WCAG AA for body text. Starter screens and images removed. | `src/theme/tokens.ts`, `src/app/_layout.tsx`, `src/components/` |
| Sign in | Email and password; email code or link (Supabase one time code, PKCE link to `beeinspect://auth-callback`); claim code (scan the desktop QR or type the 10 minute, single use code; calls `claim-code-redeem`, then completes the one time sign in token); a lockout and cool down after 5 failures (1 minute, doubling to 15). The Supabase session lives in the Keychain or Keystore (expo-secure-store, chunked for large sessions). | `src/app/sign-in.tsx`, `claim.tsx`, `email-code.tsx`, `auth-callback.tsx`, `src/backend/secure-kv.ts` |
| MFA and step up | TOTP enrolment (QR from Supabase Auth, key to type, open in the authenticator) and verify, mandatory before the app opens. Step up asks for the code again before sign off, Issue, Bee-Matched engagement and top ups over R499,00, and holds for 10 minutes (decision 1.5); sign in MFA does not count as a step up. The app also calls a `step-up-record` function (stub, see below) so the server can record it. | `src/app/mfa-enrol.tsx`, `mfa-verify.tsx`, `src/app/(app)/step-up.tsx`, `src/lib/step-up.ts` |
| Biometric unlock | Offered after the first full MFA; unlocks with fingerprint or face (expo-local-authentication) for 7 days, then the full MFA again; a reinstall (install marker missing from the app's own database while a session is left in the keychain) asks for full MFA; the app locks again after 5 minutes in the background when biometrics are on. | `src/state/app.tsx`, `src/app/unlock.tsx` |
| Rooted or jailbroken | `expo-device` `isRootedExperimentalAsync` at start: a warning on Home and Security, and Issue is blocked. Limits stated in the app: a heuristic that can be hidden by a determined person and can flag a few ordinary phones; the server should check again. | `src/app/(app)/account/security.tsx`, `src/lib/gates.ts` |
| Onboarding and accounts | Organisation profile (legal and trading name, registration, POPIA contact, onboarding status, FICA pack, CIPC, free File eligibility); authorised persons with roles 16(1), 16(2), health and safety manager, officer, representative, first aider, fire marshal, construction manager; professional registrations; qualifications with certificate upload (file picker or camera), expiry and 60, 30 and 7 day alerts; POPIA consents as purpose chips that start as Not given (marketing separate and double opt in; wording versions are placeholders); the inspector status path Identity, FICA, Qualifications, Competence review, then Cleared, Restricted or Assistant only. Start inspection is disabled until the company is Active and the inspector Cleared; Issue needs the dual gate (identity and FICA done, and a verified qualification that has not expired) plus a scope that covers the template (same rule as `bi_signer_cleared`). | `src/app/(app)/account/*`, `src/lib/gates.ts` |
| Sites tree | Company, Site, Department (File department codes), Building or Zone, Room or Area, plus tagged equipment per site; all created offline and synced parents first. | `src/app/(app)/(tabs)/sites.tsx`, `site-new.tsx` |
| Offline inspection canvas | SQLite store (expo-sqlite, one database per mode) with a sync queue: idempotent client ids, inserts with "on conflict do nothing", updates only where the last seen `row_version` still matches (a mismatch is a conflict for a person: keep mine or use the server copy), parents before children, per record order, retry with exponential backoff and jitter (2 seconds up to 5 minutes, 8 attempts, then failed with a retry button), and a parked state when a server function does not exist yet (404 or 501). Per area checklist Pass, Fail, N/A, Observe; Fail needs a photo and a corrective action, plus a voice note under the Strict policy (same rule as `bi_fail_rule_violations`, enforced before a draft). | `src/data/`, `src/lib/sync-queue.ts`, `src/app/(app)/inspection/*` |
| Evidence | Photos by camera or gallery (expo-image-picker), kept in the app's documents folder, SHA 256 fingerprint, GPS (expo-location, only with the location consent), time and inspector id, sealed with the same text as `bi_evidence_seal` so the server's seal can be compared; tap to place labelled markers (annotations). Equipment tags by QR code or barcode (expo-camera) or typed. Voice notes on every item and every area (expo-audio), GPS and time stamped and sealed, offline; the transcript is editable and each correction is a new version; the audio stays the source of truth; VN numbers come from the server on sync. | `src/features/capture.ts`, `src/features/evidence.ts`, `src/components/evidence.tsx`, `voice-recorder.tsx`, `barcode-scanner.tsx` |
| Risk | 5 x 5 inherent and residual matrix with the hierarchy of controls; LOCKED bands 1 to 4 Low green, 5 to 9 Medium amber, 10 to 15 High orange, 16 to 25 Extreme red; the number and the label are always shown together; residual can never be above inherent. Corrective actions with owner and due date. | `src/lib/risk.ts`, `src/components/risk.tsx`, `editors.tsx` |
| AI draft with wallet rules | Before an AI draft the app shows the balance, then the estimate (`wallet-estimate`) and the balance after; a warning when the estimate is more than the balance (with top up or the free template draft); a confirmation that states the 25% overrun cap and that Care Net carries any shortfall (decision 1.3); then `report-draft`. Rand only, never tokens; house format R4 000,00. Every draft carries "Assistive draft. Competent person sign off required." and the locked footer line. | `src/app/(app)/inspection/[id]/draft.tsx`, `src/lib/wallet.ts` |
| Sign off and Issue | Cleared for the scope: review photos and voice notes, step up, sign with a finger (signature pad), Sign and issue. Not cleared: "Find a competent person" opens Bee-Matched (https://www.carenetconsultants.co.za/bee_matched_Recruitment) with the WhatsApp fallback (https://wa.me/27600702723), and the report can be marked as awaiting sign off (after a step up). Issued only after the signature; the result says "Filed into Section F" when the company is eligible (contract 16.8) or "Stored, awaiting eligibility" otherwise. | `src/app/(app)/inspection/[id]/sign.tsx` |
| Wallet and top ups | Balance (included and purchased, next expiry, VAT to be confirmed), top up options R99,00, R249,00 (R260,00 value), R499,00 (R550,00 value), R999,00 (R1 150,00 value), in app purchase as a labelled stub, "Top up on the web (Ozow)" as a placeholder, automatic top up shown as not connected, subsidy notices, statement. A prior subsidy never blocks a top up. | `src/app/(app)/(tabs)/wallet.tsx` |
| Demo mode | "Try the demo" works with no backend, in Expo Go or a browser: the fictitious Rietvlei Civils and Building tenant with the ids of `supabase/seed/bee_inspect_demo.sql`, a scaffold inspection in progress (one Fail complete, one still missing its action and voice note), an earlier Issued fire inspection in Section F, a wallet of R398,20 with a subsidy notice, three clearly marked demonstration photos. Demo controls switch company status, inspector status and File eligibility, spend the wallet down, or reset. In the demo any six digit code passes MFA and any well formed claim code signs in; AI prices use demonstration rates (not Care Net's rate card). | `src/backend/demo-backend.ts`, `demo-seed.ts`, `src/app/(app)/account/demo.tsx` |

### Design notes

- **Two backends, one app.** `src/backend/types.ts` is the contract; `DemoBackend` simulates the server locally; `SupabaseBackend` uses Supabase Auth, PostgREST under the `bi_` RLS policies for capture rows, and the P3 Edge Functions. The live backend is loaded only in live mode.
- **Same arithmetic as the server.** Rand format, price, charge rule, risk bands and claim code shape are ported from `supabase/functions/_shared/bi/` and a parity test imports those modules (read only) to prove the phone and the Edge Functions agree to the cent and to the band.
- **No `packages/shared/` yet.** The shared logic lives in `apps/mobile/src/lib` (pure TypeScript, no React Native imports) with the parity test above. When the web desk (P6) needs it, `src/lib` can move to `packages/shared` unchanged.
- **React Compiler.** The app keeps `experiments.reactCompiler`; the local store hands screens a new handle after every change (`DataStore.getView`), so memoised reads always refresh.
- **Wallet balance in live mode** is computed on the phone from the ledger rows the inspector may read (`bi_wallet_ledger`), the same lot rule as `bi_wallet_balance`, which is service role only; the estimate call returns the server's own balance before every AI run.

## How to run it and make a build

From `msp-forge/apps/mobile`:

```bash
npm install
npx expo start            # scan the QR with Expo Go (SDK 57), or press w for the web preview
npm test                  # unit tests (Jest, jest-expo)
npx tsc --noEmit          # type check
npx expo lint             # lint
npx expo export --platform web   # static web build in dist/
```

Every native module used is in Expo Go for SDK 57, so the demo runs there without a custom build. On iOS, Face ID inside Expo Go is limited; fingerprint or face unlock should be judged on a build.

Android preview build (installable APK, internal distribution), for the Director to run with the Expo account:

```bash
npx eas-cli login
npx eas-cli build --profile preview --platform android
```

The preview profile in `eas.json` now builds an APK and reads the EAS `preview` environment. For live mode, set the two public variables there first (values from the Supabase project, never committed), for example with `npx eas-cli env:create --environment preview` for each name below. Without them the build opens in demo only. An iOS build needs the Apple Developer account (contract 16.4).

### Environment variables (names only)

| Name | Where | Notes |
| --- | --- | --- |
| `EXPO_PUBLIC_SUPABASE_URL` | EAS environment (preview, production) or `.env.local` for local runs | The Supabase project URL. Public by design. |
| `EXPO_PUBLIC_SUPABASE_ANON_KEY` | Same | The publishable (anon) key. Public by design. Never a service role key. |

`apps/mobile/.env.example` holds placeholders only; `.env`, `.env.*` and `.env*.local` are git ignored except the example. Live mode is offered only when both values are set to something real.

## Checks run and results

| Check | Result |
| --- | --- |
| `npx tsc --noEmit` | clean (0 errors). The template's missing `expo-env.d.ts` is covered by a committed `src/types/expo-env.d.ts` that references `expo/types`, as the CLI's generated file does; `tsconfig.json` adds `types: ["jest"]` because TypeScript 6 no longer includes `@types` by default. |
| `npx expo lint` (eslint-config-expo flat config, React Compiler rules) | clean (0 problems) |
| `npm test` (Jest 29, jest-expo 57) | 6 suites, 100 tests, all pass: rand format, top ups and step up threshold, price and charge rule (R6,11 worked example), shortfall, ledger balance (R398,20 seed), estimate display and warnings (never "token"), locked risk bands 1 to 25 with number and label, residual rule, heat map, gates (Start inspection, Issue dual gate, `bi_signer_cleared`, expiry 60, 30, 7), Fail rule (Recommended and Strict), step up window, biometric and 7 day rule, lockout, evidence seal text, claim codes, SA dates, the sync queue (idempotent enqueue, coalescing, dependencies, per record order, backoff, parked, conflict both ways, restart), the local store queue, Postgres error classification, the demo backend end to end (estimate, AI charge, Issue linked or awaiting eligibility, wallet_empty refusal), and parity with `supabase/functions/_shared/bi` (rand, bands, price, charge rule, claim codes). App tests are named `*.spec.ts` so the repository's `node --test` does not pick them up. |
| `node --test` from `msp-forge` (repository suite) | 608 tests, 0 failures (none of them from `apps/mobile`) |
| `npx expo-doctor` (offline) | 19 of 21 checks pass. The 2 that fail need the network: the app config schema check (api.expo.dev) and the React Native Directory check. It found `expo-asset` missing as a peer of `expo-audio`; installed. |
| `npx expo config --type prebuild` | resolves with every plugin; Android permissions camera, microphone, fine and coarse location, biometrics; background location blocked. The image picker and camera plugins carry the same microphone text as expo-audio, because `false` there would remove the microphone permission that voice notes need. |
| `npx expo export --platform web` | builds (`dist/`, static output) |
| Headless Chromium walk through (Playwright, 390 x 844, test microphone, fixed GPS) | the demo flow end to end with no page errors: sign in, claim code, MFA enrol, Home, sites tree, canvas, area, items, risk matrix, completing the Fail rule (action and a recorded voice note), cost preview, AI draft, step up, signature, Issue to Section F, wallet, top ups, account screens, gates, a new inspection with a sealed photo, the estimate above balance warning, working offline and the queue |
| Dependencies | installed with `npx expo install` (offline resolution, `EXPO_OFFLINE=1`, because api.expo.dev is blocked here; versions come from the SDK's own `bundledNativeModules.json`) |

## Stubs

Each is labelled in the code and in the app's words.

| Stub | What the app does now | What replaces it |
| --- | --- | --- |
| In app purchase (RevenueCat) | Live: "In app purchase is not connected yet: the store product ids are still pending. Nothing was charged." Demo: adds a demonstration top up. `react-native-purchases` is not installed: it is not an SDK bundled module and could not be proved in an SDK 57 development build here. | RevenueCat products and `BI_RC_PRODUCT_MAP` (P5), then `react-native-purchases` in a development build |
| Top up on the web (Ozow) | `WEB_TOPUP_URL` is null, so the button says the page is not live yet and offers a sales executive | The web desk billing page (P5 or P6) |
| Automatic top up | Shown as off, needing a saved card that is not connected | `{{saved_card_gateway}}` |
| Transcription | Transcripts are typed or corrected by the person; the machine transcript arrives when the `transcribe` function is connected | Transcription vendor (P5) |
| Identity and liveness | The status path is shown; the checks are done by Care Net until the KYC vendor is connected | `{{kyc_vendor}}` |
| Certificate reading (OCR assist) | The person types the details | Later |
| Consent wording | Versions `BI-*-0.1` are placeholders | Confirmed Bee-Inspect consent wording |
| Bee icon | The app icon and splash are still Expo's defaults; the in app wordmark is text. The official bee is the AutoHive gold bee, to be used as supplied once its vector master is in the repository (contract 16.5); the CDN copy could not be fetched here. | The vector master |

## Server pieces the app still needs

For the lead and the backend agent: the app calls these and treats a 404 or 501 as "not switched on yet" (items stay on the phone, parked in the queue, and are sent automatically once the function exists). None of them was built here, because `supabase/` is out of scope for this task.

| Function or change | Why | Suggested shape |
| --- | --- | --- |
| `step-up-record` | Record the step up (docs/bee-inspect/p3 said P4 wires it) | POST `{purpose}` with the user's aal2 token; `stepUpFromClaims` then `bi_step_up_record` |
| `evidence-upload-url` | The `bi-evidence` bucket has no client policy; photos and voice notes need a signed upload URL before their rows are inserted | POST `{kind, inspection_id, path, sha256, size_bytes, mime_type}` returns `{token}` for `storage.uploadToSignedUrl` (path `<company>/<inspection>/<file>`); checks the storage gate |
| `account-update` | Organisation profile, authorised persons, registrations, qualifications (with certificate), consents: every one of these is read only or denied for clients | POST `{kind, record}`; authorised persons and professional registrations also need tables (`bi_company` has only `s16_1_contact` and `s16_2_contact` text) |
| `report-request-signoff` | Mark a draft as awaiting sign off and record the Bee-Matched engagement | wraps `bi_report_request_signoff` and `bi_report_assign_reviewer` |
| `report-sign` | In app signing and Issue | wraps `bi_report_sign` (after a recorded step up) and, once the P5 renderer stores the PDF and JSON, `bi_report_issue` |
| Eligibility for the free File | The app shows "Filed into Section F" or "Stored, awaiting eligibility" (decision 1.1, contract 16.8); live mode shows eligibility as unknown until the server exposes it | a column or view the company's inspectors may read, and a `bi_report_file_link` status for awaiting eligibility |
| Onboarding, FICA upload and role management endpoints | P3 left them to P4 and P6 | as above (`account-update`) and the web desk |
| Apply migrations 059 to 063 | Live mode reads `bi_` tables; without them the app says Bee-Inspect is not switched on and offers the demo | on the Director's confirmation, behind a flag, with a backup (decision 1.6) |

## Screenshots

Headless Chromium at 390 x 844 (device scale 2, JPEG), web preview of the demo, 27/09/2026. They show the web build, not a phone: native tab bars, camera scanning and biometric prompts look different on a device.

| Screen | What it shows |
| --- | --- |
| [01-sign-in.jpg](01-sign-in.jpg) | Sign in. This build has no server settings, so the demo and the claim code route are offered. |
| [02-claim-code.jpg](02-claim-code.jpg) | Claim code sign in: scan the desktop QR or type the 10 minute, single use code (shape checked as on the File site). |
| [03-mfa-enrol.jpg](03-mfa-enrol.jpg) | MFA is mandatory for inspectors: authenticator (TOTP) enrolment. In live mode the QR comes from Supabase Auth. |
| [04-home.jpg](04-home.jpg) | Home: company Active and inspector Cleared open Start inspection; open inspections show the Fail rule and sync state. |
| [05-sites-tree.jpg](05-sites-tree.jpg) | Sites tree: Company, Site, Department, Building or Zone, Room or Area; everything can be added offline. |
| [06-inspection-canvas.jpg](06-inspection-canvas.jpg) | Inspection canvas: the Fail rule lists what each Fail still needs (Strict voice note policy). |
| [07-canvas-risk-register.jpg](07-canvas-risk-register.jpg) | Risk register with the locked bands: number and label always shown, inherent and residual. |
| [08-area-checklist.jpg](08-area-checklist.jpg) | An area: each checklist line takes Pass, Fail, N/A or Observe. |
| [09-item-fail.jpg](09-item-fail.jpg) | A Fail: result, note, severity and the equipment tag; the Fail rule is met. |
| [10-item-sealed-photo.jpg](10-item-sealed-photo.jpg) | The photo with its sealed metadata: time, GPS, inspector and fingerprint. |
| [11-item-voice-transcript.jpg](11-item-voice-transcript.jpg) | Voice note VN-1 with a versioned, editable transcript; the audio is the source of truth. |
| [12-item-action-risk.jpg](12-item-action-risk.jpg) | Corrective action with owner and due date, and the rated risk (16 Extreme down to 6 Medium). |
| [13-risk-matrix.jpg](13-risk-matrix.jpg) | The 5 x 5 picker: 1 to 4 Low (green), 5 to 9 Medium (amber), 10 to 15 High (orange), 16 to 25 Extreme (red). |
| [14-fail-needs-evidence.jpg](14-fail-needs-evidence.jpg) | The second Fail still needs a corrective action and a voice note. |
| [15-recording.jpg](15-recording.jpg) | Recording a voice note offline (web preview with a test microphone). |
| [16-fail-rule-met.jpg](16-fail-rule-met.jpg) | Both Fails now meet the Fail rule (corrective action saved, voice note recorded and sealed). |
| [17-ai-cost-preview.jpg](17-ai-cost-preview.jpg) | Before an AI draft: the balance first, then the estimate and the balance after, rand only. |
| [18-ai-confirm.jpg](18-ai-confirm.jpg) | Confirmation, with the overrun cap and the shortfall rule in plain words. |
| [19-draft-result.jpg](19-draft-result.jpg) | The draft: "Assistive draft. Competent person sign off required.", the charge in rand, and the voice note count. |
| [20-sign-off.jpg](20-sign-off.jpg) | Sign off for a cleared inspector: review the evidence, step up, sign. |
| [21-step-up.jpg](21-step-up.jpg) | Step up MFA before signing, valid 10 minutes in the app. |
| [22-signature.jpg](22-signature.jpg) | Signature captured after the step up; Sign and issue opens. |
| [23-issued-section-f.jpg](23-issued-section-f.jpg) | Issued only after the signature; filed into Section F because the demo company is eligible. |
| [24-wallet.jpg](24-wallet.jpg) | AI Wallet: balance in rand, included and purchased value, VAT to be confirmed. |
| [25-top-ups.jpg](25-top-ups.jpg) | Top ups R99,00, R249,00 (R260,00 value), R499,00 (R550,00 value), R999,00 (R1 150,00 value); over R499,00 needs step up. |
| [26-subsidy-statement.jpg](26-subsidy-statement.jpg) | Subsidy notices (never a reason to block a top up) and the statement. |
| [27-account.jpg](27-account.jpg) | Account: organisation, authorised persons, inspector status, qualifications, POPIA consents, security, sync. |
| [28-authorised-persons.jpg](28-authorised-persons.jpg) | Authorised persons with 16(1), 16(2) and health and safety roles. |
| [29-inspector-status.jpg](29-inspector-status.jpg) | Inspector status path: Identity, FICA, Qualifications, Competence review, then Cleared, Restricted or Assistant only. |
| [30-qualifications.jpg](30-qualifications.jpg) | Qualifications with verification and 60, 30 and 7 day expiry alerts; certificate upload by file or camera. |
| [31-popia-consents.jpg](31-popia-consents.jpg) | POPIA consents as purpose chips, each starting as Not given; marketing is separate and double opt in. |
| [32-security.jpg](32-security.jpg) | Security: MFA, the 10 minute step up, biometric unlock and the rooted or jailbroken check with its limits. |
| [33-home-gated.jpg](33-home-gated.jpg) | Start inspection stays closed until the company is Active and the inspector Cleared (demo control set to FICA). |
| [34-new-inspection.jpg](34-new-inspection.jpg) | Start inspection: site, template (with its Section F register) and the rooms to walk. |
| [35-new-sealed-photo.jpg](35-new-sealed-photo.jpg) | A new photo sealed on capture: SHA 256 fingerprint, time, GPS and inspector, computed on the phone the same way as the database seal. |
| [36-estimate-exceeds-balance.jpg](36-estimate-exceeds-balance.jpg) | When the estimate is more than the balance: a warning, a top up, or the free template draft. |
| [37-offline-sites.jpg](37-offline-sites.jpg) | Working offline: a new room is saved on the phone and queued; the bar shows sync paused. |
| [38-sync-queue.jpg](38-sync-queue.jpg) | The sync queue: work offline, parents before children, retry with backoff, conflicts resolved by a person, items kept on the phone until their server part exists. |

## Open items

1. **Device testing.** Run the demo in Expo Go on an Android and an iPhone, then make the Android preview build above; check camera and barcode scanning, GPS, voice recording and playback, SQLite persistence across restarts, the secure store, biometric unlock and the relock after 5 minutes. None of this was done here.
2. **Live mode** against a Supabase project with migrations 059 to 063 applied (a staging project or branch, decision 1.6), and the server pieces listed above.
3. **Bee icon** for the app icon and splash (contract 16.5), and the Care Net logo if wanted on the sign in screen.
4. **Font licence.** Bebas Neue and Inter are SIL Open Font License 1.1 (as noted in `vercel/fonts/cnc-fonts.css`); add the licence text beside `apps/mobile/assets/fonts` before a store build (it could not be fetched here).
5. **RevenueCat products, Ozow web top up, saved card gateway, transcription, KYC vendor, consent wording, rate card** (the demo uses demonstration AI rates; live estimates answer rate_card_pending until the rate card is confirmed).
6. **Web preview limits.** The web build keeps records in localStorage, asks for the authenticator code on every reload (no biometrics in a browser), and cannot scan codes; it is for walking the demo, not for live inspections.
7. **Retention and legal hold on the phone.** Evidence files stay in the app's documents folder after sync; a clean up once the server confirms the upload is still to be added with the evidence upload function.
