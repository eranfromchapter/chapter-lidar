# MeshExport

Writes the 3D files of a Chapter Capture visit on the phone: GLB (preferred 3D source), OBJ + MTL
(alternative) and LAS 1.4 (point cloud for ReCap). Swift and Foundation only, so it builds and
tests on Linux as well as iOS 17+ and macOS 14+.

## Inputs (for F2 and F6)

The capture code converts ARKit data into these neutral types; this package has no ARKit code.

- `TriangleMesh` and `FloorMesh` (one per capture or floor): positions in metres, right-handed,
  **+Y up**, in the capture's own frame (apply the `ARMeshAnchor` transform first); optional unit
  normals; optional per-vertex `RGB8` colours sampled from the camera frames; triangle indices
  counter-clockwise.
- `[DepthSample]`: x, y, z in metres (+Y up), r, g, b, confidence 0 to 2. `DepthSampleFile` reads
  and writes the `depth-samples.bin` format ("CHDS" version 1).

## Outputs

| Writer            | File                              | Notes                                                                                                 |
| ----------------- | --------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `GLBWriter`       | `mesh.glb`                        | One node per floor, `asset.generator` `Chapter Capture <version>`, POSITION, NORMAL, COLOR_0, no textures |
| `OBJWriter`       | `mesh.obj` + `mesh.mtl`           | `v x y z r g b`, `mtllib mesh.mtl` (bare file name), one `o` per floor                                |
| `LASWriter`       | `points.las`                      | LAS 1.4, format 7, scale 0.001, offsets at the minimum, Z up, system id `Chapter Capture`            |
| `CaptureExporter` | all of the above into one folder  | Decimates and thins first                                                                             |

- `MeshDecimator`: quadric error edge collapse to a face budget (default 1,500,000). Flat areas
  collapse first; corners, creases and open borders are kept. A mesh within the budget is not
  touched.
- `PointThinning`: one point per 5 mm voxel (the one nearest the voxel centre), capped at 20 million
  points. If the occupied voxels exceed the cap, the voxel edge grows by 25% steps until they fit.

## LAS details

- LAS is Z up. Model (x, y, z) is written as LAS (x, -z, y) (right-handed, same as the fixtures).
- No WKT (local coordinates). PDAL prints "Global encoding WKT flag not set for point format 6 - 10"
  (a warning, not an error). `LASOptions.writeLocalCoordinateSystemWKT = true` sets the WKT bit and
  writes a `LOCAL_CS` VLR, if ReCap turns out to need it.
- Global encoding bit 3 (synthetic return numbers) marks the file as derived data. An ASCII VLR
  (`ChapterCapture`, record 1) says it comes from a phone depth sensor and is not survey data.
  `ExportProvenance` holds the same statement for the package manifest.
- GPS time is a synthetic ascending sequence; samples have no timestamp.

## Tests

`swift test --package-path ios/Packages/MeshExport`. The tests write every GLB, OBJ + MTL and LAS to
`.build/test-output/`; check them with `scripts/verify-exports.sh gltf <dir>` (Khronos validator) and
`scripts/verify-exports.sh las <dir>` (PDAL).
