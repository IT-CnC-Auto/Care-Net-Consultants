// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | autotopup-run (cron; gateway STUB) 26/09/2026
// POST (service role, schedule) -> 200 {due: 0} or 501 when wallets are due.
// bi_autotopup_queue (062) lists opted in wallets with a saved card whose
// balance is below R20,00, at most one attempt per wallet per hour, each with
// the idempotency key the gateway charge and the credit share. Charging a saved
// card needs {{saved_card_gateway}} (Ozow tokenisation if available, else
// Paystack), which is not chosen: nothing is charged and the answer says so.
// Once connected, a successful charge is credited with bi_iap_apply (provider
// saved_card, product auto_topup) and a failure is left for the next hour.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY; SAVED_CARD_GATEWAY, SAVED_CARD_API_KEY (names only).

import { guarded, json, requireMethod, requireService, createDb, supabaseDeps, notImplemented } from '../http.js';

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  requireService(req, deps.env);
  const r = await createDb(supabaseDeps(deps)).rpc('bi_autotopup_queue', { p_limit: 25 });
  const due = (r && r.due) || [];
  if (!due.length) return json({ due: 0, charged: 0 });
  return notImplemented('Automatic top up', ['SAVED_CARD_GATEWAY', 'SAVED_CARD_API_KEY'],
    `${due.length} wallet(s) were due for R99,00; none was charged because the saved card gateway is not chosen.`);
});
