import type { PersonRole } from './types';

/** Authorised person roles (decisions section 2): OHS Act 16(1), 16(2) and health and safety roles. */
export const PERSON_ROLE_LABEL: Record<PersonRole, string> = {
  s16_1: '16(1) Chief executive officer',
  s16_2: '16(2) Assigned person',
  she_manager: 'Health and safety manager',
  she_officer: 'Health and safety officer',
  she_rep: 'Health and safety representative',
  first_aider: 'First aider',
  fire_marshal: 'Fire marshal',
  construction_manager: 'Construction manager',
  other: 'Other role',
};

export const PERSON_ROLES = Object.keys(PERSON_ROLE_LABEL) as PersonRole[];
