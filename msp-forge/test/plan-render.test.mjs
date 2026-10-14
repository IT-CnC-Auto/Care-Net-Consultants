// CNC MSP FORGE | DOC-GEN-02 v1.0.0 | msp-plan-render test 14/10/2026
// Loads the CORE region of supabase/functions/msp-plan-render/index.ts on its own and checks:
//   1. the inlined render_core.js, templates.json and config.json match their sources;
//   2. the server path (RENDER.buildPlan with the function's own inputs) produces the same
//      DOCX, part for part, as the command line factory/render_pack.js;
//   3. the PLANNING ONLY marking follows the sign off record;
//   4. the small helpers (file names, PDF switch, SharePoint paths, asset names).
// Needs docx 9.10.0 and its jszip on NODE_PATH, as render_pack.js does:
//   NODE_PATH=<dir>/node_modules node test/plan-render.test.mjs
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(root, 'factory', 'render_pack.js'));
let docx, JSZip;
try { docx = require('docx'); JSZip = require('jszip'); } catch {
  console.error('FAIL  docx/jszip not found: install docx@9.10.0 and set NODE_PATH to its node_modules');
  process.exit(1);
}
let failed = 0;
const ok = (cond, label) => { console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}`); if (!cond) failed++; };

const index = readFileSync(join(root, 'supabase/functions/msp-plan-render/index.ts'), 'utf8').replace(/\r\n/g, '\n');
const core = index.slice(index.indexOf('// ============================== CORE START'), index.indexOf('// =============================== CORE END'));
const dir = mkdtempSync(join(tmpdir(), 'msp-render-'));
const modPath = join(dir, 'core.cjs');
writeFileSync(modPath, core + '\nmodule.exports = { RENDER, TEMPLATES, CONFIG, RENDER_VERSION, ASSET_FILES, PLACEHOLDER_LOGO_SIZE, planFileName, pdfSiteConfigured, spPath, DOCX_TYPE };\n');
const F = require(modPath);

// 1. copies
const coreSrc = readFileSync(join(root, 'factory/render_core.js'), 'utf8').replace(/\r\n/g, '\n').trimEnd();
ok(index.includes(coreSrc), 'render_core.js is inlined unchanged (run build.mjs after editing it)');
ok(JSON.stringify(F.TEMPLATES) === JSON.stringify(JSON.parse(readFileSync(join(root, 'factory/templates.json'), 'utf8'))), 'templates.json inlined unchanged');
ok(JSON.stringify(F.CONFIG) === JSON.stringify(JSON.parse(readFileSync(join(root, 'factory/config.json'), 'utf8'))), 'config.json inlined unchanged');
ok(Object.values(F.ASSET_FILES).every((f) => existsSync(join(root, 'factory/assets', f))), 'every asset the function loads exists in factory/assets');

// 2 and 3. same document as the command line
const asset = (f) => readFileSync(join(root, 'factory/assets', f));
const draft = JSON.parse(readFileSync(join(root, 'agent/draft.json'), 'utf8'));
const ref = draft.composed.placeholders.reference;
const signed = { reference: ref, decision: 'approved', omp_name: 'TEST Practitioner', omp_hpcsa_number: 'MP 0000000',
  signature_name: 'TEST Practitioner', signed_at: '2026-10-13T10:05:00Z', signed: true };
async function parts(buf) {
  const z = await JSZip.loadAsync(buf);
  const out = {};
  for (const n of Object.keys(z.files).filter((n) => !n.startsWith('docProps/') && !n.endsWith('/'))) {
    // The docx library numbers drawings (docPr / cNvPr ids) and table of contents bookmarks
    // (_TocN) with counters that run on across documents built in one process, so a second
    // render in a warm function has higher numbers. They stay unique within each document,
    // which is all Word needs; compare without them.
    const raw = await z.file(n).async('nodebuffer');
    const body = n.endsWith('.xml') ? Buffer.from(raw.toString('utf8').replace(/(<(?:wp:docPr|pic:cNvPr) id=")\d+"/g, '$1N"').replace(/_Toc\d+/g, '_TocN').replace(/(<w:bookmark(?:Start|End)[^>]*w:id=")\d+"/g, '$1N"')) : raw;
    out[n] = createHash('sha256').update(body).digest('hex');
  }
  return out;
}
for (const [label, signoff] of [['marked', null], ['signed', signed]]) {
  const built = F.RENDER.buildPlan(docx, draft, { templates: F.TEMPLATES, config: F.CONFIG, signoff, clientLogoSize: F.PLACEHOLDER_LOGO_SIZE,
    images: { banner: asset(F.ASSET_FILES.banner), footer: asset(F.ASSET_FILES.footer), marking: asset(F.ASSET_FILES.marking),
      clientLogo: asset(F.ASSET_FILES.placeholderLogo) } });
  const server = await parts(await docx.Packer.toBuffer(built.doc));
  const cliOut = join(dir, `cli-${label}.docx`);
  const env = { ...process.env, MSP_CLIENT_LOGO: join(root, 'factory/assets', F.ASSET_FILES.placeholderLogo),
    MSP_CLIENT_LOGO_SIZE: F.PLACEHOLDER_LOGO_SIZE.join(',') };
  delete env.MSP_SIGNOFF;
  if (signoff) { const sf = join(dir, 'signoff.json'); writeFileSync(sf, JSON.stringify(signoff)); env.MSP_SIGNOFF = sf; }
  execFileSync(process.execPath, [join(root, 'factory/render_pack.js'), join(root, 'agent/draft.json'), cliOut], { env });
  const cli = await parts(readFileSync(cliOut));
  const names = [...new Set([...Object.keys(server), ...Object.keys(cli)])];
  const differ = names.filter((n) => !(server[n] && server[n] === cli[n]));
  ok(differ.length === 0, `${label}: server render identical to the command line (${names.length} parts${differ.length ? "; differ: " + differ.join(", ") : ""})`);
  ok(built.marked === (signoff === null), `${label}: marking ${signoff ? 'lifted by a valid sign off' : 'kept without a sign off'}`);
}

// 4. helpers
ok(F.planFileName('CNC-MSP-2026-1012-001', 2, true, 'docx') === 'CNC-MSP-2026-1012-001_Medical_Surveillance_Plan_v2_PLANNING_ONLY.docx'
  && F.planFileName('X', 1, false, 'pdf') === 'X_Medical_Surveillance_Plan_v1_SIGNED.pdf', 'file names carry the version and the marking');
ok(!F.pdfSiteConfigured('pending') && !F.pdfSiteConfigured(' ') && !F.pdfSiteConfigured(null) && F.pdfSiteConfigured('contoso.sharepoint.com:/sites/msp'), 'PDF stays off until a site is set');
ok(F.spPath('MSP Plan rendering', 'A B.docx') === 'MSP%20Plan%20rendering/A%20B.docx' && F.spPath('a/b', 'c.docx') === 'a/b/c.docx', 'SharePoint paths are encoded per segment');
ok(F.RENDER_VERSION === '1.0.0' && /DOC-GEN-02 v1\.0\.0/.test(index), 'version line and constant agree');

console.log(failed ? `\n${failed} FAILED` : '\nALL PASSED');
process.exit(failed ? 1 : 0);
