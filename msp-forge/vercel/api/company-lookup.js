// CNC MSP FORGE | SHOP-01 v1.1.0 | Company lookup for the signed in journey
// Verifies the caller's Supabase Auth token, then looks up the client account by
// the authenticated email only. An account status is never revealed to anyone
// except its own signed in contact.
//
// v1.1.0 (11/09/2026): a returning client with a registered company is handed a
// live assessment link straight away (self-service access, MD ruling 31/08/2026).
// msp_client_start_assessment approves on demand and reuses an unused, unexpired
// token, so reloading the account page never mints a second one.

const { rpc } = require('../lib/db');

function assessmentUrl(req, token) {
  if (!token) return null;
  const proto = (req.headers['x-forwarded-proto'] || 'https').split(',')[0].trim();
  const host = (req.headers['x-forwarded-host'] || req.headers.host || '').split(',')[0].trim();
  return `${proto}://${host}/assess.html?token=${encodeURIComponent(token)}`;
}

module.exports = async (req, res) => {
  if (req.method !== 'GET') { res.status(405).json({ error: 'method not allowed' }); return; }
  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) { res.status(401).json({ error: 'sign in required' }); return; }
  try {
    const userRes = await fetch(`${process.env.SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, Authorization: auth },
    });
    if (!userRes.ok) { res.status(401).json({ error: 'sign in required' }); return; }
    const user = await userRes.json();
    if (!user.email) { res.status(401).json({ error: 'sign in required' }); return; }

    const status = await rpc('msp_company_lookup', { p_email: user.email });
    if (!status.found) { res.status(200).json({ email: user.email, ...status }); return; }

    const start = await rpc('msp_client_start_assessment', { p_email: user.email });
    res.status(200).json({
      email: user.email,
      ...status,
      account_kind: start.account_kind || status.account_kind,
      declined: !!start.declined,
      assessment_url: start.declined ? null : assessmentUrl(req, start.token),
    });
  } catch (err) {
    console.error('company lookup failure', err.message);
    res.status(400).json({ error: 'lookup failed' });
  }
};
