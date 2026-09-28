import Constants from 'expo-constants';
import { router } from 'expo-router';
import { View } from 'react-native';

import { BrandBar } from '@/components/brand-bar';
import { Button, Card, ListRow, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useQueueSummary, useRecords } from '@/data/hooks';
import { companyStorage } from '@/features/capture';
import { useMe } from '@/features/inspection';
import { LOCKED_FOOTER } from '@/lib/constants';
import { COMPANY_STATUS_LABEL, expiryState, INSPECTOR_STATUS_LABEL } from '@/lib/gates';
import { space } from '@/theme/tokens';

export default function AccountScreen() {
  const { app, store, profile, inspector, company, companyId, qualifications, today } = useMe();
  const persons = useRecords('person', (p) => p.client_account_id === companyId);
  const companies = store.list('company').length;
  const meter = companyId ? companyStorage(store, companyId) : null;
  const consents = useRecords('consent');
  const { summary } = useQueueSummary();
  const alerts = qualifications.filter((q) => ['due_60', 'due_30', 'due_7', 'expired'].includes(expiryState(q.expires_on, today))).length;
  const given = consents.filter((c) => c.granted).length;

  return (
    <View style={{ flex: 1 }}>
      <BrandBar title="Account" />
      <Screen edges={[]}>
        <Card>
          <Txt variant="bodyStrong">{profile?.displayName ?? ''}</Txt>
          <Txt variant="small" muted>
            {app.auth?.email ?? ''}
          </Txt>
          <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
            <Pill label={app.mode === 'demo' ? 'Demo mode' : 'Live'} tone={app.mode === 'demo' ? 'warning' : 'success'} />
            <Pill label={`Inspector ${inspector ? INSPECTOR_STATUS_LABEL[inspector.status] : 'Identity'}`} tone={inspector?.status === 'cleared' ? 'success' : 'warning'} />
          </View>
        </Card>

        <SectionTitle>Organisation</SectionTitle>
        <Card style={{ paddingVertical: 0 }}>
          <ListRow icon="domain" title="Organisation profile" subtitle={company ? `${company.legal_name} · ${COMPANY_STATUS_LABEL[company.onboarding_status]}` : 'Not started'} onPress={() => router.push('/account/organisation')} />
          <ListRow icon="account-tie-outline" title="Authorised persons" subtitle={`${persons.length} people with 16(1), 16(2) and health and safety roles`} onPress={() => router.push('/account/persons')} />
          <ListRow icon="swap-horizontal" title="Companies" subtitle={`${companies} on this phone · switch or search`} onPress={() => router.push('/switcher')} />
          <ListRow icon="domain-plus" title="Register a company" subtitle="Company, then places, then people" onPress={() => router.push('/register')} />
          <ListRow icon="folder-image" title="Evidence and storage" subtitle={meter ? meter.text : 'Photos and voice notes'} onPress={() => router.navigate('/evidence')} />
        </Card>

        <SectionTitle>You as inspector</SectionTitle>
        <Card style={{ paddingVertical: 0 }}>
          <ListRow icon="shield-account-outline" title="Inspector status" subtitle="Identity, FICA, Qualifications, Competence review" onPress={() => router.push('/account/inspector')} />
          <ListRow icon="certificate-outline" title="Qualifications and registrations" subtitle={alerts ? `${alerts} need attention` : `${qualifications.length} on record`} onPress={() => router.push('/account/qualifications')} />
          <ListRow icon="hand-okay" title="POPIA consents" subtitle={`${given} of ${consents.length || 7} purposes given`} onPress={() => router.push('/account/consents')} />
          <ListRow icon="lock-outline" title="Security" subtitle="MFA, step up and fingerprint or face unlock" onPress={() => router.push('/account/security')} />
        </Card>

        <SectionTitle>This phone</SectionTitle>
        <Card style={{ paddingVertical: 0 }}>
          <ListRow icon="cloud-sync-outline" title="Sync" subtitle={summary.total ? `${summary.total} waiting or to check` : 'Everything is synced'} onPress={() => router.push('/sync')} />
          {app.mode === 'demo' ? <ListRow icon="tune-variant" title="Demo controls" subtitle="Switch statuses to see every gate" onPress={() => router.push('/account/demo')} /> : null}
        </Card>

        <Button title="Sign out" kind="secondary" icon="logout" onPress={app.signOut} />
        <Txt variant="tiny" muted style={{ textAlign: 'center' }}>
          {`Bee-Inspect ${Constants.expoConfig?.version ?? ''}. Health and safety inspection data only; no medical results.`}
        </Txt>
        <Txt variant="tiny" muted style={{ textAlign: 'center' }}>
          {LOCKED_FOOTER}
        </Txt>
      </Screen>
    </View>
  );
}
