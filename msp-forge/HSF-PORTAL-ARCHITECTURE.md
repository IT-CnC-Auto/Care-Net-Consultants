# CNC HSF FORGE: portal architecture, document lifecycle and POPIA analysis

Document reference: CNC-HSF-PORTAL-ARCH-V1.0-2026 | Version 1.0 | Date of issue: 23/09/2026 | Classification: INTERNAL
Owner: Care Net Consultants (Pty) Ltd, for the Director
Binding sources: hsf/BUILD-CONTRACT.md (wins for what it names), SPEC.md Part B (wins for everything else), SPEC.md Part A section 8, the CNC OHS Industry Kernel of 23/09/2026 (kernel/cnc-ohs-industry-kernel/, SANDBOX)
Companion: KERNEL-API.md (the kernel API and the Grok connection pack)

## 1. Purpose and status

1.1 This document sets out the target architecture for CNC HSF FORGE when it is hosted inside MyClinicOnline (MCO): one login portal that joins the commercial spine (Medical Surveillance Plans, Health and Safety Files, quotations, sign off) and the medical spine (MCO records), the life of a document from consent to deletion from Care Net staging, a plain words POPIA analysis, the hosting options, the sign in abstraction and the open items.

1.2 It describes the design. It is not a legal opinion and it does not claim that the platform meets POPIA or any other law. Where a question needs the Information Officer or an attorney, section 5.10 says so.

1.3 Status on 23/09/2026:
1.3.1 In the repository, with unit tests that pass locally under `node --test` (108 tests in `test/api` and `test/mco` on 23/09/2026): the web tier endpoints (`vercel/api/hsf-consent.js`, `hsf-upload.js`, `hsf-file.js`, `kernel.js`), the shared sign in check (`vercel/lib/auth.js`), the portable host (`server/serve.js`) and the transfer worker with its adapter (`supabase/functions/hsf-mco-transfer/`, `supabase/functions/_shared/`). Also in the repository: the builder and portal pages and migrations 047 and 048.
1.3.2 Specified in the contract but not in the repository when this was written: migrations 049 (consent, uploads, transfer), 050 (kernel API) and 051 (generation and the compliance figure).
1.3.3 Nothing has been applied to the live Supabase project and nothing has been deployed.
1.3.4 The MCO interface contract (HSF-3) is not in hand. No MCO endpoint, token format, single sign on method or data centre is known, and none is assumed here. The transfer worker runs in hold mode: nothing leaves Care Net.

1.4 Terms. "Staging" means the private Supabase Storage bucket `hsf-staging`. "Supabase Secrets" in the Director's brief means the secure Supabase environment: documents go to Supabase Storage (private, encrypted at rest, service role access only), never to the Secrets store, which holds credentials only (contract section 1).

## 2. Design principles

2.1 One sign in, two spines. A company contact signs in once and sees both the commercial records Care Net keeps and the medical records MCO keeps, without a second password.

2.2 Care Net holds no clinical detail. The File records that evidence exists, where it lives, who supplied it, its dates and its fingerprint. Certificates of fitness reach the File as outcome, restriction, dates and practitioner identity only (SPEC B10.4). Care Net screens fitness for work and does not diagnose.

2.3 Bytes do not linger. A document passes through Care Net staging on its way to MCO and is deleted from staging once MCO has confirmed it holds an identical copy. The audit trail keeps the fingerprints and the MCO reference, never the bytes.

2.4 Consent before storage. Three separate, unticked consents (wording version `HSF-CONSENT-1.0`) come before the first document is accepted, and withdrawal stops new uploads at once.

2.5 The kernel is the only legal reference. Pages and answers cite an instrument only if it is in `kernel_citable_instrument` (verified three ways, in force, not held). Everything else shows as awaiting verification (contract section 7).

2.6 Portable by construction. Every page reads its settings from `js/cnc-config.js`, every internal address is relative, and every API handler runs unchanged on Vercel or under `server/serve.js`. Moving into MCO is a configuration change, not a rewrite.

2.7 Nothing invented. Unknown values (the Google Tag Manager ID, the MCO portal address, MCO endpoints, the Grok model name) are null or pending, never guessed.

## 3. Target architecture

3.1 Overview. The diagram shows the target state inside MCO. Today the same components run with Vercel in place of the MCO web host, and the medical spine shows "Arrives when MyClinicOnline is connected".

```
                    ┌──────────────────────────────────────────────────────────┐
  Company contact ─▶│  Login portal (portal.html)   one sign in (cnc-auth.js)   │
  Care Net staff  ─▶│  Supabase Auth now · MCO single sign on later (HSF-3)     │
                    └──────────────┬───────────────────────────────┬───────────┘
                                   │                               │
              COMMERCIAL SPINE (Care Net)            MEDICAL SPINE (MyClinicOnline)
   ┌───────────────────────────────▼─────────┐   ┌─────────────────▼──────────────────┐
   │ Company account, approval state         │   │ Certificates of fitness (outcome,  │
   │ Medical Surveillance Plans and status   │   │   restriction, dates, practitioner)│
   │ Health and Safety Files (builder,       │   │ Training records                   │
   │   compliance figure, gap report)        │   │ Bookings                           │
   │ Quotations · sign off and review status │   │ File documents moved from staging  │
   └───────────────┬─────────────────────────┘   └─────────────────▲──────────────────┘
                   │ /api/hsf-* (JWT checked)                      │ transfer worker
   ┌───────────────▼─────────────────────────┐                     │ (hold now; live
   │ Supabase: Postgres (RLS, security        │─────────────────────┘  after HSF-3)
   │ definer functions, msp_audit),           │
   │ Storage hsf-staging (private),           │◀── /api/kernel (key) ◀── Grok bridge
   │ Auth, edge function hsf-mco-transfer     │    public kernel data only
   └──────────────────────────────────────────┘
```

3.2 Components.

| Number | Component | Where | Role |
| --- | --- | --- | --- |
| 1 | Login portal | `vercel/portal.html` | One sign in; commercial panels from Care Net APIs; medical panels pending MCO; staff links by role |
| 2 | Health and Safety File builder | `vercel/hsf-builder.html` | Sign in, consent, File setup, fifteen section cards with drop zones and department selector, upload queue, lifecycle, gap report |
| 3 | Shared front end | `vercel/js/cnc-config.js`, `cnc-tracking.js`, `cnc-auth.js`, `cnc-design-assets.js` | Settings, cookie consent and call to action tracking, sign in abstraction, designer asset overlay |
| 4 | Web tier API | `vercel/api/hsf-consent.js`, `hsf-upload.js`, `hsf-file.js`, `kernel.js`; `vercel/lib/auth.js`, `db.js` | Verifies the user's token, calls service role only database functions, signs upload URLs |
| 5 | Portable host | `server/serve.js` | Serves `vercel/` and mounts every `vercel/api/*.js` at `/api/<name>`; the path into MCO hosting |
| 6 | Database | `supabase/migrations/047` to `051` | Library, engagement, consent, upload, transfer and kernel API tables and functions; RLS on every table |
| 7 | Staging storage | Supabase Storage bucket `hsf-staging` | Private, 25 MB per file, allowed types only, service role access only |
| 8 | Transfer worker | `supabase/functions/hsf-mco-transfer/index.ts` with `_shared/mco-adapter.js`, `_shared/transfer-core.js` | Hashes, sends to MCO, checks the receipt, deletes from staging |
| 9 | Kernel API | `vercel/api/kernel.js`, `vercel/kernel-api/openapi.yaml` | Read only framework data for approved servers, including the Grok bot |
| 10 | Grok connection pack | `grok/` | Function tools, system prompt and bridge example (KERNEL-API.md) |

3.3 The commercial spine (Care Net).
3.3.1 Company account: `msp_client_account`, joined to the signed in person through `auth_user_id`.
3.3.2 Medical Surveillance Plans: the existing MSP FORGE journey (assessment, OMP review, release). The portal links to it; a read only Plan status endpoint is pending.
3.3.3 Health and Safety Files: `hsf_file` and `hsf_file_item`, the compliance figure (SPEC B9.4), the gap report (SPEC B9.5), and the review and release gate (SPEC B11), which needs the OMP for Section E, the safety content signatory (HSF-1) and the client's section 16(2) acceptance.
3.3.4 Quotations: the existing quotation tables of Part A; a read endpoint for the portal is pending.

3.4 The medical spine (MCO).
3.4.1 Certificates of fitness, training records and bookings, read from MCO through the adapter interface of SPEC B10 once HSF-3 closes. People are matched on MCO's own person reference, never on name (SPEC B10.3).
3.4.2 The documents companies drop into their File end up here, in MCO's secure environment for special personal information, after the transfer in section 4.
3.4.3 Until HSF-3 closes the portal shows each medical panel as "Arrives when MyClinicOnline is connected" and invents nothing. A clearly labelled demonstration uses the sample fixture only when the address carries `?demo=1`.

3.5 Staff. Forge roles in the token's `app_metadata.msp_roles` (forge_admin, forge_omp, forge_safety_reviewer and the others) show links to `review.html` and `settings.html`; each staff page checks the role again, and the database checks it a third time.

3.6 Tracking and calls to action.
3.6.1 `cnc-tracking.js` sets Google consent mode to denied by default, shares the consent choice under the storage key `cnc_consent_v1`, and loads Google Tag Manager only when an ID is configured and the visitor has accepted. The ID is not known and stays null (pending), so no tag loads today.
3.6.2 Every call to action carries `data-cta`; a click pushes `{event: 'cnc_cta_click', cta, page}` and nothing personal. The four shared calls to action are "Build my File", "Build my Plan", "WhatsApp a sales executive" (https://wa.me/27600702723) and "Sign in" (`/portal.html`).

## 4. Document lifecycle

4.1 Before the first upload.
4.1.1 The company contact signs in and has an approved company account.
4.1.2 The contact gives three consents, each ticked separately and shown in full with the wording version `HSF-CONSENT-1.0`: document storage (in Care Net's private Supabase staging area, for the single purpose of building the File), MCO transfer (then deletion of the staging copy, with name, size, department and fingerprint kept as the audit trail), and authority to share (the contact is authorised by the employer and understands that health information is special personal information). Each is a row in `hsf_consent` with the time and the wording version; `hsf_consent_status` reports `complete` only when all three latest rows are granted and not withdrawn.
4.1.3 The File skeleton exists (`hsf_generate_file`). Generating it needs no consent, because it holds no documents.

4.2 The life of one document, step by step.
4.2.1 Choose. The contact drops a file on a section card or an element row and chooses the department (Executive and legal, Human resources, Health and safety, Operations, Engineering and maintenance, Procurement and contractors, Occupational health and medical, Training and development, Facilities and security). The browser rejects a wrong type or a file over 25 MB with a plain message before anything is sent; the server checks again against `hsf.upload_allowed_mime` and `hsf.upload_max_bytes`.
4.2.2 Fingerprint in the browser. The browser works out the file's SHA 256 with `crypto.subtle` before the file leaves the device. The queue shows it.
4.2.3 Register. `POST /api/hsf-upload {action: 'register', ...}` verifies the user's token, then `hsf_register_upload` refuses unless consent is complete, the account is not declined, the type and size pass, the department exists and the File (if named) belongs to the account. It builds a safe file name and the staging path `<client_account_id>/<upload_id>/<safe_file_name>`, records the client fingerprint, sets status `awaiting_upload` and audits.
4.2.4 Signed upload address. The server asks Supabase Storage for a one off signed upload address for that path and returns it. The service role key never leaves the server; the address carries its own short lived token.
4.2.5 Upload. The browser sends the bytes straight to Supabase Storage with `PUT`. The bytes never pass through the Vercel functions. Screen label: Uploading.
4.2.6 Complete. `POST /api/hsf-upload {action: 'complete'}` checks that the object is in the bucket at the registered size, then `hsf_mark_uploaded` moves the upload to `uploaded`, creates the `hsf_evidence` row (next version, source `client_upload`, SHA 256 from the client) and marks the File item `uploaded`. Screen label: Uploaded.
4.2.7 Fingerprint on the server. The transfer worker (the edge function `hsf-mco-transfer`, run on a schedule or by hand, service role only) reads the mode from `hsf.mco_transfer_mode`, takes up to ten uploads in status `uploaded` or `held`, oldest first, downloads each and works out the server SHA 256. If it differs from the client fingerprint, the worker records `hash_mismatch`, the upload goes to `failed` with a reason, and nothing is sent or deleted.
4.2.8 Hold (today). In hold mode the adapter sends nothing. The worker records the outcome `held` and the upload stays in staging with status `held`. Screen label: Held for MyClinicOnline. The parameter `hsf.staging_alert_days` (14) is the age at which a held document should be flagged.
4.2.9 Transfer (after HSF-3). In live mode the adapter sends the file, its fingerprint and its filing details to MCO, and MCO answers with its document reference and the fingerprint of what it received. `hsf_transfer_record` appends a row to `hsf_mco_transfer` (append only) and, when the outcome is `received` and the server, client and receipt fingerprints are all equal, moves the upload to `transferred` with the MCO reference and time, and writes the MCO reference to the matching evidence row. Screen label: Transferred to MyClinicOnline.
4.2.10 Receipt check fails. A receipt fingerprint that differs moves the upload to `failed`; an error leaves it `uploaded` or `held` for the next run. Neither deletes anything.
4.2.11 Staging deletion. Only for an upload in `transferred` with three equal fingerprints, the worker deletes the object through the Storage API and, after Storage confirms, calls `hsf_mark_staging_deleted`, which sets status `staging_deleted`, clears `storage_path` and records `staging_deleted_at`. Screen label: Removed from Care Net staging.
4.2.12 What remains with Care Net. The `hsf_upload` row (original and safe name, type, size, department, section, both fingerprints, statuses and times, MCO reference), the `hsf_mco_transfer` rows, the `hsf_evidence` row (append only; storage path cleared, MCO reference set) and the `msp_audit` events. Never the bytes.

4.3 States and screen labels.

| Number | `hsf_upload.status` | Meaning | Screen label |
| --- | --- | --- | --- |
| 1 | `awaiting_upload` | Registered; bytes not yet in staging | Uploading |
| 2 | `uploaded` | Bytes in staging at the registered size | Uploaded |
| 3 | `verified` | Reserved in the contract's status list; not set by any step above | Not shown |
| 4 | `held` | Worker ran in hold mode; bytes still in staging | Held for MyClinicOnline |
| 5 | `transferring` | Reserved in the contract's status list; not set by any step above | Not shown |
| 6 | `transferred` | MCO holds an identical copy; staging copy about to be deleted | Transferred to MyClinicOnline |
| 7 | `staging_deleted` | Staging copy deleted; row and fingerprints kept | Removed from Care Net staging |
| 8 | `rejected` | Refused (reason recorded) | Plain message |
| 9 | `failed` | Fingerprint mismatch; nothing deleted; needs a person | Plain message and sales executive route |

4.4 Rules the lifecycle never breaks.
4.4.1 Nothing is deleted on `held`, on an error or on a mismatch.
4.4.2 The staging copy is deleted only after MCO has confirmed an identical copy and the database has recorded the transfer.
4.4.3 `hsf_evidence` and `hsf_mco_transfer` are append only. The evidence trigger allows only the one way updates the contract names (revocation once; MCO reference and transfer time once; staging deletion once together with clearing the path). A replacement document is a new version.
4.4.4 The audit keeps fingerprints and the MCO reference, never file contents.
4.4.5 Fixture mode, which pretends MCO received a file, is for tests only and is refused unless the function environment explicitly allows it; it must never be allowed on the production project.

## 5. POPIA analysis in plain words

5.1 Standing of this section. This is the build team's reading, written so the Information Officer and an attorney can check it quickly. It is not legal advice and it claims nothing about meeting POPIA. The Protection of Personal Information Act, 2013 (POPIA) is in verification batch HSF-VER-01 and has not yet passed the kernel's three checks, so this section describes its duties in words and cites no section numbers.

5.2 What personal information the platform touches.

| Number | Information | Whose | Where it lives | Notes |
| --- | --- | --- | --- | --- |
| 1 | Sign in email address and account details | Company contact | Supabase Auth and `msp_client_account` | Needed to sign in and to know which company the person acts for |
| 2 | Consent records | Company contact | `hsf_consent` | Kind, granted or withdrawn, wording version, times |
| 3 | Uploaded documents | Employees, contractors, appointees, the company | Staging, then MCO | May hold names, identity numbers, appointments, training records and health information. Care Net cannot tell what a document holds without opening it, so every upload is treated as possibly special personal information |
| 4 | Upload metadata | As item 3 | `hsf_upload`, `hsf_evidence`, `msp_audit` | Original file name, size, department, fingerprints, MCO reference. A file name can itself carry a person's name (section 5.10, item 7) |
| 5 | Question text sent to the Grok bot | Whoever asks | The bot host and xAI | The bot is meant for framework questions only; the bridge refuses questions carrying identity numbers, email addresses or telephone numbers before anything reaches xAI |
| 6 | Cookie choice and anonymous click events | Site visitor | The visitor's browser; Google Tag Manager only after acceptance and only once an ID exists | No personal information is pushed with a click event |

5.3 Special personal information. Health information about a person is special personal information under POPIA, and the Act prohibits processing it unless one of the authorisations the Act sets out applies, for example the person's consent or a specific authorisation for particular kinds of body or purpose. Two points follow:
5.3.1 The people the health information is about are the employees, not the company. The three consents are given by the company contact for the company. The third consent confirms the contact's authority to share and acknowledges that health information is special personal information, but it is not the employee's own consent.
5.3.2 Whether the employer's own authority to hold its employees' occupational health records, together with the Act's authorisations, covers sharing those records with Care Net and MCO for the File, or whether employee consent or another basis is needed, is a question for the attorney (section 5.10, item 1). Until it is answered, the safer course is to guide companies to upload outcomes and administrative records (appointments, certificates of fitness showing fit, fit with a restriction or not fit, training certificates) rather than clinical records, in line with SPEC Part A 8.2 and B10.4.

5.4 Purpose limitation.
5.4.1 One purpose: building and keeping the company's Health and Safety File, and moving its documents to MCO where they are kept. The consent wording says so.
5.4.2 Documents and their metadata are not used for marketing, not used to train any model, and not sent to xAI or any other AI provider.
5.4.3 The kernel API carries no client data at all (KERNEL-API.md section 3), so the Grok bot cannot reach client data through it.
5.4.4 Further use for another purpose would need its own lawful basis and, where consent is the basis, its own consent (as the default off marketing consent of Part A 8.1).

5.5 Who is responsible and who are the operators.
5.5.1 The employer is the responsible party for its employees' records. Whether Care Net acts as an operator for the employer when it stores and moves documents on the employer's instruction, or as a responsible party in its own right because it decides how the File platform works, affects the contracts needed and is for the attorney (section 5.10, item 2).
5.5.2 The operators that process personal information for Care Net in this design:

| Number | Operator | What it processes | Notes |
| --- | --- | --- | --- |
| 1 | Supabase | Sign in, database rows, staging bytes, the transfer worker | Private bucket, service role access only, encrypted at rest; project region to be confirmed from the Supabase dashboard |
| 2 | Vercel | The web tier: tokens, metadata and requests in transit | Upload bytes do not pass through Vercel functions; region to be confirmed |
| 3 | MCO | Documents after transfer; certificates, training records and bookings | Its role (operator for Care Net or the employer, or responsible party in its own right), location and safeguards depend on HSF-3 |
| 4 | xAI | Question text sent to the Grok bot and the public kernel data returned by tools | Only for public kernel data; never client data. xAI's security FAQ states a default 30 day retention of API requests for abuse monitoring and zero data retention for enterprise accounts (KERNEL-API.md section 7.2, finding 7) |

5.5.3 The Part A register of operators (DocuSeal, Vercel, Supabase, Anthropic) stays in force for MSP FORGE. Each operator needs a written agreement that binds it to confidentiality and security safeguards; the status of those agreements is register item CR-12.5, open, and now extends to MCO and xAI.

5.6 Security safeguards in the design.
5.6.1 Row level security on every table; anonymous and public access revoked; every write through security definer functions called only by the server after it has verified the user's token.
5.6.2 Staging is private with no storage policy for anonymous or signed in users; only the service role reads or deletes. Uploads use one off signed addresses with a short lived token. Everything travels over HTTPS.
5.6.3 Fingerprints taken in the browser, on the server and by MCO on receipt detect any change or corruption on the way. They show integrity, not confidentiality.
5.6.4 Append only audit (`msp_audit`), evidence and transfer tables.
5.6.5 No secret in any file or page; server secrets live only in the host's environment. The kernel API stores only the SHA 256 of each key.
5.6.6 Not yet built: malware scanning of staged files, and an alert for documents held in staging longer than `hsf.staging_alert_days` (section 8).

5.7 Transfers outside South Africa. POPIA limits sending personal information to a third party in another country unless conditions in the Act are met (for example laws or binding rules that give adequate protection, a contract, or the person's consent). The Part A privacy policy approach discloses cross border transfers (SPEC Part A 8.3). For this design:
5.7.1 The Supabase project region and the Vercel function region must be confirmed and recorded.
5.7.2 xAI is a United States company; where it processes API requests must be confirmed from its terms. Only question text and public kernel data should reach it.
5.7.3 MCO's hosting location is unknown until HSF-3.
5.7.4 The privacy policy at https://www.carenetconsultants.co.za/privacy-policy must name each of these and the basis relied on, as the attorney advises.

5.8 Retention.
5.8.1 Staging: only until the transfer is confirmed, then deleted automatically. While the worker runs in hold mode (until HSF-3 closes) documents stay in staging with no end date. The Director must decide whether uploads open before live transfer, and if so the longest a document may stay in staging and what happens then (section 8, item 4).
5.8.2 Metadata, fingerprints and audit: kept with the File as its evidence trail. Retention per record class is open (HSF-5, CR-12.4). Occupational health records carry long statutory retention and never default to short cycles (SPEC Part A 8.4); the house floor for medical surveillance records of hazardous exposure is 40 years where an instrument sets none (SPEC B5.3, RULE-RETAIN), and the kernel pack plans 40 years for files triggered by the noise and physical agents regulations (kernel pack 05, section 4).
5.8.3 Documents in MCO: MCO's retention, set under the MCO contract.
5.8.4 The kernel API call log and the Grok bot host's own logs: no retention period is set yet (section 8, item 12).

5.9 Rights of the people the information is about.
5.9.1 Access, correction, deletion and objection requests from employees go first to the employer as responsible party; Care Net and MCO help as the contracts provide. The Part A engagement export, correction and deletion workflows (SPEC Part A 8.4) extend to File data.
5.9.2 Deletion meets retention: the staging copy is deleted automatically, but the audit trail and statutory records may have to be kept. How a deletion request is answered when a record must be kept needs a written rule (section 5.10, item 5).
5.9.3 Withdrawal of consent stops new uploads at once. Whether a withdrawal of the MCO transfer consent should also stop documents already in staging from moving, and what happens to them, is not yet specified (section 8, item 5).
5.9.4 The Information Officer must be named in the privacy notice and in every pack's POPIA block (CR-12.6, open).

5.10 What still needs the Information Officer and the attorney.

| Number | Question | Who |
| --- | --- | --- |
| 1 | The lawful basis for employee health information in uploaded documents, and whether employee consent is needed in addition to the company's three consents | Attorney, Information Officer |
| 2 | Care Net's role (operator for the employer, or responsible party) and the contracts that follow, with clients, MCO and xAI | Attorney |
| 3 | Review of the consent wording `HSF-CONSENT-1.0` before the first real upload | Attorney, Information Officer, Director |
| 4 | Cross border basis and privacy policy wording for Supabase, Vercel, xAI and MCO | Attorney, Information Officer |
| 5 | Retention per record class and the rule for deletion requests where records must be kept (HSF-5, CR-12.4) | OMP, Director, attorney |
| 6 | A personal information impact assessment for the File platform, and the security compromise notification procedure for staging and MCO | Information Officer |
| 7 | Whether original file names (which can carry a person's name) should stay in the audit trail after transfer, and whether the safe file name should stay in the staging path and signed address | Information Officer, Director |
| 8 | xAI's retention setting for the Grok bot account and whether zero data retention is required | Information Officer, Director |

## 6. Hosting options

6.1 Now: Vercel. The static pages and the `vercel/api` functions run on the Vercel project; Supabase provides the database, sign in, staging storage and the transfer worker. Server secrets (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) live in the Vercel environment only.

6.2 Later: `server/serve.js` on MCO infrastructure. The dependency free Node server serves `vercel/` with the same clean addresses, redirects and headers as `vercel.json`, and mounts every `vercel/api/*.js` handler at `/api/<name>` with the request helpers the handlers expect. Run it with Node 18 or later behind MCO's reverse proxy, which terminates TLS: `node server/serve.js --port 3000` (or `PORT` and `HOST=0.0.0.0` in a container).

6.3 Comparison.

| Number | Concern | Vercel now | `server/serve.js` in MCO later |
| --- | --- | --- | --- |
| 1 | Where pages and API run | Vercel | MCO servers or containers |
| 2 | Secrets | Vercel environment | MCO's secret store, injected as environment variables |
| 3 | TLS and domain | Vercel | MCO reverse proxy; domain pending |
| 4 | Scaling | Automatic | Run more than one instance behind the proxy; the server keeps no state of its own |
| 5 | Logs | Vercel logs | One line per request (time, method, path without the query, status, duration) |
| 6 | Database, sign in, staging | Supabase | Supabase (unchanged) until a later decision moves any of it |
| 7 | Transfer worker | Supabase edge function | Stays in Supabase, or runs beside the server: the adapter and core are plain ES modules |

6.4 What changes on the move.
6.4.1 `js/cnc-config.js` (or `window.CNC_CONFIG_OVERRIDES` set by the MCO shell): `authProvider`, `mcoPortalUrl` and, if the API sits on another origin, `apiBase`.
6.4.2 The Supabase Auth site address and redirect allow list gain the MCO addresses, so sign in links return to the right place.
6.4.3 Browser storage is kept per origin, so a visitor's cookie choice and any stored session on the Vercel address do not carry to the MCO address; visitors choose again once.
6.4.4 The kernel API base address given to the Grok bot (`CNC_KERNEL_API_BASE`) changes, and the bot host's secret is updated.
6.4.5 DNS, and the redirect from the old addresses, are set when the MCO domain is known.

## 7. Sign in abstraction

7.1 Now: Supabase Auth. `js/cnc-auth.js` offers `init`, `signInWithEmail`, `session`, `accessToken`, `onChange` and `signOut`. With the provider `supabase` it signs people in with an email one time link, exactly as the landing page does, so one session serves every page. Each API call carries the access token; `vercel/lib/auth.js` asks Supabase Auth whose token it is and passes only the verified user id to the database, which finds the company through `msp_client_account.auth_user_id`.

7.2 Later: MCO single sign on (pending HSF-3). The provider `mco_sso` exists as a stub that refuses with "MCO single sign on is pending the MCO interface contract (HSF-3)". Nothing is guessed about how MCO signs people in. When the contract arrives, one of three shapes will be chosen:
7.2.1 MCO as an identity provider federated into Supabase Auth, if MCO supports a standard protocol Supabase accepts. The database keeps its user ids and nothing below the sign in changes. Preferred where possible.
7.2.2 The web tier validates MCO's own tokens (a second branch in `requireUser`) and maps each MCO user to a Care Net user id and company account through a mapping table.
7.2.3 A token exchange, in which a verified MCO sign in is exchanged for a Care Net session.

7.3 Whatever the shape, staff roles stay Care Net's: the forge roles in `app_metadata.msp_roles` are granted by Care Net, never inferred from an MCO claim unless the Director agrees otherwise, and the database keeps checking them.

7.4 The medical spine's data reaches the portal only through the server side adapter (SPEC B10), with the employer's view limited to outcome, restriction, dates and practitioner identity. The browser never calls MCO with a Care Net secret.

## 8. Open items

| Number | Item | Owner | Status |
| --- | --- | --- | --- |
| 1 | MCO interface contract: transfer endpoint, receipt, person identifier, single sign on, hosting location, portal address (HSF-3, CR-13.12) | Director, MCO owner | Open; blocks live transfer, the medical spine and single sign on |
| 2 | Migrations 049, 050 and 051 written, replayed with `test/sql/replay.sh` and reviewed; nothing applied to the live project until the Director approves | Build, Director | Pending |
| 3 | HSF-7: live kernel on release 1.0.0 with repealed instruments still marked verified; apply 042 or a reviewed successor | Director, OMP | Open, blocking Phase 2 |
| 4 | Whether uploads open while the worker is in hold mode, the longest stay in staging, and what happens after it | Director, Information Officer | Open |
| 5 | Worker behaviour when the MCO transfer consent is withdrawn for documents already in staging; the contract is silent and the worker does not check consent today | Director, Build | Open |
| 6 | Alert for documents held longer than `hsf.staging_alert_days` (14): the parameter exists, nothing reads it yet | Build | Open |
| 7 | Malware scanning of staged files before transfer | Director, Build | Open |
| 8 | POPIA questions in section 5.10 | Information Officer, attorney | Open |
| 9 | Operator agreements for Supabase, Vercel, MCO and xAI (CR-12.5 extended) | Director | Open |
| 10 | Information Officer named in the privacy notice and POPIA blocks (CR-12.6) | Director | Open |
| 11 | Supabase project region and Vercel function region confirmed and recorded for the cross border note | Build | Open |
| 12 | Retention for the kernel API call log and the Grok bot host's logs | Information Officer | Open |
| 13 | Google Tag Manager container ID (null until confirmed; tracking stays off) | Director | Pending |
| 14 | Read only endpoints for Plan status and quotations in the portal, and a read only account endpoint in place of company-lookup | Build | Open |
| 15 | Safety content signatory for File sign off (HSF-1) and the sign off templates TPL-SGN-02 and TPL-HSF-01 | Director | Partly resolved |
| 16 | Production host for the Forge API and portal (Vercel address now, MCO domain later) | Director | Pending |
