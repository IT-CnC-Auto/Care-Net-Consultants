import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';

import { Button, Chip, ChipRow, Field, Heading, Notice, Screen, Txt } from '@/components/ui';
import { useStore } from '@/data/hooks';
import { onScan } from '@/features/scan-bus';
import { useMe } from '@/features/inspection';
import { DEPARTMENTS } from '@/lib/constants';

type NewKind = 'site' | 'department' | 'building' | 'room' | 'equipment';

const TITLES: Record<NewKind, string> = {
  site: 'Add a site or factory',
  department: 'Add a department',
  building: 'Add a building or zone',
  room: 'Add a room or area',
  equipment: 'Add tagged equipment',
};

export default function NewSiteNodeScreen() {
  const { kind, parentId } = useLocalSearchParams<{ kind: NewKind; parentId?: string }>();
  const store = useStore();
  const { profile } = useMe();
  const [name, setName] = useState('');
  const [address, setAddress] = useState('');
  const [code, setCode] = useState<string | null>(null);
  const [sub, setSub] = useState<'building' | 'zone' | 'room' | 'area'>(kind === 'room' ? 'room' : 'building');
  const [tag, setTag] = useState('');
  const [serial, setSerial] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => onScan((data) => setTag(data.trim())), []);

  const save = async () => {
    setError(null);
    if (!profile) return;
    const id = store.id();
    try {
      if (kind === 'site') {
        if (!name.trim()) throw new Error('Name the site.');
        await store.create('site', { id, client_account_id: profile.companyId, name: name.trim(), address: address.trim() || null });
      } else if (kind === 'department') {
        if (!name.trim() && !code) throw new Error('Name the department or choose its File department.');
        await store.create('department', { id, site_id: parentId as string, department_code: code, name: name.trim() || DEPARTMENTS.find((d) => d.code === code)?.name || 'Department' });
      } else if (kind === 'building') {
        if (!name.trim()) throw new Error('Name the building or zone.');
        const dept = store.get('department', parentId);
        await store.create('building', { id, site_id: dept?.site_id ?? '', department_id: parentId as string, name: name.trim(), kind: sub === 'zone' ? 'zone' : 'building' });
      } else if (kind === 'room') {
        if (!name.trim()) throw new Error('Name the room or area.');
        const b = store.get('building', parentId);
        await store.create('room', { id, site_id: b?.site_id ?? '', building_id: parentId as string, name: name.trim(), kind: sub === 'area' ? 'area' : 'room' });
      } else if (kind === 'equipment') {
        if (!/^[A-Za-z0-9._:/-]{3,120}$/.test(tag.trim())) throw new Error('A tag is 3 to 120 letters, digits or . _ : / -');
        if (store.list('equipment').some((e) => e.tag_code === tag.trim())) throw new Error('That tag is already on this company.');
        if (name.trim().length < 2) throw new Error('Say what kind of equipment it is.');
        await store.create('equipment', { id, client_account_id: profile.companyId, site_id: parentId || null, tag_code: tag.trim(), kind: name.trim(), description: address.trim() || null, serial_number: serial.trim() || null });
      }
      router.back();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'It could not be saved.');
    }
  };

  return (
    <Screen>
      <Heading>{TITLES[kind] ?? 'Add'}</Heading>
      <Txt variant="small" muted>
        Saved on this phone straight away, and synced when there is signal.
      </Txt>
      {kind === 'equipment' ? (
        <>
          <Field label="Tag code" value={tag} onChangeText={setTag} autoCapitalize="characters" placeholder="For example DEMO-LAD-004" />
          <Button title="Scan the tag" icon="barcode-scan" kind="secondary" onPress={() => router.push('/scan')} />
          <Field label="Kind of equipment" value={name} onChangeText={setName} placeholder="For example aluminium step ladder" />
          <Field label="Description (optional)" value={address} onChangeText={setAddress} />
          <Field label="Serial number (optional)" value={serial} onChangeText={setSerial} />
        </>
      ) : (
        <>
          {kind === 'department' ? (
            <>
              <Txt variant="smallStrong">File department</Txt>
              <ChipRow>
                {DEPARTMENTS.map((d) => (
                  <Chip key={d.code} label={d.name} selected={code === d.code} onPress={() => setCode(code === d.code ? null : d.code)} />
                ))}
              </ChipRow>
            </>
          ) : null}
          {kind === 'building' ? (
            <ChipRow>
              <Chip label="Building" selected={sub === 'building'} onPress={() => setSub('building')} />
              <Chip label="Zone" selected={sub === 'zone'} onPress={() => setSub('zone')} />
            </ChipRow>
          ) : null}
          {kind === 'room' ? (
            <ChipRow>
              <Chip label="Room" selected={sub === 'room'} onPress={() => setSub('room')} />
              <Chip label="Area" selected={sub === 'area'} onPress={() => setSub('area')} />
            </ChipRow>
          ) : null}
          <Field label="Name" value={name} onChangeText={setName} />
          {kind === 'site' ? <Field label="Address (optional)" value={address} onChangeText={setAddress} /> : null}
        </>
      )}
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <Button title="Save" onPress={save} />
    </Screen>
  );
}
