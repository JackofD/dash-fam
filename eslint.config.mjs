import { dirname } from "path";
import { fileURLToPath } from "url";
import { FlatCompat } from "@eslint/eslintrc";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const compat = new FlatCompat({
  baseDirectory: __dirname,
});

const eslintConfig = [
  {
    // Build output and Claude Code local state. `.next` at the repo root is
    // ignored by default, but nested copies inside git worktrees are not, and
    // they bury real findings under thousands of generated-file errors.
    ignores: [".claude/**", ".agents/**", "**/.next/**"],
  },
  ...compat.extends("next/core-web-vitals", "next/typescript"),
];

export default eslintConfig;
