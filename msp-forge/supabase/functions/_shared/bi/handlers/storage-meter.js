// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | storage-meter (cron) 26/09/2026
// POST (service role, schedule) -> 200 {lines_warned, warnings: [{tenant_id, client_account_id, level, pct}], notified, notify}
// bi_storage_meter_run (062) recomputes every company line (10 GB each) and
// returns the lines whose level rose (80%, 95%, full). At 100% the database
// already refuses new photos and voice notes. The warning messages need
// {{email_platform}}; until it is chosen they are returned, not sent.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY; EMAIL_PLATFORM, EMAIL_API_KEY (names only, pending).

import { guarded, json, requireMethod, requireService, createDb, supabaseDeps } from '../http.js';

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  requireService(req, deps.env);
  const r = await createDb(supabaseDeps(deps)).rpc('bi_storage_meter_run', {});
  const warnings = ((r && r.warnings) || []).map((w) => ({
    tenant_id: w.tenant_id, client_account_id: w.client_account_id, level: w.level, pct: w.status ? w.status.pct : null,
  }));
  return json({ lines_warned: warnings.length, warnings, notified: 0, notify: 'pending: the email platform is not chosen' });
});
