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

The capture model example is the Floor 1 capture (one file per capture). The address, people
and numbers are illustrative test data.

Each invalid example is its valid example with exactly one defect:

| Schema         | Invalid example                         | Defect                                                                 |
| -------------- | --------------------------------------- | ---------------------------------------------------------------------- |
| capture-record | `unknown-mode.json`                     | `captures[0].mode` is `whole_floor`, not `room`/`floor`/`exterior`     |
| capture-record | `capture-without-capture-id.json`       | `captures[1]` has no `captureId`; every capture is registered by id    |
| capture-model  | `z-up.json`                             | `coordinateSystem.up` is `+Z`; the contract is +Y up                   |
| field-controls | `measured-from-scan.json`               | a distance `method` is `scan`; only `tape` or `laser` count            |
| field-controls | `landmark-in-one-capture.json`          | a shared landmark lists one capture; two or more are required          |
| manifest       | `unknown-role.json`                     | a file `role` is `revit_model`, outside the closed role enum           |
| manifest       | `capture-model-without-capture-id.json` | a per-capture file (`capture_model`) has no `captureId` and `areaKey`  |
| manifest       | `visit-file-with-capture-id.json`       | a visit-wide file (`capture_record`) carries `captureId` and `areaKey` |
| verdict        | `ready-with-blocker.json`               | `outcome` is `ready` while a finding has severity `blocker`            |

Optional fields are omitted, never `null`. Timestamps are UTC with whole seconds
(`2026-10-17T14:02:11Z`). UUIDs and SHA-256 values are lowercase.
