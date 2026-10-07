// Sign off (prompt B7). Cleared for the scope: sign in the app after step up.
// Not cleared: find a competent person on Bee-Matched (WhatsApp fallback).
// A report becomes Issued only after the signature; an Issued report files into
// Section F of the free File when the company is eligible (contract 16.8),
// otherwise it is stored, awaiting eligibility.

import * as Linking from 'expo-linking';
import { router, useLocalSearchParams } from 'expo-router';
import * as WebBrowser from 'expo-web-browser';
import { useState } from 'react';
import { View } from 'react-native';

import { NotConnectedError } from '@/backend/types';
import { SignaturePad } from '@/components/signature-pad';
import { Button, Card, Chip, Field, Heading, Notice, Pill, Screen, Txt } from '@/components/ui';
import { useInspection, useMe } from '@/features/inspection';
import { useNow } from '@/features/use-now';
import { BEE_MATCHED_URL, whatsappUrl, WHATSAPP_DISPLAY } from '@/lib/constants';
import { formatDate, plural } from '@/lib/dates';
import { canIssue, signerCleared } from '@/lib/gates';
import { voicePreviewLine } from '@/lib/report';
import { isStepUpValid, stepUpMinutesLeft } from '@/lib/step-up';
import { space } from '@/theme/tokens';

export default function SignScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const x = useInspection(id);
  const { app, profile, inspector, company, qualifications, today } = useMe();
  const [reviewedPhotos, setReviewedPhotos] = useState(false);
  const [reviewedVoice, setReviewedVoice] = useState(false);
  const [signature, setSignature] = useState('');
  const [name, setName] = useState(profile?.displayName ?? '');
  const [busy, setBusy] = useState(false);
  const [filing, setFiling] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const now = useNow();

  const report = x.report;
  if (!x.inspection || !profile || !app.backend) return <Screen><Notice tone="warning">This inspection is not on this phone.</Notice></Screen>;
  if (!report) {
    return (
      <Screen>
        <Notice tone="info">Make a draft first. Sign off needs a draft to sign.</Notice>
        <Button title="Open the draft" onPress={() => router.replace({ pathname: '/inspection/[id]/draft', params: { id: x.inspection!.id } })} />
      </Screen>
    );
  }
  const backend = app.backend;
  const category = x.template?.category ?? null;
  const cleared = signerCleared(inspector?.status, inspector?.competence_scope ?? [], category, qualifications, today);
  const stepUpOk = isStepUpValid(app.lastStepUpAt, now);
  const gate = canIssue({
    inspectorStatus: inspector?.status,
    scope: inspector?.competence_scope ?? [],
    category,
    qualifications,
    identityDone: !!inspector?.identity_done,
    ficaDone: !!inspector?.fica_done,
    deviceRooted: app.deviceRooted,
    stepUpValid: stepUpOk,
    today,
  });
  const voice = report.content.voice_notes;
  const strictBlocks = x.inspection.voice_note_policy === 'strict' && voice.missing > 0;
  const ready = gate.ok && reviewedPhotos && reviewedVoice && signature.length > 0 && name.trim().length >= 3 && !strictBlocks;

  if (report.status === 'issued') {
    const filed = report.file_link_status === 'linked' || report.file_link_status === 'section_only';
    return (
      <Screen>
        <Heading>Issued</Heading>
        <Notice tone="success" title="The report is Issued">{`Signed by ${report.signed_by} on ${formatDate(report.signed_at)}.`}</Notice>
        {filing ? <Notice tone={filed ? 'success' : 'warning'}>{filing}</Notice> : null}
        <Card>
          <Txt variant="bodyStrong">Free Health and Safety File</Txt>
          <Pill label={filed ? `In Section F, register ${report.section_f_element_code ?? ''}` : 'Stored, awaiting eligibility'} tone={filed ? 'success' : 'warning'} />
          <Txt variant="small" muted>
            {filed
              ? 'Issued reports file into Section F (Registers and inspections) of the free File, and the File figure is updated.'
              : 'The company is not yet confirmed as eligible for the free digital Safety File. The report is stored and listed in Section F, and is filed when eligibility is confirmed.'}
          </Txt>
        </Card>
        <Button title="Back to home" onPress={() => router.dismissAll()} />
      </Screen>
    );
  }

  const stepUp = (purpose: 'signoff' | 'bee_matched') => router.push({ pathname: '/step-up', params: { purpose } });

  const sign = async () => {
    setError(null);
    setBusy(true);
    try {
      const r = await backend.signAndIssue({ reportId: report.id, signerName: name.trim(), signaturePath: signature, reviewedPhotos, reviewedVoiceNotes: reviewedVoice, store: x.store });
      setFiling(r.filing);
    } catch (e) {
      setError(e instanceof NotConnectedError ? e.message : e instanceof Error ? e.message : 'Signing did not work.');
    } finally {
      setBusy(false);
    }
  };

  const requestReview = async () => {
    setError(null);
    if (!stepUpOk) return stepUp('bee_matched');
    try {
      await backend.requestReview({ reportId: report.id, store: x.store });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The request could not be recorded.');
    }
  };

  return (
    <Screen>
      <Heading>Sign off</Heading>
      <Card>
        <Txt variant="bodyStrong">{x.inspection.title}</Txt>
        <Txt variant="small" muted>
          {report.source === 'ai_assistive' ? 'AI assisted draft' : 'Template draft'}, version {report.version}. {voicePreviewLine(voice)}.
        </Txt>
        <Pill label={report.status === 'awaiting_signoff' ? 'Awaiting sign off' : 'Draft'} tone="warning" />
      </Card>
      {app.deviceRooted ? <Notice tone="danger" title="Issue is blocked on this phone">This phone looks rooted or jailbroken. Sign on another phone, or ask a competent person to sign.</Notice> : null}
      {strictBlocks ? <Notice tone="danger">{`Strict policy: ${voice.missing} voice note${voice.missing > 1 ? 's are' : ' is'} not accounted for. Sync, then rebuild the draft.`}</Notice> : null}

      {!cleared ? (
        <Card>
          <Txt variant="bodyStrong">Find a competent person</Txt>
          <Txt variant="small" muted>
            {`You are not cleared to sign ${category ?? 'this kind of'} inspections. A cleared competent person reviews the photos and voice notes and signs. Until then the report stays a draft.`}
          </Txt>
          <Button title="Find a competent person on Bee-Matched" icon="account-search-outline" onPress={() => WebBrowser.openBrowserAsync(BEE_MATCHED_URL)} />
          <Button title={`WhatsApp a sales executive (${WHATSAPP_DISPLAY})`} icon="whatsapp" kind="secondary" onPress={() => Linking.openURL(whatsappUrl(`Hello Care Net, I need a competent person to review and sign a Bee-Inspect report: ${x.inspection!.title}.`))} />
          {report.status === 'draft' ? <Button title="Mark as awaiting sign off" kind="ghost" onPress={requestReview} /> : <Pill label="Awaiting a competent person" tone="warning" />}
        </Card>
      ) : (
        <>
          <Card>
            <Txt variant="bodyStrong">1. Review the evidence</Txt>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
              <Chip label={`${reviewedPhotos ? '✓ ' : ''}I reviewed all ${plural(x.photos.length, 'photo')}`} selected={reviewedPhotos} onPress={() => setReviewedPhotos((v) => !v)} />
              <Chip label={`${reviewedVoice ? '✓ ' : ''}I checked all ${plural(x.voiceNotes.length, 'voice note')}`} selected={reviewedVoice} onPress={() => setReviewedVoice((v) => !v)} />
            </View>
          </Card>
          <Card>
            <Txt variant="bodyStrong">2. Confirm it is you</Txt>
            {stepUpOk ? (
              <Pill label={`Confirmed, valid ${stepUpMinutesLeft(app.lastStepUpAt, now)} more minutes`} tone="success" />
            ) : (
              <Button title="Confirm with my authenticator code" icon="shield-key-outline" kind="secondary" onPress={() => stepUp('signoff')} />
            )}
          </Card>
          <Card>
            <Txt variant="bodyStrong">3. Sign</Txt>
            <Field label="Full name" value={name} onChangeText={setName} />
            <SignaturePad onChange={setSignature} />
          </Card>
          {!gate.ok ? (
            <Notice tone="warning" title="Before you can issue">
              <View style={{ gap: 2 }}>
                {gate.reasons.map((r) => (
                  <Txt key={r} variant="small">
                    • {r}
                  </Txt>
                ))}
              </View>
            </Notice>
          ) : null}
          <Button title="Sign and issue" icon="check-decagram-outline" onPress={sign} busy={busy} disabled={!ready} />
          <Txt variant="tiny" muted>
            Issued only after your signature. Issued reports file into Section F of the free File when the company is eligible; otherwise they are stored, awaiting eligibility.
          </Txt>
        </>
      )}
      {error ? <Notice tone="danger">{error}</Notice> : null}
      {company ? (
        <Txt variant="tiny" muted>
          {company.file_eligibility === 'eligible' ? 'This company is eligible: the Issued report will raise its Section F.' : company.file_eligibility === 'not_eligible' ? 'This company is not yet eligible: the Issued report will be stored, awaiting eligibility.' : 'Eligibility for the free File is checked by the server when the report is Issued.'}
        </Txt>
      ) : null}
    </Screen>
  );
}
