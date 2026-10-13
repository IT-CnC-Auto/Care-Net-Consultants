// CNC MSP FORGE | DOC-GEN-01 v1.2.0 | PLANNING ONLY marking test 13/10/2026
// Renders agent/draft.json with factory/render_pack.js under each sign off case and
// reads the DOCX parts back: the marking (header band plus the full page image
// behind the text) must be present unless the record is a complete, approved,
// signed sign off for this very Plan.
//
// Needs the docx package (9.10.0) and its jszip on NODE_PATH, as render_pack.js does:
//   npm i docx@9.10.0 (anywhere), then NODE_PATH=<that>/node_modules node test/render-marking.test.mjs
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(root, 'factory', 'render_pack.js'));
let JSZip;
try { JSZip = require('jszip'); } catch {
  console.error('FAIL  jszip not found: install docx@9.10.0 and set NODE_PATH to its node_modules');
  process.exit(1);
}
const tmp = mkdtempSync(join(tmpdir(), 'msp-mark-'));
const draft = JSON.parse(readFileSync(join(root, 'agent/draft.json'), 'utf8'));
const ref = draft.composed.placeholders.reference;
const BAND = 'PLANNING ONLY. NOT REVIEWED OR SIGNED BY AN OMP.';

let failed = 0;
const ok = (cond, label) => { console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}`); if (!cond) failed++; };

const signed = { reference: ref, review_id: 'TEST', decision: 'approved', omp_name: 'TEST Practitioner',
  omp_hpcsa_number: 'MP 0000000', decided_at: '2026-10-13T10:00:00Z', signature_name: 'TEST Practitioner',
  signed_at: '2026-10-13T10:05:00Z', signed: true };

async function render(name, signoff) {
  const out = join(tmp, name + '.docx');
  const env = { ...process.env };
  delete env.MSP_SIGNOFF;
  if (signoff) { const f = join(tmp, name + '.json'); writeFileSync(f, JSON.stringify(signoff)); env.MSP_SIGNOFF = f; }
  const log = execFileSync(process.execPath, [join(root, 'factory/render_pack.js'), join(root, 'agent/draft.json'), out], { env, encoding: 'utf8' });
  const zip = await JSZip.loadAsync(readFileSync(out));
  const parts = Object.keys(zip.files);
  const headers = await Promise.all(parts.filter((p) => /^word\/header\d*\.xml$/.test(p)).map((p) => zip.file(p).async('string')));
  const documentXml = await zip.file('word/document.xml').async('string');
  const headerXml = headers.join('\n');
  return {
    log,
    band: headerXml.includes(BAND),
    behind: /<wp:anchor[^>]*behindDoc="1"/.test(headerXml) && headerXml.includes('planning-only-marking'),
    documentXml,
  };
}

const cases = [
  ['no sign off record', null, true],
  ['approved and signed, this Plan', signed, false],
  ['approved, not signed', { ...signed, signature_name: null, signed_at: null, signed: false }, true],
  ['signed but decision amended', { ...signed, decision: 'amended' }, true],
  ['signed record for another Plan', { ...signed, reference: 'CNC-MSP-2026-0000-999' }, true],
  ['record says signed but has no HPCSA number', { ...signed, omp_hpcsa_number: ' ' }, true],
];
for (const [label, signoff, expectMarked] of cases) {
  const r = await render(label.replace(/\W+/g, '_'), signoff);
  ok(r.band === expectMarked && r.behind === expectMarked, `${label}: ${expectMarked ? 'marked on every page' : 'no marking'}`);
  if (!expectMarked) ok(r.documentXml.includes('TEST Practitioner, HPCSA MP 0000000, approved and signed 2026-10-13'), `${label}: document control names the signing practitioner`);
}
console.log(failed ? `\n${failed} FAILED` : '\nALL PASSED');
process.exit(failed ? 1 : 0);
