// Public settings, inlined by Expo at build time from EXPO_PUBLIC_ variables
// (see .env.example). Only the Supabase URL and the publishable (anon) key,
// which are public by design; never a service role key or any other secret.
// They must be read as process.env.EXPO_PUBLIC_NAME for Expo to inline them.

const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '';

export const env = {
  supabaseUrl: url,
  supabaseAnonKey: anonKey,
  /** Live mode is offered only when both values are set to something real (not the example placeholders). */
  liveConfigured: /^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(url) && anonKey.length >= 20 && !/placeholder|your-/i.test(anonKey + url),
};
