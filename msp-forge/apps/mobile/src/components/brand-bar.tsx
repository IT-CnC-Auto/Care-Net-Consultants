import { useSyncExternalStore } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { router } from 'expo-router';

import { useQueueSummary } from '@/data/hooks';
import { useApp } from '@/state/app';
import { brand, fonts, onInk, radius, space, type as t } from '@/theme/tokens';

import { Icon } from './ui';

const noop = () => () => {};

/** The ink bar at the top of each tab: the Bee-Inspect wordmark, the mode and the sync state. */
export function BrandBar({ title }: { title?: string }) {
  const insets = useSafeAreaInsets();
  const { mode, engine } = useApp();
  const { summary } = useQueueSummary();
  const waiting = summary.pending + summary.waitingServer;
  const trouble = summary.conflicts + summary.failed;
  const syncState = useSyncExternalStore(engine ? engine.subscribe : noop, () => engine?.getState() ?? null, () => engine?.getState() ?? null);
  const paused = syncState?.paused;
  const label = trouble > 0 ? `${trouble} to check` : waiting > 0 ? `${waiting} waiting` : 'All synced';
  return (
    <View style={[styles.bar, { paddingTop: insets.top + space.sm }]}>
      <View style={styles.row}>
        <View style={{ flex: 1 }}>
          <Text style={styles.word} accessibilityRole="header">
            BEE-INSPECT
          </Text>
          {title ? <Text style={styles.title}>{title}</Text> : null}
        </View>
        {mode === 'demo' ? (
          <View style={styles.demo} accessibilityLabel="Demonstration mode">
            <Text style={styles.demoText}>DEMO</Text>
          </View>
        ) : null}
        <Pressable
          onPress={() => router.push('/sync')}
          accessibilityRole="button"
          accessibilityLabel={`Sync: ${label}${paused ? ', paused' : ''}`}
          style={styles.sync}>
          <Icon name={trouble > 0 ? 'cloud-alert' : waiting > 0 || paused ? 'cloud-upload-outline' : 'cloud-check-outline'} size={20} color={trouble > 0 ? brand.gold : brand.white} />
          <Text style={styles.syncText}>{paused ? 'Paused' : label}</Text>
        </Pressable>
      </View>
      <View style={styles.stripe} />
    </View>
  );
}

const styles = StyleSheet.create({
  bar: { backgroundColor: brand.ink, paddingHorizontal: space.lg },
  row: { flexDirection: 'row', alignItems: 'center', gap: space.sm, paddingBottom: space.md },
  word: { fontFamily: fonts.heading, fontSize: 30, lineHeight: 32, color: brand.white, letterSpacing: 1 },
  title: { ...t.small, color: onInk.muted },
  demo: { backgroundColor: brand.gold, borderRadius: radius.sm, paddingHorizontal: space.sm, paddingVertical: 2 },
  demoText: { fontFamily: fonts.bodyBold, fontSize: 12, color: brand.ink, letterSpacing: 1 },
  sync: { flexDirection: 'row', alignItems: 'center', gap: space.xs, minHeight: 40, paddingHorizontal: space.sm, borderRadius: radius.md, borderWidth: 1, borderColor: onInk.border },
  syncText: { ...t.tiny, color: brand.white, fontFamily: fonts.bodySemiBold },
  stripe: { height: 4, backgroundColor: brand.red, marginHorizontal: -space.lg },
});
