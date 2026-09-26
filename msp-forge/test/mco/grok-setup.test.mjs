// CNC HSF FORGE | tests for grok/setup.mjs, the bot host setup check (node --test)
// No network: every fetch is mocked. Each run works in its own temporary folder,
// so the only .env touched is the one the test made. The model ids and aliases
// are made up fixtures; none of them names a real model. The list shapes are
// assumptions until the first real run (KERNEL-API.md section 8.6).
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, readdir, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { run, parseEnv, withModelLine, EXIT } from '../../grok/setup.mjs';

const KERNEL_KEY = `cnck_${'b'.repeat(64)}`;
const XAI_KEY = 'xai-SETUP-TEST-key-must-never-appear-0123456789';
const BASE = 'https://forge.invalid';
const XAI_BASE = 'https://xai.invalid/v1';
const ENV = { XAI_API_KEY: XAI_KEY, CNC_KERNEL_API_KEY: KERNEL_KEY, CNC_KERNEL_API_BASE: BASE, XAI_API_BASE: XAI_BASE };

const KERNEL_OK = { kernel_release: '1.0.0', as_at: '2026-09-23', notice: 'Notice.', data: [{ code: 'CONSTRUCTION' }, { code: 'MINING' }] };

const WITH_ALIASES = {
  models: [
    { id: 'grok-fixture-2', created: 200, aliases: ['grok-fixture-2-0923', 'grok-fixture-latest'] },
    { id: 'grok-fixture-3', created: 300, aliases: ['grok-fixture-3-latest'] },
    { id: 'grok-fixture-3-mini', created: 900, aliases: ['grok-fixture-3-mini-latest'] },
    { id: 'grok-fixture-vision', created: 950, aliases: ['grok-fixture-vision-latest'] },
  ],
};
const NO_ALIASES = { data: [{ id: 'grok-fixture-old', created: 100 }, { id: 'grok-fixture-new', created: 300 }, { id: 'grok-fixture-new-fast', created: 999 }] };

function reply(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => { if (body instanceof Error) throw body; return body; },
    text: async () => JSON.stringify(body),
  };
}

// Answers by URL; each entry is a reply, an Error to throw, or a list of them used in turn.
function mockFetch(routes) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url: String(url), init });
    const u = String(url);
    const key = Object.keys(routes).find((k) => u.endsWith(k));
    if (!key) throw new Error(`unexpected call ${u}`);
    let next = routes[key];
    if (Array.isArray(next)) next = next.shift();
    if (next instanceof Error) throw next;
    return next;
  };
  fn.calls = calls;
  return fn;
}

async function folder(t, envText) {
  const dir = await mkdtemp(path.join(tmpdir(), 'grok-setup-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  if (envText !== undefined) await writeFile(path.join(dir, '.env'), envText);
  return dir;
}

async function go(dir, { argv = [], env = ENV, fetchImpl, nodeVersion = '22.0.0' } = {}) {
  let out = '';
  const code = await run({ argv, env, dir, fetchImpl, write: (s) => { out += s; }, nodeVersion });
  assert.ok(!out.includes(XAI_KEY), 'the xAI key was printed');
  assert.ok(!out.includes(KERNEL_KEY), 'the kernel key was printed');
  assert.ok(!out.includes('b'.repeat(16)), 'part of the kernel key was printed');
  assert.ok(!out.includes('SETUP-TEST-key'), 'part of the xAI key was printed');
  return { code, out };
}

async function envFile(dir) {
  try { return await readFile(path.join(dir, '.env'), 'utf8'); } catch { return null; }
}

test('parseEnv reads plain, exported, quoted and commented lines', () => {
  const env = parseEnv('# comment\nexport A=1\nB = "two words"\nC=\'x#y\'\nD=plain # note\n\nnot a line\n');
  assert.deepEqual(env, { A: '1', B: 'two words', C: 'x#y', D: 'plain' });
});

test('withModelLine replaces the first XAI_MODEL, drops duplicates and keeps every other line', () => {
  assert.equal(withModelLine('', 'm1'), 'XAI_MODEL=m1\n');
  assert.equal(withModelLine('A=1\nXAI_MODEL=old\nB=2\nexport XAI_MODEL=older\n', 'm1'), 'A=1\nXAI_MODEL=m1\nB=2\n');
  assert.equal(withModelLine('A=1\r\nB=2', 'm1'), 'A=1\r\nB=2\r\nXAI_MODEL=m1\r\n');
});

test('no key: settings refused, nothing sent, nothing written', async (t) => {
  const dir = await folder(t);
  const f = mockFetch({});
  const { code, out } = await go(dir, { env: { CNC_KERNEL_API_BASE: BASE }, fetchImpl: f });
  assert.equal(code, EXIT.SETTINGS);
  assert.match(out, /2\. Settings: missing XAI_API_KEY, CNC_KERNEL_API_KEY/);
  assert.equal(f.calls.length, 0);
  assert.equal(await envFile(dir), null);
});

test('a malformed kernel key or an http base is refused before any call', async (t) => {
  const dir = await folder(t);
  const f = mockFetch({});
  let r = await go(dir, { env: { ...ENV, CNC_KERNEL_API_KEY: 'cnck_short' }, fetchImpl: f });
  assert.equal(r.code, EXIT.SETTINGS);
  assert.match(r.out, /not a Care Net kernel key/);
  assert.ok(!r.out.includes('cnck_short'), 'the malformed key was echoed');
  r = await go(dir, { env: { ...ENV, CNC_KERNEL_API_BASE: 'http://forge.invalid' }, fetchImpl: f });
  assert.equal(r.code, EXIT.SETTINGS);
  assert.match(r.out, /must use https/);
  assert.equal(f.calls.length, 0);
});

test('Node older than 20 stops at step 1', async (t) => {
  const dir = await folder(t);
  const { code, out } = await go(dir, { nodeVersion: '18.19.0', fetchImpl: mockFetch({}) });
  assert.equal(code, EXIT.NODE);
  assert.match(out, /1\. Node 18\.19\.0: too old/);
});

test('an xAI list with aliases: the latest alias of the flagship family is written', async (t) => {
  const dir = await folder(t);
  const f = mockFetch({ '/api/kernel?r=industries': reply(200, KERNEL_OK), '/language-models': reply(200, WITH_ALIASES) });
  const { code, out } = await go(dir, { fetchImpl: f });
  assert.equal(code, EXIT.OK, out);
  assert.equal(await envFile(dir), 'XAI_MODEL=grok-fixture-3-latest\n');
  assert.match(out, /3\. Kernel API: GET https:\/\/forge\.invalid\/api\/kernel\?r=industries answered 200: ok \(2 industries, kernel release 1\.0\.0\)/);
  assert.match(out, /aliases field present/);
  assert.match(out, /Chosen: grok-fixture-3-latest \(xAI's own alias/);
  assert.equal(f.calls.length, 2, 'no fallback when the first list gives a choice');
  assert.equal(f.calls[0].init.headers.Authorization, `Bearer ${KERNEL_KEY}`);
  assert.equal(f.calls[1].url, `${XAI_BASE}/language-models`);
  assert.equal(f.calls[1].init.headers.Authorization, `Bearer ${XAI_KEY}`);
  if (process.platform !== 'win32') assert.equal((await stat(path.join(dir, '.env'))).mode & 0o777, 0o600, 'a new .env is private');
});

test('a list without aliases: the newest Grok chat model by the bridge rule', async (t) => {
  const dir = await folder(t, '# bot host\nXAI_API_KEY=' + XAI_KEY + '\nXAI_MODEL=auto\nOTHER=kept\n');
  const env = { CNC_KERNEL_API_KEY: KERNEL_KEY, CNC_KERNEL_API_BASE: BASE, XAI_API_BASE: XAI_BASE };
  const f = mockFetch({ '/api/kernel?r=industries': reply(200, KERNEL_OK), '/language-models': reply(200, NO_ALIASES) });
  const { code, out } = await go(dir, { env, fetchImpl: f });
  assert.equal(code, EXIT.OK, out);
  assert.match(out, /XAI_API_KEY found \(\.env\)/);
  assert.match(out, /aliases field absent/);
  assert.match(out, /Chosen: grok-fixture-new \(no latest alias listed/);
  assert.equal(await envFile(dir), `# bot host\nXAI_API_KEY=${XAI_KEY}\nXAI_MODEL=grok-fixture-new\nOTHER=kept\n`,
    'only the XAI_MODEL line changes; the key read from the .env stays where it was');
});

test('language-models not found: falls back to /models', async (t) => {
  const dir = await folder(t);
  const f = mockFetch({ '/api/kernel?r=industries': reply(200, KERNEL_OK), '/language-models': reply(404, {}), '/models': reply(200, NO_ALIASES) });
  const { code, out } = await go(dir, { fetchImpl: f });
  assert.equal(code, EXIT.OK, out);
  assert.match(out, /language-models answered 404/);
  assert.equal(f.calls[2].url, `${XAI_BASE}/models`);
  assert.equal(await envFile(dir), 'XAI_MODEL=grok-fixture-new\n');
});

test('an empty list on both endpoints: exit 4 and nothing written', async (t) => {
  const dir = await folder(t, 'A=1\n');
  const f = mockFetch({ '/api/kernel?r=industries': reply(200, KERNEL_OK), '/language-models': reply(200, { models: [] }), '/models': reply(200, { data: [] }) });
  const { code, out } = await go(dir, { fetchImpl: f });
  assert.equal(code, EXIT.XAI);
  assert.match(out, /0 models listed/);
  assert.match(out, /trying \/models/);
  assert.match(out, /no Grok chat model could be chosen/);
  assert.match(out, /5\. \.env: not written/);
  assert.equal(await envFile(dir), 'A=1\n');
});

test('a bad xAI key (401): exit 4, the status shown, no fallback, nothing written', async (t) => {
  const dir = await folder(t);
  const f = mockFetch({ '/api/kernel?r=industries': reply(200, KERNEL_OK), '/language-models': reply(401, { error: `Incorrect API key ${XAI_KEY}` }) });
  const { code, out } = await go(dir, { fetchImpl: f });
  assert.equal(code, EXIT.XAI);
  assert.match(out, /answered 401: xAI refused the key/);
  assert.equal(f.calls.length, 2);
  assert.equal(await envFile(dir), null);
});

test('xAI not reachable: exit 4', async (t) => {
  const dir = await folder(t);
  const f = mockFetch({ '/api/kernel?r=industries': reply(200, KERNEL_OK), '/language-models': new TypeError(`fetch failed for ${XAI_KEY}`) });
  const { code, out } = await go(dir, { fetchImpl: f });
  assert.equal(code, EXIT.XAI);
  assert.match(out, /4\. xAI: GET https:\/\/xai\.invalid\/v1\/language-models failed: the host could not be reached/);
});

test('the kernel refuses the key or cannot be reached: exit 3, xAI still reported, nothing written', async (t) => {
  const dir = await folder(t);
  let f = mockFetch({ '/api/kernel?r=industries': reply(401, { error: `bad ${KERNEL_KEY}` }), '/language-models': reply(200, NO_ALIASES) });
  let r = await go(dir, { fetchImpl: f });
  assert.equal(r.code, EXIT.KERNEL);
  assert.match(r.out, /answered 401: the kernel key was refused/);
  assert.match(r.out, /Chosen: grok-fixture-new/);
  f = mockFetch({ '/api/kernel?r=industries': new TypeError('fetch failed'), '/language-models': new TypeError('fetch failed') });
  r = await go(dir, { fetchImpl: f });
  assert.equal(r.code, EXIT.KERNEL, 'the first failure decides the exit code');
  assert.match(r.out, /3\. Kernel API: .* failed: the host could not be reached/);
  assert.equal(await envFile(dir), null);
});

test('--check writes nothing; --auto writes auto; the folder holds nothing else afterwards', async (t) => {
  const dir = await folder(t, 'XAI_MODEL=something\n');
  const routes = () => ({ '/api/kernel?r=industries': reply(200, KERNEL_OK), '/language-models': reply(200, WITH_ALIASES) });
  let r = await go(dir, { argv: ['--check'], fetchImpl: mockFetch(routes()) });
  assert.equal(r.code, EXIT.OK, r.out);
  assert.match(r.out, /--check, nothing written\. Without --check this would set XAI_MODEL=grok-fixture-3-latest/);
  assert.equal(await envFile(dir), 'XAI_MODEL=something\n');
  r = await go(dir, { argv: ['--auto'], fetchImpl: mockFetch(routes()) });
  assert.equal(r.code, EXIT.OK, r.out);
  assert.equal(await envFile(dir), 'XAI_MODEL=auto\n');
  r = await go(dir, { argv: ['--auto'], fetchImpl: mockFetch(routes()) });
  assert.match(r.out, /already set .*; unchanged/);
  assert.deepEqual(await readdir(dir), ['.env'], 'nothing but the .env is ever written');
  r = await go(dir, { argv: ['--check', '--auto'], fetchImpl: mockFetch({}) });
  assert.equal(r.code, EXIT.SETTINGS);
  r = await go(dir, { argv: [XAI_KEY], fetchImpl: mockFetch({}) });
  assert.equal(r.code, EXIT.SETTINGS, 'an unknown option is refused without being echoed');
});

test('the environment wins over the .env, and a clash on XAI_MODEL is pointed out', async (t) => {
  const dir = await folder(t, `CNC_KERNEL_API_BASE=https://stale.invalid\nXAI_MODEL=auto\n`);
  const f = mockFetch({ '/api/kernel?r=industries': reply(200, KERNEL_OK), '/language-models': reply(200, NO_ALIASES) });
  const { code, out } = await go(dir, { env: { ...ENV, XAI_MODEL: 'auto' }, fetchImpl: f });
  assert.equal(code, EXIT.OK, out);
  assert.equal(f.calls[0].url, `${BASE}/api/kernel?r=industries`);
  assert.match(out, /XAI_MODEL is also set in the environment as auto/);
});

test('run as a real process: exit codes and captured stdout and stderr carry no key', async () => {
  const { spawnSync } = await import('node:child_process');
  const script = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../../grok/setup.mjs');
  const envFileBefore = await envFile(path.dirname(script));
  // Nothing listens on port 9 of this host, so both checks fail fast and nothing is written.
  const env = { XAI_API_KEY: XAI_KEY, CNC_KERNEL_API_KEY: KERNEL_KEY, CNC_KERNEL_API_BASE: 'http://127.0.0.1:9', XAI_API_BASE: 'http://127.0.0.1:9/v1' };
  const p = spawnSync(process.execPath, [script, '--check'], { env, encoding: 'utf8', timeout: 60000 });
  const all = `${p.stdout}${p.stderr}`;
  assert.equal(p.status, EXIT.KERNEL, all);
  assert.match(p.stdout, /^Care Net Grok kernel bot setup \(check only/);
  assert.match(p.stdout, /4\. xAI: GET http:\/\/127\.0\.0\.1:9\/v1\/language-models failed/);
  for (const secret of [XAI_KEY, KERNEL_KEY, 'b'.repeat(16), 'SETUP-TEST-key']) assert.ok(!all.includes(secret), 'a key reached the output');
  const q = spawnSync(process.execPath, [script], { env: { XAI_API_KEY: XAI_KEY }, encoding: 'utf8', timeout: 60000 });
  assert.equal(q.status, EXIT.SETTINGS);
  assert.ok(!`${q.stdout}${q.stderr}`.includes(XAI_KEY));
  assert.equal(await envFile(path.dirname(script)), envFileBefore, 'grok/.env is untouched');
});
