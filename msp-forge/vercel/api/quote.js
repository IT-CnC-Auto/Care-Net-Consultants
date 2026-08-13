// CNC MSP FORGE | FRM-GATE-01 v1.0.0 | Quote endpoint
// Prices an assessment from the industry rate card (msp_pricing). Placeholder
// rates always produce a quote marked indicative (CR-13.14). Unknown
// industries are never silently priced: they route to a consultant.

const { rpc } = require('../lib/db');

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.status(405).json({ error: 'method not allowed' }); return; }
  const b = req.body || {};
  if (b.website) { res.status(200).json({ status: 'rejected' }); return; }
  try {
    const quote = await rpc('msp_create_quote', { p: {
      company_name: b.company_name, contact_name: b.contact_name, contact_email: b.contact_email,
      industry_code: b.industry_code, company_size: b.company_size,
      employee_count: b.employee_count, job_category_count: b.job_category_count,
    } });
    res.status(200).json(quote);
  } catch (err) {
    if (String(err.message).includes('routes to a consultant')) {
      res.status(200).json({ status: 'consultant', message: 'No self service rate card covers this industry yet. A Care Net consultant will contact you with a tailored quotation.' });
      return;
    }
    console.error('quote failure', err.message);
    res.status(400).json({ error: 'quote could not be prepared' });
  }
};
