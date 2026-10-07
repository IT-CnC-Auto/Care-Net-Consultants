// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | claim-code-create 26/09/2026
// POST (signed in) {file_id?, ad_id?, page?, utm_source?, utm_medium?, utm_campaign?, utm_content?}
//   -> 201 {code, expires_at, claim_path, claim_url}
// Makes the desktop QR one time code (prompt B3): the code is shown once; only
// its SHA 256 reaches the database (bi_claim_code_create, migration 063), valid
// 10 minutes, at most 5 per person in 10 minutes. The File contact is linked to
// their company account first (hsf_link_account, as the File site does).
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY; BI_CLAIM_LINK_BASE (optional,
// the site address the QR opens; without it only the path is returned).

import { v, AD_ID_RE, UTM_RE, PAGES } from '../validate.js';
import { generateCode, hashCode, claimPath } from '../claim-code.js';
import { guarded, json, requireMethod, readJson, requireUser, createDb, supabaseDeps, HttpError } from '../http.js';

const Body = v.object({
  file_id: v.uuid().optional(),
  ad_id: v.string().regex(AD_ID_RE, 'must be a banner id').optional(),
  page: v.enum(PAGES).optional(),
  utm_source: v.string().regex(UTM_RE).optional(),
  utm_medium: v.string().regex(UTM_RE).optional(),
  utm_campaign: v.string().regex(UTM_RE).optional(),
  utm_content: v.string().regex(UTM_RE).optional(),
});

export const handle = guarded(async (req, deps) => {
  requireMethod(req, 'POST');
  const sb = supabaseDeps(deps);
  const user = await requireUser(req, sb);
  const body = Body.parse(await readJson(req, 2048));
  const db = createDb(sb);
  try {
    await db.rpc('hsf_link_account', { p_auth_user: user.id });
  } catch (e) {
    if (!(e instanceof HttpError) || e.status >= 500) throw e; // a person without a File company may still make a code
  }
  for (let attempt = 0; attempt < 2; attempt++) {
    const code = generateCode(deps.random);
    try {
      const r = await db.rpc('bi_claim_code_create', { p_auth_user: user.id, p_code_hash: await hashCode(code), p: body });
      const base = (deps.env.BI_CLAIM_LINK_BASE || '').replace(/\/+$/, '');
      return json({ code, expires_at: r.expires_at, claim_path: claimPath(code), claim_url: base ? base + claimPath(code) : null }, 201);
    } catch (e) {
      if (!(e instanceof HttpError) || e.status !== 409 || attempt === 1) throw e; // 409: the same hash already exists; draw again
    }
  }
  throw new HttpError(500, 'A claim code could not be made.');
});
