"""CNC HSF FORGE | sample Health and Safety Files for the website.

Reads the element library from SPEC.md Part B (B6 universal elements, B6.3.1
appointment types, B7 overlays), applies a fictitious company profile per
industry, and writes one data file per industry to vercel/hsf/samples/.

Everything here is FICTITIOUS demonstration data: company names, people,
dates and statuses. The legal basis shown is the element library's own
candidate basis; nothing in a sample is a verified citation, and the viewer
says so. Deterministic: the same library always produces the same samples.

Run from msp-forge/:  python3 hsf/build_samples.py
"""
import hashlib, json, re, datetime as dt
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = (ROOT / 'SPEC.md').read_text(encoding='utf-8')
PART_B = SPEC[SPEC.index('# PART B. CNC HSF FORGE'):]
OUT = ROOT / 'vercel' / 'hsf' / 'samples'
AS_AT = dt.date(2026, 9, 23)

SECTIONS = [
    ('A', 'Legal and administrative'), ('B', 'Policy, organisation and appointments'),
    ('C', 'Risk management'), ('D', 'Training and competence'),
    ('E', 'Medical surveillance and fitness'), ('F', 'Registers and inspections'),
    ('G', 'Permits and controls'), ('H', 'Emergency preparedness'),
    ('I', 'Incident management'), ('J', 'Occupational hygiene'),
    ('K', 'Contractors, visitors and the public'), ('L', 'Communication and consultation'),
    ('M', 'Environment, welfare and facilities'), ('N', 'Audit, review and improvement'),
    ('O', 'Records and retention'),
]

ELEMENTS = [dict(zip(('code', 'name', 'basis', 'evidence', 'responsible', 'review', 'retention', 'applies'), r))
            for r in re.findall(r'^\| (HSF-[A-O]-\d\d) \| (.*?) \| (.*?) \| (.*?) \| (.*?) \| (.*?) \| (.*?) \| (.*?) \|$', PART_B, re.M)]
APPOINTMENTS = [dict(zip(('code', 'name', 'basis', 'trigger'), r))
                for r in re.findall(r'^\| (APP-\d\d) \| (.*?) \| (.*?) \| (.*?) \|$', PART_B, re.M)]
OVERLAYS = [dict(code=r[0], industry=r[1], name=r[2], basis=r[3])
            for r in re.findall(r'^\| (HSF-OV-([A-Z]+)-\d\d) \| (.*?) \| (.*?) \|$', PART_B, re.M)]
APP_NAME = {a['code']: a['name'] for a in APPOINTMENTS}

COURSES = [
    ('D04-01', 'Health and safety representative', 'T-HSR'), ('D04-02', 'First aid', 'U'),
    ('D04-03', 'Fire fighting', 'U'), ('D04-04', 'Working at height and fall arrest', 'T-HEIGHT'),
    ('D04-05', 'Scaffold erection and inspection', 'T-SCAFFOLD'), ('D04-06', 'Confined space entry', 'T-CONFINED'),
    ('D04-07', 'Lifting machine and lifting tackle operation', 'T-LIFTING'),
    ('D04-08', 'Forklift and mobile plant', 'T-MOBILEPLANT'),
    ('D04-09', 'Hazard identification and risk assessment', 'U'), ('D04-10', 'Incident investigation', 'U'),
    ('D04-11', 'Hazardous chemical handling', 'T-HCA'), ('D04-12', 'Asbestos awareness', 'T-ASBESTOS'),
    ('D04-13', 'Lead awareness', 'T-LEAD'), ('D04-14', 'Hearing conservation', 'T-NOISE'),
    ('D04-15', 'Ergonomics', 'U'), ('D04-16', 'Emergency evacuation', 'U'), ('D04-17', 'Food handler hygiene', 'T-FOOD'),
]
LICENCES = [
    ('D05-01', 'Professional driving permit', 'T-PRDP'), ('D05-02', 'Plant and machinery operator certificates', 'T-MOBILEPLANT'),
    ('D05-03', 'Electrical wireman and installation registration', 'T-ELEC'), ('D05-04', 'Gas practitioner registration', 'T-LPG'),
    ('D05-05', 'Explosives licence', 'T-EXPLOSIVES'), ('D05-06', 'Firearm competency', 'T-ARMED'),
    ('D05-07', 'PSIRA registration and grade', 'T-SECURITY'),
]
EXAMS = [
    ('E06-01', 'Lead', 'T-LEAD'), ('E06-02', 'Asbestos', 'T-ASBESTOS'), ('E06-03', 'Hazardous chemical agents', 'T-HCA'),
    ('E06-04', 'Hazardous biological agents', 'T-HBA'), ('E06-05', 'Noise (audiometry)', 'T-NOISE'),
    ('E06-06', 'Ionising radiation', 'T-RADIATION'), ('E06-07', 'Work at height', 'T-HEIGHT'),
    ('E06-08', 'Confined space', 'T-CONFINED'), ('E06-09', 'Night work', 'T-SHIFT'), ('E06-10', 'Food handling', 'T-FOOD'),
]


# ---------------------------------------------------------------------------
# Section E protocols come from the CNC OHS Industry Kernel (23/09/2026,
# kernel/cnc-ohs-industry-kernel): 02-INDUSTRY-MATRIX gives each industry's
# "Often" and "If HIRA confirms" lists, 03-PROTOCOL-LEGAL-BASIS gives the basis
# and its strength. The kernel is SANDBOX until OMP and attorney review.
KPACK = ROOT / 'kernel' / 'cnc-ohs-industry-kernel'
PROTOCOLS = {
    1: ('Audiometry', 'Noise Exposure Regulations, 2024 with the Code of Practice for Audiometry', 'strong'),
    2: ('Spirometry', 'HCA and Asbestos Abatement medical surveillance, as the OMP directs', 'practice'),
    3: ('Respiratory symptom questionnaire', 'HCA, Asbestos and physical agents medical screening, as the OMP specifies', 'practice'),
    4: ('Chest X-ray per silica protocol', 'OMP directed imaging under HCA or Asbestos surveillance; mine instruments to be fetched', 'catalogue'),
    5: ('Dust disease examination battery for mine workers', 'MHSA and mine medical Codes of Practice, to be fetched', 'catalogue'),
    6: ('Blood lead biological monitoring', 'Lead Regulations, 2001', 'strong'),
    7: ('Lead exposure clinical examination', 'Lead Regulations, 2001', 'strong'),
    8: ('Biological monitoring for specific chemical agents', 'HCA Regulations medical surveillance and biological monitoring', 'strong'),
    9: ('Occupational chemical exposure medical assessment', 'HCA Regulations medical surveillance', 'strong'),
    10: ('Cholinesterase monitoring for pesticide exposure', 'HCA biological monitoring under a written OMP protocol', 'practice'),
    11: ('Dermatological screen', 'HCA and HBA skin exposure duties; OHS Act wet work risk assessment', 'practice'),
    12: ('Heights medical with vertigo and balance screen', 'Construction Regulations, 2014 medical fitness; OHS Act fall risk assessment', 'practice'),
    13: ('Confined space medical', 'OHS Act risk assessment and confined space programme; Construction Regulations on site', 'practice'),
    14: ('Heat stress tolerance assessment', 'Physical Agents Regulations, 2024', 'strong'),
    15: ('Heat tolerance screening for hot underground workings', 'MHSA heat instruments, to be fetched', 'catalogue'),
    16: ('Vibration and musculoskeletal screen', 'Physical Agents Regulations, 2024', 'strong'),
    17: ('Musculoskeletal and ergonomic assessment', 'OHS Act employer duties; EEA section 7 for lawful testing', 'practice'),
    18: ('Night work medical examination', 'Physical Agents Regulations, 2024 with the BCEA night work interface', 'practice'),
    19: ('PrDP statutory medical and vision screen', 'National Road Traffic Act PrDP framework, to be fetched', 'catalogue'),
    20: ('Lifting machine operator certificate of fitness', 'Driven Machinery Regulations, edition to be confirmed', 'catalogue'),
    21: ('Mine certificate of fitness examination', 'MHSA medical certificate framework, to be fetched', 'catalogue'),
    22: ('Railway safety critical fitness examination', 'Railway Safety Regulator standards, to be fetched', 'catalogue'),
    23: ('General medical for electrical work', 'OHS Act risk assessment; electrical regulations to be fetched', 'practice'),
    24: ('Vision screening with colour vision and UV skin surveillance', 'OHS Act and Physical Agents Regulations interfaces; inherent job requirements', 'practice'),
    25: ('Radiation worker surveillance with dose monitoring', 'Hazardous Substances Act and licence conditions, to be fetched', 'catalogue'),
    26: ('Occupational tuberculosis screening', 'HBA Regulations, 2022', 'strong'),
    27: ('Hepatitis B immunity verification and vaccination pathway', 'HBA Regulations, 2022', 'strong'),
    28: ('Biological agent surveillance per written medical protocol', 'HBA Regulations, 2022', 'strong'),
    29: ('Zoonosis surveillance per written medical protocol', 'HBA Regulations, 2022', 'practice'),
    30: ('Food handler fitness assessment', 'Municipal by laws, to be confirmed per metro; HBA where applicable', 'society'),
    31: ('General construction fitness', 'Construction Regulations, 2014 medical fitness duties', 'strong'),
    32: ('General fitness for the inherent requirements of the job', 'EEA section 7 inherent requirements', 'practice'),
    33: ('Tetanus status within the OMP protocol', 'HBA Regulations, 2022, within the written medical protocol', 'practice'),
}
PACK_ORDER = ['AGRI', 'CLEAN', 'CONSTR', 'EDU', 'GOV', 'HEALTH', 'HOSP', 'MANU', 'MINING', 'OFFICE',
              'PETRO', 'RETAIL', 'SEC', 'TEL', 'TRANS', 'UTIL', 'WASTE']


def protocol_ids(entry):
    e = entry.lower()
    ids = []
    rules = [
        (lambda: 'underground' in e and 'heat' in e, 15), (lambda: 'dust disease' in e, 5),
        (lambda: 'mine certificate' in e, 21), (lambda: 'general construction fitness' in e, 31),
        (lambda: 'general fitness' in e, 32), (lambda: 'tetanus' in e, 33),
        (lambda: 'audiometry' in e, 1), (lambda: 'spirometry' in e, 2), (lambda: 'respiratory' in e, 3),
        (lambda: 'chest x' in e, 4), (lambda: 'blood lead' in e, 6), (lambda: 'lead clinical' in e, 7),
        (lambda: 'biological monitoring' in e, 8), (lambda: 'chemical exposure' in e or 'chemical medical' in e, 9),
        (lambda: 'cholinesterase' in e, 10), (lambda: 'dermatolog' in e, 11), (lambda: 'heights' in e, 12),
        (lambda: 'confined space' in e, 13), (lambda: 'heat' in e and 'underground' not in e, 14),
        (lambda: 'vibration' in e, 16), (lambda: 'musculoskeletal' in e and 'vibration' not in e, 17),
        (lambda: 'night work' in e, 18), (lambda: 'prdp' in e, 19), (lambda: 'lifting machine' in e, 20),
        (lambda: 'railway' in e, 22), (lambda: 'electrical' in e, 23), (lambda: 'vision' in e, 24),
        (lambda: 'radiation' in e, 25), (lambda: 'tuberculosis' in e or 'tb screen' in e, 26),
        (lambda: 'hepatitis b' in e or 'hep b' in e, 27), (lambda: 'biological agent' in e, 28),
        (lambda: 'zoonosis' in e, 29), (lambda: 'food handler' in e, 30),
    ]
    for test, pid in rules:
        if test() and pid not in ids:
            ids.append(pid)
    return ids


def pack_protocols():
    text = (KPACK / '02-INDUSTRY-MATRIX.md').read_text(encoding='utf-8')
    blocks = re.split(r'^## \d+\. ', text, flags=re.M)[1:18]
    out = {}
    for code, block in zip(PACK_ORDER, blocks):
        often, hira = [], []
        for line in block.splitlines():
            m = re.match(r'\s*- \*\*(Often[^*]*|If HIRA[^*]*):\*\*\s*(.*)$', line)
            if not m:
                continue
            target = often if m.group(1).startswith('Often') else hira
            for entry in m.group(2).split(';'):
                for pid in protocol_ids(re.sub(r'\*\*', '', entry)):
                    if pid not in often and pid not in hira and pid not in target:
                        target.append(pid)
        out[code] = (often, hira)
    return out


PACK = pack_protocols()
HIRA_REASON = 'Only once the risk assessment confirms exposure; not confirmed at this site.'

# Fictitious sample companies. Triggers are what a completed assessment for
# this kind of operation would raise; they decide which elements switch on.
PROFILES = {
    'AGRI':   ('agriculture-and-forestry', 'Agriculture and forestry', 'Umzimkhulu Valley Farming (Pty) Ltd', 'Mixed citrus and timber estate, packhouse and sawmill yard', 2, 86, 'OHSA',
               'T-HCA T-HBA T-MACHINERY T-THERMAL T-PRDP T-NOISE T-MOBILEPLANT T-HSR T-COMMITTEE T-SHIFT T-LADDERS T-STACKING T-TRAFFIC'),
    'CLEAN':  ('cleaning-and-hygiene-services', 'Cleaning and hygiene services', 'Sparkle Grid Hygiene Services (Pty) Ltd', 'Contract cleaning at 14 client sites, including two hospitals', 3, 142, 'OHSA',
               'T-HCA T-HEIGHT T-CONFINED T-HBA T-SHIFT T-CONTRACTORS T-HSR T-COMMITTEE T-LADDERS T-PRDP'),
    'CONSTR': ('construction', 'Construction', 'Rietvlei Civils and Building (Pty) Ltd', 'Civil works contract: stormwater upgrade and a two storey clinic', 1, 64, 'OHSA',
               'T-CONSTR T-CONSTR-NOTIFY T-CONTRACTORS T-HSR T-COMMITTEE T-HEIGHT T-SCAFFOLD T-EXCAVATION T-TEMPWORKS T-MOBILEPLANT T-ELEC T-LIFTING T-HCA T-NOISE T-LADDERS T-STACKING T-HOTWORK T-TASKRA T-TRAFFIC T-PUBLIC T-PTW T-PRDP'),
    'EDU':    ('education', 'Education', 'Highveld Learning Campus NPC', 'Independent school with science laboratories, workshops and a kitchen', 1, 118, 'OHSA',
               'T-HCA T-FOOD T-PRDP T-HBA T-HSR T-COMMITTEE T-LADDERS T-PUBLIC'),
    'GOV':    ('government-and-municipal', 'Government and municipal', 'Fictitious Local Municipality: Technical Services', 'Roads, water and sanitation, and parks depots', 3, 240, 'OHSA',
               'T-CONFINED T-PRDP T-CONTRACTORS T-HSR T-COMMITTEE T-MOBILEPLANT T-HCA T-HBA T-NOISE T-TRAFFIC T-ROADWORKS T-PUBLIC T-ELEC T-LADDERS T-SHIFT T-PTW'),
    'HEALTH': ('healthcare-and-laboratories', 'Healthcare and laboratories', 'Karoo Pathology and Day Hospital (Pty) Ltd', 'Day hospital with theatre, radiology and a pathology laboratory', 1, 96, 'OHSA',
               'T-HBA T-RADIATION T-SHIFT T-VIOLENCE T-HCA T-HSR T-COMMITTEE T-WASTE T-FOOD T-LADDERS'),
    'HOSP':   ('hospitality-and-food-service', 'Hospitality and food service', 'Blouberg Bay Hotel and Conference (Pty) Ltd', 'Seventy room hotel with conference kitchen and pool', 1, 74, 'OHSA',
               'T-FOOD T-LPG T-SHIFT T-VIOLENCE T-HCA T-HSR T-COMMITTEE T-LADDERS T-PUBLIC T-PRESSURE'),
    'MANU':   ('manufacturing', 'Manufacturing', 'Vaal Precision Components (Pty) Ltd', 'Metal pressing, welding and powder coating plant', 1, 185, 'OHSA',
               'T-MACHINERY T-PRESSURE T-LIFTING T-ELEC T-HCA T-NOISE T-CONFINED T-MOBILEPLANT T-HSR T-COMMITTEE T-HOTWORK T-STACKING T-LADDERS T-TRAFFIC T-SHIFT T-PTW T-THERMAL T-CONTRACTORS'),
    'MINING': ('mining-and-quarrying', 'Mining and quarrying', 'Magaliesberg Aggregates (Pty) Ltd', 'Open pit quarry with crushing and screening plant', 1, 128, 'MHSA',
               'T-MINING T-NOISE T-HCA T-MOBILEPLANT T-EXPLOSIVES T-LIFTING T-MACHINERY T-ELEC T-THERMAL T-HSR T-COMMITTEE T-CONTRACTORS T-PRDP T-TRAFFIC T-SHIFT'),
    'OFFICE': ('office-and-professional-services', 'Office and professional services', 'Sandton Advisory Partners Inc', 'Head office and a 60 seat contact centre', 1, 112, 'OHSA',
               'T-SHIFT T-HSR T-COMMITTEE T-PRDP'),
    'PETRO':  ('petrochemical-and-fuel-retail', 'Petrochemical and fuel retail', 'Garden Route Fuels (Pty) Ltd', 'Four forecourts and a bulk depot with an LPG filling plant', 5, 97, 'OHSA',
               'T-MHI T-HCA T-HOTWORK T-CONFINED T-ELEC T-LPG T-WASTE T-PTW T-PRDP T-HSR T-COMMITTEE T-PRESSURE T-TRAFFIC T-CONTRACTORS T-SHIFT T-VIOLENCE T-PUBLIC'),
    'RETAIL': ('retail-and-wholesale', 'Retail and wholesale', 'Midlands Wholesale Distributors (Pty) Ltd', 'Cash and carry store with a distribution centre and cold rooms', 2, 156, 'OHSA',
               'T-STACKING T-MOBILEPLANT T-TRAFFIC T-PRDP T-FOOD T-VIOLENCE T-HSR T-COMMITTEE T-LADDERS T-PUBLIC T-THERMAL'),
    'SEC':    ('security-services', 'Security services', 'Sentinel Ridge Protection (Pty) Ltd', 'Guarding, armed response and a control room', 2, 210, 'OHSA',
               'T-SECURITY T-ARMED T-SHIFT T-VIOLENCE T-PRDP T-HSR T-COMMITTEE'),
    'TEL':    ('telecommunications-and-tower-work', 'Telecommunications and tower work', 'Skyline Tower Services (Pty) Ltd', 'Tower maintenance crews and a regional data centre', 2, 58, 'OHSA',
               'T-HEIGHT T-ELEC T-CONFINED T-LIFTING T-PRDP T-CONSTR T-HSR T-COMMITTEE T-LADDERS T-CONTRACTORS T-PTW'),
    'TRANS':  ('transport-and-logistics', 'Transport and logistics', 'N3 Corridor Freight (Pty) Ltd', 'Long haul fleet, cross dock warehouse and a diesel workshop', 2, 174, 'OHSA',
               'T-PRDP T-STACKING T-MOBILEPLANT T-SHIFT T-HSR T-COMMITTEE T-HCA T-NOISE T-TRAFFIC T-LIFTING T-LADDERS T-PRESSURE'),
    'UTIL':   ('utilities-and-energy', 'Utilities and energy', 'Limpopo Water and Power Services (Pty) Ltd', 'Water treatment works and a 20 MW solar plant', 2, 88, 'OHSA',
               'T-ELEC T-HEIGHT T-CONFINED T-HCA T-CONSTR T-PUBLIC T-HSR T-COMMITTEE T-HBA T-NOISE T-PTW T-LADDERS T-SHIFT T-PRDP'),
    'WASTE':  ('waste-management', 'Waste management', 'Ekurhuleni Waste Recovery (Pty) Ltd', 'Collection fleet, transfer station and a materials recovery facility', 2, 132, 'OHSA',
               'T-WASTE T-HBA T-CONFINED T-MOBILEPLANT T-TRAFFIC T-HCA T-PRDP T-HSR T-COMMITTEE T-NOISE T-THERMAL T-PUBLIC'),
}

ROLES = json.loads((Path(__file__).parent / 'sample_roles.json').read_text(encoding='utf-8'))

FIRST = ['Thandeka', 'Pieter', 'Nomvula', 'Sipho', 'Anika', 'Lerato', 'Johan', 'Ayanda', 'Zanele', 'Mohammed', 'Refilwe', 'Kobus', 'Naledi', 'Themba', 'Chantel', 'Bongani']
LAST = ['Mokoena', 'van der Merwe', 'Dlamini', 'Naidoo', 'Botha', 'Khumalo', 'Pillay', 'Mahlangu', 'Nel', 'Ndlovu', 'Jacobs', 'Molefe', 'Fourie', 'Zulu', 'Adams', 'Sithole']


def h(*parts):
    return int(hashlib.sha256('|'.join(parts).encode()).hexdigest(), 16)


def applies(trigger, triggers):
    t = trigger.strip()
    if t == 'U':
        return True
    if t.startswith('Per '):
        return True
    if ' and ' in t:
        return all(x.strip() in triggers for x in t.split(' and '))
    if ' or ' in t:
        return any(x.strip() in triggers for x in t.split(' or '))
    return t in triggers


def state_of(basis):
    """H = held in the kernel, re verification in full scope pending; C = candidate."""
    if '(C' in basis and '(H' not in basis:
        return 'awaiting'
    if '(H' in basis and '(C' not in basis:
        return 'held'
    return 'mixed'


def clean_basis(basis):
    return re.sub(r'\s*\((H|C)[^)]*\)', '', basis).strip()


def fmt(d):
    return d.strftime('%d/%m/%Y')


def status_for(key, mco, section):
    r = h(key) % 100
    if mco:
        if r < 74: return 'linked_mco'
        if r < 86: return 'expired'
        return 'outstanding'
    if section in 'AB':
        return 'uploaded' if r < 72 else ('outstanding' if r < 94 else 'expired')
    if r < 58: return 'uploaded'
    if r < 84: return 'outstanding'
    if r < 93: return 'expired'
    return 'not_applicable'


NA_REASON = 'Not carried on at this site when the File was assessed; the item returns at the next revision if the activity starts.'

REVIEW_DAYS = {'annual': 365, 'monthly': 31, 'daily': 1, 'on_expiry': 365, 'statutory': 365, 'per_project': 365,
               'on_change': 730, 'per_event': 365, 'before_use': 30}


def dates_for(key, status, review):
    span = REVIEW_DAYS.get(review, 365)
    off = h(key, 'd') % max(span, 30)
    if status == 'expired':
        to = AS_AT - dt.timedelta(days=5 + h(key, 'e') % 80)
        return fmt(to - dt.timedelta(days=span)), fmt(to)
    if status in ('uploaded', 'linked_mco'):
        frm = AS_AT - dt.timedelta(days=off)
        to = frm + dt.timedelta(days=max(span, 30)) if review not in ('on_change',) else None
        return fmt(frm), (fmt(to) if to else 'On change')
    if status == 'outstanding':
        return '', fmt(AS_AT + dt.timedelta(days=14 + h(key, 'o') % 45))
    return '', ''


REGIME = {'v': 'OHSA'}


def item(code, section, name, basis, evidence, responsible, review, retention, key, mco=False):
    if REGIME['v'] == 'MHSA':
        # RULE-HSF-REGIME: at a mine the MHSA equivalent replaces the OHS Act provision.
        segs, out = [x.strip() for x in basis.split(';')], []
        for seg in segs:
            if seg.startswith('OHS Act') or seg.startswith('MHSA equivalent'):
                seg = 'MHSA, equivalent provision (C)'
            if seg not in out:
                out.append(seg)
        basis = '; '.join(out)
        name = name.replace('; MHSA equivalent for mines', '')
    elif name.endswith('; MHSA equivalent for mines'):
        name = name.replace('; MHSA equivalent for mines', '')
        basis = basis.replace('; MHSA equivalent (H)', '')
    st = status_for(key, mco, section)
    frm, to = dates_for(key, st, review)
    return {
        'code': code, 'section': section, 'name': name, 'basis': clean_basis(basis), 'basis_state': state_of(basis),
        'evidence': evidence, 'responsible': APP_NAME.get(responsible, responsible), 'review': review.replace('_', ' '),
        'retention': retention, 'status': st, 'from': frm, 'to': to,
        'reason': NA_REASON if st == 'not_applicable' else '',
        'source': ('MyClinicOnline' if st in ('linked_mco', 'expired') and mco else ('Client upload' if st == 'uploaded' else '')),
    }


def build(code):
    slug, iname, company, scope, sites, headcount, regime, trig = PROFILES[code]
    triggers = set(trig.split())
    REGIME['v'] = regime
    items = []
    for e in ELEMENTS:
        if not applies(e['applies'], triggers):
            continue
        sec = e['code'][4]
        key = code + e['code']
        if e['code'] == 'HSF-B-06':
            for a in APPOINTMENTS:
                if applies(a['trigger'], triggers):
                    items.append(item(e['code'] + '.' + a['code'][4:], sec, 'Appointment: ' + a['name'], a['basis'], 'appointment',
                                      a['code'], 'on_change', 'LIFE', key + a['code']))
            continue
        if e['code'] == 'HSF-D-04':
            for c, n, t in COURSES:
                if applies(t, triggers):
                    items.append(item('HSF-' + c, sec, 'Training: ' + n, 'Instrument that requires it (H or C) read with the Skills Development Act (C)',
                                      'training_record', 'APP-00', 'on_expiry', 'HSF-5', key + c, mco=True))
            continue
        if e['code'] == 'HSF-D-05':
            for c, n, t in LICENCES:
                if applies(t, triggers):
                    items.append(item('HSF-' + c, sec, 'Licence: ' + n, e['basis'], 'licence', 'APP-00', 'on_expiry', 'HSF-5', key + c))
            continue
        if e['code'] == 'HSF-E-06':
            often, hira = PACK[code]
            for pid in often:
                n, b, strength = PROTOCOLS[pid]
                it = item('HSF-E06-P%02d' % pid, sec, 'Surveillance protocol: ' + n, b, 'medical_certificate', 'OMP',
                          'statutory', 'MED40', key + 'P%d' % pid, mco=True)
                it['basis_state'] = strength
                items.append(it)
            for pid in hira:
                n, b, strength = PROTOCOLS[pid]
                it = item('HSF-E06-P%02d' % pid, sec, 'Surveillance protocol: ' + n, b, 'medical_certificate', 'OMP',
                          'statutory', 'MED40', key + 'P%d' % pid, mco=True)
                it.update(basis_state=strength, status='not_applicable', reason=HIRA_REASON, source='', to='', **{'from': ''})
                items.append(it)
            continue
        mco = sec == 'E' and e['evidence'] == 'medical_certificate'
        items.append(item(e['code'], sec, e['name'], e['basis'], e['evidence'], e['responsible'], e['review'], e['retention'], key, mco=mco))
    for o in OVERLAYS:
        if o['industry'] != code:
            continue
        sec = 'E' if 'Section E' in o['name'] else ('D' if 'competenc' in o['name'].lower() or 'PSIRA' in o['name'] or 'licence' in o['name'].lower() else 'C')
        items.append(item(o['code'], sec, o['name'].replace(' (Section E, MCO)', ''), o['basis'], 'document', 'APP-00', 'annual', 'INST',
                          code + o['code'], mco=(sec == 'E')))
    order = {s: i for i, (s, _) in enumerate(SECTIONS)}
    items.sort(key=lambda x: (order[x['section']], x['code']))

    # Compliance: linked_mco or uploaded over everything not marked not applicable (SPEC B9.4).
    secs = []
    for s, n in SECTIONS:
        its = [x for x in items if x['section'] == s]
        den = sum(1 for x in its if x['status'] != 'not_applicable')
        num = sum(1 for x in its if x['status'] in ('linked_mco', 'uploaded'))
        secs.append({'code': s, 'name': n, 'items': len(its), 'compliant': num, 'applicable': den,
                     'pct': round(100 * num / den, 1) if den else None})
    den = sum(x['applicable'] for x in secs); num = sum(x['compliant'] for x in secs)

    # People matrix: fictitious names, kernel role titles, requirements per role.
    roles = ROLES[code]
    columns = [('induction', 'Site induction'), ('cof', 'Certificate of fitness')]
    if 'T-CONSTR' in triggers: columns.append(('annex3', 'Annexure 3 medical'))
    if 'T-MINING' in triggers: columns.append(('minecof', 'Mine certificate of fitness'))
    columns += [('D04-02', 'First aid'), ('D04-03', 'Fire fighting')]
    for c, n, t in COURSES:
        if t != 'U' and t in triggers and len(columns) < 9:
            columns.append((c, n))
    if 'T-PRDP' in triggers: columns.append(('prdp', 'PrDP medical'))
    people = []
    for i in range(12):
        role = roles[h(code, 'r', str(i)) % len(roles)]
        name = FIRST[h(code, 'f', str(i)) % len(FIRST)] + ' ' + LAST[h(code, 'l', str(i)) % len(LAST)]
        cells = {}
        low = role.lower()
        for cid, cname in columns:
            need = cid in ('induction', 'cof', 'annex3', 'minecof')
            need |= cid == 'D04-02' and i in (0, 5)
            need |= cid == 'D04-03' and i in (1, 6)
            need |= cid == 'prdp' and ('driver' in low or 'truck' in low or 'courier' in low)
            need |= cid == 'D04-04' and any(w in low for w in ('height', 'scaffold', 'tower', 'rigger', 'line', 'aerial', 'high level', 'wind'))
            need |= cid == 'D04-05' and 'scaffold' in low
            need |= cid == 'D04-06' and any(w in low for w in ('sewer', 'tank', 'confined', 'pump', 'sanitation', 'drain', 'leachate', 'wastewater'))
            need |= cid == 'D04-07' and any(w in low for w in ('crane', 'rigging', 'winch', 'lift'))
            need |= cid == 'D04-08' and any(w in low for w in ('forklift', 'plant operator', 'loader', 'reach truck', 'excavator', 'compactor', 'tractor', 'straddle', 'dump truck', 'lhd'))
            need |= cid == 'D04-11' and any(w in low for w in ('chemical', 'spray', 'pesticide', 'chlorin', 'laboratory', 'cleaner', 'hygiene', 'dye', 'process', 'blend'))
            need |= cid == 'D04-14' and cid in dict(columns) and h(code, 'n', str(i)) % 3 == 0
            need |= cid == 'D04-17' and any(w in low for w in ('cook', 'chef', 'food', 'kitchen', 'bakery', 'butcher', 'waiter', 'counter'))
            need |= cid in ('D04-01', 'D04-09', 'D04-10') and i == 2
            need |= cid == 'D04-16' and i in (3, 7)
            if not need:
                cells[cid] = {'s': 'na'}
                continue
            r = h(code, cid, str(i)) % 100
            s = 'ok' if r < 72 else ('due' if r < 84 else ('expired' if r < 94 else 'missing'))
            if s == 'ok':
                d = AS_AT + dt.timedelta(days=60 + h(code, cid, 'x', str(i)) % 300)
            elif s == 'due':
                d = AS_AT + dt.timedelta(days=5 + h(code, cid, 'y', str(i)) % 55)
            elif s == 'expired':
                d = AS_AT - dt.timedelta(days=3 + h(code, cid, 'z', str(i)) % 120)
            else:
                d = None
            mco = cid in ('cof', 'annex3', 'minecof', 'prdp') or cid.startswith('D04')
            cells[cid] = {'s': s, 'd': fmt(d) if d else '', 'src': 'MCO' if (mco and s != 'missing') else ''}
        people.append({'name': name, 'role': role, 'cells': cells})

    ref = 'CNC-HSF-SAMPLE-' + code
    return {
        'slug': slug, 'code': code, 'industry': iname, 'company': company + ' (fictitious)', 'scope': scope,
        'sites': sites, 'headcount': headcount, 'regime': 'Mine Health and Safety Act' if regime == 'MHSA' else 'Occupational Health and Safety Act',
        'reference': ref, 'revision': 1, 'as_at': fmt(AS_AT), 'triggers': sorted(triggers),
        'kernel': 'CNC OHS Industry Kernel, 23/09/2026 (sandbox until OMP and attorney review)',
        'overall': {'compliant': num, 'applicable': den, 'pct': round(100 * num / den, 1) if den else None,
                    'counts': {k: sum(1 for x in items if x['status'] == k) for k in ('linked_mco', 'uploaded', 'outstanding', 'expired', 'not_applicable')}},
        'sections': secs, 'items': items,
        'matrix': {'columns': [{'id': c, 'name': n} for c, n in columns], 'people': people},
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    index = []
    for code in PROFILES:
        d = build(code)
        (OUT / (d['slug'] + '.js')).write_text('window.__HSF_SAMPLE=' + json.dumps(d, ensure_ascii=False, separators=(',', ':')) + ';\n', encoding='utf-8')
        index.append((d['slug'], code, d['industry'], len(d['items']), d['overall']['pct']))
    for row in index:
        print('%-36s %-7s items %3d  compliance %5.1f%%' % (row[0], row[1], row[3], row[4]))


if __name__ == '__main__':
    main()
