import { useState } from 'react';

import { Button, Heading, Notice, Screen, Txt } from '@/components/ui';
import { whatsappUrl, WHATSAPP_DISPLAY } from '@/lib/constants';
import { useApp } from '@/state/app';
import * as Linking from 'expo-linking';

export default function ProblemScreen() {
  const app = useApp();
  const [busy, setBusy] = useState(false);
  return (
    <Screen>
      <Heading>Bee-Inspect could not open your account</Heading>
      <Notice tone="warning">{app.problem ?? 'Something went wrong.'}</Notice>
      <Button
        title="Try again"
        busy={busy}
        onPress={async () => {
          setBusy(true);
          try {
            await app.afterSignIn();
          } finally {
            setBusy(false);
          }
        }}
      />
      <Button title={`WhatsApp a sales executive (${WHATSAPP_DISPLAY})`} icon="whatsapp" kind="secondary" onPress={() => Linking.openURL(whatsappUrl('Hello Care Net, I need help opening my Bee-Inspect account.'))} />
      <Button title="Sign out" kind="ghost" onPress={app.signOut} />
      <Txt variant="small" muted>
        Anything you captured stays on this phone and syncs once your account opens.
      </Txt>
    </Screen>
  );
}
