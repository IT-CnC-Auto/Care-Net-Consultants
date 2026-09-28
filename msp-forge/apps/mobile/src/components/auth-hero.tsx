import { StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { brand, fonts, onInk, space, type as t } from '@/theme/tokens';

export function AuthHero({ line }: { line: string }) {
  const insets = useSafeAreaInsets();
  return (
    <View style={[styles.hero, { paddingTop: insets.top + space.xl }]}>
      <Text style={styles.eyebrow}>CARE NET CONSULTANTS</Text>
      <Text style={styles.word} accessibilityRole="header">
        BEE-INSPECT
      </Text>
      <Text style={styles.line}>{line}</Text>
      <View style={styles.stripe}>
        <View style={[styles.band, { backgroundColor: brand.red }]} />
        <View style={[styles.band, { backgroundColor: brand.gold, flex: 0.35 }]} />
        <View style={[styles.band, { backgroundColor: brand.deepRed, flex: 0.6 }]} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  hero: { backgroundColor: brand.ink, paddingHorizontal: space.lg, paddingBottom: 0, gap: space.xs },
  eyebrow: { fontFamily: fonts.bodySemiBold, fontSize: 12, letterSpacing: 2, color: brand.gold },
  word: { fontFamily: fonts.heading, fontSize: 56, lineHeight: 58, color: brand.white, letterSpacing: 1.5 },
  line: { ...t.body, color: onInk.soft, marginBottom: space.lg },
  stripe: { flexDirection: 'row', height: 6, marginHorizontal: -space.lg },
  band: { flex: 1 },
});
