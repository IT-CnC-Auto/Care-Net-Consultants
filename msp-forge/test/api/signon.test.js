// CNC MSP FORGE | tests for vercel/api/signon.js (node --test, global fetch mocked)
// Review finding REG-1 (24/09/2026): an account that already exists is answered
// only to its own signed in contact. Anyone else who posts its email gets a
// neutral { status: 'received' }: no reference, company name, contact number,
// account kind or assessment link, and msp_client_signon is never called for it.
// v1.5.0 (24/09/2026, build contract section 15): a body with source 'hsf' (the
// Health and Safety File builder) registers through hsf_client_register, never
// msp_client_signon, and is never answered with a token or an assessment link;
// if hsf_client_register is not in the database yet the answer is 503 and
// msp_client_signon is still not called. Without source, the Plan path is as it
// was. The builder sends source 'hsf', and its tick box no longer claims more
// than a File only registration does. Review finding REG-R3: source 'hsf' is
// answered only to its own confirmed, signed in contact; anyone else gets 401
// and no account is looked up or made.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const SUPABASE_URL = 'https://unit-test.supabase.invalid';
const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
process.env.SUPABASE_URL = SUPABASE_URL;
process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY;
const REAL_FETCH = globalThis.fetch;

const handler = require('../../vercel/api/signon');

const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1bml0In0.c2lnbmF0dXJlLXVuaXQ';
const LIVE_TOKEN = 'live-assessment-token-of-the-owner';
const OWNER = 'thandi@fictitious.test';

test.mock.method(console, 'error', () => {});

function json(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

/* Supabase answers: `user` for GET /auth/v1/user (null: 401), `found` for
   msp_company_lookup, `signon` for msp_client_signon, `register` for
   hsf_client_register (the string 'missing': PostgREST's answer for a function
   that is not in the database, as before migration 056 is applied). */
const MISSING_FN = { code: 'PGRST202', details: 'Searched for the function public.hsf_client_register with parameter p or with a single unnamed json/jsonb parameter, but no matches were found in the schema cache.',
  hint: null, message: 'Could not find the function public.hsf_client_register(p) in the schema cache' };
function installFetch(t, { user = null, found = false, signon = null, register = null } = {}) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    const u = String(url);
    const i = init || {};
    calls.push({ url: u, body: i.body ? JSON.parse(i.body) : null, headers: Object.assign({}, i.headers) });
    if (u === SUPABASE_URL + '/auth/v1/user') return user ? json(200, user) : json(401, { msg: 'invalid token' });
    if (u === SUPABASE_URL + '/rest/v1/rpc/msp_company_lookup') return json(200, found ? { found: true, company_name: 'Fictitious Test Co' } : { found: false });
    if (u === SUPABASE_URL + '/rest/v1/rpc/msp_client_signon') {
      return json(200, signon || { status: 'received', reference: '6f1c2a0e-0000-4000-8000-000000000001', existing: false,
        company_name: 'New Co (fictitious)', contact_number: null, account_kind: 'client', declined: false, token: 'fresh-token' });
    }
    if (u === SUPABASE_URL + '/rest/v1/rpc/hsf_client_register') {
      if (register === 'missing') return json(404, MISSING_FN);
      return json(200, register || { status: 'received', reference: '6f1c2a0e-0000-4000-8000-000000000002', existing: false,
        company_name: 'New File Co (fictitious)', contact_number: null, declined: false });
    }
    throw new Error('unexpected fetch ' + u);
  };
  t.after(() => { globalThis.fetch = REAL_FETCH; });
  return calls;
}

function req(body, headers) {
  return { method: 'POST', body, headers: Object.assign({ host: 'unit.test', 'x-forwarded-proto': 'https' }, headers || {}) };
}
function mockRes() {
  const res = { statusCode: 200, body: undefined };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (o) => { res.body = o; return res; };
  return res;
}
const BODY = { company_name: 'Someone Else (Pty) Ltd', contact_name: 'Mallory', contact_email: 'Thandi@Fictitious.test' };
const EXISTING = { status: 'received', reference: '0b9a8c7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d', existing: true,
  company_name: 'Fictitious Test Co', contact_number: '010 000 0000', account_kind: 'client', declined: false, token: LIVE_TOKEN };
const signonCalls = (calls) => calls.filter((c) => c.url.endsWith('/rpc/msp_client_signon'));
const registerCalls = (calls) => calls.filter((c) => c.url.endsWith('/rpc/hsf_client_register'));
const FILE_BODY = Object.assign({}, BODY, { source: 'hsf', notes: 'Registered from the Health and Safety File builder' });
const OWNER_USER = { id: 'u1', email: OWNER, email_confirmed_at: '2026-09-24T08:00:00Z' };
/* Nothing of the Plan in an answer: no token, no account kind, no assessment link. */
function assertNoPlan(body) {
  for (const k of ['token', 'assessment_url', 'account_kind']) assert.ok(!(k in body), k + ' must not be in the answer');
  const text = JSON.stringify(body);
  assert.ok(!text.includes(LIVE_TOKEN) && !text.includes('fresh-token') && !text.includes('/assess'), text);
}

test('an anonymous post of an existing email gets a neutral answer and never reaches msp_client_signon', async (t) => {
  const calls = installFetch(t, { found: true, signon: EXISTING });
  const res = mockRes();
  await handler(req(BODY), res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { status: 'received' });
  assert.equal(signonCalls(calls).length, 0, 'msp_client_signon approves and hands out the live token; it must not run');
  assert.ok(!JSON.stringify(res.body).includes(LIVE_TOKEN));
  const lookup = calls.find((c) => c.url.endsWith('/rpc/msp_company_lookup'));
  assert.deepEqual(lookup.body, { p_email: OWNER });
});

test('a new email is registered and answered in full, as the Plan landing expects', async (t) => {
  const calls = installFetch(t, { found: false });
  const res = mockRes();
  await handler(req(Object.assign({}, BODY, { contact_number: '+27 10 000 0000' })), res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.status, 'received');
  assert.equal(res.body.existing, false);
  assert.equal(res.body.reference, '6f1c2a0e-0000-4000-8000-000000000001');
  assert.equal(res.body.assessment_url, 'https://unit.test/assess.html?token=fresh-token');
  assert.equal(signonCalls(calls)[0].body.p.contact_number, '+27 10 000 0000');
});

test('an account made by someone else between the lookup and the sign on is still answered neutrally', async (t) => {
  installFetch(t, { found: false, signon: EXISTING });
  const res = mockRes();
  await handler(req(BODY), res);
  assert.deepEqual(res.body, { status: 'received' });
});

test('the signed in contact whose confirmed email matches gets the full answer for an existing account', async (t) => {
  const calls = installFetch(t, { user: { id: 'u1', email: 'thandi@fictitious.test', email_confirmed_at: '2026-09-24T08:00:00Z' }, found: true, signon: EXISTING });
  const res = mockRes();
  await handler(req(BODY, { authorization: 'Bearer ' + TOKEN }), res);
  assert.equal(res.body.existing, true);
  assert.equal(res.body.reference, EXISTING.reference);
  assert.equal(res.body.company_name, 'Fictitious Test Co');
  assert.equal(res.body.assessment_url, 'https://unit.test/assess.html?token=' + LIVE_TOKEN);
  assert.equal(calls.filter((c) => c.url.endsWith('/rpc/msp_company_lookup')).length, 0, 'the owner needs no lookup');
  const auth = calls.find((c) => c.url.endsWith('/auth/v1/user'));
  assert.equal(auth.headers.Authorization, 'Bearer ' + TOKEN);
});

test('a signed in user posting someone else\'s email, an unconfirmed email, or a bad token is anonymous', async (t) => {
  const cases = [
    { user: { id: 'u2', email: 'mallory@fictitious.test', email_confirmed_at: '2026-09-24T08:00:00Z' }, auth: 'Bearer ' + TOKEN },
    { user: { id: 'u3', email: 'thandi@fictitious.test', email_confirmed_at: null, confirmed_at: null }, auth: 'Bearer ' + TOKEN },
    { user: null, auth: 'Bearer ' + TOKEN },
    { user: null, auth: 'Bearer not-a-jwt' },
    { user: null, auth: 'Basic abc' }
  ];
  for (const c of cases) {
    const calls = installFetch(t, { user: c.user, found: true, signon: EXISTING });
    const res = mockRes();
    await handler(req(BODY, { authorization: c.auth }), res);
    assert.deepEqual(res.body, { status: 'received' }, c.auth + ' ' + JSON.stringify(c.user));
    assert.equal(signonCalls(calls).length, 0);
  }
});

test('a declined account is answered in full only to its own contact', async (t) => {
  const declined = Object.assign({}, EXISTING, { declined: true });
  installFetch(t, { user: { id: 'u1', email: OWNER, confirmed_at: '2026-09-24T08:00:00Z' }, found: true, signon: declined });
  const res = mockRes();
  await handler(req(BODY, { authorization: 'Bearer ' + TOKEN }), res);
  assert.equal(res.body.declined, true);
  assert.equal(res.body.assessment_url, null);
});

test('the honeypot, missing fields and a malformed number are refused before any call', async (t) => {
  const calls = installFetch(t, {});
  const r1 = mockRes(); await handler(req(Object.assign({}, BODY, { website: 'x' })), r1);
  assert.deepEqual(r1.body, { status: 'rejected' });
  const r2 = mockRes(); await handler(req({ company_name: 'x' }), r2);
  assert.equal(r2.statusCode, 400);
  const r3 = mockRes(); await handler(req(Object.assign({}, BODY, { contact_number: 'call me' })), r3);
  assert.equal(r3.statusCode, 400);
  const r4 = mockRes(); await handler({ method: 'GET', headers: {} }, r4);
  assert.equal(r4.statusCode, 405);
  assert.equal(calls.length, 0);
});

test('a database failure is a plain 500 without the service key', async (t) => {
  globalThis.fetch = async () => new Response('{"message":"down"}', { status: 503 });
  t.after(() => { globalThis.fetch = REAL_FETCH; });
  const res = mockRes();
  await handler(req(BODY), res);
  assert.equal(res.statusCode, 500);
  assert.ok(!JSON.stringify(res.body).includes(SERVICE_KEY));
});

/* ------------------------------------------------ File only registration (v1.5.0) */

test('source hsf registers through hsf_client_register, never msp_client_signon, and answers no token', async (t) => {
  const calls = installFetch(t, { user: OWNER_USER, found: false,
    register: { status: 'received', reference: '6f1c2a0e-0000-4000-8000-000000000002', existing: false,
      company_name: 'Someone Else (Pty) Ltd', contact_number: '+27 10 000 0000', declined: false,
      /* even if the database ever sent these, they must not pass */ token: LIVE_TOKEN, account_kind: 'approved_client' } });
  const res = mockRes();
  await handler(req(Object.assign({}, FILE_BODY, { contact_number: ' +27 10 000 0000 ' }), { authorization: 'Bearer ' + TOKEN }), res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { status: 'received', reference: '6f1c2a0e-0000-4000-8000-000000000002', existing: false,
    company_name: 'Someone Else (Pty) Ltd', contact_number: '+27 10 000 0000', declined: false });
  assertNoPlan(res.body);
  assert.equal(signonCalls(calls).length, 0, 'msp_client_signon starts a Plan assessment; the File must never call it');
  const reg = registerCalls(calls);
  assert.equal(reg.length, 1);
  assert.deepEqual(reg[0].body, { p: { company_name: FILE_BODY.company_name, contact_name: FILE_BODY.contact_name,
    contact_email: FILE_BODY.contact_email, contact_number: '+27 10 000 0000', notes: 'Registered from the Health and Safety File builder' } });
  assert.ok(!('source' in reg[0].body.p), 'the source is the endpoint\'s choice of function, not data');
});

test('source hsf for the signed in contact of an existing account answers existing, with no token', async (t) => {
  const calls = installFetch(t, { user: OWNER_USER, found: true,
    register: { status: 'received', reference: EXISTING.reference, existing: true, company_name: 'Fictitious Test Co',
      contact_number: '010 000 0000', declined: false } });
  const res = mockRes();
  await handler(req(FILE_BODY, { authorization: 'Bearer ' + TOKEN }), res);
  assert.equal(res.body.existing, true);
  assert.equal(res.body.reference, EXISTING.reference);
  assertNoPlan(res.body);
  assert.equal(calls.filter((c) => c.url.endsWith('/rpc/msp_company_lookup')).length, 0, 'the owner needs no lookup');
  assert.equal(signonCalls(calls).length, 0);
  assert.equal(registerCalls(calls).length, 1);
});

test('source hsf answers only its own confirmed, signed in contact: anyone else is a 401 with no lookup and no registration (REG-R3)', async (t) => {
  const cases = [
    { user: null, auth: undefined },
    { user: null, auth: 'Bearer ' + TOKEN },
    { user: { id: 'u2', email: 'mallory@fictitious.test', email_confirmed_at: '2026-09-24T08:00:00Z' }, auth: 'Bearer ' + TOKEN },
    { user: { id: 'u3', email: OWNER, email_confirmed_at: null, confirmed_at: null }, auth: 'Bearer ' + TOKEN }
  ];
  for (const c of cases) {
    for (const found of [true, false]) {
      const calls = installFetch(t, { user: c.user, found });
      const res = mockRes();
      await handler(req(FILE_BODY, c.auth ? { authorization: c.auth } : {}), res);
      const label = JSON.stringify(Object.assign({ found }, c));
      assert.equal(res.statusCode, 401, label);
      assert.deepEqual(res.body, { error: 'sign in with this email to register your company for a File' }, label);
      assertNoPlan(res.body);
      assert.equal(calls.filter((x) => x.url.includes('/rest/v1/')).length, 0, 'no lookup and no registration: ' + label);
    }
  }
});

test('source hsf: an anonymous post of a new email under a chosen company name creates no account (REG-R3)', async (t) => {
  const calls = installFetch(t, { found: false });
  const res = mockRes();
  await handler(req({ source: 'hsf', contact_name: 'Review Tester', contact_email: '  Rev.1@Example.INVALID  ',
    company_name: ' Review Test (Pty) Ltd ' }), res);
  assert.equal(res.statusCode, 401);
  assert.equal(registerCalls(calls).length, 0, 'hsf_client_register must not run for an unproven email');
  assert.equal(signonCalls(calls).length, 0);
  assert.equal(calls.length, 0, 'no call at all without a token');
});

test('source hsf: a declined account is answered declined to its own contact, with no link', async (t) => {
  installFetch(t, { user: OWNER_USER, found: true, register: { status: 'received', reference: EXISTING.reference, existing: true,
    company_name: 'Fictitious Test Co', contact_number: null, declined: true } });
  const res = mockRes();
  await handler(req(FILE_BODY, { authorization: 'Bearer ' + TOKEN }), res);
  assert.equal(res.body.declined, true);
  assertNoPlan(res.body);
});

test('source hsf with hsf_client_register missing (056 not applied) is a 503, logged, and never falls back to msp_client_signon', async (t) => {
  const logged = [];
  const log = t.mock.method(console, 'error', (...a) => { logged.push(a.join(' ')); });
  const calls = installFetch(t, { user: OWNER_USER, found: false, register: 'missing' });
  const res = mockRes();
  await handler(req(FILE_BODY, { authorization: 'Bearer ' + TOKEN }), res);
  log.mock.restore();
  assert.equal(res.statusCode, 503);
  assert.deepEqual(res.body, { error: 'File registration is not available yet' });
  assert.equal(registerCalls(calls).length, 1);
  assert.equal(signonCalls(calls).length, 0, 'no fallback to msp_client_signon, which would start a Plan assessment');
  assert.ok(logged.some((l) => /hsf_client_register/.test(l) && /056/.test(l)), logged.join('\n'));
  assert.ok(!logged.join('\n').includes(SERVICE_KEY));
});

test('source hsf: any other database failure is a plain 500, with no fallback either', async (t) => {
  const calls = installFetch(t, { user: OWNER_USER, found: false });
  const inner = globalThis.fetch;
  globalThis.fetch = async (url, init) => (String(url).endsWith('/rpc/hsf_client_register')
    ? (calls.push({ url: String(url) }), json(500, { code: 'XX000', message: 'boom' }))
    : inner(url, init));
  const res = mockRes();
  await handler(req(FILE_BODY, { authorization: 'Bearer ' + TOKEN }), res);
  assert.equal(res.statusCode, 500);
  assert.ok(!JSON.stringify(res.body).includes(SERVICE_KEY));
  assert.equal(signonCalls(calls).length, 0);
});

test('source hsf keeps the honeypot, required fields and number shape, before any call', async (t) => {
  const calls = installFetch(t, {});
  const r1 = mockRes(); await handler(req(Object.assign({}, FILE_BODY, { website: 'x' })), r1);
  assert.deepEqual(r1.body, { status: 'rejected' });
  const r2 = mockRes(); await handler(req({ company_name: 'x', source: 'hsf' }), r2);
  assert.equal(r2.statusCode, 400);
  const r3 = mockRes(); await handler(req(Object.assign({}, FILE_BODY, { contact_number: 'call me' })), r3);
  assert.equal(r3.statusCode, 400);
  const r4 = mockRes(); await handler({ method: 'GET', headers: {}, body: FILE_BODY }, r4);
  assert.equal(r4.statusCode, 405);
  assert.equal(calls.length, 0);
});

test('an unknown source is refused before any call, so it never starts a Plan assessment', async (t) => {
  for (const source of ['HSF', 'plan', 'file', 1, true, { kind: 'hsf' }]) {
    const calls = installFetch(t, { user: OWNER_USER, found: false });
    const res = mockRes();
    await handler(req(Object.assign({}, BODY, { source }), { authorization: 'Bearer ' + TOKEN }), res);
    assert.equal(res.statusCode, 400, JSON.stringify(source));
    assert.deepEqual(res.body, { error: 'unknown registration source' });
    assert.equal(calls.length, 0);
  }
});

test('without source (the Plan landing) the old path runs: msp_client_signon, never hsf_client_register', async (t) => {
  for (const extra of [{}, { source: '' }, { source: null }]) {
    const calls = installFetch(t, { found: false, register: 'missing' });
    const res = mockRes();
    await handler(req(Object.assign({}, BODY, extra)), res);
    assert.equal(res.statusCode, 200, JSON.stringify(extra));
    assert.equal(res.body.assessment_url, 'https://unit.test/assess.html?token=fresh-token');
    assert.equal(res.body.account_kind, 'client');
    assert.equal(signonCalls(calls).length, 1);
    assert.equal(registerCalls(calls).length, 0);
  }
});

/* The builder is the only sender of source 'hsf': it must send it, and its
   POPIA tick box must say only what a File only registration does. */
test('the File builder posts source hsf and its tick box claims only a File registration', () => {
  const html = fs.readFileSync(path.join(__dirname, '..', '..', 'vercel', 'hsf-builder.html'), 'utf8');
  const payload = /const payload = \{([^}]*)\};/.exec(html);
  assert.ok(payload, 'the registration payload is found');
  assert.match(payload[1], /\bsource: 'hsf'/);
  assert.match(payload[1], /\bnotes: REG_NOTES\b/);
  const label = /<label class="chk" for="reg-consent">([\s\S]*?)<\/label>/.exec(html);
  assert.ok(label, 'the tick box is found');
  const text = label[1].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
  assert.match(text, /^I agree that Care Net uses these details to register my company with Care Net, prepare my Health and Safety File and contact me about it\. They are processed in line with POPIA\./);
  assert.doesNotMatch(text, /anything else|Medical Surveillance|Plan\b|assessment/i);
  assert.match(label[1], /<input type="checkbox" id="reg-consent" name="popia_notice" value="agreed">/);
  assert.match(html, /if \(!\$\('reg-consent'\)\.checked\) \{ fail\('reg-consent'/, 'the tick is still required');
  assert.doesNotMatch(html, /assessment_url\s*[,;)\]}]|\.assessment_url|\['assessment_url'\]/, 'the builder never reads assessment_url');
});
