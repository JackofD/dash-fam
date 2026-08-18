# Dash Fam — Features: Phase 1 — Foundation & Lists

This file is generated from the source document (00-project-scope.md, section 4, Phase 1). Each Feature represents a business outcome, kept deliberately coarse. Task-level breakdown is a separate later step.

---

## Project scaffold & deployment pipeline

**ID:** F-01
**Phase:** Phase 1 — Foundation & Lists
**Section:** Foundation
**Source Items:** scope §4 Phase 1 (foundation), 06-environment-setup.md
**Owner:** Deshen

### What are we trying to achieve?
A Next.js app that is version-controlled, checked on every change, and deploying to production automatically, before any feature code exists.

### Why does it matter?
Deploying early is the single discipline the plan leans on (ADR-003, scope timeline). An app that has never been deployed is not close to being deployable.

### Who is affected?
Deshen as the sole developer; the household as the eventual audience of the deployed app.

### What should change?
From nothing to a running empty app on a production URL, openable on a phone, with a repo and CI in place.

### What is in scope?
Scaffold (Next.js, TypeScript, Tailwind, App Router), folder structure per env doc §4, GitHub repo, minimal CI (lint, typecheck, build), Vercel connection and first production deploy.

### What is out of scope?
Any Phase 1 feature logic. Supabase wiring (F-02). Automated feature tests (added under D-08 later).

### What does success look like?
A pull request runs CI green; merging to main deploys automatically; the empty app loads on a phone over the internet.

### What systems or areas are involved?
Local tooling, GitHub Actions, Vercel.

### Acceptance criteria
- App scaffolds and runs locally with the agreed folder structure.
- CI runs lint, typecheck and build on pull requests and passes.
- Vercel auto-deploys main to production and previews per branch.
- The production URL loads on a phone.

### Definition of Done
The empty app is live in production and the checklist steps 1–3, 8, 9, 10 of the env doc are ticked.

---

## Database schema, RLS & seed data

**ID:** F-02
**Phase:** Phase 1 — Foundation & Lists
**Section:** Foundation
**Source Items:** 01-schema-foundation-lists.md, 04-decisions-log.md (D-01, D-07, D-09)
**Owner:** Deshen

### What are we trying to achieve?
The four foundation tables (households, members, lists, list_items) with their policies, triggers, realtime and the five-member seed, applied by migration locally and to production.

### Why does it matter?
RLS is the security backbone of the whole app; every later feature depends on this being correct and default-deny.

### Who is affected?
Every feature that reads or writes data; the household, whose data isolation depends on the policies.

### What should change?
From an empty database to a fully policied schema with the real household, five members and a grocery list seeded.

### What is in scope?
All SQL from the schema doc with the D-01 timezone, D-07 theme-preference and D-09 sort_position changes folded in; the current_household_id helper; updated_at and household-stamping triggers; RLS on all four tables; realtime publication; seed migration.

### What is out of scope?
Chores, calendar and meal tables (later phases). Item assignee (deferred, D-03). Application code.

### What does success look like?
`supabase db reset` builds the schema and seed cleanly; a user from no household sees zero rows on every table.

### What systems or areas are involved?
Supabase Postgres, migrations, RLS.

### Acceptance criteria
- All four tables, functions, triggers and policies apply via a single init migration.
- Seed creates the household, five members (two with invited_email) and the grocery list.
- The negative RLS case is verified: no-household user returns zero rows everywhere.
- Migrations push cleanly to the production project.

### Definition of Done
Schema and seed are live in both local and production Supabase, verified against the schema doc's migration order.

---

## Authentication & household access

**ID:** F-03
**Phase:** Phase 1 — Foundation & Lists
**Section:** Foundation
**Source Items:** scope §4 (auth, members), 02-auth-flow.md, D-02, D-04
**Owner:** Deshen

### What are we trying to achieve?
Magic-link sign-in that resolves a person to their household member, protects every route, and cleanly turns away anyone who is not a member.

### Why does it matter?
Nothing in the app works until an authenticated user resolves to a member; access control is the gate on all household data.

### Who is affected?
The two adults who sign in; any stranger who reaches the app.

### What should change?
From an open app to one where the two adults sign in by email link and land in their household, and non-members see a dedicated no-access screen.

### What is in scope?
Sign-in screen and callback, magic-link (PKCE) flow, the signup trigger that links member by invited_email, SSR cookie session with ~90-day lifetime, middleware route protection, the /no-household screen.

### What is out of scope?
Passwords, OAuth, global sign-out (D-11), the future member-invite flow.

### What does success look like?
An adult signs in via email link and sees their household; a non-member email signs in and sees only the no-access screen.

### What systems or areas are involved?
Supabase Auth, middleware, SSR clients, the members table.

### Acceptance criteria
- Magic link signs a known adult in and links their member row on first login.
- Logged-out visitors to any protected route are redirected to sign-in.
- An authenticated non-member sees /no-household and no data.
- Sessions persist for roughly 90 days without re-auth.

### Definition of Done
Both adults can sign in on their own phones and reach their household; the no-access path is verified.

---

## App shell, navigation & theming

**ID:** F-04
**Phase:** Phase 1 — Foundation & Lists
**Section:** Foundation
**Source Items:** scope §4 (app shell), 03-style-guide.md, 05-information-architecture.md, D-07
**Owner:** Deshen

### What are we trying to achieve?
The navigation frame and visual system the app lives in: bottom tabs on phone, side rail on desktop, the style-guide tokens applied, and light/dark theming with a manual override.

### Why does it matter?
Every screen renders inside this. Getting the shell and tokens right once means features are assembly, not reinvention.

### Who is affected?
Everyone using the app, on both phone and desktop.

### What should change?
From bare pages to a consistent, themed, navigable shell with the design tokens, fonts and member-avatar component in place.

### What is in scope?
AppShell layout (bottom tab bar / side rail), top bar with avatar menu, Tailwind token setup from the style guide, Bricolage + Inter fonts, MemberAvatar with the ring rule, system-following theme plus the manual light/dark toggle, shared loading/empty/error states.

### What is out of scope?
The dashboard content (F-05) and lists content (F-06). Tabs for later-phase features (they appear when those phases land).

### What does success look like?
Navigating between Home and Lists works on phone and desktop; switching theme works and persists; the app looks like the style guide in both themes.

### What systems or areas are involved?
Frontend, Tailwind config, next/font, shadcn/ui components, members table (theme preference).

### Acceptance criteria
- Bottom tabs (phone) and side rail (desktop) navigate between Home, Lists and Settings.
- Design tokens and fonts match the style guide in light and dark.
- Manual theme toggle persists to the member row and avoids a load flash.
- MemberAvatar renders the five colours correctly with the ring and initials rules.

### Definition of Done
The shell is deployed, navigable and correctly themed on both surfaces, with shared states defined once.

---

## Lists & real-time items

**ID:** F-05
**Phase:** Phase 1 — Foundation & Lists
**Section:** Lists
**Source Items:** scope §4 (Lists), 01-schema §3.3–3.4, 05-IA §3.2–3.3
**Owner:** Deshen

### What are we trying to achieve?
The core of Phase 1: creating and managing lists and their items, ticking off, clearing completed, with two devices staying in sync live.

### Why does it matter?
This is the feature that displaces WhatsApp for the grocery list. If nothing else ships, this must.

### Who is affected?
The whole household, daily.

### What should change?
From no way to share a list to a fast, live, shared list experience surfaced first on the grocery list.

### What is in scope?
Lists index, list detail, QuickAdd, add/edit/tick/delete items, clear completed, archive a list, real-time sync with optimistic updates reconciled by id, via the query/action layer (ADR-005).

### What is out of scope?
Item assignees (D-03), search, an archived-lists browse view (deferred, IA §6).

### What does success look like?
Two phones on the same list see each other's changes within a second; adding several items in a row is fast and one-thumbed.

### What systems or areas are involved?
Frontend, Server Actions, query layer, Supabase Realtime, RLS.

### Acceptance criteria
- Create, rename and archive lists; add, edit, tick and delete items; clear completed.
- QuickAdd keeps focus so multiple items go in quickly.
- Changes propagate live between two sessions without a refresh.
- Empty and loading states render, never a blank or broken screen.

### Definition of Done
The grocery list is usable end to end on phone and desktop, live-syncing, and the household could rely on it.

---

## Home dashboard (minimal)

**ID:** F-06
**Phase:** Phase 1 — Foundation & Lists
**Section:** Lists
**Source Items:** scope §4 (minimal home dashboard), 05-IA §3.1
**Owner:** Deshen

### What are we trying to achieve?
A light landing screen that shows today's date and a grocery snapshot, built from reusable widget cards.

### Why does it matter?
It is what makes Dash Fam a dashboard rather than a list app, and it is the frame later phases hang their summaries on.

### Who is affected?
Everyone, as the first thing seen on opening the app.

### What should change?
From landing straight into a list to a one-glance home with the date and outstanding grocery items.

### What is in scope?
Home route, greeting and date in the household timezone (D-01), a grocery snapshot widget linking to the full list, the DashboardWidget pattern with space reserved for later widgets.

### What is out of scope?
Chores, events and meal widgets (later phases). A wall-display/kiosk layout (deferred).

### What does success look like?
Opening the app shows today's date and the top outstanding grocery items, tapping through to the list.

### What systems or areas are involved?
Frontend, query layer, the lists data.

### Acceptance criteria
- Home shows the correct local date for the household.
- A grocery snapshot shows a count and the first outstanding items.
- Built as DashboardWidget cards so later widgets slot in without a rebuild.
- Renders sensibly when the grocery list is empty.

### Definition of Done
Home is the deployed landing screen with the date and grocery snapshot working.

---

## Settings: people, appearance & sign-out

**ID:** F-07
**Phase:** Phase 1 — Foundation & Lists
**Section:** Lists
**Source Items:** 05-IA §3.4, D-06, D-07, D-11
**Owner:** Deshen

### What are we trying to achieve?
A settings screen to manage the five people (name and colour), set the theme, and sign out.

### Why does it matter?
People need names and distinct colours for the member system to mean anything, and a reachable sign-out is the mitigation for long-lived sessions.

### Who is affected?
The whole household; the two adults who can edit.

### What should change?
From fixed seed data to editable member names and colours, a theme control, and a way to sign out.

### What is in scope?
People list with editable name and the constrained five-colour picker (showing which colours are taken, D-06), appearance control for system/light/dark (D-07), per-device sign-out (D-11).

### What is out of scope?
Global sign-out (D-11), the member-invite flow, a free colour wheel (D-06).

### What does success look like?
An adult renames a member, changes a colour without collisions, switches theme, and signs out.

### What systems or areas are involved?
Frontend, Server Actions, members table.

### Acceptance criteria
- Member name and colour are editable; the picker prevents two members sharing a colour.
- Theme preference persists and takes effect.
- Sign-out ends the session on that device.
- Changes respect RLS (household-scoped only).

### Definition of Done
Settings is deployed with people editing, theme control and sign-out all working.
