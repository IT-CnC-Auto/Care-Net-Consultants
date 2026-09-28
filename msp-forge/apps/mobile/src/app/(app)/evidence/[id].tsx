// One piece of evidence: the original, its sealed metadata sidecar, where it
// lives (canonical path and content address), every version, tags, retention
// and legal hold, the upload and integrity state, and a secure share link
// (a placeholder until the evidence service exists).

import { Image } from 'expo-image';
import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { photoSource } from '@/components/evidence';
import { Breadcrumb } from '@/components/place-ui';
import { Button, Card, Chip, ChipRow, Field, Icon, KeyValue, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { correctPhoto } from '@/features/capture';
import { haptic } from '@/features/haptics';
import { useMe } from '@/features/inspection';
import { formatDateTime } from '@/lib/dates';
import { blobId, casKey, formatBytes, history, latestVersions, normaliseTags } from '@/lib/evidence-store';
import { kernel } from '@/lib/kernel';
import { breadcrumb } from '@/lib/places';
import { voiceLabel } from '@/lib/report';
import { shortHash } from '@/lib/seal';
import { progress } from '@/lib/upload-plan';
import type { Photo, VoiceNote } from '@/lib/types';
import { brand, radius, space } from '@/theme/tokens';

const RETENTION_TEXT: Record<string, string> = {};
for (const t of kernel().templates) RETENTION_TEXT[t.retention.class] = t.retention.text;

export default function EvidenceDetailScreen() {
  const { id, kind } = useLocalSearchParams<{ id: string; kind?: string }>();
  const { store, profile } = useMe();
  const [full, setFull] = useState(false);
  const [newTag, setNewTag] = useState('');
  const [caption, setCaption] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const isVoice = kind === 'voice' || (!store.get('photo', id) && !!store.get('voice_note', id));
  const rec: Photo | VoiceNote | undefined = isVoice ? store.get('voice_note', id) : store.get('photo', id);
  if (!rec) return <Screen><Notice tone="warning">This evidence is not on this phone.</Notice></Screen>;
  const list = isVoice ? store.list('voice_note') : store.list('photo');
  const versions = history(list as (Photo | VoiceNote)[], rec.id);
  const latest = latestVersions(versions)[0] ?? rec;
  const shown = rec;
  const isLatest = shown.id === latest.id;
  const inspection = store.get('inspection', shown.inspection_id);
  const company = inspection ? store.get('company', inspection.client_account_id) : undefined;
  const places = store.list('place');
  const sha = 'sha256' in shown ? shown.sha256 : shown.audio_sha256;
  const blob = store.get('blob', blobId(inspection?.client_account_id ?? '', sha));
  const item = shown.template_item_id ? store.get('template_item', shown.template_item_id) : undefined;
  const photo = !isVoice ? (shown as Photo) : undefined;
  const title = photo ? (photo.caption ?? 'Photo') : `Voice note ${voiceLabel(shown as VoiceNote)}`;

  const saveVersion = async (changes: Partial<Pick<Photo, 'caption' | 'tags'>>) => {
    if (!photo) return;
    const next = await correctPhoto(store, latest as Photo, changes);
    haptic.success();
    setCaption(null);
    setNewTag('');
    router.setParams({ id: next.id });
  };

  return (
    <Screen>
      <Stack.Screen options={{ title: photo ? 'Photo' : 'Voice note' }} />
      <Breadcrumb crumbs={[{ label: company?.trading_name || company?.legal_name || 'Company' }, ...breadcrumb(places, shown.place_id).map((label) => ({ label }))]} />
      {photo ? (
        <Pressable onPress={() => setFull(!full)} accessibilityRole="button" accessibilityLabel={full ? 'Show smaller' : 'Open the original full size'} style={[styles.photoWrap, full && { aspectRatio: undefined, height: 520 }]}>
          <Image source={photoSource(photo._local_uri)} style={styles.photo} contentFit={full ? 'contain' : 'cover'} accessibilityIgnoresInvertColors />
        </Pressable>
      ) : (
        <Card style={{ flexDirection: 'row', alignItems: 'center', gap: space.md }}>
          <Icon name="microphone" size={32} color={brand.deepRed} />
          <Txt variant="bodyStrong">{title}</Txt>
        </Card>
      )}
      <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
        <Pill label={`Version ${shown.evidence_version} of ${versions.length}`} tone={isLatest ? 'info' : 'warning'} />
        <Pill label={shown._upload?.verified ? 'Verified on server' : 'Kept on this phone'} tone={shown._upload?.verified ? 'success' : 'neutral'} />
        {shown.legal_hold ? <Pill label="Legal hold" tone="danger" /> : null}
      </View>
      {!isLatest ? <Notice tone="warning">An earlier version. It stays exactly as it was; the newest version is used in reports.</Notice> : null}
      {photo ? (
        <Txt variant="bodyStrong">{photo.caption ?? 'No caption'}</Txt>
      ) : null}

      <SectionTitle>Sealed metadata</SectionTitle>
      <Card>
        <KeyValue label="Captured" value={formatDateTime(shown.captured_at)} />
        <KeyValue label="GPS" value={shown.gps_lat !== null && shown.gps_lng !== null ? `${shown.gps_lat.toFixed(5)}, ${shown.gps_lng.toFixed(5)}` : 'No GPS fix'} />
        <KeyValue label="Inspector" value={shown.inspector_user_id === profile?.appUserId ? profile.displayName : shown.inspector_user_id} />
        <KeyValue label="Device" value={shown.device_id ?? 'Not recorded'} />
        <KeyValue label="Inspection" value={inspection?.title ?? ''} />
        {item ? <KeyValue label="Checklist item" value={item.prompt} /> : null}
        <KeyValue label="Type and size" value={`${shown.mime_type}, ${formatBytes(shown.size_bytes)}`} />
        <KeyValue label="Fingerprint (SHA 256)" value={sha} />
        <KeyValue label="Seal" value={shown._seal_local === 'demonstration' ? 'Demonstration record' : shortHash(shown._seal_local)} />
        <KeyValue label="Metadata sidecar" value={shown.sidecar_sha256 ? shortHash(shown.sidecar_sha256) : 'Written on capture'} />
      </Card>

      <SectionTitle>Where it is kept</SectionTitle>
      <Card>
        <Txt variant="small" muted>
          Path
        </Txt>
        <Txt variant="tiny" style={{ fontFamily: 'monospace' }} accessibilityRole="text">
          {shown.canonical_path ?? 'Given on sync'}
        </Txt>
        <KeyValue label="Content address" value={`${casKey(sha).slice(0, 22)}…`} />
        <KeyValue label="Stored once for" value={blob ? `${blob.refs} ${blob.refs === 1 ? 'use' : 'uses'} of the same bytes` : 'This use'} />
        <KeyValue label="Derived copies" value={photo ? (photo._thumb_uri || photo._web_uri ? 'Thumbnail and web copy, camera metadata removed' : 'Made when the phone can; the original is kept') : 'None for audio'} />
        <KeyValue label="Retention" value={shown.retention_class ? (RETENTION_TEXT[shown.retention_class] ?? 'Set by your competent person') : 'Set by your competent person'} />
        <KeyValue label="Legal hold" value={shown.legal_hold ? 'On: nothing is removed' : 'Off'} />
        <View style={{ gap: space.xs }}>
          <Txt variant="small" muted>
            {shown._upload?.verified
              ? `Uploaded and checked: the server's fingerprint matches (${shortHash(shown._upload.verified_sha256 ?? sha)}).`
              : shown._upload
                ? `Uploading, ${Math.round(progress(shown._upload) * 100)}%: sent in parts that resume after a lost signal, then checked against the fingerprint.`
                : blob?.verified_at
                  ? 'The server already holds these bytes; only this version\'s details are sent.'
                  : 'Waiting to upload: it goes in parts that resume after a lost signal, then is checked against the fingerprint.'}
          </Txt>
        </View>
      </Card>

      {photo ? (
        <>
          <SectionTitle>Tags</SectionTitle>
          <ChipRow>
            {latest.tags.map((t) => (
              <Chip key={t} label={`${t}  ✕`} onPress={() => (isLatest ? saveVersion({ tags: latest.tags.filter((x) => x !== t) }) : undefined)} accessibilityLabel={`Tag ${t}. Remove it as a new version`} />
            ))}
          </ChipRow>
          {isLatest ? (
            <View style={{ flexDirection: 'row', gap: space.sm, alignItems: 'flex-end' }}>
              <Field label="Add a tag" value={newTag} onChangeText={setNewTag} placeholder="For example: bay 14" style={{ flex: 1 }} />
              <Button title="Add" compact kind="secondary" disabled={!newTag.trim()} onPress={() => saveVersion({ tags: normaliseTags([...latest.tags, newTag]) })} />
            </View>
          ) : null}
          {isLatest ? (
            <>
              <Field label="Correct the caption" hint="Saved as a new version; this one stays as it is." value={caption ?? (latest as Photo).caption ?? ''} onChangeText={setCaption} />
              <Button title="Save as a new version" icon="source-branch" kind="secondary" disabled={caption === null || caption.trim() === ((latest as Photo).caption ?? '')} onPress={() => saveVersion({ caption: (caption ?? '').trim() || null })} />
            </>
          ) : null}
        </>
      ) : null}

      <SectionTitle>Versions</SectionTitle>
      <Card style={{ paddingVertical: 0 }}>
        {versions.map((v) => (
          <Pressable key={v.id} onPress={() => router.setParams({ id: v.id })} accessibilityRole="button" accessibilityLabel={`Version ${v.evidence_version}`} style={styles.versionRow}>
            <Txt variant="smallStrong">{`v${v.evidence_version}`}</Txt>
            <Txt variant="small" style={{ flex: 1 }} numberOfLines={1}>
              {'caption' in v ? (v.caption ?? 'Photo') : 'Voice note'} · {v.tags.join(', ')}
            </Txt>
            {v.id === shown.id ? <Pill label="Shown" tone="info" /> : null}
          </Pressable>
        ))}
      </Card>

      <Button
        title="Share a secure link"
        icon="link-variant"
        kind="secondary"
        onPress={() => setNotice('Secure links with an expiry come with the evidence service, which is not connected yet. Nothing was shared. A shared copy is always the web copy, with the camera metadata removed.')}
      />
      {notice ? <Notice tone="info">{notice}</Notice> : null}
    </Screen>
  );
}

const styles = StyleSheet.create({
  photoWrap: { width: '100%', aspectRatio: 4 / 3, borderRadius: radius.lg, overflow: 'hidden', backgroundColor: '#000' },
  photo: { width: '100%', height: '100%' },
  versionRow: { flexDirection: 'row', alignItems: 'center', gap: space.md, minHeight: 48 },
});
