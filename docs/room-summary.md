# Room summary

Every package the station publishes now carries a **room summary**: what the scans measured, room by
room, in the quantities an estimate is priced from. It sits next to the spatial report so tools that
cannot read a PDF (AI Estimates, the PM and design briefs) can use real numbers.

- **Where:** the package's HUB folder, `Capture/<visitId>/r<revision>/room-summary-<verdictId>.json`,
  beside `spatial-report-<verdictId>.pdf`. Content type `application/json`; publication role
  `room_summary`.
- **Made by:** `station/hub/src/summary/room-summary.ts`, from the same measurements as the plan sheet
  and the spatial report (`planMetrics`), so the three always agree.
- **Never blocks a publication:** if the summary cannot be built, the publisher logs a warning and
  publishes the spatial report without it.
- **Format id:** `"schema": "chapter.room-summary"`, `"version": "1.0.0"`. Additions bump the minor
  version; nothing is removed or renamed within 1.x.

## Units

Feet and square feet, rounded to 0.1 **after** summing (totals are not sums of rounded rooms).

## Fields

Top level: `schema`, `version`, `packageId`, `dealId`, `verdictId`, `sealedAt`, `units`, `totals`,
`floors[]`, `notes[]`.

`totals` (whole package) and `floors[].totals` (one floor):

| Field | Meaning |
|---|---|
| `rooms` | Rooms measured |
| `floorAreaSqFt` | Floor area (flooring quantity) |
| `paintableWallAreaSqFt` | Walls less doors, windows and passages (painting quantity) |
| `ceilingAreaSqFt` | Ceilings, assuming flat ceilings (equals floor area) |
| `baseboardFt` | Walled length less door and passage widths |
| `doors`, `windows` | Counts |
| `fixtures` | Fixture category → count (see below) |
| `byRoomType` | Room type → `{ rooms, floorAreaSqFt }` |

`floors[]`: `captureId`, `areaKey`, `name` (the capture's label), `status` (`ok`, or `absent` /
`unreadable` when the floor's scan could not be measured — then `rooms` is empty), `totals`, `rooms[]`.

`floors[].rooms[]`:

| Field | Meaning |
|---|---|
| `roomId`, `name` | The room as named on the plan sheet |
| `type`, `typeSource` | Room type, and where it came from (below) |
| `floorAreaSqFt`, `ceilingAreaSqFt` | Floor and ceiling area |
| `ceilingHeightFt`, `ceilingHeightApproximate` | Ceiling height; `true` when the scan saw too few walls or uneven wall tops |
| `wallAreaSqFt` / `paintableWallAreaSqFt` | Walls with / without openings |
| `perimeterFt`, `baseboardFt` | Outline length; baseboard as above |
| `doors`, `windows`, `passages` | Openings on the room's walls |
| `fixtures` | `bathtub`, `dishwasher`, `fireplace`, `oven`, `refrigerator`, `sink`, `stairs`, `storage` (cabinets/built-in storage), `stove`, `toilet` |
| `furniture` | Everything else RoomPlan saw (`bed`, `sofa`, `table`, …): not scope, but it helps type rooms |
| `uncertain` | Plain-language reasons to check a number before pricing from it; empty when there is nothing to check |

`typeSource`, most to least certain: `scan` (typed in the capture), `name` (the room's name says it:
"Bedroom 1", "Kitchen"), `fixtures` (inferred: a toilet or tub makes a bathroom, a stove or fridge a
kitchen; flagged in `uncertain`), `unknown` (type `other`; flagged).

## For AI Estimates and the briefs

- Price from `totals` and `rooms[]`, not from the PDF: paint from `paintableWallAreaSqFt` and
  `ceilingAreaSqFt`, flooring from `floorAreaSqFt` by room type, trim from `baseboardFt`, plumbing and
  appliance scope from `fixtures`.
- Treat anything in `uncertain` as "flag for review", the same way AI Estimates flags an uncertain line.
- Lining the quantities up with the **Master Pricing Sheet** line items is the consumer's job; the
  summary has measurements only, never prices.
- For a brief's "Spatial Observations" section, `spatialObservations(summary)`
  (`station/hub/src/summary/spatial-observations.ts`) writes the section as plain text, ready to paste
  in or hand to a model.

## Try it without a station

```sh
npm run room-summary:demo --workspace station/hub -- --package <package folder> --out <folder>
```

Without `--package` it uses the `sample-424` fixture (12 rooms); it writes `room-summary.json` and
`spatial-observations.txt`.

## Not in 1.0

Prices or Master Pricing Sheet line items; showing the summary in the web review; a schema in
`contract/` (the summary is a station output only, so it lives with the station for now).
