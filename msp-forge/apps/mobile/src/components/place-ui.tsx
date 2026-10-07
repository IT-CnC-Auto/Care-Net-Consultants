// Building blocks for places and navigation: search field, step progress,
// breadcrumb, place rows with "Start inspection here", the context bar that
// opens the switcher, and the storage meter. Tokens only (src/theme/tokens.ts).

import { router } from 'expo-router';
import type { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { haptic } from '@/features/haptics';
import { kernel, placeType } from '@/lib/kernel';
import { typeLabel } from '@/lib/places';
import type { MeterState } from '@/lib/evidence-store';
import type { Place } from '@/lib/types';
import { brand, fonts, onInk, radius, space, touch, type as t } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

import { Icon, Txt, type IconName } from './ui';

export function placeIcon(p: Pick<Place, 'place_type'>): IconName {
  return (placeType(kernel(), p.place_type)?.icon ?? 'map-marker-outline') as IconName;
}

export function SearchField({ value, onChangeText, placeholder, autoFocus, label = 'Search' }: { value: string; onChangeText: (s: string) => void; placeholder?: string; autoFocus?: boolean; label?: string }) {
  const p = usePalette();
  return (
    <View style={[styles.search, { backgroundColor: p.surface, borderColor: p.border }]}>
      <Icon name="magnify" color={p.textMuted} />
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={p.textMuted}
        autoFocus={autoFocus}
        autoCorrect={false}
        autoCapitalize="none"
        returnKeyType="search"
        accessibilityLabel={label}
        style={[t.body, styles.searchInput, { color: p.text }]}
      />
      {value ? (
        <Pressable onPress={() => onChangeText('')} accessibilityRole="button" accessibilityLabel="Clear the search" hitSlop={12} style={styles.clear}>
          <Icon name="close-circle" color={p.textMuted} size={20} />
        </Pressable>
      ) : null}
    </View>
  );
}

/** "Step 2 of 4" with a bar and the step names; the current one is marked for screen readers. */
export function StepProgress({ steps, current }: { steps: string[]; current: number }) {
  const p = usePalette();
  return (
    <View accessibilityRole="progressbar" accessibilityLabel={`Step ${current + 1} of ${steps.length}: ${steps[current]}`} accessibilityValue={{ min: 1, max: steps.length, now: current + 1 }} style={{ gap: space.xs }}>
      <View style={styles.stepsRow}>
        {steps.map((s, i) => (
          <View key={s} style={[styles.stepBar, { backgroundColor: i <= current ? brand.red : p.border }]} />
        ))}
      </View>
      <View style={styles.stepsRow}>
        {steps.map((s, i) => (
          <Text key={s} style={[t.tiny, styles.stepLabel, { color: i === current ? p.text : p.textMuted, fontFamily: i === current ? fonts.bodyBold : fonts.body }]} numberOfLines={1}>
            {s}
          </Text>
        ))}
      </View>
    </View>
  );
}

/** Tappable breadcrumb: each crumb opens that level. */
export function Breadcrumb({ crumbs }: { crumbs: { label: string; onPress?: () => void }[] }) {
  const p = usePalette();
  return (
    <View style={styles.crumbs} accessibilityRole="summary" accessibilityLabel={crumbs.map((c) => c.label).join(', then ')}>
      {crumbs.map((c, i) => (
        <View key={`${c.label}-${i}`} style={styles.crumbWrap}>
          {i > 0 ? <Icon name="chevron-right" size={16} color={p.textMuted} /> : null}
          <Pressable onPress={c.onPress} disabled={!c.onPress} accessibilityRole={c.onPress ? 'link' : 'text'} hitSlop={8} style={styles.crumb}>
            <Text style={[t.smallStrong, { color: c.onPress ? p.info : p.text }]} numberOfLines={1}>
              {c.label}
            </Text>
          </Pressable>
        </View>
      ))}
    </View>
  );
}

/** One place in a list: icon, name, type and path, with an optional "Start here" action. */
export function PlaceRow({
  place,
  path,
  depth = 0,
  onPress,
  onStart,
  right,
  expanded,
  onToggle,
}: {
  place: Place;
  path?: string;
  depth?: number;
  onPress?: () => void;
  onStart?: () => void;
  right?: ReactNode;
  expanded?: boolean;
  onToggle?: () => void;
}) {
  const p = usePalette();
  const label = typeLabel(kernel(), place);
  return (
    <View style={[styles.placeRow, { borderBottomColor: p.border, paddingLeft: space.sm + depth * space.lg }]}>
      {onToggle ? (
        <Pressable onPress={onToggle} accessibilityRole="button" accessibilityState={{ expanded: !!expanded }} accessibilityLabel={`${expanded ? 'Collapse' : 'Expand'} ${place.name}`} hitSlop={8} style={styles.toggle}>
          <Icon name={expanded ? 'chevron-down' : 'chevron-right'} size={20} color={p.textMuted} />
        </Pressable>
      ) : (
        <View style={{ width: depth ? 28 : 4 }} />
      )}
      <Pressable
        onPress={() => {
          haptic.tap();
          onPress?.();
        }}
        accessibilityRole="button"
        accessibilityLabel={`${place.name}, ${label}${path ? `, in ${path}` : ''}`}
        style={({ pressed }) => [styles.placeMain, pressed && { opacity: 0.7 }]}>
        <View style={[styles.placeIcon, { backgroundColor: p.surfaceAlt }]}>
          <Icon name={placeIcon(place)} size={20} color={brand.deepRed} />
        </View>
        <View style={{ flex: 1, gap: 1 }}>
          <Txt variant="bodyStrong" numberOfLines={1}>
            {place.name}
          </Txt>
          <Txt variant="tiny" muted numberOfLines={1}>
            {path ? `${label} · ${path}` : label}
          </Txt>
        </View>
      </Pressable>
      {right}
      {onStart ? (
        <Pressable
          onPress={() => {
            haptic.tap();
            onStart();
          }}
          accessibilityRole="button"
          accessibilityLabel={`Start inspection at ${place.name}`}
          hitSlop={6}
          style={({ pressed }) => [styles.startBtn, { borderColor: p.border, backgroundColor: pressed ? p.surfaceAlt : p.surface }]}>
          <Icon name="clipboard-play-outline" size={20} color={brand.deepRed} />
        </Pressable>
      ) : null}
    </View>
  );
}

/**
 * The context bar under the wordmark: the company (and place) the person is in,
 * a tap away from the switcher with instant search and recent places.
 */
export function ContextBar({ company, place }: { company: string | null; place?: string | null }) {
  return (
    <Pressable
      onPress={() => {
        haptic.tap();
        router.push('/switcher');
      }}
      accessibilityRole="button"
      accessibilityLabel={`Working in ${company ?? 'no company'}${place ? `, ${place}` : ''}. Switch company or place`}
      style={({ pressed }) => [styles.context, pressed && { opacity: 0.8 }]}>
      <Icon name="swap-horizontal" size={18} color={brand.gold} />
      <Text style={styles.contextText} numberOfLines={1}>
        {company ?? 'Choose a company'}
        {place ? <Text style={styles.contextPlace}>{`  ›  ${place}`}</Text> : null}
      </Text>
      <Icon name="magnify" size={18} color={brand.white} />
    </Pressable>
  );
}

const METER_TONE: Record<MeterState, 'success' | 'warning' | 'danger'> = { ok: 'success', warn_80: 'warning', warn_95: 'danger', full: 'danger' };

export function StorageBar({ fraction, state, text }: { fraction: number; state: MeterState; text: string }) {
  const p = usePalette();
  const tone = METER_TONE[state];
  const colour = tone === 'success' ? p.success : tone === 'warning' ? p.warning : p.danger;
  return (
    <View style={{ gap: space.xs }} accessibilityRole="progressbar" accessibilityLabel={text} accessibilityValue={{ min: 0, max: 100, now: Math.min(100, Math.round(fraction * 100)) }}>
      <View style={[styles.meter, { backgroundColor: p.surfaceAlt }]}>
        <View style={[styles.meterFill, { width: `${Math.max(1, Math.min(100, fraction * 100))}%`, backgroundColor: colour }]} />
      </View>
      <Txt variant="small" muted>
        {text}
      </Txt>
    </View>
  );
}

const styles = StyleSheet.create({
  search: { flexDirection: 'row', alignItems: 'center', gap: space.sm, minHeight: touch, borderWidth: 1, borderRadius: radius.pill, paddingHorizontal: space.md },
  searchInput: { flex: 1, paddingVertical: space.sm },
  clear: { padding: 2 },
  stepsRow: { flexDirection: 'row', gap: space.xs },
  stepBar: { flex: 1, height: 6, borderRadius: radius.pill },
  stepLabel: { flex: 1, textAlign: 'center' },
  crumbs: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', rowGap: space.xs },
  crumbWrap: { flexDirection: 'row', alignItems: 'center' },
  crumb: { paddingVertical: 6, paddingHorizontal: 2, maxWidth: 220 },
  placeRow: { flexDirection: 'row', alignItems: 'center', gap: space.xs, minHeight: 60, paddingRight: space.sm, borderBottomWidth: StyleSheet.hairlineWidth },
  toggle: { width: 28, height: touch, alignItems: 'center', justifyContent: 'center' },
  placeMain: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: space.md, minHeight: touch, paddingVertical: space.sm },
  placeIcon: { width: 36, height: 36, borderRadius: radius.md, alignItems: 'center', justifyContent: 'center' },
  startBtn: { width: 44, height: 44, borderRadius: radius.md, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
  context: { flexDirection: 'row', alignItems: 'center', gap: space.sm, minHeight: 40, borderRadius: radius.pill, borderWidth: 1, borderColor: onInk.border, paddingHorizontal: space.md, marginBottom: space.md },
  contextText: { flex: 1, fontFamily: fonts.bodySemiBold, fontSize: 14, color: brand.white },
  contextPlace: { fontFamily: fonts.body, color: onInk.muted },
  meter: { height: 10, borderRadius: radius.pill, overflow: 'hidden' },
  meterFill: { height: '100%', borderRadius: radius.pill },
});
