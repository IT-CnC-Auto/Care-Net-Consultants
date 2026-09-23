// CNC HSF FORGE | HSF-WEB-01 v1.0.0 | Health and Safety File: list, detail, generate, item status
//
//   GET  /api/hsf-file                         -> hsf_my_files
//   GET  /api/hsf-file?file_id=<uuid>          -> hsf_file_detail (owning account or staff only)
//   POST /api/hsf-file { action: 'generate', industry_code, subindustry_code?,
//                        triggers: [...], scope: { sites: [{ name, address? }],
//                        project_reference?, headcount? } }
//                                              -> hsf_generate_file
//   POST /api/hsf-file { action: 'set_status', item_id, status, reason }
//                                              -> hsf_set_item_status
//
// Generating the skeleton holds no documents, so it needs no upload consent;
// uploads do (see hsf-upload.js). The engine assembles, evidences and flags;
// the named people decide and sign. Every call verifies the caller's Supabase
// Auth token and passes only the verified user id to the service role functions,
// which scope every read and write to that user's company account.

const { rpc } = require('../lib/db');
const {
  requireUser, sendError, readBody, queryValue, httpError, methodNotAllowed,
  UUID_RE, CONTROL_RE, ID_NUMBER_RE,
} = require('../lib/auth');

const INDUSTRY_RE = /^[A-Z][A-Z0-9_]{1,31}$/;
const SUBINDUSTRY_RE = /^[A-Z][A-Z0-9_]{0,31}(?:-[A-Z0-9_]{1,31}){0,4}$/;
// 'U' (universal) or a B9.2 trigger code such as T-CONSTR or T-CONSTR-NOTIFY.
const TRIGGER_RE = /^(?:U|T(?:-[A-Z0-9]{1,16}){1,4})$/;
const ITEM_STATUSES = ['not_applicable', 'outstanding'];
const MAX_TRIGGERS = 64;
const MAX_SITES = 100;
const MIN_REASON = 10;
const MAX_REASON = 1000;
const MAX_HEADCOUNT = 1000000;

function optional(v) {
  return v === undefined || v === null || v === '';
}

function parseUuid(v, label) {
  if (typeof v !== 'string' || !UUID_RE.test(v)) throw httpError(400, `${label} is missing or not a valid identifier.`, 'bad_request');
  return v.toLowerCase();
}

// Free text: new lines and runs of spaces collapse to one space; control
// characters and anything resembling an identity number are refused.
function text(v, label, min, max) {
  if (typeof v !== 'string') throw httpError(400, `${label} must be text.`, 'bad_request');
  const s = v.replace(/[\r\n\t]+/g, ' ').replace(/ {2,}/g, ' ').trim();
  if (s.length < min || s.length > max) {
    throw httpError(400, `${label} must be between ${min} and ${max} characters.`, 'bad_request');
  }
  if (CONTROL_RE.test(s)) throw httpError(400, `${label} contains characters that are not allowed.`, 'bad_request');
  if (ID_NUMBER_RE.test(s)) {
    throw httpError(400, `${label} appears to contain an identity number. Please remove it; the File never holds personal identifiers here.`, 'bad_request');
  }
  return s;
}

function parseGenerate(b) {
  const industry = typeof b.industry_code === 'string' ? b.industry_code.trim().toUpperCase() : '';
  if (!INDUSTRY_RE.test(industry)) throw httpError(400, 'Choose your industry.', 'bad_request');
  const p = { industry_code: industry };

  if (!optional(b.subindustry_code)) {
    const sub = typeof b.subindustry_code === 'string' ? b.subindustry_code.trim().toUpperCase() : '';
    if (sub.length > 64 || !SUBINDUSTRY_RE.test(sub)) throw httpError(400, 'The subindustry is not recognised.', 'bad_request');
    p.subindustry_code = sub;
  }

  const rawTriggers = optional(b.triggers) ? [] : b.triggers;
  if (!Array.isArray(rawTriggers) || rawTriggers.length > MAX_TRIGGERS) {
    throw httpError(400, `Activities must be a list of at most ${MAX_TRIGGERS} codes.`, 'bad_request');
  }
  const triggers = [];
  for (const t of rawTriggers) {
    if (typeof t !== 'string' || !TRIGGER_RE.test(t)) throw httpError(400, 'An activity code is not recognised.', 'bad_request');
    if (!triggers.includes(t)) triggers.push(t);
  }
  p.triggers = triggers;

  const s = b.scope;
  if (!s || typeof s !== 'object' || Array.isArray(s)) throw httpError(400, 'Tell us which sites the File covers.', 'bad_request');
  if (!Array.isArray(s.sites) || s.sites.length < 1 || s.sites.length > MAX_SITES) {
    throw httpError(400, `List between 1 and ${MAX_SITES} sites.`, 'bad_request');
  }
  const scope = { sites: [] };
  s.sites.forEach((site, i) => {
    if (!site || typeof site !== 'object' || Array.isArray(site)) throw httpError(400, `Site ${i + 1} is not valid.`, 'bad_request');
    const out = { name: text(site.name, `Site ${i + 1} name`, 1, 200) };
    if (!optional(site.address)) out.address = text(site.address, `Site ${i + 1} address`, 1, 500);
    scope.sites.push(out);
  });
  if (!optional(s.project_reference)) scope.project_reference = text(s.project_reference, 'The project reference', 1, 100);
  if (!optional(s.headcount)) {
    const n = typeof s.headcount === 'string' && /^\d{1,7}$/.test(s.headcount.trim()) ? Number(s.headcount.trim()) : s.headcount;
    if (!Number.isSafeInteger(n) || n < 0 || n > MAX_HEADCOUNT) {
      throw httpError(400, 'The headcount must be a whole number.', 'bad_request');
    }
    scope.headcount = n;
  }
  p.scope = scope;
  return p;
}

function parseSetStatus(b) {
  const itemId = parseUuid(b.item_id, 'The File item');
  if (typeof b.status !== 'string' || !ITEM_STATUSES.includes(b.status)) {
    throw httpError(400, "The status must be 'not_applicable' or 'outstanding'.", 'bad_request');
  }
  let reason = null;
  if (b.status === 'not_applicable') {
    reason = text(optional(b.reason) ? '' : b.reason, 'The reason', MIN_REASON, MAX_REASON);
  } else if (!optional(b.reason)) {
    reason = text(b.reason, 'The reason', 1, MAX_REASON);
  }
  return { p_item_id: itemId, p_status: b.status, p_reason: reason };
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET' && req.method !== 'POST') {
    methodNotAllowed(res, ['GET', 'POST']);
    return;
  }
  try {
    const user = await requireUser(req);

    if (req.method === 'GET') {
      const fileId = queryValue(req, 'file_id');
      if (optional(fileId)) {
        const files = await rpc('hsf_my_files', { p_auth_user: user.id });
        res.status(200).json(Array.isArray(files) ? files : []);
        return;
      }
      const detail = await rpc('hsf_file_detail', { p_auth_user: user.id, p_file_id: parseUuid(fileId, 'The File') });
      if (!detail) throw httpError(404, 'That File was not found.', 'not_found');
      res.status(200).json(detail);
      return;
    }

    const b = readBody(req);
    if (b.action === 'generate') {
      const out = await rpc('hsf_generate_file', { p_auth_user: user.id, p: parseGenerate(b) });
      res.status(200).json(out);
      return;
    }
    if (b.action === 'set_status') {
      const args = parseSetStatus(b);
      const out = await rpc('hsf_set_item_status', { p_auth_user: user.id, ...args });
      res.status(200).json(out === null || out === undefined ? { item_id: args.p_item_id, status: args.p_status } : out);
      return;
    }
    throw httpError(400, "Unknown action. Use 'generate' or 'set_status'.", 'bad_request');
  } catch (err) {
    sendError(res, err, 'hsf file');
  }
};
