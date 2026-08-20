# F-02 — Database schema, RLS, seed, and RLS tests

Replaces the earlier F-02 plan and the F-02a addendum. Those assumed the Supabase CLI's
local Docker stack was the execution target; this one commits to a **throwaway hosted
Supabase dev project** instead, which changes the verification gate, the commands, and the
secrets handling. Everything else — the schema itself, the policies, the seed — is unchanged.

## Goal

Phase-1 (Foundation + Lists) database: four tables, RLS as the security boundary, the
signup-linking trigger, seed data for one household of five, and a pgTAP suite that proves
the policies actually deny. Verified by executing all of it against a real Supabase Postgres.

Out of scope: the production project, `supabase db push` to prod, SSR client factories and
`src/middleware.ts` (F-03), non-RLS critical-path tests, and wiring tests into CI.

## Why hosted, not Docker

Docker isn't installed on this machine, and the CLI's local stack is a fleet of containers
(Postgres, GoTrue, Realtime, Storage, Kong, Studio). The schema and RLS tests need almost
none of it — just Postgres with pgTAP, the `authenticated` role, `auth.users`, and
`auth.uid()`.

Verified by probing the installed CLI (v2.115): `supabase db reset`, `supabase db push` and
`supabase test db` all accept `--db-url` and connect straight to a Postgres over the wire
with **no Docker in the path**. A free-tier throwaway project therefore gives us a real
Supabase environment — real `auth` schema, real roles, real `supabase_realtime` publication
— rather than a shim that would let a Supabase-specific defect through.

Two consequences worth stating up front:

- **`db reset --db-url` is the primary command, not `db push`.** `db reset` replays all
  migrations *plus* `seed.sql` from scratch on every run (`--no-seed` to skip the seed).
  `db push` instead records each applied version in `supabase_migrations.schema_migrations`,
  so editing the init migration and re-pushing would be treated as already-applied and the
  fix would silently not land. Since untested SQL needs a fix-and-rerun cycle, that
  distinction is load-bearing. `db reset` also reproduces the gate this plan originally
  specified — "migration and seed apply with zero errors" — just against a remote database.
- **The dev project is disposable and is never production.** `db reset` is destructive by
  design. The guard rails in step 3 exist because of that.

## Current state

The SQL is written and sits on branch `worktree-f-02-schema` / draft PR #3, checked against
the Postgres grammar but **never executed**. Already in the repo:

- `supabase/migrations/20260818150009_init_foundation_lists.sql` — `households`, `members`,
  `lists`, `list_items`; `current_household_id()` and `link_member_on_signup()` as
  `security definer … set search_path`; the `on_auth_user_created` trigger;
  `list_items_set_household()`; RLS enabled on all four tables ahead of any policy;
  per-operation policies to `authenticated` only; both `alter publication supabase_realtime`
  statements; five indexes.
- `supabase/seed.sql` — one household (fixed id), five members (`user_id` null throughout,
  two adults with `invited_email`), one `grocery` list. Every insert
  `on conflict (id) do nothing`.
- `supabase/tests/rls.test.sql` — 13 pgTAP assertions with self-contained fixtures in their
  own household, wrapped `begin … rollback`.

So the remaining work is: fix the defects found by reading, build the remote runner, and
then actually run it.

## Steps

### 1. Fix three real bugs in `supabase/tests/rls.test.sql`

Found by reading. All three would fail on Docker too — the suite has never been runnable.

- **Missing `auth.users` row (hard failure).** `members.user_id` has an FK to
  `auth.users(id)`, but the fixture inserts `user_id = '…f1'` with no such user. Insert it
  first: `insert into auth.users (id, email) values ('…f1', 'linked-adult@test.invalid');`
  — every other `auth.users` column is nullable or defaulted. The address must match no
  `invited_email` so `on_auth_user_created` stays a no-op; in particular **not**
  `deshen.padayachee@rokkit200.co` from the seed. The negative-case subject `…e0` is only
  ever a JWT claim, never a row, so it needs nothing.
- **Untyped `null` in a polymorphic assertion.** `is(public.current_household_id(), null, …)`
  can't resolve pgTAP's `anyelement`. Cast to `null::uuid`; same for the `null` errmsg
  argument in both `throws_ok` calls (`null::text`).
- **Ambiguous `has_function` overload.** The 3-arg call is ambiguous between
  `(name, name, text)` and `(name, name, name[])` given unknown-type literals. Cast
  explicitly or drop to the 2-arg form.

`plan(13)` is unchanged — no assertions added or removed.

### 2. Add the remote runner

New `scripts/supabase-remote.mjs` — a thin wrapper, not a framework. It reads
`SUPABASE_TEST_DB_URL`, exits with a message naming the env var and `.env.example` if unset,
spawns the CLI with `stdio: 'inherit'`, and propagates the exit code. It **prints the target
host before running** and never passes `--linked` or `--local`, so the target is always
explicit and never inherited from CLI state. Subcommand comes from `argv[2]`:

- `test` → `supabase test db --db-url <url>`
- `reset` → `supabase db reset --db-url <url>`
- `reset:noseed` → `supabase db reset --db-url <url> --no-seed`
- `push:dry` → `supabase db push --db-url <url> --dry-run` (inspection only — shows what a
  history-tracked push *would* do; we don't push)

A Node wrapper rather than inlining `$SUPABASE_TEST_DB_URL` in an npm script, because npm on
Windows runs scripts through `cmd`, where `$VAR` does not expand.

In `package.json`, keep `"test": "supabase test db"` as the local/Docker path for whenever
Docker exists, and add:

```
"test:remote":       "node --env-file-if-exists=.env.local scripts/supabase-remote.mjs test",
"db:reset:remote":   "node --env-file-if-exists=.env.local scripts/supabase-remote.mjs reset",
"db:reset:noseed":   "node --env-file-if-exists=.env.local scripts/supabase-remote.mjs reset:noseed",
"db:push:dry":       "node --env-file-if-exists=.env.local scripts/supabase-remote.mjs push:dry"
```

`--env-file-if-exists` needs Node ≥22.9 (local is 22.12). These scripts are local-only and
deliberately not wired into CI, so the Node 20 pin in `.github/workflows/ci.yml` is untouched.
Wiring `npm run test` into CI stays a later feature (D-08 names it; nothing here blocks it).

### 3. Secrets and guard rails

Add `.env.example` documenting `SUPABASE_TEST_DB_URL` with a commented placeholder and a note
to use the **Session pooler** string (port 5432) from the dashboard's Connect panel:
transaction mode (6543) can't run migrations, and the direct `db.<ref>.supabase.co` host is
IPv6-only on many networks. The password must be percent-encoded, as the CLI requires.

The real value goes in `.env.local`, ignored by root `.gitignore` (`.env.*` with
`!.env.example`) and again by `supabase/.gitignore`. Nothing is committed. This workflow needs
only the Postgres database password — **not** the service-role key, which bypasses RLS and
must never enter Phase-1 code or the browser.

`.env.local` is also where F-03 will put the anon key. Additive keys, same file — F-03 extends
it rather than replacing it.

We do **not** run `supabase link`. Linking writes a project ref into `supabase/.temp` and
makes `--linked` implicit; with a destructive `db reset` in the toolbox, a stale link is one
command away from wiping the wrong database. Leaving the link slot empty forces every
invocation to name its target.

### 4. Document the path

Short subsection in `project-docs/06-environment-setup.md` (the runbook): create a free dev
project, copy the session-pooler URL into `.env.local`, `npm run db:reset:remote`,
`npm run test:remote`. State plainly that this project is disposable and never production,
that `db reset` wipes whatever it points at, and that the Docker loop (`supabase start` +
`supabase db reset`) remains available and equivalent once Docker is installed. Mirror the new
commands into the CLAUDE.md commands block, and amend its "Commands (once scaffolded)" note so
`supabase start` isn't presented as the only way to get a database.

## Files

- `supabase/tests/rls.test.sql` — the three fixes
- `scripts/supabase-remote.mjs` — new
- `package.json` — four new scripts
- `.env.example` — new
- `project-docs/06-environment-setup.md`, `CLAUDE.md` — docs
- `supabase/migrations/20260818150009_init_foundation_lists.sql`, `supabase/seed.sql` — edited
  only if the run surfaces a defect, which is likely. Legal: this migration has never reached
  prod, and `db reset` rebuilds from scratch, so it stays freely editable.

Not touched: the CI workflow, anything in `src/`.

## Verification

Requires one thing I can't do myself — a Supabase dev project and its session-pooler
connection string. **needs input** at that point; I'll stop and ask rather than guess.

1. `npm run db:push:dry` — lists `20260818150009_init_foundation_lists` as pending and applies
   nothing. A cheap connectivity and credentials check before anything destructive.
2. `npm run db:reset:remote` — migration and `seed.sql` apply with **zero errors**. This is the
   core gate and the first real execution of the DDL: it proves the four tables, both
   `security definer` functions, every policy, both `alter publication` statements, the trigger
   on `auth.users`, and the seed's constraint compliance are all valid against real Supabase.
3. `npm run test:remote` — all 13 pgTAP assertions pass. The load-bearing ones: a user with no
   member row reads **zero** rows from all four tables; `current_household_id()` is null for
   them; `members` insert and update refuse to set or change `user_id` (`42501`); and
   `list_items_set_household()` overwrites a client-sent bogus `household_id`.
4. Eyeball Studio: one household, five members with `user_id` null, one `grocery` list, RLS
   badges on all four tables.
5. `npm run db:reset:noseed` then `npm run test:remote` again — the suite must pass identically
   on an empty database, proving "zero rows" is a real denial and not an empty table.
6. `npm run lint`, `npx tsc --noEmit`, `npm run build` stay green.

The suite is wrapped `begin … rollback`, so a pass or a fail leaves the database as `db reset`
left it. Between iterations, re-run `db:reset:remote` rather than trying to patch forward.

Then commit onto `worktree-f-02-schema` so draft PR #3 carries the verified state, and replace
the "gate not run" caveat in the PR body with the actual result.

## Definition of done

- Migration + seed apply cleanly to a real Supabase Postgres, repeatably.
- All 13 RLS assertions pass, both seeded and unseeded.
- The remote loop is documented and reproducible by someone with only the repo and a dev
  project.
- `supabase init` is done; **`supabase start` remains unverified** and stays on the checklist
  for whenever Docker is installed. It is not a gate for this feature.

## Risks and follow-ups

- **Untested SQL will probably fail on first contact.** That's the point — expect several
  fix-and-reset cycles on the migration and the test file.
- The `postgres` role owns the tables and so is exempt from their RLS. That's why fixtures
  insert fine, and why every assertion must `set local role authenticated` first — one that
  forgets would pass vacuously while looking green. Worth re-reading the suite with that
  specifically in mind once it passes.
- `supabase/seed.sql` still carries `TODO(F-02)` placeholders: the second adult's display name
  and `invited_email` (`adult.two@example.com`), and the three kids' display names. Harmless on
  a disposable project, but this feature hands the repo a working remote-write command, so a
  placeholder is now one edited env var away from a production `invited_email` — which is
  write-once (D-10). **Replace them before any production apply.**
- GoTrue is not in this loop, so the actual magic-link signup that fires
  `link_member_on_signup()` is F-03's verification. Here we assert only that the function and
  trigger exist.
- Realtime behaviour (subscriber-side RLS) is likewise asserted structurally only — the
  publication contains both tables. Exercised for real in the Lists feature.
