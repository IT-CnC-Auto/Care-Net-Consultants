// CNC MSP FORGE | msp-plan-render build step
// factory/render_core.js, templates.json and config.json stay the single source of the
// Plan document. This script copies them, unchanged, between their markers in index.ts so
// the edge function deploys as one file (the dashboard editor).
// Run from anywhere:  node msp-forge/supabase/functions/msp-plan-render/build.mjs
// The test (msp-forge/test/plan-render.test.mjs) fails if a copy drifts.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const factory = join(here, '..', '..', '..', 'factory');
const indexPath = join(here, 'index.ts');
const read = (f) => readFileSync(join(factory, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();

let index = readFileSync(indexPath, 'utf8').replace(/\r\n/g, '\n');
function inline(name, content, indent = '') {
  const startTag = `/* ${name} START: generated from msp-forge/factory/`;
  const a = index.indexOf(startTag);
  const aEnd = index.indexOf('*/', a) + 2;
  const b = index.indexOf(`/* ${name} END */`);
  if (a < 0 || b < 0 || b < aEnd) throw new Error(`${name} markers not found in index.ts`);
  index = index.slice(0, aEnd) + '\n' + content + '\n' + indent + index.slice(b);
}
inline('TEMPLATES', JSON.stringify(JSON.parse(read('templates.json')), null, 1));
inline('CONFIG', JSON.stringify(JSON.parse(read('config.json')), null, 1));
inline('RENDER', read('render_core.js'), '  ');
writeFileSync(indexPath, index);
console.log(`index.ts rebuilt: render_core.js, templates.json and config.json inlined, index.ts now ${index.length} chars`);
