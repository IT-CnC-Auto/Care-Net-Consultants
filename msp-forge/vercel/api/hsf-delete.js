// CNC HSF FORGE | HSF-WEB-01 v1.0.0 | Deletion of File documents by the client, with a PIN
// Contract 10.5. A company may permanently delete its own documents while their
// bytes are still in Care Net staging. Once MyClinicOnline holds a document,
// deletion is MyClinicOnline's process and the database refuses it here.
//
//   POST /api/hsf-delete { action: 'request', upload_ids: [uuid...], channel: 'email'|'sms',
//                          acknowledged: true }
//        -> hsf_deletion_request_create (ownership, deletable, at most 50, at most
//           5 requests per account per hour, SMS only where offered), then
//           POST {SUPABASE_URL}/auth/v1/otp { email | phone, create_user: false },
//           then hsf_deletion_request_pin_sent. If the PIN cannot be sent the
//           new request is cancelled (hsf_deletion_request_cancel), so only a
//           request whose own PIN went out can ever be confirmed.
//        <- { request_id, expires_at, channel, destination_hint }
//   POST /api/hsf-delete { action: 'confirm', request_id, pin }
//        -> hsf_deletion_request_attempt (counts the attempt first; 5 then locked;
//           10 minutes then expired; at most 10 per account per hour), then
//           POST {SUPABASE_URL}/auth/v1/verify { type: 'email'|'sms', email|phone, token }
//           (a 200 whose user id equals the signed in user is a pass), then
//           hsf_deletion_request_confirm
//        <- { request_id, status: 'confirmed', deleted, upload_ids }
//
// The PIN is sent and checked by Supabase Auth: Care Net never generates or
// stores one. The PIN is never logged or echoed, and a wrong PIN answers the same
// whether it was close or not. The session Supabase Auth opens when a PIN is
// verified is signed out again at once (best effort); its tokens never leave
// this function. Rate limit refusals (the database's PT429, Supabase Auth's 429,
// a locked request) are 429.
//
// Environment (never in files): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. SMS
// needs an SMS provider configured in Supabase Auth and hsf.deletion_sms_enabled.

const { rpc } = require('../lib/db');
const {
  requireUser, sendError, readBody, httpError, methodNotAllowed, UUID_RE,
} = require('../lib/auth');

const CHANNELS = ['email', 'sms'];
const MAX_UPLOADS = 50;
const PIN_RE = /^\d{6,10}$/;
const PIN_WRONG = 'That PIN is not correct or has expired.';
const START_AGAIN = 'Start again to receive a new PIN.';

function serviceHeaders(extra) {
  return Object.assign({
    apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
  }, extra || {});
}

function parseUuid(v, label) {
  if (typeof v !== 'string' || !UUID_RE.test(v)) throw httpError(400, `${label} is missing or not a valid identifier.`, 'bad_request');
  return v.toLowerCase();
}

function parseRequest(b) {
  if (!Array.isArray(b.upload_ids) || b.upload_ids.length < 1) {
    throw httpError(400, 'Choose at least one document to delete.', 'bad_request');
  }
  if (b.upload_ids.length > MAX_UPLOADS) {
    throw httpError(400, `Delete at most ${MAX_UPLOADS} documents at a time.`, 'bad_request');
  }
  const ids = [];
  for (const v of b.upload_ids) {
    const id = parseUuid(v, 'A chosen document');
    if (!ids.includes(id)) ids.push(id);
  }
  if (typeof b.channel !== 'string' || !CHANNELS.includes(b.channel)) {
    throw httpError(400, 'Choose email or SMS for the PIN.', 'bad_request');
  }
  if (b.acknowledged !== true) {
    throw httpError(400, 'Tick that you understand deleting cannot be undone before asking for a PIN.', 'bad_request');
  }
  return { ids, channel: b.channel };
}

// The PIN arrives as typed; spaces a person may add are removed, nothing else.
function parsePin(v) {
  const pin = typeof v === 'string' ? v.replace(/\s+/g, '') : '';
  if (!PIN_RE.test(pin)) throw httpError(400, 'Enter the PIN from your message: 6 to 10 digits.', 'bad_pin');
  return pin;
}

// Where the PIN goes. Email: the address Supabase Auth verified for this token.
// SMS: the confirmed phone on the auth user, read with the admin API, because the
// token reply is not asked for more than requireUser returns.
async function destination(user, channel) {
  if (channel === 'email') {
    if (!user.email) throw httpError(400, 'This sign in has no email address for the PIN.', 'bad_request');
    return { email: user.email };
  }
  let r;
  try {
    r = await fetch(`${process.env.SUPABASE_URL}/auth/v1/admin/users/${user.id}`, { headers: serviceHeaders() });
  } catch (err) {
    throw httpError(502, 'The PIN could not be sent just now. Please try again.', 'upstream_error');
  }
  if (!r.ok) {
    console.error('hsf deletion phone lookup failure', r.status);
    throw httpError(502, 'The PIN could not be sent just now. Please try again.', 'upstream_error');
  }
  let u = null;
  try { u = await r.json(); } catch (e) { u = null; }
  const phone = u && typeof u.phone === 'string' ? u.phone.trim() : '';
  if (!phone || !u.phone_confirmed_at || String(u.id || '').toLowerCase() !== user.id) {
    throw httpError(400, 'A PIN by SMS is not available for this sign in. Choose email.', 'bad_request');
  }
  return { phone };
}

async function sendPin(dest) {
  let r;
  try {
    r = await fetch(`${process.env.SUPABASE_URL}/auth/v1/otp`, {
      method: 'POST',
      headers: { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify(Object.assign({}, dest, { create_user: false })),
    });
  } catch (err) {
    throw httpError(502, 'The PIN could not be sent just now. Please try again.', 'upstream_error');
  }
  if (r.status === 429) {
    throw httpError(429, 'Too many PINs have been sent. Please wait a few minutes and try again.', 'rate_limited');
  }
  if (!r.ok) {
    console.error('hsf deletion pin send failure', r.status);
    throw httpError(502, 'The PIN could not be sent just now. Please try again.', 'upstream_error');
  }
}

// Supabase Auth opens a session when a PIN is verified. It is not needed, so it
// is signed out straight away; a failure here does not undo the check.
async function closeSession(accessToken) {
  if (typeof accessToken !== 'string' || !accessToken) return;
  try {
    await fetch(`${process.env.SUPABASE_URL}/auth/v1/logout?scope=local`, {
      method: 'POST',
      headers: { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${accessToken}` },
    });
  } catch (err) {
    console.error('hsf deletion session close failure', 'unreachable');
  }
}

// Returns 'pass', 'fail' or 'limited'. Throws 502 when Supabase Auth cannot answer.
async function verifyPin(user, channel, dest, pin) {
  let r;
  try {
    r = await fetch(`${process.env.SUPABASE_URL}/auth/v1/verify`, {
      method: 'POST',
      headers: { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify(Object.assign({ type: channel }, dest, { token: pin })),
    });
  } catch (err) {
    throw httpError(502, 'The PIN could not be checked just now. Please try again.', 'upstream_error');
  }
  if (r.status === 429) return 'limited';
  if (r.status >= 500) {
    console.error('hsf deletion pin check failure', r.status);
    throw httpError(502, 'The PIN could not be checked just now. Please try again.', 'upstream_error');
  }
  if (!r.ok) return 'fail';
  let data = null;
  try { data = await r.json(); } catch (e) { data = null; }
  await closeSession(data && data.access_token);
  const id = data && data.user && typeof data.user.id === 'string' ? data.user.id.toLowerCase() : '';
  if (id !== user.id) {
    console.error('hsf deletion pin check failure', 'user mismatch');
    return 'fail';
  }
  return 'pass';
}

async function requestDeletion(user, b) {
  const p = parseRequest(b);
  const created = await rpc('hsf_deletion_request_create', {
    p_auth_user: user.id, p_upload_ids: p.ids, p_channel: p.channel, p_acknowledged: true,
  });
  const requestId = created && typeof created.request_id === 'string' && UUID_RE.test(created.request_id)
    ? created.request_id.toLowerCase() : null;
  if (!requestId) {
    console.error('hsf deletion request failure', 'unexpected response shape');
    throw httpError(502, 'The deletion could not be prepared. Please try again.', 'upstream_error');
  }
  try {
    await sendPin(await destination(user, p.channel));
  } catch (err) {
    // No PIN went out for this request, so it is cancelled: a PIN sent earlier,
    // or a sign in code, can then never confirm it.
    try {
      await rpc('hsf_deletion_request_cancel', { p_auth_user: user.id, p_request_id: requestId });
    } catch (e) {
      console.error('hsf deletion request cancel failure', 'unexpected');
    }
    throw err;
  }
  try {
    await rpc('hsf_deletion_request_pin_sent', { p_auth_user: user.id, p_request_id: requestId });
  } catch (err) {
    console.error('hsf deletion pin sent record failure', 'unexpected');
    throw httpError(502, 'The deletion could not be prepared. Please try again.', 'upstream_error');
  }
  return {
    request_id: requestId,
    expires_at: created.expires_at || null,
    channel: created.channel === 'sms' ? 'sms' : 'email',
    destination_hint: typeof created.destination_hint === 'string' ? created.destination_hint : null,
  };
}

async function findRequest(user, requestId) {
  const url = `${process.env.SUPABASE_URL}/rest/v1/hsf_deletion_request`
    + `?id=eq.${requestId}&auth_user_id=eq.${user.id}&select=id,channel&limit=1`;
  const r = await fetch(url, { headers: serviceHeaders() });
  if (!r.ok) throw new Error(`hsf_deletion_request read failed: ${r.status}`);
  const rows = await r.json();
  return Array.isArray(rows) && rows.length ? rows[0] : null;
}

// A refusal the builder shows as it is, with how many attempts remain.
function refusal(status, code, error, attemptsLeft) {
  const out = { error, code };
  if (Number.isInteger(attemptsLeft)) out.attempts_left = attemptsLeft;
  return { status, body: out };
}

async function confirmDeletion(user, b) {
  const requestId = parseUuid(b.request_id, 'The deletion request');
  const pin = parsePin(b.pin);
  const row = await findRequest(user, requestId);
  if (!row) throw httpError(404, 'That deletion request was not found.', 'not_found');
  const channel = row.channel === 'sms' ? 'sms' : 'email';

  const attempt = await rpc('hsf_deletion_request_attempt', { p_auth_user: user.id, p_request_id: requestId });
  const left = attempt && Number.isInteger(attempt.attempts_left) ? attempt.attempts_left : 0;
  if (!attempt || attempt.allowed !== true) {
    const st = attempt && attempt.status;
    if (st === 'locked') return refusal(429, 'request_locked', `Too many PIN attempts. ${START_AGAIN}`, 0);
    if (st === 'rate_limited') return refusal(429, 'rate_limited', 'Too many PIN attempts in the last hour. Please try again later.', left);
    if (st === 'expired') return refusal(409, 'request_expired', `This PIN has expired. ${START_AGAIN}`, left);
    return refusal(409, 'request_closed', `This deletion request is no longer open. ${START_AGAIN}`, left);
  }

  const verdict = await verifyPin(user, channel, await destination(user, channel), pin);
  if (verdict === 'limited') {
    return refusal(429, 'rate_limited', 'Too many PIN checks. Please wait a few minutes and try again.', left);
  }
  if (verdict !== 'pass') return refusal(400, 'pin_incorrect', PIN_WRONG, left);

  const done = await rpc('hsf_deletion_request_confirm', { p_auth_user: user.id, p_request_id: requestId });
  return {
    status: 200,
    body: {
      request_id: requestId,
      status: 'confirmed',
      deleted: done && Number.isInteger(done.deleted) ? done.deleted : 0,
      upload_ids: done && Array.isArray(done.upload_ids) ? done.upload_ids : [],
    },
  };
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') {
    methodNotAllowed(res, ['POST']);
    return;
  }
  try {
    const user = await requireUser(req);
    const b = readBody(req);
    if (b.action === 'request') {
      res.status(200).json(await requestDeletion(user, b));
      return;
    }
    if (b.action === 'confirm') {
      const out = await confirmDeletion(user, b);
      res.status(out.status).json(out.body);
      return;
    }
    throw httpError(400, "Unknown action. Use 'request' or 'confirm'.", 'bad_request');
  } catch (err) {
    sendError(res, err, 'hsf delete');
  }
};
