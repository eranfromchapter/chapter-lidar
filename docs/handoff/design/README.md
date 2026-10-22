# Design v2 specs

The build specs of Chapter Capture v2, written on Oct 21, 2026 for the engineers who built v2.
They are copied here unchanged in `specs/`. Each spec quotes every value it needs from the design,
so you do not have to open the design bundle to build from it.

## Which document wins

When two documents disagree, the higher one wins:

1. **Owner decisions** (Eran Polack, Oct 21, 2026; binding). Recorded in
   `docs/waves/design/DESIGN.md`, section "Design v2", "Owner decisions" (`DESIGN.md:73-108`),
   and at the top of each spec. In short: the real Chapter logo and Inter everywhere; the web in
   the HUB look; the plan sheet made on the phone (Tabloid 11 x 17); the spatial report made on
   the station; the compass in three states (±10° / ±30°); the colour Floorplan unchanged.
2. **`specs/00-critique.md`**: the completeness critique. Its resolutions (R-n) are binding.
3. **The area spec's addendum**: the section "Addendum (completeness critique, Oct 21, 2026) —
   binding, overrides the body above" at the end of each area spec.
4. **The area spec's body.**

Two more notes from the specs themselves:

- When two area specs still disagree after the critique, the spec that owns the topic wins
  (ownership table in `00-critique.md` section 2.0), then any other spec (`00-critique.md:16-17`).
- The owner's open questions Q-A to Q-G are in `00-critique.md` section 5. The build ships the
  default of each; see [05-status-open-items.md](../05-status-open-items.md#61-owner-questions-q-a-to-q-g-defaults-applied-in-the-build).

The specs say what to build. They were written against branch `feat/floorplan-report` at
`05f16e8`, so file paths and "current code" notes in them refer to that base. What was built is
on `v2/main`, described in `DESIGN.md` "Design v2" and the F-specs (`docs/waves/specs/F1.md`-`F13.md`).
`compass.md` ends with "Follow-ups (wave 2 review, built; recorded Oct 22, 2026)".

## The specs

| File                                         | Area                                                                                            | Artboards                                             | Built in                                                          |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------- | ----------------------------------------------------- | ----------------------------------------------------------------- |
| [00-critique.md](specs/00-critique.md)       | Completeness critique: coverage, contradictions with binding resolutions, gaps, owner questions | all                                                   | —                                                                 |
| [00-tracks.md](specs/00-tracks.md)           | Build tracks T0-T11, merge order, deploy order, frozen interfaces, definition of done           | —                                                     | —                                                                 |
| [phone-capture.md](specs/phone-capture.md)   | Phone capture screens and phone screen tokens (F2)                                              | 2b, 2k (phone)                                        | `ios/Packages/CaptureCore`, `ios/Packages/ChapterUI`, `ios/App`   |
| [phone-field.md](specs/phone-field.md)       | Photos, field controls, entry sheet, Before you leave, rename rooms (F5)                        | 2d                                                    | `ios/Packages/FieldKit`                                           |
| [phone-package.md](specs/phone-package.md)   | Package ready, Package status, Verdict received, Revision n, notifications (F6)                 | 2f                                                    | `ios/App`, `ios/App/AppCore`, `ios/Packages/PackageKit`           |
| [plan-sheet.md](specs/plan-sheet.md)         | Plan sheet on Tabloid 11 x 17, north arrow, previews (F3)                                       | 1b, 1d, 1ab, 1ac                                      | `ios/Packages/PlanExport`                                         |
| [spatial-report.md](specs/spatial-report.md) | Spatial report made on the station after the checks (F9)                                        | 1f-1i, 1k-1l, 1n, 1p-1r, 1t, 1u, 1w-1aa               | `station/hub/src/report`, `station/worker`                        |
| [web-review.md](specs/web-review.md)         | Web review in the HUB design system (F10)                                                       | 2h, 2i, 2j, 2k (web)                                  | `web/`                                                            |
| [compass.md](specs/compass.md)               | Compass reading and north arrow, end to end                                                     | 1d and the compass parts of 2b, 2d, 2f, 1b, 1f-1r, 2j | `contract/`, `ios/Packages/CaptureCore`, `station/checks`, `web/` |

Artboard index: `DESIGN.md:58-71`.

## Design source

- **Claude Design project (v2):** <https://claude.ai/design/p/8b217162-6799-4e1c-bd1f-b6654a8c0e68?file=canvas%2FChapter+Capture+v2.dc.html>
  (canvas "Chapter Capture v2", artboards 1b-1ac and 2b-2k, approved by Eran Polack on Oct 21,
  2026; `DESIGN.md:52-56`). Opening it needs a Claude account with access to the project
  (**Input needed**: ask the owner for access).
- v1 design (frozen, the record of the first build): <https://claude.ai/artifact/323A4A7aotJg9TMvDxHYGS>
  (`DESIGN.md:3`), snapshot `docs/waves/design/snapshot.html`.
- The design bundle files (HTML canvases, images) are not copied into this kit.
