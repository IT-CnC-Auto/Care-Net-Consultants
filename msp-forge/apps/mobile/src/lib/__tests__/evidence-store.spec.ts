/// <reference types="node" />
// Evidence file management: content addressing (SHA 256 of the bytes), dedupe,
// canonical paths, the metadata sidecar, metadata stripping of shared copies,
// versions, the storage meter, retention and legal hold, the chunked upload
// plan with its integrity check, and full text search.

import { createHash } from 'crypto';
import { readFileSync } from 'fs';
import path from 'path';

import {
  addBlobRef, blobId, buildSidecar, canFreeLocalCopy, canonicalPath, casKey, chainIsSound, formatBytes, history, jpegHasMetadata, latestVersions, nextVersion,
  normaliseTags, parseCanonicalPath, rootId, stableJson, storageMeter, STORAGE_LINE_BYTES, stripJpegMetadata, stripPngMetadata, usedBytes,
} from '../evidence-store';
import { buildIndex, fold, ftsQuery, search, tokenize, type SearchDoc } from '../search-index';
import type { BlobRecord, Photo } from '../types';
import { alreadyHeld, allChunksSent, CHUNK_BYTES, markChunkDone, newUpload, planChunks, progress, remainingChunks, verifyUpload, withSession } from '../upload-plan';

const DEMO = path.resolve(__dirname, '../../../assets/demo');
const sha = (b: Uint8Array) => createHash('sha256').update(b).digest('hex');
const jpeg = readFileSync(path.join(DEMO, 'demo-photo-toe-boards.jpg'));

describe('content addressing and dedupe', () => {
  it('uses the SHA 256 of the bytes as the identity and a sharded address', () => {
    const h = sha(jpeg);
    expect(h).toBe('75dfa0d330f21d3db3fdd0079964d3844adb1f4b5a672892592c831d23d1188f');
    expect(casKey(h)).toBe(`cas/sha256/75/df/${h}`);
    expect(() => casKey('not-a-hash')).toThrow();
  });
  it('the demonstration photos carry the fingerprints the demo seed states', () => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { DEMO_PHOTO_BYTES } = require('../../backend/demo-seed') as typeof import('../../backend/demo-seed');
    for (const f of Object.values(DEMO_PHOTO_BYTES)) {
      const bytes = readFileSync(path.join(DEMO, f.file));
      expect({ file: f.file, sha256: sha(bytes), size: bytes.length }).toEqual(f);
    }
  });
  it('stores the same bytes once per company: a second reference is a dedupe, not a new blob', () => {
    const h = sha(jpeg);
    const add = { sha256: h, size_bytes: jpeg.length, mime_type: 'image/jpeg', local_uri: 'file:///a.jpg', client_account_id: 'co' };
    const first = addBlobRef(undefined, add, 't1');
    expect(first).toMatchObject({ deduped: false, blob: { id: blobId('co', h), refs: 1, variant: 'original', uploaded: false } });
    const second = addBlobRef(first.blob, { ...add, local_uri: 'file:///b.jpg' }, 't2');
    expect(second).toMatchObject({ deduped: true, blob: { refs: 2, local_uri: 'file:///a.jpg' } });
    expect(() => addBlobRef(first.blob, { ...add, size_bytes: 1 }, 't3')).toThrow(/damaged/);
  });
  it('counts used storage once per distinct blob and per company, never across companies', () => {
    const blob = (co: string, h: string, size: number, refs = 1): BlobRecord => ({ id: blobId(co, h), sha256: h, client_account_id: co, size_bytes: size, mime_type: 'image/jpeg', local_uri: '', refs, variant: 'original', derived_from: null, exif_stripped: false, uploaded: false, verified_at: null });
    const list = [blob('a', 'a'.repeat(64), 100, 3), blob('a', 'b'.repeat(64), 50), blob('b', 'a'.repeat(64), 100), blob('a', 'c'.repeat(64), 999, 0)];
    expect(usedBytes(list, 'a')).toBe(150);
    expect(usedBytes(list, 'b')).toBe(100);
  });
});

describe('the storage meter (B8: 10 GB per company line; warn at 80% and 95%; stop capture at 100%)', () => {
  it('reads ok, warn_80, warn_95 and full at the thresholds', () => {
    expect(STORAGE_LINE_BYTES).toBe(10737418240);
    const at = (f: number) => storageMeter(Math.round(STORAGE_LINE_BYTES * f));
    expect(at(0.5)).toMatchObject({ state: 'ok', canCapture: true });
    expect(at(0.8)).toMatchObject({ state: 'warn_80', canCapture: true });
    expect(at(0.95)).toMatchObject({ state: 'warn_95', canCapture: true });
    expect(at(1)).toMatchObject({ state: 'full', canCapture: false });
    expect(at(1).text).toMatch(/viewing and sync carry on/);
  });
  it('shows sizes in South African format', () => {
    expect(formatBytes(512)).toBe('512 bytes');
    expect(formatBytes(1536)).toBe('1,5 KB');
    expect(formatBytes(STORAGE_LINE_BYTES)).toBe('10 GB');
    expect(storageMeter(0).text).toBe('0 bytes of 10 GB used (0%)');
  });
});

describe('canonical paths and the metadata sidecar', () => {
  const parts = { tenantId: 't-1', companyId: 'c-1', placeSlugs: ['rietvlei-yard', 'workshop-block', 'chemical-store'], inspectionId: 'i-1', itemKey: 'item-7', evidenceId: 'e-1', version: 2 };
  it('builds tenant/company/place path/inspection/item/evidence/version and reads it back', () => {
    const p = canonicalPath(parts);
    expect(p).toBe('tenant/t-1/company/c-1/place/rietvlei-yard/workshop-block/chemical-store/inspection/i-1/item/item-7/evidence/e-1/v2');
    expect(parseCanonicalPath(p)).toEqual(parts);
    expect(canonicalPath({ ...parts, placeSlugs: [] })).toContain('/place/_unplaced/');
    expect(parseCanonicalPath('somewhere/else')).toBeNull();
  });
  it('serialises the sidecar with sorted keys, so its hash does not depend on field order', () => {
    const base = {
      evidence_id: 'e-1', root_evidence_id: 'e-1', version: 1, supersedes_id: null, kind: 'photo' as const, sha256: sha(jpeg), size_bytes: jpeg.length, mime_type: 'image/jpeg',
      canonical_path: canonicalPath({ ...parts, version: 1 }), captured_at: '2026-09-27T08:00:00.000Z', gps: { lat: -25.79, lng: 28.3, accuracy_m: 4 }, inspector_id: 'u-1', device_id: 'PHONE-1',
      tenant_id: 't-1', company_id: 'c-1', place_id: 'p-1', place_path: ['Rietvlei Yard'], inspection_id: 'i-1', area_id: null, finding_id: 'f-1', template_item_id: 'item-7',
      seal_sha256: 'a'.repeat(64), caption: 'Chemical store', tags: ['Fail', ' chemicals ', 'fail'], retention_class: 'INST', legal_hold: false,
    };
    const a = buildSidecar(base);
    const reordered = buildSidecar(Object.fromEntries(Object.entries(base).reverse()) as typeof base);
    expect(stableJson(a)).toBe(stableJson(reordered));
    expect(a).toMatchObject({ schema: 'bee-inspect.evidence.v1', cas_key: casKey(sha(jpeg)), tags: ['chemicals', 'fail'] });
    expect(JSON.parse(stableJson(a))).toEqual(JSON.parse(JSON.stringify(a)));
    expect(Object.keys(JSON.parse(stableJson(a)))).toEqual(Object.keys(a).sort());
  });
  it('normalises tags: lower case, trimmed, unique, sorted, 1 to 40 characters', () => {
    expect(normaliseTags(['  Bay 14 ', 'bay  14', 'Scaffold', '', 'x'.repeat(41)])).toEqual(['bay 14', 'scaffold']);
  });
});

describe('stripping camera metadata from shared copies', () => {
  const app1 = (payload: string) => {
    const body = Buffer.from(payload, 'latin1');
    const len = body.length + 2;
    return Buffer.concat([Buffer.from([0xff, 0xe1, len >> 8, len & 0xff]), body]);
  };
  it('removes EXIF (with GPS) and XMP from a JPEG and leaves the image data untouched', () => {
    const withExif = Buffer.concat([jpeg.subarray(0, 2), app1('Exif\u0000\u0000GPS -25.79 28.30 SERIAL 123'), app1('http://ns.adobe.com/xap/1.0/\u0000<x/>'), jpeg.subarray(2)]);
    expect(jpegHasMetadata(withExif)).toBe(true);
    const clean = stripJpegMetadata(withExif);
    expect(jpegHasMetadata(clean)).toBe(false);
    expect(Buffer.from(clean).includes(Buffer.from('SERIAL'))).toBe(false);
    // The original demo photo had no EXIF: stripping it changes nothing.
    expect(Buffer.from(stripJpegMetadata(jpeg)).equals(jpeg)).toBe(true);
    expect(Buffer.from(clean).equals(stripJpegMetadata(jpeg))).toBe(true);
  });
  it('removes text, EXIF and time chunks from a PNG and keeps the image chunks', () => {
    const chunk = (type: string, data: string) => {
      const d = Buffer.from(data, 'latin1');
      const len = Buffer.alloc(4);
      len.writeUInt32BE(d.length);
      return Buffer.concat([len, Buffer.from(type, 'latin1'), d, Buffer.alloc(4)]);
    };
    const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const png = Buffer.concat([sig, chunk('IHDR', 'x'.repeat(13)), chunk('tEXt', 'Author\u0000Someone'), chunk('eXIf', 'GPS'), chunk('IDAT', 'pixels'), chunk('IEND', '')]);
    const clean = Buffer.from(stripPngMetadata(png));
    expect(clean.includes(Buffer.from('tEXt'))).toBe(false);
    expect(clean.includes(Buffer.from('eXIf'))).toBe(false);
    expect(clean.includes(Buffer.from('IDAT'))).toBe(true);
    expect(clean.includes(Buffer.from('IEND'))).toBe(true);
  });
});

describe('versions: never overwrite', () => {
  const v1 = { id: 'e1', evidence_version: 1, root_evidence_id: null, supersedes_id: null, sha256: 'a'.repeat(64), captured_at: '2026-09-27T08:00:00Z', caption: 'Bay 14', tags: ['scaffold'] } as unknown as Photo;
  it('a correction is a new record pointing at the one it supersedes and at the root; the bytes and seal fields cannot change', () => {
    const v2 = nextVersion(v1, { caption: 'Bay 14, east side' }, 'e2');
    expect(v2).toMatchObject({ id: 'e2', evidence_version: 2, supersedes_id: 'e1', root_evidence_id: 'e1', sha256: v1.sha256, caption: 'Bay 14, east side' });
    expect(v1.caption).toBe('Bay 14');
    const v3 = nextVersion(v2, { tags: ['scaffold', 'toe boards'] }, 'e3');
    expect(v3).toMatchObject({ evidence_version: 3, supersedes_id: 'e2', root_evidence_id: 'e1' });
    expect(() => nextVersion(v2, { sha256: 'b'.repeat(64) }, 'x')).toThrow(/new evidence/);
    expect(() => nextVersion(v2, { captured_at: '2027-01-01T00:00:00Z' } as Partial<Photo>, 'x')).toThrow();
    const all = [v3, v1, v2];
    expect(latestVersions(all).map((e) => e.id)).toEqual(['e3']);
    expect(history(all, 'e2').map((e) => e.id)).toEqual(['e1', 'e2', 'e3']);
    expect(chainIsSound(history(all, 'e3'))).toBe(true);
    expect(chainIsSound([v1, v3])).toBe(false);
    expect(rootId(v1)).toBe('e1');
  });
  it('keeps separate evidence apart when showing the newest versions', () => {
    const other = { ...v1, id: 'o1' };
    expect(latestVersions([v1, other, nextVersion(v1, { caption: 'x' }, 'e2')]).map((e) => e.id).sort()).toEqual(['e2', 'o1']);
  });
});

describe('retention and legal hold', () => {
  it('frees a phone copy only when the server holds it verified and nothing using it is on legal hold', () => {
    expect(canFreeLocalCopy({ uploaded: true, verified_at: '2026-09-27' }, [{ legal_hold: false }]).ok).toBe(true);
    expect(canFreeLocalCopy({ uploaded: true, verified_at: null }, [{ legal_hold: false }])).toMatchObject({ ok: false, reason: expect.stringMatching(/Not yet verified/) });
    expect(canFreeLocalCopy({ uploaded: true, verified_at: '2026-09-27' }, [{ legal_hold: false }, { legal_hold: true }])).toMatchObject({ ok: false, reason: expect.stringMatching(/legal hold/) });
  });
});

describe('resumable chunked upload with an integrity check', () => {
  const h = sha(jpeg);
  it('plans 5 MiB chunks and covers every byte once', () => {
    const c = planChunks(12 * 1024 * 1024);
    expect(c.map((x) => x.end - x.start)).toEqual([CHUNK_BYTES, CHUNK_BYTES, 2 * 1024 * 1024]);
    expect(c[2].end).toBe(12 * 1024 * 1024);
    expect(planChunks(1)).toEqual([{ index: 0, start: 0, end: 1 }]);
    expect(() => planChunks(0)).toThrow();
  });
  it('resumes at the first chunk the server has not received', () => {
    let u = withSession(newUpload(h, 12 * 1024 * 1024), 's1', [0]);
    expect(remainingChunks(u).map((c) => c.index)).toEqual([1, 2]);
    u = markChunkDone(u, 1);
    expect(progress(u)).toBeCloseTo(2 / 3);
    u = markChunkDone(markChunkDone(u, 2), 2);
    expect(allChunksSent(u)).toBe(true);
    expect(u.done).toEqual([0, 1, 2]);
  });
  it('marks the upload verified only when the server’s hash matches, and starts again when it does not', () => {
    const sent = markChunkDone(withSession(newUpload(h, jpeg.length), 's1'), 0);
    const ok = verifyUpload(sent, h.toUpperCase());
    expect(ok).toMatchObject({ ok: true, state: { verified: true, verified_sha256: h } });
    expect(progress(ok.state)).toBe(1);
    const bad = verifyUpload(sent, 'f'.repeat(64));
    expect(bad).toMatchObject({ ok: false, state: { verified: false, session_id: null, done: [], attempts: 1 } });
    expect(bad.state.last_error).toMatch(/did not match/);
  });
  it('sends nothing when the server already holds the bytes (dedupe across phones)', () => {
    expect(alreadyHeld(newUpload(h, jpeg.length), h)).toMatchObject({ verified: true, done: [] });
  });
});

describe('full text search', () => {
  const doc = (id: string, kind: SearchDoc['kind'], title: string, body: string, tags: string[] = [], at = '2026-09-27', companyId = 'co', placeId: string | null = null): SearchDoc => ({ id, kind, ref: id, title, body, tags, companyId, placeId, inspectionId: null, at });
  const docs = [
    doc('f1', 'finding', 'Guards removed for cleaning and not refitted', 'Tail pulley guard left off after belt cleaning', ['Fail', 'critical'], '2026-09-27', 'co', 'plant'),
    doc('t1', 'transcript', 'Voice note VN-1', 'Conveyor two tail pulley guard is lying on the walkway', ['voice note'], '2026-09-26'),
    doc('p1', 'evidence', 'Missing toe boards, second lift', 'Rietvlei Yard scaffold laydown', ['photo', 'fail'], '2026-09-25'),
    doc('l1', 'place', 'Distribution centre', 'Warehouse', ['Warehouse'], '2026-09-20', 'other'),
    doc('l2', 'place', 'Ladders store', 'Room', ['Room or area'], '2026-09-19'),
  ];
  const index = buildIndex(docs);
  it('tokenises plain words, drops filler words and folds plurals', () => {
    expect(tokenize('The ladders, and the guard-rails!')).toEqual(['ladders', 'guard', 'rails']);
    expect(fold('ladders')).toBe('ladder');
    expect(fold('batteries')).toBe('battery');
    expect(fold('glass')).toBe('glass');
  });
  it('needs every word, matches word starts, and ranks titles above bodies', () => {
    expect(search(index, 'tail pulley').map((h) => h.doc.id)).toEqual(['f1', 't1']);
    expect(search(index, 'toe board').map((h) => h.doc.id)).toEqual(['p1']);
    expect(search(index, 'guard').map((h) => h.doc.id)[0]).toBe('f1');
    expect(search(index, 'ladder').map((h) => h.doc.id)).toEqual(['l2']);
    expect(search(index, 'guard toe')).toEqual([]);
  });
  it('filters by kind, company and place, and lists newest first without a query', () => {
    expect(search(index, 'guard', { kinds: ['transcript'] }).map((h) => h.doc.id)).toEqual(['t1']);
    expect(search(index, 'distribution', { companyId: 'co' })).toEqual([]);
    expect(search(index, '', { placeIds: new Set(['plant']) }).map((h) => h.doc.id)).toEqual(['f1']);
    expect(search(index, '').map((h) => h.doc.id)).toEqual(['f1', 't1', 'p1', 'l1', 'l2']);
  });
  it('writes the same query for SQLite FTS5: every word a quoted prefix', () => {
    expect(ftsQuery('Tail "pulley')).toBe('"tail"* AND "pulley"*');
    expect(ftsQuery('the and')).toBeNull();
  });
});
