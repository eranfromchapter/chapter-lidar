# Build spec · phone-package · Phone package v2 (F6)

Area key: `phone-package`. Artboard 2f `canvas/app-package-v2.dc.html` (to build); v1 is 2e
`canvas/screen-package.dc.html` (built today in `ios/App/Sources/App/Views/PackageScreens.swift`).
Written Oct 21, 2026 for the repo `chapter-lidar`, branch `feat/floorplan-report`.

This spec is complete on its own: every value below was read from the artboard source, the screen
tokens v2 artboard (2k `screen-tokens-v2.dc.html`), the plan-of-changes pages and the current code.
Nobody needs to open the bundle again.

---

## 0. Scope and binding decisions

In scope:

1. **Package ready** (revision 1): the real file list, no Spatial Report PDF.
2. **Package status**: Uploading (active), Paused (offline / station not answering), Uploaded
   (waiting for checks), Checks delayed, **Upload stopped** (fatal failure, re-seal as revision 2).
3. **Verdict received**: status only (word + shape, one sentence, next visit, station timeline),
   **Open in the HUB**, **Add to this capture**.
4. **Revision n** review (drawn as "Revision 2"): what changed, what is unchanged, seal revision n.
5. The local notification "verdict received" and the background refresh that feeds it.
6. Retiring the phone's Spatial Report: `SpatialReportWriter` and file role `spatial_report_pdf`
   (contract, PackageKit, PlanExport, AppCore, station checks and HUB publication, web, fixtures).
7. The station/contract additions these screens need (timeline, publication, links, carry-over of
   unchanged files for revision n, optional "revision in progress" notice).

Out of scope (other areas; see section 12): Captures home and Capture overview screens, the
navigation stack, compass recording, the plan sheet itself, the station spatial report, the web
review pages, the bundling of Inter into the app.

Owner decisions applied (Oct 21, 2026, binding):

| # | Decision | Effect here |
|---|---|---|
| 1 | Real Chapter logo and Inter everywhere; Inter replaces SF on phone screens; Times stays for display titles; mono stays mono | Every text on these screens is Inter (Regular 400 / SemiBold 600) except the large title, which is Times New Roman. No wordmark is drawn on these screens. |
| 2 | Web review in the HUB design system as drawn | The phone's "Open in the HUB" opens the HUB (or the review page); web pages themselves are `web-review`. |
| 3 | Plan sheet made on the phone (no verdict); spatial report made on the station after checks; the phone's `SpatialReportWriter` and role `spatial_report_pdf` retire; compass per floor with 3 states; Tabloid plan sheet | Package file list has no Spatial Report PDF; the info note says "The station makes the spatial report."; the Capture record row reports the compass. |

Design decisions from the plan of changes that this screen must honour (2f caption, plan-screens §2):
"Phone shows status, not verdict detail. The 'example verdict' card goes." · "statuses that were a
glyph only get word and shape" · "'Add more rooms' becomes 'Scan another floor or room'".

---

## 1. What changes from v1 (summary)

| v1 (built) | v2 (to build) |
|---|---|
| Title "Package ready" Times 30 | Large title Times New Roman 34/41 (owner: Times for display titles), nav row with Back and "Step 3 of 3" |
| Subtitle "618 Valley Street · 2 floors · revision 1" | "618 Valley Street · 2 floors · revision 1 · 74 files · 768 MB" |
| One card: per-floor block with a long kinds line incl. "Spatial Report PDF" | Two cards: (a) Original Exports per floor as disclosure rows with 3 sub-rows, (b) Site Photos, Field Measurements, **Capture record (compass)**, Source Register |
| Note "…changes create revision 2." | "…later changes create revision 2. The station makes the spatial report." |
| "Review before you upload" scan list on this screen | Removed from this screen (the scan viewer moves to the floor rows of Capture overview, `phone-capture`) |
| Buttons "Add more rooms" (outline) + "Seal and upload" (56 pt) | "Scan another floor or room" (tinted) + "Seal and upload" (primary), both 52 pt |
| Uploading: "New capture" button in the header | Back to Captures home; right label "Revision 1 · sealed"; subtitle with files and size |
| Category rows "Plans and reports", "● Verified" | "Plans and record", glyph + "Confirmed", "Uploading · 41%", glyph + "Waiting" |
| Station: glyph-only list, "Checks queued", "Published to the HUB" never done | Grouped card with times: Registered 14:02 · Checks "After upload" · Verdict "—" · Published to the HUB "—", driven by new station fields |
| Example verdict card on the Uploading screen | Removed. A separate **Verdict received** screen |
| No revision 2 on the phone (`VisitFlowError.alreadySealed`) | **Add to this capture** → changes → **Revision 2** screen → seal revision 2; unchanged files are not uploaded again |
| Fatal upload error shown as caption only | **Upload stopped** state with Try again / Re-seal as revision 2 |

---

## 2. Shared visual rules for the four screens

### 2.1 Frame

- Drawn on an iPhone 402 × 874 pt frame (iPhone 16 Pro / 17 Pro). The artboard's `padding-top: 62px`
  is the top safe area; `padding-bottom: 42px` under the buttons is the 34 pt home-indicator safe
  area + 8 pt. Build against safe areas, not fixed numbers.
- Screen background (ground) `#F5EFE6`, full bleed. Light appearance only (Info.plist
  `UIUserInterfaceStyle` stays Light, as today).
- Horizontal page gutter 16 pt (v1 used 20; v2 uses 16 on every screen).
- Layout per screen: **header block** (fixed) · **content** (a vertical `ScrollView`; the artboard's
  `flex: 1; overflow: hidden` becomes scrolling) · **footer** (buttons, pinned with
  `safeAreaInset(edge: .bottom)`, background ground `#F5EFE6`). Content scrolls under nothing; the
  footer has no divider line.
- iPad (the app target allows family 1,2): same layout, content column `maxWidth: 600`, centred.

### 2.2 Header block

`VStack(spacing: 8)`, padding top 0 (below the safe area), horizontal 16:

1. **Nav row**, height 44, `HStack` space-between:
   - Back button 44 × 44: circle radius 22, fill `rgba(250,245,238,0.8)` (`#FAF5EE` at 80 %),
     stroke 0.5 pt `rgba(0,0,0,0.06)`, shadows `0 1 3 rgba(0,0,0,0.07)` and `0 3 10 rgba(0,0,0,0.06)`;
     chevron 12 × 20 pt, path `M10 2 L2 10 L10 18` (drawn `M10 2L2 10l8 8`), stroke `#1F2429` 2.5 pt,
     round caps and joins. Accessibility label "Back" (Captures home targets: "Back to captures").
     If `phone-capture` hosts these screens in a `NavigationStack`, use the system back button
     instead (on iOS 26 it is this 44 pt glass pill); the custom drawing above is the fallback for
     iOS 17–25. Deployment target stays iOS 17.
   - Right label: Inter Regular 13, `#6B6557` (muted), one line, tail truncation.
2. **Large title**: Times New Roman Regular 34 pt, line height 41, colour ink `#1F2429`, header trait.
   (The artboard draws SF Pro Bold 34/41 with tracking 0.4; the owner's "Times stays for display
   titles" replaces it: Times New Roman Regular, tracking 0.) Up to 2 lines, tail truncation.
3. **Subtitle**: Inter Regular 15, muted `#6B6557`; line height 20 where it wraps (Revision screen);
   up to 3 lines.

### 2.3 Type (Inter replaces SF; Dynamic Type on)

| Token (artboard) | Use here | Font |
|---|---|---|
| large title 34/41 | screen titles | Times New Roman Regular 34, `relativeTo: .largeTitle` |
| body 17 | row titles, button labels | Inter Regular 17, `relativeTo: .body` |
| body 17 semibold | group rows ("Original Exports · Floor 1", "Site Photos"), primary button, progress bytes | Inter SemiBold 17 |
| verdict word 20 semibold | "Limited" in the verdict card | Inter SemiBold 20, `relativeTo: .title3` |
| subhead 15 | details right, subtitles, sub-rows, status words | Inter Regular 15, `relativeTo: .subheadline` |
| footnote 13 / 17 | notes, footnotes, row subtitles, section headers, nav right label | Inter Regular 13, line height 17, `relativeTo: .footnote` |

Fonts come from `ChapterTokens.Typography` (the `screen-tokens` area bundles full-coverage Inter
Regular and SemiBold `.ttf`/`.otf` into the app; the WinAnsi subsets embedded in PlanExport's
`ChapterBrandAssets` are for PDFs only and lack "→"). Numbers that change while visible (progress
bytes, percent, times) use `.monospacedDigit()`.

Characters used: middle dot U+00B7 with spaces (" · "), right arrow U+2192 ("75 → 83 entries"),
em dash U+2014 ("—"), ellipsis U+2026 ("Sealing…"), ASCII ' and " for feet-inches.

### 2.4 Colours (all existing tokens unless marked new)

| Name | Hex | Use |
|---|---|---|
| ink | `#1F2429` | text, primary button fill, progress fill |
| ground | `#F5EFE6` | screen background |
| surface | `#FAF5EE` | cards, primary button text |
| nude | `#E8DDD0` | separators, tinted button fill, info note fill, progress track |
| line | `#D9CCBC` | card stroke 1 pt, disabled button fill |
| muted | `#6B6557` | secondary text, waiting ring |
| ready | `#2E5E2E` | ● glyph and word, plus glyph fill |
| limited | `#9A6A1E` (text `#7A5214`) | ▲ glyph / word, verdict border |
| blocked | `#8B2E2E` | ■ glyph / word / error text, verdict border |
| chevron (existing `scanPlaceholder`) | `#B9AFA2` | disclosure chevron |
| disabledText (**new token**) | `#4E493F` | disabled button text |

Never colour alone: every status has a word and a shape.

### 2.5 Components

- **Grouped card**: fill `#FAF5EE`, stroke 1 pt `#D9CCBC`, corner radius 12, content clipped.
  Rows separated by a 1 pt `#E8DDD0` line across the full card width (no inset).
- **Section**: `VStack(spacing: 6)`: header (Inter 13, muted, UPPERCASE via `.textCase(.uppercase)`,
  no tracking, horizontal padding 16) · card · optional footnote (Inter 13/17 muted, padding 0 16).
- **Row**: `HStack(spacing: 12)`, horizontal padding 16, min height per screen (given per row
  below), vertical alignment centre. Title flexible (`.frame(maxWidth: .infinity, alignment:
  .leading)`), detail trailing.
- **Two-line row**: title 17 over subtitle 13 muted, `VStack(spacing: 2)`.
- **Status glyphs** (10 × 10 pt, viewBox 0 0 10 10), placed before the word with spacing 5:
  - ● done/confirmed/ready: circle centre (5,5) r 4.5, fill `#2E5E2E`.
  - ▲ limited/partly/delayed: path `M5 0.6 L9.6 9.4 L0.4 9.4 Z`, fill `#9A6A1E`; word in `#7A5214`.
  - ■ blocked/stopped: rect (0.6, 0.6, 8.8, 8.8), fill `#8B2E2E`; word in `#8B2E2E`.
  - ○ waiting/pending: circle r 4, no fill, stroke `#6B6557` 1.2 pt; word in `#6B6557`.
  - The same shapes at 14 × 14 pt in the verdict card.
- **Plus glyph** (added item): 22 × 22 circle `#2E5E2E`, two bars `#FAF5EE` 10 × 2 and 2 × 10,
  centred. **Equals glyph** (changed item, new, not drawn): 22 × 22 circle `#1F2429`, two bars
  `#FAF5EE` 10 × 2, 2 pt apart, centred. **Minus glyph** (removed item, new, not drawn): 22 × 22
  circle `#8B2E2E`, one bar `#FAF5EE` 10 × 2. Accessibility: "Added", "Changed", "Removed".
- **Disclosure chevron**: 8 × 14, path `M1 1 L7 7 L1 13`, stroke `#B9AFA2` 2 pt, round caps/joins.
- **Info note** (lock): `HStack(alignment: .top, spacing: 10)`, padding 10 vertical × 14
  horizontal, radius 12, fill `#E8DDD0`, text Inter 13/17 ink. Lock icon 16 × 16, stroke `#1F2429`
  1.5 pt, no fill: rect (3, 7, 10, 7) radius 1.5 and path `M5 7 V5 a3 3 0 0 1 6 0 v2`; top margin 1.
- **Buttons** (footer `VStack(spacing: 10)`, padding top 12, horizontal 16, bottom 8 above the
  safe area):
  - Primary: height 52, radius 12, fill `#1F2429`, text `#FAF5EE` Inter SemiBold 17.
  - Tinted: height 52, radius 12, fill `#E8DDD0`, text `#1F2429` Inter Regular 17.
  - Disabled (either): fill `#D9CCBC`, text `#4E493F` Inter SemiBold 17.
  - Full width, `.buttonStyle(.plain)`, pressed state opacity 0.7.
- **Progress bar**: height 8, radius 4, track `#E8DDD0`, fill `#1F2429`; `accessibilityHidden`
  (the bytes text carries the value).
- **System alert** (tokens v2): 270 pt, title 17 semibold, message 13, two 44 pt buttons. Use
  SwiftUI `.alert`.

### 2.6 Formatting

- Bytes: decimal units, `ByteText` as today: "768 MB", "188 MB", "3.2 MB", "512 of 768 MB" (both
  numbers in the unit of the total).
- Percent: `floor(fraction × 100)` + "%": "67%", "41%".
- Times: 24-hour `HH:mm` in the phone's time zone ("14:02"); locale fixed `en_US_POSIX`.
- Dates: "MMM d, yyyy" ("Jan 25, 2025"); short "MMM d" ("May 16").
- Lengths (revision rows): mm with comma thousands and ft-in with ASCII marks, "2,490 mm · 8' 2"",
  from FieldKit `LengthFormatter` v2 (owned by `phone-field`; today it prints "2 490 mm · 8′ 2″").
- Plurals: "1 file / 2 files", "1 control / 9 controls", "1 entry / 74 entries", "1 photo / 3
  photos", "1 limitation / 2 limitations", "1 blocker / 2 blockers".
- Capture count text (`CaptureCountText`): counts by mode, in this order, joined with " and ":
  floor → "1 floor" / "2 floors", room → "1 room" / "2 rooms", exterior → "1 exterior" /
  "2 exteriors". Examples: "2 floors", "1 floor and 1 room".

---

## 3. Screen A · Package ready (revision 1)

Reached from Capture overview's review button (`phone-capture`) after "Before you leave" passes.
`VisitStep.packageReady`. Revision 2 and later never show this screen (they show Screen D).

### 3.1 Layout and strings (normal state, 2 floors)

Header:
- Back → Capture overview. Right label: **"Step 3 of 3"**.
- Title: **"Package ready"**.
- Subtitle: **"{address} · {captureCountText} · revision 1 · {files} files · {size}"**, e.g.
  "618 Valley Street · 2 floors · revision 1 · 74 files · 768 MB".
  `files` = manifest entry count of the draft (the manifest itself is not counted, it does not list
  itself); `size` = sum of the draft files' bytes.

Content (`VStack(spacing: 10)`, padding top 10, horizontal 16):

**Card 1 · Original Exports** (one disclosure group per capture, in capture order):

- Group header row, min height 46, padding 0 16:
  - Title **"Original Exports · {capture.label}"**, Inter SemiBold 17 (e.g. "Original Exports · Floor 1").
  - Detail **"{n} files · {size}"**, Inter 15 muted (e.g. "13 files · 312 MB"); n = every file of
    that capture except photos; size = their bytes.
  - Collapsed: chevron (2.5) at the trailing edge. Expanded: no chevron (as drawn).
  - Separator above every group header except the first.
- Sub-rows when expanded (only rows that have files), each min height 32, padding leading 32,
  trailing 16, separator above, text Inter 15 ink (flexible), count Inter 13 muted:

  | Sub-row | Roles counted | Label rule | Drawn example |
  |---|---|---|---|
  | Plans | `plan_dxf`, `rooms_csv`, `plan_pdf`, `plan_png`, `plan_svg` | parts joined " · ": "Plan DXF" · "rooms CSV" · "plan sheet " + present of [PDF, PNG, SVG] joined ", " | "Plan DXF · rooms CSV · plan sheet PDF, PNG, SVG" · 5 |
  | Meshes | `mesh_glb`, `mesh_obj`, `mesh_mtl`, `texture` | "Mesh GLB" (if GLB) · "OBJ + MTL" (OBJ with MTL) or "OBJ" · "textures" (if any); when no GLB the first part is "Mesh OBJ + MTL" | "Mesh GLB · OBJ + MTL" · 4 in the mock-up |
  | Point cloud and raw | `point_cloud_las`, `raw_roomplan_json`, `raw_depth`, `capture_model` | "Point cloud LAS" (if LAS) · "raw RoomPlan + depth" / "raw RoomPlan" / "raw depth" · "capture model" (if present) | drawn "Point cloud LAS · raw RoomPlan + depth" · 4 |

  Counts are the real number of files. The phone writes no `texture` today and always writes a
  `capture_model`, so a real floor reads "Mesh GLB · OBJ + MTL · 3" and "Point cloud LAS · raw
  RoomPlan + depth · capture model · 4". (The mock-up's 5 / 4 / 4 = 13 are illustrative. See open
  question Q3.) A capture without a scene mesh has no Meshes sub-row (never invented).
- Behaviour: accordion. The first capture starts expanded, all others collapsed. Tapping a
  collapsed header expands it and collapses the open one; tapping the expanded header collapses it
  (then it shows the chevron). Animation `.easeInOut(duration: 0.2)`. The whole header row is the
  tap target (min 46 pt). Accessibility: header is a button, label "Original Exports, Floor 1, 13
  files, 312 megabytes", value "expanded"/"collapsed", hint "Shows the file kinds".
  Identifier `package.floor.{areaKey}`; sub-rows `package.floor.{areaKey}.plans|meshes|raw`.

**Card 2 · the rest** (rows min height 42, padding 0 16, title Inter SemiBold 17, detail Inter 15
muted, separators between rows, not tappable):

| Row title | Detail | Rule |
|---|---|---|
| "Site Photos" | "42 · 188 MB" | "{photoCount} · {photoBytes}"; zero photos: "none" |
| "Field Measurements" | "9 controls" | distances + ceilingHeights + openings + floorToFloor + landmarks; zero: "no controls" |
| "Capture record" | "compass: Floor 1 only" | compass text, 3.3 |
| "Source Register" | "manifest · 74 entries" | "manifest · {entries} {entry/entries}" |

**Info note** (2.5): **"Every file is fingerprinted (SHA-256). Sealing makes the package
read-only; later changes create revision 2. The station makes the spatial report."**
(`revision + 1` is always 2 on this screen.)

Footer:
- Tinted **"Scan another floor or room"** → `VisitFlow.addMoreRooms()` (today's "Add more rooms":
  plan discarded, capture model to "What are you scanning?" with the same project and confirmed
  address). Identifier `package.scanAnother`.
- Primary **"Seal and upload"** → 3.4. Identifier `package.seal`.

### 3.2 States

| State | What shows |
|---|---|
| Building (plan being written, `VisitModel.isBuilding`) | Header as normal but the subtitle shows "{address} · {captureCountText} · revision 1"; content replaced by a centred `ProgressView` with label "Writing plans and 3D files…" (Inter 15 muted). Primary button disabled (2.5), tinted button enabled. |
| Build failed (`VisitPackageError`) | Content shows a card with a ■ row: Inter 15 `#8B2E2E`, text = the error's description (e.g. "The plans of Floor 2 could not be written: …"), then footnote "Nothing was sealed. Scan the floor again or try again." and a tinted button "Try again" inside the content (calls new `VisitModel.rebuildPlan()`, which runs the builder again with no flow transition). Primary disabled. |
| Ready | 3.1. |
| Sealing | Primary label "Sealing…", disabled style; tinted disabled; back disabled. |
| Seal failed (`PackageAssembler` threw) | Under the info note: ■ glyph + Inter 13/17 `#8B2E2E` "The package could not be sealed: {reason}. Nothing was uploaded. Try again." Buttons enabled again. (Replaces today's bottom toast for this screen.) |
| One capture | Only one group (expanded, no chevron), subtitle "1 floor". |
| Many captures (3+) | All groups listed; content scrolls. |

### 3.3 Compass text (Capture record row)

Per capture, the compass state is computed by the shared `CompassState.of(capture)` (defined with
the capture-record compass fields by `north-arrow`/`phone-capture`): **verified** (true heading,
accuracy ±10° or better), **approximate** (±10° to ±30°, or magnetic only), **not verified** (no
reading, worse than ±30°, rejected, or the fields are missing). A capture "has a reading" when it
is verified or approximate.

| Captures with a reading | Text |
|---|---|
| all, and there is 1 capture | "compass: recorded" |
| all, 2 or more captures | "compass: every floor" |
| some | "compass: {labels joined ", "} only", e.g. "compass: Floor 1 only", "compass: Floor 1, Floor 3 only" |
| none | "compass: not recorded" |

Until the compass feature ships every capture lacks the fields, so the row reads "compass: not
recorded".

### 3.4 Seal and upload

1. `VisitModel.sealAndUpload()` (exists): assemble with `PackageAssembler` into
   `packages/<packageId>/`, `VisitFlow.sealed()`, start the `UploadCoordinator`.
2. After the first successful seal on this phone, request notification permission once
   (`UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound])`); the answer is
   remembered by iOS.
3. Navigate to Screen B for this package.

---

## 4. Screen B · Package status (Uploading · Paused · Uploaded · Upload stopped)

One screen `PackageStatusView(packageId:)` that renders the package's `UploadSnapshot` +
`StationStatus`. When a verdict arrives it switches itself to Screen C (same route). Entry points:
after sealing; the Captures home "In progress" row (`phone-capture`, see 12); a notification tap
before the verdict.

### 4.1 Layout and strings (drawn state: paused offline)

Header:
- Back → Captures home. Right label: **"Revision {n} · sealed"** ("Revision 1 · sealed").
- Title: **"Uploading"** (other titles per state, 4.3).
- Subtitle: revision 1: **"{address} · {files} files · {size}"** ("618 Valley Street · 74 files ·
  768 MB"). Revision n ≥ 2: "{address} · revision {n} · {k} new or changed files · {size of k}"
  (k and size from 6.4; when the station carried files over, those are not counted).

Content (`VStack(spacing: 14)`, padding top 14, horizontal 16):

**Progress card** (grouped-card style, padding 14 vertical × 16 horizontal, `VStack(spacing: 8)`):
- Row space-between, Inter 17: **"{done} of {total} MB"** SemiBold left ("512 of 768 MB"),
  **"{pct}%"** Regular right ("67%").
- Progress bar (2.5), value = fraction.
- Caption Inter 13/17 muted (state text, 4.3), e.g. **"Paused: no connection. Resumes on its own.
  You can close the app."**
- Bytes counted as today (`UploadProgressSummary.make`): verified and uploaded files count fully;
  pending/sending count their staged blocks. For revision n ≥ 2, files the station reported as
  carried over (5.3) are excluded from both `done` and `total`.

**Section "Files"** (header "FILES"), card with one row per category that has files, in this
order, rows min height 48, title Inter 17 ink, status Inter 15:

| Row title | Roles |
|---|---|
| **"Plans and record"** (renamed from "Plans and reports") | `capture_record`, `field_controls`, `capture_model`, `raw_roomplan_json`, `plan_dxf`, `rooms_csv`, `plan_pdf`, `plan_png`, `plan_svg`, and legacy `spatial_report_pdf` (only in packages sealed by older builds) |
| **"Site photos"** | `photo` |
| **"Meshes"** | `mesh_glb`, `mesh_obj`, `mesh_mtl`, `texture` |
| **"Point clouds"** | `point_cloud_las`, `raw_depth` |

| Category status | Shown | Rule |
|---|---|---|
| Confirmed | ● + **"Confirmed"** `#2E5E2E` | every file of the category `verified` by the station |
| Uploading | **"Uploading · {pct}%"** ink, no glyph | some file started (phase ≠ pending, or staged blocks, or a station check); pct = floor(category done bytes / category bytes × 100) |
| Waiting | ○ + **"Waiting"** muted | nothing started |
| Stopped (only in Upload stopped) | ■ + **"Stopped"** `#8B2E2E` | the category holds the file named by the fatal error, else the first non-confirmed category |

Identifiers `upload.category.plans|photos|meshes|pointClouds`; accessibility label "{title},
{status}" e.g. "Meshes, uploading, 41 percent".

**Section "Station"** (header "STATION"), card rows min height 44, `HStack(spacing: 12)`: glyph
10 pt · title Inter 17 · detail Inter 15. Pending rows draw title and detail in muted `#6B6557`;
done rows title ink, detail muted.

| Row | Pending | In progress | Done | Problem |
|---|---|---|---|---|
| Registered | ○ "Registered" · "When online" (no session yet) | — | ● "Registered" · "14:02" (`UploadState.registeredAt`, 9.2) | — |
| Checks | ○ "Checks" · "After upload" (stage uploading) | ○ "Checks" · "Queued" (`checks_queued`) / "Running" (`checking`) | ● "Checks run" · time of `checks.finishedAt` | ▲ "Checks" · "Delayed · the station retries" (`check_error`, word colour `#7A5214`) |
| Verdict | ○ "Verdict" · "—" | — | outcome glyph + "Verdict · {Word}" · time of `verdict.evaluatedAt` | — |
| Published to the HUB | ○ "Published to the HUB" · "—" | ○ "Published to the HUB" · "Publishing" (verdict ready, publication `pending`/`publishing`) | ● "Published to the HUB" · time of `publication.publishedAt` | ▲ "Published to the HUB" · "Not yet" (`publish_failed`) |

Times: the first done row shows "HH:mm" if it is today, else "MMM d · HH:mm"; each later row shows
"HH:mm" when on the same local day as the row above, else "MMM d · HH:mm".
Identifiers `station.registered|checks|verdict|published`; accessibility label "{title}, {done |
not yet | delayed}, {detail}" (e.g. "Registered, done, 14:02"; "Checks, not yet, after upload").

**Footnote** (Inter 13/17 muted, padding 0 16) under the Station card: **"Files stay on this phone
until the station confirms each one. You will get a notification with the verdict."** When
notifications are denied: "Files stay on this phone until the station confirms each one. Open the
app to see the verdict."

Footer: none in Uploading / Paused / Uploaded / Checks delayed (the v1 "New capture" button is
removed; Captures home has "New capture").

### 4.2 Upload stopped (fatal) — layout additions

- Title **"Upload stopped"**.
- Progress card caption becomes two blocks:
  1. ■ glyph (10 pt, top-aligned, margin top 3) + Inter 13/17 `#8B2E2E`: the fatal message (from
     `UploadErrorKind.fatal`, e.g. "plan.pdf changed on the phone after sealing. It was not
     uploaded." / "The station refused the upload (409 package_conflict)." / "The storage service
     refused a file (403 AuthorizationFailure).").
  2. Inter 13/17 muted: **"Nothing was deleted. Try again, or re-seal to upload the files as they
     are on this phone now as revision {n+1}. Revision {n} stays on this phone."**
- Files rows: the affected category shows ■ "Stopped".
- Footnote: "Files stay on this phone until the station confirms each one."
- Footer:
  - Tinted **"Try again"** → `UploadCoordinator.retry()`. Identifier `upload.retry`.
  - Primary **"Re-seal as revision {n+1}"** → alert. Identifier `upload.reseal`.
- Alert: title **"Re-seal as revision {n+1}?"**, message **"The app builds revision {n+1} from the
  scans, photos and controls on this phone and uploads it. Revision {n} stays on this phone and is
  not uploaded further."**, buttons **"Cancel"** (cancel role) and **"Re-seal"** (default).
- On "Re-seal": primary shows "Sealing…" (disabled); the app builds a **full** draft from the
  visit workspace (not a carry-over, the sealed files may be the problem) with `revision = n+1`,
  `supersedesPackageId = revision n`, assembles, cancels revision n's coordinator, writes
  `supersededBy` into revision n's upload state (9.2) and opens Screen B for revision n+1. Failure:
  ■ caption "The package could not be sealed: {reason}. Nothing was uploaded." and buttons back.
- If the visit workspace no longer holds the originals (moved/removed), the primary button is
  hidden and the muted line reads "Nothing was deleted. Try again. This phone no longer has the
  scans to re-seal; start a new capture."

### 4.3 State table (title, caption, footer)

| Snapshot | Title | Caption | Footer |
|---|---|---|---|
| `starting`/`uploading`, files not all confirmed | "Uploading" | "Uploads continue in the background. You can close the app." | — |
| `waitingToRetry(.offline)` (**new reason**) | "Uploading" | "Paused: no connection. Resumes on its own. You can close the app." | — |
| `waitingToRetry(.stationUnavailable)` (5xx, 408, 429, blob 5xx) | "Uploading" | "Paused: the station is not answering. Resumes on its own. You can close the app." | — |
| `signInRequired` | (the app shows the sign-in screen, as today; returning shows this screen) | "Sign in again to continue the upload." | — |
| `confirmed`, no verdict yet | "Uploaded" | "The station has every file. Checks run next." | — |
| stage `check_error` | "Uploaded" | "The station has every file. Its checks are delayed; it retries on its own." | — |
| `failed(message)` | "Upload stopped" | 4.2 | Try again / Re-seal |
| verdict ready | → Screen C | | |

Offline vs station: `UploadErrorKind.of` splits `.transient` into `.transient(.offline)` for
`StationError.offline`, `URLError` codes `notConnectedToInternet`, `networkConnectionLost`,
`dataNotAllowed`, `internationalRoamingOff`, `cannotFindHost`, `cannotConnectToHost`,
`timedOut` and `BlobTransportError.network`; everything else transient is `.stationUnavailable`.

---

## 5. Screen C · Verdict received

Shown for a package whose verdict the phone has (live or cached, 9.3). Entry: Screen B switches
here; Captures home "Sealed" rows; notification tap.

### 5.1 Layout and strings (drawn: Limited)

Header:
- Back → Captures home. Right label **"Revision {n}"** ("Revision 1"); for a superseded revision
  **"Revision {n} · superseded"**.
- Title: **capture record `address.formatted`** ("424 West End Ave, Apt 4K"), Times 34/41, up to
  2 lines.
- Subtitle: **"Sealed {sealedAt MMM d, yyyy} · checked {evaluatedAt MMM d, yyyy}"** ("Sealed Jan
  25, 2025 · checked May 16, 2026"). `sealedAt` = manifest; `evaluatedAt` = verdict.

Content (`VStack(spacing: 10)`, padding top 10, horizontal 16):

**Verdict card**: padding 12 vertical × 16 horizontal, radius 12, fill `#FAF5EE`, **stroke 2 pt** in
the outcome colour, `VStack(alignment: .leading, spacing: 4)`:
- Line 1 `HStack(spacing: 8)`: 14 pt glyph + word, Inter SemiBold 20:

  | Outcome | Glyph | Word | Word colour | Border |
  |---|---|---|---|---|
  | ready | ● `#2E5E2E` | "Ready" | `#2E5E2E` | `#2E5E2E` |
  | limited | ▲ `#9A6A1E` | "Limited" | `#7A5214` | `#9A6A1E` |
  | blocked | ■ `#8B2E2E` | "Blocked" | `#8B2E2E` | `#8B2E2E` |

- Line 2 Inter 15 / line height 20, ink: the phone sentence. `task` = verdict `task` with its first
  letter lower-cased ("preliminary existing-condition plans"); L = `verdict.limitations.count`;
  B = findings with severity `blocker`:
  - ready: **"Ready for {task}. Details: spatial report in the HUB."**
  - limited: **"Usable for {task}, with {L} {limitation/limitations}. Details: spatial report in
    the HUB."** (drawn: "Usable for preliminary existing-condition plans, with 2 limitations.
    Details: spatial report in the HUB.")
  - blocked: **"Not usable yet for {task}: {B} {blocker/blockers}. Details: spatial report in the
    HUB."**
  - While publication is not `published`, the last sentence reads **"Details: spatial report in
    the HUB once it is published."**
- Accessibility: one element, label "Verdict: {Word}. {sentence}", identifier `verdict.card`.

**Section "For the next visit"** (header "FOR THE NEXT VISIT"), hidden when `nextActions` is empty:
- One row per `verdict.nextActions[i]` (station order), at most 3. Row min height 50, padding 5
  vertical × 16, two-line row:
  - Title Inter 17 ink, up to 3 lines: the next action **verbatim** (same words as the report and
    the web; e.g. "Scan or measure Primary closet on the next visit if it is in scope.").
  - Subtitle Inter 13 muted, up to 2 lines: the `measured` of the first finding with
    `nextAction == title` (e.g. "Primary closet: inaccessible"); if that finding has no
    `measured`, its `message`; if none matches, no subtitle.
  (The artboard's "Scan or tape-measure the primary closet" / "Not scanned · locked [PLACEHOLDER]"
  are mock-up wording; the phone never rewrites the station's words.)
- More than 3: footnote **"{m} more in the spatial report."**
- Identifiers `verdict.next.{i}`.

**Section "Station"** (header "STATION"), rows min height 40 (not 44 as on Screen B), same row
rules as 4.1 but without the Registered row:
- ● "Checks run" · "May 16 · 14:01" (first row shows the date)
- glyph "Verdict · Limited" · "14:02"
- ● "Published to the HUB" · "14:03" (or ○ "Publishing", or ▲ "Not yet")

Superseded revision: footnote under the Station card "Revision {m} replaces this revision." (m =
the newest revision on this phone).

Footer:
- Tinted, one of:
  - **"Add to this capture"** (latest revision, workspace present, no revision in progress) →
    5.2. Identifier `verdict.addToCapture`.
  - **"Continue revision {n+1}"** (a revision in progress exists, `revision-draft.json`) → Capture
    overview in revision mode.
  - hidden (superseded revision, or the workspace is not on this phone).
- Primary **"Open in the HUB"** → `UIApplication.shared.open(links.hub ?? links.review)` (Safari,
  so the operator's HUB sign-in applies). Hidden when the station returned no link. Identifier
  `verdict.openHub`.

### 5.2 "Add to this capture"

1. `VisitModel.reopenForRevision(base: SealedPackage)`: loads the workspace that holds the package
   (the package folder's grand-parent `Visits/<workspace id>/`), the base capture record (from the
   sealed package), the current field controls file, the photo store and `room-names.json`; writes
   `revision-draft.json` (9.2); `VisitFlow` enters revision mode (9.1).
2. Navigates to Capture overview (`phone-capture`) for revision n+1, whose review button leads to
   Screen D.
3. Best effort: sends the "next revision" notice (10.4) when online.

### 5.3 States

| State | Difference |
|---|---|
| Ready | Ready card; no "For the next visit" section. |
| Limited | as drawn. |
| Blocked | Blocked card; next visit rows; Captures home lists the package as "re-seal needed" (12). |
| Publication pending / publishing / failed | Published row ○ "Publishing" / ▲ "Not yet"; sentence variant; "Open in the HUB" still shown when `links.review` exists. |
| Offline | Shows the cached status (9.3); nothing else changes; Open in the HUB still opens Safari. |
| Verdict superseded at the station (checks re-run) | The coordinator keeps the newest `verdictId`; the card shows the newest. |

---

## 6. Screen D · Revision n (drawn "Revision 2")

Shown instead of Package ready when the visit is in revision mode and the operator reviews the
package (Capture overview's button). `VisitStep.revisionReady`.

### 6.1 Layout and strings

Header:
- Back → Capture overview. Right label: **address** ("424 West End Ave, Apt 4K").
- Title **"Revision {n}"** ("Revision 2").
- Subtitle (Inter 15/20 muted): **"You changed the capture after sealing revision {n-1}. Sealing
  again creates revision {n}. Revision {n-1} stays as it was; the station checks revision {n} from
  the start."**

Content (`VStack(spacing: 14)`, padding top 14, horizontal 16):

**Section "What changed"** (header "WHAT CHANGED"), card rows: change rows min height 56, padding
8 vertical × 16, `HStack(spacing: 12)`: glyph 22 (plus / equals / minus, 2.5) · two-line text.
Row order: new captures, room-name changes, field controls, photos, retired files, then the
Manifest row.

| Item | Glyph | Title | Subtitle | Drawn example |
|---|---|---|---|---|
| New capture | plus | capture label | "Scanned · {one room / whole floor / exterior} · {n} {file/files}" | "Primary closet" / "Scanned · one room · 5 files" |
| Room names changed in a sealed capture | equals | "{capture label} room names" | "{old} → {new}" (first two, then ", +{k} more") + " · {n} files" | — |
| New field control | plus | control title (6.2) | "Field control · {mm} · {ft-in}" | "Room 4 ceiling height" / "Field control · 2,490 mm · 8' 2"" |
| Changed field control | equals | control title | "Field control · changed to {mm} · {ft-in}" | — |
| New photos (one row per capture + room) | plus | "{n} {photo/photos}" | "{room} · {subjects}" — distinct subjects in order of first appearance, lower case, joined ", " | "3 photos" / "Primary closet · general, ceiling, opening" |
| Retired phone report (only when the base is a manifest 1.0.0 package) | minus | "Spatial report PDF from the phone" | "Retired · the station makes the spatial report · {n} files" | — |
| Manifest | none | **"Manifest"** (row min height 48, padding 0 16, title 17) | detail right Inter 15 muted **"{before} → {after} entries"** | "75 → 83 entries" |

Empty state (no change at all): the card holds one row (min 48) "Nothing changed since revision
{n-1}." Inter 17 muted, plus the Manifest row.

**Section "Unchanged"** (header "UNCHANGED"), one two-line row min height 52, padding 8 × 16:
- Title: "{labels of captures whose files are all carried over, joined: 'A', 'A and B', 'A, B and
  C'} {scan/scans}, {p} photos, {c} controls" — omit a part that is zero. Drawn: **"Floor 1 scan, 42
  photos, 9 controls"**.
- Subtitle: **"Same fingerprints as revision {n-1} · not uploaded again"**.
- Hidden when nothing is unchanged.
- Footnote under it: **"Only the {k} new files are uploaded. The station checks the whole package
  and issues a new verdict and spatial report."** — k = added files + changed files; when changed
  files > 0 the first sentence reads "Only the {k} new or changed files are uploaded."; k = 1:
  "Only the 1 new file is uploaded." (Drawn "Only the 8 new files are uploaded." The real
  capture-record.json and field-controls.json are "changed" whenever a capture or control is added,
  so the real text usually reads "new or changed".)

Footer:
- Tinted **"Keep editing"** → back to Capture overview (revision mode). Identifier `revision.keepEditing`.
- Primary **"Seal revision {n} and upload"** ("Seal revision 2 and upload") → seal (6.3).
  Identifier `revision.seal`. Disabled with label **"No changes to seal"** when k = 0.

### 6.2 Field control titles

| Kind | Title |
|---|---|
| distance | "{capture label} long distance {A/B}" |
| ceiling height | "{room} ceiling height" (drawn "Room 4 ceiling height") |
| opening | "{room} {opening label} width" |
| floor to floor | "Floor to floor, {lower label} to {upper label}" |
| landmark | "Landmark {label}" (subtitle "Field control · {n} floors") |

Values: the control's `measurement.valueMm` (opening: `width.valueMm`) through `LengthFormatter`
v2 (2.6).

### 6.3 Seal revision n

1. Build the revision draft (9.4) on a background task; show "Sealing…" on the primary button.
2. Assemble with `PackageAssembler` into `packages/<new packageId>/` (APFS `copyItem` clones the
   carried-over files: no extra space).
3. `VisitFlow.sealed()`; delete nothing; `revision-draft.json` gets `sealedPackageId`.
4. Start the coordinator; open Screen B for revision n. The station marks unchanged files verified
   at once (10.3), so their categories show "Confirmed" immediately.
Failure: ■ caption under the Unchanged section "The package could not be sealed: {reason}.
Nothing was uploaded." Buttons enabled again.

### 6.4 Diff model

`RevisionChanges` (AppCore, pure): computed from the base `SealedPackage` (manifest, its capture
record, its field controls, its photo entries) and the revision draft:

- File level: by manifest path. added = path not in base; changed = path in base with another
  SHA-256; unchanged = same path and SHA-256; removed = in base but not in the draft (only retired
  roles, 11). `k = added + changed`; `bytesToUpload = Σ bytes of added + changed`.
- Item level (rows): new captures = capture ids not in the base record; room-name changes =
  base captures whose `capture-model.json` changed; controls = by control `id` (added / value
  changed); photos = photo entries whose path is new, grouped by (captureId, room).
- Unchanged summary: captures with no changed or added file; photo entries carried over; controls
  unchanged by id.
- Manifest: base entry count → draft entry count.

---

## 7. Notifications and background refresh

- Local notification when a package's verdict becomes known and the app is not active or the
  package's screen is not on screen:
  - title **"Verdict: {Word}"** ("Verdict: Limited"), body **"{address} · revision {n}. Details:
    spatial report in the HUB."**, sound default, `threadIdentifier` = packageId,
    `userInfo["packageId"]`.
  - Tap → Screen C for that package.
  - Never more than one notification per `verdictId`.
- Background: register `BGAppRefreshTask` id **`com.hellochapter.capture.verdict-refresh`** at
  launch (`AppDelegate.didFinishLaunching`). Scheduled (earliest begin 15 min) whenever a package is
  confirmed by the station and has no verdict yet, or has a verdict but publication not final.
  Handler: for each such package on the phone, `getPackage` (and `getVerdict` when
  `verdict_ready`), update the cache (9.3), post the notification, reschedule if still waiting;
  expiration handler cancels the calls.
- Info.plist: `UIBackgroundModes` += `fetch`; `BGTaskSchedulerPermittedIdentifiers` =
  [`com.hellochapter.capture.verdict-refresh`].
- Foreground polling stays in `UploadCoordinator` (15 s), and continues after the verdict until
  publication is `published` or `publish_failed`, at most 30 minutes after the verdict.

---

## 8. Status for Captures home (interface for `phone-capture`)

`phone-capture` draws Captures home (artboard 2b screen 0). This area supplies the model:

```swift
public struct PackageListItem: Sendable, Equatable {
  public var packageId: LowercaseUUID
  public var address: String          // "424 West End Ave, Apt 4K"
  public var revision: Int
  public var section: Section         // .inProgress or .sealed
  public var subtitle: String         // rules below
  public var progress: Double?        // 0...1, in-progress rows only (4 pt bar)
  public var trailing: Status?        // glyph + word, sealed rows only
  public enum Section { case inProgress, sealed }
  public enum Status { case ready, limited, blocked, checking, stopped }
}
```

| Phase | Section | Subtitle | Trailing |
|---|---|---|---|
| uploading / paused | In progress | "{captureCountText} · uploading · {done} of {total} MB" (paused: "· paused · ") | — (progress bar) |
| upload stopped | Sealed | "Revision {n} · upload stopped · re-seal needed" | ■ "Stopped" |
| confirmed, no verdict | Sealed | "Revision {n} · sealed {date}" | ○ "Checking" |
| verdict ready/limited | Sealed | "Revision {n} · sealed {date}" | ● "Ready" / ▲ "Limited" |
| verdict blocked | Sealed | "Revision {n} · re-seal needed" | ■ "Blocked" |
| revision n+1 in progress | In progress (its visit row) | "Revision {n+1} · not sealed yet" | — |

Superseded revisions are not listed (their newest revision is). Footnote (drawn): "Files stay on
this phone until the station confirms each one. Verdict details are in the HUB."

---

## 9. Code mapping (phone)

### 9.1 AppCore (`ios/App/AppCore/Sources/AppCore/`)

| File | Change |
|---|---|
| `VisitFlow.swift` | `VisitStep`: rename `.uploading` → `.packageStatus(packageId)`; add `.revisionReady`. New state: `revision: Int` (1 for a new visit), `basePackageId: LowercaseUUID?`, `isRevisionMode`. New initializer `VisitFlow(revisionOf record: CaptureRecord, base: LowercaseUUID, baseRevision: Int)` (used by "Add to this capture", also after a relaunch) that starts at the Capture overview step `phone-capture` adds, with `revision = baseRevision + 1`, `isSealed = false`, the base record as `record`. New events: `reviewRevision()` (overview → `.revisionReady`, revision mode only), `backToOverview()` (from `.packageReady` / `.revisionReady`), `resealAfterFailure()` (from `.packageStatus`, sets `revision += 1`, `basePackageId` = the failed package). `sealed()` allowed from `.packageReady` or `.revisionReady`; `addMoreRooms()` allowed in revision mode before sealing. Keep "no change after sealing" (`alreadySealed`) for the sealed revision itself. The "Add to this capture" button is shown only for the latest revision with a verdict (enforced by `PackageListItem`/`VisitModel`, tested). |
| `Summaries.swift` | `PackageReview` v2: `exportGroups: [ExportGroup]` with `rows: [ExportRow(kind: .plans/.meshes/.raw, label, count)]`, `compassText`, `filesText`, `subtitle` (3.1), `sealNote` (3.1), drop `.spatialReportPDF` from `kinds`. `UploadProgressSummary`: category `.plansAndRecord = "Plans and record"`, `Status.confirmed / .uploading(percent) / .waiting / .stopped`, `text` without glyph characters (glyphs are drawn), per-category percent, carried-over exclusion. `StationSteps` → `StationTimeline` (rows of 4.1 / 5.1 with `state: .pending/.inProgress/.done/.problem`, `title`, `detail`, `time`). New `CaptureCountText`, `CompassSummary`. |
| `StationQueries.swift` | `StationPackageStage` unchanged. `VerdictDisplay` → `VerdictStatus { outcome, task, limitationCount, blockerCount, nextVisit: [(action, reason?)], evaluatedAt, verdictId }` with `sentence(published:)`. `PackageStatusSource` adds `func package(packageId:) -> StationPackageInfo` (stage, createdAt, sealedAt, checks, publication, links) and `verdict` returns `VerdictStatus`. |
| `UploadCoordinator.swift` | `UploadActivity.waitingToRetry(PauseReason)`; `UploadErrorKind.transient(PauseReason)`; snapshot adds `station: StationPackageInfo?`, `timeline`, `verdict: VerdictStatus?`; `followStation()` continues until publication final (7); writes the status cache (9.3); `registeredAt` saved on first session answer; `PendingUploads.find` skips states with `supersededBy`. Caption texts per 4.3. |
| **new** `RevisionBuilder.swift` | `VisitPackageBuilder.revisionPlan(base:record:photos:controls:roomNames:)` (9.4) returning `VisitRevisionPlan { draft, record, changes: RevisionChanges, draftFolder }`; `VisitPackageBuilder.rebuildPlan(revision:supersedes:...)` for the re-seal after failure (full build with revision > 1). |
| **new** `RevisionChanges.swift` | 6.4 + all row strings of 6.1 (pure, Linux-testable). |
| **new** `StationStatusCache.swift` | `<package folder>.station-status.json` next to the package (same folder rules and file protection as `UploadStateStore`): `{ formatVersion: 1, packageId, stage, checks, publication, links, verdict: VerdictStatus?, fetchedAt }`. |
| **new** `RevisionDraftMarker.swift` | `<workspace>/revision-draft.json`: `{ version: 1, basePackageId, revision, startedAt, sealedPackageId? }`. |
| **new** `PackageList.swift` | `PackageListItem` builder (8) from all workspaces under `visitsRoot` (sealed packages + upload state + status cache + revision marker). |
| `VisitPackageBuilder.swift` | Doc comment: no Spatial Report PDF. No code change for revision 1 beyond `PlanExporter.exportAll` returning five files. |
| `UITestStation.swift` (Debug only) | Stub station: verdict after sealing when launched with `-ChapterUITestVerdict ready|limited|blocked` (else 404 as today); `Package` with `checks`, `publication`, `links.review = https://uitest-review.invalid/packages/<id>`; carry-over for revision > 1 (10.3); `-ChapterUITestOffline` makes blob uploads fail with `URLError(.notConnectedToInternet)` until toggled; `-ChapterUITestRefuse` returns 409 `package_conflict` to the first session. |

### 9.2 PackageKit (`ios/Packages/PackageKit/Sources/PackageCore/`)

| File | Change |
|---|---|
| `UploadState.swift` | `formatVersion` 2 (decoder accepts 1): add `registeredAt: UTCTimestamp?` (phone time of the first `POST /packages` answer), `supersededBy: LowercaseUUID?` (set on re-seal), `carriedOver: Set<String>` (paths the session answered as carried over). |
| `PackageUploader.swift` | Record `registeredAt`; record carried-over paths from the session answer (`carriedOverFrom` present) and confirm them through `completeFile` exactly as today's "verified at the station" branch (the station answers from its stored check; no re-hash). |
| `PackageDraft.swift` | `add` / `replace` reject `FileRole.isRetired` roles with new `PackageError.retiredRole(FileRole)`. `nextRevision(of:)` skips retired-role files of the base (they become "removed"). New public `init(visitId:packageId:revision:supersedesPackageId:)` for the full rebuild after a failed upload (validates revision ≥ 2 ⇔ supersedes present, ids differ). |
| `PackageAssembler.swift` | Writes `schemaVersion` = `ManifestSchemaVersion.current` ("1.1.0"). |
| `SealedPackage.swift` | Opens manifests 1.0.0 and 1.1.0 (legacy pending uploads keep working after the app update). |
| `PackageError.swift` | `retiredRole`. |
| `StationTypes.swift` | Session file answer gains `carriedOverFrom: LowercaseUUID?`. |

### 9.3 StationClient (`ios/Packages/StationClient/Sources/StationClient/StationModels.swift`)

`Package` and `PackageSummary` gain optional `checks: CheckRunSummary?`, `publication:
PublicationSummary?`, `links: PackageLinks?`, `nextRevision: NextRevisionNotice?` (Package only);
`UploadSessionFile` gains `carriedOverFrom`. New client call `putNextRevisionNotice(packageId:,
_:)`. All optional: decoding an older station still works.

### 9.4 Revision draft build (algorithm)

1. `draft = PackageDraft.nextRevision(of: base)` — every base file carried over with its expected
   fingerprint, retired roles skipped.
2. Capture record: encode the visit record (base captures + new captures, in capture order); if
   the bytes differ from the base file → `draft.replace`.
3. Field controls: `FieldControlsFile.write` into the workspace; if the bytes differ → `replace`.
4. New captures: `addCapture` as today (raw originals, capture model, PlanExport files, mesh
   files).
5. Base captures: map the capture model with today's room names; if its JSON bytes differ from the
   base `capture-model.json` → replace the model and every PlanExport file of that capture
   (re-exported); meshes, LAS and raw originals stay carried over. Otherwise nothing of that
   capture changes (no re-export, so a newer PlanExport never silently changes an old floor).
6. Photos: every photo record of the visit whose package path is not in the base → `add` with its
   recorded fingerprint.
7. `RevisionChanges` from base vs draft (6.4).

### 9.5 App target (`ios/App/Sources/App/`)

| File | Change |
|---|---|
| `Views/PackageScreens.swift` | Rewrite: `PackageReadyView` (3), `PackageStatusView` (4 + 5 by state), `VerdictView` (5), `RevisionReviewView` (6), shared `PackageCard`, `StatusGlyph`, `PlusGlyph`, `SectionHeader`, `HeaderBlock`, `FooterButtons`. Remove `ScanList` use here. |
| `VisitView.swift` | Route `.packageStatus` / `.revisionReady`; remove the `UploadingView(onNewCapture:)` branch; the bottom error toast is not used on these four screens (inline errors instead). |
| `VisitModel.swift` | `reopenForRevision`, `reviewRevision`, `sealRevision`, `resealAfterFailure`, `openInHub(url)`, `notificationPermissionRequested`; `addMoreRooms` keeps today's behaviour; `startNewCapture` removed from these screens. |
| `AppModel.swift` | Status cache loading; `PackageListItem`s for Captures home; route from notification tap; BG refresh handler; coordinators for revision n; cancel superseded coordinators. |
| `AppDelegate.swift` | `BGTaskScheduler.register`, `UNUserNotificationCenterDelegate` (tap → route; present banner only when the package screen is not visible). |
| `Resources/Info.plist` | `UIBackgroundModes: [fetch]`, `BGTaskSchedulerPermittedIdentifiers`. |
| `Views/ScanViewer.swift`, `FloorplanView.swift` | Unchanged; reached from Capture overview floor rows (`phone-capture`) instead of Package ready. |
| `UITests/ReplayFlowUITests.swift` | 13.3. |

### 9.6 Tokens (`ios/Packages/CaptureCore/Sources/CaptureUI/Tokens.swift`)

Needs from `screen-tokens`: `Typography.inter(_ size:, weight: .regular | .semibold, relativeTo:)`,
`Typography.display` = Times New Roman 34, `Control.primaryHeight = 52` (v2; today 56 — this area
uses 52 on its own screens even if the token changes later), `Palette.chevron = #B9AFA2`,
`Palette.disabledText = #4E493F`.

---

## 10. Contract and station changes (exact)

### 10.1 Manifest schema 1.1.0 (`contract/schema/manifest.schema.json`)

- `schemaVersion`: `{"enum": ["1.0.0", "1.1.0"]}` (was `const "1.0.0"`). Writers write "1.1.0".
- `$defs.role.enum`: **unchanged** (keeps `spatial_report_pdf`, so 1.0.0 manifests stay valid and
  the station DB domain `station_file_role` stays as is). Description gains: "spatial_report_pdf is
  retired: written only in manifest 1.0.0 by app builds before v2; never in 1.1.0. The spatial
  report is a station output, not a package file."
- New top-level `allOf` entry:
  ```json
  { "if": { "properties": { "schemaVersion": { "const": "1.1.0" } } },
    "then": { "properties": { "files": { "items": {
      "properties": { "role": { "not": { "const": "spatial_report_pdf" } } } } } } } }
  ```
- `$id` stays `…/v1/manifest.schema.json` (same major).
- `contract/schema/layout.json`: unchanged (`layoutVersion` 1.0.0; the role stays listed in
  `original_exports` for 1.0.0 packages). Only its `description` adds "spatial_report_pdf: legacy,
  manifest 1.0.0 only."
- Swift (`contract/swift/Sources/CaptureContract/`): new `ManifestSchemaVersion` enum (`v1 =
  "1.0.0"`, `v1_1 = "1.1.0"`, `current = .v1_1`) used by `PackageManifest.schemaVersion` (the shared
  `SchemaVersion` stays for the other documents; if `north-arrow`/`phone-capture` bump the capture
  record at the same time, coordinate one contract PR). `FileRole.retiredRoles: [FileRole] =
  [.spatialReportPDF]`, `var isRetired: Bool`. `SchemaParityTests` updated.
- TS (`contract/ts/src/generated/*`): regenerate (`manifest.ts` `schemaVersion: "1.0.0" | "1.1.0"`,
  `schemas.ts`, `constants.ts` add `RETIRED_ROLES = ["spatial_report_pdf"]`).
- Examples: `contract/examples/manifest/valid/` add a 1.1.0 example without the role and keep the
  1.0.0 example with it; `invalid/` add `retired-spatial-report-role-1.1.0.json`.

### 10.2 OpenAPI 1.1.0 (`contract/openapi/station.yaml`, `info.version: 1.1.0`)

New schemas, all fields optional on the existing objects (old apps ignore them):

```yaml
CheckRunSummary:
  type: object
  additionalProperties: false
  required: [status]
  properties:
    status: { enum: [queued, running, completed, failed] }
    startedAt: { $ref: "#/components/schemas/DateTime" }
    finishedAt: { $ref: "#/components/schemas/DateTime" }     # present when completed or failed
PublicationSummary:
  type: object
  additionalProperties: false
  required: [status]
  properties:
    status: { enum: [pending, publishing, published, publish_failed] }
    publishedAt: { $ref: "#/components/schemas/DateTime" }    # present exactly when published
PackageLinks:
  type: object
  additionalProperties: false
  required: [review]
  properties:
    review: { type: string, format: uri }   # ${REVIEW_BASE_URL}/packages/{packageId}
    hub: { type: string, format: uri }      # HUB project page of the deal; omitted when not configured
NextRevisionNotice:
  type: object
  additionalProperties: false
  required: [revision, updatedAt, changes]
  properties:
    revision: { type: integer, minimum: 2 }
    updatedAt: { $ref: "#/components/schemas/DateTime" }
    updatedBy: { type: string, minLength: 1, maxLength: 200 }   # set by the station
    changes:
      type: array
      maxItems: 50
      items:
        type: object
        additionalProperties: false
        required: [kind, subject, title, detail]
        properties:
          kind: { enum: [added, changed, removed] }
          subject: { enum: [capture, room_names, field_control, photos, retired_file] }
          title: { type: string, minLength: 1, maxLength: 200 }
          detail: { type: string, minLength: 1, maxLength: 300 }
          answersNextAction: { type: string, minLength: 1, maxLength: 500 }
```

- `Package` adds `checks`, `publication`, `links`, `nextRevision`. `PackageSummary` adds
  `publication` and `links`.
- `UploadSessionFile` adds `carriedOverFrom: Uuid` — "present when the file is verified because
  revision N−1 (`supersedesPackageId`) holds the same verified file".
- `POST /packages` description adds the carry-over rule (10.3) and a new 422 code
  `supersedes_mismatch`.
- New operation `PUT /packages/{packageId}/next-revision` (`putNextRevisionNotice`, x-roles
  [capture, admin]): body `NextRevisionNotice` without `updatedBy`; replaces the stored notice of
  the sealed package `packageId`; 200 with the stored notice; 409 `package_not_sealed` when
  `packageId` is still uploading; 409 `revision_exists` when a package superseding it already
  exists. The station deletes the notice when `POST /packages` creates a package with
  `supersedesPackageId = packageId`.

### 10.3 Station API (`station/api/src/routes/uploads/`, `packages/`)

- Carry-over in `openSession` (new packages only): when `revision > 1` and a package
  `supersedesPackageId` exists:
  - it must have the same `visit_id` and `deal_id`, `revision = body.revision − 1`, and status ≠
    `uploading`; otherwise 422 `supersedes_mismatch` with pointer `/supersedesPackageId`;
  - each declared file whose (path, role, capture_id, area_key, sha256, bytes) equals a `verified`
    file of that package is inserted with `status = 'verified'`, `blob_name` = the previous
    `blob_name`, `actual_sha256/actual_bytes/checked_at/verified_at` copied, new column
    `carried_over_from = supersedesPackageId`; no upload target is granted;
  - when `supersedesPackageId` does not exist at the station (revision n never arrived, re-seal
    after a failed upload) the session is created as today (every file gets a target).
  - Audit `package.create` adds `carriedOver: <count>`.
- Migration `0009_carry-over.sql`: `ALTER TABLE package_files ADD COLUMN carried_over_from uuid
  REFERENCES packages(package_id)`; table `next_revision_notices (package_id uuid PRIMARY KEY
  REFERENCES packages, notice jsonb NOT NULL, updated_by_id, updated_by_name, updated_at
  timestamptz NOT NULL DEFAULT now())`.
- `packageView` (`station/api/src/routes/uploads/views.ts`, used by `packages/store.ts`) adds
  `checks` (latest `check_runs` row: `running` → `running`, `completed` → `completed`, `failed`
  → `failed`; a queued `checks` job with no run → `queued`), `publication` (`hub_publications`
  row: `pending`/`publishing`/`published`/`publish_failed`, `published_at`), `links.review` (new
  API config `REVIEW_BASE_URL` in `station/api/src/core/config.ts`, same value as the worker's),
  `links.hub` (new optional config `HUB_WEB_DEAL_URL_TEMPLATE`, e.g.
  `https://hub.example/deals/{dealId}`; `{dealId}` URL-encoded), `nextRevision`.
- New route file `station/api/src/routes/packages/next-revision.ts` for 10.2's `PUT`.
- Blob retention: a blob may now be referenced by several packages; nothing deletes blobs today;
  any future clean-up must count references.

### 10.4 Phone "next revision" notice (feeds the web's "Revision 2 not sealed · on the phone")

While a visit is in revision mode, the phone sends `PUT /packages/{base}/next-revision` with the
current `RevisionChanges` rows (`title`/`detail` exactly as Screen D, `kind`, `subject`),
debounced 10 s after each change, when online, and on app foreground; failures are ignored (never
shown, never blocking). `answersNextAction` is filled only by these rules: a new capture whose label
equals (case-insensitive, trimmed) an omitted or inaccessible room name of the base capture record →
the base verdict's next action that contains that room name; a new ceiling-height control for room
R → the next action that contains R and "ceiling". See Q6.

---

## 11. Retiring the phone Spatial Report and `spatial_report_pdf` (checklist)

| Where | Change |
|---|---|
| `ios/Packages/PlanExport/Sources/PlanExport/SpatialReportWriter.swift` | **Delete.** |
| `PlanExport/Sources/PlanExport/PreviewWriters.swift` | `PlanExporter.exportAll` returns DXF, CSV, plan PDF, PNG, SVG (five); doc comment updated. |
| `PlanExport/Tests/PlanExportTests/PDFWriterTests.swift` | Delete the spatial report tests (`testSpatialReport…`, line 11–17 setup, line 156); keep plan PDF tests. Keep `testPDFsEmbedInterAndDeclareOnlyTheFontsTheyUse` for the remaining PDFs. |
| `PlanExport/Tests/PlanExportTests/ExportAllTests.swift` | `todaysFiles` = five files; add `testNoSpatialReportIsWritten`. |
| `ios/App/AppCore/Sources/AppCore/Summaries.swift` | No "Spatial Report PDF" kind. |
| `AppCoreTests/ManifestRoleTests.swift` | Remove `.spatialReportPDF` from `todaysRoles`; add assertion that no draft entry has a retired role. |
| `AppCoreTests/PackagePipelineTests.swift` | Remove "spatial-report.pdf" from the expected names; `fileCount` [10, 10] → [9, 9]. |
| `PackageKit/Tests/PackageKitTests/Support/Fixtures.swift` | Remove the `spatial-report.pdf` spec from `perCapture`; add a legacy 1.0.0 fixture builder for `SealedPackage.open` / upload-resume tests. |
| Contract | 10.1. |
| `station/checks/src/checks/independence.ts`, `parsers/index.ts` | Keep `spatial_report_pdf` (legacy 1.0.0 packages still parse and count as an export of one scan). No behaviour change. |
| `station/hub/src/plan.ts` `HUB_UPLOAD_ROLES` | Remove `spatial_report_pdf`: a legacy phone report is never uploaded to the HUB next to the station's spatial report; it is listed with a station link like other non-uploaded files. Header comment updated. (The station's own spatial report upload is `spatial-report`.) |
| `station/hub/test/helpers.ts`, `station/worker/test/e2e/pipeline.e2e.ts` | Role lists updated; add a legacy-package publish test (phone report linked, not uploaded). |
| `web/lib/format.ts` | `ROLE_LABEL.spatial_report_pdf = "Spatial report PDF · phone (retired)"`; `HUB_UPLOAD_ROLES` mirrors the station (drift test exists). |
| `web/test/package-detail.test.tsx` | Role lists updated. |
| `fixtures/generator/src/package.ts` | Stop writing `spatial-report.pdf`; write manifest `schemaVersion: "1.1.0"`; add a generated legacy fixture `fixtures/generated/legacy-1.0.0/` (box-room content, manifest 1.0.0 with `spatial-report.pdf`), flagged `"legacy": true` in `index.json`. Regenerate every fixture (the iOS UI-test app bundles `box-room/package`). |
| `fixtures/generator/test/schema.test.ts` | `ALL_ROLES` keeps the role for the legacy fixture only; good fixtures must not contain it. |
| `fixtures/reference/*.json` | Unchanged (they document historical Polycam intake). |
| `fixtures/generator/README.md`, `docs/floorplan-report-plan.md`, `docs/waves/specs/F1.md` | Note the retirement. |
| `docs/waves/design/DESIGN.md` | Add "Design v2 (Oct 21, 2026)" lines for F6: screen ids 2f, the owner decisions, the retired role. |

---

## 12. Dependencies on other areas

| Area key (as assigned by the plan) | What this area needs |
|---|---|
| `phone-capture` | Captures home (renders `PackageListItem`, routes "In progress" rows to Screen B and "Sealed" rows to Screen C — the artboard links the in-progress row to the overview; recommended: Screen B), Capture overview (its review button opens Screen A or D; revision mode banner "Revision {n} · not sealed yet"; floor rows open the scan viewer), the navigation host and back routes, persistence of an unsealed visit across relaunch, compass fields in the capture record and `CompassState`. |
| `screen-tokens` | Inter Regular/SemiBold bundled in the app with full glyph coverage, `ChapterTokens.Typography.inter`, Times display 34, new colours, 52 pt controls. |
| `phone-field` | `LengthFormatter` v2 ("2,490 mm", "8' 2""); control naming; "Before you leave" gate for revision mode. |
| `north-arrow` (compass) | Capture-record fields and thresholds (±10° / ±30°) for 3.3. |
| `plan-sheet` | Final role and file name of the plan sheet (role `plan_pdf`, label "plan sheet PDF"); if it adds a role, the Plans sub-row lists it. |
| `spatial-report` | Station spatial report generated after checks and published to the HUB; publication state in `hub_publications`; "Details: spatial report in the HUB" is only true once it ships. |
| `web-review` | Consumes `publication`, `links`, `nextRevision`, `carriedOverFrom`; the capture-role view the phone may open; label for the legacy role. |
| contract owner (whoever lands the contract PR) | One coordinated bump: manifest 1.1.0 + capture record compass fields + OpenAPI 1.1.0. |

Order: contract + station (10.1–10.3) → PackageKit/StationClient → AppCore → screens → UI tests.
The station carry-over must ship before the phone shows "not uploaded again".

---

## 13. Test plan

### 13.1 Unit (Linux-testable: `swift test --package-path ios/App/AppCore`, PackageKit, contract)

AppCore:
- `PackageReviewTests`: kinds rows for all role combinations (no GLB, no LAS, no capture model,
  textures); counts; "plan sheet PDF, PNG, SVG" ordering; no "Spatial Report" anywhere; subtitle
  ("618 Valley Street · 2 floors · revision 1 · 74 files · 768 MB" from a synthetic draft);
  `CaptureCountText` ("1 floor and 1 room"); compass text for 0 / some / all captures and 1 vs 2
  captures; controls / photos / entries plurals; seal note.
- `UploadProgressTests`: category mapping incl. legacy role → "Plans and record"; statuses and
  per-category percent (41%); carried-over files excluded from totals; "Stopped" placement.
- `UploadErrorKindTests`: offline vs station-unavailable split (each URLError code listed in 4.3,
  StationError.offline, 503, 429, blob 500); fatal messages unchanged.
- `StationTimelineTests` (replaces `testStationStepsNeverClaimHubPublication`): every row × state
  of 4.1; publication shown done only when the station says `published`; time formatting across
  midnight; Screen C rows without Registered.
- `VerdictStatusTests`: three sentences, plurals, publication-pending variant; next visit
  mapping (`measured`, else `message`, else none), cap at 3 and "{m} more in the spatial report.";
  ready → no rows.
- `RevisionBuilderTests` (fixtures `two-floor-house`, `two-room-apartment`): (a) photo-only change
  → capture record unchanged, k = photos, every base file carried with identical SHA-256; (b) new
  one-room capture → capture record changed, new capture's files added, base floors unchanged; (c)
  added ceiling height → field-controls changed + row text "Field control · 2,490 mm · 8' 2"";
  (d) rename a room in a base floor → that floor's model + five PlanExport files changed, meshes
  unchanged; (e) base manifest 1.0.0 with `spatial-report.pdf` → removed row, not in draft; (f) no
  change → k = 0, "No changes to seal"; (g) manifest counts "75 → 83 entries".
- `RevisionChangesTextTests`: every row string of 6.1, Unchanged title joins, footnote variants.
- `VisitFlowTests` additions: reopen only after a verdict and only for the latest revision; seal
  revision 2 from `.revisionReady`; `addMoreRooms` in revision mode; re-seal after failure creates
  revision n+1; cannot seal twice.
- `PendingUploadsTests`: superseded states skipped; legacy 1.0.0 packages still found.
- `PackageListTests`: every row of the table in 8.
- `ManifestRoleTests`, `PackagePipelineTests` updated (11).

PackageKit: `PackageDraft` rejects retired roles; `nextRevision` skips them; `init(revision:…)`
rules; assembler writes "1.1.0"; `SealedPackage.open` reads 1.0.0 and 1.1.0; upload state v1 file
decodes into v2; uploader records `registeredAt` and carried-over paths (fake service answering
`carriedOverFrom`).

PlanExport: `ExportAllTests` five files, byte-stable; `SpatialReportWriter` symbol gone.

Contract: `SchemaParityTests` (Swift) with `ManifestSchemaVersion`; TS validator tests: 1.0.0 +
role valid, 1.1.0 + role invalid, 1.1.0 without role valid; OpenAPI lint.

### 13.2 Station, web, fixtures (`npm test` workspaces)

- `station/api`: carry-over (verified without target, `carriedOverFrom`, blob name reused,
  `completeFile` answers from the stored check without reading the blob); `supersedes_mismatch`
  (other visit / deal / revision gap / superseded still uploading); missing superseded package →
  normal session; `packageView` returns `checks`, `publication`, `links` (with and without
  `HUB_WEB_DEAL_URL_TEMPLATE`); next-revision notice PUT / 409s / deleted by the superseding
  session; manifest 1.1.0 with the role → 422 at seal; legacy 1.0.0 manifest with the role → 202.
- `station/checks`: all fixtures regenerated; legacy fixture verdict unchanged vs today.
- `station/hub` + worker e2e: legacy phone report not uploaded to the HUB.
- `web`: format labels and role lists.
- `fixtures/generator`: good fixtures have no retired role and manifest 1.1.0; legacy fixture 1.0.0.

### 13.3 UI tests (`ios/App/UITests/ReplayFlowUITests.swift`, stub station)

1. **Package ready**: after "Before you leave", assert "Package ready", "Step 3 of 3", subtitle
   contains "revision 1", `package.floor.floor-1` expanded with sub-row labels starting "Plan DXF ·
   rooms CSV · plan sheet PDF", no text containing "Spatial Report"; "Capture record" row reads
   "compass: not recorded" (until compass ships); note contains "The station makes the spatial
   report.". (The Floorplan review steps move to the Capture overview floor row, `phone-capture`.)
2. **Upload → verdict** (`-ChapterUITestVerdict limited`): tap `package.seal`; "Uploading" appears;
   wait for `station.registered` label "Registered, done, …"; then the title becomes the address
   and `verdict.card` label starts "Verdict: Limited."; `station.published` label "Published to the
   HUB, done, …"; `verdict.openHub` exists.
3. **Paused** (`-ChapterUITestOffline`): caption "Paused: no connection. Resumes on its own. You can
   close the app." while the transport fails; resumes when toggled.
4. **Upload stopped** (`-ChapterUITestRefuse`): title "Upload stopped", `upload.retry` and
   `upload.reseal`; re-seal alert texts; after "Re-seal", header "Revision 2 · sealed".
5. **Revision 2**: from Screen C tap `verdict.addToCapture`, take one photo from the overview, open
   the review: title "Revision 2", a row "1 photo", Manifest row "{n} → {n+1} entries", footnote
   "Only the 1 new file is uploaded. …"; tap `revision.seal`; every category except "Site photos"
   shows "Confirmed" immediately (carry-over), then the revision 2 verdict.

### 13.4 Visual checks (screenshots)

UI tests attach screenshots (`XCTAttachment`, iPhone 17 Pro simulator, 402 × 874 pt) of: Package
ready (2 floors, from a two-floor stub fixture when `phone-capture` provides one, else box-room),
Uploading paused, Upload stopped, Verdict Limited / Ready / Blocked, Revision 2, Revision 2 empty.
Reviewed side by side with artboard 2f at 100 %: positions within ±2 pt, colours exact hex,
Inter/Times as in 2.3. Also Dynamic Type XXL and accessibility XL: nothing clipped, buttons grow.

### 13.5 Acceptance criteria

1. No package sealed by the v2 app contains a file with role `spatial_report_pdf` or the name
   `spatial-report.pdf`; manifests say `schemaVersion` "1.1.0".
2. A package sealed by an older build (1.0.0, with the phone report) still uploads, seals and gets
   a verdict after the app update; its phone report is not uploaded to the HUB.
3. Package ready lists exactly the files the draft holds (counts equal the manifest), grouped as in
   3.1, with every string of 3.1 verbatim (values from data).
4. The Uploading screen never claims "Published to the HUB" unless the station returned
   `publication.status = published`; times come from station data or the recorded `registeredAt`.
5. Offline shows the paused caption within one retry cycle and resumes without operator action.
6. The phone never shows verdict detail beyond the word + shape, one sentence, next actions and
   timeline; "Open in the HUB" opens the station-provided link.
7. Revision 2 uploads only added and changed files (station logs `uploadTargets = k`); unchanged
   files are verified by carry-over with identical SHA-256; revision 1 stays byte-identical on the
   phone and at the station.
8. A fatal upload error never deletes anything; "Re-seal as revision 2" produces a new package
   that uploads; the old one is not resumed again.
9. All text is Inter except the large titles (Times New Roman); no typed "chapter / RENOVATION".
10. All tests in 13.1–13.3 pass in CI (`ios.yml` App job, `npm test`).

---

## 13b. Risks

| Risk | Mitigation |
|---|---|
| "not uploaded again" is false until the station carry-over ships | Ship 10.3 first; if the session answer carries no `carriedOverFrom`, Screen B counts those files normally (the copy on Screen D is the only claim; gate it on the station `GET /health` `version` ≥ the carry-over release, else the Unchanged subtitle reads "Same fingerprints as revision {n-1}"). |
| Room naming maps differently after an app update → a base floor "changes" with no operator action | Shown honestly as "room names" changed; the row lists the renames; test (d). |
| Background refresh is best effort; the notification may come late | Copy says "You will get a notification"; foreground polling on open; Captures home shows the status. |
| Inter glyph coverage / licence | Full Inter 4.x OFL files bundled by `screen-tokens`; UI test asserts the "→" renders (no fallback font) via a screenshot review. |
| Times 34 titles with long addresses | 2 lines, tail truncation, Dynamic Type. |
| Re-seal after failure when revision 1 has an open session at the station | Allowed by contract (no existence check); web shows revision 1 as "uploading" forever — `web-review` should label sessions superseded by a newer revision. |
| Shared blobs between revisions | Documented in 10.3 (no deletion exists). |
| Manifest version bump collides with the capture-record compass bump | One coordinated contract PR (12). |

---

## 14. Open questions (with recommended defaults)

| # | Question | Recommended default |
|---|---|---|
| Q1 | Large titles: the owner says Times for display titles; the v2 artboard draws SF Bold 34. Times weight? | Times New Roman **Regular** 34/41 (the brand uses Times-Roman), tracking 0. |
| Q2 | "Open in the HUB": the HUB project page (needs `HUB_WEB_DEAL_URL_TEMPLATE`) or the web review package page (capture-role users see status only there)? | `links.hub` when configured, else `links.review`; both opened in Safari. |
| Q3 | Package ready sub-row counts: the mock-up shows 5 / 4 / 4 with only 3 named kinds in rows 2 and 3. | Real counts; "capture model" named in row 3; no `texture` row part unless textures exist. |
| Q4 | Changed and removed items on Revision n (not drawn). | Equals glyph (ink) for changed, minus glyph (blocked red) for removed, texts in 6.1. |
| Q5 | Footnote "Only the 8 new files are uploaded" when capture-record / field-controls changed. | "Only the {k} new or changed files are uploaded." whenever a file changed. |
| Q6 | The web shows "Revision 2 not sealed · on the phone … answers limitation 1"; that needs data from the phone before sealing. | Build the `next-revision` notice (10.2, 10.4) in this area, best effort, with the two `answersNextAction` rules only. |
| Q7 | "Add to this capture" before the verdict (while checks run)? | Not offered: only on Screen C (verdict known). |
| Q8 | Floor header with the chevron: accordion or navigate to the floor (the artboard links "#floor2")? | Accordion as specified; the floor screen (scan viewer) is reached from Capture overview. |
| Q9 | Upload stopped: re-seal from the sealed files (carry-over) or from the workspace? | From the workspace (full rebuild), because the sealed copy may be what failed. |
| Q10 | Notification permission timing. | Ask once, right after the first successful seal. |

---

## Addendum (completeness critique, Oct 21, 2026) — binding, overrides the body above

Numbers refer to `00-critique.md`. Built by track **T9 phone-package** (PackageKit,
StationClient, the AppCore package/upload files, `PackageScreens.swift`, `AppDelegate.swift`);
contract parts by **T0**, station parts by **T2** (API, migration 0009) and **T4** (hub roles),
web parts by **T6**, PlanExport parts by **T5**, navigation and Info.plist by **T10**.

### C1. Area names
Read `screen-tokens` as `phone-capture` §2 (ChapterUI) and `north-arrow` as `compass`. Fonts
come from `ChapterTheme.Font` (ChapterUI), not `ChapterTokens.Typography.inter`; the `→` glyph
is in the full Inter TTFs ChapterUI bundles.

### C2. Header and back (R-18c)
§2.2's custom header block and custom back pill are withdrawn. Every screen of this area uses the
system `NavigationStack` with the large title (Times New Roman 34/41 via
`ChapterAppearance`), the right caption as a `.topBarTrailing` toolbar text (Inter 13 muted) and
the subtitle as the first content line (Inter 15 muted, 8 pt under the title). Back is the system
chevron on every iOS version. Status glyphs, plus/equals/minus glyphs, info note and progress bar
come from ChapterUI (phone-capture addendum A8).

### C3. Captures home (R-28) — §8 withdrawn
`PackageListItem` and `PackageList.swift` are not built. phone-capture's `CaptureLibrary` builds
the rows with the merged table of R-28, using this area's `StationStatusCache` reader,
`UploadState` and `CaptureCountText`. In-progress rows open the **Capture overview** (drawn link
`#overview`); the overview's `Upload status` button opens Screen B.

### C4. Revision state (R-25, R-26)
- `revision-draft.json` (§9.1 `RevisionDraftMarker.swift`) is not created; revision mode lives in
  `visit.json` (`revision.number`, `revision.basePackageId`, `revision.startedAt`).
- VisitFlow changes of §9.1 are part of the merged table R-25 and are built in T10:
  `.uploading` → `.packageStatus(packageId)`, `.revisionReady`, `reviewRevision()` folded into
  `reviewPackage(canFinish:)`, `addMoreRooms()` renamed `addFloor()` (also used by Package ready's
  "Scan another floor or room", §3.1), `resealAfterFailure()`.
- The checklist gate applies before Screen D too.

### C5. Station status cache (R-27)
File name and place: `<packageId>.station-status.json` next to `<packageId>.upload-state.json`
(same folder and file protection as `UploadStateStore`). Schema = §9.1 `StationStatusCache`. This
area owns writer and reader; phone-capture only reads.

### C6. Titles (R-29)
Screen C title, Screen D right label and the notification body use the project title
(`hub.projectName` when not empty, else `address.formatted`), not `address.formatted`.

### C7. Retirement split (R-11)
Kept in this area: PackageKit (`PackageError.retiredRole`, `PackageDraft` rules,
`SealedPackage` 1.0.0/1.1.0, test `Fixtures.swift`), AppCore (`Summaries`, `ManifestRoleTests`,
`PackagePipelineTests`, `VisitPackageBuilder` doc). Moved: `SpatialReportWriter.swift` deletion,
`exportAll`, PDF/ExportAll tests → plan-sheet (T5); contract + fixtures → T0;
`station/hub/src/plan.ts` `HUB_UPLOAD_ROLES`, hub tests, worker e2e → spatial-report (T4);
`web/lib/format.ts`, web tests → web-review (T6). `PackagePipelineTests` expects
`plan-sheet.pdf` (plan-sheet rename) and no `spatial-report.pdf`; it also asserts each photo's
`directionSource` (phone-field AC8): this area owns that file and merges all three expectations.

### C8. OpenAPI 1.1.0 merged (R-14…R-16)
- `CheckRunSummary` gains optional `rules` (web); `PublicationSummary` gains required
  `hubFolder` (`Capture/{visitId}/r{revision}`); both now live on `PackageSummary` as well as
  `Package`.
- `links.hub` from station config `HUB_WEB_DEAL_URL_TEMPLATE` is also the web's deal link (the web
  env `HUB_DEAL_URL_TEMPLATE` is dropped).
- **"Registered" (R-16):** `UploadState.registeredAt` stores the station `createdAt` returned by
  the session answer (`POST /packages`) when present, else the phone time of that answer. The
  station's `packages.registered_at` ("seal accepted") is not used for this row.
- `Package.nextRevision` is **consumed by the web** to draw "Revision 2 · not sealed · on the
  phone" (R-30). The notice stays best effort and never blocks, but it is a shipped feature, not
  optional: test it in T2 and T6.
- Migration number confirmed: `0009_carry-over.sql`.

### C9. `answersNextAction` → limitation index (for the web, G-7)
The phone fills `answersNextAction` with the base verdict's next action **verbatim** (rules of
§10.4). The web derives "answers limitation {i}" from it (web-review addendum). Add a unit test
that the phone copies the action string byte for byte (no case or punctuation change).

### C10. Notification text
Title `Verdict: {Word}`; body `{project title} · revision {n}. Details: spatial report in the
HUB.`

### C11. Tests moved
UI tests of §13.3 are written in T10's `ReplayFlowUITests.swift` (single owner) against this
area's identifiers. Snapshot/visual checks of §13.4 use `ChapterUISnapshotTesting` (R-18d).
