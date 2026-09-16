// CNC MSP FORGE | FRM-GATE-01 v1.3.0 | CNC client sign on (self-service)
// A client registers their company and is handed their single use assessment
// link in the same response. There is no consultant approval step: the Plan is
// free for every client who books medicals (MD ruling 31/08/2026), so the gate
// that used to sit here only ever stalled registrations.
//
// v1.1.0 (09/09/2026): writes through the msp_client_signon security definer
// function instead of a raw table insert (RLS refused the direct insert).
// v1.2.0 (11/09/2026): msp_client_signon now approves on the spot and returns
// the assessment token; this endpoint turns it into the link the page shows.
// v1.3.0 (16/09/2026): accepts contact_number (optional) and passes it to
// msp_client_signon, which stores it on msp_client_account.contact_number
// (migration 043). The front end can stop carrying the number inside notes.
// Loose shape check only: digits, spaces, +, -, ( ) and dots, 7 to 40 characters.

const { rpc } = require('../lib/db');

const NUMBER_SHAPE = /^[0-9+()\-. ]{7,40}$/;

function cleanNumber(v) {
  if (v == null) return null;
  const s = String(v).trim();
  if (!s) return null;
  return NUMBER_SHAPE.test(s) ? s : undefined; // undefined = present but malformed
}

function assessmentUrl(req, token) {
  if (!token) return null;
  const proto = (req.headers['x-forwarded-proto'] || 'https').split(',')[0].trim();
  const host = (req.headers['x-forwarded-host'] || req.headers.host || '').split(',')[0].trim();
  return `${proto}://${host}/assess.html?token=${encodeURIComponent(token)}`;
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.status(405).json({ error: 'method not allowed' }); return; }
  const b = req.body || {};
  if (b.website) { res.status(200).json({ status: 'rejected' }); return; }
  if (!b.company_name || !b.contact_name || !b.contact_email) {
    res.status(400).json({ error: 'company name, contact name, and email are required' });
    return;
  }
  const contactNumber = cleanNumber(b.contact_number);
  if (contactNumber === undefined) {
    res.status(400).json({ error: 'the contact number should be digits, with an optional + and spaces' });
    return;
  }
  try {
    const r = await rpc('msp_client_signon', {
      p: {
        company_name: b.company_name, contact_name: b.contact_name,
        contact_email: b.contact_email, contact_number: contactNumber,
        notes: b.notes || null,
      },
    });
    res.status(200).json({
      status: 'received',
      reference: r.reference,
      existing: !!r.existing,
      company_name: r.company_name,
      contact_number: r.contact_number || null,
      account_kind: r.account_kind,
      declined: !!r.declined,
      assessment_url: r.declined ? null : assessmentUrl(req, r.token),
    });
  } catch (err) {
    console.error('signon failure', err.message);
    res.status(500).json({ error: 'sign on could not be recorded' });
  }
};
