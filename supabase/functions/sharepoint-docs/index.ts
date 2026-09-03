/**
 * sharepoint-docs · Phase 2
 * Creates a document in the client's SharePoint library from a template and links it to the task. Grok never receives the document.
 * Body: { task_id, kind: 'proposal'|'attendance'|'pro_forma', name }
 * Requires Sites.Selected with write access granted to the app on each client library [CONFIRM with the M365 administrator].
 */
import { serviceClient, userClient, TENANT_ID, audit, deadLetter, markSync, json } from "../_shared/supabase.ts";
import { graph } from "../_shared/graph.ts";

const TEMPLATE_DRIVE = Deno.env.get("SHAREPOINT_TEMPLATE_DRIVE_ID");
const TEMPLATE_ITEMS: Record<string, string | undefined> = {
  proposal: Deno.env.get("SHAREPOINT_TEMPLATE_PROPOSAL_ITEM_ID"),
  attendance: Deno.env.get("SHAREPOINT_TEMPLATE_ATTENDANCE_ITEM_ID"),
  pro_forma: Deno.env.get("SHAREPOINT_TEMPLATE_PROFORMA_ITEM_ID"),
};

Deno.serve(async (req) => {
  const me = userClient(req);
  const uid = (await me.auth.getUser()).data.user?.id;
  const { data: person } = await me.from("person").select("id").eq("auth_user_id", uid ?? "").maybeSingle();
  if (!person) return json({ error: "not signed in" }, 401);
  const body = await req.json();
  const { data: task } = await me.from("task").select("id, ref, client:client(id, name, sharepoint_drive_id)").eq("id", body.task_id).maybeSingle();
  if (!task) return json({ error: "task not visible" }, 404);
  const client = (task as any).client;
  if (!client?.sharepoint_drive_id) return json({ error: "client has no SharePoint library linked" }, 422);
  const templateItem = TEMPLATE_ITEMS[body.kind];
  if (!TEMPLATE_DRIVE || !templateItem) return json({ error: `no template for ${body.kind}` }, 422);
  const db = serviceClient();
  try {
    const name = body.name ?? `${task.ref} ${body.kind}.docx`;
    // copy template into the client library root; Graph returns 202 with a monitor URL, the item appears shortly after
    await graph(`/drives/${TEMPLATE_DRIVE}/items/${templateItem}/copy`, { method: "POST", body: JSON.stringify({ parentReference: { driveId: client.sharepoint_drive_id }, name }) });
    // find the copied item by name (eventually consistent, retry a few times)
    let item: any = null;
    for (let i = 0; i < 5 && !item; i++) {
      await new Promise((r) => setTimeout(r, 1500));
      const res = await graph<{ value: any[] }>(`/drives/${client.sharepoint_drive_id}/root/children?$filter=name eq '${name.replace(/'/g, "''")}'`);
      item = res.value?.[0] ?? null;
    }
    const { data: doc } = await db.from("task_document").insert({ task_id: task.id, name, sharepoint_item_id: item?.id ?? null, web_url: item?.webUrl ?? null, created_by: person.id }).select("id").single();
    await audit(db, "sharepoint.document_created", "task_document", doc!.id, { task: task.ref, kind: body.kind }, "person", person.id);
    await markSync(db, "sharepoint", true);
    return json({ document: doc!.id, web_url: item?.webUrl ?? null, pending: !item });
  } catch (e) { await deadLetter(db, "sharepoint-docs", body, e); await markSync(db, "sharepoint", false, { error: String(e) }); return json({ error: String(e) }, 500); }
});
