'use strict';
// Keeping the File apart from the Plan (hsf/BUILD-CONTRACT.md section 15).
//
// The Health and Safety File (and the Risk Assessment application behind it)
// is a separate product from the Medical Surveillance Plan. No File page may
// link, navigate, submit or redirect to a Plan page, and the File's sign off
// pricing for Care Net clients comes only from vercel/hsf/pricing.js.
//
//   File pages    vercel/health-and-safety-file.html, hsf-builder.html,
//                 hsf-sample.html, hsf-staff.html, legislation.html
//   File scripts  vercel/hsf/*.js, vercel/hsf/samples/*.js (and the page
//                 images in vercel/hsf/samples/pages/*.js, which hsf-sample
//                 loads), vercel/js/cnc-hsf-links.js, and every other script
//                 a File page loads, read from its own <script src> tags,
//                 module imports and loadScript calls: the shared
//                 js/cnc-header.js, cnc-config.js, cnc-tracking.js,
//                 cnc-auth.js, cnc-secnav.js, cnc-design-assets.js and
//                 cnc-icon-fit.js run on the File pages too
//   Plan pages    /, /index.html, /pilot, /method, /shop, /sample,
//                 /medical-surveillance-plans, /industry, /assess, /account,
//                 with or without .html, a query or a hash, after the
//                 redirects and rewrites in vercel/vercel.json. /hsf-sample is
//                 not /sample. /portal.html joins both products and is allowed.
//
// This is the static half: markup, inline handlers and every string in the
// scripts, with no browser and no network. The rendered half is the Chromium
// crawl in test/browser/file-links.mjs, which imports the classifier exported
// here; "node --test" runs it as a test that can fail whenever Chromium is
// found (node test/browser/file-links.mjs runs its full plan on its own).
//
// Run:  node --test                                   (every node test)
//       node --test test/api/file-separation.test.js  (just this file)

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { compileSource, fillDestination } = require('../../server/serve.js');

const ROOT = path.join(__dirname, '..', '..');
const VERCEL = path.join(ROOT, 'vercel');

/* Bee-Inspect P2 (contract 16.1): the Bee-Inspect pages sit on the File site and
   follow the same rules. */
const FILE_PAGES = ['health-and-safety-file.html', 'hsf-builder.html', 'hsf-sample.html', 'hsf-staff.html', 'legislation.html',
  'bee-inspect.html', 'bee-inspect/sample-report.html', 'get-app.html', 'claim.html'];

/* Every Plan page, as its clean path (contract 15.1). */
const PLAN_PATHS = ['/', '/pilot', '/method', '/shop', '/sample', '/medical-surveillance-plans', '/industry', '/assess', '/account'];
const PLAN_SET = new Set(PLAN_PATHS);

/* The placeholder origin static links are resolved against. The crawl passes
   its own local origin instead. */
const SITE_ORIGIN = 'https://file-pages.invalid';

/* The Care Net main site also carries the Plan landing
   (medical-surveillance-plans.html gives its canonical address there). Its
   home page is the corporate site, not the Plan, so only the other Plan paths
   count on these hosts. */
const MAIN_HOSTS = new Set(['www.carenetconsultants.co.za', 'carenetconsultants.co.za']);

/* ------------------------------------------------------------ vercel.json routes */
function loadRoutes() {
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(path.join(VERCEL, 'vercel.json'), 'utf8')); } catch (_) { cfg = {}; }
  const compile = (list) => (Array.isArray(list) ? list : [])
    .filter((r) => r && typeof r.source === 'string' && !r.has && !r.missing)
    .map((r) => Object.assign({ destination: r.destination }, compileSource(r.source)));
  return { redirects: compile(cfg.redirects), rewrites: compile(cfg.rewrites) };
}
const ROUTES = loadRoutes();

function routeOnce(pathname, list) {
  for (const r of list) {
    const m = r.re.exec(pathname);
    if (m) return fillDestination(r.destination, m, r.names);
  }
  return null;
}

/* The clean path Vercel serves: lower case, no trailing slash, no .html,
   /index is the home page. */
function cleanPath(p) {
  let s = String(p || '/');
  try { s = decodeURIComponent(s); } catch (_) { /* keep it as it is */ }
  s = s.toLowerCase().replace(/\/{2,}/g, '/');
  if (!s.startsWith('/')) s = '/' + s;
  if (s.length > 1) s = s.replace(/\/+$/, '');
  s = s.replace(/\.html?$/, '');
  if (s === '/index' || s === '') s = '/';
  return s;
}

/* planTarget(raw, base, siteOrigins) -> null, or {url, path, via} when the
   address lands on a Plan page. raw may be relative; it resolves against base
   as a browser would. siteOrigins lists the origins that are this site (the
   placeholder origin by default). */
function planTarget(raw, base, siteOrigins) {
  const origins = siteOrigins || [SITE_ORIGIN];
  let u;
  try { u = new URL(String(raw).trim(), base || SITE_ORIGIN + '/'); } catch (_) { return null; }
  const via = [];
  for (let hop = 0; hop < 6; hop++) {
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    const onSite = origins.includes(u.origin);
    const onMain = MAIN_HOSTS.has(u.hostname);
    if (!onSite && !onMain) return null;
    if (onSite) {
      const dest = routeOnce(u.pathname, ROUTES.redirects);
      if (dest) {
        via.push(u.pathname + ' redirects to ' + dest);
        try { u = new URL(dest, u); } catch (_) { return null; }
        continue;
      }
      const rw = routeOnce(u.pathname, ROUTES.rewrites);
      if (rw && rw.startsWith('/')) {
        via.push(u.pathname + ' is served as ' + rw);
        const p = cleanPath(new URL(rw, u).pathname);
        return PLAN_SET.has(p) ? { url: u.href, path: p, via } : null;
      }
    }
    const p = cleanPath(u.pathname);
    if (onSite && PLAN_SET.has(p)) return { url: u.href, path: p, via };
    if (onMain && p !== '/' && PLAN_SET.has(p)) return { url: u.href, path: p, via };
    return null;
  }
  return null;
}

/* ------------------------------------------------------------ a small JavaScript lexer
   Finds comments and string literals (template literal parts included), and
   tells a regular expression literal from a division, so that '//' inside a
   string or a regular expression is never taken for a comment. */
const KEYWORDS_BEFORE_EXPR = new Set(['return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void', 'throw', 'case', 'do', 'else', 'yield', 'await']);
const ESC = { n: '\n', t: '\t', r: '\r', b: '\b', f: '\f', v: '\v', 0: '\0' };

function readEscape(src, j) {
  const e = src[j + 1];
  if (e === undefined) return { text: '', next: j + 1 };
  if (e === '\r' && src[j + 2] === '\n') return { text: '', next: j + 3 };
  if (e === '\n' || e === '\r' || e === ' ' || e === ' ') return { text: '', next: j + 2 };
  if (e === 'x') {
    const h = src.slice(j + 2, j + 4);
    return /^[0-9a-fA-F]{2}$/.test(h) ? { text: String.fromCharCode(parseInt(h, 16)), next: j + 4 } : { text: 'x', next: j + 2 };
  }
  if (e === 'u') {
    if (src[j + 2] === '{') {
      const end = src.indexOf('}', j + 3);
      const h = end === -1 ? '' : src.slice(j + 3, end);
      if (/^[0-9a-fA-F]{1,6}$/.test(h)) return { text: String.fromCodePoint(parseInt(h, 16)), next: end + 1 };
      return { text: 'u', next: j + 2 };
    }
    const h = src.slice(j + 2, j + 6);
    return /^[0-9a-fA-F]{4}$/.test(h) ? { text: String.fromCharCode(parseInt(h, 16)), next: j + 6 } : { text: 'u', next: j + 2 };
  }
  return { text: Object.prototype.hasOwnProperty.call(ESC, e) ? ESC[e] : e, next: j + 2 };
}

function lexJs(src) {
  const strings = [];
  const comments = [];
  const n = src.length;
  const stack = [];
  let depth = 0;
  let prev = '';
  let i = 0;
  const RUN = { "'": /[^'\\\n\r]+/y, '"': /[^"\\\n\r]+/y, '`': /[^`\\$]+/y };

  function readQuoted(start, q) {
    let j = start + 1;
    const parts = [];
    const run = RUN[q];
    while (j < n) {
      run.lastIndex = j;
      const m = run.exec(src);
      if (m) { parts.push(m[0]); j += m[0].length; continue; }
      const c = src[j];
      if (c === '\\') { const e = readEscape(src, j); parts.push(e.text); j = e.next; continue; }
      if (c === q) { j++; break; }
      break; /* an unterminated string ends at the line end */
    }
    strings.push({ value: parts.join(''), start, end: j, quote: q });
    return j;
  }
  function readTemplate(start, resumed) {
    let j = start + 1;
    const parts = [];
    const run = RUN['`'];
    while (j < n) {
      run.lastIndex = j;
      const m = run.exec(src);
      if (m) { parts.push(m[0]); j += m[0].length; continue; }
      const c = src[j];
      if (c === '\\') { const e = readEscape(src, j); parts.push(e.text); j = e.next; continue; }
      if (c === '`') {
        strings.push({ value: parts.join(''), start, end: j + 1, quote: '`', afterExpr: resumed, beforeExpr: false });
        return j + 1;
      }
      if (c === '$' && src[j + 1] === '{') {
        strings.push({ value: parts.join(''), start, end: j + 2, quote: '`', afterExpr: resumed, beforeExpr: true });
        stack.push(depth);
        return j + 2;
      }
      parts.push(c); j++;
    }
    strings.push({ value: parts.join(''), start, end: n, quote: '`', afterExpr: resumed, beforeExpr: false });
    return n;
  }
  function readRegex(start) {
    let j = start + 1;
    let inClass = false;
    while (j < n) {
      const c = src[j];
      if (c === '\\') { j += 2; continue; }
      if (c === '\n' || c === '\r') break;
      if (inClass) { if (c === ']') inClass = false; j++; continue; }
      if (c === '[') { inClass = true; j++; continue; }
      if (c === '/') { j++; break; }
      j++;
    }
    while (j < n && /[A-Za-z]/.test(src[j])) j++;
    return j;
  }
  const regexAllowed = () => prev === '' || prev === 'kw' || (prev.startsWith('p') && !/^p[)\]]$/.test(prev));

  while (i < n) {
    const c = src[i];
    if (c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === '\f' || c === '\v' || c === ' ' || c === '﻿' || c === ' ' || c === ' ') { i++; continue; }
    if (c === '/' && src[i + 1] === '/') {
      let e = i + 2;
      while (e < n && src[e] !== '\n' && src[e] !== '\r') e++;
      comments.push([i, e]); i = e; continue;
    }
    if (c === '/' && src[i + 1] === '*') {
      const e = src.indexOf('*/', i + 2);
      const end = e === -1 ? n : e + 2;
      comments.push([i, end]); i = end; continue;
    }
    if (c === '"' || c === "'") { i = readQuoted(i, c); prev = 's'; continue; }
    if (c === '`') { i = readTemplate(i, false); prev = 's'; continue; }
    if (c === '}' && stack.length && depth === stack[stack.length - 1]) { stack.pop(); i = readTemplate(i, true); prev = 's'; continue; }
    if (c === '{') { depth++; prev = 'p{'; i++; continue; }
    if (c === '}') { depth--; prev = 'p}'; i++; continue; }
    if (c === '/') {
      if (regexAllowed()) { i = readRegex(i); prev = 'r'; } else { prev = 'p/'; i++; }
      continue;
    }
    if (/[A-Za-z_$\\]/.test(c) || c > '\u007f') {
      let e = i + 1;
      while (e < n && (/[A-Za-z0-9_$\\]/.test(src[e]) || src[e] > '\u007f')) e++;
      const word = src.slice(i, e);
      prev = KEYWORDS_BEFORE_EXPR.has(word) ? 'kw' : 'id';
      i = e; continue;
    }
    if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(src[i + 1] || ''))) {
      let e = i + 1;
      while (e < n && /[0-9A-Za-z_.]/.test(src[e])) e++;
      prev = 'n'; i = e; continue;
    }
    prev = 'p' + c; i++;
  }
  return { strings, comments };
}

/* src with the given [start, end) ranges replaced by spaces (line breaks kept,
   so line numbers still match). */
function blank(src, ranges) {
  if (!ranges.length) return src;
  const out = [];
  let at = 0;
  for (const [s, e] of ranges.slice().sort((a, b) => a[0] - b[0])) {
    if (s < at) continue;
    out.push(src.slice(at, s), src.slice(s, e).replace(/[^\n\r]/g, ' '));
    at = e;
  }
  out.push(src.slice(at));
  return out.join('');
}

/* ------------------------------------------------------------ HTML */
const ENTITIES = { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>', nbsp: ' ', sol: '/', num: '#', quest: '?', period: '.', colon: ':', equals: '=' };
function decodeEntities(s) {
  return String(s).replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);?/gi, (all, e) => {
    if (e[0] === '#') {
      const cp = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      try { return String.fromCodePoint(cp); } catch (_) { return all; }
    }
    const v = ENTITIES[e.toLowerCase()];
    return v === undefined ? all : v;
  });
}

/* Splits a page into markup, script and style parts, each with its offset. */
function splitHtml(html) {
  const parts = [];
  const open = /<(script|style)\b([^>]*)>/gi;
  let at = 0;
  let m;
  while ((m = open.exec(html))) {
    if (m.index > at) parts.push({ kind: 'markup', start: at, text: html.slice(at, m.index) });
    parts.push({ kind: 'markup', start: m.index, text: m[0] });
    const bodyStart = m.index + m[0].length;
    const close = new RegExp('</' + m[1] + '\\s*>', 'ig');
    close.lastIndex = bodyStart;
    const c = close.exec(html);
    const bodyEnd = c ? c.index : html.length;
    const typeM = /\btype\s*=\s*["']?([^"'\s>]+)/i.exec(m[2]);
    const type = typeM ? typeM[1].toLowerCase() : '';
    const isJs = m[1].toLowerCase() === 'script' && (!type || /javascript|ecmascript|module|json/.test(type));
    parts.push({ kind: m[1].toLowerCase() === 'style' ? 'style' : (isJs ? 'script' : 'data'), start: bodyStart, text: html.slice(bodyStart, bodyEnd) });
    at = bodyEnd;
    open.lastIndex = bodyEnd;
  }
  if (at < html.length) parts.push({ kind: 'markup', start: at, text: html.slice(at) });
  return parts;
}

function htmlCommentRanges(text) {
  const out = [];
  const re = /<!--[\s\S]*?(?:-->|$)/g;
  let m;
  while ((m = re.exec(text))) { out.push([m.index, m.index + m[0].length]); if (!m[0].length) re.lastIndex++; }
  return out;
}

const TAG_RE = /<([a-zA-Z][\w:-]*)((?:\s+[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*\/?>/g;
const ATTR_RE = /([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
const URL_ATTRS = new Set(['href', 'action', 'formaction', 'xlink:href', 'data-href', 'data-url', 'data-link']);

function* tagsOf(markup) {
  TAG_RE.lastIndex = 0;
  let m;
  while ((m = TAG_RE.exec(markup))) {
    const attrs = [];
    ATTR_RE.lastIndex = 0;
    let a;
    const text = m[2] || '';
    while ((a = ATTR_RE.exec(text))) {
      const value = a[2] !== undefined ? a[2] : (a[3] !== undefined ? a[3] : a[4]);
      attrs.push({ name: a[1].toLowerCase(), value: value === undefined ? null : decodeEntities(value) });
    }
    yield { name: m[1].toLowerCase(), attrs, index: m.index, text: m[0] };
  }
}

/* ------------------------------------------------------------ finding Plan targets */
function lineAt(src, index) {
  let line = 1;
  for (let i = 0; i < index && i < src.length; i++) if (src.charCodeAt(i) === 10) line++;
  return line;
}

/* A value built in script from a fixed start and a variable end: only a start
   that already ends its path (a query, a hash, or .html) decides the page. */
function definitePrefix(prefix) {
  const p = String(prefix).trim();
  if (!p) return null;
  if (/[?#]/.test(p)) return p;
  if (/\.html?$/i.test(p)) return p;
  return null;
}

/* Attribute style URLs in a stretch of markup (a page, or HTML built as a
   string in script). An unterminated value at the end of a script string is
   a start whose end is variable. */
function markupUrls(text, base, where, found, fromScript) {
  for (const tag of tagsOf(text)) {
    for (const a of tag.attrs) {
      if (a.value === null) continue;
      let kind = null;
      if (URL_ATTRS.has(a.name)) kind = a.name;
      else if (a.name === 'src' && (tag.name === 'iframe' || tag.name === 'frame' || tag.name === 'embed')) kind = tag.name + ' src';
      else if (a.name === 'data' && tag.name === 'object') kind = 'object data';
      else if (a.name === 'content' && tag.name === 'meta' && tag.attrs.some((x) => x.name === 'http-equiv' && /refresh/i.test(x.value || ''))) {
        const r = /url\s*=\s*['"]?([^'";]+)/i.exec(a.value);
        if (r) check(r[1], 'meta refresh');
        continue;
      }
      if (kind) check(a.value, kind);
    }
    function check(value, kind) {
      const t = planTarget(value, base);
      if (t) found.push({ where: where(tag.index), kind: (fromScript ? 'markup in script, ' : '') + kind, raw: value, target: t });
    }
  }
  if (fromScript) {
    /* An attribute whose value runs to the end of this string: the rest is
       added in script. */
    const tail = /\b(href|action|formaction)\s*=\s*(["'])([^"']*)$/i.exec(text);
    if (tail) {
      const p = definitePrefix(decodeEntities(tail[3]));
      const t = p && planTarget(p, base);
      if (t) found.push({ where: where(tail.index), kind: 'markup in script, ' + tail[1].toLowerCase() + ' (start of a built address)', raw: tail[3], target: t });
    }
  }
}

const URL_CONTEXT = [
  /(?:\blocation|\.location|\.href|\.action|\.formAction)\s*=\s*$/,
  /\b(?:location\s*\.\s*(?:assign|replace)|window\s*\.\s*open|\bopen|navigation\s*\.\s*navigate|showModalDialog)\s*\(\s*$/,
  /\bsetAttribute\s*\(\s*(['"])(?:href|action|formaction)\1\s*,\s*$/i,
  /\b(?:pushState|replaceState)\s*\([^()]*,[^()]*,\s*$/,
  /\bnew\s+URL\s*\(\s*$/,
  /(?:^|[{,\s])["']?(?:href|url|link|action)["']?\s*:\s*$/i
];

/* Plan targets in a piece of JavaScript: every string that is an address to a
   Plan page, and HTML built as a string. code is the source with comments
   blanked, used to read what surrounds each string. */
function scriptUrls(src, base, whereAt, found) {
  const { strings, comments } = lexJs(src);
  const code = blank(src, comments);
  const nextSig = (i) => { let j = i; while (j < code.length && /\s/.test(code[j])) j++; return code[j] || ''; };
  const prevSig = (i) => { let j = i - 1; while (j >= 0 && /\s/.test(code[j])) j--; return code[j] || ''; };
  for (const s of strings) {
    const v = s.value;
    if (!v || v.length > 4000 || /^\s*data:/i.test(v)) continue;
    const where = () => whereAt(s.start);
    if (/(?:href|action|formaction|src|content)\s*=/i.test(v) && v.includes('<')) {
      markupUrls(v, base, () => whereAt(s.start), found, true);
    } else if (/\b(?:href|action|formaction)\s*=\s*["'][^"']*$/i.test(v)) {
      markupUrls(v, base, () => whereAt(s.start), found, true);
    }
    const trimmed = v.trim();
    if (!trimmed || /\s/.test(trimmed)) continue;
    const before = code.slice(Math.max(0, s.start - 120), s.start);
    const inContext = URL_CONTEXT.some((re) => re.test(before));
    const isStart = s.quote === '`' ? s.beforeExpr : nextSig(s.end) === '+';
    const isEnd = s.quote === '`' ? s.afterExpr : prevSig(s.start) === '+';
    let candidate = null;
    let kind = 'string address';
    const looksLikePath = /^\/(?!\/)/.test(trimmed);
    const looksAbsolute = /^(?:https?:)?\/\//i.test(trimmed);
    /* A lone "." or ".." is a decimal point or a separator unless it is
       assigned as an address (the context branch below). */
    const looksRelativePage = /^(?:\.{1,2}\/)*[\w.-]+\.html?(?:[?#]\S*)?$/i.test(trimmed) || /^\.{1,2}\//.test(trimmed);
    if (isEnd && !isStart) {
      /* The end of an address built in script ("base + '/shop'"): a whole
         Plan path other than the home page still names a Plan page. */
      if (looksLikePath && trimmed !== '/') { candidate = trimmed; kind = 'end of a built address'; }
      else continue;
    } else if (isStart) {
      const p = definitePrefix(trimmed);
      if (p && (looksLikePath || looksAbsolute || looksRelativePage || inContext)) { candidate = p; kind = 'start of a built address'; }
      else continue;
    } else if (looksAbsolute || looksRelativePage) {
      candidate = trimmed;
    } else if (looksLikePath) {
      if (trimmed === '/' && !inContext) continue; /* a lone slash is a separator unless it is assigned as an address */
      candidate = trimmed;
    } else if (inContext && /^[\w.~%-]+(?:[?#]\S*)?$/.test(trimmed) && !/^(?:javascript|mailto|tel|data|blob|about):/i.test(trimmed)) {
      candidate = trimmed;
    } else continue;
    if (inContext) kind += ' used as a link or navigation';
    const t = planTarget(candidate, base);
    if (t) found.push({ where: where(), kind, raw: v, target: t });
  }
  return { strings, comments, code };
}

function pageBase(html, page) {
  const fallback = SITE_ORIGIN + '/' + page;
  const m = /<base\b[^>]*\bhref\s*=\s*["']([^"']+)["']/i.exec(html);
  if (!m) return fallback;
  try { return new URL(decodeEntities(m[1]), fallback).href; } catch (_) { return fallback; }
}

/* Every Plan target a File page's own markup and inline script carries. */
function scanHtml(html, page) {
  const base = pageBase(html, page);
  const found = [];
  const whereAt = (i) => page + ':' + lineAt(html, i);
  for (const part of splitHtml(html)) {
    if (part.kind === 'markup') {
      const text = blank(part.text, htmlCommentRanges(part.text));
      markupUrls(text, base, (i) => whereAt(part.start + i), found, false);
      for (const tag of tagsOf(text)) {
        for (const a of tag.attrs) {
          if (!/^on[a-z]+$/.test(a.name) || !a.value) continue;
          scriptUrls(a.value, base, () => whereAt(part.start + tag.index), found);
        }
      }
    } else if (part.kind === 'script' || part.kind === 'data') {
      scriptUrls(part.text, base, (i) => whereAt(part.start + i), found);
    }
  }
  return found;
}

/* Every Plan target a File script carries. Scripts run inside a File page, so
   relative addresses resolve against one. */
function scanScript(src, name) {
  const found = [];
  scriptUrls(src, SITE_ORIGIN + '/health-and-safety-file.html', (i) => name + ':' + lineAt(src, i), found);
  return found;
}

/* ------------------------------------------------------------ visible text */
/* The page with its HTML, JavaScript and CSS comments blanked out. */
function withoutComments(html) {
  const out = [];
  for (const part of splitHtml(html)) {
    if (part.kind === 'markup') {
      let text = blank(part.text, htmlCommentRanges(part.text));
      /* Inline handlers are script too. */
      text = text.replace(/(\son[a-z]+\s*=\s*)("([^"]*)"|'([^']*)')/gi, (all, lead, q, dq, sq) => {
        const body = dq !== undefined ? dq : sq;
        return lead + q[0] + blank(body, lexJs(body).comments) + q[0];
      });
      out.push(text);
    } else if (part.kind === 'style') {
      out.push(part.text.replace(/\/\*[\s\S]*?(?:\*\/|$)/g, (c) => c.replace(/[^\n\r]/g, ' ')));
    } else if (part.kind === 'script' || part.kind === 'data') {
      out.push(blank(part.text, lexJs(part.text).comments));
    } else out.push(part.text);
  }
  return out.join('');
}
function scriptWithoutComments(src) { return blank(src, lexJs(src).comments); }

const FORGE_RE = /\b(?:MSP|HSF)(?:[\s_-]|&nbsp;|&#160;|&#xa0;)*FORGE\b/gi;
/* The other internal platform names (contract section 15 and the IP rules of
   12.7). Cursor is matched with a capital only, on word boundaries, so the CSS
   property (cursor: pointer) and style.cursor never count. */
const SHAREPOINT_RE = /\bshare(?:[\s_-]|&nbsp;|&#160;|&#xa0;)*point\b/gi;
const CURSOR_RE = /\bCursor\b|\bCURSOR\b/g;
function platformHits(text, file) {
  return hits(text, FORGE_RE, file).concat(hits(text, SHAREPOINT_RE, file), hits(text, CURSOR_RE, file));
}
const BUILD_MY_PLAN_RE = /build(?:[\s_-]|&nbsp;|&#160;)*my(?:[\s_-]|&nbsp;|&#160;)*plan/gi;
const PCT_25_RE = /\b25\s*(?:%|&#0*37;|&#x0*25;|&percnt;|per\s*cent\b|percent\b)/gi;

function hits(text, re, file) {
  const out = [];
  re.lastIndex = 0;
  let m;
  while ((m = re.exec(text))) out.push(file + ':' + lineAt(text, m.index) + ' "' + m[0] + '"');
  return out;
}

/* ------------------------------------------------------------ the files */
/* The site path (vercel/ relative, no query or hash) of an address a File page
   loads a script from, or null when it is not on this site. */
function localScript(raw, base) {
  let u;
  try { u = new URL(String(raw).trim(), base); } catch (_) { return null; }
  if (u.origin !== SITE_ORIGIN) return null;
  const p = decodeURIComponent(u.pathname).replace(/^\/+/, '');
  return p || null;
}
/* Imports in a module and the loadScript('...') calls of the File pages, when
   the address is written out. */
const IMPORT_RES = [
  /\bimport\s+(?:[\w$*{}\s,]+?\s+from\s*)?["']([^"']+)["']/g,
  /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g,
  /\bloadScript\s*\(\s*["']([^"']+)["']/g
];
function importsIn(code, base, into) {
  for (const re of IMPORT_RES) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(code))) { const p = localScript(m[1], base); if (p) into.add(p); }
  }
}
/* Every script on this site that a File page loads: its <script src> tags,
   the modules its inline scripts import and the scripts it loads by a written
   out address, and what those scripts import in turn. Shared scripts
   (js/cnc-header.js, js/cnc-config.js, js/cnc-auth.js and the rest) run on
   every File page, so a Plan link added there would reach every File page. */
function pageScripts(html, page) {
  const base = pageBase(html, page);
  const found = new Set();
  for (const part of splitHtml(html)) {
    if (part.kind === 'markup') {
      for (const tag of tagsOf(blank(part.text, htmlCommentRanges(part.text)))) {
        if (tag.name !== 'script') continue;
        const src = tag.attrs.find((a) => a.name === 'src');
        const p = src && src.value ? localScript(src.value, base) : null;
        if (p) found.add(p);
      }
    } else if (part.kind === 'script') {
      importsIn(blank(part.text, lexJs(part.text).comments), base, found);
    }
  }
  const queue = Array.from(found);
  while (queue.length) {
    const rel = queue.shift();
    let src = '';
    try { src = fs.readFileSync(path.join(VERCEL, rel), 'utf8'); } catch (_) { continue; }
    const more = new Set();
    importsIn(blank(src, lexJs(src).comments), SITE_ORIGIN + '/' + rel, more);
    for (const p of more) if (!found.has(p)) { found.add(p); queue.push(p); }
  }
  return Array.from(found).sort();
}
function fileScripts() {
  const set = new Set();
  const add = (dir, rel) => {
    let names = [];
    try { names = fs.readdirSync(path.join(VERCEL, dir)); } catch (_) { return; }
    names.filter((f) => f.endsWith('.js')).sort().forEach((f) => set.add(path.posix.join(rel, f)));
  };
  /* The File's own scripts, including the sample data hsf-sample.html loads
     by industry (an address built in script). */
  add('hsf', 'hsf');
  add(path.join('hsf', 'samples'), 'hsf/samples');
  add(path.join('hsf', 'samples', 'pages'), 'hsf/samples/pages');
  set.add('js/cnc-hsf-links.js');
  for (const page of FILE_PAGES) {
    let html = '';
    try { html = fs.readFileSync(path.join(VERCEL, page), 'utf8'); } catch (_) { continue; }
    pageScripts(html, page).forEach((s) => set.add(s));
  }
  return Array.from(set).sort();
}

/* Strings in the shared scripts that look like a Plan address but are not
   one. Each is pinned to its exact line, so any change to the line brings the
   check back. */
const NOT_ADDRESSES = [
  { file: 'js/cnc-secnav.js', line: "var here = (location.pathname.split('/').pop() || 'index.html');",
    why: 'the name of the page being shown, compared with each band link to mark the current one; never navigated to' },
  { file: 'js/cnc-secnav.js', line: "var target = href.split('#')[0].split('?')[0].split('/').pop() || 'index.html';",
    why: 'the file name a band link points at, compared with the page being shown; never navigated to' }
];
function lineText(src, where) {
  const n = Number(String(where).split(':').pop());
  return (src.split(/\r\n|\r|\n/)[n - 1] || '').trim();
}
function notAddress(rel, src, f) {
  return NOT_ADDRESSES.some((x) => x.file === rel && x.line === lineText(src, f.where));
}
/* The sample industries, from the sample files themselves. */
function sampleSlugs() {
  try {
    return fs.readdirSync(path.join(VERCEL, 'hsf', 'samples')).filter((f) => f.endsWith('.js')).map((f) => f.slice(0, -3)).sort();
  } catch (_) { return []; }
}
const read = (rel) => fs.readFileSync(path.join(VERCEL, rel), 'utf8');

function describe(list) {
  return list.map((f) => '  ' + f.where + '  ' + f.kind + ': ' + JSON.stringify(f.raw.length > 120 ? f.raw.slice(0, 117) + '...' : f.raw)
    + ' -> Plan page ' + f.target.path + (f.target.via.length ? ' (' + f.target.via.join('; ') + ')' : '')).join('\n');
}

module.exports = {
  FILE_PAGES, PLAN_PATHS, SITE_ORIGIN, MAIN_HOSTS, NOT_ADDRESSES,
  planTarget, cleanPath, lexJs, splitHtml, scanHtml, scanScript, withoutComments, scriptWithoutComments,
  fileScripts, pageScripts, sampleSlugs, describe, platformHits
};

/* ============================================================ the tests */
function registerTests() {
  const test = require('node:test');
  const assert = require('node:assert');

  test('the Plan page classifier knows the Plan pages and nothing else', () => {
    const page = SITE_ORIGIN + '/hsf-builder.html';
    const plan = ['/', '/index.html', '/index', '/pilot', '/pilot.html', '/method', '/shop', '/shop.html#law', '/shop/',
      '/sample', '/sample.html?industry=construction', '/medical-surveillance-plans', '/medical-surveillance-plans.html',
      '/industry', '/assess.html?token=x', '/account', '/account.html', 'shop.html', './', '../index.html', 'sample.html#top',
      '/build-your-plan', '/samples/CNC-MSP-SAMPLE-Construction.pdf', '/downloads/CNC-Legislation-Register-v1.0.0.pdf',
      SITE_ORIGIN + '/', 'https://www.carenetconsultants.co.za/medical-surveillance-plans'];
    const notPlan = ['/hsf-sample.html', '/hsf-sample', '/hsf-sample.html?industry=construction', '/portal.html', '/portal',
      '/health-and-safety-file', '/health-and-safety-file.html#pricing', '/hsf-builder.html?demo=1', '/legislation',
      '/legislation#occupational-health-and-safety-act', '/samples/data/x.json', '/examples/A-legal-register-extract.pdf',
      '#main', '?industry=construction', '', 'https://wa.me/27600702723', 'https://www.carenetconsultants.co.za/',
      'https://www.carenetconsultants.co.za/privacy-policy', 'mailto:someone@example.co.za', 'javascript:void(0)',
      '/api/signon', '/shopping', '/samples', '/sampler'];
    for (const u of plan) assert.ok(planTarget(u, page), u + ' should count as a Plan page');
    for (const u of notPlan) assert.equal(planTarget(u, page), null, u + ' should not count as a Plan page');
  });

  test('the scanner finds every kind of Plan link and leaves separators alone', () => {
    const html = [
      '<a class="logo-link" href="/">logo</a>',
      '<!-- <a href="/shop.html">in a comment</a> -->',
      '<form action="/assess.html"></form>',
      '<area href="pilot.html">',
      '<button onclick="location.href=\'/method\'">x</button>',
      '<script>',
      '  // location.href = "/"; in a comment',
      '  const dmy = (m) => m[3] + \'/\' + m[2] + \'/\' + m[1];',
      '  const re = /^\\d{2}\\/\\d{2}\\/\\d{4}$/; const x = "https://wa.me/1";',
      '  function a() { location.href = \'/\'; }',
      '  function b() { window.open(\'/sample.html?industry=\' + slug); }',
      '  const menu = { href: \'/industry\' };',
      '  const h = \'<a href="/account">Account</a>\';',
      '  const k = `<a href="/medical-surveillance-plans.html#top">${t}</a>`;',
      '  const ok = \'<a href="/hsf-sample.html?industry=\' + s + \'">\' + \'<a href="\' + esc(u) + \'">\';',
      '  location.assign(CFG.base + \'/pilot\');',
      '</script>'
    ].join('\n');
    const found = scanHtml(html, 'synthetic.html');
    const lines = found.map((f) => f.where.split(':')[1] + ' ' + f.target.path).sort();
    assert.deepStrictEqual(lines, ['1 /', '10 /', '11 /sample', '12 /industry', '13 /account', '14 /medical-surveillance-plans',
      '16 /pilot', '3 /assess', '4 /pilot', '5 /method'].sort(), describe(found));
  });

  for (const page of FILE_PAGES) {
    const html = read(page);

    test(page + ' never links, submits or redirects to a Plan page', () => {
      const found = scanHtml(html, page);
      assert.strictEqual(found.length, 0, page + ' points to the Medical Surveillance Plan pages (contract 15.1):\n' + describe(found));
    });

    test(page + ': the Care Net logo links to /health-and-safety-file', () => {
      const text = blank(html, htmlCommentRanges(html));
      const logos = [];
      const re = /<a\b([^>]*)>([\s\S]*?)<\/a\s*>/gi;
      let m;
      while ((m = re.exec(text))) {
        const attrs = m[1], inner = m[2];
        const isLogo = /\bclass\s*=\s*["'][^"']*\blogo/i.test(attrs)
          || /<img\b[^>]*(?:\bclass\s*=\s*["'][^"']*logo|\bsrc\s*=\s*["'][^"']*logo[^"']*["']|\bdata-asset\s*=\s*["'][^"']*logo)/i.test(inner);
        if (!isLogo) continue;
        const h = /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(attrs);
        logos.push({ line: lineAt(html, m.index), href: h ? decodeEntities(h[1] !== undefined ? h[1] : (h[2] !== undefined ? h[2] : h[3])) : null });
      }
      assert.ok(logos.length >= 1, page + ' has no Care Net logo link');
      const wrong = logos.filter((l) => l.href !== '/health-and-safety-file');
      assert.deepStrictEqual(wrong, [], page + ': every logo link must go to /health-and-safety-file');
    });

    test(page + ' never says "Build my Plan"', () => {
      const found = hits(html, BUILD_MY_PLAN_RE, page).concat(hits(decodeEntities(html), BUILD_MY_PLAN_RE, page + ' (entities decoded)'));
      assert.deepStrictEqual(found, [], 'The "Build my Plan" button belongs to the Plan, not the File (contract 15.1)');
    });

    test(page + ' shows no internal platform name', () => {
      const found = platformHits(withoutComments(html), page);
      assert.deepStrictEqual(found, [], 'Internal platform names (MSP FORGE, HSF FORGE, SharePoint, Cursor) are never visible to visitors (comments are ignored)');
    });

    test(page + ': every script it loads is scanned, shared ones included', () => {
      const loaded = pageScripts(html, page);
      assert.ok(loaded.length > 0, page + ' loads no script from this site');
      const all = fileScripts();
      for (const rel of loaded) {
        assert.ok(fs.existsSync(path.join(VERCEL, rel)), page + ' loads ' + rel + ', which is missing');
        assert.ok(all.includes(rel), rel + ' (loaded by ' + page + ') is not in the scanned scripts');
      }
    });
  }

  const scripts = fileScripts();
  test('the File scripts are all there, with the shared scripts every File page loads', () => {
    for (const s of ['hsf/pricing.js', 'hsf/examples.js', 'hsf/legislation-index.js', 'js/cnc-hsf-links.js',
      'js/cnc-header.js', 'js/cnc-config.js', 'js/cnc-tracking.js', 'js/cnc-auth.js', 'js/cnc-secnav.js',
      'js/cnc-design-assets.js', 'js/cnc-icon-fit.js', 'hsf/samples/construction.js']) {
      assert.ok(scripts.includes(s) && fs.existsSync(path.join(VERCEL, s)), s + ' is missing');
    }
    assert.ok(sampleSlugs().length > 0, 'no sample industries in vercel/hsf/samples');
  });
  test('each string let through as "not an address" is still where it was', () => {
    for (const x of NOT_ADDRESSES) {
      assert.ok(scripts.includes(x.file), x.file + ' is no longer a File script; remove its entry');
      const lines = read(x.file).split(/\r\n|\r|\n/).map((l) => l.trim());
      assert.ok(lines.includes(x.line), x.file + ' no longer has the line ' + JSON.stringify(x.line) + '; remove its entry');
    }
  });
  for (const rel of scripts) {
    test(rel + ' carries no Plan page address and no internal platform name', () => {
      const src = read(rel);
      const found = scanScript(src, rel).filter((f) => !notAddress(rel, src, f));
      assert.strictEqual(found.length, 0, rel + ' points to the Medical Surveillance Plan pages (contract 15.1):\n' + describe(found));
      const code = scriptWithoutComments(src);
      const words = platformHits(code, rel).concat(hits(code, BUILD_MY_PLAN_RE, rel));
      assert.deepStrictEqual(words, [], rel + ' carries text visitors may see that names an internal platform or the Plan button');
    });
  }

  test('hsf/pricing.js holds the Care Net client price and the free tiers (contract 15.2)', () => {
    const src = read('hsf/pricing.js');
    const sandbox = { window: {} };
    vm.runInNewContext(src, sandbox, { filename: 'pricing.js', timeout: 2000 });
    const P = sandbox.window.HSF_PRICING;
    assert.ok(P && typeof P === 'object', 'window.HSF_PRICING is not set');
    assert.strictEqual(P.cnc_client_price, 4000, 'cnc_client_price');
    assert.strictEqual(P.free_medicals_threshold, 100, 'free_medicals_threshold');
    assert.strictEqual(P.site_and_subcontractors_threshold, 500, 'site_and_subcontractors_threshold');
    assert.ok(!Object.prototype.hasOwnProperty.call(P, 'cnc_discount'), 'cnc_discount has been replaced by the flat price');
    assert.ok(!/cnc_discount/.test(JSON.stringify(P)), 'cnc_discount still appears in the pricing data');
    assert.ok(!/cnc_discount/.test(scriptWithoutComments(src)), 'cnc_discount still appears in pricing.js');
  });

  test('every rand amount in hsf/pricing.js is written R4 000,00, the source names included', () => {
    const sandbox = { window: {} };
    vm.runInNewContext(read('hsf/pricing.js'), sandbox, { filename: 'pricing.js', timeout: 2000 });
    const bad = [];
    const walk = (v, at) => {
      if (typeof v === 'string') {
        for (const m of v.matchAll(/\bR ?\d[\d ]*(?:[.,]\d+)?/g)) {
          const amount = m[0].trim();
          if (!/^R\d{1,3}(?: \d{3})*,\d{2}$/.test(amount)) bad.push(at + ': "' + amount + '" in "' + v + '"');
        }
      } else if (v && typeof v === 'object') {
        for (const k of Object.keys(v)) walk(v[k], at + (Array.isArray(v) ? '[' + k + ']' : '.' + k));
      }
    };
    walk(sandbox.window.HSF_PRICING, 'HSF_PRICING');
    assert.deepStrictEqual(bad, [], 'rand amounts are written with a space for thousands and a comma for cents');
  });

  test('health-and-safety-file.html no longer offers 25% off', () => {
    const html = read('health-and-safety-file.html');
    const found = hits(html, PCT_25_RE, 'health-and-safety-file.html').concat(hits(decodeEntities(html), PCT_25_RE, 'health-and-safety-file.html (entities decoded)'));
    assert.deepStrictEqual(found, [], 'The market average less 25% was replaced by the flat Care Net client price (contract 15.2)');
    assert.ok(!/cnc_discount/.test(html), 'health-and-safety-file.html still reads cnc_discount');
  });
}

if (!globalThis.__CNC_FILE_SEPARATION_LIB_ONLY) registerTests();
