# Bee-Inspect evidence storage: design

27/09/2026. How Bee-Inspect keeps inspection photos, voice notes and their records: the most advanced way we could build it, kept simple for the person on site. The phone code is `apps/mobile/src/lib/evidence-store.ts`, `upload-plan.ts`, `search-index.ts` and `src/features/capture.ts`; the server side is migration `supabase/migrations/065_bi_places_evidence.sql` (not applied anywhere). Proved by `apps/mobile/src/lib/__tests__/evidence-store.spec.ts`, `src/data/__tests__/places-evidence.spec.ts` and `test/sql/bi_places_checks.sql`.

What a person sees: take a photo or record a voice note; it is saved on the phone at once, works without signal, shows its sealed details, and appears in the Evidence library under its place, inspection and date. Everything below happens without them having to think about it.

## 1. Identity: content addressing

| Rule | How |
| --- | --- |
| The SHA 256 of the bytes is the identity of a file | Computed on the phone the moment it is captured (`expo-crypto`), before anything else. |
| The same bytes are stored once | On the phone the file lives at `documents/cas/<ab>/<cd>/<sha256>.<ext>`; a second capture of identical bytes reuses it and the blob record gains a reference (`addBlobRef`). On the server a blob is one `bi_evidence_blob` row per company and hash, stored at `<company>/cas/sha256/<ab>/<cd>/<sha256>` in the private `bi-evidence` bucket. |
| Never across companies | Deduplication is per company (`blobId(company, sha256)`), so no tenant can learn what another holds. |
| Storage counts each blob once | The phone's meter (`usedBytes`) and the server's `bi_storage_used_bytes` (065) count distinct blobs plus derived copies; versions and repeats cost nothing extra. |

## 2. Paths people browse: the canonical path

`tenant/<tenant>/company/<company>/place/<site>/<department>/<room>/inspection/<inspection>/item/<checklist item>/evidence/<evidence id>/v<version>`

The place part is the places tree path in slug form (`slug()` in `src/lib/places.ts`), so a path reads like the site. The path is a name; the hash is the truth. A path is stored on every photo and voice note (`canonical_path`) and parsed back by `parseCanonicalPath`.

## 3. The original and its derived copies

| Copy | What | Where |
| --- | --- | --- |
| Original | The bytes as captured. Never changed, never re encoded. | `cas/...` |
| Thumbnail | 320 pixels wide JPEG for lists | its own blob, `variant = 'thumb'`, `derived_from` the original's hash |
| Web copy | 1 600 pixels wide JPEG for the web desk, reports and shared links | its own blob, `variant = 'web'` |

The derived copies are made with `expo-image-manipulator`; re encoding drops the camera metadata, and each copy is then checked (`jpegHasMetadata`) and stripped again if anything survived (`stripJpegMetadata`, `stripPngMetadata`: EXIF with GPS, the phone's serial and maker notes, XMP, IPTC, comments; the JFIF header and colour profile stay). The server refuses a derived blob that is not marked stripped. **A shared copy is always the web copy.** The sealed GPS stays in the sidecar and the database, where access is controlled.

## 4. The metadata sidecar

Every version has a sidecar (`buildSidecar`), written beside the evidence (`documents/sidecars/<id>.json`) and hashed (`sidecar_sha256`):

`schema, evidence_id, root_evidence_id, version, supersedes_id, kind, sha256, size_bytes, mime_type, cas_key, canonical_path, captured_at (sealed), gps (lat, lng, accuracy), inspector_id, device_id, tenant_id, company_id, place_id, place_path, inspection_id, area_id, finding_id, template_item_id, seal_sha256, caption, tags, retention_class, legal_hold`

It is serialised with sorted keys at every level (`stableJson`), so the same sidecar always gives the same bytes and the same hash. The evidence seal itself is unchanged from P3: `bi_evidence_seal(path, sha256, captured_at, lat, lng, inspector)`, computed on the phone and again by the database.

## 5. Versions: never overwrite

A correction (a caption, markers on a photo, tags) is a **new record**: version n + 1, `supersedes_id` the version it corrects, `root_evidence_id` the first version, the same blob, the same capture time, GPS and inspector, and therefore the same seal (`nextVersion`, `correctPhoto`). The earlier version stays exactly as it was. The canvas, the report and the library show the newest version (`latestVersions`); the evidence screen lists every version (`history`).

On the server (065, `bi_evidence_version_guard`): a client cannot change a caption, markers, tags, path, place or version fields in place; a version must keep the bytes and seal fields, be exactly the next number, point at the root, and a version has at most one successor (a straight chain). A voice note version keeps the first version's VN number. Transcripts were already versioned (P3).

## 6. Retention and legal hold

| | Rule |
| --- | --- |
| Retention class | Each piece of evidence carries the retention class of the Section F element its template files into (`LIFE`, `INST`, or none), from the kernel. **No period is invented:** the app shows "For the life of the File; the period after that is set by your competent person", "As the legal instrument sets it, still being confirmed", or "Set by your competent person". |
| Legal hold | Set only by Care Net or the company admin on the server (a client cannot set or clear it; 065 refuses it). The phone respects it. |
| Cleaning up the phone | A phone copy may be freed only when the server holds the blob **verified** and nothing using it is under legal hold (`canFreeLocalCopy`). Evidence records are never deleted on the phone; the server's delete of photos and voice notes under legal hold was already refused (P3). |

## 7. Upload: queued, chunked, resumable, verified

1. The photo or voice note is queued with the rest of the offline queue (parents first, backoff and jitter, parked while the server function is missing; P4).
2. **Session.** The phone asks `evidence-upload-session` for a session for the hash and size. If the server already holds the hash (another version, another phone), it answers "held" and no bytes move.
3. **Chunks.** The file goes in 5 MiB chunks (`planChunks`), one at a time; after a lost signal it resumes at the first chunk the server has not acknowledged (`remainingChunks`).
4. **Integrity check.** `evidence-upload-complete` assembles and hashes the blob; the phone compares the server's SHA 256 with its own (`verifyUpload`). A match marks the upload verified (and the blob `verified_at`); a mismatch discards the session and starts again. The server keeps the same rule: `bi_evidence_blob.verified_sha256` must equal the key.

**Stub:** `evidence-upload-session`, `evidence-upload-chunk` and `evidence-upload-complete` do not exist yet (the staging backend does not exist). Live mode parks the upload on the phone (404 or 501), demo mode simulates the three steps with the same functions and the same check. The table `bi_evidence_upload_session` (065) holds the server's side of a session.

## 8. Tags and search

- **Tags:** automatic (the kind of place, the Section F element, the finding result, the kind of photo) plus the person's own; lower case, unique, sorted (`normaliseTags`). Changing tags is a new version.
- **Search:** over findings (checklist line and note), transcripts (latest version), evidence metadata (caption, tags, markers, path) and places. On a phone build with FTS5 (expo-sqlite, `enableFTS` in app.json) the documents go into a `search_fts` virtual table ranked by bm25; otherwise, and on the web preview, the in memory index (`src/lib/search-index.ts`) gives the same answers: every word must match the start of a word, titles rank above tags above bodies, plurals fold. On the server, `bi_search_doc` (tsvector with GIN, kept by triggers) and `bi_search(query, company)` answer under RLS; only the newest version of a photo is indexed.

## 9. The storage meter

Prompt B8: 10 GB per company line; warn at 80% and 95%; at 100% new photos and voice notes stop, viewing and sync carry on. The phone shows the meter in the Evidence library and on Account (`storageMeter`) and refuses a capture at 100%; the server's storage gate (P3) does the same with dedupe aware counting (065). Storage packs wait for the rate card.

## 10. The Evidence library

Browse by place, inspection or date; filter by type (photos, voice notes), risk band (Low, Medium, High, Extreme, the locked bands of decision 1.2), age (today, 7 days, 30 days) and company; open a place's evidence from the place screen; search instantly offline. Each item opens the original full size, its sealed sidecar, where it is kept (canonical path, content address, how many uses share the bytes, derived copies, retention, legal hold, upload and integrity state), its tags, its versions, and **Share a secure link**, which is a placeholder until the evidence service exists (nothing is shared; a shared copy would be the web copy without camera metadata).
