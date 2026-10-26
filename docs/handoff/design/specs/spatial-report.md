# Build spec · spatial-report · Spatial report v2 (station, after the checks)

Area key: `spatial-report`. Artboards (to build): 1f–1i `report-cover-v2`, 1k–1l `report-plan-v2`,
1n `report-schedule-v2`, 1p–1r `report-checks-v2`, 1t/1w/1x/1y/1z/1aa `report-room-v2`,
1u `report-photos-v2`, rules from 1ab `system-v2`, print proof 1ac `bw-proof-v2`. North arrow
states from 1d `north-arrow-v2`. v1 artboards (1e, 1j, 1m, 1o, 1s, 1v) are the current look and
are not built.

Repo baseline: branch `feat/floorplan-report` at `05f16e8`. Everything in this spec is in points
(pt, 1/72 in) on a US Letter landscape page (792 × 612 pt) unless it says px. pdfkit coordinates:
origin top-left, y down (the same as the HTML artboards).

---

## 0. Scope and binding decisions

### 0.1 What this area builds

1. The **spatial report v2** PDF, rendered by the station worker after the acceptance checks, in
   the publish job, with pdfkit (`station/hub`, `pdfkit@0.20.2` + `fontkit@2.0.4` are installed).
2. It **replaces the station verdict report** (`station/hub/src/report.ts`,
   `renderVerdictReport`, spec F9 step F9.2). The HUB gets one document per verdict:
   `spatial-report-{verdictId}.pdf` in `Capture/{visitId}/r{revision}`.
3. A TypeScript port of the phone's **measurement engine** (PlanGeometry, MetricsGeometry,
   RoomMetrics, PlanTotals, UnitFormatter rounding) so every number equals the phone's plan sheet,
   proved by shared golden files.
4. **Storage of the rendered PDF** for the web review (Blob container `reports`, table
   `spatial_reports`, `GET /packages/{packageId}/spatial-report`).
5. Updated F9 tests (AC1–AC6 keep passing; the assertions that quote v1 wording change, listed in
   §10) and new tests (§11).

### 0.2 Not in this area

- Retiring the phone's `SpatialReportWriter` and the role `spatial_report_pdf`: area
  `phone-package` §11 (including the `HUB_UPLOAD_ROLES` change in `station/hub/src/plan.ts` and the
  fixture generator). This spec assumes it and handles legacy packages (§7.6).
- Recording the compass: areas `north-arrow` / `phone-capture` (capture-record fields,
  `CompassState`). This report only reads them (§6.9); until they ship every floor shows state 3.
- The plan sheet (phone, Tabloid): area `plan-sheet`. Shared: tokens, the metrics engine (goldens).
- Web pages that show/download the report: area `web-review` (consumes §8.3, §8.4).

### 0.3 Owner decisions applied (Oct 21, 2026, override the bundle)

| # | Decision | What it means here |
|---|---|---|
| 1 | Real Chapter logo and Inter everywhere | The typed serif "chapter / RENOVATION" block in every artboard header is replaced by the real logo `web/public/brand/chapter-logo.svg` (full logo with RENOVATION, viewBox 0 0 1756 635, fill #231F20). Every place the bundle says Helvetica uses **Inter** (Regular 400; "bold"/700 → **Inter SemiBold 600**, as PlanExport embeds). Times stays **Times** (PDF standard `Times-Roman`, as PlanExport does). Courier stays **Courier** (PDF standard). |
| 2 | Web in HUB design system | Not this area (the report is print, Chapter print palette). |
| 3 | Spatial report on the station after checks; phone writer and role retire; compass 3 states (±10° / ±30°) | §0.1, §6.9. |

Bundle decisions kept (`02-decisions-and-open-questions.md`, `00-plan-of-changes.dc.html`): word +
shape for verdicts (● Ready, ▲ Limited, ■ Blocked, never colour alone); not-certification statement
on every page; no invented data (brackets only in mock-ups); unlabeled rooms "Room N" + muted
"unlabeled"; item names = category names only; keep inscribed rectangle, drop casing; feet-inches
and sq ft first, metric small; furniture as boxes, symbols only for toilet, sink, bathtub, stove;
"Floor area, sum of rooms" (no gross area; never the Polycam 95928.0 figure); "sq ft"/"cu ft";
ASCII `'` and `"` for feet and inches; "approx." never ≈.

### 0.4 Resolved inconsistencies inside the bundle (no owner input needed)

| Topic | Bundle says | This spec |
|---|---|---|
| Header wordmark | typed Times "chapter" 24 + RENOVATION 6 tracked 3.75 | real logo, 34 pt tall, top-right (§3.3) |
| Logo colour vs ink | ink #1F2429 | logo keeps its own fill #231F20 (brand black); all other ink stays #1F2429 |
| Room area label on plans | helper default 6.75 pt | 7.5 pt (system 1ab: 7.5 pt minimum; only marker numbers and the north "N" are smaller) |
| Item marker in tables | mock code draws ~8.6 pt (11-unit glyph in a 14-unit box at 11 pt) | 11 pt glyph, 6.5 pt number (system 1ab §6 text) |
| Tile "approx." | appended to the 11.25 pt value (overflows the 83 pt tile) | moved to the tile's metric line: "2.48 m · approx." (system 1ab §9: tags are muted text next to the value) |
| Contents capacity | "26 rows" | 15 rows: what fits the drawn column above the 7-item legend (§5.2.3) |
| Schedule rows | "24 data rows per page" | rows are packed by measured height (a row is 16.75 or 28.75 pt), at most 24 per page (§5.3.4) |
| Room page rows | "12 item rows; continuation pages of 24" | same caps, but a page also ends when the next row does not fit (§5.5.6) |
| Photo crop | "cropped to 4:5" but cells are 134 × 160 pt | image 128 × 160 pt (exactly 4:5) centred in the 134 pt column (§5.6) |
| Rule set | 9 example rules (`orientation.compass`, `ceilings.tape`, …) and "[EXAMPLE RULE SET]" | the rules in `verdict.checks` (today the 12 `RULES` of `station/checks/src/types.ts`); bracket text dropped |
| Fixed page refs | "(page 4)", "Two blockers", "/ 28" | computed (§4) |
| Footer statements | cover and checks page draw two slightly different full statements | both kept verbatim (§3.5) |
| Item groups | RoomMetrics `ObjectGroup` (shelf → furniture; fireplace, stairs → other) and names (Cabinet, Coffee table) | system 1ab §6 groups and decision-3 category names for the report (§6.6) |
| Photo labels | "Opening, window", "looking up" | not in the contract; subject enum names and N/E/S/W only (§6.8) |

---

## 1. Where, when, what file

| Item | Value |
|---|---|
| Made by | station worker, publish job (`station/worker/src/publish-job.ts` → `HubPublisher.publish`) after a stored verdict (`packages.status = verdict_ready`). Never on the phone. No report for `check_error` (no verdict). |
| Inputs | verdict (DB), capture record (DB), manifest (sealed), per capture `capture-model.json` (role `capture_model`), `field-controls.json` (role `field_controls`), photos (role `photo`, labels from the manifest entry `photo`), the publication plan (where each file is), `REVIEW_BASE_URL`, `REPORT_TIME_ZONE`. All files read through the existing verified reader (`readVerified`, SHA-256 checked). |
| Paper | US Letter landscape 792 × 612 pt, PDF 1.7, `size: [792, 612]`, `margin: 0` (layout is absolute). |
| File name | `spatial-report-{verdictId}.pdf` (was `verdict-report-{verdictId}.pdf`): one per verdict, so a newer verdict never replaces an older file. |
| HUB folder | `Capture/{visitId}/r{revision}` (unchanged visit folder). |
| Station copy | Blob container `reports`, blob `{packageId}/spatial-report-{verdictId}.pdf`; row in `spatial_reports` (§8.2). |
| Size limit | ≤ 45 MiB (`MAX_HUB_UPLOAD_BYTES`); photo budget chain in §5.6.6 keeps it under. |
| Deterministic | Same input → byte-identical PDF (dates from `verdict.evaluatedAt`, no clock, no randomness, pinned libraries). |
| PDF info | Title `Spatial report · {title line} · revision {N}`; Author/Creator/Producer `Chapter Capture station`; Subject `Spatial report and station verdict ({outcome}) for package {packageId}`; CreationDate = ModDate = `verdict.evaluatedAt`; `lang: "en-US"`; `displayTitle: true`; `font: "Times-Roman"` in the constructor (so the default Helvetica is never registered or written). |

---

## 2. Page order and the page list

```
1            Cover                                   (always 1 page)
[c]          Contents                                (only when the contents do not fit the first plan page, §5.2.3)
2…           Floor plan, one page per floor          (contents column on the first one)
…            Room schedule (1+ pages)
…            Capture checks (1+ pages: "Capture checks (continued)")
per floor (capture-record order), per room in schedule order:
             Room page, continuation pages (0+), site-photo pages (0+)
per floor:   "Other site photos" pages (0+; photos whose room label matches no room, §5.6.5)
last         Package record (1+ pages, §5.7: capture record, captures, files with SHA-256 and links)
```

The 424 West End sample (1 floor, 12 rooms, every room photographed, ≤ 10 photos each): cover 1,
plan 2, schedule 3, checks 4, rooms 5–28, package record 29 (and 30 if the file list needs it).
The mock's "/ 28" becomes "/ 29" or "/ 30" because of the package record (§13 Q1).

Page numbers are known before drawing (§4.2).

---

## 3. Page system (every page)

### 3.1 Colours (tokens; hex exact)

| Token | Hex | Use |
|---|---|---|
| `ink` | #1F2429 | text, walls, strong rules (table header/total rules), scale bar, QR modules |
| `muted` | #6B6557 | captions, secondary text, object lines, dashes, thresholds, "None" |
| `line` | #D9CCBC | table rules, header/footer rules, note-box borders |
| `nude` | #E8DDD0 | habitable room fill, photo placeholder |
| `wet` | #EFE6DA | wet room fill (bath, kitchen, laundry) |
| `ground` | #F5EFE6 | other room fill, tiles background |
| `surface` | #FAF5EE | page background (full page rect), object box fill, marker fill, window/door clears |
| `ready` | #2E5E2E | ● glyph, "Ready"/"Passed" word, ready border |
| `limited` | #9A6A1E | ▲ glyph, limited border |
| `limitedText` | #7A5214 | "Limited" word |
| `blocked` | #8B2E2E | ■ glyph, "Blocked" word and border — nothing else is ever red |
| `logo` | #231F20 | the logo fill only |

B&W rule (1ac): meaning never depends on hue. The three fills print as three distinct greys
(nude 88 %, wet 92 %, ground 95 % lightness); verdicts carry word + shape; dashes differ by pattern.

### 3.2 Type (pt / line height in pt)

Fonts: `Inter` = Inter Regular, `Inter-SB` = Inter SemiBold (both embedded, subset by pdfkit),
`Times-Roman`, `Courier` (PDF standard fonts, WinAnsi, not embedded — same as PlanExport).

| Role | Font | Size / line | Other |
|---|---|---|---|
| Kicker | Inter | 7.5 / 9 | uppercase, tracking 1.5 (1.2 inside columns/boxes), `muted` |
| Page header title | Times-Roman | 21 / 24 | `ink` |
| Header subline | Inter | 9.75 / 12 | `muted` |
| Section heading | Times-Roman | 16.5 / 19 | Overview, Capture, Contents, Room schedule, Capture checks, Package record, floor name |
| Room title | Times-Roman | 22.5 / 26; 16.5 / 19 when the name is longer than 40 characters | max 2 lines, then "..." |
| Photo page title | Times-Roman | 22.5 / 26 | |
| Verdict word / headline | Inter-SB | 12 / 14 | verdict text colour |
| Tile value | Inter-SB | 11.25 / 13 | shrinks in 0.75 steps to 9 when it does not fit 83.25 pt |
| Body | Inter | 9.75 / 12 | |
| Table text, data rows | Inter | 9 / 11 | numbers right-aligned; bold cells Inter-SB |
| Dimensions in tables | Courier | 9 / 11 | ASCII `'` `"` |
| Dense table, table headers, legends | Inter | 8.25 / 10 | headers `muted` |
| Caption, footer, footnote | Inter | 7.5 / 9 (footnotes 7.5 / 9.5) | minimum size |
| Ids, hashes | Courier | 7.5 / 9 | |
| Plan dimension strings | Courier | 7.5 | |
| Plan room name / area | Inter-SB 7.5 `ink` / Inter 7.5 `muted` | 7.5 (area line baseline 1.5 × size below the name) | |
| Marker numbers | Inter-SB | 6.5 | the one exception to 7.5 (with the north "N") |
| North arrow "N" | Inter-SB | 6 × size/32 | |

Line positioning (to match the HTML artboards): every text line sits in a line box of the stated
line height with CSS half-leading: `top = lineBoxTop + (L − (asc − desc) × s / 1000) / 2`, drawn
with pdfkit `doc.text(str, x, top, { lineBreak: false, baseline: "top" })` where `asc`/`desc` are
the font's ascender/descender (pdfkit `font.ascender`, `font.descender`, 1/1000 em). Multi-line
text is wrapped by our own `textBlock()` (§7.3) — never pdfkit's own `lineGap` flow — so each line
lands exactly `L` below the previous one. Tracking uses pdfkit `characterSpacing`; the measured
width of tracked text is `widthOfString + spacing × (chars − 1)` (centred/right-aligned text uses
that width).

All strings pass `pdfSafeText()` (today's function, unchanged: `−`→`-`, `≤`→`<=`, `≈`→`~`, `→`→`->`,
`…`→`...`, `●`→`*`, `▲`→`^`, `■`→`#`, `′`→`'`, `″`→`"`, NBSP→space, other non-WinAnsi → `?`).
`×`, `·`, `–`, `—`, `±`, `°`, `²`, `³` are WinAnsi and stay. Truncation appends `...`.

### 3.3 Header (every page)

| Element | Position | Spec |
|---|---|---|
| Kicker | x 36, line box y 36–45, max width 610 | "Spatial report" + " · " parts (§5 per page), uppercase, tracking 1.5, single line, "..." |
| Title | x 36, line box y 48–72, max width 610 | Times-Roman 21 `ink`, single line, "..." — the **title line** (§6.1) |
| Subline | x 36, line box y 75–87, max width 610 | Inter 9.75 `muted`, single line, "..." — the **address line** (§6.1); on the cover + " · address confirmed on site" or " · address not confirmed on site" |
| Logo | x 662.0–756.0, y 36.0–70.0 | real logo, 34 pt tall × 94.0 pt wide (1756/635 × 34), paths from `chapter-logo.svg` drawn with `doc.path(d)` under `translate(662, 36) scale(34/635)`, fill #231F20, nonzero |
| Rule | x 36–756, y 90, 0.75 thick | `line` |

### 3.4 Content box

x 36–756 (720), y 102–528 (426). 12 columns of 49 pt with 12 pt gutters: spans 1 = 49, 2 = 110,
3 = 171, 4 = 232, 5 = 293, 7 = 415, 8 = 476, 9 = 537, 12 = 720.

### 3.5 Footer (every page)

| Element | Position | Spec |
|---|---|---|
| Rule | x 36–756, y 536, 0.75 | `line` |
| QR code | x 36–66, y 544–574 (30 × 30, centred in the 34 pt band y 542–576) | vector; encodes the **review URL** `${REVIEW_BASE_URL}/packages/{packageId}` (no trailing slash), error correction L, `qrcode@1.5.4` `QRCode.create(url, { errorCorrectionLevel: "L" })`; background rect `surface`, modules `ink` squares of 30 / moduleCount pt (horizontal runs merged), no quiet zone inside the 30 pt (≥ 4 modules of page clear around: left 36 pt margin, right 10 pt gap, rule 8 pt above). Link annotation over the QR to the review URL. |
| Line 1 | x 76 to (756 − page-number width − 10), Inter 7.5/9 `ink` | `Review link · {capture part} · captured {Month D, YYYY} · report generated {Month D, YYYY}` + on the cover ` by the Chapter station`. `{capture part}` = `capture {captureId}` (captureId in Courier 7.5) on floor pages (plan, room, photos) and on visit-wide pages of a 1-capture visit; `package {packageId}` (Courier) on visit-wide pages of a 2+ capture visit. "captured" = visit date (`captureRecord.visitedAt`); omit "· captured …" when there is no capture record. "report generated" = `verdict.evaluatedAt` date. "Review link" is also a link annotation. |
| Line 2 | below line 1, gap 1.5, Inter 7.5/9 `muted`, wraps to max 2 lines | cover: **full statement A**; checks pages: **full statement B**; every other page: **short statement** |
| Page number | right-aligned at x 756, vertically centred, Inter 7.5/9 `muted` | `{n} / {N}` |

The text column (line 1 + line 2) is vertically centred in the 34 pt band.

Statements (verbatim):

- **Full A (cover):** "Generated by Chapter Capture from an on-site LiDAR scan. Measurements are
  scan estimates and may differ from real conditions. This report is an automated check of the
  intake package. It does not certify any property model or measurement. Verify dimensions on site
  before planning or construction."
- **Full B (checks pages):** "Generated by Chapter Capture from an on-site LiDAR scan. This report
  is an automated check of the intake package. It does not certify any property model or
  measurement. Verify dimensions on site before planning or construction."
- **Short (all other pages):** "Automated check of the intake package; not a certification of any
  property model or measurement. Scan estimates: verify on site."

Constants (exported from `station/hub/src/report/words.ts`, re-exported by `index.ts`):
`REPORT_STATEMENT_FULL` = Full A, `REPORT_STATEMENT_CHECKS` = Full B, `REPORT_STATEMENT_SHORT`,
and `REPORT_NOT_CERTIFICATION` = Full A (name kept for F9 tests; value changes).
`REPORT_TITLE` = "Chapter Capture spatial report".

### 3.6 Verdict glyphs (vector paths, never text)

10-unit box scaled to the stated size:
- ● circle centre (5, 5) r 4.6 (table glyph r 4.4)
- ▲ path `M5 0.5 L9.6 9.3 L0.4 9.3 Z` (table: `M5 0.6 L9.6 9.4 L0.4 9.4 Z`)
- ■ rect (0.6, 0.6, 8.8 × 8.8) (table: 0.8, 0.8, 8.4 × 8.4)
- — (not applicable, table only) rect (1, 4.3, 8 × 1.4)

Sizes: cover verdict block 10 pt, checks band 11 pt, checks table 8 pt. Fill colours: ready
#2E5E2E, limited #9A6A1E, blocked #8B2E2E, n/a #6B6557.

### 3.7 Plan line weights (system 1ab §5)

| Element | Rule |
|---|---|
| Wall | filled polygon `ink`; band thickness = scanned `thicknessM` if > 0, else assumed 4.5 in (0.1143 m) for a wall that bounds 2+ rooms (`roomIds` merged over coincident walls) and 6 in (0.1524 m) otherwise (the phone Floorplan's assumptions); drawn at least 2 pt thick on cover/plan/room pages (key plan: at least 0.5 pt); band centred on the centreline; each end extended by half the band thickness (square cap) so corners close |
| Window | wall band cleared to `surface` over the opening span, then two 0.6 pt `ink` lines along the centreline offset ±1 pt (2 pt apart), spanning the opening |
| Door | band cleared over the span; threshold 0.4 pt `muted` solid on the centreline. No leaf, no swing |
| Open passage | as door, threshold dash 2 / 2 |
| Object box | 0.6 pt `muted` stroke, `surface` fill, square corners, oriented by the object's yaw |
| Low-confidence object (`confidence: "low"`) | same box, dash 1.8 / 1.2 (inner symbol lines solid) |
| Outdoor edge (rooms of a capture with `mode: "exterior"`) | no fill, 0.6 pt `muted`, dash 4 / 3 |
| Ceiling change | not available in the data: never drawn |
| Bounding box (room page) | 0.75 pt `muted`, dash 3 / 2 |
| Inscribed rectangle (room page) | 0.75 pt `muted`, dash 0.6 / 2, round caps; only when the room is not a rectangle (§6.5) |
| Dimension line | 0.4 pt (`ink`, or `muted` for inscribed), end ticks 5 pt long (±2.5) at 0.6 pt; no extension lines |
| Table rule | 0.75 `line`; header and total rules 0.75 `ink` |

Fixture symbols (by category only, drawn in the box's local frame; w = box width along local x,
d = box depth along local z; stroke 0.6 `muted`):
- **bathtub**: box + inner rounded rect inset i = min(w, d) × 0.18, corner radius i
- **sink**: box + ellipse at centre, rx = w × 0.34, ry = d × 0.32
- **stove**: box + 4 circles r = min(w, d) × 0.17 at (0.27, 0.3), (0.73, 0.3), (0.27, 0.7), (0.73, 0.7) of (w, d)
- **toilet**: no box; tank rect (full w, depth 0.3 d) on the side of the box nearest to a wall
  centreline, bowl ellipse centre at 0.64 d from that side, rx 0.46 w, ry 0.34 d; both `surface` fill
- everything else: the box only

Draw order on plans: room fills → objects (parents before children, `parentId`) → walls →
window clears + lines → door/passage clears + thresholds → room labels → dimension strings →
(room page) bounding box, inscribed rectangle, item markers.

### 3.8 Item markers (system 1ab §6)

Shapes by group: furniture ● circle, fixture ▲ triangle, appliance ◆ diamond, opening ■ square,
other ⬟ pentagon. Size 12 pt on plans, 11 pt in tables and legends; stroke 0.75 `ink`, fill
`surface`; number Inter-SB 6.5 `ink` centred (triangle: number 0.25 r lower). With r = size/2 and
centre (x, y):
- circle r; square side = size; triangle (x, y−1.15r) (x+1.15r, y+0.85r) (x−1.15r, y+0.85r);
- pentagon (x, y−1.15r) (x+1.1r, y−0.35r) (x+0.68r, y+0.95r) (x−0.68r, y+0.95r) (x−1.1r, y−0.35r);
- diamond (x, y−1.2r) (x+1.2r, y) (x, y+1.2r) (x−1.2r, y).
Numbering restarts at 1 in each group, in table order. Legend glyphs have no number.

### 3.9 North arrow and scale bar

North arrow (1d, all geometry in a 32-unit box scaled by size/32, strokes and text included):
- **Verified**: ring circle centre (16, 18) r 10.5, stroke 0.75 `ink`, no fill; arrow polygon
  (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5) fill `ink`, stroke 0.75 `ink`, round joins; "N"
  Inter-SB 6 `ink`, centred at x 16, baseline y 4.6. Caption below (2 pt gap), Inter 7.5/9
  `muted`, centred, 2 lines: "True north · compass" / "±{acc}° · {hdg}°".
- **Approximate**: ring dash 1.6 / 1.6; arrow fill `surface`. Caption "Approx. north · compass" /
  "±{acc}° · true" or "±{acc}° · magnetic".
- **Not verified**: no arrow, ever. Text box: border 0.75 `muted`, radius 3, padding 3 × 6,
  "Orientation: not verified" Inter 7.5/9 `ink`, single line; caption below (2 pt gap) Inter
  7.5/9 `muted`: the reason (§6.9).
- The whole box (ring, arrow, N) rotates about its centre (16, 16) by the arrow angle (§6.9); the
  caption does not rotate.
- Sizes: cover 32 pt (1 floor) / 26 pt (2–3 floors); floor plan page 32 pt.

Scale bar (plan-parts `scaleBar`): bar length = ptPerFt × F, F = the smallest of 5, 10, 20, 50,
100 ft whose bar is ≥ 60 pt (10 for the sample). Two halves: first half `ink` fill, second half
`surface` fill, each 5 pt tall; outline 0.6 pt `ink` over the whole bar (rect at +0.5, +0.5, F ×
ptPerFt wide, 5 tall). Label 3 pt below, Courier 7.5 `ink`: `0    {F/2}    {F} ft` (four spaces
between numbers; F/2 printed as `2.5` for F = 5). No ratio text in the report (the drawing is fitted).

---

## 4. Layout engine and pagination

### 4.1 Two passes

1. **Model** (`buildReportModel`, pure): floors, rooms (metrics, sort order, labels), schedule
   rows, check rows, photo groups, strings with page-number placeholders.
2. **Pagination** (`paginate`, pure): splits the model into a `PageSpec[]` using measured text
   heights (pdfkit `widthOfString` with the embedded fonts; no drawing). Page-dependent strings
   (contents ranges, "page N" in sentences, schedule "Page" column, `n / N`) live only in
   fixed-size cells or single lines whose wrapping never moves a page break, so page numbers
   resolved after pass 2 cannot change the page count.
3. **Render**: draw every `PageSpec` with the resolved numbers.

`renderSpatialReport()` returns `{ bytes, sha256, pages, checksPage, recordPage, name }`.

### 4.2 Page-number rules

- Contents range of a room: first page of its room page → last page of its photo pages ("5–6",
  en dash; one page: "5").
- Schedule "Page": the room page's number.
- Cover sentence "(page N)" / "on page N": first checks page.
- Checks "Package · Files" row: "· page P" = first package-record page.
- Multi-floor cover: "+{n} floors on pages {a}–{b}": first and last of the omitted floors' plan
  pages.

---

## 5. Pages

Each subsection: layout (absolute positions), strings verbatim (`{…}` = data, §6 says where from),
states, empty/error states. Header and footer per §3.3/§3.5.

### 5.1 Cover (1f Limited · 1g Ready · 1h Blocked · 1i 2 floors)

Kicker: `Spatial report`. Subline suffix: ` · address confirmed on site` /
` · address not confirmed on site` (from `captureRecord.address.confirmedOnSite`; no suffix when
there is no record).

#### 5.1.1 Plan area (8 columns): x 36–512, y 102–528

**One floor** (1f/1g/1h):
- Drawing fit box x 36–512, y 102–494 (476 × 392). The floor (§7.4: fills, objects, walls,
  windows, doors, passages, room labels; **no** dimension strings) is fitted with uniform scale,
  aligned top-left in the box (as drawn). Label rule: §7.4.4.
- North arrow block: 84 pt wide (x 428–512), arrow 32 pt centred in it, block bottom at y 506
  (22 pt above the content bottom).
- Bottom-left block x 36–416 (380 wide), bottom at y 528, column gap 5:
  - Row 1 (items aligned to the bottom, gap 14): scale bar (§3.9) + note Inter 7.5/9 `muted`
    (wraps in the remaining width): "Drawing fitted to the page. The scale bar is true for this
    print size. Doors are drawn without swing (not recorded)."
  - Row 2 (only when the visit has skipped rooms): Inter 7.5/9 `muted`, max 2 lines:
    "Not scanned: {entries joined with " · "}" (§6.7). If it does not fit 2 lines: as many entries
    as fit + " · and {k} more (see the room schedule)".
- The drawing must not overlap the north block or the bottom block: if its fitted box would, the
  scale is reduced until it does not (rectangle test against the block rectangles).

**Two or three floors** (1i):
- Floors side by side in capture-record order, gap 20 pt, one common scale: the largest scale
  where (sum of drawing widths + 20 × (n−1)) ≤ 476 and (label 9 + gap 6 + drawing height + 4 +
  arrow block height) ≤ 392.
- Each block (column, items left-aligned, gap 6): label = floor label uppercase, Inter-SB 7.5/9,
  tracking 1.2, `ink`; the drawing; the floor's own north arrow (26 pt, its own state and
  caption) centred under the drawing, 4 pt padding above.
- Room labels are drawn only when the common scale ≥ 31.8 pt per metre (0.5 pt per trace unit of
  the mock); otherwise no room labels.
- Scale bar in the bottom-left block for the common scale; no separate north block.
- **Four or more floors**: the three largest floors by floor area (ties: record order) as above,
  plus under the blocks, Inter 7.5/9 `muted`: `+{n} floors on pages {a}–{b}`.
- A floor whose model is absent/unreadable: its block shows the label and a placeholder box
  120 × 90 pt (fill `ground`, 0.75 `muted` dash 4/3 border) with centred Inter 7.5 `muted`
  "Plan not available" and the not-verified arrow box with reason "No scan model".

#### 5.1.2 Data column (4 columns): x 524–756, y 102–528, column gap 10

**Verdict block** (width 232; border 1.5 pt in the verdict colour; radius 6; padding 8 top,
11 sides, 9 bottom; inner gap 4):
- Kicker (tracking 1.2): `Station verdict · {Mon D, YYYY}` (evaluatedAt; uppercased).
- Row (gap 6, centred vertically): glyph 10 pt + word Inter-SB 12/14 in the text colour:
  `Ready` (#2E5E2E) / `Limited` (#7A5214) / `Blocked` (#8B2E2E).
- Sentence Inter 8.25/11 `ink` (wraps) — `coverSentence(verdict, checksPage)`:
  - ready: `Ready for {task}. All station checks passed (page {P}).`
  - limited: `Usable for {task}, with the limitations named on page {P}.`
  - blocked: `Not usable yet. {Count} {blocker is|blockers are} named on page {P}; the package must be re-sealed.`
  - `{task}` = `verdict.task` with its first letter lower-cased ("preliminary existing-condition
    plans"); `{Count}` = number of rules whose result is Blocked (§6.10), spelled "One"…"Nine",
    digits from 10; `{P}` = first checks page.
  - `outcomeInPlainWords(verdict, checksPage)` (exported) returns this sentence.

**Overview** (gap 4): heading Times 16.5/19 `Overview`; rows (justify between, gap 8, padding
3.75 top/bottom, bottom rule 0.75 `line`; label Inter 9/11 `muted`; value Inter 9/11 `ink`,
right-aligned, single line, "..."):

| Label | Value |
|---|---|
| `Bedrooms` | count (§6.3); row omitted when no room of the visit has a `type` (1.0.0 models) |
| `Bathrooms` | count; same rule |
| `Rooms scanned` | `{n} on 1 floor` · `{n1} + {n2} on 2 floors` · `{n1} + {n2} + {n3} on 3 floors` (rooms of readable models only; each floor without a readable model is left out of the sum and adds ` · {label}: plan not available`) |
| `Floor area, sum of rooms` | `{sq ft} sq ft` + muted ` · {m²} m²` (e.g. "807.5 sq ft · 75.0 m²") |
| `Wall area, excl. openings` | `{sq ft} sq ft` |
| `Window area` | `{sq ft} sq ft` |
| `Volume, flat ceilings` | `{cu ft} cu ft` + muted ` approx.` when any room's ceiling is approximate |
| `Perimeter, all rooms` | ft-in in Courier 9 (e.g. `388' 6.4"`) |

Note under rows, Inter 7.5/9.5 `muted`: "Bedrooms and bathrooms are counted from room labels and
recognized beds and toilets. Areas are scan estimates."

**Capture** (gap 4): heading `Capture`; rows as above:

| Label | Value |
|---|---|
| `Captured` | `{Mon D, YYYY} · {operator}` (visitedAt; operator `captureRecord.operator.name`); dates of captures spanning days: `{Mon D}–{Mon D, YYYY}` |
| `Device` | `{marketingName ?? model} · LiDAR` (`hasLidar` false → `· no LiDAR`) |
| `Mode` | `{mode labels joined ", "} · {k} capture(s)`; mode labels: room → `One room`, floor → `Whole floor`, exterior → `Exterior` (e.g. "Whole floor · 1 capture", "Whole floor · 2 captures") |
| `Package` | `revision {N} · sealed {Mon D, YYYY}` (manifest `sealedAt`) |
| `HUB deal` | `{dealId}` Courier 9 |

No capture record: `Captured` → `not recorded`, `Device` → `not recorded`, `Mode` from manifest
captures (`{k} capture(s)` only).

#### 5.1.3 States

| State | Difference |
|---|---|
| Ready (1g) | ready block |
| Limited (1f) | limited block |
| Blocked (1h) | blocked block; drawing unchanged |
| Orientation verified / approximate / not verified | north arrow state per floor (§6.9) |
| 2 floors (1i) | §5.1.1 multi-floor |
| No rooms in any readable model | plan area: centred Inter 9.75 `muted` "No rooms were recognized in this capture." |
| One floor, model absent or unreadable | plan area: the "Plan not available" box of §5.2.2 (same text), north box "Orientation: not verified" / "No scan model", no scale bar; Overview area rows show `not available` |
| No capture record | title `Address not recorded`, no subline suffix, Capture rows `not recorded` (§5.1.2) |

### 5.2 Floor plan + contents (1k Floor 1 · 1l Floor 2+)

Kicker: `Spatial report · Floor plan · {floor kicker}` — 1 floor: `{label}`; 2+ floors:
`{label} of {n}` when the label matches `^Floor \d+$`, else `{label} · {i} of {n}`.

#### 5.2.1 Left column (3 columns): x 36–207 (171), y 102–528, column gap 14

**First plan page** (when the contents fit, §5.2.3): heading `Contents` (Times 16.5/19), gap 4,
rows (padding 3 top/bottom, rule 0.75 `line`, justify between, gap 8): name Inter 9/11 `ink`
(single line, "..."), page Inter 9/11 `muted` (no shrink):
1. `Room schedule` · `{page}`
2. `Capture checks` · `{page}`
3. one row per room in report order: `{name}` or `{name} (unlabeled)` · `{range}`; with 2+
   floors a floor row precedes each floor's rooms: label uppercase Inter 7.5/9 tracking 1.2
   `muted`, no page, same row padding;
4. `Package record` · `{page}`.

Then (gap 4) Inter 7.5/9.5 `muted`: "Each room has a plan page followed by its site photos." —
when some room has no photos: "Each room has a plan page, followed by its site photos when there
are any."

**Other floor pages** (1l), and the first page when contents are on their own page: heading
`{floor label}` (Times 16.5/19), gap 6, Inter 9/12 `muted`: "One plan page per floor. The contents
list is on the first plan page only. Floors are drawn in their own scan frame: the station does
not align captures to each other." (With a separate contents page, the first plan page uses the
same text with "The contents list is on page {c}.")

**Legend** (pinned to the bottom of the column, gap 5; kicker `Legend` tracking 1.2; 7 items, each
a 24 × 8 pt sample + gap 8 + Inter 8.25/10 `ink`):

| Sample (24 × 8) | Text |
|---|---|
| rect (0, 1.5, 24 × 5) `ink` | `Wall, scanned` |
| two lines y 3 and 5, 0.6 `ink` | `Window` |
| rects (0,1.5,5×5) and (19,1.5,5×5) `ink` + line y 4 from 5 to 19, 0.5 `muted` | `Door, swing not recorded` |
| same, line dash 2 / 2 | `Open passage` |
| rect (4, 0.5, 16 × 7) `surface` fill, 0.6 `muted` | `Recognized object, box` |
| same, dash 1.8 / 1.2 | `Low-confidence object` |
| rects 8 × 8 at x 0, 8, 16: `nude`, `wet`, `ground` (last with 0.4 `line` stroke) | `Fills: habitable · wet · other` |

#### 5.2.2 Plan region (9 columns): x 219–756 (537), y 102–528

- Drawing anchored at (245, 118) (mock: left 26, top 16). Fit box for the walls' outer
  bounding box: x 245–732, y 118–494, after reserving 24 pt on every side for dimension strings
  (strings may reach x 221 and x 756).
- Content: §7.4 full (fills, objects, walls, openings, room labels) + **outer dimension strings**
  (§7.4.5).
- North + scale block: right-aligned at x 756, width 170 (x 586–756), bottom at y 502, column
  (items right-aligned, gap 8): north arrow 32 pt (§3.9) then the scale bar. If the drawing's
  ink (walls, fills, labels, dimension strings) would overlap this block, the scale is reduced (to
  no less than 85 % of the fitted scale) until it does not; past that, the block moves to the top
  right of the region (x 586–756, top y 102).
- Notes: x 219–619 (400), bottom at y 528, column gap 2, Inter 7.5/9 `muted`:
  - "Drawing fitted to the page; the scale bar is true for this print size. Dimensions are room
    bounding boxes from the scan."
  - "Not scanned: {this floor's entries}" (only when this floor has skipped rooms; §6.7, no floor
    names).
- Model absent/unreadable: region shows a centred box 300 × 80 pt (border 0.75 `line`, radius 4,
  padding 6 × 9) with Inter 8.25/10.5: "Plan not available: the scan model of {label} is missing
  from the package." / "…could not be read." + not-verified north box with reason "No scan model".
  Notes line 1 is omitted.
- Model with 0 rooms: centred Inter 9.75 `muted` "No rooms were recognized in this capture."

#### 5.2.3 Contents capacity

The left column holds heading (19) + gap 4 + rows (17.75 each) + gap 4 + note (9.5) + ≥ 9 gap +
legend (114) ≤ 426 → **15 rows**. Rows = 3 fixed + rooms (+ floor rows with 2+ floors). The 424
sample is exactly 15. More rows → a **Contents page** after the cover: kicker `Spatial report ·
Contents`, heading `Contents`, the same rows flowing in 3 columns of 232 pt (x 36, 280, 524), each
column up to 23 rows (y 125–528); more → a second contents page. The plan pages then use the
"other floor" left column text.

### 5.3 Room schedule (1n)

Kicker: `Spatial report · Room schedule`. Content x 36–756, column gap 6.

#### 5.3.1 Heading row (justify between, items aligned to the bottom, gap 12)

- `Room schedule` (Times 16.5/19).
- Right, Inter 9/11 `muted`: 1 floor `{label} · {n} rooms scanned · {k} not scanned · largest
  first` (omit "· {k} not scanned" when 0; "1 room scanned"); 2+ floors `{n} rooms scanned on {f}
  floors · {k} not scanned · largest first per floor`.

#### 5.3.2 Table

Columns (pt): 118 · 60 · 62 · 160 · 62 · 62 · 62 · 40 · 40, column gap 6 (714 ≤ 720).

Header row (padding bottom 4, bottom rule 0.75 `ink`, items aligned to the bottom; Inter
8.25/10 `muted`; numeric headers right-aligned): `Room` · `Floor area` / `sq ft` · `Wall area` /
`sq ft` · `Dimensions` / `(B) bounding box · (I) inscribed` · `Perimeter` · `Ceiling` / `height` ·
`Volume` / `cu ft` · `Items` · `Page` ("/" = line break).

Room row (padding 2.5 top/bottom, rule 0.75 `line`, items centred vertically):
1. name Inter-SB 9/11 (wraps, max 2 lines, "...") + tag line Inter 7.5/9 `muted` `unlabeled`
   (only for unlabeled rooms, §6.2)
2. floor area sq ft, 1 decimal, thousands separator, right
3. wall area **excl. openings** sq ft, right
4. Courier 9/11, no wrap: `(B) {long} × {short}`; second line `muted` `(I) {long} × {short}` only
   when the room is not a rectangle (§6.5)
5. perimeter ft-in, Courier, right
6. ceiling height ft-in, Courier, right, + ` approx.` Inter `muted` when approximate
7. volume cu ft, right, + ` approx.` `muted` when approximate
8. items count = objects + openings of the room, right
9. room page number, `muted`, right

Not-scanned rows, after each floor's rooms (columns 118 · 1fr · 40, gap 6, padding 2, rule
`line`, all `muted`): name Inter-SB 9/11 · `{status}{ · reason} · no measurements, not on the plan`
· `—` (right). Status `Not scanned` (omitted rooms) or `Could not enter` (inaccessible rooms).

2+ floors: before each floor's rooms a floor row (padding 7 top / 2 bottom, label uppercase Inter
7.5/9 tracking 1.2 `muted`); after its rooms and not-scanned rows a subtotal row styled like the
total row but with a `line` rule and label `{floor label}, scanned rooms`.

Total row (padding 5, bottom rule 0.75 `ink`, Inter-SB 9/11): `Total, scanned rooms` · floor area
· wall area · (Inter 9 regular `muted`) `{m²} m² · {m²} m²` (floor area m², wall area m²) ·
perimeter (Courier) · empty · volume · items · empty.

#### 5.3.3 Footnote (last schedule page only)

Inter 7.5/9.5 `muted`: "(B) bounding box · (I) inscribed rectangle, shown only when the room is not
a rectangle · approx.: part of the ceiling was not captured · wall area excludes openings · volume
assumes a flat ceiling."

#### 5.3.4 Pagination

Rows are packed while (heading + header + rows + [last page: total + footnote]) ≤ 426, at most 24
room rows per page; the header row is repeated on every page; continuation pages keep the kicker
and the heading row (heading `Room schedule (continued)`). A floor's not-scanned rows and subtotal
never start a page alone (keep with the previous room row).

#### 5.3.5 Empty states

- No readable model on any floor: single row spanning all columns, Inter 9 `muted`: "No rooms
  were measured: the scan models could not be read." Total row omitted.
- A floor without a readable model: its floor row + a row `Plan not available for {label}` in
  `muted`.

### 5.4 Capture checks (1p Limited · 1q Ready · 1r Blocked)

Kicker: `Spatial report · Capture checks`. Content column gap 8. Footer line 2 = Full B.

#### 5.4.1 Heading row (justify between, aligned to the bottom, gap 12)

- `Capture checks` (Times 16.5/19).
- Right (max width 590, right-aligned, max 2 lines), Inter 9/11 `muted`: `Checked by the Chapter
  station before this report was issued · rules {evaluator.name} {evaluator.version} · evaluated
  {Mon D, YYYY HH:mm}`.

#### 5.4.2 Verdict band (full width 720; border 1.5 verdict colour; radius 6; padding 9 × 12; gap 5)

- Top row (justify between, gap 16):
  - left column (gap 3): row glyph 11 pt + headline Inter-SB 12/14 in the text colour:
    - ready `Ready for {task}`
    - limited `Limited: usable with named limitations`
    - blocked `Blocked: missing information prevents the task`
    then `verdict.summary` Inter 9/11.5 `ink` (wraps; never truncated).
  - right column (no shrink, right-aligned, gap 2): `Task: {task}` Inter 9/11 `ink`; counts Inter
    9/11 `muted`: `{b} blocker(s) · {l} limitation(s) · {p} passed · {n} not applicable` — counts of
    **rules** by result (§6.10); plural "s" when ≠ 1.
- Statement Inter 7.5/9 `muted`: `verdict.statement` verbatim ("This verdict is an automated check
  of the intake package. It does not certify any property model or measurement.").

#### 5.4.3 Checks table (8 columns): x 36–512 (476)

Columns 100 · 82 · 160 · 116, gap 6. Header (padding bottom 4, rule 0.75 `ink`, Inter 8.25/10
`muted`): `Check` · `Result` · `What was found` · `Next action`.

One row per `verdict.checks[i]` in that order (padding 3, rule 0.75 `line`, items aligned to the
top):
1. `check.title` Inter 9/11 + `check.ruleId` Courier 7.5/9 `muted` (gap 1)
2. glyph 8 pt + result word Inter-SB 9/11 in the result colour (gap 4): `Passed` (#2E5E2E),
   `Limited` (#7A5214, glyph #9A6A1E), `Blocked` (#8B2E2E), `Not applicable` (#6B6557, dash)
3. one block per finding of that rule (verdict order: blocker, limitation, info; gap 3 between
   blocks):
   - `finding.message` Inter 8.25/10 `ink`
   - `Measured: {measured}` Inter 7.5/9 `muted` (when present)
   - `Expected: {expected}` Inter 7.5/9 `muted` (when present)
   - `{filePath}` Courier 7.5/9 `muted` (when present; wraps at "/" boundaries, then anywhere)
   No finding for the rule: passed `No findings.`; not applicable `Not applicable to this
   package.`; failed `No finding recorded.` (all Inter 8.25 `ink`).
4. per finding block (top-aligned with it): `finding.nextAction` Inter 8.25/10, `muted` when it is
   `None`, else `ink`. Rows without findings: `None` `muted`.

Footnote under the table (padding top 5), Inter 7.5/9.5 `muted`: "Every rule the station ran is
listed. Exports of one scan that agree with each other are not independent measurements."

Measured, expected and the file path are additions to the drawn row (the plan of changes asks for
"findings with measured / expected / next action"; F9 AC5 needs every finding's text).

#### 5.4.4 Right column (4 columns): x 524–756 (232), gap 10

Sections, each: kicker (tracking 1.2) + content gap 3.

1. `Limitations`: each `verdict.limitations[i]` Inter 8.25/10.5 `ink`; empty → `None.`
2. `Next actions`: each `verdict.nextActions[i]`; empty → `None.`
3. `Field controls recorded on site` — rows (justify between, gap 6, padding 3, rule `line`; label
   Inter 8.25/10 `muted`, value Inter 8.25/10 `ink` right):

   | Label | Value |
   |---|---|
   | `Long distances A, B ({methods})` (1 floor) / `A, B, {floor label} ({methods})` (one row per floor) | Courier 8.25: `{A} · {B}` ft-in of `valueMm`; a missing one is `none`; both missing → Inter `not recorded`. `{methods}` = `tape`, `laser` or `tape, laser` from the controls; none → `tape` |
   | `Ceiling heights` | `{n} rooms` / `1 room` / `none` (entries in `ceilingHeights`, all floors) |
   | `Openings` | `{n}` / `none` |
   | `Floor to floor · landmarks` | 1 floor: `none · one floor`; 2+: `{f} · {l}` (counts; 0 → `none`) |

   Then Inter 7.5/9.5 `muted`: "Tolerance: within 1% or 1 in (25.4 mm), whichever is larger."
   No field-controls file (or invalid): every value `not recorded`.
4. `Package` — rows as above:
   - 1 capture: `Capture id` · captureId Courier 8.25. 2+ captures: one stacked row per capture
     (label `Capture id, {floor label}` Inter 8.25 `muted` on the first line, the id in Courier
     7.5 on the second line).
   - `Package` · `revision {N} · sealed {Mon D, YYYY}`
   - `Files` · `{n} files · SHA-256 fingerprints · page {R}` (n = manifest entries; R = first
     package record page)

#### 5.4.5 Continuation pages `Capture checks (continued)`

- Same kicker, heading `Capture checks (continued)`, the same right text; no band.
- The table continues with its header repeated. A row splits between finding blocks, and inside a
  block between lines; the continued part repeats column 1 with ` (continued)` appended to the
  title in `muted`.
- The right column flows too: sections that did not fit continue on the next checks page with the
  kicker suffixed ` (continued)`. When the table ends before the lists, further checks pages hold
  only the right column.
- Typical verdicts (≤ 12 rules, ≤ 2 findings each) fit one page.

### 5.5 Room pages (1t living · 1w kitchen · 1x closet · 1y unlabeled approx · 1z long/27 items · 1aa continuation)

Kicker: 1 floor `Spatial report · Room {k} of {M}`; 2+ floors `Spatial report · {floor label} ·
Room {k} of {M}` (k = position in report order across the visit, M = rooms measured in the visit);
continuation pages append ` · continued`.

#### 5.5.1 Left column (5 columns): x 36–329 (293)

- Drawing box x 58–329, y 118–432 (271 × 314) (mock: left 22, top 16). The room is drawn in **its
  own frame** (rotated by −frameAngle so its dominant axis is horizontal), fitted uniformly
  (including 24 pt for dimension strings on each side used), top-left aligned. Content (§7.5):
  the room's walls (bands along its walled edges), its doors/windows/passages, its objects with
  symbols, the bounding box (dashed), the inscribed rectangle (dotted, only if not rectangular),
  item markers, dimension strings: bounding box `along` above the top (ink), `across` left of the
  left side (ink, rotated −90°), inscribed `along` below and `across` right (muted), only if not
  rectangular. No room fill. No scale bar (not to a stated scale).
- Bottom row (x 36–329, bottom at y 528, gap 12, aligned to the bottom):
  - Key plan (column, gap 3): the room's floor in key mode fitted into 60 × 48 pt (walls `ink`
    at least 0.5 pt, the room's polygon filled `ink`, other rooms unfilled, no objects/openings/
    labels), then `Key plan` Inter 7.5/9 `muted`. Floor model unavailable: dashed 60 × 48 box
    (0.75 `muted` dash 3/2, radius 3).
  - Legend (column, gap 3):
    1. 22 × 6 sample (line y 3, 0.75 `muted`, dash 3/2) + `Bounding box` (Inter 7.5/9 `ink`) +
       6 pt + sample (dash 0.6/2 round) + `Inscribed rectangle`
    2. marker glyphs 11 pt, each followed by Inter 7.5/9 `muted` and 4 pt: `Furniture` ● ·
       `Fixture` ▲ · `Appliance` ◆ · `Opening` ■ · `Other` ⬟ (wraps)
    3. Inter 7.5/9 `muted`: "Dashed outline = low-confidence object. Doors drawn without swing."

#### 5.5.2 Right column (7 columns): x 341–756 (415), y 102–528, column gap 8

1. Title block (gap 3): room name (Times 22.5/26, or 16.5/19 when > 40 characters, max 2 lines);
   continuation pages: `{name} (continued)`. Tag line Inter 9/11 `muted` (only unlabeled rooms):
   `Unlabeled room · numbered in scan order`.
2. Tiles (page 1 only): 4 equal columns, gap 6 (each 99.25 wide); tile padding 6 × 8, radius 4,
   fill `ground`, column gap 1: kicker Inter 7.5/9 tracking 1 `muted` · value Inter-SB 11.25/13
   `ink` single line (shrinks, §3.2) · metric line Inter 7.5/9 `muted`.

   | Kicker | Value | Metric line |
   |---|---|---|
   | `Floor area` | `{sq ft} sq ft` | `{m², 1 dp} m²` |
   | `Ceiling` | ft-in | `{m, 2 dp} m`, + ` · approx.` when approximate |
   | `Volume` | `{cu ft} cu ft` | `{m³, 1 dp} m³`, + ` · approx.` when approximate |
   | `Perimeter` | ft-in | `{m, 1 dp} m` |

3. Dimension line (page 1 only) Inter 8.25/10.5 `muted`:
   `Bounding box {long} × {short}` + (` · inscribed rectangle {long} × {short}` when not
   rectangular, else ` · rectangular room`) + walls part: when incl. ≠ excl. (to the printed
   value) ` · walls {incl} sq ft incl. openings, {excl} excl.`, else ` · walls {excl} sq ft excl.
   openings`.
4. Note box (when the room has no objects and no openings, or its ceiling is approximate):
   padding 6 × 9, border 0.75 `line`, radius 4, Inter 8.25/10.5 `ink`. Text = the applicable
   sentences joined by a space:
   - "No items or openings were recognized in this room."
   - "Part of the ceiling was not captured: the ceiling height and the volume are approximate."
5. Items table (when the room has objects or openings), §5.5.3.
6. Continuation note (pages with a continuation), Inter 8.25/10 `muted` (§5.5.6).
7. Footnote pinned to the bottom (margin-top auto), Inter 7.5/9.5 `muted`:
   - with a table: "Sizes are the recognized object's box, W × H × D. Boxes are reference geometry
     from the scan, not measured furniture. Numbers match the markers on the plan."
   - without: "Items are listed only when the scan recognizes them. An empty list means nothing was
     recognized, not that the room is empty."

#### 5.5.3 Items table

Columns 14 · 1fr · 62 · 62 · 70, column gap 8. Header (padding bottom 3, rule 0.75 `ink`, Inter
8.25/10 `muted`): empty · `Item` · `W` · `H` · `D`.

Groups in this order, only non-empty: Furniture (●), Fixtures (▲), Appliances (◆), Other (⬟),
Openings (■). Group row (padding 7 top / 2 bottom, aligned to the bottom): empty · kicker Inter
7.5/9 tracking 1.2 `muted` `{Group} · {n}` (uppercase) · empty · empty · for Openings `Area`
(Inter 7.5/9 `muted`, not uppercase in the mock: draw `Area`).

Item row (padding 2, rule 0.75 `line`, centred vertically): marker 11 pt with its number · name
Inter 9/11 + ` approx.` `muted` when `confidence: "low"` · W · H · D in Courier 9/11 no wrap.

- Objects: W = `sizeM[0]` (box x), H = `sizeM[1]` (box y, height), D = `sizeM[2]` (box z), ft-in.
- Openings: W = width, H = height, D column = area `{sq ft} sq ft`.

#### 5.5.4 Markers on the drawing

- Object marker at the footprint centre; opening marker at the opening's midpoint on the wall
  centreline. Number = the row number in its group.
- Overlap avoidance: markers are placed in table order; a marker whose centre is closer than
  12.5 pt to an already placed marker tries offsets (0, −13), (13, 0), (0, 13), (−13, 0) pt in that
  order and takes the first free one; else it stays.

#### 5.5.5 Variants (all from data)

| Artboard | Data situation | Result |
|---|---|---|
| 1t living | labeled, non-rectangular, 12 items incl. 2 openings | tiles, inscribed shown, table with 4 groups |
| 1w kitchen | rectangular | "· rectangular room", no inscribed rect/dims; fixture symbols (sink, stove) on the drawing |
| 1x closet | small, nothing recognized | note "No items or openings…", empty-list footnote, no table |
| 1y Room 4 | unlabeled, approximate ceiling, nothing recognized | tag "Unlabeled room · numbered in scan order", ` · approx.` on the ceiling and volume tiles, note with both sentences |
| 1z/1aa | name > 40 characters, 27 rows | title 16.5 (2 lines max), page 1 with 12 rows, continuation page(s) |

#### 5.5.6 Rows per page

Item rows (15.75 pt) and group rows (18 pt) are packed while the right column fits (title, tiles,
dimension line, note, header, rows, continuation note, footnote ≤ 426); page 1 holds at most 12
item rows, continuation pages at most 24 (group rows not counted). A group split across pages
repeats its group row on the next page as `{Group} · {n} · continued`. Continuation pages: same
left column (drawing, key plan, legend), title `(continued)`, no tiles, no dimension line, no
note. Continuation notes:
- every page except the last: `Continued on the next page: rows {first row of next page} to {total} of {total}.`
- last page of a split list: `End of item list. Rows {first row on this page} to {total} of {total}.`

### 5.6 Site photos (1u)

Kicker: `Spatial report · Room {k} of {M} · Site photos` (2+ floors with the floor label as in
§5.5), continuation ` · continued`. Content column gap 10.

#### 5.6.1 Heading row (justify between, aligned to the bottom, gap 12)

- Times 22.5/26: `{room name}` + ` · site photos` in `muted` (continuation: `{room name} · site
  photos (continued)`); single line, the name truncated with "..." so the title keeps ≥ 300 pt.
- Right, Inter 9/11 `muted`, right-aligned (max 2 lines): `{n} photos · taken {Month D, YYYY} by
  {operator} · reduced here, originals in the package` (n = the room's photo count; "1 photo";
  dates spanning days `taken {Month D} to {Month D, YYYY}`; no operator → omit " by …").

#### 5.6.2 Grid

5 columns of 134 pt, column gap 12.5 (x 36, 182.5, 329, 475.5, 622), 2 rows; each cell: image box
128 × 160 pt centred in the column (3 pt inset each side), then gap 4, caption line 1 Inter
8.25/10: `{i} · {Subject}` + ` · looking {N|E|S|W}` `muted`, caption line 2 Courier 7.5/9 `muted`:
`{HH:mm} · {file name}`. Row pitch 184 pt (160 + 24). Grid top = heading bottom + 10.

- `{i}`: photo number within the room, continuing across its photo pages (11, 12 …).
- `{Subject}`: opening → `Opening`, cabinetry → `Cabinetry`, ceiling → `Ceiling`, fixture →
  `Fixture`, equipment → `Equipment`, defect → `Defect`, general → `General`.
- `{file name}`: last path segment (e.g. `photo-0001.jpg`).

#### 5.6.3 Footnote (pinned to the bottom)

Inter 7.5/9.5 `muted`: "Up to 10 photos per page, in the order taken; more continue on the next
page. Labels are the operator's (room, direction, subject). Photos are cropped to 4:5 for this page
only."

#### 5.6.4 Order and paging

Photos of a room (§6.8) sorted by `takenAt`, then path; 10 per page. Rooms without photos have no
photo page. Photo pages follow the room's last table page.

#### 5.6.5 Photos that match no room

Per floor, photos whose room label matches no room of that floor's model (or the floor has no
readable model) get pages after the floor's last room: kicker `Spatial report · {floor label} ·
Other site photos`, title `{floor label} · other site photos`, same grid; the caption line 1 gets
the operator's room label: `{i} · {room label} · {Subject} · looking {dir}`. (Not drawn; §13 Q5.)

#### 5.6.6 Image processing (worker side, `sharp@0.35.5`)

- Decode, honour EXIF orientation (`.rotate()`), convert to sRGB, crop to 4:5 centred
  (`resize(356, 444, { fit: "cover", position: "centre" })` = 128 × 160 pt at 200 dpi), encode
  JPEG quality 80, 4:2:0, baseline (not progressive), **no metadata** (EXIF/GPS stripped: sharp's
  default without `withMetadata`). Embedded with `doc.image(buf, x, y, { width: 128, height: 160 })`.
- Undecodable photo: the image box is filled `nude` with centred Inter 9 `muted` "Photo could
  not be read"; captions unchanged.
- Size budget, decided before drawing (deterministic): estimate = Σ reduced photo bytes + 2 MiB.
  If > 40 MiB, re-reduce every photo to 267 × 333 px (150 dpi) quality 70; if still > 40 MiB, omit
  all photo pages and add to each room page's footnote: " Site photos are in the package (left out
  of this report: size limit)." The rendered PDF is then checked against 45 MiB; over → the publish
  fails as today (`HubError` conflict, message "The spatial report is larger than the HUB upload
  limit").
- Photos are read one at a time (sequential, `sharp.concurrency(1)`); only the reduced bytes are
  kept in memory.

### 5.7 Package record (new page type; not drawn — §13 Q1)

Needed because F9 AC2 and the F9 report test require every file with its SHA-256 and the station
link of every file not in the HUB, and the capture record, as extractable text. Built with the
system rules (12 columns, dense table type).

Kicker `Spatial report · Package record`; heading row: `Package record` (Times 16.5/19) + right
Inter 9/11 `muted` "Where each file of the package is, with its SHA-256 fingerprint". Column gap 8.

1. Kicker `Capture record`; key/value rows (key column 120 pt Inter 8.25/10 `muted`, value Inter
   8.25/10 `ink` wrapping; padding 3; rule `line`):
   `Address` · `address.formatted` (verbatim) · `Address confirmed on site` · `Yes, {Mon D, YYYY HH:mm}` / `No` ·
   `HUB project` · `{projectName} · deal {dealId}` (no name: `deal {dealId}`) · `Operator` · name ·
   `Device` · `{marketingName} ({model}) · {osName} {osVersion} · LiDAR {yes|no}` · `App` ·
   `Chapter Capture {version} (build {build})` · `Visited` · `{Mon D, YYYY HH:mm}` · `Visit id` ·
   Courier · `Package id` · Courier · `Verdict id` · Courier.
   No record: one row `Capture record` · `No capture record is stored for this package.`
2. Kicker `Captures`; table columns 100 · 60 · 190 · 120 · 226 (gap 6): `Floor or area` (label +
   `areaKey` Courier 7.5 muted) · `Mode` (mode label) · `Capture id` (Courier 7.5) · `Captured`
   (`{Mon D, YYYY HH:mm}`, + `to {HH:mm}` when `finishedAt`) · `Notes` (`Coverage: {notes}`;
   `Omitted: {name (reason); …}`; `Inaccessible: {…}`; none → `None`).
3. Kicker `Files`; paragraph Inter 7.5/9.5 `muted` (verbatim from today's report): "Files up to
   {45.0 MiB (47185920 bytes)} of the roles the HUB receives are in the HUB folders below. Every
   other file stays in the station's immutable storage and opens through its station link after
   Entra sign-in. There are no public links." then `This report: {folder}/{name}`.
   Table columns 260 · 170 · 278 (gap 6), header Inter 8.25 `muted` `File` · `SHA-256` · `Where`;
   rows (padding 3, rule `line`, top-aligned):
   - File: path Inter 8.25/10 (wraps at "/") + `{role}, {size}` Inter 7.5/9 `muted` (size =
     today's `formatBytes`, e.g. `1.2 MiB (1258291 bytes)`).
   - SHA-256: Courier 7.5/9, 2 lines of 32 characters.
   - Where: `In the HUB: {folder}/{name}` or `Not uploaded (over {45.0 MiB (47185920 bytes)}).
     Station link, Entra sign-in required: {url}` / `Kept in the station. Station link, Entra
     sign-in required: {url}` (Inter 8.25/10; the URL is a link annotation).
   Order: manifest first, then package path order (the publication plan's order).
4. Header row repeated on continuation pages (`Package record (continued)`).

### 5.8 Black-and-white proof (1ac)

Not a page. Requirement: the cover (Limited), checks (Blocked), a room page and the schedule
printed in greyscale stay readable: verdict word + shape present, the three fills distinguishable,
bounding box (dash 3/2) and inscribed (dot 0.6/2) distinguishable, nothing coloured red except the
■ Blocked glyph/word/border. Tested by §11.3.

---

## 6. Data: sources, derivations, what is not available

### 6.1 Title line and address line

From `captureRecord.address.formatted` (single line from the HUB):
- split on `", "`; with ≥ 3 parts: title = all parts but the last two (`424 West End Ave, Apt
  4K`), address line = the last two (`New York, NY 10024`); with < 3 parts: title = the whole
  string, address line = empty (subline shows only the cover suffix).
- No capture record: title `Address not recorded`, address line empty.
- The full address appears verbatim in the package record (§5.7).

### 6.2 Rooms and unlabeled rooms

- Floors = `captureRecord.captures` in record order (no record: distinct manifest captures, label
  = areaKey, mode unknown).
- Per floor the model is the capture's `capture_model` file (validated with the contract
  `validateCaptureModel`, schemaVersion 1.0.0 or 1.1.0). `absent` / `unreadable` / `ok`.
- Room name = `room.label` (the operator's rename is already applied on the phone; `room-names.json`
  is app-private and never in the package).
- **Unlabeled** ⇔ label matches `^Room \d+$` and (`type` absent or `type == "other"`) and
  `typeSource != "operator"`. Shown with the muted "unlabeled" tag / "(unlabeled)" / "Unlabeled
  room · numbered in scan order". The number is the scan-order position the phone gave it.
- Schedule/report order per floor: floor area descending; ties by model order.

### 6.3 Bedrooms, bathrooms

`type == "bedroom"` / `type == "bathroom"` counted over every room of every readable model
(PlanTotals rule; `type` comes from the RoomPlan section, the room's objects, or the operator's
name — matching the note "counted from room labels and recognized beds and toilets"). If no room in
the visit has a `type` (all models 1.0.0), both rows are omitted.

### 6.4 Measurements (TS port, identical to PlanExport)

Port, line for line, into `station/hub/src/report/metrics/`:
- `plan-geometry.ts` ← `PlanGeometry.swift` (plan point = (x, −z); wall dedup within 0.002 m;
  opening spans along their wall; opening room attach within 0.15 m; object footprints from
  centre/size/quaternion; room label points).
- `metrics-geometry.ts` ← `MetricsGeometry.swift` (dominant angle in (−45°, 45°], frame, bounds,
  `largestInscribedRectangle` exact slab search ≤ 64 corners, 0.01 m raster above).
- `room-metrics.ts` ← `RoomMetrics.swift` (floor area, perimeter, bounding box B, inscribed I,
  walled spans: wall within 0.10 m and 5°, ceiling = length-weighted median wall height, approx.
  when off-height walls > 10 % of walled length (spread > 0.05 m) or walled length < 50 % of the
  perimeter or no walls; volume = area × ceiling; wall area incl./excl.; openings on walled edges
  in model order doors, windows, openings; objects of the room).
- `plan-totals.ts` ← `PlanTotals.swift` (bedrooms, bathrooms, livable = Σ floor area, wall area =
  Σ excl., window area = Σ windows once, volume = Σ, approx. if any, perimeter = Σ). The exterior
  area estimate is **not** ported (not shown).
- `units.ts` ← `UnitFormatter.swift` rounding (`steps`: half away from zero with a 1e-6 step tie
  tolerance; feet-inches rounded as a whole before splitting: 11.96 in → `1' 0.0"`).
- Casing lengths are not ported (dropped).

Conversions: sq ft = m² / 0.09290304; cu ft = m³ / 0.028316846592; inches = m / 0.0254.

Formats (`format.ts`):
- length: `{feet}' {inches}.{tenths}"` (e.g. `19' 4.3"`, `0' 3.1"`), negative never occurs.
- area/volume: 1 decimal, thousands separators (`2,196.3`), via the ported `decimals()` then
  grouping — never `Intl.NumberFormat` (different tie rule).
- metric: m² 1 dp, m 2 dp (ceiling), m 1 dp (perimeter), m³ 1 dp.
- dimension pair: larger side first, ` × ` between (`19' 4.3" × 11' 7.8"`).

### 6.5 Rectangular rooms

A room is rectangular when its printed B and I strings are identical (both sides equal to 0.1 in).
Then: no (I) line in the schedule, "· rectangular room" in the dimension line, no inscribed
rectangle or inscribed dimensions on the drawing.

### 6.6 Items

From RoomMetrics objects and openings of the room.

| Category | Group | Name |
|---|---|---|
| bed, chair, sofa, table | Furniture | Bed, Chair, Sofa, Table |
| bathtub, sink, toilet, storage, fireplace, stairs | Fixtures | Bathtub, Sink, Toilet, Storage, Fireplace, Stairs |
| dishwasher, oven, refrigerator, stove, television, washer_dryer | Appliances | Dishwasher, Oven, Refrigerator, Stove, TV, Washer/dryer |
| other | Other | Other |
| doors / windows / openings | Openings | Door, Window, Passage |

`attributes` (StorageType, TableType, …) are ignored (decision 3). Low confidence: object or
opening `confidence: "low"` → dashed box on the drawing, " approx." in the table.

### 6.7 Skipped rooms

From `captureRecord.captures[i].omittedRooms` (status "Not scanned") and `inaccessibleRooms`
(status "Could not enter"). Note entries (cover, plan page):
- omitted with reason `{name} ({reason})`, without `{name}`
- inaccessible with reason `{name} (could not enter: {reason})`, without `{name} (could not enter)`
- cover with 2+ floors: `{name} ({floor label}, {reason or "could not enter…"})`.
They are never drawn (no geometry).

### 6.8 Photos

Manifest entries with role `photo` (labels `photo.room`, `direction`, `subject`, `takenAt`),
grouped by `captureId`. Room match: `normalize(photo.room) == normalize(room.label)` with
`normalize = s.normalize("NFKC").toLowerCase().replace(/\s+/g, " ").trim()` (the station coverage
check's rule). Not available: sub-subjects ("Opening, window"), "looking up".

### 6.9 Compass and the north arrow

Source: the capture-record compass fields added by `north-arrow`/`phone-capture` (the north-arrow
artboard: heading of the scan's −Z axis from true north at scan start, 0–360; headingAccuracy in
degrees; headingSource `true`/`magnetic`; recordedAt; missing = state 3). This spec reads them
through one adapter `compassOf(capture)` (`station/hub/src/report/compass.ts`) that accepts the
final field names chosen by those areas; until the contract has them, every floor is state 3.

| State | Rule (thresholds confirmed Oct 20: ±10° / ±30°) |
|---|---|
| verified | source `true` and 0 ≤ accuracy ≤ 10 |
| approximate | (source `true` and 10 < accuracy ≤ 30) or (source `magnetic` and 0 ≤ accuracy ≤ 30) |
| not verified | no reading; accuracy < 0 (invalid) or > 30; reading marked rejected; model unavailable |

Not-verified caption: no reading → `No compass reading`; accuracy > 30 → `Accuracy ±{acc}°`;
rejected → `Reading rejected`; no model → `No scan model`. `{acc}`, `{hdg}` rounded to whole
degrees (`hdg` 0–359).

Arrow angle (clockwise, degrees, applied to the 32-unit box about (16, 16)): `θ = a − H`, where H
= heading and a = the clockwise rotation applied to the drawing to align the floor's walls with
the page (= the floor's dominant angle in degrees, §7.4.1). Check: H = 90 (−Z points east), a = 0
→ θ = −90: the arrow points left (north is left of page-up). If §13 Q2 is answered "never rotate",
a = 0.

### 6.10 Rule results

`result(check)`: `passed` → Passed; `not_applicable` → Not applicable; `failed` → Blocked when any
finding with that `ruleId` has severity `blocker`, else Limited. Counts and the cover's blocker
count use these rule results. Shared with the web (§8.5).

### 6.11 Not available (and what shows)

| Item | Shown |
|---|---|
| Door swing | doors drawn without leaf/swing; legend "Door, swing not recorded"; cover note |
| Ceiling changes | not drawn |
| Casing lengths | not shown |
| Item sub-types | category names |
| Wall thickness (RoomPlan reports 0) | assumed 4.5 / 6 in bands (§3.7) |
| Floor-to-floor alignment | floors in their own frames; floor-page text says so |
| Gross / exterior area | not shown |
| Bedrooms/bathrooms for 1.0.0 models | rows omitted |
| Compass (until shipped) | "Orientation: not verified" / "No compass reading" |
| Photo "looking up", sub-subjects | N/E/S/W, subject names |
| Operator / device / dates without a record | "not recorded", footer omits "captured" |
| Time zone of the property | dates and times in `REPORT_TIME_ZONE` (default America/New_York, §13 Q4) |

---

## 7. Code mapping

### 7.1 Module layout (`station/hub/src/report/`, all new)

| File | Content |
|---|---|
| `index.ts` | `renderSpatialReport(input): Promise<RenderedReport>`, `outcomeInPlainWords`, `coverSentence`, constants |
| `input.ts` | `SpatialReportInput`, `ReportFloorSource`, `ReportPhoto`, `RenderedReport`, defaults |
| `sources.ts` | `loadReportSources(request, plan, options)`: reads capture models, field controls, photos through `request.readFile`, validates, reduces photos |
| `photos.ts` | `reducePhoto(bytes, quality)` (sharp), budget chain |
| `compass.ts` | `compassOf`, `compassState`, `arrowAngle` |
| `model.ts` | `buildReportModel` (pure) |
| `words.ts` | every fixed string of §5 (verbatim), statements |
| `format.ts` | `pdfSafeText` (moved unchanged from `report.ts`), units, dates (`Intl.DateTimeFormat("en-US", { timeZone })`), plurals, number words, `formatBytes` (moved unchanged) |
| `tokens.ts` | colours, type scale, line weights, grid |
| `fonts.ts` | registers `Inter`, `Inter-SB` from `brand-assets.generated.ts` |
| `brand-assets.generated.ts` | generated: Inter Regular/SemiBold TTF (base64), logo path strings, source SHA-256s |
| `metrics/*.ts` | §6.4 port |
| `layout/text.ts` | `textBlock` (wrap, half-leading, max lines, ellipsis, tracking), `measure` |
| `layout/table.ts` | grid rows with padding/rules, row splitting |
| `layout/page.ts` | page background, header, logo, footer, QR |
| `layout/paginate.ts` | §4 |
| `draw/floor.ts` | §7.4 |
| `draw/room.ts` | §7.5 |
| `draw/key-plan.ts`, `draw/north-arrow.ts`, `draw/scale-bar.ts`, `draw/glyphs.ts`, `draw/markers.ts`, `draw/symbols.ts`, `draw/dimensions.ts`, `draw/qr.ts`, `draw/logo.ts` | §3.6–3.9 |
| `pages/cover.ts`, `pages/contents.ts`, `pages/plan.ts`, `pages/schedule.ts`, `pages/checks.ts`, `pages/room.ts`, `pages/photos.ts`, `pages/record.ts` | §5 |

### 7.2 Changed files

| File | Change |
|---|---|
| `station/hub/src/report.ts` | **Replaced** by a 10-line re-export of `./report/index.js` (keeps import paths). `ReportWriter`, `OUTCOME_LABEL`, the v1 `renderVerdictReport` body are removed. |
| `station/hub/src/index.ts` | export `renderSpatialReport`, `RenderedReport`, `SpatialReportInput`, `REPORT_STATEMENT_*`, `coverSentence`, `loadReportSources`; keep `REPORT_NOT_CERTIFICATION`, `REPORT_TITLE`, `outcomeInPlainWords`, `pdfSafeText`, `ReportFile`, `ReportFileLocation`, `ReportInput` (= alias of `SpatialReportInput`); `renderVerdictReport` kept one release as a deprecated alias returning `Buffer` |
| `station/hub/src/plan.ts` | `reportName(verdictId)` → `spatial-report-${verdictId}.pdf`; header comment. (`HUB_UPLOAD_ROLES` minus `spatial_report_pdf`: phone-package §11, same PR or earlier.) |
| `station/hub/src/publisher.ts` | before uploads: `plan = planPublication(…)`; `sources = await loadReportSources(request, plan, opts)`; `rendered = await renderSpatialReport(…)`; `await options.onReportRendered?.(rendered)` (a throw is a store failure: rethrown, job retried); recorded role `spatial_report` (was `verdict_report`); error text "The spatial report is larger than the HUB upload limit". New options `reportTimeZone?: string` (default `America/New_York`), `onReportRendered?`. |
| `station/hub/src/store.ts` | doc: role `"manifest"`, `"spatial_report"` (older rows `"verdict_report"`) |
| `PublishPackage` / `PackageFileRecord` (`plan.ts`) | add `sealedAt?: string`, `manifestFileCount?: number`; file `photo?: { room; direction; subject; takenAt }` |
| `station/hub/package.json` | deps `sharp@0.35.5`, `qrcode@1.5.4`; devDeps `@types/qrcode@1.5.5`, `pixelmatch@7.1.0`, `pngjs@7.0.0`, `jsqr@1.4.0`, `wawoff2@2.0.1`; `files` unchanged (assets are generated TS); script `brand-assets` |
| `station/hub/scripts/generate-brand-assets.mjs` (new) | reads `web/public/brand/inter-400.woff2`, `inter-600.woff2` (WOFF2 → TTF with `wawoff2`), `chapter-logo.svg` (path `d` strings); writes `src/report/brand-assets.generated.ts` with the inputs' SHA-256 |
| `station/hub/THIRD_PARTY_NOTICES.md` (new) | Inter, SIL OFL 1.1 (as `web/public/brand/NOTICE.md`); the logo is a Chapter trademark |
| `station/worker/src/publish-job.ts` | pass `sealedAt` (`pkg.manifest.sealedAt`), `manifestFileCount`, photo labels from `pkg.manifest.files[].photo`; `reportTimeZone: ctx.reportTimeZone`; `onReportRendered` → write blob + upsert `spatial_reports` (§8.2) |
| `station/worker/src/config.ts` | `STORAGE_REPORTS_CONTAINER` [reports], `REPORT_TIME_ZONE` [America/New_York] (validated with `Intl.supportedValuesOf("timeZone")`) |
| `station/worker/src/storage.ts` | `createReportsWriter(config)`: `upload(blobName, bytes, { contentType: "application/pdf", ifNoneMatch: "*" })`; an existing blob with the same SHA-256 is success (idempotent); a different one → overwrite is refused, error |
| `station/worker/Dockerfile` | no layout change; build stage adds `RUN node -e "require('sharp')"` smoke check (sharp's linux-x64 optional packages are in `package-lock.json`) |
| `station/db/migrations/0010_spatial-reports.sql` (new; 0009 is phone-package's carry-over) | §8.2 |
| `station/api/src/routes/packages/spatial-report.ts` (new), `index.ts`, `store.ts` | §8.3 |
| `contract/openapi/station.yaml` | §8.3 (in the OpenAPI 1.1.0 bump coordinated by phone-package) |
| `contract/ts/src/verdict-words.ts` (new) + `index.ts` export | §8.5 |
| `infra/modules/storage.bicep` | container `reports` (versioning on, no immutability policy) |
| `infra/modules/roles.bicep` | worker: Storage Blob Data Contributor scoped to container `reports` (API already has account-wide contributor + delegator) |
| `.github/workflows/ci.yml` | install `poppler-utils` (pdftoppm) in the Node job |
| `docs/waves/specs/F9.md` | AC5 text "spatial report"; files list "spatial report PDF (station)"; F9.2 "Build the spatial report PDF generator (spatial-report spec)" |
| `ios/Packages/PlanExport/Tests/PlanExportTests/ReportParityGoldenTests.swift` (new) | §11.2 |
| `fixtures/report-parity/*.json` (new) | goldens |
| `fixtures/report/424-west-end/` (new) | design-fidelity capture model transcribed from the 424 trace (12 rooms, walls, 2 windows, 12 thresholds, 14 objects; 19.4 trace units per ft, plan y = −z) + capture record + verdicts (limited/ready/blocked) + 7 photos for the living room |

Removed: the v1 report layout (`ReportWriter` class, "Outcome: LIMITED" wording).

### 7.3 Text helper (`layout/text.ts`)

`textBlock(doc, { text, font, size, lineHeight, width, align, color, tracking, maxLines,
ellipsis, x, y }) → { height, lines }`: greedy word wrap with `widthOfString`; a word longer than
the width breaks at "/" then anywhere; draws each line with half-leading (§3.2); returns the used
height. `measureBlock` = same without drawing (pagination).

### 7.4 Floor drawing (`draw/floor.ts`)

1. **Frame**: plan coordinates (x, −z) rotated clockwise by the floor's dominant angle a
   (`dominantAngle` over all room polygons) so walls run along the page axes (§13 Q2); then
   y flipped for pdfkit.
2. **Fit**: uniform scale s (pt per metre) = min(box width / extent x, box height / extent y)
   over the walls' outer bounding box (bands included) plus reserved margins.
3. **Fills** (`fillOf(room, mode)`): capture mode `exterior` → outdoor style; else by `type`:
   living_room, dining_room, bedroom, office → `nude`; kitchen, bathroom, laundry → `wet`; closet,
   hallway, utility, other → `ground`; no type → objects: toilet, bathtub, sink, stove,
   washer_dryer inside → `wet`; bed → `nude`; else label words (case-insensitive whole words):
   bedroom, living, dining, office → `nude`; bath, bathroom, kitchen, laundry, wc → `wet`; else
   `ground`.
4. **Labels**: name Inter-SB 7.5 `ink` and area Inter 7.5 `muted` (`{sq ft} sq ft`) centred on the
   room's label point; drawn only if the two-line block (with 2 pt padding) fits inside the room's
   inscribed rectangle (rotated into the floor frame); else the area line is dropped; if the name
   alone does not fit, no label (the room is still in the schedule and has its own page).
5. **Outer dimension strings** (floor plan page only): per side (top, bottom, left, right) of the
   floor's outer wall bounding box, rooms whose axis-aligned box edge lies within (max band
   thickness + 0.30 m) of that side and whose own frame is within 3° of the floor frame get a
   string spanning the room's box edge along that side, 12 pt outside the outer wall face; text =
   that room's bounding-box side (`along` for top/bottom, `across` for left/right) ft-in, Courier
   7.5 `ink`, 2.5 pt above (top), below (bottom, baseline at +2.5 + size), left/right rotated −90°
   (reads bottom to top; right side text right of the line). Strings on one side are placed left to
   right / top to bottom; a string is skipped when its text + 4 pt is longer than its line or it
   overlaps the previous kept string on that side (±2 pt).

### 7.5 Room drawing (`draw/room.ts`)

Room frame = RoomMetrics frame (rotated so `along` is horizontal). Walls: the capture's walls
whose centreline lies within 0.10 m and 5° of the room's outline edges (RoomMetrics walled-span
rule), drawn as bands clipped to the walled spans. Openings: RoomMetrics openings. Objects: the
room's objects with symbols. B rect (dash 3/2) and I rect (dot), markers (§5.5.4), dimension
strings (§5.5.1). Fit into 271 × 314 including the dimension margins actually used.

### 7.6 Legacy packages

Packages sealed by older apps contain `spatial-report.pdf` (role `spatial_report_pdf`). The report
treats it as any other file: listed in the package record with its station link (`Kept in the
station…`), never uploaded (phone-package §11), not mentioned elsewhere.

---

## 8. Contract, storage and API

### 8.1 Schemas

No change to the JSON schemas from this area. It reads: verdict 1.0.0, capture model 1.0.0/1.1.0,
capture record (+ compass fields when `north-arrow`/`phone-capture` add them), field controls
1.0.0, manifest 1.0.0/1.1.0 (phone-package). The `spatial_report_pdf` role stays in the enum
(phone-package §10.1).

### 8.2 Database: `station/db/migrations/0010_spatial-reports.sql`

```sql
-- Up Migration
-- The station's spatial report of each package's current verdict (the PDF itself is in the
-- `reports` blob container). One row per package; a new verdict replaces the row, older blobs stay.
CREATE TABLE spatial_reports (
  package_id   uuid PRIMARY KEY REFERENCES packages (package_id),
  verdict_id   uuid NOT NULL,
  file_name    text NOT NULL CHECK (file_name ~ '^spatial-report-[0-9a-f-]{36}\.pdf$'),
  blob_name    text NOT NULL,
  sha256       text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  bytes        bigint NOT NULL CHECK (bytes > 0),
  pages        integer NOT NULL CHECK (pages >= 1),
  generated_at timestamptz NOT NULL,            -- = verdict evaluatedAt
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER spatial_reports_set_updated_at BEFORE UPDATE ON spatial_reports
  FOR EACH ROW EXECUTE FUNCTION station_set_updated_at();
COMMENT ON TABLE spatial_reports IS 'Spatial report PDF of each package''s current verdict.';
```

Worker `onReportRendered`: write blob `{packageId}/spatial-report-{verdictId}.pdf` to `reports`,
then `INSERT … ON CONFLICT (package_id) DO UPDATE` (verdict_id, file_name, blob_name, sha256, bytes,
pages, generated_at); audit `report.store` {verdictId, sha256, bytes, pages}.

### 8.3 API: `GET /packages/{packageId}/spatial-report` (OpenAPI 1.1.0)

```yaml
/packages/{packageId}/spatial-report:
  parameters: [{ $ref: "#/components/parameters/PackageId" }]
  get:
    tags: [verdicts]
    operationId: getSpatialReportLink
    summary: Get a short-lived read-only link to the station's spatial report
    description: |
      The spatial report PDF of the package's current verdict, made by the station after its
      checks. Read-only SAS link valid for 10 minutes; every link handed out is audited (the URL
      never is). 404 with code `report_not_ready` while there is no report for the current verdict.
    x-roles: [bim, admin]
    responses:
      "200": { description: The link., content: { application/json: { schema: { $ref: "#/components/schemas/SpatialReportLink" } } } }
      "401": { $ref: "#/components/responses/Unauthorized" }
      "403": { $ref: "#/components/responses/Forbidden" }
      "404": { $ref: "#/components/responses/NotFound" }
SpatialReportLink:
  type: object
  additionalProperties: false
  required: [verdictId, name, sha256, bytes, pages, generatedAt, url, expiresAt]
  properties:
    verdictId: { $ref: "#/components/schemas/Uuid" }
    name: { type: string, pattern: "^spatial-report-[0-9a-f-]{36}\\.pdf$" }
    sha256: { $ref: "#/components/schemas/Sha256" }
    bytes: { type: integer, format: int64, minimum: 1 }
    pages: { type: integer, minimum: 1 }
    generatedAt: { $ref: "#/components/schemas/DateTime" }
    url: { type: string, format: uri }
    expiresAt: { $ref: "#/components/schemas/DateTime" }
```

Implementation reuses `download.ts` signing (user delegation key; Azurite account key), container
from API config `STORAGE_REPORTS_CONTAINER` [reports]. `report_not_ready` when no row, or the row's
`verdict_id` ≠ the current verdict. Audit `report.download_link` {packageId, verdictId}.

### 8.4 Web consumers (`web-review`)

- Download button "Spatial report PDF" → this endpoint; size/pages from the response
  ("28 pages · 3.2 MB" in the web artboard).
- "same table as page {n} of the spatial report": add `checksPage` to the response? Not drawn as a
  requirement in this area; the web can omit the page reference or this area adds
  `checksPage: integer` to `SpatialReportLink` and the row (recommended: add it; one column
  `checks_page integer NOT NULL`).

### 8.5 Shared verdict words (`contract/ts/src/verdict-words.ts`)

```ts
export const RESULT_WORD = { passed: "Passed", limited: "Limited", blocked: "Blocked", not_applicable: "Not applicable" } as const;
export const OUTCOME_WORD = { ready: "Ready", limited: "Limited", blocked: "Blocked" } as const;
export function ruleResult(check: CheckResult, findings: readonly Finding[]): keyof typeof RESULT_WORD;
export function outcomeHeadline(verdict: Verdict): string;      // §5.4.2 headlines
export function ruleCountsLine(verdict: Verdict): string;       // "{b} blockers · {l} limitations · {p} passed · {n} not applicable"
export function lowerFirst(text: string): string;
```

The report and the web import these, so the checks wording is identical in both.

---

## 9. Implementation order

1. Brand assets generator + fonts/logo/QR/glyph primitives; text helper; page frame (header,
   footer) — snapshot a blank page.
2. Metrics port + Swift goldens (§11.2) green.
3. Model + pagination (pure, unit-tested).
4. Pages: checks, package record (F9 tests green first), cover, schedule, plan, room, photos.
5. Sources loader + photo reduction; publisher integration; F9 tests updated (§10).
6. Storage, migration, API, worker; e2e.
7. Visual snapshots reviewed against the artboards; B&W proof.

---

## 10. F9 tests that must keep passing

AC text (F9) is unchanged except "verdict report" → "spatial report" in AC5. Assertions:

### 10.1 `station/hub/test/report.test.ts` (AC5)

| Line | Today | v2 |
|---|---|---|
| render helper | `renderVerdictReport` → Buffer | `renderSpatialReport` → `RenderedReport`; helper returns `{ text, bytes: r.bytes, checksPage: r.checksPage }`; inputs as today (`floors` defaults from the capture record: models absent, no photos) |
| 60 | `%PDF-` | unchanged |
| 62 | `Outcome:LIMITED` | `squash("Limited: usable with named limitations")` and `STATIONVERDICT` |
| 63 | `outcomeInPlainWords(verdict)` | `outcomeInPlainWords(verdict, checksPage)` |
| 64–74 | summary, every finding (message, ruleId, nextAction, measured, expected, filePath), limitations, nextActions, statement | unchanged — §5.4 prints all of them |
| 75 | `REPORT_NOT_CERTIFICATION` | unchanged (value = Full A) |
| 76 | `text.includes("not a certification of measurements")` | `text.includes("not a certification of any property model or measurement")` (short footer, one line) |
| test 2 | `Outcome:BLOCKED`, 60 findings across pages, `<=` | headline `Blocked: missing information prevents the task`; findings ✓ (continuation pages); `<=` ✓ (`pdfSafeText` kept) |
| test 3 | `Outcome:READY`, `No findings.` | `squash("Ready for preliminary existing-condition plans")`; `Nofindings.` ✓ (passed rules without findings) |
| test 4 | full address, `TestOperator`, every captureId, every file path + SHA-256 | unchanged ✓ (package record, cover, checks Package rows) |
| test 5 | byte-identical | unchanged ✓ |

### 10.2 Other F9 tests

| Test | Change |
|---|---|
| `publish.test.ts` (AC1) | with phone-package's helper change (no `spatial-report.pdf` in new packages): 12 → 10 documents/uploads/recorded uploads; report name `spatial-report-{verdictId}.pdf`; "Only the plan files were read" → reads = 8 plan files + 3 report sources (2 photos, 1 field controls) = 11; new test: legacy package with `spatial_report_pdf` → linked `not_published`, not uploaded |
| `large-files.test.ts` (AC2) | `startsWith("verdict-report-")` → `"spatial-report-"` (2×); link, path, SHA-256, `Not uploaded (over 45.0 MiB`, `Entra sign-in required` ✓ (package record) |
| `idempotency.test.ts` (AC3) | name pattern `spatial-report-` |
| `failure.test.ts` (AC4) | unchanged |
| `station/worker/test/e2e/pipeline.e2e.ts` (AC6) | `UPLOAD_ROLES` without `spatial_report_pdf`; `verdict-report-` → `spatial-report-` (4×); add: `spatial_reports` row exists, blob in Azurite has the HUB document's SHA-256, re-run keeps one row per package |
| `mapping-drift.test.ts`, `live.test.ts` | unchanged |

---

## 11. Test plan

### 11.1 Unit (`node --import tsx --test`, `station/hub/test/report/*.test.ts`)

- `format.test.ts`: `11.96 in` → `1' 0.0"`; ties (0.05 in → `0' 0.1"`); `2196.25` → `2,196.3`;
  sq ft/cu ft conversions; m²/m/m³ decimals; long/short/date-time formats in America/New_York and
  UTC (a 23:30 EDT visit prints its local date); plurals; number words 1–9, 10; `pdfSafeText`
  table (unchanged).
- `metrics-parity.test.ts`: §11.2 goldens.
- `model.test.ts`: unlabeled rule (Room 3 untyped ✓; Room 3 typed operator ✗; "Room Mexico" ✗);
  fills (type, objects, label words, exterior); bedrooms/bathrooms (1.0.0 → rows omitted); sort
  order; skipped-room note strings (4 combinations, 2 floors); rule results and counts; cover
  sentences (ready, limited, blocked with 1/2/12 blockers); compass states at 0, 10, 10.01, 30,
  30.01, −1, magnetic 5, magnetic 31, missing, rejected; arrow angle (H 90, a 0 → −90; H 0, a 12
  → 12); rectangular detection.
- `paginate.test.ts`: 424 sample → page list `[cover, plan, schedule, checks, (room, photos)×12,
  record…]`; 13 rooms + 2 floors → contents page; 27 items → 12 + 15 rows, notes "rows 13 to 27 of
  27"; 50 items → 3 pages; 23 photos → 3 photo pages, numbering 1–23; 60 findings → 3+ checks
  pages, lists continue; schedule with 30 rooms of 28.75 pt rows → measured split; page numbers
  in contents/schedule/cover consistent.
- `text.test.ts`: half-leading top for Inter 9/11 and Times 21/24; wrap, "/" breaking, maxLines +
  "...", tracking width.
- `photos.test.ts`: EXIF orientation 6 → portrait; output 356 × 444; no EXIF/GPS in output;
  same bytes twice; garbage bytes → `undefined` (placeholder path).
- `qr.test.ts`: matrix → PNG → `jsqr` decodes the review URL; same matrix twice.
- `report-content.test.ts` (per-page text via `extractText(pdf, { mergePages: false })`): every
  page has `n / N` and a statement (Full A on 1, Full B on checks pages, short elsewhere); every
  §5 fixed string appears in the right state; no `[` placeholder (`/\[(PLACEHOLDER|N\]|DATE|OPERATOR|CAPTURE ID|DEAL ID|ACC|HDG|PHOTO)/`);
  fonts in the PDF are exactly Inter subsets (2), `Times-Roman`, `Courier` (no `/Helvetica` bytes);
  logo paths present (path count); colours used ⊆ §3.1 tokens (scan content streams for `rg`/`RG`).
- `size.test.ts`: 40 rooms × 10 synthetic 4032 × 3024 JPEGs → < 45 MiB, render < 60 s; 80 rooms ×
  10 → reduced quality branch; budget exceeded → photos omitted with the footnote.
- `report.test.ts` and the other F9 tests per §10.

### 11.2 Swift ↔ TS parity goldens

- Swift: `ReportParityGoldenTests` (Linux, `scripts/swift-test.sh`) runs `PlanMetrics` on every
  capture model under `fixtures/generated/*/package` (good fixtures) and
  `fixtures/report/424-west-end`, writes/compares `fixtures/report-parity/{fixture}-{areaKey}.json`
  with per room: id, label, type, floorAreaM2, perimeterM, bbox {alongM, acrossM, angle},
  inscribed {alongM, acrossM}, ceiling {heightM, approximate, reasons}, volumeM3,
  wallAreaIncl/ExclM2, openings [{id, type, widthM, heightM, areaM2}], objects [{id, category,
  sizeM}], plus totals, plus the formatted strings (`UnitFormatter.length(.feetInchesTenths)`,
  1-dp areas). `UPDATE_PARITY_GOLDENS=1` rewrites.
- TS: `metrics-parity.test.ts` compares its port: numbers within 1e-9 relative (1e-6 m for the
  inscribed raster path), strings exactly.
- A Swift change to the engine fails the Swift test until goldens are regenerated, then the TS test
  until the port follows.

### 11.3 Visual snapshots and B&W proof

- `station/hub/test/report-visual/*.test.ts`: render scenario PDFs, rasterize with `pdftoppm -r 96
  -png` (792 pt → 1056 px, like the artboards; skipped with a printed notice when pdftoppm is
  missing locally, required in CI), compare with `__snapshots__/{scenario}-p{n}.png` via
  `pixelmatch` (threshold 0.1, ≤ 0.5 % differing pixels). Scenarios (424 fixture unless noted):
  1f cover limited · 1g ready · 1h blocked (not verified) · 1i 2 floors (floor 2 approximate
  compass via a stub compass) · 1k plan floor 1 · 1l plan floor 2 · 1n schedule with 2 skipped
  rooms and approx. Room 4 · 1p/1q/1r checks · checks continuation (60 findings) · 1t living ·
  1w kitchen · 1x closet · 1y Room 4 · 1z/1aa long name 27 items · 1u photos (7) · package record.
- B&W: the same scenarios for cover (limited), checks (blocked), living room and schedule with
  `pdftoppm -gray`; snapshot compared; plus an assertion on the greyscale raster: the three fill
  greys differ by ≥ 3 % lightness, and the blocked glyph region is not the background.
- First approval: a person compares each snapshot with its artboard (checklist in the PR: positions
  within 2 px at 96 dpi, strings, colours; known deviations: logo, Inter, §0.4).

### 11.4 Station API, worker, e2e

- API: `GET /packages/{id}/spatial-report` — bim/admin 200 with a 10-minute SAS for the right
  blob; capture role 403; no row → 404 `report_not_ready`; row of an older verdict → 404; audit row
  written without the URL.
- Worker: `onReportRendered` idempotent (same blob twice = success; different bytes same name =
  error); config validation of `REPORT_TIME_ZONE`, `STORAGE_REPORTS_CONTAINER`.
- e2e (AC6): §10.2; within 120 s.
- Contract: `redocly lint` passes; `verdict-words` unit tests.

### 11.5 Acceptance criteria (this area)

| Id | Criterion | Verify |
|---|---|---|
| SR-AC1 | The station's publish job uploads exactly one `spatial-report-{verdictId}.pdf` per verdict to `Capture/{visitId}/r{revision}`, and no verdict report | `station/hub/test/publish.test.ts` |
| SR-AC2 | The report contains the outcome word, every check, every finding (message, rule, measured, expected, file, next action), every limitation and next action, the verdict statement and the not-certification statement, as extractable text | `station/hub/test/report.test.ts` |
| SR-AC3 | Every page carries the logo, `n / N` and a not-certification statement (full on the cover and checks pages, short elsewhere) | `report-content.test.ts` |
| SR-AC4 | Every room number (area, perimeter, B, I, ceiling, volume, wall areas) equals the phone's PlanExport value for the same capture model | `metrics-parity.test.ts` + Swift `ReportParityGoldenTests` |
| SR-AC5 | Pages match artboards 1f–1aa (snapshots approved) with the real logo and Inter | `report-visual` |
| SR-AC6 | Greyscale print keeps verdicts (word + shape), fills and dash patterns distinguishable | `report-visual` B&W |
| SR-AC7 | No bracketed placeholder, no Helvetica, only token colours | `report-content.test.ts` |
| SR-AC8 | North arrow: verified/approximate/not verified by the ±10°/±30° rules, arrow rotated by a − H; no compass data → "Orientation: not verified" / "No compass reading" | `model.test.ts`, snapshots 1h/1i |
| SR-AC9 | Photos are embedded reduced (356 × 444 px, no EXIF/GPS) and the report stays ≤ 45 MiB | `photos.test.ts`, `size.test.ts` |
| SR-AC10 | Same input → byte-identical PDF | `report.test.ts` |
| SR-AC11 | The report is stored in `reports` and `GET /packages/{id}/spatial-report` returns a 10-minute link for bim/admin | API tests, e2e |
| SR-AC12 | Files over 45 MiB and non-HUB files are listed with their Entra station links | `large-files.test.ts` |

---

## 12. Dependencies on other areas

| Area key | Needed from it |
|---|---|
| `north-arrow` / `phone-capture` | capture-record compass fields per capture (heading of −Z, accuracy, source, recordedAt, rejected flag if any) in the coordinated contract bump; until then state 3 everywhere (no blocking) |
| `phone-package` | retirement of `SpatialReportWriter` and `spatial_report_pdf` (manifest 1.1.0, `HUB_UPLOAD_ROLES`, helpers, fixture generator, legacy fixture); OpenAPI 1.1.0 bump (this area adds §8.3 to it); migration 0009 lands first (this one is 0010); `links.review` / `REVIEW_BASE_URL` in the API |
| `plan-sheet` | shares PlanExport's metrics engine (goldens are regenerated when it changes `RoomMetrics`/`PlanTotals`/`UnitFormatter`); shares tokens and drawing rules (system 1ab); if it changes how rooms are typed or named on the phone, the report follows through the capture model |
| `web-review` (consumer) | uses §8.3 and §8.5; shows "Spatial report PDF · {pages} pages · {size}" |

---

## 13. Open questions (recommended default first)

1. **Package record pages** (not drawn). F9 AC2 and the F9 report test need the file list with
   SHA-256 and station links and the capture record. *Default:* add the package record at the end
   (§5.7), listed in the contents; the sample becomes 29–30 pages. Alternative: change F9 AC2 to
   "listed on the web review" and drop the pages.
2. **Plan orientation.** 1d says "the plan is never rotated: it stays in the scan frame". RoomPlan's
   frame is arbitrary, so walls would sit at random angles, and the phone's Floorplan already
   aligns to walls. *Default:* turn each floor (and each room page) so its walls run along the page
   axes; the north arrow includes that turn (§6.9). Alternative: draw in the raw scan frame (outer
   dimension strings then only for rooms within 3° of the page axes).
3. **Where the numbers come from.** *Default:* TS port of the PlanExport measurement engine with
   shared goldens (§6.4, §11.2). Alternatives: a Linux Swift CLI from PlanExport in the worker image
   (exact code reuse, Swift toolchain in the Docker build and Node CI), or a phone-written metrics
   file in the package (new role; does not cover packages already sealed).
4. **Time zone for printed dates and times.** The contract stores UTC; the property time zone is
   not recorded. *Default:* `REPORT_TIME_ZONE` = America/New_York for every report. Alternative:
   UTC with "UTC" after times.
5. **Photos whose room label matches no room** (renamed later, rooms not scanned, exterior).
   *Default:* "Other site photos" pages per floor (§5.6.5). Alternative: leave them out of the
   report (they stay in the package).
6. **Wall drawing parity with the plan sheet.** *Default:* simple centred bands with assumed
   thickness and square caps (§3.7). Alternative: port the phone's `WallLayout` (exterior bands
   outside the rooms, mitred loops; ~600 more lines) so the report's walls look exactly like the
   plan sheet's.
7. **Times outside WinAnsi.** Times-Roman (standard, not embedded, as PlanExport) can only show
   WinAnsi; titles with other letters print "?". *Default:* keep standard Times-Roman (owner:
   "Times stays Times"). Alternative: embed a Times-metric open font (e.g. Tinos) for Times text.
8. **Report storage for the web.** *Default:* Blob container `reports` + `spatial_reports` row
   (§8.2). Alternative: PDF bytes in Postgres (`bytea`, no infra change, larger database).
9. **Site photos in the HUB.** Photos were only behind Entra station links; the photo pages now put
   reduced copies (EXIF stripped) into the HUB Files tab. *Default:* as drawn (1u). Alternative:
   omit photo pages from the HUB copy and keep them only in the station copy.
10. **`checksPage` for the web** ("same table as page N"). *Default:* add `checksPage` to
    `SpatialReportLink` and the table (§8.4).

---

## 14. Risks

| Risk | Mitigation |
|---|---|
| Swift ↔ TS metric drift | golden files checked on both sides in CI (§11.2) |
| Inter is wider than Helvetica: wraps differ from the artboards | every text cell measured with the embedded font; single-line cells truncate; snapshot review |
| Report too large with many photos (HUB 45 MiB) | budget chain (§5.6.6), `size.test.ts` |
| Site photos reach the HUB (privacy) | EXIF/GPS stripped; Q9 |
| Worker memory/time with large photos | sequential decode, `sharp.concurrency(1)`, only reduced bytes kept |
| sharp native binary in the Docker image (`npm ci --ignore-scripts`) | linux-x64 optional packages are in the lockfile; build-stage `require('sharp')` smoke check |
| Text extraction inserts spaces in tracked kickers | tests compare with `squash()` for tracked text |
| WOFF2 fonts in pdfkit | generator converts to TTF (`wawoff2`); `report-content.test.ts` checks embedded subsets and extractable text |
| Compass contract shape not final | single adapter `compassOf`; state 3 until present |
| Report name change (`verdict-report-` → `spatial-report-`) | all station/worker tests updated; older publications keep their old file; no external consumer known |
| Two-pass pagination off by one | page-dependent text only in fixed cells (§4.1); `paginate.test.ts` |
| Ownership overlap with phone-package (`plan.ts`, helpers, e2e role lists, OpenAPI bump) | land phone-package's §11 station lines first or in the same PR; this area's tests assume them |

---

## Addendum (completeness critique, Oct 21, 2026) — binding, overrides the body above

Numbers refer to `00-critique.md`. Built by track **T4 spatial-report** (`station/hub/**`,
`station/worker/**`, `infra/**`, `.github/workflows/ci.yml`). The API endpoint and migration
0010 are built by **T2 station-api**; the parity goldens by **T5 plan-export**; the words module
and OpenAPI by **T0**.

### F1. Area names
Read `north-arrow` as `compass`. The capture-record compass fields are compass §4.1 (integer
`headingAccuracy`, optional `headingIssue`).

### F2. Compass (R-4, R-6, R-7)
- `report/compass.ts` (`compassOf`, `compassState`, `arrowAngle`) is not built: use the contract's
  `compassState(capture)` and `northSymbol(state, drawingRotationCcw)` with
  `drawingRotationCcw = −a` (a = the floor's clockwise squaring rotation of §7.4.1). The arrow
  angle and the caption's `{HDG}` both come from `northSymbol` (compass §2.5: `{HDG}` is the bearing
  of page-up).
- Captions: compass §1.4 (`Compass accuracy ±{ACC}°`, not "Accuracy ±{acc}°"; plus `Compass not
  calibrated`, `Compass unavailable`). The report-only caption `No scan model` stays for a floor
  without a readable model.
- The drawing helper compass §8.3 calls `station/hub/src/north-arrow.ts` is this spec's
  `report/draw/north-arrow.ts` (one file).
- Rule count: the station adds `orientation.compass` (track T3), so verdicts have **13** rules and
  evaluator `1.1.0`; "today the 12 RULES" in §0.4 and the F9 expectations follow the fixtures
  regenerated after T3. The verdict outcome of a not-verified orientation is owner question Q-B.

### F3. Words (R-15c, R-15d)
`contract/ts/src/verdict-words.ts` (§8.5) is not created; import `contract/ts/src/review-text.ts`
(`RESULT_WORD`, `OUTCOME_WORD`, `ruleResult`, `checkRows`, `countsLine`, `verdictHeadline`,
`ruleSetLabel`, `lowerFirst`, `notScannedText`). The checks table rows come from `checkRows(verdict)`
(same rows as the web). §5.4.1's right text reads `… · rules {ruleSetLabel(evaluator)} · evaluated
…` = `rules station-checks v1.1.0`. Skipped-room notes (§6.7) use `notScannedText` wording:
omitted `{name} ({reason})` / `{name} (not scanned)`; inaccessible `{name} (could not enter)` /
`{name} (could not enter: {reason})`.

### F4. Storage and API (R-14)
- Migration `0010_spatial-reports.sql` (built by T2) adds `checks_page integer NOT NULL CHECK
  (checks_page >= 1)` and `floors jsonb NOT NULL CHECK (jsonb_typeof(floors) = 'array')`.
- `RenderedReport` gains `floors: { captureId, areaKey, roomsScanned, roomsUnlabeled,
  floorAreaSqFt }[]` (per capture-record capture with a readable model; `floorAreaSqFt` = sum of
  rooms rounded to 0.1 once; `roomsUnlabeled` by §6.2). `onReportRendered` stores it with
  `checksPage`.
- The single link endpoint is §8.3 `GET /packages/{packageId}/spatial-report` with `checksPage`
  added to `SpatialReportLink` (Q10 accepted). The web uses it through its own route.
- `PackageSummary.report` (web-review §9.1 A) is filled by T2 from this table: `ready` (row for the
  current verdict), `failed` (publication `publish_failed` for the current verdict, no row),
  `pending` (otherwise, once a verdict exists).
- The HUB publication records the report with role `spatial_report`; T2 maps that entry to
  `report.hub`.

### F5. Fill rule parity (R-35)
§7.4 step 3 is replaced by plan-sheet §3.4.1 (label substrings incl. `shower`, `toilet`, `study`,
`bed`; then type; then objects) plus "every room of an `exterior` capture is outdoor". The parity
goldens carry `fillClass`; `metrics-parity.test.ts` compares it.

### F6. Fixtures (R-19)
`fixtures/report/424-west-end/` holds only `verdict-ready.json`, `verdict-limited.json`,
`verdict-blocked.json` for the package `fixtures/generated/sample-424/` (generated by T0 with 12
rooms, 14 objects, 2 skipped rooms, 7 living-room photos, Floor 1 compass verified). No second
transcription of the 424 trace.

### F7. Fonts (G-9)
The WOFF2 files in `web/public/brand` are subset to `WEB_UNICODES`, which lacks the WinAnsi
letters Š š Ž ž Ÿ ƒ. `pdfSafeText` maps them to S s Z z Y f before measuring and drawing. Test:
an address "Šibenik Ž" prints "Sibenik Z" and no `.notdef` glyph is embedded.

### F8. Retirement rows owned here (R-11)
`station/hub/src/plan.ts` `HUB_UPLOAD_ROLES` without `spatial_report_pdf`, `station/hub/test/
helpers.ts` role lists, the legacy-package publish test, and `station/worker/test/e2e/
pipeline.e2e.ts` role lists (phone-package §11 station rows) are built in this track, in the same
PR as the report name change.

### F9. Time zone (R-34)
`REPORT_TIME_ZONE` default America/New_York is also the plan sheet's print zone; keep them equal.

### F10. Drawing orientation (R-36)
The report squares each floor by its dominant angle only; the plan sheet may add a quarter turn
to fit the Tabloid frame. The two drawings can differ by 90°; both arrows are correct. Not a
defect.
