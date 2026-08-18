# Dash Fam: Style Guide

**Status:** Draft v0.1
**Last updated:** 2026-08-13
**Covers:** colour, per-member colour system, typography, spacing, radii, elevation, theming, component inventory
**Depends on:** 00-project-scope.md, 01-schema-foundation-lists.md, ADR-004
**Resolves:** schema open item 1 (member colour palette, light and dark)

---

## 1. Design direction

Bold and playful, phone-first, light and dark following the system setting. "Playful" here means confident colour, generous rounding, and clear large type, not clutter or noise. The app is used in seconds while standing in a kitchen, so hierarchy and tap targets matter more than decoration.

Three rules hold everything together:

1. **Colour carries meaning, not mood.** The primary is for actions. Member colours identify people. Everything else is neutral. Colour is never added just to fill space.
2. **One radius language.** Rounded, consistent, friendly. No mix of sharp and soft.
3. **Both themes are first-class.** Every token below has a light and a dark value. Nothing is designed in one theme and patched into the other.

All contrast figures in this document were computed against the WCAG formula and are stated as ratios. AA requires 4.5:1 for normal text, 3:1 for large or bold text and for UI component boundaries.

---

## 2. Colour tokens

Defined as CSS custom properties on `:root` (light) and `.dark` (dark), consumed through the Tailwind config (ADR-004). Naming is semantic, not literal: components reference `--color-primary`, never a hex.

### 2.1 Brand

| Token | Light | Dark | Notes |
|---|---|---|---|
| `primary` | `#6D48E5` | `#6D48E5` | The one action colour. Buttons, active states, focus rings. White text on it = 5.66:1, passes AA. |
| `primary-hover` | `#5B34D6` | `#7C59F0` | |
| `primary-text` | `#5B34D6` | `#B49BFF` | Primary used as text or link. Light 7.22:1 on white; dark 7.91:1 on the dark surface. |
| `accent` | `#FF7A59` | `#FF7A59` | Playful secondary, used sparingly for highlights and empty-state art. **Not for text on light backgrounds** (2.57:1). Use with dark text or as a fill only. |

The primary is a saturated violet: bold enough to feel playful, calm enough to sit behind daily use without tiring the eye.

### 2.2 Neutrals

| Token | Light | Dark |
|---|---|---|
| `background` | `#F6F6FB` | `#14141C` |
| `surface` | `#FFFFFF` | `#1E1E28` |
| `surface-raised` | `#FFFFFF` | `#26263280` |
| `border` | `#E6E6EF` | `#2E2E3A` |
| `text` | `#14141C` | `#ECECF2` |
| `text-muted` | `#5B5B6B` | `#A0A0B0` |

Verified body-text contrast: `text` on `surface` is 18.32:1 (light) and 15.57:1 (dark). `text-muted` is 6.66:1 (light) and 7.11:1 (dark). All clear AA for normal text with room to spare.

### 2.3 Status

| Token | Light | Dark | Use |
|---|---|---|---|
| `success` | `#159257` | `#3BD786` | Completion, confirmations |
| `warning` | `#B5710E` | `#F2B44C` | Overdue chores, gentle alerts |
| `danger` | `#D3382E` | `#FF6B61` | Destructive actions only |

Status colours are deliberately not reused as member colours, so "green" never ambiguously means both "done" and "that person".

---

## 3. Member colour system

The load-bearing colour decision. Five people, five colours that must stay distinguishable from each other and legible in both themes, used on avatars, calendar events, chore assignments and meal chips.

### 3.1 The five

| Member slot | Token | Hex | Avatar initial text |
|---|---|---|---|
| 1 | `member-coral` | `#E5484D` | white |
| 2 | `member-amber` | `#F2A93B` | near-black `#1A1300` |
| 3 | `member-emerald` | `#1F9D5F` | white |
| 4 | `member-azure` | `#2E7CF6` | white |
| 5 | `member-violet` | `#9257D6` | white |

The hex values are stored per member in `members.colour` (schema 3.2). These five are the seed defaults; the column allows changing them, but changing to an arbitrary colour risks the accessibility guarantees below, so the picker should offer these five rather than a free colour wheel in v1.

### 3.2 The ring rule, and why it exists

Member colours appear as filled dots, avatars and event blocks. As a bare fill on a surface, most of the five clear the 3:1 UI-contrast floor in both themes, but **amber against a white surface is only 2.0:1** and cannot be made to pass while still reading as amber; deepening it far enough turns it brown and kills the playful feel.

The fix is uniform and applies to every member fill, not just amber: a hairline ring.

- Light theme: `ring: 1px inset rgba(0,0,0,0.10)`
- Dark theme: `ring: 1px inset rgba(255,255,255,0.15)`

The ring gives every member shape its own boundary, which satisfies the component-contrast requirement regardless of the fill, and as a bonus makes all five dots look crisper. This is a single rule on the avatar and dot components, not a per-colour special case.

Verified fill-vs-surface ratios (for reference; the ring makes them moot but they show why only amber needed help):

| Colour | vs light surface | vs dark surface |
|---|---|---|
| coral | 3.91 | 4.68 |
| amber | 2.00 | 9.17 |
| emerald | 3.47 | 5.27 |
| azure | 3.94 | 4.65 |
| violet | 4.61 | 3.97 |

### 3.3 Avatar initials

Avatars are a colour-filled circle with the person's initial. Initials are large and bold, so the 3:1 threshold applies. White initials pass on four of the five; amber needs dark initials (white on amber is 2.0:1, dark on amber is 9.82:1). This one exception is why the table in 3.1 names the text colour per member. Everything else is white.

### 3.4 Soft tints

For larger coloured regions (a member's events tinted across a calendar day, a chore card background), use a tint rather than the full fill so text stays readable:

- Light: member colour at 12% opacity over `surface`, with normal `text` on top.
- Dark: member colour at 22% opacity over `surface`, with normal `text` on top.

Never put small body text directly on a full member fill.

---

## 4. Typography

Playful but legible. A characterful display face for headings paired with a highly readable body face.

| Role | Font | Notes |
|---|---|---|
| Display / headings | **Fraunces** or **Bricolage Grotesque** | Personality without novelty; both have variable weights. Pick one during setup. |
| Body / UI | **Inter** | Screen-optimised, excellent at small sizes, huge weight range. |
| Numeric (times, dates) | Inter with tabular figures (`font-variant-numeric: tabular-nums`) | Stops times jittering as they change. |

Both are open-source and available via the Next.js font pipeline (`next/font`), which self-hosts them, so there is no external font request and no layout shift. That matters for the phone-on-mobile-data case.

### Type scale

Steps, mobile first. Desktop bumps the top two sizes only.

| Token | Mobile | Desktop | Weight | Use |
|---|---|---|---|---|
| `display` | 30px | 36px | 600 | Screen titles |
| `h1` | 24px | 28px | 600 | Section headers |
| `h2` | 20px | 20px | 600 | Card titles |
| `body` | 16px | 16px | 400 | Default. Never below 16px for real content. |
| `small` | 14px | 14px | 400 | Metadata, captions |
| `tiny` | 12px | 12px | 500 | Labels, timestamps. Uppercase tracking optional. |

Line height 1.5 for body, 1.2 for display and headings.

---

## 5. Spacing, radii, elevation

### Spacing

A 4px base scale: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64. Tailwind's default scale already matches this, so no customisation needed. Screen gutters are 16px on phone, 24px on desktop.

### Radii

Rounded and consistent, the backbone of the playful feel.

| Token | Value | Use |
|---|---|---|
| `radius-sm` | 8px | Inputs, small chips |
| `radius-md` | 12px | Buttons, list items |
| `radius-lg` | 16px | Cards |
| `radius-xl` | 24px | Sheets, modals |
| `radius-full` | 9999px | Avatars, pills, dots |

### Elevation

Soft, low shadows in light; in dark, elevation is shown by a lighter surface rather than a shadow, because shadows read poorly on dark backgrounds.

- Light `shadow-card`: `0 1px 2px rgba(20,20,28,0.06), 0 4px 12px rgba(20,20,28,0.06)`
- Light `shadow-pop` (menus, sheets): `0 8px 30px rgba(20,20,28,0.12)`
- Dark: no shadow; step from `surface` to `surface-raised` and lean on `border`.

---

## 6. Interaction and accessibility rules

- **Tap targets** are at least 44x44px. Non-negotiable on a phone-first app; a grocery tick that misses is worse than useless.
- **Focus** is always visible: a 2px `primary` ring with a 2px offset. Never remove focus outlines.
- **Motion** is quick and slight: 150 to 200ms ease-out for most transitions. Respect `prefers-reduced-motion` and drop non-essential animation when it is set.
- **Colour is never the only signal.** Overdue is colour plus an icon or label; a completed item is struck through and dimmed, not merely recoloured. This also protects the member-colour system for anyone colour-blind, since names and initials always accompany the colour.
- **Theme** follows the system by default via `prefers-color-scheme`. A manual override can come later; it is not required for v1.

---

## 7. Component inventory

Everything Phase 1 needs, mapped to shadcn/ui primitives (ADR-004) so the build is assembly plus restyling, not invention. shadcn components are copied into the repo and restyled with the tokens above.

**From shadcn, restyled:** Button, Input, Checkbox, Dialog, Sheet (the phone add/edit surface), Dropdown Menu, Avatar, Badge, Skeleton, Sonner (toasts), Tabs, Separator, Form (with the data-access layer from ADR-005).

**Dash Fam components, built on those:**

| Component | Purpose |
|---|---|
| `MemberAvatar` | Colour circle + initial + the ring rule (section 3.2). One source of truth for showing a person. |
| `MemberDot` | Small colour dot for dense contexts (list item assignee, calendar). |
| `AppShell` | Nav frame. Bottom tab bar on phone, side rail on desktop. |
| `ListCard` / `ListItemRow` | The Phase 1 core. Row has content, tick, assignee dot, swipe-or-menu to delete. |
| `QuickAdd` | The single most-used control: an always-reachable add field. Must be one-thumb on phone. |
| `EmptyState` | Friendly illustration-led states, using `accent`. Defined once, reused (scope cross-cutting item). |
| `DashboardWidget` | Self-contained card for the home view (schema/scope: dashboard is composed of these, wall-display-ready). |

### 7.1 Priorities that fall out of the design

- `QuickAdd` and `ListItemRow` are the components that determine whether the app displaces WhatsApp. Build and polish these first; everything else can be rough at Phase 1 start.
- `MemberAvatar` centralises the ring rule and the amber exception, so the accessibility work lives in exactly one place.
- `EmptyState` and `Skeleton` exist from day one, because an app that looks broken while loading or when empty does not earn daily use.

---

## 8. Implementation notes

- Tokens live as CSS variables and are surfaced to Tailwind via `theme.extend.colors` referencing the variables, so class names read `bg-primary`, `text-muted`, `bg-member-coral`. This keeps the light/dark switch entirely in CSS with no JavaScript theme logic.
- Member colours are the exception to pure-semantic naming: they are indexed (`member-coral` etc.) because they map to stored data, not to roles.
- The five member hexes are the single source of truth shared between the seed migration (schema section 7) and the Tailwind config. Define them once and reference; do not copy the hex into two places.

---

## 9. Open items

1. **Display font.** Fraunces (a warmer serif) versus Bricolage Grotesque (a playful sans). Pick one by looking at both with the real app title. Low stakes, quick to swap via `next/font`.
2. **Manual theme toggle.** System-following is enough for v1. Decide later whether a manual light/dark override is worth the small state it adds.
3. **Member colour picker.** Whether v1 even lets people change their colour, or ships the five fixed. Fixed is simpler and protects accessibility; a constrained picker (these five only) is the natural middle ground.
4. **Illustration style for empty states.** The playful direction wants some character here. Can be as light as a few simple line drawings; defer until the shell exists.
