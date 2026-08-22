"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

/** Supabase throttles a repeat send to one per minute. */
const RESEND_COOLDOWN_SECONDS = 60;
const CODE_LENGTH = 6;

export function SignInForm() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [codeError, setCodeError] = useState<string | null>(null);
  const [cooldown, setCooldown] = useState(0);

  useEffect(() => {
    if (cooldown <= 0) return;
    const timer = setTimeout(() => setCooldown((n) => n - 1), 1000);
    return () => clearTimeout(timer);
  }, [cooldown]);

  async function sendLink(address: string) {
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email: address,
      options: {
        // Linking a member happens in the on_auth_user_created trigger, which
        // only fires on insert — so a seeded member who has never signed in
        // needs the user to be created here. A stranger who signs in this way
        // gets no household and is denied every row by RLS; they land on
        // /no-household. Abuse is bounded by Supabase's auth rate limits, not
        // by this flag.
        shouldCreateUser: true,
        emailRedirectTo: `${window.location.origin}/auth/confirm`,
      },
    });

    // Deliberately not surfaced. Reporting "no such member" here would let
    // anyone enumerate who is in this household. Every address gets the same
    // "check your email" answer.
    if (error) console.error("signInWithOtp failed", error);
  }

  async function onSubmitEmail(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    await sendLink(email);
    setBusy(false);
    setSent(true);
    setCooldown(RESEND_COOLDOWN_SECONDS);
  }

  async function onSubmitCode(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setCodeError(null);

    const supabase = createClient();
    const { error } = await supabase.auth.verifyOtp({
      email,
      token: code,
      type: "email",
    });

    setBusy(false);

    if (error) {
      setCodeError("That code didn't work. Request a new one below.");
      return;
    }

    // replace, not push: the sign-in screen should not be in the back stack.
    // refresh so the server re-runs the household check with the new cookie.
    router.replace("/");
    router.refresh();
  }

  async function onResend() {
    setBusy(true);
    setCodeError(null);
    setCode("");
    await sendLink(email);
    setBusy(false);
    setCooldown(RESEND_COOLDOWN_SECONDS);
  }

  if (!sent) {
    return (
      <form onSubmit={onSubmitEmail} className="flex flex-col gap-6">
        <div className="flex flex-col gap-2">
          <Label htmlFor="email">Email</Label>
          <Input
            id="email"
            type="email"
            inputMode="email"
            autoComplete="email"
            autoFocus
            required
            placeholder="you@example.com"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
        </div>
        <Button type="submit" disabled={busy || email.trim().length === 0}>
          {busy ? "Sending…" : "Send me a link"}
        </Button>
      </form>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <p className="text-sm text-muted-foreground">
        We sent a link to <span className="text-foreground">{email}</span>. Open
        it on this device, or enter the {CODE_LENGTH}-digit code from the email.
      </p>

      <form onSubmit={onSubmitCode} className="flex flex-col gap-4">
        <div className="flex flex-col gap-2">
          <Label htmlFor="code">Code</Label>
          <Input
            id="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            autoFocus
            pattern="[0-9]*"
            maxLength={CODE_LENGTH}
            placeholder="123456"
            className="text-center text-lg tracking-[0.4em]"
            value={code}
            onChange={(event) =>
              setCode(event.target.value.replace(/\D/g, "").slice(0, CODE_LENGTH))
            }
          />
          {codeError ? (
            <p role="alert" className="text-sm text-destructive">
              {codeError}
            </p>
          ) : null}
        </div>

        <Button type="submit" disabled={busy || code.length !== CODE_LENGTH}>
          {busy ? "Checking…" : "Sign in"}
        </Button>
      </form>

      <div className="flex flex-col gap-2 text-sm">
        <button
          type="button"
          onClick={onResend}
          disabled={busy || cooldown > 0}
          className="text-muted-foreground underline underline-offset-4 disabled:no-underline disabled:opacity-60"
        >
          {cooldown > 0 ? `Resend in ${cooldown}s` : "Send another email"}
        </button>
        <button
          type="button"
          onClick={() => {
            setSent(false);
            setCode("");
            setCodeError(null);
          }}
          className="text-muted-foreground underline underline-offset-4"
        >
          Use a different email
        </button>
      </div>
    </div>
  );
}
