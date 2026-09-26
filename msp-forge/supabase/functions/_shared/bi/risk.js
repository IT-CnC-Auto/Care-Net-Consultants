// CNC HSF FORGE | BI-EDGE-01 v1.0.0 | Bee-Inspect 5 x 5 risk matrix 26/09/2026
//
// The same rules as migration 060 (bi_risk_score, bi_risk_band,
// bi_risk_top_control and the bi_risk constraints). Plain ES module; Deno and
// Node 22.
//
// Score = likelihood x severity, each 1 to 5. Bands (Care Net's working bands,
// to be confirmed against the Care Net methodology): 1 to 4 low, 5 to 9
// medium, 10 to 15 high, 16 to 25 extreme. Controls sit on the hierarchy of
// controls, highest first: elimination, substitution, engineering,
// administrative, ppe. A residual score never exceeds the inherent score.

export const HIERARCHY = Object.freeze(['elimination', 'substitution', 'engineering', 'administrative', 'ppe']);
export const BANDS = Object.freeze([
  { band: 'low', from: 1, to: 4 },
  { band: 'medium', from: 5, to: 9 },
  { band: 'high', from: 10, to: 15 },
  { band: 'extreme', from: 16, to: 25 },
]);

const inRange = (n) => Number.isInteger(n) && n >= 1 && n <= 5;

export function riskScore(likelihood, severity) {
  return inRange(likelihood) && inRange(severity) ? likelihood * severity : null;
}

export function riskBand(score) {
  if (!Number.isInteger(score)) return null;
  const b = BANDS.find((x) => score >= x.from && score <= x.to);
  return b ? b.band : null;
}

export function topControl(controls) {
  const levels = new Set((controls || []).map((c) => c && c.level));
  return HIERARCHY.find((l) => levels.has(l)) || null;
}

// The 5 x 5 heat map: counts per [likelihood - 1][severity - 1] of the given scores.
export function heatMap(risks, which = 'inherent') {
  const grid = Array.from({ length: 5 }, () => Array(5).fill(0));
  for (const r of risks || []) {
    const l = which === 'residual' ? r.residual_likelihood : r.inherent_likelihood;
    const s = which === 'residual' ? r.residual_severity : r.inherent_severity;
    if (inRange(l) && inRange(s)) grid[l - 1][s - 1] += 1;
  }
  return grid;
}

// Checks a risk as bi_risk does. Returns a list of plain problems (empty when sound).
export function validateRisk(r) {
  const problems = [];
  if (!r || typeof r !== 'object') return ['A risk is required.'];
  if (typeof r.hazard !== 'string' || r.hazard.trim().length < 3) problems.push('Name the hazard (at least 3 characters).');
  if (!inRange(r.inherent_likelihood) || !inRange(r.inherent_severity)) problems.push('Inherent likelihood and severity are each 1 to 5.');
  const hasRl = r.residual_likelihood !== undefined && r.residual_likelihood !== null;
  const hasRs = r.residual_severity !== undefined && r.residual_severity !== null;
  if (hasRl !== hasRs) problems.push('Give both residual likelihood and residual severity, or neither.');
  if (hasRl && hasRs) {
    if (!inRange(r.residual_likelihood) || !inRange(r.residual_severity)) problems.push('Residual likelihood and severity are each 1 to 5.');
    else if (riskScore(r.residual_likelihood, r.residual_severity) > (riskScore(r.inherent_likelihood, r.inherent_severity) || 0)) {
      problems.push('The residual risk cannot be above the inherent risk.');
    }
  }
  if (r.controls !== undefined) {
    if (!Array.isArray(r.controls)) problems.push('Controls are a list.');
    else if (r.controls.some((c) => !c || !HIERARCHY.includes(c.level))) problems.push('Every control names a level of the hierarchy of controls.');
  }
  return problems;
}

export function describeRisk(r) {
  const inherent = riskScore(r.inherent_likelihood, r.inherent_severity);
  const residual = riskScore(r.residual_likelihood, r.residual_severity);
  return {
    inherent: { likelihood: r.inherent_likelihood, severity: r.inherent_severity, score: inherent, band: riskBand(inherent) },
    residual: residual === null ? null : { likelihood: r.residual_likelihood, severity: r.residual_severity, score: residual, band: riskBand(residual) },
    top_control: topControl(r.controls),
  };
}
