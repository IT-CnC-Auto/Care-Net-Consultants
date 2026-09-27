// AI Wallet rules on the phone (prompt B8, decision 1.3). Always rand, never
// tokens. priceCents and chargeRuleCents are the same arithmetic as
// supabase/functions/_shared/bi/pricing.js (bi_price_cents and
// bi_charge_rule_cents of migration 062); the database decides again on every
// estimate and charge, the phone only shows the numbers.

import { formatRand } from './money';

export const DEFAULT_MARKUP = 3.0;
const SCALE_DIGITS = 12;
const SCALE = BigInt(10) ** BigInt(SCALE_DIGITS);

function toScaled(x: number | string | undefined | null): bigint {
  if (x === null || x === undefined || x === '') return BigInt(0);
  const s = typeof x === 'number' ? x.toFixed(SCALE_DIGITS) : String(x).trim();
  if (!/^\d+(\.\d+)?$/.test(s)) throw new RangeError(`not a non negative decimal: ${x}`);
  const [whole, frac = ''] = s.split('.');
  const fracPadded = (frac + '0'.repeat(SCALE_DIGITS)).slice(0, SCALE_DIGITS);
  return BigInt(whole) * SCALE + BigInt(fracPadded);
}

function toCount(n: number | undefined, name: string): bigint {
  const v = n ?? 0;
  if (!Number.isSafeInteger(v) || v < 0) throw new RangeError(`${name} must be a whole number of zero or more`);
  return BigInt(v);
}

export interface PriceInput {
  tokensIn?: number;
  tokensOut?: number;
  audioSeconds?: number;
  /** US dollars per million input tokens. */
  rateIn: number | string;
  /** US dollars per million output tokens. */
  rateOut: number | string;
  /** US dollars per audio minute. */
  rateMinute?: number | string;
  /** Rand per US dollar. */
  usdZar: number | string;
  markup?: number | string;
}

/** (tokens x rate + audio minutes x rate) x fx x markup, in cents, half up once. */
export function priceCents(p: PriceInput): number {
  const tin = toCount(p.tokensIn, 'tokensIn');
  const tout = toCount(p.tokensOut, 'tokensOut');
  const sec = toCount(p.audioSeconds, 'audioSeconds');
  const rin = toScaled(p.rateIn);
  const rout = toScaled(p.rateOut);
  const rmin = toScaled(p.rateMinute);
  const fx = toScaled(p.usdZar);
  const mk = toScaled(p.markup === undefined ? DEFAULT_MARKUP : p.markup);
  const n60 = BigInt(60);
  const million = BigInt(1000000);
  const num = (tin * rin * n60 + tout * rout * n60 + sec * rmin * million) * fx * mk * BigInt(100);
  const den = BigInt(60000000) * SCALE * SCALE * SCALE;
  const two = BigInt(2);
  return Number((two * num + den) / (two * den));
}

/** The amount charged: the actual, unless it is more than 25% above the estimate, then the estimate. */
export function chargeRuleCents(estimateCents: number, actualCents: number): number {
  if (!Number.isSafeInteger(estimateCents) || !Number.isSafeInteger(actualCents) || estimateCents < 0 || actualCents < 0) {
    throw new RangeError('cents must be whole numbers of zero or more');
  }
  return actualCents * 4 > estimateCents * 5 ? estimateCents : actualCents;
}

/**
 * Decision 1.3: a charge above the balance takes the balance to R0,00 and Care
 * Net carries the rest (a subsidy row). Never below zero, never billed later.
 */
export function applyCharge(availableCents: number, chargeCents: number): { chargedCents: number; shortfallCents: number; availableAfterCents: number } {
  const charged = Math.min(Math.max(0, availableCents), chargeCents);
  return { chargedCents: charged, shortfallCents: chargeCents - charged, availableAfterCents: Math.max(0, availableCents) - charged };
}

export type LedgerKind = 'included_credit' | 'topup_credit' | 'auto_topup_credit' | 'welcome_credit' | 'charge' | 'expiry' | 'refund';

export interface LedgerRow {
  id: number | string;
  entry_kind: LedgerKind;
  amount_cents: number;
  lot_id: number | string | null;
  expires_at: string | null;
  note?: string | null;
  created_at: string;
}

const CREDIT_KINDS: readonly LedgerKind[] = ['included_credit', 'topup_credit', 'auto_topup_credit', 'welcome_credit'];

export interface Balance {
  availableCents: number;
  includedCents: number;
  purchasedCents: number;
  nextExpiry: string | null;
}

/**
 * The balance from the ledger rows the app may read (bi_wallet_ledger), the
 * same as bi_wallet_lots and bi_wallet_balance: each credit is a lot; charges,
 * expiries and refunds point at their lot; only lots not yet expired count.
 */
export function balanceFromLedger(rows: readonly LedgerRow[], now: Date = new Date()): Balance {
  const lots = new Map<string, { kind: LedgerKind; expires: number; expiresIso: string; remaining: number }>();
  for (const r of rows) {
    if (CREDIT_KINDS.includes(r.entry_kind) && r.expires_at) {
      lots.set(String(r.id), { kind: r.entry_kind, expires: Date.parse(r.expires_at), expiresIso: r.expires_at, remaining: r.amount_cents });
    }
  }
  for (const r of rows) {
    if (!CREDIT_KINDS.includes(r.entry_kind) && r.lot_id !== null && r.lot_id !== undefined) {
      const lot = lots.get(String(r.lot_id));
      if (lot) lot.remaining += r.amount_cents;
    }
  }
  let available = 0;
  let included = 0;
  let next: { t: number; iso: string } | null = null;
  const t = now.getTime();
  for (const lot of lots.values()) {
    if (lot.expires <= t) continue;
    const left = Math.max(0, lot.remaining);
    available += left;
    if (lot.kind === 'included_credit') included += left;
    if (left > 0 && (!next || lot.expires < next.t)) next = { t: lot.expires, iso: lot.expiresIso };
  }
  return { availableCents: available, includedCents: included, purchasedCents: available - included, nextExpiry: next ? next.iso : null };
}

export type EstimateReason = 'rate_card_pending' | 'wallet_empty' | 'spend_cap' | 'wallet_frozen' | null;

export interface EstimateResult {
  estimate_cents: number;
  available_cents: number;
  allowed: boolean;
  reason: EstimateReason | string | null;
}

export interface EstimateView {
  estimate: string;
  balance: string;
  balanceAfter: string;
  exceedsBalance: boolean;
  canRun: boolean;
  /** Plain words shown above the confirm button; null when there is nothing to warn about. */
  warning: string | null;
  confirmText: string;
}

export function reasonText(reason: string | null | undefined): string | null {
  switch (reason) {
    case null:
    case undefined:
    case '':
      return null;
    case 'rate_card_pending':
      return 'AI prices are not set yet, so AI drafts are paused. The template draft is free and works now.';
    case 'wallet_empty':
      return 'The estimate is more than your balance. Top up to run the AI draft, or use the free template draft.';
    case 'spend_cap':
      return 'This would pass the monthly spend limit your company set. Ask your company administrator, or use the free template draft.';
    case 'wallet_frozen':
      return 'This wallet is paused. Speak to a Care Net sales executive, or use the free template draft.';
    default:
      return 'The AI Wallet cannot pay for this right now. The template draft is free and works now.';
  }
}

/** What the screen shows before an AI action (decision 1.3): balance first, then the estimate. */
export function estimateView(e: EstimateResult): EstimateView {
  const exceeds = e.estimate_cents > e.available_cents;
  const after = Math.max(0, e.available_cents - e.estimate_cents);
  let warning = reasonText(e.allowed ? null : e.reason);
  if (!warning && exceeds) {
    warning = 'The estimate is more than your balance. If the draft costs more than your balance, your balance goes to R0,00 and Care Net carries the difference.';
  }
  return {
    estimate: formatRand(e.estimate_cents),
    balance: formatRand(e.available_cents),
    balanceAfter: formatRand(after),
    exceedsBalance: exceeds,
    canRun: e.allowed,
    warning,
    confirmText: `Run the AI draft for about ${formatRand(e.estimate_cents)}? Your balance after is about ${formatRand(after)}.`,
  };
}

export interface SubsidyNotice {
  id: string;
  created_at: string;
  shortfall_cents: number;
  what: string;
}

export function subsidyText(n: SubsidyNotice): string {
  return `Care Net carried ${formatRand(n.shortfall_cents)} of ${n.what}. You never owe this, and it never stops a top up.`;
}

export function ledgerKindText(kind: LedgerKind): string {
  switch (kind) {
    case 'included_credit':
      return 'Included with your plan';
    case 'topup_credit':
      return 'Top up';
    case 'auto_topup_credit':
      return 'Automatic top up';
    case 'welcome_credit':
      return 'Welcome credit';
    case 'charge':
      return 'AI use';
    case 'expiry':
      return 'Expired value';
    case 'refund':
      return 'Refund';
  }
}
