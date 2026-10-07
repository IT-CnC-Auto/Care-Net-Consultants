// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | wallet-charge 26/09/2026
// POST (service role only) {usage_event_id, idempotency_key, tokens_in?, tokens_out?, audio_seconds?}
//   -> 200 {estimate_cents, actual_cents, charged_cents, shortfall_cents, available_cents, charged, repeat}
// Charges an estimated AI action with its actual quantities (prompt B8):
// bi_wallet_charge (062) charges the actual, or the estimate when the actual is
// more than 25% above it, oldest expiring value first. Idempotent: the same key
// returns the first result; another key on a charged event is refused (409).
// Called by the other Bee-Inspect functions after the AI call, never by an app.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { v, IDEMPOTENCY_KEY_RE } from '../validate.js';
import { formatRand } from '../pricing.js';
import { guarded, json, requireMethod, readJson, requireService, createDb, supabaseDeps } from '../http.js';

export const Body = v.object({
  usage_event_id: v.uuid(),
  idempotency_key: v.string().regex(IDEMPOTENCY_KEY_RE, 'must be 8 to 200 letters, digits or . : _ -'),
  tokens_in: v.int().min(0).optional(),
  tokens_out: v.int().min(0).optional(),
  audio_seconds: v.int().min(0).optional(),
});

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  requireService(req, deps.env);
  const sb = supabaseDeps(deps);
  const body = Body.parse(await readJson(req, 1024));
  const { usage_event_id, ...p } = body;
  const r = await createDb(sb).rpc('bi_wallet_charge', { p_usage_event_id: usage_event_id, p });
  return json({ ...r, charged: formatRand(r.charged_cents), available: formatRand(r.available_cents) });
});
