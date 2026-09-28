// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | kyc-webhook (STUB) 26/09/2026
// POST from the identity and liveness vendor (prompt B4) -> 501.
// {{kyc_vendor}} is not chosen. Once it is, a verified result moves the
// inspector's profile past Identity (bi_inspector_profile: liveness_passed_at,
// kyc_vendor_ref, id_document_kind and the last four characters only; the
// document stays with the vendor), after checking the vendor's signature.
// Env when connected: KYC_VENDOR, KYC_WEBHOOK_SECRET (names only).

import { guarded, requireMethod, notImplemented } from '../http.js';

export const handle = guarded(async (req) => {
  requireMethod(req, 'POST');
  return notImplemented('Identity and liveness checks', ['KYC_VENDOR', 'KYC_WEBHOOK_SECRET'],
    'The identity and liveness vendor is not chosen yet. Nothing was recorded.');
});
