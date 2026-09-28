// Web preview only: there is no keychain in a browser, so these values sit in
// localStorage. The web build is for the demonstration walk through; live
// inspections run on the phone, where src/backend/secure-kv.ts uses the
// Keychain or Keystore.

const mem = new Map<string, string>();

function ls(): Storage | null {
  try {
    return typeof window !== 'undefined' ? window.localStorage : null;
  } catch {
    return null;
  }
}

export const secureKv = {
  async getItem(key: string): Promise<string | null> {
    const s = ls();
    return s ? s.getItem('bi-secure:' + key) : (mem.get(key) ?? null);
  },
  async setItem(key: string, value: string): Promise<void> {
    const s = ls();
    if (s) s.setItem('bi-secure:' + key, value);
    else mem.set(key, value);
  },
  async removeItem(key: string): Promise<void> {
    const s = ls();
    if (s) s.removeItem('bi-secure:' + key);
    else mem.delete(key);
  },
};
