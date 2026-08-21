#!/usr/bin/env node
// Thin wrapper around the Supabase CLI for the throwaway hosted dev project
// (F-02). Never passes --linked or --local, so the target database is
// always the one named by SUPABASE_TEST_DB_URL, never inherited CLI state.

import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const TYPES_FILE = 'src/lib/supabase/database.types.ts';

const SUBCOMMANDS = {
  test: { args: (url) => ['test', 'db', '--db-url', url] },
  reset: { args: (url) => ['db', 'reset', '--db-url', url, '--yes'] },
  'reset:noseed': {
    args: (url) => ['db', 'reset', '--db-url', url, '--no-seed', '--yes'],
  },
  'push:dry': { args: (url) => ['db', 'push', '--db-url', url, '--dry-run'] },
  // Regenerate the committed Database type from the live schema. Re-run this
  // after every new migration, or the client generics silently describe the
  // old shape.
  'gen:types': {
    args: (url) => ['gen', 'types', 'typescript', '--db-url', url, '--schema', 'public'],
    outFile: TYPES_FILE,
  },
};

const subcommand = process.argv[2];
const spec = SUBCOMMANDS[subcommand];

if (!spec) {
  console.error(
    `Usage: node scripts/supabase-remote.mjs <${Object.keys(SUBCOMMANDS).join('|')}>`
  );
  process.exit(1);
}

const dbUrl = process.env.SUPABASE_TEST_DB_URL;

if (!dbUrl) {
  console.error(
    'SUPABASE_TEST_DB_URL is not set. Copy .env.example to .env.local and fill it in.'
  );
  process.exit(1);
}

const target = dbUrl.replace(/:\/\/([^:]+):[^@]*@/, '://$1:****@');
console.log(`[supabase-remote] target: ${target}`);

// Capture stdout only when we need to redirect it to a file; otherwise let the
// CLI write straight through so its progress output stays live. stderr is
// always inherited, so CLI progress surfaces either way — but note the CLI
// reports *failures* as JSON on stdout, which is why the non-zero branch below
// has to replay the captured buffer.
const result = spawnSync('supabase', spec.args(dbUrl), {
  stdio: spec.outFile ? ['inherit', 'pipe', 'inherit'] : 'inherit',
  shell: true,
  encoding: 'utf8',
});

if (result.error) {
  console.error(`[supabase-remote] failed to spawn supabase CLI: ${result.error.message}`);
  process.exit(1);
}

if (result.status !== 0) {
  // In outFile mode stdout is piped, so a CLI error message would be trapped in
  // the buffer and the command would fail with no explanation. Replay it.
  if (spec.outFile && result.stdout) {
    process.stderr.write(result.stdout);
  }
  process.exit(result.status ?? 1);
}

if (spec.outFile) {
  // Only write on a clean exit — a partial or empty capture would otherwise
  // clobber a good committed types file with something that doesn't compile.
  if (!result.stdout || !result.stdout.trim()) {
    console.error(
      `[supabase-remote] ${subcommand} produced no output; leaving ${spec.outFile} untouched.`
    );
    process.exit(1);
  }
  writeFileSync(spec.outFile, result.stdout);
  console.log(`[supabase-remote] wrote ${spec.outFile}`);
}

process.exit(0);
