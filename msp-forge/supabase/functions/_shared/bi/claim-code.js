// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | Bee-Inspect claim codes 26/09/2026
//
// The desktop QR one time code (prompt B3). The Edge Function makes the code
// here and stores only its SHA 256 (bi_claim_code_create, migration 063); the
// code is shown once, expires in 10 minutes and is redeemed once. Plain ES
// module: crypto.getRandomValues and crypto.subtle only; Deno and Node 22.
//
// Shape: 8 characters from an alphabet without look alike characters (no 0, O,
// 1, I or L), inside the 6 to 12 letters or digits the claim page of P2 accepts
// (vercel/js/cnc-bee.js CLAIM_RE). The hash is of the upper case code, so the
// person may type it in any case.

export const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 8;
export const CLAIM_TTL_SECONDS = 600;
export const SHAPE_RE = /^[A-Za-z0-9]{6,12}$/;

// Rejection sampling: a byte is used only below the largest multiple of the
// alphabet size, so every character is equally likely.
export function generateCode(getRandomValues = (a) => globalThis.crypto.getRandomValues(a), length = CODE_LENGTH) {
  const limit = 256 - (256 % ALPHABET.length);
  let out = '';
  while (out.length < length) {
    const buf = getRandomValues(new Uint8Array(length * 2));
    for (const b of buf) {
      if (b < limit) out += ALPHABET[b % ALPHABET.length];
      if (out.length === length) break;
    }
  }
  return out;
}

export function normaliseCode(raw) {
  if (typeof raw !== 'string') return null;
  const s = raw.trim().replace(/[\s-]/g, '');
  return SHAPE_RE.test(s) ? s.toUpperCase() : null;
}

export async function sha256HexText(text) {
  const bytes = new TextEncoder().encode(text);
  const digest = await globalThis.crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

// The hash bi_claim_code stores and bi_claim_code_redeem looks up.
export async function hashCode(code) {
  const n = normaliseCode(code);
  if (!n) throw new RangeError('A claim code is 6 to 12 letters or digits.');
  return sha256HexText(n);
}

export function claimPath(code) {
  return '/claim/' + encodeURIComponent(code);
}
