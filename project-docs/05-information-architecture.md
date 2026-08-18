# Dash Fam: Information Architecture & Navigation

**Status:** Draft v0.1
**Last updated:** 2026-08-13
**Covers:** route map, navigation model (phone and desktop), screen inventory, the add pattern, states
**Depends on:** 00-project-scope.md, 02-auth-flow.md, 03-style-guide.md, 04-decisions-log.md

---

## 1. Shape of the app

Dash Fam has one authenticated area and a thin public edge for signing in. Inside, it is a small number of top-level destinations that grow phase by phase. Nothing is nested more than two levels deep, because a household app used in seconds cannot afford people getting lost.

The whole thing:

```
Public
  /sign-in                 email entry, "check your email"
  /auth/callback           magic-link exchange, then redirect inward

Authenticated (requires session)
  /                        Home (dashboard)
  /lists                   all lists
  /lists/[listId]          one list, its items        [Phase 1]
  /chores                  chores                       [Phase 2]
  /calendar                events                       [Phase 3]
  /meals                   meal plan                    [Phase 4]
  /settings                people, theme, sign out

No-access
  /no-household            authenticated but not a member (D-02)
```

Phase 1 ships `/`, `/lists`, `/lists/[listId]`, `/settings`, plus the public and no-access routes. The later destinations are drawn here so the navigation model is designed once for its final shape, not retrofitted each phase.

---

## 2. Navigation model

Phone-first and desktop, per the scope. Same destinations, two presentations.

### Phone: bottom tab bar

A fixed bottom bar is the right pattern for a one-thumb, in-the-kitchen app: reachable without shifting grip, always visible, no hunting in a hamburger menu.

- Tabs, left to right: **Home, Lists, Chores, Calendar, Meals.**
- Phase 1 shows only **Home** and **Lists.** Tabs appear as their phases land, rather than showing disabled "coming soon" tabs, which just advertise absence.
- Five is the maximum for a bottom bar before labels get cramped; the final set is exactly five, which is a happy coincidence and a constraint to respect (do not add a sixth top-level tab).
- Settings is not a tab. It is reached from an avatar or icon in the top bar, because it is used rarely.

### Desktop: side rail

- A left side rail with the same destinations, labelled, plus Settings pinned at the bottom.
- The rail can be a slim icons-plus-label column; it does not collapse in v1 (one less bit of state).
- Content area is width-constrained for reading (the week grids in Phase 3 are the only truly wide layouts).

### Top bar (both)

Thin, contextual: the current screen title, and on the right the user's `MemberAvatar` opening a small menu (Settings, sign out). On desktop the title can be omitted since the rail shows location.

**Soft choice A:** Home as a distinct tab versus making Lists the landing screen. Recommendation: keep Home as its own destination and the default landing. It is what makes this a *dashboard* rather than a list app, and it is where the later phases surface their one-glance summaries. If Phase 1's Home feels too thin to justify a tab, the fallback is to land on Lists and fold the dashboard in later, but designing Home in from the start avoids reshuffling navigation mid-project.

---

## 3. Screen inventory (Phase 1)

### 3.1 Home `/`

The one-glance answer to "what matters right now". In Phase 1 it is deliberately light, and it grows as later phases add widgets.

- Greeting and today's date (rendered in the household timezone, D-01).
- **Grocery snapshot:** the grocery list with a count and the first few outstanding items, tapping through to the full list.
- Placeholder space where Chores-today, Today's-events and Tonight's-dinner widgets will slot in later.

Composed of `DashboardWidget` cards (style guide 7), which is also what keeps a future wall display a rearrangement rather than a rebuild.

If Home would otherwise look empty in Phase 1, that is a signal to ship it minimal rather than pad it. An honest thin dashboard beats a fake-busy one.

### 3.2 Lists `/lists`

- All non-archived lists for the household, the grocery list surfaced first (it is `kind = 'grocery'`).
- Each row: name, an outstanding-item count, tap to open.
- Create a new list from here (a `+` that opens a Sheet on phone, a dialog on desktop).
- Archived lists are not shown here; a low-priority "archived" view can come later. Archiving is reached from within a list.

### 3.3 List detail `/lists/[listId]`

The most-used screen in the app. Everything else is secondary to this working well.

- Header: list name, overflow menu (rename, archive, clear completed).
- **QuickAdd** pinned where a thumb rests (bottom on phone, top of the list on desktop): a single field, type and submit, focus stays so several items go in fast. This is the make-or-break control (style guide 7.1).
- Item rows: tick (large tap target, 44px+), content, and swipe-or-menu to delete. Completed items drop to a dimmed, struck-through section.
- Live updates: two phones on the same list stay in sync (schema 6). Local optimistic add, reconciled by id.
- Empty state: friendly prompt to add the first item, not a blank screen.

### 3.4 Settings `/settings`

- **People:** the five members, each with avatar, name, and their colour. Editing name and colour (colour via the constrained five-way picker, D-06, showing which are taken). This is also where the two adult accounts are visibly linked.
- **Appearance:** theme preference, system / light / dark (D-07), persisted to the member row.
- **Account:** sign out (per-device; no global sign-out in v1, D-11).

### 3.5 No-household `/no-household`

Authenticated but not a member (D-02). A plain, kind screen: this Dash Fam belongs to a household and your account is not part of it, with a sign-out button. No navigation chrome, no tabs.

### 3.6 Sign-in `/sign-in` and callback `/auth/callback`

- `/sign-in`: email field, submit, then the unconditional "check your email" state (never reveals membership, auth doc 4). Handles the expired-link return with a plain "get a new link" message.
- `/auth/callback`: exchanges the token, sets the cookie, redirects to Home (or to `/no-household` if unlinked). Shows a brief loading state; on failure sends back to `/sign-in`.

---

## 4. The add pattern, stated once

Adding things is the core interaction, so it is defined once and reused:

- **List items:** inline QuickAdd, no dialog. Speed matters most here.
- **A new list, editing a member:** a **Sheet** on phone (slides up, thumb-friendly), a **Dialog** on desktop. Same component, responsive presentation (style guide 7).
- Later phases (a chore, an event, a meal) follow the Sheet/Dialog pattern, never a separate full page, so the mental model stays constant.

---

## 5. States every screen must handle

Defined centrally so no screen invents its own (scope cross-cutting item):

- **Loading:** `Skeleton` placeholders, never a spinner on a blank page.
- **Empty:** `EmptyState` with a prompt toward the first useful action.
- **Error:** a toast (`Sonner`) for transient failures; a plain inline message for a screen that cannot load. Never a raw error.
- **Offline / reconnect:** at minimum, don't lose what someone typed. Full offline support is out of scope for v1, but the app should fail softly, not throw.

---

## 6. Deferred, deliberately

- Search across lists and items. Not needed at household scale in v1.
- Archived-lists view. Archiving works; browsing archives can wait.
- A dedicated wall-display / kiosk route. Home is built widget-first so this stays a later rearrangement (scope 3, style guide 7).
- Per-person notification settings. There are no notifications in v1.

---

## 7. Open items

1. **Soft choice A (section 2):** confirm Home is its own landing tab versus landing on Lists. Recommendation is Home; flagged for a quick yes.
2. **Settings depth.** Whether "People" editing lives in one screen or splits into a per-person subview. Recommendation: one screen for five people; revisit only if it gets busy.
3. **Home widget order.** The order widgets appear once later phases add them (chores vs events vs meals first). Decide when the second widget exists, not now.
