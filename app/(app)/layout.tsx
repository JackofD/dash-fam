import { requireMember } from "@/lib/auth/current-member";

// Every screen in this group resolves the caller's member row per request, so
// there is no static shell to prerender.
export const instant = false;

/**
 * Gate for everything behind sign-in. The proxy has already established that
 * there is a session; this establishes that the session maps to a member of
 * this household.
 *
 * No navigation chrome yet — that arrives with the app shell.
 */
export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  await requireMember();

  return <div className="mx-auto w-full max-w-3xl p-6">{children}</div>;
}
