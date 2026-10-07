// Step up MFA before Issue, sign off, Bee-Matched engagement and top ups over
// R499,00 (prompt B3). Valid 10 minutes in the app (decision 1.5).

import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';

import { Button, Field, Heading, Notice, Screen, Txt } from '@/components/ui';
import { isSixDigitCode, STEP_UP_PURPOSE_TEXT, type StepUpPurpose } from '@/lib/step-up';
import { useApp } from '@/state/app';

export default function StepUpScreen() {
  const app = useApp();
  const { purpose = 'signoff' } = useLocalSearchParams<{ purpose?: StepUpPurpose }>();
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const confirm = async () => {
    setError(null);
    setBusy(true);
    try {
      await app.backend?.verifyTotp(code);
      await app.markStepUp(purpose);
      router.back();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That code did not work.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Screen>
      <Heading>Confirm it is you</Heading>
      <Txt muted>{`To ${STEP_UP_PURPOSE_TEXT[purpose] ?? 'continue'}, type the six digit code from your authenticator app. It stays confirmed for 10 minutes.`}</Txt>
      {app.mode === 'demo' ? <Notice tone="info" title="Demo">This is a demonstration. Any six digit code works.</Notice> : null}
      <Field label="Code from your authenticator app" value={code} onChangeText={(t) => setCode(t.replace(/\D/g, '').slice(0, 6))} keyboardType="number-pad" inputMode="numeric" autoComplete="one-time-code" textContentType="oneTimeCode" maxLength={6} autoFocus />
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <Button title="Confirm" onPress={confirm} busy={busy} disabled={!isSixDigitCode(code)} />
      <Button title="Cancel" kind="ghost" onPress={() => router.back()} />
    </Screen>
  );
}
