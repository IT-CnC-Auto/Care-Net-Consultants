'use strict';
// CNC HSF FORGE | the File's own words about the Medical Surveillance Plan
// (build contract section 15, separation review of 24/09/2026). node --test; no
// network. The generator is run with python3 against a copy of the fragments in
// a temporary folder, so nothing in the repository is written by these tests.
//
//   F1  The OMP signs the separate Medical Surveillance Plan, never the File or
//       one of its sections: no guidance, sample or File page text says the
//       OMP signs a File section off.
//   F2  Neither product depends on the other: no guidance says the Plan follows
//       from, or is built from, the File's own Section C risk assessment, nor
//       that only certificates of fitness go in the File (HSF-E-01 files the
//       signed Plan in Section E).
//   F4  The sample Files and the builder demonstration (which reads the
//       construction sample) never show the Plan as an element's legal basis:
//       HSF-E-01 shows no basis and no "In the framework" tag.
//   F5  No kernel rule code (RULE-...) or internal status word ("sandbox")
//       reaches a visitor through a sample File.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const GUIDE = path.join(ROOT, 'hsf', 'guidance');
const SAMPLES = path.join(ROOT, 'vercel', 'hsf', 'samples');
const FILE_PAGES = ['health-and-safety-file.html', 'hsf-builder.html', 'hsf-sample.html', 'hsf-staff.html', 'legislation.html'];
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

/* The same wording build_guidance.py, 056 step 3 and hsf_naming_checks.sql refuse. */
const OMP_SIGNOFF = /\bsigned off by (?:the |its |your )?(?:OMP|occupational medical practitioner)\b|\b(?:OMP|occupational medical practitioner)(?: only)? signs? off\b/i;
/* What the review found presenting the two products as one pipeline. */
const PLAN_PIPELINE = /follows from the exposures|built from the exposures|Only certificates of fitness \(the outcome\) go in the File|based on the exposures your risk assessment found/i;

function strings(o, p, out) {
  if (typeof o === 'string') out.push([p, o]);
  else if (o && typeof o === 'object') for (const k of Object.keys(o)) strings(o[k], p + '.' + k, out);
  return out;
}
function loadWindow(file, key) {
  const ctx = { window: {} };
  vm.runInNewContext(fs.readFileSync(file, 'utf8'), ctx, { filename: file, timeout: 5000 });
  return ctx.window[key];
}
function samples() {
  return fs.readdirSync(SAMPLES).filter((f) => f.endsWith('.js')).sort()
    .map((f) => ({ file: f, d: loadWindow(path.join(SAMPLES, f), '__HSF_SAMPLE') }));
}
const guidance = () => JSON.parse(read('hsf/guidance/guidance.json'));

test('F1: no guidance, sample or File page gives the OMP a sign off of the File', () => {
  const bad = [];
  for (const [p, t] of strings(guidance(), 'guidance.json', [])) if (OMP_SIGNOFF.test(t)) bad.push(p + ': ' + t);
  for (const [p, t] of strings(loadWindow(path.join(ROOT, 'vercel/hsf/guidance.js'), 'CNC_HSF_GUIDANCE'), 'guidance.js', [])) {
    if (OMP_SIGNOFF.test(t)) bad.push(p + ': ' + t);
  }
  for (const s of samples()) for (const [p, t] of strings(s.d, s.file, [])) if (OMP_SIGNOFF.test(t)) bad.push(p + ': ' + t);
  for (const rel of ['hsf/sample-file/render.mjs'].concat(FILE_PAGES.map((f) => 'vercel/' + f))) {
    const m = OMP_SIGNOFF.exec(read(rel));
    if (m) bad.push(rel + ': ' + m[0]);
  }
  assert.deepEqual(bad, []);
});

test('F1: the Section E intro says the OMP signs the Plan, filed as evidence, and not the File', () => {
  const intro = guidance().sections.E.intro;
  assert.match(intro, /the signed Medical Surveillance Plan, a separate Care Net product filed here as evidence\./);
  assert.match(intro, /The occupational medical practitioner \(OMP\) signs that Plan; the OMP does not sign your File\./);
  assert.doesNotMatch(intro, /signed off by/i);
});

test('F2: no guidance or sample says the Plan comes from the File\'s own risk assessment', () => {
  const bad = [];
  for (const [p, t] of strings(guidance(), 'guidance.json', [])) if (PLAN_PIPELINE.test(t)) bad.push(p + ': ' + t);
  for (const s of samples()) for (const [p, t] of strings(s.d, s.file, [])) if (PLAN_PIPELINE.test(t)) bad.push(p + ': ' + t);
  assert.deepEqual(bad, []);
  const g = guidance();
  const orderE = g.first_file.order.find((o) => o.section === 'E').reason;
  assert.match(orderE, /File the signed Medical Surveillance Plan, a separate Care Net product, and each person's certificate of fitness here/);
  assert.doesNotMatch(g.sections.E.first_file_tips[0], /Medical Surveillance Plan/);
  assert.match(g.sections.L.first_file_tips[3], /if you also hold a Medical Surveillance Plan, a separate Care Net product/);
});

test('F1: the generator refuses guidance that gives the OMP a sign off of the File', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hsf-wording-'));
  try {
    for (const f of fs.readdirSync(GUIDE)) {
      if (/^fragment-.*\.json$|^worklist\.json$/.test(f)) fs.copyFileSync(path.join(GUIDE, f), path.join(dir, f));
    }
    const p = path.join(dir, 'fragment-de.json');
    const d = JSON.parse(fs.readFileSync(p, 'utf8'));
    d.sections.E.intro += ' This section is signed off by the OMP only.';
    fs.writeFileSync(p, JSON.stringify(d, null, 1));
    const r = spawnSync('python3', [path.join(ROOT, 'hsf', 'build_guidance.py'), '--validate', '--dir', dir], { cwd: ROOT, encoding: 'utf8' });
    assert.equal(r.status, 2, 'the generator should refuse: ' + r.stdout + r.stderr);
    assert.match(r.stderr, /a File sign off by the OMP/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('F4 and F5: the samples (and so the builder demonstration) show no Plan basis, rule code or sandbox wording', () => {
  const all = samples();
  assert.equal(all.length, 17);
  for (const { file, d } of all) {
    for (const it of d.items) {
      assert.doesNotMatch(it.basis, /per the Plan|Medical Surveillance Plan/i, file + ' ' + it.code + ' shows the Plan as its legal basis');
      assert.doesNotMatch(it.basis, /\bRULE-/, file + ' ' + it.code + ' shows a kernel rule code');
      if (!it.basis) assert.equal(it.basis_state, 'none', file + ' ' + it.code + ' has no basis but a framework tag');
    }
    const e01 = d.items.find((i) => i.code === 'HSF-E-01');
    assert.ok(e01, file + ' carries HSF-E-01');
    assert.equal(e01.basis, '', file + ': HSF-E-01 has no instrument of its own, as the live element library shows');
    assert.equal(e01.basis_state, 'none');
    const text = JSON.stringify(d);
    assert.doesNotMatch(text, /\bRULE-[A-Z]/, file);
    assert.doesNotMatch(text, /sandbox/i, file);
    assert.doesNotMatch(d.kernel, /\bCNC\b|sandbox/i, file);
  }
});

test('F4: the sample page shows no basis line or framework tag for an item without a basis', () => {
  const html = read('vercel/hsf-sample.html');
  assert.match(html, /\(x\.basis && BS\[x\.basis_state\] \? '<div class="basis">'/);
  const bs = /var BS = (\{[\s\S]*?\});/.exec(html);
  assert.ok(bs, 'the tag table is found');
  assert.doesNotMatch(bs[1], /\bnone\s*:/, 'no tag is defined for an item without a basis');
});

test('F4 and F5: build_samples.py drops non instruments and refuses rule codes and sandbox wording', () => {
  const py = [
    'import sys',
    'sys.dont_write_bytecode = True  # leave no __pycache__ in hsf/',
    "sys.path.insert(0, 'hsf')",
    'import build_samples as bs',
    "assert bs.drop_non_instruments('Kernel instruments per the Plan') == ''",
    "assert bs.drop_non_instruments('RULE-RETAIN-*; HCA, HBA, Lead, Asbestos Regulations') == 'HCA, HBA, Lead, Asbestos Regulations'",
    "assert bs.drop_non_instruments('OHS Act, general duty; kernel release notes') == 'OHS Act, general duty; kernel release notes'",
    "for bad in ('RULE-RETAIN-*', 'sandbox until OMP and attorney review', 'Sandbox'):",
    '    try:',
    '        bs.assert_plain(bad)',
    "        raise AssertionError('not refused: ' + bad)",
    '    except SystemExit:',
    '        pass',
    "bs.assert_plain('Care Net OHS Industry Kernel as at 23/09/2026, still under review')",
    "print('ok')",
  ].join('\n');
  const r = spawnSync('python3', ['-c', py], { cwd: ROOT, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /ok/);
});
