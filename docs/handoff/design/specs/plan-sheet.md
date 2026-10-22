# Build spec: plan sheet v2 (area key `plan-sheet`)

Chapter Capture v2, October 21, 2026. Covers artboards **1a** (plan sheet v1, current), **1b** (plan
sheet v2, Tabloid 1224 x 792 pt, 424 West End Ave at 1:50), **1c/1d** (north arrow v1/v2), **1ab**
(system v2, the parts that apply to the plan sheet) and **1ac** (black-and-white proof, plan sheet
part). Written so an engineer can build without opening the bundle.

Repo: `chapter-lidar`, branch `feat/floorplan-report`. Package: `ios/Packages/PlanExport` (pure
Swift + Foundation, builds and tests on Linux).

---

## 0. Decisions in one table

| Question | Decision |
|---|---|
| What is the plan sheet? | A one-page **Tabloid landscape PDF, 1224 x 792 pt (11 x 17 in)**, one per capture (floor or area), written **on the phone** by PlanExport when the package is built. No verdict. |
| Which writer? | New `PlanSheetWriter` (new file). It **replaces `PlanPDFWriter`** (deleted). |
| File role / name | Role stays **`plan_pdf`** (no enum change). File name changes **`plan.pdf` -> `plan-sheet.pdf`** (as drawn in web artboards 2i/2j: "Floor 1 / plan-sheet.pdf", role label "Plan sheet PDF"). |
| Drawing engine | The sheet's plan is drawn by the existing **`FloorPlanDrawing`** engine (squaring, wall layout, hall fill, label placement) with a new **`planSheet` rendition**: v2 monochrome palette, v2 line weights, doors without swing, 4 fixture symbols + boxes, caps labels, v2 dimension tiers. The colour **Floorplan** rendition (today's look) is untouched, byte for byte. |
| Colour Floorplan (`FloorplanWriter`) | **Stays as is**: the phone's Floorplan screen and share sheet (`floorplan.pdf/png`), `tools/plan-render`, scan browser. Not in the package, no file role. No code change except the shared engine gaining a rendition switch. |
| `plan.svg` (`plan_svg`) | **Becomes the plan sheet's drawing** (same scale, rendition, dimensions) as SVG in paper millimetres. Writer `SVGWriter` rewritten on `FloorPlanDrawing`. |
| `plan.png` (`plan_png`) | **Becomes the plan sheet's drawing without dimension strings**, 300 dpi RGB (it is the HUB web preview, artboard 2j). Needs an RGB rasteriser for drawing items (generalise `GrayCanvas`). |
| `plan.dxf`, `rooms.csv` | Unchanged. |
| `spatial-report.pdf` (`SpatialReportWriter`) | Retired from the phone (bundle decision). Owned by area `spatial-report`; this spec only gives the final `exportAll` list. |
| North arrow | Vector, 3 states (verified / approximate / not verified), thresholds **+-10 deg / +-30 deg** (confirmed by Eran, Oct 20, 2026). Drawn 40 pt in the title block. Until the compass reading ships, every sheet shows **"Orientation: not verified" / "No compass reading"**. |
| Brand | **Real Chapter logo** (`ChapterLogo`, the full logo with RENOVATION, vector paths, brand black #231F20) replaces the typed serif wordmark the bundle draws. **Inter** (embedded) replaces Helvetica everywhere; **Times** stays for the title and tagline; **Courier** stays for ids, dimensions and the scale label. |
| Units | Imperial first, always (ft-in to 0.1 in, sq ft one decimal); metric only after the floor area total ("807.5 sq ft · 75.0 m²"). See open question Q2. |
| Scale | Ladder **1:50 -> 1:100 -> 1:200** (+ **1:500** for `exterior` captures). Never "fit to page". Label "1:50 at 11 x 17 in". |

---

## 1. Inputs used

- Owner decisions (Oct 21, 2026, binding): real logo + Inter everywhere (Times stays, mono stays);
  plan sheet on the phone, no verdict; compass 3 states with the v2 thresholds; Tabloid 11 x 17.
- Bundle: `canvas/plan-sheet.dc.html` (1a), `canvas/plan-sheet-v2.dc.html` (1b),
  `canvas/north-arrow.dc.html` (1c), `canvas/north-arrow-v2.dc.html` (1d), `canvas/system-v2.dc.html`
  (1ab), `canvas/bw-proof-v2.dc.html` (1ac), shared `canvas/plan-parts.js` (north arrow and scale bar
  code) and `canvas/apartment-424.js` (the traced 424 drawing: palette, symbols, dimension strings),
  `00-plan-of-changes.dc.html`, handoff `02-decisions-and-open-questions.md`, `brand/brand.md`,
  `design/tokens.json`, `data/field-mapping.md`, `code-context/pdf-writer-limits.md`.
- Repo: `ios/Packages/PlanExport/**`, `contract/**`, `ios/App/AppCore/Sources/AppCore/VisitPackageBuilder.swift`,
  `docs/waves/design/DESIGN.md` (Oct 19 brand update), `docs/floorplan-report-plan.md`, `web/**`
  (preview route reads `plan_png`), `station/checks/**` (parses `plan_pdf` by role only).

Where the bundle says Helvetica, this spec says **Inter** (Regular for normal, SemiBold for "bold"/700;
only these two weights are embedded). Times-Roman stays Times-Roman; the tagline is **Times-Italic**.
Courier stays **Courier** (PDF base-14).

---

## 2. Outputs of PlanExport after this change

`PlanExporter.exportAll(model:record:)` writes, per capture, in this order:

| # | File name | Role | Writer | Change |
|---|---|---|---|---|
| 1 | `plan.dxf` | `plan_dxf` | `DXFWriter` | none |
| 2 | `rooms.csv` | `rooms_csv` | `CSVWriter` | none |
| 3 | `plan-sheet.pdf` | `plan_pdf` | **`PlanSheetWriter` (new)** | replaces `plan.pdf` from `PlanPDFWriter` |
| 4 | `plan.png` | `plan_png` | `PNGWriter` (rewritten) | v2 drawing, no dimensions, RGB |
| 5 | `plan.svg` | `plan_svg` | `SVGWriter` (rewritten) | v2 drawing with dimensions |

`spatial-report.pdf` / `spatial_report_pdf` is removed from this list by area `spatial-report`
(the station makes the spatial report). **Interim rule**: if `plan-sheet` lands first, keep
`SpatialReportWriter` as item 4 (between the sheet and the PNG) until `spatial-report` removes it;
the ExportAll test lists both states (see 13.1). This matches the phone package artboard 2f: per
floor "Plan DXF · rooms CSV · plan sheet PDF, PNG, SVG — 5".

`PlanExportInfo.generatorVersion` goes from `"1.0.0"` to **`"2.0.0"`** (the content of `plan_pdf`,
`plan_png` and `plan_svg` changed). `generator` stays `"chapter-capture-ios/PlanExport"`.

Output is a pure function of `(model, record)`: same input, same bytes (the PDF creation date is
the capture's `capturedAt`, never "now"). This keeps a re-sealed revision 2 showing the sheet as
"unchanged" when nothing changed.

---

## 3. Plan sheet v2: page

### 3.1 Coordinates

All values are PDF points. Positions are given **from the top-left corner** of the page as in the
artboard (x right, y down). In the PDF content stream (origin bottom-left, y up) use
`y_pdf = 792 - y`. Text positions are line boxes (top + line height); the baseline inside a line
box is:

```
baseline_y = lineTop + lineHeight/2 + capHeight*size/2
capHeight: Inter 0.727 · Times-Roman 0.662 · Times-Italic 0.653 · Courier 0.562
```

(This centres capitals in the line box; for Inter it equals the browser's placement of the artboard.)

### 3.2 Fixed page furniture

| Element | Geometry | Style |
|---|---|---|
| Page | 1224 x 792 | MediaBox `[0 0 1224 792]`. Whole page filled **#FAF5EE** (surface). |
| Border | outer edge (36, 36) to (1188, 756) | stroke **0.75 pt #6B6557**, drawn inside: path rect (36.375, 36.375, 1151.25, 719.25), miter join, no fill |
| Vertical rule | x 912 to 912.75, y 36 to 756 | filled rect **#6B6557** (0.75 wide) |
| Drawing area | x 36–912, y 36–756 (876 x 720) | holds the plan, its dimensions and the footnote |
| Plan frame | x 84–864, y 84–708 (**780 x 624**) | the plan (walls + rooms) must fit here ("plan 780 x 624 after 48 pt for dimensions") |
| Annotation frame | x 42–906, y 42–(footnote top − 6) | the whole drawing incl. dimensions and labels must fit here |
| Footnote | left x 60, width 560, bottom edge y 736 | Inter 7.5 / 9 pt, **#6B6557**, left aligned, wraps at 560; lines stack upward from 736 (top = 736 − 9·lines) |
| Title block | x 936–1164 (228 wide), y 60–732 (672 tall) | see 3.5 |

### 3.3 Scale ladder, placement, overflow

Scale = first rung of the ladder at which the drawing fits:

- Ladder for `room` and `floor` captures: **50, 100, 200**. For `exterior` captures: **50, 100, 200, 500**.
- At 1:50 one foot is **17.28 pt** (1 m = 56.693 pt). In general `pt per metre = 72 / 0.0254 / n`.
- For each rung, and each quarter turn in **[0, 3]** (as `FloorplanWriter` does: none, or one
  clockwise), build `FloorPlanDrawing(rendition: .planSheet, scaleDenominator: n, quarterTurns: t)`.
  It fits when **(a)** its plan extent (`planExtentMM`, walls + rooms) is at most 780 x 624 pt at
  that scale, and **(b)** its full bounds (`bounds`, incl. dimension strings and labels) are at most
  the annotation frame's size (864 x (footnoteTop − 48) pt). Pick the first rung where any turn
  fits; on a tie between turns pick turn 0.
- Placement: centre the **plan extent** in the plan frame (centre (474, 396)); then, if the full
  bounds stick out of the annotation frame, translate the drawing the least distance that brings
  them inside (it fits by (b)).
- The squaring rotation and the quarter turn are allowed: the plan is **never turned to put north
  up** (1d: "The plan is never rotated: it stays in the scan frame and the arrow turns by −heading").
  The arrow accounts for the drawing's turn (section 4.4).
- **Too big for every rung** (rare; a floor larger than 180 x 144 ft): draw at the last rung,
  centred, clipped to the drawing area (clip path rect x 36.75–911.25, y 36.75–755.25), and add the
  footnote sentence **"The plan is larger than this sheet at 1:200 and is cut at the frame. plan.dxf holds the whole floor."**
  (1:500 for exterior). See open question Q4. Never throw for this.
- No plan geometry at all (no walls, rooms or objects): throw `PlanExportError.noPlanGeometry` as
  today (package build shows "The plans of Floor 1 could not be written: The model has no walls,
  rooms or objects to draw.").

### 3.4 The drawing (rendition `.planSheet`)

All weights below are **paper points**; the engine stores plan millimetres, so convert with
`planMM = pt * 25.4 / 72 * n` at 1:n. Draw order (bottom to top): room fills (incl. hall fill) ->
objects and symbols -> walls -> window clears and window lines -> thresholds -> room labels ->
dimension strings. This is the order of `renderApartment` in the artboard.

#### Palette (design tokens, `tokens.json`)

| Token | Hex | Used for | Grey in B&W (Rec. 709 luma) |
|---|---|---|---|
| ink | #1F2429 | walls, text, window lines, dimension lines, arrow | 13.8 % |
| muted | #6B6557 | object lines, thresholds, captions, border, dashes | 39.7 % |
| line | #D9CCBC | table rules, card border, swatch outline | 80.6 % |
| nude | #E8DDD0 | habitable room fill | 87.2 % |
| wet | #EFE6DA | wet room fill | 90.6 % |
| ground | #F5EFE6 | other room fill | 94.0 % |
| surface | #FAF5EE | page, object fill, window clear | 96.3 % |

The logo keeps its own brand black **#231F20** (`ChapterLogo.draw`). See open question Q3 about
#1F2429 vs #231F20 for the drawing ink.

#### Elements

| Element | Rule (system 1ab §5–7, artboard 1b) |
|---|---|
| **Wall** | Filled polygons, **ink #1F2429**, nonzero, no stroke. Thickness: RoomPlan measures none, so the assumed thicknesses of the colour Floorplan are used: **4.5 in interior (0.1143 m), 6 in exterior (`MeasurementSettings.defaultExteriorWallThicknessM`)**. Drawn at least **2 pt** thick: `drawnThickness = max(assumed, 2pt in plan metres)`, widened symmetrically about the centre line. The 2 pt minimum never changes a dimension value. |
| **Window** | Over the window's wall piece: fill the piece with the **page colour** (#FAF5EE on the sheet, #FFFFFF in plan.png/svg), then **two lines 0.6 pt ink, 2 pt apart** (centre line ±1 pt), from gap end a to gap end b. |
| **Door** | Gap in the wall (as the engine's `walls.gaps` already leaves) + **threshold line 0.4 pt muted, solid**, along the wall centre line from a to b. **No leaf, no swing arc, no jamb lines** (swing not recorded). |
| **Open passage** | Same as a door, threshold **dashed 2 / 2 pt** (dash phase 0). |
| **Object box** | Oriented footprint rectangle (`PlacedSymbol.footprint`), **fill #FAF5EE, stroke 0.6 pt muted**, miter join, butt cap, square corners. |
| **Low-confidence object** (`confidence == .low`) | Same box, **dash 1.8 / 1.2 pt**. (Symbols of a low-confidence fixture: outline dashed, inner details solid.) |
| **Overhead / wall-hung object** (underside ≥ 1.0 m above the floor, as the engine's `overhead`) | Box outline only, **no fill**, 0.6 pt muted solid, drawn after all other objects. (Not in the bundle; see Q6.) |
| **Fixture symbols** (by category only) | **toilet**: tank rect = full width, back 0.30 of depth; bowl ellipse centred 0.64 of depth from the back, rx 0.46·w, ry 0.34·d; both filled #FAF5EE, stroked 0.6 muted (no outer box). **sink**: box + ellipse at centre rx 0.34·w, ry 0.32·d. **bathtub**: box + inner rounded rect inset i = 0.18·min(w, d), corner radius i. **stove**: box + 4 circles r = 0.17·min(w, d) at (0.27, 0.30), (0.73, 0.30), (0.27, 0.70), (0.73, 0.70) of (w, d) from the back-left corner. Inner details: stroke 0.6 pt muted, no fill. "Back" = the side nearest a wall, as `FloorPlanSymbols` picks it today. **Every other category is a plain box** (bed, chair, sofa, table, storage, fireplace, stairs, dishwasher, oven, refrigerator, television, washer_dryer, other). |
| **Room fill** | Room polygon filled by class (below), no stroke. Hall-fill regions take the class colour of the room they open to, else ground. |
| **Outdoor room** (balcony, terrace) | **No fill**, edge **0.6 pt muted, dash 4 / 3**. |
| **Rooms not scanned** | Not drawn (no geometry). Listed in the title block. |
| **Room label** | Room name in **capitals**, **Inter SemiBold 7.5 pt, letter spacing 0.9 pt (0.12 em), ink**; area line below, **Inter 7.5 pt, muted**, baseline 11.25 pt below the name baseline; both centred. Placement, wrapping (2 lines max) and cutting: the engine's `placeRoomLabel` / `fittedRoomLabel`, but **never smaller than 7.5 pt** (both sizes are already 7.5, so names wrap, then are cut with "..."). Area text: room floor area, `"187.1 sq ft"` (one decimal, thousands separator, ASCII). No label patch/background. |
| **Dimensions** | Section 3.4.2. |
| **Not on the drawing** | Compass/north arrow, scale bar (both in the title block), inside-room dimension strings, item markers, door swings, casing. |

#### 3.4.1 Room class (fill)

Order of tests for each room:

1. **Outdoor** if the label contains (case-insensitive) `balcony`, `terrace`, `patio`, `deck` or `porch`.
2. **Wet** (#EFE6DA) if `type` ∈ {bathroom, kitchen, laundry} or the label contains `bath`, `kitchen`, `laundry`, `wc`, `toilet`, `shower`.
3. **Habitable** (#E8DDD0) if `type` ∈ {bedroom, livingRoom, diningRoom, office} or the label contains `bed`, `living`, `dining`, `office`, `study`.
4. If `type` is nil or `other` and the label matched nothing: **wet** if the room holds a toilet, bathtub, sink, stove or washer_dryer; else **habitable** if it holds a bed.
5. Otherwise **other** (#F5EFE6): closets, halls, utility, unlabeled "Room N".

`type` comes from the capture model 1.1.0 (`Room.type`, operator renames set it via
`RoomTyping.renamedByOperator`); for 1.0.0 models use `FloorPlanStyle.type(fromLabel:)`. An object
is "in" a room when its `PlanGeometry` `roomId` is that room.

#### 3.4.2 Dimension strings (sheet only)

"Plan sheet: overall width and depth outside, room dimensions inside" (1ab §7): two tiers, both
outside the building.

- Frame: the drawing frame (after squaring and quarter turn). `B` = axis-aligned bounding box of all
  wall pieces and room polygons, built with the **assumed** thicknesses (not the 2 pt minimum).
- **Tier 1, room dimensions**, on every side (top, bottom, left, right), line **12 pt** outside B's
  side. A room belongs to a side when its own bounding-box edge on that side is within
  `exteriorThickness + 0.30 m` of B's edge. Its span is the room polygon's extent along the side
  (x for top/bottom, y for left/right). Sort spans; when two overlap by more than 0.05 m keep the
  one closer to the side (tie: the longer). Drop spans shorter than 0.6 m and spans shorter than
  `textWidth + 4 pt` at the sheet scale.
  **Text value** = the room's **`RoomMetrics.boundingBox`** side whose direction is closest to that
  sheet axis (`alongM` if the frame angle, turned into the drawing frame, is within 45° of the axis,
  else `acrossM`), so the sheet prints the same number as the spatial report's room schedule
  (bounding box). Ticks sit at the drawn span's ends.
- **Tier 2, overall**: width on the **top** side and depth on the **left** side only (as drawn),
  line **33 pt** outside B (tier step 21 pt), span = B's full width / height. Value = that span
  (outside faces of the exterior walls at the assumed thickness).
- Line **0.4 pt ink**; end ticks **5 pt long, 0.6 pt ink**, perpendicular, centred on the line;
  no witness lines (as drawn in 1b).
- Text **Courier 8.25 pt ink**, centred on the span: top side baseline 2.5 pt above the line;
  bottom side baseline 10.75 pt below the line; left side rotated **+90°** (counter-clockwise,
  reads bottom to top) with baseline 2.5 pt left of the line; right side rotated +90° with baseline
  10.75 pt right of the line. Text always sits on the side away from the building.
- Format: `UnitFormatter(system: .imperial).dimension(m)`: feet-inches to 0.1 in, ASCII `'` and `"`
  (`10' 10.3"`), inches alone under a foot (`5.1"`).

Expected for fixture `box-room` (4.000 x 3.000 m): tier 1 top `13' 1.5"`, tier 1 left `9' 10.1"`
(also bottom/right), tier 2 top `14' 1.5"`, tier 2 left `10' 10.1"` (with 6 in exterior walls fully
outside the room outline, as `WallLayout` places them; confirm against `WallLayout`).

### 3.5 Footnote (bottom-left of the drawing area)

Inter 7.5/9 pt, #6B6557, width 560, from x 60, bottom 736.

- Artboard text (mock-up only): "Walls, openings and object boxes come from the LiDAR scan. Doors are drawn without swing (not recorded). Room dimensions are bounding boxes; overall dimensions in [brackets] are placeholders in this mock-up."
- **Production text** (the bracket sentence is mock-only; the thickness sentence is required because RoomPlan measures no thickness; see Q5):
  **"Walls, openings and object boxes come from the LiDAR scan. Doors are drawn without swing (not recorded). Room dimensions are bounding boxes. Wall thickness is not measured: walls are drawn 4.5 in thick inside and 6 in outside, and overall dimensions include it."**
  (2 lines at 560 pt: 541.2 / 397.1 pt.) Append the too-big sentence of 3.3 when it applies.

### 3.6 Title block (x 936–1164, y 60–732)

A vertical stack of blocks A–H with gap `g` (14 pt as drawn; see 3.7). H is pinned to the bottom
(y 732). All widths below are 228 pt unless said.

#### A. Header row (height 36)

| Item | Spec |
|---|---|
| Logo | **`ChapterLogo`** (real logo: "chapter" over "RENOVATION", vector, brand black #231F20) at x 936, top yA, **height 36 pt** (width 36 x 1756/635 = **99.56 pt**). Replaces the typed "chapter" Times 33 + "RENOVATION" 8.25 tracked 4.5 of the artboard (owner decision 1). Never retype it. |
| Sheet id | **"SHEET {n} · {LABEL}"**, e.g. "SHEET 1 · FLOOR 1". Inter 8.25 pt, line 10, **letter spacing 1.5 pt**, capitals, **#6B6557**, right aligned at x 1164 (last glyph's right edge), line top yA + 6. `n` = 1-based index of the capture in `record.captures`; `LABEL` = `capture.label` upper-cased (`uppercased(with: Locale(identifier: "en_US_POSIX"))`). Available width 228 − 99.56 − 8 = 120.4 pt ("SHEET 1 · FLOOR 1" = 97.1 pt). Longer: wrap at spaces to a second line (top yA + 16), then cut the second line with "...". |

#### B. Title group (gap 4 between lines)

| Line | Text | Style | Data |
|---|---|---|---|
| Title | **"Existing-condition plan"** | Times-Roman **25.5 / 28 pt**, ink, regular | fixed. At 25.5 pt it is 240.1 pt wide, wider than 228, so it wraps to **"Existing-condition" / "plan"** (2 lines, 56 pt), as the artboard renders it. |
| Line 1 | **"{label} · {projectName}"**, e.g. "Floor 1 · 424 West End Ave, Apt 4K" | Inter **11.25 / 14 pt**, ink | `capture.label`, `record.hub.projectName`; when `projectName` is absent or blank: "{label} · {address.formatted}" |
| Line 2 | **"{address.formatted} · address confirmed on site"**, e.g. "274 W 81st St, New York, NY · address confirmed on site" | Inter **9 / 11 pt**, #6B6557 | `record.address.formatted`, `confirmedOnSite`. Not confirmed: "· address not confirmed on site". When line 1 already shows the address: line 2 is only "Address confirmed on site" / "Address not confirmed on site". |

Wrapping: each line wraps at spaces to at most 2 lines, then is cut with "...". Line 2 breaks
**before " · "** when the whole does not fit (424 sample: 241.9 pt > 228, so "274 W 81st St, New York, NY" / "address confirmed on site").
Draw `address.formatted` as **its own text run** (own `Tj`), so text extraction finds it exactly.

#### C. Data rows (7 rows, each 20.75 pt: padding 4.5, line 11, padding 4.5, rule 0.75)

Row: label left (Inter 9/11, #6B6557), value right-aligned at x 1164 (Inter 9/11 ink unless
mono), min gap 8 pt; rule under each row: filled rect (936, rowTop + 20, 228, 0.75) **#D9CCBC**.

| Label (verbatim) | Value | Source | Missing / overflow |
|---|---|---|---|
| **HUB deal** | e.g. "fixture-deal-0001" — **Courier 9** | `record.hub.dealId` | Courier steps down to **7.5** if it does not fit `228 − labelWidth − 8`, then cut with "..." |
| **Capture id** | "22bfb513-226d-4eca-bde1-0b6cb0c84aad" — **Courier 7.5** (36 chars = 162 pt; at 9 pt it would be 194.4 pt and not fit) | `capture.captureId` | never cut (always fits at 7.5) |
| **Captured** | **"Jan 25, 2025 · {operator}"** | `capture.capturedAt` (UTC date, see Q7), `record.operator.name` | operator cut with "..." to fit |
| **Device** | **"{marketingName} · LiDAR · app {version}"**, e.g. "iPhone 16 Pro · LiDAR · app 1.0.0" | `record.device.marketingName ?? device.model`, `device.hasLidar` (omit "· LiDAR" when false), `record.app.version` | cut with "..." |
| **Mode** | **"One room" / "Whole floor" / "Exterior"** | `capture.mode` room / floor / exterior | — |
| **Floor area, sum of rooms** | **"807.5 sq ft · 75.0 m²"** | `PlanMetrics.totals.livableAreaM2` (sum of unrounded room areas, rounded once) | no rooms: **"not captured"** |
| **Rooms** | **"12 scanned · 2 not scanned"** | scanned = number of rooms in the model with ≥ 3 points and area > 0; not scanned = `omittedRooms.count + inaccessibleRooms.count` | no not-scanned: "12 scanned"; no rooms: **"none recognized"** (+ " · 2 not scanned" when any) |

Not shown (v1 had them; v2 drops them): "Package revision · sealed date" (the sheet is made before
sealing), "Gross floor area" (the system has no gross area).

#### D. Note card

Rounded rect (936, yD, 228, h), **radius 6**, stroke **0.75 #D9CCBC** (inset 0.375), no fill.
Padding 8 (top/bottom) x 10 (left/right); text x = 946.75, text width 206.5; gap 3 between title
and body.

- Title: **"Made on site, before the station checks"** — Inter SemiBold 9 / 11, ink (172.0 pt).
- Body: **"The station verdict and the capture checks are in the Chapter spatial report for this capture. This sheet has no verdict."** — Inter 8.25 / 10.5, #6B6557; wraps to 3 lines ("The station verdict and the capture checks are in" / "the Chapter spatial report for this capture. This" / "sheet has no verdict.").
- Height for 3 body lines: 0.75 + 8 + 11 + 3 + 31.5 + 8 + 0.75 = **63 pt**.

#### E. Not scanned (only when the capture has omitted or inaccessible rooms)

Gap 3 between lines.

- Kicker **"NOT SCANNED"** — Inter 7.5 / 9, letter spacing 1.5, capitals, #6B6557.
- One row per room — Inter 8.25 / 10.5, ink: **"{name} · {reason}"**, e.g. "Primary closet · locked",
  "Storage room · could not enter". `name` = `RoomNote.name`; `reason` = `RoomNote.reason`, or when
  absent **"skipped"** (omitted) / **"could not enter"** (inaccessible). Order: `omittedRooms` then
  `inaccessibleRooms`, each in record order. Rows cut with "..." at 228. The artboard's muted
  "[PLACEHOLDER]" suffix is mock-only, never drawn.
- Closing line **"Rooms not scanned have no geometry and are not drawn."** — Inter 7.5 / 9, #6B6557.
- Overflow line (only when rows are dropped, 3.7): **"+{k} more, listed in the spatial report"** — Inter 8.25 / 10.5, #6B6557, before the closing line.

#### F. Legend

- Kicker **"LEGEND"** — Inter 7.5 / 9, tracking 1.5, capitals, #6B6557; gap 5 to the grid.
- Grid: 4 rows x 2 columns, row height 10, row gap 5. **Column 1 at x 936, column 2 at x 1044**
  (the artboard's equal `1fr 1fr` columns are 109 pt, too narrow for "Habitable · wet · other" in
  Inter, 86.4 pt + 31). Each item: swatch at x, vertically centred in the row; label Inter 8.25 / 10
  ink at x + 31 (swatch 24 + gap 7).
- Swatches (24 x 8 pt unless said; coordinates inside the swatch box, y down):

| Pos | Label (verbatim) | Swatch |
|---|---|---|
| r1 c1 | **Wall, scanned** | rect (0, 1.5, 24, 5) fill ink |
| r1 c2 | **Window** | lines y 3 and y 5, x 0–24, 0.6 ink |
| r2 c1 | **Door, no swing** | rects (0, 1.5, 5, 5) and (19, 1.5, 5, 5) fill ink; line y 4, x 5–19, 0.5 muted |
| r2 c2 | **Open passage** | same, line dashed 2 / 2 |
| r3 c1 | **Object, box** | rect (4, 0.5, 16, 7) fill #FAF5EE, stroke 0.6 muted |
| r3 c2 | **Low confidence** | same, dash 1.8 / 1.2 |
| r4 c1 | **Fixture symbol** | 24 x 10: rect (1, 0.5, 9, 9) fill #FAF5EE stroke 0.6 muted + 4 circles r 1.3 at (3.6, 3.2) (7.4, 3.2) (3.6, 6.8) (7.4, 6.8) stroke 0.5 muted no fill; rect (14, 0.5, 8, 2.5) fill #FAF5EE stroke 0.6 muted; ellipse c (18, 6.4) rx 3.6 ry 3 fill #FAF5EE stroke 0.6 muted |
| r4 c2 | **Habitable · wet · other** | rects (0,0,8,8) #E8DDD0, (8,0,8,8) #EFE6DA, (16,0,8,8) #F5EFE6 with stroke 0.4 #D9CCBC |

Height: 9 + 5 + 4·10 + 3·5 = **69 pt**.

#### G. Scale and north (one row, height 60, items bottom-aligned)

Scale block, left at x 936 (height 42, so its top is yG + 18):

- Kicker **"SCALE"** — Inter 7.5 / 9, tracking 1.5, capitals, #6B6557; gap 6.
- Bar: **86.4 pt long** (see Q1), 6 pt box: rect (x+0.5, y+0.5, 43.2, 5) fill ink; rect
  (x+0.5+43.2, y+0.5, 43.2, 5) fill #FAF5EE; outline rect (x+0.5, y+0.5, 86.4, 5) stroke 0.6 ink.
  Length in feet per scale: **1:50 -> 5 ft, 1:100 -> 10 ft, 1:200 -> 20 ft, 1:500 -> 50 ft** (always
  86.4 pt = 30.48 mm); first half solid.
- Tick labels, gap 3 under the bar, Courier 7.5 / 9 ink: **"0"** left-aligned at the bar start,
  half value centred at the middle (**"2.5"**, "5", "10", "25"), **"{N} ft"** right-aligned at the bar
  end ("5 ft").
- Ratio line under it, Courier 7.5 / 9 ink: **"1:50 at 11 x 17 in"** (ASCII x; "1:100 at 11 x 17 in", ...).
  "A Letter print is a reduction: the bar stays true, the ratio does not."

North block, right-aligned at x 1164, bottom-aligned: section 4 at **40 pt**. Block width =
max(40, caption widths) (verified 75.4, approximate 86.6, not verified box 97.4 pt).

#### H. Footer (pinned: bottom at y 732)

- Rule: filled rect (936, top, 228, 0.75) **#D9CCBC**; padding-top 12.
- Statement (verbatim), Inter 8.25 / 10.5, #6B6557, 5 lines at 228 pt:
  **"Generated by Chapter Capture from an on-site LiDAR scan. Measurements are scan estimates and may differ from real conditions. This sheet is not a survey and does not certify any property model or measurement. Verify on site before planning or construction."**
- Gap 8, then a 13 pt row, items vertically centred: **"It's about time."** Times-Italic 11.25 pt
  ink at x 936; **"hellochapter.com"** Inter 8.25 #6B6557 right-aligned at x 1164.
- Height 0.75 + 12 + 52.5 + 8 + 13 = **86.25 pt** (top at 645.75).

### 3.7 Stacking and overflow (deterministic)

```
blocks = [A, B, C, D, E?, F, G]   // E only when there are not-scanned rooms
H pinned: H.top = 732 - h(H)
gaps = blocks.count               // between consecutive blocks and before H
g = min(14, (672 - sum(h(blocks)) - h(H)) / gaps)
if g >= 8: place blocks from y 60 with gap g; done
else:
  g = 8
  if E present: keep the first k rows of E (k >= 0) such that it fits, replace the rest with the
     overflow line "+{m} more, listed in the spatial report"; if even k = 0 does not fit, drop E's rows and keep kicker + overflow line + closing line
  if still over (pathological label/address lengths): cut B's lines to 1 line each with "..."
```

Worked example, 424 sample (2 not-scanned rooms, title on 2 lines, line 2 on 2 lines):
A 36 + B 100 + C 145.25 + D 63 + E 48 + F 69 + G 60 = 521.25; H 86.25; free = 672 − 607.5 = 64.5;
7 gaps -> **g = 9.21 pt**. (The artboard used 14 with Helvetica and a 45 pt wordmark; Inter is
wider, so the stack compresses. This is expected.)

### 3.8 Text and number rules (1ab §10, applied)

- Feet-inches **ASCII `'` and `"`**, never ′ ″. "approx." never ≈. `×` and `·` and `²` are WinAnsi and allowed (`·` U+00B7, `²` U+00B2, `±` U+00B1, `°` U+00B0).
- Areas: **"sq ft"** one decimal with thousands separators ("2,196.3 sq ft"); metric after, one decimal: "75.0 m²". Never "ft²" on the sheet (the colour Floorplan keeps its own "ft²").
- Dates in data rows: **"Jan 25, 2025"** (English 3-letter month, no period, no leading zero on the day), locale independent.
- Missing values: left out, or "not captured" / "none recognized". **No brackets ever** in production output.
- Characters outside WinAnsi print as "?" (existing `PDFPage.encode` behaviour).
- Capitals: `uppercased(with: Locale(identifier: "en_US_POSIX"))`.
- Cutting: ASCII "..." (as `PlanPDFWriter.fitted` today; keep that helper, move it to the sheet).

### 3.9 PDF document properties

| Key | Value |
|---|---|
| Title | "Existing-condition plan - {label} - {projectName ?? address}" |
| Author | operator name |
| Subject | "Plan sheet 1:{n} at 11 x 17 in, capture {captureId}" |
| Creator / Producer | "chapter-capture-ios/PlanExport 2.0.0" |
| CreationDate | `PDFDate.string(capture.capturedAt)` |
| Lang | en-US (existing) |
| Fonts | F1 Inter-Regular (embedded), F2 Inter-SemiBold (embedded), F3 Times-Roman, **F4 Courier**, **F5 Times-Italic** (base-14, WinAnsiEncoding). Declare only fonts used. No Helvetica. |

### 3.10 States of the plan sheet

| State | What changes |
|---|---|
| Normal (1b) | as above, compass verified |
| North approximate (1ac) | north block state 2 |
| North not verified (default until the compass ships; 1d/1k) | north block state 3, "No compass reading" |
| Skipped rooms | block E shown; absent when none |
| Unlabeled rooms | labels as in the model ("ROOM 4"); no "unlabeled" tag on the drawing (the tag is a table thing) |
| Address not confirmed | "· address not confirmed on site" |
| No project name | address on line 1, confirmation alone on line 2 |
| Floor bigger than 45 x 36 ft | next ladder rung, ratio "1:100 at 11 x 17 in", bar 10 ft |
| Bigger than the last rung | clipped + footnote sentence (Q4) |
| No rooms (walls only) | "not captured", "none recognized", no labels, no tier-1 dims |
| Metric capture (`units.display == metric`) | unchanged: imperial first (Q2) |
| Multi-floor visit | one sheet per capture, "SHEET n" by capture order, each with its own north state |
| Long names | wrap/cut rules of 3.6–3.7 |
| Black-and-white print (1ac) | must read without colour, section 6 |

---

## 4. North arrow v2 (1c -> 1d)

Shared by the plan sheet (40 pt, title block), the spatial report cover (32 pt; 26 pt on the
2-floor cover) and the report plan (32 pt). This section is the single definition; area
`spatial-report` implements the same in TypeScript.

### 4.1 States and thresholds (confirmed by Eran, Oct 20, 2026)

| State | When | Drawn |
|---|---|---|
| 1 · **verified** | `headingSource == true` and `0 <= headingAccuracy <= 10` | solid ring, filled arrow, "N" |
| 2 · **approximate** | (`true` and `10 < accuracy <= 30`) or (`magnetic` and `0 <= accuracy <= 30`) | dashed ring, outline arrow filled with the page colour, "N" |
| 3 · **not verified** | no reading; accuracy > 30; reading invalid; or the compass feature not built yet | text box, **no arrow, ever** |

v1 (1c) proposed ±15° / ±45°; **v2 replaces them with ±10° / ±30°**.

### 4.2 Vector drawing (32 pt box; scale everything, strokes included, by s = size / 32)

Box coordinates (u, v), y down, origin top-left of the box:

| Part | Geometry |
|---|---|
| Ring | circle centre (16, 18), r 10.5, stroke **0.75** ink, no fill. Approximate: dash **1.6 / 1.6**. |
| Arrow | polygon (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5), closed, stroke **0.75** ink, **round joins**; fill **ink** (verified) or **page colour #FAF5EE** (approximate). |
| N | "N", **Inter SemiBold 6** (was Helvetica-Bold), ink, centred, baseline at (16, 4.6); turns with the arrow. |
| Rotation | the whole box turns **counter-clockwise on the sheet by α** about the **box centre (16, 16)** (section 4.4). |
| Caption | Inter **7.5 / 9**, #6B6557, two centred lines, **2 pt below the box** (below the unrotated box). |

At 40 pt (sheet): s = 1.25, ring r 13.125, strokes 0.9375 pt, dash 2 / 2, "N" 7.5 pt.

Not verified (state 3): text **"Orientation: not verified"**, Inter 7.5 / 9 ink, in a box with
border **0.75 #6B6557**, **radius 3**, padding **3 x 6** (box 97.4 x 16.5 pt), centred; caption
below (gap 2), Inter 7.5 / 9 #6B6557, the reason in two or three words. Size does not scale the
not-verified box.

### 4.3 Captions (verbatim templates)

| State | Line 1 | Line 2 |
|---|---|---|
| verified | **"True north · compass"** | **"±{acc}° · {hdg}°"**, e.g. "±8° · 212°" |
| approximate | **"Approx. north · compass"** | **"±{acc}° · true"** or **"±{acc}° · magnetic"** |
| not verified | (box) "Orientation: not verified" | reason: **"No compass reading"** (no reading recorded, or feature not built), **"Low compass accuracy"** (accuracy > 30), **"Reading rejected"** (values present but invalid: non-finite, accuracy < 0, heading outside 0..<360) |

`acc` = `headingAccuracy` rounded half up to whole degrees; `hdg` = `heading` rounded to whole
degrees, 360 written as 0. Classification uses the unrounded values.

### 4.4 Rotation (exact)

`heading` h = degrees **clockwise from north** (true or magnetic, per `headingSource`) of the scan's
**−Z axis** at scan start. In PlanExport's plan frame (+x = scene x, +y = scene −Z, CCW angles),
true north is **h degrees counter-clockwise from plan +y** (this is `FloorplanWriter.Options.northDegrees`).
The sheet's drawing is turned by the engine (squaring + quarter turns): `θ = FloorPlanDrawing.rotationDegrees`
(the engine rotates geometry by −θ). On the sheet, the arrow therefore points

```
α = normalize(h − θ)   // degrees counter-clockwise from sheet up, as FloorplanWriter's compass does
```

In PDF (y up): a box point (u, v) maps to `C + R(α)·(s·(u − 16), −s·(v − 16))` with `C` the box
centre and `R(α)` the CCW rotation. Check: h = 90 (−Z points east), θ = 0 -> α = 90 -> the arrow
points to the **left** of the sheet.

### 4.5 Data (contract; recorded by area `phone-capture`)

Per capture in `capture-record.json` (1d: "Stored in capture-record.json next to capturedAt.
Missing field = state 3."; screen tokens 2k: "heading, headingAccuracy, headingSource,
headingRecordedAt per floor"). Exact shape in section 9. Rules (1d): never typed by hand or taken
from a map; read away from steel and appliances, phone flat; every floor carries its own state;
floors are not rotated to match each other.

### 4.6 Shared test vectors

New file `contract/examples/north-arrow-states.json` (array of `{ input: {heading?, headingAccuracy?, headingSource?}, state, captionLine1, captionLine2 }`),
read by Swift (`NorthArrowTests`) and by the station's TS tests. Minimum rows: missing ->
not_verified/"No compass reading"; true 0 -> verified; true 10 -> verified; true 10.01 ->
approximate; true 30 -> approximate; true 30.01 -> not_verified/"Low compass accuracy"; magnetic 5
-> approximate "±5° · magnetic"; magnetic 31 -> not_verified; accuracy −1 -> not_verified/"Reading
rejected"; heading 359.6 -> "0°"; accuracy 7.5 -> "±8°".

---

## 5. System v2 rules that apply to the sheet (1ab)

| 1ab section | Applies as |
|---|---|
| 1b Plan sheet grid | Section 3.2–3.3 (border 0.75 muted at 36, rule at 912, title block 936–1164 x 60–732, scale ladder, AC5). |
| 2 Type scale | Title Times 25.5/28; data rows 9/11; legends and card body 8.25/10 (10.5); kickers 7.5 caps tracking 1.5; captions, footnote 7.5/9 **minimum**; dimensions Courier **8.25** on the sheet; ids Courier 7.5. Helvetica -> Inter. |
| 3 Colour and B&W | Palette of 3.4; meaning never by hue (section 6). Verdict colours (ready/limited/blocked) are **not used** on the sheet. |
| 4 Verdict block | **Not on the sheet** (no verdict). |
| 5 Line weights | Wall fill (≥ 2 pt), window 0.6 x2 at 2 pt, door 0.4 muted, passage 0.4 dash 2/2, object 0.6, low confidence dash 1.8/1.2, ceiling change / outdoor edge 0.6 dash 4/3, dimension 0.4 + ticks 5 pt at 0.6. Bounding box / inscribed rectangle styles: room pages only, not the sheet. |
| 6 Markers and symbols | Item markers: **not on the sheet**. Fixture symbols: 3.4. |
| 7 Dimensions and fills | 3.4.1–3.4.2. |
| 8 Pagination | The sheet is always **one page per capture**. |
| 9 Tables | Data rows use the row style (9/11, 0.75 line rules). |
| 10 Text rules | 3.8. |

---

## 6. Black-and-white proof (1ac)

The sheet (state approximate north in the proof) printed on a monochrome printer must still read:

- Room classes are three distinct greys: nude 87.2 %, wet 90.6 %, ground 94.0 % (pairwise ≥ 3.0
  points apart); page 96.3 %. Room types also carry their label.
- Dashes differ by **pattern**: door solid vs passage 2/2; object solid vs low-confidence 1.8/1.2;
  outdoor edge 4/3; approximate ring 1.6/1.6 (x1.25 = 2/2 at 40 pt) vs verified solid; approximate
  arrow outline vs verified filled.
- North state 3 is words, not an arrow.
- No meaning depends on hue anywhere on the sheet (there are no verdict colours on it).

---

## 7. `plan.svg` and `plan.png` (previews) v2

Both draw the **same `FloorPlanDrawing` as the sheet** (same rendition, scale and quarter turn as
the chosen sheet layout), without the title block, north arrow, scale bar or footnote.

| | plan.svg (`plan_svg`) | plan.png (`plan_png`) |
|---|---|---|
| Content | drawing **with** dimension strings | drawing **without** dimension strings (`exteriorDimension` layer left out): no Courier outlines exist in pure Swift, and the HUB preview (2j) shows none |
| Size | `width`/`height` in mm = drawing bounds / n + 6 mm margin each side; viewBox in plan mm (as `FloorPlanDrawing.svg`) | 300 px per paper inch at 1:n, + 6 mm margin; pHYs 300 dpi (11811 px/m) |
| Background | #FFFFFF rect; window clears in #FFFFFF | #FFFFFF; window clears #FFFFFF |
| Text | `font-family` Inter (`ChapterBrand.sansFamily`), weight 600 for SemiBold, `letter-spacing` 0.9 pt-equivalent for caps names; dimensions `'Courier New', Courier, monospace` | Inter glyph outlines (`GlyphOutlines`), SemiBold names with letter spacing |
| Title / desc | `<title>Floor plan - {label} (1:{n})</title>`, `<desc>Plan millimetres, drawn for 1:{n}. Wall thickness is assumed (4.5 in inside, 6 in outside); measurements are scan estimates.</desc>` | — |
| Pixel format | — | 8-bit RGB (colour type 2), deterministic bytes |

The web preview label in 2j stays true: "From plan.png · fitted, not to scale. Use the plan sheet
PDF for the 1:50 drawing."

---

## 8. Code mapping (`ios/Packages/PlanExport`)

### 8.1 New

| File | Content |
|---|---|
| `Sources/PlanExport/PlanSheetWriter.swift` | `public enum PlanSheetWriter { static let fileName = "plan-sheet.pdf"; static func write(model:context:) throws -> PlanSheetOutput }`. `PlanSheetOutput { file: ExportedFile; scaleDenominator: Int; quarterTurns: Int; drawingRotationDegrees: Double; northState: NorthArrow.State; layout: PlanSheetLayout }` (layout exposed `internal` for tests). Picks the ladder rung (3.3), builds the page as `[DrawingItem]` in **points** (scale 1) and renders through `PDFDrawingRenderer`. |
| `Sources/PlanExport/PlanSheetLayout.swift` | Title block blocks A–H, measuring, wrapping, stacking (3.6–3.7), legend swatches, scale bar, footnote. Pure, testable: `PlanSheetLayout.make(context:metrics:scale:north:) -> PlanSheetLayout` with each block's frame and items. |
| `Sources/PlanExport/PlanSheetDimensions.swift` | Tier-1/tier-2 dimension placement of 3.4.2 (used by the engine when `rendition == .planSheet`). |
| `Sources/PlanExport/NorthArrow.swift` | `public enum NorthArrow { enum State { verified, approximate, notVerified(reason) }; static func classify(_ reading: CompassReading?) -> State; static func captions(...) -> [String]; static func items(state:size:alpha:center:page:) -> [DrawingItem] }` and constants `verifiedMaxDegrees = 10`, `approximateMaxDegrees = 30`. |
| `Sources/PlanExport/RasterCanvas.swift` | RGB generalisation of `GrayCanvas` (anti-aliased nonzero / even-odd fills, Bezier flattening (tolerance 0.25 px), dashed strokes, round/butt caps, clip, Inter text with letter spacing) + `render([DrawingItem])`. |
| `Tests/PlanExportTests/PlanSheetWriterTests.swift`, `PlanSheetLayoutTests.swift`, `PlanSheetScaleTests.swift`, `PlanSheetDimensionTests.swift`, `NorthArrowTests.swift`, `RasterCanvasTests.swift` | Section 13. |
| `contract/examples/north-arrow-states.json` | Section 4.6. |
| `fixtures/generated/sample-424/` (+ generator script in `fixtures/generator/src`) | Visual acceptance fixture: the 424 West End Ave apartment of artboard 1b as a capture model (12 rooms with the artboard's names, walls from room edges at thickness 0, doors/passages/windows of `apartment-424.js`, 14 objects with categories, omitted "Primary closet" reason "locked", inaccessible "Storage room" reason "could not enter"). Geometry from `canvas/apartment-424.js` (trace units, 19.4 per foot). |

### 8.2 Changed

| File | Change |
|---|---|
| `FloorPlanDrawing.swift` | `Options.rendition: Rendition = .floorplan` (`.floorplan`, `.planSheet`); `FloorPlanStyle(rendition:)` replaces the hard-coded `FloorPlanStyle()`; under `.planSheet`: palette and weights of 3.4, room fill by class (3.4.1), symbols via the sheet symbol set, openings without leaves/swings/jambs, no inside dimensions, `PlanSheetDimensions` instead of `placeExteriorDimensions`, no compass, no scale bar, wall minimum 2 pt. **`.floorplan` output must stay byte-identical.** |
| `FloorPlanSymbols.swift` | `symbol(for:..., rendition:)`: sheet set = box for all + 4 fixture symbols (3.4); keeps the back-side choice. |
| `FloorPlanAnnotations.swift` | Room label style parameters (caps, tracking, sizes, no patch) per rendition; minimum size 7.5 pt for the sheet. |
| `DrawingPrimitives.swift` | `DrawingText.font: DrawingFont` (`interRegular`, `interSemiBold`, `timesRoman`, `timesItalic`, `courier`); existing `bold:`/`serif:` initialisers map to it (no call-site change for the Floorplan). |
| `FloorPlanRendering.swift` | PDF renderer and `DrawingSVG` honour `DrawingText.font` (SVG: Courier family; `font-style="italic"` for Times-Italic). |
| `PDFDocument.swift` | `PDFPage.text(..., font:)`; fonts F4 `/Courier` and F5 `/Times-Italic` as standard Type1 with `/WinAnsiEncoding`; object numbering loop over [1...5]; declare only used fonts. |
| `FontMetrics.swift` | Courier (every WinAnsi glyph 600/1000) and Times-Italic (Adobe Core14 AFM widths, ASCII; other chars 500). `width(_:size:font:)`. |
| `ChapterBrand.swift` | `ChapterBrand.Sheet` palette: ink #1F2429, muted #6B6557, line #D9CCBC, nude #E8DDD0, wet #EFE6DA, ground #F5EFE6, surface #FAF5EE; `monoFamily = "'Courier New', Courier, monospace"`. Existing members unchanged. |
| `UnitFormatter.swift` | `sheetArea(_ m2:) -> "1,234.5 sq ft"`, `sheetMetricArea(_ m2:) -> "75.0 m²"` (thousands separators, one decimal). Existing methods unchanged. |
| `PlanExportContext.swift` | Add `sheetNumber: Int` (1-based capture index), `projectTitle: String` (projectName or address), `deviceName: String` (marketingName ?? model), `hasLidar: Bool`, `appVersion` short form (`record.app.version`), `compass: CompassReading?` (from the capture's heading fields; nil until the contract has them), `capturedDateText` ("Oct 17, 2026"). Keep existing fields. |
| `PreviewWriters.swift` | `SVGWriter` and `PNGWriter` rewritten on the sheet drawing (section 7); `PlanExporter.exportAll` list of section 2. |
| `Deflate.swift` | `PNGEncoder.encodeRGB(width:height:rgb:dpi:)` taking interleaved RGB bytes (no LUT). |
| `ExportSupport.swift` | `generatorVersion = "2.0.0"`. Remove `planTooLarge` only if no writer throws it any more (DXF does not). |
| `Tests/.../Support/Inspectors.swift` | `PDFFile`: parse fill colours (`rg`), dash arrays (`d`), filled paths and their bounds, text runs with font resource and size. |
| `Tests/.../PDFWriterTests.swift`, `ExportAllTests.swift`, `PreviewTests.swift`, `PNGTextTests.swift`, `FloorplanWriterTests.swift` | Port to the sheet / new previews (13.1); Floorplan golden. |
| `ios/App/AppCore/Sources/AppCore/VisitPackageBuilder.swift` | Doc comment: "DXF, CSV, plan sheet PDF, PNG, SVG". No logic change (it iterates `exportAll`). |
| `ios/App/AppCore/Tests/AppCoreTests/PackagePipelineTests.swift` | Expected names: `plan-sheet.pdf` instead of `plan.pdf` (and no `spatial-report.pdf` once `spatial-report` lands). |
| `docs/waves/specs/F3.md` | AC4/AC5 wording of 13.3; "Plan PDF" -> "plan sheet (Tabloid 11 x 17, 1:50 / 1:100 / 1:200 / 1:500 ladder)"; Spatial Report moved to the station. |
| `docs/waves/design/DESIGN.md` | New section "Plan sheet v2 (2026-10-21)": Tabloid sheet, real logo, Inter/Times/Courier, design palette on the sheet, north arrow states. (The file is frozen; this is the approved v2 replan.) |

### 8.3 Removed

| File / symbol | When |
|---|---|
| `PlanPDFWriter.swift` (`PlanPDFWriter`, `PlanPDFOutput`) | with the sheet (step 3). Its `fitted`/`wrap` helpers move to `PlanSheetLayout`. |
| `PlanScene.swift` (`PlanScene`, `PlanSheet`, `SceneLayer`, `PaperSize` if unused) | with the new previews (step 6). DXF does not use it (it uses `PlanGeometry`). |
| `GrayCanvas.swift` | replaced by `RasterCanvas` (step 6); keep `GlyphOutlines`. |
| `PlanScaleTests.swift` | replaced by `PlanSheetScaleTests.swift`. |

`SpatialReportWriter.swift` removal is area `spatial-report`.

### 8.4 Not changed

`FloorplanWriter` (colour Floorplan, Letter/square, bronze dims, door swings), the app's
`FloorplanView`, `tools/plan-render`, `tools/scan-browser`, `DXFWriter`, `CSVWriter`,
`RoomMetrics`, `PlanTotals`, room renaming (`room-names.json`, `RoomNaming`) — renamed rooms flow
into the sheet through the capture model as they do into every plan today.

---

## 9. Contract changes

| Item | Change | Owner |
|---|---|---|
| `contract/schema/capture-record.schema.json` | `schemaVersion` enum **"1.0.0" or "1.1.0"**; app writes 1.1.0. New **optional** fields on `$defs/capture`: `heading` (number, `minimum` 0, `exclusiveMaximum` 360; "Compass heading of the scan's −Z axis at scan start, degrees clockwise from north; true or magnetic per headingSource"), `headingAccuracy` (number, `minimum` 0, `maximum` 180; degrees, as the phone reports it), `headingSource` (enum `"true"`, `"magnetic"`), `headingRecordedAt` (`$ref dateTime`). `dependentRequired`: each of the four requires the other three. Omitted, never null. | `phone-capture` (writes); `plan-sheet` and `spatial-report` read |
| `contract/swift/.../CaptureRecord.swift`, `Enums.swift` | `CaptureRecordSchemaVersion` (1.0.0, 1.1.0; current 1.1.0) like `CaptureModelSchemaVersion`; `Capture.heading: Double?`, `headingAccuracy: Double?`, `headingSource: HeadingSource?` (`true` / `magnetic`), `headingRecordedAt: UTCTimestamp?`; `SchemaParityTests` updated. | `phone-capture` |
| `contract/ts` generated types + validators | regenerate; station accepts 1.0.0 and 1.1.0 (deploy the station first). | `phone-capture` / station |
| `contract/examples/north-arrow-states.json` | new shared vectors (4.6). | `plan-sheet` |
| File roles | **No change.** `plan_pdf` stays (now the plan sheet); its file name becomes `plan-sheet.pdf` (path, not schema). `spatial_report_pdf` handling is `spatial-report`'s. | — |
| Manifest `generatorVersion` for PlanExport files | "2.0.0". | `plan-sheet` |

Until the capture-record change ships, `PlanExportContext.compass` is nil and every sheet is
state 3 "No compass reading". The sheet code must not wait for it.

---

## 10. Where each value comes from, and what is not available

| Sheet value | Source |
|---|---|
| Sheet n, floor label | `record.captures` index, `capture.label` |
| Title line 1/2 | `hub.projectName`, `address.formatted`, `address.confirmedOnSite` |
| HUB deal, capture id | `hub.dealId`, `capture.captureId` |
| Captured | `capture.capturedAt` (UTC date), `operator.name` |
| Device | `device.marketingName ?? device.model`, `device.hasLidar`, `app.version` |
| Mode | `capture.mode` |
| Floor area | `PlanMetrics(model).totals.livableAreaM2` |
| Rooms / not scanned | model rooms; `capture.omittedRooms`, `capture.inaccessibleRooms` (name, reason) |
| Plan geometry | `capture-model.json` walls, rooms, doors, windows, openings, objects (category, box, confidence) |
| Room label, area, class | `room.label`, `room.type`, `RoomMetrics.floorAreaM2`, objects in room |
| Room dimensions | `RoomMetrics.boundingBox` |
| North arrow | `capture.heading*` (new; until then state 3) |

**Not available, so not shown**: station verdict and checks (the note card points to the spatial
report); package revision and sealed date (made before sealing); wall thickness (assumed, said in
the footnote); door swing (doors drawn as gaps); gross floor area; object sub-types ("Sofa
double"); casing; true north until the compass ships.

---

## 11. Dependencies on other areas

| Area key | What this area needs / gives |
|---|---|
| `phone-capture` | **Needs**: the compass reading recorded at the start of each floor's scan and the capture-record 1.1.0 fields of section 9 (mapping CoreLocation heading of the device to the scan's −Z axis is theirs). Not blocking: without it the sheet shows state 3. |
| `spatial-report` | **Coordinates**: removes `SpatialReportWriter` and `spatial-report.pdf` from `exportAll`; implements the same north arrow (section 4, shared vectors) on the cover and report plan; **must print the same numbers**: room bounding boxes = `RoomMetrics.boundingBox` definition, floor area sum rounded once, same "sq ft" / ft-in formats. Recommendation (theirs to decide): draw the report plan from the phone's `plan.svg` so both documents show the same drawing. |
| `phone-package` | Labels the role "plan sheet PDF" in "Package ready" ("Plan DXF · rooms CSV · plan sheet PDF, PNG, SVG"), `Summaries.kinds`; the "Compass reading" checklist item. |
| `web-review` | Role label "Plan sheet PDF" (`web/lib/format.ts`), file `plan-sheet.pdf`, download button "Plan sheet PDF", Documents card "Plan sheet PDF · Tabloid · 1 sheet · from the phone"; preview reads `plan_png` (now the v2 drawing). |
| station (`spatial-report` or a station area) | Accept capture-record 1.1.0; no change for `plan_pdf` (parsed by role only). |

---

## 12. Risks

| Risk | Mitigation |
|---|---|
| The rendition switch in `FloorPlanDrawing` changes the colour Floorplan | Record SHA-256 of `FloorplanWriter.write` PDF and SVG for every fixture + walk-through **before** the change; test equality after. |
| Title block overflow with long names/addresses or many skipped rooms | Deterministic stacking with gap compression and list truncation (3.7); tests with 100-char labels, 300-char address, 10 skipped rooms. |
| Room-dimension text (RoomMetrics, measured frame) and tick span (squared drawing) differ by millimetres | Accepted; text is the measured value. Test that they agree within 1 in on fixtures. |
| Station and phone compute different bounding boxes / areas | Cross-language golden values on the fixtures (spatial-report owns the TS side). |
| Up to 4 rungs x 2 turns = 8 drawings per capture | Probe with `estimatedDenominator` first; budget **< 2 s** for the walk-through fixture on an iPhone 16 Pro, measured in a release test. |
| Base-14 Courier / Times-Italic are not embedded | Allowed (no PDF/A requirement); widths from AFM keep layout exact; viewers substitute metric-compatible fonts. |
| RGB rasteriser correctness and speed | Golden PNG tests; budget ≤ 400 ms / ≤ 3 MB for the walk-through. Fallback: if step 6 slips, keep the PlanScene previews (do not delete `PlanScene` until step 6 lands). |
| Rename `plan.pdf` -> `plan-sheet.pdf` | HUB keeps old revisions' names; web and station key on role, not name. Update app and package tests. |
| Full-page #FAF5EE tint | As drawn; printers leave a white unprintable margin. Accepted. |
| Compass contract lands late | Sheet ships with state 3; no code path waits. |

---

## 13. Test plan and acceptance criteria

All Swift tests run on Linux: `swift test --package-path ios/Packages/PlanExport`. PDF validity:
`scripts/verify-exports.sh pdf ios/Packages/PlanExport/.build/test-output`.

### 13.1 Unit tests

| Test | Asserts |
|---|---|
| `PlanSheetWriterTests.testPageAndFrame` | MediaBox `[0 0 1224 792]`; page fill #FAF5EE first; border rect stroke 0.75 #6B6557; rule rect at x 912 w 0.75; one page. |
| `...testTitleBlockStrings` (box-room) | Shown text contains exactly: "SHEET 1 · FLOOR 1", "Existing-condition", "plan", "Floor 1 · Fixture box-room", "100 Example Street, Testville, NY 00000", "HUB deal", "fixture-deal-0001", "Capture id", "22bfb513-226d-4eca-bde1-0b6cb0c84aad", "Captured", "Oct 17, 2026 · Test Operator", "Device", "iPhone 16 Pro · LiDAR · app 1.0.0", "Mode", "One room", "Floor area, sum of rooms", "129.2 sq ft · 12.0 m²", "Rooms", "1 scanned", "Made on site, before the station checks", "LEGEND", the 8 legend labels, "SCALE", "0", "2.5", "5 ft", "1:50 at 11 x 17 in", "Orientation: not verified", "No compass reading", the statement (joined lines), "It's about time.", "hellochapter.com", "TEST ROOM", "129.2 sq ft". No "NOT SCANNED" block. |
| `...testNoPlaceholdersOrForbiddenGlyphs` (all fixtures) | No "[" or "]" in shown text; no ′ ″ ≈ ▲ ● ■; no "ft²" on the sheet; no "Gross". |
| `...testFonts` | Base fonts ⊆ {CHAPRA+Inter-Regular, CHAPSB+Inter-SemiBold, Times-Roman, Times-Italic, Courier}; no Helvetica; dimension strings and ids use Courier; title Times-Roman 25.5; tagline Times-Italic 11.25. |
| `...testLogoIsTheRealLogo` | The logo's filled paths equal `ChapterLogo.paths` at height 36 pt at (936, 60); no text run "chapter" or "RENOVATION" anywhere. |
| `...testNotScannedBlock` | With omitted ("Primary closet", "locked") and inaccessible ("Storage room", nil): "NOT SCANNED", "Primary closet · locked", "Storage room · could not enter", "Rooms not scanned have no geometry and are not drawn.", Rooms row "1 scanned · 2 not scanned". |
| `PlanSheetLayoutTests` | Stacking: footer bottom 732; gap = min(14, free/gaps); 424-like case g ≈ 9.21; 10 skipped rooms -> g = 8 and "+k more, listed in the spatial report"; 100-char label and 300-char address stay inside x 936–1164 and above the footer; sheet id wraps then cuts; legend column 2 at x 1044. |
| `PlanSheetScaleTests` (AC5) | box-room at **1:50**: room fill polygon edges **226.77 ± 0.57 pt** (4.000 m = 80.0 mm ± 0.2 mm) and **170.08 ± 0.57 pt**; tier-1 dimension line length equal within 0.57 pt; scale bar outline **86.4 ± 0.57 pt** (5 ft = 30.48 mm). 20 x 9 m room -> 1:100, ratio "1:100 at 11 x 17 in", bar labels "0", "5", "10 ft". 50 x 40 m -> 1:200 (the plan frame holds 13.76 x 11.0 m at 1:50, 27.5 x 22.0 m at 1:100, 55.0 x 44.0 m at 1:200, 137.6 x 110.1 m at 1:500). Exterior 120 x 90 m -> 1:500. Denominator always in the ladder. Oversize floor (70 x 50 m, mode floor): drawn at 1:200, clip path present, the too-big sentence in the footnote; no throw. |
| `PlanSheetDimensionTests` | box-room: "13' 1.5\"" top and bottom, "9' 10.1\"" left and right (tier 1), "14' 1.5\"" top and "10' 10.1\"" left (tier 2, confirm with WallLayout), all Courier 8.25; left texts rotated +90°; lines 0.4 ink; ticks 5 pt at 0.6; no inside-room dimensions; walk-through: no two dimension texts overlap; every dimension inside the annotation frame. |
| `PlanSheetRenditionTests` | Walls filled #1F2429, none thinner than 2 pt at 1:200; door layer has no curves (no `c`) and no leaf polygons; threshold 0.4 #6B6557 solid; passage dash `[2 2] 0 d`; window: surface fill + two 0.6 ink lines 2 pt apart; low-confidence object dash `[1.8 1.2] 0 d`; objects fill #FAF5EE stroke 0.6 #6B6557; toilet/sink/bathtub/stove draw their symbol, every other category a 4-corner box; outdoor room no fill + dash `[4 3] 0 d`. |
| `RoomClassTests` | bedroom -> #E8DDD0; bathroom/kitchen/laundry -> #EFE6DA; closet/hallway/"Room 3" -> #F5EFE6; "Room 3" with a bed -> nude; with a toilet -> wet; "Balcony" -> outdoor; renamed "Shower" (from Closet) -> wet. |
| `NorthArrowTests` | Shared vectors (4.6) for state and captions; geometry: verified at α = 0 has the arrow tip (16, 6.5) straight above the box centre; h = 90, θ = 0 -> tip left of centre; approximate ring dash `[2 2]` at 40 pt and arrow filled #FAF5EE; state 3 draws no polygon and has the 0.75 #6B6557 box with radius 3. |
| `ExportAllTests` | Names and roles in order: plan.dxf/plan_dxf, rooms.csv/rooms_csv, **plan-sheet.pdf/plan_pdf**, plan.png/plan_png, plan.svg/plan_svg (interim: spatial-report.pdf/spatial_report_pdf before plan.png until `spatial-report` lands); unique names; generator "chapter-capture-ios/PlanExport" "2.0.0"; **byte-stable** twice; small captures (1 x 1 m closet, one object, stray door) export without crashing. |
| `FloorplanWriterTests.testColourFloorplanUnchanged` | SHA-256 of `FloorplanWriter.write(...).pdf` and `.svg` for each fixture and the walk-through equal the values recorded before the change. |
| `PreviewTests` | plan.svg: well-formed XML, mm width/height = bounds/n + 12 mm, Courier family on dimension texts, `<title>` "Floor plan - Floor 1 (1:50)"; plan.png: valid RGB PNG, pHYs 300 dpi, background (255,255,255), a wall pixel (31,36,41) ± 2, a bedroom fill pixel (232,221,208) ± 2, no dimension text; room label pixels span its PDF width (Inter SemiBold + 0.9 pt tracking). |
| `RasterCanvasTests` | Nonzero vs even-odd; Bezier circle area within 0.5 %; dashes on/off lengths within 0.5 px; clipping; deterministic bytes. |
| AppCore `PackagePipelineTests` | Package lists `plan-sheet.pdf` per capture (and not `plan.pdf`). |

### 13.2 Snapshot / visual

- New script `scripts/verify/plan-sheet-snapshot.sh` (Docker, poppler `pdftoppm`): render every
  `plan-sheet.pdf` in test output at 72 dpi colour and **grayscale** (`-gray`); compare with goldens
  in `ios/Packages/PlanExport/Tests/Goldens/plan-sheet/{fixture}[-gray].png`: at most 0.5 % of
  pixels differ by more than 16 levels. Goldens: box-room, l-shaped-room, two-room-apartment,
  two-floor-house (both sheets), walk-through, **sample-424** in each north state (verified with
  h = 212, accuracy 8; approximate magnetic accuracy 12; not verified).
- Owner review (once, then frozen as goldens): sample-424 sheet next to artboard 1b; sample-424
  approximate in grayscale next to artboard 1ac. Accept when layout, strings and weights match
  this spec (Inter metrics and the real logo are expected differences).

### 13.3 Acceptance criteria (replace F3 AC4/AC5 for the plan PDF)

```yaml criteria
PS1: {text: "plan-sheet.pdf is a valid one-page PDF 1.7, 1224 x 792 pt, role plan_pdf, written for every fixture capture", verify: "cmd:swift test --package-path ios/Packages/PlanExport --filter PlanSheetWriterTests"}
PS2: {text: "The sheet contains as extractable text the address, the capture id, and every room label in capitals (AC4 for the sheet)", verify: "cmd:swift test --package-path ios/Packages/PlanExport --filter PlanSheetWriterTests"}
PS3: {text: "Scale is from the ladder (1:50, 1:100, 1:200, 1:500 exterior); a 4.000 m room edge is 80.0 mm at 1:50 within 0.2 mm; the scale bar is exact (AC5)", verify: "cmd:swift test --package-path ios/Packages/PlanExport --filter PlanSheetScaleTests"}
PS4: {text: "North arrow states and captions match contract/examples/north-arrow-states.json", verify: "cmd:swift test --package-path ios/Packages/PlanExport --filter NorthArrowTests"}
PS5: {text: "The colour Floorplan writes the same bytes as before", verify: "cmd:swift test --package-path ios/Packages/PlanExport --filter FloorplanWriterTests"}
PS6: {text: "qpdf --check is clean and pdftotext finds text in every PDF", verify: "cmd:scripts/verify-exports.sh pdf ios/Packages/PlanExport/.build/test-output"}
PS7: {text: "plan.png decodes as RGB at 300 dpi and plan.svg is well-formed XML", verify: "cmd:scripts/verify-exports.sh preview ios/Packages/PlanExport/.build/test-output"}
PS8: {text: "Sheet renders match the colour and grayscale goldens", verify: "cmd:scripts/verify/plan-sheet-snapshot.sh"}
```

---

## 14. Build order

1. **Engine fonts**: `DrawingFont`, F4 Courier, F5 Times-Italic, `FontMetrics`; tests. Record Floorplan golden hashes first.
2. **North arrow**: `NorthArrow` (classify, captions, items), shared vectors JSON, tests.
3. **Plan sheet page**: `PlanSheetLayout` + `PlanSheetWriter` with the **current** colour drawing temporarily, title block, ladder, footnote; switch `exportAll` item 3 to `plan-sheet.pdf`; delete `PlanPDFWriter`; port PDF tests.
4. **Rendition `.planSheet`**: palette, openings, symbols, labels, room classes; Floorplan golden stays green.
5. **Sheet dimensions** (`PlanSheetDimensions`); AC5 tests; sample-424 fixture and goldens.
6. **Previews**: `RasterCanvas`, `encodeRGB`, `SVGWriter`/`PNGWriter` on the drawing; delete `PlanScene`, `PlanSheet`, `GrayCanvas`; port preview tests.
7. **Docs**: F3 ACs, DESIGN.md section; AppCore test names.
8. When `phone-capture` ships the heading fields: wire `PlanExportContext.compass`; add verified/approximate goldens from real fixtures.

---

## 15. Open questions (with the default to build if nobody answers)

| # | Question | Default |
|---|---|---|
| Q1 | The artboard's scale bar is 10 ft at 1:50 (172.8 pt) beside the 40 pt north block with its caption; in the 228 pt title block that row needs ≥ 250 pt, so it cannot be built as drawn. | Fixed **86.4 pt** bar (5 ft at 1:50, 10 at 1:100, 20 at 1:200, 50 at 1:500), tick labels under the bar, "1:50 at 11 x 17 in" on its own line. |
| Q2 | A capture whose display units are metric: should the sheet switch to metric? | **No.** The sheet is always imperial first (ft-in, sq ft), metric only after the floor area total; DXF and CSV stay metric. Same as the spatial report. |
| Q3 | Drawing ink: design token **#1F2429** (bundle) or brand black **#231F20** (`ChapterBrand.ink`, Oct 19 plans)? | **#1F2429** for walls, text and lines on the sheet and its previews (as drawn); the logo keeps #231F20. |
| Q4 | A floor bigger than the last ladder rung (180 x 144 ft; 450 x 360 ft exterior). | Draw at the last rung, clip at the frame, footnote "The plan is larger than this sheet at 1:200 and is cut at the frame. plan.dxf holds the whole floor." Never throw, never fit to page. |
| Q5 | RoomPlan measures no wall thickness; the bundle says "at scanned thickness". | Use the colour Floorplan's assumed 4.5 in / 6 in (≥ 2 pt drawn) and add the footnote sentence of 3.5. |
| Q6 | Overhead / wall-hung objects (upper cabinets, a mounted TV) are not covered by the bundle. | Unfilled solid 0.6 pt muted box, drawn last (so it hides nothing and is not mistaken for low confidence). |
| Q7 | "Captured" date: UTC (today's title block) or the phone's local date? | **UTC** date of `capturedAt` (deterministic; the contract has no time zone). Revisit if the record gains one. |
| Q8 | plan.png cannot draw Courier (no outlines in pure Swift). | plan.png has **no dimension strings** (as the 2j preview); plan.svg keeps them. |

---

## Addendum (completeness critique, Oct 21, 2026) — binding, overrides the body above

Numbers refer to `00-critique.md`. Built by track **T5 plan-export**, which owns all of
`ios/Packages/PlanExport/**` (this spec, compass §6.3, the `SpatialReportWriter` removal, the
report parity goldens) and `fixtures/report-parity/**`. Contract and fixtures are built by **T0**.

### E1. Contract (R-1, R-5) — §9 superseded
The capture-record fields are compass §4.1: `headingAccuracy` is an **integer 1–180**, the
optional `headingIssue` (`rejected`, `not_calibrated`, `unavailable`) exists, `heading` has one
decimal. `PlanExportContext.compass` is a contract `CompassState` (`CompassState(capture)`), not a
PlanExport `CompassReading`. `contract/examples/north-arrow-states.json` is not created; the rows
of §4.6 go into `contract/test-vectors/compass-states.json` with integer accuracies (true 10 →
verified, 11 → approximate, 30 → approximate, 31 → not verified; heading 359.6 → caption `0°`; the
"accuracy 7.5" row is dropped).

### E2. North symbol (R-6, R-7, R-10, R-12)
- `NorthArrow.swift` follows compass §6.3: `items(symbol: NorthSymbol, centerMM:, boxMM:, page:,
  caption:)` and `blockSizeMM`. `NorthArrow.State` and `classify` are not built; the contract's
  `NorthSymbol(state:drawingRotationCCW:)` gives the texts and the angle.
- Captions (compass §1.4): not verified reasons `No compass reading`, `Reading rejected`,
  `Compass accuracy ±{ACC}°` (replaces "Low compass accuracy"), `Compass not calibrated`,
  `Compass unavailable`.
- Caption line 2 prints `A`, the bearing of sheet-up: `A = heading − FloorPlanDrawing.rotationDegrees`
  (mod 360, rounded half up, never 360) — not the stored heading. §4.3 and §4.4 are corrected:
  the arrow angle and `{HDG}` are the same number.
- Not-verified box: 15 pt tall (padding 3 + line 9 + 3), border 0.75 stroked on the box edge,
  radius 3; width = measured text width (Inter 7.5) + 12. The north block width in §3.6 G uses
  this width instead of 97.4.
- Symbol ink `#1F2429` (the sheet's ink; R-8).

### E3. The colour Floorplan and the previews (compass §6.3, R-9)
- This track also builds compass §6.3 in PlanExport: `FloorplanWriter.Options.north:
  CompassState?` (default nil = draw nothing), `FloorPlanDrawing.Options.north`, the eight-point
  rose replaced by `NorthArrow.items(…, caption: false)`, `Layout.addressWidth(pageWidth:
  northBlockWidthMM:)`. PS5 (Floorplan bytes unchanged) is recorded and checked **with
  `north: nil`**; the app passes `north` (T10, `FloorplanView.swift`).
- `plan.png` and `plan.svg` carry **no** north symbol (§7 stands; compass §6.2's plan.png/svg row
  is withdrawn).

### E4. `SpatialReportWriter` (R-11)
This track deletes `SpatialReportWriter.swift` in build step 3 together with `PlanPDFWriter`; the
"interim rule" of §2 is withdrawn. `exportAll` returns the five files of §2; `ExportAllTests` lists
only them and adds `testNoSpatialReportIsWritten`; `PDFWriterTests` drops the spatial report
tests (phone-package §11 rows for PlanExport).

### E5. Printed dates (R-34) — Q7 overridden
The "Captured" row prints `capturedAt` in **America/New_York** (`ChapterBrand.printTimeZone`,
`TimeZone(identifier: "America/New_York")`, deterministic on Linux), the same default as the
station's `REPORT_TIME_ZONE`, so the sheet and the report print the same date. Test: a capture at
`2026-10-18T01:30:00Z` prints `Oct 17, 2026`.

### E6. Room fill rule is shared (R-35)
§3.4.1 is the rule for both documents, with one addition: every room of a capture whose mode is
`exterior` is **outdoor**. `ReportParityGoldenTests` (spatial-report §11.2, built here) writes
`fillClass` (`habitable` / `wet` / `other` / `outdoor`) per room so the TS port must match.
Add the renamed "Shower" (type nil, label "Shower") → `wet` to `RoomClassTests` and to the goldens.

### E7. Fixtures (R-19, G-3)
`fixtures/generated/sample-424/` is generated by T0 (one 424 fixture for the sheet and the
report: geometry of `apartment-424.js`, 12 rooms, 14 objects, the two skipped rooms, 7
living-room photos, Floor 1 compass 212.4° ±8 true). The generator writes the plan PDF as
`plan-sheet.pdf`. This track consumes it; it does not edit `fixtures/generator`.

### E8. Parity goldens owned here
`ios/Packages/PlanExport/Tests/PlanExportTests/ReportParityGoldenTests.swift` and
`fixtures/report-parity/*.json` (spatial-report §11.2) are built in this track; any change to
`RoomMetrics`, `PlanTotals`, `UnitFormatter` or the fill rule regenerates them in the same PR.

### E9. Dependencies renamed
§11 "phone-capture" (compass reading) reads `compass`. §11 web row: the Documents card prints
`Tabloid · 1 sheet · from the phone` for `generatorVersion` ≥ 2.0.0 (web-review addendum D8),
which relies on §2's `generatorVersion = "2.0.0"`.
