// Bee-Inspect building blocks. Every colour, size and font comes from
// src/theme/tokens.ts; screens compose these instead of styling from scratch.

import MaterialCommunityIcons from '@expo/vector-icons/MaterialCommunityIcons';
import type { ComponentProps, ReactNode } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  type StyleProp,
  type TextInputProps,
  type TextStyle,
  type ViewStyle,
} from 'react-native';
import { SafeAreaView, type Edge } from 'react-native-safe-area-context';

import { maxContentWidth, radius, space, touch, type as typeScale } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

export type IconName = ComponentProps<typeof MaterialCommunityIcons>['name'];

export function Icon({ name, size = 22, color }: { name: IconName; size?: number; color?: string }) {
  const p = usePalette();
  return <MaterialCommunityIcons name={name} size={size} color={color ?? p.text} accessibilityElementsHidden importantForAccessibility="no" />;
}

type TextVariant = keyof typeof typeScale;

export function Txt({
  children,
  variant = 'body',
  muted,
  color,
  style,
  numberOfLines,
  accessibilityRole,
}: {
  children: ReactNode;
  variant?: TextVariant;
  muted?: boolean;
  color?: string;
  style?: StyleProp<TextStyle>;
  numberOfLines?: number;
  accessibilityRole?: 'header' | 'text' | 'link' | 'alert';
}) {
  const p = usePalette();
  return (
    <Text
      style={[typeScale[variant] as TextStyle, { color: color ?? (muted ? p.textMuted : p.text) }, style]}
      numberOfLines={numberOfLines}
      accessibilityRole={accessibilityRole}>
      {children}
    </Text>
  );
}

export function Heading({ children, level = 2, color, style }: { children: ReactNode; level?: 1 | 2 | 3; color?: string; style?: StyleProp<TextStyle> }) {
  const variant = level === 1 ? 'h1' : level === 2 ? 'h2' : 'h3';
  return (
    <Txt variant={variant} color={color} style={style} accessibilityRole="header">
      {children}
    </Txt>
  );
}

export function Screen({
  children,
  scroll = true,
  edges = ['bottom'],
  padded = true,
  footer,
}: {
  children: ReactNode;
  scroll?: boolean;
  edges?: Edge[];
  padded?: boolean;
  footer?: ReactNode;
}) {
  const p = usePalette();
  const inner = <View style={[styles.content, padded && styles.padded]}>{children}</View>;
  return (
    <SafeAreaView edges={edges} style={{ flex: 1, backgroundColor: p.background }}>
      {scroll ? (
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled" contentInsetAdjustmentBehavior="automatic">
          {inner}
        </ScrollView>
      ) : (
        inner
      )}
      {footer ? <View style={[styles.footer, { borderTopColor: p.border, backgroundColor: p.surface }]}>{footer}</View> : null}
    </SafeAreaView>
  );
}

type ButtonKind = 'primary' | 'secondary' | 'ghost' | 'danger';

export function Button({
  title,
  onPress,
  kind = 'primary',
  disabled,
  busy,
  icon,
  accessibilityHint,
  style,
  compact,
}: {
  title: string;
  onPress?: () => void;
  kind?: ButtonKind;
  disabled?: boolean;
  busy?: boolean;
  icon?: IconName;
  accessibilityHint?: string;
  style?: StyleProp<ViewStyle>;
  compact?: boolean;
}) {
  const p = usePalette();
  const off = disabled || busy;
  const bg = kind === 'primary' ? p.primary : kind === 'danger' ? p.danger : kind === 'secondary' ? p.surface : 'transparent';
  const fg = kind === 'primary' || kind === 'danger' ? p.onPrimary : p.text;
  const border = kind === 'secondary' ? p.border : 'transparent';
  return (
    <Pressable
      onPress={off ? undefined : onPress}
      accessibilityRole="button"
      accessibilityState={{ disabled: !!off, busy: !!busy }}
      accessibilityHint={accessibilityHint}
      style={({ pressed }) => [
        styles.button,
        compact && styles.buttonCompact,
        { backgroundColor: pressed && kind === 'primary' ? p.primaryPressed : bg, borderColor: border, opacity: off ? 0.5 : 1 },
        style,
      ]}>
      {busy ? <ActivityIndicator color={fg} /> : icon ? <Icon name={icon} size={20} color={fg} /> : null}
      <Text style={[typeScale.button, { color: fg }]}>{title}</Text>
    </Pressable>
  );
}

export function Card({ children, style, onPress, accessibilityLabel }: { children: ReactNode; style?: StyleProp<ViewStyle>; onPress?: () => void; accessibilityLabel?: string }) {
  const p = usePalette();
  const s = [styles.card, { backgroundColor: p.surface, borderColor: p.border }, style];
  if (onPress) {
    return (
      <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={accessibilityLabel} style={({ pressed }) => [s, pressed && { opacity: 0.85 }]}>
        {children}
      </Pressable>
    );
  }
  return <View style={s}>{children}</View>;
}

export function Chip({
  label,
  selected,
  onPress,
  tone,
  accessibilityLabel,
}: {
  label: string;
  selected?: boolean;
  onPress?: () => void;
  tone?: { bg: string; fg: string };
  accessibilityLabel?: string;
}) {
  const p = usePalette();
  const bg = selected ? (tone ? tone.bg : p.text) : p.surface;
  const fg = selected ? (tone ? tone.fg : p.background) : p.text;
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole={onPress ? 'button' : 'text'}
      accessibilityState={{ selected: !!selected }}
      accessibilityLabel={accessibilityLabel ?? label}
      style={[styles.chip, { backgroundColor: bg, borderColor: selected ? bg : p.border }]}>
      <Text style={[typeScale.smallStrong, { color: fg }]}>{label}</Text>
    </Pressable>
  );
}

export function ChipRow({ children }: { children: ReactNode }) {
  return <View style={styles.chipRow}>{children}</View>;
}

export function Field({
  label,
  hint,
  error,
  style,
  ...input
}: TextInputProps & { label: string; hint?: string; error?: string | null; style?: StyleProp<ViewStyle> }) {
  const p = usePalette();
  return (
    <View style={[styles.field, style]}>
      <Txt variant="smallStrong">{label}</Txt>
      {hint ? (
        <Txt variant="tiny" muted>
          {hint}
        </Txt>
      ) : null}
      <TextInput
        accessibilityLabel={label}
        placeholderTextColor={p.textMuted}
        {...input}
        style={[
          styles.input,
          typeScale.body as TextStyle,
          { color: p.text, backgroundColor: p.surface, borderColor: error ? p.danger : p.border },
          input.multiline && { minHeight: 96, textAlignVertical: 'top' },
        ]}
      />
      {error ? (
        <Txt variant="tiny" color={p.danger} accessibilityRole="alert">
          {error}
        </Txt>
      ) : null}
    </View>
  );
}

type Tone = 'info' | 'success' | 'warning' | 'danger';

export function Notice({ tone = 'info', title, children, icon }: { tone?: Tone; title?: string; children?: ReactNode; icon?: IconName }) {
  const p = usePalette();
  const map = {
    info: { fg: p.info, bg: p.infoBg, icon: 'information-outline' as IconName },
    success: { fg: p.success, bg: p.successBg, icon: 'check-circle-outline' as IconName },
    warning: { fg: p.warning, bg: p.warningBg, icon: 'alert-outline' as IconName },
    danger: { fg: p.danger, bg: p.dangerBg, icon: 'alert-octagon-outline' as IconName },
  }[tone];
  return (
    <View style={[styles.notice, { backgroundColor: map.bg, borderLeftColor: map.fg }]} accessibilityRole={tone === 'danger' || tone === 'warning' ? 'alert' : undefined}>
      <Icon name={icon ?? map.icon} size={20} color={map.fg} />
      <View style={{ flex: 1, gap: 2 }}>
        {title ? (
          <Txt variant="smallStrong" color={map.fg}>
            {title}
          </Txt>
        ) : null}
        {typeof children === 'string' ? (
          <Txt variant="small" color={p.text}>
            {children}
          </Txt>
        ) : (
          children
        )}
      </View>
    </View>
  );
}

export function Pill({ label, tone = 'info', solid }: { label: string; tone?: Tone | 'neutral'; solid?: { bg: string; fg: string } }) {
  const p = usePalette();
  const map = {
    info: { fg: p.info, bg: p.infoBg },
    success: { fg: p.success, bg: p.successBg },
    warning: { fg: p.warning, bg: p.warningBg },
    danger: { fg: p.danger, bg: p.dangerBg },
    neutral: { fg: p.textMuted, bg: p.surfaceAlt },
  }[tone];
  const c = solid ?? map;
  return (
    <View style={[styles.pill, { backgroundColor: c.bg }]}>
      <Text style={[typeScale.tiny as TextStyle, { color: c.fg, fontFamily: 'Inter-SemiBold' }]}>{label}</Text>
    </View>
  );
}

export function ListRow({
  title,
  subtitle,
  right,
  icon,
  onPress,
  accessibilityLabel,
}: {
  title: string;
  subtitle?: string;
  right?: ReactNode;
  icon?: IconName;
  onPress?: () => void;
  accessibilityLabel?: string;
}) {
  const p = usePalette();
  const body = (
    <>
      {icon ? <Icon name={icon} color={p.textMuted} /> : null}
      <View style={{ flex: 1, gap: 2 }}>
        <Txt variant="bodyStrong">{title}</Txt>
        {subtitle ? (
          <Txt variant="small" muted>
            {subtitle}
          </Txt>
        ) : null}
      </View>
      {right}
      {onPress ? <Icon name="chevron-right" color={p.textMuted} /> : null}
    </>
  );
  if (!onPress) return <View style={[styles.row, { borderBottomColor: p.border }]}>{body}</View>;
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? title}
      style={({ pressed }) => [styles.row, { borderBottomColor: p.border, backgroundColor: pressed ? p.surfaceAlt : 'transparent' }]}>
      {body}
    </Pressable>
  );
}

export function SectionTitle({ children, action }: { children: string; action?: ReactNode }) {
  return (
    <View style={styles.sectionTitle}>
      <Heading level={3}>{children}</Heading>
      {action}
    </View>
  );
}

export function Gap({ size = 'lg' }: { size?: keyof typeof space }) {
  return <View style={{ height: space[size] }} />;
}

export function KeyValue({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.kv}>
      <Txt variant="small" muted style={{ flex: 1 }}>
        {label}
      </Txt>
      <Txt variant="smallStrong" style={{ flexShrink: 1, maxWidth: '62%', textAlign: 'right' }}>
        {value}
      </Txt>
    </View>
  );
}

export function EmptyState({ icon, title, body, action }: { icon: IconName; title: string; body?: string; action?: ReactNode }) {
  const p = usePalette();
  return (
    <View style={styles.empty}>
      <Icon name={icon} size={40} color={p.textMuted} />
      <Txt variant="bodyStrong" style={{ textAlign: 'center' }}>
        {title}
      </Txt>
      {body ? (
        <Txt variant="small" muted style={{ textAlign: 'center' }}>
          {body}
        </Txt>
      ) : null}
      {action}
    </View>
  );
}

const styles = StyleSheet.create({
  scroll: { flexGrow: 1 },
  content: { width: '100%', maxWidth: maxContentWidth, alignSelf: 'center', gap: space.lg },
  padded: { paddingHorizontal: space.lg, paddingVertical: space.lg },
  footer: { paddingHorizontal: space.lg, paddingVertical: space.md, borderTopWidth: StyleSheet.hairlineWidth, gap: space.sm },
  button: {
    minHeight: touch,
    paddingHorizontal: space.lg,
    borderRadius: radius.md,
    borderWidth: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: space.sm,
  },
  buttonCompact: { minHeight: 40, paddingHorizontal: space.md },
  card: { borderRadius: radius.lg, borderWidth: 1, padding: space.lg, gap: space.sm },
  chip: { minHeight: 40, paddingHorizontal: space.md, borderRadius: radius.pill, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm },
  field: { gap: space.xs },
  input: { minHeight: touch, borderWidth: 1, borderRadius: radius.md, paddingHorizontal: space.md, paddingVertical: space.sm },
  notice: { flexDirection: 'row', gap: space.sm, padding: space.md, borderRadius: radius.md, borderLeftWidth: 4 },
  pill: { alignSelf: 'flex-start', paddingHorizontal: space.sm, paddingVertical: 3, borderRadius: radius.pill },
  row: { flexDirection: 'row', alignItems: 'center', gap: space.md, minHeight: 56, paddingVertical: space.sm, borderBottomWidth: StyleSheet.hairlineWidth },
  sectionTitle: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: space.sm, marginTop: space.sm },
  kv: { flexDirection: 'row', gap: space.md, paddingVertical: space.xs },
  empty: { alignItems: 'center', gap: space.sm, paddingVertical: space.xl },
});
