"""CNC HSF FORGE | guidance for a first Health and Safety File (contract 12).

Merges the guidance fragments in hsf/guidance/fragment-*.json into one
document and writes, from that one document:

  hsf/guidance/guidance.json            the merged source of truth (12.1)
  supabase/migrations/055_hsf_guidance.sql
                                        the guidance tables, their rows, row
                                        level security and hsf_public_guidance
                                        (12.3); never edited by hand
  vercel/hsf/guidance.js                window.CNC_HSF_GUIDANCE for the builder
                                        and the sample File (12.4)

The worklist hsf/guidance/worklist.json is the list of every code the library
holds (sections 15, elements 256, appointments 41, classes 34). The build
refuses, and writes nothing, when:
  - a fragment carries a code the worklist does not know, or a code twice;
  - a worklist code has no guidance;
  - an entry does not have the contract 12.1 shape (2 to 5 items to submit,
    a reason, an example marked as an example, 0 to 3 common gaps, a known
    department where one is named, suggested_department only on elements);
  - any text carries a section, regulation, annexure, schedule or Gazette
    number, or another provision number, other than section 16(2) and
    section 37(2) of the OHS Act (contract 7 and 12.2);
  - any text breaks a house rule the build can check mechanically
    ("compliant", "guarantee", dash punctuation, the NIHL Regulations, 2003
    or the Environmental Regulations for Workplaces, 1987).

Deterministic: the same fragments always give byte identical outputs (keys in
worklist order, no timestamps).

Run from msp-forge/:   python3 hsf/build_guidance.py
Check only:            python3 hsf/build_guidance.py --check
                       (exit 1 when an output is missing or out of date)
Validate other input:  python3 hsf/build_guidance.py --validate --dir <folder>
                       (reads fragment-*.json and worklist.json from <folder>,
                       writes nothing; exit 2 on a refusal; used by the tests)
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUIDE = ROOT / 'hsf' / 'guidance'
WORKLIST = GUIDE / 'worklist.json'
OUT_JSON = GUIDE / 'guidance.json'
OUT_SQL = ROOT / 'supabase' / 'migrations' / '055_hsf_guidance.sql'
OUT_JS = ROOT / 'vercel' / 'hsf' / 'guidance.js'

DEPARTMENTS = ['EXEC', 'HR', 'SHE', 'OPS', 'ENG', 'PROC', 'OH', 'TRAIN', 'FAC']  # contract section 2
KINDS = ('elements', 'appointments', 'classes')
SINGULAR = {'sections': 'section', 'elements': 'element', 'appointments': 'appointment', 'classes': 'class'}
ITEM_KEYS = ('what_to_submit', 'why', 'example', 'common_gaps')
SECTION_KEYS = ('intro', 'what_goes_here', 'who_usually_holds', 'first_file_tips')
META = {'version': 'HSF-GUIDE-1.0', 'status': 'draft', 'reviewed_by': None}

# Contract section 7 and 12.2: no provision numbers other than section 16(2)
# and section 37(2). The same pattern is in test/sql/hsf_guidance_checks.sql.
ALLOWED_NUMBERS = re.compile(r'\b(?:16|37)\(2\)')
NUMBERED = re.compile(
    r'\b(?:sections? \d|ss?\. ?\d|subsections? \(?\d|regulations? \d|regs?\.? ?\d'
    r'|annexures? (?:\d|[a-z]\b)|schedules? \d|gnr? ?\d|gn r\b|gg ?\d|gazette (?:no\.? ?)?\d'
    r'|no\. ?\d+ of \d{4}|\d+ of (?:19|20)\d\d\b)'
    r'|\b\d+\(\d+\)|\(\d+\)\([a-z]\)', re.I)
GAZETTE_R = re.compile(r'\bR\.? ?\d{3}')
HOUSE_RULES = [
    (re.compile(r'\bcompliant\b', re.I), 'the word "compliant"'),
    (re.compile(r'\bguarantee', re.I), 'the word "guarantee"'),
    (re.compile(r'[‒–—―]'), 'dash punctuation'),
    (re.compile(r'\s-\s|\w-\w'), 'hyphen punctuation'),
    (re.compile(r'NIHL Regulations|Noise Induced Hearing Loss Regulations', re.I), 'the NIHL Regulations, 2003'),
    (re.compile(r'Environmental Regulations for Workplaces', re.I), 'the Environmental Regulations for Workplaces, 1987'),
]


class Refused(Exception):
    pass


def refuse(msg):
    raise Refused(msg)


def check_text(text, where):
    if not isinstance(text, str) or not text.strip():
        refuse('%s: empty or not text' % where)
    plain = ALLOWED_NUMBERS.sub('', text)
    m = NUMBERED.search(plain) or GAZETTE_R.search(plain)
    if m:
        refuse('%s: number pattern "%s" is not allowed (only section 16(2) and section 37(2)): %s' % (where, m.group(0), text))
    for rx, what in HOUSE_RULES:
        if rx.search(text):
            refuse('%s: %s is not allowed: %s' % (where, what, text))


def check_list(v, where, lo, hi):
    if not isinstance(v, list) or not (lo <= len(v) <= hi):
        refuse('%s: expected a list of %d to %d items, got %r' % (where, lo, hi, v if not isinstance(v, list) else len(v)))
    for i, t in enumerate(v):
        check_text(t, '%s[%d]' % (where, i + 1))


def check_keys(d, required, optional, where):
    if not isinstance(d, dict):
        refuse('%s: not an object' % where)
    missing = [k for k in required if k not in d]
    extra = sorted(set(d) - set(required) - set(optional))
    if missing:
        refuse('%s: missing %s' % (where, ', '.join(missing)))
    if extra:
        refuse('%s: unknown field %s' % (where, ', '.join(extra)))


def load_worklist():
    w = json.loads(WORKLIST.read_text(encoding='utf-8'))
    codes = {
        'sections': [s['code'] for s in w['sections']],
        'elements': [e['code'] for e in w['elements']],
        'appointments': [a['code'] for a in w['appointments']],
        'classes': [c['code'] for c in w['classes']],
    }
    for k, v in codes.items():
        if len(set(v)) != len(v):
            refuse('worklist: duplicate %s code' % k)
    return codes


def merge(codes):
    frags = sorted(GUIDE.glob('fragment-*.json'))
    if not frags:
        refuse('no fragment-*.json in hsf/guidance')
    merged = {'sections': {}, 'elements': {}, 'appointments': {}, 'classes': {}}
    single = {}
    for f in frags:
        d = json.loads(f.read_text(encoding='utf-8'))
        unknown_top = sorted(set(d) - {'meta', 'first_file', 'sections', 'elements', 'appointments', 'classes'})
        if unknown_top:
            refuse('%s: unknown top level key %s' % (f.name, ', '.join(unknown_top)))
        for top in ('meta', 'first_file'):
            if top in d:
                if top in single:
                    refuse('%s: %s already given in %s' % (f.name, top, single[top][0]))
                single[top] = (f.name, d[top])
        for kind in merged:
            for code, v in (d.get(kind) or {}).items():
                if code not in codes[kind]:
                    refuse('%s: unknown %s code %s' % (f.name, SINGULAR[kind], code))
                if code in merged[kind]:
                    refuse('%s: %s code %s is already in another fragment' % (f.name, SINGULAR[kind], code))
                merged[kind][code] = (f.name, v)
    for top in ('meta', 'first_file'):
        if top not in single:
            refuse('no fragment gives %s' % top)
    for kind in merged:
        missing = [c for c in codes[kind] if c not in merged[kind]]
        if missing:
            refuse('missing %s guidance for %d code(s): %s' % (SINGULAR[kind], len(missing), ', '.join(missing)))
    return merged, single


def build():
    codes = load_worklist()
    merged, single = merge(codes)

    meta_src, meta = single['meta']
    check_keys(meta, ('version', 'status', 'reviewed_by', 'note'), (), meta_src + ' meta')
    for k, v in META.items():
        if meta[k] != v:
            refuse('%s meta.%s must be %r' % (meta_src, k, v))
    check_text(meta['note'], 'meta.note')

    ff_src, ff = single['first_file']
    check_keys(ff, ('intro', 'order', 'before_you_start'), (), ff_src + ' first_file')
    check_text(ff['intro'], 'first_file.intro')
    check_list(ff['before_you_start'], 'first_file.before_you_start', 1, 12)
    if not isinstance(ff['order'], list):
        refuse('first_file.order: not a list')
    seen = []
    for i, step in enumerate(ff['order']):
        check_keys(step, ('section', 'reason'), (), 'first_file.order[%d]' % (i + 1))
        if step['section'] not in codes['sections']:
            refuse('first_file.order[%d]: unknown section %s' % (i + 1, step['section']))
        if step['section'] in seen:
            refuse('first_file.order[%d]: section %s twice' % (i + 1, step['section']))
        seen.append(step['section'])
        check_text(step['reason'], 'first_file.order[%d].reason' % (i + 1))
    if sorted(seen) != sorted(codes['sections']):
        refuse('first_file.order must name every section once; missing %s' % ', '.join(c for c in codes['sections'] if c not in seen))

    out = {
        'meta': {'version': meta['version'], 'status': meta['status'], 'reviewed_by': meta['reviewed_by'], 'note': meta['note']},
        'first_file': {'intro': ff['intro'], 'order': [{'section': s['section'], 'reason': s['reason']} for s in ff['order']],
                       'before_you_start': list(ff['before_you_start'])},
        'sections': {}, 'elements': {}, 'appointments': {}, 'classes': {},
    }
    for code in codes['sections']:
        src, v = merged['sections'][code]
        where = '%s section %s' % (src, code)
        check_keys(v, SECTION_KEYS, (), where)
        check_text(v['intro'], where + ' intro')
        check_list(v['what_goes_here'], where + ' what_goes_here', 1, 12)
        check_list(v['first_file_tips'], where + ' first_file_tips', 1, 8)
        who = v['who_usually_holds']
        if not isinstance(who, list) or not who or len(set(who)) != len(who) or any(d not in DEPARTMENTS for d in who):
            refuse('%s who_usually_holds: a non empty list of distinct department codes (%s), got %r' % (where, ' '.join(DEPARTMENTS), who))
        out['sections'][code] = {k: v[k] for k in SECTION_KEYS}
    for kind in KINDS:
        for code in codes[kind]:
            src, v = merged[kind][code]
            where = '%s %s %s' % (src, SINGULAR[kind], code)
            if kind == 'elements':
                check_keys(v, ITEM_KEYS + ('suggested_department',), (), where)
                if v['suggested_department'] not in DEPARTMENTS:
                    refuse('%s suggested_department: unknown department %r' % (where, v['suggested_department']))
            else:
                check_keys(v, ITEM_KEYS, (), where)
            check_list(v['what_to_submit'], where + ' what_to_submit', 2, 5)
            check_text(v['why'], where + ' why')
            check_text(v['example'], where + ' example')
            if not v['example'].startswith('Example'):
                refuse('%s example: must be marked as an example ("Example: ...")' % where)
            check_list(v['common_gaps'], where + ' common_gaps', 0, 3)
            row = {k: v[k] for k in ITEM_KEYS}
            if kind == 'elements':
                row['suggested_department'] = v['suggested_department']
            out[kind][code] = row
    return out, codes


# ------------------------------------------------------------------ SQL
def q(s):
    return 'null' if s is None else "'" + str(s).replace("'", "''") + "'"


def qj(v):
    return q(json.dumps(v, ensure_ascii=False, separators=(', ', ': '))) + '::jsonb'


def sql(g):
    n = {k: len(g[k]) for k in ('sections', 'elements', 'appointments', 'classes')}
    L = []
    w = L.append
    w('-- CNC MSP FORGE | HSF-GUIDE-01 | guidance for a first Health and Safety File')
    w('-- GENERATED by hsf/build_guidance.py from hsf/guidance/guidance.json (build contract')
    w('-- section 12, Amendment 4). Do not edit by hand: change the fragments in')
    w('-- hsf/guidance/ and run  python3 hsf/build_guidance.py')
    w('--')
    w('-- Loads guidance for %d sections, %d elements, %d appointment types and %d' % (n['sections'], n['elements'], n['appointments'], n['classes']))
    w('-- element classes, the first File order and the guidance meta (%s, %s).' % (g['meta']['version'], g['meta']['status']))
    w('-- Reference content, nothing personal: readable by anon and authenticated, written')
    w('-- only by the service role. hsf_public_guidance returns one jsonb document shaped')
    w('-- like guidance.json. The last step refuses the migration when any section,')
    w('-- element, appointment type or class in the library has no guidance.')
    w('')
    w('-- 1. Tables -------------------------------------------------------------------------------')
    w('')
    w('create table hsf_guidance_meta (')
    w("  id int primary key default 1 check (id = 1),")
    w("  version text not null,")
    w("  status text not null check (status in ('draft','reviewed')),")
    w("  reviewed_by text,")
    w("  note text not null,")
    w("  first_file_intro text not null,")
    w("  first_file_order jsonb not null check (jsonb_typeof(first_file_order) = 'array'),")
    w("  before_you_start jsonb not null check (jsonb_typeof(before_you_start) = 'array')")
    w(');')
    w("comment on table hsf_guidance_meta is 'Contract 12.1. One row: the guidance version and review status, and the first File panel (intro, the recommended order of sections with the reason for each, what to have ready).';")
    w('')
    w('create table hsf_section_guidance (')
    w('  section_code text primary key references hsf_section(code),')
    w('  intro text not null,')
    w("  what_goes_here jsonb not null check (jsonb_typeof(what_goes_here) = 'array' and jsonb_array_length(what_goes_here) >= 1),")
    w("  who_usually_holds text[] not null check (cardinality(who_usually_holds) >= 1),")
    w("  first_file_tips jsonb not null check (jsonb_typeof(first_file_tips) = 'array')")
    w(');')
    w("comment on table hsf_section_guidance is 'Contract 12.1 and 12.4. What goes in each File section, the departments that usually hold it (the builder preselects the first), and tips for a first File.';")
    w('')
    item_cols = [
        "  what_to_submit jsonb not null check (jsonb_typeof(what_to_submit) = 'array' and jsonb_array_length(what_to_submit) between 2 and 5),",
        "  why text not null,",
        "  example text not null check (example like 'Example%'),",
        "  common_gaps jsonb not null default '[]'::jsonb check (jsonb_typeof(common_gaps) = 'array' and jsonb_array_length(common_gaps) <= 3)",
    ]
    for table, key, ref, extra, comment in (
        ('hsf_element_guidance', 'element_code', 'hsf_element(code)', True,
         'Contract 12.1. Per element: what to submit, why it matters, a fictitious example and common gaps, with the department the document usually belongs to.'),
        ('hsf_appointment_guidance', 'appointment_code', 'hsf_appointment_type(code)', False,
         'Contract 12.1. Per appointment type (APP-nn): what to submit, why, a fictitious example and common gaps. Shown on each per appointment item.'),
        ('hsf_class_guidance', 'class_code', 'hsf_element_class(code)', False,
         'Contract 12.1. Per course, licence class and examination class (D04-nn, D05-nn, E06-nn): what to submit, why, a fictitious example and common gaps.'),
    ):
        w('create table %s (' % table)
        w('  %s text primary key references %s,' % (key, ref))
        cols = list(item_cols)
        if extra:
            cols[-1] += ','
            cols.append('  suggested_department text not null references hsf_department(code)')
        L.extend(cols)
        w(');')
        w('comment on table %s is %s;' % (table, q(comment)))
        w('')

    w('-- 2. Rows -----------------------------------------------------------------------------------')
    w('')
    m, ff = g['meta'], g['first_file']
    w('insert into hsf_guidance_meta (id, version, status, reviewed_by, note, first_file_intro, first_file_order, before_you_start) values')
    w('  (1, %s, %s, %s,' % (q(m['version']), q(m['status']), q(m['reviewed_by'])))
    w('   %s,' % q(m['note']))
    w('   %s,' % q(ff['intro']))
    w('   %s,' % qj(ff['order']))
    w('   %s);' % qj(ff['before_you_start']))
    w('')
    w('insert into hsf_section_guidance (section_code, intro, what_goes_here, who_usually_holds, first_file_tips) values')
    rows = []
    for code, v in g['sections'].items():
        rows.append('  (%s,\n   %s,\n   %s,\n   array[%s]::text[],\n   %s)' % (
            q(code), q(v['intro']), qj(v['what_goes_here']), ', '.join(q(d) for d in v['who_usually_holds']), qj(v['first_file_tips'])))
    w(',\n'.join(rows) + ';')
    w('')
    for kind, table, key in (('elements', 'hsf_element_guidance', 'element_code'),
                             ('appointments', 'hsf_appointment_guidance', 'appointment_code'),
                             ('classes', 'hsf_class_guidance', 'class_code')):
        dept = kind == 'elements'
        w('insert into %s (%s, what_to_submit, why, example, common_gaps%s) values' % (table, key, ', suggested_department' if dept else ''))
        rows = []
        for code, v in g[kind].items():
            rows.append('  (%s,\n   %s,\n   %s,\n   %s,\n   %s%s)' % (
                q(code), qj(v['what_to_submit']), q(v['why']), q(v['example']), qj(v['common_gaps']),
                (',\n   ' + q(v['suggested_department'])) if dept else ''))
        w(',\n'.join(rows) + ';')
        w('')

    w('-- 3. Access: reference content, read by anyone, written by the service role only ----------')
    w('')
    w('do $$')
    w('declare')
    w('  t text;')
    w('begin')
    w("  foreach t in array array['hsf_guidance_meta','hsf_section_guidance','hsf_element_guidance',")
    w("                           'hsf_appointment_guidance','hsf_class_guidance'] loop")
    w("    execute format('alter table %I enable row level security', t);")
    w("    execute format('revoke all on %I from public, anon, authenticated', t);")
    w("    execute format('grant select on %I to anon, authenticated', t);")
    w("    execute format('grant all on %I to service_role', t);")
    w("    execute format('create policy %I on %I for select to anon, authenticated using (true)', t || '_read', t);")
    w('  end loop;')
    w('end;')
    w('$$;')
    w('')
    w('-- 4. One document, shaped like hsf/guidance/guidance.json ---------------------------------')
    w('')
    w('create or replace view hsf_public_guidance with (security_invoker = true) as')
    w('select jsonb_build_object(')
    w("  'meta', jsonb_build_object('version', m.version, 'status', m.status, 'reviewed_by', m.reviewed_by, 'note', m.note),")
    w("  'first_file', jsonb_build_object('intro', m.first_file_intro, 'order', m.first_file_order, 'before_you_start', m.before_you_start),")
    w("  'sections', coalesce((select jsonb_object_agg(s.section_code, jsonb_build_object(")
    w("                'intro', s.intro, 'what_goes_here', s.what_goes_here,")
    w("                'who_usually_holds', to_jsonb(s.who_usually_holds), 'first_file_tips', s.first_file_tips))")
    w("              from hsf_section_guidance s), '{}'::jsonb),")
    w("  'elements', coalesce((select jsonb_object_agg(e.element_code, jsonb_build_object(")
    w("                'what_to_submit', e.what_to_submit, 'why', e.why, 'example', e.example,")
    w("                'common_gaps', e.common_gaps, 'suggested_department', e.suggested_department))")
    w("              from hsf_element_guidance e), '{}'::jsonb),")
    w("  'appointments', coalesce((select jsonb_object_agg(a.appointment_code, jsonb_build_object(")
    w("                'what_to_submit', a.what_to_submit, 'why', a.why, 'example', a.example, 'common_gaps', a.common_gaps))")
    w("              from hsf_appointment_guidance a), '{}'::jsonb),")
    w("  'classes', coalesce((select jsonb_object_agg(c.class_code, jsonb_build_object(")
    w("                'what_to_submit', c.what_to_submit, 'why', c.why, 'example', c.example, 'common_gaps', c.common_gaps))")
    w("              from hsf_class_guidance c), '{}'::jsonb)")
    w(') as guidance')
    w('  from hsf_guidance_meta m;')
    w("comment on view hsf_public_guidance is 'Contract 12.3. The whole guidance as one jsonb document shaped like hsf/guidance/guidance.json (meta, first_file, sections, elements, appointments, classes). Public read on purpose: reference content, nothing personal.';")
    w('grant select on hsf_public_guidance to anon, authenticated;')
    w('')
    w('-- 5. Refuse a library item without guidance ----------------------------------------------')
    w('')
    w('do $$')
    w('declare')
    w('  v_missing text;')
    w('begin')
    w("  select string_agg(x, ', ' order by x) into v_missing from (")
    w("    select 'section ' || code as x from hsf_section where code not in (select section_code from hsf_section_guidance)")
    w("    union all select 'element ' || code from hsf_element where code not in (select element_code from hsf_element_guidance)")
    w("    union all select 'appointment ' || code from hsf_appointment_type where code not in (select appointment_code from hsf_appointment_guidance)")
    w("    union all select 'class ' || code from hsf_element_class where code not in (select class_code from hsf_class_guidance)) m;")
    w('  if v_missing is not null then')
    w("    raise exception 'HSF-GUIDE-01: library items without guidance: %', v_missing;")
    w('  end if;')
    w('end;')
    w('$$;')
    return '\n'.join(L) + '\n'


def outputs(g):
    js_doc = json.dumps(g, ensure_ascii=False, separators=(',', ':'))
    return {
        OUT_JSON: json.dumps(g, ensure_ascii=False, indent=1) + '\n',
        OUT_SQL: sql(g),
        OUT_JS: ('/* GENERATED by hsf/build_guidance.py from hsf/guidance/guidance.json. Do not edit by hand.\n'
                 '   Guidance for a first Health and Safety File (build contract 12.4): %s, %s. */\n'
                 'window.CNC_HSF_GUIDANCE=%s;\n') % (g['meta']['version'], g['meta']['status'], js_doc),
    }


def main(argv):
    global GUIDE, WORKLIST
    if '--dir' in argv:
        GUIDE = Path(argv[argv.index('--dir') + 1]).resolve()
        WORKLIST = GUIDE / 'worklist.json'
    try:
        g, codes = build()
    except Refused as e:
        sys.stderr.write('REFUSED: %s\nNothing was written.\n' % e)
        return 2
    if '--validate' in argv:
        print('valid: sections %d, elements %d, appointments %d, classes %d'
              % (len(g['sections']), len(g['elements']), len(g['appointments']), len(g['classes'])))
        return 0
    if '--dir' in argv:
        sys.stderr.write('--dir is for --validate only; the outputs are built from hsf/guidance.\n')
        return 2
    outs = outputs(g)
    if '--check' in argv:
        stale = [p for p, text in outs.items() if not p.exists() or p.read_text(encoding='utf-8') != text]
        for p in stale:
            sys.stderr.write('out of date: %s\n' % p.relative_to(ROOT))
        return 1 if stale else 0
    for p, text in outs.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding='utf-8')
        print('wrote %-44s %8d bytes' % (p.relative_to(ROOT), len(text.encode('utf-8'))))
    print('guidance: sections %d, elements %d, appointments %d, classes %d, first File steps %d'
          % (len(g['sections']), len(g['elements']), len(g['appointments']), len(g['classes']), len(g['first_file']['order'])))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
