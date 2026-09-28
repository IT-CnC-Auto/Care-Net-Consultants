// App wide state: which mode (demo or live), who is signed in, how far through
// sign in they are (MFA, unlock), the local store and the sync engine, and the
// 10 minute step up. The root layout shows only the screens the phase allows.

import * as Crypto from 'expo-crypto';
import * as Device from 'expo-device';
import * as LocalAuthentication from 'expo-local-authentication';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { AppState, Platform } from 'react-native';

import { DemoBackend } from '@/backend/demo-backend';
import { secureKv } from '@/backend/secure-kv';
import { NotConnectedError, type AuthState, type Backend, type Mode, type Profile } from '@/backend/types';
import { env } from '@/config/env';
import { DataStore } from '@/data/data-store';
import { ensureKernelTemplates } from '@/data/kernel-templates';
import { openLocalStore } from '@/data/local-store';
import { SyncEngine } from '@/data/sync-engine';
import { pushRecent } from '@/lib/places';
import { isStepUpValid, unlockMode, type StepUpPurpose } from '@/lib/step-up';

export type Phase = 'booting' | 'signed_out' | 'needs_mfa_enrol' | 'needs_mfa_verify' | 'locked' | 'ready' | 'problem';

const KEY_MODE = 'bi.mode';
const KEY_LAST_MFA = 'bi.mfa.last';
const KEY_BIO = 'bi.bio';
const RELOCK_AFTER_MS = 5 * 60 * 1000;
const KV_ACTIVE_COMPANY = 'active.company';
const KV_RECENT_PLACES = 'recent.places';

export interface AppValue {
  phase: Phase;
  mode: Mode | null;
  backend: Backend | null;
  store: DataStore | null;
  engine: SyncEngine | null;
  auth: AuthState | null;
  profile: Profile | null;
  problem: string | null;
  deviceRooted: boolean;
  biometricAvailable: boolean;
  biometricEnabled: boolean;
  biometricOffered: boolean;
  lastStepUpAt: number | null;
  liveAvailable: boolean;
  /** The company the person is working on now (the switcher changes it); defaults to the profile's company. */
  activeCompanyId: string | null;
  /** Places opened lately, most recent first (kept on this phone). */
  recentPlaceIds: string[];
  setActiveCompany(id: string): Promise<void>;
  /** Marks a place as used now (recent places) and makes its company the active one. */
  touchPlace(placeId: string, companyId: string): Promise<void>;
  chooseMode(mode: Mode): Promise<Backend>;
  afterSignIn(): Promise<void>;
  completeMfa(): Promise<void>;
  unlockWithBiometrics(): Promise<boolean>;
  /** From the unlock screen: use the authenticator code instead of biometrics. */
  switchToCode(): void;
  setBiometricEnabled(on: boolean): Promise<void>;
  markStepUp(purpose: StepUpPurpose): Promise<void>;
  stepUpValid(): boolean;
  signOut(): Promise<void>;
  resetDemo(): Promise<void>;
  reloadProfile(): Promise<void>;
}

const AppContext = createContext<AppValue | null>(null);

export function useApp(): AppValue {
  const v = useContext(AppContext);
  if (!v) throw new Error('useApp must be used inside AppProvider');
  return v;
}

async function makeBackend(mode: Mode, store: DataStore): Promise<Backend> {
  if (mode === 'demo') return new DemoBackend(store);
  // Loaded only in live mode so the demo never touches the Supabase client.
  const { SupabaseBackend } = await import('@/backend/supabase-backend');
  return new SupabaseBackend();
}

export function AppProvider({ children }: { children: ReactNode }) {
  const [phase, setPhase] = useState<Phase>('booting');
  const [mode, setMode] = useState<Mode | null>(null);
  const [backend, setBackend] = useState<Backend | null>(null);
  const [store, setStore] = useState<DataStore | null>(null);
  const [engine, setEngine] = useState<SyncEngine | null>(null);
  const [auth, setAuth] = useState<AuthState | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const [deviceRooted, setDeviceRooted] = useState(false);
  const [biometricAvailable, setBiometricAvailable] = useState(false);
  const [biometricEnabled, setBioEnabled] = useState(false);
  const [biometricOffered, setBiometricOffered] = useState(false);
  const [lastStepUpAt, setLastStepUpAt] = useState<number | null>(null);
  const [activeCompanyId, setActiveCompanyId] = useState<string | null>(null);
  const [recentPlaceIds, setRecentPlaceIds] = useState<string[]>([]);
  const mfaThisLaunch = useRef(false);
  const backgroundAt = useRef<number | null>(null);
  const refs = useRef<{ store: DataStore | null; backend: Backend | null; engine: SyncEngine | null }>({ store: null, backend: null, engine: null });

  const open = useCallback(async (m: Mode) => {
    if (refs.current.store && refs.current.backend && mode === m) return { store: refs.current.store, backend: refs.current.backend };
    refs.current.engine?.stop();
    const local = await openLocalStore(m);
    const s = await DataStore.open(local, () => Crypto.randomUUID());
    const b = await makeBackend(m, s);
    refs.current = { store: s, backend: b, engine: null };
    setStore(s);
    setBackend(b);
    setMode(m);
    return { store: s, backend: b };
  }, [mode]);

  const goReady = useCallback(async (s: DataStore, b: Backend) => {
    try {
      const p = await b.loadProfile(s);
      await ensureKernelTemplates(s);
      setProfile(p);
      const savedCompany = await s.kvGet(KV_ACTIVE_COMPANY);
      setActiveCompanyId(savedCompany && s.get('company', savedCompany) ? savedCompany : p.companyId);
      try {
        const r = JSON.parse((await s.kvGet(KV_RECENT_PLACES)) ?? '[]') as unknown;
        setRecentPlaceIds(Array.isArray(r) ? r.filter((x): x is string => typeof x === 'string') : []);
      } catch {
        setRecentPlaceIds([]);
      }
      const e = new SyncEngine(s, b);
      refs.current.engine?.stop();
      refs.current.engine = e;
      setEngine(e);
      await e.start();
      setProblem(null);
      setPhase('ready');
    } catch (err) {
      setProblem(err instanceof NotConnectedError || err instanceof Error ? err.message : 'Your details could not be loaded.');
      setPhase('problem');
    }
  }, []);

  const decide = useCallback(async (s: DataStore, b: Backend) => {
    const a = await b.currentAuth();
    setAuth(a);
    if (!a) {
      setPhase('signed_out');
      return;
    }
    if (!a.hasTotp) {
      setPhase('needs_mfa_enrol');
      return;
    }
    if (a.aal === 'aal1') {
      setPhase('needs_mfa_verify');
      return;
    }
    const reinstalled = !(await s.kvGet('install.marker'));
    await s.kvSet('install.marker', '1');
    const last = Number(await secureKv.getItem(KEY_LAST_MFA)) || null;
    const bioOn = (await secureKv.getItem(KEY_BIO)) === '1';
    const m = unlockMode({ hasSession: true, mfaDoneThisLaunch: mfaThisLaunch.current, biometricEnabled: bioOn, biometricAvailable, lastFullMfaAt: last, reinstalled, now: Date.now() });
    if (m === 'biometric') setPhase('locked');
    else if (m === 'full_mfa') setPhase('needs_mfa_verify');
    else await goReady(s, b);
  }, [biometricAvailable, goReady]);

  // Boot: device checks, then the saved mode and session.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      let rooted = false;
      let bio = false;
      if (Platform.OS !== 'web') {
        try {
          rooted = await Device.isRootedExperimentalAsync();
        } catch {
          rooted = false;
        }
        try {
          bio = (await LocalAuthentication.hasHardwareAsync()) && (await LocalAuthentication.isEnrolledAsync());
        } catch {
          bio = false;
        }
      }
      const bioOn = (await secureKv.getItem(KEY_BIO)) === '1';
      const saved = (await secureKv.getItem(KEY_MODE)) as Mode | null;
      if (cancelled) return;
      setDeviceRooted(rooted);
      setBiometricAvailable(bio);
      setBioEnabled(bioOn);
      setBiometricOffered(bioOn);
      if (!saved || (saved === 'live' && !env.liveConfigured)) {
        setPhase('signed_out');
        return;
      }
      try {
        const { store: s, backend: b } = await open(saved);
        if (!cancelled) await decide(s, b);
      } catch (err) {
        setProblem(err instanceof Error ? err.message : 'The app could not start.');
        setPhase('problem');
      }
    })();
    return () => {
      cancelled = true;
    };
    // Boot runs once.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Lock again after five minutes in the background, when biometric unlock is on.
  useEffect(() => {
    const sub = AppState.addEventListener('change', (s) => {
      if (s === 'background') backgroundAt.current = Date.now();
      if (s === 'active' && backgroundAt.current && Date.now() - backgroundAt.current > RELOCK_AFTER_MS && phase === 'ready' && biometricEnabled && biometricAvailable) {
        setPhase('locked');
      }
    });
    return () => sub.remove();
  }, [phase, biometricEnabled, biometricAvailable]);

  // Live sessions can end elsewhere (sign out on another device, refresh failure).
  useEffect(() => {
    if (!backend || !store) return;
    return backend.onAuthChange(async () => {
      const a = await backend.currentAuth();
      if (!a) {
        setAuth(null);
        setPhase('signed_out');
      }
    });
  }, [backend, store]);

  const value = useMemo<AppValue>(() => ({
    phase,
    mode,
    backend,
    store,
    engine,
    auth,
    profile,
    problem,
    deviceRooted,
    biometricAvailable,
    biometricEnabled,
    biometricOffered,
    lastStepUpAt,
    liveAvailable: env.liveConfigured,
    activeCompanyId,
    recentPlaceIds,
    async setActiveCompany(id) {
      setActiveCompanyId(id);
      await refs.current.store?.kvSet(KV_ACTIVE_COMPANY, id);
    },
    async touchPlace(placeId, companyId) {
      const next = pushRecent(recentPlaceIds, placeId);
      setRecentPlaceIds(next);
      if (companyId !== activeCompanyId) setActiveCompanyId(companyId);
      await refs.current.store?.kvSet(KV_RECENT_PLACES, JSON.stringify(next));
      await refs.current.store?.kvSet(KV_ACTIVE_COMPANY, companyId);
    },
    async chooseMode(m) {
      const { backend: b } = await open(m);
      await secureKv.setItem(KEY_MODE, m);
      return b;
    },
    async afterSignIn() {
      const { store: s, backend: b } = refs.current;
      if (s && b) await decide(s, b);
    },
    async completeMfa() {
      const { store: s, backend: b } = refs.current;
      if (!s || !b) return;
      const now = Date.now();
      mfaThisLaunch.current = true;
      await secureKv.setItem(KEY_LAST_MFA, String(now));
      await s.kvSet('install.marker', '1');
      // Sign in MFA does not count as a step up: Issue, sign off and large top
      // ups always ask for the code again (valid 10 minutes from then).
      setAuth(await b.currentAuth());
      await goReady(s, b);
    },
    async unlockWithBiometrics() {
      const r = await LocalAuthentication.authenticateAsync({ promptMessage: 'Unlock Bee-Inspect', cancelLabel: 'Use my authenticator code', disableDeviceFallback: false });
      if (!r.success) return false;
      mfaThisLaunch.current = true;
      const { store: s, backend: b } = refs.current;
      if (s && b) await goReady(s, b);
      return true;
    },
    switchToCode() {
      setPhase('needs_mfa_verify');
    },
    async setBiometricEnabled(on) {
      if (on) {
        const r = await LocalAuthentication.authenticateAsync({ promptMessage: 'Turn on unlock with fingerprint or face' });
        if (!r.success) return;
      }
      await secureKv.setItem(KEY_BIO, on ? '1' : '0');
      setBioEnabled(on);
      setBiometricOffered(true);
    },
    async markStepUp(purpose) {
      const now = Date.now();
      setLastStepUpAt(now);
      await secureKv.setItem(KEY_LAST_MFA, String(now));
      try {
        await refs.current.backend?.recordStepUp(purpose);
      } catch {
        // The server records step up again at signing; the app window still applies.
      }
    },
    stepUpValid() {
      return isStepUpValid(lastStepUpAt, Date.now());
    },
    async signOut() {
      refs.current.engine?.stop();
      await refs.current.backend?.signOut();
      await secureKv.removeItem(KEY_MODE);
      mfaThisLaunch.current = false;
      setLastStepUpAt(null);
      setAuth(null);
      setProfile(null);
      setEngine(null);
      setActiveCompanyId(null);
      setPhase('signed_out');
    },
    async resetDemo() {
      refs.current.engine?.stop();
      if (refs.current.store && mode === 'demo') await refs.current.store.wipe();
      await secureKv.removeItem(KEY_MODE);
      mfaThisLaunch.current = false;
      setLastStepUpAt(null);
      setAuth(null);
      setProfile(null);
      setEngine(null);
      setPhase('signed_out');
    },
    async reloadProfile() {
      const { store: s, backend: b } = refs.current;
      if (s && b) setProfile(await b.loadProfile(s));
    },
  }), [phase, mode, backend, store, engine, auth, profile, problem, deviceRooted, biometricAvailable, biometricEnabled, biometricOffered, lastStepUpAt, activeCompanyId, recentPlaceIds, open, decide, goReady]);

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}
