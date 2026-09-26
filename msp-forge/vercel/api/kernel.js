// CNC HSF FORGE | HSF-KRN-API v1.0.0 | Cognitive Kernel read API for approved clients
// The server to server read API through which Odendaal links a Grok bot to the
// Care Net Cognitive Kernel, and which any other approved client may use to read
// framework reference data. Read only; JSON only; no client data of any kind.
//
//   GET /api/kernel?r=industries
//   GET /api/kernel?r=industry&code=<INDUSTRY>
//   GET /api/kernel?r=instruments[&industry=<INDUSTRY>]
//   GET /api/kernel?r=protocols[&industry=<INDUSTRY>]
//   GET /api/kernel?r=elements[&industry=<INDUSTRY>]
//   GET /api/kernel?r=search&q=<text>
//   Header: Authorization: Bearer cnck_<64 hex characters>
//
// A key is issued once by msp_api_client_issue (service role or forge_admin);
// only its SHA 256 hash is stored. Each call is checked and logged by
// msp_api_authorise (active, not revoked, scope kernel.read, under the hourly
// limit); no request body, IP address or query text is logged by this handler.
// 401 bad or missing key, 403 key without the kernel.read scope, 429 hourly
// limit reached, 400 bad resource or parameter, 404 nothing found (a null reply
// or SQLSTATE P0002). Only instruments that are verified three ways, in force
// and not under a currency hold are ever returned (instrument reads use
// kernel_citable_instrument; element bases use hsf_element_citable, which also
// needs a safety scope and a verified provision, contract 9.3 and 9.4); each
// response carries the kernel release, the date and the notice that it is not
// legal advice and not a clinical opinion.
//
// CORS is open (Access-Control-Allow-Origin: *) because keys are used server to
// server with no cookies; a key must never be placed in a browser page.
// The Grok model name, if a bot needs one, is configured in that bot's own
// environment, never here.

const crypto = require('crypto');
const { rpc } = require('../lib/db');
const { sendError, queryValue, httpError, serverConfigured, redact, CONTROL_RE } = require('../lib/auth');

const BEARER_KEY_RE = /^Bearer (cnck_[0-9a-f]{64})$/;
const CODE_RE = /^[A-Z][A-Z0-9_]{0,31}(?:-[A-Z0-9_]{1,31}){0,4}$/;
// Letters, digits, spaces and the punctuation found in instrument names. No
// % or _ (LIKE wildcards) and no backslash.
const SEARCH_RE = /^[\p{L}\p{N} .,'()&/-]+$/u;
const REQUIRED_SCOPE = 'kernel.read';

function code(v, label, required) {
  if (v === null || v === '') {
    if (required) throw httpError(400, `The ${label} parameter is required for this resource.`, 'bad_request');
    return null;
  }
  const s = v.trim().toUpperCase();
  if (s.length > 64 || !CODE_RE.test(s)) throw httpError(400, `The ${label} parameter is not a valid code.`, 'bad_request');
  return s;
}

function searchText(v) {
  const s = (v || '').replace(/\s+/g, ' ').trim();
  if (s.length < 2 || s.length > 100 || CONTROL_RE.test(s) || !SEARCH_RE.test(s)) {
    throw httpError(400, 'The q parameter must be 2 to 100 letters, digits, spaces or simple punctuation.', 'bad_request');
  }
  return s;
}

const RESOURCES = {
  industries: { fn: 'kernel_api_industries', args: () => ({}) },
  industry: { fn: 'kernel_api_industry', args: req => ({ p_code: code(queryValue(req, 'code'), 'code', true) }) },
  instruments: { fn: 'kernel_api_instruments', args: req => ({ p_industry: code(queryValue(req, 'industry'), 'industry', false) }) },
  protocols: { fn: 'kernel_api_protocols', args: req => ({ p_industry: code(queryValue(req, 'industry'), 'industry', false) }) },
  elements: { fn: 'kernel_api_elements', args: req => ({ p_industry: code(queryValue(req, 'industry'), 'industry', false) }) },
  search: { fn: 'kernel_api_search', args: req => ({ p_q: searchText(queryValue(req, 'q')) }) },
};

function setCommonHeaders(res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization');
  res.setHeader('Access-Control-Max-Age', '600');
  res.setHeader('X-Content-Type-Options', 'nosniff');
}

function unauthorised(message) {
  const err = httpError(401, message || 'A valid kernel API key is required.', 'invalid_key');
  err.wwwAuthenticate = true;
  return err;
}

function keyFrom(req) {
  const raw = (req.headers && (req.headers.authorization || req.headers.Authorization)) || '';
  if (typeof raw !== 'string' || raw.length > 200) return null;
  const m = BEARER_KEY_RE.exec(raw.trim());
  return m ? m[1] : null;
}

function resourceFrom(req) {
  const r = queryValue(req, 'r');
  if (r === null || !Object.prototype.hasOwnProperty.call(RESOURCES, r)) {
    throw httpError(400, 'Unknown resource. Use r=industries, industry, instruments, protocols, elements or search.', 'bad_resource');
  }
  return r;
}

async function authorise(key, resource) {
  const keyHash = crypto.createHash('sha256').update(key, 'utf8').digest('hex');
  let auth;
  try {
    auth = await rpc('msp_api_authorise', { p_key_hash: keyHash, p_resource: resource });
  } catch (err) {
    console.error('kernel api authorise failure', err && err.message ? redact(err.message) : 'unknown');
    throw httpError(503, 'The kernel API is not available at the moment.', 'unavailable');
  }
  if (!auth || auth.ok !== true) {
    const reason = auth && typeof auth.reason === 'string' ? auth.reason : '';
    if (/rate|limit|quota|too many/i.test(reason)) {
      throw httpError(429, 'The hourly call limit for this key has been reached. Please try again later.', 'rate_limited');
    }
    if (/scope/i.test(reason)) throw httpError(403, 'This key does not carry the kernel.read scope.', 'forbidden');
    throw unauthorised();
  }
  if (Array.isArray(auth.scopes) && !auth.scopes.includes(REQUIRED_SCOPE)) {
    throw httpError(403, 'This key does not carry the kernel.read scope.', 'forbidden');
  }
  return auth;
}

module.exports = async (req, res) => {
  setCommonHeaders(res);
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET, OPTIONS');
    res.status(405).json({ error: 'Method not allowed.', code: 'method_not_allowed' });
    return;
  }
  try {
    const key = keyFrom(req);
    if (!key) throw unauthorised();
    const resource = resourceFrom(req);
    const spec = RESOURCES[resource];
    const args = spec.args(req);
    if (!serverConfigured()) throw httpError(503, 'The kernel API is not available at the moment.', 'unavailable');

    await authorise(key, resource);

    const data = await rpc(spec.fn, args);
    if (data === null || data === undefined) {
      throw httpError(404, resource === 'industry' ? 'No industry has that code.' : 'Nothing was found.', 'not_found');
    }
    res.status(200).json(data);
  } catch (err) {
    if (err && err.wwwAuthenticate) res.setHeader('WWW-Authenticate', 'Bearer realm="cnc-kernel"');
    sendError(res, err, 'kernel api');
  }
};
