/**
 * approvals-act · Phase 1 · The human gate. Body: { approval_id, decision: 'approve'|'reject', option?: string, edits?: object }
 * Runs with the caller's JWT for the read (RLS decides if they may see it), then the service role performs the consequence and audits it.
 * Nothing here sends an email to a client: an approved outbound_email is queued as a send instruction for the person's own Outlook (Graph sendMail from their mailbox).
 */
import { serviceClient, userClient, TENANT_ID, audit, json } from "../_shared/supabase.ts";
import { sendMail } from "../_shared/graph.ts";
import { emailBodyIsSafe } from "../_shared/popia.ts";

Deno.serve(async (req) => {
  const me = userClient(req);
  const uid = (await me.auth.getUser()).data.user?.id;
  const { data: person } = await me.from("person").select("id, email, full_name, role").eq("auth_user_id", uid ?? "").maybeSingle();
  if (!person) return json({ error: "not signed in" }, 401);
  const body = await req.json();
  const { data: approval } = await me.from("approval").select("*").eq("id", body.approval_id).maybeSingle();
  if (!approval) return json({ error: "approval not visible to you" }, 404);
  if (approval.state !== "pending") return json({ error: "already decided" }, 409);
  const mayDecide = approval.approver_id === person.id || ["franchise_director", "sales_manager"].includes(person.role);
  if (!mayDecide) return json({ error: "you are not the named signer" }, 403);

  const db = serviceClient();
  const decision = body.decision === "approve" ? "approved" : "rejected";
  let consequence: Record<string, unknown> = {};
  if (decision === "approved") consequence = await apply(db, approval, body.option, body.edits, person);
  await db.from("approval").update({ state: decision, decided_by: person.id, decided_at: new Date().toISOString(), decision: body.option ?? body.decision }).eq("id", approval.id);
  await audit(db, `approval.${decision}`, "approval", approval.id, { kind: approval.kind, option: body.option, consequence }, "person", person.id);
  return json({ state: decision, consequence });
});

async function apply(db: any, a: any, option: string | undefined, edits: any, person: any): Promise<Record<string, unknown>> {
  switch (a.kind) {
    case "allocation":
    case "threshold": {
      const assignee = option === "alternative" ? a.payload.alternative_assignee : (a.payload.proposed_assignee ?? edits?.assignee_id);
      if (!assignee || !a.task_id) return { note: "no assignee" };
      await db.from("task").update({ assignee_id: assignee }).eq("id", a.task_id);
      await db.from("task").update({ assignee_id: assignee }).eq("parent_id", a.task_id).is("assignee_id", null);
      return { assigned_to: assignee };
    }
    case "reassignment": {
      await db.from("task").update({ assignee_id: a.payload.to }).eq("id", a.task_id);
      return { assigned_to: a.payload.to };
    }
    case "outbound_email": {
      const draft = edits?.draft_email ?? a.payload.draft_email;
      const safe = emailBodyIsSafe(draft ?? "");
      if (!safe.ok) return { blocked: safe.reason };
      // Sent from the signer's own mailbox so the client sees a person, and the record sits in their Sent items.
      if (a.payload.to && draft) { await sendMail(person.email, a.payload.to, a.payload.subject ?? "Care Net Consultants", draft); }
      await db.from("task").update({ status: "in_progress" }).eq("id", a.task_id);
      return { sent_from: person.email, sent: !!a.payload.to };
    }
    case "captured_task": {
      if (option === "discard") return { discarded: true };
      const tasks = edits?.tasks ?? a.payload.tasks ?? [];
      const created: string[] = [];
      for (const t of tasks) {
        const due = new Date(); due.setDate(due.getDate() + (t.due_in_days ?? 3));
        const { data: parent } = t.client_id ? await db.from("task").select("id").eq("client_id", t.client_id).is("parent_id", null).neq("status", "completed").order("created_at", { ascending: false }).limit(1).maybeSingle() : { data: null };
        const { data: row } = await db.from("task").insert({ tenant_id: TENANT_ID, parent_id: parent?.id ?? null, client_id: t.client_id, title: t.title, stage: t.stage, source: "capture", source_ref: a.payload.source_ref, source_url: a.payload.source_url, assignee_id: person.id, due_date: due.toISOString().slice(0, 10), created_by: person.id }).select("ref").single();
        created.push(row.ref);
      }
      return { created };
    }
    case "schedule_block": {
      await db.from("task").update({ start_date: a.payload.date, pinned: !!edits?.pin }).eq("id", a.task_id);
      return { scheduled: a.payload.date };
    }
    case "close_from_mco": {
      await db.from("task").update({ status: "completed", completed_at: new Date().toISOString() }).eq("id", a.task_id);
      return { closed: true };
    }
  }
  return {};
}
