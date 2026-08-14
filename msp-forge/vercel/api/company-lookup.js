// CNC MSP FORGE | SHOP-01 v1.0.0 | Company lookup for the signed in journey
// Verifies the caller's Supabase Auth token, then looks up the client account by
// the authenticated email only. An account status is never revealed to anyone
// except its own signed in contact.

const { rpc } = require('../lib/db');

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
    res.status(200).json({ email: user.email, ...status });
  } catch (err) {
    console.error('company lookup failure', err.message);
    res.status(400).json({ error: 'lookup failed' });
  }
};
