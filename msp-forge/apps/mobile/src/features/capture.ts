// Photo and voice note capture: take or choose, fingerprint (SHA 256), keep the
// bytes content addressed (once per company), derive the thumbnail and the web
// copy, take a GPS fix (with consent), seal, write the metadata sidecar and
// queue. Corrections are new versions. Offline throughout.
// Design: docs/bee-inspect/p4/evidence-storage.md.

import * as ImagePicker from 'expo-image-picker';
import { Platform } from 'react-native';

import type { DataStore } from '@/data/data-store';
import { addBlobRef, blobId, buildSidecar, canonicalPath, casKey, latestVersions, nextVersion, normaliseTags, stableJson, storageMeter, usedBytes } from '@/lib/evidence-store';
import { kernel, placeType } from '@/lib/kernel';
import { pathOf, slug } from '@/lib/places';
import type { Area, BlobRecord, Inspection, Photo, VoiceNote } from '@/lib/types';

import { currentFix, deriveCopies, keepBlob, mimeFromName, readBytes, sealEvidence, sha256Hex, sha256Text, writeSidecar } from './evidence';

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

/** The storage meter of a company (B8: 10 GB per company line). */
export function companyStorage(store: DataStore, companyId: string) {
  return storageMeter(usedBytes(store.list('blob'), companyId));
}

/** Where a piece of evidence sits: the place path, the item it belongs to, retention and automatic tags. */
export function evidenceContext(store: DataStore, t: CaptureTarget): { placeId: string | null; placeSlugs: string[]; placePath: string[]; itemKey: string; templateItemId: string | null; retention: string | null; autoTags: string[] } {
  const b = kernel();
  const area: Area | undefined = t.areaId ? store.get('area', t.areaId) : undefined;
  const placeId = area?.place_id ?? t.inspection.place_id ?? t.inspection.site_id ?? null;
  const path = pathOf(store.list('place'), placeId);
  const finding = t.findingId ? store.get('finding', t.findingId) : undefined;
  const templateItemId = finding?.template_item_id ?? null;
  const template = store.get('template', t.inspection.template_id);
  const kt = b.templates.find((x) => x.id === t.inspection.template_id);
  const leaf = path[path.length - 1];
  const autoTags = normaliseTags([
    ...(leaf ? [placeType(b, leaf.place_type)?.label ?? ''] : []),
    ...((kt?.section_f_element_code ?? template?.section_f_element_code) ? [(kt?.section_f_element_code ?? template?.section_f_element_code) as string] : []),
    ...(finding ? [finding.result === 'na' ? 'N/A' : finding.result] : []),
  ]);
  return {
    placeId,
    placeSlugs: path.map((p) => slug(p.name)),
    placePath: path.map((p) => p.name),
    itemKey: templateItemId ?? (t.areaId ? `area-${t.areaId}` : 'general'),
    templateItemId,
    retention: kt?.retention.class ?? null,
    autoTags,
  };
}

async function deviceId(store: DataStore): Promise<string> {
  let id = await store.kvGet('device_id');
  if (!id) {
    id = `PHONE-${store.id().slice(0, 8).toUpperCase()}`;
    await store.kvSet('device_id', id);
  }
  return id;
}

/** Adds (or references again) a blob in the phone's content addressed store. */
export async function registerBlob(store: DataStore, p: { companyId: string; sha256: string; size: number; mime: string; uri: string; variant?: BlobRecord['variant']; derivedFrom?: string | null; exifStripped?: boolean }): Promise<{ blob: BlobRecord; deduped: boolean }> {
  const existing = store.get('blob', blobId(p.companyId, p.sha256));
  const r = addBlobRef(existing, { sha256: p.sha256, size_bytes: p.size, mime_type: p.mime, local_uri: p.uri, client_account_id: p.companyId, variant: p.variant, derived_from: p.derivedFrom, exif_stripped: p.exifStripped }, new Date().toISOString());
  await store.putServer('blob', r.blob);
  return r;
}

async function sidecarFor(
  store: DataStore,
  t: CaptureTarget,
  ctx: ReturnType<typeof evidenceContext>,
  e: { id: string; version: number; rootId: string; supersedes: string | null; kind: 'photo' | 'voice_note'; sha256: string; size: number; mime: string; capturedAt: string; lat: number | null; lng: number | null; accuracy: number | null; device: string; seal: string; caption: string | null; tags: string[]; canonical: string; legalHold: boolean },
): Promise<string> {
  const sc = buildSidecar({
    evidence_id: e.id,
    root_evidence_id: e.rootId,
    version: e.version,
    supersedes_id: e.supersedes,
    kind: e.kind,
    sha256: e.sha256,
    size_bytes: e.size,
    mime_type: e.mime,
    canonical_path: e.canonical,
    captured_at: e.capturedAt,
    gps: e.lat !== null && e.lng !== null ? { lat: e.lat, lng: e.lng, accuracy_m: e.accuracy } : null,
    inspector_id: t.inspectorId,
    device_id: e.device,
    tenant_id: t.inspection.tenant_id,
    company_id: t.inspection.client_account_id,
    place_id: ctx.placeId,
    place_path: ctx.placePath,
    inspection_id: t.inspection.id,
    area_id: t.areaId,
    finding_id: t.findingId,
    template_item_id: ctx.templateItemId,
    seal_sha256: e.seal,
    caption: e.caption,
    tags: e.tags,
    retention_class: ctx.retention,
    legal_hold: e.legalHold,
  });
  const json = stableJson(sc);
  await writeSidecar(e.id, json);
  return sha256Text(json);
}

export async function capturePhoto(
  store: DataStore,
  t: CaptureTarget,
  opts: { source: 'camera' | 'library'; kind: Photo['kind']; caption?: string },
): Promise<{ photo?: Photo; deduped?: boolean; error?: string }> {
  try {
    const meter = companyStorage(store, t.inspection.client_account_id);
    if (!meter.canCapture) return { error: meter.text };
    if (opts.source === 'camera' && Platform.OS !== 'web') {
      const perm = await ImagePicker.requestCameraPermissionsAsync();
      if (!perm.granted) return { error: 'Allow the camera for Bee-Inspect in your phone settings to take photos.' };
    }
    const pickerOpts: ImagePicker.ImagePickerOptions = { mediaTypes: ['images'], quality: 0.7, exif: false };
    const res = opts.source === 'camera' ? await ImagePicker.launchCameraAsync(pickerOpts) : await ImagePicker.launchImageLibraryAsync(pickerOpts);
    if (res.canceled || !res.assets?.length) return {};
    const asset = res.assets[0];
    const mime = asset.mimeType && /^image\/(jpeg|png|heic|webp)$/.test(asset.mimeType) ? asset.mimeType : mimeFromName(asset.fileName ?? 'photo.jpg', 'image/jpeg');
    const ext = mime === 'image/png' ? 'png' : mime === 'image/heic' ? 'heic' : mime === 'image/webp' ? 'webp' : 'jpg';
    const bytes = await readBytes(asset.uri);
    if (bytes.length > PHOTO_MAX_BYTES) return { error: 'That photo is larger than 25 MB. Take it again at a lower size.' };
    const sha = await sha256Hex(bytes);
    return await storePhoto(store, t, { sha, bytesLength: bytes.length, mime, ext, sourceUri: asset.uri, kind: opts.kind, caption: opts.caption ?? (opts.source === 'library' ? 'Chosen from the gallery' : null) });
  } catch (e) {
    return { error: e instanceof Error ? `The photo could not be saved: ${e.message}` : 'The photo could not be saved.' };
  }
}

/** Stores photo bytes already fingerprinted (the capture path above, and the tests of the pipeline). */
export async function storePhoto(
  store: DataStore,
  t: CaptureTarget,
  p: { sha: string; bytesLength: number; mime: string; ext: string; sourceUri: string; kind: Photo['kind']; caption: string | null },
): Promise<{ photo: Photo; deduped: boolean }> {
  const companyId = t.inspection.client_account_id;
  const kept = await keepBlob(p.sourceUri, p.sha, p.ext);
  const { deduped } = await registerBlob(store, { companyId, sha256: p.sha, size: p.bytesLength, mime: p.mime, uri: kept.uri });
  const derived = deduped ? null : await deriveCopies(kept.uri);
  for (const d of derived ?? []) await registerBlob(store, { companyId, sha256: d.sha256, size: d.size_bytes, mime: 'image/jpeg', uri: d.uri, variant: d.variant, derivedFrom: p.sha, exifStripped: d.exif_stripped });
  // Same bytes already held: reuse their derived copies too.
  const prior = deduped ? store.where('photo', (x) => x.sha256 === p.sha && store.get('inspection', x.inspection_id)?.client_account_id === companyId)[0] : undefined;
  const fix = await currentFix(consentGiven(store, 'location'));
  const capturedAt = new Date().toISOString();
  const id = store.id();
  const ctx = evidenceContext(store, t);
  const device = await deviceId(store);
  const storagePath = `${companyId}/${casKey(p.sha)}`;
  const seal = await sealEvidence({ path: storagePath, sha256: p.sha, capturedAt, lat: fix?.lat ?? null, lng: fix?.lng ?? null, inspectorId: t.inspectorId });
  const canonical = canonicalPath({ tenantId: t.inspection.tenant_id, companyId, placeSlugs: ctx.placeSlugs, inspectionId: t.inspection.id, itemKey: ctx.itemKey, evidenceId: id, version: 1 });
  const tags = normaliseTags([...ctx.autoTags, p.kind.replace(/_/g, ' ')]);
  const sidecarSha = await sidecarFor(store, t, ctx, { id, version: 1, rootId: id, supersedes: null, kind: 'photo', sha256: p.sha, size: p.bytesLength, mime: p.mime, capturedAt, lat: fix?.lat ?? null, lng: fix?.lng ?? null, accuracy: fix?.accuracy ?? null, device, seal, caption: p.caption, tags, canonical, legalHold: false });
  const thumb = derived?.find((d) => d.variant === 'thumb')?.uri ?? prior?._thumb_uri ?? null;
  const web = derived?.find((d) => d.variant === 'web')?.uri ?? prior?._web_uri ?? null;
  const photo = await store.create('photo', {
    id,
    inspection_id: t.inspection.id,
    area_id: t.areaId,
    finding_id: t.findingId,
    equipment_id: t.equipmentId ?? null,
    kind: p.kind,
    storage_path: storagePath,
    sha256: p.sha,
    size_bytes: p.bytesLength,
    mime_type: p.mime,
    captured_at: capturedAt,
    gps_lat: fix?.lat ?? null,
    gps_lng: fix?.lng ?? null,
    gps_accuracy_m: fix?.accuracy ?? null,
    inspector_user_id: t.inspectorId,
    caption: p.caption,
    annotations: [],
    identifiable_people: false,
    people_consent_ref: null,
    evidence_version: 1,
    root_evidence_id: null,
    supersedes_id: null,
    canonical_path: canonical,
    place_id: ctx.placeId,
    template_item_id: ctx.templateItemId,
    device_id: device,
    tags,
    retention_class: ctx.retention,
    legal_hold: false,
    sidecar_sha256: sidecarSha,
    _seal_local: seal,
    _local_uri: kept.uri,
    _thumb_uri: thumb,
    _web_uri: web,
    _upload: null,
  });
  return { photo, deduped };
}

export async function saveVoiceNote(store: DataStore, t: CaptureTarget, uri: string, seconds: number): Promise<{ note?: VoiceNote; error?: string }> {
  try {
    const companyId = t.inspection.client_account_id;
    const meter = companyStorage(store, companyId);
    if (!meter.canCapture) return { error: meter.text };
    const web = Platform.OS === 'web';
    const mime = web ? 'audio/webm' : 'audio/mp4';
    const bytes = await readBytes(uri);
    if (bytes.length > AUDIO_MAX_BYTES) return { error: 'That recording is too long. Keep voice notes under 50 MB.' };
    const sha = await sha256Hex(bytes);
    const kept = await keepBlob(uri, sha, web ? 'webm' : 'm4a');
    await registerBlob(store, { companyId, sha256: sha, size: bytes.length, mime, uri: kept.uri });
    const fix = await currentFix(consentGiven(store, 'location'));
    const capturedAt = new Date().toISOString();
    const id = store.id();
    const ctx = evidenceContext(store, t);
    const device = await deviceId(store);
    const path = `${companyId}/${casKey(sha)}`;
    const seal = await sealEvidence({ path, sha256: sha, capturedAt, lat: fix?.lat ?? null, lng: fix?.lng ?? null, inspectorId: t.inspectorId });
    const canonical = canonicalPath({ tenantId: t.inspection.tenant_id, companyId, placeSlugs: ctx.placeSlugs, inspectionId: t.inspection.id, itemKey: ctx.itemKey, evidenceId: id, version: 1 });
    const tags = normaliseTags([...ctx.autoTags, 'voice note']);
    const sidecarSha = await sidecarFor(store, t, ctx, { id, version: 1, rootId: id, supersedes: null, kind: 'voice_note', sha256: sha, size: bytes.length, mime, capturedAt, lat: fix?.lat ?? null, lng: fix?.lng ?? null, accuracy: fix?.accuracy ?? null, device, seal, caption: null, tags, canonical, legalHold: false });
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
      evidence_version: 1,
      root_evidence_id: null,
      supersedes_id: null,
      canonical_path: canonical,
      place_id: ctx.placeId,
      template_item_id: ctx.templateItemId,
      device_id: device,
      tags,
      retention_class: ctx.retention,
      legal_hold: false,
      sidecar_sha256: sidecarSha,
      _seal_local: seal,
      _local_uri: kept.uri,
      _upload: null,
    });
    return { note };
  } catch (e) {
    return { error: e instanceof Error ? `The voice note could not be saved: ${e.message}` : 'The voice note could not be saved.' };
  }
}

/**
 * A correction to a photo (caption, markers or tags): a NEW version that
 * supersedes the one shown, reusing the same bytes (no new blob). The earlier
 * version stays as it was.
 */
export async function correctPhoto(store: DataStore, photo: Photo, changes: Partial<Pick<Photo, 'caption' | 'annotations' | 'tags'>>): Promise<Photo> {
  const latest = latestVersions(store.where('photo', (p) => (p.root_evidence_id ?? p.id) === (photo.root_evidence_id ?? photo.id)))[0] ?? photo;
  const inspection = store.get('inspection', latest.inspection_id);
  const id = store.id();
  const next = nextVersion(latest, { ...changes, ...(changes.tags ? { tags: normaliseTags(changes.tags) } : {}) }, id);
  if (inspection) {
    const t: CaptureTarget = { inspection, areaId: latest.area_id, findingId: latest.finding_id, inspectorId: latest.inspector_user_id };
    const ctx = evidenceContext(store, t);
    next.canonical_path = canonicalPath({ tenantId: inspection.tenant_id, companyId: inspection.client_account_id, placeSlugs: ctx.placeSlugs, inspectionId: inspection.id, itemKey: ctx.itemKey, evidenceId: next.root_evidence_id ?? id, version: next.evidence_version });
    next.sidecar_sha256 = await sidecarFor(store, t, ctx, {
      id, version: next.evidence_version, rootId: next.root_evidence_id ?? id, supersedes: next.supersedes_id, kind: 'photo', sha256: next.sha256, size: next.size_bytes, mime: next.mime_type,
      capturedAt: next.captured_at, lat: next.gps_lat, lng: next.gps_lng, accuracy: next.gps_accuracy_m, device: next.device_id ?? '', seal: next._seal_local, caption: next.caption, tags: next.tags, canonical: next.canonical_path ?? '', legalHold: next.legal_hold,
    });
  }
  await registerBlob(store, { companyId: inspection?.client_account_id ?? '', sha256: next.sha256, size: next.size_bytes, mime: next.mime_type, uri: next._local_uri });
  return store.create('photo', { ...next, _upload: null });
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

