import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';

import { Button, Chip, ChipRow, Field, Heading, Notice, Screen, Txt } from '@/components/ui';
import { useMe } from '@/features/inspection';
import { formatDate, parseSaDate } from '@/lib/dates';
import { PERSON_ROLE_LABEL, PERSON_ROLES } from '@/lib/roles';
import type { PersonRole } from '@/lib/types';

export default function PersonScreen() {
  const { id } = useLocalSearchParams<{ id?: string }>();
  const { store, companyId } = useMe();
  const existing = id ? store.get('person', id) : undefined;
  const [name, setName] = useState(existing?.full_name ?? '');
  const [roles, setRoles] = useState<PersonRole[]>(existing?.roles ?? []);
  const [email, setEmail] = useState(existing?.email ?? '');
  const [mobile, setMobile] = useState(existing?.mobile ?? '');
  const [appointed, setAppointed] = useState(existing?.appointed_on ? formatDate(existing.appointed_on) : '');
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    if (name.trim().length < 2) return setError('Give the full name.');
    if (roles.length === 0) return setError('Choose at least one role.');
    const appointedOn = appointed.trim() ? parseSaDate(appointed) : null;
    if (appointed.trim() && !appointedOn) return setError('Give the appointment date as dd/mm/yyyy.');
    const rec = { full_name: name.trim(), roles, email: email.trim() || null, mobile: mobile.trim() || null, appointed_on: appointedOn };
    if (existing) await store.update('person', existing.id, rec);
    else await store.create('person', { id: store.id(), client_account_id: companyId ?? '', ...rec });
    router.back();
  };

  return (
    <Screen>
      <Heading>{existing ? 'Edit authorised person' : 'Add an authorised person'}</Heading>
      <Field label="Full name" value={name} onChangeText={setName} />
      <Txt variant="smallStrong">Roles</Txt>
      <ChipRow>
        {PERSON_ROLES.map((r) => (
          <Chip key={r} label={PERSON_ROLE_LABEL[r]} selected={roles.includes(r)} onPress={() => setRoles((rs) => (rs.includes(r) ? rs.filter((x) => x !== r) : [...rs, r]))} />
        ))}
      </ChipRow>
      <Field label="Email (optional)" value={email} onChangeText={setEmail} keyboardType="email-address" autoCapitalize="none" />
      <Field label="Mobile (optional)" value={mobile} onChangeText={setMobile} keyboardType="phone-pad" />
      <Field label="Appointed on (dd/mm/yyyy, optional)" value={appointed} onChangeText={setAppointed} />
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <Button title="Save" onPress={save} />
    </Screen>
  );
}
