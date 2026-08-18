# ADR-002: Supabase Auth over Clerk, magic link only

**Status:** Accepted
**Date:** 2026-08-13
**Depends on:** ADR-001, 02-auth-flow.md

## Context

The app needs authentication for two adults; three children do not sign in. Sign-in must be low-friction and the security model rests on Supabase RLS, which reads `auth.uid()`. Two questions: which auth provider, and which sign-in method.

## Decision

Use **Supabase Auth**, with **magic link (passwordless email) as the only sign-in method** for v1, over the **PKCE flow**.

### Provider: Supabase Auth over Clerk

The deciding factor is that Supabase RLS policies read `auth.uid()` natively. Clerk would require issuing a Supabase-compatible JWT and wiring that integration correctly; getting it subtly wrong means the security model is wrong and it may not be obvious. Supabase Auth removes that entire integration surface. Clerk's strengths (polished prebuilt UI, user management at scale) solve problems a five-person household does not have, and it adds a second vendor and bill.

### Method: magic link only

No passwords means nothing to store, reset, leak, or choose badly. No OAuth means no provider setup. The one real cost is that signing in on a new device requires email access at that moment, which for two adults on their own phones is a rare, one-off event rather than a daily tax.

### Flow: PKCE

The PKCE flow is more robust against the "link opened in a different browser or client" failure mode than the implicit flow, and it is the recommended default for server-rendered apps. Low cost to adopt, removes a class of confusing failures.

## Consequences

- No password reset flows, no OAuth consent screens, no second auth vendor to operate.
- The sign-in screen sends a link to any email entered, so it must show "check your email" unconditionally and never reveal who is a member (see 02-auth-flow.md section 4). Access is denied at the data layer, not by refusing to send the link.
- Google Calendar sync, were it ever added, would benefit from a held Google grant. It is out of scope, so this costs nothing now; Google could be added as a second provider later without disruption.
- Refresh token lifetime is set long so sessions persist on personal devices (see ADR-007 and 02-auth-flow.md section 5).

## Revisit when

The app becomes multi-tenant with organisation invites and billing, or sign-in needs outgrow what magic link handles comfortably (for example, if children need their own logins with a different flow).
