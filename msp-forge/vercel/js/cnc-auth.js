/* =====================================================================
   cnc-auth.js :: Care Net Consultants shared sign in (ES module)
   Version: 1.0 | 23/09/2026 | HSF FORGE build contract, section 6

   Usage (after /js/cnc-config.js has loaded):
     import { auth } from '/js/cnc-auth.js';
     await auth.init();
     const s = await auth.session();            // null when signed out
     await auth.signInWithEmail(email, location.href);
     const stop = auth.onChange((event, session) => { ... });
     const data = await auth.apiFetch('/api/hsf-consent');

   Providers, chosen by CNC_CONFIG.authProvider:
     supabase  Email one time link through Supabase Auth, loaded from
               https://esm.sh/@supabase/supabase-js@2 and created with
               createClient(supabaseUrl, publishableKey), exactly as
               index.html does, so a session started there is seen here.
     mco_sso   A stub. Every call refuses with "MCO single sign on is
               pending the MCO interface contract (HSF-3)". Nothing is
               guessed about how MyClinicOnline will sign people in.

   Errors: every async method throws (rejects) with a plain English
   message on failure. signInWithEmail resolves {ok: true, error: null}.
   No token, email or session detail is logged or sent anywhere except
   Supabase Auth and this site's own /api endpoints.
   ===================================================================== */

const SUPABASE_JS = 'https://esm.sh/@supabase/supabase-js@2';
export const MCO_SSO_PENDING = 'MCO single sign on is pending the MCO interface contract (HSF-3)';
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function cfg() {
  const g = typeof window !== 'undefined' ? window : globalThis;
  return g.CNC_CONFIG || {};
}

function providerName() {
  return cfg().authProvider || 'supabase';
}

function pendingError() {
  const e = new Error(MCO_SSO_PENDING);
  e.code = 'HSF-3';
  e.pending = true;
  return e;
}

function checkProvider() {
  const p = providerName();
  if (p === 'mco_sso') throw pendingError();
  if (p !== 'supabase') throw new Error('Unknown sign in provider "' + p + '" in CNC_CONFIG.authProvider.');
  return p;
}

let client = null;
let ready = null;

async function start(options) {
  checkProvider();
  if (options && options.client) {
    /* A page that already holds a Supabase client can share it, which
       avoids two auth clients competing for the same stored session. */
    client = options.client;
    return client;
  }
  const c = cfg();
  if (!c.supabaseUrl || !c.publishableKey) {
    throw new Error('Sign in is not configured. Load /js/cnc-config.js before /js/cnc-auth.js.');
  }
  const mod = await import(SUPABASE_JS);
  client = mod.createClient(c.supabaseUrl, c.publishableKey);
  return client;
}

function init(options) {
  if (!ready) {
    ready = start(options || {}).catch((e) => { ready = null; client = null; throw e; });
  }
  return ready;
}

function defaultRedirect() {
  if (typeof location === 'undefined') return undefined;
  return location.origin + location.pathname;
}

function plainError(err, fallback) {
  const e = new Error((err && err.message) || fallback);
  if (err && err.status) e.status = err.status;
  return e;
}

function rolesOf(user) {
  const m = (user && user.app_metadata) || {};
  const r = Array.isArray(m.msp_roles) ? m.msp_roles : (Array.isArray(m.roles) ? m.roles : []);
  return r.filter((x) => typeof x === 'string');
}

export const auth = {
  /* Resolves with the underlying Supabase client. Safe to call many times. */
  init,

  provider: providerName,

  /* The Supabase client once init() has resolved, otherwise null. */
  client() { return client; },

  async signInWithEmail(email, redirectTo, extra) {
    const c = await init();
    const addr = String(email == null ? '' : email).trim();
    if (!EMAIL_RE.test(addr)) throw new Error('Please enter a valid email address.');
    const options = { emailRedirectTo: redirectTo || defaultRedirect() };
    if (extra && extra.data && typeof extra.data === 'object') options.data = extra.data;
    const { error } = await c.auth.signInWithOtp({ email: addr, options });
    if (error) throw plainError(error, 'The sign in link could not be sent. Please try again.');
    return { ok: true, error: null };
  },

  async session() {
    const c = await init();
    const { data, error } = await c.auth.getSession();
    if (error) throw plainError(error, 'Your sign in could not be checked. Please try again.');
    return (data && data.session) || null;
  },

  async accessToken() {
    const s = await auth.session();
    return s ? s.access_token : null;
  },

  /* {id, email, roles, isStaff} or null. Roles come from app_metadata,
     which only the server can set; the page uses them to show links, and
     every endpoint checks them again on its own side. */
  async user() {
    const s = await auth.session();
    if (!s || !s.user) return null;
    const roles = rolesOf(s.user);
    return {
      id: s.user.id,
      email: s.user.email || null,
      roles,
      isStaff: roles.some((r) => r.indexOf('forge_') === 0)
    };
  },

  /* cb(event, session) on every sign in, sign out and token refresh.
     Returns a function that stops listening. The callback runs on the
     next tick, so it may safely call auth.session() or auth.apiFetch(). */
  onChange(cb) {
    if (typeof cb !== 'function') throw new TypeError('auth.onChange needs a function.');
    checkProvider();
    let sub = null;
    let stopped = false;
    init().then((c) => {
      if (stopped) return;
      const r = c.auth.onAuthStateChange((event, session) => {
        setTimeout(() => { if (!stopped) cb(event, session); }, 0);
      });
      sub = r && r.data && r.data.subscription;
    }).catch((e) => {
      if (!stopped) setTimeout(() => cb('ERROR', null, e), 0);
    });
    return () => {
      stopped = true;
      if (sub && typeof sub.unsubscribe === 'function') sub.unsubscribe();
    };
  },

  /* Signs out of this browser only; other devices keep their sessions. */
  async signOut() {
    const c = await init();
    const { error } = await c.auth.signOut({ scope: 'local' });
    if (error) throw plainError(error, 'You could not be signed out. Please try again.');
    return { ok: true, error: null };
  },

  /* Calls this site's own /api endpoints with the user's access token.
     path is relative ('/api/hsf-file?file_id=...'); CNC_CONFIG.apiBase is
     put in front of it so the same page works when hosted inside MCO.
     A plain object body is sent as JSON. Throws with .status and .data. */
  async apiFetch(path, opts) {
    const o = opts || {};
    if (typeof path !== 'string' || !/^\/(?!\/)/.test(path)) {
      throw new Error('auth.apiFetch needs a path that starts with a single slash.');
    }
    const token = await auth.accessToken();
    if (!token) {
      const e = new Error('Please sign in first.');
      e.status = 401;
      throw e;
    }
    const headers = Object.assign({}, o.headers || {}, { Authorization: 'Bearer ' + token });
    let body = o.body;
    if (body != null && typeof body === 'object' && Object.getPrototypeOf(body) === Object.prototype) {
      body = JSON.stringify(body);
      headers['Content-Type'] = 'application/json';
    }
    const res = await fetch((cfg().apiBase || '') + path, {
      method: o.method || (body != null ? 'POST' : 'GET'),
      headers,
      body,
      credentials: 'omit'
    });
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch (_) { data = { raw: text }; }
    if (!res.ok) {
      /* The endpoints answer {error: "<plain message>", code: "<code>"}. */
      const msg = data && typeof data.error === 'string' ? data.error
        : (data && typeof data.message === 'string' ? data.message : null);
      const e = new Error(msg || ('The request failed with status ' + res.status + '.'));
      e.status = res.status;
      if (data && typeof data.code === 'string') e.code = data.code;
      e.data = data;
      throw e;
    }
    return data;
  }
};

export default auth;
