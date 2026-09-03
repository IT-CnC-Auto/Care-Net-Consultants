/**
 * stt-fallback · Phase 3 · Speech to text only for a recording that arrived without a transcript.
 * Uses a Whisper class REST endpoint (OpenAI compatible transcription API shape, or Azure Speech behind the same contract) at roughly USD 0.006 a minute [CONFIRM].
 * Grok never receives audio. The audio is streamed through and not stored.
 * Body: { audio_url, source_ref, title, channel }
 */
import { serviceClient, deadLetter, json } from "../_shared/supabase.ts";
import { scrubTranscript } from "../_shared/popia.ts";
import { captureFromText } from "../capture-fireflies/index.ts";

const URL_ = Deno.env.get("STT_PROVIDER_URL");   // for example https://api.openai.com/v1/audio/transcriptions
const KEY = Deno.env.get("STT_PROVIDER_KEY");
const MODEL = Deno.env.get("STT_MODEL") ?? "whisper-1";

Deno.serve(async (req) => {
  const db = serviceClient();
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.endsWith(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "-")) return json({ error: "service role only" }, 401);
  const body = await req.json();
  if (!URL_ || !KEY) return json({ error: "STT provider not configured" }, 422);
  try {
    const audio = await fetch(body.audio_url);
    if (!audio.ok) throw new Error(`audio ${audio.status}`);
    const form = new FormData();
    form.append("file", await audio.blob(), "recording.m4a");
    form.append("model", MODEL);
    form.append("response_format", "text");
    const res = await fetch(URL_, { method: "POST", headers: { Authorization: `Bearer ${KEY}` }, body: form });
    if (!res.ok) throw new Error(`STT ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const text = await res.text();
    const scrub = scrubTranscript(text);
    const result = await captureFromText(db, body.channel ?? "stt_fallback", body.source_ref, null, body.title ?? "Recording", scrub.text.slice(0, 20000), scrub.droppedLines + scrub.redactions);
    return json(result);
  } catch (e) { await deadLetter(db, "stt-fallback", { source_ref: body.source_ref }, e); return json({ error: String(e) }, 500); }
});
