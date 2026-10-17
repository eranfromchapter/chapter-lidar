# FieldKit

Labeled site photos, independent field controls and the before-leaving checklist (spec F5).

| Target        | Imports                    | Purpose                                                                                                        |
| ------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `FieldRules`  | Foundation, CaptureContract | `ChecklistRules`, `LengthParser` (exact mm), `FieldControlsEditor`, `FieldControlsFile`, `PhotoRecord`, drafts |
| `PhotoStore`  | Foundation, FieldRules      | `PhotoRecordStore` keeps original HEIC/JPEG bytes unchanged; `PhotoFileStore` is injected; pure-Swift SHA-256   |
| `FieldKitUI`  | SwiftUI, UIKit, AVFoundation | Camera, photo labeling, field controls and checklist screens (iOS only; empty on Linux and macOS)              |

`FieldRules` and `PhotoStore` build and test on Linux (`scripts/swift-test.sh`). There is no
`.apple-only` marker; the UI target is excluded from non-iOS builds with `#if canImport`.

```sh
swift test --package-path ios/Packages/FieldKit --filter ChecklistRulesTests
swift test --package-path ios/Packages/FieldKit --filter ControlsUnitTests
swift test --package-path ios/Packages/FieldKit --filter PhotoRecordTests
```

## Rules worth knowing

- Length entry: 1 in = 25.4 mm exactly, integer arithmetic, at most 4 decimals of a millimetre. A value
  that would need rounding is refused (`LengthParseError.tooPrecise`), so every stored `valueMm` is
  exactly what was entered. Tape fractions: halves to sixteenths.
- Photo direction is N/E/S/W only (the manifest schema has no free-text direction).
- Minimum controls per floor (every capture except exterior): long distance A, long distance B, one
  ceiling height. Per pair of consecutive floors: one floor-to-floor level and two shared landmarks
  (`ChecklistPolicy`).
- App shell (F6) must provide `NSCameraUsageDescription` and call `FieldControlsFile.write` from the
  `persist` closure of `FieldControlsModel`.
