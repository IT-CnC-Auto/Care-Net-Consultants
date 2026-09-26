// CNC HSF FORGE | KRN-GROK-02 v1.0.0 | Choosing the Grok model from an xAI model list
// Version 1.0 | 23/09/2026 | For Odendaal. Dependency free, pure: no network, no files.
// Used by grok/bridge-example.mjs (the newest rule, contract 10.10) and by
// grok/setup.mjs (an official latest alias first, then the newest rule, contract 11.6).
//
// The shapes read here are assumptions until the first real run on the bot host
// confirms them (KERNEL-API.md section 8.6):
//   GET /v1/models           OpenAI style {data: [{id, created}]}
//   GET /v1/language-models  a list of models under "models" or "data", each with
//                            an optional "aliases" array of strings
// A bare array is read too. Nothing in this file names a model: every id comes
// from xAI's own list at run time.

// Words that mark a model the kernel bot must not run on (images, embeddings,
// the small and fast variants, code models).
export const MODEL_EXCLUDE = Object.freeze(['image', 'imagine', 'vision', 'embed', 'mini', 'fast', 'code']);

// Ids and aliases are plain tokens; anything else is not written to a .env file.
export const MODEL_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:\/-]{0,127}$/;

// The rows of a model list, whatever its outer shape.
export function modelRows(list) {
  if (Array.isArray(list)) return list;
  if (list && Array.isArray(list.models)) return list.models;
  if (list && Array.isArray(list.data)) return list.data;
  return [];
}

// True when an id or alias names a Grok chat model of the flagship family.
export function isGrokChatId(id) {
  const low = String(id || '').trim().toLowerCase();
  return low.startsWith('grok') && !MODEL_EXCLUDE.some((w) => low.includes(w));
}

// The latest chat model in an xAI model list by the newest rule, or null: ids
// that start with grok, without the excluded words, greatest created (a tie is
// settled by the id, so the choice is the same every time).
export function pickLatestModel(list) {
  let best = null;
  for (const row of modelRows(list)) {
    const id = row && typeof row.id === 'string' ? row.id.trim() : '';
    if (!isGrokChatId(id)) continue;
    const created = Number(row.created);
    if (!Number.isFinite(created)) continue;
    if (!best || created > best.created || (created === best.created && id > best.id)) best = { id, created };
  }
  return best ? best.id : null;
}

// True when at least one row carries an "aliases" array (even an empty one):
// the list is one that reports aliases at all.
export function listHasAliases(list) {
  return modelRows(list).some((row) => row && Array.isArray(row.aliases));
}

// The official alias ending in "latest" for the flagship Grok family, or null.
// Both the alias and the model it points at must pass isGrokChatId; among
// several, the alias of the model with the greatest created wins (then the
// alias itself, for a stable choice).
export function pickLatestAlias(list) {
  let best = null;
  for (const row of modelRows(list)) {
    if (!row || !Array.isArray(row.aliases)) continue;
    const id = typeof row.id === 'string' ? row.id.trim() : '';
    if (!isGrokChatId(id)) continue;
    const created = Number.isFinite(Number(row.created)) ? Number(row.created) : -Infinity;
    for (const raw of row.aliases) {
      const alias = typeof raw === 'string' ? raw.trim() : '';
      if (!alias.toLowerCase().endsWith('latest') || !isGrokChatId(alias) || !MODEL_ID_RE.test(alias)) continue;
      if (!best || created > best.created || (created === best.created && alias > best.id)) best = { id: alias, created };
    }
  }
  return best ? best.id : null;
}

// The setup script's choice: {id, how: 'alias'|'newest'} or {id: null, how: null}.
export function pickModel(list) {
  const alias = pickLatestAlias(list);
  if (alias) return { id: alias, how: 'alias' };
  const newest = pickLatestModel(list);
  if (newest && MODEL_ID_RE.test(newest)) return { id: newest, how: 'newest' };
  return { id: null, how: null };
}
