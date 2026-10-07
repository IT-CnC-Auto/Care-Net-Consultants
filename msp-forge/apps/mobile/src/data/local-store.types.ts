import type { SyncItem } from '@/lib/sync-queue';

/**
 * Where the phone keeps its records and the sync queue. On iOS and Android it
 * is SQLite (expo-sqlite, local-store.ts); on the web preview it is the
 * browser's localStorage (local-store.web.ts), enough to walk the demo.
 */
/** Full text search held by the store itself (SQLite FTS5 on the phone). */
export interface StoreSearch {
  readonly engine: 'fts5';
  reindex(docs: readonly { id: string; title: string; tags: string; body: string }[]): Promise<void>;
  /** Document ids best first, for an FTS5 MATCH expression. */
  query(match: string, limit: number): Promise<string[]>;
}

export interface LocalStore {
  /** Present when the store has its own full text index (FTS5); otherwise the app's in memory index is used. */
  readonly search?: StoreSearch;
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
