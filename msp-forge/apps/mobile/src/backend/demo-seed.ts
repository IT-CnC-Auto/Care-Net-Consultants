// Demonstration data: five FICTITIOUS companies from five industries, so the
// app shows it is built for all 17 kernel industries and not for construction
// only. The companies are the fictitious sample companies of the File site
// (vercel/hsf/samples: construction, mining, healthcare, retail, agriculture);
// Rietvlei Civils and Building keeps the ids of supabase/seed/bee_inspect_demo.sql.
// Every name, number, place, photo and document here is FICTITIOUS. The
// inspection templates are the kernel's (assets/kernel/kernel-bundle.json).

import { CONSENT_VERSIONS } from '@/lib/constants';
import { addDaysIso, todayIso } from '@/lib/dates';
import { blobId, canonicalPath, casKey, normaliseTags } from '@/lib/evidence-store';
import { kernel, template as kernelTemplate } from '@/lib/kernel';
import { pathOf, slug } from '@/lib/places';
import type { BlobRecord, EvidenceMeta, Kind, KindMap, Place } from '@/lib/types';

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

const id = (n: number) => `b1a00000-0000-4000-8000-${String(n).padStart(12, '0')}`;

/** The other four demonstration companies (msp_client_account ids of the demo). */
export const DEMO_COMPANIES = {
  construction: DEMO.company,
  mining: id(2000),
  healthcare: id(3000),
  retail: id(4000),
  agriculture: id(5000),
} as const;

/** Demonstration photos bundled with the app (clearly marked as such in the picture). */
export const DEMO_PHOTOS = {
  'demo:toe-boards': require('@/assets/demo/demo-photo-toe-boards.jpg'),
  'demo:register': require('@/assets/demo/demo-photo-register.jpg'),
  'demo:area': require('@/assets/demo/demo-photo-area.jpg'),
  'demo:conveyor': require('@/assets/demo/demo-photo-conveyor.jpg'),
  'demo:lab': require('@/assets/demo/demo-photo-lab.jpg'),
  'demo:racking': require('@/assets/demo/demo-photo-racking.jpg'),
  'demo:chemicals': require('@/assets/demo/demo-photo-chemicals.jpg'),
} as const;

/** The SHA 256 and size of each demonstration photo (checked against the files by the tests). */
export const DEMO_PHOTO_BYTES: Record<keyof typeof DEMO_PHOTOS, { file: string; sha256: string; size: number }> = {
  'demo:toe-boards': { file: 'demo-photo-toe-boards.jpg', sha256: '75dfa0d330f21d3db3fdd0079964d3844adb1f4b5a672892592c831d23d1188f', size: 30169 },
  'demo:register': { file: 'demo-photo-register.jpg', sha256: 'd368c9f642f7079b55cac910772f10ad0e158be3e311d6d2558149cf5050447f', size: 29798 },
  'demo:area': { file: 'demo-photo-area.jpg', sha256: 'a86b9e1cd1423323daa2484d36f58ec0a2d86d97521db925585a64af9900fa72', size: 29993 },
  'demo:conveyor': { file: 'demo-photo-conveyor.jpg', sha256: 'c5d482f621513848eba5119ed879aef9172b906487d13affd3176b0e06c10cdf', size: 33082 },
  'demo:lab': { file: 'demo-photo-lab.jpg', sha256: 'c0303f8de73e74b3e70bf4c1afd0c3fc0de9f760787dbf0f82c796708d69c2ac', size: 28723 },
  'demo:racking': { file: 'demo-photo-racking.jpg', sha256: '4f18abe1a56809943d8a6d6ee5491b29c635fc3108ac1862abb7d72fec4878a7', size: 39756 },
  'demo:chemicals': { file: 'demo-photo-chemicals.jpg', sha256: '1f6d0f515b800065a1d232da1a818b7602d1afea9ce3bfc22f9bf6a6ca030916', size: 39321 },
};

type Row = { kind: Kind; record: KindMap[Kind] };

/** A kernel template's id and the id of its item at an ordinal. */
function tpl(code: string) {
  const t = kernelTemplate(kernel(), code);
  if (!t) throw new Error(`The kernel bundle has no template ${code}`);
  return { id: t.id, item: (ordinal: number) => t.items[ordinal - 1].id, t };
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
  const places: Place[] = [];

  // Companies ------------------------------------------------------------------------------------
  const company = (cid: string, legal: string, trading: string, reg: string, ind: string, sub: string, s161: string, s162: string, medicals: string) =>
    add('company', {
      id: cid,
      legal_name: `${legal} (fictitious)`,
      trading_name: trading,
      registration_number: reg,
      cipc_status: 'in_business',
      s16_1_contact: `${s161} (fictitious)`,
      s16_2_contact: `${s162} (fictitious)`,
      popia_contact: `${s162} (fictitious)`,
      onboarding_status: 'active',
      fica_status: 'accepted',
      file_eligibility: 'eligible',
      file_eligibility_note: `Demonstration: a verified Care Net client with ${medicals} medicals in the last 12 months (fictitious count).`,
      industry_code: ind,
      subindustry_code: sub,
    });
  company(DEMO_COMPANIES.construction, 'Rietvlei Civils and Building (Pty) Ltd', 'Rietvlei Civils', 'DEMO/0000/000000/07', 'CONSTR', 'CONSTR-CIVILS', 'Sipho Nkosi, Managing Director', 'Naledi Dlamini, SHE Manager', '64');
  company(DEMO_COMPANIES.mining, 'Magaliesberg Aggregates (Pty) Ltd', 'Magaliesberg Aggregates', 'DEMO/0000/000002/07', 'MINING', 'MIN-QUARRY', 'Johan van der Merwe, Chief Executive', 'Ayanda Khumalo, Mine Manager', '128');
  company(DEMO_COMPANIES.healthcare, 'Karoo Pathology and Day Hospital (Pty) Ltd', 'Karoo Day Hospital', 'DEMO/0000/000003/07', 'HEALTH', 'HLTH-HOSP', 'Anika Botha, Chief Executive', 'Refilwe Molefe, Health and Safety Manager', '96');
  company(DEMO_COMPANIES.retail, 'Midlands Wholesale Distributors (Pty) Ltd', 'Midlands Wholesale', 'DEMO/0000/000004/07', 'RETAIL', 'RET-WHOLE', 'Mohammed Pillay, Managing Director', 'Zanele Ndlovu, Health and Safety Officer', '156');
  company(DEMO_COMPANIES.agriculture, 'Umzimkhulu Valley Farming (Pty) Ltd', 'Umzimkhulu Valley', 'DEMO/0000/000005/07', 'AGRI', 'AGRI-CROP', 'Kobus Fourie, Managing Director', 'Themba Zulu, Farm Manager', '86');

  // People --------------------------------------------------------------------------------------------
  const person = (pid: string, cid: string, name: string, roles: KindMap['person']['roles'], email: string | null, days: number) =>
    add('person', { id: pid, client_account_id: cid, full_name: `${name} (fictitious)`, roles, email, mobile: null, appointed_on: addDaysIso(today, -days) });
  person('b1a00000-0000-4000-8000-0000000000d1', DEMO.company, 'Sipho Nkosi', ['s16_1'], 'sipho.demo@example.invalid', 400);
  person('b1a00000-0000-4000-8000-0000000000d2', DEMO.company, 'Naledi Dlamini', ['s16_2', 'she_manager'], 'naledi.admin.demo@example.invalid', 380);
  person('b1a00000-0000-4000-8000-0000000000d3', DEMO.company, 'Lerato Molefe', ['she_rep', 'first_aider', 'fire_marshal'], null, 120);
  person(id(2901), DEMO_COMPANIES.mining, 'Johan van der Merwe', ['s16_1'], null, 700);
  person(id(2902), DEMO_COMPANIES.mining, 'Ayanda Khumalo', ['s16_2', 'she_manager'], null, 500);
  person(id(3901), DEMO_COMPANIES.healthcare, 'Anika Botha', ['s16_1'], null, 600);
  person(id(3902), DEMO_COMPANIES.healthcare, 'Refilwe Molefe', ['s16_2', 'she_manager'], null, 300);
  person(id(4901), DEMO_COMPANIES.retail, 'Mohammed Pillay', ['s16_1'], null, 900);
  person(id(4902), DEMO_COMPANIES.retail, 'Zanele Ndlovu', ['s16_2', 'she_officer', 'assistant'], null, 210);
  person(id(5901), DEMO_COMPANIES.agriculture, 'Kobus Fourie', ['s16_1'], null, 1200);
  person(id(5902), DEMO_COMPANIES.agriculture, 'Themba Zulu', ['s16_2', 'first_aider'], null, 400);

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
    competence_scope: ['scaffolds', 'ladders', 'lifting', 'electrical', 'fire', 'ppe', 'chemicals', 'construction', 'manufacturing', 'mining', 'agriculture', 'clinics', 'mobiles', 'general'],
    restricted_reason: null,
    identity_done: true,
    fica_done: true,
  });

  // Places trees (typed nodes; kernel place types) -------------------------------------------------------
  const place = (pid: string, cid: string, parent: string | null, type: string, name: string, extra: Partial<Place> = {}) => {
    const p: Place = {
      id: pid, client_account_id: cid, parent_id: parent, place_type: type, custom_type_label: null, name, address: null, gps_lat: null, gps_lng: null,
      responsible_person: null, headcount: null, department_code: null, linked_department_ids: [], archived_at: null, ...extra,
    };
    places.push(p);
    add('place', p);
  };
  // Construction: Rietvlei Civils and Building.
  const C1 = DEMO_COMPANIES.construction;
  place(DEMO.site, C1, null, 'site', 'Rietvlei Yard', { address: '1 Demonstration Road, Pretoria East (fictitious)', gps_lat: -25.79, gps_lng: 28.3, responsible_person: 'Naledi Dlamini (fictitious)', headcount: 48 });
  place(DEMO.deptOps, C1, DEMO.site, 'department', 'Site operations', { department_code: 'OPS' });
  place(DEMO.deptFac, C1, DEMO.site, 'department', 'Stores and yard', { department_code: 'FAC' });
  place(DEMO.workshop, C1, DEMO.deptOps, 'building_block', 'Workshop block');
  place(DEMO.yardB, C1, DEMO.deptFac, 'building_block', 'Yard zone B', { custom_type_label: 'Zone' });
  place(DEMO.roomFloor, C1, DEMO.workshop, 'room_area', 'Workshop floor');
  place(DEMO.roomChem, C1, DEMO.workshop, 'room_area', 'Chemical store');
  place(DEMO.roomLaydown, C1, DEMO.yardB, 'room_area', 'Scaffold laydown area');
  place(id(1101), C1, null, 'construction_project', 'Two storey clinic build', { address: 'Erf 12, Rietvlei (fictitious)', responsible_person: 'Construction manager (fictitious)', headcount: 16 });
  place(id(1102), C1, id(1101), 'building_block', 'Clinic block');
  place(id(1103), C1, id(1102), 'floor', 'First floor slab');
  place(id(1104), C1, id(1101), 'vehicle_fleet', 'Plant and vehicles');
  // Mining: Magaliesberg Aggregates.
  const C2 = DEMO_COMPANIES.mining;
  place(id(2101), C2, null, 'mine_section', 'Open pit', { address: 'Portion 4, Magaliesberg (fictitious)', gps_lat: -25.7, gps_lng: 27.6, responsible_person: 'Ayanda Khumalo (fictitious)', headcount: 60 });
  place(id(2102), C2, id(2101), 'mine_section', 'Bench 3 north face');
  place(id(2103), C2, id(2101), 'vehicle_fleet', 'Haul trucks');
  place(id(2104), C2, null, 'factory_plant', 'Crushing and screening plant', { responsible_person: 'Plant engineer (fictitious)', headcount: 38 });
  place(id(2105), C2, id(2104), 'room_area', 'Primary crusher');
  place(id(2106), C2, id(2104), 'room_area', 'Conveyor 2 tail pulley');
  place(id(2107), C2, id(2104), 'workshop', 'Plant workshop');
  place(id(2108), C2, id(2104), 'department', 'Engineering', { department_code: 'ENG' });
  place(id(2109), C2, null, 'office', 'Site office and weighbridge', { headcount: 12 });
  // Healthcare: Karoo Pathology and Day Hospital.
  const C3 = DEMO_COMPANIES.healthcare;
  place(id(3101), C3, null, 'site', 'Day hospital', { address: '8 Demonstration Street, Beaufort West (fictitious)', responsible_person: 'Refilwe Molefe (fictitious)', headcount: 96 });
  place(id(3102), C3, id(3101), 'building_block', 'Main block');
  place(id(3103), C3, id(3102), 'floor', 'Ground floor');
  place(id(3104), C3, id(3103), 'room_area', 'Theatre 1');
  place(id(3105), C3, id(3103), 'room_area', 'Sluice room');
  place(id(3106), C3, id(3101), 'clinic_lab', 'Pathology laboratory', { responsible_person: 'Laboratory manager (fictitious)', headcount: 14 });
  place(id(3107), C3, id(3106), 'room_area', 'Specimen reception');
  place(id(3108), C3, id(3101), 'department', 'Facilities', { department_code: 'FAC' });
  // Retail and wholesale: Midlands Wholesale Distributors.
  const C4 = DEMO_COMPANIES.retail;
  place(id(4101), C4, null, 'retail_store', 'Cash and carry store', { address: '22 Demonstration Avenue, Pietermaritzburg (fictitious)', headcount: 88 });
  place(id(4102), C4, id(4101), 'room_area', 'Aisle 7 racking');
  place(id(4103), C4, id(4101), 'room_area', 'Cold rooms');
  place(id(4104), C4, null, 'warehouse', 'Distribution centre', { responsible_person: 'Zanele Ndlovu (fictitious)', headcount: 54 });
  place(id(4105), C4, id(4104), 'room_area', 'Loading dock');
  place(id(4106), C4, id(4104), 'room_area', 'High bay racking');
  place(id(4107), C4, id(4104), 'vehicle_fleet', 'Forklifts');
  place(id(4108), C4, null, 'vehicle_fleet', 'Delivery fleet', { headcount: 14 });
  // Agriculture: Umzimkhulu Valley Farming.
  const C5 = DEMO_COMPANIES.agriculture;
  place(id(5101), C5, null, 'farm', 'Citrus and timber estate', { address: 'Farm 17, Umzimkhulu (fictitious)', responsible_person: 'Themba Zulu (fictitious)', headcount: 62 });
  place(id(5102), C5, id(5101), 'room_area', 'Farm chemical store');
  place(id(5103), C5, id(5101), 'workshop', 'Tractor workshop');
  place(id(5104), C5, id(5101), 'vehicle_fleet', 'Tractors and trailers');
  place(id(5105), C5, null, 'factory_plant', 'Packhouse', { headcount: 24 });
  place(id(5106), C5, id(5105), 'room_area', 'Grading line');
  place(id(5107), C5, id(5105), 'department', 'Operations', { department_code: 'OPS' });

  const eq = (eid: string, cid: string, site: string, tag: string, kind: string, description: string, serial: string | null) =>
    add('equipment', { id: eid, client_account_id: cid, site_id: site, tag_code: tag, kind, description, serial_number: serial });
  eq('b1a00000-0000-4000-8000-000000000051', C1, DEMO.site, 'DEMO-SCAF-014', 'Tube and clamp scaffold', 'Scaffold bay 14, yard zone B (fictitious)', null);
  eq('b1a00000-0000-4000-8000-000000000052', C1, DEMO.site, 'DEMO-LAD-003', 'Aluminium extension ladder', 'Workshop ladder 3 (fictitious)', 'DEMO-SN-LAD-3');
  eq('b1a00000-0000-4000-8000-000000000053', C1, DEMO.site, 'DEMO-FE-021', 'Dry chemical powder fire extinguisher', 'Chemical store door (fictitious)', 'DEMO-SN-FE-21');
  eq('b1a00000-0000-4000-8000-000000000054', C1, DEMO.site, 'DEMO-CB-002', 'Chain block', 'Workshop gantry (fictitious)', 'DEMO-SN-CB-2');
  eq(id(2201), C2, id(2104), 'DEMO-CV-002', 'Belt conveyor', 'Conveyor 2, crushing plant (fictitious)', 'DEMO-SN-CV-2');
  eq(id(4201), C4, id(4104), 'DEMO-RK-HB07', 'Pallet racking bay', 'High bay 7 (fictitious)', null);

  // Evidence helpers ----------------------------------------------------------------------------------------
  const blobs = new Map<string, BlobRecord>();
  const blobRef = (cid: string, key: keyof typeof DEMO_PHOTOS) => {
    const f = DEMO_PHOTO_BYTES[key];
    const bid = blobId(cid, f.sha256);
    const cur = blobs.get(bid);
    blobs.set(bid, cur ? { ...cur, refs: cur.refs + 1 } : {
      id: bid, sha256: f.sha256, client_account_id: cid, size_bytes: f.size, mime_type: 'image/jpeg', local_uri: key, refs: 1, variant: 'original',
      derived_from: null, exif_stripped: false, uploaded: true, verified_at: iso(1, 18), row_version: 1,
    });
    return f;
  };
  const meta = (cid: string, inspId: string, placeId: string, itemKey: string, eid: string, templateItemId: string | null, tags: string[], retention: string | null): EvidenceMeta => ({
    evidence_version: 1, root_evidence_id: null, supersedes_id: null,
    canonical_path: canonicalPath({ tenantId: DEMO.tenant, companyId: cid, placeSlugs: pathOf(places, placeId).map((p) => slug(p.name)), inspectionId: inspId, itemKey, evidenceId: eid, version: 1 }),
    place_id: placeId, template_item_id: templateItemId, device_id: 'DEMO-DEVICE-01', tags: normaliseTags(tags), retention_class: retention, legal_hold: false, sidecar_sha256: null,
    _thumb_uri: null, _web_uri: null, _upload: { session_id: 'demo', sha256: '', size_bytes: 1, chunk_bytes: 5242880, done: [0], verified: true, verified_sha256: null, attempts: 1, last_error: null },
  });
  const photo = (p: { pid: string; cid: string; insp: string; area: string; place: string; finding: string | null; item: string | null; kind: KindMap['photo']['kind']; key: keyof typeof DEMO_PHOTOS; caption: string; at: string; lat: number; lng: number; tags: string[]; retention: string | null }) => {
    const f = blobRef(p.cid, p.key);
    const m = meta(p.cid, p.insp, p.place, p.item ?? `area-${p.area}`, p.pid, p.item, p.tags, p.retention);
    add('photo', {
      id: p.pid, inspection_id: p.insp, area_id: p.area, finding_id: p.finding, equipment_id: null, kind: p.kind,
      storage_path: `${p.cid}/${casKey(f.sha256)}`, sha256: f.sha256, size_bytes: f.size, mime_type: 'image/jpeg',
      captured_at: p.at, gps_lat: p.lat, gps_lng: p.lng, gps_accuracy_m: 4.5, inspector_user_id: DEMO.inspector,
      caption: p.caption, annotations: [], identifiable_people: false, people_consent_ref: null, _seal_local: 'demonstration', _local_uri: p.key,
      ...m, _upload: { ...(m._upload as NonNullable<EvidenceMeta['_upload']>), sha256: f.sha256, size_bytes: f.size, verified_sha256: f.sha256 },
    });
  };
  const inspection = (iid: string, cid: string, place: string, code: string, title: string, status: KindMap['inspection']['status'], started: string, submitted: string | null) =>
    add('inspection', {
      id: iid, tenant_id: DEMO.tenant, client_account_id: cid, site_id: pathOf(places, place)[0].id, place_id: place, template_id: tpl(code).id,
      inspector_user_id: DEMO.inspector, title: `${title} (fictitious)`, status, voice_note_policy: 'strict', started_at: started, submitted_at: submitted, device_id: 'DEMO-DEVICE-01',
    });
  const area = (aid: string, iid: string, place: string, label: string, ordinal: number) => add('area', { id: aid, inspection_id: iid, room_id: null, place_id: place, label, ordinal });
  const finding = (fid: string, iid: string, aid: string, item: string, result: KindMap['finding']['result'], note: string, sev: KindMap['finding']['severity'], at: string, equip: string | null = null) =>
    add('finding', { id: fid, inspection_id: iid, area_id: aid, template_item_id: item, equipment_id: equip, result, note, severity: sev, captured_by: DEMO.inspector, captured_at: at, gps_lat: -25.79, gps_lng: 28.3 });

  // 1. Construction: the scaffold register inspection in progress (walked yesterday) ---------------------------
  const F01 = tpl('REG-F-01');
  const insp = DEMO.inspection;
  inspection(insp, C1, DEMO.site, 'REG-F-01', 'Scaffold register and inspections, Rietvlei Yard', 'in_progress', iso(1, 9), null);
  const A1 = 'b1a00000-0000-4000-8000-000000000082';
  const A2 = 'b1a00000-0000-4000-8000-000000000083';
  const A3 = 'b1a00000-0000-4000-8000-000000000084';
  area(A1, insp, DEMO.roomLaydown, 'Scaffold laydown area', 1);
  area(A2, insp, DEMO.roomFloor, 'Workshop floor', 2);
  area(A3, insp, DEMO.roomChem, 'Chemical store', 3);
  const FA = 'b1a00000-0000-4000-8000-000000000092';
  const FB = 'b1a00000-0000-4000-8000-000000000095';
  finding('b1a00000-0000-4000-8000-000000000091', insp, A1, F01.item(1), 'pass', 'Register lists bay 14 by number, location and erection date.', null, iso(1, 9, 1), 'b1a00000-0000-4000-8000-000000000051');
  finding(FA, insp, A1, F01.item(3), 'fail', 'Bay 14 in use with no handover tag; toe boards missing on the second lift.', 'high', iso(1, 9, 2), 'b1a00000-0000-4000-8000-000000000051');
  finding('b1a00000-0000-4000-8000-000000000093', insp, A1, F01.item(6), 'observe', 'No inspection recorded after the strong wind on Tuesday; the next one falls due in three days.', 'low', iso(1, 9, 3));
  finding('b1a00000-0000-4000-8000-000000000094', insp, A2, F01.item(5), 'pass', 'Hired scaffold from the subcontractor is on the register.', null, iso(1, 9, 5));
  finding(FB, insp, A2, F01.item(4), 'fail', 'Last two weekly entries in the scaffold register are signed by the foreman, not the appointed inspector.', 'medium', iso(1, 9, 4));
  finding('b1a00000-0000-4000-8000-000000000096', insp, A3, F01.item(2), 'na', 'No scaffold near the chemical store.', null, iso(1, 9, 6));
  photo({ pid: 'b1a00000-0000-4000-8000-0000000000a1', cid: C1, insp, area: A1, place: DEMO.roomLaydown, finding: null, item: null, kind: 'area', key: 'demo:area', caption: 'Scaffold laydown area, general view (fictitious)', at: iso(1, 9, 0), lat: -25.79, lng: 28.3, tags: ['scaffold', 'room or area'], retention: F01.t.retention.class });
  photo({ pid: 'b1a00000-0000-4000-8000-0000000000a2', cid: C1, insp, area: A1, place: DEMO.roomLaydown, finding: FA, item: F01.item(3), kind: 'risk_close_up', key: 'demo:toe-boards', caption: 'Missing toe boards, second lift, bay 14 (fictitious)', at: iso(1, 9, 3), lat: -25.79, lng: 28.3, tags: ['fail', 'HSF-F-01', 'scaffold'], retention: F01.t.retention.class });
  photo({ pid: 'b1a00000-0000-4000-8000-0000000000a3', cid: C1, insp, area: A2, place: DEMO.roomFloor, finding: FB, item: F01.item(4), kind: 'other', key: 'demo:register', caption: 'Scaffold register, entries signed by the wrong person (fictitious)', at: iso(1, 9, 4), lat: -25.79, lng: 28.3, tags: ['fail', 'HSF-F-01', 'register'], retention: F01.t.retention.class });
  add('voice_note', {
    id: 'b1a00000-0000-4000-8000-0000000000b1', inspection_id: insp, area_id: A1, finding_id: FA, vn_number: 1,
    audio_path: `${C1}/${casKey('e'.repeat(64))}`, audio_sha256: 'e'.repeat(64), size_bytes: 48000, mime_type: 'audio/mp4', duration_seconds: 21,
    captured_at: iso(1, 9, 3), gps_lat: -25.79, gps_lng: 28.3, inspector_user_id: DEMO.inspector, _seal_local: 'demonstration', _local_uri: 'demo:no-audio',
    ...meta(C1, insp, DEMO.roomLaydown, F01.item(3), 'b1a00000-0000-4000-8000-0000000000b1', F01.item(3), ['voice note', 'scaffold'], F01.t.retention.class),
  });
  add('transcript', { id: 'b1a00000-0000-4000-8000-0000000000b2', voice_note_id: 'b1a00000-0000-4000-8000-0000000000b1', version: 1, source: 'machine', body: 'Bay fourteen second lift toe boards missing on the east side, workers below in the laydown area.', created_by: null });
  add('transcript', { id: 'b1a00000-0000-4000-8000-0000000000b3', voice_note_id: 'b1a00000-0000-4000-8000-0000000000b1', version: 2, source: 'correction', body: 'Bay 14, second lift: toe boards missing on the east side; people work below in the laydown area.', created_by: DEMO.inspector });
  add('risk', {
    id: 'b1a00000-0000-4000-8000-0000000000c5', inspection_id: insp, area_id: A1, finding_id: FA,
    hazard: 'Objects falling from the second lift onto people below', consequence: 'Head injury to people working in the laydown area',
    inherent_likelihood: 4, inherent_severity: 4, controls: [{ level: 'engineering', description: 'Fit toe boards on every working platform' }, { level: 'administrative', description: 'Barricade the area below until fixed' }],
    residual_likelihood: 2, residual_severity: 3,
  });
  add('action', { id: 'b1a00000-0000-4000-8000-0000000000c6', inspection_id: insp, finding_id: FA, risk_id: 'b1a00000-0000-4000-8000-0000000000c5', description: 'Fit toe boards to the second lift of bay 14, tag the scaffold and barricade below until done.', owner_name: 'Site foreman (fictitious)', due_on: addDaysIso(today, 2), status: 'open' });
  // The second Fail (register signed by the wrong person) still needs a corrective action and a voice note: the Fail rule shows it.

  // An earlier fire equipment register inspection, Issued and filed into Section F.
  const past = 'b1a00000-0000-4000-8000-0000000000f1';
  inspection(past, C1, DEMO.workshop, 'REG-F-06', 'Fire equipment register, Workshop block', 'submitted', iso(32, 10), iso(32, 12));
  const report = (rid: string, iid: string, title: string, element: string, at: string) =>
    add('report', {
      id: rid, inspection_id: iid, status: 'issued', version: 1, source: 'template',
      content: {
        label: 'Assistive draft. Competent person sign off required.',
        footer: 'This report is powered by Care Net Consultants Development House (Pty) Ltd',
        title: `${title} (fictitious)`,
        executive_summary: '6 checklist items recorded across 1 area: 6 Pass, 0 Fail, 0 Observe, 0 N/A.',
        findings: [], claims: [], uncited: [], voice_notes: { total: 0, accounted: 0, missing: 0 }, corrective_actions: [], risk_register: [],
      },
      charged_cents: null, signed_by: DEMO.name, signed_at: at, issued_at: at, file_link_status: 'linked', section_f_element_code: element, reviewer_requested_at: null,
    });
  report('b1a00000-0000-4000-8000-0000000000f2', past, 'Fire equipment register, Workshop block', 'HSF-F-06', iso(31, 15));

  // 2. Mining: machine guarding at the crushing plant, in progress -------------------------------------------------
  const F14 = tpl('REG-F-14');
  const i2 = id(2301);
  inspection(i2, C2, id(2104), 'REG-F-14', 'Machine guarding, Crushing and screening plant', 'in_progress', iso(0, 8, 10), null);
  area(id(2311), i2, id(2105), 'Primary crusher', 1);
  area(id(2312), i2, id(2106), 'Conveyor 2 tail pulley', 2);
  finding(id(2321), i2, id(2311), F14.item(1), 'pass', 'Crusher and feeder are on the machine register.', null, iso(0, 8, 15));
  finding(id(2322), i2, id(2312), F14.item(4), 'fail', 'Tail pulley guard left off after belt cleaning; no lockout tag on the isolator.', 'critical', iso(0, 8, 25), id(2201));
  finding(id(2323), i2, id(2312), F14.item(6), 'observe', 'Pull wire along conveyor 2 is slack near the tail end.', 'medium', iso(0, 8, 27), id(2201));
  photo({ pid: id(2331), cid: C2, insp: i2, area: id(2312), place: id(2106), finding: id(2322), item: F14.item(4), kind: 'risk_close_up', key: 'demo:conveyor', caption: 'Conveyor 2 tail pulley without its guard (fictitious)', at: iso(0, 8, 26), lat: -25.7, lng: 27.6, tags: ['fail', 'HSF-F-14', 'guarding'], retention: F14.t.retention.class });
  add('voice_note', {
    id: id(2341), inspection_id: i2, area_id: id(2312), finding_id: id(2322), vn_number: 1,
    audio_path: `${C2}/${casKey('f'.repeat(64))}`, audio_sha256: 'f'.repeat(64), size_bytes: 36000, mime_type: 'audio/mp4', duration_seconds: 16,
    captured_at: iso(0, 8, 26), gps_lat: -25.7, gps_lng: 27.6, inspector_user_id: DEMO.inspector, _seal_local: 'demonstration', _local_uri: 'demo:no-audio',
    ...meta(C2, i2, id(2106), F14.item(4), id(2341), F14.item(4), ['voice note', 'guarding'], F14.t.retention.class),
  });
  add('transcript', { id: id(2342), voice_note_id: id(2341), version: 1, source: 'machine', body: 'Conveyor two tail pulley guard is lying on the walkway after belt cleaning. Isolator not locked out. Pinch point exposed at knee height.', created_by: null });
  add('risk', { id: id(2351), inspection_id: i2, area_id: id(2312), finding_id: id(2322), hazard: 'Drawing in at the exposed tail pulley nip point', consequence: 'Crush or amputation injury to a person cleaning or walking past', inherent_likelihood: 4, inherent_severity: 5, controls: [{ level: 'engineering', description: 'Refit the fixed guard and interlock it' }, { level: 'administrative', description: 'Lockout before any belt cleaning' }], residual_likelihood: 1, residual_severity: 5 });
  add('action', { id: id(2361), inspection_id: i2, finding_id: id(2322), risk_id: id(2351), description: 'Refit the tail pulley guard before the conveyor runs again; brief the cleaning crew on lockout.', owner_name: 'Plant engineer (fictitious)', due_on: today, status: 'open' });

  // 3. Healthcare: the laboratory walkthrough, in progress -------------------------------------------------------------
  const IH = tpl('IND-HEALTH');
  const i3 = id(3301);
  inspection(i3, C3, id(3106), 'IND-HEALTH', 'Healthcare and laboratories walkthrough, Pathology laboratory', 'in_progress', iso(2, 10), null);
  area(id(3311), i3, id(3107), 'Specimen reception', 1);
  finding(id(3321), i3, id(3311), IH.item(1), 'observe', 'Sharps container is two thirds full; collection is booked for Friday.', 'low', iso(2, 10, 5));
  finding(id(3322), i3, id(3311), IH.item(6), 'pass', 'Biosafety cabinet certificate on the door is current.', null, iso(2, 10, 8));
  finding(id(3323), i3, id(3311), IH.item(11), 'fail', 'Spill kit hook at specimen reception is empty; the kit was used and not replaced.', 'medium', iso(2, 10, 12));
  photo({ pid: id(3331), cid: C3, insp: i3, area: id(3311), place: id(3107), finding: id(3323), item: IH.item(11), kind: 'risk_close_up', key: 'demo:lab', caption: 'Empty spill kit hook, specimen reception (fictitious)', at: iso(2, 10, 12), lat: -32.35, lng: 22.58, tags: ['fail', 'spill response'], retention: IH.t.retention.class });
  add('risk', { id: id(3351), inspection_id: i3, area_id: id(3311), finding_id: id(3323), hazard: 'A specimen spill with no spill kit at hand', consequence: 'Exposure of reception staff to a biological agent', inherent_likelihood: 3, inherent_severity: 3, controls: [{ level: 'administrative', description: 'Replace the kit and add it to the weekly checklist' }], residual_likelihood: 1, residual_severity: 3 });
  add('action', { id: id(3361), inspection_id: i3, finding_id: id(3323), risk_id: id(3351), description: 'Replace the spill kit at specimen reception and add it to the weekly checklist.', owner_name: 'Laboratory manager (fictitious)', due_on: addDaysIso(today, 1), status: 'open' });

  // 4. Retail and wholesale: stacking and storage at the distribution centre, in progress ---------------------------
  const F16 = tpl('REG-F-16');
  const i4 = id(4301);
  inspection(i4, C4, id(4104), 'REG-F-16', 'Stacking and storage inspection, Distribution centre', 'in_progress', iso(3, 7, 30), null);
  area(id(4311), i4, id(4106), 'High bay racking', 1);
  area(id(4312), i4, id(4105), 'Loading dock', 2);
  finding(id(4321), i4, id(4311), F16.item(1), 'pass', 'Monthly checklist signed for last month.', null, iso(3, 7, 40));
  finding(id(4322), i4, id(4311), F16.item(4), 'fail', 'Upright of bay 7 bent at the base by a forklift; not on the damage register.', 'high', iso(3, 7, 45), id(4201));
  finding(id(4323), i4, id(4311), F16.item(5), 'observe', 'Load sign faded on bay 9.', 'low', iso(3, 7, 50));
  photo({ pid: id(4331), cid: C4, insp: i4, area: id(4311), place: id(4106), finding: id(4322), item: F16.item(4), kind: 'risk_close_up', key: 'demo:racking', caption: 'Bent upright, high bay 7 (fictitious)', at: iso(3, 7, 46), lat: -29.6, lng: 30.38, tags: ['fail', 'HSF-F-16', 'racking'], retention: F16.t.retention.class });
  add('risk', { id: id(4351), inspection_id: i4, area_id: id(4311), finding_id: id(4322), hazard: 'Racking collapse after upright damage', consequence: 'Crush injury to pickers and forklift drivers', inherent_likelihood: 3, inherent_severity: 4, controls: [{ level: 'engineering', description: 'Unload the bay and replace the upright' }, { level: 'administrative', description: 'Report all racking strikes the same shift' }], residual_likelihood: 1, residual_severity: 4 });
  add('risk', { id: id(4352), inspection_id: i4, area_id: id(4311), finding_id: id(4323), hazard: 'Overloading a bay whose load sign cannot be read', consequence: 'Beam deflection', inherent_likelihood: 2, inherent_severity: 2, controls: [{ level: 'administrative', description: 'Replace the load sign' }], residual_likelihood: 1, residual_severity: 2 });
  add('action', { id: id(4361), inspection_id: i4, finding_id: id(4322), risk_id: id(4351), description: 'Offload bay 7, fit a new upright and record the strike on the damage register.', owner_name: 'Warehouse supervisor (fictitious)', due_on: addDaysIso(today, 3), status: 'open' });
  // An earlier fire equipment register inspection at the store, Issued into Section F.
  const i4b = id(4302);
  inspection(i4b, C4, id(4101), 'REG-F-06', 'Fire equipment register, Cash and carry store', 'submitted', iso(20, 11), iso(20, 13));
  report(id(4303), i4b, 'Fire equipment register, Cash and carry store', 'HSF-F-06', iso(19, 9));

  // 5. Agriculture: the chemical register at the farm store, in progress ----------------------------------------------------
  const F12 = tpl('REG-F-12');
  const i5 = id(5301);
  inspection(i5, C5, id(5101), 'REG-F-12', 'Hazardous chemical register, Citrus and timber estate', 'in_progress', iso(4, 9), null);
  area(id(5311), i5, id(5102), 'Farm chemical store', 1);
  finding(id(5321), i5, id(5311), F12.item(2), 'pass', 'Safety data sheets for all spray products are in the red file at the door.', null, iso(4, 9, 10));
  finding(id(5322), i5, id(5311), F12.item(5), 'fail', 'Two decanted sprays on the second shelf are unlabelled and not on the register.', 'medium', iso(4, 9, 20));
  photo({ pid: id(5331), cid: C5, insp: i5, area: id(5311), place: id(5102), finding: id(5322), item: F12.item(5), kind: 'risk_close_up', key: 'demo:chemicals', caption: 'Unlabelled sprays, farm chemical store (fictitious)', at: iso(4, 9, 21), lat: -30.28, lng: 29.93, tags: ['fail', 'HSF-F-12', 'chemicals'], retention: F12.t.retention.class });
  add('risk', { id: id(5351), inspection_id: i5, area_id: id(5311), finding_id: id(5322), hazard: 'Skin or breathing exposure to an unknown pesticide', consequence: 'Poisoning of a sprayer or a store hand', inherent_likelihood: 3, inherent_severity: 3, controls: [{ level: 'elimination', description: 'Dispose of unlabelled product through the chemical supplier' }, { level: 'administrative', description: 'Never decant into unmarked containers' }], residual_likelihood: 1, residual_severity: 3 });

  // Blobs (local content addressed store) ----------------------------------------------------------------------------
  for (const b of blobs.values()) add('blob', b);

  // Wallets: R150,00 included on the base line (Rietvlei), R100,00 on each extra company line (prompt B8).
  add('wallet', { id: DEMO.wallet, client_account_id: C1, status: 'active', monthly_spend_cap_cents: null, auto_topup_enabled: false });
  const first = new Date(now.getFullYear(), now.getMonth(), 1);
  const incExpiry = new Date(now.getFullYear(), now.getMonth() + 2, 1).toISOString();
  add('ledger', { id: 'demo-ledger-1', wallet_id: DEMO.wallet, entry_kind: 'included_credit', amount_cents: 15000, lot_id: null, expires_at: incExpiry, note: 'Included with the base plan this month', created_at: first.toISOString() });
  add('ledger', { id: 'demo-ledger-2', wallet_id: DEMO.wallet, entry_kind: 'charge', amount_cents: -1180, lot_id: 'demo-ledger-1', expires_at: null, note: 'AI draft, fire equipment inspection (demonstration)', created_at: iso(31, 14) });
  add('ledger', { id: 'demo-ledger-3', wallet_id: DEMO.wallet, entry_kind: 'topup_credit', amount_cents: 26000, lot_id: null, expires_at: new Date(now.getFullYear() + 1, now.getMonth(), now.getDate()).toISOString(), note: 'Top up R249,00 (R260,00 value)', created_at: iso(12, 11) });
  add('subsidy', { id: 'demo-subsidy-1', wallet_id: DEMO.wallet, shortfall_cents: 1988, estimate_cents: 5994, actual_cents: 5994, what: 'an AI draft on a ladder inspection (demonstration)', created_at: iso(15, 16) });
  for (const [n, cid] of [[2, C2], [3, C3], [4, C4], [5, C5]] as const) {
    const wid = id(n * 1000 + 801);
    add('wallet', { id: wid, client_account_id: cid, status: 'active', monthly_spend_cap_cents: null, auto_topup_enabled: false });
    add('ledger', { id: `demo-ledger-${n}-1`, wallet_id: wid, entry_kind: 'included_credit', amount_cents: 10000, lot_id: null, expires_at: incExpiry, note: 'Included with the extra company line this month', created_at: first.toISOString() });
  }

  return rows;
}
