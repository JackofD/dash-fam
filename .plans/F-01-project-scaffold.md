# F-01 — Project Scaffold & Deployment Pipeline

> On approval, this plan is written to `.plans/F-01-project-scaffold.md` in the repo (the only execution step that is a file write; everything else is scaffolding commands run by Deshen).

## Context

Dash Fam is a private household web app, currently **planning docs only** — no app code, no `package.json`, no `supabase/`. F-01 is the very first build feature of Phase 1: stand up a version-controlled Next.js app that runs locally, is checked by CI on every change, and **auto-deploys to a live production URL before any feature code exists**. This is the discipline the whole plan leans on (ADR-003, scope timeline): "an app that has never been deployed is not close to being deployable."

F-01 is deliberately narrow. **In scope:** scaffold, folder structure, GitHub, CI (lint/typecheck/build), Vercel connection, first prod deploy. **Explicitly out of scope:** all feature logic, and **Supabase wiring — that is F-02.** We create the empty `lib/supabase/` and `supabase/` folder *shapes* but do not write client/migration/seed code here.

Runbook source of truth: `project-docs/06-environment-setup.md`. Precedence: `04-decisions-log.md` > docs 00–03; ADRs are the architectural record.

## Definition of Done (from feature doc)

Env-doc checklist steps **1–3, 8, 9, 10** ticked: empty app live in production, CI green on a PR, Vercel auto-deploying `main`→prod and branches→previews, production URL loads on a phone. (Steps 4–7 are Supabase = F-02.)

---

## Steps

### 1. Verify prerequisites (env §2)
`node -v` (LTS 20.x+), `npm -v`, `git --version`, and confirm a **Vercel account linked to GitHub**. Docker + Supabase CLI are needed for F-02, not F-01 — skip here.

### 2. Scaffold Next.js (env §3, ADR-001/004)
```bash
npx create-next-app@latest dash-fam
```
Prompts: **TypeScript yes, App Router yes, Tailwind yes, ESLint yes, `src/` yes, import alias `@/*`**. Confirm `tsconfig.json` has `"strict": true` (CLAUDE.md requires TS strict).

> **Repo topology (decided): single repo, app at root.** The app scaffolds **into this existing repo** alongside `project-docs/`, keeping one git history. Since `create-next-app` wants an empty-ish target and creates its own git repo, do this safely: scaffold into a temp dir (`npx create-next-app@latest dash-fam-tmp`), **delete the generated `.git`**, then move the app files into the repo root, merging `create-next-app`'s `.gitignore` into the existing one (don't clobber the existing gitignore). Vercel Root Directory stays the repo root.

### 3. Create the folder structure (env §4)
Establish the Phase-1 shape up front so later features are assembly. Create directories + minimal placeholder files (empty route pages that render a stub, empty `lib` folders). Structure:
```
src/
  app/
    (auth)/sign-in/page.tsx        stub
    auth/callback/route.ts         stub (empty handler, wired in F-03)
    (app)/
      page.tsx                     Home /  (stub)
      lists/page.tsx               /lists (stub)
      lists/[listId]/page.tsx      stub
      settings/page.tsx            stub
    no-household/page.tsx          stub
    layout.tsx                     root layout (fonts/theme wired later in F-04)
  components/
    ui/                            shadcn target (empty)
    dash/                          MemberAvatar etc. (empty, later phases)
  lib/
    supabase/                      empty — client/server/middleware are F-02/F-03
    queries/                       empty (ADR-005 read layer)
    actions/                       empty (ADR-005 write layer)
  middleware.ts                    NOT created here — added in F-03
supabase/
  migrations/                      empty — F-02
  seed.sql                         NOT created here — F-02
```
Stub pages should render a trivial marker (e.g. the route name) so the deploy is visibly alive. Keep them free of any Supabase/auth calls. `.gitkeep` in the empty `lib/*` and `supabase/*` dirs so structure is committed.

### 4. Commit on the feature branch
Already on `feature/f-01-project-scaffold`. Commit the scaffold. Do **not** touch `main` directly.

### 5. `.env.example` (env §7)
Commit `.env.example` documenting the two keys with **no values**:
```
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
```
No `.env.local` yet (no Supabase project until F-02) — the scaffold doesn't read these keys, so the build stays green without them. Confirm `create-next-app`'s `.gitignore` covers `.env*.local`.

### 6. CI workflow (env §8.2)
Add `.github/workflows/ci.yml` exactly per the runbook — on `pull_request`, `runs-on: ubuntu-latest`: checkout → setup-node 20 (npm cache) → `npm ci` → `npm run lint` → `npx tsc --noEmit` → `npm run build`. No secrets, no DB. (Test step is deferred to D-08.) Verify `npm run lint`, `npx tsc --noEmit`, `npm run build` all pass **locally** first.

### 7. Push repo to GitHub (env §8.1)
Ensure the repo (with `project-docs/` and the app) is on GitHub. Open a **PR from `feature/f-01-project-scaffold` → `main`** and confirm CI runs and goes **green** (acceptance criterion).

### 8. Connect Vercel (env §8.3, ADR-003)
In Vercel: import the GitHub repo, framework auto-detected as Next.js, zero-config. Root Directory = repo root (app is at root). Every branch → preview deploy; `main` → production. No Vercel env vars needed yet (Supabase is F-02) — the scaffold builds without them.

### 9. Merge and deploy to production (env §9 step 10)
Merge the PR to `main`; Vercel auto-deploys prod. **Open the production URL on a phone** and confirm the empty app loads. This is the DoD.

### 10. Standing constraints to honour while scaffolding
- Keep **platform-specific (Vercel) APIs out of app code** (ADR-003).
- **No service role key** anywhere; no Supabase calls in F-01 at all.
- TS strict on; CI must stay green.

---

## Critical files created
- `package.json`, `tsconfig.json` (strict), `next.config.*`, `tailwind.config.*`, `eslint` config — from `create-next-app`
- `src/app/**` stub routes + `src/app/layout.tsx`
- `src/lib/{supabase,queries,actions}/.gitkeep`, `src/components/{ui,dash}/.gitkeep`, `supabase/migrations/.gitkeep`
- `.github/workflows/ci.yml`
- `.env.example`

## Verification (end-to-end)
1. `npm run dev` — app runs locally; each stub route reachable at `/`, `/lists`, `/lists/x`, `/settings`, `/sign-in`, `/no-household`.
2. `npm run lint` && `npx tsc --noEmit` && `npm run build` — all pass locally.
3. Open PR → GitHub Actions **CI green** (lint + typecheck + build).
4. Vercel **preview** deploy succeeds on the PR branch.
5. Merge to `main` → **production** deploy succeeds; open the prod URL **on a phone** — empty app loads over the internet.

## Decided
Repo topology: **single repo, app at root** — scaffold into this repo alongside `project-docs/`, one git history, Vercel Root Directory = repo root.
