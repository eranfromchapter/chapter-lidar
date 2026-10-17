// F11 AC4: each broken fixture is labelled with the single defect it contains. Every broken
// fixture is the box-room good fixture with exactly one mutated file (defect.json says which),
// and the manifest still matches the bytes on disk.

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, it } from "node:test";
import type { CaptureModel, FieldControls } from "@chapter/capture-contract";
import { CONTROL_FACTOR, DEFECT_IDS, INCHES_PER_METRE, type DefectJson } from "../src/broken.js";
import { OTHER_PLACEHOLDER_ADDRESS, PLACEHOLDER_ADDRESS } from "../src/spec.js";
import {
  generatedDir,
  glbPositions,
  listFiles,
  loadBroken,
  loadGood,
  readGlb,
  readIndex,
  readJson,
  type LoadedFixture,
} from "./helpers.js";

function sha(bytes: Buffer): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function defectOf(id: string): DefectJson {
  return readJson<DefectJson>(join(generatedDir, "broken", id, "defect.json"));
}

/** Paths whose bytes differ from the base package, plus added and removed paths. */
function diffPaths(
  base: LoadedFixture,
  broken: LoadedFixture,
): { changed: string[]; added: string[]; removed: string[] } {
  const baseFiles = listFiles(base.root);
  const brokenFiles = listFiles(broken.root);
  const manifestName = (fixture: LoadedFixture) =>
    `Source Register/${fixture.manifest.visitId}/manifest.json`;
  const skip = (fixture: LoadedFixture, path: string) => path === manifestName(fixture);
  const changed = baseFiles.filter(
    (path) =>
      !skip(base, path) &&
      brokenFiles.includes(path) &&
      !base.bytes(path).equals(broken.bytes(path)),
  );
  return {
    changed,
    added: brokenFiles.filter((path) => !baseFiles.includes(path)),
    removed: baseFiles.filter((path) => !brokenFiles.includes(path)),
  };
}

const base = loadGood("box-room");
const baseModel = [...base.models.values()][0] as CaptureModel;

describe("broken fixtures", () => {
  it("there is one broken fixture per listed defect and nothing else", () => {
    assert.deepEqual(
      readIndex().broken.map((entry) => entry.defectId),
      [...DEFECT_IDS],
    );
    assert.deepEqual(
      [
        "empty-file",
        "wrong-address",
        "inches-as-metres",
        "z-up-mesh",
        "missing-gltf-bin",
        "las-bad-header",
        "dimensions-3pct-off",
      ],
      [...DEFECT_IDS],
    );
    assert.deepEqual(
      listFiles(join(generatedDir, "broken"))
        .map((path) => path.split("/")[0])
        .filter((v, i, all) => all.indexOf(v) === i),
      [...DEFECT_IDS].sort(),
    );
  });

  for (const id of DEFECT_IDS) {
    describe(id, () => {
      const broken = loadBroken(id);
      const defect = defectOf(id);

      it("is labelled with exactly one defect and names the one file it changed", () => {
        assert.equal(defect.defectId, id);
        assert.equal(defect.baseFixture, "box-room");
        assert.ok(defect.title.length > 0 && defect.mutation.length > 0);
        assert.deepEqual(Object.keys(defect).sort(), [
          "affectedFile",
          "baseFixture",
          "defectId",
          "details",
          "mutation",
          "role",
          "title",
        ]);
        assert.ok(existsSync(broken.path(defect.affectedFile)), `${defect.affectedFile} exists`);
        const entry = broken.manifest.files.find((file) => file.path === defect.affectedFile);
        assert.equal(entry?.role, defect.role);
        const { changed, added, removed } = diffPaths(base, broken);
        assert.deepEqual(changed, [defect.affectedFile], "exactly one file changed");
        assert.deepEqual(added, []);
        assert.deepEqual(removed, []);
      });

      it("keeps the manifest consistent with the bytes on disk", () => {
        assert.notEqual(broken.manifest.packageId, base.manifest.packageId);
        assert.equal(broken.manifest.visitId, base.manifest.visitId);
        for (const file of broken.manifest.files) {
          const bytes = broken.bytes(file.path);
          assert.equal(file.bytes, bytes.length, file.path);
          assert.equal(file.sha256, sha(bytes), file.path);
        }
        const differing = broken.manifest.files.filter((file, i) => {
          const baseFile = base.manifest.files[i];
          return baseFile?.sha256 !== file.sha256 || baseFile.path !== file.path;
        });
        assert.deepEqual(
          differing.map((file) => file.path),
          [defect.affectedFile],
        );
      });
    });
  }

  it("empty-file: the plan DXF is zero bytes", () => {
    const broken = loadBroken("empty-file");
    const defect = defectOf("empty-file");
    assert.equal(broken.bytes(defect.affectedFile).length, 0);
    assert.equal(defect.role, "plan_dxf");
    const entry = broken.manifest.files.find((file) => file.path === defect.affectedFile);
    assert.equal(entry?.bytes, 0);
    assert.equal(entry?.sha256, sha(Buffer.alloc(0)));
    // Everything else is non-empty.
    for (const file of broken.manifest.files.filter((f) => f.path !== defect.affectedFile)) {
      assert.ok(file.bytes > 0, file.path);
    }
  });

  it("wrong-address: the capture record address differs from the HUB address in the details", () => {
    const broken = loadBroken("wrong-address");
    const defect = defectOf("wrong-address");
    assert.equal(defect.details.hubAddress, PLACEHOLDER_ADDRESS);
    assert.equal(defect.details.hubAddress, base.truth?.hub.address);
    assert.equal(defect.details.recordedAddress, OTHER_PLACEHOLDER_ADDRESS);
    assert.equal(broken.record.address.formatted, OTHER_PLACEHOLDER_ADDRESS);
    assert.notEqual(broken.record.address.formatted, defect.details.hubAddress);
    assert.deepEqual(
      { ...broken.record, address: { ...broken.record.address, formatted: PLACEHOLDER_ADDRESS } },
      base.record,
    );
  });

  it("inches-as-metres: every metre field holds the inch number", () => {
    const broken = loadBroken("inches-as-metres");
    const model = [...broken.models.values()][0] as CaptureModel;
    const defect = defectOf("inches-as-metres");
    assert.ok(Math.abs((defect.details.factor as number) - INCHES_PER_METRE) < 1e-5);
    const near = (actual: number, expected: number) =>
      assert.ok(
        Math.abs(actual - expected * INCHES_PER_METRE) < 2e-6,
        `${actual} vs ${expected} m as inches`,
      );
    const first = model.rooms[0];
    const original = baseModel.rooms[0];
    assert.ok(first !== undefined && original !== undefined);
    // 4.000 m written as 157.48 and 2.700 m as 106.299.
    assert.ok(Math.abs((first.polygon[2]?.[0] ?? 0) - 157.480315) < 1e-5);
    near(first.heightM, original.heightM);
    first.polygon.forEach((point, i) =>
      point.forEach((v, a) => near(v, original.polygon[i]?.[a] as number)),
    );
    model.walls.forEach((wall, i) => {
      near(wall.heightM, baseModel.walls[i]?.heightM as number);
      wall.end.forEach((v, a) => near(v, baseModel.walls[i]?.end[a] as number));
    });
    model.doors.forEach((door, i) => near(door.widthM, baseModel.doors[i]?.widthM as number));
    // Nothing but lengths changed: ids, labels and rotations are the same.
    assert.deepEqual(
      model.objects.map((o) => [o.id, o.category, o.box.rotation]),
      baseModel.objects.map((o) => [o.id, o.category, o.box.rotation]),
    );
    assert.equal(model.areaKey, baseModel.areaKey);
    assert.equal(model.coordinateSystem.units, "m");
  });

  it("z-up-mesh: the GLB mesh is the good mesh turned so that height runs along Z", () => {
    const broken = loadBroken("z-up-mesh");
    const defect = defectOf("z-up-mesh");
    const good = glbPositions(base.bytes(defect.affectedFile));
    const bad = glbPositions(broken.bytes(defect.affectedFile));
    assert.equal(bad.positions.length, good.positions.length);
    for (let i = 0; i < good.positions.length; i += 3) {
      const [x, y, z] = [
        good.positions[i],
        good.positions[i + 1],
        good.positions[i + 2],
      ] as number[];
      assert.ok(Math.abs((bad.positions[i] as number) - (x as number)) < 1e-6);
      assert.ok(Math.abs((bad.positions[i + 1] as number) + (z as number)) < 1e-6);
      assert.ok(Math.abs((bad.positions[i + 2] as number) - (y as number)) < 1e-6);
    }
    // Height (2.7 m) is now the Z extent; the Y extent is the room depth (3.0 m).
    assert.ok(Math.abs((bad.max[2] as number) - 2.7) < 1e-5);
    assert.ok(Math.abs((bad.max[1] as number) - (bad.min[1] as number) - 3) < 1e-5);
    assert.deepEqual(defect.details, { vertical: "+Z", expected: "+Y" });
  });

  it("missing-gltf-bin: the GLB's buffer is an external mesh.bin that is not in the package", async () => {
    const broken = loadBroken("missing-gltf-bin");
    const defect = defectOf("missing-gltf-bin");
    const { json, bin } = readGlb(broken.bytes(defect.affectedFile));
    assert.equal(bin, undefined, "no BIN chunk");
    const buffers = json.buffers as Array<{ uri?: string }>;
    assert.equal(buffers[0]?.uri, "mesh.bin");
    assert.ok(!existsSync(join(dirname(broken.path(defect.affectedFile)), "mesh.bin")));
    assert.ok(!broken.manifest.files.some((file) => file.path.endsWith("mesh.bin")));
    const validator = (await import("gltf-validator")).default;
    const dir = dirname(broken.path(defect.affectedFile));
    const report = await validator.validateBytes(
      new Uint8Array(broken.bytes(defect.affectedFile)),
      {
        maxIssues: 0,
        externalResourceFunction: async (uri: string) =>
          new Uint8Array(readFileSync(join(dir, uri))),
      },
    );
    assert.ok(report.issues.numErrors > 0, "the validator reports the unresolved buffer");
    const goodReport = await validator.validateBytes(
      new Uint8Array(base.bytes(defect.affectedFile)),
      { maxIssues: 0 },
    );
    assert.equal(goodReport.issues.numErrors, 0);
  });

  it("las-bad-header: only the header point count is wrong", () => {
    const broken = loadBroken("las-bad-header");
    const defect = defectOf("las-bad-header");
    const good = base.bytes(defect.affectedFile);
    const bad = broken.bytes(defect.affectedFile);
    assert.equal(bad.length, good.length);
    const records = (good.length - 375) / 36;
    assert.equal(Number(good.readBigUInt64LE(247)), records, "the good header matches its data");
    assert.equal(Number(bad.readBigUInt64LE(247)), records + 1000);
    assert.equal(defect.details.actualPointCount, records);
    assert.equal(defect.details.headerPointCount, records + 1000);
    const differing = [...bad.keys()].filter((i) => bad[i] !== good[i]);
    assert.ok(
      differing.every((i) => i >= 247 && i < 263),
      "only the point count bytes changed",
    );
    assert.equal(bad.subarray(0, 4).toString("latin1"), "LASF");
  });

  it("dimensions-3pct-off: the long distances of the controls are 3% short of truth", () => {
    const broken = loadBroken("dimensions-3pct-off");
    const defect = defectOf("dimensions-3pct-off");
    assert.equal(defect.details.factor, CONTROL_FACTOR);
    assert.equal(broken.controls.distances.length, base.controls.distances.length);
    broken.controls.distances.forEach((distance, i) => {
      const truth = base.controls.distances[i]?.measurement.valueMm as number;
      assert.ok(Math.abs(distance.measurement.valueMm - truth * 0.97) < 1e-3);
      assert.equal(distance.measurement.enteredUnit, "mm");
      assert.equal(Number(distance.measurement.enteredText), distance.measurement.valueMm);
      const offTruth = (truth - distance.measurement.valueMm) / truth;
      assert.ok(Math.abs(offTruth - 0.03) < 1e-6, "3% off the true length");
    });
    // The rest of the controls are untouched.
    const rest = (controls: FieldControls) => ({ ...controls, distances: [] });
    assert.deepEqual(rest(broken.controls), rest(base.controls));
    // The scan geometry is the good geometry.
    assert.deepEqual([...broken.models.values()][0], baseModel);
  });
});
