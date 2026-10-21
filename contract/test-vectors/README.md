# Contract test vectors

Shared inputs and expected outputs that the Swift and TypeScript contract tests both run, so the
phone, the plans, the station and the web agree byte for byte.

## `compass-states.json`

One array of vectors for the compass evaluator (capture record 1.1.0):

```json
{
  "name": "true ±11 is approximate (lower boundary)",
  "capture": {
    "capturedAt": "…",
    "finishedAt": "…",
    "heading": 45,
    "headingAccuracy": 11,
    "headingSource": "true",
    "headingRecordedAt": "…"
  },
  "rotationCcw": 0,
  "expected": {
    "kind": "approximate",
    "word": "approximate",
    "symbol": {
      "kind": "arrow",
      "angleCcw": 45,
      "approximate": true,
      "lines": ["Approx. north · compass", "±11° · true"]
    },
    "detail": "Approximate north: true heading 45°, accuracy ±11°"
  }
}
```

- `capture`: the capture-record fields the evaluator reads (`capturedAt`, `finishedAt`, the four
  `heading*` fields or `headingIssue`). Every vector is valid in a 1.1.0 capture record.
- `rotationCcw`: how far the drawing turns the plan counter-clockwise, degrees.
- `expected.kind`: `verified`, `approximate` or `not_verified`; `reason` (`no_reading`,
  `rejected`, `inaccurate`, `not_calibrated`, `unavailable`) and, for `inaccurate`, `accuracy`.
- `expected.symbol`: the north symbol: `arrow` with `angleCcw` (A = (heading + rotationCcw) mod
  360, compared within 1e-9), `approximate` and the two caption lines, or `box` with
  `Orientation: not verified` and the reason caption.
- `expected.detail`: the station detail and web phrase; `expected.word`: the summary word
  (`verified`, `approximate`, `not verified`, `not read`).

The vectors cover every rule (no reading, the three issues, the reading-time window with its 60 s
slack and the open-scan 24 h limit, the ±10° / ±30° boundaries for true and magnetic north), the
number formatting (`359.6` prints `0`, half up `212.5` prints `213`) and the drawing rotations of
compass spec 2.5.

Runners: `contract/swift/Tests/CaptureContractTests/CompassTests.swift` and
`contract/ts/test/compass.test.ts`.
