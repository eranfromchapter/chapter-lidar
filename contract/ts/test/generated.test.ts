// The committed files in src/generated must equal a fresh generation, so a
// schema change without `npm run generate` fails CI.

import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import { generate, generatedDir } from "../scripts/generate.js";
import { SCHEMA_NAMES, SCHEMAS } from "../src/index.js";
import { schemaPath } from "../src/node.js";
import { readJson } from "./paths.js";

describe("generated sources", () => {
  it("match a fresh generation from contract/schema", async () => {
    const expected = await generate();
    const committed = readdirSync(generatedDir).sort();
    assert.deepEqual(committed, [...expected.keys()].sort(), "generated file set differs");
    for (const [fileName, content] of expected) {
      assert.equal(
        readFileSync(join(generatedDir, fileName), "utf8"),
        content,
        `src/generated/${fileName} is stale; run npm run generate -w @chapter/capture-contract`,
      );
    }
  });

  for (const name of SCHEMA_NAMES) {
    it(`embeds ${name}.schema.json unchanged`, () => {
      assert.deepEqual(SCHEMAS[name], readJson(schemaPath(name)));
    });
  }
});
