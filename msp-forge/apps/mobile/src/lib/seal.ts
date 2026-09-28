// Evidence seal (prompt B5 and section 8: GPS, time and inspector sealed in
// the evidence). The phone builds the same text as bi_evidence_seal
// (migration 060) and keeps its SHA 256 with the photo or voice note; the
// database computes the seal again at insert, so the two can be compared.
//
//   concat_ws('|', path, sha256, captured_at as YYYY-MM-DDTHH:MM:SS.ffffffZ (UTC),
//             lat as numeric(9,6) text or '', lng likewise, inspector id)

/** An ISO time as Postgres prints timestamptz in UTC with microseconds. */
export function sealTime(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) throw new RangeError('not a time');
  return d.toISOString().replace(/\.(\d{3})Z$/, '.$1000Z');
}

/** numeric(9,6)::text: six decimals; '' when there is no GPS fix. */
export function sealCoord(n: number | null | undefined): string {
  if (typeof n !== 'number' || !Number.isFinite(n)) return '';
  return n.toFixed(6);
}

export interface SealFields {
  path: string;
  sha256: string;
  capturedAt: string;
  lat: number | null;
  lng: number | null;
  inspectorId: string;
}

export function sealInput(f: SealFields): string {
  return [f.path, f.sha256, sealTime(f.capturedAt), sealCoord(f.lat), sealCoord(f.lng), f.inspectorId].join('|');
}

/** A storage path the bi_photo and bi_voice_note checks accept: <company>/<inspection>/<file>. */
export function evidencePath(companyId: string, inspectionId: string, fileName: string): string {
  const safe = fileName.replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120);
  return `${companyId}/${inspectionId}/${safe}`;
}

export function shortHash(hex: string | null | undefined): string {
  return hex ? `${hex.slice(0, 8)}…${hex.slice(-4)}` : '';
}
