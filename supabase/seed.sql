-- Dash Fam seed data (schema doc §7, D-06 palette, D-10 invited_email).
--
-- Runs after every `supabase db reset`, so every statement is idempotent.
-- Fixed ids throughout: the household and members are known, finite people,
-- and stable ids make the seed re-runnable and the RLS tests deterministic.
--
-- user_id is null for all five members. Linking the two adults happens once,
-- automatically, when they first sign in — link_member_on_signup() matches
-- their auth email against invited_email. Never link here.

-- ---------------------------------------------------------------------------
-- The one household
-- ---------------------------------------------------------------------------

insert into public.households (id, name)
values ('00000000-0000-0000-0000-000000000001', 'Dash Fam')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Five members: two adults with accounts to come, three kids without.
-- Colours are the five accessibility-verified values from the style guide
-- (§3.1) — coral, amber, emerald, azure, violet. Two members may never share
-- one, so each appears exactly once here.
-- ---------------------------------------------------------------------------

insert into public.members
  (id, household_id, display_name, colour, is_adult, sort_order, invited_email)
values
  ('00000000-0000-0000-0000-000000000101',
   '00000000-0000-0000-0000-000000000001',
   'Deshen', '#9257D6', true,  1, 'deshen.padayachee@rokkit200.co'),

  -- TODO(F-02): replace the placeholder name and sign-in address for the
  -- second adult before this seed is applied to production. invited_email is
  -- write-once (D-10) — get it right here rather than resyncing later.
  ('00000000-0000-0000-0000-000000000102',
   '00000000-0000-0000-0000-000000000001',
   'Adult Two', '#E5484D', true,  2, 'adult.two@example.com'),

  -- TODO(F-02): replace the three kids' display names. They have no
  -- invited_email and are not expected to sign in during v1.
  ('00000000-0000-0000-0000-000000000103',
   '00000000-0000-0000-0000-000000000001',
   'Kid One', '#1F9D5F', false, 3, null),

  ('00000000-0000-0000-0000-000000000104',
   '00000000-0000-0000-0000-000000000001',
   'Kid Two', '#2E7CF6', false, 4, null),

  ('00000000-0000-0000-0000-000000000105',
   '00000000-0000-0000-0000-000000000001',
   'Kid Three', '#F2A93B', false, 5, null)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- One grocery list, so Phase 1 has content on first load and Phase 4 has a
-- target to bulk-add meal ingredients into.
-- ---------------------------------------------------------------------------

insert into public.lists (id, household_id, name, kind, created_by)
values
  ('00000000-0000-0000-0000-000000000201',
   '00000000-0000-0000-0000-000000000001',
   'Groceries', 'grocery',
   '00000000-0000-0000-0000-000000000101')
on conflict (id) do nothing;
