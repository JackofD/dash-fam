# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Dash Fam is

A private web app for one household of five (2 adults with logins, 3 kids without): shared lists, chores, calendar, meal planning. Phone-first, desktop as the planning surface. Shipped in phases — **Phase 1 is Foundation + Lists only** (auth, app shell, lists, thin dashboard). Chores, calendar and meals are deliberately unspecified until their phase; do not build ahead into them.

Guiding principle: low friction beats feature depth. If adding a list item takes more than three taps the app has failed and the family goes back to WhatsApp.

Read [.docs/PROJECT.MD](.docs/PROJECT.MD) (scope, decisions, phasing) and [.docs/NOTES.md](.docs/NOTES.md) (how things get built) before working in an area. NOTES.md overrides assumptions made anywhere else, including here.

## Current state — this is a fresh starter being rebuilt

Commit `82263e5` ("reset the codebase") wiped the previous app and dropped in the vanilla **Next.js + Supabase starter kit**. Almost everything under [app/](app/) and [components/](components/) is upstream template code, not Dash Fam code: the marketing hero, `deploy-button`, `supabase-logo`, `components/tutorial/*`, the `/protected` demo route, the password-based auth forms. Expect to delete or replace these rather than build around them — and note the template ships **password auth**, while the project has decided on **magic link only** ([.docs/PROJECT.MD](.docs/PROJECT.MD) §5.3).

What *is* Dash Fam's own work: [supabase/migrations/](supabase/migrations/), [supabase/seed.sql](supabase/seed.sql), [lib/supabase/types.ts](lib/supabase/types.ts), and the two `.docs/` files. The schema is already applied to the hosted project; the app does not consume it yet.

Paths are **root-level** (`app/`, `components/`, `lib/`), not `src/`. The `@/*` alias maps to the repo root.

## Commands

```bash
npm run dev            # next dev
npm run lint           # eslint .
npx tsc --noEmit       # typecheck
npm run build          # production build
```

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml), on PRs) runs lint → `tsc --noEmit` → build. Keep all three green. **There is no test runner and no test script** — do not assume `npm test` exists. Any test strategy must not depend on a throwaway local database (see below).

## Next.js 16 — not the Next.js you know

Installed Next is **16.3.2**. Two consequences that break training-data assumptions:

- **Middleware is `proxy.ts`, not `middleware.ts`.** The root [proxy.ts](proxy.ts) exports `proxy()` plus a `config.matcher`, delegating to [lib/supabase/proxy.ts](lib/supabase/proxy.ts). Creating `middleware.ts` will silently do nothing.
- **`cacheComponents: true`** in [next.config.ts](next.config.ts) changes caching/streaming semantics for server components.

When unsure about a Next API, read `node_modules/next/dist/docs/` rather than recalling it. `next dev` may append a `<!-- BEGIN:nextjs-agent-rules -->` block to this file; commit it with your work rather than reverting it.

## Database: remote only, no Docker

**Docker is not installed and will not be used.** There is no local Postgres, no local Supabase stack, no shadow DB. The hosted Supabase project *is* the development database — treat destructive statements accordingly. Never suggest `supabase start`/`stop`/`db reset`/`db diff` or a containerised test DB; find the hosted or CLI-only equivalent instead.

[supabase/config.toml](supabase/config.toml) exists only for CLI project linkage — its local ports are inert, ignore them.

Migration workflow ([.docs/NOTES.md](.docs/NOTES.md) §4):

1. Hand-write a new timestamped file in [supabase/migrations/](supabase/migrations/) — never edit the schema in Studio.
2. Apply it: Supabase MCP `apply_migration`, the dashboard SQL editor, or `supabase db push --linked`.
3. Regenerate [lib/supabase/types.ts](lib/supabase/types.ts) from the remote project.
4. Commit migration + regenerated types **together**, so schema and types in the repo never disagree.

Migrations are small and forward-only; there is no `db reset` to undo one. [supabase/seed.sql](supabase/seed.sql) is applied manually and must stay idempotent (`on conflict do nothing`). Its second adult and three kids are still `TODO(F-02)` placeholders — `invited_email` is write-once, so replace them before any production apply.

Every table ships RLS enabled with its policies **in the same migration that creates it**. A table with no policy is unreadable, which fails loudly — that is the intended safety behaviour, not something to fix by disabling RLS.

## Architecture rules that span files

Load-bearing decisions, mostly enforced in [supabase/migrations/20260818150009_init_foundation_lists.sql](supabase/migrations/20260818150009_init_foundation_lists.sql):

- **Members vs accounts are separate concepts.** A `member` is a person; an account is an auth login. Three of five members have no account. **All domain FKs reference `members.id`, never `auth.users`.** Never write a query, policy or FK that assumes a `member_id` implies an auth user exists — this is what lets kids get accounts later without a rewrite.
- **`household_id` on every domain table**, even with one household, so multi-tenancy stays a migration rather than a rewrite. On `list_items` it is **denormalised and set by the `list_items_set_household` trigger** — never trust it from the client.
- **RLS is the security boundary, not app code.** Per-operation policies key off `current_household_id()`, a `security definer stable` function with a fixed `search_path` (all three are mandatory — without them the policies recurse through `members`' own policy). Do not reimplement household filtering in queries.
- **Account linking is server-side only, by email allowlist.** The `on_auth_user_created` trigger matches a new user's email to a member's `invited_email` and sets `user_id`. The `members` insert/update policies deliberately forbid setting or changing `user_id` from the client — that would be privilege escalation. A user matching no member gets a null household and is denied every row by RLS; surface that as a dedicated screen, not a redirect loop.
- **Realtime is enabled per-table** in the migration (`lists`, `list_items`), never assumed on. Optimistic updates must reconcile incoming events **by id** to avoid double-apply; delete payloads carry only the primary key.
- **Keep Vercel-specific APIs out of application code** so a hosting move stays cheap.
- The **service role key** bypasses RLS: it must never reach a client-reachable path and never take a `NEXT_PUBLIC_` prefix.

**Still undecided, and it blocks Phase 1 code:** the data access pattern — Supabase client directly in server components vs a query/action layer ([.docs/PROJECT.MD](.docs/PROJECT.MD) §7). Decide before scattering client calls through components.

## Schema conventions

UUID PKs via `gen_random_uuid()`; `timestamptz` always; `snake_case` plural tables. Enums are `text` + `CHECK`, not Postgres `ENUM` types. Ordering uses `sort_position double precision` (float-gap reordering). Delete strategy: hard-delete `list_items`, soft-delete `lists` (`archived_at`), members are only ever `deactivated_at`. "Today" resolves against the fixed `households.timezone` (`Africa/Johannesburg`), not UTC or the browser zone.

The `postgres` role owns the tables and is exempt from their RLS, so any RLS assertion must `set local role authenticated` first or it passes vacuously while looking green.

## Environment

`.env.local` (never committed) holds `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` — note the template uses the **publishable** key variable name; an anon key value works in it. `next dev` runs against the remote project. Vercel holds the same variables per environment, preview and production pointing at the same project for now. `lib/utils.ts` exports a `hasEnvVars` guard that the template uses to no-op the proxy and swap in `EnvVarWarning`; it is tutorial scaffolding and can go once real auth lands.

## Working conventions

- Features are globally-numbered **F-NN** and never reused; branches are `feature/f-NN-slug` (current branch is `fix/reboot-this-whole-project`), PR'd to `main`. Commits are conventional and feature-scoped: `feat(f-02): …`.
- Each feature gets a plan in [.plans/](.plans/) before implementation; its out-of-scope section is binding. The folder is currently empty after the reset.
- `main` → production, every branch → a Vercel preview. Deploy early.
- shadcn/ui (`new-york`, neutral base, CSS variables) is configured in [components.json](components.json); add components per-screen as needed rather than bulk-installing. Components reference semantic tokens, never hex.
