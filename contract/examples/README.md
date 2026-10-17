# Contract examples

One folder per schema in `contract/schema/`, named after the schema file without
`.schema.json`:

```
contract/examples/<schema>/valid/*.json    must pass the schema
contract/examples/<schema>/invalid/*.json  must fail the schema
```

The TypeScript and Swift contract tests read these same files. Valid examples share one
capture (`captureId` `3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35`, two floors) so they agree with
each other. The address, people and numbers are illustrative test data.

Each invalid example is its valid example with exactly one defect:

| Schema         | Invalid example           | Defect                                                          |
| -------------- | ------------------------- | --------------------------------------------------------------- |
| capture-record | `unknown-mode.json`       | `areas[0].mode` is `whole_floor`, not `room`/`floor`/`exterior` |
| capture-model  | `z-up.json`               | `coordinateSystem.up` is `+Z`; the contract is +Y up            |
| field-controls | `measured-from-scan.json` | a distance `method` is `scan`; only `tape` or `laser` count     |
| manifest       | `unknown-role.json`       | a file `role` is `revit_model`, outside the closed role enum    |
| verdict        | `ready-with-blocker.json` | `outcome` is `ready` while a finding has severity `blocker`     |

Optional fields are omitted, never `null`. Timestamps are UTC with whole seconds
(`2026-10-17T14:02:11Z`). UUIDs and SHA-256 values are lowercase.
