// Web preview tab bar: a bottom bar at phone width, built with expo-router/ui.

import { TabList, TabSlot, TabTrigger, Tabs, type TabTriggerSlotProps } from 'expo-router/ui';
import { forwardRef } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { brand, fonts, space } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

import { Icon, type IconName } from './ui';

const TABS: { name: string; href: '/' | '/sites' | '/evidence' | '/wallet' | '/account'; label: string; icon: IconName }[] = [
  { name: 'index', href: '/', label: 'Home', icon: 'home-outline' },
  { name: 'sites', href: '/sites', label: 'Places', icon: 'file-tree-outline' },
  { name: 'evidence', href: '/evidence', label: 'Evidence', icon: 'folder-image' },
  { name: 'wallet', href: '/wallet', label: 'Wallet', icon: 'wallet-outline' },
  { name: 'account', href: '/account', label: 'Account', icon: 'account-circle-outline' },
];

const TabButton = forwardRef<View, TabTriggerSlotProps & { label: string; icon: IconName }>(function TabButton({ isFocused, label, icon, ...props }, ref) {
  const p = usePalette();
  const color = isFocused ? brand.deepRed : p.textMuted;
  return (
    <Pressable ref={ref} {...props} accessibilityRole="tab" accessibilityState={{ selected: !!isFocused }} style={styles.tab}>
      <Icon name={icon} color={color} size={24} />
      <Text style={[styles.label, { color }]}>{label}</Text>
    </Pressable>
  );
});

export default function AppTabs() {
  const p = usePalette();
  return (
    <Tabs>
      <TabSlot style={{ flex: 1 }} />
      <TabList style={[styles.bar, { backgroundColor: p.surface, borderTopColor: p.border }]}>
        {TABS.map((t) => (
          <TabTrigger key={t.name} name={t.name} href={t.href} asChild>
            <TabButton label={t.label} icon={t.icon} />
          </TabTrigger>
        ))}
      </TabList>
    </Tabs>
  );
}

const styles = StyleSheet.create({
  bar: { flexDirection: 'row', borderTopWidth: StyleSheet.hairlineWidth, paddingBottom: space.xs },
  tab: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: space.sm, gap: 2, minHeight: 56 },
  label: { fontFamily: fonts.bodySemiBold, fontSize: 12 },
});
