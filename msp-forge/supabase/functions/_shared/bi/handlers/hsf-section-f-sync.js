// CNC HSF FORGE | BI-EDGE-01 v1.1.0 | hsf-section-f-sync 27/09/2026
// POST (service role) {report_id?} or {limit?}
//   -> 200 the filing of one report, or {processed, results, awaiting_eligibility} for the retry run
// An Issued report is filed into the company's free File automatically, in the
// same transaction that issues it (bi_hsf_section_f_sync, 061, replaced in 064),
// when the company is eligible for the free digital Safety File (contract
// 16.8); otherwise its link waits as awaiting_eligibility, with no evidence and
// no change to the compliance figure. This function is the retry: with
// report_id it files that report (idempotent); without, it files every Issued
// report still waiting (no File yet, or awaiting eligibility and now eligible).
// Schedule it hourly, or call it after a company builds its File or a verified
// medicals count is recorded.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { v } from '../validate.js';
import { guarded, json, requireMethod, readJson, requireService, createDb, supabaseDeps } from '../http.js';

const Body = v.object({ report_id: v.uuid().optional(), limit: v.int().min(1).max(200).optional() });

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  requireService(req, deps.env);
  const body = Body.parse(await readJson(req, 1024));
  const db = createDb(supabaseDeps(deps));
  if (body.report_id) return json(await db.rpc('bi_hsf_section_f_sync', { p_report_id: body.report_id }));
  return json(await db.rpc('bi_hsf_section_f_sync_pending', { p_limit: body.limit || 25 }));
});
