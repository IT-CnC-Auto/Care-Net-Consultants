/// <reference types="node" />
// The demonstration data across five industries, the evidence pipeline on the
// local store (content addressed blobs, dedupe, versions, sidecar), search over
// the store, and the simulated chunked upload with its integrity check.

import { createHash } from 'crypto';

import { DemoBackend } from '@/backend/demo-backend';
import { DEMO, DEMO_COMPANIES, demoSeed } from '@/backend/demo-seed';
import { correctPhoto, storePhoto } from '@/features/capture';
import { searchDocs } from '@/features/search';
import { blobId, casKey, history, latestVersions, parseCanonicalPath } from '@/lib/evidence-store';
import { industry, kernel } from '@/lib/kernel';
import { checkPlace, pathOf } from '@/lib/places';
import { buildIndex, search } from '@/lib/search-index';
import { newItem } from '@/lib/sync-queue';
import type { Place } from '@/lib/types';

import { DataStore } from '../data-store';
import { ensureKernelTemplates } from '../kernel-templates';
import type { LocalStore } from '../local-store.types';

jest.mock('@/features/evidence', () => {
  const { createHash: hash } = jest.requireActual('crypto');
  return {
    keepBlob: async (uri: string, sha: string) => ({ uri: `mem://cas/${sha}`, existed: false, from: uri }),
    deriveCopies: async (uri: string) => [
      { variant: 'thumb', uri: `${uri}#thumb`, sha256: hash('sha256').update(`${uri}#thumb`).digest('hex'), size_bytes: 1200, exif_stripped: true },
      { variant: 'web', uri: `${uri}#web`, sha256: hash('sha256').update(`${uri}#web`).digest('hex'), size_bytes: 9000, exif_stripped: true },
    ],
    writeSidecar: async () => undefined,
    currentFix: async () => ({ lat: -25.79, lng: 28.3, accuracy: 5 }),
    sealEvidence: async (f: { path: string; sha256: string }) => hash('sha256').update(`${f.path}|${f.sha256}`).digest('hex'),
    sha256Text: async (t: string) => hash('sha256').update(t).digest('hex'),
    sha256Hex: async (b: Uint8Array) => hash('sha256').update(b).digest('hex'),
    readBytes: async () => new Uint8Array([1, 2, 3]),
    mimeFromName: () => 'image/jpeg',
  };
});

function memoryStore(): LocalStore {
  const records = new Map<string, Record<string, unknown>>();
  let queue: never[] = [];
  const kv = new Map<string, string>();
  return {
    name: 'memory',
    async loadAll() {
      return Array.from(records.entries()).map(([k, data]) => ({ kind: k.split('/')[0], id: k.split('/').slice(1).join('/'), data }));
    },
    async put(kind, id, data) {
      records.set(`${kind}/${id}`, data);
    },
    async remove(kind, id) {
      records.delete(`${kind}/${id}`);
    },
    async loadQueue() {
      return queue;
    },
    async saveQueue(items) {
      queue = items.slice() as never[];
    },
    async kvGet(k) {
      return kv.get(k) ?? null;
    },
    async kvSet(k, v) {
      if (v === null) kv.delete(k);
      else kv.set(k, v);
    },
    async wipe() {
      records.clear();
    },
  };
}

let n = 0;
const ids = () => `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`;

async function seeded() {
  const store = await DataStore.open(memoryStore(), ids);
  await store.putServerMany(demoSeed(new Date('2026-09-27T10:00:00+02:00')));
  await ensureKernelTemplates(store);
  return store;
}

describe('the demonstration data is not construction only', () => {
  it('holds five fictitious companies in five kernel industries, each with a places tree that keeps the tree rules', async () => {
    const store = await seeded();
    const b = kernel();
    const companies = store.list('company');
    expect(companies.map((c) => c.industry_code).sort()).toEqual(['AGRI', 'CONSTR', 'HEALTH', 'MINING', 'RETAIL']);
    for (const c of companies) {
      expect(c.legal_name).toMatch(/\(fictitious\)$/);
      expect(industry(b, c.industry_code)?.subindustries.some((s) => s.code === c.subindustry_code)).toBe(true);
      expect(industry(b, c.industry_code)?.sample_company.name).toBe(c.legal_name);
    }
    // Every place, added in order, passes the same rules as bi_place_guard.
    const built: Place[] = [];
    for (const p of store.list('place')) {
      expect(checkPlace(b, built, p).reasons).toEqual([]);
      built.push(p);
    }
    for (const cid of Object.values(DEMO_COMPANIES)) expect(built.filter((p) => p.client_account_id === cid).length).toBeGreaterThanOrEqual(6);
    // Industry specific kinds of place are used where the kernel offers them.
    expect(built.some((p) => p.client_account_id === DEMO_COMPANIES.mining && p.place_type === 'mine_section')).toBe(true);
    expect(built.some((p) => p.client_account_id === DEMO_COMPANIES.agriculture && p.place_type === 'farm')).toBe(true);
    expect(built.some((p) => p.client_account_id === DEMO_COMPANIES.healthcare && p.place_type === 'clinic_lab')).toBe(true);
    expect(built.some((p) => p.client_account_id === DEMO_COMPANIES.retail && p.place_type === 'retail_store')).toBe(true);
  });

  it('runs every inspection on a kernel template, at a place under its site, with items of that template', async () => {
    const store = await seeded();
    const b = kernel();
    const places = store.list('place');
    const inspections = store.list('inspection');
    expect(new Set(inspections.map((i) => i.client_account_id)).size).toBe(5);
    for (const i of inspections) {
      const t = b.templates.find((x) => x.id === i.template_id);
      expect(t).toBeDefined();
      expect(pathOf(places, i.place_id)[0].id).toBe(i.site_id);
      for (const f of store.where('finding', (x) => x.inspection_id === i.id)) expect(t?.items.some((it) => it.id === f.template_item_id)).toBe(true);
    }
  });

  it('stores demo evidence by content address and canonical path, and counts a reused photo once', async () => {
    const store = await seeded();
    for (const ph of store.list('photo')) {
      const company = store.get('inspection', ph.inspection_id)?.client_account_id as string;
      expect(ph.storage_path).toBe(`${company}/${casKey(ph.sha256)}`);
      const parts = parseCanonicalPath(ph.canonical_path as string);
      expect(parts).toMatchObject({ companyId: company, inspectionId: ph.inspection_id, evidenceId: ph.id, version: 1 });
      expect(parts?.placeSlugs.length).toBeGreaterThan(0);
      expect(store.get('blob', blobId(company, ph.sha256))).toBeDefined();
    }
  });
});

describe('the evidence pipeline on the phone', () => {
  it('dedupes the same bytes, derives copies once, and keeps corrections as versions', async () => {
    const store = await seeded();
    const inspection = store.get('inspection', DEMO.inspection);
    if (!inspection) throw new Error('seed');
    const target = { inspection, areaId: 'b1a00000-0000-4000-8000-000000000082', findingId: null, inspectorId: DEMO.inspector };
    const sha = createHash('sha256').update('new photo bytes').digest('hex');
    const first = await storePhoto(store, target, { sha, bytesLength: 4000, mime: 'image/jpeg', ext: 'jpg', sourceUri: 'file:///picked.jpg', kind: 'area', caption: 'Laydown area' });
    const second = await storePhoto(store, target, { sha, bytesLength: 4000, mime: 'image/jpeg', ext: 'jpg', sourceUri: 'file:///picked-again.jpg', kind: 'area', caption: 'Same picture again' });
    expect(first.deduped).toBe(false);
    expect(second.deduped).toBe(true);
    expect(store.get('blob', blobId(DEMO.company, sha))?.refs).toBe(2);
    expect(store.where('blob', (x) => x.derived_from === sha).map((x) => x.variant).sort()).toEqual(['thumb', 'web']);
    expect(second.photo._thumb_uri).toBe(first.photo._thumb_uri);
    expect(first.photo.canonical_path).toContain('/place/rietvlei-yard/stores-and-yard/yard-zone-b/scaffold-laydown-area/');
    expect(first.photo.sidecar_sha256).toMatch(/^[0-9a-f]{64}$/);
    expect(first.photo.tags).toEqual(expect.arrayContaining(['area', 'room or area', 'hsf-f-01']));
    // A caption correction: a new version on the same blob; the first stays as it was.
    const v2 = await correctPhoto(store, first.photo, { caption: 'Laydown area, bay 14' });
    expect(v2).toMatchObject({ evidence_version: 2, supersedes_id: first.photo.id, root_evidence_id: first.photo.id, sha256: sha, caption: 'Laydown area, bay 14' });
    expect(store.get('photo', first.photo.id)?.caption).toBe('Laydown area');
    expect(v2.canonical_path).toMatch(/\/v2$/);
    expect(history(store.list('photo'), v2.id).map((p) => p.id)).toEqual([first.photo.id, v2.id]);
    expect(latestVersions(store.list('photo')).some((p) => p.id === first.photo.id)).toBe(false);
    expect(store.get('blob', blobId(DEMO.company, sha))?.refs).toBe(3);
    // Both new photos are queued to upload; the correction too (a new row, never an update).
    expect(store.getQueue().filter((q) => q.kind === 'photo' && q.op === 'upload').length).toBe(3);
    expect(store.getQueue().some((q) => q.kind === 'photo' && q.op === 'update')).toBe(false);
  });

  it('uploads in resumable parts and marks the blob verified only after the hash check (demo backend)', async () => {
    const store = await seeded();
    const inspection = store.get('inspection', DEMO.inspection);
    if (!inspection) throw new Error('seed');
    const sha = createHash('sha256').update('bytes to upload').digest('hex');
    const { photo } = await storePhoto(store, { inspection, areaId: null, findingId: null, inspectorId: DEMO.inspector }, { sha, bytesLength: 12 * 1024 * 1024, mime: 'image/jpeg', ext: 'jpg', sourceUri: 'file:///big.jpg', kind: 'other', caption: null });
    const backend = new DemoBackend(store);
    const out = await backend.push(newItem({ id: 'q1', kind: 'photo', recordId: photo.id, op: 'upload', payload: {}, now: Date.now() }), store);
    expect(out.kind).toBe('ok');
    const upload = (out as unknown as { patch: { _upload: { verified: boolean; done: number[]; verified_sha256: string } } }).patch._upload;
    expect(upload).toMatchObject({ verified: true, done: [0, 1, 2], verified_sha256: sha });
    expect(store.get('blob', blobId(DEMO.company, sha))?.verified_at).toBeTruthy();
  });
});

describe('search over the phone’s records', () => {
  it('finds findings, transcripts, evidence and places across the five companies, and filters by company', async () => {
    const store = await seeded();
    const index = buildIndex(searchDocs(store));
    const kinds = (q: string, companyId?: string) => search(index, q, companyId ? { companyId } : {}).map((h) => h.doc.kind);
    expect(kinds('tail pulley')).toEqual(expect.arrayContaining(['finding', 'transcript', 'evidence']));
    expect(kinds('racking upright')).toEqual(expect.arrayContaining(['finding', 'evidence']));
    expect(kinds('spill kit')).toContain('finding');
    expect(kinds('pathology')).toEqual(expect.arrayContaining(['place']));
    expect(kinds('tail pulley', DEMO_COMPANIES.retail)).toEqual([]);
    expect(search(index, 'extreme risk').length).toBeGreaterThan(0);
  });
});
