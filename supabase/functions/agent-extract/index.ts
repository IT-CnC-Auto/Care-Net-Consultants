/**
 * agent-extract · Phase 1
 * Generic "ask the assistant" endpoint for the portal. The signed in person's JWT is required (RLS applies to what they may read).
 * Body: { question: string, task_id?: string, client_id?: string }
 */
import { serviceClient, userClient, json } from "../_shared/supabase.ts";
import { grokJson } from "../_shared/grok.ts";

Deno.serve(async (req) => {
  const me = userClient(req);
  const { data: person } = await me.from("person").select("id, full_name, role").eq("auth_user_id", (await me.auth.getUser()).data.user?.id ?? "").maybeSingle();
  if (!person) return json({ error: "not signed in" }, 401);
  const body = await req.json();
  const context: string[] = [];
  if (body.task_id) { const { data } = await me.from("task").select("ref, title, status, stage, due_date, task_type, medical_count, rank_reason").eq("id", body.task_id).maybeSingle(); if (data) context.push("Task: " + JSON.stringify(data)); }
  if (body.client_id) { const { data } = await me.from("client").select("name, current_stage, sites, contract_renewal, client_source").eq("id", body.client_id).maybeSingle(); if (data) context.push("Client: " + JSON.stringify(data)); }
  const db = serviceClient();
  const out = await grokJson<{ answer: string; suggested_actions: string[] }>(db, "documentation", "v3.2", body.task_id ?? body.client_id ?? "chat",
    `${context.join("\n")}\nQuestion from ${person.full_name} (${person.role}): ${body.question}`,
    `{"answer":string,"suggested_actions":string[]}`);
  return json({ ...out.data, run_id: out.runId });
});
