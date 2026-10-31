// The plan page of a sketch capture (spec F14 1.7): "Sketch capture" under the floor title and
// the sketch note among the plan notes; a scanned floor's page says nothing of the kind.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Capture } from "@chapter/capture-contract";
import { renderSpatialReport } from "../../src/report/index.js";
import { WORDS } from "../../src/report/words.js";
import { squash } from "../helpers.js";
import { layoutOf, pageTexts, syntheticInput } from "./support.js";

const has = (text: string, part: string) => squash(text).includes(squash(part));

const SKETCH: Partial<Capture> = {
  captureSource: "sketch",
  sketch: {
    measurements: "complete",
    wallsMeasured: 4,
    wallsEstimated: 0,
    ceilingHeightSource: "measured",
    closureResidualMm: 8,
  },
};

describe("the plan page of a sketch capture", () => {
  it("says Sketch capture on the sketch floor's page only", async () => {
    const input = syntheticInput([
      { label: "Floor 1", rooms: [{ label: "Living room", w: 5, d: 4 }] },
      { label: "Floor 2", rooms: [{ label: "Bedroom", w: 4, d: 3 }], capture: SKETCH },
    ]);
    const report = await renderSpatialReport(input);
    const texts = await pageTexts(report.bytes);
    const { pages } = layoutOf(input);
    const planPage = (floor: number) => {
      const page = pages.findIndex((spec) => spec.kind === "plan" && spec.floor === floor);
      assert.ok(page >= 0, `plan page of floor ${floor}`);
      return texts[page] as string;
    };
    assert.ok(has(planPage(1), WORDS.sketchCapture));
    assert.ok(has(planPage(1), WORDS.sketchPlanNote));
    assert.ok(!has(planPage(0), WORDS.sketchPlanNote));
    assert.ok(!has(planPage(0), WORDS.sketchCapture));
  });

  it("notes the sketch on a single floor's page, where the contents list stands in for the title", async () => {
    const input = syntheticInput([
      { label: "Floor 1", rooms: [{ label: "Kitchen", w: 4, d: 3 }], capture: SKETCH },
    ]);
    const report = await renderSpatialReport(input);
    const texts = await pageTexts(report.bytes);
    const { pages } = layoutOf(input);
    const page = pages.findIndex((spec) => spec.kind === "plan");
    assert.ok(page >= 0);
    assert.ok(has(texts[page] as string, WORDS.sketchPlanNote));
  });
});
