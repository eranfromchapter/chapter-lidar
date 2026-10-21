// F7 AC6 guard: every operationId in contract/openapi/station.yaml must be referenced by at
// least one openapi-conformance.*.test.ts under station/api/test, so an operation can never be
// left out of the conformance suite (`npm test -- openapi-conformance`) unnoticed.
//
// This file itself is not counted: it reads the operationIds from the document and names only
// the operations the contract declares ahead of the station (NOT_YET_IMPLEMENTED).

import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { basename, join, relative } from "node:path";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { OpenApi } from "../packages/openapi.js";

const TEST_DIR = fileURLToPath(new URL("..", import.meta.url));
const SELF = basename(fileURLToPath(import.meta.url));
const CONFORMANCE_FILE = /^openapi-conformance\..+\.test\.ts$/;

/**
 * Operations the contract (OpenAPI 1.1.0) declares before the station implements them. Each
 * one leaves this list in the change that adds its route and its conformance test; the test
 * below fails while a listed operation is already covered, so the list cannot go stale.
 */
const NOT_YET_IMPLEMENTED = new Set([
  // Phase 3 (web-review §9.1 H): the package ZIP needs the worker's archive job (migration
  // 0012_archive-job), which is not built yet.
  "requestPackageArchive",
  "getPackageArchive",
]);

function conformanceFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      return entry.name === "node_modules" || entry.name === "fixtures"
        ? []
        : conformanceFiles(path);
    }
    return entry.isFile() && CONFORMANCE_FILE.test(entry.name) && entry.name !== SELF ? [path] : [];
  });
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

describe("OpenAPI conformance coverage", () => {
  const operationIds = new OpenApi().operations.map((op) => op.operationId);
  const files = conformanceFiles(TEST_DIR).map((path) => ({
    name: relative(TEST_DIR, path),
    text: readFileSync(path, "utf8"),
  }));

  it("finds operations in station.yaml and conformance test files", () => {
    assert.ok(operationIds.length > 0, "station.yaml has no operations");
    assert.equal(new Set(operationIds).size, operationIds.length, "duplicate operationIds");
    assert.ok(files.length > 0, "no openapi-conformance.*.test.ts files found");
  });

  it("every operationId is referenced by an openapi-conformance.*.test.ts", () => {
    const missing = operationIds.filter((operationId) => {
      const pattern = new RegExp(`\\b${escapeRegExp(operationId)}\\b`);
      return !files.some((file) => pattern.test(file.text));
    });
    assert.deepEqual(
      missing.filter((operationId) => !NOT_YET_IMPLEMENTED.has(operationId)),
      [],
      `operationIds not referenced by any of ${files.map((file) => file.name).join(", ")}`,
    );
    assert.deepEqual(
      [...NOT_YET_IMPLEMENTED].filter((operationId) => !missing.includes(operationId)),
      [],
      "operations listed as not yet implemented that are in no document or already covered",
    );
  });
});
