// CNC MSP FORGE | FRM-DRAFT-01 v1.0.0 | Server-side assessment drafts (16/09/2026)
// A part-finished assessment, keyed by its single use access token, so the same
// emailed link resumes on any machine. The browser copy in cnc-journey.js stays
// as the fallback for when someone is offline.
//
//   GET    /api/draft?token=...            -> { found, valid, reason?, payload?, step?, filled?, company?, saved_at? }
//   POST   /api/draft   { token, payload, step?, filled?, company? }
//                                          -> { saved, saved_at? , reason? }
//   DELETE /api/draft   { token }          -> { cleared }
//
// The payload is whatever the front end already keeps in localStorage under
// cnc_msp_draft_<token>: { values: {...}, counts: {...} } is the expected shape,
// but the server does not read inside it. Hard cap 256 KB (the table enforces it
// too). Every call is refused, with the same reasons as /api/access-check, when
// the token is unknown, already used or expired. A submission consumes the token
// and a trigger deletes the draft, so nothing lingers once the intake exists.
//
// No clinical data: the form forbids employee identifiers and results, and the
// draft is the form's own fields. Service role only, like every other endpoint.

const { rpc } = require('../lib/db');

const MAX_BYTES = 262144;

function readBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string' && req.body) { try { return JSON.parse(req.body); } catch (e) { return null; } }
  return {};
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  try {
    if (req.method === 'GET') {
      const token = (req.query && req.query.token) || '';
      if (!token) { res.status(400).json({ found: false, valid: false, reason: 'no token' }); return; }
      const r = await rpc('msp_draft_get', { p_token: token });
      res.status(200).json(r);
      return;
    }

    if (req.method === 'POST') {
      const b = readBody(req);
      if (!b) { res.status(400).json({ saved: false, reason: 'bad json' }); return; }
      const token = b.token || '';
      if (!token) { res.status(400).json({ saved: false, reason: 'no token' }); return; }
      if (!b.payload || typeof b.payload !== 'object') { res.status(400).json({ saved: false, reason: 'no payload' }); return; }
      const size = Buffer.byteLength(JSON.stringify(b.payload), 'utf8');
      if (size > MAX_BYTES) { res.status(413).json({ saved: false, reason: 'draft too large' }); return; }
      const r = await rpc('msp_draft_save', {
        p_token: token,
        p_payload: b.payload,
        p_step: Number.isInteger(b.step) ? b.step : parseInt(b.step, 10) || 1,
        p_filled: Number.isInteger(b.filled) ? b.filled : parseInt(b.filled, 10) || 0,
        p_company: typeof b.company === 'string' ? b.company.slice(0, 200) : null,
      });
      res.status(200).json(r);
      return;
    }

    if (req.method === 'DELETE') {
      const b = readBody(req) || {};
      const token = b.token || (req.query && req.query.token) || '';
      if (!token) { res.status(400).json({ cleared: false, reason: 'no token' }); return; }
      const r = await rpc('msp_draft_clear', { p_token: token });
      res.status(200).json(r);
      return;
    }

    res.setHeader('Allow', 'GET, POST, DELETE');
    res.status(405).json({ error: 'method not allowed' });
  } catch (err) {
    console.error('draft failure', err.message);
    res.status(500).json({ error: 'draft could not be processed' });
  }
};
