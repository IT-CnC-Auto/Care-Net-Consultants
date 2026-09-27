import { formatRand, TOP_UPS, topUpLabel, topUpNeedsStepUp } from '../money';
import { applyCharge, balanceFromLedger, chargeRuleCents, estimateView, priceCents, reasonText, type LedgerRow } from '../wallet';

describe('formatRand (house format R4 000,00)', () => {
  it.each([
    [0, 'R0,00'],
    [5, 'R0,05'],
    [500, 'R5,00'],
    [611, 'R6,11'],
    [9900, 'R99,00'],
    [26000, 'R260,00'],
    [115000, 'R1 150,00'],
    [400000, 'R4 000,00'],
    [123456789, 'R1 234 567,89'],
    [-1988, '-R19,88'],
  ])('%i cents is %s', (cents, text) => {
    expect(formatRand(cents)).toBe(text);
  });

  it('refuses fractions of a cent', () => {
    expect(() => formatRand(1.5)).toThrow(RangeError);
  });
});

describe('top ups (prompt B8)', () => {
  it('lists the four options with their value', () => {
    expect(TOP_UPS.map(topUpLabel)).toEqual(['R99,00', 'R249,00 (R260,00 value)', 'R499,00 (R550,00 value)', 'R999,00 (R1 150,00 value)']);
  });
  it('needs step up only above R499,00', () => {
    expect(TOP_UPS.map((t) => topUpNeedsStepUp(t.priceCents))).toEqual([false, false, false, true]);
  });
});

describe('priceCents (same worked example as migration 062)', () => {
  it('prices 200 000 in, 20 000 out and 10 minutes at the test rates as R6,11', () => {
    const cents = priceCents({ tokensIn: 200000, tokensOut: 20000, audioSeconds: 600, rateIn: '0.20', rateOut: '0.50', rateMinute: '0.006', usdZar: '18.50', markup: '3.0' });
    expect(cents).toBe(611);
    expect(formatRand(cents)).toBe('R6,11');
  });
  it('is zero for no usage', () => {
    expect(priceCents({ rateIn: 1, rateOut: 1, usdZar: 18 })).toBe(0);
  });
});

describe('chargeRuleCents (actual, or the estimate when more than 25% above it)', () => {
  it.each([
    [500, 600, 600],
    [500, 625, 625],
    [500, 626, 500],
    [500, 400, 400],
  ])('estimate %i, actual %i charges %i', (est, act, charged) => {
    expect(chargeRuleCents(est, act)).toBe(charged);
  });
});

describe('applyCharge (decision 1.3: shortfall carried by Care Net)', () => {
  it('charges in full when the balance covers it', () => {
    expect(applyCharge(10000, 5994)).toEqual({ chargedCents: 5994, shortfallCents: 0, availableAfterCents: 4006 });
  });
  it('takes the balance to R0,00 and records the shortfall', () => {
    expect(applyCharge(4006, 5994)).toEqual({ chargedCents: 4006, shortfallCents: 1988, availableAfterCents: 0 });
  });
});

describe('balanceFromLedger', () => {
  const now = new Date('2026-09-27T10:00:00Z');
  const rows: LedgerRow[] = [
    { id: 1, entry_kind: 'included_credit', amount_cents: 15000, lot_id: null, expires_at: '2026-11-01T00:00:00Z', created_at: '2026-09-01T00:00:00Z' },
    { id: 2, entry_kind: 'charge', amount_cents: -1180, lot_id: 1, expires_at: null, created_at: '2026-09-20T00:00:00Z' },
    { id: 3, entry_kind: 'topup_credit', amount_cents: 26000, lot_id: null, expires_at: '2027-09-20T00:00:00Z', created_at: '2026-09-20T00:00:00Z' },
    { id: 4, entry_kind: 'included_credit', amount_cents: 15000, lot_id: null, expires_at: '2026-09-01T00:00:00Z', created_at: '2026-07-01T00:00:00Z' },
  ];
  it('matches the seed wallet: R150,00 less R11,80 plus a R249,00 top up is R398,20', () => {
    const b = balanceFromLedger(rows, now);
    expect(formatRand(b.availableCents)).toBe('R398,20');
    expect(b.includedCents).toBe(13820);
    expect(b.purchasedCents).toBe(26000);
    expect(b.nextExpiry).toBe('2026-11-01T00:00:00Z');
  });
});

describe('estimateView (balance before every run)', () => {
  it('shows balance, estimate and balance after', () => {
    const v = estimateView({ estimate_cents: 500, available_cents: 39820, allowed: true, reason: null });
    expect(v).toMatchObject({ estimate: 'R5,00', balance: 'R398,20', balanceAfter: 'R393,20', exceedsBalance: false, canRun: true, warning: null });
    expect(v.confirmText).toContain('R5,00');
  });
  it('warns when the estimate is more than the balance', () => {
    const v = estimateView({ estimate_cents: 2109, available_cents: 1500, allowed: false, reason: 'wallet_empty' });
    expect(v.exceedsBalance).toBe(true);
    expect(v.canRun).toBe(false);
    expect(v.balanceAfter).toBe('R0,00');
    expect(v.warning).toMatch(/more than your balance/);
  });
  it('never mentions tokens', () => {
    for (const r of ['rate_card_pending', 'wallet_empty', 'spend_cap', 'wallet_frozen', 'other']) {
      expect(reasonText(r)).not.toMatch(/token/i);
    }
  });
});
