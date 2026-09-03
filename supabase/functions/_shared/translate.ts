/** Azure AI Translator. Free tier 2 million characters a month [CONFIRM]. Original and translation are stored side by side. */
import { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { TENANT_ID } from "./supabase.ts";

const KEY = Deno.env.get("AZURE_TRANSLATOR_KEY");
const REGION = Deno.env.get("AZURE_TRANSLATOR_REGION") ?? "southafricanorth";
const ENDPOINT = Deno.env.get("AZURE_TRANSLATOR_ENDPOINT") ?? "https://api.cognitive.microsofttranslator.com";

export async function translateText(text: string, to: string, from?: string): Promise<{ text: string; detected: string }> {
  if (!KEY) throw new Error("AZURE_TRANSLATOR_KEY not set");
  const url = `${ENDPOINT}/translate?api-version=3.0&to=${encodeURIComponent(to)}${from ? `&from=${from}` : ""}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Ocp-Apim-Subscription-Key": KEY, "Ocp-Apim-Subscription-Region": REGION, "Content-Type": "application/json" },
    body: JSON.stringify([{ Text: text }]),
  });
  if (!res.ok) throw new Error(`Translator ${res.status}: ${await res.text()}`);
  const j = await res.json();
  return { text: j[0].translations[0].text, detected: from ?? j[0].detectedLanguage?.language ?? "und" };
}

export async function translateAndStore(db: SupabaseClient, entity: string, entityId: string, field: string, source: string, to: string) {
  if (!source.trim()) return null;
  const { text, detected } = await translateText(source, to);
  if (detected === to) return null;
  await db.from("translation").upsert({ tenant_id: TENANT_ID, entity, entity_id: entityId, field, source_language: detected, target_language: to, source_text: source, translated_text: text }, { onConflict: "entity,entity_id,field,target_language" });
  return text;
}
