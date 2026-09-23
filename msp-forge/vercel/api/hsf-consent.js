// CNC HSF FORGE | HSF-WEB-01 v1.0.0 | POPIA consent for File document storage
// The Health and Safety File builder asks for three separate consents before a
// single document can be stored: document_storage (held in Care Net's private
// Supabase Storage staging area), mco_transfer (moved to MyClinicOnline, then
// removed from staging, once the MyClinicOnline interface is connected; until
// then documents are held in staging) and authority_to_share (the company may
// share the documents it uploads). Nothing uploads until all three are given.
//
//   GET    /api/hsf-consent                           -> hsf_consent_status
//   POST   /api/hsf-consent  { kinds: [...], wording_version }
//                                                    -> hsf_record_consent
//   DELETE /api/hsf-consent?kind=<kind>               -> hsf_withdraw_consent
//
// Every call verifies the caller's Supabase Auth token first (lib/auth.js, which
// also links the user to its company account, contract 9.1) and passes only the
// verified user id to the database; the functions are service role only and find
// the company account from that id. Withdrawal stops new uploads; withdrawing
// mco_transfer or document_storage also blocks the transfer of documents not yet
// transferred, and nothing is deleted automatically (contract 9.5). The current
// wording version is enforced by the database.

const { rpc } = require('../lib/db');
const { requireUser, sendError, readBody, queryValue, httpError, methodNotAllowed, CONTROL_RE } = require('../lib/auth');

const KINDS = ['document_storage', 'mco_transfer', 'authority_to_share'];
const WORDING_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/;

function parseKinds(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > KINDS.length) {
    throw httpError(400, 'Choose at least one consent: document_storage, mco_transfer or authority_to_share.', 'bad_request');
  }
  const out = [];
  for (const k of value) {
    if (typeof k !== 'string' || !KINDS.includes(k)) {
      throw httpError(400, 'Unknown consent kind. Allowed: document_storage, mco_transfer, authority_to_share.', 'bad_request');
    }
    if (out.includes(k)) throw httpError(400, 'Each consent kind may be sent once only.', 'bad_request');
    out.push(k);
  }
  return out;
}

function parseWording(value) {
  if (typeof value !== 'string' || !WORDING_RE.test(value) || CONTROL_RE.test(value)) {
    throw httpError(400, 'The consent wording version is missing or not recognised.', 'bad_request');
  }
  return value;
}

function parseKind(value) {
  if (typeof value !== 'string' || !KINDS.includes(value)) {
    throw httpError(400, 'Name the consent to withdraw: document_storage, mco_transfer or authority_to_share.', 'bad_request');
  }
  return value;
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (!['GET', 'POST', 'DELETE'].includes(req.method)) {
    methodNotAllowed(res, ['GET', 'POST', 'DELETE']);
    return;
  }
  try {
    const user = await requireUser(req);

    if (req.method === 'GET') {
      const status = await rpc('hsf_consent_status', { p_auth_user: user.id });
      res.status(200).json(status);
      return;
    }

    if (req.method === 'POST') {
      const b = readBody(req);
      const kinds = parseKinds(b.kinds);
      const wording = parseWording(b.wording_version);
      const status = await rpc('hsf_record_consent', {
        p_auth_user: user.id,
        p_kinds: kinds,
        p_wording_version: wording,
      });
      res.status(200).json(status);
      return;
    }

    // DELETE: the kind comes from the query string; a JSON body is accepted too.
    let kind = queryValue(req, 'kind');
    if (kind === null) {
      const b = readBody(req);
      kind = b.kind;
    }
    const status = await rpc('hsf_withdraw_consent', { p_auth_user: user.id, p_kind: parseKind(kind) });
    res.status(200).json(status);
  } catch (err) {
    sendError(res, err, 'hsf consent');
  }
};
