import { router } from 'expo-router';
import * as WebBrowser from 'expo-web-browser';
import { useState } from 'react';
import { View } from 'react-native';

import { AuthHero } from '@/components/auth-hero';
import { Button, Chip, ChipRow, Field, Gap, Notice, Screen, Txt } from '@/components/ui';
import { PRIVACY_URL } from '@/lib/constants';
import { lockedUntil } from '@/lib/step-up';
import { useNow } from '@/features/use-now';
import { useApp } from '@/state/app';
import { space } from '@/theme/tokens';

export default function SignInScreen() {
  const app = useApp();
  const [method, setMethod] = useState<'password' | 'code'>('password');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState<'live' | 'demo' | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [failures, setFailures] = useState(0);
  const [lastFailure, setLastFailure] = useState<number | null>(null);

  const now = useNow(5000);
  const until = lockedUntil(failures, lastFailure);
  const locked = until !== null && until > now;

  const signInLive = async () => {
    setError(null);
    if (locked) return;
    setBusy('live');
    try {
      const backend = await app.chooseMode('live');
      if (method === 'password') {
        await backend.signInWithPassword(email, password);
        setFailures(0);
        await app.afterSignIn();
      } else {
        await backend.sendEmailCode(email);
        router.push({ pathname: '/email-code', params: { email } });
      }
    } catch (e) {
      setFailures((f) => f + 1);
      setLastFailure(Date.now());
      setError(e instanceof Error ? e.message : 'Sign in did not work.');
    } finally {
      setBusy(null);
    }
  };

  const tryDemo = async () => {
    setError(null);
    setBusy('demo');
    try {
      const backend = await app.chooseMode('demo');
      await backend.signInWithPassword('thandi.inspector.demo@example.invalid', 'demonstration');
      await app.afterSignIn();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The demo could not start.');
    } finally {
      setBusy(null);
    }
  };

  return (
    <View style={{ flex: 1 }}>
      <AuthHero line="Walk the site room by room, capture the evidence, and sign the report. Issued reports file into Section F of your free Health and Safety File." />
      <Screen edges={['bottom']}>
        {app.liveAvailable ? (
          <>
            <ChipRow>
              <Chip label="Email and password" selected={method === 'password'} onPress={() => setMethod('password')} />
              <Chip label="Email code or link" selected={method === 'code'} onPress={() => setMethod('code')} />
            </ChipRow>
            <Field label="Email address" value={email} onChangeText={setEmail} autoCapitalize="none" autoComplete="email" keyboardType="email-address" inputMode="email" textContentType="emailAddress" />
            {method === 'password' ? (
              <Field label="Password" value={password} onChangeText={setPassword} secureTextEntry autoComplete="password" textContentType="password" />
            ) : (
              <Txt variant="small" muted>
                We email you a six digit code and a sign in link. Use whichever reaches you first.
              </Txt>
            )}
            {locked ? <Notice tone="warning" title="Too many attempts">Sign in is paused for a short while. Try again in a minute, or reset your password by email.</Notice> : null}
            {error ? <Notice tone="danger">{error}</Notice> : null}
            <Button title={method === 'password' ? 'Sign in' : 'Email me a code'} onPress={signInLive} busy={busy === 'live'} disabled={!email.trim() || (method === 'password' && !password) || locked} />
            <Button title="Sign in with a claim code" icon="qrcode-scan" kind="secondary" onPress={() => router.push('/claim')} />
          </>
        ) : (
          <>
            <Notice tone="info" title="Live sign in is not set up on this build">
              This build has no server settings yet, so only the demo is available. The demo works fully offline with fictitious data.
            </Notice>
            {error ? <Notice tone="danger">{error}</Notice> : null}
            <Button title="Sign in with a claim code" icon="qrcode-scan" kind="secondary" onPress={() => router.push('/claim')} />
          </>
        )}
        <Gap size="sm" />
        <View style={{ gap: space.sm }}>
          <Button title="Try the demo" icon="play-circle-outline" kind={app.liveAvailable ? 'ghost' : 'primary'} onPress={tryDemo} busy={busy === 'demo'} accessibilityHint="Opens Bee-Inspect with fictitious Rietvlei Civils and Building data. Nothing is sent anywhere." />
          <Txt variant="tiny" muted style={{ textAlign: 'center' }}>
            The demo uses the fictitious Rietvlei Civils and Building company. Nothing is sent anywhere.
          </Txt>
        </View>
        <Gap size="md" />
        <Txt variant="tiny" muted>
          Bee-Inspect holds health and safety inspection and risk assessment data only, never medical results. Your information is processed in line with POPIA.
        </Txt>
        <Button title="Privacy policy" kind="ghost" compact onPress={() => WebBrowser.openBrowserAsync(PRIVACY_URL)} />
      </Screen>
    </View>
  );
}
