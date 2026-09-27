import { Stack } from 'expo-router';

import { stackHeader } from '@/theme/navigation';

export default function AppLayout() {
  return (
    <Stack screenOptions={stackHeader}>
      <Stack.Screen name="(tabs)" options={{ headerShown: false, title: 'Home' }} />
      <Stack.Screen name="inspection/new" options={{ title: 'Start inspection' }} />
      <Stack.Screen name="inspection/[id]/index" options={{ title: 'Inspection' }} />
      <Stack.Screen name="inspection/[id]/area/[areaId]" options={{ title: 'Area' }} />
      <Stack.Screen name="inspection/[id]/item" options={{ title: 'Checklist item' }} />
      <Stack.Screen name="inspection/[id]/draft" options={{ title: 'Report draft' }} />
      <Stack.Screen name="inspection/[id]/sign" options={{ title: 'Sign off' }} />
      <Stack.Screen name="site-new" options={{ title: 'Add to sites', presentation: 'modal' }} />
      <Stack.Screen name="step-up" options={{ title: 'Confirm it is you', presentation: 'modal' }} />
      <Stack.Screen name="scan" options={{ title: 'Scan a tag', presentation: 'modal' }} />
      <Stack.Screen name="sync" options={{ title: 'Sync' }} />
      <Stack.Screen name="account/organisation" options={{ title: 'Organisation' }} />
      <Stack.Screen name="account/persons" options={{ title: 'Authorised persons' }} />
      <Stack.Screen name="account/person" options={{ title: 'Authorised person', presentation: 'modal' }} />
      <Stack.Screen name="account/qualifications" options={{ title: 'Qualifications' }} />
      <Stack.Screen name="account/consents" options={{ title: 'POPIA consents' }} />
      <Stack.Screen name="account/inspector" options={{ title: 'Inspector status' }} />
      <Stack.Screen name="account/security" options={{ title: 'Security' }} />
      <Stack.Screen name="account/demo" options={{ title: 'Demo controls' }} />
    </Stack>
  );
}
