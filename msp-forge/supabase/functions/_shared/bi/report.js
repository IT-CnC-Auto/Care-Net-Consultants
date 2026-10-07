// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | Bee-Inspect report JSON 26/09/2026
//
// The structured report a draft is built from (prompt B6), before the PDF
// (P5). Plain ES module; Deno and Node 22.
//
// Rules this module keeps, the same as migration 061:
//   1. Every draft carries the label "Assistive draft. Competent person sign
//      off required." and the locked footer line.
//   2. Every legal claim carries a kernel reference (claims[].kernel_ref) that
//      the retrieved kernel holds; a claim without one is dropped and listed
//      under uncited, never shipped.
//   3. Every voice note is footnoted (VN-n) and the preview says "Voice notes:
//      N accounted for, M missing".

import { describeRisk, heatMap } from './risk.js';

export const DRAFT_LABEL = 'Assistive draft. Competent person sign off required.';
export const LOCKED_FOOTER = 'This report is powered by Care Net Consultants Development House (Pty) Ltd';
export const RESULTS = Object.freeze(['pass', 'fail', 'na', 'observe']);
const RESULT_WORD = { pass: 'Pass', fail: 'Fail', na: 'N/A', observe: 'Observe' };

export function voiceCounts(voiceNotes, content) {
  const cited = new Set(((content && content.voice_note_index) || []).map((x) => Number(x && x.vn)).filter(Number.isInteger));
  const all = (voiceNotes || []).map((v) => v.vn_number).filter(Number.isInteger);
  const accounted = all.filter((n) => cited.has(n)).length;
  return { total: all.length, accounted, missing: all.length - accounted };
}

export function voicePreviewLine(counts) {
  return `Voice notes: ${counts.accounted} accounted for, ${counts.missing} missing`;
}

// Claims without a kernel reference the kernel holds (index and reference).
export function claimProblems(content, knownRefs) {
  const known = knownRefs ? new Set(knownRefs) : null;
  return ((content && content.claims) || [])
    .map((c, index) => ({ index, kernel_ref: c && c.kernel_ref }))
    .filter((c) => typeof c.kernel_ref !== 'string' || !c.kernel_ref.trim() || (known && !known.has(c.kernel_ref)));
}

// Keeps only cited claims; the rest are reported so a person can add the reference.
export function enforceCitations(content, knownRefs) {
  const bad = new Set(claimProblems(content, knownRefs).map((p) => p.index));
  const claims = (content.claims || []).filter((_, i) => !bad.has(i));
  const uncited = (content.claims || []).filter((_, i) => bad.has(i)).map((c) => (c && c.text) || '');
  return { ...content, claims, uncited: (content.uncited || []).concat(uncited) };
}

// The skeleton built from the capture alone (no AI): the template draft.
export function buildDraftSkeleton(data) {
  const { inspection, template, areas = [], findings = [], photos = [], risks = [], actions = [], voiceNotes = [], transcripts = [], templateItems = [] } = data;
  const itemById = new Map(templateItems.map((t) => [t.id, t]));
  const areaById = new Map(areas.map((a) => [a.id, a]));
  const latestTranscript = new Map();
  for (const t of transcripts) {
    const cur = latestTranscript.get(t.voice_note_id);
    if (!cur || t.version > cur.version) latestTranscript.set(t.voice_note_id, t);
  }
  const count = (r) => findings.filter((f) => f.result === r).length;
  const findingOut = findings.map((f) => {
    const item = itemById.get(f.template_item_id);
    return {
      finding_id: f.id,
      area: (areaById.get(f.area_id) || {}).label || null,
      item: item ? item.prompt : null,
      result: RESULT_WORD[f.result] || f.result,
      note: f.note || null,
      severity: f.severity || null,
      photos: photos.filter((p) => p.finding_id === f.id).map((p) => p.id),
      voice_notes: voiceNotes.filter((v) => v.finding_id === f.id).map((v) => 'VN-' + v.vn_number),
      kernel_ref: item && item.kernel_ref ? item.kernel_ref : null,
    };
  });
  const claims = [];
  const uncited = [];
  for (const f of findings.filter((x) => x.result === 'fail')) {
    const item = itemById.get(f.template_item_id);
    const text = item ? `Did not pass: ${item.prompt}.` : `A Fail finding${f.note ? ': ' + f.note : ''}.`;
    if (item && item.kernel_ref) claims.push({ text, kernel_ref: item.kernel_ref, finding_id: f.id });
    else uncited.push(text);
  }
  const content = {
    label: DRAFT_LABEL,
    footer: LOCKED_FOOTER,
    title: inspection.title,
    inspection_id: inspection.id,
    template_code: template ? template.code : null,
    section_f_element_code: template ? template.section_f_element_code : null,
    executive_summary: `${findings.length} checklist items recorded across ${areas.length} areas: ${count('pass')} Pass, ${count('fail')} Fail, ${count('observe')} Observe, ${count('na')} N/A.`,
    areas: areas.map((a) => ({ area_id: a.id, label: a.label })),
    findings: findingOut,
    risk_register: risks.map((r) => ({ risk_id: r.id, hazard: r.hazard, ...describeRisk(r) })),
    heat_map: { inherent: heatMap(risks, 'inherent'), residual: heatMap(risks, 'residual') },
    corrective_actions: actions.map((c) => ({ id: c.id, finding_id: c.finding_id, description: c.description, owner: c.owner_name, due_on: c.due_on, status: c.status })),
    claims,
    uncited,
    voice_note_index: voiceNotes
      .slice()
      .sort((a, b) => a.vn_number - b.vn_number)
      .map((v) => {
        const t = latestTranscript.get(v.id);
        return { vn: v.vn_number, finding_id: v.finding_id || null, transcript_version: t ? t.version : null, excerpt: t ? String(t.body).slice(0, 200) : null };
      }),
  };
  content.voice_notes = voiceCounts(voiceNotes, content);
  return content;
}
