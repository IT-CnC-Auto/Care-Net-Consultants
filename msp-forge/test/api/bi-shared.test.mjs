// CNC | Bee-Inspect P3: the pure logic of the Edge Functions (node --test, no network).
// supabase/functions/_shared/bi/pricing.js     price, charge rule, photo tagging, storage, rand format, CSV
// supabase/functions/_shared/bi/risk.js        5 x 5 matrix, bands, hierarchy of controls
// supabase/functions/_shared/bi/claim-code.js  the one time code and its hash
// supabase/functions/_shared/bi/validate.js    the zod shaped validator
// supabase/functions/_shared/bi/report.js      the labelled draft skeleton and its citations
// supabase/functions/_shared/bi/http.js        JWT claims, step up, database error mapping
// The worked numbers are the same as test/sql/bi_wallet_checks.sql, so the app's
// cost preview and the database agree to the cent. The AI rates are TEST numbers,
// not xAI's prices.

import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  priceCents, chargeRuleCents, photoTagSplit, storageLevel, formatRand, statementCsv, toScaled, includedExpiry,
  PLANS, TOPUPS, AUTO_TOPUP, DEFAULT_MARKUP, VAT_MODE, STORAGE_BYTES_PER_LINE,
} from '../../supabase/functions/_shared/bi/pricing.js';
import { riskScore, riskBand, topControl, heatMap, validateRisk, describeRisk, HIERARCHY } from '../../supabase/functions/_shared/bi/risk.js';
import { generateCode, normaliseCode, hashCode, ALPHABET, CODE_LENGTH, SHAPE_RE, claimPath } from '../../supabase/functions/_shared/bi/claim-code.js';
import { v, ValidationError } from '../../supabase/functions/_shared/bi/validate.js';
import { buildDraftSkeleton, enforceCitations, claimProblems, voiceCounts, voicePreviewLine, DRAFT_LABEL, LOCKED_FOOTER } from '../../supabase/functions/_shared/bi/report.js';
import { decodeJwtPayload, stepUpFromClaims, sameText, createDb, HttpError } from '../../supabase/functions/_shared/bi/http.js';

const root = (p) => fileURLToPath(new URL('../../' + p, import.meta.url));
const TEST_RATES = { rateIn: 0.2, rateOut: 0.5, rateMinute: 0.006, usdZar: 18.5, markup: 3.0 };

// 1. Pricing -------------------------------------------------------------------------------

test('W1: 200 000 in, 20 000 out, 10 minutes, fx 18.50, markup 3.0 = R6,105, charged R6,11 (611 cents)', () => {
  assert.equal(priceCents({ tokensIn: 200000, tokensOut: 20000, audioSeconds: 600, ...TEST_RATES }), 611);
  assert.equal(formatRand(611), 'R6,11');
});

test('W2 to W5 match the database to the cent', () => {
  assert.equal(priceCents({ tokensIn: 150000, tokensOut: 8000, rateIn: 2, rateOut: 10, usdZar: 18.5, markup: 3 }), 2109);
  assert.equal(priceCents({ audioSeconds: 90, rateMinute: 0.006, usdZar: 18.5, markup: 3 }), 50, 'R0,4995 rounds half up to 50 cents');
  assert.equal(priceCents({ tokensIn: 1, rateIn: 1, usdZar: 18.5, markup: 3 }), 0);
  assert.equal(priceCents({ tokensIn: 200000, tokensOut: 20000, audioSeconds: 600, ...TEST_RATES, markup: 1 }), 204, '203.5 cents rounds to 204');
  assert.equal(priceCents({ tokensIn: 1000000, rateIn: 0.2, usdZar: 18.5 }), 1110, 'markup defaults to 3.0');
  assert.equal(priceCents({ tokensIn: 540000, rateIn: 2, usdZar: 18.5 }), 5994);
});

test('exact arithmetic: no floating point drift on awkward decimals', () => {
  // 0.1 + 0.2 style inputs: 3 000 000 tokens at $0.1/M and $0.2/M = $0.9 x 18.5 x 3 = R49,95.
  assert.equal(priceCents({ tokensIn: 3000000, tokensOut: 3000000, rateIn: 0.1, rateOut: 0.2, usdZar: 18.5, markup: 3 }), 4995);
  assert.equal(toScaled('18.50'), 18500000000000n);
  assert.throws(() => priceCents({ tokensIn: -1, ...TEST_RATES }), RangeError);
  assert.throws(() => priceCents({ tokensIn: 1.5, ...TEST_RATES }), RangeError);
  assert.throws(() => toScaled('-1'), RangeError);
});

test('charge rule: the actual unless more than 25% above the estimate', () => {
  assert.equal(chargeRuleCents(500, 600), 600);
  assert.equal(chargeRuleCents(500, 625), 625);
  assert.equal(chargeRuleCents(500, 626), 500);
  assert.equal(chargeRuleCents(500, 300), 300);
  assert.equal(chargeRuleCents(2109, 2276), 2276, 'the database worked example');
  assert.equal(chargeRuleCents(1110, 2220), 1110);
  assert.throws(() => chargeRuleCents(-1, 5), RangeError);
});

test('photo tagging is free for the first 50 photos of a report', () => {
  assert.deepEqual(photoTagSplit(40, 0), { free: 40, chargeable: 0 });
  assert.deepEqual(photoTagSplit(30, 40), { free: 10, chargeable: 20 });
  assert.deepEqual(photoTagSplit(10, 50), { free: 0, chargeable: 10 });
  assert.equal(priceCents({ tokensIn: 1000 * 20, tokensOut: 100 * 20, rateIn: 0.2, rateOut: 0.5, usdZar: 18.5 }), 28, 'the 20 chargeable photos cost 28 cents');
});

test('storage: 10 GB a line; 80% and 95% warn; 100% full', () => {
  assert.equal(STORAGE_BYTES_PER_LINE, 10737418240);
  assert.equal(storageLevel(79, 100), 'ok');
  assert.equal(storageLevel(80, 100), 'warn_80');
  assert.equal(storageLevel(95, 100), 'warn_95');
  assert.equal(storageLevel(100, 100), 'full');
  assert.equal(storageLevel(0, 0), 'full', 'no live line means no room');
});

test('plans, top ups and automatic top up (prompt B8), excluding VAT, VAT to be confirmed', () => {
  assert.deepEqual(PLANS.base, { price_cents: 29900, wallet_monthly_cents: 15000, storage_bytes: 10737418240 });
  assert.deepEqual(PLANS.extra_company, { price_cents: 19900, wallet_monthly_cents: 10000, storage_bytes: 10737418240 });
  assert.deepEqual(Object.values(TOPUPS).map((t) => formatRand(t.price_cents) + ' buys ' + formatRand(t.value_cents)),
    ['R99,00 buys R99,00', 'R249,00 buys R260,00', 'R499,00 buys R550,00', 'R999,00 buys R1 150,00']);
  assert.deepEqual(AUTO_TOPUP, { price_cents: 9900, value_cents: 9900, below_cents: 2000 });
  assert.equal(DEFAULT_MARKUP, 3.0);
  assert.equal(VAT_MODE, 'to_be_confirmed');
});

test('the same prices as migration 062 and the File site (vercel/hsf/ads.js): one source of truth, three copies agree', () => {
  const sql = readFileSync(root('supabase/migrations/062_bi_wallet_billing_usage.sql'), 'utf8');
  for (const [code, t] of Object.entries(TOPUPS)) {
    assert.match(sql, new RegExp(`\\('${code}', 'topup', '[^']+', ${t.price_cents}, ${t.value_cents},`), code);
  }
  assert.match(sql, /\('base', 'plan', '[^']+', 29900, null, 15000, 10737418240,/);
  assert.match(sql, /\('extra_company', 'plan', '[^']+', 19900, null, 10000, 10737418240,/);
  const ads = readFileSync(root('vercel/hsf/ads.js'), 'utf8');
  for (const t of Object.values(TOPUPS)) assert.match(ads, new RegExp(`zar: ${t.price_cents / 100}, value_zar: ${t.value_cents / 100}`));
  assert.match(ads, /auto_topup: \{ zar: 99, below_zar: 20, opt_in: true \}/);
  assert.match(ads, /photo_tagging_free_per_report: 50/);
});

test('rand in the house format and a usage statement CSV without formula injection', () => {
  assert.equal(formatRand(400000), 'R4 000,00');
  assert.equal(formatRand(115000), 'R1 150,00');
  assert.equal(formatRand(123456789), 'R1 234 567,89');
  assert.equal(formatRand(5), 'R0,05');
  assert.equal(formatRand(-1180), '-R11,80');
  const csv = statementCsv([
    { created_at: '2026-09-26T10:00:00Z', entry_kind: 'charge', amount_cents: -1180, note: '=HYPERLINK("x")' },
    { created_at: '2026-09-01T00:00:00Z', entry_kind: 'included_credit', amount_cents: 15000, note: 'Included, September' },
  ]);
  assert.equal(csv.split('\n')[0], 'Date,Entry,Amount,Note');
  assert.match(csv, /26\/09\/2026,charge,'-R11,80|26\/09\/2026,charge,"'-R11,80"/);
  assert.ok(!/,=HYPERLINK/.test(csv), 'a formula never starts a cell');
  assert.match(csv, /"R150,00"/);
});

test('included value rolls one month: it expires two months after its period starts', () => {
  assert.equal(includedExpiry(new Date(Date.UTC(2026, 8, 1))).toISOString().slice(0, 10), '2026-11-01');
});

// 2. Risk matrix ---------------------------------------------------------------------------------

test('5 x 5 score and bands: 1 to 4 low, 5 to 9 medium, 10 to 15 high, 16 to 25 extreme', () => {
  assert.equal(riskScore(4, 4), 16);
  assert.equal(riskScore(0, 3), null);
  assert.equal(riskScore(6, 1), null);
  const bands = [1, 4, 5, 9, 10, 15, 16, 25].map(riskBand);
  assert.deepEqual(bands, ['low', 'low', 'medium', 'medium', 'high', 'high', 'extreme', 'extreme']);
  assert.equal(riskBand(26), null);
  // Every possible product lands in exactly one band.
  for (let l = 1; l <= 5; l++) for (let s = 1; s <= 5; s++) assert.ok(riskBand(riskScore(l, s)));
});

test('hierarchy of controls: the highest level applied, elimination first, ppe last', () => {
  assert.deepEqual(HIERARCHY, ['elimination', 'substitution', 'engineering', 'administrative', 'ppe']);
  assert.equal(topControl([{ level: 'ppe' }, { level: 'engineering' }]), 'engineering');
  assert.equal(topControl([]), null);
});

test('risk validation matches the database constraints', () => {
  assert.deepEqual(validateRisk({ hazard: 'Unprotected edge', inherent_likelihood: 4, inherent_severity: 4, residual_likelihood: 2, residual_severity: 4, controls: [{ level: 'engineering' }] }), []);
  assert.ok(validateRisk({ hazard: 'x', inherent_likelihood: 4, inherent_severity: 4 }).length > 0, 'hazard too short');
  assert.match(validateRisk({ hazard: 'Edge', inherent_likelihood: 2, inherent_severity: 2, residual_likelihood: 5, residual_severity: 5 }).join(' '), /cannot be above the inherent/);
  assert.match(validateRisk({ hazard: 'Edge', inherent_likelihood: 2, inherent_severity: 2, residual_likelihood: 1 }).join(' '), /both residual/);
  assert.match(validateRisk({ hazard: 'Edge', inherent_likelihood: 2, inherent_severity: 2, controls: [{ level: 'luck' }] }).join(' '), /hierarchy of controls/);
  assert.deepEqual(describeRisk({ inherent_likelihood: 4, inherent_severity: 4, residual_likelihood: 2, residual_severity: 4, controls: [{ level: 'engineering' }] }),
    { inherent: { likelihood: 4, severity: 4, score: 16, band: 'extreme' }, residual: { likelihood: 2, severity: 4, score: 8, band: 'medium' }, top_control: 'engineering' });
});

test('heat map counts risks by likelihood and severity', () => {
  const g = heatMap([{ inherent_likelihood: 4, inherent_severity: 4 }, { inherent_likelihood: 4, inherent_severity: 4 }, { inherent_likelihood: 1, inherent_severity: 5 }]);
  assert.equal(g[3][3], 2);
  assert.equal(g[0][4], 1);
  assert.equal(g.flat().reduce((a, b) => a + b, 0), 3);
});

// 3. Claim codes --------------------------------------------------------------------------------------

test('claim codes: 8 characters from an alphabet without look alikes, within the claim page shape', () => {
  assert.ok(!/[01OIL]/.test(ALPHABET));
  for (let i = 0; i < 200; i++) {
    const c = generateCode();
    assert.equal(c.length, CODE_LENGTH);
    assert.ok([...c].every((ch) => ALPHABET.includes(ch)));
    assert.ok(SHAPE_RE.test(c));
  }
  // The claim page of P2 (vercel/js/cnc-bee.js) accepts the same shape.
  assert.match(readFileSync(root('vercel/js/cnc-bee.js'), 'utf8'), /CLAIM_RE = \/\^\[A-Za-z0-9\]\{6,12\}\$\//);
});

test('claim codes: rejection sampling skips biased bytes', () => {
  let call = 0;
  // 248 and above are the biased tail for a 31 character alphabet and must be skipped.
  const fake = (a) => { a.fill(call++ === 0 ? 250 : 0); return a; };
  assert.equal(generateCode(fake), 'AAAAAAAA');
});

test('claim codes: normalised to upper case and hashed like the database (SHA 256 hex)', async () => {
  assert.equal(normaliseCode(' k7m2-qx9a '), 'K7M2QX9A');
  assert.equal(normaliseCode('abc'), null);
  assert.equal(normaliseCode('<script>'), null);
  const expected = createHash('sha256').update('K7M2QX9A').digest('hex');
  assert.equal(await hashCode('k7m2qx9a'), expected);
  assert.equal(expected, '3592d710b7de6313da5c4f288203bea28bd789e4600e853453c80bfefd011fbf');
  await assert.rejects(() => hashCode('no'), RangeError);
  assert.equal(claimPath('K7M2QX9A'), '/claim/K7M2QX9A');
});

// 4. Validator -------------------------------------------------------------------------------------------

test('validator: strict objects, uuids, enums, optional fields, parse throws a 400', () => {
  const S = v.object({ id: v.uuid(), kind: v.enum(['a', 'b']), n: v.int().min(0).max(10).optional(), note: v.string().max(5).optional() });
  assert.deepEqual(S.parse({ id: '11111111-2222-4333-8444-555555555555', kind: 'a' }), { id: '11111111-2222-4333-8444-555555555555', kind: 'a' });
  const r = S.safeParse({ id: 'nope', kind: 'c', n: 11, note: 'too long', tenant_id: 'x' });
  assert.equal(r.success, false);
  const paths = r.error.issues.map((i) => i.path.join('.'));
  assert.deepEqual(paths.sort(), ['id', 'kind', 'n', 'note', 'tenant_id'].sort());
  assert.throws(() => S.parse(null), (e) => e instanceof ValidationError && e.status === 400);
  assert.throws(() => S.parse({ id: '11111111-2222-4333-8444-555555555555', kind: 'a', n: 1.5 }), /whole number/);
  assert.deepEqual(v.array(v.int()).max(2).safeParse([1, 2, 3]).success, false);
  assert.equal(v.string().nullable().parse(null), null);
});

// 5. Report skeleton ----------------------------------------------------------------------------------------

const DATA = {
  inspection: { id: 'i1', title: 'Scaffold inspection (fictitious)' },
  template: { code: 'SCAFFOLDS', section_f_element_code: 'HSF-F-01' },
  templateItems: [{ id: 't2', prompt: 'Toe boards in place', kernel_ref: 'CNC-DEMO-SCAFF-01' }, { id: 't4', prompt: 'Register signed', kernel_ref: null }],
  areas: [{ id: 'a1', label: 'Laydown area' }],
  findings: [
    { id: 'f1', area_id: 'a1', template_item_id: 't2', result: 'fail', note: 'Missing', severity: 'high' },
    { id: 'f2', area_id: 'a1', template_item_id: 't4', result: 'fail' },
    { id: 'f3', area_id: 'a1', result: 'pass' },
  ],
  photos: [{ id: 'p1', finding_id: 'f1' }],
  risks: [{ id: 'r1', hazard: 'Falling objects', inherent_likelihood: 4, inherent_severity: 4, residual_likelihood: 2, residual_severity: 4, controls: [{ level: 'engineering' }] }],
  actions: [{ id: 'c1', finding_id: 'f1', description: 'Fit toe boards', owner_name: 'Owner', due_on: '2026-10-01', status: 'open' }],
  voiceNotes: [{ id: 'v1', finding_id: 'f1', vn_number: 1 }, { id: 'v2', finding_id: 'f2', vn_number: 2 }],
  transcripts: [{ voice_note_id: 'v1', version: 1, body: 'first' }, { voice_note_id: 'v1', version: 2, body: 'corrected' }],
};

test('the draft skeleton is labelled, carries the locked footer and cites only kernel references', () => {
  const c = buildDraftSkeleton(DATA);
  assert.equal(c.label, DRAFT_LABEL);
  assert.equal(DRAFT_LABEL, 'Assistive draft. Competent person sign off required.');
  assert.equal(c.footer, LOCKED_FOOTER);
  assert.equal(c.claims.length, 1);
  assert.deepEqual(c.claims[0], { text: 'Did not pass: Toe boards in place.', kernel_ref: 'CNC-DEMO-SCAFF-01', finding_id: 'f1' });
  assert.deepEqual(c.uncited, ['Did not pass: Register signed.'], 'a Fail without a kernel reference is never a claim');
  assert.match(c.executive_summary, /3 checklist items recorded across 1 areas: 1 Pass, 2 Fail, 0 Observe, 0 N\/A\./);
  assert.deepEqual(c.findings[0].voice_notes, ['VN-1']);
  assert.equal(c.voice_note_index[0].transcript_version, 2, 'the latest correction is used');
  assert.deepEqual(c.voice_notes, { total: 2, accounted: 2, missing: 0 });
  assert.equal(c.risk_register[0].inherent.band, 'extreme');
  assert.equal(c.heat_map.inherent[3][3], 1);
  assert.equal(c.section_f_element_code, 'HSF-F-01');
  assert.ok(!/compliant/i.test(JSON.stringify(c)));
});

test('citations: claims the kernel does not hold are removed into uncited', () => {
  const c = { claims: [{ text: 'a', kernel_ref: 'CNC-DEMO-SCAFF-01' }, { text: 'b' }, { text: 'c', kernel_ref: 'MADE-UP-99' }] };
  assert.deepEqual(claimProblems(c, ['CNC-DEMO-SCAFF-01']).map((p) => p.index), [1, 2]);
  const e = enforceCitations(c, ['CNC-DEMO-SCAFF-01']);
  assert.deepEqual(e.claims.map((x) => x.text), ['a']);
  assert.deepEqual(e.uncited, ['b', 'c']);
});

test('voice note preview line', () => {
  const counts = voiceCounts([{ vn_number: 1 }, { vn_number: 2 }, { vn_number: 3 }], { voice_note_index: [{ vn: 1 }, { vn: 3 }] });
  assert.deepEqual(counts, { total: 3, accounted: 2, missing: 1 });
  assert.equal(voicePreviewLine(counts), 'Voice notes: 2 accounted for, 1 missing');
});

// 6. HTTP helpers ------------------------------------------------------------------------------------------

const b64url = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');

test('JWT claims are read (after Supabase Auth accepted the token) and step up needs aal2 with a second factor', async () => {
  const token = `x.${b64url({ sub: 'u1', aal: 'aal2', session_id: 's1', amr: [{ method: 'password', timestamp: 100 }, { method: 'totp', timestamp: 200 }] })}.y`;
  const claims = decodeJwtPayload(token);
  assert.equal(claims.sub, 'u1');
  const s = await stepUpFromClaims(claims, 'signoff');
  assert.deepEqual({ ...s, session_ref: s.session_ref.length }, { purpose: 'signoff', method: 'totp', aal: 'aal2', asserted_epoch: 200, session_ref: 64 });
  assert.notEqual(s.session_ref, 's1', 'only a hash of the session id');
  assert.equal(await stepUpFromClaims({ aal: 'aal1', amr: [{ method: 'totp', timestamp: 1 }] }, 'signoff'), null);
  assert.equal(await stepUpFromClaims({ aal: 'aal2', amr: [{ method: 'password', timestamp: 1 }] }, 'signoff'), null);
  assert.deepEqual(decodeJwtPayload('garbage'), {});
});

test('secrets are compared in constant time', () => {
  assert.equal(sameText('abc', 'abc'), true);
  assert.equal(sameText('abc', 'abd'), false);
  assert.equal(sameText('abc', 'abcd'), false);
  assert.equal(sameText(undefined, 'a'), false);
});

test('database refusals map to HTTP without leaking database detail', async () => {
  const mk = (status, body) => async () => new Response(JSON.stringify(body), { status });
  const cases = [['P0002', 404], ['42501', 403], ['28000', 401], ['22023', 400], ['23514', 422], ['53400', 429], ['53100', 507]];
  for (const [code, status] of cases) {
    const db = createDb({ url: 'https://x', serviceKey: 'k', fetch: mk(400, { code, message: 'Plain refusal.' }) });
    await assert.rejects(() => db.rpc('f', {}), (e) => e instanceof HttpError && e.status === status && e.message === 'Plain refusal.');
  }
  const db = createDb({ url: 'https://x', serviceKey: 'k', fetch: mk(500, { code: 'XX000', message: 'internal detail' }) });
  await assert.rejects(() => db.rpc('f', {}), (e) => e.status === 502 && !/internal detail/.test(e.message));
});
