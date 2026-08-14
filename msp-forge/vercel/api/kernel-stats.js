// CNC MSP FORGE | PILOT-01 v1.0.0 | Public kernel statistics
// Aggregate counts and the current kernel version only: no instrument text, no
// client data. Used by the pilot journey page to show the engine is live.

const { rpc } = require('../lib/db');

module.exports = async (req, res) => {
  if (req.method !== 'GET') { res.status(405).json({ error: 'method not allowed' }); return; }
  try {
    const counts = await rpc('msp_kernel_counts', {});
    const version = await fetch(
      `${process.env.SUPABASE_URL}/rest/v1/msp_kernel_version?select=semver,released_on,omp_ratified&order=released_on.desc,semver.desc&limit=1`,
      { headers: { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}` } }
    ).then(r => r.json());
    res.setHeader('Cache-Control', 's-maxage=3600');
    res.status(200).json({ version: version[0] || null, counts });
  } catch (err) {
    console.error('kernel stats failure', err.message);
    res.status(400).json({ error: 'stats unavailable' });
  }
};
