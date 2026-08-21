-- Foundation + Lists (F-02).
-- Reconstructed from the live Dash-Fam-dev database; version matches the
-- migration already recorded remotely (20260818150009_init_foundation_lists).

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

create table if not exists public.households (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) between 1 and 60),
  timezone    text not null default 'Africa/Johannesburg',
  created_at  timestamptz not null default now()
);

-- A member is a person, not a login. Three of five have no account, so every
-- domain FK points here and never at auth.users (ADR-006).
create table if not exists public.members (
  id                uuid primary key default gen_random_uuid(),
  household_id      uuid not null references public.households(id) on delete cascade,
  user_id           uuid unique references auth.users(id) on delete set null,
  invited_email     text unique check (invited_email is null or invited_email = lower(invited_email)),
  display_name      text not null check (length(trim(display_name)) between 1 and 40),
  colour            text not null check (colour ~ '^#[0-9a-fA-F]{6}$'),
  is_adult          boolean not null default false,
  sort_order        smallint not null default 0,
  theme_preference  text not null default 'system' check (theme_preference in ('system', 'light', 'dark')),
  deactivated_at    timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table if not exists public.lists (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  name          text not null check (length(trim(name)) between 1 and 60),
  kind          text not null default 'general' check (kind in ('general', 'grocery')),
  created_by    uuid references public.members(id) on delete set null,
  archived_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.list_items (
  id             uuid primary key default gen_random_uuid(),
  list_id        uuid not null references public.lists(id) on delete cascade,
  -- Denormalised for RLS; maintained by trigger, never trusted from the client.
  household_id   uuid not null references public.households(id) on delete cascade,
  content        text not null check (length(trim(content)) between 1 and 200),
  sort_position  double precision not null,
  is_complete    boolean not null default false,
  completed_at   timestamptz,
  completed_by   uuid references public.members(id) on delete set null,
  created_by     uuid references public.members(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint list_items_completion_consistent check (
    (is_complete = false and completed_at is null and completed_by is null)
    or (is_complete = true and completed_at is not null)
  )
);

-- ---------------------------------------------------------------------------
-- 2. Indexes
-- ---------------------------------------------------------------------------

create index if not exists members_household_id_idx on public.members using btree (household_id);
create index if not exists members_user_id_idx on public.members using btree (user_id) where user_id is not null;
create index if not exists lists_household_id_idx on public.lists using btree (household_id) where archived_at is null;
create index if not exists list_items_household_id_idx on public.list_items using btree (household_id);
create index if not exists list_items_list_id_idx on public.list_items using btree (list_id, is_complete, sort_position);

-- ---------------------------------------------------------------------------
-- 3. Functions
-- ---------------------------------------------------------------------------

-- security definer + stable + fixed search_path: without these the RLS
-- policies that call this recurse through members' own policy.
create or replace function public.current_household_id()
returns uuid
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select household_id
  from public.members
  where user_id = auth.uid()
    and deactivated_at is null
  limit 1;
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.list_items_set_household()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
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

-- Linking is by email allowlist and happens server-side only.
create or replace function public.link_member_on_signup()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
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

-- ---------------------------------------------------------------------------
-- 4. Triggers
-- ---------------------------------------------------------------------------

drop trigger if exists members_set_updated_at on public.members;
create trigger members_set_updated_at
  before update on public.members
  for each row execute function public.set_updated_at();

drop trigger if exists lists_set_updated_at on public.lists;
create trigger lists_set_updated_at
  before update on public.lists
  for each row execute function public.set_updated_at();

drop trigger if exists list_items_set_updated_at on public.list_items;
create trigger list_items_set_updated_at
  before update on public.list_items
  for each row execute function public.set_updated_at();

drop trigger if exists list_items_set_household on public.list_items;
create trigger list_items_set_household
  before insert or update of list_id on public.list_items
  for each row execute function public.list_items_set_household();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.link_member_on_signup();

-- ---------------------------------------------------------------------------
-- 5. RLS — the security boundary. App code does no household filtering.
-- ---------------------------------------------------------------------------

alter table public.households enable row level security;
alter table public.members enable row level security;
alter table public.lists enable row level security;
alter table public.list_items enable row level security;

drop policy if exists households_select on public.households;
create policy households_select on public.households
  for select to authenticated
  using (id = current_household_id());

drop policy if exists members_select on public.members;
create policy members_select on public.members
  for select to authenticated
  using (household_id = current_household_id());

-- Client-side writes must never set or change user_id: that is privilege
-- escalation. Only link_member_on_signup() may link an account.
drop policy if exists members_insert on public.members;
create policy members_insert on public.members
  for insert to authenticated
  with check (household_id = current_household_id() and user_id is null);

drop policy if exists members_update on public.members;
create policy members_update on public.members
  for update to authenticated
  using (household_id = current_household_id())
  with check (
    household_id = current_household_id()
    and not (user_id is distinct from (select m.user_id from public.members m where m.id = members.id))
  );

drop policy if exists lists_select on public.lists;
create policy lists_select on public.lists
  for select to authenticated
  using (household_id = current_household_id());

drop policy if exists lists_insert on public.lists;
create policy lists_insert on public.lists
  for insert to authenticated
  with check (household_id = current_household_id());

drop policy if exists lists_update on public.lists;
create policy lists_update on public.lists
  for update to authenticated
  using (household_id = current_household_id())
  with check (household_id = current_household_id());

drop policy if exists lists_delete on public.lists;
create policy lists_delete on public.lists
  for delete to authenticated
  using (household_id = current_household_id());

drop policy if exists list_items_select on public.list_items;
create policy list_items_select on public.list_items
  for select to authenticated
  using (household_id = current_household_id());

drop policy if exists list_items_insert on public.list_items;
create policy list_items_insert on public.list_items
  for insert to authenticated
  with check (household_id = current_household_id());

drop policy if exists list_items_update on public.list_items;
create policy list_items_update on public.list_items
  for update to authenticated
  using (household_id = current_household_id())
  with check (household_id = current_household_id());

drop policy if exists list_items_delete on public.list_items;
create policy list_items_delete on public.list_items
  for delete to authenticated
  using (household_id = current_household_id());

-- ---------------------------------------------------------------------------
-- 6. Realtime — lists sync between devices; enabled per table, never assumed.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime' and pr.prrelid = 'public.lists'::regclass
  ) then
    alter publication supabase_realtime add table public.lists;
  end if;

  if not exists (
    select 1 from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime' and pr.prrelid = 'public.list_items'::regclass
  ) then
    alter publication supabase_realtime add table public.list_items;
  end if;
end
$$;
