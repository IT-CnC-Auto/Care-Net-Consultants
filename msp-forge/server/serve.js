#!/usr/bin/env node
// CNC HSF FORGE | HSF-HOST-01 v1.0.0 | Dependency free host for the vercel/ site and API
// The path to hosting the site inside MyClinicOnline (MCO): plain Node (18 or
// later), no npm packages, no build step. It serves the vercel/ directory the
// way Vercel does for this project and mounts every vercel/api/<name>.js
// handler at /api/<name> with the helpers those handlers use.
//
//   Statics:   cleanUrls (/method serves method.html; /method.html redirects to
//              /method; /index.html redirects to /), trailingSlash false, the
//              redirects, rewrites and headers in vercel/vercel.json where they
//              use the simple source syntax (:name, :name(regex), (regex)).
//              Order as on Vercel: redirects, filesystem and API, then rewrites.
//              Never served: api/ and lib/ source, dot files, vercel.json,
//              package.json, README.md.
//   API:       /api/<name> -> require('vercel/api/<name>.js')(req, res) with
//              req.query (string, or array when a key repeats), req.body (JSON
//              parsed by content type, lazily, as Vercel does; invalid JSON is a
//              400), res.status(), res.json(), res.send(), res.redirect().
//              A handler that throws gets a 500 with a plain message: no stack.
//   Logs:      one line per request: time, method, path (never the query
//              string, which can carry a token), status, duration.
//
// Environment (set by the host, never in files): SUPABASE_URL,
// SUPABASE_SERVICE_ROLE_KEY and whatever else the handlers read. MCO_BASE_URL and
// MCO_API_TOKEN are pending the MCO interface contract (HSF-3).
//
// Run:  node server/serve.js [--port 3000] [--host 127.0.0.1]
//       (or PORT and HOST in the environment; HOST=0.0.0.0 inside a container)

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const DEFAULT_ROOT = path.resolve(__dirname, '..', 'vercel');
const MAX_BODY_BYTES = 1024 * 1024;
const API_NAME_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/;
const HIDDEN_TOP_DIRS = new Set(['api', 'lib', 'node_modules']);
const HIDDEN_ROOT_FILES = new Set(['vercel.json', 'package.json', 'package-lock.json', 'README.md']);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.htm': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.csv': 'text/csv; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.pdf': 'application/pdf',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

// Log lines never carry a secret from the environment.
function redact(value) {
  let s = String(value === undefined || value === null ? '' : value).slice(0, 300);
  for (const k of ['SUPABASE_SERVICE_ROLE_KEY', 'MCO_API_TOKEN']) {
    const v = process.env[k];
    if (v && v.length >= 8) s = s.split(v).join('[redacted]');
  }
  return s;
}

// ---------------------------------------------------------------------------
// vercel.json source patterns (the simple path-to-regexp subset this site uses)

function closingParen(s, start) {
  let depth = 0;
  for (let i = start; i < s.length; i++) {
    const c = s[i];
    if (c === '\\') { i++; continue; }
    if (c === '(') depth++;
    else if (c === ')') { depth--; if (depth === 0) return i; }
  }
  throw new Error(`unbalanced parenthesis in route source: ${s}`);
}

function compileSource(source) {
  let re = '^';
  const names = [];
  let unnamed = 0;
  let i = 0;
  while (i < source.length) {
    const c = source[i];
    if (c === ':' && /[A-Za-z_]/.test(source[i + 1] || '')) {
      let j = i + 1;
      while (j < source.length && /[A-Za-z0-9_]/.test(source[j])) j++;
      const name = source.slice(i + 1, j);
      let pattern = '[^/]+';
      if (source[j] === '(') {
        const end = closingParen(source, j);
        pattern = source.slice(j + 1, end);
        j = end + 1;
      }
      const mod = source[j];
      if (mod === '*') { re += '(.*)'; j++; }
      else if (mod === '+') { re += '(.+)'; j++; }
      else if (mod === '?') { re += `(${pattern})?`; j++; }
      else re += `(${pattern})`;
      names.push(name);
      i = j;
      continue;
    }
    if (c === '(') {
      const end = closingParen(source, i);
      re += `(${source.slice(i + 1, end)})`;
      names.push(String(unnamed++));
      i = end + 1;
      continue;
    }
    re += c.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    i++;
  }
  return { re: new RegExp(`${re}$`), names };
}

function fillDestination(destination, match, names) {
  return destination.replace(/\$(\d+)|:([A-Za-z_][A-Za-z0-9_]*)/g, (all, num, name) => {
    if (num) return match[Number(num)] || '';
    const idx = names.indexOf(name);
    return idx === -1 ? all : (match[idx + 1] || '');
  });
}

function loadConfig(root) {
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(path.join(root, 'vercel.json'), 'utf8')); } catch (err) { cfg = {}; }
  const compile = list => (Array.isArray(list) ? list : [])
    .filter(r => r && typeof r.source === 'string' && !r.has && !r.missing)
    .map(r => Object.assign({}, r, compileSource(r.source)));
  return {
    cleanUrls: cfg.cleanUrls === true,
    trailingSlash: cfg.trailingSlash,
    redirects: compile(cfg.redirects),
    rewrites: compile(cfg.rewrites),
    headers: compile(cfg.headers),
  };
}

// ---------------------------------------------------------------------------
// Request and response helpers the Vercel handlers expect

function toQuery(searchParams) {
  const q = Object.create(null);
  for (const [k, v] of searchParams) {
    if (Object.prototype.hasOwnProperty.call(q, k)) q[k] = [].concat(q[k], v);
    else q[k] = v;
  }
  return q;
}

function readRaw(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let over = false;
    req.on('data', chunk => {
      if (over) return;
      size += chunk.length;
      if (size > limit) { over = true; chunks.length = 0; return; }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(over ? null : Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function defineBody(req, raw) {
  const type = String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
  let parsed = false;
  let value;
  Object.defineProperty(req, 'body', {
    configurable: true,
    enumerable: true,
    get() {
      if (parsed) return value;
      parsed = true;
      if (!raw || raw.length === 0) { value = undefined; return value; }
      const text = raw.toString('utf8');
      if (type === 'application/json' || type.endsWith('+json')) {
        try { value = JSON.parse(text); } catch (err) {
          parsed = false;
          const e = new Error('The request body is not valid JSON.');
          e.status = 400; e.statusCode = 400; e.expose = true; e.invalidJson = true;
          throw e;
        }
      } else if (type === 'application/x-www-form-urlencoded') {
        value = toQuery(new URLSearchParams(text));
      } else if (type.startsWith('text/')) {
        value = text;
      } else {
        value = raw;
      }
      return value;
    },
    set(v) { parsed = true; value = v; },
  });
}

function decorate(res) {
  res.status = code => { res.statusCode = code; return res; };
  res.json = obj => {
    const body = JSON.stringify(obj === undefined ? null : obj);
    if (!res.hasHeader('Content-Type')) res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Content-Length', Buffer.byteLength(body));
    res.end(body);
    return res;
  };
  res.send = body => {
    if (body === undefined || body === null) { res.end(); return res; }
    if (Buffer.isBuffer(body)) {
      if (!res.hasHeader('Content-Type')) res.setHeader('Content-Type', 'application/octet-stream');
      res.setHeader('Content-Length', body.length);
      res.end(body);
      return res;
    }
    if (typeof body === 'object') return res.json(body);
    const s = String(body);
    if (!res.hasHeader('Content-Type')) res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Content-Length', Buffer.byteLength(s));
    res.end(s);
    return res;
  };
  res.redirect = (a, b) => {
    const code = typeof a === 'number' ? a : 307;
    const location = typeof a === 'number' ? b : a;
    res.statusCode = code;
    res.setHeader('Location', location);
    res.end();
    return res;
  };
  return res;
}

function sendJson(res, status, obj, extraHeaders) {
  if (res.headersSent) { res.end(); return; }
  const body = JSON.stringify(obj);
  res.writeHead(status, Object.assign({
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  }, extraHeaders || {}));
  res.end(body);
}

function sendText(res, status, text, extraHeaders) {
  res.writeHead(status, Object.assign({
    'Content-Type': 'text/plain; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
  }, extraHeaders || {}));
  res.end(text);
}

// A local redirect never starts with // (a protocol relative URL would send the
// visitor to another host).
function redirect(res, status, location) {
  if (location.startsWith('/')) location = location.replace(/^\/{2,}/, '/');
  res.writeHead(status, { Location: location, 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(`Redirecting to ${location}\n`);
}

// ---------------------------------------------------------------------------
// The server

function createServer(options) {
  const opts = options || {};
  const root = path.resolve(opts.root || DEFAULT_ROOT);
  const rootReal = fs.realpathSync(root);
  const apiDir = path.join(root, 'api');
  const cfg = loadConfig(root);
  const quiet = Boolean(opts.quiet);
  const handlers = new Map();

  function isHidden(rel) {
    const parts = rel.split('/').filter(Boolean);
    if (!parts.length) return false;
    if (parts.some(p => p.startsWith('.'))) return true;
    if (HIDDEN_TOP_DIRS.has(parts[0])) return true;
    if (parts.length === 1 && HIDDEN_ROOT_FILES.has(parts[0])) return true;
    return false;
  }

  // Resolve a URL path to a readable file inside root, or null.
  function fileFor(rel) {
    if (isHidden(rel)) return null;
    const full = path.resolve(root, rel);
    if (full !== root && !full.startsWith(root + path.sep)) return null;
    let stat;
    try { stat = fs.statSync(full); } catch (err) { return null; }
    if (!stat.isFile()) return null;
    let real;
    try { real = fs.realpathSync(full); } catch (err) { return null; }
    if (!real.startsWith(rootReal + path.sep)) return null;
    return { full, stat };
  }

  // cleanUrls lookup: exact file (not .html when cleanUrls, unless direct is
  // allowed, as for a rewrite destination), then <path>.html, then <path>/index.html.
  function resolveStatic(pathname, allowHtmlDirect) {
    const rel = pathname.replace(/^\/+/, '');
    const candidates = [];
    if (rel && (!cfg.cleanUrls || allowHtmlDirect || !/\.html?$/.test(rel))) candidates.push(rel);
    if (rel && !rel.endsWith('/')) candidates.push(`${rel}.html`);
    candidates.push(rel ? `${rel.replace(/\/$/, '')}/index.html` : 'index.html');
    for (const c of candidates) {
      const f = fileFor(c);
      if (f) return Object.assign({ rel: c }, f);
    }
    return null;
  }

  function applyHeaders(res, paths) {
    for (const rule of cfg.headers) {
      if (!paths.some(p => rule.re.test(p))) continue;
      for (const h of rule.headers || []) {
        if (h && typeof h.key === 'string' && typeof h.value === 'string') res.setHeader(h.key, h.value);
      }
    }
  }

  function loadHandler(name) {
    if (handlers.has(name)) return handlers.get(name);
    const file = path.join(apiDir, `${name}.js`);
    let handler = null;
    if (fs.existsSync(file)) {
      const mod = require(file);
      handler = typeof mod === 'function' ? mod : (mod && typeof mod.default === 'function' ? mod.default : null);
    }
    handlers.set(name, handler);
    return handler;
  }

  async function runApi(req, res, name, url) {
    const handler = loadHandler(name);
    if (!handler) { sendJson(res, 404, { error: 'Not found.', code: 'not_found' }); return; }
    const raw = await readRaw(req, MAX_BODY_BYTES);
    if (raw === null) {
      sendJson(res, 413, { error: 'The request is too large.', code: 'too_large' }, { Connection: 'close' });
      return;
    }
    req.query = toQuery(url.searchParams);
    defineBody(req, raw);
    decorate(res);
    applyHeaders(res, [url.pathname]);
    try {
      await handler(req, res);
    } catch (err) {
      if (err && err.invalidJson) {
        sendJson(res, 400, { error: 'The request body is not valid JSON.', code: 'bad_json' });
        return;
      }
      console.error(`api ${name} failure`, err && err.message ? redact(err.message) : 'unknown');
      if (!res.headersSent) sendJson(res, 500, { error: 'The request could not be processed.', code: 'server_error' });
      else res.end();
    }
  }

  function serveFile(req, res, file, requestPath) {
    const type = MIME[path.extname(file.full).toLowerCase()] || 'application/octet-stream';
    res.setHeader('X-Content-Type-Options', 'nosniff');
    applyHeaders(res, [requestPath, `/${file.rel}`]);
    const lastModified = file.stat.mtime.toUTCString();
    const since = req.headers['if-modified-since'];
    if (since && !Number.isNaN(Date.parse(since)) && Math.floor(file.stat.mtimeMs / 1000) <= Math.floor(Date.parse(since) / 1000)) {
      res.writeHead(304, { 'Last-Modified': lastModified });
      res.end();
      return;
    }
    res.writeHead(200, { 'Content-Type': type, 'Content-Length': file.stat.size, 'Last-Modified': lastModified });
    if (req.method === 'HEAD') { res.end(); return; }
    const stream = fs.createReadStream(file.full);
    stream.on('error', () => res.destroy());
    stream.pipe(res);
  }

  function notFound(req, res) {
    const page = fileFor('404.html');
    if (page && req.method !== 'HEAD') {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8', 'Content-Length': page.stat.size });
      fs.createReadStream(page.full).pipe(res);
      return;
    }
    sendText(res, 404, 'Not found\n');
  }

  function withSearch(location, search) {
    return search && !location.includes('?') ? `${location}${search}` : location;
  }

  async function route(req, res) {
    if (typeof req.url !== 'string' || !req.url.startsWith('/')) { sendText(res, 400, 'Bad request\n'); return; }
    const url = new URL(`http://localhost${req.url}`);
    let pathname;
    try { pathname = decodeURIComponent(url.pathname); } catch (err) { sendText(res, 400, 'Bad request\n'); return; }
    if (pathname.includes('\0') || pathname.includes('\\')) { sendText(res, 400, 'Bad request\n'); return; }

    // trailingSlash: false
    if (cfg.trailingSlash === false && pathname.length > 1 && pathname.endsWith('/')) {
      redirect(res, 308, withSearch(url.pathname.replace(/\/+$/, '') || '/', url.search));
      return;
    }

    // vercel.json redirects
    for (const r of cfg.redirects) {
      const m = r.re.exec(pathname);
      if (!m) continue;
      const status = Number.isInteger(r.statusCode) ? r.statusCode : (r.permanent === false ? 307 : 308);
      redirect(res, status, withSearch(fillDestination(r.destination, m, r.names), url.search));
      return;
    }

    // API functions
    const api = /^\/api\/([^/]+)$/.exec(pathname);
    if (api) {
      if (!API_NAME_RE.test(api[1])) { sendJson(res, 404, { error: 'Not found.', code: 'not_found' }); return; }
      await runApi(req, res, api[1], url);
      return;
    }
    if (pathname === '/api' || pathname.startsWith('/api/')) { sendJson(res, 404, { error: 'Not found.', code: 'not_found' }); return; }

    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.setHeader('Allow', 'GET, HEAD');
      sendText(res, 405, 'Method not allowed\n');
      return;
    }

    // cleanUrls: /name.html -> /name and /index.html -> /
    if (cfg.cleanUrls && /\.html$/.test(pathname) && fileFor(pathname.replace(/^\/+/, ''))) {
      let clean = pathname.replace(/\.html$/, '');
      if (clean === '/index' || clean.endsWith('/index')) clean = clean.slice(0, -'index'.length).replace(/\/$/, '') || '/';
      redirect(res, 308, withSearch(encodeURI(clean), url.search));
      return;
    }

    const file = resolveStatic(pathname, false);
    if (file) { serveFile(req, res, file, pathname); return; }

    // vercel.json rewrites (after the filesystem, as on Vercel)
    for (const r of cfg.rewrites) {
      const m = r.re.exec(pathname);
      if (!m) continue;
      const dest = fillDestination(r.destination, m, r.names);
      if (!dest.startsWith('/')) continue; // external proxy rewrites are not supported here
      const destUrl = new URL(`http://localhost${dest}`);
      for (const [k, v] of url.searchParams) if (!destUrl.searchParams.has(k)) destUrl.searchParams.append(k, v);
      const destPath = decodeURIComponent(destUrl.pathname);
      const destApi = /^\/api\/([^/]+)$/.exec(destPath);
      if (destApi && API_NAME_RE.test(destApi[1])) { await runApi(req, res, destApi[1], destUrl); return; }
      const target = resolveStatic(destPath, true);
      if (target) { serveFile(req, res, target, pathname); return; }
    }

    notFound(req, res);
  }

  const server = http.createServer((req, res) => {
    const started = Date.now();
    res.on('finish', () => {
      if (quiet) return;
      const p = (req.url || '').split('?')[0];
      console.log(`${new Date().toISOString()} ${req.method} ${p} ${res.statusCode} ${Date.now() - started}ms`);
    });
    route(req, res).catch(err => {
      console.error('serve failure', err && err.message ? redact(err.message) : 'unknown');
      if (!res.headersSent) sendText(res, 500, 'Server error\n');
      else res.destroy();
    });
  });
  return server;
}

function argValue(argv, flag) {
  const i = argv.indexOf(flag);
  return i !== -1 && argv[i + 1] ? argv[i + 1] : null;
}

function start(argv) {
  const args = argv || process.argv.slice(2);
  const port = Number(argValue(args, '--port') || process.env.PORT || 3000);
  const host = argValue(args, '--host') || process.env.HOST || '127.0.0.1';
  const missing = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'].filter(k => !process.env[k]);
  if (missing.length) console.warn(`serve: ${missing.join(', ')} not set; API calls that need them will answer 503 or 500.`);
  const server = createServer({ quiet: process.env.SERVE_QUIET === '1' });
  server.listen(port, host, () => {
    const a = server.address();
    console.log(`serve: vercel/ on http://${a.address}:${a.port}`);
  });
  const stop = () => server.close(() => process.exit(0));
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
  return server;
}

module.exports = { createServer, compileSource, fillDestination, start };

if (require.main === module) start();
