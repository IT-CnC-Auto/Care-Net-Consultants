// CNC HSF FORGE | tests for vercel/api/portal-summary.js (node --test, global fetch mocked)
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
const FILE_ID = '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const ENGAGEMENT_ID = '4d5e6f7a-8b9c-4d0e-9f1a-2b3c4d5e6f7a';
const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1bml0In0.c2lnbmF0dXJlLXVuaXQ';
const AUTH = { authorization: `Bearer ${TOKEN}` };
// A made up access token value that must never reach the browser from this endpoint.
const FORM_TOKEN = 'form-access-token-UNIT-TEST-never-returned';

const handler = require('../../vercel/api/portal-summary');

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

function supabase(t, rpcs) {
  return installFetch(t, c => {
    if (c.url === `${SUPABASE_URL}/auth/v1/user`) {
      return c.headers.Authorization === `Bearer ${TOKEN}`
        ? json(200, { id: USER_ID, email: 'safety@example.co.za' })
        : json(401, { msg: 'invalid JWT' });
    }
    const m = /^https:\/\/unit-test\.supabase\.invalid\/rest\/v1\/rpc\/([a-z0-9_]+)$/.exec(c.url);
    if (m) {
      assert.equal(c.method, 'POST');
      assert.equal(c.headers.apikey, SERVICE_KEY);
      assert.equal(c.headers.Authorization, `Bearer ${SERVICE_KEY}`);
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
  assert.ok(!s.includes(FORM_TOKEN), 'response carries an access token');
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

const rpcNames = calls => calls.filter(c => c.url.includes('/rest/v1/rpc/')).map(c => c.url.split('/rpc/')[1]);

// The contract 9.8 shape, with values of the kind the database returns.
const SUMMARY = {
  account: { client_account_id: ACCOUNT_ID, company_name: 'Example Holdings (Pty) Ltd', account_kind: 'approved_client', approved_at: '2026-09-20T09:15:00+00:00' },
  plans: [{ engagement_id: ENGAGEMENT_ID, reference: 'CNC-MSP-2026-0920-001', status: 'drafting', industry_code: 'CONSTR', revision: 1, created_at: '2026-09-20T10:00:00+00:00' }],
  quotes: [{ quote_reference: 'CNC-QTE-2026-0919-004', package_code: 'SIGNED_PLAN', price_zar: 4250, price_status: 'indicative', valid_until: '2026-10-19', created_at: '2026-09-19T08:00:00+00:00' }],
  files: [{
    file_id: FILE_ID, reference: 'CNC-HSF-2026-0923-001', industry_code: 'CONSTR', status: 'draft', revision: 1, compliance_pct: 12.5,
    signoffs: [{ kind: 'safety_content', decision: 'approved', decided_at: '2026-09-23T11:00:00+00:00' }],
  }],
};

test('401 without a token, and no call at all', async t => {
  const calls = supabase(t, {});
  const res = await call({});
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.code, 'sign_in_required');
  assert.equal(calls.length, 0);
});

test('401 for a token Supabase Auth does not accept, and no database call', async t => {
  const calls = supabase(t, {});
  const res = await call({ headers: { authorization: 'Bearer aaa.bbb.ccc' } });
  assert.equal(res.statusCode, 401);
  assert.deepEqual(rpcNames(calls), []);
});

test('GET: auth, account link, then hsf_portal_summary for the verified user only', async t => {
  let seen;
  const calls = supabase(t, { hsf_portal_summary: a => { seen = a; return SUMMARY; } });
  const res = await call({ headers: AUTH, query: { user: 'someone-else' } });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(seen, { p_auth_user: USER_ID });
  assert.deepEqual(res.body, SUMMARY);
  assert.deepEqual(calls.map(c => c.url.replace(SUPABASE_URL, '')),
    ['/auth/v1/user', '/rest/v1/rpc/hsf_link_account', '/rest/v1/rpc/hsf_portal_summary']);
});

test('never calls company-lookup functions that start an assessment or mint a token', async t => {
  const calls = supabase(t, { hsf_portal_summary: () => SUMMARY });
  await call({ headers: AUTH });
  const names = rpcNames(calls);
  assert.ok(!names.includes('msp_client_start_assessment'));
  assert.ok(!names.includes('msp_company_lookup'));
  assert.deepEqual(names, ['hsf_link_account', 'hsf_portal_summary']);
});

test('no company account: account null and empty lists', async t => {
  supabase(t, { hsf_portal_summary: () => ({ account: null, plans: [], quotes: [], files: [] }) });
  const res = await call({ headers: AUTH });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { account: null, plans: [], quotes: [], files: [] });
});

test('a null or malformed reply becomes the empty shape, never an error page', async t => {
  for (const out of [null, [], 'text', { account: 'x', plans: 'x', quotes: null, files: {} }]) {
    supabase(t, { hsf_portal_summary: () => out });
    const res = await call({ headers: AUTH });
    assert.equal(res.statusCode, 200, JSON.stringify(out));
    assert.deepEqual(res.body, { account: null, plans: [], quotes: [], files: [] });
  }
});

test('only the contract fields reach the browser: extra fields, tokens and nested objects are dropped', async t => {
  const noisy = JSON.parse(JSON.stringify(SUMMARY));
  noisy.account.contact_email = 'safety@example.co.za';
  noisy.account.auth_user_id = USER_ID;
  noisy.plans[0].token = FORM_TOKEN;
  noisy.plans[0].status = { nested: FORM_TOKEN };
  noisy.quotes[0].access_token = FORM_TOKEN;
  noisy.files[0].signoffs[0].signed_by = 'reviewer@example.co.za';
  noisy.files.push('not a row');
  noisy.extra = { token: FORM_TOKEN };
  supabase(t, { hsf_portal_summary: () => noisy });
  const res = await call({ headers: AUTH });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(Object.keys(res.body), ['account', 'plans', 'quotes', 'files']);
  assert.deepEqual(Object.keys(res.body.account), ['client_account_id', 'company_name', 'account_kind', 'approved_at']);
  assert.equal(res.body.plans[0].status, null, 'a nested value is not passed through');
  assert.ok(!('token' in res.body.plans[0]));
  assert.ok(!('access_token' in res.body.quotes[0]));
  assert.deepEqual(Object.keys(res.body.files[0].signoffs[0]), ['kind', 'decision', 'decided_at']);
  assert.equal(res.body.files.length, 1);
  assert.ok(!JSON.stringify(res.body).includes('example.co.za'));
});

test('missing fields are null and the rand price stays a number', async t => {
  supabase(t, { hsf_portal_summary: () => ({ account: { client_account_id: ACCOUNT_ID }, quotes: [{ quote_reference: 'CNC-QTE-2026-0919-001', price_zar: 4250.5 }], files: [{ file_id: FILE_ID }] }) });
  const res = await call({ headers: AUTH });
  assert.deepEqual(res.body.account, { client_account_id: ACCOUNT_ID, company_name: null, account_kind: null, approved_at: null });
  assert.equal(res.body.quotes[0].price_zar, 4250.5);
  assert.equal(res.body.quotes[0].valid_until, null);
  assert.deepEqual(res.body.files[0].signoffs, []);
  assert.deepEqual(res.body.plans, []);
});

test('a failed account link is a 503 and the summary is not read', async t => {
  const calls = supabase(t, {
    hsf_link_account: () => json(500, { code: 'XX000', message: `down ${SERVICE_KEY}` }),
    hsf_portal_summary: () => { throw new Error('must not be called'); },
  });
  const res = await call({ headers: AUTH });
  assert.equal(res.statusCode, 503);
  assert.deepEqual(rpcNames(calls), ['hsf_link_account']);
});

test('a database failure is a plain 500 with no detail, stack or key', async t => {
  supabase(t, { hsf_portal_summary: () => json(500, { code: 'XX000', message: `boom at fn (/srv/db.js:1:1) ${SERVICE_KEY}` }) });
  const res = await call({ headers: AUTH });
  assert.equal(res.statusCode, 500);
  assert.deepEqual(res.body, { error: 'The request could not be processed.', code: 'server_error' });
});

test('methods other than GET are 405 with an Allow header, before any sign in check', async t => {
  const calls = supabase(t, {});
  for (const method of ['POST', 'PUT', 'DELETE', 'PATCH']) {
    const res = await call({ method, headers: AUTH });
    assert.equal(res.statusCode, 405, method);
    assert.equal(res.headers.allow, 'GET');
  }
  assert.equal(calls.length, 0);
});
