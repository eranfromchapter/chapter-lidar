// F11 AC2: every generated CaptureModel and field-controls file validates against the F1
// schemas. The same goes for the capture record and manifest, and every package is a complete
// intake package that follows layout.json with a manifest that matches the bytes on disk.

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readdirSync } from "node:fs";
import { describe, it } from "node:test";
import {
  LAYOUT,
  RETIRED_ROLES,
  formatErrors,
  validateCaptureModel,
  validateCaptureRecord,
  validateFieldControls,
  validateManifest,
  type Role,
} from "@chapter/capture-contract";
import { DEFECT_IDS } from "../src/broken.js";
import { sampleSpecs } from "../src/generate.js";
import { buildPackage } from "../src/package.js";
import { SAMPLE_424_NAME } from "../src/sample424.js";
import { LEGACY_NAME, fixtureSpecs, legacySpecs } from "../src/shapes.js";
import {
  glbPositions,
  listFiles,
  loadBroken,
  loadGood,
  loadLegacy,
  loadSample,
  parseDxf,
  readGlb,
  readIndex,
  type LoadedFixture,
} from "./helpers.js";

const GOOD = ["box-room", "l-shaped-room", "two-room-apartment", "two-floor-house"];

/** Every role a v2 package holds: all roles except the retired spatial_report_pdf. */
const ALL_ROLES: Role[] = [
  "capture_record",
  "raw_roomplan_json",
  "raw_depth",
  "capture_model",
  "plan_dxf",
  "rooms_csv",
  "plan_pdf",
  "plan_png",
  "plan_svg",
  "mesh_glb",
  "mesh_obj",
  "mesh_mtl",
  "texture",
  "point_cloud_las",
  "photo",
  "field_controls",
];

function expectValid(result: { ok: boolean; errors: unknown[] }, label: string): void {
  assert.equal(result.ok, true, `${label}: ${formatErrors(result.errors as never)}`);
}

function validateContractFiles(fixture: LoadedFixture): void {
  expectValid(validateManifest(fixture.manifest), `${fixture.name} manifest`);
  expectValid(validateCaptureRecord(fixture.record), `${fixture.name} capture record`);
  expectValid(validateFieldControls(fixture.controls), `${fixture.name} field controls`);
  assert.equal(fixture.models.size, fixture.record.captures.length);
  for (const [captureId, model] of fixture.models) {
    expectValid(validateCaptureModel(model), `${fixture.name} capture model ${captureId}`);
  }
}

describe("generated fixtures validate against the contract schemas", () => {
  it("lists the four good fixtures, every broken fixture, the legacy package and the samples", () => {
    const index = readIndex();
    assert.equal(index.generatedFormatVersion, "1.1.0");
    assert.deepEqual(
      index.fixtures.map((fixture) => fixture.name),
      GOOD,
    );
    assert.deepEqual(
      index.broken.map((fixture) => fixture.defectId),
      [...DEFECT_IDS],
    );
    assert.deepEqual(
      index.legacy.map((fixture) => [fixture.name, fixture.legacy]),
      [[LEGACY_NAME, true]],
    );
    assert.deepEqual(
      index.samples.map((fixture) => fixture.name),
      [SAMPLE_424_NAME],
    );
    for (const fixture of [...index.fixtures, ...index.samples]) {
      assert.equal(fixture.legacy, undefined, fixture.name);
    }
  });

  it(`${LEGACY_NAME} and ${SAMPLE_424_NAME}: record, controls, models and manifest validate`, () => {
    validateContractFiles(loadLegacy(LEGACY_NAME));
    validateContractFiles(loadSample(SAMPLE_424_NAME));
  });

  for (const name of GOOD) {
    it(`${name}: record, controls, models and manifest validate`, () => {
      validateContractFiles(loadGood(name));
    });
  }

  for (const id of DEFECT_IDS) {
    it(`broken/${id}: contract files still validate (the defect is not a schema defect)`, () => {
      validateContractFiles(loadBroken(id));
    });
  }

  it("the two-floor house is one visit with two captures; the others have one", () => {
    for (const name of GOOD) {
      const fixture = loadGood(name);
      assert.equal(fixture.record.captures.length, name === "two-floor-house" ? 2 : 1, name);
      assert.equal(fixture.manifest.visitId, fixture.record.visitId);
      assert.equal(fixture.controls.visitId, fixture.record.visitId);
    }
  });
});

describe("every good fixture is a complete intake package", () => {
  for (const name of GOOD) {
    it(`${name}: layout, role coverage, fingerprints and cross references`, () => {
      const fixture = loadGood(name);
      const { manifest, record } = fixture;
      const folderOfRole = new Map<string, (typeof LAYOUT.folders)[number]>();
      for (const folder of LAYOUT.folders) {
        for (const role of folder.roles) {
          folderOfRole.set(role, folder);
        }
      }
      // Every file on disk is in the manifest, except the manifest itself.
      const onDisk = listFiles(fixture.root).filter(
        (path) => path !== fixture.manifestPath.replace(/^.*?\/package\//, ""),
      );
      assert.deepEqual(manifest.files.map((file) => file.path).sort(), onDisk.sort());
      assert.equal(new Set(manifest.files.map((file) => file.path)).size, manifest.files.length);
      for (const file of manifest.files) {
        const bytes = fixture.bytes(file.path);
        assert.equal(file.bytes, bytes.length, file.path);
        assert.equal(file.sha256, createHash("sha256").update(bytes).digest("hex"), file.path);
        assert.ok(bytes.length > 0, `${file.path} is empty`);
        const folder = folderOfRole.get(file.role);
        assert.ok(folder !== undefined, `${file.path}: role ${file.role} is in no folder`);
        const expectedPrefix = folder.pathTemplate
          .replace("{visitId}", manifest.visitId)
          .replace("{areaKey}", file.areaKey ?? "")
          .replace("{captureId}", file.captureId ?? "");
        assert.ok(
          file.path.startsWith(expectedPrefix),
          `${file.path} is not under ${expectedPrefix}`,
        );
        for (const source of file.derivedFrom) {
          assert.ok(
            manifest.files.some((other) => other.path === source),
            `${file.path} derivedFrom ${source}`,
          );
        }
      }
      // The manifest sits where layout.json says.
      assert.ok(
        fixture.manifestPath.endsWith(LAYOUT.manifestPath.replace("{visitId}", manifest.visitId)),
      );
      // Every role of the guide is present for every capture (photo: one per room).
      for (const capture of record.captures) {
        const own = manifest.files.filter((file) => file.captureId === capture.captureId);
        const roles = new Set(own.map((file) => file.role));
        for (const role of ALL_ROLES) {
          if (role === "capture_record" || role === "field_controls") {
            assert.equal(manifest.files.filter((file) => file.role === role).length, 1, role);
          } else {
            assert.ok(roles.has(role), `${name}/${capture.areaKey} lacks role ${role}`);
          }
        }
        const model = fixture.models.get(capture.captureId);
        assert.ok(model !== undefined);
        const photoRooms = own
          .filter((file) => file.role === "photo")
          .map((file) => file.photo?.room);
        assert.deepEqual(
          [...photoRooms].sort(),
          model.rooms.map((room) => room.label).sort(),
          "one photo per captured room",
        );
        for (const file of own) {
          assert.equal(file.areaKey, capture.areaKey);
        }
        // Model refs resolve to files of the same capture.
        for (const ref of model.refs) {
          const target = own.find((file) => file.path === ref.path);
          assert.ok(target !== undefined && target.role === ref.role, `${ref.path} (${ref.role})`);
        }
        // Control references point at registered captures.
      }
      for (const distance of fixture.controls.distances) {
        assert.ok(record.captures.some((c) => c.captureId === distance.capture.captureId));
      }
    });
  }

  it("v2 packages: manifest 1.1.0, the plan sheet as plan-sheet.pdf, no retired role", () => {
    for (const fixture of [...GOOD.map(loadGood), loadSample(SAMPLE_424_NAME)]) {
      assert.equal(fixture.manifest.schemaVersion, "1.1.0", fixture.name);
      for (const file of fixture.manifest.files) {
        assert.ok(!(RETIRED_ROLES as readonly string[]).includes(file.role), file.path);
        if (file.role === "plan_pdf") {
          assert.ok(file.path.endsWith("/plan-sheet.pdf"), file.path);
        }
        assert.ok(!file.path.endsWith("/plan.pdf") && !file.path.endsWith("/spatial-report.pdf"));
      }
    }
  });

  it("capture records are 1.1.0 exactly when a capture carries a compass reading", () => {
    const expected: Record<string, ["1.0.0" | "1.1.0", Array<Record<string, unknown>>]> = {
      "box-room": ["1.0.0", [{}]],
      "l-shaped-room": ["1.0.0", [{}]],
      "two-room-apartment": [
        "1.1.0",
        [
          {
            heading: 87.5,
            headingAccuracy: 12,
            headingSource: "magnetic",
            headingRecordedAt: "2026-10-17T14:02:23Z",
          },
        ],
      ],
      "two-floor-house": [
        "1.1.0",
        [
          {
            heading: 212.4,
            headingAccuracy: 8,
            headingSource: "true",
            headingRecordedAt: "2026-10-17T14:02:20Z",
          },
          // Scanned with the compass, no reading: the app says why.
          { headingIssue: "not_calibrated" },
        ],
      ],
    };
    const compassOf = (capture: Record<string, unknown>) =>
      Object.fromEntries(Object.entries(capture).filter(([key]) => key.startsWith("heading")));
    for (const name of GOOD) {
      const { record } = loadGood(name);
      const [version, captures] = expected[name] as (typeof expected)[string];
      assert.equal(record.schemaVersion, version, name);
      assert.deepEqual(
        record.captures.map((capture) => compassOf(capture as unknown as Record<string, unknown>)),
        captures,
        name,
      );
    }
  });

  it(`${LEGACY_NAME}: the box room as sealed before v2 (manifest 1.0.0, plan.pdf, spatial report)`, () => {
    const legacy = loadLegacy(LEGACY_NAME);
    const box = loadGood("box-room");
    assert.equal(legacy.manifest.schemaVersion, "1.0.0");
    assert.equal(legacy.record.schemaVersion, "1.0.0");
    assert.notEqual(legacy.manifest.visitId, box.manifest.visitId);
    const names = (fixture: typeof box) =>
      fixture.manifest.files.map((file) => `${file.role} ${file.path.split("/").pop() ?? ""}`);
    const legacyNames = names(legacy);
    assert.ok(legacyNames.includes("plan_pdf plan.pdf"));
    assert.ok(legacyNames.includes("spatial_report_pdf spatial-report.pdf"));
    assert.deepEqual(
      legacyNames
        .filter((name) => !name.startsWith("spatial_report_pdf"))
        .map((name) => name.replace("plan.pdf", "plan-sheet.pdf")),
      names(box),
    );
    for (const file of legacy.manifest.files) {
      assert.equal(file.photo?.directionSource, undefined);
    }
    // The same rooms, so the station judges it like the box room.
    assert.deepEqual(
      [...legacy.models.values()].map((model) => model.rooms),
      [...box.models.values()].map((model) => model.rooms),
    );
  });

  it("regenerating from the shapes gives the same manifest as the committed one", async () => {
    const specs = [
      ...fixtureSpecs().map((spec) => ({ spec, load: loadGood })),
      ...legacySpecs().map((spec) => ({ spec, load: loadLegacy })),
      ...sampleSpecs().map((spec) => ({ spec, load: loadSample })),
    ];
    for (const { spec, load } of specs) {
      const pkg = await buildPackage(spec);
      const committed = load(spec.name).manifest;
      assert.deepEqual(committed, pkg.manifest, spec.name);
    }
  });
});

describe("every role file is minimal but valid", () => {
  for (const name of GOOD) {
    it(`${name}: file contents parse`, async () => {
      const fixture = loadGood(name);
      for (const file of fixture.manifest.files) {
        const bytes = fixture.bytes(file.path);
        const text = bytes.toString("latin1");
        switch (file.role) {
          case "plan_dxf": {
            const dxf = parseDxf(text);
            assert.deepEqual(dxf.header.get("$ACADVER"), ["AC1027"]);
            assert.deepEqual(dxf.header.get("$INSUNITS"), ["4"]);
            const planLayers = [
              "A-WALL",
              "A-DOOR",
              "A-GLAZ",
              "A-OPEN",
              "A-AREA",
              "A-ANNO-TEXT",
              "A-FLOR-OBJ",
            ];
            for (const layer of planLayers) {
              assert.ok(dxf.layers.includes(layer), `layer ${layer}`);
            }
            for (const entity of dxf.entities) {
              assert.ok(["LINE", "ARC", "LWPOLYLINE", "TEXT"].includes(entity.type), entity.type);
              assert.ok(planLayers.includes(entity.layer), `${entity.type} on ${entity.layer}`);
            }
            assert.ok(text.trimEnd().endsWith("EOF"));
            break;
          }
          case "rooms_csv": {
            const lines = text.trimEnd().split("\n");
            assert.equal(lines[0]?.split(",")[0], "floor");
            assert.ok(lines.length >= 3);
            assert.ok(lines.at(-1)?.includes("not a verified construction quantity"));
            break;
          }
          case "plan_pdf":
          case "spatial_report_pdf": {
            assert.ok(text.startsWith("%PDF-1.7"));
            assert.ok(text.trimEnd().endsWith("%%EOF"));
            const model = fixture.models.get(file.captureId ?? "");
            assert.ok(model !== undefined);
            assert.ok(text.includes(fixture.record.address.formatted));
            assert.ok(text.includes(model.captureId));
            for (const room of model.rooms) {
              assert.ok(text.includes(`(${room.label}`) || text.includes(room.label), room.label);
            }
            const startxref = Number(/startxref\n(\d+)/.exec(text)?.[1]);
            assert.equal(text.slice(startxref, startxref + 4), "xref");
            break;
          }
          case "plan_png":
          case "texture": {
            assert.deepEqual(
              [...bytes.subarray(0, 8)],
              [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
            );
            assert.equal(text.slice(12, 16), "IHDR");
            assert.equal(text.slice(-8, -4), "IEND");
            break;
          }
          case "plan_svg": {
            assert.ok(text.startsWith("<?xml"));
            assert.ok(text.includes("<svg"));
            assert.ok(text.trimEnd().endsWith("</svg>"));
            const opens = (text.match(/<(?!\/|\?)[a-zA-Z]+/g) ?? []).length;
            const closes = (text.match(/<\/[a-zA-Z]+>/g) ?? []).length;
            const selfClosing = (text.match(/\/>/g) ?? []).length;
            assert.equal(opens, closes + selfClosing, "balanced tags");
            break;
          }
          case "mesh_glb": {
            const { json, bin } = readGlb(bytes);
            assert.ok(bin !== undefined, "BIN chunk present");
            assert.equal((json.asset as { version: string }).version, "2.0");
            const validator = (await import("gltf-validator")).default;
            const report = await validator.validateBytes(new Uint8Array(bytes), { maxIssues: 0 });
            assert.equal(report.issues.numErrors, 0, JSON.stringify(report.issues.messages));
            glbPositions(bytes);
            break;
          }
          case "mesh_obj": {
            assert.ok(/^mtllib mesh\.mtl$/m.test(text));
            assert.ok(/^v [-\d.]+ [-\d.]+ [-\d.]+$/m.test(text));
            assert.ok(/^f \d+\/\d+\/\d+ \d+\/\d+\/\d+ \d+\/\d+\/\d+$/m.test(text));
            break;
          }
          case "mesh_mtl": {
            assert.ok(/^newmtl /m.test(text));
            const texture = /^map_Kd (.+)$/m.exec(text)?.[1];
            assert.ok(texture !== undefined);
            assert.ok(
              fixture.manifest.files.some(
                (other) =>
                  other.role === "texture" &&
                  other.path.endsWith(`/${texture}`) &&
                  other.captureId === file.captureId,
              ),
              "MTL texture exists in the package",
            );
            break;
          }
          case "point_cloud_las": {
            assert.equal(text.slice(0, 4), "LASF");
            assert.equal(bytes[24], 1);
            assert.equal(bytes[25], 4);
            assert.equal(bytes[104], 7);
            const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
            assert.equal(view.getFloat64(131, true), 0.001);
            assert.equal(view.getUint16(94, true), 375);
            const count = Number(view.getBigUint64(247, true));
            assert.equal(bytes.length, 375 + count * 36);
            break;
          }
          case "photo": {
            assert.deepEqual([...bytes.subarray(0, 2)], [0xff, 0xd8]);
            assert.deepEqual([...bytes.subarray(-2)], [0xff, 0xd9]);
            // Walk the marker segments: only JFIF (APP0), no EXIF (APP1) and so no GPS data.
            const markers: number[] = [];
            let offset = 2;
            while (offset < bytes.length) {
              const marker = bytes[offset + 1] as number;
              markers.push(marker);
              if (marker === 0xda) {
                break;
              }
              offset += 2 + (((bytes[offset + 2] as number) << 8) | (bytes[offset + 3] as number));
            }
            assert.ok(markers.includes(0xe0), "JFIF header");
            assert.ok(!markers.includes(0xe1), "no EXIF segment");
            assert.ok(!text.includes("Exif") && !text.includes("GPS"));
            break;
          }
          case "raw_depth": {
            assert.equal(text.slice(0, 4), "CHDS");
            break;
          }
          default:
            break;
        }
      }
    });
  }
});

describe("fixture folder", () => {
  it("only contains the expected top-level entries", () => {
    const entries = readdirSync(new URL("../../generated", import.meta.url)).sort();
    assert.deepEqual(entries, [
      "box-room",
      "broken",
      "index.json",
      "l-shaped-room",
      "legacy-1.0.0",
      "roomplan-only",
      "sample-424",
      "two-floor-house",
      "two-room-apartment",
    ]);
  });
});
