// The places tree of a company: rules, paths, breadcrumbs and instant search.
// Pure functions over the records (no storage, no React), the same rules the
// database keeps in bi_place_guard (migration 065):
//   1. A top level place is a type the kernel allows at the top (site, office,
//      farm, mine or quarry section, ...); a child is a type its parent allows.
//   2. Parent and child belong to the same company; a place never moves to
//      another company.
//   3. No loops: a place never sits under itself or under one of its own
//      children.
//   4. At most `place_max_depth` levels (the bundle's limit).
//   5. Names are 1 to 200 characters and unique among siblings (ignoring case
//      and spaces), so a breadcrumb always reads one way.
//   6. Places are archived, never deleted (evidence keeps its path).

import { placeType, type KernelBundle } from './kernel';
import type { Company, Id, Place } from './types';

export type PlaceDraft = Pick<Place, 'client_account_id' | 'parent_id' | 'place_type' | 'name'> & { id?: Id };

const norm = (s: string) => s.trim().replace(/\s+/g, ' ').toLowerCase();

export function livePlaces(places: readonly Place[], companyId?: string | null): Place[] {
  return places.filter((p) => !p.archived_at && (!companyId || p.client_account_id === companyId));
}

export function childrenOf(places: readonly Place[], parentId: Id | null, companyId?: string | null): Place[] {
  return livePlaces(places, companyId)
    .filter((p) => p.parent_id === parentId)
    .sort((a, b) => a.name.localeCompare(b.name));
}

/** Root first, the place itself last. Stops on a loop or a missing parent. */
export function pathOf(places: readonly Place[], id: Id | null | undefined): Place[] {
  const byId = new Map(places.map((p) => [p.id, p]));
  const out: Place[] = [];
  const seen = new Set<string>();
  let cur = id ? byId.get(id) : undefined;
  while (cur && !seen.has(cur.id)) {
    seen.add(cur.id);
    out.unshift(cur);
    cur = cur.parent_id ? byId.get(cur.parent_id) : undefined;
  }
  return out;
}

export function depthOf(places: readonly Place[], id: Id | null | undefined): number {
  return pathOf(places, id).length;
}

/** The top level place (the site) a place belongs to. */
export function rootOf(places: readonly Place[], id: Id | null | undefined): Place | undefined {
  return pathOf(places, id)[0];
}

export function descendantsOf(places: readonly Place[], id: Id): Place[] {
  const out: Place[] = [];
  const stack = [id];
  const seen = new Set<string>([id]);
  while (stack.length) {
    const cur = stack.pop() as string;
    for (const p of places) {
      if (p.parent_id === cur && !seen.has(p.id)) {
        seen.add(p.id);
        out.push(p);
        stack.push(p.id);
      }
    }
  }
  return out;
}

export function typeLabel(b: KernelBundle, p: Pick<Place, 'place_type' | 'custom_type_label'>): string {
  return p.custom_type_label?.trim() || placeType(b, p.place_type)?.label || 'Place';
}

/** "Company › Site › Department › Room". */
export function breadcrumb(places: readonly Place[], id: Id | null | undefined, companyName?: string | null): string[] {
  const parts = pathOf(places, id).map((p) => p.name);
  return companyName ? [companyName, ...parts] : parts;
}

export interface RuleResult {
  ok: boolean;
  reasons: string[];
}

/** Checks a new or moved place against the tree rules above. */
export function checkPlace(b: KernelBundle, places: readonly Place[], draft: PlaceDraft): RuleResult {
  const reasons: string[] = [];
  const name = draft.name?.trim() ?? '';
  if (name.length < 1 || name.length > 200) reasons.push('Give the place a name (up to 200 characters).');
  const type = placeType(b, draft.place_type);
  if (!type) reasons.push('Choose what kind of place it is.');
  const parent = draft.parent_id ? places.find((p) => p.id === draft.parent_id) : undefined;
  if (draft.parent_id && !parent) reasons.push('The place it belongs under is not on this phone.');
  if (parent && parent.archived_at) reasons.push('The place it belongs under is archived.');
  if (parent && parent.client_account_id !== draft.client_account_id) reasons.push('A place stays with its own company.');
  if (type) {
    if (!parent && !type.root) reasons.push(`A ${type.label.toLowerCase()} sits under a site or another place, not at the top.`);
    if (parent) {
      const pt = placeType(b, parent.place_type);
      if (pt && !pt.children.includes(type.code)) reasons.push(`A ${type.label.toLowerCase()} cannot go under a ${pt.label.toLowerCase()}.`);
    }
  }
  if (draft.id && parent) {
    if (parent.id === draft.id || descendantsOf(places, draft.id).some((d) => d.id === parent.id)) reasons.push('A place cannot sit under itself or one of its own places.');
  }
  const depth = (parent ? depthOf(places, parent.id) : 0) + 1 + (draft.id ? maxSubtreeDepth(places, draft.id) : 0);
  if (depth > b.limits.place_max_depth) reasons.push(`Keep the tree to ${b.limits.place_max_depth} levels.`);
  if (name && livePlaces(places, draft.client_account_id).some((p) => p.id !== draft.id && p.parent_id === (draft.parent_id ?? null) && norm(p.name) === norm(name))) {
    reasons.push('There is already a place with this name here.');
  }
  return { ok: reasons.length === 0, reasons };
}

function maxSubtreeDepth(places: readonly Place[], id: Id): number {
  const kids = places.filter((p) => p.parent_id === id);
  return kids.length ? 1 + Math.max(...kids.map((k) => maxSubtreeDepth(places, k.id))) : 0;
}

/** A path segment for the canonical evidence path: lower case letters, digits and single hyphens. */
export function slug(name: string): string {
  const s = name
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48);
  return s || 'place';
}

// Recent places -------------------------------------------------------------------------------

export const RECENT_MAX = 8;

/** Most recent first, no repeats, at most RECENT_MAX. */
export function pushRecent(recent: readonly Id[], id: Id, max = RECENT_MAX): Id[] {
  return [id, ...recent.filter((x) => x !== id)].slice(0, max);
}

// Instant search ---------------------------------------------------------------------------------

export interface PlaceHit {
  kind: 'place' | 'company';
  id: Id;
  companyId: Id;
  title: string;
  /** The breadcrumb above it ("Company › Site › Department"). */
  path: string;
  typeLabel: string;
  score: number;
}

/**
 * Every word of the query must start a word of the place's name, its type or
 * its path (so "work fl" finds "Workshop floor"). Names beat types, types beat
 * paths; places of the active company come first; then shorter paths.
 */
export function searchPlaces(
  b: KernelBundle,
  places: readonly Place[],
  companies: readonly Pick<Company, 'id' | 'legal_name' | 'trading_name'>[],
  query: string,
  activeCompanyId?: string | null,
): PlaceHit[] {
  const words = norm(query).split(' ').filter(Boolean);
  const companyName = new Map(companies.map((c) => [c.id, c.trading_name || c.legal_name]));
  const hits: PlaceHit[] = [];
  const score = (fields: [string, number][]): number => {
    if (!words.length) return 1;
    let total = 0;
    for (const w of words) {
      let best = 0;
      for (const [text, weight] of fields) {
        const tokens = norm(text).split(/[^a-z0-9]+/);
        if (tokens.some((t) => t.startsWith(w))) best = Math.max(best, weight);
      }
      if (!best) return 0;
      total += best;
    }
    return total;
  };
  for (const c of companies) {
    const s = score([[c.legal_name, 3], [c.trading_name ?? '', 3]]);
    if (s) hits.push({ kind: 'company', id: c.id, companyId: c.id, title: c.trading_name || c.legal_name, path: 'Company', typeLabel: 'Company', score: s + (c.id === activeCompanyId ? 0.5 : 0) });
  }
  for (const p of livePlaces(places)) {
    const crumbs = breadcrumb(places, p.id, companyName.get(p.client_account_id));
    const pathText = crumbs.slice(0, -1).join(' › ');
    const tl = typeLabel(b, p);
    const s = score([[p.name, 3], [tl, 2], [pathText, 1]]);
    if (s) hits.push({ kind: 'place', id: p.id, companyId: p.client_account_id, title: p.name, path: pathText, typeLabel: tl, score: s + (p.client_account_id === activeCompanyId ? 0.5 : 0) - crumbs.length * 0.01 });
  }
  return hits.sort((a, b2) => b2.score - a.score || a.title.localeCompare(b2.title));
}
