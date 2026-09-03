/**
 * digest · Phase 1 · One daily digest per person at 07:00 SAST through Graph sendMail. Real time noise is opt in.
 * Counts only: what is due, what waits on a signature, what the agents did. No employee names.
 */
import { serviceClient, TENANT_ID, deadLetter, markSync, json } from "../_shared/supabase.ts";
import { sendMail } from "../_shared/graph.ts";

const FROM = Deno.env.get("DIGEST_FROM") ?? "portal@carenetconsultants.co.za";
const PORTAL_URL = Deno.env.get("PORTAL_URL") ?? "https://tasks.carenetconsultants.co.za";

Deno.serve(async () => {
  const db = serviceClient();
  const { data: people } = await db.from("person").select("id, email, full_name").eq("tenant_id", TENANT_ID).eq("is_service_account", false);
  const today = new Date().toISOString().slice(0, 10);
  let sent = 0;
  for (const p of people ?? []) {
    try {
      const [{ count: due }, { count: overdue }, { count: sig }, { count: runs }] = await Promise.all([
        db.from("task").select("id", { count: "exact", head: true }).eq("assignee_id", p.id).eq("due_date", today).neq("status", "completed"),
        db.from("task").select("id", { count: "exact", head: true }).eq("assignee_id", p.id).eq("status", "overdue"),
        db.from("approval").select("id", { count: "exact", head: true }).eq("approver_id", p.id).eq("state", "pending"),
        db.from("agent_run").select("id", { count: "exact", head: true }).gte("started_at", new Date(Date.now() - 86_400_000).toISOString()),
      ]);
      if (!due && !overdue && !sig) continue; // calm default: nothing to say, no email
      const html = `<p>Good morning ${p.full_name.split(" ")[0]}.</p><ul><li>Due today: <strong>${due ?? 0}</strong></li><li>Overdue: <strong>${overdue ?? 0}</strong></li><li>Waiting on your signature: <strong>${sig ?? 0}</strong></li><li>Agent runs in the last 24 hours: ${runs ?? 0}</li></ul><p><a href="${PORTAL_URL}/work">Open My work</a></p><p style="color:#787878;font-size:12px">Care Net Consultants · counts only, no employee names in email.</p>`;
      await sendMail(FROM, p.email, `Your Care Net desk for ${today}`, html);
      sent++;
    } catch (e) { await deadLetter(db, "digest", { person: p.id }, e); }
  }
  await markSync(db, "graph_mail", true, { digest_sent: sent });
  return json({ sent });
});
