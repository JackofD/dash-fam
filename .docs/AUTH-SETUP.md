# Making magic links actually work

The code is done. Sign-in still fails until the hosted project is configured,
because Supabase's defaults are wrong for a server-rendered app in one specific
way (see #1). None of this lives in the repo.

Project: `Dash-Fam-dev` — `https://xdrvbhhvtzlavebxixzf.supabase.co`
Dashboard: <https://supabase.com/dashboard/project/xdrvbhhvtzlavebxixzf>

## Can I sign in right now?

**Yes, once you do steps 1 and 2** — you don't need SMTP for your own testing.
The built-in mailer refuses to deliver to anyone who isn't a member of the
Supabase organisation, and `deshen.padayachee@rokkit200.co` is the account
owner, so it will send to you. It is capped at **2 emails per hour**, so don't
burn attempts.

Your second adult will not receive anything until step 4.

---

## 1. Fix the email templates — this is the actual blocker

**Auth → Emails → Templates**

The default templates use `{{ .ConfirmationURL }}`. That points at
`/auth/v1/verify` on Supabase, which verifies the token and then redirects back
with the session in the **URL fragment** (`#access_token=…`). A fragment never
reaches the server, so [app/auth/confirm/route.ts](../app/auth/confirm/route.ts)
sees no `token_hash` and sends you to `/sign-in?error=link`. It looks like the
link is broken. It isn't — the default template is simply built for a
client-side app.

Edit **both** "Confirm signup" and "Magic Link". `signInWithOtp` sends *Confirm
signup* the very first time an address is used (because `shouldCreateUser` is
`true` and the auth user doesn't exist yet) and *Magic Link* every time after.
Making them identical means you don't have to care which one fired.

Paste this as the body of each:

```html
<h2>Sign in to Dash Fam</h2>

<p><a href="{{ .RedirectTo }}?token_hash={{ .TokenHash }}&type=email">Sign in</a></p>

<p>Or enter this code: <strong>{{ .Token }}</strong></p>

<p>This expires in an hour. If you didn't ask for it, ignore it.</p>
```

Three things about that snippet:

- `{{ .RedirectTo }}` is the `emailRedirectTo` the app passed — already
  `<origin>/auth/confirm`. Using it instead of `{{ .SiteURL }}` means **one
  template works for localhost, Vercel previews and production**, which is
  worth the extra step 3. If the value isn't in the allow-list it silently
  falls back to Site URL, which is the failure step 3 prevents.
- `type=email` is correct for both templates. `verifyOtp({ type: 'email' })`
  accepts a signup hash and a magiclink hash alike.
- `{{ .Token }}` is what powers the "enter the code" fallback. Leave it out and
  that half of the sign-in screen has nothing to accept.

## 2. Allow the redirect URLs

**Auth → URL Configuration**

| Field | Value |
|---|---|
| Site URL | your production origin (Vercel domain) — the fallback when `RedirectTo` isn't allowed |
| Redirect URLs | `http://localhost:3000/**` |
| Redirect URLs | `https://*.vercel.app/**` (or narrower: `https://dash-fam-*.vercel.app/**`) |
| Redirect URLs | `https://<production-domain>/**` |

Without the localhost entry, local sign-in bounces to production instead.

## 3. Sanity-check the rest of the auth settings

**Auth → Sign In / Providers**

- **Email** provider enabled.
- **Confirm email** on. This is what makes the link mean anything.
- **Allow new users to sign up** — leave **enabled**. Disabling it breaks
  linking for any member who hasn't signed in yet: linking happens in the
  `on_auth_user_created` trigger, which only fires when the auth user is
  created. Strangers who sign up land on `/no-household` and RLS denies them
  every row, which is the designed behaviour, not a leak.
- **Email OTP expiry**: 3600s (1 hour) is fine. Never go above a day.

**Auth → Sessions**

- Refresh token rotation **on**.
- Time-box / refresh token lifetime ≈ **90 days**, so nobody in the house
  re-authenticates weekly.

**Auth → Rate Limits**

- Leave the email send limit **on**. Given `shouldCreateUser: true`, this is
  the actual defence against someone spamming sign-ins, not the flag.

## 4. Custom SMTP — needed before the second adult can sign in

**Auth → Emails → SMTP Settings**

The built-in mailer will not deliver to `adult.two@…` at all (not a member of
the Supabase org) and is 2/hour with no delivery SLA. Any provider works;
Resend is the least friction. You need host, port, username, password and a
from-address. Custom SMTP starts at 30 messages/hour, adjustable on the Rate
Limits page.

## 5. Replace the placeholder second-adult email

Member `…0102` is still `adult.two@example.com`. Linking matches the address
**exactly**, and `invited_email` is write-once, so a typo fails silently: they
sign in fine and land on `/no-household` wondering why.

```sql
update public.members
   set invited_email = lower('their.real@address'), updated_at = now()
 where id = '00000000-0000-0000-0000-000000000102';
```

Do it **before** they first try. Mirror the change into
[supabase/seed.sql](../supabase/seed.sql) so the repo doesn't disagree with the
database.

## 6. Vercel environment variables

Per environment (preview and production both point at this project for now):

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` — **note the name.** It used to be
  `…_ANON_KEY` locally, which is why nothing worked; an anon key *value* is
  fine in it.
- `NEXT_PUBLIC_SITE_URL` — optional, metadata only.

---

## Then test

`npm run dev`, and:

1. `/` redirects to `/sign-in`.
2. Enter your address → "check your email".
3. The email has **both** a link and a 6-digit code. If it has neither, step 1
   didn't save.
4. Click the link → you land on `/` and it greets you by name.
5. Sign out. Sign in again, this time typing the **code**. Same result.
   (Watch the 2/hour cap — this is email number two.)
6. Enter an address that is not a member → identical "check your email", then
   its link lands on `/no-household` with a sign-out button and no nav.

## When it doesn't work

| Symptom | Cause |
|---|---|
| `/sign-in?error=link` right after clicking | Template still uses `{{ .ConfirmationURL }}` (step 1) |
| Link opens production while testing locally | `http://localhost:3000/**` missing from Redirect URLs (step 2) |
| No email, no error on screen | Rate limit hit (2/hour), or address isn't an org member. The screen says "check your email" for *every* address by design, so it cannot tell you this — check **Auth → Logs** |
| Email arrives with no code | `{{ .Token }}` missing from the template |
| Signed in but sent to `/no-household` | The address doesn't match any `invited_email`. Compare exactly — it is lowercased on both sides |

**Auth → Logs** in the dashboard is the only place that will tell you the truth
about a send that didn't happen. The sign-in screen deliberately won't, because
distinguishing "not a member" from "sent" would let anyone enumerate the
household.
