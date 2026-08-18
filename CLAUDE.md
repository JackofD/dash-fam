# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current state: planning, not built yet

This repo currently contains **only planning documents** under `project-docs/` — there is no application code, no `package.json`, and no `supabase/` directory yet. The design is fully specified and all open decisions are resolved; the next step is scaffolding the app per `project-docs/06-environment-setup.md`. When you start writing code, follow that runbook rather than inventing structure.

The docs are the source of truth. Precedence when they conflict: **`04-decisions-log.md` overrides "Open items" in docs 00–03**, and the seven ADRs (`project-docs/ADRs/`) are the record for the big architectural calls.

## What Dash Fam is

A private, single-household web app: shared lists, chores, calendar, and meal planning for one family of five (2 adults with logins, 3 kids without). Phone-first PWA, desktop as the planning surface. Shipped in phases — **Phase 1 is Foundation + Lists only** (auth, app shell, lists, thin dashboard). Do not build ahead into chores/calendar/meals; their schemas and ADRs are intentionally deferred until their phase.

Guiding principle: low friction beats feature depth. Adding a list item must take seconds; if it takes more than three taps the app has failed.

## Stack

- **Next.js (App Router)** + **TypeScript strict**, `src/` dir, import alias `@/*`
- **Supabase** Postgres + Auth (magic link only, PKCE) + Realtime
- **Tailwind + shadcn/ui** (components added per-screen, not bulk-installed)
- **npm**, **Vercel** hosting (auto-deploy: `main` → prod, branches → previews)
- Local dev DB via **Supabase CLI + Docker**

## Commands (once scaffolded)

```bash
npm run dev            # Next dev server
npm run lint           # ESLint
npx tsc --noEmit       # typecheck
npm run build          # production build (also the CI gate)
npm run test           # RLS + critical-path tests (added under D-08; see Testing)

supabase start         # boot local Postgres/Auth/Realtime in Docker
supabase db reset      # rebuild local DB from migrations + seed.sql (repeatable)
supabase migration new <name>   # create a new migration file
supabase db push       # apply local migrations to the linked prod project
```

CI (on PRs) runs `npm run lint`, `npx tsc --noEmit`, `npm run build`, and the tests once they exist. Keep them all green.

## Deploy early

Per ADR-003 and the env-setup checklist (step 10), **deploy the empty app to production before building features**, not at the end. Connect GitHub to Vercel and ship the scaffold to a live URL in week one. An app that has never been deployed is not close to being deployable. Every branch gets a preview; `main` is production.

## Architecture rules that span files

These are the load-bearing decisions. Read the referenced doc before working in that area.

- **Members vs accounts are separate concepts** (ADR-006, scope §2). A `member` is a person; an `account` is an auth login. Three of five members have no account. **All domain foreign keys reference `members.id`, never `auth.users`.** Never write a query, policy, or FK that assumes a `member_id` implies an auth user exists. This is what lets kids get accounts later without a rewrite.
- **`household_id` on every domain table** from the first migration (scope §5.2), even with one household. This keeps multi-tenancy a future migration rather than a rewrite. On `list_items` it is **denormalised and maintained by a DB trigger** — never trust the client to send it.
- **RLS is the security boundary, not app code** (schema `01-schema-foundation-lists.md` §5, env-setup §10). Every table has RLS enabled and per-operation policies keyed to `current_household_id()` (a `security definer` function — see §4.1 of the schema doc for the recursion trap and why `set search_path`/`stable` are mandatory). App code trusts RLS; do not reimplement household filtering in queries. The `members` insert/update policies deliberately block linking `user_id` client-side — that is privilege escalation.
- **Reads via a thin query layer, writes via Server Actions** (ADR-005). `lib/queries/` holds typed read functions; `lib/actions/` holds all mutations. No Supabase client calls scattered in components. Not an ORM — just a folder of functions that grows with need.
- **Three Supabase clients, one cookie** (ADR-007, env-setup §6): `lib/supabase/client.ts` (browser + realtime), `server.ts` (server components/actions), `middleware.ts` (session refresh). `src/middleware.ts` only refreshes the session and bounces logged-out users to `/sign-in` — it is not the authorization boundary.
- **Realtime** (schema §6): lists sync between devices. Optimistic local updates must reconcile with incoming realtime events **by id** to avoid double-apply. Delete payloads carry only the primary key.
- **Keep platform-specific (Vercel) APIs out of app code** (ADR-003) so the hosting move stays cheap.
- The **service role key** bypasses RLS and must never reach the browser or Phase 1 code.

## Auth & access (see `02-auth-flow.md`, ADR-002)

Magic link is the only sign-in method (no passwords, no OAuth), over the PKCE flow. `@supabase/ssr` uses PKCE by default — don't override it.

- **Linking happens by email allowlist.** The two adult members are seeded with an `invited_email`. A `security definer` trigger on new `auth.users` (auth §3.2) matches the new user's email to a member's `invited_email` and sets that member's `user_id`. No match means the user stays unlinked and gets no access. Linking is never a client-side write.
- **`invited_email` is write-once seed data** (D-10). If an adult later changes their auth email the link persists via `user_id`; do not try to keep `invited_email` in sync.
- **Access is strict and enforced at the DB.** An authenticated user who resolves to no household (`current_household_id()` is null) is denied every row by RLS. The UI surfaces this as a dedicated `/no-household` screen with a sign-out button (D-02) — not a redirect loop to sign-in, and not per-page empty-state handling.
- **The sign-in screen never reveals membership** (auth §4). It sends a link to any email entered and always shows "check your email". Denial happens at the data layer, not by refusing to send.
- **Sessions are long, ~90 days** (D-04), so nobody re-authenticates weekly. The tradeoff (a lost unlocked phone keeps access) is accepted; keep sign-out easy to reach.
- **Per-device sign-out only in v1**; no global "sign out everywhere" (D-11). Confirm Supabase's magic-link/email rate limiting is enabled (D-12), since the sign-in screen sends to any address typed.

## Schema conventions (see `01-schema-foundation-lists.md`)

- UUID PKs (`gen_random_uuid()`); `timestamptz` always, store UTC; `snake_case` plural tables.
- Enums are `text` + `CHECK`, **not** Postgres `ENUM` types (easier to alter).
- Delete strategy: hard-delete `list_items`; soft-delete `lists` (`archived_at`); members are never deleted, only `deactivated_at`.
- Ordering column is `sort_position` (`double precision`, float-gap reordering) — renamed from `position` per D-09.
- "Today" uses a **fixed household timezone** (`households.timezone`, `Africa/Johannesburg`, D-01), not UTC or the browser zone.
- Schema changes are **always a new migration file**, never a manual edit in Studio. Migrations that have hit prod are append-only.
- **Seed data** (schema §7): one household (fixed id), five members (two with `invited_email` set, `user_id` null until first sign-in), and one grocery list (`kind = 'grocery'`). Verify with `supabase db reset`.

## Testing (D-08)

Pragmatic, not exhaustive. The one thing that must be tested rather than eyeballed is **RLS**, because its failures are silent. Cover the policies including the **negative case** — a user from no household (and later, from another household) sees zero rows on every table — plus a few critical flows (sign-in resolves to a household, add item, tick item). No pursuit of broad coverage against the September target. Add these as the `npm run test` CI step.

## Design tokens (see `03-style-guide.md`)

Semantic CSS custom properties on `:root`/`.dark`, consumed via Tailwind — components reference tokens (`--color-primary`), never hex. Primary is violet `#6D48E5`. Member colours come from a constrained five-colour palette (coral/amber/emerald/azure/violet, D-06); two members can't share one, so the picker must show which are taken. Display font Bricolage Grotesque + body Inter via `next/font`. Theme is `system|light|dark` persisted per member (D-07), read **server-side** to avoid a theme flash on load.

- **Member colour ring rule** (style guide §3.2): every member dot and avatar carries a hairline ring (`1px inset rgba(0,0,0,.10)` light, `rgba(255,255,255,.15)` dark). This gives each shape its own boundary so the fill colour need not clear the contrast floor on its own — it's the fix for amber, applied uniformly. Centralise it in `MemberAvatar`/`MemberDot`.
- **Avatar initials** (§3.3): white on four members; **near-black on amber** (white on amber is only 2.0:1). This is the one per-colour exception.
- **Accessibility floor** (§6): tap targets ≥ 44×44px, focus rings always visible (never removed), colour is never the only signal (pair with icon/label/strikethrough), respect `prefers-reduced-motion`.

## Routes & phasing (see `05-information-architecture.md`)

Phase 1 ships `/`, `/lists`, `/lists/[listId]`, `/settings`, `/sign-in`, `/auth/callback`, `/no-household`. Nav: bottom tab bar (phone) / side rail (desktop), showing only Home + Lists until later phases land — no disabled "coming soon" tabs. Five is the tab-bar ceiling and the final feature set is exactly five; nothing new goes top-level. The add pattern: inline QuickAdd for list items; Sheet (phone) / Dialog (desktop) for everything else. Every screen handles loading (Skeleton), empty (EmptyState), and error (Sonner toast) states centrally.
