# ADR-003: Vercel over Cloudflare for v1

**Status:** Accepted
**Date:** 2026-08-13
**Depends on:** ADR-001

## Context

The Next.js app needs hosting. Two candidates were weighed: Vercel and Cloudflare (Workers/Pages). The target is Phase 1 live by early September, built in evenings.

## Decision

Host on **Vercel** for v1.

Vercel provides first-party Next.js support: every framework feature works on day one because the framework and platform are built by the same company. Deployment is zero-config, with a preview URL per branch. Next.js on Cloudflare runs through an adapter (the OpenNext project) rather than natively, which adds a layer whose feature support can lag Next.js releases and whose quirks must be understood on top of the framework itself.

Cloudflare's genuine advantages are cheaper, more generous bandwidth and a global edge. At five household users, the cost advantage is worth effectively nothing, and Vercel's well-known cost risk at scale does not apply.

Spending September-critical evenings on adapter compatibility instead of features is the wrong trade.

## Consequences

- Deployment is effectively free of setup cost, which supports the "deploy in week one" discipline in the scope doc's timeline.
- To keep the door to Cloudflare (or anywhere else) open cheaply, **platform-specific APIs must be kept out of application code.** No hard coupling to Vercel primitives in domain logic. This is a standing constraint, not a one-time check.
- Vercel's free tier is assumed sufficient. If usage ever approached paid tiers (it will not, at this scale), that is the trigger to reassess.

## Alternatives considered

- **Cloudflare Workers/Pages.** Cheaper and more generous, but adapter-based Next.js support introduces a debugging and compatibility surface not worth it for the timeline. Deferred, not rejected.
- **Self-hosting (VPS / home server).** Full control, no vendor, but the deploy pipeline, TLS and uptime become the solo developer's problem. Wrong use of scarce evenings. Rejected for v1.

## Revisit when

Costs become real (not foreseeable at five users), Cloudflare's Next.js support becomes first-class, or there is a reason beyond this project to standardise on Cloudflare. Because platform-specific APIs are kept out of app code, the move stays cheap. **Verify current adapter support at revisit time**, since this space moves quickly and this record may be stale.
