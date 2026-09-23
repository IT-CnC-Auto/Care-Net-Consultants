// CNC HSF FORGE | tests for the security scan of staged uploads (node --test)
// supabase/functions/_shared/scan-core.js      inspectBytes, the antivirus engine, scanUpload
// supabase/functions/_shared/transfer-core.js  the run order: mode, sweep, scan, transfer,
//                                              cleanup, retention (contracts 10.3 and 10.4)
// Every fixture below is built here from bytes: nothing is read from disk and
// nothing touches the network.

import test from 'node:test';
import assert from 'node:assert/strict';

import { isSha256Hex, sha256Hex } from '../../supabase/functions/_shared/mco-adapter.js';
import {
  inspectBytes, createAvEngine, scanUpload, AV_NOT_CONFIGURED, INSPECT_ENGINE, METADATA_LIMIT_BYTES,
} from '../../supabase/functions/_shared/scan-core.js';
import { CLEAN_ENGINE } from '../../supabase/functions/_shared/metadata-clean.js';
import {
  runTransfer, checkStagingPath, createSupabaseIo, RPC, SCAN_LIMIT, RETENTION_LIMIT, STAGING_BUCKET,
} from '../../supabase/functions/_shared/transfer-core.js';
import { createAdapter } from '../../supabase/functions/_shared/mco-adapter.js';

// 1. Byte builders ----------------------------------------------------------------

const enc = new TextEncoder();
const text = (s) => enc.encode(s);
const latin = (s) => Uint8Array.from(s, (c) => c.charCodeAt(0) & 0xff);

function concat(...parts) {
  const n = parts.reduce((a, p) => a + p.length, 0);
  const out = new Uint8Array(n);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

function le16(v) { return Uint8Array.of(v & 0xff, (v >>> 8) & 0xff); }
function le32(v) { return Uint8Array.of(v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff); }
function be16(v) { return Uint8Array.of((v >>> 8) & 0xff, v & 0xff); }
function be32(v) { return Uint8Array.of((v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff); }
function utf16(s) { return concat(...Array.from(s, (c) => le16(c.charCodeAt(0)))); }

async function compress(bytes, format) {
  const cs = new CompressionStream(format);
  const w = cs.writable.getWriter();
  w.write(bytes);
  w.close();
  return new Uint8Array(await new Response(cs.readable).arrayBuffer());
}

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(bytes) {
  let c = 0xffffffff;
  for (const b of bytes) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// A real zip archive: local headers, central directory and end record. method 0
// stores, method 8 deflates with CompressionStream('deflate-raw'); any other
// method number is written as given so the scan meets an unreadable part.
async function buildZip(entries) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const e of entries) {
    const name = text(e.name);
    const raw = typeof e.data === 'string' ? text(e.data) : e.data;
    const method = e.method ?? 8;
    const data = method === 8 ? await compress(raw, 'deflate-raw') : raw;
    const flags = e.flags ?? 0;
    const crc = crc32(raw);
    const local = concat(le32(0x04034b50), le16(20), le16(flags), le16(method), le16(0), le16(0),
      le32(crc), le32(data.length), le32(raw.length), le16(name.length), le16(0), name, data);
    centrals.push(concat(le32(0x02014b50), le16(20), le16(20), le16(flags), le16(method), le16(0), le16(0),
      le32(crc), le32(data.length), le32(raw.length), le16(name.length), le16(0), le16(0), le16(0), le16(0),
      le32(0), le32(offset), name));
    locals.push(local);
    offset += local.length;
  }
  const cd = concat(...centrals);
  const end = concat(le32(0x06054b50), le16(0), le16(0), le16(entries.length), le16(entries.length),
    le32(cd.length), le32(offset), le16(0));
  return concat(...locals, cd, end);
}

const CONTENT_TYPES = '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"></Types>';
const ROOT_RELS = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
  + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
const HYPERLINK_RELS = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
  + '<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://www.gov.za/documents/occupational-health-and-safety-act" TargetMode="External"/></Relationships>';
const TEMPLATE_RELS = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
  + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate" Target="https://attacker.invalid/t.dotm" TargetMode="External"/></Relationships>';
const FILE_LINK_RELS = HYPERLINK_RELS.replace('https://www.gov.za/documents/occupational-health-and-safety-act', 'file://///share.invalid/x');

function docxParts(extra) {
  return [
    { name: '[Content_Types].xml', data: CONTENT_TYPES },
    { name: '_rels/.rels', data: ROOT_RELS },
    { name: 'word/document.xml', data: '<w:document><w:body><w:p><w:r><w:t>Safety file</w:t></w:r></w:p></w:body></w:document>' },
    { name: 'word/_rels/document.xml.rels', data: HYPERLINK_RELS },
    ...(extra || []),
  ];
}

// PDF: header, catalogue and trailer. body is spliced into the catalogue.
function pdf(body) {
  return latin(`%PDF-1.7\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R ${body || ''} >>\nendobj\n`
    + '2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n'
    + 'trailer\n<< /Root 1 0 R >>\n%%EOF\n');
}

// A PDF whose action dictionary is hidden inside a compressed object stream.
async function pdfWithObjStm(inner) {
  const packed = await compress(latin(inner), 'deflate');
  return concat(
    latin('%PDF-1.7\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'),
    latin(`5 0 obj\n<< /Type /ObjStm /N 1 /First 4 /Filter /FlateDecode /Length ${packed.length} >>\nstream\n`),
    packed,
    latin('\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n'),
  );
}

// TIFF (EXIF body), little endian, with IFD0 pointing at a GPS directory that
// holds a latitude.
function tiffWithGps(withLatitude) {
  const gpsTag = withLatitude ? 0x0002 : 0x0000;
  return concat(
    latin('II'), le16(42), le32(8),
    le16(1), le16(0x8825), le16(4), le32(1), le32(26), le32(0),
    le16(1), le16(gpsTag), le16(withLatitude ? 5 : 1), le32(withLatitude ? 3 : 4), le32(0), le32(0),
  );
}

function jpegSegment(marker, body) {
  return concat(Uint8Array.of(0xff, marker), be16(body.length + 2), body);
}

function jpeg(segments) {
  return concat(
    Uint8Array.of(0xff, 0xd8),
    jpegSegment(0xe0, concat(latin('JFIF\0'), Uint8Array.of(1, 1, 0, 0, 1, 0, 1, 0, 0))),
    ...(segments || []),
    jpegSegment(0xdb, new Uint8Array(65)),
    jpegSegment(0xda, Uint8Array.of(1, 1, 0, 0, 0x3f, 0)),
    Uint8Array.of(0x12, 0x34, 0x56),
    Uint8Array.of(0xff, 0xd9),
  );
}

function pngChunk(type, data) {
  const t = latin(type);
  return concat(be32(data.length), t, data, be32(crc32(concat(t, data))));
}

const PNG_SIG = Uint8Array.of(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a);
function png(chunks) {
  return concat(
    PNG_SIG,
    pngChunk('IHDR', concat(be32(1), be32(1), Uint8Array.of(8, 2, 0, 0, 0))),
    ...(chunks || []),
    pngChunk('IDAT', Uint8Array.of(0x78, 0x9c, 0x63, 0x60, 0x60, 0x60, 0, 0, 0, 4, 0, 1)),
    pngChunk('IEND', new Uint8Array(0)),
  );
}

// An OLE compound document header followed by directory names.
function ole(names) {
  const header = new Uint8Array(512);
  header.set([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  const dir = names.map((n) => {
    const e = new Uint8Array(128);
    e.set(utf16(n).subarray(0, 62));
    e.set(le16(Math.min(64, (n.length + 1) * 2)), 64);
    return e;
  });
  return concat(header, ...dir);
}

const MIME = {
  pdf: 'application/pdf',
  jpeg: 'image/jpeg',
  png: 'image/png',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  doc: 'application/msword',
  xls: 'application/vnd.ms-excel',
  csv: 'text/csv',
};

const codes = (r) => r.findings.map((f) => f.code);

// 2. inspectBytes: PDF ----------------------------------------------------------------

test('inspect PDF: a plain PDF is clean; JavaScript, launch, embedded files, rich media, XFA and automatic actions are harmful', async () => {
  assert.deepEqual(await inspectBytes({ bytes: pdf(), mimeType: MIME.pdf, fileName: 'Risk_assessment.pdf' }), { verdict: 'clean', findings: [] });
  // An open action that only shows a page is not active content.
  assert.equal((await inspectBytes({ bytes: pdf('/OpenAction [3 0 R /Fit]'), mimeType: MIME.pdf })).verdict, 'clean');

  const cases = [
    ['/OpenAction << /S /JavaScript /JS (app.alert(1)) >>', 'pdf_javascript'],
    ['/OpenAction << /S /Launch /F (cmd.exe) >>', 'pdf_launch'],
    ['/Names << /EmbeddedFiles 4 0 R >>', 'pdf_embedded_file'],
    ['/Annots [<< /Subtype /RichMedia >>]', 'pdf_rich_media'],
    ['/AcroForm << /XFA 6 0 R >>', 'pdf_xfa'],
    ['/AA << /O 7 0 R >>', 'pdf_auto_action'],
  ];
  for (const [body, code] of cases) {
    const r = await inspectBytes({ bytes: pdf(body), mimeType: MIME.pdf });
    assert.equal(r.verdict, 'harmful', body);
    assert.ok(codes(r).includes(code), `${body} gave ${codes(r)}`);
    for (const f of r.findings) {
      assert.equal(typeof f.message, 'string');
      assert.ok(!/[–—]/.test(f.message));
    }
  }
});

test('inspect PDF: names hidden with #xx escapes or in a compressed object stream are still found', async () => {
  let r = await inspectBytes({ bytes: pdf('/OpenAction << /S /J#61vaScript /J#53 (x) >>'), mimeType: MIME.pdf });
  assert.deepEqual(codes(r), ['pdf_javascript']);

  r = await inspectBytes({ bytes: await pdfWithObjStm('7 0 << /S /JavaScript /JS (app.alert(1)) >>'), mimeType: MIME.pdf });
  assert.equal(r.verdict, 'harmful');
  assert.deepEqual(codes(r), ['pdf_javascript']);

  r = await inspectBytes({ bytes: await pdfWithObjStm('7 0 << /Type /Page >>'), mimeType: MIME.pdf });
  assert.equal(r.verdict, 'clean');

  // An object stream that cannot be inflated is never clean.
  const broken = concat(
    latin('%PDF-1.7\n5 0 obj\n<< /Type /ObjStm /N 1 /First 4 /Filter /FlateDecode /Length 8 >>\nstream\n'),
    Uint8Array.of(1, 2, 3, 4, 5, 6, 7, 8),
    latin('\nendstream\nendobj\n%%EOF\n'),
  );
  r = await inspectBytes({ bytes: broken, mimeType: MIME.pdf });
  assert.equal(r.verdict, 'error');
  assert.deepEqual(codes(r), ['could_not_inspect']);
  assert.match(r.findings[0].message, /^The file could not be checked: /);
});

// An object stream whose dictionary is written in any form a PDF reader accepts.
async function pdfWithObjStmDict(extra, inner, filter) {
  const packed = await compress(latin(inner), 'deflate');
  return concat(
    latin(`%PDF-1.7\n5 0 obj\n<< /Type /ObjStm /N 1 /First 4 ${filter || '/Filter /FlateDecode'} /Length ${packed.length}${extra} >>\nstream\n`),
    packed,
    latin('\nendstream\nendobj\ntrailer\n<< /Root 3 0 R >>\n%%EOF\n'),
  );
}

test('inspect PDF: an object stream cannot hide behind a string, padding or a comment in its dictionary', async () => {
  const js = '3 0 << /Type /Catalog /OpenAction << /S /JavaScript /JS (app.alert\\(1\\)) >> >>';
  for (const extra of [
    '',
    ' /Title ( obj)',
    ' /Title (x) 7 0 obj',
    ` /Pad (${'x'.repeat(9000)})`,
    ' /Note (a \\) stream) /Hex <4f626a>',
    ' % << >> comment\n',
  ]) {
    const r = await inspectBytes({ bytes: await pdfWithObjStmDict(extra, js), mimeType: MIME.pdf });
    assert.equal(r.verdict, 'harmful', JSON.stringify(extra).slice(0, 40));
    assert.deepEqual(codes(r), ['pdf_javascript']);
  }
  // Only object streams carry /First, so one without /Type /ObjStm is read too.
  let r = await inspectBytes({ bytes: await pdfWithObjStmDict('', js.replace('/JavaScript', '/Launch').replace('/JS (app.alert\\(1\\))', '')), mimeType: MIME.pdf });
  assert.deepEqual(codes(r), ['pdf_launch']);
  // A filter given by reference is not read as plain bytes: never clean.
  r = await inspectBytes({ bytes: await pdfWithObjStmDict('', js, '/Filter 9 0 R'), mimeType: MIME.pdf });
  assert.equal(r.verdict, 'error');
  assert.match(r.findings[0].message, /encoding the scan cannot read/);
});

test('inspect PDF: a structure the scan cannot follow is never clean', async () => {
  const packed = await compress(latin('3 0 << /OpenAction << /S /JavaScript /JS (x) >> >>'), 'deflate');
  const cases = [
    // A string that is never closed swallows the object stream after it.
    concat(latin('%PDF-1.7\n1 0 obj\n<< /Title (open >>\nendobj\n5 0 obj\n<< /Type /ObjStm /N 1 /First 4 /Filter /FlateDecode >>\nstream\n'),
      packed, latin('\nendstream\nendobj\n%%EOF\n')),
    // A stream keyword with no dictionary before it.
    concat(latin('%PDF-1.7\n5 0 obj\n[1 2]\nstream\n'), packed, latin('\nendstream\nendobj\n%%EOF\n')),
    // Unbalanced dictionaries.
    latin('%PDF-1.7\n1 0 obj\n<< /Type /Catalog << /Pages 2 0 R >>\nendobj\n%%EOF\n'),
  ];
  for (const bytes of cases) {
    const r = await inspectBytes({ bytes, mimeType: MIME.pdf });
    assert.equal(r.verdict, 'error');
    assert.deepEqual(codes(r), ['could_not_inspect']);
  }
  // A stream whose data holds the word stream on a line of its own is still read correctly.
  const data = latin('BT (upstream) Tj ET\nstream\n');
  const ok = concat(latin(`%PDF-1.7\n4 0 obj\n<< /Length ${data.length} >>\nstream\n`), data,
    latin('endstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n'));
  assert.deepEqual(await inspectBytes({ bytes: ok, mimeType: MIME.pdf }), { verdict: 'clean', findings: [] });
});

// 3. inspectBytes: type checks ---------------------------------------------------------

test('inspect: magic bytes that do not match the declared type are harmful', async () => {
  const pngBytes = png();
  const pairs = [
    [pngBytes, MIME.pdf],
    [pdf(), MIME.png],
    [pdf(), MIME.jpeg],
    [pdf(), MIME.docx],
    [pdf(), MIME.doc],
    [pngBytes, MIME.xls],
    [text('MZ\x90\x00 not a document'), MIME.pdf],
  ];
  for (const [bytes, mimeType] of pairs) {
    const r = await inspectBytes({ bytes, mimeType });
    assert.equal(r.verdict, 'harmful', mimeType);
    assert.deepEqual(codes(r), ['type_mismatch'], mimeType);
  }
  // A zip that is not a Word document, declared as one.
  const notWord = await buildZip([{ name: '[Content_Types].xml', data: CONTENT_TYPES }, { name: 'xl/workbook.xml', data: '<workbook/>' }]);
  assert.deepEqual(codes(await inspectBytes({ bytes: notWord, mimeType: MIME.docx })), ['type_mismatch']);
  assert.equal((await inspectBytes({ bytes: notWord, mimeType: MIME.xlsx })).verdict, 'clean');
});

test('inspect: a type outside the allowed list and a name ending that contradicts the type are harmful', async () => {
  let r = await inspectBytes({ bytes: pdf(), mimeType: 'application/x-msdownload', fileName: 'setup.exe' });
  assert.deepEqual(codes(r), ['type_not_allowed']);
  r = await inspectBytes({ bytes: pdf(), mimeType: MIME.pdf, fileName: 'invoice.pdf.exe' });
  assert.deepEqual(codes(r), ['name_mismatch']);
  r = await inspectBytes({ bytes: pdf(), mimeType: 'Application/PDF', fileName: 'Report.PDF' });
  assert.equal(r.verdict, 'clean');
  r = await inspectBytes({ bytes: pdf(), mimeType: MIME.pdf, fileName: 'no_extension' });
  assert.equal(r.verdict, 'clean');
});

// 4. inspectBytes: OOXML ------------------------------------------------------------------

test('inspect OOXML: a Word file with a web hyperlink is clean, stored or deflated', async () => {
  let r = await inspectBytes({ bytes: await buildZip(docxParts()), mimeType: MIME.docx, fileName: 'Policy.docx' });
  assert.deepEqual(r, { verdict: 'clean', findings: [] });
  r = await inspectBytes({ bytes: await buildZip(docxParts().map((e) => Object.assign({}, e, { method: 0 }))), mimeType: MIME.docx });
  assert.deepEqual(r, { verdict: 'clean', findings: [] });
});

test('inspect OOXML: vbaProject.bin, ActiveX, OLE objects and External relationships are harmful', async () => {
  const cases = [
    [[{ name: 'word/vbaProject.bin', data: new Uint8Array(64) }], 'office_macros'],
    [[{ name: 'word/activeX/activeX1.xml', data: '<ax/>' }], 'office_activex'],
    [[{ name: 'word/embeddings/oleObject1.bin', data: new Uint8Array(32) }], 'office_embedded_object'],
    [[{ name: 'word/_rels/settings.xml.rels', data: TEMPLATE_RELS }], 'office_external_link'],
    [[{ name: 'word/_rels/settings.xml.rels', data: TEMPLATE_RELS, method: 0 }], 'office_external_link'],
    [[{ name: 'word/_rels/footer1.xml.rels', data: FILE_LINK_RELS }], 'office_external_link'],
  ];
  for (const [extra, code] of cases) {
    const r = await inspectBytes({ bytes: await buildZip(docxParts(extra)), mimeType: MIME.docx });
    assert.equal(r.verdict, 'harmful', code);
    assert.deepEqual(codes(r), [code]);
  }
  // A spreadsheet with a macro project.
  const xl = await buildZip([
    { name: '[Content_Types].xml', data: CONTENT_TYPES },
    { name: 'xl/workbook.xml', data: '<workbook/>' },
    { name: 'xl/vbaProject.bin', data: new Uint8Array(16) },
  ]);
  assert.deepEqual(codes(await inspectBytes({ bytes: xl, mimeType: MIME.xlsx })), ['office_macros']);
});

test('inspect OOXML: parts the scan cannot read are an error, never clean', async () => {
  // A relationships part compressed with a method the scan does not support.
  let r = await inspectBytes({ bytes: await buildZip(docxParts([{ name: 'word/_rels/x.rels', data: TEMPLATE_RELS, method: 12 }])), mimeType: MIME.docx });
  assert.equal(r.verdict, 'error');
  // An encrypted part.
  r = await inspectBytes({ bytes: await buildZip(docxParts([{ name: 'word/_rels/y.rels', data: HYPERLINK_RELS, method: 0, flags: 1 }])), mimeType: MIME.docx });
  assert.equal(r.verdict, 'error');
  // No central directory at all.
  r = await inspectBytes({ bytes: concat(Uint8Array.of(0x50, 0x4b, 0x03, 0x04), new Uint8Array(40)), mimeType: MIME.docx });
  assert.equal(r.verdict, 'error');
  assert.deepEqual(codes(r), ['could_not_inspect']);
  // Harmful wins over error.
  r = await inspectBytes({
    bytes: await buildZip(docxParts([{ name: 'word/vbaProject.bin', data: new Uint8Array(4) }, { name: 'word/_rels/x.rels', data: 'x', method: 12 }])),
    mimeType: MIME.docx,
  });
  assert.equal(r.verdict, 'harmful');
});

test('inspect OOXML: without DecompressionStream a deflated part is an error, not clean', async (t) => {
  const bytes = await buildZip(docxParts());
  const saved = globalThis.DecompressionStream;
  globalThis.DecompressionStream = undefined;
  t.after(() => { globalThis.DecompressionStream = saved; });
  const r = await inspectBytes({ bytes, mimeType: MIME.docx });
  assert.equal(r.verdict, 'error');
  assert.match(r.findings[0].message, /cannot decompress/);
});

// 5. inspectBytes: legacy Office -------------------------------------------------------------

test('inspect OLE: a _VBA_PROJECT stream, a Macros storage or VBA source is harmful; a plain document is clean', async () => {
  assert.equal((await inspectBytes({ bytes: ole(['Root Entry', 'WordDocument', '1Table']), mimeType: MIME.doc, fileName: 'Old.doc' })).verdict, 'clean');
  for (const names of [['Root Entry', '_VBA_PROJECT_CUR', 'VBA'], ['Root Entry', 'Macros', 'WordDocument'], ['Root Entry', 'Workbook', 'VBA']]) {
    const r = await inspectBytes({ bytes: ole(names), mimeType: MIME.xls });
    assert.deepEqual(codes(r), ['office_macros'], names.join(','));
  }
  const source = concat(ole(['Root Entry', 'Workbook']), latin('Attribute VB_Name = "Module1"'));
  assert.deepEqual(codes(await inspectBytes({ bytes: source, mimeType: MIME.xls })), ['office_macros']);
  assert.deepEqual(codes(await inspectBytes({ bytes: ole(['Root Entry', 'Equation Native']), mimeType: MIME.doc })), ['office_embedded_object']);
});

// 6. inspectBytes: CSV ------------------------------------------------------------------------

test('inspect CSV: formula injection is harmful; numbers, telephone numbers and plain text are clean', async () => {
  const clean = 'Name,Balance,Phone,Note\r\nNomsa,-12.5,+27 60 070 2723,"Said ""hello"""\nPieter;-4;+27;@ home\n';
  assert.deepEqual(await inspectBytes({ bytes: text(clean), mimeType: MIME.csv, fileName: 'register.csv' }), { verdict: 'clean', findings: [] });
  assert.equal((await inspectBytes({ bytes: text('﻿Name,Count\nA,1\n'), mimeType: MIME.csv })).verdict, 'clean');

  const injections = [
    'Name,Total\nA,=SUM(B1:B9)\n',
    'Name,Link\nA,"=HYPERLINK(""https://x.invalid"",""open"")"\n',
    "Name,Cmd\nA,=cmd|' /C calc'!A0\n",
    'Name,X\nA,+HYPERLINK("x")\n',
    'Name,X\nA,-2+3*cmd|x\n',
    'Name,X\nA,@SUM(1+1)\n',
    'Name,X\nA,\t=1+1\n',
    'Name;X\nA;\r=A1\n',
    '=1+1\n',
  ];
  for (const csv of injections) {
    const r = await inspectBytes({ bytes: text(csv), mimeType: MIME.csv });
    assert.equal(r.verdict, 'harmful', JSON.stringify(csv));
    assert.deepEqual(codes(r), ['csv_formula'], JSON.stringify(csv));
  }
});

test('inspect CSV: bytes that are not UTF 8 text, or carry NUL or control bytes, do not match the type', async () => {
  for (const bytes of [Uint8Array.of(0x41, 0x2c, 0x00, 0x42), Uint8Array.of(0xff, 0xfe, 0x41), concat(text('a,b\n'), Uint8Array.of(0x07)), png()]) {
    const r = await inspectBytes({ bytes, mimeType: MIME.csv });
    assert.deepEqual(codes(r), ['type_mismatch']);
  }
});

// 7. inspectBytes: images -------------------------------------------------------------------------

test('inspect JPEG: EXIF with a GPS latitude is harmful; EXIF without location and a plain JPEG are clean', async () => {
  assert.deepEqual(await inspectBytes({ bytes: jpeg(), mimeType: MIME.jpeg, fileName: 'site.jpg' }), { verdict: 'clean', findings: [] });
  const gps = jpeg([jpegSegment(0xe1, concat(latin('Exif\0\0'), tiffWithGps(true)))]);
  assert.deepEqual(codes(await inspectBytes({ bytes: gps, mimeType: MIME.jpeg })), ['location_metadata']);
  const noLocation = jpeg([jpegSegment(0xe1, concat(latin('Exif\0\0'), tiffWithGps(false)))]);
  assert.equal((await inspectBytes({ bytes: noLocation, mimeType: MIME.jpeg })).verdict, 'clean');
  // Big endian EXIF is read too.
  const be = concat(latin('MM'), be16(42), be32(8), be16(1), be16(0x8825), be16(4), be32(1), be32(26), be32(0),
    be16(1), be16(4), be16(5), be32(3), be32(0), be32(0));
  assert.deepEqual(codes(await inspectBytes({ bytes: jpeg([jpegSegment(0xe1, concat(latin('Exif\0\0'), be))]), mimeType: MIME.jpeg })), ['location_metadata']);
  // XMP location.
  const xmp = jpeg([jpegSegment(0xe1, latin('http://ns.adobe.com/xap/1.0/\0<x:xmpmeta><rdf:Description exif:GPSLatitude="26,12.0S"/></x:xmpmeta>'))]);
  assert.deepEqual(codes(await inspectBytes({ bytes: xmp, mimeType: MIME.jpeg })), ['location_metadata']);
});

test('inspect JPEG: more than 256 KB of metadata is harmful; a damaged structure is an error', async () => {
  const big = [];
  for (let i = 0; i < 5; i++) big.push(jpegSegment(0xe2, new Uint8Array(60000)));
  assert.ok(5 * 60002 > METADATA_LIMIT_BYTES);
  assert.deepEqual(codes(await inspectBytes({ bytes: jpeg(big), mimeType: MIME.jpeg })), ['oversized_metadata']);
  // Truncated in the middle of a segment.
  const cut = jpeg([jpegSegment(0xe1, concat(latin('Exif\0\0'), tiffWithGps(false)))]).subarray(0, 30);
  assert.equal((await inspectBytes({ bytes: cut, mimeType: MIME.jpeg })).verdict, 'error');
  // An EXIF block whose GPS pointer runs off the end.
  const badTiff = concat(latin('II'), le16(42), le32(8), le16(1), le16(0x8825), le16(4), le32(1), le32(4000), le32(0));
  assert.equal((await inspectBytes({ bytes: jpeg([jpegSegment(0xe1, concat(latin('Exif\0\0'), badTiff))]), mimeType: MIME.jpeg })).verdict, 'error');
});

test('inspect PNG: a plain PNG is clean; eXIf GPS and XMP location are harmful; oversized text is harmful', async () => {
  assert.deepEqual(await inspectBytes({ bytes: png(), mimeType: MIME.png, fileName: 'plan.png' }), { verdict: 'clean', findings: [] });
  assert.equal((await inspectBytes({ bytes: png([pngChunk('tEXt', latin('Comment\0Site plan'))]), mimeType: MIME.png })).verdict, 'clean');
  assert.deepEqual(codes(await inspectBytes({ bytes: png([pngChunk('eXIf', tiffWithGps(true))]), mimeType: MIME.png })), ['location_metadata']);

  const xmp = latin('<x:xmpmeta><rdf:Description exif:GPSLongitude="28,2.5E"/></x:xmpmeta>');
  const itxt = concat(latin('XML:com.adobe.xmp\0'), Uint8Array.of(0, 0), latin('\0\0'), xmp);
  assert.deepEqual(codes(await inspectBytes({ bytes: png([pngChunk('iTXt', itxt)]), mimeType: MIME.png })), ['location_metadata']);
  const zitxt = concat(latin('XML:com.adobe.xmp\0'), Uint8Array.of(1, 0), latin('\0\0'), await compress(xmp, 'deflate'));
  assert.deepEqual(codes(await inspectBytes({ bytes: png([pngChunk('iTXt', zitxt)]), mimeType: MIME.png })), ['location_metadata']);

  const huge = pngChunk('tEXt', concat(latin('Comment\0'), new Uint8Array(METADATA_LIMIT_BYTES + 1).fill(0x41)));
  assert.deepEqual(codes(await inspectBytes({ bytes: png([huge]), mimeType: MIME.png })), ['oversized_metadata']);

  // No end marker: the structure cannot be followed.
  assert.equal((await inspectBytes({ bytes: png().subarray(0, 40), mimeType: MIME.png })).verdict, 'error');
});

test('inspectBytes never throws and never calls anything clean it could not read', async () => {
  for (const input of [undefined, {}, { bytes: 'text', mimeType: MIME.pdf }, { bytes: new Uint8Array(0), mimeType: MIME.pdf }]) {
    const r = await inspectBytes(input);
    assert.notEqual(r.verdict, 'clean', JSON.stringify(input));
  }
});

// 8. The antivirus engine -----------------------------------------------------------------------

const AV_URL = 'https://av.unit-test.invalid/scan';
const AV_TOKEN = 'av-token-UNIT-TEST-must-never-appear-5555';

function avFetch(reply) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url: String(url), init });
    return typeof reply === 'function' ? reply(url, init) : reply;
  };
  return { calls, fetchImpl };
}

test('AV engine: not configured gives error; the fixture needs HSF_SCAN_ALLOW_FIXTURE', async () => {
  for (const o of [undefined, {}, { endpoint: AV_URL }, { token: AV_TOKEN }, { endpoint: 'http://av.unit-test.invalid/scan', token: AV_TOKEN }, { endpoint: 'not a url', token: AV_TOKEN }, { allowFixture: 'true' }]) {
    const e = createAvEngine(o);
    assert.equal(e.configured, false, JSON.stringify(o));
    assert.equal(e.kind, 'none');
    const r = await e.scan({ bytes: pdf() });
    assert.equal(r.result, 'error');
    assert.ok(r.error.startsWith(AV_NOT_CONFIGURED));
    assert.ok(!JSON.stringify(r).includes(AV_TOKEN));
  }
  const fx = createAvEngine({ allowFixture: true });
  assert.equal(fx.kind, 'fixture');
  assert.deepEqual(await fx.scan({ bytes: pdf() }), { result: 'clean', engine: 'fixture', signature: null, error: null });
  // A real endpoint always wins over the fixture.
  assert.equal(createAvEngine({ endpoint: AV_URL, token: AV_TOKEN, allowFixture: true, fetch: async () => {} }).kind, 'http');
});

test('AV engine over HTTP: request shape, clean and infected replies', async () => {
  const bytes = pdf();
  let f = avFetch(new Response(JSON.stringify({ clean: true, signature: null, engine: 'ClamAV 1.4' }), { status: 200 }));
  let e = createAvEngine({ endpoint: AV_URL, token: AV_TOKEN, fetch: f.fetchImpl });
  assert.deepEqual(await e.scan({ bytes, fileName: 'Risk assessment (1).pdf' }), { result: 'clean', engine: 'ClamAV 1.4', signature: null, error: null });
  const c = f.calls[0];
  assert.equal(c.url, AV_URL);
  assert.equal(c.init.method, 'POST');
  assert.equal(c.init.headers.Authorization, `Bearer ${AV_TOKEN}`);
  assert.equal(c.init.headers['Content-Type'], 'application/octet-stream');
  assert.equal(c.init.headers['X-File-Name'], 'Risk_assessment__1_.pdf');
  assert.equal(c.init.body, bytes);

  f = avFetch(new Response(JSON.stringify({ clean: false, signature: 'Win.Test.EICAR_HDB-1', engine: 'ClamAV 1.4' }), { status: 200 }));
  e = createAvEngine({ endpoint: AV_URL, token: AV_TOKEN, fetch: f.fetchImpl });
  assert.deepEqual(await e.scan({ bytes }), { result: 'infected', engine: 'ClamAV 1.4', signature: 'Win.Test.EICAR_HDB-1', error: null });
});

test('AV engine over HTTP: failures and unreadable replies are errors, never clean, and never carry the token', async () => {
  const replies = [
    () => new Response('busy', { status: 503 }),
    () => new Response('not json', { status: 200 }),
    () => new Response(JSON.stringify({ clean: 'yes' }), { status: 200 }),
    () => new Response(JSON.stringify({ infected: false }), { status: 200 }),
    () => new Response('null', { status: 200 }),
    () => { throw new Error(`connect ECONNREFUSED with ${AV_TOKEN}`); },
  ];
  for (const reply of replies) {
    const f = avFetch(reply);
    const e = createAvEngine({ endpoint: AV_URL, token: AV_TOKEN, fetch: f.fetchImpl });
    const r = await e.scan({ bytes: pdf() });
    assert.equal(r.result, 'error');
    assert.ok(typeof r.error === 'string' && r.error.length > 0);
    assert.ok(!JSON.stringify(r).includes(AV_TOKEN), 'the token leaked into an engine error');
  }
});

// 9. scanUpload and the run ----------------------------------------------------------------------

const ACCOUNT_ID = '0b9a8c7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d';
const SCAN_ID = '7e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c61';
const SECOND_ID = '8e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c62';
const OLD_ID = '9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c63';
const SAFE_NAME = 'Risk_assessment_2026.pdf';
const CLEAN_PDF = pdf();
const CLEAN_SHA = await sha256Hex(CLEAN_PDF);

function scanRow(over) {
  const id = (over && over.id) || SCAN_ID;
  return Object.assign({
    id,
    client_account_id: ACCOUNT_ID,
    safe_name: SAFE_NAME,
    mime_type: MIME.pdf,
    sha256_client: CLEAN_SHA,
    sha256_server: null,
    storage_bucket: STAGING_BUCKET,
    storage_path: `${ACCOUNT_ID}/${id}/${SAFE_NAME}`,
    status: 'uploaded',
    scan_status: 'pending',
    scan_attempts: 1,
  }, over || {});
}

// A fake database and Storage for one run. Every call is logged in order.
function scanWorld(opts) {
  const o = opts || {};
  const calls = [];
  const objects = new Map(Object.entries(o.objects || { [`${ACCOUNT_ID}/${SCAN_ID}/${SAFE_NAME}`]: CLEAN_PDF }));
  const scanned = new Map();
  const cleanSha = new Map();
  let inMemory = 0;
  let peak = 0;
  const deps = {
    async rpc(fn, args) {
      calls.push(['rpc', fn, args]);
      switch (fn) {
        case RPC.mode: return o.mode ?? 'hold';
        case RPC.sweep: return 0;
        case RPC.scanClaim:
          assert.deepEqual(args, { p_limit: SCAN_LIMIT });
          if (o.scanClaimFails) throw new Error('hsf_scan_claim was refused (HTTP 500)');
          return o.scanQueue ?? [scanRow()];
        case RPC.scanRecord:
          // From 054 a plain clean result is refused: it must carry the cleaned fingerprint.
          if (args.p_result === 'clean') throw new Error('hsf_scan_record was refused (HTTP 400): a clean result must carry the cleaned fingerprint');
          scanned.set(args.p_upload_id, args.p_result);
          inMemory = 0;
          return { upload_id: args.p_upload_id, scan_status: args.p_result, status: args.p_result === 'error' ? 'uploaded' : 'rejected' };
        case RPC.scanWriteBack:
          // The announcement before the write back: under the claim, with the
          // fingerprint of the bytes about to be written.
          assert.ok(isSha256Hex(args.p_sha256_clean));
          return { upload_id: args.p_upload_id, sha256_clean: args.p_sha256_clean };
        case RPC.scanRecordClean:
          if (o.recordCleanFails) throw new Error('hsf_scan_record_clean was refused (HTTP 500)');
          scanned.set(args.p_upload_id, 'clean');
          cleanSha.set(args.p_upload_id, args.p_sha256_clean);
          inMemory = 0;
          return { upload_id: args.p_upload_id, scan_status: 'clean', status: 'uploaded' };
        case RPC.claim: {
          // As the database does: only clean uploads with a cleaned fingerprint are handed out.
          const rows = (o.scanQueue ?? [scanRow()]).filter((r) => scanned.get(r.id) === 'clean' && cleanSha.has(r.id));
          return rows.map((r) => Object.assign({}, r, { scan_status: 'clean', status: 'transferring', sha256_clean: cleanSha.get(r.id) }));
        }
        case RPC.record:
          inMemory = 0;
          return { upload_id: args.p_upload_id, status: args.p_outcome === 'held' ? 'held' : 'uploaded' };
        case RPC.cleanup: return o.cleanup ?? [];
        case RPC.retention:
          assert.deepEqual(args, { p_limit: RETENTION_LIMIT });
          return o.retention ?? [];
        case RPC.markExpired: return { upload_id: args.p_upload_id, status: 'expired' };
        case RPC.markDeleted: return { upload_id: args.p_upload_id, status: 'staging_deleted' };
        default: throw new Error(`unexpected rpc ${fn}`);
      }
    },
    async download(path) {
      calls.push(['download', path]);
      if (!objects.has(path)) throw new Error('Storage replied with HTTP 404.');
      inMemory++;
      peak = Math.max(peak, inMemory);
      return objects.get(path);
    },
    async remove(path, ropts) {
      calls.push(['remove', path, ropts]);
      objects.delete(path);
      return true;
    },
    async upload(path, bytes, mimeType) {
      calls.push(['upload', path, bytes, mimeType]);
      if (o.uploadFails) throw new Error('Storage refused the cleaned file (HTTP 500).');
      objects.set(path, bytes);
      return true;
    },
    createAdapter,
    avEngine: o.avEngine,
    allowScanFixture: o.allowScanFixture,
    av: o.av,
  };
  return { deps, calls, scanned, objects, peak: () => peak };
}

// Every scan result recorded, clean ones (hsf_scan_record_clean) given p_result
// 'clean' so the two functions read alike in the assertions below.
const recordsOf = (calls) => calls
  .filter((c) => c[0] === 'rpc' && (c[1] === RPC.scanRecord || c[1] === RPC.scanRecordClean))
  .map((c) => (c[1] === RPC.scanRecordClean ? Object.assign({ p_result: 'clean' }, c[2]) : c[2]));
const order = (calls) => calls.map((c) => (c[0] === 'rpc' ? c[1] : c[0]));

test('run order: mode, sweep, scan, transfer, cleanup, retention', async () => {
  const w = scanWorld({ allowScanFixture: true, retention: [{ upload_id: OLD_ID, storage_path: `${ACCOUNT_ID}/${OLD_ID}/${SAFE_NAME}`, reason: 'retention' }] });
  const s = await runTransfer(w.deps);
  assert.equal(s.ok, true);
  assert.deepEqual(order(w.calls), [
    'hsf_transfer_mode', 'hsf_sweep_stale_uploads',
    'hsf_scan_claim', 'download', 'hsf_scan_write_back', 'upload', 'hsf_scan_record_clean',
    'hsf_transfer_claim', 'download', 'hsf_transfer_record',
    'hsf_transfer_cleanup_queue',
    'hsf_retention_queue', 'remove', 'hsf_mark_expired',
  ]);
  assert.equal(s.scan.engine, 'fixture');
  assert.deepEqual(s.scan.counts, { clean: 1 });
  assert.equal(s.results[0].action, 'held', 'a clean upload is held in hold mode');
  assert.deepEqual(recordsOf(w.calls)[0], {
    p_result: 'clean', p_upload_id: SCAN_ID, p_engine: `${INSPECT_ENGINE} + fixture + ${CLEAN_ENGINE}`, p_findings: [],
    p_sha256_clean: CLEAN_SHA, p_metadata_removed: [], p_size_bytes: CLEAN_PDF.length,
  });
});

test('scan: without an antivirus engine every scan records error and nothing transfers', async () => {
  const w = scanWorld({});
  const s = await runTransfer(w.deps);
  assert.equal(s.scan.engine, 'none');
  const rec = recordsOf(w.calls)[0];
  assert.equal(rec.p_result, 'error');
  assert.deepEqual(rec.p_findings, [{ code: 'av_not_configured', message: AV_NOT_CONFIGURED }]);
  assert.equal(s.processed, 0, 'the transfer claim handed out nothing');
  assert.ok(!w.calls.some((c) => c[0] === 'rpc' && c[1] === RPC.record));
});

test('scan: a hash mismatch records error before any inspection or antivirus call', async () => {
  let avCalls = 0;
  const avEngine = { kind: 'test', configured: true, async scan() { avCalls++; return { result: 'clean', engine: 'test' }; } };
  for (const over of [{ sha256_client: 'ab'.repeat(32) }, { sha256_server: 'cd'.repeat(32) }, { sha256_client: 'not a hash' }]) {
    const w = scanWorld({ avEngine, scanQueue: [scanRow(over)] });
    const s = await runTransfer(w.deps);
    const rec = recordsOf(w.calls)[0];
    assert.equal(rec.p_result, 'error', JSON.stringify(over));
    assert.deepEqual(rec.p_findings.map((f) => f.code), ['fingerprint_mismatch']);
    assert.equal(s.scan.results[0].action, 'error');
  }
  assert.equal(avCalls, 0);
  // A matching server fingerprint passes.
  const w = scanWorld({ avEngine, scanQueue: [scanRow({ sha256_server: CLEAN_SHA })] });
  await runTransfer(w.deps);
  assert.equal(recordsOf(w.calls)[0].p_result, 'clean');
});

test('scan: a harmful file is recorded harmful with plain findings and never reaches the antivirus engine', async () => {
  let avCalls = 0;
  const avEngine = { kind: 'test', configured: true, async scan() { avCalls++; return { result: 'clean', engine: 'test' }; } };
  const bad = pdf('/OpenAction << /S /JavaScript /JS (x) >>');
  const w = scanWorld({
    avEngine,
    scanQueue: [scanRow({ sha256_client: await sha256Hex(bad) })],
    objects: { [`${ACCOUNT_ID}/${SCAN_ID}/${SAFE_NAME}`]: bad },
  });
  const s = await runTransfer(w.deps);
  const rec = recordsOf(w.calls)[0];
  assert.equal(rec.p_result, 'harmful');
  assert.equal(rec.p_engine, INSPECT_ENGINE);
  assert.deepEqual(rec.p_findings, [{ code: 'pdf_javascript', message: 'The PDF contains JavaScript.' }]);
  assert.equal(avCalls, 0);
  assert.deepEqual(s.scan.results[0].findings, ['pdf_javascript']);
  assert.ok(!JSON.stringify(s).includes(SAFE_NAME), 'the staged file name reached the run report');
});

test('scan: an infected file is recorded infected with the signature; an engine error records error', async () => {
  let avEngine = { kind: 'test', configured: true, async scan() { return { result: 'infected', engine: 'ClamAV 1.4', signature: 'Win.Test.EICAR_HDB-1' }; } };
  let w = scanWorld({ avEngine });
  await runTransfer(w.deps);
  let rec = recordsOf(w.calls)[0];
  assert.equal(rec.p_result, 'infected');
  assert.equal(rec.p_engine, `${INSPECT_ENGINE} + ClamAV 1.4`);
  assert.deepEqual(rec.p_findings, [{ code: 'malware', message: 'The antivirus scan found a known threat (Win.Test.EICAR_HDB-1).' }]);

  avEngine = { kind: 'test', configured: true, async scan() { throw new Error('socket hang up'); } };
  w = scanWorld({ avEngine });
  await runTransfer(w.deps);
  rec = recordsOf(w.calls)[0];
  assert.equal(rec.p_result, 'error');
  assert.deepEqual(rec.p_findings.map((f) => f.code), ['av_error']);
});

test('scan: the antivirus engine over HTTP is wired from the av settings of the run', async () => {
  const f = avFetch(new Response(JSON.stringify({ clean: true, signature: null, engine: 'ClamAV 1.4' }), { status: 200 }));
  const w = scanWorld({ av: { endpoint: AV_URL, token: AV_TOKEN, fetch: f.fetchImpl } });
  const s = await runTransfer(w.deps);
  assert.equal(s.scan.engine, 'http');
  assert.equal(f.calls.length, 1);
  assert.equal(recordsOf(w.calls)[0].p_result, 'clean');
  assert.ok(!JSON.stringify(s).includes(AV_TOKEN));
});

test('scan: an unreadable object or a bad path records error; blocked or wrong status rows are skipped untouched', async () => {
  let w = scanWorld({ allowScanFixture: true, objects: {} });
  let s = await runTransfer(w.deps);
  assert.equal(recordsOf(w.calls)[0].p_result, 'error');
  assert.deepEqual(recordsOf(w.calls)[0].p_findings.map((f) => f.code), ['could_not_inspect']);

  w = scanWorld({ allowScanFixture: true, scanQueue: [scanRow({ storage_path: `${ACCOUNT_ID}/${SECOND_ID}/${SAFE_NAME}` })] });
  s = await runTransfer(w.deps);
  assert.equal(recordsOf(w.calls)[0].p_result, 'error');
  assert.ok(!w.calls.some((c) => c[0] === 'download'));

  const skipped = [
    scanRow({ transfer_blocked_reason: 'consent withdrawn' }),
    scanRow({ status: 'held' }),
    scanRow({ scan_status: 'clean' }),
    scanRow({ id: 'not-a-uuid' }),
  ];
  w = scanWorld({ allowScanFixture: true, scanQueue: skipped });
  s = await runTransfer(w.deps);
  assert.deepEqual(s.scan.counts, { skipped: skipped.length });
  assert.deepEqual(recordsOf(w.calls), []);
  assert.ok(!w.calls.some((c) => c[0] === 'download'));
});

test('scan: one document in memory at a time, and a scan claim failure does not stop the transfer pass', async () => {
  const second = pdf('/Title (Second)');
  const w = scanWorld({
    allowScanFixture: true,
    scanQueue: [scanRow(), scanRow({ id: SECOND_ID, sha256_client: await sha256Hex(second) })],
    objects: { [`${ACCOUNT_ID}/${SCAN_ID}/${SAFE_NAME}`]: CLEAN_PDF, [`${ACCOUNT_ID}/${SECOND_ID}/${SAFE_NAME}`]: second },
  });
  const s = await runTransfer(w.deps);
  assert.deepEqual(s.scan.counts, { clean: 2 });
  assert.equal(w.peak(), 1, 'a second document was downloaded before the first was recorded');
  const scanPart = order(w.calls).slice(order(w.calls).indexOf('hsf_scan_claim') + 1, order(w.calls).indexOf('hsf_transfer_claim'));
  assert.deepEqual(scanPart, ['download', 'hsf_scan_write_back', 'upload', 'hsf_scan_record_clean', 'download', 'hsf_scan_write_back', 'upload', 'hsf_scan_record_clean']);

  const f = scanWorld({ allowScanFixture: true, scanClaimFails: true });
  const r = await runTransfer(f.deps);
  assert.match(r.scan.error, /scan claim could not be read/);
  assert.equal(r.ok, true);
  assert.ok(order(f.calls).includes('hsf_transfer_claim'));
  assert.ok(order(f.calls).includes('hsf_retention_queue'));
});

test('retention: an expired row is deleted, then marked with hsf_mark_expired, blocked or not', async () => {
  const rows = [
    { upload_id: OLD_ID, storage_path: `${ACCOUNT_ID}/${OLD_ID}/${SAFE_NAME}`, reason: 'retention' },
    { upload_id: SECOND_ID, storage_path: `${ACCOUNT_ID}/${SECOND_ID}/${SAFE_NAME}`, reason: 'retention', transfer_blocked_reason: 'consent withdrawn' },
    { upload_id: SCAN_ID, storage_path: `${ACCOUNT_ID}/${OLD_ID}/${SAFE_NAME}`, reason: 'retention' },
  ];
  const w = scanWorld({ allowScanFixture: true, scanQueue: [], retention: rows });
  const s = await runTransfer(w.deps);
  assert.deepEqual(s.retention.counts, { expired: 2, skipped: 1 });
  const tail = w.calls.slice(w.calls.findIndex((c) => c[1] === RPC.retention) + 1);
  assert.deepEqual(tail.map((c) => (c[0] === 'rpc' ? `${c[1]}:${c[2].p_upload_id}` : `${c[0]}:${c[1]}`)), [
    `remove:${rows[0].storage_path}`, `hsf_mark_expired:${OLD_ID}`,
    `remove:${rows[1].storage_path}`, `hsf_mark_expired:${SECOND_ID}`,
  ]);
  for (const c of tail.filter((x) => x[0] === 'remove')) assert.deepEqual(c[2], { allowAbsent: true });
});

test('end to end over REST: the scan pass and the retention pass use the Supabase bindings', async () => {
  const SUPABASE_URL = 'https://unit-test.supabase.invalid';
  const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
  const path = `${ACCOUNT_ID}/${SCAN_ID}/${SAFE_NAME}`;
  const oldPath = `${ACCOUNT_ID}/${OLD_ID}/${SAFE_NAME}`;
  const steps = [];
  const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
  const fetchImpl = async (url, init) => {
    const u = String(url);
    const method = (init && init.method) || 'GET';
    if (u.startsWith(`${SUPABASE_URL}/rest/v1/rpc/`)) {
      const fn = u.split('/rest/v1/rpc/')[1];
      const args = JSON.parse(init.body);
      steps.push(`rpc:${fn}`);
      if (fn === 'hsf_transfer_mode') return json(200, 'hold');
      if (fn === 'hsf_sweep_stale_uploads') return json(200, 0);
      if (fn === 'hsf_scan_claim') return json(200, [scanRow()]);
      if (fn === 'hsf_scan_write_back') {
        assert.equal(args.p_sha256_clean, CLEAN_SHA);
        return json(200, { upload_id: args.p_upload_id, sha256_clean: args.p_sha256_clean });
      }
      if (fn === 'hsf_scan_record_clean') {
        assert.equal(args.p_sha256_clean, CLEAN_SHA);
        return json(200, { upload_id: args.p_upload_id, scan_status: 'clean' });
      }
      if (fn === 'hsf_transfer_claim') return json(200, []);
      if (fn === 'hsf_transfer_cleanup_queue') return json(200, []);
      if (fn === 'hsf_retention_queue') return json(200, [{ upload_id: OLD_ID, storage_path: oldPath, reason: 'retention' }]);
      if (fn === 'hsf_mark_expired') return json(200, { upload_id: args.p_upload_id, status: 'expired' });
      return json(404, { message: 'no such function' });
    }
    if (method === 'GET' && u === `${SUPABASE_URL}/storage/v1/object/${STAGING_BUCKET}/${path}`) {
      steps.push('GET storage');
      return new Response(CLEAN_PDF, { status: 200 });
    }
    if (method === 'POST' && u === `${SUPABASE_URL}/storage/v1/object/${STAGING_BUCKET}/${path}`) {
      steps.push('POST storage');
      assert.equal(init.headers['x-upsert'], 'true');
      assert.equal(init.headers['Content-Type'], MIME.pdf);
      assert.deepEqual(new Uint8Array(init.body), CLEAN_PDF);
      return json(200, { Key: `${STAGING_BUCKET}/${path}` });
    }
    if (method === 'DELETE' && u === `${SUPABASE_URL}/storage/v1/object/${STAGING_BUCKET}`) {
      steps.push('DELETE storage');
      assert.deepEqual(JSON.parse(init.body), { prefixes: [oldPath] });
      return json(200, [{ name: oldPath }]);
    }
    return json(404, { message: 'unexpected call' });
  };
  const io = createSupabaseIo({ url: SUPABASE_URL, serviceKey: SERVICE_KEY, fetch: fetchImpl });
  const s = await runTransfer({ rpc: io.rpc, download: io.download, upload: io.upload, remove: io.remove, createAdapter, allowScanFixture: true });
  assert.deepEqual(steps, [
    'rpc:hsf_transfer_mode', 'rpc:hsf_sweep_stale_uploads', 'rpc:hsf_scan_claim', 'GET storage', 'rpc:hsf_scan_write_back', 'POST storage', 'rpc:hsf_scan_record_clean',
    'rpc:hsf_transfer_claim', 'rpc:hsf_transfer_cleanup_queue', 'rpc:hsf_retention_queue', 'DELETE storage', 'rpc:hsf_mark_expired',
  ]);
  assert.deepEqual(s.retention.counts, { expired: 1 });
  assert.equal(checkStagingPath(scanRow()).ok, true);
});

test('scanUpload: without a path check or an engine it records error, never clean', async () => {
  const calls = [];
  const rpc = async (fn, args) => { calls.push([fn, args]); return {}; };
  let r = await scanUpload(scanRow(), { rpc, download: async () => CLEAN_PDF });
  assert.equal(r.action, 'error');
  assert.equal(calls[0][1].p_result, 'error');
  calls.length = 0;
  r = await scanUpload(scanRow(), { rpc, download: async () => CLEAN_PDF, checkPath: checkStagingPath });
  assert.equal(r.action, 'error');
  assert.deepEqual(calls[0][1].p_findings, [{ code: 'av_not_configured', message: AV_NOT_CONFIGURED }]);
  // Without a way to write the cleaned bytes back it records error, never clean.
  calls.length = 0;
  r = await scanUpload(scanRow(), { rpc, download: async () => CLEAN_PDF, checkPath: checkStagingPath, av: createAvEngine({ allowFixture: true }) });
  assert.equal(r.action, 'error');
  assert.deepEqual(calls.map((c) => c[0]), ['hsf_scan_record']);
  assert.deepEqual(calls[0][1].p_findings.map((f) => f.code), ['write_back_failed']);
  // A record that fails is reported, not hidden.
  r = await scanUpload(scanRow(), {
    rpc: async (fn) => { if (fn === 'hsf_scan_record_clean') throw new Error('hsf_scan_record_clean was refused (HTTP 500)'); return {}; },
    download: async () => CLEAN_PDF, upload: async () => true, checkPath: checkStagingPath, av: createAvEngine({ allowFixture: true }),
  });
  assert.equal(r.action, 'record_failed');
  assert.equal(r.result, 'clean');
});
