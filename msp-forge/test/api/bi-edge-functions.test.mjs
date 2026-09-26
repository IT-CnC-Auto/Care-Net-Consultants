// CNC | Bee-Inspect P3: every Edge Function handler with fetch mocked (node --test, no network).
// supabase/functions/<name>/index.ts only calls handle() from
// supabase/functions/_shared/bi/handlers/<name>.js, which these tests drive with
// Request objects and a fake fetch that stands in for Supabase Auth, PostgREST
// and xAI. They prove: methods, sign in and service role checks, validation,
// the rpc each function calls and with what, the answers and status codes, the
// stubs (501 with the names of the settings they wait for, nothing sent), and
// that no secret or personal detail leaks into an answer.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = (p) => fileURLToPath(new URL('../../' + p, import.meta.url));
const handler = async (name) => (await import(`../../supabase/functions/_shared/bi/handlers/${name}.js`)).handle;

const URL_BASE = 'https://project.supabase.test';
const SERVICE_KEY = 'service-role-key-for-tests-only';
const USER = { id: '11111111-2222-4333-8444-555555555555', email: 'inspector.test@example.invalid' };
const b64url = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const TOKEN = `h.${b64url({ sub: USER.id, aal: 'aal1' })}.s`;
const INSPECTION = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const WALLET = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

// A fake fetch: routes are [predicate(url, init), responder(url, init, body)] tried in order.
function fakeFetch(routes) {
  const calls = [];
  const fn = async (url, init = {}) => {
    const body = init.body ? JSON.parse(init.body) : null;
    calls.push({ url: String(url), method: init.method || 'GET', headers: init.headers || {}, body });
    for (const [match, respond] of routes) {
      if (match(String(url), init)) {
        const out = await respond(String(url), init, body);
        if (out instanceof Response) return out;
        return new Response(JSON.stringify(out), { status: 200 });
      }
    }
    throw new Error('unexpected fetch ' + url);
  };
  fn.calls = calls;
  return fn;
}
// An error answer (a plain object is always a 200 JSON answer).
const err = (status, body) => new Response(JSON.stringify(body), { status });
const authOk = [(u) => u.endsWith('/auth/v1/user'), () => USER];
const rpc = (name, respond) => [(u) => u.endsWith('/rest/v1/rpc/' + name), respond];
const deps = (fetch, env = {}) => ({ env: { SUPABASE_URL: URL_BASE, SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY, ...env }, fetch, random: undefined });
const post = (path, body, headers = {}) => new Request('https://fn.test/' + path, {
  method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: typeof body === 'string' ? body : JSON.stringify(body),
});
const asUser = { Authorization: `Bearer ${TOKEN}` };
const asService = { Authorization: `Bearer ${SERVICE_KEY}` };
const read = async (res) => ({ status: res.status, body: await res.json() });

const FUNCTIONS = ['claim-code-create', 'claim-code-redeem', 'report-draft', 'transcribe', 'wallet-estimate', 'wallet-charge',
  'revenuecat-webhook', 'ozow-notify', 'autotopup-run', 'storage-meter', 'docuseal-webhook', 'kyc-webhook', 'qualification-expiry',
  'schedule-reminders', 'ncr-escalation', 'hsf-section-f-sync', 'mco-register', 'mco-export'];

// 0. Layout -----------------------------------------------------------------------------------------

test('every Bee-Inspect Edge Function is a thin index.ts over its handler, and hsf-events is not duplicated', () => {
  for (const name of FUNCTIONS) {
    const ts = readFileSync(root(`supabase/functions/${name}/index.ts`), 'utf8');
    assert.match(ts, new RegExp(`from "\\.\\./_shared/bi/handlers/${name}\\.js"`), name);
    assert.match(ts, /Deno\.serve\(/);
    assert.ok(ts.split('\n').length < 40, `${name} stays thin`);
  }
  assert.equal(existsSync(root('supabase/functions/hsf-events')), false, 'the Vercel /api/hsf-events is the implementation');
  const handlers = readdirSync(root('supabase/functions/_shared/bi/handlers')).map((f) => f.replace(/\.js$/, '')).sort();
  assert.deepEqual(handlers, FUNCTIONS.slice().sort());
});

test('no secret value, model name or invented endpoint is written in the Bee-Inspect functions', () => {
  const files = ['http.js', 'pricing.js', 'risk.js', 'claim-code.js', 'report.js', 'validate.js']
    .map((f) => 'supabase/functions/_shared/bi/' + f)
    .concat(FUNCTIONS.map((n) => `supabase/functions/_shared/bi/handlers/${n}.js`));
  for (const f of files) {
    const s = readFileSync(root(f), 'utf8');
    assert.ok(!/sk_live|sb_secret_|eyJhbGciOi|xai-[A-Za-z0-9]{20,}/.test(s), f + ' holds no key');
    assert.ok(!/grok-[0-9]/i.test(s), f + ' names no Grok model (read from XAI_MODEL_QUALITY)');
    assert.ok(!/myclinic[a-z]*\.(co|com)/i.test(s), f + ' invents no MyClinicOnline address');
    assert.ok(!/\bcompliant\b/i.test(s.replace(/Never say compliant/g, '')), f + ' never says compliant');
  }
});

test('every function refuses the wrong method with 405', async () => {
  for (const name of FUNCTIONS) {
    const h = await handler(name);
    const res = await h(new Request('https://fn.test/x', { method: 'GET' }), deps(fakeFetch([])));
    assert.equal(res.status, 405, name);
  }
});

test('service role functions refuse any other caller with 401 and touch nothing', async () => {
  for (const name of ['wallet-charge', 'autotopup-run', 'storage-meter', 'qualification-expiry', 'schedule-reminders', 'ncr-escalation', 'hsf-section-f-sync', 'mco-register']) {
    const f = fakeFetch([]);
    const res = await (await handler(name))(post(name, {}, asUser), deps(f));
    assert.equal(res.status, 401, name);
    assert.equal(f.calls.length, 0, name);
  }
});

test('signed in functions refuse a missing or rejected token with 401', async () => {
  for (const name of ['claim-code-create', 'report-draft', 'wallet-estimate']) {
    const none = await (await handler(name))(post(name, {}), deps(fakeFetch([])));
    assert.equal(none.status, 401, name);
    const rejected = await (await handler(name))(post(name, {}, asUser), deps(fakeFetch([[(u) => u.endsWith('/auth/v1/user'), () => err(401, {})]])));
    assert.equal(rejected.status, 401, name);
  }
});

test('without SUPABASE_URL or the service key a function answers 503, never 500', async () => {
  const res = await (await handler('wallet-estimate'))(post('x', {}, asUser), { env: {}, fetch: fakeFetch([]) });
  assert.equal(res.status, 503);
});

// 1. Stubs --------------------------------------------------------------------------------------------

test('stubs answer 501 with the settings they wait for, and send nothing', async () => {
  const cases = {
    transcribe: ['TRANSCRIBE_PROVIDER', 'TRANSCRIBE_API_KEY'],
    'ozow-notify': ['OZOW_SITE_CODE', 'OZOW_PRIVATE_KEY', 'OZOW_API_KEY'],
    'kyc-webhook': ['KYC_VENDOR', 'KYC_WEBHOOK_SECRET'],
    'mco-export': ['MCO_BASE_URL', 'MCO_API_TOKEN'],
  };
  for (const [name, needs] of Object.entries(cases)) {
    const f = fakeFetch([]);
    const { status, body } = await read(await (await handler(name))(post(name, { any: 'thing' }, asService), deps(f, { MCO_BASE_URL: 'https://example.invalid', OZOW_PRIVATE_KEY: 'x' })));
    assert.equal(status, 501, name);
    assert.equal(body.stub, true);
    assert.deepEqual(body.needs, needs);
    assert.equal(f.calls.length, 0, `${name} makes no call, even with settings present`);
  }
});

test('ozow-notify rejects every notification until the hash rules are supplied', async () => {
  const { status, body } = await read(await (await handler('ozow-notify'))(post('ozow', 'SiteCode=X&Hash=abc'), deps(fakeFetch([]))));
  assert.equal(status, 501);
  assert.match(body.detail, /Rejected/);
});

// 2. Claim codes ----------------------------------------------------------------------------------------

test('claim-code-create makes a code, stores only its hash, and returns the code once', async () => {
  const f = fakeFetch([authOk, rpc('hsf_link_account', () => '99999999-2222-4333-8444-555555555555'),
    rpc('bi_claim_code_create', (u, i, b) => ({ claim_id: 'c1', expires_at: '2026-09-26T10:10:00Z' }))]);
  const { status, body } = await read(await (await handler('claim-code-create'))(
    post('c', { ad_id: 'AD-01', page: '/hsf-builder', utm_content: 'AD-01_gaps' }, asUser), deps(f, { BI_CLAIM_LINK_BASE: 'https://staging.example.test/' })));
  assert.equal(status, 201);
  assert.match(body.code, /^[A-HJ-NP-Z2-9]{8}$/);
  assert.equal(body.claim_path, '/claim/' + body.code);
  assert.equal(body.claim_url, 'https://staging.example.test/claim/' + body.code);
  const call = f.calls.find((c) => c.url.endsWith('bi_claim_code_create'));
  assert.equal(call.body.p_code_hash, createHash('sha256').update(body.code).digest('hex'));
  assert.ok(!JSON.stringify(call.body).includes(body.code), 'the plain code never reaches the database');
  assert.equal(call.body.p_auth_user, USER.id);
  assert.deepEqual(call.body.p, { ad_id: 'AD-01', page: '/hsf-builder', utm_content: 'AD-01_gaps' });
});

test('claim-code-create refuses unknown fields and bad shapes', async () => {
  const f = fakeFetch([authOk]);
  const { status, body } = await read(await (await handler('claim-code-create'))(post('c', { ad_id: 'AD-99', tenant_id: 'x' }, asUser), deps(f)));
  assert.equal(status, 400);
  assert.deepEqual(body.issues.map((i) => i.path.join('.')).sort(), ['ad_id', 'tenant_id']);
});

test('claim-code-create passes the database rate limit on as 429', async () => {
  const f = fakeFetch([authOk, rpc('hsf_link_account', () => null),
    rpc('bi_claim_code_create', () => err(400, { code: '53400', message: 'Too many claim codes. Please wait a few minutes.' }))]);
  const { status, body } = await read(await (await handler('claim-code-create'))(post('c', {}, asUser), deps(f)));
  assert.equal(status, 429);
  assert.match(body.error, /Too many claim codes/);
});

test('claim-code-redeem signs the phone in with a one time token hash, never the email', async () => {
  const f = fakeFetch([
    rpc('bi_claim_code_redeem', (u, i, b) => ({ ok: true, auth_user_id: USER.id, email: USER.email, client_account_id: 'acc', file_id: 'file' })),
    [(u) => u.endsWith('/auth/v1/admin/generate_link'), (u, i, b) => ({ hashed_token: 'hash-from-auth', verification_type: 'magiclink' })],
  ]);
  const { status, body } = await read(await (await handler('claim-code-redeem'))(
    post('r', { code: 'k7m2-qx9a', device: 'Test phone' }, { 'x-forwarded-for': '198.51.100.7, 10.0.0.1' }), deps(f)));
  assert.equal(status, 200);
  assert.deepEqual(body, { ok: true, token_hash: 'hash-from-auth', type: 'magiclink', client_account_id: 'acc', file_id: 'file' });
  const redeem = f.calls.find((c) => c.url.endsWith('bi_claim_code_redeem'));
  assert.equal(redeem.body.p_code_hash, createHash('sha256').update('K7M2QX9A').digest('hex'));
  assert.match(redeem.body.p.caller_key, /^[0-9a-f]{64}$/);
  assert.ok(!JSON.stringify(redeem.body).includes('198.51.100.7'), 'the caller address is hashed, never sent');
  const link = f.calls.find((c) => c.url.endsWith('generate_link'));
  assert.deepEqual(link.body, { type: 'magiclink', email: USER.email });
  assert.ok(!JSON.stringify(body).includes(USER.email));
});

test('claim-code-redeem maps invalid, used, expired and rate to 400, 409, 410 and 429', async () => {
  for (const [reason, status] of [['invalid', 400], ['used', 409], ['expired', 410], ['rate', 429]]) {
    const f = fakeFetch([rpc('bi_claim_code_redeem', () => ({ ok: false, reason }))]);
    const res = await read(await (await handler('claim-code-redeem'))(post('r', { code: 'ABCD2345' }), deps(f)));
    assert.equal(res.status, status, reason);
    assert.equal(res.body.reason, reason);
    assert.equal(f.calls.some((c) => c.url.includes('generate_link')), false);
  }
  const f = fakeFetch([]);
  const bad = await read(await (await handler('claim-code-redeem'))(post('r', { code: '<x>' }), deps(f)));
  assert.equal(bad.status, 400);
  assert.equal(f.calls.length, 0, 'a malformed code never reaches the database');
});

// 3. Wallet ------------------------------------------------------------------------------------------------

test('wallet-estimate passes the checked input to bi_wallet_estimate and answers in rand', async () => {
  const f = fakeFetch([authOk, rpc('bi_wallet_estimate', (u, i, b) => ({ usage_event_id: 'ue1', estimate_cents: 2109, available_cents: 39820, allowed: true, reason: null, free_photos: 0, vat_mode: 'to_be_confirmed' }))]);
  const input = { wallet_id: WALLET, kind: 'ai_draft', tokens_in: 150000, tokens_out: 8000, idempotency_key: 'est:draft:0001' };
  const { status, body } = await read(await (await handler('wallet-estimate'))(post('e', input, asUser), deps(f)));
  assert.equal(status, 200);
  assert.equal(body.estimate, 'R21,09');
  assert.equal(body.available, 'R398,20');
  assert.equal(body.vat_mode, 'to_be_confirmed');
  assert.deepEqual(f.calls.find((c) => c.url.endsWith('bi_wallet_estimate')).body, { p_auth_user: USER.id, p: input });
  assert.ok(!('tokens' in body), 'tokens are never shown');
});

test('wallet-estimate refuses a bad kind, a short key or negative tokens before the database', async () => {
  const f = fakeFetch([authOk]);
  const res = await read(await (await handler('wallet-estimate'))(post('e', { wallet_id: WALLET, kind: 'gold', tokens_in: -1, idempotency_key: 'x' }, asUser), deps(f)));
  assert.equal(res.status, 400);
  assert.equal(f.calls.filter((c) => c.url.includes('/rpc/')).length, 0);
});

test('wallet-charge is service role only and idempotent through the database key', async () => {
  const f = fakeFetch([rpc('bi_wallet_charge', (u, i, b) => ({ estimate_cents: 2109, actual_cents: 2276, charged_cents: 2276, shortfall_cents: 0, available_cents: 37544, repeat: false }))]);
  const { status, body } = await read(await (await handler('wallet-charge'))(
    post('c', { usage_event_id: WALLET, idempotency_key: 'chg:draft:0001', tokens_in: 160000, tokens_out: 9000 }, asService), deps(f)));
  assert.equal(status, 200);
  assert.equal(body.charged, 'R22,76');
  assert.equal(body.available, 'R375,44');
  assert.deepEqual(f.calls[0].body, { p_usage_event_id: WALLET, p: { idempotency_key: 'chg:draft:0001', tokens_in: 160000, tokens_out: 9000 } });
  const missingKey = await (await handler('wallet-charge'))(post('c', { usage_event_id: WALLET }, asService), deps(fakeFetch([])));
  assert.equal(missingKey.status, 400, 'no idempotency key, no charge');
  const conflict = fakeFetch([rpc('bi_wallet_charge', () => err(409, { code: '23505', message: 'This usage event was already charged under another key.' }))]);
  assert.equal((await (await handler('wallet-charge'))(post('c', { usage_event_id: WALLET, idempotency_key: 'chg:other:0001' }, asService), deps(conflict))).status, 409);
});

// 4. Store and payment webhooks ---------------------------------------------------------------------------------

const RC_EVENT = { api_version: '1.0', event: { id: 'rc-evt-1', type: 'NON_RENEWING_PURCHASE', app_user_id: USER.id, product_id: 'za.carenet.bee.topup499', purchased_at_ms: Date.UTC(2026, 8, 26) } };

test('revenuecat-webhook is a labelled stub until REVENUECAT_WEBHOOK_AUTH is set', async () => {
  const f = fakeFetch([]);
  const { status, body } = await read(await (await handler('revenuecat-webhook'))(post('rc', RC_EVENT), deps(f)));
  assert.equal(status, 501);
  assert.deepEqual(body.needs, ['REVENUECAT_WEBHOOK_AUTH', 'BI_RC_PRODUCT_MAP']);
});

test('revenuecat-webhook checks the Authorization header, maps the product and applies each event once', async () => {
  const env = { REVENUECAT_WEBHOOK_AUTH: 'Bearer rc-test-secret', BI_RC_PRODUCT_MAP: JSON.stringify({ 'za.carenet.bee.topup499': 'topup_499' }) };
  const wrong = await (await handler('revenuecat-webhook'))(post('rc', RC_EVENT, { Authorization: 'Bearer nope' }), deps(fakeFetch([]), env));
  assert.equal(wrong.status, 401);
  const f = fakeFetch([rpc('bi_iap_apply', () => ({ receipt_id: 'r1', status: 'applied', repeat: false }))]);
  const { status, body } = await read(await (await handler('revenuecat-webhook'))(post('rc', RC_EVENT, { Authorization: 'Bearer rc-test-secret' }), deps(f, env)));
  assert.equal(status, 200);
  assert.deepEqual(body, { received: true, status: 'applied', repeat: false });
  const p = f.calls[0].body.p;
  assert.equal(p.provider, 'revenuecat');
  assert.equal(p.event_id, 'rc-evt-1');
  assert.equal(p.product_code, 'topup_499');
  assert.equal(p.auth_user_id, USER.id);
  assert.equal(p.period_start, '2026-09-26');
  assert.match(p.payload_sha256, /^[0-9a-f]{64}$/);
});

test('revenuecat-webhook never guesses: an unmapped product goes to the database as unmapped (recorded as rejected)', async () => {
  const env = { REVENUECAT_WEBHOOK_AUTH: 's3cret' };
  const f = fakeFetch([rpc('bi_iap_apply', (u, i, b) => ({ receipt_id: 'r2', status: b.p.product_code === 'unmapped' ? 'rejected' : 'applied' }))]);
  const { body } = await read(await (await handler('revenuecat-webhook'))(post('rc', RC_EVENT, { Authorization: 's3cret' }), deps(f, env)));
  assert.equal(body.status, 'rejected');
  const test = await read(await (await handler('revenuecat-webhook'))(post('rc', { event: { id: 't', type: 'TEST' } }, { Authorization: 's3cret' }), deps(fakeFetch([]), env)));
  assert.equal(test.body.status, 'ignored');
});

test('autotopup-run: nothing due is 200; wallets due answer 501 because the saved card gateway is not chosen', async () => {
  const none = await read(await (await handler('autotopup-run'))(post('a', {}, asService), deps(fakeFetch([rpc('bi_autotopup_queue', () => ({ due: [] }))]))));
  assert.deepEqual([none.status, none.body], [200, { due: 0, charged: 0 }]);
  const f = fakeFetch([rpc('bi_autotopup_queue', () => ({ due: [{ wallet_id: WALLET, saved_card_ref: 'tok_x', price_cents: 9900 }] }))]);
  const due = await read(await (await handler('autotopup-run'))(post('a', {}, asService), deps(f)));
  assert.equal(due.status, 501);
  assert.match(due.body.detail, /1 wallet\(s\) were due for R99,00; none was charged/);
  assert.equal(f.calls.length, 1, 'no gateway call');
  assert.ok(!JSON.stringify(due.body).includes('tok_x'), 'the saved card reference is never returned');
});

// 5. DocuSeal ----------------------------------------------------------------------------------------------

const REPORT = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const STEP = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const DS = { event_type: 'submission.completed', data: { submission_id: 4321, metadata: { bi_report_id: REPORT, bi_auth_user_id: USER.id, bi_step_up_id: STEP, bi_confirm_photos: true, bi_confirm_voice_notes: true } } };

test('docuseal-webhook: stub without its secret; wrong secret 401; other submissions ignored', async () => {
  assert.equal((await (await handler('docuseal-webhook'))(post('d', DS), deps(fakeFetch([])))).status, 501);
  const env = { DOCUSEAL_WEBHOOK_SECRET: 'ds-secret' };
  assert.equal((await (await handler('docuseal-webhook'))(post('d', DS, { 'x-docuseal-signature': 'no' }), deps(fakeFetch([]), env))).status, 401);
  const plan = await read(await (await handler('docuseal-webhook'))(post('d', { event_type: 'submission.completed', data: { id: 1, metadata: {} } }, { 'x-webhook-secret': 'ds-secret' }), deps(fakeFetch([]), env)));
  assert.equal(plan.body.ignored, true, 'the File site DocuSeal intake is left alone');
});

test('docuseal-webhook records the signature through bi_report_sign, once per submission', async () => {
  const env = { DOCUSEAL_WEBHOOK_SECRET: 'ds-secret' };
  const f = fakeFetch([[(u) => u.includes('/rest/v1/bi_signature?'), () => []], rpc('bi_report_sign', () => ({ signature_id: 's1' }))]);
  const { status, body } = await read(await (await handler('docuseal-webhook'))(post('d', DS, { 'x-docuseal-signature': 'ds-secret' }), deps(f, env)));
  assert.deepEqual([status, body], [200, { signed: true }]);
  const sign = f.calls.find((c) => c.url.endsWith('bi_report_sign')).body;
  assert.deepEqual(sign, { p_auth_user: USER.id, p_report_id: REPORT, p: { step_up_id: STEP, channel: 'docuseal', docuseal_submission_ref: '4321', device_integrity: 'unknown', confirm_photos: true, confirm_voice_notes: true } });
  const again = fakeFetch([[(u) => u.includes('/rest/v1/bi_signature?'), () => [{ id: 's1' }]]]);
  const r2 = await read(await (await handler('docuseal-webhook'))(post('d', DS, { 'x-docuseal-signature': 'ds-secret' }), deps(again, env)));
  assert.deepEqual(r2.body, { signed: true, repeat: true });
  assert.equal(again.calls.some((c) => c.url.endsWith('bi_report_sign')), false);
  const refused = fakeFetch([[(u) => u.includes('/rest/v1/bi_signature?'), () => []],
    rpc('bi_report_sign', () => err(400, { code: '42501', message: 'You are not cleared to sign scaffolds reports.' }))]);
  const r3 = await read(await (await handler('docuseal-webhook'))(post('d', DS, { 'x-docuseal-signature': 'ds-secret' }), deps(refused, env)));
  assert.deepEqual([r3.status, r3.body.signed], [200, false], 'a refusal is answered 200 so DocuSeal does not retry forever');
});

// 6. Cron runs and Section F --------------------------------------------------------------------------------

test('cron functions call their run and return counts and ids, never names', async () => {
  const runs = {
    'qualification-expiry': ['bi_qualification_expiry_run', { alerts: [{ id: 'q1', app_user_id: 'u1', threshold: 30, days: 25, qual_type: 'Secret Name' }], expired: [], restricted: [] }],
    'schedule-reminders': ['bi_schedule_reminders_run', { reminders: [{ id: 'i1', inspector_user_id: 'u1', scheduled_for: '2026-10-01', title: 'x' }], overdue: [{}, {}], recurring_created: 1 }],
    'ncr-escalation': ['bi_ncr_escalation_run', { escalated: [{ escalation_level: 1, owner_name: 'Private Person' }, { escalation_level: 3 }] }],
    'storage-meter': ['bi_storage_meter_run', { warnings: [{ tenant_id: 't', client_account_id: 'c', level: 'warn_80', status: { pct: 81.2 } }] }],
  };
  for (const [name, [fn, result]] of Object.entries(runs)) {
    const f = fakeFetch([rpc(fn, () => result)]);
    const { status, body } = await read(await (await handler(name))(post(name, {}, asService), deps(f)));
    assert.equal(status, 200, name);
    assert.equal(f.calls[0].url, `${URL_BASE}/rest/v1/rpc/${fn}`);
    assert.equal(f.calls[0].headers.Authorization, `Bearer ${SERVICE_KEY}`);
    assert.ok(!/Secret Name|Private Person/.test(JSON.stringify(body)), name + ' returns no names');
    assert.equal(body.notified, 0, name + ' sends nothing until a platform exists');
  }
  const ncr = await read(await (await handler('ncr-escalation'))(post('n', {}, asService), deps(fakeFetch([rpc('bi_ncr_escalation_run', () => runs['ncr-escalation'][1])]))));
  assert.deepEqual(ncr.body.by_level, { 1: 1, 2: 0, 3: 1 });
});

test('hsf-section-f-sync files one report, or retries every waiting report', async () => {
  const one = fakeFetch([rpc('bi_hsf_section_f_sync', (u, i, b) => ({ report_id: b.p_report_id, status: 'linked', element_code: 'HSF-F-01' }))]);
  const r1 = await read(await (await handler('hsf-section-f-sync'))(post('s', { report_id: REPORT }, asService), deps(one)));
  assert.deepEqual(r1.body, { report_id: REPORT, status: 'linked', element_code: 'HSF-F-01' });
  const all = fakeFetch([rpc('bi_hsf_section_f_sync_pending', (u, i, b) => ({ processed: 0, results: [], limit: b.p_limit }))]);
  const r2 = await read(await (await handler('hsf-section-f-sync'))(post('s', {}, asService), deps(all)));
  assert.equal(r2.body.limit, 25);
});

test('mco-register registers nodes locally and never calls MyClinicOnline', async () => {
  const f = fakeFetch([rpc('bi_mco_register', () => ({ nodes: 4, status: 'registered_local' }))]);
  const { body } = await read(await (await handler('mco-register'))(post('m', { client_account_id: REPORT }, asService), deps(f, { MCO_BASE_URL: 'https://mco.example.invalid' })));
  assert.equal(body.status, 'registered_local');
  assert.ok(f.calls.every((c) => c.url.startsWith(URL_BASE)), 'only Supabase is called');
});

// 7. Report draft ----------------------------------------------------------------------------------------

function draftRoutes(extra = []) {
  const table = (name, rows) => [(u) => u.startsWith(`${URL_BASE}/rest/v1/${name}?`), () => rows];
  return fakeFetch([
    authOk,
    table('bi_inspection', [{ id: INSPECTION, title: 'Scaffold inspection (fictitious)', template_id: 't', tenant_id: 'ten', client_account_id: 'acc' }]),
    rpc('bi_user_roles', (u, i, b) => (b.p_auth_user === USER.id ? ['inspector'] : [])),
    table('bi_template_item', [{ id: 'ti1', prompt: 'Toe boards in place', kernel_ref: 'CNC-DEMO-SCAFF-01' }]),
    table('bi_template', [{ id: 't', code: 'SCAFFOLDS', category: 'scaffolds', section_f_element_code: 'HSF-F-01' }]),
    table('bi_inspection_area', [{ id: 'a1', label: 'Laydown area' }]),
    table('bi_finding', [{ id: 'f1', area_id: 'a1', template_item_id: 'ti1', result: 'fail', note: 'Missing' }]),
    table('bi_photo', [{ id: 'p1', finding_id: 'f1' }]),
    table('bi_risk', []),
    table('bi_corrective_action', [{ id: 'c1', finding_id: 'f1', description: 'Fit toe boards', owner_name: 'Owner', due_on: '2026-10-01', status: 'open' }]),
    table('bi_voice_note', [{ id: 'v1', finding_id: 'f1', vn_number: 1 }]),
    table('bi_voice_transcript', [{ voice_note_id: 'v1', version: 1, body: 'No toe boards.' }]),
    rpc('bi_report_save_draft', (u, i, b) => ({ report_id: 'r1', version: 1, status: 'draft', voice_notes: { total: 1, accounted: 1, missing: 0 } })),
    ...extra,
  ]);
}

test('report-draft without AI settings saves the labelled template draft and never calls xAI', async () => {
  const f = draftRoutes();
  const { status, body } = await read(await (await handler('report-draft'))(post('d', { inspection_id: INSPECTION, use_ai: true, wallet_id: WALLET }, asUser), deps(f)));
  assert.equal(status, 200);
  assert.equal(body.label, 'Assistive draft. Competent person sign off required.');
  assert.equal(body.voice_notes_line, 'Voice notes: 1 accounted for, 0 missing');
  assert.equal(body.ai.used, false);
  assert.match(body.ai.reason, /XAI_API_KEY and XAI_MODEL_QUALITY/);
  assert.equal(f.calls.some((c) => c.url.includes('x.ai')), false);
  assert.equal(f.calls.some((c) => c.url.endsWith('bi_wallet_estimate')), false, 'nothing is estimated or charged');
  const saved = f.calls.find((c) => c.url.endsWith('bi_report_save_draft')).body;
  assert.equal(saved.p_source, 'template');
  assert.equal(saved.p_content.label, 'Assistive draft. Competent person sign off required.');
  assert.equal(saved.p_content.footer, 'This report is powered by Care Net Consultants Development House (Pty) Ltd');
  assert.ok(saved.p_content.claims.every((c) => c.kernel_ref), 'every claim carries a kernel reference');
});

test('report-draft reads nothing more of an inspection the caller does not inspect', async () => {
  const other = { ...USER, id: '99999999-9999-4999-8999-999999999999' };
  const g = fakeFetch([[(u) => u.endsWith('/auth/v1/user'), () => other]]);
  const routes = draftRoutes();
  const combined = async (url, init) => (String(url).endsWith('/auth/v1/user') ? g(url, init) : routes(url, init));
  const res = await (await handler('report-draft'))(post('d', { inspection_id: INSPECTION }, asUser), deps(combined));
  assert.equal(res.status, 404);
  assert.equal(routes.calls.some((c) => c.url.includes('bi_finding')), false, 'no findings were read');
});

test('report-draft with AI settings: estimate, one xAI call with the model from the environment, charge on actual tokens, citations enforced', async () => {
  const xai = [(u) => u === 'https://api.x.ai/v1/chat/completions', (u, i, b) => ({
    choices: [{ message: { content: JSON.stringify({ executive_summary: 'Two edges lack protection.', claims: [
      { text: 'Edge protection is needed.', kernel_ref: 'CNC-DEMO-SCAFF-01', finding_id: 'f1' },
      { text: 'An invented legal duty.', kernel_ref: 'MADE-UP-99' }] }) } }],
    usage: { prompt_tokens: 1200, completion_tokens: 300 },
  })];
  const f = draftRoutes([
    rpc('bi_wallet_estimate', () => ({ usage_event_id: 'ue1', estimate_cents: 50, allowed: true })),
    rpc('bi_wallet_charge', () => ({ charged_cents: 48 })),
    xai,
  ]);
  const env = { XAI_API_KEY: 'test-key', XAI_MODEL_QUALITY: 'model-from-env' };
  const { status, body } = await read(await (await handler('report-draft'))(post('d', { inspection_id: INSPECTION, use_ai: true, wallet_id: WALLET }, asUser), deps(f, env)));
  assert.equal(status, 200);
  assert.deepEqual(body.ai, { used: true, charged_cents: 48 });
  const call = f.calls.find((c) => c.url.includes('x.ai'));
  assert.equal(call.body.model, 'model-from-env');
  assert.equal(call.headers.Authorization, 'Bearer test-key');
  const order = f.calls.map((c) => c.url.split('/').pop()).filter((n) => ['bi_wallet_estimate', 'completions', 'bi_wallet_charge', 'bi_report_save_draft'].includes(n));
  assert.deepEqual(order, ['bi_wallet_estimate', 'completions', 'bi_wallet_charge', 'bi_report_save_draft']);
  assert.deepEqual(f.calls.find((c) => c.url.endsWith('bi_wallet_charge')).body.p, { idempotency_key: 'charge:ue1', tokens_in: 1200, tokens_out: 300 });
  const saved = f.calls.find((c) => c.url.endsWith('bi_report_save_draft')).body;
  assert.equal(saved.p_source, 'ai_assistive');
  assert.equal(saved.p_content.executive_summary, 'Two edges lack protection.');
  assert.ok(saved.p_content.claims.every((c) => c.kernel_ref === 'CNC-DEMO-SCAFF-01'), 'the uncited AI claim was dropped');
  assert.ok(saved.p_content.uncited.includes('An invented legal duty.'));
  assert.ok(!JSON.stringify(body).includes('test-key'));
});

test('report-draft: a refused estimate answers 402 and xAI is never called', async () => {
  const f = draftRoutes([rpc('bi_wallet_estimate', () => ({ usage_event_id: 'ue1', estimate_cents: 5000, allowed: false, reason: 'wallet_empty' }))]);
  const { status, body } = await read(await (await handler('report-draft'))(post('d', { inspection_id: INSPECTION, use_ai: true, wallet_id: WALLET }, asUser),
    deps(f, { XAI_API_KEY: 'k', XAI_MODEL_QUALITY: 'm' })));
  assert.equal(status, 402);
  assert.equal(body.reason, 'wallet_empty');
  assert.equal(f.calls.some((c) => c.url.includes('x.ai')), false);
  assert.equal(f.calls.some((c) => c.url.endsWith('bi_report_save_draft')), false);
});

test('report-draft: when xAI fails nothing is charged', async () => {
  const f = draftRoutes([rpc('bi_wallet_estimate', () => ({ usage_event_id: 'ue1', estimate_cents: 50, allowed: true })),
    [(u) => u.includes('x.ai'), () => err(503, { error: 'down' })]]);
  const res = await (await handler('report-draft'))(post('d', { inspection_id: INSPECTION, use_ai: true, wallet_id: WALLET }, asUser), deps(f, { XAI_API_KEY: 'k', XAI_MODEL_QUALITY: 'm' }));
  assert.equal(res.status, 502);
  assert.equal(f.calls.some((c) => c.url.endsWith('bi_wallet_charge')), false);
});
