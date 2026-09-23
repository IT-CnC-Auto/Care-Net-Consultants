#!/usr/bin/env node
// CNC HSF FORGE | KRN-GROK-01 v1.0.0 | Example bridge: a Grok bot answering from the Care Net Cognitive Kernel
// Version 1.0 | 23/09/2026 | For Odendaal. Dependency free: Node 18 or later (global fetch), no npm packages.
//
// What it does, for one question:
//   1. Refuses, before anything leaves the host, a question that carries
//      personal information (identity number, email address, telephone number).
//   2. Sends the question to the xAI chat completions API with the system prompt
//      from grok/system-prompt.md and the six function tools from
//      grok/kernel-tools.json, tool_choice auto.
//   3. Runs every tool call Grok asks for against the Care Net kernel API
//      (GET <CNC_KERNEL_API_BASE>/api/kernel?r=...) with the Care Net key, and
//      returns each result to Grok as a role "tool" message.
//   4. Repeats until Grok answers in text (at most MAX_ROUNDS rounds), then
//      appends the kernel notice to the answer, word for word.
//
// Environment (set as secrets in the bot host; never in this file, never in chat):
//   XAI_API_KEY          xAI API key.
//   XAI_MODEL            The Grok model to use. Read from here only: this file
//                        never names a model.
//   CNC_KERNEL_API_KEY   Care Net kernel key, cnck_ followed by 64 hex characters,
//                        issued once by a forge_admin (KERNEL-API.md section 4).
//   CNC_KERNEL_API_BASE  The origin that serves /api/kernel, for example
//                        https://<forge host>. https only (http allowed for
//                        localhost testing).
//   XAI_API_BASE         Optional. Defaults to https://api.x.ai/v1.
//
// Run:     node grok/bridge-example.mjs "Which instruments apply to construction?"
//          echo "What does the kernel hold on noise?" | node grok/bridge-example.mjs
// Import:  import { answer } from './bridge-example.mjs';
//          const { text } = await answer('Which File elements cover scaffolding?');
//
// Never logged: keys, the question, tool arguments or answers. Errors printed to
// stderr carry a status and a short reason with any key redacted.
//
// What the kernel API returns (KERNEL-API.md section 2, vercel/kernel-api/openapi.yaml):
// every 200 body is {kernel_release, as_at, notice, data}, passed to Grok as it
// comes. An unknown industry code answers 404, a malformed argument 400, a bad
// or revoked key 401, the hourly limit 429; the bridge hands Grok a short plain
// reason for each. File elements carry an empty citable list until the Phase 2
// re verification (contract 9.3), so their instruments show under awaiting.
// The unfiltered element list is longer than MAX_TOOL_RESULT_CHARS and is cut
// with a note asking for an industry filter.
//
// The xAI API details this relies on (OpenAI compatible chat completions at
// https://api.x.ai/v1/chat/completions, Bearer key, tools of type "function",
// tool_calls in the reply, tool results sent back with role "tool" and
// tool_call_id) were read from search engine extracts of the xAI documentation
// on 23/09/2026; docs.x.ai itself could not be opened from the build
// environment (KERNEL-API.md section 7). xAI describes chat completions as a
// legacy endpoint and adds new features to its Responses API first. Read the
// xAI documentation directly and recheck these details before go live.

import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const HERE = path.dirname(fileURLToPath(import.meta.url));

export const NOTICE =
  'Framework reference data from the Care Net Cognitive Kernel. Not legal advice and not a clinical opinion. ' +
  'Only instruments that have passed three verification checks and are in force are included.';

export const ESCALATION = 'Please WhatsApp a sales executive on 27 60 070 2723 (https://wa.me/27600702723).';

const XAI_DEFAULT_BASE = 'https://api.x.ai/v1';
const MAX_ROUNDS = 6;                  // model turns before the bridge gives up
const MAX_TOOL_CALLS_PER_ROUND = 8;    // tool calls honoured in one turn
const MAX_TOOL_RESULT_CHARS = 60000;   // a larger kernel result is cut down before Grok sees it
const MAX_QUESTION_CHARS = 2000;
const XAI_TIMEOUT_MS = 120000;
const KERNEL_TIMEOUT_MS = 20000;

const KEY_RE = /^cnck_[0-9a-f]{64}$/;
const CODE_RE = /^[A-Za-z][A-Za-z0-9_]{0,31}(?:-[A-Za-z0-9_]{1,31}){0,4}$/;
const SEARCH_RE = /^[\p{L}\p{N} .,'()&/-]{2,100}$/u;

// Tool name -> kernel resource and the arguments it may carry.
export const TOOL_ROUTES = Object.freeze({
  kernel_industries: { r: 'industries', params: {} },
  kernel_industry: { r: 'industry', params: { code: { required: true, re: CODE_RE } } },
  kernel_instruments: { r: 'instruments', params: { industry: { required: false, re: CODE_RE } } },
  kernel_protocols: { r: 'protocols', params: { industry: { required: false, re: CODE_RE } } },
  kernel_elements: { r: 'elements', params: { industry: { required: false, re: CODE_RE } } },
  kernel_search: { r: 'search', params: { q: { required: true, re: SEARCH_RE } } },
});

// 1. Configuration ------------------------------------------------------------

function isLocalHost(hostname) {
  return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '[::1]' || hostname === '::1';
}

function baseUrl(raw, label) {
  let u;
  try { u = new URL(String(raw).trim()); } catch { throw new Error(`${label} is not a valid URL.`); }
  if (u.protocol !== 'https:' && !(u.protocol === 'http:' && isLocalHost(u.hostname))) {
    throw new Error(`${label} must use https (http is allowed for localhost only).`);
  }
  if (u.username || u.password || u.search || u.hash) {
    throw new Error(`${label} must not carry credentials, a query or a fragment.`);
  }
  return u.origin + u.pathname.replace(/\/+$/, '');
}

export function readConfig(env = process.env) {
  const need = ['XAI_API_KEY', 'XAI_MODEL', 'CNC_KERNEL_API_KEY', 'CNC_KERNEL_API_BASE'];
  const missing = need.filter((k) => !env[k] || !String(env[k]).trim());
  if (missing.length) {
    throw new Error(`Missing environment variables: ${missing.join(', ')}. Set them as secrets in the bot host.`);
  }
  const kernelKey = String(env.CNC_KERNEL_API_KEY).trim();
  if (!KEY_RE.test(kernelKey)) {
    throw new Error('CNC_KERNEL_API_KEY is not a Care Net kernel key (cnck_ followed by 64 lowercase hex characters).');
  }
  return Object.freeze({
    xaiKey: String(env.XAI_API_KEY).trim(),
    model: String(env.XAI_MODEL).trim(),
    kernelKey,
    kernelBase: baseUrl(env.CNC_KERNEL_API_BASE, 'CNC_KERNEL_API_BASE'),
    xaiBase: baseUrl(env.XAI_API_BASE || XAI_DEFAULT_BASE, 'XAI_API_BASE'),
  });
}

// Replaces any configured secret in a message before it is shown or logged.
function redact(text, cfg) {
  let s = String(text === undefined || text === null ? '' : text).slice(0, 400);
  for (const secret of [cfg && cfg.xaiKey, cfg && cfg.kernelKey]) {
    if (secret && secret.length >= 8) s = s.split(secret).join('[redacted]');
  }
  return s.replace(/cnck_[0-9a-f]{8,}/g, 'cnck_[redacted]');
}

// 2. Prompt and tools, read from the files beside this one ---------------------

export async function loadSystemPrompt(file = path.join(HERE, 'system-prompt.md')) {
  const md = await readFile(file, 'utf8');
  const m = /<!-- BEGIN SYSTEM PROMPT -->\s*([\s\S]*?)\s*<!-- END SYSTEM PROMPT -->/.exec(md);
  if (!m || !m[1].trim()) throw new Error('system-prompt.md has no text between the BEGIN and END SYSTEM PROMPT markers.');
  return m[1].trim();
}

export async function loadTools(file = path.join(HERE, 'kernel-tools.json')) {
  const tools = JSON.parse(await readFile(file, 'utf8'));
  if (!Array.isArray(tools) || tools.length === 0) throw new Error('kernel-tools.json must be a non empty array.');
  for (const t of tools) {
    const name = t && t.type === 'function' && t.function && t.function.name;
    if (!name || !Object.prototype.hasOwnProperty.call(TOOL_ROUTES, name)) {
      throw new Error(`kernel-tools.json holds a tool this bridge cannot run: ${String(name)}.`);
    }
  }
  return tools;
}

// 3. Personal information screen (runs before anything is sent to xAI) ---------

const PERSONAL_CHECKS = [
  { what: 'an identity number', test: (q) => /\d{13}/.test(q.replace(/[\s.]/g, '')) },
  { what: 'an email address', test: (q) => /[^\s@]+@[^\s@]+\.[^\s@]+/.test(q) },
  { what: 'a telephone number', test: (q) => /(?:\+?27|\b0)[\s.()]*\d{2}[\s.()]*\d{3}[\s.]*\d{4}\b/.test(q) },
];

export function personalInformationIn(question) {
  return PERSONAL_CHECKS.filter((c) => c.test(question)).map((c) => c.what);
}

// 4. The kernel API -----------------------------------------------------------

async function fetchWithTimeout(url, init, ms) {
  return fetch(url, Object.assign({}, init, { signal: AbortSignal.timeout(ms) }));
}

function toolError(status, message) {
  return { ok: false, status, body: { error: message, code: 'bridge_refused' } };
}

// Runs one tool call. Returns { ok, status, body } and never throws for a bad
// argument or a refused call, so Grok can be told what went wrong.
export async function callKernel(cfg, name, rawArguments) {
  const route = Object.prototype.hasOwnProperty.call(TOOL_ROUTES, name) ? TOOL_ROUTES[name] : null;
  if (!route) return toolError(400, `Unknown tool ${String(name).slice(0, 40)}.`);

  let args = {};
  if (rawArguments !== undefined && rawArguments !== null && rawArguments !== '') {
    try { args = typeof rawArguments === 'string' ? JSON.parse(rawArguments) : rawArguments; } catch {
      return toolError(400, 'The tool arguments were not valid JSON.');
    }
  }
  if (!args || typeof args !== 'object' || Array.isArray(args)) return toolError(400, 'The tool arguments must be an object.');

  const url = new URL(`${cfg.kernelBase}/api/kernel`);
  url.searchParams.set('r', route.r);
  for (const [param, rule] of Object.entries(route.params)) {
    let v = args[param];
    if (v === undefined || v === null || (typeof v === 'string' && !v.trim())) {
      if (rule.required) return toolError(400, `The ${param} argument is required.`);
      continue;
    }
    if (typeof v !== 'string') return toolError(400, `The ${param} argument must be text.`);
    v = v.replace(/\s+/g, ' ').trim();
    if (!rule.re.test(v)) return toolError(400, `The ${param} argument is not in the accepted form.`);
    if (param === 'q' && personalInformationIn(v).length) return toolError(400, 'Search text must not carry personal information.');
    url.searchParams.set(param, v);
  }

  let res;
  try {
    res = await fetchWithTimeout(url, {
      method: 'GET',
      headers: { Authorization: `Bearer ${cfg.kernelKey}`, Accept: 'application/json' },
    }, KERNEL_TIMEOUT_MS);
  } catch (err) {
    return toolError(503, 'The Care Net kernel could not be reached.');
  }
  let body = null;
  try { body = await res.json(); } catch { body = null; }
  if (!res.ok) {
    const plain = {
      401: 'The Care Net kernel refused the bot key. Tell the person the kernel is unavailable at the moment.',
      403: 'The bot key does not carry the kernel.read scope. Tell the person the kernel is unavailable at the moment.',
      429: 'The hourly call limit for this bot has been reached. Tell the person to try again later.',
    }[res.status];
    const reason = plain || (body && typeof body.error === 'string' ? body.error : 'The kernel call failed.');
    return { ok: false, status: res.status, body: { error: redact(reason, cfg), code: body && body.code ? String(body.code) : 'kernel_error' } };
  }
  return { ok: true, status: res.status, body };
}

// What Grok sees for a tool result: the JSON, cut down if it is too large.
function toolContent(result) {
  const payload = result.ok ? result.body : { status: result.status, error: result.body.error, code: result.body.code };
  const text = JSON.stringify(payload);
  if (text.length <= MAX_TOOL_RESULT_CHARS) return text;
  const b = result.body || {};
  return JSON.stringify({
    truncated: true,
    note: 'The result was too large and has been cut. Ask a narrower question or filter by industry.',
    kernel_release: b.kernel_release ?? null,
    as_at: b.as_at ?? null,
    notice: b.notice ?? NOTICE,
    partial: text.slice(0, MAX_TOOL_RESULT_CHARS - 1000),
  });
}

// 5. The xAI chat completions API ---------------------------------------------

async function chat(cfg, messages, tools) {
  let res;
  try {
    res = await fetchWithTimeout(`${cfg.xaiBase}/chat/completions`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${cfg.xaiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: cfg.model, messages, tools, tool_choice: 'auto' }),
    }, XAI_TIMEOUT_MS);
  } catch (err) {
    throw new Error(`The xAI API could not be reached: ${redact(err && err.message, cfg)}`);
  }
  const text = await res.text();
  if (!res.ok) throw new Error(`The xAI API answered ${res.status}: ${redact(text, cfg)}`);
  let body;
  try { body = JSON.parse(text); } catch { throw new Error('The xAI API did not return JSON.'); }
  const message = body && Array.isArray(body.choices) && body.choices[0] && body.choices[0].message;
  if (!message || typeof message !== 'object') throw new Error('The xAI API returned no message.');
  return message;
}

// 6. Answer text: house style and the notice ----------------------------------

function tidy(text) {
  return String(text || '')
    .replace(/\s*[\u2014\u2013]\s*/g, ', ') // no em or en dashes in anything Care Net shows
    .replace(/[ \t]+\n/g, '\n')
    .trim();
}

function withNotice(text, notice) {
  const body = tidy(text).split(notice).join('').trim();
  return `${body}\n\n${notice}`;
}

// 7. One question, end to end --------------------------------------------------

export async function answer(question, options = {}) {
  const cfg = options.config || readConfig(options.env || process.env);
  const q = String(question === undefined || question === null ? '' : question).trim();

  if (!q) return { text: withNotice('Please ask a question about the Care Net kernel.', NOTICE), toolCalls: [], refused: true };
  if (q.length > MAX_QUESTION_CHARS) {
    return { text: withNotice(`Please keep the question under ${MAX_QUESTION_CHARS} characters.`, NOTICE), toolCalls: [], refused: true };
  }
  const found = personalInformationIn(q);
  if (found.length) {
    return {
      text: withNotice(
        `Your question seems to contain personal information (${found.join(', ')}). This assistant works only with framework reference data, so nothing has been sent. Please remove it and ask again. For anything about a specific person or company: ${ESCALATION}`,
        NOTICE,
      ),
      toolCalls: [],
      refused: true,
    };
  }

  const [systemPrompt, tools] = await Promise.all([
    options.systemPrompt ? Promise.resolve(options.systemPrompt) : loadSystemPrompt(),
    options.tools ? Promise.resolve(options.tools) : loadTools(),
  ]);

  const messages = [
    { role: 'system', content: systemPrompt },
    { role: 'user', content: q },
  ];
  const toolCalls = [];
  let notice = NOTICE;
  let kernelRelease = null;
  let asAt = null;

  for (let round = 1; round <= MAX_ROUNDS; round++) {
    const msg = await chat(cfg, messages, tools);
    const calls = Array.isArray(msg.tool_calls) ? msg.tool_calls : [];

    if (calls.length === 0) {
      const content = typeof msg.content === 'string' ? msg.content : '';
      const text = content.trim()
        ? content
        : `I could not form an answer from the Care Net kernel. ${ESCALATION}`;
      return { text: withNotice(text, notice), toolCalls, kernelRelease, asAt, refused: false };
    }

    // The assistant turn goes back exactly as Grok sent it, then one tool
    // message per call, each carrying the tool_call_id it answers.
    messages.push({ role: 'assistant', content: typeof msg.content === 'string' ? msg.content : null, tool_calls: calls });

    for (let i = 0; i < calls.length; i++) {
      const call = calls[i] || {};
      const fn = call.function || {};
      let result;
      if (i >= MAX_TOOL_CALLS_PER_ROUND) {
        result = toolError(429, 'Too many tool calls in one turn. Ask for fewer at a time.');
      } else {
        result = await callKernel(cfg, fn.name, fn.arguments);
      }
      toolCalls.push({ name: String(fn.name || ''), status: result.status });
      if (result.ok && result.body && typeof result.body === 'object') {
        if (typeof result.body.notice === 'string' && result.body.notice.trim()) notice = result.body.notice.trim();
        if (result.body.kernel_release) kernelRelease = String(result.body.kernel_release);
        if (result.body.as_at) asAt = String(result.body.as_at);
      }
      messages.push({ role: 'tool', tool_call_id: String(call.id || ''), content: toolContent(result) });
    }
  }

  return {
    text: withNotice(`That question needed more steps than this assistant allows. Please ask something narrower. ${ESCALATION}`, notice),
    toolCalls,
    kernelRelease,
    asAt,
    refused: false,
  };
}

// 8. Command line ---------------------------------------------------------------

async function readStdin() {
  if (process.stdin.isTTY) return '';
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  return Buffer.concat(chunks).toString('utf8');
}

async function main() {
  const question = process.argv.slice(2).join(' ').trim() || (await readStdin()).trim();
  if (!question) {
    process.stderr.write('Usage: node grok/bridge-example.mjs "your question"\n');
    process.exitCode = 2;
    return;
  }
  let cfg;
  try {
    cfg = readConfig();
    const out = await answer(question, { config: cfg });
    process.stdout.write(`${out.text}\n`);
  } catch (err) {
    process.stderr.write(`bridge error: ${redact(err && err.message, cfg)}\n`);
    process.exitCode = 1;
  }
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (invokedDirectly) main();
