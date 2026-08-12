// CNC MSP FORGE | FRM-WHK-01 v1.0.0 | DocuSeal webhook receiver
// Vercel serverless function. Flow: shared secret check, validate and
// normalise (lib/validate.js), then persist through the single controlled
// write path msp_ingest_intake in Supabase. A validation failure routes to
// human triage, never to silent correction. A consent failure persists
// nothing at all.
//
// Environment (set in the Vercel project, never committed):
//   SUPABASE_URL                e.g. https://pboebfnujzffgwctsplw.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY   service role key, server side only
//   DOCUSEAL_WEBHOOK_SECRET     shared secret configured on the DocuSeal webhook

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

  const secret = req.headers['x-docuseal-signature'] || req.headers['x-webhook-secret'];
  if (!process.env.DOCUSEAL_WEBHOOK_SECRET || secret !== process.env.DOCUSEAL_WEBHOOK_SECRET) {
    res.status(401).json({ error: 'unauthorised' });
    return;
  }

  const payload = req.body;
  const eventType = payload && payload.event_type;
  if (eventType && eventType !== 'form.completed' && eventType !== 'submission.completed') {
    res.status(200).json({ status: 'ignored', event_type: eventType });
    return;
  }

  try {
    const selectable = await fetchSelectableSubindustries();
    const result = validateIntake(payload, selectable);

    if (!result.ok) {
      // Nothing is persisted. The submission remains in DocuSeal for human
      // follow up; log only the submission id and masked reasons.
      console.error('intake rejected', {
        rejections: result.rejections.map(r => r.replace(/\d{13}/g, '#############')),
      });
      res.status(200).json({ status: 'rejected', reasons_logged: true });
      return;
    }

    const outcome = await ingest(result.normalised);
    res.status(200).json({
      status: outcome.status,
      reference: outcome.reference,
      engagement_id: outcome.engagement_id,
    });
  } catch (err) {
    // A processing failure must surface for retry; DocuSeal retries non 2xx.
    console.error('webhook processing failure', err.message);
    res.status(500).json({ error: 'processing failure' });
  }
};
