// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | ncr-escalation (cron) 26/09/2026
// POST (service role, daily) -> 200 {escalated, by_level: {1, 2, 3}, notified, notify}
// bi_ncr_escalation_run (060): open corrective actions past due become overdue
// (level 1, the owner), after 7 days escalated to the company admin (level 2),
// after 14 days to Care Net ops (level 3). Messages wait for {{email_platform}}.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY; EMAIL_PLATFORM (name only, pending).

import { guarded, json, requireMethod, requireService, createDb, supabaseDeps } from '../http.js';

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  requireService(req, deps.env);
  const r = await createDb(supabaseDeps(deps)).rpc('bi_ncr_escalation_run', {});
  const moved = (r && r.escalated) || [];
  const byLevel = { 1: 0, 2: 0, 3: 0 };
  for (const m of moved) byLevel[m.escalation_level] = (byLevel[m.escalation_level] || 0) + 1;
  return json({ escalated: moved.length, by_level: byLevel, notified: 0, notify: 'pending: the email platform is not chosen' });
});
