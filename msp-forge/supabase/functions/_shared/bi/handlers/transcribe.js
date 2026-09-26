// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | transcribe (STUB) 26/09/2026
// POST {voice_note_id} -> 501 until the transcription vendor is chosen.
// Prompt B2 and B5: transcription on sync; the audio stays the source of truth
// and each transcript is a version in bi_voice_transcript (source machine),
// written with the service role once a vendor exists, and charged through the
// AI Wallet (kind transcription). Nothing is sent anywhere today.
// Env when connected: TRANSCRIBE_PROVIDER, TRANSCRIBE_API_KEY (names only).

import { guarded, requireMethod, notImplemented } from '../http.js';

export const handle = guarded(async (req) => {
  requireMethod(req, 'POST');
  return notImplemented('Transcription', ['TRANSCRIBE_PROVIDER', 'TRANSCRIBE_API_KEY'],
    'The transcription vendor is not chosen yet. Voice notes are kept as audio; their transcripts will follow on sync once it is.');
});
