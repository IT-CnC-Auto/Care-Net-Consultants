import {
  applyOutcome,
  backoffDelay,
  BACKOFF,
  classifyMissedUpdate,
  eligible,
  enqueue,
  markInFlight,
  newItem,
  recoverInFlight,
  resolveConflict,
  retryItem,
  stripLocal,
  summarise,
  type SyncItem,
} from '../sync-queue';

const T = 1_000_000;
const item = (id: string, recordId: string, op: SyncItem['op'], payload: Record<string, unknown> = {}, extra: Partial<SyncItem> = {}, at = T) =>
  ({ ...newItem({ id, kind: 'finding', recordId, op, payload, now: at }), ...extra });

describe('backoff', () => {
  it('doubles from 2 seconds up to 5 minutes, with jitter between half and all of the cap', () => {
    expect(backoffDelay(1, () => 0)).toBe(1000);
    expect(backoffDelay(1, () => 1)).toBe(2000);
    expect(backoffDelay(3, () => 1)).toBe(8000);
    expect(backoffDelay(20, () => 1)).toBe(BACKOFF.maxMs);
    expect(backoffDelay(20, () => 0)).toBe(BACKOFF.maxMs / 2);
  });
});

describe('enqueue', () => {
  it('is idempotent on the operation id', () => {
    const q = enqueue([], item('op1', 'r1', 'insert', { result: 'pass' }));
    expect(enqueue(q, item('op1', 'r1', 'insert', { result: 'fail' }))).toEqual(q);
  });
  it('folds an update into a waiting insert of the same record', () => {
    let q = enqueue([], item('op1', 'r1', 'insert', { result: 'pass', note: null }));
    q = enqueue(q, item('op2', 'r1', 'update', { result: 'fail' }, {}, T + 5));
    expect(q).toHaveLength(1);
    expect(q[0].op).toBe('insert');
    expect(q[0].payload).toEqual({ result: 'fail', note: null });
  });
  it('merges two waiting updates and keeps the first base version', () => {
    let q = enqueue([], item('op1', 'r1', 'update', { note: 'a' }, { baseRowVersion: 3 }));
    q = enqueue(q, item('op2', 'r1', 'update', { result: 'fail' }, { baseRowVersion: 4 }, T + 5));
    expect(q).toHaveLength(1);
    expect(q[0].baseRowVersion).toBe(3);
    expect(q[0].payload).toEqual({ note: 'a', result: 'fail' });
  });
  it('does not fold into an item already in flight', () => {
    let q = markInFlight(enqueue([], item('op1', 'r1', 'insert', { note: 'a' })), ['op1']);
    q = enqueue(q, item('op2', 'r1', 'update', { note: 'b' }, {}, T + 5));
    expect(q).toHaveLength(2);
  });
});

describe('eligible (order and dependencies)', () => {
  it('lets a child wait for its unsynced parent', () => {
    const area = { ...item('op1', 'area1', 'insert'), kind: 'area' };
    const finding = item('op2', 'f1', 'insert', {}, { dependsOn: ['area1'] }, T + 1);
    const q = [finding, area];
    expect(eligible(q, T + 10).map((x) => x.id)).toEqual(['op1']);
    const after = applyOutcome(q, 'op1', { kind: 'ok', rowVersion: 1 }, T + 11).queue;
    expect(eligible(after, T + 12).map((x) => x.id)).toEqual(['op2']);
  });
  it('keeps operations on one record in order', () => {
    const q = [item('op1', 'r1', 'upload', {}, { status: 'failed' }), item('op2', 'r1', 'update', {}, {}, T + 1)];
    expect(eligible(q, T + 10)).toEqual([]);
  });
  it('waits for the backoff time', () => {
    const q = [item('op1', 'r1', 'insert', {}, { nextAttemptAt: T + 100 })];
    expect(eligible(q, T + 50)).toEqual([]);
    expect(eligible(q, T + 100)).toHaveLength(1);
  });
});

describe('applyOutcome', () => {
  it('removes a synced item and moves later updates onto the new row version', () => {
    const q = [item('op1', 'r1', 'insert'), item('op2', 'r1', 'update', { note: 'x' }, { status: 'conflict' }, T + 1)];
    const r = applyOutcome(q, 'op1', { kind: 'ok', rowVersion: 1, patch: { vn_number: 3 } }, T + 2);
    expect(r.queue.map((x) => x.id)).toEqual(['op2']);
    expect(r.queue[0].baseRowVersion).toBe(1);
    expect(r.synced).toEqual({ kind: 'finding', recordId: 'r1', rowVersion: 1, patch: { vn_number: 3 } });
  });
  it('retries with backoff and fails after the last attempt', () => {
    let q: SyncItem[] = [item('op1', 'r1', 'insert')];
    q = applyOutcome(q, 'op1', { kind: 'retry', error: 'offline' }, T, () => 1).queue;
    expect(q[0]).toMatchObject({ status: 'pending', attempts: 1, nextAttemptAt: T + 2000, lastError: 'offline' });
    for (let i = 0; i < BACKOFF.maxAttempts - 1; i++) q = applyOutcome(q, 'op1', { kind: 'retry', error: 'offline' }, T, () => 1).queue;
    expect(q[0].status).toBe('failed');
    expect(eligible(q, T + 10 ** 9)).toEqual([]);
    q = retryItem(q, 'op1', T + 5);
    expect(q[0]).toMatchObject({ status: 'pending', attempts: 0, nextAttemptAt: T + 5 });
  });
  it('parks an item when the server function does not exist yet', () => {
    const q = applyOutcome([item('op1', 'r1', 'upload')], 'op1', { kind: 'waiting_server', error: 'not deployed' }, T).queue;
    expect(q[0]).toMatchObject({ status: 'waiting_server', nextAttemptAt: T + BACKOFF.waitingServerMs });
    expect(eligible(q, T + BACKOFF.waitingServerMs)).toHaveLength(1);
  });
  it('holds a conflict for a person and resolves it either way', () => {
    const q = applyOutcome([item('op1', 'r1', 'update', { note: 'mine' }, { baseRowVersion: 2 })], 'op1', { kind: 'conflict', error: 'changed', serverRowVersion: 4 }, T).queue;
    expect(q[0].status).toBe('conflict');
    expect(eligible(q, T + 1)).toEqual([]);
    const keep = resolveConflict(q, 'op1', 'keep_mine', T + 2);
    expect(keep[0]).toMatchObject({ status: 'pending', baseRowVersion: 4, payload: { note: 'mine' } });
    expect(resolveConflict(q, 'op1', 'use_server', T + 2)).toEqual([]);
  });
  it('marks a rejected item failed', () => {
    const q = applyOutcome([item('op1', 'r1', 'insert')], 'op1', { kind: 'rejected', error: 'not allowed' }, T).queue;
    expect(q[0].status).toBe('failed');
  });
});

describe('restart, summary and helpers', () => {
  it('sends in flight items again after a restart', () => {
    const q = recoverInFlight(markInFlight([item('op1', 'r1', 'insert')], ['op1']));
    expect(q[0].status).toBe('pending');
  });
  it('summarises the queue', () => {
    const q = [item('a', '1', 'insert'), item('b', '2', 'insert', {}, { status: 'conflict' }), item('c', '3', 'upload', {}, { status: 'waiting_server' }), item('d', '4', 'insert', {}, { status: 'failed' })];
    expect(summarise(q)).toEqual({ total: 4, pending: 1, waitingServer: 1, conflicts: 1, failed: 1 });
  });
  it('tells a lost answer from a real conflict', () => {
    expect(classifyMissedUpdate({ note: 'x' }, 2, { row_version: 3, note: 'x' })).toBe('already_applied');
    expect(classifyMissedUpdate({ note: 'x' }, 2, { row_version: 3, note: 'y' })).toBe('conflict');
    expect(classifyMissedUpdate({ note: 'x' }, 2, { row_version: 5, note: 'x' })).toBe('conflict');
    expect(classifyMissedUpdate({ note: 'x' }, 2, null)).toBe('missing');
  });
  it('never sends local only fields', () => {
    expect(stripLocal({ id: '1', _local_uri: 'file:///x', note: 'a' })).toEqual({ id: '1', note: 'a' });
  });
});
