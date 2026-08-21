# Dash Fam: Implementation Notes

Working notes on *how* things get built. Complements [PROJECT.MD](PROJECT.MD), which covers *what*
and *why*. Anything here overrides an assumption made elsewhere.

**Last updated:** 2026-08-21

---

## 1. Database: remote only, no local stack

**Decision:** all database work happens against the hosted Supabase project. There is no local
Postgres, no local Supabase stack, no shadow database.

Practical consequences:

- The hosted project *is* the development database. Treat it accordingly: destructive statements get
  read twice before they run.
- Migrations in [../supabase/migrations/](../supabase/migrations/) remain the source of truth for
  schema. They are written by hand, committed, and applied to the remote project. The folder is a
  record of intent, not a byproduct of a local diff tool.
- Do **not** use workflows that assume a local database: `supabase start`, `supabase stop`,
  `supabase db reset`, `supabase db diff` (needs a local shadow DB), or local `supabase status`.
- `supabase/config.toml` exists for CLI project linkage. Its local-service ports and settings are
  inert here — ignore them rather than tuning them.
- Applying a migration means either the Supabase MCP `apply_migration` tool, the SQL editor in the
  dashboard, or `supabase db push --linked` against the linked project. Prefer whichever is already
  authenticated in the current session.
- Generated types ([../lib/supabase/types.ts](../lib/supabase/types.ts)) come from the remote
  project, not a local instance. Regenerate after every applied migration.
- Seed data ([../supabase/seed.sql](../supabase/seed.sql)) is applied manually to the remote project.
  It must be idempotent — no local reset exists to clean up after a half-applied run.

**Tradeoff being accepted:** no free rollback. There is no `db reset` to undo a bad migration, so
every migration should be small, forward-only, and paired with a way back if it drops or rewrites
data. Branching (Supabase preview branches) is the escape hatch if a change ever feels too risky to
apply straight to the project.

## 2. No Docker

**Decision:** Docker is not installed and will not be used. Avoid every path that depends on it.

This rules out, among others:

- The local Supabase stack in all its forms (it is Docker Compose underneath).
- Containerised test databases, testcontainers-style setups.
- Any suggested fix whose first step is "run the container".

If a tool's documented happy path requires Docker, the answer is to find the hosted or CLI-only
equivalent, not to install Docker. If no such equivalent exists, that tool is out of scope and the
approach needs rethinking.

## 3. Environment and secrets

- Local development runs `next dev` against the remote Supabase project, using the project URL and
  publishable (anon) key from `.env.local`.
- `.env.local` is never committed. The service role key does not belong in any client-reachable
  code path — RLS is the security model, not key secrecy.
- Vercel holds the same variables per environment. Preview and production should point at the same
  project for now; a separate project or branch per environment is a later decision if it becomes
  necessary.

## 4. Migration workflow

1. Write the migration as a new timestamped file in `supabase/migrations/`.
2. Apply it to the remote project.
3. Regenerate `lib/supabase/types.ts`.
4. Commit the migration and the regenerated types together, so the schema and the types in the repo
   never disagree.

Every table ships with RLS enabled and policies in the same migration that creates it. A table with
no policy is a table nobody can read, which fails loudly — that is the intended safety behaviour,
not a bug to work around by disabling RLS.

## 5. Open items

- Data access pattern (Supabase client directly in server components vs a query layer) — still
  undecided per PROJECT.MD section 7. Blocks Phase 1 code.
- Test strategy: whatever is chosen must not assume a throwaway local database, since there is not
  one. Likely implication is testing against the remote project with clearly-namespaced test data,
  or leaning on type checking plus manual verification for Phase 1.
