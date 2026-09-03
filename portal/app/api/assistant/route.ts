import { NextResponse, type NextRequest } from "next/server";
import { supabaseServer } from "@/lib/supabase-server";
/** Ask the assistant. Forwards the question to the agent-extract Edge Function with the person's own JWT. */
export async function POST(req: NextRequest) {
  const form = await req.formData();
  const sb = await supabaseServer();
  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch(`${process.env.NEXT_PUBLIC_FUNCTIONS_URL}/agent-extract`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${session?.access_token ?? ""}` }, body: JSON.stringify({ question: form.get("question"), task_id: form.get("task_id") ?? undefined }) });
  return NextResponse.json(await res.json());
}
