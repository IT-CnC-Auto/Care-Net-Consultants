// Resumable, chunked evidence upload, as pure functions over an UploadState
// (docs/bee-inspect/p4/evidence-storage.md, "Upload"). The phone:
//   1. asks the server for an upload session for a blob (hash, size, type);
//      the server answers "already held" when it has the hash (dedupe across
//      devices), so nothing is sent twice;
//   2. sends the chunks it has not sent yet, in order, one at a time; a lost
//      connection resumes at the first chunk not acknowledged;
//   3. asks the server to assemble the blob and hash it, and compares the
//      server's SHA 256 with its own: a match marks the upload verified, a
//      mismatch throws away the session and starts again (integrity check).
// The server side (evidence-upload-session, -chunk, -complete) is a STUB until
// the staging backend exists: live mode parks the item, demo mode simulates it.

import type { UploadState } from './types';

/** 5 MiB: large enough to keep requests few, small enough to resume cheaply on a weak signal. */
export const CHUNK_BYTES = 5 * 1024 * 1024;

export interface Chunk {
  index: number;
  start: number;
  /** Exclusive. */
  end: number;
}

export function planChunks(size: number, chunkBytes = CHUNK_BYTES): Chunk[] {
  if (!Number.isFinite(size) || size <= 0) throw new RangeError('A file to upload has at least one byte.');
  if (!Number.isInteger(chunkBytes) || chunkBytes <= 0) throw new RangeError('Chunk size must be a positive whole number.');
  const out: Chunk[] = [];
  for (let i = 0, start = 0; start < size; i++, start += chunkBytes) out.push({ index: i, start, end: Math.min(size, start + chunkBytes) });
  return out;
}

export function newUpload(sha256: string, size: number, chunkBytes = CHUNK_BYTES): UploadState {
  planChunks(size, chunkBytes);
  return { session_id: null, sha256, size_bytes: size, chunk_bytes: chunkBytes, done: [], verified: false, verified_sha256: null, attempts: 0, last_error: null };
}

export function withSession(u: UploadState, sessionId: string, alreadyReceived: readonly number[] = []): UploadState {
  const total = planChunks(u.size_bytes, u.chunk_bytes).length;
  const done = Array.from(new Set([...u.done, ...alreadyReceived])).filter((i) => i >= 0 && i < total).sort((a, b) => a - b);
  return { ...u, session_id: sessionId, done };
}

/** The chunks still to send, in order (resume point first). */
export function remainingChunks(u: UploadState): Chunk[] {
  const done = new Set(u.done);
  return planChunks(u.size_bytes, u.chunk_bytes).filter((c) => !done.has(c.index));
}

export function markChunkDone(u: UploadState, index: number): UploadState {
  if (u.done.includes(index)) return u;
  return { ...u, done: [...u.done, index].sort((a, b) => a - b), last_error: null };
}

export function allChunksSent(u: UploadState): boolean {
  return remainingChunks(u).length === 0;
}

export function progress(u: UploadState): number {
  const total = planChunks(u.size_bytes, u.chunk_bytes).length;
  return u.verified ? 1 : u.done.length / total;
}

/**
 * The integrity check after the server assembled the blob: its hash must be
 * the phone's hash. A mismatch starts the upload again from nothing.
 */
export function verifyUpload(u: UploadState, serverSha256: string): { state: UploadState; ok: boolean } {
  if (serverSha256.toLowerCase() === u.sha256.toLowerCase()) return { ok: true, state: { ...u, verified: true, verified_sha256: serverSha256.toLowerCase(), last_error: null } };
  return { ok: false, state: { ...u, session_id: null, done: [], verified: false, verified_sha256: null, attempts: u.attempts + 1, last_error: 'The server copy did not match the phone copy; sending it again.' } };
}

/** The server already holds these bytes (another version or another phone sent them): no bytes move. */
export function alreadyHeld(u: UploadState, serverSha256: string): UploadState {
  return verifyUpload(u, serverSha256).state;
}

export function failAttempt(u: UploadState, error: string): UploadState {
  return { ...u, attempts: u.attempts + 1, last_error: error };
}
