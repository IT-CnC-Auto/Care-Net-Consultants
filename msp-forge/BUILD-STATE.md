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

- vercel/health-and-safety-file.html: the Build your File page on the shared shell. The File is free to build for every client; sign off by a registered Health and Safety Manager is priced at the researched market average, and Care Net clients pay 25% less. Amounts are published here by instruction (HSF-2 partly resolved).
- vercel/hsf/pricing.js with hsf/PRICING-RESEARCH.md: market research of 23/09/2026. Only two averages are supported by published prices: a construction File (8 prices, 7 providers, R5 802,50) and a general business File (3 prices, 2 providers, R8 630,00). No provider publishes a price for a single industry outside construction, or a separate sign off price; every industry row says which average applies. The research could read search summaries only, not the pages themselves, so the figures need a manual check before go live.
- vercel/hsf-sample.html with vercel/hsf/samples/*.js: seventeen fictitious sample Files (compliance matrix, training and medical matrix, gap report) generated by hsf/build_samples.py from SPEC.md Part B and kernel role titles.
- Links from index.html and shop.html. The site menu is unchanged: a sixth item does not fit the desktop header.

### CNC OHS Industry Kernel received | 23/09/2026

The Director's OHS Legal Compliance Kernel pack (sandbox until OMP and attorney review) is held verbatim in kernel/cnc-ohs-industry-kernel/ and reconciled against the live kernel in kernel/OHS-KERNEL-RECONCILIATION.md. Industries, role counts (316) and the thirty protocols agree. The pack independently confirms HSF-7: the live kernel still cites the repealed NIHL Regulations, 2003 and Environmental Regulations, 1987. New register items HSF-11 to HSF-16. The sample Files now take their Section E protocols and basis strengths from the pack, and "POPIA compliant" is gone from the site per the pack's rule.
