/**
 * teams-exceptions · Phase 2
 * Posts exceptions only (SLA at risk, signature waiting more than 24 hours, failed sync) to a Teams channel through an incoming webhook.
 * Counts and refs only, never names of employees or clients' contacts. Runs hourly from pg_cron or on demand.
 */
import { serviceClient, TENANT_ID, deadLetter, json } from "../_shared/supabase.ts";

const WEBHOOK = Deno.env.get("TEAMS_EXCEPTIONS_WEBHOOK_URL");
const PORTAL_URL = Deno.env.get("PORTAL_URL") ?? "https://tasks.carenetconsultants.co.za";

Deno.serve(async () => {
  const db = serviceClient();
  if (!WEBHOOK) return json({ skipped: "TEAMS_EXCEPTIONS_WEBHOOK_URL not set" });
  try {
    const dayAgo = new Date(Date.now() - 86_400_000).toISOString();
    const [{ data: sla }, { data: stale }, { data: failed }] = await Promise.all([
      db.from("task").select("ref, sla_breach_probability").gte("sla_breach_probability", 0.6).neq("status", "completed"),
      db.from("approval").select("id, title").eq("state", "pending").lt("created_at", dayAgo),
      db.from("integration_sync").select("connector").eq("status", "failed"),
    ]);
    const facts: { name: string; value: string }[] = [];
    if (sla?.length) facts.push({ name: "SLA at risk", value: sla.map((t) => `${t.ref} (${Math.round((t.sla_breach_probability ?? 0) * 100)}%)`).join(", ") });
    if (stale?.length) facts.push({ name: "Signatures waiting over 24 hours", value: String(stale.length) });
    if (failed?.length) facts.push({ name: "Connectors failed", value: failed.map((f) => f.connector).join(", ") });
    if (!facts.length) return json({ posted: false, reason: "no exceptions" });
    const card = {
      type: "message",
      attachments: [{ contentType: "application/vnd.microsoft.card.adaptive", content: {
        $schema: "http://adaptivecards.io/schemas/adaptive-card.json", type: "AdaptiveCard", version: "1.4",
        body: [{ type: "TextBlock", text: "Care Net sales tasks · exceptions", weight: "Bolder", size: "Medium" }, { type: "FactSet", facts }],
        actions: [{ type: "Action.OpenUrl", title: "Open Inbox", url: `${PORTAL_URL}/inbox` }],
      } }],
    };
    const res = await fetch(WEBHOOK, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(card) });
    if (!res.ok) throw new Error(`Teams webhook ${res.status}`);
    return json({ posted: true, facts: facts.length, tenant: TENANT_ID });
  } catch (e) { await deadLetter(db, "teams-exceptions", {}, e); return json({ error: String(e) }, 500); }
});
