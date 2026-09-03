import { NextResponse, type NextRequest } from "next/server";
import { supabaseServer } from "@/lib/supabase-server";

/** Exchanges the OAuth code for a session, then links auth.users.id to the person row by email on first sign in. */
export async function GET(req: NextRequest) {
  const code = req.nextUrl.searchParams.get("code");
  const sb = await supabaseServer();
  if (code) {
    const { data } = await sb.auth.exchangeCodeForSession(code);
    const user = data.user;
    if (user?.email) {
      await sb.from("person").update({ auth_user_id: user.id }).eq("email", user.email.toLowerCase()).is("auth_user_id", null);
    }
  }
  return NextResponse.redirect(new URL("/desk", req.url));
}
