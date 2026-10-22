// The fonts and the logo the report embeds are generated from the phone's plan-sheet fonts
// (PlanExport ChapterBrandAssets.swift) and the web logo (web/public/brand/chapter-logo.svg).
// When either changes, this fails until `npm run brand-assets -w @chapter/station-hub` is run,
// so the report never keeps old bytes without anyone noticing.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";

const SCRIPT = fileURLToPath(new URL("../../scripts/generate-brand-assets.mjs", import.meta.url));

describe("brand assets", () => {
  it("match their sources (generate-brand-assets.mjs --check)", () => {
    const run = spawnSync(process.execPath, [SCRIPT, "--check"], { encoding: "utf8" });
    assert.equal(run.status, 0, `${run.stdout}${run.stderr}`);
    assert.match(run.stdout, /is up to date/);
  });
});
