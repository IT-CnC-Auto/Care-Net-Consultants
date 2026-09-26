#!/usr/bin/env node
/* =====================================================================
   bee-inspect-pages.mjs :: the Bee-Inspect P2 site pages, rendered
   hsf/BUILD-CONTRACT.md 16; hsf/BEE-INSPECT-BUILD-PROMPT.md A3

   Starts server/serve.js on a free local port and drives Chromium at 1280
   and 390 pixels wide through:
     /bee-inspect                 prices from /hsf/ads.js, the FAQ and its
                                  FAQPage schema, the WhatsApp fallback, no
                                  store link or badge, noindex logic
     /bee-inspect/sample-report   eight watermarked pages, each with the locked
                                  footer, the draft label and the Issued
                                  stamp, the voice note index, view only
     /get-app                     coming soon, device detection (desktop,
                                  iPhone, Android), no store link
     /claim/{code}                a well formed code and a hostile one; the
                                  code is never written into the page
     /health-and-safety-file      the industry variants and the pricing
                                  preselection, the flagged menu and footer
                                  items, the campaign tags kept for sign in
     /hsf-builder                 the Inspection reports list in Section F
                                  (demonstration: two Issued reports; live:
                                  empty, under AD-01; flag off: none), the
                                  P2 banner links (/bee-inspect with UTMs and
                                  See a sample report), the tags on the sign
                                  in return address and attribution_seen sent
                                  once after sign in
   On every page at both widths: no console error, no horizontal scroll,
   keyboard focus visible on every tab stop reached, layout shift near 0 while
   loading and scrolling, and no link to a Medical Surveillance Plan page.
   On /bee-inspect, /get-app and /claim (and no drawn bee on the sample
   report): every bee is the official gold bee image, and the faded Africa
   page break of www.carenetconsultants.co.za replaces the pattern strip.

   Run:  node test/browser/bee-inspect-pages.mjs           (checks)
         node test/browser/bee-inspect-pages.mjs --shots   (and writes the
               screenshots to docs/bee-inspect/p2/)
   "node --test" runs the checks as one test and skips it only when
   Playwright or its Chromium is missing. Every address off the local server
   is refused or answered by a stand in (the image host gets drawn stand ins
   of the declared size): nothing reaches Supabase, Vercel or a live service.
   ===================================================================== */

import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..', '..');
const VERCEL = path.join(ROOT, 'vercel');
const SHOT_DIR = path.join(ROOT, 'docs', 'bee-inspect', 'p2');
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
const UA = {
  iphone: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
  android: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36'
};
const FOOTER_TEXT = 'This report is powered by Care Net Consultants Development House (Pty) Ltd';

/* ------------------------------------------------------------ stand ins */
/* The Care Net logo, cut from the letterhead the repository already holds
   (hsf/examples/letterhead), so screenshots look like the site. Only served
   inside this test, never published. */
let LOGO_SVG = null;
function logoSvg() {
  if (LOGO_SVG) return LOGO_SVG;
  let png = '';
  try { png = fs.readFileSync(path.join(ROOT, 'hsf', 'examples', 'letterhead', 'header_cropped.png')).toString('base64'); } catch (_) { png = ''; }
  LOGO_SVG = png
    ? '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="445" height="160" viewBox="1600 75 470 170"><clipPath id="c"><rect x="1688" y="75" width="300" height="170"/></clipPath><image clip-path="url(#c)" width="2000" height="304" xlink:href="data:image/png;base64,' + png + '"/></svg>'
    : '<svg xmlns="http://www.w3.org/2000/svg" width="445" height="160"><rect width="445" height="160" fill="#fff"/><text x="20" y="95" font-family="Arial" font-size="48" font-weight="700" fill="#ED1B24">CARE NET</text></svg>';
  return LOGO_SVG;
}
/* Stand ins for the two files the Director named (25/09/2026), at their real
   shape: the faded Africa page break (2000 x 100) and the square gold bee.
   Both say "stand in" so no screenshot passes for the real artwork. */
const FADED_STAND_IN = '<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="100" viewBox="0 0 2000 100"><rect width="2000" height="100" fill="#fff"/>'
  + '<path d="' + Array.from({ length: 50 }, (_, i) => 'M' + (i * 40) + ' 70l20-40 20 40').join('') + '" stroke="#e7b8ba" stroke-width="6" fill="none"/>'
  + '<text x="1000" y="62" font-family="Arial" font-size="26" fill="#9a9a9a" text-anchor="middle">stand in: CNC Website Page break Africa Pattern faded 2000 x 100</text></svg>';
const BEE_STAND_IN = '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><circle cx="128" cy="128" r="120" fill="#F0A32B"/>'
  + '<text x="128" y="146" font-family="Arial" font-size="56" font-weight="700" fill="#0F0F0F" text-anchor="middle">BEE</text>'
  + '<text x="128" y="190" font-family="Arial" font-size="26" fill="#0F0F0F" text-anchor="middle">stand in</text></svg>';
const BEE_SRC = 'https://img.carenetcdn.com/medical-surveillance/New-Site_Bee_Icon_Gold.webp';
const FADED_SRC = 'https://pub-05e130c201dd463a8accbcd12eb02d77.r2.dev/wp-content/uploads/2025/05/CNC-Website-Page-break-Africa-Pattern-faded-2000x100px-1.1.webp';

/* The Director's brand fixes (25/09/2026): every bee is the official gold bee
   image (square, loaded, never a drawing) and, where asked, the pattern is
   the faded page break of www.carenetconsultants.co.za at the content width,
   its 20:1 shape kept (no stretching), never the old pattern strip. */
async function brandArt(run, tag, o) {
  const d = await run.page.evaluate(() => {
    const box = (el) => { const r = el.getBoundingClientRect(); return { w: r.width, h: r.height }; };
    const drawn = Array.from(document.querySelectorAll('svg')).filter((s) => /rotate\(-?28/.test(s.innerHTML) || s.matches('.bee-mark, .cnc-ad-bee')).length;
    const bees = Array.from(document.querySelectorAll('img[src*="Bee_Icon"]')).map((i) => Object.assign({ src: i.getAttribute('src'), nw: i.naturalWidth, alt: i.getAttribute('alt'), aw: i.getAttribute('width'), ah: i.getAttribute('height') }, box(i)));
    const div = Array.from(document.querySelectorAll('img.divider')).map((i) => {
      const cs = getComputedStyle(i.parentElement);
      return Object.assign({ src: i.getAttribute('src'), nw: i.naturalWidth, aw: i.getAttribute('width'), ah: i.getAttribute('height'), alt: i.getAttribute('alt'), hidden: i.getAttribute('aria-hidden'),
        cw: i.parentElement.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) }, box(i));
    });
    return { drawn, bees, div, strips: document.querySelectorAll('.pattern-strip').length };
  });
  check(tag('no hand drawn bee'), d.drawn === 0, d.drawn);
  if (o && o.bee) check(tag('the bee is the official gold bee image, loaded, square, sized by width and height'), d.bees.length >= o.bee
    && d.bees.every((b) => b.src === BEE_SRC && b.nw > 0 && b.alt === '' && b.aw === b.ah && Math.abs(b.w - b.h) < 0.6 && b.w > 0), d.bees);
  if (o && o.divider) {
    check(tag('the faded Africa page break replaces the pattern strip'), d.strips === 0 && d.div.length === 1, d);
    const v = d.div[0] || {};
    check(tag('the page break is the site file at the content width, 20:1 kept (' + (v.w || 0).toFixed(0) + ' x ' + (v.h || 0).toFixed(1) + ')'),
      v.src === FADED_SRC && v.nw > 0 && v.aw === '2000' && v.ah === '100' && v.alt === '' && v.hidden === 'true' && Math.abs(v.w - v.cw) < 1 && Math.abs(v.h - v.w / 20) < 1, v);
  }
}

function standIn(u) {
  const p = u.pathname;
  if (/Care_Net_Logo/i.test(p)) return logoSvg();
  if (/pattern-strip/i.test(p)) return '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="48"><rect width="96" height="48" fill="#fff"/><path d="M0 24l12-12 12 12 12-12 12 12 12-12 12 12 12-12 12 12" stroke="#ED1B24" stroke-width="3" fill="none"/><path d="M0 40h96" stroke="#F0A32B" stroke-width="4"/></svg>';
  if (/Page-break-Africa-Pattern-faded/i.test(p)) return FADED_STAND_IN;
  if (/Bee_Icon/i.test(p)) return BEE_STAND_IN;
  return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" rx="8" fill="#e9e6e6"/></svg>';
}

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
      async signInWithOtp(args) { (globalThis.__OTP = globalThis.__OTP || []).push(JSON.parse(JSON.stringify(args || {}))); return { data: {}, error: null }; },
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
const GATE = { uploads_open: true, client_verified: true, verification_requested: false, deletion_sms_available: false, consent_complete: true };
const FILE_ROW = { file_id: 'bee-file-1', reference: 'CNC-HSF-2026-0925-001', industry_code: 'MANU', industry_name: 'Manufacturing', status: 'draft', revision: 1, compliance_pct: 25, created_at: '2026-09-25T08:00:00Z' };
function detail() {
  const item = (sec, n, status, name) => ({ item_id: 'bee-' + sec + n, element_code: 'HSF-' + sec + '-0' + n, name, duty: 'A fictitious duty for the test.', evidence_type: 'register',
    review_interval: 'annual', status, reason: null, due_date: null, citable: [], awaiting: [], uploads: [] });
  const secs = 'ABCDEFGHIJKLMNO'.split('').map((c) => ({ code: c, name: '', compliance_pct: 50, items: [item(c, 1, 'uploaded', 'Uploaded record ' + c), item(c, 2, 'outstanding', 'Outstanding record ' + c)] }));
  return { file: { id: 'bee-file-1', reference: FILE_ROW.reference, industry_code: 'MANU', industry_name: 'Manufacturing', company_name: COMPANY, status: 'draft', revision: 1, regime: 'OHSA' },
    sections: secs, overall: { pct: 50, counts: { uploaded: 15, linked_mco: 0, outstanding: 15, expired: 0, not_applicable: 0 } } };
}
const json = (status, body) => ({ status, body });
const API = {
  none: () => json(404, { error: 'Not available in the test.' }),
  signedOut: () => json(401, { error: 'Please sign in first.' }),
  live: (m, p, q) => {
    if (p === '/api/hsf-consent') return json(200, CONSENT_DONE);
    if (p === '/api/hsf-upload' && q.get('gate')) return json(200, GATE);
    if (p === '/api/hsf-upload') return json(200, []);
    if (p === '/api/hsf-file' && q.get('file_id')) return json(200, detail());
    if (p === '/api/hsf-file') return json(200, [FILE_ROW]);
    return json(404, {});
  }
};

/* ------------------------------------------------------------ in the page */
function initPage(arg) {
  if (window.top !== window) return;
  window.__BEE_SESSION = arg.session;
  try { localStorage.setItem('cnc_consent_v1', JSON.stringify({ analytics: false, marketing: false, savedAt: Date.now() })); } catch (e) { /* none */ }
  window.__cls = 0;
  window.__shifts = [];
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

/* ------------------------------------------------------------ harness */
const results = [];
function check(name, cond, detail) {
  results.push({ name, ok: !!cond, detail: cond ? '' : (detail === undefined ? '' : (typeof detail === 'string' ? detail : JSON.stringify(detail))) });
}

async function open(browser, origin, vp, o) {
  const opts = o || {};
  const context = await browser.newContext({ viewport: vp, serviceWorkers: 'block', reducedMotion: 'reduce', userAgent: opts.ua || undefined,
    isMobile: !!opts.mobile, hasTouch: !!opts.mobile });
  await context.addInitScript(initPage, { session: opts.session === undefined ? null : opts.session });
  const page = await context.newPage();
  const run = { page, context, events: [], errors: [], consoleErrors: [], external: [] };
  page.on('pageerror', (e) => run.errors.push(String(e && e.message ? e.message : e).slice(0, 200)));
  page.on('console', (m) => { if (m.type() === 'error') run.consoleErrors.push(m.text().slice(0, 200)); });
  const api = opts.api || API.none;
  await context.route('**/*', async (route) => {
    const req = route.request();
    let u;
    try { u = new URL(req.url()); } catch (_) { return route.abort().catch(() => {}); }
    if (u.origin === origin) {
      if (u.pathname === '/api/hsf-events') {
        let b = null;
        try { b = JSON.parse(req.postData() || 'null'); } catch (_) { b = 'unparsable'; }
        run.events.push({ body: b, credentials: req.headers().cookie ? 'cookie' : 'none' });
        return route.fulfill({ status: 202, contentType: 'application/json', body: '{"accepted":false}' }).catch(() => {});
      }
      /* Vercel proxies /icon-src/ (a vercel.json rewrite) to the image host;
         the local server does not, so the stand in answers here. */
      if (u.pathname.startsWith('/icon-src/')) return route.fulfill({ status: 200, contentType: 'image/svg+xml', body: standIn(u) }).catch(() => {});
      if (u.pathname.startsWith('/api/')) {
        const r = api(req.method(), u.pathname, u.searchParams);
        return route.fulfill({ status: r.status, contentType: 'application/json', body: JSON.stringify(r.body) }).catch(() => {});
      }
      return route.continue().catch(() => {});
    }
    const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET, POST, OPTIONS' };
    if (/supabase-js/i.test(u.pathname) || (u.hostname === 'esm.sh' && /supabase/i.test(u.pathname))) {
      return route.fulfill({ status: 200, headers: Object.assign({ 'content-type': 'application/javascript; charset=utf-8' }, cors), body: FAKE_SUPABASE_JS }).catch(() => {});
    }
    if (/\.supabase\.co$/i.test(u.hostname)) {
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors, body: '' }).catch(() => {});
      return route.fulfill({ status: 200, headers: Object.assign({ 'content-type': 'application/json' }, cors), body: u.pathname.startsWith('/rest/') ? '[]' : '{}' }).catch(() => {});
    }
    if (u.hostname === 'img.carenetcdn.com' || /\.r2\.dev$/.test(u.hostname)) {
      return route.fulfill({ status: 200, headers: Object.assign({ 'content-type': 'image/svg+xml' }, cors), body: standIn(u) }).catch(() => {});
    }
    run.external.push(u.href.slice(0, 120));
    return route.abort('blockedbyclient').catch(() => {});
  });
  if (opts.path) {
    await page.goto(origin + opts.path, { waitUntil: 'load', timeout: 60000 });
    await page.waitForTimeout(opts.wait || 600);
  }
  return run;
}

/* The common checks every page gets at every width. */
async function common(run, origin, tag, o) {
  const { page } = run;
  const opts = o || {};
  const wide = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, w: window.innerWidth }));
  check(tag('no horizontal scroll (' + wide.sw + ' in ' + wide.w + ')'), wide.sw <= wide.w, wide);
  const H = await page.evaluate(() => document.documentElement.scrollHeight);
  for (let y = 0; y < H; y += 500) { await page.evaluate((yy) => window.scrollTo(0, yy), y); await page.waitForTimeout(25); }
  await page.waitForTimeout(250);
  const c = await page.evaluate(() => ({ cls: window.__cls, shifts: window.__shifts }));
  if (opts.clsBase !== undefined) {
    check(tag('no added layout shift against the flag off page (' + c.cls.toFixed(4) + ' against ' + opts.clsBase.toFixed(4) + ')'), c.cls <= opts.clsBase + 0.005, c.shifts);
  } else {
    check(tag('layout shift near 0 while loading and scrolling (' + c.cls.toFixed(4) + ')'), c.cls < 0.02, c.shifts);
  }
  const hrefs = await page.evaluate(() => Array.from(document.querySelectorAll('a[href], area[href], form[action]')).map((a) => a.getAttribute('href') || a.getAttribute('action')));
  const plan = hrefs.filter((h) => lib.planTarget(h, page.url(), [origin]));
  check(tag('no link to a Medical Surveillance Plan page (' + hrefs.length + ' links)'), plan.length === 0 && hrefs.length > 0, plan);
  const store = hrefs.filter((h) => /apps\.apple\.com|play\.google\.com|itunes\.apple\.com/i.test(String(h)));
  check(tag('no store link while the apps are not released'), store.length === 0, store);
  /* Keyboard: every tab stop reached shows a focus indicator. */
  await page.evaluate(() => { window.scrollTo(0, 0); if (document.activeElement) document.activeElement.blur(); });
  const bad = [];
  let stops = 0;
  const N = opts.tabs || 24;
  for (let i = 0; i < N; i++) {
    await page.keyboard.press('Tab');
    const r = await page.evaluate(() => {
      const el = document.activeElement;
      if (!el || el === document.body) return null;
      const cs = getComputedStyle(el);
      const outline = cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0;
      const shadow = cs.boxShadow && cs.boxShadow !== 'none';
      const r = el.getBoundingClientRect();
      return { tag: el.tagName, text: (el.getAttribute('aria-label') || el.textContent || '').trim().slice(0, 40), vis: outline || shadow, shown: r.width > 0 && r.height > 0 };
    });
    if (!r) continue;
    stops++;
    if (r.shown && !r.vis) bad.push(r);
  }
  check(tag('keyboard focus is visible on every tab stop (' + stops + ' stops)'), stops > 3 && bad.length === 0, bad);
  check(tag('no console error'), run.consoleErrors.length === 0, run.consoleErrors);
  check(tag('no script error'), run.errors.length === 0, run.errors);
  check(tag('nothing was asked of an outside address'), run.external.length === 0, run.external);
}

async function shot(page, name, vp, o, where) {
  if (!o.shots) return;
  fs.mkdirSync(SHOT_DIR, { recursive: true });
  await page.addStyleTag({ content: '.cnc-secnav{display:none!important}' }).catch(() => {});
  let clip = null;
  if (where && where.sel) {
    await page.evaluate((s) => { const e = document.querySelector(s); if (e) e.scrollIntoView({ block: 'start' }); window.scrollBy(0, -(window.__shotAbove || 110)); }, where.sel);
    await page.waitForTimeout(300);
    const bb = await page.evaluate((s) => { const e = document.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return { y: r.top, h: r.height }; }, where.sel);
    if (!bb) { check('screenshot ' + name + ': ' + where.sel + ' is there', false); return; }
    const y = Math.max(0, bb.y - 20);
    clip = { x: 0, y, width: vp.width, height: Math.max(200, Math.min(vp.height - y, bb.h + 40, where.max || 2000)) };
  } else {
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(250);
  }
  const base = path.join(SHOT_DIR, name + '-' + vp.width);
  let file = base + '.png';
  await page.screenshot(clip ? { path: file, clip } : { path: file });
  let kb = fs.statSync(file).size / 1024;
  if (kb >= 300) {
    fs.unlinkSync(file);
    file = base + '.jpg';
    await page.screenshot(clip ? { path: file, clip, type: 'jpeg', quality: 72 } : { path: file, type: 'jpeg', quality: 72 });
    kb = fs.statSync(file).size / 1024;
  }
  check('screenshot ' + path.basename(file) + ' is under 300 KB (' + kb.toFixed(0) + ' KB)', kb < 300);
  o.list.push({ file: path.basename(file), kb: Math.round(kb) });
}

/* ------------------------------------------------------------ scenarios */
async function productPage(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => '/bee-inspect at ' + W + ': ' + s;
  const run = await open(browser, origin, vp, { path: '/bee-inspect' });
  const { page } = run;
  const d = await page.evaluate(() => {
    const t = (s) => { const e = document.querySelector(s); return e ? e.textContent.replace(/\s+/g, ' ').trim() : ''; };
    const ld = document.getElementById('faq-ld');
    let parsed = null; try { parsed = JSON.parse(ld.textContent); } catch (e) { parsed = null; }
    return {
      robots: !!document.querySelector('meta[name="robots"]'),
      hero: t('.cnc-hero .price-line'), plans: t('#bi-plans'), topups: Array.from(document.querySelectorAll('#bi-topups tr')).map((r) => Array.from(r.cells).map((c) => c.textContent.replace(/\s+/g, ' ').trim()).join(' ')),
      wallet: t('#bi-wallet-points'), storage: t('#bi-storage-points'),
      faqVisible: Array.from(document.querySelectorAll('#faq details')).map((x) => [x.querySelector('summary').textContent.trim(), x.querySelector('div').textContent.replace(/\s+/g, ' ').trim()]),
      faqLd: parsed, wa: Array.from(document.querySelectorAll('a[href^="https://wa.me/"]')).map((a) => a.href),
      logo: (document.querySelector('a.logo-link') || {}).getAttribute ? document.querySelector('a.logo-link').getAttribute('href') : null,
      badges: document.querySelectorAll('img[src*="badge" i], img[alt*="App Store" i], img[alt*="Google Play" i]').length,
      stores: t('.stores'), active: t('.cnc-mainnav li.active'), body: document.body.innerText
    };
  });
  check(tag('indexable here: the flag is on for this host, so the robots tag is gone'), !d.robots);
  check(tag('the hero price line comes from ads.js'), d.hero === 'From R299,00 a month. Extra company R199,00 a month. VAT to be confirmed.', d.hero);
  check(tag('both plans, in house rand format, with VAT to be confirmed'), /R299,00 a month/.test(d.plans) && /R199,00 a month/.test(d.plans) && /VAT to be confirmed/.test(d.plans)
    && /R150,00/.test(d.plans) && /R100,00/.test(d.plans) && /10 GB/.test(d.plans) && /Unlimited inspections and template reports/.test(d.plans), d.plans);
  check(tag('the four top ups with their value'), d.topups.length === 4 && /^R99,00 R99,00 Same value$/.test(d.topups[0]) && /^R249,00 R260,00 R11,00 more$/.test(d.topups[1])
    && /^R499,00 R550,00 R51,00 more$/.test(d.topups[2]) && /^R999,00 R1 150,00 R151,00 more$/.test(d.topups[3]), d.topups);
  check(tag('the AI Wallet is explained in rand, never tokens'), /holds rand, never tokens/.test(d.wallet) && /R20,00/.test(d.wallet) && !/\btokens? (?:cost|price)/i.test(d.body), d.wallet);
  check(tag('storage: 10 GB, warned at 80% and 95%'), /10 GB/.test(d.storage) && /80% and 95%/.test(d.storage), d.storage);
  const ld = d.faqLd;
  const same = ld && ld['@type'] === 'FAQPage' && Array.isArray(ld.mainEntity) && ld.mainEntity.length === d.faqVisible.length
    && ld.mainEntity.every((q, i) => q['@type'] === 'Question' && q.acceptedAnswer && q.acceptedAnswer['@type'] === 'Answer'
      && q.name === d.faqVisible[i][0] && q.acceptedAnswer.text === d.faqVisible[i][1]);
  check(tag('the FAQPage schema parses and says exactly what the visible FAQ says'), same, { ld: ld && ld.mainEntity && ld.mainEntity.length, visible: d.faqVisible.length });
  check(tag('the WhatsApp fallback carries a prefilled Bee-Inspect message and no UTM'), d.wa.length >= 2 && d.wa.every((h) => /^https:\/\/wa\.me\/27600702723\?text=/.test(h) && !/utm_/.test(h) && /Bee-Inspect/.test(decodeURIComponent(h))), d.wa);
  check(tag('the logo goes to /health-and-safety-file'), d.logo === '/health-and-safety-file', d.logo);
  check(tag('store badges are text only: coming soon, no badge image'), d.badges === 0 && /App Store: coming soon/.test(d.stores) && /Google Play: coming soon/.test(d.stores), d.stores);
  check(tag('the page says the File stays free, AI assists, a competent person signs, and no medical results'),
    /The File stays free/i.test(d.body) && /AI assists/.test(d.body) && /Nothing is Issued without the competent person/.test(d.body) && /no clinical medical results/.test(d.body) && /MyClinicOnline/.test(d.body));
  check(tag('Bee-Inspect is the active menu item'), /Bee.Inspect/i.test(d.active), d.active);
  await shot(page, 'bee-inspect-top', vp, o);
  await shot(page, 'bee-inspect-pricing', vp, o, { sel: '#pricing', max: 1500 });
  await shot(page, 'bee-inspect-faq', vp, o, { sel: '#app', max: 1500 });
  await common(run, origin, tag);
  await brandArt(run, tag, { bee: 2, divider: true });
  await run.context.close();

  const off = await open(browser, origin, vp, { path: '/bee-inspect?flags=bee_inspect_ads:0' });
  check(tag('with the flag off the page carries noindex'), await off.page.evaluate(() => { const m = document.querySelector('meta[name="robots"]'); return !!m && /noindex/.test(m.content); }));
  await off.context.close();
}

async function sampleReport(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => '/bee-inspect/sample-report at ' + W + ': ' + s;
  const run = await open(browser, origin, vp, { path: '/bee-inspect/sample-report' });
  const { page } = run;
  const d = await page.evaluate((FT) => {
    const pages = Array.from(document.querySelectorAll('article.rp'));
    const txt = document.body.innerText;
    return {
      n: pages.length,
      footers: pages.map((p) => { const f = p.querySelector(':scope > footer.rfoot'); return !!f && !!f.querySelector('img[alt="Care Net Consultants"]') && f.textContent.includes(FT) && p.lastElementChild === f; }),
      watermark: pages.every((p) => /SAMPLE/.test(decodeURIComponent(getComputedStyle(p).backgroundImage))),
      select: getComputedStyle(document.body).userSelect,
      draft: txt.includes('Assistive draft. Competent person sign off required.'),
      issued: !!document.querySelector('svg.stamp[aria-label*="Issued"]'),
      vn: ['VN-01', 'VN-02', 'VN-03', 'VN-04', 'VN-05', 'VN-06'].every((v) => txt.includes(v)), accounted: txt.includes('Voice notes: 6 accounted for, 0 missing.'),
      results: ['Pass', 'Fail', 'N/A', 'Observe'].every((r) => document.querySelector('.res') && Array.from(document.querySelectorAll('.res')).some((e) => e.textContent === r)),
      heat: document.querySelectorAll('table.heat').length, heatCells: Array.from(document.querySelectorAll('table.heat')).map((t) => Array.from(t.querySelectorAll('td')).reduce((a, td) => a + (Number(td.textContent) || 0), 0)),
      photos: document.querySelectorAll('svg.photo').length, fictitious: /fictitious/i.test(txt), clogo: !!document.querySelector('svg.clogo'),
      law: Array.from(document.querySelectorAll('.law a')).map((a) => a.getAttribute('href')),
      numbers: (txt.match(/\b(?:section|regulation|reg\.?|s\.)\s*\d+(?:\(\d+\))*/gi) || []).filter((m) => !/16\(1\)|16\(2\)|37\(2\)/.test(m)),
      medical: /\b(?:audiogram|spirometry|blood pressure|diagnos(?:is|ed)|lung function|x\s?ray)\b/i.test(txt)
    };
  }, FOOTER_TEXT);
  check(tag('eight report pages'), d.n === 8, d.n);
  check(tag('every page ends with the locked footer: the Care Net logo and the powered by line'), d.footers.length === 8 && d.footers.every(Boolean), d.footers);
  check(tag('every page carries the SAMPLE watermark'), d.watermark);
  check(tag('view only: no text selection'), d.select === 'none', d.select);
  const menu = await page.evaluate(() => { let prevented = false; const ev = new MouseEvent('contextmenu', { bubbles: true, cancelable: true }); document.body.dispatchEvent(ev); prevented = ev.defaultPrevented; return prevented; });
  check(tag('view only: the context menu is off'), menu);
  check(tag('the draft label and the Issued stamp are there'), d.draft && d.issued);
  check(tag('the voice note index VN-01 to VN-06, all accounted for'), d.vn && d.accounted);
  check(tag('findings use Pass, Fail, N/A and Observe, with drawn photo placeholders'), d.results && d.photos >= 6, d);
  check(tag('the heat maps, inherent and residual, each hold the eight risks'), d.heat === 2 && d.heatCells.every((n) => n === 8), d.heatCells);
  check(tag('the company is marked fictitious and the client logo is a placeholder'), d.fictitious && d.clogo);
  check(tag('the law links to /legislation, with no section or regulation numbers other than 16(2)'), d.law.length >= 3 && d.law.every((h) => /^\/legislation#[a-z0-9-]+$/.test(h)) && d.numbers.length === 0, d);
  check(tag('health and safety only: no clinical medical results'), !d.medical);
  await shot(page, 'sample-report-cover', vp, o);
  await shot(page, 'sample-report-heat-map', vp, o, { sel: 'article.rp:nth-of-type(2)', max: 1600 });
  await shot(page, 'sample-report-findings', vp, o, { sel: 'article.rp:nth-of-type(4)', max: 1400 });
  await shot(page, 'sample-report-sign-off', vp, o, { sel: 'article.rp:nth-of-type(8) .hist', max: 1100 });
  await common(run, origin, tag);
  await brandArt(run, tag, {});
  await run.context.close();
}

async function getApp(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => '/get-app at ' + W + ': ' + s;
  const run = await open(browser, origin, vp, W < 768 ? { path: '/get-app', ua: UA.iphone, mobile: true } : { path: '/get-app' });
  const { page } = run;
  const d = await page.evaluate(() => ({ status: document.getElementById('ga-status').textContent, device: document.getElementById('ga-device').textContent,
    wa: Array.from(document.querySelectorAll('a[href^="https://wa.me/"]')).map((a) => decodeURIComponent(a.href)), back: !!document.querySelector('a[href="/bee-inspect"]'), url: location.pathname,
    robots: !!document.querySelector('meta[name="robots"]') }));
  check(tag('says the app is coming to the App Store and Google Play'), d.status === 'The Bee-Inspect app is coming to the App Store and Google Play.', d.status);
  check(tag(W < 768 ? 'an iPhone is recognised' : 'a computer is recognised'), W < 768 ? /iPhone or iPad/.test(d.device) : /on a computer/.test(d.device), d.device);
  check(tag('stays on the page (no store address yet)'), d.url === '/get-app', d.url);
  check(tag('Tell me when it is ready opens WhatsApp with a prefilled message, and a link goes back to /bee-inspect'), d.wa.some((h) => /when the Bee-Inspect app is in the App Store and Google Play/.test(h)) && d.back, d.wa);
  await shot(page, 'get-app', vp, o);
  await common(run, origin, tag);
  await brandArt(run, tag, { bee: 1, divider: true });
  await run.context.close();
  if (W < 768) {
    const a = await open(browser, origin, vp, { path: '/get-app', ua: UA.android, mobile: true });
    check(tag('an Android phone is recognised'), /Android phone/.test(await a.page.evaluate(() => document.getElementById('ga-device').textContent)));
    await a.context.close();
  }
}

async function claim(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => '/claim at ' + W + ': ' + s;
  let run = await open(browser, origin, vp, { path: '/claim/K7PQ2MX9' });
  let d = await run.page.evaluate(() => ({ valid: !document.getElementById('cl-valid').hidden, invalid: !document.getElementById('cl-invalid').hidden, html: document.documentElement.outerHTML, text: document.body.innerText }));
  check(tag('a well formed code: the app is not released yet'), d.valid && !d.invalid && /not released yet/.test(d.text));
  check(tag('the code is never written into the page'), !d.html.includes('K7PQ2MX9') && !d.text.includes('K7PQ2MX9'));
  await shot(run.page, 'claim-code', vp, o);
  await common(run, origin, tag, { tabs: 12 });
  await brandArt(run, tag, { divider: true });
  await run.context.close();
  const hostile = '/claim/%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E';
  run = await open(browser, origin, vp, { path: hostile });
  d = await run.page.evaluate(() => ({ valid: !document.getElementById('cl-valid').hidden, invalid: !document.getElementById('cl-invalid').hidden, imgs: document.querySelectorAll('main img').length, html: document.querySelector('main').innerHTML }));
  check(tag('a hostile code is refused and never echoed'), !d.valid && d.invalid && d.imgs === 0 && !/onerror|alert\(/.test(d.html), d);
  check(tag('a hostile code causes no script error'), run.errors.length === 0, run.errors);
  await run.context.close();
}

async function landing(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => '/health-and-safety-file at ' + W + ': ' + s;
  /* The landing's own shift, flag off, is the yardstick for the variant (the
     hero has a small font swap shift of its own at 390, from before P2). */
  const base = await open(browser, origin, vp, { path: '/health-and-safety-file?flags=bee_inspect_ads:0', wait: 300 });
  const H0 = await base.page.evaluate(() => document.documentElement.scrollHeight);
  for (let y = 0; y < H0; y += 500) { await base.page.evaluate((yy) => window.scrollTo(0, yy), y); await base.page.waitForTimeout(25); }
  await base.page.waitForTimeout(250);
  const clsBase = await base.page.evaluate(() => window.__cls);
  await base.context.close();
  const want = { construction: 'CONSTR', manufacturing: 'MANU', agriculture: 'AGRI', food: 'HOSP', logistics: 'TRANS', cleaning: 'CLEAN', security: 'SEC' };
  for (const [slug, code] of Object.entries(want)) {
    const run = await open(browser, origin, vp, { path: '/health-and-safety-file?industry=' + slug, wait: 300 });
    const d = await run.page.evaluate(() => ({ line: document.getElementById('hero-line').textContent, eb: document.getElementById('hero-eyebrow').textContent, sel: document.getElementById('ind').value, formula: !document.getElementById('formula').hidden }));
    check(tag('?industry=' + slug + ' adjusts the hero and preselects ' + code), d.sel === code && d.formula && d.line !== 'Your Health and Safety File, free to build.' && /Health and Safety File for /.test(d.eb), d);
    if (slug === 'food') {
      await shot(run.page, 'hsf-industry-food', vp, o);
      await common(run, origin, tag, { tabs: 14, clsBase });
    }
    check(tag('?industry=' + slug + ': no script error'), run.errors.length === 0, run.errors);
    await run.context.close();
  }
  for (const q of ['?industry=mining%3Cb%3E', '?industry=', '?industry=__proto__', '?industry=food&flags=bee_inspect_ads:0']) {
    const run = await open(browser, origin, vp, { path: '/health-and-safety-file' + q, wait: 300 });
    const d = await run.page.evaluate(() => ({ line: document.getElementById('hero-line').textContent, sel: document.getElementById('ind').value }));
    check(tag(q + ' is ignored safely'), d.line === 'Your Health and Safety File, free to build.' && d.sel === '' && run.errors.length === 0, d);
    await run.context.close();
  }
  /* The menu and footer items follow the flag. */
  for (const on of [true, false]) {
    const run = await open(browser, origin, vp, { path: '/health-and-safety-file' + (on ? '' : '?flags=bee_inspect_ads:0'), wait: 300 });
    const d = await run.page.evaluate(() => Array.from(document.querySelectorAll('[data-flag="bee_inspect_ads"]')).map((e) => getComputedStyle(e).display));
    check(tag('the Bee-Inspect menu and footer items are ' + (on ? 'shown' : 'hidden') + ' with the flag ' + (on ? 'on' : 'off')), d.length === 3 && d.every((x) => (on ? x !== 'none' : x === 'none')), d);
    await run.context.close();
  }
  /* The campaign tags of the landing address are kept for the sign in. */
  const q = '?utm_source=hsf_builder&utm_medium=in_product_banner&utm_campaign=bee_inspect_addon&utm_content=AD-06_base&utm_term=someone%40example.co.za';
  const run = await open(browser, origin, vp, { path: '/health-and-safety-file' + q, wait: 300 });
  const kept = await run.page.evaluate(() => { try { return JSON.parse(sessionStorage.getItem('cnc_utm_v1')); } catch (e) { return null; } });
  check(tag('the landing keeps the campaign tags in sessionStorage, and drops a tag that is an email address'),
    kept && kept.utm_source === 'hsf_builder' && kept.utm_content === 'AD-06_base' && !('utm_term' in kept), kept);
  await run.context.close();
}

async function builder(browser, origin, vp, o) {
  const W = vp.width;
  const tag = (s) => '/hsf-builder at ' + W + ': ' + s;
  /* Demonstration: two Issued reports, each opening the sample report. */
  let run = await open(browser, origin, vp, { path: '/hsf-builder?demo=1', wait: 800 });
  let { page } = run;
  await page.check('#c-storage'); await page.check('#c-transfer'); await page.check('#c-authority');
  await page.click('#consent-btn');
  await page.waitForTimeout(500);
  await page.evaluate(() => document.getElementById('sec-F').scrollIntoView({ block: 'start' }));
  await page.waitForTimeout(500);
  let d = await page.evaluate(() => {
    const box = document.getElementById('insp-F');
    return { box: !!box, rows: box ? Array.from(box.querySelectorAll('tbody tr')).map((r) => r.textContent.replace(/\s+/g, ' ').trim()) : [],
      links: box ? Array.from(box.querySelectorAll('a')).map((a) => a.getAttribute('href')) : [],
      ad01: (() => { const a = document.querySelector('[data-cnc-ad="AD-01"]'); return a ? Array.from(a.querySelectorAll('a')).map((x) => [x.getAttribute('href'), x.textContent]) : []; })(),
      order: (() => { const s = document.querySelector('#sec-F .shead'); return s && s.nextElementSibling && s.nextElementSibling.getAttribute('data-cnc-ad') === 'AD-01' && s.nextElementSibling.nextElementSibling && s.nextElementSibling.nextElementSibling.id === 'insp-F'; })() };
  });
  check(tag('demonstration: Section F lists two fictitious Issued reports from Rietvlei Civils and Building'), d.box && d.rows.length === 2 && d.rows.every((r) => /Issued/.test(r) && /fictitious/.test(r)), d.rows);
  check(tag('each report opens /bee-inspect/sample-report'), d.links.length === 2 && d.links.every((h) => h === '/bee-inspect/sample-report'), d.links);
  check(tag('the list sits in the Section F card, right under AD-01'), d.order);
  const u = d.ad01.length ? new URL(d.ad01[0][0], origin) : null;
  check(tag('AD-01 now opens /bee-inspect with the UTM rules'), u && u.pathname === '/bee-inspect' && u.searchParams.get('utm_source') === 'hsf_builder' && u.searchParams.get('utm_medium') === 'in_product_banner'
    && u.searchParams.get('utm_campaign') === 'bee_inspect_addon' && /^AD-01_[a-z0-9_]+$/.test(u.searchParams.get('utm_content') || ''), d.ad01);
  check(tag('AD-01 carries See a sample report to /bee-inspect/sample-report'), d.ad01.some(([h, t]) => /^\/bee-inspect\/sample-report\?utm_source=hsf_builder/.test(h) && /See a sample report/.test(t)), d.ad01);
  await page.evaluate(() => { window.__shotAbove = 20; });
  await shot(page, 'section-f-inspection-reports', vp, o, { sel: '#sec-F', max: W < 768 ? 1300 : 900 });
  check(tag('demonstration: no script error'), run.errors.length === 0, run.errors);
  await run.context.close();

  /* Live, signed in with a File: the stub list is empty and AD-01 above it is the empty state. */
  run = await open(browser, origin, vp, { path: '/hsf-builder?utm_source=hsf_builder&utm_medium=in_product_banner&utm_campaign=bee_inspect_addon&utm_content=AD-01_gaps', session: USER, api: API.live, wait: 1500 });
  page = run.page;
  await page.evaluate(() => { const s = document.getElementById('sec-F'); if (s) s.scrollIntoView({ block: 'start' }); });
  await page.waitForTimeout(500);
  d = await page.evaluate(() => { const b = document.getElementById('insp-F'); return { box: !!b, text: b ? b.textContent : '', rows: b ? b.querySelectorAll('tbody tr').length : -1, ad: !!document.querySelector('[data-cnc-ad="AD-01"] .cnc-ad') }; });
  check(tag('live: the Inspection reports list is empty, with AD-01 as its empty state'), d.box && d.rows === 0 && /No inspection reports yet/.test(d.text) && d.ad, d);
  const att = run.events.filter((e) => e.body && e.body.event === 'attribution_seen');
  check(tag('live: signed in, the visit\'s campaign tags go to /api/hsf-events once as attribution_seen, with nothing else'),
    att.length === 1 && Object.keys(att[0].body).sort().join() === 'event,page,utm_campaign,utm_content,utm_medium,utm_source,utm_term' && att[0].body.page === '/hsf-builder'
    && att[0].body.utm_content === 'AD-01_gaps' && att[0].body.utm_term === null && att[0].credentials === 'none', att);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(1200);
  check(tag('live: a reload does not send the same tags again'), run.events.filter((e) => e.body && e.body.event === 'attribution_seen').length === 1);
  check(tag('live: no script error'), run.errors.length === 0, run.errors);
  await run.context.close();

  /* Flag off: no list, no attribution. */
  run = await open(browser, origin, vp, { path: '/hsf-builder?demo=1&flags=bee_inspect_ads:0', wait: 800 });
  await run.page.check('#c-storage'); await run.page.check('#c-transfer'); await run.page.check('#c-authority');
  await run.page.click('#consent-btn');
  await run.page.waitForTimeout(500);
  check(tag('flag off: no Inspection reports list'), !(await run.page.evaluate(() => !!document.getElementById('insp-F'))));
  await run.context.close();

  /* Signed out: the sign in link's return address carries the tags. */
  run = await open(browser, origin, vp, { path: '/hsf-builder?utm_source=hsf_builder&utm_campaign=bee_inspect_addon&utm_content=AD-06_base', session: null, api: API.signedOut, wait: 1200 });
  page = run.page;
  await page.fill('#signin-email', 'bee@example.co.za');
  await page.click('#signin-btn');
  await page.waitForTimeout(600);
  const otp = await page.evaluate(() => globalThis.__OTP || []);
  const redirect = otp.length ? new URL(otp[0].options.emailRedirectTo) : null;
  check(tag('signed out: the sign in link returns to the builder with the campaign tags'), redirect && redirect.pathname === '/hsf-builder'
    && redirect.searchParams.get('utm_source') === 'hsf_builder' && redirect.searchParams.get('utm_content') === 'AD-06_base' && redirect.searchParams.get('utm_campaign') === 'bee_inspect_addon', otp);
  check(tag('signed out: nothing is reported before sign in'), run.events.filter((e) => e.body && e.body.event === 'attribution_seen').length === 0);
  await run.context.close();

  /* Without tags the return address is exactly what it was. */
  run = await open(browser, origin, vp, { path: '/hsf-builder', session: null, api: API.signedOut, wait: 1200 });
  await run.page.fill('#signin-email', 'bee@example.co.za');
  await run.page.click('#signin-btn');
  await run.page.waitForTimeout(600);
  const plain = await run.page.evaluate(() => globalThis.__OTP || []);
  check(tag('without tags the sign in link returns to the builder exactly as before'), plain.length === 1 && plain[0].options.emailRedirectTo === origin + '/hsf-builder', plain);
  await run.context.close();
}

/* ------------------------------------------------------------ main */
async function main(opts) {
  const o = Object.assign({ shots: false, log: (l) => console.log(l), list: [] }, opts || {});
  results.length = 0;
  const pw = findPlaywright();
  if (!pw) { o.log('bee-inspect-pages: Playwright not found'); return 2; }
  const server = createServer({ quiet: true, root: VERCEL });
  await new Promise((ok, bad) => { server.once('error', bad); server.listen(0, '127.0.0.1', ok); });
  const origin = 'http://127.0.0.1:' + server.address().port;
  const browser = await pw.chromium.launch();
  const started = Date.now();
  try {
    for (const vp of VIEWPORTS) {
      await productPage(browser, origin, vp, o);
      await sampleReport(browser, origin, vp, o);
      await getApp(browser, origin, vp, o);
      await claim(browser, origin, vp, o);
      await landing(browser, origin, vp, o);
      await builder(browser, origin, vp, o);
    }
  } finally {
    await browser.close();
    await new Promise((ok) => server.close(ok));
  }
  if (o.shots) o.list.sort((a, b) => a.file.localeCompare(b.file)).forEach((x) => o.log('  ' + x.file + '  ' + x.kb + ' KB'));
  const failed = results.filter((r) => !r.ok);
  for (const r of results) if (!r.ok || o.verbose) o.log((r.ok ? 'ok   ' : 'FAIL ') + r.name + (r.ok ? '' : '\n       ' + r.detail.slice(0, 1500)));
  o.log('bee-inspect-pages: ' + (failed.length ? 'FAIL' : 'PASS') + ', ' + (results.length - failed.length) + ' of ' + results.length + ' checks at ' + VIEWPORTS.map((v) => v.width).join(' and ')
    + 'px' + (o.shots ? ', ' + o.list.length + ' screenshots in docs/bee-inspect/p2' : '') + ', ' + ((Date.now() - started) / 1000).toFixed(0) + 's');
  return failed.length ? 1 : 0;
}

if (process.env.NODE_TEST_CONTEXT) {
  const { test } = await import('node:test');
  const missing = chromiumMissing();
  test('the Bee-Inspect P2 site pages, in Chromium (contract 16)', {
    skip: missing ? missing + ': run node test/browser/bee-inspect-pages.mjs where Chromium is installed' : false,
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
    console.error('bee-inspect-pages: could not run: ' + (e && e.stack ? e.stack : e));
    process.exit(1);
  });
}
