'use strict';
// CNC | Bee-Inspect P1 banners (hsf/BUILD-CONTRACT.md 16.3; hsf/BEE-INSPECT-BUILD-PROMPT.md A1, A2, A4).
// node --test; no network (global fetch mocked), no browser. The rendered half
// (every placement, forbidden states, layout shift, dismiss and collapse, focus,
// the File flow) is test/browser/bee-inspect-ads.mjs.
//
//   flags.js      window.CNC_FLAGS: bee_inspect_ads on for *.vercel.app, localhost
//                 and 127.0.0.1 only; welcome_hook off; ?flags=name:0|1 overrides.
//   ads.js        copy house rules: no dash or hyphen punctuation in prose (the
//                 names Bee-Inspect and Bee-Matched excepted), rand as R299,00,
//                 never "compliant" or "guarantee", no internal system names, AI
//                 only "assists", no Plan links, since P2 every call to action
//                 on /bee-inspect (UTMs added by cnc-ad.js, never on wa.me) and
//                 See a sample report on AD-01, AD-09 and AD-10 parked.
//   cnc-ad        the 15 KB budget for cnc-ad.js and cnc-ad.css, no third party
//                 address, the UTM rules, the flag off no op.
//   hsf-events    strict validation, size and rate limits, 202 and a dropped
//                 event when the database or its settings are missing, never 500,
//                 nothing personal passed on.
//   pages         the three pages that carry banners load the four files, in the
//                 right places; flags.js and ads.js also where P2 needs them.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

globalThis.__CNC_FILE_SEPARATION_LIB_ONLY = true;
const sep = require('./file-separation.test.js');

const ROOT = path.join(__dirname, '..', '..');
const VERCEL = path.join(ROOT, 'vercel');
const read = (rel) => fs.readFileSync(path.join(VERCEL, rel), 'utf8');

/* ------------------------------------------------------------ flags.js */
function loadFlags(href) {
  const u = new URL(href);
  const classes = new Set();
  const window = {
    location: { hostname: u.hostname, search: u.search },
    document: { documentElement: { classList: { add: (c) => classes.add(c) } } }
  };
  vm.runInNewContext(read('js/flags.js'), { window, URLSearchParams }, { filename: 'flags.js', timeout: 2000 });
  return { flags: window.CNC_FLAGS, classes };
}

test('flags.js: bee_inspect_ads is on for staging and local hosts only', () => {
  const on = ['https://cnc-msp-forge-staging-git-cl-f1797f-auto-hive-wesite-developers.vercel.app/hsf-builder', 'http://localhost:3000/', 'http://127.0.0.1:8080/portal'];
  const off = ['https://www.carenetconsultants.co.za/hsf-builder', 'https://carenetconsultants.co.za/', 'https://vercel.app.example.co.za/', 'https://evilvercel.app/', 'http://127.0.0.2/'];
  for (const h of on) {
    const { flags, classes } = loadFlags(h);
    assert.equal(flags.bee_inspect_ads, true, h);
    assert.equal(flags.welcome_hook, false, h);
    assert.ok(classes.has('cnc-ads-on'), h + ' marks <html> so slots take room');
  }
  for (const h of off) {
    const { flags, classes } = loadFlags(h);
    assert.equal(flags.bee_inspect_ads, false, h);
    assert.ok(!classes.has('cnc-ads-on'), h + ' leaves <html> alone');
  }
});

test('flags.js: ?flags=name:0|1 overrides, unknown names and bad pairs are ignored', () => {
  assert.equal(loadFlags('http://localhost/?flags=bee_inspect_ads:0').flags.bee_inspect_ads, false);
  assert.equal(loadFlags('https://www.carenetconsultants.co.za/?flags=bee_inspect_ads:1').flags.bee_inspect_ads, true);
  assert.equal(loadFlags('https://www.carenetconsultants.co.za/?flags=welcome_hook:1').flags.welcome_hook, true);
  const f = loadFlags('http://localhost/?flags=bee_inspect_ads:0,%20welcome_hook:1,made_up:1,bee_inspect_ads:yes').flags;
  assert.equal(f.bee_inspect_ads, false);
  assert.equal(f.welcome_hook, true);
  assert.ok(!('made_up' in f));
  assert.deepEqual(Object.keys(loadFlags('http://localhost/?flags=%3Cscript%3E').flags).sort(), ['bee_inspect_ads', 'welcome_hook']);
  const lib = loadFlags('http://localhost/').flags._lib;
  assert.deepEqual(JSON.parse(JSON.stringify(lib.parse('a:1,welcome_hook:0,bee_inspect_ads:1'))), { welcome_hook: false, bee_inspect_ads: true });
  assert.ok(Object.isFrozen(loadFlags('http://localhost/').flags), 'the flags cannot be changed by a page script');
});

/* ------------------------------------------------------------ ads.js */
function loadAds() {
  const window = {};
  vm.runInNewContext(read('hsf/ads.js'), { window, encodeURIComponent }, { filename: 'ads.js', timeout: 2000 });
  return window.HSF_ADS;
}
const A = loadAds();
const LIVE = ['AD-01', 'AD-02', 'AD-03', 'AD-04', 'AD-05', 'AD-06', 'AD-07', 'AD-08'];

/* Every string a visitor can read or hear: the banner words, the control
   labels and the prefilled WhatsApp messages. */
const VISIBLE_KEYS = new Set(['eyebrow', 'headline', 'headline_gaps', 'headline_gaps_one', 'headline_one', 'body', 'strip', 'tip', 'text', 'text_one',
  'label', 'aria', 'line', 'short', 'dismiss_label', 'collapse_label', 'show_label', 'show_aria', 'how_label', 'how_steps', 'subscriber_headline', 'subscriber_body']);
function visible(o, at, out) {
  if (Array.isArray(o)) o.forEach((x, i) => visible(x, at + '[' + i + ']', out));
  else if (o && typeof o === 'object') {
    for (const k of Object.keys(o)) {
      const v = o[k];
      if (VISIBLE_KEYS.has(k) && typeof v === 'string') out.push([at + '.' + k, v]);
      else if (VISIBLE_KEYS.has(k) && Array.isArray(v)) v.forEach((x, i) => out.push([at + '.' + k + '[' + i + ']', x]));
      else if (k === 'href' && typeof v === 'string' && v.startsWith('https://wa.me/')) out.push([at + '.href (WhatsApp message)', new URL(v).searchParams.get('text') || '']);
      else visible(v, at + '.' + k, out);
    }
  }
  return out;
}
function allStrings(o, at, out) {
  if (typeof o === 'string') out.push([at, o]);
  else if (o && typeof o === 'object') for (const k of Object.keys(o)) allStrings(o[k], at + '.' + k, out);
  return out;
}
const WORDS = visible(A, 'HSF_ADS', []);

test('ads.js: every banner of A2 is there, AD-09 and AD-10 parked', () => {
  for (const id of LIVE) {
    const ad = A.ads[id];
    assert.ok(ad && !ad.parked, id);
    assert.ok(ad.primary && ad.primary.label && ad.primary.href, id + ' has a primary call to action');
    assert.ok(ad.headline || ad.tip || ad.text, id + ' has words');
  }
  for (const id of ['AD-09', 'AD-10']) assert.equal(A.ads[id].parked, true, id);
  assert.equal(A.ads['AD-01'].collapses, true, 'AD-01 collapses, never vanishes');
  assert.equal(A.ads['AD-05'].collapses, true, 'AD-05 collapses, never vanishes');
  for (const id of LIVE.filter((x) => x !== 'AD-01' && x !== 'AD-05')) assert.ok(!A.ads[id].collapses, id + ' is dismissed for 14 days');
  assert.equal(A.ads['AD-04'].mobile, 'hidden', 'AD-04 is desktop only');
  for (const id of ['AD-01', 'AD-03', 'AD-05']) assert.equal(A.ads[id].mobile, 'inline', id);
  assert.match(A.ads['AD-01'].headline, /^Inspect it on your phone\. File it here\.$/);
  assert.equal(A.ads['AD-01'].headline_gaps, '{n} inspection records outstanding');
  assert.equal(A.ads['AD-03'].headline, 'Close {n} gaps in Section F');
  assert.equal(A.ads['AD-06'].headline, 'The File is free. The risk assessment is Bee-Inspect.');
  assert.equal(A.ads['AD-07'].headline, 'This is where Bee-Inspect fills Section F');
  assert.equal(A.ads['AD-08'].headline, 'Your File is built. Keep it current.');
  assert.match(A.ads['AD-05'].body, /^Bee-Matched finds the competent person\. Bee-Inspect is their tool on site/);
  assert.equal(A.dismiss_days, 14);
  assert.equal(A.max_per_screen, 2);
  assert.equal(A.subscriber_stub, false);
  assert.deepEqual(JSON.parse(JSON.stringify(A.tenant_stub)), { hidden: false, brand: null });
});

test('ads.js: prices in house format, VAT to be confirmed', () => {
  assert.equal(A.price.base_zar, 299);
  assert.equal(A.price.extra_company_zar, 199);
  assert.equal(A.price.vat_inclusive, null, 'pending Chantelle');
  assert.equal(A.price.line, 'From R299,00 a month. Extra company R199,00 a month. VAT to be confirmed.');
  const bad = [];
  for (const [at, s] of allStrings(A, 'HSF_ADS', [])) {
    for (const m of s.matchAll(/\bR ?\d[\d ]*(?:[.,]\d+)?/g)) if (!/^R\d{1,3}(?: \d{3})*,\d{2}$/.test(m[0].trim())) bad.push(at + ': ' + m[0]);
    if (/\bpm\b|\bp\/m\b|ZAR ?\d/i.test(s)) bad.push(at + ': ' + s);
  }
  assert.deepEqual(bad, []);
});

test('ads.js: no dash or hyphen punctuation in prose (Bee-Inspect and Bee-Matched keep theirs)', () => {
  const bad = [];
  for (const [at, s] of WORDS) {
    /* The banner reference that ends each WhatsApp message is an identifier. */
    const t = s.replace(/Bee-Inspect|Bee-Matched/g, 'Bee').replace(/ \(ref AD-\d\d\)$/, '');
    if (/[‐-―−]/.test(t) || /-/.test(t)) bad.push(at + ': ' + s);
  }
  assert.deepEqual(bad, []);
  assert.ok(WORDS.length > 40, 'the visible words were found (' + WORDS.length + ')');
});

test('ads.js: never "compliant" or "guarantee", no internal system names, AI only assists', () => {
  const bad = [];
  const INTERNAL = /\b(?:Grok|xAI|Supabase|Vercel|RevenueCat|DocuSeal|Telnyx|Ozow|Paystack|Sentry|Expo|kernel|MCO|FORGE|SharePoint|Cursor|AutoHive CRM)\b/i;
  for (const [at, s] of WORDS) {
    if (/complian|guarantee/i.test(s)) bad.push(at + ' (compliant or guarantee): ' + s);
    if (INTERNAL.test(s)) bad.push(at + ' (internal name): ' + s);
    for (const m of s.matchAll(/\bAI\b\s*(\w+)?/g)) if (m[1] !== 'assists' && m[1] !== 'Wallet') bad.push(at + ' (AI must only assist): ' + s);
    if (/\b(?:drafts?|writes?|decides?)\b/i.test(s) && /\bAI\b|Bee-Inspect/.test(s) && !/competent person/.test(s)) bad.push(at + ' (a machine drafting with no competent person): ' + s);
  }
  const code = sep.scriptWithoutComments(read('hsf/ads.js'));
  assert.deepEqual(sep.platformHits(code, 'hsf/ads.js'), []);
  assert.deepEqual(bad, []);
  for (const id of ['AD-01', 'AD-05', 'AD-06', 'AD-08']) {
    assert.match(A.ads[id].body, /competent person/, id + ' says who signs or uses it');
  }
  assert.match(A.ads['AD-01'].body, /competent person signs/);
  assert.ok(A.ui.how_steps.some((s) => /AI assists/.test(s) && /competent person reviews and signs/.test(s)));
});

/* P1 sent every call to action to WhatsApp until /bee-inspect existed; P2
   (contract 16, this round) switches them to the product page, where cnc-ad.js
   adds the UTM rules, and turns on See a sample report. */
test('ads.js P2: every banner opens /bee-inspect, AD-01 adds See a sample report, WhatsApp keeps no UTM, no Plan page', () => {
  const links = allStrings(A, 'HSF_ADS', []).filter(([at, s]) => /\.(?:href|future_href)$/.test(at) && s);
  assert.ok(links.length >= 9);
  for (const [at, s] of links) {
    assert.equal(sep.planTarget(s, 'https://file-pages.invalid/hsf-builder'), null, at + ' is a Plan page: ' + s);
    if (/^https:\/\/wa\.me\//.test(s)) {
      const u = new URL(s);
      assert.deepEqual(Array.from(u.searchParams.keys()), ['text'], at + ': only the prefilled message, no UTM on wa.me');
      assert.match(u.searchParams.get('text'), /Bee-Inspect/, at);
    }
  }
  for (const id of LIVE) {
    const p = A.ads[id].primary;
    assert.equal(p.href, '/bee-inspect', id);
    assert.ok(!p.stub, id + ' is no longer a stub');
    assert.match(p.aria, /opens the Bee-Inspect page in a new tab$/, id);
  }
  assert.equal(A.ads['AD-01'].secondary, 'sample_report', 'AD-01 carries See a sample report');
  for (const id of LIVE.filter((x) => x !== 'AD-01')) assert.ok(!A.ads[id].secondary, id + ' has one call to action');
  assert.equal(A.links.sample_report.href, '/bee-inspect/sample-report');
  assert.equal(A.links.sample_report.label, 'See a sample report');
  assert.equal(A.links.open_app.stub, true, 'Open Bee-Inspect stays a stub until P3 and P4');
  assert.match(A.links.open_app.href, /^https:\/\/wa\.me\/27600702723\?text=/);
  assert.deepEqual(JSON.parse(JSON.stringify(A.utm)), {
    utm_source: 'hsf_builder', utm_medium: 'in_product_banner', utm_campaign: 'bee_inspect_addon', utm_content: '{ad_id}_{variant}',
    never_on_hosts: ['wa.me', 'api.whatsapp.com']
  });
});

/* ------------------------------------------------------------ cnc-ad.js and cnc-ad.css */
const BUDGET = 15 * 1024;
test('cnc-ad.js and cnc-ad.css stay under 15 KB together, with no third party address', () => {
  const js = fs.statSync(path.join(VERCEL, 'js/cnc-ad.js')).size;
  const css = fs.statSync(path.join(VERCEL, 'css/cnc-ad.css')).size;
  assert.ok(js + css < BUDGET, 'cnc-ad.js ' + js + ' + cnc-ad.css ' + css + ' = ' + (js + css) + ' bytes, budget ' + BUDGET);
  const src = read('js/cnc-ad.js') + read('css/cnc-ad.css');
  assert.doesNotMatch(src, /https?:\/\/(?!wa\.me)/, 'no address off this site: no pixel, no tag manager, no font or image CDN');
  assert.doesNotMatch(src, /googletagmanager|gtag\(|fbq\(|dataLayer|doubleclick|facebook|linkedin|hotjar|clarity/i);
  assert.doesNotMatch(src, /document\.cookie/, 'no cookie is read or written');
  assert.match(read('js/cnc-ad.js'), /'\/api\/hsf-events'/, 'first party events only');
  assert.match(read('css/cnc-ad.css'), /prefers-reduced-motion:reduce/);
  assert.match(read('css/cnc-ad.css'), /:focus-visible\{outline:3px solid/);
  assert.ok(read('css/cnc-ad.css').includes('@media (max-width:767px){.cnc-ad-slot--full{min-height:300px}.cnc-ad-slot--tip{min-height:150px}.cnc-ads-on .cnc-ad-slot--desk{display:none}}'), 'AD-04 hidden under 768 pixels');
});

function loadCncAd(flagOn) {
  const window = {
    CNC_FLAGS: { bee_inspect_ads: flagOn }, HSF_ADS: loadAds(), CNC_CONFIG: { apiBase: '' },
    localStorage: { getItem: () => null, setItem: () => {} }, innerHeight: 800, scrollY: 0
  };
  const document = { readyState: 'complete', querySelectorAll: () => [], createElement: () => { throw new Error('no DOM in this test'); } };
  const location = new URL('http://127.0.0.1:3000/hsf-builder');
  const calls = [];
  window.fetch = (url, init) => { calls.push({ url, init }); return Promise.resolve({}); };
  vm.runInNewContext(read('js/cnc-ad.js'), { window, document, location, URL, JSON, navigator: {}, setTimeout }, { filename: 'cnc-ad.js', timeout: 2000 });
  return { CNCAds: window.CNCAds, calls };
}

test('cnc-ad.js: flag off is a no op; band, UTM rules and the tenant hook', () => {
  const off = loadCncAd(false).CNCAds;
  assert.equal(off.enabled(), false);
  const slot = { className: 'x cnc-ad-slot cnc-ad-slot--full', hidden: false, innerHTML: 'old' };
  assert.equal(off.render(slot, 'AD-01', { n: 3 }), false);
  assert.equal(slot.hidden, true);
  assert.equal(slot.innerHTML, '');
  assert.equal(slot.className, 'x', 'the slot gives its room back');
  assert.equal(off.place({}, 'afterend', 'AD-01', {}), null);

  const { CNCAds: on, calls } = loadCncAd(true);
  assert.equal(on.enabled(), true);
  assert.deepEqual([null, 0, 1, 2, 3, 5, 6, 40].map((n) => on.band(n)), ['na', '0', '1to2', '1to2', '3to5', '3to5', '6plus', '6plus']);
  const wa = 'https://wa.me/27600702723?text=Hello';
  assert.equal(on.withUtm(wa, 'AD-01', 'gaps'), wa, 'never a UTM on wa.me');
  assert.equal(on.withUtm('/bee-inspect', 'AD-01', 'gaps'),
    '/bee-inspect?utm_source=hsf_builder&utm_medium=in_product_banner&utm_campaign=bee_inspect_addon&utm_content=AD-01_gaps');
  assert.equal(on.withUtm('https://www.carenetconsultants.co.za/bee-inspect?x=1', 'AD-06', 'base'),
    'https://www.carenetconsultants.co.za/bee-inspect?x=1&utm_source=hsf_builder&utm_medium=in_product_banner&utm_campaign=bee_inspect_addon&utm_content=AD-06_base');
  on.configure({ hidden: true });
  assert.equal(on.enabled(), false, 'a tenant that hides the banners sees none');
  on.configure({ hidden: false, brand: { accent: 'red; background:url(x)', label: 'x'.repeat(80) } });
  assert.equal(on._state.brand.accent, null, 'only a #rrggbb colour is taken');
  assert.equal(on._state.brand.label.length, 40);
  on.track('ad_click', { id: 'AD-03', ctx: { n: 4, industry: 'CONSTR', fBand: '3to5' } });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, '/api/hsf-events');
  assert.equal(calls[0].init.credentials, 'omit', 'no cookie goes with an event');
  assert.equal(calls[0].init.keepalive, true);
  assert.deepEqual(JSON.parse(calls[0].init.body), { event: 'ad_click', ad_id: 'AD-03', variant: 'gaps', page: '/hsf-builder', industry: 'CONSTR', f_band: '3to5' });
});

/* ------------------------------------------------------------ the pages */
/* P2: flags.js also runs on the other File pages (the flagged menu items) and on
   the Bee-Inspect pages (noindex until the flag is on); ads.js, data only, also
   feeds the Bee-Inspect pages their prices. The banner itself stays on the three
   banner pages. */
test('the banner (cnc-ad.js and cnc-ad.css) loads on the three banner pages only; flags.js and ads.js where P2 needs them', () => {
  const pages = { 'hsf-builder.html': '/', 'health-and-safety-file.html': '/', 'portal.html': '' };
  for (const [page, pre] of Object.entries(pages)) {
    const html = read(page);
    const head = html.slice(0, html.indexOf('</head>'));
    assert.ok(head.includes('<script src="' + pre + 'js/flags.js"></script>'), page + ': flags.js in <head>, not deferred');
    assert.ok(head.includes('<link rel="stylesheet" href="' + pre + 'css/cnc-ad.css'), page + ': cnc-ad.css in <head>');
    assert.ok(html.includes('<script src="' + pre + 'hsf/ads.js" defer></script>'), page + ': ads.js');
    assert.ok(html.includes('<script src="' + pre + 'js/cnc-ad.js" defer></script>'), page + ': cnc-ad.js');
    assert.ok(html.indexOf(pre + 'js/flags.js') < html.indexOf(pre + 'js/cnc-ad.js'));
  }
  const flagsToo = ['hsf-sample.html', 'hsf-staff.html', 'legislation.html', 'bee-inspect.html', 'get-app.html', 'claim.html', 'bee-inspect/sample-report.html'];
  const adsData = ['bee-inspect.html', 'get-app.html', 'claim.html'];
  for (const f of flagsToo) {
    const html = read(f);
    assert.ok(html.slice(0, html.indexOf('</head>')).includes('<script src="/js/flags.js"></script>'), f + ': flags.js in <head>');
    assert.doesNotMatch(html, /cnc-ad\.(?:js|css)/, f + ' carries no banner');
    if (adsData.includes(f)) assert.ok(html.includes('<script src="/hsf/ads.js"></script>'), f + ': ads.js for its prices and links');
    else assert.doesNotMatch(html, /hsf\/ads\.js/, f);
  }
  for (const f of fs.readdirSync(VERCEL).filter((x) => x.endsWith('.html') && !(x in pages) && !flagsToo.includes(x))) {
    assert.doesNotMatch(read(f), /cnc-ad\.(?:js|css)|hsf\/ads\.js|js\/flags\.js/, f + ' carries no banner');
  }
});

test('the builder keeps banners off the forbidden states and out of the consent panel', () => {
  const html = read('hsf-builder.html');
  const m = /const AD_BLOCKED = (\[[^\]]*\]);/.exec(html);
  assert.ok(m, 'AD_BLOCKED is found');
  assert.deepEqual(JSON.parse(m[1].replace(/'/g, '"')).sort(), ['st-consent', 'st-error', 'st-loading', 'st-noaccount', 'st-signin']);
  assert.match(html, /if \(!A \|\| !S\.detail \|\| \$\('st-file'\)\.hidden \|\| AD_BLOCKED\.some/);
  assert.match(html, /function adsSafe\(\) \{ try \{ adsSync\(\); \} catch \(_\)/, 'a banner fault never stops the builder');
  for (const id of ['st-consent', 'consents', 'consent-form', 'queue', 'del-panel']) {
    assert.doesNotMatch(html, new RegExp("\\$\\('" + id + "'\\)[^;]*A\\.place|place\\(\\$\\('" + id + "'\\)"), 'nothing is placed in #' + id);
  }
  const landing = read('health-and-safety-file.html');
  const slotAt = landing.indexOf('data-cnc-ad-slot="AD-06"');
  assert.ok(slotAt > landing.indexOf('<section id="two-ways"') && slotAt < landing.indexOf('<section id="pricing"'), 'AD-06 below the hero, outside the pricing table');
});

/* ------------------------------------------------------------ /api/hsf-events */
const SUPABASE_URL = 'https://unit-test.supabase.invalid';
const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
const REAL_FETCH = globalThis.fetch;
const handler = require('../../vercel/api/hsf-events');

function setEnv(on) {
  if (on) { process.env.SUPABASE_URL = SUPABASE_URL; process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY; }
  else { delete process.env.SUPABASE_URL; delete process.env.SUPABASE_SERVICE_ROLE_KEY; }
}
function installFetch(t, answer) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), body: init && init.body ? JSON.parse(init.body) : null, headers: Object.assign({}, init && init.headers) });
    if (answer === 'throw') throw new Error('network down');
    return answer || new Response(JSON.stringify({ accepted: true, id: 1 }), { status: 200 });
  };
  t.after(() => { globalThis.fetch = REAL_FETCH; setEnv(false); handler.resetLimits(); });
  return calls;
}
function req(body, headers, method) {
  return { method: method || 'POST', body, headers: Object.assign({ 'x-forwarded-for': '198.51.100.7' }, headers || {}), socket: {} };
}
function mockRes() {
  const res = { statusCode: 200, body: undefined, headers: {} };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (o) => { res.body = o; return res; };
  res.setHeader = (k, v) => { res.headers[k.toLowerCase()] = v; };
  return res;
}
async function call(body, headers, method) { const res = mockRes(); await handler(req(body, headers, method), res); return res; }
const GOOD = { event: 'ad_impression', ad_id: 'AD-01', variant: 'gaps', page: '/hsf-builder', industry: 'CONSTR', f_band: '3to5' };
test.mock.method(console, 'error', () => {});

test('hsf-events: a good event reaches hsf_ad_event_record with the six fields and nothing else', async (t) => {
  setEnv(true);
  const calls = installFetch(t);
  const res = await call(Object.assign({}, GOOD), { cookie: 'sb-access-token=secret', authorization: 'Bearer x.y.z' });
  assert.equal(res.statusCode, 202);
  assert.deepEqual(res.body, { accepted: true });
  assert.equal(res.headers['cache-control'], 'no-store');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, SUPABASE_URL + '/rest/v1/rpc/hsf_ad_event_record');
  assert.deepEqual(calls[0].body, { p: GOOD });
  const sent = JSON.stringify(calls[0].body);
  assert.doesNotMatch(sent, /198\.51\.100\.7|secret|Bearer/, 'no address, cookie or token is passed on');
  const str = await call(JSON.stringify({ event: 'ad_click', ad_id: 'AD-08', variant: 'base', page: '/portal', industry: null, f_band: 'na' }));
  assert.equal(str.statusCode, 202, 'a string body (sendBeacon) is read too');
  assert.deepEqual(calls[1].body, { p: { event: 'ad_click', ad_id: 'AD-08', variant: 'base', page: '/portal', industry: null, f_band: 'na' } });
  const bare = await call({ event: 'ad_dismiss', ad_id: 'AD-06', variant: 'base', page: '/health-and-safety-file' });
  assert.equal(bare.statusCode, 202);
  assert.deepEqual(calls[2].body.p, { event: 'ad_dismiss', ad_id: 'AD-06', variant: 'base', page: '/health-and-safety-file', industry: null, f_band: null });
});

test('hsf-events: strict validation', async (t) => {
  setEnv(true);
  const calls = installFetch(t);
  const bad = [
    [Object.assign({}, GOOD, { email: 'someone@example.co.za' }), /unknown field/],
    [Object.assign({}, GOOD, { user_id: 'u1' }), /unknown field/],
    [Object.assign({}, GOOD, { event: 'page_view' }), /unknown event/],
    [Object.assign({}, GOOD, { ad_id: 'AD-09' }), /unknown banner/],
    [Object.assign({}, GOOD, { ad_id: 'AD-11' }), /unknown banner/],
    [Object.assign({}, GOOD, { ad_id: 'ad-01' }), /unknown banner/],
    [Object.assign({}, GOOD, { variant: 'Gaps-1' }), /bad variant/],
    [Object.assign({}, GOOD, { variant: 'x'.repeat(25) }), /bad variant/],
    [Object.assign({}, GOOD, { page: '/' }), /unknown page/],
    [Object.assign({}, GOOD, { page: '/shop' }), /unknown page/],
    [Object.assign({}, GOOD, { industry: 'constr' }), /bad industry/],
    [Object.assign({}, GOOD, { industry: 'CONSTR-1' }), /bad industry/],
    [Object.assign({}, GOOD, { f_band: '7' }), /bad Section F band/],
    [Object.assign({}, GOOD, { variant: 5 }), /must be text/],
    [Object.assign({}, GOOD, { industry: { a: 1 } }), /must be text/],
    [[GOOD], /JSON object/],
    ['not json', /must be JSON/],
    [null, /JSON object/]
  ];
  for (const [body, re] of bad) {
    const res = await call(body);
    assert.equal(res.statusCode, 400, JSON.stringify(body));
    assert.match(res.body.error, re, JSON.stringify(body));
  }
  for (const ev of handler.SERVER_EVENTS) {
    const res = await call(Object.assign({}, GOOD, { event: ev }));
    assert.equal(res.statusCode, 400, ev + ' is refused from a page');
    assert.match(res.body.error, /recorded by Care Net/);
  }
  assert.deepEqual(handler.BROWSER_EVENTS, ['ad_impression', 'ad_click', 'ad_dismiss', 'ad_qr_shown']);
  assert.equal((await call(Object.assign({}, GOOD, { event: 'ad_qr_shown' }))).statusCode, 202);
  assert.equal((await call(GOOD, {}, 'GET')).statusCode, 405);
  assert.equal((await call('{"event":"' + 'x'.repeat(2000) + '"}')).statusCode, 413);
  assert.equal((await call(Object.assign({}, GOOD, { variant: 'y'.repeat(2000) }))).statusCode, 413);
  assert.equal((await call(GOOD, { 'content-length': '5000' })).statusCode, 413);
  assert.equal(calls.length, 1, 'only the one good event reached the database');
});

test('hsf-events: no settings, no function or no database: 202 and the event is dropped, never 500', async (t) => {
  setEnv(false);
  let calls = installFetch(t);
  let res = await call(GOOD);
  assert.equal(res.statusCode, 202);
  assert.deepEqual(res.body, { accepted: false });
  assert.equal(calls.length, 0, 'nothing is sent without the settings');

  setEnv(true);
  calls = installFetch(t, new Response(JSON.stringify({ code: 'PGRST202', message: 'Could not find the function public.hsf_ad_event_record(p) in the schema cache' }), { status: 404 }));
  res = await call(GOOD);
  assert.equal(res.statusCode, 202);
  assert.deepEqual(res.body, { accepted: false });

  calls = installFetch(t, 'throw');
  setEnv(true);
  res = await call(GOOD);
  assert.equal(res.statusCode, 202);
  assert.deepEqual(res.body, { accepted: false });

  calls = installFetch(t, new Response(JSON.stringify({ accepted: false, reason: 'rate' }), { status: 200 }));
  setEnv(true);
  res = await call(GOOD);
  assert.deepEqual(res.body, { accepted: false }, 'the database refused a flood');
});

test('hsf-events: per instance rate limits, per caller and overall', async (t) => {
  setEnv(true);
  const calls = installFetch(t);
  handler.resetLimits();
  const { PER_CALLER, PER_INSTANCE } = handler.LIMITS;
  for (let i = 0; i < PER_CALLER; i++) assert.equal((await call(GOOD)).statusCode, 202);
  const over = await call(GOOD);
  assert.equal(over.statusCode, 429);
  assert.equal((await call(GOOD, { 'x-forwarded-for': '203.0.113.9' })).statusCode, 202, 'another caller still gets through');
  let n = PER_CALLER + 1;
  let ip = 0;
  while (n < PER_INSTANCE) {
    ip++;
    for (let i = 0; i < PER_CALLER && n < PER_INSTANCE; i++, n++) await call(GOOD, { 'x-forwarded-for': '192.0.2.' + ip });
  }
  assert.equal((await call(GOOD, { 'x-forwarded-for': '192.0.2.250' })).statusCode, 429, 'the instance as a whole is capped');
  assert.equal(calls.length, PER_INSTANCE);
  assert.ok(calls.every((c) => !/192\.0\.2\.|198\.51\.100\.|203\.0\.113\./.test(JSON.stringify(c))), 'no address is ever passed on');
});
