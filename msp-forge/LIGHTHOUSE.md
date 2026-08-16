# Medical Surveillance Plans page | Lighthouse audit | 16/08/2026

Lighthouse 13.4.1, run locally against Chromium, four mobile runs and two desktop runs. Every run returned the same figures.

| Category | Mobile | Desktop |
| --- | --- | --- |
| Performance | 100 | 100 |
| Accessibility | 100 | 100 |
| Best Practices | 100 | 100 |
| SEO | 100 | 100 |
| Agentic Browsing | 100 | 100 |

Desktop metrics: first contentful paint 225 ms, largest contentful paint 403 ms, cumulative layout shift 0, total blocking time 0 ms. Ninety six audits pass.

## What was wrong, and what was done about it

The first run scored 89 / 96 / 92 / 100. Four things were genuinely wrong with the page and one thing was wrong with the way it was being measured.

**Character set declared too late.** The build comment at the top of the head pushed `meta charset` past the first 1024 bytes, so the browser had to guess the encoding before it read the declaration. The charset now sits on the second line of the document, ahead of the comment.

**Three colour contrast failures, all real.** White text on the brand red measures 4.39 to 1 and AA needs 4.5. The same red as small bold text on white measures 4.39, and on the soft grey panel it drops to 4.06. The accent is now split by role. `--red` stays #ED1B24 for rules, bars, icons, card borders, focus outlines and display sizes, where the standard asks 3 to 1 and 4.39 clears it comfortably. `--red-ink` #C5141B, at 5.9 to 1, carries small bold text and solid button fills. Side by side the difference is barely visible, and it is the difference between a page that passes AA and one that does not.

**A render blocking third party stylesheet.** The three house faces were loaded from a font content delivery network, costing 780 ms of blocked rendering. They are now self hosted from `/fonts/`, latin subset only, and preloaded. Inter and Montserrat are variable fonts, so one file each covers every weight the page uses: 104 KiB for all three faces. All three are SIL Open Font License 1.1, which permits self hosting. This also means no visitor's IP address reaches a third party before they have consented to anything, which is the right posture for a POPIA page.

**Horizontal scroll on every phone size.** Not a scored audit, found by measuring the document against the viewport at seven widths. The logo and two calls to action did not fit across the sticky bar, so the page was 28 pixels wider than the screen at 320, 360, 390 and 414 pixels. The secondary button is now hidden in the sticky bar below 760 pixels. It is still the second button in the hero, so nothing is lost. Measured again at all seven widths: no overflow anywhere.

**The measurement itself.** Two of the first run's failures were the sandbox, not the page: the font request was blocked by the build environment's proxy, which stalled the paint and produced a speed index of 20 seconds, and the local server sent no compression, which showed as a 35 KiB saving that production does not actually have. The harness now mirrors the fonts locally and serves gzip, so the run measures the page.

## What this audit can and cannot tell you

Accessibility, best practices and SEO are environment independent. Those three hundreds hold on the live site.

The performance hundred is measured against a local mirror, because the build environment's proxy blocks the image origin. The images are stand ins generated at the exact declared dimensions, so layout, request count and cumulative layout shift are honest, and transferred image bytes are not. Re-run Lighthouse against the published URL once it is live. The structural work that earns the score, no render blocking requests, preloaded fonts, an explicitly sized and prioritised hero image, zero layout shift, is in the page and travels with it.

## Before it goes live

1. Upload the three font files to `/fonts/` at the publishing origin. The page references them by absolute path, so they must sit at the site root, not beside the page.
2. The canonical host is resolved to `https://www.carenetconsultants.co.za`, which is the host the page's own navigation, footer and privacy links already point at. If the page will live at a different slug, change the canonical, the og:url, the hreflang and the three breadcrumb items.
3. The analytics container identifier is still absent and was never invented. The consent loader works correctly without it and denies every storage category until a visitor accepts.
4. The accent split described above is a brand decision as well as an accessibility one. It is reversible in one line, but reversing it costs the accessibility hundred.
