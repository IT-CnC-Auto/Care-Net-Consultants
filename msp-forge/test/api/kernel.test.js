// CNC HSF FORGE | tests for vercel/api/kernel.js (node --test, global fetch mocked)
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');

const SUPABASE_URL = 'https://unit-test.supabase.invalid';
const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
process.env.SUPABASE_URL = SUPABASE_URL;
process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY;
const REAL_FETCH = globalThis.fetch;

// A syntactically valid key made up for the tests; it opens nothing anywhere.
const API_KEY = `cnck_${'0f'.repeat(32)}`;
const KEY_HASH = crypto.createHash('sha256').update(API_KEY).digest('hex');
const CLIENT_ID = '3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e6f';
const BEARER = { authorization: `Bearer ${API_KEY}` };
const NOTICE = 'Framework reference data from the Care Net Cognitive Kernel. Not legal advice and not a clinical opinion. Only instruments that have passed three verification checks and are in force are included.';

const handler = require('../../vercel/api/kernel');

const logged = [];
test.mock.method(console, 'error', (...a) => { logged.push(a.map(String).join(' ')); });
test.after(() => {
  for (const line of logged) {
    assert.ok(!line.includes(SERVICE_KEY), 'a log line carries the service role key');
    assert.ok(!line.includes(API_KEY), 'a log line carries the client API key');
  }
});

function json(status, body) {
  return new Response(body === undefined ? null : JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

function installFetch(t, fn) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    const i = init || {};
    const c = { url: String(url), method: (i.method || 'GET').toUpperCase(), headers: Object.assign({}, i.headers), body: i.body };
    calls.push(c);
    return fn(c);
  };
  t.after(() => { globalThis.fetch = REAL_FETCH; });
  return calls;
}

function envelope(extra) {
  return Object.assign({ kernel_release: '1.0.0', as_at: '2026-09-23', notice: NOTICE }, extra);
}

// authorise: the msp_api_authorise answer; data: rpc name -> function(args)
function kernelDb(t, authorise, data) {
  return installFetch(t, c => {
    const m = /^https:\/\/unit-test\.supabase\.invalid\/rest\/v1\/rpc\/([a-z0-9_]+)$/.exec(c.url);
    if (!m) throw new Error(`unexpected fetch ${c.method} ${c.url}`);
    assert.equal(c.headers.apikey, SERVICE_KEY);
    assert.equal(c.headers.Authorization, `Bearer ${SERVICE_KEY}`);
    const args = JSON.parse(c.body);
    if (m[1] === 'msp_api_authorise') {
      const out = typeof authorise === 'function' ? authorise(args) : authorise;
      return out instanceof Response ? out : json(200, out);
    }
    const fn = data && data[m[1]];
    if (!fn) throw new Error(`unexpected rpc ${m[1]}`);
    const out = fn(args);
    return out instanceof Response ? out : json(200, out);
  });
}

const OK = { ok: true, client_id: CLIENT_ID, scopes: ['kernel.read'], reason: null };

function mockRes() {
  const res = { statusCode: 200, headers: {}, body: undefined, ended: false };
  res.setHeader = (k, v) => { res.headers[String(k).toLowerCase()] = v; };
  res.getHeader = k => res.headers[String(k).toLowerCase()];
  res.status = c => { res.statusCode = c; return res; };
  res.json = o => { res.body = o; res.ended = true; return res; };
  res.end = () => { res.ended = true; return res; };
  return res;
}

function assertSafe(res) {
  const s = JSON.stringify(res.body === undefined ? null : res.body) + JSON.stringify(res.headers);
  assert.ok(!s.includes(SERVICE_KEY), 'response carries the service role key');
  assert.ok(!s.includes(API_KEY), 'response echoes the client API key');
  assert.ok(!s.includes(KEY_HASH), 'response carries the key hash');
  assert.ok(!/\bat [^\s]+ \(?[^\s)]*:\d+:\d+\)?/.test(s), 'response carries a stack trace');
  assert.ok(!/"stack"/.test(s), 'response carries a stack property');
}

function assertHeaders(res) {
  assert.equal(res.headers['cache-control'], 'no-store');
  assert.equal(res.headers['access-control-allow-origin'], '*');
  assert.match(res.headers['access-control-allow-headers'], /Authorization/);
}

async function call({ method = 'GET', headers = {}, query = {} } = {}) {
  const res = mockRes();
  await handler({ method, headers, query }, res);
  assert.ok(res.ended, 'response not sent');
  assertSafe(res);
  assertHeaders(res);
  return res;
}

test('OPTIONS preflight: 204 with CORS allowing Authorization, no database call', async t => {
  const calls = kernelDb(t, () => { throw new Error('must not be called'); });
  const res = await call({ method: 'OPTIONS', headers: { origin: 'https://bot.example' } });
  assert.equal(res.statusCode, 204);
  assert.match(res.headers['access-control-allow-methods'], /GET/);
  assert.equal(calls.length, 0);
});

test('401 without a key, with WWW-Authenticate, JSON, no-store and CORS, and no database call', async t => {
  const calls = kernelDb(t, () => { throw new Error('must not be called'); });
  const res = await call({ query: { r: 'industries' } });
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.code, 'invalid_key');
  assert.match(res.headers['www-authenticate'], /^Bearer/);
  const bare = await call({});
  assert.equal(bare.statusCode, 401, 'no key and no resource is still 401');
  assert.equal(calls.length, 0);
});

test('401 for malformed keys, checked before the database', async t => {
  const calls = kernelDb(t, () => { throw new Error('must not be called'); });
  for (const h of [
    'Bearer cnck_short',
    `Bearer ${API_KEY.toUpperCase()}`,
    `Bearer ${API_KEY}0`,
    `Basic ${API_KEY}`,
    API_KEY,
    `Bearer sk_${'0f'.repeat(32)}`,
    `Bearer ${TOKEN_LIKE()}`,
  ]) {
    const res = await call({ headers: { authorization: h }, query: { r: 'industries' } });
    assert.equal(res.statusCode, 401, h.slice(0, 16));
  }
  assert.equal(calls.length, 0);
});

function TOKEN_LIKE() { return 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1bml0In0.c2ln'; }

test('400 for a bad or missing resource or parameter, before the database', async t => {
  const calls = kernelDb(t, () => { throw new Error('must not be called'); });
  const cases = [
    {},
    { r: '' },
    { r: 'clients' },
    { r: 'INDUSTRIES' },
    { r: '__proto__' },
    { r: 'constructor' },
    { r: ['industries', 'search'] },
    { r: 'industry' },
    { r: 'industry', code: '../etc' },
    { r: 'industry', code: 'CON STR' },
    { r: 'instruments', industry: 'x'.repeat(70) },
    { r: 'protocols', industry: "CONSTR' or 1=1" },
    { r: 'search' },
    { r: 'search', q: 'a' },
    { r: 'search', q: 'noise%' },
    { r: 'search', q: 'a_b' },
    { r: 'search', q: 'x'.repeat(101) },
    { r: 'search', q: 'bad\u0000' },
  ];
  for (const query of cases) {
    const res = await call({ headers: BEARER, query });
    assert.equal(res.statusCode, 400, JSON.stringify(query));
  }
  assert.equal(calls.length, 0);
});

test('401 for an unknown, revoked or inactive key; the database sees only the SHA 256 hash', async t => {
  for (const reason of ['unknown key', 'revoked', 'inactive', null]) {
    let seen;
    kernelDb(t, a => { seen = a; return { ok: false, client_id: null, scopes: null, reason }; });
    const res = await call({ headers: BEARER, query: { r: 'industries' } });
    assert.equal(res.statusCode, 401, String(reason));
    assert.deepEqual(seen, { p_key_hash: KEY_HASH, p_resource: 'industries' });
    assert.ok(!JSON.stringify(seen).includes(API_KEY), 'the raw key reached the database');
  }
});

test('429 when the hourly limit is reached', async t => {
  const calls = kernelDb(t, { ok: false, client_id: CLIENT_ID, scopes: ['kernel.read'], reason: 'hourly rate limit reached' });
  const res = await call({ headers: BEARER, query: { r: 'instruments' } });
  assert.equal(res.statusCode, 429);
  assert.equal(res.body.code, 'rate_limited');
  assert.equal(calls.length, 1, 'no data read after a refusal');
});

test('403 for a key without the kernel.read scope (reason or scopes list)', async t => {
  kernelDb(t, { ok: false, client_id: CLIENT_ID, scopes: [], reason: 'missing scope kernel.read' });
  assert.equal((await call({ headers: BEARER, query: { r: 'industries' } })).statusCode, 403);
  const calls = kernelDb(t, { ok: true, client_id: CLIENT_ID, scopes: ['other.read'], reason: null });
  assert.equal((await call({ headers: BEARER, query: { r: 'industries' } })).statusCode, 403);
  assert.equal(calls.length, 1, 'no data read without the scope');
});

test('200 for every resource, with the right function, arguments and envelope', async t => {
  const cases = [
    [{ r: 'industries' }, 'kernel_api_industries', {}],
    [{ r: 'industry', code: 'constr' }, 'kernel_api_industry', { p_code: 'CONSTR' }],
    [{ r: 'instruments' }, 'kernel_api_instruments', { p_industry: null }],
    [{ r: 'instruments', industry: 'MINING' }, 'kernel_api_instruments', { p_industry: 'MINING' }],
    [{ r: 'protocols', industry: 'HOSP' }, 'kernel_api_protocols', { p_industry: 'HOSP' }],
    [{ r: 'elements' }, 'kernel_api_elements', { p_industry: null }],
    [{ r: 'elements', industry: 'CONSTR' }, 'kernel_api_elements', { p_industry: 'CONSTR' }],
    [{ r: 'search', q: '  Construction   Regulations ' }, 'kernel_api_search', { p_q: 'Construction Regulations' }],
  ];
  for (const [query, fn, args] of cases) {
    const seen = {};
    const body = envelope({ data: [{ fn }] });
    const calls = kernelDb(t, a => { seen.auth = a; return OK; }, { [fn]: a => { seen.args = a; return body; } });
    const res = await call({ headers: BEARER, query });
    assert.equal(res.statusCode, 200, JSON.stringify(query));
    assert.deepEqual(res.body, body);
    assert.equal(res.body.notice, NOTICE);
    assert.deepEqual(seen.auth, { p_key_hash: KEY_HASH, p_resource: query.r });
    assert.deepEqual(seen.args, args);
    assert.deepEqual(calls.map(c => c.url.split('/rpc/')[1]), ['msp_api_authorise', fn], 'authorise runs before the read');
  }
});

test('404 when the industry code is not in the kernel', async t => {
  kernelDb(t, OK, { kernel_api_industry: () => null });
  const res = await call({ headers: BEARER, query: { r: 'industry', code: 'NOPE' } });
  assert.equal(res.statusCode, 404);
});

test('404 when a kernel read raises SQLSTATE P0002, whatever HTTP status PostgREST used', async t => {
  for (const status of [400, 404, 500]) {
    kernelDb(t, OK, { kernel_api_industry: () => json(status, { code: 'P0002', message: 'No industry has that code.' }) });
    const res = await call({ headers: BEARER, query: { r: 'industry', code: 'NOPE' } });
    assert.equal(res.statusCode, 404, `HTTP ${status}`);
    assert.equal(res.body.code, 'not_found');
  }
});

test('an authorisation store failure is 503 and a read failure is 500, both plain', async t => {
  kernelDb(t, () => json(500, { code: 'XX000', message: `down at x (/srv/a.js:1:1) ${SERVICE_KEY}` }));
  const r1 = await call({ headers: BEARER, query: { r: 'industries' } });
  assert.equal(r1.statusCode, 503);

  kernelDb(t, OK, { kernel_api_industries: () => json(500, { code: 'XX000', message: `boom ${SERVICE_KEY}` }) });
  const r2 = await call({ headers: BEARER, query: { r: 'industries' } });
  assert.equal(r2.statusCode, 500);
  assert.deepEqual(r2.body, { error: 'The request could not be processed.', code: 'server_error' });
});

test('missing server configuration is 503 with no call', async t => {
  const calls = kernelDb(t, () => { throw new Error('must not be called'); });
  const saved = process.env.SUPABASE_URL;
  delete process.env.SUPABASE_URL;
  try {
    const res = await call({ headers: BEARER, query: { r: 'industries' } });
    assert.equal(res.statusCode, 503);
  } finally {
    process.env.SUPABASE_URL = saved;
  }
  assert.equal(calls.length, 0);
});

test('methods other than GET and OPTIONS are 405 and still carry CORS and no-store', async t => {
  const calls = kernelDb(t, () => { throw new Error('must not be called'); });
  for (const method of ['POST', 'PUT', 'DELETE', 'HEAD']) {
    const res = await call({ method, headers: BEARER, query: { r: 'industries' } });
    assert.equal(res.statusCode, 405, method);
    assert.equal(res.headers.allow, 'GET, OPTIONS');
  }
  assert.equal(calls.length, 0);
});
