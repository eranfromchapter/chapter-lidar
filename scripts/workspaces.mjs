#!/usr/bin/env node
// Runs an npm script in every npm workspace that exists, with --if-present.
//
// `npm run <script> --workspaces` fails with "No workspaces found!" while no
// workspace folder exists yet. Workspace folders land feature by feature, so
// this wrapper expands the root "workspaces" patterns itself and only calls npm
// when at least one workspace package.json is present.
//
// Usage: node scripts/workspaces.mjs <script>

import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const script = process.argv[2];

if (!script) {
  console.error("usage: node scripts/workspaces.mjs <script>");
  process.exit(2);
}

const rootPackage = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const patterns = Array.isArray(rootPackage.workspaces) ? rootPackage.workspaces : [];

/** Expands a workspace pattern. Only literal paths and "<dir>/*" are supported. */
function expand(pattern) {
  if (pattern.endsWith("/*")) {
    const base = pattern.slice(0, -2);
    if (base.includes("*")) {
      throw new Error(`Unsupported workspace pattern: ${pattern}`);
    }
    const dir = join(root, base);
    if (!existsSync(dir) || !statSync(dir).isDirectory()) {
      return [];
    }
    return readdirSync(dir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => join(base, entry.name));
  }
  if (pattern.includes("*")) {
    throw new Error(`Unsupported workspace pattern: ${pattern}`);
  }
  return [pattern];
}

const present = patterns
  .flatMap(expand)
  .filter((location) => existsSync(join(root, location, "package.json")));

if (present.length === 0) {
  console.log(`No npm workspaces present yet; nothing to run for "${script}".`);
  process.exit(0);
}

console.log(`Running "${script}" in workspaces: ${present.join(", ")}`);
const npm = process.platform === "win32" ? "npm.cmd" : "npm";
const result = spawnSync(npm, ["run", script, "--workspaces", "--if-present"], {
  cwd: root,
  stdio: "inherit",
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status ?? 1);
