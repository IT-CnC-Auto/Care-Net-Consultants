// The place switcher: one search box over every company and place on this
// phone (instant, word starts, breadcrumbs), recent places, the companies, and
// "start inspection here" on every place. Opens from the context bar.

import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, View } from 'react-native';

import { PlaceRow, SearchField } from '@/components/place-ui';
import { Button, Card, EmptyState, Icon, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { haptic } from '@/features/haptics';
import { useMe } from '@/features/inspection';
import { kernel } from '@/lib/kernel';
import { breadcrumb, livePlaces, pathOf, searchPlaces } from '@/lib/places';
import type { Place } from '@/lib/types';
import { brand, space } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

export default function SwitcherScreen() {
  const { store, app, companyId, industry } = useMe();
  const p = usePalette();
  const [q, setQ] = useState('');
  const b = kernel();
  const companies = store.list('company').sort((a, c) => (a.trading_name || a.legal_name).localeCompare(c.trading_name || c.legal_name));
  const places = store.list('place');
  const nameOf = (cid: string) => {
    const c = store.get('company', cid);
    return c ? c.trading_name || c.legal_name : '';
  };
  const pathText = (pl: Place) => breadcrumb(places, pl.id, nameOf(pl.client_account_id)).slice(0, -1).join(' › ');

  const go = (pl: Place, start = false) => {
    void app.touchPlace(pl.id, pl.client_account_id);
    router.back();
    if (start) router.push({ pathname: '/inspection/new', params: { placeId: pl.id } });
    else router.push({ pathname: '/place/[id]', params: { id: pl.id } });
  };
  const pickCompany = (id: string) => {
    haptic.tap();
    void app.setActiveCompany(id);
    router.back();
  };

  const hits = q.trim() ? searchPlaces(b, places, companies, q, companyId) : [];
  const recent = app.recentPlaceIds.map((id) => store.get('place', id)).filter((x): x is Place => !!x && !x.archived_at);
  const here = livePlaces(places, companyId).sort((a, c) => pathOf(places, a.id).map((x) => x.name).join('/').localeCompare(pathOf(places, c.id).map((x) => x.name).join('/')));

  return (
    <Screen>
      <SearchField value={q} onChangeText={setQ} autoFocus placeholder="Company, site, department or room" label="Search companies and places" />
      {q.trim() ? (
        hits.length ? (
          <Card style={{ padding: 0, gap: 0 }}>
            {hits.slice(0, 30).map((h) => {
              if (h.kind === 'company') {
                return (
                  <Pressable key={`c-${h.id}`} onPress={() => pickCompany(h.id)} accessibilityRole="button" accessibilityLabel={`Switch to ${h.title}`} style={({ pressed }) => [{ flexDirection: 'row', alignItems: 'center', gap: space.md, minHeight: 60, paddingHorizontal: space.md, borderBottomWidth: 0.5, borderBottomColor: p.border }, pressed && { backgroundColor: p.surfaceAlt }]}>
                    <Icon name="domain" color={brand.deepRed} />
                    <View style={{ flex: 1 }}>
                      <Txt variant="bodyStrong">{h.title}</Txt>
                      <Txt variant="tiny" muted>
                        Company
                      </Txt>
                    </View>
                    {h.id === companyId ? <Pill label="Current" tone="success" /> : null}
                  </Pressable>
                );
              }
              const pl = store.get('place', h.id) as Place;
              return <PlaceRow key={h.id} place={pl} path={h.path} onPress={() => go(pl)} onStart={() => go(pl, true)} />;
            })}
          </Card>
        ) : (
          <EmptyState icon="map-search-outline" title="Nothing matches" body="Try the first letters of a name, a kind of place such as workshop, or the company." />
        )
      ) : (
        <>
          {recent.length ? (
            <>
              <SectionTitle>Recent places</SectionTitle>
              <Card style={{ padding: 0, gap: 0 }}>
                {recent.map((pl) => (
                  <PlaceRow key={pl.id} place={pl} path={pathText(pl)} onPress={() => go(pl)} onStart={() => go(pl, true)} />
                ))}
              </Card>
            </>
          ) : null}

          <SectionTitle>Companies</SectionTitle>
          <Card style={{ padding: 0, gap: 0 }}>
            {companies.map((c) => (
              <Pressable key={c.id} onPress={() => pickCompany(c.id)} accessibilityRole="button" accessibilityLabel={`Switch to ${c.trading_name || c.legal_name}`} style={({ pressed }) => [{ flexDirection: 'row', alignItems: 'center', gap: space.md, minHeight: 60, paddingHorizontal: space.md, borderBottomWidth: 0.5, borderBottomColor: p.border }, pressed && { backgroundColor: p.surfaceAlt }]}>
                <Icon name="domain" color={c.id === companyId ? brand.deepRed : p.textMuted} />
                <View style={{ flex: 1 }}>
                  <Txt variant="bodyStrong">{c.trading_name || c.legal_name}</Txt>
                  <Txt variant="tiny" muted>
                    {b.industries.find((i) => i.code === c.industry_code)?.name ?? 'Industry not chosen'} · {livePlaces(places, c.id).length} places
                  </Txt>
                </View>
                {c.id === companyId ? <Pill label="Current" tone="success" /> : <Icon name="chevron-right" color={p.textMuted} />}
              </Pressable>
            ))}
          </Card>
          <Button title="Register another company" icon="domain-plus" kind="secondary" onPress={() => { router.back(); router.push('/register'); }} />

          <SectionTitle>{`All places${industry ? ` · ${industry.name}` : ''}`}</SectionTitle>
          {here.length ? (
            <Card style={{ padding: 0, gap: 0 }}>
              {here.map((pl) => (
                <PlaceRow key={pl.id} place={pl} depth={Math.min(4, pathOf(places, pl.id).length - 1)} onPress={() => go(pl)} onStart={() => go(pl, true)} />
              ))}
            </Card>
          ) : (
            <Txt muted>No places for this company yet. Add them under Places.</Txt>
          )}
        </>
      )}
    </Screen>
  );
}
