// Bee-Inspect design tokens: the one place for colour, type, spacing and shape.
// Care Net brand: CNC red #ED1B24, deep red #B7141A, ink #0F0F0F, gold #F0A32B,
// Bebas Neue headings, Inter body (fonts bundled in assets/fonts, converted
// from the File site's own vercel/fonts files, SIL Open Font License 1.1).
//
// Contrast: white on CNC red is about 4.0:1, below AA for body text, so solid
// buttons use deep red (about 6.5:1) and CNC red is kept for the brand bar,
// accents and large headings.

export const brand = {
  red: '#ED1B24',
  deepRed: '#B7141A',
  ink: '#0F0F0F',
  gold: '#F0A32B',
  white: '#FFFFFF',
} as const;

/** Text and lines on the ink surfaces (brand bar, hero, balance card). */
export const onInk = {
  muted: '#CFCBC4',
  soft: '#E6E2DB',
  border: '#3A3A3A',
} as const;

/** Finding results: Pass, Fail, N/A, Observe (fixed, with AA contrast text). */
export const resultTone = {
  pass: { bg: '#1E6B2A', fg: brand.white },
  fail: { bg: brand.deepRed, fg: brand.white },
  na: { bg: '#57534D', fg: brand.white },
  observe: { bg: brand.gold, fg: brand.ink },
} as const;

/**
 * Risk bands, LOCKED (decision 1.2): Low green, Medium amber, High orange,
 * Extreme red, each with a text colour that keeps WCAG AA contrast.
 */
export const riskBandColour = {
  low: { bg: '#2E7D32', fg: brand.white, name: 'green' },
  medium: { bg: '#F9A825', fg: brand.ink, name: 'amber' },
  high: { bg: '#EF6C00', fg: brand.ink, name: 'orange' },
  extreme: { bg: '#C62828', fg: brand.white, name: 'red' },
} as const;

export interface Palette {
  background: string;
  surface: string;
  surfaceAlt: string;
  border: string;
  text: string;
  textMuted: string;
  primary: string;
  primaryPressed: string;
  onPrimary: string;
  accent: string;
  header: string;
  onHeader: string;
  success: string;
  successBg: string;
  warning: string;
  warningBg: string;
  danger: string;
  dangerBg: string;
  info: string;
  infoBg: string;
  focus: string;
}

export const light: Palette = {
  background: '#F6F5F2',
  surface: '#FFFFFF',
  surfaceAlt: '#EFEDE8',
  border: '#DEDAD2',
  text: brand.ink,
  textMuted: '#57534D',
  primary: brand.deepRed,
  primaryPressed: '#8F0F14',
  onPrimary: brand.white,
  accent: brand.red,
  header: brand.ink,
  onHeader: brand.white,
  success: '#1E6B2A',
  successBg: '#E3F1E5',
  warning: '#7A4A00',
  warningBg: '#FDF0D8',
  danger: brand.deepRed,
  dangerBg: '#FBE4E5',
  info: '#1F4E79',
  infoBg: '#E4EDF6',
  focus: brand.gold,
};

export const dark: Palette = {
  background: brand.ink,
  surface: '#1A1A1A',
  surfaceAlt: '#252525',
  border: '#3A3A3A',
  text: '#F4F3F0',
  textMuted: '#B3AFA8',
  primary: brand.deepRed,
  primaryPressed: '#8F0F14',
  onPrimary: brand.white,
  accent: '#FF4B52',
  header: '#000000',
  onHeader: brand.white,
  success: '#7FD18B',
  successBg: '#16301A',
  warning: '#F5C26B',
  warningBg: '#3A2A0E',
  danger: '#FF7B80',
  dangerBg: '#3A1214',
  info: '#8DB9E6',
  infoBg: '#14263A',
  focus: brand.gold,
};

/** Font family names as loaded by useFonts in src/app/_layout.tsx. */
export const fonts = {
  heading: 'BebasNeue',
  body: 'Inter',
  bodySemiBold: 'Inter-SemiBold',
  bodyBold: 'Inter-Bold',
} as const;

export const type = {
  display: { fontFamily: fonts.heading, fontSize: 40, lineHeight: 44, letterSpacing: 0.5 },
  h1: { fontFamily: fonts.heading, fontSize: 32, lineHeight: 36, letterSpacing: 0.5 },
  h2: { fontFamily: fonts.heading, fontSize: 26, lineHeight: 30, letterSpacing: 0.4 },
  h3: { fontFamily: fonts.heading, fontSize: 21, lineHeight: 24, letterSpacing: 0.3 },
  body: { fontFamily: fonts.body, fontSize: 16, lineHeight: 23 },
  bodyStrong: { fontFamily: fonts.bodySemiBold, fontSize: 16, lineHeight: 23 },
  small: { fontFamily: fonts.body, fontSize: 14, lineHeight: 20 },
  smallStrong: { fontFamily: fonts.bodySemiBold, fontSize: 14, lineHeight: 20 },
  tiny: { fontFamily: fonts.body, fontSize: 12, lineHeight: 16 },
  label: { fontFamily: fonts.bodySemiBold, fontSize: 12, lineHeight: 16, letterSpacing: 0.6, textTransform: 'uppercase' as const },
  button: { fontFamily: fonts.bodySemiBold, fontSize: 16, lineHeight: 20 },
} as const;

export const space = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32, xxxl: 48 } as const;
export const radius = { sm: 6, md: 10, lg: 16, pill: 999 } as const;

/** Minimum touch target (WCAG 2.5.5 and platform guidance). */
export const touch = 48;

export const maxContentWidth = 640;
