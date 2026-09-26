#!/usr/bin/env node
// CNC HSF FORGE | KRN-GROK-03 v1.0.0 | Setup check for the Grok kernel bot host
// Version 1.0 | 23/09/2026 | For Odendaal. Dependency free: Node 20 or later, no npm packages.
// Contract: hsf/BUILD-CONTRACT.md 11.6. How to run it: KERNEL-API.md section 8.6.
//
//   node grok/setup.mjs            check everything, then write XAI_MODEL=<chosen id> into grok/.env
//   node grok/setup.mjs --auto     check everything, then write XAI_MODEL=auto (the bridge chooses daily)
//   node grok/setup.mjs --check    check everything, write nothing
//
// Steps, printed with numbers:
//   1. Node version (20 or later; 20.6 or later to load the .env with --env-file).
//   2. Settings: XAI_API_KEY, CNC_KERNEL_API_KEY and CNC_KERNEL_API_BASE from the
//      environment, or else from the .env beside this file (the environment wins,
//      as it does with node --env-file). XAI_API_BASE is optional, as in the bridge.
//   3. The Care Net kernel API: GET <CNC_KERNEL_API_BASE>/api/kernel?r=industries.
//   4. The xAI model list: GET <XAI_API_BASE>/language-models, falling back to
//      /models when that gives no usable choice. An official alias ending in
//      "latest" for the flagship Grok family is preferred when the list carries
//      aliases; otherwise the bridge's newest rule (grok/model-pick.mjs). What
//      was found is printed, so the list's real shape can be confirmed on the
//      first run (the alias field and the endpoint's shape are assumptions).
//   5. The .env beside this file: XAI_MODEL written or updated, every other line
//      kept as it was. Nothing is written unless steps 1 to 4 all passed.
//
// Exit codes: 0 all passed; 1 a setting is missing or malformed (or a bad
// option); 2 Node too old; 3 the kernel API check failed; 4 the xAI check
// failed (key refused, not reachable, no Grok chat model); 5 the .env could not
// be written.
//
// Never printed or logged: either key. Replies are reported by status only; no
// response body is echoed, and every line passes through a redaction of both
// keys before it is written. The only file this script ever writes is the .env
// beside it.

import { readFile, writeFile, stat } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { pickModel, modelRows, listHasAliases, isGrokChatId, MODEL_ID_RE } from './model-pick.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

export const EXIT = Object.freeze({ OK: 0, SETTINGS: 1, NODE: 2, KERNEL: 3, XAI: 4, WRITE: 5 });

const MIN_NODE_MAJOR = 20;
const XAI_DEFAULT_BASE = 'https://api.x.ai/v1';
const TIMEOUT_MS = 20000;
const KEY_RE = /^cnck_[0-9a-f]{64}$/;
const NAMES = ['XAI_API_KEY', 'CNC_KERNEL_API_KEY', 'CNC_KERNEL_API_BASE'];
const SHOW_IDS = 20; // ids listed on screen from the model list, at most

const USAGE = 'Usage: node grok/setup.mjs [--check | --auto]\n' +
  '  (no option)  check, then write XAI_MODEL=<chosen id> into grok/.env\n' +
  '  --auto       check, then write XAI_MODEL=auto so the bridge chooses the model once a day\n' +
  '  --check      check only, write nothing\n';

// 1. The .env file -------------------------------------------------------------

// KEY=VALUE lines; blank lines, # comments and an optional "export " prefix are
// allowed; a value may sit in single or double quotes.
export function parseEnv(text) {
  const out = {};
  for (const line of String(text).split(/\r?\n/)) {
    const m = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!m || line.trim().startsWith('#')) continue;
    let v = m[2];
    if (v.length >= 2 && ((v[0] === '"' && v.endsWith('"')) || (v[0] === "'" && v.endsWith("'")))) v = v.slice(1, -1);
    else v = v.replace(/\s+#.*$/, '');
    out[m[1]] = v;
  }
  return out;
}

// The file with XAI_MODEL set to value: the existing line replaced in place (the
// first one; later duplicates removed), or a line added at the end. Every other
// line is kept byte for byte.
export function withModelLine(text, value) {
  const src = String(text || '');
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  const lines = src === '' ? [] : src.split(/\r?\n/);
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  const re = /^\s*(?:export\s+)?XAI_MODEL\s*=/;
  const out = [];
  let done = false;
  for (const line of lines) {
    if (!re.test(line)) { out.push(line); continue; }
    if (!done) { out.push(`XAI_MODEL=${value}`); done = true; }
  }
  if (!done) out.push(`XAI_MODEL=${value}`);
  return out.join(eol) + eol;
}

// 2. Small helpers -------------------------------------------------------------

function isLocalHost(hostname) {
  return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '[::1]' || hostname === '::1';
}

// The same rule as the bridge: https only (http for localhost), no credentials,
// query or fragment. Returns {url} or {problem}.
function baseUrl(raw, label) {
  let u;
  try { u = new URL(String(raw).trim()); } catch { return { problem: `${label} is not a valid URL.` }; }
  if (u.protocol !== 'https:' && !(u.protocol === 'http:' && isLocalHost(u.hostname))) {
    return { problem: `${label} must use https (http is allowed for localhost only).` };
  }
  if (u.username || u.password || u.search || u.hash) {
    return { problem: `${label} must not carry credentials, a query or a fragment.` };
  }
  return { url: u.origin + u.pathname.replace(/\/+$/, '') };
}

function nodeMajorMinor(version) {
  const m = /^v?(\d+)\.(\d+)/.exec(String(version || ''));
  return m ? { major: Number(m[1]), minor: Number(m[2]) } : { major: 0, minor: 0 };
}

async function getJson(doFetch, url, key) {
  const res = await doFetch(url, {
    method: 'GET',
    headers: { Authorization: `Bearer ${key}`, Accept: 'application/json' },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  let body = null;
  if (res.ok) { try { body = await res.json(); } catch { body = null; } }
  return { status: res.status, ok: res.ok, body };
}

function reachReason(err) {
  return err && err.name === 'TimeoutError' ? `no answer within ${TIMEOUT_MS / 1000} seconds` : 'the host could not be reached';
}

const KERNEL_STATUS = {
  400: 'the request was refused as malformed; check that CNC_KERNEL_API_BASE is the Forge origin',
  401: 'the kernel key was refused (wrong, revoked or never issued)',
  403: 'the kernel key does not carry the kernel.read scope',
  404: 'nothing answers at /api/kernel on this host; check CNC_KERNEL_API_BASE',
  429: 'the hourly call limit for this key has been reached; try again later',
  500: 'the kernel API failed on the server; tell the Forge admin',
  503: 'the kernel API is not configured on the server; tell the Forge admin',
};

const XAI_STATUS = {
  400: 'xAI refused the request as malformed; the xAI key may be malformed',
  401: 'xAI refused the key (wrong or revoked); create a new key in the xAI console',
  403: 'xAI refused this key access to the model list; check the key\'s permissions in the xAI console',
  429: 'xAI rate limited the request; try again later',
};

// 3. The run ------------------------------------------------------------------

export async function run({
  argv = process.argv.slice(2),
  env = process.env,
  dir = HERE,
  fetchImpl,
  write = (s) => process.stdout.write(s),
  nodeVersion = process.versions.node,
} = {}) {
  const doFetch = fetchImpl || ((url, init) => fetch(url, init));
  const secrets = [];
  const say = (line = '') => {
    let s = String(line);
    for (const k of secrets) if (k && k.length >= 4) s = s.split(k).join('[redacted]');
    write(`${s.replace(/cnck_[0-9a-f]{8,}/g, 'cnck_[redacted]')}\n`);
  };

  // Options
  const flags = new Set();
  for (const a of argv) {
    if (a === '--check' || a === '--auto' || a === '--help' || a === '-h') flags.add(a);
    else { write(`Unknown option (not repeated here, in case it was a key).\n${USAGE}`); return EXIT.SETTINGS; }
  }
  if (flags.has('--help') || flags.has('-h')) { write(USAGE); return EXIT.OK; }
  if (flags.has('--check') && flags.has('--auto')) { write(`Choose --check or --auto, not both.\n${USAGE}`); return EXIT.SETTINGS; }
  const checkOnly = flags.has('--check');
  const autoMode = flags.has('--auto');
  const envPath = path.join(dir, '.env');

  say(`Care Net Grok kernel bot setup (${checkOnly ? 'check only: nothing will be written' : `will write XAI_MODEL into ${envPath} if every check passes`})`);

  // Step 1: Node
  const v = nodeMajorMinor(nodeVersion);
  if (v.major < MIN_NODE_MAJOR) {
    say(`1. Node ${nodeVersion}: too old. Install Node ${MIN_NODE_MAJOR} or later and run this again.`);
    return EXIT.NODE;
  }
  const envFileOk = v.major > 20 || (v.major === 20 && v.minor >= 6);
  say(`1. Node ${nodeVersion}: ok${envFileOk ? '' : ' (node --env-file needs 20.6 or later; set the variables in the environment instead)'}`);

  // Step 2: settings
  let fileText = null;
  try {
    fileText = await readFile(envPath, 'utf8');
  } catch (err) {
    if (!err || err.code !== 'ENOENT') {
      say(`2. Settings: ${envPath} exists but could not be read (${err && err.code ? err.code : 'error'}).`);
      return EXIT.SETTINGS;
    }
  }
  const fromFile = fileText === null ? {} : parseEnv(fileText);
  const cfg = {};
  const where = {};
  for (const name of [...NAMES, 'XAI_API_BASE', 'XAI_MODEL']) {
    const e = env[name] !== undefined && String(env[name]).trim() ? String(env[name]).trim() : '';
    const f = fromFile[name] !== undefined && String(fromFile[name]).trim() ? String(fromFile[name]).trim() : '';
    cfg[name] = e || f;
    where[name] = e ? 'environment' : (f ? '.env' : null);
  }
  secrets.push(cfg.XAI_API_KEY, cfg.CNC_KERNEL_API_KEY);

  const problems = [];
  const missing = NAMES.filter((n) => !cfg[n]);
  if (missing.length) problems.push(`missing ${missing.join(', ')} (set in the environment or in ${envPath})`);
  if (cfg.CNC_KERNEL_API_KEY && !KEY_RE.test(cfg.CNC_KERNEL_API_KEY)) {
    problems.push('CNC_KERNEL_API_KEY is not a Care Net kernel key (cnck_ followed by 64 lowercase hex characters)');
  }
  if (cfg.XAI_API_KEY && /\s/.test(cfg.XAI_API_KEY)) problems.push('XAI_API_KEY contains a space or line break');
  const kernel = cfg.CNC_KERNEL_API_BASE ? baseUrl(cfg.CNC_KERNEL_API_BASE, 'CNC_KERNEL_API_BASE') : {};
  const xai = baseUrl(cfg.XAI_API_BASE || XAI_DEFAULT_BASE, 'XAI_API_BASE');
  if (kernel.problem) problems.push(kernel.problem.replace(/\.$/, ''));
  if (xai.problem) problems.push(xai.problem.replace(/\.$/, ''));
  if (problems.length) {
    say(`2. Settings: ${problems.join('; ')}.`);
    say('   Nothing was sent anywhere and nothing was written.');
    return EXIT.SETTINGS;
  }
  say(`2. Settings: XAI_API_KEY found (${where.XAI_API_KEY}); CNC_KERNEL_API_KEY found (${where.CNC_KERNEL_API_KEY}); ` +
    `CNC_KERNEL_API_BASE ${kernel.url} (${where.CNC_KERNEL_API_BASE}); xAI API ${xai.url}`);

  let failed = null;

  // Step 3: the kernel API
  const kernelUrl = `${kernel.url}/api/kernel?r=industries`;
  try {
    const r = await getJson(doFetch, kernelUrl, cfg.CNC_KERNEL_API_KEY);
    if (r.ok) {
      const b = r.body && typeof r.body === 'object' ? r.body : {};
      const n = Array.isArray(b.data) ? b.data.length : null;
      const release = typeof b.kernel_release === 'string' && /^[\w.\-]{1,32}$/.test(b.kernel_release) ? b.kernel_release : 'not stated';
      if (n === null) {
        say(`3. Kernel API: GET ${kernelUrl} answered ${r.status} but not with the kernel's reply shape (no data list). Check CNC_KERNEL_API_BASE.`);
        failed = failed || EXIT.KERNEL;
      } else {
        say(`3. Kernel API: GET ${kernelUrl} answered ${r.status}: ok (${n} industries, kernel release ${release})`);
      }
    } else {
      say(`3. Kernel API: GET ${kernelUrl} answered ${r.status}: ${KERNEL_STATUS[r.status] || 'unexpected status'}.`);
      failed = failed || EXIT.KERNEL;
    }
  } catch (err) {
    say(`3. Kernel API: GET ${kernelUrl} failed: ${reachReason(err)}.`);
    failed = failed || EXIT.KERNEL;
  }

  // Step 4: the xAI model list
  let chosen = { id: null, how: null };
  let xaiFailed = false;
  for (const endpoint of ['language-models', 'models']) {
    const url = `${xai.url}/${endpoint}`;
    let r;
    try {
      r = await getJson(doFetch, url, cfg.XAI_API_KEY);
    } catch (err) {
      say(`4. xAI: GET ${url} failed: ${reachReason(err)}.`);
      xaiFailed = true;
      break;
    }
    if (!r.ok) {
      const plain = XAI_STATUS[r.status];
      say(`4. xAI: GET ${url} answered ${r.status}${plain ? `: ${plain}` : ''}.`);
      if (plain) { xaiFailed = true; break; }
      continue; // 404 and the like: try the other list
    }
    const rows = modelRows(r.body);
    const ids = rows.map((row) => (row && typeof row.id === 'string' ? row.id.trim() : '')).filter(Boolean);
    const grok = ids.filter(isGrokChatId);
    const hasAliases = listHasAliases(r.body);
    const aliases = hasAliases ? rows.flatMap((row) => (row && Array.isArray(row.aliases) ? row.aliases.filter((a) => typeof a === 'string') : [])) : [];
    const list = (a) => (a.length ? a.slice(0, SHOW_IDS).join(', ') + (a.length > SHOW_IDS ? `, and ${a.length - SHOW_IDS} more` : '') : 'none');
    say(`4. xAI: GET ${url} answered ${r.status}: ${rows.length} ${rows.length === 1 ? 'model' : 'models'} listed; ` +
      `aliases field ${hasAliases ? 'present' : 'absent'}; Grok chat models after the filter: ${list(grok)}`);
    if (hasAliases) say(`   Aliases listed: ${list(aliases)}`);
    if (!rows.length && r.body && !Array.isArray(r.body)) {
      say(`   The reply had no "models" or "data" list; its top level fields were: ${list(Object.keys(r.body).filter((k) => /^[\w-]{1,40}$/.test(k)))}`);
    }
    chosen = pickModel(r.body);
    if (chosen.id) break;
    say(`   No usable Grok chat model in this list${endpoint === 'language-models' ? '; trying /models' : ''}.`);
  }
  if (!xaiFailed && chosen.id) {
    say(chosen.how === 'alias'
      ? `   Chosen: ${chosen.id} (xAI's own alias ending in "latest", so xAI decides what latest means)`
      : `   Chosen: ${chosen.id} (no latest alias listed; the newest Grok chat model by the bridge's rule)`);
  } else if (!xaiFailed) {
    say('4. xAI: no Grok chat model could be chosen from either list. Check the xAI account and read what the lists returned above.');
  }
  if (xaiFailed || !chosen.id) failed = failed || EXIT.XAI;

  // Step 5: the .env file
  const value = autoMode ? 'auto' : chosen.id;
  if (failed) {
    say(`5. .env: not written, because a check above failed. Fix it and run this again. Exit code ${failed}.`);
    return failed;
  }
  if (where.XAI_MODEL === 'environment' && cfg.XAI_MODEL !== value) {
    say(`   Note: XAI_MODEL is also set in the environment as ${MODEL_ID_RE.test(cfg.XAI_MODEL) ? cfg.XAI_MODEL : 'an unusual value'}; the environment wins over the .env, so unset it there.`);
  }
  if (checkOnly) {
    say(`5. .env: --check, nothing written. Without --check this would set XAI_MODEL=${value}.`);
    say('All checks passed.');
    return EXIT.OK;
  }
  if (!MODEL_ID_RE.test(value)) {
    say('5. .env: the chosen id is not a plain model id, so it was not written.');
    return EXIT.WRITE;
  }
  const next = withModelLine(fileText, value);
  if (fileText !== null && next === fileText) {
    say(`5. .env: XAI_MODEL=${value} already set in ${envPath}; unchanged.`);
  } else {
    try {
      await writeFile(envPath, next, fileText === null ? { encoding: 'utf8', mode: 0o600, flag: 'wx' } : { encoding: 'utf8' });
    } catch (err) {
      say(`5. .env: ${envPath} could not be written (${err && err.code ? err.code : 'error'}).`);
      return EXIT.WRITE;
    }
    say(`5. .env: XAI_MODEL=${value} ${fileText === null ? 'written to a new' : 'updated in'} ${envPath}${autoMode ? ' (the bridge chooses the latest model itself, once a day)' : ''}`);
  }
  try {
    const st = await stat(envPath);
    if (process.platform !== 'win32' && (st.mode & 0o077)) {
      say(`   Warning: ${envPath} can be read by other users of this host; run chmod 600 on it.`);
    }
  } catch { /* the write above succeeded; a failed stat is not worth failing the run */ }
  say(`All checks passed. Start the bridge with: node --env-file=${path.relative(process.cwd(), envPath) || '.env'} ${path.relative(process.cwd(), path.join(dir, 'bridge-example.mjs'))} "your question"`);
  return EXIT.OK;
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (invokedDirectly) {
  run().then((code) => { process.exitCode = code; }, () => {
    process.stdout.write('setup: stopped by an unexpected error; nothing further was written.\n');
    process.exitCode = 1;
  });
}
