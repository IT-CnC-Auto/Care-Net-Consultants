/** Natural language dates in en-ZA for the quick add bar. Recurrence ("every last Friday") is backlog. */
export function parseQuick(text: string): { title: string; due: string | null } {
  const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
  const lower = text.toLowerCase();
  const today = new Date();
  let due: Date | null = null;
  if (/\btoday\b/.test(lower)) due = today;
  else if (/\btomorrow\b/.test(lower)) { due = new Date(today); due.setDate(due.getDate() + 1); }
  else {
    const m = lower.match(/\b(next\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b/);
    if (m) { const target = days.indexOf(m[2]); due = new Date(today); let delta = (target - today.getDay() + 7) % 7; if (delta === 0 || m[1]) delta += m[1] ? 7 : 0; if (delta === 0) delta = 7; due.setDate(due.getDate() + delta); }
  }
  const title = text.replace(/\b(next\s+)?(today|tomorrow|sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b/gi, "").replace(/\b\d{1,2}(:\d{2})?\s?(am|pm)\b/gi, "").replace(/\s{2,}/g, " ").trim();
  return { title: title || text, due: due ? due.toISOString().slice(0, 10) : null };
}
