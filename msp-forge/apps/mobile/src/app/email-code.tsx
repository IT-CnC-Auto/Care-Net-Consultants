import { useLocalSearchParams } from 'expo-router';
import { useState } from 'react';

import { Button, Field, Heading, Notice, Screen, Txt } from '@/components/ui';
import { isSixDigitCode } from '@/lib/step-up';
import { useApp } from '@/state/app';

export default function EmailCodeScreen() {
  const app = useApp();
  const { email } = useLocalSearchParams<{ email: string }>();
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState<string | null>(null);

  const verify = async () => {
    setError(null);
    setBusy(true);
    try {
      await app.backend?.verifyEmailCode(email ?? '', code);
      await app.afterSignIn();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That code did not work.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Screen>
      <Heading>Check your email</Heading>
      <Txt muted>{`We sent a six digit code and a sign in link to ${email ?? 'your email address'}. Type the code here, or open the link on this phone.`}</Txt>
      <Field label="Six digit code" value={code} onChangeText={(t) => setCode(t.replace(/\D/g, '').slice(0, 6))} keyboardType="number-pad" inputMode="numeric" autoComplete="one-time-code" textContentType="oneTimeCode" maxLength={6} />
      {error ? <Notice tone="danger">{error}</Notice> : null}
      {sent ? <Notice tone="success">{sent}</Notice> : null}
      <Button title="Continue" onPress={verify} busy={busy} disabled={!isSixDigitCode(code)} />
      <Button
        title="Send a new code"
        kind="ghost"
        onPress={async () => {
          setError(null);
          try {
            await app.backend?.sendEmailCode(email ?? '');
            setSent('A new code is on its way.');
          } catch (e) {
            setError(e instanceof Error ? e.message : 'The email could not be sent.');
          }
        }}
      />
    </Screen>
  );
}
