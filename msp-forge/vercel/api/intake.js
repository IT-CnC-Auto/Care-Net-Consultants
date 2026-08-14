// CNC MSP FORGE | FRM-WHK-01 v1.1.0 | Public HTML form intake endpoint
// Receives the flat JSON posted by the hosted onboarding form (index.html),
// runs the identical validator used by the DocuSeal webhook and the test
// harness, and persists through the same controlled write path
// msp_ingest_intake. Field names in the form are the variable names in
// Supabase and in the document placeholder map: one vocabulary end to end.

const { validateIntake } = require('../lib/validate');

async function fetchSelectableSubindustries() {
  const res = await fetch(
    `${process.env.SUPABASE_URL}/rest/v1/msp_subindustry?selectable=eq.true&select=code`,
    {
      headers: {
        apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
    }
  );
  if (!res.ok) throw new Error(`kernel taxonomy read failed: ${res.status}`);
  const rows = await res.json();
  return rows.map(r => r.code);
}

async function ingest(normalised) {
  const res = await fetch(`${process.env.SUPABASE_URL}/rest/v1/rpc/msp_ingest_intake`, {
    method: 'POST',
    headers: {
      apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ p: normalised }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`ingest failed: ${res.status} ${detail}`);
  }
  return res.json();
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'method not allowed' });
    return;
  }

  const payload = req.body;
  // Honeypot: the hidden website field is never filled by a person.
  if (payload && payload.website) {
    res.status(200).json({ status: 'rejected' });
    return;
  }

  // Access gate: the assessment is reached through an approved client grant
  // or a paid quote; every submission carries its single use token.
  let accessId = null;
  try {
    const gate = await fetch(`${process.env.SUPABASE_URL}/rest/v1/rpc/msp_check_access`, {
      method: 'POST',
      headers: {
        apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_token: (payload && payload.access_token) || '' }),
    }).then(r => r.json());
    if (!gate.valid) {
      res.status(200).json({ status: 'rejected', reason: `Access not valid: ${gate.reason}. Please start from the Care Net landing page.` });
      return;
    }
    accessId = gate.access_id;
  } catch (err) {
    console.error('access gate failure', err.message);
    res.status(500).json({ error: 'processing failure' });
    return;
  }

  try {
    const selectable = await fetchSelectableSubindustries();
    const result = validateIntake(payload, selectable);

    if (!result.ok) {
      const consentMissing = result.rejections.some(r => r.includes('consent'));
      const idPattern = result.rejections.some(r => r.includes('identity number'));
      res.status(200).json({
        status: 'rejected',
        reason: idPattern
          ? 'A field appears to contain an identity number. This form must never carry personal information about an identifiable individual. Please remove it and resubmit.'
          : consentMissing
            ? 'The POPIA processing consent is required before your information can be processed.'
            : 'The submission could not be accepted.',
      });
      return;
    }

    const outcome = await ingest(result.normalised);
    // Consume the single use token against this intake.
    await fetch(`${process.env.SUPABASE_URL}/rest/v1/msp_form_access?id=eq.${accessId}`, {
      method: 'PATCH',
      headers: {
        apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ used_by_intake: outcome.intake_id }),
    });
    res.status(200).json({
      status: outcome.status,
      reference: outcome.reference,
    });
  } catch (err) {
    console.error('intake processing failure', err.message);
    res.status(500).json({ error: 'processing failure' });
  }
};
