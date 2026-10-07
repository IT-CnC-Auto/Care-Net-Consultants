// Risk display and the 5 x 5 picker. Every rating shows the number AND the
// band label (decision 1.2); colour is never the only signal.

import { Pressable, StyleSheet, Text, View } from 'react-native';

import { BAND_COLOUR, BAND_LABEL, LIKELIHOOD_LABEL, riskBand, riskScore, SEVERITY_LABEL } from '@/lib/risk';
import { fonts, radius, space, type as t } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

import { Txt } from './ui';

export function RiskBadge({ score, prefix, large }: { score: number | null; prefix?: string; large?: boolean }) {
  const p = usePalette();
  const band = riskBand(score);
  if (!band) {
    return (
      <View style={[styles.badge, { backgroundColor: p.surfaceAlt }]}>
        <Text style={[t.smallStrong, { color: p.textMuted }]}>{prefix ? `${prefix}: ` : ''}Not rated</Text>
      </View>
    );
  }
  const c = BAND_COLOUR[band];
  return (
    <View style={[styles.badge, large && styles.badgeLarge, { backgroundColor: c.bg }]} accessibilityLabel={`${prefix ? prefix + ' ' : ''}risk ${score}, ${BAND_LABEL[band]}`}>
      <Text style={[large ? styles.bigNum : t.smallStrong, { color: c.fg }]}>
        {prefix ? `${prefix}: ` : ''}
        {score} {BAND_LABEL[band]}
      </Text>
    </View>
  );
}

/** Tap a cell: likelihood down the side (5 at the top), severity along the bottom. */
export function RiskMatrix({
  likelihood,
  severity,
  onChange,
  maxScore,
  label,
}: {
  likelihood: number | null;
  severity: number | null;
  onChange: (l: number, s: number) => void;
  maxScore?: number;
  label: string;
}) {
  const p = usePalette();
  const score = riskScore(likelihood, severity);
  return (
    <View style={{ gap: space.sm }} accessibilityLabel={label}>
      <View style={styles.header}>
        <Txt variant="smallStrong">{label}</Txt>
        <RiskBadge score={score} />
      </View>
      {[5, 4, 3, 2, 1].map((l) => (
        <View key={l} style={styles.gridRow}>
          <Text style={[styles.axis, { color: p.textMuted }]} numberOfLines={1}>
            {l}
          </Text>
          {[1, 2, 3, 4, 5].map((s) => {
            const sc = l * s;
            const band = riskBand(sc)!;
            const c = BAND_COLOUR[band];
            const selected = likelihood === l && severity === s;
            const disabled = maxScore !== undefined && sc > maxScore;
            return (
              <Pressable
                key={s}
                disabled={disabled}
                onPress={() => onChange(l, s)}
                accessibilityRole="button"
                accessibilityState={{ selected, disabled }}
                accessibilityLabel={`Likelihood ${l} ${LIKELIHOOD_LABEL[l - 1]}, severity ${s} ${SEVERITY_LABEL[s - 1]}: ${sc} ${BAND_LABEL[band]}`}
                style={[
                  styles.cell,
                  { backgroundColor: c.bg, opacity: disabled ? 0.25 : selected ? 1 : 0.55, borderColor: selected ? p.text : 'transparent' },
                ]}>
                <Text style={[styles.cellText, { color: c.fg }]}>{sc}</Text>
              </Pressable>
            );
          })}
        </View>
      ))}
      <View style={styles.gridRow}>
        <Text style={styles.axis} />
        {[1, 2, 3, 4, 5].map((s) => (
          <Text key={s} style={[styles.axisBottom, { color: p.textMuted }]}>
            {s}
          </Text>
        ))}
      </View>
      <Txt variant="tiny" muted>
        Likelihood (side) {likelihood ? `${likelihood} ${LIKELIHOOD_LABEL[likelihood - 1]}` : 'not chosen'} · Severity (bottom) {severity ? `${severity} ${SEVERITY_LABEL[severity - 1]}` : 'not chosen'}
      </Txt>
    </View>
  );
}

export function BandLegend() {
  return (
    <View style={styles.legend}>
      {(['low', 'medium', 'high', 'extreme'] as const).map((b) => (
        <View key={b} style={[styles.legendItem, { backgroundColor: BAND_COLOUR[b].bg }]}>
          <Text style={[t.tiny, { color: BAND_COLOUR[b].fg, fontFamily: fonts.bodySemiBold }]}>
            {b === 'low' ? '1 to 4' : b === 'medium' ? '5 to 9' : b === 'high' ? '10 to 15' : '16 to 25'} {BAND_LABEL[b]}
          </Text>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  badge: { alignSelf: 'flex-start', paddingHorizontal: space.sm, paddingVertical: 4, borderRadius: radius.sm },
  badgeLarge: { paddingHorizontal: space.md, paddingVertical: space.sm },
  bigNum: { fontFamily: fonts.heading, fontSize: 24, lineHeight: 26 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  gridRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  axis: { width: 18, textAlign: 'center', ...t.tiny },
  axisBottom: { flex: 1, textAlign: 'center', ...t.tiny },
  cell: { flex: 1, aspectRatio: 1.4, borderRadius: radius.sm, alignItems: 'center', justifyContent: 'center', borderWidth: 3 },
  cellText: { fontFamily: fonts.bodyBold, fontSize: 14 },
  legend: { flexDirection: 'row', flexWrap: 'wrap', gap: space.xs },
  legendItem: { paddingHorizontal: space.sm, paddingVertical: 3, borderRadius: radius.sm },
});
