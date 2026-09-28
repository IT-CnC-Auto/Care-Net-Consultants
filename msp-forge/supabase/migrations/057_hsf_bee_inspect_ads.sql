-- CNC HSF FORGE | HSF-ADS-01 v1.0.0 | Bee-Inspect banner events (first party, no personal information) 24/09/2026
-- Built to hsf/BUILD-CONTRACT.md 16.3 (Amendment 8, Bee-Inspect P1) and section
-- A4 of hsf/BEE-INSPECT-BUILD-PROMPT.md.
--
-- What this migration does:
--   1. hsf_ad_event: one row per banner event the File site reports through
--      POST /api/hsf-events (vercel/api/hsf-events.js). A row holds only the
--      event, the banner id, its variant, the page, the File's industry code
--      and a band of Section F counts, with the time. No user id, no email, no
--      company, no IP address, no cookie, no document content: nothing that
--      identifies a person or a company. Append only (updates and deletes are
--      refused).
--   2. hsf_ad_event_record(p jsonb): the only way in. Service role only (the
--      Vercel function calls it). It refuses any key it does not know, checks
--      every value, and drops the event (accepted false) once the site has
--      reported more than 1 200 events in the last minute, so a flood cannot
--      fill the table.
--   3. hsf_ad_event_summary(p_days int): counts per banner, variant, page and
--      event for the funnel. Service role only.
--
-- Events: the browser may report ad_impression, ad_click, ad_dismiss and
-- ad_qr_shown. claim_code_created, claim_code_scanned, install, trial_start and
-- subscribe are reserved here for the server side sources P3 builds (claim
-- codes, store installs, subscriptions); /api/hsf-events refuses them from a
-- browser.
--
-- Left to P3 (hsf/BEE-INSPECT-BUILD-PROMPT.md section 6): ad_config (the per
-- tenant hide or rebrand toggle, which needs the tenant and company tables) and
-- ad_dismissal (a dismissal kept per signed in user, which needs a user
-- reference this table deliberately does not hold). Until then the toggle is a
-- stub in vercel/js/cnc-ad.js and a dismissal lives in the visitor's browser
-- for 14 days.
--
-- Not applied to the live project without the Director's confirmation
-- (contract 16.3). Until it is, /api/hsf-events answers 202 and drops the event.
-- Migrations 001 to 056 are unchanged. Idempotent where it can be: the table and
-- index are created if missing; functions are replaced.

-- 1. The event table ----------------------------------------------------------------

create table if not exists hsf_ad_event (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  event text not null check (event in ('ad_impression','ad_click','ad_dismiss','ad_qr_shown',
    'claim_code_created','claim_code_scanned','install','trial_start','subscribe')),
  ad_id text not null check (ad_id ~ '^AD-(0[1-9]|10)$'),
  variant text not null check (variant ~ '^[a-z0-9_]{1,24}$'),
  page text not null check (page in ('/hsf-builder','/health-and-safety-file','/portal','/bee-inspect')),
  industry text check (industry ~ '^[A-Z][A-Z0-9_]{1,15}$'),
  f_band text check (f_band in ('na','0','1to2','3to5','6plus'))
);
comment on table hsf_ad_event is 'HSF-ADS-01 (migration 057). First party Bee-Inspect banner events from the File site: event, banner id, variant, page, industry code and a band of Section F counts. Never a user, company, email, IP address, cookie or document content. Append only. Written only through hsf_ad_event_record (service role).';
create index if not exists hsf_ad_event_time_idx on hsf_ad_event(occurred_at);

create or replace function hsf_ad_event_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'hsf_ad_event is append only';
end;
$$;
drop trigger if exists hsf_ad_event_append_only on hsf_ad_event;
create trigger hsf_ad_event_append_only
  before update or delete on hsf_ad_event
  for each row execute function hsf_ad_event_guard();

-- RLS on, no policy for anon or authenticated: nobody but the service role reads
-- or writes a row.
alter table hsf_ad_event enable row level security;
revoke all on hsf_ad_event from public, anon, authenticated;
grant all on hsf_ad_event to service_role;

-- 2. The one way in -----------------------------------------------------------------

create or replace function hsf_ad_event_record(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_event text;
  v_ad text;
  v_variant text;
  v_page text;
  v_industry text;
  v_band text;
  v_id bigint;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'hsf_ad_event_record: an object is required' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key not in ('event','ad_id','variant','page','industry','f_band') then
      raise exception 'hsf_ad_event_record: unknown key %', v_key using errcode = '22023';
    end if;
  end loop;
  for v_key in select k from jsonb_each(p) as e(k, v) where jsonb_typeof(v) not in ('string','null') loop
    raise exception 'hsf_ad_event_record: % must be text', v_key using errcode = '22023';
  end loop;

  v_event := p ->> 'event';
  v_ad := p ->> 'ad_id';
  v_variant := p ->> 'variant';
  v_page := p ->> 'page';
  v_industry := nullif(p ->> 'industry', '');
  v_band := nullif(p ->> 'f_band', '');

  if v_event is null or v_event not in ('ad_impression','ad_click','ad_dismiss','ad_qr_shown',
      'claim_code_created','claim_code_scanned','install','trial_start','subscribe') then
    raise exception 'hsf_ad_event_record: unknown event' using errcode = '22023';
  end if;
  if v_ad is null or v_ad !~ '^AD-(0[1-9]|10)$' then
    raise exception 'hsf_ad_event_record: unknown banner' using errcode = '22023';
  end if;
  if v_variant is null or v_variant !~ '^[a-z0-9_]{1,24}$' then
    raise exception 'hsf_ad_event_record: bad variant' using errcode = '22023';
  end if;
  if v_page is null or v_page not in ('/hsf-builder','/health-and-safety-file','/portal','/bee-inspect') then
    raise exception 'hsf_ad_event_record: unknown page' using errcode = '22023';
  end if;
  if v_industry is not null and v_industry !~ '^[A-Z][A-Z0-9_]{1,15}$' then
    raise exception 'hsf_ad_event_record: bad industry code' using errcode = '22023';
  end if;
  if v_band is not null and v_band not in ('na','0','1to2','3to5','6plus') then
    raise exception 'hsf_ad_event_record: bad Section F band' using errcode = '22023';
  end if;

  -- A flood is dropped, never stored.
  if (select count(*) from hsf_ad_event where occurred_at > now() - interval '1 minute') >= 1200 then
    return jsonb_build_object('accepted', false, 'reason', 'rate');
  end if;

  insert into hsf_ad_event (event, ad_id, variant, page, industry, f_band)
  values (v_event, v_ad, v_variant, v_page, v_industry, v_band)
  returning id into v_id;
  return jsonb_build_object('accepted', true, 'id', v_id);
end;
$$;
revoke execute on function hsf_ad_event_record(jsonb) from public, anon, authenticated;
grant execute on function hsf_ad_event_record(jsonb) to service_role;
comment on function hsf_ad_event_record is 'HSF-ADS-01 (migration 057). Server side only (/api/hsf-events): records one Bee-Inspect banner event. Keys event, ad_id, variant, page, industry and f_band only, each text or null; anything else is refused (22023). Drops the event (accepted false, reason rate) once 1 200 events arrived in the last minute. Returns {accepted, id}.';

-- 3. The funnel ----------------------------------------------------------------------

create or replace function hsf_ad_event_summary(p_days int default 30)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('ad_id', ad_id, 'variant', variant, 'page', page, 'event', event, 'count', n)
           order by ad_id, variant, page, event), '[]'::jsonb)
  from (select ad_id, variant, page, event, count(*) as n
          from hsf_ad_event
         where occurred_at > now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 366)))
         group by ad_id, variant, page, event) s;
$$;
revoke execute on function hsf_ad_event_summary(int) from public, anon, authenticated;
grant execute on function hsf_ad_event_summary(int) to service_role;
comment on function hsf_ad_event_summary is 'HSF-ADS-01 (migration 057). Counts of Bee-Inspect banner events per banner, variant, page and event over the last p_days (1 to 366, default 30). Service role only.';

notify pgrst, 'reload schema';
