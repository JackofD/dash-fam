# Dash Fam: Project Scope

**Status:** Draft v0.1
**Last updated:** 2026-08-13
**Owner:** Deshen Padayachee

---

## 1. What Dash Fam is

Dash Fam is a private web app that acts as the shared operating surface for a single household. It answers four questions that currently live in people's heads, group chats, and paper on the fridge:

1. Who is doing what, and when?
2. Whose turn is it to do the thing nobody wants to do?
3. What do we need from the shops?
4. What are we eating this week?

It is not a productivity suite, a social network, or a product for other families. It is a tool for one house, built to be genuinely used every day rather than admired once and abandoned.

### Principles

- **Low friction beats feature depth.** If adding a grocery item takes more than three taps, the app has failed and the family goes back to WhatsApp.
- **Shared state, no gatekeeper.** Anyone can add to anything. No approval flows.
- **Boring and reliable.** Household infrastructure. It should work offline-tolerantly and load fast on a mid-range phone on mobile data.
- **Built to be extended.** Scope is deliberately small now; the schema and structure should not fight the next feature.

### Explicit non-goals for v1

| Not doing | Why |
|---|---|
| Multi-tenancy / other families signing up | Single household. Adding tenancy later is a schema migration, not a rewrite, if households are modelled from day one (see 5.2). |
| Native mobile apps | Responsive web plus PWA install covers it. |
| Kiosk / wall-display mode | Not a stated need. Deferred to a possible v2. |
| Fine-grained child vs parent permissions | Everyone in the household is a trusted member. Revisit only if kids get accounts and it becomes a problem. |
| Push notifications | Nice to have, real complexity (service workers, permissions, delivery). Phase 3 at the earliest. |
| Recipe database with nutrition data | Meal planning in v1 is free-text meal names, not a recipe manager. |
| Budgeting or expense splitting | Different product. Do not let it creep in. |

---

## 2. Users

One household. Every member gets an account. All members have the same permissions in v1: read and write everything.

**Assumption to confirm:** number of members, and whether any of them are children who need their own login versus being represented as an assignable person without an account. This matters because it separates two concepts in the schema: a *user* (can log in) and a *member* (can be assigned a chore). Modelling them separately from the start costs almost nothing and avoids a painful migration.

---

## 3. Surfaces

Phone first, desktop second. Both are first-class; neither is an afterthought.

- **Phone:** the primary interaction surface. Quick capture (add a grocery item, tick a chore) must work one-handed in seconds. Installable as a PWA so it sits on the home screen.
- **Desktop:** the planning surface. Wider layouts for the week view of the calendar and the meal plan. This is where someone sits down on a Sunday and sets up the week.

Design implication: build mobile layouts first, then expand to desktop. The week-grid views are the only components that genuinely need two distinct layouts.

---

## 4. Feature scope

All four feature areas are in the plan. They are **not** all in the first release. Shipping four half-features produces an app nobody trusts. The phasing below sequences them so each phase is independently usable.

### Phase 1: Foundation + Lists

The smallest thing that is genuinely useful daily.

- Auth: sign in, household membership, protected routes
- App shell: nav, layout, mobile and desktop
- **Lists:** create a list, add and edit items, tick items off, delete, clear completed. Real-time sync so two phones in the same house stay consistent.
- A minimal home dashboard: today's date, list summary

Exit criteria: the family stops using WhatsApp for the grocery list.

### Phase 2: Chores

- Define chores, including recurring schedules (daily, weekly, specific weekdays)
- Assign to a member, or rotate on a schedule
- Tick off; see what is due today and what is overdue
- Dashboard shows "your chores today"

Exit criteria: the rotation is visible without anyone having to argue about it.

### Phase 3: Calendar

- Household events: title, date and time or all-day, who it involves, optional location and notes
- Week view (desktop) and agenda list view (phone)
- Dashboard shows today and tomorrow
- **Open question:** Google Calendar sync. Read-only import is significantly less work than two-way sync and probably covers the real need. Decide before starting this phase; do not build two-way sync speculatively.

Exit criteria: someone checks Dash Fam instead of asking "what's happening Saturday?"

### Phase 4: Meal planning

- Assign a meal to a date and slot (dinner is likely the only slot that matters; confirm)
- Meals are free text with an optional saved-meals list to pick from repeat favourites
- Send ingredients to the grocery list. Simplest useful version: a text field of ingredients per saved meal that bulk-adds to a chosen list.
- Dashboard shows tonight's dinner

Exit criteria: the Sunday planning session happens in the app.

---

## 5. Technical scope

### 5.1 Stack

| Layer | Choice | Note |
|---|---|---|
| Framework | Next.js (App Router) | Server components for data-heavy views, client components for interactive ones |
| Language | TypeScript, strict | |
| Database | Supabase Postgres | |
| Auth | Supabase Auth | See 5.3 |
| Realtime | Supabase Realtime | Needed for lists and chores |
| Hosting | Vercel | Assumption, confirm |
| Styling | To be decided | Tailwind is the default expectation; needs its own decision record alongside a component library choice |
| Data access | To be decided | Supabase client directly vs a query layer. Decide before Phase 1 code. |

Each of these needs its own ADR. This document records the shape; the ADRs record the reasoning.

### 5.2 Data model, at scope level

Detailed schemas belong in a separate document. What matters for scope:

- A `households` table exists from day one, even with exactly one row. Every domain table carries `household_id`. This is the single decision that keeps multi-tenancy a possibility rather than a rewrite.
- `profiles` (users who log in) and `members` (people who can be assigned things) are related but distinct concepts.
- Row Level Security on every table, keyed to household membership. No table ships without policies.

### 5.3 Auth decision: Supabase Auth

**Decision:** use Supabase Auth.

Reasoning:

- It is already in the stack. No second vendor, no second dashboard, no second bill.
- Supabase RLS policies read `auth.uid()` natively. This is the deciding factor: with Clerk you must issue a Supabase-compatible JWT and wire the integration correctly, and if you get it wrong your security model is wrong.
- Clerk's advantage is prebuilt UI and user management at scale. For a household of a handful of people, user management is not a problem worth paying to solve.

Revisit if: the app becomes multi-tenant with organisation invites and billing, or if the sign-in flows needed grow beyond what Supabase Auth handles comfortably.

**Sign-in method to confirm:** magic link is the lowest-friction option and avoids password handling entirely. Google OAuth is a reasonable alternative if everyone already has a Google account. Pick one for v1 rather than supporting both.

---

## 6. Work to be done

### Planning and documentation (this project folder)

- [x] Project scope (this document)
- [ ] ADR-001: Next.js + Supabase stack
- [ ] ADR-002: Supabase Auth over Clerk
- [ ] ADR-003: styling and component library
- [ ] ADR-004: data access pattern
- [ ] Database schema, per feature area
- [ ] RLS policy design
- [ ] Auth flows: sign in, household membership, invites
- [ ] Style guide: colour, type, spacing, component inventory
- [ ] Information architecture and navigation
- [ ] Environment and deployment setup

### Build

Phases 1 to 4 as set out in section 4. Each phase needs its own breakdown into features and tasks before work starts on it.

### Cross-cutting

- Seed and test data for a realistic household
- Error and empty states, defined once and reused
- Migration workflow for schema changes
- Basic testing strategy, sized to a personal project rather than aspirational

---

## 7. Open questions

Answers to these unblock the next documents.

1. How many household members, and do all of them need logins?
2. Magic link or Google OAuth for sign-in?
3. Google Calendar: no sync, read-only import, or two-way? (Needed before Phase 3.)
4. Meal planning: dinner only, or multiple slots per day?
5. Hosting: Vercel confirmed?
6. Is a wall-mounted display genuinely off the table, or something you want later? It changes nothing now, but it would inform layout decisions.
7. Any hard deadline or occasion driving this, or is it paced by available evenings?
