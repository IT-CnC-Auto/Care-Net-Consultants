// The sites tree: Company, Site, Department, Building or Zone, Room or Area.
// Everything can be created offline; it syncs when there is signal.

import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { BrandBar } from '@/components/brand-bar';
import { SyncMark } from '@/components/evidence';
import { Button, Card, EmptyState, Icon, Pill, Screen, SectionTitle, Txt } from '@/components/ui';
import { useRecords } from '@/data/hooks';
import { useMe } from '@/features/inspection';
import { COMPANY_STATUS_LABEL } from '@/lib/gates';
import { DEPARTMENTS } from '@/lib/constants';
import { space } from '@/theme/tokens';
import { usePalette } from '@/theme/use-palette';

function Node({ depth, icon, title, subtitle, recordId, open, onToggle, children }: { depth: number; icon: Parameters<typeof Icon>[0]['name']; title: string; subtitle?: string; recordId: string; open?: boolean; onToggle?: () => void; children?: React.ReactNode }) {
  const p = usePalette();
  return (
    <View>
      <Pressable
        onPress={onToggle}
        accessibilityRole={onToggle ? 'button' : 'text'}
        accessibilityState={onToggle ? { expanded: !!open } : undefined}
        accessibilityLabel={`${title}${subtitle ? ', ' + subtitle : ''}`}
        style={[styles.node, { paddingLeft: space.sm + depth * space.lg, borderBottomColor: p.border }]}>
        {onToggle ? <Icon name={open ? 'chevron-down' : 'chevron-right'} size={20} color={p.textMuted} /> : <View style={{ width: 20 }} />}
        <Icon name={icon} size={20} color={p.textMuted} />
        <View style={{ flex: 1 }}>
          <Txt variant="bodyStrong">{title}</Txt>
          {subtitle ? (
            <Txt variant="tiny" muted>
              {subtitle}
            </Txt>
          ) : null}
        </View>
        <SyncMark recordId={recordId} />
      </Pressable>
      {open ? children : null}
    </View>
  );
}

function AddLink({ depth, label, onPress }: { depth: number; label: string; onPress: () => void }) {
  return (
    <View style={{ paddingLeft: space.sm + depth * space.lg + 20 }}>
      <Button title={label} icon="plus" kind="ghost" compact onPress={onPress} style={{ alignSelf: 'flex-start' }} />
    </View>
  );
}

export default function SitesScreen() {
  const { company, profile } = useMe();
  const sites = useRecords('site', (s) => s.client_account_id === profile?.companyId);
  const departments = useRecords('department');
  const buildings = useRecords('building');
  const rooms = useRecords('room');
  const equipment = useRecords('equipment');
  const [openIds, setOpen] = useState<Record<string, boolean>>({});
  const toggle = (id: string) => setOpen((o) => ({ ...o, [id]: !(o[id] ?? true) }));
  const isOpen = (id: string) => openIds[id] ?? true;
  const add = (kind: string, parentId?: string) => router.push({ pathname: '/site-new', params: { kind, parentId: parentId ?? '' } });

  return (
    <View style={{ flex: 1 }}>
      <BrandBar title="Sites" />
      <Screen edges={[]}>
        <Card>
          <Txt variant="label" muted>
            Company
          </Txt>
          <Txt variant="bodyStrong">{company?.legal_name ?? 'Your company'}</Txt>
          {company ? <Pill label={COMPANY_STATUS_LABEL[company.onboarding_status]} tone={company.onboarding_status === 'active' ? 'success' : 'warning'} /> : null}
        </Card>
        <SectionTitle action={<Button title="Add site" icon="plus" compact kind="secondary" onPress={() => add('site')} />}>Sites tree</SectionTitle>
        {sites.length === 0 ? <EmptyState icon="office-building-outline" title="No sites yet" body="Add the company's first site or factory. You can do this offline." /> : null}
        {sites.map((s) => (
          <Card key={s.id} style={{ padding: 0, gap: 0 }}>
            <Node depth={0} icon="map-marker-outline" title={s.name} subtitle={s.address ?? 'Site'} recordId={s.id} open={isOpen(s.id)} onToggle={() => toggle(s.id)}>
              {departments
                .filter((d) => d.site_id === s.id)
                .map((d) => (
                  <Node key={d.id} depth={1} icon="account-group-outline" title={d.name} subtitle={`Department${d.department_code ? `, ${DEPARTMENTS.find((x) => x.code === d.department_code)?.name ?? d.department_code}` : ''}`} recordId={d.id} open={isOpen(d.id)} onToggle={() => toggle(d.id)}>
                    {buildings
                      .filter((b) => b.department_id === d.id)
                      .map((b) => (
                        <Node key={b.id} depth={2} icon={b.kind === 'zone' ? 'vector-square' : 'office-building-outline'} title={b.name} subtitle={b.kind === 'zone' ? 'Zone' : 'Building'} recordId={b.id} open={isOpen(b.id)} onToggle={() => toggle(b.id)}>
                          {rooms
                            .filter((r) => r.building_id === b.id)
                            .map((r) => (
                              <Node key={r.id} depth={3} icon={r.kind === 'area' ? 'texture-box' : 'door'} title={r.name} subtitle={r.kind === 'area' ? 'Area' : 'Room'} recordId={r.id} />
                            ))}
                          <AddLink depth={3} label="Add room or area" onPress={() => add('room', b.id)} />
                        </Node>
                      ))}
                    <AddLink depth={2} label="Add building or zone" onPress={() => add('building', d.id)} />
                  </Node>
                ))}
              <AddLink depth={1} label="Add department" onPress={() => add('department', s.id)} />
              <View style={{ padding: space.md, gap: space.xs }}>
                <Txt variant="label" muted>
                  Tagged equipment
                </Txt>
                {equipment
                  .filter((e) => e.site_id === s.id)
                  .map((e) => (
                    <Txt key={e.id} variant="small">
                      {e.tag_code} · {e.kind}
                    </Txt>
                  ))}
                <Button title="Add equipment" icon="barcode-scan" kind="ghost" compact onPress={() => add('equipment', s.id)} style={{ alignSelf: 'flex-start' }} />
              </View>
            </Node>
          </Card>
        ))}
      </Screen>
    </View>
  );
}

const styles = StyleSheet.create({
  node: { flexDirection: 'row', alignItems: 'center', gap: space.sm, minHeight: 52, paddingVertical: space.sm, paddingRight: space.md, borderBottomWidth: StyleSheet.hairlineWidth },
});
