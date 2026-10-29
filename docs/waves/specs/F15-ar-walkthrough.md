---
id: F15
title: AR walkthrough capture (any iPhone)
depends_on: [F14]
owns: [ios/Packages/SketchCapture/Sources/Walkthrough/**, ios/Packages/SketchCapture/Sources/WalkthroughUI/**, contract/schema/walkthrough-log.schema.json]
reads: [docs/waves/specs/F14-sketch-capture.md, contract/**, ios/Packages/SketchCapture/**, ios/Packages/CaptureCore/**, ios/App/**, station/checks/**]
risk: [data]
steps: [F15.1, F15.2, F15.3, F15.4]
---

# F15 AR walkthrough capture (any iPhone)

## Summary

The owner tried the typed sketch flow (F14) and rejected it: it makes the operator do the
measuring, and the goal is that every user gets the same quality of scans, plans and 3D as a
LiDAR scan. This spec replaces typing as the main no-LiDAR path with an **AR walkthrough**: the
operator walks each room with the camera up and taps the floor corners, the openings and the
ceiling line on screen. Every tap is a metric 3D point from ARKit world tracking, which every
iPhone that runs iOS 17 has (camera plus motion sensors; no LiDAR needed). The walk is recorded
(video and camera poses) as the capture's raw original, the way `roomplan.json` is for a scan.
The typed sketch flow stays as the fallback and as a tape override.

## 1. What this can and cannot match (owner's question, answered plainly)

| Output                       | LiDAR scan                         | AR walkthrough, any iPhone                                    |
| ---------------------------- | ---------------------------------- | ------------------------------------------------------------- |
| Rooms, walls, openings       | detected automatically, about 1 cm | tapped by the operator, about 1 to 3 % of a length; about 0.3 % with one tape check per floor (1.3) |
| Plan sheet, Floorplan, DXF, CSV, SVG, PNG | yes                   | yes, the same writers                                         |
| 3D model (GLB, OBJ)          | the real scanned surfaces          | extruded from the walls and the ceiling height, openings cut (F14 `SketchMesh`) |
| Point cloud (LAS), furniture | yes                                | no                                                            |
| Station checks, spatial report, HUB | yes                          | yes; rule 14 says how the geometry was measured               |
| Replayable raw record        | `roomplan.json`, depth samples     | `walkthrough.mp4` and `walkthrough-log.json` (every tap and camera pose) |

An iPhone without LiDAR has no depth sensor. Nothing on the phone can produce a dense mesh or
point cloud of the walls; a server-side reconstruction from the recorded video (photogrammetry,
Gaussian splatting) is possible later because the video and the metric poses are kept, but it is
research work and out of scope here. **Plans and the package reach LiDAR quality with one tape
check; the 3D is a clean extruded model, not a scan of the surfaces.** If scanned 3D surfaces
are required for every capture, the answer is LiDAR phones (iPhone Pro) for the field team.

## 2. Flow

```
Captures home ── Capture without LiDAR ──► New capture (step 1: HUB project, address; no LiDAR gate)
  ──► How do you want to measure? (step 2: Walk the rooms with the camera [recommended] / Enter from a sketch)
  ──► Walk the rooms (step 3, AR, full screen)
        per room: name ► tap each floor corner in order, close the loop on the first corner
                  ► tap where a wall meets the ceiling (once per room; the floor's value is offered for the next room)
                  ► add doors, windows and openings: left jamb, right jamb (at the floor for doors and openings,
                    on the wall for windows), then the head; windows also the sill
                  ► Next room / Done
  ──► Check the scale (step 4, recommended): tape one long wall, type it; shown as the scale correction
  ──► Check (the F14 Check screen: plan, notes, Complete / Limited) ──► Finish floor ──► photos ──► overview … as today
```

- **Reticle and taps.** A reticle at the screen centre sits on the detected floor plane
  (ARKit horizontal plane detection, raycast `.estimatedPlane` / `.existingPlaneInfinite`). A
  tap button (not a tap anywhere) adds the reticle's point. Wall-level points (window jambs,
  sills, heads, the ceiling line) are the intersection of the centre ray with the **vertical
  plane of a wall already defined by its two floor corners**, the wall the ray meets first inside
  its extent; no vertical plane detection is needed.
- **Furniture in a corner.** Per room the operator can switch to "Tap each wall": two floor
  points anywhere along the base of each wall, in order; the corners are the intersections of
  consecutive wall lines.
- **Closing the loop.** The last corner tap on the first corner (snapped when within 0.25 m) closes
  the room. The gap between the first tap and the closing tap is the **loop drift**; it is
  distributed back along the corners in proportion to the time since the first tap (drift grows
  with time) and graded with the station's tolerance (F14 1.4).
- **Overlay.** Tapped corners, walls and openings are drawn in AR (SceneKit nodes) and as a live
  2D outline in a corner of the screen, with each wall's length.
- **Undo** removes the last tap. **Tracking** is shown: when ARKit reports limited tracking the
  tap button is disabled and the screen says why ("Move slower", "More light", "Point at the
  floor").
- **Recording.** The camera image is recorded at 1280 px wide, about 15 frames per second, HEVC,
  to `walkthrough.mp4`; each recorded frame's camera pose and tracking state goes into
  `walkthrough-log.json` with the intrinsics and every tap. Audio is not recorded. Recording never
  blocks the taps; a recording error leaves the taps and the log.

## 3. From taps to the model

The walkthrough is converted into the F14 document (`sketch-measurements.json`, source kind
`ar_walkthrough`) and solved by the F14 solver, so there is one solver, one model writer and one
station rule:

1. Corners on the floor plane (y of the floor), loop drift distributed (2), wall lines intersected
   for "Tap each wall" rooms.
2. Each wall's length = distance between its corners, `measured: true`. Each corner's turn: left
   or right when its angle is within 5° of 90° (squared by the solver), else `unsquare` with the
   diagonals across it computed from the corners (`measured: true`), so the solver keeps the
   angle.
3. Openings: width = distance between the jambs along the wall; `fromCornerDistance` from the
   wall's start corner to the nearer jamb; height = head − floor (doors, openings) or head − sill
   (windows); sill = sill − floor.
4. Ceiling: the mean of the room's ceiling taps above the floor.
5. **Scale check (recommended):** a tape length of one wall gives the scale factor
   `tape / AR length`, applied to every length of the floor before solving. Without it the scale
   is the phone's own (recorded as `scaleSource: ar`).
6. Rooms that share a wall: two rooms are placed in one AR frame, so shared walls need no
   `sharedWith`; the converter writes each room's corners in the common frame and the solver
   keeps each room where it was walked (`SketchSolveContext.keepPlacement`, new).

Accuracy notes for the dev team: world tracking without LiDAR drifts about 1 % of the distance
walked; the closing tap and the scale check are what keep it at plan quality. Large open floors
should be walked room by room with the loop closed in each room.

## 4. Contract (still 1.2, not merged yet)

- Capture record 1.2.0: `captureSource` gains `walkthrough`. The `sketch` summary is present for
  `sketch` and `walkthrough`. New `walkthrough` object, present exactly when the source is
  `walkthrough`: `scaleSource: tape | ar`, `scaleFactor` (when tape), `loopClosureMm` (largest
  room loop gap before distribution), `trackingLimitedSeconds`, `recorded: true|false` (video).
- Manifest 1.2.0: roles `walkthrough_video` (MP4 or QuickTime) and `walkthrough_log` (JSON),
  in Original Exports.
- New schema `walkthrough-log` 1.0.0 (start and finish time, intrinsics, frames with time,
  camera-to-world transform and tracking state, floor height, rooms with their taps, the scale
  check). Every point is in the walkthrough's own AR frame, metres, +Y up.
- Sketch measurements 1.0.0: `source.kind` gains `ar_walkthrough` (path: the walkthrough log).

## 5. Station

- Parsers: `walkthrough_video` (ISO base media `ftyp`), `walkthrough_log` (schema-checked JSON).
- Rule 14 `sketch.measurements` covers walkthrough captures: "Geometry of Floor 1 comes from an
  AR walkthrough, not a LiDAR scan"; limitations as for a sketch, plus "scale comes from the
  phone's motion tracking only" when `scaleSource` is `ar` and the floor has no field-control
  distance, and a loop closure over the tolerance.
- Compass rule: a walkthrough capture is not graded (as a sketch).
- Missing `walkthrough_log` is a limitation (the raw record is gone); a missing video is info.

## 6. Out of scope

Server-side reconstruction from the video; automatic wall and opening detection on non-LiDAR
phones (no reliable on-device method); furniture; the compass heading of a walkthrough (ARKit's
`gravityAndHeading` frame could give it later).

## 7. Acceptance criteria

```yaml criteria
AC1: {text: "A walked 4.000 x 3.000 m rectangle (corner taps with 20 mm noise and a 60 mm loop gap) converts and solves to walls within 25 mm and square corners; with a tape check of one wall the other walls are within 10 mm", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter WalkthroughTests"}
AC2: {text: "Tap each wall: two points per wall of an L-shaped room give the six corners within 10 mm", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter WalkthroughTests"}
AC3: {text: "Openings from jamb, sill and head taps get width, height, sill and position within 10 mm of the walked truth", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter WalkthroughTests"}
AC4: {text: "walkthrough-log 1.0.0, capture record and manifest examples validate in TypeScript and Swift; F14 examples stay valid", verify: "cmd:npm test --workspace contract/ts && swift test --package-path contract/swift"}
AC5: {text: "The station gives a walkthrough package with a tape check a Ready verdict and one without any scale reference a Limited verdict naming the scale", verify: "test:station/checks/test/walkthrough.test.ts"}
AC6: {text: "In the replay mode the UI test walks one room (four corners, a door, a window, the ceiling), checks the scale and reaches Package ready", verify: "cmd:scripts/wait-workflow.sh ios.yml App"}
```

## Steps

- F15.1 Contract additions (this spec, section 4).
- F15.2 `Walkthrough` target: log types, converter (taps to sketch measurements), drift, wall lines, scale; tests.
- F15.3 iOS: AR session protocol with a live ARKit implementation and a replay one, recording, the AR screen, the method choice, app integration, UI test.
- F15.4 Station: parsers, rule 14 and the compass rule for walkthrough captures, tests.
