// Demonstration only: switch the fictitious statuses to walk every gate.

import { View } from 'react-native';

import { Button, Card, Chip, Heading, Notice, Screen, SectionTitle, Txt } from '@/components/ui';
import { useMe } from '@/features/inspection';
import { COMPANY_STATUS_LABEL, INSPECTOR_OUTCOMES, INSPECTOR_PATH, INSPECTOR_STATUS_LABEL } from '@/lib/gates';
import { formatRand } from '@/lib/money';
import type { CompanyStatus, FileEligibility } from '@/lib/types';
import { balanceFromLedger } from '@/lib/wallet';
import { space } from '@/theme/tokens';

export default function DemoControlsScreen() {
  const { app, store, profile, inspector, company } = useMe();
  if (app.mode !== 'demo' || !profile) return <Screen><Notice tone="info">Demo controls exist only in demo mode.</Notice></Screen>;
  const walletId = profile.walletId as string;
  const balance = balanceFromLedger(store.where('ledger', (l) => l.wallet_id === walletId).map((l) => ({ ...l, created_at: l.created_at ?? '' }))).availableCents;

  const spendDownTo = async (cents: number) => {
    if (balance <= cents) return;
    const lots = store.where('ledger', (l) => l.wallet_id === walletId && l.amount_cents > 0 && !!l.expires_at);
    let left = balance - cents;
    for (const lot of lots) {
      const used = store.where('ledger', (d) => d.lot_id === lot.id).reduce((s, d) => s + d.amount_cents, 0);
      const take = Math.min(left, lot.amount_cents + used);
      if (take <= 0) continue;
      await store.putServer('ledger', { id: store.id(), wallet_id: walletId, entry_kind: 'charge', amount_cents: -take, lot_id: lot.id, expires_at: null, note: 'Demonstration spend', created_at: new Date().toISOString() });
      left -= take;
      if (left <= 0) break;
    }
  };

  return (
    <Screen>
      <Heading>Demo controls</Heading>
      <Txt muted>Fictitious data only. Change a status to see how each gate behaves.</Txt>
      <SectionTitle>Company onboarding</SectionTitle>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
        {(['not_started', 'in_review', 'active', 'blocked'] as CompanyStatus[]).map((s) => (
          <Chip key={s} label={COMPANY_STATUS_LABEL[s]} selected={company?.onboarding_status === s} onPress={() => company && store.putServer('company', { ...company, onboarding_status: s })} />
        ))}
      </View>
      <SectionTitle>Inspector status</SectionTitle>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
        {[...INSPECTOR_PATH, ...INSPECTOR_OUTCOMES].map((s) => (
          <Chip
            key={s}
            label={INSPECTOR_STATUS_LABEL[s]}
            selected={inspector?.status === s}
            onPress={() => inspector && store.putServer('inspector', { ...inspector, status: s, identity_done: s !== 'identity', fica_done: !['identity', 'fica'].includes(s), restricted_reason: s === 'restricted' ? 'Demonstration: a qualification expired.' : null })}
          />
        ))}
      </View>
      <SectionTitle>Free File eligibility</SectionTitle>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
        {(['eligible', 'not_eligible', 'unknown'] as FileEligibility[]).map((e) => (
          <Chip key={e} label={e === 'eligible' ? 'Eligible' : e === 'not_eligible' ? 'Not eligible' : 'Unknown'} selected={company?.file_eligibility === e} onPress={() => company && store.putServer('company', { ...company, file_eligibility: e })} />
        ))}
      </View>
      <SectionTitle>AI Wallet</SectionTitle>
      <Card>
        <Txt>{`Balance ${formatRand(balance)}`}</Txt>
        <Button title="Spend the demo wallet down to R2,00" kind="secondary" compact onPress={() => spendDownTo(200)} disabled={balance <= 200} />
        <Txt variant="tiny" muted>
          Then check the cost of an AI draft to see the warning when the estimate is more than the balance.
        </Txt>
      </Card>
      <SectionTitle>Start again</SectionTitle>
      <Button title="Reset the demo" kind="danger" onPress={app.resetDemo} />
    </Screen>
  );
}
