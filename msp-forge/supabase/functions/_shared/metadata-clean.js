// CNC HSF FORGE | HSF-CLEAN-01 v1.0.0 | Metadata removal for staged uploads 23/09/2026
//
// The Director's rule (contract 11.1): scan for viruses, malware and all
// metadata. After the structural check and the antivirus engine, the scan pass
// asks this module for a cleaned copy with every non essential hidden detail
// removed, writes it back over the staged object at the same path and records
// its fingerprint. The original bytes are not kept. Plain ES module: no
// dependencies, only the globals TextDecoder, TextEncoder, CompressionStream and
// DecompressionStream, so it runs in the Supabase edge function (Deno) and
// under node --test (Node 22).
//
// cleanMetadata({ bytes, mimeType, fileName, uploadedAt }) →
//   { outcome: 'cleaned' | 'unchanged' | 'refused', bytes, removed: [{ code, message }], reason }
//   JPEG  every APPn segment except APP0 JFIF (cut back to its 14 byte header,
//         so a thumbnail or anything written after the header goes) and APP2
//         ICC profile goes, so EXIF, XMP, IPTC and thumbnails go, and every COM
//         segment. The Adobe APP14 segment stays: it holds no details about
//         people or places, only the colour transform a CMYK picture needs to
//         show its true colours. Bytes after the end of image go. The picture
//         data is copied byte for byte.
//   PNG   tEXt, zTXt, iTXt, eXIf, tIME and every other ancillary chunk outside
//         the kept list go; kept chunks are copied with their own CRC, which is
//         checked. An unknown critical chunk is refused, never dropped.
//   OOXML the zip is rebuilt without custom properties, thumbnails, comments
//         and the people who commented, with their relationships and content
//         type overrides; core.xml becomes a minimal part dated the upload day;
//         Company, Manager, HyperlinkBase and Template leave app.xml. The core,
//         extended and custom properties and the thumbnail are found by their
//         usual names and through the package relationships, wherever they
//         sit. Every JPEG or PNG part (the pictures in the document) is cleaned
//         as a picture uploaded on its own. Every other part is copied
//         compressed as it was, after its CRC is checked. Entry dates, extra
//         fields and comments of the archive are cleared. XML parts are read by
//         a linear scan, never by patterns that run ahead to a closing tag.
//   PDF   every value in the trailer Info dictionary (names included; a key
//         outside the standard set is itself blanked) and every XMP metadata
//         stream (typed /Metadata, /Subtype /XML, or named by any /Metadata
//         key, a catalogue in an object stream included) is blanked in place
//         at the same byte length, so every cross reference offset stays valid.
//         Names are compared after their #xx escapes are decoded, each object
//         is blanked once however often it is named, and every object read is
//         checked against every cross reference entry for it. A compressed XMP
//         stream is replaced by a stored zlib stream of spaces of the same
//         length. An Info dictionary inside an object stream, an encrypted
//         file, and an object or watched name a reader could load from a place
//         the walker did not parse (a comment, a string, stream data) are
//         refused.
//   Legacy Word and Excel files are refused. CSV loses only a UTF 8 byte order
//   mark.
// Anything this module cannot parse is refused, never passed as it is. Work is
// bounded: inflated sizes are capped (no zip bomb expansion), and counts of
// segments, chunks, parts and PDF objects are limited. The labels in removed
// are plain words for the client ('Hidden details removed: author, company,
// location') and never carry the removed values.

export const CLEAN_ENGINE = 'hsf-clean-1.0';

export const REFUSALS = Object.freeze({
  pdf: 'This PDF keeps its details in a form Care Net cannot clean. Please print it to a new PDF or save it again, then upload it.',
  legacy: 'Older Word and Excel files cannot have their hidden details removed. Please save it as a .docx or .xlsx file and upload it again.',
  unreadable: 'Care Net could not read this file to remove its hidden details. Please save it again, then upload it.',
  type: 'This type of file cannot have its hidden details removed.',
});

// Plain labels, in the order the builder lists them.
const LABELS = Object.freeze({
  author: 'author',
  company: 'company',
  manager: 'manager',
  location: 'location',
  title: 'title, subject and keywords',
  comments: 'comments',
  people: 'names of reviewers',
  camera: 'camera details',
  thumbnail: 'thumbnail picture',
  xmp: 'embedded document details (XMP)',
  iptc: 'caption and credit details (IPTC)',
  text: 'text notes',
  custom: 'custom properties',
  template: 'template name',
  hyperlink_base: 'link base address',
  software: 'software used',
  revision: 'revision number',
  dates: 'dates and times',
  other: 'other hidden details',
  trailing_data: 'extra data after the picture',
  byte_order_mark: 'byte order mark',
});

const KINDS = Object.freeze({
  'application/pdf': 'pdf',
  'image/jpeg': 'jpeg',
  'image/png': 'png',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'ooxml',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'ooxml',
  'application/msword': 'legacy',
  'application/vnd.ms-excel': 'legacy',
  'text/csv': 'csv',
});

const SEGMENT_LIMIT = 100000;
const CHUNK_LIMIT = 100000;
const ZIP_ENTRY_LIMIT = 20000;
const XML_PART_LIMIT = 8 * 1024 * 1024;
const MEDIA_PART_LIMIT = 64 * 1024 * 1024;
const ZIP_INFLATE_LIMIT = 256 * 1024 * 1024;
const PDF_OBJECT_LIMIT = 2000000;
const PDF_NEST_LIMIT = 64;
const OBJSTM_LIMIT = 64 * 1024 * 1024;

// 1. Small helpers --------------------------------------------------------------

class Refusal extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

const unreadable = () => new Refusal(REFUSALS.unreadable);

function toUint8(v) {
  if (v instanceof Uint8Array) return v;
  if (v instanceof ArrayBuffer) return new Uint8Array(v);
  if (ArrayBuffer.isView(v)) return new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
  throw unreadable();
}

function ascii(s) {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff;
  return out;
}

function startsWith(bytes, sig, at) {
  const o = at || 0;
  if (bytes.length < o + sig.length) return false;
  for (let i = 0; i < sig.length; i++) if (bytes[o + i] !== sig[i]) return false;
  return true;
}

function sameBytes(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function concat(parts) {
  let n = 0;
  for (const p of parts) n += p.length;
  const out = new Uint8Array(n);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

function latin1(bytes, start, end) {
  const s = start || 0;
  const e = end === undefined ? bytes.length : end;
  const parts = [];
  for (let i = s; i < e; i += 0x8000) {
    parts.push(String.fromCharCode.apply(null, bytes.subarray(i, Math.min(i + 0x8000, e))));
  }
  return parts.join('');
}

const u16le = (b, i) => b[i] | (b[i + 1] << 8);
const u32le = (b, i) => (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0;
const u16be = (b, i) => (b[i] << 8) | b[i + 1];
const u32be = (b, i) => ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0;
const le16 = (v) => Uint8Array.of(v & 0xff, (v >>> 8) & 0xff);
const le32 = (v) => Uint8Array.of(v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff);
const be16 = (v) => Uint8Array.of((v >>> 8) & 0xff, v & 0xff);

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

// CRC 32 as zip and PNG use it; pass the previous value to continue.
function crc32(bytes, prev) {
  let c = prev === undefined ? 0xffffffff : (prev ^ 0xffffffff) >>> 0;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// Inflates through DecompressionStream, stopping as soon as more than limit
// bytes come out. With keep false the output is only measured and its CRC
// taken, so a large part never sits in memory. Throws a Refusal on any fault.
async function inflate(data, format, limit, keep) {
  if (typeof DecompressionStream !== 'function') throw unreadable();
  let ds;
  try {
    ds = new DecompressionStream(format);
  } catch (_) {
    throw unreadable();
  }
  const writer = ds.writable.getWriter();
  writer.write(data).catch(() => {});
  writer.close().catch(() => {});
  const reader = ds.readable.getReader();
  const chunks = [];
  let total = 0;
  let crc = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > limit) {
        reader.cancel().catch(() => {});
        throw unreadable();
      }
      crc = crc32(value, crc);
      if (keep) chunks.push(value);
    }
  } catch (_) {
    throw unreadable();
  }
  return { bytes: keep ? concat(chunks) : null, size: total, crc };
}

async function deflateRaw(bytes) {
  if (typeof CompressionStream !== 'function') return null;
  try {
    const cs = new CompressionStream('deflate-raw');
    const w = cs.writable.getWriter();
    w.write(bytes).catch(() => {});
    w.close().catch(() => {});
    const reader = cs.readable.getReader();
    const chunks = [];
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      chunks.push(value);
    }
    return concat(chunks);
  } catch (_) {
    return null;
  }
}

function createRemoved() {
  const seen = new Set();
  return {
    add(code) { if (LABELS[code]) seen.add(code); },
    list() { return Object.keys(LABELS).filter((c) => seen.has(c)).map((code) => ({ code, message: LABELS[code] })); },
    get size() { return seen.size; },
  };
}

// Upload day as YYYY-MM-DD (UTC); today when none is given or it cannot be read.
function uploadDay(v) {
  const d = v instanceof Date ? v : new Date(typeof v === 'string' || typeof v === 'number' ? v : Date.now());
  const t = Number.isFinite(d.getTime()) ? d : new Date();
  return t.toISOString().slice(0, 10);
}

// 2. EXIF (TIFF) reading, only to name what is removed -----------------------------

// Reports whether a TIFF structure carries GPS coordinates and a thumbnail
// (a second image directory). Never throws: damaged details are removed anyway.
function exifFacts(b, start, end) {
  const facts = { gps: false, thumbnail: false };
  try {
    if (end - start < 8) return facts;
    let le;
    if (b[start] === 0x49 && b[start + 1] === 0x49) le = true;
    else if (b[start] === 0x4d && b[start + 1] === 0x4d) le = false;
    else return facts;
    const r16 = (i) => (le ? u16le(b, i) : u16be(b, i));
    const r32 = (i) => (le ? u32le(b, i) : u32be(b, i));
    const dir = (off) => {
      const at = start + off;
      if (off < 8 || at + 2 > end) return null;
      const n = r16(at);
      if (n > 1000 || at + 2 + n * 12 + 4 > end) return null;
      const tags = [];
      for (let k = 0; k < n; k++) tags.push({ tag: r16(at + 2 + k * 12), value: r32(at + 2 + k * 12 + 8) });
      return { tags, next: r32(at + 2 + n * 12) };
    };
    const ifd0 = dir(r32(start + 4));
    if (!ifd0) return facts;
    const gps = ifd0.tags.find((t) => t.tag === 0x8825);
    const g = gps ? dir(gps.value) : null;
    facts.gps = !!(g && g.tags.some((t) => t.tag >= 1 && t.tag <= 4));
    facts.thumbnail = ifd0.next !== 0 && !!dir(ifd0.next);
  } catch (_) { /* reported as camera details only */ }
  return facts;
}

const GPS_TEXT_RE = /GPS(Latitude|Longitude)|exif:GPS|Iptc4xmpExt:LocationCreated|photoshop:City/;

// 3. JPEG ---------------------------------------------------------------------------

const JFIF_SIG = ascii('JFIF\0');
const JFXX_SIG = ascii('JFXX\0');
const EXIF_SIG = ascii('Exif\0\0');
const XMP_SIG = ascii('http://ns.adobe.com/xap/1.0/\0');
const XMP_EXT_SIG = ascii('http://ns.adobe.com/xmp/extension/\0');
const ICC_SIG = ascii('ICC_PROFILE\0');
const PHOTOSHOP_SIG = ascii('Photoshop 3.0\0');
const ADOBE_SIG = ascii('Adobe');

function cleanJpeg(b, removed) {
  if (!(b[0] === 0xff && b[1] === 0xd8)) throw unreadable();
  const out = [b.subarray(0, 2)];
  const len = b.length;
  let i = 2;
  let segments = 0;
  let sawScan = false;
  for (;;) {
    if (++segments > SEGMENT_LIMIT) throw unreadable();
    if (i >= len || b[i] !== 0xff) throw unreadable();
    let j = i;
    while (j < len && b[j] === 0xff) j++; // fill bytes before a marker are dropped
    if (j >= len) throw unreadable();
    const marker = b[j];
    if (marker === 0x00) throw unreadable();
    if (marker === 0xd9) {
      if (!sawScan) throw unreadable();
      out.push(Uint8Array.of(0xff, 0xd9));
      if (j + 1 < len) removed.add('trailing_data');
      break;
    }
    if (marker === 0xd8) throw unreadable();
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      out.push(Uint8Array.of(0xff, marker));
      i = j + 1;
      continue;
    }
    if (j + 3 > len) throw unreadable();
    const segLen = u16be(b, j + 1);
    if (segLen < 2 || j + 1 + segLen > len) throw unreadable();
    const s = j + 3;
    const e = j + 1 + segLen;
    const whole = b.subarray(j - 1, e);

    if (marker >= 0xe0 && marker <= 0xef) {
      const kept = jpegAppKeep(b, marker, s, e, removed);
      if (kept) out.push(kept);
    } else if (marker === 0xfe) {
      removed.add('comments');
    } else {
      out.push(whole);
    }
    i = e;

    if (marker === 0xda) {
      sawScan = true;
      // Entropy coded picture data runs to the next marker that is not a
      // stuffed zero or a restart marker; it is copied as it is.
      let k = e;
      for (;;) {
        k = b.indexOf(0xff, k);
        if (k === -1 || k + 1 >= len) throw unreadable();
        const n = b[k + 1];
        if (n === 0x00 || (n >= 0xd0 && n <= 0xd7)) { k += 2; continue; }
        if (n === 0xff) { k += 1; continue; }
        break;
      }
      out.push(b.subarray(e, k));
      i = k;
    }
  }
  return concat(out);
}

// The segment to keep (possibly rewritten), or null when it is removed.
function jpegAppKeep(b, marker, s, e, removed) {
  const whole = b.subarray(s - 4, e);
  if (marker === 0xe0) {
    if (startsWith(b, JFIF_SIG, s)) {
      if (e - s < 14) throw unreadable();
      const w = b[s + 12];
      const h = b[s + 13];
      // Only the 14 byte JFIF header is kept, with no thumbnail: a segment of
      // exactly that is copied, anything longer (a thumbnail, or bytes after the
      // header whatever the stated thumbnail size) is rewritten without the rest.
      if (w * h === 0 && e - s === 14) return whole;
      removed.add(w * h === 0 ? 'other' : 'thumbnail');
      const body = new Uint8Array(14);
      body.set(b.subarray(s, s + 12));
      return concat([Uint8Array.of(0xff, 0xe0), be16(16), body]);
    }
    removed.add(startsWith(b, JFXX_SIG, s) ? 'thumbnail' : 'other');
    return null;
  }
  if (marker === 0xe1) {
    if (startsWith(b, EXIF_SIG, s)) {
      const f = exifFacts(b, s + EXIF_SIG.length, e);
      removed.add('camera');
      if (f.gps) removed.add('location');
      if (f.thumbnail) removed.add('thumbnail');
    } else if (startsWith(b, XMP_SIG, s) || startsWith(b, XMP_EXT_SIG, s)) {
      removed.add('xmp');
      if (GPS_TEXT_RE.test(latin1(b, s, e))) removed.add('location');
    } else {
      removed.add('other');
    }
    return null;
  }
  if (marker === 0xe2 && startsWith(b, ICC_SIG, s)) return whole;
  if (marker === 0xed && startsWith(b, PHOTOSHOP_SIG, s)) {
    removed.add('iptc');
    return null;
  }
  if (marker === 0xee && startsWith(b, ADOBE_SIG, s) && e - s <= 12) return whole;
  removed.add('other');
  return null;
}

// 4. PNG ----------------------------------------------------------------------------

const PNG_SIG = Uint8Array.of(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a);
const PNG_KEEP = new Set(['IHDR', 'PLTE', 'IDAT', 'IEND', 'tRNS', 'gAMA', 'cHRM', 'sRGB', 'iCCP', 'pHYs', 'sBIT', 'bKGD']);
const PNG_TYPE_RE = /^[A-Za-z]{4}$/;

function cleanPng(b, removed) {
  if (!startsWith(b, PNG_SIG)) throw unreadable();
  const out = [b.subarray(0, 8)];
  let i = 8;
  let chunks = 0;
  let sawData = false;
  for (;;) {
    if (++chunks > CHUNK_LIMIT) throw unreadable();
    if (i + 12 > b.length) throw unreadable();
    const len = u32be(b, i);
    const type = latin1(b, i + 4, i + 8);
    if (!PNG_TYPE_RE.test(type) || len > 0x7fffffff) throw unreadable();
    const s = i + 8;
    const e = s + len;
    if (e + 4 > b.length) throw unreadable();
    if (chunks === 1 && type !== 'IHDR') throw unreadable();
    if (PNG_KEEP.has(type)) {
      if (crc32(b.subarray(i + 4, e)) !== u32be(b, e)) throw unreadable();
      out.push(b.subarray(i, e + 4));
      if (type === 'IDAT') sawData = true;
    } else if (type.charCodeAt(0) < 0x61) {
      // An unknown critical chunk: dropping it would break the picture.
      throw unreadable();
    } else if (type === 'tEXt' || type === 'zTXt' || type === 'iTXt') {
      const kwEnd = b.indexOf(0, s);
      const kw = kwEnd !== -1 && kwEnd < e ? latin1(b, s, kwEnd) : '';
      if (kw === 'XML:com.adobe.xmp') {
        removed.add('xmp');
        if (type !== 'zTXt' && GPS_TEXT_RE.test(latin1(b, s, e))) removed.add('location');
      } else if (/^(Author|Artist)$/i.test(kw)) {
        removed.add('author');
      } else if (/^(Software|Source)$/i.test(kw)) {
        removed.add('software');
      } else if (/^(Title|Description|Comment)$/i.test(kw)) {
        removed.add(kw.toLowerCase() === 'comment' ? 'comments' : 'title');
      } else if (/^Creation Time$/i.test(kw)) {
        removed.add('dates');
      } else {
        removed.add('text');
      }
    } else if (type === 'eXIf') {
      const f = exifFacts(b, s, e);
      removed.add('camera');
      if (f.gps) removed.add('location');
      if (f.thumbnail) removed.add('thumbnail');
    } else if (type === 'tIME') {
      removed.add('dates');
    } else {
      removed.add('other');
    }
    i = e + 4;
    if (type === 'IEND') {
      if (!sawData) throw unreadable();
      if (i < b.length) removed.add('trailing_data');
      break;
    }
  }
  return concat(out);
}

// 5. OOXML (docx, xlsx) ---------------------------------------------------------------

function findEocd(b) {
  const min = Math.max(0, b.length - 22 - 0xffff);
  for (let i = b.length - 22; i >= min; i--) {
    if (b[i] === 0x50 && b[i + 1] === 0x4b && b[i + 2] === 0x05 && b[i + 3] === 0x06) return i;
  }
  return -1;
}

// Reads the central directory and checks every local header against it.
function readZip(b) {
  if (!startsWith(b, Uint8Array.of(0x50, 0x4b, 0x03, 0x04))) throw unreadable();
  const eocd = findEocd(b);
  if (eocd === -1) throw unreadable();
  if (u16le(b, eocd + 4) !== 0 || u16le(b, eocd + 6) !== 0) throw unreadable();
  const count = u16le(b, eocd + 10);
  const size = u32le(b, eocd + 12);
  const offset = u32le(b, eocd + 16);
  if (count !== u16le(b, eocd + 8)) throw unreadable();
  if (count === 0xffff || size === 0xffffffff || offset === 0xffffffff) throw unreadable(); // zip64
  if (count === 0 || count > ZIP_ENTRY_LIMIT || offset + size > eocd) throw unreadable();
  const dec = new TextDecoder('utf-8', { fatal: true });
  const entries = [];
  const names = new Set();
  let declared = 0;
  let p = offset;
  for (let k = 0; k < count; k++) {
    if (p + 46 > eocd || u32le(b, p) !== 0x02014b50) throw unreadable();
    const flags = u16le(b, p + 8);
    const method = u16le(b, p + 10);
    const crc = u32le(b, p + 16);
    const csize = u32le(b, p + 20);
    const usize = u32le(b, p + 24);
    const nameLen = u16le(b, p + 28);
    const extraLen = u16le(b, p + 30);
    const commentLen = u16le(b, p + 32);
    const disk = u16le(b, p + 34);
    const local = u32le(b, p + 42);
    if (p + 46 + nameLen > eocd || nameLen === 0 || disk !== 0) throw unreadable();
    if (flags & 0x41) throw unreadable(); // encrypted
    if (method !== 0 && method !== 8) throw unreadable();
    if (csize === 0xffffffff || usize === 0xffffffff || local === 0xffffffff) throw unreadable();
    if (method === 0 && csize !== usize) throw unreadable();
    const nameBytes = b.subarray(p + 46, p + 46 + nameLen);
    let name;
    try {
      name = dec.decode(nameBytes);
    } catch (_) {
      throw unreadable();
    }
    const key = name.toLowerCase();
    if (names.has(key)) throw unreadable();
    names.add(key);
    if (local + 30 > offset || u32le(b, local) !== 0x04034b50) throw unreadable();
    const ln = u16le(b, local + 26);
    const lx = u16le(b, local + 28);
    if (u16le(b, local + 8) !== method) throw unreadable();
    if (!sameBytes(b.subarray(local + 30, local + 30 + ln), nameBytes)) throw unreadable();
    const start = local + 30 + ln + lx;
    if (start + csize > offset) throw unreadable();
    declared += usize;
    if (declared > ZIP_INFLATE_LIMIT) throw unreadable();
    entries.push({ name, key, nameBytes, flags, method, crc, csize, usize, data: b.subarray(start, start + csize) });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

// The inflated content of an entry, checked against its CRC and size.
async function entryBytes(e, limit) {
  if (e.usize > limit) throw unreadable();
  if (e.method === 0) {
    if (crc32(e.data) !== e.crc) throw unreadable();
    return e.data;
  }
  const r = await inflate(e.data, 'deflate-raw', limit, true);
  if (r.size !== e.usize || r.crc !== e.crc) throw unreadable();
  return r.bytes;
}

// Checks a copied entry without keeping its content in memory.
async function verifyEntry(e) {
  if (e.method === 0) {
    if (crc32(e.data) !== e.crc) throw unreadable();
    return;
  }
  const r = await inflate(e.data, 'deflate-raw', e.usize, false);
  if (r.size !== e.usize || r.crc !== e.crc) throw unreadable();
}

function droppedPart(key) {
  if (key === 'docprops/custom.xml') return 'custom';
  if (/^docprops\/thumbnail\.[^/]+$/.test(key)) return 'thumbnail';
  if (/^(word|xl)\/comments[^/]*\.xml$/.test(key)) return 'comments';
  if (key.startsWith('xl/threadedcomments/')) return 'comments';
  if (key === 'word/people.xml' || key.startsWith('xl/persons/')) return 'people';
  return null;
}

const RELS_RE = /^(.*\/)?_rels\/([^/]*)\.rels$/;

// The part a relationships file belongs to ('' for the package itself).
function relsSource(key) {
  const m = RELS_RE.exec(key);
  if (!m) return null;
  return (m[1] || '') + m[2];
}

function xmlUnescape(s) {
  return s.replace(/&(amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/gi, (m, g) => {
    const l = g.toLowerCase();
    if (l === 'amp') return '&';
    if (l === 'lt') return '<';
    if (l === 'gt') return '>';
    if (l === 'quot') return '"';
    if (l === 'apos') return "'";
    const n = l[1] === 'x' ? parseInt(l.slice(2), 16) : parseInt(l.slice(1), 10);
    return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : m;
  });
}

function attr(tag, name) {
  const m = new RegExp(`\\s${name}\\s*=\\s*("([^"]*)"|'([^']*)')`).exec(tag);
  return m ? xmlUnescape(m[2] !== undefined ? m[2] : m[3]) : null;
}

// Resolves a relationship target against the folder of its source part, as a
// lower case part name without a leading slash.
function resolveTarget(baseDir, target) {
  let t = target;
  try { t = decodeURIComponent(t); } catch (_) { /* keep as written */ }
  t = t.split('#')[0];
  const segs = (t.startsWith('/') ? t.slice(1) : baseDir + t).split('/');
  const out = [];
  for (const s of segs) {
    if (s === '' || s === '.') continue;
    if (s === '..') out.pop();
    else out.push(s);
  }
  return out.join('/').toLowerCase();
}

// A linear scan of an XML part: the direct children of its root element, each
// { name (local name), qname, tag (the start tag), start, end, innerStart,
// innerEnd }. Every character is visited once, so an element that is never
// closed costs one pass, not one pass per element (no pattern runs ahead to a
// closing tag). A part that is not well formed at this level, or that declares
// a document type, is refused.
function xmlChildren(xml) {
  const n = xml.length;
  const kids = [];
  let i = 0;
  let depth = 0;
  let root = false;
  let child = null;
  while (i < n) {
    const lt = xml.indexOf('<', i);
    if (lt === -1) break;
    if (xml.startsWith('<!--', lt)) {
      const e = xml.indexOf('-->', lt + 4);
      if (e === -1) throw unreadable();
      i = e + 3;
      continue;
    }
    if (xml.startsWith('<![CDATA[', lt)) {
      const e = xml.indexOf(']]>', lt + 9);
      if (e === -1 || depth === 0) throw unreadable();
      i = e + 3;
      continue;
    }
    if (xml.startsWith('<?', lt)) {
      const e = xml.indexOf('?>', lt + 2);
      if (e === -1) throw unreadable();
      i = e + 2;
      continue;
    }
    if (xml.startsWith('<!', lt)) throw unreadable(); // a document type has no place in OOXML
    // The end of the tag, past any '>' inside a quoted attribute value.
    let k = lt + 1;
    let q = 0;
    for (; k < n; k++) {
      const c = xml.charCodeAt(k);
      if (q) { if (c === q) q = 0; } else if (c === 0x22 || c === 0x27) q = c; else if (c === 0x3e) break;
    }
    if (k >= n) throw unreadable();
    const closing = xml.charCodeAt(lt + 1) === 0x2f;
    const selfClosing = !closing && xml.charCodeAt(k - 1) === 0x2f;
    let e = lt + (closing ? 2 : 1);
    const ns = e;
    while (e < k && !/[\s/>]/.test(xml[e])) e++;
    if (e === ns) throw unreadable();
    const qname = xml.slice(ns, e);
    if (closing) {
      depth--;
      if (depth < 0) throw unreadable();
      if (depth === 1 && child) {
        if (child.qname !== qname) throw unreadable();
        child.innerEnd = lt;
        child.end = k + 1;
        kids.push(child);
        child = null;
      }
      if (depth === 0) return kids;
    } else if (depth === 0) {
      if (root) throw unreadable();
      root = true;
      if (selfClosing) return kids;
      depth = 1;
    } else if (depth === 1) {
      child = { name: qname.slice(qname.indexOf(':') + 1), qname, tag: xml.slice(lt, k + 1), start: lt, innerStart: k + 1 };
      if (selfClosing) {
        child.innerEnd = k + 1;
        child.end = k + 1;
        kids.push(child);
        child = null;
      } else {
        depth = 2;
      }
    } else if (!selfClosing) {
      depth++;
    }
    i = k + 1;
  }
  throw unreadable(); // the root element is never closed
}

// The part with the given [start, end) ranges (in order, not overlapping) cut out.
function cutRanges(xml, ranges) {
  const parts = [];
  let at = 0;
  for (const [s, e] of ranges) {
    parts.push(xml.slice(at, s));
    at = e;
  }
  parts.push(xml.slice(at));
  return parts.join('');
}

function removeRelationships(xml, sourceKey, dropped) {
  const slash = sourceKey.lastIndexOf('/');
  const baseDir = slash === -1 ? '' : sourceKey.slice(0, slash + 1);
  const cut = [];
  for (const el of xmlChildren(xml)) {
    if (el.name !== 'Relationship') continue;
    const mode = attr(el.tag, 'TargetMode');
    if (mode && mode.toLowerCase() === 'external') continue;
    const target = attr(el.tag, 'Target');
    if (target === null) continue;
    if (dropped.has(resolveTarget(baseDir, target))) cut.push([el.start, el.end]);
  }
  return cut.length ? cutRanges(xml, cut) : null;
}

function removeOverrides(xml, dropped) {
  const cut = [];
  for (const el of xmlChildren(xml)) {
    if (el.name !== 'Override') continue;
    const part = attr(el.tag, 'PartName');
    if (part !== null && dropped.has(resolveTarget('', part.startsWith('/') ? part : `/${part}`))) cut.push([el.start, el.end]);
  }
  return cut.length ? cutRanges(xml, cut) : null;
}

// Package relationship types that name a part holding details about the
// document, wherever the part sits (OPC does not fix its name).
const PACKAGE_ROLES = [
  [/\/metadata\/core-properties$/i, 'core'],
  [/\/extended-properties$/i, 'app'],
  [/\/custom-properties$/i, 'custom'],
  [/\/metadata\/thumbnail$/i, 'thumbnail'],
];

const CORE_FIELDS = Object.freeze({
  creator: 'author', lastModifiedBy: 'author',
  title: 'title', subject: 'title', keywords: 'title', description: 'title', category: 'title',
  revision: 'revision', lastPrinted: 'dates', created: 'dates', modified: 'dates',
  contentStatus: 'other', identifier: 'other', language: 'other', version: 'other',
});

function minimalCore(day) {
  const at = `${day}T00:00:00Z`;
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    + '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"'
    + ' xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/"'
    + ' xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    + `<dcterms:created xsi:type="dcterms:W3CDTF">${at}</dcterms:created>`
    + `<dcterms:modified xsi:type="dcterms:W3CDTF">${at}</dcterms:modified>`
    + '</cp:coreProperties>';
}

// Names what the original core part held that the minimal part does not.
function coreLabels(xml, day, removed) {
  const at = `${day}T00:00:00Z`;
  for (const el of xmlChildren(xml)) {
    const value = xml.slice(el.innerStart, el.innerEnd).trim();
    if (!value) continue;
    const field = el.name;
    if ((field === 'created' || field === 'modified') && value === at) continue;
    removed.add(Object.prototype.hasOwnProperty.call(CORE_FIELDS, field) ? CORE_FIELDS[field] : 'other');
  }
}

const APP_FIELDS = Object.freeze({ Company: 'company', Manager: 'manager', HyperlinkBase: 'hyperlink_base', Template: 'template' });

function stripApp(xml, removed) {
  const cut = [];
  for (const el of xmlChildren(xml)) {
    if (!Object.prototype.hasOwnProperty.call(APP_FIELDS, el.name)) continue;
    cut.push([el.start, el.end]);
    if (xml.slice(el.innerStart, el.innerEnd).trim()) removed.add(APP_FIELDS[el.name]);
  }
  return cut.length ? cutRanges(xml, cut) : null;
}

function decodeXml(bytes) {
  try {
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch (_) {
    throw unreadable();
  }
}

const JPEG_SOI = Uint8Array.of(0xff, 0xd8, 0xff);

async function cleanOoxml(b, removed, day) {
  const entries = readZip(b);
  const enc = new TextEncoder();
  const byKey = new Map(entries.map((e) => [e.key, e]));

  // The core and extended properties, custom properties and thumbnail parts are
  // found by their conventional names and by the package relationships, which
  // may place them anywhere.
  const core = new Set(['docprops/core.xml']);
  const app = new Set(['docprops/app.xml']);
  const dropped = new Set();
  const drop = (key, why) => {
    if (!byKey.has(key) || dropped.has(key)) return;
    dropped.add(key);
    removed.add(why);
  };
  for (const e of entries) {
    const why = droppedPart(e.key);
    if (why) drop(e.key, why);
  }
  const pkg = byKey.get('_rels/.rels');
  if (pkg) {
    for (const el of xmlChildren(decodeXml(await entryBytes(pkg, XML_PART_LIMIT)))) {
      if (el.name !== 'Relationship') continue;
      const mode = attr(el.tag, 'TargetMode');
      if (mode && mode.toLowerCase() === 'external') continue;
      const target = attr(el.tag, 'Target');
      const role = PACKAGE_ROLES.find(([re]) => re.test(attr(el.tag, 'Type') || ''));
      if (target === null || !role) continue;
      const key = resolveTarget('', target);
      if (role[1] === 'core') core.add(key);
      else if (role[1] === 'app') app.add(key);
      else drop(key, role[1]);
    }
  }
  // Relationships of a removed part go with it.
  for (const e of entries) {
    const src = relsSource(e.key);
    if (src && dropped.has(src)) dropped.add(e.key);
  }

  const out = [];
  let changed = dropped.size > 0;
  for (const e of entries) {
    if (dropped.has(e.key)) continue;
    let replaced = null;
    if (core.has(e.key)) {
      const xml = decodeXml(await entryBytes(e, XML_PART_LIMIT));
      const fresh = minimalCore(day);
      if (xml !== fresh) {
        coreLabels(xml, day, removed);
        replaced = fresh;
      }
    } else if (app.has(e.key)) {
      replaced = stripApp(decodeXml(await entryBytes(e, XML_PART_LIMIT)), removed);
    } else if (dropped.size && e.key === '[content_types].xml') {
      replaced = removeOverrides(decodeXml(await entryBytes(e, XML_PART_LIMIT)), dropped);
    } else if (dropped.size && relsSource(e.key) !== null) {
      replaced = removeRelationships(decodeXml(await entryBytes(e, XML_PART_LIMIT)), relsSource(e.key), dropped);
    } else if (!/\.(xml|rels)$/.test(e.key)) {
      // A picture inside the document (usually word/media or xl/media) keeps
      // its own details, a location among them, so every JPEG or PNG part,
      // whatever its name, is cleaned as a picture uploaded on its own would be.
      const data = await entryBytes(e, MEDIA_PART_LIMIT);
      let pic = null;
      if (startsWith(data, JPEG_SOI)) pic = cleanJpeg(data, removed);
      else if (startsWith(data, PNG_SIG)) pic = cleanPng(data, removed);
      if (pic && !sameBytes(pic, data)) replaced = pic;
    } else {
      await verifyEntry(e);
    }
    if (replaced !== null) {
      changed = true;
      const raw = typeof replaced === 'string' ? enc.encode(replaced) : replaced;
      const packed = await deflateRaw(raw);
      out.push({
        nameBytes: e.nameBytes, flags: e.flags & 0x800, crc: crc32(raw), usize: raw.length,
        method: packed ? 8 : 0, data: packed || raw,
      });
    } else {
      if (e.flags & 0x8) changed = true; // the data descriptor goes; sizes move into the header
      out.push({ nameBytes: e.nameBytes, flags: e.flags & 0x800, crc: e.crc, usize: e.usize, method: e.method, data: e.data });
    }
  }
  if (!out.length) throw unreadable();
  const rebuilt = writeZip(out);
  // Entry dates, extra fields and archive comments are cleared in the rebuild;
  // when nothing else changed, the rebuild is the answer only if it differs.
  if (!changed && sameBytes(rebuilt, b)) return null;
  if (!changed) removed.add('dates');
  return rebuilt;
}

// Writes a plain zip: local headers without extra fields, dated 1 January 1980,
// then the central directory and the end record.
function writeZip(entries) {
  const parts = [];
  const central = [];
  let offset = 0;
  for (const e of entries) {
    const local = concat([
      le32(0x04034b50), le16(20), le16(e.flags), le16(e.method), le16(0), le16(0x21),
      le32(e.crc), le32(e.data.length), le32(e.usize), le16(e.nameBytes.length), le16(0), e.nameBytes,
    ]);
    central.push(concat([
      le32(0x02014b50), le16(20), le16(20), le16(e.flags), le16(e.method), le16(0), le16(0x21),
      le32(e.crc), le32(e.data.length), le32(e.usize), le16(e.nameBytes.length), le16(0), le16(0), le16(0), le16(0),
      le32(0), le32(offset), e.nameBytes,
    ]));
    parts.push(local, e.data);
    offset += local.length + e.data.length;
  }
  const cd = concat(central);
  const end = concat([le32(0x06054b50), le16(0), le16(0), le16(entries.length), le16(entries.length), le32(cd.length), le32(offset), le16(0)]);
  return concat([...parts, cd, end]);
}

// 6. PDF ------------------------------------------------------------------------------
//
// A reader finds the Info dictionary and the XMP streams through names and
// references it resolves with the cross reference data, so the cleaner does
// the same: names are compared after their #xx escapes are decoded; every
// object it blanks or reads is checked against every cross reference entry
// for its number (each must land on an object the walker parsed, with the same
// number); and an object header, or a watched name (Info, Metadata, Encrypt),
// that appears anywhere the walker did not parse it (a comment, a string,
// stream data) is refused, because a reader rebuilding a damaged cross
// reference table could load it from there.

const PDF_WS = new Set([0x00, 0x09, 0x0a, 0x0c, 0x0d, 0x20]);
const PDF_DELIM = new Set([0x28, 0x29, 0x3c, 0x3e, 0x5b, 0x5d, 0x7b, 0x7d, 0x2f, 0x25]);
const pdfRegular = (c) => !PDF_WS.has(c) && !PDF_DELIM.has(c) && !Number.isNaN(c);
const pdfDigit = (c) => c >= 0x30 && c <= 0x39;
const INT_RE = /^\d+$/;
const PDF_REF_LIMIT = 1000000;
const pdfRefusal = () => new Refusal(REFUSALS.pdf);

// PDF names may hide letters behind #xx escapes (/In#66o is /Info).
function decodePdfName(raw) {
  return raw.indexOf('#') === -1 ? raw : raw.replace(/#([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
}

// The names whose every appearance in the file must be one the cleaner parsed,
// each as a pattern matching any mix of plain letters and #xx escapes.
const WATCHED = new Set(['Info', 'Metadata', 'Encrypt']);
const WATCHED_RES = [...WATCHED].map((name) => new RegExp(`/${[...name].map((ch) => {
  const h = ch.charCodeAt(0).toString(16);
  return `(?:${ch}|#${h[0]}${/[a-f]/.test(h[1]) ? `[${h[1]}${h[1].toUpperCase()}]` : h[1]})`;
}).join('')}(?![^\\x00\\x09\\x0a\\x0c\\x0d\\x20()<>\\[\\]{}/%])`, 'g'));

// End of a literal string starting at i ('('), past its closing ')'.
function literalEnd(text, i, n) {
  let p = 1;
  let k = i + 1;
  while (k < n && p > 0) {
    const d = text.charCodeAt(k);
    if (d === 0x5c) k += 2;
    else { if (d === 0x28) p++; else if (d === 0x29) p--; k++; }
  }
  if (p > 0) throw pdfRefusal();
  return k;
}

// Walks the file as a PDF reader tokenises it, recording each top level
// object ('N G obj') with the position of its header (pos), where its value
// starts (at) and its first value, every trailer dictionary, every 'xref'
// keyword and every stream with its dictionary, data and object. A structure
// it cannot follow is refused.
function pdfWalk(text) {
  const n = text.length;
  const objects = [];
  const trailers = [];
  const streams = [];
  const xrefs = [];
  let cur = null;
  let recent = [];
  let depth = 0;
  let dictStart = -1;
  let lastDict = null;
  let afterDict = false;
  let trailerNext = false;
  let i = 0;
  const firstValue = (v) => { if (cur && !cur.first) cur.first = v; };
  while (i < n) {
    const c = text.charCodeAt(i);
    if (PDF_WS.has(c)) { i++; continue; }
    if (c === 0x25) {
      while (i < n && text.charCodeAt(i) !== 0x0a && text.charCodeAt(i) !== 0x0d) i++;
      continue;
    }
    if (c === 0x28) {
      const e = literalEnd(text, i, n);
      if (depth === 0) firstValue({ type: 'string', start: i, end: e });
      i = e;
      recent = [];
      afterDict = false;
      continue;
    }
    if (c === 0x3c) {
      if (text.charCodeAt(i + 1) === 0x3c) {
        if (depth === 0) dictStart = i;
        if (++depth > PDF_NEST_LIMIT) throw pdfRefusal();
        i += 2;
        recent = [];
        afterDict = false;
        continue;
      }
      const close = text.indexOf('>', i + 1);
      if (close === -1) throw pdfRefusal();
      if (depth === 0) firstValue({ type: 'hex', start: i, end: close + 1 });
      i = close + 1;
      recent = [];
      afterDict = false;
      continue;
    }
    if (c === 0x3e) {
      if (text.charCodeAt(i + 1) !== 0x3e || depth === 0) throw pdfRefusal();
      depth--;
      i += 2;
      recent = [];
      afterDict = false;
      if (depth === 0) {
        lastDict = { start: dictStart, end: i };
        afterDict = true;
        firstValue({ type: 'dict', start: dictStart, end: i });
        if (trailerNext) { trailers.push(lastDict); trailerNext = false; }
      }
      continue;
    }
    if (c === 0x2f) {
      const s = i;
      i++;
      while (i < n && pdfRegular(text.charCodeAt(i))) i++;
      if (depth === 0) firstValue({ type: 'name', start: s, end: i });
      recent = [];
      afterDict = false;
      continue;
    }
    if (!pdfRegular(c)) { i++; recent = []; afterDict = false; continue; }
    const s = i;
    while (i < n && pdfRegular(text.charCodeAt(i))) i++;
    const tok = text.slice(s, i);
    if (depth > 0) { recent = []; continue; }
    if (tok === 'obj') {
      if (recent.length < 2 || !INT_RE.test(recent[0].tok) || !INT_RE.test(recent[1].tok)) throw pdfRefusal();
      cur = { num: Number(recent[0].tok), gen: Number(recent[1].tok), pos: recent[0].start, at: i, first: null, stream: null };
      objects.push(cur);
      if (objects.length > PDF_OBJECT_LIMIT) throw pdfRefusal();
      recent = [];
      afterDict = false;
      continue;
    }
    if (tok === 'endobj') { cur = null; recent = []; afterDict = false; continue; }
    if (tok === 'trailer') { trailerNext = true; recent = []; afterDict = false; continue; }
    if (tok === 'xref') { xrefs.push(i); recent = []; afterDict = false; continue; }
    if (tok === 'stream') {
      if (!afterDict || !lastDict) throw pdfRefusal();
      let start = i;
      while (start < n && (text.charCodeAt(start) === 0x20 || text.charCodeAt(start) === 0x09)) start++;
      if (text.charCodeAt(start) === 0x0d && text.charCodeAt(start + 1) === 0x0a) start += 2;
      else if (text.charCodeAt(start) === 0x0a || text.charCodeAt(start) === 0x0d) start++;
      else throw pdfRefusal();
      const dict = lastDict;
      let end = -1;
      let resume = -1;
      let exact = false;
      const entries = pdfDictEntries(text, dict.start, dict.end, null);
      const length = entries.get('Length');
      if (length && length.type === 'number') {
        const e = start + Number(length.value);
        const m = /^[\x00\x09\x0a\x0c\x0d\x20]*endstream/.exec(text.slice(e, e + 64));
        if (e <= n && m) { end = e; resume = e + m[0].length; exact = true; }
      }
      if (end === -1) {
        const stop = text.indexOf('endstream', start);
        if (stop === -1) throw pdfRefusal();
        end = stop;
        if (text.charCodeAt(end - 1) === 0x0a) end--;
        if (text.charCodeAt(end - 1) === 0x0d) end--;
        if (end < start) end = start;
        resume = stop + 9;
      }
      const st = { obj: cur, dict, entries, start, end, exact, lengthRef: length && length.type === 'ref' ? length : null };
      streams.push(st);
      if (cur && !cur.stream) cur.stream = st;
      i = resume;
      recent = [];
      afterDict = false;
      lastDict = null;
      continue;
    }
    if (depth === 0) firstValue({ type: INT_RE.test(tok) ? 'number' : 'word', start: s, end: i, value: tok });
    recent.push({ tok, start: s });
    if (recent.length > 2) recent.shift();
    afterDict = false;
  }
  if (depth !== 0) throw pdfRefusal();
  return { objects, trailers, streams, xrefs };
}

// Reads one value starting at i. Returns { type, start, end, value, num, gen };
// name values are decoded. With acc ({ strings, names, refs }) the string, name
// and reference tokens met at value positions (never dictionary keys) are
// added to it. With ctx ({ watch, meta }) the position of every watched name is
// added to ctx.watch and every reference held under a /Metadata key to ctx.meta.
function pdfValue(text, i, end, level, ctx, acc) {
  if (level > PDF_NEST_LIMIT) throw pdfRefusal();
  for (;;) {
    while (i < end && PDF_WS.has(text.charCodeAt(i))) i++;
    if (i >= end || text.charCodeAt(i) !== 0x25) break;
    while (i < end && text.charCodeAt(i) !== 0x0a && text.charCodeAt(i) !== 0x0d) i++;
  }
  if (i >= end) return null;
  const c = text.charCodeAt(i);
  if (c === 0x28) {
    const e = literalEnd(text, i, end);
    if (acc) acc.strings.push([i, e]);
    return { type: 'string', start: i, end: e };
  }
  if (c === 0x3c && text.charCodeAt(i + 1) !== 0x3c) {
    const close = text.indexOf('>', i + 1);
    if (close === -1 || close >= end) throw pdfRefusal();
    if (acc) acc.strings.push([i, close + 1]);
    return { type: 'hex', start: i, end: close + 1 };
  }
  if (c === 0x3c || c === 0x5b) {
    const dict = c === 0x3c;
    let k = i + (dict ? 2 : 1);
    let count = 0;
    let metaKey = false;
    for (;;) {
      while (k < end && PDF_WS.has(text.charCodeAt(k))) k++;
      if (k < end && text.charCodeAt(k) === 0x25) {
        while (k < end && text.charCodeAt(k) !== 0x0a && text.charCodeAt(k) !== 0x0d) k++;
        continue;
      }
      if (k >= end) throw pdfRefusal();
      if (dict && text.charCodeAt(k) === 0x3e && text.charCodeAt(k + 1) === 0x3e) { k += 2; break; }
      if (!dict && text.charCodeAt(k) === 0x5d) { k += 1; break; }
      const isKey = dict && count % 2 === 0;
      const v = pdfValue(text, k, end, level + 1, ctx, isKey ? null : acc);
      if (!v) throw pdfRefusal();
      if (isKey) {
        if (v.type !== 'name') throw pdfRefusal();
        metaKey = v.value === 'Metadata';
      } else if (dict && metaKey && v.type === 'ref' && ctx) {
        ctx.meta.push({ num: v.num, gen: v.gen });
      }
      count++;
      k = v.end;
    }
    if (dict && count % 2 !== 0) throw pdfRefusal();
    return { type: dict ? 'dict' : 'array', start: i, end: k };
  }
  if (c === 0x2f) {
    let k = i + 1;
    while (k < end && pdfRegular(text.charCodeAt(k))) k++;
    const value = decodePdfName(text.slice(i + 1, k));
    if (ctx && WATCHED.has(value)) ctx.watch.add(i);
    if (acc) acc.names.push([i, k]);
    return { type: 'name', start: i, end: k, value };
  }
  if (!pdfRegular(c)) throw pdfRefusal();
  let k = i;
  while (k < end && pdfRegular(text.charCodeAt(k))) k++;
  const tok = text.slice(i, k);
  // An indirect reference: 'N G R'.
  const m = /^[\x00\x09\x0a\x0c\x0d\x20]+(\d+)[\x00\x09\x0a\x0c\x0d\x20]+R(?![^\x00\x09\x0a\x0c\x0d\x20()<>[\]{}/%])/.exec(text.slice(k, Math.min(end, k + 40)));
  if (INT_RE.test(tok) && m) {
    const r = { num: Number(tok), gen: Number(m[1]) };
    if (acc) acc.refs.push(r);
    return { type: 'ref', start: i, end: k + m[0].length, num: r.num, gen: r.gen };
  }
  return { type: INT_RE.test(tok) ? 'number' : 'word', start: i, end: k, value: tok };
}

const newAcc = () => ({ strings: [], names: [], refs: [] });

// The entries of the dictionary text[start, end) as a Map of decoded key →
// value, each value carrying the strings, names and references inside it; the
// Map's list holds every entry in order with its key position. A key that
// matters to the cleaner written twice is refused (readers differ on which
// copy they take).
const SINGLE_KEYS = new Set(['Info', 'Encrypt', 'Type', 'Subtype', 'Metadata', 'Filter', 'DecodeParms', 'Length', 'W', 'Index', 'Size', 'N', 'First']);

function pdfDictEntries(text, start, end, ctx) {
  const map = new Map();
  map.list = [];
  let k = start + 2;
  const stop = end - 2;
  for (;;) {
    while (k < stop && PDF_WS.has(text.charCodeAt(k))) k++;
    if (k >= stop) break;
    if (text.charCodeAt(k) === 0x25) {
      while (k < stop && text.charCodeAt(k) !== 0x0a && text.charCodeAt(k) !== 0x0d) k++;
      continue;
    }
    const key = pdfValue(text, k, stop, 1, ctx, null);
    if (!key || key.type !== 'name') throw pdfRefusal();
    const acc = newAcc();
    const value = pdfValue(text, key.end, stop, 1, ctx, acc);
    if (!value) throw pdfRefusal();
    if (ctx && key.value === 'Metadata' && value.type === 'ref') ctx.meta.push({ num: value.num, gen: value.gen });
    Object.assign(value, acc);
    if (map.has(key.value) && SINGLE_KEYS.has(key.value)) throw pdfRefusal();
    map.set(key.value, value);
    map.list.push({ key: key.value, keyStart: key.start, keyEnd: key.end, value });
    k = value.end;
  }
  return map;
}

// The integers of an array value, or a refusal.
function pdfInts(text, v) {
  if (!v || v.type !== 'array') throw pdfRefusal();
  const toks = text.slice(v.start + 1, v.end - 1).split(/[\x00\x09\x0a\x0c\x0d\x20]+/).filter(Boolean);
  if (toks.some((t) => !INT_RE.test(t))) throw pdfRefusal();
  return toks.map(Number);
}

// The decoded filter names of a stream.
function pdfFilters(text, entries) {
  const f = entries.get('Filter');
  if (!f) return [];
  if (f.type === 'name') return [f.value];
  if (f.type === 'array') return f.names.map(([s, e]) => decodePdfName(text.slice(s + 1, e)));
  throw pdfRefusal();
}

// Replaces the inside of a string token with spaces. True when a byte changed.
function blankString(out, s, e) {
  let changed = false;
  for (let k = s + 1; k < e - 1; k++) {
    if (out[k] !== 0x20) { out[k] = 0x20; changed = true; }
  }
  return changed;
}

// Replaces the characters of a name after its '/' with X (a regular character,
// so the name keeps its length and ends where it did). True when a byte changed.
function blankName(out, s, e) {
  let changed = false;
  for (let k = s + 1; k < e; k++) {
    if (out[k] !== 0x58) { out[k] = 0x58; changed = true; }
  }
  return changed;
}

// A zlib stream of exactly total bytes that inflates to spaces (stored blocks).
function storedSpaces(total) {
  const blocks = Math.max(1, Math.ceil((total - 6) / 65540));
  const payload = total - 6 - 5 * blocks;
  if (payload < 0 || payload > 65535 * blocks) return null;
  const out = new Uint8Array(total);
  out[0] = 0x78;
  out[1] = 0x01;
  let o = 2;
  let left = payload;
  for (let k = 0; k < blocks; k++) {
    const n = k === blocks - 1 ? left : Math.min(65535, left);
    out[o] = k === blocks - 1 ? 1 : 0;
    out.set(le16(n), o + 1);
    out.set(le16(~n & 0xffff), o + 3);
    out.fill(0x20, o + 5, o + 5 + n);
    o += 5 + n;
    left -= n;
  }
  let a = 1;
  let bsum = 0;
  for (let k = 0; k < payload; k++) {
    a = (a + 0x20) % 65521;
    bsum = (bsum + a) % 65521;
  }
  const adler = ((bsum << 16) | a) >>> 0;
  out.set(Uint8Array.of(adler >>> 24, (adler >>> 16) & 0xff, (adler >>> 8) & 0xff, adler & 0xff), o);
  return out;
}

// Every place in the raw text where a reader could read an object header
// 'N G obj' (white space or comments between the parts, 'N' starting at any
// digit run), as a Map of object number → positions of N.
function rawObjectHeaders(text) {
  const n = text.length;
  const found = new Map();
  const gap = (k) => {
    const s = k;
    for (;;) {
      while (k < n && PDF_WS.has(text.charCodeAt(k))) k++;
      if (k < n && text.charCodeAt(k) === 0x25) {
        while (k < n && text.charCodeAt(k) !== 0x0a && text.charCodeAt(k) !== 0x0d) k++;
        continue;
      }
      return k > s ? k : -1;
    }
  };
  let i = 0;
  while (i < n) {
    if (!pdfDigit(text.charCodeAt(i))) { i++; continue; }
    const s = i;
    while (i < n && pdfDigit(text.charCodeAt(i))) i++;
    let k = gap(i);
    if (k === -1 || !pdfDigit(text.charCodeAt(k))) continue;
    while (k < n && pdfDigit(text.charCodeAt(k))) k++;
    k = gap(k);
    if (k === -1 || !text.startsWith('obj', k)) continue;
    const num = Number(text.slice(s, i));
    if (!found.has(num)) found.set(num, []);
    found.get(num).push(s);
  }
  return found;
}

// The exact end of a stream's data: its direct /Length, or an indirect /Length
// whose every top level copy gives the same number.
function pdfStreamEnd(text, st, copiesOf) {
  if (st.exact) return st.end;
  if (!st.lengthRef) throw pdfRefusal();
  const lens = new Set(copiesOf(st.lengthRef).map((o) => (o.first && o.first.type === 'number' ? o.first.value : null)));
  if (lens.size !== 1 || lens.has(null)) throw pdfRefusal();
  const end = st.start + Number([...lens][0]);
  if (end > text.length || !/^[\x00\x09\x0a\x0c\x0d\x20]*endstream/.test(text.slice(end, end + 64))) throw pdfRefusal();
  return end;
}

// The decoded data of a stream the cleaner must read (an object stream or a
// cross reference stream): no filter or FlateDecode, with the PNG predictors
// of a cross reference stream when parms is true. budget.left caps the bytes
// inflated over the whole file.
async function pdfStreamData(b, text, st, copiesOf, budget, parms) {
  const end = pdfStreamEnd(text, st, copiesOf);
  let data = b.subarray(st.start, end);
  const filters = pdfFilters(text, st.entries);
  if (filters.length > 1 || (filters.length === 1 && filters[0] !== 'FlateDecode')) throw pdfRefusal();
  if (filters.length) {
    let r;
    try {
      r = await inflate(data, 'deflate', budget.left, true);
    } catch (_) {
      throw pdfRefusal();
    }
    budget.left -= r.size;
    data = r.bytes;
  }
  const dp = st.entries.get('DecodeParms');
  if (!dp) return data;
  if (!parms || !filters.length || dp.type !== 'dict') throw pdfRefusal();
  const p = pdfDictEntries(text, dp.start, dp.end, null);
  const num = (key, dflt) => {
    const v = p.get(key);
    if (!v) return dflt;
    if (v.type !== 'number') throw pdfRefusal();
    return Number(v.value);
  };
  const predictor = num('Predictor', 1);
  if (num('Colors', 1) !== 1 || num('BitsPerComponent', 8) !== 8) throw pdfRefusal();
  if (predictor === 1) return data;
  if (predictor < 10 || predictor > 15) throw pdfRefusal();
  return unpredictPng(data, num('Columns', 1));
}

// Undoes the PNG row filters (one byte per pixel).
function unpredictPng(data, columns) {
  const row = columns + 1;
  if (columns < 1 || data.length % row !== 0) throw pdfRefusal();
  const rows = data.length / row;
  const out = new Uint8Array(rows * columns);
  for (let r = 0; r < rows; r++) {
    const ft = data[r * row];
    const o = r * columns;
    for (let x = 0; x < columns; x++) {
      const raw = data[r * row + 1 + x];
      const left = x > 0 ? out[o + x - 1] : 0;
      const up = r > 0 ? out[o - columns + x] : 0;
      const ul = r > 0 && x > 0 ? out[o - columns + x - 1] : 0;
      let v;
      if (ft === 0) v = raw;
      else if (ft === 1) v = raw + left;
      else if (ft === 2) v = raw + up;
      else if (ft === 3) v = raw + ((left + up) >> 1);
      else if (ft === 4) {
        const pa = Math.abs(up - ul);
        const pb = Math.abs(left - ul);
        const pc = Math.abs(left + up - 2 * ul);
        v = raw + (pa <= pb && pa <= pc ? left : pb <= pc ? up : ul);
      } else throw pdfRefusal();
      out[o + x] = v & 0xff;
    }
  }
  return out;
}

// Every compressed object stream: the object numbers it holds, and the
// references its objects hold under a /Metadata key (a catalogue packed in an
// object stream still names its XMP stream). A stream it cannot read is refused.
async function pdfObjectStreams(b, text, streams, copiesOf, budget) {
  const nums = new Set();
  const meta = [];
  for (const st of streams) {
    const t = st.entries.get('Type');
    if (!t || t.type !== 'name' || t.value !== 'ObjStm') continue;
    const first = st.entries.get('First');
    const count = st.entries.get('N');
    if (!first || first.type !== 'number' || !count || count.type !== 'number') throw pdfRefusal();
    const data = await pdfStreamData(b, text, st, copiesOf, budget, false);
    const s = latin1(data);
    const at = Number(first.value);
    if (at > s.length) throw pdfRefusal();
    const tokens = s.slice(0, at).trim().split(/[\x00\x09\x0a\x0c\x0d\x20]+/).filter(Boolean);
    if (tokens.length < 2 * Number(count.value) || tokens.some((x) => !INT_RE.test(x))) throw pdfRefusal();
    const inner = { watch: new Set(), meta };
    for (let k = 0; k < 2 * Number(count.value); k += 2) {
      nums.add(Number(tokens[k]));
      const off = at + Number(tokens[k + 1]);
      if (off >= s.length) throw pdfRefusal();
      pdfValue(s, off, s.length, 1, inner, null);
    }
  }
  return { nums, meta };
}

// Every cross reference entry of the file, from each 'xref' table and each
// cross reference stream: in use objects as a Map of number → [{ gen, offset }],
// and the numbers stored in object streams. An entry it cannot read is refused.
async function pdfCrossReference(b, text, walk, copiesOf, budget) {
  const n = text.length;
  const offsets = new Map();
  const packed = new Set();
  let total = 0;
  const add = (num, gen, offset) => {
    if (++total > PDF_OBJECT_LIMIT) throw pdfRefusal();
    if (!offsets.has(num)) offsets.set(num, []);
    offsets.get(num).push({ gen, offset });
  };
  for (const at of walk.xrefs) {
    let k = at;
    const next = () => {
      while (k < n && PDF_WS.has(text.charCodeAt(k))) k++;
      const s = k;
      while (k < n && pdfRegular(text.charCodeAt(k))) k++;
      return text.slice(s, k);
    };
    for (;;) {
      const tok = next();
      if (tok === 'trailer' || tok === '') break;
      const count = next();
      if (!INT_RE.test(tok) || !INT_RE.test(count)) throw pdfRefusal();
      let num = Number(tok);
      for (let c = 0; c < Number(count); c++, num++) {
        const off = next();
        const gen = next();
        const kind = next();
        if (!INT_RE.test(off) || !INT_RE.test(gen) || (kind !== 'n' && kind !== 'f')) throw pdfRefusal();
        if (kind === 'n') add(num, Number(gen), Number(off));
      }
    }
  }
  for (const st of walk.streams) {
    const t = st.entries.get('Type');
    if (!t || t.type !== 'name' || t.value !== 'XRef') continue;
    const w = pdfInts(text, st.entries.get('W'));
    if (w.length !== 3 || w.some((x) => x > 8)) throw pdfRefusal();
    const size = st.entries.get('Size');
    if (!size || size.type !== 'number') throw pdfRefusal();
    const index = st.entries.has('Index') ? pdfInts(text, st.entries.get('Index')) : [0, Number(size.value)];
    if (index.length % 2 !== 0) throw pdfRefusal();
    const data = await pdfStreamData(b, text, st, copiesOf, budget, true);
    const width = w[0] + w[1] + w[2];
    const field = (p, len, dflt) => {
      if (!len) return dflt;
      let v = 0;
      for (let q = 0; q < len; q++) v = v * 256 + data[p + q];
      return v;
    };
    let p = 0;
    for (let x = 0; x < index.length; x += 2) {
      for (let c = 0; c < index[x + 1]; c++) {
        if (p + width > data.length) throw pdfRefusal();
        const type = field(p, w[0], 1);
        const f2 = field(p + w[0], w[1], 0);
        const f3 = field(p + w[0] + w[1], w[2], 0);
        if (type === 1) add(index[x] + c, f3, f2);
        else if (type === 2) packed.add(index[x] + c);
        p += width;
      }
    }
  }
  return { offsets, packed };
}

const INFO_LABELS = Object.freeze({
  Author: 'author', Title: 'title', Subject: 'title', Keywords: 'title',
  Creator: 'software', Producer: 'software', CreationDate: 'dates', ModDate: 'dates',
});
const TRAPPED = new Set(['True', 'False', 'Unknown']);

async function cleanPdf(b, removed) {
  if (!startsWith(b, ascii('%PDF-'))) throw unreadable();
  const text = latin1(b);
  const n = text.length;
  const walk = pdfWalk(text);
  const byKey = new Map();
  const byPos = new Map();
  for (const o of walk.objects) {
    const k = `${o.num} ${o.gen}`;
    if (!byKey.has(k)) byKey.set(k, []);
    byKey.get(k).push(o);
    byPos.set(o.pos, o);
  }
  const copiesOf = (r) => {
    const list = byKey.get(`${r.num} ${r.gen}`);
    if (!list || !list.length) throw pdfRefusal();
    return list;
  };

  // Every top level value and trailer is read once: the positions of the
  // watched names it holds, and the references under /Metadata keys.
  const ctx = { watch: new Set(), meta: [] };
  for (const o of walk.objects) pdfValue(text, o.at, n, 1, ctx, null);
  const trailerDicts = walk.trailers.map((d) => pdfDictEntries(text, d.start, d.end, ctx));
  for (const re of WATCHED_RES) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(text)) !== null) if (!ctx.watch.has(m.index)) throw pdfRefusal();
  }
  for (const st of walk.streams) {
    const t = st.entries.get('Type');
    if (t && t.type === 'name' && t.value === 'XRef') trailerDicts.push(st.entries);
  }
  if (!trailerDicts.length) throw pdfRefusal();

  const infoRefs = [];
  for (const t of trailerDicts) {
    if (t.has('Encrypt')) throw pdfRefusal();
    const info = t.get('Info');
    if (!info) continue;
    if (info.type !== 'ref') throw pdfRefusal();
    infoRefs.push(info);
  }

  const budget = { left: OBJSTM_LIMIT };
  const packedStreams = await pdfObjectStreams(b, text, walk.streams, copiesOf, budget);
  const metaRefs = ctx.meta.concat(packedStreams.meta);
  const xref = infoRefs.length || metaRefs.length
    ? await pdfCrossReference(b, text, walk, copiesOf, budget)
    : { offsets: new Map(), packed: new Set() };
  const headers = infoRefs.length || metaRefs.length ? rawObjectHeaders(text) : new Map();

  // The top level objects a reference names. Refused when the object sits in a
  // compressed object stream, is not written at the top level at all, when a
  // cross reference entry for it lands anywhere but on a parsed object of that
  // number, or when its header also appears where the walker did not parse it.
  const resolved = new Map();
  const resolve = (r) => {
    const key = `${r.num} ${r.gen}`;
    if (resolved.has(key)) return resolved.get(key);
    if (packedStreams.nums.has(r.num) || xref.packed.has(r.num)) throw pdfRefusal();
    const list = copiesOf(r);
    for (const e of xref.offsets.get(r.num) || []) {
      if (e.gen !== r.gen) continue;
      let p = e.offset;
      while (p < n && PDF_WS.has(text.charCodeAt(p))) p++;
      const o = byPos.get(p);
      if (!o || o.num !== r.num || o.gen !== r.gen) throw pdfRefusal();
    }
    for (const p of headers.get(r.num) || []) {
      const o = byPos.get(p);
      if (!o || o.num !== r.num) throw pdfRefusal();
    }
    resolved.set(key, list);
    return list;
  };

  const out = new Uint8Array(b);
  let changed = false;
  let work = 0;
  const count = (k) => { work += k; if (work > PDF_REF_LIMIT) throw pdfRefusal(); };

  // Each object is blanked once, however many references name it.
  const valueDone = new Map();
  const blankValueObject = (o) => {
    if (valueDone.has(o)) return valueDone.get(o);
    const acc = newAcc();
    const v = pdfValue(text, o.at, n, 1, null, acc);
    if (!v || v.type === 'dict' || acc.refs.length) throw pdfRefusal();
    let hit = false;
    for (const [s, e] of acc.strings) hit = blankString(out, s, e) || hit;
    for (const [s, e] of acc.names) hit = blankName(out, s, e) || hit;
    count(acc.strings.length + acc.names.length + 1);
    valueDone.set(o, hit);
    return hit;
  };

  // Every copy of the object a reference names, once per object number.
  const refDone = new Map();
  const blankValueRef = (r) => {
    const key = `${r.num} ${r.gen}`;
    if (!refDone.has(key)) {
      let hit = false;
      for (const target of resolve(r)) hit = blankValueObject(target) || hit;
      refDone.set(key, hit);
    }
    return refDone.get(key);
  };

  const infoDone = new Set();
  for (const ref of infoRefs) {
    for (const obj of resolve(ref)) {
      if (infoDone.has(obj)) continue;
      infoDone.add(obj);
      const v = pdfValue(text, obj.at, n, 1, null, null);
      if (!v || v.type !== 'dict') throw pdfRefusal();
      const entries = pdfDictEntries(text, v.start, v.end, null);
      for (const { key, keyStart, keyEnd, value } of entries.list) {
        let hit = false;
        const label = INFO_LABELS[key] || 'other';
        // A key outside the standard set is itself a detail (its name is shown).
        if (!INFO_LABELS[key] && key !== 'Trapped') hit = blankName(out, keyStart, keyEnd) || hit;
        for (const [s, e] of value.strings) hit = blankString(out, s, e) || hit;
        if (!(key === 'Trapped' && value.type === 'name' && TRAPPED.has(value.value))) {
          for (const [s, e] of value.names) hit = blankName(out, s, e) || hit;
        }
        count(value.strings.length + value.names.length + value.refs.length + 1);
        for (const r of value.refs) hit = blankValueRef(r) || hit;
        if (hit) { changed = true; removed.add(label); }
      }
    }
  }

  // Every XMP metadata stream: typed /Metadata or /Subtype /XML, and every
  // stream a /Metadata key names, whatever its type says.
  const metaStreams = new Set();
  for (const st of walk.streams) {
    const t = st.entries.get('Type');
    const sub = st.entries.get('Subtype');
    if ((t && t.type === 'name' && t.value === 'Metadata') || (sub && sub.type === 'name' && sub.value === 'XML')) metaStreams.add(st);
  }
  for (const r of metaRefs) {
    count(1);
    for (const o of resolve(r)) {
      if (!o.stream) throw pdfRefusal();
      metaStreams.add(o.stream);
    }
  }
  for (const st of metaStreams) {
    if (st.end <= st.start) continue;
    const names = pdfFilters(text, st.entries);
    let hit = false;
    if (!names.length) {
      for (let k = st.start; k < st.end; k++) if (out[k] !== 0x20) { out[k] = 0x20; hit = true; }
    } else {
      if (names.length !== 1 || names[0] !== 'FlateDecode' || st.entries.has('DecodeParms')) throw pdfRefusal();
      // The exact data length is needed to replace the compressed bytes with a
      // stream of the same size.
      const end = pdfStreamEnd(text, st, (r) => resolve(r));
      const blank = storedSpaces(end - st.start);
      if (!blank) throw pdfRefusal();
      if (!sameBytes(out.subarray(st.start, end), blank)) { out.set(blank, st.start); hit = true; }
    }
    if (hit) { changed = true; removed.add('xmp'); }
  }
  return changed ? out : null;
}

// 7. CSV -------------------------------------------------------------------------------

function cleanCsv(b, removed) {
  try {
    new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(b);
  } catch (_) {
    throw unreadable();
  }
  if (b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) {
    removed.add('byte_order_mark');
    return b.slice(3);
  }
  return null;
}

// 8. cleanMetadata ----------------------------------------------------------------------

// Never throws. A refusal carries bytes null and the plain reason for the client.
export async function cleanMetadata(input) {
  const o = input || {};
  const removed = createRemoved();
  const refuse = (reason) => ({ outcome: 'refused', bytes: null, removed: [], reason });
  try {
    const bytes = toUint8(o.bytes);
    const mime = typeof o.mimeType === 'string' ? o.mimeType.trim().toLowerCase() : '';
    const kind = KINDS[mime];
    if (!kind) return refuse(REFUSALS.type);
    if (kind === 'legacy') return refuse(REFUSALS.legacy);
    if (!bytes.length) return refuse(REFUSALS.unreadable);
    let cleaned = null;
    if (kind === 'jpeg') cleaned = cleanJpeg(bytes, removed);
    else if (kind === 'png') cleaned = cleanPng(bytes, removed);
    else if (kind === 'ooxml') cleaned = await cleanOoxml(bytes, removed, uploadDay(o.uploadedAt));
    else if (kind === 'pdf') cleaned = await cleanPdf(bytes, removed);
    else if (kind === 'csv') cleaned = cleanCsv(bytes, removed);
    if (cleaned === null || sameBytes(cleaned, bytes)) {
      return { outcome: 'unchanged', bytes, removed: [], reason: null };
    }
    return { outcome: 'cleaned', bytes: cleaned, removed: removed.list(), reason: null };
  } catch (err) {
    return refuse(err instanceof Refusal ? err.reason : REFUSALS.unreadable);
  }
}
