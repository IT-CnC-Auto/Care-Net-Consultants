// The report draft, with the AI Wallet rules (decision 1.3): the remaining
// balance is shown before every AI run, then the cost estimate; a warning when
// the estimate is more than the balance; a confirmation; then the draft. Rand
// only. Every draft carries "Assistive draft. Competent person sign off required."

import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { View } from 'react-native';

import { NotConnectedError } from '@/backend/types';
import { DraftLabel, ReportView } from '@/components/report-view';
import { Button, Card, Heading, KeyValue, Notice, Screen, Txt } from '@/components/ui';
import { useInspection, useMe } from '@/features/inspection';
import { DRAFT_LABEL } from '@/lib/constants';
import { missingText } from '@/lib/gates';
import { formatRand } from '@/lib/money';
import { AI_OUTPUT_TOKENS, buildDraftSkeleton, estimateTokensIn } from '@/lib/report';
import { balanceFromLedger, estimateView, type EstimateResult } from '@/lib/wallet';
import { space } from '@/theme/tokens';

export default function DraftScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const x = useInspection(id);
  const { app, profile } = useMe();
  const [busy, setBusy] = useState<'template' | 'estimate' | 'ai' | null>(null);
  const [est, setEst] = useState<EstimateResult | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!x.inspection || !profile || !app.backend) return <Screen><Notice tone="warning">This inspection is not on this phone.</Notice></Screen>;
  const { inspection, violations, report, store } = x;
  const backend = app.backend;
  const walletId = profile.walletId;
  const ledger = store.where('ledger', (l) => l.wallet_id === walletId).map((l) => ({ ...l, created_at: l.created_at ?? '' }));
  const localBalance = balanceFromLedger(ledger).availableCents;
  const estimate = est ? estimateView(est) : null;
  const blockedBySync = app.mode === 'live' && x.pendingSync > 0;
  const canDraft = violations.length === 0 && !blockedBySync && report?.status !== 'issued' && report?.status !== 'awaiting_signoff';

  const fail = (e: unknown) => setError(e instanceof NotConnectedError || e instanceof Error ? e.message : 'Something went wrong.');

  const templateDraft = async () => {
    setError(null);
    setBusy('template');
    try {
      const r = await backend.reportDraft({ inspectionId: inspection.id, useAi: false, walletId, store });
      setNote(r.aiNote);
    } catch (e) {
      fail(e);
    } finally {
      setBusy(null);
    }
  };

  const checkCost = async () => {
    if (!walletId) return setError('There is no AI Wallet on this company yet.');
    setError(null);
    setBusy('estimate');
    try {
      const skeleton = buildDraftSkeleton({ ...x, inspection, template: x.template ?? null, templateItems: x.items });
      const e = await backend.walletEstimate({ walletId, inspectionId: inspection.id, tokensIn: estimateTokensIn(skeleton), tokensOut: AI_OUTPUT_TOKENS, store });
      setEst(e);
      setConfirming(false);
    } catch (e) {
      fail(e);
    } finally {
      setBusy(null);
    }
  };

  const runAi = async () => {
    setError(null);
    setBusy('ai');
    try {
      const r = await backend.reportDraft({ inspectionId: inspection.id, useAi: true, walletId, store });
      setNote(r.aiNote);
      setEst(null);
      setConfirming(false);
    } catch (e) {
      fail(e);
    } finally {
      setBusy(null);
    }
  };

  return (
    <Screen
      footer={
        report && report.status !== 'issued' ? (
          <Button title={report.status === 'awaiting_signoff' ? 'Open sign off' : 'Go to sign off'} icon="draw-pen" onPress={() => router.push({ pathname: '/inspection/[id]/sign', params: { id: inspection.id } })} />
        ) : undefined
      }>
      <Heading>{report?.status === 'issued' ? 'Issued report' : 'Report draft'}</Heading>

      {violations.length ? (
        <Notice tone="warning" title="Finish the Fail rule first">
          {`${violations.length} Fail item${violations.length > 1 ? 's need' : ' needs'} ${missingText(Array.from(new Set(violations.flatMap((v) => v.missing))))} before a report can be drafted.`}
        </Notice>
      ) : null}
      {blockedBySync ? <Notice tone="info" title="Sync first">{`${x.pendingSync} item${x.pendingSync > 1 ? 's are' : ' is'} still waiting to sync. The server drafts only from what it has, so sync before drafting.`}</Notice> : null}

      {report?.status !== 'issued' ? (
        <>
          {!report ? <DraftLabel label={DRAFT_LABEL} /> : null}
          <Card>
            <Txt variant="bodyStrong">Template draft</Txt>
            <Txt variant="small" muted>
              Built from your capture only. Free, and it works even when the AI Wallet is empty.
            </Txt>
            <Button title={report ? 'Rebuild the template draft' : 'Make the template draft'} kind="secondary" onPress={templateDraft} busy={busy === 'template'} disabled={!canDraft} />
          </Card>

          <Card>
            <Txt variant="bodyStrong">AI assisted draft</Txt>
            <Txt variant="small" muted>
              Drafts the summary and the references for you to review. Paid from the AI Wallet in rand.
            </Txt>
            <KeyValue label="Your balance now" value={formatRand(est ? est.available_cents : localBalance)} />
            {estimate ? (
              <>
                <KeyValue label="Cost estimate" value={estimate.estimate} />
                <KeyValue label="Balance after, about" value={estimate.balanceAfter} />
                {estimate.warning ? <Notice tone="warning">{estimate.warning}</Notice> : null}
                {estimate.canRun ? (
                  confirming ? (
                    <View style={{ gap: space.sm }}>
                      <Txt variant="bodyStrong">{estimate.confirmText}</Txt>
                      <Txt variant="tiny" muted>
                        You pay the actual cost, never more than the estimate plus a quarter. If it costs more than your balance, your balance goes to R0,00 and Care Net carries the rest.
                      </Txt>
                      <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
                        <Button title="Yes, run the AI draft" onPress={runAi} busy={busy === 'ai'} />
                        <Button title="Cancel" kind="ghost" onPress={() => setConfirming(false)} />
                      </View>
                    </View>
                  ) : (
                    <Button title="Run the AI draft" icon="creation" onPress={() => setConfirming(true)} disabled={!canDraft} />
                  )
                ) : (
                  <Button title="Top up the AI Wallet" icon="wallet-plus-outline" kind="secondary" onPress={() => router.push('/wallet')} />
                )}
              </>
            ) : (
              <Button title="Check the cost" icon="calculator-variant-outline" onPress={checkCost} busy={busy === 'estimate'} disabled={!canDraft} />
            )}
          </Card>
        </>
      ) : null}

      {note ? <Notice tone="success">{note}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}
      {report ? <ReportView report={report} /> : <Txt muted>No draft yet.</Txt>}
    </Screen>
  );
}
