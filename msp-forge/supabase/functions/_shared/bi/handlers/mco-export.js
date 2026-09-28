// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | mco-export (STUB) 26/09/2026
// POST -> 501, always. Never calls MyClinicOnline.
// Prompt B9 "later": inspect_package_v1.json plus artifacts.zip to
// MyClinicOnline and status mco_ingested. Until {{mco_endpoint}} and the
// interface contract exist (the same open item as HSF-3), every Issued report's
// package stays in Supabase with status supabase_stored (bi_transfer_package,
// 061), and the database refuses mco_ingested.
// Env when connected: MCO_BASE_URL, MCO_API_TOKEN (names only, as the File's transfer worker).

import { guarded, requireMethod, notImplemented } from '../http.js';

export const handle = guarded(async (req) => {
  requireMethod(req, 'POST');
  return notImplemented('The MyClinicOnline report export', ['MCO_BASE_URL', 'MCO_API_TOKEN'],
    'MyClinicOnline was not called. Report packages stay in Supabase (supabase_stored) until the MyClinicOnline endpoint exists.');
});
