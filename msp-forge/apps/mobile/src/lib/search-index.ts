// Full text search over findings, transcripts, evidence metadata and places.
// On the phone the same documents go into SQLite FTS5 (src/data/search-fts.ts)
// when the build has it; this in memory index is the fallback and the web
// preview's engine. Both take the same documents and give the same answers for
// the queries people type (words, prefixes, several words = all of them).

export type SearchKind = 'finding' | 'transcript' | 'evidence' | 'place' | 'inspection';

export interface SearchDoc {
  id: string;
  kind: SearchKind;
  /** The record the result opens. */
  ref: string;
  title: string;
  body: string;
  tags: string[];
  companyId: string | null;
  placeId: string | null;
  inspectionId: string | null;
  at: string | null;
}

export interface SearchHit {
  doc: SearchDoc;
  score: number;
}

// Words that carry no meaning in a search (plain English, short list).
const STOP = new Set(['a', 'an', 'and', 'the', 'of', 'to', 'in', 'on', 'at', 'for', 'is', 'are', 'was', 'with', 'by', 'or', 'it', 'be', 'as', 'from', 'this', 'that']);

export function tokenize(text: string): string[] {
  return text
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 0 && !STOP.has(t));
}

/** A light plural fold so "ladders" finds "ladder" and the other way round. */
export function fold(t: string): string {
  if (t.length > 4 && t.endsWith('ies')) return t.slice(0, -3) + 'y';
  if (t.length > 3 && t.endsWith('s') && !t.endsWith('ss')) return t.slice(0, -1);
  return t;
}

interface Posting {
  doc: number;
  weight: number;
}

export interface SearchIndex {
  docs: SearchDoc[];
  terms: Map<string, Posting[]>;
  sortedTerms: string[];
}

const FIELD_WEIGHT = { title: 3, tags: 2, body: 1 } as const;

export function buildIndex(docs: readonly SearchDoc[]): SearchIndex {
  const terms = new Map<string, Posting[]>();
  docs.forEach((d, i) => {
    const w = new Map<string, number>();
    const add = (text: string, weight: number) => {
      for (const t of tokenize(text).map(fold)) w.set(t, Math.max(w.get(t) ?? 0, weight));
    };
    add(d.title, FIELD_WEIGHT.title);
    add(d.tags.join(' '), FIELD_WEIGHT.tags);
    add(d.body, FIELD_WEIGHT.body);
    for (const [t, weight] of w) {
      const list = terms.get(t);
      if (list) list.push({ doc: i, weight });
      else terms.set(t, [{ doc: i, weight }]);
    }
  });
  return { docs: docs.slice(), terms, sortedTerms: Array.from(terms.keys()).sort() };
}

function prefixRange(sorted: readonly string[], prefix: string): string[] {
  let lo = 0;
  let hi = sorted.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (sorted[mid] < prefix) lo = mid + 1;
    else hi = mid;
  }
  const out: string[] = [];
  for (let i = lo; i < sorted.length && sorted[i].startsWith(prefix); i++) out.push(sorted[i]);
  return out;
}

export interface SearchFilter {
  kinds?: SearchKind[];
  companyId?: string | null;
  placeIds?: Set<string> | null;
  inspectionId?: string | null;
}

/**
 * Every query word must match (as a whole word or the start of one); the score
 * adds each word's best field weight, exact words count double a prefix, and a
 * newer record wins a tie.
 */
export function search(index: SearchIndex, query: string, filter: SearchFilter = {}, limit = 50): SearchHit[] {
  const words = tokenize(query);
  const pass = (d: SearchDoc) =>
    (!filter.kinds || filter.kinds.includes(d.kind)) &&
    (!filter.companyId || d.companyId === filter.companyId) &&
    (!filter.placeIds || (d.placeId !== null && filter.placeIds.has(d.placeId))) &&
    (!filter.inspectionId || d.inspectionId === filter.inspectionId);
  if (!words.length) {
    return index.docs
      .filter(pass)
      .sort((a, b) => (b.at ?? '').localeCompare(a.at ?? ''))
      .slice(0, limit)
      .map((doc) => ({ doc, score: 0 }));
  }
  let scores: Map<number, number> | null = null;
  for (const w of words) {
    const f = fold(w);
    const perDoc = new Map<number, number>();
    const exact = new Set([w, f]);
    for (const term of new Set([...prefixRange(index.sortedTerms, w), ...prefixRange(index.sortedTerms, f)])) {
      for (const p of index.terms.get(term) ?? []) {
        const s = p.weight * (exact.has(term) ? 2 : 1);
        perDoc.set(p.doc, Math.max(perDoc.get(p.doc) ?? 0, s));
      }
    }
    if (scores === null) scores = perDoc;
    else {
      const next = new Map<number, number>();
      for (const [d, s] of scores) {
        const add = perDoc.get(d);
        if (add !== undefined) next.set(d, s + add);
      }
      scores = next;
    }
    if (!scores.size) return [];
  }
  return Array.from((scores ?? new Map()).entries())
    .map(([i, score]) => ({ doc: index.docs[i], score }))
    .filter((h) => pass(h.doc))
    .sort((a, b) => b.score - a.score || (b.doc.at ?? '').localeCompare(a.doc.at ?? ''))
    .slice(0, limit);
}

/** An FTS5 MATCH expression for the same query: every word as a prefix, quoted. */
export function ftsQuery(query: string): string | null {
  const words = tokenize(query);
  if (!words.length) return null;
  return words.map((w) => `"${w.replace(/"/g, '')}"*`).join(' AND ');
}
