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
writeFileSync(modPath, core + '\nexport { PIPELINE, runPipeline, preflightIntake, renderIntakeMail, renderResultMail, renderOmpMail, renderOverdueMail, emails, siteBase, mailRecipients, recipientsLine, mailForEvent, renderAbandonedMail, recordLink, PIPELINE_VERSION, MODEL_USED, bookingLink, renderBookingConfirmedMail, renderClientChoiceMail };\n');
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

// 5b. missing measured levels (CNC-MSP-2026-1008-001, 12/10/2026)
const noLevel = { ...intake, exposures: [ { hazard_location: 'Heat and humidity', measured_level: null, unit: 'Whole company', stated_oel: 'Underground workings' }, { hazard_location: 'Flying particles', unit: 'all' } ] };
const nl = W.runPipeline(W.PIPELINE, kernel, noLevel, 'R', '2026-10-12');
ok(nl.stages.profile.exceedances.every(x => x.measured === 'Not measured'), 'exposure rows without a level read Not measured');
ok(!JSON.stringify(nl).includes('undefined') && nl.outcome === 'queued', 'no undefined text anywhere and the Plan still queues');
const poisoned = JSON.parse(JSON.stringify(r.stages.compose)); poisoned.sections[0].blocks.push({ kind: 'paragraph', text: 'measured undefined' });
const vp = W.PIPELINE.validateDraft(poisoned, r.stages.frame, r.stages.prescribe, kernel);
ok(vp.checks.find(c => c.check_code === 'NO_MISSING_VALUE_TEXT').result === 'fail' && !vp.passed, 'a stray undefined in client text halts the Plan');

// 6. mails
const e = { engagement_id: 'x', reference: 'CNC-MSP-2026-1008-001', status: 'omp_queue', created_at: '2026-10-08T07:00:00Z',
  company: 'TEST <Acme> & Sons (Pty) Ltd', trading_name: 'Acme', industry_code: 'CONSTR', industry_name: 'Construction',
  subindustry_code: 'CONSTR-CIVILS', subindustry_name: 'Civil engineering', validation_status: 'valid', workforce_total: '64',
  job_categories: 3, sites: 1, contact_name: 'TEST Contact', contact_email: 'it@carenetconsultants.co.za', contact_position: 'SHE Officer',
  defects: [{ stage: 'validate', code: 'PROSE_RULE_HOLDS', detail: { detail: 'no em dash' } }], omp_requested_at: '2026-10-01T07:00:00Z' };
const site = W.siteBase('https://medicalsurveillance.carenetconsultants.co.za');
const drafted = { reference: e.reference, checks_passed: true, checks: 10, checks_total: 10 };
const mails = [W.renderIntakeMail(e, site), W.renderIntakeMail({ ...e, validation_status: 'triage', triage_reason: 'Area of work Other', contact_number: '060 070 2723' }, site),
  W.renderResultMail(e, site, drafted), W.renderResultMail({ ...e, status: 'triage' }, site, { checks_passed: false }),
  W.renderOmpMail(e, site, 5), W.renderOverdueMail(e, site, 5),
  W.renderAbandonedMail({ event_type: 'intake.submitted', engagement: e }, 'sendMail 503', 5, site)];
const all = mails.map(x => x.subject + x.html).join('\n');
ok(!/[–—]/.test(all), 'no en or em dash in any mail');
ok(!/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}]/u.test(all), 'no emoji in any mail');
const bodies = mails.map(x => x.html).join('\n');
ok(!bodies.includes('<Acme>') && bodies.includes('&lt;Acme&gt;'), 'client text is escaped in mail bodies (subjects are plain text)');
ok(mails[0].subject === 'New assessment in: CNC-MSP-2026-1008-001, TEST <Acme> & Sons (Pty) Ltd', 'submission mail subject follows the SOP');
ok(mails[0].html.includes('A new Medical Surveillance Plan assessment has just come in.') && mails[0].html.includes('quick call to confirm'), 'submission mail carries the SOP wording');
ok(mails[0].html.includes('review.html?ref=CNC-MSP-2026-1008-001') && mails[0].html.includes('Open the record'), 'submission mail links to the record');
ok(mails[0].html.includes('no contact number given') && mails[1].html.includes('tel:0600702723') && mails[1].html.includes('060 070 2723'), 'contact number shown when known, said plainly when not');
ok(mails[1].html.includes('Needs triage: Area of work Other') && mails[1].html.includes('look over the record before you call'), 'triage submission mail asks for a look first');
ok(mails[2].subject.startsWith('Plan drafted, waiting for booking') && mails[2].html.includes('booking deposit is paid') && mails[2].html.includes('10 of 10') && mails[2].html.includes('marked planning only'), 'drafted mail: waiting for booking, checks, marking');
ok(!/practitioner review/i.test(mails[2].html) && mails[3].subject.startsWith('Plan drafting needs a person'), 'a clean Plan no longer goes to the practitioner queue; a halted one asks for a person');
{
  const ev = (t, payload) => ({ event_id: 'x', event_type: t, attempts: 0, payload, engagement: e });
  ok(W.mailForEvent(ev('intake.submitted', {}), site).subject.startsWith('New assessment in')
    && W.mailForEvent(ev('plan.drafted', drafted), site).subject.startsWith('Plan drafted')
    && W.mailForEvent(ev('plan.drafted', { checks_passed: false }), site).subject.startsWith('Plan drafting needs')
    && W.mailForEvent(ev('plan.draft_failed', {}), site).subject.startsWith('Plan drafting needs')
    && W.mailForEvent(ev('plan.released', {}), site) === null
    && W.mailForEvent({ event_type: 'intake.submitted' }, site) === null, 'each sales event maps to its mail; others send nothing');
}
ok(mails[6].subject === 'MSP mail abandoned: CNC-MSP-2026-1008-001, intake.submitted' && mails[6].html.includes('sendMail 503'), 'IT is told when a mail is abandoned');
{
  // Booking gate (worker v1.2.0, migration 074)
  const waiting = { ...e, status: 'awaiting_booking' };
  const url = W.bookingLink('https://medicalsurveillance.carenetconsultants.co.za/booking-confirm.html', 'abc123');
  ok(url === 'https://medicalsurveillance.carenetconsultants.co.za/booking-confirm.html?t=abc123'
    && W.bookingLink('https://x.test/p?a=1', 't') === 'https://x.test/p?a=1&t=t'
    && W.bookingLink('pending', 't') === null && W.bookingLink('https://x.test/p', null) === null, 'booking link: built from the page setting, none while pending');
  const withLink = W.renderResultMail(waiting, site, drafted, { bookingUrl: url });
  const noLink = W.renderResultMail(waiting, site, drafted);
  ok(withLink.html.includes(url) && withLink.html.includes('Confirm booking or deposit') && withLink.html.includes('nothing changes until you press Confirm'),
    'drafted mail carries the one-time confirmation link when the page exists');
  ok(!noLink.html.includes('Confirm booking or deposit') && noLink.html.includes('send IT the booking number or deposit reference'), 'without the page, the mail says how to send the evidence');
  const already = W.renderResultMail({ ...e, status: 'booking_confirmed' }, site, drafted);
  ok(already.subject.startsWith('Plan drafted, booking confirmed') && already.html.includes('ready for release'), 'a Plan drafted after its booking was confirmed says it is ready for release');
  const conf = W.renderBookingConfirmedMail({ ...e, status: 'booking_confirmed' }, site,
    { type: 'deposit', evidence_ref: 'OZ-123', confirmed_by: 'link:Celeste', method: 'link', confirmed_at: '2026-10-14T08:00:00Z' });
  ok(conf.subject === 'Booking confirmed: CNC-MSP-2026-1008-001, TEST <Acme> & Sons (Pty) Ltd' && conf.html.includes('Booking deposit paid')
    && conf.html.includes('OZ-123') && conf.html.includes('Celeste (one-time link)') && !conf.html.includes('link:Celeste') && conf.html.includes('ready for release'), 'booking confirmed mail: type, evidence, who, status');
  const early = W.renderBookingConfirmedMail({ ...e, status: 'classifying' }, site, { type: 'booking', evidence_ref: 'MCO 55', confirmed_by: 'it:sql-editor', method: 'staff' });
  ok(early.html.includes('Medicals booked with Care Net') && early.html.includes('passes the gate as soon as it is drafted'), 'a booking confirmed before drafting says the gate passes on drafting');
  const choices = ['booked', 'deposit', 'call_me'].map((c) => W.renderClientChoiceMail(e, site, { choice: c, note: c === 'call_me' ? 'after 14:00' : null, chosen_at: '2026-10-14T08:00:00Z' }));
  ok(choices[0].subject.startsWith('Client says the medicals are booked') && choices[0].html.includes('I have booked my medicals')
    && choices[1].subject.startsWith('Client wants to pay a booking deposit') && choices[1].html.includes('Online payment is not built yet')
    && choices[2].subject.startsWith('Client asks for a call') && choices[2].html.includes('after 14:00'), 'each client answer gets its own mail and next step');
  const all2 = [withLink, noLink, already, conf, early, ...choices].map((x) => x.subject + x.html).join('\n');
  ok(!/[–—]/.test(all2) && !/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}]/u.test(all2), 'booking mails: no dashes, no emoji');
  ok(W.mailForEvent({ event_type: 'booking.confirmed', payload: { type: 'booking' }, engagement: e }, site).subject.startsWith('Booking confirmed')
    && W.mailForEvent({ event_type: 'client.booking_choice', payload: { choice: 'deposit' }, engagement: e }, site).subject.startsWith('Client wants'),
    'booking events map to their mails');
}
{
  const header = readFileSync(join(root, 'agent/pipeline.js'), 'utf8').split('\n')[0];
  ok(header.includes(`v${W.PIPELINE_VERSION} `) && r.summary.pipeline_version === W.PIPELINE_VERSION, 'drafting records the pipeline version, in step with pipeline.js');
}
ok(W.emails('salesdesk@carenetconsultants.co.za, it@carenetconsultants.co.za').length === 2 && W.emails('pending').length === 0, 'recipient parsing: list kept, pending ignored');
{
  const r = W.mailRecipients(['salesdesk@carenetconsultants.co.za'], W.emails('director@example.co.za, salesdesk@carenetconsultants.co.za'), W.emails('it@carenetconsultants.co.za, director@example.co.za'));
  ok(r.to.length === 1 && r.cc.join() === 'director@example.co.za' && r.bcc.join() === 'it@carenetconsultants.co.za', 'blind copy: each address once, To over Cc over Bcc');
  ok(W.recipientsLine(r).endsWith(' | bcc it@carenetconsultants.co.za') && W.recipientsLine(W.mailRecipients(['a@b.co'], [], W.emails('pending'))) === 'a@b.co', 'blind copy recorded in the register; pending sends none');
}
ok(W.siteBase('pending') === 'https://medicalsurveillance.carenetconsultants.co.za', 'site falls back to the custom domain');

writeFileSync(join(dir, 'sample-mail.html'), mails.map(x => `<h3>${x.subject}</h3>${x.html}`).join('<hr>'));
console.log(`\nsample mails: ${join(dir, 'sample-mail.html')}`);
console.log(failed ? `\n${failed} FAILED` : '\nALL PASSED');
process.exit(failed ? 1 : 0);
