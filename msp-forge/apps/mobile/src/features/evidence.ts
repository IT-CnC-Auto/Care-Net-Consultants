// Evidence capture helpers: keep the file on the phone, fingerprint it, take a
// GPS fix (only with location consent) and seal the evidence fields the same
// way as bi_evidence_seal. Works offline; nothing here uses the network.

import * as Crypto from 'expo-crypto';
import { Directory, File, Paths } from 'expo-file-system';
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';
import * as Location from 'expo-location';
import { Platform } from 'react-native';

import { jpegHasMetadata, stripMetadata } from '@/lib/evidence-store';
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

/**
 * Keeps the bytes in the phone's content addressed store:
 * documents/cas/<ab>/<cd>/<sha256>.<ext>. The same bytes are kept once; a
 * second capture of identical bytes reuses the file (dedupe).
 */
export async function keepBlob(uri: string, sha256: string, ext: string): Promise<{ uri: string; existed: boolean }> {
  if (Platform.OS === 'web') return { uri, existed: false };
  const dir = new Directory(Paths.document, 'cas', sha256.slice(0, 2), sha256.slice(2, 4));
  if (!dir.exists) dir.create({ intermediates: true, idempotent: true });
  const dest = new File(dir, `${sha256}.${ext}`);
  if (dest.exists) return { uri: dest.uri, existed: true };
  new File(uri).copySync(dest);
  return { uri: dest.uri, existed: false };
}

export interface DerivedCopy {
  variant: 'thumb' | 'web';
  uri: string;
  sha256: string;
  size_bytes: number;
  exif_stripped: boolean;
}

/** Widths of the derived copies: a list thumbnail and a copy fit for the web desk and shared links. */
export const DERIVED_WIDTH = { thumb: 320, web: 1600 } as const;

/**
 * The thumbnail and the web optimised copy of a photo, re encoded as JPEG
 * (which drops the camera metadata); each is checked and stripped again if a
 * metadata segment survived. The original is never touched. Null when the
 * phone cannot make them (they are made again later; the original is enough).
 */
export async function deriveCopies(uri: string): Promise<DerivedCopy[] | null> {
  try {
    const out: DerivedCopy[] = [];
    for (const variant of ['thumb', 'web'] as const) {
      const ref = await ImageManipulator.manipulate(uri).resize({ width: DERIVED_WIDTH[variant] }).renderAsync();
      const saved = await ref.saveAsync({ compress: variant === 'thumb' ? 0.6 : 0.8, format: SaveFormat.JPEG });
      let bytes = await readBytes(saved.uri);
      let stripped = true;
      if (jpegHasMetadata(bytes)) {
        bytes = stripMetadata(bytes, 'image/jpeg') as Uint8Array<ArrayBuffer>;
        stripped = !jpegHasMetadata(bytes);
        if (Platform.OS !== 'web') new File(saved.uri).write(bytes);
      }
      const sha = await sha256Hex(bytes);
      const kept = Platform.OS === 'web' ? { uri: saved.uri } : await keepBlob(saved.uri, sha, 'jpg');
      out.push({ variant, uri: kept.uri, sha256: sha, size_bytes: bytes.length, exif_stripped: stripped });
    }
    return out;
  } catch {
    return null;
  }
}

/** Writes the metadata sidecar beside the evidence (documents/sidecars/<id>.json). The web preview keeps its hash only. */
export async function writeSidecar(evidenceId: string, json: string): Promise<void> {
  if (Platform.OS === 'web') return;
  const dir = new Directory(Paths.document, 'sidecars');
  if (!dir.exists) dir.create({ intermediates: true, idempotent: true });
  const f = new File(dir, `${evidenceId}.json`);
  if (f.exists) return; // a sidecar is written once per version, never changed
  f.write(json);
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
