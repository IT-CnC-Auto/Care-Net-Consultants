// Places: the active company's places of inspection as a tree of typed nodes
// (site, office, farm, mine or quarry section, clinic or laboratory, retail
// store, department, building, floor, room or area ...), the types its kernel
// industry suits. Everything is made offline and synced later. Every place can
// start an inspection.

import { router } from 'expo-router';
import { useState } from 'react';
import { View } from 'react-native';

import { BrandBar } from '@/components/brand-bar';
import { PlaceRow } from '@/components/place-ui';
import { Button, Card, Chip, ChipRow, EmptyState, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useMe } from '@/features/inspection';
import { useOpenPlace, usePlaces, useStartHere } from '@/features/places';
import { COMPANY_STATUS_LABEL } from '@/lib/gates';
import { kernel, placeType } from '@/lib/kernel';
import type { Place } from '@/lib/types';
import { space } from '@/theme/tokens';

function Branch({ place, depth, tree, open, toggle }: { place: Place; depth: number; tree: ReturnType<typeof usePlaces>; open: Record<string, boolean>; toggle: (id: string) => void }) {
  const openPlace = useOpenPlace();
  const startHere = useStartHere();
  const kids = tree.childrenOf(place.id);
  const isOpen = open[place.id] ?? depth < 1;
  return (
    <View>
      <PlaceRow place={place} depth={depth} onPress={() => openPlace(place)} onStart={() => startHere(place)} expanded={isOpen} onToggle={kids.length ? () => toggle(place.id) : undefined} />
      {isOpen ? kids.map((k) => <Branch key={k.id} place={k} depth={depth + 1} tree={tree} open={open} toggle={toggle} />) : null}
    </View>
  );
}

export default function PlacesScreen() {
  const { company, companyId, industry } = useMe();
  const tree = usePlaces(companyId);
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const toggle = (id: string) => setOpen((o) => ({ ...o, [id]: !(o[id] ?? false) }));
  const b = kernel();
  const suggestions = (industry?.suggested_places ?? []).filter((s) => !tree.roots.some((r) => r.place_type === s.place_type));

  return (
    <View style={{ flex: 1 }}>
      <BrandBar title="Places" />
      <Screen edges={[]}>
        {company ? (
          <Card>
            <Txt variant="label" muted>
              Company
            </Txt>
            <Txt variant="bodyStrong">{company.legal_name}</Txt>
            <Txt variant="small" muted>
              {industry ? `${industry.name}${company.subindustry_code ? ` · ${industry.subindustries.find((s) => s.code === company.subindustry_code)?.name ?? ''}` : ''}` : 'Industry not chosen yet'}
            </Txt>
            <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
              <Pill label={COMPANY_STATUS_LABEL[company.onboarding_status]} tone={company.onboarding_status === 'active' ? 'success' : 'warning'} />
              <Pill label={`${tree.places.length} places`} tone="neutral" />
            </View>
          </Card>
        ) : (
          <EmptyState icon="domain" title="No company yet" body="Register the company first; its industry decides the kinds of places and the inspections offered." action={<Button title="Register a company" onPress={() => router.push('/register')} />} />
        )}

        {company ? (
          <>
            <SectionTitle action={<Button title="Add place" icon="plus" compact kind="secondary" onPress={() => router.push({ pathname: '/place/edit', params: { companyId: company.id } })} />}>Places of inspection</SectionTitle>
            {tree.roots.length === 0 ? (
              <EmptyState
                icon="map-marker-plus-outline"
                title="Add the first place"
                body={`A place is anywhere you inspect: a site, an office, a ${industry ? (placeType(b, industry.suggested_places[0]?.place_type)?.label.toLowerCase() ?? 'site') : 'site'}. Add departments, buildings, floors and rooms under it. It works without signal.`}
              />
            ) : (
              <Card style={{ padding: 0, gap: 0 }}>
                {tree.roots.map((r) => (
                  <Branch key={r.id} place={r} depth={0} tree={tree} open={open} toggle={toggle} />
                ))}
              </Card>
            )}
            {suggestions.length ? (
              <Card>
                <Txt variant="smallStrong">Suggested for {industry?.name.toLowerCase()}</Txt>
                <Txt variant="tiny" muted>
                  From the Care Net kernel for this industry. Tap to add one; skip the rest.
                </Txt>
                <ChipRow>
                  {suggestions.map((s) => {
                    const pt = placeType(b, s.place_type);
                    return pt ? <Chip key={s.place_type} label={`+ ${pt.label}`} onPress={() => router.push({ pathname: '/place/edit', params: { companyId: company.id, type: pt.code } })} /> : null;
                  })}
                </ChipRow>
              </Card>
            ) : null}
            <Button title="Add tagged equipment" icon="barcode-scan" kind="ghost" compact onPress={() => router.push({ pathname: '/site-new', params: { kind: 'equipment', parentId: tree.roots[0]?.id ?? '' } })} style={{ alignSelf: 'flex-start' }} />
          </>
        ) : null}
      </Screen>
    </View>
  );
}
