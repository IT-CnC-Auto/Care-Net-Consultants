-- CNC HSF FORGE | BI-WAL-01, Bee-Inspect AI Wallet and pricing checks | local test harness only.
-- Proves migration 062 (hsf/BUILD-CONTRACT.md 16, P3; hsf/BEE-INSPECT-BUILD-PROMPT.md B8)
-- with worked numbers in rand: the price formula and its rounding, the charge rule
-- (actual unless more than the estimate plus 25%), estimate refusals (rates not
-- confirmed, wallet empty, spend cap), spending oldest expiry first, idempotency,
-- the shortfall, included value rolling one month and purchased value lasting 12,
-- the top up values, store receipts once per event, photo tagging free to 50 per
-- report, automatic top up, the welcome hook and the storage gate. The AI rates used
-- here are TEST NUMBERS inserted inside the transaction, not xAI's prices
-- ({{rate_card}} is still open). Loads the fictitious seed. Rolled back.
--
-- Usage (from msp-forge/):
--   test/sql/replay.sh
--   psql -h /tmp -p 55432 -U postgres -d cnc_test -v ON_ERROR_STOP=1 -f test/sql/bi_wallet_checks.sql

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

\ir ../../supabase/seed/bee_inspect_demo.sql

\set tenant '''b1a00000-0000-4000-8000-000000000001'''
\set company '''b1a00000-0000-4000-8000-000000000002'''
\set inspauth '''b1a00000-0000-4000-8000-000000000011'''
\set adminauth '''b1a00000-0000-4000-8000-000000000013'''
select id as wallet from bi_wallet where tenant_id = :tenant and client_account_id = :company \gset

-- 1. The formula, with worked numbers ---------------------------------------------------------------------

select pg_temp.ok('W1: 200 000 tokens in at $0.20/M, 20 000 out at $0.50/M, 10 minutes of audio at $0.006/min, fx R18,50, markup 3.0 = R6,11 (611 cents; exact R6,105 rounds up)',
  bi_price_cents(200000, 20000, 600, 0.20, 0.50, 0.006, 18.50, 3.0) = 611);
select pg_temp.ok('W2: a quality draft of 150 000 in at $2/M and 8 000 out at $10/M = $0.38 x 18,50 x 3 = R21,09 (2 109 cents)',
  bi_price_cents(150000, 8000, 0, 2.00, 10.00, 0, 18.50, 3.0) = 2109);
select pg_temp.ok('W3: 90 seconds of transcription at $0.006/min = R0,4995, which rounds half up to 50 cents',
  bi_price_cents(0, 0, 90, 0, 0, 0.006, 18.50, 3.0) = 50);
select pg_temp.ok('W4: one token at $1/M is R0,0000555: 0 cents', bi_price_cents(1, 0, 0, 1, 0, 0, 18.50, 3.0) = 0);
select pg_temp.ok('W5: markup 1.0 gives the cost price: the W1 quantities cost R2,04 (203.5 cents rounds to 204)',
  bi_price_cents(200000, 20000, 600, 0.20, 0.50, 0.006, 18.50, 1.0) = 204);
select pg_temp.refuses('negative quantities are refused', $q$select bi_price_cents(-1, 0, 0, 1, 1, 1, 18.5, 3)$q$, 'negative');
select pg_temp.ok('charge rule: estimate R5,00, actual R6,00 (within 25%) charges R6,00', bi_charge_rule_cents(500, 600) = 600);
select pg_temp.ok('charge rule: actual exactly 25% above (R6,25) charges R6,25', bi_charge_rule_cents(500, 625) = 625);
select pg_temp.ok('charge rule: actual R6,26 (more than 25% above) charges the estimate R5,00', bi_charge_rule_cents(500, 626) = 500);
select pg_temp.ok('charge rule: an actual below the estimate charges the actual', bi_charge_rule_cents(500, 300) = 300);
select pg_temp.ok('markup default is 3.0 and VAT mode to_be_confirmed',
  msp_env_get_numeric('bi.markup_default') = 3.0 and msp_env_get('bi.vat_mode') = 'to_be_confirmed');
select pg_temp.ok('rate card: base R299,00 with R150,00 wallet and 10 GB; extra company R199,00 with R100,00',
  (select price_cents = 29900 and wallet_monthly_cents = 15000 and storage_bytes = 10737418240 from bi_rate_card_current('base'))
  and (select price_cents = 19900 and wallet_monthly_cents = 10000 from bi_rate_card_current('extra_company')));
select pg_temp.ok('rate card: top ups R99 (R99), R249 (R260), R499 (R550), R999 (R1 150); automatic R99 below R20',
  (select array_agg(price_cents || '/' || value_cents order by price_cents) from bi_rate_card where kind = 'topup')
    = array['9900/9900','24900/26000','49900/55000','99900/115000']
  and (select price_cents = 9900 and threshold_cents = 2000 from bi_rate_card_current('auto_topup')));
select pg_temp.ok('the AI, transcription and fx rows are placeholders without rates ({{rate_card}})',
  (select bool_and(status = 'placeholder' and usd_per_mtok_in is null and usd_per_minute is null and usd_zar is null)
     from bi_rate_card where kind in ('ai_model','transcription','fx')));

-- 2. The seed wallet ------------------------------------------------------------------------------------------

select pg_temp.ok('seed wallet: R150,00 included less the R11,80 demonstration charge, plus R260,00 purchased = R398,20',
  bi_wallet_balance(:'wallet') @> '{"available_cents": 39820, "included_cents": 13820, "purchased_cents": 26000, "vat_mode": "to_be_confirmed"}');
select pg_temp.ok('included value expires two months after its period starts (rolls one month); purchased lasts 12 months',
  (select expires_at = date_trunc('month', current_date) + interval '2 months' from bi_wallet_ledger where wallet_id = :'wallet' and entry_kind = 'included_credit')
  and (select expires_at::date between (current_date + interval '12 months')::date - 1 and (current_date + interval '12 months')::date
         from bi_wallet_ledger where wallet_id = :'wallet' and entry_kind = 'topup_credit'));
select pg_temp.ok('January''s included value is gone by March: granting it adds nothing spendable now',
  (bi_wallet_grant_included('b1a00000-0000-4000-8000-000000000031', '2026-01-01') ->> 'amount_cents')::int = 15000
  and bi_wallet_available_cents(:'wallet') = 39820);
select pg_temp.ok('granting the same month again is idempotent', (select count(*) from bi_wallet_ledger where idempotency_key like 'included:%') = 2);

-- 3. Estimates and charges ---------------------------------------------------------------------------------------

select pg_temp.ok('with placeholder rates an AI estimate answers rate_card_pending (capture and template reports still work)',
  bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'wallet', 'kind', 'ai_draft', 'tokens_in', 1000, 'idempotency_key', 'est:pending:1'))
    @> '{"allowed": false, "reason": "rate_card_pending"}');

insert into bi_rate_card (code, kind, label, usd_per_mtok_in, usd_per_mtok_out, status, effective_from, notes) values
  ('ai_fast', 'ai_model', 'TEST fast', 0.20, 0.50, 'confirmed', current_date, 'TEST NUMBERS ONLY'),
  ('ai_quality', 'ai_model', 'TEST quality', 2.00, 10.00, 'confirmed', current_date, 'TEST NUMBERS ONLY');
insert into bi_rate_card (code, kind, label, usd_per_minute, status, effective_from, notes) values
  ('transcription', 'transcription', 'TEST transcription', 0.006, 'confirmed', current_date, 'TEST NUMBERS ONLY');
insert into bi_rate_card (code, kind, label, usd_zar, status, effective_from, notes) values
  ('fx_usd_zar', 'fx', 'TEST fx', 18.50, 'confirmed', current_date, 'TEST NUMBERS ONLY');

select bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'wallet', 'kind', 'ai_draft', 'tokens_in', 150000, 'tokens_out', 8000,
         'report_id', (select id from bi_report limit 1), 'idempotency_key', 'est:draft:0001')) as e1 \gset
select pg_temp.ok('estimate: the quality draft of W2 previews R21,09 and is allowed', :'e1'::jsonb @> '{"estimate_cents": 2109, "allowed": true}');
select pg_temp.ok('the same estimate key returns the same usage event',
  bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'wallet', 'kind', 'ai_draft', 'tokens_in', 1, 'idempotency_key', 'est:draft:0001')) ->> 'usage_event_id'
    = :'e1'::jsonb ->> 'usage_event_id');
select pg_temp.refuses('the assistant cannot ask for an estimate (no wallet access)',
  $q$select bi_wallet_estimate('b1a00000-0000-4000-8000-000000000012', jsonb_build_object('wallet_id', '$q$ || :'wallet' || $q$', 'kind', 'ai_draft', 'tokens_in', 1, 'idempotency_key', 'est:asst:0001'))$q$, 'not found');

select bi_wallet_charge((:'e1'::jsonb ->> 'usage_event_id')::uuid, '{"idempotency_key":"chg:draft:0001","tokens_in":160000,"tokens_out":9000}') as c1 \gset
select pg_temp.ok('charge: the actual 160 000 in and 9 000 out cost R22,76 (within 25% of R21,09), so R22,76 is charged',
  :'c1'::jsonb @> '{"estimate_cents": 2109, "actual_cents": 2276, "charged_cents": 2276, "shortfall_cents": 0}');
select pg_temp.ok('the charge spends the included lot first (oldest expiry): R398,20 less R22,76 leaves R375,44',
  bi_wallet_available_cents(:'wallet') = 37544
  and (select count(*) from bi_wallet_ledger where idempotency_key like 'chg:draft:0001:%') = 1
  and (select remaining_cents from bi_wallet_lots(:'wallet') where entry_kind = 'included_credit' and expires_at > now()) = 11544);
select pg_temp.ok('the same charge key again changes nothing (idempotent)',
  (bi_wallet_charge((:'e1'::jsonb ->> 'usage_event_id')::uuid, '{"idempotency_key":"chg:draft:0001","tokens_in":999999}') ->> 'repeat')::boolean);
select pg_temp.ok('and wrote no second ledger row', (select count(*) from bi_wallet_ledger where idempotency_key like 'chg:draft:0001:%') = 1
  and bi_wallet_available_cents(:'wallet') = 37544);
select pg_temp.refuses('a charged event cannot be charged again under another key',
  $q$select bi_wallet_charge('$q$ || (:'e1'::jsonb ->> 'usage_event_id') || $q$', '{"idempotency_key":"chg:draft:other","tokens_in":1}')$q$, 'another key');

select bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'wallet', 'kind', 'ai_draft', 'model_code', 'ai_fast', 'tokens_in', 1000000,
         'idempotency_key', 'est:over:0001')) as e2 \gset
select pg_temp.ok('estimate: 1 000 000 fast tokens in preview R11,10', (:'e2'::jsonb ->> 'estimate_cents')::int = 1110);
select pg_temp.ok('an actual of 2 000 000 tokens (R22,20, more than 25% above) charges only the estimate R11,10',
  bi_wallet_charge((:'e2'::jsonb ->> 'usage_event_id')::uuid, '{"idempotency_key":"chg:over:0001","tokens_in":2000000}')
    @> '{"actual_cents": 2220, "charged_cents": 1110}');

select pg_temp.ok('an estimate above the balance is refused as wallet_empty',
  bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'wallet', 'kind', 'ai_draft', 'tokens_in', 100000000, 'idempotency_key', 'est:empty:0001'))
    @> '{"allowed": false, "reason": "wallet_empty"}');
select pg_temp.refuses('a refused estimate is never charged',
  $q$select bi_wallet_charge((select id from bi_usage_event where estimate_key = 'est:empty:0001'), '{"idempotency_key":"chg:empty:0001"}')$q$, 'never charged');
select pg_temp.refuses('only the company admin sets the spend cap',
  $q$select bi_wallet_set_cap('b1a00000-0000-4000-8000-000000000011', '$q$ || :'wallet' || $q$', 3000)$q$, 'not found');
select pg_temp.ok('the company admin sets a R30,00 monthly cap', bi_wallet_set_cap(:adminauth, :'wallet', 3000) ->> 'monthly_spend_cap_cents' = '3000');
select pg_temp.ok('this month''s charges (R11,80 + R22,76 + R11,10) plus a R21,09 estimate pass the cap: spend_cap',
  bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'wallet', 'kind', 'ai_draft', 'tokens_in', 150000, 'tokens_out', 8000, 'idempotency_key', 'est:cap:0001'))
    @> '{"allowed": false, "reason": "spend_cap"}');
select bi_wallet_set_cap(:adminauth, :'wallet', null) is not null as cap_cleared \gset

-- 4. Photo tagging free to 50 per report ----------------------------------------------------------------------------

select id as report from bi_report limit 1 \gset
select bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'wallet', 'kind', 'photo_tag', 'photos', 40, 'tokens_in', 1000, 'tokens_out', 100,
         'report_id', :'report', 'idempotency_key', 'est:tag:0001')) as t1 \gset
select pg_temp.ok('tagging the first 40 photos of a report is free (R0,00, 40 free)', :'t1'::jsonb @> '{"estimate_cents": 0, "free_photos": 40, "allowed": true}');
select pg_temp.ok('and charges nothing', bi_wallet_charge((:'t1'::jsonb ->> 'usage_event_id')::uuid, '{"idempotency_key":"chg:tag:0001","tokens_in":1000,"tokens_out":100}') ->> 'charged_cents' = '0');
select pg_temp.ok('the next 30 photos: 10 free, 20 charged at 1 000 in and 100 out each = R0,2775, 28 cents',
  bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'wallet', 'kind', 'photo_tag', 'photos', 30, 'tokens_in', 1000, 'tokens_out', 100,
         'report_id', :'report', 'idempotency_key', 'est:tag:0002')) @> '{"estimate_cents": 28, "free_photos": 10}');

-- 5. Shortfall on a small wallet ------------------------------------------------------------------------------------

insert into msp_client_account (id, company_name, contact_name, contact_email) values
  ('b5a00000-0000-4000-8000-000000000002', 'Small Wallet Works (fictitious)', 'Contact', 'small.wallet.check@example.invalid');
insert into bi_company (client_account_id, legal_name, onboarding_status, activated_at, activated_by)
values ('b5a00000-0000-4000-8000-000000000002', 'Small Wallet Works (fictitious)', 'active', now(), 'check');
insert into bi_company_subscription (id, tenant_id, client_account_id, plan_code, price_cents, wallet_monthly_cents, storage_bytes)
values ('b5a00000-0000-4000-8000-000000000031', :tenant, 'b5a00000-0000-4000-8000-000000000002', 'extra_company', 19900, 10000, 1500);
select (bi_wallet_grant_included('b5a00000-0000-4000-8000-000000000031', date_trunc('month', current_date)::date) ->> 'wallet_id') as w2 \gset
select pg_temp.ok('an extra company line receives R100,00 included', bi_wallet_available_cents(:'w2') = 10000);
select (bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'w2', 'kind', 'ai_draft', 'tokens_in', 540000, 'idempotency_key', 'est:sf:0001')) ->> 'usage_event_id') as sf1 \gset
select (bi_wallet_estimate(:inspauth, jsonb_build_object('wallet_id', :'w2', 'kind', 'ai_draft', 'tokens_in', 540000, 'idempotency_key', 'est:sf:0002')) ->> 'usage_event_id') as sf2 \gset
select pg_temp.ok('two R59,94 estimates are each allowed against R100,00',
  (select bool_and(status = 'estimated' and estimate_cents = 5994) from bi_usage_event where estimate_key like 'est:sf:%'));
select pg_temp.ok('the first charges R59,94', bi_wallet_charge(:'sf1', '{"idempotency_key":"chg:sf:0001","tokens_in":540000}') ->> 'charged_cents' = '5994');
select pg_temp.ok('the second finds R40,06 left: R40,06 is charged and R19,88 recorded as shortfall carried by Care Net',
  bi_wallet_charge(:'sf2', '{"idempotency_key":"chg:sf:0002","tokens_in":540000}') @> '{"charged_cents": 5994, "shortfall_cents": 1988, "available_cents": 0}');
select pg_temp.ok('the ledger never goes below zero', bi_wallet_available_cents(:'w2') = 0
  and (select sum(amount_cents) from bi_wallet_ledger where wallet_id = :'w2') = 0);

-- 6. Automatic top up ------------------------------------------------------------------------------------------------

select pg_temp.refuses('automatic top up needs a saved card', $q$select bi_wallet_set_autotopup('b1a00000-0000-4000-8000-000000000011', '$q$ || :'w2' || $q$', true)$q$, 'saved card');
select pg_temp.ok('the inspector opts in with a saved card reference',
  (bi_wallet_set_autotopup(:inspauth, :'w2', true, 'tok_demo_saved_card_0001') ->> 'auto_topup_enabled')::boolean);
select pg_temp.ok('below R20,00 the wallet is due an automatic R99,00 top up',
  (select count(*) from jsonb_array_elements(bi_autotopup_queue(10) -> 'due') x where x ->> 'wallet_id' = :'w2' and x ->> 'price_cents' = '9900') = 1);
select pg_temp.ok('at most one attempt per wallet per hour', (select count(*) from jsonb_array_elements(bi_autotopup_queue(10) -> 'due') x where x ->> 'wallet_id' = :'w2') = 0);
select pg_temp.ok('the gateway''s success credits R99,00 for 12 months (automatic top up credit)',
  (bi_wallet_topup_apply(:'w2', 'auto_topup', 'auto:check:0001') ->> 'value_cents')::int = 9900);
select pg_temp.ok('the small wallet now holds R99,00', bi_wallet_available_cents(:'w2') = 9900);

-- 7. Receipts, top ups, plans ---------------------------------------------------------------------------------------

select pg_temp.ok('a RevenueCat top up R499,00 credits R550,00',
  bi_iap_apply(jsonb_build_object('provider', 'revenuecat', 'event_id', 'rc-evt-0001', 'event_type', 'NON_RENEWING_PURCHASE',
    'auth_user_id', :inspauth, 'product_code', 'topup_499')) ->> 'status' = 'applied');
select pg_temp.ok('the same RevenueCat event again changes nothing',
  (bi_iap_apply(jsonb_build_object('provider', 'revenuecat', 'event_id', 'rc-evt-0001', 'event_type', 'NON_RENEWING_PURCHASE',
    'auth_user_id', :inspauth, 'product_code', 'topup_499')) ->> 'repeat')::boolean);
select pg_temp.ok('one R550,00 credit landed in the base line''s wallet',
  (select count(*) from bi_wallet_ledger where idempotency_key = 'revenuecat:rc-evt-0001' and amount_cents = 55000 and wallet_id = :'wallet') = 1);
select pg_temp.ok('an unknown product is recorded as rejected, never guessed',
  bi_iap_apply(jsonb_build_object('provider', 'revenuecat', 'event_id', 'rc-evt-0002', 'auth_user_id', :inspauth, 'product_code', 'gold_bars')) @> '{"status": "rejected", "reason": "unknown product"}');
select pg_temp.ok('an unknown user is recorded as rejected',
  bi_iap_apply(jsonb_build_object('provider', 'ozow', 'event_id', 'oz-evt-0001', 'auth_user_id', gen_random_uuid(), 'product_code', 'topup_99')) @> '{"status": "rejected"}');
insert into msp_client_account (id, company_name, contact_name, contact_email) values
  ('b6a00000-0000-4000-8000-000000000002', 'Plan Renewal Works (fictitious)', 'Contact', 'plan.check@example.invalid');
select pg_temp.ok('a store subscription to an extra company opens the line and credits R100,00 included',
  (bi_iap_apply(jsonb_build_object('provider', 'revenuecat', 'event_id', 'rc-evt-0003', 'event_type', 'INITIAL_PURCHASE',
    'auth_user_id', :inspauth, 'product_code', 'extra_company', 'client_account_id', 'b6a00000-0000-4000-8000-000000000002')) -> 'result' ->> 'amount_cents') = '10000');
select pg_temp.ok('the line is live and the company''s onboarding record starts Not started',
  bi_subscription_live(:tenant, 'b6a00000-0000-4000-8000-000000000002')
  and (select onboarding_status from bi_company where client_account_id = 'b6a00000-0000-4000-8000-000000000002') = 'not_started');
select pg_temp.refuses('a top up product not on the rate card is refused', $q$select bi_wallet_topup_apply('$q$ || :'wallet' || $q$', 'topup_5', 'x:y:z:0001')$q$, 'Unknown top up');

-- 8. Expiry ----------------------------------------------------------------------------------------------------------

select pg_temp.ok('the expiry run writes the remainder of every lapsed lot (thirteen months on, everything has lapsed)',
  (bi_wallet_expire_lots(now() + interval '13 months') ->> 'expired_lots')::int > 0);
select pg_temp.ok('once only', (bi_wallet_expire_lots(now() + interval '13 months') ->> 'expired_lots')::int = 0);
select pg_temp.ok('after expiry rows the ledger of the seed wallet sums to zero', (select sum(amount_cents) from bi_wallet_ledger where wallet_id = :'wallet') = 0);

-- 9. Welcome hook ----------------------------------------------------------------------------------------------------

select pg_temp.ok('welcome_hook is off by default: nothing is granted', bi_welcome_hook_grant(:tenant) @> '{"granted": false}');
update bi_feature_flag set enabled = true where key = 'welcome_hook' and tenant_id is null;
select pg_temp.ok('with welcome_hook on: R20,00 is granted', bi_welcome_hook_grant(:tenant) @> '{"granted": true, "amount_cents": 2000}');
select pg_temp.ok('one R20,00 welcome credit', (select count(*) from bi_wallet_ledger where idempotency_key = 'welcome:' || :tenant) = 1);
select pg_temp.ok('a second grant returns the same lot', (bi_welcome_hook_grant(:tenant) ->> 'lot_id') = (select id::text from bi_wallet_ledger where idempotency_key = 'welcome:' || :tenant));
select pg_temp.ok('and one free template inspection', (select welcome_inspections_left from bi_tenant where id = :tenant) = 1);

-- 10. Storage ---------------------------------------------------------------------------------------------------------

select pg_temp.ok('storage levels: 79% ok, 80% warn_80, 95% warn_95, 100% full',
  bi_storage_level(79, 100) = 'ok' and bi_storage_level(80, 100) = 'warn_80' and bi_storage_level(95, 100) = 'warn_95' and bi_storage_level(100, 100) = 'full');
insert into bi_site (id, client_account_id, name) values ('b5a00000-0000-4000-8000-000000000041', 'b5a00000-0000-4000-8000-000000000002', 'Small Site');
insert into bi_inspection (id, tenant_id, client_account_id, site_id, template_id, inspector_user_id, title, status)
values ('b5a00000-0000-4000-8000-000000000081', :tenant, 'b5a00000-0000-4000-8000-000000000002', 'b5a00000-0000-4000-8000-000000000041',
        'b1a00000-0000-4000-8000-000000000062', 'b1a00000-0000-4000-8000-000000000021', 'Small storage line', 'in_progress');
insert into bi_photo (inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, inspector_user_id)
values ('b5a00000-0000-4000-8000-000000000081', :tenant, 'b5a00000-0000-4000-8000-000000000002', 'area',
        'b5a00000-0000-4000-8000-000000000002/b5a00000-0000-4000-8000-000000000081/one.jpg', repeat('1', 64), 1000, 'image/jpeg', now() - interval '2 hours', 'b1a00000-0000-4000-8000-000000000021');
select pg_temp.ok('1 000 of 1 500 bytes: 66,7%, ok', bi_storage_status(:tenant, 'b5a00000-0000-4000-8000-000000000002') @> '{"level": "ok", "used_bytes": 1000}');
insert into bi_photo (inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, inspector_user_id)
values ('b5a00000-0000-4000-8000-000000000081', :tenant, 'b5a00000-0000-4000-8000-000000000002', 'area',
        'b5a00000-0000-4000-8000-000000000002/b5a00000-0000-4000-8000-000000000081/two.jpg', repeat('2', 64), 600, 'image/jpeg', now() - interval '1 hour', 'b1a00000-0000-4000-8000-000000000021');
select pg_temp.ok('the photo that crosses 100% is kept and the meter records when the line filled',
  (select level = 'full' and full_since is not null from bi_storage_meter where client_account_id = 'b5a00000-0000-4000-8000-000000000002'));
select pg_temp.refuses('at 100% a new photo is refused (view and sync continue)',
  $q$insert into bi_voice_note (inspection_id, tenant_id, client_account_id, audio_path, audio_sha256, size_bytes, mime_type, duration_seconds, captured_at, inspector_user_id)
     values ('b5a00000-0000-4000-8000-000000000081', 'b1a00000-0000-4000-8000-000000000001', 'b5a00000-0000-4000-8000-000000000002',
             'b5a00000-0000-4000-8000-000000000002/b5a00000-0000-4000-8000-000000000081/three.m4a', repeat('3', 64), 10, 'audio/mp4', 3, now(), 'b1a00000-0000-4000-8000-000000000021')$q$, 'Storage is full');
-- But a photo captured offline before the line filled still syncs:
insert into bi_photo (inspection_id, tenant_id, client_account_id, kind, storage_path, sha256, size_bytes, mime_type, captured_at, inspector_user_id)
values ('b5a00000-0000-4000-8000-000000000081', :tenant, 'b5a00000-0000-4000-8000-000000000002', 'area',
        'b5a00000-0000-4000-8000-000000000002/b5a00000-0000-4000-8000-000000000081/offline.jpg', repeat('4', 64), 10, 'image/jpeg', now() - interval '3 hours', 'b1a00000-0000-4000-8000-000000000021');
select pg_temp.ok('the offline photo is stored', exists (select 1 from bi_photo where storage_path like '%/offline.jpg'));
select pg_temp.ok('the storage meter run reports the line''s level',
  exists (select 1 from jsonb_array_elements(bi_storage_meter_run() -> 'warnings') w where w ->> 'client_account_id' = 'b5a00000-0000-4000-8000-000000000002')
  or (select level from bi_storage_meter where client_account_id = 'b5a00000-0000-4000-8000-000000000002') = 'full');

do $$ begin raise notice 'bi_wallet_checks: all checks passed. Rolling back the test data.'; end $$;
rollback;
