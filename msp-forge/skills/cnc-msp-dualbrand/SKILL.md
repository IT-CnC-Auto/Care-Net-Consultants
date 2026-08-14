---
name: cnc-msp-dualbrand
version: 1.0.0
description: "MANDATORY for every CNC MSP FORGE Medical Surveillance Pack render. Use this skill EVERY TIME a dual branded MSP pack, client co branded Care Net document, or MSP FORGE Document Factory render is requested. Extends cnc-letterhead v1.0.0 with the client dual branding layer: CNC mark left, client logo right, enforced clear space, locked footer line, and geometry verification on every build. Use IN ADDITION to the docx skill and the cnc-letterhead skill. ALWAYS read this skill BEFORE writing pack rendering code."
---

# CNC MSP Dual Branding Standard v1.0.0

## 1. Purpose

1.1 This skill governs the dual branded geometry of every Medical Surveillance Pack produced by CNC MSP FORGE. It extends, and never replaces, the cnc-letterhead skill v1.0.0. Construction over correction: the layout is enforced structurally and verified on every build, never patched after render.

## 2. Base geometry, from the canonical Plan CNC-RPT-2026-0812-001

2.1 The canonical Medical Surveillance Plan family uses inline banner images in the header and footer of every page, with these verified values:

| Property | Value |
| --- | --- |
| Page | A4, 11,906 x 16,838 DXA |
| Margins | top 2,892, right 1,417, bottom 3,207, left 1,417 DXA |
| Header distance | 504 DXA; footer distance 504 DXA |
| CNC header banner source | 993 x 230 px PNG (cnc_header_banner.png) |
| Canonical header display | 5,762,625 x 1,333,500 EMU (605 x 140 px), inline, every page |
| CNC footer banner source | 993 x 264 px PNG (cnc_footer_banner.png) |
| Canonical footer display | 5,762,625 x 1,533,525 EMU (605 x 161 px), inline, every page |
| Content width | 9,072 DXA (6.30 inches, 605 px at 96 dpi) |

## 3. Dual brand header band

3.1 The header band is a single borderless two cell table spanning the content width on every page:
3.1.1 Left cell: the CNC banner, scaled to 102 px height (banner aspect held: 440 x 102 px, 4,191,000 x 971,550 EMU). The CNC mark always occupies the left side of the band. This is fixed and never moves.
3.1.2 Right cell: the client logo, processed by prepare_client_logo.py, proportionally scaled to the 102 px cap height band with width never exceeding 130 px, right aligned.
3.1.3 Clear space: the free run between the two marks must be at least 360 DXA (0.25 inches). With the fixed cell widths this is guaranteed structurally and asserted by verify_geometry.py on every build.
3.1.4 CR-13.4 note: when the standalone CNC mark asset is confirmed, the left cell swaps to the mark at the same band height; the band contract and the verifier do not change.

## 4. Client logo pipeline

4.1 prepare_client_logo.py (Pillow): accepts PNG or SVG (SVG rasterised at 300 dpi), validates minimum 600 px source width, normalises transparency (white backgrounds keyed only when lossless), scales proportionally into the 102 px band, and writes client_logo_prepared.png plus a JSON report.
4.2 Lossless corrections are applied automatically. Lossy cases route to human review with the reason stated: source below 600 px, opaque background that cannot be cleanly keyed, or aspect ratio beyond 8:1.

## 5. Footer band

5.1 Every page carries, inside the footer element: one text line in Arial 8pt charcoal with the locked line, Proudly prepared by the Care Net Consultants Team. Your Partner in Workplace Health., followed by the page number field right on the same line, then the CNC footer banner at the canonical display size.
5.2 The locked footer line and the cover carry the same wording, verbatim, always.

## 6. Body standards

6.1 Arial throughout. Legal style numbered headings. Body 10pt charcoal #1A1A1A, headings CNC red #ED1B24 (H1) and charcoal (H2). Tables: header rows shaded charcoal with white bold text via ShadingType.CLEAR (never SOLID), alternating light grey #F2F2F2 body rows, dual DXA widths on table and every cell.
6.2 Locked template blocks (TPL-LIA-01, TPL-POP-01, TPL-SGN-01, TPL-EXA-01, TPL-CGN-01) are inserted verbatim from factory/templates.json and never paraphrased.

## 7. Verification on every build

7.1 verify_geometry.py runs after every render and asserts, from the produced DOCX XML:
7.1.1 Both logo images present in the header with the exact contracted extents.
7.1.2 Clear space between the marks at or above 360 DXA.
7.1.3 Footer banner present with canonical extents, footer line present verbatim, page number field present.
7.1.4 Margins at or above the canonical values so body text cannot collide with either band.
7.1.5 Every locked template anchor resolved in the body text.
7.2 A raster pixel pass (soffice render plus pdftoppm plus Pillow) runs wherever LibreOffice is available and is mandatory in the production factory path; the structural pass is mandatory everywhere. Any failed assertion fails the build.
