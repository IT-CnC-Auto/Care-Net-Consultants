# CNC MSP FORGE: WEBHOOK RECEIVER (FRM-WHK-01 v1.0.0)

## 1. What this is

1.1 The Vercel serverless endpoint that receives DocuSeal form.completed webhooks for the CNC MSP Onboarding Form (template 5396590), validates and normalises the submission through lib/validate.js, and persists it through the single controlled write path msp_ingest_intake in Supabase. A validation failure routes to human triage, never to silent correction. A missing processing consent persists nothing at all.

## 2. Deployment

2.1 Project: cnc-msp-forge on Vercel team AutoHive Wesite Developers (CR-13.2). Endpoint path: /api/docuseal-webhook.

2.2 Environment variables, set in the Vercel project settings and never committed:
2.2.1 SUPABASE_URL: https://pboebfnujzffgwctsplw.supabase.co
2.2.2 SUPABASE_SERVICE_ROLE_KEY: the service role key, server side only.
2.2.3 DOCUSEAL_WEBHOOK_SECRET: the shared secret also configured on the DocuSeal webhook.

2.3 The endpoint answers 401 to every request until the secret is configured, which is the safe default. DocuSeal retries non 2xx responses, so a processing failure is retried and never lost silently.

## 3. Go live checklist

3.1 Upload msp-forge/form/onboarding_form.docx to DocuSeal template 5396590 (the 310 field tags parse automatically on upload).
3.2 Set the three environment variables in Vercel and redeploy to production.
3.3 In DocuSeal, add a webhook pointing to the production /api/docuseal-webhook URL with the shared secret, subscribed to form.completed.
3.4 Submit a test form and confirm the engagement row, reference number, and audit event in Supabase.
3.5 Record the outcome against CR-12.10 in the confirmation register.

## 4. Test discipline

4.1 msp-forge/test/run_synthetic.js runs the production validator over the canonical Horizon synthetic profile plus three negative cases (identity number guard, missing consent, OTHER industry triage). The happy path payload persisted through msp_ingest_intake on 12/08/2026 produced engagement CNC-MSP-2026-0812-001 with all child rows, three consent records, and the intake_received audit event. Database level guards for the identity pattern, the consent gate, and audit immutability were exercised directly and hold.
