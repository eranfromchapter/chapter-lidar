import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { CLAIM_SQL, retryDelaySeconds } from "../src/queue.js";

const squash = (text: string) => text.replace(/\s+/g, " ").trim();

describe("job queue", () => {
  it("claims with exactly the SKIP LOCKED query documented in 0004_jobs.sql", () => {
    const migration = readFileSync(
      new URL("../../db/migrations/0004_jobs.sql", import.meta.url),
      "utf8",
    );
    const comment = migration
      .split("\n")
      .filter((line) => line.startsWith("--"))
      .map((line) => line.replace(/^--\s?/, ""))
      .join("\n");
    const start = comment.indexOf("UPDATE jobs");
    const end = comment.indexOf("RETURNING *;") + "RETURNING *".length;
    assert.ok(start >= 0 && end > start);
    assert.equal(squash(CLAIM_SQL), squash(comment.slice(start, end)));
  });

  it("backs off exponentially with a cap", () => {
    assert.deepEqual(
      [1, 2, 3, 4, 5, 6].map((attempt) => retryDelaySeconds(attempt, 30, 600)),
      [30, 60, 120, 240, 480, 600],
    );
  });
});
