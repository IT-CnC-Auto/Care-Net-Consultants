// CNC HSF FORGE | tests for vercel/api/hsf-staff.js (node --test, global fetch mocked)
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const SUPABASE_URL = 'https://unit-test.supabase.invalid';
const SERVICE_KEY = 'svc-role-key-UNIT-TEST-must-never-appear-0123456789';
process.env.SUPABASE_URL = SUPABASE_URL;
process.env.SUPABASE_SERVICE_ROLE_KEY = SERVICE_KEY;
const REAL_FETCH = globalThis.fetch;

const USER_ID = '6f1c2d3e-4a5b-4c6d-8e7f-9a0b1c2d3e4f';
const ACCOUNT_ID = '0b9a8c7d-6e5f-4a3b-9c2d-1e0f9a8b7c6d';
const FILE_ID = '3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e6f';
const UPLOAD_ID = '9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b';
const SIGNATORY_ID = '5a6b7c8d-9e0f-4a1b-8c2d-3e4f5a6b7c8d';
const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1bml0In0.c2lnbmF0dXJlLXVuaXQ';
const AUTH = { authorization: `Bearer ${TOKEN}` };

const handler = require('../../vercel/api/hsf-staff');

const logged = [];
test.mock.method(console, 'error', (...a) => { logged.push(a.map(String).join(' ')); });
test.after(() => {
  for (const line of logged) assert.ok(!line.includes(SERVICE_KEY), 'a log line carries the service role key');
});

function json(status, body) {
  return new Response(body === undefined ? null : JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

// A PostgREST error body, as lib/db.js rpc() receives it.
function pgError(code, message, status = 400) {
  return json(status, { code, message, details: null, hint: null });
}

function installFetch(t, fn) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    const i = init || {};
    const c = { url: String(url), method: (i.method || 'GET').toUpperCase(), headers: Object.assign({}, i.headers), body: i.body };
    calls.push(c);
    return fn(c);
  };
  t.after(() => { globalThis.fetch = REAL_FETCH; });
  return calls;
}

// A fake Supabase: Auth answers for TOKEN only; the account link and the staff
// check answer by default (staff unless told otherwise); rpc functions from the map.
function supabase(t, rpcs, { staff = true } = {}) {
  return installFetch(t, c => {
    if (c.url === `${SUPABASE_URL}/auth/v1/user`) {
      return c.headers.Authorization === `Bearer ${TOKEN}`
        ? json(200, { id: USER_ID, email: 'staff@carenet.example' })
        : json(401, { msg: 'invalid JWT' });
    }
    const m = /\/rest\/v1\/rpc\/([a-z0-9_]+)$/.exec(c.url);
    if (m && c.url.startsWith(`${SUPABASE_URL}/rest/v1/rpc/`)) {
      assert.equal(c.method, 'POST');
      assert.equal(c.headers.apikey, SERVICE_KEY);
      assert.equal(c.headers.Authorization, `Bearer ${SERVICE_KEY}`);
      if (m[1] === 'hsf_link_account' && !rpcs.hsf_link_account) return json(200, null);
      if (m[1] === 'hsf_user_is_staff' && !rpcs.hsf_user_is_staff) {
        assert.deepEqual(JSON.parse(c.body), { p_auth_user: USER_ID });
        return json(200, staff);
      }
      const fn = rpcs[m[1]];
      if (!fn) throw new Error(`unexpected rpc ${m[1]}`);
      const out = fn(JSON.parse(c.body));
      return out instanceof Response ? out : json(200, out);
    }
    throw new Error(`unexpected fetch ${c.method} ${c.url}`);
  });
}

function mockRes() {
  const res = { statusCode: 200, headers: {}, body: undefined };
  res.setHeader = (k, v) => { res.headers[String(k).toLowerCase()] = v; };
  res.getHeader = k => res.headers[String(k).toLowerCase()];
  res.status = c => { res.statusCode = c; return res; };
  res.json = o => { res.body = o; return res; };
  res.end = () => res;
  return res;
}

function assertSafe(res) {
  const s = JSON.stringify(res.body === undefined ? null : res.body) + JSON.stringify(res.headers);
  assert.ok(!s.includes(SERVICE_KEY), 'response carries the service role key');
  assert.ok(!/\bat [^\s]+ \(?[^\s)]*:\d+:\d+\)?/.test(s), 'response carries a stack trace');
  assert.ok(!/"stack"/.test(s), 'response carries a stack property');
}

async function call({ method = 'GET', headers = AUTH, query = {}, body } = {}) {
  const res = mockRes();
  await handler({ method, headers, query, body }, res);
  assertSafe(res);
  assert.equal(res.headers['cache-control'], 'no-store');
  return res;
}

// Console calls made by the handler itself (the account link and the staff check are counted apart).
const consoleCalls = calls => calls.filter(c => c.url.includes('/rest/v1/rpc/')
  && !c.url.endsWith('/rpc/hsf_link_account') && !c.url.endsWith('/rpc/hsf_user_is_staff'));
const staffChecks = calls => calls.filter(c => c.url.endsWith('/rpc/hsf_user_is_staff'));

test('401 without a token, and no database call', async t => {
  const calls = supabase(t, {});
  for (const method of ['GET', 'POST']) {
    const res = await call({ method, headers: {}, query: { view: 'files' }, body: { action: 'scan_reset', upload_id: UPLOAD_ID } });
    assert.equal(res.statusCode, 401, method);
    assert.equal(res.body.code, 'sign_in_required');
  }
  assert.equal(calls.length, 0);
});

test('405 for other methods, with Allow, before any sign in check', async t => {
  const calls = supabase(t, {});
  for (const method of ['PUT', 'DELETE', 'PATCH']) {
    const res = await call({ method });
    assert.equal(res.statusCode, 405);
    assert.equal(res.headers.allow, 'GET, POST');
  }
  assert.equal(calls.length, 0);
});

test('403 for a signed in person without a staff role: no console function runs, and no role name is shown', async t => {
  const calls = supabase(t, {}, { staff: false });
  const reqs = [
    { query: { view: 'verification' } },
    { query: { view: 'readiness', file_id: FILE_ID } },
    { method: 'POST', body: { action: 'verify_client', client_account_id: ACCOUNT_ID, method: 'client_register', evidence_ref: 'CR 1042' } },
    { method: 'POST', body: { action: 'scan_reset', upload_id: 'not-a-uuid' } },
    { method: 'POST', body: { action: 'nonsense' } },
  ];
  for (const r of reqs) {
    const res = await call(r);
    assert.equal(res.statusCode, 403);
    assert.equal(res.body.code, 'forbidden');
    assert.match(res.body.error, /Care Net staff/);
    assert.ok(!/forge_/.test(res.body.error), 'a role name reached the page');
  }
  assert.equal(staffChecks(calls).length, reqs.length);
  assert.equal(consoleCalls(calls).length, 0);
});

test('403 when the staff check answers anything but true', async t => {
  for (const answer of [null, 'true', 1, {}]) {
    await t.test(`answer ${JSON.stringify(answer)}`, async t2 => {
      const calls = supabase(t2, { hsf_user_is_staff: () => json(200, answer) });
      const res = await call({ query: { view: 'files' } });
      assert.equal(res.statusCode, 403);
      assert.equal(consoleCalls(calls).length, 0);
    });
  }
});

test('a staff role removed between the API check and the database check (42501) is a 403', async t => {
  supabase(t, { hsf_staff_file_list: () => pgError('42501', 'This needs a Care Net staff role.', 403) });
  const res = await call({ query: { view: 'files' } });
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.code, 'forbidden');
});

test('each list view calls its console function with the verified user only', async t => {
  const views = {
    verification: ['hsf_staff_verification_list', [{ client_account_id: ACCOUNT_ID, status: 'requested' }]],
    signatories: ['hsf_staff_signatory_list', [{ id: SIGNATORY_ID, full_name: 'N. Dlamini' }]],
    signatory_alerts: ['hsf_staff_signatory_alerts', [{ signatory_id: SIGNATORY_ID, days_to_expiry: 12 }]],
    files: ['hsf_staff_file_list', [{ file_id: FILE_ID, readiness: { ready: false, missing: ['x'] } }]],
  };
  for (const [view, [fn, rows]] of Object.entries(views)) {
    await t.test(view, async t2 => {
      const seen = [];
      const calls = supabase(t2, { [fn]: a => { seen.push(a); return rows; } });
      const res = await call({ query: { view, user_id: 'someone-else' } });
      assert.equal(res.statusCode, 200);
      assert.deepEqual(res.body, rows);
      assert.deepEqual(seen, [{ p_auth_user: USER_ID }]);
      assert.equal(consoleCalls(calls).length, 1);
    });
  }
});

test('a list the database answers with null reads as an empty list', async t => {
  supabase(t, { hsf_staff_verification_list: () => null });
  const res = await call({ query: { view: 'verification' } });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, []);
});

test('the scans view always answers {scans, staging_alerts}', async t => {
  await t.test('as the database gives it', async t2 => {
    const out = { scans: [{ upload_id: UPLOAD_ID, scan_exhausted: true }], staging_alerts: [{ upload_id: UPLOAD_ID, expires_on: '2028-09-01' }] };
    supabase(t2, { hsf_staff_scan_list: () => out });
    const res = await call({ query: { view: 'scans' } });
    assert.deepEqual(res.body, out);
  });
  await t.test('an odd shape becomes two empty lists', async t2 => {
    supabase(t2, { hsf_staff_scan_list: () => ({ scans: 'x' }) });
    const res = await call({ query: { view: 'scans' } });
    assert.deepEqual(res.body, { scans: [], staging_alerts: [] });
  });
});

test('an unknown or missing view is a 400 after the staff check, with no console call', async t => {
  const calls = supabase(t, {});
  for (const q of [{}, { view: 'everything' }, { view: 'hsf_staff_file_list' }]) {
    const res = await call({ query: q });
    assert.equal(res.statusCode, 400);
    assert.match(res.body.error, /Unknown view/);
  }
  const res = await call({ query: { view: ['files', 'scans'] } });
  assert.equal(res.statusCode, 400);
  assert.equal(consoleCalls(calls).length, 0);
});

test('readiness: file and revision go to hsf_release_readiness, which writes nothing', async t => {
  const seen = [];
  supabase(t, { hsf_release_readiness: a => { seen.push(a); return { file_id: FILE_ID, revision: a.p_revision || 2, ready: false, missing: ['No approved safety content sign off.'] }; } });
  let res = await call({ query: { view: 'readiness', file_id: FILE_ID.toUpperCase(), revision: '2' } });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ready, false);
  res = await call({ query: { view: 'readiness', file_id: FILE_ID } });
  assert.equal(res.statusCode, 200);
  assert.deepEqual(seen, [{ p_file_id: FILE_ID, p_revision: 2 }, { p_file_id: FILE_ID, p_revision: null }]);
});

test('readiness: a bad File id or revision is a 400 with no call; a missing File is a 404', async t => {
  const calls = supabase(t, { hsf_release_readiness: () => pgError('P0002', 'That File was not found.') });
  for (const q of [{ view: 'readiness' }, { view: 'readiness', file_id: 'abc' }, { view: 'readiness', file_id: FILE_ID, revision: '0' }, { view: 'readiness', file_id: FILE_ID, revision: '1.5' }]) {
    const res = await call({ query: q });
    assert.equal(res.statusCode, 400, JSON.stringify(q));
  }
  assert.equal(consoleCalls(calls).length, 0);
  const res = await call({ query: { view: 'readiness', file_id: FILE_ID } });
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error, 'That File was not found.');
});

test('verify_client: the account, method and evidence go through; the database names the actor', async t => {
  const seen = [];
  supabase(t, { hsf_staff_verify_client: a => { seen.push(a); return { client_account_id: ACCOUNT_ID, status: 'verified', verified_by: 'staff@carenet.example' }; } });
  const res = await call({ method: 'POST', body: { action: 'verify_client', client_account_id: ACCOUNT_ID, method: 'client_register', evidence_ref: '  CR  1042\n', verified_by: 'someone else' } });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.status, 'verified');
  assert.deepEqual(seen, [{ p_auth_user: USER_ID, p_client_account_id: ACCOUNT_ID, p_method: 'client_register', p_evidence_ref: 'CR 1042' }]);
});

test('verify_client: refusals in plain words, before any console call', async t => {
  const calls = supabase(t, {});
  const bad = [
    [{ client_account_id: 'x', method: 'client_register', evidence_ref: 'CR 1' }, /company account/],
    [{ client_account_id: ACCOUNT_ID, method: 'phoned them', evidence_ref: 'CR 1' }, /Choose how the company was verified/],
    [{ client_account_id: ACCOUNT_ID, method: 'client_register', evidence_ref: '   ' }, /Record what the verification rests on/],
    [{ client_account_id: ACCOUNT_ID, method: 'client_register' }, /Record what the verification rests on/],
    [{ client_account_id: ACCOUNT_ID, method: 'client_register', evidence_ref: 'x'.repeat(201) }, /at most 200/],
    [{ client_account_id: ACCOUNT_ID, method: 'client_register', evidence_ref: 'ID 8001015009087' }, /identity number/],
  ];
  for (const [b, re] of bad) {
    const res = await call({ method: 'POST', body: { action: 'verify_client', ...b } });
    assert.equal(res.statusCode, 400);
    assert.match(res.body.error, re);
  }
  assert.equal(consoleCalls(calls).length, 0);
});

test('verify_client: the database refusal reaches the page in its own words; a missing account is a 404', async t => {
  await t.test('declined', async t2 => {
    supabase(t2, { hsf_staff_verify_client: () => pgError('P0001', 'A declined company account cannot be verified.') });
    const res = await call({ method: 'POST', body: { action: 'verify_client', client_account_id: ACCOUNT_ID, method: 'sales_executive', evidence_ref: 'Call note 14/09/2026' } });
    assert.equal(res.statusCode, 400);
    assert.equal(res.body.error, 'A declined company account cannot be verified.');
    assert.equal(res.body.code, 'refused');
  });
  await t.test('missing', async t2 => {
    supabase(t2, { hsf_staff_verify_client: () => pgError('P0002', 'That company account was not found.') });
    const res = await call({ method: 'POST', body: { action: 'verify_client', client_account_id: ACCOUNT_ID, method: 'sales_executive', evidence_ref: 'Call note' } });
    assert.equal(res.statusCode, 404);
    assert.equal(res.body.error, 'That company account was not found.');
  });
});

test('revoke_client: a reason is required; the database refusal passes through', async t => {
  const seen = [];
  const calls = supabase(t, {
    hsf_staff_revoke_client: a => {
      seen.push(a);
      return a.p_reason === 'Not verified' ? pgError('P0001', 'That company account is not verified.') : { client_account_id: ACCOUNT_ID, status: 'revoked' };
    },
  });
  let res = await call({ method: 'POST', body: { action: 'revoke_client', client_account_id: ACCOUNT_ID, reason: ' ' } });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /reason/);
  assert.equal(consoleCalls(calls).length, 0);
  res = await call({ method: 'POST', body: { action: 'revoke_client', client_account_id: ACCOUNT_ID, reason: 'The client register shows the contract ended on 31/08/2026.' } });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.status, 'revoked');
  res = await call({ method: 'POST', body: { action: 'revoke_client', client_account_id: ACCOUNT_ID, reason: 'Not verified' } });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'That company account is not verified.');
  assert.deepEqual(seen[0], { p_auth_user: USER_ID, p_client_account_id: ACCOUNT_ID, p_reason: 'The client register shows the contract ended on 31/08/2026.' });
});

test('scan_reset: the upload goes through; a bad id is a 400, a missing upload a 404, a refusal its own words', async t => {
  const seen = [];
  const other = '11111111-2222-4333-8444-555555555555';
  const calls = supabase(t, {
    hsf_staff_scan_reset: a => {
      seen.push(a);
      if (a.p_upload_id === other) return pgError('P0002', 'That upload was not found.');
      if (seen.length === 3) return pgError('P0001', 'Only an uploaded document still waiting for its security scan can be scanned again (status held, scan clean).');
      return { upload_id: a.p_upload_id, scan_status: 'error', scan_attempts: 0 };
    },
  });
  let res = await call({ method: 'POST', body: { action: 'scan_reset', upload_id: 'nope' } });
  assert.equal(res.statusCode, 400);
  assert.equal(consoleCalls(calls).length, 0);
  res = await call({ method: 'POST', body: { action: 'scan_reset', upload_id: UPLOAD_ID } });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.scan_attempts, 0);
  res = await call({ method: 'POST', body: { action: 'scan_reset', upload_id: other } });
  assert.equal(res.statusCode, 404);
  res = await call({ method: 'POST', body: { action: 'scan_reset', upload_id: UPLOAD_ID } });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /^Only an uploaded document/);
  assert.deepEqual(seen[0], { p_auth_user: USER_ID, p_upload_id: UPLOAD_ID });
});

test('signatory_save: only the 053 fields go through, empty values as null, the actor never from the body', async t => {
  const seen = [];
  supabase(t, { hsf_staff_signatory_save: a => { seen.push(a); return Object.assign({ id: SIGNATORY_ID, action: 'created' }, a.p); } });
  const res = await call({
    method: 'POST',
    body: {
      action: 'signatory_save',
      signatory: {
        full_name: ' Nomsa  Dlamini ', registration_body: 'SACPCMP', category: 'CHSM', registration_number: 'CHSM/123/2024',
        registration_expires_on: '2027-03-31', register_checked_on: '2026-09-20', register_proof_ref: 'REG-PROOF-0921',
        appointment_letter_ref: 'APPT-77', appointment_letter_date: '2026-09-01', appointment_letter_recruitment_portal_ref: '',
        engagement_letter_ref: '', engagement_letter_date: null,
        created_by: 'someone else', frozen: false, id: '',
      },
    },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.action, 'created');
  assert.deepEqual(seen, [{
    p_auth_user: USER_ID,
    p: {
      full_name: 'Nomsa Dlamini', registration_body: 'SACPCMP', category: 'CHSM', registration_number: 'CHSM/123/2024',
      register_proof_ref: 'REG-PROOF-0921', appointment_letter_ref: 'APPT-77', appointment_letter_recruitment_portal_ref: null,
      engagement_letter_ref: null, engagement_letter_recruitment_portal_ref: null,
      registration_expires_on: '2027-03-31', register_checked_on: '2026-09-20', appointment_letter_date: '2026-09-01', engagement_letter_date: null,
    },
  }]);
});

test('signatory_save: a correction carries the id; shape errors are 400; the 053 freeze and a missing record come from the database', async t => {
  const seen = [];
  const calls = supabase(t, {
    hsf_staff_signatory_save: a => {
      seen.push(a);
      if (a.p.full_name === 'Frozen') return pgError('P0001', 'These credentials support a released File and cannot be changed. Record a renewal or a correction as a new signatory.');
      return pgError('P0002', 'That signatory was not found.');
    },
  });
  const bad = [
    [{ signatory: 'x' }, /signatory details/],
    [{}, /signatory details/],
    [{ signatory: { id: 'abc', full_name: 'A' } }, /signatory/],
    [{ signatory: { full_name: 'A', registration_expires_on: '31/03/2027' } }, /YYYY-MM-DD/],
    [{ signatory: { full_name: 'A', registration_number: '8001015009087' } }, /identity number/],
    [{ signatory: { full_name: 'x'.repeat(201) } }, /at most 200/],
  ];
  for (const [b, re] of bad) {
    const res = await call({ method: 'POST', body: { action: 'signatory_save', ...b } });
    assert.equal(res.statusCode, 400, JSON.stringify(b));
    assert.match(res.body.error, re);
  }
  assert.equal(consoleCalls(calls).length, 0);
  let res = await call({ method: 'POST', body: { action: 'signatory_save', signatory: { id: SIGNATORY_ID, full_name: 'Frozen' } } });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /support a released File/);
  assert.equal(seen[0].p.id, SIGNATORY_ID);
  res = await call({ method: 'POST', body: { action: 'signatory_save', signatory: { id: SIGNATORY_ID, full_name: 'Gone' } } });
  assert.equal(res.statusCode, 404);
  assert.equal(res.body.error, 'That signatory was not found.');
});

test('signoff_record: a safety content decision goes through with its signatory, scope and time', async t => {
  const seen = [];
  supabase(t, {
    hsf_staff_signoff_record: a => {
      seen.push(a);
      return { signoff_id: '77777777-8888-4999-8aaa-bbbbbbbbbbbb', file_id: FILE_ID, revision: 1, kind: a.p.kind, decision: a.p.decision, recorded_by: 'staff@carenet.example', signatory_fit: null, readiness: { ready: false, missing: ['The client’s section 16(2) acceptance is not approved for this revision.'] } };
    },
  });
  const res = await call({
    method: 'POST',
    body: {
      action: 'signoff_record',
      signoff: {
        file_id: FILE_ID, revision: '1', kind: 'safety_content', decision: 'approved', signatory_id: SIGNATORY_ID,
        scope: 'Sections A to O, construction File revision 1', decided_at: '2026-09-22T10:30+02:00', recorded_by: 'someone else',
      },
    },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.readiness.ready, false);
  assert.deepEqual(seen, [{
    p_auth_user: USER_ID,
    p: { file_id: FILE_ID, revision: 1, kind: 'safety_content', decision: 'approved', scope: 'Sections A to O, construction File revision 1', signatory_id: SIGNATORY_ID, decided_at: '2026-09-22T10:30+02:00' },
  }]);
});

test('signoff_record: shape errors are 400; the OMP refusal and the other rules come from the database', async t => {
  const calls = supabase(t, {
    hsf_staff_signoff_record: a => (a.p.kind === 'omp_medical'
      ? pgError('P0001', 'The Occupational Medical Practitioner does not sign a File. File the signed medical surveillance plan in Section E as evidence instead.')
      : pgError('P0001', 'The reference of the signed acceptance document is required.')),
  });
  const bad = [
    [{}, /sign off details/],
    [{ signoff: { kind: 'safety_content', decided_at: '2026-09-22T10:30+02:00' } }, /The File/],
    [{ signoff: { file_id: FILE_ID, kind: 'client_16_2_acceptance' } }, /date of the decision is required/],
    [{ signoff: { file_id: FILE_ID, kind: 'client_16_2_acceptance', decided_at: '22/09/2026' } }, /date and time/],
    [{ signoff: { file_id: FILE_ID, revision: 0, decided_at: '2026-09-22T10:30Z' } }, /revision/],
    [{ signoff: { file_id: FILE_ID, signatory_id: 'x', decided_at: '2026-09-22T10:30Z' } }, /signatory/],
  ];
  for (const [b, re] of bad) {
    const res = await call({ method: 'POST', body: { action: 'signoff_record', ...b } });
    assert.equal(res.statusCode, 400, JSON.stringify(b));
    assert.match(res.body.error, re);
  }
  assert.equal(consoleCalls(calls).length, 0);
  let res = await call({ method: 'POST', body: { action: 'signoff_record', signoff: { file_id: FILE_ID, kind: 'omp_medical', decision: 'approved', decided_at: '2026-09-22T10:30:00Z' } } });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /^The Occupational Medical Practitioner does not sign a File/);
  res = await call({ method: 'POST', body: { action: 'signoff_record', signoff: { file_id: FILE_ID, kind: 'client_16_2_acceptance', decision: 'approved', signatory_name: 'T. Mokoena', decided_at: '2026-09-22T10:30:00Z' } } });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /signed acceptance document/);
});

test('an unknown action, or a body that is not an object, is a 400 after the staff check', async t => {
  const calls = supabase(t, {});
  let res = await call({ method: 'POST', body: { action: 'release' } });
  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /Unknown action/);
  res = await call({ method: 'POST', body: '[1,2]' });
  assert.equal(res.statusCode, 400);
  res = await call({ method: 'POST', body: '{not json' });
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.code, 'bad_json');
  assert.equal(consoleCalls(calls).length, 0);
});

test('a database fault is a plain 500 with no detail, logged without the key', async t => {
  supabase(t, { hsf_staff_scan_list: () => json(500, { code: 'XX000', message: `internal: key ${SERVICE_KEY}` }) });
  const res = await call({ query: { view: 'scans' } });
  assert.equal(res.statusCode, 500);
  assert.ok(!JSON.stringify(res.body).includes('internal'));
});
