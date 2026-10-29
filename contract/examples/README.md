# Contract examples

One folder per schema in `contract/schema/`, named after the schema file without
`.schema.json`:

```
contract/examples/<schema>/valid/*.json    must pass the schema
contract/examples/<schema>/invalid/*.json  must fail the schema
```

The TypeScript and Swift contract tests read these same files. The valid examples describe one
site visit (`visitId` `7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5`) with two captures, so they agree
with each other:

| Capture | `captureId`                            | `areaKey` |
| ------- | -------------------------------------- | --------- |
| Floor 1 | `3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35` | `floor-1` |
| Floor 2 | `a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60` | `floor-2` |

The capture model examples are one file per capture: `floor-1.json` is schema 1.0.0 and
`floor-2.json` is schema 1.1.0 with the fields 1.1.0 adds (room `type` and `typeSource`, door
`isOpen`, object `attributes` and `parentId`). The address, people and numbers are illustrative
test data.

Older documents stay valid, so each schema with a 1.1.0 keeps its 1.0.0 example:

| Schema         | Valid example                      | Version | Shows                                                                                                                                                  |
| -------------- | ---------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| capture-record | `two-captures.json`                | 1.0.0   | no compass fields                                                                                                                                      |
| capture-record | `compass-two-captures.json`        | 1.1.0   | Floor 1 compass reading (`heading` 212.4, `headingAccuracy` 8, `headingSource` `true`, read 9 s after `capturedAt`); Floor 2 `headingIssue` `rejected` |
| manifest       | `two-captures.json`                | 1.0.0   | no `photo.directionSource`                                                                                                                             |
| manifest       | `photo-direction-source.json`      | 1.1.0   | one photo with `directionSource` `compass`, one with `manual`                                                                                          |
| manifest       | `legacy-spatial-report-1.0.0.json` | 1.0.0   | a package sealed by an app before v2: it lists the phone's `spatial-report.pdf` (role `spatial_report_pdf`, retired in 1.1.0)                          |
| capture-record | `sketch-capture.json`              | 1.2.0   | Floor 1 `captureSource` `lidar` with its compass reading; Floor 2 `sketch` with a limited `sketch` summary and no compass field (spec F14)             |
| manifest       | `sketch-capture.json`              | 1.2.0   | Floor 2's originals are `sketch.jpg` (`sketch_image`) and `sketch-measurements.json` (`sketch_measurements`); its capture model is derived from both   |

`sketch-measurements/valid/two-rooms.json` (1.0.0, one version) is Floor 2's entered
measurements: a measured bedroom with a door, a window and a squareness diagonal, and a closet
that shares the bedroom's wall-4, with an unmeasured wall and two "about" walls.

The shared compass vectors are in `contract/test-vectors/compass-states.json` (see the README
there).

Each invalid example is its valid example with exactly one defect:

| Schema              | Invalid example                          | Defect                                                                 |
| ------------------- | ---------------------------------------- | ---------------------------------------------------------------------- |
| capture-record      | `unknown-mode.json`                      | `captures[0].mode` is `whole_floor`, not `room`/`floor`/`exterior`     |
| capture-record      | `capture-without-capture-id.json`        | `captures[1]` has no `captureId`; every capture is registered by id    |
| capture-record      | `heading-in-1.0.0.json`                  | a 1.0.0 record with Floor 1's compass reading, added in 1.1.0          |
| capture-record      | `heading-without-accuracy.json`          | Floor 1 has `heading` without `headingAccuracy`; the four go together  |
| capture-record      | `heading-and-issue.json`                 | Floor 1 has `heading` and `headingIssue`; an issue means no heading    |
| capture-record      | `heading-360.json`                       | Floor 1 `heading` is 360; headings are `0 <= heading < 360`            |
| capture-record      | `unknown-heading-source.json`            | Floor 1 `headingSource` is `grid`, not `true`/`magnetic`               |
| capture-model       | `z-up.json`                              | `coordinateSystem.up` is `+Z`; the contract is +Y up                   |
| capture-model       | `room-type-in-1.0.0.json`                | Floor 1 (1.0.0) with a room `type` and `typeSource`, added in 1.1.0    |
| capture-model       | `unknown-room-type.json`                 | Floor 2 with `rooms[0].type` `garage`, outside the closed room types   |
| field-controls      | `measured-from-scan.json`                | a distance `method` is `scan`; only `tape` or `laser` count            |
| field-controls      | `landmark-in-one-capture.json`           | a shared landmark lists one capture; two or more are required          |
| manifest            | `unknown-role.json`                      | a file `role` is `revit_model`, outside the closed role enum           |
| manifest            | `capture-model-without-capture-id.json`  | a per-capture file (`capture_model`) has no `captureId` and `areaKey`  |
| manifest            | `visit-file-with-capture-id.json`        | a visit-wide file (`capture_record`) carries `captureId` and `areaKey` |
| manifest            | `unknown-direction-source.json`          | a photo `directionSource` is `gps`, not `compass`/`manual`             |
| manifest            | `direction-source-wrong-type.json`       | a photo `directionSource` is `true` (a boolean)                        |
| manifest            | `direction-source-in-1.0.0.json`         | a 1.0.0 manifest with `photo.directionSource`, added in 1.1.0          |
| manifest            | `retired-spatial-report-role-1.1.0.json` | a 1.1.0 manifest lists `spatial_report_pdf`, retired in 1.1.0          |
| capture-record      | `sketch-in-1.1.0.json`                   | a 1.1.0 record with `captureSource` and `sketch`, added in 1.2.0       |
| capture-record      | `sketch-without-source.json`             | Floor 2 has a `sketch` summary without `captureSource` `sketch`        |
| capture-record      | `sketch-with-heading.json`               | Floor 2 is a sketch capture with a `headingIssue`; sketches carry none |
| manifest            | `sketch-role-in-1.1.0.json`              | a 1.1.0 manifest lists `sketch_image`, added in 1.2.0                  |
| sketch-measurements | `door-with-sill.json`                    | a door has a `sill`; only windows have one                             |
| sketch-measurements | `source-without-path.json`               | `source.kind` is `hand_sketch` without the image's `path`              |
| verdict             | `ready-with-blocker.json`                | `outcome` is `ready` while a finding has severity `blocker`            |

Optional fields are omitted, never `null`. Timestamps are UTC with whole seconds
(`2026-10-17T14:02:11Z`). UUIDs and SHA-256 values are lowercase.
