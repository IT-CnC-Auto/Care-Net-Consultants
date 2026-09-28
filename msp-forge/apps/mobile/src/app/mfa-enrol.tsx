import * as Linking from 'expo-linking';
import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { SvgXml } from 'react-native-svg';

import type { TotpEnrolment } from '@/backend/types';
import { Button, Card, Field, Heading, Notice, Screen, Txt } from '@/components/ui';
import { isSixDigitCode } from '@/lib/step-up';
import { useApp } from '@/state/app';
import { brand, light, radius, space } from '@/theme/tokens';

export default function MfaEnrolScreen() {
  const app = useApp();
  const [enrolment, setEnrolment] = useState<TotpEnrolment | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    app.backend
      ?.enrolTotp()
      .then(setEnrolment)
      .catch((e: unknown) => setError(e instanceof Error ? e.message : 'The authenticator could not be set up.'));
  }, [app.backend]);

  const verify = async () => {
    if (!enrolment) return;
    setError(null);
    setBusy(true);
    try {
      await app.backend?.verifyTotp(code, enrolment.factorId);
      await app.completeMfa();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That code did not work.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Screen>
      <Heading>Protect your account</Heading>
      <Txt muted>Inspectors confirm sign in with an authenticator app. You also use it to sign reports and approve large top ups.</Txt>
      {app.mode === 'demo' ? <Notice tone="info" title="Demo">This is a demonstration. Any six digit code works.</Notice> : null}
      <Card>
        <Txt variant="bodyStrong">1. Add Bee-Inspect to your authenticator app</Txt>
        {enrolment?.qrSvg ? (
          <View style={styles.qr} accessibilityLabel="QR code for your authenticator app">
            <SvgXml xml={enrolment.qrSvg} width="100%" height="100%" />
          </View>
        ) : (
          <View style={[styles.qr, styles.qrEmpty]}>
            <Txt variant="small" muted style={{ textAlign: 'center' }}>
              {app.mode === 'demo' ? 'In live mode, the QR code for your authenticator app shows here.' : 'Preparing your code…'}
            </Txt>
          </View>
        )}
        {enrolment ? (
          <>
            <Txt variant="small" muted>
              Or type this key into the app:
            </Txt>
            <Txt variant="bodyStrong" style={{ letterSpacing: 2 }}>
              {enrolment.secret.replace(/(.{4})/g, '$1 ').trim()}
            </Txt>
            <Button title="Open my authenticator app" icon="open-in-new" kind="secondary" compact onPress={() => Linking.openURL(enrolment.uri).catch(() => setError('No authenticator app on this phone opened the link. Type the key instead.'))} />
          </>
        ) : null}
      </Card>
      <Card>
        <Txt variant="bodyStrong">2. Type the six digit code it shows</Txt>
        <Field label="Code from your authenticator app" value={code} onChangeText={(t) => setCode(t.replace(/\D/g, '').slice(0, 6))} keyboardType="number-pad" inputMode="numeric" autoComplete="one-time-code" maxLength={6} />
      </Card>
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <Button title="Turn on MFA" onPress={verify} busy={busy} disabled={!enrolment || !isSixDigitCode(code)} />
      <Button title="Sign out" kind="ghost" onPress={app.signOut} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  qr: { width: 200, height: 200, alignSelf: 'center', backgroundColor: brand.white, padding: space.sm, borderRadius: radius.md },
  qrEmpty: { alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: light.border, borderStyle: 'dashed' },
});
