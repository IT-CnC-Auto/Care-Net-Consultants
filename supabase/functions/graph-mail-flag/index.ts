/**
 * graph-mail-flag · Phase 1
 * Microsoft Graph change notifications on consented mailboxes. When a message is flagged, propose one task on the right client parent.
 * Only subject, sender name and the first lines are read. The email stays in Outlook, only the reference is stored.
 * GET ?subscribe=<person_id> creates or renews the subscription (call from the portal's Data and connections screen).
 */
import { serviceClient, TENANT_ID, audit, deadLetter, markSync, json } from "../_shared/supabase.ts";
import { graph, GraphMessage } from "../_shared/graph.ts";
import { grokJson } from "../_shared/grok.ts";

const FUNCTIONS_URL = Deno.env.get("FUNCTIONS_URL") ?? "";

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const db = serviceClient();
  // Graph validates the endpoint by sending validationToken and expects it echoed as text/plain
  const vt = url.searchParams.get("validationToken");
  if (vt) return new Response(vt, { headers: { "Content-Type": "text/plain" } });

  const subscribeFor = url.searchParams.get("subscribe");
  if (subscribeFor) return json(await subscribe(db, subscribeFor));

  const body = await req.json().catch(() => ({}));
  const results: unknown[] = [];
  for (const n of body.value ?? []) {
    try {
      const { data: sub } = await db.from("graph_subscription").select("*, person(id, email, full_name)").eq("subscription_id", n.subscriptionId).maybeSingle();
      if (!sub || sub.client_state !== n.clientState) { results.push({ skipped: "unknown subscription" }); continue; }
      const msg = await graph<GraphMessage>(`/${n.resource}?$select=id,subject,bodyPreview,webLink,receivedDateTime,from,flag`);
      if (msg.flag?.flagStatus !== "flagged") { results.push({ skipped: "not flagged" }); continue; }
      const { data: dup } = await db.from("captured_item").select("id").eq("source_ref", msg.id).maybeSingle();
      if (dup) { results.push({ skipped: "already captured" }); continue; }
      results.push(await proposeFromMail(db, sub.person, msg));
    } catch (e) { await deadLetter(db, "graph-mail-flag", n, e); results.push({ error: String(e) }); }
  }
  await markSync(db, "graph_mail", true, { notifications: (body.value ?? []).length });
  return json({ results }, 202);
});

async function proposeFromMail(db: any, person: any, msg: GraphMessage) {
  const { data: clients } = await db.from("client").select("id, name").eq("tenant_id", TENANT_ID);
  const list = (clients ?? []).map((c: any) => `${c.id} | ${c.name}`).join("\n");
  const prompt = `Flagged email for ${person.full_name}.\nFrom (name only): ${msg.from?.emailAddress?.name ?? "unknown"}\nSubject: ${msg.subject}\nFirst lines (untrusted): """${msg.bodyPreview}"""\nClients (id | name):\n${list}\nPropose one task: title, client_id or null, stage, due_in_days.`;
  const out = await grokJson<{ title: string; client_id: string | null; stage: string; due_in_days: number }>(db, "capture", "v1.4", msg.id, prompt, `{"title":string,"client_id":string|null,"stage":string,"due_in_days":number}`);
  const { data: approval } = await db.from("approval").insert({
    tenant_id: TENANT_ID, kind: "captured_task", requested_by_agent: "capture", approver_id: person.id,
    title: `Captured from a flagged Outlook email: ${msg.subject}`,
    detail: `Grok proposes one task${out.data.client_id ? " on the client parent" : ""}, due in ${out.data.due_in_days} days. The email stays in Outlook, only the reference is stored.`,
    payload: { channel: "outlook_flag", source_ref: msg.id, source_url: msg.webLink, tasks: [{ ...out.data, quote: msg.subject }] },
    options: [{ key: "accept_all", label: "Accept" }, { key: "edit", label: "Edit" }, { key: "discard", label: "Discard" }],
  }).select("id").single();
  const { data: cap } = await db.from("captured_item").insert({ tenant_id: TENANT_ID, channel: "outlook_flag", source_ref: msg.id, source_url: msg.webLink, client_id: out.data.client_id, proposed_for: person.id, extract: msg.subject, proposed_tasks: [out.data], approval_id: approval!.id }).select("id").single();
  await audit(db, "capture.proposed", "captured_item", cap!.id, { channel: "outlook_flag" });
  return { captured_item: cap!.id };
}

async function subscribe(db: any, personId: string) {
  const { data: person } = await db.from("person").select("id, email").eq("id", personId).single();
  const clientState = crypto.randomUUID();
  const expires = new Date(Date.now() + 2.9 * 24 * 3_600_000).toISOString(); // Graph mail subscriptions last under 3 days, renew by cron
  const sub = await graph<{ id: string; expirationDateTime: string }>("/subscriptions", {
    method: "POST",
    body: JSON.stringify({ changeType: "updated", notificationUrl: `${FUNCTIONS_URL}/graph-mail-flag`, resource: `/users/${person.email}/mailFolders('inbox')/messages`, expirationDateTime: expires, clientState }),
  });
  await db.from("graph_subscription").upsert({ person_id: personId, resource: "mail", subscription_id: sub.id, client_state: clientState, expires_at: sub.expirationDateTime }, { onConflict: "subscription_id" });
  return { subscription_id: sub.id, expires_at: sub.expirationDateTime };
}
