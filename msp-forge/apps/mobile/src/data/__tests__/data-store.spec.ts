import { DemoBackend } from '@/backend/demo-backend';
import { DEMO } from '@/backend/demo-seed';
import { classifyPushError } from '@/backend/pg-errors';
import { formatRand } from '@/lib/money';
import { eligible, type SyncItem } from '@/lib/sync-queue';
import { balanceFromLedger } from '@/lib/wallet';

import { DataStore } from '../data-store';
import type { LocalStore } from '../local-store.types';

function memoryStore(): LocalStore & { dump(): { records: number; queue: SyncItem[] } } {
  const records = new Map<string, Record<string, unknown>>();
  let queue: SyncItem[] = [];
  const kv = new Map<string, string>();
  return {
    name: 'memory',
    async loadAll() {
      return Array.from(records.entries()).map(([k, data]) => ({ kind: k.split('/')[0], id: k.split('/')[1], data }));
    },
    async put(kind, id, data) {
      records.set(`${kind}/${id}`, data);
    },
    async remove(kind, id) {
      records.delete(`${kind}/${id}`);
    },
    async loadQueue() {
      return queue;
    },
    async saveQueue(items) {
      queue = items.slice();
    },
    async kvGet(k) {
      return kv.get(k) ?? null;
    },
    async kvSet(k, v) {
      if (v === null) kv.delete(k);
      else kv.set(k, v);
    },
    async wipe() {
      records.clear();
      queue = [];
      kv.clear();
    },
    dump: () => ({ records: records.size, queue }),
  };
}

let n = 0;
const ids = () => `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`;

describe('DataStore: offline first writes and the queue', () => {
  it('saves locally, queues an insert, folds a later edit into it and survives a restart', async () => {
    const local = memoryStore();
    const store = await DataStore.open(local, ids);
    await store.create('site', { id: 'site-1', client_account_id: 'co', name: 'Yard', address: null });
    await store.create('department', { id: 'dep-1', site_id: 'site-1', department_code: 'OPS', name: 'Ops' });
    await store.update('site', 'site-1', { name: 'Main yard' });
    const q = store.getQueue();
    expect(q).toHaveLength(2);
    expect(q[0]).toMatchObject({ kind: 'site', op: 'insert', payload: { name: 'Main yard' } });
    expect(q[1]).toMatchObject({ kind: 'department', dependsOn: ['site-1'] });
    expect(eligible(q, Date.now() + 1).map((i) => i.recordId)).toEqual(['site-1']);

    const reopened = await DataStore.open(local, ids);
    expect(reopened.get('site', 'site-1')?.name).toBe('Main yard');
    expect(reopened.getQueue()).toHaveLength(2);
  });

  it('never sends local only fields and queues account data for the server function', async () => {
    const store = await DataStore.open(memoryStore(), ids);
    await store.create('qualification', { id: 'q1', qual_type: 'CHSO', issuer: 'X', number: '1', issued_on: null, expires_on: null, status: 'pending', document_name: 'a.pdf', _local_uri: 'file:///a.pdf' });
    const [item] = store.getQueue();
    expect(item.op).toBe('rpc');
    expect(item.payload).not.toHaveProperty('_local_uri');
  });
});

describe('classifyPushError', () => {
  it('parks work whose server part is not deployed, rejects refusals, retries network trouble', () => {
    expect(classifyPushError({ code: 'PGRST205', message: 'table not found' }, 'insert').kind).toBe('waiting_server');
    expect(classifyPushError({ status: 404, message: 'not found' }, 'upload').kind).toBe('waiting_server');
    expect(classifyPushError({ code: '42501', message: 'rls' }, 'insert').kind).toBe('rejected');
    expect(classifyPushError({ code: '23505', message: 'duplicate' }, 'insert').kind).toBe('ok');
    expect(classifyPushError({ message: 'Network request failed' }, 'update').kind).toBe('retry');
    expect(classifyPushError({ status: 503, message: 'unavailable' }, 'rpc').kind).toBe('retry');
  });
});

describe('demo backend: wallet rules, draft and Issue to Section F', () => {
  jest.setTimeout(20000);

  it('shows the balance and estimate, charges the draft, and files the Issued report by eligibility', async () => {
    const store = await DataStore.open(memoryStore(), ids);
    const b = new DemoBackend(store);
    const profile = await b.loadProfile(store);
    const ledger = () => store.where('ledger', (l) => l.wallet_id === DEMO.wallet).map((l) => ({ ...l, created_at: l.created_at ?? '' }));
    expect(formatRand(balanceFromLedger(ledger()).availableCents)).toBe('R398,20');

    const est = await b.walletEstimate({ walletId: DEMO.wallet, inspectionId: DEMO.inspection, tokensIn: 3000, tokensOut: 4000, store });
    expect(est.allowed).toBe(true);
    expect(est.available_cents).toBe(39820);
    expect(est.estimate_cents).toBe(383);

    // The seeded inspection still breaks the Fail rule, but the demo backend drafts from what is there.
    const d = await b.reportDraft({ inspectionId: DEMO.inspection, useAi: true, walletId: profile.walletId, store });
    expect(d.report.content.label).toBe('Assistive draft. Competent person sign off required.');
    expect(d.aiUsed).toBe(true);
    expect(d.chargedCents).toBeGreaterThan(0);
    expect(balanceFromLedger(ledger()).availableCents).toBe(39820 - (d.chargedCents as number));

    const signed = await b.signAndIssue({ reportId: d.report.id, signerName: 'Thandi Mokoena (fictitious)', signaturePath: 'M0 0 L1 1', reviewedPhotos: true, reviewedVoiceNotes: true, store });
    expect(signed.report.status).toBe('issued');
    expect(signed.report.file_link_status).toBe('linked');

    const company = store.get('company', DEMO.company)!;
    await store.putServer('company', { ...company, file_eligibility: 'not_eligible' });
    const d2 = await b.reportDraft({ inspectionId: DEMO.inspection, useAi: false, walletId: profile.walletId, store });
    const s2 = await b.signAndIssue({ reportId: d2.report.id, signerName: 'Thandi', signaturePath: 'M0 0 L1 1', reviewedPhotos: true, reviewedVoiceNotes: true, store });
    expect(s2.report.file_link_status).toBe('awaiting_eligibility');
    expect(s2.filing).toMatch(/awaiting eligibility/);
  });

  it('takes the balance to R0,00 and records a subsidy when a charge runs past it', async () => {
    const store = await DataStore.open(memoryStore(), ids);
    const b = new DemoBackend(store);
    await b.loadProfile(store);
    // Spend down to 300 cents, then run a draft whose estimate fits but whose charge is forced higher.
    const lots = store.where('ledger', (l) => l.amount_cents > 0);
    await store.putServer('ledger', { id: 'x1', wallet_id: DEMO.wallet, entry_kind: 'charge', amount_cents: -13820, lot_id: lots[0].id, expires_at: null, note: 't', created_at: new Date().toISOString() });
    await store.putServer('ledger', { id: 'x2', wallet_id: DEMO.wallet, entry_kind: 'charge', amount_cents: -25700, lot_id: lots[1].id, expires_at: null, note: 't', created_at: new Date().toISOString() });
    const est = await b.walletEstimate({ walletId: DEMO.wallet, inspectionId: DEMO.inspection, tokensIn: 100000, tokensOut: 4000, store });
    expect(est.available_cents).toBe(300);
    expect(est.allowed).toBe(false);
    expect(est.reason).toBe('wallet_empty');
  });
});
