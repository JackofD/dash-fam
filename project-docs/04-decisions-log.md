# Dash Fam: Decisions Log

**Status:** Accepted
**Last updated:** 2026-08-13
**Purpose:** Resolve every open item left across docs 00 to 03 in one place.
**Precedence:** Where this log conflicts with an "Open items" section in an earlier doc, **this log wins.** The earlier sections are considered closed.

This log covers the smaller decisions that did not each warrant an ADR. The seven architectural ADRs still stand as the record for the big calls; this is everything else.

---

## Decisions requiring input (resolved with the owner)

### D-01 — "Today" uses a fixed household timezone
**Resolves:** schema open item 4.
**Decision:** Store a timezone on the household and treat it as authoritative for all date logic ("today", "overdue", which day an event falls on). Value: `Africa/Johannesburg`.
**Why:** One household in one place. A device-local zone only ever diverges when someone travels, and when it does it creates the exact bug worth avoiding: two people disagreeing on what is due today. A fixed zone is simpler and correct.
**Change implied (schema):**
```sql
alter table public.households
  add column timezone text not null default 'Africa/Johannesburg';
```
Date-bucketing queries compute "today" in this zone, not in UTC and not in the browser's zone. Timestamps remain `timestamptz` (stored UTC); only the day boundary uses the household zone.

### D-02 — Non-members get a dedicated screen
**Resolves:** auth open item 1.
**Decision:** An authenticated user who resolves to no household sees a dedicated "this Dash Fam isn't yours" screen with a sign-out button. Protected pages do not each have to tolerate a null household.
**Why:** One place to handle the case is less error-prone than every page defending against empty data, where missing one leaves a broken-looking screen. RLS still denies the data regardless; this is purely the UX layer over that denial.
**Change implied (auth flow, section 6):** the "authenticated but unlinked" branch routes to this screen rather than looping back to sign-in.

### D-03 — List items have no assignee in Phase 1
**Resolves:** schema open item 3.
**Decision:** Do not add an assignee to list items in Phase 1. Defer until a real need appears.
**Why:** "Milk" does not need an owner. Adding it now puts extra UI in the single most-used component for a need that may never materialise. Adding a nullable `assigned_member_id` later is a non-breaking migration.
**Change implied:** none now. Recorded so it is a decision, not an omission.

### D-04 — Long session lifetime (~60 to 90 days)
**Resolves:** the refresh-token-lifetime open item in ADR-002 / auth flow section 5.1.
**Decision:** Set the Supabase refresh token to roughly 60 to 90 days, so sessions effectively persist on personal devices. Use 90 days unless the Supabase setting granularity suggests otherwise.
**Why:** Matches the scope's "don't make me sign in weekly" intent. The honest tradeoff, already noted in the auth doc: a lost, unlocked phone retains access until expiry. Mitigation is keeping sign-out easy to reach (D-09 keeps global sign-out out of scope but the per-device control is always present).
**Change implied:** a Supabase Auth config value, set during environment setup.

### D-05 — Display font: Bricolage Grotesque
**Resolves:** style guide open item 1.
**Decision:** Bricolage Grotesque for display and headings, paired with Inter for body. Loaded via `next/font` (self-hosted, no external request).
**Why:** Leans into the bold-and-playful direction as a characterful sans, and pairs cleanly with Inter. Swappable in seconds if it ever grates.
**Change implied (style guide section 4):** the display-font choice is now Bricolage Grotesque, not an either/or with Fraunces.

### D-06 — Member colour: constrained picker (these five only)
**Resolves:** style guide open item 3.
**Decision:** People may change their member colour, but only by choosing among the five accessibility-verified colours (coral, amber, emerald, azure, violet). No arbitrary colour wheel.
**Why:** Gives a little personalisation without breaking a single contrast guarantee from the style guide. A free wheel would let someone pick a colour that fails legibility in one theme.
**Change implied:** the picker offers exactly the five style-guide colours. Two members cannot hold the same colour at once, so the picker must show which are taken. `members.colour` still stores the hex; the picker just constrains input to the five.

### D-07 — Include a manual light/dark toggle
**Resolves:** style guide open item 2.
**Decision:** Ship a manual light/dark override in v1, defaulting to the system setting but letting a person force one theme.
**Why:** Small amount of persisted state, and a common expectation. Chosen over system-only despite the slight extra work.
**Change implied:** the theme is `system | light | dark`, persisted per person. Note it cannot live only in `localStorage` if it must survive across devices; simplest v1 is a preference on the member row, read server-side so there is no theme flash on load. Store as `members.theme_preference text not null default 'system' check (theme_preference in ('system','light','dark'))`.

### D-08 — Testing: pragmatic (RLS + critical paths)
**Resolves:** the scope "test strategy scope" open item.
**Decision:** Automated tests for the RLS policies and a small set of critical flows (sign-in resolves to a household, add item, tick item, the non-member sees nothing). No pursuit of broad coverage.
**Why:** RLS is the security backbone and its failures are silent, so it is the one thing that must be verified rather than eyeballed. Beyond that, a household app does not justify exhaustive testing against the September target.
**Change implied:** a test setup task in the environment/build plan, scoped to the above. RLS tests should include the negative case: a user from no household, and (later) a user from another household, seeing zero rows.

---

## Decisions made on recommendation (no fork worth surfacing)

### D-09 — Rename `position` to `sort_position`
**Resolves:** schema open item 2.
**Decision:** Use `sort_position` for the list-item ordering column instead of `position`.
**Why:** `position` needs quoting in some SQL contexts and invites subtle bugs. Free to change now, annoying after data exists.
**Change implied (schema 3.4):** the column and its index use `sort_position`. The float-gap reordering behaviour is unchanged.

### D-10 — `invited_email` is write-once seed data
**Resolves:** auth open item 2.
**Decision:** Do not keep `invited_email` in sync if an adult later changes their auth email. The link persists via `user_id`, so nothing breaks; `invited_email` is only used to make the first match at signup.
**Why:** Keeping it synced solves nothing real and adds a moving part. Treat it as write-once.

### D-11 — No "sign out everywhere" in v1
**Resolves:** auth open item 3.
**Decision:** Ship the normal per-device sign-out only. Global sign-out (which Supabase supports) is not in v1.
**Why:** Two adults on their own devices. The lost-phone scenario is real but rare, and Supabase's global sign-out can be reached from its dashboard in a pinch. Not worth building UI for in v1. Noted here so it is a known, deliberate gap.

### D-12 — Confirm magic-link rate limiting is enabled
**Resolves:** auth open item 4.
**Decision:** Not a design decision, a setup checklist item. Confirm Supabase's built-in email/OTP rate limits are on, since the sign-in screen sends to any address typed.
**Change implied:** a verification step during environment setup.

### D-13 — Defer empty-state illustration style
**Resolves:** style guide open item 4.
**Decision:** Empty-state illustration style is deferred until the app shell exists. The `EmptyState` component ships with simple text and the `accent` colour first; character can be added later without structural change.
**Why:** Cannot sensibly design illustrations before seeing the real screens, and none of it blocks Phase 1.

---

## Net schema changes from this log

For convenience, everything above that touches the Phase 1 schema, collected:

```sql
-- D-01: household timezone
alter table public.households
  add column timezone text not null default 'Africa/Johannesburg';

-- D-07: per-member theme preference
alter table public.members
  add column theme_preference text not null default 'system'
    check (theme_preference in ('system','light','dark'));

-- D-09: rename ordering column (apply in the list_items definition itself,
-- since no data exists yet; shown here as the intent)
-- list_items.position  ->  list_items.sort_position
```

`invited_email` (auth doc 3.1) and the members/accounts columns are unchanged by this log.

---

## What is now fully closed

All "Open items" sections in docs 00 (scope), 01 (schema), 02 (auth) and 03 (style guide) are resolved by the decisions above or by the seven ADRs. There are no open design questions remaining before build.

The only things left before writing Phase 1 code are execution setup, not decisions:

1. Information architecture and navigation sketch
2. Environment and deployment setup (Supabase project, SSR client structure, Vercel, env vars, migration workflow, and the D-04 / D-12 config)
3. Phase 1 feature and task breakdown
