// The evidence library: every photo and voice note on this phone, newest
// version only, browsable by place, inspection or date, filtered by type, risk
// band and age, and searchable (findings, transcripts and evidence metadata).
// Shows the company's storage against its 10 GB line.

import { Image } from 'expo-image';
import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { BrandBar } from '@/components/brand-bar';
import { photoSource } from '@/components/evidence';
import { SearchField, StorageBar } from '@/components/place-ui';
import { Card, Chip, EmptyState, Icon, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { companyStorage } from '@/features/capture';
import { useMe } from '@/features/inspection';
import { useSearch } from '@/features/search';
import { useNow } from '@/features/use-now';
import { formatDate, formatDateTime } from '@/lib/dates';
import { latestVersions } from '@/lib/evidence-store';
import { breadcrumb } from '@/lib/places';
import { BAND_COLOUR, BAND_LABEL, riskBand, riskScore, type RiskBand } from '@/lib/risk';
import { voiceLabel } from '@/lib/report';
import type { Photo, VoiceNote } from '@/lib/types';
import { brand, radius, space } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

type Item = { kind: 'photo'; rec: Photo } | { kind: 'voice'; rec: VoiceNote };
type GroupBy = 'place' | 'inspection' | 'date';
const AGE: { key: string; label: string; days: number | null }[] = [
  { key: 'all', label: 'Any date', days: null },
  { key: '1', label: 'Today', days: 1 },
  { key: '7', label: '7 days', days: 7 },
  { key: '30', label: '30 days', days: 30 },
];

export default function EvidenceScreen() {
  const params = useLocalSearchParams<{ placeId?: string }>();
  const { store, company, companyId } = useMe();
  const p = usePalette();
  const [q, setQ] = useState('');
  const [type, setType] = useState<'all' | 'photo' | 'voice'>('all');
  const [band, setBand] = useState<RiskBand | 'all'>('all');
  const [age, setAge] = useState('all');
  const [group, setGroup] = useState<GroupBy>('place');
  const [allCompanies, setAllCompanies] = useState(false);
  // The place filter comes from the route (a place's "Evidence" button), so it follows every visit.
  const placeFilter = params.placeId || null;
  const setPlaceFilter = (v: string | null) => router.setParams({ placeId: v ?? '' });
  const now = useNow(60000);

  const places = store.list('place');
  const inspections = new Map(store.list('inspection').map((i) => [i.id, i]));
  const risks = store.list('risk');
  const companyOf = (inspectionId: string) => inspections.get(inspectionId)?.client_account_id ?? null;
  const bandOf = (findingId: string | null): RiskBand | null => {
    const r = findingId ? risks.find((x) => x.finding_id === findingId) : undefined;
    return r ? riskBand(riskScore(r.inherent_likelihood, r.inherent_severity)) : null;
  };
  const underPlace = (pid: string | null) => {
    if (!placeFilter) return true;
    let cur = pid ? places.find((x) => x.id === pid) : undefined;
    while (cur) {
      if (cur.id === placeFilter) return true;
      cur = cur.parent_id ? places.find((x) => x.id === cur?.parent_id) : undefined;
    }
    return false;
  };

  const all: Item[] = [
    ...latestVersions(store.list('photo')).map((rec) => ({ kind: 'photo' as const, rec })),
    ...latestVersions(store.list('voice_note')).map((rec) => ({ kind: 'voice' as const, rec })),
  ];
  const { hits, engine } = useSearch(q, allCompanies ? {} : { companyId });
  let items = all;
  if (q.trim()) {
    const order = new Map<string, number>();
    hits.forEach((h, i) => {
      const add = (id: string) => {
        if (!order.has(id)) order.set(id, i);
      };
      const d = h.doc;
      if (d.kind === 'evidence' || d.kind === 'transcript') add(d.ref);
      for (const it of all) {
        if (d.kind === 'finding' && it.rec.finding_id === d.ref) add(it.rec.id);
        if (d.kind === 'inspection' && it.rec.inspection_id === d.ref) add(it.rec.id);
        if (d.kind === 'place' && it.rec.place_id === d.ref) add(it.rec.id);
      }
    });
    items = all.filter((it) => order.has(it.rec.id)).sort((a, b) => (order.get(a.rec.id) ?? 0) - (order.get(b.rec.id) ?? 0));
  }
  const days = AGE.find((a) => a.key === age)?.days ?? null;
  items = items.filter(
    (it) =>
      (allCompanies || companyOf(it.rec.inspection_id) === companyId) &&
      (type === 'all' || it.kind === type) &&
      (band === 'all' || bandOf(it.rec.finding_id) === band) &&
      (days === null || now - Date.parse(it.rec.captured_at) <= days * 86400000) &&
      underPlace(it.rec.place_id),
  );
  if (!q.trim()) items = items.sort((a, b) => b.rec.captured_at.localeCompare(a.rec.captured_at));

  const groupKey = (it: Item) =>
    group === 'place'
      ? breadcrumb(places, it.rec.place_id).join(' › ') || 'Not placed'
      : group === 'inspection'
        ? (inspections.get(it.rec.inspection_id)?.title ?? 'Inspection')
        : formatDate(it.rec.captured_at);
  const groups: [string, Item[]][] = [];
  for (const it of items) {
    const k = groupKey(it);
    const g = groups.find((x) => x[0] === k);
    if (g) g[1].push(it);
    else groups.push([k, [it]]);
  }
  const meter = companyId ? companyStorage(store, companyId) : null;
  const filterPlace = placeFilter ? places.find((x) => x.id === placeFilter) : undefined;

  return (
    <View style={{ flex: 1 }}>
      <BrandBar title="Evidence library" />
      <Screen edges={[]}>
        {meter ? (
          <Card>
            <Txt variant="label" muted>
              {`Storage · ${company?.trading_name ?? company?.legal_name ?? ''}`}
            </Txt>
            <StorageBar fraction={meter.fraction} state={meter.state} text={meter.text} />
          </Card>
        ) : null}
        <SearchField value={q} onChangeText={setQ} placeholder="Search findings, transcripts, tags, places" label="Search the evidence" />
        {q.trim() ? (
          <Txt variant="tiny" muted>
            {engine === 'fts5' ? 'Searching the full text index on this phone.' : 'Searching on this phone, offline.'}
          </Txt>
        ) : null}

        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.rail} accessibilityLabel="Filters">
          <Chip label="Photos" selected={type === 'photo'} onPress={() => setType(type === 'photo' ? 'all' : 'photo')} />
          <Chip label="Voice notes" selected={type === 'voice'} onPress={() => setType(type === 'voice' ? 'all' : 'voice')} />
          <View style={[styles.railGap, { backgroundColor: p.border }]} />
          {(['low', 'medium', 'high', 'extreme'] as RiskBand[]).map((k) => (
            <Chip key={k} label={BAND_LABEL[k]} selected={band === k} tone={BAND_COLOUR[k]} onPress={() => setBand(band === k ? 'all' : k)} accessibilityLabel={`Risk band ${BAND_LABEL[k]}`} />
          ))}
          <View style={[styles.railGap, { backgroundColor: p.border }]} />
          {AGE.filter((a) => a.days !== null).map((a) => (
            <Chip key={a.key} label={a.label} selected={age === a.key} onPress={() => setAge(age === a.key ? 'all' : a.key)} />
          ))}
          <View style={[styles.railGap, { backgroundColor: p.border }]} />
          <Chip label="All companies" selected={allCompanies} onPress={() => setAllCompanies(!allCompanies)} />
        </ScrollView>
        {filterPlace ? <Chip label={`At ${filterPlace.name}  ✕`} selected onPress={() => setPlaceFilter(null)} accessibilityLabel={`Only evidence at ${filterPlace.name}. Remove this filter`} /> : null}
        <View style={styles.groupRow}>
          <Txt variant="small" muted>{`${items.length} ${items.length === 1 ? 'item' : 'items'} · group by`}</Txt>
          {(['place', 'inspection', 'date'] as GroupBy[]).map((g) => (
            <Chip key={g} label={g === 'place' ? 'Place' : g === 'inspection' ? 'Inspection' : 'Date'} selected={group === g} onPress={() => setGroup(g)} />
          ))}
        </View>

        {groups.length === 0 ? (
          <EmptyState
            icon="folder-search-outline"
            title={q.trim() || type !== 'all' || band !== 'all' || age !== 'all' || placeFilter ? 'Nothing matches these filters' : 'No evidence yet'}
            body={q.trim() || type !== 'all' || band !== 'all' || age !== 'all' || placeFilter ? 'Clear a filter or try other words.' : 'Photos and voice notes you capture in an inspection appear here, sorted by place, inspection and date, and searchable offline.'}
          />
        ) : null}
        {groups.map(([k, list]) => (
          <View key={k} style={{ gap: space.sm }}>
            <SectionTitle>{k}</SectionTitle>
            {list.map((it) => {
              const bnd = bandOf(it.rec.finding_id);
              const verified = !!it.rec._upload?.verified;
              return (
                <Pressable
                  key={it.rec.id}
                  onPress={() => router.push({ pathname: '/evidence/[id]', params: { id: it.rec.id, kind: it.kind } })}
                  accessibilityRole="button"
                  accessibilityLabel={`${it.kind === 'photo' ? (it.rec.caption ?? 'Photo') : voiceLabel(it.rec)}, ${formatDateTime(it.rec.captured_at)}${bnd ? `, risk ${BAND_LABEL[bnd]}` : ''}`}
                  style={({ pressed }) => [styles.row, { backgroundColor: p.surface, borderColor: p.border }, pressed && { opacity: 0.85 }]}>
                  {it.kind === 'photo' ? (
                    <Image source={photoSource(it.rec._thumb_uri ?? it.rec._local_uri)} style={styles.thumb} contentFit="cover" accessibilityIgnoresInvertColors />
                  ) : (
                    <View style={[styles.thumb, { backgroundColor: p.surfaceAlt, alignItems: 'center', justifyContent: 'center' }]}>
                      <Icon name="microphone" color={brand.deepRed} size={28} />
                    </View>
                  )}
                  <View style={{ flex: 1, gap: 2 }}>
                    <Txt variant="bodyStrong" numberOfLines={2}>
                      {it.kind === 'photo' ? (it.rec.caption ?? 'Photo') : `Voice note ${voiceLabel(it.rec)}`}
                    </Txt>
                    <Txt variant="tiny" muted numberOfLines={1}>
                      {`${formatDateTime(it.rec.captured_at)} · ${inspections.get(it.rec.inspection_id)?.title ?? ''}`}
                    </Txt>
                    <View style={styles.pills}>
                      {bnd ? <Pill label={BAND_LABEL[bnd]} solid={BAND_COLOUR[bnd]} /> : null}
                      {it.rec.evidence_version > 1 ? <Pill label={`Version ${it.rec.evidence_version}`} tone="info" /> : null}
                      <Pill label={verified ? 'Verified on server' : 'On this phone'} tone={verified ? 'success' : 'neutral'} />
                    </View>
                  </View>
                  <Icon name="chevron-right" color={p.textMuted} />
                </Pressable>
              );
            })}
          </View>
        ))}
        {groups.length ? (
          <Txt variant="tiny" muted style={{ textAlign: 'center' }}>
            The same photo used twice is stored once. Originals are never changed; corrections are new versions.
          </Txt>
        ) : null}
      </Screen>
    </View>
  );
}

const styles = StyleSheet.create({
  groupRow: { flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' },
  rail: { flexDirection: 'row', alignItems: 'center', gap: space.sm, paddingRight: space.lg },
  railGap: { width: 1, height: 24, marginHorizontal: space.xs },
  row: { flexDirection: 'row', alignItems: 'center', gap: space.md, padding: space.sm, borderRadius: radius.lg, borderWidth: 1, minHeight: 88 },
  thumb: { width: 72, height: 72, borderRadius: radius.md },
  pills: { flexDirection: 'row', gap: space.xs, flexWrap: 'wrap' },
});
