// CNC HSF FORGE | HSF-MCO-01 v1.0.0 | MyClinicOnline document adapter 23/09/2026
//
// The one place that knows how a staged client document is handed to
// MyClinicOnline (MCO). Plain ES module: no Deno or Node specific APIs, only the
// global fetch and crypto.subtle, so the same file runs in the Supabase edge
// function (Deno) and under node --test.
//
// Three modes, read by the worker from msp_env_parameter hsf.mco_transfer_mode:
//
//   hold     The default while the MCO interface contract (HSF-3, register
//            CR-13.12) is pending. Nothing leaves Care Net and no network call
//            is made. The outcome is 'held' and the document stays in staging.
//   fixture  For tests only. Pretends MCO received the document: the reference
//            is 'FIXTURE-' + uploadId and the receipt fingerprint echoes the one
//            sent. The deployed worker refuses this mode unless its environment
//            explicitly allows it (see transfer-core.js), because a fixture
//            receipt would otherwise let a real document be removed from staging
//            without ever reaching MCO.
//   live     Refuses to start without MCO_BASE_URL and MCO_API_TOKEN. The request
//            it sends is a PLACEHOLDER, not a real MCO endpoint: see
//            buildPlaceholderRequest below, which Phase 5 replaces with the
//            request shape the MCO contract specifies.
//
// send() never throws for a network or MCO failure: it returns outcome 'error'
// with a short reason. It never puts the token, the file bytes or the file name
// into an error message. The adapter never deletes anything; deletion is the
// worker's decision, taken only after the fingerprints agree.

export const MODES = Object.freeze(['hold', 'fixture', 'live']);

export const PENDING_MESSAGE = 'MCO interface contract pending (HSF-3)';

const HEX64_RE = /^[0-9a-f]{64}$/;
const DEFAULT_TIMEOUT_MS = 60000;

// 1. Fingerprints -------------------------------------------------------------

function toBytes(input) {
  if (input instanceof Uint8Array) return input;
  if (input instanceof ArrayBuffer) return new Uint8Array(input);
  if (ArrayBuffer.isView(input)) return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
  throw new TypeError('sha256Hex expects a Uint8Array, an ArrayBuffer or a typed array view.');
}

// Lower case hexadecimal SHA 256 of the bytes, the same form the browser sends
// as sha256_client and the database stores.
export async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', /** @type {BufferSource} */ (toBytes(bytes)));
  const view = new Uint8Array(digest);
  let out = '';
  for (let i = 0; i < view.length; i++) out += view[i].toString(16).padStart(2, '0');
  return out;
}

export function isSha256Hex(v) {
  return typeof v === 'string' && HEX64_RE.test(v);
}

// 2. Outcomes -----------------------------------------------------------------

function result(outcome, fields) {
  const f = fields || {};
  return {
    outcome,
    mcoDocumentRef: f.mcoDocumentRef ?? null,
    receiptSha256: f.receiptSha256 ?? null,
    error: f.error ?? null,
  };
}

function checkSendInput(doc) {
  if (!doc || typeof doc !== 'object') return 'No document was given to send.';
  if (typeof doc.uploadId !== 'string' || !doc.uploadId) return 'The upload identifier is missing.';
  if (!(doc.bytes instanceof Uint8Array)) return 'The document bytes are missing.';
  if (!isSha256Hex(doc.sha256)) return 'The SHA 256 fingerprint is missing or malformed.';
  return null;
}

// 3. The live PLACEHOLDER -----------------------------------------------------
//
// PLACEHOLDER. NOT A REAL MYCLINICONLINE ENDPOINT.
// The MCO interface contract (HSF-3, register CR-13.12) is not in hand, so no
// MCO path, header, field name or response shape is known. Everything in this
// section is a stand in that keeps the rest of the worker testable, and the
// path deliberately carries the word PLACEHOLDER so it can never be mistaken for
// an agreed interface. Phase 5 replaces buildPlaceholderRequest and
// readPlaceholderReceipt with the shapes the contract specifies; nothing else in
// the worker needs to change, because the worker only depends on the outcome
// object { outcome, mcoDocumentRef, receiptSha256, error }.

export const LIVE_PLACEHOLDER = Object.freeze({
  status: 'placeholder pending the MCO interface contract (HSF-3, register CR-13.12)',
  method: 'POST',
  path: '/PLACEHOLDER-HSF-3/documents',
});

export function buildPlaceholderRequest(baseUrl, token, doc) {
  const url = baseUrl.replace(/\/+$/, '') + LIVE_PLACEHOLDER.path;
  return {
    url,
    init: {
      method: LIVE_PLACEHOLDER.method,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': doc.mimeType || 'application/octet-stream',
        Accept: 'application/json',
        // Placeholder metadata headers. The real names come from the contract.
        'Idempotency-Key': doc.uploadId,
        'X-Placeholder-Upload-Id': doc.uploadId,
        'X-Placeholder-Sha256': doc.sha256,
        'X-Placeholder-Client-Account': String(doc.clientAccountId ?? ''),
        'X-Placeholder-Department': String(doc.departmentCode ?? ''),
        'X-Placeholder-Section': String(doc.sectionCode ?? ''),
        'X-Placeholder-File-Name': encodeURIComponent(String(doc.fileName ?? '')),
      },
      body: doc.bytes,
    },
  };
}

// Placeholder receipt: a 2xx JSON body { document_ref, sha256 }. Anything else
// is an error, so an unexpected reply can never be read as a receipt.
export async function readPlaceholderReceipt(res) {
  if (!res.ok) return result('error', { error: `MyClinicOnline replied with HTTP ${res.status}.` });
  let body;
  try {
    body = await res.json();
  } catch (_) {
    return result('error', { error: 'MyClinicOnline replied without a readable receipt.' });
  }
  const ref = body && typeof body.document_ref === 'string' ? body.document_ref.trim() : '';
  const sha = body && typeof body.sha256 === 'string' ? body.sha256.trim().toLowerCase() : '';
  if (!ref || ref.length > 200) return result('error', { error: 'The MyClinicOnline receipt carried no document reference.' });
  if (!isSha256Hex(sha)) return result('error', { error: 'The MyClinicOnline receipt carried no SHA 256 fingerprint.' });
  return result('received', { mcoDocumentRef: ref, receiptSha256: sha });
}

function timeoutSignal(ms) {
  if (typeof AbortSignal !== 'undefined' && typeof AbortSignal.timeout === 'function') return AbortSignal.timeout(ms);
  return undefined;
}

// 4. The adapter ----------------------------------------------------------------

export function createAdapter(options) {
  const o = options || {};
  const mode = typeof o.mode === 'string' ? o.mode.trim().toLowerCase() : '';
  if (!MODES.includes(mode)) {
    throw new Error(`Unknown MCO transfer mode. Use one of: ${MODES.join(', ')}.`);
  }

  if (mode === 'hold') {
    return Object.freeze({
      mode,
      async send(doc) {
        const bad = checkSendInput(doc);
        if (bad) return result('error', { error: bad });
        return result('held');
      },
    });
  }

  if (mode === 'fixture') {
    return Object.freeze({
      mode,
      async send(doc) {
        const bad = checkSendInput(doc);
        if (bad) return result('error', { error: bad });
        return result('received', { mcoDocumentRef: 'FIXTURE-' + doc.uploadId, receiptSha256: doc.sha256 });
      },
    });
  }

  // live
  const baseUrl = typeof o.baseUrl === 'string' ? o.baseUrl.trim() : '';
  const token = typeof o.token === 'string' ? o.token.trim() : '';
  if (!baseUrl || !token) throw new Error(PENDING_MESSAGE);
  let parsed;
  try {
    parsed = new URL(baseUrl);
  } catch (_) {
    throw new Error(`${PENDING_MESSAGE}: MCO_BASE_URL is not a valid address.`);
  }
  // Special personal information never travels in the clear.
  if (parsed.protocol !== 'https:') throw new Error(`${PENDING_MESSAGE}: MCO_BASE_URL must use https.`);

  const doFetch = typeof o.fetch === 'function' ? o.fetch : (url, init) => globalThis.fetch(url, init);
  const timeoutMs = Number.isFinite(o.timeoutMs) && o.timeoutMs > 0 ? o.timeoutMs : DEFAULT_TIMEOUT_MS;

  return Object.freeze({
    mode,
    placeholder: true,
    async send(doc) {
      const bad = checkSendInput(doc);
      if (bad) return result('error', { error: bad });
      const { url, init } = buildPlaceholderRequest(baseUrl, token, doc);
      let res;
      try {
        res = await doFetch(url, Object.assign({}, init, { signal: timeoutSignal(timeoutMs) }));
      } catch (err) {
        const timedOut = err && (err.name === 'TimeoutError' || err.name === 'AbortError');
        return result('error', {
          error: timedOut ? 'MyClinicOnline did not answer in time.' : 'MyClinicOnline could not be reached.',
        });
      }
      return readPlaceholderReceipt(res);
    },
  });
}
