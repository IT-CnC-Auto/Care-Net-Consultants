// CNC MSP FORGE | msp-intake-worker build step
// agent/pipeline.js stays the single source of the drafting logic. This script
// copies it, unchanged, between the PIPELINE START and PIPELINE END markers in
// index.ts so the edge function deploys as one file (the dashboard editor).
// Run from anywhere:  node msp-forge/supabase/functions/msp-intake-worker/build.mjs
// The test (msp-forge/test/intake-worker.test.mjs) fails if the copy drifts.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const indexPath = join(here, 'index.ts');
const pipelinePath = join(here, '..', '..', '..', 'agent', 'pipeline.js');

const START = '/* PIPELINE START: generated from msp-forge/agent/pipeline.js by build.mjs, do not edit here */';
const END = '/* PIPELINE END */';

const index = readFileSync(indexPath, 'utf8');
const pipeline = readFileSync(pipelinePath, 'utf8').replace(/\r\n/g, '\n').trimEnd();
const a = index.indexOf(START);
const b = index.indexOf(END);
if (a < 0 || b < 0 || b < a) throw new Error('pipeline markers not found in index.ts');

const out = index.slice(0, a + START.length) + '\n' + pipeline + '\n  ' + index.slice(b);
writeFileSync(indexPath, out);
console.log(`index.ts rebuilt: pipeline.js ${pipeline.length} chars inlined, index.ts now ${out.length} chars`);
