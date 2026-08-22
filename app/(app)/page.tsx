import { Suspense } from "react";
import { connection } from "next/server";
import { requireMember } from "@/lib/auth/current-member";
import { createClient } from "@/lib/supabase/server";

/**
 * "Today" resolves against the household's fixed timezone, not the browser's
 * and not UTC, so everyone in the house agrees on what day it is.
 */
async function Today() {
  // Reading the clock is request-time work: connection() keeps it out of the
  // prerender, which would otherwise fail the build under Cache Components.
  await connection();

  const supabase = await createClient();
  const { data: household } = await supabase
    .from("households")
    .select("timezone")
    .limit(1)
    .maybeSingle();

  const formatted = new Intl.DateTimeFormat("en-ZA", {
    weekday: "long",
    day: "numeric",
    month: "long",
    timeZone: household?.timezone ?? "Africa/Johannesburg",
  }).format(new Date());

  return <p className="text-sm text-muted-foreground">{formatted}</p>;
}

export default async function HomePage() {
  const member = await requireMember();

  return (
    <main className="flex flex-col gap-2">
      <h1 className="text-2xl font-semibold">Hi {member.display_name}</h1>
      <Suspense fallback={<p className="text-sm text-muted-foreground">&nbsp;</p>}>
        <Today />
      </Suspense>
    </main>
  );
}
