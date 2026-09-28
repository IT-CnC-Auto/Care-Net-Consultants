// Search across findings, voice note transcripts, evidence metadata, places and
// inspections. The documents are built from the local store; the phone's
// SQLite FTS5 index answers when the build has it, the in memory index
// (src/lib/search-index.ts) otherwise (and always on the web preview).

import { useEffect, useMemo, useRef, useState } from 'react';

import type { DataStore } from '@/data/data-store';
import { useStore } from '@/data/hooks';
import { latestVersions } from '@/lib/evidence-store';
import { kernel } from '@/lib/kernel';
import { breadcrumb, typeLabel } from '@/lib/places';
import { latestTranscripts } from '@/lib/report';
import { BAND_LABEL, riskBand, riskScore } from '@/lib/risk';
import { buildIndex, ftsQuery, search, type SearchDoc, type SearchFilter, type SearchHit } from '@/lib/search-index';

const RESULT_WORD = { pass: 'Pass', fail: 'Fail', na: 'N/A', observe: 'Observe' } as const;

/** Every searchable thing on this phone, as search documents. */
export function searchDocs(store: DataStore): SearchDoc[] {
  const b = kernel();
  const places = store.list('place');
  const companies = new Map(store.list('company').map((c) => [c.id, c.trading_name || c.legal_name]));
  const inspections = new Map(store.list('inspection').map((i) => [i.id, i]));
  // Checklist lines: the store's, with the kernel bundle's as a fallback before they are loaded.
  const items = new Map<string, { prompt: string }>([...b.templates.flatMap((t) => t.items.map((i) => [i.id, i] as const)), ...store.list('template_item').map((i) => [i.id, i] as const)]);
  const findings = new Map(store.list('finding').map((f) => [f.id, f]));
  const risks = store.list('risk');
  const pathText = (placeId: string | null | undefined, companyId: string | null | undefined) => breadcrumb(places, placeId, companyId ? companies.get(companyId) : null).join(' ');
  const bandOf = (findingId: string | null) => {
    const r = findingId ? risks.find((x) => x.finding_id === findingId) : undefined;
    const band = r ? riskBand(riskScore(r.inherent_likelihood, r.inherent_severity)) : null;
    return band ? [`${BAND_LABEL[band]} risk`] : [];
  };
  const docs: SearchDoc[] = [];
  for (const p of places.filter((x) => !x.archived_at)) {
    docs.push({ id: `place:${p.id}`, kind: 'place', ref: p.id, title: p.name, body: `${typeLabel(b, p)} ${pathText(p.id, p.client_account_id)} ${p.address ?? ''} ${p.responsible_person ?? ''}`, tags: [typeLabel(b, p)], companyId: p.client_account_id, placeId: p.id, inspectionId: null, at: p.updated_at ?? p.created_at ?? null });
  }
  for (const i of inspections.values()) {
    docs.push({ id: `inspection:${i.id}`, kind: 'inspection', ref: i.id, title: i.title, body: pathText(i.place_id ?? i.site_id, i.client_account_id), tags: [i.status.replace('_', ' ')], companyId: i.client_account_id, placeId: i.place_id ?? i.site_id, inspectionId: i.id, at: i.started_at });
  }
  for (const f of findings.values()) {
    const insp = inspections.get(f.inspection_id);
    const item = f.template_item_id ? items.get(f.template_item_id) : undefined;
    docs.push({
      id: `finding:${f.id}`,
      kind: 'finding',
      ref: f.id,
      title: item?.prompt ?? f.note ?? 'Finding',
      body: `${f.note ?? ''} ${insp?.title ?? ''} ${pathText(insp?.place_id ?? insp?.site_id, insp?.client_account_id)}`,
      tags: [RESULT_WORD[f.result], ...(f.severity ? [f.severity] : []), ...bandOf(f.id)],
      companyId: insp?.client_account_id ?? null,
      placeId: insp?.place_id ?? insp?.site_id ?? null,
      inspectionId: f.inspection_id,
      at: f.captured_at,
    });
  }
  const latestT = latestTranscripts(store.list('transcript'));
  for (const v of latestVersions(store.list('voice_note'))) {
    const t = latestT.get(v.root_evidence_id ?? v.id) ?? latestT.get(v.id);
    const insp = inspections.get(v.inspection_id);
    if (t) {
      docs.push({ id: `transcript:${t.id}`, kind: 'transcript', ref: v.id, title: v.vn_number ? `Voice note VN-${v.vn_number}` : 'Voice note', body: t.body, tags: ['voice note', ...v.tags], companyId: insp?.client_account_id ?? null, placeId: v.place_id ?? insp?.place_id ?? null, inspectionId: v.inspection_id, at: v.captured_at });
    }
    docs.push({ id: `evidence:${v.id}`, kind: 'evidence', ref: v.id, title: `Voice note ${v.vn_number ? `VN-${v.vn_number}` : ''}`.trim(), body: `${insp?.title ?? ''} ${pathText(v.place_id ?? insp?.place_id, insp?.client_account_id)} ${v.audio_sha256}`, tags: ['voice note', ...v.tags, ...bandOf(v.finding_id)], companyId: insp?.client_account_id ?? null, placeId: v.place_id ?? insp?.place_id ?? null, inspectionId: v.inspection_id, at: v.captured_at });
  }
  for (const ph of latestVersions(store.list('photo'))) {
    const insp = inspections.get(ph.inspection_id);
    const f = ph.finding_id ? findings.get(ph.finding_id) : undefined;
    docs.push({
      id: `evidence:${ph.id}`,
      kind: 'evidence',
      ref: ph.id,
      title: ph.caption ?? 'Photo',
      body: `${insp?.title ?? ''} ${pathText(ph.place_id ?? insp?.place_id, insp?.client_account_id)} ${ph.annotations.map((a) => a.label).join(' ')} ${f?.note ?? ''} ${ph.sha256}`,
      tags: ['photo', ph.kind.replace(/_/g, ' '), ...ph.tags, ...bandOf(ph.finding_id)],
      companyId: insp?.client_account_id ?? null,
      placeId: ph.place_id ?? insp?.place_id ?? null,
      inspectionId: ph.inspection_id,
      at: ph.captured_at,
    });
  }
  return docs;
}

/**
 * Instant search: the in memory index answers at once; where the phone's
 * SQLite has FTS5 the same query is also run there and its ranking is used when
 * it arrives. Returns the engine that answered, for the screen to show.
 */
export function useSearch(query: string, filter: SearchFilter = {}, limit = 60): { hits: SearchHit[]; engine: 'fts5' | 'memory' } {
  const store = useStore();
  const docs = useMemo(() => searchDocs(store), [store]);
  const index = useMemo(() => buildIndex(docs), [docs]);
  const filterKey = JSON.stringify({ ...filter, placeIds: filter.placeIds ? Array.from(filter.placeIds).sort() : null });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const stableFilter = useMemo(() => filter, [filterKey]);
  const memoryHits = useMemo(() => search(index, query, stableFilter, limit), [index, query, stableFilter, limit]);
  const fts = store.local.search;
  const [ftsHits, setFtsHits] = useState<{ q: string; hits: SearchHit[] } | null>(null);
  const indexed = useRef<SearchDoc[] | null>(null);

  useEffect(() => {
    if (!fts) return;
    const match = ftsQuery(query);
    if (!match) return;
    let cancelled = false;
    (async () => {
      try {
        if (indexed.current !== docs) {
          await fts.reindex(docs.map((d) => ({ id: d.id, title: d.title, tags: d.tags.join(' '), body: d.body })));
          indexed.current = docs;
        }
        const ids = await fts.query(match, limit * 2);
        const byId = new Map(docs.map((d) => [d.id, d]));
        const allowed = new Set(search(index, query, stableFilter, limit * 4).map((h) => h.doc.id));
        // The filters are applied by the memory search; FTS5 gives the order.
        const ranked = ids.map((id, i) => ({ doc: byId.get(id), score: ids.length - i })).filter((h): h is SearchHit => !!h.doc && allowed.has(h.doc.id));
        if (!cancelled) setFtsHits({ q: query, hits: ranked.slice(0, limit) });
      } catch {
        if (!cancelled) setFtsHits(null);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [fts, docs, index, query, stableFilter, limit]);

  if (fts && ftsHits && ftsHits.q === query && ftsQuery(query)) return { hits: ftsHits.hits, engine: 'fts5' };
  return { hits: memoryHits, engine: 'memory' };
}
