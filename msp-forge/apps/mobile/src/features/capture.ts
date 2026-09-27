// Photo and voice note capture: take or choose, keep on the phone, fingerprint,
// GPS (with consent), seal, store and queue. Offline throughout.

import * as ImagePicker from 'expo-image-picker';
import { Platform } from 'react-native';

import type { DataStore } from '@/data/data-store';
import { evidencePath } from '@/lib/seal';
import type { Inspection, Photo, VoiceNote } from '@/lib/types';

import { currentFix, keepFile, mimeFromName, readBytes, sealEvidence, sha256Hex } from './evidence';

const PHOTO_MAX_BYTES = 26214400;
const AUDIO_MAX_BYTES = 52428800;

export function consentGiven(store: DataStore, kind: 'location' | 'voice_recording' | 'identifiable_people'): boolean {
  return store.list('consent').some((c) => c.consent_kind === kind && c.granted && !c.withdrawn_at);
}

export interface CaptureTarget {
  inspection: Inspection;
  areaId: string | null;
  findingId: string | null;
  equipmentId?: string | null;
  inspectorId: string;
}

export async function capturePhoto(
  store: DataStore,
  t: CaptureTarget,
  opts: { source: 'camera' | 'library'; kind: Photo['kind']; caption?: string },
): Promise<{ photo?: Photo; error?: string }> {
  try {
    if (opts.source === 'camera' && Platform.OS !== 'web') {
      const perm = await ImagePicker.requestCameraPermissionsAsync();
      if (!perm.granted) return { error: 'Allow the camera for Bee-Inspect in your phone settings to take photos.' };
    }
    const pickerOpts: ImagePicker.ImagePickerOptions = { mediaTypes: ['images'], quality: 0.7, exif: false };
    const res = opts.source === 'camera' ? await ImagePicker.launchCameraAsync(pickerOpts) : await ImagePicker.launchImageLibraryAsync(pickerOpts);
    if (res.canceled || !res.assets?.length) return {};
    const asset = res.assets[0];
    const id = store.id();
    const mime = asset.mimeType && /^image\/(jpeg|png|heic|webp)$/.test(asset.mimeType) ? asset.mimeType : mimeFromName(asset.fileName ?? 'photo.jpg', 'image/jpeg');
    const ext = mime === 'image/png' ? 'png' : mime === 'image/heic' ? 'heic' : mime === 'image/webp' ? 'webp' : 'jpg';
    const fileName = `${id}.${ext}`;
    const localUri = await keepFile(asset.uri, t.inspection.id, fileName);
    const bytes = await readBytes(localUri);
    if (bytes.length > PHOTO_MAX_BYTES) return { error: 'That photo is larger than 25 MB. Take it again at a lower size.' };
    const sha = await sha256Hex(bytes);
    const fix = await currentFix(consentGiven(store, 'location'));
    const capturedAt = new Date().toISOString();
    const path = evidencePath(t.inspection.client_account_id, t.inspection.id, fileName);
    const seal = await sealEvidence({ path, sha256: sha, capturedAt, lat: fix?.lat ?? null, lng: fix?.lng ?? null, inspectorId: t.inspectorId });
    const photo = await store.create('photo', {
      id,
      inspection_id: t.inspection.id,
      area_id: t.areaId,
      finding_id: t.findingId,
      equipment_id: t.equipmentId ?? null,
      kind: opts.kind,
      storage_path: path,
      sha256: sha,
      size_bytes: bytes.length,
      mime_type: mime,
      captured_at: capturedAt,
      gps_lat: fix?.lat ?? null,
      gps_lng: fix?.lng ?? null,
      gps_accuracy_m: fix?.accuracy ?? null,
      inspector_user_id: t.inspectorId,
      caption: opts.caption ?? (opts.source === 'library' ? 'Chosen from the gallery' : null),
      annotations: [],
      identifiable_people: false,
      people_consent_ref: null,
      _seal_local: seal,
      _local_uri: localUri,
    });
    return { photo };
  } catch (e) {
    return { error: e instanceof Error ? `The photo could not be saved: ${e.message}` : 'The photo could not be saved.' };
  }
}

export async function saveVoiceNote(store: DataStore, t: CaptureTarget, uri: string, seconds: number): Promise<{ note?: VoiceNote; error?: string }> {
  try {
    const id = store.id();
    const web = Platform.OS === 'web';
    const mime = web ? 'audio/webm' : 'audio/mp4';
    const fileName = `${id}.${web ? 'webm' : 'm4a'}`;
    const localUri = await keepFile(uri, t.inspection.id, fileName);
    const bytes = await readBytes(localUri);
    if (bytes.length > AUDIO_MAX_BYTES) return { error: 'That recording is too long. Keep voice notes under 50 MB.' };
    const sha = await sha256Hex(bytes);
    const fix = await currentFix(consentGiven(store, 'location'));
    const capturedAt = new Date().toISOString();
    const path = evidencePath(t.inspection.client_account_id, t.inspection.id, fileName);
    const seal = await sealEvidence({ path, sha256: sha, capturedAt, lat: fix?.lat ?? null, lng: fix?.lng ?? null, inspectorId: t.inspectorId });
    const note = await store.create('voice_note', {
      id,
      inspection_id: t.inspection.id,
      area_id: t.areaId,
      finding_id: t.findingId,
      vn_number: null,
      audio_path: path,
      audio_sha256: sha,
      size_bytes: bytes.length,
      mime_type: mime,
      duration_seconds: Math.min(3600, Math.max(1, seconds)),
      captured_at: capturedAt,
      gps_lat: fix?.lat ?? null,
      gps_lng: fix?.lng ?? null,
      inspector_user_id: t.inspectorId,
      _seal_local: seal,
      _local_uri: localUri,
    });
    return { note };
  } catch (e) {
    return { error: e instanceof Error ? `The voice note could not be saved: ${e.message}` : 'The voice note could not be saved.' };
  }
}

export async function addTranscriptCorrection(store: DataStore, voiceNoteId: string, body: string, by: string): Promise<void> {
  const versions = store.where('transcript', (x) => x.voice_note_id === voiceNoteId).map((x) => x.version);
  await store.create('transcript', {
    id: store.id(),
    voice_note_id: voiceNoteId,
    version: Math.max(0, ...versions) + 1,
    source: 'correction',
    body,
    created_by: by,
  });
}
