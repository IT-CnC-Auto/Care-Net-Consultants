// CNC MSP FORGE | Phase 3 runner | Pipeline verification against real data
// Usage: node run_pipeline.js <kernel.json> <intake.json> <reference> <date>
// Runs every stage over the stored intake and the live kernel snapshot,
// prints the validation report, and writes draft.json for persistence.

const fs = require('fs');
const path = require('path');
const P = require('./pipeline');

const [kernelPath, intakePath, reference, dateOfIssue] = process.argv.slice(2);
const kernel = JSON.parse(fs.readFileSync(kernelPath, 'utf8'));
const intake = JSON.parse(fs.readFileSync(intakePath, 'utf8'));
const engagement = { reference, date_of_issue: dateOfIssue };

const classification = P.classify(intake, kernel);
console.log(`CLASSIFY  ${classification.industry_code} / ${classification.subindustry_code}  confidence=${classification.confidence}  triage=${classification.triage}`);
if (classification.triage) { console.error('halted at CLASSIFY triage'); process.exit(2); }

const framed = P.frame(intake, kernel, classification, dateOfIssue);
console.log(`FRAME     ${framed.instruments.length} instruments, route=${framed.compensation_route}, triggers=${framed.triggered_additions.map(t => t.rule_code).join(',') || 'none'}`);

const prof = P.profile(intake, kernel);
const exceedCount = prof.exceedances.filter(x => ['exceeds', 'significantly_exceeds', 'borderline'].includes(x.assessment)).length;
console.log(`PROFILE   ${prof.jobs.length} jobs, ${prof.jobs.reduce((a, j) => a + j.risk_matrix.length, 0)} risk matrix rows, ${prof.exceedances.length} exposures assessed (${exceedCount} at or above limit)`);

const prescribed = P.prescribe(intake, kernel, prof, framed);
console.log(`PRESCRIBE ${prescribed.programmes.length} programmes, ${prescribed.omp_notes.length} OMP notes`);

const composed = P.compose(intake, kernel, classification, framed, prof, prescribed, engagement);
console.log(`COMPOSE   ${composed.sections.length} sections, ${Object.keys(composed.placeholders).length} placeholders, locked blocks: ${composed.locked_blocks.join(', ')}`);

const validation = P.validateDraft(composed, framed, prescribed, kernel);
console.log(`VALIDATE  passed=${validation.passed}`);
for (const c of validation.checks) console.log(`  ${c.result.toUpperCase().padEnd(4)} ${c.check_code}`);
if (!validation.passed) {
  console.error('defects:', JSON.stringify(validation.defects, null, 2));
  process.exit(1);
}

const draft = { classification, framed, profile: prof, prescribed, composed, validation };
fs.writeFileSync(path.join(__dirname, 'draft.json'), JSON.stringify(draft, null, 2));
console.log(`draft.json written (${JSON.stringify(draft).length} bytes)`);
