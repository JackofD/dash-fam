# Dash Fam: Environment & Deployment Setup

**Status:** Draft v0.1
**Last updated:** 2026-08-13
**Covers:** prerequisites, project scaffold, folder structure, Supabase local + prod, migration workflow, SSR client structure, env vars, Vercel, CI, pre-build checklist
**Depends on:** all ADRs, 04-decisions-log.md

This is a runbook, not a decision document. Follow it top to bottom to reach a deployed, empty-but-working app. Version numbers move quickly; where one is given, verify it is current rather than trusting this file.

---

## 1. Decisions this encodes

- Package manager: **npm** (D-discussion). Zero setup, matches the docs.
- Dev database: **Supabase CLI + Docker locally**, plus a **separate hosted production project**. Migrations are proven locally before they touch prod.
- Source control: **GitHub**, with **minimal CI** (lint, typecheck, build) on pull requests. **Vercel** auto-deploys (ADR-003).
- Sessions: **SSR cookie-based** (ADR-007), which dictates the client structure in section 6.

---

## 2. Prerequisites

Install and verify each before scaffolding:

- **Node.js**, current LTS (20.x or later; confirm Next's minimum at build time). `node -v`.
- **npm** (ships with Node). `npm -v`.
- **Docker Desktop**, running. The Supabase CLI local stack needs it. `docker info` should succeed.
- **Supabase CLI**. Install per Supabase's current instructions, then `supabase -v`.
- **Git**, and a GitHub account. `git --version`.
- A **Vercel account**, linked to GitHub.
- A **Supabase account** for the hosted production project.

---

## 3. Scaffold the app

```bash
npx create-next-app@latest dash-fam
```

Choose, when prompted: TypeScript yes, App Router yes, Tailwind yes, ESLint yes, `src/` directory yes, import alias `@/*`. This matches ADR-001 and ADR-004.

Then add the runtime dependencies:

```bash
cd dash-fam
npm install @supabase/supabase-js @supabase/ssr
```

shadcn/ui is initialised after the first run, per its current setup, and components are added as needed (ADR-004). Do not bulk-install every component; add each when a screen needs it.

---

## 4. Folder structure

A shape that fits the data-access decision (ADR-005) and keeps Phase 1 legible:

```
src/
  app/
    (auth)/sign-in/           public
    auth/callback/            magic-link exchange
    (app)/                    authenticated group, shares the AppShell layout
      page.tsx                Home  /
      lists/
        page.tsx              /lists
        [listId]/page.tsx     /lists/[listId]
      settings/page.tsx
    no-household/page.tsx
    layout.tsx                root: fonts, theme, providers
  components/
    ui/                       shadcn components (owned, restyled)
    dash/                     MemberAvatar, QuickAdd, ListItemRow, DashboardWidget, ...
  lib/
    supabase/
      client.ts               browser client
      server.ts               server-component client
      middleware.ts           middleware client + session refresh
    queries/                  read functions (the thin query layer, ADR-005)
    actions/                  Server Actions, i.e. writes (ADR-005)
  middleware.ts               route protection (auth doc 6)
supabase/
  migrations/                 timestamped SQL migrations
  seed.sql                    the five members, household, grocery list
```

Reads live in `lib/queries`, writes in `lib/actions`. That separation is the whole of ADR-005 and it starts with a handful of files.

---

## 5. Supabase: local and production

### 5.1 Initialise local

```bash
supabase init
supabase start
```

`supabase start` boots the full stack in Docker and prints local URLs and keys (API URL, anon key, service role key, Studio URL). These are the values for `.env.local` (section 7). The local database is disposable: `supabase db reset` rebuilds it from migrations plus `seed.sql`, which is exactly how the five-member seed (schema section 7) should be verified.

### 5.2 Migrations workflow

The schema doc's SQL and the decisions-log deltas (D-01 timezone, D-07 theme preference, D-09 the `sort_position` name) become migration files, applied in the order schema section 9 sets out.

```bash
supabase migration new init_foundation_lists
# paste the schema doc SQL (tables, functions, triggers, RLS, realtime) into the file,
# with the D-01/D-07/D-09 changes already folded in
supabase db reset          # apply from scratch locally + run seed.sql, repeatable
```

Rule: **schema changes are always a new migration file, never a manual edit in Studio.** Studio is for looking, not for changing structure. This keeps local, prod, and the repo identical.

### 5.3 Production project

Create a separate hosted project in the Supabase dashboard. This is prod; it is never developed against directly. Link and push migrations:

```bash
supabase link --project-ref <prod-ref>
supabase db push          # applies local migrations to prod
```

Seed data for prod is applied once (the household, five members, grocery list). The two adult member rows get `invited_email` set to the real sign-in addresses so the signup trigger links them on first login (auth doc 3).

### 5.4 Auth configuration (in the Supabase dashboard, prod and local where applicable)

- Enable **email / magic link**; the sign-in uses it exclusively (ADR-002).
- Set the **redirect URL allowlist** to include the local dev URL and the production Vercel URL's `/auth/callback`.
- Set the **refresh token / session lifetime long, ~90 days** (D-04).
- Confirm **rate limiting on the email/OTP endpoint is enabled** (D-12); the sign-in screen will send to any address typed.
- Use the **PKCE flow** (ADR-002); `@supabase/ssr` uses it by default, just don't override it.

---

## 6. The SSR client structure (ADR-007)

This is the one part that must be set up correctly at the start, because retrofitting it is painful. Three clients, one cookie.

- `lib/supabase/client.ts` — a browser client (`createBrowserClient`) for client components and realtime subscriptions.
- `lib/supabase/server.ts` — a server client (`createServerClient`) reading and writing the request's cookies, for server components, route handlers, and Server Actions.
- `lib/supabase/middleware.ts` — a client used inside `middleware.ts` that refreshes the session cookie on every request and lets the middleware decide redirects.

`middleware.ts` at the `src` root does two things and no more (auth doc 6): refresh the session, and redirect an unauthenticated request to `/sign-in`. It does not do per-row authorisation; RLS does that. Keep its route matcher current as routes are added, but never rely on it as the security boundary.

All three read the same env vars (section 7). Follow Supabase's current `@supabase/ssr` guide for the exact cookie-handling code, since that API has changed over time; the structure above is the stable part.

---

## 7. Environment variables

`.env.local` for local dev (never committed; `create-next-app` gitignores it):

```
NEXT_PUBLIC_SUPABASE_URL=<from supabase start>
NEXT_PUBLIC_SUPABASE_ANON_KEY=<from supabase start>
```

The `NEXT_PUBLIC_` prefix is required for the browser client to see them. The **service role key is never** given a `NEXT_PUBLIC_` prefix and never reaches the browser; Phase 1 does not need it in app code at all, since all access goes through RLS with the anon key plus the user's session.

In **Vercel** (project settings, Production and Preview): the same two variables, pointed at the **production** Supabase project's URL and anon key. Commit a `.env.example` with the keys and no values so the setup is documented.

---

## 8. GitHub and CI

### 8.1 Repository

The app lives in its own repo (the `project-docs` folder these documents sit in can stay separate, or the app repo can hold a `/docs` copy; keep one as the source of truth). Push `dash-fam` to GitHub.

### 8.2 Minimal CI

A single workflow on pull requests, doing the three cheap checks that catch most breakage:

```yaml
# .github/workflows/ci.yml
name: ci
on:
  pull_request:
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npx tsc --noEmit
      - run: npm run build
```

This is lint, typecheck, and build. It does not run the app or hit a database, so it needs no secrets. The RLS and critical-path tests from D-08 are added as a fourth step once they exist.

### 8.3 Vercel

Connect the GitHub repo to Vercel. Every branch gets a preview deploy; `main` deploys to production. This is what makes ADR-003's "deploy in week one" cheap: it is automatic once connected.

---

## 9. Pre-build checklist

Done in order, this is the whole runway. None of it is Phase 1 feature code; it is the ground that code stands on.

1. Prerequisites installed and verified (section 2).
2. App scaffolded, Supabase libs installed (section 3).
3. Folder structure created (section 4).
4. `supabase init` and `supabase start` working locally (5.1).
5. First migration written from the schema doc + decision deltas; `supabase db reset` applies it cleanly with seed data (5.2).
6. Three SSR clients and `middleware.ts` in place; a hardcoded protected page correctly bounces a logged-out visitor to `/sign-in` (section 6).
7. Prod Supabase project created, linked, migrations pushed, auth configured (5.3, 5.4).
8. Env vars set locally and in Vercel (section 7).
9. Repo on GitHub, CI green on a first PR, Vercel connected (section 8).
10. **Deploy the empty app to production and open it on your phone.** Do this now, not at the end. An app that has never been deployed is not close to being deployable (ADR-003, scope timeline).

When all ten are ticked, the next document is the Phase 1 feature and task breakdown, and after that it is feature code.

---

## 10. Notes and gotchas

- **Do not put `household_id` or any RLS logic in application code.** The database enforces it (schema 5). App code trusts RLS.
- **The service role key bypasses RLS entirely.** It has no place in the Phase 1 client or server code. If a future admin task needs it, that is an isolated server-only path, decided then.
- **Migrations are append-only in spirit.** Once a migration has run against prod, do not edit it; write a new one. Before prod exists, the single init migration can still be edited freely.
- **Realtime must be enabled per table** in the migration (schema 6), not assumed on.
- **Keep platform-specific APIs out of app code** (ADR-003) so the Vercel-to-elsewhere door stays cheap.
