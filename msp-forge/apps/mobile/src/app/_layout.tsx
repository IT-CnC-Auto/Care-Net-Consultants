import { useFonts } from 'expo-font';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { useColorScheme } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { AppProvider, useApp } from '@/state/app';
import { stackHeader } from '@/theme/navigation';

SplashScreen.preventAutoHideAsync().catch(() => {});

export default function RootLayout() {
  const [loaded, error] = useFonts({
    BebasNeue: require('@/assets/fonts/BebasNeue-Regular.ttf'),
    Inter: require('@/assets/fonts/Inter-Regular.ttf'),
    'Inter-SemiBold': require('@/assets/fonts/Inter-SemiBold.ttf'),
    'Inter-Bold': require('@/assets/fonts/Inter-Bold.ttf'),
  });
  return (
    <SafeAreaProvider>
      <AppProvider>
        <Gate fontsReady={loaded || !!error} />
      </AppProvider>
    </SafeAreaProvider>
  );
}

function Gate({ fontsReady }: { fontsReady: boolean }) {
  const { phase } = useApp();
  const scheme = useColorScheme();
  const ready = fontsReady && phase !== 'booting';

  useEffect(() => {
    if (ready) SplashScreen.hideAsync().catch(() => {});
  }, [ready]);

  if (!ready) return null;

  return (
    <ThemeProvider value={scheme === 'dark' ? DarkTheme : DefaultTheme}>
      <StatusBar style="light" />
      <Stack screenOptions={stackHeader}>
        <Stack.Protected guard={phase === 'signed_out'}>
          <Stack.Screen name="sign-in" options={{ headerShown: false }} />
          <Stack.Screen name="email-code" options={{ title: 'Email code' }} />
          <Stack.Screen name="claim" options={{ title: 'Claim code' }} />
        </Stack.Protected>
        <Stack.Protected guard={phase === 'needs_mfa_enrol'}>
          <Stack.Screen name="mfa-enrol" options={{ title: 'Set up MFA', headerBackVisible: false }} />
        </Stack.Protected>
        <Stack.Protected guard={phase === 'needs_mfa_verify'}>
          <Stack.Screen name="mfa-verify" options={{ title: 'Confirm it is you', headerBackVisible: false }} />
        </Stack.Protected>
        <Stack.Protected guard={phase === 'locked'}>
          <Stack.Screen name="unlock" options={{ headerShown: false }} />
        </Stack.Protected>
        <Stack.Protected guard={phase === 'problem'}>
          <Stack.Screen name="problem" options={{ title: 'Bee-Inspect' }} />
        </Stack.Protected>
        <Stack.Protected guard={phase === 'ready'}>
          <Stack.Screen name="(app)" options={{ headerShown: false }} />
        </Stack.Protected>
        <Stack.Screen name="auth-callback" options={{ title: 'Signing in' }} />
      </Stack>
    </ThemeProvider>
  );
}
