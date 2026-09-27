// The phone and the Edge Functions must agree to the cent and to the band.
// These modules are read, never changed, from supabase/functions/_shared/bi.

import { formatRand } from '../money';
import { riskBand } from '../risk';
import { chargeRuleCents, priceCents } from '../wallet';
import { normaliseClaimCode } from '../claim-code';

/* eslint-disable @typescript-eslint/no-require-imports */
const backendPricing = require('../../../../../supabase/functions/_shared/bi/pricing.js');
const backendRisk = require('../../../../../supabase/functions/_shared/bi/risk.js');
const backendClaim = require('../../../../../supabase/functions/_shared/bi/claim-code.js');
/* eslint-enable @typescript-eslint/no-require-imports */

describe('parity with supabase/functions/_shared/bi', () => {
  it('formats rand the same way', () => {
    for (const c of [0, 1, 99, 100, 9900, 26000, 115000, 400000, 39820, 123456789, -1988]) {
      expect(formatRand(c)).toBe(backendPricing.formatRand(c));
    }
  });
  it('bands every score the same way', () => {
    for (let s = 0; s <= 26; s++) expect(riskBand(s)).toBe(backendRisk.riskBand(s));
  });
  it('prices and charges the same way', () => {
    const cases = [
      { tokensIn: 200000, tokensOut: 20000, audioSeconds: 600, rateIn: '0.20', rateOut: '0.50', rateMinute: '0.006', usdZar: '18.50', markup: '3.0' },
      { tokensIn: 12345, tokensOut: 4000, rateIn: '3', rateOut: '15', usdZar: '18.2', markup: '3' },
      { tokensIn: 0, tokensOut: 0, audioSeconds: 3600, rateIn: '0', rateOut: '0', rateMinute: '0.006', usdZar: '18.5' },
    ];
    for (const p of cases) expect(priceCents(p)).toBe(backendPricing.priceCents(p));
    for (const [e, a] of [[500, 600], [500, 625], [500, 626], [0, 0], [2109, 2276]]) {
      expect(chargeRuleCents(e, a)).toBe(backendPricing.chargeRuleCents(e, a));
    }
  });
  it('normalises claim codes the same way', () => {
    for (const raw of ['abcd-2345', ' KQ7M 2P9X ', 'abc', 'ABCDEFGHJKMNP', 'A1B2C3']) {
      expect(normaliseClaimCode(raw)).toBe(backendClaim.normaliseCode(raw));
    }
  });
});
