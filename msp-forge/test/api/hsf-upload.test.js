// CNC HSF FORGE | tests for vercel/api/hsf-upload.js (node --test, global fetch mocked)
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
const UPLOAD_ID = '9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b';
const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1bml0In0.c2lnbmF0dXJlLXVuaXQ';
const AUTH = { authorization: `Bearer ${TOKEN}` };
const SHA = 'ab'.repeat(32);
const SAFE_NAME = 'Risk_assessment_2026.pdf';
const PATH = `${ACCOUNT_ID}/${UPLOAD_ID}/${SAFE_NAME}`;
const SIGN_TOKEN = 'signed-upload-token.abc';

const handler = require('../../vercel/api/hsf-upload');

const logged = [];
test.mock.method(console, 'error', (...a) => { logged.push(a.map(String).join(' ')); });
test.after(() => {
  for (const line of logged) assert.ok(!line.includes(SERVICE_KEY), 'a log line carries the service role key');
});

function json(status, body, headers) {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status, headers: Object.assign({ 'content-type': 'application/json' }, headers || {}),
  });
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

function assertService(c) {
  assert.equal(c.headers.apikey, SERVICE_KEY);
  assert.equal(c.headers.Authorization, `Bearer ${SERVICE_KEY}`);
}

// A fake Supabase: Auth, rpc functions, the hsf_upload table read and Storage.
function supabase(t, o) {
  const opts = o || {};
  return installFetch(t, c => {
    if (c.url === `${SUPABASE_URL}/auth/v1/user`) {
      return c.headers.Authorization === `Bearer ${TOKEN}`
        ? json(200, { id: USER_ID, email: 'safety@example.co.za' })
        : json(401, { msg: 'invalid JWT' });
    }
    const m = /^https:\/\/unit-test\.supabase\.invalid\/rest\/v1\/rpc\/([a-z0-9_]+)$/.exec(c.url);
    if (m) {
      assertService(c);
      const fn = opts.rpc && opts.rpc[m[1]];
      if (!fn) throw new Error(`unexpected rpc ${m[1]}`);
      const out = fn(JSON.parse(c.body));
      return out instanceof Response ? out : json(200, out);
    }
    if (c.url.startsWith(`${SUPABASE_URL}/rest/v1/hsf_upload?`)) {
      assertService(c);
      if (!opts.table) throw new Error('unexpected table read');
      return json(200, opts.table(c));
    }
    if (c.url.startsWith(`${SUPABASE_URL}/storage/v1/object/upload/sign/`)) {
      assertService(c);
      if (!opts.sign) throw new Error('unexpected sign call');
      return opts.sign(c);
    }
    if (c.url.startsWith(`${SUPABASE_URL}/storage/v1/object/`)) {
      assertService(c);
      if (!opts.head) throw new Error('unexpected storage call');
      return opts.head(c);
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

function registerBody(over) {
  return Object.assign({
    action: 'register',
    file_id: FILE_ID,
    section_code: 'C',
    element_code: 'HSF-C-01',
    department_code: 'SHE',
    original_name: '  Risk assessment 2026.pdf ',
    mime_type: 'Application/PDF',
    size_bytes: 482113,
    sha256: SHA.toUpperCase(),
  }, over || {});
}

const registered = { upload_id: UPLOAD_ID, bucket: 'hsf-staging', path: PATH };
const signOk = () => json(200, { url: `/object/upload/sign/hsf-staging/${PATH}?token=${SIGN_TOKEN}` });
const byKind = (calls, part) => calls.filter(c => c.url.includes(part));

test('401 without a token for GET and POST, and no call at all', async t => {
  const calls = supabase(t, {});
  assert.equal((await call({})).statusCode, 401);
  assert.equal((await call({ method: 'POST', body: registerBody() })).statusCode, 401);
  assert.equal((await call({ method: 'POST', body: { action: 'complete', upload_id: UPLOAD_ID } })).statusCode, 401);
  assert.equal(calls.length, 0);
});

test('register: validates, registers, then signs an upload URL in hsf-staging with the service role', async t => {
  let regArgs;
  const calls = supabase(t, {
    rpc: { hsf_register_upload: a => { regArgs = a; return registered; } },
    sign: signOk,
  });
  const res = await call({ method: 'POST', headers: AUTH, body: registerBody() });
  assert.equal(res.statusCode, 200);

  // The database receives only the validated, normalised fields.
  assert.deepEqual(regArgs, {
    p_auth_user: USER_ID,
    p: {
      department_code: 'SHE',
      section_code: 'C',
      file_id: FILE_ID,
      element_code: 'HSF-C-01',
      original_name: 'Risk assessment 2026.pdf',
      mime_type: 'application/pdf',
      size_bytes: 482113,
      sha256: SHA,
    },
  });

  // The signed upload URL call shape.
  const sign = byKind(calls, '/storage/v1/object/upload/sign/');
  assert.equal(sign.length, 1);
  assert.equal(sign[0].url, `${SUPABASE_URL}/storage/v1/object/upload/sign/hsf-staging/${ACCOUNT_ID}/${UPLOAD_ID}/${SAFE_NAME}`);
  assert.equal(sign[0].method, 'POST');
  assert.equal(sign[0].headers['Content-Type'], 'application/json');
  assert.equal(sign[0].headers['x-upsert'], undefined, 'an upload must never overwrite an object');
  assert.equal(sign[0].body, '{}');

  // Order: auth, register, sign.
  assert.deepEqual(calls.map(c => c.url.replace(SUPABASE_URL, '').split('?')[0].split('/').slice(0, 4).join('/')),
    ['/auth/v1/user', '/rest/v1/rpc', '/storage/v1/object']);

  assert.deepEqual(res.body, {
    upload_id: UPLOAD_ID,
    upload_url: `${SUPABASE_URL}/storage/v1/object/upload/sign/hsf-staging/${PATH}?token=${SIGN_TOKEN}`,
  });
});

test('register: accepts a JSON string body and optional fields left out', async t => {
  let regArgs;
  supabase(t, { rpc: { hsf_register_upload: a => { regArgs = a; return registered; } }, sign: signOk });
  const body = JSON.stringify({ action: 'register', department_code: 'HR', original_name: 'Policy.docx', mime_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', size_bytes: 1024, sha256: SHA });
  const res = await call({ method: 'POST', headers: AUTH, body });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(Object.keys(regArgs.p).sort(), ['department_code', 'mime_type', 'original_name', 'sha256', 'size_bytes']);
});

test('register: strict validation refuses bad input with 400 before any database call', async t => {
  const calls = supabase(t, { rpc: { hsf_register_upload: () => { throw new Error('must not be called'); } } });
  const cases = [
    { department_code: undefined },
    { department_code: 'she' },
    { department_code: 'S' },
    { department_code: ['SHE'] },
    { section_code: 'P' },
    { section_code: 'AB' },
    { file_id: 'not-a-uuid' },
    { file_id: `${FILE_ID}x` },
    { element_code: 'HSF-C-01; drop table' },
    { element_code: 'X-C-01' },
    { element_code: 'HSF-C-01', file_id: undefined },
    { original_name: '' },
    { original_name: '   ' },
    { original_name: 'a'.repeat(256) },
    { original_name: 'bad\u0000name.pdf' },
    { original_name: 'line\nbreak.pdf' },
    { original_name: 42 },
    { mime_type: '' },
    { mime_type: 'pdf' },
    { mime_type: 'application/pdf; charset=binary' },
    { mime_type: 'text/html<script>' },
    { size_bytes: 0 },
    { size_bytes: -1 },
    { size_bytes: 1.5 },
    { size_bytes: '482113' },
    { size_bytes: Number.MAX_SAFE_INTEGER + 2 },
    { sha256: 'ab'.repeat(31) },
    { sha256: 'zz'.repeat(32) },
    { sha256: `${SHA}00` },
    { sha256: undefined },
  ];
  for (const over of cases) {
    const body = registerBody(over);
    for (const [k, v] of Object.entries(over)) if (v === undefined) delete body[k];
    const res = await call({ method: 'POST', headers: AUTH, body });
    assert.equal(res.statusCode, 400, JSON.stringify(over));
    assert.equal(typeof res.body.error, 'string');
  }
  assert.equal(byKind(calls, '/rest/v1/').length, 0);
  assert.equal(byKind(calls, '/storage/').length, 0);
});

test('register: a database refusal (no consent, wrong type or size) is a 400 and nothing is signed', async t => {
  const calls = supabase(t, {
    rpc: { hsf_register_upload: () => json(400, { code: 'P0001', message: 'All three consents are needed before a document can be stored.' }) },
    sign: () => { throw new Error('must not be called'); },
  });
  const res = await call({ method: 'POST', headers: AUTH, body: registerBody() });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'All three consents are needed before a document can be stored.');
  assert.equal(byKind(calls, '/storage/').length, 0);
});

test('register: an unexpected register result (wrong bucket or unsafe path) is refused before signing', async t => {
  for (const bad of [
    { upload_id: UPLOAD_ID, bucket: 'public-bucket', path: PATH },
    { upload_id: UPLOAD_ID, bucket: 'hsf-staging', path: `${ACCOUNT_ID}/../${UPLOAD_ID}/x.pdf` },
    { upload_id: UPLOAD_ID, bucket: 'hsf-staging', path: `${ACCOUNT_ID}/other/x.pdf` },
    { upload_id: 'nope', bucket: 'hsf-staging', path: PATH },
    null,
  ]) {
    const calls = supabase(t, { rpc: { hsf_register_upload: () => bad }, sign: () => { throw new Error('must not be called'); } });
    const res = await call({ method: 'POST', headers: AUTH, body: registerBody() });
    assert.equal(res.statusCode, 502, JSON.stringify(bad));
    assert.equal(byKind(calls, '/storage/').length, 0);
  }
});

test('register: a Storage failure or odd sign response is a plain 502', async t => {
  for (const sign of [
    () => json(400, { statusCode: '400', error: 'Bucket not found', message: `detail ${SERVICE_KEY}` }),
    () => json(200, { url: 'https://elsewhere.example/upload?token=x' }),
    () => json(200, { url: `/object/upload/sign/hsf-staging/${PATH}` }),
    () => json(200, {}),
    () => { throw new TypeError('fetch failed'); },
  ]) {
    supabase(t, { rpc: { hsf_register_upload: () => registered }, sign });
    const res = await call({ method: 'POST', headers: AUTH, body: registerBody() });
    assert.equal(res.statusCode, 502);
    assert.equal(res.body.code, 'upstream_error');
    assert.ok(!('upload_url' in res.body));
  }
});

test('complete: checks the object is in hsf-staging at the registered size, then marks it uploaded', async t => {
  let markArgs;
  const calls = supabase(t, {
    table: () => [{ id: UPLOAD_ID, status: 'awaiting_upload', storage_bucket: 'hsf-staging', storage_path: PATH, size_bytes: 482113 }],
    head: () => new Response(null, { status: 200, headers: { 'content-length': '482113' } }),
    rpc: { hsf_mark_uploaded: a => { markArgs = a; return { upload_id: UPLOAD_ID, status: 'uploaded' }; } },
  });
  const res = await call({ method: 'POST', headers: AUTH, body: { action: 'complete', upload_id: UPLOAD_ID.toUpperCase() } });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { upload_id: UPLOAD_ID, status: 'uploaded' });
  assert.deepEqual(markArgs, { p_auth_user: USER_ID, p_upload_id: UPLOAD_ID });

  const read = byKind(calls, '/rest/v1/hsf_upload?')[0];
  assert.ok(read.url.includes(`id=eq.${UPLOAD_ID}`));
  assert.ok(read.url.includes(`auth_user_id=eq.${USER_ID}`), 'the lookup is scoped to the signed in user');
  const head = byKind(calls, '/storage/v1/object/hsf-staging/')[0];
  assert.equal(head.method, 'HEAD');
  assert.equal(head.url, `${SUPABASE_URL}/storage/v1/object/hsf-staging/${PATH}`);
});

test('complete: nothing in the bucket, or a different size, is a 409 and nothing is marked', async t => {
  for (const [head, code] of [
    [() => json(400, { statusCode: '404', error: 'not_found' }), 'not_arrived'],
    [() => json(404, {}), 'not_arrived'],
    [() => new Response(null, { status: 200, headers: { 'content-length': '10' } }), 'size_mismatch'],
  ]) {
    const calls = supabase(t, {
      table: () => [{ id: UPLOAD_ID, status: 'awaiting_upload', storage_bucket: 'hsf-staging', storage_path: PATH, size_bytes: 482113 }],
      head,
      rpc: { hsf_mark_uploaded: () => { throw new Error('must not be called'); } },
    });
    const res = await call({ method: 'POST', headers: AUTH, body: { action: 'complete', upload_id: UPLOAD_ID } });
    assert.equal(res.statusCode, 409);
    assert.equal(res.body.code, code);
    assert.equal(byKind(calls, '/rpc/').length, 0);
  }
});

test('complete: an upload of someone else, or unknown, is 404; one already past awaiting_upload is returned as it stands', async t => {
  supabase(t, { table: () => [] });
  const r1 = await call({ method: 'POST', headers: AUTH, body: { action: 'complete', upload_id: UPLOAD_ID } });
  assert.equal(r1.statusCode, 404);

  const calls = supabase(t, { table: () => [{ id: UPLOAD_ID, status: 'transferred', storage_bucket: 'hsf-staging', storage_path: null, size_bytes: 5 }] });
  const r2 = await call({ method: 'POST', headers: AUTH, body: { action: 'complete', upload_id: UPLOAD_ID } });
  assert.equal(r2.statusCode, 200);
  assert.deepEqual(r2.body, { upload_id: UPLOAD_ID, status: 'transferred' });
  assert.equal(byKind(calls, '/storage/').length, 0);
  assert.equal(byKind(calls, '/rpc/').length, 0);
});

test('complete: a bad upload_id is 400 with no database call', async t => {
  const calls = supabase(t, {});
  for (const upload_id of [undefined, '', 'x', 123, `${UPLOAD_ID}'--`]) {
    const res = await call({ method: 'POST', headers: AUTH, body: { action: 'complete', upload_id } });
    assert.equal(res.statusCode, 400);
  }
  assert.equal(byKind(calls, '/rest/').length, 0);
});

test('GET lists my uploads, optionally for one File', async t => {
  const seen = [];
  const row = { upload_id: UPLOAD_ID, original_name: 'Risk assessment 2026.pdf', department_code: 'SHE', section_code: 'C', element_code: 'HSF-C-01', size_bytes: 482113, status: 'held', created_at: '2026-09-23T08:00:00Z', transferred_at: null, staging_deleted_at: null, mco_document_ref: null };
  supabase(t, { rpc: { hsf_my_uploads: a => { seen.push(a); return a.p_file_id ? [row] : null; } } });
  const r1 = await call({ headers: AUTH, query: { file_id: FILE_ID } });
  assert.equal(r1.statusCode, 200);
  assert.deepEqual(r1.body, [row]);
  const r2 = await call({ headers: AUTH });
  assert.deepEqual(r2.body, []);
  assert.deepEqual(seen, [{ p_auth_user: USER_ID, p_file_id: FILE_ID }, { p_auth_user: USER_ID, p_file_id: null }]);
});

test('GET with a bad or repeated file_id is 400', async t => {
  const calls = supabase(t, {});
  for (const file_id of ['nope', [FILE_ID, FILE_ID]]) {
    const res = await call({ headers: AUTH, query: { file_id } });
    assert.equal(res.statusCode, 400);
  }
  assert.equal(byKind(calls, '/rest/').length, 0);
});

test('unknown action is 400; other methods are 405', async t => {
  const calls = supabase(t, {});
  for (const body of [{ action: 'delete', upload_id: UPLOAD_ID }, {}, { action: ['register'] }]) {
    const res = await call({ method: 'POST', headers: AUTH, body });
    assert.equal(res.statusCode, 400);
  }
  for (const method of ['PUT', 'DELETE', 'PATCH']) {
    const res = await call({ method, headers: AUTH });
    assert.equal(res.statusCode, 405);
    assert.equal(res.headers.allow, 'GET, POST');
  }
  assert.equal(byKind(calls, '/rest/').length, 0);
});
