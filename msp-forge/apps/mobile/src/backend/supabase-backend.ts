// The live backend: Supabase Auth (email and password, email code or link,
// TOTP MFA), PostgREST under the bi_ RLS policies for capture rows, and the P3
// Edge Functions (claim-code-redeem, wallet-estimate, report-draft).
//
// NOT EXERCISED against a live project in P4: migrations 059 to 063 are not
// applied anywhere but the local replay (contract 16.8). Every server piece the
// app needs that P3 did not build is a labelled stub here and in
// docs/bee-inspect/p4/index.md: step-up-record, evidence-upload-url,
// account-update, report-request-signoff, report-sign, and the RevenueCat
// products.

import { FunctionsFetchError, FunctionsHttpError, FunctionsRelayError, type SupabaseClient } from '@supabase/supabase-js';
import * as Linking from 'expo-linking';

import type { DataStore } from '@/data/data-store';
import { readBytes } from '@/features/evidence';
import { normaliseClaimCode } from '@/lib/claim-code';
import { voicePreviewLine } from '@/lib/report';
import type { StepUpPurpose } from '@/lib/step-up';
import { classifyMissedUpdate, stripLocal, type PushOutcome, type SyncItem } from '@/lib/sync-queue';
import { TABLE_OF, type Kind, type KindMap, type Report, type ReportContent } from '@/lib/types';
import type { EstimateResult } from '@/lib/wallet';

import { classifyPushError } from './pg-errors';
import { getSupabase } from './supabase-client';
import { NotConnectedError, type AuthState, type Backend, type DraftResult, type Profile, type SignResult, type TotpEnrolment } from './types';

type Row = Record<string, unknown>;

async function functionError(error: unknown): Promise<{ status: number | null; message: string; body: Row | null }> {
  if (error instanceof FunctionsHttpError) {
    const res = error.context as Response | undefined;
    let body: Row | null = null;
    try {
      body = res ? ((await res.clone().json()) as Row) : null;
    } catch {
      body = null;
    }
    return { status: res?.status ?? null, message: (body?.error as string) || error.message, body };
  }
  if (error instanceof FunctionsRelayError || error instanceof FunctionsFetchError) {
    return { status: null, message: 'The server could not be reached. Check your signal and try again.', body: null };
  }
  return { status: null, message: error instanceof Error ? error.message : 'Something went wrong.', body: null };
}

function svgFromDataUri(uri: string | null | undefined): string | null {
  if (!uri) return null;
  if (uri.startsWith('<svg')) return uri;
  const i = uri.indexOf(',');
  if (i < 0) return null;
  const payload = uri.slice(i + 1);
  try {
    return uri.slice(0, i).includes('base64') ? atob(payload) : decodeURIComponent(payload);
  } catch {
    return payload;
  }
}

export class SupabaseBackend implements Backend {
  readonly mode = 'live' as const;
  private readonly sb: SupabaseClient = getSupabase();

  async currentAuth(): Promise<AuthState | null> {
    const { data } = await this.sb.auth.getSession();
    const session = data.session;
    if (!session) return null;
    const { data: aal } = await this.sb.auth.mfa.getAuthenticatorAssuranceLevel();
    return {
      userId: session.user.id,
      email: session.user.email ?? null,
      aal: aal?.currentLevel === 'aal2' ? 'aal2' : 'aal1',
      hasTotp: aal?.nextLevel === 'aal2',
    };
  }

  onAuthChange(cb: () => void): () => void {
    const { data } = this.sb.auth.onAuthStateChange(() => cb());
    return () => data.subscription.unsubscribe();
  }

  async signInWithPassword(email: string, password: string): Promise<void> {
    const { error } = await this.sb.auth.signInWithPassword({ email: email.trim(), password });
    if (error) throw new Error(error.status === 429 ? 'Too many attempts. Please wait a few minutes.' : 'That email and password do not match.');
  }

  async sendEmailCode(email: string): Promise<void> {
    const { error } = await this.sb.auth.signInWithOtp({
      email: email.trim(),
      options: { shouldCreateUser: false, emailRedirectTo: Linking.createURL('auth-callback') },
    });
    if (error) throw new Error(error.status === 429 ? 'Too many attempts. Please wait a few minutes.' : 'The email could not be sent. Check the address.');
  }

  async verifyEmailCode(email: string, code: string): Promise<void> {
    const { error } = await this.sb.auth.verifyOtp({ email: email.trim(), token: code.trim(), type: 'email' });
    if (error) throw new Error('That code is not valid or has expired.');
  }

  async redeemClaimCode(code: string): Promise<void> {
    const n = normaliseClaimCode(code);
    if (!n) throw new Error('That code is not valid. Check it and try again.');
    const { data, error } = await this.sb.functions.invoke('claim-code-redeem', { body: { code: n, device: 'Bee-Inspect phone app' } });
    if (error) throw new Error((await functionError(error)).message);
    const tokenHash = (data as Row | null)?.token_hash;
    if (typeof tokenHash !== 'string') throw new Error('Sign in could not be completed.');
    const { error: e2 } = await this.sb.auth.verifyOtp({ token_hash: tokenHash, type: 'magiclink' });
    if (e2) throw new Error('Sign in could not be completed. Make a new code on the computer.');
  }

  async completeRedirect(params: Record<string, string | undefined>): Promise<void> {
    if (params.code) {
      const { error } = await this.sb.auth.exchangeCodeForSession(params.code);
      if (error) throw new Error('That sign in link has expired. Ask for a new one.');
    } else if (params.token_hash && params.type) {
      const { error } = await this.sb.auth.verifyOtp({ token_hash: params.token_hash, type: params.type as 'magiclink' | 'email' });
      if (error) throw new Error('That sign in link has expired. Ask for a new one.');
    } else {
      throw new Error('That sign in link is not complete.');
    }
  }

  async enrolTotp(): Promise<TotpEnrolment> {
    const { data: list } = await this.sb.auth.mfa.listFactors();
    for (const f of list?.all ?? []) {
      if (f.factor_type === 'totp' && f.status !== 'verified') await this.sb.auth.mfa.unenroll({ factorId: f.id });
    }
    const { data, error } = await this.sb.auth.mfa.enroll({ factorType: 'totp', friendlyName: `Bee-Inspect ${new Date().toISOString().slice(0, 10)}` });
    if (error || !data) throw new Error('The authenticator could not be set up. Try again.');
    return { factorId: data.id, qrSvg: svgFromDataUri(data.totp.qr_code), secret: data.totp.secret, uri: data.totp.uri };
  }

  async verifyTotp(code: string, factorId?: string): Promise<void> {
    let id = factorId;
    if (!id) {
      const { data } = await this.sb.auth.mfa.listFactors();
      id = data?.totp?.[0]?.id;
    }
    if (!id) throw new Error('No authenticator is set up on this account yet.');
    const { error } = await this.sb.auth.mfa.challengeAndVerify({ factorId: id, code: code.trim() });
    if (error) throw new Error(error.status === 429 ? 'Too many attempts. Please wait a few minutes.' : 'That code is not valid. Check the time on your phone and try again.');
  }

  async recordStepUp(purpose: StepUpPurpose): Promise<'recorded' | 'not_connected'> {
    // STUB until the step-up-record Edge Function (around bi_step_up_record) exists.
    const { error } = await this.sb.functions.invoke('step-up-record', { body: { purpose } });
    if (!error) return 'recorded';
    const e = await functionError(error);
    if (e.status === 404 || e.status === 501) return 'not_connected';
    throw new Error(e.message);
  }

  async signOut(): Promise<void> {
    await this.sb.auth.signOut();
  }

  private async select(table: string, build: (q: ReturnType<SupabaseClient['from']>) => PromiseLike<{ data: unknown; error: { code?: string; message: string } | null }>): Promise<Row[]> {
    const { data, error } = await build(this.sb.from(table));
    if (error) {
      if (error.code === 'PGRST205' || error.code === '42P01') {
        throw new NotConnectedError('Bee-Inspect tables', 'Bee-Inspect is not switched on for your account on the server yet. Try the demo meanwhile.');
      }
      throw new Error(`Your Bee-Inspect details could not be loaded (${error.code ?? 'error'}).`);
    }
    return (Array.isArray(data) ? data : data ? [data] : []) as Row[];
  }

  async loadProfile(store: DataStore): Promise<Profile> {
    const { data: sess } = await this.sb.auth.getSession();
    const uid = sess.session?.user.id;
    if (!uid) throw new Error('Please sign in again.');
    const [me] = await this.select('bi_app_user', (q) => q.select('id,tenant_id,display_name,email').eq('auth_user_id', uid).limit(1));
    if (!me) throw new Error('This account has no Bee-Inspect profile yet. Ask a Care Net sales executive to set you up, or try the demo.');
    const appUserId = String(me.id);
    const tenantId = String(me.tenant_id);
    const roles = await this.select('bi_role_assignment', (q) => q.select('role,client_account_id').eq('app_user_id', appUserId).is('revoked_at', null));
    const [tenant] = await this.select('bi_tenant', (q) => q.select('voice_note_policy').eq('id', tenantId).limit(1));
    let companyId = (roles.find((r) => r.client_account_id)?.client_account_id as string | undefined) ?? null;
    if (!companyId) {
      const subs = await this.select('bi_company_subscription', (q) => q.select('client_account_id').eq('tenant_id', tenantId).eq('status', 'active').limit(1));
      companyId = (subs[0]?.client_account_id as string | undefined) ?? null;
    }
    if (!companyId) throw new Error('Your tenant has no live Bee-Inspect line on a company yet.');

    const pending = new Set(store.getQueue().map((q) => q.recordId));
    const rows: { kind: Kind; record: KindMap[Kind] }[] = [];
    const put = <K extends Kind>(kind: K, record: KindMap[K]) => {
      if (!pending.has(record.id)) rows.push({ kind, record });
    };

    const [prof] = await this.select('bi_inspector_profile', (q) => q.select('status,competence_scope,restricted_reason,liveness_passed_at').eq('app_user_id', appUserId).limit(1));
    put('inspector', {
      id: appUserId,
      display_name: String(me.display_name),
      status: (prof?.status as KindMap['inspector']['status']) ?? 'identity',
      competence_scope: (prof?.competence_scope as string[]) ?? [],
      restricted_reason: (prof?.restricted_reason as string | null) ?? null,
      identity_done: Boolean(prof?.liveness_passed_at),
      // FICA records are read only through audited server functions (bi_fica_list); the path status stands in.
      fica_done: prof ? !['identity', 'fica'].includes(String(prof.status)) : false,
    });

    const [co] = await this.select('bi_company', (q) => q.select('*').eq('client_account_id', companyId).limit(1));
    if (co) {
      const status = String(co.onboarding_status) as KindMap['company']['onboarding_status'];
      put('company', {
        id: companyId,
        row_version: co.row_version as number,
        legal_name: String(co.legal_name),
        trading_name: (co.trading_name as string | null) ?? null,
        registration_number: (co.registration_number as string | null) ?? null,
        cipc_status: (co.cipc_status as KindMap['company']['cipc_status']) ?? null,
        s16_1_contact: (co.s16_1_contact as string | null) ?? null,
        s16_2_contact: (co.s16_2_contact as string | null) ?? null,
        popia_contact: (co.popia_contact as string | null) ?? null,
        onboarding_status: status,
        fica_status: status === 'active' ? 'accepted' : 'submitted',
        // Decision 1.1 eligibility is not a column yet (P5); unknown until the server says.
        file_eligibility: 'unknown',
        file_eligibility_note: null,
      });
    }

    const live = (q: ReturnType<SupabaseClient['from']>) => q.select('*').eq('client_account_id', companyId).is('archived_at', null);
    for (const s of await this.select('bi_site', live)) put('site', { id: String(s.id), row_version: s.row_version as number, client_account_id: companyId, name: String(s.name), address: (s.address as string | null) ?? null });
    for (const d of await this.select('bi_department', live)) put('department', { id: String(d.id), row_version: d.row_version as number, site_id: String(d.site_id), department_code: (d.department_code as string | null) ?? null, name: String(d.name) });
    for (const b of await this.select('bi_building', live)) put('building', { id: String(b.id), row_version: b.row_version as number, site_id: String(b.site_id), department_id: String(b.department_id), name: String(b.name), kind: b.kind as 'building' | 'zone' });
    for (const r of await this.select('bi_room', live)) put('room', { id: String(r.id), row_version: r.row_version as number, site_id: String(r.site_id), building_id: String(r.building_id), name: String(r.name), kind: r.kind as 'room' | 'area' });
    for (const e of await this.select('bi_equipment', (q) => q.select('*').eq('client_account_id', companyId))) {
      put('equipment', { id: String(e.id), row_version: e.row_version as number, client_account_id: companyId, site_id: (e.site_id as string | null) ?? null, tag_code: String(e.tag_code), kind: String(e.kind), description: (e.description as string | null) ?? null, serial_number: (e.serial_number as string | null) ?? null });
    }

    const templates = await this.select('bi_template', (q) => q.select('id,code,name,category,section_f_element_code,description').eq('status', 'published'));
    for (const t of templates) put('template', { id: String(t.id), code: String(t.code), name: String(t.name), category: String(t.category), section_f_element_code: (t.section_f_element_code as string | null) ?? null, description: (t.description as string | null) ?? null });
    if (templates.length) {
      const items = await this.select('bi_template_item', (q) => q.select('id,template_id,ordinal,section_label,prompt,kernel_ref').in('template_id', templates.map((t) => String(t.id))));
      for (const i of items) put('template_item', { id: String(i.id), template_id: String(i.template_id), ordinal: Number(i.ordinal), section_label: (i.section_label as string | null) ?? null, prompt: String(i.prompt), kernel_ref: (i.kernel_ref as string | null) ?? null });
    }

    for (const c of await this.select('bi_consent_record', (q) => q.select('*').eq('auth_user_id', uid).order('granted_at'))) {
      const kind = c.consent_kind as KindMap['consent']['consent_kind'];
      put('consent', { id: `consent-${kind}`, consent_kind: kind, granted: Boolean(c.granted) && !c.withdrawn_at, wording_version: String(c.wording_version), granted_at: (c.granted_at as string | null) ?? null, confirmed_at: (c.confirmed_at as string | null) ?? null, withdrawn_at: (c.withdrawn_at as string | null) ?? null });
    }

    const [wallet] = await this.select('bi_wallet', (q) => q.select('*').eq('tenant_id', tenantId).eq('client_account_id', companyId).limit(1));
    let walletId: string | null = null;
    if (wallet) {
      walletId = String(wallet.id);
      put('wallet', { id: walletId, client_account_id: companyId, status: wallet.status as 'active' | 'frozen', monthly_spend_cap_cents: (wallet.monthly_spend_cap_cents as number | null) ?? null, auto_topup_enabled: Boolean(wallet.auto_topup_enabled) });
      for (const l of await this.select('bi_wallet_ledger', (q) => q.select('*').eq('wallet_id', walletId as string).order('created_at'))) {
        put('ledger', { id: String(l.id), wallet_id: walletId, entry_kind: l.entry_kind as KindMap['ledger']['entry_kind'], amount_cents: Number(l.amount_cents), lot_id: l.lot_id === null ? null : String(l.lot_id), expires_at: (l.expires_at as string | null) ?? null, note: (l.note as string | null) ?? null, created_at: String(l.created_at) });
      }
      for (const u of await this.select('bi_usage_event', (q) => q.select('id,shortfall_cents,estimate_cents,actual_cents,kind,created_at').eq('wallet_id', walletId as string).gt('shortfall_cents', 0))) {
        put('subsidy', { id: String(u.id), wallet_id: walletId, shortfall_cents: Number(u.shortfall_cents), estimate_cents: Number(u.estimate_cents ?? 0), actual_cents: Number(u.actual_cents ?? 0), what: u.kind === 'ai_draft' ? 'an AI draft' : 'an AI action', created_at: String(u.created_at) });
      }
    }

    const inspections = await this.select('bi_inspection', (q) => q.select('*').eq('inspector_user_id', appUserId).in('status', ['planned', 'in_progress', 'submitted']));
    for (const i of inspections) {
      put('inspection', {
        id: String(i.id), row_version: i.row_version as number, tenant_id: tenantId, client_account_id: String(i.client_account_id), site_id: String(i.site_id), template_id: String(i.template_id),
        inspector_user_id: appUserId, title: String(i.title), status: i.status as KindMap['inspection']['status'], voice_note_policy: i.voice_note_policy as 'recommended' | 'strict',
        started_at: (i.started_at as string | null) ?? null, submitted_at: (i.submitted_at as string | null) ?? null, device_id: (i.device_id as string | null) ?? null,
      });
    }
    const ids = inspections.map((i) => String(i.id));
    if (ids.length) {
      for (const a of await this.select('bi_inspection_area', (q) => q.select('*').in('inspection_id', ids))) put('area', { id: String(a.id), row_version: a.row_version as number, inspection_id: String(a.inspection_id), room_id: (a.room_id as string | null) ?? null, label: String(a.label), ordinal: Number(a.ordinal) });
      for (const f of await this.select('bi_finding', (q) => q.select('*').in('inspection_id', ids))) {
        put('finding', { id: String(f.id), row_version: f.row_version as number, inspection_id: String(f.inspection_id), area_id: String(f.area_id), template_item_id: (f.template_item_id as string | null) ?? null, equipment_id: (f.equipment_id as string | null) ?? null, result: f.result as KindMap['finding']['result'], note: (f.note as string | null) ?? null, severity: (f.severity as KindMap['finding']['severity']) ?? null, captured_by: String(f.captured_by ?? appUserId), captured_at: String(f.captured_at), gps_lat: (f.gps_lat as number | null) ?? null, gps_lng: (f.gps_lng as number | null) ?? null });
      }
      for (const r of await this.select('bi_risk', (q) => q.select('*').in('inspection_id', ids))) {
        put('risk', { id: String(r.id), row_version: r.row_version as number, inspection_id: String(r.inspection_id), area_id: (r.area_id as string | null) ?? null, finding_id: (r.finding_id as string | null) ?? null, hazard: String(r.hazard), consequence: (r.consequence as string | null) ?? null, inherent_likelihood: Number(r.inherent_likelihood), inherent_severity: Number(r.inherent_severity), controls: (r.controls as KindMap['risk']['controls']) ?? [], residual_likelihood: (r.residual_likelihood as number | null) ?? null, residual_severity: (r.residual_severity as number | null) ?? null });
      }
      for (const c of await this.select('bi_corrective_action', (q) => q.select('*').in('inspection_id', ids))) {
        put('action', { id: String(c.id), row_version: c.row_version as number, inspection_id: String(c.inspection_id), finding_id: (c.finding_id as string | null) ?? null, risk_id: (c.risk_id as string | null) ?? null, description: String(c.description), owner_name: String(c.owner_name), due_on: String(c.due_on), status: c.status as KindMap['action']['status'] });
      }
    }
    await store.putServerMany(rows);
    return {
      appUserId,
      tenantId,
      companyId,
      displayName: String(me.display_name),
      roles: roles.map((r) => String(r.role)),
      voicePolicy: (tenant?.voice_note_policy as 'recommended' | 'strict') ?? 'recommended',
      walletId,
    };
  }

  async push(item: SyncItem, store: DataStore): Promise<PushOutcome> {
    const kind = item.kind as Kind;
    try {
      if (item.op === 'rpc') {
        // STUB until the account-update Edge Function (onboarding, authorised persons, registrations, qualifications, consents) exists.
        const { error } = await this.sb.functions.invoke('account-update', { body: { kind, record: item.payload } });
        if (!error) return { kind: 'ok' };
        const e = await functionError(error);
        return classifyPushError({ status: e.status, message: e.message }, 'rpc');
      }
      const table = TABLE_OF[kind];
      if (!table) return { kind: 'rejected', error: `Nothing to send for ${kind}.` };

      if (item.op === 'upload') {
        const rec = store.get(kind, item.recordId) as (KindMap['photo'] | KindMap['voice_note']) | undefined;
        if (!rec) return { kind: 'rejected', error: 'The file is no longer on this phone.' };
        const path = 'storage_path' in rec ? rec.storage_path : rec.audio_path;
        // STUB until the evidence-upload-url Edge Function (signed upload URL into the private bi-evidence bucket) exists.
        const { data, error } = await this.sb.functions.invoke('evidence-upload-url', {
          body: { kind, inspection_id: rec.inspection_id, path, sha256: 'sha256' in rec ? rec.sha256 : rec.audio_sha256, size_bytes: rec.size_bytes, mime_type: rec.mime_type },
        });
        if (error) {
          const e = await functionError(error);
          return classifyPushError({ status: e.status, message: e.message }, 'upload');
        }
        const token = (data as Row | null)?.token;
        if (typeof token !== 'string') return { kind: 'retry', error: 'The upload could not be prepared.' };
        const bytes = await readBytes(rec._local_uri);
        const up = await this.sb.storage.from('bi-evidence').uploadToSignedUrl(path, token, bytes, { contentType: rec.mime_type });
        if (up.error && !/exists|duplicate/i.test(up.error.message)) return { kind: 'retry', error: up.error.message };
        return this.insertRow(table, item);
      }

      if (item.op === 'insert') return this.insertRow(table, item);

      // update: only where the row_version we last saw still matches (conflict safe).
      let q = this.sb.from(table).update(item.payload).eq('id', item.recordId);
      if (item.baseRowVersion !== null) q = q.eq('row_version', item.baseRowVersion);
      const { data, error } = await q.select('id,row_version');
      if (error) return classifyPushError(error, 'update');
      if (Array.isArray(data) && data.length === 1) return { kind: 'ok', rowVersion: Number((data[0] as Row).row_version) };
      const { data: server } = await this.sb.from(table).select('*').eq('id', item.recordId).maybeSingle();
      const verdict = classifyMissedUpdate(item.payload, item.baseRowVersion, (server as Row | null) ?? null);
      if (verdict === 'already_applied') return { kind: 'ok', rowVersion: Number((server as Row).row_version) };
      if (verdict === 'missing') return { kind: 'retry', error: 'The record is not on the server yet.' };
      return { kind: 'conflict', error: 'Someone else changed this on the server.', serverRowVersion: Number((server as Row).row_version), server: server as Row };
    } catch (e) {
      return { kind: 'retry', error: e instanceof Error ? e.message : 'No connection' };
    }
  }

  private async insertRow(table: string, item: SyncItem): Promise<PushOutcome> {
    const payload = stripLocal(item.payload);
    // Idempotent: a repeat after a lost answer does nothing (on conflict do nothing).
    const { error } = await this.sb.from(table).upsert(payload, { onConflict: 'id', ignoreDuplicates: true });
    if (error) return classifyPushError(error, 'insert');
    const cols = table === 'bi_voice_note' ? 'row_version,vn_number' : table === 'bi_voice_transcript' ? 'version' : 'row_version';
    const { data } = await this.sb.from(table).select(cols).eq('id', item.recordId).maybeSingle();
    const row = (data as Row | null) ?? {};
    const patch: Row = {};
    if (typeof row.vn_number === 'number') patch.vn_number = row.vn_number;
    if (typeof row.version === 'number') patch.version = row.version;
    return { kind: 'ok', rowVersion: typeof row.row_version === 'number' ? row.row_version : undefined, patch };
  }

  async walletEstimate(p: { walletId: string; inspectionId: string; tokensIn: number; tokensOut: number }): Promise<EstimateResult> {
    const { data, error } = await this.sb.functions.invoke('wallet-estimate', {
      body: { wallet_id: p.walletId, kind: 'ai_draft', model_code: 'ai_quality', tokens_in: p.tokensIn, tokens_out: p.tokensOut, inspection_id: p.inspectionId, idempotency_key: `estimate:${p.inspectionId}:${Date.now()}` },
    });
    if (error) {
      const e = await functionError(error);
      if (e.status === 404) throw new NotConnectedError('The cost preview', 'The cost preview is not switched on on the server yet. The free template draft works now.');
      throw new Error(e.message);
    }
    const r = data as Row;
    return { estimate_cents: Number(r.estimate_cents), available_cents: Number(r.available_cents), allowed: Boolean(r.allowed), reason: (r.reason as string | null) ?? null };
  }

  async reportDraft(p: { inspectionId: string; useAi: boolean; walletId: string | null; store: DataStore }): Promise<DraftResult> {
    const { data, error } = await this.sb.functions.invoke('report-draft', { body: { inspection_id: p.inspectionId, use_ai: p.useAi, ...(p.walletId ? { wallet_id: p.walletId } : {}) } });
    if (error) {
      const e = await functionError(error);
      if (e.status === 404) throw new NotConnectedError('Report drafting', 'Report drafting is not switched on on the server yet.');
      if (e.status === 402) throw new Error('The AI Wallet cannot pay for this draft. Top up, or use the free template draft.');
      throw new Error(e.message);
    }
    const r = data as Row;
    const content = r.content as ReportContent;
    const ai = (r.ai as Row) ?? {};
    const insp = p.store.get('inspection', p.inspectionId);
    const tpl = insp ? p.store.get('template', insp.template_id) : undefined;
    const report: Report = {
      id: String(r.report_id),
      inspection_id: p.inspectionId,
      status: 'draft',
      version: Number(r.version),
      source: ai.used ? 'ai_assistive' : 'template',
      content,
      charged_cents: typeof ai.charged_cents === 'number' ? ai.charged_cents : null,
      signed_by: null,
      signed_at: null,
      issued_at: null,
      file_link_status: null,
      section_f_element_code: tpl?.section_f_element_code ?? null,
      reviewer_requested_at: null,
    };
    await p.store.putServer('report', report);
    return {
      report,
      aiUsed: Boolean(ai.used),
      aiNote: ai.used
        ? 'AI assisted draft. The charge is on your wallet statement.'
        : p.useAi
          ? 'AI drafting is not switched on yet, so this is the template draft. Nothing was charged.'
          : 'Template draft from your capture. Nothing was charged.',
      chargedCents: report.charged_cents,
      voiceLine: typeof r.voice_notes_line === 'string' ? r.voice_notes_line : voicePreviewLine(content.voice_notes),
    };
  }

  async requestReview(): Promise<Report> {
    throw new NotConnectedError('Request sign off', 'Recording a sign off request is not switched on on the server yet. Use Bee-Matched or WhatsApp meanwhile.');
  }

  async signAndIssue(): Promise<SignResult> {
    throw new NotConnectedError('In app signing', 'In app signing is not switched on on the server yet. Nothing was signed or issued.');
  }

  async topUp(): Promise<{ credited: boolean; message: string }> {
    // STUB: RevenueCat in app purchase until the store product ids exist (BI_RC_PRODUCT_MAP).
    return { credited: false, message: 'In app purchase is not connected yet: the store product ids are still pending. Nothing was charged. Ask a Care Net sales executive to top up meanwhile.' };
  }
}
