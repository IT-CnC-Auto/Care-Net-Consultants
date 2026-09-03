import { redirect } from "next/navigation";
import { currentPerson, supabaseServer } from "./supabase-server";

/** Every page starts here: signed in person, RLS bound client, open inbox count for the badge. */
export async function pageContext() {
  const person = await currentPerson();
  if (!person) redirect("/login");
  const sb = await supabaseServer();
  const { count } = await sb.from("approval").select("id", { count: "exact", head: true }).eq("state", "pending");
  return { person, sb, inboxCount: count ?? 0 };
}
