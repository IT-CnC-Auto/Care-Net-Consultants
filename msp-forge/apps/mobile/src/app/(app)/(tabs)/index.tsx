import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { BrandBar } from '@/components/brand-bar';
import { PlaceRow } from '@/components/place-ui';
import { Button, Card, EmptyState, Heading, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useInspection, useMe } from '@/features/inspection';
import { useOpenPlace, useStartHere } from '@/features/places';
import { formatDate, plural } from '@/lib/dates';
import { canStartInspection, COMPANY_STATUS_LABEL, INSPECTOR_STATUS_LABEL } from '@/lib/gates';
import { pathOf } from '@/lib/places';
import type { Inspection, Place, Report } from '@/lib/types';
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
  const { app, store, profile, inspector, company, companyId, industry } = useMe();
  const openPlace = useOpenPlace();
  const startHere = useStartHere();
  const gate = canStartInspection(company?.onboarding_status, inspector?.status);
  const inCompany = (inspectionId: string) => store.get('inspection', inspectionId)?.client_account_id === companyId;
  const open = store.where('inspection', (i) => i.client_account_id === companyId && (i.status === 'planned' || i.status === 'in_progress')).sort((a, b) => (b.started_at ?? '').localeCompare(a.started_at ?? ''));
  const elsewhere = store.where('inspection', (i) => i.client_account_id !== companyId && (i.status === 'planned' || i.status === 'in_progress')).length;
  const issued = store.where('report', (r) => r.status === 'issued' && inCompany(r.inspection_id)).sort((a, b) => (b.issued_at ?? '').localeCompare(a.issued_at ?? ''));
  const awaiting = store.where('report', (r) => r.status === 'awaiting_signoff' && inCompany(r.inspection_id));
  const firstName = (profile?.displayName ?? '').split(' ')[0];
  const places = store.list('place');
  const recent = app.recentPlaceIds.map((id) => store.get('place', id)).filter((p): p is Place => !!p && !p.archived_at).slice(0, 4);
  const [resume, setResume] = useState<{ companyId: string; step: number } | null>(null);
  useEffect(() => {
    let live = true;
    void store.kvGet('register.draft').then((raw) => {
      try {
        const d = raw ? (JSON.parse(raw) as { companyId: string | null; step: number }) : null;
        if (live) setResume(d && d.companyId && d.step < 3 ? { companyId: d.companyId, step: d.step } : null);
      } catch {
        if (live) setResume(null);
      }
    });
    return () => {
      live = false;
    };
  }, [store]);
  const resumeCompany = resume ? store.get('company', resume.companyId) : undefined;

  return (
    <View style={{ flex: 1 }}>
      <BrandBar title="Home" />
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

        {resumeCompany ? (
          <Card onPress={() => router.push('/register')} accessibilityLabel={`Carry on registering ${resumeCompany.legal_name}`}>
            <Txt variant="label" muted>
              Registration saved on this phone
            </Txt>
            <Txt variant="bodyStrong">{resumeCompany.legal_name}</Txt>
            <Txt variant="small" muted>
              {`Step ${(resume?.step ?? 0) + 1} of 4: ${['Company', 'Places', 'People', 'Done'][resume?.step ?? 0]}. Tap to carry on.`}
            </Txt>
          </Card>
        ) : null}

        <Card>
          {industry ? (
            <Txt variant="small" muted>
              {industry.name}
            </Txt>
          ) : null}
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

        {recent.length ? (
          <>
            <SectionTitle action={<Button title="All places" kind="ghost" compact onPress={() => router.push('/switcher')} />}>Recent places</SectionTitle>
            <Card style={{ padding: 0, gap: 0 }}>
              {recent.map((pl) => (
                <PlaceRow key={pl.id} place={pl} path={pathOf(places, pl.id).slice(0, -1).map((x) => x.name).join(' › ') || (store.get('company', pl.client_account_id)?.trading_name ?? '')} onPress={() => openPlace(pl)} onStart={() => startHere(pl)} />
              ))}
            </Card>
          </>
        ) : null}

        <SectionTitle>In progress</SectionTitle>
        {open.length ? open.map((i) => <InspectionCard key={i.id} inspection={i} />) : <EmptyState icon="clipboard-text-outline" title="No inspections in progress here" body="Open a place and choose Start inspection here. It works without signal." />}
        {elsewhere ? (
          <Button title={`${elsewhere} more in progress at other companies`} kind="ghost" compact icon="swap-horizontal" onPress={() => router.push('/switcher')} style={{ alignSelf: 'flex-start' }} />
        ) : null}

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
        {issued.length ? issued.map((r) => <ReportRow key={r.id} report={r} title={store.get('inspection', r.inspection_id)?.title ?? 'Report'} />) : <Txt muted>No Issued reports for this company yet.</Txt>}

        <Button title="Register a company" icon="domain-plus" kind="secondary" onPress={() => router.push('/register')} />
      </Screen>
    </View>
  );
}
