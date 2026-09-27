// Demonstration data: the fictitious Rietvlei Civils and Building tenant of
// supabase/seed/bee_inspect_demo.sql (same ids where the seed has them), so
// the whole flow can be walked in Expo Go or a browser without a Supabase
// project. Every name, number and document here is FICTITIOUS.

import { CONSENT_VERSIONS } from '@/lib/constants';
import { addDaysIso, todayIso } from '@/lib/dates';
import type { Kind, KindMap } from '@/lib/types';

export const DEMO = {
  tenant: 'b1a00000-0000-4000-8000-000000000001',
  company: 'b1a00000-0000-4000-8000-000000000002',
  inspectorAuth: 'b1a00000-0000-4000-8000-000000000011',
  inspector: 'b1a00000-0000-4000-8000-000000000021',
  site: 'b1a00000-0000-4000-8000-000000000041',
  deptOps: 'b1a00000-0000-4000-8000-000000000042',
  deptFac: 'b1a00000-0000-4000-8000-000000000043',
  workshop: 'b1a00000-0000-4000-8000-000000000044',
  yardB: 'b1a00000-0000-4000-8000-000000000045',
  roomFloor: 'b1a00000-0000-4000-8000-000000000046',
  roomChem: 'b1a00000-0000-4000-8000-000000000047',
  roomLaydown: 'b1a00000-0000-4000-8000-000000000048',
  inspection: 'b1a00000-0000-4000-8000-000000000081',
  wallet: 'b1a00000-0000-4000-8000-0000000000c1',
  email: 'thandi.inspector.demo@example.invalid',
  name: 'Thandi Mokoena (fictitious)',
} as const;

/** Demonstration photos bundled with the app (clearly marked as such). */
export const DEMO_PHOTOS = {
  'demo:toe-boards': require('@/assets/demo/demo-photo-toe-boards.jpg'),
  'demo:register': require('@/assets/demo/demo-photo-register.jpg'),
  'demo:area': require('@/assets/demo/demo-photo-area.jpg'),
} as const;

type Row = { kind: Kind; record: KindMap[Kind] };

const TEMPLATES: { id: string; code: string; name: string; category: string; element: string; items: [string, string, string | null][] }[] = [
  {
    id: 'b1a00000-0000-4000-8000-000000000061', code: 'SCAFFOLDS', name: 'Scaffold inspection', category: 'scaffolds', element: 'HSF-F-01',
    items: [
      ['Foundation', 'Scaffold stands on sound base plates and sole boards', 'CNC-DEMO-SCAFF-01'],
      ['Platforms', 'Guard rails, mid rails and toe boards are in place on every working platform', 'CNC-DEMO-SCAFF-01'],
      ['Tagging', 'The scaffold tag shows a current inspection', 'CNC-DEMO-SCAFF-02'],
      ['Records', 'The scaffold inspection register is signed by the competent person', 'CNC-DEMO-SCAFF-02'],
      ['Access', 'The access ladder is secured and extends past the platform', null],
      ['Surroundings', 'The scaffold is clear of overhead power lines', null],
    ],
  },
  { id: 'b1a00000-0000-4000-8000-000000000062', code: 'LADDERS', name: 'Ladder inspection', category: 'ladders', element: 'HSF-F-02',
    items: [['Condition', 'Stiles and rungs are free of damage', null], ['Feet', 'Non slip feet are present and sound', null], ['Records', 'The ladder is on the ladder register with a current inspection', null]] },
  { id: 'b1a00000-0000-4000-8000-000000000063', code: 'LIFTING', name: 'Lifting machines and tackle inspection', category: 'lifting', element: 'HSF-F-03',
    items: [['Marking', 'The safe working load is marked on the machine and the tackle', null], ['Records', 'A current load test and inspection are on record', null], ['Condition', 'Hooks carry a working safety catch', null]] },
  { id: 'b1a00000-0000-4000-8000-000000000064', code: 'ELECTRICAL', name: 'Portable electrical equipment inspection', category: 'electrical', element: 'HSF-F-04',
    items: [['Leads', 'Leads and plugs are undamaged', null], ['Protection', 'Equipment is used through an earth leakage device', null], ['Records', 'The item is on the portable electrical register with a current inspection', null]] },
  { id: 'b1a00000-0000-4000-8000-000000000065', code: 'FIRE', name: 'Fire equipment inspection', category: 'fire', element: 'HSF-F-06',
    items: [['Access', 'Fire equipment is visible, signed and unobstructed', null], ['Service', 'The service tag is current', null], ['Condition', 'The pressure gauge reads in the green and the seal is intact', null]] },
  { id: 'b1a00000-0000-4000-8000-000000000066', code: 'PPE', name: 'Personal protective equipment inspection', category: 'ppe', element: 'HSF-F-11',
    items: [['Issue', 'PPE issued matches the risk assessment for the task', null], ['Condition', 'PPE in use is in good condition', null], ['Records', 'The PPE issue register is signed by each worker', null]] },
  { id: 'b1a00000-0000-4000-8000-000000000067', code: 'CHEMICALS', name: 'Hazardous chemical store inspection', category: 'chemicals', element: 'HSF-F-12',
    items: [['Register', 'Every chemical in the store is on the hazardous chemical agent register', null], ['Information', 'A current safety data sheet is available for every chemical', null], ['Storage', 'Incompatible chemicals are stored apart with spill containment', null]] },
];

export function templateItemId(templateIndex: number, ordinal: number): string {
  return `b1a00000-0000-4000-8000-0000000007${templateIndex}${ordinal}`;
}

export function demoSeed(now: Date = new Date()): Row[] {
  const today = todayIso(now);
  const iso = (daysAgo: number, hour = 9, minute = 0) => {
    const d = new Date(now);
    d.setDate(d.getDate() - daysAgo);
    d.setHours(hour, minute, 0, 0);
    return d.toISOString();
  };
  const rows: Row[] = [];
  const add = <K extends Kind>(kind: K, record: KindMap[K]) => rows.push({ kind, record: { row_version: 1, ...record } });

  add('company', {
    id: DEMO.company,
    legal_name: 'Rietvlei Civils and Building (Pty) Ltd (fictitious)',
    trading_name: 'Rietvlei Civils',
    registration_number: 'DEMO/0000/000000/07',
    cipc_status: 'in_business',
    s16_1_contact: 'Sipho Nkosi, Managing Director (fictitious)',
    s16_2_contact: 'Naledi Dlamini, SHE Manager (fictitious)',
    popia_contact: 'Naledi Dlamini (fictitious)',
    onboarding_status: 'active',
    fica_status: 'accepted',
    file_eligibility: 'eligible',
    file_eligibility_note: 'Demonstration: a verified Care Net client with 64 medicals in the last 12 months (fictitious count).',
  });

  add('person', { id: 'b1a00000-0000-4000-8000-0000000000d1', client_account_id: DEMO.company, full_name: 'Sipho Nkosi (fictitious)', roles: ['s16_1'], email: 'sipho.demo@example.invalid', mobile: null, appointed_on: addDaysIso(today, -400) });
  add('person', { id: 'b1a00000-0000-4000-8000-0000000000d2', client_account_id: DEMO.company, full_name: 'Naledi Dlamini (fictitious)', roles: ['s16_2', 'she_manager'], email: 'naledi.admin.demo@example.invalid', mobile: null, appointed_on: addDaysIso(today, -380) });
  add('person', { id: 'b1a00000-0000-4000-8000-0000000000d3', client_account_id: DEMO.company, full_name: 'Lerato Molefe (fictitious)', roles: ['she_rep', 'first_aider', 'fire_marshal'], email: null, mobile: null, appointed_on: addDaysIso(today, -120) });

  add('registration', { id: 'b1a00000-0000-4000-8000-0000000000e1', body: 'SACPCMP (demonstration record)', number: 'DEMO-CHSM-0001', category: 'Construction Health and Safety Manager', expires_on: addDaysIso(today, 330) });

  add('qualification', { id: 'b1a00000-0000-4000-8000-000000000027', qual_type: 'Construction Health and Safety Manager (fictitious)', issuer: 'SACPCMP (demonstration record)', number: 'DEMO-CHSM-0001', issued_on: addDaysIso(today, -400), expires_on: addDaysIso(today, 330), status: 'verified', document_name: 'demo-chsm.pdf' });
  add('qualification', { id: 'b1a00000-0000-4000-8000-0000000000e2', qual_type: 'Fire equipment inspector (fictitious)', issuer: 'Demonstration training provider', number: 'DEMO-FIRE-0042', issued_on: addDaysIso(today, -340), expires_on: addDaysIso(today, 25), status: 'verified', document_name: 'demo-fire.pdf' });

  const consent = (kind: KindMap['consent']['consent_kind'], granted: boolean) =>
    add('consent', { id: `demo-consent-${kind}`, consent_kind: kind, granted, wording_version: CONSENT_VERSIONS[kind], granted_at: granted ? iso(30) : null, confirmed_at: null, withdrawn_at: null });
  consent('terms', true);
  consent('privacy', true);
  consent('location', true);
  consent('voice_recording', true);
  consent('identifiable_people', false);
  consent('fica_processing', true);
  consent('marketing', false);

  add('inspector', {
    id: DEMO.inspector,
    display_name: DEMO.name,
    status: 'cleared',
    competence_scope: ['scaffolds', 'ladders', 'lifting', 'electrical', 'fire', 'ppe', 'chemicals', 'construction', 'general'],
    restricted_reason: null,
    identity_done: true,
    fica_done: true,
  });

  add('site', { id: DEMO.site, client_account_id: DEMO.company, name: 'Rietvlei Yard (fictitious)', address: '1 Demonstration Road, Pretoria East (fictitious)' });
  add('department', { id: DEMO.deptOps, site_id: DEMO.site, department_code: 'OPS', name: 'Site operations' });
  add('department', { id: DEMO.deptFac, site_id: DEMO.site, department_code: 'FAC', name: 'Stores and yard' });
  add('building', { id: DEMO.workshop, site_id: DEMO.site, department_id: DEMO.deptOps, name: 'Workshop block', kind: 'building' });
  add('building', { id: DEMO.yardB, site_id: DEMO.site, department_id: DEMO.deptFac, name: 'Yard zone B', kind: 'zone' });
  add('room', { id: DEMO.roomFloor, site_id: DEMO.site, building_id: DEMO.workshop, name: 'Workshop floor', kind: 'room' });
  add('room', { id: DEMO.roomChem, site_id: DEMO.site, building_id: DEMO.workshop, name: 'Chemical store', kind: 'room' });
  add('room', { id: DEMO.roomLaydown, site_id: DEMO.site, building_id: DEMO.yardB, name: 'Scaffold laydown area', kind: 'area' });

  const eq = (id: string, tag: string, kind: string, description: string, serial: string | null) =>
    add('equipment', { id, client_account_id: DEMO.company, site_id: DEMO.site, tag_code: tag, kind, description, serial_number: serial });
  eq('b1a00000-0000-4000-8000-000000000051', 'DEMO-SCAF-014', 'Tube and clamp scaffold', 'Scaffold bay 14, yard zone B (fictitious)', null);
  eq('b1a00000-0000-4000-8000-000000000052', 'DEMO-LAD-003', 'Aluminium extension ladder', 'Workshop ladder 3 (fictitious)', 'DEMO-SN-LAD-3');
  eq('b1a00000-0000-4000-8000-000000000053', 'DEMO-FE-021', 'Dry chemical powder fire extinguisher', 'Chemical store door (fictitious)', 'DEMO-SN-FE-21');
  eq('b1a00000-0000-4000-8000-000000000054', 'DEMO-CB-002', 'Chain block', 'Workshop gantry (fictitious)', 'DEMO-SN-CB-2');

  TEMPLATES.forEach((t, ti) => {
    add('template', { id: t.id, code: t.code, name: t.name, category: t.category, section_f_element_code: t.element, description: `Demonstration template. Files into Section F register ${t.element}.` });
    t.items.forEach(([section, prompt, ref], i) =>
      add('template_item', { id: templateItemId(ti + 1, i + 1), template_id: t.id, ordinal: i + 1, section_label: section, prompt, kernel_ref: ref }),
    );
  });

  // The scaffold inspection in progress (walked yesterday, still open).
  const insp = DEMO.inspection;
  add('inspection', {
    id: insp, tenant_id: DEMO.tenant, client_account_id: DEMO.company, site_id: DEMO.site, template_id: TEMPLATES[0].id,
    inspector_user_id: DEMO.inspector, title: 'Scaffold inspection, Rietvlei Yard (fictitious)', status: 'in_progress',
    voice_note_policy: 'strict', started_at: iso(1, 9), submitted_at: null, device_id: 'DEMO-DEVICE-01',
  });
  const A1 = 'b1a00000-0000-4000-8000-000000000082';
  const A2 = 'b1a00000-0000-4000-8000-000000000083';
  const A3 = 'b1a00000-0000-4000-8000-000000000084';
  add('area', { id: A1, inspection_id: insp, room_id: DEMO.roomLaydown, label: 'Scaffold laydown area', ordinal: 1 });
  add('area', { id: A2, inspection_id: insp, room_id: DEMO.roomFloor, label: 'Workshop floor', ordinal: 2 });
  add('area', { id: A3, inspection_id: insp, room_id: DEMO.roomChem, label: 'Chemical store', ordinal: 3 });

  const f = (id: string, area: string, ord: number, equip: string | null, result: KindMap['finding']['result'], note: string, sev: KindMap['finding']['severity'], minute: number) =>
    add('finding', {
      id, inspection_id: insp, area_id: area, template_item_id: templateItemId(1, ord), equipment_id: equip, result, note, severity: sev,
      captured_by: DEMO.inspector, captured_at: iso(1, 9, minute), gps_lat: -25.79, gps_lng: 28.3,
    });
  f('b1a00000-0000-4000-8000-000000000091', A1, 1, 'b1a00000-0000-4000-8000-000000000051', 'pass', 'Base plates and sole boards sound on bay 14.', null, 1);
  f('b1a00000-0000-4000-8000-000000000092', A1, 2, 'b1a00000-0000-4000-8000-000000000051', 'fail', 'Toe boards missing on the second lift of bay 14.', 'high', 2);
  f('b1a00000-0000-4000-8000-000000000093', A1, 3, 'b1a00000-0000-4000-8000-000000000051', 'observe', 'Tag inspection falls due in three days.', 'low', 3);
  f('b1a00000-0000-4000-8000-000000000094', A2, 5, null, 'pass', 'Access ladder tied in and extends past the platform.', null, 5);
  f('b1a00000-0000-4000-8000-000000000095', A2, 4, null, 'fail', 'Last two weekly entries in the scaffold register are unsigned.', 'medium', 4);
  f('b1a00000-0000-4000-8000-000000000096', A3, 6, null, 'na', 'No scaffold near the chemical store.', null, 6);

  const photo = (id: string, area: string, finding: string | null, kind: KindMap['photo']['kind'], file: string, local: string, caption: string, minute: number) =>
    add('photo', {
      id, inspection_id: insp, area_id: area, finding_id: finding, equipment_id: null, kind,
      storage_path: `${DEMO.company}/${insp}/${file}`, sha256: 'd'.repeat(64), size_bytes: 30000, mime_type: 'image/jpeg',
      captured_at: iso(1, 9, minute), gps_lat: -25.79, gps_lng: 28.3, gps_accuracy_m: 4.5, inspector_user_id: DEMO.inspector,
      caption, annotations: [], identifiable_people: false, people_consent_ref: null, _seal_local: 'demonstration', _local_uri: local,
    });
  photo('b1a00000-0000-4000-8000-0000000000a1', A1, null, 'area', 'demo-area-laydown.jpg', 'demo:area', 'Scaffold laydown area, general view (fictitious)', 0);
  photo('b1a00000-0000-4000-8000-0000000000a2', A1, 'b1a00000-0000-4000-8000-000000000092', 'risk_close_up', 'demo-missing-toe-boards.jpg', 'demo:toe-boards', 'Missing toe boards, second lift, bay 14 (fictitious)', 3);
  photo('b1a00000-0000-4000-8000-0000000000a3', A2, 'b1a00000-0000-4000-8000-000000000095', 'other', 'demo-register-unsigned.jpg', 'demo:register', 'Scaffold register, unsigned entries (fictitious)', 4);

  add('voice_note', {
    id: 'b1a00000-0000-4000-8000-0000000000b1', inspection_id: insp, area_id: A1, finding_id: 'b1a00000-0000-4000-8000-000000000092', vn_number: 1,
    audio_path: `${DEMO.company}/${insp}/demo-vn-1.m4a`, audio_sha256: 'e'.repeat(64), size_bytes: 48000, mime_type: 'audio/mp4', duration_seconds: 21,
    captured_at: iso(1, 9, 3), gps_lat: -25.79, gps_lng: 28.3, inspector_user_id: DEMO.inspector, _seal_local: 'demonstration', _local_uri: 'demo:no-audio',
  });
  add('transcript', { id: 'b1a00000-0000-4000-8000-0000000000b2', voice_note_id: 'b1a00000-0000-4000-8000-0000000000b1', version: 1, source: 'machine', body: 'Bay fourteen second lift toe boards missing on the east side, workers below in the laydown area.', created_by: null });
  add('transcript', { id: 'b1a00000-0000-4000-8000-0000000000b3', voice_note_id: 'b1a00000-0000-4000-8000-0000000000b1', version: 2, source: 'correction', body: 'Bay 14, second lift: toe boards missing on the east side; people work below in the laydown area.', created_by: DEMO.inspector });

  add('risk', {
    id: 'b1a00000-0000-4000-8000-0000000000c5', inspection_id: insp, area_id: A1, finding_id: 'b1a00000-0000-4000-8000-000000000092',
    hazard: 'Objects falling from the second lift onto people below', consequence: 'Head injury to people working in the laydown area',
    inherent_likelihood: 4, inherent_severity: 4, controls: [{ level: 'engineering', description: 'Fit toe boards on every working platform' }, { level: 'administrative', description: 'Barricade the area below until fixed' }],
    residual_likelihood: 2, residual_severity: 3,
  });
  add('action', {
    id: 'b1a00000-0000-4000-8000-0000000000c6', inspection_id: insp, finding_id: 'b1a00000-0000-4000-8000-000000000092', risk_id: 'b1a00000-0000-4000-8000-0000000000c5',
    description: 'Fit toe boards to the second lift of bay 14 and barricade below until done.', owner_name: 'Site foreman (fictitious)', due_on: addDaysIso(today, 2), status: 'open',
  });
  // The second Fail (unsigned register) still needs a corrective action and a voice note: the Fail rule shows it.

  // An earlier fire equipment inspection, Issued and filed into Section F.
  const past = 'b1a00000-0000-4000-8000-0000000000f1';
  add('inspection', {
    id: past, tenant_id: DEMO.tenant, client_account_id: DEMO.company, site_id: DEMO.site, template_id: TEMPLATES[4].id,
    inspector_user_id: DEMO.inspector, title: 'Fire equipment inspection, Workshop block (fictitious)', status: 'submitted',
    voice_note_policy: 'strict', started_at: iso(32, 10), submitted_at: iso(32, 12), device_id: 'DEMO-DEVICE-01',
  });
  add('report', {
    id: 'b1a00000-0000-4000-8000-0000000000f2', inspection_id: past, status: 'issued', version: 1, source: 'template',
    content: {
      label: 'Assistive draft. Competent person sign off required.',
      footer: 'This report is powered by Care Net Consultants Development House (Pty) Ltd',
      title: 'Fire equipment inspection, Workshop block (fictitious)',
      executive_summary: '3 checklist items recorded across 1 areas: 3 Pass, 0 Fail, 0 Observe, 0 N/A.',
      findings: [], claims: [], uncited: [], voice_notes: { total: 0, accounted: 0, missing: 0 }, corrective_actions: [], risk_register: [],
    },
    charged_cents: null, signed_by: DEMO.name, signed_at: iso(31, 15), issued_at: iso(31, 15), file_link_status: 'linked', section_f_element_code: 'HSF-F-06', reviewer_requested_at: null,
  });

  // The AI Wallet: R150,00 included less R11,80, plus a R249,00 top up (R260,00 value) = R398,20.
  add('wallet', { id: DEMO.wallet, client_account_id: DEMO.company, status: 'active', monthly_spend_cap_cents: null, auto_topup_enabled: false });
  const first = new Date(now.getFullYear(), now.getMonth(), 1);
  const incExpiry = new Date(now.getFullYear(), now.getMonth() + 2, 1).toISOString();
  add('ledger', { id: 'demo-ledger-1', wallet_id: DEMO.wallet, entry_kind: 'included_credit', amount_cents: 15000, lot_id: null, expires_at: incExpiry, note: 'Included with the base plan this month', created_at: first.toISOString() });
  add('ledger', { id: 'demo-ledger-2', wallet_id: DEMO.wallet, entry_kind: 'charge', amount_cents: -1180, lot_id: 'demo-ledger-1', expires_at: null, note: 'AI draft, fire equipment inspection (demonstration)', created_at: iso(31, 14) });
  add('ledger', { id: 'demo-ledger-3', wallet_id: DEMO.wallet, entry_kind: 'topup_credit', amount_cents: 26000, lot_id: null, expires_at: new Date(now.getFullYear() + 1, now.getMonth(), now.getDate()).toISOString(), note: 'Top up R249,00 (R260,00 value)', created_at: iso(12, 11) });
  add('subsidy', { id: 'demo-subsidy-1', wallet_id: DEMO.wallet, shortfall_cents: 1988, estimate_cents: 5994, actual_cents: 5994, what: 'an AI draft on a ladder inspection (demonstration)', created_at: iso(15, 16) });

  return rows;
}

export const DEMO_TEMPLATE_IDS = TEMPLATES.map((t) => t.id);
