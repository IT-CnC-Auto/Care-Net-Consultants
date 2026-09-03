/** translate · Phase 1 · Body: { entity, entity_id, field, text, to }. Stores original and translation side by side. */
import { serviceClient, userClient, json, deadLetter, markSync } from "../_shared/supabase.ts";
import { translateAndStore } from "../_shared/translate.ts";

Deno.serve(async (req) => {
  const me = userClient(req);
  if (!(await me.auth.getUser()).data.user) return json({ error: "not signed in" }, 401);
  const body = await req.json();
  const db = serviceClient();
  try {
    const text = await translateAndStore(db, body.entity, body.entity_id, body.field, body.text, body.to);
    await markSync(db, "translator", true);
    return json({ translated: text });
  } catch (e) { await deadLetter(db, "translate", body, e); await markSync(db, "translator", false, { error: String(e) }); return json({ error: String(e) }, 500); }
});
