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

Each document has its own schema version. The capture record, field controls, manifest and
verdict use `SchemaVersion` (1.0.0). The capture model uses `CaptureModelSchemaVersion`: it
reads 1.0.0 and 1.1.0 and always writes 1.1.0, which only adds optional fields (room type and
its source, door `isOpen`, object attributes and parent).

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
  semantically equal JSON (a 1.0.0 capture model comes back as 1.1.0, nothing else changes).
- `SchemaParityTests`: each document's schema versions, every closed enum, the role list, the
  visit roles and the folder layout match the schema files exactly (missing or extra values
  fail).
- `PrimitiveTests`: timestamp, UUID and vector wire formats.

The tests read `contract/schema` and `contract/examples` in place; nothing is copied.
