// No-household access screen — wired in F-03 (D-02). Stub for the F-01 scaffold.
export default function NoHouseholdPage() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-2 p-8">
      <h1 className="font-semibold text-2xl">No access</h1>
      <p className="text-zinc-500 dark:text-zinc-400">
        This account is not part of a household — scaffold placeholder
      </p>
    </main>
  );
}
