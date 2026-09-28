-- CNC HSF FORGE | BI-WAL-01 v1.0.0 | Bee-Inspect AI Wallet, billing, usage and storage 26/09/2026
-- Built to hsf/BUILD-CONTRACT.md 16 and hsf/BEE-INSPECT-BUILD-PROMPT.md B8 and
-- section 6, phase P3.
--
-- Money rules (B8), all amounts in cents of a rand, excluding VAT
-- (bi.vat_mode 'to_be_confirmed' until Chantelle confirms {{vat_inclusive}}):
--   price  = (tokens in x input rate + tokens out x output rate
--             + audio minutes x transcription rate) x fx x markup
--            rates in US dollars per million tokens and per minute, fx rand per
--            US dollar, markup bi.markup_default (3.0); rounded half up to the
--            cent once, at the end (bi_price_cents; the same arithmetic as
--            supabase/functions/_shared/bi/pricing.js).
--   charge = the actual price, unless it is more than the estimate plus 25%,
--            then the estimate (bi_charge_rule_cents).
--   Included value (R150,00 base, R100,00 extra company, each month) rolls over
--   one month (expires two months after its period starts); purchased value
--   lasts 12 months. Value is spent oldest expiry first.
--   Top ups: R99,00 (R99,00 value), R249,00 (R260,00), R499,00 (R550,00),
--   R999,00 (R1 150,00). Automatic top up (opt in): R99,00 when the balance is
--   below R20,00.
--   At R0,00 capture and template reports still work: only AI actions wait.
--   Photo tagging is free for the first 50 photos of a report.
--   Storage: 10 GB per company line; warnings at 80% and 95%; at 100% new photos
--   and voice notes are refused (viewing and syncing of what was captured
--   before continue).
-- The AI and transcription rates are not known yet ({{rate_card}}): their rate
-- card rows are placeholders with no rates, and every estimate that needs them
-- answers rate_card_pending until ops enters confirmed rows.
--
-- What this migration does:
--   1. bi_rate_card with the plan, top up, automatic top up, storage pack, AI
--      model, transcription and fx rows.
--   2. bi_wallet (one per company line), bi_wallet_ledger (append only; every
--      credit is a lot with an expiry, every charge or expiry row names the lot
--      it spends), bi_usage_event (the estimate before each AI action and the
--      charge after it, idempotent on its keys), bi_iap_receipt (store and
--      payment receipts, idempotent per provider event).
--   3. The pricing, estimate, charge, credit, expiry and automatic top up
--      functions, and the welcome hook (flag welcome_hook, off).
--   4. bi_storage_meter and the storage gate on photos and voice notes.
-- No client writes to any of these tables: only security definer functions.
-- Not applied to the live project.

-- 1. Rate card --------------------------------------------------------------------------------

create table bi_rate_card (
  id uuid primary key default gen_random_uuid(),
  code text not null check (code ~ '^[a-z][a-z0-9_]{2,40}$'),
  kind text not null check (kind in ('plan','topup','auto_topup','storage_pack','ai_model','transcription','fx')),
  label text not null,
  price_cents bigint check (price_cents >= 0),
  value_cents bigint check (value_cents >= 0),
  wallet_monthly_cents bigint check (wallet_monthly_cents >= 0),
  storage_bytes bigint check (storage_bytes > 0),
  threshold_cents bigint check (threshold_cents >= 0),
  usd_per_mtok_in numeric(12,6) check (usd_per_mtok_in >= 0),
  usd_per_mtok_out numeric(12,6) check (usd_per_mtok_out >= 0),
  usd_per_minute numeric(12,6) check (usd_per_minute >= 0),
  usd_zar numeric(10,4) check (usd_zar > 0),
  status text not null default 'placeholder' check (status in ('placeholder','confirmed','retired')),
  effective_from date not null default current_date,
  notes text,
  created_at timestamptz not null default now(),
  unique (code, effective_from)
);
comment on table bi_rate_card is 'BI-WAL-01 (prompt B8). Prices and rates, excluding VAT, in cents (rand) or US dollars for the AI and transcription rates. The row in force for a code is the latest effective_from on or before today that is not retired. AI model, transcription and fx rows are placeholders without rates until {{rate_card}} is confirmed; storage packs wait for {{rate_card}} too. Written by ops through the service role.';

insert into bi_rate_card (code, kind, label, price_cents, value_cents, wallet_monthly_cents, storage_bytes, threshold_cents, status, effective_from, notes) values
  ('base', 'plan', 'Bee-Inspect base: one auditor, first company', 29900, null, 15000, 10737418240, null, 'confirmed', '2026-09-24', 'Prompt B8. Unlimited inspections and template reports.'),
  ('extra_company', 'plan', 'Bee-Inspect extra company', 19900, null, 10000, 10737418240, null, 'confirmed', '2026-09-24', 'Prompt B8.'),
  ('topup_99', 'topup', 'AI Wallet top up R99,00', 9900, 9900, null, null, null, 'confirmed', '2026-09-24', 'Prompt B8.'),
  ('topup_249', 'topup', 'AI Wallet top up R249,00 (R260,00 value)', 24900, 26000, null, null, null, 'confirmed', '2026-09-24', 'Prompt B8.'),
  ('topup_499', 'topup', 'AI Wallet top up R499,00 (R550,00 value)', 49900, 55000, null, null, null, 'confirmed', '2026-09-24', 'Prompt B8.'),
  ('topup_999', 'topup', 'AI Wallet top up R999,00 (R1 150,00 value)', 99900, 115000, null, null, null, 'confirmed', '2026-09-24', 'Prompt B8.'),
  ('auto_topup', 'auto_topup', 'Automatic top up R99,00 below R20,00 (opt in)', 9900, 9900, null, null, 2000, 'confirmed', '2026-09-24', 'Prompt B8.'),
  ('storage_pack', 'storage_pack', 'Extra storage (price to be confirmed)', null, null, null, null, null, 'placeholder', '2026-09-24', '{{rate_card}}'),
  ('ai_fast', 'ai_model', 'AI fast model (tagging and passes)', null, null, null, null, null, 'placeholder', '2026-09-24', '{{rate_card}}: xAI rates not confirmed. The model id is read from an environment variable, never stored here.'),
  ('ai_quality', 'ai_model', 'AI quality model (final draft)', null, null, null, null, null, 'placeholder', '2026-09-24', '{{rate_card}}: xAI rates not confirmed.'),
  ('transcription', 'transcription', 'Transcription on sync', null, null, null, null, null, 'placeholder', '2026-09-24', '{{rate_card}}: transcription vendor not chosen.'),
  ('fx_usd_zar', 'fx', 'Rand per US dollar', null, null, null, null, null, 'placeholder', '2026-09-24', '{{rate_card}}: fx source and update rule not decided.');

create function bi_rate_card_current(p_code text)
returns bi_rate_card
language sql
stable
security definer
set search_path = public
as $$
  select r.* from bi_rate_card r
   where r.code = p_code and r.status <> 'retired' and r.effective_from <= current_date
   order by r.effective_from desc, r.created_at desc limit 1;
$$;
comment on function bi_rate_card_current is 'BI-WAL-01. The rate card row in force for a code today.';

-- 2. Pricing maths -----------------------------------------------------------------------------

create function bi_price_cents(p_tokens_in bigint, p_tokens_out bigint, p_audio_seconds bigint,
                               p_usd_per_mtok_in numeric, p_usd_per_mtok_out numeric, p_usd_per_minute numeric,
                               p_usd_zar numeric, p_markup numeric)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_n numeric;
  v_d constant numeric := 60000000;  -- 60 seconds x 1 000 000 tokens
begin
  if least(coalesce(p_tokens_in, 0), coalesce(p_tokens_out, 0), coalesce(p_audio_seconds, 0)) < 0
     or least(coalesce(p_usd_per_mtok_in, 0), coalesce(p_usd_per_mtok_out, 0), coalesce(p_usd_per_minute, 0), p_usd_zar, p_markup) < 0 then
    raise exception 'bi_price_cents: negative input' using errcode = '22023';
  end if;
  -- Exact: every factor multiplies; the one division is the final rounding.
  -- cents = (tin x rin / 1e6 + tout x rout / 1e6 + sec x rmin / 60) x fx x markup x 100
  v_n := (coalesce(p_tokens_in, 0) * coalesce(p_usd_per_mtok_in, 0) * 60
          + coalesce(p_tokens_out, 0) * coalesce(p_usd_per_mtok_out, 0) * 60
          + coalesce(p_audio_seconds, 0) * coalesce(p_usd_per_minute, 0) * 1000000)
         * p_usd_zar * p_markup * 100;
  -- Round half up to the cent.
  return div(2 * v_n + v_d, 2 * v_d)::bigint;
end;
$$;
comment on function bi_price_cents is 'BI-WAL-01 (prompt B8). price = (tokens in x input rate + tokens out x output rate + audio minutes x transcription rate) x fx x markup, in cents, rounded half up once at the end. Rates in US dollars per million tokens and per minute; fx in rand per US dollar. Worked example: 200 000 tokens in at 0.20, 20 000 out at 0.50, 10 minutes at 0.006, fx 18.50, markup 3.0 = 0.11 US dollars x 18.50 x 3.0 = R6,105 = 611 cents (R6,11).';

create function bi_charge_rule_cents(p_estimate_cents bigint, p_actual_cents bigint)
returns bigint
language sql
immutable
set search_path = ''
as $$
  -- Charge the actual, unless the actual is more than the estimate plus 25%:
  -- then charge the estimate. actual > 1.25 x estimate  <=>  4 x actual > 5 x estimate.
  select case when p_actual_cents * 4 > p_estimate_cents * 5 then p_estimate_cents else p_actual_cents end;
$$;
comment on function bi_charge_rule_cents is 'BI-WAL-01 (prompt B8). The amount charged: the actual price, unless it is more than the estimate plus 25%, then the estimate. Estimate 500, actual 600: 600. Estimate 500, actual 625: 625. Estimate 500, actual 626: 500.';

create function bi_storage_level(p_used bigint, p_quota bigint)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when coalesce(p_quota, 0) <= 0 then 'full'
              when p_used * 100 >= p_quota * 100 then 'full'
              when p_used * 100 >= p_quota * 95 then 'warn_95'
              when p_used * 100 >= p_quota * 80 then 'warn_80'
              else 'ok' end;
$$;
comment on function bi_storage_level is 'BI-WAL-01 (prompt B8). ok below 80%, warn_80 from 80%, warn_95 from 95%, full at 100% of the quota.';

-- 3. Wallets and the ledger -------------------------------------------------------------------------

create table bi_wallet (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  monthly_spend_cap_cents bigint check (monthly_spend_cap_cents >= 0),
  auto_topup_enabled boolean not null default false,
  auto_topup_opted_in_at timestamptz,
  auto_topup_opted_in_by uuid references auth.users(id),
  saved_card_ref text check (saved_card_ref is null or saved_card_ref ~ '^[A-Za-z0-9_:.-]{8,200}$'),
  status text not null default 'active' check (status in ('active','frozen')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version int not null default 1,
  unique (tenant_id, client_account_id),
  check (not auto_topup_enabled or (auto_topup_opted_in_at is not null and auto_topup_opted_in_by is not null))
);
comment on table bi_wallet is 'BI-WAL-01 (prompt B8). The AI Wallet of one company line (tenant and company): the balance is the ledger, never a stored number. Company spend cap per calendar month (set by the company admin). Automatic top up only after an explicit opt in, with a saved card reference from {{saved_card_gateway}} (a gateway token, never card details).';
create trigger bi_wallet_touch before update on bi_wallet for each row execute function bi_touch();

create table bi_wallet_ledger (
  id bigint generated always as identity primary key,
  wallet_id uuid not null references bi_wallet(id),
  entry_kind text not null check (entry_kind in ('included_credit','topup_credit','auto_topup_credit','welcome_credit','charge','expiry','refund')),
  amount_cents bigint not null check (amount_cents <> 0),
  lot_id bigint references bi_wallet_ledger(id),
  expires_at timestamptz,
  idempotency_key text not null unique check (length(idempotency_key) between 8 and 200),
  usage_event_id uuid,
  iap_receipt_id uuid,
  note text,
  created_by text not null default 'system',
  created_at timestamptz not null default now(),
  constraint bi_ledger_credit_shape check (entry_kind not in ('included_credit','topup_credit','auto_topup_credit','welcome_credit')
    or (amount_cents > 0 and expires_at is not null and lot_id is null)),
  constraint bi_ledger_debit_shape check (entry_kind not in ('charge','expiry')
    or (amount_cents < 0 and lot_id is not null and expires_at is null)),
  constraint bi_ledger_refund_shape check (entry_kind <> 'refund' or (amount_cents > 0 and lot_id is not null and expires_at is null))
);
comment on table bi_wallet_ledger is 'BI-WAL-01 (prompt B8). Append only AI Wallet ledger in cents of a rand. Every credit is a lot with its expiry (included value: two months from its period start, so it rolls one month; purchased value: 12 months). Every charge, expiry and refund row names the lot it moves. Idempotent on idempotency_key. Written only by the wallet functions; never shown as tokens.';
create index bi_wallet_ledger_wallet_idx on bi_wallet_ledger(wallet_id, created_at);
create index bi_wallet_ledger_lot_idx on bi_wallet_ledger(lot_id);
create trigger bi_wallet_ledger_append_only before update or delete on bi_wallet_ledger for each row execute function bi_append_only();

create function bi_wallet_lots(p_wallet_id uuid)
returns table (lot_id bigint, entry_kind text, expires_at timestamptz, credited_cents bigint, remaining_cents bigint)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.entry_kind, c.expires_at, c.amount_cents,
         c.amount_cents + coalesce((select sum(d.amount_cents) from bi_wallet_ledger d where d.lot_id = c.id), 0)
    from bi_wallet_ledger c
   where c.wallet_id = p_wallet_id and c.lot_id is null
   order by c.expires_at, c.id;
$$;
comment on function bi_wallet_lots is 'BI-WAL-01. Every credit lot of a wallet with what remains of it.';

create function bi_wallet_available_cents(p_wallet_id uuid, p_at timestamptz default now())
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(greatest(l.remaining_cents, 0)), 0)::bigint
    from bi_wallet_lots(p_wallet_id) l where l.expires_at > p_at;
$$;
comment on function bi_wallet_available_cents is 'BI-WAL-01. What a wallet can spend now: the remainder of every lot that has not expired.';

create function bi_wallet_balance(p_wallet_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'wallet_id', p_wallet_id,
    'available_cents', coalesce(sum(greatest(l.remaining_cents, 0)) filter (where l.expires_at > now()), 0),
    'included_cents', coalesce(sum(greatest(l.remaining_cents, 0)) filter (where l.expires_at > now() and l.entry_kind = 'included_credit'), 0),
    'purchased_cents', coalesce(sum(greatest(l.remaining_cents, 0)) filter (where l.expires_at > now() and l.entry_kind <> 'included_credit'), 0),
    'next_expiry', min(l.expires_at) filter (where l.expires_at > now() and l.remaining_cents > 0),
    'vat_mode', coalesce(msp_env_get('bi.vat_mode'), 'to_be_confirmed'))
    from bi_wallet_lots(p_wallet_id) l;
$$;
comment on function bi_wallet_balance is 'BI-WAL-01. The balance in cents: available, of which included and purchased, the next expiry, and the VAT mode. Always rand, never tokens.';

create table bi_usage_event (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references bi_wallet(id),
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  auth_user_id uuid references auth.users(id),
  report_id uuid references bi_report(id),
  inspection_id uuid references bi_inspection(id),
  kind text not null check (kind in ('ai_draft','ai_tagging','transcription','photo_tag')),
  model_code text,
  est_tokens_in bigint not null default 0 check (est_tokens_in >= 0),
  est_tokens_out bigint not null default 0 check (est_tokens_out >= 0),
  est_audio_seconds bigint not null default 0 check (est_audio_seconds >= 0),
  photos int not null default 0 check (photos >= 0),
  free_photos int not null default 0 check (free_photos >= 0),
  rate_in numeric(12,6),
  rate_out numeric(12,6),
  rate_minute numeric(12,6),
  usd_zar numeric(10,4),
  markup numeric(6,3),
  estimate_cents bigint not null default 0 check (estimate_cents >= 0),
  act_tokens_in bigint,
  act_tokens_out bigint,
  act_audio_seconds bigint,
  actual_cents bigint,
  charged_cents bigint,
  shortfall_cents bigint,
  status text not null check (status in ('estimated','refused','charged')),
  refusal_reason text check (refusal_reason in ('wallet_empty','spend_cap','rate_card_pending','wallet_frozen')),
  estimate_key text not null unique check (length(estimate_key) between 8 and 200),
  charge_key text unique check (length(charge_key) between 8 and 200),
  created_at timestamptz not null default now(),
  charged_at timestamptz,
  check ((status = 'refused') = (refusal_reason is not null)),
  check (status <> 'charged' or (charged_cents is not null and actual_cents is not null and charge_key is not null))
);
comment on table bi_usage_event is 'BI-WAL-01 (prompt B8). One AI action: the cost preview before it (estimate, status estimated or refused with the reason) and the charge after it (actual, charged, and any shortfall Care Net carries when the balance ran out mid action). Rates, fx and markup are copied at the estimate so the charge uses the same card. Idempotent on estimate_key and charge_key. Written only by bi_wallet_estimate and bi_wallet_charge.';
create index bi_usage_event_wallet_idx on bi_usage_event(wallet_id, created_at);
create index bi_usage_event_report_idx on bi_usage_event(report_id, kind);

create function bi_usage_event_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'bi_usage_event is never deleted';
  end if;
  if old.status <> 'estimated' then
    raise exception 'bi_usage_event: a refused or charged event never changes';
  end if;
  return new;
end;
$$;
create trigger bi_usage_event_guard before update or delete on bi_usage_event for each row execute function bi_usage_event_guard();

create table bi_iap_receipt (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('revenuecat','ozow','saved_card','manual')),
  external_event_id text not null check (length(external_event_id) between 3 and 200),
  event_type text not null,
  auth_user_id uuid references auth.users(id),
  tenant_id uuid references bi_tenant(id),
  wallet_id uuid references bi_wallet(id),
  client_account_id uuid references msp_client_account(id),
  product_code text,
  amount_cents bigint,
  status text not null default 'received' check (status in ('received','applied','rejected','ignored')),
  reject_reason text,
  payload_sha256 text check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  received_at timestamptz not null default now(),
  applied_at timestamptz,
  unique (provider, external_event_id)
);
comment on table bi_iap_receipt is 'BI-WAL-01 (prompt B8). Store and payment receipts: RevenueCat (store subscriptions and top ups), Ozow (web billing), the saved card gateway (automatic top up). One row per provider event, so a repeated webhook changes nothing. Only the payload fingerprint is kept, never card details.';

-- 4. Credits, estimate, charge ------------------------------------------------------------------------

create function bi_wallet_credit(p_wallet_id uuid, p_kind text, p_amount_cents bigint, p_expires_at timestamptz,
                                 p_idempotency_key text, p_iap_receipt_id uuid default null, p_note text default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if p_kind not in ('included_credit','topup_credit','auto_topup_credit','welcome_credit') then
    raise exception 'bi_wallet_credit: unknown credit kind %', p_kind using errcode = '22023';
  end if;
  insert into bi_wallet_ledger (wallet_id, entry_kind, amount_cents, expires_at, idempotency_key, iap_receipt_id, note)
  values (p_wallet_id, p_kind, p_amount_cents, p_expires_at, p_idempotency_key, p_iap_receipt_id, p_note)
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from bi_wallet_ledger where idempotency_key = p_idempotency_key;
  else
    perform bi_audit(null, 'wallet_credited', w.tenant_id, w.client_account_id, 'wallet', w.id,
                     jsonb_build_object('kind', p_kind, 'amount_cents', p_amount_cents, 'expires_at', p_expires_at))
       from bi_wallet w where w.id = p_wallet_id;
  end if;
  return v_id;
end;
$$;
comment on function bi_wallet_credit is 'BI-WAL-01. Adds one credit lot, idempotent on the key (a repeat returns the first lot). Audited.';

create function bi_wallet_ensure(p_tenant uuid, p_company uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into bi_wallet (tenant_id, client_account_id) values (p_tenant, p_company)
  on conflict (tenant_id, client_account_id) do nothing
  returning id into v_id;
  return coalesce(v_id, (select id from bi_wallet where tenant_id = p_tenant and client_account_id = p_company));
end;
$$;

create function bi_wallet_grant_included(p_subscription_id uuid, p_period_start date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s bi_company_subscription;
  v_w uuid;
  v_lot bigint;
begin
  select * into v_s from bi_company_subscription where id = p_subscription_id;
  if v_s.id is null or v_s.status not in ('trial','active','past_due') then
    raise exception 'That subscription line is not live.' using errcode = 'P0002';
  end if;
  v_w := bi_wallet_ensure(v_s.tenant_id, v_s.client_account_id);
  -- Included value rolls over one month: it expires two months after the period starts.
  v_lot := bi_wallet_credit(v_w, 'included_credit', v_s.wallet_monthly_cents,
                            (p_period_start + interval '2 months')::timestamptz,
                            'included:' || v_s.id || ':' || p_period_start, null,
                            'Included AI Wallet value for the month from ' || to_char(p_period_start, 'DD/MM/YYYY'));
  return jsonb_build_object('wallet_id', v_w, 'lot_id', v_lot, 'amount_cents', v_s.wallet_monthly_cents);
end;
$$;
comment on function bi_wallet_grant_included(uuid, date) is 'BI-WAL-01 (prompt B8). Credits a line''s monthly included value (R150,00 base, R100,00 extra company) for the period starting p_period_start; it expires two months later (rolls one month). Idempotent per line and period.';

create function bi_wallet_topup_apply(p_wallet_id uuid, p_product_code text, p_idempotency_key text, p_receipt_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc bi_rate_card;
  v_lot bigint;
begin
  v_rc := bi_rate_card_current(p_product_code);
  if v_rc.id is null or v_rc.kind not in ('topup','auto_topup') or v_rc.status <> 'confirmed' or v_rc.value_cents is null then
    raise exception 'Unknown top up product %', p_product_code using errcode = '22023';
  end if;
  v_lot := bi_wallet_credit(p_wallet_id, case when v_rc.kind = 'auto_topup' then 'auto_topup_credit' else 'topup_credit' end,
                            v_rc.value_cents, now() + interval '12 months', p_idempotency_key, p_receipt_id,
                            v_rc.label);
  return jsonb_build_object('wallet_id', p_wallet_id, 'lot_id', v_lot, 'price_cents', v_rc.price_cents, 'value_cents', v_rc.value_cents);
end;
$$;
comment on function bi_wallet_topup_apply is 'BI-WAL-01 (prompt B8). Credits a paid top up at its rate card value (R249,00 buys R260,00 and so on); purchased value lasts 12 months. Idempotent on the key.';

create function bi_photo_tags_used(p_report_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(u.photos), 0)::int from bi_usage_event u
   where u.report_id = p_report_id and u.kind = 'photo_tag' and u.status = 'charged';
$$;

create function bi_wallet_estimate(p_auth_user uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_w bi_wallet;
  v_kind text := p ->> 'kind';
  v_model text;
  v_rc bi_rate_card;
  v_fx bi_rate_card;
  v_markup numeric := coalesce(msp_env_get_numeric('bi.markup_default'), 3.0);
  v_tin bigint := coalesce((p ->> 'tokens_in')::bigint, 0);
  v_tout bigint := coalesce((p ->> 'tokens_out')::bigint, 0);
  v_sec bigint := coalesce((p ->> 'audio_seconds')::bigint, 0);
  v_photos int := coalesce((p ->> 'photos')::int, 0);
  v_report uuid := nullif(p ->> 'report_id', '')::uuid;
  v_free int := 0;
  v_chargeable int;
  v_est bigint := 0;
  v_avail bigint;
  v_spent bigint;
  v_reason text;
  v_key text := p ->> 'idempotency_key';
  v_id uuid;
  v_existing bi_usage_event;
begin
  select * into v_existing from bi_usage_event where estimate_key = v_key;
  if v_existing.id is not null then
    return jsonb_build_object('usage_event_id', v_existing.id, 'estimate_cents', v_existing.estimate_cents,
      'allowed', v_existing.status = 'estimated', 'reason', v_existing.refusal_reason, 'free_photos', v_existing.free_photos,
      'available_cents', bi_wallet_available_cents(v_existing.wallet_id), 'repeat', true);
  end if;
  select * into v_w from bi_wallet where id = nullif(p ->> 'wallet_id', '')::uuid;
  if v_w.id is null or not (bi_user_is_ops(p_auth_user)
       or bi_user_roles(p_auth_user, v_w.tenant_id, v_w.client_account_id) && array['inspector','company_admin']) then
    raise exception 'That wallet was not found.' using errcode = 'P0002';
  end if;
  if v_kind not in ('ai_draft','ai_tagging','transcription','photo_tag') or least(v_tin, v_tout, v_sec, v_photos) < 0 then
    raise exception 'bi_wallet_estimate: unknown kind or negative quantity' using errcode = '22023';
  end if;
  if v_key is null or length(v_key) < 8 then
    raise exception 'bi_wallet_estimate: an idempotency key of at least 8 characters is required' using errcode = '22023';
  end if;
  v_model := case v_kind when 'transcription' then 'transcription'
                         when 'ai_draft' then coalesce(p ->> 'model_code', 'ai_quality')
                         else coalesce(p ->> 'model_code', 'ai_fast') end;
  if v_model not in ('ai_fast','ai_quality','transcription') then
    raise exception 'bi_wallet_estimate: unknown model code' using errcode = '22023';
  end if;
  v_rc := bi_rate_card_current(v_model);
  v_fx := bi_rate_card_current('fx_usd_zar');

  if v_kind = 'photo_tag' then
    -- Free for the first 50 photos of a report; tokens are per photo.
    v_free := least(v_photos, greatest(0, 50 - case when v_report is null then 0 else bi_photo_tags_used(v_report) end));
    v_chargeable := v_photos - v_free;
    v_tin := v_tin * v_chargeable;
    v_tout := v_tout * v_chargeable;
    v_sec := 0;
  end if;

  if v_tin = 0 and v_tout = 0 and v_sec = 0 then
    v_est := 0;
  elsif v_rc.status is distinct from 'confirmed' or v_fx.status is distinct from 'confirmed' or v_fx.usd_zar is null
        or (v_model <> 'transcription' and (v_rc.usd_per_mtok_in is null or v_rc.usd_per_mtok_out is null))
        or (v_model = 'transcription' and v_rc.usd_per_minute is null) then
    v_reason := 'rate_card_pending';
  else
    v_est := bi_price_cents(v_tin, v_tout, v_sec, v_rc.usd_per_mtok_in, v_rc.usd_per_mtok_out, v_rc.usd_per_minute, v_fx.usd_zar, v_markup);
  end if;

  v_avail := bi_wallet_available_cents(v_w.id);
  if v_reason is null and v_w.status = 'frozen' and v_est > 0 then
    v_reason := 'wallet_frozen';
  end if;
  if v_reason is null and v_w.monthly_spend_cap_cents is not null and v_est > 0 then
    select coalesce(-sum(l.amount_cents), 0) into v_spent from bi_wallet_ledger l
     where l.wallet_id = v_w.id and l.entry_kind = 'charge' and l.created_at >= date_trunc('month', now());
    if v_spent + v_est > v_w.monthly_spend_cap_cents then
      v_reason := 'spend_cap';
    end if;
  end if;
  if v_reason is null and v_est > v_avail then
    v_reason := 'wallet_empty';
  end if;

  insert into bi_usage_event (wallet_id, tenant_id, client_account_id, auth_user_id, report_id, inspection_id, kind, model_code,
                              est_tokens_in, est_tokens_out, est_audio_seconds, photos, free_photos,
                              rate_in, rate_out, rate_minute, usd_zar, markup, estimate_cents, status, refusal_reason, estimate_key)
  values (v_w.id, v_w.tenant_id, v_w.client_account_id, p_auth_user, v_report, nullif(p ->> 'inspection_id', '')::uuid, v_kind, v_model,
          v_tin, v_tout, v_sec, v_photos, v_free,
          v_rc.usd_per_mtok_in, v_rc.usd_per_mtok_out, v_rc.usd_per_minute, v_fx.usd_zar, v_markup, v_est,
          case when v_reason is null then 'estimated' else 'refused' end, v_reason, v_key)
  returning id into v_id;
  return jsonb_build_object('usage_event_id', v_id, 'estimate_cents', v_est, 'available_cents', v_avail,
                            'allowed', v_reason is null, 'reason', v_reason, 'free_photos', v_free,
                            'vat_mode', coalesce(msp_env_get('bi.vat_mode'), 'to_be_confirmed'), 'repeat', false);
end;
$$;
comment on function bi_wallet_estimate is 'BI-WAL-01 (prompt B8). The cost preview before an AI action, in cents: p = {wallet_id, kind (ai_draft, ai_tagging, transcription, photo_tag), model_code?, tokens_in, tokens_out, audio_seconds, photos, report_id?, inspection_id?, idempotency_key}. For photo_tag the tokens are per photo and the first 50 photos of a report are free. Refused with a reason: rate_card_pending (rates not confirmed), wallet_frozen, spend_cap (the month''s charges plus this estimate pass the company cap) or wallet_empty (capture and template reports still work). Idempotent on the key. Inspector or company admin of the line, or ops.';

create function bi_wallet_charge(p_usage_event_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_e bi_usage_event;
  v_key text := p ->> 'idempotency_key';
  v_tin bigint := coalesce((p ->> 'tokens_in')::bigint, 0);
  v_tout bigint := coalesce((p ->> 'tokens_out')::bigint, 0);
  v_sec bigint := coalesce((p ->> 'audio_seconds')::bigint, 0);
  v_actual bigint;
  v_charge bigint;
  v_left bigint;
  v_take bigint;
  v_n int := 0;
  r record;
  v_chargeable int;
begin
  select * into v_e from bi_usage_event where id = p_usage_event_id for update;
  if v_e.id is null then
    raise exception 'That usage event was not found.' using errcode = 'P0002';
  end if;
  if v_e.status = 'charged' then
    if v_e.charge_key is distinct from v_key then
      raise exception 'This usage event was already charged under another key.' using errcode = '23505';
    end if;
    return jsonb_build_object('usage_event_id', v_e.id, 'estimate_cents', v_e.estimate_cents, 'actual_cents', v_e.actual_cents,
                              'charged_cents', v_e.charged_cents, 'shortfall_cents', v_e.shortfall_cents,
                              'available_cents', bi_wallet_available_cents(v_e.wallet_id), 'repeat', true);
  end if;
  if v_e.status <> 'estimated' then
    raise exception 'A refused estimate is never charged.';
  end if;
  if v_key is null or length(v_key) < 8 then
    raise exception 'bi_wallet_charge: an idempotency key of at least 8 characters is required' using errcode = '22023';
  end if;
  if least(v_tin, v_tout, v_sec) < 0 then
    raise exception 'bi_wallet_charge: negative quantity' using errcode = '22023';
  end if;
  if v_e.kind = 'photo_tag' then
    v_chargeable := v_e.photos - v_e.free_photos;
    v_tin := v_tin * v_chargeable;
    v_tout := v_tout * v_chargeable;
    v_sec := 0;
  end if;
  if v_e.estimate_cents = 0 and v_tin = 0 and v_tout = 0 and v_sec = 0 then
    v_actual := 0;
  elsif v_e.usd_zar is null then
    v_actual := v_e.estimate_cents;
  else
    v_actual := bi_price_cents(v_tin, v_tout, v_sec, v_e.rate_in, v_e.rate_out, v_e.rate_minute, v_e.usd_zar, v_e.markup);
  end if;
  v_charge := bi_charge_rule_cents(v_e.estimate_cents, v_actual);

  -- Spend the oldest expiry first; every row names the lot it spends.
  perform pg_advisory_xact_lock(hashtext('bi_wallet'), hashtext(v_e.wallet_id::text));
  v_left := v_charge;
  for r in select * from bi_wallet_lots(v_e.wallet_id) l where l.expires_at > now() and l.remaining_cents > 0 order by l.expires_at, l.lot_id loop
    exit when v_left <= 0;
    v_take := least(v_left, r.remaining_cents);
    v_n := v_n + 1;
    insert into bi_wallet_ledger (wallet_id, entry_kind, amount_cents, lot_id, idempotency_key, usage_event_id, note)
    values (v_e.wallet_id, 'charge', -v_take, r.lot_id, v_key || ':' || v_n, v_e.id, v_e.kind);
    v_left := v_left - v_take;
  end loop;

  update bi_usage_event
     set status = 'charged', act_tokens_in = v_tin, act_tokens_out = v_tout, act_audio_seconds = v_sec,
         actual_cents = v_actual, charged_cents = v_charge, shortfall_cents = v_left, charge_key = v_key, charged_at = now()
   where id = v_e.id;
  perform bi_audit(v_e.auth_user_id, 'wallet_charged', v_e.tenant_id, v_e.client_account_id, 'usage_event', v_e.id,
                   jsonb_build_object('estimate_cents', v_e.estimate_cents, 'actual_cents', v_actual, 'charged_cents', v_charge, 'shortfall_cents', v_left));
  return jsonb_build_object('usage_event_id', v_e.id, 'estimate_cents', v_e.estimate_cents, 'actual_cents', v_actual,
                            'charged_cents', v_charge, 'shortfall_cents', v_left,
                            'available_cents', bi_wallet_available_cents(v_e.wallet_id), 'repeat', false);
end;
$$;
comment on function bi_wallet_charge is 'BI-WAL-01 (prompt B8). Charges an estimated usage event after the AI action with the actual quantities, using the rates copied at the estimate: the actual price, or the estimate when the actual is more than 25% above it. Spends the oldest expiring lots first. A shortfall (the balance ran out during the action) is recorded and carried by Care Net, never charged later. Idempotent on the charge key; a repeat returns the first result. Service role only.';

create function bi_wallet_expire_lots(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_n int := 0;
  v_cents bigint := 0;
begin
  for r in
    select w.id as wallet_id, l.lot_id, l.remaining_cents
      from bi_wallet w cross join lateral bi_wallet_lots(w.id) l
     where l.expires_at <= p_now and l.remaining_cents > 0
  loop
    insert into bi_wallet_ledger (wallet_id, entry_kind, amount_cents, lot_id, idempotency_key, note)
    values (r.wallet_id, 'expiry', -r.remaining_cents, r.lot_id, 'expiry:' || r.lot_id, 'Value expired')
    on conflict (idempotency_key) do nothing;
    if found then
      v_n := v_n + 1;
      v_cents := v_cents + r.remaining_cents;
    end if;
  end loop;
  return jsonb_build_object('expired_lots', v_n, 'expired_cents', v_cents);
end;
$$;
comment on function bi_wallet_expire_lots is 'BI-WAL-01 (prompt B8). Writes an expiry row for the remainder of every lot past its expiry (included value after its rollover month, purchased value after 12 months). Idempotent per lot. The balance already ignores expired lots; this makes the statement show it.';

create function bi_wallet_set_cap(p_auth_user uuid, p_wallet_id uuid, p_cap_cents bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_w bi_wallet;
begin
  select * into v_w from bi_wallet where id = p_wallet_id for update;
  if v_w.id is null or not (bi_user_is_ops(p_auth_user)
       or 'company_admin' = any(bi_user_roles(p_auth_user, v_w.tenant_id, v_w.client_account_id))) then
    raise exception 'That wallet was not found.' using errcode = 'P0002';
  end if;
  if p_cap_cents is not null and p_cap_cents < 0 then
    raise exception 'A spend cap cannot be negative.';
  end if;
  update bi_wallet set monthly_spend_cap_cents = p_cap_cents where id = v_w.id;
  perform bi_audit(p_auth_user, 'wallet_cap_set', v_w.tenant_id, v_w.client_account_id, 'wallet', v_w.id,
                   jsonb_build_object('from', v_w.monthly_spend_cap_cents, 'to', p_cap_cents));
  return jsonb_build_object('wallet_id', v_w.id, 'monthly_spend_cap_cents', p_cap_cents);
end;
$$;
comment on function bi_wallet_set_cap is 'BI-WAL-01 (prompt B8, company wallet and spend caps). The company admin (or ops) sets or clears the monthly spend cap. Audited.';

create function bi_wallet_set_autotopup(p_auth_user uuid, p_wallet_id uuid, p_enabled boolean, p_saved_card_ref text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_w bi_wallet;
begin
  select * into v_w from bi_wallet where id = p_wallet_id for update;
  if v_w.id is null or not (bi_user_roles(p_auth_user, v_w.tenant_id, v_w.client_account_id) && array['inspector','company_admin']) then
    raise exception 'That wallet was not found.' using errcode = 'P0002';
  end if;
  if p_enabled and coalesce(p_saved_card_ref, v_w.saved_card_ref) is null then
    raise exception 'Automatic top up needs a saved card first.';
  end if;
  update bi_wallet
     set auto_topup_enabled = p_enabled,
         saved_card_ref = coalesce(p_saved_card_ref, saved_card_ref),
         auto_topup_opted_in_at = case when p_enabled then now() else auto_topup_opted_in_at end,
         auto_topup_opted_in_by = case when p_enabled then p_auth_user else auto_topup_opted_in_by end
   where id = v_w.id;
  perform bi_audit(p_auth_user, case when p_enabled then 'autotopup_opted_in' else 'autotopup_opted_out' end,
                   v_w.tenant_id, v_w.client_account_id, 'wallet', v_w.id, '{}'::jsonb);
  return jsonb_build_object('wallet_id', v_w.id, 'auto_topup_enabled', p_enabled);
end;
$$;
comment on function bi_wallet_set_autotopup is 'BI-WAL-01 (prompt B8). Opt in or out of automatic top up (R99,00 when the balance is below R20,00). Off unless the inspector or company admin switches it on. Audited.';

create function bi_autotopup_queue(p_limit int default 25)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc bi_rate_card := bi_rate_card_current('auto_topup');
  v_out jsonb := '[]'::jsonb;
  r record;
begin
  for r in
    select w.* from bi_wallet w
     where w.auto_topup_enabled and w.status = 'active' and w.saved_card_ref is not null
       and bi_wallet_available_cents(w.id) < coalesce(v_rc.threshold_cents, 2000)
     order by w.id limit greatest(1, least(coalesce(p_limit, 25), 200))
  loop
    -- At most one attempt per wallet per hour, whatever the gateway answers.
    if bi_rate_allow('autotopup', r.id::text, 1, 3600) then
      v_out := v_out || jsonb_build_array(jsonb_build_object('wallet_id', r.id, 'tenant_id', r.tenant_id,
                 'client_account_id', r.client_account_id, 'saved_card_ref', r.saved_card_ref,
                 'product_code', 'auto_topup', 'price_cents', v_rc.price_cents,
                 'idempotency_key', 'auto:' || r.id || ':' || to_char(now() at time zone 'UTC', 'YYYYMMDDHH24')));
    end if;
  end loop;
  return jsonb_build_object('due', v_out);
end;
$$;
comment on function bi_autotopup_queue is 'BI-WAL-01 (prompt B8). For autotopup-run (cron): opted in wallets with a saved card whose balance is below the threshold (R20,00), at most one attempt per wallet per hour, each with the idempotency key the gateway charge and the credit share. Service role only.';

-- 5. Store and payment receipts -------------------------------------------------------------------------

create function bi_iap_apply(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_provider text := p ->> 'provider';
  v_event text := p ->> 'event_id';
  v_type text := p ->> 'event_type';
  v_user uuid := nullif(p ->> 'auth_user_id', '')::uuid;
  v_product text := p ->> 'product_code';
  v_company uuid := nullif(p ->> 'client_account_id', '')::uuid;
  v_r bi_iap_receipt;
  v_me bi_app_user;
  v_rc bi_rate_card;
  v_line bi_company_subscription;
  v_wallet uuid;
  v_result jsonb := '{}'::jsonb;
  v_period date := coalesce(nullif(p ->> 'period_start', '')::date, current_date);
begin
  if v_provider not in ('revenuecat','ozow','saved_card','manual') or coalesce(length(v_event), 0) < 3 then
    raise exception 'bi_iap_apply: provider and event id are required' using errcode = '22023';
  end if;
  select * into v_r from bi_iap_receipt where provider = v_provider and external_event_id = v_event;
  if v_r.id is not null then
    return jsonb_build_object('receipt_id', v_r.id, 'status', v_r.status, 'repeat', true);
  end if;
  insert into bi_iap_receipt (provider, external_event_id, event_type, auth_user_id, product_code, amount_cents, payload_sha256, client_account_id)
  values (v_provider, v_event, coalesce(v_type, 'unknown'),
          (select u.id from auth.users u where u.id = v_user), v_product, nullif(p ->> 'amount_cents', '')::bigint,
          nullif(p ->> 'payload_sha256', ''), v_company)
  returning * into v_r;

  v_me := bi_app_user_of(v_user);
  v_rc := bi_rate_card_current(v_product);
  if v_me.id is null then
    update bi_iap_receipt set status = 'rejected', reject_reason = 'unknown user' where id = v_r.id;
    return jsonb_build_object('receipt_id', v_r.id, 'status', 'rejected', 'reason', 'unknown user', 'repeat', false);
  end if;
  if v_rc.id is null or v_rc.status <> 'confirmed' then
    update bi_iap_receipt set status = 'rejected', reject_reason = 'unknown product', tenant_id = v_me.tenant_id where id = v_r.id;
    return jsonb_build_object('receipt_id', v_r.id, 'status', 'rejected', 'reason', 'unknown product', 'repeat', false);
  end if;

  if v_rc.kind in ('topup','auto_topup') then
    -- A top up lands in the wallet of the tenant's base line unless a company is named.
    select s.* into v_line from bi_company_subscription s
     where s.tenant_id = v_me.tenant_id and s.status in ('trial','active','past_due')
       and (v_company is null and s.plan_code = 'base' or s.client_account_id = v_company)
     order by (s.plan_code = 'base') desc limit 1;
    if v_line.id is null then
      update bi_iap_receipt set status = 'rejected', reject_reason = 'no live line', tenant_id = v_me.tenant_id where id = v_r.id;
      return jsonb_build_object('receipt_id', v_r.id, 'status', 'rejected', 'reason', 'no live line', 'repeat', false);
    end if;
    v_wallet := bi_wallet_ensure(v_me.tenant_id, v_line.client_account_id);
    v_result := bi_wallet_topup_apply(v_wallet, v_product, v_provider || ':' || v_event, v_r.id);
  elsif v_rc.kind = 'plan' then
    if v_type in ('CANCELLATION','EXPIRATION','cancelled') then
      update bi_company_subscription set status = 'cancelled', cancelled_at = now()
       where tenant_id = v_me.tenant_id and client_account_id = v_company and status in ('trial','active','past_due');
      v_result := jsonb_build_object('cancelled', found);
    else
      if v_company is null then
        update bi_iap_receipt set status = 'rejected', reject_reason = 'no company named', tenant_id = v_me.tenant_id where id = v_r.id;
        return jsonb_build_object('receipt_id', v_r.id, 'status', 'rejected', 'reason', 'no company named', 'repeat', false);
      end if;
      select * into v_line from bi_company_subscription
       where tenant_id = v_me.tenant_id and client_account_id = v_company and status in ('trial','active','past_due') for update;
      if v_line.id is null then
        insert into bi_company_subscription (tenant_id, client_account_id, plan_code, status, price_cents, wallet_monthly_cents,
                                             storage_bytes, source, external_ref, current_period_start, current_period_end)
        values (v_me.tenant_id, v_company, v_product, 'active', v_rc.price_cents, v_rc.wallet_monthly_cents, v_rc.storage_bytes,
                v_provider, v_event, v_period, (v_period + interval '1 month')::date)
        returning * into v_line;
      else
        update bi_company_subscription set status = 'active', current_period_start = v_period,
               current_period_end = (v_period + interval '1 month')::date
         where id = v_line.id;
      end if;
      insert into bi_company (client_account_id, legal_name, prefilled_from_file)
      select a.id, a.company_name, true from msp_client_account a where a.id = v_company
      on conflict (client_account_id) do nothing;
      v_result := bi_wallet_grant_included(v_line.id, v_period);
    end if;
  end if;
  update bi_iap_receipt set status = 'applied', applied_at = now(), tenant_id = v_me.tenant_id, wallet_id = coalesce(v_wallet, (v_result ->> 'wallet_id')::uuid)
   where id = v_r.id;
  perform bi_audit(v_user, 'receipt_applied', v_me.tenant_id, v_company, 'iap_receipt', v_r.id,
                   jsonb_build_object('provider', v_provider, 'product_code', v_product, 'event_type', v_type));
  return jsonb_build_object('receipt_id', v_r.id, 'status', 'applied', 'result', v_result, 'repeat', false);
end;
$$;
comment on function bi_iap_apply is 'BI-WAL-01 (prompt B8). Applies one store or payment event, once per provider event id: a top up product credits its value to the line''s wallet (12 months); a plan product activates or renews the line on the named company (creating the onboarding record from the File company if missing) and credits the month''s included value; a cancellation or expiration ends the line. Unknown users, products or companies are recorded as rejected, never guessed. Service role only (revenuecat-webhook, ozow-notify, autotopup-run).';

-- 6. Welcome hook ----------------------------------------------------------------------------------------

create function bi_welcome_hook_grant(p_tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line bi_company_subscription;
  v_w uuid;
  v_lot bigint;
begin
  if not bi_flag_enabled('welcome_hook', p_tenant) then
    return jsonb_build_object('granted', false, 'reason', 'welcome_hook is off');
  end if;
  select * into v_line from bi_company_subscription where tenant_id = p_tenant and status in ('trial','active','past_due')
   order by (plan_code = 'base') desc limit 1;
  if v_line.id is null then
    return jsonb_build_object('granted', false, 'reason', 'no live line');
  end if;
  v_w := bi_wallet_ensure(p_tenant, v_line.client_account_id);
  v_lot := bi_wallet_credit(v_w, 'welcome_credit', 2000, now() + interval '12 months', 'welcome:' || p_tenant, null, 'Welcome value R20,00');
  update bi_tenant set welcome_inspections_left = 1 where id = p_tenant and welcome_inspections_left = 0
     and not exists (select 1 from bi_audit_log a where a.tenant_id = p_tenant and a.event = 'welcome_granted');
  perform bi_audit(null, 'welcome_granted', p_tenant, v_line.client_account_id, 'wallet', v_w, '{}'::jsonb)
   where not exists (select 1 from bi_audit_log a where a.tenant_id = p_tenant and a.event = 'welcome_granted');
  return jsonb_build_object('granted', true, 'wallet_id', v_w, 'lot_id', v_lot, 'amount_cents', 2000);
end;
$$;
comment on function bi_welcome_hook_grant is 'BI-WAL-01 (prompt A2, B8). Only while the welcome_hook flag is on for the tenant (off by default): R20,00 in the AI Wallet (12 months) and one free template inspection, once per tenant.';

-- 7. Storage ----------------------------------------------------------------------------------------------

create table bi_storage_meter (
  tenant_id uuid not null references bi_tenant(id),
  client_account_id uuid not null references msp_client_account(id),
  used_bytes bigint not null default 0,
  quota_bytes bigint not null default 0,
  level text not null default 'ok' check (level in ('ok','warn_80','warn_95','full')),
  full_since timestamptz,
  warned_80_at timestamptz,
  warned_95_at timestamptz,
  measured_at timestamptz not null default now(),
  primary key (tenant_id, client_account_id)
);
comment on table bi_storage_meter is 'BI-WAL-01 (prompt B8). Storage of one company line: photos and voice notes of the tenant on the company against the line''s 10 GB (plus packs once {{rate_card}} prices them). full_since is when it reached 100%: evidence captured before that still syncs; new evidence is refused. Written by the storage gate and bi_storage_meter_run only.';

create function bi_storage_used_bytes(p_tenant uuid, p_company uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select (coalesce((select sum(size_bytes) from bi_photo where tenant_id = p_tenant and client_account_id = p_company), 0)
        + coalesce((select sum(size_bytes) from bi_voice_note where tenant_id = p_tenant and client_account_id = p_company), 0))::bigint;
$$;

create function bi_storage_quota_bytes(p_tenant uuid, p_company uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(s.storage_bytes), 0)::bigint from bi_company_subscription s
   where s.tenant_id = p_tenant and s.client_account_id = p_company and s.status in ('trial','active','past_due');
$$;

create function bi_storage_status(p_tenant uuid, p_company uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('used_bytes', u, 'quota_bytes', q, 'level', bi_storage_level(u, q),
                            'pct', case when q > 0 then round(100.0 * u / q, 1) end)
    from (select bi_storage_used_bytes(p_tenant, p_company) as u, bi_storage_quota_bytes(p_tenant, p_company) as q) x;
$$;
comment on function bi_storage_status is 'BI-WAL-01. Used and quota bytes, level (ok, warn_80, warn_95, full) and percentage of a company line.';

create function bi_storage_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_used bigint;
  v_quota bigint;
  v_meter bi_storage_meter;
begin
  if tg_op = 'INSERT' and tg_when = 'BEFORE' then
    v_used := bi_storage_used_bytes(new.tenant_id, new.client_account_id);
    v_quota := bi_storage_quota_bytes(new.tenant_id, new.client_account_id);
    select * into v_meter from bi_storage_meter where tenant_id = new.tenant_id and client_account_id = new.client_account_id;
    if v_used >= v_quota and (v_meter.full_since is null or new.captured_at >= v_meter.full_since) then
      raise exception 'Storage is full for this company. New photos and voice notes wait until space is freed or added; viewing and syncing carry on.'
        using errcode = '53100';
    end if;
    return new;
  end if;
  -- AFTER INSERT: keep the meter current and note when 100% was reached.
  v_used := bi_storage_used_bytes(new.tenant_id, new.client_account_id);
  v_quota := bi_storage_quota_bytes(new.tenant_id, new.client_account_id);
  insert into bi_storage_meter (tenant_id, client_account_id, used_bytes, quota_bytes, level, full_since, measured_at)
  values (new.tenant_id, new.client_account_id, v_used, v_quota, bi_storage_level(v_used, v_quota),
          case when v_used >= v_quota then now() end, now())
  on conflict (tenant_id, client_account_id) do update
     set used_bytes = excluded.used_bytes, quota_bytes = excluded.quota_bytes, level = excluded.level,
         full_since = case when excluded.used_bytes >= excluded.quota_bytes then coalesce(bi_storage_meter.full_since, now()) end,
         measured_at = now();
  return null;
end;
$$;
comment on function bi_storage_gate is 'BI-WAL-01 (prompt B8). Before a photo or voice note is stored: refused (SQLSTATE 53100) when the line is at 100% and the evidence was captured after it filled; evidence captured earlier (offline) still syncs. After: updates the meter.';
create trigger bi_photo_storage_gate before insert on bi_photo for each row execute function bi_storage_gate();
create trigger bi_photo_storage_meter after insert on bi_photo for each row execute function bi_storage_gate();
create trigger bi_voice_note_storage_gate before insert on bi_voice_note for each row execute function bi_storage_gate();
create trigger bi_voice_note_storage_meter after insert on bi_voice_note for each row execute function bi_storage_gate();

create function bi_storage_meter_run()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_level text;
  v_warn jsonb := '[]'::jsonb;
  v_old bi_storage_meter;
begin
  for r in
    select distinct s.tenant_id, s.client_account_id from bi_company_subscription s where s.status in ('trial','active','past_due')
  loop
    select * into v_old from bi_storage_meter where tenant_id = r.tenant_id and client_account_id = r.client_account_id;
    insert into bi_storage_meter (tenant_id, client_account_id, used_bytes, quota_bytes, level, measured_at)
    values (r.tenant_id, r.client_account_id, bi_storage_used_bytes(r.tenant_id, r.client_account_id),
            bi_storage_quota_bytes(r.tenant_id, r.client_account_id), 'ok', now())
    on conflict (tenant_id, client_account_id) do update
       set used_bytes = excluded.used_bytes, quota_bytes = excluded.quota_bytes, measured_at = now();
    update bi_storage_meter m
       set level = bi_storage_level(m.used_bytes, m.quota_bytes),
           full_since = case when m.used_bytes >= m.quota_bytes then coalesce(m.full_since, now()) end,
           warned_80_at = case when m.used_bytes * 100 >= m.quota_bytes * 80 then coalesce(m.warned_80_at, now()) end,
           warned_95_at = case when m.used_bytes * 100 >= m.quota_bytes * 95 then coalesce(m.warned_95_at, now()) end
     where m.tenant_id = r.tenant_id and m.client_account_id = r.client_account_id
    returning m.level into v_level;
    if v_level <> 'ok' and v_level is distinct from coalesce(v_old.level, 'ok') then
      v_warn := v_warn || jsonb_build_array(jsonb_build_object('tenant_id', r.tenant_id, 'client_account_id', r.client_account_id,
                  'level', v_level, 'status', bi_storage_status(r.tenant_id, r.client_account_id)));
    end if;
  end loop;
  return jsonb_build_object('warnings', v_warn);
end;
$$;
comment on function bi_storage_meter_run is 'BI-WAL-01 (prompt B8). For storage-meter (cron): recomputes every live line, records when 80%, 95% and 100% were first reached (cleared again below) and returns the lines whose level rose since the last run, for the warning messages. Service role only.';

-- 8. Row Level Security ----------------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array['bi_rate_card','bi_wallet','bi_wallet_ledger','bi_usage_event','bi_iap_receipt','bi_storage_meter'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from public, anon, authenticated', t);
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;
grant select on bi_rate_card, bi_wallet, bi_wallet_ledger, bi_usage_event, bi_storage_meter to authenticated;

create policy bi_rate_card_read on bi_rate_card for select to authenticated
  using (bi_is_ops() or kind in ('plan','topup','auto_topup','storage_pack'));
create policy bi_wallet_read on bi_wallet for select to authenticated
  using (bi_can(tenant_id, client_account_id, 'read_wallet'));
create policy bi_wallet_ledger_read on bi_wallet_ledger for select to authenticated
  using (exists (select 1 from bi_wallet w where w.id = wallet_id and bi_can(w.tenant_id, w.client_account_id, 'read_wallet')));
create policy bi_usage_event_read on bi_usage_event for select to authenticated
  using (bi_can(tenant_id, client_account_id, 'read_wallet'));
create policy bi_storage_meter_read on bi_storage_meter for select to authenticated
  using (bi_can(tenant_id, client_account_id, 'read_capture'));
-- bi_iap_receipt: no authenticated policy (ops read it through the service role).

do $$
declare
  f text;
begin
  foreach f in array array['bi_rate_card_current(text)','bi_wallet_lots(uuid)','bi_wallet_available_cents(uuid, timestamptz)',
                           'bi_wallet_balance(uuid)','bi_wallet_credit(uuid, text, bigint, timestamptz, text, uuid, text)',
                           'bi_wallet_ensure(uuid, uuid)','bi_wallet_grant_included(uuid, date)','bi_wallet_topup_apply(uuid, text, text, uuid)',
                           'bi_photo_tags_used(uuid)','bi_wallet_estimate(uuid, jsonb)','bi_wallet_charge(uuid, jsonb)',
                           'bi_wallet_expire_lots(timestamptz)','bi_wallet_set_cap(uuid, uuid, bigint)',
                           'bi_wallet_set_autotopup(uuid, uuid, boolean, text)','bi_autotopup_queue(int)','bi_iap_apply(jsonb)',
                           'bi_welcome_hook_grant(uuid)','bi_storage_used_bytes(uuid, uuid)','bi_storage_quota_bytes(uuid, uuid)',
                           'bi_storage_status(uuid, uuid)','bi_storage_meter_run()'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array['bi_price_cents(bigint, bigint, bigint, numeric, numeric, numeric, numeric, numeric)',
                           'bi_charge_rule_cents(bigint, bigint)','bi_storage_level(bigint, bigint)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  foreach f in array array['bi_usage_event_guard()','bi_storage_gate()'] loop
    execute format('revoke execute on function %s from public, anon', f);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
