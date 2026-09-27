// Add or edit a place of inspection. Only the kinds of place the company's
// industry suits (kernel bundle) and the parent allows are offered; a person
// may give the kind their own name. Details stay folded away until wanted.

import { router, Stack, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { View } from 'react-native';

import { Breadcrumb } from '@/components/place-ui';
import { Button, Card, Chip, ChipRow, Field, Icon, Notice, Screen, Txt } from '@/components/ui';
import { consentGiven } from '@/features/capture';
import { currentFix } from '@/features/evidence';
import { haptic } from '@/features/haptics';
import { useMe } from '@/features/inspection';
import { createPlace, updatePlace, usePlaces } from '@/features/places';
import { childTypesFor, kernel, placeType } from '@/lib/kernel';
import { breadcrumb } from '@/lib/places';
import { space } from '@/theme/tokens';

export default function PlaceEditScreen() {
  const params = useLocalSearchParams<{ companyId?: string; parentId?: string; id?: string; type?: string }>();
  const { store, companyId: activeId } = useMe();
  const b = kernel();
  const editing = params.id ? store.get('place', params.id) : undefined;
  const companyId = editing?.client_account_id ?? params.companyId ?? activeId ?? '';
  const company = store.get('company', companyId);
  const tree = usePlaces(companyId);
  const parentId = editing ? editing.parent_id : params.parentId || null;
  const parent = parentId ? store.get('place', parentId) : undefined;
  const offered = childTypesFor(b, parent?.place_type ?? null, company?.industry_code, company?.subindustry_code);
  const [type, setType] = useState<string | null>(editing?.place_type ?? (params.type && offered.some((o) => o.code === params.type) ? params.type : offered.length === 1 ? offered[0].code : null));
  const [name, setName] = useState(editing?.name ?? '');
  const [customType, setCustomType] = useState(editing?.custom_type_label ?? '');
  const [more, setMore] = useState(!!editing);
  const [address, setAddress] = useState(editing?.address ?? '');
  const [gps, setGps] = useState<{ lat: number; lng: number } | null>(editing?.gps_lat != null && editing?.gps_lng != null ? { lat: editing.gps_lat, lng: editing.gps_lng } : null);
  const [responsible, setResponsible] = useState(editing?.responsible_person ?? '');
  const [headcount, setHeadcount] = useState(editing?.headcount != null ? String(editing.headcount) : '');
  const [deptCode, setDeptCode] = useState<string | null>(editing?.department_code ?? null);
  const [linked, setLinked] = useState<string[]>(editing?.linked_department_ids ?? []);
  const [error, setError] = useState<string | null>(null);
  const [locating, setLocating] = useState(false);
  const pt = placeType(b, type);
  const departments = tree.places.filter((p) => p.place_type === 'department' && p.id !== editing?.id);

  const save = async () => {
    setError(null);
    try {
      if (!type) throw new Error('Choose what kind of place it is.');
      const n = name.trim() || (type === 'department' && deptCode ? (b.departments.find((d) => d.code === deptCode)?.name ?? '') : '');
      if (headcount.trim() && !/^\d{1,7}$/.test(headcount.trim())) throw new Error('The headcount is a whole number.');
      const fields = {
        name: n,
        place_type: type,
        custom_type_label: customType.trim() || null,
        address: address.trim() || null,
        gps_lat: gps?.lat ?? null,
        gps_lng: gps?.lng ?? null,
        responsible_person: responsible.trim() || null,
        headcount: headcount.trim() ? Number(headcount.trim()) : null,
        department_code: deptCode,
        linked_department_ids: linked,
      };
      if (editing) await updatePlace(store, editing.id, fields);
      else await createPlace(store, { client_account_id: companyId, parent_id: parentId, ...fields });
      haptic.success();
      router.back();
    } catch (e) {
      haptic.warn();
      setError(e instanceof Error ? e.message : 'The place could not be saved.');
    }
  };

  const locate = async () => {
    setLocating(true);
    const fix = await currentFix(consentGiven(store, 'location'));
    setLocating(false);
    if (fix) setGps({ lat: fix.lat, lng: fix.lng });
    else setError(consentGiven(store, 'location') ? 'No GPS fix yet. Try again outside, or type the address.' : 'Give the location consent under Account, POPIA consents, to record GPS.');
  };

  return (
    <Screen footer={<Button title={editing ? 'Save changes' : 'Save place'} icon="content-save-outline" onPress={save} />}>
      <Stack.Screen options={{ title: editing ? 'Edit place' : parent ? `Add under ${parent.name}` : 'Add a place' }} />
      <Breadcrumb crumbs={breadcrumb(tree.all, parent?.id, company?.trading_name || company?.legal_name).map((label) => ({ label }))} />
      <Txt variant="small" muted>
        Saved on this phone straight away and synced when there is signal.
      </Txt>

      <Txt variant="smallStrong">What kind of place is it?</Txt>
      {offered.length === 0 ? <Notice tone="warning">Nothing can go under this place. Choose a place higher up.</Notice> : null}
      <ChipRow>
        {offered.map((o) => (
          <Chip
            key={o.code}
            label={o.label}
            selected={type === o.code}
            onPress={() => {
              haptic.tap();
              setType(o.code);
            }}
          />
        ))}
      </ChipRow>
      {pt ? (
        <Txt variant="tiny" muted>
          Offered for: {pt.why}.
        </Txt>
      ) : null}

      <Field label="Name" value={name} onChangeText={setName} placeholder={pt ? `For example: ${pt.code === 'department' ? 'Maintenance' : pt.code === 'room_area' ? 'Chemical store' : `Main ${pt.label.toLowerCase()}`}` : 'Name the place'} />
      {type === 'department' ? (
        <View style={{ gap: space.xs }}>
          <Txt variant="smallStrong">File department</Txt>
          <ChipRow>
            {b.departments.map((d) => (
              <Chip key={d.code} label={d.name} selected={deptCode === d.code} onPress={() => setDeptCode(deptCode === d.code ? null : d.code)} />
            ))}
          </ChipRow>
        </View>
      ) : null}

      {!more ? (
        <Button title="Add details: address, GPS, responsible person, headcount" icon="chevron-down" kind="ghost" compact onPress={() => setMore(true)} style={{ alignSelf: 'flex-start' }} />
      ) : (
        <Card>
          <Field label="Your own name for this kind of place (optional)" hint={pt ? `Shown instead of "${pt.label}"` : undefined} value={customType} onChangeText={setCustomType} placeholder="For example: pump station" />
          <Field label="Address (optional)" value={address} onChangeText={setAddress} />
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
            <Icon name="crosshairs-gps" />
            <Txt variant="small" style={{ flex: 1 }}>
              {gps ? `GPS ${gps.lat.toFixed(5)}, ${gps.lng.toFixed(5)}` : 'No GPS recorded'}
            </Txt>
            <Button title={gps ? 'Update' : 'Use my location'} kind="secondary" compact busy={locating} onPress={locate} />
          </View>
          <Field label="Responsible person (optional)" value={responsible} onChangeText={setResponsible} placeholder="Name and role" />
          <Field label="Headcount (optional)" hint="People who normally work here, a whole number" value={headcount} onChangeText={setHeadcount} keyboardType="number-pad" />
          {departments.length ? (
            <View style={{ gap: space.xs }}>
              <Txt variant="smallStrong">Departments that use this place</Txt>
              <ChipRow>
                {departments.map((d) => (
                  <Chip key={d.id} label={d.name} selected={linked.includes(d.id)} onPress={() => setLinked((l) => (l.includes(d.id) ? l.filter((x) => x !== d.id) : [...l, d.id]))} />
                ))}
              </ChipRow>
            </View>
          ) : null}
        </Card>
      )}
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </Screen>
  );
}
