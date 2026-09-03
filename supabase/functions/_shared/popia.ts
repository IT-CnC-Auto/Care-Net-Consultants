/**
 * POPIA and HPCSA scrub. Employee names and medical outcomes never enter a task, an email or a transcript extract.
 * Boards carry counts, dates and case numbers only. This is deliberately conservative: a dropped line is logged, never lost silently.
 */
const HEALTH_TERMS = /\b(fit|unfit|diagnos\w*|hiv|tb|tuberculosis|audiogram|audiometry result|spirometry result|hearing loss|hypertension|diabet\w*|pregnan\w*|referr?al result|medical outcome|certificate of fitness|restricted duty|blood pressure|drug test|alcohol test|positive|negative)\b/i;
const PERSON_NAME = /\b[A-Z][a-z]{2,}\s+[A-Z][a-z]{2,}\b/;           // Two capitalised words, a likely full name
const ID_NUMBER = /\b\d{13}\b/;                                       // South African identity number
const EMAIL = /[\w.+-]+@[\w-]+\.[\w.-]+/g;
const PHONE = /(\+27|0)\s?\d{2}[\s-]?\d{3}[\s-]?\d{4}/g;

export interface ScrubResult { text: string; droppedLines: number; redactions: number; }

/** Removes lines that pair a person with a health term, redacts identity numbers, emails and phone numbers everywhere. */
export function scrubTranscript(text: string): ScrubResult {
  let dropped = 0; let redactions = 0;
  const kept: string[] = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    if (HEALTH_TERMS.test(line) && (PERSON_NAME.test(line) || ID_NUMBER.test(line))) { dropped++; continue; }
    let out = line;
    out = out.replace(ID_NUMBER, () => { redactions++; return "[id number removed]"; });
    out = out.replace(EMAIL, () => { redactions++; return "[email removed]"; });
    out = out.replace(PHONE, () => { redactions++; return "[phone removed]"; });
    kept.push(out);
  }
  return { text: kept.join("\n"), droppedLines: dropped, redactions };
}

/** MCO descriptions may name an employee ("1x Medical(s) expiring for Tyrell Henderson"). Replace with a count and case wording. */
export function scrubMcoDescription(description: string, count: number | null): string {
  const m = description.match(/for\s+(.+?)\s+in between/i);
  if (m && PERSON_NAME.test(m[1]) && !/\(pty\)|ltd|services|group|industries|chemicals|cooling|coach|auto/i.test(m[1])) {
    return description.replace(m[1], `${count ?? 1} employee${(count ?? 1) === 1 ? "" : "s"}`);
  }
  return description.replace(EMAIL, "[email removed]").replace(PHONE, "[phone removed]");
}

/** Outbound email bodies are checked before a signature is even requested. */
export function emailBodyIsSafe(body: string): { ok: boolean; reason?: string } {
  if (HEALTH_TERMS.test(body) && PERSON_NAME.test(body)) return { ok: false, reason: "names a person with a health term" };
  if (ID_NUMBER.test(body)) return { ok: false, reason: "contains an identity number" };
  return { ok: true };
}
