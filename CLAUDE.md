# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Dash Fam is

A private web app for one household of five (2 adults with logins, 3 kids without): shared lists, chores, calendar, meal planning. Phone-first, desktop as the planning surface. Shipped in phases — **Phase 1 is Foundation + Lists only** (auth, app shell, lists, thin dashboard). Chores, calendar and meals are deliberately unspecified until their phase; do not build ahead into them.

Guiding principle: low friction beats feature depth. If adding a list item takes more than three taps the app has failed and the family goes back to WhatsApp.

Read [.docs/PROJECT.MD](.docs/PROJECT.MD) (scope, decisions, phasing) and [.docs/NOTES.md](.docs/NOTES.md) (how things get built) before working in an area. NOTES.md overrides assumptions made anywhere else, including here.

## Current state

Commit `82263e5` ("reset the codebase") wiped the previous app and dropped in the vanilla **Next.js + Supabase starter kit**. F-08 then deleted all of that template's auth and chrome — the marketing hero, `deploy-button`, `supabase-logo`, `components/tutorial/*`, `/protected`, and the password-based auth forms are gone, along with `hasEnvVars`. If you are looking for one of those, it was removed on purpose, not misplaced.

Auth is built and is **magic link with a 6-digit code fallback**, no passwords. The route map is `/sign-in`, `/auth/confirm`, `/no-household`, and everything else inside the `app/(app)/` group behind its member gate. See [.plans/F-08-auth-household-access.md](.plans/F-08-auth-household-access.md) for the decisions, including why `verifyOtp` rather than `exchangeCodeForSession` and why `shouldCreateUser` must stay `true`.

Styling is **Tailwind v4**, matching what the shadcn registry now emits, so `shadcn add` output can be trusted as-is. There is **no `tailwind.config.ts`** — the theme lives in `@theme inline` in [app/globals.css](app/globals.css). See the Styling section below.

Still template-shaped: `next-themes` theming (vs `members.theme_preference`), `components/theme-switcher.tsx` is currently orphaned pending the app shell, and there is no navigation chrome yet.

What is Dash Fam's own work: [supabase/migrations/](supabase/migrations/), [supabase/seed.sql](supabase/seed.sql), [lib/supabase/types.ts](lib/supabase/types.ts), `lib/auth/`, `components/auth/`, and the `.docs/` and `.plans/` files.

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

Installed Next is **16.3.2**. Consequences that break training-data assumptions:

- **Middleware is `proxy.ts`, not `middleware.ts`.** The root [proxy.ts](proxy.ts) exports `proxy()` plus a `config.matcher`, delegating to [lib/supabase/proxy.ts](lib/supabase/proxy.ts). Creating `middleware.ts` will silently do nothing.
- **`cacheComponents: true`** in [next.config.ts](next.config.ts) changes caching/streaming semantics for server components. Three things follow:
  - `export const dynamic` / `revalidate` / `fetchCache` **error outright**. The escape hatch for a segment that must block is `export const instant = false`.
  - `instant = false` does **not** defer synchronous IO. `new Date()`, `Math.random()` and friends still fail the prerender; put them behind `connection()` inside a `<Suspense>` boundary.
  - Reading `cookies()` or `searchParams` inside a `<Suspense>` boundary keeps a route partially prerendered (`◐`) instead of fully dynamic. Prefer that to opting the whole segment out.
- **Deleting a route leaves stale generated types in `.next`**, and `tsc --noEmit` keeps failing on the old path until you `rm -rf .next tsconfig.tsbuildinfo`. It is not your code that is broken.

When unsure about a Next API, read `node_modules/next/dist/docs/` rather than recalling it. `next dev` may append a `<!-- BEGIN:nextjs-agent-rules -->` block to this file; commit it with your work rather than reverting it.

## Styling: Tailwind v4, CSS-first

**There is no `tailwind.config.ts` and adding one back is wrong.** Tailwind 4 configures itself from CSS, and everything lives in [app/globals.css](app/globals.css):

- `@import "tailwindcss"` replaces the three `@tailwind` directives.
- `@custom-variant dark (&:is(.dark *))` is **required** — v4 defaults `dark:` to `prefers-color-scheme`, but `next-themes` toggles a `.dark` class. Without this line every `dark:` utility silently targets the wrong thing.
- `:root` / `.dark` hold the palette as **complete colours** (`hsl(0 0% 100%)`), not the bare triplets v3 used. `@theme inline` maps them to `--color-*`, which is what generates `bg-background` and friends. `inline` matters: it makes the utilities reference the custom properties, so `.dark` reassigning them just works.
- Animations come from `tw-animate-css` (imported in the CSS), **not** `tailwindcss-animate` (a v3 plugin, removed).
- `autoprefixer` is gone; `@tailwindcss/postcss` handles prefixing. [postcss.config.mjs](postcss.config.mjs) lists only that one plugin.

To add a colour, add the variable to both `:root` and `.dark` **and** map it in `@theme inline` — a variable with no mapping generates no utility, and fails silently rather than loudly.

Verifying styles actually work needs more than a green build: v4 emits nothing for an unmapped token without erroring. Check the served CSS. Note that selectors escape `@`, `/`, `[`, `]` (`.\@container\/card-header`), so grep for the CSS property (`inline-size`) rather than the class name.

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
- **Account linking is server-side only, by email allowlist.** The `on_auth_user_created` trigger matches a new user's email to a member's `invited_email` and sets `user_id`. The `members` insert/update policies deliberately forbid setting or changing `user_id` from the client — that would be privilege escalation. A user matching no member gets a null household and is denied every row by RLS; that is the `/no-household` screen, not a redirect loop. Because the trigger only fires on insert, `signInWithOtp` must keep `shouldCreateUser: true` or a seeded member who has never signed in can never link.
- **Auth guards come in two layers and they are not interchangeable.** [lib/supabase/proxy.ts](lib/supabase/proxy.ts) checks only *is there a session* (no DB read). `app/(app)/layout.tsx` checks *does the session map to a member*, via `requireMember()` in [lib/auth/current-member.ts](lib/auth/current-member.ts). The second is routing, not security — RLS still denies an account that bypasses it. Do not move the membership check into the proxy; it runs on every request.
- **Realtime is enabled per-table** in the migration (`lists`, `list_items`), never assumed on. Optimistic updates must reconcile incoming events **by id** to avoid double-apply; delete payloads carry only the primary key.
- **Keep Vercel-specific APIs out of application code** so a hosting move stays cheap.
- The **service role key** bypasses RLS: it must never reach a client-reachable path and never take a `NEXT_PUBLIC_` prefix.

**Still undecided, and it blocks Phase 1 code:** the data access pattern — Supabase client directly in server components vs a query/action layer ([.docs/PROJECT.MD](.docs/PROJECT.MD) §7). Decide before scattering client calls through components. F-08 deliberately did **not** settle this: `lib/auth/` is the auth helpers auth itself needed and sets no precedent for reads or writes. Whichever way it goes, note that `getCurrentMember` is wrapped in React `cache()` so a layout and its page share one round trip — per-request dedup is the cheapest half of a query layer.

## Schema conventions

UUID PKs via `gen_random_uuid()`; `timestamptz` always; `snake_case` plural tables. Enums are `text` + `CHECK`, not Postgres `ENUM` types. Ordering uses `sort_position double precision` (float-gap reordering). Delete strategy: hard-delete `list_items`, soft-delete `lists` (`archived_at`), members are only ever `deactivated_at`. "Today" resolves against the fixed `households.timezone` (`Africa/Johannesburg`), not UTC or the browser zone.

The `postgres` role owns the tables and is exempt from their RLS, so any RLS assertion must `set local role authenticated` first or it passes vacuously while looking green.

## Environment

`.env.local` (never committed) holds `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` — the **publishable** name; an anon key value works in it. `NEXT_PUBLIC_SITE_URL` is optional and only feeds metadata. `next dev` runs against the remote project. Vercel holds the same variables per environment, preview and production pointing at the same project for now.

These are validated in [lib/supabase/env.ts](lib/supabase/env.ts), which **throws** on a missing value. That is deliberate: the old `hasEnvVars` guard failed *open*, silently no-opping the proxy so every auth check was skipped. Do not reintroduce a soft fallback.

**Auth also depends on remote dashboard settings that live outside this repo** — custom SMTP (the built-in mailer's few-per-hour cap makes magic-link auth untestable), a Magic Link template carrying both `{{ .TokenHash }}` and `{{ .Token }}`, and the allowed redirect URLs. If sign-in "doesn't work", check those before the code.

## Working conventions

- Features are globally-numbered **F-NN** and never reused; branches are `feature/f-NN-slug`, PR'd to `main`. Commits are conventional and feature-scoped: `feat(f-08): …`. **Highest allocated is F-08** (auth); F-03..F-07 were allocated before the reset and their numbers are spent.
- Each feature gets a plan in [.plans/](.plans/) before implementation; its out-of-scope section is binding.
- `main` → production, every branch → a Vercel preview. Deploy early.
- shadcn/ui (`new-york`, neutral base, CSS variables) is configured in [components.json](components.json); add components per-screen as needed rather than bulk-installing. Components reference semantic tokens, never hex.
- `eslint .` covers the whole repo; nested `.next` directories inside git worktrees are ignored in [eslint.config.mjs](eslint.config.mjs) because they otherwise bury real findings under thousands of generated-file errors.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
