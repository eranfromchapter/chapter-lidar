# Build spec: Phone capture v2 (area `phone-capture`)

Chapter Capture v2, iPhone app, feature F2 plus the phone screen tokens. Written October 21, 2026
for the engineers who build it. Everything needed is quoted here, so the design bundle does not
have to be opened again.

| | |
|---|---|
| Artboards | `2b` app-capture-v2 (this build) · `2a` screen-capture v1 (today) · `2k` screen-tokens-v2 (phone half) |
| Related artboards | `2d` app-field-v2 (Photos, Field controls, Before you leave) · `2f` app-package-v2 (Package ready, Uploading, Verdict received) · `1d` north-arrow-v2 (compass states and thresholds) |
| Owner decisions applied | Oct 21, 2026: the real Chapter logo and Inter everywhere. On the phone, Inter replaces SF and Times stays for display titles. The compass is recorded at the start of each floor's scan, with 3 states and the ±10° / ±30° thresholds. |
| Device frame | Every artboard is 402 × 874 pt (iPhone 16 Pro / 17 Pro): safe area 62 pt at the top and 34 pt at the bottom. The bundle's `padding-top: 62px` and `padding-bottom: 42px` are the safe area plus 0 and 8 pt. |
| Code today | `ios/Packages/CaptureCore` (CaptureUI, CaptureCore, CaptureRoomPlan), `ios/App/Sources/App`, `ios/App/AppCore`, `ios/Packages/FieldKit/Sources/FieldKitUI/FieldTheme.swift` |

Placeholders: `[OPERATOR]`, `[DEAL ID]` and other bracketed values are live data. "618 Valley
Street", "12 rooms" and "512 of 768 MB" are sample values. All other text is verbatim and must
match character for character, including `·` (U+00B7), `°` (U+00B0), `±` (U+00B1) and `…`
(U+2026).

---

## 0. What this area delivers

1. **Phone screen tokens v2 and the brand on the phone.** This is a new shared SwiftUI package
   `ios/Packages/ChapterUI`: colours, type (Inter and Times), metrics, the real Chapter logo, and
   the components every phone screen uses. CaptureUI (this area), FieldKitUI (area `phone-field`)
   and the App's package screens (area `phone-package`) all use it.
2. **Captures home** (artboard 2b-0). This is new and becomes the app's home screen.
3. **New capture**, step 1 (2b-1), with the states **offline** (2b-1b) and **address different
   on site** (2b-1c).
4. **What are you scanning?**, step 2 (2b-2), with the **compass reading**.
5. **Live scan** (2b-3), with the **compass state** and the **tracking lost** state (2b-3b),
   plus the paused and failed states that are not drawn.
6. **Capture overview** (2b-4). This is new: the home of one capture, listing its floors, photos,
   controls, checklist state and the package button.
7. **How the compass is read**: CoreLocation heading and accuracy, CoreMotion attitude,
   permissions, retry, and no way to type a value. The data fields and the state rules belong to
   area `compass` (§8).
8. **Persistence of a capture in progress**, so the Captures home can list it and reopen it
   after the app is relaunched.

Out of scope here, but linked from these screens: photo labeling, field controls and the full
Before you leave screen (`phone-field`), and Package ready, Uploading, Verdict received and
revision 2 (`phone-package`). The plan sheet, spatial report, web review and scan browser are also
out of scope.

---

## 1. Brand rules on the phone (binding)

| Rule | Implementation |
|---|---|
| **Use the real logo, never typed text.** The bundle draws a typed serif "chapter" over "RENOVATION". It must not be built. | Use the `ChapterLogo` view in ChapterUI. It draws the filled paths of `web/public/brand/chapter-logo.svg` (the full logo with RENOVATION, viewBox 1756 × 635, fill `#231F20`). `tools/brand/generate_plan_brand.py` produces the paths, from the same source as PlanExport's `ChapterLogo`. Delete the typed `Wordmark` in `CaptureUI/Components.swift` and the typed "chapter / RENOVATION" in `RootView.SignInView`. |
| **Inter replaces SF on every phone screen.** | Bundle Inter Regular (400) and Inter SemiBold (600) as static TTFs in ChapterUI and register them at launch (§2.6). Every place the bundle says `-apple-system`, `SF Pro Text` or `system-ui` becomes Inter. Weight 600 and 700 both map to Inter SemiBold. |
| **Times stays for display titles.** | Large titles (34/41) use Times New Roman Regular 34 (`TimesNewRomanPSMT`, shipped with iOS). The bundle draws them in SF Bold 34 with 0.4 tracking. That drawing is overridden: use Times Regular, tracking 0, as in v1 and in every Times heading of the bundle. |
| **Mono stays mono.** | The live-scan timer and any ids use the system monospaced font (`.system(size:design:.monospaced)`, SF Mono). |
| **Status shows word and shape, never colour alone.** | The status glyphs are drawn as shapes (§2.4.6), not as the Unicode characters ●▲■, which Inter does not contain. |
| Colours | The app's tokens stay as they are (ink `#1F2429`, and so on). Only the logo uses brand black `#231F20`. |

---

## 2. Phone screen tokens v2 (`ios/Packages/ChapterUI`)

These replace `CaptureUI/Tokens.swift` (`ChapterTokens`) and `FieldKitUI/FieldTheme.swift` as the
single source. Both old types stay as thin aliases that forward to `ChapterTheme`, so files in other
areas compile unchanged and pick up v2 values. The point and pixel values below are the design
values.

### 2.1 Colour (`ChapterTheme.Color`)

| Token | Hex / value | Use |
|---|---|---|
| `ink` | `#1F2429` | text, primary button fill, toggle tint, live-scan background |
| `ground` | `#F5EFE6` | screen background, navigation bar background |
| `surface` | `#FAF5EE` | grouped cards, text on ink, filled button on the dark scan screen |
| `nude` | `#E8DDD0` | row separators, tinted buttons, segmented track, banners, avatar, progress track |
| `line` | `#D9CCBC` | 1 pt card border, disabled button fill |
| `muted` | `#6B6557` | secondary text, section headers, footnotes |
| `disabledText` | `#4E493F` | text of a disabled primary button |
| `chevron` | `#B9AFA2` | navigation-row chevron; live-scan placeholder text |
| `ready` | `#2E5E2E` | ● Done / Verified / Recorded / Ready; the "add" circle |
| `limited` | `#9A6A1E` | ▲ glyph |
| `limitedText` | `#7A5214` | ▲ text (Partly / Approx. / Limited / Not verified) |
| `blocked` | `#8B2E2E` | ■ Missing / Open / Blocked; the "remove" circle |
| `logo` | `#231F20` | Chapter logo fill only |
| `scanWell` | `#2B3137` | camera well, normal |
| `scanWellDimmed` | `#23282D` | camera well while tracking is lost |
| `scanWellBorder` | `#3A424A` | 1 pt camera-well border |
| `onDarkCaption` | `#D9CCBC` | live-scan count labels and status line |
| `onDarkPill` | `rgba(250,245,238,0.14)` | live-scan pills |
| `alertCard` | `rgba(250,245,238,0.97)` | tracking-lost card |

The app stays light-only (`UIUserInterfaceStyle = Light` in Info.plist). Dark Mode is not part of
this build. The live scan is dark by design (§3.4).

### 2.2 Type (`ChapterTheme.Font`)

Every style is created with `Font.custom(name, size:, relativeTo:)`, so Dynamic Type scales it.
Line heights are the design values; apply them as `lineSpacing = lineHeight − font.lineHeight`
where they differ.

| Style | Font | Size / line | relativeTo | Used for |
|---|---|---|---|---|
| `largeTitle` | Times New Roman Regular (`TimesNewRomanPSMT`) | 34 / 41 | `.largeTitle` | Captures, New capture, What are you scanning?, the overview's project title |
| `navTitle` | Inter SemiBold | 17 / 22 | `.headline` | inline navigation title when scrolled; sheet titles |
| `body` | Inter Regular | 17 / 22 | `.body` | row titles, values, text fields |
| `bodyEmphasis` | Inter SemiBold | 17 / 22 | `.body` | primary buttons, address row, alert title |
| `subhead` | Inter Regular | 15 / 20 | `.subheadline` | statuses, banners, segmented items, tinted buttons, overview subtitle |
| `subheadEmphasis` | Inter SemiBold | 15 / 20 | `.subheadline` | selected segment, live-scan title pill and coaching pill |
| `footnote` | Inter Regular | 13 / 17 | `.footnote` | row subtitles, section headers (uppercased), footnotes, "Step 1 of 3" |
| `footnoteEmphasis` | Inter SemiBold | 13 / 17 | `.footnote` | avatar initials |
| `caption` | Inter Regular | 12 / 16 | `.caption` | live-scan count labels |
| `count` | Inter SemiBold | 22 / 28 | `.title2` | live-scan counts |
| `glyphN` | Inter SemiBold | 7 (fixed, not scaled) | none | the "N" inside the 32 pt compass glyph |
| `mono` | SF Mono (system monospaced) Regular | 15 / 20 | `.subheadline` | live-scan timer "06:42" |

Section headers are footnote, `textCase(.uppercase)`, muted, with no extra tracking (the bundle
uses none).

### 2.3 Metrics (`ChapterTheme.Metric`)

| Token | Value | Note |
|---|---|---|
| Screen side padding | 16 | v1 used 20 |
| Content top padding under the title | 16 (home, step 1), 14 (step 2), 12 (overview) | |
| Gap between sections | 18 (home, step 1), 14 (step 2), 10 (overview) | |
| Section header to card | 6 | |
| Section header and footnote inset | 16 inside the card edge, so 32 from the screen edge | |
| Card | fill `surface`, 1 pt border `line`, radius 12, content clipped | |
| Row separator | 1 pt `nude`, full card width (not inset) | |
| Navigation row | min height 52, padding 8 × 16 (10 × 16 for a row with a progress bar), gap 12; title/subtitle gap 2 | |
| Overview row | min height 48, padding 6 × 16, gap 12 | |
| Label–value row | min height 48, padding 0 × 16 | |
| Compass row | min height 56, padding 8 × 16, gap 12 | |
| Bottom action bar | padding 12 above, 16 on the sides, 8 above the bottom safe area; gap 10 between stacked buttons; background `ground` | |
| Primary button | height 52, radius 12 | v1 was 56 |
| Tinted row button | min height 44, padding 0 × 12, radius 8 | |
| Segmented control | height 44, track padding 2, track radius 9, segment radius 7 | v1 was 48 |
| Chips (not used on these screens) | min height 44, radius 8 | |
| Touch target | 44 minimum everywhere; 52 for primary actions | |
| Status glyph | 10 × 10 pt, gap 5 to its text | |
| Chevron | 8 × 14 pt | |
| Add / remove circle | 22 × 22 pt | |
| Progress bar | 4 pt tall, radius 2 | |
| Sheet radius | 16 (system sheet, with grabber) | |
| Alert | system alert (270 pt wide, title 17 semibold, message 13, two 44 pt buttons) | |

### 2.4 Components (exact drawings)

#### 2.4.1 `ChapterSection(header:footer:) { rows }`
A VStack with spacing 6 holding: an optional header (footnote, uppercase, muted, leading padding
16), then the card (the rows with 1 pt `nude` dividers between them), then an optional footer
(footnote 13/17, muted, horizontal padding 16, wrapping). A section without a header draws only
the card (step 2, first card).

#### 2.4.2 Rows
| Row | Drawing |
|---|---|
| `NavigationRow(title:subtitle:detail:status:)` | HStack spacing 12: VStack(spacing 2) {title `body` ink; subtitle `footnote` muted, up to 2 lines}; then optional detail text (`body` muted, e.g. "Change") or optional `StatusLabel`; then a chevron (path `M1 1l6 6-6 6`, stroke `chevron` 2 pt, round caps and joins). The whole row is a button with min height 52 and padding 8 × 16. |
| `ProgressNavigationRow` | Like NavigationRow, but the VStack spacing is 6 and it ends with the progress bar: track `nude`, fill `ink`, height 4, radius 2, width = fraction. Padding 10 × 16. |
| `ValueRow(label:value:)` | HStack spacing 12: label `body` ink (flexible), value `body` muted (trailing). Min height 48, padding 0 × 16. Not tappable. |
| `ProminentTextRow(text)` | `bodyEmphasis` ink, min height 52, padding 10 × 16. Used for the address. |
| `ToggleRow(label:isOn:)` | Label `body` ink (flexible) and a system `Toggle` with `.tint(ink)` and its label hidden. Min height 52, padding 8 × 16. The tokens say "Toggle: system, tint ink". The bundle's off-state track `#D9CCBC` is not reproduced; the system off track is accepted. |
| `TextFieldRow(label:text:)` | Label `body` ink (fixed width), then a TextField `body` ink, right-aligned and flexible. Min height 52, padding 0 × 16. |
| `AddRow(title:)` | A 22 pt circle filled `ready` with a centred plus (bars 10 × 2 and 2 × 10, `surface`), then the title `body` ink. Min height 48, padding 0 × 16, gap 12. Button. |
| `RemovableRow(title:subtitle:onRemove:)` | A 22 pt circle filled `blocked` with a 10 × 2 `surface` bar. It is a button with a 44 pt hit area and accessibility label "Remove [title]". Then a VStack(spacing 2) {title `body`; subtitle `footnote` muted}. Min height 52, padding 8 × 16, gap 12. |
| `TextAreaRow` | TextEditor `body` 17/22, min height 72, padding 14 × 16, hidden scroll background. |

#### 2.4.3 Buttons (`ChapterButtonStyle`)
| Kind | Drawing |
|---|---|
| `.primary` | Height 52, full width, radius 12, fill `ink`, text `bodyEmphasis` `surface`. |
| `.primary` disabled | Fill `line #D9CCBC`, text `bodyEmphasis` `disabledText #4E493F`. Not drawn with opacity. The disabled label is different text that says what is missing (each screen gives it). |
| `.tinted` | Height 52, radius 12, fill `nude`, text `body` ink. |
| `.rowAction` | Min height 44, padding 0 × 12, radius 8, fill `nude`, text `subhead` ink. |
| `.outlineOnDark` | Height 52, radius 12, 1 pt `surface` border, clear fill, text `body` (regular) `surface`. |
| `.filledOnDark` | Height 52, radius 12, fill `surface`, text `bodyEmphasis` ink. |
| `.cardAction` | Height 44, padding 0 × 16, radius 10, fill `nude`, text `subhead` ink. Used inside the tracking-lost card. |

#### 2.4.4 `ChapterSegmented(selection:options:)`
The track is `nude`, height 44, padding 2, radius 9, with N equal columns. A segment is a button
with radius 7. Unselected: clear background, `subhead` regular ink. Selected: `surface` fill,
`subheadEmphasis` ink, shadows `0 3 8 rgba(0,0,0,0.12)` and `0 3 1 rgba(0,0,0,0.04)`. Accessibility:
each segment is a button with the `.isSelected` trait when chosen, and the group is labelled
(for example "Mode"). Selecting a segment fires `.selection` haptic feedback.

#### 2.4.5 `Banner(icon:text:)`
HStack aligned to the top, spacing 10, padding 12 × 16, radius 12, fill `nude`. The icon is 18 × 18
in ink, offset 1 pt from the top; the offline icon is SF Symbol `wifi.slash`. The text is `subhead`
15/20 ink, wrapping.

#### 2.4.6 `StatusLabel(kind:word:)` and the glyphs
HStack spacing 5: a 10 × 10 glyph, then the word in `subhead` (15). When a status is a subtitle,
the word is in `footnote` (13) with the same glyph.

| Kind | Glyph (10 pt viewBox) | Glyph colour | Text colour |
|---|---|---|---|
| `.done` (●) | circle cx 5 cy 5 r 4.5, filled | `#2E5E2E` | `#2E5E2E` |
| `.partly` (▲) | path `M5 .6 9.6 9.4H.4z`, filled | `#9A6A1E` | `#7A5214` |
| `.missing` (■) | rect x .6 y .6 w 8.8 h 8.8, filled | `#8B2E2E` | `#8B2E2E` |
| `.waiting` (○) | circle r 4.5, 1 pt stroke, no fill | `#6B6557` | `#6B6557` |

Glyphs are hidden from accessibility; VoiceOver reads the word.

#### 2.4.7 `CompassGlyph(state:rotation:size:)`
Drawn in a 32 × 32 viewBox and scaled to `size`:
- Ring: circle at (16, 18), r 10.5, 1 pt stroke `ink`, no fill. In the approximate state the ring is dashed 1.6 / 1.6.
- Arrow: polygon (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5), 1 pt stroke `ink` with round joins. Verified: filled `ink`. Approximate: filled `surface`.
- "N": `glyphN` (Inter SemiBold 7), `ink`, centred at x 16 with its baseline at y 5.
- The whole glyph rotates by `rotation` degrees about its centre. Rotation = −(the heading of the direction the phone faces), so the arrow points at north on screen. Updates are throttled to 4 Hz, with no animation when Reduce Motion is on.
- Not verified, or no reading yet: only the ring, dashed 1.6 / 1.6, in `muted`. No arrow and no "N" (north-arrow v2: "No arrow, ever").

Live-scan variant `CompassPillGlyph` (14 × 14, drawn on the dark screen): the arrow-only polygon
(16,4) (22,28) (16,23) (10,28) in a 32 viewBox. Verified: filled `surface`. Approximate: 1.5 pt
`surface` stroke, no fill. Not verified: no glyph.

#### 2.4.8 `ChapterLogo(height:)`
Draws the generated logo paths (§2.6), filled `#231F20`, with aspect 1756 : 635. Its accessibility
label is "Chapter Renovation" and it is one element. Size on the Captures home: **26 pt tall,
72 pt wide**, which is the footprint of the drawn wordmark. On the sign-in screen: 40 pt tall.

#### 2.4.9 `AvatarButton(initials:name:)`
A 36 × 36 circle filled `nude`, showing the initials in `footnoteEmphasis` (13/600) ink. Hit area
44 × 44. Accessibility label "Signed in as [OPERATOR]". The initials are the first letter of the
first two words of the operator's name, uppercased ("Dana Ruiz" gives "DR", "Field test" gives
"FT"). An empty name shows "?".

### 2.5 Navigation (`ChapterAppearance.apply()`, called once at launch)

- Use the system `NavigationStack` and navigation bar. The tokens say "System navigation bar,
  large title on root and form screens … Back is the system chevron (44 pt glass pill in iOS 26)."
- `UINavigationBarAppearance` (standard and scrollEdge):
  - background `ground #F5EFE6`, no shadow line;
  - `largeTitleTextAttributes`: Times New Roman 34 scaled with `UIFontMetrics(forTextStyle: .largeTitle)`, colour ink;
  - `titleTextAttributes`: Inter SemiBold 17 scaled for `.headline`, ink;
  - button text Inter 17, ink.
- Back shows the chevron only: `.toolbarRole(.editor)` on pushed screens (`backButtonDisplayMode =
  .minimal`). On iOS 26 the system draws the 44 pt glass pill.
- The right-hand caption ("Step 1 of 3", "Deal [DEAL ID]") is a `ToolbarItem(placement:
  .topBarTrailing)` showing `footnote` muted text. It is not a button.
- Sheets: system sheets with a grabber, radius 16 (system), and a 52 pt bar with Cancel, title
  and Save where needed.
- The live scan is a `fullScreenCover` with no navigation bar and a light status bar
  (`.preferredColorScheme(.dark)` on the cover only).

### 2.6 Fonts and logo assets

- `tools/brand/generate_plan_brand.py` gains two outputs. Its inputs stay the same (the logo SVG
  and Inter's variable TTF):
  1. `ios/Packages/ChapterUI/Sources/ChapterUI/Fonts/Inter-Regular.ttf` and `Inter-SemiBold.ttf`:
     static instances at wght 400 and 600, **not subset** (the phone needs full Latin plus
     punctuation; size is about 300–400 KB each). PostScript names `Inter-Regular` and
     `Inter-SemiBold`. Add the SIL OFL 1.1 text as `ios/Packages/ChapterUI/THIRD_PARTY_NOTICES.md`,
     copied from PlanExport's.
  2. `ios/Packages/ChapterUI/Sources/ChapterUI/ChapterLogoData.swift`: the header "Generated by
     tools/brand/generate_plan_brand.py. Do not edit.", `logoWidth = 1756`, `logoHeight = 635`, and
     the same `M/C/Z` path string as `ChapterBrandAssets.logoPaths` (y up from the lower left).
     `ChapterLogo` flips y when it builds the SwiftUI `Path`.
- Package resources: `resources: [.process("Fonts")]`. `ChapterFonts.register()` calls
  `CTFontManagerRegisterFontsForURL(url, .process, nil)` for both files in `Bundle.module`. It is
  idempotent: "already registered" is not an error. Call it in `ChapterCaptureApp.init()` and in
  the setUp of every snapshot test.
- Do not use `UIAppFonts` in Info.plist, because package bundles are not visible to it.

---

## 3. Screens

### 3.0 Navigation map (v2)

```
Launch ─► Sign-in (unchanged flow) ─► Captures home (root of the NavigationStack)
Captures home
  ├─ "New capture" ─► New capture (step 1) ─► What are you scanning? (step 2) ─► Live scan (full-screen cover)
  │                                                                              └─ Finish floor ─► stack becomes [Overview, Photos(floor)]  (Photos = phone-field)
  ├─ In progress row ─► Capture overview
  ├─ Sealed row ─► Verdict received (phone-package)
  └─ Avatar ─► account dialog (Sign out)
Capture overview
  ├─ Floor row ─► Floor scan (existing ScanViewer, pushed)
  ├─ "Scan another floor or room" ─► What are you scanning? (step 2, project fixed) ─► Live scan ─► [Overview, Photos(new floor)]
  ├─ Photos ─► Photo labeling (phone-field), at the first room without a photo
  ├─ Field controls ─► Field controls list (phone-field)
  ├─ Compass ─► Before you leave (phone-field), scrolled to "Compass reading"
  ├─ Rooms not scanned ─► Before you leave (phone-field), scrolled to "Rooms not scanned recorded"
  └─ "Review the package" ─► Package ready (phone-package)
```

"Done with photos" (phone-field) pops back to the overview. In v1 it went on to field controls;
see §5.3. Every pushed screen goes back with the system back chevron. When a NavigationStack
route has no target built yet (another area not landed), it shows the v1 screen.

### 3.1 Captures home (artboard 2b-0), NEW

**Purpose.** The app's root screen. It lists every capture on this phone: unsealed ones, sealed
ones still uploading or waiting for a verdict, and those with a verdict.

**Layout, top to bottom.**
1. Navigation bar, 44 pt. Leading: `ChapterLogo` 26 pt tall. Trailing: `AvatarButton`.
2. Large title **"Captures"**.
3. Scroll content, padding 16 × 16, section gap 18:
   - Section **"In progress"** (shown when it has rows). One card with a row per capture
     (§3.1.1).
   - Section **"Sealed"** (shown when it has rows). One card with a row per capture (§3.1.2).
   - Footnote under the last section shown: **"Files stay on this phone until the station
     confirms each one. Verdict details are in the HUB."**
4. Bottom bar: primary button **"New capture"** (`captures.newCapture`).

#### 3.1.1 In progress rows
One row per capture (visit workspace) that is not yet sealed, or whose newest package has no
verdict yet. Newest activity first. Each row navigates to the Capture overview.

| Case | Row | Title | Subtitle (footnote, muted) | Trailing |
|---|---|---|---|---|
| Not sealed | NavigationRow | project title † | `"[N] floor"` / `"[N] floors"` + `" · not sealed yet"` | chevron |
| Sealed, uploading | ProgressNavigationRow | project title | `"[N] floors · uploading · 512 of 768 MB"` (`UploadProgressSummary.bytesText`) | chevron |
| Sealed, paused offline (`waitingToRetry`) | ProgressNavigationRow | project title | `"[N] floors · upload paused · 512 of 768 MB"` | chevron |
| Sealed, sign-in required | NavigationRow | project title | `"[N] floors · sign in to upload"` | chevron |
| Sealed, upload failed (`failed`) | NavigationRow | project title | `"[N] floors · upload failed"` | `StatusLabel(.missing, "Failed")`, chevron |
| Sealed, all files confirmed, no verdict yet | NavigationRow | project title | `"[N] floors · uploaded · checks running"` | `StatusLabel(.waiting, "Checking")`, chevron |
| Revision R+1 started after a verdict | NavigationRow | project title | `"[N] floors · revision [R+1] not sealed yet"` | chevron |

† Project title = `record.hub.projectName` when it is not empty, else `record.address.formatted`.
This is the same rule as today's `NewCaptureScreen.projectTitle`.

Only the "uploading" row is drawn in the bundle. The other subtitles are derived; see §11, Q1.

#### 3.1.2 Sealed rows
One row per capture whose newest package has a station verdict. Newest `manifest.sealedAt`
first. Each row navigates to Verdict received (`phone-package`).

| Verdict | Subtitle | Trailing status |
|---|---|---|
| limited | `"Revision [R] · sealed [MMM d, yyyy]"`, e.g. "Revision 1 · sealed Jan 25, 2025" | `StatusLabel(.partly, "Limited")` |
| ready | `"Revision [R] · sealed [MMM d, yyyy]"` | `StatusLabel(.done, "Ready")` |
| blocked | `"Revision [R] · re-seal needed"` | `StatusLabel(.missing, "Blocked")` |

R is `manifest.revision`. The date is `manifest.sealedAt`, formatted `MMM d, yyyy` in the
en_US_POSIX locale and the device time zone. Rows are NavigationRows (min height 52, padding
8 × 16), with title and subtitle gap 2.

#### 3.1.3 States
| State | What is shown |
|---|---|
| Empty (no capture on the phone) | No sections. One section with no header: a card with one non-tappable row (min height 52, padding 10 × 16), text **"No captures on this phone yet."** in `body` muted. Footnote **"Tap New capture to scan a floor or room."** The New capture button as usual. (Not drawn; recommended default.) |
| Loading (reading disk, > 300 ms) | `ProgressView` centred in the content. Normally not visible. |
| Refresh | Pull to refresh (`.refreshable`) re-reads the disk and asks the station for the stage and verdict of each package that is fully uploaded but has no verdict yet. The same refresh runs on appear and when the scene becomes active. |
| Offline | Rows show what is stored. Uploads say "upload paused". No banner on this screen. |
| Many captures | The content scrolls. The bottom bar stays pinned. |

#### 3.1.4 Account (the avatar)
Tapping the avatar opens a `confirmationDialog` titled **"Signed in as [OPERATOR]"**, with the
buttons **"Sign out"** (`account.signOut`) and **"Cancel"**. When sealed packages are waiting for
the station, the message is **"Uploads resume after you sign in again."** Sign-out works as today
(`AppModel.signOut()`): it deletes no file, and in-progress captures and pending uploads stay on
the phone. This replaces the v1 `AccountFooter` on New capture. The v1 "My scans" sheet is removed:
the home is the list of scans, and each floor's scan opens from the overview.

### 3.2 New capture, step 1 (artboard 2b-1)

**Layout.**
1. Navigation bar: system back (to Captures). Trailing caption **"Step 1 of 3"**.
2. Large title **"New capture"**.
3. Content, padding 16 × 16, section gap 18:
   - Section **"HUB project"**: one NavigationRow (`capture.project`).
     - Chosen: title = project title (§3.1.1 †); subtitle **"Deal [DEAL ID] · from the HUB, updated 2 min ago"**; detail **"Change"** (`body` muted); chevron.
     - None chosen: title **"Choose a HUB project"** (`body` muted); subtitle **"Projects come from the HUB"**; detail **"Choose"**.
     - Loading the list: subtitle **"Loading projects from the HUB…"**.
     - "updated …" uses the relative-age rule in §5.6 ("just now", "2 min ago", "3 h ago", "on Oct 20").
   - Section **"Address in the HUB"**: a card with two rows.
     - ProminentTextRow: the HUB address exactly as stored (`HubProjectSummary.address`), e.g. **"618 Valley Street, [CITY, STATE ZIP]"**. With no project: **"Choose a HUB project first"** in `body` muted.
     - ToggleRow **"I am at this address"** (`capture.addressConfirmed`). Disabled while no project is chosen.
     - Footer: **"If the address on site is different, stop and call the PM. The station blocks packages with a different address."** (v1 said "mismatched address".)
   - Section **"Recorded automatically"**: three ValueRows.
     - **"Operator"** / `[SIGNED-IN NAME]` (`draft.operatorName`).
     - **"Device"** / `"[marketing name] · LiDAR"`, e.g. "iPhone 16 Pro · LiDAR", or `"[marketing name] · no LiDAR"`. The marketing name comes from §5.7 and falls back to the model identifier. The v1 "✓ / ✗" marks are removed.
     - **"App"** / `"[version] ([build])"`, e.g. "1.0.0 (37)".
4. Bottom bar, primary button (`capture.continue`):

| Condition (first that applies) | Label | Enabled |
|---|---|---|
| Device fails the gate | **"This phone cannot scan"** | no |
| No project chosen | **"Choose a HUB project to continue"** | no |
| Address not confirmed | **"Confirm the address to continue"** (drawn in 1c) | no |
| List is the offline copy | **"Continue offline"** (drawn in 1b) | yes |
| Otherwise | **"Continue"** | yes |

**Interactions.**
- The project row opens the **HUB project sheet**: a system sheet, inline title **"HUB project"**,
  and **"Cancel"** in the leading slot. Its content is a ChapterSection holding one NavigationRow
  per project: title = project title, subtitle = the address, no detail. Tapping a row chooses the
  project (`draft.select`, which clears the address confirmation when the project changes) and
  closes the sheet. Empty list: the text **"No HUB projects."**. Error: the error text (§3.2.3).
- The toggle ON calls `setAddressConfirmed(true)` and records `addressConfirmedAt`, as today.
- The toggle going ON → OFF shows the **address-different alert** (§3.2.2) after the toggle has
  turned off.
- "Continue" pushes step 2.

#### 3.2.1 State: offline at New capture (artboard 2b-1b)
This state applies when `ProjectStore.projects()` returned the saved list
(`ProjectList.isStale == true`).
- The first content item is a `Banner` with the `wifi.slash` icon and the text: **"No connection.
  Showing the [N] projects saved on this phone (updated [MMM d, HH:mm]). You can scan offline; the
  upload waits for a connection."** For example: "…Showing the 12 projects saved on this phone
  (updated Oct 20, 14:12)…". With N = 1 the text is "the 1 project". The date is
  `ProjectList.fetchedAt`, formatted `MMM d, HH:mm`, en_US_POSIX, 24 h, device time zone.
- The HUB project row's subtitle becomes **"Deal [DEAL ID] · saved on this phone"**.
- The HUB project section's footer: **"A project not in this list cannot be started offline: the deal id must come from the HUB."**
- The button says **"Continue offline"**.
- The bundle drew "Recorded automatically" without the App row here. That looks like a space
  saving; the App row stays (§11, Q11).
- **Offline with no saved list** (not drawn): banner **"No connection and no projects saved on
  this phone. Connect once to load the HUB projects."**; the HUB project row is in its "none
  chosen" state and disabled; the button is disabled with the label **"Connect to load projects"**.

#### 3.2.2 State: address different on site (artboard 2b-1c)
- The toggle is OFF. The button is disabled with the label **"Confirm the address to continue"**.
- A system alert:
  - title **"Address is different on site?"**
  - message **"Do not scan under this project. Call the PM to fix the HUB record, then start the capture again. Nothing is saved."**
  - buttons, in this order: **"Go back"** (cancel role) and **"Call the PM"** (default, bold).
- **Go back** closes the alert and stays on New capture, with the toggle OFF and the project kept.
  The operator can pick another project.
- **Call the PM**: if the project has a PM phone number (§7, optional addition), open
  `tel:<number>`. Either way, the draft is then discarded and the app pops to the Captures home.
  "Nothing is saved": no workspace folder exists yet (§5.2).

#### 3.2.3 Other states (not drawn)
| State | Shown |
|---|---|
| Device gate fails (no LiDAR, no RoomPlan, iOS < 17) | A `Banner` with a ■ glyph (blocked) as icon and the `DeviceGateResult.message` text (unchanged wording), first in the content. Button "This phone cannot scan". |
| Project list error (not offline: 403, 5xx, invalid) | A `Banner` with the ■ icon and **"Could not load HUB projects: [message]"** (v1 wording), plus a `.rowAction` button **"Try again"** inside the banner, at the trailing edge. |
| Station says sign in again (401) | Existing behaviour: `AppModel.requireSignIn()` shows the sign-in screen and returns here afterwards. |

### 3.3 What are you scanning?, step 2 (artboard 2b-2)

**Layout.**
1. Navigation bar: back (to step 1, or to the overview when adding a floor). Trailing caption:
   **"Step 2 of 3"** for a new capture. When adding a floor from the overview, the caption is the
   project title, e.g. **"618 Valley Street"** (§11, Q6).
2. Large title **"What are you scanning?"**.
3. Scroll content, padding 14 × 16, section gap 14. The keyboard is dismissed by scrolling
   (`.scrollDismissesKeyboard(.interactively)`). The bottom bar stays above the keyboard
   (`safeAreaInset`), as v1 does today.
   - **Card 1, no header:**
     - TextFieldRow, label **"Name"**, field accessibility label **"Floor or area"**
       (`capture.floorName`). Value: prefilled with the next free **"Floor [N]"**, where N = the
       number of captures in the visit + 1, raised until its area key is unused. Placeholder
       "Floor 1". Return key "Done". (§11, Q5)
     - A second row (padding 8 × 16, separator above) with `ChapterSegmented`, group label
       **"Mode"**, options **"One room"** / **"Whole floor"** / **"Exterior"**
       (`capture.mode.room` / `.floor` / `.exterior`). There is no default: nothing is selected
       until the operator taps.
   - Section **"Rooms you will not scan"**:
     - One `RemovableRow` per entry of `draft.omittedRooms`: title = name; subtitle = reason with
       its first letter uppercased (stored "locked" shows as **"Locked"**); no subtitle when there
       is no reason. The remove button's accessibility label is **"Remove [name]"**
       (`capture.removeSkippedRoom.[index]`).
     - `AddRow` **"Add a room you cannot scan"** (`capture.addSkippedRoom`). It opens a system
       alert titled **"Add a room you cannot scan"**, message **"A room you will not scan, for
       example a locked closet."**, text fields **"Room name"** and **"Reason (for example locked)"**,
       and buttons **"Cancel"** / **"Add"**. Add with an empty name does nothing (v1 behaviour).
   - Section **"Coverage notes"**: a `TextAreaRow` bound to `draft.coverageNotes`
     (`capture.coverageNotes`, accessibility label **"Coverage notes"**). Placeholder **"Optional"**
     in muted. Maximum 2000 characters (existing validation).
   - Section **"Compass"**: one compass row (§3.3.1).
     - Footer: **"Read automatically. Hold the phone flat, away from steel and appliances. Approximate or missing readings are shown as such on the plans."**
     - When location permission is denied, a second footer paragraph (not drawn): **"Location is off for Chapter Capture, so north is magnetic and shown as approximate. Turn it on in Settings for true north."**
4. Bottom bar, primary button (`capture.startScan`):

| Condition (first that applies) | Label | Enabled |
|---|---|---|
| Device gate fails | "This phone cannot scan" | no |
| Name empty | **"Enter the floor or area"** | no |
| Name has no letters or digits | **"Use letters or numbers in the name"** | no |
| Name's area key already used in this visit | **"[Name] is already captured. Use another name"** | no |
| No mode chosen | **"Choose what you are scanning"** | no |
| Other validation error | the error's description without its final period | no |
| Otherwise | **"Start scan"** | yes |

The compass state never blocks Start scan ("The compass is recommended, not required").

The duplicate-name check is new. In v1 the duplicate area key was refused only after the scan
(`VisitFlowError.duplicateCapture`), which lost the scan.

#### 3.3.1 Compass row (`compass.row`)
HStack, min height 56, padding 8 × 16, gap 12:
- `CompassGlyph` 32 pt (§2.4.7). Its rotation follows the phone while the reading runs; after a
  reading it is frozen at −(heading of that reading).
- VStack(spacing 2): a title (`body`) and a status line (`footnote` with a 10 pt glyph, gap 5).
- Trailing: a `.rowAction` button **"Read again"** (`compass.readAgain`). It is hidden while a
  reading is in progress and when the phone has no compass.

| State | Title | Status line (glyph · text) |
|---|---|---|
| Reading (auto on appear, or after Read again) | **"Reading the compass…"** | ○ muted · **"Hold the phone flat"** |
| Verified (true north, accuracy ≤ 10°) | **"North [HDG]° true · ±[ACC]°"**, e.g. "North 212° true · ±8°" | ● ready · **"Verified · read [AGE]"**, e.g. "Verified · read 12 s ago" |
| Approximate, true north (10° < accuracy ≤ 30°) | **"North [HDG]° true · ±[ACC]°"** | ▲ limitedText · **"Approximate · read [AGE]"** |
| Approximate, magnetic (location off or no fix, accuracy ≤ 30°) | **"North [HDG]° magnetic · ±[ACC]°"** | ▲ · **"Approximate · magnetic · read [AGE]"** |
| Not verified, accuracy > 30° | **"Compass not verified"** | ▲ · **"Accuracy too low · read [AGE]"** |
| Not verified, no valid sample within 8 s | **"Compass not verified"** | ▲ · **"No compass reading"** |
| Not verified, unsteady (every 2 s window spread > 20° within 8 s) | **"Compass not verified"** | ▲ · **"Reading rejected · read [AGE]"** |
| No compass on this phone (`CLLocationManager.headingAvailable() == false`) | **"Compass not verified"** | ▲ · **"No compass on this phone"** |

- [HDG] is the heading rounded to an integer in 0–359 (360 shows as 0). [ACC] is the accuracy
  rounded up to an integer.
- [AGE] is "N s ago" under 60 s, "N min ago" under 60 min, then "at HH:mm". It is refreshed every
  second by a `TimelineView(.periodic(from:by: 1))`.
- Not verified uses ▲ and never ■. Red is only for items that block the package, and the compass
  does not block.
- Accessibility: one element with the label "Compass, [title spoken], [status]". Degrees are
  spoken: "North 212 degrees true, plus or minus 8 degrees, Verified, read 12 seconds ago". The
  Read again button is a separate element. There is no text field and no way to edit or type a
  heading (§4.6).
- **The step 2 reading is a check, not the recorded value.** It shows the operator that the
  compass is good at this spot. The value written to the capture record is measured at scan start
  in the scan's own frame (§4.3). The step 2 reading is not stored.

### 3.4 Live scan (artboard 2b-3) and its states

Presented as a full-screen cover over step 2. Background `ink #1F2429`, light status bar, no
navigation bar. There is no back control while scanning (as drawn).

**Layout (normal state, 2b-3).**
1. Top row (fills the 44 pt below the safe area, padding 0 × 16, space-between):
   - Title pill (`scan.title`): height 36, padding 0 × 14, radius 18, fill `onDarkPill`, text
     `subheadEmphasis` `surface`: **"[Name] · [Mode]"**, e.g. "Floor 1 · Whole floor".
   - Timer pill (`scan.elapsed`): same pill, `mono` 15 `surface`: **"06:42"** (mm:ss of running
     time; minutes may pass 59, e.g. "72:05"). Accessibility label "Elapsed 6 minutes 42 seconds".
2. Camera well: margin 12 above and 16 on the sides, fills the remaining height, radius 16, fill
   `scanWell`, 1 pt border `scanWellBorder`, padding 14. The live `CaptureSessionPreview` is
   clipped to it. Overlays, in a VStack with space-between:
   - **Coaching pill** (`scan.guidance`), top-left: padding 8 × 12, radius 8, fill `surface`.
     Line 1: `ScanGuidance.title` in `subheadEmphasis` ink, e.g. **"Move slowly along the walls"**.
     Line 2 (not drawn; keeps the field-tested guidance, §11, Q3): `ScanGuidance.detail` in
     `footnote` ink, up to 3 lines. The pill's maximum width is the well width minus 28. The v1
     "Step N of 4" line is dropped. For a RoomPlan warning (`isWarning`), line 1 starts with a 10 pt
     ▲ glyph (`limited`) and a 5 pt gap.
   - The bundle's "[LIVE CAMERA + ROOMPLAN OVERLAY]" marks where the camera feed goes. It is not
     text to show in any build. With no feed (replay and UI tests), the well stays plain
     `scanWell`.
   - **Counts**: 4 equal columns, gap 8, centred: the value in `count` (22/600) `surface`, then the
     label in `caption` (12) `onDarkCaption`, gap 2. Labels **"walls"**, **"doors"**, **"windows"**,
     **"rooms"**. Each column is one accessibility element ("11 walls").
3. Status row: padding 12 above, 16 on the sides; HStack spacing 10:
   - **Compass pill** (`scan.compass`): height 32, padding 0 × 10, radius 16, fill `onDarkPill`,
     HStack spacing 6 with `CompassPillGlyph` 14 and text in `footnote` `surface`:

     | Compass state of this floor's scan | Glyph | Text |
     |---|---|---|
     | measuring (first seconds) | none | **"Compass · reading"** |
     | verified | filled arrow | **"N · true · ±[ACC]°"**, e.g. "N · true · ±8°" |
     | approximate, true | outline arrow | **"N · approx. · ±[ACC]°"** |
     | approximate, magnetic | outline arrow | **"N · magnetic · ±[ACC]°"** |
     | not verified | none | **"Compass not verified"** |

     The glyph rotates by −(heading the camera faces) at up to 4 Hz, so it points at north
     relative to the phone.
   - **Recording status** (`scan.status`): an 8 × 8 dot (`surface`) and **"Recording LiDAR depth
     and mesh · saved on this phone"** in `footnote` `onDarkCaption`. If no depth sample and no
     mesh anchor has arrived after 5 s of normal tracking (`ScanProgress.depthSampleCount == 0 &&
     meshAnchorCount == 0`), the text becomes **"Recording the room outline only · saved on this
     phone"**, so it stays truthful.
4. Bottom: padding 12 above, 16 on the sides, 8 above the safe area; 2 equal columns, gap 12:
   - **"Pause"** (`scan.pause`), `.outlineOnDark`. While paused it reads **"Resume"**.
   - **"Finish floor"** (`scan.finish`), `.filledOnDark`. Disabled at opacity 0.4 while the
     live wall count is 0 (§3.4.4).

**Haptics (keep from v1).** A soft pulse every 1.2 s while scanning normally; a medium tap for each
new wall, door, window or object; a warning on a RoomPlan instruction; an error on failure; a
selection tick on Pause and Resume. New: a warning when tracking is lost and a success tap when it
comes back.

#### 3.4.1 State: tracking lost (artboard 2b-3b)
**Trigger** (§5.5): ARKit tracking is `.notAvailable` or `.limited(.relocalizing)` for ≥ 1.0 s,
or any `.limited` reason for ≥ 3.0 s. **Cleared** after `.normal` for ≥ 0.5 s. RoomPlan's session
keeps running; this is not a user pause.

Changes from the normal state:
- The well fill becomes `scanWellDimmed #23282D`.
- The coaching pill is replaced by a translucent pill: padding 8 × 12, radius 8, fill
  `onDarkPill`, text `subheadEmphasis` `surface`: **"Paused · [mm:ss]"**, where mm:ss is the time
  since tracking was lost, e.g. "Paused · 00:06".
- **Card** (`scan.trackingLost`, accessibility role alert), centred in the well: width 280, padding
  18 top and 16 on the other sides, radius 16, fill `alertCard`, ink, centred text, VStack spacing 8:
  - a ▲ glyph 22 × 22 (`limited #9A6A1E`);
  - **"Tracking lost"** in `bodyEmphasis`;
  - **"Point the camera at a wall you already scanned and hold still. Scanning continues on its own. Nothing is lost."** in `subhead` 15/20;
  - 6 pt extra top margin, then the button **"Restart this floor instead"** (`scan.restartFloor`), `.cardAction`.
  - On appear, post a VoiceOver announcement with the title and body text.
- The counts are drawn at opacity 0.5.
- Recording status: the dot becomes `limited #9A6A1E` and the text **"Recording paused · [W] walls
  kept"** (W = the current wall count). Depth, pose and mesh sampling really are paused while
  tracking is not normal (§5.5), so the text is true.
- The compass pill is unchanged.
- **Pause** is disabled at opacity 0.4. **Finish floor** stays enabled but is drawn at opacity 0.5,
  as drawn (finishing keeps what was scanned; §11, Q4).
- The top timer keeps counting (the bundle goes from 06:42 to 06:48).
- **"Restart this floor instead"** shows a confirmation alert (not drawn; §11, Q4): title
  **"Restart [Name]?"**, message **"The [W] walls scanned so far are discarded. The compass is read
  again."**, buttons **"Cancel"** / **"Restart"** (destructive). Restart cancels the session
  (nothing is written) and starts a new one with the same draft (`CaptureFlowModel.restartFloor()`).

#### 3.4.2 State: paused by the operator (not drawn; derived from 3b)
- The coaching pill becomes the translucent pill **"Paused · [mm:ss since pause]"**. Its second line
  is `ScanGuidance` paused detail in `footnote` `onDarkCaption`: **"Walk to the next room or area,
  point at a wall you already scanned, then tap Resume."**
- Recording status: `limited` dot and **"Recording paused · [W] walls kept"**.
- The timer stops (paused time is not counted, as in v1).
- **"Resume"** and **"Finish floor"** are both enabled at full opacity.

#### 3.4.3 State: scan stopped (RoomPlan ended on its own, or could not start)
This restyles v1's failed state. It covers too hot, tracking failure that ended the session, area
too large, and other errors.
- The card has the same geometry as the tracking-lost card, with a ■ glyph 22 pt (`blocked`), the
  title **"Scan stopped"**, and as body the `CaptureSessionError.description` (v1 wording, e.g. "The
  phone is too hot to scan. Let it cool down for a few minutes, out of the sun and out of its case,
  then tap Try again."). The card has no button of its own.
- The counts are at opacity 0.5. The status dot is `blocked` with the text **"Recording stopped"**.
- Bottom: **"Back"** (`.outlineOnDark`; it cancels and returns to step 2) and **"Try again"**
  (`.filledOnDark`, `scan.tryAgain`).

#### 3.4.4 Finish floor
- Runs the existing `finishFloor()`: it writes the originals, maps the model, and puts the compass
  reading into the capture (§4.4). Then it closes the cover.
- The App replaces the navigation stack with `[Overview(visit), Photos(captureId)]`, so the photo
  step (phone-field) appears and back leads to the overview.
- While finishing, the bottom bar shows a `ProgressView` in `surface` on the Finish button, and
  both buttons are disabled.
- **Nothing captured yet.** While the live wall count is 0, **Finish floor** is disabled at
  opacity 0.4, so the operator cannot end an empty scan. In v1, `LiveCaptureSession.finish()`
  threw `noRoomsCaptured` and also ended the session. If `noRoomsCaptured` still arrives (a race
  with RoomPlan's last update), show the scan stopped state (§3.4.3) with its v1 text "Nothing was
  captured. Scan at least one wall before finishing." and the buttons Back / Try again (§11, Q12).

### 3.5 Capture overview (artboard 2b-4), NEW

**Purpose.** The home of one capture (one visit): its floors and areas, the before-you-leave
state, and the way to the package.

**Layout.**
1. Navigation bar: back (to Captures; accessibility label **"Back to captures"**). Trailing caption
   **"Deal [DEAL ID]"** (`record.hub.dealId`).
2. Large title: the project title (§3.1.1 †), e.g. **"618 Valley Street"**. It is truncated with a
   tail ellipsis on one line (system large title).
3. First content line, 8 pt under the title: the subtitle in `subhead` muted:
   **"Captured [WHEN] by [OPERATOR] · [SEAL STATE]"**, for example "Captured today by Dana Ruiz ·
   not sealed yet".
   - [WHEN] is based on `record.visitedAt`: "today", "yesterday", "Oct 20" (same year), or
     "Oct 20, 2025".
   - [OPERATOR] is `record.operator.name`.
   - [SEAL STATE] is "not sealed yet", "revision [R] sealed", or "revision [R+1] not sealed yet".
4. Content, padding 12 × 16, section gap 10:
   - Section **"Floors and areas"**, one card:
     - One row per capture, in capture order (`overview.floor.[areaKey]`), drawn as an overview row
       (min height 48, padding 6 × 16):
       - title = the capture label, e.g. **"Floor 1"**;
       - subtitle = **"[Mode] · [R] rooms · [P] photos · controls [STATE]"**, e.g. "Whole floor ·
         12 rooms · 42 photos · controls complete" or "Whole floor · 9 rooms · no photos yet ·
         controls missing". Mode uses the v1 titles (One room / Whole floor / Exterior). Write
         "1 room" / "1 photo" in the singular. P = 0 gives "no photos yet". R = 0 drops the rooms
         part. [STATE] is "complete" when A, B and a ceiling height are recorded for this floor,
         "missing" when none is, and "incomplete" otherwise (§11, Q7).
       - trailing `StatusLabel`: **"Done"** (●) when the floor has no photo gap and no per-floor
         control gap; otherwise **"Open"** (■ blocked, as drawn).
       - chevron. Tapping opens the floor's scan (the existing `ScanViewer`, pushed, inline title
         = label, without its "Done" button).
     - `AddRow` **"Scan another floor or room"** (`overview.addFloor`). It pushes step 2 with the
       visit's project and the address confirmation carried over (today's `addMoreRooms` draft
       rules). This replaces the v1 "Add more rooms".
   - Section **"Before you leave"**, one card with four overview rows (§3.5.1).
     - Footer: **"Photos and controls cannot be recovered later."**
5. Bottom bar, one button (`overview.review`):

| Condition | Label | Style | Action |
|---|---|---|---|
| Not sealed and N > 0 failing checklist items | **"Fix [N] item to review the package"** / **"Fix [N] items to review the package"**, e.g. "Fix 2 items to review the package" | primary, disabled | none |
| Not sealed, checklist passes | **"Review the package"** | primary | push Package ready (`phone-package`) |
| Sealed, upload not yet confirmed or no verdict | **"Upload status"** | primary | push Uploading (`phone-package`) |
| Sealed and changed since (revision R+1 draft) | **"Review revision [R+1]"** | primary | push revision 2 screen (`phone-package`) |

N = `ChecklistReport.failedItems.count`, the blocking FieldRules items. The compass is never
counted. The last two rows are recommended defaults; `phone-package` owns those screens (§11, Q8).

#### 3.5.1 Before you leave rows
Each row is an overview row with title, subtitle, trailing `StatusLabel` and chevron. The data is
the visit's `ChecklistReport` plus the compass state of each capture.

| Row (id) | Title | Subtitle when failing | Status when failing | Subtitle when passing | Status when passing | Tap |
|---|---|---|---|---|---|---|
| `overview.photos` | **"Photos"** | 1 gap: the gap text, e.g. **"Bath 2 has no photo"**. k > 1 room gaps: **"[first room] and [k−1] more rooms have no photo"**. A capture without photos: **"Floor 2 has no photo"**. | ■ **"Missing"** | **"Every room has a photo"** | ● **"Done"** | photo step (phone-field) for the first gap's capture and room, else the last capture |
| `overview.controls` | **"Field controls"** | **"[list] missing"**, built from the `minimumControls` gaps (rule below), e.g. **"Floor to floor and 1 landmark missing"** | ■ **"Missing"** | **"Minimum set complete"** | ● **"Done"** | field controls list (phone-field) |
| `overview.compass` | **"Compass"** | per floor, joined with " · ", e.g. **"Floor 1 verified · Floor 2 not read"** | ▲ word below | **"Every floor verified"** | ● **"Verified"** | Before you leave (phone-field), scrolled to "Compass reading" |
| `overview.skippedRooms` | **"Rooms not scanned"** | **"Record skipped rooms, or confirm none were skipped"** | ■ **"Missing"** | the recorded rooms: **"[name] · [reason]"**, e.g. "Primary closet · locked", then ", +[n] more"; or **"No rooms skipped"** when confirmed | ● **"Recorded"** | Before you leave (phone-field), scrolled to "Rooms not scanned recorded" |

How the controls list is built: go through the gaps in checklist order.
- When a floor misses A, B and the ceiling height together, write **"[Label] set"**.
- Otherwise write **"Long distance A"**, **"Long distance B"** or **"Ceiling height"**, each
  followed by " on [Label]" when the visit has more than one floor.
- A missing floor to floor is **"Floor to floor"**.
- A landmark gap is **"[need − have] landmark"** / **"landmarks"**.
- Join: one item "X missing"; two items "X and Y missing"; three "X, Y and Z missing"; four or
  more "X, Y and [n] more missing".

Compass status word over all floors (§4.5):
- every floor verified: ● **"Verified"**;
- every floor usable (verified or approximate) and at least one approximate: ▲ **"Approx."**;
- some floors usable and some not: ▲ **"Partly"** (drawn);
- no floor usable: ▲ **"Not verified"**.

The per-floor words in the subtitle are "verified", "approx.", "not verified" (a reading existed
but was rejected or too poor) and "not read" (no reading).

The compass row never shows ■ and never counts toward N.

#### 3.5.2 States
| State | Shown |
|---|---|
| One floor | One floor row and the add row. |
| Many floors | The content scrolls and the bottom bar stays pinned. |
| Sealed, uploading | The same sections. The rows stay tappable; the field screens decide what may change. Bottom "Upload status". |
| Opening a capture from the home after a relaunch | Rebuilt from disk (§5.2). While the scans' models load: the floor rows show title and mode, the subtitle **"Loading…"**, and no status. |
| A floor's model failed to map (`mappingError`) | Subtitle **"[Mode] · the scan could not be read"**, status ■ **"Open"**. The originals are kept. |

### 3.6 Sign-in and Not configured (brand only)
- `SignInView`: replace the typed serif wordmark with `ChapterLogo(height: 40)`. The title
  **"Sign in"** becomes `largeTitle` (Times 34). The text **"Use your Chapter Microsoft account."**
  uses `subhead` muted. The button **"Sign in with Microsoft"** / **"Signing in…"** uses
  `.primary` (52 pt). Messages keep their wording, prefixed by a ■ glyph drawn as a shape, not the
  "\u{25A0}" character.
- `NotConfiguredView`: the same wording, with ChapterTheme fonts (title `largeTitle`).

---

## 4. The compass: how it is read

The data contract (field names, JSON shape, schema version, state rules and the reason words)
belongs to area `compass`. This section says how the phone produces the reading and shows it. If
`compass` changes a threshold or a word, the classifier it ships is used and nothing here is
hard-coded.

### 4.1 Permissions and Info.plist
- Add `NSLocationWhenInUseUsageDescription`: **"Chapter Capture uses your location only to find
  true north for the plans. Your location is not saved."**
- Ask for When In Use authorization the first time step 2 appears
  (`CLLocationManager.requestWhenInUseAuthorization()` when the status is `.notDetermined`). Never
  ask anywhere else and never on launch.
- Location is used only for magnetic declination: `desiredAccuracy =
  kCLLocationAccuracyReduced`. No coordinate is stored, logged or sent. The tests must check that
  no `CLLocation` value reaches any file (§10).
- Denied or restricted: the reading continues with the magnetic heading, so its source is
  `magnetic` and its state is at best approximate. The footer adds the Settings sentence (§3.3).
- Heading and CoreMotion attitude need no permission. `NSMotionUsageDescription` is not needed,
  because device-motion attitude is not motion activity.

### 4.2 Step 2 check reading (`CompassReader`, CaptureRoomPlan, Apple only)
1. `CLLocationManager`: `headingFilter = kCLHeadingFilterNone`, `headingOrientation = .portrait`,
   `startUpdatingHeading()`. When authorized, also `startUpdatingLocation()`, because `trueHeading`
   is only valid while location updates run.
2. A sample is valid when `headingAccuracy >= 0`. Its heading is `trueHeading` when `>= 0` (source
   true), else `magneticHeading` (source magnetic). Wait up to 5 s for a valid `trueHeading` before
   using magnetic.
3. Windows of 2.0 s of valid samples. A window is **steady** when its circular spread (the largest
   angular distance from the circular mean) is ≤ 20°. The first steady window gives the reading:
   - heading = circular mean;
   - accuracy = ⌈max(`headingAccuracy`) in the window⌉;
   - source = true only if every sample in the window was true;
   - recordedAt = the time of the window's last sample.
4. Give up after 8 s: "No compass reading" when there was no valid sample, "Reading rejected" when
   there were only unsteady windows.
5. Stop heading and location updates when the reading completes, when step 2 disappears, or when
   the app goes to the background. **Read again** starts again from step 1 of this list.
6. While reading, the glyph rotates live by −(the latest heading).
7. `locationManagerShouldDisplayHeadingCalibration` returns false, so the system calibration
   overlay never covers the screen.

### 4.3 The recorded reading, at scan start (`LiveCaptureSession`)
Area `compass` defines the heading as "degrees from true north of the scan's −Z axis at scan start
(0–360)". The step 2 reading cannot give this, because the AR world frame does not exist until the
session starts and the phone is then held upright. It is measured inside the scan:

1. At `start()`, start heading updates (as in 4.2, for accuracy and declination) and
   `CMMotionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)` at 30 Hz. Keep the
   last 1 s of motion samples in a ring buffer. If that reference frame is not in
   `availableAttitudeReferenceFrames()`, there is no reading (state 3, "No compass reading").
2. On every 4 Hz tick that already exists (`tick()`), when `frame.camera.trackingState ==
   .normal`:
   - Camera forward in the AR world: `f = −(frame.camera.transform.columns.2.xyz)`. Use the sample
     only when |f.y| ≤ 0.766 (the camera is within 50° of level).
   - **AR yaw** ψ_ar = atan2(f.x, −f.z) in degrees, clockwise from world −Z seen from above.
   - Take the motion sample nearest to `frame.timestamp`. Both use the system uptime clock; require
     |Δt| ≤ 20 ms. Let `R_dr` be the rotation from the device frame to the reference frame.
     `CMAttitude.rotationMatrix` may be either direction; pin the convention with the device test
     T-C7 (§10) and transpose if needed. Then d = R_dr · (0, 0, −1), the back camera axis in the
     reference frame (X = magnetic north, Y = west, Z = up).
   - **Magnetic azimuth of the camera** ψ_m = atan2(−d.y, d.x), clockwise from magnetic north.
   - Declination δ = `trueHeading − magneticHeading` from the latest valid `CLHeading`, normalised
     to (−180, 180]. It exists only when `trueHeading >= 0`.
   - **Sample** h = ψ_m + (δ or 0) − ψ_ar, normalised to [0, 360). This is the heading of the
     world −Z axis and is the same at every instant of the session.
3. After 8 samples (2 s): heading = circular mean; spread = largest deviation from the mean;
   accuracy = ⌈max(max `headingAccuracy` over the samples, spread)⌉; source = true if δ existed for
   every sample; recordedAt = the last sample's time. Classify with `compass`'s classifier and emit
   `CaptureSessionEvent.compass(CompassReading)`.
4. **Improve during the scan** (§11, Q2). The −Z axis is fixed for the whole session, so a later
   window measures the same quantity. When the current reading is not verified, keep forming
   windows until Finish floor, and replace the reading when a window classifies better: verified
   beats approximate, which beats not verified. Stop sampling once verified.
5. For the live pill glyph only, the heading the camera faces = the latest sample's (ψ_m + δ).
6. At `finish()`, stop CoreMotion and CoreLocation. With no window at all, the reading is state 3
   with the reason "No compass reading".
7. Pause and Resume keep the same ARSession (`stop(pauseARSession: false)`), so the frame and the
   reading stay valid. **Restart this floor** and **Try again** create a new session, which takes
   a new reading.

### 4.4 Into the capture record
- `CaptureFlowModel` stores the latest `.compass` event of the running session. In
  `finishFloor()` it is copied into `record.captures[0]` through the internal (module-only)
  `CaptureRecordDraft`/record setter that `compass` defines. No public API takes a heading from the
  UI.
- A floor whose session never produced a reading gets no heading fields, which means state 3 (per
  north-arrow v2: "Missing field = state 3").
- The step 2 check reading is never written.

### 4.5 States and thresholds (owned by `compass`; repeated here for the UI)
- **Verified**: source true and accuracy ≤ 10°.
- **Approximate**: accuracy > 10° and ≤ 30°, or source magnetic with accuracy ≤ 30°.
- **Not verified**: no reading, accuracy > 30°, a rejected reading, or the feature is off.

The UI calls `CompassClassifier.classify(heading:accuracy:source:)` from the shared contract
package (`compass` decides where it lives; recommended: `contract/swift`, so PlanExport, the
station TS port and the phone agree).

### 4.6 Never typed
- No text field, stepper, picker or editable value for the heading exists anywhere in the app.
- `CompassReading` values are made only by `CompassReader`/`LiveCaptureSession` (and, in Debug UI
  tests, by `FixedHeadingSource`). The setter on the draft/record is `internal` to CaptureCore.
- The compiler enforces this: App and AppCore code cannot call the `internal` setter. Code review
  checks that no public or `package` setter is added. UI test U2 checks that the compass row has
  no text field.

### 4.7 Replay and UI tests
- `HeadingSource` protocol (CaptureCore). It is implemented by `CompassReader` (live) and by
  `FixedHeadingSource(heading: 212, accuracy: 8, source: .true)` (Debug, `UITestEnvironment`).
- `ReplaySession(source:…, compass: CompassReading?)` emits `.compass(reading)` right after
  `.stateChanged(.running)`.
- `UITestEnvironment` passes heading 212, accuracy 8, source true. Step 2 then shows **"North 212°
  true · ±8°"** and **"Verified · read [AGE]"**, and the live pill shows **"N · true · ±8°"**.

---

## 5. Data, state and persistence

### 5.1 Models (CaptureCore, Linux-testable unless marked)
```swift
// CaptureCore/HubProjects.swift (changed)
public struct HubProjectListing: Sendable, Equatable {
  public var projects: [HubProjectSummary]
  public var fetchedAt: Date?        // ProjectList.fetchedAt
  public var isOfflineCopy: Bool      // ProjectList.isStale
}
public protocol HubProjectProvider: Sendable { func listing() async throws -> HubProjectListing }
// HubProjectSummary gains: public var projectManagerPhone: String?   (nil until §7 lands)

// CaptureCore/CompassReading.swift (new; mirrors compass's contract fields)
public struct CompassReading: Sendable, Equatable {
  public enum Source: String, Sendable { case trueNorth = "true", magnetic }
  public var heading: Double?          // 0..<360
  public var accuracy: Double?         // degrees, rounded up
  public var source: Source?
  public var recordedAt: Date?
  public var state: CompassState       // verified | approximate | notVerified (from compass)
  public var reason: CompassNotVerifiedReason?   // noReading | accuracyTooLow | rejected | noCompass
}
public enum CompassPreview: Sendable, Equatable {   // step 2 row
  case reading, done(CompassReading), unavailable
}

// CaptureCore/CompassMath.swift (new, pure)
public enum CompassMath {
  public static func arYaw(cameraForward: SIMD3<Double>) -> Double?            // nil when |y| > 0.766
  public static func azimuth(deviceToReference: [[Double]]) -> Double?         // ψ_m of −Z_device
  public static func sceneHeading(azimuth: Double, declination: Double?, arYaw: Double) -> Double
  public static func circularMean(_ degrees: [Double]) -> Double
  public static func spread(_ degrees: [Double], around mean: Double) -> Double
  public static func normalized(_ degrees: Double) -> Double                   // [0, 360)
}

// CaptureCore/CaptureSession.swift (changed)
public enum CaptureSessionEvent { case stateChanged(…), progress(…), instruction(…),
                                  compass(CompassReading), tracking(TrackingStatus) }
public enum TrackingStatus: Sendable, Equatable { case normal, lost(since: Date) }

// CaptureCore/CaptureFlowModel.swift (changed: additions)
public private(set) var listing: HubProjectListing?
public private(set) var compassPreview: CompassPreview
public private(set) var scanCompass: CompassReading?
public private(set) var tracking: TrackingStatus
public var existingAreaKeys: Set<String>             // set by the host when adding a floor
public var continueBlocker: String?                   // nil = Continue enabled (§3.2 table)
public var startScanBlocker: String?                  // nil = Start scan enabled (§3.3 table)
public func readCompass() async                       // auto on appear + "Read again"
public func addressToggleChanged(isOn: Bool) -> Bool  // true → show the address-different alert
public func restartFloor() async                      // tracking lost: cancel and start again, same draft
public static func suggestedFloorName(existing: Set<String>) -> String  // "Floor N"
```

### 5.2 Persisting a capture in progress (AppCore, new)
- The **workspace folder is created at the first Start scan**, not when New capture is tapped.
  `VisitWorkspace.create` moves from `AppModel.startNewVisit()` into the first `startScan`. Until
  then the workspace id is only allocated in memory. A New capture that is abandoned leaves
  nothing on disk ("Nothing is saved").
- **`<workspace>/visit.json`** is app-private: it is not in the package and not in the contract.
  It is written atomically with `.completeFileProtectionUntilFirstUserAuthentication` after every
  `VisitFlow` change to `record`, `noRoomsSkipped` or `isSealed`:
  ```json
  { "formatVersion": 1,
    "createdAt": "2026-10-21T13:02:11Z",
    "updatedAt": "2026-10-21T14:40:03Z",
    "record": { /* CaptureRecord, CaptureContractJSON encoder */ },
    "noRoomsSkipped": { "confirmedCaptureIds": ["…"] },
    "isSealed": false }
  ```
  `NoRoomsSkippedConfirmation` gains `Codable` (FieldRules, additive). `phone-package` may add
  revision fields; additive only, with `formatVersion` staying 1.
- **Resume**: `VisitModel(resuming workspace:)` reads `visit.json`, loads `field-controls.json`
  (`FieldControlsFile`), opens the photo store, loads `room-names.json`, and maps each capture's
  model through `rooms.load`, which recomputes `ScanMeasurements`. The overview opens. A floor scan
  interrupted by the app being killed is lost, as in v1: originals are written at Finish floor.
- **Migration of v1 workspaces** (no `visit.json`): if the workspace has a draft capture record
  (`ScanLibrary.record(visit:)`), write `visit.json` from it with `noRoomsSkipped` unconfirmed and
  `isSealed` = (a package folder exists). Otherwise the workspace is not listed (its files stay on
  disk; nothing is deleted).

### 5.3 VisitFlow v2 (AppCore, changed)
The overview becomes the hub. The rules stay: one HUB project per visit, no package before the
checklist passes, no change after sealing (revisions belong to `phone-package`).

| Event | From | To | Change from v1 |
|---|---|---|---|
| `scanStarted()` | `.captureRecord` | `.scan` | also allowed from `.overview` (adding a floor) |
| `scanCancelled()` | `.scan` | `.captureRecord` | unchanged |
| `floorFinished(record)` | `.scan` | `.photos(captureId, nil)` | unchanged guards (same deal and address, no duplicate area key) |
| `photosDone()` | `.photos` | **`.overview`** | v1 went to `.controls` (or `.checklist` when opened from it); `photosFromChecklist` is removed |
| `openPhotos(captureId, room)` | `.overview`, `.checklist` | `.photos` | new (v1 `takePhoto` only from the checklist) |
| `openControls()` | `.overview`, `.checklist` | `.controls` | new name for `addControls` |
| `controlsDone()` | `.controls` | `.overview` | v1 went to `.checklist` |
| `openChecklist(focus:)` | `.overview` | `.checklist` | new |
| `backToOverview()` | `.photos`, `.controls`, `.checklist`, `.packageReady` | `.overview` | new |
| `confirmNoRoomsSkipped()` | `.checklist` | same | unchanged |
| `reviewPackage(canFinish:)` | `.overview`, `.checklist` | `.packageReady` | replaces `checklistFinished`; throws `checklistIncomplete` when `!canFinish` |
| `addFloor()` | `.overview`, `.packageReady` | `.captureRecord` (adding) | replaces `addMoreRooms`; throws `alreadySealed` after sealing |
| `sealed()` | `.packageReady` | `.uploading` | unchanged |

`VisitStep` gains `.overview`. The App's `NavigationStack` path is derived from `VisitFlow.step`:
`.overview` gives `[overview]`; `.photos`, `.controls`, `.checklist` and `.packageReady` give
`[overview, step]`; `.captureRecord` gives `[newCapture, scanSetup]` for a visit without captures
and `[overview, scanSetup]` when adding a floor; `.scan` presents the cover. `allowsSignOut` is
removed, because sign-out now happens from the home.

### 5.4 Captures home data (AppCore `CaptureLibrary`, new)
`CaptureLibrary.load(visitsRoot:uploads:statusStore:) -> CapturesHomeState` is pure and reads the
disk. For each workspace:
- `visit.json` gives the record, the floor count and the project title;
- `packages/*/` gives the sealed packages (`SealedPackage.open`, `manifest.revision`, `sealedAt`);
- `<packageId>.upload-state.json` gives the upload phase (an existing file);
- **`<packageId>.station-status.json`** (new, app-private) gives the station stage and verdict:
  `{ "formatVersion": 1, "stage": "verdict_ready", "outcome": "limited", "fetchedAt": "…" }`.
  `UploadCoordinator` writes it whenever it learns a stage or verdict, and the home's refresh does
  too. `phone-package` may add fields such as `checkedAt` and `summary`.

The rows for the live uploads (bytes, activity) come from `AppModel.uploads` snapshots when a
coordinator is running, and from the upload state file otherwise. `CapturesHomeState` (CaptureCore)
is plain data: sections, rows (id, title, subtitle, progress?, status?) and footnote, so the
screen is snapshot-testable with fixtures.

### 5.5 Tracking status (CaptureRoomPlan `LiveCaptureSession`)
- In `tick()`, read `frame.camera.trackingState`. Keep `notNormalSince`. Emit `.tracking(.lost(since:))`
  using the thresholds in §3.4.1, and `.tracking(.normal)` after 0.5 s of normal tracking.
- While tracking is not normal, **skip `sample(frame)`**, so no depth, pose or mesh is taken from a
  drifting frame. This is a behaviour change and makes "Recording paused" true.
- `ReplaySession` gains an optional script `trackingLost: ClosedRange<Int>?` (steps during which
  it emits lost), for model and UI tests.

### 5.6 Text formatting helpers (CaptureCore `CaptureText`, pure, en_US_POSIX)
| Helper | Output |
|---|---|
| `relativeAge(from:now:)` | "just now" (< 60 s), "N min ago", "N h ago" (< 24 h), "on MMM d" |
| `readAge(from:now:)` | "N s ago", "N min ago", "at HH:mm" |
| `sealedDate` | "Jan 25, 2025" |
| `offlineStamp` | "Oct 20, 14:12" |
| `capturedWhen(visitedAt:now:)` | "today", "yesterday", "Oct 20", "Oct 20, 2025" |
| `plural(_ n:, _ one:, _ many:)` | "1 floor" / "2 floors" |
| `degrees(_:)` | integer, 360 → 0 |

These replace `RelativeDateTimeFormatter`, which prints "2 min. ago" and not the design's
"2 min ago".

### 5.7 Device marketing name (CaptureCore `DeviceNames`, new)
A table from identifier to name for LiDAR phones and tablets, used for the Device row and for
`record.device.marketingName` (already an optional schema field, today always nil):
iPhone13,3 "iPhone 12 Pro", iPhone13,4 "iPhone 12 Pro Max", iPhone14,2 "iPhone 13 Pro",
iPhone14,3 "iPhone 13 Pro Max", iPhone15,2 "iPhone 14 Pro", iPhone15,3 "iPhone 14 Pro Max",
iPhone16,1 "iPhone 15 Pro", iPhone16,2 "iPhone 15 Pro Max", iPhone17,1 "iPhone 16 Pro",
iPhone17,2 "iPhone 16 Pro Max", iPhone18,1 "iPhone 17 Pro", iPhone18,2 "iPhone 17 Pro Max".
**Check the identifiers for iPhone18,x against Apple's list before merging.** An unknown
identifier gives nil and the screen shows the identifier. Add the iPad Pro LiDAR models in the
same way.

---

## 6. Mapping to the current code

### 6.1 New
| Path | What |
|---|---|
| `ios/Packages/ChapterUI/Package.swift`, `.apple-only` | New SwiftUI package with no dependencies. Every source is wrapped in `#if canImport(SwiftUI) && os(iOS)` so dependants still build on Linux. Product `ChapterUI`; resources `Fonts`. |
| `ChapterUI/Sources/ChapterUI/ChapterTheme.swift` | §2.1–2.3 |
| `ChapterUI/Sources/ChapterUI/ChapterFonts.swift`, `Fonts/Inter-Regular.ttf`, `Fonts/Inter-SemiBold.ttf` | §2.6 |
| `ChapterUI/Sources/ChapterUI/ChapterLogo.swift`, `ChapterLogoData.swift` (generated) | §2.4.8 |
| `ChapterUI/Sources/ChapterUI/Components/*.swift` | ChapterSection, rows, ChapterButtonStyle, ChapterSegmented, Banner, StatusLabel/StatusGlyph, CompassGlyph/CompassPillGlyph, AvatarButton, ChapterAppearance |
| `ChapterUI/Tests/ChapterUITests/*` | fonts, logo, component snapshots, snapshot helper |
| `ChapterUI/THIRD_PARTY_NOTICES.md` | Inter OFL 1.1 |
| `CaptureCore/Sources/CaptureCore/CompassReading.swift`, `CompassMath.swift`, `HeadingSource.swift`, `CaptureText.swift`, `DeviceNames.swift`, `CapturesHomeState.swift`, `CaptureOverviewState.swift` | §4, §5 |
| `CaptureCore/Sources/CaptureRoomPlan/CompassReader.swift` | CoreLocation + CoreMotion reader (§4.2, §4.3) |
| `CaptureCore/Sources/CaptureUI/CapturesHomeScreen.swift`, `CaptureOverviewScreen.swift`, `CompassRow.swift`, `ScanCards.swift` (tracking lost / stopped) | the screens take state and actions; they hold no disk access |
| `CaptureCore/Tests/CaptureCoreTests/CompassMathTests.swift`, `CompassReadingTests.swift`, `CaptureTextTests.swift`, `DeviceNamesTests.swift`, `CapturesHomeStateTests.swift`, `CaptureOverviewStateTests.swift` | Linux-run unit tests |
| `CaptureCore/Tests/CaptureUITests/` (+ `__Snapshots__/`) | iOS simulator snapshot tests (§10.2). Sources guarded with `#if canImport(UIKit)`. |
| `ios/App/AppCore/Sources/AppCore/CaptureLibrary.swift`, `VisitStore.swift` (visit.json), `StationStatusStore.swift`, `OverviewBuilder.swift` | §5.2–5.4, §3.5.1 rules |
| `ios/App/AppCore/Tests/AppCoreTests/CaptureLibraryTests.swift`, `VisitStoreTests.swift`, `OverviewBuilderTests.swift` | unit tests |
| `ios/App/Sources/App/HomeModel.swift`, `Views/AppNavigation.swift` | the root NavigationStack, routes and wiring |
| `ios/App/UITests/CaptureV2UITests.swift` | §10.3 |

### 6.2 Changed
| Path | Change |
|---|---|
| `ios/Packages/CaptureCore/Package.swift` | Add `.package(path: "../ChapterUI")`. CaptureUI depends on `ChapterUI`. New test target `CaptureUITests` (depends on CaptureUI, CaptureCore, ChapterUI). |
| `CaptureUI/Tokens.swift` | `ChapterTokens` becomes a façade over `ChapterTheme`. Values change: `primaryHeight` 52, `segmentHeight` 44, `sans()` is Inter, `display` is Times 34. |
| `CaptureUI/Components.swift` | Remove `Wordmark` (typed serif). `PrimaryButton` and `FieldLabel` forward to ChapterUI. Keep `WrapLayout` only if something still uses it (nothing in this area does). |
| `CaptureUI/NewCaptureScreen.swift` | Rewrite to §3.2. The project picker sheet is restyled. Alert and banner states. |
| `CaptureUI/ScanSetupScreen.swift` | Rewrite to §3.3. The "Name" row, the segmented control in the card, the removable rows, the compass row, and the button blockers. |
| `CaptureUI/LiveScanScreen.swift` | Rewrite to §3.4: pills, two-line coaching pill, compass pill, status line, tracking-lost / paused / stopped states, Restart confirmation. |
| `CaptureUI/CaptureFlowView.swift` | **Removed.** The app's NavigationStack hosts the screens (§3.0). `CaptureSessionPreview` stays. |
| `CaptureCore/CaptureFlowModel.swift` | Additions in §5.1. `startScan` creates the workspace through an injected `prepareWorkspace` closure. `finishFloor` attaches the compass. `restartFloor`, the blockers, `existingAreaKeys` and the floor-name suggestion are new. Events `.compass` and `.tracking` are handled. |
| `CaptureCore/CaptureRecordDraft.swift` | Internal compass attach (with `compass`). New validation `duplicateAreaKey(existing:)`. |
| `CaptureCore/CaptureSession.swift` | New events `.compass` and `.tracking`, and `TrackingStatus`. `CaptureFlowModel.canFinishFloor` is false while `progress.counts.walls == 0`. |
| `CaptureCore/HubProjects.swift` | `HubProjectListing`; `listing()` replaces `projects()`. `StaticHubProjectProvider` is updated. |
| `CaptureCore/ReplaySession.swift` | `compass:` and `trackingLost:` options. |
| `CaptureCore/ScanGuidance.swift` | Unchanged logic. The UI no longer shows `step` (the "Step N of 4" line). |
| `CaptureRoomPlan/LiveCaptureSession.swift` | Heading and motion sampling (§4.3), the tracking monitor, and skipping sampling while not normal (§5.5). Injected `HeadingSource` / motion provider. |
| `CaptureRoomPlan/DeviceCapabilities+Current.swift` | `DeviceInfo.current()` fills `marketingName` from `DeviceNames`. |
| `ios/Packages/FieldKit/Package.swift` | FieldKitUI depends on `ChapterUI`. |
| `FieldKitUI/FieldTheme.swift` | Façade over `ChapterTheme` (Inter fonts, 52 pt primary, title in Times 34). `phone-field` restyles its screens on top of this. |
| `ios/App/Sources/App/ChapterCaptureApp.swift` | `ChapterFonts.register()` and `ChapterAppearance.apply()` in `init`. |
| `ios/App/Sources/App/AppModel.swift` | `Screen.visit(VisitModel)` becomes `Screen.home(HomeModel)`. `startNewVisit` no longer creates a workspace or shows the pending upload. Uploads still resume at launch (`PendingUploads.find`). New `openVisit(workspace:)` and `newCapture()`. |
| `ios/App/Sources/App/VisitModel.swift` | Init for a new visit (lazy workspace) and for resuming one (§5.2). `photosDone` returns to the overview. The checklist routes and `addFloor` follow §5.3. `visit.json` is saved through `VisitStore`. `canSignOut` and `AccountFooter` support are removed. Builds the `CaptureOverviewState` (through AppCore `OverviewBuilder`). |
| `ios/App/Sources/App/Views/RootView.swift` | `.home` route; sign-in screen logo and type (§3.6). |
| `ios/App/Sources/App/Views/VisitView.swift` | Replaced by `AppNavigation.swift` (routes per §3.0). `AccountFooter` is removed. |
| `ios/App/Sources/App/Views/ScanViewer.swift` | `MyScansView` is removed. `ScanViewer` can be pushed (inline title, no Done). `ScanLibrary` stays (used by the migration). |
| `ios/App/Sources/App/Debug/UITestEnvironment.swift` | `FixedHeadingSource(212, 8, true)`; a ReplaySession with compass; launch arguments `-ChapterUITestOffline` (the stub station answers `/projects` as offline after seeding the cache) and `-ChapterUITestVisitsRoot <name>` (a stable root, for the relaunch test). |
| `ios/App/Sources/App/Debug/FieldTestEnvironment.swift` | Live `CompassReader`. |
| `ios/App/AppCore/Sources/AppCore/VisitFlow.swift` | §5.3. |
| `ios/App/AppCore/Sources/AppCore/VisitWorkspace.swift` | `visitURL` (`visit.json`), `stationStatusURL(packageId:)`. The doc comment lists the new files. |
| `ios/App/AppCore/Sources/AppCore/StationQueries.swift` | `StationProjectProvider.listing()` returns `HubProjectListing` (from `ProjectList`). |
| `ios/App/AppCore/Sources/AppCore/UploadCoordinator.swift` | Writes `station-status.json` when the stage or verdict changes. |
| `ios/App/AppCore/Tests/AppCoreTests/VisitFlowTests.swift` | Rewritten for the v2 transitions (§10.1). |
| `ios/Packages/FieldKit/Sources/FieldRules/NoRoomsSkippedConfirmation.swift` | `Codable` (additive). |
| `ios/App/Resources/Info.plist` | `NSLocationWhenInUseUsageDescription` (§4.1). |
| `ios/project.yml` | Package `ChapterUI` and the App dependency on product `ChapterUI`. |
| `.github/workflows/ios.yml` | Matrix entry `ChapterUI` (`ios/Packages/ChapterUI`). |
| `tools/brand/generate_plan_brand.py` | iOS font and logo outputs (§2.6). |
| `ios/App/UITests/ReplayFlowUITests.swift` | Updated for the home, the new labels, and the overview between photos and controls (§10.3). |
| `ios/App/README.md`, `docs/waves/design/DESIGN.md` | Document v2. The DESIGN.md brand update says "The iOS app's own screens keep SF"; replace that with "Inter replaces SF on the phone; Times for display titles (owner decision, Oct 21, 2026)". |

### 6.3 Removed
- The typed serif wordmark in CaptureUI and in the sign-in screen.
- `CaptureFlowView` (the step switcher).
- `AccountFooter` and `MyScansView` (the home replaces them).
- The v1 "‹ Back" text button, the "Floor or area" and "Mode" field labels, the "+ Add room"
  dashed chip, the "Primary closet · locked ✕" chips, the "LiDAR ✓" device text, and the "Step N of
  4" guidance line.
- `VisitFlow.photosFromChecklist`, and the linear photos → controls → checklist transitions.
- Disabled primary buttons drawn at opacity 0.4 (v2 uses the line fill and `#4E493F` text).

---

## 7. Contract and schema changes

| Change | Owner | Detail |
|---|---|---|
| Capture-record compass fields per capture (`heading`, `headingAccuracy`, `headingSource`, `headingRecordedAt`, plus anything `compass` adds, e.g. a not-verified reason) and the schema version | **`compass`** | This area only produces values through §4.3 and reads them for the overview. **No change to `contract/` is made by this area.** |
| `record.device.marketingName` | this area | Already in the schema (optional). It is now filled. No schema change. |
| `visit.json`, `<packageId>.station-status.json` | this area (status: shared with `phone-package`) | App-private files in the visit workspace. Not in the package and not in `contract/`. `formatVersion: 1`. |
| `HubProject.projectManager { name, phone }` (optional) in `contract/openapi/station.yaml` `GET /projects`, and the station and HUB source | station (not this area) | Only needed for a real "Call the PM" (§3.2.2, §11, Q9). Optional and additive. Without it the app still works. |
| `HubProjectProvider` API | this area | Internal Swift API (CaptureCore ↔ AppCore), not contract. |

---

## 8. Dependencies on other areas

| Area | Relation |
|---|---|
| **`compass`** (blocking for §4.4/§4.5) | Owns the capture-record fields, the schema version bump, the state classifier, the thresholds (±10° / ±30°) and the reason words. It must also confirm how the scan frame relates to the plan frame: the drawing is never rotated, but `FloorPlanSquaring` and the mapper may rotate the plan relative to RoomPlan's world. Any such rotation must be added to the arrow by `compass` / the plan areas (§9, R3). Until `compass` lands, the UI runs with the local `CompassReading` and writes nothing into the record. |
| `phone-field` (uses this area) | Consumes ChapterUI and the FieldTheme façade. Its screens are the targets of the overview rows (Photos, Field controls, Before you leave focus on compass / skipped rooms). "Done with photos" returns to the overview. Its photo "Looking toward · from the compass" needs a live heading: use `HeadingSource`/`CompassReader` from this area (the heading the camera faces, §4.3 step 5, or CLHeading when flat). Its "Read" on the checklist compass item cannot read an already-scanned floor (§9, R2). |
| `phone-package` (uses this area) | Consumes ChapterUI. Package ready, Uploading, Verdict received and revision 2 are reached from the overview and the home. May add fields to `visit.json` and `station-status.json`. The overview's bottom-button rows 3–4 hand off to it. |
| Brand tooling (shared) | `tools/brand/generate_plan_brand.py` gets the iOS outputs. The plan and PDF outputs stay unchanged. |
| Not touched | PlanExport (ChapterBrand, PDF Inter embedding, FloorplanWriter), room renaming (`room-names.json`, `RoomNamesSheet`), and `tools/scan-browser`. This area builds on them; room names flow into the overview through `VisitRooms`. |

---

## 9. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **The CMAttitude matrix convention** (reference→device or device→reference) flips the computed heading. | Pure math tests with synthetic matrices, and the on-device test T-C7: compare with a known building edge or a calibrated compass, ±5°. |
| R2 | **A post-scan "Read"** (checklist item in `phone-field`) cannot be tied to a finished floor: its AR frame no longer exists. | Readings are only taken during a floor's session (§4.3) and improve until Finish floor. `phone-field` must make "Read" mean "scan this floor again" or remove it. Flagged as §11, Q2. |
| R3 | The plan export rotates the drawing relative to the RoomPlan world (`FloorPlanSquaring`, the mapper), so the arrow would be wrong. | `compass` and the plan areas own this; this area records the frame defined in the bundle. |
| R4 | Steel and appliances disturb the magnetometer; readings indoors are often approximate. | Accuracy is honest, the step 2 check, the footer advice, and improvement during the scan. |
| R5 | Inter is wider than SF, so long strings may wrap or truncate (titles, buttons, the offline banner). | AX3 and "large title truncation" snapshots (§10.2). Primary labels are kept under 34 characters. |
| R6 | The system large title in Times on iOS 17–26: appearance proxies behave differently on iOS 26 (Liquid Glass). | Snapshot both a large and a collapsed title on the CI simulator. Fallback: a custom header row. |
| R7 | **Persisting `visit.json` is new**: a write that fails or is torn could lose a visit's state. | Atomic writes. The originals, photos and controls are still separate files. The migration path (§5.2) rebuilds from drafts. |
| R8 | Sampling is skipped while tracking is lost, which lowers the depth sample count of bad scans. | This is intended; the station checks density. Documented in the README. |
| R9 | Snapshot flakiness (fonts not registered, the simulator version). | Register fonts in setUp. Pin the CI simulator (iPhone 17 Pro, Xcode 26.3). Use a tolerance (§10.2). Record with `RECORD_SNAPSHOTS=1`. |
| R10 | A different operator signing in on the same phone sees and continues other people's in-progress captures, so `record.operator` stays the first operator's. | Accepted for v2. The overview subtitle names the capture's operator. |
| R11 | ImageRenderer cannot draw UIKit-backed views (TextField, Toggle, ScrollView). | Snapshots are taken from a UIWindow hosting the view (`drawHierarchy`), not with ImageRenderer. |

---

## 10. Test plan and acceptance criteria

### 10.1 Unit tests (Linux unless marked)
| ID | Test | Accepts when |
|---|---|---|
| T-C1 | `CompassMathTests.testArYawFromCameraForward` | forward (0,0,−1) → 0°; (1,0,0) → 90°; (0,0,1) → 180°; (−1,0,0) → 270°; \|y\| > 0.766 → nil |
| T-C2 | `testAzimuthFromAttitude` | a synthetic device→reference matrix for an upright phone facing magnetic east → 90° ± 0.01 |
| T-C3 | `testSceneHeadingIsInvariantToTurning` | the camera at magnetic 120° with AR yaw 30° → the world −Z axis at 90°. Turning the camera by +45° on both keeps 90°. Declination +13° gives 103°. |
| T-C4 | `testCircularMeanAcrossNorth` | mean of [355, 5, 1] = 0.33 ± 0.01; spread = 5.33 |
| T-C5 | `CompassReadingTests.testClassification` (with `compass`'s classifier) | (true, 8) verified; (true, 10) verified; (true, 10.5) approximate; (true, 30) approximate; (true, 31) not verified; (magnetic, 8) approximate; (magnetic, 31) not verified; nil → not verified |
| T-C6 | `testWindowing` (a scripted `HeadingSource`) | the first steady 2 s window gives the reading; accuracy = ⌈max⌉; unsteady for 8 s → "Reading rejected"; no samples → "No compass reading"; true for 5 s missing → magnetic |
| T-C7 | **On device** (manual, recorded in the PR): `CompassFieldCheck` | Standing at a known façade (azimuth from a survey or a map), the start-of-scan heading of world −Z agrees within ±5° on 3 runs. Upright and tilted 30° give the same value ±3°. |
| T-F1 | `CaptureFlowModelTests.testContinueBlockers` | the labels in the §3.2 table, in priority order |
| T-F2 | `testStartScanBlockers` | §3.3 table, including a duplicate area key with `existingAreaKeys = ["floor-1"]` and name "Floor 1" → "Floor 1 is already captured. Use another name" |
| T-F3 | `testSuggestedFloorName` | {} → "Floor 1"; {floor-1} → "Floor 2"; {floor-1, floor-2, floor-3} → "Floor 4"; {floor-2} → "Floor 3" (N = captures + 1 = 2, already used, so raised to 3) |
| T-F4 | `testAddressToggleOffAsksForAlert` | on→off returns true and clears `addressConfirmedAt`; off→on returns false and sets the time |
| T-F5 | `testCompassReadingAttachedAtFinish` | ReplaySession with compass(212, 8, true) → `result.record.captures[0]` carries the heading fields. With no compass event → no fields. |
| T-F6 | `testStep2ReadingIsNotRecorded` | a preview reading of 100° and a session reading of 212° → the record says 212 |
| T-F7 | `testTrackingLostEventsAndRestart` | the ReplaySession script makes `tracking` `.lost`, then `.normal`. `restartFloor()` cancels, starts a new session and resets the counts. |
| T-F8 | `testOfflineListing` | `HubProjectListing.isOfflineCopy` → the model exposes the count (12) and the stamp "Oct 20, 14:12" |
| T-T1 | `CaptureTextTests` | every output in §5.6, including "2 min ago" (not "2 min.") and 360 → "0" |
| T-T2 | `DeviceNamesTests` | the table and the fallback |
| T-H1 | `CapturesHomeStateTests` | fixtures produce the rows in §3.1.1 / §3.1.2 with exact subtitles, sorting and the footnote placement. Empty state. |
| T-O1 | `OverviewBuilderTests` (AppCore) | the 618 Valley Street fixture gives the floor rows "Whole floor · 12 rooms · 42 photos · controls complete" ● Done and "Whole floor · 9 rooms · no photos yet · controls missing" ■ Open; Photos "Bath 2 has no photo" ■ Missing; Field controls "Floor to floor and 1 landmark missing" ■ Missing (only those gaps); Compass "Floor 1 verified · Floor 2 not read" ▲ Partly; Rooms "Primary closet · locked" ● Recorded; button "Fix 2 items to review the package" disabled. Every compass word and the controls join cases. |
| T-V1 | `VisitFlowTests` (rewritten) | the transitions in §5.3; checklist gate; no change after sealing; same deal for later floors; `photosDone` → `.overview`; `addFloor` after sealing throws `alreadySealed` |
| T-S1 | `VisitStoreTests` | round trip of `visit.json`; atomic write; the migration from a v1 workspace with a draft record; an abandoned New capture leaves no folder |
| T-L1 | `CaptureLibraryTests` | workspaces with: not sealed; sealed uploading; paused; failed; confirmed without a verdict; a verdict of each outcome; revision 2 in progress. Each row's section, title, subtitle and status. |
| T-P1 | `LocationNotStoredTests` | after a full replay visit with a compass, no file under the workspace contains "latitude"/"longitude" or a coordinate pattern |

### 10.2 Snapshot tests (iOS simulator; `CaptureUITests` and `ChapterUITests`)
- Rendering: host the view in a `UIWindow` of 402 × 874 pt at scale 3 (the iPhone 17 Pro CI
  simulator), light appearance, `ChapterFonts.register()` in setUp. Capture with
  `drawHierarchy(in:afterScreenUpdates: true)`. Compare with the committed PNGs in
  `__Snapshots__/` at a tolerance of ≤ 0.5 % of pixels differing by > 2/255 per channel. Record
  with `RECORD_SNAPSHOTS=1`.
- Snapshots (fixtures with the bundle's sample values):
  1. Captures home: the drawn state (618 Valley Street uploading 67 %, three Sealed rows Limited / Ready / Blocked); the empty state; AX3 text size.
  2. New capture: the drawn state; offline (1b); address different with the alert (1c); no project chosen; device gate failure; offline with no saved list.
  3. What are you scanning?: the drawn state (verified 212° ±8°, Primary closet · Locked, the coverage note); reading; approximate magnetic; not verified; keyboard up (the button visible above it); AX3.
  4. Live scan: normal (11 / 4 / 6 / 3, 06:42); tracking lost (Paused · 00:06, 06:48); paused by the operator; scan stopped (too hot); compass not verified pill.
  5. Capture overview: the drawn state; all passing ("Review the package"); one floor; sealed uploading ("Upload status").
  6. ChapterUI components: every button state, segmented, status glyphs, compass glyph in its 3 states, logo at 26 pt and 40 pt.
- **Visual acceptance against the design** (a manual review checklist in the PR, with the
  snapshots next to the artboard screenshots at the same 402 × 874 size): every measurement in §2
  and §3 (row heights, paddings, radii, colours sampled from the PNG) matches. The only accepted
  differences are those this spec mandates: Inter instead of SF, Times large titles, the real logo,
  the system toggle off-track, and the second coaching line.

### 10.3 UI tests (XCUITest, Debug replay mode)
| ID | Flow | Accepts when |
|---|---|---|
| U1 | `ReplayFlowUITests` (updated). Launch → "Captures" (empty state) → **New capture** → choose "UI test visit" → toggle `capture.addressConfirmed` → **Continue** → step 2: `capture.floorName` already "Floor 1", tap "Whole floor" → **Start scan** → **Finish floor** → photos (phone-field) → Done → **Overview** → Field controls (phone-field) → back → Before you leave (phone-field) … → **Review the package** → Package ready → … → "Checks queued" | Every existing assertion on photos, renames, the Floorplan and the upload still passes. The order is updated for photos → overview. |
| U2 | Compass texts | step 2 shows "North 212° true · ±8°" and a label starting "Verified · read"; the live pill "N · true · ±8°"; no text field exists inside `compass.row`. |
| U3 | Address different | toggle on, then off → alert "Address is different on site?" with the two buttons; "Go back" stays on New capture; the button label is "Confirm the address to continue" and disabled. |
| U4 | Offline (`-ChapterUITestOffline`) | the banner text begins "No connection. Showing the 1 project saved on this phone (updated "; the row subtitle ends "· saved on this phone"; the button is "Continue offline". |
| U5 | Tracking lost (replay script) | `scan.trackingLost` appears with "Tracking lost"; Pause is disabled; then it disappears; "Restart this floor instead" → the confirmation → Restart gives counts reset to 0. |
| U6 | Overview statuses | after a first floor without photos, the overview shows "Photos" with "Missing" and the button "Fix 3 items to review the package" (photos, controls, skipped rooms in the box-room fixture) disabled. |
| U7 | Resume after relaunch (`-ChapterUITestVisitsRoot stable`) | finish a floor, terminate and relaunch → "In progress" row "UI test visit" / "1 floor · not sealed yet" → tap → the overview with Floor 1. |
| U8 | Duplicate name | "Scan another floor or room" → name "Floor 1" → button "Floor 1 is already captured. Use another name", disabled; default suggestion "Floor 2". |
| U9 | Sign-out from the home | avatar → "Signed in as UI Test Operator" dialog → the `account.signOut` button exists. Not tapped in replay mode, as in v1. |
| U10 | Accessibility audit | `XCUIApplication().performAccessibilityAudit()` on home, step 1, step 2 and overview passes (contrast, hit regions ≥ 44, labels). Known system-toggle exceptions are listed. |

### 10.4 Definition of done
- All the tests above are green on CI (Linux `scripts/swift-test.sh`, macOS `ios.yml` including
  the new `ChapterUI` job and `App`).
- No SF text remains on the phone's own screens: a debug check walks the hierarchy in a UI test
  and asserts that every `UILabel`/`Text` font family is Inter, Times New Roman or the system
  monospaced font.
- No typed wordmark remains: grep `"RENOVATION"` in `ios/` shows only generated logo data and
  accessibility labels.
- A field test on a device: a two-floor capture, the app killed between floors, the capture
  resumed from the home, both floors' compass states correct in `capture-record.json`, and the
  package seals.

---

## 11. Open questions (only where the bundle and the owner decisions leave a gap)

| # | Question | Recommended default |
|---|---|---|
| Q1 | Captures home: the In progress subtitles for not sealed, paused, failed, sign-in and checks running are not drawn. | Use the texts in §3.1.1. Keep "In progress" until a verdict exists; Sealed rows always carry a verdict. |
| Q2 | Compass: improve the reading during the scan, and what the checklist "Read" does for an already-scanned floor. | Improve during the scan until verified (§4.3 step 4); `headingRecordedAt` = the time of the window used. "Read" for a scanned floor cannot work; `phone-field`/`compass` should change it to "Scan again" or drop it. |
| Q3 | The coaching pill: one line as drawn, or keep the field-tested detail line. | Two lines: the title as drawn, plus `ScanGuidance.detail` in 13 pt. Drop "Step N of 4". |
| Q4 | Tracking lost: Finish floor dimmed but enabled? A confirmation for "Restart this floor instead"? | Finish stays enabled at opacity 0.5, as drawn. Restart asks for confirmation (§3.4.1), because it discards scanned walls. |
| Q5 | Step 2 name: prefilled or empty? | Prefill the next free "Floor N", fully editable. Mode is not preselected. |
| Q6 | The trailing caption of step 2 when adding a floor from the overview. | The project title, e.g. "618 Valley Street", not "Step 2 of 3". |
| Q7 | The floor-row controls wording when some controls exist. | "controls incomplete". |
| Q8 | The overview button after sealing. | "Upload status" while uploading or checking, and "Review revision [R+1]" after changes; `phone-package` owns the targets. |
| Q9 | "Call the PM": no PM phone in the HUB project data. | Add an optional `projectManager.phone` to the station's `/projects`. Until then the button discards the draft and returns to the home, without dialling. |
| Q10 | The large title weight in Times (the bundle draws SF Bold 34). | Times New Roman Regular 34/41, tracking 0, as every Times heading in the bundle and in v1. |
| Q11 | The bundle's offline variant (1b) omits the App row. | Keep the App row in every state. |
| Q12 | Finish floor with nothing captured: in v1 it ends the session with "Nothing was captured" and offers Try again. | Disable Finish floor while the live wall count is 0, so the case cannot happen; keep the v1 handling as a fallback. |
| Q13 | iPad and Dynamic Type (the bundle's open question 3). | iPhone layout on iPad, with content limited to 600 pt wide and centred. Dynamic Type is on, with stacked rows at accessibility sizes. Dark Mode is not built (the app stays light; the live scan is dark by design). |

---

## Appendix A. Every string on these screens (for tests and copy review)

Captures home: "Captures" · "In progress" · "Sealed" · "[N] floors · uploading · [x of y MB]" ·
"[N] floors · upload paused · [x of y MB]" · "[N] floors · not sealed yet" · "[N] floors · sign in
to upload" · "[N] floors · upload failed" · "Failed" · "[N] floors · uploaded · checks running" ·
"Checking" · "[N] floors · revision [R] not sealed yet" · "Revision [R] · sealed [MMM d, yyyy]" ·
"Revision [R] · re-seal needed" · "Limited" · "Ready" · "Blocked" · "Files stay on this phone until
the station confirms each one. Verdict details are in the HUB." · "No captures on this phone yet." ·
"Tap New capture to scan a floor or room." · "New capture" · "Signed in as [OPERATOR]" · "Sign out"
· "Cancel" · "Uploads resume after you sign in again."

New capture: "Step 1 of 3" · "New capture" · "HUB project" · "Deal [DEAL ID] · from the HUB,
updated [AGE]" · "Deal [DEAL ID] · saved on this phone" · "Change" · "Choose a HUB project" ·
"Projects come from the HUB" · "Choose" · "Loading projects from the HUB…" · "Address in the HUB" ·
"Choose a HUB project first" · "I am at this address" · "If the address on site is different, stop
and call the PM. The station blocks packages with a different address." · "Recorded automatically"
· "Operator" · "Device" · "App" · "[name] · LiDAR" · "Continue" · "Continue offline" · "Confirm the
address to continue" · "Choose a HUB project to continue" · "This phone cannot scan" · "No
connection. Showing the [N] projects saved on this phone (updated [MMM d, HH:mm]). You can scan
offline; the upload waits for a connection." · "A project not in this list cannot be started
offline: the deal id must come from the HUB." · "No connection and no projects saved on this phone.
Connect once to load the HUB projects." · "Connect to load projects" · "Could not load HUB projects:
[message]" · "Try again" · "Address is different on site?" · "Do not scan under this project. Call
the PM to fix the HUB record, then start the capture again. Nothing is saved." · "Go back" · "Call
the PM" · Sheet: "HUB project" · "Cancel" · "No HUB projects."

What are you scanning?: "Step 2 of 3" · "What are you scanning?" · "Name" · "Floor [N]" · "One
room" · "Whole floor" · "Exterior" · "Rooms you will not scan" · "Add a room you cannot scan" ·
"Remove [name]" · "A room you will not scan, for example a locked closet." · "Room name" · "Reason
(for example locked)" · "Add" · "Coverage notes" · "Optional" · "Compass" · "Reading the compass…" ·
"Hold the phone flat" · "North [HDG]° true · ±[ACC]°" · "North [HDG]° magnetic · ±[ACC]°" ·
"Verified · read [AGE]" · "Approximate · read [AGE]" · "Approximate · magnetic · read [AGE]" ·
"Compass not verified" · "Accuracy too low · read [AGE]" · "No compass reading" · "Reading rejected
· read [AGE]" · "No compass on this phone" · "Read again" · "Read automatically. Hold the phone
flat, away from steel and appliances. Approximate or missing readings are shown as such on the
plans." · "Location is off for Chapter Capture, so north is magnetic and shown as approximate. Turn
it on in Settings for true north." · "Start scan" · "Enter the floor or area" · "Use letters or
numbers in the name" · "[Name] is already captured. Use another name" · "Choose what you are
scanning"

Live scan: "[Name] · [Mode]" · "[mm:ss]" · ScanGuidance titles and details (unchanged, in
`ScanGuidance.swift`, e.g. "Move slowly along the walls") · "walls" · "doors" · "windows" · "rooms"
· "Compass · reading" · "N · true · ±[ACC]°" · "N · approx. · ±[ACC]°" · "N · magnetic · ±[ACC]°" ·
"Compass not verified" · "Recording LiDAR depth and mesh · saved on this phone" · "Recording the
room outline only · saved on this phone" · "Pause" · "Resume" · "Finish floor" · "Paused · [mm:ss]"
· "Tracking lost" · "Point the camera at a wall you already scanned and hold still. Scanning
continues on its own. Nothing is lost." · "Restart this floor instead" · "Recording paused · [W]
walls kept" · "Restart [Name]?" · "The [W] walls scanned so far are discarded. The compass is read
again." · "Restart" · "Scan stopped" · "Recording stopped" · "Back" · "Try again" · v1 error texts
from `CaptureSessionError.description` (unchanged, e.g. "Nothing was captured. Scan at least one
wall before finishing.")

Capture overview: "Deal [DEAL ID]" · "[project title]" · "Captured [WHEN] by [OPERATOR] · not
sealed yet" · "Floors and areas" · "[Mode] · [R] rooms · [P] photos · controls complete" · "… · no
photos yet · controls missing" · "… controls incomplete" · "Done" · "Open" · "Loading…" · "[Mode] ·
the scan could not be read" · "Scan another floor or room" · "Before you leave" · "Photos" · "[room]
has no photo" · "[room] and [n] more rooms have no photo" · "Every room has a photo" · "Missing" ·
"Field controls" · "[list] missing" · "Minimum set complete" · "Compass" · "Floor 1 verified · Floor
2 not read" · "Every floor verified" · "Verified" · "Approx." · "Partly" · "Not verified" · "Rooms
not scanned" · "[name] · [reason]" · "No rooms skipped" · "Record skipped rooms, or confirm none
were skipped" · "Recorded" · "Photos and controls cannot be recovered later." · "Fix [N] item(s) to
review the package" · "Review the package" · "Upload status" · "Review revision [R]" · "Back to
captures" (accessibility)

---

## Addendum (completeness critique, Oct 21, 2026) — binding, overrides the body above

Resolutions are numbered as in `00-critique.md`. Build split: this area is built by two tracks
(`00-tracks.md`): **T1 phone-foundation** (§2: ChapterUI, fonts, logo, appearance, brand tool,
`project.yml`, `ios.yml`, `ChapterCaptureApp.swift`) and **T7 phone-capture-core** (everything in
`ios/Packages/CaptureCore`), with the App/AppCore wiring in **T10 phone-app-shell**.

### A1. Compass parts are superseded by `compass` (R-20)
- §3.3.1 row texts, the pill table in §3.4, §4 (all of it), the compass types of §5.1
  (`CompassReading`, `CompassPreview`, `CompassMath`, the `HeadingSource` protocol), the
  compass rows of §6.1/§6.2 (`CompassReader`, `CompassMath.swift`, `HeadingSource.swift`) and the
  tests T-C1…T-C7, T-F5, T-F6 and the U2 strings are replaced by compass §1.3, §2, §3 and §5.1–5.2.
  Types come from the contract (`CompassState`, `NorthSymbol`, `HeadingSource`, `CompassMath`) and
  from compass's `CaptureCompass` target (`CompassService`, `CompassResult`, `CompassLiveState`,
  `CompassPrecheckState`, `FakeCompass`).
- Kept from this spec: the host layout (compass row min 56 pt, padding 8 × 16, glyph 32 pt, gap
  12; live pill height 32, padding 0 × 10, radius 16, icon 14 pt, gap 6), haptics, accessibility
  structure.
- Phone strings now (compass §5.1/§5.2): reading `Compass` / `Reading the compass…` (no glyph);
  verified `North {HDG}° true · ±{ACC}°` / ● `Verified · read {AGO}`; approximate `North {HDG}°
  {true|magnetic} · ±{ACC}°` / ▲ `Approximate · read {AGO}`; inaccurate same line 1 / ▲ `Not
  verified · accuracy too low · read {AGO}`; not calibrated `No compass reading` / ▲ `Not verified
  · move the phone in a figure 8, then read again`; unavailable `No compass on this phone` / ▲
  `Not verified · the plans will say so`. `{AGO}`: `just now` (< 5 s), `{n} s ago`, `{n} min ago`,
  `over an hour ago`. Chip: `N · reading…`, `N · true · ±{ACC}°`, `N · approx. · ±{ACC}°`,
  `N · magnetic · ±{ACC}°`, `N · not verified`.
- `Read again`: disabled (opacity 0.4) while reading, hidden when `unavailable`.
- Location-off note (compass §5.1) replaces §3.3's second footer: `Location is off for Chapter
  Capture, so north is magnetic and shown as approximate. Turn on Location in Settings to record
  true north.` plus the text button `Open Settings` (`compass.openSettings`).
- `NSLocationWhenInUseUsageDescription` = compass §3.1 text: `Chapter Capture uses your location
  only to turn the compass into true north on the plans. Your location is not saved.`
- `CompassGlyph` approximate ring: dash 1.6 / 1.6 (north-arrow v2 vector) at 32 pt.
- `CaptureFlowModel` API names follow compass: `compassPrecheck`, `liveCompass`,
  `readCompassAgain()`, `openLocationSettings()`; `finishFloor()` calls
  `record.captures[0].setCompass(result)`; `restartFloor()` (§3.4.1) discards the reading like
  `retryScan()`.

### A2. Overview Compass row (R-21)
Right side: all verified ● `Verified`; all usable and ≥ 1 approximate ▲ `Approx.`; some usable,
some not ▲ `Partly`; none usable ▲ `Not verified`. Subtitle per floor from FieldRules
`CompassSummary.short`: words `verified`, `approximate`, `not verified`, `not read` (e.g. `Floor 1
verified · Floor 2 not read`). Tap → Before you leave with `focus: .compass` (no Compass sheet).

### A3. Captures home (R-28) replaces §3.1.1–§3.1.2
Use the table in `00-critique.md` R-28 verbatim. `{count}` is phone-package's `CaptureCountText`.
Upload stopped stays **In progress** with ■ `Stopped` (not "Failed"). Rows are built by
`CaptureLibrary` (T10) from `visit.json`, `packages/*`, `<packageId>.upload-state.json` and
`<packageId>.station-status.json` (schema owned by phone-package, R-27). §5.4's station-status
schema is withdrawn. Title rule (R-29) unchanged.

### A4. VisitFlow (R-25) replaces the table in §5.3
Merged with phone-package: `.uploading` is `.packageStatus(packageId)`; `.revisionReady` added;
`reviewPackage(canFinish:)` goes to `.packageReady` or `.revisionReady`; `addFloor()` also from
`.revisionReady`; checklist gate also in revision mode. Overview button rows (§3.5):

| Condition | Label | Action |
|---|---|---|
| Not sealed (revision 1 or revision mode), N > 0 blocking items | `Fix [N] item to review the package` / `Fix [N] items to review the package` (disabled) | — |
| Revision 1, checklist passes | `Review the package` | Package ready |
| Revision mode (revision R ≥ 2), checklist passes | `Review revision [R]` | Revision n screen (phone-package §6) |
| Sealed, newest package without a verdict (uploading, paused, stopped, checking) | `Upload status` | Package status (phone-package §4), which shows "Upload stopped" when fatal |
| Sealed with a verdict | `Open the verdict` | Verdict received (phone-package §5) |

The last row is new (the bundle draws none; a sealed visit with a verdict otherwise has no exit
from the overview except back).

### A5. `visit.json` (R-26)
Adds, for revision mode only: `"revision": { "number": 2, "basePackageId": "<uuid>",
"startedAt": "<UTC>" }`. phone-package's `revision-draft.json` is not created. `isSealed` is
false while a revision draft is open.

### A6. Overview rows (R-37, R-38, G-2)
- `overview.controls` failing subtitle = **between-floor gaps only** (`Floor to floor`, `{k}
  landmark(s)`; join rule of §3.5.1); per-floor gaps are on the floor rows. Only per-floor gaps:
  `Missing on Floor 2` / `Missing on Floor 1 and Floor 2` / `Missing on Floor 1, Floor 2 and Floor
  3`. Status ■ `Missing` whenever `minimumControls` fails. T-O1 stays as written.
- Floor-row `controls [STATE]` comes from FieldRules `ControlsList.sections` for that floor:
  manual policy → `complete` (no ■ row), `missing` (A, B and ceiling all ■), else `incomplete`;
  standard policy (shipping default, owner question Q-A) → `controls from the scan` when every A,
  B and ceiling row has a tape or scan value, else `controls optional`.
- `overview.skippedRooms` passing subtitle when confirmed: `All rooms scanned` (not "No rooms
  skipped").
- Compass and Rooms-not-scanned rows push Before you leave with `focus` (phone-field addendum).

### A7. Ownership changes
- `NoRoomsSkippedConfirmation` `Codable`: done by phone-field (owner of FieldKit), not here.
- `FieldKit/Package.swift` and `FieldKitUI/FieldTheme.swift`: done by phone-field (this area does
  not edit FieldKit).
- `StationProjectProvider.listing()`: new AppCore file `StationProjectListing.swift` (T10);
  `StationQueries.swift` belongs to phone-package.
- `UploadCoordinator.swift` belongs to phone-package; it writes the status cache.
- `Info.plist`, `UITestEnvironment.swift`, `ReplayFlowUITests.swift`, `AppModel.swift`,
  `VisitModel.swift`, `RootView.swift`, `VisitView.swift` → T10 (one owner).
- `docs/waves/design/DESIGN.md`, `ios/App/README.md` → docs track T11.

### A8. ChapterUI scope (R-18, R-18b, R-18d)
ChapterUI also provides phone-field's `TextButton`, `ChoiceChip` (rooms padding 0 × 14, subjects
0 × 12, needs-photo dot), `SheetBar`, `SectionCaption` (12 and 13 pt), and phone-package's
`PlusGlyph`, `EqualsGlyph`, `MinusGlyph`, lock `InfoNote`, `ProgressBar(height: 4 | 8)`, 14 pt
status glyphs. Waiting glyph ○: circle (5, 5) r 4, stroke 1.2 `#6B6557`. Product
`ChapterUISnapshotTesting` (UIWindow + `drawHierarchy`, 402 × 874 @3x; fail when > 0.5 % of
pixels differ by > 8/255) is used by every phone snapshot test (this area's §10.2 threshold of
2/255 becomes 8/255).

### A9. Station and HUB data
`HubProject.projectManager?: {name, phone?}` is part of the merged OpenAPI 1.1.0 (T0, built by
T2). "Call the PM" dials only when `phone` exists (owner question Q-C).

### A10. UI-test hook (R-24)
`-ChapterUITestCompass verified|approximate|none` replaces `FixedHeadingSource`. U2 expects
`North 212° true · ±8°`, `Verified · read just now` and chip `N · true · ±8°`.

### A11. Missing states now specified
- Overview of a sealed visit: rows stay tappable; field screens open read-only (phone-field
  addendum G-1).
- Overview while the newest package is "Upload stopped": the bottom button `Upload status` leads
  to phone-package's Upload stopped state (Try again / Re-seal).
