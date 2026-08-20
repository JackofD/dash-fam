"use client";

import { useEffect, useState } from "react";

import { createClient } from "@/lib/supabase/client";

type ProbeResult = {
  session: string;
  rowCount: number | null;
  error: string | null;
};

// The browser half of the smoke test. This is the only check that can catch a
// missing NEXT_PUBLIC_ inline — the server sees process.env either way, so a
// server-only probe would pass while the shipped bundle had `undefined` baked
// in. Temporary; deleted with the rest of /debug/connection in F-03.
export function BrowserProbe() {
  const [result, setResult] = useState<ProbeResult | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function probe(): Promise<ProbeResult> {
      try {
        const supabase = createClient();
        const { data: sessionData } = await supabase.auth.getSession();
        const { data, error } = await supabase
          .from("lists")
          .select("id, name")
          .limit(5);

        return {
          session: sessionData.session ? "present" : "none",
          rowCount: data?.length ?? null,
          error: error ? `${error.code ?? "?"}: ${error.message}` : null,
        };
      } catch (cause) {
        // A thrown error here (rather than a returned one) is the signature of
        // a bad URL or an env var that never made it into the bundle.
        return {
          session: "unknown",
          rowCount: null,
          error: cause instanceof Error ? cause.message : String(cause),
        };
      }
    }

    probe().then((value) => {
      if (!cancelled) setResult(value);
    });

    return () => {
      cancelled = true;
    };
  }, []);

  if (!result) return <p>Browser client: probing…</p>;

  return (
    <ul>
      <li>Browser session: {result.session}</li>
      <li>Browser rows from `lists`: {result.rowCount ?? "—"}</li>
      <li>Browser error: {result.error ?? "none"}</li>
    </ul>
  );
}
