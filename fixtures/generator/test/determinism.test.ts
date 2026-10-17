// F11 AC1: the generator is deterministic. Two runs produce byte-identical fixtures, and the
// committed fixtures are exactly what the generator writes today.

import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { generateAll } from "../src/generate.js";
import { generatedDir, generatorDir, listFiles, readTree } from "./helpers.js";

function compare(a: Map<string, Buffer>, b: Map<string, Buffer>, label: string): void {
  assert.deepEqual([...a.keys()], [...b.keys()], `${label}: same file list`);
  for (const [path, bytes] of a) {
    assert.ok(bytes.equals(b.get(path) as Buffer), `${label}: ${path} differs`);
  }
}

describe("generator determinism", () => {
  it("two runs produce byte-identical fixtures, equal to the committed ones", async () => {
    const first = mkdtempSync(join(tmpdir(), "chapter-fixtures-a-"));
    const second = mkdtempSync(join(tmpdir(), "chapter-fixtures-b-"));
    try {
      await generateAll(first);
      await generateAll(second);
      const treeA = readTree(first);
      assert.ok(treeA.size > 100, "fixtures were written");
      compare(treeA, readTree(second), "run 1 vs run 2");
      assert.deepEqual(listFiles(generatedDir), [...treeA.keys()]);
      compare(treeA, readTree(generatedDir), "fresh run vs committed fixtures/generated");
    } finally {
      rmSync(first, { recursive: true, force: true });
      rmSync(second, { recursive: true, force: true });
    }
  });

  it("the generator source never reads the clock or an unseeded random source", () => {
    const srcDir = join(generatorDir, "src");
    const banned = [
      /Math\.random/,
      /Date\.now/,
      /new Date\(\)/,
      /randomUUID/,
      /randomBytes/,
      /performance\.now/,
    ];
    for (const path of listFiles(srcDir).filter((file) => file.endsWith(".ts"))) {
      const text = readFileSync(join(srcDir, path), "utf8");
      for (const pattern of banned) {
        assert.ok(!pattern.test(text), `${path} uses ${pattern}`);
      }
    }
  });
});
