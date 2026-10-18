// Capture model 1.1.0 (docs/floorplan-report-plan.md, phase 2): readers accept 1.0.0 and 1.1.0;
// the fields added in 1.1.0 are optional and only allowed in a 1.1.0 document.

import assert from "node:assert/strict";
import { join } from "node:path";
import { describe, it } from "node:test";
import { formatErrors, validateCaptureModel, type CaptureModel } from "../src/index.js";
import { examplesDir, readJson } from "./paths.js";

const floor1 = readJson(
  join(examplesDir, "capture-model", "valid", "floor-1.json"),
) as CaptureModel;
const floor2 = readJson(
  join(examplesDir, "capture-model", "valid", "floor-2.json"),
) as CaptureModel;

function changed(model: CaptureModel, change: (copy: CaptureModel) => void): CaptureModel {
  const copy = structuredClone(model);
  change(copy);
  return copy;
}

function assertValid(model: unknown): void {
  const result = validateCaptureModel(model);
  assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
}

/** Fails unless the model is rejected with an error at each pointer (and possibly at the root). */
function assertRejectedAt(model: unknown, pointers: string[]): void {
  const result = validateCaptureModel(model);
  assert.equal(result.ok, false, "expected the model to fail the schema");
  const at = new Set(result.errors.map((error) => error.instancePath));
  for (const pointer of pointers) {
    assert.ok(at.has(pointer), `no error at ${pointer}:\n${formatErrors(result.errors)}`);
  }
  const stray = [...at].filter((pointer) => pointer !== "" && !pointers.includes(pointer));
  assert.deepEqual(stray, [], formatErrors(result.errors));
}

describe("capture model schema versions", () => {
  it("accepts 1.0.0 and 1.1.0", () => {
    assert.equal(floor1.schemaVersion, "1.0.0");
    assert.equal(floor2.schemaVersion, "1.1.0");
    assertValid(floor1);
    assertValid(floor2);
  });

  it("accepts a 1.0.0 document relabelled 1.1.0, so writers can always write 1.1.0", () => {
    assertValid(changed(floor1, (model) => (model.schemaVersion = "1.1.0")));
  });

  it("rejects any other version", () => {
    for (const version of ["1.2.0", "2.0.0", "1.0", ""]) {
      const model = { ...floor1, schemaVersion: version };
      assertRejectedAt(model, ["/schemaVersion"]);
    }
  });

  it("rejects each 1.1.0 field in a 1.0.0 document, at the field", () => {
    assertRejectedAt(
      changed(floor2, (model) => (model.schemaVersion = "1.0.0")),
      [
        "/rooms/0/type",
        "/rooms/0/typeSource",
        "/rooms/1/type",
        "/rooms/1/typeSource",
        "/doors/0/isOpen",
        "/doors/1/isOpen",
        "/objects/1/attributes",
        "/objects/2/attributes",
        "/objects/3/parentId",
      ],
    );
    assertRejectedAt(
      changed(floor1, (model) => (model.doors[0]!.isOpen = true)),
      ["/doors/0/isOpen"],
    );
  });
});

describe("capture model 1.1.0 fields", () => {
  it("allows isOpen on doors only", () => {
    assertRejectedAt(
      changed(floor2, (model) => (model.windows[0]!.isOpen = false)),
      ["/windows/0"],
    );
    assertRejectedAt(
      changed(floor2, (model) => {
        model.openings = [
          {
            id: "f2-opening-1",
            wallId: "f2-wall-5",
            offsetM: 1,
            bottomM: 0,
            widthM: 1,
            heightM: 2.1,
          },
        ];
        model.openings[0]!.isOpen = true;
      }),
      ["/openings/0"],
    );
  });

  it("requires type and typeSource together", () => {
    assertRejectedAt(
      changed(floor2, (model) => delete model.rooms[0]!.typeSource),
      ["/rooms/0"],
    );
    assertRejectedAt(
      changed(floor2, (model) => delete model.rooms[0]!.type),
      ["/rooms/0"],
    );
    assertValid(
      changed(floor2, (model) => {
        delete model.rooms[0]!.type;
        delete model.rooms[0]!.typeSource;
      }),
    );
  });

  it("rejects a room type outside the closed list", () => {
    const model = changed(floor2, (copy) => {
      (copy.rooms[0] as { type: string }).type = "garage";
    });
    assertRejectedAt(model, ["/rooms/0/type"]);
  });

  it("keeps object attributes as strings", () => {
    const model = changed(floor2, (copy) => {
      (copy.objects[1]!.attributes as Record<string, unknown>)["ChairType"] = 3;
    });
    assertRejectedAt(model, ["/objects/1/attributes/ChairType"]);
  });
});
