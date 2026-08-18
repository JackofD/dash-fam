-- Dash Fam — Phase 1 (Foundation + Lists) initial schema.
--
-- Source of truth: project-docs/01-schema-foundation-lists.md (statement order §9),
-- project-docs/02-auth-flow.md §3.1–3.2 (invited_email + signup linking trigger),
-- project-docs/04-decisions-log.md D-01 (household timezone), D-07 (theme_preference),
-- D-09 (sort_position, not position).
--
-- Standing rules honoured here:
--   * All domain FKs reference members.id, never auth.users (ADR-006).
--   * household_id lives on every domain table; on list_items it is trigger-maintained.
--   * RLS is the security boundary. Enabled before any policy is written.
--   * Enums are text + CHECK, never Postgres ENUM types.

-- ---------------------------------------------------------------------------
-- 1. households
-- ---------------------------------------------------------------------------

create table public.households (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) between 1 and 60),
  -- D-01: the household timezone is authoritative for all "today" logic.
  -- Timestamps stay timestamptz (UTC); only the day boundary uses this zone.
  timezone    text not null default 'Africa/Johannesburg',
  created_at  timestamptz not null default now()
);

-- No owner_id: there is no owner concept in v1.

-- ---------------------------------------------------------------------------
-- 2. members  (references households and auth.users)
-- ---------------------------------------------------------------------------

create table public.members (
  id                uuid primary key default gen_random_uuid(),
  household_id      uuid not null references public.households(id) on delete cascade,
  -- Nullable: the three kids have no account. Unique: one auth user must never
  -- map to two members. set null on delete: the person outlives their login.
  user_id           uuid unique references auth.users(id) on delete set null,
  -- auth §3.1 — the email a member is expected to sign in with, before any
  -- account exists. Lowercased by constraint so matching is case-insensitive.
  -- D-10: write-once seed data; never resynced if the auth email later changes.
  invited_email     text unique
                      check (invited_email is null or invited_email = lower(invited_email)),
  display_name      text not null check (length(trim(display_name)) between 1 and 40),
  colour            text not null check (colour ~ '^#[0-9a-fA-F]{6}$'),
  -- Descriptive only. Never write a policy against is_adult.
  is_adult          boolean not null default false,
  sort_order        smallint not null default 0,
  -- D-07: per-member theme, read server-side to avoid a theme flash.
  theme_preference  text not null default 'system'
                      check (theme_preference in ('system', 'light', 'dark')),
  deactivated_at    timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3. current_household_id()  (reads members)
-- ---------------------------------------------------------------------------

-- security definer so that policies *on* members can call it without the
-- policy recursing into itself. stable so Postgres calls it once per statement
-- rather than once per row. set search_path so a caller who can create objects
-- cannot shadow a name this function resolves.
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

-- ---------------------------------------------------------------------------
-- 4. link_member_on_signup()  (auth §3.2)
-- ---------------------------------------------------------------------------

-- Linking a member to an auth user is what grants access, so it happens here
-- and nowhere else — never as a client write. A new auth user whose email
-- matches no invited_email simply stays unlinked and is denied by RLS.
create or replace function public.link_member_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.members
     set user_id = new.id,
         updated_at = now()
   where invited_email = lower(new.email)
     and user_id is null;

  -- No exception on no match: a stranger is not an error, just a user with
  -- no household who sees nothing.
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.link_member_on_signup();

-- ---------------------------------------------------------------------------
-- 5. lists  (references households and members)
-- ---------------------------------------------------------------------------

create table public.lists (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  name          text not null check (length(trim(name)) between 1 and 60),
  -- Two values only. 'grocery' exists so Phase 4 knows where to write
  -- meal ingredients without guessing by name.
  kind          text not null default 'general'
                  check (kind in ('general', 'grocery')),
  created_by    uuid references public.members(id) on delete set null,
  -- Soft delete: deleting a list destroys many items at once.
  archived_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 6. list_items  (references lists, households, members)
-- ---------------------------------------------------------------------------

create table public.list_items (
  id            uuid primary key default gen_random_uuid(),
  list_id       uuid not null references public.lists(id) on delete cascade,
  -- Denormalised from lists so every RLS check is a comparison, not a join.
  -- Maintained by list_items_set_household() below; never client-supplied.
  household_id  uuid not null references public.households(id) on delete cascade,
  content       text not null check (length(trim(content)) between 1 and 200),
  -- D-09: sort_position, not position. double precision so reordering by
  -- averaging two neighbours touches one row instead of rewriting the tail.
  sort_position double precision not null,
  is_complete   boolean not null default false,
  completed_at  timestamptz,
  completed_by  uuid references public.members(id) on delete set null,
  created_by    uuid references public.members(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- completed_by may be null even when complete: a deactivated member's
  -- reference is set null.
  constraint list_items_completion_consistent check (
    (is_complete = false and completed_at is null and completed_by is null)
    or (is_complete = true and completed_at is not null)
  )
);

-- ---------------------------------------------------------------------------
-- 7. set_updated_at() and its triggers
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- 8. list_items_set_household() and its trigger
-- ---------------------------------------------------------------------------

-- Makes list_items.household_id derived rather than supplied, which removes
-- the class of bug where a client writes an item into another household's
-- list by sending a mismatched pair.
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

-- ---------------------------------------------------------------------------
-- 9. Enable RLS on all four tables, before any policy exists
-- ---------------------------------------------------------------------------

alter table public.households  enable row level security;
alter table public.members     enable row level security;
alter table public.lists       enable row level security;
alter table public.list_items  enable row level security;

-- ---------------------------------------------------------------------------
-- 10. Policies — per operation, to authenticated only. Nothing is public.
-- ---------------------------------------------------------------------------

-- households: select only. The single row comes from seed; no client may
-- create or modify a household in v1.
create policy households_select on public.households
  for select to authenticated
  using (id = public.current_household_id());

create policy members_select on public.members
  for select to authenticated
  using (household_id = public.current_household_id());

-- A client may add a member (a fourth kid) but never one already linked to
-- an account: linking is what grants access.
create policy members_insert on public.members
  for insert to authenticated
  with check (
    household_id = public.current_household_id()
    and user_id is null
  );

-- Update may edit every other column but cannot change user_id. Without this
-- guard, repointing a member row at your own user_id is privilege escalation.
create policy members_update on public.members
  for update to authenticated
  using (household_id = public.current_household_id())
  with check (
    household_id = public.current_household_id()
    and user_id is not distinct from (
      select m.user_id from public.members m where m.id = members.id
    )
  );

-- No members delete policy: members are deactivated via update, never deleted.

create policy lists_select on public.lists
  for select to authenticated
  using (household_id = public.current_household_id());

create policy lists_insert on public.lists
  for insert to authenticated
  with check (household_id = public.current_household_id());

-- Both clauses: using picks the rows you may attempt to modify, with check
-- validates the result. Omitting with check lets a row be moved out of the
-- household.
create policy lists_update on public.lists
  for update to authenticated
  using (household_id = public.current_household_id())
  with check (household_id = public.current_household_id());

create policy lists_delete on public.lists
  for delete to authenticated
  using (household_id = public.current_household_id());

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

-- ---------------------------------------------------------------------------
-- 11. Realtime — lists sync between devices. RLS applies to subscribers.
-- ---------------------------------------------------------------------------

-- Replica identity stays default: delete payloads carry only the primary key,
-- and removing by id is sufficient for the client.
alter publication supabase_realtime add table public.lists;
alter publication supabase_realtime add table public.list_items;

-- ---------------------------------------------------------------------------
-- 12. Indexes (schema §10)
-- ---------------------------------------------------------------------------

create index members_household_id_idx on public.members (household_id);
create index members_user_id_idx on public.members (user_id) where user_id is not null;

-- Almost every query wants non-archived lists.
create index lists_household_id_idx on public.lists (household_id)
  where archived_at is null;

create index list_items_list_id_idx on public.list_items (list_id, is_complete, sort_position);
create index list_items_household_id_idx on public.list_items (household_id);
