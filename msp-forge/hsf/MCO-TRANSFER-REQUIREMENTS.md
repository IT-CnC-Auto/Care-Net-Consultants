# HSF document transfer to MyClinicOnline: Care Net's requirements for the MCO team

Document reference: CNC-HSF-MCO-REQ-V1.0-2026 | Version 1.0 | Date of issue: 23/09/2026 | Classification: INTERNAL, shared with the MCO team
Owner: Care Net Consultants (Pty) Ltd, for the Director
Status: **CARE NET'S PROPOSAL, AWAITING MCO'S OWN DESIGN.** Nothing here is an agreed interface. MCO designs and builds the transfer protocol; this document says what Care Net's side already does, what it needs from the protocol, and what it proposes where MCO has not yet decided.
Binding sources: hsf/BUILD-CONTRACT.md section 10.7 (Amendment 2), with sections 5, 9.5, 10.3, 10.4 and 10.5; SPEC.md Part B section B10; HSF-PORTAL-ARCHITECTURE.md sections 4, 5 and 7
Care Net code this describes: `supabase/functions/_shared/mco-adapter.js` (the only file that talks to MCO), `supabase/functions/_shared/transfer-core.js` (the worker), `supabase/functions/hsf-mco-transfer/index.ts` (the scheduled edge function)

## 1. Purpose and status

1.1 The Director has decided that MyClinicOnline (MCO) builds the protocol that moves Health and Safety File documents from Care Net to MCO. Until MCO delivers it, every document stays in Care Net's private Supabase staging bucket (`hsf-staging`) and the worker runs in hold mode: nothing leaves Care Net.

1.2 This document is written for the MCO team as requirements. Where it proposes a shape (a field, an error code, a signing method), that is Care Net's suggestion only. Once MCO publishes its design and both sides agree it, MCO's design wins and Care Net changes its adapter to match.

1.3 No MCO endpoint, host, path, header name, field name, token format or data centre is known to Care Net, and none is named here. Where this document needs to refer to an MCO operation it describes it in words ("the receive operation", "the status operation"). The live request in `mco-adapter.js` is a deliberate placeholder whose path carries the word PLACEHOLDER; it is not a proposal of MCO's address.

1.4 Words used: "must" is a requirement Care Net's safeguards depend on; "should" is strongly preferred; "may" is optional.

1.5 Register references: HSF-3 and CR-13.12 (the MCO interface contract, open), CR-12.5 (operator agreements, open), HSF-5 and CR-12.4 (retention per record class, open).

## 2. What happens before a document reaches MCO

2.1 Every document MCO will receive has already passed these steps on Care Net's side:
2.1.1 The company account is a verified Care Net Consultants client (contract 10.2). The verification records how it was confirmed, one of: the MCO company reference, the Care Net client register, or a sales executive, with an evidence reference.
2.1.2 The company contact has given three separate consents with wording version `HSF-CONSENT-1.0`: document storage, MCO transfer, and authority to share (the contact is authorised by the employer and understands that health information is special personal information).
2.1.3 The browser took the file's SHA 256 fingerprint before upload; the file went straight to private Supabase Storage through a one off signed address; the type and size were checked against the parameters (25 MB at most; PDF, JPEG, PNG, Word, Excel and CSV).
2.1.4 The worker downloaded the stored bytes, took its own SHA 256 and confirmed it equals the browser fingerprint.
2.1.5 The document passed Care Net's security scan (contract 10.4): a structural check (the content matches the declared type; no active content such as PDF JavaScript, launch actions or embedded files; no Office macros, ActiveX or external links; no spreadsheet formula injection; no location metadata in images) and an antivirus engine. Only a document whose scan status is `clean` is ever handed to the adapter.
2.1.6 The upload is not blocked: a consent withdrawal or a revoked client verification sets a block reason, and a blocked upload is never sent.

2.2 The worker runs on a schedule as a Supabase edge function with the service role. Each run claims at most ten documents, oldest first, locks them so that two runs never take the same one, and handles them one at a time, holding one document in memory at a time.

## 3. The send contract: what Care Net's worker sends

3.1 One document per request. The worker calls the adapter's `send` once per document with exactly these values, and the protocol must be able to carry all of them:

| Number | Value (adapter name) | Form | Notes |
| --- | --- | --- | --- |
| 1 | Upload identifier (`uploadId`) | UUID | Care Net's permanent identifier for this document; the idempotency key (section 5) |
| 2 | File bytes (`bytes`) | Raw bytes, at most 26 214 400 | Exactly as stored in staging; never altered, never re encoded |
| 3 | Type (`mimeType`) | A MIME type from the allowed list | application/pdf, image/jpeg, image/png, the Word and Excel types (current and legacy), text/csv |
| 4 | File name (`fileName`) | Letters, digits, dot and underscore, at most 120 characters | The safe name Care Net built; the original name the client chose stays with Care Net |
| 5 | Fingerprint (`sha256`) | 64 lower case hexadecimal characters | SHA 256 of the bytes; the browser, server and receipt fingerprints must all agree |
| 6 | Company (`clientAccountId`) | UUID | Care Net's own company account identifier; see section 6 for matching |
| 7 | Department (`departmentCode`) | One of EXEC, HR, SHE, OPS, ENG, PROC, OH, TRAIN, FAC | The company department the document is filed under |
| 8 | File section (`sectionCode`) | A to O, or empty | The Health and Safety File section; E is medical surveillance and fitness |

3.2 Proposed additions, if MCO wants them (the database already holds each one, so adding them changes only the adapter): the MCO company reference recorded at client verification (section 6.1); the File element code (for example `HSF-E-03`) and the File reference (`CNC-HSF-YYYY-MMDD-NNN`); the time the client completed the upload. Care Net does not send the original file name by default, because a client may have typed personal information into it.

3.3 Transport and size. The request travels over HTTPS only; the adapter refuses any MCO address that is not https. The worker waits up to 60 seconds for an answer. MCO should accept a whole 25 MB document in one request, or say which chunked or resumable method it prefers.

3.4 Direction. The worker calls MCO; MCO does not need to call Care Net. A synchronous receipt (section 4) is preferred. If MCO can only confirm later, it must offer a status operation the worker can ask by upload identifier (section 4.5), and Care Net will keep the document in staging until that operation confirms it.

## 4. The receipt

4.1 On success MCO must answer with:
4.1.1 MCO's document reference: non empty text of at most 200 characters, unique, stable for the life of the document and never reused. Care Net stores it on the upload and on the File evidence row.
4.1.2 The SHA 256 fingerprint of the bytes as MCO stored them, as 64 lower case hexadecimal characters. MCO must compute it over the stored bytes after they are durably written. It must not echo the fingerprint Care Net sent, because the receipt is Care Net's only proof that MCO holds an identical copy.
4.1.3 Should: the time MCO stored the document, in UTC (ISO 8601).

4.2 What Care Net does with the receipt. The staging copy is deleted only when all of the following hold: the adapter outcome is `received`; the server fingerprint equals the browser fingerprint equals the receipt fingerprint; and the database, running the same check in `hsf_transfer_record`, has recorded the upload as `transferred`. Storage must confirm the deletion before the upload is marked `staging_deleted`. The row, the fingerprints, the MCO reference and the transfer log stay with Care Net; the bytes do not.

4.3 Therefore MCO must send a success receipt only after the document is durably stored. A success answer for a document MCO later loses would leave no copy anywhere.

4.4 Anything else is not a receipt. A reply that is not a success, is not readable, lacks the reference or lacks a valid fingerprint is recorded as an error; the document returns to `uploaded`, stays in staging and is claimed again on a later run. A receipt fingerprint that differs is recorded as `hash_mismatch`: the upload fails, its File evidence is revoked, and the client is asked to upload it again.

4.5 Status operation (needed only if MCO confirms asynchronously): given an upload identifier, it answers one of: stored (with the reference and fingerprint of section 4.1), still processing, refused (with an error code from section 7), or unknown.

## 5. Idempotency on the upload identifier

5.1 The same upload identifier can reach MCO more than once: after a time out, after an error answer, and when a worker run stops part way and a later run reclaims the document (after 30 minutes).

5.2 MCO must treat the upload identifier as an idempotency key. A repeat with the same identifier and the same fingerprint must not create a second document; it must answer with the same reference and fingerprint as the first successful receipt.

5.3 A repeat with the same identifier but a different fingerprint must be refused with a distinct error code (section 7, `conflict`), and must never overwrite the stored document.

5.4 MCO should keep the idempotency record for at least as long as it keeps the document.

## 6. Matching companies and people

6.1 Companies. Care Net sends its own company account identifier. MCO must map it to the MCO company, and must refuse a document whose company it cannot match (section 7, `company_not_matched`); it must never match on company name. Care Net proposes that the mapping rests on the MCO company reference: when Care Net verifies a client by MCO company reference, it records that reference, and the adapter can send it with every document (section 3.2). MCO should say whether it prefers to hold the mapping itself or to receive its own reference on each request.

6.2 People. Documents are filed at company level. Care Net does not open documents and does not tell MCO which person a document concerns. If MCO links a document to a person inside MCO, that is MCO's process. Wherever people are matched between the two systems, the match is on MCO's own person reference only, never on name (SPEC B10.3); an MCO person with no Care Net record is offered to the client to confirm, and a Care Net person with no MCO match stays unmatched.

6.3 The reverse direction (outside this transfer, listed so the designs fit together): Care Net's portal will read certificates of fitness, training records and bookings from MCO through the interface in SPEC B10.2 (company, people, medicals, training), matched on MCO's person reference. Clinical detail never crosses to the employer: only outcome, work restriction, dates and practitioner identity (SPEC B10.4).

6.4 Shared sign in (outside this transfer): MCO single sign on is pending HSF-3. HSF-PORTAL-ARCHITECTURE.md section 7.2 lists the three shapes Care Net can work with; MCO as an identity provider federated into Supabase Auth through a standard protocol is preferred. Staff roles stay Care Net's.

## 7. Error codes

7.1 MCO must answer every refusal with a stable, machine readable code and a short plain reason. Neither may contain the file name, file content or any personal information, because Care Net records the reason in its transfer log.

7.2 Care Net proposes these codes; MCO may rename them. Today the adapter treats every refusal as a retryable error, so a permanent refusal would be retried on every run. When MCO's codes are agreed, Care Net will map permanent refusals to a failed upload with a plain reason for the client (this needs a database change on Care Net's side as well as the adapter).

| Number | Proposed code | Meaning | Care Net's proposed handling |
| --- | --- | --- | --- |
| 1 | `unauthorised` | The credential or signature was refused | Stop the run; alert Care Net staff; nothing deleted |
| 2 | `company_not_matched` | MCO cannot match the company | Keep in staging; staff resolve the mapping |
| 3 | `unsupported_type` | MCO does not accept this type | Permanent: the upload fails with a plain reason |
| 4 | `too_large` | Over MCO's size limit | Permanent: the upload fails with a plain reason |
| 5 | `fingerprint_mismatch` | The bytes MCO received do not match the fingerprint sent | Recorded as `hash_mismatch`: the upload fails, evidence revoked |
| 6 | `conflict` | Same upload identifier, different fingerprint (section 5.3) | Keep in staging; staff investigate |
| 7 | `security_refused` | MCO's own scan refused the document | Permanent: the upload is rejected with the reason |
| 8 | `rate_limited` | Too many requests; should carry a retry time | Retry after that time |
| 9 | `unavailable` | MCO is down or busy | Retry on a later run |
| 10 | `invalid_request` | A value is missing or malformed | Keep in staging; staff investigate |

## 8. Deletion at MCO

8.1 Care Net staging. A client may permanently delete their own document while its bytes are still in Care Net staging, through a journey with a warning, an "I understand this cannot be undone" tick and a one time PIN by email or SMS (contract 10.5). Care Net deletes staged bytes only from its own database queues, after Storage confirms.

8.2 After transfer. Once MCO holds a document, deletion is MCO's process, and the builder tells the client so. Care Net requires MCO to provide:
8.2.1 A way to delete a transferred document, identified by MCO reference or upload identifier, on the employer's instruction, with safeguards at least equal to Care Net's (a clear warning that deletion is permanent, an explicit acknowledgement and a second factor such as a one time PIN), whether the client acts in MCO directly or Care Net relays the instruction.
8.2.2 A rule for documents that must be kept by law. Occupational health records carry long statutory retention. When a deletion request meets such a rule, MCO must refuse with a reason rather than delete silently or keep silently.
8.2.3 A way for Care Net to learn that a transferred document was deleted or is no longer held (the status operation of section 4.5, or a notice), so that Care Net can revoke the File evidence and return the File item to outstanding.

8.3 Consent withdrawal. A withdrawal blocks documents still in Care Net staging and deletes nothing automatically. It does not reach documents already in MCO; what happens to those must be set in MCO's design and the MCO contract (HSF-PORTAL-ARCHITECTURE.md section 4.5.6).

## 9. Audit

9.1 Care Net keeps, for every document: the upload row (names, type, size, department, section, both fingerprints, statuses and times, MCO reference, any block reason), an append only transfer log row for every attempt (mode, outcome, MCO reference, receipt fingerprint, short error), the append only File evidence row, and audit events. Never the bytes after transfer.

9.2 MCO must keep, for every receive, status and delete operation: the upload identifier, the MCO reference, the fingerprint, the time (UTC), the credential or certificate used, and the outcome. MCO must make these records available to Care Net on request, for POPIA requests, disputes and incident investigations.

9.3 Both sides record times in UTC and exchange them as ISO 8601.

## 10. Security

10.1 Transport. HTTPS with TLS 1.2 or later, certificate validated; no plain http at any stage.

10.2 Authentication. The adapter today supports a bearer token (`MCO_API_TOKEN`, with the address in `MCO_BASE_URL`), both held only in the Supabase secrets of the edge function. Care Net asks MCO to choose one of these stronger methods in addition to, or instead of, the token:
10.2.1 Signed requests: each request carries a signature (for example HMAC SHA 256) over the method, the path, a timestamp, the upload identifier and the document fingerprint, with a short acceptance window (for example five minutes) and rejection of reused signatures. The worker can do this with the Web Crypto API it already uses.
10.2.2 Mutual TLS: Care Net presents a client certificate that MCO issues or trusts. Care Net must first confirm that the Supabase edge runtime can present a client certificate on an outbound request; until then signed requests are the safer choice.

10.3 Credentials. One credential per environment (test and production), stored only in secret stores, never in files or chat; rotation without downtime (two valid credentials during a change over); immediate revocation; and least privilege: the credential can only use the transfer operations (receive, status and, if agreed, delete) for Care Net's documents, and can read nothing else in MCO.

10.4 Network restrictions. If MCO wants to allow only known source addresses, Care Net must first confirm whether the edge function has stable outbound addresses; an address list must not be the only control.

10.5 MCO's own checks. Care Net scans every document before sending (section 2.1.5). MCO should scan again on receipt under its own policy and refuse with `security_refused` (section 7).

10.6 Errors and logs on either side carry identifiers, codes and short reasons only: never document content, file names chosen by clients, fingerprint pairs in prose, or credentials.

## 11. POPIA and special personal information

11.1 Every document is treated as possibly holding special personal information. Care Net cannot tell what a document holds without opening it, and a File holds certificates of fitness, appointments, training records and incident reports that can name people and describe their health.

11.2 Roles and agreements. Whether MCO acts as an operator for Care Net or for the employer, or as a responsible party in its own right, must be settled by the attorneys before live transfer (HSF-PORTAL-ARCHITECTURE.md section 5.5). A written agreement binding MCO to confidentiality and security safeguards must be signed before the first live document (CR-12.5 extended to MCO).

11.3 Location. MCO must state where the documents are stored and processed. If that is outside South Africa, the transfer must meet the conditions POPIA sets for transfers across borders, and Care Net's privacy notice must say so.

11.4 Safeguards MCO must describe: encryption in transit and at rest; access limited to people who need it, with health information seen only by those entitled to it; access logging (section 9.2); and backups that respect deletion (section 8).

11.5 Security compromises. MCO must tell Care Net without delay of any compromise that affects Care Net documents, with what is known, so that the responsible party can notify the Information Regulator and the people affected as POPIA requires.

11.6 Purpose. MCO uses the documents only to hold the employer's Health and Safety File records and occupational health records, and never for any other purpose such as analytics or model training.

11.7 Employer view. Clinical detail never flows back to the employer through either system: only outcome, work restriction, dates and practitioner identity (SPEC B10.4).

## 12. Retention

12.1 Care Net staging. A document stays in staging until MCO's receipt is confirmed, and then its staging copy is deleted. While the worker is in hold mode, a document may stay at most two years (parameter `hsf.staging_retention_days`, 730 days, contract 10.3), blocked documents included. After that the worker deletes the bytes, the upload becomes `expired` and the File item returns to outstanding. Documents staged long before MCO goes live may therefore expire before they can be transferred; the builder shows each client the date their document is kept until.

12.2 MCO. Retention of transferred documents is set by MCO's design and the MCO contract, per record class (HSF-5, CR-12.4). Occupational health records carry long statutory retention and must never default to short cycles; the house floor for medical surveillance records of hazardous exposure is 40 years where an instrument sets none (SPEC B5.3, RULE-RETAIN). MCO must say how it applies these periods and what happens at the end of each.

## 13. From hold to live

13.1 Care Net switches to live transfer only when all of these are done: MCO's design is published and agreed; Care Net has replaced the placeholder request and receipt reader in `mco-adapter.js` (nothing else in the worker needs to change, because it depends only on the outcome `{outcome, mcoDocumentRef, receiptSha256, error}`); the adapter is tested against an MCO test environment holding no real data; the credentials are in the Supabase secrets; the operator agreement is signed (section 11.2); and the Director approves. A Care Net forge administrator then sets `hsf.mco_transfer_mode` to `live`.

13.2 Backlog. When live transfer starts, every held document becomes eligible at once, ten per run, oldest first. MCO should say how many documents per hour it can accept, so Care Net can set the schedule.

13.3 Test environment. Care Net asks MCO for a test environment with its own credentials, the same protocol and synthetic data only.

## 14. What Care Net asks MCO to answer

| Number | Question | Section |
| --- | --- | --- |
| 1 | The receive operation: address, method, how the bytes and each value of section 3.1 are carried, size limit | 3 |
| 2 | The receipt: fields, when it is sent, and whether confirmation is synchronous or through a status operation | 4 |
| 3 | Idempotency on the upload identifier, and how a conflict is answered | 5 |
| 4 | Company matching: MCO reference on each request, or a mapping MCO holds | 6.1 |
| 5 | Error codes and which are permanent | 7 |
| 6 | Deletion after transfer, the rule for records that must be kept, and how Care Net learns of a deletion | 8 |
| 7 | Audit records MCO keeps and how Care Net obtains them | 9 |
| 8 | Authentication: signed requests or mutual TLS, credential rotation and revocation | 10 |
| 9 | MCO's POPIA role, storage location, safeguards and compromise notice | 11 |
| 10 | Retention per record class | 12 |
| 11 | Throughput for the backlog, and a test environment | 13 |
| 12 | Related, outside the transfer: the read interface of SPEC B10.2, single sign on, and the portal address | 6.3, 6.4 |

## Director's rule on deletion (24/09/2026)

A document on its way to MyClinicOnline, or held there, is never deleted on request. MCO holds each document for the retention period the applicable legislation sets and deletes it only when that period expires, keeping an audit record of the deletion (fingerprint, date, legal basis, never the content). Care Net's client deletion journey applies only while a document is still in Care Net staging and not in transit.
