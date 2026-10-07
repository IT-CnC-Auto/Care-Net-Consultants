#!/usr/bin/env node
// Bee-Inspect | app icon, Android adaptive icon, monochrome icon, splash and
// favicon, from the Director's icon set in assets/brand/bee-inspect-icon/.
//
//   icon.png                    the supplied icon-1024.png (opaque, red with the white bee)
//   android-icon-background.png the supplied adaptive-icon-background.png (plain red)
//   android-icon-foreground.png the white bee on transparency, rendered from the
//                               vector master bee-inspected-app-icon.svg and fitted
//                               inside the Android safe zone (the centre circle of
//                               66 of 108 dp); the red stripes, the letters and the
//                               tick are cut out, so the red background shows through
//   android-icon-monochrome.png the same shape (Android themed icons use its alpha)
//   splash-icon.png             the white bee on transparency, for the red splash
//   favicon.png                 the supplied favicon-48.png
//
// The vector master is drawn by headless Chromium (Playwright), because no SVG
// library is installed here. The master sets the letters "BI" in the system
// font, so they can differ slightly between renderers; converting that text to
// outlines in the master would make every render identical.
//
// Run from msp-forge/:  node apps/mobile/scripts/build-icons.mjs
// Needs Playwright with its Chromium (PLAYWRIGHT_MODULE, or the global
// /opt/node22/lib/node_modules/playwright used by test/browser).

import { copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP = path.resolve(HERE, '..');
const SRC = path.join(APP, 'assets', 'brand', 'bee-inspect-icon');
const OUT = path.join(APP, 'assets', 'images');
const RED = '#DC2626';

const require = createRequire(import.meta.url);
let pw = null;
for (const m of [process.env.PLAYWRIGHT_MODULE, 'playwright', '/opt/node22/lib/node_modules/playwright'].filter(Boolean)) {
  try {
    pw = require(m);
    break;
  } catch {
    // try the next place
  }
}
if (!pw) throw new Error('Playwright was not found; set PLAYWRIGHT_MODULE.');

const master = readFileSync(path.join(SRC, 'bee-inspected-app-icon.svg'), 'utf8').replace(/<\?xml[^>]*>\s*/, '');

// In the page: turn the master into a white bee on transparency. Everything
// drawn in the red of the background (the stripes, the letters, the tick) is
// moved into a mask as black, so it cuts through the white instead of being
// painted red. Then the bee is scaled so its box is `fit` of the canvas and
// centred. Returns the page ready for a transparent screenshot.
async function renderBee(page, size, fit) {
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<!doctype html><html><head><style>html,body{margin:0;background:transparent}svg{display:block}</style></head><body>${master}</body></html>`);
  await page.evaluate(
    ({ size, fit, red }) => {
      const NS = 'http://www.w3.org/2000/svg';
      const svg = document.querySelector('svg');
      svg.setAttribute('width', String(size));
      svg.setAttribute('height', String(size));
      svg.querySelector(':scope > rect')?.remove();
      const art = svg.querySelector(':scope > g');
      // Measure the bee in the 1024 user space before anything moves.
      const r = art.getBoundingClientRect();
      const s0 = svg.getBoundingClientRect();
      const box = { x: ((r.x - s0.x) * 1024) / s0.width, y: ((r.y - s0.y) * 1024) / s0.height, width: (r.width * 1024) / s0.width, height: (r.height * 1024) / s0.height };
      const defs = document.createElementNS(NS, 'defs');
      const mask = document.createElementNS(NS, 'mask');
      mask.setAttribute('id', 'cut');
      mask.setAttribute('maskUnits', 'userSpaceOnUse');
      mask.setAttribute('x', '-2000');
      mask.setAttribute('y', '-2000');
      mask.setAttribute('width', '6000');
      mask.setAttribute('height', '6000');
      // The mask is drawn in the master's paint order: white shapes paint
      // white (visible), shapes in the background red paint black (cut out),
      // so a white tick or dot drawn over a red stripe stays visible.
      const black = document.createElementNS(NS, 'rect');
      for (const [k, v] of Object.entries({ x: '-2000', y: '-2000', width: '6000', height: '6000', fill: '#000' })) black.setAttribute(k, v);
      mask.appendChild(black);
      const paint = art.cloneNode(true);
      paint.removeAttribute('fill');
      mask.appendChild(paint);
      defs.appendChild(mask);
      svg.insertBefore(defs, svg.firstChild);
      const isRed = (v) => (v || '').toUpperCase() === red;
      for (const el of Array.from(paint.querySelectorAll('*'))) {
        for (const attr of ['fill', 'stroke']) {
          const v = el.getAttribute(attr);
          if (!v || v === 'none') continue;
          el.setAttribute(attr, isRed(v) ? '#000' : '#fff');
        }
      }
      // What shows: the bee's own box filled white, seen through the mask.
      const box0 = art.getBBox();
      const fillRect = document.createElementNS(NS, 'rect');
      for (const [k, v] of Object.entries({ x: String(box0.x - 4), y: String(box0.y - 4), width: String(box0.width + 8), height: String(box0.height + 8), fill: '#fff' })) fillRect.setAttribute(k, v);
      const inner = document.createElementNS(NS, 'g');
      inner.setAttribute('transform', art.getAttribute('transform'));
      inner.appendChild(fillRect);
      const wrap = document.createElementNS(NS, 'g');
      wrap.setAttribute('mask', 'url(#cut)');
      wrap.appendChild(inner);
      svg.replaceChild(wrap, art);
      // Fit and centre.
      const scale = (fit * 1024) / Math.max(box.width, box.height);
      const tx = 512 - scale * (box.x + box.width / 2);
      const ty = 512 - scale * (box.y + box.height / 2);
      const outer = document.createElementNS(NS, 'g');
      outer.setAttribute('transform', `translate(${tx} ${ty}) scale(${scale})`);
      svg.replaceChild(outer, wrap);
      outer.appendChild(wrap);
    },
    { size, fit, red: RED },
  );
}

// Largest distance from the centre of any visible pixel, as a share of the half width.
async function reach(page, png, size) {
  return page.evaluate(
    async ({ b64, size }) => {
      const img = new Image();
      img.src = 'data:image/png;base64,' + b64;
      await img.decode();
      const c = document.createElement('canvas');
      c.width = size;
      c.height = size;
      const ctx = c.getContext('2d');
      ctx.drawImage(img, 0, 0);
      const d = ctx.getImageData(0, 0, size, size).data;
      let max = 0;
      let opaque = 0;
      const h = size / 2;
      for (let y = 0; y < size; y++)
        for (let x = 0; x < size; x++) {
          const a = d[(y * size + x) * 4 + 3];
          if (a > 8) {
            opaque++;
            max = Math.max(max, Math.hypot(x + 0.5 - h, y + 0.5 - h));
          }
          // Every visible pixel must be white (a white bee, nothing else).
          if (a > 200 && (d[(y * size + x) * 4] < 240 || d[(y * size + x) * 4 + 1] < 240)) return { error: `not white at ${x},${y}` };
        }
      return { reach: max / h, opaque };
    },
    { b64: png.toString('base64'), size },
  );
}

const browser = await pw.chromium.launch();
try {
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  const SIZE = 1024;
  // Android safe zone: a circle of 66 dp inside the 108 dp canvas. Keep the bee
  // inside 92% of that circle for a margin.
  const SAFE = 66 / 108;
  let fit = 0.62;
  let fg = null;
  for (let i = 0; i < 30; i++) {
    await renderBee(page, SIZE, fit);
    fg = await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: SIZE, height: SIZE } });
    const r = await reach(page, fg, SIZE);
    if (r.error) throw new Error(r.error);
    if (r.reach <= SAFE * 0.92) {
      process.stdout.write(`foreground: bee box ${Math.round(fit * 100)}% of the canvas, reaches ${(r.reach * 100).toFixed(1)}% of the half width (safe zone ${(SAFE * 100).toFixed(1)}%)\n`);
      break;
    }
    fit -= 0.01;
  }
  writeFileSync(path.join(OUT, 'android-icon-foreground.png'), fg);
  writeFileSync(path.join(OUT, 'android-icon-monochrome.png'), fg);

  await renderBee(page, SIZE, 0.86);
  const splash = await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: SIZE, height: SIZE } });
  writeFileSync(path.join(OUT, 'splash-icon.png'), splash);
} finally {
  await browser.close();
}

copyFileSync(path.join(SRC, 'icon-1024.png'), path.join(OUT, 'icon.png'));
copyFileSync(path.join(SRC, 'adaptive-icon-background.png'), path.join(OUT, 'android-icon-background.png'));
copyFileSync(path.join(SRC, 'favicon-48.png'), path.join(OUT, 'favicon.png'));
process.stdout.write('Wrote icon.png, android-icon-foreground.png, android-icon-background.png, android-icon-monochrome.png, splash-icon.png and favicon.png to apps/mobile/assets/images/\n');
