// npm run generate --workspace @chapter/fixtures [-- --out <dir>]
// Rewrites fixtures/generated (default) from scratch.

import { rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { generateAll } from "./generate.js";
import { repoRoot } from "./json.js";

const args = process.argv.slice(2);
const outIndex = args.indexOf("--out");
const outDir =
  outIndex >= 0 && args[outIndex + 1] !== undefined
    ? resolve(args[outIndex + 1] as string)
    : join(repoRoot, "fixtures", "generated");

rmSync(outDir, { recursive: true, force: true });
await generateAll(outDir);
console.log(`Generated fixtures in ${outDir}`);
