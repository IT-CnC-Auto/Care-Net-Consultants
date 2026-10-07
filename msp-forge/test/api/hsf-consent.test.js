// CNC HSF FORGE | tests for vercel/api/hsf-consent.js (node --test, global fetch mocked)
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const SUPABASE_URL = 'https://unit-test.supabase.invalid';
const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
process.env.SUPABASE_URL = SUPABASE_URL;
process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY;
const REAL_FETCH = globalThis.fetch;

const USER_ID = '6f1c2d3e-4a5b-4c6d-8e7f-9a0b1c2d3e4f';
const ACCOUNT_ID = '0b9a8c7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d';
const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1bml0In0.c2lnbmF0dXJlLXVuaXQ';
const AUTH = { authorization: `Bearer ${TOKEN}` };
const WORDING = 'HSF-CONSENT-1.0';
const KINDS = ['document_storage', 'mco_transfer', 'authority_to_share'];

const handler = require('../../vercel/api/hsf-consent');

const logged = [];
test.mock.method(console, 'error', (...a) => { logged.push(a.map(String).join(' ')); });
test.after(() => {
  for (const line of logged) assert.ok(!line.includes(SERVICE_KEY), 'a log line carries the service role key');
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

// A fake Supabase: Auth answers for TOKEN only; rpc functions from the map.
function supabase(t, rpcs) {
  return installFetch(t, c => {
    if (c.url === `${SUPABASE_URL}/auth/v1/user`) {
      return c.headers.Authorization === `Bearer ${TOKEN}`
        ? json(200, { id: USER_ID, email: 'safety@example.co.za' })
        : json(401, { msg: 'invalid JWT' });
    }
    const m = /\/rest\/v1\/rpc\/([a-z0-9_]+)$/.exec(c.url);
    if (m && c.url.startsWith(`${SUPABASE_URL}/rest/v1/rpc/`)) {
      assert.equal(c.method, 'POST');
      assert.equal(c.headers.apikey, SERVICE_KEY);
      assert.equal(c.headers.Authorization, `Bearer ${SERVICE_KEY}`);
      // Contract 9.1: lib/auth.js links the verified user once per request.
      if (m[1] === 'hsf_link_account' && !rpcs.hsf_link_account) {
        assert.deepEqual(JSON.parse(c.body), { p_auth_user: USER_ID });
        return json(200, ACCOUNT_ID);
      }
      const fn = rpcs[m[1]];
      if (!fn) throw new Error(`unexpected rpc ${m[1]}`);
      const out = fn(JSON.parse(c.body));
      return out instanceof Response ? out : json(200, out);
    }
    throw new Error(`unexpected fetch ${c.method} ${c.url}`);
  });
}

function mockRes() {
  const res = { statusCode: 200, headers: {}, body: undefined };
  res.setHeader = (k, v) => { res.headers[String(k).toLowerCase()] = v; };
  res.getHeader = k => res.headers[String(k).toLowerCase()];
  res.status = c => { res.statusCode = c; return res; };
  res.json = o => { res.body = o; return res; };
  res.end = () => res;
  return res;
}

function assertSafe(res) {
  const s = JSON.stringify(res.body === undefined ? null : res.body) + JSON.stringify(res.headers);
  assert.ok(!s.includes(SERVICE_KEY), 'response carries the service role key');
  assert.ok(!/\bat [^\s]+ \(?[^\s)]*:\d+:\d+\)?/.test(s), 'response carries a stack trace');
  assert.ok(!/"stack"/.test(s), 'response carries a stack property');
}

async function call({ method = 'GET', headers = {}, query = {}, body } = {}) {
  const res = mockRes();
  await handler({ method, headers, query, body }, res);
  assertSafe(res);
  assert.equal(res.headers['cache-control'], 'no-store');
  return res;
}

function status(kinds) {
  const s = { client_account_id: ACCOUNT_ID, company_name: 'Example Holdings (Pty) Ltd', wording_version: WORDING };
  for (const k of KINDS) s[k] = kinds.includes(k);
  s.complete = KINDS.every(k => s[k]);
  return s;
}

// Database calls made by the handler itself (the account link in lib/auth.js is counted apart).
const rpcCalls = calls => calls.filter(c => c.url.includes('/rest/v1/rpc/') && !c.url.endsWith('/rpc/hsf_link_account'));
const linkCalls = calls => calls.filter(c => c.url.endsWith('/rpc/hsf_link_account'));

test('401 without a token on every method, and no database call', async t => {
  const calls = supabase(t, {});
  for (const method of ['GET', 'POST', 'DELETE']) {
    const res = await call({ method, body: { kinds: KINDS, wording_version: WORDING }, query: { kind: 'mco_transfer' } });
    assert.equal(res.statusCode, 401, method);
    assert.equal(res.body.code, 'sign_in_required');
  }
  assert.equal(calls.length, 0);
});

test('401 with a token Supabase Auth does not accept, and no rpc (not even the account link)', async t => {
  const calls = supabase(t, {});
  const res = await call({ headers: { authorization: 'Bearer aaa.bbb.ccc' } });
  assert.equal(res.statusCode, 401);
  assert.equal(calls.length, 1);
  assert.equal(rpcCalls(calls).length, 0);
  assert.equal(linkCalls(calls).length, 0);
});

test('GET returns hsf_consent_status for the verified user only, after the account link', async t => {
  let seen;
  const calls = supabase(t, { hsf_consent_status: a => { seen = a; return status([]); } });
  const res = await call({ headers: AUTH, query: { user: 'someone-else' } });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(seen, { p_auth_user: USER_ID });
  assert.equal(res.body.complete, false);
  assert.equal(res.body.wording_version, WORDING);
  assert.deepEqual(calls.map(c => c.url.replace(SUPABASE_URL, '')),
    ['/auth/v1/user', '/rest/v1/rpc/hsf_link_account', '/rest/v1/rpc/hsf_consent_status']);
});

test('a signed in contact whose account links on this request sees it at once (contract 9.1)', async t => {
  // The fake database links on the first call, as hsf_link_account does for a
  // confirmed email that matches a registered company.
  let linked = false;
  supabase(t, {
    hsf_link_account: a => { assert.deepEqual(a, { p_auth_user: USER_ID }); linked = true; return ACCOUNT_ID; },
    hsf_consent_status: () => (linked ? status([]) : Object.assign(status([]), { client_account_id: null, company_name: null })),
  });
  const res = await call({ headers: AUTH });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.client_account_id, ACCOUNT_ID);
});

test('a failed account link is a 503 and the consent status is not read', async t => {
  const calls = supabase(t, {
    hsf_link_account: () => json(500, { code: 'XX000', message: `down ${SERVICE_KEY}` }),
    hsf_consent_status: () => { throw new Error('must not be called'); },
  });
  const res = await call({ headers: AUTH });
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.code, 'unavailable');
  assert.equal(rpcCalls(calls).length, 0);
});

test('POST records the three consents with the wording version', async t => {
  let seen;
  supabase(t, { hsf_record_consent: a => { seen = a; return status(a.p_kinds); } });
  const res = await call({ method: 'POST', headers: AUTH, body: { kinds: KINDS, wording_version: WORDING } });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(seen, { p_auth_user: USER_ID, p_kinds: KINDS, p_wording_version: WORDING });
  assert.equal(res.body.complete, true);
});

test('POST accepts a JSON string body', async t => {
  let seen;
  supabase(t, { hsf_record_consent: a => { seen = a; return status(a.p_kinds); } });
  const res = await call({ method: 'POST', headers: AUTH, body: JSON.stringify({ kinds: ['mco_transfer'], wording_version: WORDING }) });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(seen.p_kinds, ['mco_transfer']);
});

test('POST refuses bad input with 400 and never reaches the database', async t => {
  const calls = supabase(t, { hsf_record_consent: () => { throw new Error('must not be called'); } });
  const bad = [
    { wording_version: WORDING },
    { kinds: 'document_storage', wording_version: WORDING },
    { kinds: [], wording_version: WORDING },
    { kinds: ['marketing'], wording_version: WORDING },
    { kinds: ['mco_transfer', 'mco_transfer'], wording_version: WORDING },
    { kinds: [...KINDS, 'document_storage'], wording_version: WORDING },
    { kinds: [1], wording_version: WORDING },
    { kinds: KINDS },
    { kinds: KINDS, wording_version: '' },
    { kinds: KINDS, wording_version: 'HSF CONSENT 1.0' },
    { kinds: KINDS, wording_version: 'x'.repeat(41) },
    { kinds: KINDS, wording_version: 10 },
  ];
  for (const body of bad) {
    const res = await call({ method: 'POST', headers: AUTH, body });
    assert.equal(res.statusCode, 400, JSON.stringify(body));
    assert.equal(typeof res.body.error, 'string');
  }
  const res = await call({ method: 'POST', headers: AUTH, body: '{"kinds": [' });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.code, 'bad_json');
  assert.equal(rpcCalls(calls).length, 0);
});

test('a refusal raised by the database (P0001) reaches the client as a 400 with its message', async t => {
  supabase(t, {
    hsf_record_consent: () => json(400, { code: 'P0001', details: null, hint: null, message: 'The consent wording has changed. Please read the current wording.' }),
  });
  const res = await call({ method: 'POST', headers: AUTH, body: { kinds: KINDS, wording_version: 'HSF-CONSENT-0.9' } });
  assert.equal(res.statusCode, 400);
  assert.deepEqual(res.body, { error: 'The consent wording has changed. Please read the current wording.', code: 'refused' });
});

test('DELETE ?kind= withdraws one consent', async t => {
  let seen;
  supabase(t, { hsf_withdraw_consent: a => { seen = a; return status(['document_storage', 'authority_to_share']); } });
  const res = await call({ method: 'DELETE', headers: AUTH, query: { kind: 'mco_transfer' } });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(seen, { p_auth_user: USER_ID, p_kind: 'mco_transfer' });
  assert.equal(res.body.complete, false);
});

test('DELETE refuses a missing, unknown or repeated kind', async t => {
  const calls = supabase(t, { hsf_withdraw_consent: () => { throw new Error('must not be called'); } });
  for (const query of [{}, { kind: 'everything' }, { kind: ['mco_transfer', 'document_storage'] }]) {
    const res = await call({ method: 'DELETE', headers: AUTH, query });
    assert.equal(res.statusCode, 400, JSON.stringify(query));
  }
  assert.equal(rpcCalls(calls).length, 0);
});

test('other methods are 405 with an Allow header, before any sign in check', async t => {
  const calls = supabase(t, {});
  for (const method of ['PUT', 'PATCH', 'OPTIONS']) {
    const res = await call({ method, headers: AUTH });
    assert.equal(res.statusCode, 405, method);
    assert.equal(res.headers.allow, 'GET, POST, DELETE');
  }
  assert.equal(calls.length, 0);
});

test('a database failure is a plain 500 with no detail, stack or key', async t => {
  supabase(t, {
    hsf_consent_status: () => json(500, { code: 'XX000', message: `internal at Object.<anonymous> (/srv/db.js:10:5) ${SERVICE_KEY}` }),
  });
  const res = await call({ headers: AUTH });
  assert.equal(res.statusCode, 500);
  assert.deepEqual(res.body, { error: 'The request could not be processed.', code: 'server_error' });
});
