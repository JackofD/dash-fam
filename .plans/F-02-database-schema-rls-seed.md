# F-02 — Database Schema, RLS & Seed Data

> On approval, this plan lives at `.plans/F-02-database-schema-rls-seed.md` in the repo. Every other artifact this feature produces (the migration file, `seed.sql`, the RLS test) is created by executing the steps below against the **local Supabase Docker stack** — no production project is touched in this feature.

## Context

Dash Fam is a private single-household PWA (shared lists, chores, calendar, meals) shipped in phases; Phase 1 is Foundation + Lists only. F-01 scaffolded the Next.js app, CI, and Vercel deploy. The `supabase/migrations/` and `src/lib/supabase/` folders currently exist only as `.gitkeep` placeholders — there is no schema, no local DB, and no seed.

**F-02 builds the entire data foundation**: the four Phase-1 tables (`households`, `members`, `lists`, `list_items`), the `security definer` helper/trigger functions, Row-Level Security policies, Realtime enablement, and the five-member seed — delivered as a **single init migration** plus `seed.sql`, verified locally with `supabase db reset`.

**In scope:** local Supabase stack, the init migration, seed data, and one negative-case RLS test (D-08). **Out of scope (later features):** the three SSR Supabase client factories + `src/middleware.ts` (F-03 auth wiring), the query/action layer (ADR-005), any UI, and pushing to a prod project. The source of truth is `project-docs/01-schema-foundation-lists.md` (SQL, migration order §9, RLS §5, realtime §6, seed §7), with the `invited_email` column + signup trigger from `02-auth-flow.md` §3.1–3.2, and the deltas D-01/D-07/D-09 from `04-decisions-log.md`. **The decisions log overrides "Open items" in the schema doc** — so `sort_position` (not `position`) is authoritative.

---

## Definition of Done (from env doc)

Maps to env-doc checklist **steps 4–5**: `supabase init` + `supabase start` work locally, and the first migration written from the schema doc + decision deltas applies cleanly via `supabase db reset` together with the seed. Plus the D-08 negative RLS test passes. Prod link/push (env step 7) is deferred.

---

## Steps

### 1. Initialise the local Supabase stack (env §5.1)

```bash
supabase init          # creates supabase/config.toml
supabase start         # boots Postgres/Auth/Realtime/Studio in Docker; prints local URLs + keys
```

> The local DB is disposable — `supabase db reset` rebuilds it from migrations + `seed.sql`. That command is how the whole feature is verified. The printed anon/service-role keys and API URL are the values that will go in `.env.local` in a later feature; do **not** commit them and do **not** let the service-role key reach any client/Phase-1 code.

### 2. Create the single init migration (env §5.2)

```bash
supabase migration new init_foundation_lists
```

Populate `supabase/migrations/<timestamp>_init_foundation_lists.sql` following the schema doc's migration order (§9). Because prod does not exist yet, this one file may be edited freely until it lands on prod. **Fold the deltas directly into the base DDL** — do not append `ALTER TABLE`s for things known now. Order:

1. **`households`** — base DDL from schema §3.1, **plus D-01**: add `timezone text not null default 'Africa/Johannesburg'` as a column in the `create table`. No `owner_id`.
2. **`members`** — base DDL from schema §3.2, **plus** three folded-in additions:
   - **D-07:** `theme_preference text not null default 'system' check (theme_preference in ('system','light','dark'))`
   - **auth §3.1:** `invited_email text unique check (invited_email is null or invited_email = lower(invited_email))`
   - Keep `user_id uuid unique references auth.users(id) on delete set null` (nullable — kids have none), `colour text check (colour ~ '^#[0-9a-fA-F]{6}$')`, `is_adult`, `sort_order smallint`, `deactivated_at`.
3. **`current_household_id()`** — `sql`, `stable`, `security definer`, `set search_path = public, pg_temp`; `revoke all from public` + `grant execute to authenticated`. (§4.1 — `stable` = one call per statement; `search_path` prevents definer hijack; `security definer` avoids the members-policy recursion trap.)
4. **`lists`** — schema §3.3. `kind text default 'general' check (kind in ('general','grocery'))`; `created_by references members(id)`; `archived_at` for soft delete.
5. **`list_items`** — schema §3.4, **with D-09 applied**: the ordering column is **`sort_position double precision not null`** (never `position`). Denormalised `household_id`; the `list_items_completion_consistent` CHECK.
6. **`set_updated_at()`** + `before update` triggers on `members`, `lists`, `list_items`.
7. **`list_items_set_household()`** (`security definer`, `set search_path`) + `before insert or update of list_id` trigger — derives `household_id` from the parent list, raises if the list is missing. Never trust a client-sent `household_id`.
8. **Enable RLS** on all four tables *before* policies.
9. **Policies** (§5) — per-operation, `to authenticated`, keyed on `current_household_id()`:
   - `households`: SELECT only.
   - `members`: SELECT (household match); INSERT `with check (household_id = current_household_id() and user_id is null)`; UPDATE with the `user_id is not distinct from (select ...)` guard so linking can't happen client-side. **No delete policy** (deactivate via update).
   - `lists` / `list_items`: SELECT/INSERT/UPDATE/DELETE, every UPDATE carrying **both** `using` and `with check` (omitting `with check` lets a row be moved out of the household).
10. **Realtime** (§6): `alter publication supabase_realtime add table public.lists;` and `... public.list_items;`. Replica identity stays default — delete-by-id is sufficient.

> The `invited_email` mismatch is intentional and resolved: the base schema doc (§3.2) has no email column; the column and its uniqueness/lowercase constraint come from **auth doc §3.1**, and the `link_member_on_signup()` trigger from **§3.2**. Add both here.

### 3. Add the signup-linking trigger (auth §3.2)

In the same migration, after `members`: `link_member_on_signup()` — `security definer`, `set search_path`, updates `members.user_id = new.id where invited_email = lower(new.email) and user_id is null`, no exception on no-match (a stranger simply stays unlinked and is denied by RLS). Trigger `on_auth_user_created after insert on auth.users for each row`.

### 4. Add all indexes (schema §10)

`members(household_id)`; partial `members(user_id) where user_id is not null`; partial `lists(household_id) where archived_at is null`; composite `list_items(list_id, is_complete, sort_position)` (**note the D-09 rename in the index too**); `list_items(household_id)`.

### 5. Write `supabase/seed.sql` (schema §7, D-10)

- One household, **fixed id** `00000000-0000-0000-0000-000000000001`, name `Dash Fam`, `on conflict (id) do nothing`. Timezone defaults to `Africa/Johannesburg`.
- **Five members** against that household, `user_id` null for all five. Give each a distinct hex from the five-colour palette (D-06: coral/amber/emerald/azure/violet), `is_adult` true for the two adults, and stable `sort_order`.
- The **two adults** get `invited_email` set to their real sign-in addresses (write-once, D-10 — never kept in sync afterward; the link persists via `user_id`). Kids leave `invited_email` null.
- One **grocery list** (`kind = 'grocery'`) so Phase 1 has content on first load.

> No invite/claim flow, no assignee column (D-03 defers `assigned_member_id`). Linking the two adult accounts to `user_id` happens later, once — by the signup trigger on first real sign-in — not in seed.

### 6. Verify locally (env §5.2)

```bash
supabase db reset      # rebuilds from the migration + runs seed.sql; must complete with no errors
```

Open Studio; confirm four tables, RLS badge on each, the seeded household/5 members/grocery list, and that `current_household_id`, `link_member_on_signup`, `set_updated_at`, `list_items_set_household` exist.

### 7. Add the D-08 negative-case RLS test

The one thing that must be tested, not eyeballed — RLS failures are silent. Add a repeatable SQL/pgTAP-style test (runnable against the local stack, wired toward the future `npm run test` CI step) that asserts: **an authenticated user who resolves to no household (`current_household_id()` is null — e.g. a session for an email matching no `invited_email`) reads zero rows from all four tables**, and that the members INSERT/UPDATE policies reject a client attempt to set/change `user_id`. Keep it minimal; the add-item/tick-item critical-path tests can follow with the query/action layer.

### 8. Standing constraints to honour while building the schema

- **All domain FKs reference `members.id`, never `auth.users`** (ADR-006). `member_id` never implies an auth user exists.
- **Linking `user_id` is never a client write** — only the signup trigger sets it; the members policies must block it.
- **`household_id` on every domain table** from this first migration; on `list_items` it is trigger-maintained, never client-supplied.
- **RLS is the security boundary** — no household filtering in app code, ever. The service-role key never reaches client/Phase-1 code.
- **Text + CHECK, not Postgres ENUM.** UUID PKs, `timestamptz` (UTC). Migrations are new files; this init file is editable only until it hits prod.
- **Enable RLS before writing policies**; verify a member-less authenticated session gets zero rows (not an error) on every table.

---

## Critical files created

- `supabase/config.toml` — from `supabase init`.
- `supabase/migrations/<timestamp>_init_foundation_lists.sql` — the single Phase-1 migration (tables, functions, triggers, RLS, realtime, indexes).
- `supabase/seed.sql` — household + five members + grocery list.
- RLS test file (location per the future test setup, e.g. `supabase/tests/rls.test.sql` or a `tests/` harness) — the D-08 negative case.
- `.plans/F-02-database-schema-rls-seed.md` — this plan.

## Verification (end-to-end)

1. `supabase start` boots the stack cleanly in Docker.
2. `supabase db reset` applies the migration and `seed.sql` with **zero errors** — this is the core gate.
3. In Studio: four tables exist, each shows RLS enabled; the seed shows one household, five members (two with `invited_email`, all `user_id` null), one grocery list.
4. The four functions and their triggers exist; inserting a `list_item` with a bogus client `household_id` still lands in the correct household (trigger overrides it).
5. The D-08 negative RLS test passes: a no-household authenticated session sees zero rows on all four tables, and `user_id` cannot be set/changed via the members policies.
6. `npx tsc --noEmit`, `npm run lint`, `npm run build` remain green (no app code changed, but confirm the repo still builds).

## Decided

- **Local-only** for F-02: build and verify entirely on the local Docker stack; creating/linking the prod project and `supabase db push` (env §5.3) are deferred to a later feature.
- **Single init migration** (`init_foundation_lists`) with D-01/D-07/D-09 and the `invited_email` column + signup trigger folded into the base DDL — not a chain of `ALTER TABLE`s — since no data exists yet.
- Include the **D-08 negative-case RLS test** now; defer the add/tick critical-path tests to the query/action feature.
