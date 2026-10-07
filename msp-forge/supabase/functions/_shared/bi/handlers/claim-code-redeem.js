// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | claim-code-redeem 26/09/2026
// POST (no sign in: the phone is not signed in yet) {code, device?}
//   -> 200 {ok: true, token_hash, type: 'magiclink', client_account_id, file_id}
//      400 invalid, 409 used, 410 expired, 429 too many attempts
// The phone scans the desktop QR (prompt B3). bi_claim_code_redeem (063) checks
// the SHA 256, the 10 minutes and single use, and rate limits per caller (the
// caller's address, hashed here and hashed again in the database, never
// stored). On success Supabase Auth issues a one time sign in token for the
// same account (admin generate_link); the app completes it with
// verifyOtp({ token_hash, type: 'magiclink' }). The email is never returned.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { v } from '../validate.js';
import { normaliseCode, hashCode, sha256HexText } from '../claim-code.js';
import { guarded, json, requireMethod, readJson, createDb, supabaseDeps } from '../http.js';

const Body = v.object({ code: v.string().max(24), device: v.string().max(120).optional() });
const REFUSAL = {
  invalid: [400, 'That code is not valid. Check it and try again.'],
  used: [409, 'That code has already been used. Make a new one on the computer.'],
  expired: [410, 'That code has expired. Make a new one on the computer.'],
  rate: [429, 'Too many attempts. Please wait a few minutes.'],
};

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  const sb = supabaseDeps(deps);
  const body = Body.parse(await readJson(req, 1024));
  const code = normaliseCode(body.code);
  if (!code) return json({ ok: false, reason: 'invalid', error: REFUSAL.invalid[1] }, 400);
  const caller = (req.headers.get('x-forwarded-for') || req.headers.get('cf-connecting-ip') || 'unknown').split(',')[0].trim();
  const db = createDb(sb);
  const r = await db.rpc('bi_claim_code_redeem', {
    p_code_hash: await hashCode(code),
    p: { caller_key: await sha256HexText('bi-claim:' + caller), device: body.device || null },
  });
  if (!r || r.ok !== true) {
    const [status, message] = REFUSAL[(r && r.reason) || 'invalid'] || REFUSAL.invalid;
    return json({ ok: false, reason: (r && r.reason) || 'invalid', error: message }, status);
  }
  const tokenHash = await db.generateMagicLinkHash(r.email);
  return json({ ok: true, token_hash: tokenHash, type: 'magiclink', client_account_id: r.client_account_id || null, file_id: r.file_id || null });
});
