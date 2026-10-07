// Qualifications (with certificate upload and expiry) and professional
// registrations (decisions section 2; prompt B4). Expiry alerts at 60, 30 and
// 7 days; an expired qualification makes the inspector Restricted. Care Net
// verifies each certificate; the phone never marks one verified itself.

import * as DocumentPicker from 'expo-document-picker';
import * as ImagePicker from 'expo-image-picker';
import { useState } from 'react';
import { View } from 'react-native';

import { SyncMark } from '@/components/evidence';
import { Button, Card, Field, Heading, Notice, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { keepFile } from '@/features/evidence';
import { useMe } from '@/features/inspection';
import { useRecords } from '@/data/hooks';
import { formatDate, parseSaDate } from '@/lib/dates';
import { expiryState, expiryText, type ExpiryState } from '@/lib/gates';
import { space } from '@/theme/tokens';

const tone = (s: ExpiryState) => (s === 'expired' || s === 'due_7' ? 'danger' : s === 'due_30' || s === 'due_60' ? 'warning' : 'success');
const STATUS_TEXT = { pending: 'Awaiting verification', verified: 'Verified', rejected: 'Rejected', expired: 'Expired' } as const;

export default function QualificationsScreen() {
  const { store, today } = useMe();
  const quals = useRecords('qualification').sort((a, b) => (a.expires_on ?? '9999').localeCompare(b.expires_on ?? '9999'));
  const regs = useRecords('registration');
  const [adding, setAdding] = useState<'qual' | 'reg' | null>(null);
  const [f, setF] = useState({ type: '', issuer: '', number: '', issued: '', expires: '', category: '' });
  const [doc, setDoc] = useState<{ uri: string; name: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const set = (k: keyof typeof f) => (v: string) => setF((s) => ({ ...s, [k]: v }));

  const pickDocument = async () => {
    const r = await DocumentPicker.getDocumentAsync({ type: ['application/pdf', 'image/jpeg', 'image/png'], copyToCacheDirectory: true });
    if (!r.canceled && r.assets?.[0]) setDoc({ uri: r.assets[0].uri, name: r.assets[0].name });
  };
  const photographDocument = async () => {
    const perm = await ImagePicker.requestCameraPermissionsAsync();
    if (!perm.granted) return setError('Allow the camera to photograph the certificate.');
    const r = await ImagePicker.launchCameraAsync({ mediaTypes: ['images'], quality: 0.8 });
    if (!r.canceled && r.assets?.[0]) setDoc({ uri: r.assets[0].uri, name: r.assets[0].fileName ?? 'certificate.jpg' });
  };

  const save = async () => {
    setError(null);
    const issued = f.issued.trim() ? parseSaDate(f.issued) : null;
    const expires = f.expires.trim() ? parseSaDate(f.expires) : null;
    if ((f.issued.trim() && !issued) || (f.expires.trim() && !expires)) return setError('Give dates as dd/mm/yyyy.');
    if (issued && expires && expires <= issued) return setError('The expiry date must be after the issue date.');
    if (adding === 'qual') {
      if (f.type.trim().length < 2 || f.issuer.trim().length < 2 || !f.number.trim()) return setError('Give the qualification, the issuer and the number.');
      const id = store.id();
      const localUri = doc ? await keepFile(doc.uri, 'qualifications', `${id}-${doc.name.replace(/[^A-Za-z0-9._-]/g, '_')}`) : null;
      await store.create('qualification', { id, qual_type: f.type.trim(), issuer: f.issuer.trim(), number: f.number.trim(), issued_on: issued, expires_on: expires, status: 'pending', document_name: doc?.name ?? null, _local_uri: localUri });
    } else {
      if (f.type.trim().length < 2 || !f.number.trim()) return setError('Give the registration body and number.');
      await store.create('registration', { id: store.id(), body: f.type.trim(), number: f.number.trim(), category: f.category.trim() || null, expires_on: expires });
    }
    setAdding(null);
    setDoc(null);
    setF({ type: '', issuer: '', number: '', issued: '', expires: '', category: '' });
  };

  return (
    <Screen>
      <Heading>Qualifications</Heading>
      <Txt muted>Care Net checks each certificate before it counts. An expired qualification makes your status Restricted until it is renewed.</Txt>
      {quals.map((q) => {
        const s = expiryState(q.expires_on, today);
        return (
          <Card key={q.id}>
            <Txt variant="bodyStrong">{q.qual_type}</Txt>
            <Txt variant="small" muted>
              {`${q.issuer} · ${q.number}`}
            </Txt>
            <Txt variant="tiny" muted>
              {`Issued ${formatDate(q.issued_on) || 'not given'} · Expires ${formatDate(q.expires_on) || 'no expiry'}${q.document_name ? ` · Certificate ${q.document_name}` : ' · No certificate yet'}`}
            </Txt>
            <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
              <Pill label={STATUS_TEXT[q.status]} tone={q.status === 'verified' ? 'success' : q.status === 'pending' ? 'neutral' : 'danger'} />
              <Pill label={expiryText(s)} tone={tone(s)} />
              <SyncMark recordId={q.id} />
            </View>
          </Card>
        );
      })}
      {adding !== 'qual' ? <Button title="Add a qualification" icon="plus" kind="secondary" onPress={() => setAdding('qual')} /> : null}

      <SectionTitle>Professional registrations</SectionTitle>
      {regs.map((r) => {
        const s = expiryState(r.expires_on, today);
        return (
          <Card key={r.id}>
            <Txt variant="bodyStrong">{r.body}</Txt>
            <Txt variant="small" muted>
              {`${r.number}${r.category ? ` · ${r.category}` : ''}`}
            </Txt>
            <Pill label={r.expires_on ? `${expiryText(s)} (${formatDate(r.expires_on)})` : 'No expiry date'} tone={tone(s)} />
          </Card>
        );
      })}
      {adding !== 'reg' ? <Button title="Add a registration" icon="plus" kind="secondary" onPress={() => setAdding('reg')} /> : null}

      {adding ? (
        <Card>
          <Txt variant="bodyStrong">{adding === 'qual' ? 'New qualification' : 'New registration'}</Txt>
          <Field label={adding === 'qual' ? 'Qualification' : 'Registration body'} value={f.type} onChangeText={set('type')} placeholder={adding === 'qual' ? 'For example Construction Health and Safety Officer' : 'For example SACPCMP'} />
          {adding === 'qual' ? <Field label="Issuer" value={f.issuer} onChangeText={set('issuer')} /> : <Field label="Category (optional)" value={f.category} onChangeText={set('category')} />}
          <Field label="Number" value={f.number} onChangeText={set('number')} />
          {adding === 'qual' ? <Field label="Issued on (dd/mm/yyyy)" value={f.issued} onChangeText={set('issued')} /> : null}
          <Field label="Expires on (dd/mm/yyyy)" value={f.expires} onChangeText={set('expires')} />
          {adding === 'qual' ? (
            <>
              <Txt variant="smallStrong">Certificate</Txt>
              {doc ? <Pill label={doc.name} tone="info" /> : null}
              <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
                <Button title="Choose a file" icon="file-upload-outline" kind="secondary" compact onPress={pickDocument} />
                <Button title="Photograph it" icon="camera-outline" kind="ghost" compact onPress={photographDocument} />
              </View>
              <Txt variant="tiny" muted>
                PDF, JPEG or PNG. Reading the details from the certificate automatically comes later; type them for now.
              </Txt>
            </>
          ) : null}
          {error ? <Notice tone="danger">{error}</Notice> : null}
          <View style={{ flexDirection: 'row', gap: space.sm }}>
            <Button title="Save" onPress={save} />
            <Button title="Cancel" kind="ghost" onPress={() => { setAdding(null); setError(null); }} />
          </View>
        </Card>
      ) : null}
    </Screen>
  );
}
