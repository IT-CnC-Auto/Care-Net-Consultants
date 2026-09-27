import { router } from 'expo-router';
import { useState } from 'react';

import { BarcodeScanner } from '@/components/barcode-scanner';
import { Button, Field, Heading, Screen, Txt } from '@/components/ui';
import { emitScan } from '@/features/scan-bus';

export default function ScanScreen() {
  const [manual, setManual] = useState('');
  const finish = (data: string) => {
    emitScan(data);
    router.back();
  };
  return (
    <Screen>
      <Heading>Scan an equipment tag</Heading>
      <Txt muted>QR codes and the common barcodes work. Hold the phone steady, about 20 cm from the tag.</Txt>
      <BarcodeScanner hint="Point at the tag" onCode={finish} />
      <Field label="Or type the tag" value={manual} onChangeText={setManual} autoCapitalize="characters" />
      <Button title="Use this tag" disabled={manual.trim().length < 3} onPress={() => finish(manual.trim())} />
    </Screen>
  );
}
