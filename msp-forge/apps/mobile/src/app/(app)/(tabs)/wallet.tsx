// The AI Wallet: balance, top ups, subsidy notices and the statement. Rand only.
// In app purchase is a labelled stub until the RevenueCat products exist; the
// Ozow web top up is a placeholder until the web desk billing page exists. A
// prior subsidy never blocks a top up (decision 1.3).

import { router } from 'expo-router';
import * as Linking from 'expo-linking';
import { useState } from 'react';
import { View } from 'react-native';

import { BrandBar } from '@/components/brand-bar';
import { Button, Card, Heading, KeyValue, ListRow, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useRecords } from '@/data/hooks';
import { useMe } from '@/features/inspection';
import { WEB_TOPUP_URL, whatsappUrl } from '@/lib/constants';
import { formatDate } from '@/lib/dates';
import { formatRand, TOP_UPS, topUpLabel, topUpNeedsStepUp, VAT_NOTE, type TopUpOption } from '@/lib/money';
import { isStepUpValid } from '@/lib/step-up';
import { balanceFromLedger, ledgerKindText, subsidyText } from '@/lib/wallet';
import { brand, fonts, onInk, space } from '@/theme/tokens';

export default function WalletScreen() {
  const { app, store, profile } = useMe();
  const walletId = profile?.walletId ?? null;
  const ledger = useRecords('ledger', (l) => l.wallet_id === walletId).map((l) => ({ ...l, created_at: l.created_at ?? '' }));
  const subsidies = useRecords('subsidy', (s) => s.wallet_id === walletId).sort((a, b) => (b.created_at ?? '').localeCompare(a.created_at ?? ''));
  const wallet = walletId ? store.get('wallet', walletId) : undefined;
  const balance = balanceFromLedger(ledger);
  const [choice, setChoice] = useState<TopUpOption | null>(null);
  const [message, setMessage] = useState<{ tone: 'success' | 'info' | 'danger'; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const buy = async () => {
    if (!choice || !walletId || !app.backend) return;
    setMessage(null);
    if (topUpNeedsStepUp(choice.priceCents) && !isStepUpValid(app.lastStepUpAt, Date.now())) {
      router.push({ pathname: '/step-up', params: { purpose: 'topup_over_499' } });
      return;
    }
    setBusy(true);
    try {
      const r = await app.backend.topUp({ code: choice.code, store, walletId });
      setMessage({ tone: r.credited ? 'success' : 'info', text: r.message });
      if (r.credited) setChoice(null);
    } catch (e) {
      setMessage({ tone: 'danger', text: e instanceof Error ? e.message : 'The top up did not go through.' });
    } finally {
      setBusy(false);
    }
  };

  const statement = ledger.slice().sort((a, b) => b.created_at.localeCompare(a.created_at));

  return (
    <View style={{ flex: 1 }}>
      <BrandBar title="AI Wallet" />
      <Screen edges={[]}>
        <Card style={{ backgroundColor: brand.ink, borderColor: brand.ink }}>
          <Txt variant="label" color={onInk.muted}>
            Balance
          </Txt>
          <Txt style={{ fontFamily: fonts.heading, fontSize: 48, lineHeight: 52 }} color={brand.white}>
            {formatRand(balance.availableCents)}
          </Txt>
          <Txt variant="small" color={onInk.soft}>
            {`Included ${formatRand(balance.includedCents)} · Purchased ${formatRand(balance.purchasedCents)}`}
          </Txt>
          {balance.nextExpiry ? (
            <Txt variant="tiny" color={onInk.muted}>
              {`Next value expires ${formatDate(balance.nextExpiry)}. Included value rolls over one month; purchased value lasts 12 months.`}
            </Txt>
          ) : null}
          <Txt variant="tiny" color={onInk.muted}>
            {`Amounts exclude VAT (${VAT_NOTE}).`}
          </Txt>
        </Card>
        {wallet?.status === 'frozen' ? <Notice tone="warning">This wallet is paused. Speak to a Care Net sales executive.</Notice> : null}
        <Txt variant="small" muted>
          Capture and template reports always work, even at R0,00. The AI Wallet pays only for AI drafts and AI extras, and you see the cost before each one.
        </Txt>

        <SectionTitle>Top up</SectionTitle>
        <View style={{ gap: space.sm }}>
          {TOP_UPS.map((o) => (
            <Card key={o.code} onPress={() => setChoice(o)} style={choice?.code === o.code ? { borderColor: brand.deepRed, borderWidth: 2 } : undefined} accessibilityLabel={`${topUpLabel(o)}${choice?.code === o.code ? ', chosen' : ''}`}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
                <Txt variant="bodyStrong" style={{ flexGrow: 1 }}>
                  {formatRand(o.priceCents)}
                </Txt>
                {o.valueCents > o.priceCents ? <Pill label={`${formatRand(o.valueCents)} value`} tone="success" /> : null}
              </View>
              {topUpNeedsStepUp(o.priceCents) ? <Pill label="Over R499,00: confirm with your authenticator" tone="neutral" /> : null}
            </Card>
          ))}
        </View>
        {choice ? (
          <Card>
            <Txt variant="bodyStrong">{`Top up ${topUpLabel(choice)}`}</Txt>
            <Button title={app.mode === 'demo' ? 'Buy in the app (demo, no money moves)' : 'Buy in the app'} icon="cart-outline" onPress={buy} busy={busy} />
            {app.mode !== 'demo' ? (
              <Txt variant="tiny" muted>
                In app purchase is not connected yet: the store product ids are pending.
              </Txt>
            ) : null}
          </Card>
        ) : null}
        <Button
          title="Top up on the web (Ozow)"
          icon="web"
          kind="secondary"
          onPress={() => {
            if (WEB_TOPUP_URL) void Linking.openURL(WEB_TOPUP_URL);
            else setMessage({ tone: 'info', text: 'The web top up page (Ozow) is not live yet. Ask a Care Net sales executive to top up meanwhile.' });
          }}
        />
        <Button title="Ask a sales executive" icon="whatsapp" kind="ghost" onPress={() => Linking.openURL(whatsappUrl('Hello Care Net, I would like to top up my Bee-Inspect AI Wallet.'))} />
        {message ? <Notice tone={message.tone}>{message.text}</Notice> : null}
        <ListRow title="Automatic top up" subtitle="Adds R99,00 when the balance drops below R20,00. Needs a saved card, which is not connected yet." right={<Pill label={wallet?.auto_topup_enabled ? 'On' : 'Off'} tone="neutral" />} />

        {subsidies.length ? (
          <>
            <SectionTitle>Subsidy notices</SectionTitle>
            {subsidies.map((s) => (
              <Notice key={s.id} tone="info" title={formatDate(s.created_at)}>
                {subsidyText({ id: s.id, created_at: s.created_at ?? '', shortfall_cents: s.shortfall_cents, what: s.what })}
              </Notice>
            ))}
          </>
        ) : null}

        <SectionTitle>Statement</SectionTitle>
        <Card style={{ paddingVertical: 0 }}>
          {statement.length === 0 ? <Txt muted>No entries yet.</Txt> : null}
          {statement.map((l) => (
            <View key={l.id} style={{ paddingVertical: space.sm, gap: 2 }}>
              <KeyValue label={`${formatDate(l.created_at)} · ${ledgerKindText(l.entry_kind)}`} value={formatRand(l.amount_cents)} />
              {l.note ? (
                <Txt variant="tiny" muted>
                  {l.note}
                </Txt>
              ) : null}
            </View>
          ))}
        </Card>
        <Heading level={3}>How AI costs work</Heading>
        <Txt variant="small" muted>
          Before each AI action you see your balance and the cost estimate in rand. You pay the actual cost, and never more than the estimate plus a quarter. If an action costs more than your balance, the balance goes to R0,00 and Care Net carries the rest. You can top up at any time.
        </Txt>
      </Screen>
    </View>
  );
}
