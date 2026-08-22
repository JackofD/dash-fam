import { redirect } from "next/navigation";
import { SignOutButton } from "@/components/auth/sign-out-button";
import { getCurrentMember } from "@/lib/auth/current-member";
import { createClient } from "@/lib/supabase/server";

// Reads the session on every request and has nothing worth prerendering.
export const instant = false;

export default async function NoHouseholdPage() {
  // If an account did get linked, this screen is stale — send them home.
  if (await getCurrentMember()) redirect("/");

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <main className="flex min-h-svh items-center justify-center p-6">
      <div className="flex w-full max-w-sm flex-col gap-6">
        <div className="flex flex-col gap-3">
          <h1 className="text-2xl font-semibold">You&apos;re not in this household</h1>
          <p className="text-sm text-muted-foreground">
            You&apos;re signed in
            {user?.email ? (
              <>
                {" "}
                as <span className="text-foreground">{user.email}</span>
              </>
            ) : null}
            , but that address isn&apos;t set up for this household.
          </p>
          <p className="text-sm text-muted-foreground">
            If you used the wrong address, sign out and try the other one.
            Otherwise ask whoever set up Dash Fam to add you.
          </p>
        </div>
        <SignOutButton />
      </div>
    </main>
  );
}
