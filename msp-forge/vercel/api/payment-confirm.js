// CNC MSP FORGE | FRM-GATE-01 v1.0.0 | Payment confirmation
// Until the payment gateway is wired (CR-13.13), payment confirmation is a
// manual forge_admin action protected by ADMIN_ACTION_SECRET. When the
// gateway lands, its webhook replaces the secret header with signature
// verification and calls the same grant path.

const { rpc } = require('../lib/db');

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.status(405).json({ error: 'method not allowed' }); return; }
  const secret = req.headers['x-admin-action-secret'];
  if (!process.env.ADMIN_ACTION_SECRET || secret !== process.env.ADMIN_ACTION_SECRET) {
    res.status(401).json({ error: 'unauthorised' });
    return;
  }
  const b = req.body || {};
  if (!b.company_name || !b.granted_via) {
    res.status(400).json({ error: 'company_name and granted_via are required' });
    return;
  }
  try {
    const grant = await rpc('msp_grant_access', {
      p_granted_via: b.granted_via,
      p_company_name: b.company_name,
      p_quote_id: b.quote_id || null,
      p_client_account_id: b.client_account_id || null,
    });
    res.status(200).json({ status: 'granted', assessment_url: `/assess.html?token=${grant.token}` });
  } catch (err) {
    console.error('grant failure', err.message);
    res.status(500).json({ error: 'grant failed' });
  }
};
