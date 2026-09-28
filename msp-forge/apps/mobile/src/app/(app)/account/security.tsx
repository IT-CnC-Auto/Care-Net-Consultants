import { router } from 'expo-router';

import { Button, Card, KeyValue, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useNow } from '@/features/use-now';
import { useApp } from '@/state/app';
import { isStepUpValid, stepUpMinutesLeft } from '@/lib/step-up';

export default function SecurityScreen() {
  const app = useApp();
  const now = useNow();
  const stepOk = isStepUpValid(app.lastStepUpAt, now);

  return (
    <Screen>
      <SectionTitle>Multi factor authentication</SectionTitle>
      <Card>
        <KeyValue label="Authenticator app" value={app.auth?.hasTotp ? 'Set up' : 'Not set up'} />
        <KeyValue label="This session" value={app.auth?.aal === 'aal2' ? 'Confirmed with MFA' : 'Password or link only'} />
        <Txt variant="small" muted>
          Inspectors always confirm sign in with the authenticator app. It is asked for again before sign off, Issue, Bee-Matched engagement and top ups over R499,00.
        </Txt>
      </Card>

      <SectionTitle>Step up</SectionTitle>
      <Card>
        {stepOk ? <Pill label={`Confirmed, valid ${stepUpMinutesLeft(app.lastStepUpAt, now)} more minutes`} tone="success" /> : <Pill label="Not confirmed in the last 10 minutes" tone="neutral" />}
        <Button title="Confirm now" kind="secondary" compact onPress={() => router.push({ pathname: '/step-up', params: { purpose: 'signoff' } })} />
      </Card>

      <SectionTitle>Fingerprint or face unlock</SectionTitle>
      <Card>
        {app.biometricAvailable ? (
          <>
            <Pill label={app.biometricEnabled ? 'On' : 'Off'} tone={app.biometricEnabled ? 'success' : 'neutral'} />
            <Txt variant="small" muted>
              Opens Bee-Inspect with your fingerprint or face after a full MFA sign in. Every 7 days, and after a reinstall, the authenticator code is asked for again.
            </Txt>
            <Button title={app.biometricEnabled ? 'Turn off' : 'Turn on'} kind="secondary" compact onPress={() => app.setBiometricEnabled(!app.biometricEnabled)} />
          </>
        ) : (
          <Txt variant="small" muted>
            This device has no fingerprint or face unlock set up (or this is the web preview), so Bee-Inspect asks for the authenticator code instead.
          </Txt>
        )}
      </Card>

      <SectionTitle>This phone</SectionTitle>
      {app.deviceRooted ? (
        <Notice tone="danger" title="Rooted or jailbroken">
          Issue is blocked on this phone. Capture and sync still work.
        </Notice>
      ) : (
        <Notice tone="success">No sign of rooting or jailbreaking found.</Notice>
      )}
      <Txt variant="tiny" muted>
        The check looks for common signs of a rooted or jailbroken phone. It is a heuristic: a determined person can hide those signs, and a few ordinary phones can look rooted. The server checks again before Issue.
      </Txt>
    </Screen>
  );
}
