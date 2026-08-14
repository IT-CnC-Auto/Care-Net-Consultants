// CNC MSP FORGE | FRM-GATE-01 v1.0.0 | CNC client sign on
// An existing or prospective CNC client applies for access; a forge_admin
// approves in the review interface (or Supabase dashboard), which issues the
// single use assessment token via msp_grant_access.

const { insert } = require('../lib/db');

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.status(405).json({ error: 'method not allowed' }); return; }
  const b = req.body || {};
  if (b.website) { res.status(200).json({ status: 'rejected' }); return; }
  if (!b.company_name || !b.contact_name || !b.contact_email) {
    res.status(400).json({ error: 'company name, contact name, and email are required' });
    return;
  }
  try {
    const row = await insert('msp_client_account', {
      company_name: b.company_name, contact_name: b.contact_name,
      contact_email: b.contact_email, notes: b.notes || null,
    });
    res.status(200).json({ status: 'received', reference: row.id });
  } catch (err) {
    console.error('signon failure', err.message);
    res.status(500).json({ error: 'sign on could not be recorded' });
  }
};
