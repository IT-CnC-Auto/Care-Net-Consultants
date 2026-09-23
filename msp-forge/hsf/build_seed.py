"""CNC HSF FORGE | HSF-SEED-01 | writes supabase/migrations/048_hsf_library_seed.sql.

Reads the element library from SPEC.md Part B (B6 universal elements, B6.3.1
appointment types, B6.5.1 courses, B6.5.2 licence classes, the HSF-E-06
examination classes, B7 overlays and their "Switches on" lines, B9.2 triggers)
and the kernel pack protocols (kernel/cnc-ohs-industry-kernel, parsed exactly as
hsf/build_samples.py parses them, by importing its parser), and writes the seed
migration required by hsf/BUILD-CONTRACT.md section 3 (048).

Rules the output follows:
  1. Every element loads with basis_state 'awaiting' (SPEC B6.1.5).
  2. Each basis is split on ';' (outside brackets), the (H...) and (C...) markers
     and "Candidate:" prefixes are stripped, and the remaining name is matched to
     an instrument the kernel already holds by short_name: exact, or the longest
     held short_name followed only by provision words (", general duty",
     " section 16", " in full" and the like). The held names come from
     migrations 001 to 046 and the register release 1.0.0 CSV, kept in
     hsf/sources/ now that it is no longer published.
  3. A name the kernel does not hold becomes a candidate instrument: status
     'pending', scope 'safety', sources 'Gate a pending', 'Gate b pending',
     'Gate c pending'. It is inserted only where no row with that short_name
     exists, so no existing instrument row is ever changed.
  4. Links (hsf_element_instrument) carry provision 'awaiting verification'.
  5. Every statement is idempotent (on conflict do nothing / where not exists).
  6. Deterministic: the same SPEC and kernel always produce the same bytes.
  7. Displayed names (elements, appointment types, classes, candidates) are in
     plain words, as hsf/build_samples.py writes them: no section, regulation or
     annexure number other than section 16(2) and section 37(2). The build
     stops if one survives (contract 10.9(c)).

Run from msp-forge/:  python3 hsf/build_seed.py          (writes 048)
                      python3 hsf/build_seed.py --report (also prints the basis map)
"""
import csv, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True  # leave no __pycache__ in hsf/
import build_samples as bs  # noqa: E402  (reuses the SPEC and kernel pack parsers)

MIG = ROOT / 'supabase' / 'migrations'
OUT = MIG / '048_hsf_library_seed.sql'
CSV = HERE / 'sources' / 'CNC-Legislation-Register-v1.0.0.csv'  # register release 1.0.0, no longer published (contract 10.9)
PART_B = bs.PART_B

# ---------------------------------------------------------------------------
# 1. Held instruments: every short_name migrations 001 to 046 insert or rename
#    to, plus the published register release 1.0.0.

def held_names():
    names = set()
    for f in sorted(MIG.glob('[0-9][0-9][0-9]_*.sql')):
        if int(f.name[:3]) > 46:
            continue
        text = f.read_text(encoding='utf-8')
        for m in re.finditer(r'insert into msp_legal_instrument\b(.*?);[ \t]*$', text, re.S | re.M | re.I):
            body = m.group(1)
            for r in re.finditer(r"(?:^\s*\(|\bselect\s+|\bvalues\s*\()\s*'((?:[^']|'')+)'", body, re.M | re.I):
                names.add(r.group(1).replace("''", "'"))
        for r in re.finditer(r"set short_name\s*=\s*'((?:[^']|'')+)'", text, re.I):
            names.add(r.group(1).replace("''", "'"))
    with CSV.open(encoding='utf-8-sig', newline='') as fh:
        for row in csv.DictReader(fh):
            names.add(row['Instrument'].strip())
    return names


HELD = held_names()
EXPECTED_HELD = ['OHS Act', 'Construction Regulations, 2014', 'COIDA', 'HCA Regulations, 2021', 'HBA Regulations, 2022',
                 'Lead Regulations, 2001', 'General Safety Regulations, 1986', 'General Administrative Regulations, 2003',
                 'Driven Machinery Regulations', 'Electrical Machinery and Installation Regulations',
                 'General Machinery Regulations, 1988', 'Facilities Regulations, 2004', 'Ergonomics Regulations, 2019',
                 'MHI Regulations, 2022', 'NEM Waste Act', 'Noise Exposure Regulations, 2024',
                 'Physical Agents Regulations, 2024', 'Asbestos Abatement Regulations, 2020',
                 'Hazardous Substances Act (radiation control)', 'NRTA PrDP medical', 'BCEA night work Code',
                 'Food Premises Hygiene Regulations, R638 of 2018', 'MHSA', 'ODMWA', 'EEA section 7', 'POPIA']
_missing = [n for n in EXPECTED_HELD if n not in HELD]
if _missing:
    sys.exit('held instrument names not found in migrations 001 to 046 or the register CSV: %s' % _missing)

# ---------------------------------------------------------------------------
# 2. Basis parsing.

MARKER = re.compile(r'\s*\((?:all )?[HC]\b[^)]*\)')
PROVISION_TAIL = re.compile(r'^(?:,| (?:section|sections|in full|equivalent|where|for|Annexure|operator|read with)\b)')

# Library entries that name no instrument: kernel data, rules and expansions.
NOT_INSTRUMENT = {'kernel release notes', 'kernel role library', 'kernel hazard library',
                  'Kernel release (msp_kernel_version)', 'Kernel instruments per the Plan',
                  'Per appointment type', 'Per course', 'Per class', 'Reference only', 'no citation'}

# Segments that name several instruments, or whose clean name is not the literal text.
ALIASES = {
    'HCA, HBA, Noise Exposure, Lead, Ergonomics Regulations per protocol':
        ['HCA Regulations, 2021', 'HBA Regulations, 2022', 'Noise Exposure Regulations, 2024',
         'Lead Regulations, 2001', 'Ergonomics Regulations, 2019'],
    'HCA, HBA, Lead, Asbestos Regulations':
        ['HCA Regulations, 2021', 'HBA Regulations, 2022', 'Lead Regulations, 2001', 'Asbestos Abatement Regulations, 2020'],
    'SANS 10400 T part and local fire by laws': ['SANS 10400 T part', 'Local fire by laws'],
    'Fire Brigade Services Act and local fire by laws': ['Fire Brigade Services Act', 'Local fire by laws'],
    'SANS 10400 T part, Fire Brigade Services Act, local fire by laws':
        ['SANS 10400 T part', 'Fire Brigade Services Act', 'Local fire by laws'],
    'local by laws': ['Local by laws'],
    'Electrical Installation Regulations, 2009 read with SANS 10142': ['Electrical Installation Regulations, 2009', 'SANS 10142'],
    'Electrical Installation Regulations, 2009 wireman provisions': ['Electrical Installation Regulations, 2009'],
    'National Road Traffic Act in full, SANS 10231 and 10232': ['National Road Traffic Act', 'SANS 10231', 'SANS 10232'],
    'National Road Traffic Act, SANS 10231 and 10232': ['National Road Traffic Act', 'SANS 10231', 'SANS 10232'],
    'Railway Safety Regulator Act and SANS 3000 series': ['Railway Safety Regulator Act', 'SANS 3000 series'],
    'Merchant Shipping Act and Ports Act': ['Merchant Shipping Act', 'Ports Act'],
    'Civil Aviation Act and regulations': ['Civil Aviation Act', 'Civil Aviation Regulations'],
    'National Health Act and the Health Care Waste regulations': ['National Health Act', 'Health Care Waste regulations'],
    'Nursing Act, Health Professions Act, SAHPRA': ['Nursing Act', 'Health Professions Act', 'SAHPRA provisions'],
    'Private Security Industry Regulation Act and PSIRA training regulations':
        ['Private Security Industry Regulation Act', 'PSIRA training regulations'],
    'Skills Development Act and SETA unit standards': ['Skills Development Act', 'SETA unit standards'],
    'NEMA instruments': ['NEMA and its instruments'],
    'NEMA and its instruments': ['NEMA and its instruments'],
    'DMRE guideline': ['DMRE mandatory Code guidelines'],
    'MHSA regulations': ['MHSA regulations'],
}


def split_basis(basis):
    """Split on ';' outside brackets."""
    out, depth, cur = [], 0, ''
    for ch in basis:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ';' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += ch
    out.append(cur)
    return [s.strip() for s in out if s.strip()]


def match_held(text):
    best = None
    for h in HELD:
        if text == h:
            return h
        if text.startswith(h) and PROVISION_TAIL.match(text[len(h):]):
            if best is None or len(h) > len(best):
                best = h
    return best


def clean_candidate(text):
    t = re.sub(r'\s+in full( scope)?$', '', text).strip()
    return t[:1].upper() + t[1:]


def resolve(basis):
    """Instrument short names named by a basis cell, in order, without duplicates."""
    names = []
    for seg in split_basis(basis):
        text = re.sub(r'\s+', ' ', MARKER.sub('', seg)).strip()
        text = re.sub(r'^Candidate:\s*', '', text)
        if not text or text in NOT_INSTRUMENT or text.startswith('RULE-'):
            continue
        if text in ALIASES:
            found = ALIASES[text]
        else:
            held = match_held(text)
            found = [held] if held else [clean_candidate(text)]
        for n in found:
            if n not in names:
                names.append(n)
    return names


def rules_named(basis):
    return [s.strip() for s in split_basis(basis) if s.strip().startswith('RULE-HSF-')]

# ---------------------------------------------------------------------------
# 3. The library from SPEC.md Part B.

SECTION_TEXT = {
    'A': 'Company identity, the scope of the File, letters of good standing, construction notifications, contractor agreements and the dated legal register.',
    'B': 'The health and safety policy, chief executive responsibility, the section 16(2) assignment, representatives, the committee and every statutory appointment.',
    'C': 'Baseline, issue based and task based risk assessments, the hazard register, the hierarchy of control, safe work procedures and activity plans.',
    'D': 'Training needs, the training matrix, inductions, statutory training records, licences and competency assessments.',
    'E': 'The Medical Surveillance Plan, certificates of fitness, statutory examinations and the handling of medical records. Signed by the occupational medical practitioner only.',
    'F': 'Registers of equipment, installations and workplaces, with their inspection records.',
    'G': 'The permit to work system and the permits issued for high risk work.',
    'H': 'Emergency plans, drills, fire arrangements, medical emergency arrangements and spill response.',
    'I': 'Incident reporting, the incident register, investigations, COIDA records and corrective actions.',
    'J': 'Occupational hygiene surveys and exposure monitoring.',
    'K': 'Contractor selection and control, visitor control and the protection of the public.',
    'L': 'Committee minutes, representative inspections, toolbox talks, notices and change notifications.',
    'M': 'Welfare facilities, the physical environment, environmental management and waste.',
    'N': 'Internal and external audits, management review, objectives and corrective actions.',
    'O': 'The retention schedule, storage and access control, and the POPIA operator agreement.',
}

DEPARTMENTS = [('EXEC', 'Executive and legal'), ('HR', 'Human resources'), ('SHE', 'Health and safety'),
               ('OPS', 'Operations'), ('ENG', 'Engineering and maintenance'), ('PROC', 'Procurement and contractors'),
               ('OH', 'Occupational health and medical'), ('TRAIN', 'Training and development'),
               ('FAC', 'Facilities and security')]

TRIGGER_TEXT = {
    'T-CONSTR': 'Construction work is carried on',
    'T-CONSTR-NOTIFY': 'Construction work at or above the notification or permit thresholds (thresholds pinned in Phase 2)',
    'T-CONTRACTORS': 'Contractors or mandataries work for the employer',
    'T-HSR': 'The workforce requires designated health and safety representatives',
    'T-COMMITTEE': 'A health and safety committee is required',
    'T-HEIGHT': 'Work at height',
    'T-SCAFFOLD': 'Scaffolding is erected or used',
    'T-EXCAVATION': 'Excavation work',
    'T-DEMOLITION': 'Demolition work',
    'T-TEMPWORKS': 'Temporary works',
    'T-MOBILEPLANT': 'Construction vehicles, forklifts or other mobile plant',
    'T-ELEC': 'Electrical installations or electrical work',
    'T-LIFTING': 'Lifting machines and lifting tackle',
    'T-MACHINERY': 'Machinery that needs guarding and supervision',
    'T-PRESSURE': 'Pressure equipment',
    'T-HCA': 'Hazardous chemical agents are used, stored or produced',
    'T-HBA': 'Exposure to hazardous biological agents',
    'T-LADDERS': 'Ladders are used',
    'T-STACKING': 'Goods are stacked and stored',
    'T-CONFINED': 'Confined spaces are entered',
    'T-EPT': 'Explosive powered tools are used',
    'T-HOTWORK': 'Hot work such as welding, cutting or grinding',
    'T-ASBESTOS': 'Asbestos is present or may be disturbed',
    'T-LEAD': 'Work with lead',
    'T-NOISE': 'Noise exposure identified by the risk assessment',
    'T-RADIATION': 'Ionising radiation sources',
    'T-FOOD': 'Food is prepared, handled or served',
    'T-PRDP': 'Drivers who need a professional driving permit',
    'T-MINING': 'A mine, under the Mine Health and Safety Act regime',
    'T-TASKRA': 'Task based and daily pre task risk assessments are needed',
    'T-TRAFFIC': 'Vehicles and people share space',
    'T-SHIFT': 'Shift or night work',
    'T-VIOLENCE': 'Exposure to violence or aggression',
    'T-MHI': 'Holdings of listed substances at or above the major hazard installation thresholds (pinned in Phase 2)',
    'T-THERMAL': 'Heat or cold exposure',
    'T-WASTE': 'Waste is generated, handled or disposed of',
    'T-ENVIRO': 'Other environmental law applies',
    'T-PTW': 'A permit to work system is needed',
    'T-ROADWORKS': 'Work on or next to public roads',
    'T-SECURITY': 'Private security services are provided',
    'T-ARMED': 'Armed security or firearms are carried',
    'T-LPG': 'Liquefied petroleum gas installations',
    'T-EXPLOSIVES': 'Explosives are used',
    'T-PUBLIC': 'Members of the public may be affected by the work',
}

EVIDENCE = {'document', 'register', 'certificate', 'appointment', 'plan', 'report', 'permit', 'minutes',
            'training_record', 'medical_certificate', 'licence', 'agreement', 'log'}
REVIEW = {'annual', 'on_change', 'per_event', 'per_project', 'monthly', 'daily', 'before_use', 'on_expiry', 'statutory'}


def parse_triggers():
    m = re.search(r'^B9\.2 Trigger vocabulary.*?\. (T-CONSTR, .*?)\. Triggers are raised', PART_B, re.M)
    codes = [c.strip() for c in m.group(1).split(',')]
    assert len(codes) == 44 and set(codes) == set(TRIGGER_TEXT), codes
    return codes


TRIGGERS = parse_triggers()


def trigger_expr(applies):
    """Stored trigger for an Applies cell: None for every File, else the expression."""
    a = applies.strip()
    if a == 'U' or a.startswith('Per '):
        return None
    for part in re.split(r' (?:and|or) ', a):
        assert part in TRIGGERS, (a, part)
    return a


def compound_text(expr):
    parts = re.split(r' (and|or) ', expr)
    atoms, op = parts[0::2], parts[1]
    if op == 'or':
        return 'Compound: raised when any of %s is raised' % ', '.join(atoms)
    return 'Compound: raised when all of %s are raised' % ', '.join(atoms)


APPOINTMENTS = bs.APPOINTMENTS
ELEMENTS = bs.ELEMENTS
OVERLAYS = bs.OVERLAYS
assert len(ELEMENTS) == 137 and len(APPOINTMENTS) == 41 and len(OVERLAYS) == 119


def parse_courses():
    m = re.search(r'^B6\.5\.1 Courses.*?: (D04-01 .*?); D04-18 and onward', PART_B, re.M)
    out = []
    for part in m.group(1).split('; '):
        r = re.match(r'(D04-\d\d) (.+?)(?: \((T-[A-Z-]+(?: (?:and|or) T-[A-Z-]+)*)\))?$', part)
        out.append((r.group(1), r.group(2)[:1].upper() + r.group(2)[1:], r.group(3)))
    assert len(out) == 17, out
    return out


def parse_licences():
    m = re.search(r'^B6\.5\.2 Licence classes.*?: (D05-01 .*?); D05-08 and onward', PART_B, re.M)
    out = []
    for r in re.finditer(r'(D05-\d\d) (.+?) \((.+?), ([HC]); (T-[A-Z-]+(?: (?:and|or) T-[A-Z-]+)*)\)', m.group(1)):
        out.append((r.group(1), r.group(2)[:1].upper() + r.group(2)[1:], r.group(3) + ' (' + r.group(4) + ')', r.group(5)))
    assert len(out) == 7, out
    return out


# HSF-E-06 names ten examination classes and, in the same order, ten instruments.
# The class to trigger map uses the B9.2 vocabulary word for word (as
# hsf/build_samples.py EXAMS does).
EXAM_TRIGGER = {'lead': 'T-LEAD', 'asbestos': 'T-ASBESTOS', 'hazardous chemical agents': 'T-HCA',
                'hazardous biological agents': 'T-HBA', 'noise': 'T-NOISE', 'radiation': 'T-RADIATION',
                'heights': 'T-HEIGHT', 'confined space': 'T-CONFINED', 'night work': 'T-SHIFT',
                'food handling': 'T-FOOD'}


def parse_exams():
    e06 = next(e for e in ELEMENTS if e['code'] == 'HSF-E-06')
    classes = re.search(r'one item per applicable class: (.*?) \(MCO\)$', e06['name']).group(1).split(', ')
    bases = split_basis(MARKER.sub('', e06['basis']))
    assert len(classes) == len(bases) == 10
    return [('E06-%02d' % (i + 1), c[:1].upper() + c[1:], b.strip(), EXAM_TRIGGER[c]) for i, (c, b) in enumerate(zip(classes, bases))]


COURSES = parse_courses()
LICENCES = parse_licences()
EXAMS = parse_exams()
COURSE_BASIS = 'Skills Development Act and SETA unit standards (C)'


INDUSTRY_NAME = {}


def parse_switches():
    out = {}
    for m in re.finditer(r'^B7\.\d+ ([A-Z]+) (.+?)\. (.*)$', PART_B, re.M):
        code, rest = m.group(1), m.group(3)
        INDUSTRY_NAME[code] = m.group(2)
        s = re.search(r'Switches on: (.+?)\.(?:\s|$)', rest)
        items = []
        if s:
            for part in s.group(1).split('; ')[0].split(', '):
                r = re.match(r'(T-[A-Z-]+)(?: (.*))?$', part.strip())
                items.append((r.group(1), (r.group(2) or '').strip()))
        out[code] = items
    return out


SWITCHES = parse_switches()
assert len(SWITCHES) == 17 and sorted(SWITCHES) == sorted(bs.PACK_ORDER), sorted(SWITCHES)
# B7.10 names no "Switches on" line: the mining overlay is the MHSA regime itself
# (RULE-HSF-REGIME), which the T-MINING trigger stands for.
if not SWITCHES['MINING']:
    SWITCHES['MINING'] = [('T-MINING', '')]


def overlay_section(name):
    # Same assignment as hsf/build_samples.py, so the builder and the samples agree.
    if 'Section E' in name:
        return 'E'
    low = name.lower()
    if 'competenc' in low or 'PSIRA' in name or 'licence' in low:
        return 'D'
    return 'C'

# ---------------------------------------------------------------------------
# 3a. Plain words (hsf/BUILD-CONTRACT.md 10.9(c)): the names the builder and the
#     public library show carry no section, regulation or annexure number other
#     than section 16(2) and section 37(2) of the OHS Act. The rewrite is the one
#     hsf/build_samples.py uses for the samples, so both read the same; element
#     codes never change. Provision numbers stay out until Phase 2 pins them.

plain = bs.plain_name
NUMBERED = re.compile(bs.NUMBERED.pattern + r'|\b(?:[Rr]egs?\.? ?\d|[Ss]s?\. ?\d|[Aa]nnexures? (?:\d|[A-Z]\b)|[Ss]chedule \d)')


def assert_plain(kind, code, text):
    if text and NUMBERED.search(bs.ALLOWED_NUMBERS.sub('', text)):
        sys.exit('provision number left in a displayed %s name (contract 10.9(c)), %s: %s' % (kind, code, text))


# ---------------------------------------------------------------------------
# 4. SQL.


def q(v):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def values(rows, indent='  '):
    return (',\n').join(indent + '(' + ', '.join(q(v) for v in r) + ')' for r in rows)


def instrument_type(name):
    if name.startswith('SANS'):
        return 'sans'
    if 'guideline' in name.lower():
        return 'guideline'
    if re.search(r'\bAct\b', name) or name.split(' ')[0] in ('BCEA', 'NEMA', 'SAHPRA'):
        return 'act'
    if 'Code of Good Practice' in name:
        return 'code'
    if 'unit standards' in name:
        return 'guideline'
    return 'regulation'


# The row a short_name resolves to: verified first, then pending, then superseded.
LOOKUP_BODY = ("select li.id from msp_legal_instrument li where li.short_name = v.short_name "
               "order by case li.status when 'verified' then 0 when 'pending' then 1 when 'superseded' then 2 else 3 end, "
               "li.verified_on desc nulls last, li.id limit 1")
INSTRUMENT_LOOKUP = '(' + LOOKUP_BODY + ')'


def build():
    # Elements, universal then overlays, in SPEC order.
    elements = []
    links = []            # (element code, short name)
    for e in ELEMENTS:
        code, sec = e['code'], e['code'][4]
        assert e['evidence'] in EVIDENCE and e['review'] in REVIEW, e
        resp = e['responsible']
        appt, role = (resp, None) if re.match(r'^APP-\d\d$', resp) else (None, resp)
        retention = e['retention'].split(' ')[0]
        retention = None if retention == 'HSF-5' else retention
        mco = None
        if sec == 'E' and e['evidence'] == 'medical_certificate':
            mco = 'mco_medical'
        if code == 'HSF-D-04':
            mco = 'mco_training'
        name = plain(e['name'])
        elements.append((code, sec, name, name, e['evidence'], appt, role, e['review'], retention,
                         'BOTH', True, trigger_expr(e['applies']), mco))
        names = resolve(e['basis'])
        if code == 'HSF-B-06':
            names = []
            for a in APPOINTMENTS:
                names += [n for n in resolve(a['basis']) if n not in names]
        elif code == 'HSF-D-04':
            names = resolve(COURSE_BASIS)
        elif code == 'HSF-D-05':
            names = []
            for _, _, basis, _ in LICENCES:
                names += [n for n in resolve(basis) if n not in names]
        links += [(code, n) for n in names]
    for o in OVERLAYS:
        sec = overlay_section(o['name'])
        name = plain(o['name'].replace(' (Section E, MCO)', ''))
        regime = 'MHSA' if o['industry'] == 'MINING' else 'OHSA'
        elements.append((o['code'], sec, name, name, 'document', 'APP-00', None, 'annual', 'INST', regime, False, None,
                         'mco_medical' if sec == 'E' else None))
        links += [(o['code'], n) for n in resolve(o['basis'])]

    appts = []
    appt_links = []
    for a in APPOINTMENTS:
        names = resolve(a['basis'])
        rules = rules_named(a['basis'])
        regime = 'MHSA' if a['trigger'] == 'T-MINING' else 'BOTH'
        appts.append((a['code'], plain(a['name']), names[0] if names else None, rules[0] if rules else None, regime,
                      trigger_expr(a['trigger'])))
        appt_links += names

    classes = []
    class_names = []
    for i, (c, n, t) in enumerate(COURSES, 1):
        classes.append((c, 'HSF-D-04', 'course', i, plain(n), t, None, 'mco_training'))
    for i, (c, n, basis, t) in enumerate(LICENCES, 1):
        names = resolve(basis)
        class_names += names
        classes.append((c, 'HSF-D-05', 'licence', i, plain(n), t, names[0] if names else None, None))
    for i, (c, n, basis, t) in enumerate(EXAMS, 1):
        names = resolve(basis)
        class_names += names
        classes.append((c, 'HSF-E-06', 'examination', i, plain(n), t, names[0] if names else None, 'mco_medical'))

    # Candidates: every name the library uses that the kernel does not hold.
    used = []
    for n in [l[1] for l in links] + appt_links + class_names:
        if n not in used:
            used.append(n)
    candidates = sorted(n for n in used if n not in HELD)
    held_used = sorted(n for n in used if n in HELD)

    # Triggers: the vocabulary, then every compound expression the library uses.
    compounds = sorted({x for x in [r[11] for r in elements] + [a[5] for a in appts] + [c[5] for c in classes]
                        if x and (' or ' in x or ' and ' in x)})

    # Element industry rows.
    ei = {}
    for o in OVERLAYS:
        ei[(o['code'], o['industry'])] = ['mandatory', ['Addition of the %s overlay (SPEC B7).' % INDUSTRY_NAME[o['industry']]]]
    for ind in bs.PACK_ORDER:
        hits = {}
        for trig, qual in SWITCHES[ind]:
            conditional = qual.startswith(('where', 'for', '('))
            label = trig + ((' ' + (qual if not qual.startswith('(') else 'for ' + qual.strip('()'))) if qual else '')
            for e in ELEMENTS:
                expr = trigger_expr(e['applies'])
                if not expr or trig not in re.split(r' (?:and|or) ', expr):
                    continue
                if ' and ' in expr and not all(t in [x[0] for x in SWITCHES[ind]] for t in expr.split(' and ')):
                    continue
                h = hits.setdefault(e['code'], [True, []])
                h[0] = h[0] and conditional
                h[1].append(label)
        for code, (conditional, labels) in hits.items():
            ei[(code, ind)] = ['conditional' if conditional else 'mandatory',
                               ['Switched on by the %s overlay through %s.' % (INDUSTRY_NAME[ind], ', '.join(labels))]]
        often, hira = bs.PACK[ind]
        name = lambda pid: bs.PROTOCOLS[pid][0].replace('-', ' ')
        note = ('Kernel pack surveillance protocols for %s. Often: %s. Only if the risk assessment confirms exposure: %s. '
                'The CNC OHS Industry Kernel (23/09/2026) is sandbox until OMP and attorney review.'
                % (INDUSTRY_NAME[ind], ', '.join(name(p) for p in often) or 'none', ', '.join(name(p) for p in hira) or 'none'))
        ei[('HSF-E-06', ind)] = ['emphasis', [note]]
    order = {r[0]: i for i, r in enumerate(elements)}
    ei_rows = sorted(((k[0], k[1], v[0], ' '.join(v[1])) for k, v in ei.items()),
                     key=lambda r: (order[r[0]], bs.PACK_ORDER.index(r[1])))

    # Every displayed name must now be in plain words, or the build stops.
    for r in elements:
        assert_plain('element', r[0], r[2])
    for r in appts:
        assert_plain('appointment type', r[0], r[1])
    for r in classes:
        assert_plain('element class', r[0], r[4])
    for c in candidates:
        assert_plain('candidate instrument', c, c)
    for code, text in list(TRIGGER_TEXT.items()) + list(SECTION_TEXT.items()):
        assert_plain('trigger or section', code, text)
    for r in ei_rows:
        assert_plain('element industry note', r[0], r[3])
    return elements, links, appts, classes, candidates, held_used, compounds, ei_rows


def sql():
    elements, links, appts, classes, candidates, held_used, compounds, ei_rows = build()
    L = []
    w = L.append
    w('-- CNC MSP FORGE | HSF-SEED-01 v1.0.0 | HSF FORGE element library seed 23/09/2026')
    w('-- GENERATED by hsf/build_seed.py from SPEC.md Part B (B6, B6.3.1, B6.5.1, B6.5.2,')
    w('-- B7, B9.2) and the CNC OHS Industry Kernel pack protocols. Do not edit by hand:')
    w('-- change the SPEC or the generator and run  python3 hsf/build_seed.py')
    w('--')
    w('-- Loads: %d sections, %d departments, %d triggers (%d vocabulary, %d compound),' % (
        15, len(DEPARTMENTS), len(TRIGGERS) + len(compounds), len(TRIGGERS), len(compounds)))
    w('-- %d appointment types, %d elements (%d universal, %d overlay), %d element classes,' % (
        len(appts), len(elements), sum(1 for e in elements if e[10]), sum(1 for e in elements if not e[10]), len(classes)))
    w('-- %d element industry rows, %d element instrument links, and %d candidate' % (len(ei_rows), len(links), len(candidates)))
    w('-- instruments entered as status pending, scope safety, gates a to c pending.')
    w('-- Every element is awaiting verification; every link reads awaiting verification.')
    w('-- Names are in plain words: no provision numbers other than section 16(2) and')
    w('-- section 37(2) until Phase 2 pins them (contract 10.9(c)).')
    w('-- Idempotent. Never updates or deletes an existing msp_legal_instrument row:')
    w('-- candidates are inserted only where no row carries the same short_name.')
    w('')
    w('-- 0. Precondition (SPEC B8.2, HSF-7): the held instruments the library cites must')
    w('--    be in the kernel, or their links would be silently lost. Refuse otherwise.')
    w('do $$')
    w('declare')
    w('  v_missing text;')
    w('begin')
    w('  select string_agg(n, \'; \' order by n) into v_missing')
    w('    from unnest(array[')
    w(',\n'.join('      ' + q(n) for n in held_used))
    w('    ]) as n')
    w('   where not exists (select 1 from msp_legal_instrument li where li.short_name = n);')
    w('  if v_missing is not null then')
    w("    raise exception 'HSF seed refused: the kernel does not hold %. Apply migration 042 (release 1.1.0) first (HSF-7).', v_missing;")
    w('  end if;')
    w('end;')
    w('$$;')
    w('')
    w('-- 1. Sections A to O --------------------------------------------------------------')
    w('insert into hsf_section (code, ordinal, name, description, signatory_kind) values')
    w(values([(c, i, n, SECTION_TEXT[c], 'omp' if c == 'E' else 'safety') for i, (c, n) in enumerate(bs.SECTIONS, 1)]))
    w('on conflict (code) do nothing;')
    w('')
    w('-- 2. Departments (contract section 2) -------------------------------------------------')
    w('insert into hsf_department (code, name, ordinal) values')
    w(values([(c, n, i) for i, (c, n) in enumerate(DEPARTMENTS, 1)]))
    w('on conflict (code) do nothing;')
    w('')
    w('-- 3. Triggers (SPEC B9.2), then the compound expressions the library uses --------------')
    w('insert into hsf_trigger (code, description) values')
    w(values([(t, TRIGGER_TEXT[t]) for t in TRIGGERS] + [(c, compound_text(c)) for c in compounds]))
    w('on conflict (code) do nothing;')
    w('')
    w('-- 4. Candidate instruments (SPEC B8.1): pending, scope safety, uncitable until gates a, b and c pass')
    w('insert into msp_legal_instrument')
    w('  (short_name, full_citation, instrument_type, source_one, source_two, source_three, status, scope)')
    w("select v.short_name, v.full_citation, v.instrument_type, 'Gate a pending', 'Gate b pending', 'Gate c pending', 'pending', 'safety'")
    w('  from (values')
    w(values([(n, n + ' (Health and Safety File candidate named in the SPEC B6 and B7 element library; full citation pending verification)',
                instrument_type(n)) for n in candidates], '    '))
    w('       ) as v(short_name, full_citation, instrument_type)')
    w(' where not exists (select 1 from msp_legal_instrument li where li.short_name = v.short_name);')
    w('')
    w('-- 5. Appointment types (SPEC B6.3.1) --------------------------------------------------')
    w('insert into hsf_appointment_type (code, name, instrument_id, provision, competence_requirement, ratio_rule, regime, trigger_code)')
    w('select v.code, v.name, ' + INSTRUMENT_LOOKUP + ",")
    w("       'awaiting verification',")
    w("       'Pending: the competence requirement is pinned from the governing provision in Phase 2 (SPEC B8).',")
    w('       v.ratio_rule, v.regime, v.trigger_code')
    w('  from (values')
    w(values(appts, '    '))
    w('       ) as v(code, name, short_name, ratio_rule, regime, trigger_code)')
    w('on conflict (code) do nothing;')
    w('')
    w('-- 6. Elements: SPEC B6 universal (137), then B7 overlay additions (119) ------------------')
    w('insert into hsf_element (code, section_code, name, duty, evidence_type, responsible_appointment, responsible_role,')
    w('                         review_interval, retention_rule, regime, universal, trigger_code, mco_source, basis_state)')
    w("select v.code, v.section_code, v.name, v.duty, v.evidence_type, v.responsible_appointment, v.responsible_role,")
    w("       v.review_interval, v.retention_rule, v.regime, v.universal, v.trigger_code, v.mco_source, 'awaiting'")
    w('  from (values')
    w(values(elements, '    '))
    w('       ) as v(code, section_code, name, duty, evidence_type, responsible_appointment, responsible_role,')
    w('              review_interval, retention_rule, regime, universal, trigger_code, mco_source)')
    w('on conflict (code) do nothing;')
    w('')
    w('-- 7. Element classes: courses (B6.5.1), licence classes (B6.5.2), examination classes (HSF-E-06)')
    w('insert into hsf_element_class (code, element_code, kind, ordinal, name, trigger_code, instrument_id, provision, mco_source)')
    w('select v.code, v.element_code, v.kind, v.ordinal, v.name, v.trigger_code,')
    w('       case when v.short_name is null then null else ' + INSTRUMENT_LOOKUP + ' end,')
    w("       'awaiting verification', v.mco_source")
    w('  from (values')
    w(values([(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]) for c in classes], '    '))
    w('       ) as v(code, element_code, kind, ordinal, name, trigger_code, short_name, mco_source)')
    w('on conflict (code) do nothing;')
    w('')
    w('-- 8. Element instrument links (provision awaiting verification until Phase 2) -------------')
    w('insert into hsf_element_instrument (element_id, instrument_id, provision)')
    w("select e.id, i.id, 'awaiting verification'")
    w('  from (values')
    w(values(links, '    '))
    w('       ) as v(code, short_name)')
    w('  join hsf_element e on e.code = v.code')
    w('  cross join lateral (' + LOOKUP_BODY + ') i')
    w('on conflict (element_id, instrument_id) do nothing;')
    w('')
    w('-- 9. Element industry rows: overlay additions, universal elements each overlay switches on,')
    w('--    and the kernel pack surveillance protocols per industry (HSF-E-06 emphasis).')
    w('insert into hsf_element_industry (element_id, industry_id, subindustry_id, applicability, overlay_note)')
    w('select e.id, i.id, null, v.applicability, v.overlay_note')
    w('  from (values')
    w(values(ei_rows, '    '))
    w('       ) as v(code, industry_code, applicability, overlay_note)')
    w('  join hsf_element e on e.code = v.code')
    w('  join msp_industry i on i.code = v.industry_code')
    w(' where not exists (select 1 from hsf_element_industry x')
    w('                    where x.element_id = e.id and x.industry_id = i.id and x.subindustry_id is null);')
    w('')
    return '\n'.join(L), (elements, links, appts, classes, candidates, held_used, compounds, ei_rows)


def main():
    text, parts = sql()
    OUT.write_text(text, encoding='utf-8')
    elements, links, appts, classes, candidates, held_used, compounds, ei_rows = parts
    print('wrote %s' % OUT.relative_to(ROOT))
    print('elements %d, links %d, appointment types %d, classes %d, industry rows %d' % (
        len(elements), len(links), len(appts), len(classes), len(ei_rows)))
    print('held instruments cited: %d' % len(held_used))
    print('candidate instruments (pending): %d' % len(candidates))
    for c in candidates:
        print('  candidate: %s [%s]' % (c, instrument_type(c)))
    if '--report' in sys.argv:
        seen = {}
        for e in ELEMENTS + [dict(code=a['code'], basis=a['basis']) for a in APPOINTMENTS] + \
                [dict(code=o['code'], basis=o['basis']) for o in OVERLAYS]:
            for seg in split_basis(e['basis']):
                seen.setdefault(seg, resolve(seg))
        for seg in sorted(seen):
            print('  %-90s -> %s' % (seg[:90], seen[seg]))


if __name__ == '__main__':
    main()
