// Risk and corrective action editors used on a checklist item.

import { useState } from 'react';
import { View } from 'react-native';

import { addDaysIso, formatDate, parseSaDate, todayIso } from '@/lib/dates';
import { CONTROL_LABEL, HIERARCHY, riskScore, validateRisk, type Control, type ControlLevel } from '@/lib/risk';
import type { CorrectiveAction, Risk } from '@/lib/types';
import { space } from '@/theme/tokens';

import { RiskBadge, RiskMatrix } from './risk';
import { Button, Card, Chip, ChipRow, Field, Notice, Txt } from './ui';

export function RiskEditor({ initial, onSave, onCancel }: { initial?: Risk; onSave: (r: Omit<Risk, 'id' | 'inspection_id' | 'area_id' | 'finding_id'>) => void; onCancel?: () => void }) {
  const [hazard, setHazard] = useState(initial?.hazard ?? '');
  const [consequence, setConsequence] = useState(initial?.consequence ?? '');
  const [il, setIl] = useState<number | null>(initial?.inherent_likelihood ?? null);
  const [is, setIs] = useState<number | null>(initial?.inherent_severity ?? null);
  const [rl, setRl] = useState<number | null>(initial?.residual_likelihood ?? null);
  const [rs, setRs] = useState<number | null>(initial?.residual_severity ?? null);
  const [controls, setControls] = useState<Control[]>(initial?.controls ?? []);
  const [problems, setProblems] = useState<string[]>([]);
  const inherent = riskScore(il, is);

  const toggleControl = (level: ControlLevel) =>
    setControls((cs) => (cs.some((c) => c.level === level) ? cs.filter((c) => c.level !== level) : [...cs, { level, description: '' }]));

  const save = () => {
    const input = { hazard, inherent_likelihood: il, inherent_severity: is, residual_likelihood: rl, residual_severity: rs, controls };
    const p = validateRisk(input);
    setProblems(p);
    if (p.length) return;
    onSave({
      hazard: hazard.trim(),
      consequence: consequence.trim() || null,
      inherent_likelihood: il as number,
      inherent_severity: is as number,
      controls: controls.map((c) => ({ level: c.level, description: (c.description ?? '').trim() })),
      residual_likelihood: rl,
      residual_severity: rs,
    });
  };

  return (
    <Card>
      <Txt variant="bodyStrong">Risk assessment (5 x 5)</Txt>
      <Field label="Hazard" value={hazard} onChangeText={setHazard} placeholder="What could cause harm" />
      <Field label="Consequence (optional)" value={consequence} onChangeText={setConsequence} placeholder="What harm, to whom" />
      <RiskMatrix
        label="Inherent risk (before controls)"
        likelihood={il}
        severity={is}
        onChange={(l, s) => {
          setIl(l);
          setIs(s);
          if (rl !== null && rs !== null && rl * rs > l * s) {
            setRl(null);
            setRs(null);
          }
        }}
      />
      <Txt variant="smallStrong">Controls (hierarchy of controls, highest first)</Txt>
      <ChipRow>
        {HIERARCHY.map((level) => (
          <Chip key={level} label={CONTROL_LABEL[level]} selected={controls.some((c) => c.level === level)} onPress={() => toggleControl(level)} />
        ))}
      </ChipRow>
      {HIERARCHY.filter((l) => controls.some((c) => c.level === l)).map((level) => (
        <Field
          key={level}
          label={CONTROL_LABEL[level]}
          value={controls.find((c) => c.level === level)?.description ?? ''}
          onChangeText={(t) => setControls((cs) => cs.map((c) => (c.level === level ? { ...c, description: t } : c)))}
          placeholder="Describe the control"
        />
      ))}
      <RiskMatrix
        label="Residual risk (after controls)"
        likelihood={rl}
        severity={rs}
        maxScore={inherent ?? 0}
        onChange={(l, s) => {
          setRl(l);
          setRs(s);
        }}
      />
      {rl !== null ? <Button title="Clear residual rating" kind="ghost" compact onPress={() => { setRl(null); setRs(null); }} /> : null}
      {problems.length ? <Notice tone="danger">{problems.join(' ')}</Notice> : null}
      <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
        <Button title="Save risk" onPress={save} />
        {onCancel ? <Button title="Cancel" kind="ghost" onPress={onCancel} /> : null}
      </View>
    </Card>
  );
}

export function RiskSummary({ risk, onEdit }: { risk: Risk; onEdit?: () => void }) {
  return (
    <Card>
      <Txt variant="bodyStrong">{risk.hazard}</Txt>
      {risk.consequence ? <Txt variant="small" muted>{risk.consequence}</Txt> : null}
      <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
        <RiskBadge prefix="Inherent" score={riskScore(risk.inherent_likelihood, risk.inherent_severity)} />
        <RiskBadge prefix="Residual" score={riskScore(risk.residual_likelihood, risk.residual_severity)} />
      </View>
      {risk.controls.map((c, i) => (
        <Txt key={i} variant="small">
          {CONTROL_LABEL[c.level]}
          {c.description ? `: ${c.description}` : ''}
        </Txt>
      ))}
      {onEdit ? <Button title="Edit risk" kind="ghost" compact onPress={onEdit} /> : null}
    </Card>
  );
}

export function ActionEditor({ initial, onSave, onCancel }: { initial?: CorrectiveAction; onSave: (a: { description: string; owner_name: string; due_on: string }) => void; onCancel?: () => void }) {
  const [description, setDescription] = useState(initial?.description ?? '');
  const [owner, setOwner] = useState(initial?.owner_name ?? '');
  const [due, setDue] = useState(initial ? formatDate(initial.due_on) : formatDate(addDaysIso(todayIso(), 7)));
  const [error, setError] = useState<string | null>(null);
  const save = () => {
    const d = parseSaDate(due);
    if (description.trim().length < 5) return setError('Describe the action (at least 5 characters).');
    if (owner.trim().length < 2) return setError('Name the owner.');
    if (!d) return setError('Give the due date as dd/mm/yyyy.');
    setError(null);
    onSave({ description: description.trim(), owner_name: owner.trim(), due_on: d });
  };
  return (
    <Card>
      <Txt variant="bodyStrong">Corrective action</Txt>
      <Field label="What must be done" value={description} onChangeText={setDescription} multiline />
      <Field label="Owner" value={owner} onChangeText={setOwner} placeholder="Name or role, for example the supervisor" />
      <Field label="Due date (dd/mm/yyyy)" value={due} onChangeText={setDue} keyboardType="numbers-and-punctuation" />
      <ChipRow>
        {[2, 7, 14, 30].map((n) => (
          <Chip key={n} label={`In ${n} days`} onPress={() => setDue(formatDate(addDaysIso(todayIso(), n)))} />
        ))}
      </ChipRow>
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <View style={{ flexDirection: 'row', gap: space.sm, flexWrap: 'wrap' }}>
        <Button title="Save action" onPress={save} />
        {onCancel ? <Button title="Cancel" kind="ghost" onPress={onCancel} /> : null}
      </View>
    </Card>
  );
}
