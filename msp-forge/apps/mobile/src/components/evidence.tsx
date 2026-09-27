// Photo and voice note cards. Each shows its sealed metadata (time, GPS,
// inspector, fingerprint) so the person can see what is sealed. Audio is the
// source of truth; the transcript is an editable, versioned aid.

import { useAudioPlayer, useAudioPlayerStatus } from 'expo-audio';
import { Image } from 'expo-image';
import { useState } from 'react';
import { Pressable, StyleSheet, Text, View, type GestureResponderEvent } from 'react-native';

import { DEMO_PHOTOS } from '@/backend/demo-seed';
import { useQueueSummary } from '@/data/hooks';
import { formatDateTime, formatDuration } from '@/lib/dates';
import { latestTranscripts, voiceLabel } from '@/lib/report';
import { shortHash } from '@/lib/seal';
import type { Annotation, Photo, Transcript, VoiceNote } from '@/lib/types';
import { brand, fonts, radius, space } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

import { Button, Card, Field, Icon, Pill, Txt } from './ui';

export function photoSource(uri: string) {
  return uri in DEMO_PHOTOS ? DEMO_PHOTOS[uri as keyof typeof DEMO_PHOTOS] : { uri };
}

function gpsText(lat: number | null, lng: number | null, acc?: number | null) {
  if (lat === null || lng === null) return 'No GPS fix';
  return `${lat.toFixed(5)}, ${lng.toFixed(5)}${acc ? ` (about ${Math.round(acc)} m)` : ''}`;
}

export function SyncMark({ recordId }: { recordId: string }) {
  const { queue } = useQueueSummary();
  const q = queue.find((i) => i.recordId === recordId);
  if (!q) return <Pill label="Synced" tone="success" />;
  if (q.status === 'waiting_server') return <Pill label="Kept on phone" tone="warning" />;
  if (q.status === 'failed' || q.status === 'conflict') return <Pill label="Check sync" tone="danger" />;
  return <Pill label="Waiting to sync" tone="neutral" />;
}

export function PhotoCard({ photo, inspectorName, onChange }: { photo: Photo; inspectorName: string; onChange?: (changes: Partial<Photo>) => void }) {
  const p = usePalette();
  const [annotating, setAnnotating] = useState(false);
  const [box, setBox] = useState({ w: 1, h: 1 });
  const [label, setLabel] = useState('');
  const annotations = photo.annotations ?? [];

  const addMarker = (e: GestureResponderEvent) => {
    if (!annotating || !onChange) return;
    const { locationX, locationY } = e.nativeEvent;
    const next: Annotation[] = [...annotations, { x: Math.min(1, Math.max(0, locationX / box.w)), y: Math.min(1, Math.max(0, locationY / box.h)), label: label.trim() || `Point ${annotations.length + 1}` }];
    onChange({ annotations: next });
    setLabel('');
  };

  return (
    <Card>
      <Pressable
        onPress={addMarker}
        disabled={!annotating}
        accessibilityLabel={annotating ? 'Tap the photo to add a marker' : photo.caption ?? 'Photo'}
        onLayout={(e) => setBox({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height })}
        style={styles.photoWrap}>
        <Image source={photoSource(photo._local_uri)} style={styles.photo} contentFit="cover" accessibilityIgnoresInvertColors />
        {annotations.map((a, i) => (
          <View key={i} style={[styles.marker, { left: a.x * box.w - 14, top: a.y * box.h - 14 }]} accessibilityLabel={`Marker ${i + 1}: ${a.label}`}>
            <Text style={styles.markerText}>{i + 1}</Text>
          </View>
        ))}
      </Pressable>
      {photo.caption ? <Txt variant="smallStrong">{photo.caption}</Txt> : null}
      {annotations.length ? (
        <View style={{ gap: 2 }}>
          {annotations.map((a, i) => (
            <Txt key={i} variant="tiny" muted>
              {i + 1}. {a.label}
            </Txt>
          ))}
        </View>
      ) : null}
      <View style={[styles.meta, { borderColor: p.border }]}>
        <Txt variant="label" muted>
          Sealed evidence
        </Txt>
        <Txt variant="tiny">Taken {formatDateTime(photo.captured_at)}</Txt>
        <Txt variant="tiny">GPS {gpsText(photo.gps_lat, photo.gps_lng, photo.gps_accuracy_m)}</Txt>
        <Txt variant="tiny">Inspector {inspectorName}</Txt>
        <Txt variant="tiny">Fingerprint {shortHash(photo.sha256)} · Seal {photo._seal_local === 'demonstration' ? 'demonstration' : shortHash(photo._seal_local)}</Txt>
        <SyncMark recordId={photo.id} />
      </View>
      {onChange ? (
        annotating ? (
          <View style={{ gap: space.sm }}>
            <Field label="Marker label" hint="Type a label, then tap the photo where it belongs." value={label} onChangeText={setLabel} placeholder="For example: missing toe board" />
            <View style={styles.rowButtons}>
              <Button title="Done" kind="secondary" compact onPress={() => setAnnotating(false)} />
              {annotations.length ? <Button title="Remove last marker" kind="ghost" compact onPress={() => onChange({ annotations: annotations.slice(0, -1) })} /> : null}
            </View>
          </View>
        ) : (
          <Button title="Annotate" icon="map-marker-plus-outline" kind="secondary" compact onPress={() => setAnnotating(true)} />
        )
      ) : null}
    </Card>
  );
}

export function PhotoThumb({ photo, size = 72 }: { photo: Photo; size?: number }) {
  return <Image source={photoSource(photo._local_uri)} style={{ width: size, height: size, borderRadius: radius.sm }} contentFit="cover" accessibilityLabel={photo.caption ?? 'Photo'} />;
}

function Player({ uri }: { uri: string }) {
  const player = useAudioPlayer(uri);
  const status = useAudioPlayerStatus(player);
  const playing = status.playing;
  return (
    <Button
      title={playing ? 'Pause' : 'Play'}
      icon={playing ? 'pause' : 'play'}
      kind="secondary"
      compact
      onPress={() => {
        if (playing) player.pause();
        else {
          if (status.didJustFinish || (status.duration > 0 && status.currentTime >= status.duration)) player.seekTo(0);
          player.play();
        }
      }}
    />
  );
}

export function VoiceNoteCard({ note, transcripts, onCorrect }: { note: VoiceNote; transcripts: Transcript[]; onCorrect: (body: string) => void }) {
  const p = usePalette();
  const latest = latestTranscripts(transcripts).get(note.id);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(latest?.body ?? '');
  const hasAudio = !note._local_uri.startsWith('demo:');
  return (
    <Card>
      <View style={styles.vnHead}>
        <Icon name="microphone" color={brand.deepRed} />
        <Txt variant="bodyStrong" style={{ flex: 1 }}>
          {voiceLabel(note)} · {formatDuration(note.duration_seconds)}
        </Txt>
        {hasAudio ? <Player uri={note._local_uri} /> : <Pill label="Demonstration, no audio" tone="neutral" />}
      </View>
      <Txt variant="tiny" muted>
        Recorded {formatDateTime(note.captured_at)} · GPS {gpsText(note.gps_lat, note.gps_lng)} · Fingerprint {shortHash(note.audio_sha256)}
      </Txt>
      <SyncMark recordId={note.id} />
      <View style={[styles.meta, { borderColor: p.border }]}>
        <Txt variant="label" muted>
          Transcript {latest ? `version ${latest.version}${latest.source === 'correction' ? ', corrected' : ''}` : ''}
        </Txt>
        {editing ? (
          <>
            <Field label="Edit transcript" hint="Each save is a new version. The audio stays the source of truth." value={draft} onChangeText={setDraft} multiline />
            <View style={styles.rowButtons}>
              <Button
                title="Save correction"
                compact
                disabled={!draft.trim() || draft.trim() === latest?.body}
                onPress={() => {
                  onCorrect(draft.trim());
                  setEditing(false);
                }}
              />
              <Button title="Cancel" kind="ghost" compact onPress={() => setEditing(false)} />
            </View>
          </>
        ) : (
          <>
            <Txt variant="small">{latest ? latest.body : 'No transcript yet. Transcription runs after sync once it is connected; you can type one now.'}</Txt>
            <Button title={latest ? 'Edit transcript' : 'Type a transcript'} icon="pencil-outline" kind="ghost" compact onPress={() => { setDraft(latest?.body ?? ''); setEditing(true); }} />
          </>
        )}
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  photoWrap: { width: '100%', aspectRatio: 4 / 3, borderRadius: radius.md, overflow: 'hidden' },
  photo: { width: '100%', height: '100%' },
  marker: { position: 'absolute', width: 28, height: 28, borderRadius: 14, backgroundColor: brand.gold, borderWidth: 2, borderColor: brand.ink, alignItems: 'center', justifyContent: 'center' },
  markerText: { fontFamily: fonts.bodyBold, fontSize: 13, color: brand.ink },
  meta: { borderTopWidth: StyleSheet.hairlineWidth, paddingTop: space.sm, gap: 2 },
  rowButtons: { flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' },
  vnHead: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
});
