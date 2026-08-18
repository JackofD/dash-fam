# Dash Fam: Schema, Phase 1 (Foundation + Lists)

**Status:** Draft v0.1
**Last updated:** 2026-08-13
**Covers:** `households`, `members`, `lists`, `list_items` and their RLS policies
**Depends on:** 00-project-scope.md

---

## 1. What this document is for

Phase 1 needs four tables and nothing else. This document specifies them, the policies that guard them, and the reasoning behind the choices that are not obvious. Chores, events and meals get their own document when their phase starts.

Two constraints from the scope doc drive most of what follows:

1. A member is a person; an account is a login. Three of five members have no account. Domain data references members, never auth users.
2. `household_id` exists on every domain table from the first migration, even with one household, so multi-tenancy stays a migration rather than a rewrite.

---

## 2. Conventions

| Convention | Choice | Reasoning |
|---|---|---|
| Primary keys | `uuid` default `gen_random_uuid()` | Generatable client-side, no sequence to leak row counts, and safe if data is ever merged across environments |
| Timestamps | `timestamptz`, default `now()` | Never `timestamp` without a zone. Store UTC, render in the browser's zone. |
| Naming | `snake_case`, plural tables | Postgres convention, avoids quoting |
| Soft delete | Only where history matters | See 2.1 |
| Enums | Postgres `text` + `CHECK` constraint | See 2.2 |
| Audit columns | `created_at` everywhere, `updated_at` only where rows are edited | Do not add columns nothing reads |

### 2.1 Delete strategy

Hard delete for list items. If someone deletes "milk" from the grocery list, nobody will ever want it back, and a soft-deleted-items filter on every query is a permanent tax for no benefit.

Soft delete (`archived_at`) for lists, because deleting a list destroys many items at once and that is the kind of mistake people want undone.

Members are never deleted. A member who has completed chores and appears on events cannot be removed without orphaning history. Use `deactivated_at` to hide them from assignment pickers while keeping their history intact.

### 2.2 Enums as text plus CHECK, not Postgres ENUM types

Postgres native `ENUM` types are awkward to change: adding a value is fine, but removing or reordering one requires recreating the type and every column using it. A `text` column with a `CHECK` constraint gives the same integrity, and changing the allowed set is one `ALTER TABLE` statement.

This matters concretely for the meal slot column in Phase 4, where the scope doc anticipates adding breakfast later.

---

## 3. Tables

### 3.1 `households`

```sql
create table public.households (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) between 1 and 60),
  created_at  timestamptz not null default now()
);
```

One row for now. It exists so that `household_id` on every other table has something real to point at, and so the multi-tenant path stays open.

No `owner_id`. There is no owner concept in v1, and inventing one now means writing policies for a role nobody has.

### 3.2 `members`

The load-bearing table.

```sql
create table public.members (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references public.households(id) on delete cascade,
  user_id         uuid unique references auth.users(id) on delete set null,
  display_name    text not null check (length(trim(display_name)) between 1 and 40),
  colour          text not null check (colour ~ '^#[0-9a-fA-F]{6}$'),
  is_adult        boolean not null default false,
  sort_order      smallint not null default 0,
  deactivated_at  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index members_household_id_idx on public.members (household_id);
create index members_user_id_idx on public.members (user_id) where user_id is not null;
```

Notes on the columns that carry weight:

**`user_id` is nullable and unique.** Nullable because the three kids have no account. Unique because one auth user must never map to two members. `on delete set null` rather than `cascade`: if an auth user is deleted, the person still exists and their history must survive. This single column is the entire members-versus-accounts design.

**`colour`** is here because a family dashboard is unreadable without per-person colour coding, and it needs to be consistent across chores, events and meals. Storing it on the member means it is decided once. The CHECK constraint enforces a hex value so the UI never has to defend against garbage.

**`is_adult`** is deliberately descriptive, not a permission. Both adults have identical rights, and the scope doc rules out parent/child permissions for v1. This flag is for display and filtering only, for example defaulting the "who is this chore for" picker. Do not write a policy against it. If real permissions ever arrive, they get an explicit `role` column and this flag stays what it is.

**`sort_order`** so the family appears in a stable, human-chosen order rather than by creation time or alphabetically.

**No `email` column.** Email lives in `auth.users` for members who have accounts. Duplicating it creates two sources of truth that will drift.

### 3.3 `lists`

```sql
create table public.lists (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  name          text not null check (length(trim(name)) between 1 and 60),
  kind          text not null default 'general'
                  check (kind in ('general', 'grocery')),
  created_by    uuid references public.members(id) on delete set null,
  archived_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index lists_household_id_idx on public.lists (household_id)
  where archived_at is null;
```

**`kind`** exists for exactly one reason: Phase 4 needs to know which list to bulk-add meal ingredients to. Without it, that feature has to guess by name, which breaks the moment someone renames the list. Two values only. Resist adding more.

**`created_by` references `members`, not `auth.users`.** This is the pattern for every actor reference in the schema. `on delete set null` so removing a member never deletes their lists.

The partial index reflects that almost every query wants non-archived lists.

### 3.4 `list_items`

```sql
create table public.list_items (
  id            uuid primary key default gen_random_uuid(),
  list_id       uuid not null references public.lists(id) on delete cascade,
  household_id  uuid not null references public.households(id) on delete cascade,
  content       text not null check (length(trim(content)) between 1 and 200),
  position      double precision not null,
  is_complete   boolean not null default false,
  completed_at  timestamptz,
  completed_by  uuid references public.members(id) on delete set null,
  created_by    uuid references public.members(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint list_items_completion_consistent check (
    (is_complete = false and completed_at is null and completed_by is null)
    or (is_complete = true and completed_at is not null)
  )
);

create index list_items_list_id_idx on public.list_items (list_id, is_complete, position);
create index list_items_household_id_idx on public.list_items (household_id);
```

Three things here deserve explanation.

**`household_id` is denormalised onto this table** even though it is reachable via `list_id`. This is intentional and the reason is RLS performance: without it, every policy check on `list_items` requires a join to `lists`. With it, the check is a direct comparison. The cost is a redundant column that must be kept correct, which a trigger handles (see 4.3). For a table that will be read constantly and filtered by RLS on every single row, this trade is worth making.

**`position` is `double precision`, not an integer.** Reordering by integer requires rewriting every subsequent row. With a float you insert between two items by averaging their positions, touching one row. The known limitation is float precision exhausting after many repeated insertions in the same gap, which in practice takes far more reordering than a grocery list will ever see. If it ever became a problem the fix is a periodic renumber.

**The completion CHECK constraint** stops the impossible state of an item marked complete with no completion time. `completed_by` is allowed to be null even when complete, because a member could be deactivated and the reference set to null.

---

## 4. Functions and triggers

### 4.1 The RLS helper, and the recursion trap

Every policy needs to answer "which household does the current user belong to?" The obvious way to write that is a subquery against `members`. Doing so inside a policy **on** `members` causes infinite recursion: the policy queries the table, which invokes the policy, which queries the table.

The fix is a `security definer` function, which runs with the definer's rights and therefore bypasses RLS on the tables it touches.

```sql
create or replace function public.current_household_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select household_id
  from public.members
  where user_id = auth.uid()
    and deactivated_at is null
  limit 1;
$$;

revoke all on function public.current_household_id() from public;
grant execute on function public.current_household_id() to authenticated;
```

Points that matter for safety and performance:

- **`set search_path`** is not optional on a `security definer` function. Without it, a caller who can create objects could shadow a name the function resolves and hijack execution.
- **`stable`** lets Postgres call it once per statement rather than once per row. On a policy applied to every row of a list, this is the difference between one query and hundreds.
- **`limit 1`** is safe today because one user maps to one member maps to one household. If a person ever belongs to two households, this function's contract changes and every policy using it needs revisiting. Written down here so that is not a surprise.
- Deactivated members resolve to null and therefore see nothing. That is the intended behaviour: deactivating a member revokes their access.

### 4.2 `updated_at` maintenance

```sql
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger members_set_updated_at
  before update on public.members
  for each row execute function public.set_updated_at();

create trigger lists_set_updated_at
  before update on public.lists
  for each row execute function public.set_updated_at();

create trigger list_items_set_updated_at
  before update on public.list_items
  for each row execute function public.set_updated_at();
```

Doing this in a trigger rather than in application code means it cannot be forgotten and cannot be lied about by a client.

### 4.3 Keeping the denormalised `household_id` honest

The redundant column on `list_items` is only safe if the database maintains it. Never trust the client to send it.

```sql
create or replace function public.list_items_set_household()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  select l.household_id into new.household_id
  from public.lists l
  where l.id = new.list_id;

  if new.household_id is null then
    raise exception 'list % not found', new.list_id;
  end if;

  return new;
end;
$$;

create trigger list_items_set_household
  before insert or update of list_id on public.list_items
  for each row execute function public.list_items_set_household();
```

This makes the column derived rather than supplied, which removes the class of bug where a client writes an item into another household's list by sending a mismatched pair.

---

## 5. Row Level Security

### 5.1 Rules that apply to every table

- RLS is enabled on every table in `public`. A table without policies and with RLS enabled denies everything, which is the correct default.
- No policies for the `anon` role. Nothing in Dash Fam is public.
- Policies are written per operation rather than as one `for all` policy, because insert and update need `with check` and select needs `using`, and combining them obscures which clause guards what.

```sql
alter table public.households  enable row level security;
alter table public.members     enable row level security;
alter table public.lists       enable row level security;
alter table public.list_items  enable row level security;
```

### 5.2 `households`

```sql
create policy households_select on public.households
  for select to authenticated
  using (id = public.current_household_id());
```

Select only. There is no policy for insert, update or delete, which means no client can create or modify a household. The one row is created by a seed migration. This is deliberate: household creation is not a user-facing feature in v1, so it gets no user-facing capability.

### 5.3 `members`

```sql
create policy members_select on public.members
  for select to authenticated
  using (household_id = public.current_household_id());

create policy members_insert on public.members
  for insert to authenticated
  with check (
    household_id = public.current_household_id()
    and user_id is null
  );

create policy members_update on public.members
  for update to authenticated
  using (household_id = public.current_household_id())
  with check (
    household_id = public.current_household_id()
    and user_id is not distinct from (
      select m.user_id from public.members m where m.id = members.id
    )
  );
```

The two restrictions here are the security-relevant part of this document.

**Insert requires `user_id is null`.** An authenticated user may add a member (a fourth kid, say) but cannot create a member already linked to an account. Linking a member to an auth user is what grants access, so it must never be a client-side operation. When the invite flow arrives it will do that linking in a controlled server-side path, not through this policy.

**Update cannot change `user_id`.** Without this clause, any member row could be repointed at any auth user, which is a privilege escalation: attach your own `user_id` to a member in another household and `current_household_id()` starts returning theirs. The `is not distinct from` comparison against the existing value blocks it while still allowing every other column to be edited normally.

**No delete policy.** Per section 2.1, members are deactivated, not deleted. Setting `deactivated_at` goes through the update policy.

### 5.4 `lists` and `list_items`

Both follow the same shape, and both allow full read and write within the household because the scope doc states shared state with no gatekeeper.

```sql
create policy lists_select on public.lists
  for select to authenticated
  using (household_id = public.current_household_id());

create policy lists_insert on public.lists
  for insert to authenticated
  with check (household_id = public.current_household_id());

create policy lists_update on public.lists
  for update to authenticated
  using (household_id = public.current_household_id())
  with check (household_id = public.current_household_id());

create policy lists_delete on public.lists
  for delete to authenticated
  using (household_id = public.current_household_id());
```

```sql
create policy list_items_select on public.list_items
  for select to authenticated
  using (household_id = public.current_household_id());

create policy list_items_insert on public.list_items
  for insert to authenticated
  with check (household_id = public.current_household_id());

create policy list_items_update on public.list_items
  for update to authenticated
  using (household_id = public.current_household_id())
  with check (household_id = public.current_household_id());

create policy list_items_delete on public.list_items
  for delete to authenticated
  using (household_id = public.current_household_id());
```

Note that update policies need **both** clauses. `using` decides which rows you may attempt to modify; `with check` validates the row after modification. Omitting `with check` on an update policy allows moving a row out of your own household, which is a data leak in the other direction.

A `lists_delete` policy exists even though the app archives rather than deletes, because archiving is an update and hard delete is still wanted for genuine cleanup.

---

## 6. Realtime

Lists need real-time sync so two phones in the kitchen agree. Supabase Realtime's Postgres changes feed applies RLS to the authenticated subscriber, so a subscription cannot leak rows a query would not return. Both tables must be added to the publication explicitly:

```sql
alter publication supabase_realtime add table public.list_items;
alter publication supabase_realtime add table public.lists;
```

Two practical notes for the client work:

- Delete events carry only the primary key, not the full old row, unless replica identity is set to full. Since `list_items` deletes are hard deletes, the client must handle a delete payload that contains only an id. Removing by id is sufficient, so there is no need to change replica identity.
- Optimistic local updates plus an incoming realtime event for the same change will double-apply unless the client reconciles by id. Worth settling that pattern once before building.

---

## 7. Seed data

The five members are fixed and known, so they belong in a seed migration rather than a setup UI that gets used once.

```sql
insert into public.households (id, name)
values ('00000000-0000-0000-0000-000000000001', 'Dash Fam')
on conflict (id) do nothing;
```

Members are then inserted against that household id with `user_id` left null for all five. Linking the two adult accounts happens after those users first sign in, as a one-off manual update, because the auth user ids do not exist until then.

Do not build an invite or claim flow for this. Two rows, updated by hand, once.

The grocery list should be seeded too, with `kind = 'grocery'`, so Phase 4 has a target to write into and Phase 1 has something on screen from the first load.

---

## 8. Open items

1. **Colour palette.** `members.colour` needs a defined set of five distinguishable colours that also pass contrast requirements in both light and dark themes. Belongs in the style guide, not here.
2. **Naming `position`.** `position` is a reserved word in some SQL contexts and will need quoting in certain queries. Consider `sort_position` instead. Low stakes, but cheaper to change now than after data exists.
3. **Item assignment.** List items currently have no assignee. If "Deshen buys the milk" is a real need, that is another `member_id` column. Left out on purpose until the need proves itself.
4. **Timezone handling.** All timestamps are `timestamptz`, but "today" on a dashboard is a local-date question. Decide whether the household has a fixed timezone stored on `households` or whether the browser's zone is authoritative. It matters more in Phase 3 than Phase 1, but the decision should be made once.

---

## 9. Migration order

Statements must run in this order because of dependencies:

1. `households`
2. `members` (references households and `auth.users`)
3. `current_household_id()` (reads members)
4. `lists` (references households and members)
5. `list_items` (references lists, households, members)
6. `set_updated_at()` and its triggers
7. `list_items_set_household()` and its trigger
8. Enable RLS on all four tables
9. Policies
10. Realtime publication
11. Seed data

Enable RLS before writing policies, and verify by connecting as an authenticated user with no member row: every query should return zero rows rather than an error.
