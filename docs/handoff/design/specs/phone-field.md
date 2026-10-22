# Build spec · phone-field · Phone field v2 (photos, field controls, entry sheet, before you leave)

Area key: `phone-field` · Feature: F5 · Artboards: **2d** `canvas/app-field-v2.dc.html` (to build), **2c**
`canvas/screen-field.dc.html` (v1, current) · Written Oct 21, 2026 for engineers; the bundle does not need to be
opened again.

Owner decisions applied (binding, Oct 21, 2026):

1. Inter replaces SF on every phone screen in this area. Times stays for display titles (see §1.2 and open
   question Q2). Mono stays mono. This area shows no logo; nowhere in it may the typed serif "chapter /
   RENOVATION" wordmark appear.
2. (Web: not this area.)
3. Compass recorded at the start of each floor's scan, 3 states (verified / approximate / not verified),
   thresholds ±10° / ±30° (north-arrow v2). The phone's spatial-report writer retires (phone-package / spatial-report
   areas); nothing in this area writes or lists a spatial report.

Recent repo work this area builds on and must not undo: room renaming (`RoomNamesSheet`, `RoomNamingDraft`,
`PhotoCoverage`, `RoomChips`, `PhotoRecordStore.relabelRooms`, `VisitRoomNames`/`room-names.json`,
`FieldControlsEditor.renameRooms`), the scan-derived measurements (`ScanMeasurements`, `ChecklistPolicy.standard`,
decided by Eran 2026-10-18), exact length parsing (`LengthParser`), originals kept byte for byte (`PhotoRecordStore`).

---

## 0. Scope

In scope (this spec):

| # | Screen / piece | Artboard |
|---|---|---|
| S1 | Photo step: viewfinder (kept, restyled) and **Label a photo** (v2) | 2d panel 1 |
| S1b | Room picker sheet ("More" chip) with "Rename rooms" | not drawn (needed by v2 chip row) |
| S1c | Discard-photo alert | not drawn (system alert per tokens) |
| S2 | **Field controls** guided list of the minimum set per floor | 2d panel 2 |
| S3 | **Entry sheet** (feet and inches as two fields, stored mm shown) | 2d panel 3 |
| S4 | **Before you leave** with the compass item | 2d panel 4 |
| S5 | Rename rooms sheet restyled to the v2 sheet pattern | not drawn (tokens: sheets) |
| D1 | Compass pre-fill of "Looking toward" (camera heading at the shutter) | 2d panel 1, tokens "New data" |
| D2 | Contract: manifest photo `directionSource` (manifest 1.1.0) | tokens "New data" |

Out of scope (other areas): Captures home, New capture, What are you scanning (incl. the compass reading at scan
start), Live scan, **Capture overview** and the visit navigation model (`phone-capture`); Package ready, upload,
verdict, revision 2, manifest assembly beyond the photo label field (`phone-package`); plan sheet, north arrow
drawing, spatial report, web review.

---

## 1. Visual system for this area (FieldTheme v2)

`ios/Packages/FieldKit/Sources/FieldKitUI/FieldTheme.swift` is rewritten to these values. Every number is pt.
Screen: iPhone 402 × 874 pt (artboard frame, iPhone 16/17 Pro). Light only (Info.plist `UIUserInterfaceStyle =
Light`, unchanged). Portrait only (unchanged).

### 1.1 Colour (hex, sRGB)

| Token | Hex | Use |
|---|---|---|
| `ink` | #1F2429 | text, selected chip fill, primary button fill, focused field border (1.5) |
| `ground` | #F5EFE6 | screen background, sheet background, value-field fill in the entry sheet |
| `surface` | #FAF5EE | grouped card fill, selected segment, text on ink |
| `nude` | #E8DDD0 | chip fill, segmented track, tinted row buttons, separators inside cards (1 pt) |
| `line` | #D9CCBC | card border (1 pt), photo placeholder, thumbnail placeholder, disabled primary fill, grabber |
| `muted` | #6B6557 | captions, subtitles, footnotes, section headers |
| `ready` | #2E5E2E | ● glyph |
| `limited` | #9A6A1E | ▲ glyph |
| `limitedText` | #7A5214 | text next to ▲ (compass detail) |
| `blocked` | #8B2E2E | ■ glyph, "Missing", "1 of 2", failing details, error text, needs-photo dot |
| `disabledText` | #4E493F | text of a disabled primary button |
| `chevron` | #B9AFA2 | row chevrons (8 × 14, stroke 2, round caps/joins), disabled Save in a sheet bar |
| `photoPill` | rgba(31,36,41,0.70) | time pill on the photo; text #FAF5EE |

### 1.2 Type

Inter is used by PostScript name with Dynamic Type scaling (`Font.custom(name, size:, relativeTo:)`):
`Inter-Regular` (400), `Inter-SemiBold` (600). Times: `Times New Roman` (system font). Mono: system monospaced
(`.system(size:, design: .monospaced)`, SF Mono).

| Role | Font | Size / line | relativeTo | Where |
|---|---|---|---|---|
| Large title (display) | Times New Roman Regular | 34 / 41, tracking 0 | `.largeTitle` | "Field controls", "Before you leave" (Q2: Times per owner; bundle drew SF Bold 34 tracking 0.4) |
| Nav title | Inter-SemiBold | 17 | `.headline` | "Photo 14 · Floor 1", sheet titles |
| Body | Inter-Regular | 17 | `.body` | row titles, text fields, Cancel |
| Body strong | Inter-SemiBold | 17 | `.headline` | primary button, sheet Save |
| Subhead | Inter-Regular | 15 | `.subheadline` | chips, segments, row values, row buttons, Before-you-leave subtitle (15/20) |
| Subhead strong | Inter-SemiBold | 15 | `.subheadline` | selected segment |
| Footnote | Inter-Regular | 13 (paragraphs 13/17) | `.footnote` | subtitles, details, footnotes, section captions on the labeling screen and sheets (uppercase) |
| Section header (list) | Inter-Regular | 12, uppercase | `.caption` | Field controls section headers |
| Entry value | Inter-Regular | 26 | `.title2` | feet / inches / mm / m fields |
| Mono 13 | SF Mono | 13 | `.footnote` | ft-in second line in Field controls rows |
| Mono 11 | SF Mono | 11 | `.caption2` | time pill on the photo |

Uppercase captions are produced with `.textCase(.uppercase)` on the first part only, e.g. `ROOM` + `· stays
selected for the next photo` (the suffix keeps its case). Glyphs needed: ASCII, `·` U+00B7, `–` U+2013,
straight quotes. No `′ ″ ⟂ → ½ ■ ● ▲` glyphs are typeset in this area: status shapes are drawn (§1.3), ft-in uses
ASCII `'` and `"`.

Font files: Inter must be registered in the app (`UIAppFonts`) before these screens render. That is shared phone
work (see §13, dependency on `phone-capture`). If Inter fails to register, iOS silently falls back to SF: the UI
test in §15.3 catches it.

### 1.3 Components (FieldKitUI `Components.swift`)

| Component | Spec |
|---|---|
| `PrimaryButton` | height **52** (v1 56), full width, radius 12, ink fill, text surface Inter-SemiBold 17. Disabled: fill `line` #D9CCBC, text #4E493F, same weight. |
| `TextButton` (new) | height 44, full width, transparent, ink Inter-Regular 17 ("Done with photos"). Disabled: text #B9AFA2. |
| `TintedRowButton` (new, replaces `OutlineButton`) | min height 44, horizontal padding 14, radius 8, fill nude #E8DDD0, ink Inter-Regular 15, no border ("Take photo", "Add", "Read", "All rooms scanned", "Use"). |
| `ChoiceChip` | min height 44, padding 0 × 14 (rooms) or 0 × 12 (subjects), radius 8; off: nude fill, ink 15; on: ink fill, surface 15. Keeps the existing needs-photo dot (7 pt circle, 5 pt inset top-right, #8B2E2E, #FAF5EE on a selected chip) and `accessibilityValue("needs photo")`. |
| `SegmentedControl` (new) | height 44, track nude #E8DDD0, track radius 9, inner padding 2; segments equal width; segment radius 7; unselected: transparent, ink Inter-Regular 15; selected: surface #FAF5EE, ink Inter-SemiBold 15, shadows `0 3 8 rgba(0,0,0,0.12)` and `0 3 1 rgba(0,0,0,0.04)` (SwiftUI: `.shadow(color: .black.opacity(0.12), radius: 4, y: 3)` then `.shadow(color: .black.opacity(0.04), radius: 0.5, y: 3)`). Accessibility: each segment a button with `.isSelected` when selected, container labelled (radio group semantics). |
| `GroupedCard` (new) | fill surface #FAF5EE, border 1 #D9CCBC, radius 12, clipped; rows separated by a full-width 1 pt nude #E8DDD0 line (drawn as the row's top border, not inset). |
| `SectionCaption` (new) | uppercase muted; size 13 on the labeling screen (padding 0 × 4) and in sheets (padding 0 × 16); size 12 in the Field controls list (padding 0 × 16). Gap to its card: 6 (labeling, sheets), 4 (Field controls list). |
| `StatusGlyph` (new) | 10 × 10 frame. ● circle centre (5,5) r 4.5 fill #2E5E2E; ■ square at (0.6,0.6) 8.8 × 8.8 fill #8B2E2E; ▲ triangle (5,0.6) (9.6,9.4) (0.4,9.4) fill #9A6A1E; ○ circle r 4 stroke 1 #6B6557 (new "optional / waiting", tokens "○ Waiting muted"). Accessibility labels: "Done", "Missing", "Partly", "Optional". |
| `Chevron` (new) | 8 × 14, path M1 1 L7 7 L1 13, stroke #B9AFA2 width 2, round caps and joins. |
| `SheetBar` (new) | grabber 36 × 5 radius 3 #D9CCBC, 6 pt from the sheet top; bar height 52, padding 0 × 16: left "Cancel" (Inter-Regular 17 ink, min width 60, leading), centre title (Inter-SemiBold 17), right action (Inter-SemiBold 17 ink, min width 60, trailing; disabled #B9AFA2). Sheet: `.presentationCornerRadius(16)`, `.presentationDragIndicator(.hidden)` (the bar draws its own grabber), `.presentationBackground(ground)`. |
| `InlineAction` | kept: pencil icon + "Rename rooms", Inter-Regular 15 ink, min height 44. |
| Back button | system navigation back (iOS 26: 44 pt glass pill). Where the back must be intercepted (S1), a leading toolbar button with `chevron.left` (12 × 20 visual, stroke 2.5) and accessibility label "Back"; on iOS < 26 draw the pill: 44 × 44 circle, fill rgba(250,245,238,0.8), border 0.5 rgba(0,0,0,0.06), shadows `0 1 3 rgba(0,0,0,0.07)` and `0 3 10 rgba(0,0,0,0.06)`. |

Layout constants: screen side padding **16** (v1 20). Bottom action area padding 10–12 top, 16 sides, safe-area
bottom (artboard 42 = home indicator + 8). Space scale 4·8·12·16·24.

---

## 2. Navigation and entry points (integration contract)

v2 replaces the straight line photos → controls → checklist with a home per capture (the **Capture overview**,
owned by `phone-capture`). This area's screens are pushed onto the app's `NavigationStack` and pop back to whatever
opened them. FieldKit views never push; they set `.navigationTitle`, `.navigationBarTitleDisplayMode`, `.toolbar`
and present their own sheets, and report everything else through callbacks.

| Opened from | Screen | Back / done returns to |
|---|---|---|
| Capture overview "Photos" row, a floor's detail, "Finish floor" (as today) | S1 viewfinder | viewfinder "Done" → opener |
| Before you leave "Take photo" | S1 viewfinder with `initialRoom` | viewfinder "Done" → Before you leave |
| S1 viewfinder shutter | S1 labeling (same view, state switch; nav bar shown) | "Save and take next" → viewfinder; "Done with photos" → opener; Back → viewfinder after discard |
| Capture overview "Field controls" row | S2 | system Back → overview |
| Before you leave "Add" | S2, entry sheet S3 opened on the first missing row | Back → Before you leave |
| S2 row tap | S3 sheet | Save / Cancel → S2 |
| Capture overview (Q5) | S4 | system Back → overview |

Callbacks the app (VisitModel / VisitView) wires:

```swift
PhotoCaptureFlowView(model:, camera:, onDone: () -> Void, onRenameRooms: (() -> Void)?)
FieldControlsView(model:)                         // model.focus(rowId:) presents S3 on appear
BeforeYouLeaveView(report:, headerCaption: String,
  onTakePhoto: (ChecklistItem) -> Void, onAddControls: (ChecklistItem) -> Void,
  onReadCompass: ((LowercaseUUID) -> Void)?,      // nil hides "Read"
  onConfirmNoRoomsSkipped: (() -> Void)?, onRenameRooms: (() -> Void)?, onFinish: () -> Void)
```

Fallback while `phone-capture`'s overview has not landed: `VisitView` keeps the v1 `VisitFlow` order and wraps the
current field step in a `NavigationStack` root with no back button; S2 keeps a trailing toolbar text button
"Continue" (identifier `controls.continue`, Inter-SemiBold 17) that calls `visit.controlsDone()`. Remove it once
the overview exists.

---

## 3. S1 Photo step

### 3.1 Viewfinder (kept; not drawn in v1 or v2)

`PhotoViewfinder.swift` keeps its layout (dark camera, header scrim, "Rooms", "Done", coverage pill, privacy pill,
72 pt shutter). Changes:

- Fonts: Inter per §1.2 (header 17 SemiBold, buttons 15, pills 13).
- Title (identifier `photo.title`): `Photo {n} · {captureLabel}`; when opened for a room from Before you leave:
  `{room} · Photo {n} · {captureLabel}` (was "… of …"). `{n}` = `store.nextSequence(captureId:)`.
- Navigation bar hidden while the viewfinder shows (`.toolbar(.hidden, for: .navigationBar)`).
- Starts the camera heading provider (§3.6) on appear, stops it on disappear.
- On the shutter: sample the heading **before** awaiting the camera, then take the photo (§3.6).
- "Rooms" (identifier `photo.rooms`) still opens Rename rooms for this capture. "Done" calls `onDone`.

### 3.2 Label a photo (v2, artboard 2d-1)

Shown when `model.pendingOriginal != nil`. Order top to bottom; content padding 0 × 16; vertical gap 12 between
blocks; caption-to-control gap 6.

| Block | Exact spec |
|---|---|
| Nav bar (inline) | Leading: Back (intercepted, §3.4). Title, centred, Inter-SemiBold 17: `Photo 14 · Floor 1` (`Photo {n} · {captureLabel}`; no target room here, the selected chip shows it). Trailing: `HEIC` or `JPEG` (format of the pending photo from `PhotoFormat.detect`; hidden if unknown), Inter 13 muted, 44 wide, right-aligned. Identifier of the title: `photo.labelTitle`; trailing: `photo.format`. |
| Photo | height **210**, full width, radius 16, placeholder fill #D9CCBC, image `scaledToFill` and clipped. Overlay pill bottom-left, 12 from left, 10 from bottom: padding 4 × 8, radius 6, fill rgba(31,36,41,0.7), text #FAF5EE SF Mono 11: `12:41 · original kept` (`{HH:mm} · original kept`, `takenAt` in the phone's time zone, 24-hour, zero-padded). Accessibility: "Photo just taken, 12:41, original kept". |
| Room | Caption `ROOM` + ` · stays selected for the next photo` (13 muted, padding 0 × 4). Below: **one non-wrapping row** of room chips that scrolls horizontally (`ScrollView(.horizontal, showsIndicators: false)`, gap 8, scrolls the selected chip into view on appear). Chips: `RoomChips.primary(rooms, target: selectedRoom)` (first **4** rooms of the capture, plus the selected or target room if further down), then a chip **`More`** (no ellipsis) that opens S1b. Selected: ink. Needs-photo dot kept. |
| Looking toward | Caption `LOOKING TOWARD` + suffix (13 muted, padding 0 × 4). Suffix: ` · from the compass, change if wrong` when the direction was pre-filled and not touched; ` · chosen by you` once the operator picked a segment; ` · no compass reading, choose one` when no pre-fill and nothing picked. Below: `SegmentedControl` with 4 segments `N`, `E`, `S`, `W` (identifiers `photo.direction.N` …; accessibility labels "North", "East", "South", "West"). No segment selected when the direction is nil. |
| Subject | Caption `SUBJECT`. Wrapping chips (FlowLayout, gap 8, padding 0 × 12) — **all seven, no More**: `Opening`, `Cabinetry`, `Ceiling`, `Fixture`, `Defect`, `General`, `Equipment`. Identifiers `photo.subject.{rawValue}`. |
| Photo strip | Row, gap 8, vertically centred: up to **4** thumbnails 40 × 40 radius 6 (placeholder #D9CCBC while decoding or on failure), then text 13 muted, 4 pt extra leading margin, wraps (max 3 lines): see §3.5. Identifier of the text: `photo.strip`. Thumbnails are `accessibilityHidden`. |
| Missing hint (kept, not drawn) | Above the buttons when a label is missing: `Choose Subject to save.` / `Choose Looking toward and Subject to save.` (13 muted; existing `missingHint`). Error from a failed save replaces it in #8B2E2E (existing `errorMessage`). |
| Bottom actions | Pinned (`safeAreaInset(edge: .bottom)`), background ground, padding 10 16 + safe area, gap 6: `PrimaryButton` **`Save and take next`** (identifier `photo.save`), `TextButton` **`Done with photos`** (identifier `photo.doneWithPhotos`). Both enabled only when `model.canSave`. |

The labels scroll (ScrollView) and the actions stay pinned (the reason in today's code still holds). The v1
"Still needs a photo: …" line under the chips is **removed** from this screen (the chip dots carry it; the
viewfinder keeps its coverage pill). The v1 "Rename rooms" next to the Room caption moves into S1b.

Interactions:

- Tap a room chip → `draft.room = room`. The strip updates to that room.
- Tap `More` → S1b.
- Tap a direction segment → `draft.chooseDirection(d)` (§9.3). Tapping the already-selected pre-filled
  segment keeps source `compass`.
- Tap a subject chip → `draft.subject = s`.
- **Save and take next** → `store.save(...)` with labels incl. `directionSource`; then back to the viewfinder;
  next draft = same room, direction cleared (re-filled from the compass at the next shutter), subject cleared.
- **Done with photos** → same save; on success call `onDone` (the camera stops on disappear). On a save error
  stay and show the error.
- **Back** → §3.4.

Default room when the step opens: `initialRoom` (from Before you leave) else the room of the most recent saved
photo of this capture else none.

### 3.3 S1b Room picker sheet ("More")

Detents `[.medium, .large]`, `SheetBar`: left `Cancel`, title `Rooms on {captureLabel}`, no right action.
Content padding 8 16, gap 14:

1. `GroupedCard` of every room of the capture (`capture.rooms`, renamed labels, capture order): row min 52,
   padding 0 × 16: name Inter 17; trailing: `No photo yet` 13 #8B2E2E with the 7 pt dot when the room needs a
   photo; a checkmark (SF Symbol `checkmark`, ink, 17) on the selected room. Tap → select, dismiss.
2. Caption `OTHER ROOM`; card with one row: `TextField` placeholder `Room not in the list` (17, words
   autocapitalised, max 100 characters) and a trailing `TintedRowButton` `Use` (enabled when trimmed text is
   non-empty) → `draft.room = text`, dismiss.
3. Card with one navigation row (min 52): pencil icon + `Rename rooms` (17) + `Chevron`. Shown only when
   `onRenameRooms` is given. Tap → dismiss this sheet, then present S5 for this capture. Identifier
   `photo.renameRooms`.

Empty room list (capture model without rooms): section 1 is omitted; the chip row shows only `More`.

### 3.4 S1c Back from the labeling screen

The photo is not saved yet, so Back asks first (system alert, 270 pt, per tokens):

- Title `Discard this photo?` · Message `It is not saved yet. You can take it again.`
- Buttons: `Keep` (cancel role) · `Discard` (destructive) → `model.discardPending()`, show the viewfinder.

(Q4: the artboard links Back to the overview; this spec returns to the viewfinder.)

### 3.5 Photo strip rule (pure, `PhotoStrip` in FieldRules)

Inputs: saved photos of this capture, the selected room, whether a photo is pending (always true on this screen).

- `roomPhotos` = saved photos of this capture whose room matches the selected room by `PhotoCoverage.key`, in save
  order. Thumbnails = the **last 4** of them, oldest left, newest right.
- `count` = `roomPhotos.count + 1` (the photo being labeled counts: artboard shows 4 thumbnails and "5 photos").
- Text: count 1 → `1 photo in Kitchen · keep people and personal items out of the frame`; count ≥ 2 →
  `5 photos in Kitchen · keep people and personal items out of the frame`; no room selected →
  `Keep people and personal items out of the frame.`

Thumbnails: decode with `CGImageSourceCreateThumbnailAtIndex` (max pixel size 120, `kCGImageSourceCreateThumbnailWithTransform`
true) from `store.originalData(for:)` off the main actor; keep in an in-memory `NSCache` keyed by record path.
Never write thumbnails to the visit or package folders.

### 3.6 D1 Compass pre-fill of "Looking toward"

Separate from the floor's scan-start compass (that is `phone-capture`'s): this is the direction the **camera** was
pointing when the photo was taken.

Provider (new, FieldKitUI, iOS only, `#if canImport(CoreMotion) && canImport(CoreLocation)`):

```swift
public struct PhotoHeadingSample: Hashable, Sendable {   // FieldRules (pure)
  public var azimuthDegrees: Double          // camera axis, clockwise from north, 0..<360
  public var horizontalComponent: Double     // 0...1, |horizontal part| of the unit camera axis
  public var accuracyDegrees: Double?        // CLHeading.headingAccuracy; nil if invalid (< 0)
  public var source: HeadingSource           // .true or .magnetic
  public var sampledAt: Date
}
@MainActor public protocol PhotoHeadingProviding: AnyObject {
  func start(); func stop(); func currentSample() -> PhotoHeadingSample?
}
public final class DeviceCameraHeading: PhotoHeadingProviding { ... }   // FieldKitUI
```

`DeviceCameraHeading`:
- `CMMotionManager.startDeviceMotionUpdates(using:)` at 30 Hz with `.xTrueNorthZVertical` when it is in
  `availableAttitudeReferenceFrames()` **and** location authorisation is When-In-Use or Always (true north needs
  location); otherwise `.xMagneticNorthZVertical` (source `.magnetic`). Never requests authorisation itself (the
  scan-start compass in `phone-capture` asks for it).
- `CLLocationManager.startUpdatingHeading()` only for `headingAccuracy`.
- Camera axis: the back camera looks along device −Z. With `m = attitude.rotationMatrix` (reference → device; its
  rows are the device axes in reference coordinates), the camera axis in the reference frame is
  `v = (−m.m31, −m.m32, −m.m33)`; reference X = north, Y = west, Z = up. `north = v.x`, `east = −v.y`,
  `horizontalComponent = sqrt(north² + east²)`, `azimuth = atan2(east, north)` in degrees normalised to 0..<360.
  This is `CameraAxis.sample(rotationMatrix:)` in FieldRules (pure, unit-tested). The convention must be confirmed
  on a device (§15.4); if it is the transpose, the fix is in that one function.

Mapping (pure, `PhotoDirection.fromCompass(_ sample: PhotoHeadingSample?, now: Date) -> PhotoDirection?`):
- nil when: no sample; sample older than 2 s; `accuracyDegrees` nil or > 30 (the ±30° "not verified" limit of
  north-arrow v2); `horizontalComponent` < 0.5 (camera more than 60° up or down, e.g. a ceiling photo).
- else the nearest cardinal: N for [315, 45), E [45, 135), S [135, 225), W [225, 315).
- Magnetic samples are used too (the operator can change the choice; the label says it came from the compass).

On the shutter: `suggestion = PhotoDirection.fromCompass(heading?.currentSample(), now:)`; after the photo arrives:
`draft.applyCompass(suggestion)` (sets direction and `directionSource = .compass` when non-nil).

Simulator, iPads without a magnetometer, compass uncalibrated: no sample → no pre-fill → caption suffix
`· no compass reading, choose one`. UI tests inject a fixed provider (§15.3).

---

## 4. S2 Field controls (artboard 2d-2)

### 4.1 Layout

| Part | Spec |
|---|---|
| Nav | System back. Large title **`Field controls`** (§1.2). Trailing toolbar text (13 muted, identifier `controls.progress`): manual policy `4 of 9 required` (`{done} of {total} required`, §4.4); standard policy: no trailing text. |
| Subtitle | First content line, 13 muted (13/17), 8 below the title, aligned with it: manual policy `Tape or laser only. Never copy numbers from the scan.`; standard policy `Measured by the LiDAR scan. Tap a row to add an optional tape or laser check.` (existing string). |
| Body | ScrollView, padding 10 16 0; sections stacked with gap 8. One section per non-exterior capture in capture order (by `capturedAt`, then record order), with a **between** section after each floor that has a next floor: Floor 1 · between 1 and 2 · Floor 2 · between 2 and 3 · Floor 3 … |
| Section | `SectionCaption` 12 uppercase (padding 0 × 16), gap 4, then a `GroupedCard`. Headers: `FLOOR 1 · MINIMUM SET` (`{label} · minimum set`, uppercased) and `BETWEEN FLOOR 1 AND FLOOR 2` (`between {lower} and {upper}`, uppercased). |
| Footnote | After the last card, gap 4, 13/17 muted, padding 0 × 16: `Stored in mm, shown in both units. Tap a row to add or change it.` |
| Empty | No capture: `No floor or area has been scanned yet.` Only exterior captures: `Exterior captures need no field controls.` (15 muted, in place of the sections). |

The v1 floor picker chips and the inline "New measurement" card are removed; every floor is on one scrolling list
and entry happens in S3.

### 4.2 Rows

Row anatomy: `Button` covering the whole row; HStack gap 12, padding 5 × 16, **min height 50** (two-line) or
padding 0 × 16, **min height 42** (one-line "compact"); `StatusGlyph` · VStack (title Inter 17; subtitle 13 muted;
gap 2) flexible · value VStack trailing (primary 15; secondary SF Mono 13 muted; gap 2) · `Chevron`. Rows separated
by the card's 1 pt #E8DDD0 line. Identifier `controls.row.{areaKey}.{kind}` for floor rows and
`controls.row.{lowerAreaKey}~{upperAreaKey}.{kind}` for between rows; the row's accessibility element combines its
texts, e.g. "Long distance A, Kitchen east wall to living west wall, 7,520 millimetres, 24 feet 8.1 inches, Done".

Manual policy (`ChecklistPolicy.manualControls`), exactly as drawn:

| Row (order) | Recorded | Missing |
|---|---|---|
| Long distance A | ● · title `Long distance A` · subtitle `{from} to {to}` (as entered, e.g. `Kitchen east wall to living west wall`) · values `7,520 mm` / `24' 8.1"` | ■ compact · `Long distance A` · value `Missing` #8B2E2E |
| Long distance B | ● · `Long distance B · at a right angle to A` · `{from} to {to}` · mm / ft-in | ■ compact · `Long distance B` · `Missing` |
| Ceiling height | ● · `Ceiling height` · `{n} rooms · at least 1 required` (`1 room · at least 1 required`) · one line `2,690–2,740 mm` when the heights differ (by whole mm), else two lines `2,690 mm` / `8' 9.9"` | ■ compact · `Ceiling height` · `Missing` |
| Openings · optional | ● compact · `Openings · optional` · `2 recorded` (ink) | ○ compact · `Openings · optional` · `None` (muted) |
| Floor to floor (between) | ● · `Floor to floor` · subtitle = location as entered · mm / ft-in | ■ · `Floor to floor` · subtitle `Level difference, measured at the stair` · `Missing` |
| Shared landmarks (between) | ● · `Shared landmarks` · `Visible from both floors · 2 required` · `{n} recorded` (ink) when n ≥ 2 | ■ · same title and subtitle · `1 of 2` (#8B2E2E) when 1; `Missing` when 0 |

`2` is `policy.minimumLandmarksPerFloorPair`. A landmark counts for a pair when its captures include both
floors (existing rule).

Standard policy (`ChecklistPolicy.standard`, the shipping default today, see Q1): same sections, rows and
order; no row is ever ■:
- A / B / ceiling with a tape or laser value: as "Recorded" above, plus a third value line `Scan 7,512 mm`
  (13 muted, Inter) when the scan has the quantity (existing behaviour).
- A / B / ceiling without tape but with a scan value: ● · subtitle `From the LiDAR scan · tap to check with tape`
  (ceiling: `From the LiDAR scan · {n} rooms`) · scan values.
- Anything with neither, and floor to floor / landmarks with none recorded: ○ · value `Optional` (muted).
- Openings with none recorded but scan openings: ● compact · `Openings · optional` · value
  `{doors + windows + openings} from the scan`.

### 4.3 Tap behaviour

- Single-value rows (A, B, floor to floor): open S3 for that control, prefilled when recorded (edit).
- Multi-value rows (ceiling height, openings, shared landmarks): open S3 in add mode, with a `RECORDED …` list of
  the existing entries at the top of the sheet (§5.6); tapping an entry switches the sheet to editing it.
- `model.focus(rowId:)` (used by Before you leave "Add"): scroll the row into view and open its S3.

### 4.4 Progress counter (manual policy)

`total = 3 × floors + Σ pairs (1 + minLandmarks)`; `done = Σ floors ([A] + [B] + [≥ 1 ceiling]) + Σ pairs ([≥ 1
floor-to-floor] + min(shared landmarks, minLandmarks))`. Openings never count. Floors = non-exterior captures;
pairs = consecutive floors. Artboard check: Floor 1 complete (3) + landmarks 1 + Floor 2 none = **4 of 9**. The
same function feeds the Before-you-leave item so both screens agree.

---

## 5. S3 Entry sheet (artboard 2d-3)

Presented from S2 with `.sheet` (detent `.large`; system dimming behind; artboard shows the sheet top at 96 pt).
`SheetBar`: `Cancel` · title · `Save`. Content: ScrollView, padding 8 16 0, gap 14 between sections; section =
`SectionCaption` 13 uppercase (padding 0 × 16) + gap 6 + card. Keyboard: system decimal pad for numbers
(`.keyboardType(.decimalPad)`), default keyboard with `.words` capitalisation for words.

### 5.1 Titles and word sections per kind

| Kind | Sheet title | Word sections (in order) |
|---|---|---|
| distanceA | `Long distance A` | `WHERE`: card with two rows (52 pt each, separator): label `From` 17 left + right-aligned TextField placeholder `Kitchen east wall`; label `To` + placeholder `Living west wall` |
| distanceB | `Long distance B` | same as A |
| ceilingHeight | `Ceiling height` | `ROOM`: one horizontally scrolling row of the floor's room chips (single select, 44 pt); when the capture has no rooms, a card TextField placeholder `Room`. Then a card row label `Where in the room` + TextField placeholder `Optional` |
| opening | `Opening` | `ROOM` (as ceiling) · `WHICH OPENING`: card TextField placeholder `Entry door` |
| floorToFloor | `Floor to floor` | `WHERE`: card TextField 52 pt, prefilled `At the stair` (artboard example: `At the stair, Floor 1 landing to Floor 2 landing`), accessibility label `Where measured` |
| landmark | `Shared landmark` | `WHAT IT IS`: card TextField placeholder `Stair newel post` · `VISIBLE FROM`: wrapping chips of every non-exterior floor (multi-select, the pair's two floors preselected, at least 2) |

The pair of a floor-to-floor or landmark entry is the between-section it was opened from (the v1 "Upper floor"
picker is removed).

### 5.2 `MEASUREMENT` card (all kinds except landmark)

Card rows, top to bottom:

1. Padding 8 × 16: `SegmentedControl` with 3 segments **`mm`**, **`m`**, **`ft-in`** (this order; identifiers
   `entry.unit.mm`, `entry.unit.m`, `entry.unit.ftIn`).
2. Separator, then padding 12 16 12: value fields.
   - ft-in: a 2-column grid (1fr 1fr, gap 10) of two fields: **feet** (suffix `ft`, identifier `entry.feet`,
     accessibility label `Feet`) and **inches** (suffix `in`, `entry.inches`, `Inches`).
   - mm / m: one field spanning both columns, suffix `mm` / `m` (`entry.value`, label `Millimetres` / `Metres`).
   - Field: height 56, radius 12, fill ground #F5EFE6, padding 0 × 14, gap 8 between input and suffix; input
     Inter 26 ink; suffix Inter 15 muted. Border 1 #D9CCBC; the focused field 1.5 #1F2429; a field in error 1.5
     #8B2E2E.
3. Separator, padding 8 × 16: `SegmentedControl` **`Tape`** · **`Laser`** (`entry.method.tape|laser`). Not
   drawn: required because `measurement.method` is required by `field-controls.schema.json` (Eran accepted the
   Tape/Laser addition on 2026-10-17). Default: last used in this visit, else Tape.

Opening adds a second card captioned `HEIGHT · OPTIONAL` with value fields only (same unit as the width, no
segmented rows). The first card's caption for an opening is `WIDTH` instead of `MEASUREMENT`.

Default unit: last unit used in this visit; else `ft-in` when the capture's `units.display` is imperial (the
default) and `mm` when metric. Changing the unit **clears** the value fields (the operator types what the
instrument shows in that unit; nothing is converted silently).

The first value field is focused when the sheet opens on a kind whose words are prefilled or optional (floor to
floor, ceiling height with a chosen room); otherwise the first empty word field is focused.

### 5.3 Footnote under the card (13/17, padding 0 × 16)

| State | Text | Colour |
|---|---|---|
| No value yet | `Stored in mm. Shown in both units everywhere. Tape or laser only.` | muted |
| Valid value | `Stored as 3,061 mm. Shown in both units everywhere. Tape or laser only.` (`LengthFormatter.millimetres`) | muted |
| Invalid value | the error message (§5.4) | #8B2E2E |
| Distance B | prefix `At a right angle to A. ` before the text above | as above |
| Landmark (no card) | `Pick something you can see from both floors, for example the stair newel post.` | muted |
| Persist failure | `The measurement could not be saved: {reason}` (existing wording) | #8B2E2E |

### 5.4 Two-field feet and inches (FieldRules `MeasurementEntryDraft` v2)

```swift
public struct MeasurementEntryDraft: Hashable, Sendable {
  public var unit: EnteredUnit            // .mm, .m, .ftIn offered
  public var feet: String                 // ft-in only
  public var inches: String               // ft-in only
  public var value: String                // mm or m
  public var method: MeasurementMethod
  public var enteredText: String { get }  // what goes to the contract
  public var result: Result<ParsedLength, LengthParseError> { get }
  public var isEmpty: Bool { get }
  public var errorMessage: String? { get } // nil when empty or valid
  public var storedText: String? { get }   // "3,061 mm" when valid
  public func measurement(recordedAt:) throws -> FieldControls.Measurement
  public static func editing(_ m: FieldControls.Measurement) -> MeasurementEntryDraft
}
```

Rules:
- Both fields accept the decimal pad's characters; a comma is read as a decimal point (decimal pads in many
  locales show `,`). Surrounding spaces are trimmed.
- Feet must be a whole number (`^[0-9]{1,9}$`); otherwise error `Enter whole feet. Put the rest in inches.`
- Inches: a decimal (`10`, `0.5`, `10.25`, `.5`); otherwise `Enter inches as a number, for example 8 or 10.5.`
- `enteredText` (stored verbatim in `measurement.enteredText`, enteredUnit `ft_in`): both → `{feet}' {inches}"`
  (`10' 0.5"`), feet only → `{feet}'`, inches only → `{inches}"`. mm / m: the typed number without suffix
  (`3061`, `3.061`). Max 40 characters (`LengthParser.maximumTextLength`).
- Parsed with the existing `LengthParser.parse(enteredText, unit:)`: exact rational, at most 4 decimals of a mm,
  never rounded; its messages are kept (`Inches must be less than 12 when feet are given.`, `Too many decimal
  places. Enter what the tape or laser shows.`, `The measurement must be greater than zero.`, `The measurement is
  larger than 200 m.`). Examples: 10 ft + 0.5 in → 3060.7 mm (`Stored as 3,061 mm`); 24 + 8 → 7518.4; 36 + 10.5
  → 11239.5; 0 + 0.0625 → 1.5875.
- Edit prefill (`editing(_:)`): enteredUnit `ft_in` → feet and inches from the parsed rational (fractions written
  as terminating decimals: `10 1/2` → `10.5`, `1/16` → `0.0625`); `mm`/`m` → `value` = enteredText without a unit
  suffix; any other unit (`cm`, `in`, `ft`, never offered by the app) → empty fields in the default unit. Method
  from the measurement. New helper `LengthParser.feetAndInches(_ text: String) throws -> (feet: Int, inches:
  String)`.

### 5.5 Save / Cancel

- `Save` enabled when the kind's words are filled (distance: From and To; ceiling: a room; opening: room and
  label; floor to floor: location; landmark: label and ≥ 2 floors) **and** (except landmark) the value parses;
  opening height, when typed, must parse too.
- Save → `FieldControlsEditor.set…` on a copy → `persist(next.controls)` (the app's
  `FieldControlsFile.write`) → keep → dismiss. Editing an entry whose id would change (room, location, label
  edited) removes the old id first (`editor.remove(id:)`), all in the same copy. Any failure: nothing is kept,
  the sheet stays, the footnote shows the error.
- `Cancel` and swipe-down discard without asking.

### 5.6 `RECORDED …` list (multi-value kinds)

Above the word sections, when entries exist: caption `RECORDED ON FLOOR 1` (ceiling, openings) or `RECORDED
BETWEEN FLOOR 1 AND FLOOR 2` (landmarks); card rows (min 50): title = room (ceiling), `{room} · {label}`
(opening) or label (landmark); subtitle = location (ceiling, when set) or `{width} × {height}` (opening) or the
floors (landmark, `Floor 1, Floor 2`); trailing value `2,690 mm` / ft-in mono for ceiling; `Chevron`. Tapping one
loads it into the form; the sheet title becomes `Ceiling height · Kitchen` / `Opening · Entry door` / `Shared
landmark · Stair newel post`. A trailing `New` text button is not needed: Cancel and reopening starts a new entry.

---

## 6. S4 Before you leave (artboard 2d-4)

### 6.1 Layout

| Part | Spec |
|---|---|
| Nav | System back. Trailing text 13 muted: the HUB project name (`record.hub.projectName`, else `record.address.formatted` up to the first comma), e.g. `618 Valley Street` (identifier `checklist.property`). |
| Title | Large title **`Before you leave`** (§1.2) |
| Subtitle | 15/20 muted: `Photos and controls cannot be recovered later. Fix these now.` |
| Card | content padding 14 16 0, gap 10; one `GroupedCard` with the six rows below, separators 1 pt #E8DDD0. |
| Row | HStack gap 12, padding 8 × 16, min height **56** (no button) / **64** (with a trailing button); `StatusGlyph`; VStack gap 2: title Inter 17, detail 13 (muted when passed, #8B2E2E when blocking, #7A5214 when advisory); trailing `TintedRowButton` when listed below. Identifier `checklist.row.{itemId}`. |
| Footnote | gap 10 under the card, 13/17 muted, padding 0 × 16: `Red items block the package. The compass is recommended, not required.` |
| Primary | bottom, padding 12 16 + safe area: disabled `Fix 2 items to finish` (`Fix {n} item(s) to finish`, n = **blocking** failures only) / enabled `Finish capture` → `onFinish` (identifier `checklist.finish`). |

### 6.2 Rows (order and exact wording)

| # | `ChecklistItemID` | Title | Passed detail | Failing detail | Glyph when failing | Trailing action |
|---|---|---|---|---|---|---|
| 1 | `floorsLabeled` | `Every floor and area labeled` | `Floor 1, Floor 2` | gaps (existing texts) | ■ | — |
| 2 | `skippedRoomsRecorded` | **`Rooms not scanned recorded`** (was "Skipped rooms recorded") | `Primary closet · locked` (`{name} · {reason}`, joined `; `) or **`All rooms scanned`** (was "No rooms skipped") | `Record rooms not scanned, or confirm there are none` · `A room not scanned has no name` · `{room}: reason missing` | ■ | `All rooms scanned` (only when the gap `skippedRoomsNotRecorded` is present and `onConfirmNoRoomsSkipped` is given; identifier `checklist.allRoomsScanned`) |
| 3 | `photoPerRoom` | `A photo for every room` | `14 photos, 12 rooms covered` (existing) | `Bath 2 has no photo` (joined ` · `) | ■ | `Take photo` (`checklist.takePhoto`). Under the detail, passed or failing, when `onRenameRooms` is given: `InlineAction` `Rename rooms` (`checklist.renameRooms`) |
| 4 | `minimumControls` | `Minimum field controls` | manual: `All minimum controls recorded`; standard: `Measured by the LiDAR scan` / `Measured by the LiDAR scan · 3 tape or laser checks` (existing) | compact list §6.3, e.g. `Floor to floor · 1 of 2 landmarks · Floor 2 set` | ■ | `Add` (`checklist.addControls`) |
| 5 | **`compass`** (new) | `Compass reading` | `Floor 1 verified · Floor 2 verified` | §6.4, e.g. `Floor 1 verified · Floor 2 not read: its plan will say "not verified"` | ▲ (advisory, never blocks) | `Read` (`checklist.readCompass`) when `onReadCompass` is given and a capture is not verified; calls it with the first such capture id |
| 6 | `visitDetails` | `Device, mode, date, operator` | `Filled automatically` | existing gap texts | ■ | — |

"Take photo" opens the photo step for the first `roomWithoutPhoto` / `captureWithoutPhoto` gap (existing
`checklistTakePhoto`). "Add" calls `onAddControls(item)`; the app opens S2 and `focus(rowId:)` on the row of the
first gap (mapping in §9.5). Rows with an action keep their button in the passed state hidden (only failing rows
show "Take photo", "Add", "Read", "All rooms scanned").

### 6.3 Minimum field controls: compact gap wording (manual policy)

Gaps in **list order** (floor 1, between 1 and 2, floor 2, …), joined ` · `:

| Gap | Text (visit with one floor) | Text (more than one floor) |
|---|---|---|
| A, B and ceiling all missing on a floor | `Floor 1 set` | `Floor 2 set` |
| `missingDistance(axis)` | `Long distance A` | `Long distance A on Floor 2` |
| `missingCeilingHeight` | `Ceiling height` | `Ceiling height on Floor 2` |
| `missingFloorToFloor` | — | `Floor to floor` (two floors) · `Floor to floor between Floor 2 and Floor 3` (more than two) |
| `missingLandmarks(have, need)` | — | `1 of 2 landmarks` · `1 of 2 landmarks between Floor 2 and Floor 3` |

(The full `ChecklistGap.description` stays as is for errors and logs.)

### 6.4 Compass item (new)

Input per capture (all captures, exterior included, record order): `CaptureCompassStatus` (§9.4) =
`.verified`, `.approximate`, `.notVerified`, `.notRead`. Words: `verified`, `approximate`, `not verified`,
`not read`. Detail = `{label} {word}` joined ` · `, then a suffix:

- one capture not verified or not read → `: its plan will say "not verified"`; several →
  `: their plans will say "not verified"`;
- else one approximate → `: its plan will say "approx. north"`; several → `: their plans will say "approx. north"`;
- all verified → no suffix, item passed (● and muted detail).

Severity: advisory. The item never adds to `Fix {n} items`, never blocks `canFinish`, and `requireCanFinish()`
ignores it. Until `phone-capture` records the compass, every capture is `.notRead` (e.g. single floor:
`Floor 1 not read: its plan will say "not verified"`) and `Read` is hidden (callback nil).

---

## 7. S5 Rename rooms inside v2 (keep it working)

Entry points in v2: viewfinder `Rooms` (`photo.rooms`), labeling `More` → `Rename rooms` (`photo.renameRooms`),
Before you leave photo row `Rename rooms` (`checklist.renameRooms`). The app's `renameAction` and
`VisitModel.renameRooms` stay as they are (rename writes `room-names.json`, the capture models, relabels photos
and controls, updates the open photo model through `roomsRenamed`).

`RoomNamesSheet` restyled to the v2 sheet pattern (behaviour, `RoomNamingDraft`, identifiers unchanged):

- `SheetBar`: `Cancel` (`rooms.cancel`) · `Rename rooms` · `Save` (`rooms.save`, disabled while
  `!draft.canSave`). The Times 30 heading and the bottom "Save names" button go.
- Under the bar, 13/17 muted, padding 0 × 16: `The new name goes on the floor plan, the report and the photos
  already labeled with the old name.` A save error appears under it in #8B2E2E.
- Per capture (header only when more than one): caption `FLOOR 1` (13 uppercase). Per room: caption row (13
  muted `Scanned as Closet · 1.9 m²`, trailing `No photo yet` 13 #8B2E2E with the 7 pt dot), then a `GroupedCard`
  with the name TextField (52, Inter 17) and, after a separator, the quick-name chip row (horizontal scroll,
  padding 8 × 16, chips padding 12). Issue text (13 #8B2E2E) under the card; the card border turns 1.5 #8B2E2E.
- Keyboard handling (scroll the focused room above the keyboard, open at `focusRoomId`) is kept.

---

## 8. Number formats (FieldRules `LengthFormatter` v2)

Screens show ASCII marks and comma thousands (tokens: "mm with thousands separators (7,520 mm), feet-inches with
ASCII marks (24' 8"), both shown. Stored in mm."). Locale independent.

| Function | Rule | Examples |
|---|---|---|
| `millimetres(_:)` | whole mm, half away from zero, `,` every 3 digits, ` mm` | 7520 → `7,520 mm`; 3060.7 → `3,061 mm`; 914.4 → `914 mm`; 200000 → `200,000 mm` |
| `millimetreRange(_:_:)` | `{low}–{high} mm`, en dash U+2013, no spaces; equal after rounding → single | `2,690–2,740 mm`; (2690, 2690.2) → `2,690 mm` |
| `feetInches(_:)` | inches rounded to 0.1 (half away from zero) as a whole, then split; `{ft}' {in}"`; a trailing `.0` is dropped | 7518.4 → `24' 8"`; 11239.5 → `36' 10.5"`; 3060.7 → `10' 0.5"`; 7520 → `24' 8.1"`; 2490 → `8' 2"`; 1524 → `5' 0"`; 1.5875 → `0' 0.1"`; 303.8 (11.96 in) → `1' 0"`, never `0' 12"`; 2690 → `8' 9.9"` |
| `both(_:)` | `{mm} · {ft-in}` | `7,520 mm · 24' 8.1"` |

The design's "7,520 mm / 24' 8"" pair is illustrative (7,520 mm is 24' 8.06"); the rule above is binding. Tenths
match `PlanExport.UnitFormatter.feetInchesTenths` except the dropped `.0` (screen only).

---

## 9. Logic and types (FieldKit)

### 9.1 New / changed in `FieldRules` (pure Swift, builds and tests on Linux)

| File | Change |
|---|---|
| `LengthFormatter.swift` | v2 formats (§8). |
| `MeasurementEntryDraft.swift` | two-field draft (§5.4); `ControlKind.rowTitle`: `Long distance A`, `Long distance B · at a right angle to A`, `Ceiling height`, `Openings · optional`, `Floor to floor`, `Shared landmarks`; `entryTitle`: `Long distance A`, `Long distance B`, `Ceiling height`, `Opening`, `Floor to floor`, `Shared landmark`; `UnitChoice.offered = [.mm, .m, .ftIn]`. |
| `LengthParser.swift` | + `feetAndInches(_:)` for edit prefill. Parsing rules unchanged. |
| **`ControlsList.swift`** (new) | `ControlsFloor` (ref, label, mode, capturedAt, rooms, scan), `ControlRow` (id, kind, target `.floor(id)` / `.pair(lower, upper)`, title, subtitle?, valuePrimary?, valueSecondary?, extraLine?, status `.done/.missing/.optional`, isCompact), `ControlSection` (id, header, rows), `ControlsProgress` (done, total, `text`), `ControlsList.sections(floors:controls:policy:)`, `ControlsList.progress(floors:controls:policy:)`, `ControlsList.rowId(for gap:)`. All of §4.2–4.4 lives here so it is unit-tested; FieldKitUI only renders. |
| `ChecklistRules.swift` | `ChecklistItemID.compass` (between `minimumControls` and `visitDetails`); `ChecklistItem.severity: .blocking | .advisory`; `ChecklistReport.canFinish` and `finishButtonTitle` count blocking failures only; titles/details per §6.2; `minimumControls` gaps emitted in list order (§6.3) and its detail uses the compact texts; `ChecklistInput.compass: [LowercaseUUID: CaptureCompassStatus]` (default empty = all `.notRead`). The manual-policy gate uses `ControlsList.progress` rules so S2 and S4 agree. |
| `PhotoLabelDraft.swift` | `directionSource: PhotoDirectionSource?`, `compassSuggestion: PhotoDirection?`, `directionTouched: Bool`; `mutating applyCompass(_:)`, `mutating chooseDirection(_:)` (§9.3); `labels(takenAt:)` includes `directionSource` (`.manual` when nil and a direction is set); `forNextPhoto()` keeps the room only; `PhotoSubject.primaryChoices` = all seven in the order Opening, Cabinetry, Ceiling, Fixture, Defect, General, Equipment; `moreChoices` removed. |
| **`CompassDirection.swift`** (new) | `HeadingSource`, `PhotoHeadingSample`, `CameraAxis.sample(rotationMatrix:accuracy:source:at:)`, `PhotoDirection.fromCompass(_:now:)` (§3.6). |
| **`PhotoStrip.swift`** (new) | §3.5 selection and text. |
| **`CaptureCompassStatus.swift`** (new) | `enum CaptureCompassStatus { case verified, approximate, notVerified, notRead }` + `CompassSummary.detail(captures:statuses:)` (§6.4) + `CompassSummary.short` (`Floor 1 verified · Floor 2 not read`, for `phone-capture`'s overview row). |
| `RoomChips.swift` | `shownBeforeMore = 4`; `primary(_:target:)` also keeps the currently selected room visible (pass it as `target`). |
| `NoRoomsSkippedConfirmation.swift`, `PhotoCoverage.swift`, `RoomNamingDraft.swift`, `FieldControlsEditor.swift`, `ScanMeasurements.swift` | unchanged. |

### 9.2 `PhotoStore`

`PhotoRecordStore.save(...)` stores the labels with `directionSource` (comes in `PackageManifest.PhotoLabels`).
`photo-records.json` written before this change decodes unchanged (`directionSource` absent → nil). Relabel and
restore keep `directionSource` untouched.

### 9.3 Direction source rules

- `applyCompass(d?)`: if `d` non-nil → `direction = d`, `directionSource = .compass`, `compassSuggestion = d`,
  `directionTouched = false`; if nil → `direction = nil`, `directionSource = nil`.
- `chooseDirection(d)`: if `d == direction && directionSource == .compass && !directionTouched` → no change;
  else `direction = d`, `directionSource = .manual`, `directionTouched = true`.
- Saved label: `directionSource = .compass` only when the saved direction is the untouched compass suggestion.

### 9.4 Compass status per capture

Computed by the app from the capture record with the **shared evaluator** owned by `phone-capture` / contract
(north-arrow v2 thresholds: verified = true heading and accuracy ≤ ±10°; approximate = accuracy ±10–30° or magnetic
heading only; not verified = no reading, accuracy worse than ±30°, or rejected) and mapped to
`CaptureCompassStatus`: no compass fields → `.notRead`; evaluator "not verified" with a reading → `.notVerified`.
FieldRules does not duplicate the thresholds.

### 9.5 Gap → row mapping for "Add"

`missingDistance(capture, axis)` → `controls.row.{areaKey}.distanceA|distanceB`; `missingCeilingHeight` →
`.ceilingHeight`; `missingFloorToFloor(lower, upper)` → `{lower}~{upper}.floorToFloor`; `missingLandmarks` →
`{lower}~{upper}.landmarks`. Gap labels are resolved to area keys through the record (labels are unique per
visit; if not, the first match).

### 9.6 `FieldKitUI`

| File | Change |
|---|---|
| `FieldTheme.swift` | §1 tokens; Inter / Times / mono fonts with Dynamic Type. |
| `Components.swift` | §1.3 components; `OutlineButton` removed (replaced by `TintedRowButton`); `fieldBox` replaced by card rows; `fieldScreen()` side padding 16. |
| `PhotoLabelingModel.swift` | inject `heading: PhotoHeadingProviding?`; `takePhoto()` samples the heading first, then `draft.applyCompass`; `pendingFormat`, `takenAtText`, `strip` (PhotoStrip), `directionCaption`, `saveAndFinish() -> Bool`; titles per §3.1–3.2; default room per §3.2; remove `showsAllRooms`, `showsMoreSubjects`, `coverage` line text use on the labeling screen (keep `coverage` for chips and the viewfinder). |
| `PhotoLabelingView.swift` | rewrite per §3.2, S1b and S1c. |
| `PhotoCaptureFlowView.swift` | pass the heading provider; start/stop it with the viewfinder; nav bar hidden for the viewfinder, inline for labeling. |
| `PhotoViewfinder.swift` | §3.1. |
| **`RoomPickerSheet.swift`** (new) | S1b. |
| **`PhotoStripView.swift`**, **`ThumbnailCache.swift`** (new) | §3.5. |
| **`DeviceCameraHeading.swift`** (new) | §3.6 provider (CoreMotion + CoreLocation). |
| `FieldControlsModel.swift` | renders `ControlsList`; owns the sheet state (`activeRow`, `editingId`, word fields, `MeasurementEntryDraft`, landmark floors), `focus(rowId:)`, `saveEntry()` (remove-then-set on id change), last unit / method memory; `ControlRowContent` removed. |
| `FieldControlsView.swift` | rewrite per §4. |
| **`ControlEntrySheet.swift`** (new) | S3. |
| `BeforeYouLeaveView.swift` | rewrite per §6 (new init with `headerCaption`, `onReadCompass`). |
| `RoomNamesSheet.swift` | §7. |
| `FieldCaptureOption.swift` | + `displayUnits: DisplayUnitSystem` (default unit in S3) and a `controlsFloor` adapter to `ControlsFloor`. |
| `CameraEngine.swift` | unchanged. |

---

## 10. D2 Contract change: manifest 1.1.0 `photo.directionSource`

`contract/schema/manifest.schema.json`:

```jsonc
"schemaVersion": {
  "description": "1.1.0 adds the optional photo.directionSource; a 1.0.0 document does not carry it. Readers accept both versions; writers write 1.1.0.",
  "enum": ["1.0.0", "1.1.0"]
},
// $defs.photo.properties, added:
"directionSource": {
  "description": "How direction was set. compass: pre-filled from the phone's compass when the photo was taken and kept by the operator. manual: chosen or changed by the operator. Absent in 1.0.0 documents.",
  "enum": ["compass", "manual"]
}
```

(`photo.required` unchanged: room, direction, subject, takenAt. `additionalProperties: false` stays.)

Swift (`contract/swift`): `ManifestSchemaVersion` (`v1 = "1.0.0"`, `v1_1 = "1.1.0"`, `current = .v1_1`) replaces
`SchemaVersion` in `PackageManifest` (decode both, always encode 1.1.0, same pattern as
`CaptureModelSchemaVersion`); `public enum PhotoDirectionSource: String, Codable, CaseIterable, Sendable { case
compass, manual }`; `PackageManifest.PhotoLabels.directionSource: PhotoDirectionSource?` (omitted when nil); README
table updated. TS (`contract/ts`): regenerate `src/generated/manifest.ts`, `schemas.ts`, `constants.ts`
(`npm run generate`). Examples: `contract/examples/manifest/valid/photo-direction-source.json` (1.1.0, one photo
`compass`, one `manual`), `contract/examples/manifest/invalid/unknown-direction-source.json` (`"directionSource":
"gps"`), `contract/examples/manifest/invalid/direction-source-wrong-type.json` (`true`). Existing 1.0.0 examples stay
valid.

Writers: `VisitPackageBuilder` copies `photo.labels` as today, so photos carry `directionSource`; the manifest is
written as 1.1.0 by `PackageAssembler` through the Swift type (`phone-package` area owns assembly; this is a
one-line consequence, no new code there beyond tests).

Deploy order: station (api, checks, worker, hub) with the regenerated contract **before** the app build that
writes 1.1.0 (same rule as capture model 1.1.0). Readers that ignore the field need no change. Coordinate the
version bump with `phone-capture`'s capture-record 1.1.0 (compass fields): one contract release, one station
deploy.

Not changed: `field-controls.schema.json` (two-field entry composes `enteredText` like `10' 0.5"` with
`enteredUnit: "ft_in"`; method stays required), `capture-record.schema.json` (compass fields are `phone-capture`'s).

---

## 11. Data sources and what is not available

| Shown | Source | When not available |
|---|---|---|
| Photo number, capture label | `PhotoRecordStore.nextSequence`, `CaptureRecord.Capture.label` | — |
| HEIC / JPEG | `PhotoFormat.detect(pendingOriginal)` | hidden |
| Time on the photo | `takenAt` (set when the camera returns) | — |
| Room chips | `VisitRooms.labels(of:)` (renamed labels) | only `More`; S1b offers "Other room" |
| Needs-photo dots, "No photo yet" | `PhotoCoverage` | — |
| Compass pre-fill | `DeviceCameraHeading` at the shutter | no pre-fill; caption `· no compass reading, choose one` |
| Photo strip | saved `PhotoRecord`s of the capture + original bytes for thumbnails | grey placeholders; text still correct |
| Field controls values | `FieldControls` (field-controls.json) | `Missing` (manual) / `Optional` (standard) |
| Scan values (standard policy) | `ScanMeasurements(model:)` | row shows `Optional` |
| Progress `4 of 9 required` | `ControlsList.progress` | — |
| Property caption on S4 | `record.hub.projectName` → `address.formatted` first part | address first part |
| Compass statuses | capture-record compass fields via the shared evaluator (`phone-capture`) | every capture `.notRead`; `Read` hidden |
| "Read" | `onReadCompass` from `phone-capture` | hidden |

---

## 12. Removed

- v1 inline "New measurement" card, unit menu ("ft-in ▾"), "Save measurement" button, floor picker, "Upper floor"
  picker, Times 30 headings, separate bordered checklist cards with 2 pt red borders, `OutlineButton`, subject
  `More…`, room `More…` in-place expansion, "Still needs a photo" line on the labeling screen, "Original kept"
  header text (moved into the photo pill), `″ ′ ½ ⟂ →` glyphs on these screens, `FieldTheme.primaryHeight = 56`.
- `VisitView`'s "Continue" overlay on Field controls (after `phone-capture` lands; §2 fallback until then).

---

## 13. Dependencies on other areas

| Area | What this area needs | If it is late |
|---|---|---|
| `phone-capture` | (a) Capture overview + `NavigationStack` visit navigation (push/pop of S1, S2, S4, origin-aware "Done"); (b) compass recorded at scan start (capture-record fields `heading`, `headingAccuracy`, `headingSource`, `headingRecordedAt`) and the shared 3-state evaluator; (c) location When-In-Use permission (true north for D1); (d) optional post-scan compass reading for `Read`; (e) app-wide Inter registration (`UIAppFonts`: `Inter-Regular.ttf`, `Inter-SemiBold.ttf`, full Latin static instances generated by `tools/brand/generate_plan_brand.py` from the same Inter variable font, OFL notice) and the global Times large-title / Inter inline-title `UINavigationBarAppearance` | (a) §2 fallback; (b) compass row shows "not read"; (c) magnetic pre-fill; (d) `Read` hidden; (e) this area adds the fonts and Info.plist keys itself (files listed in §14) |
| contract (whoever owns `contract/`) | manifest 1.1.0 release combined with capture-record 1.1.0 | this area makes the manifest change (§10) |
| `phone-package` | manifest written as 1.1.0 with `directionSource`; Package ready counts "9 controls" from `FieldControls` | none for this area |
| `spatial-report` | may print `looking N` (and "up" for ceiling photos, Q6) from the manifest labels; may mark compass-set directions | none |

---

## 14. Files touched

FieldKit: `Package.swift` (new iOS-only test target `FieldKitUISnapshotTests`), `README.md`;
`Sources/FieldRules/{ChecklistRules,LengthFormatter,LengthParser,MeasurementEntryDraft,PhotoLabelDraft,RoomChips}.swift`
(changed), `Sources/FieldRules/{ControlsList,CompassDirection,PhotoStrip,CaptureCompassStatus}.swift` (new);
`Sources/PhotoStore/PhotoRecordStore.swift` (labels pass-through, doc);
`Sources/FieldKitUI/{FieldTheme,Components,PhotoLabelingModel,PhotoLabelingView,PhotoCaptureFlowView,PhotoViewfinder,FieldControlsModel,FieldControlsView,BeforeYouLeaveView,RoomNamesSheet,FieldCaptureOption}.swift`
(changed), `Sources/FieldKitUI/{RoomPickerSheet,PhotoStripView,ThumbnailCache,DeviceCameraHeading,ControlEntrySheet}.swift`
(new); tests in §15.

App: `ios/App/Sources/App/Views/VisitView.swift`, `ios/App/Sources/App/VisitModel.swift` (heading provider,
compass statuses into `ChecklistInput`, `headerCaption`, `focus` on Add, default room, callbacks),
`ios/App/Sources/App/AppModel.swift` (`AppServices.photoHeading: (@MainActor () -> PhotoHeadingProviding?)`),
`ios/App/Sources/App/Debug/UITestEnvironment.swift` (fixed heading 85°, ±8°, true; `UITestViewfinder` v2),
`ios/App/Sources/App/Debug/FieldTestEnvironment.swift` (live heading), `ios/App/UITests/ReplayFlowUITests.swift`,
`ios/App/AppCore/Tests/AppCoreTests/PackagePipelineTests.swift`. Only if `phone-capture` does not:
`ios/App/Resources/Info.plist` (`UIAppFonts`), `ios/App/Resources/Fonts/Inter-Regular.ttf`,
`ios/App/Resources/Fonts/Inter-SemiBold.ttf`, `ios/App/Resources/Fonts/OFL.txt`, `ios/project.yml` (resources),
`tools/brand/generate_plan_brand.py` (write the app fonts).

Contract: `contract/schema/manifest.schema.json`, `contract/swift/Sources/CaptureContract/{PackageManifest,Enums}.swift`,
`contract/swift/README.md`, `contract/swift/Tests/CaptureContractTests/{SchemaParityTests,RoundTripTests}.swift`,
`contract/ts/src/generated/{manifest,schemas,constants}.ts`, `contract/ts/test/examples.test.ts`,
`contract/examples/manifest/valid/photo-direction-source.json`,
`contract/examples/manifest/invalid/{unknown-direction-source,direction-source-wrong-type}.json`.

Docs: `docs/waves/design/DESIGN.md` (F5 screens now v2; phone type Inter, display Times), `docs/waves/specs/F5.md`
(AC5 → v2 screens; compass item; manifest 1.1.0).

---

## 15. Test plan and acceptance criteria

### 15.1 Unit tests (Linux and macOS, `swift test`)

FieldRulesTests:
- `LengthFormatterV2Tests`: every example of §8 (incl. `3,061 mm`, `2,690–2,740 mm`, `10' 0.5"`, carry `1' 0"`).
  The v1 assertions in `ControlsUnitTests` (`7 518 mm`, `24′ 8″`, `36′ 10½″`, `2 690 – 2 740 mm`, `0′ 0 1/16″`)
  are replaced by the v2 strings.
- `MeasurementEntryDraftTests` (replaces the ft-in parts of `ControlsUnitTests`): two-field composition
  (`10`+`0.5` → `10' 0.5"` → 3060.7 mm exactly; feet only; inches only `96` → 2438.4; comma decimal `0,5`;
  feet `10.5` → `Enter whole feet. Put the rest in inches.`; inches `12` with feet → `Inches must be less than 12
  when feet are given.`; `0.00001` → too precise; mm `3061`; m `3.061`); `editing(_:)` round trips for
  `24' 8"`, `36' 10 1/2"`, `36-10 1/2`, `3061`, `3.061`, and `cm` → empty; each saved measurement validates
  against `field-controls.schema.json`.
- `ControlsListTests`: the artboard scenario (2 floors; floor 1 A 7520 / B 11240 / 3 ceilings 2690–2740 / 2
  openings; 1 landmark; floor 2 empty) gives exactly the section headers, row titles, subtitles, values, status
  and compactness of §4.2 and progress `4 of 9 required`; one floor → `3 of 3`; three floors → headers interleave;
  exterior excluded; standard policy → no `.missing`, scan subtitles, `Optional`; rename of a room flows into
  ceiling rows (existing rename tests still pass).
- `ChecklistV2Tests` (extends `ChecklistRulesTests`): titles of §6.2; compact detail `Floor to floor · 1 of 2
  landmarks · Floor 2 set`; gap order by list; `finishButtonTitle` `Fix 2 items to finish` with the compass not
  verified; compass detail strings (all verified; one not read; two not read → "their plans"; one approximate →
  `approx. north`; mixed); compass never blocks `canFinish` / `requireCanFinish`; `All rooms scanned` detail;
  standard policy unchanged.
- `CompassDirectionTests`: `CameraAxis.sample` for upright phone facing N/E/S/W (azimuth 0/90/180/270 ±0.01),
  flat phone (horizontal 0 → no direction), 70° up (no direction); `fromCompass` boundaries 44.9 → N, 45 → E,
  314.9 → W, 315 → N; accuracy 30 → value, 30.1 → nil, nil → nil; stale (2.1 s) → nil; magnetic accepted.
- `PhotoLabelDraftTests`: §9.3 source rules; `forNextPhoto` keeps room only; labels carry the source; seven
  subjects in order.
- `PhotoStripTests`: §3.5 texts (`1 photo …`, `5 photos …`, no room), last-4 selection, case-insensitive room
  match.
- `RoomChipsTests`: 4 shown; selected room beyond 4 is appended.

PhotoStoreTests: `directionSource` persists in `photo-records.json`; a pre-change index (no field) loads;
labels with `directionSource` validate against `manifest.schema.json#/$defs/photo`; relabel keeps the source;
original bytes and SHA-256 unchanged (existing AC3).

Contract: `swift test --package-path contract/swift` (`SchemaParityTests` covers `ManifestSchemaVersion` and
`PhotoDirectionSource`; `RoundTripTests` re-encodes the new example; a 1.0.0 manifest comes back as 1.1.0 with no
other change); `npm test --workspace contract/ts` (examples valid/invalid).

AppCore: `PackagePipelineTests`: a sealed visit's manifest is 1.1.0, validates against the schema, and each photo
entry carries the `directionSource` it was saved with.

### 15.2 Snapshot / visual (iOS simulator, iPhone 17 Pro, 402 × 874 pt @3x, light, Dynamic Type L)

New test target `FieldKitUISnapshotTests` (files wrapped in `#if canImport(UIKit)`, so Linux builds an empty
target): renders views with `ImageRenderer` inside a `NavigationStack` and compares with reference PNGs in
`Tests/FieldKitUISnapshotTests/__Snapshots__/` (fail when more than 0.5 % of pixels differ by more than 8/255 in
any channel; write `*.actual.png` on failure as an attachment). Fixtures reproduce the artboards' states:

1. Label a photo: 618 Valley Street, Floor 1, Photo 14, HEIC, 12:41, rooms Kitchen (selected) / Living / Bath 1
   / Bedroom 1 / More, E from the compass, Cabinetry, 4 saved Kitchen photos → `5 photos in Kitchen · …`.
2. Same with no compass reading (caption `· no compass reading, choose one`, no direction, hint `Choose Looking
   toward and Subject to save.`, buttons disabled).
3. Field controls, manual policy: the §15.1 scenario (`4 of 9 required`).
4. Field controls, standard policy, same data.
5. Entry sheet: Floor to floor, ft-in, 10 / 0.5, Tape → `Stored as 3,061 mm. …`.
6. Entry sheet error: feet 10, inches 12.
7. Before you leave: 2 failing + compass ▲ + `Fix 2 items to finish`.
8. Before you leave all passed, compass verified, `Finish capture`.
9. Rename rooms sheet (v2 bar), one room with `No photo yet`.
10. Room picker sheet.

References are recorded once, then reviewed side by side with artboard 2d at the same scale (design-fidelity
F5.AC5 now points at 2d). The same tests at Dynamic Type AX3 must show no clipped text (separate references).

### 15.3 UI tests (`ReplayFlowUITests`, simulator replay)

Update the existing flow to v2 (after `phone-capture`'s overview, or with the §2 fallback):
- The fixed heading provider (85°, ±8°, true) pre-selects `E` (`photo.direction.E` selected) with caption
  `… · from the compass, change if wrong`; tapping `N` changes the caption to `… · chosen by you`.
- Labeling title `Photo 1 · Floor 1`; `photo.format` = `JPEG` or `HEIC` per fixture; `photo.strip` =
  `1 photo in Shower · keep people and personal items out of the frame`.
- Rename from `More` → `Rename rooms` (`photo.renameRooms`) and from the checklist (`checklist.renameRooms`); the
  existing assertions on `rooms.name.room-1`, `rooms.suggest.room-1.Shower`, `rooms.save`, `rooms.needsPhoto.room-1`
  and the relabel-follows behaviour still pass.
- Field controls: tap `controls.row.floor-1.distanceA`, type From/To, `entry.feet` 12, `entry.inches` 4 →
  footnote `Stored as 3,759 mm. …`, Save; same for B (10 / 2) and ceiling (room chip Shower, 8 / 1); rows show
  `3,759 mm` / `12' 4"`.
- Before you leave: rows and texts of §6.2 (`Rooms not scanned recorded`, `All rooms scanned`, `Shower has no
  photo`, compass `Floor 1 not read: its plan will say "not verified"`), `Take photo` round trip, `Finish
  capture` enabled after fixes although the compass stays ▲.
- Fonts: in UI-test mode the app exposes a hidden element `debug.fonts` whose value is `ok` only when
  `UIFont(name: "Inter-Regular", size: 17)` and `UIFont(name: "Inter-SemiBold", size: 17)` exist; the test asserts
  `ok`.
- Screenshots attached for each v2 screen (design-fidelity evidence).

### 15.4 Device field test (iPhone Pro, on site or outdoors)

- Pre-fill correctness: 8 photos at known bearings (two per cardinal, each ≥ 20° from a sector boundary, bearing
  from a map street line) with location on → all 8 pre-filled correctly; with location off → magnetic, still
  correct where declination allows; pointing at the ceiling → no pre-fill.
- Originals: saved HEIC bytes equal the camera output (existing check); thumbnails appear within 300 ms.
- Decimal pad in a comma-decimal locale (e.g. German region) accepts `0,5`.

### 15.5 Acceptance criteria

```yaml criteria
AC1: {text: "Checklist v2 blocks only on blocking items, lists them in list order with the v2 wording, and the compass item never blocks", verify: "cmd:swift test --package-path ios/Packages/FieldKit --filter ChecklistV2Tests"}
AC2: {text: "Feet and inches typed as two fields are stored in mm exactly, with enteredText and enteredUnit ft_in, and validate against field-controls.schema.json", verify: "cmd:swift test --package-path ios/Packages/FieldKit --filter MeasurementEntryDraftTests"}
AC3: {text: "Field controls rows, values, statuses and the 'N of M required' counter match section 4 for the artboard scenario in both policies", verify: "cmd:swift test --package-path ios/Packages/FieldKit --filter ControlsListTests"}
AC4: {text: "Numbers read 7,520 mm, 2,690–2,740 mm and 36' 10.5\" (ASCII marks, comma thousands)", verify: "cmd:swift test --package-path ios/Packages/FieldKit --filter LengthFormatterV2Tests"}
AC5: {text: "Looking toward is pre-filled from the camera heading only with accuracy within 30 degrees and the camera within 60 degrees of horizontal; the saved label records compass or manual", verify: "cmd:swift test --package-path ios/Packages/FieldKit --filter 'CompassDirectionTests|PhotoLabelDraftTests'"}
AC6: {text: "A saved photo keeps its original bytes and its directionSource; old photo indexes still load", verify: "cmd:swift test --package-path ios/Packages/FieldKit --filter 'PhotoRecordTests|PhotoRelabelTests'"}
AC7: {text: "Manifest 1.1.0 with photo.directionSource is valid in Swift and TS; 1.0.0 manifests stay valid", verify: "cmd:swift test --package-path contract/swift && npm test --workspace contract/ts"}
AC8: {text: "A sealed package's manifest is 1.1.0 and every photo entry carries directionSource", verify: "cmd:swift test --package-path ios/App/AppCore --filter PackagePipelineTests"}
AC9: {text: "The four v2 screens and the three sheets match the reference snapshots reviewed against artboard 2d", verify: "cmd:xcodebuild test -scheme FieldKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:FieldKitUISnapshotTests (run from ios/Packages/FieldKit; ios.yml job FieldKit runs it)"}
AC10: {text: "The replay UI flow passes on v2: compass pre-fill, two-field entry, rename rooms from More and from the checklist, Before you leave with the compass item, Inter registered", verify: "cmd:scripts/wait-workflow.sh ios.yml App"}
AC11: {text: "FieldKit builds for iOS on the macOS runner and its pure targets test on Linux", verify: "cmd:scripts/wait-workflow.sh ios.yml FieldKit && scripts/swift-test.sh"}
```

---

## 16. Risks

| Risk | Mitigation |
|---|---|
| Policy conflict: v2 draws tape/laser controls as required and blocking; the code ships `ChecklistPolicy.standard` (scan provides them, decided 2026-10-18) | S2/S4 render both policies (§4.2); Q1 decides the shipping default; one constant to flip |
| Camera-axis convention wrong (transposed rotation matrix) → wrong pre-fill | one pure function with unit tests; device test §15.4 before release; operator can always change; caption says it came from the compass |
| Inter not registered → silent SF fallback | `debug.fonts` UI test; fonts generated and committed with the OFL notice |
| Times large titles via `UINavigationBarAppearance` are global and touch other screens | coordinate with `phone-capture` (§13 e); FieldKit sets nothing global |
| Two areas change navigation at once | FieldKit views are navigation-agnostic with callbacks; §2 fallback lets this area land first |
| Contract bump without station deploy → station rejects 1.1.0 manifests | deploy order in §10; release with `phone-capture`'s capture-record 1.1.0 |
| Intercepting Back on the labeling screen differs from the system back look on older iOS | custom leading button drawn as the pill (§1.3) |
| Decimal pad shows `,` in some regions | comma accepted as decimal point (§5.4), tested |
| Dynamic Type at accessibility sizes in fixed 44/52/56 controls | all heights are minimums; rows wrap; AX3 snapshots |
| HEIC thumbnail decoding cost on long visits | 120 px thumbnails off the main actor, in-memory cache, last 4 only |
| UI-test churn (identifiers and strings change) | identifiers listed in this spec; UI test updated in the same change |

---

## 17. Open questions (with recommended defaults)

| # | Question | Recommended default |
|---|---|---|
| Q1 | Are tape/laser field controls **required and blocking** (v2 drawing: "4 of 9 required", "Red items block the package", "Tape or laser only. Never copy numbers from the scan.") or **optional with the scan's values** (Eran's 2026-10-18 decision, `ChecklistPolicy.standard`, shipping today)? The bundle was drawn from the F5 spec of 2026-10-17 and does not mention the 10-18 decision. | Keep `ChecklistPolicy.standard` as the default (the later explicit owner decision); build both renderings; the drawn states appear when the policy is `.manualControls`. Ask Eran to confirm before release. |
| Q2 | Large titles ("Field controls", "Before you leave"): the bundle draws SF Bold 34/41; the owner says Inter replaces SF and "Times stays for display titles". | Times New Roman Regular 34/41 for large titles; Inter for everything else. Alternative: Inter Bold 34/41 tracking 0.4 (then add `Inter-Bold.ttf`). |
| Q3 | "Read" on the compass row after the floor was scanned: a heading read later cannot be tied to the scan's frame without relocalising or aligning to a known wall. | Hide `Read` unless `phone-capture` ships a post-scan reading (for example "hold the phone's edge against the highlighted wall"); the row still explains what the plan will say. |
| Q4 | Back on "Label a photo": the artboard links it to the Capture overview; the photo is unsaved. | Back asks `Discard this photo?` and returns to the viewfinder (retake); leaving the step is "Done with photos" or the viewfinder's "Done". |
| Q5 | How is "Before you leave" reached in v2? The overview lists most of the same items and its own button ("Fix 2 items to review the package"). | `phone-capture` makes the overview's "BEFORE YOU LEAVE" section header a tappable row with a chevron that pushes S4; the overview's button opens Package ready when nothing blocks. |
| Q6 | Ceiling photos: the contract allows only N/E/S/W, the spatial-report photo page draws "looking up" for a ceiling photo. | Phone unchanged (N/E/S/W required; no compass pre-fill when the camera points up); the report derives "up" from subject `ceiling` if it wants it. No contract change. |

---

## Addendum (completeness critique, Oct 21, 2026) — binding, overrides the body above

Numbers refer to `00-critique.md`. This area is built by track **T8 phone-field** (all of
`ios/Packages/FieldKit/**`); the App wiring of §2 and §14 (VisitView, VisitModel, AppModel,
UITestEnvironment, ReplayFlowUITests, Info.plist) is built by **T10 phone-app-shell**; the
manifest change of §10 by **T0 contract-and-fixtures**.

### B1. Fonts and tokens (R-17, R-18)
- Withdrawn: §1.2 "Inter must be registered in the app (`UIAppFonts`)", §13 row (e) fallback and
  the §14 files `ios/App/Resources/Fonts/*`, `UIAppFonts`, `project.yml` resources. Inter is
  registered by ChapterUI (`ChapterFonts.register()`, phone-capture §2.6).
- `FieldKit/Package.swift`: FieldKitUI depends on `ChapterUI` (`.package(path: "../ChapterUI")`);
  this area makes the change (phone-capture does not edit FieldKit).
- `FieldTheme.swift` becomes a façade over `ChapterTheme`; the extra styles of §1.2 that ChapterUI
  lacks (Section header 12 uppercase, Entry value Inter 26, Mono 13, Mono 11) are added to
  ChapterUI by T1 (listed in phone-capture addendum A8).
- Components: use ChapterUI's `ChapterButtonStyle(.primary/.tinted/.rowAction)`,
  `ChapterSegmented`, `ChapterSection` card, `StatusGlyph`, `Chevron`, `TextButton`, `ChoiceChip`,
  `SheetBar`, `SectionCaption`. FieldKitUI keeps only screen-specific views.
- Waiting glyph ○ (`Optional`): circle (5, 5) r 4, stroke **1.2** `#6B6557` (drawn in 2f).

### B2. Compass (R-2, R-3, R-21, R-22, R-23)
- `HeadingSource` in FieldRules is removed; `PhotoHeadingSample.source` is
  `CaptureContract.HeadingSource`.
- `CameraAxis.sample(rotationMatrix:accuracy:source:at:)` calls
  `CompassMath.cameraAxisInReference(rotationMatrix:)` (contract) and only adds the
  `horizontalComponent` / sample packaging; no matrix convention is repeated here.
- `DeviceCameraHeading` is **not built**. FieldKitUI keeps `PhotoHeadingProviding` and adds
  `FixedPhotoHeading` (tests, previews). The app passes compass's `CompassPhotoHeading` adapter
  (single `CompassService`).
- `CaptureCompassStatus` is mapped from the contract `CompassState`: `verified`, `approximate`,
  `notVerified` for reasons `inaccurate`/`rejected`, `notRead` for `no_reading`/`not_calibrated`/
  `unavailable` (compass §5.3).
- `CompassSummary` also exposes the overview status word (R-21): all verified `Verified`; all
  usable with ≥ 1 approximate `Approx.`; mixed `Partly`; none usable `Not verified`; plus
  `short` (`Floor 1 verified · Floor 2 not read`).
- Q3 is settled: `Read` stays hidden (the app passes `onReadCompass: nil`).

### B3. Before you leave entry and exit (R-39, G-4)
`BeforeYouLeaveView` gains `focus: ChecklistItemID?`: on appear scroll the row into view and fill
its background `#E8DDD0` for 0.6 s (ease-out back to clear; no animation with Reduce Motion).
The overview's Compass row passes `.compass`, its Rooms not scanned row `.skippedRoomsRecorded`.
`onFinish` is wired to `VisitFlow.reviewPackage(canFinish:)` (Package ready, or Revision n in
revision mode). Q5 is settled: Before you leave is reached from those overview rows and from the
"Fix" flow; no section-header tap is added to the overview.

### B4. Read-only after sealing (G-1, new)
Every screen of this area takes `isReadOnly: Bool` (true when the visit is sealed and not in
revision mode):
- Label a photo / viewfinder: not reachable; the overview's Photos row opens Before you leave
  (read-only) with `focus: .photoPerRoom` instead. Rename rooms: Save hidden.
- Field controls: rows open S3 with every field disabled and the bar's right action hidden.
- Before you leave: no trailing buttons; the primary button is replaced by the footnote.
- Footnote (13/17 muted, under the last card): `Revision {n} is sealed. To change it, use Add to
  this capture on the verdict screen.`
In revision mode the screens are editable; their changes become revision n+1.

### B5. Revision mode (G-5)
Before you leave applies to revision n+1 as to revision 1 (blocking items of the whole visit,
base captures included). Its primary button title stays `Fix {n} item(s) to finish` / `Finish
capture`.

### B6. Snapshot harness (R-18d)
§15.2's `ImageRenderer` is replaced by `ChapterUISnapshotTesting` (UIWindow + `drawHierarchy`):
the entry sheet (S3), room picker (S1b) and rename sheet (S5) contain `TextField`s that
`ImageRenderer` does not draw. Threshold unchanged (> 8/255 on ≤ 0.5 % of pixels).

### B7. UI-test hook (R-24)
The fixed heading 85° ±8 true comes from `FakeCompass` under `-ChapterUITestCompass verified`
(camera bearing script), not from a separate provider.

### B8. Contract (R-1)
§10 is built in T0 together with phone-package's manifest rule (same 1.1.0). `ManifestSchemaVersion`
is defined once. This area writes no contract file; its tests depend on T0.

### B9. `NoRoomsSkippedConfirmation` (G-13)
Gains `Codable` (additive; keys `confirmedCaptureIds`) for phone-capture's `visit.json`.

### B10. Policy (Q1 escalated as owner question Q-A)
Default unchanged (`ChecklistPolicy.standard`). `ControlsList.sections` is also the source of the
overview floor-row word (phone-capture addendum A6), so the two screens never disagree.

### B11. §2 fallback
The "Continue" toolbar fallback on Field controls is not needed when T10 lands after this track;
keep it behind `#if FIELD_V1_NAVIGATION` only if T8 must ship alone.
