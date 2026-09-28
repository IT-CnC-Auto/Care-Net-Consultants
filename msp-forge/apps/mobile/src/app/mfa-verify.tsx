import { useState } from 'react';

import { Button, Field, Heading, Notice, Screen, Txt } from '@/components/ui';
import { isSixDigitCode } from '@/lib/step-up';
import { useApp } from '@/state/app';

export default function MfaVerifyScreen() {
  const app = useApp();
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const verify = async () => {
    setError(null);
    setBusy(true);
    try {
      await app.backend?.verifyTotp(code);
      await app.completeMfa();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That code did not work.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Screen>
      <Heading>Confirm it is you</Heading>
      <Txt muted>Type the six digit code from your authenticator app. After this, you can unlock with your fingerprint or face for 7 days.</Txt>
      {app.mode === 'demo' ? <Notice tone="info" title="Demo">This is a demonstration. Any six digit code works.</Notice> : null}
      <Field label="Code from your authenticator app" value={code} onChangeText={(t) => setCode(t.replace(/\D/g, '').slice(0, 6))} keyboardType="number-pad" inputMode="numeric" autoComplete="one-time-code" textContentType="oneTimeCode" maxLength={6} />
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <Button title="Continue" onPress={verify} busy={busy} disabled={!isSixDigitCode(code)} />
      <Txt variant="small" muted>
        Lost your phone or authenticator? Ask a Care Net sales executive to reset it after checking who you are.
      </Txt>
      <Button title="Use a different account" kind="ghost" onPress={app.signOut} />
    </Screen>
  );
}
