// CNC HSF FORGE | tests for vercel/api/hsf-file.js (node --test, global fetch mocked)
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const SUPABASE_URL = 'https://unit-test.supabase.invalid';
const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
process.env.SUPABASE_URL = SUPABASE_URL;
process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY;
const REAL_FETCH = globalThis.fetch;

const USER_ID = '6f1c2d3e-4a5b-4c6d-8e7f-9a0b1c2d3e4f';
const FILE_ID = '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const ITEM_ID = '2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e';
const ACCOUNT_ID = '0b9a8c7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d';
const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1bml0In0.c2lnbmF0dXJlLXVuaXQ';
const AUTH = { authorization: `Bearer ${TOKEN}` };

const handler = require('../../vercel/api/hsf-file');

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

// Database calls made by the handler itself (the account link in lib/auth.js is counted apart).
const rpcCalls = calls => calls.filter(c => c.url.includes('/rest/v1/rpc/') && !c.url.endsWith('/rpc/hsf_link_account'));
const linkCalls = calls => calls.filter(c => c.url.endsWith('/rpc/hsf_link_account'));

function generateBody(over) {
  return Object.assign({
    action: 'generate',
    industry_code: 'constr',
    subindustry_code: 'CONSTR-CIVILS',
    triggers: ['T-CONSTR', 'T-HEIGHT', 'T-CONSTR', 'U', 'T-CONSTR-NOTIFY'],
    scope: {
      sites: [{ name: '  Main yard ', address: '12 Example Road,\nGermiston' }, { name: 'Site 2' }],
      project_reference: 'PRJ 2026 14',
      headcount: 48,
      extra: 'ignored',
    },
  }, over || {});
}

test('401 without a token, and no call at all', async t => {
  const calls = supabase(t, {});
  assert.equal((await call({})).statusCode, 401);
  assert.equal((await call({ query: { file_id: FILE_ID } })).statusCode, 401);
  assert.equal((await call({ method: 'POST', body: generateBody() })).statusCode, 401);
  assert.equal(calls.length, 0);
});

test('GET lists my Files; a null result is an empty list', async t => {
  const files = [{ file_id: FILE_ID, reference: 'CNC-HSF-2026-0923-001', industry_code: 'CONSTR', industry_name: 'Construction', status: 'draft', revision: 1, compliance_pct: 0, created_at: '2026-09-23T08:00:00Z' }];
  let seen;
  supabase(t, { hsf_my_files: a => { seen = a; return files; } });
  const r1 = await call({ headers: AUTH });
  assert.equal(r1.statusCode, 200);
  assert.deepEqual(r1.body, files);
  assert.deepEqual(seen, { p_auth_user: USER_ID });

  supabase(t, { hsf_my_files: () => null });
  assert.deepEqual((await call({ headers: AUTH })).body, []);
});

test('GET ?file_id= returns the detail; a bad id is 400', async t => {
  const detail = { file: { file_id: FILE_ID }, sections: [], overall: { pct: 0, counts: {} } };
  let seen;
  const c1 = supabase(t, { hsf_file_detail: a => { seen = a; return detail; } });
  const r1 = await call({ headers: AUTH, query: { file_id: FILE_ID.toUpperCase() } });
  assert.equal(r1.statusCode, 200);
  assert.deepEqual(r1.body, detail);
  assert.deepEqual(seen, { p_auth_user: USER_ID, p_file_id: FILE_ID });
  assert.equal(linkCalls(c1).length, 1, 'the account is linked once, before the read');

  const calls = supabase(t, {});
  for (const file_id of ['1', 'x'.repeat(36), [FILE_ID, ITEM_ID]]) {
    assert.equal((await call({ headers: AUTH, query: { file_id } })).statusCode, 400);
  }
  assert.equal(rpcCalls(calls).length, 0);
});

// Contract 9.2: hsf_file_detail returns SQL null (PostgREST answers 200 null) for a
// File that does not exist or is not the caller's. Both answer the same 404.
test('GET ?file_id= for a missing File, or one of another account, is the same 404 (null detail)', async t => {
  supabase(t, { hsf_file_detail: () => null });
  const missing = await call({ headers: AUTH, query: { file_id: ITEM_ID } });
  const foreign = await call({ headers: AUTH, query: { file_id: FILE_ID } });
  for (const res of [missing, foreign]) {
    assert.equal(res.statusCode, 404);
    assert.deepEqual(res.body, { error: 'That File was not found.', code: 'not_found' });
  }
});

test('GET ?file_id= raising SQLSTATE P0002 is a 404, whatever HTTP status PostgREST used', async t => {
  for (const status of [400, 404, 500]) {
    supabase(t, { hsf_file_detail: () => json(status, { code: 'P0002', details: null, hint: null, message: 'That File was not found.' }) });
    const res = await call({ headers: AUTH, query: { file_id: FILE_ID } });
    assert.equal(res.statusCode, 404, `HTTP ${status}`);
    assert.deepEqual(res.body, { error: 'That File was not found.', code: 'not_found' });
  }
});

test('GET ?file_id= a non object detail is treated as not found', async t => {
  for (const out of ['', 0, false]) {
    supabase(t, { hsf_file_detail: () => out });
    const res = await call({ headers: AUTH, query: { file_id: FILE_ID } });
    assert.equal(res.statusCode, 404, JSON.stringify(out));
  }
});

test('GET for a File of another account: a permission refusal (42501) is still a plain 403', async t => {
  supabase(t, { hsf_file_detail: () => json(403, { code: '42501', message: 'permission denied: file belongs to another account' }) });
  const res = await call({ headers: AUTH, query: { file_id: FILE_ID } });
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, 'You do not have access to that record.');
});

test('generate: normalises and passes exactly the contract fields', async t => {
  let seen;
  supabase(t, { hsf_generate_file: a => { seen = a; return { file_id: FILE_ID, reference: 'CNC-HSF-2026-0923-001', items: 96 }; } });
  const res = await call({ method: 'POST', headers: AUTH, body: generateBody() });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { file_id: FILE_ID, reference: 'CNC-HSF-2026-0923-001', items: 96 });
  assert.deepEqual(seen, {
    p_auth_user: USER_ID,
    p: {
      industry_code: 'CONSTR',
      subindustry_code: 'CONSTR-CIVILS',
      triggers: ['T-CONSTR', 'T-HEIGHT', 'U', 'T-CONSTR-NOTIFY'],
      scope: {
        sites: [{ name: 'Main yard', address: '12 Example Road, Germiston' }, { name: 'Site 2' }],
        project_reference: 'PRJ 2026 14',
        headcount: 48,
      },
    },
  });
});

test('generate: a JSON string body, no subindustry and no triggers', async t => {
  let seen;
  supabase(t, { hsf_generate_file: a => { seen = a; return { file_id: FILE_ID, reference: 'CNC-HSF-2026-0923-002', items: 40 }; } });
  const body = JSON.stringify({ action: 'generate', industry_code: 'OFFICE', scope: { sites: [{ name: 'Head office' }], headcount: '12' } });
  const res = await call({ method: 'POST', headers: AUTH, body });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(seen.p, { industry_code: 'OFFICE', triggers: [], scope: { sites: [{ name: 'Head office' }], headcount: 12 } });
});

test('generate: strict validation refuses bad input with 400 before any database call', async t => {
  const calls = supabase(t, { hsf_generate_file: () => { throw new Error('must not be called'); } });
  const sites = n => Array.from({ length: n }, (_, i) => ({ name: `Site ${i + 1}` }));
  const cases = [
    { industry_code: '' },
    { industry_code: 'C' },
    { industry_code: 'CONSTR; drop' },
    { industry_code: 7 },
    { subindustry_code: 'CONSTR CIVILS' },
    { subindustry_code: 'X'.repeat(70) },
    { triggers: 'T-CONSTR' },
    { triggers: ['T_CONSTR'] },
    { triggers: ['t-constr'] },
    { triggers: ['X'] },
    { triggers: [12] },
    { triggers: Array.from({ length: 65 }, (_, i) => `T-X${i}`) },
    { scope: undefined },
    { scope: [] },
    { scope: { sites: [] } },
    { scope: { sites: 'Main yard' } },
    { scope: { sites: sites(101) } },
    { scope: { sites: [{ name: '' }] } },
    { scope: { sites: [{ name: 'x'.repeat(201) }] } },
    { scope: { sites: [{ name: 'Yard', address: 'a'.repeat(501) }] } },
    { scope: { sites: [null] } },
    { scope: { sites: [{ name: 'Supervisor 8001015009087' }] } },
    { scope: { sites: [{ name: 'Yard' }], project_reference: 'ID 8001015009087' } },
    { scope: { sites: [{ name: 'Yard\u0007' }] } },
    { scope: { sites: [{ name: 'Yard' }], headcount: -1 } },
    { scope: { sites: [{ name: 'Yard' }], headcount: 2.5 } },
    { scope: { sites: [{ name: 'Yard' }], headcount: 'many' } },
    { scope: { sites: [{ name: 'Yard' }], headcount: 1000001 } },
  ];
  for (const over of cases) {
    const body = generateBody(over);
    for (const [k, v] of Object.entries(over)) if (v === undefined) delete body[k];
    const res = await call({ method: 'POST', headers: AUTH, body });
    assert.equal(res.statusCode, 400, JSON.stringify(over).slice(0, 120));
    assert.equal(typeof res.body.error, 'string');
  }
  assert.equal(rpcCalls(calls).length, 0);
});

test('generate: a refusal from the database (for example no company account) is a 400 with its message', async t => {
  supabase(t, { hsf_generate_file: () => json(400, { code: 'P0001', message: 'Register your company before building a File.' }) });
  const res = await call({ method: 'POST', headers: AUTH, body: generateBody() });
  assert.equal(res.statusCode, 400);
  assert.deepEqual(res.body, { error: 'Register your company before building a File.', code: 'refused' });
});

test('set_status: not_applicable with a reason, and back to outstanding', async t => {
  const seen = [];
  supabase(t, { hsf_set_item_status: a => { seen.push(a); return { item_id: a.p_item_id, status: a.p_status }; } });
  const r1 = await call({ method: 'POST', headers: AUTH, body: { action: 'set_status', item_id: ITEM_ID, status: 'not_applicable', reason: '  No lifting machinery\non any site. ' } });
  assert.equal(r1.statusCode, 200);
  assert.deepEqual(r1.body, { item_id: ITEM_ID, status: 'not_applicable' });
  const r2 = await call({ method: 'POST', headers: AUTH, body: { action: 'set_status', item_id: ITEM_ID, status: 'outstanding' } });
  assert.equal(r2.statusCode, 200);
  assert.deepEqual(seen, [
    { p_auth_user: USER_ID, p_item_id: ITEM_ID, p_status: 'not_applicable', p_reason: 'No lifting machinery on any site.' },
    { p_auth_user: USER_ID, p_item_id: ITEM_ID, p_status: 'outstanding', p_reason: null },
  ]);
});

test('set_status: a missing or foreign item (SQLSTATE P0002) is a 404, never 400 refused', async t => {
  for (const status of [400, 404, 500]) {
    supabase(t, { hsf_set_item_status: () => json(status, { code: 'P0002', message: 'That File item was not found.' }) });
    const res = await call({ method: 'POST', headers: AUTH, body: { action: 'set_status', item_id: ITEM_ID, status: 'outstanding' } });
    assert.equal(res.statusCode, 404, `HTTP ${status}`);
    assert.deepEqual(res.body, { error: 'That File item was not found.', code: 'not_found' });
  }
});

test('set_status: a deliberate refusal (P0001) stays a 400 with its message', async t => {
  supabase(t, { hsf_set_item_status: () => json(400, { code: 'P0001', message: 'Evidence is already held for this item.' }) });
  const res = await call({ method: 'POST', headers: AUTH, body: { action: 'set_status', item_id: ITEM_ID, status: 'not_applicable', reason: 'No lifting machinery on any site.' } });
  assert.equal(res.statusCode, 400);
  assert.deepEqual(res.body, { error: 'Evidence is already held for this item.', code: 'refused' });
});

test('set_status: a void result still answers with the item and status', async t => {
  supabase(t, { hsf_set_item_status: () => null });
  const res = await call({ method: 'POST', headers: AUTH, body: { action: 'set_status', item_id: ITEM_ID, status: 'outstanding' } });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { item_id: ITEM_ID, status: 'outstanding' });
});

test('set_status: refuses bad input with 400 before any database call', async t => {
  const calls = supabase(t, { hsf_set_item_status: () => { throw new Error('must not be called'); } });
  const cases = [
    { item_id: 'x', status: 'outstanding' },
    { status: 'outstanding' },
    { item_id: ITEM_ID, status: 'uploaded' },
    { item_id: ITEM_ID, status: 'linked_mco' },
    { item_id: ITEM_ID, status: 'NOT_APPLICABLE', reason: 'No lifting machinery on site.' },
    { item_id: ITEM_ID, status: 'not_applicable' },
    { item_id: ITEM_ID, status: 'not_applicable', reason: 'too short' },
    { item_id: ITEM_ID, status: 'not_applicable', reason: 'x'.repeat(1001) },
    { item_id: ITEM_ID, status: 'not_applicable', reason: 42 },
    { item_id: ITEM_ID, status: 'not_applicable', reason: 'Employee 8001015009087 left' },
  ];
  for (const b of cases) {
    const res = await call({ method: 'POST', headers: AUTH, body: Object.assign({ action: 'set_status' }, b) });
    assert.equal(res.statusCode, 400, JSON.stringify(b).slice(0, 100));
  }
  assert.equal(rpcCalls(calls).length, 0);
});

test('unknown action and invalid JSON are 400; other methods are 405', async t => {
  const calls = supabase(t, {});
  for (const body of [{ action: 'release' }, { action: 'GENERATE' }, {}, '{"action":']) {
    const res = await call({ method: 'POST', headers: AUTH, body });
    assert.equal(res.statusCode, 400);
  }
  for (const method of ['PUT', 'DELETE']) {
    const res = await call({ method, headers: AUTH });
    assert.equal(res.statusCode, 405);
    assert.equal(res.headers.allow, 'GET, POST');
  }
  assert.equal(rpcCalls(calls).length, 0);
});

test('a database failure is a plain 500', async t => {
  supabase(t, { hsf_my_files: () => json(500, { code: 'XX000', message: `boom at fn (/srv/db.js:1:1) ${SERVICE_KEY}` }) });
  const res = await call({ headers: AUTH });
  assert.equal(res.statusCode, 500);
  assert.deepEqual(res.body, { error: 'The request could not be processed.', code: 'server_error' });
});
