// Synthetic single-change variants of the good fixtures, each re-fingerprinted unless the change
// is the fingerprint itself. Used to drive every rule through its failing paths.

import type { CaptureModel, CaptureRecord, FieldControls } from "@chapter/capture-contract";
import type { LoadedPackage } from "../src/types.js";
import {
  jsonOf,
  loadGood,
  pathOf,
  rewriteGlbJson,
  textOf,
  withFile,
  withJson,
  withManifest,
  withoutFile,
  withText,
  withUnlistedFile,
} from "./helpers.js";

export interface Variant {
  name: string;
  pkg: LoadedPackage;
  hubAddress?: string;
}

const box = loadGood("box-room");
const house = loadGood("two-floor-house");
/** Capture record 1.1.0 with an approximate compass reading (magnetic, ±12°). */
const apartment = loadGood("two-room-apartment");
const p = (role: string, pkg: LoadedPackage = box) => pathOf(pkg, role);

function lasWithMaxZ(pkg: LoadedPackage, delta: number): LoadedPackage {
  const path = p("point_cloud_las", pkg);
  const bytes = new Uint8Array(pkg.files.get(path) as Uint8Array);
  const view = new DataView(bytes.buffer);
  view.setFloat64(211, view.getFloat64(211, true) + delta, true);
  return withFile(pkg, path, bytes);
}

function dxfWithEntities(pkg: LoadedPackage, extra: string): LoadedPackage {
  const path = p("plan_dxf", pkg);
  const text = textOf(pkg, path).replace("  2\nENTITIES\n", `  2\nENTITIES\n${extra}`);
  return withText(pkg, path, text);
}

export function variants(): Variant[] {
  const list: Variant[] = [];
  const add = (name: string, pkg: LoadedPackage, hubAddress?: string) =>
    list.push(hubAddress === undefined ? { name, pkg } : { name, pkg, hubAddress });

  // Check 1
  add(
    "fingerprint mismatch",
    withFile(box, p("plan_svg"), new TextEncoder().encode("<svg></svg>"), {
      keepFingerprint: true,
    }),
  );
  add("listed file missing", withoutFile(box, p("plan_png"), { keepManifestEntry: true }));
  add("unlisted file", withUnlistedFile(box, "Working Conversions/notes.txt", new Uint8Array([1])));
  // Check 2
  add(
    "capture model not valid",
    withJson<Record<string, unknown>>(box, p("capture_model"), (model) => {
      delete model.rooms;
    }),
  );
  add("truncated pdf", withText(box, p("plan_pdf"), "%PDF-1.7\n1 0 obj\n"));
  add("csv ragged row", withText(box, p("rooms_csv"), "a,b,c\n1,2\n"));
  add("photo not an image", withText(box, pathOf(box, "photo"), "not a photo"));
  // Check 3
  add("hub address empty", box, "  ");
  add(
    "capture model of another capture",
    withJson<CaptureModel>(box, p("capture_model"), (model) => {
      model.areaKey = "floor-9";
    }),
  );
  // Check 4
  add("no field controls file", withoutFile(box, p("field_controls")));
  add(
    "no distance controls",
    withJson<FieldControls>(box, p("field_controls"), (controls) => {
      controls.distances = [];
    }),
  );
  add(
    "distance 2% off",
    withJson<FieldControls>(box, p("field_controls"), (controls) => {
      const a = controls.distances[0] as FieldControls["distances"][number];
      a.measurement.valueMm = 3920;
    }),
  );
  // Check 5
  add(
    "dxf in inches",
    withText(
      box,
      p("plan_dxf"),
      textOf(box, p("plan_dxf")).replace("$INSUNITS\n 70\n4\n", "$INSUNITS\n 70\n1\n"),
    ),
  );
  add("las z extent too tall", lasWithMaxZ(box, 1.0));
  add(
    "glb rotated z-up by its node",
    withFile(
      box,
      p("mesh_glb"),
      rewriteGlbJson(box.files.get(p("mesh_glb")) as Uint8Array, (json) => {
        const nodes = json.nodes as Array<Record<string, unknown>>;
        (nodes[0] as Record<string, unknown>).rotation = [Math.SQRT1_2, 0, 0, Math.SQRT1_2];
      }),
    ),
  );
  // Check 5b (every state of the reading: compass.test.ts)
  add(
    "compass reading rejected by the phone",
    withJson<CaptureRecord>(apartment, p("capture_record", apartment), (record) => {
      const capture = record.captures[0] as CaptureRecord["captures"][number];
      delete capture.heading;
      delete capture.headingAccuracy;
      delete capture.headingSource;
      delete capture.headingRecordedAt;
      capture.headingIssue = "rejected";
    }),
  );
  add(
    "compass accuracy over 30 degrees",
    withJson<CaptureRecord>(apartment, p("capture_record", apartment), (record) => {
      (record.captures[0] as CaptureRecord["captures"][number]).headingAccuracy = 31;
    }),
  );
  // No compass fields at all in a 1.1.0 record: a capture scanned before the app read the compass
  // (carried over from an older revision), not graded (Q-B).
  add(
    "capture record 1.1.0 with a capture scanned before the compass",
    withJson<CaptureRecord>(box, p("capture_record"), (record) => {
      record.schemaVersion = "1.1.0";
    }),
  );
  // Check 6
  add("obj material library missing", withoutFile(box, p("mesh_mtl")));
  add("mtl texture missing", withoutFile(box, p("texture")));
  add(
    "gltf image missing",
    withFile(
      box,
      p("mesh_glb"),
      rewriteGlbJson(box.files.get(p("mesh_glb")) as Uint8Array, (json) => {
        json.images = [{ uri: "missing-texture.png" }];
      }),
    ),
  );
  // Check 7
  add(
    "dxf with mesh and points",
    dxfWithEntities(
      box,
      "  0\n3DFACE\n  8\nA-WALL\n 10\n0\n 20\n0\n 30\n0\n  0\nPOINT\n  8\n0\n 10\n1\n 20\n1\n 30\n0\n",
    ),
  );
  // Check 8 is driven by las z extent too tall (extents) and the las-bad-header fixture.
  // Check 9
  add("room photo missing", withoutFile(box, pathOf(box, "photo")));
  add(
    "omitted and inaccessible rooms",
    withJson<CaptureRecord>(box, p("capture_record"), (record) => {
      const capture = record.captures[0];
      capture.omittedRooms = [{ name: "Closet", reason: "owner request" }];
      capture.inaccessibleRooms = [{ name: "Boiler room" }];
    }),
  );
  // Check 10
  add(
    "implausible ceiling and door",
    withJson<CaptureModel>(box, p("capture_model"), (model) => {
      (model.rooms[0] as CaptureModel["rooms"][number]).heightM = 1.9;
      (model.doors[0] as CaptureModel["doors"][number]).widthM = 0.5;
    }),
  );
  // Check 11
  add(
    "house with one shared landmark",
    withJson<FieldControls>(house, p("field_controls", house), (controls) => {
      controls.landmarks = controls.landmarks.slice(0, 1);
    }),
  );
  // Check 12
  add(
    "field controls derived from the scan",
    withManifest(box, (manifest) => {
      const entry = manifest.files.find((file) => file.role === "field_controls");
      if (entry !== undefined) {
        entry.derivedFrom = [p("capture_model")];
      }
    }),
  );
  return list;
}

/** The capture record of the box room, for tests that need its ids. */
export function boxRecord(): CaptureRecord {
  return jsonOf<CaptureRecord>(box, p("capture_record"));
}
