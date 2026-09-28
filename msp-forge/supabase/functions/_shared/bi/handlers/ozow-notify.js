// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | ozow-notify (STUB, REJECTS) 26/09/2026
// POST from Ozow (web billing, prompt B2) -> 501, always, and nothing is recorded.
// Ozow signs its notifications with a hash over the posted fields and the
// merchant's private key. The exact field order and hash rules must come from
// Ozow's own specification for Care Net's account; they are not guessed here,
// so every notification is refused until they are supplied and tested.
// Env when connected: OZOW_SITE_CODE, OZOW_PRIVATE_KEY, OZOW_API_KEY (names only).

import { guarded, requireMethod, notImplemented } from '../http.js';

export const handle = guarded(async (req) => {
  requireMethod(req, 'POST');
  return notImplemented('Ozow payment notifications', ['OZOW_SITE_CODE', 'OZOW_PRIVATE_KEY', 'OZOW_API_KEY'],
    'Rejected: the Ozow hash check is not implemented until Care Net supplies Ozow\'s notification specification. Nothing was recorded or credited.');
});
