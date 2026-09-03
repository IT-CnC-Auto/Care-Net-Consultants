"use client";
import Image from "next/image";
import { supabaseBrowser } from "@/lib/supabase-browser";

export default function Login() {
  async function signIn() {
    const sb = supabaseBrowser();
    await sb.auth.signInWithOAuth({ provider: "azure", options: { scopes: "email openid profile", redirectTo: `${window.location.origin}/auth/callback` } });
  }
  return (
    <main className="flex min-h-screen items-center justify-center bg-cnc-panel">
      <div className="flex w-[400px] flex-col gap-4 rounded-md border border-cnc-line bg-white p-8 shadow-card">
        <Image src="/cnc-logo-trim.png" alt="Care Net Consultants" width={120} height={80} priority />
        <h1 className="text-[22px] font-semibold">Sign in</h1>
        <p className="text-[13px] text-cnc-mute">Use your Care Net Microsoft 365 account. Your role and what you may see come from the oversight tree, not from this screen.</p>
        <button onClick={signIn} className="h-11 rounded-sm bg-cnc-red text-[13px] font-semibold text-white">Continue with Microsoft</button>
        <p className="text-[11.5px] text-cnc-mute">Signing in is logged. Information Officer: [CONFIRM].</p>
      </div>
    </main>
  );
}
