// CNC HSF FORGE | HSF-WEB-01 v1.0.0 | Signed in user check and shared request helpers
// Used by the Health and Safety File endpoints (hsf-consent, hsf-upload, hsf-file)
// and by the kernel API. Server side only: the service role key is read from
// the environment at call time and never leaves this process.
//
//   requireUser(req)  reads "Authorization: Bearer <access_token>", asks Supabase
//                     Auth who the token belongs to (GET /auth/v1/user) and
//                     returns { id, email }. A missing, malformed, expired or
//                     unknown token throws an error with .status = 401. An auth
//                     service that cannot be reached throws .status = 503, so the
//                     browser does not sign a person out because of an outage.
//   sendError(res, e) maps e.status (or a deliberate refusal raised by one of our
//                     security definer functions) to a JSON error. It never sends
//                     a stack trace, a raw database error or any secret.
//   readBody(req)     Vercel parses a JSON body into req.body; a string or Buffer
//                     body (another host, or a client that sent text/plain) is
//                     parsed here. Invalid JSON throws .status = 400.
//
// Environment (never in files): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/;
// Printable text only: no C0 or C1 control characters (tabs and new lines included).
const CONTROL_RE = /[\u0000-\u001f\u007f-\u009f]/;
// A thirteen digit run resembles a South African identity number (as lib/validate.js).
const ID_NUMBER_RE = /\d{13}/;
// Supabase access tokens are JWTs: three base64url segments.
const BEARER_RE = /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/;
const MAX_TOKEN_LENGTH = 8192;

function httpError(status, message, code) {
  const err = new Error(message);
  err.status = status;
  err.expose = true; // the message was written for the person reading the response
  if (code) err.code = code;
  return err;
}

function serverConfigured() {
  return Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
}

function bearerToken(req) {
  const headers = (req && req.headers) || {};
  const raw = headers.authorization || headers.Authorization || '';
  if (typeof raw !== 'string' || !raw || raw.length > MAX_TOKEN_LENGTH) return null;
  const m = BEARER_RE.exec(raw.trim());
  return m ? m[1] : null;
}

async function requireUser(req) {
  const token = bearerToken(req);
  if (!token) throw httpError(401, 'Please sign in to continue.', 'sign_in_required');
  if (!serverConfigured()) throw httpError(503, 'The service is not available at the moment.', 'not_configured');

  let userRes;
  try {
    userRes = await fetch(`${process.env.SUPABASE_URL}/auth/v1/user`, {
      headers: {
        apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${token}`,
      },
    });
  } catch (err) {
    throw httpError(503, 'Your sign in could not be checked. Please try again.', 'auth_unavailable');
  }
  if (userRes.status >= 500) {
    throw httpError(503, 'Your sign in could not be checked. Please try again.', 'auth_unavailable');
  }
  if (!userRes.ok) throw httpError(401, 'Please sign in to continue.', 'sign_in_required');

  let user;
  try { user = await userRes.json(); } catch (err) { user = null; }
  if (!user || typeof user.id !== 'string' || !UUID_RE.test(user.id)) {
    throw httpError(401, 'Please sign in to continue.', 'sign_in_required');
  }
  return {
    id: user.id.toLowerCase(),
    email: typeof user.email === 'string' && user.email ? user.email : null,
  };
}

function readBody(req) {
  const b = req ? req.body : undefined;
  if (b === undefined || b === null || b === '') return {};
  let parsed = b;
  if (Buffer.isBuffer(b)) parsed = b.toString('utf8');
  if (typeof parsed === 'string') {
    if (!parsed.trim()) return {};
    try { parsed = JSON.parse(parsed); } catch (err) {
      throw httpError(400, 'The request body is not valid JSON.', 'bad_json');
    }
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw httpError(400, 'The request body must be a JSON object.', 'bad_json');
  }
  return parsed;
}

// A query value from Vercel is a string, or an array when the key repeats.
// A repeated key is refused rather than guessed at.
function queryValue(req, key) {
  const q = (req && req.query) || {};
  const v = q[key];
  if (v === undefined || v === null) return null;
  if (Array.isArray(v)) throw httpError(400, `Send ${key} once only.`, 'bad_request');
  return String(v);
}

// Database errors arrive from lib/db.js rpc() as "<fn> failed: <status> <PostgREST body>".
// Only a deliberate refusal (raise exception in one of our functions, SQLSTATE P0001)
// carries a message meant for the client; everything else becomes a plain status.
function classifyDbError(err) {
  const m = /^[a-z0-9_]+ failed: (\d{3}) ([\s\S]*)$/.exec((err && err.message) || '');
  if (!m) return null;
  let body = null;
  try { body = JSON.parse(m[2]); } catch (e) { body = null; }
  const code = body && typeof body.code === 'string' ? body.code : '';
  const message = body && typeof body.message === 'string' ? body.message : '';
  if (code === 'P0001') return { status: 400, code: 'refused', message: cleanMessage(message) };
  if (code === 'P0002') return { status: 404, code: 'not_found', message: 'That record was not found.' };
  if (code === '42501') return { status: 403, code: 'forbidden', message: 'You do not have access to that record.' };
  if (code === '23505') return { status: 409, code: 'conflict', message: 'That record already exists.' };
  if (/^22/.test(code)) return { status: 400, code: 'bad_request', message: 'The request could not be accepted.' };
  return null;
}

const SECRET_ENV = ['SUPABASE_SERVICE_ROLE_KEY', 'MCO_API_TOKEN'];

function containsSecret(s) {
  return SECRET_ENV.some(k => process.env[k] && process.env[k].length >= 8 && s.includes(process.env[k]));
}

// For log lines: secrets from the environment are replaced, the text is capped.
function redact(value) {
  let s = String(value === undefined || value === null ? '' : value).slice(0, 500);
  for (const k of SECRET_ENV) {
    const v = process.env[k];
    if (v && v.length >= 8) s = s.split(v).join('[redacted]');
  }
  return s;
}

function cleanMessage(message) {
  let s = String(message || '').replace(/[\u0000-\u001f\u007f-\u009f]+/g, ' ').trim().slice(0, 300);
  if (!s || containsSecret(s)) s = 'The request could not be accepted.';
  return s;
}

const GENERIC = {
  400: 'The request could not be accepted.',
  401: 'Please sign in to continue.',
  403: 'You do not have access to that record.',
  404: 'That record was not found.',
  405: 'Method not allowed.',
  409: 'That request conflicts with the current state of the record.',
  413: 'The request is too large.',
  429: 'Too many requests. Please try again later.',
  502: 'A connected service did not respond as expected. Please try again.',
  503: 'The service is not available at the moment.',
};
const CODES = {
  400: 'bad_request', 401: 'sign_in_required', 403: 'forbidden', 404: 'not_found',
  405: 'method_not_allowed', 409: 'conflict', 413: 'too_large', 429: 'rate_limited',
  502: 'upstream_error', 503: 'unavailable',
};

function sendError(res, err, context) {
  let status = err && Number.isInteger(err.status) && err.status >= 400 && err.status <= 599 ? err.status : 0;
  let message = null;
  let code = null;
  if (status) {
    message = err.expose ? cleanMessage(err.message) : null;
    code = typeof err.code === 'string' ? err.code : null;
  } else {
    const db = classifyDbError(err);
    if (db) { status = db.status; message = db.message; code = db.code; }
  }
  if (!status) status = 500;
  if (status >= 500) {
    // Log the message only: never the stack, never a request body.
    console.error(`${context || 'api'} failure`, err && err.message ? redact(err.message) : 'unknown');
  }
  if (typeof res.setHeader === 'function') res.setHeader('Cache-Control', 'no-store');
  res.status(status).json({
    error: message || GENERIC[status] || 'The request could not be processed.',
    code: code || CODES[status] || 'server_error',
  });
}

function methodNotAllowed(res, allowed) {
  res.setHeader('Allow', allowed.join(', '));
  res.setHeader('Cache-Control', 'no-store');
  res.status(405).json({ error: 'Method not allowed.', code: 'method_not_allowed' });
}

module.exports = {
  requireUser,
  sendError,
  readBody,
  queryValue,
  httpError,
  methodNotAllowed,
  classifyDbError,
  serverConfigured,
  redact,
  UUID_RE,
  SHA256_RE,
  CONTROL_RE,
  ID_NUMBER_RE,
};
