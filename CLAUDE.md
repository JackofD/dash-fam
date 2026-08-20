# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Dash Fam is

A private, single-household web app: shared lists, chores, calendar, and meal planning for one family of five (2 adults with logins, 3 kids without). Phone-first PWA, desktop as the planning surface. Shipped in phases — **Phase 1 is Foundation + Lists only** (auth, app shell, lists, thin dashboard). Do not build ahead into chores/calendar/meals; their schemas and ADRs are intentionally deferred until their phase.

Guiding principle: low friction beats feature depth. Adding a list item must take seconds; if it takes more than three taps the app has failed.

## Docs are the source of truth

`project-docs/` is a fully-specified design, not aspirational notes. Read the relevant doc before working in an area. Precedence when they conflict: **`04-decisions-log.md` (the D-NN decisions) overrides "Open items" in docs 00–03**, and the seven ADRs (`project-docs/ADRs/`) are the record for the big architectural calls. `06-environment-setup.md` is the runbook — follow it rather than inventing structure.

## Current state

- **F-01 done** — Next.js app scaffolded at the repo root, CI green, auto-deploying to Vercel. Routes exist as stubs that render a marker.
- **F-02 in progress** on `feature/f-02-supabase-setup-connection`, which now carries both halves: the schema (migration, `seed.sql`, pgTAP RLS suite, merged from `worktree-f-02-schema` / draft PR #3) and the connection wiring (three `src/lib/supabase/*.ts` factories, generated types, `src/middleware.ts`). Plans: `.plans/F-02-database-schema-rls-seed.md` and `.plans/F-02b-supabase-connection.md`.
- **`src/middleware.ts` refreshes the session only.** No redirects — a logged-out visitor is not yet bounced anywhere. That logic is F-03's.
- **`/debug/connection` is a temporary dev-only smoke page**, not part of the IA. It proves the round trip end to end and gets deleted in F-03.
- **F-03 (auth) is next** and is where `src/middleware.ts`, the sign-in flow, and `/auth/callback` get their real logic. The stubs say "lands in F-03" — respect that boundary; don't opportunistically fill them in.

## Commands

```bash
npm run dev            # Next dev server (Turbopack)
npm run lint           # ESLint — but see the caveat below
npx tsc --noEmit       # typecheck
npm run build          # production build (also the CI gate)
```

CI (`.github/workflows/ci.yml`, on PRs) runs `npm run lint`, `npx tsc --noEmit`, `npm run build`. Keep all three green. The pgTAP RLS suite is **not** in CI — it needs a live database, so it stays a local gate (see Database below). Wiring D-08's tests into CI arrives with F-03.

**Lint caveat:** `npm run lint` is bare `eslint`, which walks the whole tree including the nested git worktree at `.claude/worktrees/f-02-schema/`. Its generated `.next/types/` produces ~180 errors and ~3000 warnings that have nothing to do with your changes. To check your own work, scope it:

```bash
npx eslint "src/**/*.{ts,tsx}"
```

### Database

Docker is **not installed on this machine**, so the documented `supabase start` local stack is unverified and not the working loop. The F-02 branch instead drives the CLI against a throwaway *hosted* dev project over `--db-url`, via `scripts/supabase-remote.mjs`:

```bash
npm run db:push:dry        # connectivity check; applies nothing
npm run db:reset:remote    # replay all migrations + seed.sql from scratch (DESTRUCTIVE)
npm run db:reset:noseed    # same, without seed.sql
npm run test:remote        # pgTAP RLS suite
supabase migration new <name>
```

These read `SUPABASE_TEST_DB_URL` from `.env.local`. Use `db reset`, not `db push`, while iterating — `db push` records applied versions, so an edit to an already-pushed migration silently doesn't land. We deliberately do **not** run `supabase link`: with a destructive reset in the toolbox, a stale link is one command away from wiping the wrong database, so every invocation must name its target.

## Architecture rules that span files

These are the load-bearing decisions.

- **Members vs accounts are separate concepts** (ADR-006, scope §2). A `member` is a person; an `account` is an auth login. Three of five members have no account. **All domain foreign keys reference `members.id`, never `auth.users`.** Never write a query, policy, or FK that assumes a `member_id` implies an auth user exists. This is what lets kids get accounts later without a rewrite.
- **`household_id` on every domain table** from the first migration (scope §5.2), even with one household. This keeps multi-tenancy a future migration rather than a rewrite. On `list_items` it is **denormalised and maintained by a DB trigger** — never trust the client to send it.
- **RLS is the security boundary, not app code** (schema §5). Every table has RLS enabled and per-operation policies keyed to `current_household_id()` (a `security definer` function — see schema §4.1 for the recursion trap and why `set search_path`/`stable` are mandatory). App code trusts RLS; do not reimplement household filtering in queries. The `members` insert/update policies deliberately block linking `user_id` client-side — that is privilege escalation.
- **Reads via a thin query layer, writes via Server Actions** (ADR-005). `src/lib/queries/` holds typed read functions; `src/lib/actions/` holds all mutations. No Supabase client calls scattered in components. Not an ORM — just a folder of functions that grows with need.
- **Three Supabase clients, one cookie** (ADR-007, env-setup §6): `src/lib/supabase/client.ts` (browser + realtime), `server.ts` (server components/actions/route handlers), `middleware.ts` (session refresh). `src/middleware.ts` only refreshes the session and bounces logged-out users to `/sign-in` — it is not the authorization boundary.
- **Realtime** (schema §6): lists sync between devices, enabled per-table in the migration, never assumed on. Optimistic local updates must reconcile with incoming realtime events **by id** to avoid double-apply. Delete payloads carry only the primary key.
- **Keep platform-specific (Vercel) APIs out of app code** (ADR-003) so the hosting move stays cheap.
- The **service role key** bypasses RLS and must never reach the browser or Phase 1 code — and never gets a `NEXT_PUBLIC_` prefix.

Env vars are `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (see `.env.example`). Supabase's newer `sb_publishable_…` key is a drop-in for the anon key value; keep the documented variable *name* rather than renaming to match whatever a quickstart snippet uses.

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
- Schema changes are **always a new migration file**, never a manual edit in Studio. Migrations that have hit prod are append-only; the init migration is still freely editable because prod does not exist yet.
- **Seed data** (schema §7): one household (fixed id), five members (two with `invited_email` set, `user_id` null until first sign-in), and one grocery list (`kind = 'grocery'`). `seed.sql` still carries `TODO(F-02)` placeholder names/emails — **replace them before any production apply**, since `invited_email` is write-once.
- The `postgres` role owns the tables and is exempt from their RLS. Every RLS assertion must `set local role authenticated` first, or it passes vacuously while looking green.

## Testing (D-08)

Pragmatic, not exhaustive. The one thing that must be tested rather than eyeballed is **RLS**, because its failures are silent. Cover the policies including the **negative case** — a user from no household (and later, from another household) sees zero rows on every table — plus a few critical flows (sign-in resolves to a household, add item, tick item). Run the suite against both a seeded and an empty database, so "zero rows" proves a real denial and not an empty table. No pursuit of broad coverage against the September target.

## Design tokens (see `03-style-guide.md`)

Semantic CSS custom properties on `:root`/`.dark`, consumed via Tailwind — components reference tokens (`--color-primary`), never hex. Primary is violet `#6D48E5`. Member colours come from a constrained five-colour palette (coral/amber/emerald/azure/violet, D-06); two members can't share one, so the picker must show which are taken. Display font Bricolage Grotesque + body Inter via `next/font` (the scaffold still ships create-next-app's Geist — swapped in F-04). Theme is `system|light|dark` persisted per member (D-07), read **server-side** to avoid a theme flash on load.

- **Member colour ring rule** (§3.2): every member dot and avatar carries a hairline ring (`1px inset rgba(0,0,0,.10)` light, `rgba(255,255,255,.15)` dark). This gives each shape its own boundary so the fill colour need not clear the contrast floor on its own — it's the fix for amber, applied uniformly. Centralise it in `MemberAvatar`/`MemberDot`.
- **Avatar initials** (§3.3): white on four members; **near-black on amber** (white on amber is only 2.0:1). This is the one per-colour exception.
- **Accessibility floor** (§6): tap targets ≥ 44×44px, focus rings always visible (never removed), colour is never the only signal (pair with icon/label/strikethrough), respect `prefers-reduced-motion`.

shadcn/ui components are added **per-screen as needed**, not bulk-installed (ADR-004), into `src/components/ui/`. App-specific composites go in `src/components/dash/`.

## Routes & phasing (see `05-information-architecture.md`)

Phase 1 ships exactly `/`, `/lists`, `/lists/[listId]`, `/settings`, `/sign-in`, `/auth/callback`, `/no-household`. Nav: bottom tab bar (phone) / side rail (desktop), showing only Home + Lists until later phases land — no disabled "coming soon" tabs. Five is the tab-bar ceiling and the final feature set is exactly five; nothing new goes top-level. The add pattern: inline QuickAdd for list items; Sheet (phone) / Dialog (desktop) for everything else. Every screen handles loading (Skeleton), empty (EmptyState), and error (Sonner toast) states centrally.

## Working conventions

- **Features are globally-numbered F-NN**, tracked in `project-docs/features/index.md` with the counter in `features/last-id.md`. Phase 1 is F-01…F-07. Never reuse or reset IDs.
- **Each feature gets a plan** at `.plans/F-NN-slug.md` before implementation, stating scope, explicit out-of-scope, steps, files touched, verification, and definition of done. Read the plan for the feature you're working on; the out-of-scope section is binding.
- **Branches** are `feature/f-NN-slug`, PR'd to `main`. Commits are conventional and feature-scoped: `feat(f-01): …`, `fix(f-01): …`, `chore: …`.
- **Deploy early** (ADR-003, env-setup step 10): `main` → production, every branch → a preview. This is already wired; keep it that way.
