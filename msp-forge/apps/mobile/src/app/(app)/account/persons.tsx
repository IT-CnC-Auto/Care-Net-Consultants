import { router } from 'expo-router';

import { SyncMark } from '@/components/evidence';
import { Button, Card, EmptyState, Heading, Pill, Screen, Txt } from '@/components/ui';
import { useRecords } from '@/data/hooks';
import { formatDate } from '@/lib/dates';
import { PERSON_ROLE_LABEL } from '@/lib/roles';
import { View } from 'react-native';
import { space } from '@/theme/tokens';

export default function PersonsScreen() {
  const persons = useRecords('person').sort((a, b) => a.full_name.localeCompare(b.full_name));
  const has161 = persons.some((p) => p.roles.includes('s16_1'));
  const has162 = persons.some((p) => p.roles.includes('s16_2'));
  return (
    <Screen footer={<Button title="Add a person" icon="account-plus-outline" onPress={() => router.push('/account/person')} />}>
      <Heading>Authorised persons</Heading>
      <Txt muted>The people who carry health and safety duties for the company. One person can hold more than one role.</Txt>
      <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
        <Pill label={has161 ? '16(1) named' : '16(1) missing'} tone={has161 ? 'success' : 'warning'} />
        <Pill label={has162 ? '16(2) named' : '16(2) missing'} tone={has162 ? 'success' : 'warning'} />
      </View>
      {persons.length === 0 ? <EmptyState icon="account-group-outline" title="No authorised persons yet" /> : null}
      {persons.map((p) => (
        <Card key={p.id} onPress={() => router.push({ pathname: '/account/person', params: { id: p.id } })} accessibilityLabel={`Edit ${p.full_name}`}>
          <Txt variant="bodyStrong">{p.full_name}</Txt>
          <Txt variant="small" muted>
            {p.roles.map((r) => PERSON_ROLE_LABEL[r]).join(' · ')}
          </Txt>
          {p.appointed_on ? <Txt variant="tiny" muted>{`Appointed ${formatDate(p.appointed_on)}`}</Txt> : null}
          <SyncMark recordId={p.id} />
        </Card>
      ))}
    </Screen>
  );
}
