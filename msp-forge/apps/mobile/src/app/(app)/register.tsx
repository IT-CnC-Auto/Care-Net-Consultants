// Register a company in one guided flow: Company, then places, then people.
// Each step is shaped by the industry chosen from the Care Net kernel (17
// industries): the kinds of place offered, the suggested places and
// departments. Progress is saved on the phone after every step, so a person can
// stop and carry on later; everything works offline and syncs later.

import { router, Stack } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { PlaceRow, SearchField, StepProgress } from '@/components/place-ui';
import { Button, Card, Chip, ChipRow, Field, Heading, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { haptic } from '@/features/haptics';
import { useMe } from '@/features/inspection';
import { createPlace, useOpenPlace, usePlaces, useStartHere } from '@/features/places';
import { COMPANY_STATUS_LABEL } from '@/lib/gates';
import { industry as industryOf, kernel, placeTypesFor, placeType } from '@/lib/kernel';
import { PERSON_ROLE_LABEL } from '@/lib/roles';
import type { PersonRole } from '@/lib/types';
import { space } from '@/theme/tokens';

const STEPS = ['Company', 'Places', 'People', 'Done'];
const KV = 'register.draft';
const PEOPLE_ROLES: PersonRole[] = ['s16_1', 's16_2', 'inspector', 'assistant', 'she_manager', 'she_officer', 'she_rep', 'first_aider'];

interface Draft {
  companyId: string | null;
  step: number;
}

export default function RegisterScreen() {
  const { store, app } = useMe();
  const b = kernel();
  const [draft, setDraft] = useState<Draft>({ companyId: null, step: 0 });
  const [loaded, setLoaded] = useState(false);
  const company = draft.companyId ? store.get('company', draft.companyId) : undefined;

  // Company step fields.
  const [legal, setLegal] = useState('');
  const [trading, setTrading] = useState('');
  const [reg, setReg] = useState('');
  const [ind, setInd] = useState<string | null>(null);
  const [sub, setSub] = useState<string | null>(null);
  const [indQuery, setIndQuery] = useState('');
  const [duty, setDuty] = useState(false);
  const [s161, setS161] = useState('');
  const [s162, setS162] = useState('');
  const [popia, setPopia] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const raw = await store.kvGet(KV);
        const d = raw ? (JSON.parse(raw) as Draft) : null;
        if (live && d && d.companyId && store.get('company', d.companyId) && d.step < 3) {
          const c = store.get('company', d.companyId);
          setDraft(d);
          if (c) {
            setLegal(c.legal_name);
            setTrading(c.trading_name ?? '');
            setReg(c.registration_number ?? '');
            setInd(c.industry_code);
            setSub(c.subindustry_code);
            setS161(c.s16_1_contact ?? '');
            setS162(c.s16_2_contact ?? '');
            setPopia(c.popia_contact ?? '');
          }
        }
      } finally {
        if (live) setLoaded(true);
      }
    })();
    return () => {
      live = false;
    };
    // Runs once: resume a saved registration.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const save = async (next: Draft) => {
    setDraft(next);
    await store.kvSet(KV, next.step >= 3 ? null : JSON.stringify(next));
  };

  const chosen = industryOf(b, ind);
  const industries = b.industries.filter((i) => !indQuery.trim() || `${i.name} ${i.subindustries.map((s) => s.name).join(' ')}`.toLowerCase().includes(indQuery.trim().toLowerCase()));

  const saveCompany = async () => {
    setError(null);
    if (legal.trim().length < 2) return setError("Enter the company's legal name as registered.");
    if (!ind) return setError('Choose the industry. It decides the places and inspections offered.');
    const fields = {
      legal_name: legal.trim(),
      trading_name: trading.trim() || null,
      registration_number: reg.trim() || null,
      industry_code: ind,
      subindustry_code: sub,
      s16_1_contact: s161.trim() || null,
      s16_2_contact: s162.trim() || null,
      popia_contact: popia.trim() || null,
    };
    let id = draft.companyId;
    if (id && store.get('company', id)) await store.update('company', id, fields);
    else {
      id = store.id();
      await store.create('company', { id, cipc_status: 'not_checked', onboarding_status: 'not_started', fica_status: 'not_submitted', file_eligibility: 'unknown', file_eligibility_note: null, ...fields });
    }
    await app.setActiveCompany(id);
    haptic.success();
    await save({ companyId: id, step: 1 });
  };

  if (!loaded) return <Screen><Txt muted>Loading…</Txt></Screen>;

  return (
    <Screen
      footer={
        draft.step === 0 ? (
          <Button title="Save and continue" icon="arrow-right" onPress={saveCompany} />
        ) : draft.step === 1 ? (
          <Button title="Continue to people" icon="arrow-right" onPress={() => save({ ...draft, step: 2 })} />
        ) : draft.step === 2 ? (
          <Button
            title="Finish registration"
            icon="check"
            onPress={async () => {
              if (company && company.onboarding_status === 'not_started') await store.update('company', company.id, { onboarding_status: 'in_review' });
              haptic.success();
              await save({ ...draft, step: 3 });
            }}
          />
        ) : null
      }>
      <Stack.Screen options={{ title: 'Register a company' }} />
      <StepProgress steps={STEPS} current={draft.step} />
      {draft.step > 0 && draft.step < 3 ? (
        <Button title="Back" icon="arrow-left" kind="ghost" compact onPress={() => save({ ...draft, step: draft.step - 1 })} style={{ alignSelf: 'flex-start' }} />
      ) : null}

      {draft.step === 0 ? (
        <>
          <Heading>The company</Heading>
          <Txt variant="small" muted>
            Saved on this phone as you go; you can stop and carry on later.
          </Txt>
          <Field label="Legal name" value={legal} onChangeText={setLegal} placeholder="As registered with CIPC" />
          <Field label="Trading name (optional)" value={trading} onChangeText={setTrading} />
          <Field label="Registration number (optional)" value={reg} onChangeText={setReg} placeholder="For example 2019/123456/07" autoCapitalize="characters" />

          <SectionTitle>Industry</SectionTitle>
          {chosen ? (
            <Card>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm }}>
                <Txt variant="bodyStrong" style={{ flex: 1 }}>
                  {chosen.name}
                </Txt>
                {chosen.regime === 'MHSA' ? <Pill label="Mine Health and Safety Act" tone="info" /> : null}
                <Button title="Change" kind="ghost" compact onPress={() => { setInd(null); setSub(null); }} />
              </View>
              <Txt variant="smallStrong">Subindustry</Txt>
              <ChipRow>
                {chosen.subindustries.map((s) => (
                  <Chip key={s.code} label={s.name} selected={sub === s.code} onPress={() => { haptic.tap(); setSub(sub === s.code ? null : s.code); }} />
                ))}
              </ChipRow>
              <Txt variant="tiny" muted>
                Places offered: {placeTypesFor(b, chosen.code, sub).filter((p) => !p.rule.always).map((p) => p.label.toLowerCase()).join(', ') || 'sites, offices and branches'}, plus departments, buildings, floors and rooms.
              </Txt>
            </Card>
          ) : (
            <>
              <SearchField value={indQuery} onChangeText={setIndQuery} placeholder="Search 17 industries" label="Search industries" />
              <Card style={{ padding: 0, gap: 0 }}>
                {industries.map((i) => (
                  <Button key={i.code} title={i.name} kind="ghost" onPress={() => { haptic.tap(); setInd(i.code); setSub(i.subindustries.length === 1 ? i.subindustries[0].code : null); setIndQuery(''); }} style={{ justifyContent: 'flex-start', borderRadius: 0 }} />
                ))}
              </Card>
            </>
          )}

          <SectionTitle>Duty holders and POPIA</SectionTitle>
          {duty ? (
            <Card>
              <Field label="OHS Act 16(1): chief executive officer" value={s161} onChangeText={setS161} placeholder="Name and title" />
              <Field label="OHS Act 16(2): assigned person" value={s162} onChangeText={setS162} placeholder="Name and title" />
              <Field label="POPIA contact (information officer)" value={popia} onChangeText={setPopia} placeholder="Name and email" />
            </Card>
          ) : (
            <Button title="Add the 16(1), 16(2) and POPIA contacts now" icon="account-plus-outline" kind="secondary" onPress={() => setDuty(true)} accessibilityHint="Optional now; you can add them later under Account" />
          )}
          {error ? <Notice tone="danger">{error}</Notice> : null}
        </>
      ) : null}

      {draft.step === 1 && company ? <PlacesStep companyId={company.id} industryCode={company.industry_code} subCode={company.subindustry_code} /> : null}
      {draft.step === 2 && company ? <PeopleStep companyId={company.id} /> : null}
      {draft.step === 3 && company ? <DoneStep companyId={company.id} onAnother={() => { setLegal(''); setTrading(''); setReg(''); setInd(null); setSub(null); setS161(''); setS162(''); setPopia(''); setDuty(false); void save({ companyId: null, step: 0 }); }} /> : null}
    </Screen>
  );
}

function PlacesStep({ companyId, industryCode, subCode }: { companyId: string; industryCode: string | null; subCode: string | null }) {
  const { store } = useMe();
  const b = kernel();
  const ind = industryOf(b, industryCode);
  const tree = usePlaces(companyId);
  const openPlace = useOpenPlace();
  const offered = placeTypesFor(b, industryCode, subCode).filter((p) => p.root);
  const suggestedTypes = Array.from(new Set([...(ind?.suggested_places.map((s) => s.place_type) ?? []), ...offered.filter((p) => p.rule.subindustries?.includes(subCode ?? '')).map((p) => p.code)]));
  const [names, setNames] = useState<Record<string, string>>({});
  const [picked, setPicked] = useState<Record<string, boolean>>({});
  const [deptPicked, setDeptPicked] = useState<Record<string, boolean>>({});
  const [error, setError] = useState<string | null>(null);
  const pending = suggestedTypes.filter((c) => !tree.roots.some((r) => r.place_type === c));
  // Departments go under the industry's main place (the first suggestion kept), else the first place.
  const firstRoot = suggestedTypes.map((c) => tree.roots.find((r) => r.place_type === c)).find((r) => !!r) ?? tree.roots[0];
  const existingDepts = new Set(tree.places.filter((p) => p.place_type === 'department').map((p) => p.department_code));
  const deptSuggestions = (ind?.suggested_departments ?? []).filter((d) => !existingDepts.has(d.code));

  const addSuggested = async () => {
    setError(null);
    try {
      for (const code of pending.filter((c) => picked[c] ?? true)) {
        await createPlace(store, { client_account_id: companyId, parent_id: null, place_type: code, name: (names[code] ?? placeType(b, code)?.label ?? 'Place').trim() });
      }
      haptic.success();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The places could not be added.');
    }
  };

  const addDepartments = async () => {
    if (!firstRoot) return;
    setError(null);
    try {
      for (const d of deptSuggestions.filter((x) => deptPicked[x.code] ?? true)) {
        await createPlace(store, { client_account_id: companyId, parent_id: firstRoot.id, place_type: 'department', name: b.departments.find((x) => x.code === d.code)?.name ?? d.code, department_code: d.code });
      }
      haptic.success();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The departments could not be added.');
    }
  };

  return (
    <>
      <Heading>Places of inspection</Heading>
      <Txt variant="small" muted>
        {ind ? `Suggested for ${ind.name.toLowerCase()} from the Care Net kernel. Keep what fits, rename it, skip the rest.` : 'Add the places you inspect.'}
      </Txt>
      {pending.length ? (
        <Card>
          {pending.map((code) => {
            const pt = placeType(b, code);
            const on = picked[code] ?? true;
            return (
              <View key={code} style={{ gap: space.xs }}>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm }}>
                  <Txt variant="bodyStrong" style={{ flex: 1 }}>
                    {pt?.label}
                  </Txt>
                  <Chip label={on ? 'Add' : 'Skip'} selected={on} onPress={() => { haptic.tap(); setPicked((x) => ({ ...x, [code]: !on })); }} accessibilityLabel={`${pt?.label}: ${on ? 'will be added' : 'skipped'}`} />
                </View>
                {on ? <Field label={`Name of the ${pt?.label.toLowerCase()}`} value={names[code] ?? pt?.label ?? ''} onChangeText={(v) => setNames((x) => ({ ...x, [code]: v }))} /> : null}
              </View>
            );
          })}
          <Button title="Add these places" icon="plus" onPress={addSuggested} disabled={!pending.some((c) => picked[c] ?? true)} />
        </Card>
      ) : null}

      {firstRoot && deptSuggestions.length ? (
        <Card>
          <Txt variant="smallStrong">{`Departments at ${firstRoot.name}`}</Txt>
          <Txt variant="tiny" muted>
            The File departments this industry&apos;s registers most often sit with.
          </Txt>
          <ChipRow>
            {deptSuggestions.map((d) => {
              const on = deptPicked[d.code] ?? true;
              return <Chip key={d.code} label={b.departments.find((x) => x.code === d.code)?.name ?? d.code} selected={on} onPress={() => { haptic.tap(); setDeptPicked((x) => ({ ...x, [d.code]: !on })); }} />;
            })}
          </ChipRow>
          <Button title="Add departments" icon="account-group-outline" kind="secondary" onPress={addDepartments} />
        </Card>
      ) : null}

      <SectionTitle action={<Button title="Add a place" icon="plus" compact kind="secondary" onPress={() => router.push({ pathname: '/place/edit', params: { companyId } })} />}>Your places</SectionTitle>
      {tree.roots.length ? (
        <Card style={{ padding: 0, gap: 0 }}>
          {tree.places
            .slice()
            .sort((a, c) => tree.pathOf(a.id).map((x) => x.name).join('/').localeCompare(tree.pathOf(c.id).map((x) => x.name).join('/')))
            .map((p) => (
              <PlaceRow key={p.id} place={p} depth={tree.pathOf(p.id).length - 1} onPress={() => openPlace(p)} />
            ))}
        </Card>
      ) : (
        <Txt muted>No places yet. Add the suggestions above, or your own.</Txt>
      )}
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </>
  );
}

function PeopleStep({ companyId }: { companyId: string }) {
  const { store } = useMe();
  const people = store.where('person', (p) => p.client_account_id === companyId);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [roles, setRoles] = useState<PersonRole[]>([]);
  const [error, setError] = useState<string | null>(null);

  const add = async () => {
    setError(null);
    if (name.trim().length < 2) return setError("Enter the person's full name.");
    if (!roles.length) return setError('Choose at least one role.');
    if (email.trim() && !/^\S+@\S+\.\S+$/.test(email.trim())) return setError('That email address does not look right.');
    await store.create('person', { id: store.id(), client_account_id: companyId, full_name: name.trim(), roles, email: email.trim() || null, mobile: null, appointed_on: null });
    haptic.success();
    setName('');
    setEmail('');
    setRoles([]);
  };

  return (
    <>
      <Heading>People</Heading>
      <Txt variant="small" muted>
        The authorised persons (16(1) and 16(2)), the inspectors and their assistants. You can skip this and add them later under Account.
      </Txt>
      {people.map((p) => (
        <Card key={p.id}>
          <Txt variant="bodyStrong">{p.full_name}</Txt>
          <Txt variant="small" muted>
            {p.roles.map((r) => PERSON_ROLE_LABEL[r]).join(', ')}
          </Txt>
        </Card>
      ))}
      <Card>
        <Field label="Full name" value={name} onChangeText={setName} />
        <Txt variant="smallStrong">Roles</Txt>
        <ChipRow>
          {PEOPLE_ROLES.map((r) => (
            <Chip key={r} label={PERSON_ROLE_LABEL[r]} selected={roles.includes(r)} onPress={() => { haptic.tap(); setRoles((x) => (x.includes(r) ? x.filter((y) => y !== r) : [...x, r])); }} />
          ))}
        </ChipRow>
        <Field label="Email (optional)" value={email} onChangeText={setEmail} keyboardType="email-address" autoCapitalize="none" />
        <Button title="Add person" icon="account-plus-outline" kind="secondary" onPress={add} />
      </Card>
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </>
  );
}

function DoneStep({ companyId, onAnother }: { companyId: string; onAnother: () => void }) {
  const { store } = useMe();
  const b = kernel();
  const company = store.get('company', companyId);
  const tree = usePlaces(companyId);
  const startHere = useStartHere();
  const people = store.where('person', (p) => p.client_account_id === companyId).length;
  if (!company) return null;
  const first = tree.roots[0];
  return (
    <>
      <Heading>Registered</Heading>
      <Card>
        <Txt variant="bodyStrong">{company.legal_name}</Txt>
        <Txt variant="small" muted>
          {industryOf(b, company.industry_code)?.name} · {tree.places.length} places · {people} people
        </Txt>
        <Pill label={`Onboarding ${COMPANY_STATUS_LABEL[company.onboarding_status]}`} tone={company.onboarding_status === 'active' ? 'success' : 'warning'} />
      </Card>
      <Notice tone="info" title="What happens next">
        Care Net checks the registration and the FICA documents; Start inspection opens once the company is Active. The places, people and templates are ready on this phone now.
      </Notice>
      {first ? <Button title={`Start inspection at ${first.name}`} icon="clipboard-play-outline" onPress={() => startHere(first)} /> : null}
      <Button title="Open places" icon="file-tree-outline" kind="secondary" onPress={() => router.navigate('/sites')} />
      <Button title="Register another company" icon="domain-plus" kind="ghost" onPress={onAnother} />
    </>
  );
}
