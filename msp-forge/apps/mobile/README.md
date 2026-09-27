# Bee-Inspect phone app

Care Net's health and safety inspection and risk assessment app for competent persons: walk the site room by room, capture findings, sealed photos, voice notes and 5 x 5 risks offline, draft the report (template or AI, paid in rand from the AI Wallet), sign after step up MFA, and Issue into Section F of the free Health and Safety File. Expo SDK 57, Expo Router, TypeScript. Phase P4; full notes, checks, stubs and screenshots in [docs/bee-inspect/p4/index.md](../../docs/bee-inspect/p4/index.md).

## Run

```bash
npm install
npx expo start      # Expo Go (SDK 57) or press w for the web preview; choose "Try the demo"
npm test            # Jest unit tests (src/**/__tests__/*.spec.ts)
npx tsc --noEmit    # type check
npx expo lint       # lint
```

The demo needs no backend: fictitious Rietvlei Civils and Building data, any six digit code passes MFA. For live mode copy `.env.example` to `.env.local` and set `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` (public values only; never a service role key).

Android preview build (APK, internal): `npx eas-cli build --profile preview --platform android`, with the two variables set in the EAS preview environment.

## Layout

- `src/app/`: routes only (Expo Router). Sign in, MFA, unlock and problem screens at the top; everything after sign in under `(app)/`, with the tabs in `(app)/(tabs)/`.
- `src/lib/`: pure rules shared with the server's arithmetic (rand, wallet, risk bands, gates, step up, sync queue, seal, report skeleton), unit tested.
- `src/data/`: the offline store (SQLite on the phone, localStorage on the web preview), the data store and the sync engine.
- `src/backend/`: the demo backend, the Supabase backend and the secure session storage.
- `src/features/`, `src/components/`, `src/theme/`: capture helpers, UI building blocks and the design tokens (one file).

Read `AGENTS.md` before changing Expo APIs: use the SDK 57 docs and `npx expo install` for dependencies.
