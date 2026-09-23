// CNC HSF FORGE | HSF-SCAN-01 v1.0.0 | Security scan of staged uploads 23/09/2026
//
// Every document a company drops into its Health and Safety File is scanned
// before it can move to MyClinicOnline (contract 10.4). Plain ES module: no
// dependencies, only the globals fetch, crypto.subtle, TextDecoder and
// DecompressionStream, so the same file runs in the Supabase edge function
// (Deno) and under node --test (Node 22).
//
// Two checks, both mandatory:
//   1. inspectBytes, the built in structural check, always runs. It flags as
//      harmful: content whose first bytes do not match the declared type; PDF
//      active content (JavaScript, launch actions, embedded files, rich media,
//      XFA forms, automatic actions), including names hidden with #xx escapes or
//      inside compressed object streams (each stream is paired with its
//      dictionary by walking the file as a PDF reader does, so text in a
//      string or a padded dictionary cannot hide an object stream); OOXML macros (vbaProject.bin), ActiveX,
//      embedded OLE objects and relationships that load content from outside
//      when the document opens; legacy Office macros and embedded objects; CSV
//      cells that start like a formula; images carrying GPS location details or
//      more than 256 KB of metadata.
//   2. createAvEngine, the HTTP antivirus engine at HSF_AV_ENDPOINT with the
//      bearer HSF_AV_TOKEN. Without both, every scan records 'error' with the
//      finding 'Antivirus engine not configured', and the file never transfers.
//      A fixture engine that answers clean exists for tests only and needs
//      HSF_SCAN_ALLOW_FIXTURE=1, which is never set in production.
//
// Anything that cannot be inspected (a truncated structure, a zip64 or
// encrypted archive, a compression method the runtime cannot read, a runtime
// without DecompressionStream) is 'error', never 'clean'. Harmful wins over
// error, and error wins over clean.
//
// scanUpload runs one claimed upload: download, fingerprint check, inspectBytes,
// the antivirus engine, then hsf_scan_record. One document in memory at a time.
// Findings carry plain words for the client and never the file name, the file
// content or a key.

import { isSha256Hex, sha256Hex as defaultSha256Hex } from './mco-adapter.js';

export const INSPECT_ENGINE = 'hsf-inspect-1.0';
export const METADATA_LIMIT_BYTES = 256 * 1024;
export const AV_NOT_CONFIGURED = 'Antivirus engine not configured';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEFAULT_AV_TIMEOUT_MS = 120000;
const RELS_LIMIT_BYTES = 2 * 1024 * 1024;
const OBJSTM_LIMIT_BYTES = 64 * 1024 * 1024;
const TEXT_CHUNK_LIMIT_BYTES = 1024 * 1024;
const ZIP_ENTRY_LIMIT = 20000;

// The declared types hsf.upload_allowed_mime accepts, with the file name endings
// each may carry.
const KINDS = Object.freeze({
  'application/pdf': { kind: 'pdf', ext: ['pdf'] },
  'image/jpeg': { kind: 'jpeg', ext: ['jpg', 'jpeg', 'jpe'] },
  'image/png': { kind: 'png', ext: ['png'] },
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': { kind: 'ooxml', part: 'word/', ext: ['docx'] },
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': { kind: 'ooxml', part: 'xl/', ext: ['xlsx'] },
  'application/msword': { kind: 'ole', ext: ['doc'] },
  'application/vnd.ms-excel': { kind: 'ole', ext: ['xls'] },
  'text/csv': { kind: 'csv', ext: ['csv', 'txt'] },
});

// Plain words for the client. The database builds the rejection reason from these.
const MESSAGES = Object.freeze({
  type_not_allowed: 'This type of file is not accepted.',
  type_mismatch: 'The file content does not match its file type.',
  name_mismatch: 'The file name ending does not match its file type.',
  pdf_javascript: 'The PDF contains JavaScript.',
  pdf_launch: 'The PDF can start other programs.',
  pdf_embedded_file: 'The PDF carries embedded files.',
  pdf_rich_media: 'The PDF contains rich media.',
  pdf_xfa: 'The PDF contains an XFA form, which can run scripts.',
  pdf_auto_action: 'The PDF runs actions automatically.',
  office_macros: 'The document contains macros.',
  office_activex: 'The document contains ActiveX controls.',
  office_embedded_object: 'The document contains an embedded object.',
  office_external_link: 'The document loads content from an outside address when it opens.',
  csv_formula: 'The spreadsheet has cells that start like a formula, which could run when it is opened.',
  location_metadata: 'The image carries location (GPS) details.',
  oversized_metadata: 'The image carries more than 256 KB of hidden details (metadata).',
  fingerprint_mismatch: 'The stored file does not match the fingerprint taken when it was uploaded.',
  malware: 'The antivirus scan found a known threat.',
});

// 1. Small helpers --------------------------------------------------------------

class InspectError extends Error {}

function messageOf(err) {
  const m = err && typeof err.message === 'string' ? err.message : String(err);
  return m.slice(0, 300);
}

function toUint8(v) {
  if (v instanceof Uint8Array) return v;
  if (v instanceof ArrayBuffer) return new Uint8Array(v);
  if (ArrayBuffer.isView(v)) return new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
  throw new TypeError('The file is not bytes.');
}

function lowerHex(v) {
  return typeof v === 'string' ? v.trim().toLowerCase() : '';
}

function startsWith(bytes, sig, at) {
  const o = at || 0;
  if (bytes.length < o + sig.length) return false;
  for (let i = 0; i < sig.length; i++) if (bytes[o + i] !== sig[i]) return false;
  return true;
}

function ascii(s) {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff;
  return out;
}

function utf16le(s) {
  const out = new Uint8Array(s.length * 2);
  for (let i = 0; i < s.length; i++) out[i * 2] = s.charCodeAt(i) & 0xff;
  return out;
}

// First index of needle in hay, using the native indexOf to find candidates.
function indexOfBytes(hay, needle, from) {
  if (!needle.length) return -1;
  const first = needle[0];
  let i = hay.indexOf(first, from || 0);
  while (i !== -1 && i + needle.length <= hay.length) {
    let ok = true;
    for (let j = 1; j < needle.length; j++) {
      if (hay[i + j] !== needle[j]) { ok = false; break; }
    }
    if (ok) return i;
    i = hay.indexOf(first, i + 1);
  }
  return -1;
}

// Bytes as a string of char codes 0 to 255, in slices, for keyword searches.
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

// Inflate with DecompressionStream ('deflate-raw' for zip entries, 'deflate'
// for zlib wrapped PDF and PNG streams), refusing to grow past limit bytes.
async function inflate(data, format, limit) {
  if (typeof DecompressionStream !== 'function') {
    throw new InspectError('this runtime cannot decompress the file');
  }
  let ds;
  try {
    ds = new DecompressionStream(format);
  } catch (_) {
    throw new InspectError('this runtime cannot decompress the file');
  }
  const writer = ds.writable.getWriter();
  writer.write(data).catch(() => {});
  writer.close().catch(() => {});
  const reader = ds.readable.getReader();
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > limit) {
        reader.cancel().catch(() => {});
        throw new InspectError('a compressed part is larger than the scan allows');
      }
      chunks.push(value);
    }
  } catch (err) {
    if (err instanceof InspectError) throw err;
    throw new InspectError('a compressed part could not be read');
  }
  const out = new Uint8Array(total);
  let o = 0;
  for (const c of chunks) { out.set(c, o); o += c.length; }
  return out;
}

function fileExtension(name) {
  if (typeof name !== 'string') return '';
  const base = name.split('/').pop();
  const dot = base.lastIndexOf('.');
  return dot > 0 && dot < base.length - 1 ? base.slice(dot + 1).toLowerCase() : '';
}

// 2. PDF ------------------------------------------------------------------------

const PDF_SIG = ascii('%PDF-');
const PDF_NAMES = Object.freeze({
  javascript: 'pdf_javascript',
  js: 'pdf_javascript',
  launch: 'pdf_launch',
  embeddedfile: 'pdf_embedded_file',
  embeddedfiles: 'pdf_embedded_file',
  richmedia: 'pdf_rich_media',
  xfa: 'pdf_xfa',
  aa: 'pdf_auto_action',
});
const PDF_NAME_RE = /\/([^\x00\x09\x0a\x0c\x0d\x20/[\]<>(){}%]+)/g;

// PDF names may hide letters behind #xx escapes (/J#61vaScript is /JavaScript).
function decodePdfName(raw) {
  return raw.replace(/#([0-9A-Fa-f]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
}

function pdfNameCodes(text, add) {
  PDF_NAME_RE.lastIndex = 0;
  let m;
  while ((m = PDF_NAME_RE.exec(text)) !== null) {
    const code = PDF_NAMES[decodePdfName(m[1]).toLowerCase()];
    if (code) add(code);
  }
}

// PDF white space and delimiters (ISO 32000 7.2.2). Everything else is a
// regular character that belongs to a keyword, number or name.
function pdfRegular(c) {
  return !(c === 0x00 || c === 0x09 || c === 0x0a || c === 0x0c || c === 0x0d || c === 0x20
    || c === 0x28 || c === 0x29 || c === 0x3c || c === 0x3e || c === 0x5b || c === 0x5d
    || c === 0x7b || c === 0x7d || c === 0x2f || c === 0x25);
}

// Every 'stream' keyword as a PDF reader would find it: preceded by white space
// or a delimiter and followed by an end of line. Used to prove the lexer below
// saw every stream in the file.
const PDF_STREAM_KW_RE = /(?:^|[\x00\x09\x0a\x0c\x0d\x20()<>[\]{}/%])stream(?:\r\n|\n|\r)/g;

// Walks the file the way a PDF reader tokenises it (comments, literal strings
// with nesting and escapes, hex strings, dictionaries) so that each stream is
// paired with the dictionary written immediately before it. Text inside a
// string or a comment can therefore never pose as, or hide, a stream
// dictionary. Stream data is skipped using a direct /Length when 'endstream'
// follows it, otherwise up to the next 'endstream'. Returns the streams as
// { dict, start, end }, or null after calling fail when the structure cannot be
// followed (the file is then 'could not inspect', never clean).
function pdfStreams(text, fail) {
  const n = text.length;
  const out = [];
  const seen = new Set();
  const skipped = [];
  let i = 0;
  let depth = 0;
  let dictStart = -1;
  let lastDict = null;
  let afterDict = false;
  while (i < n) {
    const c = text.charCodeAt(i);
    if (c === 0x00 || c === 0x09 || c === 0x0a || c === 0x0c || c === 0x0d || c === 0x20) { i++; continue; }
    if (c === 0x25) { // % comment to the end of the line
      while (i < n && text.charCodeAt(i) !== 0x0a && text.charCodeAt(i) !== 0x0d) i++;
      continue;
    }
    if (c === 0x28) { // ( literal string, balanced parentheses, backslash escapes
      let p = 1;
      i++;
      while (i < n && p > 0) {
        const d = text.charCodeAt(i);
        if (d === 0x5c) i += 2;
        else { if (d === 0x28) p++; else if (d === 0x29) p--; i++; }
      }
      if (p > 0) { fail('a PDF string is not closed'); return null; }
      afterDict = false;
      continue;
    }
    if (c === 0x3c) {
      if (text.charCodeAt(i + 1) === 0x3c) {
        if (depth === 0) dictStart = i;
        depth++;
        i += 2;
        afterDict = false;
        continue;
      }
      const close = text.indexOf('>', i + 1);
      if (close === -1) { fail('a PDF hex string is not closed'); return null; }
      i = close + 1;
      afterDict = false;
      continue;
    }
    if (c === 0x3e) {
      if (text.charCodeAt(i + 1) !== 0x3e || depth === 0) { fail('the PDF dictionaries are not balanced'); return null; }
      depth--;
      i += 2;
      if (depth === 0) { lastDict = [dictStart, i]; afterDict = true; } else afterDict = false;
      continue;
    }
    if (c === 0x2f) { // name
      i++;
      while (i < n && pdfRegular(text.charCodeAt(i))) i++;
      afterDict = false;
      continue;
    }
    if (!pdfRegular(c)) { i++; afterDict = false; continue; } // [ ] { } ) outside a string
    const s = i;
    while (i < n && pdfRegular(text.charCodeAt(i))) i++;
    if (i - s !== 6 || text.slice(s, i) !== 'stream') { afterDict = false; continue; }

    // The stream keyword: it must follow its dictionary directly.
    if (!afterDict || depth !== 0) { fail('a PDF stream has no dictionary the scan can read'); return null; }
    seen.add(s);
    let start = i;
    while (start < n && (text.charCodeAt(start) === 0x20 || text.charCodeAt(start) === 0x09)) start++;
    if (text.charCodeAt(start) === 0x0d && text.charCodeAt(start + 1) === 0x0a) start += 2;
    else if (text.charCodeAt(start) === 0x0a || text.charCodeAt(start) === 0x0d) start++;
    else { fail('a PDF stream keyword is not followed by a line end'); return null; }
    const dict = text.slice(lastDict[0], lastDict[1]);
    // A direct /Length is used when endstream follows it; otherwise the data
    // runs to the next endstream.
    let end = -1;
    let resume = -1;
    const len = /\/Length\s+(\d+)(?![\s\d]*R)/.exec(dict);
    if (len) {
      const e = start + Number(len[1]);
      const m = /^[\x00\x09\x0a\x0c\x0d\x20]*endstream/.exec(text.slice(e, e + 64));
      if (e <= n && m) { end = e; resume = e + m[0].length; }
    }
    if (end === -1) {
      const stop = text.indexOf('endstream', start);
      if (stop === -1) { fail('a PDF stream is not closed'); return null; }
      end = stop;
      if (text.charCodeAt(end - 1) === 0x0a) end--;
      if (text.charCodeAt(end - 1) === 0x0d) end--;
      if (end < start) end = start;
      resume = stop + 9;
    }
    out.push({ dict, start, end });
    skipped.push([start, resume]);
    i = resume;
    afterDict = false;
    lastDict = null;
  }
  if (depth !== 0) { fail('the PDF dictionaries are not balanced'); return null; }

  // Every stream keyword a reader could find must be one the walk paired with
  // its dictionary, or lie inside stream data it skipped. Anything else means
  // the walk lost step with the file (for example a string that swallows a
  // stream), so the file is not inspected rather than passed.
  PDF_STREAM_KW_RE.lastIndex = 0;
  let m;
  let k = 0;
  while ((m = PDF_STREAM_KW_RE.exec(text)) !== null) {
    const at = m.index + (m[0].startsWith('stream') ? 0 : 1);
    PDF_STREAM_KW_RE.lastIndex = at + 1;
    if (seen.has(at)) continue;
    while (k < skipped.length && skipped[k][1] <= at) k++;
    if (k < skipped.length && skipped[k][0] <= at && at < skipped[k][1]) continue;
    fail('a PDF stream could not be matched to its dictionary');
    return null;
  }
  return out;
}

// Dictionaries packed into compressed object streams are only visible after
// inflating, so each object stream (a stream whose dictionary carries /ObjStm
// or the /First offset only object streams have) is inflated and searched too.
async function inspectPdf(bytes, add, fail) {
  const text = latin1(bytes);
  pdfNameCodes(text, add);

  const streams = pdfStreams(text, fail);
  if (!streams) return;
  let total = 0;
  for (const st of streams) {
    const names = new Set();
    PDF_NAME_RE.lastIndex = 0;
    let n;
    while ((n = PDF_NAME_RE.exec(st.dict)) !== null) names.add(decodePdfName(n[1]).toLowerCase());
    if (!names.has('objstm') && !names.has('first')) continue;

    let data = bytes.subarray(st.start, st.end);
    const filters = [...names].filter((x) => /decode$/.test(x));
    // A filter given by reference (/Filter 9 0 R) names no decoder here, so it is
    // not read as plain bytes.
    if (filters.length > 1 || (filters.length === 1 && filters[0] !== 'flatedecode') || names.has('decodeparms')
        || (names.has('filter') && filters.length === 0)) {
      fail('a PDF object stream uses an encoding the scan cannot read');
      continue;
    }
    if (filters.length === 1) {
      try {
        data = await inflate(data, 'deflate', OBJSTM_LIMIT_BYTES - total);
      } catch (err) {
        fail(err instanceof InspectError && /larger/.test(err.message)
          ? 'the PDF object streams are larger than the scan allows'
          : 'a PDF object stream could not be read (the PDF may be encrypted)');
        continue;
      }
    }
    total += data.length;
    pdfNameCodes(latin1(data), add);
  }
}

// 3. Zip based Office files (OOXML) -----------------------------------------------

const ZIP_LOCAL_SIG = [0x50, 0x4b, 0x03, 0x04];

function findEocd(bytes) {
  const min = Math.max(0, bytes.length - 22 - 0xffff);
  for (let i = bytes.length - 22; i >= min; i--) {
    if (bytes[i] === 0x50 && bytes[i + 1] === 0x4b && bytes[i + 2] === 0x05 && bytes[i + 3] === 0x06) return i;
  }
  return -1;
}

function readCentralDirectory(bytes) {
  const eocd = findEocd(bytes);
  if (eocd === -1) throw new InspectError('the archive has no central directory');
  const count = u16le(bytes, eocd + 10);
  const size = u32le(bytes, eocd + 12);
  const offset = u32le(bytes, eocd + 16);
  if (count === 0xffff || size === 0xffffffff || offset === 0xffffffff) {
    throw new InspectError('the archive uses a zip64 layout the scan cannot read');
  }
  if (count > ZIP_ENTRY_LIMIT) throw new InspectError('the archive has more parts than the scan allows');
  if (offset + size > eocd) throw new InspectError('the archive directory is damaged');
  const dec = new TextDecoder('utf-8');
  const entries = [];
  let p = offset;
  for (let k = 0; k < count; k++) {
    if (p + 46 > bytes.length || u32le(bytes, p) !== 0x02014b50) throw new InspectError('the archive directory is damaged');
    const flags = u16le(bytes, p + 8);
    const method = u16le(bytes, p + 10);
    const csize = u32le(bytes, p + 20);
    const nameLen = u16le(bytes, p + 28);
    const extraLen = u16le(bytes, p + 30);
    const commentLen = u16le(bytes, p + 32);
    const local = u32le(bytes, p + 42);
    if (p + 46 + nameLen > bytes.length) throw new InspectError('the archive directory is damaged');
    const name = dec.decode(bytes.subarray(p + 46, p + 46 + nameLen));
    entries.push({ name, flags, method, csize, local });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

async function readZipEntry(bytes, e) {
  if (e.flags & 0x1) throw new InspectError('the archive is encrypted');
  const h = e.local;
  if (h + 30 > bytes.length || u32le(bytes, h) !== 0x04034b50) throw new InspectError('an archive part is damaged');
  const start = h + 30 + u16le(bytes, h + 26) + u16le(bytes, h + 28);
  const end = start + e.csize;
  if (end > bytes.length) throw new InspectError('an archive part is damaged');
  const data = bytes.subarray(start, end);
  if (e.method === 0) {
    if (data.length > RELS_LIMIT_BYTES) throw new InspectError('an archive part is larger than the scan allows');
    return data;
  }
  if (e.method === 8) return inflate(data, 'deflate-raw', RELS_LIMIT_BYTES);
  throw new InspectError('an archive part uses a compression method the scan cannot read');
}

// Relationships that fetch content when the document opens (remote templates,
// frames, images, OLE links) are flagged. Plain web and email hyperlinks, which
// only open when someone clicks them, are not; a hyperlink to a file share or a
// local file is.
function externalRelationship(xml) {
  const relRe = /<(?:\w+:)?Relationship\b([^>]*)>/g;
  let m;
  while ((m = relRe.exec(xml)) !== null) {
    const attrs = m[1];
    const mode = /\bTargetMode\s*=\s*["']([^"']*)["']/i.exec(attrs);
    if (!mode || mode[1].toLowerCase() !== 'external') continue;
    const type = (/\bType\s*=\s*["']([^"']*)["']/i.exec(attrs) || [])[1] || '';
    const target = ((/\bTarget\s*=\s*["']([^"']*)["']/i.exec(attrs) || [])[1] || '').trim().toLowerCase();
    const hyperlink = /\/hyperlink$/i.test(type);
    const safeTarget = /^(https?:|mailto:)/.test(target);
    if (!hyperlink || !safeTarget) return true;
  }
  return false;
}

async function inspectOoxml(bytes, spec, add, fail) {
  let entries;
  try {
    entries = readCentralDirectory(bytes);
  } catch (err) {
    fail(err instanceof InspectError ? err.message : 'the archive could not be read');
    return;
  }
  const names = entries.map((e) => e.name.replace(/\\/g, '/'));
  if (!names.includes('[Content_Types].xml') || !names.some((n) => n.startsWith(spec.part))) {
    add('type_mismatch');
  }
  for (const n of names) {
    const lower = n.toLowerCase();
    const base = lower.split('/').pop();
    if (base === 'vbaproject.bin' || base === 'vbadata.xml') add('office_macros');
    if (lower.split('/').some((s) => s.startsWith('activex'))) add('office_activex');
    if (base.startsWith('oleobject')) add('office_embedded_object');
  }
  for (let k = 0; k < entries.length; k++) {
    if (!/\.rels$/i.test(names[k])) continue;
    let data;
    try {
      data = await readZipEntry(bytes, entries[k]);
    } catch (err) {
      fail(err instanceof InspectError ? err.message : 'an archive part could not be read');
      continue;
    }
    if (externalRelationship(new TextDecoder('utf-8').decode(data))) add('office_external_link');
  }
}

// 4. Legacy Office files (OLE compound documents) -----------------------------------

const OLE_SIG = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
// Stream and storage names are UTF 16 in the directory; the trailing NUL makes
// 'VBA' and 'Macros' match a whole name, not part of one.
const OLE_MACRO_MARKERS = [utf16le('_VBA_PROJECT'), utf16le('Macros\0'), utf16le('VBA\0'), ascii('Attribute VB_')];
const OLE_OBJECT_MARKERS = [utf16le('\u0001Ole10Native'), utf16le('Equation Native')];

function inspectOle(bytes, add) {
  if (OLE_MACRO_MARKERS.some((m) => indexOfBytes(bytes, m) !== -1)) add('office_macros');
  if (OLE_OBJECT_MARKERS.some((m) => indexOfBytes(bytes, m) !== -1)) add('office_embedded_object');
}

// 5. CSV ---------------------------------------------------------------------------

const NUMBER_RE = /^[\d\s.,]*\d[\d\s.,]*%?$/;

// A cell is formula like when a spreadsheet would read it as one: '=' with
// anything after it; '+', '-' or '@' followed by a function call, a cell
// reference, an operator chain or a DDE pipe, but not a plain number such as
// -12,5 or a telephone number such as +27 60 070 2723.
function formulaLike(cell) {
  const c = cell.replace(/^[\t\r]+/, '');
  if (!c) return false;
  const lead = c[0];
  const rest = c.slice(1).trim();
  if (lead === '=') return rest.length > 0;
  if (lead !== '+' && lead !== '-' && lead !== '@') return false;
  if (!rest || NUMBER_RE.test(rest)) return false;
  return /[A-Za-z_][A-Za-z0-9_.]*\s*\(/.test(rest)
    || /[|!]/.test(rest)
    || /^\$?[A-Za-z]{1,3}\$?\d+/.test(rest)
    || /^[=+\-@]/.test(rest)
    || /[*/^&<>=]/.test(rest);
}

function csvCells(text) {
  const cells = [];
  let cell = '';
  let quoted = false;
  let atStart = true;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { cell += '"'; i++; } else quoted = false;
      } else cell += ch;
      continue;
    }
    if (ch === '"' && atStart) { quoted = true; atStart = false; continue; }
    if (ch === ',' || ch === ';' || ch === '\n' || (ch === '\r' && text[i + 1] === '\n')) {
      cells.push(cell);
      cell = '';
      atStart = true;
      if (ch === '\r') i++;
      continue;
    }
    cell += ch;
    atStart = false;
  }
  cells.push(cell);
  return cells;
}

function inspectCsv(bytes, add) {
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch (_) {
    add('type_mismatch');
    return;
  }
  // Text only: no NUL and no control characters other than tab, line feed,
  // form feed and carriage return.
  if (/[\x00-\x08\x0b\x0e-\x1f\x7f]/.test(text)) {
    add('type_mismatch');
    return;
  }
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  if (csvCells(text).some(formulaLike)) add('csv_formula');
}

// 6. Images ----------------------------------------------------------------------

const JPEG_SIG = [0xff, 0xd8, 0xff];
const PNG_SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const EXIF_SIG = ascii('Exif\0\0');
const XMP_GPS_RE = /exif:GPS(Latitude|Longitude)|GPSLatitude|GPSLongitude/;

// Reads a TIFF structure (the body of an EXIF block) and reports whether its
// GPS directory holds a latitude or longitude.
function tiffHasGps(b, start, end) {
  if (end - start < 8) throw new InspectError('the image details are damaged');
  let le;
  if (b[start] === 0x49 && b[start + 1] === 0x49) le = true;
  else if (b[start] === 0x4d && b[start + 1] === 0x4d) le = false;
  else throw new InspectError('the image details are damaged');
  const r16 = (i) => (le ? u16le(b, i) : u16be(b, i));
  const r32 = (i) => (le ? u32le(b, i) : u32be(b, i));
  if (r16(start + 2) !== 42) throw new InspectError('the image details are damaged');
  const dir = (off) => {
    const at = start + off;
    if (off < 8 || at + 2 > end) throw new InspectError('the image details are damaged');
    const n = r16(at);
    if (at + 2 + n * 12 > end) throw new InspectError('the image details are damaged');
    const tags = [];
    for (let k = 0; k < n; k++) tags.push({ tag: r16(at + 2 + k * 12), value: r32(at + 2 + k * 12 + 8) });
    return tags;
  };
  const gps = dir(r32(start + 4)).find((t) => t.tag === 0x8825);
  if (!gps) return false;
  return dir(gps.value).some((t) => t.tag >= 1 && t.tag <= 4);
}

function inspectJpeg(bytes, add, fail) {
  let meta = 0;
  let i = 2;
  for (;;) {
    if (i >= bytes.length) { fail('the image ends before its picture data'); return; }
    if (bytes[i] !== 0xff) { fail('the image structure is damaged'); return; }
    while (bytes[i] === 0xff) i++;
    const marker = bytes[i++];
    if (marker === 0xd9 || marker === 0xda) break; // end of image, or start of the picture data
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (i + 2 > bytes.length) { fail('the image structure is damaged'); return; }
    const len = u16be(bytes, i);
    if (len < 2 || i + len > bytes.length) { fail('the image structure is damaged'); return; }
    const s = i + 2;
    const e = i + len;
    if ((marker >= 0xe0 && marker <= 0xef) || marker === 0xfe) {
      meta += len;
      if (marker === 0xe1 && startsWith(bytes, EXIF_SIG, s)) {
        try {
          if (tiffHasGps(bytes, s + EXIF_SIG.length, e)) add('location_metadata');
        } catch (err) {
          fail(err instanceof InspectError ? err.message : 'the image details could not be read');
        }
      } else if (marker === 0xe1 && XMP_GPS_RE.test(latin1(bytes, s, e))) {
        add('location_metadata');
      }
    }
    i = e;
  }
  if (meta > METADATA_LIMIT_BYTES) add('oversized_metadata');
}

async function inspectPng(bytes, add, fail) {
  let meta = 0;
  let i = 8;
  let first = true;
  for (;;) {
    if (i + 12 > bytes.length) { fail('the image ends before its end marker'); return; }
    const len = u32be(bytes, i);
    const type = latin1(bytes, i + 4, i + 8);
    const s = i + 8;
    const e = s + len;
    if (e + 4 > bytes.length) { fail('the image structure is damaged'); return; }
    if (first && type !== 'IHDR') { add('type_mismatch'); return; }
    first = false;
    if (type === 'IEND') break;
    if (type === 'eXIf' || type === 'tEXt' || type === 'zTXt' || type === 'iTXt') {
      meta += len;
      try {
        if (type === 'eXIf') {
          if (tiffHasGps(bytes, s, e)) add('location_metadata');
        } else {
          const text = await pngText(type, bytes.subarray(s, e));
          if (XMP_GPS_RE.test(text)) add('location_metadata');
        }
      } catch (err) {
        fail(err instanceof InspectError ? err.message : 'the image details could not be read');
      }
    }
    i = e + 4;
  }
  if (meta > METADATA_LIMIT_BYTES) add('oversized_metadata');
}

// The text of a PNG text chunk, inflated when it is stored compressed.
async function pngText(type, d) {
  const kwEnd = d.indexOf(0);
  if (kwEnd === -1) throw new InspectError('the image details are damaged');
  if (type === 'tEXt') return latin1(d, kwEnd + 1);
  if (type === 'zTXt') {
    if (d[kwEnd + 1] !== 0) throw new InspectError('the image details use an unknown compression');
    return latin1(await inflate(d.subarray(kwEnd + 2), 'deflate', TEXT_CHUNK_LIMIT_BYTES));
  }
  // iTXt: keyword NUL, flag, method, language NUL, translated keyword NUL, text
  const compressed = d[kwEnd + 1] === 1;
  const langEnd = d.indexOf(0, kwEnd + 3);
  const transEnd = langEnd === -1 ? -1 : d.indexOf(0, langEnd + 1);
  if (transEnd === -1) throw new InspectError('the image details are damaged');
  const body = d.subarray(transEnd + 1);
  if (!compressed) return latin1(body);
  if (d[kwEnd + 2] !== 0) throw new InspectError('the image details use an unknown compression');
  return latin1(await inflate(body, 'deflate', TEXT_CHUNK_LIMIT_BYTES));
}

// 7. inspectBytes ----------------------------------------------------------------

// { bytes, mimeType, fileName } → { verdict: 'clean' | 'harmful' | 'error',
// findings: [{ code, message }] }. Never throws: a failure of the check itself
// is verdict 'error' with a 'could_not_inspect' finding.
export async function inspectBytes(input) {
  const o = input || {};
  const findings = [];
  const seen = new Set();
  const add = (code) => {
    if (seen.has(code)) return;
    seen.add(code);
    findings.push({ code, message: MESSAGES[code] });
  };
  let why = null;
  const fail = (reason) => { if (!why) why = reason; };

  try {
    const bytes = toUint8(o.bytes);
    const mime = typeof o.mimeType === 'string' ? o.mimeType.trim().toLowerCase() : '';
    const spec = KINDS[mime];
    if (!spec) {
      add('type_not_allowed');
    } else {
      const ext = fileExtension(o.fileName);
      if (ext && !spec.ext.includes(ext)) add('name_mismatch');
      if (spec.kind === 'pdf') {
        if (!startsWith(bytes, PDF_SIG)) add('type_mismatch');
        else await inspectPdf(bytes, add, fail);
      } else if (spec.kind === 'png') {
        if (!startsWith(bytes, PNG_SIG)) add('type_mismatch');
        else await inspectPng(bytes, add, fail);
      } else if (spec.kind === 'jpeg') {
        if (!startsWith(bytes, JPEG_SIG)) add('type_mismatch');
        else inspectJpeg(bytes, add, fail);
      } else if (spec.kind === 'ooxml') {
        if (!startsWith(bytes, ZIP_LOCAL_SIG)) add('type_mismatch');
        else await inspectOoxml(bytes, spec, add, fail);
      } else if (spec.kind === 'ole') {
        if (!startsWith(bytes, OLE_SIG)) add('type_mismatch');
        else inspectOle(bytes, add);
      } else if (spec.kind === 'csv') {
        inspectCsv(bytes, add);
      }
    }
  } catch (err) {
    fail(err instanceof InspectError ? err.message : 'the check could not finish');
  }

  if (findings.length) return { verdict: 'harmful', findings };
  if (why) return { verdict: 'error', findings: [{ code: 'could_not_inspect', message: `The file could not be checked: ${why}.` }] };
  return { verdict: 'clean', findings: [] };
}

// 8. The antivirus engine ----------------------------------------------------------

// HTTP engine (for example a ClamAV REST service hosted by Care Net or MCO):
//   POST <HSF_AV_ENDPOINT>, Authorization: Bearer <HSF_AV_TOKEN>,
//   Content-Type: application/octet-stream, X-File-Name: <safe name>, raw bytes
//   reply { clean: boolean, signature: string | null, engine: string }
// scan() never throws: it answers { result: 'clean' | 'infected' | 'error',
// engine, signature, error }. The token never appears in an error.
export function createAvEngine(options) {
  const o = options || {};
  const endpoint = typeof o.endpoint === 'string' ? o.endpoint.trim() : '';
  const token = typeof o.token === 'string' ? o.token.trim() : '';
  const answer = (result, f) => Object.assign({ result, engine: null, signature: null, error: null }, f || {});

  if (!endpoint || !token) {
    if (!endpoint && o.allowFixture === true) {
      // Tests only: HSF_SCAN_ALLOW_FIXTURE=1. Never set in production.
      return Object.freeze({
        kind: 'fixture',
        configured: true,
        async scan() { return answer('clean', { engine: 'fixture' }); },
      });
    }
    return Object.freeze({
      kind: 'none',
      configured: false,
      async scan() { return answer('error', { error: AV_NOT_CONFIGURED }); },
    });
  }

  let url;
  try {
    url = new URL(endpoint);
  } catch (_) {
    url = null;
  }
  // Special personal information never travels in the clear.
  if (!url || url.protocol !== 'https:') {
    return Object.freeze({
      kind: 'none',
      configured: false,
      async scan() { return answer('error', { error: `${AV_NOT_CONFIGURED}: HSF_AV_ENDPOINT must be an https address.` }); },
    });
  }

  const doFetch = typeof o.fetch === 'function' ? o.fetch : (u, init) => globalThis.fetch(u, init);
  const timeoutMs = Number.isFinite(o.timeoutMs) && o.timeoutMs > 0 ? o.timeoutMs : DEFAULT_AV_TIMEOUT_MS;
  const clean = (s) => String(s).split(token).join('[redacted]').slice(0, 200);
  const printable = (s, n) => String(s).replace(/[^\x20-\x7e]/g, '').trim().slice(0, n);

  return Object.freeze({
    kind: 'http',
    configured: true,
    async scan(doc) {
      const d = doc || {};
      let bytes;
      try {
        bytes = toUint8(d.bytes);
      } catch (_) {
        return answer('error', { error: 'No file was given to the antivirus engine.' });
      }
      const name = typeof d.fileName === 'string' ? d.fileName.replace(/[^A-Za-z0-9._]/g, '_').slice(0, 120) : '';
      const signal = typeof AbortSignal !== 'undefined' && typeof AbortSignal.timeout === 'function'
        ? AbortSignal.timeout(timeoutMs) : undefined;
      let res;
      try {
        res = await doFetch(url.href, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/octet-stream',
            Accept: 'application/json',
            'X-File-Name': name || 'upload',
          },
          body: bytes,
          signal,
        });
      } catch (err) {
        return answer('error', { error: `The antivirus engine could not be reached. ${clean(messageOf(err))}`.trim() });
      }
      if (!res || !res.ok) {
        try { if (res) await res.arrayBuffer(); } catch (_) { /* drain only */ }
        return answer('error', { error: `The antivirus engine replied with HTTP ${res ? res.status : 'nothing'}.` });
      }
      let body;
      try {
        body = await res.json();
      } catch (_) {
        return answer('error', { error: 'The antivirus engine replied without a readable result.' });
      }
      if (!body || typeof body !== 'object' || typeof body.clean !== 'boolean') {
        return answer('error', { error: 'The antivirus engine reply did not say whether the file is clean.' });
      }
      const engine = typeof body.engine === 'string' && printable(body.engine, 60) ? printable(body.engine, 60) : 'antivirus';
      if (body.clean) return answer('clean', { engine });
      const signature = typeof body.signature === 'string' && printable(body.signature, 120) ? printable(body.signature, 120) : null;
      return answer('infected', { engine, signature });
    },
  });
}

// 9. One upload --------------------------------------------------------------------

// deps: {
//   rpc:        async (fn, args) => parsed JSON reply; throws on refusal
//   download:   async (path) => Uint8Array | ArrayBuffer; throws when unreadable
//   av:         an engine from createAvEngine
//   checkPath:  (row) => { ok, path, reason } (transfer-core checkStagingPath)
//   recordFn?:  the database function name (default 'hsf_scan_record')
//   sha256Hex?, log?
// }
// Returns { uploadId, result, action, findings: [codes], error }.
export async function scanUpload(row, deps) {
  const d = deps || {};
  const hash = typeof d.sha256Hex === 'function' ? d.sha256Hex : defaultSha256Hex;
  const log = typeof d.log === 'function' ? d.log : () => {};
  const recordFn = typeof d.recordFn === 'string' ? d.recordFn : 'hsf_scan_record';
  const id = row && typeof row.id === 'string' ? row.id : null;
  const report = { uploadId: id, result: null, action: null, findings: [], error: null };

  if (!id || !UUID_RE.test(id)) {
    report.action = 'skipped';
    report.error = 'The scan claim returned a row without a valid upload identifier.';
    return report;
  }
  if (row.status !== 'uploaded' || (row.scan_status !== undefined && row.scan_status !== 'pending' && row.scan_status !== 'error')) {
    report.action = 'skipped';
    report.error = 'The upload is not waiting for a security scan.';
    return report;
  }
  const blocked = row.transfer_blocked_reason;
  if (typeof blocked === 'string' ? blocked.trim() !== '' : blocked !== undefined && blocked !== null && blocked !== false) {
    report.action = 'skipped';
    report.error = 'The upload is blocked, so it is not scanned now.';
    return report;
  }

  const record = async (result, engine, findings, note) => {
    report.result = result;
    report.findings = findings.map((f) => f.code);
    if (note) report.error = note;
    try {
      await d.rpc(recordFn, { p_upload_id: id, p_result: result, p_engine: engine, p_findings: findings });
      report.action = result;
      if (result !== 'clean') log(`hsf-mco-transfer scan ${id}: ${result}: ${report.findings.join(', ')}${note ? ` (${note})` : ''}`);
    } catch (err) {
      report.action = 'record_failed';
      report.error = [note, `The scan result could not be recorded: ${messageOf(err)}`].filter(Boolean).join(' ');
      log(`hsf-mco-transfer scan ${id}: ${report.error}`);
    }
    return report;
  };
  const cannot = (why) => record('error', INSPECT_ENGINE, [{ code: 'could_not_inspect', message: `The file could not be checked: ${why}.` }], null);

  const p = typeof d.checkPath === 'function' ? d.checkPath(row) : { ok: false, reason: 'no path check was given' };
  if (!p.ok) return cannot(String(p.reason || 'the staging path is not usable').replace(/\.$/, '').toLowerCase());

  let bytes;
  try {
    bytes = toUint8(await d.download(p.path));
  } catch (err) {
    return record('error', INSPECT_ENGINE, [{ code: 'could_not_inspect', message: 'The file could not be checked: it could not be read from staging.' }], messageOf(err));
  }

  // The bytes scanned must be the bytes fingerprinted: the server fingerprint
  // when the database holds one, and always the browser fingerprint.
  let actual;
  try {
    actual = lowerHex(await hash(bytes));
  } catch (_) {
    actual = '';
  }
  const expected = [lowerHex(row.sha256_server), lowerHex(row.sha256_client)].filter(Boolean);
  if (!isSha256Hex(actual) || !expected.length || expected.some((h) => h !== actual)) {
    return record('error', INSPECT_ENGINE, [{ code: 'fingerprint_mismatch', message: MESSAGES.fingerprint_mismatch }], null);
  }

  const inspected = await inspectBytes({ bytes, mimeType: row.mime_type, fileName: row.safe_name });
  if (inspected.verdict === 'harmful') return record('harmful', INSPECT_ENGINE, inspected.findings, null);
  if (inspected.verdict !== 'clean') return record('error', INSPECT_ENGINE, inspected.findings, null);

  const av = d.av && typeof d.av.scan === 'function' ? d.av : createAvEngine({});
  let verdict;
  try {
    verdict = await av.scan({ bytes, fileName: row.safe_name, mimeType: row.mime_type });
  } catch (err) {
    verdict = { result: 'error', error: `The antivirus engine failed. ${messageOf(err)}` };
  }
  bytes = null;
  const engine = verdict && verdict.engine ? `${INSPECT_ENGINE} + ${verdict.engine}` : INSPECT_ENGINE;
  if (verdict && verdict.result === 'clean') return record('clean', engine, [], null);
  if (verdict && verdict.result === 'infected') {
    const message = verdict.signature ? `${MESSAGES.malware.slice(0, -1)} (${verdict.signature}).` : MESSAGES.malware;
    return record('infected', engine, [{ code: 'malware', message }], null);
  }
  const why = verdict && typeof verdict.error === 'string' ? verdict.error : 'The antivirus engine gave no result.';
  const code = why.startsWith(AV_NOT_CONFIGURED) ? 'av_not_configured' : 'av_error';
  return record('error', engine, [{ code, message: code === 'av_not_configured' ? AV_NOT_CONFIGURED : 'The antivirus scan could not finish.' }], why);
}
