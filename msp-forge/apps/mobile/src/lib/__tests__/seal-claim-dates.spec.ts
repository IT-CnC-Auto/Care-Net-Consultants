import { claimCodeFromScan, normaliseClaimCode } from '../claim-code';
import { addDaysIso, formatDate, formatDuration, parseSaDate } from '../dates';
import { evidencePath, sealCoord, sealInput, sealTime } from '../seal';

describe('evidence seal text (same as bi_evidence_seal)', () => {
  it('prints time in UTC with microseconds and coordinates with six decimals', () => {
    expect(sealTime('2026-09-26T07:03:00.123Z')).toBe('2026-09-26T07:03:00.123000Z');
    expect(sealTime('2026-09-26T09:03:00.123+02:00')).toBe('2026-09-26T07:03:00.123000Z');
    expect(sealCoord(-25.79)).toBe('-25.790000');
    expect(sealCoord(null)).toBe('');
  });
  it('joins the fields with a bar, keeping empty coordinates', () => {
    expect(
      sealInput({ path: 'c/i/p.jpg', sha256: 'ab', capturedAt: '2026-09-26T07:03:00.000Z', lat: null, lng: null, inspectorId: 'u1' }),
    ).toBe('c/i/p.jpg|ab|2026-09-26T07:03:00.000000Z|||u1');
  });
  it('makes a storage path the database accepts', () => {
    const p = evidencePath('b1a00000-0000-4000-8000-000000000002', 'b1a00000-0000-4000-8000-000000000081', 'photo 1 (bay).jpg');
    expect(p).toMatch(/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[A-Za-z0-9._-]{1,120}$/);
  });
});

describe('claim codes', () => {
  it('accepts 6 to 12 letters or digits in any case, ignoring spaces and dashes', () => {
    expect(normaliseClaimCode(' abcd-2345 ')).toBe('ABCD2345');
    expect(normaliseClaimCode('ABC12')).toBeNull();
    expect(normaliseClaimCode('ABCDEFGHJKMNP')).toBeNull();
    expect(normaliseClaimCode('ABC$1234')).toBeNull();
  });
  it('reads a code from the claim link in a QR', () => {
    expect(claimCodeFromScan('https://www.carenetconsultants.co.za/claim/kq7m2p9x')).toBe('KQ7M2P9X');
    expect(claimCodeFromScan('KQ7M2P9X')).toBe('KQ7M2P9X');
  });
});

describe('dates (dd/mm/yyyy)', () => {
  it('formats and parses South African dates', () => {
    expect(formatDate('2026-09-27')).toBe('27/09/2026');
    expect(parseSaDate('27/09/2026')).toBe('2026-09-27');
    expect(parseSaDate('31/02/2026')).toBeNull();
    expect(parseSaDate('2026-09-27')).toBeNull();
    expect(addDaysIso('2026-09-27', 7)).toBe('2026-10-04');
    expect(formatDuration(75)).toBe('1:15');
  });
});
