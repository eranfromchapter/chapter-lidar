// The plan page of an AR walkthrough capture (spec F15 5): "AR walkthrough" under the floor title
// and the walkthrough note among the plan notes, where a sketch capture's page says "Sketch
// capture"; a scanned floor's page says neither.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Capture } from "@chapter/capture-contract";
import { renderSpatialReport } from "../../src/report/index.js";
import { WORDS } from "../../src/report/words.js";
import { squash } from "../helpers.js";
import { layoutOf, pageTexts, syntheticInput } from "./support.js";

const has = (text: string, part: string) => squash(text).includes(squash(part));

const SKETCH: Capture["sketch"] = {
  measurements: "complete",
  wallsMeasured: 4,
  wallsEstimated: 0,
  ceilingHeightSource: "measured",
  closureResidualMm: 8,
};

const WALKTHROUGH: Partial<Capture> = {
  captureSource: "walkthrough",
  sketch: SKETCH,
  walkthrough: {
    scaleSource: "tape",
    scaleFactor: 0.99725,
    loopClosureMm: 38.3,
    trackingLimitedSeconds: 0.5,
    recorded: true,
  },
};

describe("the plan page of an AR walkthrough capture", () => {
  it("says AR walkthrough on the walked floor's page only, and no sketch wording", async () => {
    const input = syntheticInput([
      { label: "Floor 1", rooms: [{ label: "Living room", w: 5, d: 4 }] },
      { label: "Floor 2", rooms: [{ label: "Bedroom", w: 4, d: 3 }], capture: WALKTHROUGH },
      {
        label: "Floor 3",
        rooms: [{ label: "Attic", w: 4, d: 3 }],
        capture: { captureSource: "sketch", sketch: SKETCH },
      },
    ]);
    const report = await renderSpatialReport(input);
    const texts = await pageTexts(report.bytes);
    const { pages } = layoutOf(input);
    const planPage = (floor: number) => {
      const page = pages.findIndex((spec) => spec.kind === "plan" && spec.floor === floor);
      assert.ok(page >= 0, `plan page of floor ${floor}`);
      return texts[page] as string;
    };
    assert.ok(has(planPage(1), WORDS.walkthroughCapture));
    assert.ok(has(planPage(1), WORDS.walkthroughPlanNote));
    assert.ok(!has(planPage(1), WORDS.sketchCapture));
    assert.ok(!has(planPage(1), WORDS.sketchPlanNote));
    // The sketch floor keeps its wording; the scanned floor says neither.
    assert.ok(has(planPage(2), WORDS.sketchCapture));
    assert.ok(!has(planPage(2), WORDS.walkthroughPlanNote));
    for (const words of [
      WORDS.walkthroughCapture,
      WORDS.walkthroughPlanNote,
      WORDS.sketchCapture,
    ]) {
      assert.ok(!has(planPage(0), words), words);
    }
  });

  it("notes the walkthrough on a single floor's page, where the contents list stands in for the title", async () => {
    const input = syntheticInput([
      { label: "Floor 1", rooms: [{ label: "Kitchen", w: 4, d: 3 }], capture: WALKTHROUGH },
    ]);
    const report = await renderSpatialReport(input);
    const texts = await pageTexts(report.bytes);
    const { pages } = layoutOf(input);
    const page = pages.findIndex((spec) => spec.kind === "plan");
    assert.ok(page >= 0);
    assert.ok(has(texts[page] as string, WORDS.walkthroughPlanNote));
  });
});
