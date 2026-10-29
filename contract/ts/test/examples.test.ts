// F1 AC1: every schema compiles and every valid example passes while every
// invalid example fails, in TypeScript.

import assert from "node:assert/strict";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import { SCHEMA_NAMES, formatErrors, getValidator, validate } from "../src/index.js";
import { examplesDir, readJson } from "./paths.js";

/**
 * Where each known invalid example breaks the schema (contract/examples/README.md).
 * Every error must sit at or under this JSON Pointer, so an example that fails
 * for an unrelated reason is caught. Invalid examples not listed here are only
 * required to fail.
 */
const DEFECT_AT: Record<string, string> = {
  "capture-record/capture-without-capture-id.json": "/captures/1",
  "capture-record/unknown-mode.json": "/captures/0/mode",
  // schemaVersion (root) decides which fields are allowed; capture-record-versions.test.ts
  // checks the exact pointers.
  "capture-record/heading-in-1.0.0.json": "",
  "capture-record/heading-without-accuracy.json": "/captures/0",
  "capture-record/heading-and-issue.json": "/captures/0",
  "capture-record/heading-360.json": "/captures/0/heading",
  "capture-record/unknown-heading-source.json": "/captures/0/headingSource",
  "capture-record/sketch-in-1.1.0.json": "",
  "capture-record/sketch-without-source.json": "/captures/1",
  "capture-record/sketch-with-heading.json": "/captures/1",
  "capture-model/z-up.json": "/coordinateSystem/up",
  "capture-model/unknown-room-type.json": "/rooms/0/type",
  // schemaVersion (root) decides which fields are allowed, so Ajv also reports at the root;
  // capture-model-versions.test.ts checks the exact pointers.
  "capture-model/room-type-in-1.0.0.json": "",
  "field-controls/landmark-in-one-capture.json": "/landmarks/0/captures",
  "field-controls/measured-from-scan.json": "/distances/0/measurement/method",
  "manifest/capture-model-without-capture-id.json": "/files/4",
  "manifest/unknown-role.json": "/files/5/role",
  "manifest/visit-file-with-capture-id.json": "/files/0",
  "manifest/unknown-direction-source.json": "/files/9",
  "manifest/direction-source-wrong-type.json": "/files/9",
  // schemaVersion (root) decides which fields and roles are allowed; manifest-versions.test.ts
  // checks the exact pointers.
  "manifest/direction-source-in-1.0.0.json": "",
  "manifest/retired-spatial-report-role-1.1.0.json": "",
  "manifest/sketch-role-in-1.1.0.json": "",
  "sketch-measurements/door-with-sill.json": "/rooms/0/openings/0",
  "sketch-measurements/source-without-path.json": "/source",
  // outcome (root) contradicts findings, so Ajv reports at the root and /findings.
  "verdict/ready-with-blocker.json": "",
};

function within(pointer: string, prefix: string): boolean {
  return prefix === "" || pointer === prefix || pointer.startsWith(`${prefix}/`);
}

function exampleFiles(name: string, kind: "valid" | "invalid"): string[] {
  const dir = join(examplesDir, name, kind);
  if (!existsSync(dir)) {
    return [];
  }
  return readdirSync(dir)
    .filter((file) => file.endsWith(".json"))
    .sort()
    .map((file) => join(dir, file));
}

describe("contract examples", () => {
  it("has an example folder for every schema and a schema for every example folder", () => {
    const folders = readdirSync(examplesDir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
      .sort();
    assert.deepEqual(folders, [...SCHEMA_NAMES].sort());
  });

  for (const name of SCHEMA_NAMES) {
    describe(name, () => {
      it("compiles under Ajv 2020-12 strict mode", () => {
        assert.doesNotThrow(() => getValidator(name));
      });

      const valid = exampleFiles(name, "valid");
      const invalid = exampleFiles(name, "invalid");

      it("has at least one valid and one invalid example", () => {
        assert.ok(valid.length > 0, `no valid examples for ${name}`);
        assert.ok(invalid.length > 0, `no invalid examples for ${name}`);
      });

      for (const file of valid) {
        it(`accepts valid/${file.split("/").pop()}`, () => {
          const result = validate(name, readJson(file));
          assert.ok(result.ok, `expected valid, got:\n${formatErrors(result.errors)}`);
          assert.deepEqual(result.errors, []);
        });
      }

      for (const file of invalid) {
        it(`rejects invalid/${file.split("/").pop()}`, () => {
          const result = validate(name, readJson(file));
          assert.equal(result.ok, false, "expected the example to fail the schema");
          assert.ok(result.errors.length > 0);
          const prefix = DEFECT_AT[`${name}/${file.split("/").pop()}`];
          if (prefix !== undefined) {
            const stray = result.errors.filter((error) => !within(error.instancePath, prefix));
            assert.deepEqual(stray, [], `errors outside ${prefix || "/"}:\n${formatErrors(stray)}`);
          }
        });
      }
    });
  }
});
