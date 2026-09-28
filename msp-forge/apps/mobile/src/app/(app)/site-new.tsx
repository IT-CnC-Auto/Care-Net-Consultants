// Add tagged equipment (QR code or barcode, or typed) at a place. Places
// themselves are added with the place editor (place/edit.tsx).

import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';

import { Button, Chip, ChipRow, Field, Heading, Notice, Screen, Txt } from '@/components/ui';
import { useStore } from '@/data/hooks';
import { haptic } from '@/features/haptics';
import { useMe } from '@/features/inspection';
import { usePlaces } from '@/features/places';
import { onScan } from '@/features/scan-bus';

export default function NewEquipmentScreen() {
  const { parentId } = useLocalSearchParams<{ kind?: string; parentId?: string }>();
  const store = useStore();
  const { companyId } = useMe();
  const tree = usePlaces(companyId);
  const [siteId, setSiteId] = useState<string | null>(parentId || tree.roots[0]?.id || null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [tag, setTag] = useState('');
  const [serial, setSerial] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => onScan((data) => setTag(data.trim())), []);

  const save = async () => {
    setError(null);
    try {
      if (!companyId) throw new Error('Choose a company first.');
      if (!/^[A-Za-z0-9._:/-]{3,120}$/.test(tag.trim())) throw new Error('A tag is 3 to 120 letters, digits or . _ : / -');
      if (store.list('equipment').some((e) => e.client_account_id === companyId && e.tag_code === tag.trim())) throw new Error('That tag is already on this company.');
      if (name.trim().length < 2) throw new Error('Say what kind of equipment it is.');
      await store.create('equipment', { id: store.id(), client_account_id: companyId, site_id: siteId, tag_code: tag.trim(), kind: name.trim(), description: description.trim() || null, serial_number: serial.trim() || null });
      haptic.success();
      router.back();
    } catch (e) {
      haptic.warn();
      setError(e instanceof Error ? e.message : 'It could not be saved.');
    }
  };

  return (
    <Screen footer={<Button title="Save" onPress={save} />}>
      <Heading>Add tagged equipment</Heading>
      <Txt variant="small" muted>
        Saved on this phone straight away, and synced when there is signal.
      </Txt>
      {tree.roots.length > 1 ? (
        <ChipRow>
          {tree.roots.map((r) => (
            <Chip key={r.id} label={r.name} selected={siteId === r.id} onPress={() => setSiteId(r.id)} />
          ))}
        </ChipRow>
      ) : null}
      <Field label="Tag code" value={tag} onChangeText={setTag} autoCapitalize="characters" placeholder="For example FE-021" />
      <Button title="Scan the tag" icon="barcode-scan" kind="secondary" onPress={() => router.push('/scan')} />
      <Field label="Kind of equipment" value={name} onChangeText={setName} placeholder="For example aluminium step ladder" />
      <Field label="Description (optional)" value={description} onChangeText={setDescription} />
      <Field label="Serial number (optional)" value={serial} onChangeText={setSerial} />
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </Screen>
  );
}
