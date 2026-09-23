// CNC HSF FORGE | tests for server/serve.js (node --test; a real server on a spare port)
// No network beyond localhost: the API paths exercised here answer before any
// outbound call (no key, no token, bad JSON), and the throwing handler lives in a
// temporary root made for this test.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
process.env.SUPABASE_URL = 'https://unit-test.supabase.invalid';
process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY;

const { createServer, compileSource, fillDestination } = require('../../server/serve');

const VERCEL = path.resolve(__dirname, '..', '..', 'vercel');
const logged = [];
test.mock.method(console, 'error', (...a) => { logged.push(a.map(String).join(' ')); });
test.after(() => {
  for (const line of logged) assert.ok(!line.includes(SERVICE_KEY), 'a log line carries the service role key');
});

function listen(server) {
  return new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}

function request(port, method, p, opts) {
  const o = opts || {};
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method, path: p, headers: o.headers || {} }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString('utf8') }));
    });
    req.on('error', reject);
    if (o.body !== undefined) req.write(o.body);
    req.end();
  });
}

function assertSafe(r) {
  const s = r.body + JSON.stringify(r.headers);
  assert.ok(!s.includes(SERVICE_KEY), 'response carries the service role key');
  assert.ok(!/\bat [^\s]+ \(?[^\s)]*:\d+:\d+\)?/.test(s), 'response carries a stack trace');
}

let server;
let port;
test.before(async () => {
  server = createServer({ quiet: true });
  port = await listen(server);
});
test.after(() => new Promise(resolve => server.close(resolve)));

const get = (p, o) => request(port, 'GET', p, o).then(r => { assertSafe(r); return r; });

test('compileSource and fillDestination handle the vercel.json syntax used here', () => {
  const a = compileSource('/samples/:file(.*\\.pdf)');
  const m = a.re.exec('/samples/CNC-MSP-SAMPLE-Mining.pdf');
  assert.ok(m);
  assert.equal(fillDestination('/sample.html?f=:file', m, a.names), '/sample.html?f=CNC-MSP-SAMPLE-Mining.pdf');
  assert.equal(a.re.exec('/samples/data/x.js'), null);
  const b = compileSource('/fonts/(.*)');
  assert.ok(b.re.test('/fonts/arial.woff2'));
  assert.equal(fillDestination('/f/$1', b.re.exec('/fonts/a.woff2'), b.names), '/f/a.woff2');
  const c = compileSource('/sample.html');
  assert.ok(c.re.test('/sample.html'));
  assert.ok(!c.re.test('/sampleXhtml'), 'dots are literal');
  const d = compileSource('/blog/:slug');
  assert.equal(fillDestination('/posts/:slug', d.re.exec('/blog/hello'), d.names), '/posts/hello');
});

test('static pages: / and clean URLs serve HTML; .html and trailing slashes redirect', async () => {
  const home = await get('/');
  assert.equal(home.status, 200);
  assert.match(home.headers['content-type'], /^text\/html/);
  assert.equal(home.body, fs.readFileSync(path.join(VERCEL, 'index.html'), 'utf8'));
  assert.equal(home.headers['x-content-type-options'], 'nosniff');

  const method = await get('/method');
  assert.equal(method.status, 200);
  assert.equal(method.body, fs.readFileSync(path.join(VERCEL, 'method.html'), 'utf8'));

  const r1 = await get('/method.html?x=1');
  assert.equal(r1.status, 308);
  assert.equal(r1.headers.location, '/method?x=1');
  const r2 = await get('/index.html');
  assert.equal(r2.status, 308);
  assert.equal(r2.headers.location, '/');
  const r3 = await get('/method/');
  assert.equal(r3.status, 308);
  assert.equal(r3.headers.location, '/method');

  const head = await request(port, 'HEAD', '/method');
  assert.equal(head.status, 200);
  assert.equal(head.body, '');

  const post = await request(port, 'POST', '/method', { body: 'x' });
  assert.equal(post.status, 405);
});

test('assets carry their types and the vercel.json headers', async () => {
  const css = fs.readdirSync(path.join(VERCEL, 'css')).find(f => f.endsWith('.css'));
  const r1 = await get(`/css/${css}`);
  assert.equal(r1.status, 200);
  assert.match(r1.headers['content-type'], /^text\/css/);

  const font = fs.readdirSync(path.join(VERCEL, 'fonts')).find(f => f.endsWith('.woff2'));
  const r2 = await get(`/fonts/${font}`);
  assert.equal(r2.status, 200);
  assert.equal(r2.headers['content-type'], 'font/woff2');
  assert.equal(r2.headers['cache-control'], 'public, max-age=31536000, immutable');
  assert.equal(r2.headers['access-control-allow-origin'], '*');

  const r3 = await get('/sample');
  assert.equal(r3.status, 200);
  assert.equal(r3.headers['x-robots-tag'], 'noindex, nofollow, noarchive', 'the /sample.html header rule follows the clean URL');

  const r4 = await get('/does-not-exist');
  assert.equal(r4.status, 404);
});

test('vercel.json redirects and rewrites', async () => {
  const r1 = await get('/samples/CNC-MSP-SAMPLE-Construction.pdf');
  assert.equal(r1.status, 308);
  assert.equal(r1.headers.location, '/sample.html?industry=construction');
  const r2 = await get('/samples/CNC-MSP-SAMPLE-Mining.pdf');
  assert.equal(r2.status, 308);
  assert.equal(r2.headers.location, '/sample.html');
  const r3 = await get('/build-your-plan');
  assert.equal(r3.status, 200);
  assert.equal(r3.body, fs.readFileSync(path.join(VERCEL, 'shop.html'), 'utf8'));
});

test('server source, config and traversal attempts are never served', async () => {
  for (const p of [
    '/api/kernel.js', '/lib/db.js', '/lib/auth.js', '/api/../lib/db.js', '/vercel.json', '/package.json',
    '/README.md', '/%2e%2e/server/serve.js', '/css/..%2F..%2Fserver%2Fserve.js', '/css/%2e%2e/%2e%2e/SPEC.md',
    '/.env', '/api', '/api/', '/api/nope', '/api/Kernel', '/api/a/b',
  ]) {
    const r = await get(p);
    assert.ok([400, 404, 308].includes(r.status), `${p} answered ${r.status}`);
    if (r.status === 308) {
      const next = await get(r.headers.location);
      assert.ok([400, 404].includes(next.status), `${p} then ${r.headers.location} answered ${next.status}`);
    }
    assert.ok(!r.body.includes('module.exports'), `${p} leaked source`);
    assert.ok(!r.body.includes('SUPABASE_SERVICE_ROLE_KEY'), `${p} leaked source`);
  }
});

test('no redirect ever points at another host (no protocol relative Location)', async () => {
  for (const p of ['//evil.example/', '//evil.example//', '//method.html', '///method/', '//index.html']) {
    const r = await get(p);
    if (r.status >= 300 && r.status < 400) {
      assert.ok(r.headers.location.startsWith('/'), `${p} -> ${r.headers.location}`);
      assert.ok(!r.headers.location.startsWith('//'), `${p} -> ${r.headers.location}`);
    }
  }
});

test('/api/kernel without a key is a 401 JSON answer with CORS and no-store', async () => {
  const r = await get('/api/kernel?r=industries');
  assert.equal(r.status, 401);
  assert.match(r.headers['content-type'], /^application\/json/);
  assert.equal(r.headers['access-control-allow-origin'], '*');
  assert.equal(r.headers['cache-control'], 'no-store');
  assert.equal(JSON.parse(r.body).code, 'invalid_key');
  const bare = await get('/api/kernel');
  assert.equal(bare.status, 401);
  const pre = await request(port, 'OPTIONS', '/api/kernel');
  assert.equal(pre.status, 204);
});

test('/api/hsf-* without a token are 401 JSON answers', async () => {
  for (const p of ['/api/hsf-consent', '/api/hsf-upload', '/api/hsf-file']) {
    const r = await get(p);
    assert.equal(r.status, 401, p);
    assert.equal(JSON.parse(r.body).code, 'sign_in_required');
  }
  const post = await request(port, 'POST', '/api/hsf-upload', {
    headers: { 'content-type': 'application/json' }, body: JSON.stringify({ action: 'register' }),
  });
  assert.equal(post.status, 401);
});

test('invalid JSON reaching a handler that reads req.body directly is a 400, as on Vercel', async () => {
  const r = await request(port, 'POST', '/api/intake', { headers: { 'content-type': 'application/json' }, body: '{"company_registered_name":' });
  assertSafe(r);
  assert.equal(r.status, 400);
  assert.equal(JSON.parse(r.body).code, 'bad_json');
});

test('a body over the limit is refused with 413', async () => {
  const r = await request(port, 'POST', '/api/hsf-file', { headers: { 'content-type': 'application/json' }, body: `{"x":"${'a'.repeat(1024 * 1024 + 10)}"}` });
  assert.equal(r.status, 413);
});

test('a handler that throws answers 500 with no stack and no secret; query, body and helpers reach handlers', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cnc-serve-'));
  try {
    fs.mkdirSync(path.join(root, 'api'));
    fs.writeFileSync(path.join(root, 'index.html'), '<!doctype html><title>t</title>');
    fs.writeFileSync(path.join(root, 'api', 'boom.js'),
      "module.exports = async () => { throw new Error('exploded with ' + process.env.SUPABASE_SERVICE_ROLE_KEY); };\n");
    fs.writeFileSync(path.join(root, 'api', 'echo.js'),
      'module.exports = async (req, res) => { res.status(201).json({ method: req.method, query: Object.assign({}, req.query), body: req.body }); };\n');
    const s = createServer({ root, quiet: true });
    const p = await listen(s);
    try {
      const r1 = await request(p, 'GET', '/api/boom');
      assertSafe(r1);
      assert.equal(r1.status, 500);
      assert.deepEqual(JSON.parse(r1.body), { error: 'The request could not be processed.', code: 'server_error' });

      const r2 = await request(p, 'POST', '/api/echo?a=1&b=2&b=3', { headers: { 'content-type': 'application/json' }, body: '{"x":[1,2]}' });
      assert.equal(r2.status, 201);
      assert.deepEqual(JSON.parse(r2.body), { method: 'POST', query: { a: '1', b: ['2', '3'] }, body: { x: [1, 2] } });

      const r3 = await request(p, 'POST', '/api/echo', { headers: { 'content-type': 'text/plain' }, body: '{"y":1}' });
      assert.deepEqual(JSON.parse(r3.body).body, '{"y":1}', 'a text body stays a string for the handler to parse');

      const r4 = await request(p, 'POST', '/api/echo?__proto__=x', { headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: 'k=v&k=w' });
      assert.deepEqual(JSON.parse(r4.body).body, { k: ['v', 'w'] });
    } finally {
      await new Promise(resolve => s.close(resolve));
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
