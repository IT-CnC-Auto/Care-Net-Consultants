import { BAND_LABEL, heatMap, riskBand, riskScore, riskText, topControl, validateRisk } from '../risk';
import { canIssue, canStartInspection, expiryState, failRuleViolations, missingText, pathStepState, signerCleared } from '../gates';
import { isStepUpValid, lockedUntil, stepUpMinutesLeft, unlockMode } from '../step-up';
import type { Qualification } from '../types';

describe('risk bands (decision 1.2, locked)', () => {
  const expected: Record<number, string> = {};
  for (let s = 1; s <= 25; s++) expected[s] = s <= 4 ? 'low' : s <= 9 ? 'medium' : s <= 15 ? 'high' : 'extreme';
  it.each(Object.entries(expected))('score %s is %s', (score, band) => {
    expect(riskBand(Number(score))).toBe(band);
  });
  it('has no band outside 1 to 25', () => {
    expect(riskBand(0)).toBeNull();
    expect(riskBand(26)).toBeNull();
    expect(riskBand(4.5)).toBeNull();
  });
  it('always shows the number and the label', () => {
    expect(riskText(4)).toBe('4 Low');
    expect(riskText(5)).toBe('5 Medium');
    expect(riskText(15)).toBe('15 High');
    expect(riskText(16)).toBe('16 Extreme');
    expect(riskText(null)).toBe('Not rated');
    expect(Object.values(BAND_LABEL)).toEqual(['Low', 'Medium', 'High', 'Extreme']);
  });
  it('scores likelihood x severity only for 1 to 5', () => {
    expect(riskScore(4, 4)).toBe(16);
    expect(riskScore(0, 4)).toBeNull();
    expect(riskScore(6, 1)).toBeNull();
  });
  it('refuses a residual above the inherent risk', () => {
    expect(validateRisk({ hazard: 'Fall from height', inherent_likelihood: 3, inherent_severity: 4, residual_likelihood: 4, residual_severity: 4 })).toContain('The residual risk cannot be above the inherent risk.');
    expect(validateRisk({ hazard: 'Fall from height', inherent_likelihood: 3, inherent_severity: 4, residual_likelihood: 1, residual_severity: 4 })).toEqual([]);
    expect(validateRisk({ hazard: 'Fa', inherent_likelihood: null, inherent_severity: 2, residual_likelihood: 1 })).toHaveLength(3);
  });
  it('picks the highest control on the hierarchy and builds the heat map', () => {
    expect(topControl([{ level: 'ppe' }, { level: 'engineering' }])).toBe('engineering');
    const grid = heatMap([{ hazard: 'x', inherent_likelihood: 4, inherent_severity: 4 }]);
    expect(grid[3][3]).toBe(1);
  });
});

describe('gates', () => {
  it('Start Inspection needs the company Active and the inspector Cleared', () => {
    expect(canStartInspection('active', 'cleared').ok).toBe(true);
    const r = canStartInspection('in_review', 'fica');
    expect(r.ok).toBe(false);
    expect(r.reasons).toHaveLength(2);
    expect(canStartInspection('active', 'assistant_only').ok).toBe(false);
  });

  const today = '2026-09-27';
  const verified: Qualification = { id: 'q1', qual_type: 'CHSM', issuer: 'SACPCMP', number: 'X', issued_on: '2025-08-23', expires_on: '2027-08-23', status: 'verified', document_name: null };
  const base = { inspectorStatus: 'cleared' as const, scope: ['scaffolds'], category: 'scaffolds', qualifications: [verified], identityDone: true, ficaDone: true, deviceRooted: false, stepUpValid: true, today };

  it('Issue passes the dual gate when everything holds', () => {
    expect(canIssue(base)).toEqual({ ok: true, reasons: [] });
  });
  it('Issue is blocked on a rooted phone, without step up, out of scope or with an expired qualification', () => {
    expect(canIssue({ ...base, deviceRooted: true }).ok).toBe(false);
    expect(canIssue({ ...base, stepUpValid: false }).ok).toBe(false);
    expect(canIssue({ ...base, category: 'mining' }).ok).toBe(false);
    expect(canIssue({ ...base, ficaDone: false }).ok).toBe(false);
    expect(canIssue({ ...base, qualifications: [{ ...verified, expires_on: '2026-09-01' }] }).ok).toBe(false);
  });
  it('signerCleared matches bi_signer_cleared', () => {
    expect(signerCleared('cleared', ['fire'], 'fire', [verified], today)).toBe(true);
    expect(signerCleared('restricted', ['fire'], 'fire', [verified], today)).toBe(false);
    expect(signerCleared('cleared', ['fire'], 'fire', [{ ...verified, status: 'expired' }], today)).toBe(false);
  });
  it('flags expiry at 60, 30 and 7 days', () => {
    expect(expiryState('2026-12-31', today)).toBe('valid');
    expect(expiryState('2026-11-20', today)).toBe('due_60');
    expect(expiryState('2026-10-20', today)).toBe('due_30');
    expect(expiryState('2026-10-02', today)).toBe('due_7');
    expect(expiryState('2026-09-26', today)).toBe('expired');
    expect(expiryState(null, today)).toBe('no_expiry');
  });
  it('shows the inspector path', () => {
    expect(pathStepState('qualifications', 'identity')).toBe('done');
    expect(pathStepState('qualifications', 'qualifications')).toBe('current');
    expect(pathStepState('qualifications', 'competence_review')).toBe('todo');
    expect(pathStepState('cleared', 'competence_review')).toBe('done');
  });
});

describe('Fail rule (bi_fail_rule_violations)', () => {
  const findings = [
    { id: 'f1', result: 'fail' as const },
    { id: 'f2', result: 'fail' as const },
    { id: 'f3', result: 'pass' as const },
  ];
  it('needs a photo and a corrective action for every Fail', () => {
    const v = failRuleViolations({ findings, photos: [{ finding_id: 'f1' }], actions: [{ finding_id: 'f1' }], voiceNotes: [], policy: 'recommended' });
    expect(v).toEqual([{ finding_id: 'f2', missing: ['photo', 'corrective_action'] }]);
  });
  it('also needs a voice note under the Strict policy', () => {
    const v = failRuleViolations({ findings, photos: [{ finding_id: 'f1' }, { finding_id: 'f2' }], actions: [{ finding_id: 'f1' }, { finding_id: 'f2' }], voiceNotes: [{ finding_id: 'f1' }], policy: 'strict' });
    expect(v).toEqual([{ finding_id: 'f2', missing: ['voice_note'] }]);
    expect(missingText(['photo', 'corrective_action', 'voice_note'])).toBe('a photo, a corrective action and a voice note (Strict policy)');
  });
});

describe('step up and unlock (decision 1.5, prompt B3)', () => {
  const t0 = Date.parse('2026-09-27T10:00:00Z');
  it('is valid for 10 minutes', () => {
    expect(isStepUpValid(t0, t0 + 9 * 60000 + 59000)).toBe(true);
    expect(isStepUpValid(t0, t0 + 10 * 60000)).toBe(false);
    expect(isStepUpValid(null, t0)).toBe(false);
    expect(isStepUpValid(t0 + 1000, t0)).toBe(true);
    expect(isStepUpValid(t0 + 120000, t0)).toBe(false);
    expect(stepUpMinutesLeft(t0 + 1000, t0)).toBe(10);
    expect(stepUpMinutesLeft(t0, t0 + 60000)).toBe(9);
  });
  const base = { hasSession: true, mfaDoneThisLaunch: false, biometricEnabled: true, biometricAvailable: true, lastFullMfaAt: t0, reinstalled: false, now: t0 + 86400000 };
  it('offers biometric unlock within 7 days of a full MFA', () => {
    expect(unlockMode(base)).toBe('biometric');
  });
  it('asks for full MFA after 7 days, after a reinstall, or without biometrics', () => {
    expect(unlockMode({ ...base, now: t0 + 7 * 86400000 })).toBe('full_mfa');
    expect(unlockMode({ ...base, reinstalled: true })).toBe('full_mfa');
    expect(unlockMode({ ...base, biometricAvailable: false })).toBe('full_mfa');
    expect(unlockMode({ ...base, lastFullMfaAt: null })).toBe('full_mfa');
  });
  it('asks for nothing without a session or once MFA is done', () => {
    expect(unlockMode({ ...base, hasSession: false })).toBe('none');
    expect(unlockMode({ ...base, mfaDoneThisLaunch: true })).toBe('none');
  });
});

describe('sign in lockout', () => {
  it('pauses after five failures and doubles up to 15 minutes', () => {
    expect(lockedUntil(4, 1000)).toBeNull();
    expect(lockedUntil(5, 1000)).toBe(61000);
    expect(lockedUntil(6, 1000)).toBe(121000);
    expect(lockedUntil(20, 0)).toBe(15 * 60 * 1000);
  });
});
