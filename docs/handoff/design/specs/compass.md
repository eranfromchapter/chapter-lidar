# Build spec · compass · Compass reading and north arrow, end to end

Area key: `compass` (other specs call it `north-arrow` or "the shared evaluator owned by phone-capture"; it is
this spec). Artboards: **1d** `canvas/north-arrow-v2.dc.html` (to build; v1 `north-arrow.dc.html` is superseded),
compass parts of **2b** `canvas/app-capture-v2.dc.html` (panels 2, 3, 3b, 4), **2d** `canvas/app-field-v2.dc.html`
(panels 1, 4), **2f** `canvas/app-package-v2.dc.html` (Package ready), **1b** `plan-sheet-v2`, **1f–1i**
`report-cover-v2`, **1k–1l** `report-plan-v2`, **1p–1r** `report-checks-v2`, **2j** `web-review-v2`,
**2k** `screen-tokens-v2` ("New data"), `canvas/plan-parts.js` (`northArrow`), `canvas/sample-424.js` (rule
`orientation.compass`). Written Oct 21, 2026. The bundle does not need to be opened again.

Owner decisions applied (binding, Oct 21, 2026):

1. Inter everywhere (phone screens, plan sheet, spatial report, web). Every place the bundle says Helvetica for
   the north arrow (the "N", the captions, the not-verified box) is **Inter** (bold = Inter SemiBold 600, the
   weight PlanExport embeds). Times stays Times; mono stays mono. The arrow never sits next to the typed serif
   "chapter / RENOVATION" wordmark; logos are the real files (other areas).
2. Web review in the HUB design system, Inter, self-hosted fonts (texts for the web are in section 9).
3. Compass recorded at the start of each floor's scan, three states (verified / approximate / not verified),
   thresholds **±10° / ±30°** from the v2 north-arrow artboard (confirmed by Eran, Oct 20, 2026). Plan sheet made
   on the phone (no verdict); spatial report made on the station after checks.

Already in the repo and built upon (not undone): `FloorplanWriter` / `FloorPlanDrawing` (they already accept
`northDegrees` and draw a compass on the colour Floorplan), `ChapterBrand` colours and embedded Inter in
`PDFDocument`, room renaming, the scan browser (`tools/`, untouched: see 6.4).

---

## 0. Scope

| # | Piece | Where it shows | Owner of the host screen/page |
|---|---|---|---|
| C1 | Contract: compass fields in the capture record (1.1.0), the shared state evaluator, the shared texts | everywhere | this spec |
| C2 | Taking the reading on the phone: sensors, permission, pairing with ARKit, frame conventions | phone | this spec |
| C3 | "What are you scanning?" · Compass section | 2b panel 2 | `phone-capture` hosts, this spec defines the section |
| C4 | Live scan · compass chip | 2b panels 3, 3b | `phone-capture` hosts, this spec defines the chip |
| C5 | Capture overview · Compass row (+ Compass sheet) | 2b panel 4 | `phone-capture` hosts, this spec defines content |
| C6 | Before you leave · Compass reading item | 2d panel 4 | `phone-field` (spec §6.4); this spec supplies the evaluator |
| C7 | Photo "Looking toward" pre-fill | 2d panel 1 | `phone-field` (spec §3.6); this spec fixes the shared attitude convention |
| C8 | Package ready · "Capture record · compass: …" | 2f | `phone-package` (spec §3.3); this spec supplies the evaluator |
| C9 | North symbol (vector) and its placement on every drawn output | plan sheet, Floorplan, plan.png/svg, report cover, report plan | symbol: this spec; page layout: `plan-sheet`, `spatial-report` |
| C10 | Station: validation and the `orientation.compass` check | station, report checks page, web | this spec |
| C11 | Web review texts (Orientation, Compass rows) | 2j | `web-review` hosts |

Not in scope: plan.dxf, rooms.csv, meshes, LAS (they stay in the scan frame; north is metadata in the capture
record, see 6.5); `tools/scan-browser` and `tools/plan-render` (unchanged behaviour, see 6.4); typing or editing a
heading by hand (never allowed: "Never typed by hand or taken from a map"). The earlier plan item "manual north
override in the Rooms screen" (`docs/floorplan-report-plan.md`, phase 9) is withdrawn by this rule; update that
doc line.

---

## 1. The reading and the three states

### 1.1 What is recorded (per capture = per floor or area scan)

| Field (capture record) | Meaning |
|---|---|
| `heading` | Compass bearing of this capture's **−Z axis** (the direction that is "up" on an unrotated plan), degrees **clockwise from north**, `0 ≤ heading < 360`, one decimal. North is true north when `headingSource` is `true`, magnetic north when `magnetic`. |
| `headingAccuracy` | The phone's compass accuracy in whole degrees (the heading is within ± this), rounded **up**, `1…180`. |
| `headingSource` | `true` (corrected to true north with the phone's location) or `magnetic` (Location off: magnetic north only). |
| `headingRecordedAt` | UTC time (whole seconds) of the reading. |
| `headingIssue` | Only when there is no `heading` and the app tried: `rejected`, `not_calibrated` or `unavailable` (1.5). |

The four `heading*` fields are present together or not at all. "Missing field = state 3" (artboard). Nothing
about the phone's location is ever stored (latitude, longitude, altitude: not recorded, not logged).

### 1.2 State rules (one evaluator, phone and station)

Thresholds (constants, both languages): `VERIFIED_MAX = 10`, `APPROXIMATE_MAX = 30` (degrees, inclusive).

Evaluated in this order:

| # | Condition | State | Reason |
|---|---|---|---|
| 1 | no `heading`, `headingIssue` = `rejected` | not verified | `rejected` |
| 2 | no `heading`, `headingIssue` = `not_calibrated` | not verified | `not_calibrated` |
| 3 | no `heading`, `headingIssue` = `unavailable` | not verified | `unavailable` |
| 4 | no `heading`, no issue (1.0.0 record, older app, or no reading taken) | not verified | `no_reading` |
| 5 | `heading` present but `headingRecordedAt` outside `[capturedAt − 60 s, (finishedAt ?? capturedAt + 24 h) + 60 s]` | not verified | `rejected` |
| 6 | `headingAccuracy` > 30 | not verified | `inaccurate` (keeps the accuracy for the caption) |
| 7 | `headingSource` = `true` and `headingAccuracy` ≤ 10 | **verified** | — |
| 8 | otherwise (`true` and 11…30, or `magnetic` and ≤ 30) | **approximate** | — |

Boundary cases (test vectors, 13.1): true ±10 → verified; true ±11 → approximate; true ±30 → approximate; true ±31
→ not verified (inaccurate); magnetic ±1 → approximate; magnetic ±30 → approximate; magnetic ±31 → not verified.
Accuracy is an integer, so "between ±10° and ±30°" is 11…30.

"Until the compass feature ships, every output uses state 3": a 1.0.0 record (no fields) is rule 4 on every
output, phone and station alike.

### 1.3 Number formatting

| Token | Rule | Examples |
|---|---|---|
| `{HDG}` | the bearing being shown (see 2.5 for drawings), rounded half up to a whole degree, then `mod 360`; never "360" | 212.4 → `212`; 359.6 → `0`; 0.4 → `0` |
| `{ACC}` | `headingAccuracy` as stored (integer) | `8`, `18`, `42` |
| degree sign | U+00B0 `°`; plus-minus U+00B1 `±`; middle dot U+00B7 `·` (all in WinAnsi 0xB0, 0xB1, 0xB7, so the phone PDF writer prints them) | `±8° · 212°` |
| `{AGO}` | < 5 s: `just now`; 5–59 s: `{n} s ago`; 1–59 min: `{n} min ago`; else `over an hour ago`. Refreshed every second while shown. | `read 12 s ago` |

Never use U+2212 minus, `′ ″`, `≈` in any compass text (the phone PDF writer has no glyphs for them).

### 1.4 Shared texts (exact strings; one table used by phone, station and web)

Drawn outputs (the north symbol, section 6):

| State | Line 1 | Line 2 |
|---|---|---|
| verified | `True north · compass` | `±{ACC}° · {HDG}°` |
| approximate, source true | `Approx. north · compass` | `±{ACC}° · true` |
| approximate, source magnetic | `Approx. north · compass` | `±{ACC}° · magnetic` |
| not verified | box: `Orientation: not verified` | reason caption (below) |

Reason captions ("two or three words", artboard):

| Reason | Caption on drawings | Station detail / web phrase |
|---|---|---|
| `no_reading` | `No compass reading` | `No compass reading recorded; orientation not verified` |
| `rejected` | `Reading rejected` | `Compass reading rejected; orientation not verified` |
| `inaccurate` | `Compass accuracy ±{ACC}°` | `Compass accuracy ±{ACC}°; orientation not verified` |
| `not_calibrated` | `Compass not calibrated` | `Compass not calibrated; orientation not verified` |
| `unavailable` | `Compass unavailable` | `No compass on the device; orientation not verified` |

Station detail for usable states: verified `True heading {HDG}°, accuracy ±{ACC}°` (artboard text);
approximate `Approximate north: {true|magnetic} heading {HDG}°, accuracy ±{ACC}°`.

Verdict limitation (state 3, section 8): `Plan orientation is not verified; north is not shown.` (artboard text).

### 1.5 Why a reading is "rejected", "not calibrated", "unavailable"

| Issue | Set by the phone when |
|---|---|
| `unavailable` | `CLLocationManager.headingAvailable()` is false, or Core Motion device motion with a north reference frame is unavailable (`CMMotionManager.availableAttitudeReferenceFrames()` contains neither `.xTrueNorthZVertical` nor `.xMagneticNorthZVertical`). |
| `not_calibrated` | During the whole reading period every `CLHeading.headingAccuracy` was < 0 (invalid), or Core Motion's `magneticField.accuracy` stayed `.uncalibrated`. |
| `rejected` | At least one reading window was completed but every window failed the consistency test (3.3 step 5), or the frame check (3.4) found no consistent alignment. |
| (no issue, no heading) | Not enough valid samples were ever collected (for example the scan lasted under 3 s, or tracking never became normal). |

Precedence when several apply: `unavailable` > `not_calibrated` > `rejected`.

---

## 2. Rotation conventions (read before writing any code)

### 2.1 Frames

| Frame | Definition |
|---|---|
| **W**, ARKit world | The world frame of the floor's `ARSession` (`LiveCaptureSession.arSession`, shared by every RoomPlan segment of the floor). Right-handed, +Y up (RoomPlan runs it with gravity alignment). Origin and yaw are wherever the session started; **arbitrary with respect to north**. A new session (Try again, next floor) is a new W. |
| **C**, capture frame | The coordinates of `capture-model.json`: the RoomPlan geometry exactly as encoded (`CaptureModelMapper` copies coordinates, walk-through splitting included; it ignores `referenceOriginTransform`). **Expected C = W** (see 2.4). |
| **P**, plan frame | `Point2(x: C.x, y: −C.z)` (`PlanGeometry.swift`): seen from above, not mirrored; +y is "up the sheet" before any drawing rotation. |
| **D**, device (Core Motion) | +X right edge (portrait), +Y top edge, +Z out of the screen. |
| **K**, ARKit camera | `ARFrame.camera.transform`'s local frame: +X along the long axis from the front camera toward the bottom edge (= −Y_D), +Y = +X_D, +Z out of the screen (= +Z_D). |
| **N**, Core Motion reference | `.xTrueNorthZVertical` or `.xMagneticNorthZVertical`: +X north, +Y west, +Z up. |

### 2.2 Rotations (column vectors, `v_target = R_target←source · v_source`)

| Rotation | Value |
|---|---|
| `R_W←K` | upper-left 3×3 of `ARFrame.camera.transform` |
| `R_K←D` | rows `(0, −1, 0)`, `(1, 0, 0)`, `(0, 0, 1)` (so X_D = +Y_K, Y_D = −X_K, Z_D = +Z_K) |
| `R_N←D` | `transpose(CMDeviceMotion.attitude.rotationMatrix)` (the matrix maps reference to device; its rows are the device axes in reference coordinates; same convention as `phone-field` §3.6) |
| `R_W←D` | `R_W←K · R_K←D` |
| `R_N←W` | `R_N←D · transpose(R_W←D)` |

Runtime convention checks (every paired sample; `g_D` = `CMDeviceMotion.gravity`, unit vector toward the Earth
in D):

- `angle(R_N←D · g_D, (0, 0, −1)) ≤ 3°` (Core Motion convention)
- `angle(R_W←D · g_D, (0, −1, 0)) ≤ 3°` (ARKit camera to device mapping and timing)

A sample that fails either check is dropped; if more than 50% of samples in the first 10 s fail, log
`compass.convention_mismatch` (debug builds: `assertionFailure`). These checks make a transposed matrix or a wrong
K→D mapping impossible to ship silently.

### 2.3 Heading of the capture frame from one paired sample

```
v       = R_N←W · (0, 0, −1)                       // W's −Z axis in N
bearing = atan2(−v.y, v.x) in degrees, mod 360     // east = −v.y (N's +Y is west), north = v.x
H_W     = bearing                                  // true or magnetic, as the reference frame is
H_C     = (H_W + φ) mod 360                         // φ = frame yaw from 3.4, expected 0
```

`H_C` is what is stored as `heading`.

Camera bearing at any moment of the scan (used by the live chip, 5.2): `f = R_W←K · (0, 0, −1)`;
`ψ = atan2(f.x, −f.z)` in degrees (clockwise from W's −Z seen from above); valid when
`sqrt(f.x² + f.z²) ≥ 0.3`; camera bearing `= (H_W + ψ) mod 360`.

Photo camera bearing without ARKit (`phone-field`): `u = R_N←D · (0, 0, −1)` (back camera looks along −Z_D),
`azimuth = atan2(−u.y, u.x)`, valid when `sqrt(u.x² + u.y²) ≥ 0.5`.

**One implementation.** These functions live once, in `contract/swift/Sources/CaptureContract/CompassMath.swift`
(pure Swift, no simd, Linux-testable), because CaptureContract is the only module both CaptureCore and FieldKit
depend on. `phone-field`'s `CameraAxis.sample(rotationMatrix:)` must call
`CompassMath.cameraAxisInReference(rotationMatrix:)` instead of repeating the matrix convention.

### 2.4 Capture frame vs ARKit world: what is known and what must be verified

Known from the repo: the mapper writes RoomPlan's encoded coordinates unchanged; the fixture generator, modelled
on two real iPhone 17 Pro Max exports, puts the floor at y = −1.31 m in the capture frame ("the phone started the
scan 1.31 m above the floor"), i.e. the origin is the phone at session start, as for W; and it models
`referenceOriginTransform` as a separate yaw (37°) and offset that the geometry does not use. So **C = W is the
working assumption** and φ is expected to be 0.

Not proven: whether RoomPlan's post-processing (`RoomBuilder`, `StructureBuilder` for paused-and-resumed scans)
can rotate the final geometry relative to the live session. Two safeguards:

1. **Device test D1 before any UI work** (13.5). If D1 shows C ≠ W by a consistent rotation, set the documented
   convention in `CompassMath.captureFrameYaw` (for example "C = referenceOriginTransform⁻¹ · W") and add the D1
   recording as a unit-test fixture.
2. **Frame check at Finish floor** (3.4): matches surfaces of the last live update with the final result and
   applies a measured φ when there is a consistent one.

Side note for `spatial-report` / station: if D1 finds C ≠ W, today's `points.las` (built from depth samples in W)
and `camera-poses` are also not in the capture model's frame. Report it; do not fix it in this area.

### 2.5 From heading to the arrow on a drawing

North lies at angle `H_C` **counter-clockwise** from P's +y (derivation: P's +y has bearing `H_C`; a direction of
bearing `b` is `b − H_C` clockwise from +y; north `b = 0` is therefore `H_C` counter-clockwise). This equals
FloorplanWriter's existing `northDegrees` ("degrees counter-clockwise from the plan's +y axis"), so
**`northDegrees = heading`** with no conversion.

A drawing that shows P turned counter-clockwise by `ρ` degrees draws north at

```
A = (H_C + ρ) mod 360        // counter-clockwise from "up" on the page
```

- Station spatial report (plan drawn in P, never rotated): `ρ = 0`, `A = H_C`.
- `FloorPlanDrawing` (turns the plan to square walls with the sheet, plus quarter turns): `ρ = −rotationDegrees`,
  so `A = H_C − rotationDegrees` (exactly what its code does today: `(0, 1).rotated(by: north − theta)`).
- Any other renderer: `ρ` is whatever turn it applied to P; never turn a plan to put north up ("The plan is never
  rotated: it stays in the scan frame and the arrow turns by −heading"). Squaring a plan to the sheet is allowed;
  the arrow absorbs it.

`A` is also the bearing of "up" on that drawing, and **the caption's `{HDG}` is `A`** (equal to the stored heading
on an unrotated plan). Rendering: rotate the symbol counter-clockwise by `A` about its box centre. In SVG/CSS
(y down): `rotate(−A deg)`. In PDF and PlanExport primitives (y up): `+A`.

Worked examples (unit tests, 13.1):

| `H_C` | `ρ` | `A` | Arrow tip on the page | Caption line 2 (verified, ±8) |
|---|---|---|---|---|
| 0 | 0 | 0 | straight up | `±8° · 0°` |
| 90 | 0 | 90 | left (scan −Z points east, so north is to its left) | `±8° · 90°` |
| 212.4 | 0 | 212.4 | down and 32° toward the right | `±8° · 212°` |
| 90 | −30 | 60 | up-left, 60° from up | `±8° · 60°` |
| 359.7 | 0 | 359.7 | up (0.3° right) | `±8° · 0°` |

Multi-floor pages: every floor uses its own `heading` and its own `ρ`. Floors are never rotated to match each
other (v2 rule; the v1 rule "floors are rotated to match" is withdrawn).

---

## 3. Phone: taking the reading

### 3.1 Sensors and permission

- **Core Motion**: `CMMotionManager.startDeviceMotionUpdates(using:to:withHandler:)` at 60 Hz with
  `.xTrueNorthZVertical` when it is in `availableAttitudeReferenceFrames()` **and** location authorisation is
  When-In-Use or Always; else `.xMagneticNorthZVertical`. The frame chosen sets `headingSource` (`true` /
  `magnetic`). If authorisation changes during a reading, restart device motion with the new frame and start a new
  window (3.3). Same rule as `phone-field`'s photo heading provider.
- **Core Location**: one `CLLocationManager` (`CompassService`, 3.5). `startUpdatingHeading()`
  (`headingFilter = kCLHeadingFilterNone`) for `headingAccuracy` (and the phone's heading on the pre-check card).
  While authorised, `startUpdatingLocation()` with `desiredAccuracy = kCLLocationAccuracyThreeKilometers`,
  `distanceFilter = 1000`, only while a compass consumer is active, so true north is available; the location
  values are discarded. `locationManagerShouldDisplayHeadingCalibration` returns false (the card shows our own
  hint).
- **Permission**: requested once with `requestWhenInUseAuthorization()` when the "What are you scanning?" screen
  first appears and status is `.notDetermined`. Never requested elsewhere (photos and the live scan only use what
  is granted). Reduced ("approximate") location is enough.
- **Info.plist** (`ios/App/Resources/Info.plist`), new key `NSLocationWhenInUseUsageDescription`:
  `Chapter Capture uses your location only to turn the compass into true north on the plans. Your location is not saved.`
- No new `UIRequiredDeviceCapabilities` (every LiDAR iPhone and iPad has a compass; `unavailable` covers the rest).

### 3.2 Pre-check on "What are you scanning?" (before Start scan)

Purpose: show the operator the compass health and let them fix it (move away from steel, calibrate, turn
Location on) before scanning. **The pre-check is not stored**: a reading taken before the ARSession exists cannot
be tied to the scan frame; the stored reading is taken in the first seconds of the scan (3.3).

- Starts automatically when the screen appears ("Read automatically"), and again on `Read again`.
- Collects `CLHeading` updates for 2.0 s. Result = last valid sample's heading (`trueHeading` if ≥ 0, else
  `magneticHeading`; the source follows), accuracy = **maximum** valid `headingAccuracy` in the 2 s, rounded up.
- No valid sample (accuracy < 0) within 5 s → result `not_calibrated`. `headingAvailable()` false → `unavailable`.
- Classified with the 1.2 thresholds (verified / approximate / inaccurate). Stops heading updates afterwards.
- `readAt` = end of the 2 s window; `{AGO}` counts from it.

### 3.3 Scan-start reading (stored)

Runs inside `LiveCaptureSession` (it owns the `ARSession`), from `start()` until `finish()`/`cancel()`.

1. **Clock.** Core Motion samples go into a ring buffer (last 1.0 s). Every existing 4 Hz tick
   (`LiveCaptureSession.tick`) takes `arSession.currentFrame` and the motion sample nearest to `frame.timestamp`
   (both clocks are seconds since boot). Pair only if `|Δt| ≤ 0.025 s`.
2. **Gate each pair.** `frame.camera.trackingState == .normal`; `|rotationRate| < 0.35 rad/s` (20°/s); both
   gravity checks (2.2); latest `CLHeading` younger than 2 s with `headingAccuracy ≥ 0`;
   `magneticField.accuracy != .uncalibrated`. Dropped pairs are counted per reason (debug log only).
3. **Window.** 8 consecutive valid pairs within 3.0 s (a gap > 1 s or an invalid pair restarts the window).
4. **Window value.** `H_W` = circular mean of the 8 bearings (2.3); `spread` = largest angular distance of a
   bearing from the mean; `accuracy` = ceil(max `headingAccuracy` over the window), minimum 1; `source` from the
   reference frame in use; `recordedAt` = UTC of the window's last pair, whole seconds.
5. **Consistency test.** Reject the window if `spread > max(5, accuracy)` degrees (the compass moved while the
   phone did not: magnetic disturbance or bad pairing). Rejected windows are counted.
6. **Best window.** Keep the best accepted window: state class first (verified > approximate > not verified), then
   lower accuracy, then later time. Stop early as soon as a **verified** window is accepted.
7. **Start period.** The attempt runs for the first **30 s of running time** (paused time not counted). If no
   verified window has been accepted by then, attempts **continue silently until Finish floor** and the best
   window still wins (the ARKit world frame is the same for the whole floor, so a later window measures the same
   quantity; see Q4). `headingRecordedAt` tells when.
8. **Live events.** Every change of the best window, and the end of the start period, emits
   `CaptureSessionEvent.compass(CompassLiveState)` (5.2).
9. **Finish.** At `finish()`: run the frame check (3.4), compute `H_C`, round to 0.1° and normalise (360.0 → 0.0),
   return it in `CaptureSessionResult.compass`. No accepted window → `CompassResult.none(issue:)` per 1.5.
10. **Try again / Cancel.** `retryScan()` starts a new session (new W): the old reading is discarded.
    `cancel()` discards everything.

Battery/thermal: Core Motion at 60 Hz and the 4 Hz pairing are negligible next to RoomPlan; location updates at
3 km accuracy only while a reading runs. Stop all compass sensors at `finish()`/`cancel()`.

### 3.4 Frame check at Finish floor

During the scan, keep per segment the surfaces of the last `CapturedRoom` delivered by
`captureSession(_:didUpdate:)`: `identifier → yaw`, where `yaw` is the plan-frame angle of the surface's local
X axis: `a = (T.columns.0.x, T.columns.0.z)`, `yaw = atan2(−a.z, a.x)`. After `RoomBuilder` / `StructureBuilder`,
compute the same for every surface of the final result (walls, doors, windows, openings, objects) and match by
identifier.

- `φ_i = wrap(yaw_final − yaw_live)` into (−90°, 90°] (surfaces may be re-fitted end for end).
- With ≥ 3 matches and ≥ 70% of `φ_i` within 2° of their median: `φ = median` (expected ≈ 0). If `|φ| > 2°`, log
  `compass.frame_yaw` with the value.
- Fewer than 3 matches, or no consensus: `φ` = the convention fixed by device test D1 (0 unless D1 says otherwise).

### 3.5 Phone code shape (new types)

`contract/swift` (CaptureContract, pure Swift):

```swift
public enum HeadingSource: String, Codable, CaseIterable, Sendable { case trueNorth = "true", magnetic }
public enum HeadingIssue: String, Codable, CaseIterable, Sendable { case rejected, notCalibrated = "not_calibrated", unavailable }
public enum CompassThresholds { public static let verifiedMax = 10; public static let approximateMax = 30 }
public enum CompassReason: String, Sendable { case noReading = "no_reading", rejected, inaccurate, notCalibrated = "not_calibrated", unavailable }
public enum CompassState: Hashable, Sendable {
  case verified(heading: Double, accuracy: Int)                          // source true
  case approximate(heading: Double, accuracy: Int, source: HeadingSource)
  case notVerified(CompassReason, accuracy: Int?)                         // accuracy only for .inaccurate
  public init(_ capture: CaptureRecord.Capture)                            // rules 1.2
  public var isUsable: Bool                                                 // verified or approximate
}
public enum NorthSymbol: Hashable, Sendable {                               // texts of 1.4
  case arrow(angleCCW: Double, approximate: Bool, line1: String, line2: String)
  case notVerified(box: String, caption: String)                            // "Orientation: not verified"
  public init(state: CompassState, drawingRotationCCW rho: Double = 0)     // A = (H + rho) mod 360, 2.5
}
public enum CompassMath { /* 2.2–2.3, 2.5, circular mean, wrap, cardinal() */ }
public enum CompassText { /* station details, web phrases, AGO formatting, words for summaries */ }
```

`ios/Packages/CaptureCore` (new folder `Sources/CaptureCore/Compass/`, Foundation only, Linux-testable):
`CompassSample` (paired values), `HeadingWindow` (steps 3–6), `FrameCheck` (3.4), `CompassResult`
(`.reading(heading, accuracy, source, recordedAt)` / `.none(issue: HeadingIssue?)`), `CompassLiveState`
(`.reading`, `.result(CompassState, cameraBearing: Double?)`, `.notVerified`), `CompassPrecheckState`
(`.reading`, `.result(heading, accuracy, source, readAt)`, `.notCalibrated`, `.unavailable`),
`protocol CompassProviding` (pre-check, authorisation status, open-settings), `FakeCompass` (scripted, for unit
and UI tests).

New target `CaptureCompass` in `ios/Packages/CaptureCore/Package.swift` (APPLE ONLY, CoreLocation + CoreMotion,
depends on `CaptureCore` and `CaptureContract`, `.apple-only` marker, Swift 5 language mode like
`CaptureRoomPlan`): `CompassService` (`@MainActor`, owns the one `CLLocationManager` and one `CMMotionManager`,
implements `CompassProviding`, vends Core Motion samples to `LiveCaptureSession` and to the photo heading).
`CaptureRoomPlan` depends on it. The App creates one `CompassService`; for photos it passes an adapter
`CompassPhotoHeading: PhotoHeadingProviding` (new, `ios/App/Sources/App/CompassPhotoHeading.swift`, conforms to
`phone-field`'s protocol) instead of `phone-field`'s own `DeviceCameraHeading`, so the app runs a single location
manager and a single motion manager. (If `phone-field` ships first with `DeviceCameraHeading`, the adapter replaces
it; behaviour is identical.)

---

## 4. Contract changes

### 4.1 `contract/schema/capture-record.schema.json` → 1.1.0

```jsonc
"schemaVersion": {
  "description": "1.1.0 adds the optional compass reading of each capture (heading, headingAccuracy, headingSource, headingRecordedAt) and headingIssue; a 1.0.0 document does not carry them. Readers accept both versions; writers write 1.1.0.",
  "enum": ["1.0.0", "1.1.0"]
},
```

In `$defs.capture.properties` (all optional; `required` unchanged):

```jsonc
"heading": {
  "description": "Compass bearing of this capture's -Z axis (plan up: plan y is -Z), in degrees clockwise from north, 0 <= heading < 360, one decimal. True north when headingSource is true, magnetic north when magnetic. Read by the phone compass at the start of the scan and matched to the scan frame; never typed. Omitted when there is no reading: the orientation is then not verified.",
  "type": "number", "minimum": 0, "exclusiveMaximum": 360
},
"headingAccuracy": {
  "description": "Compass accuracy reported by the phone for the reading, whole degrees rounded up: the heading is within plus or minus this value. Verified at 10 or less with a true heading; approximate up to 30; not verified above 30.",
  "type": "integer", "minimum": 1, "maximum": 180
},
"headingSource": {
  "description": "true: corrected to true north with the phone's location. magnetic: magnetic north only (Location off).",
  "enum": ["true", "magnetic"]
},
"headingRecordedAt": { "description": "When the compass reading was taken.", "$ref": "#/$defs/dateTime" },
"headingIssue": {
  "description": "Why there is no heading although the app tried: rejected (readings disagreed or could not be matched to the scan), not_calibrated (the compass reported no valid accuracy), unavailable (no usable compass on the device). Never present together with heading.",
  "enum": ["rejected", "not_calibrated", "unavailable"]
}
```

In `$defs.capture` (siblings of `properties`):

```jsonc
"dependentRequired": {
  "heading": ["headingAccuracy", "headingSource", "headingRecordedAt"],
  "headingAccuracy": ["heading"],
  "headingSource": ["heading"],
  "headingRecordedAt": ["heading"]
},
"not": { "required": ["heading", "headingIssue"] }
```

At the root, next to the existing properties (same pattern as capture-model 1.1.0):

```jsonc
"if": { "properties": { "schemaVersion": { "const": "1.0.0" } } },
"then": {
  "description": "A 1.0.0 document carries none of the fields added in 1.1.0.",
  "properties": { "captures": { "type": "array", "items": { "type": "object", "properties": {
    "heading": false, "headingAccuracy": false, "headingSource": false, "headingRecordedAt": false, "headingIssue": false
  } } } }
}
```

`$id` stays `.../v1/capture-record.schema.json`. The station API validates uploads with this schema (via the
contract validators) and the OpenAPI document references the file, so both pick it up without code changes.

### 4.2 Swift (`contract/swift/Sources/CaptureContract`)

- `Enums.swift`: `CaptureRecordSchemaVersion` (`v1 = "1.0.0"`, `v1_1 = "1.1.0"`, `current = .v1_1`), replacing
  `SchemaVersion` in `CaptureRecord` (the shared `SchemaVersion` stays for the other documents); `HeadingSource`,
  `HeadingIssue` (3.5).
- `CaptureRecord.swift`: `schemaVersion: CaptureRecordSchemaVersion` (decoded as read, **always encoded as
  `.current`**, custom `encode(to:)` like `CaptureModel`); `Capture` gains `heading: Double?`,
  `headingAccuracy: Int?`, `headingSource: HeadingSource?`, `headingRecordedAt: UTCTimestamp?`,
  `headingIssue: HeadingIssue?` (init parameters default nil; nil is omitted on encode). New
  `mutating func setCompass(_ result: CompassResultValue)` that writes the four fields or the issue and clears the
  others.
- New `Compass.swift` and `CompassMath.swift` (3.5).
- `README.md` of the package: one paragraph on the compass fields.

### 4.3 TypeScript (`contract/ts`)

- `npm run generate -w @chapter/capture-contract` → `src/generated/capture-record.ts`, `schemas.ts` (committed;
  `generated.test.ts` enforces it).
- New `src/compass.ts`, exported from `src/index.ts`:

```ts
export const COMPASS_VERIFIED_MAX = 10;
export const COMPASS_APPROXIMATE_MAX = 30;
export type CompassReason = "no_reading" | "rejected" | "inaccurate" | "not_calibrated" | "unavailable";
export type CompassState =
  | { kind: "verified"; heading: number; accuracy: number; source: "true" }
  | { kind: "approximate"; heading: number; accuracy: number; source: "true" | "magnetic" }
  | { kind: "not_verified"; reason: CompassReason; accuracy?: number };
export function compassState(capture: Capture): CompassState;                 // rules 1.2
export type NorthSymbol =
  | { kind: "arrow"; angleCcw: number; approximate: boolean; lines: [string, string] }
  | { kind: "box"; box: "Orientation: not verified"; caption: string };
export function northSymbol(state: CompassState, drawingRotationCcw?: number): NorthSymbol;   // 1.4, 2.5
export function compassDetail(state: CompassState): string;                    // station/web phrases, 1.4
export function formatHeading(deg: number): string; export function formatAccuracy(acc: number): string;
```

- `package.json` version `1.0.0` → `1.1.0`.

### 4.4 Examples and shared test vectors

- `contract/examples/capture-record/valid/compass-two-captures.json` (new): the README's visit, schema 1.1.0,
  Floor 1 `heading 212.4, headingAccuracy 8, headingSource "true", headingRecordedAt` = Floor 1 `capturedAt` + 9 s;
  Floor 2 `headingIssue "rejected"`. The existing `two-captures.json` stays 1.0.0 (old documents stay valid).
- Invalid (each one defect, README table updated):
  `heading-in-1.0.0.json` (1.0.0 with `heading`…), `heading-without-accuracy.json`, `heading-and-issue.json`,
  `heading-360.json` (`heading: 360`), `unknown-heading-source.json` (`"grid"`).
- `contract/test-vectors/compass-states.json` (new folder, read by the Swift and TS tests): an array of
  `{ name, capture: {…capture fields…}, rotationCcw, expected: { kind, reason?, symbol, detail } }` covering every
  row of 1.2 (including boundaries 10/11/30/31, magnetic, the time-window rule), 1.3 rounding (359.6 → `0`) and the
  2.5 examples.

### 4.5 Fixtures

`fixtures/generator`: `FixtureSpec` captures gain optional `compass: { heading, accuracy, source, offsetSeconds }
| { issue }`; the capture record is written as 1.1.0 when any capture has it, else 1.0.0 (keeps old-version
coverage). Regenerate: `two-floor-house` → Floor 1 verified (212.4°, ±8, true), Floor 2 none;
`two-room-apartment` → approximate (magnetic, ±12). Others unchanged. Optional broken fixture
`compass-time-outside-scan` (heading recorded 2 h before `capturedAt`) for the station rule 5.

### 4.6 Compatibility and order

Readers accept 1.0.0 and 1.1.0; writers write 1.1.0. The station rejects an unknown version with 422
(`invalid_capture_record`), so **station (API + checks) ships before the app** that writes 1.1.0. Coordinate one
contract PR with `phone-field` (manifest 1.1.0 `photo.directionSource`) and any other capture-record change of
other areas: a single capture-record 1.1.0.

---

## 5. Phone screens

Tokens (phone): ink #1F2429, surface #FAF5EE, ground #F5EFE6, nude #E8DDD0, line #D9CCBC, divider #E8DDD0,
muted #6B6557, ready #2E5E2E, limited glyph #9A6A1E, limited text #7A5214. Type: Inter via
`ChapterTokens.Typography.sans` (switched from SF to Inter by `phone-capture`/brand work); sizes below are pt.
Status glyphs are drawn 10 × 10 (● circle r 4.5; ▲ path `M5 .6 9.6 9.4H.4z`), never typed. The compass never uses
red (■ #8B2E2E): it is "recommended, not required".

### 5.1 C3 · "What are you scanning?" · Compass section

Placement: last section of the scrolling fields, after "Coverage notes", above the pinned `Start scan` button.
Section gap 14 (v2 screen).

| Element | Spec |
|---|---|
| Section label | `COMPASS` (text "Compass", uppercase), 13, muted, padding 0 × 16 |
| Card | gap 6 below label; background surface, border 1 line, radius 12, clip |
| Row | HStack, align centre, gap 12, min-height 56, padding 8 × 16 |
| Icon | 32 × 32, coordinate box 0…32 (y down). Ring: circle centre (16, 18) r 10.5, stroke 1 ink, no fill. Arrow: polygon (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5), fill ink, stroke 1 ink, round joins. "N": Inter SemiBold 7, ink, horizontally centred on x = 16, baseline y = 5. Whole icon turned so it points to north relative to the phone's top edge at the reading: SwiftUI `rotationEffect(.degrees(−HDG))` about (16, 16) (SwiftUI angles are clockwise). Approximate: ring dash 2 / 2, arrow fill surface. Not verified, reading, unavailable: ring only, stroke 1 muted, dash 2 / 2, no arrow, no "N". `accessibilityHidden(true)`. |
| Text column | VStack, gap 2, flex 1. Line 1: 17, ink. Line 2: 13, colour per state, with the state glyph 10 × 10 and gap 5 before the text |
| Button | `Read again`: min-height 44, padding 0 × 12, radius 8, background nude, 15, ink, no border. Disabled while reading (opacity 0.4). Hidden when `unavailable`. Identifier `compass.readAgain` |
| Footnote | gap 6 below the card, 13 / 17, muted, padding 0 × 16: `Read automatically. Hold the phone flat, away from steel and appliances. Approximate or missing readings are shown as such on the plans.` |
| Location-off note | only when authorisation is denied/restricted: gap 6 below the footnote, 13 / 17, limited text (#7A5214), padding 0 × 16: `Location is off for Chapter Capture, so north is magnetic and shown as approximate. Turn on Location in Settings to record true north.` followed by a text button `Open Settings` (15, ink, min-height 44, padding 0 × 16; opens `UIApplication.openSettingsURLString`; identifier `compass.openSettings`) |

States (line 1 / glyph / line 2 / line 2 colour):

| Pre-check state | Line 1 | Line 2 |
|---|---|---|
| reading (first appearance, `Read again`) | `Compass` | no glyph · `Reading the compass…` · muted |
| verified (true, ≤ 10) | `North {HDG}° true · ±{ACC}°` (artboard: `North 212° true · ±8°`) | ● ready · `Verified · read {AGO}` · ready |
| approximate (true 11–30, or magnetic ≤ 30) | `North {HDG}° true · ±{ACC}°` or `North {HDG}° magnetic · ±{ACC}°` | ▲ · `Approximate · read {AGO}` · limited text |
| inaccurate (> 30) | `North {HDG}° {true|magnetic} · ±{ACC}°` | ▲ · `Not verified · accuracy too low · read {AGO}` · limited text |
| not calibrated | `No compass reading` | ▲ · `Not verified · move the phone in a figure 8, then read again` · limited text |
| unavailable | `No compass on this phone` | ▲ · `Not verified · the plans will say so` · limited text |

`{HDG}` here is the phone's own heading (top edge) from `CLHeading`, not the stored heading. `Start scan` is
never gated by the compass. Accessibility: the row is one element, label e.g. `Compass. North 212 degrees true,
plus or minus 8 degrees. Verified, read 12 seconds ago.`; `Read again` is its own button. Dynamic Type: the row
grows; line 2 wraps.

### 5.2 C4 · Live scan · compass chip

Placement: the row under the scan panel (artboard: padding 12 16 0, HStack, align centre, gap 10): the chip first
(`flex: none`), then the recording caption (owned by `phone-capture`). Same on 3b "Tracking lost" (chip
unchanged).

| Element | Spec |
|---|---|
| Chip | height 32, padding 0 × 10, radius 16, background `rgba(250,245,238,0.14)`, HStack gap 6, text 13 #FAF5EE |
| Icon | 14 × 14, box 0…32: polygon (16, 4) (22, 28) (16, 23) (10, 28). Verified: fill #FAF5EE. Approximate: fill none, stroke #FAF5EE width 2.5 (box units), round joins. Rotation: SwiftUI `rotationEffect(.degrees(−cameraBearing))` (2.3), so the arrow points to north as seen through the camera (up on the chip = the direction the camera looks); updated at the 4 Hz tick, animated 0.2 s ease-out; the last value is kept while the camera points steeply up or down. No icon while reading or when not verified. |

| Live state | Chip text | Icon |
|---|---|---|
| reading (start period, nothing accepted yet) | `N · reading…` | none |
| verified | `N · true · ±{ACC}°` (artboard `N · true · ±8°`) | filled |
| approximate, true | `N · approx. · ±{ACC}°` | outline |
| approximate, magnetic | `N · magnetic · ±{ACC}°` | outline |
| not verified (start period over, best so far not usable; attempts continue) | `N · not verified` | none |

No haptics for the compass (the live screen's haptics stay as they are). Accessibility label: `Compass verified,
true north, plus or minus 8 degrees` / `Compass reading` / `Compass approximate, magnetic north, plus or minus 12
degrees` / `Compass not verified`. Identifier `scan.compass`. The chip is not a button.

### 5.3 C5 · Capture overview · Compass row and sheet

Row in the "Before you leave" card of the overview (`phone-capture` lays out the card; artboard order: Photos,
Field controls, **Compass**, Rooms not scanned). Row: HStack gap 12, min-height 48, padding 6 × 16, top border 1
divider; title `Compass` 17; detail 13 muted = per-floor words (`CompassSummary.short` of `phone-field` §9.4):
`{label} {word}` joined ` · `, e.g. `Floor 1 verified · Floor 2 not read`; right: glyph + word 15; chevron
8 × 14 #B9AFA2.

Words per capture: `verified` (verified), `approximate` (approximate), `not verified` (reasons `inaccurate`,
`rejected`), `not read` (reasons `no_reading`, `not_calibrated`, `unavailable`). Same mapping for
`phone-field`'s `CaptureCompassStatus`.

| Captures | Right side |
|---|---|
| all verified | ● ready `Verified` (ready colour) |
| all usable, at least one approximate | ▲ `Approximate` (limited text) |
| some usable, some not (artboard) | ▲ `Partly` (limited text) |
| none usable | ▲ `Not read` (limited text) |

Tap → **Compass sheet** (not drawn; iOS sheet, `.medium` detent, background ground, drag indicator):
title row `Compass` 17 semibold centred with `Done` (17, ink, trailing); a card (surface, 1 line, radius 12) with
one row per capture in record order (min-height 52, padding 8 × 16, divider between): label 17 ink; under it 13
muted the drawn-output text joined with ` · ` (`True north · compass ±8° · 212°`,
`Approx. north · compass ±18° · true`, `Orientation: not verified · No compass reading`); trailing glyph + word
15 as in the table above. Footnote 13 / 17 muted, padding 0 × 16: `Read automatically at the start of each floor's
scan. A floor scanned without a usable reading says "Orientation: not verified" on its plans.` Identifier
`overview.compass`, sheet `compass.sheet`.

### 5.4 C6 · Before you leave · Compass reading

Built by `phone-field` (§6.4 of its spec: advisory item `compass` between `minimumControls` and `visitDetails`,
title `Compass reading`, ▲ / ●, details such as `Floor 1 verified · Floor 2 not read: its plan will say "not
verified"`, footnote `Red items block the package. The compass is recommended, not required.`). This spec
supplies `CompassState` per capture and the word mapping of 5.3. The item never counts in `Fix {n} items to
finish` and never blocks.

The artboard's `Read` button: **not shown** (default of Q1): a reading taken after a floor's scan has ended cannot
be tied to that scan's frame, so there is nothing valid it could record. `phone-field` already hides it when the
host passes no `onReadCompass`; the app passes nil.

### 5.5 C7 · Photo "Looking toward" pre-fill

UI, data (`PhotoLabelDraft.directionSource`, manifest 1.1.0 `photo.directionSource`) and rules are
`phone-field` §3.6 / §9.3 / §10. This spec fixes two shared things: the attitude convention is
`CompassMath.cameraAxisInReference` (2.3), and the provider uses the app's single `CompassService` (3.5). Its
thresholds match this spec (no pre-fill when the accuracy is invalid or > 30, or the camera is more than 60° up or
down; sectors N [315, 45), E [45, 135), S [135, 225), W [225, 315)).

### 5.6 C8 · Package ready · Capture record line

`phone-package` §3.3: `compass: recorded` / `compass: every floor` / `compass: {labels} only` /
`compass: not recorded`, where "has a reading" = `CompassState.isUsable`.

---

## 6. North symbol on drawn outputs

### 6.1 Symbol geometry (vector, never an image or a font glyph)

Coordinates in a 32 × 32 box, y down as in the artboard SVG (unit = 1/32 of the box size `S`; scale
`s = S / 32`). Everything inside the box is rotated counter-clockwise by `A` (2.5) about the box centre (16, 16);
the caption is not rotated. Every point stays within 16 units of the centre at any angle (the "N"'s top corners
are the farthest, about 15.9), so nothing leaves the box's circle and the block size does not depend on `A`.

| Part | Verified | Approximate |
|---|---|---|
| Ring | circle centre (16, 18), r 10.5, stroke 0.75 × s pt ink, no fill | same, dash 1.6 × s on / 1.6 × s off, butt caps |
| Arrow | polygon (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5), fill ink, stroke 0.75 × s pt ink, round joins | same outline, **fill = page colour** |
| "N" | Inter SemiBold, 6 × s pt, ink, horizontally centred on x = 16, **baseline at y = 4.6** (as the artboard SVG draws it: `<text x=16 y=4.6 text-anchor=middle>`; the letter spans about y 0.2–4.6), turns with the arrow | same |
| Caption | two centred lines, Inter Regular 7.5 pt (not scaled), line height 9 pt, muted #6B6557, top 2 pt below the box; lines from 1.4 | same |

Not verified: no ring, no arrow, no "N", ever. A text box: `Orientation: not verified`, Inter Regular 7.5 pt,
line height 9 pt, ink; border 0.75 pt muted #6B6557; corner radius 3 pt; padding 3 pt top/bottom, 6 pt left/right
(box height 15 pt); below it, 2 pt gap, one centred caption line (Inter Regular 7.5 pt, muted) with the reason
(1.4). The box block is centred where the arrow block would be.

Block size: arrow block width = max(S, widest caption line), height = S + 2 + 18 pt; not-verified block width =
max(box width, caption width), height = 15 + 2 + 9 = 26 pt.

Colours: ink = the output's own ink token (design value #1F2429; PlanExport's PDFs use `ChapterBrand.ink`
#231F20 for walls and text, so the arrow uses that on phone outputs; the station uses the spatial report's ink).
Page colour = the output's background (plan sheet and report pages #FAF5EE per artboards; the Floorplan page and
plan.png white).

Black and white: the symbol is ink plus page colour only, so it prints in grey scale; approximate stays different
from verified (dashed ring, hollow arrow). The bundle's B/W proof uses the approximate state on the plan sheet.

### 6.2 Sizes and placement per output

| Output | Made by | Box `S` | Placement (artboard) | Host area |
|---|---|---|---|---|
| Plan sheet (Tabloid 1224 × 792 pt) | phone, PlanExport | **40 pt** | title block (x 936–1164), the row "Scale + north": `justify-content: space-between; align-items: flex-end; gap 12pt` with the `SCALE` label (7.5 pt caps, tracking 1.5 pt, muted) + scale bar on the left and the north block on the right | `plan-sheet` |
| Report cover, 1 floor (Letter landscape 792 × 612 pt) | station, pdfkit | **32 pt** | in the plan area (left 36, top 102, 476 × 426 pt): a column `right: 0; bottom: 22pt; width: 84pt`, block centred in it (block bottom at y = 506 pt from the page top, centre x = 470 pt) | `spatial-report` |
| Report cover, 2–3 floors | station | **26 pt** each | under each floor's drawing: floor label (7.5 pt bold caps, tracking 1.2 pt), the drawing, then the north block centred (`align-self: center`, 4 pt top padding). Every floor shows its own state (a floor without a reading shows the box with `No compass reading`). 4+ floors: the three drawn floors only. | `spatial-report` |
| Report plan page (per floor) | station | **32 pt** | plan area (left 219, top 102, 537 × 426 pt): a column `right: 0; bottom: 26pt; width: 170pt; flex column; align-items: flex-end; gap 8pt` holding the north block, then the scale bar (block right edge at x = 756 pt) | `spatial-report` |
| Floorplan page (`floorplan.pdf`, `floorplan.png`, `FloorplanWriter.write/pdf`) | phone | **32 pt** (11.29 mm) | top right of the header, where today's compass rose sits: block right edge at `width − margin`, box centre y at `top − 10 mm` (today's compass centre); the address line clearance (`Layout.addressWidth`) uses the block's left edge | this spec (6.3) |
| Floorplan on screen (`FloorplanWriter.screenPDF`, `FloorPlanDrawing` with north) | phone | 32 pt at paper scale | the free corner FloorPlanDrawing already picks for its compass; **no caption**; arrow for verified/approximate only; nothing for not verified | this spec (6.3) |
| plan.png / plan.svg | phone | 32 pt | top right of the drawing, as on the Floorplan page | `plan-sheet` (if plan.png/svg become renders of the plan sheet they inherit the sheet's symbol) |

The phone's plan outputs get the state from `PlanExportContext.compass` (6.3); the station from
`compassState(capture)` for each capture of the record.

Removed text: the plan PDF note `True north was not captured. Sheet up is the -Z axis of the capture frame.`
(`PlanPDFWriter.swift` line 134) is replaced by the symbol (owner: `plan-sheet`).

### 6.3 PlanExport changes (phone)

- New `ios/Packages/PlanExport/Sources/PlanExport/NorthArrow.swift`:
  `enum NorthArrow { static func items(symbol: NorthSymbol, centerMM: Point2, boxMM: Double, page: DrawingColor,
  caption: Bool, layer: DrawingLayer = .compass) -> [DrawingItem]; static func blockSizeMM(symbol:boxMM:caption:) ->
  (width: Double, height: Double) }`. Builds the 6.1 geometry with `PathBuilder` (ring as a circle with
  `DrawingStroke.dash` for approximate; polygon; text items with `bold: true` for "N", rotated by `A`; the box as a
  rounded rectangle with 3 pt radius). Text sizes in mm (pt × 25.4 / 72).
- `PlanExportContext`: `public var compass: CompassState` (from the record's capture; `CompassState(capture)`).
- `FloorplanWriter.Options`: new `public var north: CompassState?`, default **nil = draw nothing** (keeps
  `tools/plan-render` and the scan browser output unchanged). `northDegrees` stays as a computed convenience:
  setting it sets `north = .verified(heading: x, accuracy: 1)`, reading it returns the heading of a usable state
  (keeps existing tests compiling; the app never uses it). `compass:
  Bool` keeps its meaning (false hides the symbol). The page draws `NorthArrow` with `ρ = −drawing.rotationDegrees`
  and caption; `Layout.addressWidth(pageWidth:compass:)` becomes `addressWidth(pageWidth:northBlockWidthMM:)`.
- `FloorPlanDrawing.Options.northDegrees` → `north: CompassState?` (+ the same `northDegrees` convenience).
  `compassItems` (the eight-point rose) is replaced by `NorthArrow.items(... caption: false)` (Q3); placement code
  unchanged; not verified draws nothing in the drawing.
- App: `FloorplanFiles.pdf` / `screenPDF` (`ios/App/Sources/App/Views/FloorplanView.swift`) pass
  `north: CompassState(capture)` from the visit record (always non-nil in the app, so state 3 is drawn on the
  page when there is no reading).

### 6.4 Tools

`tools/plan-render` and `tools/scan-browser` read only `capture-model.json`; with `north` nil they draw exactly
what they draw today. No change (scan browser is out of scope).

### 6.5 Files that stay in the scan frame

plan.dxf (no `$NORTHDIRECTION`), rooms.csv, mesh GLB/OBJ, LAS, raw RoomPlan JSON, depth samples, camera poses:
unchanged. North is in the capture record only.

---

## 7. Where each output gets its data, and what is not available

| Output | Data source | When the data is not there |
|---|---|---|
| Pre-check card (5.1) | live `CLHeading` (phone top edge), not stored | `No compass reading` / `No compass on this phone` states |
| Live chip (5.2) | `CompassLiveState` from `LiveCaptureSession` (best window so far + camera pose) | `N · reading…`, then `N · not verified` |
| Overview row, sheet, Before you leave, Package line | the visit's capture record (`CompassState(capture)` per capture) | every capture of an older visit (1.0.0) is `not read` / `compass: not recorded` |
| Photo pre-fill | live Core Motion attitude at the shutter (`phone-field`) | no pre-fill; operator chooses |
| Plan sheet, Floorplan, plan.png/svg (phone) | `PlanExportContext.compass` from the record | the not-verified box with its reason |
| Spatial report cover, plan page, checks page (station) | `capture-record.json` of the package (`compassState`) and the verdict | box `Orientation: not verified` + `No compass reading`; limitation row (Q2) |
| Web (Orientation, Compass rows) | `pkg.captureRecord` (already in the package detail API) and the verdict | the not-verified texts of 9 |

Not available anywhere and never shown: the phone's location, a declination value, the magnetic heading when the
source is true, the raw sensor samples. Not recorded by older app builds: everything in 1.1 (shown as state 3).

---

## 8. Station

### 8.1 Validation

- Upload (`station/api/src/routes/uploads/index.ts`): unchanged code; the contract validator now accepts 1.0.0 and
  1.1.0 and enforces 4.1 (dependent fields, no heading with issue, `0 ≤ heading < 360`, integer accuracy 1–180).
  A failing record is refused with 422 `invalid_capture_record` as today.
- Semantic rule 5 of 1.2 (reading time inside the scan) is part of the shared evaluator, so the phone, the
  station report and the web agree.

### 8.2 New check `orientation.compass` ("Orientation (compass)")

- `station/checks/src/types.ts`: add `{ id: "orientation.compass", title: "Orientation (compass)" }` to `RULES`
  right after `orientation.up` (13 rules).
- `station/checks/src/checks/compass.ts` (new) `checkCompass(ctx)`, registered in `verdict.ts` `RUNNERS`.
- `EVALUATOR.version` `1.0.0` → `1.1.0`.

Per capture of the record (`ctx.captures()`), `state = compassState(capture)`; one finding each, `filePath` = the
capture record's package path, `captureId`/`areaKey` set:

| State | Severity | message | measured | expected | nextAction |
|---|---|---|---|---|---|
| verified | info | `True north from the compass.` | `True heading {HDG}°, accuracy ±{ACC}°` | `a compass reading at scan start, true north, accuracy ±10° or better` | `None` |
| approximate | info | `North is approximate.` | `Approximate north: {true|magnetic} heading {HDG}°, accuracy ±{ACC}°` | same | `None` |
| not verified | **limitation** (Q2) | `Plan orientation is not verified; north is not shown.` | the reason phrase (1.4), e.g. `No compass reading recorded; orientation not verified`; rule 5 adds ` (reading at {headingRecordedAt}, scan {capturedAt} to {finishedAt})` | same | `None` (a reading cannot be added to a finished scan; nothing is added to the verdict's next actions) |

Check status follows the existing `statusOf`: any not verified → `failed` (limitation), else `passed`. The verdict
adds the floor label to the limitation as it does for every per-capture finding
(`Floor 2: Plan orientation is not verified; north is not shown.`). No capture record →
`notApplicable: true` with no finding (the property check already reports the missing record).

Effect: a package is **Ready** only when every floor's orientation is verified or approximate (Q2 has the
alternative). The spatial report's checks page and the web show this row from the verdict and its finding.

### 8.3 Spatial report drawing helper

`station/hub/src/north-arrow.ts` (new, used by the spatial-report renderer): `drawNorthBlock(doc: PDFKit.PDFDocument,
symbol: NorthSymbol, box: { centerX: number; top: number; size: number }, colors: { ink: string; muted: string;
page: string }, fonts: { regular: string; semibold: string })` implementing 6.1 in pdfkit (`circle`, `dash`,
`polygon`, `rotate(−A, { origin })`; pdfkit's y axis points down, so a counter-clockwise turn is a negative
angle). Fonts: the self-hosted Inter registered by `spatial-report` (no Google fonts).

---

## 9. Web review texts (C11; layout by `web-review`, HUB design system, Inter)

Plan card, row label `Orientation` (12 muted) and value (13 strong), for the floor shown by the card's floor
badge:

| State | Value |
|---|---|
| verified | `Verified · true north from the compass, ±{ACC}°. The plan sheet shows the north arrow.` |
| approximate | `Approximate · compass ±{ACC}°, {true north|magnetic north}. The plan sheet shows an approximate north arrow.` |
| not verified (artboard) | `Not verified · {phrase}. North is not shown.` with phrase `no compass reading` / `the compass reading was rejected` / `compass accuracy ±{ACC}°` / `the compass was not calibrated` / `no compass on the phone` (artboard: `Not verified · no compass reading. North is not shown.`) |

Capture record card, row `Compass` (right-aligned value, 13 strong):

| Visit | Value |
|---|---|
| one capture, verified | `Verified · {HDG}° true, ±{ACC}°` (HDG = stored heading) |
| one capture, approximate | `Approximate · {HDG}° {true|magnetic}, ±{ACC}°` |
| one capture, not verified (artboard) | `Not read · orientation not verified` (no heading) / `Rejected · orientation not verified` / `±{ACC}° · orientation not verified` (inaccurate) |
| several captures | per-floor words of 5.3 joined ` · `, e.g. `Floor 1 verified · Floor 2 not read` |

Limitations: the verdict card lists `verdict.limitations` as today; the orientation line comes from the verdict
(8.2), so the web adds no logic of its own. The web shows no arrow next to the plan preview (the arrow is on the
drawings; a preview may be turned relative to the scan frame).

All web texts come from `@chapter/capture-contract`'s `compassState` / `compassDetail` helpers plus these
templates in `web/lib/compass.ts` (new, small).

---

## 10. Code map

### 10.1 Contract

| File | Change |
|---|---|
| `contract/schema/capture-record.schema.json` | 4.1 |
| `contract/swift/Sources/CaptureContract/Enums.swift` | `CaptureRecordSchemaVersion`, `HeadingSource`, `HeadingIssue` |
| `contract/swift/Sources/CaptureContract/CaptureRecord.swift` | schema version type, five optional fields, custom encode, `setCompass` |
| `contract/swift/Sources/CaptureContract/Compass.swift` (new) | `CompassThresholds`, `CompassReason`, `CompassState`, `NorthSymbol`, `CompassText` |
| `contract/swift/Sources/CaptureContract/CompassMath.swift` (new) | 2.2–2.5 math, circular statistics, cardinal sectors |
| `contract/swift/Tests/CaptureContractTests/CompassTests.swift`, `CompassMathTests.swift` (new); `RoundTripTests.swift`, `SchemaParityTests.swift` | vectors, round trips, `HeadingSource`/`HeadingIssue` vs schema enums |
| `contract/ts/src/compass.ts` (new), `src/index.ts`, `src/generated/*` (regenerated), `package.json` | 4.3 |
| `contract/ts/test/compass.test.ts`, `capture-record-versions.test.ts` (new) | vectors; 1.0.0/1.1.0 rules (pattern of `capture-model-versions.test.ts`) |
| `contract/examples/capture-record/{valid,invalid}/…`, `contract/examples/README.md`, `contract/test-vectors/compass-states.json` (new) | 4.4 |

### 10.2 iOS

| File | Change |
|---|---|
| `ios/App/Resources/Info.plist` | `NSLocationWhenInUseUsageDescription` |
| `ios/Packages/CaptureCore/Package.swift` | target + product `CaptureCompass` (apple-only); `CaptureRoomPlan` depends on it |
| `ios/Packages/CaptureCore/Sources/CaptureCompass/CompassService.swift` (new) + `.apple-only` | 3.1, 3.5 |
| `ios/Packages/CaptureCore/Sources/CaptureCore/Compass/{CompassSample,HeadingWindow,FrameCheck,CompassResult,CompassLiveState,CompassPrecheckState,CompassProviding,FakeCompass}.swift` (new) | 3.2–3.5 |
| `ios/Packages/CaptureCore/Sources/CaptureCore/CaptureSession.swift` | `CaptureSessionEvent.compass(CompassLiveState)`; `CaptureSessionResult.compass: CompassResult` (default `.none(issue: nil)`) |
| `ios/Packages/CaptureCore/Sources/CaptureCore/ReplaySession.swift` | scripted compass events and result (for tests and UI tests) |
| `ios/Packages/CaptureCore/Sources/CaptureCore/CaptureFlowModel.swift` | `compassPrecheck`, `liveCompass`, `readCompassAgain()`, `openLocationSettings()`; `finishFloor()` writes `record.captures[0].setCompass(result)`; `retryScan()`/`cancelScan()` reset |
| `ios/Packages/CaptureCore/Sources/CaptureRoomPlan/LiveCaptureSession.swift` | pairing in `tick()`, last live surfaces in `didUpdate`, frame check and result in `finish()`, sensor stop in `cancel()`/`failed()` |
| `ios/Packages/CaptureCore/Sources/CaptureUI/CompassViews.swift` (new) | `CompassCard` (5.1), `CompassChip` (5.2), `NorthGlyph` shape, `CompassSheet` (5.3) |
| `ios/Packages/CaptureCore/Sources/CaptureUI/ScanSetupScreen.swift`, `LiveScanScreen.swift` | host the card and the chip (inside `phone-capture`'s v2 rewrite) |
| `ios/Packages/CaptureCore/Sources/CaptureTestSupport/SchemaValidator.swift`, `ios/Packages/PackageKit/Tests/PackageKitTests/Support/SchemaValidator.swift` | support `exclusiveMaximum` (both fail loudly on unknown keywords today) |
| `ios/App/AppCore/Sources/AppCore/VisitFlow.swift` | no logic change (the floor's capture carries the fields); tests |
| `ios/App/Sources/App/VisitModel.swift`, `AppModel.swift`, `CompassPhotoHeading.swift` (new) | one `CompassService` for the app; passed to the capture flow and, through the adapter, to the photo labeling model; UI-test mode uses `FakeCompass` from launch env `UITEST_COMPASS` = `verified` / `approximate` / `none` |
| `ios/App/Sources/App/Views/FloorplanView.swift` | pass `north` (6.3) |
| `ios/Packages/PlanExport/Sources/PlanExport/NorthArrow.swift` (new), `PlanExportContext.swift`, `FloorplanWriter.swift`, `FloorPlanDrawing.swift` | 6.3 |
| `ios/Packages/FieldKit/...` | per `phone-field` (§3.6, §6.4, §9.3–9.4); `CameraAxis.sample` calls `CompassMath` |

Removed: `FloorPlanDrawing.compassItems` (rose) (Q3); the plan PDF north note (via `plan-sheet`); the phone's
spatial report already retires in other areas (nothing compass-specific there).

### 10.3 Station and web

| File | Change |
|---|---|
| `station/checks/src/types.ts`, `verdict.ts`, `checks/compass.ts` (new) | 8.2 |
| `station/checks/test/checks.test.ts`, `broken-fixtures.test.ts` | rule count 13, compass findings per fixture |
| `station/hub/src/north-arrow.ts` (new) | 8.3 |
| `web/lib/compass.ts` (new) | 9 |
| `fixtures/generator/src/{spec,controls,package}.ts`, `fixtures/generated/**` | 4.5 |
| `docs/floorplan-report-plan.md` | phase 9: "manual north override" withdrawn; link to this spec |

---

## 11. Dependencies on other areas

| Area | What this spec needs from it | What it needs from this spec |
|---|---|---|
| `phone-capture` | v2 "What are you scanning?" and Live scan layouts that host `CompassCard` / `CompassChip`; Capture overview hosts the Compass row and sheet; Inter in `ChapterTokens.Typography` | 5.1–5.3, `CaptureFlowModel` compass state, the evaluator |
| `phone-field` | Before you leave item (§6.4), photo pre-fill (§3.6), manifest `photo.directionSource` (§10); use `CaptureContract.HeadingSource` (do not define a second one) and `CompassMath.cameraAxisInReference`; `onReadCompass` nil | `CompassState`, word mapping (5.3), the single `CompassService` |
| `phone-package` | Package ready "compass: …" line (§3.3) | `CompassState.isUsable` |
| `plan-sheet` | title block row "Scale + north" with a 40 pt block; plan.png/svg symbol; removal of the old north note; page colour token | `NorthArrow`, `PlanExportContext.compass` |
| `spatial-report` | cover (1 floor, 2–3 floors) and plan page placement (6.2), Inter registered in pdfkit, checks page row from the verdict | `northSymbol`, `drawNorthBlock`, check 8.2 |
| `web-review` | Orientation and Compass rows (9) | `compassState`, `compassDetail`, `web/lib/compass.ts` |
| contract owner (one PR) | capture-record 1.1.0 together with manifest 1.1.0 (`phone-field`) and any other capture-record field | 4.1–4.4 |

---

## 12. Rollout, risks

Order: (1) device tests D0–D1 on a prototype branch; (2) contract PR (schema, Swift, TS, examples, vectors);
(3) station: API (validator) + checks 1.1.0 deployed; (4) PlanExport `NorthArrow` and outputs (state 3 everywhere
until the app records readings); (5) app: `CompassService`, scan-start reading, screens; (6) spatial report and
web use the helpers.

| Risk | Mitigation |
|---|---|
| Capture frame not equal to the ARKit world frame (RoomPlan post-processing, `StructureBuilder`) | D1 and D5 before UI work; frame check 3.4; convention fixed in one function with a recorded-data unit test |
| Core Motion / ARKit matrix conventions wrong (transpose, K→D mapping) | runtime gravity checks drop bad samples and flag `compass.convention_mismatch`; unit tests with synthetic and recorded matrices; D0 |
| Magnetic disturbance indoors (steel, appliances, MagSafe cases and wallets with magnets) | consistency test 3.3 step 5, accuracy shown before scanning, footnote text; operator training note: remove magnetic wallets and cases before scanning |
| `trueHeading` / true-north frame need location updates; reduced-accuracy location | location updates at 3 km while reading; D3 confirms true north with approximate location; otherwise magnetic → approximate, never wrong |
| ARKit yaw drift on long scans | reading early (start period) preferred; best-window rule; accuracy reported as the compass's own |
| Station deployed after the app | 422 on upload; enforce the rollout order (4.6) |
| Every package becomes Limited until the feature ships (Q2 default) | stated in the release note; accepted as honest (plans without north) |
| Two `HeadingSource` types (FieldRules and CaptureContract) | only the contract one exists (11) |

---

## 13. Test plan and acceptance criteria

### 13.1 Unit (Swift, Linux CI: `scripts/swift-test.sh`)

- `CompassTests` (contract): every vector in `contract/test-vectors/compass-states.json` gives the expected
  `CompassState`, `NorthSymbol` texts and detail; boundaries 10/11/30/31; magnetic; rule 5; rounding 359.6 → `0`.
- `CompassMathTests`: synthetic device attitudes (flat, upright portrait, pitched 30° and 60°, rolled 20°) and
  ARKit camera poses with random world yaw ω: computed `H_W` equals the constructed heading within 0.01°;
  transposed Core Motion matrix fails the gravity check; camera bearing ψ; photo azimuth; the 2.5 table
  (`A` and captions); `wrap`, circular mean across 359°/1°.
- `HeadingWindowTests`: 8 consistent pairs → accepted; spread 6° with accuracy 4 → rejected; rotation rate 0.5
  rad/s → pairs dropped; accuracy −1 throughout → `not_calibrated`; verified window stops the attempt; best-of
  (approximate at 5 s replaced by verified at 50 s); pause time not counted in the 30 s; magnetic frame →
  `source magnetic`.
- `FrameCheckTests`: identical surfaces → φ 0; all surfaces turned 37° → φ 37; one wall flipped 180° → still 37;
  two matches → D1 convention; no consensus → D1 convention.
- `CaptureRecord` round trip: a 1.0.0 document decodes and re-encodes as 1.1.0 without compass fields; a 1.1.0
  document with fields round-trips byte-stable (sorted keys); `SchemaValidator` accepts every valid example and
  rejects every invalid one (with `exclusiveMaximum` support).
- `CaptureFlowModelTests` with `ReplaySession` + `FakeCompass`: finish writes the four fields (verified script),
  writes `headingIssue` (rejected script), writes nothing (no-reading script); `retryScan` discards the old reading;
  pre-check states and `Read again`.
- PlanExport `NorthArrowTests`: ring centre and radius, polygon points after rotation by `A`, dash `[1.6s, 1.6s]`
  only for approximate, arrow fill = page colour for approximate, "N" position and rotation, caption lines and
  sizes, not-verified box size (padding 3 × 6, radius 3) and caption; `FloorplanWriterTests` and
  `FloorPlanDrawingTests` updated: the symbol turns with the plan (`A = H − rotationDegrees`), state 3 draws the
  box on the page and nothing on screen, `north` nil draws nothing (plan-render unchanged), address clearance.

### 13.2 TypeScript

- `contract/ts/test/compass.test.ts`: the same vectors (parity with Swift); `capture-record-versions.test.ts`:
  accepts 1.0.0 and 1.1.0, rejects each 1.1.0 field in a 1.0.0 document at its pointer, rejects heading without
  accuracy, heading with issue, heading 360, accuracy 0 / 2.5 / 181.
- `station/checks`: `orientation.compass` on generated fixtures: `two-floor-house` → Floor 1 info verified, Floor 2
  limitation, status failed, outcome Limited; `two-room-apartment` → info approximate, passed; `box-room` (1.0.0) →
  limitation `No compass reading recorded; orientation not verified`; `compass-time-outside-scan` → limitation
  with the time note; RULES has 13 entries; `EVALUATOR.version` is `1.1.0`.
- `station/hub` north-arrow: pdfkit output contains the expected path operators for each state (golden PDF
  operator stream or PNG via the spatial-report golden setup).

### 13.3 Snapshot / visual

- SVG goldens of the symbol in the three states at 26, 32 and 40 pt, `A` = 0, 32, 212.4 (rendered from
  `NorthArrow` via the SVG writer) compared with reference renders of `plan-parts.js` geometry (Inter for the
  text); maximum pixel difference 1%.
- Floorplan page golden (one per state) from `PlanExportTests`; grey-scale render of the approximate state shows a
  dashed ring and a hollow arrow (pixel check on the ring path).
- Phone: SwiftUI previews / snapshot tests of `CompassCard` (6 states), `CompassChip` (5 states), `CompassSheet`.

### 13.4 UI tests (XCUITest, `ios/App/UITests/ReplayFlowUITests.swift`, launch env `UITEST_COMPASS`)

- `verified`: "What are you scanning?" shows `North 212° true · ±8°` and `Verified · read just now`;
  `compass.readAgain` → `Reading the compass…` → back to verified. Live scan `scan.compass` reads
  `N · true · ±8°`. After Finish floor, the overview Compass row reads `Floor 1 verified` and `Verified`; the
  sealed package's `capture-record.json` (UITestStation) has `schemaVersion 1.1.0` and the four fields.
- `approximate`: chip `N · magnetic · ±12°`; overview `Approximate`.
- `none`: card `No compass reading`, chip `N · reading…` then `N · not verified`; Before you leave shows the
  compass item with ▲ and no `Read` button; `checklist.finish` count unchanged by the compass.

### 13.5 Device tests (manual, recorded in `docs/qa/compass-device-tests.md`, new)

| # | Procedure | Pass |
|---|---|---|
| D0 | Phone flat on a table, top edge along a line of known bearing (from a survey map or a reference compass far from steel); log `H` from `CompassMath` (device top axis) and `CLHeading.trueHeading` | agree within 3°; gravity checks pass in flat, upright and pitched postures |
| D1 | Scan a rectangular room whose wall bearings are known; compare the drawn arrow with reality; log φ from the frame check | arrow within ±max(accuracy, 5°); φ = 0 ± 1° |
| D2 | Five scans of the same room at different start directions | headings agree within ±max(accuracy, 5°) of the true value |
| D3 | Location denied; then approximate location only | magnetic → approximate; with approximate location → true north available |
| D4 | Start the scan next to a refrigerator | accuracy rises or the reading is rejected; never verified with a wrong heading beyond accuracy |
| D5 | Scan with Pause/Resume (several segments, `StructureBuilder`) | same heading as a single-segment scan within 2°; φ = 0 ± 1° |
| D6 | Photos facing N/E/S/W (phone-field pre-fill) | correct cardinal pre-filled |

### 13.6 Acceptance criteria

- AC1: A capture record written by the app is schema 1.1.0; a floor scanned with a good compass carries `heading`,
  `headingAccuracy`, `headingSource`, `headingRecordedAt`; one without carries `headingIssue` or no fields; 1.0.0
  records remain valid everywhere.
- AC2: Phone and station classify every test vector identically (Swift and TS run the same file).
- AC3: The arrow on every output points to north within the recorded accuracy in D1/D2, including Floorplan pages
  whose plan was squared (rotationDegrees ≠ 0).
- AC4: No output ever draws an arrow for a not-verified capture; every not-verified output shows
  `Orientation: not verified` with its reason caption (plan sheet, Floorplan page, report cover, report plan).
- AC5: The compass never blocks Finish capture or the package; Start scan is never gated by it.
- AC6: Station verdicts list `orientation.compass` (13 rules, evaluator 1.1.0) with the 8.2 findings.
- AC7: No location value is written to any file or log.

---

## 14. Open questions (recommended default first)

| # | Question | Default | Alternative |
|---|---|---|---|
| Q1 | The artboard draws `Read` on the Before-you-leave compass row, but a reading after a floor's scan has ended cannot be tied to that scan's frame. | **Hide `Read`**; the row explains what the plan will say; failures are made rare by the pre-check and the continuing attempts during the scan (3.3 step 7). | A "line up with a wall" reading: the floor's plan with one highlighted long wall and an arrow; the operator holds the phone flat against that wall, top edge along the arrow, for 3 s; heading = wall bearing − wall angle in the capture frame; recorded with a new `headingMethod: "wall"` field and **capped at approximate**. Risk: wrong wall or reversed phone gives a wrong arrow. |
| Q2 | Does a not-verified orientation make the package Limited? The bundle disagrees with itself (the Limited sample lists "Plan orientation is not verified; north is not shown." as a limitation while the checks row is "not applicable" and the summary counts two limitations). | **Yes: limitation** finding, so Ready means the plans carry a usable north arrow; next action "None". | Info only: outcome unchanged, checks row `not_applicable`; the orientation line would then have to be added to the Limitations block by the report and the web from the capture record (and would read oddly under a Ready verdict). |
| Q3 | The colour Floorplan draws an eight-point rose (never shown so far: north was never known). Use the v2 symbol there too? | **Yes**: one symbol with the three states on every drawing; the Floorplan page shows the caption and the not-verified box; the screen version shows the arrow only for usable states. | Keep the rose for verified only and draw nothing otherwise on the Floorplan. |
| Q4 | Keep trying after the 30 s start period when no verified window was found? | **Yes**, silently until Finish floor, best window wins (same ARKit frame for the whole floor); `headingRecordedAt` shows when. | Record strictly the first 30 s, nothing later. |
| Q5 | Store the pre-check (screen 2) result? | **No**: it is not tied to the scan frame. | Store it as an extra audit field (no output uses it). |

---

## Addendum (completeness critique, Oct 21, 2026) — binding, overrides the body above

Numbers refer to `00-critique.md`. This spec is the owner of the compass (R-2…R-6, R-20). It is
built across tracks: contract §4 + test vectors + fixtures §4.5 → **T0**; phone §3, §5.1–5.2 and the
`CaptureCompass` target → **T7 phone-capture-core** (with the device tests D0–D1 first and
`docs/qa/compass-device-tests.md`); app wiring (`CompassService` creation,
`CompassPhotoHeading`, `FloorplanView` north, `-ChapterUITestCompass`) → **T10**; PlanExport §6.3
→ **T5**; station check §8.2 → **T3**; report drawing §8.3 → **T4**; web texts §9 → **T6**.

### G1. Corrections
- §2.5 table, row "Station spatial report (plan drawn in P, never rotated): ρ = 0": the report
  squares each floor by its dominant angle `a` (spatial-report §7.4.1, Q2 default), so
  `ρ = −a`. §6.2 placement rows are unchanged.
- §6.1 colours: the symbol uses the host output's ink — `#1F2429` on the plan sheet and the
  spatial report, `ChapterBrand.ink #231F20` on the colour Floorplan (R-8).
- §6.2 row "plan.png / plan.svg … 32 pt" is withdrawn: previews carry no north symbol (R-9).
- §5.1 approximate ring on the 32 pt phone glyph: dash **1.6 / 1.6** (the north-arrow v2 vector),
  not 2 / 2.
- §5.3: the overview right-side words are ● `Verified`, ▲ `Approx.` (2k status vocabulary, not
  "Approximate"), ▲ `Partly`, ▲ `Not verified` (not "Not read": a floor with an inaccurate or
  rejected reading was read). Per-floor subtitle words stay `verified`, `approximate`, `not
  verified`, `not read`. The **Compass sheet is not built**: the row opens Before you leave with
  `focus: .compass` (R-21).
- §13.4: the launch environment `UITEST_COMPASS` becomes the launch argument
  `-ChapterUITestCompass verified|approximate|none` (R-24). `FakeCompass` also scripts the photo
  camera bearing (85° ±8 true → "E") used by phone-field's UI test.
- §8.3 `station/hub/src/north-arrow.ts` is spatial-report's `report/draw/north-arrow.ts`.

### G2. Absorbed from the other specs
- The rows of plan-sheet §4.6 are added to `contract/test-vectors/compass-states.json` (integer
  accuracies), and plan-sheet's separate vectors file is not created.
- phone-capture's step-2 "Read again" accessibility and row metrics are kept by the host; every
  string and algorithm here wins over phone-capture §3.3.1, §3.4 and §4.

### G3. Missing cases now stated (G-14)
- **Revision n+1**: base captures keep their stored compass fields (sealed data is never re-read);
  only new captures carry new readings.
- **Restart this floor instead** (phone-capture §3.4.1) discards the reading exactly like Try
  again (new ARSession, new W).
- **Pause/Resume** keeps the same session and the same window state (already implied by §3.3 step
  7; D5 verifies).

### G4. Q2 escalated (owner question Q-B)
The station check `orientation.compass` changes verdicts. Because the station deploys before the
app (§4.6), every package captured with today's app would become Limited. Recommended default
(critique): **1.0.0 capture records → check `not_applicable` with one info finding** (`No compass
reading recorded; orientation not verified`, the drawn sample's wording) and no limitation;
**1.1.0 records → §8.2 as written** (limitation for a not-verified floor). Until the owner
answers, T3 builds the recommended default behind one constant
(`COMPASS_LIMITATION_FOR_LEGACY_RECORDS = false`).

### G5. Device tests first (G-16)
T7 runs D0 and D1 on a prototype branch before the compass UI work and records the result in
`docs/qa/compass-device-tests.md` (owned by T7). If D1 finds C ≠ W, the convention goes into
`CompassMath.captureFrameYaw` (T0 follow-up PR) before T5/T4 rely on `heading`.

## Follow-ups (wave 2 review, built; recorded Oct 22, 2026)

These two corrections are in the code on `v2/main` and in `docs/waves/design/DESIGN.md`
("Design v2", "Compass rules settled after wave 2"); they override §1.2 rule 4's parenthesis,
§1.5's last row and §4.5.

- **No reading always names an issue.** A floor scanned with the compass records either the four
  reading fields or `headingIssue`; §1.5's "(no issue, no heading)" case no longer exists: readings
  that never paired with a scan frame (too few valid samples, tracking never normal) are
  `rejected`, `unavailable` is only "no usable compass on the phone", and `not_calibrated` still
  needs pairs to judge. A capture with neither was **not scanned with the compass** (a 1.0.0
  record, a floor carried over from a revision sealed before the compass, a build without the
  compass service): the station does not grade it (Q-B, `scannedBeforeCompass`). `FakeCompass`
  `none` records `not_calibrated`.
- **Fixture `two-floor-house`:** Floor 2 records `headingIssue: "not_calibrated"` (§4.5 said
  "none"), so the visit keeps the drawn compass-Limited state (Floor 1 verified, Floor 2 "not
  read", verdict Limited with "Floor 2: Plan orientation is not verified; north is not shown.").
