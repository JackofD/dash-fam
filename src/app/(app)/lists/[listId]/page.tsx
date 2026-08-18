// List detail — real content lands in F-05. Stub for the F-01 scaffold.
export default async function ListDetailPage({
  params,
}: {
  params: Promise<{ listId: string }>;
}) {
  const { listId } = await params;
  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-2 p-8">
      <h1 className="font-semibold text-2xl">List</h1>
      <p className="text-zinc-500 dark:text-zinc-400">
        List detail <code className="font-mono">{listId}</code> — scaffold placeholder
      </p>
    </main>
  );
}
