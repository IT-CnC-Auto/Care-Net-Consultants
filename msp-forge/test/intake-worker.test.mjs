// CNC MSP FORGE | msp-intake-worker core test (Node, no network, no database)
// Loads the CORE region of supabase/functions/msp-intake-worker/index.ts on its
// own and checks: the inlined pipeline is byte-identical to agent/pipeline.js;
// a real construction intake drafts cleanly and queues; an unknown area of work
// and a classification miss halt in triage; the regime route check accepts an
// MHSA industry (the mining defect fixed 08/10/2026); preflight builds a usable
// intake; mails carry no em dash, no emoji and escape client text.
// Run: node msp-forge/test/intake-worker.test.mjs

import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const index = readFileSync(join(root, 'supabase/functions/msp-intake-worker/index.ts'), 'utf8').replace(/\r\n/g, '\n');
const core = index.slice(index.indexOf('// ============================== CORE START'), index.indexOf('// =============================== CORE END'));
const dir = mkdtempSync(join(tmpdir(), 'msp-worker-'));
const modPath = join(dir, 'core.mjs');
writeFileSync(modPath, core + '\nexport { PIPELINE, runPipeline, preflightIntake, renderIntakeMail, renderResultMail, renderOmpMail, renderOverdueMail, emails, siteBase, MODEL_USED };\n');
const W = await import(pathToFileURL(modPath).href);

let failed = 0;
const ok = (cond, name) => { console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}`); if (!cond) failed++; };

// 1. inlined pipeline is the repo pipeline, unchanged
const pipelineSrc = readFileSync(join(root, 'agent/pipeline.js'), 'utf8').replace(/\r\n/g, '\n').trimEnd();
ok(index.includes(pipelineSrc), 'inlined pipeline matches agent/pipeline.js byte for byte');

// 2. a real intake (the 14/09 construction end to end run) drafts and queues
const kernel = JSON.parse(readFileSync(join(root, 'agent/kernel_snapshot_constr.json'), 'utf8'));
const intakePath = process.env.MSP_TEST_INTAKE;
const intake = intakePath ? JSON.parse(readFileSync(intakePath, 'utf8')) : W.preflightIntake(kernel, 'CONSTR-CIVILS');
const r = W.runPipeline(W.PIPELINE, kernel, intake, 'CNC-MSP-TEST-0001', '2026-10-08');
ok(r.outcome === 'queued', `construction intake queues (outcome ${r.outcome}, ${r.summary.checks_passed}/${r.summary.checks_total} checks)`);
ok(['classify', 'frame', 'profile', 'prescribe', 'compose', 'validate'].every(s => r.stages[s]), 'all six stages present for msp_draft');
ok(r.stages.compose && r.stages.compose.placeholders && 'omp_notes' in r.stages.compose, 'compose stage carries placeholders and omp_notes (what msp_review_queue reads)');
ok(JSON.stringify(r).length < 250000, `result fits the request comfortably (${JSON.stringify(r).length} bytes)`);

// 3. halts
const unknown = W.runPipeline(W.PIPELINE, null, { subindustry_code: 'NOPE-X' }, 'R', '2026-10-08');
ok(unknown.outcome === 'triage' && unknown.defects[0].defect_code === 'AREA_OF_WORK_UNKNOWN', 'unknown area of work halts in triage');
const miss = W.runPipeline(W.PIPELINE, kernel, { ...intake, subindustry_code: 'CONSTR-NOT-A-CODE' }, 'R', '2026-10-08');
ok(miss.outcome === 'triage' && miss.defects[0].defect_code === 'CLASSIFY_TRIAGE', 'classification miss halts in triage');

// 4. regime route: an MHSA industry now passes its own route check
const mhsa = JSON.parse(JSON.stringify(kernel));
mhsa.industries[0].regulatory_regime = 'MHSA';
const m = W.runPipeline(W.PIPELINE, mhsa, intake, 'R', '2026-10-08');
const routeCheck = m.stages.validate.checks.find(c => c.check_code === 'ODMWA_COIDA_ROUTE_CORRECT');
ok(m.stages.frame.compensation_route.startsWith('ODMWA') && routeCheck.result === 'pass', 'MHSA industry: ODMWA route and the route check passes');
const wrong = JSON.parse(JSON.stringify(r.stages.frame)); wrong.compensation_route = 'ODMWA for compensable lung disease, COIDA otherwise';
const v2 = W.PIPELINE.validateDraft(r.stages.compose, wrong, r.stages.prescribe, kernel);
ok(v2.checks.find(c => c.check_code === 'ODMWA_COIDA_ROUTE_CORRECT').result === 'fail', 'OHSA industry with an ODMWA route still fails the check');

// 5. preflight intake
const pf = W.preflightIntake(kernel, 'CONSTR-BUILD');
ok(pf.jobs.length >= 1 && pf.jobs.every(j => j.hazard_codes.length), `preflight intake builds ${pf.jobs.length} jobs with hazard codes`);
ok(W.runPipeline(W.PIPELINE, kernel, pf, 'P', '2026-10-08').outcome === 'queued', 'preflight intake drafts cleanly for CONSTR-BUILD');

// 6. mails
const e = { engagement_id: 'x', reference: 'CNC-MSP-2026-1008-001', status: 'omp_queue', created_at: '2026-10-08T07:00:00Z',
  company: 'TEST <Acme> & Sons (Pty) Ltd', trading_name: 'Acme', industry_code: 'CONSTR', industry_name: 'Construction',
  subindustry_code: 'CONSTR-CIVILS', subindustry_name: 'Civil engineering', validation_status: 'valid', workforce_total: '64',
  job_categories: 3, sites: 1, contact_name: 'TEST Contact', contact_email: 'it@carenetconsultants.co.za', contact_position: 'SHE Officer',
  defects: [{ stage: 'validate', code: 'PROSE_RULE_HOLDS', detail: { detail: 'no em dash' } }], omp_requested_at: '2026-10-01T07:00:00Z' };
const site = W.siteBase('https://medicalsurveillance.carenetconsultants.co.za');
const mails = [W.renderIntakeMail(e, site), W.renderIntakeMail({ ...e, validation_status: 'triage', triage_reason: 'Area of work Other' }, site),
  W.renderResultMail(e, site, false, 5), W.renderResultMail(e, site, true, 5), W.renderResultMail({ ...e, status: 'triage' }, site, false, 5),
  W.renderOmpMail(e, site, 5), W.renderOverdueMail(e, site, 5)];
const all = mails.map(x => x.subject + x.html).join('\n');
ok(!/[–—]/.test(all), 'no en or em dash in any mail');
ok(!/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}]/u.test(all), 'no emoji in any mail');
const bodies = mails.map(x => x.html).join('\n');
ok(!bodies.includes('<Acme>') && bodies.includes('&lt;Acme&gt;'), 'client text is escaped in mail bodies (subjects are plain text)');
ok(mails[2].html.includes('review clock has not started') && mails[3].html.includes('within 5 days'), 'result mail states the review clock honestly');
ok(W.emails('salesdesk@carenetconsultants.co.za, it@carenetconsultants.co.za').length === 2 && W.emails('pending').length === 0, 'recipient parsing: list kept, pending ignored');
ok(W.siteBase('pending') === 'https://medicalsurveillance.carenetconsultants.co.za', 'site falls back to the custom domain');

writeFileSync(join(dir, 'sample-mail.html'), mails.map(x => `<h3>${x.subject}</h3>${x.html}`).join('<hr>'));
console.log(`\nsample mails: ${join(dir, 'sample-mail.html')}`);
console.log(failed ? `\n${failed} FAILED` : '\nALL PASSED');
process.exit(failed ? 1 : 0);
