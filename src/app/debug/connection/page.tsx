// TEMPORARY — F-02 connection smoke test. Deleted in F-03, when a real
// sign-in flow proves the same round trip. Deliberately outside the (app)
// group and outside the Phase 1 route list in IA §3; it is not a product
// screen and gets no nav entry.
//
// What "pass" looks like with no session: user null, zero rows, and NO error.
// Zero rows is the point — current_household_id() is null for an
// unauthenticated caller, so RLS denies every row (schema §5). An error here
// instead means the wiring is wrong, not that access was denied.
import { notFound } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

import { BrowserProbe } from "./browser-probe";

// Never prerendered — it must hit the database on each request, and it reads
// cookies via the server client.
export const dynamic = "force-dynamic";

export default async function ConnectionDebugPage() {
  if (process.env.NODE_ENV === "production") notFound();

  const supabase = await createClient();

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const { data: lists, error: listsError } = await supabase
    .from("lists")
    .select("id, name")
    .limit(5);

  // Host only. The anon key is not a secret, but there is no reason to render
  // it, and the habit of not printing keys is worth keeping.
  const rawUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const host = rawUrl ? new URL(rawUrl).host : "MISSING";

  return (
    <main>
      <h1>Supabase connection</h1>

      <ul>
        <li>Supabase host: {host}</li>
        <li>
          Anon key:{" "}
          {process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ? "present" : "MISSING"}
        </li>
      </ul>

      <h2>Server client</h2>
      <ul>
        <li>User: {userData?.user?.email ?? "none"}</li>
        {/* AuthSessionMissingError is expected and not a failure. */}
        <li>Auth error: {userError ? userError.message : "none"}</li>
        <li>Rows from `lists`: {lists?.length ?? "—"}</li>
        <li>
          Query error:{" "}
          {listsError
            ? `${listsError.code ?? "?"}: ${listsError.message}`
            : "none"}
        </li>
      </ul>

      <h2>Browser client</h2>
      <BrowserProbe />

      <p>
        Expected with no session: user none, 0 rows, no query error — the
        connection is live and RLS is denying an unauthenticated caller.
      </p>
    </main>
  );
}
