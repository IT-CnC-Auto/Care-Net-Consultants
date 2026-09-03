import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

/** Service role client. Only ever used inside Edge Functions. Bypasses RLS, so every write is audited explicitly. */
export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(url, key, { auth: { persistSession: false } });
}

/** Client bound to the caller's JWT, so RLS applies to what a signed in person may do. */
export function userClient(req: Request): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  return createClient(url, anon, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
}

export const TENANT_ID = Deno.env.get("TENANT_ID") ?? "00000000-0000-0000-0000-000000000001";

export async function audit(db: SupabaseClient, action: string, entity: string, entityId: string | null, detail: Record<string, unknown> = {}, actorKind = "agent", actorPersonId: string | null = null) {
  await db.from("audit_log").insert({ tenant_id: TENANT_ID, action, entity, entity_id: entityId, detail, actor_kind: actorKind, actor_person_id: actorPersonId });
}

export async function deadLetter(db: SupabaseClient, fn: string, payload: unknown, error: unknown) {
  await db.from("dead_letter").insert({ tenant_id: TENANT_ID, function_name: fn, payload, error: String(error) });
}

export async function markSync(db: SupabaseClient, connector: string, ok: boolean, detail: Record<string, unknown> = {}) {
  const now = new Date().toISOString();
  await db.from("integration_sync").upsert({
    tenant_id: TENANT_ID, connector, status: ok ? "ok" : "failed", last_run_at: now, ...(ok ? { last_ok_at: now } : {}), detail,
  }, { onConflict: "tenant_id,connector" });
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
