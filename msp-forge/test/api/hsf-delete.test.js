// CNC HSF FORGE | tests for vercel/api/hsf-delete.js (node --test, global fetch mocked)
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const SUPABASE_URL = 'https://unit-test.supabase.invalid';
const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
process.env.SUPABASE_URL = SUPABASE_URL;
process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY;
const REAL_FETCH = globalThis.fetch;

const USER_ID = '6f1c2d3e-4a5b-4c6d-8e7f-9a0b1c2d3e4f';
const OTHER_ID = '7a1c2d3e-4a5b-4c6d-8e7f-9a0b1c2d3e4f';
const ACCOUNT_ID = '0b9a8c7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d';
const UP1 = '9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b';
const UP2 = '8e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b';
const REQ = '5d4c3b2a-1f0e-4d9c-8b7a-6f5e4d3c2b1a';
const EMAIL = 'safety@example.co.za';
const PHONE = '27821234567';
const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1bml0In0.c2lnbmF0dXJlLXVuaXQ';
const VERIFY_SESSION = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ2ZXJpZnkifQ.dmVyaWZ5LXNlc3Npb24';
const AUTH = { authorization: `Bearer ${TOKEN}` };
const PIN = '48213907';

const handler = require('../../vercel/api/hsf-delete');

const logged = [];
test.mock.method(console, 'error', (...a) => { logged.push(a.map(String).join(' ')); });
test.after(() => {
  for (const line of logged) {
    assert.ok(!line.includes(SERVICE_KEY), 'a log line carries the service role key');
    assert.ok(!line.includes(PIN), 'a log line carries the PIN');
  }
});

function json(status, body) {
  return new Response(body === undefined ? null : JSON.stringify(body), {
    status, headers: { 'content-type': 'application/json' },
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

// Recording that the PIN went out, and cancelling a request whose PIN did not,
// answer as the database does unless a test says otherwise.
const DEFAULT_RPC = {
  hsf_deletion_request_pin_sent: a => ({ request_id: a.p_request_id, pin_sent_at: '2026-09-23T08:00:01Z' }),
  hsf_deletion_request_cancel: a => ({ request_id: a.p_request_id, status: 'cancelled' }),
};

// A fake Supabase: Auth (user, admin user, otp, verify, logout), rpc functions and
// the hsf_deletion_request table read.
function supabase(t, o) {
  const opts = o || {};
  return installFetch(t, c => {
    if (c.url === `${SUPABASE_URL}/auth/v1/user`) {
      return c.headers.Authorization === `Bearer ${TOKEN}`
        ? json(200, { id: USER_ID, email: 'email' in opts ? opts.email : EMAIL })
        : json(401, { msg: 'invalid JWT' });
    }
    if (c.url === `${SUPABASE_URL}/auth/v1/admin/users/${USER_ID}`) {
      assert.equal(c.headers.apikey, SERVICE_KEY);
      assert.equal(c.headers.Authorization, `Bearer ${SERVICE_KEY}`);
      return opts.admin ? opts.admin(c) : json(200, { id: USER_ID, email: EMAIL, phone: PHONE, phone_confirmed_at: '2026-09-01T08:00:00Z' });
    }
    if (c.url === `${SUPABASE_URL}/auth/v1/otp`) {
      assert.equal(c.method, 'POST');
      assert.equal(c.headers.apikey, SERVICE_KEY);
      return opts.otp ? opts.otp(c) : json(200, {});
    }
    if (c.url === `${SUPABASE_URL}/auth/v1/verify`) {
      assert.equal(c.method, 'POST');
      assert.equal(c.headers.apikey, SERVICE_KEY);
      return opts.verify ? opts.verify(c) : json(200, { access_token: VERIFY_SESSION, user: { id: USER_ID } });
    }
    if (c.url === `${SUPABASE_URL}/auth/v1/logout?scope=local`) {
      assert.equal(c.headers.Authorization, `Bearer ${VERIFY_SESSION}`);
      return json(204);
    }
    const m = /^https:\/\/unit-test\.supabase\.invalid\/rest\/v1\/rpc\/([a-z0-9_]+)$/.exec(c.url);
    if (m) {
      assert.equal(c.headers.apikey, SERVICE_KEY);
      if (m[1] === 'hsf_link_account') return json(200, ACCOUNT_ID);
      const fn = (opts.rpc && opts.rpc[m[1]]) || DEFAULT_RPC[m[1]];
      if (!fn) throw new Error(`unexpected rpc ${m[1]}`);
      const out = fn(JSON.parse(c.body));
      return out instanceof Response ? out : json(200, out);
    }
    if (c.url.startsWith(`${SUPABASE_URL}/rest/v1/hsf_deletion_request?`)) {
      assert.equal(c.headers.apikey, SERVICE_KEY);
      return json(200, opts.table ? opts.table(c) : [{ id: REQ, channel: 'email' }]);
    }
    throw new Error(`unexpected fetch ${c.method} ${c.url}`);
  });
}

function mockRes() {
  const res = { statusCode: 200, headers: {}, body: undefined };
  res.setHeader = (k, v) => { res.headers[String(k).toLowerCase()] = v; };
  res.status = c => { res.statusCode = c; return res; };
  res.json = o => { res.body = o; return res; };
  res.end = () => res;
  return res;
}

async function call({ method = 'POST', headers = AUTH, body } = {}) {
  const res = mockRes();
  await handler({ method, headers, query: {}, body }, res);
  const s = JSON.stringify(res.body === undefined ? null : res.body);
  assert.ok(!s.includes(SERVICE_KEY), 'response carries the service role key');
  assert.ok(!s.includes(PIN), 'response echoes the PIN');
  assert.ok(!s.includes(VERIFY_SESSION), 'response carries the verification session');
  assert.equal(res.headers['cache-control'], 'no-store');
  return res;
}

const created = { request_id: REQ, expires_at: '2026-09-23T08:10:00Z', channel: 'email', destination_hint: 's***@example.co.za' };
const requestBody = over => Object.assign({ action: 'request', upload_ids: [UP1, UP2.toUpperCase(), UP1], channel: 'email', acknowledged: true }, over || {});
const confirmBody = over => Object.assign({ action: 'confirm', request_id: REQ, pin: PIN }, over || {});
const LINK = '/rest/v1/rpc/hsf_link_account';
const handlerCalls = calls => calls.filter(c => c.url !== `${SUPABASE_URL}/auth/v1/user` && !c.url.endsWith(LINK));

test('401 without a token, 405 for other methods, and nothing is called', async t => {
  const calls = supabase(t, {});
  assert.equal((await call({ headers: {}, body: requestBody() })).statusCode, 401);
  for (const method of ['GET', 'PUT', 'DELETE']) {
    const res = await call({ method });
    assert.equal(res.statusCode, 405);
    assert.equal(res.headers.allow, 'POST');
  }
  assert.equal(calls.length, 0);
});

test('request: creates the request, then asks Supabase Auth to email a PIN to the signed in address', async t => {
  let args;
  const calls = supabase(t, { rpc: { hsf_deletion_request_create: a => { args = a; return created; } } });
  const res = await call({ body: requestBody() });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, created);
  assert.deepEqual(args, { p_auth_user: USER_ID, p_upload_ids: [UP1, UP2], p_channel: 'email', p_acknowledged: true });
  const own = handlerCalls(calls);
  assert.deepEqual(own.map(c => c.url.replace(SUPABASE_URL, '')),
    ['/rest/v1/rpc/hsf_deletion_request_create', '/auth/v1/otp', '/rest/v1/rpc/hsf_deletion_request_pin_sent']);
  assert.deepEqual(JSON.parse(own[1].body), { email: EMAIL, create_user: false });
  assert.deepEqual(JSON.parse(own[2].body), { p_auth_user: USER_ID, p_request_id: REQ });
});

test('request: SMS reads the confirmed phone with the admin API and sends the PIN to it', async t => {
  const calls = supabase(t, { rpc: { hsf_deletion_request_create: () => Object.assign({}, created, { channel: 'sms', destination_hint: 'number ending 4567' }) } });
  const res = await call({ body: requestBody({ channel: 'sms' }) });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.channel, 'sms');
  const otp = calls.find(c => c.url.endsWith('/auth/v1/otp'));
  assert.deepEqual(JSON.parse(otp.body), { phone: PHONE, create_user: false });
});

test('request: SMS with no confirmed phone on the auth user is refused and no PIN is sent', async t => {
  const calls = supabase(t, {
    rpc: { hsf_deletion_request_create: () => Object.assign({}, created, { channel: 'sms' }) },
    admin: () => json(200, { id: USER_ID, phone: PHONE, phone_confirmed_at: null }),
  });
  const res = await call({ body: requestBody({ channel: 'sms' }) });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /Choose email/);
  assert.equal(calls.filter(c => c.url.endsWith('/auth/v1/otp')).length, 0);
  assert.equal(calls.filter(c => c.url.endsWith('/rpc/hsf_deletion_request_cancel')).length, 1);
  assert.equal(calls.filter(c => c.url.endsWith('/rpc/hsf_deletion_request_pin_sent')).length, 0);
});

test('request: bad input is 400 before any database call', async t => {
  const calls = supabase(t, {});
  const bad = [
    { upload_ids: [] }, { upload_ids: 'x' }, { upload_ids: ['nope'] },
    { upload_ids: Array.from({ length: 51 }, () => UP1) },
    { channel: 'whatsapp' }, { channel: undefined },
    { acknowledged: false }, { acknowledged: 'true' }, { acknowledged: undefined },
  ];
  for (const over of bad) {
    const res = await call({ body: requestBody(over) });
    assert.equal(res.statusCode, 400, JSON.stringify(over).slice(0, 60));
  }
  assert.equal(handlerCalls(calls).length, 0);
});

test('request: the database rate limit (PT429) is 429 in its own words, and no PIN is sent', async t => {
  const calls = supabase(t, { rpc: { hsf_deletion_request_create: () => json(429, { code: 'PT429', message: 'Too many deletion requests in the last hour. Please try again later.' }) } });
  const res = await call({ body: requestBody() });
  assert.equal(res.statusCode, 429);
  assert.deepEqual(res.body, { error: 'Too many deletion requests in the last hour. Please try again later.', code: 'rate_limited' });
  assert.equal(calls.filter(c => c.url.endsWith('/auth/v1/otp')).length, 0);
});

test('request: a document that has moved to MyClinicOnline is refused in plain words', async t => {
  const message = 'One or more of the chosen documents cannot be deleted here. A document that has moved to MyClinicOnline is deleted through MyClinicOnline.';
  supabase(t, { rpc: { hsf_deletion_request_create: () => json(400, { code: 'P0001', message }) } });
  const res = await call({ body: requestBody() });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, message);
});

test('request: Supabase Auth 429 on sending is 429; any other failure is 502', async t => {
  supabase(t, { rpc: { hsf_deletion_request_create: () => created }, otp: () => json(429, { msg: 'over_email_send_rate_limit' }) });
  assert.equal((await call({ body: requestBody() })).statusCode, 429);
  supabase(t, { rpc: { hsf_deletion_request_create: () => created }, otp: () => json(500, { msg: 'smtp down' }) });
  const res = await call({ body: requestBody() });
  assert.equal(res.statusCode, 502);
  assert.match(res.body.error, /PIN could not be sent/);
});

test('request: when the PIN cannot be sent the new request is cancelled, never recorded as sent, and no request id is returned', async t => {
  for (const otp of [() => json(429, { msg: 'over_email_send_rate_limit' }), () => json(502, {}), () => { throw new Error('network down'); }]) {
    let cancelled = null;
    const calls = supabase(t, {
      rpc: { hsf_deletion_request_create: () => created, hsf_deletion_request_cancel: a => { cancelled = a; return { request_id: REQ, status: 'cancelled' }; } },
      otp,
    });
    const res = await call({ body: requestBody() });
    assert.ok([429, 502].includes(res.statusCode));
    assert.equal(res.body.request_id, undefined);
    assert.deepEqual(cancelled, { p_auth_user: USER_ID, p_request_id: REQ });
    assert.equal(calls.filter(c => c.url.endsWith('/rpc/hsf_deletion_request_pin_sent')).length, 0);
  }
  // A cancel that fails too still answers the send failure, not a success.
  supabase(t, {
    rpc: { hsf_deletion_request_create: () => created, hsf_deletion_request_cancel: () => json(500, { message: 'down' }) },
    otp: () => json(502, {}),
  });
  assert.equal((await call({ body: requestBody() })).statusCode, 502);
});

test('request: a PIN sent but not recorded as sent is 502, so the request cannot be used', async t => {
  supabase(t, { rpc: { hsf_deletion_request_create: () => created, hsf_deletion_request_pin_sent: () => json(500, { message: 'down' }) } });
  const res = await call({ body: requestBody() });
  assert.equal(res.statusCode, 502);
  assert.equal(res.body.request_id, undefined);
});

test('confirm: counts the attempt, verifies the PIN with Supabase Auth, closes that session, then deletes', async t => {
  const seen = [];
  const calls = supabase(t, {
    rpc: {
      hsf_deletion_request_attempt: a => { seen.push(['attempt', a]); return { allowed: true, attempts_left: 4, status: 'pending' }; },
      hsf_deletion_request_confirm: a => { seen.push(['confirm', a]); return { request_id: REQ, status: 'confirmed', deleted: 2, upload_ids: [UP1, UP2] }; },
    },
  });
  const res = await call({ body: confirmBody({ pin: ' 4821 3907 ' }) });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { request_id: REQ, status: 'confirmed', deleted: 2, upload_ids: [UP1, UP2] });
  assert.deepEqual(seen, [['attempt', { p_auth_user: USER_ID, p_request_id: REQ }], ['confirm', { p_auth_user: USER_ID, p_request_id: REQ }]]);
  const own = handlerCalls(calls).map(c => c.url.replace(SUPABASE_URL, '').split('?')[0]);
  assert.deepEqual(own, ['/rest/v1/hsf_deletion_request', '/rest/v1/rpc/hsf_deletion_request_attempt', '/auth/v1/verify', '/auth/v1/logout', '/rest/v1/rpc/hsf_deletion_request_confirm']);
  const read = calls.find(c => c.url.includes('/rest/v1/hsf_deletion_request?'));
  assert.ok(read.url.includes(`id=eq.${REQ}`) && read.url.includes(`auth_user_id=eq.${USER_ID}`), 'only the caller\'s own request is read');
  const verify = calls.find(c => c.url.endsWith('/auth/v1/verify'));
  assert.deepEqual(JSON.parse(verify.body), { type: 'email', email: EMAIL, token: PIN });
});

test('confirm: an SMS request verifies with type sms and the phone', async t => {
  const calls = supabase(t, {
    table: () => [{ id: REQ, channel: 'sms' }],
    rpc: {
      hsf_deletion_request_attempt: () => ({ allowed: true, attempts_left: 4, status: 'pending' }),
      hsf_deletion_request_confirm: () => ({ request_id: REQ, status: 'confirmed', deleted: 1, upload_ids: [UP1] }),
    },
  });
  const res = await call({ body: confirmBody() });
  assert.equal(res.statusCode, 200);
  const verify = calls.find(c => c.url.endsWith('/auth/v1/verify'));
  assert.deepEqual(JSON.parse(verify.body), { type: 'sms', phone: PHONE, token: PIN });
});

test('confirm: a wrong PIN is 400 with attempts left, the same answer however close it was, and nothing is deleted', async t => {
  for (const reply of [json(403, { msg: 'Token has expired or is invalid', code: 'otp_expired' }), json(400, { msg: 'bad' }), json(422, {})]) {
    const calls = supabase(t, {
      rpc: { hsf_deletion_request_attempt: () => ({ allowed: true, attempts_left: 3, status: 'pending' }) },
      verify: () => reply,
    });
    const res = await call({ body: confirmBody() });
    assert.equal(res.statusCode, 400);
    assert.deepEqual(res.body, { error: 'That PIN is not correct or has expired.', code: 'pin_incorrect', attempts_left: 3 });
    assert.equal(calls.filter(c => c.url.includes('hsf_deletion_request_confirm')).length, 0);
  }
});

test('confirm: a PIN verified for another user is a fail, and nothing is deleted', async t => {
  const calls = supabase(t, {
    rpc: { hsf_deletion_request_attempt: () => ({ allowed: true, attempts_left: 2, status: 'pending' }) },
    verify: () => json(200, { access_token: VERIFY_SESSION, user: { id: OTHER_ID } }),
  });
  const res = await call({ body: confirmBody() });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.code, 'pin_incorrect');
  assert.equal(calls.filter(c => c.url.includes('hsf_deletion_request_confirm')).length, 0);
});

test('confirm: a locked request is 429, an expired one 409, and Supabase Auth is not asked', async t => {
  for (const [status, code, http] of [['locked', 'request_locked', 429], ['expired', 'request_expired', 409], ['cancelled', 'request_closed', 409]]) {
    const calls = supabase(t, { rpc: { hsf_deletion_request_attempt: () => ({ allowed: false, attempts_left: 0, status }) } });
    const res = await call({ body: confirmBody() });
    assert.equal(res.statusCode, http);
    assert.equal(res.body.code, code);
    assert.match(res.body.error, /Start again to receive a new PIN\./);
    assert.equal(calls.filter(c => c.url.includes('/auth/v1/verify')).length, 0);
  }
});

test('confirm: too many attempts on the account is 429, a request whose PIN was never sent is closed, and Supabase Auth is not asked', async t => {
  for (const [status, code, http] of [['rate_limited', 'rate_limited', 429], ['pin_not_sent', 'request_closed', 409]]) {
    const calls = supabase(t, { rpc: { hsf_deletion_request_attempt: () => ({ allowed: false, attempts_left: 5, status }) } });
    const res = await call({ body: confirmBody() });
    assert.equal(res.statusCode, http);
    assert.equal(res.body.code, code);
    assert.equal(calls.filter(c => c.url.includes('/auth/v1/verify')).length, 0);
    assert.equal(calls.filter(c => c.url.includes('hsf_deletion_request_confirm')).length, 0);
  }
});

test('confirm: Supabase Auth 429 on checking is 429; an outage is 502', async t => {
  supabase(t, { rpc: { hsf_deletion_request_attempt: () => ({ allowed: true, attempts_left: 4, status: 'pending' }) }, verify: () => json(429, {}) });
  assert.equal((await call({ body: confirmBody() })).statusCode, 429);
  supabase(t, { rpc: { hsf_deletion_request_attempt: () => ({ allowed: true, attempts_left: 4, status: 'pending' }) }, verify: () => json(503, {}) });
  assert.equal((await call({ body: confirmBody() })).statusCode, 502);
});

test('confirm: a PIN that is not 6 to 10 digits is 400 and no attempt is used', async t => {
  const calls = supabase(t, {});
  for (const pin of ['12345', '12345678901', 'abcdef', '', 123456, null, '12 34']) {
    const res = await call({ body: confirmBody({ pin }) });
    assert.equal(res.statusCode, 400, String(pin));
    assert.equal(res.body.code, 'bad_pin');
  }
  assert.equal(handlerCalls(calls).length, 0);
});

test('confirm: a request of another person, or none, is 404 and no attempt is used', async t => {
  const calls = supabase(t, { table: () => [] });
  const res = await call({ body: confirmBody() });
  assert.equal(res.statusCode, 404);
  assert.equal(calls.filter(c => c.url.includes('/rpc/hsf_deletion_request')).length, 0);
  const bad = await call({ body: confirmBody({ request_id: 'nope' }) });
  assert.equal(bad.statusCode, 400);
});

test('confirm: a document that can no longer be deleted is refused in plain words after the PIN', async t => {
  const message = 'One or more of the chosen documents can no longer be deleted here. Start again.';
  supabase(t, {
    rpc: {
      hsf_deletion_request_attempt: () => ({ allowed: true, attempts_left: 4, status: 'pending' }),
      hsf_deletion_request_confirm: () => json(400, { code: 'P0001', message }),
    },
  });
  const res = await call({ body: confirmBody() });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, message);
});

test('unknown action is 400', async t => {
  supabase(t, {});
  for (const body of [{}, { action: 'delete' }, { action: ['request'] }]) {
    assert.equal((await call({ body })).statusCode, 400);
  }
});
