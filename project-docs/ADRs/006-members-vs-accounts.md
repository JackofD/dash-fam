# ADR-006: Members and accounts modelled as separate concepts

**Status:** Accepted
**Date:** 2026-08-13
**Depends on:** 00-project-scope.md, 01-schema-foundation-lists.md, 02-auth-flow.md

## Context

The household has five people: two adults who sign in and three children who do not. All five must be assignable to chores, appear on events, and be referenced throughout the app; only two of them authenticate. A future path exists where any member is invited to claim a full account, keeping their existing history. The data model has to serve both facts without a painful migration later.

## Decision

Model a **member** (a person) and an **account** (a login) as separate concepts, linked by a nullable `members.user_id`.

- Every person is a `members` row. All three children are members with `user_id` null.
- An account is an `auth.users` row. It links to at most one member via `members.user_id` (unique, nullable).
- **All domain foreign keys reference `member_id`, never an auth user id.** Chores, events, list items, everything that names a person points at a member.

## Consequences

- Account-less people are first-class data. They can be assigned things and referenced everywhere; they simply cannot log in.
- The future invite flow becomes a controlled linking of an existing member row to a new auth user. Because no domain data references auth users directly, all of an invited member's history stays attached automatically. This is the entire reason the separation exists.
- RLS resolves an auth user to their member row, then to their household (`current_household_id()`), so an account-less member has no direct bearing on policy evaluation (schema doc 4.1).
- Two rules must never be broken, or the model's guarantees fail:
  1. Never write a query, policy, or foreign key that assumes `member_id` implies an auth user exists.
  2. Linking a member to an auth user is what grants access, so it is never a client-side write. It happens via the signup trigger (02-auth-flow.md section 3) or a future controlled invite path, guarded so `user_id` cannot be set or changed by a normal client (schema doc 5.3).
- Small ongoing cost: two related concepts to keep straight in code and conversation. The payoff is that adding accounts for children, or opening to more households, is a migration rather than a rewrite.

## Alternatives considered

- **One table where a person is their login.** Simpler today, but the three account-less children have no representation, and adding logins later means retrofitting the concept of a person distinct from a login across the whole schema. Rejected as a guaranteed future rewrite.

## Revisit when

Never expected to be reversed; this is foundational. If children are given accounts, this model already supports it with no structural change.
