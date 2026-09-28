-- CNC HSF FORGE | HSF-ADS-02 v1.0.0 | Bee-Inspect attribution (UTM kept through the sign in link) 25/09/2026
-- Built to hsf/BUILD-CONTRACT.md 16 (Amendment 8, Bee-Inspect P2, site pages)
-- and section A3 of hsf/BEE-INSPECT-BUILD-PROMPT.md ("Keep UTM through magic
-- link; store on first sign in").
--
-- Why a new migration: hsf_ad_event (057) cannot hold this. Its event check
-- names only the banner events, ad_id is required and must be a banner id, and
-- it has no column for a campaign tag. 057 is applied to the live project and
-- stays byte identical, so the attribution record gets its own small table.
--
-- What this migration does:
--   1. hsf_attribution_event: one row each time a visitor who arrived on the
--      File site from a tagged link (utm_source, utm_medium, utm_campaign,
--      utm_content, utm_term) signs in to the File builder for the first time
--      in that visit. A row holds only the event name (attribution_seen), the
--      page it was recorded on and the five campaign tags, with the time. No
--      user id, no email, no company, no IP address, no cookie: the tags say
--      which link brought a visit, never who made it. Append only.
--   2. hsf_attribution_record(p jsonb): the only way in. Service role only
--      (POST /api/hsf-events, event attribution_seen, calls it). It refuses any
--      key it does not know, checks every value against the same shape the
--      page and the endpoint enforce (letters, digits, dot, underscore and
--      hyphen, 1 to 64 characters: no @, so no email address fits), and drops
--      the event (accepted false) once 600 arrived in the last minute.
--   3. hsf_attribution_summary(p_days int): counts per source, medium,
--      campaign and content. Service role only.
--
-- Not applied to the live project without the Director's confirmation. Until it
-- is, /api/hsf-events answers 202 and drops an attribution_seen event, exactly
-- as it did for banner events before 057. Migrations 001 to 057 are unchanged.
-- Idempotent where it can be: the table and index are created if missing;
-- functions are replaced.

-- 1. The table ------------------------------------------------------------------------

create table if not exists hsf_attribution_event (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  event text not null default 'attribution_seen' check (event in ('attribution_seen')),
  page text not null check (page in ('/hsf-builder','/health-and-safety-file','/bee-inspect','/get-app','/portal')),
  utm_source text check (utm_source ~ '^[A-Za-z0-9._-]{1,64}$'),
  utm_medium text check (utm_medium ~ '^[A-Za-z0-9._-]{1,64}$'),
  utm_campaign text check (utm_campaign ~ '^[A-Za-z0-9._-]{1,64}$'),
  utm_content text check (utm_content ~ '^[A-Za-z0-9._-]{1,64}$'),
  utm_term text check (utm_term ~ '^[A-Za-z0-9._-]{1,64}$'),
  constraint hsf_attribution_event_has_tag check (coalesce(utm_source, utm_medium, utm_campaign, utm_content, utm_term) is not null)
);
comment on table hsf_attribution_event is 'HSF-ADS-02 (migration 058). First party attribution from the File site: the campaign tags (utm_source, utm_medium, utm_campaign, utm_content, utm_term) of the link that brought a visit, recorded once when that visitor first signs in to the File builder. Never a user, company, email, IP address or cookie. Append only. Written only through hsf_attribution_record (service role).';
create index if not exists hsf_attribution_event_time_idx on hsf_attribution_event(occurred_at);

create or replace function hsf_attribution_event_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'hsf_attribution_event is append only';
end;
$$;
drop trigger if exists hsf_attribution_event_append_only on hsf_attribution_event;
create trigger hsf_attribution_event_append_only
  before update or delete on hsf_attribution_event
  for each row execute function hsf_attribution_event_guard();

-- RLS on, no policy: nobody but the service role reads or writes a row.
alter table hsf_attribution_event enable row level security;
revoke all on hsf_attribution_event from public, anon, authenticated;
grant all on hsf_attribution_event to service_role;

-- 2. The one way in -----------------------------------------------------------------

create or replace function hsf_attribution_record(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_page text;
  v_tags text[];
  v_tag text;
  v_id bigint;
  k_names constant text[] := array['utm_source','utm_medium','utm_campaign','utm_content','utm_term'];
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'hsf_attribution_record: an object is required' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key not in ('event','page','utm_source','utm_medium','utm_campaign','utm_content','utm_term') then
      raise exception 'hsf_attribution_record: unknown key %', v_key using errcode = '22023';
    end if;
  end loop;
  for v_key in select k from jsonb_each(p) as e(k, v) where jsonb_typeof(v) not in ('string','null') loop
    raise exception 'hsf_attribution_record: % must be text', v_key using errcode = '22023';
  end loop;

  if coalesce(p ->> 'event', '') <> 'attribution_seen' then
    raise exception 'hsf_attribution_record: unknown event' using errcode = '22023';
  end if;
  v_page := p ->> 'page';
  if v_page is null or v_page not in ('/hsf-builder','/health-and-safety-file','/bee-inspect','/get-app','/portal') then
    raise exception 'hsf_attribution_record: unknown page' using errcode = '22023';
  end if;
  v_tags := array[]::text[];
  foreach v_key in array k_names loop
    v_tag := nullif(p ->> v_key, '');
    if v_tag is not null and v_tag !~ '^[A-Za-z0-9._-]{1,64}$' then
      raise exception 'hsf_attribution_record: bad %', v_key using errcode = '22023';
    end if;
    v_tags := v_tags || v_tag;
  end loop;
  if coalesce(v_tags[1], v_tags[2], v_tags[3], v_tags[4], v_tags[5]) is null then
    raise exception 'hsf_attribution_record: no campaign tag' using errcode = '22023';
  end if;

  -- A flood is dropped, never stored.
  if (select count(*) from hsf_attribution_event where occurred_at > now() - interval '1 minute') >= 600 then
    return jsonb_build_object('accepted', false, 'reason', 'rate');
  end if;

  insert into hsf_attribution_event (event, page, utm_source, utm_medium, utm_campaign, utm_content, utm_term)
  values ('attribution_seen', v_page, v_tags[1], v_tags[2], v_tags[3], v_tags[4], v_tags[5])
  returning id into v_id;
  return jsonb_build_object('accepted', true, 'id', v_id);
end;
$$;
revoke execute on function hsf_attribution_record(jsonb) from public, anon, authenticated;
grant execute on function hsf_attribution_record(jsonb) to service_role;
comment on function hsf_attribution_record is 'HSF-ADS-02 (migration 058). Server side only (/api/hsf-events, event attribution_seen): records the campaign tags of one visit at its first sign in. Keys event, page, utm_source, utm_medium, utm_campaign, utm_content and utm_term only, each text or null, at least one tag; anything else is refused (22023). Drops the event (accepted false, reason rate) once 600 arrived in the last minute. Returns {accepted, id}.';

-- 3. The funnel ----------------------------------------------------------------------

create or replace function hsf_attribution_summary(p_days int default 30)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('utm_source', utm_source, 'utm_medium', utm_medium, 'utm_campaign', utm_campaign,
           'utm_content', utm_content, 'count', n) order by utm_source, utm_medium, utm_campaign, utm_content), '[]'::jsonb)
  from (select utm_source, utm_medium, utm_campaign, utm_content, count(*) as n
          from hsf_attribution_event
         where occurred_at > now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 366)))
         group by utm_source, utm_medium, utm_campaign, utm_content) s;
$$;
revoke execute on function hsf_attribution_summary(int) from public, anon, authenticated;
grant execute on function hsf_attribution_summary(int) to service_role;
comment on function hsf_attribution_summary is 'HSF-ADS-02 (migration 058). Counts of first sign ins per utm_source, utm_medium, utm_campaign and utm_content over the last p_days (1 to 366, default 30). Service role only.';

notify pgrst, 'reload schema';
