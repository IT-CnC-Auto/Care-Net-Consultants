// One room or area: every checklist line with Pass, Fail, N/A or Observe, plus
// area photos and section voice notes.

import { router, Stack, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Pressable, View } from 'react-native';

import { PhotoCard, VoiceNoteCard } from '@/components/evidence';
import { RESULT_LABEL, ResultPicker } from '@/components/result-picker';
import { VoiceRecorder } from '@/components/voice-recorder';
import { Button, Card, Icon, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { addTranscriptCorrection, capturePhoto, consentGiven, correctPhoto, saveVoiceNote } from '@/features/capture';
import { currentFix } from '@/features/evidence';
import { useInspection, useMe } from '@/features/inspection';
import type { FindingResult } from '@/lib/types';
import { space } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

export default function AreaScreen() {
  const { id, areaId } = useLocalSearchParams<{ id: string; areaId: string }>();
  const x = useInspection(id);
  const { profile } = useMe();
  const p = usePalette();
  const [error, setError] = useState<string | null>(null);
  const area = x.areas.find((a) => a.id === areaId);
  if (!x.inspection || !area || !profile) return <Screen><Notice tone="warning">This area is not on this phone.</Notice></Screen>;
  const { inspection, items, findings, photos, voiceNotes, transcripts, store, violations } = x;
  const readOnly = inspection.status !== 'planned' && inspection.status !== 'in_progress';
  const areaFindings = findings.filter((f) => f.area_id === area.id);
  const target = { inspection, areaId: area.id, findingId: null, inspectorId: profile.appUserId };

  const setResult = async (itemId: string, result: FindingResult) => {
    const existing = areaFindings.find((f) => f.template_item_id === itemId);
    let findingId = existing?.id;
    if (existing) {
      await store.update('finding', existing.id, { result });
    } else {
      findingId = store.id();
      await store.create('finding', {
        id: findingId, inspection_id: inspection.id, area_id: area.id, template_item_id: itemId, equipment_id: null, result, note: null, severity: null,
        captured_by: profile.appUserId, captured_at: new Date().toISOString(), gps_lat: null, gps_lng: null,
      });
      void currentFix(consentGiven(store, 'location')).then((fix) => {
        if (fix && findingId) void store.update('finding', findingId, { gps_lat: fix.lat, gps_lng: fix.lng });
      });
    }
    if (result === 'fail') router.push({ pathname: '/inspection/[id]/item', params: { id: inspection.id, areaId: area.id, itemId } });
  };

  return (
    <Screen>
      <Stack.Screen options={{ title: area.label }} />
      <Txt variant="small" muted>
        {areaFindings.length} of {items.length} items recorded. Choosing Fail opens the item so you can add the photo and corrective action{inspection.voice_note_policy === 'strict' ? ' and voice note' : ''}.
      </Txt>
      {items.map((item) => {
        const f = areaFindings.find((q) => q.template_item_id === item.id);
        const v = f ? violations.find((q) => q.finding_id === f.id) : undefined;
        return (
          <Card key={item.id}>
            <Pressable
              onPress={() => router.push({ pathname: '/inspection/[id]/item', params: { id: inspection.id, areaId: area.id, itemId: item.id } })}
              accessibilityRole="button"
              accessibilityLabel={`Open item ${item.ordinal}: ${item.prompt}${f ? `, ${RESULT_LABEL[f.result]}` : ''}`}
              style={{ flexDirection: 'row', gap: space.sm, alignItems: 'flex-start' }}>
              <View style={{ flex: 1, gap: 2 }}>
                {item.section_label ? (
                  <Txt variant="label" muted>
                    {item.section_label}
                  </Txt>
                ) : null}
                <Txt variant="bodyStrong">{item.prompt}</Txt>
              </View>
              <Icon name="chevron-right" color={p.textMuted} />
            </Pressable>
            {readOnly ? <Pill label={f ? RESULT_LABEL[f.result] : 'Not recorded'} tone="neutral" /> : <ResultPicker value={f?.result ?? null} onChange={(r) => setResult(item.id, r)} itemLabel={item.prompt} />}
            {f ? (
              <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
                {photos.some((q) => q.finding_id === f.id) ? <Pill label="Photo" tone="neutral" /> : null}
                {voiceNotes.some((q) => q.finding_id === f.id) ? <Pill label="Voice note" tone="neutral" /> : null}
                {x.actions.some((q) => q.finding_id === f.id) ? <Pill label="Corrective action" tone="neutral" /> : null}
                {x.risks.some((q) => q.finding_id === f.id) ? <Pill label="Risk rated" tone="neutral" /> : null}
                {v ? <Pill label="Needs evidence" tone="warning" /> : null}
              </View>
            ) : null}
          </Card>
        );
      })}

      <SectionTitle>Area photos</SectionTitle>
      {photos.filter((q) => q.area_id === area.id && !q.finding_id).map((q) => (
        <PhotoCard key={q.id} photo={q} inspectorName={profile.displayName} onChange={readOnly ? undefined : (c) => void correctPhoto(store, q, c)} />
      ))}
      {!readOnly ? (
        <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
          <Button title="Take an area photo" icon="camera-outline" kind="secondary" onPress={async () => { const r = await capturePhoto(store, target, { source: 'camera', kind: 'area' }); setError(r.error ?? null); }} />
          <Button title="From gallery" icon="image-outline" kind="ghost" onPress={async () => { const r = await capturePhoto(store, target, { source: 'library', kind: 'area' }); setError(r.error ?? null); }} />
        </View>
      ) : null}

      <SectionTitle>Section voice notes</SectionTitle>
      {voiceNotes.filter((v) => v.area_id === area.id && !v.finding_id).map((v) => (
        <VoiceNoteCard key={v.id} note={v} transcripts={transcripts.filter((t) => t.voice_note_id === (v.root_evidence_id ?? v.id))} onCorrect={(body) => addTranscriptCorrection(store, v.root_evidence_id ?? v.id, body, profile.appUserId)} />
      ))}
      {!readOnly ? (
        <VoiceRecorder
          label="Record a voice note for this area"
          consentGiven={consentGiven(store, 'voice_recording')}
          onRecorded={async (uri, seconds) => {
            const r = await saveVoiceNote(store, target, uri, seconds);
            setError(r.error ?? null);
          }}
        />
      ) : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </Screen>
  );
}
