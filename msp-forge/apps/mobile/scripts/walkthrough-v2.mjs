#!/usr/bin/env node
// Bee-Inspect | a scripted walk through the web export of the demo, in headless
// Chromium at 390 x 844, for the screenshots in docs/bee-inspect/p4/v2/.
// It walks: the demo sign in, Home with the context bar, the place switcher
// (recent places, companies, instant search), registration for three industries
// (mining, healthcare, agriculture: company, places, people, done), the places
// tree, a place, the place editor, the template picker, an inspection (canvas,
// area, a Fail item with its sealed photo), the evidence library (grouped,
// filtered, searched), a piece of evidence with its sidecar and a new version.
//
// Run from apps/mobile after `npx expo export --platform web` and
// `npx expo serve --port 8087`:
//   node scripts/walkthrough-v2.mjs [http://localhost:8087] [out dir]
// Needs Playwright with Chromium (PLAYWRIGHT_MODULE or /opt/node22/lib/node_modules/playwright).

import { mkdirSync, statSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);
let pw = null;
for (const m of [process.env.PLAYWRIGHT_MODULE, 'playwright', '/opt/node22/lib/node_modules/playwright'].filter(Boolean)) {
  try {
    pw = require(m);
    break;
  } catch {
    // next
  }
}
if (!pw) throw new Error('Playwright was not found.');

const BASE = process.argv[2] ?? 'http://localhost:8087';
const OUT = path.resolve(process.argv[3] ?? path.join(process.cwd(), '..', '..', 'docs', 'bee-inspect', 'p4', 'v2'));
mkdirSync(OUT, { recursive: true });

const errors = [];
const shots = [];
const browser = await pw.chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, geolocation: { latitude: -25.7, longitude: 27.6 }, permissions: ['geolocation'], locale: 'en-ZA', timezoneId: 'Africa/Johannesburg' });
const page = await ctx.newPage();
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
page.on('console', (m) => {
  if (m.type() === 'error' && !/favicon|Download the React DevTools/.test(m.text())) errors.push(`console: ${m.text()}`);
});

const wait = (ms) => page.waitForTimeout(ms);
// Icon glyphs can sit in a button's accessible name, so "exact" matches the words at the end.
const esc = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// Screens further down the stack stay in the page, hidden: only visible elements count.
const btn = (name, exact = false) => page.getByRole('button', { name: exact ? new RegExp(`^\\W*${esc(name)}$`) : name }).locator('visible=true').first();
async function click(name, exact = false) {
  const b = btn(name, exact);
  await b.scrollIntoViewIfNeeded();
  await b.click();
  await wait(450);
}
async function fill(label, value) {
  const f = page.getByLabel(label, { exact: true }).locator('visible=true').first();
  await f.scrollIntoViewIfNeeded();
  await f.fill(value);
  await wait(150);
}
async function shot(name, what, opts = {}) {
  await wait(opts.settle ?? 500);
  const file = path.join(OUT, `${name}.jpg`);
  await page.screenshot({ path: file, type: 'jpeg', quality: opts.quality ?? 62, fullPage: false });
  let size = statSync(file).size;
  // Keep each picture under about 200 KB.
  for (let q = (opts.quality ?? 62) - 10; size > 200 * 1024 && q >= 30; q -= 8) {
    await page.screenshot({ path: file, type: 'jpeg', quality: q, fullPage: false });
    size = statSync(file).size;
  }
  shots.push({ name: `${name}.jpg`, what, kb: Math.round(size / 1024) });
  process.stdout.write(`shot ${name}.jpg (${Math.round(size / 1024)} KB)\n`);
}
async function scrollTo(text) {
  const el = page.getByText(text, { exact: false }).locator('visible=true').first();
  await el.scrollIntoViewIfNeeded();
  await wait(300);
}
async function top() {
  await page.evaluate(() => document.querySelectorAll('*').forEach((e) => {
    if (e.scrollTop) e.scrollTop = 0;
  }));
  await wait(300);
}
async function tab(name) {
  // Go back down the stack until the tab bar shows.
  for (let i = 0; i < 8 && !(await page.getByRole('tab', { name }).locator('visible=true').count()); i++) {
    await page.goBack();
    await wait(500);
  }
  await page.getByRole('tab', { name }).locator('visible=true').first().click();
  await wait(700);
  await top();
}

try {
  // Sign in to the demo.
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await wait(1200);
  await click('Try the demo');
  await wait(1200);
  await fill('Code from your authenticator app', '123456');
  await click('Turn on MFA');
  await wait(1500);
  if (await btn('Not now').isVisible().catch(() => false)) await click('Not now');

  // Home: construction company, context bar.
  await shot('01-home-construction', 'Home for the fictitious construction company: the context bar (company and place, a tap from the switcher), the offline and sync state, one primary action and the registration entry.');

  // Switcher: companies and search.
  await click('Working in Rietvlei Civils');
  await wait(600);
  await shot('02-switcher', 'The place switcher: one search box over every company and place, the five demonstration companies (five industries) and every place, each with Start inspection here.');
  await page.getByLabel('Search companies and places').locator('visible=true').first().fill('work');
  await wait(500);
  await shot('03-switcher-search', 'Instant search: "work" finds workshops and work areas across the companies, with the breadcrumb of each.');
  await page.getByLabel('Search companies and places').locator('visible=true').first().fill('');
  await wait(300);
  await click('Switch to Magaliesberg Aggregates');
  await wait(700);

  // Places tree for mining.
  await tab('Places');
  await shot('04-places-mining', 'Places of the fictitious quarry (Mining): a mine or quarry section, a factory or plant, an office, with sections, a haul truck fleet, a workshop and a department under them. Every row has Start inspection here.');
  await click('Crushing and screening plant, Factory or plant');
  await wait(700);
  await shot('05-place-detail', 'One place: breadcrumb, kind of place, responsible person and headcount, the places under it, the inspections and evidence here, and one primary action: Start inspection here.');
  await click('Add', true);
  await wait(700);
  await shot('06-place-editor', 'Adding under the plant: only the kinds of place the kernel offers for mining and the plant allows; details stay folded until wanted.');
  await page.goBack();
  await wait(700);

  // Template picker at the plant.
  await click('Start inspection here');
  await wait(900);
  await shot('07-template-picker-mining', 'The template picker at a mining plant: the Mining walkthrough from the kernel first, then the Section F registers the plant suits (machine guarding and others), each with its checks and how often.');
  await click('Machine guarding inspection register');
  await click('All 22 Section F registers');
  await scrollTo('About this template');
  await shot('08-template-about', 'Every Section F register stays available everywhere; the chosen template shows where it files, how often ("Set by your competent person" where no verified interval is held), who usually does it, its legal basis and how long it is kept.');
  await page.goBack();
  await wait(600);
  await page.goBack();
  await wait(600);

  // The inspection in progress at the plant.
  await tab('Home');
  await click('Open Machine guarding, Crushing and screening plant (fictitious)');
  await wait(800);
  await shot('09-inspection-mining', 'The inspection canvas at the plant, on the kernel\'s machine guarding register: the Fail rule, the areas walked and the risk register (20 Extreme down to 5 Medium).');
  await click('Conveyor 2 tail pulley', false);
  await wait(800);
  await shot('10-area-checklist', 'An area: each kernel checklist line takes Pass, Fail, N/A or Observe; the "Gaps to look for" lines pass when the gap is not found.');
  await click('Open item 4', false);
  await wait(900);
  await scrollTo('Sealed evidence');
  await shot('11-item-fail-photo', 'A Fail with its sealed photo: time, GPS, inspector, fingerprint and seal; markers are saved as a new version, never over the original.');
  for (let i = 0; i < 3; i++) {
    await page.goBack();
    await wait(500);
  }

  // Evidence library.
  await tab('Evidence');
  await shot('12-evidence-library', 'The evidence library: storage against the 10 GB line (the same bytes are stored once), instant offline search, filters by type, risk band and date, grouped by place.');
  await click('All companies', true);
  await click('Risk band Extreme');
  await shot('13-evidence-filtered', 'Filtered to Extreme risk across all companies: the quarry\'s tail pulley and the construction scaffold, each verified on the server after upload.');
  await click('Risk band Extreme');
  await page.getByLabel('Search the evidence').locator('visible=true').first().fill('racking');
  await wait(600);
  await click('Inspection', true);
  await shot('14-evidence-search', 'Search over findings, transcripts and evidence metadata ("racking"), grouped by inspection.');
  await page.getByLabel('Search the evidence').locator('visible=true').first().fill('');
  await wait(300);
  await page.getByRole('button', { name: /Conveyor 2 tail pulley without its guard/ }).first().click();
  await wait(900);
  await shot('15-evidence-detail', 'One piece of evidence: the original, and its sealed metadata sidecar (capture time, GPS, inspector, device, inspection, checklist item, SHA 256, seal).');
  await scrollTo('Where it is kept');
  await shot('16-evidence-storage', 'Where it is kept: the canonical path (tenant, company, place path, inspection, item, evidence, version), the content address, how many uses share the bytes, retention and legal hold, and the verified upload.');
  await scrollTo('Correct the caption');
  await page.getByLabel('Correct the caption', { exact: true }).locator('visible=true').first().fill('Conveyor 2 tail pulley without its guard, isolator not locked out (fictitious)');
  await click('Save as a new version');
  await wait(800);
  await scrollTo('Versions');
  await shot('17-evidence-version', 'A caption correction saved as version 2 on the same bytes: version 1 stays exactly as it was, and both are listed.');
  await page.goBack();
  await wait(500);

  // Registration: mining, then healthcare, then agriculture.
  const register = async (industry, legal, trading, sub, key) => {
    await tab('Home');
    await click('Register a company');
    await wait(700);
    await fill('Legal name', legal);
    await fill('Trading name (optional)', trading);
    await page.getByLabel('Search industries').locator('visible=true').first().fill(industry.slice(0, 5));
    await wait(400);
    await click(industry, true);
    await click(sub, true);
    await click('Add the 16(1), 16(2) and POPIA contacts now');
    await fill('OHS Act 16(1): chief executive officer', 'Sam Demo, Chief Executive (fictitious)');
    await fill('OHS Act 16(2): assigned person', 'Lee Demo, Health and Safety Manager (fictitious)');
    await scrollTo('Industry');
    await shot(`${key}-a-company`, `Registration, step 1 of 4, ${industry}: the company, the industry and subindustry from the kernel (17 industries), and the duty holders; saved on the phone as you go.`);
    await click('Save and continue');
    await wait(800);
    await shot(`${key}-b-places`, `Step 2, places for ${industry.toLowerCase()}: the kinds of place the kernel suggests for this industry, to keep, rename or skip.`);
    await click('Add these places');
    await wait(700);
    await click('Add departments');
    await wait(700);
    await scrollTo('Your places');
    await shot(`${key}-c-tree`, `The ${industry.toLowerCase()} places tree after one tap each: the suggested places and the File departments the industry's registers sit with.`);
    await click('Continue to people');
    await fill('Full name', 'Pat Demo (fictitious)');
    await click('Inspector', true);
    await click('16(2) Assigned person', true);
    await click('Add person');
    await wait(500);
    if (key === '18') await shot(`${key}-d-people`, 'Step 3, people: the authorised persons (16(1), 16(2)), inspectors and assistants.');
    await click('Finish registration');
    await wait(700);
    if (key === '18') await shot(`${key}-e-done`, 'Done: onboarding goes to Care Net for review; Start inspection opens once the company is Active. Places, people and the kernel templates are ready on the phone.');
  };
  await register('Mining', 'Witwater Chrome Mining (Pty) Ltd (fictitious)', 'Witwater Chrome', 'Chrome mining', '18');
  await register('Healthcare and laboratories', 'Hilltop Clinic Group (Pty) Ltd (fictitious)', 'Hilltop Clinics', 'Clinics and practices', '19');
  await register('Agriculture and forestry', 'Blue Crane Orchards (Pty) Ltd (fictitious)', 'Blue Crane Orchards', 'Crop farming', '20');

  // Back on Home with recent places and the new company.
  await tab('Home');
  await shot('21-home-after', 'Home after registering: the newest company is active in the context bar; recent places sit a tap away.');
} catch (e) {
  errors.push(`walkthrough stopped: ${e.message}`);
  await page.screenshot({ path: path.join(OUT, '..', 'v2-failure.png') }).catch(() => {});
} finally {
  await browser.close();
}

process.stdout.write(`\n${shots.length} screenshots, ${errors.length} errors\n`);
for (const e of errors) process.stdout.write(`  ${e}\n`);
process.stdout.write(JSON.stringify(shots) + '\n');
process.exit(errors.some((e) => e.startsWith('walkthrough stopped') || e.startsWith('pageerror')) ? 1 : 0);
