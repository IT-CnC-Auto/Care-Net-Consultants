import { NextResponse } from "next/server";
import { supabaseServer } from "@/lib/supabase-server";
/** Excel report as CSV (opens in Excel). Counts and case numbers only. Every export is written to the audit log. */
export async function GET() {
  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  const { data: me } = await sb.from("person").select("id, tenant_id").eq("auth_user_id", user?.id ?? "").maybeSingle();
  const { data } = await sb.from("task").select("ref, title, task_type, status, stage, due_date, source, medical_count, client:client(name), assignee:person!task_assignee_id_fkey(full_name)").neq("status", "completed").order("due_date");
  const rows = [["Ref", "Client", "Task", "Type", "Status", "Stage", "Due", "Owner", "Source", "Medicals"], ...(data ?? []).map((t: any) => [t.ref, t.client?.name ?? "", t.title, t.task_type ?? "", t.status, t.stage ?? "", t.due_date ?? "", t.assignee?.full_name ?? "", t.source, t.medical_count ?? ""])];
  const csv = rows.map((r) => r.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(",")).join("\r\n");
  if (me) await sb.from("audit_log").insert({ tenant_id: me.tenant_id, actor_person_id: me.id, actor_kind: "person", action: "export.csv", entity: "task", detail: { rows: rows.length - 1 } });
  return new NextResponse("﻿" + csv, { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="care-net-tasks-${new Date().toISOString().slice(0, 10)}.csv"` } });
}
