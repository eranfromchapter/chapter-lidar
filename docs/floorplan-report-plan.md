# Floorplan report: plan to match the Polycam outputs

Goal (Eran, 2026-10-18): from a scan, the app produces what Polycam's Floorplan Report and its
Floorplan, Spatial and 3D screens show, **and keeps every file the app produces today**.
Reference: Polycam Spatial Report of the same apartment (20 pages, Letter landscape) and four
Polycam app screenshots, reviewed 2026-10-18. Gap analysis: two real iPhone 17 Pro Max exports
of that apartment (kept local, never committed) and the code at commit 80182ea.

## Design v2 update (2026-10-21)

Decided by Eran on Oct 21, 2026 (`docs/waves/design/DESIGN.md`, "Design v2"); these lines
replace the matching ones below:

- **The phone report is retired.** The phone no longer writes `spatial-report.pdf`
  (role `spatial_report_pdf` is retired in manifest 1.1.0; legacy 1.0.0 packages keep it and the
  station never uploads it to the HUB). The multi-page report of phase 7 is made by the station
  after its checks: the spatial report (`spatial-report-{verdictId}.pdf`), which also replaces the
  station's verdict report and goes to the HUB.
- **plan.pdf became the plan sheet**: `plan-sheet.pdf`, one Tabloid 11 x 17 page per capture,
  made on the phone with no verdict, at a scale stepped down 1:50 → 1:100 → 1:200 (1:500 for an
  exterior capture), never fitted to the page. plan.png and plan.svg are drawn from the same
  sheet drawing, without a north symbol. The colour Floorplan of phase 8 is unchanged.
- **The manual north override is withdrawn** (phase 9). North comes only from the phone's compass,
  read at the start of each floor's scan, in three states (verified ±10°, approximate ±30°, not
  verified); a heading is never typed or taken from a map. The phone's location is used only to
  turn the compass into true north and is never stored. Build spec: `compass` (Design v2).
- Brand: the real Chapter logo and Inter on every output and screen; Times for titles, Courier
  for ids, dimensions and scale labels.

## Decisions

Decided by Eran, 2026-10-18:

| Topic | Decision |
|---|---|
| Multi-room scanning | Operators keep walking through doorways. The app splits rooms automatically; a Rooms screen after the scan lets the operator rename, retype, merge and split. |
| Location | The app asks for location while scanning: latitude, longitude, altitude and true north (compass). If permission is denied, the scan still works and the report says so. **Design v2:** location only turns the compass into true north and is never stored; with Location off north is magnetic (approximate at best). |
| Report files | A new multi-page Floorplan Report PDF and a colour floor plan are added. Today's plan.pdf/png/svg/dxf, spatial-report.pdf and rooms.csv stay (unit fixes only). **Design v2:** plan.pdf is now the plan sheet `plan-sheet.pdf`; the phone's spatial-report.pdf is retired; the multi-page report is the station's spatial report. |
| Branding | Chapter name, logo and colours from the app design. Own disclaimer, drafted for Eran's review. No Polycam branding or wording. |

Defaults until Eran says otherwise:

- Imperial is the default for reports and plans (ft-in to 0.1 in, ft² to 1 decimal, ft³ to 2
  decimals); metric stays an option. plan.dxf stays in millimetres (CAD convention).
- Xactimate export is parked: ESX is a proprietary Verisk format. DXF and rooms.csv are the
  hand-off.
- Wall thickness is not measured by RoomPlan (always 0). Thick walls, outside dimensions and
  exterior floor area use an assumed 4.5 in interior and 6 in exterior thickness, and are
  labelled as estimates.
- Low-confidence objects are shown and marked.
- No QR code until there is a HUB link to point it at.
- The two real apartment scans stay local-only test inputs.

## What the gap analysis found

- Rooms are the hard part. A walk-through scan is one RoomPlan room: one floor outline, 24-36
  walls, and 3-5 `sections` (a label such as bedroom or kitchen, and a centre point, no shape).
  The mapper turns it into one "Room 1". Everything per room depends on real room polygons.
- Splitting from geometry works only partly. Walls plus the floor outline gave 5 correct rooms on
  export A; on export B the bedroom and bathroom stay merged. Rooms with no wall between them
  (living room and kitchen, a closet) cannot be split from geometry, and RoomPlan never labels a
  closet. Hence the Rooms screen.
- Totals check out against Polycam's own schedule: livable area, volume and perimeter are sums of
  the per-room values; casing lengths are window 2(w+h)+8c and door 2h+w+4c with c = 1 9/16 in
  (passages without a door get no casing).
  Polycam's per-room wall area rule is not yet reproduced; it also subtracts open passages that
  its Openings tables do not list.
- The PDF engine is grayscale, Helvetica, no dashes and no images; the PNG is grayscale with a
  capitals-only font. Colour, dashes and symbols need engine work.
- points.las is not produced on real devices today: both real exports have a header-only
  depth-samples.bin.

## Phases

Each phase ships on the phone and is tested on Linux (Swift packages) or the iOS simulator.

1. **Lock today's files, add a realistic test scan.** Export tests assert every current file and
   role is still produced. A synthetic walk-through fixture shaped like the real exports. Fix the
   spatial-report object-size cell. Add AppCore tests to CI.
2. **Room names from RoomPlan.** Decode `sections`, object attributes, door `isOpen`. Room type
   from the section inside each room, or from its objects (toilet → bathroom). Contract 1.1.0
   with per-document schema versions; the station accepts 1.0.0 and 1.1.0.
3. **Automatic room splitting.** Planar arrangement of walls and floor outline, vertex welding,
   face tracing, sections decide; split walls at room junctions and rebase openings. Rooms
   without walls get a fallback height.
4. **Rooms screen.** Rename, retype, merge, split; edits stored in the capture record and applied
   in every export. Photo and field-control room labels follow the edits.
5. **Measurement engine.** Per room: area, perimeter, bounding box, largest inscribed rectangle,
   wall area incl./excl. openings, ceiling height with an approx flag, volume, casing lengths.
   Totals: bedrooms, bathrooms, livable and exterior area, wall and window area, volume,
   perimeter. One unit formatter.
6. **Drawing engine.** PDF colour and dashes, colour PNG, furniture/fixture/appliance symbols,
   room-type colours, thick walls along room boundaries, compass, feet scale bar, dimension
   placement with collision checks.
7. **Floorplan Report PDF** (Design v2: made by the station after its checks as the spatial
   report, not on the phone; uploaded to the HUB): overview with totals,
   table of contents and fully dimensioned plan, room schedule, then 1-3 pages per room with
   bounding-box and inscribed overlays, numbered markers, key map, and Furniture, Fixtures,
   Appliances, Openings and casing tables. Station deployed before the app.
8. **In-app screens.** Floorplan (colour plan, room names and areas, total area, compass, Edit,
   Download), Report (preview, Configure, Download), Files (every file, Quick Look, Share).
9. **Location and true north.** One location fix at the property; heading sampled during the scan
   and paired with the camera yaw. ~~Manual north override in the Rooms screen~~: withdrawn
   (Design v2, Oct 21, 2026): north is never typed; see the `compass` build spec.
10. **3D viewer.** Layers (walls, doors, windows, objects), orbit, top and walk views, measuring,
    Share. Furniture models and textured floors are a later decision.
11. **Station check of report numbers.** Recompute the totals from capture-model.json and flag a
    mismatch.
