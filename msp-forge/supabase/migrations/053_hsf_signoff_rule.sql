-- CNC MSP FORGE | HSF-REV-02 v1.0.0 | HSF File sign off: who may sign, and what release checks 23/09/2026
-- Built to hsf/BUILD-CONTRACT.md section 10.8, with hsf/SIGNOFF-CRITERIA.md
-- sections 3 to 6 as the rule. Amends SPEC B4.5 (review and release).
--
-- What this migration does:
--   1. The Occupational Medical Practitioner is no longer a File signatory
--      (SIGNOFF-CRITERIA 2.4, 3.1, 3.2). The value omp_medical stays allowed in
--      the kind check so earlier rows keep their history, but a new omp_medical
--      row is refused: the OMP signed medical surveillance plan is Section E
--      evidence, not a sign off. The release gate no longer asks for it.
--   2. New kind ceo_16_1_acknowledgement: the chief executive's acknowledgement,
--      recorded and never a release gate (SIGNOFF-CRITERIA 3.3, section 4).
--   3. hsf_signatory: the credential record of a safety content signatory
--      (SIGNOFF-CRITERIA 6.1 and 6.1.1). A safety_content sign off references
--      it through hsf_signoff.signatory_id; the sign off keeps its own scope.
--   4. hsf_signoff_rule: which registering body and category may sign the
--      safety content of a File, by industry (SIGNOFF-CRITERIA section 5).
--   5. hsf_signatory_fit: the one definition of whether a safety content sign
--      off can release its File (SIGNOFF-CRITERIA 6.2), and hsf_release_gate
--      redefined to use it. The citability rule of 047 and 050 is kept exactly.
--
-- Design choice: a separate hsf_signatory table rather than credential columns
-- on hsf_signoff. The credentials belong to the practitioner, not to one File:
-- one practitioner signs many Files and revisions, and the register check and
-- the two letters are recorded once and reused. A renewal is a new row with its
-- new expiry, and a row relied on by a released revision is frozen, so every
-- release keeps the credentials it was decided on. hsf_signoff stays one narrow
-- row per decision, and the client acceptance and chief executive rows carry no
-- practitioner columns. No identity number is stored (SIGNOFF-CRITERIA 6.3).
--
-- Migrations 047 to 052 are not edited: every changed function is redefined
-- here with create or replace, keeping security definer, the fixed search path
-- and service role only execute. The hsf_release_gate trigger of 047 stays and
-- calls the redefined function.

-- 1. hsf_signatory (SIGNOFF-CRITERIA 6.1, 6.1.1, 6.3) -------------------------------------------

create table hsf_signatory (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(btrim(full_name)) > 0),
  registration_body text not null check (registration_body in ('SACPCMP','SAIOSH')),
  category text not null,
  registration_number text not null check (length(btrim(registration_number)) > 0),
  registration_expires_on date not null,
  register_checked_on date,
  register_proof_ref text,
  appointment_letter_ref text,
  appointment_letter_date date,
  appointment_letter_recruitment_portal_ref text,
  engagement_letter_ref text,
  engagement_letter_date date,
  engagement_letter_recruitment_portal_ref text,
  created_by text not null default 'service_role',
  created_at timestamptz not null default now(),
  constraint hsf_signatory_category_fits_body check (
    (registration_body = 'SACPCMP' and category in ('Pr CHSA','CHSM','CHSO','Can CHSA','Can CHSM','Can CHSO'))
    or (registration_body = 'SAIOSH' and category in ('TechSAIOSH','GradSAIOSH','CMSAIOSH'))),
  constraint hsf_signatory_register_check_pair check ((register_checked_on is null) = (register_proof_ref is null)),
  constraint hsf_signatory_appointment_letter_pair check ((appointment_letter_ref is null) = (appointment_letter_date is null)),
  constraint hsf_signatory_engagement_letter_pair check ((engagement_letter_ref is null) = (engagement_letter_date is null)),
  unique (registration_body, registration_number, registration_expires_on)
);
comment on table hsf_signatory is 'HSF-REV-02, contract 10.8 (SIGNOFF-CRITERIA 6.1, 6.1.1, 6.3). The credential record of a registered health and safety practitioner who signs the safety content of a File: registering body and category, registration number and expiry, the public register check with its saved proof, and the appointment and engagement letters. One row per registration period: a renewal is a new row. A row relied on by a released File revision is frozen (hsf_signatory_guard). No identity number is stored; the registration number identifies the practitioner. Staff read; writes by the service role only.';
comment on column hsf_signatory.full_name is 'The practitioner''s full name as it appears on the register of the body.';
comment on column hsf_signatory.registration_number is 'The registration or membership number with the body. It identifies the practitioner; no identity number is stored (SIGNOFF-CRITERIA 6.3).';
comment on column hsf_signatory.registration_body is 'SACPCMP (the statutory body for construction health and safety) or SAIOSH (a professional body; its designations are voluntary).';
comment on column hsf_signatory.category is 'SACPCMP: Pr CHSA, CHSM, CHSO and the candidate categories Can CHSA, Can CHSM, Can CHSO. SAIOSH: TechSAIOSH, GradSAIOSH, CMSAIOSH. Candidate categories are recorded but never sign a File alone (hsf_signoff_rule lists none).';
comment on column hsf_signatory.registration_expires_on is 'The expiry or renewal date of the registration or designation. A sign off decided after this date cannot release a File.';
comment on column hsf_signatory.register_checked_on is 'The date the public register of the body was checked for this registration. Must be on or before the decision date of a sign off that releases a File.';
comment on column hsf_signatory.register_proof_ref is 'Reference to the saved proof of the register check (for example a stored screenshot or PDF). Recorded together with register_checked_on.';
comment on column hsf_signatory.appointment_letter_ref is 'Document reference of the written appointment letter. Recorded together with appointment_letter_date; a missing letter refuses the release.';
comment on column hsf_signatory.appointment_letter_date is 'Date of the appointment letter. Must be on or before the decision date of a sign off that releases a File.';
comment on column hsf_signatory.appointment_letter_recruitment_portal_ref is 'Record identifier of the appointment letter in Care Net''s recruitment portal, once the portal exposes it. Null until then; the letter is uploaded and referenced by hand meanwhile. May be added after a release.';
comment on column hsf_signatory.engagement_letter_ref is 'Document reference of the engagement letter. Recorded together with engagement_letter_date; a missing letter refuses the release.';
comment on column hsf_signatory.engagement_letter_date is 'Date of the engagement letter. Must be on or before the decision date of a sign off that releases a File.';
comment on column hsf_signatory.engagement_letter_recruitment_portal_ref is 'Record identifier of the engagement letter in Care Net''s recruitment portal, once the portal exposes it. Null until then. May be added after a release.';
comment on column hsf_signatory.created_by is 'Who recorded the credentials: a staff email or service_role.';

create or replace function hsf_signatory_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mutable constant text[] := array['appointment_letter_recruitment_portal_ref','engagement_letter_recruitment_portal_ref'];
begin
  -- Only a row relied on by a released revision is frozen; before a release the
  -- credentials may be corrected, because the gate reads them at release time.
  if not exists (select 1
                   from hsf_signoff so
                   join hsf_release r on r.file_id = so.file_id and r.revision = so.revision
                  where so.signatory_id = old.id
                    and so.kind = 'safety_content' and so.decision = 'approved') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' then
    raise exception 'hsf_signatory: these credentials support a released File and cannot be deleted';
  end if;
  if (to_jsonb(new) - v_mutable) is distinct from (to_jsonb(old) - v_mutable) then
    raise exception 'hsf_signatory: these credentials support a released File and are frozen; record a renewal or a correction as a new signatory row';
  end if;
  if (old.appointment_letter_recruitment_portal_ref is not null
      and new.appointment_letter_recruitment_portal_ref is distinct from old.appointment_letter_recruitment_portal_ref)
     or (old.engagement_letter_recruitment_portal_ref is not null
      and new.engagement_letter_recruitment_portal_ref is distinct from old.engagement_letter_recruitment_portal_ref) then
    raise exception 'hsf_signatory: a recruitment portal reference on credentials that support a released File is set once and never changed';
  end if;
  return new;
end;
$$;
revoke execute on function hsf_signatory_guard() from public, anon, authenticated;
comment on function hsf_signatory_guard is 'Contract 10.8. Freezes a hsf_signatory row once an approved safety_content sign off that relies on it has released a File revision: no delete, and no change except adding each recruitment portal reference once. Before a release the row may be corrected.';

create trigger hsf_signatory_guard
  before update or delete on hsf_signatory
  for each row execute function hsf_signatory_guard();
comment on trigger hsf_signatory_guard on hsf_signatory is 'Contract 10.8. Freezes credentials relied on by a released File revision (hsf_signatory_guard).';

-- 2. hsf_signoff: kinds, the signatory reference and the scope -----------------------------------

alter table hsf_signoff drop constraint if exists hsf_signoff_kind_check;
alter table hsf_signoff add constraint hsf_signoff_kind_check check (kind in
  ('omp_medical','safety_content','client_16_2_acceptance','ceo_16_1_acknowledgement'));

alter table hsf_signoff drop constraint if exists decision_complete;
alter table hsf_signoff add constraint decision_complete check (decision is null or
  (signatory_name is not null and decided_at is not null
   and (kind in ('client_16_2_acceptance','ceo_16_1_acknowledgement') or registration_number is not null)));

alter table hsf_signoff
  add column if not exists signatory_id uuid references hsf_signatory(id),
  add column if not exists scope text;
alter table hsf_signoff add constraint hsf_signoff_signatory_is_safety
  check (signatory_id is null or kind = 'safety_content');
alter table hsf_signoff add constraint hsf_signoff_safety_decision_complete
  check (kind <> 'safety_content' or decision is null
         or (signatory_id is not null and length(btrim(coalesce(scope, ''))) > 0));
create index if not exists hsf_signoff_signatory_idx on hsf_signoff(signatory_id);

comment on table hsf_signoff is 'HSF-REV-01, amended by HSF-REV-02 (contract 10.8, SIGNOFF-CRITERIA section 4). The sign offs of a File revision. Release needs an approved safety_content sign off by a registered practitioner whose body and category fit the File (hsf_signoff_rule) and an approved client_16_2_acceptance. ceo_16_1_acknowledgement is recorded, not a gate. omp_medical is kept for history only: new rows are refused, because the OMP signed medical surveillance plan is Section E evidence, not a File sign off.';
comment on column hsf_signoff.kind is 'safety_content (registered practitioner, required), client_16_2_acceptance (the client''s section 16(2) appointee, required), ceo_16_1_acknowledgement (the client''s chief executive, recorded, not a gate). omp_medical: history only, refused for new rows.';
comment on column hsf_signoff.signatory_id is 'Contract 10.8. The credential record (hsf_signatory) of the practitioner who decides a safety_content sign off. Required once a safety_content row carries a decision; only safety_content rows carry it. signatory_name, registration_body and registration_number are copied from it.';
comment on column hsf_signoff.scope is 'SIGNOFF-CRITERIA 6.1. The scope of the sign off in words (for example the sections and sites it covers). Required once a safety_content row carries a decision.';

create or replace function hsf_signoff_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sig hsf_signatory;
begin
  if new.kind = 'omp_medical' and (tg_op = 'INSERT' or old.kind is distinct from 'omp_medical') then
    raise exception 'hsf_signoff: the Occupational Medical Practitioner is not a File signatory. File the OMP signed medical surveillance plan in Section E as evidence instead';
  end if;
  if new.signatory_id is not null then
    select * into v_sig from hsf_signatory where id = new.signatory_id;
    new.signatory_name := v_sig.full_name;
    new.registration_body := v_sig.registration_body;
    new.registration_number := v_sig.registration_number;
  end if;
  return new;
end;
$$;
revoke execute on function hsf_signoff_guard() from public, anon, authenticated;
comment on function hsf_signoff_guard is 'Contract 10.8. Refuses a new omp_medical sign off (the OMP signed plan is Section E evidence) and copies the signatory name, registering body and registration number of a safety_content sign off from its hsf_signatory row, so the two never disagree.';

create trigger hsf_signoff_guard
  before insert or update on hsf_signoff
  for each row execute function hsf_signoff_guard();
comment on trigger hsf_signoff_guard on hsf_signoff is 'Contract 10.8. Refuses new omp_medical sign offs and copies the safety content signatory''s name, body and number (hsf_signoff_guard).';

create or replace function hsf_signatory_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Reached only for a row that is not frozen (hsf_signatory_guard), so every
  -- sign off it touches is of a revision not yet released.
  if (new.full_name, new.registration_body, new.registration_number)
     is distinct from (old.full_name, old.registration_body, old.registration_number) then
    update hsf_signoff
       set signatory_name = new.full_name,
           registration_body = new.registration_body,
           registration_number = new.registration_number
     where signatory_id = new.id;
  end if;
  return null;
end;
$$;
revoke execute on function hsf_signatory_sync() from public, anon, authenticated;
comment on function hsf_signatory_sync is 'Contract 10.8. After a correction to a hsf_signatory row that is not yet frozen, copies the corrected name, body and registration number onto the sign offs that reference it, so hsf_signoff never disagrees with its credential record.';

create trigger hsf_signatory_sync
  after update on hsf_signatory
  for each row execute function hsf_signatory_sync();
comment on trigger hsf_signatory_sync on hsf_signatory is 'Contract 10.8. Keeps the copied signatory fields of unreleased sign offs in step with a corrected credential record (hsf_signatory_sync).';

-- 3. hsf_signoff_rule (SIGNOFF-CRITERIA section 5) -------------------------------------------------

create table hsf_signoff_rule (
  id uuid primary key default gen_random_uuid(),
  file_type text not null check (file_type in ('construction','mining','general')),
  industry_id uuid references msp_industry(id),
  registration_body text not null check (registration_body in ('SACPCMP','SAIOSH')),
  category text not null,
  practitioner_review boolean not null default false,
  note text not null,
  constraint hsf_signoff_rule_general_has_no_industry check ((file_type = 'general') = (industry_id is null)),
  constraint hsf_signoff_rule_no_candidates check (category not like 'Can %'),
  constraint hsf_signoff_rule_category_fits_body check (
    (registration_body = 'SACPCMP' and category in ('Pr CHSA','CHSM','CHSO'))
    or (registration_body = 'SAIOSH' and category in ('TechSAIOSH','GradSAIOSH','CMSAIOSH'))),
  unique nulls not distinct (industry_id, registration_body, category)
);
comment on table hsf_signoff_rule is 'HSF-REV-02, contract 10.8 (SIGNOFF-CRITERIA section 5, a design inference for confirmation by the attorney and a registered practitioner). Which registering body and category may sign the safety content of a File. Rows with an industry apply to Files of that industry; the rows with no industry (file_type general) apply to every industry that has none of its own. Candidate categories are never listed, so they never sign alone.';
comment on column hsf_signoff_rule.file_type is 'construction (the CONSTR industry), mining (the MINING industry) or general (every other industry, industry_id null).';
comment on column hsf_signoff_rule.industry_id is 'The industry the row applies to (msp_industry). Null for the general rows, which apply to every industry without rows of its own.';
comment on column hsf_signoff_rule.registration_body is 'SACPCMP or SAIOSH.';
comment on column hsf_signoff_rule.category is 'A registered category or designation that may sign: SACPCMP Pr CHSA, CHSM, CHSO; SAIOSH CMSAIOSH, GradSAIOSH, TechSAIOSH. Never a candidate category.';
comment on column hsf_signoff_rule.practitioner_review is 'True where the File is a practitioner review and is never presented as a sign off under the mining regime (SIGNOFF-CRITERIA section 5, mining).';
comment on column hsf_signoff_rule.note is 'Why the row is allowed, in words, as SIGNOFF-CRITERIA section 5 gives it.';

insert into hsf_signoff_rule (file_type, industry_id, registration_body, category, practitioner_review, note)
select 'construction', i.id, 'SACPCMP', c.category, false, c.note
  from msp_industry i
  cross join (values
    ('Pr CHSA', 'Registered construction health and safety agent; needed where the client needs a registered agent (construction work permit projects).'),
    ('CHSM', 'Registered construction health and safety manager.'),
    ('CHSO', 'Registered construction health and safety officer.')) as c(category, note)
 where i.code = 'CONSTR';

insert into hsf_signoff_rule (file_type, industry_id, registration_body, category, practitioner_review, note)
select 'mining', i.id, c.body, c.category, true, c.note
  from msp_industry i
  cross join (values
    ('SACPCMP', 'Pr CHSA', 'As general industry; the File is a practitioner review.'),
    ('SACPCMP', 'CHSM', 'As general industry; the File is a practitioner review.'),
    ('SAIOSH', 'CMSAIOSH', 'As general industry; the File is a practitioner review.'),
    ('SAIOSH', 'GradSAIOSH', 'As general industry; the File is a practitioner review.'),
    ('SAIOSH', 'TechSAIOSH', 'As general industry; the File is a practitioner review.')) as c(body, category, note)
 where i.code = 'MINING';

insert into hsf_signoff_rule (file_type, industry_id, registration_body, category, practitioner_review, note) values
  ('general', null, 'SACPCMP', 'Pr CHSA', false, 'Registered construction health and safety agent.'),
  ('general', null, 'SACPCMP', 'CHSM', false, 'Registered health and safety manager: Care Net''s standard (HSF-1).'),
  ('general', null, 'SAIOSH', 'CMSAIOSH', false, 'SAIOSH chartered member.'),
  ('general', null, 'SAIOSH', 'GradSAIOSH', false, 'SAIOSH graduate member.'),
  ('general', null, 'SAIOSH', 'TechSAIOSH', false, 'SAIOSH technical member.');

do $$
declare
  v_n int;
begin
  select count(*) into v_n from hsf_signoff_rule;
  if v_n <> 13 then
    raise exception '053: expected 13 hsf_signoff_rule rows (3 construction, 5 mining, 5 general), found %; is the CONSTR or MINING industry missing?', v_n;
  end if;
end;
$$;

-- 4. hsf_signatory_fit and the release gate (SIGNOFF-CRITERIA 6.2) -------------------------------

create or replace function hsf_signatory_fit(p_signoff_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_so hsf_signoff;
  v_sig hsf_signatory;
  v_industry uuid;
  v_type text;
  v_allowed text;
  v_day date;
begin
  select * into v_so from hsf_signoff where id = p_signoff_id;
  if v_so.id is null then
    return 'the sign off does not exist';
  end if;
  if v_so.kind <> 'safety_content' then
    return 'the sign off is not a safety content sign off';
  end if;
  if v_so.decision is distinct from 'approved' then
    return 'the safety content sign off is not approved';
  end if;
  if v_so.signatory_id is null then
    return 'no signatory credentials are recorded on the safety content sign off';
  end if;
  select * into v_sig from hsf_signatory where id = v_so.signatory_id;
  select f.industry_id into v_industry from hsf_file f where f.id = v_so.file_id;
  -- The decision date is the South African calendar day of decided_at.
  v_day := (v_so.decided_at at time zone 'Africa/Johannesburg')::date;

  if v_sig.category like 'Can %' then
    return format('%s is a candidate category (%s %s) and never signs a File alone',
                  v_sig.full_name, v_sig.registration_body, v_sig.category);
  end if;

  -- The rows of the File's industry; an industry with none takes the general rows.
  if exists (select 1 from hsf_signoff_rule r where r.industry_id = v_industry) then
    select min(r.file_type),
           string_agg(r.registration_body || ' ' || r.category, ', ' order by r.registration_body, r.category)
      into v_type, v_allowed
      from hsf_signoff_rule r where r.industry_id = v_industry;
  else
    select min(r.file_type),
           string_agg(r.registration_body || ' ' || r.category, ', ' order by r.registration_body, r.category)
      into v_type, v_allowed
      from hsf_signoff_rule r where r.industry_id is null;
  end if;
  if not exists (select 1 from hsf_signoff_rule r
                  where r.registration_body = v_sig.registration_body and r.category = v_sig.category
                    and ((r.industry_id = v_industry)
                         or (r.industry_id is null
                             and not exists (select 1 from hsf_signoff_rule x where x.industry_id = v_industry)))) then
    return format('%s %s may not sign the safety content of a %s File; allowed: %s',
                  v_sig.registration_body, v_sig.category, v_type, coalesce(v_allowed, 'none recorded'));
  end if;

  if v_sig.registration_expires_on < v_day then
    return format('the registration of %s (%s %s) expired on %s, before the decision on %s',
                  v_sig.full_name, v_sig.registration_body, v_sig.registration_number,
                  to_char(v_sig.registration_expires_on, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  if v_sig.register_checked_on is null or length(btrim(coalesce(v_sig.register_proof_ref, ''))) = 0 then
    return format('the check of the %s public register for %s is not recorded (date and saved proof)',
                  v_sig.registration_body, v_sig.full_name);
  end if;
  if v_sig.register_checked_on > v_day then
    return format('the %s register was checked on %s, after the decision on %s',
                  v_sig.registration_body, to_char(v_sig.register_checked_on, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  if v_sig.appointment_letter_ref is null or v_sig.appointment_letter_date is null then
    return format('the appointment letter of %s is not on record', v_sig.full_name);
  end if;
  if v_sig.appointment_letter_date > v_day then
    return format('the appointment letter of %s is dated %s, after the decision on %s',
                  v_sig.full_name, to_char(v_sig.appointment_letter_date, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  if v_sig.engagement_letter_ref is null or v_sig.engagement_letter_date is null then
    return format('the engagement letter of %s is not on record', v_sig.full_name);
  end if;
  if v_sig.engagement_letter_date > v_day then
    return format('the engagement letter of %s is dated %s, after the decision on %s',
                  v_sig.full_name, to_char(v_sig.engagement_letter_date, 'DD/MM/YYYY'), to_char(v_day, 'DD/MM/YYYY'));
  end if;
  return null;
end;
$$;
revoke execute on function hsf_signatory_fit(uuid) from public, anon, authenticated;
grant execute on function hsf_signatory_fit(uuid) to service_role;
comment on function hsf_signatory_fit is 'Contract 10.8 (SIGNOFF-CRITERIA 6.2). Null when an approved safety_content sign off can release its File revision; otherwise the first reason it cannot, in words: no credentials, a candidate category, a body or category that does not fit the File''s industry by hsf_signoff_rule, a registration expired on the decision date, no register check (or one after the decision), or a missing appointment or engagement letter (or one dated after the decision). The decision date is the South African calendar day of decided_at. Used by hsf_release_gate; service role only.';

create or replace function hsf_release_gate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_so record;
  v_reason text;
  v_first text;
  v_any boolean := false;
  v_fits boolean := false;
  v_unverified text;
begin
  -- 1. Safety content (SIGNOFF-CRITERIA 6.2): an approved sign off whose
  -- signatory fits. The latest decision's reason is reported when none fits.
  for v_so in select s.id from hsf_signoff s
               where s.file_id = new.file_id and s.revision = new.revision
                 and s.kind = 'safety_content' and s.decision = 'approved'
               order by s.decided_at desc, s.id loop
    v_any := true;
    v_reason := hsf_signatory_fit(v_so.id);
    if v_reason is null then
      v_fits := true;
      exit;
    end if;
    v_first := coalesce(v_first, v_reason);
  end loop;
  if not v_any then
    raise exception 'hsf_release_gate: safety_content sign off is not approved for this File revision';
  end if;
  if not v_fits then
    raise exception 'hsf_release_gate: the safety content sign off cannot release this File: %', v_first;
  end if;
  -- 2. The client's section 16(2) acceptance. The chief executive's
  -- acknowledgement is recorded, not a gate; the OMP is not a File signatory.
  if not exists (select 1 from hsf_signoff s
                  where s.file_id = new.file_id and s.revision = new.revision
                    and s.kind = 'client_16_2_acceptance' and s.decision = 'approved') then
    raise exception 'hsf_release_gate: client_16_2_acceptance sign off is not approved for this File revision';
  end if;
  -- 3. Contract 9.3, unchanged from 047: hsf_element_citable (migration 050) is
  -- the single definition of an instrument a File element may cite: verified,
  -- not held, not superseded, scope safety or both, and a provision pinned past
  -- 'awaiting verification'. Every instrument an item's element names must pass it.
  select string_agg(distinct li.short_name, ', ' order by li.short_name) into v_unverified
    from hsf_file_item fi
    join hsf_element_instrument ei on ei.element_id = fi.element_id
    join msp_legal_instrument li on li.id = ei.instrument_id
   where fi.file_id = new.file_id
     and not (hsf_element_citable(fi.element_id) ? li.short_name);
  if v_unverified is not null then
    raise exception 'hsf_release_gate: the File cites instruments that are not verified for a File: %', v_unverified;
  end if;
  return new;
end;
$$;
revoke execute on function hsf_release_gate() from public, anon, authenticated;
comment on function hsf_release_gate is 'SPEC B4.5 and B11.2 as amended by contract 10.8, and contract 9.3. Release needs (1) an approved safety_content sign off that hsf_signatory_fit accepts: body and category fit the File''s industry by hsf_signoff_rule, registration not expired on the decision date, register check recorded, appointment and engagement letters on record; (2) an approved client_16_2_acceptance; and (3) every instrument the File''s elements name citable for a File by hsf_element_citable. The OMP is not a File signatory and the chief executive acknowledgement is not a gate. Enforced in the database; the parameter hsf.release_required is display only and does not relax it.';

comment on table hsf_release is 'HSF-REV-01, amended by contract 10.8. A released File revision. The hsf_release_gate trigger refuses the insert unless an approved safety content sign off by a fitting, current, register checked and appointed practitioner and the client section 16(2) acceptance are on record, and every instrument the File''s elements name is citable for a File (hsf_element_citable, contract 9.3).';

comment on table hsf_section is 'HSF-SCH-01. The fifteen sections of the Health and Safety File, A to O. signatory_kind omp marks Section E, whose medical surveillance plan and certificates the OMP signs and the File holds as evidence; the OMP does not sign the File (contract 10.8). The safety content of every section is signed by a registered practitioner (hsf_signoff_rule).';

-- 5. Row Level Security and grants (as 047) ---------------------------------------------------------

alter table hsf_signatory enable row level security;
revoke all on hsf_signatory from public, anon, authenticated;
grant select on hsf_signatory to authenticated;
grant all on hsf_signatory to service_role;
create policy hsf_signatory_read on hsf_signatory
  for select to authenticated using (hsf_is_staff());

-- The rule table is reference data, like the 047 library tables: any signed in
-- person may read which body and category may sign; only the service role writes.
alter table hsf_signoff_rule enable row level security;
revoke all on hsf_signoff_rule from public, anon, authenticated;
grant select on hsf_signoff_rule to authenticated;
grant all on hsf_signoff_rule to service_role;
create policy hsf_signoff_rule_read on hsf_signoff_rule
  for select to authenticated using (true);
