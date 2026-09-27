// Native tab bar on iOS and Android (SDK 57 NativeTabs). The web preview uses
// app-tabs.web.tsx.

import { NativeTabs } from 'expo-router/unstable-native-tabs';

import { brand } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

export default function AppTabs() {
  const p = usePalette();
  return (
    <NativeTabs tintColor={brand.deepRed} backgroundColor={p.surface}>
      <NativeTabs.Trigger name="index">
        <NativeTabs.Trigger.Icon sf={{ default: 'house', selected: 'house.fill' }} md="home" />
        <NativeTabs.Trigger.Label>Home</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="sites">
        <NativeTabs.Trigger.Icon sf="building.2" md="account_tree" />
        <NativeTabs.Trigger.Label>Sites</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="wallet">
        <NativeTabs.Trigger.Icon sf="creditcard" md="account_balance_wallet" />
        <NativeTabs.Trigger.Label>Wallet</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="account">
        <NativeTabs.Trigger.Icon sf="person.crop.circle" md="person" />
        <NativeTabs.Trigger.Label>Account</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
