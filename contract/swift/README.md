# CaptureContract (Swift)

Codable models of the Chapter Capture package contract. Foundation only, no dependencies;
builds on Linux, iOS 17+ and macOS 14+. The JSON Schemas in `contract/schema/` are the source
of truth.

| Schema                       | Swift type                                   |
| ---------------------------- | -------------------------------------------- |
| `capture-record.schema.json` | `CaptureRecord`                              |
| `capture-model.schema.json`  | `CaptureModel`                               |
| `field-controls.schema.json` | `FieldControls`                              |
| `manifest.schema.json`       | `PackageManifest`                            |
| `verdict.schema.json`        | `Verdict`                                    |
| `layout.json`                | `PackageFolder`, `PackageLayout`, `FileRole` |

Each document has its own schema version. Field controls and verdict use `SchemaVersion`
(1.0.0). The others read 1.0.0 and 1.1.0 and write 1.1.0:

| Document       | Version type                 | 1.1.0 adds                                                                                                                 |
| -------------- | ---------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| capture model  | `CaptureModelSchemaVersion`  | room type and its source, door `isOpen`, object attributes and parent                                                      |
| capture record | `CaptureRecordSchemaVersion` | the compass reading of each capture (`heading`, `headingAccuracy`, `headingSource`, `headingRecordedAt`) or `headingIssue` |
| manifest       | `ManifestSchemaVersion`      | `photo.directionSource` (`PhotoDirectionSource`); retires `spatial_report_pdf`                                             |

A manifest read as 1.0.0 that lists a retired role (`FileRole.retiredRoles`, `isRetired`) is
written back as 1.0.0 (`PackageManifest.writtenSchemaVersion`), the only version that allows it;
new manifests never list one.

## Compass

`Compass.swift` holds the one evaluator of a capture's reading, shared with
`contract/ts/src/compass.ts`: `CompassState(capture)` (verified: true north ±10° or better;
approximate: true ±11–30° or magnetic ±30°; not verified with a `CompassReason`), `NorthSymbol`
(arrow angle and caption lines, or the `Orientation: not verified` box, for a drawing turned by
ρ), `CompassText` (captions, station details, `{AGO}`) and `Capture.setCompass(_:)`.
`CompassMath.swift` holds the frame conventions (Core Motion, ARKit, capture and plan frames),
the heading of the capture frame from one paired sample, camera and photo bearings, the gravity
checks and the angle helpers. `HeadingSource` (`true`/`magnetic`) and `HeadingIssue` are the
only types of their kind in the app.

Wire formats: `UTCTimestamp` (UTC, whole seconds, `Z`), `LowercaseUUID`, `Vec3` and
`Quaternion` (fixed-length number arrays). Optional fields are omitted when nil, never `null`.
Use `CaptureContractJSON.makeEncoder()` for sorted keys and unescaped slashes, so files written
by the app are byte-stable.

These types are not a schema validator: they do not check patterns, ranges or cross-field rules.
Validate against the JSON Schemas (TypeScript package `@chapter/capture-contract`) where that matters.

## Tests

```sh
swift test --package-path contract/swift
swift test --package-path contract/swift --filter SchemaParityTests
```

- `RoundTripTests`: every `contract/examples/<schema>/valid/*.json` decodes and re-encodes to
  semantically equal JSON (a 1.0.0 capture model, capture record or manifest comes back as
  1.1.0, except the legacy manifest with a retired role; nothing else changes).
- `CompassTests`: every vector of `contract/test-vectors/compass-states.json` (the TypeScript
  tests run the same file), plus `{AGO}` and the tokens.
- `CompassMathTests`: synthetic Core Motion attitudes and ARKit poses (upright, flat, pitched,
  rolled, random world yaw) give back the constructed heading; transposed matrices fail the
  gravity checks; camera and photo bearings; the drawing angles; wrap and circular mean.
- `SchemaParityTests`: each document's schema versions, every closed enum, the role list, the
  visit roles and the folder layout match the schema files exactly (missing or extra values
  fail).
- `PrimitiveTests`: timestamp, UUID and vector wire formats.

The tests read `contract/schema`, `contract/examples` and `contract/test-vectors` in place;
nothing is copied.
