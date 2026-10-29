---
id: F14
title: Sketch capture (no LiDAR)
depends_on: [F1, F2, F3, F4, F5, F6, F8]
owns: [ios/Packages/SketchCapture/**, contract/schema/sketch-measurements.schema.json, station/checks/src/checks/sketch.ts]
reads: [contract/**, ios/Packages/CaptureCore/Sources/CaptureModelMapping/**, ios/Packages/PlanExport/**, ios/Packages/MeshExport/**, ios/Packages/PackageKit/**, ios/App/AppCore/**, station/checks/**, docs/waves/design/DESIGN.md]
risk: [data]
steps: [F14.1, F14.2, F14.3, F14.4, F14.5]
---

# F14 Sketch capture (no LiDAR)

## Summary

A user whose iPhone has no LiDAR scanner (anything that is not a Pro) cannot run RoomPlan, so
Chapter Capture refuses to scan on it (`DeviceGate`). Sketch capture is the second way in: the
user photographs or imports a hand sketch or an existing floor plan, enters measurements in a
guided flow, and the app builds the same capture model (`capture-model.json`, contract 1.1), the
colour Floorplan, the v2 plan sheet, the DXF/CSV/SVG/PNG exports, a 3D model (GLB/OBJ extruded
from the walls and the ceiling height), and seals the same package through `PackageKit` and
`StationClient`. The station runs its checks on it and writes the spatial report.

Part 1 of this spec is the measurement study the owner asked for before anything is built: how
many measurements a sketch needs before the model is geometrically complete, and what happens
when fewer are given. Part 2 is the design built behind it.

## Part 1. Measurement study

### 1.1 The question, answered plainly

**Is one wall, one window and one door enough? No.**

One wall length fixes the scale of the sketch in one direction only. A hand sketch is not drawn to
scale: its proportions are typically off by 10 to 30 percent, so every other wall "measured" by
applying that one scale to the drawing is a guess, not a measurement. One window and one door give
the sizes of those two openings and nothing about the room's second dimension, the ceiling, the
other openings, or where along the wall each opening sits.

The smallest set that gives a geometrically complete model of a plain rectangular room is:

- two wall lengths, of two walls that meet at a corner (the width and the depth);
- the ceiling height;
- for every door and opening: its width, and its distance from the nearest corner;
- for every window: its width, its sill height and its height, and its distance from the nearest
  corner.

That is the "required" column of the table in 1.6. With it the room, its openings and its 3D
extrusion are fully determined under one assumption: that every corner is square. Everything
else (the other two walls, a diagonal, door heights) is redundant and is used to check the
required set, not to build the model.

A room that is not a plain rectangle needs more: an L-shaped room needs four of its six walls; a
room with a corner that is not square needs the diagonal across that corner. The rule is in 1.3.

With fewer measurements than the required set the app still builds a model, but it is marked
`limited`: the unmeasured walls are drawn from the sketch's proportions (or from the measured
opposite wall) and carry `confidence: low` in the capture model, and the station's verdict names
them (1.7).

### 1.2 What the sketch alone gives, and what it cannot

A sketch, a photo of one, or a scan of an existing plan carries **topology**:

| From the sketch                        | Reliability                                                                 |
| -------------------------------------- | --------------------------------------------------------------------------- |
| Room count and names                   | reliable                                                                    |
| Which rooms share a wall (adjacency)   | reliable                                                                    |
| The order of the walls around a room   | reliable                                                                    |
| Which walls are exterior               | reliable when drawn; otherwise asked                                        |
| Which wall each door or window is in   | reliable                                                                    |
| The order of openings along a wall     | reliable                                                                    |
| Rough position of an opening on a wall | ±20 to 30 % of the wall on a hand sketch; ±2 to 5 % on a scaled plan        |
| Rough proportions of the rooms         | ±10 to 30 % on a hand sketch; ±2 to 5 % on a scaled plan with a scale bar   |
| Whether a corner is "meant" square     | usually: a sketch draws corners square unless the drafter marks otherwise   |

It carries **no metric information** that can be trusted for a plan:

| Must be measured                               | Why the sketch cannot give it                                              |
| ---------------------------------------------- | -------------------------------------------------------------------------- |
| Scale                                          | nothing in a hand sketch is to scale; a scanned plan's scale bar is unverified |
| Each wall length                               | proportion is not a measurement                                            |
| Any angle that is not 90°                      | a sketch cannot show 87° from 90°; it needs a diagonal or an angle         |
| Ceiling height                                 | a plan has no height at all                                                |
| Opening width, height, sill and head height    | not drawn, or drawn symbolically                                           |
| Position of an opening (distance from a corner) | the sketch gives the order along the wall, not the distance                |
| Wall thickness                                 | a sketch draws a line; the LiDAR path also assumes it (4.5 in interior, 6 in exterior, `docs/floorplan-report-plan.md`) |

An existing plan with printed dimensions is the one exception: when the dimensions are printed, the
operator types them from the plan and marks the source as `existing_plan`; they are still entered
measurements, not scan evidence.

### 1.3 How many measurements a room needs (degrees of freedom)

A room outline with `n` corners has `2n` coordinates. Three of them are the position and rotation
of the room on the sheet, which measurements cannot and need not fix, so the **shape** has `2n − 3`
unknowns. Each measurement is one equation.

**Rectilinear room (every corner square).** The `n` right angles are `n − 1` independent equations
(the last angle follows from the others). `2n − 3 − (n − 1) = n − 2` wall lengths are needed.

| Shape                 | Corners `n` | Walls needed (`n − 2`) | Redundant if all walls measured |
| --------------------- | ----------- | ---------------------- | ------------------------------- |
| Rectangle             | 4           | 2 (adjacent)           | 2 (one per axis: closure)       |
| L-shape               | 6           | 4                      | 2                               |
| U-shape or T-shape    | 8           | 6                      | 2                               |
| Rectilinear, general  | n           | n − 2                  | 2                               |

The two redundant walls are the closure equations: along each axis the lengths going one way must
add up to the lengths coming back. They are what makes a closure check possible (1.4), which is
why the recommended set is **every wall**, not the minimum `n − 2`.

Which `n − 2` walls? Any set that leaves one wall unmeasured on each axis. The guided flow asks
for every wall and marks what is missing; the solver fills one unknown per axis from closure and
refuses to guess when two walls on the same axis are both missing (then both are estimated, 1.5).

**Room with corners that are not square.** Drop the angle equations for those corners: each such
corner adds one unknown back. A polygon is rigid when, in addition to its `n` sides, `n − 3`
diagonals (or angles) are known: a triangulation. In practice a room has one or two off-square
corners (a bay, a splayed entry wall), and each needs **one diagonal** measured across it
(corner-to-corner through the room) or the angle itself. The flow asks "Are all corners square?";
"No" opens the corner picker and asks for one diagonal per unsquare corner.

**Several rooms.** Each room is solved on its own, then the rooms are placed by their shared
walls: the sketch says which wall of room A is which wall of room B, and the measured wall lengths
say where along that wall room B starts. Rooms that are fully measured need nothing more. Two
rooms that share a wall but whose common wall is unmeasured in both are placed by the sketch's
proportion and flagged. Exterior overall dimensions (the field controls' axis A and B distances)
are the cross-check for the whole floor and are entered on the Field controls screen as today.

**Heights.** One ceiling height per room. In a house with one ceiling height, one measurement
applied to every room is complete; a room with a different ceiling is asked for its own. Without
any ceiling height the model assumes 2.44 m (8 ft) and the capture is `limited`.

**Openings.** A door is placed by its wall, its width and its distance from the nearest corner
(two numbers after the wall is known); its height defaults to 2.03 m (6 ft 8 in) unless measured.
A window needs the same two plus its sill height and its height (four numbers); without them the
sill defaults to 0.91 m (3 ft) and the height to 1.22 m (4 ft), both flagged. An opening without a
door (passage, arch) is a door with the full height of the wall unless measured.

### 1.4 Closure error

When a rectilinear room has every wall measured, each axis has one closure residual:
`Σ(lengths going +x) − Σ(lengths going −x)`, and the same for z.

- A residual within the tolerance `max(1 % of the axis extent, 25.4 mm)` (the station's own scale
  tolerance, `station/checks/src/tolerance.ts`) is distributed across the walls on that axis in
  proportion to their lengths (the surveyor's compass rule), so every wall moves a little and the
  long walls absorb most of it. The entered values are kept unchanged in
  `sketch-measurements.json`; the adjusted values go into the capture model.
- A residual above the tolerance but within 3 % is applied the same way and reported: the room
  is `limited` with "measurements of Kitchen do not close by 48 mm on the long axis".
- A residual above 3 % is refused at entry time: the flow shows which axis does not close and asks
  the operator to re-check the lengths before continuing. (The operator can still continue; the
  room is then `limited` and the station reports the disagreement.)

A room with diagonals is solved by least squares on its corner coordinates, starting from the
sketch's shape with the measured sides, minimising the squared differences of every measured side
and diagonal; the residuals are graded with the same tolerance.

### 1.5 Fewer measurements than required

The flow never blocks on a missing number. It marks what it had to estimate:

| Missing                                 | What the model uses                                                       | Marking                                      |
| --------------------------------------- | ------------------------------------------------------------------------- | -------------------------------------------- |
| One wall of an axis (rectilinear)       | its length from closure                                                   | `confidence: medium` (derived)               |
| Both walls of an axis, or more          | the operator's "about" estimate, else the sketch proportion of a measured wall | `confidence: low`, capture `limited`     |
| Diagonal of an unsquare corner          | the corner is drawn square                                                | `confidence: low` on both walls, `limited`   |
| Ceiling height                          | 2.44 m                                                                    | `sketch.ceilingHeightSource: assumed`, `limited` |
| Opening width                           | 0.91 m door, 1.22 m window, 1.22 m opening                                | `confidence: low`, `limited`                 |
| Opening position                        | centred on the wall, or by sketch order (evenly spaced)                   | `confidence: low`, `limited`                 |
| Window sill or height, door height      | the defaults in 1.3                                                       | `confidence: low` (not `limited` on its own) |

`limited` is recorded in the capture record (`sketch.measurements: "limited"`), shown on the
Capture overview's floor row ("Floor 1 · sketch · limited"), and graded by the station (1.7).
Walls and openings that were measured carry `confidence: high`.

### 1.6 Measurement table

Required: the model is incomplete or wrong without it. Recommended: used to check the required
values (closure, squareness) or to replace a default. Optional: improves the exports only.

| Room shape                    | Required                                                                                                           | Recommended                                                                   | Optional                                        |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- | ----------------------------------------------- |
| Rectangle (4 corners)         | 2 adjacent walls; ceiling height; per door/opening: width + distance from a corner; per window: width + sill + height + distance from a corner | the other 2 walls (closure); 1 diagonal (squareness); door heights            | window head height; wall thickness if known     |
| L-shape (6 corners)           | 4 walls (no two unmeasured on one axis); ceiling; openings as above                                                | all 6 walls; 1 diagonal across the inside corner                              | as above                                        |
| Rectilinear, n corners        | n − 2 walls; ceiling; openings as above                                                                            | all n walls; 1 diagonal per 4 corners                                         | as above                                        |
| Any room with k unsquare corners | the rectilinear set + k diagonals (one across each unsquare corner)                                              | all walls; a second diagonal where the room is long                           | as above                                        |
| Whole floor (several rooms)   | each room's required set; which walls are shared (from the sketch)                                                 | overall length and width of the floor as field controls (axis A, axis B)      | floor-to-floor height (field controls)          |

The flow asks for exactly the required set in order and offers the recommended items on the same
screen as "Also measured" rows, so the operator who has the tape out can add them without a
second pass.

### 1.7 What the station needs to accept a sketch package

Read against `station/checks` (13 rules, evaluator 1.1.0) and `CaptureModelMapping`:

- **The capture model needs nothing new.** Walls, rooms, doors, windows and openings carry the
  same fields; `confidence` (`low`/`medium`/`high`, "detection confidence reported by the capture
  framework") carries the measured/derived/estimated marking. `refs` is empty: the sketch is not
  one of the geometry source roles, and the manifest's `derivedFrom` carries the provenance.
  `CaptureModelMapping` is not used: it maps RoomPlan documents. The sketch solver is its own
  pure target, `SketchCapture/SketchSolver`, that writes a `CaptureModel` directly, reusing
  `PolygonMath` for winding and area.
- **The capture record** gets `captureSource: lidar | sketch` per capture (1.2.0) and, for a sketch
  capture, a `sketch` object with the completeness (`complete` / `limited`), the counts of measured
  and estimated walls, and the ceiling height source. A sketch capture carries none of the compass
  fields: there is no scan frame to read a heading into.
- **The manifest** gets two roles (1.2.0): `sketch_image` (the photo, image or PDF of the sketch,
  one per capture) and `sketch_measurements` (the entered values, `sketch-measurements.json`),
  both in `Original Exports/{areaKey}/{captureId}/`. A sketch capture has no `raw_roomplan_json`,
  `raw_depth` or `point_cloud_las` file.
- **Checks that pass unchanged:** 1 fingerprints, 2 parseable (with parsers for the two roles:
  JPEG/HEIC/PNG/PDF for the image, schema-checked JSON for the measurements), 3 property, 6
  companions (the GLB is self-contained), 7 DXF content, 8 LAS (not applicable), 9 coverage
  (photos are taken with the phone's camera as today), 10 plausibility, 11 registration, 12
  independence.
- **Check 4, units and scale:** unchanged. The field controls' axis A and B distances are
  compared with the model as today. They are measured by the same operator with the same tape, but
  they are a second reading of the overall extents against the sum of the wall segments, which is
  the closure check at floor level. Without controls the capture is "scale not verified", the same
  limitation a scan gets.
- **Check 5, orientation (up):** the extruded GLB is +Y up with a horizontal floor at Y = 0 and a
  height extent equal to the ceiling height; the DXF is in millimetres. Passes unchanged.
- **Check 5b, orientation (compass): adapted.** A sketch capture is not graded: one info finding,
  "Sketch capture: the plan is oriented as drawn; north is not shown." The plan sheet and the
  report show no north arrow for it (the existing not-verified rendering).
- **Check 14, sketch measurements (new rule `sketch.measurements`, evaluator 1.2.0):** for each
  sketch capture, reads the capture record's `sketch` object and the model's confidences:
  - complete, every wall and opening `high`, ceiling measured: info, "Geometry of Floor 1 comes
    from a measured sketch: 6 walls and 3 openings measured, ceiling measured."
  - any wall estimated: limitation, "2 of 6 walls of Floor 1 are estimated, not measured
    (wall-3, wall-5)"; next action: measure them on the next visit.
  - ceiling assumed: limitation, "Ceiling height of Floor 1 is assumed (2.440 m), not measured."
  - an opening estimated: limitation naming it.
  - a closure residual over the pass tolerance (recorded in `sketch-measurements.json`): limitation.
  - not applicable when the package has no sketch capture, so LiDAR verdicts do not change.
- **The spatial report and the web** read the verdict; the report's checks table lists the
  verdict's checks, so it gains the row when the rule ran. The report's plan page notes "Sketch
  capture" under the floor title. No migration: the station stores the capture record as JSON
  (`packages.capture_record`) and reads `captureSource` from it.

### 1.8 Recommendation

Build the guided flow around the required set of 1.6, ask for every wall (the recommended set
costs one more tape reading per wall and buys the closure check), and never block on a missing
number: estimate, mark `low`, and let the station say "limited". Do not try to vectorise the
sketch in this version: the sketch is kept as the reference original and shown beside the form;
the operator enters the topology (rooms, corners, which walls are shared, which wall each opening
is in) by tapping, which takes under a minute per room and is right every time, where line
detection on a phone photo of a pencil sketch is not. Automatic tracing of a scanned CAD plan is a
later step and changes nothing in the contract.

## Part 2. Design

### 2.1 In scope

- **Entry.** The Captures home gets a second button under "New capture": "Sketch capture", with
  the footnote "No LiDAR? Photograph a sketch or plan and enter the measurements." On a phone
  without LiDAR "New capture" stays (it explains the device gate) and "Sketch capture" is the
  primary button. Same Chapter brand: real logo, Inter, Times display titles, Courier ids.
- **Sketch source.** Step 2 of the sketch flow ("What are you drawing from?"): take a photo of the
  sketch (camera), choose from Photos, or import a file (image or PDF, `UIDocumentPicker`); or
  "No sketch" (measurements only). The file is copied unchanged into the capture's originals folder
  as `sketch.<ext>` and listed with role `sketch_image`.
- **Guided measurement entry** (`SketchCapture/SketchEntry`): a `SketchEntryModel` that asks for
  exactly the required set, in order, for every room: room name and type; shape (rectangle,
  L-shape, other with a corner count); "Are all corners square?"; the walls around the room
  (each: length, "Also measured" diagonal, exterior toggle, shared-with picker for rooms already
  entered); the openings per wall (kind, width, from which corner and how far, and for windows
  sill and height); ceiling height (once per floor, per room when different). Lengths use
  `FieldRules.LengthParser` (feet-inches and metric, the Field controls' entry rules). Each
  number has a "Measured" / "About" toggle; "About" and empty fields are what marks estimates.
- **Solver** (`SketchCapture/SketchSolver`, pure Swift, Linux-tested): `SketchMeasurements` →
  `CaptureModel` with the closure rule of 1.4, the estimates of 1.5, confidences, room polygons
  counter-clockwise from +Y, walls as centrelines with the assumed thickness (4.5 in interior,
  6 in exterior), openings placed by offset from the wall start, and a `SketchSolveReport`
  (completeness, closure residuals, estimated element ids) that fills the capture record's
  `sketch` object.
- **3D model** (`SketchCapture/SketchMesh`): a `TriangleMesh` for `MeshExport` from the model:
  the floor polygon at Y = 0 (ear-clipped), each wall as a box of its thickness and height with
  rectangular holes for its openings (the faces around an opening are rectangles in the wall's
  own plane), and the ceiling slab's underside. Written as `mesh.glb` and `mesh.obj` + `mesh.mtl`
  through `CaptureExporter` with no depth samples (no `points.las`).
- **Exports and package.** `VisitPackageBuilder` branches on `captureSource`: the sketch image
  and `sketch-measurements.json` are the originals; `capture-model.json` lists both in
  `derivedFrom`; the PlanExport files (`PlanExporter.exportAll`) and the mesh files follow as
  today. The visit flow (`VisitFlow`) is unchanged: a sketch floor is finished like a scanned
  floor, then photos, Field controls, Before you leave, Package ready, seal and upload through the
  existing `StationClient` path. A visit can mix scanned and sketched floors.
- **Contract 1.2** (`contract/`): capture record 1.2.0 (`captureSource`, `sketch`), manifest 1.2.0
  (roles `sketch_image`, `sketch_measurements`; layout folder Original Exports), OpenAPI 1.2.0
  (version note only: the record is carried as JSON), and the new `sketch-measurements` schema
  1.0.0 with TypeScript and Swift types, valid and invalid examples. Readers accept every version;
  writers write the newest.
- **Station:** rule 14 `sketch.measurements`, the compass rule adapted, parsers for the two roles,
  evaluator 1.2.0; fixtures: a one-room and a two-room sketch package (complete and limited) under
  `fixtures/`.
- **Tests:** solver unit tests (rectangle, L-shape, closure distribution, refused closure,
  estimates and confidences, diagonals, openings, mesh orientation and extent, schema
  conformance of the model); `SketchEntryModel` tests (the required set is asked in order and
  nothing more is required); App UI test of the flow in the replay mode (`-ChapterUITestSketch`:
  Captures home → Sketch capture → no sketch → one rectangular room with a door and a window →
  Capture overview shows the floor as a sketch → Package ready); station tests for rule 14 and
  the adapted compass rule.
- **Handoff note** in `docs/handoff/05-status-open-items.md`.

### 2.2 Out of scope

- Vectorising the sketch (line detection, OCR of printed dimensions). Tracing a scanned CAD plan.
- Editing a scanned floor's geometry with typed measurements (the LiDAR model is what RoomPlan
  measured).
- A point cloud for a sketch capture.
- The web review app: it reads the verdict and the record as they are; "Sketch" appears through
  the report's plan page and the checks table. The scan browser gets the sketch screens only if
  cheap (F14.5).

### 2.3 Data

`sketch-measurements.json` (`contract/schema/sketch-measurements.schema.json`, 1.0.0): what the
operator entered, unchanged by the solver.

```json
{
  "schemaVersion": "1.0.0",
  "visitId": "…", "captureId": "…", "areaKey": "floor-1",
  "displayUnits": "imperial",
  "source": { "kind": "hand_sketch", "path": "Original Exports/floor-1/…/sketch.jpg" },
  "ceilingHeight": { "valueMm": 2438, "enteredUnit": "ft_in", "enteredText": "8' 0\"", "measured": true },
  "rooms": [
    {
      "id": "room-1", "label": "Kitchen", "type": "kitchen", "shape": "rectangle",
      "allCornersSquare": true,
      "walls": [
        { "id": "wall-1", "length": { "valueMm": 4000, "enteredUnit": "mm", "enteredText": "4000", "measured": true }, "exterior": true },
        { "id": "wall-2", "length": { "valueMm": 3000, "enteredUnit": "mm", "enteredText": "3000", "measured": true } },
        { "id": "wall-3" },
        { "id": "wall-4", "sharedWith": { "roomId": "room-2", "wallId": "wall-6" } }
      ],
      "diagonals": [ { "from": 0, "to": 2, "length": { "…": "…" } } ],
      "openings": [
        { "id": "door-1", "kind": "door", "wallId": "wall-2", "width": { "…": "…" }, "fromCorner": "start", "fromCornerDistance": { "…": "…" } },
        { "id": "window-1", "kind": "window", "wallId": "wall-1", "width": { "…": "…" }, "sill": { "…": "…" }, "height": { "…": "…" }, "fromCorner": "end", "fromCornerDistance": { "…": "…" } }
      ]
    }
  ]
}
```

Walls are listed in order around the room, counter-clockwise seen from above as drawn; the room's
corner `i` is the start of wall `i`. A wall without `length` is unmeasured; `measured: false` is
an "About" estimate. `sharedWith` names the wall of an earlier room that is the same partition.

Capture record 1.2.0, per capture:

```json
"captureSource": "sketch",
"sketch": { "measurements": "limited", "wallsMeasured": 3, "wallsEstimated": 1, "ceilingHeightSource": "measured" }
```

`captureSource` is optional in the schema (a 1.1.0 document has none; a reader treats absence as
`lidar`); a 1.2.0 writer writes it for every capture. `sketch` is present exactly when
`captureSource` is `sketch`. A sketch capture carries no compass field.

### 2.4 Flow

```
Captures home ── Sketch capture ──► New capture (step 1 of 4: HUB project, address; no device gate)
  ──► What are you drawing from? (step 2: photo / Photos / file / no sketch; floor label; mode: room or floor)
  ──► Rooms and measurements (step 3: room list; per room the guided entry; the sketch image on top, zoomable)
  ──► Check (step 4: the colour Floorplan drawn live from the solver, closure residuals, what is estimated)
  ── Finish floor ──► photos ──► Capture overview (floor row "Floor 1 · sketch · 1 room") ──► … as today
```

"Finish floor" writes `sketch.<ext>` and `sketch-measurements.json` into the capture's originals
folder and hands the visit the same `CaptureFlowResult` shape (record with one capture, originals
directory, the solved capture model). `VisitRoomNames` (rename rooms) applies to sketch rooms as
to scanned ones: the operator's names are already the labels.

### 2.5 Acceptance criteria

```yaml criteria
AC1: {text: "The solver turns the required set of a 4.000 x 3.000 m rectangle (two walls, ceiling, one door, one window) into a capture model within 1 mm, every wall high confidence, and the model validates against capture-model.schema.json", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter SolverTests"}
AC2: {text: "An L-shaped room with four of six walls closes from the other two; a 2 % closure residual is distributed by length; a 5 % residual is reported and the capture is limited", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter ClosureTests"}
AC3: {text: "A rectangle with one wall is limited: the other axis is estimated with low confidence; an assumed ceiling is recorded as assumed", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter EstimateTests"}
AC4: {text: "The extruded mesh is +Y up with horizontal floor faces at Y 0, a height extent equal to the ceiling height, and passes the GLB validator", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter MeshTests"}
AC5: {text: "Capture record 1.2.0 and manifest 1.2.0 validate in TypeScript and Swift against the same examples; 1.0.0 and 1.1.0 documents stay valid; sketch-measurements 1.0.0 has valid and invalid examples", verify: "cmd:npm test --workspace contract/ts && swift test --package-path contract/swift"}
AC6: {text: "The station gives a complete one-room sketch package with field controls and photos a Ready verdict, a limited one a Limited verdict naming the estimated walls, and LiDAR fixture verdicts are unchanged except the evaluator version", verify: "test:station/checks/test/sketch.test.ts"}
AC7: {text: "In the replay mode the UI test goes from the Captures home through Sketch capture to Package ready with one rectangular room, a door and a window", verify: "cmd:scripts/wait-workflow.sh ios.yml App"}
AC8: {text: "ci, ios and web-e2e are green on the branch", verify: "cmd:gh run list --branch feat/f14-sketch-capture"}
```

## Steps

- F14.1 Contract 1.2: capture record 1.2.0, manifest 1.2.0, OpenAPI 1.2.0, the sketch-measurements schema, TypeScript and Swift types, examples and version tests.
- F14.2 `SketchCapture` package: `SketchSolver` (closure, estimates, confidences, report), `SketchMesh`, Linux tests.
- F14.3 Station: rule 14, the adapted compass rule, parsers, fixtures, evaluator 1.2.0.
- F14.4 iOS: Captures home entry, sketch source screen, guided entry, check screen, package builder branch, UI test.
- F14.5 Handoff note; scan browser screens if cheap.
