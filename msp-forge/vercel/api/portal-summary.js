// CNC HSF FORGE | HSF-WEB-01 v1.0.0 | Portal summary for the signed in company contact
// One read for vercel/portal.html, which joins the commercial and medical spines
// (contract 9.8). It replaces the portal's use of /api/company-lookup, which also
// starts an assessment and so can mint an access token; this endpoint never does.
//
//   GET /api/portal-summary  -> hsf_portal_summary(p_auth_user)
//   <- { account: { client_account_id, company_name, account_kind, approved_at } | null,
//        plans:  [{ engagement_id, reference, status, industry_code, revision, created_at }],
//        quotes: [{ quote_reference, package_code, price_zar, price_status, valid_until, created_at }],
//        files:  [{ file_id, reference, industry_code, status, revision, compliance_pct,
//                   signoffs: [{ kind, decision, decided_at }] }] }
//
// The caller's Supabase Auth token is verified first (lib/auth.js requireUser,
// which also links the user to its company account, contract 9.1), and only the
// verified user id reaches the database. hsf_portal_summary is service role only
// and read only. The reply is rebuilt here from the contract fields alone, so a
// field the database might add later (a token, an email, an identifier of
// someone else) never reaches the browser by accident. MyClinicOnline records are
// not part of this reply: they arrive when MyClinicOnline is connected (HSF-3).

const { rpc } = require('../lib/db');
const { requireUser, sendError, methodNotAllowed } = require('../lib/auth');

const MAX_ROWS = 500;

const ACCOUNT_FIELDS = ['client_account_id', 'company_name', 'account_kind', 'approved_at'];
const PLAN_FIELDS = ['engagement_id', 'reference', 'status', 'industry_code', 'revision', 'created_at'];
const QUOTE_FIELDS = ['quote_reference', 'package_code', 'price_zar', 'price_status', 'valid_until', 'created_at'];
const FILE_FIELDS = ['file_id', 'reference', 'industry_code', 'status', 'revision', 'compliance_pct'];
const SIGNOFF_FIELDS = ['kind', 'decision', 'decided_at'];

function isObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

// Only scalar values of the named fields; a missing field is null.
function pick(row, fields) {
  const out = {};
  for (const f of fields) {
    const v = row[f];
    out[f] = v === undefined || v === null || typeof v === 'object' ? null : v;
  }
  return out;
}

function list(value, map) {
  if (!Array.isArray(value)) return [];
  return value.filter(isObject).slice(0, MAX_ROWS).map(map);
}

function shape(summary) {
  const s = isObject(summary) ? summary : {};
  return {
    account: isObject(s.account) ? pick(s.account, ACCOUNT_FIELDS) : null,
    plans: list(s.plans, r => pick(r, PLAN_FIELDS)),
    quotes: list(s.quotes, r => pick(r, QUOTE_FIELDS)),
    files: list(s.files, r => Object.assign(pick(r, FILE_FIELDS), {
      signoffs: list(r.signoffs, x => pick(x, SIGNOFF_FIELDS)),
    })),
  };
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET') {
    methodNotAllowed(res, ['GET']);
    return;
  }
  try {
    const user = await requireUser(req);
    const summary = await rpc('hsf_portal_summary', { p_auth_user: user.id });
    res.status(200).json(shape(summary));
  } catch (err) {
    sendError(res, err, 'portal summary');
  }
};

module.exports.shape = shape;
