// SQLite store for iOS and Android (expo-sqlite, SDK 57 async API).
// One database per mode, so demonstration data never mixes with live data.

import * as SQLite from 'expo-sqlite';

import type { SyncItem } from '@/lib/sync-queue';

import type { LocalStore } from './local-store.types';

const SCHEMA = `
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS records (
  kind TEXT NOT NULL,
  id TEXT NOT NULL,
  data TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (kind, id)
);
CREATE TABLE IF NOT EXISTS sync_queue (
  id TEXT PRIMARY KEY NOT NULL,
  created_at INTEGER NOT NULL,
  data TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS kv (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);
`;

export async function openLocalStore(mode: 'demo' | 'live'): Promise<LocalStore> {
  const name = mode === 'demo' ? 'bee-inspect-demo.db' : 'bee-inspect.db';
  const db = await SQLite.openDatabaseAsync(name);
  await db.execAsync(SCHEMA);

  return {
    name,
    async loadAll() {
      const rows = await db.getAllAsync<{ kind: string; id: string; data: string }>('SELECT kind, id, data FROM records');
      return rows.map((r) => ({ kind: r.kind, id: r.id, data: JSON.parse(r.data) as Record<string, unknown> }));
    },
    async put(kind, id, data) {
      await db.runAsync(
        'INSERT INTO records (kind, id, data, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(kind, id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at',
        kind,
        id,
        JSON.stringify(data),
        Date.now(),
      );
    },
    async remove(kind, id) {
      await db.runAsync('DELETE FROM records WHERE kind = ? AND id = ?', kind, id);
    },
    async loadQueue() {
      const rows = await db.getAllAsync<{ data: string }>('SELECT data FROM sync_queue ORDER BY created_at, id');
      return rows.map((r) => JSON.parse(r.data) as SyncItem);
    },
    async saveQueue(items: readonly SyncItem[]) {
      await db.withTransactionAsync(async () => {
        await db.runAsync('DELETE FROM sync_queue');
        for (const it of items) {
          await db.runAsync('INSERT INTO sync_queue (id, created_at, data) VALUES (?, ?, ?)', it.id, it.createdAt, JSON.stringify(it));
        }
      });
    },
    async kvGet(key) {
      const row = await db.getFirstAsync<{ value: string }>('SELECT value FROM kv WHERE key = ?', key);
      return row ? row.value : null;
    },
    async kvSet(key, value) {
      if (value === null) await db.runAsync('DELETE FROM kv WHERE key = ?', key);
      else await db.runAsync('INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value', key, value);
    },
    async wipe() {
      await db.execAsync('DELETE FROM records; DELETE FROM sync_queue; DELETE FROM kv;');
    },
  };
}
