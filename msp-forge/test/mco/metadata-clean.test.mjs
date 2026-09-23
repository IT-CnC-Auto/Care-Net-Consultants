// CNC HSF FORGE | tests for the removal of hidden details before a file leaves staging (node --test)
// supabase/functions/_shared/metadata-clean.js  cleanMetadata (contract 11.1)
// supabase/functions/_shared/scan-core.js       scanUpload: structural check, antivirus engine,
//                                               clean, write back, hsf_scan_record_clean
// Every fixture below is built here from bytes: nothing is read from disk and
// nothing touches the network. Names, companies and places in the fixtures are
// invented.

import test from 'node:test';
import assert from 'node:assert/strict';

import { sha256Hex } from '../../supabase/functions/_shared/mco-adapter.js';
import { cleanMetadata, REFUSALS, CLEAN_ENGINE } from '../../supabase/functions/_shared/metadata-clean.js';
import { inspectBytes, scanUpload, createAvEngine, INSPECT_ENGINE } from '../../supabase/functions/_shared/scan-core.js';
import {
  runTransfer, checkStagingPath, RPC, STAGING_BUCKET,
} from '../../supabase/functions/_shared/transfer-core.js';
import { createAdapter } from '../../supabase/functions/_shared/mco-adapter.js';

// 1. Byte builders ----------------------------------------------------------------

const enc = new TextEncoder();
const dec = new TextDecoder();
const text = (s) => enc.encode(s);
const latin = (s) => Uint8Array.from(s, (c) => c.charCodeAt(0) & 0xff);
const asLatin = (b) => Array.from(b, (x) => String.fromCharCode(x)).join('');

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
const rd16le = (b, i) => b[i] | (b[i + 1] << 8);
const rd32le = (b, i) => (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0;
const rd32be = (b, i) => ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0;

function indexOf(hay, needle, from) {
  outer: for (let i = from || 0; i <= hay.length - needle.length; i++) {
    for (let j = 0; j < needle.length; j++) if (hay[i + j] !== needle[j]) continue outer;
    return i;
  }
  return -1;
}
const contains = (hay, s) => indexOf(hay, typeof s === 'string' ? latin(s) : s) !== -1;

async function pipe(bytes, stream) {
  const w = stream.writable.getWriter();
  w.write(bytes);
  w.close();
  return new Uint8Array(await new Response(stream.readable).arrayBuffer());
}
const compress = (bytes, format) => pipe(bytes, new CompressionStream(format));
const decompress = (bytes, format) => pipe(bytes, new DecompressionStream(format));

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

const codes = (r) => r.removed.map((x) => x.code);
const UPLOADED_AT = '2026-09-23T10:15:00+02:00';

// 2. JPEG ------------------------------------------------------------------------------

function seg(marker, body) {
  return concat(Uint8Array.of(0xff, marker), be16(body.length + 2), body);
}

// EXIF body: IFD0 with a GPS pointer and a next directory (IFD1, the
// thumbnail), a GPS directory holding a latitude, and the thumbnail bytes.
function exifWithGpsAndThumbnail() {
  const thumb = Uint8Array.of(0xff, 0xd8, 0xff, 0xd9);
  const tiff = concat(
    latin('II'), le16(42), le32(8),
    le16(1), le16(0x8825), le16(4), le32(1), le32(26), le32(44), // IFD0 at 8, GPS at 26, IFD1 at 44
    le16(1), le16(0x0002), le16(5), le32(3), le32(0), le32(0), // GPS latitude
    le16(2), le16(0x0201), le16(4), le32(1), le32(74), le16(0x0202), le16(4), le32(1), le32(thumb.length), le32(0),
    thumb,
  );
  return concat(latin('Exif\0\0'), tiff);
}

const APP0 = seg(0xe0, concat(latin('JFIF\0'), Uint8Array.of(1, 1, 0, 0, 72, 0, 72, 0, 0)));
const APP2_ICC = seg(0xe2, concat(latin('ICC_PROFILE\0'), Uint8Array.of(1, 1), latin('fake icc profile body for the test')));
const XMP_PACKET = '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF><rdf:Description dc:creator="Thandi Example"'
  + ' exif:GPSLatitude="26,12.3S" exif:GPSLongitude="28,2.5E"/></rdf:RDF></x:xmpmeta>';
const APP1_EXIF = seg(0xe1, exifWithGpsAndThumbnail());
const APP1_XMP = seg(0xe1, concat(latin('http://ns.adobe.com/xap/1.0/\0'), latin(XMP_PACKET)));
const APP13_IPTC = seg(0xed, concat(latin('Photoshop 3.0\0'), latin('8BIM\x04\x04\0\0\0\0\0\x10\x1c\x02\x50\0\x0cThandi Examp')));
const COM = seg(0xfe, latin('Taken on site at Example Mine by the safety officer'));

// The picture itself: tables, frame, Huffman table and scan data with a stuffed
// 0xFF 0x00 and a restart marker inside it.
const PICTURE = concat(
  seg(0xdb, concat(Uint8Array.of(0), new Uint8Array(64).fill(1))),
  seg(0xc0, Uint8Array.of(8, 0, 1, 0, 1, 1, 1, 0x11, 0)),
  seg(0xc4, concat(Uint8Array.of(0), new Uint8Array(16).fill(0), Uint8Array.of())),
  seg(0xda, Uint8Array.of(1, 1, 0, 0, 0x3f, 0)),
  Uint8Array.of(0x12, 0xff, 0x00, 0x34, 0xff, 0xd0, 0x56, 0x78),
  Uint8Array.of(0xff, 0xd9),
);

function jpeg(...segments) {
  return concat(Uint8Array.of(0xff, 0xd8), ...segments, PICTURE);
}

// Walks the markers of a JPEG up to the scan and returns them in order.
function jpegMarkers(b) {
  const out = [];
  let i = 2;
  while (i < b.length) {
    const m = b[i + 1];
    out.push(m);
    if (m === 0xda) break;
    i += 2 + ((b[i + 2] << 8) | b[i + 3]);
  }
  return out;
}

test('JPEG: EXIF with GPS and a thumbnail, XMP, IPTC and COM all go; APP0, ICC and the picture data stay byte for byte', async () => {
  const input = jpeg(APP0, APP1_EXIF, APP1_XMP, APP2_ICC, APP13_IPTC, COM);
  const before = await inspectBytes({ bytes: input, mimeType: MIME.jpeg, fileName: 'site.jpg' });
  assert.equal(before.verdict, 'harmful', 'the fixture carries GPS, which the structural check flags');

  const r = await cleanMetadata({ bytes: input, mimeType: MIME.jpeg, fileName: 'site.jpg' });
  assert.equal(r.outcome, 'cleaned');
  assert.equal(r.reason, null);
  assert.deepEqual(codes(r), ['location', 'comments', 'camera', 'thumbnail', 'xmp', 'iptc']);
  for (const x of r.removed) assert.equal(typeof x.message, 'string');
  assert.equal(r.removed.find((x) => x.code === 'location').message, 'location');

  const out = r.bytes;
  assert.deepEqual(out, concat(Uint8Array.of(0xff, 0xd8), APP0, APP2_ICC, PICTURE));
  assert.deepEqual(jpegMarkers(out), [0xe0, 0xe2, 0xdb, 0xc0, 0xc4, 0xda]);
  for (const gone of ['Exif', 'http://ns.adobe.com', 'Photoshop', 'Thandi', 'Example Mine', 'GPS']) {
    assert.ok(!contains(out, gone), `${gone} survived`);
  }
  // The picture data is identical, and the cleaned file passes the structural check.
  assert.deepEqual(out.subarray(out.length - PICTURE.length), PICTURE);
  assert.deepEqual(await inspectBytes({ bytes: out, mimeType: MIME.jpeg, fileName: 'site.jpg' }), { verdict: 'clean', findings: [] });
});

test('JPEG: a JFIF thumbnail is cleared, JFXX and MPF go, the Adobe colour segment stays, and data after the end marker goes', async () => {
  const jfifThumb = seg(0xe0, concat(latin('JFIF\0'), Uint8Array.of(1, 2, 0, 0, 1, 0, 1, 1, 1), Uint8Array.of(9, 9, 9)));
  const jfxx = seg(0xe0, concat(latin('JFXX\0'), Uint8Array.of(0x10), new Uint8Array(20)));
  const mpf = seg(0xe2, concat(latin('MPF\0'), new Uint8Array(20)));
  const adobe = seg(0xee, concat(latin('Adobe'), Uint8Array.of(0, 100, 0, 0, 0, 0, 1)));
  const input = concat(jpeg(jfifThumb, jfxx, mpf, adobe), latin('hidden trailing bytes'));
  const r = await cleanMetadata({ bytes: input, mimeType: MIME.jpeg });
  assert.equal(r.outcome, 'cleaned');
  assert.deepEqual(codes(r), ['thumbnail', 'other', 'trailing_data']);
  const expectedApp0 = seg(0xe0, concat(latin('JFIF\0'), Uint8Array.of(1, 2, 0, 0, 1, 0, 1, 0, 0)));
  assert.deepEqual(r.bytes, concat(Uint8Array.of(0xff, 0xd8), expectedApp0, adobe, PICTURE));
});

test('JPEG: a progressive file keeps every scan; metadata between scans goes', async () => {
  const scan2 = concat(seg(0xc4, new Uint8Array(17)), COM, seg(0xda, Uint8Array.of(1, 1, 0, 1, 0x3f, 0)), Uint8Array.of(0x9a, 0xff, 0x00, 0xbc));
  const head = concat(Uint8Array.of(0xff, 0xd8), APP0,
    seg(0xdb, concat(Uint8Array.of(0), new Uint8Array(64).fill(1))),
    seg(0xc2, Uint8Array.of(8, 0, 1, 0, 1, 1, 1, 0x11, 0)),
    seg(0xda, Uint8Array.of(1, 1, 0, 0, 0x3f, 0)), Uint8Array.of(0x11, 0x22));
  const input = concat(head, scan2, Uint8Array.of(0xff, 0xd9));
  const r = await cleanMetadata({ bytes: input, mimeType: MIME.jpeg });
  assert.equal(r.outcome, 'cleaned');
  assert.deepEqual(codes(r), ['comments']);
  assert.deepEqual(r.bytes, concat(head, seg(0xc4, new Uint8Array(17)), seg(0xda, Uint8Array.of(1, 1, 0, 1, 0x3f, 0)), Uint8Array.of(0x9a, 0xff, 0x00, 0xbc, 0xff, 0xd9)));
});

test('JPEG: a picture without hidden details is unchanged and returned as it is', async () => {
  const input = jpeg(APP0, APP2_ICC);
  const r = await cleanMetadata({ bytes: input, mimeType: MIME.jpeg });
  assert.equal(r.outcome, 'unchanged');
  assert.equal(r.bytes, input);
  assert.deepEqual(r.removed, []);
});

test('JPEG: a JFIF segment carrying bytes after its header is cut back to the header, whatever thumbnail size it states', async () => {
  const padded = seg(0xe0, concat(latin('JFIF\0'), Uint8Array.of(1, 1, 0, 0, 1, 0, 1, 0, 0), latin('Owner: Thandi Example; GPS -33.9249,18.4241')));
  const r = await cleanMetadata({ bytes: jpeg(padded, APP2_ICC), mimeType: MIME.jpeg });
  assert.equal(r.outcome, 'cleaned');
  assert.deepEqual(codes(r), ['other']);
  assert.deepEqual(r.bytes, jpeg(seg(0xe0, concat(latin('JFIF\0'), Uint8Array.of(1, 1, 0, 0, 1, 0, 1, 0, 0))), APP2_ICC));
  assert.ok(!contains(r.bytes, 'Thandi'));
});

// 3. PNG -------------------------------------------------------------------------------

function pngChunk(type, data) {
  const t = latin(type);
  return concat(be32(data.length), t, data, be32(crc32(concat(t, data))));
}
const PNG_SIG = Uint8Array.of(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a);
const IHDR = pngChunk('IHDR', concat(be32(1), be32(1), Uint8Array.of(8, 2, 0, 0, 0)));
// A real 1 by 1 red pixel: filter byte 0, then RGB.
const IDAT_DATA = await compress(Uint8Array.of(0, 255, 0, 0), 'deflate');
const IDAT = pngChunk('IDAT', IDAT_DATA);
const IEND = pngChunk('IEND', new Uint8Array(0));
const GAMA = pngChunk('gAMA', be32(45455));
const PHYS = pngChunk('pHYs', concat(be32(2835), be32(2835), Uint8Array.of(1)));

// Every chunk of a PNG as { type, data, crcOk }.
function pngChunks(b) {
  assert.deepEqual(b.subarray(0, 8), PNG_SIG);
  const out = [];
  let i = 8;
  while (i < b.length) {
    const len = rd32be(b, i);
    const type = asLatin(b.subarray(i + 4, i + 8));
    const data = b.subarray(i + 8, i + 8 + len);
    out.push({ type, data, crcOk: crc32(b.subarray(i + 4, i + 8 + len)) === rd32be(b, i + 8 + len) });
    i += 12 + len;
    if (type === 'IEND') break;
  }
  assert.equal(i, b.length, 'bytes after IEND');
  return out;
}

test('PNG: tEXt, iTXt, eXIf, tIME and private chunks go; IDAT is identical and every kept CRC is valid', async () => {
  const input = concat(
    PNG_SIG, IHDR, GAMA,
    pngChunk('tEXt', latin('Author\0Thandi Example')),
    pngChunk('iTXt', concat(latin('XML:com.adobe.xmp\0\0\0\0\0'), text(XMP_PACKET))),
    pngChunk('eXIf', exifWithGpsAndThumbnail().subarray(6)),
    pngChunk('tIME', Uint8Array.of(0x07, 0xea, 9, 23, 10, 15, 0)),
    pngChunk('prVt', latin('private application data')),
    PHYS, IDAT, IEND,
  );
  const r = await cleanMetadata({ bytes: input, mimeType: MIME.png });
  assert.equal(r.outcome, 'cleaned');
  assert.deepEqual(codes(r), ['author', 'location', 'camera', 'thumbnail', 'xmp', 'dates', 'other']);
  const chunks = pngChunks(r.bytes);
  assert.deepEqual(chunks.map((c) => c.type), ['IHDR', 'gAMA', 'pHYs', 'IDAT', 'IEND']);
  for (const c of chunks) assert.ok(c.crcOk, `${c.type} CRC`);
  assert.deepEqual(chunks[3].data, IDAT_DATA);
  assert.deepEqual(await decompress(chunks[3].data, 'deflate'), Uint8Array.of(0, 255, 0, 0));
  assert.deepEqual(r.bytes, concat(PNG_SIG, IHDR, GAMA, PHYS, IDAT, IEND));
  assert.ok(!contains(r.bytes, 'Thandi'));
  assert.deepEqual(await inspectBytes({ bytes: r.bytes, mimeType: MIME.png, fileName: 'plan.png' }), { verdict: 'clean', findings: [] });
});

test('PNG: an unknown critical chunk or a damaged kept chunk is refused; a plain PNG is unchanged', async () => {
  let r = await cleanMetadata({ bytes: concat(PNG_SIG, IHDR, pngChunk('ABCD', new Uint8Array(4)), IDAT, IEND), mimeType: MIME.png });
  assert.equal(r.outcome, 'refused');
  assert.equal(r.bytes, null);
  assert.equal(r.reason, REFUSALS.unreadable);

  const badIdat = IDAT.slice();
  badIdat[badIdat.length - 1] ^= 0xff;
  r = await cleanMetadata({ bytes: concat(PNG_SIG, IHDR, badIdat, IEND), mimeType: MIME.png });
  assert.equal(r.outcome, 'refused');

  const plain = concat(PNG_SIG, IHDR, IDAT, IEND);
  r = await cleanMetadata({ bytes: plain, mimeType: MIME.png });
  assert.equal(r.outcome, 'unchanged');
  assert.equal(r.bytes, plain);
});

// 4. OOXML ------------------------------------------------------------------------------

// A real zip archive: local headers, central directory and end record. method 0
// stores, method 8 deflates. Entry dates and an extra field are written so the
// test can see they are cleared.
async function buildZip(entries, opts) {
  const o = opts || {};
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const e of entries) {
    const name = text(e.name);
    const raw = typeof e.data === 'string' ? text(e.data) : e.data;
    const method = e.method ?? 8;
    const data = e.packed ?? (method === 8 ? await compress(raw, 'deflate-raw') : raw);
    const flags = e.flags ?? 0;
    const crc = e.crc ?? crc32(raw);
    const usize = e.usize ?? raw.length;
    const extra = concat(le16(0x5455), le16(5), Uint8Array.of(1), le32(1790000000));
    const local = concat(le32(0x04034b50), le16(20), le16(flags), le16(method), le16(0x6000), le16(0x5b37),
      le32(crc), le32(data.length), le32(usize), le16(name.length), le16(extra.length), name, extra, data);
    centrals.push(concat(le32(0x02014b50), le16(20), le16(20), le16(flags), le16(method), le16(0x6000), le16(0x5b37),
      le32(crc), le32(data.length), le32(usize), le16(name.length), le16(extra.length), le16(0), le16(0), le16(0),
      le32(0), le32(offset), name, extra));
    locals.push(local);
    offset += local.length;
  }
  const cd = concat(...centrals);
  const comment = latin(o.comment || '');
  const end = concat(le32(0x06054b50), le16(0), le16(0), le16(entries.length), le16(entries.length),
    le32(cd.length), le32(offset), le16(comment.length), comment);
  return concat(...locals, cd, end);
}

// Reopens a zip strictly: every central entry must match its local header, and
// every part must inflate to its recorded size and CRC. Returns name → { raw,
// packed, method }.
async function openZip(b) {
  let eocd = -1;
  for (let i = b.length - 22; i >= 0; i--) if (rd32le(b, i) === 0x06054b50) { eocd = i; break; }
  assert.ok(eocd >= 0, 'no end record');
  const count = rd16le(b, eocd + 10);
  const cdSize = rd32le(b, eocd + 12);
  const cdOffset = rd32le(b, eocd + 16);
  assert.equal(cdOffset + cdSize, eocd, 'the central directory does not end at the end record');
  const parts = new Map();
  let p = cdOffset;
  let expectLocal = 0;
  for (let k = 0; k < count; k++) {
    assert.equal(rd32le(b, p), 0x02014b50);
    const flags = rd16le(b, p + 8);
    const method = rd16le(b, p + 10);
    const time = rd16le(b, p + 12);
    const date = rd16le(b, p + 14);
    const crc = rd32le(b, p + 16);
    const csize = rd32le(b, p + 20);
    const usize = rd32le(b, p + 24);
    const nl = rd16le(b, p + 28);
    const xl = rd16le(b, p + 30);
    const cl = rd16le(b, p + 32);
    const local = rd32le(b, p + 42);
    const name = dec.decode(b.subarray(p + 46, p + 46 + nl));
    assert.equal(local, expectLocal, `${name}: local headers are not packed in order`);
    assert.equal(rd32le(b, local), 0x04034b50);
    assert.equal(rd16le(b, local + 6), flags, `${name}: flags`);
    assert.equal(rd16le(b, local + 8), method, `${name}: method`);
    assert.equal(rd32le(b, local + 14), crc, `${name}: local CRC`);
    assert.equal(rd32le(b, local + 18), csize, `${name}: local compressed size`);
    assert.equal(rd32le(b, local + 22), usize, `${name}: local size`);
    const lnl = rd16le(b, local + 26);
    const lxl = rd16le(b, local + 28);
    assert.equal(dec.decode(b.subarray(local + 30, local + 30 + lnl)), name);
    const start = local + 30 + lnl + lxl;
    const packed = b.subarray(start, start + csize);
    const raw = method === 8 ? await decompress(packed, 'deflate-raw') : packed;
    assert.equal(raw.length, usize, `${name}: size`);
    assert.equal(crc32(raw), crc, `${name}: CRC`);
    parts.set(name, { raw, packed, method, flags, time, date, extra: xl, comment: cl });
    expectLocal = start + csize;
    p += 46 + nl + xl + cl;
  }
  assert.equal(expectLocal, cdOffset, 'bytes between the parts and the central directory');
  return parts;
}

const CORE_XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
  + '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"'
  + ' xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
  + '<dc:title>Risk assessment, Example Mine</dc:title><dc:subject>Shaft 3</dc:subject><dc:creator>Thandi Example</dc:creator>'
  + '<cp:keywords>noise</cp:keywords><cp:lastModifiedBy>Pieter Sample</cp:lastModifiedBy><cp:revision>14</cp:revision>'
  + '<dcterms:created xsi:type="dcterms:W3CDTF">2025-02-01T08:12:00Z</dcterms:created>'
  + '<dcterms:modified xsi:type="dcterms:W3CDTF">2026-09-20T16:40:00Z</dcterms:modified></cp:coreProperties>';
const APP_XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
  + '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
  + '<Template>Example Holdings Letter.dotm</Template><TotalTime>42</TotalTime><Application>Microsoft Office Word</Application>'
  + '<Company>Example Holdings (Pty) Ltd</Company><Manager>Sipho Placeholder</Manager>'
  + '<HyperlinkBase>https://intranet.example.invalid/</HyperlinkBase><AppVersion>16.0000</AppVersion></Properties>';
const CUSTOM_XML = '<?xml version="1.0"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties">'
  + '<property name="Client"><vt:lpwstr>Example Holdings</vt:lpwstr></property></Properties>';
const REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const PKG_NS = 'http://schemas.openxmlformats.org/package/2006/relationships';

const DOCX_TYPES = '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
  + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
  + '<Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/>'
  + '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
  + '<Override PartName="/word/comments.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/>'
  + '<Override PartName="/word/commentsExtended.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml"/>'
  + '<Override PartName="/word/people.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.people+xml"/>'
  + '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
  + '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
  + '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
  + '<Override PartName="/docProps/custom.xml" ContentType="application/vnd.openxmlformats-officedocument.custom-properties+xml"/></Types>';
const ROOT_RELS = `<?xml version="1.0"?><Relationships xmlns="${PKG_NS}">`
  + `<Relationship Id="rId3" Type="${REL_NS}/extended-properties" Target="docProps/app.xml"/>`
  + '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
  + '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="docProps/thumbnail.jpeg"/>'
  + `<Relationship Id="rId1" Type="${REL_NS}/officeDocument" Target="word/document.xml"/>`
  + `<Relationship Id="rId5" Type="${REL_NS}/custom-properties" Target="/docProps/custom.xml"/></Relationships>`;
const DOCUMENT_XML = '<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
  + '<w:p><w:commentRangeStart w:id="0"/><w:r><w:t>Noise survey of the plant floor</w:t></w:r><w:commentRangeEnd w:id="0"/>'
  + '<w:r><w:commentReference w:id="0"/></w:r></w:p></w:body></w:document>';
const DOCUMENT_RELS = `<?xml version="1.0"?><Relationships xmlns="${PKG_NS}">`
  + `<Relationship Id="rId1" Type="${REL_NS}/styles" Target="styles.xml"/>`
  + `<Relationship Id="rId2" Type="${REL_NS}/comments" Target="comments.xml"/>`
  + '<Relationship Id="rId3" Type="http://schemas.microsoft.com/office/2011/relationships/commentsExtended" Target="commentsExtended.xml"/>'
  + '<Relationship Id="rId4" Type="http://schemas.microsoft.com/office/2011/relationships/people" Target="./people.xml"/>'
  + `<Relationship Id="rId5" Type="${REL_NS}/hyperlink" Target="https://www.gov.za/documents/occupational-health-and-safety-act" TargetMode="External"/>`
  + '</Relationships>';

async function docxFixture() {
  return buildZip([
    { name: '[Content_Types].xml', data: DOCX_TYPES },
    { name: '_rels/.rels', data: ROOT_RELS },
    { name: 'word/document.xml', data: DOCUMENT_XML },
    { name: 'word/_rels/document.xml.rels', data: DOCUMENT_RELS },
    { name: 'word/styles.xml', data: '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"/>', method: 0 },
    { name: 'word/comments.xml', data: '<w:comments><w:comment w:id="0" w:author="Pieter Sample" w:initials="PS"><w:p><w:r><w:t>Check the shaft 3 readings</w:t></w:r></w:p></w:comment></w:comments>' },
    { name: 'word/_rels/comments.xml.rels', data: `<?xml version="1.0"?><Relationships xmlns="${PKG_NS}"></Relationships>` },
    { name: 'word/commentsExtended.xml', data: '<w15:commentsEx/>' },
    { name: 'word/people.xml', data: '<w15:people><w15:person w15:author="Pieter Sample"/></w15:people>' },
    { name: 'docProps/core.xml', data: CORE_XML },
    { name: 'docProps/app.xml', data: APP_XML },
    { name: 'docProps/custom.xml', data: CUSTOM_XML },
    { name: 'docProps/thumbnail.jpeg', data: jpeg(APP0), method: 0 },
  ], { comment: 'Made by Thandi Example' });
}

test('docx: custom properties, thumbnail, comments and people go; core and app are stripped; the zip reopens and the document part is unchanged', async () => {
  const input = await docxFixture();
  const inParts = await openZip(input);
  const r = await cleanMetadata({ bytes: input, mimeType: MIME.docx, fileName: 'Noise_survey.docx', uploadedAt: UPLOADED_AT });
  assert.equal(r.outcome, 'cleaned');
  assert.deepEqual(codes(r), ['author', 'company', 'manager', 'title', 'comments', 'people', 'thumbnail', 'custom', 'template', 'hyperlink_base', 'revision', 'dates']);

  const parts = await openZip(r.bytes);
  assert.deepEqual([...parts.keys()], [
    '[Content_Types].xml', '_rels/.rels', 'word/document.xml', 'word/_rels/document.xml.rels', 'word/styles.xml',
    'docProps/core.xml', 'docProps/app.xml',
  ]);
  // The document part is copied byte for byte, compressed as it was.
  assert.deepEqual(parts.get('word/document.xml').packed, inParts.get('word/document.xml').packed);
  assert.equal(dec.decode(parts.get('word/document.xml').raw), DOCUMENT_XML);
  assert.deepEqual(parts.get('word/styles.xml').raw, inParts.get('word/styles.xml').raw);
  assert.equal(parts.get('word/styles.xml').method, 0);
  // Entry dates, extra fields and the archive comment are cleared.
  for (const [name, part] of parts) {
    assert.equal(part.time, 0, name);
    assert.equal(part.date, 0x21, name);
    assert.equal(part.extra, 0, name);
  }
  assert.equal(rd16le(r.bytes, r.bytes.length - 2), 0, 'archive comment');

  const core = dec.decode(parts.get('docProps/core.xml').raw);
  for (const gone of ['creator', 'lastModifiedBy', 'title', 'subject', 'keywords', 'revision', 'Thandi', 'Pieter', 'Example Mine', '2025-02-01']) {
    assert.ok(!core.includes(gone), `core.xml still holds ${gone}`);
  }
  assert.match(core, /<dcterms:created xsi:type="dcterms:W3CDTF">2026-09-23T00:00:00Z<\/dcterms:created>/);
  assert.match(core, /<dcterms:modified xsi:type="dcterms:W3CDTF">2026-09-23T00:00:00Z<\/dcterms:modified>/);

  const app = dec.decode(parts.get('docProps/app.xml').raw);
  for (const gone of ['Company', 'Manager', 'HyperlinkBase', 'Template', 'Example Holdings', 'Sipho']) assert.ok(!app.includes(gone), `app.xml still holds ${gone}`);
  assert.match(app, /<Application>Microsoft Office Word<\/Application>/);
  assert.match(app, /<TotalTime>42<\/TotalTime>/);

  const types = dec.decode(parts.get('[Content_Types].xml').raw);
  for (const gone of ['/word/comments.xml', '/word/commentsExtended.xml', '/word/people.xml', '/docProps/custom.xml']) assert.ok(!types.includes(gone), gone);
  for (const kept of ['/word/document.xml', '/word/styles.xml', '/docProps/core.xml', '/docProps/app.xml', 'Extension="jpeg"']) assert.ok(types.includes(kept), kept);

  const rootRels = dec.decode(parts.get('_rels/.rels').raw);
  assert.ok(!rootRels.includes('thumbnail.jpeg') && !rootRels.includes('custom.xml'));
  assert.ok(rootRels.includes('word/document.xml') && rootRels.includes('docProps/core.xml') && rootRels.includes('docProps/app.xml'));
  const docRels = dec.decode(parts.get('word/_rels/document.xml.rels').raw);
  assert.ok(!/comments|people/.test(docRels.replace(/Type="[^"]*"/g, '')), docRels);
  assert.ok(!docRels.includes('rId2') && !docRels.includes('rId3') && !docRels.includes('rId4'));
  assert.ok(docRels.includes('styles.xml'));
  assert.ok(docRels.includes('TargetMode="External"'), 'a web hyperlink is not metadata and stays');

  // The scan still reads the cleaned file as a clean Word document.
  assert.deepEqual(await inspectBytes({ bytes: r.bytes, mimeType: MIME.docx, fileName: 'Noise_survey.docx' }), { verdict: 'clean', findings: [] });
});

test('xlsx: comments, threaded comments and persons go with their relationships; the worksheet is unchanged byte for byte', async () => {
  const sheet = '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c></row></sheetData><legacyDrawing r:id="rId2"/></worksheet>';
  const input = await buildZip([
    { name: '[Content_Types].xml', data: '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      + '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      + '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      + '<Override PartName="/xl/comments1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml"/>'
      + '<Override PartName="/xl/threadedComments/threadedComment1.xml" ContentType="application/vnd.ms-excel.threadedcomments+xml"/>'
      + '<Override PartName="/xl/persons/person.xml" ContentType="application/vnd.ms-excel.person+xml"/>'
      + '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      + '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>' },
    { name: '_rels/.rels', data: `<Relationships xmlns="${PKG_NS}"><Relationship Id="rId1" Type="${REL_NS}/officeDocument" Target="xl/workbook.xml"/>`
      + '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      + `<Relationship Id="rId3" Type="${REL_NS}/extended-properties" Target="docProps/app.xml"/></Relationships>` },
    { name: 'xl/workbook.xml', data: '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheets><sheet name="Register" sheetId="1" r:id="rId1"/></sheets></workbook>' },
    { name: 'xl/_rels/workbook.xml.rels', data: `<Relationships xmlns="${PKG_NS}"><Relationship Id="rId1" Type="${REL_NS}/worksheet" Target="worksheets/sheet1.xml"/>`
      + '<Relationship Id="rId9" Type="http://schemas.microsoft.com/office/2017/10/relationships/person" Target="persons/person.xml"/></Relationships>' },
    { name: 'xl/worksheets/sheet1.xml', data: sheet },
    { name: 'xl/worksheets/_rels/sheet1.xml.rels', data: `<Relationships xmlns="${PKG_NS}">`
      + `<Relationship Id="rId1" Type="${REL_NS}/comments" Target="../comments1.xml"/>`
      + `<Relationship Id="rId2" Type="${REL_NS}/vmlDrawing" Target="../drawings/vmlDrawing1.vml"/>`
      + '<Relationship Id="rId3" Type="http://schemas.microsoft.com/office/2017/10/relationships/threadedComment" Target="../threadedComments/threadedComment1.xml"/>'
      + '</Relationships>' },
    { name: 'xl/drawings/vmlDrawing1.vml', data: '<xml><v:shape/></xml>' },
    { name: 'xl/comments1.xml', data: '<comments><authors><author>Pieter Sample</author></authors></comments>' },
    { name: 'xl/threadedComments/threadedComment1.xml', data: '<ThreadedComments><threadedComment personId="{1}"><text>Recheck</text></threadedComment></ThreadedComments>' },
    { name: 'xl/persons/person.xml', data: '<personList><person displayName="Pieter Sample" userId="pieter@example.invalid"/></personList>' },
    { name: 'docProps/core.xml', data: CORE_XML },
    { name: 'docProps/app.xml', data: APP_XML.replace('Microsoft Office Word', 'Microsoft Excel') },
    { name: 'docProps/custom.xml', data: CUSTOM_XML },
  ]);
  const before = await openZip(input);
  const r = await cleanMetadata({ bytes: input, mimeType: MIME.xlsx, uploadedAt: UPLOADED_AT });
  assert.equal(r.outcome, 'cleaned');
  for (const c of ['author', 'company', 'comments', 'people', 'custom']) assert.ok(codes(r).includes(c), c);
  const parts = await openZip(r.bytes);
  for (const gone of ['xl/comments1.xml', 'xl/threadedComments/threadedComment1.xml', 'xl/persons/person.xml', 'docProps/custom.xml']) assert.ok(!parts.has(gone), gone);
  assert.deepEqual(parts.get('xl/worksheets/sheet1.xml').packed, before.get('xl/worksheets/sheet1.xml').packed);
  assert.equal(dec.decode(parts.get('xl/worksheets/sheet1.xml').raw), sheet);
  assert.deepEqual(parts.get('xl/drawings/vmlDrawing1.vml').packed, before.get('xl/drawings/vmlDrawing1.vml').packed);
  const sheetRels = dec.decode(parts.get('xl/worksheets/_rels/sheet1.xml.rels').raw);
  assert.ok(sheetRels.includes('vmlDrawing1.vml'));
  assert.ok(!sheetRels.includes('comments1.xml') && !sheetRels.includes('threadedComment1.xml'));
  const wbRels = dec.decode(parts.get('xl/_rels/workbook.xml.rels').raw);
  assert.ok(!wbRels.includes('person.xml') && wbRels.includes('worksheets/sheet1.xml'));
  const types = dec.decode(parts.get('[Content_Types].xml').raw);
  assert.ok(!/comments1|threadedComment1|person\.xml/.test(types));
  for (const [name, part] of parts) assert.ok(!dec.decode(part.raw).includes('Pieter'), `a reviewer name survived in ${name}`);
  assert.deepEqual(await inspectBytes({ bytes: r.bytes, mimeType: MIME.xlsx, fileName: 'Register.xlsx' }), { verdict: 'clean', findings: [] });
});

test('OOXML: core, custom and thumbnail parts are found through the package relationships wherever they sit', async () => {
  const input = await buildZip([
    { name: '[Content_Types].xml', data: DOCX_TYPES.replace('/docProps/core.xml', '/props/core.xml') },
    { name: '_rels/.rels', data: `<?xml version="1.0"?><Relationships xmlns="${PKG_NS}">`
      + '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="props/core.xml"/>'
      + `<Relationship Id="rId3" Type="${REL_NS}/extended-properties" Target="/props/app.xml"/>`
      + `<Relationship Id="rId4" Type="${REL_NS}/custom-properties" Target="props/extra.xml"/>`
      + '<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="props/pic.jpeg"/>'
      + `<Relationship Id="rId1" Type="${REL_NS}/officeDocument" Target="word/document.xml"/></Relationships>` },
    { name: 'word/document.xml', data: DOCUMENT_XML },
    { name: 'props/core.xml', data: CORE_XML },
    { name: 'props/app.xml', data: APP_XML },
    { name: 'props/extra.xml', data: CUSTOM_XML },
    { name: 'props/pic.jpeg', data: jpeg(APP0), method: 0 },
  ]);
  const r = await cleanMetadata({ bytes: input, mimeType: MIME.docx, uploadedAt: UPLOADED_AT });
  assert.equal(r.outcome, 'cleaned');
  for (const c of ['author', 'company', 'title', 'thumbnail', 'custom']) assert.ok(codes(r).includes(c), c);
  const parts = await openZip(r.bytes);
  assert.deepEqual([...parts.keys()], ['[Content_Types].xml', '_rels/.rels', 'word/document.xml', 'props/core.xml', 'props/app.xml']);
  const core = dec.decode(parts.get('props/core.xml').raw);
  assert.ok(!/Thandi|Pieter|Example Mine/.test(core), core);
  assert.match(core, /2026-09-23T00:00:00Z/);
  assert.ok(!dec.decode(parts.get('props/app.xml').raw).includes('Example Holdings'));
  const rels = dec.decode(parts.get('_rels/.rels').raw);
  assert.ok(!rels.includes('extra.xml') && !rels.includes('pic.jpeg') && rels.includes('props/core.xml'));
});

test('OOXML: a picture inside the document loses its location and camera details, as a picture uploaded on its own does', async () => {
  const photo = jpeg(APP0, APP1_EXIF, APP1_XMP, APP2_ICC);
  const png = concat(PNG_SIG, IHDR, pngChunk('tEXt', latin('Author\0Thandi Example')), IDAT, IEND);
  const input = await buildZip([
    { name: '[Content_Types].xml', data: DOCX_TYPES },
    { name: '_rels/.rels', data: ROOT_RELS },
    { name: 'word/document.xml', data: DOCUMENT_XML },
    { name: 'word/media/image1.jpeg', data: photo, method: 0 },
    { name: 'word/media/image2.png', data: png },
    { name: 'word/media/image3.bin', data: photo },
  ]);
  const r = await cleanMetadata({ bytes: input, mimeType: MIME.docx, uploadedAt: UPLOADED_AT });
  assert.equal(r.outcome, 'cleaned');
  for (const c of ['author', 'location', 'camera', 'xmp']) assert.ok(codes(r).includes(c), c);
  const parts = await openZip(r.bytes);
  assert.deepEqual(parts.get('word/media/image1.jpeg').raw, jpeg(APP0, APP2_ICC));
  assert.deepEqual(parts.get('word/media/image3.bin').raw, jpeg(APP0, APP2_ICC), 'a picture under another name kept its details');
  assert.deepEqual(parts.get('word/media/image2.png').raw, concat(PNG_SIG, IHDR, IDAT, IEND));
  // A picture that cannot be read is refused, never passed.
  const broken = await buildZip([{ name: '[Content_Types].xml', data: DOCX_TYPES }, { name: 'word/document.xml', data: DOCUMENT_XML },
    { name: 'word/media/image1.jpeg', data: concat(Uint8Array.of(0xff, 0xd8), APP1_EXIF) }]);
  assert.equal((await cleanMetadata({ bytes: broken, mimeType: MIME.docx })).outcome, 'refused');
});

test('OOXML: an element never closed in core.xml or app.xml costs one pass and is refused, not scanned again for each element', async () => {
  for (const [name, xml] of [
    ['docProps/core.xml', CORE_XML.replace('</cp:coreProperties>', `${'<a>'.repeat(80000)}</cp:coreProperties>`)],
    ['docProps/app.xml', APP_XML.replace('</Properties>', `${'<Company>'.repeat(80000)}</Properties>`)],
  ]) {
    const input = await buildZip([{ name: '[Content_Types].xml', data: DOCX_TYPES }, { name: 'word/document.xml', data: DOCUMENT_XML }, { name, data: xml }]);
    const t = Date.now();
    const r = await cleanMetadata({ bytes: input, mimeType: MIME.docx });
    assert.ok(Date.now() - t < 2000, `${name} took ${Date.now() - t} ms`);
    assert.equal(r.outcome, 'refused', name);
    assert.equal(r.reason, REFUSALS.unreadable);
  }
});

test('OOXML: no zip bomb expansion, and damaged, encrypted or zip64 archives are refused, never passed', async () => {
  // A part that claims 1 000 bytes but inflates to 8 MB stops at the claim.
  const zeros = new Uint8Array(8 * 1024 * 1024);
  const bomb = await buildZip([
    { name: '[Content_Types].xml', data: DOCX_TYPES },
    { name: 'word/document.xml', data: zeros, usize: 1000, crc: 0 },
  ]);
  let r = await cleanMetadata({ bytes: bomb, mimeType: MIME.docx });
  assert.equal(r.outcome, 'refused');
  assert.equal(r.bytes, null);

  // Parts that claim more than the cap in total are refused before anything is inflated.
  const huge = await buildZip([
    { name: 'a.bin', data: new Uint8Array(4), usize: 200 * 1024 * 1024 },
    { name: 'b.bin', data: new Uint8Array(4), usize: 200 * 1024 * 1024 },
  ]);
  r = await cleanMetadata({ bytes: huge, mimeType: MIME.docx });
  assert.equal(r.outcome, 'refused');

  const good = await docxFixture();
  const cases = {
    encrypted: await buildZip([{ name: 'word/document.xml', data: DOCUMENT_XML, flags: 1 }]),
    unknownMethod: await buildZip([{ name: 'word/document.xml', data: DOCUMENT_XML, method: 12 }]),
    badCrc: await buildZip([{ name: '[Content_Types].xml', data: DOCX_TYPES }, { name: 'word/document.xml', data: DOCUMENT_XML, crc: 1 }]),
    truncated: good.subarray(0, good.length - 30),
    noDirectory: good.subarray(0, 200),
    zip64: (() => {
      const b = good.slice();
      const at = indexOf(b, le32(0x06054b50), b.length - 22 - 40);
      b.set(le16(0xffff), at + 8);
      b.set(le16(0xffff), at + 10);
      return b;
    })(),
    notAZip: text('just some text pretending to be a Word file'),
  };
  for (const [name, bytes] of Object.entries(cases)) {
    r = await cleanMetadata({ bytes, mimeType: MIME.docx });
    assert.equal(r.outcome, 'refused', name);
    assert.equal(r.bytes, null, name);
    assert.equal(r.reason, REFUSALS.unreadable, name);
  }
});

// 5. PDF -----------------------------------------------------------------------------------

// Writes numbered objects with a correct cross reference table and trailer.
function pdfFile(objects, trailerExtra) {
  let body = '%PDF-1.7\n%\xe2\xe3\xcf\xd3\n';
  const offsets = [];
  for (let k = 0; k < objects.length; k++) {
    offsets.push(body.length);
    body += `${k + 1} 0 obj\n${objects[k]}\nendobj\n`;
  }
  const xref = body.length;
  body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const o of offsets) body += `${String(o).padStart(10, '0')} 00000 n \n`;
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R ${trailerExtra || ''} >>\nstartxref\n${xref}\n%%EOF\n`;
  return latin(body);
}

// Every in use offset of the (last) cross reference table must land on 'N 0 obj'.
function assertXrefValid(b) {
  const s = asLatin(b);
  const at = Number(/startxref\s+(\d+)/.exec(s.slice(s.lastIndexOf('startxref')))[1]);
  assert.equal(s.slice(at, at + 4), 'xref');
  const lines = s.slice(at).split('\n');
  const [first, count] = lines[1].split(' ').map(Number);
  for (let k = 0; k < count; k++) {
    const [off, , kind] = lines[2 + k].trim().split(' ');
    if (kind !== 'n') continue;
    const num = first + k;
    assert.ok(s.startsWith(`${num} 0 obj`, Number(off)), `object ${num} is not at ${off}`);
  }
}

const XMP_STREAM_TEXT = `<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>${XMP_PACKET}<?xpacket end="w"?>`;

async function pdfWithMetadata() {
  const packed = asLatin(await compress(text('<x:xmpmeta><pdf:Producer>Example Scanner by Thandi</pdf:Producer></x:xmpmeta>'), 'deflate'));
  return pdfFile([
    '<< /Type /Catalog /Pages 2 0 R /Metadata 4 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Metadata 7 0 R >>',
    `<< /Type /Metadata /Subtype /XML /Length ${XMP_STREAM_TEXT.length} >>\nstream\n${XMP_STREAM_TEXT}\nendstream`,
    '<< /Author (Thandi \\(Safety\\) Example) /Title <FEFF0052006900730006B> /Subject (Shaft 3 (north)) /Keywords [(noise) (dust)]'
      + ' /Producer 6 0 R /Creator (Example Writer 9) /CreationDate (D:20250201081200+02\'00\') /ModDate (D:20260920) /Trapped /False'
      + ' /CompanyName (Example Holdings) >>',
    '(Example PDF Library 4.1)',
    `<< /Type /Metadata /Subtype /XML /Filter /FlateDecode /Length 8 0 R >>\nstream\n${packed}\nendstream`,
    String(packed.length),
  ], '/Info 5 0 R');
}

test('PDF: Info values and XMP streams are blanked in place at the same length; xref offsets still point at their objects', async () => {
  const input = await pdfWithMetadata();
  assertXrefValid(input);
  const r = await cleanMetadata({ bytes: input, mimeType: MIME.pdf, fileName: 'Risk.pdf' });
  assert.equal(r.outcome, 'cleaned', r.reason);
  assert.deepEqual(codes(r), ['author', 'title', 'xmp', 'software', 'dates', 'other']);
  const out = r.bytes;
  assert.equal(out.length, input.length);
  assertXrefValid(out);
  const s = asLatin(out);
  for (const gone of ['Thandi', 'Shaft', 'noise', 'Example Writer', 'Example PDF Library', 'Example Holdings', 'D:2025', 'GPSLatitude', 'xpacket']) {
    assert.ok(!s.includes(gone), `${gone} survived`);
  }
  // The structure around the values is intact.
  assert.match(s, /\/Author \( +\) \/Title < +> \/Subject \( +\) \/Keywords \[\( +\) \( +\)\]/);
  assert.match(s, /\/Trapped \/False/);
  assert.match(s, /6 0 obj\n\( +\)\nendobj/);
  assert.match(s, /\/Length 8 0 R >>\nstream\n/);
  // The compressed XMP stream still inflates, to spaces only, at the same length.
  const m = /\/FlateDecode \/Length 8 0 R >>\nstream\n/.exec(s);
  const len = Number(/8 0 obj\n(\d+)/.exec(s)[1]);
  const data = out.subarray(m.index + m[0].length, m.index + m[0].length + len);
  const inflated = await decompress(data, 'deflate');
  assert.ok(inflated.length > 0 && inflated.every((x) => x === 0x20));
  // A key outside the standard set is a detail too: its name is shown by
  // readers, so it becomes X of the same length.
  assert.match(s, /\/XXXXXXXXXXX \( +\) >>/);
  // Every byte that changed became a space (or an X inside a name), except
  // inside the compressed stream, which now holds stored blocks of spaces.
  const packedAt = m.index + m[0].length;
  for (let k = 0; k < out.length; k++) {
    if (k >= packedAt && k < packedAt + len) continue;
    if (out[k] !== input[k]) assert.ok(out[k] === 0x20 || out[k] === 0x58, `byte ${k}`);
  }
  assert.deepEqual(await inspectBytes({ bytes: out, mimeType: MIME.pdf, fileName: 'Risk.pdf' }), { verdict: 'clean', findings: [] });

  // Cleaning the cleaned file changes nothing.
  const again = await cleanMetadata({ bytes: out, mimeType: MIME.pdf });
  assert.equal(again.outcome, 'unchanged');
});

test('PDF: a file without Info or XMP is unchanged', async () => {
  const plain = pdfFile(['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [] /Count 0 >>']);
  const r = await cleanMetadata({ bytes: plain, mimeType: MIME.pdf });
  assert.equal(r.outcome, 'unchanged');
  assert.equal(r.bytes, plain);
});

// PDF 1.5: the Info dictionary packed in a compressed object stream, found
// through a cross reference stream.
async function pdfInfoInObjectStream(alsoTopLevel) {
  const header = '5 0 ';
  const inner = `${header}<< /Author (Thandi Example) /Producer (Example) >>`;
  const packed = asLatin(await compress(latin(inner), 'deflate'));
  let body = '%PDF-1.7\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n';
  if (alsoTopLevel) body += '5 0 obj\n<< /Author (Old Name) >>\nendobj\n';
  body += `6 0 obj\n<< /Type /ObjStm /N 1 /First ${header.length} /Filter /FlateDecode /Length ${packed.length} >>\nstream\n${packed}\nendstream\nendobj\n`;
  const xrefAt = body.length;
  const xdata = '\x01\x00\x0f\x00';
  body += `7 0 obj\n<< /Type /XRef /Size 8 /Root 1 0 R /Info 5 0 R /W [1 2 1] /Length ${xdata.length} >>\nstream\n${xdata}\nendstream\nendobj\n`;
  body += `startxref\n${xrefAt}\n%%EOF\n`;
  return latin(body);
}

test('PDF: an Info dictionary inside a compressed object stream, or an encrypted PDF, is refused with the plain reason', async () => {
  for (const bytes of [await pdfInfoInObjectStream(false), await pdfInfoInObjectStream(true)]) {
    const r = await cleanMetadata({ bytes, mimeType: MIME.pdf });
    assert.equal(r.outcome, 'refused');
    assert.equal(r.bytes, null);
    assert.equal(r.reason, 'This PDF keeps its details in a form Care Net cannot clean. Please print it to a new PDF or save it again, then upload it.');
  }
  const encrypted = pdfFile([
    '<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [] /Count 0 >>',
    '<< /Filter /Standard /V 2 /R 3 /O <00> /U <00> /P -4 >>', '<< /Author (x) >>',
  ], '/Encrypt 3 0 R /Info 4 0 R /ID [<01> <01>]');
  const r = await cleanMetadata({ bytes: encrypted, mimeType: MIME.pdf });
  assert.equal(r.outcome, 'refused');
  assert.equal(r.reason, REFUSALS.pdf);
});

test('PDF: structures the cleaner cannot follow are refused, never passed', async () => {
  const good = await pdfWithMetadata();
  const cases = [
    latin('%PDF-1.7\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n'), // dictionary not closed
    latin('%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF\n'), // no trailer at all
    latin('%PDF-1.7\n1 0 obj\n<< /Author (never closed >>\nendobj\ntrailer\n<< /Root 1 0 R /Info 1 0 R >>\n'),
    latin('%PDF-1.7\ntrailer\n<< /Root 1 0 R /Info 9 0 R >>\n%%EOF\n'), // Info names an object that is not there
    good.subarray(0, 300),
    text('not a PDF at all'),
  ];
  for (const bytes of cases) {
    const r = await cleanMetadata({ bytes, mimeType: MIME.pdf });
    assert.equal(r.outcome, 'refused', asLatin(bytes.subarray(0, 60)));
    assert.equal(r.bytes, null);
  }
});

// Writes the given [number, body] objects (or [number, raw text, offset into
// it] for an object whose cross reference entry points into raw text) with a
// cross reference table; xref overrides entries by number.
function pdfBuild(objs, trailer, xref) {
  let s = '%PDF-1.7\n%\xe2\xe3\xcf\xd3\n';
  const off = {};
  let max = 0;
  for (const [num, body, raw] of objs) {
    if (raw !== undefined) { off[num] = s.length + raw; s += body; } else { off[num] = s.length; s += `${num} 0 obj\n${body}\nendobj\n`; }
    max = Math.max(max, num);
  }
  Object.assign(off, xref || {});
  const at = s.length;
  s += `xref\n0 ${max + 1}\n0000000000 65535 f \n`;
  for (let k = 1; k <= max; k++) s += off[k] !== undefined ? `${String(off[k]).padStart(10, '0')} 00000 n \n` : '0000000000 00000 f \n';
  s += `trailer\n<< /Size ${max + 1} ${trailer} >>\nstartxref\n${at}\n%%EOF\n`;
  return latin(s);
}
const PDF_BASE = [[1, '<< /Type /Catalog /Pages 2 0 R >>'], [2, '<< /Type /Pages /Kids [] /Count 0 >>']];
const XMP_OF = (who) => `<?xpacket begin=""?><x:xmpmeta xmlns:x="adobe:ns:meta/"><dc:creator>${who}</dc:creator></x:xmpmeta><?xpacket end="w"?>`;

test('PDF: names hidden behind #xx escapes are read as a reader reads them', async () => {
  let r = await cleanMetadata({ bytes: pdfBuild([...PDF_BASE, [5, '<< /Author (Thandi Example) /Title (Private Title) >>']], '/Root 1 0 R /In#66o 5 0 R'), mimeType: MIME.pdf });
  assert.equal(r.outcome, 'cleaned');
  assert.deepEqual(codes(r), ['author', 'title']);
  assert.ok(!contains(r.bytes, 'Thandi'));

  const xmp = XMP_OF('Thandi Example');
  r = await cleanMetadata({ bytes: pdfBuild([[1, '<< /Type /Catalog /Pages 2 0 R /Metadata 6 0 R >>'], PDF_BASE[1],
    [6, `<< /Type /Metad#61ta /Length ${xmp.length} >>\nstream\n${xmp}\nendstream`]], '/Root 1 0 R'), mimeType: MIME.pdf });
  assert.equal(r.outcome, 'cleaned');
  assert.deepEqual(codes(r), ['xmp']);
  assert.ok(!contains(r.bytes, 'Thandi'));

  r = await cleanMetadata({ bytes: pdfBuild([...PDF_BASE, [3, '<< /Filter /Standard >>']], '/Root 1 0 R /Encr#79pt 3 0 R'), mimeType: MIME.pdf });
  assert.equal(r.outcome, 'refused');
  assert.equal(r.reason, REFUSALS.pdf);
});

test('PDF: Info values that are names, and keys outside the standard set, are blanked; /Trapped keeps its standard value', async () => {
  const r = await cleanMetadata({ bytes: pdfBuild([...PDF_BASE,
    [5, '<< /Author /Thandi#20Example /Keywords [/Shaft#203 (dust)] /Trapped /True /Jane#20Secret (x) >>']], '/Root 1 0 R /Info 5 0 R'), mimeType: MIME.pdf });
  assert.equal(r.outcome, 'cleaned');
  assert.deepEqual(codes(r), ['author', 'title', 'other']);
  const s = asLatin(r.bytes);
  assert.match(s, /\/Author \/X{16} \/Keywords \[\/X{9} \( {4}\)\] \/Trapped \/True \/X{13} \( \) >>/);
  assertXrefValid(r.bytes);
});

test('PDF: an XMP stream is found through /Metadata whatever its type says, also from a catalogue packed in an object stream', async () => {
  const xmp = XMP_OF('Thandi Example');
  for (const dict of [`<< /Length ${xmp.length} >>`, `<< /Subtype /XML /Length ${xmp.length} >>`]) {
    const r = await cleanMetadata({ bytes: pdfBuild([[1, '<< /Type /Catalog /Pages 2 0 R /Metadata 6 0 R >>'], PDF_BASE[1],
      [6, `${dict}\nstream\n${xmp}\nendstream`]], '/Root 1 0 R'), mimeType: MIME.pdf });
    assert.equal(r.outcome, 'cleaned', dict);
    assert.ok(!contains(r.bytes, 'Thandi'), dict);
  }
  const inner = '1 0 << /Type /Catalog /Pages 2 0 R /Metadata 6 0 R >>';
  const packed = asLatin(await compress(latin(inner), 'deflate'));
  const r = await cleanMetadata({ bytes: pdfBuild([PDF_BASE[1],
    [4, `<< /Type /ObjStm /N 1 /First 4 /Filter /FlateDecode /Length ${packed.length} >>\nstream\n${packed}\nendstream`],
    [6, `<< /Length ${xmp.length} >>\nstream\n${xmp}\nendstream`]], '/Root 1 0 R'), mimeType: MIME.pdf });
  assert.equal(r.outcome, 'cleaned');
  assert.ok(!contains(r.bytes, 'Thandi'));
});

test('PDF: an object a reader could load from where the walker did not parse it (a comment, a string, another object) is refused', async () => {
  const hidden = '% 5 0 obj << /Author (Thandi Example) >> endobj\n';
  const decoy = [...PDF_BASE, [5, '<< /Author (decoy) >>']];
  const cases = {
    // The cross reference entry points into a comment; a decoy sits at the top level.
    comment: pdfBuild([...decoy, [5, hidden, 2]], '/Root 1 0 R /Info 5 0 R'),
    // The header only appears inside a string, for a reader rebuilding the table.
    string: pdfBuild([...decoy, [3, '(5 0 obj << /Author (Thandi Example) >> endobj)']], '/Root 1 0 R /Info 5 0 R'),
    // The entry for 5 points at object 3, whose values are not blanked.
    other: pdfBuild([...PDF_BASE, [3, '<< /Author (Thandi Example) >>'], [5, '<< /Author (decoy) >>']], '/Root 1 0 R /Info 5 0 R', { 5: 0 }),
    // A trailer naming the Info dictionary inside a comment.
    trailer: pdfBuild([...decoy, [4, '% trailer << /Info 5 0 R >>\n', 0]], '/Root 1 0 R'),
  };
  const good = asLatin(cases.other);
  cases.other = pdfBuild([...PDF_BASE, [3, '<< /Author (Thandi Example) >>'], [5, '<< /Author (decoy) >>']], '/Root 1 0 R /Info 5 0 R', { 5: good.indexOf('3 0 obj') });
  for (const [name, bytes] of Object.entries(cases)) {
    const r = await cleanMetadata({ bytes, mimeType: MIME.pdf });
    assert.equal(r.outcome, 'refused', name);
    assert.equal(r.reason, REFUSALS.pdf, name);
  }
});

test('PDF: many references to many copies of one object are blanked once each, in linear time', async () => {
  const k = 64000;
  let s = '%PDF-1.7\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n';
  s += `5 0 obj\n<< /Keywords [${'9 0 R '.repeat(k)}] >>\nendobj\n${'9 0 obj\n(x)\nendobj\n'.repeat(k)}`;
  s += 'trailer\n<< /Size 10 /Root 1 0 R /Info 5 0 R >>\n%%EOF\n';
  const t = Date.now();
  const r = await cleanMetadata({ bytes: latin(s), mimeType: MIME.pdf });
  assert.ok(Date.now() - t < 5000, `took ${Date.now() - t} ms`);
  assert.equal(r.outcome, 'cleaned');
  assert.ok(!asLatin(r.bytes).includes('(x)'));
});

// 6. Legacy Office, CSV, anything else -------------------------------------------------------

test('legacy Word and Excel files are refused with the plain reason', async () => {
  const header = new Uint8Array(512);
  header.set([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  for (const mimeType of [MIME.doc, MIME.xls]) {
    const r = await cleanMetadata({ bytes: header, mimeType, fileName: 'old.doc' });
    assert.equal(r.outcome, 'refused');
    assert.equal(r.bytes, null);
    assert.equal(r.reason, 'Older Word and Excel files cannot have their hidden details removed. Please save it as a .docx or .xlsx file and upload it again.');
  }
});

test('CSV: a byte order mark is removed; plain UTF 8 is unchanged; bytes that are not UTF 8 are refused', async () => {
  const body = text('Name,Test date,Result\r\nWorker A,2026-09-01,Pass\r\n');
  let r = await cleanMetadata({ bytes: concat(Uint8Array.of(0xef, 0xbb, 0xbf), body), mimeType: MIME.csv });
  assert.equal(r.outcome, 'cleaned');
  assert.deepEqual(r.bytes, body);
  assert.deepEqual(codes(r), ['byte_order_mark']);
  r = await cleanMetadata({ bytes: body, mimeType: MIME.csv });
  assert.equal(r.outcome, 'unchanged');
  assert.equal(r.bytes, body);
  r = await cleanMetadata({ bytes: Uint8Array.of(0x41, 0xff, 0xfe, 0x42), mimeType: MIME.csv });
  assert.equal(r.outcome, 'refused');
});

test('anything unparseable or of an unknown type is refused, never passed as it is', async () => {
  const junk = Uint8Array.from({ length: 64 }, (_, k) => (k * 37) & 0xff);
  const cases = [
    [MIME.jpeg, concat(Uint8Array.of(0xff, 0xd8), APP0)], // ends before the picture
    [MIME.jpeg, concat(Uint8Array.of(0xff, 0xd8), seg(0xe1, new Uint8Array(10)).subarray(0, 8))],
    [MIME.jpeg, junk],
    [MIME.png, concat(PNG_SIG, IHDR, IDAT)], // no IEND
    [MIME.png, concat(PNG_SIG, IDAT, IEND)], // IHDR not first
    [MIME.png, junk],
    [MIME.pdf, junk],
    [MIME.docx, junk],
    [MIME.xlsx, new Uint8Array(0)],
    ['application/zip', junk],
    ['', junk],
    [MIME.pdf, 'not bytes'],
  ];
  for (const [mimeType, bytes] of cases) {
    const r = await cleanMetadata({ bytes, mimeType });
    assert.equal(r.outcome, 'refused', `${mimeType} ${String(bytes).slice(0, 20)}`);
    assert.equal(r.bytes, null);
    assert.equal(typeof r.reason, 'string');
    assert.deepEqual(r.removed, []);
  }
  assert.equal((await cleanMetadata({ bytes: junk, mimeType: 'application/zip' })).reason, REFUSALS.type);
  assert.equal((await cleanMetadata(undefined)).outcome, 'refused');
});

// 7. The scan path: structural check, antivirus engine, clean, write back, record ------------

const ACCOUNT_ID = '0b9a8c7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d';
const UPLOAD_ID = '7e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c61';
const DOCX_NAME = 'Noise_survey.docx';
const DOCX_PATH = `${ACCOUNT_ID}/${UPLOAD_ID}/${DOCX_NAME}`;
const CLAIM_ID = '5d4c3b2a-1f0e-4d9c-8b7a-6f5e4d3c2b1a';

async function scanFixture(bytes, over) {
  const sha = await sha256Hex(bytes);
  return Object.assign({
    id: UPLOAD_ID,
    client_account_id: ACCOUNT_ID,
    safe_name: DOCX_NAME,
    mime_type: MIME.docx,
    sha256_client: sha,
    sha256_server: null,
    storage_bucket: STAGING_BUCKET,
    storage_path: DOCX_PATH,
    status: 'uploaded',
    scan_status: 'pending',
    scan_claim_id: CLAIM_ID,
    scan_write_back: null,
    uploaded_at: UPLOADED_AT,
  }, over || {});
}

// Logs every step in order; the antivirus engine records the bytes it saw.
function scanDeps(original, opts) {
  const o = opts || {};
  const steps = [];
  const store = new Map([[DOCX_PATH, original]]);
  const seen = {};
  const deps = {
    checkPath: checkStagingPath,
    async download(path) { steps.push('download'); return store.get(path); },
    av: {
      kind: 'test',
      configured: true,
      async scan(doc) { steps.push('antivirus'); seen.av = doc.bytes; return o.av || { result: 'clean', engine: 'ClamAV 1.4' }; },
    },
    async upload(path, bytes, mimeType) {
      steps.push('write back');
      seen.upload = { path, bytes, mimeType };
      if (o.uploadFails) throw new Error('Storage refused the cleaned file (HTTP 500).');
      store.set(path, bytes);
    },
    async rpc(fn, args) {
      steps.push(fn);
      seen[fn] = args;
      if (o.recordCleanFails && fn === 'hsf_scan_record_clean') throw new Error('hsf_scan_record_clean was refused (HTTP 500)');
      if (o.writeBackRefused && fn === 'hsf_scan_write_back') throw new Error('hsf_scan_write_back was refused (HTTP 400): The upload is not waiting for a security scan (status client_deleted, scan pending).');
      return { upload_id: args.p_upload_id };
    },
  };
  return { deps, steps, seen, store };
}

test('scan path: structural check, antivirus engine, clean, write back, then hsf_scan_record_clean with the cleaned fingerprint', async () => {
  const original = await docxFixture();
  const row = await scanFixture(original);
  const w = scanDeps(original);
  const rep = await scanUpload(row, w.deps);
  assert.deepEqual(w.steps, ['download', 'antivirus', 'hsf_scan_write_back', 'write back', 'hsf_scan_record_clean']);
  assert.equal(rep.action, 'clean');
  assert.equal(rep.metadata, 'cleaned');
  assert.ok(rep.removed.includes('author') && rep.removed.includes('company'));
  // The engine saw the original; staging now holds the cleaned bytes at the same path.
  assert.deepEqual(w.seen.av, original);
  assert.equal(w.seen.upload.path, DOCX_PATH);
  assert.equal(w.seen.upload.mimeType, MIME.docx);
  const cleaned = w.store.get(DOCX_PATH);
  assert.notDeepEqual(cleaned, original);
  const args = w.seen.hsf_scan_record_clean;
  assert.deepEqual(Object.keys(args).sort(), ['p_engine', 'p_findings', 'p_metadata_removed', 'p_sha256_clean', 'p_size_bytes', 'p_upload_id']);
  assert.equal(args.p_upload_id, UPLOAD_ID);
  assert.equal(args.p_engine, `${INSPECT_ENGINE} + ClamAV 1.4 + ${CLEAN_ENGINE}`);
  assert.deepEqual(args.p_findings, []);
  assert.equal(args.p_sha256_clean, await sha256Hex(cleaned));
  assert.notEqual(args.p_sha256_clean, row.sha256_client);
  assert.equal(args.p_size_bytes, cleaned.length);
  assert.deepEqual(args.p_metadata_removed.map((x) => x.code), rep.removed);
  // The write back was announced under this pass's claim, with the same
  // fingerprint, size and list, before anything was written.
  assert.deepEqual(w.seen.hsf_scan_write_back, {
    p_upload_id: UPLOAD_ID, p_claim_id: CLAIM_ID, p_sha256_clean: args.p_sha256_clean,
    p_size_bytes: cleaned.length, p_metadata_removed: args.p_metadata_removed,
  });
  for (const x of args.p_metadata_removed) assert.ok(!/Thandi|Pieter|Example/.test(x.message), 'a removed value reached the record');
  assert.ok(!('hsf_scan_record' in w.seen), 'a plain clean result was recorded');
  // The cleaned document reopens and its document part is unchanged.
  const parts = await openZip(cleaned);
  assert.equal(dec.decode(parts.get('word/document.xml').raw), DOCUMENT_XML);
});

test('scan path: a photo with GPS is not rejected; the cleaner removes the location and the cleaned copy carries none', async () => {
  const photo = jpeg(APP0, APP1_EXIF, APP1_XMP, APP2_ICC);
  const path = `${ACCOUNT_ID}/${UPLOAD_ID}/Site.jpg`;
  const w = scanDeps(photo);
  w.store.set(path, photo);
  const rep = await scanUpload(await scanFixture(photo, { mime_type: MIME.jpeg, safe_name: 'Site.jpg', storage_path: path }), w.deps);
  assert.deepEqual(w.steps, ['download', 'antivirus', 'hsf_scan_write_back', 'write back', 'hsf_scan_record_clean']);
  assert.equal(rep.action, 'clean');
  assert.ok(rep.removed.includes('location'));
  const cleaned = w.store.get(path);
  assert.deepEqual((await inspectBytes({ bytes: cleaned, mimeType: MIME.jpeg, fileName: 'Site.jpg' })).findings, []);
  assert.equal(w.seen.hsf_scan_record_clean.p_sha256_clean, await sha256Hex(cleaned));
  // inspectBytes on its own still flags the original.
  assert.equal((await inspectBytes({ bytes: photo, mimeType: MIME.jpeg })).verdict, 'harmful');
});

test('scan path: a harmful file stops at the structural check; an infected file stops at the engine; nothing is cleaned or written', async () => {
  const bad = await buildZip([{ name: '[Content_Types].xml', data: DOCX_TYPES }, { name: 'word/vbaProject.bin', data: 'x' }]);
  let w = scanDeps(bad);
  let rep = await scanUpload(await scanFixture(bad), w.deps);
  assert.deepEqual(w.steps, ['download', 'hsf_scan_record']);
  assert.equal(w.seen.hsf_scan_record.p_result, 'harmful');
  assert.equal(rep.metadata, null);

  const original = await docxFixture();
  w = scanDeps(original, { av: { result: 'infected', engine: 'ClamAV 1.4', signature: 'Win.Test.EICAR_HDB-1' } });
  rep = await scanUpload(await scanFixture(original), w.deps);
  assert.deepEqual(w.steps, ['download', 'antivirus', 'hsf_scan_record']);
  assert.equal(w.seen.hsf_scan_record.p_result, 'infected');
  assert.equal(w.store.get(DOCX_PATH), original);
});

test('scan path: a file the cleaner refuses is recorded harmful with the plain reason and never written back', async () => {
  // A PDF whose Info sits in an object stream passes the structural check and
  // the engine, then the cleaner refuses it.
  const pdf = await pdfInfoInObjectStream(false);
  const w = scanDeps(pdf);
  const row = await scanFixture(pdf, { mime_type: MIME.pdf, safe_name: 'Risk.pdf', storage_path: `${ACCOUNT_ID}/${UPLOAD_ID}/Risk.pdf` });
  w.store.set(row.storage_path, pdf);
  const rep = await scanUpload(row, w.deps);
  assert.deepEqual(w.steps, ['download', 'antivirus', 'hsf_scan_record']);
  assert.equal(rep.metadata, 'refused');
  assert.deepEqual(w.seen.hsf_scan_record, {
    p_upload_id: UPLOAD_ID,
    p_result: 'harmful',
    p_engine: `${INSPECT_ENGINE} + ClamAV 1.4 + ${CLEAN_ENGINE}`,
    p_findings: [{ code: 'metadata_not_removable', message: REFUSALS.pdf }],
  });
  assert.equal(w.seen.upload, undefined);
});

test('scan path: a write back failure records error and never records clean; a failed clean record is reported', async () => {
  const original = await docxFixture();
  let w = scanDeps(original, { uploadFails: true });
  let rep = await scanUpload(await scanFixture(original), w.deps);
  assert.deepEqual(w.steps, ['download', 'antivirus', 'hsf_scan_write_back', 'write back', 'hsf_scan_record']);
  assert.equal(rep.action, 'error');
  assert.equal(w.seen.hsf_scan_record.p_result, 'error');
  assert.deepEqual(w.seen.hsf_scan_record.p_findings.map((f) => f.code), ['write_back_failed']);
  assert.ok(!('hsf_scan_record_clean' in w.seen));

  w = scanDeps(original, { recordCleanFails: true });
  rep = await scanUpload(await scanFixture(original), w.deps);
  assert.equal(rep.action, 'record_failed');
  assert.match(rep.error, /could not be recorded/);
});

test('scan path: a write back the database refuses (the upload left the scan, for example the client deleted it) writes nothing and records nothing', async () => {
  const original = await docxFixture();
  const w = scanDeps(original, { writeBackRefused: true });
  const rep = await scanUpload(await scanFixture(original), w.deps);
  assert.deepEqual(w.steps, ['download', 'antivirus', 'hsf_scan_write_back']);
  assert.equal(rep.action, 'skipped');
  assert.match(rep.error, /not written/);
  assert.equal(w.seen.upload, undefined);
  assert.equal(w.store.get(DOCX_PATH), original, 'staging was changed');
});

test('scan path: a pass that stopped after its write back is finished by the next one, which accepts the announced cleaned copy', async () => {
  // Pass 1 announces, writes and then cannot record.
  const original = await docxFixture();
  const row = await scanFixture(original);
  const w1 = scanDeps(original, { recordCleanFails: true });
  assert.equal((await scanUpload(row, w1.deps)).action, 'record_failed');
  const cleaned = w1.store.get(DOCX_PATH);
  const announced = w1.seen.hsf_scan_write_back;
  // Pass 2 reads the cleaned copy: not a fingerprint mismatch, and the list of
  // what pass 1 removed is kept.
  const w2 = scanDeps(cleaned);
  const rep = await scanUpload(await scanFixture(original, {
    scan_status: 'error',
    scan_write_back: { sha256_clean: announced.p_sha256_clean, size_bytes: announced.p_size_bytes, metadata_removed: announced.p_metadata_removed },
  }), w2.deps);
  assert.equal(rep.action, 'clean');
  assert.deepEqual(w2.steps, ['download', 'antivirus', 'hsf_scan_write_back', 'write back', 'hsf_scan_record_clean']);
  assert.deepEqual(w2.seen.av, cleaned);
  assert.equal(w2.seen.hsf_scan_record_clean.p_sha256_clean, announced.p_sha256_clean, 'cleaning the cleaned copy changed it');
  assert.deepEqual(w2.seen.hsf_scan_record_clean.p_metadata_removed.map((x) => x.code), announced.p_metadata_removed.map((x) => x.code));
  // Bytes matching neither the client fingerprint nor the announced copy still fail.
  const w3 = scanDeps(text('something else'));
  const bad = await scanUpload(await scanFixture(original, { scan_write_back: { sha256_clean: announced.p_sha256_clean } }), w3.deps);
  assert.deepEqual(bad.findings, ['fingerprint_mismatch']);
});

test('scan path: a CSV that is only a byte order mark is refused as an empty file, never written back as nothing', async () => {
  const bom = Uint8Array.of(0xef, 0xbb, 0xbf);
  const path = `${ACCOUNT_ID}/${UPLOAD_ID}/staff.csv`;
  const w = scanDeps(bom);
  w.store.set(path, bom);
  const rep = await scanUpload(await scanFixture(bom, { mime_type: MIME.csv, safe_name: 'staff.csv', storage_path: path }), w.deps);
  assert.deepEqual(w.steps, ['download', 'antivirus', 'hsf_scan_record']);
  assert.equal(rep.action, 'harmful');
  assert.deepEqual(w.seen.hsf_scan_record.p_findings, [{ code: 'empty_file', message: 'The file is empty.' }]);
  assert.equal(w.seen.upload, undefined);
});

test('run: the scan pass cleans and writes back, then the transfer pass moves the cleaned bytes and deletes only when server = receipt = sha256_clean', async () => {
  const original = await docxFixture();
  const row = await scanFixture(original);
  const store = new Map([[DOCX_PATH, original]]);
  const steps = [];
  let cleanSha = null;
  let sentSha = null;
  const rpc = async (fn, args) => {
    steps.push(fn);
    switch (fn) {
      case RPC.mode: return 'fixture';
      case RPC.sweep: return 0;
      case RPC.scanClaim: return [row];
      case RPC.scanWriteBack: return { upload_id: UPLOAD_ID };
      case RPC.scanRecordClean: cleanSha = args.p_sha256_clean; return { upload_id: UPLOAD_ID, scan_status: 'clean' };
      case RPC.claim: return cleanSha ? [Object.assign({}, row, { status: 'transferring', scan_status: 'clean', sha256_clean: cleanSha })] : [];
      case RPC.record: {
        const ok = args.p_outcome === 'received' && args.p_server_sha256 === cleanSha && args.p_receipt_sha256 === cleanSha;
        return { upload_id: UPLOAD_ID, status: ok ? 'transferred' : 'uploaded' };
      }
      case RPC.markDeleted: return { upload_id: UPLOAD_ID, status: 'staging_deleted' };
      case RPC.cleanup: case RPC.retention: return [];
      default: throw new Error(`unexpected rpc ${fn}`);
    }
  };
  const fixture = createAdapter({ mode: 'fixture' });
  const s = await runTransfer({
    rpc,
    download: async (p) => { steps.push('download'); return store.get(p); },
    upload: async (p, b) => { steps.push('write back'); store.set(p, b); },
    remove: async (p) => { steps.push('remove'); store.delete(p); return true; },
    createAdapter: () => ({ mode: 'fixture', async send(doc) { sentSha = doc.sha256; return fixture.send(doc); } }),
    allowFixture: true,
    allowScanFixture: true,
  });
  assert.deepEqual(steps, [
    'hsf_transfer_mode', 'hsf_sweep_stale_uploads',
    'hsf_scan_claim', 'download', 'hsf_scan_write_back', 'write back', 'hsf_scan_record_clean',
    'hsf_transfer_claim', 'download', 'hsf_transfer_record', 'remove', 'hsf_mark_staging_deleted',
    'hsf_transfer_cleanup_queue', 'hsf_retention_queue',
  ]);
  assert.equal(sentSha, cleanSha, 'the cleaned bytes were sent');
  assert.deepEqual(s.counts, { staging_deleted: 1 });
  assert.equal(store.size, 0);
});
