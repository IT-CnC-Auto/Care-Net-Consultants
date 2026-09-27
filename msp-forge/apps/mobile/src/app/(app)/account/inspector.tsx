// The inspector status path (prompt B4): Identity, FICA, Qualifications,
// Competence review, then Cleared, Restricted or Assistant only. Dual gate
// before Issue: FICA or KYC, and a qualification.

import { router } from 'expo-router';
import { StyleSheet, View } from 'react-native';

import { Button, Card, Heading, Icon, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useMe } from '@/features/inspection';
import { canStartInspection, expiryState, INSPECTOR_OUTCOMES, INSPECTOR_PATH, INSPECTOR_STATUS_LABEL, pathStepState } from '@/lib/gates';
import { brand, resultTone, space } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

const STEP_TEXT: Record<string, string> = {
  identity: 'SA ID or passport, a liveness check and a verified mobile number.',
  fica: 'Your FICA documents, checked by Care Net.',
  qualifications: 'At least one verified qualification that has not expired.',
  competence_review: 'Care Net reviews your competence scope and declarations.',
};

const OUTCOME_TEXT: Record<string, string> = {
  cleared: 'You may inspect and sign reports within your competence scope.',
  restricted: 'You may capture, but not sign, until the reason is resolved.',
  assistant_only: 'You may capture findings and photos for a cleared inspector.',
};

export default function InspectorStatusScreen() {
  const p = usePalette();
  const { inspector, company, qualifications, today } = useMe();
  const status = inspector?.status ?? 'identity';
  const gate = canStartInspection(company?.onboarding_status, status);
  const expired = qualifications.some((q) => expiryState(q.expires_on, today) === 'expired');

  return (
    <Screen>
      <Heading>Inspector status</Heading>
      <Pill label={INSPECTOR_STATUS_LABEL[status]} tone={status === 'cleared' ? 'success' : status === 'restricted' ? 'danger' : 'warning'} />
      {INSPECTOR_PATH.map((step, i) => {
        const s = pathStepState(status, step);
        return (
          <View key={step} style={styles.step}>
            <View style={[styles.dot, { backgroundColor: s === 'done' ? resultTone.pass.bg : s === 'current' ? brand.gold : p.surfaceAlt, borderColor: p.border }]}>
              {s === 'done' ? <Icon name="check" size={16} color={resultTone.pass.fg} /> : <Txt variant="smallStrong">{String(i + 1)}</Txt>}
            </View>
            <View style={{ flex: 1 }}>
              <Txt variant="bodyStrong">{INSPECTOR_STATUS_LABEL[step]}</Txt>
              <Txt variant="small" muted>
                {STEP_TEXT[step]}
              </Txt>
              <Txt variant="tiny" muted>
                {s === 'done' ? 'Done' : s === 'current' ? 'In progress' : 'Still to do'}
              </Txt>
            </View>
          </View>
        );
      })}
      <SectionTitle>Outcome</SectionTitle>
      {INSPECTOR_OUTCOMES.map((o) => (
        <Card key={o} style={o === status ? { borderColor: brand.deepRed, borderWidth: 2 } : undefined}>
          <Txt variant="bodyStrong">{INSPECTOR_STATUS_LABEL[o]}</Txt>
          <Txt variant="small" muted>
            {OUTCOME_TEXT[o]}
          </Txt>
          {o === status && inspector?.restricted_reason ? <Txt variant="small">{inspector.restricted_reason}</Txt> : null}
        </Card>
      ))}
      {inspector?.competence_scope?.length ? (
        <Card>
          <Txt variant="bodyStrong">Competence scope</Txt>
          <Txt variant="small" muted>
            {inspector.competence_scope.join(', ')}
          </Txt>
        </Card>
      ) : null}
      {expired ? <Notice tone="danger">A qualification has expired. Renew it to stay Cleared.</Notice> : null}
      <Notice tone={gate.ok ? 'success' : 'warning'} title={gate.ok ? 'Start Inspection is open' : 'Start Inspection is closed'}>
        {gate.ok ? 'The company is Active and you are Cleared.' : gate.reasons.join(' ')}
      </Notice>
      <Txt variant="small" muted>
        {"Identity and liveness checks run with Care Net's verification partner once it is connected; until then Care Net checks documents by hand."}
      </Txt>
      <Button title="Qualifications and registrations" kind="secondary" onPress={() => router.push('/account/qualifications')} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  step: { flexDirection: 'row', gap: space.md, alignItems: 'flex-start' },
  dot: { width: 32, height: 32, borderRadius: 16, alignItems: 'center', justifyContent: 'center', borderWidth: 1 },
});
