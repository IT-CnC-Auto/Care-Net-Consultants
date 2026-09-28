// Evidence file management, as pure functions (docs/bee-inspect/p4/evidence-storage.md).
//
//   Identity   The SHA 256 of the bytes is the blob's identity (content
//              addressing). The same bytes are stored once per company however
//              many findings use them (dedupe); a blob lives at cas/sha256/ab/cd/<hash>.
//   Paths      People browse a structured canonical path:
//              tenant/<t>/company/<c>/place/<site>/<...>/inspection/<i>/item/<k>/evidence/<id>/v<n>
//              which points at a blob; the path is a name, the hash is the truth.
//   Copies     The original is immutable. A thumbnail and a web optimised copy are
//              derived blobs (their own hashes, derived_from the original); shared
//              copies carry no camera metadata (EXIF, XMP, GPS, maker notes).
//   Sidecar    Every version has a metadata sidecar (sealed capture time, GPS,
//              inspector, device, place, inspection, item, hash, size, type),
//              serialised with sorted keys so its own hash is stable.
//   Versions   Nothing is overwritten. A correction (caption, markers, tags) is a
//              new version: a new record pointing at the version it supersedes and
//              at the first version, reusing the same blob.
//   Retention  Legal hold and the retention class are respected: nothing under
//              hold or not yet verified on the server is ever cleaned off the phone.

import type { BlobRecord, EvidenceMeta, Id, UploadState } from './types';

export const SHA256_RE = /^[0-9a-f]{64}$/;

/** Prompt B8: 10 GB of storage per company line. The server counts the same bytes (bi_company_subscription.storage_bytes = 10737418240). */
export const STORAGE_LINE_BYTES = 10737418240;
/** Prompt B8: warn at 80% and 95%; at 100% new photos and voice notes stop (viewing and sync continue). */
export const STORAGE_WARN_AT = [0.8, 0.95] as const;

export function casKey(sha256: string): string {
  if (!SHA256_RE.test(sha256)) throw new RangeError('not a SHA 256');
  return `cas/sha256/${sha256.slice(0, 2)}/${sha256.slice(2, 4)}/${sha256}`;
}

const seg = (s: string) => s.replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 64) || '_';

export interface CanonicalParts {
  tenantId: Id;
  companyId: Id;
  /** Slugs of the place path, root first (src/lib/places.ts slug). */
  placeSlugs: string[];
  inspectionId: Id;
  /** The template item, or the area for an area photo, or "general". */
  itemKey: string;
  evidenceId: Id;
  version: number;
}

export function canonicalPath(p: CanonicalParts): string {
  const places = p.placeSlugs.length ? p.placeSlugs.map(seg).join('/') : '_unplaced';
  return `tenant/${seg(p.tenantId)}/company/${seg(p.companyId)}/place/${places}/inspection/${seg(p.inspectionId)}/item/${seg(p.itemKey)}/evidence/${seg(p.evidenceId)}/v${Math.max(1, Math.trunc(p.version))}`;
}

/** Splits a canonical path back into its parts (null when it is not one). */
export function parseCanonicalPath(path: string): Omit<CanonicalParts, 'placeSlugs'> & { placeSlugs: string[] } | null {
  const m = /^tenant\/([^/]+)\/company\/([^/]+)\/place\/(.+)\/inspection\/([^/]+)\/item\/([^/]+)\/evidence\/([^/]+)\/v(\d+)$/.exec(path);
  if (!m) return null;
  return { tenantId: m[1], companyId: m[2], placeSlugs: m[3] === '_unplaced' ? [] : m[3].split('/'), inspectionId: m[4], itemKey: m[5], evidenceId: m[6], version: Number(m[7]) };
}

// Sidecar ---------------------------------------------------------------------------------

export interface Sidecar {
  schema: 'bee-inspect.evidence.v1';
  evidence_id: Id;
  root_evidence_id: Id;
  version: number;
  supersedes_id: Id | null;
  kind: 'photo' | 'voice_note';
  sha256: string;
  size_bytes: number;
  mime_type: string;
  cas_key: string;
  canonical_path: string | null;
  captured_at: string;
  gps: { lat: number; lng: number; accuracy_m: number | null } | null;
  inspector_id: Id;
  device_id: string | null;
  tenant_id: Id;
  company_id: Id;
  place_id: Id | null;
  place_path: string[];
  inspection_id: Id;
  area_id: Id | null;
  finding_id: Id | null;
  template_item_id: Id | null;
  seal_sha256: string | null;
  caption: string | null;
  tags: string[];
  retention_class: string | null;
  legal_hold: boolean;
}

export function buildSidecar(p: Omit<Sidecar, 'schema' | 'cas_key' | 'tags'> & { tags: readonly string[] }): Sidecar {
  if (!SHA256_RE.test(p.sha256)) throw new RangeError('not a SHA 256');
  return { schema: 'bee-inspect.evidence.v1', ...p, cas_key: casKey(p.sha256), tags: normaliseTags(p.tags) };
}

/** JSON with sorted keys at every level: the same sidecar always gives the same bytes and hash. */
export function stableJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  const o = value as Record<string, unknown>;
  return `{${Object.keys(o)
    .filter((k) => o[k] !== undefined)
    .sort()
    .map((k) => `${JSON.stringify(k)}:${stableJson(o[k])}`)
    .join(',')}}`;
}

// Tags ----------------------------------------------------------------------------------

export function normaliseTags(tags: readonly string[]): string[] {
  return Array.from(new Set(tags.map((t) => t.trim().toLowerCase().replace(/\s+/g, ' ')).filter((t) => t.length > 0 && t.length <= 40))).sort();
}

// Content addressed blobs and dedupe ----------------------------------------------------------

export interface BlobAdd {
  sha256: string;
  size_bytes: number;
  mime_type: string;
  local_uri: string;
  client_account_id: Id;
  variant?: BlobRecord['variant'];
  derived_from?: string | null;
  exif_stripped?: boolean;
}

/**
 * Adds one reference to a blob. Returns the blob to store and whether the bytes
 * were already held (dedupe: the existing blob gains a reference, no new bytes).
 */
export function addBlobRef(existing: BlobRecord | undefined, add: BlobAdd, now: string): { blob: BlobRecord; deduped: boolean } {
  if (!SHA256_RE.test(add.sha256)) throw new RangeError('not a SHA 256');
  if (existing) {
    if (existing.size_bytes !== add.size_bytes) throw new Error('Two files with the same fingerprint and different sizes: the file is damaged.');
    return { blob: { ...existing, refs: existing.refs + 1, updated_at: now }, deduped: true };
  }
  return {
    deduped: false,
    blob: {
      id: blobId(add.client_account_id, add.sha256),
      sha256: add.sha256,
      client_account_id: add.client_account_id,
      size_bytes: add.size_bytes,
      mime_type: add.mime_type,
      local_uri: add.local_uri,
      refs: 1,
      variant: add.variant ?? 'original',
      derived_from: add.derived_from ?? null,
      exif_stripped: add.exif_stripped ?? false,
      uploaded: false,
      verified_at: null,
      created_at: now,
      updated_at: now,
    },
  };
}

/** Blobs are deduplicated per company, never across companies (no inference between tenants). */
export function blobId(companyId: Id, sha256: string): string {
  return `${companyId}:${sha256}`;
}

/** Bytes a company uses: every distinct blob once, originals and derived copies. */
export function usedBytes(blobs: readonly BlobRecord[], companyId: Id): number {
  const seen = new Set<string>();
  let total = 0;
  for (const b of blobs) {
    if (b.client_account_id !== companyId || seen.has(b.sha256) || b.refs <= 0) continue;
    seen.add(b.sha256);
    total += b.size_bytes;
  }
  return total;
}

export type MeterState = 'ok' | 'warn_80' | 'warn_95' | 'full';

export interface StorageMeter {
  usedBytes: number;
  limitBytes: number;
  fraction: number;
  state: MeterState;
  /** False at 100%: new photos and voice notes stop; viewing and sync go on (B8). */
  canCapture: boolean;
  text: string;
}

export function formatBytes(n: number): string {
  const units = ['bytes', 'KB', 'MB', 'GB', 'TB'];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  const s = i === 0 ? String(Math.round(v)) : v.toFixed(v < 10 ? 1 : 0).replace('.', ',');
  return `${s} ${units[i]}`;
}

export function storageMeter(used: number, limit = STORAGE_LINE_BYTES): StorageMeter {
  const fraction = limit > 0 ? used / limit : 1;
  const state: MeterState = fraction >= 1 ? 'full' : fraction >= STORAGE_WARN_AT[1] ? 'warn_95' : fraction >= STORAGE_WARN_AT[0] ? 'warn_80' : 'ok';
  const pct = Math.min(100, Math.floor(fraction * 100));
  const text =
    state === 'full'
      ? `Storage is full (${formatBytes(used)} of ${formatBytes(limit)}). New photos and voice notes stop until space is freed or a storage pack is added; viewing and sync carry on.`
      : `${formatBytes(used)} of ${formatBytes(limit)} used (${pct}%)${state === 'warn_95' ? '. Nearly full.' : state === 'warn_80' ? '. Plan for more space.' : ''}`;
  return { usedBytes: used, limitBytes: limit, fraction, state, canCapture: state !== 'full', text };
}

// Versions ---------------------------------------------------------------------------------

export type Versioned = { id: Id } & Pick<EvidenceMeta, 'evidence_version' | 'root_evidence_id' | 'supersedes_id'>;

export function rootId(e: Versioned): Id {
  return e.root_evidence_id ?? e.id;
}

/**
 * The next version of a piece of evidence: a NEW record (new id) carrying the
 * changes, pointing at the version it supersedes and at the root. The bytes
 * (hash, size, type, capture time, GPS, inspector) never change; a changed file
 * is new evidence, not a version.
 */
export function nextVersion<T extends Versioned & { sha256?: string; audio_sha256?: string; captured_at: string }>(prev: T, changes: Partial<T>, newId: Id): T {
  const frozen = ['sha256', 'audio_sha256', 'size_bytes', 'mime_type', 'captured_at', 'gps_lat', 'gps_lng', 'inspector_user_id', 'id', 'evidence_version', 'root_evidence_id', 'supersedes_id'] as const;
  for (const k of frozen) {
    if (k in changes && (changes as Record<string, unknown>)[k] !== (prev as Record<string, unknown>)[k]) throw new Error(`A correction cannot change ${k}; that would be new evidence.`);
  }
  return { ...prev, ...changes, id: newId, evidence_version: prev.evidence_version + 1, supersedes_id: prev.id, root_evidence_id: rootId(prev), created_at: undefined, updated_at: undefined, row_version: undefined };
}

/** The newest version of every piece of evidence (what the canvas, the report and the library show). */
export function latestVersions<T extends Versioned>(list: readonly T[]): T[] {
  const best = new Map<Id, T>();
  for (const e of list) {
    const r = rootId(e);
    const cur = best.get(r);
    if (!cur || e.evidence_version > cur.evidence_version) best.set(r, e);
  }
  const keep = new Set(Array.from(best.values()).map((e) => e.id));
  return list.filter((e) => keep.has(e.id));
}

/** Every version of one piece of evidence, oldest first. */
export function history<T extends Versioned>(list: readonly T[], anyVersionId: Id): T[] {
  const me = list.find((e) => e.id === anyVersionId);
  if (!me) return [];
  const r = rootId(me);
  return list.filter((e) => rootId(e) === r).sort((a, b) => a.evidence_version - b.evidence_version);
}

/** A version chain is sound when versions run 1..n, each superseding the one before. */
export function chainIsSound<T extends Versioned>(chain: readonly T[]): boolean {
  return chain.every((e, i) => e.evidence_version === i + 1 && (i === 0 ? e.supersedes_id === null : e.supersedes_id === chain[i - 1].id));
}

// Retention and legal hold ----------------------------------------------------------------------

/**
 * Whether the phone may drop its local copy of a blob to save space: only when
 * the server holds it verified (hash checked after upload) and no evidence using
 * it is under legal hold. Evidence records themselves are never deleted on the
 * phone; retention runs on the server once periods are decided.
 */
export function canFreeLocalCopy(blob: Pick<BlobRecord, 'verified_at' | 'uploaded'>, users: readonly Pick<EvidenceMeta, 'legal_hold'>[]): { ok: boolean; reason: string } {
  if (users.some((u) => u.legal_hold)) return { ok: false, reason: 'Under legal hold: kept on this phone.' };
  if (!blob.uploaded || !blob.verified_at) return { ok: false, reason: 'Not yet verified on the server: kept on this phone.' };
  return { ok: true, reason: 'Verified on the server; the phone copy may be freed.' };
}

// Stripping camera metadata from shared copies ----------------------------------------------------

/**
 * A JPEG without its metadata segments: every APPn except APP0 (JFIF) and APP2
 * ICC colour profiles, and every comment (COM), are dropped. EXIF (APP1) holds
 * GPS, the camera, the phone's serial and the time; XMP (APP1) and IPTC (APP13)
 * hold more. The image data is untouched. Returns the input when it is not a JPEG.
 */
export function stripJpegMetadata(bytes: Uint8Array): Uint8Array {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return bytes;
  const out: number[] = [0xff, 0xd8];
  let i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] !== 0xff) break;
    const marker = bytes[i + 1];
    if (marker === 0xda) {
      // Start of scan: the rest is image data up to the end marker.
      for (let j = i; j < bytes.length; j++) out.push(bytes[j]);
      return Uint8Array.from(out);
    }
    if (marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7) || marker === 0x01) {
      out.push(0xff, marker);
      i += 2;
      continue;
    }
    const len = (bytes[i + 2] << 8) | bytes[i + 3];
    const end = i + 2 + len;
    if (len < 2 || end > bytes.length) break;
    const isApp = marker >= 0xe0 && marker <= 0xef;
    const keep = !(isApp && marker !== 0xe0 && marker !== 0xe2) && marker !== 0xfe;
    if (keep) for (let j = i; j < end; j++) out.push(bytes[j]);
    i = end;
  }
  // Truncated or unusual file: keep what was parsed plus the remainder untouched.
  for (let j = i; j < bytes.length; j++) out.push(bytes[j]);
  return Uint8Array.from(out);
}

const PNG_SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const PNG_DROP = new Set(['tEXt', 'zTXt', 'iTXt', 'eXIf', 'tIME']);

/** A PNG without its text, EXIF and time chunks. Returns the input when it is not a PNG. */
export function stripPngMetadata(bytes: Uint8Array): Uint8Array {
  if (bytes.length < 8 || PNG_SIG.some((v, k) => bytes[k] !== v)) return bytes;
  const out: number[] = PNG_SIG.slice();
  let i = 8;
  while (i + 12 <= bytes.length) {
    const len = ((bytes[i] << 24) >>> 0) + (bytes[i + 1] << 16) + (bytes[i + 2] << 8) + bytes[i + 3];
    const type = String.fromCharCode(bytes[i + 4], bytes[i + 5], bytes[i + 6], bytes[i + 7]);
    const end = i + 12 + len;
    if (end > bytes.length) break;
    if (!PNG_DROP.has(type)) for (let j = i; j < end; j++) out.push(bytes[j]);
    i = end;
    if (type === 'IEND') break;
  }
  return Uint8Array.from(out);
}

export function stripMetadata(bytes: Uint8Array, mime: string): Uint8Array {
  if (mime === 'image/jpeg') return stripJpegMetadata(bytes);
  if (mime === 'image/png') return stripPngMetadata(bytes);
  return bytes;
}

/** True when a JPEG still carries an EXIF or XMP segment (used by the tests and the share check). */
export function jpegHasMetadata(bytes: Uint8Array): boolean {
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) return false;
  let i = 2;
  while (i + 4 <= bytes.length && bytes[i] === 0xff) {
    const marker = bytes[i + 1];
    if (marker === 0xda) return false;
    const len = (bytes[i + 2] << 8) | bytes[i + 3];
    if ((marker >= 0xe1 && marker <= 0xef && marker !== 0xe2) || marker === 0xfe) return true;
    i += 2 + len;
  }
  return false;
}

// Upload state (see src/lib/upload-plan.ts for the chunk plan) -------------------------------------

export function uploadDone(u: UploadState | null | undefined): boolean {
  return !!u && u.verified;
}
