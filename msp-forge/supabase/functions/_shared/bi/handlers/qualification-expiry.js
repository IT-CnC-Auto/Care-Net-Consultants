// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | qualification-expiry (cron) 26/09/2026
// POST (service role, daily) -> 200 {alerts, expired, restricted, notified, notify}
// bi_qualification_expiry_run (063): 60, 30 and 7 day alerts (each once), a
// lapsed qualification becomes expired and a cleared inspector restricted
// (prompt B4). The run is audited in the database. The alert messages (email,
// SMS, push) need {{email_platform}} and the SMS provider; until then the ids
// and thresholds are returned, never names or numbers.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY; EMAIL_PLATFORM, EMAIL_API_KEY (names only, pending).

import { guarded, json, requireMethod, requireService, createDb, supabaseDeps } from '../http.js';

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  requireService(req, deps.env);
  const r = await createDb(supabaseDeps(deps)).rpc('bi_qualification_expiry_run', {});
  const alerts = ((r && r.alerts) || []).map((a) => ({ qualification_id: a.id, app_user_id: a.app_user_id, threshold_days: a.threshold, days_left: a.days }));
  return json({ alerts, expired: ((r && r.expired) || []).length, restricted: (r && r.restricted) || [], notified: 0,
                notify: 'pending: the email platform is not chosen' });
});
