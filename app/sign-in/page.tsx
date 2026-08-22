import { Suspense } from "react";
import { SignInForm } from "@/components/auth/sign-in-form";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

/** Coarse codes only — never echo a raw auth error back into the URL. */
const ERROR_MESSAGES: Record<string, string> = {
  link: "That link didn't work. It may have expired or already been used. Ask for a new one below.",
};

async function SignInError({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;
  const message = error ? ERROR_MESSAGES[error] : undefined;
  if (!message) return null;

  return (
    <p
      role="alert"
      className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive"
    >
      {message}
    </p>
  );
}

export default function SignInPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  return (
    <main className="flex min-h-svh items-center justify-center p-6">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Dash Fam</CardTitle>
          <CardDescription>
            Enter your email and we&apos;ll send you a link to sign in. No
            password needed.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {/* searchParams is request-time data, so it streams in separately
              rather than blocking the shell (cacheComponents is enabled). */}
          <Suspense fallback={null}>
            <SignInError searchParams={searchParams} />
          </Suspense>
          <SignInForm />
        </CardContent>
      </Card>
    </main>
  );
}
