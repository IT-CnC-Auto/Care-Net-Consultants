// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | Bee-Inspect Edge Function plumbing 26/09/2026
//
// Shared by every supabase/functions/<bee-inspect function>/index.ts. Plain ES
// module with its dependencies injected (env and fetch), so each handler runs
// unchanged in Deno and under node --test with fetch mocked. No network is
// touched here except through the injected fetch.
//
// The service role key is used only inside these functions (prompt section
// 3.6): database calls go through PostgREST rpc to the bi_ security definer
// functions, which decide every rule again. A person is identified by asking
// Supabase Auth who the bearer token belongs to (GET /auth/v1/user), exactly as
// vercel/lib/auth.js does for the File site.
//
// Secrets are read from the environment at call time and are never logged,
// returned or written anywhere.

import { isServiceCaller } from '../transfer-core.js';
import { sha256HexText } from './claim-code.js';

export { isServiceCaller };

export class HttpError extends Error {
  constructor(status, message, code, extra) {
    super(message);
    this.status = status;
    this.code = code || null;
    this.extra = extra || null;
  }
}

export function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers },
  });
}

// Every unknown vendor or secret: a clearly labelled stub that does nothing.
export function notImplemented(what, needs, detail) {
  return json({
    error: `${what} is not connected yet.`,
    stub: true,
    needs: needs || [],
    detail: detail || 'This is a placeholder. Nothing was sent, charged or stored.',
  }, 501);
}

export function requireMethod(req, method) {
  if (req.method !== method) throw new HttpError(405, `${method} only`, 'method');
}

export async function readJson(req, maxBytes = 16384) {
  const text = await req.text();
  if (new TextEncoder().encode(text).length > maxBytes) throw new HttpError(413, 'The request is too large.', 'too_large');
  if (!text.trim()) return {};
  try {
    const body = JSON.parse(text);
    if (body === null || typeof body !== 'object' || Array.isArray(body)) throw new Error('not an object');
    return body;
  } catch {
    throw new HttpError(400, 'The request body must be a JSON object.', 'bad_json');
  }
}

export function bearerToken(req) {
  const raw = req.headers.get('Authorization') || '';
  const m = /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/.exec(raw.trim());
  return m && raw.length <= 8192 ? m[1] : null;
}

export function sameText(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] || 0) ^ (y[i] || 0);
  return diff === 0;
}

// The payload of a JWT, without verifying it: only ever used after Supabase
// Auth has accepted the same token (requireUser), to read aal, amr and session_id.
export function decodeJwtPayload(token) {
  try {
    const part = token.split('.')[1];
    const b64 = part.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((part.length + 3) % 4);
    return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
  } catch {
    return {};
  }
}

// Step up MFA (prompt B3) from the claims of a token Supabase Auth accepted:
// aal2 and an amr entry for a second factor (totp or phone). Returns the input
// of bi_step_up_record, or null when the session has no second factor.
export async function stepUpFromClaims(claims, purpose) {
  if (!claims || claims.aal !== 'aal2' || !Array.isArray(claims.amr)) return null;
  const factors = claims.amr.filter((a) => a && (a.method === 'totp' || a.method === 'phone') && Number.isFinite(a.timestamp));
  if (!factors.length) return null;
  const latest = factors.reduce((a, b) => (b.timestamp > a.timestamp ? b : a));
  return {
    purpose,
    method: latest.method,
    aal: 'aal2',
    asserted_epoch: latest.timestamp,
    session_ref: await sha256HexText(String(claims.session_id || 'no-session')),
  };
}

// SQLSTATEs raised by the bi_ functions, mapped to HTTP.
const SQLSTATE_STATUS = { P0002: 404, 42501: 403, 28000: 401, 22023: 400, 23514: 422, 23505: 409, 53400: 429, 53100: 507 };

export function config(env, names) {
  const missing = names.filter((n) => !env[n]);
  if (missing.length) throw new HttpError(503, 'The function is not configured.', 'not_configured', { missing });
  return Object.fromEntries(names.map((n) => [n, env[n]]));
}

export function createDb({ url, serviceKey, fetch }) {
  const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' };
  async function parse(res, what) {
    const text = await res.text();
    let body = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = text; }
    if (!res.ok) {
      const code = body && body.code;
      const status = SQLSTATE_STATUS[code] || (res.status >= 500 ? 502 : 400);
      const message = status === 502 ? 'The database could not be reached.' : (body && body.message) || `${what} failed`;
      throw new HttpError(status, message, code || 'db_error');
    }
    return body;
  }
  return {
    async rpc(name, args) {
      const res = await fetch(`${url}/rest/v1/rpc/${name}`, { method: 'POST', headers, body: JSON.stringify(args || {}) });
      return parse(res, name);
    },
    async select(table, query) {
      const res = await fetch(`${url}/rest/v1/${table}?${query}`, { method: 'GET', headers });
      return parse(res, table);
    },
    async generateMagicLinkHash(email) {
      const res = await fetch(`${url}/auth/v1/admin/generate_link`, { method: 'POST', headers, body: JSON.stringify({ type: 'magiclink', email }) });
      const body = await parse(res, 'generate_link');
      const hash = (body && (body.hashed_token || (body.properties && body.properties.hashed_token))) || null;
      if (!hash) throw new HttpError(502, 'Sign in could not be prepared.', 'no_token');
      return hash;
    },
  };
}

// The signed in person: Supabase Auth checks the token; we also keep its claims.
export async function requireUser(req, { url, serviceKey, fetch }) {
  const token = bearerToken(req);
  if (!token) throw new HttpError(401, 'Please sign in to continue.', 'sign_in_required');
  let res;
  try {
    res = await fetch(`${url}/auth/v1/user`, { method: 'GET', headers: { apikey: serviceKey, Authorization: `Bearer ${token}` } });
  } catch {
    throw new HttpError(503, 'The sign in service could not be reached.', 'auth_unreachable');
  }
  if (res.status === 401 || res.status === 403) throw new HttpError(401, 'Please sign in again.', 'sign_in_required');
  if (!res.ok) throw new HttpError(503, 'The sign in service could not be reached.', 'auth_unreachable');
  const user = await res.json();
  if (!user || typeof user.id !== 'string') throw new HttpError(401, 'Please sign in again.', 'sign_in_required');
  return { id: user.id, email: user.email || null, claims: decodeJwtPayload(token) };
}

export function requireService(req, env) {
  if (!isServiceCaller(req.headers.get('Authorization') || '', env.SUPABASE_SERVICE_ROLE_KEY || '')) {
    throw new HttpError(401, 'This function runs with the service role only.', 'service_only');
  }
}

// Wraps a handler: every HttpError becomes JSON; anything else a plain 500 with no detail.
export function guarded(fn) {
  return async (req, deps) => {
    try {
      return await fn(req, deps);
    } catch (e) {
      if (e instanceof HttpError) {
        return json({ error: e.message, code: e.code, ...(e.extra || {}) }, e.status);
      }
      if (e && e.name === 'ValidationError') return json({ error: e.message, code: 'invalid', issues: e.issues }, 400);
      if (deps && typeof deps.log === 'function') deps.log('bee-inspect function failed: ' + String((e && e.message) || e).slice(0, 200));
      return json({ error: 'The request could not be completed.' }, 500);
    }
  };
}

export function supabaseDeps(deps) {
  const env = deps.env || {};
  const c = config(env, ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']);
  return { url: c.SUPABASE_URL, serviceKey: c.SUPABASE_SERVICE_ROLE_KEY, fetch: deps.fetch };
}
