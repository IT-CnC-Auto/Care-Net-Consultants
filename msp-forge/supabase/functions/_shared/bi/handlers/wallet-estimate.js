// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | wallet-estimate 26/09/2026
// POST (signed in inspector or company admin) {wallet_id, kind, model_code?, tokens_in?, tokens_out?,
//   audio_seconds?, photos?, report_id?, inspection_id?, idempotency_key}
//   -> 200 {usage_event_id, estimate_cents, estimate, available_cents, available, allowed, reason, free_photos, vat_mode}
// The cost preview before each AI action (prompt B8), always in rand, never
// tokens: bi_wallet_estimate (062) prices it, checks the spend cap and the
// balance and records it. Refusal reasons: rate_card_pending, wallet_empty,
// spend_cap, wallet_frozen. Idempotent on the key.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { v, IDEMPOTENCY_KEY_RE } from '../validate.js';
import { formatRand, VAT_MODE } from '../pricing.js';
import { guarded, json, requireMethod, readJson, requireUser, createDb, supabaseDeps } from '../http.js';

const count = () => v.int().min(0).max(50000000).optional();
export const Body = v.object({
  wallet_id: v.uuid(),
  kind: v.enum(['ai_draft', 'ai_tagging', 'transcription', 'photo_tag']),
  model_code: v.enum(['ai_fast', 'ai_quality', 'transcription']).optional(),
  tokens_in: count(),
  tokens_out: count(),
  audio_seconds: v.int().min(0).max(86400).optional(),
  photos: v.int().min(0).max(5000).optional(),
  report_id: v.uuid().optional(),
  inspection_id: v.uuid().optional(),
  idempotency_key: v.string().regex(IDEMPOTENCY_KEY_RE, 'must be 8 to 200 letters, digits or . : _ -'),
});

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  const sb = supabaseDeps(deps);
  const user = await requireUser(req, sb);
  const body = Body.parse(await readJson(req, 2048));
  const r = await createDb(sb).rpc('bi_wallet_estimate', { p_auth_user: user.id, p: body });
  return json({
    ...r,
    estimate: formatRand(r.estimate_cents),
    available: formatRand(r.available_cents),
    vat_mode: r.vat_mode || VAT_MODE,
  });
});
