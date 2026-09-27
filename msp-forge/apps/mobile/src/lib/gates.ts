// Who may do what, decided on the phone the same way the database decides it
// (the database always decides again). Prompt B4 and decisions section 2:
// Start Inspection needs the company Active and the inspector Cleared; Issue
// needs the dual gate (FICA or KYC, and a qualification) plus a cleared scope,
// a step up in the last 10 minutes and a device that is not rooted.

import type { CompanyStatus, FindingResult, InspectorStatus, Qualification, VoicePolicy } from './types';

export const COMPANY_STATUS_LABEL: Record<CompanyStatus, string> = {
  not_started: 'Not started',
  in_review: 'In review',
  active: 'Active',
  blocked: 'Blocked',
};

export const INSPECTOR_STATUS_LABEL: Record<InspectorStatus, string> = {
  identity: 'Identity',
  fica: 'FICA',
  qualifications: 'Qualifications',
  competence_review: 'Competence review',
  cleared: 'Cleared',
  restricted: 'Restricted',
  assistant_only: 'Assistant only',
};

/** The path shown to the inspector: four steps, then one outcome. */
export const INSPECTOR_PATH: readonly InspectorStatus[] = ['identity', 'fica', 'qualifications', 'competence_review'];
export const INSPECTOR_OUTCOMES: readonly InspectorStatus[] = ['cleared', 'restricted', 'assistant_only'];

export function pathStepState(current: InspectorStatus, step: InspectorStatus): 'done' | 'current' | 'todo' {
  if (INSPECTOR_OUTCOMES.includes(current)) return 'done';
  const ci = INSPECTOR_PATH.indexOf(current);
  const si = INSPECTOR_PATH.indexOf(step);
  if (si < ci) return 'done';
  return si === ci ? 'current' : 'todo';
}

export interface GateResult {
  ok: boolean;
  reasons: string[];
}

export function canStartInspection(company: CompanyStatus | null | undefined, inspector: InspectorStatus | null | undefined): GateResult {
  const reasons: string[] = [];
  if (company !== 'active') {
    reasons.push(`The company must be Active first. It is ${company ? COMPANY_STATUS_LABEL[company] : 'Not started'}.`);
  }
  if (inspector !== 'cleared') {
    reasons.push(`Your inspector status must be Cleared first. It is ${inspector ? INSPECTOR_STATUS_LABEL[inspector] : 'Identity'}.`);
  }
  return { ok: reasons.length === 0, reasons };
}

export type ExpiryState = 'valid' | 'due_60' | 'due_30' | 'due_7' | 'expired' | 'no_expiry';

/** Prompt B4: expiry alerts at 60, 30 and 7 days; expired becomes Restricted. Dates are yyyy-mm-dd. */
export function expiryState(expiresOn: string | null | undefined, today: string): ExpiryState {
  if (!expiresOn) return 'no_expiry';
  const days = Math.round((Date.parse(expiresOn + 'T00:00:00Z') - Date.parse(today + 'T00:00:00Z')) / 86400000);
  if (days < 0) return 'expired';
  if (days <= 7) return 'due_7';
  if (days <= 30) return 'due_30';
  if (days <= 60) return 'due_60';
  return 'valid';
}

export function expiryText(state: ExpiryState): string {
  switch (state) {
    case 'expired':
      return 'Expired';
    case 'due_7':
      return 'Expires within 7 days';
    case 'due_30':
      return 'Expires within 30 days';
    case 'due_60':
      return 'Expires within 60 days';
    case 'no_expiry':
      return 'No expiry date';
    default:
      return 'Valid';
  }
}

/** bi_signer_cleared: Cleared, the category in scope, and no expired qualification. */
export function signerCleared(status: InspectorStatus | null | undefined, scope: readonly string[], category: string | null | undefined, quals: readonly Qualification[], today: string): boolean {
  if (status !== 'cleared' || !category || !scope.includes(category)) return false;
  return !quals.some((q) => q.status === 'expired' || (q.status === 'verified' && q.expires_on !== null && q.expires_on < today));
}

export interface IssueInput {
  inspectorStatus: InspectorStatus | null | undefined;
  scope: readonly string[];
  category: string | null | undefined;
  qualifications: readonly Qualification[];
  identityDone: boolean;
  ficaDone: boolean;
  deviceRooted: boolean;
  stepUpValid: boolean;
  today: string;
}

/** Everything that must be true before a signature can make a report Issued. */
export function canIssue(i: IssueInput): GateResult {
  const reasons: string[] = [];
  if (i.deviceRooted) reasons.push('This phone looks rooted or jailbroken. Issue is blocked on it.');
  if (!i.identityDone || !i.ficaDone) reasons.push('Your identity and FICA checks must be complete (dual gate).');
  const hasValidQual = i.qualifications.some((q) => q.status === 'verified' && (q.expires_on === null || q.expires_on >= i.today));
  if (!hasValidQual) reasons.push('A verified qualification that has not expired is needed (dual gate).');
  if (!signerCleared(i.inspectorStatus, i.scope, i.category, i.qualifications, i.today)) {
    reasons.push('You are not cleared to sign this kind of inspection. Find a competent person to review and sign it.');
  }
  if (!i.stepUpValid) reasons.push('Confirm it is you with your authenticator code (valid for 10 minutes).');
  return { ok: reasons.length === 0, reasons };
}

export type FailMissing = 'photo' | 'corrective_action' | 'voice_note';

export interface FailViolation {
  finding_id: string;
  missing: FailMissing[];
}

/**
 * bi_fail_rule_violations: every Fail finding needs a photo and a corrective
 * action, and a voice note too under the Strict policy.
 */
export function failRuleViolations(input: {
  findings: readonly { id: string; result: FindingResult }[];
  photos: readonly { finding_id: string | null }[];
  actions: readonly { finding_id: string | null }[];
  voiceNotes: readonly { finding_id: string | null }[];
  policy: VoicePolicy;
}): FailViolation[] {
  const has = (rows: readonly { finding_id: string | null }[], id: string) => rows.some((r) => r.finding_id === id);
  const out: FailViolation[] = [];
  for (const f of input.findings) {
    if (f.result !== 'fail') continue;
    const missing: FailMissing[] = [];
    if (!has(input.photos, f.id)) missing.push('photo');
    if (!has(input.actions, f.id)) missing.push('corrective_action');
    if (input.policy === 'strict' && !has(input.voiceNotes, f.id)) missing.push('voice_note');
    if (missing.length) out.push({ finding_id: f.id, missing });
  }
  return out;
}

export const MISSING_TEXT: Record<FailMissing, string> = {
  photo: 'a photo',
  corrective_action: 'a corrective action',
  voice_note: 'a voice note (Strict policy)',
};

export function missingText(missing: readonly FailMissing[]): string {
  const parts = missing.map((m) => MISSING_TEXT[m]);
  if (parts.length <= 1) return parts.join('');
  return parts.slice(0, -1).join(', ') + ' and ' + parts[parts.length - 1];
}
