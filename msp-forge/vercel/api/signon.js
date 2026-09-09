// CNC MSP FORGE | FRM-GATE-01 v1.1.0 | CNC client sign on
// An existing or prospective CNC client applies for access; a forge_admin
// approves in the review interface (or Supabase dashboard), which issues the
// single use assessment token via msp_grant_access.
//
// v1.1.0 (09/09/2026): writes through the msp_client_signon security definer
// function instead of a raw table insert. msp_client_account has RLS enabled
// with no INSERT policy, so the direct insert was refused for every applicant.

const { rpc } = require('../lib/db');

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
    res.status(200).json({ status: 'received', reference: r.reference });
  } catch (err) {
    console.error('signon failure', err.message);
    res.status(500).json({ error: 'sign on could not be recorded' });
  }
};
