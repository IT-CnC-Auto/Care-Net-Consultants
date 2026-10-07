// Rand in the house format (R4 000,00) and the wallet top up options.
// Same arithmetic as supabase/functions/_shared/bi/pricing.js, so the phone and
// the database always agree to the cent. Amounts are cents of a rand,
// excluding VAT, until VAT treatment is confirmed.

export const VAT_NOTE = 'VAT to be confirmed';

/** R4 000,00: a space between thousands and a comma before the cents. */
export function formatRand(cents: number): string {
  if (!Number.isSafeInteger(cents)) throw new RangeError('cents must be a whole number');
  const neg = cents < 0;
  const abs = Math.abs(cents);
  const rands = Math.floor(abs / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  const c = String(abs % 100).padStart(2, '0');
  return (neg ? '-' : '') + 'R' + rands + ',' + c;
}

export type TopUpCode = 'topup_99' | 'topup_249' | 'topup_499' | 'topup_999';

export interface TopUpOption {
  code: TopUpCode;
  priceCents: number;
  valueCents: number;
}

/** Prompt B8 and migration 062: price and value of each top up (value lasts 12 months). */
export const TOP_UPS: readonly TopUpOption[] = [
  { code: 'topup_99', priceCents: 9900, valueCents: 9900 },
  { code: 'topup_249', priceCents: 24900, valueCents: 26000 },
  { code: 'topup_499', priceCents: 49900, valueCents: 55000 },
  { code: 'topup_999', priceCents: 99900, valueCents: 115000 },
];

/** Prompt B3: top ups over R499,00 need step up MFA. R499,00 itself does not. */
export const STEP_UP_TOPUP_ABOVE_CENTS = 49900;

export function topUpNeedsStepUp(priceCents: number): boolean {
  return priceCents > STEP_UP_TOPUP_ABOVE_CENTS;
}

/** "R249,00 (R260,00 value)" when the value is more than the price, else "R99,00". */
export function topUpLabel(o: TopUpOption): string {
  return o.valueCents > o.priceCents
    ? `${formatRand(o.priceCents)} (${formatRand(o.valueCents)} value)`
    : formatRand(o.priceCents);
}
