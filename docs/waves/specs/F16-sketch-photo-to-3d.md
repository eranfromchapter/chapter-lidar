---
id: F16
title: Sketch photo to 3D model
depends_on: [F14, F15]
owns: [contract/schema/sketch-interpretation.schema.json, contract/prompts/**, station/api/src/routes/sketch/**, ios/Packages/SketchCapture/Sources/SketchInterpretation/**]
reads: [docs/waves/specs/F14-sketch-capture.md, docs/waves/specs/F15-ar-walkthrough.md, contract/**, station/api/**, ios/**]
risk: [data, security]
steps: [F16.1, F16.2, F16.3, F16.4]
---

# F16 Sketch photo to 3D model

## Summary

The owner's target, in his words: a user takes a photo of a sketch and gets the 3D model (the
3D Snap ad, Oct 29, 2026). F14 made the user type every length; F15 made the user walk the
room. F16 is the one-photo path: the photo goes to the station, **Claude (vision) reads the
drawing** (rooms, walls, doors, windows, furniture symbols and any dimensions written on it), and
the app turns that reading into the F14 sketch measurements, so the existing solver, plans,
package and checks are reused. The 3D model gains the furniture from the sketch and colour.

Owner decision (Oct 29, 2026): sketch photos may go from the phone to the station and from the
station to Anthropic's API. The station holds the API key; the phone never does in production.

## 1. What it promises, plainly

- **Shape** (rooms, walls in order, where the openings and furniture are): read from the drawing.
- **Size:** from the dimensions written on the sketch. Without any, the app asks for **one**
  length (a wall the user knows), and every other length follows the drawing's proportions.
- **Accuracy:** a dimensioned sketch gives the drafter's numbers. An undimensioned one is as
  accurate as the drawing's proportions (often 10 to 30 % off on a hand sketch); every length not
  written on the sketch is marked estimated, and the station says Limited. The ad's "100 %
  accurate measurements" is not something a drawing can give.
- **3D:** walls extruded to the ceiling height (written on the sketch, else 2.44 m), openings cut,
  furniture as simple coloured blocks of the sketched size, floor and walls coloured. Not a
  photoreal render.

## 2. Flow

```
Captures home ── Capture without LiDAR ──► project, address ──► How to measure?
   Photograph a sketch (new, first) | Walk the rooms with the camera | Enter from a sketch
  ──► take the photo / choose from Photos / import a file
  ──► "Reading your sketch…" (station, typically 10 to 40 s)
  ──► One length (only when the sketch has no written dimensions): tap a wall on the drawn plan, type its length
  ──► Check: the plan, a 3D preview (rotate with a finger), what was read and what is estimated; rename rooms; fix a length
  ──► Finish floor ──► photos ──► overview … as today
```

When the photo is not a floor plan, or cannot be read, the app says why and offers to retake it
or to enter the sketch by hand (F14).

## 3. Contract (1.2, still unmerged)

- New schema `sketch-interpretation` 1.0.0: what the station returns and the package keeps
  (role `sketch_interpretation`, `Original Exports/{areaKey}/{captureId}/sketch-interpretation.json`):
  `model`, `interpretedAt`, `image` (width, height), and `reading`, Claude's structured output:
  `isFloorPlan`, `problem`, `dimensionUnits`, `rooms` (label, type, corners in drawing
  coordinates, openings by wall and position along it, furniture by centre, size and angle),
  `dimensions` (each written label, its value in millimetres when readable, and the wall it
  measures). Drawing coordinates: origin top-left, y down, the image's longer side is 1000. The
  `reading` part is the structured-output format, so its absent values are `null` (the one
  documented exception to "omitted, never null").
- Sketch measurements 1.0.0: optional `furniture` per room (`category`, centre `x`/`z` in the
  capture frame, `widthM`, `depthM`, optional `heightM`, `angleDeg`); source kind `hand_sketch`
  or `existing_plan` with `interpretation` (package path of the interpretation).
- Manifest 1.2.0: role `sketch_interpretation`. Capture record: unchanged (`captureSource:
  sketch`).
- OpenAPI 1.2.0: `POST /v1/sketch-interpretations` (role `capture`), JSON body `{mediaType,
  data (base64), hint?}`, image at most 10 MB; answers 200 with the interpretation, 422 when the
  image is unreadable or not a plan (the interpretation explains), 503 when the station has no
  API key or Claude is unavailable.
- The prompt is one file, `contract/prompts/sketch-interpretation.md`, used by the station and
  (Debug field test only) the app.

## 4. From the reading to the model (`SketchInterpretationConverter`, Swift, Linux-tested)

1. Scale (mm per drawing unit): the median of the written dimensions' `valueMm / drawn length`
   (outliers more than 15 % from the median dropped and noted); else the user's one length.
2. Each room's corners × scale become the capture frame (x right, z down the drawing: plan up
   is −Z). Walls: lengths from the corners, `measured: true` where a written dimension measures
   that wall (its value replaces the drawn length), else `measured: false` (estimated). Turns:
   square within 10° (hand sketches are wobbly), else unsquare with diagonals; room `placement`
   from corner 0.
3. Openings: width and offset from the positions along the wall; door and window heights and
   sills left to the solver's defaults (marked estimated).
4. Furniture: centre and size × scale, angle, category (contract object categories).
5. Ceiling: a written ceiling height when the reading has one, else none (the solver assumes
   2.44 m and marks it).

## 5. 3D

`SketchMesh` adds each furniture item as a box (height by category when not given) and colours:
floor oak, walls warm white, openings' reveals light grey, furniture by category. The capture
model carries the furniture as `objects` (category, oriented box), so the plan sheet and the
Floorplan draw it as they draw scanned objects. GLB `COLOR_0` and OBJ vertex colours carry the
colour.

## 6. Station

- `@anthropic-ai/sdk`, model `claude-opus-5-5` (config `SKETCH_MODEL`), adaptive thinking,
  structured output (`output_config.format` with the reading schema), server-side refusal
  fallback (`fallbacks: "default"`), timeout 120 s, at most 2 retries (SDK default).
- `ANTHROPIC_API_KEY` from Key Vault (secret `anthropic-api-key`); without it the route answers
  503 and the app offers the manual sketch.
- The image is not stored by the station; the app keeps the photo and the interpretation in the
  package. Audit log entry per call (who, when, size, model, outcome, tokens), no image content.

## 7. Acceptance criteria

```yaml criteria
AC1: {text: "A reading of a 4 x 3 m room with written dimensions 13' 1.5\" and 9' 10.5\" converts to walls within 1 mm of the written values, measured, and solves Complete apart from defaulted heights", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter InterpretationTests"}
AC2: {text: "A reading without dimensions plus one user length gives every other wall by proportion, estimated, Limited", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter InterpretationTests"}
AC3: {text: "Furniture in the reading becomes capture model objects and coloured boxes in the GLB; the GLB passes the validator", verify: "cmd:swift test --package-path ios/Packages/SketchCapture --filter 'InterpretationTests|MeshTests'"}
AC4: {text: "POST /v1/sketch-interpretations calls Claude with the image and the reading schema, answers 200 with a contract-valid interpretation, 422 for a non-plan, 503 without a key; tests mock the SDK", verify: "test:station/api/test/sketch/sketch-interpretation.test.ts"}
AC5: {text: "In the replay mode the UI test photographs the fixture sketch, gets the stub interpretation, enters one length, sees the 3D preview and reaches Package ready", verify: "cmd:scripts/wait-workflow.sh ios.yml App"}
```

## Steps

- F16.1 Contract: schema, prompt, sketch-measurements furniture, role, OpenAPI route.
- F16.2 Station route.
- F16.3 Converter, furniture and colour in solver and mesh.
- F16.4 iOS flow, interpreter clients (station; Debug direct), stub, 3D preview, UI test.
