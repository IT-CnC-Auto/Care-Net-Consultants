# Bee-Inspect P4 v2: all 17 industries, places of inspection, evidence storage

27/09/2026. The rebuild of the phone app's scope after the Director's review of the same day: *"The Health and Safety App is very Limited and the scope feels like its only for construction rebuild the scope to the full 17 industries, the app needs to register a site, office, department or place of inspection ... The Photos and the inspections needs to be stored according to the most advance way or storing files and file management systems and the thought of the app must feel advance but be simple and easy to use and function."* Not committed, not pushed; nothing sent to Supabase, Vercel or EAS. Migration 065 is written and replayed locally only.

**Tested honestly:** Jest, the type check, lint, the repository's node suite, the SQL replay with every check file, a web export and a scripted walk through the demo in headless Chromium at 390 x 844 (the screenshots below). No phone or emulator was used; FTS5 search, the camera, image derivation on a device, haptics and the native tab bar were not exercised on a device.

## What changed

| Area | What the app does now | Where |
| --- | --- | --- |
| Icon and splash | The Director's icon set: `icon-1024.png` as the app and iOS icon, the red `adaptive-icon-background.png` behind a white bee for Android (rendered from the vector master, fitted inside the 66 of 108 dp safe zone, with the stripes, letters and tick cut through), the same shape as the Android themed (monochrome) icon, a red #DC2626 splash with the white bee, and the supplied 48 pixel favicon. Expo's default icon folder is removed. See [00-app-icon-set.jpg](00-app-icon-set.jpg). | `apps/mobile/scripts/build-icons.mjs`, `app.json`, `assets/images/` |
| The kernel on the phone | An offline bundle of the Care Net Cognitive Kernel: the 17 industries with their 56 subindustries, the 44 activity triggers, the File departments, 18 place types with the types each industry is offered, and 39 inspection templates (22 Section F registers and 17 industry walkthroughs, 346 checklist lines), each item carrying the source id it came from. A refresh hook waits for the kernel service. | `scripts/build-kernel-bundle.mjs`, `assets/kernel/kernel-bundle.json`, `src/lib/kernel.ts` |
| Register a company | One guided flow, Company, then places, then people, with a four step progress bar, saved on the phone after every step (a Home card resumes it): legal and trading name, registration number, the industry (search the 17) and subindustry from the kernel, the OHS Act 16(1), 16(2) and POPIA contacts (folded until wanted); then the places the kernel suggests for the industry (keep, rename or skip) and the File departments its registers most often sit with; then authorised persons, inspectors and assistants. | `src/app/(app)/register.tsx` |
| Places of inspection | A flexible tree of typed places: site, office, branch, factory or plant, warehouse, workshop, farm, mine or quarry section, school campus, clinic or laboratory, retail store, depot, vehicle or fleet, construction project, department, building or block, floor, room or area. Only the types that suit the industry (and the parent) are offered; a person may give a type their own name. Each place can carry an address, GPS, a responsible person, a headcount and linked departments. Every place has Start inspection here. | `src/lib/places.ts`, `src/features/places.ts`, `src/app/(app)/(tabs)/sites.tsx`, `place/[id].tsx`, `place/edit.tsx` |
| Moving between company, sites and places | A context bar under the wordmark on every tab (company and recent place) opens the switcher: one search box over every company and place (instant, word starts, breadcrumbs), recent places, the companies, all places, each with Start inspection here. Breadcrumbs on every place are tappable. | `src/app/(app)/switcher.tsx`, `src/components/place-ui.tsx` |
| Inspections per industry | The template picker is shaped by the industry and the kind of place: the industry walkthrough first, then the Section F registers the place suits (machine guarding in a workshop, stacking in a warehouse); all 22 Section F registers stay available everywhere. Each shows where it files, how often ("Set by your competent person" where the kernel holds no verified interval), who usually does it, its legal basis and its retention. The engine is unchanged: Pass, Fail, N/A, Observe, the Fail rule, the locked risk bands, corrective actions, voice notes, sealed photos. | `src/app/(app)/inspection/new.tsx` |
| Demonstration data | Five fictitious companies from five industries, the sample companies of the File site: Rietvlei Civils and Building (construction), Magaliesberg Aggregates (mining), Karoo Pathology and Day Hospital (healthcare), Midlands Wholesale Distributors (retail and wholesale), Umzimkhulu Valley Farming (agriculture), each with a places tree, an inspection in progress on a kernel template, drawn demonstration photos, risks across all four bands, and a wallet. Construction only wording is gone from the app. | `src/backend/demo-seed.ts`, `scripts/build-demo-photos.py`, `assets/demo/` |
| Evidence and file management | Content addressed storage (SHA 256 identity, dedupe per company), an immutable original with a thumbnail and a web copy without camera metadata, the canonical path, a metadata sidecar, versions instead of overwrites, tags, full text search (FTS5 on the phone, an in memory index otherwise), retention and legal hold respected, the storage meter against the 10 GB line, a resumable chunked upload with an integrity check (server stubbed). Design: [../evidence-storage.md](../evidence-storage.md). | `src/lib/evidence-store.ts`, `upload-plan.ts`, `search-index.ts`, `src/features/capture.ts`, `search.ts` |
| Evidence library | A new tab: storage, instant search, filters (type, risk band, age, company, place), grouping by place, inspection or date; each item opens its original, sidecar, storage details, tags, versions and a secure link placeholder. | `src/app/(app)/(tabs)/evidence.tsx`, `evidence/[id].tsx` |
| Backend | Migration 065 (see below) and the kernel templates seed. | `supabase/migrations/065_bi_places_evidence.sql`, `supabase/seed/bee_inspect_kernel_templates.sql` |
| UX | One design token file (CNC red #ED1B24 accents, deep red #B7141A solid buttons, ink, gold), Bebas Neue headings, 48 pixel touch targets, one primary action per screen, empty states that teach, haptics on choices and saves (expo-haptics), accessible names on every control, a signal and sync state on every tab ("Offline, 3 on phone"). | `src/theme/tokens.ts`, `src/components/`, `src/features/haptics.ts` |

## The 17 industry bundle

Kernel 1.1.0 (release of 16/09/2026, `msp_kernel_version`), guidance HSF-GUIDE-1.0. Built by `node apps/mobile/scripts/build-kernel-bundle.mjs` from a fresh replay of migrations 001 to 064, `hsf/guidance/guidance.json`, `vercel/hsf/samples/*.js`, `vercel/hsf/pricing.js` and `hsf/sample-file/instruments.json`; `--check` rebuilds and compares.

| Industry | Regime | Subindustries | Triggers (overlay and sample) | Place types offered | Templates suggested | Walkthrough checks | First suggested places |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AGRI Agriculture and forestry | OHSA | 3 | 13 | 12 | 14 | 13 | farm, factory or plant, warehouse |
| CLEAN Cleaning and hygiene services | OHSA | 2 | 10 | 8 | 13 | 20 | site, vehicle or fleet |
| CONSTR Construction | OHSA | 5 | 22 | 11 | 17 | 10 | construction project, warehouse, workshop |
| EDU Education | OHSA | 2 | 8 | 10 | 11 | 9 | school campus, clinic or laboratory |
| GOV Government and municipal | OHSA | 3 | 17 | 11 | 13 | 14 | depot, workshop, vehicle or fleet |
| HEALTH Healthcare and laboratories | OHSA | 3 | 10 | 8 | 12 | 12 | clinic or laboratory |
| HOSP Hospitality and food service | OHSA | 2 | 10 | 7 | 12 | 9 | site |
| MANU Manufacturing | OHSA | 7 | 20 | 11 | 18 | 20 | factory or plant, warehouse, workshop |
| MINING Mining | MHSA | 6 | 15 | 11 | 13 | 13 | mine or quarry section, factory or plant, workshop |
| OFFICE Office and professional services | OHSA | 2 | 4 | 8 | 9 | 5 | office, vehicle or fleet |
| PETRO Petrochemical and fuel retail | OHSA | 3 | 17 | 12 | 13 | 20 | factory or plant, retail store, depot |
| RETAIL Retail and wholesale | OHSA | 2 | 11 | 11 | 12 | 7 | retail store, warehouse, workshop |
| SEC Security services | OHSA | 2 | 7 | 8 | 9 | 9 | site, vehicle or fleet |
| TEL Telecommunications and tower work | OHSA | 3 | 11 | 9 | 13 | 13 | site, vehicle or fleet, construction project |
| TRANS Transport and logistics | OHSA | 5 | 12 | 11 | 15 | 7 | depot, warehouse, workshop |
| UTIL Utilities and energy | OHSA | 3 | 14 | 10 | 13 | 17 | factory or plant, vehicle or fleet, construction project |
| WASTE Waste management | OHSA | 3 | 12 | 10 | 13 | 16 | depot, workshop, vehicle or fleet |

Where each part comes from:

- **Industries, subindustries, triggers, departments, sections, elements, overlays, appointments, instruments:** the kernel as the migrations load it (`msp_industry`, `msp_subindustry`, `hsf_trigger`, `hsf_department`, `hsf_section`, `hsf_element`, `hsf_element_industry`, `hsf_appointment_type`, `hsf_element_instrument` with `msp_legal_instrument`). The instrument states are cross checked against `hsf/sample-file/instruments.json`.
- **Triggers per industry:** those its overlay switches on (the SPEC B7 "switched on through" notes) and those its sample assessment raised (`vercel/hsf/samples`), each tagged with its source.
- **Section F register templates (22):** one per Section F element; the checklist lines are the element's own "what to submit" (Records to see) and "common gaps" (Gaps to look for, Pass means not found) from the File guidance, word for word. Category, responsible appointment, review cadence and retention class come from the element.
- **Industry walkthroughs (17):** the overlay's own additions and the library elements it switches on outside Section F, by element name. **51 element and industry pairs are left out** because they are about medical fitness or surveillance (every Section E element and, for example, "Certificate of fitness system"): Care Net screens fitness and does not diagnose, and no clinical line reaches an inspection. They are listed in the bundle's `excluded`.
- **Place types (18):** the Director's list. Which types an industry is offered follows rules that name only kernel codes (an industry, a subindustry or a trigger), for example a farm for AGRI, a mine or quarry section for MINING or T-MINING, a warehouse for T-STACKING or the warehousing and wholesale subindustries, a workshop for T-MACHINERY, T-HOTWORK or T-MOBILEPLANT, a vehicle or fleet for T-PRDP or T-MOBILEPLANT, a construction project for T-CONSTR. Site, office, branch, department, building or block, floor and room or area are offered to every industry. The allowed children of each type are the same in the bundle and in 065 (tested).
- **Suggested departments:** the File departments the guidance suggests for the elements behind the industry's templates, most frequent first, Health and safety always first.
- **Sample companies:** `vercel/hsf/samples/*.js` (fictitious).

## Not sourced from the kernel (and so not invented)

| Item | What the app does |
| --- | --- |
| Legal inspection intervals | Only the element library's own cadences are shown (daily, monthly, before each use, when anything changes, each time it is used). "Statutory" and "annual" wait for a verified legal interval: **Set by your competent person**. |
| Retention periods | The retention class only (LIFE, INST); the period reads "set by your competent person" or "as the legal instrument sets it, still being confirmed". |
| Headcount bands | The kernel holds none, so a place takes a whole number headcount, as the File's generator does. |
| Place types | The type list is the Director's; the kernel decides which are offered. Hospitality has no industry specific type in the kernel, so it is offered the universal types and a site is suggested. |
| Checklist wording beyond the guidance | None: every line is the guidance or the element name, word for word. |
| Legal bases on walkthrough templates | None shown: "Set by your competent person". |

## Migration 065 (not applied anywhere; 001 to 064 unchanged)

`bi_company.industry_code` and `subindustry_code` (checked together); `bi_place_type` (the 18 types and their allowed children) and `bi_place_type_industry`; `bi_place` with `bi_place_guard` (same company, allowed type, no loops, at most 8 levels, unique sibling names, archived never deleted) and `bi_place_site_sync` (a top level place is also the engine's `bi_site` with the same id); kernel templates on `bi_template` (`industry_code`, `template_kind`, `kernel_version`), `bi_template_item.source_ref` and `bi_template_industry`; `bi_inspection.place_id` and `bi_inspection_area.place_id` (under the site, same company); `bi_evidence_blob` and `bi_evidence_upload_session`; versions, canonical path, place, item, device, tags, retention class, legal hold and sidecar hash on `bi_photo` and `bi_voice_note`, content addressed paths allowed and `bi_evidence_version_guard`; dedupe aware `bi_storage_used_bytes`; `bi_search_doc` with `bi_search`; RLS on every new table in the house style of 059 to 064. The kernel templates themselves are `supabase/seed/bee_inspect_kernel_templates.sql`, written by the bundle script. `test/sql/bi_popia_checks.sql` now counts 62 bi_ tables (7 from 065).

## Checks run and results

| Check | Result |
| --- | --- |
| `npx tsc --noEmit` | clean |
| `npx expo lint` | clean (0 problems) |
| `npm test` (Jest, `*.spec.ts`) | 10 suites, 163 tests, all pass. New: kernel bundle integrity (17 industries against the migrations, pricing codes and samples; 56 subindustries; every checklist line resolves to its source with the same words; intervals and retention never invented; house rules on every visible line; no clinical line; place type rules and 065 agree; every id in the server seed), place tree rules, switcher search and recent places, place types per industry, template filtering by industry and place, the kernel refresh hook, content addressing and dedupe, the demo photo fingerprints, the storage meter, canonical paths, sidecar stability, EXIF and PNG metadata stripping, versions, legal hold, chunk planning, resume and the integrity check, search, the demo data across five industries, the capture pipeline on the store and the simulated upload. |
| `node --test` from msp-forge | 608 tests, 0 failures |
| `bash test/sql/replay.sh` | 001 to 065 replay cleanly |
| `test/sql/*_checks.sql` | all 16 pass; `bi_places_checks.sql` (new) 54 checks |
| `node apps/mobile/scripts/build-kernel-bundle.mjs --check` | the bundle and the seed are current |
| `npx expo config --type prebuild` | resolves; icons, the red splash and `enableFTS` in place |
| `npx expo export --platform web` | builds |
| Chromium walk through (`apps/mobile/scripts/walkthrough-v2.mjs`, 390 x 844, device scale 2) | 29 screenshots, no page errors, no console errors |

## Screenshots

Headless Chromium at 390 x 844, the web export of the demo, 27/09/2026. The web build, not a phone: the native tab bar, camera, haptics and FTS5 look or behave differently on a device.

| Screen | What it shows |
| --- | --- |
| [00-app-icon-set.jpg](00-app-icon-set.jpg) | The icon set from the Director's icon: iOS and store icon, Android adaptive icon (red background, white bee in the safe zone), the themed monochrome icon, the red splash and the favicon. |
| [01-home-construction.jpg](01-home-construction.jpg) | Home for the fictitious construction company: the context bar (company and place, a tap from the switcher), the sync state, one primary action. |
| [02-switcher.jpg](02-switcher.jpg) | The place switcher: one search box, the five demonstration companies in five industries, every place with Start inspection here. |
| [03-switcher-search.jpg](03-switcher-search.jpg) | Instant search: "work" finds workshops across companies, each with its breadcrumb. |
| [04-places-mining.jpg](04-places-mining.jpg) | The quarry's places: a mine or quarry section, a factory or plant, an office, with sections, a haul truck fleet, a workshop and a department. |
| [05-place-detail.jpg](05-place-detail.jpg) | One place: breadcrumb, kind, responsible person, headcount, the places under it, and Start inspection here. |
| [06-place-editor.jpg](06-place-editor.jpg) | Adding under the plant: only the kinds of place mining is offered and the plant allows; details folded until wanted. |
| [07-template-picker-mining.jpg](07-template-picker-mining.jpg) | The template picker at a mining plant: the Mining walkthrough first, then the registers that suit a plant. |
| [08-template-about.jpg](08-template-about.jpg) | All 22 Section F registers available everywhere; the chosen one shows where it files, "Set by your competent person", who usually does it, the legal basis and retention. |
| [09-inspection-mining.jpg](09-inspection-mining.jpg) | The inspection at the plant on the kernel's machine guarding register: the Fail rule met, the areas walked. |
| [10-area-checklist.jpg](10-area-checklist.jpg) | An area: kernel checklist lines with Pass, Fail, N/A, Observe; "Gaps to look for" pass when the gap is not found. |
| [11-item-fail-photo.jpg](11-item-fail-photo.jpg) | A Fail with its sealed photo (drawn demonstration photo) and its voice note. |
| [12-evidence-library.jpg](12-evidence-library.jpg) | The evidence library: storage against 10 GB, search, the filter rail, grouped by place. |
| [13-evidence-filtered.jpg](13-evidence-filtered.jpg) | Extreme risk across all companies, verified on the server after upload. |
| [14-evidence-search.jpg](14-evidence-search.jpg) | Search ("racking") grouped by inspection. |
| [15-evidence-detail.jpg](15-evidence-detail.jpg) | One photo and its sealed sidecar: time, GPS, inspector, device, inspection, checklist line, SHA 256, seal. |
| [16-evidence-storage.jpg](16-evidence-storage.jpg) | Where it is kept: canonical path, content address, shared bytes, derived copies, retention, legal hold, verified upload. |
| [17-evidence-version.jpg](17-evidence-version.jpg) | A caption correction saved as version 2 on the same bytes; version 1 unchanged. |
| [18-a-company.jpg](18-a-company.jpg) | Registration step 1 for a mining company: industry and subindustry from the kernel, the 16(1), 16(2) and POPIA contacts. |
| [18-b-places.jpg](18-b-places.jpg) | Step 2 for mining: a mine or quarry section, a factory or plant, a workshop, a vehicle or fleet, suggested by the kernel. |
| [18-c-tree.jpg](18-c-tree.jpg) | The mining tree after one tap each, with the File departments under the mine section. |
| [18-d-people.jpg](18-d-people.jpg) | Step 3: authorised persons, inspectors and assistants. |
| [18-e-done.jpg](18-e-done.jpg) | Done: onboarding in review, Start inspection opens once Active. |
| [19-a-company.jpg](19-a-company.jpg) | Registration for a healthcare company: clinics and practices. |
| [19-b-places.jpg](19-b-places.jpg) | Healthcare places: a clinic or laboratory. |
| [19-c-tree.jpg](19-c-tree.jpg) | The healthcare tree with its departments. |
| [20-a-company.jpg](20-a-company.jpg) | Registration for an agriculture company: crop farming. |
| [20-b-places.jpg](20-b-places.jpg) | Agriculture places: a farm first, then a factory or plant, a warehouse, a workshop, a vehicle or fleet. |
| [20-c-tree.jpg](20-c-tree.jpg) | The agriculture tree with its departments. |
| [21-home-after.jpg](21-home-after.jpg) | Home after registering: the new company active (in review, so Start inspection waits), recent places a tap away. |

Repeat from `apps/mobile`: `npx expo export --platform web`, `npx expo serve --port 8087`, then `node scripts/walkthrough-v2.mjs http://localhost:8087`.

## Stubs and open items

| Item | Now | Next |
| --- | --- | --- |
| `evidence-upload-session`, `evidence-upload-chunk`, `evidence-upload-complete` | Live mode parks uploads on the phone; demo mode simulates the three steps and the hash check | Edge Functions on the staging backend, writing `bi_evidence_blob` and `bi_evidence_upload_session` |
| `account-update` (company registration, industry, authorised persons, inspectors and assistants) | Saved on the phone and queued; parked until the function exists (as in P4) | The Edge Function; onboarding status stays Care Net's decision |
| Kernel service | `refreshKernel` refuses to change anything without a fetcher; the bundled kernel 1.1.0 is used | The kernel API (KERNEL-API.md) returning the same bundle schema |
| Secure share link | A placeholder; nothing is shared | Signed links with expiry to the web copy, audited |
| Legal hold and retention runs | Respected on the phone; set and run only on the server | Retention periods once decided (HSF-5); the admin's hold control on the web desk |
| FTS5 on a device | Built for (enableFTS, `search_fts`); the web preview uses the in memory index | Check on a development build |
| Derived copies on a device | `expo-image-manipulator` (in Expo Go for SDK 57); if it fails the original is kept and copies are made later | Check on a device |
| App icon name | The master SVG is labelled "Bee Inspected" (aria label) while the app is Bee-Inspect; not renamed. Its letters "BI" use a system font, so renders can differ slightly; converting that text to outlines in the master would fix it. | The Director's choice |
| Migration 065 and the kernel seed | Replayed locally only | Apply with 059 to 064 on a staging project, on the Director's confirmation (decision 1.6) |
