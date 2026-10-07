// Web preview store: the browser's localStorage. expo-sqlite on the web needs
// extra bundler and header set up, so the web build (used for the demo walk
// through and the screenshots) keeps the same records here instead. Photos and
// voice notes taken in a browser live only for the session.

import type { SyncItem } from '@/lib/sync-queue';

import type { LocalStore } from './local-store.types';

const memory = new Map<string, string>();

function storage(): { getItem(k: string): string | null; setItem(k: string, v: string): void; removeItem(k: string): void } {
  try {
    if (typeof window !== 'undefined' && window.localStorage) return window.localStorage;
  } catch {
    // Private mode or blocked storage: fall back to memory.
  }
  return {
    getItem: (k) => (memory.has(k) ? (memory.get(k) as string) : null),
    setItem: (k, v) => void memory.set(k, v),
    removeItem: (k) => void memory.delete(k),
  };
}

export async function openLocalStore(mode: 'demo' | 'live'): Promise<LocalStore> {
  const prefix = mode === 'demo' ? 'bi-demo:' : 'bi-live:';
  const s = storage();
  const read = <T,>(key: string, fallback: T): T => {
    try {
      const v = s.getItem(prefix + key);
      return v ? (JSON.parse(v) as T) : fallback;
    } catch {
      return fallback;
    }
  };
  const write = (key: string, value: unknown) => {
    try {
      s.setItem(prefix + key, JSON.stringify(value));
    } catch {
      // Quota reached: the session keeps working from memory.
    }
  };
  let records = read<Record<string, Record<string, unknown>>>('records', {});

  return {
    name: prefix + 'localStorage',
    async loadAll() {
      return Object.entries(records).map(([key, data]) => {
        const i = key.indexOf('/');
        return { kind: key.slice(0, i), id: key.slice(i + 1), data };
      });
    },
    async put(kind, id, data) {
      records = { ...records, [`${kind}/${id}`]: data };
      write('records', records);
    },
    async remove(kind, id) {
      const next = { ...records };
      delete next[`${kind}/${id}`];
      records = next;
      write('records', records);
    },
    async loadQueue() {
      return read<SyncItem[]>('queue', []);
    },
    async saveQueue(items) {
      write('queue', items);
    },
    async kvGet(key) {
      return read<string | null>('kv:' + key, null);
    },
    async kvSet(key, value) {
      if (value === null) s.removeItem(prefix + 'kv:' + key);
      else write('kv:' + key, value);
    },
    async wipe() {
      records = {};
      for (const k of ['records', 'queue']) s.removeItem(prefix + k);
    },
  };
}
