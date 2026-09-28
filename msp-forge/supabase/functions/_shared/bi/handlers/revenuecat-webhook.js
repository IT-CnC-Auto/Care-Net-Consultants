// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | revenuecat-webhook 26/09/2026
// POST from RevenueCat (store subscriptions and AI Wallet top ups, prompt B2 and B8).
//   -> 200 {received: true, status}   recorded (applied, rejected or a repeat)
//      401                             the Authorization header does not match
//      501                             not connected: REVENUECAT_WEBHOOK_AUTH is not set
// RevenueCat sends the Authorization header value configured on its webhook;
// it is compared here in constant time with REVENUECAT_WEBHOOK_AUTH. Each event
// is applied once per event id (bi_iap_apply, 062), so a retried delivery
// changes nothing. The store product ids are mapped to rate card codes by
// BI_RC_PRODUCT_MAP (JSON, set once the products exist in the stores); an
// unmapped product is recorded as rejected, never guessed. The app sets the
// RevenueCat app user id to the Supabase user id and the subscriber attribute
// bi_client_account_id to the company a plan is bought for.
// STUB PARTS: the product map and the store accounts do not exist yet.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, REVENUECAT_WEBHOOK_AUTH, BI_RC_PRODUCT_MAP.

import { guarded, json, requireMethod, notImplemented, createDb, supabaseDeps, sameText, HttpError } from '../http.js';
import { sha256HexText } from '../claim-code.js';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function mapEvent(event, productMap) {
  const product = event.product_id && Object.prototype.hasOwnProperty.call(productMap, event.product_id)
    ? productMap[event.product_id] : 'unmapped';
  const attr = event.subscriber_attributes && event.subscriber_attributes.bi_client_account_id;
  const company = attr && typeof attr.value === 'string' && UUID_RE.test(attr.value) ? attr.value : null;
  return {
    provider: 'revenuecat',
    event_id: String(event.id),
    event_type: String(event.type || 'unknown'),
    auth_user_id: typeof event.app_user_id === 'string' && UUID_RE.test(event.app_user_id) ? event.app_user_id : null,
    product_code: product,
    client_account_id: company,
    period_start: Number.isFinite(event.purchased_at_ms) ? new Date(event.purchased_at_ms).toISOString().slice(0, 10) : null,
  };
}

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  const secret = deps.env.REVENUECAT_WEBHOOK_AUTH;
  if (!secret) return notImplemented('The RevenueCat webhook', ['REVENUECAT_WEBHOOK_AUTH', 'BI_RC_PRODUCT_MAP']);
  if (!sameText(req.headers.get('Authorization') || '', secret)) throw new HttpError(401, 'unauthorised', 'unauthorised');
  const raw = await req.text();
  if (raw.length > 65536) throw new HttpError(413, 'The request is too large.');
  let body;
  try { body = JSON.parse(raw); } catch { throw new HttpError(400, 'The body must be JSON.'); }
  const event = body && body.event;
  if (!event || !event.id) throw new HttpError(400, 'No event in the body.');
  if (event.type === 'TEST') return json({ received: true, status: 'ignored' });
  let productMap = {};
  try { productMap = JSON.parse(deps.env.BI_RC_PRODUCT_MAP || '{}'); } catch { productMap = {}; }
  const p = { ...mapEvent(event, productMap), payload_sha256: await sha256HexText(raw) };
  const r = await createDb(supabaseDeps(deps)).rpc('bi_iap_apply', { p });
  return json({ received: true, status: r.status, repeat: !!r.repeat });
});
