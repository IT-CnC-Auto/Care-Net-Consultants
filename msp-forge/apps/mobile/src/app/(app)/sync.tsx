// The sync queue: what is waiting, parked, failed or in conflict, with retry
// and conflict resolution, and a switch to work offline.

import { useSyncExternalStore } from 'react';

import { useNow } from '@/features/use-now';
import { View } from 'react-native';

import { Button, Card, Heading, KeyValue, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useQueueSummary } from '@/data/hooks';
import { useApp } from '@/state/app';
import { formatDateTime } from '@/lib/dates';
import type { SyncItem } from '@/lib/sync-queue';
import { space } from '@/theme/tokens';

const KIND_TEXT: Record<string, string> = {
  site: 'Site', department: 'Department', building: 'Building or zone', room: 'Room or area', equipment: 'Equipment tag',
  inspection: 'Inspection', area: 'Area', finding: 'Finding', photo: 'Photo', voice_note: 'Voice note', transcript: 'Transcript',
  risk: 'Risk', action: 'Corrective action', company: 'Organisation profile', person: 'Authorised person', registration: 'Registration',
  qualification: 'Qualification', consent: 'Consent',
};

const STATUS: Record<SyncItem['status'], { label: string; tone: 'neutral' | 'warning' | 'danger' | 'info' }> = {
  pending: { label: 'Waiting', tone: 'neutral' },
  in_flight: { label: 'Sending', tone: 'info' },
  waiting_server: { label: 'Kept on phone', tone: 'warning' },
  failed: { label: 'Failed', tone: 'danger' },
  conflict: { label: 'Conflict', tone: 'danger' },
};

const noop = () => () => {};

export default function SyncScreen() {
  const app = useApp();
  const { summary, queue } = useQueueSummary();
  const now = useNow(5000);
  const engine = app.engine;
  const state = useSyncExternalStore(engine ? engine.subscribe : noop, () => engine?.getState() ?? null, () => engine?.getState() ?? null);

  return (
    <Screen>
      <Heading>Sync</Heading>
      <Card>
        <KeyValue label="Signal" value={state?.online ? 'Online' : 'No signal'} />
        <KeyValue label="Sync" value={state?.paused ? 'Paused (working offline)' : state?.running ? 'Sending now' : 'On'} />
        <KeyValue label="Last synced" value={state?.lastSyncAt ? formatDateTime(new Date(state.lastSyncAt).toISOString()) : 'Not yet this session'} />
        <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
          <Button title={state?.paused ? 'Resume sync' : 'Work offline'} kind="secondary" compact onPress={() => engine?.setPaused(!state?.paused)} />
          <Button title="Sync now" compact onPress={() => engine?.kick()} disabled={!!state?.paused} />
        </View>
      </Card>
      <Txt variant="small" muted>
        {"Everything is saved on this phone first. Items go in order, parents before children, and retry by themselves with growing gaps when the signal drops. A change is never written over someone else's newer change without asking you."}
      </Txt>
      {summary.waitingServer ? (
        <Notice tone="warning" title={`${summary.waitingServer} kept on this phone`}>
          The server part for these is not switched on yet. They stay safely on the phone and are sent automatically once it is.
        </Notice>
      ) : null}
      <SectionTitle>{queue.length ? `${queue.length} in the queue` : 'Queue'}</SectionTitle>
      {queue.length === 0 ? <Notice tone="success">Everything is synced.</Notice> : null}
      {queue.map((q) => (
        <Card key={q.id}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm }}>
            <Txt variant="bodyStrong" style={{ flex: 1 }}>
              {`${KIND_TEXT[q.kind] ?? q.kind}: ${q.op === 'insert' || q.op === 'upload' ? 'new' : 'change'}`}
            </Txt>
            <Pill label={STATUS[q.status].label} tone={STATUS[q.status].tone} />
          </View>
          <Txt variant="tiny" muted>
            {`Made ${formatDateTime(new Date(q.createdAt).toISOString())}${q.attempts ? ` · ${q.attempts} attempts` : ''}${q.status === 'pending' && q.nextAttemptAt > now ? ` · next try ${formatDateTime(new Date(q.nextAttemptAt).toISOString())}` : ''}`}
          </Txt>
          {q.lastError ? <Txt variant="small">{q.lastError}</Txt> : null}
          {q.status === 'failed' || q.status === 'waiting_server' ? <Button title="Try again now" kind="ghost" compact onPress={() => engine?.retry(q.id)} /> : null}
          {q.status === 'conflict' ? (
            <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
              <Button title="Keep mine" compact onPress={() => engine?.resolve(q.id, 'keep_mine')} />
              <Button title="Use the server copy" kind="secondary" compact onPress={() => engine?.resolve(q.id, 'use_server')} />
            </View>
          ) : null}
        </Card>
      ))}
    </Screen>
  );
}
