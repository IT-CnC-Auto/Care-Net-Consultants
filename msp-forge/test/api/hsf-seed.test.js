// CNC HSF FORGE | tests for the frozen seed generator hsf/build_seed.py (node --test).
// Migration 048_hsf_library_seed.sql is applied to the live project, so the
// generator that wrote it never writes it again (review finding INT-1): it pins
// 048's SHA-256, checks that SPEC.md Part B still renders everything outside the
// element rows exactly as 048 loaded it, and requires every element row change
// since 048 to be carried by a later migration. The generator is run with
// python3; the refusal cases use a copy of the migrations in a temporary folder,
// so nothing in the repository is written by these tests.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const GEN = path.join(ROOT, 'hsf', 'build_seed.py');
const MIG = path.join(ROOT, 'supabase', 'migrations');
const SEED = path.join(MIG, '048_hsf_library_seed.sql');
const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const run = (args) => spawnSync('python3', [GEN].concat(args || []), { cwd: ROOT, encoding: 'utf8', timeout: 120000 });

function copyMigrations() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hsf-seed-'));
  for (const f of fs.readdirSync(MIG)) if (f.endsWith('.sql')) fs.copyFileSync(path.join(MIG, f), path.join(dir, f));
  return dir;
}

test('048 is pinned in the generator to the bytes in the repository', () => {
  const pin = /APPLIED_SQL_SHA256 = '([0-9a-f]{64})'/.exec(fs.readFileSync(GEN, 'utf8'));
  assert.ok(pin, 'hsf/build_seed.py pins no SHA-256 for 048');
  assert.equal(sha(SEED), pin[1], '048_hsf_library_seed.sql differs from the file applied to live');
});

test('the generator never writes a migration', () => {
  const src = fs.readFileSync(GEN, 'utf8');
  assert.ok(!/\.write_(?:text|bytes)\s*\(/.test(src), 'hsf/build_seed.py still writes a file');
  assert.ok(!/\bopen\s*\([^)]*['"]w/.test(src), 'hsf/build_seed.py still opens a file for writing');
});

test('the frozen check passes and leaves 048 byte for byte as it was', () => {
  const before = sha(SEED);
  const r = run([]);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /048_hsf_library_seed\.sql unchanged \(frozen, applied to live\)/);
  assert.equal(sha(SEED), before);
  const again = run(['--check']);
  assert.equal(again.status, 0, again.stderr);
  assert.equal(sha(SEED), before);
});

test('every element change since 048 is printed by --delta and carried by a later migration', () => {
  const r = run(['--delta']);
  assert.equal(r.status, 0, r.stderr);
  const flat = (t) => t.replace(/\s+/g, ' ').trim();
  const later = fs.readdirSync(MIG).filter((f) => /^\d{3}_.*\.sql$/.test(f) && Number(f.slice(0, 3)) > 48)
    .map((f) => flat(fs.readFileSync(path.join(MIG, f), 'utf8'))).join(' ');
  const stmts = r.stdout.split(/\n-- element [^\n]+\n/).slice(1);
  assert.ok(stmts.length >= 1, 'expected at least the HSF-E-01 rename');
  assert.match(r.stdout, /-- element HSF-E-01\nupdate hsf_element\n {3}set name = 'The signed Medical Surveillance Plan, a separate Care Net product signed by the OMP, filed as evidence'/);
  for (const s of stmts) assert.ok(later.includes(flat(s)), 'not carried by a migration after 048:\n' + s);
});

test('a changed 048 is refused and is not rewritten', () => {
  const dir = copyMigrations();
  try {
    const p = path.join(dir, '048_hsf_library_seed.sql');
    fs.appendFileSync(p, '\n-- edited by hand\n');
    const before = sha(p);
    const r = run(['--migrations', dir]);
    assert.equal(r.status, 1, r.stdout + r.stderr);
    assert.match(r.stderr, /FROZEN: .*048_hsf_library_seed\.sql is not the file applied to the live project/);
    assert.equal(sha(p), before, 'the generator rewrote 048');
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('an element change no later migration carries fails the check', () => {
  const dir = copyMigrations();
  try {
    fs.rmSync(path.join(dir, '056_hsf_file_naming.sql'), { force: true });
    const r = run(['--migrations', dir]);
    assert.equal(r.status, 1, r.stdout + r.stderr);
    assert.match(r.stderr, /not in any migration after 048_hsf_library_seed\.sql: the update for element HSF-E-01/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
