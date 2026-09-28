// Bee-Inspect phone app: fixed values shared by every screen (P4).
// Labels and links follow hsf/BUILD-CONTRACT.md 16 and hsf/BEE-INSPECT-P3-DECISIONS.md.

export const APP_NAME = 'Bee-Inspect';

/** Every draft carries this label (prompt B6, migration 061). */
export const DRAFT_LABEL = 'Assistive draft. Competent person sign off required.';

/** The locked footer of every report page (prompt section 3.5). */
export const LOCKED_FOOTER = 'This report is powered by Care Net Consultants Development House (Pty) Ltd';

/** Decision 1.8. */
export const BEE_MATCHED_URL = 'https://www.carenetconsultants.co.za/bee_matched_Recruitment';

/** Contract 1: the only verified number. */
export const WHATSAPP_NUMBER = '27600702723';
export const WHATSAPP_DISPLAY = '27 60 070 2723';
export function whatsappUrl(message?: string): string {
  const base = `https://wa.me/${WHATSAPP_NUMBER}`;
  return message ? `${base}?text=${encodeURIComponent(message)}` : base;
}

export const PRIVACY_URL = 'https://www.carenetconsultants.co.za/privacy-policy';

/**
 * Ozow web top up page. STUB: null until the web desk billing page exists
 * (prompt B10, phase P5 or P6). The wallet screen says so instead of linking.
 */
export const WEB_TOPUP_URL: string | null = null;

/** Decision 1.5: step up valid 10 minutes in the app. */
export const STEP_UP_WINDOW_MS = 10 * 60 * 1000;

/** Prompt B3: biometric unlock after the first MFA; full MFA again after 7 days or a reinstall. */
export const FULL_MFA_EVERY_MS = 7 * 24 * 60 * 60 * 1000;

/** Claim codes live 10 minutes and are used once (prompt B3, migration 063). */
export const CLAIM_TTL_MINUTES = 10;

/** File departments a site department is filed under (contract 2). */
export const DEPARTMENTS: readonly { code: string; name: string }[] = [
  { code: 'EXEC', name: 'Executive and legal' },
  { code: 'HR', name: 'Human resources' },
  { code: 'SHE', name: 'Health and safety' },
  { code: 'OPS', name: 'Operations' },
  { code: 'ENG', name: 'Engineering and maintenance' },
  { code: 'PROC', name: 'Procurement and contractors' },
  { code: 'OH', name: 'Occupational health and medical' },
  { code: 'TRAIN', name: 'Training and development' },
  { code: 'FAC', name: 'Facilities and security' },
];

/**
 * Consent wording versions. PLACEHOLDERS (0.1) until the Bee-Inspect consent
 * wording is confirmed (docs/bee-inspect/p3/index.md, open questions).
 */
export const CONSENT_VERSIONS = {
  terms: 'BI-TERMS-0.1',
  privacy: 'BI-PRIVACY-0.1',
  location: 'BI-LOCATION-0.1',
  voice_recording: 'BI-VOICE-0.1',
  identifiable_people: 'BI-PEOPLE-0.1',
  fica_processing: 'BI-FICA-0.1',
  marketing: 'BI-MARKETING-0.1',
} as const;
