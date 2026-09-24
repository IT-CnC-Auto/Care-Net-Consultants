#!/usr/bin/env node
/* =====================================================================
   file-links.mjs :: the File pages never lead to the Plan pages, rendered
   hsf/BUILD-CONTRACT.md section 15.1, the Chromium half

   KEEPING THE FILE APART FROM THE PLAN
   The Health and Safety File (and the Risk Assessment application behind
   it) is a separate product from the Medical Surveillance Plan. No File
   page may link, navigate, submit or redirect to a Plan page:
     /, /index.html, /pilot, /method, /shop, /sample,
     /medical-surveillance-plans, /industry, /assess, /account
   (with or without .html, a query or a hash, after the redirects and
   rewrites in vercel/vercel.json; /hsf-sample is not /sample). The portal
   (/portal.html, "Sign in" in the File menu) joins both products and is
   allowed. Two checks hold the line:
     1. Static, no browser, part of every "node --test" run:
          node --test test/api/file-separation.test.js
        markup, inline handlers and every string in the File scripts, the
        logo link, "Build my Plan", the sign off pricing in
        vercel/hsf/pricing.js and the internal platform names.
     2. Rendered, this script, a gate that can fail. "node --test" (which
        in Node 22 also picks up every script under test/) runs it as one
        test whenever Chromium is found, and skips it only when Playwright
        or its Chromium is missing. There it crawls the quick plan: every
        state of every File page except the sample industries, and the
        construction sample in both views, at 1280 and 390 pixels (about
        30 seconds). CNC_FILE_LINKS=full node --test crawls every sample
        industry too. On its own it always crawls the full plan:
          node test/browser/file-links.mjs
          node test/browser/file-links.mjs --quick
          node test/browser/file-links.mjs --only builder --width 390 --verbose
        Options: --only <text> crawls only the states whose name contains
        the text; --width 1280|390 one width only; --jobs <n> parallel
        pages (default 4); --quick the quick plan that node --test
        crawls; --verbose prints each crawl; --list prints the
        crawl plan and stops; --root <dir> serves another copy of vercel/
        (for example an export of an older commit, to see the crawl catch
        its links); --dump <file> writes every target found, as JSON.

   WHAT IT DOES
   Starts server/serve.js on a free local port (the vercel/ site, served
   the Vercel way with cleanUrls) and opens every File page in Chromium at
   1280 and 390 pixels wide:
     health-and-safety-file
     hsf-builder   demonstration (?demo=1), signed out, signed in with no
                   company account (registering walks on to consent and
                   setup; the builder posts /api/signon only here, signed
                   in), and sign in unreachable
     hsf-staff     demonstration, signed out, signed in without staff
                   access, and sign in unreachable
     hsf-sample    the industry chooser, and every industry in
                   vercel/hsf/samples in both views ("The File document"
                   and "Explore it interactively")
     legislation   without a hash, with an instrument's hash and with an
                   unknown hash
   On each it notes the address the page opened at (after any server
   redirect) and collects every a[href], area[href], form action,
   formaction and frame address; fills and submits every visible form
   (never the honeypot); steps through every option of every select, then
   puts the first choice back; and clicks every link, button, summary, tab
   and menu item (hidden ones too), clicking again whatever new ones
   appear, so the demonstrations walk every state they can reach. Every navigation, form submission, location change,
   history change and window.open that would follow is recorded through
   the Navigation API and a window.open stand in, then cancelled, so the
   page never leaves the site. A link that opens a new tab is followed in
   the same tab and cancelled the same way.

   The page decides its state the way it does in production: cnc-auth.js
   imports supabase-js from its CDN, and the crawl answers that import
   with a stand in whose getSession returns no session (signed out) or a
   fictitious one. /api/* is answered in the browser by stubs (for
   example /api/hsf-consent with no company account, /api/signon with a
   reference and an assessment_url on /assess.html, which the builder must
   never follow, whether it posts signed in or, if it ever did again,
   signed out, /api/hsf-staff with 403). Supabase REST reads answer an
   empty list. Every other address off the local server is refused, so the
   crawl never reaches Supabase, Vercel or any live service.

   It fails, with the page, state, width, element text and target, on any
   Plan page target, or when a File page cannot be opened. A state the
   crawl could not reach is listed as a warning. The last line is a one
   line summary; the exit code is 1 on failure.

   Playwright: require('playwright') if installed, else the global copy at
   /opt/node22/lib/node_modules/playwright, or PLAYWRIGHT_MODULE. Browsers
   come from PLAYWRIGHT_BROWSERS_PATH (for example /opt/pw-browsers). Under
   node --test, a missing Playwright or Chromium skips the test (the reason
   is printed); a Chromium that is there but will not start fails it.
   ===================================================================== */

import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..', '..');

/* The crawl never needs the server's own Supabase access: /api/* is answered
   in the browser, and nothing is passed on. */
for (const k of Object.keys(process.env)) if (/^SUPABASE_|^MCO_|^XAI_|^CNC_KERNEL/.test(k)) delete process.env[k];

globalThis.__CNC_FILE_SEPARATION_LIB_ONLY = true;
const lib = require('../api/file-separation.test.js');
const { createServer } = require('../../server/serve.js');

const PLAYWRIGHT_TRIES = [process.env.PLAYWRIGHT_MODULE, 'playwright', '/opt/node22/lib/node_modules/playwright'].filter(Boolean);
function findPlaywright() {
  for (const t of PLAYWRIGHT_TRIES) {
    try { return require(t); } catch (_) { /* try the next */ }
  }
  return null;
}
function loadPlaywright() {
  const pw = findPlaywright();
  if (pw) return pw;
  console.error('file-links: Playwright was not found (tried ' + PLAYWRIGHT_TRIES.join(', ') + '). Set PLAYWRIGHT_MODULE.');
  process.exit(2);
}
/* null when Chromium can be started, otherwise why not (for a skip). */
function chromiumMissing() {
  const pw = findPlaywright();
  if (!pw || !pw.chromium) return 'Playwright was not found (tried ' + PLAYWRIGHT_TRIES.join(', ') + '; set PLAYWRIGHT_MODULE)';
  let exe = '';
  try { exe = pw.chromium.executablePath(); } catch (_) { exe = ''; }
  if (!exe || !fs.existsSync(exe)) return 'Chromium was not found (' + (exe || 'no path') + '; set PLAYWRIGHT_BROWSERS_PATH)';
  return null;
}

/* ------------------------------------------------------------ options */
const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf(name); return i !== -1 && argv[i + 1] !== undefined ? argv[i + 1] : dflt; };
const ONLY = opt('--only', null);
const WIDTH = opt('--width', null);
const JOBS = Math.max(1, Math.min(8, Number(opt('--jobs', 4)) || 4));
const VERBOSE = argv.includes('--verbose');
const LIST = argv.includes('--list');
const QUICK = argv.includes('--quick');
/* The sample industries the quick plan crawls: every sample page is drawn by
   the same page script from its industry's data, which the static half scans
   in full. */
const QUICK_SAMPLES = ['construction'];
const DUMP = opt('--dump', null);
const VERCEL = path.resolve(opt('--root', path.join(ROOT, 'vercel')));
const VIEWPORTS = [{ width: 1280, height: 900 }, { width: 390, height: 844 }].filter((v) => !WIDTH || String(v.width) === String(WIDTH));
const MAX_CLICKS = 2500;
const CRAWL_TIMEOUT_MS = 240000;

/* ------------------------------------------------------------ fictitious sign in */
const USER = {
  access_token: 'crawl-access-token', token_type: 'bearer', expires_in: 3600, refresh_token: 'crawl-refresh-token',
  user: { id: '00000000-0000-4000-8000-00000000c0de', email: 'crawler@example.co.za', app_metadata: {}, user_metadata: {} }
};

/* Stands in for https://esm.sh/@supabase/supabase-js@2. The session comes
   from window.__CRAWL_SESSION, set before any page script runs. */
const FAKE_SUPABASE_JS = `
const current = () => (globalThis.__CRAWL_SESSION || null);
function query() {
  const q = { select: () => q, eq: () => q, in: () => q, order: () => q, limit: () => q, single: () => q, maybeSingle: () => q,
    then: (ok, bad) => Promise.resolve({ data: [], error: null }).then(ok, bad) };
  return q;
}
export function createClient() {
  return {
    auth: {
      async getSession() { return { data: { session: current() }, error: null }; },
      async getUser() { const s = current(); return { data: { user: s ? s.user : null }, error: null }; },
      onAuthStateChange() { return { data: { subscription: { unsubscribe() {} } } }; },
      async signInWithOtp() { return { data: {}, error: null }; },
      async verifyOtp() { return { data: {}, error: null }; },
      async signOut() { return { error: null }; }
    },
    from: () => query(),
    rpc: async () => ({ data: null, error: null })
  };
}
export default { createClient };
`;

/* ------------------------------------------------------------ /api stubs, per state */
const json = (status, body) => ({ status, body });
const COMPANY = 'Crawl Test (Pty) Ltd (fictitious)';
function signonAnswer(origin) {
  /* assessment_url belongs to the Plan: the builder must never follow it. */
  return json(200, { status: 'received', reference: 'CNC-CRAWL-0001', existing: false, company_name: COMPANY, contact_number: null,
    account_kind: 'client', declined: false, assessment_url: origin + '/assess.html?token=crawl-only' });
}
const API = {
  none: () => () => json(404, { error: 'Not available in the crawl.' }),
  signedOut: (origin) => (m, p) => (p === '/api/signon' && m === 'POST' ? signonAnswer(origin) : json(401, { error: 'Please sign in first.' })),
  noAccount: (origin) => {
    const st = { registered: false, consent: false };
    const consent = () => (st.registered
      ? { client_account_id: 'crawl-account', company_name: COMPANY, wording_version: 'HSF-CONSENT-1.0',
        document_storage: st.consent, mco_transfer: st.consent, authority_to_share: st.consent, complete: st.consent }
      : { client_account_id: null, complete: false });
    return (m, p, q) => {
      if (p === '/api/signon' && m === 'POST') { st.registered = true; return signonAnswer(origin); }
      if (p === '/api/hsf-consent') {
        if (m === 'POST' && st.registered) st.consent = true;
        if (m === 'DELETE') st.consent = false;
        return json(200, consent());
      }
      if (p === '/api/hsf-upload' && q.get('gate')) {
        return json(200, { uploads_open: true, client_verified: false, verification_requested: false, deletion_sms_available: false, consent_complete: st.consent });
      }
      if (p === '/api/hsf-upload' && m === 'GET') return json(200, []);
      if (p === '/api/hsf-file' && m === 'GET') return json(200, []);
      if (p === '/api/hsf-file') return json(400, { error: 'The crawl does not create Files.' });
      return json(404, { error: 'Not available in the crawl.' });
    };
  },
  notStaff: () => (m, p) => (p.startsWith('/api/hsf-staff') ? json(403, { error: 'This console is for Care Net staff.', code: 'forbidden' }) : json(404, { error: 'Not available in the crawl.' }))
};

/* ------------------------------------------------------------ the crawl plan */
function legislationSlug() {
  try {
    const sandbox = { window: {} };
    vm.runInNewContext(fs.readFileSync(path.join(VERCEL, 'hsf', 'legislation-index.js'), 'utf8'), sandbox, { timeout: 2000 });
    const idx = sandbox.window.CNC_LEGISLATION_INDEX;
    return Array.isArray(idx) && idx[0] && idx[0].slug ? String(idx[0].slug) : null;
  } catch (_) { return null; }
}
/* What each forced state shows, as the contract describes it: a sign in email
   when signed out; the company registration in place with no account. */
const visibleEmail = () => !!Array.from(document.querySelectorAll('input[type=email]')).find((e) => e.offsetWidth || e.offsetHeight);
const visibleCompanyField = () => !!Array.from(document.querySelectorAll('input')).find((e) => (e.offsetWidth || e.offsetHeight)
  && /company|organi[sz]ation/i.test([e.name, e.id, e.getAttribute('autocomplete')].join(' ')));

function crawlPlan(quick) {
  const plan = [
    { name: 'health-and-safety-file', path: '/health-and-safety-file', state: 'landing page' },
    { name: 'builder demonstration', path: '/hsf-builder?demo=1', state: 'demonstration' },
    { name: 'builder signed out', path: '/hsf-builder', state: 'signed out', session: null, api: 'signedOut', expect: visibleEmail },
    { name: 'builder no account', path: '/hsf-builder', state: 'signed in, no company account', session: USER, api: 'noAccount', expect: visibleCompanyField },
    { name: 'builder sign in unreachable', path: '/hsf-builder', state: 'sign in unreachable', supabase: 'fail' },
    { name: 'staff demonstration', path: '/hsf-staff?demo=1', state: 'demonstration' },
    { name: 'staff signed out', path: '/hsf-staff', state: 'signed out', session: null, api: 'signedOut', expect: visibleEmail },
    { name: 'staff not staff', path: '/hsf-staff', state: 'signed in without staff access', session: USER, api: 'notStaff' },
    { name: 'staff sign in unreachable', path: '/hsf-staff', state: 'sign in unreachable', supabase: 'fail' },
    { name: 'sample chooser', path: '/hsf-sample', state: 'industry chooser' }
  ];
  let slugs = [];
  try { slugs = fs.readdirSync(path.join(VERCEL, 'hsf', 'samples')).filter((f) => f.endsWith('.js')).map((f) => f.slice(0, -3)).sort(); } catch (_) { slugs = []; }
  if (quick) {
    const some = slugs.filter((x) => QUICK_SAMPLES.includes(x));
    slugs = some.length ? some : slugs.slice(0, 1);
  }
  for (const slug of slugs) {
    for (const view of ['The File document', 'Explore it interactively']) {
      plan.push({ name: 'sample ' + slug + ' ' + (view.startsWith('The') ? 'document' : 'interactive'), path: '/hsf-sample?industry=' + encodeURIComponent(slug), state: slug + ', ' + view, view });
    }
  }
  const slug = legislationSlug();
  plan.push({ name: 'legislation', path: '/legislation', state: 'no hash' });
  if (slug) plan.push({ name: 'legislation hash', path: '/legislation#' + slug, state: 'hash #' + slug });
  plan.push({ name: 'legislation unknown hash', path: '/legislation#no-such-instrument', state: 'unknown hash' });
  return plan.filter((c) => !ONLY || c.name.includes(ONLY) || c.path.includes(ONLY));
}

/* ------------------------------------------------------------ in the page */
/* Runs before any page script, in the top frame. Records every navigation
   the page starts and cancels it, lets same page hash changes through, and
   stands in for window.open and print. */
function instrument(session) {
  if (window.top !== window) return;
  const C = window.__crawl = { events: [], label: 'page load', hist: false };
  window.__CRAWL_SESSION = session;
  const abs = (u) => { try { return new URL(String(u), location.href).href; } catch (e) { return String(u); } };
  const rec = (kind, url) => { C.events.push({ kind, url: abs(url), label: C.label }); };
  ['pushState', 'replaceState'].forEach((m) => {
    const orig = history[m];
    history[m] = function (st, title, url) {
      if (url !== undefined && url !== null) {
        rec('history.' + m, url);
        try { if (new URL(abs(url)).pathname !== location.pathname) return undefined; } catch (e) { return undefined; }
      }
      C.hist = true;
      try { return orig.apply(this, arguments); } finally { C.hist = false; }
    };
  });
  if (window.navigation && typeof navigation.addEventListener === 'function') {
    navigation.addEventListener('navigate', (e) => {
      if (C.hist) return;
      const kind = e.formData ? 'form submission' : (e.hashChange ? 'hash change' : (e.downloadRequest !== null && e.downloadRequest !== undefined ? 'download' : 'navigation'));
      rec(kind, e.destination.url);
      if (e.hashChange) return;
      if (e.cancelable) e.preventDefault();
    });
  }
  const fakeLocation = { assign: (u) => rec('window.open', u), replace: (u) => rec('window.open', u), reload() {}, toString: () => 'about:blank' };
  Object.defineProperty(fakeLocation, 'href', { get: () => 'about:blank', set: (u) => rec('window.open', u) });
  window.open = function (url) {
    rec('window.open', url === undefined || url === null || String(url) === '' ? 'about:blank' : url);
    const w = { closed: false, opener: null, close() { this.closed = true; }, focus() {}, blur() {}, postMessage() {},
      document: { write() {}, writeln() {}, open() {}, close() {} } };
    Object.defineProperty(w, 'location', { get: () => fakeLocation, set: (u) => rec('window.open', u) });
    return w;
  };
  window.print = function () {};
}

/* Every address the page carries right now. */
function collectTargets() {
  const out = [];
  /* The same description the clicks carry: tag, role and words. */
  const text = (el) => {
    const t = ((el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim()
      || el.getAttribute('aria-label') || el.getAttribute('title') || el.value
      || (el.querySelector && el.querySelector('img[alt]') ? el.querySelector('img[alt]').getAttribute('alt') : '') || '').slice(0, 90);
    const role = el.getAttribute('role');
    return el.tagName.toLowerCase() + (role ? '[role=' + role + ']' : '') + (t ? ' "' + t + '"' : (el.id ? ' #' + el.id : ''));
  };
  const abs = (u) => { try { return new URL(u, document.baseURI).href; } catch (e) { return String(u); } };
  document.querySelectorAll('a[href], area[href], a[*|href]').forEach((el) => {
    const raw = el.getAttribute('href') || el.getAttribute('xlink:href');
    if (raw !== null) out.push({ kind: el.tagName.toLowerCase() + ' href', url: abs(raw), text: text(el) });
  });
  document.querySelectorAll('form').forEach((f) => {
    const a = f.getAttribute('action');
    if (a !== null) out.push({ kind: 'form action', url: abs(a), text: 'form' + (f.id ? ' #' + f.id : '') });
  });
  document.querySelectorAll('[formaction]').forEach((el) => out.push({ kind: 'formaction', url: abs(el.getAttribute('formaction')), text: text(el) }));
  document.querySelectorAll('iframe[src], frame[src], embed[src]').forEach((el) => out.push({ kind: el.tagName.toLowerCase() + ' src', url: abs(el.getAttribute('src')), text: el.tagName.toLowerCase() + (el.title ? ' "' + el.title + '"' : '') }));
  document.querySelectorAll('meta[http-equiv]').forEach((m) => {
    if (!/refresh/i.test(m.getAttribute('http-equiv') || '')) return;
    const r = /url\s*=\s*['"]?([^'";]+)/i.exec(m.getAttribute('content') || '');
    if (r) out.push({ kind: 'meta refresh', url: abs(r[1]), text: '<meta refresh>' });
  });
  return out;
}

/* The headings showing now: the dump lists them, so a reader can see which
   states each crawl reached. */
function visibleHeadings() {
  return Array.from(document.querySelectorAll('h1, h2, h3')).filter((h) => h.offsetWidth || h.offsetHeight)
    .map((h) => (h.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 90)).filter(Boolean);
}

/* Tags the clickable elements not seen before and returns them. An element
   that looks exactly like one already clicked (same kind, address, text and
   data) is tagged but not clicked again, so re rendered lists stay finite. */
function tagNew(max) {
  const C = window.__crawl;
  C.seen = C.seen || new Set();
  C.next = C.next || 0;
  const SEL = 'a[href], area[href], button, input[type=submit], input[type=button], input[type=image], summary, '
    + '[role=button], [role=menuitem], [role=menuitemcheckbox], [role=menuitemradio], [role=tab], [role=link], [role=switch], [onclick], [data-cta]';
  const words = (el) => ((el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim()
    || el.getAttribute('aria-label') || el.getAttribute('title') || el.value || '').slice(0, 90);
  const out = [];
  for (const el of document.querySelectorAll(SEL)) {
    if (el.hasAttribute('data-crawl-i')) continue;
    const id = String(C.next++);
    el.setAttribute('data-crawl-i', id);
    const data = Array.from(el.attributes).filter((a) => a.name.startsWith('data-') && a.name !== 'data-crawl-i').map((a) => a.name + '=' + a.value).sort().join('&');
    const sig = [el.tagName, el.getAttribute('href') || '', el.getAttribute('target') || '', words(el), el.id, data, el.getAttribute('role') || '',
      el.getAttribute('aria-controls') || '', el.getAttribute('name') || '', el.getAttribute('type') || '', el.getAttribute('onclick') || ''].join('|');
    if (C.seen.has(sig)) continue;
    C.seen.add(sig);
    const w = words(el);
    const role = el.getAttribute('role');
    out.push({ id, label: el.tagName.toLowerCase() + (role ? '[role=' + role + ']' : '') + (w ? ' "' + w + '"' : (el.id ? ' #' + el.id : '')),
      fast: (!!el.closest('a[href], area[href]') || el.tagName === 'SUMMARY') && !el.hasAttribute('onclick') });
    if (out.length >= max) break;
  }
  return out;
}

/* Clicks one tagged element. A link or form that would open a new tab is
   pointed at this tab for the click, so the navigation is recorded and
   cancelled here, then put back. */
async function clickOne(arg) {
  const C = window.__crawl;
  const el = document.querySelector('[data-crawl-i="' + arg.id + '"]');
  if (!el || !el.isConnected) return false;
  C.label = arg.label;
  const fixes = [];
  const retarget = (node, attr) => {
    if (!node) return;
    const t = node.getAttribute(attr);
    if (t !== null && t.toLowerCase() !== '_self') { fixes.push([node, attr, t]); node.setAttribute(attr, '_self'); }
  };
  retarget(el.closest('a[href], area[href]'), 'target');
  retarget(el.form || el.closest('form'), 'target');
  retarget(el, 'formtarget');
  try {
    if (typeof el.click === 'function') el.click();
    else el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
  } catch (e) { /* the page's own handler threw; carry on */ }
  for (const [node, attr, t] of fixes) node.setAttribute(attr, t);
  await new Promise((r) => setTimeout(r, arg.fast ? 0 : 30));
  return true;
}

/* Fills and submits every visible form not submitted before. Never fills a
   honeypot, a file input, a password or a read only field. A submission
   navigates a moment later, so each one is given that moment before the
   next step takes over the label. */
async function fillForms() {
  const C = window.__crawl;
  C.formsDone = C.formsDone || new Set();
  const vis = (el) => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length) && getComputedStyle(el).visibility !== 'hidden';
  const honey = (el) => el.tabIndex === -1 || el.getAttribute('aria-hidden') === 'true' || !!el.closest('[aria-hidden="true"]')
    || /honey|website|homepage/i.test([el.name, el.id, el.className].join(' '));
  const setValue = (el, v) => {
    const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : (el instanceof HTMLSelectElement ? HTMLSelectElement.prototype : HTMLInputElement.prototype);
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  };
  const valueFor = (el) => {
    const t = (el.type || 'text').toLowerCase();
    const hint = [el.name, el.id, el.getAttribute('autocomplete'), el.getAttribute('inputmode'), el.placeholder].join(' ').toLowerCase();
    if (t === 'email') return 'crawler@example.co.za';
    if (t === 'tel') return el.required ? '010 000 0000' : null;
    if (t === 'number' || t === 'range') return el.min || '1';
    if (t === 'date') return '2026-10-01';
    if (t === 'month') return '2026-10';
    if (t === 'time') return '09:00';
    if (t === 'url') return el.required ? 'https://example.co.za' : null;
    if (/one-time-code|pin|otp|numeric/.test(hint) || el.maxLength === 6) return '123456';
    if (/company|organi[sz]ation|employer/.test(hint)) return COMPANY_NAME;
    if (/name/.test(hint)) return 'Crawl Tester';
    if (/reason|note|comment|scope|evidence|ref/.test(hint)) return 'Crawl test entry';
    return 'Crawl Test';
  };
  const COMPANY_NAME = 'Crawl Test (Pty) Ltd';
  const done = [];
  for (const form of document.querySelectorAll('form')) {
    if (!vis(form)) continue;
    const fields = Array.from(form.elements).filter((e) => e.tagName !== 'BUTTON' && e.tagName !== 'FIELDSET' && e.tagName !== 'OUTPUT' && vis(e) && !e.disabled && !e.readOnly && !honey(e));
    const sig = (form.id || form.getAttribute('name') || form.className) + '|' + fields.map((e) => e.name || e.id || e.type).join(',');
    if (C.formsDone.has(sig)) continue;
    C.formsDone.add(sig);
    const radios = new Set();
    for (const e of fields) {
      const t = (e.type || '').toLowerCase();
      if (t === 'hidden' || t === 'file' || t === 'password' || t === 'submit' || t === 'button' || t === 'reset' || t === 'image') continue;
      if (t === 'checkbox') { if (!e.checked) e.click(); continue; }
      if (t === 'radio') { if (!radios.has(e.name)) { radios.add(e.name); if (!form.querySelector('input[type=radio][name="' + CSS.escape(e.name) + '"]:checked')) e.click(); } continue; }
      if (e.tagName === 'SELECT') {
        const o = Array.from(e.options).find((x) => x.value && !x.disabled);
        if (o) setValue(e, o.value);
        continue;
      }
      if (e.value) continue;
      const v = valueFor(e);
      if (v !== null) setValue(e, v);
    }
    const btn = form.querySelector('button[type=submit], button:not([type]), input[type=submit]');
    const words = btn ? (btn.innerText || btn.textContent || btn.value || '').replace(/\s+/g, ' ').trim().slice(0, 60) : '';
    C.label = 'submitting form' + (form.id ? ' #' + form.id : '') + (words ? ' "' + words + '"' : '');
    try { if (typeof form.requestSubmit === 'function') form.requestSubmit(); else form.submit(); } catch (e) { /* invalid on purpose or refused */ }
    done.push(C.label);
    await new Promise((r) => setTimeout(r, 30));
  }
  /* A search box outside a form: type into it once. */
  for (const el of document.querySelectorAll('input[type=search]')) {
    if (el.form || !vis(el) || el.disabled || el.readOnly || el.dataset.crawlTyped) continue;
    el.dataset.crawlTyped = '1';
    C.label = 'typing in search #' + (el.id || el.name || '');
    setValue(el, 'Crawl');
    done.push(C.label);
    await new Promise((r) => setTimeout(r, 30));
  }
  return done;
}

function tagSelects() {
  const vis = (el) => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
  const out = [];
  document.querySelectorAll('select').forEach((s, i) => {
    if (s.dataset.crawlSelect || s.disabled || !vis(s)) return;
    s.dataset.crawlSelect = 'sel' + i + '_' + Math.random().toString(36).slice(2, 7);
    out.push({ id: s.dataset.crawlSelect, label: 'select ' + (s.id ? '#' + s.id : (s.name || '')), options: Math.min(s.options.length, 40), start: s.selectedIndex });
  });
  return out;
}
async function chooseOption(arg) {
  const s = document.querySelector('select[data-crawl-select="' + arg.id + '"]');
  if (!s || !s.isConnected || arg.index < 0 || arg.index >= s.options.length) return false;
  window.__crawl.label = arg.restore ? 'putting back ' + arg.label : arg.label + ' option "' + (s.options[arg.index].textContent || '').trim().slice(0, 60) + '"';
  s.selectedIndex = arg.index;
  s.dispatchEvent(new Event('input', { bubbles: true }));
  s.dispatchEvent(new Event('change', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 25));
  return true;
}

/* ------------------------------------------------------------ one crawl */
async function crawl(browser, origin, item, viewport) {
  const run = {
    item, viewport, label: 'page load', allowNav: true, targets: [], pageErrors: [], warnings: [], clicks: 0, capped: false,
    api: API[item.api || 'none'](origin), apiCalls: [], headings: new Set()
  };
  const context = await browser.newContext({ viewport, serviceWorkers: 'block', acceptDownloads: false });
  const page = await context.newPage();
  /* Each distinct (kind, address, element) once per crawl. */
  const seenTargets = new Set();
  const keep = (t) => {
    const k = t.kind + '\u0001' + t.url + '\u0001' + t.text;
    if (seenTargets.has(k)) return;
    seenTargets.add(k);
    run.targets.push(t);
  };
  await context.addInitScript(instrument, item.session === undefined ? null : item.session);
  context.on('page', (p) => { if (p !== page) setTimeout(() => p.close().catch(() => {}), 300); });
  page.on('pageerror', (e) => run.pageErrors.push(String(e && e.message ? e.message : e).slice(0, 200)));
  /* Requests the page has in flight: after a button click the crawl waits for
     them, so a navigation that follows an answer is put down to that click. */
  let inflight = 0;
  page.on('request', () => { inflight++; });
  page.on('requestfinished', () => { inflight = Math.max(0, inflight - 1); });
  page.on('requestfailed', () => { inflight = Math.max(0, inflight - 1); });
  const quiet = async (limit) => {
    const until = Date.now() + (limit || 1500);
    while (inflight > 0 && Date.now() < until) await page.waitForTimeout(25);
  };
  page.on('dialog', (d) => d.dismiss().catch(() => {}));

  await context.route('**/*', async (route) => {
    const req = route.request();
    let u;
    try { u = new URL(req.url()); } catch (_) { return route.abort().catch(() => {}); }
    let frame = null;
    try { frame = req.frame(); } catch (_) { frame = null; }
    if (req.isNavigationRequest()) {
      const main = frame && frame === page.mainFrame();
      if (main && run.allowNav) { run.allowNav = false; return route.continue().catch(() => {}); }
      keep({ kind: main ? 'navigation request' : (frame && frame.page() === page ? 'frame navigation' : 'new tab or window'), url: req.url(), text: run.label });
      return route.fulfill({ status: 204, body: '' }).catch(() => {});
    }
    if (u.origin === origin) {
      if (u.pathname.startsWith('/api/')) {
        let body = null;
        try { body = req.postDataJSON(); } catch (_) { body = null; }
        const r = run.api(req.method(), u.pathname, u.searchParams, body);
        run.apiCalls.push(req.method() + ' ' + u.pathname + (u.search ? u.search : '') + ' ' + r.status);
        return route.fulfill({ status: r.status, contentType: 'application/json', body: JSON.stringify(r.body) }).catch(() => {});
      }
      return route.continue().catch(() => {});
    }
    const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS' };
    if (/supabase-js/i.test(u.pathname) || (u.hostname === 'esm.sh' && /supabase/i.test(u.pathname))) {
      if (item.supabase === 'fail') return route.fulfill({ status: 503, headers: cors, body: 'unavailable in the crawl' }).catch(() => {});
      return route.fulfill({ status: 200, headers: Object.assign({ 'content-type': 'application/javascript; charset=utf-8' }, cors), body: FAKE_SUPABASE_JS }).catch(() => {});
    }
    if (/\.supabase\.co$/i.test(u.hostname)) {
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors, body: '' }).catch(() => {});
      return route.fulfill({ status: 200, headers: Object.assign({ 'content-type': 'application/json' }, cors), body: u.pathname.startsWith('/rest/') ? '[]' : '{}' }).catch(() => {});
    }
    /* Images, fonts and anything else off this server: refused. */
    return route.abort('blockedbyclient').catch(() => {});
  });

  const settle = async (ms) => {
    await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(ms || 150);
  };
  const pull = async () => {
    const h = await page.evaluate(visibleHeadings).catch(() => []);
    h.forEach((x) => run.headings.add(x));
    const t = await page.evaluate(collectTargets).catch(() => []);
    t.forEach((x) => keep(x));
    const ev = await page.evaluate(() => (window.__crawl ? window.__crawl.events.splice(0) : [])).catch(() => []);
    ev.forEach((e) => keep({ kind: e.kind, url: e.url, text: e.label }));
  };

  const pageUrl = origin + item.path;
  let res;
  try {
    res = await page.goto(pageUrl, { waitUntil: 'load', timeout: 60000 });
  } catch (e) {
    run.openError = 'could not open: ' + String(e && e.message ? e.message.split('\n')[0] : e);
  }
  if (!run.openError && (!res || res.status() >= 400)) run.openError = 'could not open: HTTP ' + (res ? res.status() : 'no response');
  if (run.openError) { await context.close().catch(() => {}); return run; }
  /* A server redirect is followed before any page script runs: the address
     the page opened at is a target too. */
  keep({ kind: 'address the page opened at', url: page.url(), text: 'opening ' + item.path });
  await settle(300);

  if (item.view) {
    const btn = page.getByRole('button', { name: item.view });
    try {
      await btn.first().waitFor({ state: 'visible', timeout: 20000 });
      run.label = 'choosing the view "' + item.view + '"';
      await btn.first().click({ timeout: 10000 });
      await settle(400);
      const pressed = await btn.first().getAttribute('aria-pressed').catch(() => null);
      if (pressed === 'false') run.warnings.push('the view "' + item.view + '" did not become the chosen view');
    } catch (e) {
      run.warnings.push('the view "' + item.view + '" could not be chosen: ' + String(e && e.message ? e.message.split('\n')[0] : e));
    }
  }
  if (item.expect) {
    const ok = await page.evaluate(item.expect).catch(() => false);
    if (!ok) run.warnings.push('the state "' + item.state + '" was not reached (its expected form is not showing)');
  }
  await pull();

  for (let round = 0; round < 4; round++) {
    let did = 0;
    run.label = 'filling forms';
    const submitted = await page.evaluate(fillForms).catch(() => []);
    did += submitted.length;
    if (submitted.length) { await quiet(); await settle(250); await pull(); }

    const selects = await page.evaluate(tagSelects).catch(() => []);
    for (const s of selects) {
      for (let i = 0; i < s.options; i++) {
        run.label = s.label + ' option ' + (i + 1);
        const ok = await page.evaluate(chooseOption, { id: s.id, index: i, label: s.label }).catch(() => false);
        if (!ok) break;
        did++;
        await pull();
      }
      /* Put the first choice back, so a filter does not hide what the clicks
         below should reach. */
      await page.evaluate(chooseOption, { id: s.id, index: s.start, label: s.label, restore: true }).catch(() => false);
    }

    for (;;) {
      if (run.clicks >= MAX_CLICKS) { run.capped = true; break; }
      const batch = await page.evaluate(tagNew, 200).catch(() => []);
      if (!batch.length) break;
      for (const it of batch) {
        if (run.clicks >= MAX_CLICKS) { run.capped = true; break; }
        run.clicks++; did++;
        run.label = it.label;
        await page.evaluate(clickOne, it).catch(() => false);
        if (!it.fast) {
          await quiet();
          /* A form this click has just shown is filled and sent at once, so
             the walk carries on from the state the click reached. */
          const sent = await page.evaluate(fillForms).catch(() => []);
          if (sent.length) { await quiet(); await settle(100); await pull(); }
        }
        if (run.clicks % 40 === 0) await pull();
      }
      await settle(100);
      await pull();
    }
    if (!did) break;
  }
  run.label = 'after the last click';
  await page.waitForTimeout(600);
  await pull();
  await context.close().catch(() => {});
  return run;
}

/* ------------------------------------------------------------ main */
/* opts.quick crawls the quick plan; opts.log receives the report lines
   (console.log by default). Resolves with the exit code: 0 pass, 1 fail. */
async function main(opts) {
  const o = opts || {};
  const log = o.log || ((line) => console.log(line));
  const plan = crawlPlan(!!o.quick);
  if (LIST) {
    plan.forEach((c) => log(c.path.padEnd(58) + ' ' + c.state));
    log('file-links: ' + plan.length + ' page states at ' + VIEWPORTS.map((v) => v.width).join(' and '));
    return 0;
  }
  if (!plan.length || !VIEWPORTS.length) { log('file-links: nothing to crawl (check --only and --width)'); return 2; }
  const started = Date.now();
  const server = createServer({ quiet: true, root: VERCEL });
  await new Promise((ok, bad) => { server.once('error', bad); server.listen(0, '127.0.0.1', ok); });
  const origin = 'http://127.0.0.1:' + server.address().port;
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch();

  const jobs = [];
  for (const item of plan) for (const vp of VIEWPORTS) jobs.push({ item, vp });
  const runs = [];
  let next = 0;
  async function worker() {
    while (next < jobs.length) {
      const j = jobs[next++];
      const t0 = Date.now();
      let run;
      let timer;
      try {
        run = await Promise.race([
          crawl(browser, origin, j.item, j.vp),
          new Promise((_, bad) => { timer = setTimeout(() => bad(new Error('the crawl took longer than ' + CRAWL_TIMEOUT_MS / 1000 + ' seconds')), CRAWL_TIMEOUT_MS); })
        ]);
      } catch (e) {
        run = { item: j.item, viewport: j.vp, targets: [], pageErrors: [], warnings: [], clicks: 0, apiCalls: [], headings: new Set(), crashed: String(e && e.message ? e.message : e) };
      } finally { clearTimeout(timer); }
      runs.push(run);
      if (VERBOSE) {
        console.error('  ' + (j.item.path + ' (' + j.item.state + ')').padEnd(78) + ' ' + String(j.vp.width).padStart(4) + 'px  '
          + String(run.targets.length).padStart(5) + ' targets  ' + String(run.clicks).padStart(4) + ' clicks  ' + ((Date.now() - t0) / 1000).toFixed(1) + 's'
          + (run.openError ? '  ' + run.openError : '') + (run.crashed ? '  CRASHED: ' + run.crashed : '')
          + (run.pageErrors.length ? '  page errors: ' + run.pageErrors.length : ''));
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(JOBS, jobs.length) }, worker));
  await browser.close();
  await new Promise((ok) => server.close(ok));

  /* ---- judge */
  const localPath = (u) => (u.startsWith(origin) ? u.slice(origin.length) || '/' : u);
  const violations = new Map();
  const failures = [];
  const warnings = [];
  let checked = 0;
  for (const run of runs) {
    const where = run.item.path + ' (' + run.item.state + ')';
    if (run.openError) failures.push(where + ' at ' + run.viewport.width + 'px: ' + run.openError);
    if (run.crashed) failures.push(where + ' at ' + run.viewport.width + 'px: the crawl stopped: ' + run.crashed);
    run.warnings.forEach((w) => warnings.push(where + ' at ' + run.viewport.width + 'px: ' + w));
    if (run.capped) warnings.push(where + ' at ' + run.viewport.width + 'px: stopped clicking after ' + MAX_CLICKS + ' elements');
    const pageUrl = origin + run.item.path;
    for (const t of run.targets) {
      checked++;
      const hit = lib.planTarget(t.url, pageUrl, [origin]);
      if (!hit) continue;
      const key = [where, t.text, t.url].join('\u0001');
      const v = violations.get(key) || { where, kinds: new Set(), text: t.text, target: localPath(t.url), plan: hit.path, via: hit.via, widths: new Set() };
      v.widths.add(run.viewport.width);
      v.kinds.add(t.kind);
      violations.set(key, v);
    }
  }
  if (VERBOSE) {
    const errs = new Map();
    runs.forEach((r) => r.pageErrors.forEach((e) => errs.set(r.item.path + ': ' + e, (errs.get(r.item.path + ': ' + e) || 0) + 1)));
    if (errs.size) { console.error('file-links: script errors on the pages (for information):'); errs.forEach((n, e) => console.error('  ' + e + (n > 1 ? ' (x' + n + ')' : ''))); }
  }

  if (DUMP) {
    fs.writeFileSync(DUMP, JSON.stringify(runs.map((r) => ({ path: r.item.path, state: r.item.state, width: r.viewport.width, clicks: r.clicks,
      openError: r.openError || null, crashed: r.crashed || null, warnings: r.warnings, pageErrors: r.pageErrors,
      apiCalls: r.apiCalls || [], headings: Array.from(r.headings || []),
      targets: r.targets.map((t) => ({ kind: t.kind, text: t.text, url: localPath(t.url) })) })), null, 1));
  }
  if (violations.size) {
    log('file-links: File pages that lead to a Medical Surveillance Plan page (contract 15.1):');
    const list = Array.from(violations.values()).sort((a, b) => (a.where + a.text).localeCompare(b.where + b.text));
    for (const v of list) {
      log('  ' + v.where + ' at ' + Array.from(v.widths).sort((a, b) => b - a).join(' and ') + 'px: ' + v.text + ' -> '
        + v.target + ' (Plan page ' + v.plan + (v.via.length ? ', ' + v.via.join('; ') : '') + '; ' + Array.from(v.kinds).sort().join(', ') + ')');
    }
  }
  if (failures.length) { log('file-links: pages the crawl could not check:'); failures.forEach((f) => log('  ' + f)); }
  if (warnings.length) { log('file-links: warnings:'); warnings.forEach((w) => log('  ' + w)); }

  const pages = new Set(plan.map((c) => c.path.split(/[?#]/)[0])).size;
  const ok = !violations.size && !failures.length;
  const secs = ((Date.now() - started) / 1000).toFixed(0);
  log('file-links: ' + (ok ? 'PASS' : 'FAIL') + ', ' + pages + ' File pages in ' + plan.length + ' states at '
    + VIEWPORTS.map((v) => v.width).join(' and ') + 'px (' + runs.length + ' crawls, ' + runs.reduce((n, r) => n + r.clicks, 0) + ' clicks), '
    + checked + ' links, form actions, navigations and window.open calls checked, ' + violations.size + ' Plan page targets, '
    + failures.length + ' pages not checked, ' + warnings.length + ' warnings, ' + secs + 's');
  return ok ? 0 : 1;
}

/* Node 22's "node --test" also runs every script under a test/ folder, this
   one included. There the crawl is one test that fails on any Plan target or
   any page it could not check, and is skipped only when Playwright or its
   Chromium is missing. It crawls the quick plan unless CNC_FILE_LINKS=full. */
if (process.env.NODE_TEST_CONTEXT) {
  const { test } = await import('node:test');
  const missing = chromiumMissing();
  const full = process.env.CNC_FILE_LINKS === 'full';
  test('the File pages never lead to the Plan pages, in Chromium (contract 15.1)', {
    skip: missing ? missing + ': run node test/browser/file-links.mjs where Chromium is installed' : false,
    timeout: 20 * 60 * 1000
  }, async (t) => {
    const lines = [];
    const code = await main({ quick: !full, log: (line) => lines.push(line) });
    if (lines.length) t.diagnostic(lines[lines.length - 1]);
    if (code !== 0) throw new Error('\n' + lines.join('\n'));
  });
} else {
  main({ quick: QUICK }).then((code) => process.exit(code), (e) => {
    console.error('file-links: the crawl could not run: ' + (e && e.stack ? e.stack : e));
    console.log('file-links: FAIL, the crawl could not run');
    process.exit(1);
  });
}
