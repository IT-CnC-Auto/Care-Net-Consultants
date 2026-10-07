// The kernel's inspection templates in the local store. Kept apart from the
// React hooks so the app state can call it without an import cycle.

import { kernel, type KernelBundle } from '@/lib/kernel';
import type { KindMap } from '@/lib/types';

import type { DataStore } from './data-store';

/**
 * Puts the kernel's templates into the store as server rows (the same ids as
 * supabase/seed/bee_inspect_kernel_templates.sql), once per kernel version.
 */
export async function ensureKernelTemplates(store: DataStore, b: KernelBundle = kernel()): Promise<void> {
  const key = 'kernel.templates.version';
  if ((await store.kvGet(key)) === b.kernel.version && store.get('template', b.templates[0]?.id)) return;
  const rows: { kind: 'template' | 'template_item'; record: KindMap['template'] | KindMap['template_item'] }[] = [];
  for (const t of b.templates) {
    rows.push({
      kind: 'template',
      record: {
        id: t.id,
        code: t.code,
        name: t.name,
        category: t.category,
        section_f_element_code: t.section_f_element_code,
        description: t.description,
        template_kind: t.kind,
        industry_code: t.industry_code,
        kernel_version: b.kernel.version,
        row_version: 1,
      },
    });
    for (const it of t.items) {
      rows.push({ kind: 'template_item', record: { id: it.id, template_id: t.id, ordinal: it.ordinal, section_label: it.section_label, prompt: it.prompt, kernel_ref: it.kernel_ref, source_ref: it.src, row_version: 1 } });
    }
  }
  await store.putServerMany(rows);
  await store.kvSet(key, b.kernel.version);
}
