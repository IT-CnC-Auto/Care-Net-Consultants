// POPIA consents as purpose chips, each defaulting to Not given (decisions
// section 2). Marketing is separate, unticked and double opt in. The wording
// versions are placeholders until the Bee-Inspect consent wording is confirmed.

import * as WebBrowser from 'expo-web-browser';
import { View } from 'react-native';

import { Button, Card, Chip, Heading, Notice, Pill, Screen, Txt } from '@/components/ui';
import { useRecords, useStore } from '@/data/hooks';
import { CONSENT_VERSIONS, PRIVACY_URL } from '@/lib/constants';
import { formatDate } from '@/lib/dates';
import type { Consent, ConsentKind } from '@/lib/types';
import { resultTone, space } from '@/theme/tokens';

const PURPOSES: { kind: ConsentKind; title: string; body: string }[] = [
  { kind: 'terms', title: 'Terms of use', body: 'You accept the Bee-Inspect terms.' },
  { kind: 'privacy', title: 'Privacy notice', body: 'You have read how Care Net processes your information.' },
  { kind: 'location', title: 'Location on evidence', body: 'GPS is sealed into photos and voice notes as proof of where they were taken.' },
  { kind: 'voice_recording', title: 'Voice notes', body: 'Bee-Inspect records the voice notes you make on site and keeps the audio as evidence.' },
  { kind: 'identifiable_people', title: 'People in photos', body: 'You may capture photos in which a person can be recognised, with their consent reference.' },
  { kind: 'fica_processing', title: 'FICA and identity checks', body: 'Care Net checks your identity and FICA documents to clear you as an inspector.' },
  { kind: 'marketing', title: 'News and offers', body: 'Care Net may send you news and offers. Separate from everything else; we confirm by email first.' },
];

export default function ConsentsScreen() {
  const store = useStore();
  const consents = useRecords('consent');
  const byKind = new Map(consents.map((c) => [c.consent_kind, c]));

  const set = async (kind: ConsentKind, granted: boolean) => {
    const now = new Date().toISOString();
    const cur = byKind.get(kind);
    const changes: Partial<Consent> = granted
      ? { granted: true, granted_at: now, withdrawn_at: null, confirmed_at: null, wording_version: CONSENT_VERSIONS[kind] }
      : { granted: false, withdrawn_at: cur?.granted ? now : null };
    if (cur) await store.update('consent', cur.id, changes);
    else await store.create('consent', { id: `consent-${kind}`, consent_kind: kind, granted: false, wording_version: CONSENT_VERSIONS[kind], granted_at: null, confirmed_at: null, withdrawn_at: null, ...changes });
  };

  return (
    <Screen>
      <Heading>POPIA consents</Heading>
      <Txt muted>Each purpose is separate and starts as Not given. You can change your mind at any time; a withdrawal is recorded, never erased.</Txt>
      <Notice tone="info">The consent wording is still being finalised; these are placeholder versions.</Notice>
      {PURPOSES.map((p) => {
        const c = byKind.get(p.kind);
        const given = !!c?.granted;
        const pendingConfirm = p.kind === 'marketing' && given && !c?.confirmed_at;
        return (
          <Card key={p.kind}>
            <Txt variant="bodyStrong">{p.title}</Txt>
            <Txt variant="small" muted>
              {p.body}
            </Txt>
            <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
              <Chip label="Not given" selected={!given} onPress={() => set(p.kind, false)} accessibilityLabel={`${p.title}: not given`} />
              <Chip label="Given" selected={given} tone={resultTone.pass} onPress={() => set(p.kind, true)} accessibilityLabel={`${p.title}: given`} />
            </View>
            {pendingConfirm ? <Pill label="Waiting for your email confirmation" tone="warning" /> : null}
            {given && c?.granted_at ? <Txt variant="tiny" muted>{`Given ${formatDate(c.granted_at)} · ${c.wording_version}`}</Txt> : null}
            {!given && c?.withdrawn_at ? <Txt variant="tiny" muted>{`Withdrawn ${formatDate(c.withdrawn_at)}`}</Txt> : null}
          </Card>
        );
      })}
      <Button title="Read the privacy policy" kind="ghost" onPress={() => WebBrowser.openBrowserAsync(PRIVACY_URL)} />
    </Screen>
  );
}
