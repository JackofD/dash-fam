import { redirect } from "next/navigation";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/types";

export type Member = Tables<"members">;

/**
 * The member row for the signed-in account, or null.
 *
 * Null covers two distinct cases the caller does not need to tell apart:
 * no session at all, and a session whose email matched no member's
 * invited_email when the on_auth_user_created trigger ran. Both mean "cannot
 * see any household data".
 *
 * There is no household filtering here on purpose — members_select already
 * restricts this to current_household_id(). RLS is the boundary; duplicating
 * it in app code is how the two drift apart.
 *
 * Wrapped in cache() so a layout and the page it renders share one round trip
 * per request instead of each issuing their own.
 */
export const getCurrentMember = cache(async (): Promise<Member | null> => {
  const supabase = await createClient();

  // getUser, not getSession: it revalidates the token against the auth server
  // rather than trusting whatever is in the cookie.
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase
    .from("members")
    .select("*")
    .eq("user_id", user.id)
    .is("deactivated_at", null)
    // maybeSingle, not single: zero rows is the expected unlinked case, not an
    // error worth throwing over.
    .maybeSingle();

  if (error) {
    console.error("Failed to resolve current member", error);
    return null;
  }

  return data;
});

/**
 * Guard for authenticated screens. Sends an account with no member row to
 * /no-household, which lives outside the (app) route group so this cannot
 * loop. The proxy has already handled the no-session case.
 *
 * This is routing, not security — an account that skipped it still reads zero
 * rows through RLS.
 */
export async function requireMember(): Promise<Member> {
  const member = await getCurrentMember();
  if (!member) redirect("/no-household");
  return member;
}
