// The Care Net kernel on the phone: the offline bundle written by
// scripts/build-kernel-bundle.mjs from the repository's kernel sources (17
// industries, their subindustries, triggers, place types and the inspection
// templates). Pure functions over a bundle, so every rule is testable; the
// app reads the bundled copy offline and a later kernel service can replace it
// (refreshKernel, a hook that is not connected yet).

import bundled from '../../assets/kernel/kernel-bundle.json';

export interface Sourced {
  src: string;
}

export interface KernelSubindustry extends Sourced {
  code: string;
  name: string;
  selectable: boolean;
}

export interface KernelIndustry extends Sourced {
  code: string;
  name: string;
  regime: 'OHSA' | 'MHSA' | 'DUAL';
  sic_reference: string | null;
  subindustries: KernelSubindustry[];
  triggers: { overlay: (Sourced & { code: string })[]; typical: (Sourced & { code: string })[] };
  place_types: string[];
  suggested_places: (Sourced & { place_type: string })[];
  suggested_departments: (Sourced & { code: string })[];
  template_codes: string[];
  sample_company: Sourced & { name: string; scope: string; sites: number; headcount: number };
}

export interface KernelPlaceType extends Sourced {
  code: string;
  label: string;
  icon: string;
  root: boolean;
  rule: { always?: boolean; industries?: string[]; triggers?: string[]; subindustries?: string[] };
  why: string;
  children: string[];
}

export interface KernelTemplateItem extends Sourced {
  id: string;
  ordinal: number;
  section_label: string;
  prompt: string;
  kernel_ref: string;
  conditional?: boolean;
}

export interface KernelTemplate extends Sourced {
  id: string;
  code: string;
  kind: 'register' | 'industry';
  name: string;
  category: string;
  section_f_element_code: string | null;
  industry_code: string | null;
  trigger_code: string | null;
  responsible: string | null;
  interval: Sourced & { cadence: string | null; set_by?: 'competent_person' };
  retention: Sourced & { class: string; text: string };
  basis: (Sourced & { name: string; status: string })[];
  basis_state: string;
  description: string;
  suggested_department: string | null;
  items: KernelTemplateItem[];
}

export interface KernelBundle {
  schema: string;
  kernel: Sourced & { name: string; version: string; released_on: string | null; bundle_built_on: string; ratified: boolean; guidance_version: string; counts: Record<string, number>; note: string };
  limits: { place_max_depth: number };
  departments: (Sourced & { code: string; name: string })[];
  triggers: (Sourced & { code: string; description: string })[];
  place_types: KernelPlaceType[];
  industries: KernelIndustry[];
  templates: KernelTemplate[];
  excluded: (Sourced & { element: string; industry: string; reason: string })[];
}

/** The words shown wherever the kernel holds no verified value (an interval, a retention period, a threshold). */
export const SET_BY_COMPETENT_PERSON = 'Set by your competent person';

let current: KernelBundle = bundled as unknown as KernelBundle;
const listeners = new Set<() => void>();

export function kernel(): KernelBundle {
  return current;
}

export function onKernelChange(l: () => void): () => void {
  listeners.add(l);
  return () => listeners.delete(l);
}

/**
 * Hook for the kernel service (KERNEL-API.md). NOT CONNECTED: the app ships the
 * bundle built from the repository; when the service exists, pass a fetcher
 * that returns a newer bundle of the same schema. A bundle of another schema, an
 * older version or fewer than 17 industries is refused and the bundled copy stays.
 */
export async function refreshKernel(fetcher?: () => Promise<unknown>): Promise<{ updated: boolean; reason: string }> {
  if (!fetcher) return { updated: false, reason: 'The kernel service is not connected yet; the bundled kernel is in use.' };
  const next = (await fetcher()) as KernelBundle;
  if (!next || next.schema !== current.schema) return { updated: false, reason: 'The kernel service sent a bundle this app cannot read.' };
  if (!Array.isArray(next.industries) || next.industries.length < 17) return { updated: false, reason: 'The kernel service sent an incomplete bundle.' };
  if (compareVersions(next.kernel.version, current.kernel.version) <= 0) return { updated: false, reason: 'The bundled kernel is already current.' };
  current = next;
  for (const l of listeners) l();
  return { updated: true, reason: `Kernel ${next.kernel.version} is now in use.` };
}

/** For tests only: put the bundled copy back. */
export function resetKernel(): void {
  current = bundled as unknown as KernelBundle;
}

export function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d) return d;
  }
  return 0;
}

// Lookups -------------------------------------------------------------------------------

export function industry(b: KernelBundle, code: string | null | undefined): KernelIndustry | undefined {
  return code ? b.industries.find((i) => i.code === code) : undefined;
}

export function placeType(b: KernelBundle, code: string | null | undefined): KernelPlaceType | undefined {
  return code ? b.place_types.find((p) => p.code === code) : undefined;
}

export function template(b: KernelBundle, code: string): KernelTemplate | undefined {
  return b.templates.find((t) => t.code === code);
}

export function departmentName(b: KernelBundle, code: string | null | undefined): string | null {
  return code ? (b.departments.find((d) => d.code === code)?.name ?? null) : null;
}

export function triggerText(b: KernelBundle, code: string): string {
  return b.triggers.find((t) => t.code === code)?.description ?? code;
}

/** The triggers an industry raises: those its overlay switches on and those its sample assessment raised. */
export function industryTriggers(ind: KernelIndustry | undefined): Set<string> {
  if (!ind) return new Set();
  return new Set([...ind.triggers.overlay.map((t) => t.code), ...ind.triggers.typical.map((t) => t.code)]);
}

// Place types -------------------------------------------------------------------------------

/**
 * The place types the app offers for an industry (and optionally a
 * subindustry): the bundle's list for the industry, plus a type whose rule
 * names the subindustry. With no industry, every type.
 */
export function placeTypesFor(b: KernelBundle, industryCode: string | null | undefined, subindustryCode?: string | null): KernelPlaceType[] {
  const ind = industry(b, industryCode);
  if (!ind) return b.place_types;
  const codes = new Set(ind.place_types);
  if (subindustryCode) for (const pt of b.place_types) if (pt.rule.subindustries?.includes(subindustryCode)) codes.add(pt.code);
  return b.place_types.filter((p) => codes.has(p.code));
}

/** Types offered under a parent (or at the top when parentType is null) for the industry. */
export function childTypesFor(b: KernelBundle, parentType: string | null, industryCode: string | null | undefined, subindustryCode?: string | null): KernelPlaceType[] {
  const offered = placeTypesFor(b, industryCode, subindustryCode);
  if (!parentType) return offered.filter((p) => p.root);
  const parent = placeType(b, parentType);
  if (!parent) return [];
  return offered.filter((p) => parent.children.includes(p.code));
}

/** The triggers that make a template relevant to a kind of place (the place type's own rule). */
export function placeAffinity(b: KernelBundle, placeTypeCode: string | null | undefined): Set<string> {
  return new Set(placeType(b, placeTypeCode)?.rule.triggers ?? []);
}

// Templates ---------------------------------------------------------------------------------

export function registerAppliesTo(t: KernelTemplate, triggers: Set<string>): boolean {
  return t.kind === 'register' && (!t.trigger_code || triggers.has(t.trigger_code));
}

export interface TemplateChoice {
  template: KernelTemplate;
  score: number;
  why: string;
}

export interface TemplatePick {
  /** Suggested for this industry and kind of place, best first. */
  suggested: TemplateChoice[];
  /** Every Section F register: available everywhere, whatever the industry. */
  registers: KernelTemplate[];
}

function matchesQuery(t: KernelTemplate, q: string): boolean {
  if (!q) return true;
  const hay = `${t.name} ${t.code} ${t.section_f_element_code ?? ''} ${t.items.map((i) => i.prompt).join(' ')}`.toLowerCase();
  return q
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .every((w) => hay.includes(w));
}

/**
 * The template picker's lists. Suggested: the industry walkthrough (always,
 * when the industry has one), then the Section F registers this industry's
 * triggers switch on, ranked up when the kind of place carries the same
 * trigger (a workshop and machine guarding, a warehouse and stacking). Every
 * Section F register stays available everywhere in the second list.
 */
export function templatesFor(b: KernelBundle, p: { industryCode?: string | null; placeTypeCode?: string | null; query?: string }): TemplatePick {
  const ind = industry(b, p.industryCode);
  const trig = industryTriggers(ind);
  const affinity = placeAffinity(b, p.placeTypeCode);
  const q = (p.query ?? '').trim();
  const suggested: TemplateChoice[] = [];
  for (const t of b.templates) {
    if (!matchesQuery(t, q)) continue;
    if (t.kind === 'industry') {
      if (ind && t.industry_code === ind.code) suggested.push({ template: t, score: 100, why: `${ind.name} checks from the kernel` });
      continue;
    }
    if (!ind) continue;
    const place = !!t.trigger_code && affinity.has(t.trigger_code);
    const industrySpecific = !!t.trigger_code && trig.has(t.trigger_code);
    if (place) suggested.push({ template: t, score: 50 + (industrySpecific ? 10 : 0), why: 'Suits this kind of place' });
    else if (industrySpecific) suggested.push({ template: t, score: 20, why: `${ind.name} raises this register` });
  }
  suggested.sort((a, b2) => b2.score - a.score || a.template.name.localeCompare(b2.template.name));
  const registers = b.templates.filter((t) => t.kind === 'register' && matchesQuery(t, q)).sort((a, b2) => (a.section_f_element_code ?? '').localeCompare(b2.section_f_element_code ?? ''));
  return { suggested, registers };
}

/** "Monthly", or "Set by your competent person" when the kernel holds no verified interval. */
export function intervalText(t: Pick<KernelTemplate, 'interval'>): string {
  return t.interval.cadence ?? SET_BY_COMPETENT_PERSON;
}

/** The plain words for an instrument's state in the kernel. */
export function basisText(t: Pick<KernelTemplate, 'basis'>): string {
  if (!t.basis.length) return SET_BY_COMPETENT_PERSON;
  return t.basis.map((x) => `${x.name}${x.status === 'verified' ? '' : ' (verification pending)'}`).join('; ');
}
