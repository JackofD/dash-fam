-- Seed data, mirrored from the live Dash-Fam-dev database.
-- One household, five members (two adults carry invited_email), one grocery list.
--
-- TODO(F-02): the second adult and the three kids are still placeholders.
-- invited_email is write-once (D-10) — replace these before any production apply.

insert into public.households (id, name, timezone)
values ('00000000-0000-0000-0000-000000000001', 'Dash Fam', 'Africa/Johannesburg')
on conflict (id) do nothing;

insert into public.members (id, household_id, invited_email, display_name, colour, is_adult, sort_order)
values
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', 'deshen.padayachee@rokkit200.co', 'Deshen',    '#9257D6', true,  1),
  ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001', 'adult.two@example.com',          'Adult Two', '#E5484D', true,  2),
  ('00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000001', null,                             'Kid One',   '#1F9D5F', false, 3),
  ('00000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000001', null,                             'Kid Two',   '#2E7CF6', false, 4),
  ('00000000-0000-0000-0000-000000000105', '00000000-0000-0000-0000-000000000001', null,                             'Kid Three', '#F2A93B', false, 5)
on conflict (id) do nothing;

insert into public.lists (id, household_id, name, kind, created_by)
values ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000001', 'Groceries', 'grocery', '00000000-0000-0000-0000-000000000101')
on conflict (id) do nothing;
