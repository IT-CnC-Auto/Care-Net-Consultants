// How a failed push is treated, from the error PostgREST, Supabase Storage or
// an Edge Function returned. Pure, so it is tested (src/backend/__tests__).

import type { PushOutcome } from '@/lib/sync-queue';

export interface PgLikeError {
  code?: string | null;
  message?: string | null;
  status?: number | null;
}

const NOT_DEPLOYED = new Set(['PGRST205', 'PGRST202', '42P01', '42883']);
const REJECTED = new Set(['42501', '23514', '23502', '23503', '22023', '22P02', 'P0001', 'P0002', '28000']);

export function classifyPushError(e: PgLikeError | null | undefined, op: 'insert' | 'update' | 'upload' | 'rpc'): PushOutcome {
  if (!e) return { kind: 'retry', error: 'Unknown error' };
  const msg = (e.message ?? '').slice(0, 300);
  const code = e.code ?? '';
  if (code === '23505' && (op === 'insert' || op === 'upload')) return { kind: 'ok' };
  if (NOT_DEPLOYED.has(code) || e.status === 404 || e.status === 501) {
    return { kind: 'waiting_server', error: 'The server part for this is not switched on yet. It is kept on the phone and sent later.' };
  }
  if (REJECTED.has(code) || (typeof e.status === 'number' && e.status >= 400 && e.status < 500 && e.status !== 408 && e.status !== 429)) {
    return { kind: 'rejected', error: `The server refused this change${code ? ` (code ${code})` : ''}. A Care Net sales executive can look into it.` };
  }
  if (/network|fetch|timed? ?out|offline|connection/i.test(msg) || !code) return { kind: 'retry', error: msg || 'No connection' };
  return { kind: 'retry', error: msg || 'The server could not be reached.' };
}
