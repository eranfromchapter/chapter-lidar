# Compass device tests D0 and D1

Build spec `compass` §13.5 and addendum G5 (critique G-16). These two tests prove, on a real
iPhone, the two assumptions the whole compass rests on. They gate the compass UI: if D1 finds
that the capture frame is not the ARKit world frame, `CompassMath.captureFrameYaw` (contract,
track T0) is changed in a follow-up PR before the plan sheet (T5) and the spatial report (T4)
rely on `heading`.

| Test | What it proves | Status |
| --- | --- | --- |
| D0 | The Core Motion convention: `CompassMath` (`R_N←D` = transpose of `CMAttitude.rotationMatrix`) gives the bearing Core Location gives, and the gravity checks pass | **pending**: not run yet (no phone in the build environment of Oct 21, 2026) |
| D1 | The capture frame C of `capture-model.json` is the ARKit world W of the scan (φ = 0), so the stored `heading` turns the plan correctly | **pending**: not run yet; needs the app wiring of `CompassService` (track T10) |

Nothing in either test records the phone's position: the location is used only for true north
and its values are dropped by `CompassService`.

## D0: Core Motion against Core Location

**Harness.** `CompassDeviceCheck` (target `CaptureCompass`) records every 0.5 s, while the phone
is still, the bearing `CompassMath` computes from device motion next to `CLHeading`
(`CompassDeviceCheckLine`): flat, the bearing of the top edge; upright, the bearing of the back
camera. Each line also carries the Core Motion gravity check (gravity through `R_N←D` against
straight down). `CompassDeviceCheckReport.passes` when every compared line agrees within 3° and
every gravity check is within 3°. The device test `CompassDeviceCheckTests` runs it and attaches
the lines as `compass-d0.json`; it is skipped unless `COMPASS_D0_SECONDS` is set.

**Procedure.**

1. Away from steel, appliances and magnetic phone cases, find a straight line of known bearing:
   a building edge or kerb measured on a survey or tax map, or a reference compass held away from
   the phone. Write the bearing down (true north).
2. Run, for each posture below, with the phone still for the whole recording. A package's test
   runner has no location permission text, so Location is usually not granted: device motion
   then uses magnetic north and the lines compare with `CLHeading.magneticHeading`, which tests
   the same matrix convention (the known line is then compared with its magnetic bearing:
   true bearing − declination of the site).

   ```sh
   cd ios/Packages/CaptureCore
   TEST_RUNNER_COMPASS_D0_SECONDS=30 xcodebuild test -scheme CaptureCore-Package \
     -destination 'platform=iOS,id=<phone UDID>' -allowProvisioningUpdates \
     DEVELOPMENT_TEAM=<team id> -only-testing:CaptureCompassTests/CompassDeviceCheckTests \
     -resultBundlePath d0-<posture>.xcresult
   xcrun xcresulttool export attachments --path d0-<posture>.xcresult --output-path d0-<posture>
   ```

   - flat on a table, top edge along the line;
   - upright in portrait, back camera along the line;
   - upright, pitched up about 30°.
3. In each `compass-d0.json`: `difference` (CompassMath − Core Location, same north) per line,
   `gravityError` per line, and the summary.

**Pass.** Every compared line within 3° of `CLHeading`; every gravity check within 3°; flat and
the known line within ±max(`headingAccuracy`, 5°). A transposed matrix would fail the gravity
check at once (unit test `HeadingWindowTests.testATransposedAttitudeFailsTheGravityCheck`).

**Results** (fill in; one row per posture and phone).

| Date | Phone, iOS | Posture | Known bearing | Lines compared | Max \|difference\| | Gravity failures | Pass |
| --- | --- | --- | --- | --- | --- | --- | --- |
| pending | | flat | | | | | |
| pending | | upright | | | | | |
| pending | | pitched 30° | | | | | |

## D1: capture frame against ARKit world

**Harness.** `LiveCaptureSession` (created with the app's `CompassService`) does the scan-start
reading and, at Finish floor, the frame check of compass §3.4: it compares the yaw of every wall,
door, window, opening and object in RoomPlan's last live update with the final result built by
`RoomBuilder` / `StructureBuilder`, matched by identifier, and measures φ. The outcome is in
`CaptureSessionResult.compassDiagnostics` (`frameYaw`, `frameMatches`, `frameConsensus`, pairs,
windows, drops by reason, `conventionMismatch`) and in the log, subsystem
`com.hellochapter.capture`, category `compass`:

```sh
log stream --device <phone UDID> --predicate 'subsystem == "com.hellochapter.capture" AND category == "compass"'
```

Lines: `compass: reading(heading: …, accuracy: …, source: …, recordedAt: …); pairs …, windows …`,
`compass.frame_yaw …` (only when |φ| > 2°) and `compass.convention_mismatch` (more than half of
the pairs of the first 10 s failed a gravity check).

**Before it can run.** The field-test build must create the session with the compass:
`LiveCaptureSession(compass: compassService)`, one `CompassService` for the app (compass §3.5).
That wiring belongs to the app shell (track T10, `FieldTestEnvironment` and `AppModel`); today's
field-test build creates `LiveCaptureSession()` and records no reading.

**Procedure.**

1. Pick a rectangular room whose wall bearings are known (from a survey, the building plan or a
   satellite map: the bearing of one long wall, true north).
2. Field-test build, Location allowed. Scan the room as one floor ("One room"), holding the phone
   upright and steady for the first seconds; finish when the chip reads `N · true · ±{ACC}°`.
3. Repeat once with Pause / Resume in the middle (two RoomPlan segments, `StructureBuilder`).
4. Copy the package off the phone (see `FieldTestEnvironment.swift`). From `capture-record.json`
   take `heading` (H) and `headingAccuracy`; from `capture-model.json` take the long wall's
   direction (dx, dz) in the capture frame. In the plan frame (x = C.x, y = −C.z) the wall is
   (dx, −dz); its bearing is `(H + atan2(dx, −dz)) mod 180`, in degrees.
5. Read φ and the diagnostics from the log.

**Pass.** The wall's bearing from H agrees with the known bearing within ±max(accuracy, 5°) (mod
180); φ = 0 ± 1° with consensus on both scans. If φ is consistent but not 0, record it: the
convention goes into `CompassMath.captureFrameYaw` with this recording as a unit-test fixture.

**Results.**

| Date | Phone, iOS | Scan | H (stored) | ±acc | Known wall bearing | Bearing from H | φ (matches, consensus) | Pass |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| pending | | one segment | | | | | | |
| pending | | paused and resumed | | | | | | |

## Later device tests (not part of this gate)

D2 (five start directions), D3 (Location denied, then approximate location), D4 (next to a
refrigerator), D5 (several segments) and D6 (photo directions N/E/S/W) are in compass §13.5; they
run with the app once the screens and the compass are wired.
