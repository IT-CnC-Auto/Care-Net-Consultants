/**
 * zoom-webhook · Phase 3 · Only where a client insists on Zoom.
 * Handles Zoom's endpoint.url_validation challenge and recording.completed. Downloads the VTT transcript with the payload's download_token
 * (audio transcript is included on Zoom Pro and above [CONFIRM plan]). Falls back to stt-fallback when no transcript file exists.
 */
import { serviceClient, deadLetter, markSync, json } from "../_shared/supabase.ts";
import { scrubTranscript } from "../_shared/popia.ts";
import { captureFromText } from "../capture-fireflies/index.ts";
import { vttToText } from "../graph-transcript/index.ts";

const SECRET = Deno.env.get("ZOOM_WEBHOOK_SECRET_TOKEN") ?? "";
const FUNCTIONS_URL = Deno.env.get("FUNCTIONS_URL") ?? "";

async function hmacHex(key: string, msg: string) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(msg));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  const raw = await req.text();
  const body = JSON.parse(raw || "{}");
  if (body.event === "endpoint.url_validation") {
    return json({ plainToken: body.payload.plainToken, encryptedToken: await hmacHex(SECRET, body.payload.plainToken) });
  }
  // verify x-zm-signature: v0=HMAC(secret, "v0:" + ts + ":" + body)
  const ts = req.headers.get("x-zm-request-timestamp") ?? "";
  const expected = `v0=${await hmacHex(SECRET, `v0:${ts}:${raw}`)}`;
  if (SECRET && req.headers.get("x-zm-signature") !== expected) return json({ error: "bad signature" }, 401);
  if (body.event !== "recording.completed") return json({ ignored: body.event });
  const db = serviceClient();
  try {
    const obj = body.payload.object;
    const files: any[] = obj.recording_files ?? [];
    const transcript = files.find((f) => f.file_type === "TRANSCRIPT" || f.recording_type === "audio_transcript");
    if (!transcript) {
      const audio = files.find((f) => f.file_type === "M4A");
      if (!audio) return json({ skipped: "no transcript or audio" });
      const r = await fetch(`${FUNCTIONS_URL}/stt-fallback`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}` }, body: JSON.stringify({ audio_url: `${audio.download_url}?access_token=${body.download_token}`, source_ref: String(obj.uuid), title: obj.topic, channel: "zoom_transcript" }) });
      return json({ forwarded_to_stt: r.status });
    }
    const vtt = await (await fetch(`${transcript.download_url}?access_token=${body.download_token}`)).text();
    const scrub = scrubTranscript(vttToText(vtt));
    const result = await captureFromText(db, "zoom_transcript", String(obj.uuid), obj.share_url ?? null, obj.topic ?? "Zoom meeting", scrub.text.slice(0, 20000), scrub.droppedLines + scrub.redactions);
    await markSync(db, "zoom", true, { last_meeting: obj.uuid });
    return json(result);
  } catch (e) { await deadLetter(db, "zoom-webhook", body, e); await markSync(db, "zoom", false, { error: String(e) }); return json({ error: String(e) }, 500); }
});
