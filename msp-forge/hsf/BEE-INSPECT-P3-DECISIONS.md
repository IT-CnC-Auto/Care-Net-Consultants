# Bee-Inspect P3 decisions (received from the Director, 27/09/2026)

Freeze label: Bee-Inspect-P3-Decisions-P0-20260927. Held as received (sections 0 to 3). Sections 4 to 8 ("full Quintis endpoints, CI acceptance tests, builder order, and non goals") and the MCO spec were referred to as attachments but were not received. hsf/BUILD-CONTRACT.md 16.8 records how these decisions apply.

## 0. Status
P3 accepted. 600 node tests; 16 SQL check files (5 Bee-Inspect). Wallet maths verified to the cent: actual R6,25 against estimate R5,00 (overrun above 25% of the estimate) bills the estimate, R5,00. P4 is the Expo phone app on the linked Expo project. Do not invent deploy URLs; hand off a UI demo only when a real preview, APK or Expo Go link exists.

## 1. Decisions (locked 27/09/2026)
1.1 Issued Bee-Inspect report and Free Safety File compliance (contract 16.7): yes, an Issued report raises the File compliance figure, but only when the File owner qualifies for free digital Safety File entitlement. Eligible when either: A. a verified Care Net Consultants client with more than 50 medicals in the rolling 12 months; or B. a big site with more than 500 medicals in the rolling 12 months (site registry / MCO count). When eligible: the principal's digital Safety File stays free; all subcontractors registered on that same site also receive a free digital Safety File for that site; Issued reports for that site may raise Section F and the compliance figure. Verification: Care Net client flag plus medicals count from the occupational health / MCO source of truth, not self declaration alone. When not eligible: paid File / paid Bee-Inspect rules apply; do not raise free File compliance from a Bee-Inspect issue without the eligibility check.
1.2 Risk bands (5x5, likelihood x severity = 1 to 25): 1 to 4 Low (green); 5 to 9 Medium (amber); 10 to 15 High (orange); 16 to 25 Extreme (red). Show the number and the band label. Never invent other cut points.
1.3 AI Wallet overspend: if a charge exceeds the remaining balance, set the wallet to R0,00 and Care Net carries the difference (subsidy ledger row: reason, estimate, actual, shortfall, job id, user id). Users may always top up (RevenueCat in app and/or Ozow in the account); never block a top up because of a prior subsidy. Keep the estimate cap (actual more than 25% above the estimate bills the estimate). Always show the remaining balance before a run; warn when the estimate exceeds the balance.
1.4 Minimum margin 20% on all products and services after all costs (model tokens, voice minutes, storage, SMS, payment gateway fees, app store cut, KYC, transcription): sell price excluding VAT >= total landed cost / 0,80. Applies to R299, R199, wallet top ups, storage packs and add ons. Prefer Ozow web for wallet top ups where the Apple or Google cut would break the floor.
1.5 Step up sign in: app 10 minutes; DocuSeal signing 24 hours.
1.6 Migrations 059 to 063: apply on Bee-Inspect staging only; promote to live when P4 needs the tables, behind a feature flag, with a backup; keep the five SQL checks in CI; do not apply to the production Care Net database until then.
1.7 Export page: super users only; audit every export.
1.8 Bee-Matched: https://www.carenetconsultants.co.za/bee_matched_Recruitment
1.9 Vendors (email, KYC, saved card gateway, transcription, Ozow notification spec, RevenueCat product ids, rate card, VAT (Chantelle), consent wording, monthly legal kernel and expanded industries): yes, wire when keys exist.
1.10 MCO: Quintis builds from the MCO spec. No fake production URL.

## 2. Accounts and settings (advanced H&S)
Organisation profile; multiple authorised persons (16(1), 16(2) and H&S roles); professional registrations; qualifications; certificate uploads with expiry; POPIA consents (purpose chips, default Not given); MFA and step up; billing, wallet and subsidy notices. Dual gate: FICA/KYC and qualification before Issue.

## 3. P4
Expo phone app: inspection flow, locked risk bands, voice, photos, AI draft with wallet rules, Bee-Matched sign off, Issue to Section F when eligible, offline queue, 10 minute step up.
