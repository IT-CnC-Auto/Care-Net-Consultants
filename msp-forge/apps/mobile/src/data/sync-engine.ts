// Drives the sync queue: when there is signal (and sync is not paused), pushes
// the eligible operations one at a time, applies each outcome (backoff, park,
// conflict) and writes the new row_version and server fields back locally.

import * as Network from 'expo-network';
import { AppState } from 'react-native';

import type { Backend } from '@/backend/types';
import { applyOutcome, eligible, markInFlight, retryItem, resolveConflict } from '@/lib/sync-queue';
import type { Kind } from '@/lib/types';

import type { DataStore } from './data-store';

export interface SyncState {
  online: boolean;
  paused: boolean;
  running: boolean;
  lastSyncAt: number | null;
  lastError: string | null;
}

const TICK_MS = 4000;

export class SyncEngine {
  private state: SyncState = { online: true, paused: false, running: false, lastSyncAt: null, lastError: null };
  private listeners = new Set<() => void>();
  private timer: ReturnType<typeof setInterval> | null = null;
  private cleanups: (() => void)[] = [];

  constructor(
    private readonly store: DataStore,
    private readonly backend: Backend,
  ) {}

  subscribe = (l: () => void) => {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  };

  getState = (): SyncState => this.state;

  private set(p: Partial<SyncState>) {
    this.state = { ...this.state, ...p };
    for (const l of this.listeners) l();
  }

  async start(): Promise<void> {
    const paused = (await this.store.kvGet('sync.paused')) === '1';
    let online = true;
    try {
      const n = await Network.getNetworkStateAsync();
      online = n.isConnected !== false && n.isInternetReachable !== false;
    } catch {
      online = true;
    }
    this.set({ paused, online });
    try {
      const sub = Network.addNetworkStateListener((n) => {
        this.set({ online: n.isConnected !== false && n.isInternetReachable !== false });
        void this.tick();
      });
      this.cleanups.push(() => sub.remove());
    } catch {
      // No network events on this platform: the timer still ticks.
    }
    const app = AppState.addEventListener('change', (s) => {
      if (s === 'active') void this.tick();
    });
    this.cleanups.push(() => app.remove());
    this.timer = setInterval(() => void this.tick(), TICK_MS);
    void this.tick();
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    for (const c of this.cleanups) c();
    this.cleanups = [];
  }

  async setPaused(paused: boolean): Promise<void> {
    await this.store.kvSet('sync.paused', paused ? '1' : null);
    this.set({ paused });
    if (!paused) void this.tick();
  }

  kick(): void {
    void this.tick();
  }

  async retry(itemId: string): Promise<void> {
    await this.store.setQueue(retryItem(this.store.getQueue(), itemId, Date.now()));
    void this.tick();
  }

  async resolve(itemId: string, choice: 'keep_mine' | 'use_server'): Promise<void> {
    const item = this.store.getQueue().find((q) => q.id === itemId);
    if (item && choice === 'use_server') {
      const server = (item.payload as Record<string, unknown>).__server as Record<string, unknown> | undefined;
      if (server) await this.store.patchLocal(item.kind as Kind, item.recordId, server as never);
    }
    const cleaned = this.store.getQueue().map((q) => {
      if (q.id !== itemId) return q;
      const { __server: _drop, ...payload } = q.payload as Record<string, unknown>;
      return { ...q, payload };
    });
    await this.store.setQueue(resolveConflict(cleaned, itemId, choice, Date.now()));
    void this.tick();
  }

  private async tick(): Promise<void> {
    if (this.state.running || this.state.paused || !this.state.online) return;
    this.set({ running: true });
    try {
      for (let round = 0; round < 50; round++) {
        const [item] = eligible(this.store.getQueue(), Date.now(), 1);
        if (!item) break;
        await this.store.setQueue(markInFlight(this.store.getQueue(), [item.id]));
        const outcome = await this.backend.push(item, this.store);
        const res = applyOutcome(this.store.getQueue(), item.id, outcome, Date.now());
        if (outcome.kind === 'conflict' && outcome.server) {
          res.queue = res.queue.map((q) => (q.id === item.id ? { ...q, payload: { ...q.payload, __server: outcome.server } } : q));
        }
        await this.store.setQueue(res.queue);
        if (res.synced) {
          const patch: Record<string, unknown> = { ...(res.synced.patch ?? {}) };
          if (res.synced.rowVersion !== undefined) patch.row_version = res.synced.rowVersion;
          if (Object.keys(patch).length) await this.store.patchLocal(res.synced.kind as Kind, res.synced.recordId, patch as never);
          this.set({ lastSyncAt: Date.now(), lastError: null });
        } else if (outcome.kind !== 'ok') {
          this.set({ lastError: outcome.error });
        }
      }
    } finally {
      this.set({ running: false });
    }
  }
}
