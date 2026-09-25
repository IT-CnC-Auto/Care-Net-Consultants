#!/usr/bin/env node
/* =====================================================================
   bee-inspect-ads.mjs :: the Bee-Inspect P1 banners, rendered
   hsf/BUILD-CONTRACT.md 16.3; hsf/BEE-INSPECT-BUILD-PROMPT.md A1, A2, A4

   Starts server/serve.js on a free local port and drives Chromium at 1280
   and 390 pixels wide through every placement and state:
     hsf-builder demonstration  consent card first (no banner), then the
                   File view: AD-05 twin of the Bee-Matched box, AD-04 in
                   the compliance strip (1280 only), AD-01 at the top of
                   Section F with its gaps wording, AD-07 after Section F,
                   AD-02 in the First File guide's Section F step, AD-03 in
                   the gap report after the Section F gaps
     hsf-builder live (sign in and /api answered in the browser by stubs):
                   loading, signed out, no company account, sign in
                   unreachable, consent, setup (no banner in any), and the
                   File view (AD-01, AD-03, AD-04, AD-05; never AD-07)
     health-and-safety-file  AD-06 between "Two ways" and "What is in the
                   File", outside the pricing table
     portal        AD-08 on the Files side in the demonstration and signed
                   in with a File; none signed in without one or signed out
   and checks: the banners and what they say; none on a forbidden state or
   inside the consent panel; at most two on any one screen while scrolling;
   no layout shift from the banners (CLS measured with PerformanceObserver,
   flag on against flag off, loading and scrolling); flag off shows nothing
   and sends nothing; dismiss hides for 14 days, AD-01 and AD-05 collapse to
   a strip with Show and come back; keyboard focus is visible; one
   impression per banner per page view with only the six fields; no link to
   a Plan page; and the File flow of the demonstration (consent, drop a
   document, the upload queue, sign off readiness) still works with the
   banners on.

   Run:  node test/browser/bee-inspect-ads.mjs            (checks)
         node test/browser/bee-inspect-ads.mjs --shots    (and writes the
               screenshots of every placement at 1280 and 390 to
               docs/bee-inspect/p1/)
   "node --test" runs the checks (never the screenshots) as one test, and
   skips it only when Playwright or its Chromium is missing.

   Playwright: require('playwright') if installed, else the global copy at
   /opt/node22/lib/node_modules/playwright, or PLAYWRIGHT_MODULE. Browsers
   from PLAYWRIGHT_BROWSERS_PATH (for example /opt/pw-browsers). Every
   address off the local server is refused or answered by a stub: nothing
   reaches Supabase, Vercel or any live service.
   ===================================================================== */

import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..', '..');
const VERCEL = path.join(ROOT, 'vercel');
const SHOT_DIR = path.join(ROOT, 'docs', 'bee-inspect', 'p1');
for (const k of Object.keys(process.env)) if (/^SUPABASE_|^MCO_|^XAI_|^CNC_KERNEL/.test(k)) delete process.env[k];

globalThis.__CNC_FILE_SEPARATION_LIB_ONLY = true;
const lib = require('../api/file-separation.test.js');
const { createServer } = require('../../server/serve.js');

const PLAYWRIGHT_TRIES = [process.env.PLAYWRIGHT_MODULE, 'playwright', '/opt/node22/lib/node_modules/playwright'].filter(Boolean);
function findPlaywright() {
  for (const t of PLAYWRIGHT_TRIES) { try { return require(t); } catch (_) { /* next */ } }
  return null;
}
function chromiumMissing() {
  const pw = findPlaywright();
  if (!pw || !pw.chromium) return 'Playwright was not found (tried ' + PLAYWRIGHT_TRIES.join(', ') + ')';
  let exe = '';
  try { exe = pw.chromium.executablePath(); } catch (_) { exe = ''; }
  if (!exe || !fs.existsSync(exe)) return 'Chromium was not found (' + (exe || 'no path') + '; set PLAYWRIGHT_BROWSERS_PATH)';
  return null;
}

const VIEWPORTS = [{ width: 1280, height: 900 }, { width: 390, height: 844 }];
const DAY = 86400000;

/* ------------------------------------------------------------ stubs */
const USER = { access_token: 'bee-access-token', token_type: 'bearer', expires_in: 3600, refresh_token: 'bee-refresh',
  user: { id: '00000000-0000-4000-8000-0000000000be', email: 'bee@example.co.za', app_metadata: {}, user_metadata: {} } };
const FAKE_SUPABASE_JS = `
const current = () => (globalThis.__BEE_SESSION || null);
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
      async signOut() { return { error: null }; }
    },
    from: () => query(),
    rpc: async () => ({ data: null, error: null })
  };
}
export default { createClient };
`;
const COMPANY = 'Bee Test Works (Pty) Ltd (fictitious)';
const CONSENT_DONE = { client_account_id: 'bee-account', company_name: COMPANY, wording_version: 'HSF-CONSENT-1.0', document_storage: true, mco_transfer: true, authority_to_share: true, complete: true };
const CONSENT_NONE = Object.assign({}, CONSENT_DONE, { document_storage: false, mco_transfer: false, authority_to_share: false, complete: false });
const GATE = { uploads_open: true, client_verified: true, verification_requested: false, deletion_sms_available: false, consent_complete: true };
const FILE_ROW = { file_id: 'bee-file-1', reference: 'CNC-HSF-2026-0924-001', industry_code: 'MANUF', industry_name: 'Manufacturing', status: 'draft', revision: 1, compliance_pct: 25, created_at: '2026-09-24T08:00:00Z' };
function detail() {
  const item = (sec, n, status, name) => ({ item_id: 'bee-' + sec + n, element_code: 'HSF-' + sec + '-0' + n, name, duty: 'A fictitious duty for the test.', evidence_type: 'register',
    review_interval: 'annual', status, reason: null, due_date: null, citable: [], awaiting: [], uploads: [] });
  const secs = 'ABCDEFGHIJKLMNO'.split('').map((c) => ({ code: c, name: '', compliance_pct: 50, items: [item(c, 1, 'uploaded', 'Uploaded record ' + c), item(c, 2, 'outstanding', 'Outstanding record ' + c)] }));
  secs[5].items.push(item('F', 3, 'expired', 'Ladder inspection register'), item('F', 4, 'outstanding', 'Scaffold inspection register'));
  return { file: { id: 'bee-file-1', reference: FILE_ROW.reference, industry_code: 'MANUF', industry_name: 'Manufacturing', company_name: COMPANY, status: 'draft', revision: 1, regime: 'OHSA' },
    sections: secs, overall: { pct: 46.9, counts: { uploaded: 15, linked_mco: 0, outstanding: 16, expired: 1, not_applicable: 0 } } };
}
const json = (status, body, delay) => ({ status, body, delay });
const API = {
  none: () => json(404, { error: 'Not available in the test.' }),
  signedOut: () => json(401, { error: 'Please sign in first.' }),
  noAccount: (m, p) => (p === '/api/hsf-consent' ? json(200, { client_account_id: null, complete: false }) : json(404, {})),
  slowConsent: (m, p) => (p === '/api/hsf-consent' ? json(200, CONSENT_DONE, 6000) : json(404, {})),
  live: (consent, files) => (m, p, q) => {
    if (p === '/api/hsf-consent') return json(200, consent);
    if (p === '/api/hsf-upload' && q.get('gate')) return json(200, Object.assign({}, GATE, { consent_complete: consent.complete }));
    if (p === '/api/hsf-upload') return json(200, []);
    if (p === '/api/hsf-file' && q.get('file_id')) return json(200, detail());
    if (p === '/api/hsf-file') return json(200, files ? [FILE_ROW] : []);
    return json(404, {});
  },
  portal: (files) => (m, p, q) => {
    if (p === '/api/portal-summary') return json(200, { account: { client_account_id: 'bee-account', company_name: COMPANY, account_kind: 'client', approved_at: null }, plans: [], quotes: [], files: files ? [FILE_ROW] : [] });
    if (p === '/api/hsf-file' && q.get('file_id')) return json(200, detail());
    return json(404, {});
  }
};

/* ------------------------------------------------------------ in the page */
function initPage(arg) {
  if (window.top !== window) return;
  window.__BEE_SESSION = arg.session;
  try { localStorage.setItem('cnc_consent_v1', JSON.stringify({ analytics: false, marketing: false, savedAt: Date.now() })); } catch (e) { /* none */ }
  if (arg.store !== undefined) { try { if (arg.store) localStorage.setItem('cnc_bee_ads_v1', arg.store); else localStorage.removeItem('cnc_bee_ads_v1'); } catch (e) { /* none */ } }
  window.__cls = 0; window.__shifts = [];
  try {
    new PerformanceObserver((l) => {
      for (const e of l.getEntries()) {
        if (e.hadRecentInput) continue;
        window.__cls += e.value;
        window.__shifts.push({ v: e.value, t: Math.round(e.startTime), n: (e.sources || []).map((s) => s.node && s.node.nodeType === 1 ? (s.node.id || s.node.className || s.node.tagName) : '#').join(',') });
      }
    }).observe({ type: 'layout-shift', buffered: true });
  } catch (e) { /* no observer */ }
}
function bannerState() {
  const out = [];
  document.querySelectorAll('[data-cnc-ad]').forEach((el) => {
    const b = el.querySelector('.cnc-ad');
    const r = (b || el).getBoundingClientRect();
    out.push({ id: el.getAttribute('data-cnc-ad'), shown: !!b && r.height > 0, height: Math.round(r.height), top: Math.round(r.top + scrollY),
      kind: b ? (b.className.match(/cnc-ad--(\w+)/) || [])[1] : null, v: b ? b.getAttribute('data-v') : null,
      text: b ? b.textContent.replace(/\u2011/g, '-').replace(/\s+/g, ' ').trim() : '', hrefs: b ? Array.from(b.querySelectorAll('a[href]')).map((a) => [a.href, a.target, a.rel]) : [] });
  });
  return out;
}
function onScreen() {
  return Array.from(document.querySelectorAll('.cnc-ad')).filter((b) => { const r = b.getBoundingClientRect(); return r.height > 0 && r.bottom > 0 && r.top < innerHeight; })
    .map((b) => b.parentNode.getAttribute('data-cnc-ad'));
}

/* ------------------------------------------------------------ harness */
const results = [];
function check(name, cond, detail) {
  results.push({ name, ok: !!cond, detail: cond ? '' : (detail === undefined ? '' : (typeof detail === 'string' ? detail : JSON.stringify(detail))) });
}

async function open(browser, origin, vp, o) {
  const opts = o || {};
  const context = await browser.newContext({ viewport: vp, serviceWorkers: 'block', reducedMotion: 'reduce' });
  await context.addInitScript(initPage, { session: opts.session === undefined ? null : opts.session, store: opts.store });
  const page = await context.newPage();
  const run = { page, context, events: [], errors: [], apiCalls: [] };
  page.on('pageerror', (e) => run.errors.push(String(e && e.message ? e.message : e).slice(0, 200)));
  const api = opts.api || API.none;
  await context.route('**/*', async (route) => {
    const req = route.request();
    let u;
    try { u = new URL(req.url()); } catch (_) { return route.abort().catch(() => {}); }
    if (u.origin === origin) {
      if (u.pathname === '/api/hsf-events') {
        let b = null;
        try { b = JSON.parse(req.postData() || 'null'); } catch (_) { b = 'unparsable'; }
        run.events.push({ body: b, headers: req.headers() });
        return route.fulfill({ status: 202, contentType: 'application/json', body: '{"accepted":false}' }).catch(() => {});
      }
      if (u.pathname.startsWith('/api/')) {
        let body = null;
        try { body = req.postDataJSON(); } catch (_) { body = null; }
        const r = api(req.method(), u.pathname, u.searchParams, body);
        run.apiCalls.push(req.method() + ' ' + u.pathname + u.search);
        if (r.delay) await new Promise((ok) => setTimeout(ok, r.delay));
        return route.fulfill({ status: r.status, contentType: 'application/json', body: JSON.stringify(r.body) }).catch(() => {});
      }
      return route.continue().catch(() => {});
    }
    const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET, POST, OPTIONS' };
    if (/supabase-js/i.test(u.pathname) || (u.hostname === 'esm.sh' && /supabase/i.test(u.pathname))) {
      if (opts.supabase === 'fail') return route.fulfill({ status: 503, headers: cors, body: 'unavailable' }).catch(() => {});
      return route.fulfill({ status: 200, headers: Object.assign({ 'content-type': 'application/javascript; charset=utf-8' }, cors), body: FAKE_SUPABASE_JS }).catch(() => {});
    }
    if (/\.supabase\.co$/i.test(u.hostname)) {
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors, body: '' }).catch(() => {});
      return route.fulfill({ status: 200, headers: Object.assign({ 'content-type': 'application/json' }, cors), body: u.pathname.startsWith('/rest/') ? '[]' : '{}' }).catch(() => {});
    }
    return route.abort('blockedbyclient').catch(() => {});
  });
  if (opts.path) {
    await page.goto(origin + opts.path, { waitUntil: 'load', timeout: 60000 });
    await page.waitForTimeout(opts.wait || 500);
  }
  return run;
}
const visibleState = (page) => page.evaluate(() => ['st-loading', 'st-error', 'st-signin', 'st-noaccount', 'st-consent', 'st-setup', 'st-file']
  .filter((id) => { const e = document.getElementById(id); return e && !e.hidden; }));
async function giveConsent(page) {
  await page.check('#c-storage'); await page.check('#c-transfer'); await page.check('#c-authority');
  await page.click('#consent-btn');
  await page.waitForTimeout(500);
}
async function scrollScan(page) {
  const H = await page.evaluate(() => document.documentElement.scrollHeight);
  let most = 0; let where = null;
  for (let y = 0; y < H; y += 150) {
    await page.evaluate((yy) => window.scrollTo(0, yy), y);
    await page.waitForTimeout(40);
    const ids = await page.evaluate(onScreen);
    if (ids.length > most) { most = ids.length; where = { y, ids }; }
  }
  await page.waitForTimeout(300);
  return { most, where };
}
const byId = (list) => Object.fromEntries(list.map((b) => [b.id, b]));
const cls = (page) => page.evaluate(() => ({ cls: window.__cls, shifts: window.__shifts }));

async function shot(page, id, name, vp, opts) {
  if (!opts.shots) return;
  const el = await page.$('[data-cnc-ad="' + id + '"]');
  const target = (el && await el.boundingBox()) ? el : (opts.fallback ? await page.$(opts.fallback) : null);
  if (!target) { check('screenshot ' + name + ': the banner is there', false); return; }
  await page.addStyleTag({ content: '.cnc-secnav{display:none!important}' });
  await page.evaluate((e) => e.scrollIntoView({ block: 'center' }), target);
  await page.waitForTimeout(350);
  const bb = await target.boundingBox();
  if (!bb) { check('screenshot ' + name + ': the region is displayed', false); return; }
  const above = opts.above === undefined ? 140 : opts.above;
  const y = Math.max(0, bb.y - above);
  const h = Math.min(vp.height - y, bb.height + above + 50);
  fs.mkdirSync(SHOT_DIR, { recursive: true });
  const file = path.join(SHOT_DIR, name + '-' + vp.width + '.png');
  await page.screenshot({ path: file, clip: { x: 0, y, width: vp.width, height: h } });
  const kb = fs.statSync(file).size / 1024;
  check('screenshot ' + path.basename(file) + ' is under 300 KB (' + kb.toFixed(0) + ' KB)', kb < 300);
  opts.list.push({ file: path.basename(file), kb: Math.round(kb) });
}

/* ------------------------------------------------------------ scenarios */
async function reveal(page, id) {
  await page.evaluate((i) => { const s = document.querySelector('[data-cnc-ad="' + i + '"]'); if (s) s.scrollIntoView({ block: 'center' }); }, id);
  await page.waitForTimeout(350);
  return byId(await page.evaluate(bannerState))[id];
}
/* The walk both builder runs make, flag on and flag off, for the layout shift
   comparison and the two per screen scan: consent, a scroll through the File,
   the First File guide opened by a click, another scroll, the gap report tab
   by a click, a scroll. Returns the most banners seen on one screen. */
async function builderWalk(page) {
  await giveConsent(page);
  const load = await page.evaluate(() => window.__cls);
  const a = await scrollScan(page);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.evaluate(() => document.querySelector('#ff-steps > summary').scrollIntoView({ block: 'center' }));
  await page.click('#ff-steps > summary');
  await page.waitForTimeout(300);
  const b = await scrollScan(page);
  await page.evaluate(() => document.getElementById('tab-gaps').scrollIntoView({ block: 'center' }));
  await page.click('#tab-gaps');
  await page.waitForTimeout(300);
  const c = await scrollScan(page);
  await page.evaluate(() => document.getElementById('tab-sections').scrollIntoView({ block: 'center' }));
  await page.click('#tab-sections');
  await page.waitForTimeout(200);
  const all = await cls(page);
  return { load, all: all.cls, shifts: all.shifts, scans: [a, b, c] };
}

async function builderDemo(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => 'builder demonstration at ' + W + ': ' + s;
  const run = await open(browser, origin, vp, { path: '/hsf-builder?demo=1', wait: 700 });
  const { page } = run;
  check(tag('the consent card shows first'), (await visibleState(page)).includes('st-consent'));
  let b = await page.evaluate(bannerState);
  check(tag('no banner while the consent card shows'), b.filter((x) => x.shown).length === 0, b);
  check(tag('html carries cnc-ads-on'), await page.evaluate(() => document.documentElement.classList.contains('cnc-ads-on')));

  const walk = await builderWalk(page);
  o.cls[W] = o.cls[W] || {};
  o.cls[W].builderOn = walk;
  ['sections view', 'sections view with the First File guide open', 'gap report'].forEach((v, i) => {
    check(tag('never more than two banners on one screen while scrolling the ' + v), walk.scans[i].most <= 2, walk.scans[i].where);
  });
  check(tag('the scroll showed banners at all'), walk.scans.some((x) => x.most >= 1), walk.scans);

  let x = await reveal(page, 'AD-05');
  check(tag('AD-05 shows in Sign off readiness'), x && x.shown && /Bee-Matched finds the competent person/.test(x.text), x);
  check(tag('AD-05 is the twin of the Bee-Matched box'), await page.evaluate(() => {
    const s = document.querySelector('[data-cnc-ad="AD-05"]');
    return !!s && s.parentElement.classList.contains('cnc-ad-twin') && !!s.parentElement.querySelector(':scope > .recruit') && !!s.closest('#f-signoff');
  }));
  await shot(page, 'AD-05', 'AD-05-signoff-twin', vp, o);
  x = await reveal(page, 'AD-04');
  if (W >= 768) {
    check(tag('AD-04 shows in the compliance strip'), x && x.shown && /\d+ items are outstanding or expired/.test(x.text), x);
    check(tag('AD-04 sits right after the counts'), await page.evaluate(() => document.getElementById('f-counts').nextElementSibling === document.querySelector('[data-cnc-ad="AD-04"]')));
    await shot(page, 'AD-04', 'AD-04-compliance-strip', vp, o);
  } else {
    check(tag('AD-04 is hidden on a phone'), !x || !x.shown, x);
    await shot(page, 'AD-04', 'AD-04-hidden-on-phone', vp, Object.assign({}, o, { fallback: '#f-counts', above: 200 }));
  }
  x = await reveal(page, 'AD-01');
  check(tag('AD-01 shows at the top of Section F with the gaps wording'), x && x.shown && x.v === 'gaps' && /\d+ inspection records? outstanding/i.test(x.text), x);
  check(tag('AD-01 sits right under the Section F heading'), await page.evaluate(() => document.querySelector('#sec-F .shead').nextElementSibling === document.querySelector('[data-cnc-ad="AD-01"]')));
  const fullPrice = await page.evaluate(() => { const p = document.querySelector('[data-cnc-ad="AD-01"] .cnc-ad-p'); return p ? p.textContent : ''; });
  check(tag('the price reads R299,00 a month, extra company R199,00, VAT to be confirmed'), fullPrice === 'From R299,00 a month. Extra company R199,00 a month. VAT to be confirmed.', fullPrice);
  const font = await page.evaluate(() => { const h = document.querySelector('[data-cnc-ad="AD-01"] .cnc-ad-h'); return h ? getComputedStyle(h).fontFamily : ''; });
  check(tag('the headline is set in Bebas Neue'), /Bebas Neue/.test(font), font);
  await shot(page, 'AD-01', 'AD-01-section-f', vp, o);
  x = await reveal(page, 'AD-07');
  check(tag('AD-07 shows right after the Section F card'), x && x.shown && /This is where Bee-Inspect fills Section F/i.test(x.text)
    && await page.evaluate(() => document.getElementById('sec-F').nextElementSibling === document.querySelector('[data-cnc-ad="AD-07"]')), x);
  await shot(page, 'AD-07', 'AD-07-demonstration', vp, o);
  check(tag('no banner inside the consent card, the consent panel, the upload queue, the deletion panel or setup'),
    await page.evaluate(() => !document.querySelector('#st-consent [data-cnc-ad], #consents [data-cnc-ad], #queue [data-cnc-ad], #del-panel [data-cnc-ad], #st-setup [data-cnc-ad]')));

  /* The guide (opened by the walk): AD-02 in the Section F step. */
  x = await reveal(page, 'AD-02');
  check(tag('AD-02 shows in the guide\'s Section F step, with How it works'), x && x.shown && x.kind === 'tip' && /How it works/.test(x.text)
    && await page.evaluate(() => !!document.querySelector('[data-ff-step="F"]').closest('li').querySelector('[data-cnc-ad="AD-02"]')), x);
  await page.click('[data-cnc-ad="AD-02"] summary');
  await page.waitForTimeout(150);
  check(tag('How it works opens and says the competent person signs'), await page.evaluate(() => { const d = document.querySelector('[data-cnc-ad="AD-02"] details'); return !!d && d.open && /competent person reviews and signs/.test(d.textContent); }));
  await shot(page, 'AD-02', 'AD-02-first-file-guide', vp, o);

  /* The gap report: AD-03 after the Section F gaps. */
  await page.evaluate(() => document.getElementById('tab-gaps').scrollIntoView({ block: 'center' }));
  await page.click('#tab-gaps');
  await page.waitForTimeout(200);
  x = await reveal(page, 'AD-03');
  check(tag('AD-03 shows in the gap report with the Section F count'), x && x.shown && /Close \d+ gaps? in Section F/i.test(x.text) && /Turn gaps into a checklist/.test(x.text), x);
  check(tag('AD-03 follows the Section F gaps, before Section G'), await page.evaluate(() => {
    const s = document.querySelector('[data-cnc-ad="AD-03"]');
    let p = s.previousElementSibling; while (p && p.tagName !== 'H3') p = p.previousElementSibling;
    const n = s.nextElementSibling;
    return !!p && p.dataset.gapSec === 'F' && (!n || n.tagName === 'H3' || n.classList.contains('okbox'));
  }));
  await shot(page, 'AD-03', 'AD-03-gap-report', vp, o);
  await page.click('#tab-sections');
  await page.waitForTimeout(200);

  /* Links, impressions and the event fields. */
  const all = await page.evaluate(bannerState);
  const hrefs = all.flatMap((x) => x.hrefs);
  /* P2 (contract 16): every banner opens /bee-inspect in a new tab with the UTM
     rules (utm_content {ad_id}_{variant}); AD-01 also opens the sample report. */
  const utmOk = (h) => { const u = new URL(h); const id = (u.searchParams.get('utm_content') || '').split('_')[0];
    return u.origin === origin && (u.pathname === '/bee-inspect' || (u.pathname === '/bee-inspect/sample-report' && id === 'AD-01'))
      && u.searchParams.get('utm_source') === 'hsf_builder' && u.searchParams.get('utm_medium') === 'in_product_banner' && u.searchParams.get('utm_campaign') === 'bee_inspect_addon'
      && /^AD-0[1-8]_[a-z0-9_]+$/.test(u.searchParams.get('utm_content') || ''); };
  check(tag('every banner link opens /bee-inspect (AD-01 also the sample report) in a new tab with the UTM rules, and none leads to a Plan page'),
    hrefs.length >= 6 && hrefs.every(([h, t, r]) => utmOk(h) && t === '_blank' && /noopener/.test(r) && !lib.planTarget(h, origin + '/hsf-builder', [origin]))
    && hrefs.some(([h]) => /\/bee-inspect\/sample-report\?/.test(h)), hrefs);
  const imp = run.events.filter((e) => e.body && e.body.event === 'ad_impression').map((e) => e.body.ad_id);
  const expected = ['AD-01', 'AD-02', 'AD-03', 'AD-05', 'AD-07'].concat(W >= 768 ? ['AD-04'] : []);
  check(tag('one impression per banner seen, and none twice'), expected.every((id) => imp.includes(id)) && new Set(imp).size === imp.length && (W >= 768 || !imp.includes('AD-04')), imp);
  check(tag('each event carries only the six fields, page /hsf-builder, industry CONSTR, no cookie'),
    run.events.length > 0 && run.events.every((e) => e.body && Object.keys(e.body).sort().join() === 'ad_id,event,f_band,industry,page,variant'
      && e.body.page === '/hsf-builder' && e.body.industry === 'CONSTR' && /^(na|0|1to2|3to5|6plus)$/.test(e.body.f_band) && !e.headers.cookie), run.events.map((e) => e.body));

  /* Keyboard focus is visible. */
  await page.keyboard.press('Shift');
  const focus = await page.evaluate(() => {
    const out = [];
    for (const sel of ['[data-cnc-ad="AD-01"] [data-go]', '[data-cnc-ad="AD-01"] [data-x]', '[data-cnc-ad="AD-02"] summary', '[data-cnc-ad="AD-05"] [data-go]']) {
      const el = document.querySelector(sel);
      if (!el) { out.push([sel, 'missing']); continue; }
      el.focus();
      const cs = getComputedStyle(el);
      out.push([sel, el.matches(':focus-visible') && cs.outlineStyle === 'solid' && parseFloat(cs.outlineWidth) >= 3, cs.outlineStyle + ' ' + cs.outlineWidth + ' ' + cs.outlineColor]);
    }
    return out;
  });
  check(tag('keyboard focus shows a 3 pixel ring on the banner controls'), focus.every((f) => f[1] === true), focus);
  const labels = await page.evaluate(() => Array.from(document.querySelectorAll('.cnc-ad')).map((b) => [b.tagName, b.getAttribute('aria-label'),
    Array.from(b.querySelectorAll('a,button')).every((c) => (c.getAttribute('aria-label') || c.textContent).trim().length > 2)]));
  check(tag('each banner is a labelled aside with named controls'), labels.every((l) => l[0] === 'ASIDE' && l[1] === 'Bee-Inspect add on' && l[2]), labels);

  /* Subscriber hook. */
  await page.evaluate(() => window.CNCAds.setSubscriber(true));
  await page.waitForTimeout(150);
  b = byId(await page.evaluate(bannerState));
  check(tag('a subscriber sees Open Bee-Inspect'), b['AD-01'] && /Open Bee-Inspect/.test(b['AD-01'].text) && !/R299,00/.test(b['AD-01'].text), b['AD-01']);
  if (W >= 768) await shot(page, 'AD-01', 'AD-01-subscriber-stub', vp, o);
  await page.evaluate(() => window.CNCAds.setSubscriber(false));

  /* Collapse AD-01 and AD-05; dismiss AD-07. */
  await page.evaluate(() => document.querySelector('[data-cnc-ad="AD-01"]').scrollIntoView({ block: 'center' }));
  await page.click('[data-cnc-ad="AD-01"] [data-x]');
  await page.waitForTimeout(200);
  b = byId(await page.evaluate(bannerState));
  const focused = await page.evaluate(() => document.activeElement && document.activeElement.matches('[data-cnc-ad="AD-01"] [data-show]'));
  check(tag('AD-01 folds to a one line strip with Show, and focus moves to Show'), b['AD-01'] && b['AD-01'].shown && b['AD-01'].kind === 'strip' && /Show/.test(b['AD-01'].text) && b['AD-01'].height < 70 && focused, b['AD-01']);
  if (W >= 768) await shot(page, 'AD-01', 'AD-01-collapsed', vp, o);
  await page.click('[data-cnc-ad="AD-05"] [data-x]');
  await page.evaluate(() => document.querySelector('[data-cnc-ad="AD-07"]').scrollIntoView({ block: 'center' }));
  await page.click('[data-cnc-ad="AD-07"] [data-x]');
  await page.waitForTimeout(200);
  const store = await page.evaluate(() => JSON.parse(localStorage.getItem('cnc_bee_ads_v1') || '{}'));
  const now = Date.now();
  check(tag('the choices are kept 14 days: AD-01 and AD-05 collapsed, AD-07 hidden'), store['AD-01'] && store['AD-01'].m === 'c' && store['AD-05'] && store['AD-05'].m === 'c'
    && store['AD-07'] && store['AD-07'].m === 'd' && Math.abs(store['AD-07'].u - (now + 14 * DAY)) < 5 * 60000, store);
  b = byId(await page.evaluate(bannerState));
  check(tag('AD-07 is gone once dismissed'), !b['AD-07'] || !b['AD-07'].shown, b['AD-07']);
  const dis = run.events.filter((e) => e.body && e.body.event === 'ad_dismiss').map((e) => e.body.ad_id).sort();
  check(tag('each dismissal is counted'), dis.join() === 'AD-01,AD-05,AD-07', dis);

  /* Reload: the choices hold. */
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(600);
  await giveConsent(page);
  b = { 'AD-01': await reveal(page, 'AD-01'), 'AD-05': await reveal(page, 'AD-05'), 'AD-07': await reveal(page, 'AD-07') };
  check(tag('after a reload AD-01 and AD-05 are still strips and AD-07 stays hidden'),
    b['AD-01'] && b['AD-01'].kind === 'strip' && b['AD-05'] && b['AD-05'].kind === 'strip' && (!b['AD-07'] || !b['AD-07'].shown), [b['AD-01'], b['AD-05'], b['AD-07']]);
  if (W < 768) await shot(page, 'AD-05', 'AD-05-collapsed', vp, o);
  await page.evaluate(() => document.querySelector('[data-cnc-ad="AD-01"]').scrollIntoView({ block: 'center' }));
  await page.click('[data-cnc-ad="AD-01"] [data-show]');
  await page.waitForTimeout(200);
  b = byId(await page.evaluate(bannerState));
  const back = await page.evaluate(() => ({ store: JSON.parse(localStorage.getItem('cnc_bee_ads_v1') || '{}'), focus: document.activeElement && document.activeElement.matches('[data-cnc-ad="AD-01"] [data-x]') }));
  check(tag('Show brings AD-01 back in full, clears its choice and puts focus on its control'), b['AD-01'] && b['AD-01'].kind === 'full' && !back.store['AD-01'] && back.focus, back);

  /* The File flow still works with the banners on: drop a document into
     Section C, watch the queue, sign off readiness still there. */
  const before = await page.evaluate(() => document.querySelectorAll('#queue li').length);
  await page.setInputFiles('input[data-pick="section"][data-section="C"]', { name: 'Bee test risk assessment (fictitious).pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4\n% fictitious\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n') });
  let flow = null;
  for (let i = 0; i < 40; i++) {
    await page.waitForTimeout(150);
    flow = await page.evaluate(() => {
      const li = Array.from(document.querySelectorAll('#queue li')).find((x) => /Bee test risk assessment/.test(x.textContent));
      return li ? li.textContent.replace(/\s+/g, ' ') : null;
    });
    if (flow && /Uploaded|Held for MyClinicOnline|Security scan/.test(flow)) break;
  }
  check(tag('the File flow still works: a dropped document reaches the upload queue and is uploaded'),
    !!flow && /Uploaded|Held for MyClinicOnline|Security scan/.test(flow) && (await page.evaluate(() => document.querySelectorAll('#queue li').length)) > before, flow);
  check(tag('sign off readiness still shows its Bee-Matched call to action'), await page.evaluate(() => !!document.querySelector('#f-signoff .recruit a[data-cta="recruitment_onboard_hs_practitioner"]')));
  check(tag('no script error on the page'), run.errors.length === 0, run.errors);
  await run.context.close();
}

async function builderFlagOff(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => 'builder demonstration, flag off, at ' + W + ': ' + s;
  const run = await open(browser, origin, vp, { path: '/hsf-builder?demo=1&flags=bee_inspect_ads:0', wait: 700 });
  const { page } = run;
  const walk = await builderWalk(page);
  const b = await page.evaluate(bannerState);
  check(tag('no banner and no slot anywhere'), b.length === 0 && await page.evaluate(() => !document.querySelector('.cnc-ad, .cnc-ad-slot, .cnc-ad-twin')), b);
  check(tag('html does not carry cnc-ads-on'), !await page.evaluate(() => document.documentElement.classList.contains('cnc-ads-on')));
  check(tag('nothing is sent to /api/hsf-events'), run.events.length === 0, run.events);
  check(tag('the File flow still shows sign off readiness with its Bee-Matched call to action'), await page.evaluate(() => !!document.querySelector('#f-signoff > .recruit a[data-cta="recruitment_onboard_hs_practitioner"]')));
  check(tag('no script error on the page'), run.errors.length === 0, run.errors);
  o.cls[W] = o.cls[W] || {};
  o.cls[W].builderOff = walk;
  await run.context.close();
}

async function builderForbidden(browser, origin, vp) {
  const W = vp.width;
  const states = [
    { name: 'signed out', o: { path: '/hsf-builder', session: null, api: API.signedOut, wait: 1200 }, expect: 'st-signin' },
    { name: 'no company account', o: { path: '/hsf-builder', session: USER, api: API.noAccount, wait: 1200 }, expect: 'st-noaccount' },
    { name: 'sign in unreachable', o: { path: '/hsf-builder', supabase: 'fail', wait: 1500 }, expect: 'st-error' },
    { name: 'consent not given, File there', o: { path: '/hsf-builder', session: USER, api: API.live(CONSENT_NONE, true), wait: 1500 }, expect: 'st-consent' },
    { name: 'no File yet (setup)', o: { path: '/hsf-builder', session: USER, api: API.live(CONSENT_DONE, false), wait: 1500 }, expect: 'st-setup' },
    { name: 'loading', o: { path: '/hsf-builder', session: USER, api: API.slowConsent, wait: 800 }, expect: 'st-loading' }
  ];
  for (const s of states) {
    const run = await open(browser, origin, vp, s.o);
    const vis = await visibleState(run.page);
    check('builder ' + s.name + ' at ' + W + ': shows ' + s.expect, vis.includes(s.expect), vis);
    await scrollScan(run.page);
    const b = await run.page.evaluate(bannerState);
    check('builder ' + s.name + ' at ' + W + ': no banner', b.filter((x) => x.shown).length === 0 && run.events.length === 0, { b, events: run.events.length });
    await run.context.close();
  }

  /* Live, signed in, consent given, a File with Section F gaps. */
  const tag = (x) => 'builder live File view at ' + W + ': ' + x;
  const run = await open(browser, origin, vp, { path: '/hsf-builder', session: USER, api: API.live(CONSENT_DONE, true), wait: 1500 });
  const { page } = run;
  const vis = await visibleState(page);
  check(tag('the File view shows, with no consent card'), vis.includes('st-file') && !vis.includes('st-consent'), vis);
  let b = { 'AD-01': await reveal(page, 'AD-01'), 'AD-05': await reveal(page, 'AD-05'), 'AD-04': await reveal(page, 'AD-04') };
  check(tag('AD-01 with the gaps wording for the Section F count (3)'), b['AD-01'] && b['AD-01'].shown && /3 inspection records outstanding/i.test(b['AD-01'].text), b['AD-01']);
  check(tag('AD-05 in sign off readiness'), b['AD-05'] && b['AD-05'].shown, b['AD-05']);
  check(tag(W >= 768 ? 'AD-04 with the open count (17)' : 'AD-04 hidden on a phone'), W >= 768 ? (b['AD-04'] && b['AD-04'].shown && /17 items are outstanding or expired/.test(b['AD-04'].text)) : (!b['AD-04'] || !b['AD-04'].shown), b['AD-04']);
  check(tag('no demonstration banner (AD-07) outside the demonstration'), !(await page.evaluate(() => !!document.querySelector('[data-cnc-ad="AD-07"]'))));
  await page.click('#tab-gaps');
  await page.evaluate(() => document.querySelector('h3[data-gap-sec="F"]').scrollIntoView({ block: 'center' }));
  await page.waitForTimeout(400);
  b = byId(await page.evaluate(bannerState));
  check(tag('AD-03 reads Close 3 gaps in Section F'), b['AD-03'] && b['AD-03'].shown && /Close 3 gaps in Section F/i.test(b['AD-03'].text), b['AD-03']);
  const ev = run.events.filter((e) => e.body && e.body.event === 'ad_impression');
  check(tag('events carry industry MANUF and the Section F band 3to5'), ev.length > 0 && ev.every((e) => e.body.industry === 'MANUF' && e.body.f_band === '3to5'), ev.map((e) => e.body));
  check(tag('no script error on the page'), run.errors.length === 0, run.errors);
  await run.context.close();
}

async function landing(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => 'health-and-safety-file at ' + W + ': ' + s;
  for (const on of [true, false]) {
    const run = await open(browser, origin, vp, { path: '/health-and-safety-file' + (on ? '' : '?flags=bee_inspect_ads:0'), wait: 700 });
    const { page } = run;
    const load = await page.evaluate(() => window.__cls);
    await scrollScan(page);
    const all = await page.evaluate(() => window.__cls);
    await page.evaluate(() => window.scrollTo(0, 0));
    const pos = await page.evaluate(() => {
      const s = document.querySelector('[data-cnc-ad-slot="AD-06"]');
      return { between: !!s && s.previousElementSibling && s.previousElementSibling.id === 'two-ways' && s.nextElementSibling && s.nextElementSibling.id === 'inside',
        inPricing: !!(s && s.closest('#pricing')), h: s ? Math.round(s.getBoundingClientRect().height) : -1 };
    });
    await page.evaluate(() => document.querySelector('[data-cnc-ad-slot="AD-06"]').scrollIntoView({ block: 'center' }));
    await page.waitForTimeout(500);
    const b = byId(await page.evaluate(bannerState));
    if (on) {
      check(tag('AD-06 sits between Two ways and What is in the File, outside the pricing table'), pos.between && !pos.inPricing, pos);
      check(tag('AD-06 shows its headline'), b['AD-06'] && b['AD-06'].shown && /The File is free\. The risk assessment is Bee-Inspect\./i.test(b['AD-06'].text), b['AD-06']);
      check(tag('AD-06 impression counted with page /health-and-safety-file'), run.events.some((e) => e.body.event === 'ad_impression' && e.body.ad_id === 'AD-06' && e.body.page === '/health-and-safety-file'), run.events.map((e) => e.body));
      await shot(page, 'AD-06', 'AD-06-landing', vp, o);
    } else {
      check(tag('flag off: the AD-06 slot takes no room and nothing is drawn or sent'), pos.h === 0 && !b['AD-06'] && run.events.length === 0, { pos, b, events: run.events.length });
    }
    o.cls[W] = o.cls[W] || {};
    o.cls[W]['landing' + (on ? 'On' : 'Off')] = { load, all };
    check(tag('no script error (flag ' + (on ? 'on' : 'off') + ')'), run.errors.length === 0, run.errors);
    await run.context.close();
  }
}

async function portal(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => 'portal at ' + W + ': ' + s;
  const cases = [
    { name: 'demonstration', o: { path: '/portal?demo=1', wait: 1200 }, want: true, shot: true },
    { name: 'signed in with a File', o: { path: '/portal', session: USER, api: API.portal(true), wait: 1500 }, want: true },
    { name: 'signed in without a File', o: { path: '/portal', session: USER, api: API.portal(false), wait: 1500 }, want: false },
    { name: 'signed out', o: { path: '/portal', session: null, api: API.signedOut, wait: 1500 }, want: false }
  ];
  for (const c of cases) {
    const run = await open(browser, origin, vp, c.o);
    const { page } = run;
    await page.evaluate(() => { const f = document.getElementById('c-files'); if (f) f.scrollIntoView({ block: 'center' }); });
    await page.waitForTimeout(500);
    const b = byId(await page.evaluate(bannerState));
    if (c.want) {
      check(tag(c.name + ': AD-08 shows on the Files side, above its buttons'), b['AD-08'] && b['AD-08'].shown && /Your File is built\. Keep it current\./i.test(b['AD-08'].text)
        && await page.evaluate(() => document.getElementById('files-actions').previousElementSibling === document.querySelector('[data-cnc-ad="AD-08"]')), b['AD-08']);
      if (c.shot) await shot(page, 'AD-08', 'AD-08-portal', vp, o);
    } else {
      check(tag(c.name + ': no banner'), !b['AD-08'] && run.events.length === 0, { b, events: run.events.length });
    }
    check(tag(c.name + ': no script error'), run.errors.length === 0, run.errors);
    await run.context.close();
  }
}

/* ------------------------------------------------------------ main */
async function main(opts) {
  const o = Object.assign({ shots: false, log: (l) => console.log(l), list: [], cls: {} }, opts || {});
  results.length = 0;
  const pw = findPlaywright();
  if (!pw) { o.log('bee-inspect-ads: Playwright not found'); return 2; }
  const server = createServer({ quiet: true, root: VERCEL });
  await new Promise((ok, bad) => { server.once('error', bad); server.listen(0, '127.0.0.1', ok); });
  const origin = 'http://127.0.0.1:' + server.address().port;
  const browser = await pw.chromium.launch();
  const started = Date.now();
  try {
    for (const vp of VIEWPORTS) {
      await builderDemo(browser, origin, vp, o);
      await builderFlagOff(browser, origin, vp, o);
      await builderForbidden(browser, origin, vp);
      await landing(browser, origin, vp, o);
      await portal(browser, origin, vp, o);
      const c = o.cls[vp.width];
      const tol = 0.005;
      check('no layout shift from the banners at ' + vp.width + ': builder, loading and consent (on ' + c.builderOn.load.toFixed(4) + ', off ' + c.builderOff.load.toFixed(4) + ')',
        c.builderOn.load <= c.builderOff.load + tol, c.builderOn.shifts);
      check('no layout shift from the banners at ' + vp.width + ': builder, the whole walk through with lazy filling (on ' + c.builderOn.all.toFixed(4) + ', off ' + c.builderOff.all.toFixed(4) + ')',
        c.builderOn.all <= c.builderOff.all + tol, c.builderOn.shifts);
      check('no layout shift from the banners at ' + vp.width + ': health-and-safety-file, loading and scrolling (on ' + c.landingOn.all.toFixed(4) + ', off ' + c.landingOff.all.toFixed(4) + ')',
        c.landingOn.all <= c.landingOff.all + tol && c.landingOn.load <= c.landingOff.load + tol);
    }
  } finally {
    await browser.close();
    await new Promise((ok) => server.close(ok));
  }
  if (o.shots) o.list.sort((a, b) => a.file.localeCompare(b.file)).forEach((x) => o.log('  ' + x.file + '  ' + x.kb + ' KB'));
  const failed = results.filter((r) => !r.ok);
  for (const r of results) if (!r.ok || o.verbose) o.log((r.ok ? 'ok   ' : 'FAIL ') + r.name + (r.ok ? '' : '\n       ' + r.detail.slice(0, 1500)));
  o.log('bee-inspect-ads: ' + (failed.length ? 'FAIL' : 'PASS') + ', ' + (results.length - failed.length) + ' of ' + results.length + ' checks at ' + VIEWPORTS.map((v) => v.width).join(' and ')
    + 'px' + (o.shots ? ', ' + o.list.length + ' screenshots in docs/bee-inspect/p1' : '') + ', ' + ((Date.now() - started) / 1000).toFixed(0) + 's');
  return failed.length ? 1 : 0;
}

if (process.env.NODE_TEST_CONTEXT) {
  const { test } = await import('node:test');
  const missing = chromiumMissing();
  test('the Bee-Inspect P1 banners, in Chromium (contract 16.3)', {
    skip: missing ? missing + ': run node test/browser/bee-inspect-ads.mjs where Chromium is installed' : false,
    timeout: 15 * 60 * 1000
  }, async (t) => {
    const lines = [];
    const code = await main({ log: (l) => lines.push(l) });
    if (lines.length) t.diagnostic(lines[lines.length - 1]);
    if (code !== 0) throw new Error('\n' + lines.join('\n'));
  });
} else {
  const argv = process.argv.slice(2);
  main({ shots: argv.includes('--shots'), verbose: argv.includes('--verbose') }).then((code) => process.exit(code), (e) => {
    console.error('bee-inspect-ads: could not run: ' + (e && e.stack ? e.stack : e));
    process.exit(1);
  });
}
