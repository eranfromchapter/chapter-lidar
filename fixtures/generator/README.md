# @chapter/fixtures generator

Deterministic generator of synthetic Chapter Capture intake packages. Phones cannot scan in CI, so
every export writer and every station check is tested against these fixtures. Everything is
generated from fixed seeds, fixed UUIDs and fixed timestamps: two runs give byte-identical output.

```
npm run generate --workspace @chapter/fixtures        # rewrites fixtures/generated
npm run record-report --workspace @chapter/fixtures   # rewrites fixtures/report/424-west-end
npm test --workspace @chapter/fixtures
node fixtures/generator/scripts/scan-pii.mjs fixtures
```

Placeholder data only: address `100 Example Street, Testville, NY 00000`, deal id
`fixture-deal-0001`, operator `Test Operator`. No real customer files, no personal information.

## What is generated

`fixtures/generated/index.json` (`generatedFormatVersion` 1.1.0) lists everything below except
the RoomPlan-only fixtures: `fixtures` (the good ones), `broken`, `legacy` and `samples`.

| Fixture              | Visit and captures  | Shape                                                                                                                              | Compass (capture record)                                            |
| -------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `box-room`           | 1 visit, 1 capture  | 4.000 x 3.000 m, ceiling 2.700 m, 1 door, 1 window, 1 table                                                                        | none (record 1.0.0)                                                 |
| `l-shaped-room`      | 1 visit, 1 capture  | 6.000 x 4.000 m outline minus a 3.000 x 2.000 m corner (18 m2), ceiling 2.700 m                                                    | none (record 1.0.0)                                                 |
| `two-room-apartment` | 1 visit, 1 capture  | Living Room 5.000 x 4.000 m + Bedroom 3.000 x 4.000 m, 1 door, 2 windows, 1 passage                                                | approximate: 87.5°, ±12°, magnetic (record 1.1.0)                   |
| `two-floor-house`    | 1 visit, 2 captures | Floor 1 6.000 x 5.000 m (2.700 m); Floor 2 with a 1.000 x 3.000 m stair void (2.500 m); floor-to-floor 2.950 m; 2 shared landmarks | Floor 1 verified: 212.4°, ±8°, true; Floor 2 not calibrated (1.1.0) |

Each good fixture folder holds:

- `truth.json`: exact dimensions, areas, opening sizes, bounds, control distances (and for the
  house: floor-to-floor, stair void, landmark positions in each capture's own frame).
- `package/`: a complete v2 intake package laid out exactly per `contract/schema/layout.json`,
  with `manifest.json` (schema 1.1.0; sha256 and bytes of every file), `capture-record.json`
  (1.1.0 when a capture has a compass reading or issue, else 1.0.0, so both versions stay
  covered), `field-controls.json`, and per capture: `roomplan.json`, `depth-samples.bin`,
  `capture-model.json`, `plan.dxf`, `rooms.csv`, `plan-sheet.pdf` (role `plan_pdf`), `plan.png`,
  `plan.svg`, `mesh.glb`, `mesh.obj`, `mesh.mtl`, `mesh-texture.png`, `points.las` and one site
  photo JPEG per captured room. No `spatial-report.pdf`: the spatial report is a station output
  and the role `spatial_report_pdf` is retired in manifest 1.1.0.

`legacy`: `legacy-1.0.0` is the box room as an app before v2 sealed it: manifest 1.0.0 with
`plan.pdf` and the phone's `spatial-report.pdf` (role `spatial_report_pdf`), capture record
1.0.0. Its index entry carries `"legacy": true`. Such packages must still upload, seal and get a
verdict.

`samples`: `sample-424` is the apartment of the design artboards (plan sheet 1b, spatial report
1f–1aa), traced from the design bundle's `apartment-424.js` (19.4 trace units per foot; close to
the sample, not exact): one floor, 12 rooms with the sample's names (5 unlabeled `Room N`), walls
from the room outlines at thickness 0, 8 doors (traced thresholds narrower than 0.7 m are widened
about their centre), 4 passages, 2 windows, 14 objects, Room 4 with one lower wall (approximate
ceiling), Primary closet not scanned (locked), Storage room not entered, 7 photos of the Living
Room (with `directionSource`) and one of every other room, compass verified (212.4°, ±8°, true
north), units shown imperial. Text data stays placeholder data. Its station verdicts, one per
outcome, are in `fixtures/report/424-west-end/`, recorded from the station checks by
`src/report.ts` (`npm run record-report`; see the README there).

Broken fixtures are in `fixtures/generated/broken/<defect-id>/`, each with `defect.json` and a
`package/`. Each is the `box-room` package with exactly one file changed; the manifest is rebuilt
so it matches the bytes (none of them is a fingerprint mismatch). `defect.json` names the defect
id, the affected file and role, the mutation and its details.

| Defect id                   | The one change                                                                                        |
| --------------------------- | ----------------------------------------------------------------------------------------------------- |
| `empty-file`                | `plan.dxf` is zero bytes                                                                              |
| `wrong-address`             | `capture-record.json` address differs from the HUB address (`details.hubAddress`, also in truth.json) |
| `inches-as-metres`          | `capture-model.json`: every length multiplied by 39.37007874 (inch numbers in metre fields)           |
| `z-up-mesh`                 | `mesh.glb` has height along +Z: (x, y, z) -> (x, -z, y)                                               |
| `missing-gltf-bin`          | `mesh.glb` has no BIN chunk; its buffer is the external `mesh.bin`, which is not in the package       |
| `las-bad-header`            | `points.las` header point count is 1000 more than the points in the file                              |
| `dimensions-3pct-off`       | `field-controls.json` long distances are 0.97 x truth (3% short), entered in mm                       |
| `compass-time-outside-scan` | `capture-record.json` 1.1.0 with a true-north reading (212.4°, ±8°) recorded 2 h before `capturedAt`  |

## RoomPlan-only fixtures

`fixtures/generated/roomplan-only/<name>/` holds a raw RoomPlan export (`roomplan.json`) and its
ground truth (`expected.json`), with no package around it. These are not in `index.json`, whose
readers expect complete packages. Swift tests load them with `Fixtures.roomPlanOnly(name)`
(CaptureCore `CaptureTestSupport`).

`apartment-walkthrough` (`src/walkthrough.ts`) is a whole two-bedroom apartment scanned by walking
through every doorway, shaped like a real iPhone export: one `CapturedRoom` (version 2, no
top-level identifier) with one floor outlining the whole apartment (26 corners, clockwise from
+Y), 31 walls with about 15% of the outline left without a wall and 7 interior wall ends that stop
0.2 to 0.5 m short of their junction, no wall between the kitchen and the living room, sections
for the living room, kitchen, both bedrooms and bathroom plus an `unidentified` one in the hall
(none for the closet), 24 objects with RoomPlan attributes and mostly low confidence, doors seen
open and closed, one passage opening and four windows. The floor is 1.31 m below the capture
origin and the plan is turned 14.2 degrees about +Y. `expected.json` lists each intended room
(label, type, counter-clockwise polygon in the capture frame, area, the section and the objects in
it), every wall (outline or interior, the rooms beside it, short ends) and every opening.

## Conventions

- Lengths in metres, right-handed, +Y up; plan coordinates are X and Z. Counter-clockwise polygons
  are seen from +Y (negative shoelace sum in x, z).
- Scanned surfaces have thickness 0, so wall centrelines coincide with room outlines and wall
  lengths equal room edge lengths.
- Floor 2 of the house is written in its own frame (turned 90 degrees about Y and moved). Nothing
  in the models relates it to floor 1; only the landmarks and the floor-to-floor level do.
- The apartment lists the partition between the rooms once per room (`wall-3` and `wall-5`), like
  a RoomPlan structure; the door is in `wall-3`.
- Field controls equal the truth (tape or laser, units mm, cm and m).
- Depth samples and `points.las` carry seeded uniform noise of up to 5 mm per axis. The meshes,
  plan files and models are noise free.

## File formats written here

- `roomplan.json`: Apple `CapturedRoom` Codable JSON for a one-room capture; `CapturedStructure`
  (`{ "version", "rooms": [CapturedRoom] }`) for the apartment. simd values are arrays:
  `dimensions` `[x, y, z]`, `transform` one flat array of 16 numbers, column after column (`simd_float4x4`). Enum cases with values encode as
  `{ "door": { "isOpen": false } }`, confidence as `{ "high": {} }`. A wall surface has local X
  along the wall, local Y up; `dimensions` is `[length, height, 0]`; doors, windows and openings
  carry `parentIdentifier` (the wall). Floors carry `polygonCorners` in the floor's local frame.
  Float values are shortest float32 decimals.
- `depth-samples.bin` ("CHDS" version 1, little endian): 16-byte header (magic, u32 version, u32
  count, u32 reserved), then `count` x 16 bytes: f32 x, y, z (metres, capture frame, +Y up) and
  u8 red, green, blue, confidence (0 to 2). See `src/depth.ts`.
- `plan.dxf`: ASCII R2013 (AC1027), `$INSUNITS` 4 (millimetres), plan entities (LINE, ARC,
  LWPOLYLINE, TEXT) on layers `A-WALL A-DOOR A-GLAZ A-OPEN A-AREA A-ANNO-TEXT A-FLOR-OBJ`; plan y
  is the model's -z.
- `mesh.glb`: glTF 2.0, one node, POSITION and NORMAL float32, uint16 indices, +Y up, metres. Passes
  the Khronos validator with zero errors.
- `mesh.obj` + `mesh.mtl` + `mesh-texture.png`: relative companions (`mtllib mesh.mtl`,
  `map_Kd mesh-texture.png`).
- `points.las`: LAS 1.4, point format 7, scale 0.001, offsets at the minimum, Z up (model height),
  legacy counts zero, 64-bit count set, no WKT, system identifier `Chapter Capture`.
- PDFs: PDF 1.7, one Letter page, Helvetica text; address, capture id and room labels are text.
- `plan.png`: 256 x 192, 1 bit; PNG data uses stored deflate blocks so bytes never depend on the
  zlib version. Photos are 64 x 48 grayscale JPEG with a JFIF header only (no EXIF, no location).

JSON files are written through Prettier (config from the repository root), so
`npm run format:check` passes on the committed output.

## PII scan

`scripts/scan-pii.mjs <dir>` scans text files for emails, phone numbers and street addresses, prints
every hit and exits 1 on any. The two placeholder addresses above are allowed exactly as written. A
scanned folder may carry a `pii-allowlist.txt` (one literal per line) for reviewed exceptions.
