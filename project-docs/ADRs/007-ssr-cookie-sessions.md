# ADR-007: Supabase SSR cookie-based sessions

**Status:** Accepted
**Date:** 2026-08-13
**Depends on:** ADR-001, ADR-002, 02-auth-flow.md

## Context

The app uses Supabase Auth (ADR-002) inside the Next.js App Router (ADR-001), which renders on the server via server components and fetches data server-side (ADR-005). The Supabase session can be stored in browser storage or in cookies. This choice dictates the client-factory structure of the entire app and is very costly to change once code exists, so it is recorded before any app code is written.

## Decision

Store the Supabase session in **cookies** using the **Supabase SSR pattern**, not in `localStorage`.

A server component renders on the server and has no access to browser storage. If the session lived only in `localStorage`, the server could not know who the user is, and every data fetch and every route guard would be forced client-side, defeating the point of the App Router. Cookie-stored sessions are readable in server components, middleware, and route handlers, which is what makes server-side data fetching (ADR-005) and route protection (02-auth-flow.md section 6) possible at all.

Concretely this means adopting the Supabase SSR pattern: distinct client factories for the browser context, the server-component context, and the middleware context, all reading and writing the same session cookie.

## Consequences

- Route protection can run in middleware before a page renders, and middleware refreshes the session cookie on each request so the access token stays fresh (02-auth-flow.md section 6).
- Server-side data fetching in server components works because the session is available server-side. Without this decision, ADR-005's reads-in-server-components approach could not function.
- The app carries three client-creation paths instead of one. This is a documented, well-trodden Supabase pattern, but it must be set up correctly at the start; retrofitting it later is painful, which is why this is decided up front.
- Session persistence (how long a user stays signed in) is governed by refresh-token lifetime, set long for personal devices (ADR-002, 02-auth-flow.md section 5). The honest tradeoff: a long-lived session on a lost, unlocked phone is long-lived access for whoever holds it, mitigated by keeping sign-out easy to reach.
- No custom JWT claims in v1. `household_id` is resolved by `current_household_id()` per request rather than embedded in the token, so it can never go stale (02-auth-flow.md section 5.3).

## Alternatives considered

- **`localStorage`-based sessions (the Supabase browser default).** Simpler for a pure client-side SPA, but incompatible with server components and server-side route protection. Rejected as fundamentally at odds with the App Router architecture.

## Revisit when

Not expected to change; it is architectural. Any move away would effectively be re-choosing the rendering model.
