// The offline inspection canvas: areas with progress, the Fail rule, the risk
// register and corrective actions, and the way on to the report draft.

import { router, Stack, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { View } from 'react-native';

import { BandLegend, RiskBadge } from '@/components/risk';
import { Button, Card, Field, KeyValue, ListRow, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useInspection } from '@/features/inspection';
import { formatDate, formatDateTime, plural } from '@/lib/dates';
import { missingText } from '@/lib/gates';
import { pathOf } from '@/lib/places';
import { riskScore } from '@/lib/risk';
import { space } from '@/theme/tokens';

export default function InspectionScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const x = useInspection(id);
  const [newArea, setNewArea] = useState('');
  if (!x.inspection) return <Screen><Notice tone="warning">This inspection is not on this phone.</Notice></Screen>;
  const { inspection, template, items, areas, findings, photos, voiceNotes, risks, actions, violations, report, store } = x;
  const placePath = pathOf(store.list('place'), inspection.place_id ?? inspection.site_id).map((p) => p.name).join(' › ');
  const readOnly = inspection.status !== 'planned' && inspection.status !== 'in_progress';
  const itemById = new Map(items.map((i) => [i.id, i]));

  const addArea = async () => {
    if (!newArea.trim()) return;
    await store.create('area', { id: store.id(), inspection_id: inspection.id, room_id: null, place_id: inspection.place_id, label: newArea.trim(), ordinal: areas.length + 1 });
    setNewArea('');
  };

  return (
    <Screen
      footer={
        <Button
          title={report ? (report.status === 'issued' ? 'Open the Issued report' : 'Open the report draft') : 'Review and draft the report'}
          icon="file-document-edit-outline"
          onPress={() => router.push({ pathname: '/inspection/[id]/draft', params: { id: inspection.id } })}
        />
      }>
      <Stack.Screen options={{ title: 'Inspection' }} />
      <Card>
        <Txt variant="bodyStrong">{inspection.title}</Txt>
        <KeyValue label="Place" value={placePath} />
        <KeyValue label="Template" value={template?.name ?? ''} />
        <KeyValue label="Section F register" value={template?.section_f_element_code ?? 'To be mapped'} />
        <KeyValue label="Started" value={formatDateTime(inspection.started_at)} />
        <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
          <Pill label={inspection.voice_note_policy === 'strict' ? 'Strict voice policy' : 'Recommended voice policy'} tone="neutral" />
          <Pill label={readOnly ? 'Submitted' : 'In progress'} tone={readOnly ? 'info' : 'warning'} />
          {x.pendingSync ? <Pill label={`${x.pendingSync} waiting to sync`} tone="neutral" /> : <Pill label="Synced" tone="success" />}
        </View>
      </Card>

      {violations.length ? (
        <Notice tone="warning" title={`Fail rule: ${violations.length === 1 ? '1 item still needs' : `${violations.length} items still need`} evidence`}>
          <View style={{ gap: space.xs }}>
            {violations.map((v) => {
              const f = findings.find((q) => q.id === v.finding_id);
              const item = f?.template_item_id ? itemById.get(f.template_item_id) : undefined;
              return (
                <Txt key={v.finding_id} variant="small">
                  {item?.prompt ?? f?.note ?? 'Fail finding'}: needs {missingText(v.missing)}.
                </Txt>
              );
            })}
          </View>
        </Notice>
      ) : findings.some((f) => f.result === 'fail') ? (
        <Notice tone="success">Every Fail has its photo, corrective action{inspection.voice_note_policy === 'strict' ? ' and voice note' : ''}.</Notice>
      ) : null}

      <SectionTitle>Areas</SectionTitle>
      <Card style={{ paddingVertical: 0 }}>
        {areas.map((a) => {
          const af = findings.filter((f) => f.area_id === a.id);
          const fails = af.filter((f) => f.result === 'fail').length;
          return (
            <ListRow
              key={a.id}
              icon="door-open"
              title={a.label}
              subtitle={`${af.length} of ${plural(items.length, 'item')} · ${fails} Fail · ${plural(photos.filter((p) => p.area_id === a.id).length, 'photo')} · ${plural(voiceNotes.filter((v) => v.area_id === a.id).length, 'voice note')}`}
              onPress={() => router.push({ pathname: '/inspection/[id]/area/[areaId]', params: { id: inspection.id, areaId: a.id } })}
            />
          );
        })}
      </Card>
      {!readOnly ? (
        <View style={{ gap: space.sm }}>
          <Field label="Add another area" value={newArea} onChangeText={setNewArea} placeholder="For example: loading bay 2" />
          <Button title="Add area" icon="plus" kind="secondary" compact disabled={!newArea.trim()} onPress={addArea} />
        </View>
      ) : null}

      <SectionTitle>Risk register</SectionTitle>
      <BandLegend />
      {risks.length === 0 ? <Txt muted>No risks rated yet. Rate a risk from any checklist item.</Txt> : null}
      {risks.map((r) => (
        <Card key={r.id}>
          <Txt variant="bodyStrong">{r.hazard}</Txt>
          <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
            <RiskBadge prefix="Inherent" score={riskScore(r.inherent_likelihood, r.inherent_severity)} />
            <RiskBadge prefix="Residual" score={riskScore(r.residual_likelihood, r.residual_severity)} />
          </View>
        </Card>
      ))}

      <SectionTitle>Corrective actions</SectionTitle>
      {actions.length === 0 ? <Txt muted>None yet.</Txt> : null}
      {actions.map((a) => (
        <Card key={a.id}>
          <Txt variant="bodyStrong">{a.description}</Txt>
          <Txt variant="small" muted>
            Owner {a.owner_name} · Due {formatDate(a.due_on)} · {a.status === 'open' ? 'Open' : a.status}
          </Txt>
        </Card>
      ))}
    </Screen>
  );
}
