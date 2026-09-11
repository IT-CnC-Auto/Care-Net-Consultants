// CNC MSP FORGE | FRM-GATE-01 v1.2.0 | CNC client sign on (self-service)
// A client registers their company and is handed their single use assessment
// link in the same response. There is no consultant approval step: the Plan is
// free for every client who books medicals (MD ruling 31/08/2026), so the gate
// that used to sit here only ever stalled registrations.
//
// v1.1.0 (09/09/2026): writes through the msp_client_signon security definer
// function instead of a raw table insert (RLS refused the direct insert).
// v1.2.0 (11/09/2026): msp_client_signon now approves on the spot and returns
// the assessment token; this endpoint turns it into the link the page shows.

const { rpc } = require('../lib/db');

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
  try {
    const r = await rpc('msp_client_signon', {
      p: {
        company_name: b.company_name, contact_name: b.contact_name,
        contact_email: b.contact_email, notes: b.notes || null,
      },
    });
    res.status(200).json({
      status: 'received',
      reference: r.reference,
      existing: !!r.existing,
      company_name: r.company_name,
      account_kind: r.account_kind,
      declined: !!r.declined,
      assessment_url: r.declined ? null : assessmentUrl(req, r.token),
    });
  } catch (err) {
    console.error('signon failure', err.message);
    res.status(500).json({ error: 'sign on could not be recorded' });
  }
};
