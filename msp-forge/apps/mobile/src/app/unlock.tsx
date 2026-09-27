import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AuthHero } from '@/components/auth-hero';
import { Button, Notice, Screen, Txt } from '@/components/ui';
import { useApp } from '@/state/app';

export default function UnlockScreen() {
  const app = useApp();
  const [error, setError] = useState<string | null>(null);

  const unlock = async () => {
    setError(null);
    const ok = await app.unlockWithBiometrics();
    if (!ok) setError('Not unlocked. Try again, or use your authenticator code.');
  };

  useEffect(() => {
    // Prompt once when the screen opens.
    app.unlockWithBiometrics().then((ok) => {
      if (!ok) setError('Not unlocked. Try again, or use your authenticator code.');
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <View style={{ flex: 1 }}>
      <AuthHero line="Unlock to carry on where you left off. Your capture stays on this phone until it syncs." />
      <Screen>
        {error ? <Notice tone="warning">{error}</Notice> : null}
        <Button title="Unlock with fingerprint or face" icon="fingerprint" onPress={unlock} />
        <Button title="Use my authenticator code" kind="secondary" onPress={app.switchToCode} />
        <Txt variant="small" muted>
          Every 7 days, and after a reinstall, Bee-Inspect asks for your authenticator code again.
        </Txt>
      </Screen>
    </View>
  );
}
