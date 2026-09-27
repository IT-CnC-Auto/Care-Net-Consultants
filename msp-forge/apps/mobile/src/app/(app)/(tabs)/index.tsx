import { router } from 'expo-router';
import { View } from 'react-native';

import { BrandBar } from '@/components/brand-bar';
import { Button, Card, EmptyState, Heading, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useInspection, useMe } from '@/features/inspection';
import { formatDate, plural } from '@/lib/dates';
import { canStartInspection, COMPANY_STATUS_LABEL, INSPECTOR_STATUS_LABEL } from '@/lib/gates';
import type { Inspection, Report } from '@/lib/types';
import { space } from '@/theme/tokens';

function greeting(): string {
  const h = new Date().getHours();
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
}

function InspectionCard({ inspection }: { inspection: Inspection }) {
  const { items, areas, findings, violations, pendingSync } = useInspection(inspection.id);
  const total = items.length * Math.max(1, areas.length);
  const fails = findings.filter((f) => f.result === 'fail').length;
  return (
    <Card onPress={() => router.push({ pathname: '/inspection/[id]', params: { id: inspection.id } })} accessibilityLabel={`Open ${inspection.title}`}>
      <Txt variant="bodyStrong">{inspection.title}</Txt>
      <Txt variant="small" muted>
        {plural(areas.length, 'area')} · {findings.length} of {plural(total, 'item')} recorded · {fails} Fail
      </Txt>
      <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
        <Pill label={inspection.voice_note_policy === 'strict' ? 'Strict voice policy' : 'Recommended voice policy'} tone="neutral" />
        {violations.length ? <Pill label={violations.length === 1 ? '1 Fail item needs evidence' : `${violations.length} Fail items need evidence`} tone="warning" /> : <Pill label="Fail rule met" tone="success" />}
        {pendingSync ? <Pill label={`${pendingSync} waiting to sync`} tone="neutral" /> : null}
      </View>
    </Card>
  );
}

function ReportRow({ report, title }: { report: Report; title: string }) {
  const filed = report.file_link_status === 'linked' || report.file_link_status === 'section_only';
  return (
    <Card onPress={() => router.push({ pathname: '/inspection/[id]/draft', params: { id: report.inspection_id } })} accessibilityLabel={`Open report ${title}`}>
      <Txt variant="bodyStrong">{title}</Txt>
      <Txt variant="small" muted>
        Issued {formatDate(report.issued_at)} · Signed by {report.signed_by}
      </Txt>
      <Pill label={filed ? `In Section F (${report.section_f_element_code ?? 'register'})` : 'Stored, awaiting eligibility'} tone={filed ? 'success' : 'warning'} />
    </Card>
  );
}

export default function HomeScreen() {
  const { app, store, profile, inspector, company } = useMe();
  const gate = canStartInspection(company?.onboarding_status, inspector?.status);
  const open = store.where('inspection', (i) => i.status === 'planned' || i.status === 'in_progress').sort((a, b) => (b.started_at ?? '').localeCompare(a.started_at ?? ''));
  const issued = store.where('report', (r) => r.status === 'issued').sort((a, b) => (b.issued_at ?? '').localeCompare(a.issued_at ?? ''));
  const awaiting = store.where('report', (r) => r.status === 'awaiting_signoff');
  const firstName = (profile?.displayName ?? '').split(' ')[0];

  return (
    <View style={{ flex: 1 }}>
      <BrandBar title={company?.trading_name ?? company?.legal_name ?? undefined} />
      <Screen edges={[]}>
        <Heading level={1}>
          {greeting()}
          {firstName ? `, ${firstName}` : ''}
        </Heading>
        {app.deviceRooted ? (
          <Notice tone="danger" title="This phone looks rooted or jailbroken">
            You can capture and sync, but Issue is blocked on this phone. The check is a heuristic and can be wrong; speak to a sales executive if it is.
          </Notice>
        ) : null}
        {app.biometricAvailable && !app.biometricOffered ? (
          <Card>
            <Txt variant="bodyStrong">Unlock with your fingerprint or face</Txt>
            <Txt variant="small" muted>
              Next time, open Bee-Inspect with your fingerprint or face. Every 7 days it asks for your authenticator code again.
            </Txt>
            <View style={{ flexDirection: 'row', gap: space.sm }}>
              <Button title="Turn on" compact onPress={() => app.setBiometricEnabled(true)} />
              <Button title="Not now" kind="ghost" compact onPress={() => app.setBiometricEnabled(false)} />
            </View>
          </Card>
        ) : null}

        <Card>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
            <Pill label={`Company ${company ? COMPANY_STATUS_LABEL[company.onboarding_status] : 'Not started'}`} tone={company?.onboarding_status === 'active' ? 'success' : 'warning'} />
            <Pill label={`Inspector ${inspector ? INSPECTOR_STATUS_LABEL[inspector.status] : 'Identity'}`} tone={inspector?.status === 'cleared' ? 'success' : 'warning'} />
          </View>
          <Button title="Start inspection" icon="clipboard-plus-outline" disabled={!gate.ok} onPress={() => router.push('/inspection/new')} accessibilityHint={gate.ok ? undefined : gate.reasons.join(' ')} />
          {!gate.ok ? (
            <View style={{ gap: space.xs }}>
              {gate.reasons.map((r) => (
                <Txt key={r} variant="small" muted>
                  {r}
                </Txt>
              ))}
              <Button title="See what is outstanding" kind="ghost" compact onPress={() => router.push('/account/inspector')} />
            </View>
          ) : null}
        </Card>

        <SectionTitle>In progress</SectionTitle>
        {open.length ? open.map((i) => <InspectionCard key={i.id} inspection={i} />) : <EmptyState icon="clipboard-text-outline" title="No inspections in progress" body="Start one when you are on site. It works without signal." />}

        {awaiting.length ? (
          <>
            <SectionTitle>Awaiting sign off</SectionTitle>
            {awaiting.map((r) => (
              <Card key={r.id} onPress={() => router.push({ pathname: '/inspection/[id]/sign', params: { id: r.inspection_id } })}>
                <Txt variant="bodyStrong">{store.get('inspection', r.inspection_id)?.title ?? 'Report'}</Txt>
                <Pill label="Awaiting a competent person's signature" tone="warning" />
              </Card>
            ))}
          </>
        ) : null}

        <SectionTitle>Issued reports</SectionTitle>
        {issued.length ? issued.map((r) => <ReportRow key={r.id} report={r} title={store.get('inspection', r.inspection_id)?.title ?? 'Report'} />) : <Txt muted>No Issued reports yet.</Txt>}
      </Screen>
    </View>
  );
}
