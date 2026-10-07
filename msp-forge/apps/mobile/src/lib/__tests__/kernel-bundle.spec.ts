/// <reference types="node" />
// The kernel bundle (assets/kernel/kernel-bundle.json) against the repository's
// own kernel sources: all 17 industries are present, and nothing in it is
// invented. Every item carries a source id that resolves in the repository.

import { readdirSync, readFileSync } from 'fs';
import path from 'path';

import { kernel, industryTriggers, placeTypesFor, type KernelBundle } from '../kernel';

const ROOT = path.resolve(__dirname, '../../../../..');
const read = (p: string) => readFileSync(path.join(ROOT, p), 'utf8');
const MIGRATIONS = readdirSync(path.join(ROOT, 'supabase/migrations'))
  .filter((f) => /^\d{3}_.*\.sql$/.test(f) && Number(f.slice(0, 3)) <= 64)
  .map((f) => read(`supabase/migrations/${f}`))
  .join('\n');
const GUIDANCE = JSON.parse(read('hsf/guidance/guidance.json')) as { elements: Record<string, Record<string, unknown>>; meta: { version: string } };
const SPEC_B = read('SPEC.md').split('# PART B. CNC HSF FORGE')[1];
const b: KernelBundle = kernel();

function samples(): Record<string, { company: string; scope: string; sites: number; headcount: number; triggers: string[]; file: string }> {
  const dir = path.join(ROOT, 'vercel/hsf/samples');
  const out: Record<string, { company: string; scope: string; sites: number; headcount: number; triggers: string[]; file: string }> = {};
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.js'))) {
    const text = readFileSync(path.join(dir, f), 'utf8');
    const s = JSON.parse(text.slice(text.indexOf('=') + 1).trim().replace(/;\s*$/, ''));
    out[s.code] = { company: s.company, scope: s.scope, sites: s.sites, headcount: s.headcount, triggers: s.triggers, file: `vercel/hsf/samples/${f}` };
  }
  return out;
}

// The industry codes as the kernel migrations insert them: ('CODE', 'Name', 'SIC ...', 'OHSA|MHSA').
const MIGRATION_INDUSTRIES = new Map(Array.from(MIGRATIONS.matchAll(/\('([A-Z]+)',\s*'([^']+)',\s*'SIC[^']*',\s*'(OHSA|MHSA|DUAL)'\)/g)).map((m) => [m[1], { name: m[2], regime: m[3] }]));

describe('the kernel bundle: 17 industries, nothing invented', () => {
  it('has the schema, the kernel version of the latest release and its date', () => {
    expect(b.schema).toBe('bee-inspect.kernel-bundle.v1');
    const releases = Array.from(MIGRATIONS.matchAll(/insert into msp_kernel_version \(semver[^)]*\)\s*values \('(\d+\.\d+\.\d+)',\s*'([^']*)'/g)).map((m) => ({ v: m[1], summary: m[2] }));
    const latest = releases.sort((x, y) => y.v.localeCompare(x.v, undefined, { numeric: true }))[0];
    expect(b.kernel.version).toBe(latest.v);
    const d = /release (\d{2})\/(\d{2})\/(\d{4})/.exec(latest.summary);
    expect(b.kernel.released_on).toBe(d ? `${d[3]}-${d[2]}-${d[1]}` : null);
    expect(b.kernel.src).toBe(`msp_kernel_version:${b.kernel.version}`);
    expect(b.kernel.ratified).toBe(false);
    expect(b.kernel.guidance_version).toBe(GUIDANCE.meta.version);
  });

  it('holds exactly the 17 kernel industries, with their names and regimes from the migrations, the File pricing codes and a sample company each', () => {
    expect(b.industries).toHaveLength(17);
    expect(MIGRATION_INDUSTRIES.size).toBe(17);
    const priced = Array.from(read('vercel/hsf/pricing.js').matchAll(/"code":\s*"([A-Z]+)"/g)).map((m) => m[1]);
    const s = samples();
    for (const i of b.industries) {
      expect(MIGRATION_INDUSTRIES.get(i.code)).toEqual({ name: i.name, regime: i.regime });
      expect(i.src).toBe(`msp_industry:${i.code}`);
      expect(priced).toContain(i.code);
      expect(s[i.code]).toBeDefined();
      expect(i.sample_company).toMatchObject({ name: s[i.code].company, scope: s[i.code].scope, sites: s[i.code].sites, headcount: s[i.code].headcount });
    }
    expect(new Set(b.industries.map((i) => i.code))).toEqual(new Set(priced));
  });

  it('lists every subindustry the kernel inserts, 56 in all, and invents none', () => {
    const all = b.industries.flatMap((i) => i.subindustries.map((s) => ({ ...s, industry: i.code })));
    expect(all).toHaveLength(56);
    for (const s of all) {
      expect(s.src).toBe(`msp_subindustry:${s.code}`);
      // Inserted by a kernel migration as ('CODE', 'Name', ...) or ('IND', 'CODE', 'Name', ...).
      const name = s.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      expect(MIGRATIONS).toMatch(new RegExp(`(?:\\(|\\('${s.industry}',\\s*)'${s.code}',\\s*'${name}'`));
    }
  });

  it('takes the triggers from the trigger library, and each industry’s triggers from its overlay or its sample assessment', () => {
    expect(b.triggers.length).toBeGreaterThanOrEqual(40);
    for (const t of b.triggers) expect(MIGRATIONS).toContain(`'${t.code}'`);
    const known = new Set(b.triggers.map((t) => t.code));
    const s = samples();
    for (const i of b.industries) {
      for (const t of i.triggers.typical) {
        expect(s[i.code].triggers).toContain(t.code);
        expect(t.src).toBe(`${s[i.code].file}#triggers`);
      }
      for (const t of [...i.triggers.overlay, ...i.triggers.typical]) expect(known.has(t.code)).toBe(true);
    }
  });

  it('builds every checklist line from a kernel source that resolves to the same words', () => {
    let lines = 0;
    for (const t of b.templates) {
      for (const it of t.items) {
        lines++;
        const g = /^guidance:(HSF-[A-Z0-9-]+)#(what_to_submit|common_gaps)\[(\d+)\]$/.exec(it.src);
        const o = /^hsf_element_industry:(HSF-[A-Z0-9-]+)@([A-Z]+)$/.exec(it.src);
        if (g) {
          const list = GUIDANCE.elements[g[1]]?.[g[2]] as string[] | undefined;
          expect(list?.[Number(g[3])]).toBe(it.prompt);
          expect(it.kernel_ref).toBe(g[1]);
        } else if (o) {
          expect(it.kernel_ref).toBe(o[1]);
          expect(t.industry_code).toBe(o[2]);
          // The element is in the element library (SPEC Part B tables or the migrations).
          expect(SPEC_B.includes(`| ${o[1]} |`) || MIGRATIONS.includes(`'${o[1]}'`)).toBe(true);
        } else {
          throw new Error(`Untraceable line ${it.src}`);
        }
      }
    }
    expect(lines).toBe(346);
  });

  it('has a Section F register template for each of the 22 Section F elements and a walkthrough for each industry', () => {
    const regs = b.templates.filter((t) => t.kind === 'register');
    expect(regs).toHaveLength(22);
    for (const r of regs) {
      expect(r.section_f_element_code).toMatch(/^HSF-F-\d\d$/);
      expect(r.src).toBe(`hsf_element:${r.section_f_element_code}`);
      expect(SPEC_B).toContain(`| ${r.section_f_element_code} | ${r.name} |`);
    }
    for (const i of b.industries) expect(b.templates.filter((t) => t.kind === 'industry' && t.industry_code === i.code)).toHaveLength(1);
  });

  it('never invents an interval or a retention period: a cadence only where the element library holds one, else the competent person sets it', () => {
    const cadenceOf: Record<string, string> = { daily: 'Daily', monthly: 'Monthly', before_use: 'Before each use', on_change: 'When anything changes', per_event: 'Each time it is used' };
    for (const t of b.templates.filter((x) => x.kind === 'register')) {
      const row = new RegExp(`^\\| ${t.section_f_element_code} \\| .*? \\| .*? \\| .*? \\| .*? \\| (\\w+) \\| (\\w[\\w-]*) \\|`, 'm').exec(SPEC_B);
      expect(row).not.toBeNull();
      const review = (row as RegExpExecArray)[1];
      expect(t.interval.cadence).toBe(cadenceOf[review] ?? null);
      if (!t.interval.cadence) expect(t.interval.set_by).toBe('competent_person');
      expect(t.retention.text).not.toMatch(/\d+ (year|month|day)/);
    }
    for (const t of b.templates.filter((x) => x.kind === 'industry')) expect(t.interval.cadence).toBeNull();
  });

  it('keeps the house rules on every line people see', () => {
    const texts = [
      ...b.templates.flatMap((t) => [t.name, t.description, ...t.items.map((i) => i.prompt), ...t.items.map((i) => i.section_label), ...t.basis.map((x) => x.name)]),
      ...b.triggers.map((t) => t.description),
      ...b.place_types.map((p) => `${p.label} ${p.why}`),
    ];
    for (const t of texts) {
      const probe = t.replace(/\b(?:[Ss]ection )?(?:16\((?:1|2)\)|37\(2\))/g, '');
      expect(probe).not.toMatch(/\b(?:[Ss]ections? \d|[Rr]egulations? \d|[Aa]nnexure \d|GNR? ?\d|GN R|R\.? ?\d{3})/);
      expect(t).not.toMatch(/\bcompliant\b|\bguarantee/i);
      expect(t).not.toMatch(/[‐-―]|\s-\s/);
      expect(t).not.toMatch(/\b(?:msp|hsf|bi)_[a-z_]+|FORGE|sandbox/i);
    }
  });

  it('keeps medical fitness and surveillance out of every inspection line', () => {
    const excluded = new Set(b.excluded.map((e) => e.element));
    for (const t of b.templates) {
      for (const it of t.items) {
        expect(excluded.has(it.kernel_ref)).toBe(false);
        expect(it.kernel_ref).not.toMatch(/^HSF-E-/);
        expect(it.prompt).not.toMatch(/\b(?:medical|fitness|examination|immunisation|surveillance|clinical|diagnos)/i);
      }
    }
    expect(b.excluded.length).toBeGreaterThan(0);
  });

  it('offers place types by rules that name only kernel codes, and each industry’s list follows those rules', () => {
    const codes = new Set(b.industries.map((i) => i.code));
    const subs = new Set(b.industries.flatMap((i) => i.subindustries.map((s) => s.code)));
    const trig = new Set(b.triggers.map((t) => t.code));
    for (const pt of b.place_types) {
      for (const c of pt.rule.industries ?? []) expect(codes.has(c)).toBe(true);
      for (const c of pt.rule.subindustries ?? []) expect(subs.has(c)).toBe(true);
      for (const c of pt.rule.triggers ?? []) expect(trig.has(c)).toBe(true);
      for (const c of pt.children) expect(b.place_types.some((p) => p.code === c)).toBe(true);
    }
    for (const i of b.industries) {
      const t = industryTriggers(i);
      const expected = b.place_types
        .filter((pt) => pt.rule.always || pt.rule.industries?.includes(i.code) || pt.rule.triggers?.some((c) => t.has(c)) || pt.rule.subindustries?.some((c) => i.subindustries.some((s) => s.code === c)))
        .map((p) => p.code);
      expect(i.place_types).toEqual(expected);
      expect(placeTypesFor(b, i.code).map((p) => p.code)).toEqual(expected);
      expect(i.suggested_departments[0].code).toBe('SHE');
      for (const d of i.suggested_departments) expect(b.departments.some((x) => x.code === d.code)).toBe(true);
    }
  });

  it('agrees with migration 065 on the place types and what may sit under each', () => {
    const sql = read('supabase/migrations/065_bi_places_evidence.sql');
    const rows = Array.from(sql.matchAll(/\('([a-z_]+)', '([^']+)', (true|false), '\{([a-z_,]*)\}', (\d+)\)/g)).map((m) => ({ code: m[1], label: m[2], root: m[3] === 'true', children: m[4] ? m[4].split(',') : [] }));
    expect(rows).toHaveLength(b.place_types.length);
    for (const pt of b.place_types) expect(rows.find((r) => r.code === pt.code)).toEqual({ code: pt.code, label: pt.label, root: pt.root, children: pt.children });
  });

  it('matches the server seed: every template and item id is in supabase/seed/bee_inspect_kernel_templates.sql', () => {
    const seed = read('supabase/seed/bee_inspect_kernel_templates.sql');
    const ids = new Set<string>();
    for (const t of b.templates) {
      expect(seed).toContain(`'${t.id}'`);
      ids.add(t.id);
      for (const it of t.items) {
        expect(seed).toContain(`'${it.id}'`);
        ids.add(it.id);
      }
    }
    for (const id of ids) expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(ids.size).toBe(b.templates.length + 346);
  });
});
