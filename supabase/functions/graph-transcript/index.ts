/**
 * graph-transcript · Phase 2
 * Teams native transcripts through Microsoft Graph, replacing Fireflies seats when Care Net chooses to.
 * Two entry points:
 *   POST (Graph change notification on /communications/onlineMeetings/getAllTranscripts) → fetch VTT → scrub → capture
 *   GET ?subscribe=1 → create or renew the subscription (application permission OnlineMeetingTranscript.Read.All, admin consent [CONFIRM], metering [CONFIRM])
 */
import { serviceClient, deadLetter, markSync, json } from "../_shared/supabase.ts";
import { graph } from "../_shared/graph.ts";
import { scrubTranscript } from "../_shared/popia.ts";
import { captureFromText } from "../capture-fireflies/index.ts";

const FUNCTIONS_URL = Deno.env.get("FUNCTIONS_URL") ?? "";

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const vt = url.searchParams.get("validationToken");
  if (vt) return new Response(vt, { headers: { "Content-Type": "text/plain" } });
  const db = serviceClient();
  if (url.searchParams.get("subscribe")) {
    const clientState = crypto.randomUUID();
    const sub = await graph<{ id: string; expirationDateTime: string }>("/subscriptions", { method: "POST", body: JSON.stringify({ changeType: "created", notificationUrl: `${FUNCTIONS_URL}/graph-transcript`, resource: "communications/onlineMeetings/getAllTranscripts", expirationDateTime: new Date(Date.now() + 2.9 * 86_400_000).toISOString(), clientState }) });
    await db.from("graph_subscription").upsert({ resource: "teams_transcript", subscription_id: sub.id, client_state: clientState, expires_at: sub.expirationDateTime }, { onConflict: "subscription_id" });
    return json(sub);
  }
  const body = await req.json().catch(() => ({}));
  const results: unknown[] = [];
  for (const n of body.value ?? []) {
    try {
      const { data: sub } = await db.from("graph_subscription").select("client_state").eq("subscription_id", n.subscriptionId).maybeSingle();
      if (!sub || sub.client_state !== n.clientState) { results.push({ skipped: "unknown subscription" }); continue; }
      // resource looks like communications/onlineMeetings('id')/transcripts('id')
      const meetingUrl = `/${n.resource.replace(/\/transcripts\(.*$/, "")}`;
      const meeting = await graph<{ id: string; subject: string; joinWebUrl: string }>(meetingUrl);
      const vtt = await graph<string>(`/${n.resource}/content?$format=text/vtt`, {}, true);
      const text = vttToText(vtt);
      const scrub = scrubTranscript(text);
      const { data: dup } = await db.from("captured_item").select("id").eq("source_ref", meeting.id).maybeSingle();
      if (dup) { results.push({ skipped: "already captured" }); continue; }
      results.push(await captureFromText(db, "teams_transcript", meeting.id, meeting.joinWebUrl, meeting.subject ?? "Teams meeting", scrub.text.slice(0, 20000), scrub.droppedLines + scrub.redactions));
    } catch (e) { await deadLetter(db, "graph-transcript", n, e); results.push({ error: String(e) }); }
  }
  await markSync(db, "teams_transcript", true, { notifications: (body.value ?? []).length });
  return json({ results }, 202);
});

/** WebVTT to "Speaker: text" lines. Teams puts the speaker in a <v Name> tag. */
export function vttToText(vtt: string): string {
  const out: string[] = [];
  for (const line of vtt.split(/\r?\n/)) {
    if (!line || line === "WEBVTT" || /^\d+$/.test(line) || /-->/.test(line) || /^NOTE/.test(line)) continue;
    const m = line.match(/^<v\s+([^>]+)>(.*?)(<\/v>)?$/);
    out.push(m ? `${m[1]}: ${m[2]}` : line.replace(/<[^>]+>/g, ""));
  }
  return out.join("\n");
}
