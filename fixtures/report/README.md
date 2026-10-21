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

Every verdict is recorded by `fixtures/generator/src/report.ts`: the station checks
(`station/checks`, `runChecks`, from its sources) run on the three package states above with the
HUB address `100 Example Street, Testville, NY 00000`, `evaluatedAt` 2026-10-17T15:20:44Z and a
pinned `verdictId` per outcome (`…8c10` ready, `…8c11` limited, `…8c12` blocked; the station's
derived id would be the same for all three, and pinned ids survive a rule-set change). Until the
station runs the compass check of the v2 rule set (compass spec 8.2, track T3), the recorder adds
it as the station will report it: the row `orientation.compass` "Orientation (compass)" after
`orientation.up`, passed, one info finding per capture in the station's field order and check
order ("True north from the compass.", measured "True heading 212°, accuracy ±8°"), and
evaluator version `1.1.0` (13 rules). Once the station has the rule, its own output is recorded
unchanged. Package ids, paths and capture ids are those of `sample-424`.

```
npm run record-report --workspace @chapter/fixtures             # rewrites the three files
npm run record-report --workspace @chapter/fixtures -- --check  # exits 1 if any would change
```

`fixtures/generator/test/report.test.ts` checks the files against the schema and the package,
and that they are exactly what the recorder gives, byte for byte. When the station's wording or
the sample package changes (`npm run generate` first), re-record and commit the three files.
