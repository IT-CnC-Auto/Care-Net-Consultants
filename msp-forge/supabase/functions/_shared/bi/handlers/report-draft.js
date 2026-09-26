// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | report-draft 26/09/2026
// POST (signed in inspector) {inspection_id, use_ai?, wallet_id?}
//   -> 200 {report_id, version, status: 'draft', label, voice_notes, voice_notes_line, content, ai}
//      402 {reason, estimate_cents} when the AI Wallet refuses the estimate
// Builds the report JSON from the capture (findings, photos, voice notes and
// their latest transcripts, risks, corrective actions) and saves it as a Draft
// version (bi_report_save_draft, 061). Every draft carries "Assistive draft.
// Competent person sign off required." and every legal claim a kernel reference;
// uncited claims are dropped into `uncited` for a person to resolve.
//
// AI (prompt B6) runs ONLY when use_ai is true AND XAI_API_KEY and
// XAI_MODEL_QUALITY are set: estimate from the AI Wallet first
// (bi_wallet_estimate), then one call to xAI's OpenAI compatible chat
// completions, then the charge on the actual tokens (bi_wallet_charge). No
// model name is written in any file (contract 8, 10.10). Without the settings
// the template draft is saved and the answer says AI is not connected. Kernel
// retrieval by embedding waits for {{kernel_source}} (P5); until then the
// kernel references are those of the template lines.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY; XAI_API_KEY, XAI_MODEL_QUALITY,
// XAI_BASE_URL (optional, default https://api.x.ai/v1).

import { v } from '../validate.js';
import { buildDraftSkeleton, enforceCitations, voicePreviewLine, DRAFT_LABEL, LOCKED_FOOTER } from '../report.js';
import { sha256HexText } from '../claim-code.js';
import { guarded, json, requireMethod, readJson, requireUser, createDb, supabaseDeps, HttpError } from '../http.js';

const Body = v.object({ inspection_id: v.uuid(), use_ai: v.boolean().optional(), wallet_id: v.uuid().optional() });
const OUTPUT_TOKENS = 4000;
const SYSTEM_PROMPT = [
  'You draft a South African health and safety inspection report for a competent person to review and sign.',
  'Use plain South African British English. Never say compliant. Never give medical or clinical opinions.',
  'Answer with JSON only: {"executive_summary": string, "claims": [{"text": string, "kernel_ref": string, "finding_id": string}]}.',
  'Every claim must cite one of the kernel_refs given to you; if none fits, leave the claim out.',
].join(' ');

async function load(db, id, userId) {
  const one = async (t, q) => (await db.select(t, q))[0] || null;
  const inspection = await one('bi_inspection', `select=*&id=eq.${id}`);
  if (!inspection) throw new HttpError(404, 'That inspection was not found.', 'not_found');
  // Nothing else is read (and nothing reaches the AI service) unless the caller
  // is an inspector of this company in this tenant.
  const roles = await db.rpc('bi_user_roles', { p_auth_user: userId, p_tenant: inspection.tenant_id, p_company: inspection.client_account_id });
  if (!Array.isArray(roles) || !roles.includes('inspector')) throw new HttpError(404, 'That inspection was not found.', 'not_found');
  const [template, templateItems, areas, findings, photos, risks, actions, voiceNotes] = await Promise.all([
    one('bi_template', `select=id,code,category,section_f_element_code&id=eq.${inspection.template_id}`),
    db.select('bi_template_item', `select=id,ordinal,prompt,kernel_ref&template_id=eq.${inspection.template_id}&order=ordinal`),
    db.select('bi_inspection_area', `select=id,label,ordinal&inspection_id=eq.${id}&order=ordinal`),
    db.select('bi_finding', `select=id,area_id,template_item_id,result,note,severity&inspection_id=eq.${id}&order=captured_at`),
    db.select('bi_photo', `select=id,finding_id,caption&inspection_id=eq.${id}`),
    db.select('bi_risk', `select=*&inspection_id=eq.${id}`),
    db.select('bi_corrective_action', `select=id,finding_id,description,owner_name,due_on,status&inspection_id=eq.${id}`),
    db.select('bi_voice_note', `select=id,finding_id,vn_number&inspection_id=eq.${id}&order=vn_number`),
  ]);
  const transcripts = voiceNotes.length
    ? await db.select('bi_voice_transcript', `select=voice_note_id,version,body&voice_note_id=in.(${voiceNotes.map((x) => x.id).join(',')})`)
    : [];
  return { inspection, template, templateItems, areas, findings, photos, risks, actions, voiceNotes, transcripts };
}

async function aiDraft(deps, db, user, body, skeleton, knownRefs) {
  const env = deps.env;
  if (!body.wallet_id) throw new HttpError(400, 'An AI draft needs the wallet it is paid from.', 'wallet_required');
  const prompt = JSON.stringify({ kernel_refs: knownRefs, draft: skeleton });
  const tokensIn = Math.ceil((SYSTEM_PROMPT.length + prompt.length) / 4);
  const est = await db.rpc('bi_wallet_estimate', {
    p_auth_user: user.id,
    p: { wallet_id: body.wallet_id, kind: 'ai_draft', model_code: 'ai_quality', tokens_in: tokensIn, tokens_out: OUTPUT_TOKENS,
         inspection_id: body.inspection_id, idempotency_key: 'draft:' + (await sha256HexText(body.inspection_id + ':' + prompt)).slice(0, 40) },
  });
  if (!est.allowed) throw new HttpError(402, 'The AI Wallet cannot pay for this draft.', 'wallet_refused', { reason: est.reason, estimate_cents: est.estimate_cents });
  const base = (env.XAI_BASE_URL || 'https://api.x.ai/v1').replace(/\/+$/, '');
  const res = await deps.fetch(`${base}/chat/completions`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.XAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: env.XAI_MODEL_QUALITY, max_tokens: OUTPUT_TOKENS, response_format: { type: 'json_object' },
      messages: [{ role: 'system', content: SYSTEM_PROMPT }, { role: 'user', content: prompt }] }),
  });
  if (!res.ok) throw new HttpError(502, 'The AI service did not answer. Nothing was charged.', 'ai_failed');
  const out = await res.json();
  let parsed = {};
  try { parsed = JSON.parse(out.choices[0].message.content); } catch { parsed = {}; }
  const usage = out.usage || {};
  const charge = await db.rpc('bi_wallet_charge', {
    p_usage_event_id: est.usage_event_id,
    p: { idempotency_key: 'charge:' + est.usage_event_id, tokens_in: usage.prompt_tokens | 0, tokens_out: usage.completion_tokens | 0 },
  });
  const merged = {
    ...skeleton,
    executive_summary: typeof parsed.executive_summary === 'string' ? parsed.executive_summary : skeleton.executive_summary,
    claims: skeleton.claims.concat(Array.isArray(parsed.claims) ? parsed.claims.filter((c) => c && typeof c.text === 'string') : []),
  };
  return { content: enforceCitations(merged, knownRefs), charge };
}

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  const sb = supabaseDeps(deps);
  const user = await requireUser(req, sb);
  const body = Body.parse(await readJson(req, 1024));
  const db = createDb(sb);
  const data = await load(db, body.inspection_id, user.id);
  const skeleton = buildDraftSkeleton(data);
  const knownRefs = [...new Set(data.templateItems.map((t) => t.kernel_ref).filter(Boolean))];

  const aiConfigured = Boolean(deps.env.XAI_API_KEY && deps.env.XAI_MODEL_QUALITY);
  let content = skeleton;
  let source = 'template';
  let ai = { used: false, reason: body.use_ai ? 'AI drafting is not connected (XAI_API_KEY and XAI_MODEL_QUALITY are not set).' : 'Not asked for.' };
  if (body.use_ai && aiConfigured) {
    const r = await aiDraft(deps, db, user, body, skeleton, knownRefs);
    content = r.content;
    source = 'ai_assistive';
    ai = { used: true, charged_cents: r.charge.charged_cents };
  }
  content = { ...content, label: DRAFT_LABEL, footer: LOCKED_FOOTER };
  const saved = await db.rpc('bi_report_save_draft', {
    p_auth_user: user.id, p_inspection_id: body.inspection_id, p_content: content, p_source: source, p_kernel_version_id: null,
  });
  return json({
    report_id: saved.report_id, version: saved.version, status: saved.status, label: DRAFT_LABEL,
    voice_notes: saved.voice_notes, voice_notes_line: voicePreviewLine(saved.voice_notes), content, ai,
  });
});
