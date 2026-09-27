import { View } from 'react-native';

import { LOCKED_FOOTER } from '@/lib/constants';
import { formatDate } from '@/lib/dates';
import { voicePreviewLine } from '@/lib/report';
import type { Report } from '@/lib/types';
import { brand, space } from '@/theme/tokens';

import { RiskBadge } from './risk';
import { Card, Notice, Pill, SectionTitle, Txt } from './ui';

export function DraftLabel({ label }: { label: string }) {
  return (
    <View style={{ backgroundColor: brand.gold, padding: space.md, borderRadius: 10 }} accessibilityRole="alert">
      <Txt variant="bodyStrong" color={brand.ink}>
        {label}
      </Txt>
    </View>
  );
}

export function ReportView({ report }: { report: Report }) {
  const c = report.content;
  return (
    <View style={{ gap: space.md }}>
      {report.status !== 'issued' ? <DraftLabel label={c.label} /> : <Notice tone="success" title="Issued">{`Signed by ${report.signed_by ?? ''} on ${formatDate(report.signed_at)}.`}</Notice>}
      <Card>
        <Txt variant="label" muted>
          {report.source === 'ai_assistive' ? 'AI assisted draft' : 'Template draft'} · Version {report.version}
        </Txt>
        <Txt variant="bodyStrong">{c.title}</Txt>
        <Txt>{c.executive_summary}</Txt>
        <Pill label={voicePreviewLine(c.voice_notes)} tone={c.voice_notes.missing ? 'warning' : 'success'} />
      </Card>
      {c.findings.length ? (
        <>
          <SectionTitle>Findings</SectionTitle>
          {c.findings.map((f) => (
            <Card key={f.finding_id}>
              <Txt variant="label" muted>
                {f.area ?? 'Area'} · {f.result}
              </Txt>
              <Txt variant="bodyStrong">{f.item ?? f.note ?? 'Finding'}</Txt>
              {f.note && f.item ? <Txt variant="small">{f.note}</Txt> : null}
              <Txt variant="tiny" muted>
                {f.photos.length} photos{f.voice_notes.length ? ` · ${f.voice_notes.join(', ')}` : ''}
                {f.kernel_ref ? ` · Ref ${f.kernel_ref}` : ''}
              </Txt>
            </Card>
          ))}
        </>
      ) : null}
      {c.claims.length ? (
        <>
          <SectionTitle>Legal and method references</SectionTitle>
          {c.claims.map((cl, i) => (
            <Txt key={i} variant="small">
              {cl.text} ({cl.kernel_ref})
            </Txt>
          ))}
        </>
      ) : null}
      {c.uncited.length ? (
        <Notice tone="warning" title="Statements without a reference">
          {`${c.uncited.length} statement${c.uncited.length > 1 ? 's have' : ' has'} no reference yet and will not appear as a legal claim until one is added.`}
        </Notice>
      ) : null}
      {c.risk_register.length ? (
        <>
          <SectionTitle>Risk register</SectionTitle>
          {c.risk_register.map((r) => (
            <Card key={r.risk_id}>
              <Txt variant="bodyStrong">{r.hazard}</Txt>
              <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
                <RiskBadge prefix="Inherent" score={r.inherent.score} />
                <RiskBadge prefix="Residual" score={r.residual?.score ?? null} />
              </View>
            </Card>
          ))}
        </>
      ) : null}
      {c.corrective_actions.length ? (
        <>
          <SectionTitle>Corrective actions</SectionTitle>
          {c.corrective_actions.map((a) => (
            <Txt key={a.id} variant="small">
              {a.description} Owner {a.owner}, due {formatDate(a.due_on)}.
            </Txt>
          ))}
        </>
      ) : null}
      <Txt variant="tiny" muted style={{ textAlign: 'center' }}>
        {LOCKED_FOOTER}
      </Txt>
    </View>
  );
}
