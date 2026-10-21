# FieldKit

Labeled site photos, independent field controls and the before-leaving checklist (spec F5; design
v2, artboard 2d `app-field-v2`, build spec `phone-field`).

| Target                    | Imports                                | Purpose                                                                                                        |
| ------------------------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `FieldRules`              | Foundation, CaptureContract            | `ChecklistRules`, `ControlsList`, `LengthParser` (exact mm), `LengthFormatter`, `MeasurementEntryDraft`, `FieldControlsEditor`, `FieldControlsFile`, `PhotoRecord`, `PhotoLabelDraft`, `PhotoStrip`, the compass pre-fill (`PhotoHeadingSample`, `CameraAxis`, `PhotoDirection.fromCompass`) and `CaptureCompassStatus` / `CompassSummary` |
| `PhotoStore`              | Foundation, FieldRules                 | `PhotoRecordStore` keeps original HEIC/JPEG bytes unchanged; `PhotoFileStore` is injected; pure-Swift SHA-256   |
| `FieldKitUI`              | SwiftUI, UIKit, AVFoundation, ChapterUI | The v2 screens on ChapterUI's tokens and components (iOS only; empty on Linux and macOS)                       |
| `FieldKitUISnapshotTests` | ChapterUISnapshotTesting               | The screens and sheets of artboard 2d, at the default text size and at AX3 (iOS simulator only)                |

`FieldRules` and `PhotoStore` build and test on Linux (`scripts/swift-test.sh`). There is no
`.apple-only` marker; the UI target is excluded from non-iOS builds with `#if canImport`.

```sh
swift test --package-path ios/Packages/FieldKit --filter ChecklistV2Tests
swift test --package-path ios/Packages/FieldKit --filter ControlsListTests
swift test --package-path ios/Packages/FieldKit --filter PhotoRecordTests
# The snapshots (iPhone 17 Pro, iOS 26.0, like ios.yml; record with TEST_RUNNER_RECORD_SNAPSHOTS=1):
cd ios/Packages/FieldKit
xcodebuild test -scheme FieldKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' \
  -only-testing:FieldKitUISnapshotTests
```

## Screens (FieldKitUI)

The app pushes these onto its `NavigationStack`; they never push, and report everything else
through callbacks. Fonts, colours and components are ChapterUI's (`FieldTheme` is an alias of
`ChapterTheme`; Inter is registered by `ChapterFonts.register()`).

| Screen | API | Notes |
| --- | --- | --- |
| Photo step | `PhotoCaptureFlowView(model:camera:onDone:onRenameRooms:)`, or `PhotoViewfinder` + `PhotoLabelingView(model:onDone:onRenameRooms:)` | The viewfinder hides the bar and runs the heading provider; "Label a photo" has an inline bar, Back asks `Discard this photo?`. The room stays selected; `More` opens the room picker (every room, "Room not in the list", "Rename rooms"). |
| Heading | `PhotoLabelingModel(…, heading: PhotoHeadingProviding?)`, `FixedPhotoHeading` | The app passes its adapter over the one compass service (`CompassPhotoHeading`). The shutter samples it before the camera returns; a sample pre-fills N/E/S/W when it is at most 2 s old, ±30° or better and the camera within 60° of level. |
| Field controls | `FieldControlsView(model:)`, `FieldControlsModel(captures:controls:policy:isReadOnly:sealedRevision:persist:)` | One list: each floor's minimum set and what lies between floors. A row opens the entry sheet (feet and inches as two fields; mm and m; tape or laser). `focus(rowId:)` / `focusFirstGap(of:)` for Before you leave "Add". |
| Before you leave | `BeforeYouLeaveView(report:headerCaption:focus:isReadOnly:sealedRevision:onTakePhoto:onAddControls:onReadCompass:onConfirmNoRoomsSkipped:onRenameRooms:onFinish:)` | Six rows in one card; the compass row is advisory (▲, never blocks). `focus` scrolls to a row and flashes it. Pass `onReadCompass: nil` (critique R-22). |
| Rename rooms | `RoomNamesSheet(draft:isReadOnly:onSave:)` | v2 sheet bar (`rooms.cancel`, `rooms.save`). |

## Rules worth knowing

- Policy: `ChecklistPolicy.shipping` (= `.standard`, owner question Q-A) is the one constant that
  switches the Field controls list and Before you leave between the two renderings. Standard: the
  LiDAR scan provides the measurements and tape or laser checks are optional (nothing is ■).
  Manual (`.manualControls`, as drawn): A, B and one ceiling height per floor, one floor-to-floor
  level and two shared landmarks per pair of consecutive floors are required (`4 of 9 required`).
- Length entry: 1 in = 25.4 mm exactly, integer arithmetic, at most 4 decimals of a millimetre. A
  value that would need rounding is refused (`LengthParseError.tooPrecise`), so every stored
  `valueMm` is exactly what was entered. Feet must be whole; inches a decimal (`0,5` reads as
  0.5). `enteredText` is `10' 0.5"` with `enteredUnit` `ft_in`. Changing the unit clears the fields.
- Screens show `7,520 mm`, `2,690–2,740 mm` and `24' 8.1"` (ASCII marks, 0.1 in, comma thousands).
- Photo direction is N/E/S/W only (the manifest schema has no free-text direction). The saved
  label's `directionSource` is `compass` only when the operator kept the untouched pre-fill.
- Rooms not scanned: the row passes when every omitted or inaccessible room has a name and a
  reason, or when there are no such notes and the operator tapped "All rooms scanned". The tap is
  never a default. Keep it in `NoRoomsSkippedConfirmation` (`Codable` for `visit.json`) and pass
  `isConfirmed(for: record)` as `ChecklistInput.noRoomsSkippedConfirmed`. It counts only while the
  visit has the same capture ids as at the tap and no capture lists a room not scanned.
- Compass: `ChecklistInput.compass` overrides a capture's status; otherwise it comes from the
  capture record through the contract's evaluator (`CompassState`; a 1.0.0 record is `not read`).
  `CompassSummary.short` / `.overview` are the capture overview's Compass row words.
- App shell (F6) must provide `NSCameraUsageDescription` and call `FieldControlsFile.write` from the
  `persist` closure of `FieldControlsModel`.
