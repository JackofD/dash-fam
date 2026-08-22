# F-08 — Authentication & household access

Branch `feature/f-08-auth-household-access`.

## Why

The schema for members-vs-accounts landed in F-02 and is live on the hosted
project, but no application code consumed it. Everything under `app/` and
`components/` was still the vanilla Next.js + Supabase starter, which ships
**password auth** — contradicting the decision of magic link only
([PROJECT.MD](../.docs/PROJECT.MD) §5.3).

This feature builds the app-side half: passwordless sign-in, a cookie session
RLS can read, the route guard, and the screen for an authenticated account that
matches no member.

## Scope

In: `/sign-in`, `/auth/confirm`, `/no-household`, the `(app)` route group and
its gate, sign-out, removal of all template auth and chrome.

Out, and deliberately so: passwords, OAuth, global sign-out across devices,
the member-invite flow, giving kids accounts, navigation chrome, anything
touching `lists`. **The data-access pattern stays undecided** — this feature
adds only the auth helpers it needs and sets no house style for reads or
writes.

## Decisions

**D-F08-1 — Magic link, with a 6-digit code fallback.** One `signInWithOtp`
call backs both. The email carries a link to `/auth/confirm` *and* `{{ .Token
}}`. The known weakness of link-only auth is a link opened in a different
browser than it was requested from (mail-app in-app browsers do this); the code
makes that recoverable by typing six digits instead of being a dead end.

**D-F08-2 — `verifyOtp`, not `exchangeCodeForSession`.** The pre-reset ADR-002
specified "PKCE / `exchangeCodeForSession`". That is wrong for email links —
`exchangeCodeForSession` is the OAuth code flow. Supabase's documented SSR
email flow is `{{ .TokenHash }}` in the template, verified with
`verifyOtp({ type: 'email', token_hash })` at a route handler. **ADR-002 should
be corrected if it is ever restored.**

**D-F08-3 — `shouldCreateUser: true`.** Linking runs in the
`on_auth_user_created` trigger, which only fires on insert into `auth.users`.
With `false`, a seeded member who has never signed in could never sign in at
all — the account they need to be linked to would never exist. The cost is that
any stranger can create an auth user, which is precisely the null-household
case the schema already anticipates: they get no household and RLS denies every
row. Abuse is bounded by Supabase's auth rate limits, not by this flag.

**D-F08-4 — Two gates, split by cost.**

| | Where | Checks | Reads DB |
|---|---|---|---|
| 1 | `proxy.ts` → `lib/supabase/proxy.ts` | is there a session | no |
| 2 | `app/(app)/layout.tsx` | does the session map to a member | yes |

Membership is *not* checked in the proxy: it needs a query, the proxy runs on
every request, and being unlinked is a permanent state rather than a
per-request one. `/no-household` sits outside the `(app)` group so the redirect
cannot loop.

Gate 2 is routing, not security. An account that bypasses it still reads zero
rows: `current_household_id()` returns null and every policy compares against
it. Verified against the live database — see below.

**D-F08-5 — Never disclose membership.** `/sign-in` answers "check your email"
for every address, including ones matching no member and ones where the send
errored. Anything else lets a caller enumerate the household.

**D-F08-6 — No shadcn `alert` / `input-otp`.** The registry has moved to
Tailwind v4 (`has-[>svg]:`, `var(--spacing)`, `shadow-xs`, `has-disabled:`)
while this project is on Tailwind 3.4.1, so generated components render subtly
wrong. A plain numeric `Input` covers the code field. **Any future
`shadcn add` needs the same check.**

**D-F08-7 — No migration.** The trigger, `current_household_id()` and the
`members_select` policy already cover everything the app reads. Confirmed live:
the trigger exists and is enabled, and `current_household_id()` is
`security definer` so `members_select` resolves through it without recursing.

## Files

```
lib/supabase/env.ts            new    throwing env guard, replaces hasEnvVars
lib/supabase/{client,server,proxy}.ts  typed with Database, use env.ts
lib/auth/current-member.ts     new    getCurrentMember (cached) / requireMember
lib/auth/actions.ts            new    signOut server action
app/sign-in/page.tsx           new
components/auth/sign-in-form.tsx      new    both sign-in paths
components/auth/sign-out-button.tsx   new
app/auth/confirm/route.ts      rewritten in place
app/no-household/page.tsx      new
app/(app)/layout.tsx           new    gate 2
app/(app)/page.tsx             new    home placeholder (was app/page.tsx)
```

Deleted: the six password-auth pages and their five forms, `auth-button`,
`logout-button`, `/protected`, `hero`, `deploy-button`, `supabase-logo`,
`next-logo`, `env-var-warning`, `components/tutorial/*`, and the
Supabase-branded OG/Twitter images.

## Defects fixed in passing

1. **The proxy was dead.** `.env.local` defined
   `NEXT_PUBLIC_SUPABASE_ANON_KEY`; every file read
   `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. `hasEnvVars` was therefore false,
   the proxy early-returned, and every client was constructed with an
   `undefined` key. Auth could not have worked. Standardised on the
   publishable name; `env.ts` now throws rather than failing open.
2. **Open redirect in `/auth/confirm`.** `next` was redirected to unvalidated,
   in a URL that arrives by email where an attacker controls the query string.
3. **`error.message` reflected into a URL** and rendered on `/auth/error`.
   Coarse codes only now.
4. **`tailwind.config.ts` used `require()`**, which fails `eslint .` and would
   have turned CI red on the first PR.
5. **`eslint .` linted nested `.next` inside git worktrees**, burying real
   findings under ~3200 generated-file errors.
6. **`VERCEL_URL` read in `app/layout.tsx`** — replaced with
   `NEXT_PUBLIC_SITE_URL`, per the hosting-portability rule.

## Next.js 16 notes

- Middleware is root `proxy.ts`. `middleware.ts` would silently do nothing.
- `cacheComponents: true` means `export const dynamic` **errors**. The escape
  hatch is `export const instant = false`, used on `app/(app)/layout.tsx` and
  `app/no-household/page.tsx`.
- `instant = false` does **not** defer synchronous IO. `new Date()` in the home
  placeholder still fails the prerender, so it sits behind `connection()`
  inside a `<Suspense>` boundary.
- `/sign-in` reads `searchParams` inside a `<Suspense>` boundary, which keeps
  it partially prerendered (`◐`) rather than fully dynamic.
- Deleting a route leaves stale generated types in `.next`; `tsc --noEmit`
  fails until `.next` and `tsconfig.tsbuildinfo` are removed.

## Verified

`npm run lint`, `npx tsc --noEmit`, `npm run build` green. Route map builds as
`ƒ /`, `ƒ /auth/confirm`, `ƒ /no-household`, `◐ /sign-in`.

Both gate-2 cases asserted against the hosted database, each inside a
transaction that was rolled back, with `set local role authenticated` so the
assertions could not pass vacuously through the `postgres` role's RLS
exemption:

| case | `current_household_id()` | members | lists |
|---|---|---|---|
| stranger (no matching member) | null | 0 | 0 |
| linked adult | the household | 5 | — |

Also confirmed the `on_auth_user_created` trigger is present and enabled, and
that the rollback left `auth.users` empty.

## Still to do by hand

These are not code and the app is not usable without the first three.

1. **Custom SMTP.** The built-in mailer allows only a few emails an hour and is
   not for production. Magic-link-only auth means every sign-in is an email, so
   this is a hard blocker, not a nice-to-have.
2. **Email template** (Auth → Email Templates → Magic Link) must contain both
   a link to `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email`
   and the literal `{{ .Token }}`. The default template has neither.
3. **Redirect URLs** (Auth → URL Configuration): production origin as Site URL,
   plus `http://localhost:3000/**` and the Vercel preview wildcard.
4. **Session lifetime** ~90 days with refresh-token rotation, so nobody
   re-authenticates weekly.
5. **Rate limits** on email send — the real defence given D-F08-3.
6. **Leave signups enabled.** Disabling them breaks linking for any member who
   has not signed in yet.
7. **`NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` in Vercel** for every environment,
   plus `NEXT_PUBLIC_SITE_URL`.
8. **Replace the placeholder `invited_email`.** Member
   `…0102` is still `adult.two@example.com`. Linking matches the address
   exactly and `invited_email` is write-once, so a wrong address is a silent
   failure: they sign in fine and land on `/no-household`.

## Deferred, with reasons

- **`on_auth_user_created` only fires on insert.** A member row created after
  its person already signed up never gets linked. That is the invite flow.
- **Advisor warnings on `link_member_on_signup` and
  `list_items_set_household`** — both are `security definer` and exposed on
  `/rest/v1/rpc/`. Probed as `authenticated`: **not exploitable**, Postgres
  refuses with `0A000 trigger functions can only be called as triggers`.
  Revoking `EXECUTE` is still worthwhile defence-in-depth, along with a fixed
  `search_path` on `set_updated_at` (a genuine WARN). Left out because it is a
  forward-only migration against the live database and not needed for auth.
- **`members.theme_preference` vs `next-themes`.** Server-reading the column
  would avoid a flash of the wrong theme. Belongs with the app shell.
