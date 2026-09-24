// CNC HSF FORGE | HSF-ADS-01 v1.0.0 | First party Bee-Inspect banner events
// Built to hsf/BUILD-CONTRACT.md 16.3 (Bee-Inspect P1) and section A4 of
// hsf/BEE-INSPECT-BUILD-PROMPT.md.
//
//   POST /api/hsf-events  {event, ad_id, variant, page, industry, f_band}
//     -> hsf_ad_event_record(p) (migration 057), service role only
//     <- 202 {accepted: true}         stored
//        202 {accepted: false}        dropped: the database is not set up for
//                                     it yet (057 not applied, or no Supabase
//                                     settings), or it refused the flood
//        400 {error}                  a malformed or unknown event
//        405, 413, 429                method, size, rate
//
// What is stored is only what the banner knows: the event, the banner id, its
// variant, the page, the File's industry code and a band of Section F counts.
// No user, email, company, cookie, IP address or document content reaches the
// database or the logs. The caller's address is used only in memory, hashed
// with a salt made when the instance starts, for the per instance rate limit,
// and is never written anywhere. The page sends events with sendBeacon or
// fetch keepalive and never waits for the answer, so this endpoint never holds
// up the File builder; it never answers 500 to a page.
//
// Browser events: ad_impression, ad_click, ad_dismiss, ad_qr_shown. The other
// events of A4 (claim_code_created, claim_code_scanned, install, trial_start,
// subscribe) need server truth and are refused here; P3 records them from
// their own server side sources.

const crypto = require('crypto');
const { rpc } = require('../lib/db');

const BROWSER_EVENTS = ['ad_impression', 'ad_click', 'ad_dismiss', 'ad_qr_shown'];
const SERVER_EVENTS = ['claim_code_created', 'claim_code_scanned', 'install', 'trial_start', 'subscribe'];
const KEYS = ['event', 'ad_id', 'variant', 'page', 'industry', 'f_band'];
const PAGES = ['/hsf-builder', '/health-and-safety-file', '/portal', '/bee-inspect'];
const BANDS = ['na', '0', '1to2', '3to5', '6plus'];
// AD-09 and AD-10 are parked (export page and email); the browser cannot send them.
const AD_RE = /^AD-0[1-8]$/;
const VARIANT_RE = /^[a-z0-9_]{1,24}$/;
const INDUSTRY_RE = /^[A-Z][A-Z0-9_]{1,15}$/;
const MAX_BODY_BYTES = 1024;

// Per instance limits: a caller, and the instance as a whole, per minute.
const WINDOW_MS = 60 * 1000;
const PER_CALLER = 60;
const PER_INSTANCE = 600;
const SALT = crypto.randomBytes(16).toString('hex');
const buckets = new Map();
let instance = { start: 0, count: 0 };

function now() { return Date.now(); }

function callerKey(req) {
  const h = (req && req.headers) || {};
  const fwd = String(h['x-forwarded-for'] || '').split(',')[0].trim();
  const raw = fwd || String(h['x-real-ip'] || '') || String((req.socket && req.socket.remoteAddress) || '');
  return crypto.createHash('sha256').update(SALT + '|' + raw).digest('hex').slice(0, 32);
}

// True when the request may go on; counts it.
function allow(req) {
  const t = now();
  if (t - instance.start >= WINDOW_MS) instance = { start: t, count: 0 };
  if (instance.count >= PER_INSTANCE) return false;
  const k = callerKey(req);
  let b = buckets.get(k);
  if (!b || t - b.start >= WINDOW_MS) { b = { start: t, count: 0 }; buckets.set(k, b); }
  if (b.count >= PER_CALLER) return false;
  b.count++;
  instance.count++;
  if (buckets.size > 5000) {
    for (const [key, v] of buckets) if (t - v.start >= WINDOW_MS) buckets.delete(key);
  }
  return true;
}

function resetLimits() { buckets.clear(); instance = { start: 0, count: 0 }; }

// The body as an object, or an error { status, error }.
function readBody(req) {
  const len = Number((req.headers || {})['content-length']);
  if (Number.isFinite(len) && len > MAX_BODY_BYTES) return { status: 413, error: 'event too large' };
  let b = req.body;
  if (Buffer.isBuffer(b)) b = b.toString('utf8');
  if (typeof b === 'string') {
    if (Buffer.byteLength(b, 'utf8') > MAX_BODY_BYTES) return { status: 413, error: 'event too large' };
    try { b = JSON.parse(b); } catch (e) { return { status: 400, error: 'the event must be JSON' }; }
  } else if (b && typeof b === 'object') {
    let s = '';
    try { s = JSON.stringify(b); } catch (e) { return { status: 400, error: 'the event must be JSON' }; }
    if (Buffer.byteLength(s, 'utf8') > MAX_BODY_BYTES) return { status: 413, error: 'event too large' };
  }
  if (!b || typeof b !== 'object' || Array.isArray(b)) return { status: 400, error: 'the event must be a JSON object' };
  return { body: b };
}

// A clean event, or { error }.
function validate(b) {
  for (const k of Object.keys(b)) {
    if (!KEYS.includes(k)) return { error: 'unknown field ' + String(k).slice(0, 40) };
  }
  for (const k of KEYS) {
    const v = b[k];
    if (v !== undefined && v !== null && typeof v !== 'string') return { error: k + ' must be text' };
  }
  if (SERVER_EVENTS.includes(b.event)) return { error: 'this event is recorded by Care Net’s servers, not by a page' };
  if (!BROWSER_EVENTS.includes(b.event)) return { error: 'unknown event' };
  if (typeof b.ad_id !== 'string' || !AD_RE.test(b.ad_id)) return { error: 'unknown banner' };
  if (typeof b.variant !== 'string' || !VARIANT_RE.test(b.variant)) return { error: 'bad variant' };
  if (!PAGES.includes(b.page)) return { error: 'unknown page' };
  const industry = b.industry === undefined || b.industry === null || b.industry === '' ? null : b.industry;
  if (industry !== null && !INDUSTRY_RE.test(industry)) return { error: 'bad industry code' };
  const band = b.f_band === undefined || b.f_band === null || b.f_band === '' ? null : b.f_band;
  if (band !== null && !BANDS.includes(band)) return { error: 'bad Section F band' };
  return { event: { event: b.event, ad_id: b.ad_id, variant: b.variant, page: b.page, industry, f_band: band } };
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    res.status(405).json({ error: 'method not allowed' });
    return;
  }
  const read = readBody(req);
  if (read.error) { res.status(read.status).json({ error: read.error }); return; }
  const v = validate(read.body);
  if (v.error) { res.status(400).json({ error: v.error }); return; }
  if (!allow(req)) { res.status(429).json({ error: 'too many events', accepted: false }); return; }
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    res.status(202).json({ accepted: false });
    return;
  }
  try {
    const r = await rpc('hsf_ad_event_record', { p: v.event });
    res.status(202).json({ accepted: !!(r && r.accepted === true) });
  } catch (err) {
    // 057 not applied yet, or the database refused: the event is dropped,
    // never a 500 to the page. The log line names the gap, never the event.
    const m = /^hsf_ad_event_record failed: (\d{3})/.exec((err && err.message) || '');
    console.error('hsf-events: event dropped (' + (m ? 'database answered ' + m[1] : 'database unreachable') + ')');
    res.status(202).json({ accepted: false });
  }
};

module.exports.validate = validate;
module.exports.readBody = readBody;
module.exports.resetLimits = resetLimits;
module.exports.BROWSER_EVENTS = BROWSER_EVENTS;
module.exports.SERVER_EVENTS = SERVER_EVENTS;
module.exports.LIMITS = { PER_CALLER, PER_INSTANCE, MAX_BODY_BYTES };
