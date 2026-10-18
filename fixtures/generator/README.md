# @chapter/fixtures generator

Deterministic generator of synthetic Chapter Capture intake packages. Phones cannot scan in CI, so
every export writer and every station check is tested against these fixtures. Everything is
generated from fixed seeds, fixed UUIDs and fixed timestamps: two runs give byte-identical output.

```
npm run generate --workspace @chapter/fixtures   # rewrites fixtures/generated
npm test --workspace @chapter/fixtures
node fixtures/generator/scripts/scan-pii.mjs fixtures
```

Placeholder data only: address `100 Example Street, Testville, NY 00000`, deal id
`fixture-deal-0001`, operator `Test Operator`. No real customer files, no personal information.

## What is generated

`fixtures/generated/index.json` lists everything below.

| Fixture              | Visit and captures  | Shape                                                                                                                              |
| -------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `box-room`           | 1 visit, 1 capture  | 4.000 x 3.000 m, ceiling 2.700 m, 1 door, 1 window, 1 table                                                                        |
| `l-shaped-room`      | 1 visit, 1 capture  | 6.000 x 4.000 m outline minus a 3.000 x 2.000 m corner (18 m2), ceiling 2.700 m                                                    |
| `two-room-apartment` | 1 visit, 1 capture  | Living Room 5.000 x 4.000 m + Bedroom 3.000 x 4.000 m, 1 door, 2 windows, 1 passage                                                |
| `two-floor-house`    | 1 visit, 2 captures | Floor 1 6.000 x 5.000 m (2.700 m); Floor 2 with a 1.000 x 3.000 m stair void (2.500 m); floor-to-floor 2.950 m; 2 shared landmarks |

Each good fixture folder holds:

- `truth.json`: exact dimensions, areas, opening sizes, bounds, control distances (and for the
  house: floor-to-floor, stair void, landmark positions in each capture's own frame).
- `package/`: a complete intake package laid out exactly per `contract/schema/layout.json`, with
  `manifest.json` (sha256 and bytes of every file), `capture-record.json`, `field-controls.json`,
  and per capture: `roomplan.json`, `depth-samples.bin`, `capture-model.json`, `plan.dxf`,
  `rooms.csv`, `plan.pdf`, `spatial-report.pdf`, `plan.png`, `plan.svg`, `mesh.glb`, `mesh.obj`,
  `mesh.mtl`, `mesh-texture.png`, `points.las` and one site photo JPEG per captured room.

Broken fixtures are in `fixtures/generated/broken/<defect-id>/`, each with `defect.json` and a
`package/`. Each is the `box-room` package with exactly one file changed; the manifest is rebuilt
so it matches the bytes (none of them is a fingerprint mismatch). `defect.json` names the defect
id, the affected file and role, the mutation and its details.

| Defect id             | The one change                                                                                        |
| --------------------- | ----------------------------------------------------------------------------------------------------- |
| `empty-file`          | `plan.dxf` is zero bytes                                                                              |
| `wrong-address`       | `capture-record.json` address differs from the HUB address (`details.hubAddress`, also in truth.json) |
| `inches-as-metres`    | `capture-model.json`: every length multiplied by 39.37007874 (inch numbers in metre fields)           |
| `z-up-mesh`           | `mesh.glb` has height along +Z: (x, y, z) -> (x, -z, y)                                               |
| `missing-gltf-bin`    | `mesh.glb` has no BIN chunk; its buffer is the external `mesh.bin`, which is not in the package       |
| `las-bad-header`      | `points.las` header point count is 1000 more than the points in the file                              |
| `dimensions-3pct-off` | `field-controls.json` long distances are 0.97 x truth (3% short), entered in mm                       |

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
