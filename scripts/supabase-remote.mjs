#!/usr/bin/env node
// Thin wrapper around the Supabase CLI for the throwaway hosted dev project
// (F-02). Never passes --linked or --local, so the target database is
// always the one named by SUPABASE_TEST_DB_URL, never inherited CLI state.

import { spawnSync } from 'node:child_process';

const SUBCOMMANDS = {
  test: (url) => ['test', 'db', '--db-url', url],
  reset: (url) => ['db', 'reset', '--db-url', url, '--yes'],
  'reset:noseed': (url) => ['db', 'reset', '--db-url', url, '--no-seed', '--yes'],
  'push:dry': (url) => ['db', 'push', '--db-url', url, '--dry-run'],
};

const subcommand = process.argv[2];
const args = SUBCOMMANDS[subcommand];

if (!args) {
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

const result = spawnSync('supabase', args(dbUrl), { stdio: 'inherit', shell: true });

if (result.error) {
  console.error(`[supabase-remote] failed to spawn supabase CLI: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status ?? 1);
