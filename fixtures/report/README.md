# Report fixtures

Station verdicts for the design-sample package `fixtures/generated/sample-424`, one per outcome,
for the spatial report (cover states 1f Limited, 1g Ready, 1h Blocked; checks pages 1p–1r) and
the web review. The package itself is generated (`fixtures/generator/src/sample424.ts`); only the
verdicts live here.

| File                                | Outcome | What the checks saw                                                                                                                                                           |
| ----------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `424-west-end/verdict-limited.json` | limited | the package as generated: Primary closet not scanned (locked) and Storage room not entered, two limitations                                                                   |
| `424-west-end/verdict-ready.json`   | ready   | the same package with no skipped rooms in its capture record                                                                                                                  |
| `424-west-end/verdict-blocked.json` | blocked | the same package with the capture-record address changed to the second placeholder and one digit of `rooms.csv` changed after sealing: two blockers, plus the two limitations |

Every verdict is the output of the station checks (`station/checks`, `runChecks` with the HUB
address `100 Example Street, Testville, NY 00000`, `evaluatedAt` 2026-10-17T15:20:44Z) with the
compass check of the v2 rule set added as the station will report it (compass spec 8.2): the row
`orientation.compass` "Orientation (compass)" after `orientation.up`, passed, with one info
finding per capture ("True north from the compass.", measured "True heading 212°, accuracy
±8°"), and evaluator version `1.1.0` (13 rules). Package ids, paths and capture ids are those of
`sample-424`; `fixtures/generator/test/report.test.ts` checks it.

Re-record them when the station's wording changes: run `runChecks` on the three package states
above (`station/checks/test/helpers.ts` `withJson` / `withFile` make the changes) and write the
verdicts with two-space indentation.
