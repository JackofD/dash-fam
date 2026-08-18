# ADR-005: Server Actions + a thin query layer for data access

**Status:** Accepted
**Date:** 2026-08-13
**Depends on:** ADR-001, ADR-007

## Context

The app reads and writes household data through Supabase. The App Router (ADR-001) supports fetching in server components and mutating via Server Actions. The question is how much structure to impose: calling the Supabase client directly everywhere is fastest to type but scatters logic; a heavy abstraction is premature for an MVP. A pattern was needed before Phase 1 code so data access is consistent from the first feature.

## Decision

**Reads go through a thin query layer of typed data-access functions. Writes go through Next.js Server Actions.**

- The query layer starts as a handful of functions (list the household's lists, get a list's items) in one place, returning typed results. It grows only as features need it. It is not an ORM or a repository framework; it is a folder of functions.
- Mutations (add item, tick item, create list) are Server Actions. They run on the server, hold the user's session via the SSR cookie (ADR-007), and are the single, discoverable home for every write.

## Consequences

- Every write lives in one layer rather than being scattered across client components, which is the pattern most regretted later. This is the main reason to reach past "Supabase client directly" even for an MVP.
- Server Actions are native to the App Router, so this is the framework's grain, not extra ceremony imposed on top of it.
- RLS remains the enforcement layer regardless. The query layer and Server Actions are for structure and maintainability, not security; a bug there cannot leak cross-household data because the database denies it (schema doc section 5).
- Realtime updates (lists syncing between phones) are a client-side subscription and sit alongside this, not inside it: the server writes, the client subscribes and reconciles (schema doc section 6).
- Optimistic UI updates on the client pair naturally with Server Action writes and must reconcile with incoming realtime events by id to avoid double-applying.

## Alternatives considered

- **Supabase client called directly everywhere.** Least code up front, but mutations spread through the UI and become hard to change or reason about. Rejected for the cost it defers onto later.
- **A full query layer with mutations also as typed functions called from the client, no Server Actions.** More boilerplate and it swims against the App Router's grain, without a corresponding benefit. Rejected.

## Revisit when

The query layer stops being thin, meaning duplicated query logic or ad hoc caching appears. That is the signal to consider a more formal data layer, not before.
