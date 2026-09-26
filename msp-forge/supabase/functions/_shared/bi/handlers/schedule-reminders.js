// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | schedule-reminders (cron) 26/09/2026
// POST (service role, daily) -> 200 {reminders, overdue, recurring_created, notified, notify}
// bi_schedule_reminders_run (060): planned inspections due within three days
// (each reminded once), the overdue list, and the next inspection of every
// recurring series (prompt B5). Push and email need Expo push credentials and
// {{email_platform}}; until then the counts and ids are returned.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY; EXPO_ACCESS_TOKEN, EMAIL_PLATFORM (names only, pending).

import { guarded, json, requireMethod, requireService, createDb, supabaseDeps } from '../http.js';

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  requireService(req, deps.env);
  const r = await createDb(supabaseDeps(deps)).rpc('bi_schedule_reminders_run', {});
  return json({
    reminders: ((r && r.reminders) || []).map((x) => ({ inspection_id: x.id, inspector_user_id: x.inspector_user_id, scheduled_for: x.scheduled_for })),
    overdue: ((r && r.overdue) || []).length,
    recurring_created: (r && r.recurring_created) || 0,
    notified: 0,
    notify: 'pending: push and email are not connected',
  });
});
