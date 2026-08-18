# Dash Fam: Project Scope

**Status:** Draft v0.2, open questions resolved
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
| Kiosk / wall-display mode | Wanted later, not now. Design keeps the door open (see 3). |
| Fine-grained child vs parent permissions | Everyone in the household is a trusted member. Revisit only if kids get accounts and it becomes a problem. |
| Push notifications | Nice to have, real complexity (service workers, permissions, delivery). Phase 3 at the earliest. |
| Recipe database with nutrition data | Meal planning in v1 is free-text meal names, not a recipe manager. |
| Budgeting or expense splitting | Different product. Do not let it creep in. |

---

## 2. Users

One household, five people:

| Person | Type | Signs in |
|---|---|---|
| Adult 1 | Member with account | Yes |
| Adult 2 | Member with account | Yes |
| Kid 1 | Member only | No |
| Kid 2 | Member only | No |
| Kid 3 | Member only | No |

Both adults have identical permissions in v1: read and write everything. No parent/admin distinction.

### Members and accounts are separate concepts

This is a load-bearing design decision. A **member** is a person in the household who can be assigned a chore, appear on an event, or be referenced anywhere in the app. An **account** is a login. The two are related but not the same.

- Every person is a `member` row.
- A member may optionally be linked to an auth user.
- Members without an account are fully functional as data. They just cannot log in.

**Future path:** any existing member can later be invited to claim a full account. When that happens their member row is linked to the new auth user and all their existing history (chores completed, events, list contributions) stays attached. This works because nothing in the schema references an auth user directly for domain data; everything references `member_id`. The invite flow is a Phase 5 or later concern, but the schema must support it from the first migration.

The corollary: never write a query, policy or foreign key that assumes `member_id` implies an auth user exists.

---

## 3. Surfaces

Phone first, desktop second. Both are first-class; neither is an afterthought.

- **Phone:** the primary interaction surface. Quick capture (add a grocery item, tick a chore) must work one-handed in seconds. Installable as a PWA so it sits on the home screen.
- **Desktop:** the planning surface. Wider layouts for the week view of the calendar and the meal plan. This is where someone sits down on a Sunday and sets up the week.

Design implication: build mobile layouts first, then expand to desktop. The week-grid views are the only components that genuinely need two distinct layouts.

### Wall display, later

A kitchen wall display is a want, not a v1 requirement. It is not built now, but two cheap decisions keep it viable:

1. The dashboard is its own route with its own layout, not a variant of the app shell. A future kiosk view becomes a third layout on the same route rather than a rewrite.
2. Dashboard content is read-only and composed of self-contained widgets (today's events, chores due, tonight's dinner, list summary). A kiosk view is then a re-arrangement of existing widgets.

The genuinely hard part of a wall display is a device staying authenticated indefinitely without a person present. That is deferred entirely, and it is worth knowing now that it will likely need a long-lived device session or a read-only display token rather than a normal user session.

---

## 4. Feature scope

All four feature areas are in the plan. They are **not** all in the first release. Shipping four half-features produces an app nobody trusts. The phasing below sequences them so each phase is independently usable.

**Target:** Phase 1 live and in daily household use by the first week of September 2026. Later phases are paced by available evenings with no fixed dates. See section 8.

### Phase 1: Foundation + Lists

The smallest thing that is genuinely useful daily.

- Auth: magic link sign in, household membership, protected routes
- Members: seed the five household members, two linked to accounts
- App shell: nav, layout, mobile and desktop
- **Lists:** create a list, add and edit items, tick items off, delete, clear completed. Real-time sync so two phones in the same house stay consistent.
- A minimal home dashboard: today's date, list summary

Exit criteria: the family stops using WhatsApp for the grocery list.

### Phase 2: Chores

- Define chores, including recurring schedules (daily, weekly, specific weekdays)
- Assign to any member, including the three kids who have no accounts
- Tick off; see what is due today and what is overdue
- Dashboard shows "your chores today"

Exit criteria: the rotation is visible without anyone having to argue about it.

### Phase 3: Calendar

- Household events: title, date and time or all-day, who it involves, optional location and notes
- Week view (desktop) and agenda list view (phone)
- Dashboard shows today and tomorrow
- **No Google Calendar sync.** Decided. Events live only in Dash Fam. If double entry turns out to be the thing that kills adoption, revisit with read-only import, which is far less work than two-way. Do not build sync speculatively.

Exit criteria: someone checks Dash Fam instead of asking "what's happening Saturday?"

### Phase 4: Meal planning

- Two slots per day: **lunch and dinner**. No breakfast slot.
- Assign a meal to a date and slot
- Meals are free text with an optional saved-meals list for repeat favourites
- Send ingredients to the grocery list. Simplest useful version: a text field of ingredients per saved meal that bulk-adds to a chosen list.
- Dashboard shows today's lunch and dinner

Note on the schema: model the slot as an enum-style column rather than separate lunch and dinner columns. Adding breakfast later then costs nothing.

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
| Hosting | Vercel for v1 | See 5.4. Cloudflare considered and deferred. |
| Styling | To be decided | Tailwind is the default expectation; needs its own decision record alongside a component library choice |
| Data access | To be decided | Supabase client directly vs a query layer. Decide before Phase 1 code. |

Each of these needs its own ADR. This document records the shape; the ADRs record the reasoning.

### 5.2 Data model, at scope level

Detailed schemas belong in a separate document. What matters for scope:

- A `households` table exists from day one, even with exactly one row. Every domain table carries `household_id`. This is the single decision that keeps multi-tenancy a possibility rather than a rewrite.
- `members` (people, five rows) and auth users (logins, two rows) are separate. A member optionally links to an auth user. All domain foreign keys point at `member_id`, never at an auth user.
- Row Level Security on every table, keyed to household membership. No table ships without policies. Note that the RLS predicate resolves an auth user to their member row, then to their household, so an account-less member has no direct bearing on policies.
- Meal slot is an enum-style column, not fixed lunch/dinner columns.

### 5.3 Auth decision: Supabase Auth

**Decision:** use Supabase Auth.

Reasoning:

- It is already in the stack. No second vendor, no second dashboard, no second bill.
- Supabase RLS policies read `auth.uid()` natively. This is the deciding factor: with Clerk you must issue a Supabase-compatible JWT and wire the integration correctly, and if you get it wrong your security model is wrong.
- Clerk's advantage is prebuilt UI and user management at scale. For a household of a handful of people, user management is not a problem worth paying to solve.

Revisit if: the app becomes multi-tenant with organisation invites and billing, or if the sign-in flows needed grow beyond what Supabase Auth handles comfortably.

**Sign-in method:** magic link only. No passwords to store, reset or leak, and no OAuth provider setup. The known tradeoff is that signing in on a new device requires email access at that moment. With two adults on their own phones this is a once-off cost, not a daily one. Sessions should be long-lived so nobody is re-authenticating every week.

Google OAuth was the alternative. Its main advantage would have been holding a Google grant already for calendar sync, and since calendar sync is out of scope that advantage disappears. If read-only calendar import is ever added, adding Google as a second provider at that point is straightforward.

### 5.4 Hosting: Vercel for v1, Cloudflare as an open door

**Decision:** Vercel for v1.

The comparison, honestly stated:

**Vercel**
- First-party Next.js support. Every Next.js feature works on day one because the framework and the platform are built by the same company.
- Zero configuration. Push to a branch, get a preview URL.
- The real risk is cost at scale. Bandwidth and function invocation pricing beyond the free tier is the standard complaint. A five-person household app is nowhere near that territory.

**Cloudflare (Workers / Pages)**
- Generally cheaper and more generous on bandwidth, with a genuinely global edge.
- Next.js on Cloudflare runs through an adapter (the OpenNext project) rather than native support. That layer works, but it is a layer: feature support can lag behind Next.js releases, and debugging a deploy problem means understanding the adapter as well as the framework.
- Verify current adapter support before committing, since this space moves quickly and anything written here may be out of date.

**Why Vercel wins for v1:** the goal is Phase 1 live by early September. Spending evenings on adapter compatibility instead of the grocery list feature is the wrong trade. Vercel's cost risk does not apply at this scale.

**Revisit if:** costs become real (they will not at five users), you want the app on Cloudflare for reasons beyond this project, or Cloudflare's Next.js support becomes first-class. Nothing in the codebase should hard-couple to Vercel, so keep platform-specific APIs out of application code. That keeps the move cheap.

---

## 6. Work to be done

### Planning and documentation (this project folder)

- [x] Project scope (this document)
- [ ] ADR-001: Next.js + Supabase stack
- [ ] ADR-002: Supabase Auth over Clerk, magic link only
- [ ] ADR-003: Vercel over Cloudflare for v1
- [ ] ADR-004: styling and component library
- [ ] ADR-005: data access pattern
- [ ] ADR-006: members and accounts as separate concepts
- [ ] Database schema, per feature area
- [ ] RLS policy design, including the account-less member case
- [ ] Auth flows: magic link sign in, household membership, future member invite
- [ ] Style guide: colour, type, spacing, component inventory
- [ ] Information architecture and navigation
- [ ] Environment and deployment setup

### Build

Phases 1 to 4 as set out in section 4. Each phase needs its own breakdown into features and tasks before work starts on it.

### Cross-cutting

- Seed and test data for the five-member household
- Error and empty states, defined once and reused
- Migration workflow for schema changes
- Basic testing strategy, sized to a personal project rather than aspirational
- Keep platform-specific APIs out of application code so hosting stays portable

---

## 7. Decisions on record

| # | Question | Decision | Notes |
|---|---|---|---|
| 1 | Household makeup | 2 adults with accounts, 3 kids as members only | Members and accounts modelled separately; kids can be invited to full accounts later |
| 2 | Sign-in method | Magic link only | No passwords, no OAuth setup. Long-lived sessions. |
| 3 | Google Calendar sync | None in v1 | Revisit with read-only import only if double entry blocks adoption |
| 4 | Meal slots | Lunch and dinner | Slot as an enum column so breakfast is a free addition |
| 5 | Hosting | Vercel for v1 | Cloudflare cheaper but adapter-based; revisit later, keep code portable |
| 6 | Wall display | Deferred, designed for | Dashboard as its own route composed of read-only widgets |
| 7 | Timeline | Phase 1 by first week of September 2026 | Later phases unscheduled |

### Deliberately left open

These do not block Phase 1 planning but need answers before Phase 1 code:

- Styling approach and whether to adopt a component library
- Data access pattern: Supabase client directly in server components versus a query layer
- Test strategy scope

---

## 8. Timeline

Phase 1 target: **first week of September 2026**. From 13 August that is roughly three weeks of evenings.

What has to be true to hit it:

- Documentation for Phase 1 only. Do not write the calendar schema or the meal-planning ADR before Phase 1 ships. Those documents will be better written after the first phase has taught you something.
- The two open items above (styling, data access) get decided quickly and cheaply rather than researched exhaustively. Either choice, made now, beats the better choice made in two weeks.
- Lists is the whole scope. Auth, shell, lists, a thin dashboard. If something must be cut to hit the date, cut the dashboard.
- Deploy to Vercel in week one, not week three. An app that has never been deployed is not three weeks from being deployed.

Phases 2 to 4 are paced by available evenings with no target dates. Setting dates for them now would be inventing information.

### Immediate next steps

1. ADRs 001 to 003 (stack, auth, hosting) as short records of what section 5 already decides
2. Database schema for households, members, lists and list items
3. RLS policy design for those tables
4. Decide styling and data access, timeboxed
5. Break Phase 1 into features and tasks
