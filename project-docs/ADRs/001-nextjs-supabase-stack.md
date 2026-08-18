# ADR-001: Next.js + Supabase as the stack

**Status:** Accepted
**Date:** 2026-08-13
**Depends on:** 00-project-scope.md

## Context

Dash Fam is a private household web app, phone-first with a desktop planning surface, targeting Phase 1 in daily use by early September 2026. It needs a database, authentication, real-time sync for shared lists, and a way to build a responsive UI. It is built by one person in evenings. The overriding constraint is time-to-usable, not scale: the user ceiling is five people in one house.

## Decision

Build on **Next.js (App Router) with TypeScript in strict mode**, backed by **Supabase** for Postgres, Auth, Realtime and storage.

- Next.js because it gives server and client components in one framework, first-class hosting, and the largest body of documentation for this exact combination.
- Supabase because it collapses database, auth, and realtime into one service with a single bill and a single mental model, and because its Row Level Security is the security backbone the schema and auth docs are built around.
- TypeScript strict because a solo, intermittently-worked project cannot afford the class of runtime bugs a loose type setup permits.

## Consequences

- One vendor for data, auth and realtime means one dashboard, one set of credentials, one thing to learn. It also means concentration risk: a Supabase outage is a total outage. Acceptable for a household app.
- RLS becomes the primary security mechanism, not application code. This is a deliberate posture set out in the schema and auth docs; every table is default-deny.
- Server components allow data fetching on the server, which the SSR session decision (ADR-007) depends on.
- The realtime requirement (lists syncing between phones) is met natively rather than bolted on.

## Alternatives considered

- **Next.js + custom Postgres + own auth.** More control, materially more work, and hand-rolled auth is exactly where a solo project introduces security bugs. Rejected on time and risk.
- **A separate backend (.NET, Node, Go) + SPA.** Two deployables, two codebases, a hand-built API layer. Wrong shape for the size of the problem. Rejected.

## Revisit when

The app outgrows a single household and needs capabilities Supabase does not serve well, or vendor concentration becomes an operational problem. Neither is foreseeable at five users.
