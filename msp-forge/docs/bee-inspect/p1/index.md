# Bee-Inspect P1: site banners, screenshots

Every placement of the Bee-Inspect add on banners (hsf/BEE-INSPECT-BUILD-PROMPT.md A2, applied under hsf/BUILD-CONTRACT.md 16.3), at desktop 1280 pixels and mobile 390 pixels wide, taken on the local server with the flag `bee_inspect_ads` on (localhost). Each image is cropped to the banner and the page around it; the right side navigator band is hidden in the crops so it does not cover the banner.

Regenerate with `node test/browser/bee-inspect-ads.mjs --shots` (the same run checks every placement, the forbidden states, layout shift, dismiss and collapse, keyboard focus and the File flow).

| Banner | Where | 1280 | 390 |
| --- | --- | --- | --- |
| AD-01 | hsf-builder, top of the Section F card, gaps wording ("4 inspection records outstanding" in the demonstration) | [AD-01-section-f-1280.png](AD-01-section-f-1280.png) | [AD-01-section-f-390.png](AD-01-section-f-390.png) |
| AD-01 collapsed | the one line strip with Show, after the close button | [AD-01-collapsed-1280.png](AD-01-collapsed-1280.png) | |
| AD-01 subscriber | the subscriber hook (stub) shows "Open Bee-Inspect" | [AD-01-subscriber-stub-1280.png](AD-01-subscriber-stub-1280.png) | |
| AD-02 | hsf-builder, First File guide, Section F step, How it works open | [AD-02-first-file-guide-1280.png](AD-02-first-file-guide-1280.png) | [AD-02-first-file-guide-390.png](AD-02-first-file-guide-390.png) |
| AD-03 | hsf-builder, Gap report tab, after the Section F gaps ("Close 4 gaps in Section F") | [AD-03-gap-report-1280.png](AD-03-gap-report-1280.png) | [AD-03-gap-report-390.png](AD-03-gap-report-390.png) |
| AD-04 | hsf-builder, compliance strip under the counts; desktop only | [AD-04-compliance-strip-1280.png](AD-04-compliance-strip-1280.png) | [AD-04-hidden-on-phone-390.png](AD-04-hidden-on-phone-390.png) (the strip without it) |
| AD-05 | hsf-builder, Sign off readiness, twin beside the Bee-Matched box | [AD-05-signoff-twin-1280.png](AD-05-signoff-twin-1280.png) | [AD-05-signoff-twin-390.png](AD-05-signoff-twin-390.png) |
| AD-05 collapsed | the strip with Show | | [AD-05-collapsed-390.png](AD-05-collapsed-390.png) |
| AD-06 | health-and-safety-file, between "Two ways to take it" and "What is in the File", outside the pricing table | [AD-06-landing-1280.png](AD-06-landing-1280.png) | [AD-06-landing-390.png](AD-06-landing-390.png) |
| AD-07 | hsf-builder demonstration (?demo=1), directly after the Section F card | [AD-07-demonstration-1280.png](AD-07-demonstration-1280.png) | [AD-07-demonstration-390.png](AD-07-demonstration-390.png) |
| AD-08 | portal, Health and Safety Files card, above its buttons (demonstration portal) | [AD-08-portal-1280.png](AD-08-portal-1280.png) | [AD-08-portal-390.png](AD-08-portal-390.png) |

Not shown, by design: no banner on the loading, sign in, registration, consent or error states, inside the consent panel, or in setup; none at all with the flag off (`?flags=bee_inspect_ads:0`, and every host other than *.vercel.app, localhost and 127.0.0.1). AD-09 (export page) and AD-10 (email) are parked.

All 19 images are under 300 KB (the largest about 75 KB).
