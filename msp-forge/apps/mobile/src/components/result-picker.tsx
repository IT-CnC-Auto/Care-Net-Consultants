import type { FindingResult } from '@/lib/types';
import { resultTone } from '@/theme/tokens';

import { Chip, ChipRow } from './ui';

export const RESULT_LABEL: Record<FindingResult, string> = { pass: 'Pass', fail: 'Fail', na: 'N/A', observe: 'Observe' };

export const RESULT_TONE: Record<FindingResult, { bg: string; fg: string }> = resultTone;

export function ResultPicker({ value, onChange, itemLabel }: { value: FindingResult | null; onChange: (r: FindingResult) => void; itemLabel?: string }) {
  return (
    <ChipRow>
      {(['pass', 'fail', 'na', 'observe'] as const).map((r) => (
        <Chip
          key={r}
          label={RESULT_LABEL[r]}
          selected={value === r}
          tone={RESULT_TONE[r]}
          onPress={() => onChange(r)}
          accessibilityLabel={`${RESULT_LABEL[r]}${itemLabel ? ` for ${itemLabel}` : ''}`}
        />
      ))}
    </ChipRow>
  );
}
