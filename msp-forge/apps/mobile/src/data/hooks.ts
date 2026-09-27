import { useSyncExternalStore } from 'react';

import { summarise } from '@/lib/sync-queue';
import type { Kind, KindMap } from '@/lib/types';
import { useApp } from '@/state/app';

import type { DataStore } from './data-store';

const noop = () => () => {};

/**
 * The local store, as a handle that changes identity whenever any record or the
 * queue changes, so every read below it is recomputed (the React Compiler
 * memoises on identity). The data sets on a phone are small.
 */
export function useStore(): DataStore {
  const { store } = useApp();
  const view = useSyncExternalStore(store ? store.subscribe : noop, store ? store.getView : () => null, store ? store.getView : () => null);
  if (!view) throw new Error('The local store is not open yet.');
  return view;
}

export function useRecords<K extends Kind>(kind: K, pred?: (r: KindMap[K]) => boolean): KindMap[K][] {
  const store = useStore();
  const all = store.list(kind);
  return pred ? all.filter(pred) : all;
}

export function useRecord<K extends Kind>(kind: K, id: string | null | undefined): KindMap[K] | undefined {
  return useStore().get(kind, id);
}

export function useQueueSummary() {
  const queue = useStore().getQueue();
  return { summary: summarise(queue), queue };
}
