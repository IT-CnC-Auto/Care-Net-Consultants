// The phone's records in memory, written through to the local store (SQLite
// on the phone), with the sync queue beside them. Every change a person makes
// is saved locally first and queued; the sync engine pushes the queue when
// there is signal. Screens read through useRecords (src/data/hooks.ts).

import { enqueue as enqueueItem, newItem, recoverInFlight, stripLocal, type SyncItem, type SyncOp } from '@/lib/sync-queue';
import { KINDS, TABLE_OF, type Kind, type KindMap } from '@/lib/types';

import type { LocalStore } from './local-store.types';

/** How each kind reaches the server. */
export function syncModeOf(kind: Kind): 'table' | 'upload' | 'append' | 'rpc' | 'none' {
  if (kind === 'photo' || kind === 'voice_note') return 'upload';
  if (kind === 'transcript') return 'append';
  if (TABLE_OF[kind]) return 'table';
  if (kind === 'company' || kind === 'person' || kind === 'registration' || kind === 'qualification' || kind === 'consent') return 'rpc';
  return 'none';
}

/** The records a record needs on the server first (its parents). */
export function parentsOf(kind: Kind, r: Record<string, unknown>): string[] {
  const keys: Partial<Record<Kind, string[]>> = {
    place: ['parent_id'],
    department: ['site_id'],
    building: ['department_id'],
    room: ['building_id'],
    equipment: ['site_id'],
    inspection: ['site_id', 'place_id'],
    area: ['inspection_id', 'room_id', 'place_id'],
    finding: ['area_id', 'equipment_id'],
    photo: ['inspection_id', 'area_id', 'finding_id', 'equipment_id'],
    voice_note: ['inspection_id', 'area_id', 'finding_id'],
    transcript: ['voice_note_id'],
    risk: ['inspection_id', 'area_id', 'finding_id'],
    action: ['inspection_id', 'finding_id', 'risk_id'],
  };
  return (keys[kind] ?? []).map((k) => r[k]).filter((v): v is string => typeof v === 'string' && v.length > 0);
}

type AnyRecord = KindMap[Kind];

export class DataStore {
  private cache = new Map<Kind, Map<string, AnyRecord>>();
  private queue: SyncItem[] = [];
  private version = 0;
  private listeners = new Set<() => void>();
  /**
   * A fresh handle on this same store after every change. Screens read the
   * store through it (useStore), so anything memoised on the store, by React or
   * by the React Compiler, is recomputed when the data changes. A Proxy with no
   * traps forwards every read, write and method call to this instance.
   */
  private view: DataStore;

  private constructor(
    readonly local: LocalStore,
    private readonly newId: () => string,
  ) {
    for (const k of KINDS) this.cache.set(k, new Map());
    this.view = new Proxy(this, {});
  }

  static async open(local: LocalStore, newId: () => string): Promise<DataStore> {
    const s = new DataStore(local, newId);
    for (const row of await local.loadAll()) {
      const bucket = s.cache.get(row.kind as Kind);
      if (bucket) bucket.set(row.id, row.data as unknown as AnyRecord);
    }
    s.queue = recoverInFlight(await local.loadQueue());
    return s;
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getVersion = (): number => this.version;

  /** The current handle (see view); a new object after every change. */
  getView = (): DataStore => this.view;

  private emit() {
    this.version += 1;
    this.view = new Proxy(this, {});
    for (const l of this.listeners) l();
  }

  id(): string {
    return this.newId();
  }

  list<K extends Kind>(kind: K): KindMap[K][] {
    return Array.from((this.cache.get(kind) as Map<string, KindMap[K]>).values());
  }

  get<K extends Kind>(kind: K, id: string | null | undefined): KindMap[K] | undefined {
    if (!id) return undefined;
    return (this.cache.get(kind) as Map<string, KindMap[K]>).get(id);
  }

  where<K extends Kind>(kind: K, pred: (r: KindMap[K]) => boolean): KindMap[K][] {
    return this.list(kind).filter(pred);
  }

  /** Server owned rows (profile, templates, wallet) arrive through here: stored, never queued. */
  async putServer<K extends Kind>(kind: K, record: KindMap[K]): Promise<void> {
    (this.cache.get(kind) as Map<string, KindMap[K]>).set(record.id, record);
    await this.local.put(kind, record.id, record as unknown as Record<string, unknown>);
    this.emit();
  }

  async putServerMany(rows: { kind: Kind; record: AnyRecord }[]): Promise<void> {
    for (const { kind, record } of rows) {
      this.cache.get(kind)?.set(record.id, record);
      await this.local.put(kind, record.id, record as unknown as Record<string, unknown>);
    }
    this.emit();
  }

  /** A new record made on the phone: saved, then queued for the server. */
  async create<K extends Kind>(kind: K, record: KindMap[K]): Promise<KindMap[K]> {
    const now = new Date().toISOString();
    const rec = { ...record, created_at: record.created_at ?? now, updated_at: now } as KindMap[K];
    (this.cache.get(kind) as Map<string, KindMap[K]>).set(rec.id, rec);
    await this.local.put(kind, rec.id, rec as unknown as Record<string, unknown>);
    const mode = syncModeOf(kind);
    if (mode !== 'none') {
      const op: SyncOp = mode === 'upload' ? 'upload' : mode === 'rpc' ? 'rpc' : 'insert';
      await this.pushQueue(kind, rec.id, op, stripLocal(rec as unknown as Record<string, unknown>), null, parentsOf(kind, rec as unknown as Record<string, unknown>));
    }
    this.emit();
    return rec;
  }

  /** A change to a record: merged locally, queued as an update carrying the row_version it was based on. */
  async update<K extends Kind>(kind: K, id: string, changes: Partial<KindMap[K]>): Promise<KindMap[K] | undefined> {
    const cur = this.get(kind, id);
    if (!cur) return undefined;
    const rec = { ...cur, ...changes, updated_at: new Date().toISOString() } as KindMap[K];
    (this.cache.get(kind) as Map<string, KindMap[K]>).set(id, rec);
    await this.local.put(kind, id, rec as unknown as Record<string, unknown>);
    const mode = syncModeOf(kind);
    const payload = stripLocal(changes as Record<string, unknown>);
    if (mode !== 'none' && mode !== 'append' && Object.keys(payload).length > 0) {
      const op: SyncOp = mode === 'rpc' ? 'rpc' : 'update';
      await this.pushQueue(kind, id, op, mode === 'rpc' ? stripLocal(rec as unknown as Record<string, unknown>) : payload, cur.row_version ?? null, parentsOf(kind, rec as unknown as Record<string, unknown>));
    }
    this.emit();
    return rec;
  }

  /** Local only change (for example a server field arriving, or a local file path). */
  async patchLocal<K extends Kind>(kind: K, id: string, changes: Partial<KindMap[K]>): Promise<void> {
    const cur = this.get(kind, id);
    if (!cur) return;
    const rec = { ...cur, ...changes } as KindMap[K];
    (this.cache.get(kind) as Map<string, KindMap[K]>).set(id, rec);
    await this.local.put(kind, id, rec as unknown as Record<string, unknown>);
    this.emit();
  }

  async removeLocal(kind: Kind, id: string): Promise<void> {
    this.cache.get(kind)?.delete(id);
    await this.local.remove(kind, id);
    this.emit();
  }

  private async pushQueue(kind: Kind, recordId: string, op: SyncOp, payload: Record<string, unknown>, baseRowVersion: number | null, dependsOn: string[]) {
    const item = newItem({ id: this.newId(), kind, recordId, op, payload, baseRowVersion, dependsOn, now: Date.now() });
    this.queue = enqueueItem(this.queue, item);
    await this.local.saveQueue(this.queue);
  }

  getQueue(): SyncItem[] {
    return this.queue;
  }

  async setQueue(q: SyncItem[]): Promise<void> {
    this.queue = q;
    await this.local.saveQueue(q);
    this.emit();
  }

  async kvGet(key: string): Promise<string | null> {
    return this.local.kvGet(key);
  }

  async kvSet(key: string, value: string | null): Promise<void> {
    await this.local.kvSet(key, value);
    this.emit();
  }

  async wipe(): Promise<void> {
    await this.local.wipe();
    for (const k of KINDS) this.cache.set(k, new Map());
    this.queue = [];
    this.emit();
  }
}
