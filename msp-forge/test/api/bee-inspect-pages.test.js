'use strict';
// CNC | Bee-Inspect P2 site pages (hsf/BUILD-CONTRACT.md 16; hsf/BEE-INSPECT-BUILD-PROMPT.md A3, B6, B8).
// node --test; no network, no browser. The rendered half (layout, focus,
// shift, console, the builder flows) is test/browser/bee-inspect-pages.mjs.
//
//   copy        house rules on every visible word of /bee-inspect,
//               /bee-inspect/sample-report, /get-app and /claim, the P2 strings
//               of hsf/ads.js, js/cnc-bee.js and the builder's Inspection
//               reports list: no dash or hyphen punctuation in prose (the names
//               Bee-Inspect and Bee-Matched and identifiers such as F-01, VN-01
//               and SC-014 excepted), rand as R1 150,00, never "compliant" or
//               "guarantee", no internal system names, AI only assists, no
//               section or regulation numbers other than 16(1), 16(2) and
//               37(2), sales executives, no Plan links
//   pricing     one source (hsf/ads.js) with the B8 figures; no page types a price
//   schema      the FAQPage JSON-LD parses and matches the visible FAQ
//   noindex     flags.js removes <meta data-noindex-unless> only where the flag is on
//   claim       the code shape, hostile input, never echoed; the rewrite and headers
//   get-app     device detection and routing, store addresses null (stub)
//   utm         js/cnc-utm.js capture, query and report; /api/hsf-events attribution_seen
//   industry    the landing variants map onto codes in hsf/pricing.js
//   builder     the Section F list is flagged, stubbed and links only to the sample

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const http = require('node:http');

globalThis.__CNC_FILE_SEPARATION_LIB_ONLY = true;
const sep = require('./file-separation.test.js');

const ROOT = path.join(__dirname, '..', '..');
const VERCEL = path.join(ROOT, 'vercel');
const read = (rel) => fs.readFileSync(path.join(VERCEL, rel), 'utf8');
const NEW_PAGES = ['bee-inspect.html', 'bee-inspect/sample-report.html', 'get-app.html', 'claim.html'];

/* ------------------------------------------------------------ visible words */
const ENT = { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>', nbsp: ' ', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', middot: '·', hellip: '…', times: '×' };
function decode(s) {
  return String(s).replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (all, e) => {
    if (e[0] === '#') return String.fromCodePoint(e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
    return ENT[e.toLowerCase()] === undefined ? all : ENT[e.toLowerCase()];
  });
}
/* Text units a visitor reads or hears: markup text, the shown attributes, the
   meta description, and the FAQPage schema's questions and answers. */
function visibleUnits(html) {
  const units = [];
  let s = html.replace(/<!--[\s\S]*?-->/g, ' ');
  s = s.replace(/<script\b[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi, (m, j) => {
    const walk = (v) => { if (typeof v === 'string') units.push(v); else if (v && typeof v === 'object') Object.keys(v).filter((k) => !k.startsWith('@')).forEach((k) => walk(v[k])); };
    walk(JSON.parse(j));
    return ' ';
  });
  s = s.replace(/<(script|style)\b[\s\S]*?<\/\1\s*>/gi, ' ');
  const desc = /<meta name="description" content="([^"]*)"/.exec(s);
  if (desc) units.push(decode(desc[1]));
  s.replace(/\s(?:aria-label|alt|title|placeholder)="([^"]*)"/g, (m, v) => { units.push(decode(v)); return m; });
  for (const u of s.replace(/<[^>]+>/g, '\n').split(/\n\s*\n|\n/)) if (u.trim()) units.push(decode(u).replace(/\s+/g, ' ').trim());
  return units;
}
const ID_RE = /\b[A-Z]{1,4}(?:-[A-Z0-9]{2,5})+\b/g;
function dashProblems(units) {
  const bad = [];
  for (const u of units) {
    const t = u.replace(/Bee[-‑](?:Inspect|Matched)/g, 'Bee').replace(ID_RE, 'ID');
    if (/[‐-―−-]/.test(t)) bad.push(u.slice(0, 160));
  }
  return bad;
}
function randProblems(units) {
  const bad = [];
  for (const u of units) {
    for (const m of u.replace(/ /g, ' ').matchAll(/\bR ?\d[\d ]*(?:[.,]\d+)?/g)) if (!/^R\d{1,3}(?: \d{3})*,\d{2}$/.test(m[0].trim())) bad.push(m[0] + ' in ' + u.slice(0, 120));
    if (/\bpm\b|\bp\/m\b|ZAR ?\d/i.test(u)) bad.push(u.slice(0, 120));
  }
  return bad;
}
const INTERNAL = /\b(?:Grok|xAI|Supabase|Vercel|RevenueCat|DocuSeal|Telnyx|Ozow|Paystack|Sentry|Expo|kernel|MCO|FORGE|SharePoint|Cursor|AutoHive CRM|Branch|EAS|pgvector)\b/;
function ruleProblems(units) {
  const bad = [];
  for (const u of units) {
    if (/complian|guarantee/i.test(u)) bad.push('compliant or guarantee: ' + u);
    if (INTERNAL.test(u)) bad.push('internal name: ' + u);
    for (const m of u.matchAll(/\bAI\b\s*(\w+)?/g)) if (!['assists', 'assisted', 'Wallet'].includes(m[1])) bad.push('AI must only assist: ' + u);
    for (const m of u.matchAll(/\b(?:section|regulation|regulations|reg\.?)\s+(\d+[\w()]*)/gi)) if (!/^(?:16\(1\)|16\(2\)|37\(2\))$/.test(m[1])) bad.push('a legal number: ' + u);
    if (/\bsales (?:rep|reps|representative|agent|consultant|team)\b/i.test(u)) bad.push('staff are sales executives: ' + u);
  }
  return bad;
}
function pageText(rel) { return visibleUnits(read(rel)); }

for (const page of NEW_PAGES) {
  test(page + ': house rules on every visible word', () => {
    const units = pageText(page);
    assert.ok(units.length > 10, 'words found');
    assert.deepEqual(dashProblems(units), [], 'no dash or hyphen punctuation in prose');
    assert.deepEqual(randProblems(units), [], 'rand as R1 150,00');
    assert.deepEqual(ruleProblems(units), []);
  });
  test(page + ': no Plan link, the File menu, the logo to /health-and-safety-file, no internal platform name', () => {
    const html = read(page);
    assert.deepEqual(sep.scanHtml(html, page), [], 'no link to a Medical Surveillance Plan page');
    for (const href of ['/health-and-safety-file.html', '/hsf-builder.html', '/hsf-sample.html', '/portal.html', '/bee-inspect', '/get-app']) {
      assert.ok(new RegExp('<li(?: class="active")?><a href="' + href.replace(/[.]/g, '\\.') + '"').test(html), page + ' menu lacks ' + href);
    }
    assert.ok(html.includes('<a class="logo-link" href="/health-and-safety-file"'), 'logo link');
    assert.deepEqual(sep.platformHits(sep.withoutComments(html), page), []);
    assert.doesNotMatch(html, /apps\.apple\.com|play\.google\.com|apple-itunes-app|google-play-app/, 'no store link or smart app banner while the apps are not released');
    assert.doesNotMatch(html, /googletagmanager|gtag\(|fbq\(|connect\.facebook|doubleclick/i, 'no third party pixel');
  });
}

test('the new pages and every script they load are covered by the File separation checks', () => {
  for (const p of NEW_PAGES) assert.ok(sep.FILE_PAGES.includes(p), p + ' is in FILE_PAGES of test/api/file-separation.test.js');
  const scripts = sep.fileScripts();
  for (const s of ['js/cnc-bee.js', 'js/cnc-utm.js', 'js/flags.js', 'hsf/ads.js']) assert.ok(scripts.includes(s), s);
});

/* ------------------------------------------------------------ ads.js: pricing, one source */
function loadAds() {
  const window = {};
  vm.runInNewContext(read('hsf/ads.js'), { window, encodeURIComponent }, { filename: 'ads.js', timeout: 2000 });
  return window.HSF_ADS;
}
const A = loadAds();

test('ads.js holds the B8 prices once: base, extra company, AI Wallet, top ups, storage, VAT to be confirmed', () => {
  const P = A.price;
  assert.equal(P.base_zar, 299);
  assert.equal(P.extra_company_zar, 199);
  assert.equal(P.vat_inclusive, null);
  assert.equal(P.vat_line, 'VAT to be confirmed.');
  const [base, extra] = P.plans;
  assert.deepEqual([base.id, base.zar_month, base.wallet_zar_month, base.storage_gb], ['base', 299, 150, 10]);
  assert.deepEqual([extra.id, extra.zar_month, extra.wallet_zar_month, extra.storage_gb], ['extra_company', 199, 100, 10]);
  assert.ok(base.includes.some((x) => /One auditor and your first company/.test(x)) && base.includes.some((x) => /Unlimited inspections and template reports/.test(x)));
  assert.ok(base.includes.some((x) => x.includes('R150,00')) && extra.includes.some((x) => x.includes('R100,00')), 'the wallet words match the numbers');
  assert.deepEqual(JSON.parse(JSON.stringify(P.wallet.topups)), [{ zar: 99, value_zar: 99 }, { zar: 249, value_zar: 260 }, { zar: 499, value_zar: 550 }, { zar: 999, value_zar: 1150 }]);
  assert.deepEqual([P.wallet.auto_topup.zar, P.wallet.auto_topup.below_zar, P.wallet.auto_topup.opt_in], [99, 20, true]);
  assert.deepEqual([P.wallet.included_rolls_months, P.wallet.purchased_lasts_months, P.wallet.photo_tagging_free_per_report], [1, 12, 50]);
  assert.ok(P.wallet.points.some((x) => /holds rand, never tokens/.test(x)));
  assert.equal(P.storage.included_gb, 10);
  assert.equal(P.storage.packs, null, 'storage packs wait for the rate card');
  const units = [].concat(P.plans.flatMap((p) => [p.name].concat(p.includes)), P.wallet.points, P.storage.points, [P.vat_line, P.line, P.short]);
  assert.deepEqual(dashProblems(units), []);
  assert.deepEqual(randProblems(units), []);
  assert.deepEqual(ruleProblems(units), []);
});

test('no page types a price: the Bee-Inspect pages read every rand amount from ads.js', () => {
  for (const p of NEW_PAGES) {
    const units = pageText(p);
    const typed = units.filter((u) => /\bR\s?\d/.test(u.replace(/ /g, ' ')));
    assert.deepEqual(typed, [], p + ' types a rand amount');
  }
  const html = read('bee-inspect.html');
  for (const id of ['bi-plans', 'bi-topups', 'bi-wallet-points', 'bi-storage-points']) assert.ok(html.includes('id="' + id + '"'), id);
  assert.ok(html.includes('data-bee-price="line"'));
});

test('ads.js P2: every banner opens /bee-inspect, AD-01 adds See a sample report, the stores are a stub', () => {
  for (const id of ['AD-01', 'AD-02', 'AD-03', 'AD-04', 'AD-05', 'AD-06', 'AD-07', 'AD-08']) {
    const p = A.ads[id].primary;
    assert.equal(p.href, '/bee-inspect', id);
    assert.ok(!p.stub, id + ' is no longer a stub');
    assert.match(p.aria, /opens the Bee-Inspect page in a new tab$/, id);
  }
  assert.equal(A.ads['AD-01'].secondary, 'sample_report');
  assert.equal(A.links.sample_report.href, '/bee-inspect/sample-report');
  assert.equal(A.links.sample_report.label, 'See a sample report');
  assert.match(A.links.whatsapp_fallback.href, /^https:\/\/wa\.me\/27600702723\?text=/);
  assert.match(A.links.notify_me.href, /^https:\/\/wa\.me\/27600702723\?text=/);
  assert.deepEqual([A.app.ios_url, A.app.android_url, A.app.ios_app_id, A.app.android_package], [null, null, null, null]);
  assert.equal(A.app.stub, true);
  assert.equal(A.app.coming_soon, 'The Bee-Inspect app is coming to the App Store and Google Play.');
  assert.deepEqual(JSON.parse(JSON.stringify(A.inspection_reports_stub)), []);
});

/* ------------------------------------------------------------ the FAQPage schema */
test('bee-inspect.html: the FAQPage JSON-LD parses, is well formed and says what the visible FAQ says', () => {
  const html = read('bee-inspect.html');
  const m = /<script type="application\/ld\+json" id="faq-ld">([\s\S]*?)<\/script>/.exec(html);
  assert.ok(m, 'the schema block');
  const ld = JSON.parse(m[1]);
  assert.equal(ld['@context'], 'https://schema.org');
  assert.equal(ld['@type'], 'FAQPage');
  assert.ok(Array.isArray(ld.mainEntity) && ld.mainEntity.length >= 6);
  const visible = [];
  const re = /<details><summary>([\s\S]*?)<\/summary><div><p>([\s\S]*?)<\/p><\/div><\/details>/g;
  let v;
  const faq = html.slice(html.indexOf('<section id="faq"'), html.indexOf('</section>', html.indexOf('<section id="faq"')));
  while ((v = re.exec(faq))) visible.push([decode(v[1]).trim(), decode(v[2]).trim()]);
  assert.equal(visible.length, ld.mainEntity.length);
  ld.mainEntity.forEach((q, i) => {
    assert.equal(q['@type'], 'Question');
    assert.equal(q.acceptedAnswer['@type'], 'Answer');
    assert.equal(q.name, visible[i][0]);
    assert.equal(q.acceptedAnswer.text, visible[i][1]);
    assert.ok(q.name.length > 5 && q.acceptedAnswer.text.length > 20);
  });
  const all = ld.mainEntity.map((q) => q.name + ' ' + q.acceptedAnswer.text).join(' ');
  assert.match(all, /stays free/);
  assert.match(all, /AI assists/);
  assert.match(all, /MyClinicOnline/);
  assert.match(all, /does not diagnose/);
  for (const p of NEW_PAGES.filter((x) => x !== 'bee-inspect.html')) {
    for (const j of read(p).matchAll(/<script type="application\/(?:ld\+)?json"[^>]*>([\s\S]*?)<\/script>/g)) JSON.parse(j[1]);
  }
});

/* ------------------------------------------------------------ noindex */
function loadFlags(href, metas) {
  const u = new URL(href);
  const list = metas.map((name) => ({ name, gone: false, getAttribute: () => name, parentNode: null }));
  list.forEach((m) => { m.parentNode = { removeChild: (x) => { x.gone = true; } }; });
  const window = {
    location: { hostname: u.hostname, search: u.search },
    document: { documentElement: { classList: { add: () => {} } }, querySelectorAll: (sel) => (sel === 'meta[data-noindex-unless]' ? list : []) }
  };
  vm.runInNewContext(read('js/flags.js'), { window, URLSearchParams }, { filename: 'flags.js', timeout: 2000 });
  return { flags: window.CNC_FLAGS, list };
}
test('noindex unless the flag is on for the host', () => {
  const STAGING = 'https://cnc-msp-forge-staging-git-cl-f1797f-auto-hive-wesite-developers.vercel.app/bee-inspect';
  const PROD = 'https://www.carenetconsultants.co.za/bee-inspect';
  assert.equal(loadFlags(STAGING, ['bee_inspect_ads']).list[0].gone, true, 'staging: indexable');
  assert.equal(loadFlags('http://127.0.0.1:3000/bee-inspect', ['bee_inspect_ads']).list[0].gone, true, 'local: indexable');
  assert.equal(loadFlags(PROD, ['bee_inspect_ads']).list[0].gone, false, 'production, flag off: noindex stays');
  assert.equal(loadFlags(STAGING + '?flags=bee_inspect_ads:0', ['bee_inspect_ads']).list[0].gone, false, 'flag forced off: noindex stays');
  assert.equal(loadFlags(PROD + '?flags=bee_inspect_ads:1', ['bee_inspect_ads']).list[0].gone, true, 'flag forced on: indexable');
  assert.equal(loadFlags(STAGING, ['made_up_flag']).list[0].gone, false, 'an unknown flag name keeps noindex');
  assert.equal(loadFlags(STAGING, ['welcome_hook']).list[0].gone, false, 'a flag that is off keeps noindex');
  for (const p of ['bee-inspect.html', 'bee-inspect/sample-report.html', 'get-app.html']) {
    const html = read(p);
    const head = html.slice(0, html.indexOf('</head>'));
    const meta = head.indexOf('<meta name="robots" content="noindex" data-noindex-unless="bee_inspect_ads">');
    assert.ok(meta > 0, p + ' carries the gated robots tag');
    assert.ok(meta < head.indexOf('<script src="/js/flags.js"></script>'), p + ': the tag comes before flags.js, which removes it');
    assert.equal((head.match(/<meta name="robots"/g) || []).length, 1, p + ': one robots tag');
  }
  const claim = read('claim.html');
  assert.ok(claim.includes('<meta name="robots" content="noindex, nofollow">'), 'claim links are never indexed');
  assert.ok(!/data-noindex-unless/.test(claim));
  assert.ok(claim.includes('<meta name="referrer" content="no-referrer">'));
});

/* ------------------------------------------------------------ cnc-bee.js */
function loadBee(extra) {
  const window = Object.assign({ HSF_ADS: loadAds() }, extra || {});
  vm.runInNewContext(read('js/cnc-bee.js'), { window }, { filename: 'cnc-bee.js', timeout: 2000 });
  return window.CNCBee;
}
const B = loadBee();

test('cnc-bee.js: rand in house format', () => {
  assert.equal(B.zar(299), 'R299,00');
  assert.equal(B.zar(1150), 'R1 150,00');
  assert.equal(B.zar(4000), 'R4 000,00');
  assert.equal(B.zar(1234567.5), 'R1 234 567,50');
  assert.equal(B.zar('x'), '');
});

test('claim codes: the shape is checked, hostile input refused, nothing echoed', () => {
  const ok = { '/claim/K7PQ2MX9': 'K7PQ2MX9', '/claim/abc123': 'ABC123', '/claim/ABCDEF123456': 'ABCDEF123456', '/claim/k7pq2mx9/': 'K7PQ2MX9' };
  for (const [p, c] of Object.entries(ok)) assert.deepEqual(JSON.parse(JSON.stringify(B.claimCode(p))), { valid: true, code: c }, p);
  const bad = ['/claim/', '/claim', '/claim/ABC12', '/claim/ABCDEFG1234567', '/claim/ABC-123', '/claim/AB%20C123', '/claim/%3Cscript%3Ealert(1)%3C%2Fscript%3E',
    '/claim/%E0%A4%A', '/claim/ABC123/extra', '/claim/..%2F..%2Fetc', '/claims/ABC123', '/x/claim/ABC123', '/claim/ABC123?x=1', '/claim/ABC12３', null, undefined, 5];
  for (const p of bad) assert.deepEqual(JSON.parse(JSON.stringify(B.claimCode(p))), { valid: false, code: null }, String(p));
  const html = read('claim.html');
  const inline = Array.from(html.matchAll(/<script>([\s\S]*?)<\/script>/g)).map((m) => m[1]).join('\n');
  assert.match(inline, /CNCBee\.claimCode\(location\.pathname\)\.valid/);
  assert.doesNotMatch(inline, /innerHTML|outerHTML|insertAdjacentHTML|document\.write|textContent|innerText|localStorage|sessionStorage|fetch\(|sendBeacon/, 'the code is never written, stored or sent');
});

test('claim: vercel.json rewrites /claim/:code to /claim.html with noindex headers, and the local server does the same', async () => {
  const cfg = JSON.parse(read('vercel.json'));
  assert.ok(cfg.rewrites.some((r) => r.source === '/claim/:code' && r.destination === '/claim.html'));
  const h = cfg.headers.find((x) => x.source === '/claim/(.*)');
  assert.ok(h && h.headers.some((x) => x.key === 'X-Robots-Tag' && /noindex/.test(x.value)) && h.headers.some((x) => x.key === 'Referrer-Policy' && x.value === 'no-referrer'));
  assert.equal(sep.planTarget('/claim/ABC123', sep.SITE_ORIGIN + '/get-app'), null, '/claim is not a Plan page');
  const { createServer } = require('../../server/serve.js');
  const server = createServer({ quiet: true, root: VERCEL });
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  const get = (p) => new Promise((ok, bad) => http.get({ host: '127.0.0.1', port: server.address().port, path: p }, (res) => { let b = ''; res.on('data', (c) => { b += c; }); res.on('end', () => ok({ status: res.statusCode, headers: res.headers, body: b })); }).on('error', bad));
  try {
    const c = await get('/claim/K7PQ2MX9');
    assert.equal(c.status, 200);
    assert.match(c.body, /Claim your sign in/);
    assert.match(String(c.headers['x-robots-tag']), /noindex/);
    assert.equal(c.headers['referrer-policy'], 'no-referrer');
    assert.equal((await get('/bee-inspect')).status, 200);
    assert.match((await get('/bee-inspect/sample-report')).body, /Site inspection and risk assessment/);
    assert.equal((await get('/get-app')).status, 200);
    assert.equal((await get('/bee-inspect.html')).status, 308);
    assert.equal((await get('/.well-known/apple-app-site-association')).status, 404, 'no association file with placeholder ids');
    assert.equal((await get('/.well-known/assetlinks.json')).status, 404);
  } finally { await new Promise((ok) => server.close(ok)); }
  assert.ok(!fs.existsSync(path.join(VERCEL, '.well-known')), 'the app association files wait for the Apple team id and the Android fingerprint');
  const tpl = fs.readFileSync(path.join(ROOT, 'docs', 'bee-inspect', 'p2', 'app-links-templates.md'), 'utf8');
  assert.match(tpl, /\{\{apple_team_id\}\}/);
  assert.match(tpl, /\{\{android_sha256\}\}/);
});

test('get-app: device detection and routing are ready; with no store address every device waits', () => {
  assert.equal(B.detect('Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)', 'iPhone', 5), 'ios');
  assert.equal(B.detect('Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X)', 'iPad', 5), 'ios');
  assert.equal(B.detect('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15', 'MacIntel', 5), 'ios', 'iPadOS presents itself as a Mac');
  assert.equal(B.detect('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15', 'MacIntel', 0), 'desktop');
  assert.equal(B.detect('Mozilla/5.0 (Linux; Android 14; Pixel 8)', 'Linux armv8l', 5), 'android');
  assert.equal(B.detect('Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 'Win32', 0), 'desktop');
  assert.equal(B.detect(undefined, undefined, undefined), 'desktop');
  const app = loadAds().app;
  for (const d of ['ios', 'android', 'desktop']) assert.equal(B.route(d, app).action, 'wait', d);
  assert.deepEqual(JSON.parse(JSON.stringify(B.route('ios', { ios_url: 'https://apps.apple.com/za/app/bee-inspect/id000' }))), { action: 'store', url: 'https://apps.apple.com/za/app/bee-inspect/id000' });
  assert.equal(B.route('android', { android_url: 'https://play.google.com/store/apps/details?id=x' }).action, 'store');
  assert.equal(B.route('ios', { ios_url: 'javascript:alert(1)' }).action, 'wait', 'only a real store address is followed');
  assert.equal(B.route('ios', { ios_url: 'https://evil.example/apps.apple.com/' }).action, 'wait');
  assert.equal(B.route('desktop', { ios_url: 'https://apps.apple.com/x', android_url: 'https://play.google.com/x' }).action, 'wait', 'a computer never jumps to a store');
  assert.deepEqual(dashProblems(Object.values(B.DEVICE_LINE)), []);
  assert.deepEqual(ruleProblems(Object.values(B.DEVICE_LINE)), []);
  /* getApp on a stub document */
  const els = { 'ga-device': { textContent: '' }, 'ga-status': { textContent: '' } };
  const loc = { replaced: null, replace(u) { this.replaced = u; } };
  const r = B.getApp({ getElementById: (id) => els[id] || null }, { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)', platform: 'iPhone', maxTouchPoints: 5 }, loc);
  assert.equal(r.device, 'ios');
  assert.equal(loc.replaced, null, 'no store address: no redirect');
  assert.match(els['ga-device'].textContent, /iPhone or iPad/);
  assert.equal(els['ga-status'].textContent, 'The Bee-Inspect app is coming to the App Store and Google Play.');
});

test('cnc-bee.js: links take only this site, https or WhatsApp addresses from the data', () => {
  const s = B._lib.safeHref;
  for (const h of ['/bee-inspect', '/bee-inspect/sample-report', 'https://wa.me/27600702723?text=Hello', 'https://www.carenetconsultants.co.za/x']) assert.equal(s(h), h);
  for (const h of ['javascript:alert(1)', '//evil.example', 'http://x.example', '/x" onclick="y', 'data:text/html,x', '']) assert.equal(s(h), null, h);
});

/* ------------------------------------------------------------ cnc-utm.js */
function loadUtm(search, flagOn, opts) {
  const o = opts || {};
  const mem = {};
  const mk = (name) => (o.throws ? { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } }
    : { getItem: (k) => (Object.prototype.hasOwnProperty.call(mem, name + k) ? mem[name + k] : null), setItem: (k, v) => { mem[name + k] = String(v); } });
  const calls = [];
  const window = {
    CNC_FLAGS: { bee_inspect_ads: flagOn }, CNC_CONFIG: { apiBase: '' }, location: { search },
    fetch: (url, init) => { calls.push({ url, init }); return Promise.resolve({}); }
  };
  if (!o.noStorage) { window.sessionStorage = mk('s:'); window.localStorage = mk('l:'); }
  vm.runInNewContext(read('js/cnc-utm.js'), { window, URLSearchParams, encodeURIComponent, JSON }, { filename: 'cnc-utm.js', timeout: 2000 });
  return { U: window.CNCUtm, calls, mem, window };
}
test('cnc-utm.js: tags are kept only with the flag on, in shape, and handed over once', () => {
  const q = '?utm_source=hsf_builder&utm_medium=in_product_banner&utm_campaign=bee_inspect_addon&utm_content=AD-01_gaps&utm_term=a%40b.co.za&other=1';
  const off = loadUtm(q, false);
  assert.equal(off.U.read(), null, 'flag off: nothing is kept');
  assert.equal(off.U.query(), '');
  assert.equal(off.U.report('/hsf-builder'), false);
  assert.equal(off.calls.length, 0);

  const on = loadUtm(q, true);
  assert.deepEqual(JSON.parse(JSON.stringify(on.U.read())), { utm_source: 'hsf_builder', utm_medium: 'in_product_banner', utm_campaign: 'bee_inspect_addon', utm_content: 'AD-01_gaps' }, 'an email address is never kept');
  assert.equal(on.U.query(), '?utm_source=hsf_builder&utm_medium=in_product_banner&utm_campaign=bee_inspect_addon&utm_content=AD-01_gaps');
  assert.equal(on.U.report('/hsf-builder'), true);
  assert.equal(on.U.report('/hsf-builder'), false, 'the same tags are reported once');
  assert.equal(on.calls.length, 1);
  assert.equal(on.calls[0].url, '/api/hsf-events');
  assert.equal(on.calls[0].init.credentials, 'omit');
  assert.deepEqual(JSON.parse(on.calls[0].init.body), { event: 'attribution_seen', page: '/hsf-builder', utm_source: 'hsf_builder', utm_medium: 'in_product_banner', utm_campaign: 'bee_inspect_addon', utm_content: 'AD-01_gaps', utm_term: null });

  const none = loadUtm('?x=1', true);
  assert.equal(none.U.query(), '', 'no tags: the return address is left alone');
  assert.equal(none.U.report('/hsf-builder'), false);
  const hostile = loadUtm('?utm_source=%3Cscript%3E&utm_campaign=' + 'a'.repeat(65), true);
  assert.equal(hostile.U.read(), null);
  const blocked = loadUtm(q, true, { throws: true });
  assert.equal(blocked.U.read(), null, 'blocked storage keeps nothing and throws nothing');
  assert.equal(blocked.U.report('/hsf-builder'), true, 'the tags on the address itself are still handed over');
  const nostore = loadUtm(q, true, { noStorage: true });
  assert.equal(nostore.U.query(), '');
});

/* ------------------------------------------------------------ /api/hsf-events attribution_seen */
const REAL_FETCH = globalThis.fetch;
const handler = require('../../vercel/api/hsf-events');
function mockRes() {
  const res = { statusCode: 200, body: undefined, headers: {} };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (o) => { res.body = o; return res; };
  res.setHeader = (k, v) => { res.headers[k.toLowerCase()] = v; };
  return res;
}
async function post(body) { const res = mockRes(); await handler({ method: 'POST', body, headers: { 'x-forwarded-for': '198.51.100.9' }, socket: {} }, res); return res; }
test.mock.method(console, 'error', () => {});
test('hsf-events: attribution_seen reaches hsf_attribution_record with the page and the five tags only', async (t) => {
  process.env.SUPABASE_URL = 'https://unit-test.supabase.invalid';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
  const calls = [];
  globalThis.fetch = async (url, init) => { calls.push({ url: String(url), body: JSON.parse(init.body) }); return new Response(JSON.stringify({ accepted: true, id: 1 }), { status: 200 }); };
  t.after(() => { globalThis.fetch = REAL_FETCH; delete process.env.SUPABASE_URL; delete process.env.SUPABASE_SERVICE_ROLE_KEY; handler.resetLimits(); });
  handler.resetLimits();
  const good = { event: 'attribution_seen', page: '/hsf-builder', utm_source: 'hsf_builder', utm_medium: 'in_product_banner', utm_campaign: 'bee_inspect_addon', utm_content: 'AD-01_gaps', utm_term: null };
  let res = await post(good);
  assert.equal(res.statusCode, 202);
  assert.deepEqual(res.body, { accepted: true });
  assert.equal(calls[0].url, 'https://unit-test.supabase.invalid/rest/v1/rpc/hsf_attribution_record');
  assert.deepEqual(calls[0].body, { p: good });
  res = await post({ event: 'attribution_seen', page: '/hsf-builder', utm_campaign: 'spring' });
  assert.equal(res.statusCode, 202);
  assert.deepEqual(calls[1].body.p, { event: 'attribution_seen', page: '/hsf-builder', utm_source: null, utm_medium: null, utm_campaign: 'spring', utm_content: null, utm_term: null });
  const bad = [
    [Object.assign({}, good, { email: 'a@b.co.za' }), /unknown field/],
    [Object.assign({}, good, { ad_id: 'AD-01' }), /unknown field/],
    [Object.assign({}, good, { utm_term: 'someone@example.co.za' }), /bad utm_term/],
    [Object.assign({}, good, { utm_source: '<b>x</b>' }), /bad utm_source/],
    [Object.assign({}, good, { utm_content: 'x'.repeat(65) }), /bad utm_content/],
    [Object.assign({}, good, { page: '/shop' }), /unknown page/],
    [Object.assign({}, good, { utm_source: 5 }), /must be text/],
    [{ event: 'attribution_seen', page: '/hsf-builder' }, /no campaign tag/],
    [{ event: 'attribution_seen', page: '/hsf-builder', utm_source: '' }, /no campaign tag/]
  ];
  for (const [body, re] of bad) {
    const r = await post(body);
    assert.equal(r.statusCode, 400, JSON.stringify(body));
    assert.match(r.body.error, re, JSON.stringify(body));
  }
  assert.equal(calls.length, 2, 'only the good ones reached the database');
  assert.equal(handler.ATTRIBUTION_EVENT, 'attribution_seen');
  assert.ok(!handler.BROWSER_EVENTS.includes('attribution_seen'), 'the banner events are unchanged');
  globalThis.fetch = async () => new Response(JSON.stringify({ code: 'PGRST202' }), { status: 404 });
  res = await post(good);
  assert.equal(res.statusCode, 202, '058 not applied: dropped, never 500');
  assert.deepEqual(res.body, { accepted: false });
  delete process.env.SUPABASE_URL;
  res = await post(good);
  assert.deepEqual(res.body, { accepted: false }, 'no settings: dropped');
});

test('migration 058 carries the attribution table and 057 is left alone', () => {
  const m = fs.readFileSync(path.join(ROOT, 'supabase', 'migrations', '058_hsf_bee_inspect_attribution.sql'), 'utf8');
  assert.match(m, /create table if not exists hsf_attribution_event/);
  assert.match(m, /alter table hsf_attribution_event enable row level security/);
  assert.match(m, /revoke execute on function hsf_attribution_record\(jsonb\) from public, anon, authenticated/);
  assert.doesNotMatch(m, /alter table hsf_ad_event|drop table|hsf_ad_event_record/i, '057 objects are not touched');
});

/* ------------------------------------------------------------ the landing variants */
test('health-and-safety-file industry variants map onto pricing.js codes, flag gated, unknown values ignored', () => {
  const html = read('health-and-safety-file.html');
  const m = /window\.CNC_HSF_INDUSTRY_VARIANT = \(function \(\) \{\s*var V = (\{[\s\S]*?\});/.exec(html);
  assert.ok(m, 'the variant map');
  const V = vm.runInNewContext('(' + m[1] + ')');
  assert.deepEqual(Object.keys(V).sort(), ['agriculture', 'cleaning', 'construction', 'food', 'logistics', 'manufacturing', 'security']);
  const P = (() => { const w = {}; vm.runInNewContext(read('hsf/pricing.js'), { window: w }); return w.HSF_PRICING; })();
  const codes = new Set(P.industries.map((r) => r.code));
  const want = { construction: 'CONSTR', manufacturing: 'MANU', agriculture: 'AGRI', food: 'HOSP', logistics: 'TRANS', cleaning: 'CLEAN', security: 'SEC' };
  for (const [slug, code] of Object.entries(want)) {
    assert.equal(V[slug][0], code, slug);
    assert.ok(codes.has(code), code + ' is in pricing.js');
  }
  const units = Object.values(V).flatMap((v) => [v[1], v[2]]);
  assert.deepEqual(dashProblems(units), []);
  assert.deepEqual(ruleProblems(units), []);
  assert.match(html, /if \(!\(window\.CNC_FLAGS && window\.CNC_FLAGS\.bee_inspect_ads\)\) return null;/);
  assert.match(html, /if \(!Object\.prototype\.hasOwnProperty\.call\(V, k\)\) return null;/, 'unknown values, __proto__ included, are ignored');
  assert.match(html, /\.textContent = v\[2\]/, 'the hero line is set as text, never as markup');
  assert.match(html, /if \(IV && byCode\[IV\.code\]\) \{ sel\.value = IV\.code;/);
});

/* ------------------------------------------------------------ the builder */
test('hsf-builder: the Section F Inspection reports list is flagged, stubbed, and links only to the sample report', () => {
  const html = read('hsf-builder.html');
  const fn = html.slice(html.indexOf('const DEMO_REPORTS = ['), html.indexOf('/* Documents dropped on the section itself'));
  assert.ok(fn.length > 200);
  assert.match(fn, /if \(!\(window\.CNC_FLAGS && window\.CNC_FLAGS\.bee_inspect_ads\)\) return '';/);
  assert.match(fn, /const list = DEMO \? DEMO_REPORTS : stub;/);
  assert.match(fn, /inspection_reports_stub/);
  assert.ok(/\+ \(c === 'F' \? inspectionReportsHtml\(\) : ''\)/.test(html));
  const demo = vm.runInNewContext('(' + /const DEMO_REPORTS = (\[[\s\S]*?\]);/.exec(fn)[1] + ')');
  assert.equal(demo.length, 2);
  for (const r of demo) {
    assert.equal(r.status, 'Issued');
    assert.equal(r.href, '/bee-inspect/sample-report');
    assert.match(r.signed, /\(fictitious\)/);
    for (const k of ['title', 'site', 'date', 'signed']) assert.ok(r[k], k);
    assert.match(r.date, /^\d{2}\/\d{2}\/\d{4}$/);
  }
  const units = demo.flatMap((r) => [r.title, r.site, r.signed]).concat(Array.from(fn.matchAll(/'(<p class="muted">[^']*)'/g)).map((m) => decode(m[1].replace(/<[^>]+>/g, ''))));
  assert.deepEqual(dashProblems(units), []);
  assert.deepEqual(ruleProblems(units), []);
  assert.match(fn, /esc\(r\.title\)/, 'every value is escaped');
  assert.match(html, /auth\.signInWithEmail\(email, location\.origin \+ location\.pathname \+ utmQuery\(\)/, 'the tags ride on the sign in return address');
  assert.match(html, /window\.CNCUtm\.report\('\/hsf-builder'\)/, 'handed over at sign in');
  assert.ok(html.indexOf('<script src="/js/cnc-utm.js" defer></script>') < html.indexOf('<script type="module">'));
});

test('the File pages carry Bee-Inspect and Get the app in the menu and footer, behind the flag', () => {
  for (const p of ['health-and-safety-file.html', 'hsf-builder.html', 'hsf-sample.html', 'hsf-staff.html', 'legislation.html']) {
    const html = read(p);
    assert.ok(html.includes('<li data-flag="bee_inspect_ads"><a href="/bee-inspect">Bee-Inspect</a></li>'), p + ' menu');
    assert.ok(html.includes('<li data-flag="bee_inspect_ads"><a href="/get-app">Get the app</a></li>'), p + ' menu');
    assert.ok(/<nav class="cnc-footlinks" data-flag="bee_inspect_ads"/.test(html), p + ' footer');
    assert.ok(html.slice(0, html.indexOf('</head>')).includes('<script src="/js/flags.js"></script>'), p + ' loads flags.js in <head>');
    assert.doesNotMatch(html, /apps\.apple\.com|play\.google\.com/, p + ': no store badge or link yet');
  }
  const css = read('css/cnc-header.css');
  assert.ok(css.includes('html:not(.cnc-ads-on) [data-flag="bee_inspect_ads"]{display:none!important}'));
});
