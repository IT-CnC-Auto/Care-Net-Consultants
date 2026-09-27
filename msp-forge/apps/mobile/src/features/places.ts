// Places of inspection on the phone: create (offline, validated against the
// tree rules), the kernel templates in the store, and the hooks screens use.

import { router } from 'expo-router';

import type { DataStore } from '@/data/data-store';
import { useStore } from '@/data/hooks';
import { kernel } from '@/lib/kernel';
import { checkPlace, childrenOf, livePlaces, pathOf, typeLabel } from '@/lib/places';
import type { Id, Place } from '@/lib/types';
import { useApp } from '@/state/app';

export type NewPlace = Omit<Place, 'id' | 'archived_at' | 'linked_department_ids' | 'custom_type_label' | 'address' | 'gps_lat' | 'gps_lng' | 'responsible_person' | 'headcount' | 'department_code'> &
  Partial<Pick<Place, 'custom_type_label' | 'address' | 'gps_lat' | 'gps_lng' | 'responsible_person' | 'headcount' | 'department_code' | 'linked_department_ids'>>;

/** Saves a new place on the phone (queued for sync) after the tree rules pass. */
export async function createPlace(store: DataStore, p: NewPlace): Promise<Place> {
  const b = kernel();
  const draft = { client_account_id: p.client_account_id, parent_id: p.parent_id, place_type: p.place_type, name: p.name.trim() };
  const check = checkPlace(b, store.list('place'), draft);
  if (!check.ok) throw new Error(check.reasons[0]);
  return store.create('place', {
    id: store.id(),
    client_account_id: p.client_account_id,
    parent_id: p.parent_id,
    place_type: p.place_type,
    custom_type_label: p.custom_type_label?.trim() || null,
    name: p.name.trim(),
    address: p.address?.trim() || null,
    gps_lat: p.gps_lat ?? null,
    gps_lng: p.gps_lng ?? null,
    responsible_person: p.responsible_person?.trim() || null,
    headcount: p.headcount ?? null,
    department_code: p.department_code ?? null,
    linked_department_ids: p.linked_department_ids ?? [],
    archived_at: null,
  });
}

export async function updatePlace(store: DataStore, id: Id, changes: Partial<Place>): Promise<void> {
  const cur = store.get('place', id);
  if (!cur) throw new Error('This place is not on this phone.');
  const next = { ...cur, ...changes };
  const check = checkPlace(kernel(), store.list('place'), { id, client_account_id: next.client_account_id, parent_id: next.parent_id, place_type: next.place_type, name: next.name });
  if (!check.ok) throw new Error(check.reasons[0]);
  await store.update('place', id, changes);
}

/** Places are archived, never deleted: evidence keeps its path. */
export async function archivePlace(store: DataStore, id: Id): Promise<void> {
  await store.update('place', id, { archived_at: new Date().toISOString() });
}

/** Opens a place and remembers it (recent places, active company). */
export function useOpenPlace() {
  const app = useApp();
  return (p: Pick<Place, 'id' | 'client_account_id'>) => {
    void app.touchPlace(p.id, p.client_account_id);
    router.push({ pathname: '/place/[id]', params: { id: p.id } });
  };
}

/** Starts an inspection at a place (the picker opens with the place chosen). */
export function useStartHere() {
  const app = useApp();
  return (p: Pick<Place, 'id' | 'client_account_id'>) => {
    void app.touchPlace(p.id, p.client_account_id);
    router.push({ pathname: '/inspection/new', params: { placeId: p.id } });
  };
}

export function usePlaces(companyId: string | null | undefined) {
  const store = useStore();
  const all = store.list('place');
  const places = livePlaces(all, companyId ?? undefined);
  return {
    all,
    places,
    roots: childrenOf(all, null, companyId ?? undefined),
    childrenOf: (id: Id) => childrenOf(all, id, companyId ?? undefined),
    pathOf: (id: Id | null | undefined) => pathOf(all, id),
    label: (p: Pick<Place, 'place_type' | 'custom_type_label'>) => typeLabel(kernel(), p),
  };
}
