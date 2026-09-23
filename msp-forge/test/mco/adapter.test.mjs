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
  createSupabaseIo, encodeStagingPath, checkCleanupItem, cleanupUpload,
  QUEUE_LIMIT, CLAIM_LIMIT, CLEANUP_LIMIT, STALE_UPLOAD_HOURS, MODE_PARAMETER, STAGING_BUCKET, RPC,
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
    async remove(path, ropts) {
      calls.push(['remove', path, ropts]);
      if (o.removeFails) throw new Error('Storage refused the removal (HTTP 500).');
      if (o.removeReturnsFalse) return false;
      if (o.removeAbsent && ropts && ropts.allowAbsent) return 'absent';
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

test('an upload blocked by a consent withdrawal is never read, sent or deleted; it is recorded as an error', async () => {
  let sent = 0;
  const adapter = { async send() { sent++; return { outcome: 'received', mcoDocumentRef: 'X', receiptSha256: SHA }; } };
  for (const status of ['uploaded', 'held', 'transferring']) {
    const f = fakeDeps({ mode: 'fixture', adapter });
    const r = await processUpload(uploadRow({ status, transfer_blocked_reason: 'consent withdrawn' }), f.deps);
    assert.deepEqual(f.names(), ['rpc:hsf_transfer_record'], status);
    assert.equal(recordArgs(f.calls).p_outcome, 'error');
    assert.match(recordArgs(f.calls).p_error, /consent was withdrawn/);
    assert.equal(r.action, 'error');
    assert.equal(r.deleted, false);
  }
  assert.equal(sent, 0);
  // An empty reason is no block.
  const g = fakeDeps({ mode: 'fixture' });
  assert.equal((await processUpload(uploadRow({ transfer_blocked_reason: null }), g.deps)).action, 'staging_deleted');
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

// A cleanup queue row as hsf_transfer_cleanup_queue returns it (contract 9.5).
function cleanupRow(id, reason, over) {
  return Object.assign({ upload_id: id, storage_path: `${ACCOUNT_ID}/${id}/${SAFE_NAME}`, reason }, over || {});
}
const FAILED_ID = '3e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6d';
const REJECTED_ID = '4e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6e';
const LEFTOVER_ID = '5e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6f';

// The run level fake for the contract 9.5 functions: hsf_transfer_mode,
// hsf_transfer_claim, hsf_sweep_stale_uploads and hsf_transfer_cleanup_queue
// here; hsf_transfer_record and hsf_mark_staging_deleted through the per upload
// fake (which logs its own calls). The retired msp_env_get and
// hsf_transfer_queue fail the test if they are ever called.
function runDeps(modeValue, opts) {
  const o = opts || {};
  const f = fakeDeps(o.fake);
  const statusOf = new Map((Array.isArray(o.cleanup) ? o.cleanup : []).filter((r) => r && r.upload_id).map((r) => [r.upload_id, r.reason]));
  const rpc = async (fn, args) => {
    if (fn === 'msp_env_get' || fn === 'hsf_transfer_queue') throw new Error(`the retired function ${fn} was called`);
    if (fn === RPC.mode) {
      f.calls.push(['rpc', fn, args]);
      assert.deepEqual(args, {});
      if (o.modeFails) throw new Error('hsf_transfer_mode was refused (HTTP 500)');
      return modeValue;
    }
    if (fn === RPC.claim) {
      f.calls.push(['rpc', fn, args]);
      assert.deepEqual(args, { p_limit: CLAIM_LIMIT });
      if (o.claimFails) throw new Error('hsf_transfer_claim was refused (HTTP 500)');
      return o.queue || [uploadRow()];
    }
    if (fn === RPC.sweep) {
      f.calls.push(['rpc', fn, args]);
      assert.deepEqual(args, { p_hours: STALE_UPLOAD_HOURS });
      if (o.sweepFails) throw new Error('hsf_sweep_stale_uploads was refused (HTTP 500)');
      return o.swept ?? 0;
    }
    if (fn === RPC.cleanup) {
      f.calls.push(['rpc', fn, args]);
      assert.deepEqual(args, { p_limit: CLEANUP_LIMIT });
      if (o.cleanupFails) throw new Error('hsf_transfer_cleanup_queue was refused (HTTP 500)');
      return o.cleanup === undefined ? [] : o.cleanup;
    }
    if (fn === RPC.markDeleted && statusOf.has(args.p_upload_id)) {
      f.calls.push(['rpc', fn, args]);
      if (o.markStatus) return { upload_id: args.p_upload_id, status: o.markStatus };
      const was = statusOf.get(args.p_upload_id);
      return { upload_id: args.p_upload_id, status: was === 'transferred' ? 'staging_deleted' : was };
    }
    return f.deps.rpc(fn, args);
  };
  return {
    f,
    deps: {
      rpc, download: f.deps.download, remove: f.deps.remove,
      createAdapter: o.createAdapter || createAdapter, mco: o.mco, allowFixture: o.allowFixture,
    },
  };
}

const rpcOrder = (calls) => calls.filter((c) => c[0] === 'rpc').map((c) => c[1]);

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

test('run: live without MCO_BASE_URL and MCO_API_TOKEN refuses before claiming anything', async (t) => {
  forbidNetwork(t);
  const { f, deps } = runDeps('live', { mco: { baseUrl: '', token: '' } });
  const s = await runTransfer(deps);
  assert.equal(s.ok, false);
  assert.equal(s.refused, PENDING_MESSAGE);
  assert.deepEqual(f.names(), ['rpc:hsf_transfer_mode']);
});

test('run: fixture is refused unless the environment allows it; unknown modes are refused', async () => {
  let r = runDeps('fixture');
  let s = await runTransfer(r.deps);
  assert.equal(s.ok, false);
  assert.match(s.refused, /Fixture mode is for tests only/);
  assert.deepEqual(r.f.names(), ['rpc:hsf_transfer_mode']);

  r = runDeps('Fixture', { allowFixture: true });
  s = await runTransfer(r.deps);
  assert.equal(s.ok, true);
  assert.equal(s.results[0].action, 'staging_deleted');

  for (const bad of ['send', 42, { mode: 'live' }]) {
    r = runDeps(bad);
    s = await runTransfer(r.deps);
    assert.equal(s.ok, false);
    assert.deepEqual(r.f.names(), ['rpc:hsf_transfer_mode']);
  }

  r = runDeps('hold', { modeFails: true });
  s = await runTransfer(r.deps);
  assert.equal(s.ok, false);
  assert.match(s.refused, /could not be read/);
  assert.deepEqual(r.f.names(), ['rpc:hsf_transfer_mode']);
});

test('run: the mode comes from hsf_transfer_mode() and the rows from hsf_transfer_claim(10), never msp_env_get or hsf_transfer_queue', async () => {
  assert.equal(RPC.mode, 'hsf_transfer_mode');
  assert.equal(RPC.claim, 'hsf_transfer_claim');
  assert.equal(CLAIM_LIMIT, 10);
  assert.equal(QUEUE_LIMIT, CLAIM_LIMIT);
  const { f, deps } = runDeps('hold');
  const s = await runTransfer(deps);
  assert.equal(s.ok, true);
  assert.deepEqual(rpcOrder(f.calls).slice(0, 2), ['hsf_transfer_mode', 'hsf_transfer_claim']);
  const src = readFileSync(fileURLToPath(new URL('../../supabase/functions/_shared/transfer-core.js', import.meta.url)), 'utf8');
  assert.ok(!/msp_env_get/.test(src), 'the worker still names msp_env_get');
  assert.ok(!/hsf_transfer_queue/.test(src), 'the worker still names hsf_transfer_queue');
});

test('run: rows the claim marked transferring are transferred in fixture mode and held in hold mode', async (t) => {
  forbidNetwork(t);
  let r = runDeps('fixture', { allowFixture: true, queue: [uploadRow({ status: 'transferring' })] });
  let s = await runTransfer(r.deps);
  assert.equal(s.results[0].action, 'staging_deleted');
  assert.equal(recordArgs(r.f.calls).p_outcome, 'received');

  r = runDeps('hold', { queue: [uploadRow({ status: 'transferring' })] });
  s = await runTransfer(r.deps);
  assert.equal(s.results[0].action, 'held');
  assert.equal(recordArgs(r.f.calls).p_outcome, 'held');
  assertNoDeletion(r.f.calls);
});

test('run: a claim that fails or is not a list refuses the run: no sweep, no cleanup, nothing deleted', async () => {
  for (const o of [{ claimFails: true }, { queue: { rows: [] } }]) {
    const { f, deps } = runDeps('fixture', Object.assign({ allowFixture: true, cleanup: [cleanupRow(FAILED_ID, 'failed')] }, o));
    const s = await runTransfer(deps);
    assert.equal(s.ok, false);
    assert.match(s.refused, /claim/);
    assert.deepEqual(rpcOrder(f.calls), ['hsf_transfer_mode', 'hsf_transfer_claim']);
    assert.ok(!f.calls.some((c) => c[0] === 'remove'));
    assert.equal(s.sweep.ran, false);
    assert.equal(s.cleanup.ran, false);
  }
});

test('run: a refused mode never sweeps, never cleans up and never deletes', async () => {
  for (const [mode, o] of [['fixture', {}], ['live', { mco: {} }], ['nonsense', {}], ['hold', { modeFails: true }]]) {
    const { f, deps } = runDeps(mode, Object.assign({ cleanup: [cleanupRow(FAILED_ID, 'failed')] }, o));
    const s = await runTransfer(deps);
    assert.equal(s.ok, false, mode);
    assert.deepEqual(rpcOrder(f.calls), ['hsf_transfer_mode'], mode);
    assert.ok(!f.calls.some((c) => c[0] === 'remove' || c[0] === 'download'), mode);
  }
});

test('run: held, error and mismatch outcomes delete nothing in the transfer pass', async (t) => {
  forbidNetwork(t);
  // hold
  let r = runDeps('hold');
  let s = await runTransfer(r.deps);
  assert.equal(s.results[0].action, 'held');
  assertNoDeletion(r.f.calls);

  // error: the adapter answers error; hsf_transfer_record returns the upload to 'uploaded'
  const erring = () => ({ mode: 'live', async send() { return { outcome: 'error', mcoDocumentRef: null, receiptSha256: null, error: 'MyClinicOnline replied with HTTP 503.' }; } });
  r = runDeps('live', { createAdapter: erring, mco: { baseUrl: MCO_BASE, token: MCO_TOKEN } });
  s = await runTransfer(r.deps);
  assert.equal(s.results[0].action, 'error');
  assert.equal(s.results[0].deleted, false);
  assert.equal(recordArgs(r.f.calls).p_outcome, 'error');
  assertNoDeletion(r.f.calls);

  // mismatch
  r = runDeps('fixture', { allowFixture: true, queue: [uploadRow({ sha256_client: WRONG_SHA })] });
  s = await runTransfer(r.deps);
  assert.equal(s.results[0].action, 'hash_mismatch');
  assert.equal(s.results[0].deleted, false);
  assertNoDeletion(r.f.calls);
});

test('run: every run sweeps stale uploads once, with 24 hours, after the transfer pass and before the cleanup', async () => {
  assert.equal(STALE_UPLOAD_HOURS, 24);
  const { f, deps } = runDeps('hold', { swept: 3 });
  const s = await runTransfer(deps);
  assert.equal(s.ok, true);
  assert.deepEqual(s.sweep, { ran: true, failed: 3, error: null });
  assert.deepEqual(rpcOrder(f.calls), ['hsf_transfer_mode', 'hsf_transfer_claim', 'hsf_transfer_record', 'hsf_sweep_stale_uploads', 'hsf_transfer_cleanup_queue']);
  assert.equal(f.calls.filter((c) => c[1] === RPC.sweep).length, 1);
});

test('run: the sweep runs even when nothing was claimed', async () => {
  const { f, deps } = runDeps('hold', { queue: [] });
  const s = await runTransfer(deps);
  assert.equal(s.processed, 0);
  assert.deepEqual(rpcOrder(f.calls), ['hsf_transfer_mode', 'hsf_transfer_claim', 'hsf_sweep_stale_uploads', 'hsf_transfer_cleanup_queue']);
});

test('run cleanup: transferred leftovers, failed and rejected rows are deleted, then marked, one by one', async () => {
  assert.equal(CLEANUP_LIMIT, 25);
  const cleanup = [cleanupRow(LEFTOVER_ID, 'transferred'), cleanupRow(FAILED_ID, 'failed'), cleanupRow(REJECTED_ID, 'rejected')];
  const { f, deps } = runDeps('hold', { queue: [], cleanup });
  const s = await runTransfer(deps);
  assert.equal(s.ok, true);
  assert.equal(s.cleanup.listed, 3);
  assert.deepEqual(s.cleanup.counts, { removed: 3 });
  // For each row: remove (allowing an object already gone), then mark.
  const tail = f.calls.slice(f.calls.findIndex((c) => c[1] === RPC.cleanup) + 1);
  assert.deepEqual(tail.map((c) => (c[0] === 'rpc' ? `rpc:${c[1]}:${c[2].p_upload_id}` : `remove:${c[1]}`)), [
    `remove:${cleanup[0].storage_path}`, `rpc:hsf_mark_staging_deleted:${LEFTOVER_ID}`,
    `remove:${cleanup[1].storage_path}`, `rpc:hsf_mark_staging_deleted:${FAILED_ID}`,
    `remove:${cleanup[2].storage_path}`, `rpc:hsf_mark_staging_deleted:${REJECTED_ID}`,
  ]);
  for (const c of tail.filter((x) => x[0] === 'remove')) assert.deepEqual(c[2], { allowAbsent: true });
  for (const r of s.cleanup.results) {
    assert.equal(r.deleted, true);
    assert.equal(r.marked, true);
    assert.equal(r.error, null);
  }
  assert.deepEqual(s.cleanup.results.map((r) => r.reason), ['transferred', 'failed', 'rejected']);
  assert.ok(!JSON.stringify(s).includes(SAFE_NAME), 'a staged file name reached the run report');
});

test('run cleanup: an object already gone is marked once Storage confirms it is absent', async () => {
  const { deps } = runDeps('hold', { queue: [], cleanup: [cleanupRow(FAILED_ID, 'failed')], fake: { removeAbsent: true } });
  const s = await runTransfer(deps);
  assert.deepEqual(s.cleanup.counts, { already_absent: 1 });
  assert.equal(s.cleanup.results[0].absent, true);
  assert.equal(s.cleanup.results[0].deleted, false);
  assert.equal(s.cleanup.results[0].marked, true);
});

test('run cleanup: nothing is marked unless Storage confirmed the removal', async () => {
  for (const fake of [{ removeFails: true }, { removeReturnsFalse: true }]) {
    const { f, deps } = runDeps('hold', { queue: [], cleanup: [cleanupRow(FAILED_ID, 'failed')], fake });
    const s = await runTransfer(deps);
    assert.deepEqual(s.cleanup.counts, { delete_failed: 1 });
    assert.ok(!f.calls.some((c) => c[0] === 'rpc' && c[1] === RPC.markDeleted), JSON.stringify(fake));
    assert.equal(s.cleanup.results[0].marked, false);
  }
});

test('run cleanup: a row whose path is not its own, or whose status is wrong, is skipped untouched', async () => {
  const bad = [
    cleanupRow(FAILED_ID, 'failed', { storage_path: `${ACCOUNT_ID}/${UPLOAD_ID}/${SAFE_NAME}` }),
    cleanupRow(FAILED_ID, 'failed', { storage_path: `${ACCOUNT_ID}/${FAILED_ID}/..` }),
    cleanupRow(FAILED_ID, 'failed', { storage_path: `${ACCOUNT_ID}/${FAILED_ID}` }),
    cleanupRow(FAILED_ID, 'failed', { storage_path: `../${FAILED_ID}/${SAFE_NAME}` }),
    cleanupRow(FAILED_ID, 'failed', { storage_path: null }),
    cleanupRow(FAILED_ID, 'failed', { client_account_id: OTHER_ACCOUNT }),
    cleanupRow(FAILED_ID, 'held', { status: 'held' }),
    cleanupRow(FAILED_ID, 'failed', { status: 'failed', transfer_blocked_reason: 'consent withdrawn' }),
    cleanupRow('not-a-uuid', 'failed'),
    null,
    'text',
  ];
  const { f, deps } = runDeps('hold', { queue: [], cleanup: bad });
  const s = await runTransfer(deps);
  assert.equal(s.cleanup.listed, bad.length);
  assert.deepEqual(s.cleanup.counts, { skipped: bad.length });
  assert.ok(!f.calls.some((c) => c[0] === 'remove'));
  assert.ok(!f.calls.some((c) => c[0] === 'rpc' && c[1] === RPC.markDeleted));
});

test('run cleanup: a mark reply with an unexpected status is reported as mark_failed', async () => {
  const { deps } = runDeps('hold', { queue: [], cleanup: [cleanupRow(FAILED_ID, 'failed')], markStatus: 'transferred' });
  const s = await runTransfer(deps);
  assert.deepEqual(s.cleanup.counts, { mark_failed: 1 });
  assert.equal(s.cleanup.results[0].deleted, true);
  assert.equal(s.cleanup.results[0].marked, false);
});

test('run cleanup: at most CLEANUP_LIMIT rows are handled in one run', async () => {
  const many = Array.from({ length: CLEANUP_LIMIT + 5 }, (_, i) => {
    const id = `${String(i).padStart(8, '0')}-5a4f-4e3d-8c2b-1a0f9e8d7c6f`;
    return cleanupRow(id, 'failed');
  });
  const { f, deps } = runDeps('hold', { queue: [], cleanup: many });
  const s = await runTransfer(deps);
  assert.equal(s.cleanup.results.length, CLEANUP_LIMIT);
  assert.equal(f.calls.filter((c) => c[0] === 'remove').length, CLEANUP_LIMIT);
});

test('run: a sweep failure or an unreadable cleanup queue is reported and the transfer results stand', async () => {
  let r = runDeps('fixture', { allowFixture: true, sweepFails: true, cleanup: [cleanupRow(FAILED_ID, 'failed')] });
  let s = await runTransfer(r.deps);
  assert.equal(s.ok, true);
  assert.equal(s.results[0].action, 'staging_deleted');
  assert.match(s.sweep.error, /sweep could not run/);
  assert.deepEqual(s.cleanup.counts, { removed: 1 }, 'the cleanup still runs after a sweep failure');

  for (const o of [{ cleanupFails: true }, { cleanup: { rows: [] } }]) {
    r = runDeps('hold', Object.assign({ queue: [] }, o));
    s = await runTransfer(r.deps);
    assert.equal(s.ok, true);
    assert.equal(s.cleanup.ran, true);
    assert.ok(typeof s.cleanup.error === 'string' && s.cleanup.error.length > 0);
    assert.ok(!r.f.calls.some((c) => c[0] === 'remove'));
  }

  r = runDeps('hold', { queue: [], cleanup: null });
  s = await runTransfer(r.deps);
  assert.equal(s.cleanup.error, null, 'a null cleanup reply is an empty queue');
  assert.equal(s.cleanup.listed, 0);
});

test('checkCleanupItem and cleanupUpload: the path must be this upload under a company account', async () => {
  assert.deepEqual(checkCleanupItem(cleanupRow(FAILED_ID, 'failed')), { ok: true, id: FAILED_ID, path: `${ACCOUNT_ID}/${FAILED_ID}/${SAFE_NAME}` });
  assert.equal(checkCleanupItem(cleanupRow(FAILED_ID, 'failed', { client_account_id: ACCOUNT_ID.toUpperCase() })).ok, true);
  assert.equal(checkCleanupItem(cleanupRow(FAILED_ID, 'failed', { storage_path: `nope/${FAILED_ID}/${SAFE_NAME}` })).ok, false);
  assert.equal(checkCleanupItem(cleanupRow(FAILED_ID, 'failed', { storage_path: `${ACCOUNT_ID}/${FAILED_ID}/a b.pdf` })).ok, false);
  for (const status of ['transferred', 'failed', 'rejected']) {
    assert.equal(checkCleanupItem(cleanupRow(FAILED_ID, status, { status })).ok, true, status);
  }
  for (const status of ['uploaded', 'held', 'transferring', 'staging_deleted', 'awaiting_upload']) {
    assert.equal(checkCleanupItem(cleanupRow(FAILED_ID, status, { status })).ok, false, status);
  }
  // A reason that is not a short code is not echoed into the report.
  const calls = [];
  const rep = await cleanupUpload(cleanupRow(FAILED_ID, `failed for ${SAFE_NAME}`), {
    async remove(p, o) { calls.push(['remove', p, o]); return true; },
    async rpc(fn, a) { calls.push(['rpc', fn, a]); return { upload_id: a.p_upload_id, status: 'failed' }; },
  });
  assert.equal(rep.reason, null);
  assert.equal(rep.action, 'removed');
  assert.deepEqual(calls.map((c) => c[0]), ['remove', 'rpc']);
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
      if (fn === 'hsf_transfer_mode') {
        assert.deepEqual(args, {});
        return reply(200, o.mode ?? 'fixture');
      }
      if (fn === 'hsf_transfer_claim') {
        assert.deepEqual(args, { p_limit: 10 });
        return reply(200, o.claim ?? [uploadRow({ status: 'transferring' })]);
      }
      if (fn === 'hsf_transfer_record') {
        const ok = args.p_outcome === 'received' && args.p_server_sha256 === SHA && args.p_receipt_sha256 === SHA;
        return reply(200, { upload_id: args.p_upload_id, status: ok ? 'transferred' : args.p_outcome });
      }
      if (fn === 'hsf_mark_staging_deleted') {
        if (o.markRefused) return reply(400, { message: `refused ${SERVICE_KEY}` });
        const was = (o.cleanup || []).find((r) => r.upload_id === args.p_upload_id);
        return reply(200, { upload_id: args.p_upload_id, status: was && was.reason !== 'transferred' ? was.reason : 'staging_deleted' });
      }
      if (fn === 'hsf_sweep_stale_uploads') {
        assert.deepEqual(args, { p_hours: 24 });
        return reply(200, o.swept ?? 0);
      }
      if (fn === 'hsf_transfer_cleanup_queue') {
        assert.deepEqual(args, { p_limit: 25 });
        return reply(200, o.cleanup ?? []);
      }
      return reply(404, { message: 'no such function' });
    }
    const objectPrefix = `${SUPABASE_URL}/storage/v1/object/${STAGING_BUCKET}/`;
    if (c.method === 'GET' && c.url === `${objectPrefix}${PATH}`) {
      if (o.downloadStatus) return new Response('nope', { status: o.downloadStatus });
      return new Response(BYTES, { status: 200, headers: { 'content-type': 'application/pdf' } });
    }
    if (c.method === 'HEAD' && c.url.startsWith(objectPrefix)) {
      return new Response(null, { status: o.headStatus ?? 400 });
    }
    if (c.method === 'DELETE' && c.url === `${SUPABASE_URL}/storage/v1/object/${STAGING_BUCKET}`) {
      if (o.deleteStatus) return reply(o.deleteStatus, { message: 'Storage failure' });
      const { prefixes } = JSON.parse(c.body);
      assert.equal(prefixes.length, 1);
      const known = [PATH, ...(o.cleanup || []).map((r) => r.storage_path)];
      assert.ok(known.includes(prefixes[0]), `DELETE of an unexpected path ${prefixes[0]}`);
      return reply(200, o.deleteEmpty ? [] : [{ name: prefixes[0], bucket_id: STAGING_BUCKET }]);
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

test('end to end over REST: fixture success runs the calls in order, then the sweep and the cleanup queue', async () => {
  const { s, sb } = await runOverRest({});
  assert.deepEqual(steps(sb.calls), [
    'rpc:hsf_transfer_mode', 'rpc:hsf_transfer_claim', 'GET storage', 'rpc:hsf_transfer_record', 'DELETE storage', 'rpc:hsf_mark_staging_deleted',
    'rpc:hsf_sweep_stale_uploads', 'rpc:hsf_transfer_cleanup_queue',
  ]);
  assert.equal(s.results[0].action, 'staging_deleted');
  const del = sb.calls.find((c) => c.method === 'DELETE');
  assert.deepEqual(JSON.parse(del.body), { prefixes: [PATH] });
});

test('end to end over REST: hold never calls DELETE', async () => {
  const { s, sb } = await runOverRest({ mode: 'hold' });
  assert.deepEqual(steps(sb.calls), [
    'rpc:hsf_transfer_mode', 'rpc:hsf_transfer_claim', 'GET storage', 'rpc:hsf_transfer_record',
    'rpc:hsf_sweep_stale_uploads', 'rpc:hsf_transfer_cleanup_queue',
  ]);
  assert.equal(s.results[0].action, 'held');
});

test('end to end over REST: the cleanup queue deletes each object, then marks it', async () => {
  const cleanup = [cleanupRow(FAILED_ID, 'failed'), cleanupRow(REJECTED_ID, 'rejected')];
  const { s, sb } = await runOverRest({ mode: 'hold', claim: [], cleanup });
  assert.deepEqual(steps(sb.calls), [
    'rpc:hsf_transfer_mode', 'rpc:hsf_transfer_claim', 'rpc:hsf_sweep_stale_uploads', 'rpc:hsf_transfer_cleanup_queue',
    'DELETE storage', 'rpc:hsf_mark_staging_deleted', 'DELETE storage', 'rpc:hsf_mark_staging_deleted',
  ]);
  const dels = sb.calls.filter((c) => c.method === 'DELETE').map((c) => JSON.parse(c.body).prefixes[0]);
  assert.deepEqual(dels, cleanup.map((r) => r.storage_path));
  assert.deepEqual(s.cleanup.counts, { removed: 2 });
});

test('end to end over REST: cleanup of an object already gone looks again before it marks', async () => {
  // Storage deletes nothing (empty list) and HEAD says not found: already absent, so mark.
  let r = await runOverRest({ mode: 'hold', claim: [], cleanup: [cleanupRow(FAILED_ID, 'failed')], deleteEmpty: true, headStatus: 400 });
  assert.deepEqual(steps(r.sb.calls).slice(-3), ['DELETE storage', 'HEAD storage', 'rpc:hsf_mark_staging_deleted']);
  assert.deepEqual(r.s.cleanup.counts, { already_absent: 1 });

  // Storage deletes nothing but HEAD finds the object: not marked.
  r = await runOverRest({ mode: 'hold', claim: [], cleanup: [cleanupRow(FAILED_ID, 'failed')], deleteEmpty: true, headStatus: 200 });
  assert.ok(!steps(r.sb.calls).slice(4).includes('rpc:hsf_mark_staging_deleted'));
  assert.deepEqual(r.s.cleanup.counts, { delete_failed: 1 });

  // HEAD itself fails: not marked.
  r = await runOverRest({ mode: 'hold', claim: [], cleanup: [cleanupRow(FAILED_ID, 'failed')], deleteEmpty: true, headStatus: 503 });
  assert.deepEqual(r.s.cleanup.counts, { delete_failed: 1 });
});

test('end to end over REST: the transfer pass never takes an empty delete list as a removal', async () => {
  // Outside the cleanup pass, an empty list is a failure even if the object is gone.
  const { s, sb } = await runOverRest({ deleteEmpty: true, headStatus: 404 });
  assert.equal(s.results[0].action, 'delete_failed');
  const transferPass = steps(sb.calls).slice(0, steps(sb.calls).indexOf('rpc:hsf_sweep_stale_uploads'));
  assert.ok(!transferPass.includes('HEAD storage'));
  assert.ok(!transferPass.includes('rpc:hsf_mark_staging_deleted'));
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
