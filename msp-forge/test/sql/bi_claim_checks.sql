-- CNC HSF FORGE | BI-OPS-01, Bee-Inspect claim code checks | local test harness only.
-- Proves the claim code of migration 063 (hsf/BEE-INSPECT-BUILD-PROMPT.md B3): only
-- the SHA 256 of the code is stored, it expires 10 minutes after it is made, it is
-- redeemed once, creation and redemption are rate limited, the conversion events
-- are recorded (and mirrored to the banner funnel of 057 when the banner is
-- known), and nothing is open to a client. Loads the fictitious seed. Rolled back.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/bi_claim_checks.sql

\set ON_ERROR_STOP 1
\pset pager off
\pset tuples_only on
begin;

create function pg_temp.ok(p_name text, p_cond boolean) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'CHECK FAILED: %', p_name;
  end if;
  raise notice 'ok   %', p_name;
end $$;

create function pg_temp.refuses(p_name text, p_sql text, p_pattern text) returns void language plpgsql as $$
declare
  v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_msg := sqlerrm;
    if v_msg ~* p_pattern then
      raise notice 'ok   %', p_name;
      return;
    end if;
    raise exception 'CHECK FAILED: % (refused with "%", expected /%/)', p_name, v_msg, p_pattern;
  end;
  raise exception 'CHECK FAILED: % (not refused)', p_name;
end $$;

-- The same hash as supabase/functions/_shared/bi/claim-code.js hashCode: SHA 256 hex of the upper case code.
create function pg_temp.h(p_code text) returns text language sql as $$ select encode(extensions.digest(upper(p_code), 'sha256'), 'hex') $$;

\ir ../../supabase/seed/bee_inspect_demo.sql

\set admin '''b1a00000-0000-4000-8000-000000000013'''
select id as file from hsf_file where client_account_id = 'b1a00000-0000-4000-8000-000000000002' \gset

select pg_temp.ok('the claim code table holds a hash, never the code',
  not exists (select 1 from information_schema.columns where table_name = 'bi_claim_code' and column_name in ('code','plain_code'))
  and exists (select 1 from information_schema.columns where table_name = 'bi_claim_code' and column_name = 'code_hash'));
select pg_temp.ok('no client role can read or write claim codes or call the claim functions',
  not has_table_privilege('authenticated', 'bi_claim_code', 'select') and not has_table_privilege('anon', 'bi_claim_code', 'select')
  and not has_function_privilege('authenticated', 'bi_claim_code_create(uuid, text, jsonb)', 'execute')
  and not has_function_privilege('anon', 'bi_claim_code_redeem(text, jsonb)', 'execute'));

select bi_claim_code_create(:admin, pg_temp.h('K7M2QX9A'), jsonb_build_object('file_id', :'file', 'ad_id', 'AD-01', 'page', '/hsf-builder',
         'utm_source', 'hsf_builder', 'utm_medium', 'in_product_banner', 'utm_campaign', 'bee_inspect_addon', 'utm_content', 'AD-01_gaps')) as c1 \gset
select pg_temp.ok('a code is made for the signed in File contact and expires in 10 minutes',
  (select expires_at - created_at = interval '10 minutes' and client_account_id = 'b1a00000-0000-4000-8000-000000000002' and file_id = :'file'
     from bi_claim_code where id = (:'c1'::jsonb ->> 'claim_id')::uuid));
select pg_temp.ok('claim_code_created is recorded with its campaign tags',
  exists (select 1 from bi_attribution where event = 'claim_code_created' and ad_id = 'AD-01' and utm_content = 'AD-01_gaps'));
select pg_temp.ok('and mirrored, without the person, to the banner funnel (hsf_ad_event)',
  exists (select 1 from hsf_ad_event where event = 'claim_code_created' and ad_id = 'AD-01' and page = '/hsf-builder'));

select pg_temp.ok('a wrong code is invalid', bi_claim_code_redeem(pg_temp.h('WRONG999'), '{"caller_key":"phone-a"}') @> '{"ok": false, "reason": "invalid"}');
select pg_temp.ok('a malformed hash is invalid', bi_claim_code_redeem('not-a-hash', '{"caller_key":"phone-a"}') @> '{"ok": false, "reason": "invalid"}');
select bi_claim_code_redeem(pg_temp.h('k7m2qx9a'), '{"caller_key":"phone-a","device":"Demo phone (fictitious)"}') as r1 \gset
select pg_temp.ok('the right code (any case) signs the phone in to the same account and File',
  :'r1'::jsonb @> jsonb_build_object('ok', true, 'auth_user_id', 'b1a00000-0000-4000-8000-000000000013', 'email', 'naledi.admin.demo@example.invalid',
                                      'client_account_id', 'b1a00000-0000-4000-8000-000000000002', 'file_id', :'file'));
select pg_temp.ok('a code is single use', bi_claim_code_redeem(pg_temp.h('K7M2QX9A'), '{"caller_key":"phone-b"}') @> '{"ok": false, "reason": "used"}');
select pg_temp.ok('claim_code_scanned is recorded', exists (select 1 from bi_attribution where event = 'claim_code_scanned'));
select pg_temp.refuses('a redeemed code never changes', $q$update bi_claim_code set redeemed_at = now() where code_hash = pg_temp.h('K7M2QX9A')$q$, 'redeemed once');
select pg_temp.refuses('a claim code is never deleted', $q$delete from bi_claim_code$q$, 'never deleted');

insert into bi_claim_code (code_hash, auth_user_id, created_at, expires_at)
values (pg_temp.h('OLD2CODE'), :admin, now() - interval '20 minutes', now() - interval '10 minutes');
select pg_temp.ok('a code older than 10 minutes is expired', bi_claim_code_redeem(pg_temp.h('OLD2CODE'), '{"caller_key":"phone-c"}') @> '{"ok": false, "reason": "expired"}');
select pg_temp.refuses('a code cannot be made to live longer than 10 minutes',
  $q$insert into bi_claim_code (code_hash, auth_user_id, expires_at) values (pg_temp.h('LONG2LIVE'), 'b1a00000-0000-4000-8000-000000000013', now() + interval '11 minutes')$q$, 'bi_claim_code_ten_minutes');
select pg_temp.refuses('a hash must be SHA 256 hex', $q$select bi_claim_code_create('b1a00000-0000-4000-8000-000000000013', 'K7M2QX9A')$q$, 'SHA 256');
select pg_temp.refuses('a File of another company cannot be named',
  $q$select bi_claim_code_create('b1a00000-0000-4000-8000-000000000011', pg_temp.h('OTHERF1L'), jsonb_build_object('file_id', '$q$ || :'file' || $q$'))$q$, 'File was not found');

-- Rate limits: at most 5 codes per person in 10 minutes (one made above, one refused above did not count).
select bi_claim_code_create(:admin, pg_temp.h('RATE0002')) is not null as a2 \gset
select bi_claim_code_create(:admin, pg_temp.h('RATE0003')) is not null as a3 \gset
select bi_claim_code_create(:admin, pg_temp.h('RATE0004')) is not null as a4 \gset
select bi_claim_code_create(:admin, pg_temp.h('RATE0005')) is not null as a5 \gset
select pg_temp.refuses('the sixth code within 10 minutes is refused', $q$select bi_claim_code_create('b1a00000-0000-4000-8000-000000000013', pg_temp.h('RATE0006'))$q$, 'Too many claim codes');
select pg_temp.ok('redeem attempts are limited to 10 per caller in 10 minutes',
  (select count(*) from generate_series(1, 8) g where (bi_claim_code_redeem(pg_temp.h('GUESS' || g), '{"caller_key":"phone-a"}') ->> 'reason') = 'invalid') = 7);
select pg_temp.ok('the eleventh attempt from the same caller answers rate', bi_claim_code_redeem(pg_temp.h('RATE0002'), '{"caller_key":"phone-a"}') @> '{"reason": "rate"}');
select pg_temp.ok('another caller is not held up', bi_claim_code_redeem(pg_temp.h('RATE0002'), '{"caller_key":"phone-z"}') @> '{"ok": true}');
select pg_temp.ok('rate limit keys are stored hashed, never as given',
  not exists (select 1 from bi_rate_event where key_hash in ('phone-a','phone-z')) and (select count(*) from bi_rate_event where bucket = 'claim_redeem') > 0);

do $$ begin raise notice 'bi_claim_checks: all checks passed. Rolling back the test data.'; end $$;
rollback;
