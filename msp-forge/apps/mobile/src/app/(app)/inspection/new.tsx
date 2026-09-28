// Start an inspection at a place. The template picker is shaped by the
// company's kernel industry and the kind of place: the industry walkthrough and
// the Section F registers that suit the place come first; every Section F
// register stays available everywhere. Intervals and legal bases show only
// what the kernel holds; otherwise "Set by your competent person".

import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { View } from 'react-native';

import { Breadcrumb, PlaceRow, SearchField } from '@/components/place-ui';
import { Button, Card, Chip, ChipRow, Field, Heading, KeyValue, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { haptic } from '@/features/haptics';
import { useMe } from '@/features/inspection';
import { usePlaces } from '@/features/places';
import { canStartInspection } from '@/lib/gates';
import { basisText, intervalText, kernel, placeType, templatesFor, type KernelTemplate } from '@/lib/kernel';
import { searchPlaces, typeLabel } from '@/lib/places';
import { brand, space } from '@/theme/tokens';

function TemplateCard({ t, why, chosen, onPick }: { t: KernelTemplate; why?: string; chosen: boolean; onPick: () => void }) {
  return (
    <Card
      onPress={() => {
        haptic.tap();
        onPick();
      }}
      style={chosen ? { borderColor: brand.deepRed, borderWidth: 2 } : undefined}
      accessibilityLabel={`${t.name}, ${t.items.length} checks${chosen ? ', chosen' : ''}`}>
      <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: space.sm }}>
        <Txt variant="bodyStrong" style={{ flex: 1 }}>
          {t.name}
        </Txt>
        <Pill label={t.kind === 'industry' ? 'Industry' : (t.section_f_element_code ?? 'Register')} tone={t.kind === 'industry' ? 'info' : 'neutral'} />
      </View>
      <Txt variant="tiny" muted>
        {`${t.items.length} checks · ${intervalText(t)}${why ? ` · ${why}` : ''}`}
      </Txt>
    </Card>
  );
}

export default function NewInspectionScreen() {
  const params = useLocalSearchParams<{ placeId?: string }>();
  const { store, app, profile, inspector, company: activeCompany } = useMe();
  const b = kernel();
  const [placeId, setPlaceId] = useState<string | null>(params.placeId ?? app.recentPlaceIds.find((id) => store.get('place', id)?.client_account_id === activeCompany?.id) ?? null);
  const place = placeId ? store.get('place', placeId) : undefined;
  const company = place ? store.get('company', place.client_account_id) : activeCompany;
  const tree = usePlaces(company?.id);
  const gate = canStartInspection(company?.onboarding_status, inspector?.status);
  const [changing, setChanging] = useState(!place);
  const [placeQuery, setPlaceQuery] = useState('');
  const [q, setQ] = useState('');
  const [showAll, setShowAll] = useState(false);
  const [templateId, setTemplateId] = useState<string | null>(null);
  const [areaIds, setAreaIds] = useState<string[]>([]);
  const [adhoc, setAdhoc] = useState('');
  const [title, setTitle] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pick = templatesFor(b, { industryCode: company?.industry_code, placeTypeCode: place?.place_type, query: q });
  const chosen = templateId ? b.templates.find((t) => t.id === templateId) : undefined;
  const kids = place ? tree.childrenOf(place.id) : [];
  const grandKids = kids.flatMap((k) => tree.childrenOf(k.id));
  const walkable = [...kids, ...grandKids];
  const autoTitle = chosen && place ? `${chosen.name}, ${place.name}` : '';
  const pt = placeType(b, place?.place_type);
  const placeHits = searchPlaces(b, tree.places, [], placeQuery, company?.id).filter((h) => h.kind === 'place');

  const start = async () => {
    setError(null);
    if (!gate.ok || !profile || !place || !chosen || !company) return;
    if (!store.get('template', chosen.id)) {
      setError('The kernel templates are still loading on this phone. Try again in a moment.');
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
      const root = tree.pathOf(place.id)[0] ?? place;
      await store.create('inspection', {
        id,
        tenant_id: profile.tenantId,
        client_account_id: company.id,
        site_id: root.id,
        place_id: place.id,
        template_id: chosen.id,
        inspector_user_id: profile.appUserId,
        title: (title.trim() || autoTitle).slice(0, 200),
        status: 'in_progress',
        voice_note_policy: profile.voicePolicy,
        started_at: new Date().toISOString(),
        submitted_at: null,
        device_id: deviceId,
      });
      let ordinal = 1;
      for (const aid of areaIds) {
        const a = store.get('place', aid);
        await store.create('area', { id: store.id(), inspection_id: id, room_id: null, place_id: aid, label: a?.name ?? 'Area', ordinal: ordinal++ });
      }
      if (adhoc.trim()) await store.create('area', { id: store.id(), inspection_id: id, room_id: null, place_id: place.id, label: adhoc.trim(), ordinal: ordinal++ });
      if (ordinal === 1) await store.create('area', { id: store.id(), inspection_id: id, room_id: null, place_id: place.id, label: place.name, ordinal: ordinal++ });
      await app.touchPlace(place.id, company.id);
      haptic.success();
      router.replace({ pathname: '/inspection/[id]', params: { id } });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The inspection could not be started.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Screen footer={<Button title="Start inspection" icon="clipboard-play-outline" onPress={start} busy={busy} disabled={!gate.ok || !place || !chosen} accessibilityHint={!gate.ok ? gate.reasons.join(' ') : !place ? 'Choose a place first' : !chosen ? 'Choose a template first' : undefined} />}>
      <Heading>New inspection</Heading>
      {!gate.ok ? (
        <Notice tone="warning" title="Start inspection is not open yet">
          <View style={{ gap: 2 }}>
            {gate.reasons.map((r) => (
              <Txt key={r} variant="small">
                {r}
              </Txt>
            ))}
          </View>
        </Notice>
      ) : null}

      <SectionTitle action={place && !changing ? <Button title="Change" kind="ghost" compact onPress={() => setChanging(true)} /> : undefined}>1. Where</SectionTitle>
      {place && !changing ? (
        <Card>
          <Breadcrumb crumbs={[{ label: company?.trading_name || company?.legal_name || '' }, ...tree.pathOf(place.id).map((p) => ({ label: p.name }))]} />
          <Txt variant="small" muted>
            {typeLabel(b, place)}
            {company?.industry_code ? ` · ${b.industries.find((i) => i.code === company.industry_code)?.name}` : ''}
          </Txt>
        </Card>
      ) : (
        <View style={{ gap: space.sm }}>
          <SearchField value={placeQuery} onChangeText={setPlaceQuery} placeholder={`Places of ${company?.trading_name ?? 'this company'}`} label="Search places" />
          <Card style={{ padding: 0, gap: 0 }}>
            {(placeQuery.trim() ? placeHits.map((h) => store.get('place', h.id)).filter((x) => !!x) : tree.places)
              .slice(0, 12)
              .map((p) =>
                p ? (
                  <PlaceRow
                    key={p.id}
                    place={p}
                    path={tree.pathOf(p.id).slice(0, -1).map((x) => x.name).join(' › ')}
                    onPress={() => {
                      setPlaceId(p.id);
                      setAreaIds([]);
                      setChanging(false);
                    }}
                  />
                ) : null,
              )}
          </Card>
          {tree.places.length === 0 ? <Notice tone="warning">This company has no places yet. Add one under Places first.</Notice> : null}
        </View>
      )}

      <SectionTitle>2. Template</SectionTitle>
      <SearchField value={q} onChangeText={setQ} placeholder="Search templates and checks" label="Search templates" />
      {pick.suggested.length ? (
        <>
          <Txt variant="label" muted>
            {`Suggested${pt ? ` for this ${pt.label.toLowerCase()}` : ''}`}
          </Txt>
          {pick.suggested.map((c) => (
            <TemplateCard key={c.template.id} t={c.template} why={c.why} chosen={templateId === c.template.id} onPick={() => setTemplateId(c.template.id)} />
          ))}
        </>
      ) : (
        <Txt variant="small" muted>
          {company?.industry_code ? 'No suggestion matches; every Section F register is below.' : "Choose the company's industry to get suggestions; every Section F register is below."}
        </Txt>
      )}
      <Button title={showAll ? 'Hide the Section F registers' : `All ${pick.registers.length} Section F registers, available everywhere`} icon={showAll ? 'chevron-up' : 'chevron-down'} kind="ghost" compact onPress={() => setShowAll(!showAll)} style={{ alignSelf: 'flex-start' }} />
      {showAll ? pick.registers.map((t) => <TemplateCard key={t.id} t={t} chosen={templateId === t.id} onPick={() => setTemplateId(t.id)} />) : null}

      {chosen ? (
        <Card>
          <Txt variant="label" muted>
            About this template
          </Txt>
          <Txt variant="small">{chosen.description}</Txt>
          {chosen.section_f_element_code ? <KeyValue label="Files into" value={`Section F, ${chosen.section_f_element_code}`} /> : null}
          <KeyValue label="How often" value={intervalText(chosen)} />
          {chosen.responsible ? <KeyValue label="Usually done by" value={chosen.responsible} /> : null}
          <KeyValue label="Legal basis" value={basisText(chosen)} />
          <KeyValue label="Kept" value={chosen.retention.text} />
          <Txt variant="tiny" muted>
            {`Care Net kernel ${b.kernel.version}. Legal intervals show only once Care Net has verified them.`}
          </Txt>
        </Card>
      ) : null}

      <SectionTitle>3. Areas to walk</SectionTitle>
      {walkable.length ? (
        <ChipRow>
          {walkable.map((a) => (
            <Chip key={a.id} label={a.name} selected={areaIds.includes(a.id)} onPress={() => { haptic.tap(); setAreaIds((ids) => (ids.includes(a.id) ? ids.filter((x) => x !== a.id) : [...ids, a.id])); }} />
          ))}
        </ChipRow>
      ) : (
        <Txt variant="small" muted>
          {place ? `Nothing is set up under ${place.name}; the inspection walks ${place.name} itself unless you name areas.` : 'Choose the place first.'}
        </Txt>
      )}
      <Field label="Or name another area (optional)" value={adhoc} onChangeText={setAdhoc} placeholder="For example: loading bay" />

      <SectionTitle>4. Title</SectionTitle>
      <Field label="Inspection title" value={title} onChangeText={setTitle} placeholder={autoTitle || 'Template and place'} />
      <Txt variant="tiny" muted>
        {`Works without signal. Voice note policy: ${profile?.voicePolicy === 'strict' ? 'Strict (every Fail needs a voice note)' : 'Recommended'}.`}
      </Txt>
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </Screen>
  );
}
