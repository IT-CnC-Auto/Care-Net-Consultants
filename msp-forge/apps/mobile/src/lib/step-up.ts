// Step up MFA and the biometric unlock rules (prompt B3, decision 1.5).

import { FULL_MFA_EVERY_MS, STEP_UP_WINDOW_MS } from './constants';

export type StepUpPurpose = 'signoff' | 'issue' | 'bee_matched' | 'bulk_export' | 'topup_over_499';

export const STEP_UP_PURPOSE_TEXT: Record<StepUpPurpose, string> = {
  signoff: 'sign this report',
  issue: 'issue this report',
  bee_matched: 'engage a competent person',
  bulk_export: 'export in bulk',
  topup_over_499: 'top up more than R499,00',
};

/** Screens read the clock every few seconds, so a step up can look up to a minute "in the future". */
const CLOCK_SLACK_MS = 60 * 1000;

/** A step up is valid for 10 minutes in the app. */
export function isStepUpValid(lastStepUpAt: number | null | undefined, now: number, windowMs: number = STEP_UP_WINDOW_MS): boolean {
  return typeof lastStepUpAt === 'number' && lastStepUpAt - now <= CLOCK_SLACK_MS && now - lastStepUpAt < windowMs;
}

export function stepUpMinutesLeft(lastStepUpAt: number | null | undefined, now: number, windowMs: number = STEP_UP_WINDOW_MS): number {
  if (!isStepUpValid(lastStepUpAt, now, windowMs)) return 0;
  return Math.min(Math.round(windowMs / 60000), Math.ceil((windowMs - (now - (lastStepUpAt as number))) / 60000));
}

export type UnlockMode = 'none' | 'biometric' | 'full_mfa';

export interface UnlockInput {
  hasSession: boolean;
  /** The session already has a second factor for this launch (aal2 in memory). */
  mfaDoneThisLaunch: boolean;
  biometricEnabled: boolean;
  biometricAvailable: boolean;
  lastFullMfaAt: number | null;
  /** The install marker was missing: a reinstall (or first launch) with a session left in the keychain. */
  reinstalled: boolean;
  now: number;
}

/**
 * What the app asks for when it opens with a saved session: nothing, the
 * fingerprint or face (after a full MFA in the last 7 days), or the full MFA
 * again (after 7 days, after a reinstall, or when biometrics are not set up).
 */
export function unlockMode(i: UnlockInput): UnlockMode {
  if (!i.hasSession || i.mfaDoneThisLaunch) return 'none';
  if (i.reinstalled || i.lastFullMfaAt === null) return 'full_mfa';
  if (i.now - i.lastFullMfaAt >= FULL_MFA_EVERY_MS) return 'full_mfa';
  if (i.biometricEnabled && i.biometricAvailable) return 'biometric';
  return 'full_mfa';
}

export function isSixDigitCode(code: string): boolean {
  return /^\d{6}$/.test(code.trim());
}

/**
 * Sign in lockout and cool down on the phone (the server rate limits too):
 * after 5 failed attempts, wait 1 minute, doubling each further failure, at
 * most 15 minutes. Returns the time until which sign in is paused, or null.
 */
export function lockedUntil(failures: number, lastFailureAt: number | null): number | null {
  if (failures < 5 || lastFailureAt === null) return null;
  const wait = Math.min(15 * 60 * 1000, 60 * 1000 * 2 ** (failures - 5));
  return lastFailureAt + wait;
}
