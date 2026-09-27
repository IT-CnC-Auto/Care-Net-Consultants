// The offline sync queue, as pure functions over a list (no storage, no
// network), so the rules can be tested and the same list can live in SQLite.
//
// Rules:
//   1. Idempotent client ids. Every record takes its id from the phone (a
//      uuid) and every queued operation has its own id. Enqueuing the same
//      operation twice changes nothing; the server inserts with "on conflict
//      do nothing", so a repeat after a lost answer is harmless.
//   2. Coalescing. An update to a record still waiting to be inserted is folded
//      into the insert; two waiting updates to one record become one.
//   3. Order. Operations on one record go in the order they were made, and an
//      operation waits while a record it depends on (its parent) is unsynced.
//   4. Conflict safe. An update carries the row_version it was based on; the
//      server applies it only where that version still matches. A mismatch is
//      a conflict for a person to resolve, never a silent overwrite.
//   5. Retry with backoff. Network and server errors retry with exponential
//      backoff and jitter, up to a limit; then the item is marked failed and
//      waits for a person to press retry. A server function that does not exist
//      yet (404 or 501) parks the item as waiting for the server.

export type SyncOp = 'insert' | 'update' | 'upload' | 'rpc';
export type SyncStatus = 'pending' | 'in_flight' | 'conflict' | 'failed' | 'waiting_server';

export interface SyncItem {
  id: string;
  kind: string;
  recordId: string;
  op: SyncOp;
  payload: Record<string, unknown>;
  baseRowVersion: number | null;
  dependsOn: string[];
  attempts: number;
  nextAttemptAt: number;
  status: SyncStatus;
  lastError: string | null;
  createdAt: number;
}

export type PushOutcome =
  | { kind: 'ok'; rowVersion?: number; patch?: Record<string, unknown> }
  | { kind: 'retry'; error: string }
  | { kind: 'conflict'; error: string; serverRowVersion?: number; server?: Record<string, unknown> }
  | { kind: 'waiting_server'; error: string }
  | { kind: 'rejected'; error: string };

export interface BackoffConfig {
  baseMs: number;
  maxMs: number;
  maxAttempts: number;
  waitingServerMs: number;
}

export const BACKOFF: BackoffConfig = { baseMs: 2000, maxMs: 5 * 60 * 1000, maxAttempts: 8, waitingServerMs: 60 * 60 * 1000 };

/** Exponential backoff with equal jitter: half the cap plus a random half. */
export function backoffDelay(attempt: number, random: () => number = Math.random, cfg: BackoffConfig = BACKOFF): number {
  const cap = Math.min(cfg.maxMs, cfg.baseMs * 2 ** Math.max(0, attempt - 1));
  const r = Math.min(1, Math.max(0, random()));
  return Math.round(cap / 2 + (r * cap) / 2);
}

export function newItem(p: {
  id: string;
  kind: string;
  recordId: string;
  op: SyncOp;
  payload: Record<string, unknown>;
  baseRowVersion?: number | null;
  dependsOn?: string[];
  now: number;
}): SyncItem {
  return {
    id: p.id,
    kind: p.kind,
    recordId: p.recordId,
    op: p.op,
    payload: p.payload,
    baseRowVersion: p.baseRowVersion ?? null,
    dependsOn: p.dependsOn ?? [],
    attempts: 0,
    nextAttemptAt: p.now,
    status: 'pending',
    lastError: null,
    createdAt: p.now,
  };
}

/** Adds an operation, coalescing with a waiting one for the same record (rules 1 and 2). */
export function enqueue(queue: readonly SyncItem[], item: SyncItem): SyncItem[] {
  if (queue.some((q) => q.id === item.id)) return queue.slice();
  if (item.op === 'update') {
    const idx = queue.findIndex((q) => q.recordId === item.recordId && q.kind === item.kind && q.status === 'pending' && (q.op === 'insert' || q.op === 'update' || q.op === 'upload'));
    if (idx >= 0) {
      const target = queue[idx];
      const merged: SyncItem = {
        ...target,
        payload: { ...target.payload, ...item.payload },
        dependsOn: Array.from(new Set([...target.dependsOn, ...item.dependsOn])),
      };
      const next = queue.slice();
      next[idx] = merged;
      return next;
    }
  }
  return [...queue, item];
}

/** The operations that may be pushed now, oldest first (rule 3). */
export function eligible(queue: readonly SyncItem[], now: number, limit = Infinity): SyncItem[] {
  const sorted = queue.slice().sort((a, b) => a.createdAt - b.createdAt || (a.id < b.id ? -1 : 1));
  const out: SyncItem[] = [];
  const seenRecords = new Set<string>();
  for (const item of sorted) {
    const earlierSameRecord = seenRecords.has(item.recordId);
    seenRecords.add(item.recordId);
    if (out.length >= limit) break;
    if (earlierSameRecord) continue;
    if (item.status !== 'pending' && item.status !== 'waiting_server') continue;
    if (item.nextAttemptAt > now) continue;
    const blockedByParent = item.dependsOn.some((dep) => sorted.some((q) => q.recordId === dep && q.id !== item.id));
    if (blockedByParent) continue;
    out.push(item);
  }
  return out;
}

export function markInFlight(queue: readonly SyncItem[], ids: readonly string[]): SyncItem[] {
  const set = new Set(ids);
  return queue.map((q) => (set.has(q.id) ? { ...q, status: 'in_flight' as const } : q));
}

/** After a restart nothing is really in flight: push it again (safe, rule 1). */
export function recoverInFlight(queue: readonly SyncItem[]): SyncItem[] {
  return queue.map((q) => (q.status === 'in_flight' ? { ...q, status: 'pending' as const } : q));
}

export interface ApplyResult {
  queue: SyncItem[];
  /** When the push succeeded: the record's new row_version and any fields the server set. */
  synced?: { kind: string; recordId: string; rowVersion?: number; patch?: Record<string, unknown> };
}

export function applyOutcome(queue: readonly SyncItem[], itemId: string, outcome: PushOutcome, now: number, random: () => number = Math.random, cfg: BackoffConfig = BACKOFF): ApplyResult {
  const item = queue.find((q) => q.id === itemId);
  if (!item) return { queue: queue.slice() };
  switch (outcome.kind) {
    case 'ok': {
      const rest = queue.filter((q) => q.id !== itemId);
      const rv = outcome.rowVersion;
      const next = rv === undefined ? rest : rest.map((q) => (q.recordId === item.recordId && q.op === 'update' ? { ...q, baseRowVersion: rv } : q));
      return { queue: next, synced: { kind: item.kind, recordId: item.recordId, rowVersion: rv, patch: outcome.patch } };
    }
    case 'retry': {
      const attempts = item.attempts + 1;
      const failed = attempts >= cfg.maxAttempts;
      return {
        queue: queue.map((q) =>
          q.id === itemId
            ? { ...q, attempts, status: failed ? ('failed' as const) : ('pending' as const), lastError: outcome.error, nextAttemptAt: failed ? q.nextAttemptAt : now + backoffDelay(attempts, random, cfg) }
            : q,
        ),
      };
    }
    case 'conflict':
      return {
        queue: queue.map((q) =>
          q.id === itemId
            ? { ...q, status: 'conflict' as const, lastError: outcome.error, payload: outcome.serverRowVersion !== undefined ? { ...q.payload, __server_row_version: outcome.serverRowVersion } : q.payload }
            : q,
        ),
      };
    case 'waiting_server':
      return {
        queue: queue.map((q) => (q.id === itemId ? { ...q, status: 'waiting_server' as const, attempts: q.attempts + 1, lastError: outcome.error, nextAttemptAt: now + cfg.waitingServerMs } : q)),
      };
    case 'rejected':
      return { queue: queue.map((q) => (q.id === itemId ? { ...q, status: 'failed' as const, lastError: outcome.error } : q)) };
  }
}

/** A person pressed retry on a failed or parked item. */
export function retryItem(queue: readonly SyncItem[], itemId: string, now: number): SyncItem[] {
  return queue.map((q) => (q.id === itemId ? { ...q, status: 'pending' as const, attempts: 0, nextAttemptAt: now, lastError: null } : q));
}

/**
 * A person resolved a conflict. keep_mine: send the update again on top of the
 * server's version. use_server: drop the local change (the caller then
 * replaces the local record with the server copy).
 */
export function resolveConflict(queue: readonly SyncItem[], itemId: string, choice: 'keep_mine' | 'use_server', now: number): SyncItem[] {
  if (choice === 'use_server') return queue.filter((q) => q.id !== itemId);
  return queue.map((q) => {
    if (q.id !== itemId) return q;
    const { __server_row_version: srv, ...payload } = q.payload as Record<string, unknown> & { __server_row_version?: number };
    return { ...q, payload, baseRowVersion: typeof srv === 'number' ? srv : q.baseRowVersion, status: 'pending' as const, attempts: 0, nextAttemptAt: now, lastError: null };
  });
}

export interface QueueSummary {
  total: number;
  pending: number;
  waitingServer: number;
  conflicts: number;
  failed: number;
}

export function summarise(queue: readonly SyncItem[]): QueueSummary {
  const count = (s: SyncStatus) => queue.filter((q) => q.status === s).length;
  return {
    total: queue.length,
    pending: count('pending') + count('in_flight'),
    waitingServer: count('waiting_server'),
    conflicts: count('conflict'),
    failed: count('failed'),
  };
}

/**
 * An update came back with no row: was it ours already (a lost answer), or did
 * someone else change the row? Ours when the server is exactly one version on
 * and holds every value we sent.
 */
export function classifyMissedUpdate(sent: Record<string, unknown>, baseRowVersion: number | null, server: Record<string, unknown> | null): 'already_applied' | 'conflict' | 'missing' {
  if (!server) return 'missing';
  const sameValues = Object.entries(sent).every(([k, v]) => JSON.stringify(server[k] ?? null) === JSON.stringify(v ?? null));
  if (baseRowVersion !== null && server.row_version === baseRowVersion + 1 && sameValues) return 'already_applied';
  return 'conflict';
}

/** Local only fields (leading underscore) never leave the phone. */
export function stripLocal(record: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(record)) if (!k.startsWith('_')) out[k] = v;
  return out;
}
