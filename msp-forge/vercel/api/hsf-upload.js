// CNC HSF FORGE | HSF-WEB-01 v1.0.0 | File document uploads into the private staging bucket
// A company drops a document into a section or department of its Health and
// Safety File. The bytes never pass through this function: it registers the
// upload, then asks Supabase Storage for a one off signed upload URL into the
// private hsf-staging bucket, and the browser sends the file straight there.
// The transfer worker later moves the file to MyClinicOnline and removes it
// from staging; the row and its hashes stay for the audit trail.
//
//   POST /api/hsf-upload { action: 'register', department_code, original_name,
//                          mime_type, size_bytes, sha256,
//                          file_id?, section_code?, element_code? }
//        -> hsf_register_upload, then
//           POST {SUPABASE_URL}/storage/v1/object/upload/sign/hsf-staging/<path>
//        <- { upload_id, upload_url }   (browser: PUT upload_url, header Content-Type)
//   POST /api/hsf-upload { action: 'complete', upload_id }
//        -> checks the object is in the bucket at the registered size, then
//           hsf_mark_uploaded
//        <- { upload_id, status }
//   GET  /api/hsf-upload?file_id=<uuid>   -> hsf_my_uploads (file_id optional)
//
// Consent (all three kinds), the allowed types and the size limit are enforced
// by hsf_register_upload from msp_env_parameter, never from constants here.
// The service role key is used only in server to server calls and is never
// returned; the signed URL carries its own short lived token.

const { rpc } = require('../lib/db');
const {
  requireUser, sendError, readBody, queryValue, httpError, methodNotAllowed,
  UUID_RE, SHA256_RE, CONTROL_RE,
} = require('../lib/auth');

const BUCKET = 'hsf-staging';
const DEPARTMENT_RE = /^[A-Z]{2,16}$/;
const SECTION_RE = /^[A-O]$/;
const ELEMENT_RE = /^HSF(?:-[A-Z0-9]{1,16}){1,6}$/;
const MIME_RE = /^[a-z0-9][a-z0-9!#$&^_.+-]{0,63}\/[a-z0-9][a-z0-9!#$&^_.+-]{0,126}$/;
const SEGMENT_RE = /^[A-Za-z0-9._-]{1,160}$/;
const MAX_NAME = 255;

function serviceHeaders(extra) {
  return Object.assign({
    apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
  }, extra || {});
}

function optional(v) {
  return v === undefined || v === null || v === '';
}

function parseUuid(v, label) {
  if (typeof v !== 'string' || !UUID_RE.test(v)) throw httpError(400, `${label} is missing or not a valid identifier.`, 'bad_request');
  return v.toLowerCase();
}

function parseRegister(b) {
  const p = {};

  if (typeof b.department_code !== 'string' || !DEPARTMENT_RE.test(b.department_code)) {
    throw httpError(400, 'Choose the department this document belongs to.', 'bad_request');
  }
  p.department_code = b.department_code;

  if (!optional(b.section_code)) {
    if (typeof b.section_code !== 'string' || !SECTION_RE.test(b.section_code)) {
      throw httpError(400, 'The File section must be a single letter from A to O.', 'bad_request');
    }
    p.section_code = b.section_code;
  }

  if (!optional(b.file_id)) p.file_id = parseUuid(b.file_id, 'The File');

  if (!optional(b.element_code)) {
    if (typeof b.element_code !== 'string' || b.element_code.length > 64 || !ELEMENT_RE.test(b.element_code)) {
      throw httpError(400, 'The File element code is not recognised.', 'bad_request');
    }
    if (!p.file_id) throw httpError(400, 'An element upload must name the File it belongs to.', 'bad_request');
    p.element_code = b.element_code;
  }

  if (typeof b.original_name !== 'string') throw httpError(400, 'The file name is missing.', 'bad_request');
  const name = b.original_name.trim();
  if (!name || name.length > MAX_NAME || CONTROL_RE.test(name)) {
    throw httpError(400, `The file name must be between 1 and ${MAX_NAME} printable characters.`, 'bad_request');
  }
  p.original_name = name;

  if (typeof b.mime_type !== 'string') throw httpError(400, 'The file type is missing.', 'bad_request');
  const mime = b.mime_type.trim().toLowerCase();
  if (!MIME_RE.test(mime)) throw httpError(400, 'The file type is not recognised.', 'bad_request');
  p.mime_type = mime;

  if (typeof b.size_bytes !== 'number' || !Number.isSafeInteger(b.size_bytes) || b.size_bytes <= 0) {
    throw httpError(400, 'The file size must be a whole number of bytes greater than zero.', 'bad_request');
  }
  p.size_bytes = b.size_bytes;

  const sha = typeof b.sha256 === 'string' ? b.sha256.trim().toLowerCase() : '';
  if (!SHA256_RE.test(sha)) throw httpError(400, 'The SHA 256 fingerprint must be 64 hexadecimal characters.', 'bad_request');
  p.sha256 = sha;

  return p;
}

// The staging path is <client_account_id>/<upload_id>/<safe_file_name>, built by
// hsf_register_upload. Check it before it goes into a URL.
function encodedStagingPath(path, uploadId) {
  if (typeof path !== 'string' || path.length > 400) return null;
  const segments = path.split('/');
  if (segments.length < 2) return null;
  for (const s of segments) {
    if (!SEGMENT_RE.test(s) || s === '.' || s === '..') return null;
  }
  if (!segments.includes(uploadId)) return null;
  return segments.map(encodeURIComponent).join('/');
}

async function signUpload(encodedPath) {
  let r;
  try {
    r = await fetch(`${process.env.SUPABASE_URL}/storage/v1/object/upload/sign/${BUCKET}/${encodedPath}`, {
      method: 'POST',
      headers: serviceHeaders({ 'Content-Type': 'application/json' }),
      body: '{}',
    });
  } catch (err) {
    throw httpError(502, 'The upload could not be prepared. Please try again.', 'upstream_error');
  }
  if (!r.ok) {
    console.error('hsf upload sign failure', r.status);
    throw httpError(502, 'The upload could not be prepared. Please try again.', 'upstream_error');
  }
  let data = null;
  try { data = await r.json(); } catch (e) { data = null; }
  const url = data && typeof data.url === 'string' ? data.url : '';
  if (!url.startsWith(`/object/upload/sign/${BUCKET}/`) || !/[?&]token=[^&\s]+/.test(url) || /\s/.test(url)) {
    console.error('hsf upload sign failure', 'unexpected response shape');
    throw httpError(502, 'The upload could not be prepared. Please try again.', 'upstream_error');
  }
  return `${process.env.SUPABASE_URL}/storage/v1${url}`;
}

async function register(user, b) {
  const p = parseRegister(b);
  const reg = await rpc('hsf_register_upload', { p_auth_user: user.id, p });
  const uploadId = reg && typeof reg.upload_id === 'string' && UUID_RE.test(reg.upload_id) ? reg.upload_id.toLowerCase() : null;
  const encoded = uploadId && reg.bucket === BUCKET ? encodedStagingPath(reg.path, uploadId) : null;
  if (!encoded) {
    console.error('hsf upload register failure', 'unexpected response shape');
    throw httpError(502, 'The upload could not be prepared. Please try again.', 'upstream_error');
  }
  const uploadUrl = await signUpload(encoded);
  return { upload_id: uploadId, upload_url: uploadUrl };
}

async function findUpload(user, uploadId) {
  const url = `${process.env.SUPABASE_URL}/rest/v1/hsf_upload`
    + `?id=eq.${uploadId}&auth_user_id=eq.${user.id}`
    + '&select=id,status,storage_bucket,storage_path,size_bytes&limit=1';
  const r = await fetch(url, { headers: serviceHeaders() });
  if (!r.ok) throw new Error(`hsf_upload read failed: ${r.status}`);
  const rows = await r.json();
  return Array.isArray(rows) && rows.length ? rows[0] : null;
}

async function objectSize(encodedPath) {
  let r;
  try {
    r = await fetch(`${process.env.SUPABASE_URL}/storage/v1/object/${BUCKET}/${encodedPath}`, {
      method: 'HEAD',
      headers: serviceHeaders(),
    });
  } catch (err) {
    throw httpError(502, 'The upload could not be checked. Please try again.', 'upstream_error');
  }
  if (r.status === 400 || r.status === 404) return null;
  if (!r.ok) {
    console.error('hsf upload check failure', r.status);
    throw httpError(502, 'The upload could not be checked. Please try again.', 'upstream_error');
  }
  const len = r.headers.get('content-length');
  return len !== null && /^\d+$/.test(len) ? Number(len) : -1; // -1: present, size not reported
}

async function complete(user, b) {
  const uploadId = parseUuid(b.upload_id, 'The upload');
  const row = await findUpload(user, uploadId);
  if (!row) throw httpError(404, 'That upload was not found.', 'not_found');
  if (row.status !== 'awaiting_upload') return { upload_id: uploadId, status: row.status };

  const encoded = row.storage_bucket === BUCKET ? encodedStagingPath(row.storage_path, uploadId) : null;
  if (!encoded) throw httpError(409, 'That upload cannot be completed. Please start it again.', 'conflict');

  const size = await objectSize(encoded);
  if (size === null) {
    throw httpError(409, 'The file has not arrived in secure storage yet. Please upload it again.', 'not_arrived');
  }
  if (size >= 0 && Number(row.size_bytes) !== size) {
    throw httpError(409, 'The stored file is not the size that was registered. Please upload it again.', 'size_mismatch');
  }

  const done = await rpc('hsf_mark_uploaded', { p_auth_user: user.id, p_upload_id: uploadId });
  return {
    upload_id: done && done.upload_id ? done.upload_id : uploadId,
    status: done && done.status ? done.status : 'uploaded',
  };
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
      const list = await rpc('hsf_my_uploads', {
        p_auth_user: user.id,
        p_file_id: optional(fileId) ? null : parseUuid(fileId, 'The File'),
      });
      res.status(200).json(Array.isArray(list) ? list : []);
      return;
    }

    const b = readBody(req);
    if (b.action === 'register') {
      res.status(200).json(await register(user, b));
      return;
    }
    if (b.action === 'complete') {
      res.status(200).json(await complete(user, b));
      return;
    }
    throw httpError(400, "Unknown action. Use 'register' or 'complete'.", 'bad_request');
  } catch (err) {
    sendError(res, err, 'hsf upload');
  }
};
