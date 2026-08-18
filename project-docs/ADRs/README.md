# Architecture Decision Records

Each ADR records one decision: the context that forced it, what was decided, and what living with it means. They are short on purpose. When a decision is reversed, the ADR is not deleted; a new ADR supersedes it and this index is updated.

| # | Decision | Status |
|---|---|---|
| [001](001-nextjs-supabase-stack.md) | Next.js + Supabase as the stack | Accepted |
| [002](002-supabase-auth-magic-link.md) | Supabase Auth over Clerk, magic link only | Accepted |
| [003](003-vercel-hosting.md) | Vercel over Cloudflare for v1 | Accepted |
| [004](004-tailwind-shadcn.md) | Tailwind + shadcn/ui for the UI | Accepted |
| [005](005-server-actions-query-layer.md) | Server Actions + a thin query layer for data access | Accepted |
| [006](006-members-vs-accounts.md) | Members and accounts modelled as separate concepts | Accepted |
| [007](007-ssr-cookie-sessions.md) | Supabase SSR cookie-based sessions | Accepted |

**Format:** Status, Context, Decision, Consequences, and where relevant Alternatives considered and Revisit when. Dates are ISO. Owner is Deshen Padayachee unless noted.
