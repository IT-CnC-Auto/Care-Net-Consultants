// One checklist item: the result, note and severity; photos with sealed
// metadata and markers; voice notes with editable transcripts; the equipment
// tag; the corrective action; and the 5 x 5 risk. A Fail needs a photo and a
// corrective action, and a voice note under the Strict policy.

import { router, Stack, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { ActionEditor, RiskEditor, RiskSummary } from '@/components/editors';
import { PhotoCard, VoiceNoteCard } from '@/components/evidence';
import { ResultPicker } from '@/components/result-picker';
import { Button, Card, Chip, ChipRow, Field, Icon, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { VoiceRecorder } from '@/components/voice-recorder';
import { addTranscriptCorrection, capturePhoto, consentGiven, correctPhoto, saveVoiceNote } from '@/features/capture';
import { currentFix } from '@/features/evidence';
import { useInspection, useMe } from '@/features/inspection';
import { onScan } from '@/features/scan-bus';
import { formatDate } from '@/lib/dates';
import { MISSING_TEXT } from '@/lib/gates';
import type { Finding, FindingResult } from '@/lib/types';
import { space } from '@/theme/tokens';

const SEVERITIES: NonNullable<Finding['severity']>[] = ['low', 'medium', 'high', 'critical'];
const SEVERITY_TEXT = { low: 'Low', medium: 'Medium', high: 'High', critical: 'Critical' } as const;

export default function ItemScreen() {
  const { id, areaId, itemId } = useLocalSearchParams<{ id: string; areaId: string; itemId: string }>();
  const x = useInspection(id);
  const { profile } = useMe();
  const [note, setNote] = useState<string | null>(null);
  const [editRisk, setEditRisk] = useState(false);
  const [editAction, setEditAction] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [scanned, setScanned] = useState<string | null>(null);

  const item = x.items.find((i) => i.id === itemId);
  const area = x.areas.find((a) => a.id === areaId);
  const finding = x.findings.find((f) => f.area_id === areaId && f.template_item_id === itemId);

  useEffect(
    () =>
      onScan((data) => {
        const tag = data.trim();
        const eq = x.store.list('equipment').find((e) => e.tag_code.toUpperCase() === tag.toUpperCase());
        if (eq && finding) void x.store.update('finding', finding.id, { equipment_id: eq.id });
        setScanned(eq ? null : tag);
      }),
    [x.store, finding],
  );

  if (!x.inspection || !item || !area || !profile) return <Screen><Notice tone="warning">This item is not on this phone.</Notice></Screen>;
  const { inspection, store } = x;
  const readOnly = inspection.status !== 'planned' && inspection.status !== 'in_progress';
  const photos = finding ? x.photos.filter((p) => p.finding_id === finding.id) : [];
  const notes = finding ? x.voiceNotes.filter((v) => v.finding_id === finding.id) : [];
  const action = finding ? x.actions.find((a) => a.finding_id === finding.id) : undefined;
  const risk = finding ? x.risks.find((r) => r.finding_id === finding.id) : undefined;
  const violation = finding ? x.violations.find((v) => v.finding_id === finding.id) : undefined;
  const equipment = finding?.equipment_id ? store.get('equipment', finding.equipment_id) : undefined;
  const siteEquipment = store.where('equipment', (e) => e.site_id === inspection.site_id);
  const target = { inspection, areaId: area.id, findingId: finding?.id ?? null, equipmentId: finding?.equipment_id ?? null, inspectorId: profile.appUserId };
  const isFail = finding?.result === 'fail';

  const setResult = async (result: FindingResult) => {
    if (finding) {
      await store.update('finding', finding.id, { result });
      return;
    }
    const fid = store.id();
    await store.create('finding', {
      id: fid, inspection_id: inspection.id, area_id: area.id, template_item_id: item.id, equipment_id: null, result, note: null, severity: null,
      captured_by: profile.appUserId, captured_at: new Date().toISOString(), gps_lat: null, gps_lng: null,
    });
    void currentFix(consentGiven(store, 'location')).then((fix) => {
      if (fix) void store.update('finding', fid, { gps_lat: fix.lat, gps_lng: fix.lng });
    });
  };

  return (
    <Screen>
      <Stack.Screen options={{ title: `Item ${item.ordinal}` }} />
      <Card>
        {item.section_label ? (
          <Txt variant="label" muted>
            {item.section_label} · {area.label}
          </Txt>
        ) : null}
        <Txt variant="bodyStrong">{item.prompt}</Txt>
        {item.kernel_ref ? (
          <Txt variant="tiny" muted>
            Reference {item.kernel_ref}
          </Txt>
        ) : null}
        {readOnly ? <Pill label="Submitted: read only" tone="info" /> : <ResultPicker value={finding?.result ?? null} onChange={setResult} itemLabel={item.prompt} />}
      </Card>

      {!finding ? <Notice tone="info">Choose Pass, Fail, N/A or Observe first. Then add photos, voice notes, a corrective action or a risk.</Notice> : null}

      {finding && isFail ? (
        violation ? (
          <Notice tone="warning" title="This Fail still needs">
            <View style={{ gap: 2 }}>
              {violation.missing.map((m) => (
                <Txt key={m} variant="small">
                  • {MISSING_TEXT[m]}
                </Txt>
              ))}
            </View>
          </Notice>
        ) : (
          <Notice tone="success">This Fail has everything the Fail rule needs.</Notice>
        )
      ) : null}

      {finding ? (
        <>
          <Field
            label="Note"
            value={note ?? finding.note ?? ''}
            onChangeText={setNote}
            onBlur={() => {
              if (note !== null && note !== (finding.note ?? '')) void store.update('finding', finding.id, { note: note.trim() || null });
            }}
            multiline
            editable={!readOnly}
            placeholder="What you saw. Workplace facts only, never anyone's health."
          />
          {finding.result === 'fail' || finding.result === 'observe' ? (
            <>
              <Txt variant="smallStrong">Severity</Txt>
              <ChipRow>
                {SEVERITIES.map((s) => (
                  <Chip key={s} label={SEVERITY_TEXT[s]} selected={finding.severity === s} onPress={readOnly ? undefined : () => store.update('finding', finding.id, { severity: finding.severity === s ? null : s })} />
                ))}
              </ChipRow>
            </>
          ) : null}

          <SectionTitle>Equipment tag</SectionTitle>
          {equipment ? (
            <Card>
              <View style={{ flexDirection: 'row', gap: space.sm, alignItems: 'center' }}>
                <Icon name="tag-outline" />
                <View style={{ flex: 1 }}>
                  <Txt variant="bodyStrong">{equipment.tag_code}</Txt>
                  <Txt variant="small" muted>
                    {equipment.kind}
                    {equipment.description ? ` · ${equipment.description}` : ''}
                  </Txt>
                </View>
              </View>
              {!readOnly ? <Button title="Unlink" kind="ghost" compact onPress={() => store.update('finding', finding.id, { equipment_id: null })} /> : null}
            </Card>
          ) : null}
          {!readOnly && !equipment ? (
            <>
              <Button title="Scan a QR code or barcode" icon="barcode-scan" kind="secondary" onPress={() => router.push('/scan')} />
              {siteEquipment.length ? (
                <ChipRow>
                  {siteEquipment.map((e) => (
                    <Chip key={e.id} label={e.tag_code} onPress={() => store.update('finding', finding.id, { equipment_id: e.id })} />
                  ))}
                </ChipRow>
              ) : null}
              {scanned ? (
                <Notice tone="info" title={`Tag ${scanned} is not on this site yet`}>
                  <Button title="Add it to the site" kind="ghost" compact onPress={() => router.push({ pathname: '/site-new', params: { kind: 'equipment', parentId: inspection.site_id } })} />
                </Notice>
              ) : null}
            </>
          ) : null}

          <SectionTitle>Photos</SectionTitle>
          {photos.map((ph) => (
            <PhotoCard key={ph.id} photo={ph} inspectorName={profile.displayName} onChange={readOnly ? undefined : (c) => void correctPhoto(store, ph, c)} />
          ))}
          {!readOnly ? (
            <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
              <Button title="Take a photo" icon="camera-outline" kind={isFail && photos.length === 0 ? 'primary' : 'secondary'} onPress={async () => { const r = await capturePhoto(store, target, { source: 'camera', kind: isFail ? 'risk_close_up' : equipment ? 'equipment' : 'other' }); setError(r.error ?? null); }} />
              <Button title="From gallery" icon="image-outline" kind="ghost" onPress={async () => { const r = await capturePhoto(store, target, { source: 'library', kind: 'other' }); setError(r.error ?? null); }} />
            </View>
          ) : null}
          {!consentGiven(store, 'location') ? <Txt variant="tiny" muted>Location consent is not given, so photos and voice notes are sealed without GPS.</Txt> : null}

          <SectionTitle>Voice notes</SectionTitle>
          {notes.map((v) => (
            <VoiceNoteCard key={v.id} note={v} transcripts={x.transcripts.filter((t) => t.voice_note_id === (v.root_evidence_id ?? v.id))} onCorrect={(body) => addTranscriptCorrection(store, v.root_evidence_id ?? v.id, body, profile.appUserId)} />
          ))}
          {!readOnly ? (
            <VoiceRecorder
              consentGiven={consentGiven(store, 'voice_recording')}
              onRecorded={async (uri, seconds) => {
                const r = await saveVoiceNote(store, target, uri, seconds);
                setError(r.error ?? null);
              }}
            />
          ) : null}

          <SectionTitle>Corrective action</SectionTitle>
          {action && !editAction ? (
            <Card>
              <Txt variant="bodyStrong">{action.description}</Txt>
              <Txt variant="small" muted>
                Owner {action.owner_name} · Due {formatDate(action.due_on)}
              </Txt>
              {!readOnly ? <Button title="Edit action" kind="ghost" compact onPress={() => setEditAction(true)} /> : null}
            </Card>
          ) : !readOnly && (editAction || isFail) ? (
            <ActionEditor
              initial={action}
              onCancel={action ? () => setEditAction(false) : undefined}
              onSave={async (a) => {
                if (action) await store.update('action', action.id, a);
                else await store.create('action', { id: store.id(), inspection_id: inspection.id, finding_id: finding.id, risk_id: risk?.id ?? null, status: 'open', ...a });
                setEditAction(false);
              }}
            />
          ) : !readOnly ? (
            <Button title="Add a corrective action" icon="plus" kind="secondary" onPress={() => setEditAction(true)} />
          ) : (
            <Txt muted>None.</Txt>
          )}

          <SectionTitle>Risk</SectionTitle>
          {risk && !editRisk ? (
            <RiskSummary risk={risk} onEdit={readOnly ? undefined : () => setEditRisk(true)} />
          ) : !readOnly && editRisk ? (
            <RiskEditor
              initial={risk}
              onCancel={() => setEditRisk(false)}
              onSave={async (r) => {
                if (risk) await store.update('risk', risk.id, r);
                else {
                  const rid = store.id();
                  await store.create('risk', { id: rid, inspection_id: inspection.id, area_id: area.id, finding_id: finding.id, ...r });
                  if (action && !action.risk_id) await store.update('action', action.id, { risk_id: rid });
                }
                setEditRisk(false);
              }}
            />
          ) : !readOnly ? (
            <Button title="Rate a risk" icon="grid" kind="secondary" onPress={() => setEditRisk(true)} />
          ) : (
            <Txt muted>Not rated.</Txt>
          )}
        </>
      ) : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </Screen>
  );
}
