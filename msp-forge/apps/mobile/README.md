# Bee-Inspect phone app

Care Net's health and safety inspection and risk assessment app for competent persons, for all 17 industries of the Care Net kernel: register a company, then its places of inspection (sites, offices, farms, mine sections, clinics, stores, departments, buildings, floors, rooms), then its people; walk a place, capture findings, sealed photos, voice notes and 5 x 5 risks offline on kernel templates; keep the evidence content addressed and versioned; draft the report (template or AI, paid in rand from the AI Wallet), sign after step up MFA, and Issue into Section F of the free Health and Safety File. Expo SDK 57, Expo Router, TypeScript. Phase P4 and its v2 rebuild: [docs/bee-inspect/p4/v2/index.md](../../docs/bee-inspect/p4/v2/index.md) (and [docs/bee-inspect/p4/index.md](../../docs/bee-inspect/p4/index.md) for the first build); evidence design in [docs/bee-inspect/p4/evidence-storage.md](../../docs/bee-inspect/p4/evidence-storage.md).

## Run

```bash
npm install
npx expo start      # Expo Go (SDK 57) or press w for the web preview; choose "Try the demo"
npm test            # Jest unit tests (src/**/__tests__/*.spec.ts)
npx tsc --noEmit    # type check
npx expo lint       # lint
```

The demo needs no backend: five fictitious companies (construction, mining, healthcare, retail, agriculture), any six digit code passes MFA. For live mode copy `.env.example` to `.env.local` and set `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` (public values only; never a service role key).

Android preview build (APK, internal): `npx eas-cli build --profile preview --platform android`, with the two variables set in the EAS preview environment.

## Scripts (run from msp-forge)

```bash
node apps/mobile/scripts/build-kernel-bundle.mjs          # kernel bundle and server seed from the repository's kernel (needs the local Postgres of test/sql/replay.sh)
node apps/mobile/scripts/build-kernel-bundle.mjs --db cnc_kernel_bundle --check   # is the bundle current?
node apps/mobile/scripts/build-icons.mjs                  # icons, splash and favicon from assets/brand/bee-inspect-icon (Playwright Chromium)
python3 apps/mobile/scripts/build-demo-photos.py           # the drawn demonstration photos (Pillow)
```

From `apps/mobile`, after `npx expo export --platform web` and `npx expo serve --port 8087`: `node scripts/walkthrough-v2.mjs` writes the screenshots to `docs/bee-inspect/p4/v2/`.

## Layout

- `src/app/`: routes only (Expo Router). Sign in, MFA, unlock and problem screens at the top; everything after sign in under `(app)/`, with the tabs in `(app)/(tabs)/`.
- `src/lib/`: pure rules shared with the server's arithmetic (rand, wallet, risk bands, gates, step up, sync queue, seal, report skeleton), the kernel (`kernel.ts`), the places tree (`places.ts`), evidence storage (`evidence-store.ts`, `upload-plan.ts`) and search (`search-index.ts`), unit tested.
- `assets/kernel/kernel-bundle.json`: the offline Care Net kernel (generated; do not edit by hand).
- `src/data/`: the offline store (SQLite on the phone, localStorage on the web preview), the data store and the sync engine.
- `src/backend/`: the demo backend, the Supabase backend and the secure session storage.
- `src/features/`, `src/components/`, `src/theme/`: capture helpers, UI building blocks and the design tokens (one file).

Read `AGENTS.md` before changing Expo APIs: use the SDK 57 docs and `npx expo install` for dependencies.
