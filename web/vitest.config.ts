import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));

export default defineConfig({
  oxc: {
    jsx: { runtime: "automatic", importSource: "react" },
  },
  resolve: {
    alias: [
      { find: /^@\//, replacement: `${here("./")}` },
      // "server-only" throws outside the react-server build condition; tests run the server
      // modules directly.
      { find: /^server-only$/, replacement: here("./test/support/server-only.ts") },
      // The checks package ships TypeScript sources (no build on install); tests use them to
      // compute fixture verdicts.
      {
        find: /^@chapter\/station-checks\/node$/,
        replacement: here("../station/checks/src/node.ts"),
      },
      { find: /^@chapter\/station-checks$/, replacement: here("../station/checks/src/index.ts") },
    ],
  },
  test: {
    include: ["test/**/*.test.{ts,tsx}"],
    environment: "node",
    restoreMocks: true,
    env: { CHAPTER_REPO_ROOT: here("../") },
    testTimeout: 30_000,
    // next-auth imports "next/server" without an extension, which Node's ESM resolver rejects
    // (next has no exports map); let Vite resolve it as Next.js's bundler does.
    server: { deps: { inline: ["next-auth", "@auth/core"] } },
  },
});
