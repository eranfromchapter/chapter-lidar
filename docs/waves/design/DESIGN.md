# Design (FROZEN)

- Source: Claude Design canvas "Chapter Capture design" — https://claude.ai/artifact/323A4A7aotJg9TMvDxHYGS (version 1792260478-bbee)
- Approved: 2026-10-17 by Eran Polack
- Snapshot: docs/waves/design/snapshot.html (assembled from the approved artboard sources, because the
  canvas page itself is the editor shell; markup and values are unchanged)

| Screen id | Feature | Contains |
|---|---|---|
| tokens | all | colour, type, spacing, radius, controls |
| screen-capture | F2 | 1 New capture (HUB project, address confirm) · 2 What are you scanning (floor/area, mode, skipped rooms, coverage notes) · 3 Live scan |
| screen-field | F5 | 1 Photo labeling (room, direction, subject) · 2 Field controls · 3 Before you leave checklist |
| screen-package | F6 | 1 Package ready (folder layout, sizes, seal) · 2 Uploading + station status |
| screen-review | F10 | Web: project list · package detail (verdict, findings, files) · modeling decision log |

## Tokens

- Colour: ink #1F2429, ground #F5EFE6, surface #FAF5EE, nude #E8DDD0, line #D9CCBC, muted #6B6557,
  ready #2E5E2E, limited #9A6A1E (text #7A5214), blocked #8B2E2E.
- Verdicts always carry a word and a shape: ● Ready, ▲ Limited, ■ Blocked. Never colour alone.
- Type: display/title serif (Times New Roman) 34/30/24; body sans 17 (iOS SF, web Helvetica); caption 13; mono 13 for sha256 and ids.
- Space 4·8·12·16·24·32·48. Radius chip 8, card 12, sheet 16. Phone touch targets ≥ 52 px for primary actions, ≥ 44 px for chips.
- Wordmark: "chapter" serif with "RENOVATION" letter-spaced beneath. No other mark.

## Decisions the design fixes (contract must match)

- Capture mode values shown to users: One room, Whole floor, Exterior → contract enum `room`, `floor`, `exterior`.
- Photo direction: N, E, S, W. Photo subject: opening, cabinetry, ceiling, fixture, defect, general (plus equipment in the enum, reached via More).
- HUB link rule shown on screen-review: files over 45 MB are "Linked (over 45 MB)".
- Example values in the mockups (618 Valley Street, distances, sizes) are illustrative; [BRACKETS] are live data.

FROZEN: changes after approval require replanning.
