// The Supabase client for live mode: the same project as the File. The session
// is kept in the Keychain or Keystore (secure-kv), refreshed while the app is in
// the foreground, and never written to plain storage on the phone.

import 'react-native-url-polyfill/auto';

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { AppState, Platform } from 'react-native';

import { env } from '@/config/env';

import { secureKv } from './secure-kv';

let client: SupabaseClient | null = null;

export function getSupabase(): SupabaseClient {
  if (!env.liveConfigured) throw new Error('Live sign in is not set up on this build.');
  if (!client) {
    client = createClient(env.supabaseUrl, env.supabaseAnonKey, {
      auth: {
        storage: secureKv,
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: false,
        flowType: 'pkce',
      },
    });
    if (Platform.OS !== 'web') {
      AppState.addEventListener('change', (state) => {
        if (!client) return;
        if (state === 'active') client.auth.startAutoRefresh();
        else client.auth.stopAutoRefresh();
      });
    }
  }
  return client;
}
