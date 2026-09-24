'use strict';
// Contract 12.7: every section has an example on Care Net letterhead, the files
// exist, and the legislation page has an anchor for every background.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..', '..');
const VERCEL = path.join(ROOT, 'vercel');
const SECTIONS = 'ABCDEFGHIJKLMNO'.split('');

function loadWindowScript(file) {
  const ctx = { window: {} };
  vm.runInNewContext(fs.readFileSync(path.join(VERCEL, file), 'utf8'), ctx);
  return JSON.parse(JSON.stringify(ctx.window));
}
const EXAMPLES = loadWindowScript('hsf/examples.js').CNC_HSF_EXAMPLES;
const LEG = loadWindowScript('hsf/legislation.js').CNC_LEGISLATION;
const INDEX = loadWindowScript('hsf/legislation-index.js').CNC_LEGISLATION_INDEX;
const BACKGROUNDS = JSON.parse(fs.readFileSync(path.join(ROOT, 'hsf', 'legislation', 'backgrounds.json'), 'utf8')).instruments;

test('every section A to O has at least one example', () => {
  assert.ok(Array.isArray(EXAMPLES), 'vercel/hsf/examples.js must set window.CNC_HSF_EXAMPLES');
  for (const s of SECTIONS) {
    assert.ok(EXAMPLES.some((e) => e.section === s), 'no example for Section ' + s);
  }
});

test('every example has its DOCX and PDF on disk, and every source is listed', () => {
  for (const e of EXAMPLES) {
    assert.match(e.slug, /^[A-O]-[a-z0-9-]+$/);
    assert.ok(e.slug.startsWith(e.section + '-'), e.slug + ' is filed under the wrong section');
    for (const [kind, magic] of [['docx', 'PK'], ['pdf', '%PDF']]) {
      assert.strictEqual(e[kind], '/examples/' + e.slug + '.' + kind, e.slug + ' ' + kind + ' address');
      const file = path.join(VERCEL, e[kind]);
      assert.ok(fs.existsSync(file), file + ' is missing');
      const head = fs.readFileSync(file).subarray(0, magic.length).toString('latin1');
      assert.strictEqual(head, magic, file + ' is not a ' + kind);
    }
  }
  const sources = fs.readdirSync(path.join(ROOT, 'hsf', 'examples')).filter((f) => /^[A-O]-[a-z0-9-]+\.json$/.test(f)).map((f) => f.replace(/\.json$/, ''));
  assert.deepStrictEqual(sources.sort(), EXAMPLES.map((e) => e.slug).sort(), 'examples.js is out of step with hsf/examples/*.json; run hsf/build_examples.mjs');
});

test('the legislation page has an anchor for every background', () => {
  const html = fs.readFileSync(path.join(VERCEL, 'legislation.html'), 'utf8');
  assert.ok(html.includes('<script src="/hsf/legislation.js"></script>'), 'legislation.html must load /hsf/legislation.js');
  assert.ok(html.includes('\'<article class="card leg" id="\' + esc(e.slug) + \'"'), 'legislation.html must anchor each entry at its slug');
  const want = BACKGROUNDS.map((b) => b.slug).sort();
  assert.deepStrictEqual(LEG.instruments.map((e) => e.slug).sort(), want, 'legislation.js is out of step with backgrounds.json');
  assert.deepStrictEqual(INDEX.map((e) => e.slug).sort(), want, 'legislation-index.js is out of step with backgrounds.json');
  assert.strictEqual(new Set(want).size, want.length, 'a slug repeats');
  for (const s of want) assert.match(s, /^[a-z0-9]+(-[a-z0-9]+)*$/);
});

test('the legislation data is current with its sources', { skip: spawnSync('python3', ['--version']).status !== 0 && 'python3 not available' }, () => {
  const r = spawnSync('python3', [path.join(ROOT, 'hsf', 'build_legislation.py'), '--check'], { encoding: 'utf8' });
  assert.strictEqual(r.status, 0, r.stderr || r.stdout);
});

test('status wording is exactly the four the contract allows, and never overstated', () => {
  assert.deepStrictEqual(LEG.status_text, {
    verified: "Verified through the kernel's three checks",
    medical: 'Verified for medical surveillance; awaiting verification for health and safety provisions',
    candidate: 'Candidate, awaiting verification',
    held: 'Held from citation while a Gazette detail is confirmed',
  });
  const html = fs.readFileSync(path.join(VERCEL, 'legislation.html'), 'utf8');
  assert.ok(!/triple verified/i.test(html + JSON.stringify(LEG)), 'nothing is called triple verified');
  const inst = JSON.parse(fs.readFileSync(path.join(ROOT, 'hsf', 'sample-file', 'instruments.json'), 'utf8')).instruments;
  const byShort = Object.fromEntries(inst.map((i) => [i.short_name, i]));
  for (const e of LEG.instruments) {
    const k = byShort[e.short_name];
    if (e.fallback.status === 'verified') assert.ok(k.status === 'verified' && ['safety', 'both'].includes(k.scope) && !k.held, e.slug + ' is shown as verified for health and safety without the kernel saying so');
    if (k.held) assert.strictEqual(e.fallback.status, 'held', e.slug + ' is held in the kernel');
  }
  if (!LEG.hsf7_closed) {
    for (const slug of ['noise-exposure-regulations-2024', 'physical-agents-regulations-2024']) {
      const e = LEG.instruments.find((x) => x.slug === slug);
      assert.ok(e && e.withheld && !/2024/.test(e.name), slug + ' is named on a static page while HSF-7 is open');
    }
  }
});

test('the File pages load the example and legislation links', () => {
  for (const page of ['health-and-safety-file.html', 'hsf-builder.html', 'hsf-sample.html']) {
    const html = fs.readFileSync(path.join(VERCEL, page), 'utf8');
    for (const src of ['/hsf/examples.js', '/hsf/legislation-index.js', '/js/cnc-hsf-links.js']) {
      assert.ok(html.includes('<script src="' + src + '"'), page + ' does not load ' + src);
    }
    assert.ok(/exampleHtml\(/.test(html), page + ' never shows its section examples');
  }
  const js = fs.readFileSync(path.join(VERCEL, 'js', 'cnc-hsf-links.js'), 'utf8');
  assert.ok(js.includes('See an example on Care Net letterhead'));
  assert.ok(js.includes("'data-cta', 'legislation_background:'"), 'instrument links carry data-cta');
  assert.ok(/data-cta="hsf_example_/.test(js), 'example links carry data-cta');
});

/* ---- The files themselves (review round of 24/09/2026). A minimal zip reader,
   so the DOCX parts are checked without any tool outside Node. */
const zlib = require('node:zlib');
function readZip(file) {
  const buf = fs.readFileSync(file);
  let eocd = buf.length - 22;
  while (eocd >= 0 && buf.readUInt32LE(eocd) !== 0x06054b50) eocd -= 1;
  assert.ok(eocd >= 0, file + ' is not a zip');
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const out = {};
  for (let i = 0; i < count; i += 1) {
    const method = buf.readUInt16LE(p + 10), size = buf.readUInt32LE(p + 20);
    const nameLen = buf.readUInt16LE(p + 28), extraLen = buf.readUInt16LE(p + 30), commentLen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString('utf8', p + 46, p + 46 + nameLen);
    const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
    const raw = buf.subarray(start, start + size);
    out[name] = (method === 8 ? zlib.inflateRawSync(raw) : raw).toString('utf8');
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

test('every example PDF is set in Arial (the letterhead standard), never a substitute', () => {
  for (const e of EXAMPLES) {
    const pdf = fs.readFileSync(path.join(VERCEL, e.pdf)).toString('latin1');
    const fonts = [...new Set((pdf.match(/\/BaseFont\s*\/[A-Za-z0-9+-]+/g) || []).map((f) => f.replace(/^\/BaseFont\s*\/([A-Z]{6}\+)?/, '')))];
    assert.ok(fonts.length, e.slug + ' embeds no font');
    for (const f of fonts) assert.match(f, /^Arial/, e.slug + ' embeds ' + f + ' (Arial was missing when the PDF was made)');
  }
});

test('every example DOCX follows the letterhead standard and is marked as an example on every page', () => {
  for (const e of EXAMPLES) {
    const z = readZip(path.join(VERCEL, e.docx));
    const doc = z['word/document.xml'];
    // The standard's two sections: the cover at top 2520, every later page at 1440.
    const margins = [...doc.matchAll(/<w:pgMar ([^>]+)\/>/g)].map((m) => m[1]);
    assert.strictEqual(margins.length, 2, e.slug + ' must have the two sections of the standard');
    assert.match(margins[0], /w:top="2520"/, e.slug + ' cover top margin');
    assert.match(margins[1], /w:top="1440"/, e.slug + ' later pages top margin');
    for (const m of margins) assert.match(m, /w:right="1440" w:bottom="2700" w:left="1440" w:header="425" w:footer="708"/, e.slug + ' margins');
    assert.ok(!doc.includes('w:titlePg'), e.slug + ' uses a title page switch instead of the two sections');
    const heads = Object.keys(z).filter((n) => /^word\/header\d+\.xml$/.test(n)).map((n) => z[n]);
    const feet = Object.keys(z).filter((n) => /^word\/footer\d+\.xml$/.test(n)).map((n) => z[n]);
    const imageHeads = heads.filter((h) => h.includes('<pic:pic'));
    assert.strictEqual(imageHeads.length, 1, e.slug + ' letterhead header image appears on the cover only');
    assert.match(imageHeads[0], /<wp:posOffset>-819150<\/wp:posOffset>[\s\S]*<wp:posOffset>114300<\/wp:posOffset>[\s\S]*<wp:wrapNone\/>/, e.slug + ' header image position and wrap');
    assert.ok(heads.some((h) => !h.includes('<pic:pic') && h.includes('EXAMPLE DOCUMENT')), e.slug + ' later pages carry the running EXAMPLE line');
    assert.ok(feet.length >= 1, e.slug + ' has no footer');
    for (const f of feet) {
      assert.ok(/<wp:wrapSquare wrapText="bothSides"[^>]*\/>/.test(f) && !f.includes('wrapNone'), e.slug + ' footer image must wrap square on both sides');
      assert.ok(f.includes('<wp:extent cx="7448550" cy="1590675"/>') && f.includes('<wp:posOffset>-885825</wp:posOffset>') && f.includes('<wp:posOffset>9039225</wp:posOffset>'), e.slug + ' footer image size and position');
      assert.ok(!/<w:t[ >]/.test(f), e.slug + ' nothing is typed in the footer');
    }
    const cover = doc.split('<w:sectPr')[0];
    assert.ok(cover.includes('EXAMPLE DOCUMENT.'), e.slug + ' cover carries the EXAMPLE notice');
    assert.ok(!/\(fictitious\) is a fictitious|\(fictitious\) is fictitious/.test(doc), e.slug + ' notice repeats "(fictitious)"');
    for (const f of new Set([...doc.matchAll(/w:ascii="([^"]+)"/g)].map((m) => m[1]))) assert.strictEqual(f, 'Arial', e.slug + ' uses ' + f);
  }
});

test('the File pages link instrument names everywhere they appear (12.7)', () => {
  const builder = fs.readFileSync(path.join(VERCEL, 'hsf-builder.html'), 'utf8');
  assert.match(builder, /\['sec-cards', 'lib-box', 'first-file', 'secs', 'panel-gaps', 'f-kv'\]\.forEach\(\(id\) => LINKS\.watch/, 'the builder links the gap report and the File header');
  const sample = fs.readFileSync(path.join(VERCEL, 'hsf-sample.html'), 'utf8');
  assert.ok(sample.includes("window.CNCHsfLinks.link($('file'))"), 'the sample links its header, matrices and gap report');
  const landing = fs.readFileSync(path.join(VERCEL, 'health-and-safety-file.html'), 'utf8');
  assert.ok(landing.includes("['inside', 'mco'].forEach") && landing.includes("window.CNCHsfLinks.link($('price-rows'))"), 'the landing page links the overview, the medicals section and the industry table');
  const leg = fs.readFileSync(path.join(VERCEL, 'legislation.html'), 'utf8');
  assert.ok(/u\.hash !== location\.hash\) return;[\s\S]*showTarget\(\);/.test(leg), 'a click on the entry already in the address still shows it');
});
