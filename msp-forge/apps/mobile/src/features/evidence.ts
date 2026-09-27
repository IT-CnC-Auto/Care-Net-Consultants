// Evidence capture helpers: keep the file on the phone, fingerprint it, take a
// GPS fix (only with location consent) and seal the evidence fields the same
// way as bi_evidence_seal. Works offline; nothing here uses the network.

import * as Crypto from 'expo-crypto';
import { Directory, File, Paths } from 'expo-file-system';
import * as Location from 'expo-location';
import { Platform } from 'react-native';

import { sealInput, type SealFields } from '@/lib/seal';

const toHex = (buf: ArrayBuffer) => Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('');

export async function readBytes(uri: string): Promise<Uint8Array<ArrayBuffer>> {
  if (Platform.OS === 'web' || uri.startsWith('blob:') || uri.startsWith('data:') || uri.startsWith('http')) {
    const res = await fetch(uri);
    return new Uint8Array(await res.arrayBuffer());
  }
  return new File(uri).bytes();
}

export async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return toHex(await Crypto.digest(Crypto.CryptoDigestAlgorithm.SHA256, bytes));
}

export async function sha256Text(text: string): Promise<string> {
  return Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, text);
}

export async function sealEvidence(fields: SealFields): Promise<string> {
  return sha256Text(sealInput(fields));
}

/** Copies a captured file into the app's own documents folder so it survives until synced. */
export async function keepFile(uri: string, inspectionId: string, fileName: string): Promise<string> {
  if (Platform.OS === 'web') return uri;
  const dir = new Directory(Paths.document, 'evidence', inspectionId);
  if (!dir.exists) dir.create({ intermediates: true, idempotent: true });
  const dest = new File(dir, fileName);
  if (dest.exists) dest.delete();
  new File(uri).copySync(dest);
  return dest.uri;
}

export interface Fix {
  lat: number;
  lng: number;
  accuracy: number | null;
}

/**
 * A GPS fix for sealing evidence, only when the person gave location consent.
 * Falls back to the last known position; null when there is no fix in time.
 */
export async function currentFix(consentGiven: boolean, timeoutMs = 8000): Promise<Fix | null> {
  if (!consentGiven) return null;
  try {
    let perm = await Location.getForegroundPermissionsAsync();
    if (!perm.granted && perm.canAskAgain) perm = await Location.requestForegroundPermissionsAsync();
    if (!perm.granted) return null;
    const timeout = new Promise<null>((resolve) => setTimeout(() => resolve(null), timeoutMs));
    const pos = await Promise.race([Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced }), timeout]);
    const p = pos ?? (await Location.getLastKnownPositionAsync());
    if (!p) return null;
    return { lat: Number(p.coords.latitude.toFixed(6)), lng: Number(p.coords.longitude.toFixed(6)), accuracy: p.coords.accuracy ?? null };
  } catch {
    return null;
  }
}

export function mimeFromName(name: string, fallback: string): string {
  const ext = name.split('.').pop()?.toLowerCase();
  const map: Record<string, string> = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', heic: 'image/heic', webp: 'image/webp', m4a: 'audio/mp4', mp4: 'audio/mp4', aac: 'audio/aac', wav: 'audio/wav', webm: 'audio/webm', mp3: 'audio/mpeg' };
  return (ext && map[ext]) || fallback;
}
