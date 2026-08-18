# ADR-004: Tailwind + shadcn/ui for the UI

**Status:** Accepted
**Date:** 2026-08-13
**Depends on:** ADR-001

## Context

The app is phone-first with a desktop planning surface and needs a consistent, restyleable look tied to a household colour system (per-member colours defined in the schema). It is built solo against a September target, so time-to-usable matters, but so does not being locked into a look that fights the Dash Fam identity. A styling approach and a component strategy were needed before UI work begins.

## Decision

Use **Tailwind CSS** for styling and **shadcn/ui** for components.

shadcn/ui is not a runtime dependency. Its components are copied into the repository and owned outright: there is no library version dictating the look and no upgrade that can break the UI from outside. Components are built on Tailwind and accessible primitives (Radix), and can be restyled freely to match the Dash Fam palette rather than inheriting someone else's design language.

This is also the most heavily documented combination for the Next.js + Supabase stack, which shortens the distance between hitting a problem and finding the answer, a real factor for solo evening work.

## Consequences

- Components live in the repo and are the project's to maintain. This is the intended trade: full control and zero external styling lock-in, in exchange for owning the code.
- The per-member colour system (schema 3.2) becomes a set of design tokens in the Tailwind config, applied consistently across chores, events and meals. This belongs in the style guide.
- Getting to a working Phase 1 UI is faster than hand-building every component, and less locked-in than a batteries-included library (Mantine, MUI, Chakra).
- Dark and light themes are a first-class concern from the start, because per-member colours must remain distinguishable and accessible in both (an open item in the schema doc).

## Alternatives considered

- **Tailwind with no component library.** Maximum control, but rebuilding accessible dialogs, menus and form controls by hand is slow and error-prone against the timeline. Rejected.
- **A styled component library (Mantine / MUI / Chakra).** Fastest initial build, but inherits their visual identity and a runtime dependency, and restyling to the Dash Fam palette fights the framework. Rejected on lock-in.

## Revisit when

The owned-component maintenance burden ever outweighs the control it buys, which is unlikely at this scope.
