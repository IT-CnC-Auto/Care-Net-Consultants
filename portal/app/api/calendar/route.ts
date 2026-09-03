import { NextResponse } from "next/server";
import { supabaseServer } from "@/lib/supabase-server";
/** Focus block proposals for today from the graph-calendar-gaps Edge Function. */
export async function GET() {
  const sb = await supabaseServer();
  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch(`${process.env.NEXT_PUBLIC_FUNCTIONS_URL}/graph-calendar-gaps`, { headers: { Authorization: `Bearer ${session?.access_token ?? ""}` } });
  return NextResponse.json(await res.json());
}
