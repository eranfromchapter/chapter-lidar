#!/usr/bin/env node
// Runs the station API tests with node:test and tsx.
//
//   npm test                                  every test/**/*.test.ts
//   npm test -- openapi-conformance           only test files whose path contains a filter
//   npm test -- core/auth uploads/seal        several filters (any match)
//
// A filter that matches no test file fails the run, so a typo cannot pass silently.
// Database tests (*.db.test.ts) skip unless STATION_TEST_DATABASE_URL is set; npm run test:db
// provides one.

import { spawnSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const testDir = join(root, "test");

function findTests(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      return entry.name === "node_modules" || entry.name === "fixtures" ? [] : findTests(path);
    }
    return entry.isFile() && entry.name.endsWith(".test.ts") ? [path] : [];
  });
}

const filters = process.argv.slice(2).filter((arg) => !arg.startsWith("-"));
const all = findTests(testDir).sort();
const selected =
  filters.length === 0
    ? all
    : all.filter((file) => filters.some((filter) => relative(root, file).includes(filter)));

for (const filter of filters) {
  if (!all.some((file) => relative(root, file).includes(filter))) {
    console.error(`No test file matches "${filter}".`);
    process.exit(1);
  }
}
if (selected.length === 0) {
  console.error("No test files found.");
  process.exit(1);
}

const result = spawnSync(
  process.execPath,
  ["--import", "tsx", "--test", "--test-reporter=spec", ...selected],
  { cwd: root, stdio: "inherit" },
);
if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status ?? 1);
