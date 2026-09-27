// What the app needs from a backend. Two implementations: the demonstration
// backend (no network, seeded fictitious data) and the Supabase backend (the
// same Supabase project as the File, the P3 Edge Functions and tables).

import type { DataStore } from '@/data/data-store';
import type { StepUpPurpose } from '@/lib/step-up';
import type { PushOutcome, SyncItem } from '@/lib/sync-queue';
import type { Report, VoicePolicy } from '@/lib/types';
import type { EstimateResult } from '@/lib/wallet';
import type { TopUpCode } from '@/lib/money';

export type Mode = 'demo' | 'live';

export interface AuthState {
  userId: string;
  email: string | null;
  aal: 'aal1' | 'aal2';
  /** A verified TOTP factor exists (the next level is aal2). */
  hasTotp: boolean;
}

export interface Profile {
  appUserId: string;
  tenantId: string;
  companyId: string;
  displayName: string;
  roles: string[];
  voicePolicy: VoicePolicy;
  walletId: string | null;
}

export interface TotpEnrolment {
  factorId: string;
  /** The QR code as SVG markup (Supabase returns it as an SVG data URI). */
  qrSvg: string | null;
  secret: string;
  uri: string;
}

export interface DraftResult {
  report: Report;
  aiUsed: boolean;
  aiNote: string;
  chargedCents: number | null;
  voiceLine: string;
}

export interface SignInput {
  reportId: string;
  signerName: string;
  signaturePath: string;
  reviewedPhotos: boolean;
  reviewedVoiceNotes: boolean;
  store: DataStore;
}

export interface SignResult {
  report: Report;
  /** Plain words about where the Issued report went (Section F or awaiting eligibility). */
  filing: string;
}

/** Raised when a server function the app needs is not deployed yet (a labelled stub). */
export class NotConnectedError extends Error {
  constructor(
    readonly what: string,
    message?: string,
  ) {
    super(message ?? `${what} is not connected yet.`);
    this.name = 'NotConnectedError';
  }
}

export interface Backend {
  readonly mode: Mode;
  currentAuth(): Promise<AuthState | null>;
  onAuthChange(cb: () => void): () => void;
  signInWithPassword(email: string, password: string): Promise<void>;
  sendEmailCode(email: string): Promise<void>;
  verifyEmailCode(email: string, code: string): Promise<void>;
  redeemClaimCode(code: string): Promise<void>;
  completeRedirect(params: Record<string, string | undefined>): Promise<void>;
  enrolTotp(): Promise<TotpEnrolment>;
  /** Challenge and verify a TOTP code; lifts the session to aal2. */
  verifyTotp(code: string, factorId?: string): Promise<void>;
  recordStepUp(purpose: StepUpPurpose): Promise<'recorded' | 'not_connected'>;
  signOut(): Promise<void>;

  /** Loads the person's profile and the server owned rows into the store. */
  loadProfile(store: DataStore): Promise<Profile>;
  push(item: SyncItem, store: DataStore): Promise<PushOutcome>;
  walletEstimate(p: { walletId: string; inspectionId: string; tokensIn: number; tokensOut: number; store: DataStore }): Promise<EstimateResult>;
  reportDraft(p: { inspectionId: string; useAi: boolean; walletId: string | null; store: DataStore }): Promise<DraftResult>;
  requestReview(p: { reportId: string; store: DataStore }): Promise<Report>;
  signAndIssue(p: SignInput): Promise<SignResult>;
  topUp(p: { code: TopUpCode; store: DataStore; walletId: string }): Promise<{ credited: boolean; message: string }>;
}
