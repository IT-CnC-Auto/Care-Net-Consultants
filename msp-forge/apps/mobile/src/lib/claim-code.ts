// Claim codes (prompt B3): the one time code shown beside the desktop QR, 10
// minutes, single use. Same shape as supabase/functions/_shared/bi/claim-code.js
// and the claim page (6 to 12 letters or digits; spaces and dashes ignored;
// any case).

const SHAPE_RE = /^[A-Za-z0-9]{6,12}$/;

export function normaliseClaimCode(raw: string | null | undefined): string | null {
  if (typeof raw !== 'string') return null;
  const s = raw.trim().replace(/[\s-]/g, '');
  return SHAPE_RE.test(s) ? s.toUpperCase() : null;
}

/** A code from a scanned QR: the claim link https://…/claim/{code} or the bare code. */
export function claimCodeFromScan(data: string): string | null {
  const m = /\/claim\/([^/?#]+)/.exec(data);
  return normaliseClaimCode(m ? decodeURIComponent(m[1]) : data);
}
