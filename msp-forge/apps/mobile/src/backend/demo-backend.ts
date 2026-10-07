// The demonstration backend: no network, no Supabase project. It behaves like
// the P3 backend closely enough to walk every screen (sign in, MFA, claim code,
// capture, sync, AI draft with wallet rules, sign off, Issue to Section F) with
// the fictitious Rietvlei Civils and Building data. Nothing leaves the phone.

import type { DataStore } from '@/data/data-store';
import { normaliseClaimCode } from '@/lib/claim-code';
import { blobId, latestVersions } from '@/lib/evidence-store';
import { formatRand, TOP_UPS } from '@/lib/money';
import { AI_OUTPUT_TOKENS, buildDraftSkeleton, estimateTokensIn, voicePreviewLine } from '@/lib/report';
import { isSixDigitCode } from '@/lib/step-up';
import type { PushOutcome, SyncItem } from '@/lib/sync-queue';
import type { Company, Inspection, LedgerEntry, Report, VoiceNote } from '@/lib/types';
import { markChunkDone, newUpload, remainingChunks, verifyUpload, withSession } from '@/lib/upload-plan';
import { applyCharge, balanceFromLedger, chargeRuleCents, priceCents } from '@/lib/wallet';

import { DEMO, demoSeed } from './demo-seed';
import type { AuthState, Backend, DraftResult, Profile, SignInput, SignResult, TotpEnrolment } from './types';

/**
 * DEMONSTRATION rates only, so the preview shows realistic rand amounts. They
 * are not Care Net's rate card, which is still pending ({{rate_card}}); in live
 * mode every AI estimate answers rate_card_pending until ops confirms it.
 */
export const DEMO_RATES = { rateIn: '3.00', rateOut: '15.00', usdZar: '18.50', markup: '3.0' } as const;

interface DemoAuth {
  signedIn: boolean;
  aal: 'aal1' | 'aal2';
  totpEnrolled: boolean;
}

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class DemoBackend implements Backend {
  readonly mode = 'demo' as const;

  constructor(private readonly store: DataStore) {}

  private async auth(): Promise<DemoAuth> {
    const raw = await this.store.kvGet('demo.auth');
    return raw ? (JSON.parse(raw) as DemoAuth) : { signedIn: false, aal: 'aal1', totpEnrolled: false };
  }

  private async setAuth(a: Partial<DemoAuth>) {
    await this.store.kvSet('demo.auth', JSON.stringify({ ...(await this.auth()), ...a }));
  }

  async currentAuth(): Promise<AuthState | null> {
    const a = await this.auth();
    if (!a.signedIn) return null;
    return { userId: DEMO.inspectorAuth, email: DEMO.email, aal: a.aal, hasTotp: a.totpEnrolled };
  }

  onAuthChange(): () => void {
    return () => {};
  }

  async signInWithPassword(email: string, password: string): Promise<void> {
    await wait(300);
    if (!/^\S+@\S+\.\S+$/.test(email.trim())) throw new Error('Enter your email address.');
    if (password.length < 1) throw new Error('Enter your password.');
    await this.setAuth({ signedIn: true, aal: 'aal1' });
  }

  async sendEmailCode(email: string): Promise<void> {
    await wait(300);
    if (!/^\S+@\S+\.\S+$/.test(email.trim())) throw new Error('Enter your email address.');
  }

  async verifyEmailCode(_email: string, code: string): Promise<void> {
    await wait(300);
    if (!isSixDigitCode(code)) throw new Error('Enter the six digit code from the email.');
    await this.setAuth({ signedIn: true, aal: 'aal1' });
  }

  async redeemClaimCode(code: string): Promise<void> {
    await wait(400);
    if (!normaliseClaimCode(code)) throw new Error('That code is not valid. Check it and try again.');
    await this.setAuth({ signedIn: true, aal: 'aal1' });
  }

  async completeRedirect(): Promise<void> {
    await this.setAuth({ signedIn: true, aal: 'aal1' });
  }

  async enrolTotp(): Promise<TotpEnrolment> {
    await wait(200);
    return { factorId: 'demo-factor', qrSvg: null, secret: 'DEMO DEMO DEMO DEMO', uri: 'otpauth://totp/Bee-Inspect:demo?secret=DEMODEMODEMODEMO&issuer=Bee-Inspect' };
  }

  async verifyTotp(code: string): Promise<void> {
    await wait(300);
    if (!isSixDigitCode(code)) throw new Error('Enter the six digit code from your authenticator app.');
    await this.setAuth({ aal: 'aal2', totpEnrolled: true });
  }

  async recordStepUp(): Promise<'recorded'> {
    return 'recorded';
  }

  async signOut(): Promise<void> {
    await this.setAuth({ signedIn: false, aal: 'aal1' });
  }

  async loadProfile(store: DataStore): Promise<Profile> {
    // Seed once; a phone holding the earlier construction only demo is seeded again.
    if (!store.get('company', DEMO.company)?.industry_code) {
      await store.putServerMany(demoSeed());
    }
    return {
      appUserId: DEMO.inspector,
      tenantId: DEMO.tenant,
      companyId: DEMO.company,
      displayName: DEMO.name,
      roles: ['inspector'],
      voicePolicy: 'strict',
      walletId: DEMO.wallet,
    };
  }

  async push(item: SyncItem, store: DataStore): Promise<PushOutcome> {
    await wait(250);
    if (item.op === 'upload') {
      // The chunked, resumable upload as the server will run it (a simulation):
      // a session per blob, the chunks not yet sent, then the server's hash is
      // compared with the phone's. Bytes already held (dedupe) are not sent again.
      const rec = item.kind === 'photo' ? store.get('photo', item.recordId) : store.get('voice_note', item.recordId);
      if (!rec) return { kind: 'rejected', error: 'The file is no longer on this phone.' };
      const sha = 'sha256' in rec ? rec.sha256 : rec.audio_sha256;
      const company = store.get('inspection', rec.inspection_id)?.client_account_id ?? '';
      const blob = store.get('blob', blobId(company, sha));
      let u = rec._upload && rec._upload.sha256 === sha ? rec._upload : newUpload(sha, rec.size_bytes);
      if (!blob?.verified_at) {
        u = withSession(u, `demo-session-${sha.slice(0, 8)}`);
        for (const c of remainingChunks(u)) u = markChunkDone(u, c.index);
      }
      const v = verifyUpload(u, sha);
      if (!v.ok) return { kind: 'retry', error: v.state.last_error ?? 'Upload check failed.' };
      if (blob && !blob.verified_at) await store.putServer('blob', { ...blob, uploaded: true, verified_at: new Date().toISOString() });
      const patch: Record<string, unknown> = { _upload: v.state };
      if (item.kind === 'voice_note') {
        const vn = rec as VoiceNote;
        if (!vn.vn_number && !vn.supersedes_id) {
          const max = Math.max(0, ...store.where('voice_note', (x: VoiceNote) => x.inspection_id === vn.inspection_id).map((x) => x.vn_number ?? 0));
          patch.vn_number = max + 1;
        }
      }
      return { kind: 'ok', rowVersion: 1, patch };
    }
    return { kind: 'ok', rowVersion: item.op === 'update' ? (item.baseRowVersion ?? 1) + 1 : 1 };
  }

  private balance(store: DataStore, walletId: string): number {
    const rows = store.where('ledger', (l) => l.wallet_id === walletId).map((l) => ({ ...l, created_at: l.created_at ?? '' }));
    return balanceFromLedger(rows).availableCents;
  }

  async walletEstimate(p: { walletId: string; inspectionId: string; tokensIn: number; tokensOut: number; store: DataStore }) {
    await wait(350);
    const estimate = priceCents({ tokensIn: p.tokensIn, tokensOut: p.tokensOut, ...DEMO_RATES });
    const available = this.balance(p.store, p.walletId);
    const wallet = p.store.get('wallet', p.walletId);
    const reason = wallet?.status === 'frozen' ? 'wallet_frozen' : estimate > available ? 'wallet_empty' : null;
    return { estimate_cents: estimate, available_cents: available, allowed: reason === null, reason };
  }

  private bundle(store: DataStore, inspectionId: string) {
    const inspection = store.get('inspection', inspectionId) as Inspection;
    const voiceNotes = store.where('voice_note', (v) => v.inspection_id === inspectionId);
    const vnIds = new Set(voiceNotes.map((v) => v.id));
    return {
      inspection,
      template: store.get('template', inspection.template_id) ?? null,
      templateItems: store.where('template_item', (t) => t.template_id === inspection.template_id),
      areas: store.where('area', (a) => a.inspection_id === inspectionId).sort((a, b) => a.ordinal - b.ordinal),
      findings: store.where('finding', (f) => f.inspection_id === inspectionId),
      photos: latestVersions(store.where('photo', (x) => x.inspection_id === inspectionId)),
      voiceNotes: latestVersions(voiceNotes),
      transcripts: store.where('transcript', (t) => vnIds.has(t.voice_note_id)),
      risks: store.where('risk', (r) => r.inspection_id === inspectionId),
      actions: store.where('action', (a) => a.inspection_id === inspectionId),
    };
  }

  /** Spends the oldest expiring value first; a shortfall is carried by Care Net (decision 1.3). */
  private async charge(store: DataStore, walletId: string, chargeCents: number, estimateCents: number, actualCents: number, what: string): Promise<{ charged: number; shortfall: number }> {
    const now = Date.now();
    const rows = store.where('ledger', (l) => l.wallet_id === walletId);
    const lots = rows
      .filter((l) => l.amount_cents > 0 && l.expires_at && Date.parse(l.expires_at) > now)
      .map((l) => ({ lot: l, left: l.amount_cents + rows.filter((d) => d.lot_id === l.id).reduce((s, d) => s + d.amount_cents, 0) }))
      .filter((x) => x.left > 0)
      .sort((a, b) => Date.parse(a.lot.expires_at as string) - Date.parse(b.lot.expires_at as string));
    const available = lots.reduce((s, x) => s + x.left, 0);
    const { chargedCents, shortfallCents } = applyCharge(available, chargeCents);
    let remaining = chargedCents;
    for (const x of lots) {
      if (remaining <= 0) break;
      const take = Math.min(x.left, remaining);
      remaining -= take;
      const entry: LedgerEntry = { id: store.id(), wallet_id: walletId, entry_kind: 'charge', amount_cents: -take, lot_id: x.lot.id, expires_at: null, note: what, created_at: new Date().toISOString() };
      await store.putServer('ledger', entry);
    }
    if (shortfallCents > 0) {
      await store.putServer('subsidy', { id: store.id(), wallet_id: walletId, shortfall_cents: shortfallCents, estimate_cents: estimateCents, actual_cents: actualCents, what, created_at: new Date().toISOString() });
    }
    return { charged: chargedCents, shortfall: shortfallCents };
  }

  async reportDraft(p: { inspectionId: string; useAi: boolean; walletId: string | null; store: DataStore }): Promise<DraftResult> {
    await wait(700);
    const b = this.bundle(p.store, p.inspectionId);
    let content = buildDraftSkeleton(b);
    let aiUsed = false;
    let chargedCents: number | null = null;
    let aiNote = 'Template draft from your capture. No AI was used and nothing was charged.';
    if (p.useAi) {
      if (!p.walletId) throw new Error('An AI draft needs the wallet it is paid from.');
      const tokensIn = estimateTokensIn(content);
      const est = await this.walletEstimate({ walletId: p.walletId, inspectionId: p.inspectionId, tokensIn, tokensOut: AI_OUTPUT_TOKENS, store: p.store });
      if (!est.allowed) throw new Error('The AI Wallet cannot pay for this draft. Top up, or use the free template draft.');
      // A demonstration "actual": 93% of the estimate, then the charge rule.
      const actual = Math.round(est.estimate_cents * 0.93);
      const toCharge = chargeRuleCents(est.estimate_cents, actual);
      const c = await this.charge(p.store, p.walletId, toCharge, est.estimate_cents, actual, `AI draft, ${b.inspection.title}`);
      chargedCents = c.charged;
      aiUsed = true;
      const fails = b.findings.filter((f) => f.result === 'fail').length;
      content = {
        ...content,
        executive_summary:
          `Demonstration AI summary. The walk covered ${b.areas.length} areas and ${b.findings.length} checklist items. ` +
          `${fails} items did not pass and each has an owner and a due date in the corrective actions. ` +
          'The highest rated risk is falling objects from the second lift of bay 14; toe boards and a barricade bring it down. ' +
          'A competent person must review every finding, photo and voice note before signing.',
      };
      aiNote = `AI assisted draft. ${formatRand(c.charged)} was charged to the AI Wallet${c.shortfall > 0 ? `, and Care Net carried ${formatRand(c.shortfall)}` : ''}.`;
    }
    const existing = p.store.where('report', (r) => r.inspection_id === p.inspectionId && r.status !== 'withdrawn')[0];
    const report: Report = {
      id: existing?.id ?? p.store.id(),
      inspection_id: p.inspectionId,
      status: 'draft',
      version: (existing?.version ?? 0) + 1,
      source: aiUsed ? 'ai_assistive' : 'template',
      content,
      charged_cents: chargedCents,
      signed_by: null,
      signed_at: null,
      issued_at: null,
      file_link_status: null,
      section_f_element_code: b.template?.section_f_element_code ?? null,
      reviewer_requested_at: null,
      created_at: existing?.created_at ?? new Date().toISOString(),
    };
    await p.store.putServer('report', report);
    return { report, aiUsed, aiNote, chargedCents, voiceLine: voicePreviewLine(content.voice_notes) };
  }

  async requestReview(p: { reportId: string; store: DataStore }): Promise<Report> {
    const r = p.store.get('report', p.reportId) as Report;
    const next: Report = { ...r, status: 'awaiting_signoff', reviewer_requested_at: new Date().toISOString() };
    await p.store.putServer('report', next);
    return next;
  }

  async signAndIssue(p: SignInput): Promise<SignResult> {
    await wait(600);
    const r = p.store.get('report', p.reportId) as Report;
    const inspectionOf = p.store.get('inspection', r.inspection_id);
    const company = p.store.get('company', inspectionOf?.client_account_id ?? DEMO.company) as Company;
    const eligible = company.file_eligibility === 'eligible';
    const at = new Date().toISOString();
    const next: Report = { ...r, status: 'issued', signed_by: p.signerName, signed_at: at, issued_at: at, file_link_status: eligible ? 'linked' : 'awaiting_eligibility' };
    await p.store.putServer('report', next);
    const insp = p.store.get('inspection', r.inspection_id);
    if (insp && insp.status !== 'submitted') await p.store.putServer('inspection', { ...insp, status: 'submitted', submitted_at: at });
    return {
      report: next,
      filing: eligible
        ? `Filed into Section F of the free Health and Safety File (register ${r.section_f_element_code ?? 'Section F'}). The File's figure is updated.`
        : 'Stored, awaiting eligibility. It is listed in Section F and is filed into the free File when eligibility is confirmed.',
    };
  }

  async topUp(p: { code: (typeof TOP_UPS)[number]['code']; store: DataStore; walletId: string }): Promise<{ credited: boolean; message: string }> {
    await wait(500);
    const o = TOP_UPS.find((t) => t.code === p.code);
    if (!o) throw new Error('Unknown top up.');
    const now = new Date();
    await p.store.putServer('ledger', {
      id: p.store.id(), wallet_id: p.walletId, entry_kind: 'topup_credit', amount_cents: o.valueCents, lot_id: null,
      expires_at: new Date(now.getFullYear() + 1, now.getMonth(), now.getDate()).toISOString(),
      note: `Demonstration top up ${formatRand(o.priceCents)}${o.valueCents > o.priceCents ? ` (${formatRand(o.valueCents)} value)` : ''}`,
      created_at: now.toISOString(),
    });
    return { credited: true, message: `Demonstration top up: ${formatRand(o.valueCents)} added. No money moved.` };
  }
}
