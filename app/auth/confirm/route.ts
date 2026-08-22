import { type EmailOtpType } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import { type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

/**
 * Only the email OTP types this app actually issues.
 *
 * "email" is what the templates should send and covers both cases. The other
 * two are accepted because `signInWithOtp` with shouldCreateUser: true sends
 * the *Confirm signup* template on a first-ever sign-in and the *Magic link*
 * template afterwards — so a default template left unedited yields "signup"
 * or "magiclink" instead, and rejecting those would break exactly the
 * first-run case that is hardest to debug.
 *
 * Recovery and email_change are deliberately absent: this app issues neither.
 */
const ALLOWED_TYPES: readonly EmailOtpType[] = ["email", "magiclink", "signup"];

/**
 * Where to land after a successful verify. Only same-origin relative paths are
 * allowed: an unvalidated `next` is an open redirect, and this URL arrives in
 * an email where an attacker controls the query string.
 */
function safeNext(value: string | null): string {
  if (!value) return "/";
  if (!value.startsWith("/")) return "/";
  // "//evil.com" and "/\evil.com" are protocol-relative, not local paths.
  if (value.startsWith("//") || value.startsWith("/\\")) return "/";
  return value;
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;
  const next = safeNext(searchParams.get("next"));

  if (!tokenHash || !type || !ALLOWED_TYPES.includes(type)) {
    redirect("/sign-in?error=link");
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });

  if (error) {
    // Expired, already consumed, or tampered with. The user only needs to know
    // to ask for a new link, so the reason stays in the server log rather than
    // being reflected into a URL and rendered.
    console.error("verifyOtp failed", error);
    redirect("/sign-in?error=link");
  }

  redirect(next);
}
