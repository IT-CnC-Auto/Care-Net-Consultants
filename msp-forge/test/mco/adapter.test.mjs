// CNC HSF FORGE | tests for the MyClinicOnline transfer worker (node --test)
// supabase/functions/_shared/mco-adapter.js   hold, fixture, live placeholder
// supabase/functions/_shared/transfer-core.js per upload flow, deletion rule, run, REST bindings
// The edge function supabase/functions/hsf-mco-transfer/index.ts only wires these
// together; Deno is not needed to run this file.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  sha256Hex, createAdapter, isSha256Hex, MODES, PENDING_MESSAGE, LIVE_PLACEHOLDER, buildPlaceholderRequest,
} from '../../supabase/functions/_shared/mco-adapter.js';
import {
  processUpload, runTransfer, resolveMode, checkStagingPath, mayDeleteStaging, isServiceCaller,
  createSupabaseIo, encodeStagingPath, QUEUE_LIMIT, MODE_PARAMETER, STAGING_BUCKET,
} from '../../supabase/functions/_shared/transfer-core.js';

// 1. Fixtures ------------------------------------------------------------------

const ACCOUNT_ID = '0b9a8c7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d';
const UPLOAD_ID = '9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b';
const OTHER_ACCOUNT = '11111111-2222-4333-8444-555555555555';
const SAFE_NAME = 'Risk_assessment_2026.pdf';
const PATH = `${ACCOUNT_ID}/${UPLOAD_ID}/${SAFE_NAME}`;
const BYTES = new TextEncoder().encode('Synthetic test document for Section F. Not a real record.');
const SHA = await sha256Hex(BYTES);
const WRONG_SHA = 'ab'.repeat(32);
const SUPABASE_URL = 'https://unit-test.supabase.invalid';
const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
const MCO_BASE = 'https://mco.unit-test.invalid';
const MCO_TOKEN = 'mco-token-UNIT-TEST-must-never-appear-9876543210';
const REAL_FETCH = globalThis.fetch;

function uploadRow(over) {
  return Object.assign({
    id: UPLOAD_ID,
    client_account_id: ACCOUNT_ID,
    auth_user_id: '6f1c2d3e-4a5b-4c6d-8e7f-9a0b1c2d3e4f',
    department_code: 'SHE',
    section_code: 'F',
    original_name: 'Risk assessment 2026.pdf',
    safe_name: SAFE_NAME,
    mime_type: 'application/pdf',
    size_bytes: BYTES.length,
    sha256_client: SHA,
    sha256_server: null,
    storage_bucket: STAGING_BUCKET,
    storage_path: PATH,
    status: 'uploaded',
  }, over || {});
}

// Fetch that fails the test if anything touches the network.
function forbidNetwork(t) {
  globalThis.fetch = async () => { throw new Error('network used where none was allowed'); };
  t.after(() => { globalThis.fetch = REAL_FETCH; });
}

// Injected dependencies with a call log. The fake database answers
// hsf_transfer_record the way section 5 of the contract describes.
function fakeDeps(opts) {
  const o = opts || {};
  const calls = [];
  const deps = {
    mode: o.mode || 'fixture',
    adapter: o.adapter || createAdapter({ mode: o.mode || 'fixture' }),
    async download(path) {
      calls.push(['download', path]);
      if (o.downloadFails) throw new Error('Storage replied with HTTP 404.');
      return o.bytes || BYTES;
    },
    async remove(path) {
      calls.push(['remove', path]);
      if (o.removeFails) throw new Error('Storage refused the removal (HTTP 500).');
      if (o.removeReturnsFalse) return false;
      return true;
    },
    async rpc(fn, args) {
      calls.push(['rpc', fn, args]);
      if (o.rpcFails && o.rpcFails.includes(fn)) throw new Error(`${fn} was refused (HTTP 500)`);
      if (fn === 'hsf_transfer_record') {
        if (o.recordReply !== undefined) return o.recordReply;
        const status = {
          held: 'held',
          received: args.p_server_sha256 === SHA && args.p_receipt_sha256 === SHA ? 'transferred' : 'failed',
          hash_mismatch: 'failed',
          error: 'uploaded',
        }[args.p_outcome];
        return { upload_id: args.p_upload_id, status };
      }
      if (fn === 'hsf_mark_staging_deleted') return { upload_id: args.p_upload_id, status: 'staging_deleted' };
      throw new Error(`unexpected rpc ${fn}`);
    },
  };
  return { deps, calls, names: () => calls.map((c) => (c[0] === 'rpc' ? `rpc:${c[1]}` : c[0])) };
}

function recordArgs(calls) {
  const c = calls.filter((x) => x[0] === 'rpc' && x[1] === 'hsf_transfer_record');
  assert.equal(c.length, 1, 'exactly one transfer log row per upload');
  return c[0][2];
}

function assertNoDeletion(calls) {
  assert.ok(!calls.some((c) => c[0] === 'remove'), 'the staging object was deleted');
  assert.ok(!calls.some((c) => c[0] === 'rpc' && c[1] === 'hsf_mark_staging_deleted'), 'hsf_mark_staging_deleted was called');
}

// 2. Fingerprints ----------------------------------------------------------------

test('sha256Hex matches the published SHA 256 test vectors', async () => {
  assert.equal(await sha256Hex(new Uint8Array(0)), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  assert.equal(await sha256Hex(new TextEncoder().encode('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.equal(await sha256Hex(new TextEncoder().encode('abc').buffer), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.ok(isSha256Hex(SHA));
  await assert.rejects(() => sha256Hex('not bytes'), TypeError);
});

// 3. Adapter ------------------------------------------------------------------------

test('adapter: the modes are hold, fixture and live, and anything else is refused', () => {
  assert.deepEqual([...MODES], ['hold', 'fixture', 'live']);
  assert.throws(() => createAdapter({ mode: 'send_everything' }), /Unknown MCO transfer mode/);
  assert.throws(() => createAdapter({}), /Unknown MCO transfer mode/);
});

test('adapter hold: outcome held and no network call', async (t) => {
  forbidNetwork(t);
  const a = createAdapter({ mode: 'hold' });
  const r = await a.send({ uploadId: UPLOAD_ID, fileName: SAFE_NAME, mimeType: 'application/pdf', bytes: BYTES, sha256: SHA });
  assert.deepEqual(r, { outcome: 'held', mcoDocumentRef: null, receiptSha256: null, error: null });
});

test('adapter fixture: received with FIXTURE reference and the receipt echoing the hash', async (t) => {
  forbidNetwork(t);
  const a = createAdapter({ mode: 'fixture' });
  const r = await a.send({ uploadId: UPLOAD_ID, fileName: SAFE_NAME, mimeType: 'application/pdf', bytes: BYTES, sha256: SHA });
  assert.equal(r.outcome, 'received');
  assert.equal(r.mcoDocumentRef, 'FIXTURE-' + UPLOAD_ID);
  assert.equal(r.receiptSha256, SHA);
  assert.equal(r.error, null);
});

test('adapter: a malformed document is an error outcome, not a receipt', async () => {
  const a = createAdapter({ mode: 'fixture' });
  const r = await a.send({ uploadId: UPLOAD_ID, bytes: BYTES, sha256: 'nope' });
  assert.equal(r.outcome, 'error');
  assert.equal(r.mcoDocumentRef, null);
});

test('adapter live: refuses to start without MCO_BASE_URL and MCO_API_TOKEN', () => {
  assert.equal(PENDING_MESSAGE, 'MCO interface contract pending (HSF-3)');
  assert.throws(() => createAdapter({ mode: 'live' }), { message: PENDING_MESSAGE });
  assert.throws(() => createAdapter({ mode: 'live', baseUrl: MCO_BASE }), { message: PENDING_MESSAGE });
  assert.throws(() => createAdapter({ mode: 'live', token: MCO_TOKEN }), { message: PENDING_MESSAGE });
  assert.throws(() => createAdapter({ mode: 'live', baseUrl: '  ', token: MCO_TOKEN }), { message: PENDING_MESSAGE });
  assert.throws(() => createAdapter({ mode: 'live', baseUrl: 'http://mco.unit-test.invalid', token: MCO_TOKEN }), /must use https/);
});

test('adapter live: the request is a clearly marked placeholder, not an MCO endpoint', () => {
  assert.match(LIVE_PLACEHOLDER.path, /PLACEHOLDER/);
  assert.match(LIVE_PLACEHOLDER.status, /HSF-3/);
  const { url, init } = buildPlaceholderRequest(MCO_BASE + '/', MCO_TOKEN, {
    uploadId: UPLOAD_ID, fileName: 'a b.pdf', mimeType: 'application/pdf', bytes: BYTES, sha256: SHA,
  });
  assert.equal(url, `${MCO_BASE}/PLACEHOLDER-HSF-3/documents`);
  assert.equal(init.headers.Authorization, `Bearer ${MCO_TOKEN}`);
  assert.equal(init.headers['X-Placeholder-File-Name'], 'a%20b.pdf');
  assert.equal(init.body, BYTES);
});

test('adapter live placeholder: a well formed receipt is received; failures are errors without the token', async () => {
  const doc = { uploadId: UPLOAD_ID, fileName: SAFE_NAME, mimeType: 'application/pdf', bytes: BYTES, sha256: SHA };
  const seen = [];
  const reply = (status, body) => async (url, init) => {
    seen.push({ url, init });
    return new Response(body === undefined ? null : JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
  };

  let a = createAdapter({ mode: 'live', baseUrl: MCO_BASE, token: MCO_TOKEN, fetch: reply(201, { document_ref: 'REF-1', sha256: SHA.toUpperCase() }) });
  assert.equal(a.placeholder, true);
  let r = await a.send(doc);
  assert.deepEqual(r, { outcome: 'received', mcoDocumentRef: 'REF-1', receiptSha256: SHA, error: null });
  assert.equal(seen[0].init.method, 'POST');
  assert.ok(seen[0].url.includes('PLACEHOLDER'));

  const failures = [
    reply(503, { message: `boom ${MCO_TOKEN}` }),
    reply(200, { sha256: SHA }),
    reply(200, { document_ref: 'REF-2' }),
    async () => new Response('not json', { status: 200 }),
    async () => { throw new TypeError(`fetch failed for ${MCO_TOKEN}`); },
    async () => { const e = new Error('timed out'); e.name = 'TimeoutError'; throw e; },
  ];
  for (const f of failures) {
    a = createAdapter({ mode: 'live', baseUrl: MCO_BASE, token: MCO_TOKEN, fetch: f });
    r = await a.send(doc);
    assert.equal(r.outcome, 'error');
    assert.equal(r.mcoDocumentRef, null);
    assert.ok(typeof r.error === 'string' && r.error.length > 0);
    assert.ok(!r.error.includes(MCO_TOKEN), 'the MCO token leaked into an error');
  }
});

// 4. The deletion rule ----------------------------------------------------------------

test('mayDeleteStaging: only received, transferred and three equal hashes', () => {
  const ok = { outcome: 'received', recordedStatus: 'transferred', serverSha256: SHA, clientSha256: SHA, receiptSha256: SHA };
  assert.equal(mayDeleteStaging(ok), true);
  assert.equal(mayDeleteStaging({ ...ok, serverSha256: SHA.toUpperCase() }), true);
  assert.equal(mayDeleteStaging({ ...ok, outcome: 'held' }), false);
  assert.equal(mayDeleteStaging({ ...ok, outcome: 'error' }), false);
  assert.equal(mayDeleteStaging({ ...ok, recordedStatus: 'failed' }), false);
  assert.equal(mayDeleteStaging({ ...ok, recordedStatus: undefined }), false);
  assert.equal(mayDeleteStaging({ ...ok, serverSha256: WRONG_SHA }), false);
  assert.equal(mayDeleteStaging({ ...ok, clientSha256: WRONG_SHA }), false);
  assert.equal(mayDeleteStaging({ ...ok, receiptSha256: WRONG_SHA }), false);
  assert.equal(mayDeleteStaging({ ...ok, serverSha256: '', clientSha256: '', receiptSha256: '' }), false);
  assert.equal(mayDeleteStaging(undefined), false);
});

test('checkStagingPath: the path must be this account, this upload, this safe name', () => {
  assert.deepEqual(checkStagingPath(uploadRow()), { ok: true, path: PATH });
  assert.equal(checkStagingPath(uploadRow({ storage_path: `${OTHER_ACCOUNT}/${UPLOAD_ID}/${SAFE_NAME}` })).ok, false);
  assert.equal(checkStagingPath(uploadRow({ storage_path: `${ACCOUNT_ID}/${OTHER_ACCOUNT}/${SAFE_NAME}` })).ok, false);
  assert.equal(checkStagingPath(uploadRow({ storage_path: `${ACCOUNT_ID}/${UPLOAD_ID}/..` })).ok, false);
  assert.equal(checkStagingPath(uploadRow({ storage_path: `${ACCOUNT_ID}/${UPLOAD_ID}/other.pdf` })).ok, false);
  assert.equal(checkStagingPath(uploadRow({ storage_path: `${ACCOUNT_ID}/${UPLOAD_ID}` })).ok, false);
  assert.equal(checkStagingPath(uploadRow({ storage_path: null })).ok, false);
  assert.equal(checkStagingPath(uploadRow({ storage_bucket: 'public' })).ok, false);
});

// 5. One upload ------------------------------------------------------------------------

test('hold: the upload is checked and recorded as held; nothing is sent or deleted', async (t) => {
  forbidNetwork(t);
  const f = fakeDeps({ mode: 'hold' });
  const r = await processUpload(uploadRow(), f.deps);
  assert.deepEqual(f.names(), ['download', 'rpc:hsf_transfer_record']);
  const a = recordArgs(f.calls);
  assert.equal(a.p_mode, 'hold');
  assert.equal(a.p_outcome, 'held');
  assert.equal(a.p_server_sha256, SHA);
  assert.equal(a.p_mco_ref, null);
  assertNoDeletion(f.calls);
  assert.equal(r.action, 'held');
  assert.equal(r.deleted, false);
  assert.equal(r.marked, false);
});

test('hold: an upload already held is left alone, with no download and no new log row', async () => {
  const f = fakeDeps({ mode: 'hold' });
  const r = await processUpload(uploadRow({ status: 'held' }), f.deps);
  assert.equal(f.calls.length, 0);
  assert.equal(r.action, 'skipped');
});

test('fixture success: record received, then delete from Storage, then mark staging deleted', async (t) => {
  forbidNetwork(t);
  const f = fakeDeps({ mode: 'fixture' });
  const r = await processUpload(uploadRow({ status: 'held' }), f.deps);
  assert.deepEqual(f.names(), ['download', 'rpc:hsf_transfer_record', 'remove', 'rpc:hsf_mark_staging_deleted']);
  const a = recordArgs(f.calls);
  assert.equal(a.p_outcome, 'received');
  assert.equal(a.p_mode, 'fixture');
  assert.equal(a.p_server_sha256, SHA);
  assert.equal(a.p_receipt_sha256, SHA);
  assert.equal(a.p_mco_ref, 'FIXTURE-' + UPLOAD_ID);
  assert.equal(f.calls[2][1], PATH);
  assert.deepEqual(f.calls[3][2], { p_upload_id: UPLOAD_ID });
  assert.equal(r.action, 'staging_deleted');
  assert.equal(r.outcome, 'received');
  assert.equal(r.deleted, true);
  assert.equal(r.marked, true);
  assert.equal(r.error, null);
});

test('hash mismatch (browser against server): recorded, never sent, never deleted', async () => {
  let sent = 0;
  const adapter = { async send() { sent++; return { outcome: 'received', mcoDocumentRef: 'X', receiptSha256: SHA }; } };
  const f = fakeDeps({ mode: 'fixture', adapter });
  const r = await processUpload(uploadRow({ sha256_client: WRONG_SHA }), f.deps);
  assert.equal(sent, 0, 'a file that does not match the browser fingerprint was sent to MCO');
  const a = recordArgs(f.calls);
  assert.equal(a.p_outcome, 'hash_mismatch');
  assert.equal(a.p_server_sha256, SHA);
  assertNoDeletion(f.calls);
  assert.equal(r.action, 'hash_mismatch');
  assert.equal(r.deleted, false);
});

test('hash mismatch (receipt): MCO acknowledged a different fingerprint, so nothing is deleted', async () => {
  const adapter = { async send() { return { outcome: 'received', mcoDocumentRef: 'REF-9', receiptSha256: WRONG_SHA, error: null }; } };
  const f = fakeDeps({ mode: 'live', adapter });
  const r = await processUpload(uploadRow(), f.deps);
  const a = recordArgs(f.calls);
  assert.equal(a.p_outcome, 'hash_mismatch');
  assert.equal(a.p_mco_ref, 'REF-9');
  assert.equal(a.p_receipt_sha256, WRONG_SHA);
  assertNoDeletion(f.calls);
  assert.equal(r.action, 'hash_mismatch');
});

test('storage delete failure: the upload is not marked staging deleted', async () => {
  const f = fakeDeps({ mode: 'fixture', removeFails: true });
  const r = await processUpload(uploadRow(), f.deps);
  assert.deepEqual(f.names(), ['download', 'rpc:hsf_transfer_record', 'remove']);
  assert.equal(r.action, 'delete_failed');
  assert.equal(r.deleted, false);
  assert.equal(r.marked, false);
  assert.match(r.error, /could not be removed/);

  const g = fakeDeps({ mode: 'fixture', removeReturnsFalse: true });
  const r2 = await processUpload(uploadRow(), g.deps);
  assert.ok(!g.names().includes('rpc:hsf_mark_staging_deleted'));
  assert.equal(r2.action, 'delete_failed');
});

test('adapter error outcome: recorded as error, nothing deleted', async () => {
  const adapter = { async send() { return { outcome: 'error', mcoDocumentRef: null, receiptSha256: null, error: 'MyClinicOnline replied with HTTP 503.' }; } };
  const f = fakeDeps({ mode: 'live', adapter });
  const r = await processUpload(uploadRow(), f.deps);
  const a = recordArgs(f.calls);
  assert.equal(a.p_outcome, 'error');
  assert.equal(a.p_error, 'MyClinicOnline replied with HTTP 503.');
  assertNoDeletion(f.calls);
  assert.equal(r.action, 'error');
});

test('adapter that throws, or answers nonsense, or omits the reference: error, nothing deleted', async () => {
  const adapters = [
    { async send() { throw new Error('socket closed'); } },
    { async send() { return { outcome: 'probably' }; } },
    { async send() { return null; } },
    { async send() { return { outcome: 'received', mcoDocumentRef: '', receiptSha256: SHA }; } },
  ];
  for (const adapter of adapters) {
    const f = fakeDeps({ mode: 'live', adapter });
    const r = await processUpload(uploadRow(), f.deps);
    assert.equal(recordArgs(f.calls).p_outcome, 'error');
    assertNoDeletion(f.calls);
    assert.equal(r.deleted, false);
  }
});

test('download failure: recorded as error, nothing sent, nothing deleted', async () => {
  let sent = 0;
  const adapter = { async send() { sent++; return { outcome: 'received', mcoDocumentRef: 'X', receiptSha256: SHA }; } };
  const f = fakeDeps({ mode: 'fixture', adapter, downloadFails: true });
  const r = await processUpload(uploadRow(), f.deps);
  assert.equal(sent, 0);
  assert.equal(recordArgs(f.calls).p_outcome, 'error');
  assertNoDeletion(f.calls);
  assert.equal(r.action, 'error');
});

test('the database must confirm the transfer before anything is deleted', async () => {
  for (const recordReply of [null, {}, { status: 'failed' }, { status: 'uploaded' }, 'transferred']) {
    const f = fakeDeps({ mode: 'fixture', recordReply });
    const r = await processUpload(uploadRow(), f.deps);
    assertNoDeletion(f.calls);
    assert.equal(r.action, 'not_confirmed');
  }
  const g = fakeDeps({ mode: 'fixture', rpcFails: ['hsf_transfer_record'] });
  const r = await processUpload(uploadRow(), g.deps);
  assertNoDeletion(g.calls);
  assert.equal(r.action, 'record_failed');
});

test('a path belonging to another account is never read or deleted', async () => {
  const f = fakeDeps({ mode: 'fixture' });
  const r = await processUpload(uploadRow({ storage_path: `${OTHER_ACCOUNT}/${UPLOAD_ID}/${SAFE_NAME}` }), f.deps);
  assert.ok(!f.calls.some((c) => c[0] === 'download'));
  assertNoDeletion(f.calls);
  assert.equal(recordArgs(f.calls).p_outcome, 'error');
  assert.equal(r.action, 'error');
});

test('mark failure after a confirmed delete is reported, not hidden', async () => {
  const f = fakeDeps({ mode: 'fixture', rpcFails: ['hsf_mark_staging_deleted'] });
  const r = await processUpload(uploadRow(), f.deps);
  assert.equal(r.deleted, true);
  assert.equal(r.marked, false);
  assert.equal(r.action, 'mark_failed');
});

test('rows that are not waiting for transfer are skipped untouched', async () => {
  for (const status of ['transferred', 'staging_deleted', 'failed', 'awaiting_upload']) {
    const f = fakeDeps({ mode: 'fixture' });
    const r = await processUpload(uploadRow({ status }), f.deps);
    assert.equal(f.calls.length, 0);
    assert.equal(r.action, 'skipped');
  }
});

// 6. One run ------------------------------------------------------------------------------

// The run level fake: msp_env_get and hsf_transfer_queue here, everything else
// through the per upload fake (which logs its own calls).
function runDeps(modeValue, opts) {
  const o = opts || {};
  const f = fakeDeps();
  const rpc = async (fn, args) => {
    if (fn === 'msp_env_get') {
      f.calls.push(['rpc', fn, args]);
      assert.deepEqual(args, { p_key: MODE_PARAMETER });
      if (o.modeFails) throw new Error('msp_env_get was refused (HTTP 500)');
      return modeValue;
    }
    if (fn === 'hsf_transfer_queue') {
      f.calls.push(['rpc', fn, args]);
      assert.deepEqual(args, { p_limit: QUEUE_LIMIT });
      return o.queue || [uploadRow()];
    }
    return f.deps.rpc(fn, args);
  };
  return { f, deps: { rpc, download: f.deps.download, remove: f.deps.remove, createAdapter, mco: o.mco, allowFixture: o.allowFixture } };
}

test('run: hold is the default when the parameter is unset', async (t) => {
  forbidNetwork(t);
  for (const v of [null, '', '  ']) {
    const { f, deps } = runDeps(v);
    const s = await runTransfer(deps);
    assert.equal(s.ok, true);
    assert.equal(s.mode, 'hold');
    assert.equal(s.defaulted, true);
    assert.equal(s.results[0].action, 'held');
    assertNoDeletion(f.calls);
  }
  assert.deepEqual(resolveMode('HOLD'), { ok: true, mode: 'hold', defaulted: false });
});

test('run: live without MCO_BASE_URL and MCO_API_TOKEN refuses before reading the queue', async (t) => {
  forbidNetwork(t);
  const { f, deps } = runDeps('live', { mco: { baseUrl: '', token: '' } });
  const s = await runTransfer(deps);
  assert.equal(s.ok, false);
  assert.equal(s.refused, PENDING_MESSAGE);
  assert.deepEqual(f.names(), ['rpc:msp_env_get']);
});

test('run: fixture is refused unless the environment allows it; unknown modes are refused', async () => {
  let r = runDeps('fixture');
  let s = await runTransfer(r.deps);
  assert.equal(s.ok, false);
  assert.match(s.refused, /Fixture mode is for tests only/);
  assert.deepEqual(r.f.names(), ['rpc:msp_env_get']);

  r = runDeps('Fixture', { allowFixture: true });
  s = await runTransfer(r.deps);
  assert.equal(s.ok, true);
  assert.equal(s.results[0].action, 'staging_deleted');

  for (const bad of ['send', 42, { mode: 'live' }]) {
    r = runDeps(bad);
    s = await runTransfer(r.deps);
    assert.equal(s.ok, false);
    assert.deepEqual(r.f.names(), ['rpc:msp_env_get']);
  }

  r = runDeps('hold', { modeFails: true });
  s = await runTransfer(r.deps);
  assert.equal(s.ok, false);
  assert.match(s.refused, /could not be read/);
});

test('run: rows are processed one at a time and counted by action', async () => {
  const second = '2e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6c';
  const queue = [
    uploadRow(),
    uploadRow({ id: second, storage_path: `${ACCOUNT_ID}/${second}/${SAFE_NAME}`, sha256_client: WRONG_SHA }),
  ];
  const { f, deps } = runDeps('fixture', { allowFixture: true, queue });
  const s = await runTransfer(deps);
  assert.equal(s.ok, true);
  assert.equal(s.processed, 2);
  assert.deepEqual(s.counts, { staging_deleted: 1, hash_mismatch: 1 });
  const removed = f.calls.filter((c) => c[0] === 'remove').map((c) => c[1]);
  assert.deepEqual(removed, [PATH], 'only the matching upload was deleted');
  for (const res of s.results) assert.ok(!JSON.stringify(res).includes('Risk assessment'), 'a file name reached the run report');
});

// 7. Service caller check -------------------------------------------------------------------

test('isServiceCaller: only the service role key as a bearer token', () => {
  assert.equal(isServiceCaller(`Bearer ${SERVICE_KEY}`, SERVICE_KEY), true);
  assert.equal(isServiceCaller(`bearer ${SERVICE_KEY}`, SERVICE_KEY), true);
  assert.equal(isServiceCaller(`Bearer ${SERVICE_KEY}x`, SERVICE_KEY), false);
  assert.equal(isServiceCaller('Bearer sb_publishable_anything', SERVICE_KEY), false);
  assert.equal(isServiceCaller(SERVICE_KEY, SERVICE_KEY), false);
  assert.equal(isServiceCaller('', SERVICE_KEY), false);
  assert.equal(isServiceCaller(`Bearer ${SERVICE_KEY}`, ''), false);
  assert.equal(isServiceCaller(null, SERVICE_KEY), false);
});

// 8. Supabase bindings, end to end over a fake Supabase ------------------------------------

function fakeSupabase(opts) {
  const o = opts || {};
  const calls = [];
  const reply = (status, body) => new Response(body === undefined ? null : JSON.stringify(body), {
    status, headers: { 'content-type': 'application/json' },
  });
  const fetchImpl = async (url, init) => {
    const i = init || {};
    const c = { url: String(url), method: (i.method || 'GET').toUpperCase(), headers: Object.assign({}, i.headers), body: i.body };
    calls.push(c);
    assert.equal(c.headers.apikey, SERVICE_KEY);
    assert.equal(c.headers.Authorization, `Bearer ${SERVICE_KEY}`);
    const rpcPrefix = `${SUPABASE_URL}/rest/v1/rpc/`;
    if (c.url.startsWith(rpcPrefix)) {
      const fn = c.url.slice(rpcPrefix.length);
      const args = JSON.parse(c.body);
      if (fn === 'msp_env_get') return reply(200, o.mode ?? 'fixture');
      if (fn === 'hsf_transfer_queue') return reply(200, [uploadRow()]);
      if (fn === 'hsf_transfer_record') {
        const ok = args.p_outcome === 'received' && args.p_server_sha256 === SHA && args.p_receipt_sha256 === SHA;
        return reply(200, { upload_id: args.p_upload_id, status: ok ? 'transferred' : args.p_outcome });
      }
      if (fn === 'hsf_mark_staging_deleted') {
        if (o.markRefused) return reply(400, { message: `refused ${SERVICE_KEY}` });
        return reply(200, { upload_id: args.p_upload_id, status: 'staging_deleted' });
      }
      return reply(404, { message: 'no such function' });
    }
    if (c.method === 'GET' && c.url === `${SUPABASE_URL}/storage/v1/object/${STAGING_BUCKET}/${PATH}`) {
      if (o.downloadStatus) return new Response('nope', { status: o.downloadStatus });
      return new Response(BYTES, { status: 200, headers: { 'content-type': 'application/pdf' } });
    }
    if (c.method === 'DELETE' && c.url === `${SUPABASE_URL}/storage/v1/object/${STAGING_BUCKET}`) {
      if (o.deleteStatus) return reply(o.deleteStatus, { message: 'Storage failure' });
      const { prefixes } = JSON.parse(c.body);
      assert.deepEqual(prefixes, [PATH]);
      return reply(200, o.deleteEmpty ? [] : [{ name: PATH, bucket_id: STAGING_BUCKET }]);
    }
    return reply(404, { message: 'unexpected call' });
  };
  return { calls, fetchImpl };
}

function steps(calls) {
  return calls.map((c) => {
    if (c.url.includes('/rest/v1/rpc/')) return `rpc:${c.url.split('/rest/v1/rpc/')[1]}`;
    return `${c.method} storage`;
  });
}

async function runOverRest(opts) {
  const sb = fakeSupabase(opts);
  const io = createSupabaseIo({ url: SUPABASE_URL + '/', serviceKey: SERVICE_KEY, fetch: sb.fetchImpl });
  const s = await runTransfer({ rpc: io.rpc, download: io.download, remove: io.remove, createAdapter, allowFixture: true });
  return { s, sb };
}

test('end to end over REST: fixture success runs the six calls in order', async () => {
  const { s, sb } = await runOverRest({});
  assert.deepEqual(steps(sb.calls), [
    'rpc:msp_env_get', 'rpc:hsf_transfer_queue', 'GET storage', 'rpc:hsf_transfer_record', 'DELETE storage', 'rpc:hsf_mark_staging_deleted',
  ]);
  assert.equal(s.results[0].action, 'staging_deleted');
  const del = sb.calls.find((c) => c.method === 'DELETE');
  assert.deepEqual(JSON.parse(del.body), { prefixes: [PATH] });
});

test('end to end over REST: hold never calls DELETE', async () => {
  const { s, sb } = await runOverRest({ mode: 'hold' });
  assert.deepEqual(steps(sb.calls), ['rpc:msp_env_get', 'rpc:hsf_transfer_queue', 'GET storage', 'rpc:hsf_transfer_record']);
  assert.equal(s.results[0].action, 'held');
});

test('end to end over REST: Storage not confirming the delete stops the mark', async () => {
  for (const o of [{ deleteEmpty: true }, { deleteStatus: 500 }]) {
    const { s, sb } = await runOverRest(o);
    assert.ok(!steps(sb.calls).includes('rpc:hsf_mark_staging_deleted'));
    assert.equal(s.results[0].action, 'delete_failed');
  }
});

test('end to end over REST: an unreadable object is an error and nothing is deleted', async () => {
  const { s, sb } = await runOverRest({ downloadStatus: 404 });
  assert.ok(!steps(sb.calls).includes('DELETE storage'));
  assert.equal(s.results[0].action, 'error');
  assert.match(s.results[0].error, /HTTP 404/);
});

test('REST bindings never put the service role key in an error', async () => {
  const { s } = await runOverRest({ markRefused: true });
  assert.equal(s.results[0].action, 'mark_failed');
  assert.ok(!JSON.stringify(s).includes(SERVICE_KEY), 'the service role key leaked into the run report');
  assert.throws(() => createSupabaseIo({ url: SUPABASE_URL }), /service role key are required/);
  assert.throws(() => encodeStagingPath('../../etc/passwd'), /not usable/);
  assert.throws(() => encodeStagingPath(`${ACCOUNT_ID}/${UPLOAD_ID}/a b.pdf`), /not usable/);
  const io = createSupabaseIo({ url: SUPABASE_URL, serviceKey: SERVICE_KEY, fetch: async () => { throw new Error('unused'); } });
  await assert.rejects(() => io.rpc('drop table; --', {}), /unexpected function name/);
});

// 9. House rules and portability of the shipped files ---------------------------------------

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const SHIPPED = {
  adapter: here('../../supabase/functions/_shared/mco-adapter.js'),
  core: here('../../supabase/functions/_shared/transfer-core.js'),
  worker: here('../../supabase/functions/hsf-mco-transfer/index.ts'),
};

test('shipped files: no em or en dashes, no compliance stamps, no secrets', () => {
  for (const [name, file] of Object.entries(SHIPPED)) {
    const src = readFileSync(file, 'utf8');
    assert.ok(!/[\u2013\u2014]/.test(src), `${name} contains an em or en dash`);
    assert.ok(!/compliant/i.test(src), `${name} says compliant`);
    assert.ok(!/eyJ[A-Za-z0-9_-]{10,}/.test(src), `${name} carries what looks like a JWT`);
    assert.ok(!/sb_secret_/.test(src), `${name} carries a secret key`);
  }
});

test('shared modules use no Deno or Node specific APIs', () => {
  for (const file of [SHIPPED.adapter, SHIPPED.core]) {
    const src = readFileSync(file, 'utf8').replace(/^\s*\/\/.*$/gm, '');
    for (const api of [/\bDeno\./, /\bprocess\.(env|exit|argv|version)/, /\brequire\(/, /\bBuffer\b/, /['"]node:/]) {
      assert.ok(!api.test(src), `${file} uses ${api}`);
    }
  }
  const worker = readFileSync(SHIPPED.worker, 'utf8');
  assert.match(worker, /from "\.\.\/_shared\/mco-adapter\.js"/);
  assert.match(worker, /from "\.\.\/_shared\/transfer-core\.js"/);
  assert.match(worker, /isServiceCaller\(/);
  assert.ok(!/\bfetch\(/.test(worker), 'the worker makes its own network calls instead of using the tested bindings');
});
