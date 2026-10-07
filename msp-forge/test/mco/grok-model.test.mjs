// CNC HSF FORGE | tests for the latest model choice in grok/model-pick.mjs and grok/bridge-example.mjs (node --test)
// No network: every fetch is mocked. The model ids below are made up fixtures
// shaped like an OpenAI style model list; none of them names a real model.
import test from 'node:test';
import assert from 'node:assert/strict';
import { pickLatestModel, createModelPicker, readConfig, resolveModel, answer } from '../../grok/bridge-example.mjs';
import * as pick from '../../grok/model-pick.mjs';

const KERNEL_KEY = `cnck_${'a'.repeat(64)}`;
const XAI_KEY = 'xai-UNIT-TEST-key-must-never-appear';
const DAY = 24 * 60 * 60 * 1000;

const LIST = {
  object: 'list',
  data: [
    { id: 'grok-fixture-old', created: 100 },
    { id: 'grok-fixture-new', created: 300 },
    { id: 'grok-fixture-new-mini', created: 900 },
    { id: 'grok-fixture-new-fast', created: 901 },
    { id: 'grok-fixture-image', created: 902 },
    { id: 'grok-fixture-imagine', created: 903 },
    { id: 'grok-fixture-vision', created: 904 },
    { id: 'grok-fixture-embed', created: 905 },
    { id: 'grok-fixture-code', created: 906 },
    { id: 'other-fixture', created: 999 },
    { id: 'grok-fixture-undated' },
  ],
};

function reply(status, body) {
  return { ok: status >= 200 && status < 300, status, json: async () => body, text: async () => JSON.stringify(body) };
}

function mockFetch(answers) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url: String(url), init });
    const next = answers.shift();
    if (next instanceof Error) throw next;
    return next;
  };
  fn.calls = calls;
  return fn;
}

test('pickLatestModel keeps grok chat models, drops the excluded kinds and takes the greatest created', () => {
  assert.equal(pickLatestModel(LIST), 'grok-fixture-new');
  assert.equal(pickLatestModel(LIST.data), 'grok-fixture-new', 'a bare array is read too');
  assert.equal(pickLatestModel({ data: [{ id: 'Grok-Fixture-Vision', created: 5 }] }), null, 'the exclusions ignore case');
  assert.equal(pickLatestModel({ data: [] }), null);
  assert.equal(pickLatestModel(null), null);
  assert.equal(pickLatestModel({ data: [{ id: 'grok-fixture-b', created: 7 }, { id: 'grok-fixture-a', created: 7 }] }), 'grok-fixture-b',
    'a tie is settled the same way every time');
});

test('the picker reads the list on first use, then at most once a day, with the xAI key', async () => {
  let clock = 1_000_000;
  const logs = [];
  const f = mockFetch([reply(200, LIST), reply(200, { data: [...LIST.data, { id: 'grok-fixture-newer', created: 400 }] })]);
  const picker = createModelPicker({ xaiBase: 'https://xai.invalid/v1', xaiKey: XAI_KEY, fetchImpl: f, now: () => clock, log: (l) => logs.push(l) });

  assert.equal(await picker.model(), 'grok-fixture-new');
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].url, 'https://xai.invalid/v1/models');
  assert.equal(f.calls[0].init.method, 'GET');
  assert.equal(f.calls[0].init.headers.Authorization, `Bearer ${XAI_KEY}`);

  clock += DAY - 1;
  assert.equal(await picker.model(), 'grok-fixture-new');
  assert.equal(f.calls.length, 1, 'no second call inside a day');

  clock += 1;
  assert.equal(await picker.model(), 'grok-fixture-newer');
  assert.equal(f.calls.length, 2, 'the list is read again after a day');
  assert.deepEqual(logs, ['bridge: xAI model chosen: grok-fixture-new', 'bridge: xAI model chosen: grok-fixture-newer']);
  for (const l of logs) assert.ok(!l.includes(XAI_KEY), 'a log line carries the xAI key');
});

test('a failed list keeps the last good choice and waits another day', async () => {
  let clock = 0;
  const logs = [];
  const f = mockFetch([reply(200, LIST), reply(503, { error: 'down' }), new Error('network down'), reply(200, { data: [] })]);
  const picker = createModelPicker({ xaiBase: 'https://xai.invalid/v1', xaiKey: XAI_KEY, fetchImpl: f, now: () => clock, log: (l) => logs.push(l) });
  assert.equal(await picker.model(), 'grok-fixture-new');
  clock += DAY;
  assert.equal(await picker.model(), 'grok-fixture-new', 'a 503 keeps the last good choice');
  assert.equal(await picker.model(), 'grok-fixture-new');
  assert.equal(f.calls.length, 2, 'a failure also counts as the day\'s read');
  clock += DAY;
  assert.equal(await picker.model(), 'grok-fixture-new', 'a network failure keeps the last good choice');
  clock += DAY;
  assert.equal(await picker.model(), 'grok-fixture-new', 'a list with no Grok chat model keeps the last good choice');
  assert.equal(f.calls.length, 4);
  assert.ok(logs.slice(1).every((l) => l.endsWith('keeping grok-fixture-new')), logs.join(' | '));
});

test('with no good choice yet the question fails plainly and the list is tried again later', async () => {
  let clock = 0;
  const f = mockFetch([new Error('network down'), reply(200, LIST)]);
  const picker = createModelPicker({ xaiBase: 'https://xai.invalid/v1', xaiKey: XAI_KEY, fetchImpl: f, now: () => clock, log: () => {} });
  await assert.rejects(picker.model(), /No Grok model could be chosen/);
  await assert.rejects(picker.model(), /No Grok model could be chosen/);
  assert.equal(f.calls.length, 1, 'no hammering straight after a failure');
  clock += 15 * 60 * 1000;
  assert.equal(await picker.model(), 'grok-fixture-new');
  assert.equal(f.calls.length, 2);
});

test('XAI_MODEL unset or auto means the latest model; any other value is used as it stands', async () => {
  const base = { XAI_API_KEY: XAI_KEY, CNC_KERNEL_API_KEY: KERNEL_KEY, CNC_KERNEL_API_BASE: 'https://forge.invalid' };
  const unset = readConfig(base);
  assert.equal(unset.model, null);
  assert.ok(unset.modelPicker);
  const auto = readConfig({ ...base, XAI_MODEL: ' AUTO ' });
  assert.equal(auto.model, null);
  assert.equal(auto.modelPicker, unset.modelPicker, 'one picker per xAI account, shared across calls');
  const fixed = readConfig({ ...base, XAI_MODEL: 'alias-set-by-odendaal' });
  assert.equal(fixed.model, 'alias-set-by-odendaal');
  assert.equal(fixed.modelPicker, null);
  assert.equal(await resolveModel(fixed), 'alias-set-by-odendaal');
  assert.throws(() => readConfig({ XAI_MODEL: 'auto' }), /Missing environment variables: XAI_API_KEY, CNC_KERNEL_API_KEY, CNC_KERNEL_API_BASE/);
});

test('answer() sends the chosen model to chat completions', async (t) => {
  const f = mockFetch([reply(200, LIST), reply(200, { choices: [{ message: { role: 'assistant', content: 'From the kernel.' } }] })]);
  t.mock.method(globalThis, 'fetch', f);
  const picker = createModelPicker({ xaiBase: 'https://xai.invalid/v1', xaiKey: XAI_KEY, log: () => {} });
  const config = Object.freeze({
    xaiKey: XAI_KEY, model: null, modelPicker: picker, kernelKey: KERNEL_KEY,
    kernelBase: 'https://forge.invalid', xaiBase: 'https://xai.invalid/v1',
  });
  const out = await answer('Which instruments apply to construction?', { config, systemPrompt: 'Test prompt.', tools: [] });
  assert.equal(f.calls[0].url, 'https://xai.invalid/v1/models');
  assert.equal(f.calls[1].url, 'https://xai.invalid/v1/chat/completions');
  assert.equal(JSON.parse(f.calls[1].init.body).model, 'grok-fixture-new');
  assert.match(out.text, /^From the kernel\./);
});

test('the bridge uses the shared rule in model-pick.mjs', () => {
  assert.equal(pickLatestModel, pick.pickLatestModel);
  assert.deepEqual(pick.MODEL_EXCLUDE, ['image', 'imagine', 'vision', 'embed', 'mini', 'fast', 'code']);
});

test('pickLatestAlias takes an alias ending in latest for the flagship family only', () => {
  const list = {
    models: [
      { id: 'grok-fixture-2', created: 200, aliases: ['grok-fixture-2-0101', 'grok-fixture-2-latest'] },
      { id: 'grok-fixture-3', created: 300, aliases: ['grok-fixture-3-0923'] },
      { id: 'grok-fixture-3-fast', created: 900, aliases: ['grok-fixture-fast-latest'] },
      { id: 'grok-fixture-4', created: 400, aliases: ['grok-fixture-mini-latest'] },
      { id: 'other-fixture', created: 999, aliases: ['other-latest'] },
      { id: 'grok-fixture-5', created: 500, aliases: ['grok-fixture latest'] },
    ],
  };
  assert.equal(pick.pickLatestAlias(list), 'grok-fixture-2-latest',
    'a fast model, a mini alias, another family and an alias with a space are all passed over');
  assert.equal(pick.listHasAliases(list), true);
  assert.deepEqual(pick.pickModel(list), { id: 'grok-fixture-2-latest', how: 'alias' });
  assert.equal(pick.pickLatestAlias({ data: [{ id: 'grok-fixture-a', created: 1, aliases: ['grok-fixture-a-LATEST'] }] }), 'grok-fixture-a-LATEST',
    'the data key and any case of latest are read');
});

test('pickModel falls back to the newest rule, and gives nothing for an empty or odd list', () => {
  assert.deepEqual(pick.pickModel(LIST), { id: 'grok-fixture-new', how: 'newest' });
  assert.equal(pick.listHasAliases(LIST), false);
  assert.deepEqual(pick.pickModel({ models: [{ id: 'grok-fixture-x', created: 1, aliases: [] }] }), { id: 'grok-fixture-x', how: 'newest' },
    'an empty alias list falls back to the newest rule');
  assert.deepEqual(pick.pickModel({ models: [] }), { id: null, how: null });
  assert.deepEqual(pick.pickModel({ unexpected: true }), { id: null, how: null });
  assert.deepEqual(pick.pickModel({ data: [{ id: 'grok-fixture\nXAI_API_KEY=x', created: 5 }] }), { id: null, how: null },
    'an id that is not a plain token is never chosen for the .env');
});
