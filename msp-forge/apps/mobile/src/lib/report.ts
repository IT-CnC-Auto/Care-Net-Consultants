// The template draft built from the capture alone (no AI), the same shape as
// buildDraftSkeleton in supabase/functions/_shared/bi/report.js. Used by the
// demonstration mode and to size the AI cost preview; in live mode the
// report-draft Edge Function builds and stores the real draft.

import { DRAFT_LABEL, LOCKED_FOOTER } from './constants';
import { riskScore } from './risk';
import type { Area, CorrectiveAction, Finding, Inspection, Photo, ReportClaim, ReportContent, Risk, Template, TemplateItem, Transcript, VoiceNote } from './types';

const RESULT_WORD = { pass: 'Pass', fail: 'Fail', na: 'N/A', observe: 'Observe' } as const;

export interface CaptureBundle {
  inspection: Inspection;
  template: Template | null;
  templateItems: TemplateItem[];
  areas: Area[];
  findings: Finding[];
  photos: Photo[];
  voiceNotes: VoiceNote[];
  transcripts: Transcript[];
  risks: Risk[];
  actions: CorrectiveAction[];
}

export function voiceLabel(v: Pick<VoiceNote, 'vn_number'>): string {
  return v.vn_number ? `VN-${v.vn_number}` : 'VN (numbered on sync)';
}

export function voicePreviewLine(c: { accounted: number; missing: number }): string {
  return `Voice notes: ${c.accounted} accounted for, ${c.missing} missing`;
}

export function latestTranscripts(transcripts: readonly Transcript[]): Map<string, Transcript> {
  const m = new Map<string, Transcript>();
  for (const t of transcripts) {
    const cur = m.get(t.voice_note_id);
    if (!cur || t.version > cur.version) m.set(t.voice_note_id, t);
  }
  return m;
}

export function buildDraftSkeleton(b: CaptureBundle): ReportContent {
  const itemById = new Map(b.templateItems.map((t) => [t.id, t]));
  const areaById = new Map(b.areas.map((a) => [a.id, a]));
  const count = (r: Finding['result']) => b.findings.filter((f) => f.result === r).length;
  const claims: ReportClaim[] = [];
  const uncited: string[] = [];
  for (const f of b.findings.filter((x) => x.result === 'fail')) {
    const item = f.template_item_id ? itemById.get(f.template_item_id) : undefined;
    const text = item ? `Did not pass: ${item.prompt}.` : `A Fail finding${f.note ? ': ' + f.note : ''}.`;
    if (item?.kernel_ref) claims.push({ text, kernel_ref: item.kernel_ref, finding_id: f.id });
    else uncited.push(text);
  }
  const numbered = b.voiceNotes.filter((v) => typeof v.vn_number === 'number');
  return {
    label: DRAFT_LABEL,
    footer: LOCKED_FOOTER,
    title: b.inspection.title,
    executive_summary: `${b.findings.length} checklist items recorded across ${b.areas.length} areas: ${count('pass')} Pass, ${count('fail')} Fail, ${count('observe')} Observe, ${count('na')} N/A.`,
    findings: b.findings.map((f) => {
      const item = f.template_item_id ? itemById.get(f.template_item_id) : undefined;
      return {
        finding_id: f.id,
        area: areaById.get(f.area_id)?.label ?? null,
        item: item?.prompt ?? null,
        result: RESULT_WORD[f.result],
        note: f.note,
        photos: b.photos.filter((p) => p.finding_id === f.id).map((p) => p.id),
        voice_notes: b.voiceNotes.filter((v) => v.finding_id === f.id).map(voiceLabel),
        kernel_ref: item?.kernel_ref ?? null,
      };
    }),
    claims,
    uncited,
    // Every voice note of the inspection is footnoted in the voice note index, so
    // all numbered notes are accounted for; unnumbered ones wait for sync.
    voice_notes: { total: b.voiceNotes.length, accounted: numbered.length, missing: b.voiceNotes.length - numbered.length },
    corrective_actions: b.actions.map((c) => ({ id: c.id, description: c.description, owner: c.owner_name, due_on: c.due_on, status: c.status })),
    risk_register: b.risks.map((r) => ({
      risk_id: r.id,
      hazard: r.hazard,
      inherent: { score: riskScore(r.inherent_likelihood, r.inherent_severity) },
      residual: r.residual_likelihood ? { score: riskScore(r.residual_likelihood, r.residual_severity) } : null,
    })),
  };
}

/** A rough size of the AI prompt in tokens (four characters a token), as report-draft sizes it. */
export function estimateTokensIn(content: ReportContent): number {
  const SYSTEM_PROMPT_CHARS = 520;
  return Math.ceil((SYSTEM_PROMPT_CHARS + JSON.stringify(content).length) / 4);
}

export const AI_OUTPUT_TOKENS = 4000;
