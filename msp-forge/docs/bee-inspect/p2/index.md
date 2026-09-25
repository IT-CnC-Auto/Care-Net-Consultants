# Bee-Inspect P2: site pages

Bee-Inspect P2 (hsf/BEE-INSPECT-BUILD-PROMPT.md A3, applied under hsf/BUILD-CONTRACT.md 16), 25/09/2026. Built on the static File site (HTML, vanilla JS, CSS; no bundler). Not committed, not deployed, nothing applied to the live Supabase project.

## What was built

| Route | File | Notes |
| --- | --- | --- |
| /bee-inspect | vercel/bee-inspect.html | Hero, four steps, the File stays free, AI assists and people decide, features, pricing from /hsf/ads.js, sample report, store status as text ("coming soon"), FAQ with FAQPage JSON-LD, WhatsApp fallback |
| /bee-inspect/sample-report | vercel/bee-inspect/sample-report.html | Watermarked SAMPLE, view only; fictitious Rietvlei Civils and Building; eight pages, each with the locked footer (Care Net logo and "This report is powered by Care Net Consultants Development House (Pty) Ltd") |
| /get-app | vercel/get-app.html | Router stub: device detection ready (js/cnc-bee.js), store addresses null, "Tell me when it is ready" on WhatsApp, link back to /bee-inspect |
| /claim/{code} | vercel/claim.html + vercel.json rewrite | Shape check only (6 to 12 letters or digits); the code is never written into the page, stored or sent; always noindex, no referrer |
| /.well-known/* | not published | Templates with {{apple_team_id}} and {{android_sha256}}: [app-links-templates.md](app-links-templates.md) |

Also: flagged "Bee-Inspect" and "Get the app" in the menu and footer of the five File pages; `?industry=` variants on /health-and-safety-file; campaign tags kept through the sign in link (js/cnc-utm.js, `attribution_seen` through /api/hsf-events into migration 058); the Section F "Inspection reports" list in the builder; every P1 banner now opens /bee-inspect with the UTM rules and AD-01 adds "See a sample report".

noindex: /bee-inspect, the sample report and /get-app carry `<meta name="robots" content="noindex" data-noindex-unless="bee_inspect_ads">`, which js/flags.js removes where the flag is on (staging and local). In production, while the flag is off, they stay noindex. When the Director switches the flag on for production, drop the tag in the same release so crawlers that run no script agree.

## Lighthouse

Lighthouse 12.8.2 (`npx --yes lighthouse@12`), Chromium from /opt/pw-browsers, against server/serve.js with gzip in front, median of three runs, flag on (127.0.0.1). Scores: [lighthouse/summary.json](lighthouse/summary.json). The full HTML and JSON reports (about 17 MB) are not kept in the repository; regenerate them with the command below. Rerun: `node docs/bee-inspect/p2/lighthouse/run-lighthouse.mjs --runs 3`.

| Page | Form factor | Performance | Accessibility | Best practices | SEO | LCP | CLS |
| --- | --- | --- | --- | --- | --- | --- | --- |
| /bee-inspect | desktop | 100 | 100 | 100 | 100 | 0.5 s | 0.006 |
| /bee-inspect | mobile | 100 | 100 | 100 | 100 | 1.9 s | 0 |
| /bee-inspect/sample-report | desktop | 100 | 100 | 100 | 100 | 0.4 s | 0 |
| /bee-inspect/sample-report | mobile | 100 | 100 | 100 | 100 | 1.7 s | 0 |
| /get-app | desktop | 100 | 100 | 100 | 100 | 0.5 s | 0 |
| /get-app | mobile | 99 | 100 | 100 | 100 | 2.0 s | 0 |
| /health-and-safety-file | desktop | 100 | 100 | 100 | 100 | 0.5 s | 0.009 |
| /health-and-safety-file | mobile | 98 | 100 | 100 | 100 | 2.1 s | 0.04 |

Below 100, and why:
- /get-app mobile, performance 99: largest contentful paint 2.0 s (score 0.97) under simulated slow 4G. It sits on the edge (single runs gave 99 and 100). The paint waits on the render blocking requests in `<head>` (four stylesheets and flags.js) over the local server's HTTP/1.1, which Lighthouse models with six connections; Vercel serves HTTP/2.
- /health-and-safety-file mobile, performance 98: unchanged by P2. The commit before P2 (7bb499d exported with `git archive`) scores the same 98 with the same numbers. Causes: ten render blocking requests in `<head>` (first contentful paint score 0.97) and a font swap in the hero at 390 pixels that moves the hero photograph (CLS 0.04). Fixing them means changing the shared font loading (cnc-fonts.css, `font-display`) or the shared script order, which reaches the Medical Surveillance Plan pages too; left for a decision rather than changed in this phase.
- SEO 100 is measured with the flag on. With the flag off (production today) the three pages are noindex by design, which Lighthouse scores down.

How it was measured (as in msp-forge/LIGHTHOUSE.md): the build environment's proxy blocks img.carenetcdn.com and the r2.dev icon host, so Chromium maps those hosts to a local HTTPS stand in answering drawn images of the declared size; request counts, layout and shift are honest, image bytes are not. On the new pages, cnc-config.js and cnc-tracking.js load with `defer` (same order, end of `<head>`; nothing on those pages reads them before load), and the price and store data load in the body with their room reserved.

## Screenshots

Regenerate with `node test/browser/bee-inspect-pages.mjs --shots` (the image host is answered by stand ins; the logo is cut from the letterhead in hsf/examples/letterhead). All under 300 KB (largest about 250 KB).

| What | 1280 | 390 |
| --- | --- | --- |
| /bee-inspect, hero and steps | [bee-inspect-top-1280.png](bee-inspect-top-1280.png) | [bee-inspect-top-390.png](bee-inspect-top-390.png) |
| /bee-inspect, pricing and AI Wallet | [bee-inspect-pricing-1280.png](bee-inspect-pricing-1280.png) | [bee-inspect-pricing-390.png](bee-inspect-pricing-390.png) |
| /bee-inspect, get the app and FAQ | [bee-inspect-faq-1280.png](bee-inspect-faq-1280.png) | [bee-inspect-faq-390.png](bee-inspect-faq-390.png) |
| Sample report, cover | [sample-report-cover-1280.png](sample-report-cover-1280.png) | [sample-report-cover-390.png](sample-report-cover-390.png) |
| Sample report, summary and heat map | [sample-report-heat-map-1280.png](sample-report-heat-map-1280.png) | [sample-report-heat-map-390.png](sample-report-heat-map-390.png) |
| Sample report, findings | [sample-report-findings-1280.png](sample-report-findings-1280.png) | [sample-report-findings-390.png](sample-report-findings-390.png) |
| Sample report, draft label, Issued, sign off | [sample-report-sign-off-1280.png](sample-report-sign-off-1280.png) | [sample-report-sign-off-390.png](sample-report-sign-off-390.png) |
| /get-app | [get-app-1280.png](get-app-1280.png) | [get-app-390.png](get-app-390.png) (iPhone) |
| /claim/{code} | [claim-code-1280.png](claim-code-1280.png) | [claim-code-390.png](claim-code-390.png) |
| /health-and-safety-file?industry=food | [hsf-industry-food-1280.png](hsf-industry-food-1280.png) | [hsf-industry-food-390.png](hsf-industry-food-390.png) |
| Builder demonstration, Section F Inspection reports under AD-01 | [section-f-inspection-reports-1280.png](section-f-inspection-reports-1280.png) | [section-f-inspection-reports-390.png](section-f-inspection-reports-390.png) |

## Stubs and open inputs

- Store accounts, {{store_publisher}}, {{apple_team_id}}, {{android_sha256}}: no badges, store links, smart app banner or association files until they exist (HSF_ADS.app all null).
- Desktop QR with claim code and claim-code-redeem: P3. /claim checks the shape only.
- {{vat_inclusive}}: "VAT to be confirmed" (Chantelle). {{rate_card}}: storage packs "price to be confirmed".
- Inspection reports in Section F: empty stub list until P3 reads Issued reports.
- "Open Bee-Inspect" for subscribers: WhatsApp until an app or web desk address exists (P3, P4).
- Migration 058 (attribution): written and replayed locally only; needs the Director's confirmation before it goes to live. Until then /api/hsf-events drops attribution_seen with 202.
- Supabase Auth redirect allow list: the sign in return address now carries utm_* when a visit arrived tagged. Odendaal to confirm the allow list entries for the builder use a wildcard that admits a query string (for example `https://<host>/hsf-builder**`); without tags the address is exactly as before.
