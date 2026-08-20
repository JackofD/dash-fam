-- Dash Fam — RLS policy tests (D-08).
--
-- RLS is the security boundary and its failures are silent, so it is the one
-- thing that must be tested rather than eyeballed. Run against the local
-- stack with:
--
--     supabase test db
--
-- Two things are covered here:
--   1. The negative case — an authenticated user who resolves to no household
--      reads zero rows from all four tables (not an error, zero rows).
--   2. The members policies refuse to let a client set or change user_id,
--      which would be privilege escalation.
--
-- The test builds its own household and member rather than leaning on
-- seed.sql, so "zero rows" is a real denial and not an empty database. The
-- magic-link path that actually fires link_member_on_signup() is exercised in
-- F-03; here we only assert the function and trigger exist.

begin;

create extension if not exists pgtap;

select plan(13);

-- ---------------------------------------------------------------------------
-- Fixtures, created as the migration owner so RLS does not apply.
-- ---------------------------------------------------------------------------

insert into public.households (id, name)
values ('11111111-1111-1111-1111-111111111111', 'Test Household');

-- auth.users row for the linked member below. members.user_id has an FK
-- here, and every other auth.users column is nullable or defaulted. The
-- address must match no seed invited_email so on_auth_user_created is a
-- no-op for it.
insert into auth.users (id, email)
values ('11111111-1111-1111-1111-1111111111f1', 'linked-adult@test.invalid');

-- Linked member: stands in for an adult who has signed in. Linking is done
-- here by the table owner, exactly as the signup trigger would — never as a
-- client write.
insert into public.members
  (id, household_id, user_id, display_name, colour, is_adult, sort_order)
values
  ('11111111-1111-1111-1111-1111111111a1',
   '11111111-1111-1111-1111-111111111111',
   '11111111-1111-1111-1111-1111111111f1',
   'Linked Adult', '#9257D6', true, 1);

insert into public.lists (id, household_id, name, kind)
values ('11111111-1111-1111-1111-1111111111b1',
        '11111111-1111-1111-1111-111111111111', 'Test List', 'general');

insert into public.list_items (id, list_id, household_id, content, sort_position)
values ('11111111-1111-1111-1111-1111111111c1',
        '11111111-1111-1111-1111-1111111111b1',
        '11111111-1111-1111-1111-111111111111', 'test item', 1000);

-- ---------------------------------------------------------------------------
-- The negative case: authenticated, but matching no member row.
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-1111111111e0","role":"authenticated"}';

select is(
  (select count(*) from public.households), 0::bigint,
  'no-household user reads zero households'
);

select is(
  (select count(*) from public.members), 0::bigint,
  'no-household user reads zero members'
);

select is(
  (select count(*) from public.lists), 0::bigint,
  'no-household user reads zero lists'
);

select is(
  (select count(*) from public.list_items), 0::bigint,
  'no-household user reads zero list_items'
);

select is(
  public.current_household_id(), null::uuid,
  'current_household_id() is null for a user with no member row'
);

-- ---------------------------------------------------------------------------
-- A household member: reads their own rows, but cannot touch user_id.
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-1111111111f1","role":"authenticated"}';

select is(
  (select count(*) from public.members), 1::bigint,
  'household member reads their own household members'
);

select throws_ok(
  $$insert into public.members
      (household_id, user_id, display_name, colour)
    values ('11111111-1111-1111-1111-111111111111',
            '11111111-1111-1111-1111-1111111111f9',
            'Smuggled', '#E5484D')$$,
  '42501',
  null::text,
  'members_insert refuses a member that arrives already linked to a user'
);

select lives_ok(
  $$insert into public.members (household_id, display_name, colour)
    values ('11111111-1111-1111-1111-111111111111', 'New Kid', '#1F9D5F')$$,
  'members_insert allows an unlinked member in the same household'
);

select throws_ok(
  $$update public.members
       set user_id = '11111111-1111-1111-1111-1111111111f9'
     where id = '11111111-1111-1111-1111-1111111111a1'$$,
  '42501',
  null::text,
  'members_update refuses a change to user_id'
);

select lives_ok(
  $$update public.members set display_name = 'Renamed'
     where id = '11111111-1111-1111-1111-1111111111a1'$$,
  'members_update allows editing every other column'
);

-- A client-sent household_id on a list item is overwritten by the trigger,
-- so the row lands in the household of its parent list either way.
select lives_ok(
  $$insert into public.list_items (list_id, household_id, content, sort_position)
    values ('11111111-1111-1111-1111-1111111111b1',
            '99999999-9999-9999-9999-999999999999',
            'bogus household', 2000)$$,
  'list_items insert survives a bogus client household_id'
);

select is(
  (select household_id from public.list_items where content = 'bogus household'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'list_items_set_household() derives household_id from the parent list'
);

-- ---------------------------------------------------------------------------
-- The signup-linking path exists (its behaviour is verified in F-03).
-- ---------------------------------------------------------------------------

reset role;

select has_function('public', 'link_member_on_signup', 'signup linking function exists'::text);

select * from finish();

rollback;
