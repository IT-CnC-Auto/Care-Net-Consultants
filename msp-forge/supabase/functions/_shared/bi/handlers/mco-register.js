// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | mco-register 26/09/2026
// POST (service role) {client_account_id} -> 200 {client_account_id, nodes, status: 'registered_local', note}
// Registers the company, its sites and departments as MyClinicOnline nodes in
// Supabase only (bi_mco_register, 063; prompt B9 "now"). MyClinicOnline is
// never called: {{mco_endpoint}} does not exist yet, and linking a node is
// refused by the database until it does.
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { v } from '../validate.js';
import { guarded, json, requireMethod, readJson, requireService, createDb, supabaseDeps } from '../http.js';

const Body = v.object({ client_account_id: v.uuid() });

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  requireService(req, deps.env);
  const body = Body.parse(await readJson(req, 512));
  return json(await createDb(supabaseDeps(deps)).rpc('bi_mco_register', { p_client_account_id: body.client_account_id }));
});
