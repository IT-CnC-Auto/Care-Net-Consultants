import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import { View } from 'react-native';

import { Button, Card, Chip, ChipRow, Field, Heading, Notice, Screen, SectionTitle, Txt } from '@/components/ui';
import { useMe } from '@/features/inspection';
import { canStartInspection } from '@/lib/gates';
import { brand, space } from '@/theme/tokens';

export default function NewInspectionScreen() {
  const { store, profile, inspector, company } = useMe();
  const gate = canStartInspection(company?.onboarding_status, inspector?.status);
  const sites = store.where('site', (s) => s.client_account_id === profile?.companyId);
  const templates = store.list('template').sort((a, b) => a.name.localeCompare(b.name));
  const [siteId, setSiteId] = useState<string | null>(sites[0]?.id ?? null);
  const [templateId, setTemplateId] = useState<string | null>(null);
  const [roomIds, setRoomIds] = useState<string[]>([]);
  const [adhoc, setAdhoc] = useState('');
  const [title, setTitle] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const site = siteId ? store.get('site', siteId) : undefined;
  const template = templateId ? store.get('template', templateId) : undefined;
  const buildings = store.where('building', (b) => b.site_id === siteId);
  const rooms = store.where('room', (r) => r.site_id === siteId);
  const autoTitle = useMemo(() => (template && site ? `${template.name}, ${site.name}` : ''), [template, site]);

  const start = async () => {
    setError(null);
    if (!gate.ok || !profile || !site || !template) return;
    if (roomIds.length === 0 && !adhoc.trim()) {
      setError('Choose at least one room or area to walk, or name one.');
      return;
    }
    setBusy(true);
    try {
      let deviceId = await store.kvGet('device_id');
      if (!deviceId) {
        deviceId = `PHONE-${store.id().slice(0, 8).toUpperCase()}`;
        await store.kvSet('device_id', deviceId);
      }
      const id = store.id();
      await store.create('inspection', {
        id,
        tenant_id: profile.tenantId,
        client_account_id: profile.companyId,
        site_id: site.id,
        template_id: template.id,
        inspector_user_id: profile.appUserId,
        title: (title.trim() || autoTitle).slice(0, 200),
        status: 'in_progress',
        voice_note_policy: profile.voicePolicy,
        started_at: new Date().toISOString(),
        submitted_at: null,
        device_id: deviceId,
      });
      let ordinal = 1;
      for (const rid of roomIds) {
        const r = store.get('room', rid);
        await store.create('area', { id: store.id(), inspection_id: id, room_id: rid, label: r?.name ?? 'Area', ordinal: ordinal++ });
      }
      if (adhoc.trim()) await store.create('area', { id: store.id(), inspection_id: id, room_id: null, label: adhoc.trim(), ordinal: ordinal++ });
      router.replace({ pathname: '/inspection/[id]', params: { id } });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The inspection could not be started.');
    } finally {
      setBusy(false);
    }
  };

  if (!gate.ok) {
    return (
      <Screen>
        <Heading>Start Inspection is not open yet</Heading>
        {gate.reasons.map((r) => (
          <Notice key={r} tone="warning">
            {r}
          </Notice>
        ))}
        <Button title="See inspector status" onPress={() => router.replace('/account/inspector')} />
      </Screen>
    );
  }

  return (
    <Screen footer={<Button title="Start inspection" icon="clipboard-play-outline" onPress={start} busy={busy} disabled={!site || !template} />}>
      <Heading>New inspection</Heading>
      <Txt variant="small" muted>
        Works without signal. Voice note policy: {profile?.voicePolicy === 'strict' ? 'Strict (every Fail needs a voice note)' : 'Recommended'}.
      </Txt>

      <SectionTitle>1. Site</SectionTitle>
      {sites.length === 0 ? <Notice tone="warning">Add a site first, under Sites.</Notice> : null}
      <ChipRow>
        {sites.map((s) => (
          <Chip key={s.id} label={s.name} selected={siteId === s.id} onPress={() => { setSiteId(s.id); setRoomIds([]); }} />
        ))}
      </ChipRow>

      <SectionTitle>2. Template</SectionTitle>
      <View style={{ gap: space.sm }}>
        {templates.map((t) => (
          <Card key={t.id} onPress={() => setTemplateId(t.id)} style={templateId === t.id ? { borderColor: brand.deepRed, borderWidth: 2 } : undefined} accessibilityLabel={`${t.name}${templateId === t.id ? ', chosen' : ''}`}>
            <Txt variant="bodyStrong">{t.name}</Txt>
            <Txt variant="tiny" muted>
              Files into Section F register {t.section_f_element_code ?? 'to be mapped'}
            </Txt>
          </Card>
        ))}
      </View>

      <SectionTitle>3. Rooms and areas to walk</SectionTitle>
      {buildings.map((b) => (
        <View key={b.id} style={{ gap: space.xs }}>
          <Txt variant="label" muted>
            {b.name}
          </Txt>
          <ChipRow>
            {rooms
              .filter((r) => r.building_id === b.id)
              .map((r) => (
                <Chip key={r.id} label={r.name} selected={roomIds.includes(r.id)} onPress={() => setRoomIds((ids) => (ids.includes(r.id) ? ids.filter((x) => x !== r.id) : [...ids, r.id]))} />
              ))}
          </ChipRow>
        </View>
      ))}
      <Field label="Or name another area (optional)" value={adhoc} onChangeText={setAdhoc} placeholder="For example: loading bay" />

      <SectionTitle>4. Title</SectionTitle>
      <Field label="Inspection title" value={title} onChangeText={setTitle} placeholder={autoTitle || 'Chosen template and site'} />
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </Screen>
  );
}
