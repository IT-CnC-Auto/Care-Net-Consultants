// CNC HSF FORGE | HSF-SAMPLE-DOC-01 v1.0.0 | Sample Health and Safety File pages.
//
// Renders the sample Health and Safety File for one industry as A4 page images,
// in the same visual family as the sample Medical Surveillance Plans (cover on
// the Care Net textured cover, SAMPLE band, Care Net and SAMPLE watermarks,
// page footer), but as a File, never as a Plan: its own title, the fifteen File
// sections, the compliance register, the training and medical matrix, the gap
// report, the legal register and the File sign off.
//
// Data: vercel/hsf/samples/<slug>.js (fictitious company, built by
// hsf/build_samples.py from the element library and the Cognitive Kernel role
// data) and, when present, hsf/guidance/guidance.json for the section intros.
//
// Usage: node hsf/sample-file/render.mjs <slug> [--out vercel/hsf/samples/pages]
// Needs Playwright with Chromium (chromium.launch() with no options) and Python
// Pillow for the WebP conversion. Writes <out>/<slug>.js with
// window.__HSF_SAMPLE_PAGES = {slug, industry, pages: [data URIs]} and, for
// review, PNG pages in the system temporary folder under hsf-sample-file/<slug>/.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import os from 'node:os';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const HERE = path.dirname(new URL(import.meta.url).pathname);
const ROOT = path.resolve(HERE, '..', '..');
const slug = process.argv[2];
if (!slug) { console.error('usage: node hsf/sample-file/render.mjs <slug> [--out dir]'); process.exit(2); }
const outArg = process.argv.indexOf('--out');
const OUT = path.resolve(ROOT, outArg > 0 ? process.argv[outArg + 1] : 'vercel/hsf/samples/pages');

function loadSample(s) {
  const ctx = { window: {} };
  vm.runInNewContext(fs.readFileSync(path.join(ROOT, 'vercel/hsf/samples', s + '.js'), 'utf8'), ctx);
  if (!ctx.window.__HSF_SAMPLE) throw new Error('sample ' + s + ' has no data');
  return ctx.window.__HSF_SAMPLE;
}
function loadGuidance() {
  const p = path.join(ROOT, 'hsf/guidance/guidance.json');
  return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8')) : null;
}
const d = loadSample(slug);
const guide = loadGuidance();
const worklist = JSON.parse(fs.readFileSync(path.join(ROOT, 'hsf/guidance/worklist.json'), 'utf8'));
const sectionInfo = Object.fromEntries(worklist.sections.map((s) => [s.code, s]));

const tidy = (v) => String(v == null ? '' : v).replace(/\s*\(cross reference [^)]*\)/gi, '').replace(/\s*\(see HSF-[^)]*\)/gi, '');
const esc0 = (v) => String(v == null ? '' : v).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const esc = (v) => esc0(tidy(v));
const pct = (n) => (Math.round(n * 10) / 10).toFixed(1).replace('.', ',') + '%';
const STATUS = {
  uploaded: ['Evidence on file', 'ok'],
  linked_mco: ['Linked from MyClinicOnline', 'ok'],
  outstanding: ['Outstanding', 'bad'],
  expired: ['Expired', 'bad'],
  not_applicable: ['Not applicable', 'na'],
};
const REVIEW = { annual: 'Every year', on_change: 'On change', per_event: 'Per event', per_project: 'Per project', monthly: 'Monthly', daily: 'Daily', before_use: 'Before use', on_expiry: 'On expiry', statutory: 'As the instrument sets', 'on change': 'On change', 'per event': 'Per event', 'per project': 'Per project', 'before use': 'Before use', 'on expiry': 'On expiry' };
const EVIDENCE = { document: 'Document', register: 'Register', certificate: 'Certificate', appointment: 'Appointment', plan: 'Plan', report: 'Report', permit: 'Permit', minutes: 'Minutes', training_record: 'Training record', medical_certificate: 'Certificate of fitness', licence: 'Licence', agreement: 'Agreement', log: 'Log' };

// Internal kernel references never reach a client document.
function cleanBasis(b) {
  return String(b || '')
    .split(';').map((x) => x.trim())
    .filter((x) => x && !/^RULE-|kernel (release notes|role library)/i.test(x))
    .join('; ')
    .replace(/^Candidate:\s*/i, 'Candidate, being verified: ');
}

// ---- Blocks: the document as a flow of blocks the paginator places on pages ----
const B = [];
const h1 = (t) => B.push({ k: 'h1', html: esc(t) });
const h2 = (t) => B.push({ k: 'h2', html: esc(t) });
const h3 = (t) => B.push({ k: 'h3', html: esc(t) });
const p = (html) => B.push({ k: 'p', html });
const note = (html) => B.push({ k: 'note', html });
const table = (cols, widths, rows, opts = {}) => B.push({ k: 'table', cols, widths, rows, cls: opts.cls || '' });
const pagebreak = () => B.push({ k: 'break' });

const ov = d.overall;
const company = d.company;
// Sign off by industry (hsf/SIGNOFF-CRITERIA.md section 5; migration 053 rule table).
const MINING = d.code === 'MINING' || /Mine Health and Safety/i.test(d.regime);
const RULE = d.code === 'CONSTR'
  ? { who: 'A Health and Safety practitioner registered with SACPCMP as a construction health and safety agent, manager or officer (candidate categories cannot sign alone)', cover: 'Registered Health and Safety practitioner (SACPCMP): xxxx | Registration number xxxxx', status: 'Unsigned sample. A released File is signed by a SACPCMP registered construction Health and Safety practitioner and accepted by the company\'s section 16(2) appointee.' }
  : MINING
    ? { who: 'A registered Health and Safety practitioner (SACPCMP, or SAIOSH CMSAIOSH, GradSAIOSH or TechSAIOSH) as a practitioner review. Under the Mine Health and Safety Act the employer and the managers it appoints carry the duties, so this File is never presented as a sign off under that Act', cover: 'Practitioner review: registered Health and Safety practitioner xxxx | Registration number xxxxx', status: 'Unsigned sample. A released File carries a practitioner review and is accepted by the mine\'s appointed manager; it is not a sign off under the Mine Health and Safety Act.' }
    : { who: 'A registered Health and Safety practitioner: SACPCMP registered as a construction health and safety agent or manager, or SAIOSH designated as CMSAIOSH, GradSAIOSH or TechSAIOSH (training certificates alone are not enough)', cover: 'Registered Health and Safety practitioner (SACPCMP or SAIOSH): xxxx | Registration number xxxxx', status: 'Unsigned sample. A released File is signed by a registered Health and Safety practitioner and accepted by the company\'s section 16(2) appointee.' };
const ACCEPT = MINING ? ['Employer acceptance', 'The manager the employer appointed for the mine, in writing'] : ['Client acceptance', 'The company\'s section 16(2) appointee, in writing'];
h1('Health and Safety File');
B.push({ k: 'sub', html: esc(d.industry) });
p('This is a demonstration document. It shows the structure, depth and legal referencing of the Health and Safety File a Care Net client builds. <b>' + esc(company) + '</b> is a fictitious company; every name, date, figure and document in this sample is made up. It carries no authority, is deliberately unsigned and is watermarked throughout.');
table(['', ''], [30, 70], [
  ['Document', 'Sample Health and Safety File'],
  ['Industry', esc(d.industry)],
  ['Company', esc(company)],
  ['Scope of the File', esc(d.scope)],
  ['Sites and people', d.sites + (d.sites === 1 ? ' site' : ' sites') + ', ' + d.headcount + ' employees'],
  ['Regime', esc(d.regime)],
  ['Reference and revision', esc(d.reference) + ', revision ' + d.revision + ', as at ' + esc(d.as_at)],
  ['Prepared with', 'Care Net Consultants (Pty) Ltd, from the Care Net Cognitive Kernel element library'],
  ['Sign off status', esc(RULE.status)],
  ['Compensation route', MINING ? 'COIDA for injuries and diseases generally; ODMWA for the occupational lung diseases of mine workers' : 'COIDA'],
  ['Review cycle', 'The File is a living record: items are reviewed at the interval each one sets, and the File is revised whenever work, sites or people change.'],
], { cls: 'kv' });

h2('1. Introduction and purpose of this File');
p('This Health and Safety File has been compiled for <b>' + esc(company) + '</b>. It brings together, in one place, the documents that show how the company meets its health and safety duties: its legal registration, its policy and appointments, its risk assessments, training, registers and inspections, permits, emergency arrangements, incident records and its audit and review cycle.');
if (MINING) p('This company is a mine, so the Mine Health and Safety Act is the governing regime: the employer and the managers it appoints carry the duties, and the mine\'s own codes of practice apply. This File organises the evidence of those duties in the same fifteen sections, as a practitioner review.');
p('A Health and Safety File is not a Medical Surveillance Plan. The Medical Surveillance Plan is a separate Care Net document, recommended on and signed by an Occupational Medical Practitioner; this File holds only its evidence (the signed Plan and the fitness outcomes), never clinical records.');

h2('2. Company and scope');
p('<b>' + esc(company) + '</b> works in ' + esc(d.industry.toLowerCase()) + '. The File covers: ' + esc(d.scope) + '. It applies to ' + d.headcount + ' employees across ' + d.sites + (d.sites === 1 ? ' site' : ' sites') + ', and to every contractor working under the company\'s control.');
const acts = d.triggers.map((t) => (worklist.triggers.find((x) => x.code === t) || {}).description || '')
  .map((t) => t.replace(/\s*\([^)]*\)/g, '').trim()).filter(Boolean)
  .map((t, i) => (i === 0 ? t : t.charAt(0).toLowerCase() + t.slice(1)));
p('The activities recorded at intake switch on the File items that apply. For this company they include: ' + esc(acts.join('; ')) + '.');

pagebreak();
h2('3. How this File is organised');
p('The File has fifteen sections. Each item names the duty in plain words, the person who owns it, the evidence that proves it and how often it is reviewed. The percentage is the share of applicable items with current evidence on file.');
table(['Section', 'What it holds', 'Items', 'Applicable', 'Evidenced'], [30, 43, 9, 9, 9],
  d.sections.map((s) => [
    '<b>' + esc(s.code) + '</b> ' + esc(s.name),
    esc((guide && guide.sections && guide.sections[s.code] && guide.sections[s.code].intro) || (sectionInfo[s.code] || {}).description || ''),
    String(s.items), String(s.applicable), pct(s.pct),
  ]), { cls: 'compact' });

h2('4. Where the File stands');
p('Of <b>' + ov.applicable + '</b> applicable items, <b>' + ov.compliant + '</b> have current evidence on file (' + pct(ov.pct) + '). ' + ov.counts.outstanding + ' are outstanding, ' + ov.counts.expired + ' have expired and need renewal, and ' + ov.counts.not_applicable + ' do not apply to this company\'s current work. ' + ov.counts.linked_mco + ' items are linked from MyClinicOnline, where training and fitness records are kept.');
table(['Status', 'Items', 'What it means'], [26, 10, 64], [
  ['Evidence on file', String(ov.counts.uploaded), 'A current document is filed against the item.'],
  ['Linked from MyClinicOnline', String(ov.counts.linked_mco), 'Training or fitness outcomes held in MyClinicOnline; only the outcome shows here.'],
  ['Outstanding', String(ov.counts.outstanding), 'No evidence yet. Listed in the gap report with an owner and a date.'],
  ['Expired', String(ov.counts.expired), 'Evidence was filed but has passed its review or expiry date.'],
  ['Not applicable', String(ov.counts.not_applicable), 'The activity is not carried on now, with the reason recorded.'],
]);

pagebreak();
h2('5. The File, section by section');
p('Every item in the File, with its owner, the evidence type, its review interval and where it stands. Dates are fictitious.');
for (const s of d.sections) {
  const items = d.items.filter((i) => i.section === s.code);
  h3('Section ' + s.code + ': ' + s.name + ' (' + pct(s.pct) + ')');
  table(['Item', 'Owner', 'Evidence', 'Review', 'Status'], [44, 17, 13, 11, 15], items.map((i) => {
    const st = STATUS[i.status] || [i.status, ''];
    const isDate = /^\d{2}\/\d{2}\/\d{4}$/.test(i.to || '');
    const when = !isDate ? '' : i.status === 'uploaded' || i.status === 'linked_mco' ? (i.to ? 'Next ' + i.to : '') : i.status === 'expired' ? (i.to ? 'Expired ' + i.to : '') : i.status === 'outstanding' ? (i.to ? 'Due ' + i.to : '') : '';
    return [esc(i.name) + (i.status === 'not_applicable' && i.reason ? '<br><i class="muted">' + esc(i.reason) + '</i>' : ''),
      esc(i.responsible), esc(EVIDENCE[i.evidence] || i.evidence), esc(REVIEW[i.review] || i.review),
      '<span class="st ' + st[1] + '">' + esc(st[0]) + '</span>' + (when ? '<br><span class="muted">' + esc(when) + '</span>' : '')];
  }), { cls: 'reg' });
}

pagebreak();
h2('6. Training and medical fitness matrix');
p('Who holds which training and fitness outcome, and until when. Fitness outcomes come from MyClinicOnline and show only fit, fit with restrictions or unfit, never clinical detail.');
const cols = d.matrix.columns;
const SYM = { ok: 'Current', expired: 'Expired', due: 'Due', missing: 'Missing', na: '' };
table(['Person and role'].concat(cols.map((c) => c.name)), [22].concat(cols.map(() => 78 / cols.length)),
  d.matrix.people.map((pp) => ['<b>' + esc(pp.name) + '</b><br><span class="muted">' + esc(pp.role) + '</span>'].concat(cols.map((c) => {
    const cell = pp.cells[c.id] || { s: 'na' };
    if (cell.s === 'na') return '<span class="muted">n/a</span>';
    return '<span class="st ' + (cell.s === 'ok' ? 'ok' : 'bad') + '">' + esc(SYM[cell.s] || cell.s) + '</span>' + (cell.d ? '<br><span class="muted">' + esc(cell.d) + '</span>' : '');
  }))), { cls: 'matrix' });

h2('7. Medical surveillance evidence');
p('Section E of the File holds the evidence of the company\'s medical surveillance: the Medical Surveillance Plan signed by the Occupational Medical Practitioner, and each employee\'s certificate of fitness outcome. The Plan itself is a separate Care Net document. Clinical records stay with the occupational health practitioner and are never filed here. Care Net screens fitness and does not diagnose; the employer pays for occupational health services.');

pagebreak();
h2('8. Gap report and action plan');
const gaps = d.items.filter((i) => i.status === 'outstanding' || i.status === 'expired')
  .sort((a, b) => (a.to || '99').split('/').reverse().join('').localeCompare((b.to || '99').split('/').reverse().join('')));
p('The ' + gaps.length + ' items that need action, oldest date first. Each has an owner; the File is revised as evidence is filed.');
table(['Section', 'Item', 'Owner', 'Status', 'By'], [9, 49, 18, 12, 12], gaps.map((i) => {
  const st = STATUS[i.status];
  return [esc(i.section), esc(i.name), esc(i.responsible), '<span class="st bad">' + esc(st[0]) + '</span>', esc(i.to || '')];
}), { cls: 'compact' });

pagebreak();
h2('9. Legal register');
p('The instruments this File draws on, as recorded in the Care Net Cognitive Kernel. A File cites an instrument only once the kernel has verified it three ways for health and safety provisions: against its primary text, independently corroborated, and confirmed in force. Until then the duty is described in plain words and the instrument shows its status as the kernel records it today.');
const kernel = JSON.parse(fs.readFileSync(path.join(HERE, 'instruments.json'), 'utf8'));
const kInst = Object.fromEntries(kernel.instruments.map((x) => [x.short_name, x]));
const DISPLAY = { 'EEA section 7': 'Employment Equity Act, medical testing provision', 'Food Premises Hygiene Regulations, R638 of 2018': 'Food Premises Hygiene Regulations, 2018' };
const uses = new Map();
// Count File items per instrument. An expanded appointment item draws on its
// own appointment type's instrument, not on every instrument its parent names.
for (const i of d.items) {
  let names;
  const appt = /^Appointment:\s*(.+)$/.exec(i.name);
  if (/\.\d+$/.test(i.code) && appt && kernel.by_appointment && kernel.by_appointment[appt[1]]) names = [kernel.by_appointment[appt[1]]];
  else names = kernel.by_element[i.code.replace(/\.\d+$/, '')] || [];
  for (const n of new Set(names)) uses.set(n, (uses.get(n) || 0) + 1);
}
function kstatus(x) {
  if (x.held) return 'Held from citation while a Gazette detail is confirmed';
  if (x.status === 'verified' && x.scope === 'medical') return 'Verified for medical surveillance; awaiting verification for health and safety provisions';
  if (x.status === 'verified') return 'Verified';
  return 'Candidate, awaiting verification';
}
table(['Instrument', 'Items', 'Status in the Care Net Cognitive Kernel'], [44, 9, 47],
  [...uses.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([n, c]) => [esc(DISPLAY[n] || n), String(c), esc(kstatus(kInst[n] || { status: 'pending' }))]), { cls: 'compact' });

pagebreak();
h2('10. Sign off');
p('A released File carries these sign offs. This sample is deliberately unsigned.');
table(['Sign off', 'Who', 'Required for release'], [30, 50, 20], [
  [MINING ? 'Practitioner review' : 'Safety content', esc(RULE.who) + ', with a register check no older than 30 days before signing and an appointment letter and engagement letter on record', 'Yes'],
  [ACCEPT[0], esc(ACCEPT[1]), 'Yes'],
  ['Chief executive acknowledgement', 'The company\'s chief executive', 'Recorded'],
  ['Medical surveillance', 'Not a File sign off. The Occupational Medical Practitioner signs the separate Medical Surveillance Plan, which is filed in Section E as evidence', 'No'],
]);
B.push({ k: 'sign', html: [
  ['Registered Health and Safety practitioner', 'Name, body, category and registration number'],
  [(MINING ? 'Appointed manager, ' : 'Section 16(2) appointee, ') + esc(company), 'Name and designation'],
  ['Chief executive, ' + esc(company), 'Name'],
].map(([a, b]) => '<div class="sig"><div class="line"></div><b>' + a + '</b><span>' + b + '</span><span>Date</span></div>').join('') });
note('Not legal advice. The File records how the company manages its duties; the company, its chief executive and its appointees remain responsible for them.');

// ---- HTML shell ----------------------------------------------------------------
const fontsDir = path.join(ROOT, 'vercel/fonts');
const f64 = (n) => fs.readFileSync(path.join(fontsDir, n)).toString('base64');
const cover64 = fs.readFileSync(path.join(HERE, 'assets/cover-base.png')).toString('base64');
const CSS = `
@font-face{font-family:'Bebas Neue';src:url(data:font/woff2;base64,${f64('BebasNeue.woff2')}) format('woff2')}
@font-face{font-family:'Inter';font-weight:400 700;src:url(data:font/woff2;base64,${f64('Inter-var.woff2')}) format('woff2')}
@font-face{font-family:'Montserrat';font-weight:600 800;src:url(data:font/woff2;base64,${f64('Montserrat-var.woff2')}) format('woff2')}
*{box-sizing:border-box} body{margin:0;background:#888}
.page{width:794px;height:1123px;background:#fff;position:relative;overflow:hidden;margin:0 0 20px;font-family:Inter,Arial,sans-serif;color:#1E1E1E}
.cover{background:url(data:image/png;base64,${cover64}) center/100% 100% no-repeat}
.cover .t1{position:absolute;top:296px;left:0;right:0;text-align:center;font-family:'Bebas Neue',Arial;font-size:38px;letter-spacing:.5px}
.cover .t2{position:absolute;top:350px;left:0;right:0;text-align:center;font-family:'Bebas Neue',Arial;font-size:24px}
.cover .t3{position:absolute;top:392px;left:0;right:0;text-align:center;font-family:Montserrat,Arial;font-weight:700;font-size:16px;color:#ED1B24}
.cover .t4{position:absolute;top:448px;left:120px;right:120px;text-align:center;font-size:12.5px;color:#444;line-height:1.5}
.cover .t5{position:absolute;top:846px;left:0;right:0;text-align:center;font-family:Montserrat,Arial;font-size:11px;letter-spacing:.6px;color:#333;line-height:1.5}
.band{position:absolute;top:0;left:52px;right:52px;height:36px;border-bottom:1.5px solid #ED1B24;display:flex;justify-content:space-between;align-items:flex-end;padding-bottom:6px;font-size:9.5px;color:#666}
.band b{color:#ED1B24;letter-spacing:2px;font-size:10px}
.foot{position:absolute;bottom:0;left:52px;right:52px;height:38px;border-top:1px solid #ddd;display:flex;justify-content:space-between;align-items:center;font-size:9px;color:#444}
.wm{position:absolute;inset:0;pointer-events:none;overflow:hidden;z-index:0}
.wm .a{position:absolute;left:-60px;top:420px;transform:rotate(-38deg);font:800 96px Montserrat,Arial;color:rgba(160,150,150,.29);white-space:nowrap}
.wm .b{position:absolute;inset:-200px;display:grid;grid-template-columns:repeat(4,1fr);gap:120px 60px;transform:rotate(-30deg);font:800 38px Montserrat,Arial;letter-spacing:10px;color:rgba(180,170,170,.14)}
.body{position:absolute;top:58px;left:52px;right:52px;bottom:52px;z-index:1}
h1{font:400 40px 'Bebas Neue',Arial;margin:6px 0 4px}
.sub{font:700 12.5px Montserrat,Arial;margin:0 0 10px}
h2{font:400 21px 'Bebas Neue',Arial;letter-spacing:.3px;margin:16px 0 8px;padding-bottom:5px;border-bottom:2px solid #ED1B24}
h3{font:700 11.5px Montserrat,Arial;text-transform:uppercase;letter-spacing:.4px;margin:12px 0 6px}
p{font-size:11.2px;line-height:1.62;margin:0 0 8px}
.note{font-size:10px;color:#555;border-left:3px solid #ED1B24;padding:6px 10px;background:rgba(247,245,245,.85);margin:10px 0}
table{width:100%;border-collapse:collapse;margin:0 0 10px;font-size:10.2px;line-height:1.4;background:rgba(255,255,255,.72)}
th{background:#1A1A1A;color:#fff;text-align:left;font:700 9.8px Montserrat,Arial;padding:6px 7px}
td{border:1px solid #ddd;padding:5px 7px;vertical-align:top}
table.kv td:first-child{font-weight:700;background:rgba(247,245,245,.8)} table.kv th{display:none}
table.compact{font-size:9.6px} table.reg{font-size:9.3px} table.matrix{font-size:8.3px} table.matrix th{font-size:8.2px;padding:5px 4px} table.matrix td{padding:4px}
.st{font-weight:700} .st.ok{color:#1B6E45} .st.bad{color:#C5141B} .st.na{color:#777}
.muted{color:#777;font-style:normal}
.sig{display:inline-block;width:30%;margin:26px 3% 0 0;font-size:10px;vertical-align:top} .sig .line{border-bottom:1px solid #1E1E1E;height:34px;margin-bottom:5px} .sig b,.sig span{display:block;margin-top:2px} .sig span{color:#666}
`;

function pageShell(inner, n) {
  return '<div class="page" data-n="' + n + '"><div class="wm"><div class="b">' + '<span>SAMPLE</span>'.repeat(40) + '</div><div class="a">Care Net Consultants</div></div>'
    + '<div class="band"><b>SAMPLE, NOT FOR USE</b><span>Demonstration document. Fictitious company. Not a released File.</span></div>'
    + '<div class="body">' + inner + '</div>'
    + '<div class="foot"><span>Sample Health and Safety File, prepared by Care Net Consultants (Pty) Ltd. Your Partner in Workplace Health.</span><span class="pn"></span></div></div>';
}

const coverHtml = '<div class="page cover" data-n="0"><div class="t1">' + esc(d.industry) + '</div><div class="t2">Sample Health and Safety File</div><div class="t3">Health and Safety File</div>'
  + '<div class="t4">' + esc(company) + '<br>' + esc(d.scope) + '</div>'
  + '<div class="t5">Compiled by Care Net Consultants (Pty) Ltd<br>' + esc(RULE.cover) + '</div></div>';

const html = '<!doctype html><html><head><meta charset="utf-8"><style>' + CSS + '</style></head><body>' + coverHtml + '<div id="flow"></div>'
  + '<script>window.BLOCKS=' + JSON.stringify(B).replace(/</g, '\\u003c') + ';window.SHELL=' + JSON.stringify(pageShell('', 'N')).replace(/</g, '\\u003c') + ';</script></body></html>';

// Working files (the HTML and the PNG pages for review) stay outside the site.
const tmp = path.join(os.tmpdir(), 'hsf-sample-file', slug);
fs.mkdirSync(tmp, { recursive: true });
fs.writeFileSync(path.join(tmp, 'doc.html'), html);

const browser = await chromium.launch();
const pg = await browser.newPage({ viewport: { width: 794, height: 1123 }, deviceScaleFactor: 1.2 });
await pg.goto('file://' + path.join(tmp, 'doc.html'));
await pg.evaluate(() => document.fonts.ready);
const total = await pg.evaluate(() => {
  const flow = document.getElementById('flow');
  let page, body;
  function newPage() {
    const w = document.createElement('div'); w.innerHTML = window.SHELL; page = w.firstChild; flow.appendChild(page); body = page.querySelector('.body');
  }
  const fits = () => body.scrollHeight <= body.clientHeight + 1;
  function tag(b) {
    if (b.k === 'h1') return '<h1>' + b.html + '</h1>';
    if (b.k === 'sub') return '<div class="sub">' + b.html + '</div>';
    if (b.k === 'h2') return '<h2>' + b.html + '</h2>';
    if (b.k === 'h3') return '<h3>' + b.html + '</h3>';
    if (b.k === 'note') return '<div class="note">' + b.html + '</div>';
    if (b.k === 'sign') return '<div>' + b.html + '</div>';
    return '<p>' + b.html + '</p>';
  }
  newPage();
  const blocks = window.BLOCKS;
  for (let bi = 0; bi < blocks.length; bi++) {
    const b = blocks[bi];
    if (b.k === 'break') { if (body.children.length) newPage(); continue; }
    if (b.k !== 'table') {
      const w = document.createElement('div'); w.innerHTML = tag(b); const el = w.firstChild; body.appendChild(el);
      // keep headings with what follows: move a heading that ends a page
      if (!fits()) { body.removeChild(el); newPage(); body.appendChild(el); }
      continue;
    }
    const mk = () => {
      const t = document.createElement('table'); if (b.cls) t.className = b.cls;
      const cg = document.createElement('colgroup'); b.widths.forEach((wd) => { const c = document.createElement('col'); c.style.width = wd + '%'; cg.appendChild(c); }); t.appendChild(cg);
      const th = document.createElement('thead'); th.innerHTML = '<tr>' + b.cols.map((c) => '<th>' + c + '</th>').join('') + '</tr>'; t.appendChild(th);
      const tb = document.createElement('tbody'); t.appendChild(tb); body.appendChild(t); return tb;
    };
    // a heading left alone at the bottom of a page moves with its table
    let tb = mk();
    if (!fits()) {
      body.removeChild(tb.parentNode);
      const last = body.lastElementChild;
      const carry = last && /^H[23]$/.test(last.tagName) ? last : null;
      if (carry) body.removeChild(carry);
      newPage(); if (carry) body.appendChild(carry); tb = mk();
    }
    for (const r of b.rows) {
      const tr = document.createElement('tr'); tr.innerHTML = r.map((c) => '<td>' + c + '</td>').join(''); tb.appendChild(tr);
      if (!fits()) { tb.removeChild(tr); newPage(); tb = mk(); tb.appendChild(tr); }
    }
  }
  const pages = document.querySelectorAll('.page');
  pages.forEach((p, i) => { const pn = p.querySelector('.pn'); if (pn) pn.textContent = 'Page ' + i + ' of ' + (pages.length - 1); });
  return pages.length;
});
const files = [];
for (let i = 0; i < total; i++) {
  const el = (await pg.$$('.page'))[i];
  const f = path.join(tmp, 'p' + String(i + 1).padStart(2, '0') + '.png');
  await el.screenshot({ path: f });
  files.push(f);
}
await browser.close();

// PNG to WebP (quality 82), then the page data file the viewer loads.
const py = 'import sys,base64,io\nfrom PIL import Image\nout=[]\nfor f in sys.argv[1:]:\n  b=io.BytesIO(); Image.open(f).convert("RGB").save(b,"WEBP",quality=62,method=6); out.append("data:image/webp;base64,"+base64.b64encode(b.getvalue()).decode())\nprint("\\n".join(out))';
const uris = execFileSync('python3', ['-c', py, ...files], { maxBuffer: 1 << 30 }).toString().trim().split('\n');
fs.writeFileSync(path.join(OUT, slug + '.js'), 'window.__HSF_SAMPLE_PAGES=' + JSON.stringify({ slug: d.slug, code: d.code, industry: d.industry, company, pages: uris }) + ';\n');
console.log(slug + ': ' + total + ' pages, ' + Math.round(fs.statSync(path.join(OUT, slug + '.js')).size / 1024) + ' KB');
