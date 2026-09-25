#!/usr/bin/env node
/* =====================================================================
   run-lighthouse.mjs :: Lighthouse for the Bee-Inspect P2 pages, locally
   Bee-Inspect P2 (hsf/BEE-INSPECT-BUILD-PROMPT.md section 3 item 7: public
   pages Lighthouse 100 in all four categories).

   Run from msp-forge/:
     CHROME_PATH=/opt/pw-browsers/chromium-1194/chrome-linux/chrome \
       node docs/bee-inspect/p2/lighthouse/run-lighthouse.mjs [--runs 1]
   Needs npx and network access to the npm registry for lighthouse@12 (npx
   --yes lighthouse@12). Writes <page>-<desktop|mobile>.report.html and
   .report.json beside this file and prints a summary table (the median run
   when --runs is above 1).

   How it measures, and why (the same approach as msp-forge/LIGHTHOUSE.md):
   - server/serve.js serves vercel/ as Vercel does; a small front server here
     adds gzip, as Vercel's edge does, so the audit measures the page and not
     the missing compression of a test server.
   - The build environment's proxy blocks the image host (img.carenetcdn.com)
     and the icon host (*.r2.dev). Chromium maps those hosts to a local HTTPS
     stand in (a self signed certificate, --ignore-certificate-errors) that
     answers each image with a drawn stand in of the declared size, so layout,
     request count and layout shift are honest and image bytes are not.
     /icon-src/ (a vercel.json rewrite to the icon host, which the local server
     does not proxy) is answered the same way.
   - The flag bee_inspect_ads is on for 127.0.0.1 (js/flags.js), so the pages
     are measured as they will be where the flag is on: indexable. With the
     flag off in production they carry noindex, which Lighthouse's SEO
     category scores down by design (see index.md).
   ===================================================================== */
import http from 'node:http';
import https from 'node:https';
import zlib from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync, spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..', '..');
const { createServer } = require(path.join(ROOT, 'server', 'serve.js'));

const PAGES = [
  ['bee-inspect', '/bee-inspect'],
  ['bee-inspect-sample-report', '/bee-inspect/sample-report'],
  ['get-app', '/get-app'],
  ['health-and-safety-file', '/health-and-safety-file']
];
const argv = process.argv.slice(2);
const RUNS = Math.max(1, Number(argv[argv.indexOf('--runs') + 1]) || 1);
const ONLY = argv.includes('--only') ? argv[argv.indexOf('--only') + 1] : null;
/* --root <dir>: measure another copy of vercel/ (for example an export of the
   commit before P2, to compare); reports then go to <dir>/../lighthouse-root. */
const SITE = argv.includes('--root') ? path.resolve(argv[argv.indexOf('--root') + 1]) : path.join(ROOT, 'vercel');
const OUTDIR = argv.includes('--root') ? path.join(path.dirname(SITE), 'lighthouse-root') : HERE;
const CHROME = process.env.CHROME_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

function standIn(p) {
  if (/Care_Net_Logo/i.test(p)) return '<svg xmlns="http://www.w3.org/2000/svg" width="445" height="160" viewBox="0 0 445 160"><rect width="445" height="160" fill="#fff"/><text x="30" y="92" font-family="Arial" font-size="64" font-weight="700" fill="#0F0F0F">CARE NET</text><rect x="60" y="108" width="320" height="34" rx="4" fill="#ED1B24"/></svg>';
  if (/pattern-strip/i.test(p)) return '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="48"><rect width="96" height="48" fill="#fff"/><path d="M0 24l12-12 12 12 12-12 12 12 12-12 12 12 12-12 12 12" stroke="#ED1B24" stroke-width="3" fill="none"/></svg>';
  if (/record-submission/i.test(p)) return '<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><rect width="1920" height="1080" fill="#3a3a3a"/></svg>';
  if (/Bee_Icon/i.test(p)) return '<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44"><circle cx="22" cy="22" r="18" fill="#F0A32B"/></svg>';
  return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" rx="8" fill="#e9e6e6"/></svg>';
}
function sendSvg(res, p) {
  const body = zlib.gzipSync(Buffer.from(standIn(p)));
  res.writeHead(200, { 'Content-Type': 'image/svg+xml', 'Content-Encoding': 'gzip', 'Cache-Control': 'public, max-age=31536000', 'Access-Control-Allow-Origin': '*' });
  res.end(body);
}

function run(cmd, args, opts, ms) {
  return new Promise((ok) => {
    const c = spawn(cmd, args, opts);
    let stdout = '', stderr = '';
    c.stdout.on('data', (d) => { stdout += d; });
    c.stderr.on('data', (d) => { stderr += d; });
    const t = setTimeout(() => c.kill('SIGKILL'), ms);
    c.on('close', (status) => { clearTimeout(t); ok({ status, stdout, stderr }); });
    c.on('error', (error) => { clearTimeout(t); ok({ status: 1, stdout, stderr, error }); });
  });
}
async function listen(server) { await new Promise((ok, bad) => { server.once('error', bad); server.listen(0, '127.0.0.1', ok); }); return server.address().port; }

async function main() {
  if (!fs.existsSync(CHROME)) throw new Error('Chromium not found at ' + CHROME + ' (set CHROME_PATH)');
  const inner = createServer({ quiet: true, root: SITE });
  fs.mkdirSync(OUTDIR, { recursive: true });
  const innerPort = await listen(inner);
  const front = http.createServer((req, res) => {
    if (req.url.startsWith('/icon-src/')) return sendSvg(res, req.url);
    const up = http.request({ host: '127.0.0.1', port: innerPort, path: req.url, method: req.method, headers: Object.assign({}, req.headers, { 'accept-encoding': 'identity' }) }, (r) => {
      const type = String(r.headers['content-type'] || '');
      const headers = Object.assign({}, r.headers);
      if (/text|javascript|json|svg|xml/.test(type) && /gzip/.test(String(req.headers['accept-encoding'] || ''))) {
        delete headers['content-length'];
        headers['content-encoding'] = 'gzip';
        headers.vary = 'Accept-Encoding';
        if (!headers['cache-control'] && /\/(?:css|js|fonts|hsf)\//.test(req.url)) headers['cache-control'] = 'public, max-age=31536000';
        res.writeHead(r.statusCode, headers);
        r.pipe(zlib.createGzip()).pipe(res);
      } else {
        res.writeHead(r.statusCode, headers);
        r.pipe(res);
      }
    });
    up.on('error', () => { res.writeHead(502); res.end(); });
    req.pipe(up);
  });
  const port = await listen(front);

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bee-lh-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=img.carenetcdn.com',
    '-keyout', path.join(tmp, 'k.pem'), '-out', path.join(tmp, 'c.pem')], { stdio: 'ignore' });
  const cdn = https.createServer({ key: fs.readFileSync(path.join(tmp, 'k.pem')), cert: fs.readFileSync(path.join(tmp, 'c.pem')) }, (req, res) => sendSvg(res, req.url));
  const cdnPort = await listen(cdn);

  const flags = ['--headless=new', '--no-sandbox', '--no-proxy-server', '--ignore-certificate-errors', '--disable-dev-shm-usage',
    '--host-resolver-rules="MAP img.carenetcdn.com 127.0.0.1:' + cdnPort + ', MAP pub-05e130c201dd463a8accbcd12eb02d77.r2.dev 127.0.0.1:' + cdnPort + '"'].join(' ');
  const rows = [];
  try {
    for (const [name, p] of PAGES) {
      if (ONLY && !name.includes(ONLY)) continue;
      for (const ff of ['desktop', 'mobile']) {
        const runs = [];
        for (let i = 0; i < RUNS; i++) {
          const out = path.join(OUTDIR, name + '-' + ff);
          const args = ['--yes', 'lighthouse@12', 'http://127.0.0.1:' + port + p, '--quiet', '--output=json', '--output=html', '--output-path=' + out,
            '--chrome-flags=' + flags, '--only-categories=performance,accessibility,best-practices,seo'];
          if (ff === 'desktop') args.push('--preset=desktop');
          /* Asynchronous: the stand in servers live in this process and must keep answering. */
          const r = await run('npx', args, { env: Object.assign({}, process.env, { CHROME_PATH: CHROME }) }, 240000);
          if (r.status !== 0) throw new Error('lighthouse failed for ' + name + ' ' + ff + ':\n' + ((r.stdout || '') + (r.stderr || '') + String(r.error || '')).slice(-2000));
          const j = JSON.parse(fs.readFileSync(out + '.report.json', 'utf8'));
          const c = j.categories;
          const failing = [];
          for (const cat of Object.values(c)) {
            for (const ref of cat.auditRefs) {
              const a = j.audits[ref.id];
              if (ref.weight > 0 && a && a.score !== null && a.score < 1) failing.push(cat.id + ':' + ref.id + '=' + a.score);
            }
          }
          runs.push({ perf: Math.round(c.performance.score * 100), a11y: Math.round(c.accessibility.score * 100), bp: Math.round(c['best-practices'].score * 100),
            seo: Math.round(c.seo.score * 100), lcp: j.audits['largest-contentful-paint'].displayValue, cls: j.audits['cumulative-layout-shift'].displayValue,
            tbt: j.audits['total-blocking-time'].displayValue, failing, version: j.lighthouseVersion });
        }
        runs.sort((a, b) => (a.perf + a.a11y + a.bp + a.seo) - (b.perf + b.a11y + b.bp + b.seo));
        const m = runs[Math.floor(runs.length / 2)];
        rows.push(Object.assign({ page: p, ff }, m));
        console.log([p, ff, m.perf, m.a11y, m.bp, m.seo, 'LCP ' + m.lcp, 'CLS ' + m.cls, 'TBT ' + m.tbt, m.failing.join(' ')].join(' | '));
      }
    }
  } finally {
    inner.close(); front.close(); cdn.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  fs.writeFileSync(path.join(OUTDIR, 'summary.json'), JSON.stringify(rows, null, 1) + '\n');
}

main().catch((e) => { console.error(String(e && e.stack || e)); process.exit(1); });
