// CNC HSF FORGE | HSF-EXAMPLES-01 v1.0.0 | Example documents on the External CNC letterhead.
//
// Reads every hsf/examples/<section>-<slug>.json and writes, per example,
// vercel/examples/<section>-<slug>.docx and .pdf on the External Care Net
// letterhead exactly as the CNC Letterhead Standard v1.0.0 sets it:
//   header image on the first page only (768 x 117, offset -819150 EMU, 114300 EMU
//   from the page top, behind text); footer image on every page (782 x 167,
//   offset -885825 EMU, 9039225 EMU from the page top, square wrap); A4;
//   margins left and right 1440, header 425, footer 708, bottom 2700 DXA;
//   top 2520 on the first page and 1440 after; Arial, 12 pt body, 1.5 lines,
//   justified; H1 16 pt deep red, H2 14 pt CNC red; nothing typed in the footer.
// The header and footer images come from the letterhead the Director supplied
// (CNC_Letterhead_-_External.pdf, images already cropped to the standard's
// 2000 x 305 and 2000 x 428): hsf/examples/letterhead/.
//
// Every example is fictitious and marked EXAMPLE on its first line and in its
// closing note. No internal platform names (the standard's IP rules).
//
// Usage: NODE_PATH=<node_modules with docx> node hsf/build_examples.mjs [--no-pdf]
// PDF conversion uses LibreOffice (soffice --headless --convert-to pdf).

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const {
  Document, Packer, Paragraph, TextRun, ImageRun, Header, Footer, Table, TableRow, TableCell,
  WidthType, AlignmentType, BorderStyle, ShadingType, HeadingLevel, LevelFormat, LineRuleType,
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

// The first page header is one paragraph of exact height, so on page 1 the
// body starts at 425 + 2095 = 2520 DXA from the top; later pages have an empty
// header and start at the section's 1440 DXA top margin.
const FIRST_HEADER_LINE = 2520 - 425;
function makeHeaderWithImage() {
  return new Header({ children: [new Paragraph({ spacing: { before: 0, after: 0, line: FIRST_HEADER_LINE, lineRule: LineRuleType.EXACT }, children: [new ImageRun({
    type: 'png', data: headerImg, transformation: { width: 768, height: 117 },
    floating: { horizontalPosition: { relative: 'column', offset: -819150 }, verticalPosition: { relative: 'page', offset: 114300 }, behindDocument: true, wrap: { type: 'none' } },
    altText: { title: 'Care Net Consultants Header', description: 'Care Net Consultants letterhead header banner', name: 'header' },
  })] })] });
}
function makeEmptyHeader() { return new Header({ children: [new Paragraph({ children: [] })] }); }
function makeFooter() {
  return new Footer({ children: [new Paragraph({ children: [new ImageRun({
    type: 'png', data: footerImg, transformation: { width: 782, height: 167 },
    floating: { horizontalPosition: { relative: 'column', offset: -885825 }, verticalPosition: { relative: 'page', offset: 9039225 }, behindDocument: true, wrap: { type: 'square', side: 'bothSides' } },
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
const h1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun({ text: t, bold: true, font: 'Arial', size: 32, color: DEEP_RED })], spacing: { before: 120, after: 160 } });
const h2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun({ text: t, bold: true, font: 'Arial', size: 28, color: CNC_RED })], spacing: { before: 240, after: 120 } });
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
      .concat(rows.map((r, ri) => new TableRow({ children: r.map((c, i) => cell(c, widths[i], false, ri % 2 === 1)) }))),
  });
}
const spacer = () => new Paragraph({ children: [], spacing: { after: 120 } });

function blockToDocx(b) {
  if (b.page === true) return [new Paragraph({ pageBreakBefore: true, spacing: { before: 0, after: 0, line: 20, lineRule: LineRuleType.EXACT }, children: [] })];
  if (b.h1) return [h1(b.h1)];
  if (b.h2) return [h2(b.h2)];
  if (b.p) return [body(b.p)];
  if (b.bullets) return b.bullets.map((t) => new Paragraph({ children: runs(t), numbering: { reference: 'bullets', level: 0 }, alignment: AlignmentType.JUSTIFIED, spacing: { line: 360, lineRule: 'auto', after: 60 } }));
  if (b.numbered) return b.numbered.map((t) => new Paragraph({ children: runs(t), numbering: { reference: 'legal', level: 0 }, alignment: AlignmentType.JUSTIFIED, spacing: { line: 360, lineRule: 'auto', after: 60 } }));
  if (b.table) return [table(b.table.cols, b.table.rows, b.table.widths), spacer()];
  if (b.sign) return b.sign.flatMap((s) => [
    new Paragraph({ children: [], spacing: { before: 360 } }),
    new Paragraph({ children: [new TextRun({ text: '______________________________', font: 'Arial', size: 24 })] }),
    new Paragraph({ children: runs('**' + s.role + '**'), spacing: { after: 0 } }),
    new Paragraph({ children: runs((s.name ? s.name + ', ' : '') + 'Date: ' + (s.date || '________')), spacing: { after: 120 } }),
  ]);
  if (b.note) return [new Paragraph({ children: runs(b.note, { size: 20, color: '555555' }), alignment: AlignmentType.JUSTIFIED, spacing: { line: 300, lineRule: 'auto', before: 240 }, border: { left: { style: BorderStyle.SINGLE, size: 18, color: CNC_RED, space: 8 } } })];
  throw new Error('Unknown block: ' + JSON.stringify(b).slice(0, 80));
}

const NUMBERING = { config: [
  { reference: 'bullets', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
  { reference: 'legal', levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
] };

const EXAMPLE_LINE = (ex) => new Paragraph({ children: [new TextRun({ text: 'EXAMPLE DOCUMENT. ' + (ex.company || 'A fictitious company') + ' is fictitious; every name, date and number is made up. For guidance only; not a document to sign or rely on.', font: 'Arial', size: 18, bold: true, color: CNC_RED })], spacing: { after: 200 } });

function build(ex) {
  const blocks = ex.blocks || [];
  const title = [EXAMPLE_LINE(ex), h1(ex.title)];
  if (ex.subtitle) title.push(new Paragraph({ children: runs(ex.subtitle, { size: 24, bold: true, color: CHARCOAL }), spacing: { after: 200 } }));
  const closing = { note: 'This example shows the form and content Care Net recommends for this document in a Health and Safety File. Adapt it to your company, your sites and your appointments; your registered Health and Safety practitioner confirms it before your File is released. Not legal advice.' };
  // One section: header image on the first page only (titlePage), footer on
  // every page, top 2520 on page 1 (through the first page header) and 1440
  // after. A {page:true} block starts a new page.
  const sections = [{
    properties: { titlePage: true, page: { ...PAGE, margin: { top: 1440, right: 1440, bottom: 2700, left: 1440, header: 425, footer: 708 } } },
    headers: { first: makeHeaderWithImage(), default: makeEmptyHeader() },
    footers: { first: makeFooter(), default: makeFooter() },
    children: title.concat(blocks.flatMap(blockToDocx)).concat(blockToDocx(closing)),
  }];
  return new Document({ creator: 'Care Net Consultants (Pty) Ltd', title: ex.title, description: 'Example document for a Health and Safety File',
    styles: { default: { document: { run: { font: 'Arial', size: 24, color: CHARCOAL } } } }, numbering: NUMBERING, sections });
}

// House rules the examples must keep (contract 12.2 and the standard's IP rules).
function check(ex, file) {
  const text = JSON.stringify(ex);
  const bad = [];
  if (/[–—]| - /.test(text)) bad.push('dash punctuation');
  if (/\bcompliant\b/i.test(text)) bad.push('the word compliant');
  if (/GoHighLevel|SharePoint|Make\.com|Firebase|Supabase|MyClinic(?!Online)|Exco\b/i.test(text)) bad.push('internal platform name');
  if (/(section|regulation|reg\.?|annexure)\s+\d/i.test(text.replace(/section 16\(2\)|section 37\(2\)|section 16\(1\)/gi, ''))) bad.push('a provision number');
  if (bad.length) throw new Error(file + ': ' + bad.join(', '));
}

fs.mkdirSync(OUT, { recursive: true });
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
    execFileSync('soffice', ['--headless', '-env:UserInstallation=file://' + tmp + '/profile', '--convert-to', 'pdf', '--outdir', OUT, docx], { stdio: 'ignore', timeout: 180000 });
  }
  index.push({ section: ex.section, slug: base, title: ex.title, subtitle: ex.subtitle || '', docx: '/examples/' + base + '.docx', pdf: noPdf ? null : '/examples/' + base + '.pdf' });
  console.log('ok ' + base);
}
fs.writeFileSync(path.join(ROOT, 'vercel', 'hsf', 'examples.js'), 'window.CNC_HSF_EXAMPLES=' + JSON.stringify(index) + ';\n');
console.log(index.length + ' examples');
