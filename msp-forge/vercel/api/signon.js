// CNC MSP FORGE | FRM-GATE-01 v1.5.0 | CNC client sign on (self-service), and File only registration
// A client registers their company and is handed their single use assessment
// link in the same response. There is no consultant approval step: the Plan is
// free for every client who books medicals (MD ruling 31/08/2026), so the gate
// that used to sit here only ever stalled registrations.
//
// v1.1.0 (09/09/2026): writes through the msp_client_signon security definer
// function instead of a raw table insert (RLS refused the direct insert).
// v1.2.0 (11/09/2026): msp_client_signon now approves on the spot and returns
// the assessment token; this endpoint turns it into the link the page shows.
// v1.3.0 (16/09/2026): accepts contact_number (optional) and passes it to
// msp_client_signon, which stores it on msp_client_account.contact_number
// (migration 043). The front end can stop carrying the number inside notes.
// Loose shape check only: digits, spaces, +, -, ( ) and dots, 7 to 40 characters.
// v1.4.0 (24/09/2026): an account that already exists is answered only to its
// own signed in contact (review finding REG-1). Before, anyone who posted an
// email got that account's live assessment link (its token opens the saved
// draft through /api/draft), its company name and its contact number. Now:
//   - the caller counts as the account's contact only when the request carries
//     "Authorization: Bearer <access token>" and Supabase Auth says the token
//     belongs to a user whose confirmed email is the contact_email posted;
//   - for anyone else, an email that already has an account is answered with a
//     neutral { status: 'received' } and nothing else, and msp_client_signon is
//     not called for it, so an anonymous post never approves the account, mints
//     or reuses its token, or fills in its contact number. The contact reaches
//     their link by signing in (/api/company-lookup on the Plan landing);
//   - a new email is registered and answered in full, as before, because the
//     account and its first token were made by this very request.
// msp_client_signon is itself callable by the service role only (migration 043).
// v1.5.0 (24/09/2026): File only registration (build contract section 15). The
// Health and Safety File builder registers a company here too, and
// msp_client_signon calls msp_client_start_assessment (migration 040), which
// approves the account as a Plan client and mints a live Plan assessment token.
// So registering for a File quietly started a Medical Surveillance Plan
// assessment. Now:
//   - a body with source: 'hsf' (sent only by vercel/hsf-builder.html) is
//     registered through hsf_client_register (migration 056), which records the
//     account as msp_client_signon does but never approves it, never starts a
//     Plan assessment and never issues a token. The answer is status,
//     reference, existing, company_name, contact_number and declined; never a
//     token, an account kind or an assessment_url. The Plan starts for that
//     company only if its contact later chooses it on the Plan landing
//     (/api/company-lookup);
//   - every rule above holds for it as well: method, honeypot, required fields
//     and number shape. The signed in contact rule is stricter here (review
//     finding REG-R3, before v1.5.0 went live): a File registration is made
//     only for the caller whose confirmed, signed in email is the
//     contact_email posted. Anyone else (no token, another email, an
//     unconfirmed email, a token Supabase Auth refuses) gets 401, and neither
//     msp_company_lookup nor hsf_client_register is called, so nobody can
//     create an account for someone else's email under a company name they
//     choose. The builder always posts with the signed in contact's token;
//   - if hsf_client_register is not in the database yet (056 not applied), the
//     answer is 503 "File registration is not available yet" and the gap is
//     logged. It never falls back to msp_client_signon;
//   - any other source value is refused with 400 before any call, so a
//     mistyped source never starts a Plan assessment;
//   - a body without source (the Plan landing, vercel/index.html) is handled
//     exactly as before.

const { rpc } = require('../lib/db');

const NUMBER_SHAPE = /^[0-9+()\-. ]{7,40}$/;
// The one source value this endpoint knows: the Health and Safety File builder.
const FILE_SOURCE = 'hsf';
// Supabase access tokens are JWTs: three base64url segments (as lib/auth.js).
const BEARER_RE = /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/;
const MAX_TOKEN_LENGTH = 8192;

function cleanNumber(v) {
  if (v == null) return null;
  const s = String(v).trim();
  if (!s) return null;
  return NUMBER_SHAPE.test(s) ? s : undefined; // undefined = present but malformed
}

function assessmentUrl(req, token) {
  if (!token) return null;
  const proto = (req.headers['x-forwarded-proto'] || 'https').split(',')[0].trim();
  const host = (req.headers['x-forwarded-host'] || req.headers.host || '').split(',')[0].trim();
  return `${proto}://${host}/assess.html?token=${encodeURIComponent(token)}`;
}

// The confirmed email of the signed in caller, in lower case, or null when the
// request carries no valid access token or Supabase Auth cannot confirm it. A
// caller that cannot be confirmed is treated as anonymous, never refused, so
// the Plan landing (which sends no token) works as before.
async function signedInEmail(req) {
  const headers = req.headers || {};
  const raw = headers.authorization || headers.Authorization || '';
  if (typeof raw !== 'string' || !raw || raw.length > MAX_TOKEN_LENGTH) return null;
  const m = BEARER_RE.exec(raw.trim());
  if (!m) return null;
  try {
    const r = await fetch(`${process.env.SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${m[1]}` },
    });
    if (!r.ok) return null;
    const u = await r.json();
    if (!u || typeof u.email !== 'string' || !u.email.trim()) return null;
    if (!u.email_confirmed_at && !u.confirmed_at) return null;
    return u.email.trim().toLowerCase();
  } catch (err) {
    return null;
  }
}

// What anyone but the account's own contact is told about an email that
// already has an account: that the details arrived, and nothing about it.
function neutral(res) {
  res.status(200).json({ status: 'received' });
}

// True when PostgREST says a function is not in the database (or not yet in its
// schema cache): PGRST202, or PostgreSQL's undefined_function (42883). lib/db.js
// rpc() reports a failure as "<fn> failed: <status> <PostgREST body>".
function functionMissing(err, fn) {
  const m = /^([a-z0-9_]+) failed: (\d{3}) ([\s\S]*)$/.exec((err && err.message) || '');
  if (!m || m[1] !== fn) return false;
  let body = null;
  try { body = JSON.parse(m[3]); } catch (e) { body = null; }
  const code = body && typeof body.code === 'string' ? body.code : '';
  const message = body && typeof body.message === 'string' ? body.message : '';
  return code === 'PGRST202' || code === '42883'
    || (m[2] === '404' && /could not find the function/i.test(message));
}

// File only registration (v1.5.0): hsf_client_register, never msp_client_signon.
// The answer is rebuilt from the named fields, so nothing of the Plan (a token,
// an account kind, an assessment link) can reach the File builder.
async function registerForFile(res, b, contactNumber, own) {
  let r;
  try {
    r = await rpc('hsf_client_register', {
      p: {
        company_name: b.company_name, contact_name: b.contact_name,
        contact_email: b.contact_email, contact_number: contactNumber,
        notes: b.notes || null,
      },
    });
  } catch (err) {
    if (functionMissing(err, 'hsf_client_register')) {
      console.error('file registration unavailable: hsf_client_register is not in the database (migration 056 not applied)');
      res.status(503).json({ error: 'File registration is not available yet' });
      return;
    }
    throw err;
  }
  // Only the signed in contact reaches here (see the handler); kept as a guard.
  if (!r || (r.existing && !own)) { neutral(res); return; }
  res.status(200).json({
    status: 'received',
    reference: r.reference,
    existing: !!r.existing,
    company_name: r.company_name,
    contact_number: r.contact_number || null,
    declined: !!r.declined,
  });
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.status(405).json({ error: 'method not allowed' }); return; }
  const b = req.body || {};
  if (b.website) { res.status(200).json({ status: 'rejected' }); return; }
  if (!b.company_name || !b.contact_name || !b.contact_email) {
    res.status(400).json({ error: 'company name, contact name, and email are required' });
    return;
  }
  const contactNumber = cleanNumber(b.contact_number);
  if (contactNumber === undefined) {
    res.status(400).json({ error: 'the contact number should be digits, with an optional + and spaces' });
    return;
  }
  const hasSource = b.source !== undefined && b.source !== null && b.source !== '';
  if (hasSource && b.source !== FILE_SOURCE) {
    res.status(400).json({ error: 'unknown registration source' });
    return;
  }
  const email = String(b.contact_email).trim().toLowerCase();
  try {
    const caller = await signedInEmail(req);
    const own = caller !== null && caller === email;
    // The File path registers only for its own confirmed, signed in contact,
    // so nobody can make an account for someone else's email under a company
    // name of their choosing (review finding REG-R3). The builder always sends
    // the token; no lookup and no registration happens without it.
    if (hasSource && !own) {
      res.status(401).json({ error: 'sign in with this email to register your company for a File' });
      return;
    }
    if (!own) {
      const found = await rpc('msp_company_lookup', { p_email: email });
      if (found && found.found) { neutral(res); return; }
    }
    if (hasSource) { await registerForFile(res, b, contactNumber, own); return; }
    const r = await rpc('msp_client_signon', {
      p: {
        company_name: b.company_name, contact_name: b.contact_name,
        contact_email: b.contact_email, contact_number: contactNumber,
        notes: b.notes || null,
      },
    });
    // An account made by someone else between the lookup and the sign on.
    if (r.existing && !own) { neutral(res); return; }
    res.status(200).json({
      status: 'received',
      reference: r.reference,
      existing: !!r.existing,
      company_name: r.company_name,
      contact_number: r.contact_number || null,
      account_kind: r.account_kind,
      declined: !!r.declined,
      assessment_url: r.declined ? null : assessmentUrl(req, r.token),
    });
  } catch (err) {
    console.error('signon failure', err.message);
    res.status(500).json({ error: 'sign on could not be recorded' });
  }
};
