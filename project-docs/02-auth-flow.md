# Dash Fam: Auth Flow

**Status:** Draft v0.1
**Last updated:** 2026-08-13
**Covers:** magic link sign-in, session handling, member linking, access control, protected routes
**Depends on:** 00-project-scope.md, 01-schema-foundation-lists.md

---

## 1. What this document decides

How a person goes from a cold browser to an authenticated session that resolves to a household member, and what happens to everyone who should not get in. Three decisions from earlier documents constrain it:

- Magic link only, no passwords, no OAuth (scope 5.3).
- A member is a person; an account is a login; the two are linked by `members.user_id` (scope 2, schema 3.2).
- Access is strict: only people who are already household members get in (this document, section 4).

The linking mechanism is an email allowlist with automatic linking on first sign-in. The rest of this document builds on that choice.

---

## 2. The core problem, stated plainly

Supabase Auth creates a row in `auth.users` when someone signs in. Dash Fam's data is keyed to `members`, not to `auth.users`. Nothing works until an authenticated user resolves to a member row, because `current_household_id()` reads `members.user_id` and returns null for any user with no matching member.

So the whole of auth comes down to one question: **when a new `auth.users` row appears, which member row does it belong to, if any?**

The answer: the member whose pre-seeded email matches the new user's email. If none matches, the user is a stranger and gets nothing.

---

## 3. Linking: email allowlist with auto-link

### 3.1 Seed the adults with their emails

The schema doc seeds five members with `user_id` null. For the two adults, also seed the email they will sign in with. Add a column to hold it:

```sql
alter table public.members
  add column invited_email text unique
    check (invited_email is null or invited_email = lower(invited_email));
```

`invited_email` is the email a member is expected to sign in with, before any account exists. It is separate from the real email, which lives in `auth.users` once linked. Lowercased by constraint because email matching that is not case-insensitive will fail in practice the first time someone types a capital letter. The unique constraint stops two members claiming the same address.

The three kids leave `invited_email` null. They are never expected to sign in during v1.

### 3.2 Link on first sign-in with a trigger

When Supabase inserts into `auth.users`, a trigger matches the new user's email against `invited_email` and links the member:

```sql
create or replace function public.link_member_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  matched_member_id uuid;
begin
  update public.members
     set user_id = new.id,
         updated_at = now()
   where invited_email = lower(new.email)
     and user_id is null
  returning id into matched_member_id;

  -- No matching allowlisted member: leave the auth user unlinked.
  -- They will resolve to no household and see nothing (section 4).
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.link_member_on_signup();
```

Why this shape:

- **`security definer`** because the trigger runs in the context of the auth system inserting the row, and it must write to `public.members`, which RLS otherwise guards. Same `search_path` safety rule as every other definer function in this project.
- **`and user_id is null`** so a member already linked is never silently repointed. If someone changes their email in the auth system and signs in fresh, they do not hijack an existing member.
- **No exception on no match.** A stranger signing in is not an error; it is a person who gets no access. Raising here would leave a half-created auth user and a confusing failure. Letting it through and denying at the data layer is cleaner and is handled in section 4.

### 3.3 Why this over manual SQL

Manual linking (run an `UPDATE` after each adult first signs in) is fewer lines but has a live gap: between first sign-in and your manual update, the adult is authenticated but resolves to no member, so they see an empty app. It also needs you present at the database at sign-up time. The trigger removes both problems and becomes the foundation the Phase 5 invite flow extends, so it is not throwaway work. The cost is roughly fifteen lines and one column.

---

## 4. Access control: strict, only known members

There is no public surface in Dash Fam. Access has two gates, and both must hold.

**Gate one, authentication.** No valid session, no entry. Handled by route protection (section 6).

**Gate two, membership.** A valid session whose user has no linked member resolves to `current_household_id() = null`. Every RLS policy compares against that and every comparison fails, so the user can read and write nothing. This is the enforcement layer, and it is enforced by the database, not by the UI.

The important property: gate two is not a UI check that a determined user could bypass. Even hitting the Supabase API directly with a valid token for a non-member email returns zero rows on every table. The UI's job is only to turn that empty result into a clear message rather than a broken-looking blank screen.

### The stranger's experience

Anyone can request a magic link for any email, because Supabase will send one to any address. That is fine and not a hole: receiving the link only creates an authenticated-but-unlinked session, which sees nothing. The app detects "signed in but no member" and shows a plain screen: this Dash Fam belongs to a household and your account is not part of it. No data, no navigation, a sign-out button.

Optional hardening, noted not required for v1: Supabase can be configured to only send magic links to pre-existing users, or an allowlist can gate the send. For a five-person private app whose URL is not published, the data-layer denial is sufficient and the extra configuration is deferred.

---

## 5. Session handling

### 5.1 Long-lived sessions

The scope doc calls for sessions long enough that nobody re-authenticates weekly. Supabase issues a short-lived access token (JWT, one hour by default) and a long-lived refresh token. The client library refreshes the access token automatically using the refresh token, so "how long until I must sign in again" is governed by refresh token lifetime and inactivity settings, not the one-hour access token.

Set the refresh token to a long expiry (the scope's intent is effectively "stay signed in on my own phone indefinitely"). The tradeoff is honest: a longer-lived refresh token on a lost, unlocked phone is longer-lived access for whoever holds it. For a household app on personal devices this is the right trade, but it is a trade, and the mitigation is the sign-out control being easy to reach.

### 5.2 Where the session lives

This is the decision that most affects how the Next.js app is built, so it is called out rather than assumed.

Supabase sessions in a Next.js App Router app should be stored in cookies, not `localStorage`. The reason is server components: a server component renders on the server and has no access to browser storage, so if the session lives only in `localStorage` the server cannot know who the user is and every data fetch has to happen client-side. Cookie-based sessions are readable in server components, middleware, and route handlers, which is what makes server-side data fetching and route protection possible.

This means the app uses the Supabase SSR pattern: separate client factories for browser, server component, and middleware contexts, all reading and writing the same cookie. This is a known, documented setup, but it must be decided before the first line of app code because retrofitting it is painful. Flagged as a required ADR (see section 8).

### 5.3 Token contents and RLS

The access token is a JWT carrying `auth.uid()`, which is exactly what `current_household_id()` reads. No custom claims are needed in v1. Specifically, do not put `household_id` into a custom JWT claim as an optimisation: it would go stale if membership changed, and the function lookup is cheap and always correct. Revisit only if profiling ever shows the lookup is a real cost, which at this scale it will not be.

---

## 6. Protected routes

Two layers, because each catches what the other cannot.

**Middleware** runs before a page renders and is the right place to bounce an unauthenticated request to the sign-in screen. It also refreshes the session cookie on each request so the token stays fresh. It should be fast and coarse: is there a session or not, redirect accordingly. It must not try to do per-row authorisation.

**Server-side data access** is the real guard. Middleware protects routes; RLS protects data. A page that renders for an authenticated-but-unlinked user still returns no data because of RLS, and the page handles that empty state. Never rely on middleware alone for anything security-relevant, because a missed route matcher becomes an open door, whereas RLS is default-deny across every table at once.

Route shape:

- Public: only the sign-in route and the magic-link callback route.
- Everything else: requires a session, else redirect to sign-in.
- A special case: authenticated but unlinked. This is not a redirect loop back to sign-in (the user is signed in). It is its own "not part of this household" state, or all protected pages must tolerate zero data gracefully. Decide one approach and apply it uniformly.

---

## 7. The magic link flow, end to end

1. Person enters their email on the sign-in screen.
2. App calls Supabase to send a magic link. App shows "check your email" regardless of whether the email is a known member, so the screen never reveals who is or is not in the household.
3. Person clicks the link, which lands on the callback route with a token in the URL.
4. Callback route exchanges the token for a session, sets the session cookie, and redirects into the app.
5. If this is a first-ever sign-in, the `auth.users` insert has already fired the link trigger (section 3.2), so by the time the app loads, the member is linked if the email was allowlisted.
6. App loads. `current_household_id()` resolves. Either the person sees their household's data, or, if unlinked, the "not part of this household" state.

Two failure modes to handle in the UI:

- **Expired or reused link.** Magic links are single-use and time-limited. The callback must catch the exchange failure and send the person back to the sign-in screen with a plain "that link has expired, here's a new one" message, not a stack trace.
- **Link opened in a different browser.** Depending on flow configuration this can fail. The PKCE flow is the more robust choice for this and should be the default; note it in the auth ADR.

---

## 8. Decisions to record as ADRs

1. **Supabase SSR cookie-based sessions** (section 5.2). Required before app code. This dictates the client-factory structure of the entire app.
2. **PKCE magic-link flow** (section 7). Low cost to decide, avoids a class of "link opened elsewhere" failures.
3. **Refresh token lifetime** (section 5.1). A number, plus the security note.

---

## 9. Open items

1. **Unlinked-user UX.** Dedicated "not part of this household" screen versus every page tolerating empty data. Section 6 needs one chosen. The dedicated screen is cleaner; decide before building the app shell.
2. **Email change.** If an adult changes the email on their auth account, the link persists via `user_id`, so nothing breaks. But `invited_email` then no longer matches their real email, which is only a cosmetic staleness. Decide whether to bother keeping `invited_email` in sync or treat it as write-once seed data. Leaning write-once.
3. **Sign-out everywhere.** Whether a lost-phone scenario needs "sign out all sessions" in v1. Probably not, but note where it would live (Supabase supports global sign-out) so it is not a surprise later.
4. **Rate limiting magic-link sends.** Supabase has built-in limits. Confirm they are enabled so the send endpoint cannot be used to spam an address, since the sign-in screen will send to any email entered.
