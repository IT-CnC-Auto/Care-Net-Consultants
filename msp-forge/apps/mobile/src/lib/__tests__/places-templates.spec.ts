// The places tree rules (the same as bi_place_guard, migration 065), the switcher
// search and recent places, and the template picker's filtering by industry and
// kind of place.

import { childTypesFor, intervalText, basisText, kernel, placeTypesFor, refreshKernel, resetKernel, SET_BY_COMPETENT_PERSON, templatesFor } from '../kernel';
import { breadcrumb, checkPlace, childrenOf, depthOf, pathOf, pushRecent, RECENT_MAX, rootOf, searchPlaces, slug } from '../places';
import type { Place } from '../types';

const b = kernel();
const CO = 'co-1';
const OTHER = 'co-2';
const place = (id: string, parent: string | null, type: string, name: string, company = CO, extra: Partial<Place> = {}): Place => ({
  id, client_account_id: company, parent_id: parent, place_type: type, custom_type_label: null, name, address: null, gps_lat: null, gps_lng: null,
  responsible_person: null, headcount: null, department_code: null, linked_department_ids: [], archived_at: null, ...extra,
});
const TREE: Place[] = [
  place('site', null, 'site', 'Rietvlei Yard'),
  place('ops', 'site', 'department', 'Site operations'),
  place('block', 'ops', 'building_block', 'Workshop block'),
  place('floor', 'block', 'floor', 'Ground floor'),
  place('room', 'floor', 'room_area', 'Workshop floor'),
  place('pit', null, 'mine_section', 'Open pit', OTHER),
  place('old', 'site', 'room_area', 'Old store', CO, { archived_at: '2026-01-01T00:00:00Z' }),
];

describe('the places tree rules', () => {
  it('accepts a sound child and a top level place of a root type', () => {
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: 'floor', place_type: 'room_area', name: 'Store room' })).toEqual({ ok: true, reasons: [] });
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: null, place_type: 'farm', name: 'Citrus estate' }).ok).toBe(true);
  });
  it('keeps rooms, floors, buildings and departments off the top level', () => {
    for (const t of ['room_area', 'floor', 'building_block', 'department']) {
      const r = checkPlace(b, TREE, { client_account_id: CO, parent_id: null, place_type: t, name: 'X' });
      expect(r.ok).toBe(false);
      expect(r.reasons[0]).toMatch(/not at the top/);
    }
  });
  it('allows only the types a parent allows (nothing under a room; no office under a floor)', () => {
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: 'room', place_type: 'room_area', name: 'Cupboard' }).reasons[0]).toMatch(/cannot go under a room or area/);
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: 'floor', place_type: 'office', name: 'Office' }).reasons[0]).toMatch(/cannot go under a floor/);
  });
  it('keeps a place with its own company', () => {
    expect(checkPlace(b, TREE, { client_account_id: OTHER, parent_id: 'site', place_type: 'department', name: 'Stolen' }).reasons).toContain('A place stays with its own company.');
  });
  it('refuses loops when a place moves', () => {
    expect(checkPlace(b, TREE, { id: 'ops', client_account_id: CO, parent_id: 'room', place_type: 'department', name: 'Site operations' }).reasons.join(' ')).toMatch(/under itself/);
    expect(checkPlace(b, TREE, { id: 'ops', client_account_id: CO, parent_id: 'ops', place_type: 'department', name: 'Site operations' }).ok).toBe(false);
  });
  it('stops at the bundle’s depth limit of 8 levels', () => {
    expect(b.limits.place_max_depth).toBe(8);
    const deep: Place[] = [place('d1', null, 'site', 'L1')];
    for (let i = 2; i <= 8; i++) deep.push(place(`d${i}`, `d${i - 1}`, 'department', `L${i}`));
    expect(depthOf(deep, 'd8')).toBe(8);
    expect(checkPlace(b, deep, { client_account_id: CO, parent_id: 'd8', place_type: 'department', name: 'L9' }).reasons).toContain('Keep the tree to 8 levels.');
    expect(checkPlace(b, deep, { client_account_id: CO, parent_id: 'd7', place_type: 'department', name: 'L8b' }).ok).toBe(true);
  });
  it('refuses a sibling with the same name, ignoring case and spaces, but not an archived one or a cousin', () => {
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: 'site', place_type: 'department', name: '  site   OPERATIONS ' }).reasons).toContain('There is already a place with this name here.');
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: 'site', place_type: 'room_area', name: 'Old store' }).ok).toBe(true);
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: 'ops', place_type: 'department', name: 'Site operations' }).ok).toBe(true);
  });
  it('needs a name of 1 to 200 characters and a known type', () => {
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: null, place_type: 'site', name: '  ' }).ok).toBe(false);
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: null, place_type: 'site', name: 'x'.repeat(201) }).ok).toBe(false);
    expect(checkPlace(b, TREE, { client_account_id: CO, parent_id: null, place_type: 'spaceship', name: 'X' }).reasons).toContain('Choose what kind of place it is.');
  });
  it('walks paths, roots, breadcrumbs and children (archived places left out)', () => {
    expect(pathOf(TREE, 'room').map((p) => p.id)).toEqual(['site', 'ops', 'block', 'floor', 'room']);
    expect(rootOf(TREE, 'room')?.id).toBe('site');
    expect(breadcrumb(TREE, 'room', 'Rietvlei Civils')).toEqual(['Rietvlei Civils', 'Rietvlei Yard', 'Site operations', 'Workshop block', 'Ground floor', 'Workshop floor']);
    expect(childrenOf(TREE, 'site', CO).map((p) => p.id)).toEqual(['ops']);
    expect(pathOf([place('a', 'b', 'site', 'A'), place('b', 'a', 'site', 'B')], 'a')).toHaveLength(2);
  });
  it('makes stable path segments for the canonical evidence path', () => {
    expect(slug('Workshop floor')).toBe('workshop-floor');
    expect(slug('  Café & Bar (No. 2) ')).toBe('cafe-bar-no-2');
    expect(slug('***')).toBe('place');
  });
});

describe('the switcher: instant search and recent places', () => {
  const companies = [{ id: CO, legal_name: 'Rietvlei Civils and Building (Pty) Ltd', trading_name: 'Rietvlei Civils' }, { id: OTHER, legal_name: 'Magaliesberg Aggregates (Pty) Ltd', trading_name: null }];
  it('matches the start of any word of the name, type or path; names first; the active company first', () => {
    const hits = searchPlaces(b, TREE, companies, 'work fl', CO);
    expect(hits[0]).toMatchObject({ kind: 'place', id: 'room', title: 'Workshop floor', path: 'Rietvlei Civils › Rietvlei Yard › Site operations › Workshop block › Ground floor' });
    expect(searchPlaces(b, TREE, companies, 'quarry', CO).map((h) => h.id)).toEqual(['pit']);
    expect(searchPlaces(b, TREE, companies, 'magalies', CO)[0]).toMatchObject({ kind: 'company', id: OTHER });
    expect(searchPlaces(b, TREE, companies, 'old store', CO)).toHaveLength(0);
    expect(searchPlaces(b, TREE, companies, 'zzz', CO)).toHaveLength(0);
  });
  it('keeps recent places most recent first, without repeats, up to 8', () => {
    let r: string[] = [];
    for (const id of ['a', 'b', 'c', 'a']) r = pushRecent(r, id);
    expect(r).toEqual(['a', 'c', 'b']);
    for (let i = 0; i < 20; i++) r = pushRecent(r, `p${i}`);
    expect(r).toHaveLength(RECENT_MAX);
    expect(r[0]).toBe('p19');
  });
});

describe('place types offered per industry', () => {
  it('offers a farm only to agriculture, a mine or quarry section only to mining, a school campus only to education', () => {
    const offered = (code: string) => placeTypesFor(b, code).map((p) => p.code);
    expect(b.industries.filter((i) => offered(i.code).includes('farm')).map((i) => i.code)).toEqual(['AGRI']);
    expect(b.industries.filter((i) => offered(i.code).includes('mine_section')).map((i) => i.code)).toEqual(['MINING']);
    expect(b.industries.filter((i) => offered(i.code).includes('school_campus')).map((i) => i.code)).toEqual(['EDU']);
    for (const i of b.industries) for (const u of ['site', 'office', 'branch', 'department', 'building_block', 'floor', 'room_area']) expect(offered(i.code)).toContain(u);
  });
  it('adds a type a subindustry calls for (a service station is a retail store)', () => {
    expect(placeTypesFor(b, 'PETRO', 'PETRO-RETAIL').map((p) => p.code)).toContain('retail_store');
    expect(placeTypesFor(b, 'TRANS', 'TRANS-WARE').map((p) => p.code)).toContain('warehouse');
  });
  it('offers under a parent only what the parent allows, and at the top only root types', () => {
    expect(childTypesFor(b, null, 'MINING').every((p) => p.root)).toBe(true);
    expect(childTypesFor(b, 'floor', 'MINING').map((p) => p.code)).toEqual(['department', 'room_area']);
    expect(childTypesFor(b, 'room_area', 'MINING')).toEqual([]);
  });
});

describe('the template picker', () => {
  const codes = (p: ReturnType<typeof templatesFor>) => p.suggested.map((s) => s.template.code);
  it('puts the industry walkthrough first for every one of the 17 industries', () => {
    for (const i of b.industries) expect(codes(templatesFor(b, { industryCode: i.code }))[0]).toBe(`IND-${i.code}`);
  });
  it('ranks the registers the kind of place carries: machine guarding in a mining workshop, stacking in a retail warehouse', () => {
    const mine = codes(templatesFor(b, { industryCode: 'MINING', placeTypeCode: 'workshop' }));
    expect(mine.slice(0, 3)).toEqual(expect.arrayContaining(['IND-MINING', 'REG-F-14']));
    const retail = codes(templatesFor(b, { industryCode: 'RETAIL', placeTypeCode: 'warehouse' }));
    expect(retail.slice(0, 2)).toEqual(['IND-RETAIL', 'REG-F-16']);
    const lab = codes(templatesFor(b, { industryCode: 'HEALTH', placeTypeCode: 'clinic_lab' }));
    expect(lab[0]).toBe('IND-HEALTH');
    expect(lab).toContain('REG-F-12');
  });
  it('never suggests a register the industry does not raise (no scaffold register for an office)', () => {
    const office = codes(templatesFor(b, { industryCode: 'OFFICE', placeTypeCode: 'office' }));
    expect(office).toContain('IND-OFFICE');
    expect(office).not.toContain('REG-F-01');
    expect(office).not.toContain('IND-CONSTR');
  });
  it('keeps every Section F register available everywhere, sorted by element', () => {
    for (const i of [null, ...b.industries.map((x) => x.code)]) {
      const regs = templatesFor(b, { industryCode: i }).registers;
      expect(regs).toHaveLength(22);
      expect(regs[0].section_f_element_code).toBe('HSF-F-01');
    }
  });
  it('filters by every word of the query, over names and checklist lines', () => {
    const p = templatesFor(b, { industryCode: 'CONSTR', query: 'ladder register' });
    expect(p.registers.map((t) => t.code)).toEqual(['REG-F-02']);
    expect(templatesFor(b, { industryCode: 'CONSTR', query: 'zzzz' })).toEqual({ suggested: [], registers: [] });
  });
  it('shows "Set by your competent person" where the kernel holds no verified interval or basis', () => {
    const f02 = b.templates.find((t) => t.code === 'REG-F-02');
    const f15 = b.templates.find((t) => t.code === 'REG-F-15');
    expect(intervalText(f02!)).toBe(SET_BY_COMPETENT_PERSON);
    expect(intervalText(f15!)).toBe('Monthly');
    expect(basisText(b.templates.find((t) => t.code === 'IND-MINING')!)).toBe(SET_BY_COMPETENT_PERSON);
    expect(basisText(b.templates.find((t) => t.code === 'REG-F-05')!)).toMatch(/verification pending/);
  });
});

describe('the kernel refresh hook', () => {
  afterEach(() => resetKernel());
  it('keeps the bundled kernel while no service is connected, and refuses an older or incomplete bundle', async () => {
    expect((await refreshKernel()).updated).toBe(false);
    expect((await refreshKernel(async () => ({ ...b, kernel: { ...b.kernel, version: '0.9.0' } }))).updated).toBe(false);
    expect((await refreshKernel(async () => ({ ...b, industries: b.industries.slice(0, 5), kernel: { ...b.kernel, version: '9.0.0' } }))).updated).toBe(false);
    expect((await refreshKernel(async () => ({ ...b, schema: 'other' }))).updated).toBe(false);
  });
  it('takes a newer bundle of the same schema', async () => {
    const r = await refreshKernel(async () => ({ ...b, kernel: { ...b.kernel, version: '1.2.0' } }));
    expect(r.updated).toBe(true);
    expect(kernel().kernel.version).toBe('1.2.0');
  });
});
