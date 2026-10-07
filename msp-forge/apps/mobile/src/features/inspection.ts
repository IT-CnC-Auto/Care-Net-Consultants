import { useStore } from '@/data/hooks';
import { latestVersions } from '@/lib/evidence-store';
import { failRuleViolations } from '@/lib/gates';
import { todayIso } from '@/lib/dates';
import { industry, kernel } from '@/lib/kernel';
import { useApp } from '@/state/app';

/** Everything a screen needs about one inspection, kept live from the store. */
export function useInspection(id: string | undefined) {
  const store = useStore();
  const inspection = id ? store.get('inspection', id) : undefined;
  const template = inspection ? store.get('template', inspection.template_id) : undefined;
  const items = inspection ? store.where('template_item', (t) => t.template_id === inspection.template_id).sort((a, b) => a.ordinal - b.ordinal) : [];
  const areas = store.where('area', (a) => a.inspection_id === id).sort((a, b) => a.ordinal - b.ordinal);
  const findings = store.where('finding', (f) => f.inspection_id === id);
  // Only the newest version of each photo and voice note: corrections are new versions, never overwrites.
  const photos = latestVersions(store.where('photo', (p) => p.inspection_id === id));
  const voiceNotes = latestVersions(store.where('voice_note', (v) => v.inspection_id === id)).sort((a, b) => a.captured_at.localeCompare(b.captured_at));
  const vnIds = new Set(voiceNotes.flatMap((v) => [v.id, v.root_evidence_id ?? v.id]));
  const transcripts = store.where('transcript', (t) => vnIds.has(t.voice_note_id));
  const risks = store.where('risk', (r) => r.inspection_id === id);
  const actions = store.where('action', (a) => a.inspection_id === id);
  const reports = store.where('report', (r) => r.inspection_id === id && r.status !== 'withdrawn').sort((a, b) => b.version - a.version);
  const violations = inspection ? failRuleViolations({ findings, photos, actions, voiceNotes, policy: inspection.voice_note_policy }) : [];
  const pendingSync = store.getQueue().filter((q) => {
    const r = q.payload as Record<string, unknown>;
    return q.recordId === id || r.inspection_id === id || (q.kind === 'transcript' && vnIds.has(String(r.voice_note_id)));
  }).length;
  const place = inspection?.place_id ? store.get('place', inspection.place_id) : undefined;
  return { store, inspection, template, place, items, areas, findings, photos, voiceNotes, transcripts, risks, actions, report: reports[0], violations, pendingSync };
}

/**
 * The signed in person, their inspector record, the company they are working on
 * now (the switcher's active company, else their own), its industry from the
 * kernel, its wallet, and their qualifications.
 */
export function useMe() {
  const app = useApp();
  const store = useStore();
  const profile = app.profile;
  const inspector = profile ? store.get('inspector', profile.appUserId) : undefined;
  const companyId = app.activeCompanyId ?? profile?.companyId ?? null;
  const company = companyId ? store.get('company', companyId) : undefined;
  const wallet = companyId ? store.where('wallet', (w) => w.client_account_id === companyId)[0] : undefined;
  const walletId = wallet?.id ?? (companyId === profile?.companyId ? (profile?.walletId ?? null) : null);
  const qualifications = store.list('qualification');
  const kernelIndustry = industry(kernel(), company?.industry_code);
  return { app, store, profile, inspector, company, companyId, walletId, industry: kernelIndustry, qualifications, today: todayIso() };
}
