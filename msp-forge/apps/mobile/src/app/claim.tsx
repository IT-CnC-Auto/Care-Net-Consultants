import { useState } from 'react';

import { BarcodeScanner } from '@/components/barcode-scanner';
import { Button, Field, Heading, Notice, Screen, Txt } from '@/components/ui';
import { claimCodeFromScan, normaliseClaimCode } from '@/lib/claim-code';
import { CLAIM_TTL_MINUTES } from '@/lib/constants';
import { useApp } from '@/state/app';

export default function ClaimScreen() {
  const app = useApp();
  const [code, setCode] = useState('');
  const [scanning, setScanning] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const valid = normaliseClaimCode(code) !== null;

  const redeem = async (raw: string) => {
    setError(null);
    const n = normaliseClaimCode(raw);
    if (!n) {
      setError('A claim code is 6 to 12 letters or digits.');
      return;
    }
    setBusy(true);
    try {
      const backend = await app.chooseMode(app.liveAvailable ? 'live' : 'demo');
      await backend.redeemClaimCode(n);
      await app.afterSignIn();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That code did not work.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Screen>
      <Heading>Sign in with a claim code</Heading>
      <Txt muted>
        On the computer, open your Health and Safety File and choose Get the app. Scan the QR code, or type the code shown beside it. The phone signs in to the same account and File.
      </Txt>
      <Notice tone="info">{`A claim code lasts ${CLAIM_TTL_MINUTES} minutes and works once. You still confirm it is you with your authenticator app next.`}</Notice>
      {!app.liveAvailable ? <Notice tone="warning">Live sign in is not set up on this build, so any well formed code opens the demo.</Notice> : null}
      {scanning ? (
        <BarcodeScanner
          hint="Point at the QR code on the computer"
          onCode={(data) => {
            setScanning(false);
            const c = claimCodeFromScan(data);
            if (c) {
              setCode(c);
              void redeem(c);
            } else setError('That QR code is not a Bee-Inspect claim code.');
          }}
        />
      ) : (
        <Button title="Scan the QR code" icon="qrcode-scan" kind="secondary" onPress={() => setScanning(true)} />
      )}
      <Field label="Claim code" value={code} onChangeText={(t) => setCode(t.toUpperCase())} autoCapitalize="characters" autoCorrect={false} maxLength={16} placeholder="For example KQ7M2P9X" />
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <Button title="Sign in" onPress={() => redeem(code)} busy={busy} disabled={!valid} />
    </Screen>
  );
}
