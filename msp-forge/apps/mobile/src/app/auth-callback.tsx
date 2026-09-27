// The email sign in link opens beeinspect://auth-callback?code=… (PKCE) or with
// a token_hash; this screen completes the sign in.

import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator } from 'react-native';

import { Button, Notice, Screen, Txt } from '@/components/ui';
import { useApp } from '@/state/app';

export default function AuthCallbackScreen() {
  const app = useApp();
  const params = useLocalSearchParams<{ code?: string; token_hash?: string; type?: string }>();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        if (!app.liveAvailable) throw new Error('Live sign in is not set up on this build.');
        const backend = await app.chooseMode('live');
        await backend.completeRedirect({ code: params.code, token_hash: params.token_hash, type: params.type });
        await app.afterSignIn();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'The sign in link did not work.');
      }
    })();
    // Runs once for the link that opened the app.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Screen>
      {error ? (
        <>
          <Notice tone="danger">{error}</Notice>
          <Button title="Back to sign in" onPress={() => router.replace('/sign-in')} />
        </>
      ) : (
        <>
          <ActivityIndicator />
          <Txt muted>Signing you in…</Txt>
        </>
      )}
    </Screen>
  );
}
