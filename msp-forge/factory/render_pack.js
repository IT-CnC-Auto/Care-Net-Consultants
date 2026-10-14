// CNC MSP FORGE | DOC-GEN-01 v1.3.0 | Document Factory renderer (command line)
// v1.3.0 (14/10/2026): the document is built by render_core.js, shared with the msp-plan-render
// edge function; this file only reads the inputs from disk and writes the DOCX.
// v1.2.0 (13/10/2026): every page of an unsigned Plan is marked PLANNING ONLY (MD ruling
// 12/10/2026): a diagonal marking behind the content and a band in the header. The
// marking comes off only when MSP_SIGNOFF names the practitioner sign off record from
// msp_plan_signoff(reference) (migration 069) for this Plan, and that record shows an
// approved decision with the practitioner's name, HPCSA number, signature and signing
// time. No other setting removes it.
// v1.1.0 (14/09/2026): executive summary derived from the draft (was sample template text);
// MSP_CLIENT_LOGO / MSP_CLIENT_LOGO_SIZE override the client logo asset.
// Renders the validated structured draft (agent/draft.json) into the dual
// branded Medical Surveillance Pack DOCX per the cnc-msp-dualbrand skill
// v1.0.0. Locked template blocks insert verbatim from templates.json and are
// never paraphrased. Geometry is verified after render by verify_geometry.py.
//
// Usage: node render_pack.js <draft.json> <output.docx>
//        MSP_SIGNOFF=<signoff.json> node render_pack.js ...   (signed Plan, unmarked)

const fs = require('fs');
const path = require('path');
const docx = require('docx');
const { buildPlan } = require('./render_core.js');

const ASSETS = path.join(__dirname, 'assets');
const read = (f) => fs.readFileSync(path.join(ASSETS, f));
const draft = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const OUT = process.argv[3];
const signoff = process.env.MSP_SIGNOFF ? JSON.parse(fs.readFileSync(process.env.MSP_SIGNOFF, 'utf8')) : null;

const { doc, marked, markReason } = buildPlan(docx, draft, {
  templates: JSON.parse(fs.readFileSync(path.join(__dirname, 'templates.json'), 'utf8')),
  config: JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8')),
  signoff,
  images: {
    banner: read('cnc_header_banner.png'),
    footer: read('cnc_footer_banner.png'),
    marking: read('marking_planning_only.png'),
    clientLogo: fs.readFileSync(process.env.MSP_CLIENT_LOGO || path.join(ASSETS, 'client_logo_prepared.png')),
  },
  clientLogoSize: process.env.MSP_CLIENT_LOGO_SIZE
    ? process.env.MSP_CLIENT_LOGO_SIZE.split(',').map(Number)
    : JSON.parse(fs.readFileSync(path.join(ASSETS, 'client_logo_prepared.report.json'), 'utf8')).prepared_size,
});

docx.Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync(OUT, buf);
  console.log(`${OUT} written (${buf.length} bytes)`);
  console.log(marked ? `marking: PLANNING ONLY on every page (${markReason}${signoff ? '' : ', MSP_SIGNOFF not set'})` : `marking: none, signed by ${signoff.signature_name} on ${signoff.signed_at}`);
});
