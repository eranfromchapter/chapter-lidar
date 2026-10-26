# Completeness critique of the Chapter Capture v2 build specs

Written Oct 21, 2026 by the completeness critic. Inputs: the seven area specs in this folder
(`phone-capture`, `phone-field`, `phone-package`, `web-review`, `plan-sheet`, `spatial-report`,
`compass`), the main canvas `canvas/Chapter Capture v2.dc.html`, `00-plan-of-changes.dc.html`,
`00-plan-screens.dc.html`, the v2 artboard sources and the repo at `feat/floorplan-report`.

**How to read this.** Section 1 checks that every artboard and decision has an owner. Section 2
lists every contradiction found, each with a **binding resolution** (marked R-n). Section 3 lists
gaps and underspecified parts with the fix. Section 4 checks the specs against the owner
decisions of Oct 21. Section 5 holds the questions only the owner can answer. Each spec file
now ends with an "Addendum (completeness critique)" that applies the resolutions to that spec;
where an addendum and the spec body disagree, **the addendum wins**. Build tracks are in
`00-tracks.md`.

Precedence when two specs still disagree after this document: owner decisions (Oct 21) >
this critique (R-n) > the spec that owns the topic (ownership table in 2.0) > any other spec.

---

## 1. Coverage: every artboard and decision has an owner

| Id | Artboard | Owner spec(s) | Status |
|---|---|---|---|
| 1a, 1c, 1e, 1j, 1m, 1o, 1s, 1v, 2a, 2c, 2e, 2g | v1 (current) artboards | reference only | not built (correct) |
| 1b | plan-sheet-v2 | plan-sheet | covered |
| 1d | north-arrow-v2 | compass (symbol, data, thresholds); plan-sheet, spatial-report (placement) | covered; contradictions R-6…R-10 |
| 1f, 1g, 1h, 1i | report-cover-v2 (Limited, Ready, Blocked, 2 floors) | spatial-report | covered |
| 1k, 1l | report-plan-v2 | spatial-report | covered |
| 1n | report-schedule-v2 | spatial-report | covered |
| 1p, 1q, 1r | report-checks-v2 | spatial-report (+ shared words with web-review) | covered; R-15 |
| 1t, 1w, 1x, 1y, 1z, 1aa | report-room-v2 variants | spatial-report | covered |
| 1u | report-photos-v2 | spatial-report §5.6 | covered |
| 1ab | system-v2 | plan-sheet §5, spatial-report §3 | covered |
| 1ac | bw-proof-v2 | plan-sheet §6, spatial-report §5.8/§11.3 | covered |
| 2b (0, 1, 1b, 1c, 2, 3, 3b, 4) | app-capture-v2 | phone-capture (host), compass (compass parts) | covered; R-20…R-24 |
| 2d (1–4) | app-field-v2 | phone-field | covered; G-4, G-5 added |
| 2f (1–4) | app-package-v2 | phone-package | covered; R-25…R-29 |
| 2h, 2i, 2j | web-review-v2 (projects, project, package) | web-review | covered; R-30…R-33 restore drawn content |
| 2k | screen-tokens-v2 | phone-capture §2 (phone), web-review §2 (web) | covered; R-17, R-18 |
| 00-plan-screens "Web" | capture-role view, sign-in, empty state (not drawn) | web-review §6.6–§6.8 | covered |
| 00-plan-of-changes §4 | skipped rooms, units, honesty statement | plan-sheet, spatial-report | covered |
| Owner decision 1 (logo, Inter) | all | all | covered; one fix in R-17 (font registration) |
| Owner decision 2 (web in HUB DS, Inter, self-hosted) | web | web-review | covered |
| Owner decision 3 (plan sheet on phone, report on station, compass, Tabloid) | all | plan-sheet, spatial-report, compass, phone-package | covered; ownership of the retirement fixed in R-11 |

No v2 artboard is uncovered. The gaps are behaviours between screens and data between areas
(section 3).

---

## 2. Contradictions and binding resolutions

### 2.0 Who owns what (binding)

| Topic | Owner spec | Others must defer |
|---|---|---|
| Compass fields, evaluator, texts, reading algorithm, every compass string on the phone | `compass` | phone-capture §3.3.1, §3.4 (pill texts), §4, §5.1 compass types; plan-sheet §4.1, §4.3, §9; spatial-report §6.9; web-review §5.3 |
| Phone tokens, fonts, logo, shared components, navigation chrome | `phone-capture` §2 (ChapterUI) | phone-field §1, phone-package §2 |
| Captures home, Capture overview, VisitFlow, `visit.json` | `phone-capture` | phone-package §8, §9.1 (VisitFlow part) |
| Upload, station status cache, verdict screen, revision n | `phone-package` | phone-capture §5.4 |
| PlanExport (plan sheet, previews, north symbol on drawings, Floorplan north, `SpatialReportWriter` removal) | `plan-sheet` | phone-package §11 PlanExport rows; compass §6.3 (API only, built in the plan-export track) |
| Station spatial report, its storage, HUB publication | `spatial-report` | web-review §9.1 G |
| Web pages | `web-review` | compass §9 supplies texts |

There are no areas called `north-arrow`, `screen-tokens` or "station". Read `north-arrow` as
`compass`, `screen-tokens` as `phone-capture` §2. Station work is split by area but built in the
station tracks of `00-tracks.md`.

### 2.1 Contract and data

**R-1. One contract release (v1.1) for everything.** phone-field (manifest 1.1.0
`photo.directionSource`), phone-package (manifest 1.1.0 retired-role rule, OpenAPI 1.1.0),
compass (capture-record 1.1.0), web-review (OpenAPI 1.1.0, `review-text.ts`, contract/ts 1.1.0)
and spatial-report (OpenAPI 1.1.0, `verdict-words.ts`) each describe part of the same bump.
Binding: one PR, built by track T0, containing:

- `manifest.schema.json` 1.1.0 = phone-field §10 **plus** phone-package §10.1 (both in the same
  `schemaVersion` 1.1.0; `ManifestSchemaVersion` defined once).
- `capture-record.schema.json` 1.1.0 = compass §4.1 exactly. plan-sheet §9's contract table is
  **superseded**: `headingAccuracy` is an **integer 1–180** (not a number 0–180), and the optional
  `headingIssue` exists.
- OpenAPI 1.1.0 = the merged schema of R-12…R-16.
- contract/ts 1.1.0: `src/compass.ts` (compass §4.3) and **one** `src/review-text.ts` (R-15).
- Swift: `ManifestSchemaVersion`, `CaptureRecordSchemaVersion`, `HeadingSource`, `HeadingIssue`,
  `PhotoDirectionSource`, `FileRole.isRetired`, `Compass.swift`, `CompassMath.swift`.
- Test vectors: **only** `contract/test-vectors/compass-states.json` (compass §4.4).
  plan-sheet's `contract/examples/north-arrow-states.json` is not created; its rows are merged
  into the compass vectors with integer accuracies (plan-sheet's "true 10.01" becomes 11; "accuracy
  7.5 → ±8°" is dropped because the schema stores integers).
- Fixtures (see R-19).

**R-2. One `HeadingSource` type.** Three exist in the specs: a protocol in CaptureCore
(phone-capture §4.7), an enum in FieldRules (phone-field §3.6) and an enum in CaptureContract
(compass §3.5). Binding: `CaptureContract.HeadingSource` (`trueNorth = "true"`, `magnetic`) is the
only one. The heading provider protocol is compass's `CompassProviding`; FieldRules'
`PhotoHeadingSample.source` uses the contract enum.

**R-3. One compass math implementation.** `CaptureContract.CompassMath` (compass §2.3). phone-capture
§5.1 `CompassMath` (CaptureCore) is not created. phone-field `CameraAxis.sample(rotationMatrix:)`
calls `CompassMath.cameraAxisInReference`. The conventions in phone-capture §4.3 (magnetic frame +
declination, |f.y| ≤ 0.766, 30 Hz, 20 ms pairing) are replaced by compass §3.3 (true-north frame
when authorised, 60 Hz, 25 ms pairing, gravity checks, consistency test, 30 s start period).

**R-4. One evaluator and one text table.** Swift `CompassState`, `NorthSymbol`, `CompassText`
(contract) and TS `compassState`, `northSymbol`, `compassDetail`. Not created: phone-capture's
`CompassClassifier`/`CompassReading`/`CompassPreview`, plan-sheet's `NorthArrow.classify` and
`NorthArrow.State`, spatial-report's `compassOf`/`compassState` in `station/hub`, web-review's
`orientationOf`.

**R-5. Field names.** `heading`, `headingAccuracy` (integer), `headingSource`, `headingRecordedAt`,
`headingIssue` on each capture. phone-capture's "not-verified reason" field is `headingIssue`;
spatial-report's "rejected flag if any" is `headingIssue = "rejected"`.

### 2.2 North symbol on drawings

**R-6. Reason captions** (compass §1.4, binding): `No compass reading`, `Reading rejected`,
`Compass accuracy ±{ACC}°`, `Compass not calibrated`, `Compass unavailable`. plan-sheet's "Low
compass accuracy" and spatial-report's "Accuracy ±{acc}°" are replaced. spatial-report keeps one
report-only caption, `No scan model`, for a floor whose capture model is absent or unreadable (it
is not a compass reason and is never written to data).

**R-7. Caption line 2 shows A, not the stored heading.** compass §2.5: on any drawing turned by ρ,
`A = (H + ρ) mod 360` is both the arrow angle and the `{HDG}` printed. plan-sheet §4.3 ("hdg =
heading") and spatial-report §6.9 are corrected: plan sheet `ρ = −FloorPlanDrawing.rotationDegrees`;
spatial report `ρ = −a` where `a` is the clockwise squaring rotation of spatial-report §7.4.1.
compass §2.5's table row "Station spatial report: ρ = 0 (never rotated)" is wrong for the default
of spatial-report Q2 and is corrected to `ρ = −a`.

**R-8. Ink of the symbol** = the host output's ink token: `#1F2429` on the plan sheet (plan-sheet
Q3 default) and on the spatial report; `ChapterBrand.ink #231F20` on the colour Floorplan only
(compass §6.1 note corrected).

**R-9. `plan.png` and `plan.svg` carry no north symbol** (plan-sheet §7, binding). The web preview
in 2j draws none and shows orientation as text. compass §6.2's row "plan.png / plan.svg 32 pt" is
withdrawn.

**R-10. Not-verified box.** Box height 15 pt (padding 3 + line 9 + 3), 0.75 pt border stroked on
the box edge, radius 3; width = text + 12. plan-sheet's "97.4 × 16.5" counted the border twice;
use the compass value everywhere.

### 2.3 Ownership of files claimed twice

**R-11. Retiring the phone report.** Three specs claim the deletion of `SpatialReportWriter.swift`
and the `exportAll` change (phone-package §11, plan-sheet §2 "owned by spatial-report",
spatial-report §0.2 "phone-package"). Binding split:

| Piece | Built by (area / track) |
|---|---|
| `SpatialReportWriter.swift` deleted, `exportAll` = five files, PlanExport tests | plan-sheet (track T5). No interim rule: deleted in plan-sheet step 3. |
| Contract (manifest 1.1.0 rule, `FileRole.isRetired`, examples) | T0 |
| Fixtures (no `spatial-report.pdf`, legacy 1.0.0 fixture) | T0 |
| PackageKit (`retiredRole`), AppCore (`Summaries`, `ManifestRoleTests`, `PackagePipelineTests`) | phone-package (T9) |
| `station/hub/src/plan.ts` `HUB_UPLOAD_ROLES`, hub tests, worker e2e | spatial-report (T4) |
| `web/lib/format.ts` legacy label, web tests | web-review (T6) |

**R-12. `NorthArrow.swift` in PlanExport** is one file for the plan sheet (40 pt) and the
Floorplan (compass §6.3). API = compass §6.3 (`items(symbol: NorthSymbol, …)`,
`blockSizeMM`). Built in the plan-export track together with the sheet.

**R-13. Migration numbers.** phone-package and web-review both wrote `0009_…`. Binding:
`0009_carry-over.sql` (phone-package), `0010_spatial-reports.sql` (spatial-report, with the two
extra columns of R-14), `0011_review-read-model.sql` (web-review, renamed). All three are built
by the station-api track.

### 2.4 Station API 1.1.0 (merged; phone-package §10.2, web-review §9.1, spatial-report §8.3)

**R-14. Spatial report endpoint and summary.** web-review defines
`GET /packages/{id}/report/download` + `ReportSummary`; spatial-report defines
`GET /packages/{id}/spatial-report` + `SpatialReportLink`. Binding:
- One endpoint: `GET /packages/{packageId}/spatial-report`, operationId `getSpatialReportLink`,
  response `SpatialReportLink` **plus** `checksPage: integer ≥ 1` (spatial-report §8.4 / Q10
  default). web-review §9.1 G is withdrawn; the web keeps its own URL
  `/packages/[id]/report/download` and calls `getSpatialReportLink`.
- `PackageSummary.report: ReportSummary` (web-review §9.1 A) stays and is filled from
  `spatial_reports`. Migration 0010 adds `checks_page integer NOT NULL CHECK (checks_page >= 1)`
  and `floors jsonb NOT NULL` (array of `{captureId, areaKey, roomsScanned, roomsUnlabeled,
  floorAreaSqFt}`). `renderSpatialReport` returns `floors` in `RenderedReport` (it computes them
  for the cover and schedule) and the worker stores them.
- `report.status`: `ready` when a row exists whose `verdict_id` is the current verdict; `failed`
  when the current verdict's publication is `publish_failed` and there is no such row; `pending`
  otherwise (a verdict exists). Omitted before a verdict.
- `report.hub`: the HUB file state of the publication entry with role `spatial_report`.

**R-15. Merged summary objects.**
- `checks` = `{status: queued|running|completed|failed, startedAt?, finishedAt?, rules?}` on
  `PackageSummary` (phone-package's `CheckRunSummary` + web-review's `rules`).
- `publication` = `{status, publishedAt?, hubFolder}`; `hubFolder` is required and always
  `Capture/{visitId}/r{revision}` (computed, so it is always known).
- `links` = `{review, hub?}` on `Package` and `PackageSummary` (phone-package).
- `Package.nextRevision` (phone-package) **is consumed by the web** (R-30).
- `PackageFile` gains `generator` and `generatorVersion` from the manifest entry when not already
  exposed (needed by R-32).
- `HubProject.projectManager?: {name, phone?}` (phone-capture Q9) is added as optional and also
  feeds the web's "PM [NAME]" (R-33). Shown only when the HUB source provides it.

**R-16. "Registered" means the same on phone and web.** The phone artboard 2f shows "Registered
14:02" as done while the upload is paused at 67%, so "Registered" is the moment the station
created the package (upload session opened) = existing `Package.createdAt`. The station column
`packages.registered_at` means "seal accepted" and must not be shown as "Registered". Binding:
web-review does **not** add `registeredAt` to `PackageSummary`; the web Station card row 1 is
"Registered · {createdAt}" (done for every package the station knows); while uploading, row 2 is
"Checks · after upload". phone-package's `UploadState.registeredAt` takes the station `createdAt`
from the session answer when present (phone clock only as a fallback).

**R-15b. HUB deal link.** phone-package adds station config `HUB_WEB_DEAL_URL_TEMPLATE` →
`links.hub`; web-review adds web env `HUB_DEAL_URL_TEMPLATE` for the same URL. Binding: the
station config only; the web uses `links.hub` (project page "Open in the HUB"). Web keeps
`HUB_APP_URL`, `HUB_FILES_URL_TEMPLATE`, `INTAKE_GUIDE_URL`.

### 2.5 Shared words

**R-15c. One verdict-words module.** web-review §5 (`review-text.ts`) and spatial-report §8.5
(`verdict-words.ts`) define the same words under different names. Binding: one file
`contract/ts/src/review-text.ts` exporting `RESULT_WORD`, `OUTCOME_WORD`, `lowerFirst`,
`ruleResult(check, findings)`, `checkRows(verdict)`, `sortCheckRows`, `checkCounts`,
`countsLine`, `verdictHeadline(verdict)`, `ruleSetLabel(evaluator)`, `notScannedText(record)`.
The two rule semantics agree with today's `statusOf` (a check with a limitation finding is always
`failed`), so the merge is mechanical. `ruleSetLabel` = `"{evaluator.name} v{evaluator.version}"`
on both the web meta line ("rules station-checks v1.1.0") and the report checks heading
("rules station-checks v1.1.0"); spatial-report §5.4.1's "rules {name} {version}" uses it.

**R-15d. Not-scanned text** (web-review §5.6 vs spatial-report §6.7). Binding: `notScannedText`
for the web and the report notes: omitted `{name} ({reason})` / `{name} (not scanned)`;
inaccessible `{name} (could not enter)` / `{name} (could not enter: {reason})`; multi-floor cover
`{name} ({floor label}, {…})`. The plan sheet and the phone keep their drawn list form
`{name} · {reason}`.

### 2.6 Phone foundation

**R-17. Fonts are registered by ChapterUI only.** phone-field §1.2/§13(e)/§14 put Inter in
`ios/App/Resources/Fonts` with `UIAppFonts`; phone-capture §2.6 bundles them in the ChapterUI
package and forbids `UIAppFonts`. Binding: phone-capture §2.6. FieldKitUI depends on ChapterUI;
phone-field's fallback files are not created.

**R-18. One token and component library.** phone-package §2.3/§9.6 asks for
`ChapterTokens.Typography.inter` from a "screen-tokens" area; compass §5 uses
`ChapterTokens.Typography.sans`; phone-field §1.3 defines its own components. Binding: ChapterUI
(`ChapterTheme.Color/Font/Metric`) holds the **union**: phone-capture §2.4 plus phone-field §1.3
(`TextButton`, `ChoiceChip`, `SheetBar`, `SectionCaption` 12/13 pt variants, `Chevron`) plus
phone-package §2.5 (`PlusGlyph`, `EqualsGlyph`, `MinusGlyph`, lock `InfoNote`, 8 pt
`ProgressBar` variant, 14 pt verdict glyphs). `ChapterTokens` and `FieldTheme` stay as façades.
Name mapping: phone-field `SegmentedControl` = `ChapterSegmented`, `GroupedCard` = the
`ChapterSection` card, `StatusGlyph`/`Chevron` = ChapterUI's.

**R-18b. The waiting glyph ○** is drawn in 2f as circle (5, 5) r 4, stroke 1.2 `#6B6557`, no fill.
phone-capture (r 4.5, stroke 1) and phone-field (r 4, stroke 1) are corrected. The web keeps its
own `ring` (r 4, stroke 1.4) per the HUB drawing.

**R-18c. One header pattern.** phone-package §2.2 draws its own header block and a custom back
pill for iOS 17–25; phone-capture §2.5 uses the system `NavigationStack`, large title through
`UINavigationBarAppearance` and the subtitle as first content line. Binding: phone-capture §2.5 on
every phone screen, including Package ready, Package status, Verdict received and Revision n.
The only custom back is phone-field's intercepted Back on "Label a photo" (system
`chevron.left` image in a leading toolbar button).

**R-18d. One snapshot harness.** phone-field §15.2 renders with `ImageRenderer`, which cannot
draw `TextField`, `Toggle` or `ScrollView` (phone-capture R11); its entry sheet and room picker
have text fields. Binding: ChapterUI ships a library product `ChapterUISnapshotTesting`
(host the view in a `UIWindow` 402 × 874 pt at scale 3, `drawHierarchy(afterScreenUpdates:
true)`, fonts registered in `setUp`). Tolerance for every phone snapshot: fail when more than
0.5 % of pixels differ by more than 8/255 in any channel (phone-capture's 2/255 is too tight
for anti-aliasing drift between simulator builds).

**R-19. Fixtures.** Four specs edit `fixtures/generator` (phone-package: no `spatial-report.pdf`,
manifest 1.1.0, legacy fixture; compass: compass fields; plan-sheet: `sample-424`;
spatial-report: `fixtures/report/424-west-end`). Binding: track T0 owns `fixtures/**` except
`fixtures/report-parity/**` (T5). One 424 fixture: `fixtures/generated/sample-424/` (geometry
from `apartment-424.js`, 12 rooms, 14 objects, 2 windows, thresholds, omitted "Primary closet"
(locked), inaccessible "Storage room", 7 living-room photos, Floor 1 compass verified 212.4° ±8
true). `fixtures/report/424-west-end/` holds only `verdict-ready.json`, `verdict-limited.json`,
`verdict-blocked.json` for that package. **Gap fixed:** the generator also writes the plan sheet
as `plan-sheet.pdf` (it writes `plan.pdf` today) so fixtures look like v2 packages.

### 2.7 Compass on the phone

**R-20. compass is binding for every compass string and behaviour on the phone.** phone-capture
§3.3.1 (row texts), the pill table in §3.4, §4 (all) and the compass parts of §5.1, §10 (T-C1…T-C7,
T-F5, T-F6, U2 strings) are superseded by compass §1.3 (AGO rule), §3 (algorithms), §5.1 (row),
§5.2 (chip). phone-capture keeps the host layout (row 56 pt, glyph 32 pt, pill 32 pt, positions).
Concretely the phone shows: reading `Compass` / `Reading the compass…`; inaccurate `North {HDG}°
{true|magnetic} · ±{ACC}°` / ▲ `Not verified · accuracy too low · read {AGO}`; not calibrated
`No compass reading` / ▲ `Not verified · move the phone in a figure 8, then read again`;
unavailable `No compass on this phone` / ▲ `Not verified · the plans will say so`; chip `N ·
reading…` and `N · not verified`; `{AGO}` = `just now`, `{n} s ago`, `{n} min ago`, `over an hour
ago`; `Read again` disabled at opacity 0.4 while reading, hidden when unavailable; Location-off
note with the `Open Settings` button. Permission string (Info.plist): compass §3.1.
On the 32 pt phone glyph the approximate ring dash is 1.6 / 1.6 (north-arrow v2 vector), not
compass §5.1's 2 / 2.

**R-21. Overview Compass row.** compass §5.3 and phone-capture §3.5.1 disagree on words and on the
tap target. Binding:
- right side: all verified ● `Verified`; all usable and ≥ 1 approximate ▲ `Approx.` (the 2k
  status vocabulary "▲ Partly / Approx."); some usable, some not ▲ `Partly` (drawn); none usable ▲
  `Not verified`;
- subtitle per floor (`CompassSummary.short`): `verified`, `approximate`, `not verified` (reasons
  inaccurate, rejected), `not read` (no_reading, not_calibrated, unavailable);
- tap → Before you leave with focus on "Compass reading" (an existing drawn screen). compass
  §5.3's new Compass sheet is not built.

**R-22. "Read" on Before you leave is hidden** (compass Q1, phone-capture Q2, phone-field Q3 all
agree): the app passes `onReadCompass: nil`.

**R-23. One sensor owner.** compass §3.5's single `CompassService` (target `CaptureCompass`) also
feeds the photo heading through the app's `CompassPhotoHeading` adapter. phone-field does not
build `DeviceCameraHeading`; it keeps the `PhotoHeadingProviding` protocol and a
`FixedPhotoHeading` test double.

**R-24. One UI-test hook.** Launch argument `-ChapterUITestCompass verified|approximate|none`
(same style as `-ChapterUITestVerdict`), replacing phone-capture's `FixedHeadingSource` and
compass's `UITEST_COMPASS` env. `FakeCompass` scripts the scan reading (verified 212.4° ±8 true;
approximate magnetic ±12; none) **and** the photo camera bearing (85° ±8 true → "E", phone-field
§15.3).

### 2.8 Phone navigation and state

**R-25. One VisitFlow** (phone-capture §5.3 + phone-package §9.1). Steps: `.captureRecord`,
`.scan`, `.photos(captureId, room)`, `.controls`, `.checklist(focus)`, `.overview`,
`.packageReady`, `.revisionReady`, `.packageStatus(packageId)` (phone-capture's `.uploading` is
renamed). State: `revision` (1 for a new visit), `basePackageId?`, `isRevisionMode`, `isSealed`.

| Event | From | To |
|---|---|---|
| `scanStarted()` | `.captureRecord` | `.scan` |
| `scanCancelled()` | `.scan` | `.captureRecord` |
| `floorFinished(record)` | `.scan` | `.photos(captureId, nil)` |
| `photosDone()` | `.photos` | `.overview` |
| `openPhotos(captureId, room)` | `.overview`, `.checklist` | `.photos` |
| `openControls(focus:)` | `.overview`, `.checklist` | `.controls` |
| `controlsDone()` | `.controls` | `.overview` |
| `openChecklist(focus:)` | `.overview` | `.checklist(focus)` |
| `backToOverview()` | `.photos`, `.controls`, `.checklist`, `.packageReady`, `.revisionReady` | `.overview` |
| `confirmNoRoomsSkipped()` | `.checklist` | same |
| `reviewPackage(canFinish:)` | `.overview`, `.checklist` | `.packageReady` (revision 1) or `.revisionReady` (revision mode); throws `checklistIncomplete` |
| `addFloor()` | `.overview`, `.packageReady`, `.revisionReady` | `.captureRecord`; throws `alreadySealed` when sealed and not in revision mode |
| `sealed(packageId)` | `.packageReady`, `.revisionReady` | `.packageStatus(packageId)` |
| `resealAfterFailure(newPackageId)` | `.packageStatus` | `.packageStatus(newPackageId)`, `revision += 1` |
| `VisitFlow(revisionOf:base:baseRevision:)` | — | `.overview`, revision mode |

phone-package's `addMoreRooms()` and `reviewRevision()` are these `addFloor()` and
`reviewPackage(canFinish:)`. **Gap fixed:** the checklist gate applies in revision mode too
(blocking items of the whole visit); the overview button reads "Fix [N] item(s) to review the
package" when failing and "Review revision [R]" when passing.

**R-26. One visit file.** phone-package's `revision-draft.json` is not created. phone-capture's
`visit.json` gains (additive, `formatVersion` stays 1):
`"revision": { "number": 2, "basePackageId": "…", "startedAt": "…" }` (absent for revision 1).
The sealed package of revision n is the newest folder in `packages/` whose manifest has that
revision.

**R-27. One station status cache.** File `<packageId>.station-status.json` next to
`<packageId>.upload-state.json`, schema = phone-package §9.1 `StationStatusCache` (`formatVersion`
1, `packageId`, `stage`, `checks`, `publication`, `links`, `verdict` (`VerdictStatus`),
`fetchedAt`). phone-capture §5.4's smaller schema is withdrawn (`outcome` = `verdict.outcome`).
Written only by `UploadCoordinator` and the background refresh (phone-package); read by
`CaptureLibrary` (phone-capture).

**R-28. Captures home rows: one builder, one table.** phone-package §8 (`PackageListItem`,
`PackageList.swift`) is withdrawn; phone-capture's `CaptureLibrary` builds the rows, using
phone-package's `StationStatusCache`, `UploadState` and `CaptureCountText`. Rule: "In progress"
until the newest package has a verdict; "Sealed" only with a verdict. In-progress rows open the
Capture overview (drawn link `#overview`; phone-package's "recommended Screen B" is withdrawn);
Sealed rows open Verdict received.

| Case | Section | Subtitle | Trailing |
|---|---|---|---|
| not sealed | In progress | `{count} · not sealed yet` | chevron |
| uploading | In progress | `{count} · uploading · {x} of {y} MB` + 4 pt bar | chevron |
| paused (offline or station) | In progress | `{count} · upload paused · {x} of {y} MB` + bar | chevron |
| sign-in required | In progress | `{count} · sign in to upload` | chevron |
| upload stopped (fatal) | In progress | `{count} · upload stopped` | ■ `Stopped`, chevron |
| all confirmed, no verdict (incl. `check_error`) | In progress | `{count} · uploaded · checks running` | ○ `Checking`, chevron |
| revision n+1 started | In progress | `{count} · revision {n+1} not sealed yet` | chevron |
| verdict ready / limited | Sealed | `Revision {n} · sealed {MMM d, yyyy}` | ● `Ready` / ▲ `Limited` |
| verdict blocked | Sealed | `Revision {n} · re-seal needed` | ■ `Blocked` |

`{count}` = `CaptureCountText` ("2 floors", "1 floor and 1 room"), replacing phone-capture's
"[N] floors". The word "Failed" (phone-capture) becomes "Stopped" to match Screen B "Upload
stopped".

**R-29. One title rule on the phone.** Project title = `hub.projectName` when not empty, else
`address.formatted` (phone-capture §3.1.1 †) for home rows, overview, Verdict received title
(phone-package §5.1 used `address.formatted`, the whole one-line address), the Revision n right
label, and the notification body.

### 2.9 Web restored to the drawing (owner decision 2: "as drawn")

**R-30. Revision 2 on the phone is shown, as drawn.** web-review marked the drawn row "Revision 2
· not sealed · on the phone", the card "What revision 2 adds · from the phone, not sealed yet",
the subs "answers limitation 1 · coverage" / "answers limitation 2 · 2,490 mm" and the line
"Revision 2 is in progress on the phone with both." as **not available** (deviations 2, 3, 8).
phone-package §10.2/§10.4 builds exactly that data (`Package.nextRevision`). Binding: the web
renders it (rules in the web-review addendum); the deviations are withdrawn. When the station has
the revision package, the notice is gone and the station row is shown as today.

**R-31. Orientation texts on the web** = compass §9 (binding): plan card "Orientation" and
capture-record "Compass" values from `compassState` + `web/lib/compass.ts`. web-review §5.3's
table is superseded.

**R-32. Plan sheet document row.** web-review deviation 7 drops "Tabloid · 1 sheet". Binding:
right text `Tabloid · 1 sheet · from the phone` when the `plan_pdf` manifest entry is written by
`chapter-capture-ios/PlanExport` with `generatorVersion` ≥ 2.0.0 (every v2 sheet is one Tabloid
page), else `{size} · from the phone` (older Letter plan PDFs).

**R-33. "PM [NAME]"** is rendered as `PM {projectManager.name}` when the station returns it (R-15);
otherwise omitted (web-review deviation 1 stays only for that case).

### 2.10 Plan sheet and report agree

**R-34. Printed dates use one time zone.** plan-sheet prints the UTC date of `capturedAt`
(Q7); spatial-report and web print America/New_York. A capture at 21:00 New York would show two
different dates on the sheet and the report. Binding: PlanExport formats every printed date in
`America/New_York` (constant `ChapterBrand.printTimeZone`, deterministic, `TimeZone(identifier:)`
works on Linux), the same default as `REPORT_TIME_ZONE`. Owner question Q-G confirms the zone.

**R-35. One room fill rule.** plan-sheet §3.4.1 (label substrings incl. "shower", "toilet", "wc",
"study", "bed"; type; objects) and spatial-report §7.4 step 3 (type first, then objects, then
whole-word labels without "shower") classify a renamed "Shower" differently (the Oct 18 rename
feature, Closet → Shower). Binding: plan-sheet §3.4.1 is the rule, plus "outdoor when the capture
mode is `exterior`" from spatial-report. The Swift parity goldens (spatial-report §11.2) add
`fillClass` per room so the TS port must match.

**R-36. Drawing orientation may differ by a quarter turn** between the sheet (FloorPlanSquaring +
quarter turn chosen to fit the Tabloid frame) and the report (dominant-angle squaring only).
Accepted: both arrows are correct by R-7. Not a defect; testers should not file it.

### 2.11 Before you leave and the overview

**R-37. Overview "Field controls" subtitle.** phone-capture §3.5.1's join rule would print
"Floor to floor, 1 landmark and Floor 2 set missing" for the drawn state, but the artboard and
phone-capture's own test T-O1 say "Floor to floor and 1 landmark missing" while the Floor 2 row
says "controls missing". Binding: the overview Field controls subtitle lists **between-floor gaps
only** (floor to floor, landmarks; join rule unchanged); per-floor gaps are shown on the floor
rows; when only per-floor gaps exist the subtitle is `Missing on {labels joined " and "}` (two) /
`{A}, {B} and {C}` (three). Before you leave keeps phone-field's full compact list (drawn).

**R-38. Skipped rooms wording.** The overview passing subtitle is `All rooms scanned`
(phone-field's v2 term on Before you leave), not "No rooms skipped".

**R-39. Before you leave entry points.** `BeforeYouLeaveView` gains `focus: ChecklistItemID?`
(scroll to the item and flash its background `nude` for 0.6 s); the overview's Compass and Rooms
not scanned rows use it; `onFinish` calls `reviewPackage(canFinish:)` (Package ready or Revision n).

---

## 3. Gaps and underspecified parts (fixed in the addenda)

| # | Gap | Fix (addendum) |
|---|---|---|
| G-1 | No spec says what the field screens do **after sealing** (overview rows "stay tappable; the field screens decide"). | phone-field: `isReadOnly` mode when the visit is sealed and not in revision mode: no Save / Take photo / Add / All rooms scanned; footnote `Revision {n} is sealed. To change it, use Add to this capture on the verdict screen.` |
| G-2 | Field controls under `ChecklistPolicy.standard` (the shipping policy) have no overview wording; the drawn "controls complete / missing" assumes the manual policy. | phone-capture: floor-row word from FieldRules `ControlsList`: manual → complete / incomplete / missing; standard → `controls from the scan` when every A, B and ceiling row has a tape or scan value, else `controls optional`. Owner question Q-A. |
| G-3 | The fixture generator still writes `plan.pdf`. | T0 renames to `plan-sheet.pdf` (R-19). |
| G-4 | `BeforeYouLeaveView` has no focus parameter, but the overview needs it. | R-39. |
| G-5 | Revision mode had no checklist gate. | R-25. |
| G-6 | `ReportSummary.floors`, `checksPage` and `report.status` had no producer. | R-14. |
| G-7 | The web has no source for "answers limitation i". | web-review addendum: map `answersNextAction` → first limitation finding with that next action → its index in `verdict.limitations`. |
| G-8 | The station Station-card "Registered" semantics differ from the phone. | R-16. |
| G-9 | PlanExport and the station both need Inter; the station converts the **web** WOFF2 subset, which lacks the WinAnsi letters Š š Ž ž Ÿ ƒ. | spatial-report: `pdfSafeText` maps them to S s Z z Y f; test with an address "Šibenik". |
| G-10 | Several tracks edit `ReplayFlowUITests.swift`, `Info.plist`, `DESIGN.md`, `ios.yml`. | single owners in `00-tracks.md`. |
| G-11 | `StationProjectProvider.listing()` (phone-capture) lives in `StationQueries.swift`, which phone-package rewrites. | phone-capture: new AppCore file `StationProjectListing.swift`. |
| G-12 | The compass station check makes every existing package Limited the day the station deploys (station ships before the app). | owner question Q-B, recommended default limits the limitation to 1.1.0 records. |
| G-13 | `NoRoomsSkippedConfirmation` must become `Codable` for `visit.json`; phone-field lists the file as unchanged. | phone-field (owner of FieldKit) adds `Codable`. |
| G-14 | Revision n+1 base captures and the compass: not stated. | compass addendum: base captures keep their stored fields; only new captures carry new readings; "Restart this floor instead" (phone-capture) discards the reading like Try again. |
| G-15 | Contract validators in Swift (`CaptureTestSupport/SchemaValidator.swift`, PackageKit's test `SchemaValidator.swift`) fail on `exclusiveMaximum`; the regenerated examples break those packages' tests the moment T0 lands. | T0 owns those two one-keyword edits. |
| G-16 | Device test D1 (capture frame = ARKit world) gates the whole compass UI but has no owner or slot. | phone-capture-core track (T7) runs D0/D1 first and owns `docs/qa/compass-device-tests.md`. |

---

## 4. Specs against the owner decisions (Oct 21)

| Decision | Finding | Status |
|---|---|---|
| Real logo, never the typed "chapter / RENOVATION" | All specs use `chapter-logo.svg` / `ChapterLogo` (phone, sheet, report) and the HUB `chapter-wordmark.svg` (web). No spec builds the typed wordmark. | OK |
| Inter everywhere; Times stays for display titles; mono stays mono | Phone: Inter + Times large titles + SF Mono (OK). Sheet: Inter/Times-Roman/Times-Italic/Courier (OK). Report: Inter/Times-Roman/Courier (OK). Web: Inter only, no Times (HUB headings are sans; OK). Fault: phone-field registered Inter through `UIAppFonts` in the app target, contradicting phone-capture (fixed R-17; not an owner conflict). | OK after R-17 |
| Web in HUB DS as drawn, Inter, self-hosted | web-review is faithful, but it **departs from the drawing** in four places where the data exists after all: revision 2 on the phone (R-30), "answers limitation" (R-30), "Tabloid · 1 sheet" (R-32), "PM [NAME]" when available (R-33). Restored. Remaining deviations (pure white wordmark, Inter 600 for HUB 700, "drawing to scale" instead of "1:50 drawing", "compare a download with its SHA-256") are data or truth constraints and stay. | fixed |
| Plan sheet on the phone, no verdict; spatial report on the station; phone writer and `spatial_report_pdf` retire | All agree; ownership of the retirement was claimed three times (R-11). | fixed |
| Compass at the start of each floor's scan, 3 states, ±10° / ±30° | All agree on thresholds; phone-capture invented its own reading algorithm and texts (R-20). | fixed |
| Tabloid 11 × 17 | plan-sheet OK. | OK |

---

## 5. Questions only the owner can answer (with the default the build uses)

| # | Question | Default |
|---|---|---|
| Q-A | **Field controls policy.** The v2 drawings (2d, 2b) treat tape/laser controls as required and blocking ("4 of 9 required", "Tape or laser only. Never copy numbers from the scan.", red rows). Your Oct 18 decision made the scan values sufficient (`ChecklistPolicy.standard`, shipping today). Which one ships? | Keep `ChecklistPolicy.standard`; both renderings are built and one constant switches (phone-field Q1). Overview wording per G-2. |
| Q-B | **Does a missing or poor compass reading make a package Limited?** compass Q2 adds the station rule `orientation.compass` as a limitation. Because the station ships before the app, every package captured with today's app would become Limited. | Limitation only when the capture record is 1.1.0 (the app could have recorded a reading). A 1.0.0 record gives check status `not_applicable` with an info finding "No compass reading recorded; orientation not verified" (the drawn sample's wording), so older packages keep their verdict. |
| Q-C | **HUB data.** Does the HUB give the station the project manager (name, phone) and the web URLs of a deal and of its Files folder? | Optional fields and config; "Call the PM" only discards the draft, "PM [NAME]", "Open in the HUB" and the Files link are hidden until set. |
| Q-D | **Who reads the spatial report** (plan-of-changes Q1)? It decides whether reduced site photos go into the HUB copy. | As drawn: photo pages included, EXIF and GPS stripped (spatial-report Q9). |
| Q-E | **Package record pages** at the end of the report (not drawn, needed by F9 AC2). | Add them (spatial-report Q1). |
| Q-F | **A floor too big for the Tabloid sheet** (plan-of-changes Q2). | Ladder 1:50 → 1:100 → 1:200 (→ 1:500 exterior), then clip with a footnote (plan-sheet Q4). |
| Q-G | **Time zone of printed dates.** | America/New_York on the sheet, the report and the web (R-34). |
