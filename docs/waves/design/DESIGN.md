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

### Brand update (2026-10-19, requested by Eran Polack)

Every plan, report and web page now uses the Chapter brand of hellochapter.com. This replaces the
type and wordmark lines above; the colour tokens are unchanged.

- Type: Times for titles and headings, Inter for all other text (web: self-hosted
  `web/public/brand/inter-400.woff2` and `inter-600.woff2`; PDFs embed Inter and use Times-Roman).
  Inter replaces SF on the phone; Times for display titles (owner decision, Oct 21, 2026; see
  "Design v2" below).
- Logo: the real Chapter logo (bold sans "chapter" over letter-spaced "RENOVATION"),
  `web/public/brand/chapter-logo.svg`, never retyped. The HUB header is a light surface bar so the
  brand-black logo shows (it was an ink bar).
- Plans: brand black #231F20, warm charcoal walls #4D4744, bronze inside dimensions #7A6347 and
  warm room tints by room type (`ChapterBrand.swift`). `tools/brand/generate_plan_brand.py`
  regenerates the logo paths and fonts.

## Decisions the design fixes (contract must match)

- Capture mode values shown to users: One room, Whole floor, Exterior → contract enum `room`, `floor`, `exterior`.
- Photo direction: N, E, S, W. Photo subject: opening, cabinetry, ceiling, fixture, defect, general (plus equipment in the enum, reached via More).
- HUB link rule shown on screen-review: files over 45 MB are "Linked (over 45 MB)".
- Example values in the mockups (618 Valley Street, distances, sizes) are illustrative; [BRACKETS] are live data.

FROZEN: changes after approval require replanning.

## Design v2 (Oct 21, 2026)

The approved replan of the frozen design above. Source: the Claude Design project "Plan of
changes review" (canvas "Chapter Capture v2", artboards 1b–1ac and 2b–2k), approved by Eran
Polack on Oct 21, 2026, with the build specs and their completeness critique of the same day.
Where a line above disagrees with this section, this section wins; the v1 screens above are
kept as the record of the first build.

| Screen id | Feature | Contains |
|---|---|---|
| 1b plan-sheet-v2 | F3 | the plan sheet: one Tabloid 11 x 17 landscape page per capture, made on the phone |
| 1d north-arrow-v2 | F2, F3, F9 | the north symbol in its three states, with captions |
| 1f–1i report-cover-v2 | F9 | spatial report cover: Limited, Ready, Blocked (not verified), 2 floors |
| 1k–1l report-plan-v2, 1n report-schedule-v2 | F9 | plan page per floor, room schedule |
| 1p–1r report-checks-v2 | F9 | capture checks pages (Limited, Ready, Blocked) |
| 1t, 1w–1aa report-room-v2, 1u report-photos-v2 | F9 | room pages, photo pages |
| 1ab system-v2, 1ac bw-proof-v2 | F3, F9 | tokens of the printed outputs; black-and-white proof |
| 2b app-capture-v2 | F2 | Captures home, New capture, What are you scanning (compass), Live scan, Capture overview |
| 2d app-field-v2 | F5 | Photos, Field controls, Before you leave (compass item), sheets |
| 2f app-package-v2 | F6 | Package ready, Package status, Verdict received, Revision n |
| 2h, 2i, 2j web-review-v2 | F10 | web: projects, project, package |
| 2k screen-tokens-v2 | all | phone and web tokens |

### Owner decisions (Oct 21, 2026; binding)

- **The real Chapter logo everywhere, never the typed wordmark.** Phone: `ChapterLogo`
  (ChapterUI, paths generated from `tools/brand/chapter-logo.svg`); plan sheet and spatial
  report: the same logo as vector paths; web: the HUB `chapter-wordmark.svg`, white on the HUB
  sidebar. No "chapter / RENOVATION" is typed in any font anywhere.
- **Inter everywhere.** Phone: Inter replaces SF on the app's own screens (registered by
  ChapterUI only, never through `UIAppFonts`); Times New Roman for the display titles; the system
  monospaced font for ids. Every PDF embeds Inter (Regular and SemiBold): the plan sheet and the
  spatial report use Inter for text, Times-Roman for titles (the sheet's tagline Times-Italic) and
  Courier for ids, dimensions and scale labels. This replaces "The iOS app's own screens keep SF"
  of the Oct 19 brand update.
- **Web in the HUB look.** The web review is drawn in the HUB design system (2h, 2i, 2j): HUB
  tokens, the white HUB wordmark in the sidebar, Inter 400/600 self-hosted from
  `web/public/brand/` (no Google font request), no Times on the web. Sign-in, not-found, error
  and configuration pages use the same look. screen-review (F10) is replaced by web-review-v2.
- **The plan sheet is made on the phone, with no verdict.** `plan-sheet.pdf` (role `plan_pdf`),
  one Tabloid 11 x 17 landscape page (1224 x 792 pt) per capture, drawn at the first rung of the
  scale ladder at which it fits. The phone's Spatial Report PDF is retired: no package sealed by
  the v2 app has a `spatial_report_pdf` file (manifest 1.1.0); a legacy 1.0.0 package keeps it,
  and the station lists it with a station link and never uploads it to the HUB.
- **The spatial report is made on the station after the checks**, and replaces the station's
  verdict report: `spatial-report-{verdictId}.pdf` (pdfkit, Inter, the real logo), uploaded to
  the HUB folder `Capture/{visitId}/r{revision}`, stored in the `reports` container and
  downloadable from the web through `GET /packages/{packageId}/spatial-report` (bim and admin).
- **Compass, three states, thresholds ±10° / ±30°.** The phone reads the compass at the start of
  each floor's scan; the reading is never typed by hand or taken from a map. verified: true north
  with accuracy ±10° or better (solid arrow, "True north · compass", "±{ACC}° · {HDG}°");
  approximate: true north ±11–30°, or magnetic north ±30° or better (dashed ring, hollow arrow,
  "Approx. north · compass"); not verified: no arrow, the box "Orientation: not verified" and the
  reason ("No compass reading", "Reading rejected", "Compass accuracy ±{ACC}°", "Compass not
  calibrated", "Compass unavailable"). One evaluator for the phone, the station and the web
  (`CompassState` in Swift, `compassState` in TypeScript, `contract/test-vectors/compass-states.json`).
- **Tabloid 11 x 17** for the plan sheet.
- **The colour Floorplan stays as it is.** `FloorplanWriter` writes the same bytes as before
  for the same input (no north given); its look is unchanged.

### Compass rules settled after wave 2

- **A scan read with the compass always records the reading or the reason.** For every floor it
  scans with the compass, the app writes either the four reading fields (`heading`,
  `headingAccuracy`, `headingSource`, `headingRecordedAt`) or `headingIssue` (`rejected`,
  `not_calibrated` or `unavailable`); readings that never paired with a scan frame are
  `rejected`, and `unavailable` means the phone has no usable compass. A capture with neither was
  not scanned with the compass: every capture of a 1.0.0 capture record, a floor carried over
  from a revision sealed before the compass, or a build without the compass service. The station
  does not grade such a capture (Q-B below).
- **Fixture `two-floor-house`:** Floor 1 verified (212.4°, ±8°, true), Floor 2 scanned with the
  compass and not calibrated (`headingIssue: "not_calibrated"`), so the visit shows "Floor 1
  verified · Floor 2 not read" and the station verdict is Limited ("Floor 2: Plan orientation is
  not verified; north is not shown."). `two-room-apartment` is approximate (magnetic, ±12°).

### Defaults applied where the owner has not answered (critique Q-A to Q-G)

| # | Question | As built |
|---|---|---|
| Q-A | Field controls policy | `ChecklistPolicy.standard` ships (scan values are enough; tape or laser controls are optional); the manual policy of the drawings is built behind one constant (`ChecklistPolicy.shipping`). Overview floor rows say "controls from the scan" or "controls optional". |
| Q-B | Does a missing compass reading make a package Limited? | Only for a capture the app scanned with the compass (capture record 1.1.0 with a reading or a `headingIssue`): not verified is a limitation, "Plan orientation is not verified; north is not shown." A capture without compass fields (1.0.0 records, carried-over pre-compass floors) is not graded: one info finding "No compass reading recorded; orientation not verified", and `orientation.compass` is `not_applicable` when no capture is graded, so older packages keep their verdict (`COMPASS_LIMITATION_FOR_LEGACY_RECORDS = false`). 13 rules, evaluator 1.1.0. |
| Q-C | HUB data (project manager, deal and Files URLs) | Optional fields and station configuration (`HUB_WEB_DEAL_URL_TEMPLATE` gives `links.hub`); "PM {name}", "Open in the HUB" and the Files link are hidden until the HUB provides them. |
| Q-D | Photos in the spatial report | Photo pages as drawn (1u): each photo reduced to 356 x 444 px JPEG with EXIF and GPS stripped; the report stays at or under 45 MiB (photo pages are left out with a note if not). |
| Q-E | Package record pages | Added at the end of the report: every file with role, size, SHA-256 and where it is (HUB folder or station link). |
| Q-F | A floor too big for the sheet | The scale steps down 1:50 → 1:100 → 1:200 (→ 1:500 for an exterior capture), with a quarter turn tried at each rung; never fitted to the page. Past the last rung the plan is cut at the frame with a footnote. |
| Q-G | Time zone of printed dates | America/New_York on the plan sheet (`ChapterBrand.printTimeZone`), the spatial report (`REPORT_TIME_ZONE`) and the web. A floor captured at 21:28 in New York on Oct 20 prints Oct 20 on both documents, although its UTC date is Oct 21. |

### Plan sheet and spatial report agree

The two documents print the same thing for the same capture: room names (the operator's renames
included), room areas and the floor area as the sum of the rooms' unrounded areas rounded once
("796.2 sq ft · 74.0 m²"), number formats (`sq ft`, `m²`, feet and inches with ASCII `'` and
`"`, to 0.1 in), the room fill class (habitable, wet, other, outdoor; one rule,
`RoomFillClass` on the phone and `fillClass` on the station, critique R-35), the compass state
and the capture date. Each document squares its own drawing, so the two drawings may differ by
a quarter turn or a fraction of a degree; each north arrow is turned with its own drawing
(compass §2.5) and is correct for it. PlanExport's `ReportParityGoldenTests` write
`fixtures/report-parity`; the station's `plan-sheet-parity.test.ts` and `metrics-parity.test.ts`
compare against them.

### Tokens of the printed outputs (1ab)

Ink `#1F2429`, muted `#6B6557`, line `#D9CCBC`, nude `#E8DDD0` (habitable rooms), wet `#EFE6DA`,
ground `#F5EFE6` (other rooms), surface `#FAF5EE`; outdoor rooms are not filled (dashed edge).
The north symbol uses the host's ink (`#1F2429` on the sheet and the report, `#231F20` on the
colour Floorplan). Verdicts keep a word and a shape (● Ready, ▲ Limited, ■ Blocked), and the
black-and-white proof (1ac) keeps fills, dash patterns and verdicts distinguishable in grey.
