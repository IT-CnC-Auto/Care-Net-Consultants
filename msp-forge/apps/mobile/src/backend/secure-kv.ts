// Secrets on the phone: the Supabase session and the unlock settings, in the
// iOS Keychain or Android Keystore through expo-secure-store. SecureStore
// values should stay under about 2 KB, and a Supabase session can be larger,
// so long values are split into chunks under one key.

import * as SecureStore from 'expo-secure-store';

const CHUNK = 1800;
const OPTS: SecureStore.SecureStoreOptions = { keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY };

const safeKey = (key: string) => key.replace(/[^A-Za-z0-9._-]/g, '_');

export const secureKv = {
  async getItem(key: string): Promise<string | null> {
    const k = safeKey(key);
    const n = await SecureStore.getItemAsync(`${k}.n`, OPTS);
    if (n === null) return SecureStore.getItemAsync(k, OPTS);
    const parts: string[] = [];
    for (let i = 0; i < Number(n); i++) {
      const part = await SecureStore.getItemAsync(`${k}.${i}`, OPTS);
      if (part === null) return null;
      parts.push(part);
    }
    return parts.join('');
  },
  async setItem(key: string, value: string): Promise<void> {
    const k = safeKey(key);
    await this.removeItem(key);
    if (value.length <= CHUNK) {
      await SecureStore.setItemAsync(k, value, OPTS);
      return;
    }
    const count = Math.ceil(value.length / CHUNK);
    for (let i = 0; i < count; i++) await SecureStore.setItemAsync(`${k}.${i}`, value.slice(i * CHUNK, (i + 1) * CHUNK), OPTS);
    await SecureStore.setItemAsync(`${k}.n`, String(count), OPTS);
  },
  async removeItem(key: string): Promise<void> {
    const k = safeKey(key);
    const n = await SecureStore.getItemAsync(`${k}.n`, OPTS);
    if (n !== null) {
      for (let i = 0; i < Number(n); i++) await SecureStore.deleteItemAsync(`${k}.${i}`, OPTS);
      await SecureStore.deleteItemAsync(`${k}.n`, OPTS);
    }
    await SecureStore.deleteItemAsync(k, OPTS);
  },
};
