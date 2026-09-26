// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | docuseal-webhook 26/09/2026
// POST from DocuSeal when a Bee-Inspect report is signed there (prompt B7).
//   -> 200 {signed: true} | {signed: false, reason} | {ignored: true}
//      401 wrong secret; 501 not connected (DOCUSEAL_WEBHOOK_SECRET not set)
// The same shared secret check as vercel/api/docuseal-webhook.js (header
// x-docuseal-signature or x-webhook-secret). Only submissions Care Net created
// for a Bee-Inspect report carry metadata bi_report_id, bi_auth_user_id and
// bi_step_up_id (the signer's step up MFA recorded in the app before DocuSeal
// opened, prompt B3) and the signer's confirmations; anything else is ignored,
// so the File site's own DocuSeal flow is untouched. bi_report_sign (061)
// decides every rule again (cleared scope, step up within 24 hours for
// DocuSeal, confirmations). A delivery already recorded answers signed again
// without a second signature. A refusal answers 200 so DocuSeal does not retry
// forever; the reason is in the answer and the audit trail.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, DOCUSEAL_WEBHOOK_SECRET.

import { guarded, json, requireMethod, readJson, notImplemented, createDb, supabaseDeps, sameText, HttpError } from '../http.js';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  const secret = deps.env.DOCUSEAL_WEBHOOK_SECRET;
  if (!secret) return notImplemented('DocuSeal signing for Bee-Inspect', ['DOCUSEAL_WEBHOOK_SECRET']);
  const given = req.headers.get('x-docuseal-signature') || req.headers.get('x-webhook-secret') || '';
  if (!sameText(given, secret)) throw new HttpError(401, 'unauthorised', 'unauthorised');
  const body = await readJson(req, 262144);
  if (body.event_type !== 'submission.completed' && body.event_type !== 'form.completed') return json({ ignored: true, event_type: body.event_type || null });
  const data = body.data || {};
  const meta = data.metadata || (data.submission && data.submission.metadata) || {};
  if (!UUID_RE.test(meta.bi_report_id || '') || !UUID_RE.test(meta.bi_auth_user_id || '') || !UUID_RE.test(meta.bi_step_up_id || '')) {
    return json({ ignored: true, reason: 'not a Bee-Inspect submission' });
  }
  const ref = String(data.submission_id || (data.submission && data.submission.id) || data.id || '');
  if (!ref) throw new HttpError(400, 'No submission id.');
  const db = createDb(supabaseDeps(deps));
  const seen = await db.select('bi_signature', `select=id&docuseal_submission_ref=eq.${encodeURIComponent(ref)}&limit=1`);
  if (seen.length) return json({ signed: true, repeat: true });
  try {
    await db.rpc('bi_report_sign', {
      p_auth_user: meta.bi_auth_user_id,
      p_report_id: meta.bi_report_id,
      p: { step_up_id: meta.bi_step_up_id, channel: 'docuseal', docuseal_submission_ref: ref, device_integrity: 'unknown',
           confirm_photos: meta.bi_confirm_photos === true, confirm_voice_notes: meta.bi_confirm_voice_notes === true },
    });
  } catch (e) {
    if (e instanceof HttpError && e.status < 500) return json({ signed: false, reason: e.message });
    throw e;
  }
  return json({ signed: true });
});
