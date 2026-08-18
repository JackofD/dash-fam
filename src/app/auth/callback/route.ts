import { NextResponse } from "next/server";

// Magic-link PKCE code exchange lands in F-03. Stub for the F-01 scaffold:
// no session handling yet, just a valid handler that returns to sign-in.
export function GET(request: Request) {
  return NextResponse.redirect(new URL("/sign-in", request.url));
}
