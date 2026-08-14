// CNC MSP FORGE | FRM-GATE-01 v1.0.0 | Assessment access check
const { rpc } = require('../lib/db');

module.exports = async (req, res) => {
  const token = (req.query && req.query.token) || '';
  if (!token) { res.status(200).json({ valid: false, reason: 'no token' }); return; }
  try {
    const result = await rpc('msp_check_access', { p_token: token });
    res.status(200).json(result);
  } catch (err) {
    console.error('access check failure', err.message);
    res.status(500).json({ valid: false, reason: 'check failed' });
  }
};
