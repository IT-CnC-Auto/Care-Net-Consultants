// One place: where it sits (breadcrumb), what it is, the places under it, the
// inspections and evidence here, and one primary action: start an inspection here.

import { router, Stack, useLocalSearchParams } from 'expo-router';
import { View } from 'react-native';

import { Breadcrumb, PlaceRow, placeIcon } from '@/components/place-ui';
import { Button, Card, EmptyState, Icon, KeyValue, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useMe } from '@/features/inspection';
import { archivePlace, useOpenPlace, usePlaces, useStartHere } from '@/features/places';
import { formatDate, plural } from '@/lib/dates';
import { latestVersions } from '@/lib/evidence-store';
import { childTypesFor, departmentName, kernel, placeType } from '@/lib/kernel';
import { descendantsOf, typeLabel } from '@/lib/places';
import { brand, space } from '@/theme/tokens';

export default function PlaceScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { store, app } = useMe();
  const b = kernel();
  const place = store.get('place', id);
  const tree = usePlaces(place?.client_account_id);
  const openPlace = useOpenPlace();
  const startHere = useStartHere();
  if (!place) return <Screen><Notice tone="warning">This place is not on this phone.</Notice></Screen>;
  const company = store.get('company', place.client_account_id);
  const path = tree.pathOf(place.id);
  const kids = tree.childrenOf(place.id);
  const under = new Set([place.id, ...descendantsOf(tree.all, place.id).map((d) => d.id)]);
  const inspections = store.where('inspection', (i) => under.has(i.place_id ?? '') || under.has(i.site_id)).sort((a, c) => (c.started_at ?? '').localeCompare(a.started_at ?? ''));
  const photos = latestVersions(store.where('photo', (p) => under.has(p.place_id ?? '')));
  const notes = latestVersions(store.where('voice_note', (v) => under.has(v.place_id ?? '')));
  const canAdd = childTypesFor(b, place.place_type, company?.industry_code, company?.subindustry_code).length > 0;
  const pt = placeType(b, place.place_type);

  return (
    <Screen footer={<Button title="Start inspection here" icon="clipboard-play-outline" onPress={() => startHere(place)} accessibilityHint={`Opens the template picker for ${place.name}`} />}>
      <Stack.Screen options={{ title: place.name }} />
      <Breadcrumb
        crumbs={[
          { label: company?.trading_name || company?.legal_name || 'Company', onPress: () => { void app.setActiveCompany(place.client_account_id); router.navigate('/sites'); } },
          ...path.slice(0, -1).map((p) => ({ label: p.name, onPress: () => openPlace(p) })),
          { label: place.name },
        ]}
      />
      <Card>
        <View style={{ flexDirection: 'row', gap: space.md, alignItems: 'center' }}>
          <Icon name={placeIcon(place)} size={32} color={brand.deepRed} />
          <View style={{ flex: 1 }}>
            <Txt variant="h3">{place.name}</Txt>
            <Txt variant="small" muted>
              {typeLabel(b, place)}
              {place.custom_type_label && pt ? ` (${pt.label})` : ''}
            </Txt>
          </View>
          <Button title="Edit" kind="ghost" compact onPress={() => router.push({ pathname: '/place/edit', params: { id: place.id } })} />
        </View>
        {place.address ? <KeyValue label="Address" value={place.address} /> : null}
        {place.gps_lat != null && place.gps_lng != null ? <KeyValue label="GPS" value={`${place.gps_lat.toFixed(5)}, ${place.gps_lng.toFixed(5)}`} /> : null}
        {place.responsible_person ? <KeyValue label="Responsible person" value={place.responsible_person} /> : null}
        {place.headcount != null ? <KeyValue label="Headcount" value={String(place.headcount)} /> : null}
        {place.department_code ? <KeyValue label="File department" value={departmentName(b, place.department_code) ?? place.department_code} /> : null}
        {place.linked_department_ids.length ? <KeyValue label="Used by" value={place.linked_department_ids.map((d) => store.get('place', d)?.name ?? '').filter(Boolean).join(', ')} /> : null}
        <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
          <Pill label={plural(inspections.length, 'inspection')} tone="neutral" />
          <Pill label={plural(photos.length, 'photo')} tone="neutral" />
          <Pill label={plural(notes.length, 'voice note')} tone="neutral" />
        </View>
      </Card>

      <SectionTitle action={canAdd ? <Button title="Add" icon="plus" compact kind="secondary" onPress={() => router.push({ pathname: '/place/edit', params: { companyId: place.client_account_id, parentId: place.id } })} /> : undefined}>
        {`Under ${place.name}`}
      </SectionTitle>
      {kids.length ? (
        <Card style={{ padding: 0, gap: 0 }}>
          {kids.map((k) => (
            <PlaceRow key={k.id} place={k} onPress={() => openPlace(k)} onStart={() => startHere(k)} />
          ))}
        </Card>
      ) : (
        <EmptyState
          icon="file-tree-outline"
          title={canAdd ? 'Nothing under this place yet' : 'This is the smallest level'}
          body={canAdd ? 'Add the departments, buildings, floors, rooms or areas you walk. Each becomes an area you can pick when you start an inspection.' : 'Start an inspection here, or add an area from the inspection itself.'}
        />
      )}

      <SectionTitle action={photos.length + notes.length ? <Button title="Evidence" icon="folder-image" compact kind="ghost" onPress={() => router.push({ pathname: '/evidence', params: { placeId: place.id } })} /> : undefined}>Inspections here</SectionTitle>
      {inspections.length ? (
        inspections.slice(0, 8).map((i) => (
          <Card key={i.id} onPress={() => router.push({ pathname: '/inspection/[id]', params: { id: i.id } })} accessibilityLabel={`Open ${i.title}`}>
            <Txt variant="bodyStrong">{i.title}</Txt>
            <Txt variant="small" muted>
              {formatDate(i.started_at)} · {i.status === 'in_progress' ? 'In progress' : i.status === 'submitted' ? 'Submitted' : i.status}
            </Txt>
          </Card>
        ))
      ) : (
        <Txt muted>No inspections here yet. Start one with the button below.</Txt>
      )}

      <Button
        title="Archive this place"
        kind="ghost"
        compact
        icon="archive-outline"
        onPress={async () => {
          await archivePlace(store, place.id);
          router.back();
        }}
        accessibilityHint="Archived places keep their inspections and evidence; they are never deleted"
        style={{ alignSelf: 'flex-start' }}
      />
    </Screen>
  );
}
