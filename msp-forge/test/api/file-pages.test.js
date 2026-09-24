'use strict';
// Contract 12.8: a Health and Safety File is never presented as a Medical
// Surveillance Plan. The File pages carry their own menu and never offer the
// Plan's menu items or its sample as if they were part of the File.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const VERCEL = path.join(__dirname, '..', '..', 'vercel');
const FILE_PAGES = ['health-and-safety-file.html', 'hsf-builder.html', 'hsf-sample.html', 'hsf-staff.html'];

for (const page of FILE_PAGES) {
  const html = fs.readFileSync(path.join(VERCEL, page), 'utf8');
  test(page + ' carries the File menu, not the Plan menu', () => {
    for (const href of ['/health-and-safety-file.html', '/hsf-builder.html', '/hsf-sample.html', '/portal.html']) {
      assert.ok(html.includes('<li><a href="' + href + '">'), page + ' menu lacks ' + href);
    }
    assert.ok(!/<li><a href="\/shop\.html">Build your Plan<\/a><\/li>/.test(html), page + ' still offers Build your Plan in its menu');
    assert.ok(!/<li><a href="\/sample\.html">Sample Plan<\/a><\/li>/.test(html), page + ' still offers Sample Plan in its menu');
  });
  test(page + ' never labels the File or its samples as a Plan', () => {
    assert.ok(!/>\s*Sample Plan\s*</.test(html), page + ' shows a "Sample Plan" label');
    assert.ok(!/>\s*Sample Medical Surveillance Plan\s*</.test(html), page + ' links to the Plan sample');
    assert.ok(!/Sample Medical Surveillance Plan/i.test(html.replace(/"notes":\s*"[^"]*"/g, '')), page + ' names the Plan sample');
  });
}

test('the portal names the two samples apart', () => {
  const html = fs.readFileSync(path.join(VERCEL, 'portal.html'), 'utf8');
  assert.ok(html.includes('title="Sample Medical Surveillance Plan">Sample Plan<'));
  assert.ok(html.includes('title="Sample Health and Safety File">Sample File<'));
});
