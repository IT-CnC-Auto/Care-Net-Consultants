// CNC HSF FORGE | tests for the first File guidance and the recruitment call to
// action (build contract 12.1, 12.3, 12.4 and 12.5). node --test; no network.
// The generator is run with python3 against copies of the fragments in a
// temporary folder, so nothing in the repository is written by these tests.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const GUIDE = path.join(ROOT, 'hsf', 'guidance');
const GEN = path.join(ROOT, 'hsf', 'build_guidance.py');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

function runGen(args) {
  return spawnSync('python3', [GEN].concat(args), { cwd: ROOT, encoding: 'utf8' });
}

/* A copy of the fragments and the worklist that a test may change. */
function copyGuide() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hsf-guide-'));
  for (const f of fs.readdirSync(GUIDE)) {
    if (/^fragment-.*\.json$|^worklist\.json$/.test(f)) fs.copyFileSync(path.join(GUIDE, f), path.join(dir, f));
  }
  return dir;
}
function edit(dir, file, fn) {
  const p = path.join(dir, file);
  const d = JSON.parse(fs.readFileSync(p, 'utf8'));
  fn(d);
  fs.writeFileSync(p, JSON.stringify(d, null, 1));
}
function refusedWith(dir, re) {
  const r = runGen(['--validate', '--dir', dir]);
  fs.rmSync(dir, { recursive: true, force: true });
  assert.equal(r.status, 2, 'the generator should refuse: ' + r.stdout + r.stderr);
  assert.match(r.stderr, re);
}

function loadGuidance() {
  const ctx = { window: {} };
  vm.runInNewContext(read('vercel/hsf/guidance.js'), ctx);
  return ctx.window.CNC_HSF_GUIDANCE;
}

test('generator: the committed outputs are current and the build is deterministic', () => {
  const r = runGen(['--check']);
  assert.equal(r.status, 0, 'guidance.json, 055 or guidance.js is out of date: ' + r.stderr);
  const again = runGen(['--check']);
  assert.equal(again.status, 0);
});

test('generator: the real fragments validate with the worklist counts', () => {
  const r = runGen(['--validate', '--dir', GUIDE]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /sections 15, elements 256, appointments 41, classes 34/);
});

test('generator: refuses an unknown code', () => {
  const dir = copyGuide();
  edit(dir, 'fragment-ab.json', (d) => { d.elements['HSF-Z-99'] = d.elements['HSF-A-01']; });
  refusedWith(dir, /unknown element code HSF-Z-99/);
});

test('generator: refuses a missing code', () => {
  const dir = copyGuide();
  edit(dir, 'fragment-de.json', (d) => { delete d.classes['E06-10']; });
  refusedWith(dir, /missing class guidance .*E06-10/);
});

test('generator: refuses a code given twice', () => {
  const dir = copyGuide();
  edit(dir, 'fragment-c1.json', (d) => { d.appointments = { 'APP-00': { what_to_submit: ['a', 'b'], why: 'w', example: 'Example: x', common_gaps: [] } }; });
  refusedWith(dir, /APP-00 is already in another fragment/);
});

test('generator: refuses provision numbers other than section 16(2) and section 37(2)', () => {
  for (const bad of ['Keep it as regulation 3 requires.', 'Report it under section 24(1).', 'See Annexure 3.', 'Gazette No. 4123 applies.', 'The R638 hygiene rules.']) {
    const dir = copyGuide();
    edit(dir, 'fragment-fo.json', (d) => { const k = Object.keys(d.elements)[0]; d.elements[k].why = bad; });
    refusedWith(dir, /number pattern/);
  }
});

test('generator: allows section 16(2), section 37(2), dates, counts and rand amounts', () => {
  const dir = copyGuide();
  edit(dir, 'fragment-fo.json', (d) => {
    const k = Object.keys(d.elements)[0];
    d.elements[k].why = 'Your section 16(2) assignee signs it and the section 37(2) agreement covers contractors.';
    d.elements[k].example = 'Example: dated 14 May 2026, for 25 staff, at a cost of R4 250,00.';
  });
  const r = runGen(['--validate', '--dir', dir]);
  fs.rmSync(dir, { recursive: true, force: true });
  assert.equal(r.status, 0, r.stderr);
});

test('generator: refuses a broken shape and house rule breaches', () => {
  let dir = copyGuide();
  edit(dir, 'fragment-ab.json', (d) => { d.elements['HSF-A-01'].what_to_submit = ['only one']; });
  refusedWith(dir, /what_to_submit: expected a list of 2 to 5/);
  dir = copyGuide();
  edit(dir, 'fragment-ab.json', (d) => { d.elements['HSF-A-01'].suggested_department = 'XX'; });
  refusedWith(dir, /unknown department/);
  dir = copyGuide();
  edit(dir, 'fragment-ab.json', (d) => { d.appointments['APP-00'].suggested_department = 'SHE'; });
  refusedWith(dir, /unknown field suggested_department/);
  dir = copyGuide();
  edit(dir, 'fragment-ab.json', (d) => { d.elements['HSF-A-01'].example = 'Dube Engineering files it.'; });
  refusedWith(dir, /marked as an example/);
  dir = copyGuide();
  edit(dir, 'fragment-ab.json', (d) => { d.elements['HSF-A-01'].why = 'This keeps you compliant.'; });
  refusedWith(dir, /compliant/);
});

test('guidance.js: window.CNC_HSF_GUIDANCE carries every code and the first File order', () => {
  const g = loadGuidance();
  const w = JSON.parse(read('hsf/guidance/worklist.json'));
  assert.equal(g.meta.version, 'HSF-GUIDE-1.0');
  assert.equal(g.meta.status, 'draft');
  assert.equal(g.meta.reviewed_by, null);
  for (const [kind, n] of [['sections', 15], ['elements', 256], ['appointments', 41], ['classes', 34]]) {
    assert.equal(Object.keys(g[kind]).length, n, kind);
    assert.deepEqual(Object.keys(g[kind]), w[kind].map((x) => x.code), kind + ' in worklist order');
  }
  assert.deepEqual(JSON.parse(JSON.stringify(g.first_file.order.map((o) => o.section))).sort(), 'ABCDEFGHIJKLMNO'.split(''));
  assert.deepEqual(JSON.parse(read('hsf/guidance/guidance.json')), JSON.parse(JSON.stringify(g)));
});

test('migration 055: generated, never hand edited, with the tables, RLS and the public view', () => {
  const sql = read('supabase/migrations/055_hsf_guidance.sql');
  assert.match(sql, /GENERATED by hsf\/build_guidance\.py/);
  for (const t of ['hsf_section_guidance', 'hsf_element_guidance', 'hsf_appointment_guidance', 'hsf_class_guidance', 'hsf_guidance_meta']) {
    assert.match(sql, new RegExp('create table ' + t + ' \\('));
  }
  assert.match(sql, /grant select on %I to anon, authenticated/);
  assert.match(sql, /create or replace view hsf_public_guidance with \(security_invoker = true\)/);
});

test('samples: every sample item carries its guidance', () => {
  const dir = path.join(ROOT, 'vercel', 'hsf', 'samples');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.js'));
  assert.equal(files.length, 17);
  for (const f of files) {
    const ctx = { window: {} };
    vm.runInNewContext(fs.readFileSync(path.join(dir, f), 'utf8'), ctx);
    const d = ctx.window.__HSF_SAMPLE;
    assert.ok(d.guidance && d.guidance.version === 'HSF-GUIDE-1.0', f);
    for (const it of d.items) {
      assert.match(it.guide, /^[eac]:/, f + ' ' + it.code);
      const [k, ref] = [it.guide[0], it.guide.slice(2)];
      const g = d.guidance[k][ref];
      assert.ok(g && g.what_to_submit.length >= 2 && g.why && /^Example/.test(g.example), f + ' ' + it.code);
    }
    const appt = d.items.find((i) => /^HSF-B-06\.\d\d$/.test(i.code));
    assert.match(appt.guide, /^a:APP-\d\d$/, f + ' appointment items show appointment guidance');
  }
});

const RECRUIT_LINE = 'Need a SACPCMP or SAIOSH registered practitioner to sign your File, or a competent person for an appointment?';
const FALLBACK = 'Ask a sales executive about onboarding a registered Health and Safety practitioner';

test('config: recruitmentPortalUrl is null and marked pending', () => {
  const ctx = { window: {} };
  vm.runInNewContext(read('vercel/js/cnc-config.js'), ctx);
  const c = ctx.window.CNC_CONFIG;
  assert.equal(c.recruitmentPortalUrl, null);
  assert.equal(c.pending.recruitmentPortalUrl, true);
  const ctx2 = { window: { CNC_CONFIG_OVERRIDES: { recruitmentPortalUrl: 'https://portal.example.invalid/' } } };
  vm.runInNewContext(read('vercel/js/cnc-config.js'), ctx2);
  assert.equal(ctx2.window.CNC_CONFIG.recruitmentPortalUrl, 'https://portal.example.invalid/');
  assert.equal(ctx2.window.CNC_CONFIG.pending.recruitmentPortalUrl, false);
});

test('builder: loads the guidance and carries the panel, disclosures, preselect and call to action', () => {
  const h = read('vercel/hsf-builder.html');
  assert.match(h, /<script src="\/hsf\/guidance\.js" defer><\/script>\s*<script type="module">/);
  assert.ok(h.includes('First File? Start here'));
  assert.ok(h.includes('What goes in this section'));
  assert.ok(h.includes('What to submit, why, and an example'));
  assert.ok(h.includes('does not replace the advice of your health and safety practitioner'));
  assert.match(h, /is being reviewed by Care Net(\u2019|\\u2019)s Health and Safety Manager/);
  assert.match(h, /const dept = deptChoice\[c\] \|\| sectionDept\(c\);/);
  assert.ok(h.includes('data-cta="recruitment_onboard_hs_practitioner"'));
  assert.ok(h.includes(RECRUIT_LINE));
  assert.ok(h.includes(FALLBACK));
  assert.ok(h.includes("'Onboard a registered Health and Safety practitioner'"));
  assert.match(h, /searchParams\.set\('source', 'hsf'\)/);
  assert.match(h, /recruitHtml\('signatory'\)/);
  assert.match(h, /c === 'B' \? recruitHtml\('appointment'\)/);
  assert.match(h, /st === 'outstanding' && isAppointmentItem\(it\) \? recruitHtml\('appointment'\)/);
});

test('other pages: the recruitment call to action with the WhatsApp fallback', () => {
  for (const p of ['vercel/health-and-safety-file.html', 'vercel/hsf-sample.html']) {
    const h = read(p);
    assert.match(h, /<a class="btn ghost" href="https:\/\/wa\.me\/27600702723" target="_blank" rel="noopener" data-cta="recruitment_onboard_hs_practitioner">Ask a sales executive about onboarding a registered Health and Safety practitioner<\/a>/, p);
    assert.ok(h.includes('Need a SACPCMP or SAIOSH registered practitioner to sign your File'), p);
    assert.ok(h.includes('recruitmentPortalUrl'), p);
  }
  const staff = read('vercel/hsf-staff.html');
  assert.ok(staff.includes('Find a practitioner in the Recruitment Portal'));
  assert.ok(staff.includes('data-cta="recruitment_onboard_hs_practitioner"'));
  const sample = read('vercel/hsf-sample.html');
  assert.ok(sample.includes('What to submit, why, and an example'));
});

test('pages: no invented recruitment portal address', () => {
  for (const p of ['vercel/hsf-builder.html', 'vercel/hsf-sample.html', 'vercel/health-and-safety-file.html', 'vercel/hsf-staff.html', 'vercel/js/cnc-config.js']) {
    const h = read(p);
    assert.doesNotMatch(h, /https?:\/\/[^"'\s]*recruit/i, p);
    assert.doesNotMatch(h, /https?:\/\/[^"'\s]*be-?matched/i, p);
  }
});
