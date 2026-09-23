// CNC HSF FORGE | HSF-MCO-01 v1.0.0 | MyClinicOnline transfer worker core 23/09/2026
//
// Everything the hsf-mco-transfer edge function does, as plain functions with
// their dependencies injected, so it runs unchanged in Deno and under
// node --test. Plain ES module: global fetch and crypto.subtle only.
//
// The rule this module exists to keep:
//   A staging object is deleted only when the adapter outcome is 'received' AND
//   the server fingerprint equals the client fingerprint equals the receipt
//   fingerprint AND the database has recorded the upload as transferred.
//   hsf_mark_staging_deleted is called only after Storage has confirmed the
//   delete. Held, error and mismatch never delete anything.
//
// Per upload (processUpload):
//   1. check the row and its staging path <client_account_id>/<upload_id>/<safe_name>
//   2. download the object and take the server SHA 256
//   3. server hash differs from the client hash: record hash_mismatch, stop
//   4. send through the adapter (hold, fixture or live)
//   5. record the outcome with hsf_transfer_record
//   6. only for received with three equal hashes and a 'transferred' reply:
//      delete the object from Storage, then hsf_mark_staging_deleted
//
// Per run (runTransfer): read hsf.mco_transfer_mode (hold when unset), refuse to
// run on an unknown mode, on live without MCO_BASE_URL and MCO_API_TOKEN, and on
// fixture unless the environment allows it; then read hsf_transfer_queue(10) and
// process the rows one at a time.
//
// Reports carry upload identifiers, outcomes and short reasons only: never a
// file name, file content, a fingerprint pair in prose, or a key.

import { MODES, isSha256Hex, sha256Hex as defaultSha256Hex } from './mco-adapter.js';

export const STAGING_BUCKET = 'hsf-staging';
export const QUEUE_LIMIT = 10;
export const MODE_PARAMETER = 'hsf.mco_transfer_mode';
export const DEFAULT_MODE = 'hold';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SEGMENT_RE = /^[A-Za-z0-9._-]{1,160}$/;
const FUNCTION_RE = /^[a-z_][a-z0-9_]{0,62}$/;
const TRANSFERABLE = new Set(['uploaded', 'held']);

// 1. Small helpers --------------------------------------------------------------

function messageOf(err) {
  const m = err && typeof err.message === 'string' ? err.message : String(err);
  return m.slice(0, 300);
}

function toUint8(v) {
  if (v instanceof Uint8Array) return v;
  if (v instanceof ArrayBuffer) return new Uint8Array(v);
  if (ArrayBuffer.isView(v)) return new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
  throw new TypeError('The staging download did not return bytes.');
}

function lowerHex(v) {
  return typeof v === 'string' ? v.trim().toLowerCase() : '';
}

// Constant time comparison of two strings of equal length.
function sameText(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// The worker runs with the service role only: a scheduled call or a manual call
// that presents the service role key as its bearer token.
export function isServiceCaller(authorization, serviceKey) {
  if (typeof authorization !== 'string' || typeof serviceKey !== 'string' || !serviceKey) return false;
  const m = /^Bearer\s+(\S+)\s*$/i.exec(authorization.trim());
  return !!m && sameText(m[1], serviceKey);
}

// 2. Mode ---------------------------------------------------------------------

// Unset or empty means hold: nothing leaves Care Net until someone deliberately
// changes the parameter. Fixture is refused unless the environment allows it.
export function resolveMode(raw, options) {
  const allowFixture = !!(options && options.allowFixture);
  if (raw === null || raw === undefined || (typeof raw === 'string' && raw.trim() === '')) {
    return { ok: true, mode: DEFAULT_MODE, defaulted: true };
  }
  if (typeof raw !== 'string') {
    return { ok: false, mode: null, reason: `${MODE_PARAMETER} is not text, so nothing was processed.` };
  }
  const mode = raw.trim().toLowerCase();
  if (!MODES.includes(mode)) {
    return { ok: false, mode: null, reason: `${MODE_PARAMETER} is not one of ${MODES.join(', ')}, so nothing was processed.` };
  }
  if (mode === 'fixture' && !allowFixture) {
    return {
      ok: false,
      mode,
      reason: 'Fixture mode is for tests only and is refused here, because a fixture receipt would remove documents from staging that never reached MyClinicOnline.',
    };
  }
  return { ok: true, mode, defaulted: false };
}

// 3. Staging path ---------------------------------------------------------------

// The path must be exactly <client_account_id>/<upload_id>/<safe_name> for this
// row, so the worker can never read or delete an object that belongs to another
// upload or another company.
export function checkStagingPath(row) {
  if (row.storage_bucket !== undefined && row.storage_bucket !== null && row.storage_bucket !== STAGING_BUCKET) {
    return { ok: false, reason: `The upload is not held in the ${STAGING_BUCKET} bucket.` };
  }
  const path = row.storage_path;
  if (typeof path !== 'string' || !path || path.length > 400) {
    return { ok: false, reason: 'The upload has no staging path.' };
  }
  const seg = path.split('/');
  if (seg.length !== 3) return { ok: false, reason: 'The staging path does not have the expected three parts.' };
  if (!UUID_RE.test(seg[0]) || seg[0].toLowerCase() !== String(row.client_account_id ?? '').toLowerCase()) {
    return { ok: false, reason: 'The staging path does not belong to the company account on the upload.' };
  }
  if (!UUID_RE.test(seg[1]) || seg[1].toLowerCase() !== String(row.id ?? '').toLowerCase()) {
    return { ok: false, reason: 'The staging path does not belong to this upload.' };
  }
  if (!SEGMENT_RE.test(seg[2]) || /^\.+$/.test(seg[2])) {
    return { ok: false, reason: 'The staged file name is not a safe name.' };
  }
  if (typeof row.safe_name === 'string' && row.safe_name && seg[2] !== row.safe_name) {
    return { ok: false, reason: 'The staged file name does not match the upload record.' };
  }
  return { ok: true, path };
}

// 4. The deletion rule ------------------------------------------------------------

// The single predicate that allows the one destructive step. Pure and tested.
export function mayDeleteStaging(f) {
  const x = f || {};
  const server = lowerHex(x.serverSha256);
  const client = lowerHex(x.clientSha256);
  const receipt = lowerHex(x.receiptSha256);
  return x.outcome === 'received'
    && x.recordedStatus === 'transferred'
    && isSha256Hex(server)
    && server === client
    && client === receipt;
}

// 5. One upload -----------------------------------------------------------------

// deps: {
//   mode:       'hold' | 'fixture' | 'live' (as resolved for this run)
//   adapter:    { send(doc) } from createAdapter
//   download:   async (path) => Uint8Array | ArrayBuffer; throws when unreadable
//   remove:     async (path) => resolves when Storage confirms the delete;
//               throws (or resolves false) otherwise
//   rpc:        async (fn, args) => parsed JSON reply; throws on refusal
//   sha256Hex?: async (bytes) => hex (defaults to the adapter's)
//   log?:       (line) => void, for operator logs (no secrets are passed to it)
// }
export async function processUpload(row, deps) {
  const d = deps || {};
  const hash = typeof d.sha256Hex === 'function' ? d.sha256Hex : defaultSha256Hex;
  const log = typeof d.log === 'function' ? d.log : () => {};
  const mode = d.mode;
  const id = row && typeof row.id === 'string' ? row.id : null;
  const report = { uploadId: id, mode, outcome: null, action: null, deleted: false, marked: false, error: null };

  if (!id || !UUID_RE.test(id)) {
    report.action = 'skipped';
    report.error = 'The queue returned a row without a valid upload identifier.';
    return report;
  }
  if (!TRANSFERABLE.has(row.status)) {
    report.action = 'skipped';
    report.error = 'The upload is not waiting for transfer.';
    return report;
  }
  if (mode === 'hold' && row.status === 'held') {
    // Already held and checked. Nothing changes until the mode changes, so no
    // download and no new log row on every scheduled run.
    report.action = 'skipped';
    return report;
  }

  const record = async (outcome, f) => {
    try {
      const res = await d.rpc('hsf_transfer_record', {
        p_upload_id: id,
        p_mode: mode,
        p_outcome: outcome,
        p_server_sha256: f.serverSha ?? null,
        p_mco_ref: f.ref ?? null,
        p_receipt_sha256: isSha256Hex(f.receipt) ? f.receipt : null,
        p_error: f.error ?? null,
      });
      return { ok: true, res };
    } catch (err) {
      return { ok: false, error: messageOf(err) };
    }
  };

  // Record a non deleting outcome and stop.
  const stop = async (outcome, f) => {
    report.outcome = outcome;
    report.error = f.error ?? null;
    const r = await record(outcome, f);
    if (!r.ok) {
      report.action = 'record_failed';
      report.error = [report.error, `The transfer log could not be written: ${r.error}`].filter(Boolean).join(' ');
      log(`hsf-mco-transfer ${id}: ${report.error}`);
      return report;
    }
    report.action = outcome;
    if (report.error) log(`hsf-mco-transfer ${id}: ${outcome}: ${report.error}`);
    return report;
  };

  const client = lowerHex(row.sha256_client);
  if (!isSha256Hex(client)) return stop('error', { error: 'The upload carries no valid browser fingerprint.' });

  const p = checkStagingPath(row);
  if (!p.ok) return stop('error', { error: p.reason });

  let bytes;
  try {
    bytes = toUint8(await d.download(p.path));
  } catch (err) {
    return stop('error', { error: `The staging object could not be read. ${messageOf(err)}`.trim() });
  }

  let server;
  try {
    server = lowerHex(await hash(bytes));
  } catch (err) {
    return stop('error', { error: 'The server fingerprint could not be computed.' });
  }
  if (!isSha256Hex(server)) return stop('error', { error: 'The server fingerprint could not be computed.' });

  if (server !== client) {
    return stop('hash_mismatch', {
      serverSha: server,
      error: 'The staged file does not match the SHA 256 fingerprint taken in the browser.',
    });
  }

  let sent;
  try {
    sent = await d.adapter.send({
      uploadId: id,
      fileName: row.safe_name ?? p.path.split('/')[2],
      mimeType: row.mime_type ?? null,
      bytes,
      sha256: server,
      clientAccountId: row.client_account_id ?? null,
      departmentCode: row.department_code ?? null,
      sectionCode: row.section_code ?? null,
    });
  } catch (err) {
    return stop('error', { serverSha: server, error: `The MyClinicOnline adapter failed. ${messageOf(err)}`.trim() });
  }

  const outcome = sent && typeof sent === 'object' ? sent.outcome : null;
  if (outcome === 'held') return stop('held', { serverSha: server });
  if (outcome === 'error') {
    return stop('error', { serverSha: server, error: String(sent.error || 'MyClinicOnline did not accept the document.').slice(0, 300) });
  }
  if (outcome !== 'received') {
    return stop('error', { serverSha: server, error: 'The adapter returned an outcome the worker does not recognise.' });
  }

  const ref = typeof sent.mcoDocumentRef === 'string' ? sent.mcoDocumentRef.trim() : '';
  const receipt = lowerHex(sent.receiptSha256);
  if (!ref) {
    return stop('error', { serverSha: server, receipt, error: 'MyClinicOnline acknowledged the document without a reference.' });
  }
  if (receipt !== server || receipt !== client) {
    return stop('hash_mismatch', {
      serverSha: server,
      ref,
      receipt,
      error: 'The MyClinicOnline receipt fingerprint does not match the file sent.',
    });
  }

  // All three fingerprints agree. Record first: the database runs the same check
  // and only its 'transferred' reply lets the staging object go.
  report.outcome = 'received';
  const r = await record('received', { serverSha: server, ref, receipt });
  if (!r.ok) {
    report.action = 'record_failed';
    report.error = `Received by MyClinicOnline, but the transfer log could not be written, so the staging object is kept: ${r.error}`;
    log(`hsf-mco-transfer ${id}: ${report.error}`);
    return report;
  }
  const recordedStatus = r.res && typeof r.res === 'object' ? r.res.status : null;

  if (!mayDeleteStaging({ outcome, recordedStatus, serverSha256: server, clientSha256: client, receiptSha256: receipt })) {
    report.action = 'not_confirmed';
    report.error = 'The database did not confirm the transfer, so the staging object is kept.';
    log(`hsf-mco-transfer ${id}: ${report.error}`);
    return report;
  }
  report.action = 'transferred';

  try {
    const removed = await d.remove(p.path);
    if (removed === false) throw new Error('Storage did not confirm the removal.');
    report.deleted = true;
  } catch (err) {
    report.action = 'delete_failed';
    report.error = `Transferred, but the staging object could not be removed: ${messageOf(err)}`;
    log(`hsf-mco-transfer ${id}: ${report.error}`);
    return report;
  }

  try {
    const res = await d.rpc('hsf_mark_staging_deleted', { p_upload_id: id });
    if (res && typeof res === 'object' && 'status' in res && res.status !== 'staging_deleted') {
      throw new Error(`the database replied with status ${String(res.status).slice(0, 40)}`);
    }
    report.marked = true;
    report.action = 'staging_deleted';
  } catch (err) {
    report.action = 'mark_failed';
    report.error = `The staging object was removed, but the upload could not be marked: ${messageOf(err)}`;
    log(`hsf-mco-transfer ${id}: ${report.error}`);
  }
  return report;
}

// 6. One run ---------------------------------------------------------------------

// deps: {
//   rpc, download, remove    as for processUpload
//   createAdapter            from mco-adapter.js
//   mco?:          { baseUrl, token, fetch? } for live mode
//   allowFixture?: boolean (the deployed worker reads HSF_MCO_ALLOW_FIXTURE)
//   sha256Hex?, log?
// }
export async function runTransfer(deps) {
  const d = deps || {};
  const log = typeof d.log === 'function' ? d.log : () => {};
  const summary = { ok: false, mode: null, defaulted: false, refused: null, processed: 0, counts: {}, results: [] };

  let raw;
  try {
    raw = await d.rpc('msp_env_get', { p_key: MODE_PARAMETER });
  } catch (err) {
    summary.refused = 'The transfer mode could not be read, so nothing was processed.';
    log(`hsf-mco-transfer: ${summary.refused} ${messageOf(err)}`);
    return summary;
  }

  const m = resolveMode(raw, { allowFixture: d.allowFixture });
  summary.mode = m.mode;
  if (!m.ok) {
    summary.refused = m.reason;
    log(`hsf-mco-transfer: ${m.reason}`);
    return summary;
  }
  summary.defaulted = m.defaulted;

  let adapter;
  try {
    const mco = d.mco || {};
    adapter = d.createAdapter({ mode: m.mode, baseUrl: mco.baseUrl, token: mco.token, fetch: mco.fetch });
  } catch (err) {
    // Live without MCO_BASE_URL and MCO_API_TOKEN lands here: the run refuses
    // before it touches the queue.
    summary.refused = messageOf(err);
    log(`hsf-mco-transfer: ${summary.refused}`);
    return summary;
  }

  let queue;
  try {
    queue = await d.rpc('hsf_transfer_queue', { p_limit: QUEUE_LIMIT });
  } catch (err) {
    summary.refused = 'The transfer queue could not be read, so nothing was processed.';
    log(`hsf-mco-transfer: ${summary.refused} ${messageOf(err)}`);
    return summary;
  }
  if (!Array.isArray(queue)) {
    summary.refused = 'The transfer queue reply was not a list, so nothing was processed.';
    log(`hsf-mco-transfer: ${summary.refused}`);
    return summary;
  }

  // One at a time: at most one document is held in memory.
  for (const row of queue.slice(0, QUEUE_LIMIT)) {
    const rep = await processUpload(row, {
      mode: m.mode,
      adapter,
      download: d.download,
      remove: d.remove,
      rpc: d.rpc,
      sha256Hex: d.sha256Hex,
      log,
    });
    summary.results.push(rep);
    summary.counts[rep.action] = (summary.counts[rep.action] || 0) + 1;
  }
  summary.processed = summary.results.length;
  summary.ok = true;
  return summary;
}

// 7. Supabase bindings ---------------------------------------------------------------

// The three I/O dependencies over the Supabase REST, Storage and rpc endpoints,
// with the service role key. fetch is injectable for tests. The key is sent only
// in the apikey and Authorization headers and never appears in an error.

export function encodeStagingPath(path) {
  if (typeof path !== 'string' || path.length > 400) throw new Error('The staging path is not usable.');
  const seg = path.split('/');
  if (seg.length !== 3 || seg.some((s) => !SEGMENT_RE.test(s) || /^\.+$/.test(s))) {
    throw new Error('The staging path is not usable.');
  }
  return seg.map(encodeURIComponent).join('/');
}

export function createSupabaseIo(options) {
  const o = options || {};
  const base = typeof o.url === 'string' ? o.url.trim().replace(/\/+$/, '') : '';
  const key = typeof o.serviceKey === 'string' ? o.serviceKey.trim() : '';
  if (!base || !key) throw new Error('SUPABASE_URL and the service role key are required.');
  const doFetch = typeof o.fetch === 'function' ? o.fetch : (url, init) => globalThis.fetch(url, init);

  const headers = (extra) => Object.assign({ apikey: key, Authorization: `Bearer ${key}` }, extra || {});
  const clean = (s) => String(s).split(key).join('[redacted]').slice(0, 300);

  async function rpc(fn, args) {
    if (typeof fn !== 'string' || !FUNCTION_RE.test(fn)) throw new Error('Refused an unexpected function name.');
    const res = await doFetch(`${base}/rest/v1/rpc/${fn}`, {
      method: 'POST',
      headers: headers({ 'Content-Type': 'application/json', Accept: 'application/json' }),
      body: JSON.stringify(args || {}),
    });
    const text = await res.text();
    if (!res.ok) {
      let detail = '';
      try {
        const e = JSON.parse(text);
        if (e && typeof e.message === 'string') detail = `: ${clean(e.message)}`;
      } catch (_) { /* not JSON; the status is enough */ }
      throw new Error(`${fn} was refused (HTTP ${res.status})${detail}`);
    }
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch (_) {
      throw new Error(`${fn} replied with something other than JSON.`);
    }
  }

  async function download(path) {
    const enc = encodeStagingPath(path);
    const res = await doFetch(`${base}/storage/v1/object/${STAGING_BUCKET}/${enc}`, {
      method: 'GET',
      headers: headers(),
    });
    if (!res.ok) {
      try { await res.arrayBuffer(); } catch (_) { /* drain only */ }
      throw new Error(`Storage replied with HTTP ${res.status}.`);
    }
    return new Uint8Array(await res.arrayBuffer());
  }

  // DELETE /storage/v1/object/hsf-staging { prefixes: [path] }. Storage answers
  // 200 with the list of objects it removed, and 200 with an empty list when
  // nothing matched, so success means the list names this exact path.
  async function remove(path) {
    encodeStagingPath(path);
    const res = await doFetch(`${base}/storage/v1/object/${STAGING_BUCKET}`, {
      method: 'DELETE',
      headers: headers({ 'Content-Type': 'application/json', Accept: 'application/json' }),
      body: JSON.stringify({ prefixes: [path] }),
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`Storage refused the removal (HTTP ${res.status}).`);
    let list;
    try {
      list = JSON.parse(text);
    } catch (_) {
      throw new Error('Storage replied to the removal without a readable list.');
    }
    if (!Array.isArray(list) || !list.some((obj) => obj && obj.name === path)) {
      throw new Error('Storage did not confirm that the staging object was removed.');
    }
    return true;
  }

  return { rpc, download, remove };
}
