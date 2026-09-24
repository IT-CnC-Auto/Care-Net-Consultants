'use strict';
// Contract 12.8 and 15.1: a Health and Safety File is never presented as a
// Medical Surveillance Plan. The File pages carry their own menu and never
// offer the Plan's menu items, its sample or its journey as if they were part
// of the File. The only mention of the Plan a File page may make is a sentence
// that names it as a separate Care Net product (for example that the signed
// Plan is filed in Section E as evidence).
//
// What is checked is the text a visitor can see: every File page (with its
// HTML, CSS and JavaScript comments removed), the text of its markup and of
// the attributes a browser shows (title, alt, aria-label, placeholder, value,
// content), every string in its inline scripts, and every string in the
// scripts it loads from this site (the builder's guidance, the sample Files,
// the shared header and the rest), sentence by sentence.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

/* The helpers of the separation test, loaded without registering its tests. */
const before = globalThis.__CNC_FILE_SEPARATION_LIB_ONLY;
globalThis.__CNC_FILE_SEPARATION_LIB_ONLY = true;
const lib = require('./file-separation.test.js');
globalThis.__CNC_FILE_SEPARATION_LIB_ONLY = before;

const VERCEL = path.join(__dirname, '..', '..', 'vercel');
const FILE_PAGES = ['health-and-safety-file.html', 'hsf-builder.html', 'hsf-sample.html', 'hsf-staff.html', 'legislation.html'];
const read = (rel) => fs.readFileSync(path.join(VERCEL, rel), 'utf8');

/* Offering the Plan, or calling the File a Plan. */
const PLAN_OFFERS = [
  /\bSample\s+Medical\s+Surveillance\s+Plans?\b/i,
  /\bSample\s+Plans?\b/i,
  /\bBuild\s+(?:your|my|a)\s+Plan\b/i
];
/* Any mention of the Plan by name. */
const PLAN_NAME = /\bMedical\s+Surveillance\s+Plans?\b/i;
/* The one kind of sentence that may name it. */
const SEPARATE_PRODUCT = /\bseparate\s+(?:Care\s+Net\s+)?product\b/i;

const ENTITIES = { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>', nbsp: ' ', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', middot: '·', hellip: '…' };
function decode(s) {
  return String(s).replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);?/gi, (all, e) => {
    if (e[0] === '#') {
      const cp = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      try { return String.fromCodePoint(cp); } catch (_) { return all; }
    }
    const v = ENTITIES[e.toLowerCase()];
    return v === undefined ? all : v;
  });
}

const BLOCK = /<\/?(?:p|div|li|ul|ol|dl|dt|dd|h[1-6]|section|article|header|footer|nav|main|aside|table|thead|tbody|tr|td|th|caption|details|summary|button|label|option|select|form|fieldset|legend|figure|figcaption|blockquote|br|hr|title)\b[^>]*>/gi;
const SHOWN_ATTRS = /\s(?:title|alt|aria-label|placeholder|value|content|label)\s*=\s*(?:"([^"]*)"|'([^']*)')/gi;

/* Markup (or HTML built as a string) as text units: a block element ends a
   unit, inline tags are dropped, and each shown attribute is a unit of its own. */
function markupUnits(html) {
  const units = [];
  let m;
  const tags = /<[a-zA-Z][^>]*>/g;
  while ((m = tags.exec(html))) {
    let a;
    SHOWN_ATTRS.lastIndex = 0;
    while ((a = SHOWN_ATTRS.exec(m[0]))) units.push(decode(a[1] !== undefined ? a[1] : a[2]));
  }
  const text = html.replace(BLOCK, '\n\n').replace(/<\/?[a-zA-Z][^>]*>/g, '');
  for (const u of text.split(/\n\s*\n/)) units.push(decode(u));
  return units;
}
function scriptUnits(src) {
  const units = [];
  for (const s of lib.lexJs(src).strings) {
    if (!s.value || /^\s*data:/i.test(s.value)) continue;
    if (/<[a-zA-Z]/.test(s.value)) markupUnits(s.value).forEach((u) => units.push(u));
    else units.push(s.value);
  }
  return units;
}
function pageUnits(html) {
  const units = [];
  const clean = lib.withoutComments(html);
  for (const part of lib.splitHtml(clean)) {
    if (part.kind === 'markup') markupUnits(part.text).forEach((u) => units.push(u));
    else if (part.kind === 'script' || part.kind === 'data') scriptUnits(part.text).forEach((u) => units.push(u));
  }
  return units;
}
function sentences(units) {
  const out = [];
  for (const u of units) {
    for (const s of String(u).replace(/\s+/g, ' ').split(/(?<=[.!?])\s+(?=[A-Z0-9"'‘“(])/)) {
      if (s.trim()) out.push(s.trim());
    }
  }
  return out;
}
/* Sentences that present the Plan as part of the File. */
function planProblems(units) {
  const bad = [];
  for (const s of sentences(units)) {
    const offer = PLAN_OFFERS.some((re) => re.test(s));
    const named = PLAN_NAME.test(s);
    if ((offer || named) && !SEPARATE_PRODUCT.test(s)) bad.push(s.length > 200 ? s.slice(0, 197) + '...' : s);
  }
  return bad;
}

test('the check catches a Plan offer or mention and lets the separate product sentence through', () => {
  const html = [
    '<nav><ul><li><a href="/hsf-builder">Build your Plan</a></li><li><a href="/hsf-sample">Sample Plan</a></li></ul></nav>',
    '<!-- <p>Sample Medical Surveillance Plan in a comment</p> -->',
    '<p class="help">We walk you through your Medical Surveillance Plan and its sign off.</p>',
    '<p>The Medical Surveillance Plan, a separate Care Net product signed by the OMP, is filed in Section E.</p>',
    '<img alt="Sample Medical Surveillance Plan cover">',
    '<script>/* Build my Plan */ const t = \'<b>Build my Plan</b>\'; const ok = "a Plan copied from another company";</script>'
  ].join('\n');
  const bad = planProblems(pageUnits(html)).sort();
  assert.deepStrictEqual(bad, ['Build my Plan', 'Build your Plan', 'Sample Medical Surveillance Plan cover', 'Sample Plan',
    'We walk you through your Medical Surveillance Plan and its sign off.']);
});

for (const page of FILE_PAGES) {
  const html = read(page);
  test(page + ' carries the File menu, not the Plan menu', () => {
    for (const href of ['/health-and-safety-file.html', '/hsf-builder.html', '/hsf-sample.html', '/portal.html']) {
      assert.ok(html.includes('<li><a href="' + href + '">'), page + ' menu lacks ' + href);
    }
    assert.ok(!/<li><a href="\/shop\.html">Build your Plan<\/a><\/li>/.test(html), page + ' still offers Build your Plan in its menu');
    assert.ok(!/<li><a href="\/sample\.html">Sample Plan<\/a><\/li>/.test(html), page + ' still offers Sample Plan in its menu');
  });
  test(page + ' never presents the File as a Plan, nor offers the Plan, in the text a visitor sees', () => {
    const bad = planProblems(pageUnits(html));
    assert.deepStrictEqual(bad, [], page + ': "Sample Plan", "Build your Plan", "Sample Medical Surveillance Plan" and any'
      + ' sentence naming the Medical Surveillance Plan must not appear unless the sentence names it as a separate Care Net product');
  });
  test(page + ': the scripts it loads never present the File as a Plan either', () => {
    const bad = [];
    for (const rel of lib.pageScripts(html, page)) {
      planProblems(scriptUnits(read(rel))).forEach((s) => bad.push(rel + ': ' + s));
    }
    assert.deepStrictEqual(bad, []);
  });
}

test('the sample Files hsf-sample.html loads by industry never present the File as a Plan', () => {
  const bad = [];
  for (const rel of lib.fileScripts().filter((f) => f.startsWith('hsf/'))) {
    planProblems(scriptUnits(read(rel))).forEach((s) => bad.push(rel + ': ' + s));
  }
  assert.deepStrictEqual(bad, []);
});

test('the portal names the two samples apart', () => {
  const html = read('portal.html');
  assert.ok(html.includes('title="Sample Medical Surveillance Plan">Sample Plan<'));
  assert.ok(html.includes('title="Sample Health and Safety File">Sample File<'));
});
