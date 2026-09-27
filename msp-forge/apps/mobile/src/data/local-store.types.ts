import type { SyncItem } from '@/lib/sync-queue';

/**
 * Where the phone keeps its records and the sync queue. On iOS and Android it
 * is SQLite (expo-sqlite, local-store.ts); on the web preview it is the
 * browser's localStorage (local-store.web.ts), enough to walk the demo.
 */
export interface LocalStore {
  readonly name: string;
  loadAll(): Promise<{ kind: string; id: string; data: Record<string, unknown> }[]>;
  put(kind: string, id: string, data: Record<string, unknown>): Promise<void>;
  remove(kind: string, id: string): Promise<void>;
  loadQueue(): Promise<SyncItem[]>;
  saveQueue(items: readonly SyncItem[]): Promise<void>;
  kvGet(key: string): Promise<string | null>;
  kvSet(key: string, value: string | null): Promise<void>;
  wipe(): Promise<void>;
}
