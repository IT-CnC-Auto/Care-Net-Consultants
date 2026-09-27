// Organisation profile (decisions section 2; prompt B4 company onboarding).
// Pre filled from the free File's company. Saved on the phone and queued; the
// server function that accepts it is still to come (account-update, stub).

import { useState } from 'react';

import { Button, Card, Field, Heading, KeyValue, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useMe } from '@/features/inspection';
import { COMPANY_STATUS_LABEL } from '@/lib/gates';

export default function OrganisationScreen() {
  const { store, company } = useMe();
  const [legal, setLegal] = useState(company?.legal_name ?? '');
  const [trading, setTrading] = useState(company?.trading_name ?? '');
  const [reg, setReg] = useState(company?.registration_number ?? '');
  const [popia, setPopia] = useState(company?.popia_contact ?? '');
  const [saved, setSaved] = useState(false);
  if (!company) return <Screen><Notice tone="info">No company on this account yet.</Notice></Screen>;
  const statusTone = company.onboarding_status === 'active' ? 'success' : company.onboarding_status === 'blocked' ? 'danger' : 'warning';

  return (
    <Screen>
      <Heading>Organisation profile</Heading>
      <Card>
        <KeyValue label="Onboarding" value={COMPANY_STATUS_LABEL[company.onboarding_status]} />
        <Pill label={company.onboarding_status === 'active' ? 'Start Inspection is open for this company' : 'Start Inspection opens once the company is Active'} tone={statusTone} />
        <KeyValue label="FICA pack" value={company.fica_status === 'accepted' ? 'Accepted' : company.fica_status === 'submitted' ? 'In review' : company.fica_status === 'rejected' ? 'Rejected' : 'Not submitted'} />
        <KeyValue label="CIPC" value={company.cipc_status === 'in_business' ? 'In business' : company.cipc_status ? company.cipc_status.replace(/_/g, ' ') : 'Not checked'} />
      </Card>
      <SectionTitle>Details</SectionTitle>
      <Field label="Legal name" value={legal} onChangeText={setLegal} />
      <Field label="Trading name" value={trading} onChangeText={setTrading} />
      <Field label="Registration number" value={reg} onChangeText={setReg} />
      <Field label="POPIA contact" hint="The person who handles personal information questions for the company." value={popia} onChangeText={setPopia} />
      <Txt variant="small" muted>
        Section 16(1) and 16(2) people and other health and safety roles are under Authorised persons.
      </Txt>
      {saved ? <Notice tone="success">Saved on this phone. It is sent for review when the server accepts profile changes.</Notice> : null}
      <Button
        title="Save"
        onPress={async () => {
          await store.update('company', company.id, { legal_name: legal.trim(), trading_name: trading.trim() || null, registration_number: reg.trim() || null, popia_contact: popia.trim() || null });
          setSaved(true);
        }}
        disabled={legal.trim().length < 2}
      />
      <SectionTitle>Free Health and Safety File</SectionTitle>
      <Card>
        <Pill label={company.file_eligibility === 'eligible' ? 'Eligible: Issued reports raise Section F' : company.file_eligibility === 'not_eligible' ? 'Not eligible yet: reports are stored, awaiting eligibility' : 'Eligibility not confirmed yet'} tone={company.file_eligibility === 'eligible' ? 'success' : 'warning'} />
        <Txt variant="small" muted>
          A company qualifies for the free digital Safety File as a verified Care Net client with more than 50 medicals in the last 12 months, or as a big site with more than 500. Care Net verifies the count; it is not self declared.
        </Txt>
        {company.file_eligibility_note ? <Txt variant="tiny" muted>{company.file_eligibility_note}</Txt> : null}
      </Card>
    </Screen>
  );
}
