// CNC HSF FORGE | HSF-EXAMPLES-01 v1.1.0 | Example documents on the External CNC letterhead.
//
// Reads every hsf/examples/<section>-<slug>.json and writes, per example,
// vercel/examples/<section>-<slug>.docx and .pdf on the External Care Net
// letterhead exactly as the CNC Letterhead Standard v1.0.0 sets it, in the
// standard's two section architecture:
//   section 1, the cover page: top margin 2520 DXA, the header image
//     (768 x 117, offset -819150 EMU from the column, 114300 EMU from the page
//     top, behind text, no wrap) and the footer image;
//   section 2, every later page: top margin 1440 DXA, no header image, the
//     footer image;
//   the footer image on every page (782 x 167, offset -885825 EMU from the
//   column, 9039225 EMU from the page top, behind text, square wrap on both
//   sides); A4; margins left and right 1440, header 425, footer 708, bottom
//   2700 DXA; Arial, 12 pt body, 1.5 lines, justified; H1 16 pt deep red,
//   H2 14 pt CNC red; nothing typed in the footer.
// The header and footer images come from the letterhead the Director supplied
// (CNC_Letterhead_-_External.pdf, images already cropped to the standard's
// 2000 x 305 and 2000 x 428): hsf/examples/letterhead/.
//
// Every example is fictitious and marked on every page: the cover carries the
// EXAMPLE notice and how to use the example, and every later page carries a
// running EXAMPLE line in its header (the header holds no letterhead image
// there, so the line never touches the letterhead). The cover is the only page
// with the letterhead header, so the fictitious record itself never sits under
// Care Net's registration details. No internal platform names (the standard's
// IP rules).
//
// Usage: NODE_PATH=<node_modules with docx> node hsf/build_examples.mjs [--no-pdf]
// PDF conversion uses LibreOffice (soffice --headless --convert-to pdf). The
// PDF is set in Arial, so Arial must be installed on the build host: the build
// stops before converting if fontconfig resolves Arial to any other font.

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const {
  Document, Packer, Paragraph, TextRun, ImageRun, Header, Footer, Table, TableRow, TableCell,
  WidthType, AlignmentType, BorderStyle, ShadingType, HeadingLevel, LevelFormat, LineRuleType,
  TextWrappingType, TextWrappingSide,
} = require('docx');

const HERE = path.dirname(new URL(import.meta.url).pathname);
const ROOT = path.resolve(HERE, '..');
const SRC = path.join(HERE, 'examples');
const OUT = path.join(ROOT, 'vercel', 'examples');
const noPdf = process.argv.includes('--no-pdf');

const headerImg = fs.readFileSync(path.join(SRC, 'letterhead', 'header_cropped.png'));
const footerImg = fs.readFileSync(path.join(SRC, 'letterhead', 'footer_cropped.png'));

const DEEP_RED = '8B0000', CNC_RED = 'C1272D', CHARCOAL = '1E1E1E', LIGHT = 'F2F2F2';
const PAGE = { size: { width: 11906, height: 16838 } };
const CONTENT_W = 9026;

const MARGIN = { right: 1440, bottom: 2700, left: 1440, header: 425, footer: 708 };
const COVER_TOP = 2520, BODY_TOP = 1440;

// Section names for the cover, from the guidance worklist (contract 12.1).
const SECTION_NAME = Object.fromEntries(JSON.parse(fs.readFileSync(path.join(HERE, 'guidance', 'worklist.json'), 'utf8')).sections.map((s) => [s.code, s.name]));

function makeHeaderWithImage() {
  return new Header({ children: [new Paragraph({ children: [new ImageRun({
    type: 'png', data: headerImg, transformation: { width: 768, height: 117 },
    floating: { horizontalPosition: { relative: 'column', offset: -819150 }, verticalPosition: { relative: 'page', offset: 114300 }, behindDocument: true, wrap: { type: TextWrappingType.NONE } },
    altText: { title: 'Care Net Consultants Header', description: 'Care Net Consultants letterhead header banner', name: 'header' },
  })] })] });
}
// Section 2 header: no letterhead image (the standard), only the running
// EXAMPLE line, so a single printed page still reads as an example.
const RUNNING_MARK = 'EXAMPLE DOCUMENT. The company, people and records on this page are fictitious. For guidance only; not a document to sign or rely on.';
function makeExampleHeader() {
  return new Header({ children: [new Paragraph({ children: [new TextRun({ text: RUNNING_MARK, font: 'Arial', size: 16, bold: true, color: CNC_RED })], spacing: { before: 0, after: 0 } })] });
}
function makeFooter() {
  return new Footer({ children: [new Paragraph({ children: [new ImageRun({
    type: 'png', data: footerImg, transformation: { width: 782, height: 167 },
    floating: { horizontalPosition: { relative: 'column', offset: -885825 }, verticalPosition: { relative: 'page', offset: 9039225 }, behindDocument: true, wrap: { type: TextWrappingType.SQUARE, side: TextWrappingSide.BOTH_SIDES } },
    altText: { title: 'Care Net Consultants Footer', description: 'Care Net Consultants letterhead footer banner', name: 'footer' },
  })] })] });
}

// Inline **bold** only; everything else is plain text.
function runs(text, base = {}) {
  const out = [];
  String(text).split(/(\*\*[^*]+\*\*)/).forEach((part) => {
    if (!part) return;
    const bold = /^\*\*[^*]+\*\*$/.test(part);
    out.push(new TextRun({ text: bold ? part.slice(2, -2) : part, bold: bold || base.bold, font: 'Arial', size: base.size || 24, color: base.color || CHARCOAL }));
  });
  return out;
}
const body = (text, extra = {}) => new Paragraph({ children: runs(text), alignment: AlignmentType.JUSTIFIED, spacing: { line: 360, lineRule: 'auto', after: 120 }, ...extra });
const h1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, keepNext: true, children: [new TextRun({ text: t, bold: true, font: 'Arial', size: 32, color: DEEP_RED })], spacing: { before: 120, after: 160 } });
const h2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, keepNext: true, children: [new TextRun({ text: t, bold: true, font: 'Arial', size: 28, color: CNC_RED })], spacing: { before: 240, after: 120 } });
const border = { style: BorderStyle.SINGLE, size: 4, color: 'BFBFBF' };
const borders = { top: border, bottom: border, left: border, right: border };

function table(cols, rows, widthsPct) {
  const n = cols.length;
  const widths = (widthsPct && widthsPct.length === n ? widthsPct : Array(n).fill(100 / n)).map((p) => Math.round(CONTENT_W * p / 100));
  const fix = CONTENT_W - widths.reduce((a, b) => a + b, 0); widths[widths.length - 1] += fix;
  const cell = (text, w, head, shade) => new TableCell({
    borders, width: { size: w, type: WidthType.DXA },
    shading: head ? { fill: DEEP_RED, type: ShadingType.CLEAR } : shade ? { fill: LIGHT, type: ShadingType.CLEAR } : undefined,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    children: [new Paragraph({ children: runs(text, { size: 20, bold: head, color: head ? 'FFFFFF' : CHARCOAL }), spacing: { line: 276, lineRule: 'auto' } })],
  });
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: widths,
    rows: [new TableRow({ tableHeader: true, children: cols.map((c, i) => cell(c, widths[i], true)) })]
      .concat(rows.map((r, ri) => new TableRow({ cantSplit: true, children: r.map((c, i) => cell(c, widths[i], false, ri % 2 === 1)) }))),
  });
}
const spacer = () => new Paragraph({ children: [], spacing: { after: 120 } });

function blockToDocx(b, opts = {}) {
  if (b.page === true) return [new Paragraph({ pageBreakBefore: true, spacing: { before: 0, after: 0, line: 20, lineRule: LineRuleType.EXACT }, children: [] })];
  if (b.h1) return [h1(b.h1)];
  if (b.h2) return [h2(b.h2)];
  if (b.p) return [body(b.p)];
  if (b.bullets) return b.bullets.map((t) => new Paragraph({ children: runs(t), numbering: { reference: 'bullets', level: 0 }, alignment: AlignmentType.JUSTIFIED, spacing: { line: 360, lineRule: 'auto', after: 60 } }));
  if (b.numbered) return b.numbered.map((t) => new Paragraph({ children: runs(t), numbering: { reference: 'legal', level: 0 }, alignment: AlignmentType.JUSTIFIED, spacing: { line: 360, lineRule: 'auto', after: 60 } }));
  if (b.table) return [table(b.table.cols, b.table.rows, b.table.widths), spacer()];
  // A signature block (every signature in it: space, line, role, name and date)
  // never splits across pages; the document's last block also keeps with the
  // end note, so the note never stands alone on a page.
  if (b.sign) return b.sign.flatMap((s, i) => [
    new Paragraph({ children: [], spacing: { before: 360 }, keepNext: true }),
    new Paragraph({ children: [new TextRun({ text: '______________________________', font: 'Arial', size: 24 })], keepNext: true }),
    new Paragraph({ children: runs('**' + s.role + '**'), spacing: { after: 0 }, keepNext: true }),
    new Paragraph({ children: runs((s.name ? s.name + ', ' : '') + 'Date: ' + (s.date || '________')), spacing: { after: 120 }, keepNext: i < b.sign.length - 1 || !!opts.keepLast }),
  ]);
  if (b.note) return [new Paragraph({ children: runs(b.note, { size: 20, color: '555555' }), alignment: AlignmentType.JUSTIFIED, spacing: { line: 300, lineRule: 'auto', before: 240 }, border: { left: { style: BorderStyle.SINGLE, size: 18, color: CNC_RED, space: 8 } } })];
  throw new Error('Unknown block: ' + JSON.stringify(b).slice(0, 80));
}

const NUMBERING = { config: [
  { reference: 'bullets', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
  { reference: 'legal', levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
] };

// The company field carries "(fictitious)" for the source; the notices say it in words.
const companyName = (ex) => String(ex.company || '').replace(/\s*\(fictitious\)\s*$/i, '').trim();
const EXAMPLE_NOTICE = (ex) => 'EXAMPLE DOCUMENT. ' + (companyName(ex) ? companyName(ex) + ' is a fictitious company. ' : '')
  + 'Every company, person, address, date, figure and reference number in this example is made up; only the Care Net letterhead and any public emergency number are real. For guidance only; not a document to sign or rely on.';
const HOW_TO_USE = 'This example shows the form and content Care Net recommends for this document in a Health and Safety File. Adapt it to your company, your sites and your appointments; your registered Health and Safety practitioner confirms it before your File is released. Not legal advice.';
const END_NOTE = 'End of the example. The company, people and records in it are fictitious; the cover page explains how to use it.';

// Section 1: the cover page, the only page with the letterhead header. It holds
// Care Net's presentation of the example, never the fictitious record itself,
// and is short enough to stay on one page (the build checks the headings list).
function cover(ex) {
  const contents = (ex.blocks || []).filter((b) => b.h2 && /^\d+\.\s/.test(b.h2)).map((b) => b.h2);
  if (contents.length > 12) throw new Error(ex.section + ': too many headings for the cover page');
  const sec = ex.section + (SECTION_NAME[ex.section] ? ': ' + SECTION_NAME[ex.section] : '');
  return [
    new Paragraph({ children: [new TextRun({ text: EXAMPLE_NOTICE(ex), font: 'Arial', size: 18, bold: true, color: CNC_RED })], spacing: { after: 240 } }),
    new Paragraph({ children: runs('Example for a Health and Safety File, Section ' + sec, { size: 22, bold: true, color: CNC_RED }), spacing: { after: 120 } }),
    h1(ex.title),
  ].concat(ex.subtitle ? [new Paragraph({ children: runs(ex.subtitle, { size: 24, bold: true, color: CHARCOAL }), spacing: { after: 200 } })] : [])
    .concat([
      table(['About this example', 'Detail'], [
        ['Company in the example', (companyName(ex) || 'A company') + ', a fictitious company'],
        ['Where it is filed', 'Section ' + sec],
        ['Published by', 'Care Net Consultants, as guidance for companies building a Health and Safety File'],
      ], [32, 68]),
      spacer(),
      h2('How to use this example'),
      body(HOW_TO_USE),
    ])
    .concat(contents.length ? [h2('Contents')].concat(contents.map((t) => new Paragraph({ children: runs(t), spacing: { line: 300, lineRule: 'auto', after: 40 } }))) : []);
}

function build(ex) {
  const blocks = ex.blocks || [];
  const start = [h1(ex.title)];
  if (ex.subtitle) start.push(new Paragraph({ children: runs(ex.subtitle, { size: 24, bold: true, color: CHARCOAL }), spacing: { after: 200 } }));
  // The standard's two sections. Section 1 (cover): top 2520, header image,
  // footer. Section 2 (every later page, starting on a new page): top 1440, no
  // header image (only the running EXAMPLE line), footer. A {page:true} block
  // starts a new page inside section 2.
  const sections = [
    {
      properties: { page: { ...PAGE, margin: { top: COVER_TOP, ...MARGIN } } },
      headers: { default: makeHeaderWithImage() },
      footers: { default: makeFooter() },
      children: cover(ex),
    },
    {
      properties: { page: { ...PAGE, margin: { top: BODY_TOP, ...MARGIN } } },
      headers: { default: makeExampleHeader() },
      footers: { default: makeFooter() },
      children: start.concat(blocks.flatMap((b, i) => blockToDocx(b, { keepLast: i === blocks.length - 1 }))).concat(blockToDocx({ note: END_NOTE })),
    },
  ];
  return new Document({ creator: 'Care Net Consultants (Pty) Ltd', title: ex.title, description: 'Example document for a Health and Safety File. Fictitious; for guidance only.',
    styles: { default: { document: { run: { font: 'Arial', size: 24, color: CHARCOAL } } } }, numbering: NUMBERING, sections });
}

// The PDF must be set in Arial (the standard). LibreOffice silently substitutes
// a metric twin when Arial is missing, so refuse to convert without it.
function assertArial() {
  let got = '';
  try { got = execFileSync('fc-match', ['-f', '%{family}', 'Arial'], { encoding: 'utf8' }); } catch (e) { got = ''; }
  if (!/(^|,)Arial(,|$)/.test(got.trim())) {
    throw new Error('Arial is not installed on this build host (fontconfig gives "' + got.trim() + '"). Install Arial before building the PDFs, or run with --no-pdf.');
  }
}

// House rules the examples must keep (contract 12.2 and the standard's IP rules).
function check(ex, file) {
  const text = JSON.stringify(ex);
  const bad = [];
  if (/[–—]| - /.test(text)) bad.push('dash punctuation');
  if (/\bcompliant\b/i.test(text)) bad.push('the word compliant');
  if (/guarantee/i.test(text)) bad.push('the word guarantee');
  if (/NIHL|Environmental Regulations for Workplaces/i.test(text)) bad.push('a repealed instrument named as current');
  if (/GoHighLevel|SharePoint|Make\.com|Firebase|Supabase|MyClinic(?!Online)|Exco\b/i.test(text)) bad.push('internal platform name');
  if (/(section|regulation|reg\.?|annexure)\s+\d/i.test(text.replace(/section 16\(2\)|section 37\(2\)|section 16\(1\)/gi, ''))) bad.push('a provision number');
  if (bad.length) throw new Error(file + ': ' + bad.join(', '));
}

fs.mkdirSync(OUT, { recursive: true });
if (!noPdf) assertArial();
const files = fs.readdirSync(SRC).filter((f) => /^[A-O]-[a-z0-9-]+\.json$/.test(f)).sort();
const index = [];
for (const f of files) {
  const ex = JSON.parse(fs.readFileSync(path.join(SRC, f), 'utf8'));
  check(ex, f);
  const base = f.replace(/\.json$/, '');
  const docx = path.join(OUT, base + '.docx');
  fs.writeFileSync(docx, await Packer.toBuffer(build(ex)));
  if (!noPdf) {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cnc-ex-'));
    try {
      execFileSync('soffice', ['--headless', '-env:UserInstallation=file://' + tmp + '/profile', '--convert-to', 'pdf', '--outdir', OUT, docx], { stdio: 'ignore', timeout: 180000 });
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }
  index.push({ section: ex.section, slug: base, title: ex.title, subtitle: ex.subtitle || '', docx: '/examples/' + base + '.docx', pdf: noPdf ? null : '/examples/' + base + '.pdf' });
  console.log('ok ' + base);
}
fs.writeFileSync(path.join(ROOT, 'vercel', 'hsf', 'examples.js'), 'window.CNC_HSF_EXAMPLES=' + JSON.stringify(index) + ';\n');
console.log(index.length + ' examples');
