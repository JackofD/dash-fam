import type { NextRequest } from "next/server";

import { createClient } from "@/lib/supabase/middleware";

// Refreshes the Supabase session cookie on every matched request (ADR-007,
// env-setup §6). That refresh is what makes the `catch {}` in
// lib/supabase/server.ts safe: a Server Component cannot write cookies, so
// without this running first, a rotated token would be dropped and the user
// would be logged out at random.
//
// F-02 scope is the refresh and nothing else. Redirecting a logged-out
// visitor to /sign-in, and an authenticated user with no household to
// /no-household (D-02), lands in F-03 (auth doc §6). Middleware is never the
// authorization boundary regardless — RLS is.
export async function middleware(request: NextRequest) {
  const { supabase, response } = createClient(request);

  // getUser() — not getSession() — because it revalidates the token with the
  // Auth server, which is what triggers the refresh and the Set-Cookie the
  // factory captures. The result is deliberately unused here.
  await supabase.auth.getUser();

  // Must be the factory's own response object. Building a fresh NextResponse
  // here would discard the refreshed cookies it just set.
  return response;
}

export const config = {
  matcher: [
    // Everything except Next's internals and static assets. Keep this current
    // as routes are added.
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|avif|ico)$).*)",
  ],
};
