// The 5 x 5 risk matrix with the LOCKED bands (decision 1.2):
// 1 to 4 Low (green), 5 to 9 Medium (amber), 10 to 15 High (orange),
// 16 to 25 Extreme (red). Always show the number AND the label. The same rules
// as supabase/functions/_shared/bi/risk.js and bi_risk_band (migration 060).

import { riskBandColour } from '../theme/tokens';

export type RiskBand = 'low' | 'medium' | 'high' | 'extreme';
export type ControlLevel = 'elimination' | 'substitution' | 'engineering' | 'administrative' | 'ppe';

export const HIERARCHY: readonly ControlLevel[] = ['elimination', 'substitution', 'engineering', 'administrative', 'ppe'];

export const BANDS: readonly { band: RiskBand; from: number; to: number }[] = [
  { band: 'low', from: 1, to: 4 },
  { band: 'medium', from: 5, to: 9 },
  { band: 'high', from: 10, to: 15 },
  { band: 'extreme', from: 16, to: 25 },
];

export const BAND_LABEL: Record<RiskBand, string> = { low: 'Low', medium: 'Medium', high: 'High', extreme: 'Extreme' };

/** Band colours live with the other design tokens (src/theme/tokens.ts). */
export const BAND_COLOUR: Record<RiskBand, { bg: string; fg: string; name: string }> = riskBandColour;

export const CONTROL_LABEL: Record<ControlLevel, string> = {
  elimination: 'Elimination',
  substitution: 'Substitution',
  engineering: 'Engineering controls',
  administrative: 'Administrative controls',
  ppe: 'PPE',
};

export const LIKELIHOOD_LABEL = ['Rare', 'Unlikely', 'Possible', 'Likely', 'Almost certain'] as const;
export const SEVERITY_LABEL = ['Insignificant', 'Minor', 'Moderate', 'Major', 'Catastrophic'] as const;

const inRange = (n: unknown): n is number => typeof n === 'number' && Number.isInteger(n) && n >= 1 && n <= 5;

export function riskScore(likelihood: number | null | undefined, severity: number | null | undefined): number | null {
  return inRange(likelihood) && inRange(severity) ? likelihood * severity : null;
}

export function riskBand(score: number | null | undefined): RiskBand | null {
  if (typeof score !== 'number' || !Number.isInteger(score)) return null;
  const b = BANDS.find((x) => score >= x.from && score <= x.to);
  return b ? b.band : null;
}

/** "12 High": the number and the label, never one without the other. */
export function riskText(score: number | null | undefined): string {
  const band = riskBand(score);
  return band ? `${score} ${BAND_LABEL[band]}` : 'Not rated';
}

export interface Control {
  level: ControlLevel;
  description?: string;
}

export function topControl(controls: readonly (Control | null | undefined)[] | null | undefined): ControlLevel | null {
  const levels = new Set((controls ?? []).map((c) => c?.level));
  return HIERARCHY.find((l) => levels.has(l)) ?? null;
}

export interface RiskInput {
  hazard: string;
  inherent_likelihood: number | null;
  inherent_severity: number | null;
  residual_likelihood?: number | null;
  residual_severity?: number | null;
  controls?: Control[];
}

/** Plain problems, the same checks as bi_risk (empty when sound). */
export function validateRisk(r: RiskInput): string[] {
  const problems: string[] = [];
  if (typeof r.hazard !== 'string' || r.hazard.trim().length < 3) problems.push('Name the hazard (at least 3 characters).');
  if (!inRange(r.inherent_likelihood) || !inRange(r.inherent_severity)) problems.push('Choose the inherent likelihood and severity (1 to 5 each).');
  const hasRl = r.residual_likelihood !== undefined && r.residual_likelihood !== null;
  const hasRs = r.residual_severity !== undefined && r.residual_severity !== null;
  if (hasRl !== hasRs) problems.push('Give both residual likelihood and residual severity, or neither.');
  if (hasRl && hasRs) {
    if (!inRange(r.residual_likelihood) || !inRange(r.residual_severity)) problems.push('Residual likelihood and severity are 1 to 5 each.');
    else if ((riskScore(r.residual_likelihood, r.residual_severity) ?? 0) > (riskScore(r.inherent_likelihood, r.inherent_severity) ?? 0)) {
      problems.push('The residual risk cannot be above the inherent risk.');
    }
  }
  if (r.controls && r.controls.some((c) => !c || !HIERARCHY.includes(c.level))) {
    problems.push('Every control names a level of the hierarchy of controls.');
  }
  return problems;
}

/** The 5 x 5 heat map: counts per [likelihood - 1][severity - 1]. */
export function heatMap(risks: readonly RiskInput[], which: 'inherent' | 'residual' = 'inherent'): number[][] {
  const grid = Array.from({ length: 5 }, () => Array<number>(5).fill(0));
  for (const r of risks) {
    const l = which === 'residual' ? r.residual_likelihood : r.inherent_likelihood;
    const s = which === 'residual' ? r.residual_severity : r.inherent_severity;
    if (inRange(l) && inRange(s)) grid[l - 1][s - 1] += 1;
  }
  return grid;
}
