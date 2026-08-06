# Care Net Consultants Design System

Brand and UI system for **Care Net Consultants (Pty) Ltd** — a South African workplace health consultancy — and its **Employee Operational Check-in Application** (internal tool where employees log daily operational check-ins).

Sources provided: brand colour spec (chat notes), logo/badge/pulse-icon PNGs and African triangle pattern assets in `uploads/`, the internal ATELIER.CNC brand skill (colour roles, font roles, pulse-line rules), and the cnc-brand-guidelines skill (voice pillars, mandatory taglines, approved/forbidden language, imagery rules). No codebase or Figma was provided — the check-in app UI kit is an original composition strictly in brand.

## Brand essence
- Red leads. White grounds. Charcoal carries the words.
- Signature devices: the **pulse line** (official PNG assets in `assets/pulse/`: standard, heart, protea, springbok, Ubuntu handshake variants in red and black; red on white or white on red, used once per surface with intent; never redrawn) and the **triangle pattern** (SA-flag-coloured geometric texture, low-contrast, behind content, 1–2 zones max).
- Ubuntu ethos. Internal tagline: *"I Am Because We Are"*. External tagline: *"Your Partner in Workplace Health"*.

## CONTENT FUNDAMENTALS
Canonical source: the cnc-brand-guidelines skill. Four voice pillars: clinical credibility, human warmth, Ubuntu presence, quiet confidence.
- **Mandatory taglines:** "Your Partner in Workplace Health" on every client-facing document; *"I am because we are."* as the Ubuntu close on internal documents (italic, centred, no quotation marks; never on the same line/block as the tagline). Regulator documents carry neither.
- **Approved language:** "worker/employee" not "patient"; "client" not "customer"; "medical/assessment" not "case"; "not medically fit for this task at this time" not "failed"; "medical surveillance" not "screening"; "declined" not "refused"; "participation" not "compliance" (about workers).
- **Never:** pass/fail, clean/dirty, "just", superlatives without proof, corporate Zoom-speak (stakeholder, synergy, leverage, touch point), "patient journey", "guys", unexplained acronyms.
- Dates DD/MM/YYYY. Person-first disability language.
- British English, South African register ("organisation", "colleague"). Currency in ZAR as `R`.
- Warm, direct, human — never corporate filler. Tight, concrete sentences. Second person ("How are you today?"), first-person-plural for the company ("we").
- **No hyphens or dashes of any kind** in copy — hard brand rule. Use commas, full stops, or restructure.
- Sentence case for body and UI labels; Bebas display headlines render uppercase by design.
- No emoji.
- Examples: "Good morning, Thandi. Ready to check in?" · "Your wellbeing matters. Three quick questions." · "Thank you. Your team lead has been notified."

## VISUAL FOUNDATIONS
- **Colour:** Red `#ED1B24` primary accent; charcoal `#1E1E1E` ink; white ground. Support colours sparingly: green `#007749` (growth/wellness, positive states), blue `#001489` (trust/clinical, info), yellow `#FFB81C` (energy, warnings). Greys: `#787878` muted text, `#F0F0F0`/`#F2F2F2` quiet panels. Support colours never compete with red.
- **Type:** Bebas Neue (display, large headlines/hero numbers, tracking +0.02em), Montserrat (headings/labels, 600–800), Open Sans (body, 15px/1.55). One face per role, never more.
- **Spacing:** 4px scale (`--space-1..8`: 4/8/12/16/24/32/48/64).
- **Backgrounds:** white pages; light-grey panels; triangle-pattern PNG bands as texture zones (footer bands, headers) at low visual weight; full-bleed red for hero/section-starter moments.
- **Corners:** 6/10/14px; pills for badges and tags. The logo's red plate uses modest rounding — cards echo that.
- **Cards:** white, 1px `#E2E2E2` border, 10px radius, soft shadow (`--shadow-card`). No coloured left-border accents.
- **Borders:** subtle `#E2E2E2`; strong charcoal only for emphasis.
- **Shadows:** two levels only — card and raised (modals). No inner shadows.
- **Animation:** restrained. 120–200ms ease-out fades/transforms. No bounces.
- **Hover:** buttons darken (red → `#C1272D`); links darken; cards lift slightly. **Press:** slight darken, no shrink.
- **Transparency/blur:** none in-product; pattern tints at low opacity only.
- **Imagery:** real workers in real SA workplaces, natural light, real colour, environmental portraits. Never stock "happy office workers", stethoscope-on-laptop clichés, or anything undignified. No clinical data ever (POPIA).
- **Pulse line:** red or white ONLY, once per surface, as a rule under a headline or a spine. Never decorative clutter, never in support colours.

## ICONOGRAPHY
No proprietary icon set was provided. Use **Lucide** (CDN) at 1.75px stroke, sized 16–24px, coloured `currentColor` — its clean geometric stroke matches the brand's flat geometry. Flagged as a substitution; replace if CNC supplies its own icons. No emoji, no unicode-glyph icons. Brand marks and patterns are PNGs in `assets/` — always copy/reference, never redraw.

## Known colour-spec discrepancies (resolved)
The brief's RGB and hex values disagreed in two places; hex + brand skill win: red = `#ED1B24` (not RGB 224/60/49), green = `#007749` (RGB 0/119/73; the hex "#007703" was a typo).

## Fonts
All three faces load from Google Fonts (`tokens/typography.css`). No font binaries were provided — supply licensed files if self-hosting is required.

## Index
- `styles.css` → `tokens/colors.css`, `tokens/typography.css`, `tokens/layout.css`
- `assets/` — logos (`logo-horizontal.png`, `logo-stacked.png`), badge marks (`badge-flag-*.png`, `badge-plain-*.png`), pulse icons (`assets/pulse/`), triangle patterns (also `pattern-line-1-4k.png`, `pattern-line-2-4k.png`) (`pattern-rows.png`, `pattern-groups.png`, `pattern-band-4k.png`, `pattern-circle.png`, `pattern-scatter-muted.png`, single triangles `triangle-*.png`), `dot-grid.png`
- `guidelines/` — foundation specimen cards (colors, type, spacing, brand devices)
- `components/core/` — Button, IconButton, Input, Select, Checkbox, Radio, Switch, Card, Badge, Tag, Tabs, Dialog, Toast, PulseLine, Logo, StatusChip
- `ui_kits/checkin_app/` — Employee Operational Check-in App screens (interactive `index.html`)
- `templates/` — reusable Design Component templates (if any)
- `SKILL.md` — agent skill entry point

## Intentional additions
- `PulseLine` — renders the official pulse icon PNGs (standard/heart/protea/springbok/handshake).
- `Logo` — img wrapper choosing horizontal/stacked lockup.
- `StatusChip` — check-in status indicator (core to the app's domain).
No component inventory was supplied, so the core set is authored per brand rules.
