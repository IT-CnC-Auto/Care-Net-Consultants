// Records the phone keeps offline. Field names follow the bi_ tables of
// migrations 059 to 063 (snake case), so a record is pushed as it is stored.
// Fields starting with an underscore are local only and never leave the phone.

import type { Control } from './risk';

export type Id = string;

export type CompanyStatus = 'not_started' | 'in_review' | 'active' | 'blocked';
export type InspectorStatus = 'identity' | 'fica' | 'qualifications' | 'competence_review' | 'cleared' | 'restricted' | 'assistant_only';
export type FindingResult = 'pass' | 'fail' | 'na' | 'observe';
export type VoicePolicy = 'recommended' | 'strict';
export type ReportStatus = 'draft' | 'awaiting_signoff' | 'issued' | 'withdrawn';
/** Section F filing after Issue (contract 16.7 and 16.8). */
export type FileLinkStatus = 'linked' | 'section_only' | 'no_file' | 'awaiting_eligibility' | null;
export type FileEligibility = 'eligible' | 'not_eligible' | 'unknown';

export interface BaseRecord {
  id: Id;
  row_version?: number;
  created_at?: string;
  updated_at?: string;
}

export interface Company extends BaseRecord {
  legal_name: string;
  trading_name: string | null;
  registration_number: string | null;
  cipc_status: 'not_checked' | 'in_business' | 'deregistered' | 'in_deregistration' | 'unknown' | null;
  s16_1_contact: string | null;
  s16_2_contact: string | null;
  popia_contact: string | null;
  onboarding_status: CompanyStatus;
  fica_status: 'not_submitted' | 'submitted' | 'accepted' | 'rejected';
  /** Free digital Safety File entitlement (decision 1.1): decides whether an Issued report raises Section F. */
  file_eligibility: FileEligibility;
  file_eligibility_note: string | null;
  /** Kernel industry and subindustry (msp_industry, msp_subindustry codes; migration 065 adds them to bi_company). */
  industry_code: string | null;
  subindustry_code: string | null;
}

export type PersonRole = 's16_1' | 's16_2' | 'she_manager' | 'she_officer' | 'she_rep' | 'first_aider' | 'fire_marshal' | 'construction_manager' | 'inspector' | 'assistant' | 'other';

export interface AuthorisedPerson extends BaseRecord {
  client_account_id: Id;
  full_name: string;
  roles: PersonRole[];
  email: string | null;
  mobile: string | null;
  appointed_on: string | null;
}

export interface Registration extends BaseRecord {
  body: string;
  number: string;
  category: string | null;
  expires_on: string | null;
}

export interface Qualification extends BaseRecord {
  qual_type: string;
  issuer: string;
  number: string;
  issued_on: string | null;
  expires_on: string | null;
  status: 'pending' | 'verified' | 'rejected' | 'expired';
  document_name: string | null;
  _local_uri?: string | null;
}

export type ConsentKind = 'terms' | 'privacy' | 'location' | 'voice_recording' | 'identifiable_people' | 'fica_processing' | 'marketing';

export interface Consent extends BaseRecord {
  consent_kind: ConsentKind;
  granted: boolean;
  wording_version: string;
  granted_at: string | null;
  /** Marketing is double opt in: granted stays pending until confirmed. */
  confirmed_at: string | null;
  withdrawn_at: string | null;
}

export interface InspectorProfile extends BaseRecord {
  display_name: string;
  status: InspectorStatus;
  competence_scope: string[];
  restricted_reason: string | null;
  identity_done: boolean;
  fica_done: boolean;
}

/**
 * A place of inspection: one typed node of the company's places tree (bi_place,
 * migration 065). The type comes from the kernel bundle's place types; a root
 * place is also the company's site (the server keeps a bi_site with the same id).
 */
export interface Place extends BaseRecord {
  client_account_id: Id;
  parent_id: Id | null;
  place_type: string;
  /** The person's own name for the type (for example "Pump station"), shown instead of the kernel label. */
  custom_type_label: string | null;
  name: string;
  address: string | null;
  gps_lat: number | null;
  gps_lng: number | null;
  responsible_person: string | null;
  /** A whole number, as the File's generator takes it; no bands are invented. */
  headcount: number | null;
  /** File department code (hsf_department) for a department place. */
  department_code: string | null;
  /** Departments this place serves (ids of department places), for places shared between departments. */
  linked_department_ids: Id[];
  archived_at: string | null;
}

export interface Site extends BaseRecord {
  client_account_id: Id;
  name: string;
  address: string | null;
}
export interface Department extends BaseRecord {
  site_id: Id;
  department_code: string | null;
  name: string;
}
export interface Building extends BaseRecord {
  site_id: Id;
  department_id: Id;
  name: string;
  kind: 'building' | 'zone';
}
export interface Room extends BaseRecord {
  site_id: Id;
  building_id: Id;
  name: string;
  kind: 'room' | 'area';
}

export interface Template extends BaseRecord {
  code: string;
  name: string;
  category: string;
  section_f_element_code: string | null;
  description: string | null;
  /** Kernel templates: 'register' (a Section F register) or 'industry' (an industry walkthrough). */
  template_kind?: 'register' | 'industry' | 'tenant';
  industry_code?: string | null;
  kernel_version?: string | null;
}
export interface TemplateItem extends BaseRecord {
  template_id: Id;
  ordinal: number;
  section_label: string | null;
  prompt: string;
  kernel_ref: string | null;
  /** Where the line came from in the kernel (for example guidance:HSF-F-02#common_gaps[1]). */
  source_ref?: string | null;
}

export interface Inspection extends BaseRecord {
  tenant_id: Id;
  client_account_id: Id;
  site_id: Id;
  template_id: Id;
  inspector_user_id: Id;
  title: string;
  status: 'planned' | 'in_progress' | 'submitted' | 'closed' | 'cancelled';
  voice_note_policy: VoicePolicy;
  started_at: string | null;
  submitted_at: string | null;
  device_id: string | null;
  /** The exact place inspected (any node of the places tree); site_id is its root. */
  place_id: Id | null;
}

export interface Area extends BaseRecord {
  inspection_id: Id;
  room_id: Id | null;
  /** The place walked as this area (a child of the inspected place), or null for an ad hoc area. */
  place_id: Id | null;
  label: string;
  ordinal: number;
}

export interface Finding extends BaseRecord {
  inspection_id: Id;
  area_id: Id;
  template_item_id: Id | null;
  equipment_id: Id | null;
  result: FindingResult;
  note: string | null;
  severity: 'low' | 'medium' | 'high' | 'critical' | null;
  captured_by: Id;
  captured_at: string;
  gps_lat: number | null;
  gps_lng: number | null;
}

export interface Annotation {
  x: number;
  y: number;
  label: string;
}

/**
 * Evidence file management fields shared by photos and voice notes
 * (docs/bee-inspect/p4/evidence-storage.md). The bytes are content addressed:
 * the SHA 256 is the identity of the blob, a repeat of the same bytes is stored
 * once. A correction never overwrites: it is a new version (a new record) that
 * points at the one it supersedes and at the first version (the root).
 */
export interface EvidenceMeta {
  evidence_version: number;
  root_evidence_id: Id | null;
  supersedes_id: Id | null;
  /** tenant/company/place path/inspection/item/evidence id: the logical path people browse. */
  canonical_path: string | null;
  place_id: Id | null;
  template_item_id: Id | null;
  device_id: string | null;
  tags: string[];
  /** Retention class of the Section F element the inspection files into (SPEC B6.1.4), or null. */
  retention_class: string | null;
  /** Set only by Care Net or the company admin on the server; the phone respects it. */
  legal_hold: boolean;
  sidecar_sha256: string | null;
  /** Local only: the derived copies on this phone and the upload state. */
  _thumb_uri?: string | null;
  _web_uri?: string | null;
  _upload?: UploadState | null;
}

/** Resumable, chunked upload state of one blob (src/lib/upload-plan.ts). */
export interface UploadState {
  session_id: string | null;
  sha256: string;
  size_bytes: number;
  chunk_bytes: number;
  done: number[];
  verified: boolean;
  verified_sha256: string | null;
  attempts: number;
  last_error: string | null;
}

/** A content addressed blob on this phone (local only; the server keeps bi_evidence_blob). */
export interface BlobRecord extends BaseRecord {
  /** id is the SHA 256 of the bytes. */
  sha256: string;
  client_account_id: Id;
  size_bytes: number;
  mime_type: string;
  local_uri: string;
  /** How many evidence versions point at these bytes. */
  refs: number;
  variant: 'original' | 'thumb' | 'web';
  derived_from: string | null;
  exif_stripped: boolean;
  uploaded: boolean;
  verified_at: string | null;
}

export interface Photo extends BaseRecord, EvidenceMeta {
  inspection_id: Id;
  area_id: Id | null;
  finding_id: Id | null;
  equipment_id: Id | null;
  kind: 'area' | 'equipment' | 'risk_close_up' | 'closure_evidence' | 'other';
  storage_path: string;
  sha256: string;
  size_bytes: number;
  mime_type: string;
  captured_at: string;
  gps_lat: number | null;
  gps_lng: number | null;
  gps_accuracy_m: number | null;
  inspector_user_id: Id;
  caption: string | null;
  annotations: Annotation[];
  identifiable_people: boolean;
  people_consent_ref: string | null;
  /** SHA 256 of the evidence fields, computed the same way as bi_evidence_seal. */
  _seal_local: string;
  _local_uri: string;
}

export interface VoiceNote extends BaseRecord, EvidenceMeta {
  inspection_id: Id;
  area_id: Id | null;
  finding_id: Id | null;
  /** Given by the database on sync (VN-1, VN-2 ...); null until then. */
  vn_number: number | null;
  audio_path: string;
  audio_sha256: string;
  size_bytes: number;
  mime_type: string;
  duration_seconds: number;
  captured_at: string;
  gps_lat: number | null;
  gps_lng: number | null;
  inspector_user_id: Id;
  _seal_local: string;
  _local_uri: string;
}

export interface Transcript extends BaseRecord {
  voice_note_id: Id;
  version: number;
  source: 'machine' | 'correction';
  body: string;
  created_by: Id | null;
}

export interface Risk extends BaseRecord {
  inspection_id: Id;
  area_id: Id | null;
  finding_id: Id | null;
  hazard: string;
  consequence: string | null;
  inherent_likelihood: number;
  inherent_severity: number;
  controls: Control[];
  residual_likelihood: number | null;
  residual_severity: number | null;
}

export interface CorrectiveAction extends BaseRecord {
  inspection_id: Id;
  finding_id: Id | null;
  risk_id: Id | null;
  description: string;
  owner_name: string;
  due_on: string;
  status: 'open' | 'in_progress' | 'closed' | 'overdue' | 'escalated';
}

export interface Equipment extends BaseRecord {
  client_account_id: Id;
  site_id: Id | null;
  tag_code: string;
  kind: string;
  description: string | null;
  serial_number: string | null;
}

export interface ReportClaim {
  text: string;
  kernel_ref: string;
  finding_id?: string;
}

export interface ReportContent {
  label: string;
  footer: string;
  title: string;
  executive_summary: string;
  findings: { finding_id: string; area: string | null; item: string | null; result: string; note: string | null; photos: string[]; voice_notes: string[]; kernel_ref: string | null }[];
  claims: ReportClaim[];
  uncited: string[];
  voice_notes: { total: number; accounted: number; missing: number };
  corrective_actions: { id: string; description: string; owner: string; due_on: string; status: string }[];
  risk_register: { risk_id: string; hazard: string; inherent: { score: number | null }; residual: { score: number | null } | null }[];
}

export interface Report extends BaseRecord {
  inspection_id: Id;
  status: ReportStatus;
  version: number;
  source: 'template' | 'ai_assistive';
  content: ReportContent;
  charged_cents: number | null;
  signed_by: string | null;
  signed_at: string | null;
  issued_at: string | null;
  file_link_status: FileLinkStatus;
  section_f_element_code: string | null;
  reviewer_requested_at: string | null;
}

export interface Wallet extends BaseRecord {
  client_account_id: Id;
  status: 'active' | 'frozen';
  monthly_spend_cap_cents: number | null;
  auto_topup_enabled: boolean;
}

export interface LedgerEntry extends BaseRecord {
  wallet_id: Id;
  entry_kind: 'included_credit' | 'topup_credit' | 'auto_topup_credit' | 'welcome_credit' | 'charge' | 'expiry' | 'refund';
  amount_cents: number;
  lot_id: string | null;
  expires_at: string | null;
  note: string | null;
}

export interface Subsidy extends BaseRecord {
  wallet_id: Id;
  shortfall_cents: number;
  estimate_cents: number;
  actual_cents: number;
  what: string;
}

/** Every kind the local store holds, with its record type. */
export interface KindMap {
  company: Company;
  place: Place;
  blob: BlobRecord;
  person: AuthorisedPerson;
  registration: Registration;
  qualification: Qualification;
  consent: Consent;
  inspector: InspectorProfile;
  site: Site;
  department: Department;
  building: Building;
  room: Room;
  template: Template;
  template_item: TemplateItem;
  inspection: Inspection;
  area: Area;
  finding: Finding;
  photo: Photo;
  voice_note: VoiceNote;
  transcript: Transcript;
  risk: Risk;
  action: CorrectiveAction;
  equipment: Equipment;
  report: Report;
  wallet: Wallet;
  ledger: LedgerEntry;
  subsidy: Subsidy;
}

export type Kind = keyof KindMap;

export const KINDS: readonly Kind[] = [
  'company', 'place', 'blob', 'person', 'registration', 'qualification', 'consent', 'inspector',
  'site', 'department', 'building', 'room', 'template', 'template_item',
  'inspection', 'area', 'finding', 'photo', 'voice_note', 'transcript', 'risk', 'action', 'equipment',
  'report', 'wallet', 'ledger', 'subsidy',
];

/** The bi_ table each synced kind is written to (capture rows go straight to PostgREST under RLS). */
export const TABLE_OF: Partial<Record<Kind, string>> = {
  place: 'bi_place',
  site: 'bi_site',
  department: 'bi_department',
  building: 'bi_building',
  room: 'bi_room',
  inspection: 'bi_inspection',
  area: 'bi_inspection_area',
  finding: 'bi_finding',
  photo: 'bi_photo',
  voice_note: 'bi_voice_note',
  transcript: 'bi_voice_transcript',
  risk: 'bi_risk',
  action: 'bi_corrective_action',
  equipment: 'bi_equipment',
};
