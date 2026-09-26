// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | Bee-Inspect pricing maths 26/09/2026
//
// The same arithmetic as migration 062 (bi_price_cents, bi_charge_rule_cents,
// bi_storage_level), so the app's cost preview and the database always agree to
// the cent. Plain ES module, no dependencies; Deno and Node 22.
//
// Prompt B8, all amounts in cents of a rand, excluding VAT (VAT mode
// 'to_be_confirmed' until Chantelle confirms {{vat_inclusive}}):
//   price  = (tokens in x input rate + tokens out x output rate
//             + audio minutes x transcription rate) x fx x markup
//            rates in US dollars per million tokens and per minute; fx in rand
//            per US dollar; markup 3.0 by default. Exact decimal arithmetic
//            (BigInt), rounded half up to the cent once, at the end.
//   charge = the actual price unless it is more than the estimate plus 25%,
//            then the estimate.
// Worked example (TEST rates, not xAI's prices): 200 000 tokens in at $0.20/M,
// 20 000 out at $0.50/M, 10 minutes at $0.006/min, fx 18.50, markup 3.0:
// $0.11 x 18.50 x 3.0 = R6,105, charged as R6,11 (611 cents).

export const DEFAULT_MARKUP = 3.0;
export const VAT_MODE = 'to_be_confirmed';
export const OVERRUN_ALLOWANCE_NUM = 5; // actual may be up to 5/4 of the estimate
export const OVERRUN_ALLOWANCE_DEN = 4;
export const PHOTO_TAGS_FREE_PER_REPORT = 50;
export const STORAGE_BYTES_PER_LINE = 10 * 1024 * 1024 * 1024; // 10 GB per company line

// Prompt B8. Price and value in cents, excluding VAT.
export const PLANS = Object.freeze({
  base: { price_cents: 29900, wallet_monthly_cents: 15000, storage_bytes: STORAGE_BYTES_PER_LINE },
  extra_company: { price_cents: 19900, wallet_monthly_cents: 10000, storage_bytes: STORAGE_BYTES_PER_LINE },
});
export const TOPUPS = Object.freeze({
  topup_99: { price_cents: 9900, value_cents: 9900 },
  topup_249: { price_cents: 24900, value_cents: 26000 },
  topup_499: { price_cents: 49900, value_cents: 55000 },
  topup_999: { price_cents: 99900, value_cents: 115000 },
});
export const AUTO_TOPUP = Object.freeze({ price_cents: 9900, value_cents: 9900, below_cents: 2000 });
export const INCLUDED_ROLLS_MONTHS = 1; // included value expires two months after its period starts
export const PURCHASED_LASTS_MONTHS = 12;
export const STEP_UP_TOPUP_ABOVE_CENTS = 49900; // top ups over R499,00 need step up MFA (B3)

const SCALE_DIGITS = 12;
const SCALE = 10n ** BigInt(SCALE_DIGITS);

// A non negative decimal (number or numeric string) as a BigInt scaled by 10^12.
export function toScaled(x) {
  if (x === null || x === undefined || x === '') return 0n;
  let s = typeof x === 'number' ? x.toFixed(SCALE_DIGITS) : String(x).trim();
  if (!/^\d+(\.\d+)?$/.test(s)) throw new RangeError(`not a non negative decimal: ${x}`);
  const [whole, frac = ''] = s.split('.');
  const fracPadded = (frac + '0'.repeat(SCALE_DIGITS)).slice(0, SCALE_DIGITS);
  return BigInt(whole) * SCALE + BigInt(fracPadded);
}

function toCount(x, name) {
  const n = x === undefined || x === null ? 0 : x;
  if (!Number.isSafeInteger(n) || n < 0) throw new RangeError(`${name} must be a whole number of zero or more`);
  return BigInt(n);
}

// priceCents({tokensIn, tokensOut, audioSeconds, rateIn, rateOut, rateMinute, usdZar, markup})
export function priceCents(p) {
  const tin = toCount(p.tokensIn, 'tokensIn');
  const tout = toCount(p.tokensOut, 'tokensOut');
  const sec = toCount(p.audioSeconds, 'audioSeconds');
  const rin = toScaled(p.rateIn);
  const rout = toScaled(p.rateOut);
  const rmin = toScaled(p.rateMinute);
  const fx = toScaled(p.usdZar);
  const mk = toScaled(p.markup === undefined ? DEFAULT_MARKUP : p.markup);
  // cents = (tin*rin/1e6 + tout*rout/1e6 + sec*rmin/60) * fx * mk * 100
  // Every rate carries SCALE; three scaled factors multiply (SCALE^3).
  const num = (tin * rin * 60n + tout * rout * 60n + sec * rmin * 1000000n) * fx * mk * 100n;
  const den = 60000000n * SCALE * SCALE * SCALE;
  return Number((2n * num + den) / (2n * den)); // half up
}

// The amount charged after the action (prompt B8).
export function chargeRuleCents(estimateCents, actualCents) {
  if (!Number.isSafeInteger(estimateCents) || !Number.isSafeInteger(actualCents) || estimateCents < 0 || actualCents < 0) {
    throw new RangeError('cents must be whole numbers of zero or more');
  }
  return actualCents * OVERRUN_ALLOWANCE_DEN > estimateCents * OVERRUN_ALLOWANCE_NUM ? estimateCents : actualCents;
}

// Photo tagging: free for the first 50 photos of a report.
export function photoTagSplit(photos, alreadyTagged) {
  const n = Math.max(0, photos | 0);
  const free = Math.min(n, Math.max(0, PHOTO_TAGS_FREE_PER_REPORT - Math.max(0, alreadyTagged | 0)));
  return { free, chargeable: n - free };
}

export function storageLevel(usedBytes, quotaBytes) {
  if (!(quotaBytes > 0)) return 'full';
  if (usedBytes * 100 >= quotaBytes * 100) return 'full';
  if (usedBytes * 100 >= quotaBytes * 95) return 'warn_95';
  if (usedBytes * 100 >= quotaBytes * 80) return 'warn_80';
  return 'ok';
}

// Included value for a period rolls over one month: it expires two months after the period starts.
export function includedExpiry(periodStart) {
  const d = new Date(Date.UTC(periodStart.getUTCFullYear(), periodStart.getUTCMonth() + 1 + INCLUDED_ROLLS_MONTHS, periodStart.getUTCDate()));
  return d;
}

// House format: R4 000,00 (space between thousands, comma before cents).
export function formatRand(cents) {
  if (!Number.isSafeInteger(cents)) throw new RangeError('cents must be a whole number');
  const neg = cents < 0;
  const abs = Math.abs(cents);
  const rands = Math.floor(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  const c = String(abs % 100).padStart(2, '0');
  return (neg ? '-' : '') + 'R' + rands + ',' + c;
}

// A usage statement as CSV (prompt B8, "usage statement + CSV"): rand, never tokens.
export function statementCsv(rows) {
  const esc = (x) => {
    const s = x === null || x === undefined ? '' : String(x);
    // Formula injection guard: a cell never starts with = + - @ or a control character.
    const safe = /^[=+\-@\t\r]/.test(s) ? "'" + s : s;
    return /[",\n]/.test(safe) ? '"' + safe.replace(/"/g, '""') + '"' : safe;
  };
  const head = ['Date', 'Entry', 'Amount', 'Note'];
  const body = rows.map((r) => [
    new Date(r.created_at).toISOString().slice(0, 10).split('-').reverse().join('/'),
    r.entry_kind,
    formatRand(r.amount_cents),
    r.note || '',
  ]);
  return [head].concat(body).map((line) => line.map(esc).join(',')).join('\n') + '\n';
}
