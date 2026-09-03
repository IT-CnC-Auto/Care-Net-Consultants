"use server";
import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase-server";
import { parseQuick } from "@/lib/quick";

async function callFunction(name: string, body: unknown) {
  const sb = await supabaseServer();
  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch(`${process.env.NEXT_PUBLIC_FUNCTIONS_URL}/${name}`, {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${session?.access_token ?? ""}` }, body: JSON.stringify(body),
  });
  return res.json();
}

/** The human gate. decision approve | reject, option is one of the approval's options. */
export async function decide(formData: FormData) {
  const approval_id = String(formData.get("approval_id"));
  const decision = String(formData.get("decision") ?? "approve");
  const option = formData.get("option") ? String(formData.get("option")) : undefined;
  await callFunction("approvals-act", { approval_id, decision, option });
  revalidatePath("/inbox"); revalidatePath("/work"); revalidatePath("/desk");
}

/** One tap tick. Completing a parent completes nothing else; every leaf is its own tick. */
export async function tick(formData: FormData) {
  const sb = await supabaseServer();
  const id = String(formData.get("task_id"));
  const done = formData.get("done") === "true";
  await sb.from("task").update(done ? { status: "completed", completed_at: new Date().toISOString() } : { status: "new", completed_at: null }).eq("id", id);
  revalidatePath("/work"); revalidatePath(`/tasks/${id}`);
}

export async function pin(formData: FormData) {
  const sb = await supabaseServer();
  await sb.from("task").update({ pinned: formData.get("pinned") === "true" }).eq("id", String(formData.get("task_id")));
  revalidatePath("/work");
}

export async function comment(formData: FormData) {
  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  const { data: me } = await sb.from("person").select("id").eq("auth_user_id", user?.id ?? "").maybeSingle();
  const task_id = String(formData.get("task_id"));
  await sb.from("task_comment").insert({ task_id, author_id: me?.id, body: String(formData.get("body")) });
  revalidatePath(`/tasks/${task_id}`);
}

export async function toggleRule(formData: FormData) {
  const sb = await supabaseServer();
  await sb.from("rule").update({ enabled: formData.get("enabled") === "true" }).eq("id", String(formData.get("rule_id")));
  revalidatePath("/automations");
}

export async function logFocus(formData: FormData) {
  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  const { data: me } = await sb.from("person").select("id").eq("auth_user_id", user?.id ?? "").maybeSingle();
  await sb.from("time_entry").insert({ task_id: String(formData.get("task_id")), person_id: me?.id, minutes: Number(formData.get("minutes") ?? 25), kind: "focus" });
  revalidatePath(`/tasks/${formData.get("task_id")}`);
}

/** Quick add with natural language dates in en-ZA: "call Thabo Friday 9am", "next Tuesday", "every last Friday" (recurrence to backlog). */
export async function quickAdd(text: string) {
  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  const { data: me } = await sb.from("person").select("id, tenant_id").eq("auth_user_id", user?.id ?? "").maybeSingle();
  if (!me) return;
  const { title, due } = parseQuick(text);
  await sb.from("task").insert({ tenant_id: me.tenant_id, title, source: "manual", assignee_id: me.id, created_by: me.id, due_date: due });
  revalidatePath("/work");
}
