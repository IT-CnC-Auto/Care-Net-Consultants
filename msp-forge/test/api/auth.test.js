// CNC HSF FORGE | tests for vercel/lib/auth.js (node --test, global fetch mocked)
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const SUPABASE_URL = 'https://unit-test.supabase.invalid';
const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
process.env.SUPABASE_URL = SUPABASE_URL;
process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY;
const REAL_FETCH = globalThis.fetch;

const USER_ID = '6f1c2d3e-4a5b-4c6d-8e7f-9a0b1c2d3e4f';
const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1bml0In0.c2lnbmF0dXJlLXVuaXQ';

const auth = require('../../vercel/lib/auth');

const logged = [];
test.mock.method(console, 'error', (...a) => { logged.push(a.map(String).join(' ')); });

function json(status, body, headers) {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status, headers: Object.assign({ 'content-type': 'application/json' }, headers || {}),
  });
}

function installFetch(t, handler) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    const i = init || {};
    const call = { url: String(url), method: (i.method || 'GET').toUpperCase(), headers: Object.assign({}, i.headers), body: i.body };
    calls.push(call);
    return handler(call);
  };
  t.after(() => { globalThis.fetch = REAL_FETCH; });
  return calls;
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

test.after(() => {
  for (const line of logged) assert.ok(!line.includes(SERVICE_KEY), 'a log line carries the service role key');
});

test('requireUser: no Authorization header is 401 and makes no network call', async t => {
  const calls = installFetch(t, () => { throw new Error('no call expected'); });
  await assert.rejects(auth.requireUser({ headers: {} }), e => e.status === 401);
  assert.equal(calls.length, 0);
});

test('requireUser: malformed bearer values are 401 without a network call', async t => {
  const calls = installFetch(t, () => { throw new Error('no call expected'); });
  for (const h of ['Basic abc', 'Bearer', 'Bearer not-a-jwt', `Bearer ${TOKEN} extra`, `bearer${TOKEN}`, `Bearer ${'a'.repeat(9000)}.b.c`]) {
    await assert.rejects(auth.requireUser({ headers: { authorization: h } }), e => e.status === 401, h.slice(0, 20));
  }
  assert.equal(calls.length, 0);
});

const LINK_URL = `${SUPABASE_URL}/rest/v1/rpc/hsf_link_account`;
const ACCOUNT_ID = '0b9a8c7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d';

// Auth answers with the user; hsf_link_account answers with `link` (a value or a Response).
function authAndLink(t, user, link) {
  return installFetch(t, c => {
    if (c.url === `${SUPABASE_URL}/auth/v1/user`) return user instanceof Response ? user : json(200, user);
    if (c.url === LINK_URL) {
      if (typeof link === 'function') return link(c);
      return link instanceof Response ? link : json(200, link === undefined ? ACCOUNT_ID : link);
    }
    throw new Error(`unexpected fetch ${c.method} ${c.url}`);
  });
}

test('requireUser: calls GET /auth/v1/user with the service apikey and the user token, then links the account once', async t => {
  const calls = authAndLink(t, { id: USER_ID.toUpperCase(), email: 'safety@example.co.za', role: 'authenticated' });
  const user = await auth.requireUser({ headers: { authorization: `Bearer ${TOKEN}` } });
  assert.deepEqual(user, { id: USER_ID, email: 'safety@example.co.za' });
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, `${SUPABASE_URL}/auth/v1/user`);
  assert.equal(calls[0].method, 'GET');
  assert.equal(calls[0].headers.apikey, SERVICE_KEY);
  assert.equal(calls[0].headers.Authorization, `Bearer ${TOKEN}`);

  // Contract 9.1: hsf_link_account, service role, the verified id only (lower case).
  assert.equal(calls[1].url, LINK_URL);
  assert.equal(calls[1].method, 'POST');
  assert.equal(calls[1].headers.apikey, SERVICE_KEY);
  assert.equal(calls[1].headers.Authorization, `Bearer ${SERVICE_KEY}`);
  assert.deepEqual(JSON.parse(calls[1].body), { p_auth_user: USER_ID });
});

test('requireUser: a user with no company account to link (null) is still signed in', async t => {
  const calls = authAndLink(t, { id: USER_ID, email: 'new@example.co.za' }, null);
  const user = await auth.requireUser({ headers: { authorization: `Bearer ${TOKEN}` } });
  assert.deepEqual(user, { id: USER_ID, email: 'new@example.co.za' });
  assert.equal(calls.filter(c => c.url === LINK_URL).length, 1);
});

test('requireUser: the email in the token reply is never sent to the linker', async t => {
  const calls = authAndLink(t, { id: USER_ID, email: 'someone.else@example.co.za', email_confirmed_at: null });
  await auth.requireUser({ headers: { authorization: `Bearer ${TOKEN}` } });
  const link = calls.find(c => c.url === LINK_URL);
  assert.deepEqual(Object.keys(JSON.parse(link.body)), ['p_auth_user'], 'the database reads the confirmed email itself');
});

test('requireUser: a linking failure is 503 (not a false "no account"), plain and without the key', async t => {
  for (const link of [
    json(500, { code: 'XX000', message: `boom ${SERVICE_KEY}` }),
    json(404, { code: 'PGRST202', message: 'Could not find the function public.hsf_link_account' }),
    json(400, { code: 'P0001', message: 'refused' }),
    () => { throw new TypeError(`fetch failed ${SERVICE_KEY}`); },
  ]) {
    authAndLink(t, { id: USER_ID, email: 'safety@example.co.za' }, link);
    await assert.rejects(auth.requireUser({ headers: { authorization: `Bearer ${TOKEN}` } }), e => {
      assert.equal(e.status, 503);
      assert.equal(e.code, 'unavailable');
      assert.ok(!e.message.includes(SERVICE_KEY));
      const r = mockRes();
      auth.sendError(r, e);
      assert.equal(r.statusCode, 503);
      assert.deepEqual(r.body, { error: 'Your company account could not be checked. Please try again.', code: 'unavailable' });
      assertSafe(r);
      return true;
    });
  }
});

test('requireUser: an expired or unknown token is 401, and nothing is linked', async t => {
  const calls = installFetch(t, () => json(401, { msg: 'invalid JWT' }));
  await assert.rejects(auth.requireUser({ headers: { authorization: `Bearer ${TOKEN}` } }), e => e.status === 401);
  assert.equal(calls.filter(c => c.url.includes('/rest/v1/')).length, 0);
});

test('requireUser: a user object without a uuid id is 401, and nothing is linked', async t => {
  const calls = authAndLink(t, { id: 'nope', email: 'x@example.co.za' });
  await assert.rejects(auth.requireUser({ headers: { authorization: `Bearer ${TOKEN}` } }), e => e.status === 401);
  assert.equal(calls.filter(c => c.url === LINK_URL).length, 0);
});

test('requireUser: an auth outage is 503, not a sign out, and nothing is linked', async t => {
  let calls = installFetch(t, () => { throw new TypeError('fetch failed'); });
  await assert.rejects(auth.requireUser({ headers: { authorization: `Bearer ${TOKEN}` } }), e => e.status === 503);
  assert.equal(calls.length, 1);
  calls = installFetch(t, () => json(502, { message: 'bad gateway' }));
  await assert.rejects(auth.requireUser({ headers: { authorization: `Bearer ${TOKEN}` } }), e => e.status === 503);
  assert.equal(calls.length, 1);
});

test('requireUser: missing server configuration is 503 and makes no call', async t => {
  const calls = installFetch(t, () => { throw new Error('no call expected'); });
  const saved = process.env.SUPABASE_SERVICE_ROLE_KEY;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  try {
    await assert.rejects(auth.requireUser({ headers: { authorization: `Bearer ${TOKEN}` } }), e => e.status === 503);
  } finally {
    process.env.SUPABASE_SERVICE_ROLE_KEY = saved;
  }
  assert.equal(calls.length, 0);
});

test('readBody: object, JSON string, Buffer, empty and invalid bodies', () => {
  assert.deepEqual(auth.readBody({ body: { a: 1 } }), { a: 1 });
  assert.deepEqual(auth.readBody({ body: '{"a":2}' }), { a: 2 });
  assert.deepEqual(auth.readBody({ body: Buffer.from('{"a":3}') }), { a: 3 });
  assert.deepEqual(auth.readBody({ body: undefined }), {});
  assert.deepEqual(auth.readBody({ body: '   ' }), {});
  assert.throws(() => auth.readBody({ body: '{not json' }), e => e.status === 400);
  assert.throws(() => auth.readBody({ body: '[1,2]' }), e => e.status === 400);
  assert.throws(() => auth.readBody({ body: [1, 2] }), e => e.status === 400);
  assert.throws(() => auth.readBody({ body: '"text"' }), e => e.status === 400);
});

test('queryValue: single values pass, repeated keys are refused', () => {
  assert.equal(auth.queryValue({ query: { kind: 'mco_transfer' } }, 'kind'), 'mco_transfer');
  assert.equal(auth.queryValue({ query: {} }, 'kind'), null);
  assert.equal(auth.queryValue({}, 'kind'), null);
  assert.throws(() => auth.queryValue({ query: { kind: ['a', 'b'] } }, 'kind'), e => e.status === 400);
});

test('sendError: maps .status, hides unexposed messages and never sends a stack', () => {
  const r1 = mockRes();
  auth.sendError(r1, auth.httpError(401, 'Please sign in to continue.', 'sign_in_required'));
  assert.equal(r1.statusCode, 401);
  assert.deepEqual(r1.body, { error: 'Please sign in to continue.', code: 'sign_in_required' });
  assert.equal(r1.headers['cache-control'], 'no-store');

  const r2 = mockRes();
  const internal = new Error(`connect ECONNREFUSED with key ${SERVICE_KEY}`);
  auth.sendError(r2, internal);
  assert.equal(r2.statusCode, 500);
  assert.equal(r2.body.code, 'server_error');
  assertSafe(r2);

  const r3 = mockRes();
  const e3 = new Error('internal detail'); e3.status = 404;
  auth.sendError(r3, e3);
  assert.equal(r3.statusCode, 404);
  assert.equal(r3.body.error, 'That record was not found.');
  assertSafe(r3);
});

test('sendError: a deliberate database refusal (P0001) is a 400 with its message; P0002 is 404; other database errors are generic', () => {
  const refusal = new Error('hsf_register_upload failed: 400 {"code":"P0001","details":null,"hint":null,"message":"Consent is not complete for this account."}');
  const r1 = mockRes();
  auth.sendError(r1, refusal);
  assert.equal(r1.statusCode, 400);
  assert.deepEqual(r1.body, { error: 'Consent is not complete for this account.', code: 'refused' });

  const leaky = new Error(`hsf_register_upload failed: 400 {"code":"P0001","message":"key ${SERVICE_KEY}"}`);
  const r2 = mockRes();
  auth.sendError(r2, leaky);
  assert.equal(r2.statusCode, 400);
  assertSafe(r2);

  const notFound = new Error('hsf_set_item_status failed: 500 {"code":"P0002","message":"That File item was not found."}');
  const r0 = mockRes();
  auth.sendError(r0, notFound);
  assert.equal(r0.statusCode, 404, 'P0002 is a 404 whatever HTTP status PostgREST gave it');
  assert.deepEqual(r0.body, { error: 'That record was not found.', code: 'not_found' });

  const forbidden = new Error('hsf_file_detail failed: 403 {"code":"42501","message":"permission denied for function hsf_file_detail"}');
  const r3 = mockRes();
  auth.sendError(r3, forbidden);
  assert.equal(r3.statusCode, 403);
  assert.ok(!JSON.stringify(r3.body).includes('permission denied for function'));

  const crash = new Error('hsf_my_files failed: 500 {"code":"XX000","message":"at Object.<anonymous> (/srv/x.js:1:2)"}');
  const r4 = mockRes();
  auth.sendError(r4, crash);
  assert.equal(r4.statusCode, 500);
  assertSafe(r4);
});

test('shape constants: uuid and sha256', () => {
  assert.ok(auth.UUID_RE.test(USER_ID));
  assert.ok(!auth.UUID_RE.test(`${USER_ID}0`));
  assert.ok(auth.SHA256_RE.test('a'.repeat(64)));
  assert.ok(!auth.SHA256_RE.test('A'.repeat(64)));
  assert.ok(!auth.SHA256_RE.test('a'.repeat(63)));
});
