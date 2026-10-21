// Capture model 1.1.0 (docs/floorplan-report-plan.md, phase 2): the station reads capture
// models of schema 1.0.0 (the generated fixtures, and apps before 1.1.0) and 1.1.0. A package
// whose capture models are 1.1.0 with the new fields gets the same verdict as the same package
// written as 1.0.0.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { CaptureModel } from "@chapter/capture-contract";
import { parseByRole } from "../src/parsers/index.js";
import type { LoadedPackage } from "../src/types.js";
import { runChecks } from "../src/verdict.js";
import { goodOutcome, loadGood, pathOf, readIndex, readTruth, withJson } from "./helpers.js";

/** Fixed so the verdicts of two packages compare whole. */
const OPTIONS = {
  evaluatedAt: "2026-10-18T12:00:00Z",
  verdictId: "0b7e5c2a-4d1f-4e8b-9a3c-6f2d1e0b9c7a",
};

/** Sets schema 1.1.0 and every field it adds. The values are arbitrary; geometry is unchanged. */
function toVersion11(model: CaptureModel): void {
  model.schemaVersion = "1.1.0";
  for (const room of model.rooms) {
    room.type = room.label === "Bedroom" ? "bedroom" : "living_room";
    room.typeSource = "roomplan_section";
  }
  model.doors.forEach((door, index) => {
    door.isOpen = index % 2 === 0;
  });
  model.objects.forEach((object, index) => {
    object.attributes = { ExampleType: "unidentified" };
    if (index > 0) {
      object.parentId = model.objects[0]?.id;
    }
  });
}

function modelPaths(pkg: LoadedPackage): string[] {
  return pkg.manifest.files
    .filter((file) => file.role === "capture_model")
    .map((file) => file.path);
}

function withVersion11Models(pkg: LoadedPackage): LoadedPackage {
  return modelPaths(pkg).reduce((next, path) => withJson(next, path, toVersion11), pkg);
}

describe("capture model schema versions", () => {
  for (const fixture of readIndex().fixtures) {
    describe(fixture.name, () => {
      const base = loadGood(fixture.name);
      const pkg = withVersion11Models(base);
      const hubAddress = readTruth(fixture.name).hub.address;

      it("starts from 1.0.0 models", () => {
        for (const path of modelPaths(base)) {
          const result = parseByRole("capture_model", base.files.get(path) as Uint8Array);
          assert.ok(result.ok && result.value.kind === "capture_model");
          assert.equal(result.value.value.schemaVersion, "1.0.0");
        }
      });

      it("parses every 1.1.0 model with its new fields", () => {
        const paths = modelPaths(pkg);
        assert.ok(paths.length > 0);
        for (const path of paths) {
          const result = parseByRole("capture_model", pkg.files.get(path) as Uint8Array);
          assert.ok(result.ok, result.ok ? "" : result.reason);
          assert.equal(result.value.kind, "capture_model");
          if (result.value.kind !== "capture_model") {
            continue;
          }
          const model = result.value.value;
          assert.equal(model.schemaVersion, "1.1.0");
          assert.ok(model.rooms.every((room) => room.type && room.typeSource));
          assert.ok(model.doors.every((door) => typeof door.isOpen === "boolean"));
          assert.ok(model.objects.every((object) => object.attributes !== undefined));
        }
      });

      it("gets the same verdict as the 1.0.0 package", () => {
        const verdict = runChecks(pkg, hubAddress, OPTIONS);
        assert.equal(verdict.outcome, goodOutcome(fixture.name));
        assert.deepEqual(verdict, runChecks(base, hubAddress, OPTIONS));
      });
    });
  }

  it("blocks a 1.0.0 capture model that carries a 1.1.0 field", () => {
    const box = loadGood("box-room");
    const pkg = withJson<CaptureModel>(box, pathOf(box, "capture_model"), (model) => {
      model.doors[0]!.isOpen = true;
    });
    const verdict = runChecks(pkg, readTruth("box-room").hub.address);
    assert.equal(verdict.outcome, "blocked");
    const blockers = verdict.findings.filter((item) => item.severity === "blocker");
    assert.deepEqual(
      blockers.map((item) => item.ruleId),
      ["files.parseable"],
    );
    assert.match(blockers[0]?.measured ?? "", /\/doors\/0\/isOpen/);
  });
});
