/** Microsoft Graph with client credentials on one Entra app registration. Least privilege scopes are listed in design/specs/INTEGRATIONS.md section 5. */
const TENANT = Deno.env.get("AZURE_TENANT_ID");
const CLIENT_ID = Deno.env.get("AZURE_CLIENT_ID");
const SECRET = Deno.env.get("AZURE_CLIENT_SECRET");
let cached: { token: string; exp: number } | null = null;

export async function graphToken(): Promise<string> {
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  if (!TENANT || !CLIENT_ID || !SECRET) throw new Error("Azure app registration env not set");
  const res = await fetch(`https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token`, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: CLIENT_ID, client_secret: SECRET, scope: "https://graph.microsoft.com/.default", grant_type: "client_credentials" }),
  });
  if (!res.ok) throw new Error(`Graph token ${res.status}: ${await res.text()}`);
  const j = await res.json();
  cached = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
  return cached.token;
}

export async function graph<T = unknown>(path: string, init: RequestInit = {}, raw = false): Promise<T> {
  const token = await graphToken();
  const res = await fetch(path.startsWith("http") ? path : `https://graph.microsoft.com/v1.0${path}`, {
    ...init, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
  if (!res.ok) throw new Error(`Graph ${res.status} ${path}: ${(await res.text()).slice(0, 300)}`);
  if (res.status === 202 || res.status === 204) return undefined as T;
  return (raw ? await res.text() : await res.json()) as T;
}

export interface GraphMessage { id: string; subject: string; bodyPreview: string; webLink: string; receivedDateTime: string; from?: { emailAddress?: { name?: string } }; flag?: { flagStatus?: string }; }
export interface GraphEvent { id: string; subject: string; start: { dateTime: string }; end: { dateTime: string }; showAs: string; isAllDay: boolean; }

export async function sendMail(fromUser: string, to: string, subject: string, html: string) {
  await graph(`/users/${encodeURIComponent(fromUser)}/sendMail`, {
    method: "POST",
    body: JSON.stringify({ message: { subject, body: { contentType: "HTML", content: html }, toRecipients: [{ emailAddress: { address: to } }] }, saveToSentItems: false }),
  });
}
