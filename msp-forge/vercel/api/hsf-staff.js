// CNC HSF FORGE | HSF-WEB-01 v1.0.0 | Staff console for the Health and Safety File
// Contract 11.5 (and 11.4 for the signatory expiry alerts). Care Net staff verify
// client companies, give a stuck security scan a fresh start, keep the signatory
// credential records, record sign off decisions and see whether a File revision
// may be released. Every call verifies the caller's Supabase Auth token
// (requireUser), then asks hsf_user_is_staff; anyone else gets 403 before any
// console function runs. Each console function checks staff again in its body and
// records the staff member's email as verified_by, revoked_by, created_by,
// recorded_by or the audit actor, so this endpoint never names the actor itself.
//
//   GET  /api/hsf-staff?view=verification        -> hsf_staff_verification_list
//   GET  /api/hsf-staff?view=scans               -> hsf_staff_scan_list {scans, staging_alerts}
//   GET  /api/hsf-staff?view=signatories         -> hsf_staff_signatory_list
//   GET  /api/hsf-staff?view=signatory_alerts    -> hsf_staff_signatory_alerts
//   GET  /api/hsf-staff?view=files               -> hsf_staff_file_list
//   GET  /api/hsf-staff?view=readiness&file_id=<uuid>[&revision=<n>]
//                                                -> hsf_release_readiness (writes nothing)
//   POST /api/hsf-staff { action: 'verify_client', client_account_id, method, evidence_ref }
//                                                -> hsf_staff_verify_client
//   POST /api/hsf-staff { action: 'revoke_client', client_account_id, reason }
//                                                -> hsf_staff_revoke_client
//   POST /api/hsf-staff { action: 'scan_reset', upload_id }
//                                                -> hsf_staff_scan_reset
//   POST /api/hsf-staff { action: 'signatory_save', signatory: { id?, full_name, ... } }
//                                                -> hsf_staff_signatory_save
//   POST /api/hsf-staff { action: 'signoff_record', signoff: { file_id, revision?, kind, ... } }
//                                                -> hsf_staff_signoff_record
//
// The shape of each request is checked here (identifiers, known fields, text
// without control characters, lengths); the rules themselves (a method the
// database knows, pairs given together, the 053 freeze, the OMP never signing
// a File) are the database's, and its refusals reach the page in its own words.
//
// Environment (never in files): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

const { rpc } = require('../lib/db');
const {
  requireUser, sendError, readBody, queryValue, httpError, methodNotAllowed, classifyDbError,
  UUID_RE, CONTROL_RE, ID_NUMBER_RE,
} = require('../lib/auth');

const VIEWS = {
  verification: 'hsf_staff_verification_list',
  scans: 'hsf_staff_scan_list',
  signatories: 'hsf_staff_signatory_list',
  signatory_alerts: 'hsf_staff_signatory_alerts',
  files: 'hsf_staff_file_list',
};
const METHODS = ['mco_company_ref', 'client_register', 'sales_executive'];
const NOT_STAFF = 'This console is for Care Net staff. If you are a client, your File is in the File builder.';

// The fields hsf_staff_signatory_save reads (053 hsf_signatory), with the
// longest value each may carry. Dates are YYYY-MM-DD.
const SIGNATORY_TEXT = {
  full_name: 200,
  registration_body: 20,
  category: 40,
  registration_number: 100,
  register_proof_ref: 200,
  appointment_letter_ref: 200,
  appointment_letter_recruitment_portal_ref: 200,
  engagement_letter_ref: 200,
  engagement_letter_recruitment_portal_ref: 200,
};
const SIGNATORY_DATES = ['registration_expires_on', 'register_checked_on', 'appointment_letter_date', 'engagement_letter_date'];
// The fields hsf_staff_signoff_record reads.
const SIGNOFF_TEXT = { kind: 40, decision: 20, scope: 500, signatory_name: 200, document_ref: 200 };
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
// An ISO 8601 date and time with an offset or Z, as the console sends it.
const DATETIME_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}:\d{2})$/;

function optional(v) {
  return v === undefined || v === null || v === '';
}

function parseUuid(v, label) {
  if (typeof v !== 'string' || !UUID_RE.test(v)) throw httpError(400, `${label} is missing or not a valid identifier.`, 'bad_request');
  return v.toLowerCase();
}

// Free text: new lines and runs of spaces collapse to one space; control
// characters and anything resembling an identity number are refused (the
// console records registration numbers, never identity numbers).
function text(v, label, max) {
  if (typeof v !== 'string') throw httpError(400, `${label} must be text.`, 'bad_request');
  const s = v.replace(/[\r\n\t]+/g, ' ').replace(/ {2,}/g, ' ').trim();
  if (s.length > max) throw httpError(400, `${label} must be at most ${max} characters.`, 'bad_request');
  if (CONTROL_RE.test(s)) throw httpError(400, `${label} contains characters that are not allowed.`, 'bad_request');
  if (ID_NUMBER_RE.test(s)) {
    throw httpError(400, `${label} appears to contain an identity number. Please remove it; the console never holds identity numbers.`, 'bad_request');
  }
  return s;
}

function object(v, label) {
  if (!v || typeof v !== 'object' || Array.isArray(v)) throw httpError(400, `${label} are missing.`, 'bad_request');
  return v;
}

function parseVerify(b) {
  const id = parseUuid(b.client_account_id, 'The company account');
  if (typeof b.method !== 'string' || !METHODS.includes(b.method)) {
    throw httpError(400, 'Choose how the company was verified: MyClinicOnline company reference, client register or sales executive.', 'bad_request');
  }
  const ref = text(optional(b.evidence_ref) ? '' : b.evidence_ref, 'The evidence reference', 200);
  if (!ref) {
    throw httpError(400, 'Record what the verification rests on (for example the MyClinicOnline company reference or the client register number).', 'bad_request');
  }
  return { p_client_account_id: id, p_method: b.method, p_evidence_ref: ref };
}

function parseRevoke(b) {
  const id = parseUuid(b.client_account_id, 'The company account');
  const reason = text(optional(b.reason) ? '' : b.reason, 'The reason', 500);
  if (!reason) throw httpError(400, 'Give the reason for the revocation.', 'bad_request');
  return { p_client_account_id: id, p_reason: reason };
}

// Only the known fields go to the database; an empty value is sent as null so
// the database decides whether it may be left out.
function parseSignatory(b) {
  const s = object(b.signatory, 'The signatory details');
  const p = {};
  if (!optional(s.id)) p.id = parseUuid(s.id, 'The signatory');
  for (const [k, max] of Object.entries(SIGNATORY_TEXT)) {
    p[k] = optional(s[k]) ? null : (text(s[k], `The field ${k.replace(/_/g, ' ')}`, max) || null);
  }
  for (const k of SIGNATORY_DATES) {
    if (optional(s[k])) { p[k] = null; continue; }
    if (typeof s[k] !== 'string' || !DATE_RE.test(s[k].trim())) {
      throw httpError(400, `The field ${k.replace(/_/g, ' ')} must be a date written as YYYY-MM-DD.`, 'bad_request');
    }
    p[k] = s[k].trim();
  }
  return p;
}

function parseSignoff(b) {
  const s = object(b.signoff, 'The sign off details');
  const p = { file_id: parseUuid(s.file_id, 'The File') };
  if (!optional(s.revision)) {
    const n = typeof s.revision === 'string' && /^\d{1,6}$/.test(s.revision.trim()) ? Number(s.revision.trim()) : s.revision;
    if (!Number.isSafeInteger(n) || n < 1 || n > 999999) throw httpError(400, 'The revision must be a whole number from 1.', 'bad_request');
    p.revision = n;
  }
  for (const [k, max] of Object.entries(SIGNOFF_TEXT)) {
    if (!optional(s[k])) p[k] = text(s[k], `The field ${k.replace(/_/g, ' ')}`, max) || null;
  }
  if (!optional(s.signatory_id)) p.signatory_id = parseUuid(s.signatory_id, 'The signatory');
  if (optional(s.decided_at)) throw httpError(400, 'The date of the decision is required.', 'bad_request');
  if (typeof s.decided_at !== 'string' || !DATETIME_RE.test(s.decided_at.trim())) {
    throw httpError(400, 'The date of the decision must be a date and time.', 'bad_request');
  }
  p.decided_at = s.decided_at.trim();
  return p;
}

// A database 'not found' (P0002) becomes a 404 with a message naming the record.
async function orNotFound(promise, message) {
  try {
    return await promise;
  } catch (err) {
    const db = classifyDbError(err);
    if (db && db.status === 404) throw httpError(404, message, 'not_found');
    throw err;
  }
}

async function requireStaff(user) {
  const staff = await rpc('hsf_user_is_staff', { p_auth_user: user.id });
  if (staff !== true) throw httpError(403, NOT_STAFF, 'forbidden');
}

async function read(req, user) {
  const view = queryValue(req, 'view');
  if (view === 'readiness') {
    const fileId = parseUuid(queryValue(req, 'file_id'), 'The File');
    const rev = queryValue(req, 'revision');
    let revision = null;
    if (!optional(rev)) {
      if (!/^\d{1,6}$/.test(rev) || Number(rev) < 1) throw httpError(400, 'The revision must be a whole number from 1.', 'bad_request');
      revision = Number(rev);
    }
    return orNotFound(rpc('hsf_release_readiness', { p_file_id: fileId, p_revision: revision }), 'That File was not found.');
  }
  const fn = VIEWS[view];
  if (!fn) throw httpError(400, 'Unknown view. Use verification, scans, signatories, signatory_alerts, files or readiness.', 'bad_request');
  const out = await rpc(fn, { p_auth_user: user.id });
  if (view === 'scans') {
    const o = out && typeof out === 'object' && !Array.isArray(out) ? out : {};
    return {
      scans: Array.isArray(o.scans) ? o.scans : [],
      staging_alerts: Array.isArray(o.staging_alerts) ? o.staging_alerts : [],
    };
  }
  return Array.isArray(out) ? out : [];
}

async function write(b, user) {
  if (b.action === 'verify_client') {
    return orNotFound(rpc('hsf_staff_verify_client', { p_auth_user: user.id, ...parseVerify(b) }), 'That company account was not found.');
  }
  if (b.action === 'revoke_client') {
    return orNotFound(rpc('hsf_staff_revoke_client', { p_auth_user: user.id, ...parseRevoke(b) }), 'That company account was not found.');
  }
  if (b.action === 'scan_reset') {
    const id = parseUuid(b.upload_id, 'The upload');
    return orNotFound(rpc('hsf_staff_scan_reset', { p_auth_user: user.id, p_upload_id: id }), 'That upload was not found.');
  }
  if (b.action === 'signatory_save') {
    return orNotFound(rpc('hsf_staff_signatory_save', { p_auth_user: user.id, p: parseSignatory(b) }), 'That signatory was not found.');
  }
  if (b.action === 'signoff_record') {
    return orNotFound(rpc('hsf_staff_signoff_record', { p_auth_user: user.id, p: parseSignoff(b) }), 'That File or signatory was not found.');
  }
  throw httpError(400, "Unknown action. Use 'verify_client', 'revoke_client', 'scan_reset', 'signatory_save' or 'signoff_record'.", 'bad_request');
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET' && req.method !== 'POST') {
    methodNotAllowed(res, ['GET', 'POST']);
    return;
  }
  try {
    const user = await requireUser(req);
    await requireStaff(user);
    if (req.method === 'GET') {
      res.status(200).json(await read(req, user));
      return;
    }
    const out = await write(readBody(req), user);
    res.status(200).json(out === null || out === undefined ? {} : out);
  } catch (err) {
    sendError(res, err, 'hsf staff');
  }
};
