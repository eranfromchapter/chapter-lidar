# Report parity goldens

What the phone's PlanExport computes for every good generated fixture, so the station's
spatial report (its TypeScript port in `station/hub`) prints the same numbers and words as the
plan sheet (spatial-report spec 11.2, critique R-35). Written and checked by
`ios/Packages/PlanExport/Tests/PlanExportTests/ReportParityGoldenTests.swift`.

| File | Content |
| --- | --- |
| `{fixture}-{areaKey}.json` | One per capture of `fixtures/generated/index.json` (fixtures and samples; the legacy package is left out). Per room: id, label, model `type`, `fillClass`, floor area, perimeter, bounding box (along, across, angle), inscribed rectangle, ceiling (height, approximate, reasons), volume, wall areas, openings, objects, and the formatted strings (`187.4 sq ft`, `17.4 m²`, `20' 5.6" × 10' 9.9"`, the plan sheet's dimension values). Totals with the sheet's "Floor area, sum of rooms". North: the compass state, the floor's dominant angle, and the symbol unturned and on the report's drawing (rho = minus the dominant angle). |
| `rules.json` | The room fill rule's own cases (renamed "Shower", "Pantry" with a stove, exterior captures, ...), lengths (feet-inches to 0.1 in, and the sheet's inches-alone dimensions) and areas (sq ft and m² with thousands separators). |

The TypeScript side compares numbers within 1e-9 relative and strings exactly. After a
deliberate change to `RoomMetrics`, `PlanTotals`, `UnitFormatter`, `RoomFillClass` or the north
symbol, regenerate in the same change:

```
UPDATE_PARITY_GOLDENS=1 swift test --package-path ios/Packages/PlanExport --filter ReportParityGoldenTests
```
