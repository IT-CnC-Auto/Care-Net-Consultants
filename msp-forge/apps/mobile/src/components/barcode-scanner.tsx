// QR code and barcode scanning with expo-camera (SDK 57 CameraView). Used for
// equipment tags and for the desktop claim QR. On the web preview, or without
// camera permission, the person types the code instead.

import { CameraView, useCameraPermissions, type BarcodeType } from 'expo-camera';
import { useRef } from 'react';
import { Platform, StyleSheet, View } from 'react-native';

import { brand, radius, space } from '@/theme/tokens';

import { Button, Notice, Txt } from './ui';

const TYPES: BarcodeType[] = ['qr', 'code128', 'code39', 'ean13', 'ean8', 'datamatrix', 'upc_a', 'upc_e', 'itf14', 'pdf417'];

export function BarcodeScanner({ onCode, hint }: { onCode: (data: string) => void; hint: string }) {
  const [permission, requestPermission] = useCameraPermissions();
  const done = useRef(false);

  if (Platform.OS === 'web') {
    return <Notice tone="info">Scanning uses the phone camera. On the web preview, type the code below instead.</Notice>;
  }
  if (!permission) return null;
  if (!permission.granted) {
    return (
      <View style={{ gap: space.sm }}>
        <Txt variant="small" muted>
          Bee-Inspect needs the camera to scan codes.
        </Txt>
        <Button title="Allow the camera" icon="camera-outline" onPress={requestPermission} />
      </View>
    );
  }
  return (
    <View style={styles.wrap}>
      <CameraView
        style={StyleSheet.absoluteFill}
        facing="back"
        barcodeScannerSettings={{ barcodeTypes: TYPES }}
        onBarcodeScanned={(r) => {
          if (done.current || !r.data) return;
          done.current = true;
          onCode(r.data);
        }}
      />
      <View style={styles.frame} pointerEvents="none" />
      <View style={styles.hint} pointerEvents="none">
        <Txt variant="smallStrong" color={brand.white}>
          {hint}
        </Txt>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { height: 320, borderRadius: radius.lg, overflow: 'hidden', backgroundColor: brand.ink },
  frame: { position: 'absolute', left: '15%', right: '15%', top: '20%', bottom: '20%', borderWidth: 3, borderColor: brand.gold, borderRadius: radius.md },
  hint: { position: 'absolute', left: space.md, right: space.md, bottom: space.md, alignItems: 'center' },
});
