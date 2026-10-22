# ChapterUI

The phone's screen tokens v2 and shared SwiftUI components (design v2, artboard 2k; build spec
phone-capture §2 with critique R-17, R-18, R-18b–d). CaptureUI, FieldKitUI and the app's package
screens build on it; `ChapterTokens` (CaptureUI) and `FieldTheme` (FieldKitUI) become façades over
`ChapterTheme`.

| Product                    | Contents                                                                                       |
| -------------------------- | ---------------------------------------------------------------------------------------------- |
| `ChapterUI`                | `ChapterTheme` (colour, type, metrics), `ChapterFonts`, `ChapterAppearance`, `ChapterLogo`, the components |
| `ChapterUISnapshotTesting` | the one snapshot harness of every phone snapshot test (`assertChapterSnapshot`, `ChapterSnapshotTestCase`) |

Every source is wrapped in `#if canImport(SwiftUI) && os(iOS)`, so both targets are empty modules
on Linux and macOS. There is no `.apple-only` marker at the package root, so
`scripts/swift-test.sh` builds the package on Linux (which checks those guards); the marker files
in the two source folders document that they need Apple frameworks. The macOS runner
(`.github/workflows/ios.yml`, job `ChapterUI`) builds it for iOS and runs the tests on the iPhone
17 Pro simulator with **iOS 26.0**, the runtime the snapshot references are recorded on, or a point
release of it (the runner image has 26.0.1; `scripts/snapshot-simulator.sh` picks it): the
package tests (scheme `ChapterUI-Package`) and the app-hosted snapshot tests (scheme
`ChapterUISnapshots` of the XcodeGen project, `HostedTests/` with the empty host app
`SnapshotHost/`; see Snapshot tests).

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # the pinned Xcode
DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0'
# or, from the repository root, the simulator CI uses (iOS 26.0 or 26.0.x, downloaded if missing):
# DESTINATION="$(scripts/snapshot-simulator.sh)"
cd ios/Packages/ChapterUI
xcodebuild test -scheme ChapterUI-Package -destination "$DESTINATION"
# The app-hosted snapshots (from the repository root):
xcodegen generate --spec ios/project.yml
xcodebuild test -project ios/ChapterCapture.xcodeproj -scheme ChapterUISnapshots \
  -destination "$DESTINATION"
# Record again (the run fails on purpose; look at every image), with either command:
TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test -scheme ChapterUI-Package -destination "$DESTINATION"
```

## Brand rules on the phone

- **The real logo, never typed text.** `ChapterLogo(height:)` draws the generated paths of the
  logo in brand black #231F20 (26 pt in the Captures home's bar, 40 pt on sign-in). One
  accessibility element, "Chapter Renovation".
- **Inter replaces SF; Times for display titles; mono stays mono.** Large titles are Times New
  Roman Regular 34/41 (shipped with iOS), everything else Inter Regular or SemiBold, the timer and
  ids SF Mono. Every style scales with Dynamic Type (`relativeTo:`) except the 7 pt "N" of the
  compass glyph.
- **Status is word and shape, never colour alone.** `StatusLabel(kind:word:)`; the ●▲■○ glyphs are
  drawn, not typed.

## Fonts

`Sources/ChapterUI/Fonts/Inter-Regular.ttf` and `Inter-SemiBold.ttf` (PostScript names
`Inter-Regular`, `Inter-SemiBold`) are static instances of the Inter variable font, not subset,
generated with the logo data by `tools/brand/generate_plan_brand.py` (see
`THIRD_PARTY_NOTICES.md`). Do not edit them or `ChapterLogoData.swift` by hand:

```sh
python3 -I tools/brand/generate_plan_brand.py --logo tools/brand/chapter-logo.svg \
  --inter "<path to>/Inter-VariableFont_slnt,wght.ttf"            # writes every brand output
python3 -I tools/brand/generate_plan_brand.py --logo tools/brand/chapter-logo.svg \
  --inter "<path to>/Inter-VariableFont_slnt,wght.ttf" --check    # byte-for-byte check
```

`ChapterFonts.register()` registers them for the process with `CTFontManagerRegisterFontsForURL`
(`UIAppFonts` cannot see a package's bundle). It is idempotent: call it in the app's `init` (done
in `ChapterCaptureApp`) and in the `setUp` of every snapshot test (`ChapterSnapshotTestCase` does).

## Using it

```swift
import ChapterUI

ScrollView {
  VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGap) {
    ChapterSection(header: "HUB project") {
      NavigationRow(title: "618 Valley Street", subtitle: "Deal 4821 · from the HUB, updated 2 min ago",
                    detail: "Change") { showProjects = true }
    }
    ChapterSection(header: "Address in the HUB", footer: "If the address on site is different, …") {
      ProminentTextRow(address)
      ToggleRow("I am at this address", isOn: $confirmed)
    }
  }
  .padding(.horizontal, ChapterTheme.Metric.screenPadding)
}
.navigationTitle("New capture")
.chapterNavigationCaption("Step 1 of 3")
.chapterBackChevronOnly()
.chapterScreenBackground()
.chapterActionBar {
  Button(label) { … }.buttonStyle(.chapter(.primary)).disabled(!canContinue)
}
```

| Area | API |
| --- | --- |
| Colour | `ChapterTheme.Color.ink` … (`Swatch` has the hex values and `uiColor`) |
| Type | `ChapterTheme.Font.body` for `.font`; `.chapterTextStyle(.footnote)` also applies the design line height to wrapping text |
| Metrics | `ChapterTheme.Metric.screenPadding`, `.primaryButtonHeight`, `.navigationRowHeight`, … |
| Navigation | `ChapterAppearance.apply()` (once, at launch), `.chapterRoot()` (on the root view: Inter, ink tint), `.chapterNavigationCaption(_:)`, `.chapterBackChevronOnly()`, `ScreenSubtitle`, `PlainToolbarItem`, `.chapterScreenBackground()`, `.chapterContentWidth()` |
| Sections | `ChapterSection(header:footer:)`, `ChapterCard`, `SectionCaption`, `SectionFooter` |
| Rows | `NavigationRow` (`.regular` 52 pt / `.compact` 48 pt overview rows), `ProgressNavigationRow`, `ValueRow`, `ProminentTextRow`, `ToggleRow`, `TextFieldRow`, `AddRow`, `RemovableRow`, `TextAreaRow` |
| Buttons | `.buttonStyle(.chapter(.primary / .tinted / .text / .rowAction / .cardAction / .outlineOnDark / .filledOnDark))`, `TextButton`, `ChapterActionBar` / `.chapterActionBar { }` |
| Controls | `ChapterSegmented`, `ChoiceChip`, `SheetBar` + `.chapterSheet()`, `AvatarButton` |
| Status | `StatusKind`, `StatusGlyph` (10 pt, 14 pt in the verdict card), `StatusLabel`, `RowStatus`, `Chevron` |
| Glyphs and notes | `PlusGlyph`, `EqualsGlyph`, `MinusGlyph`, `ProgressBar` (4 or 8 pt), `Banner`, `InfoNote` |
| Compass | `CompassGlyph(state:rotation:size:)` (32 pt row glyph), `CompassPillGlyph` (14 pt live-scan pill); map the contract's `CompassState` to `CompassGlyphState`. Pass `rotation` = −heading as it comes (0..<360 or any other range): the glyphs turn the short way round, so crossing north turns them 2°, not 358° |
| Brand | `ChapterLogo`, `ChapterFonts`, `ChapterTheme.TextStyle` |

At accessibility text sizes `NavigationRow` and `ValueRow` stack (detail and status under the
titles), so nothing is clipped.

## Snapshot tests

```swift
import ChapterUISnapshotTesting

@MainActor
final class HomeSnapshotTests: ChapterSnapshotTestCase {
  func testDrawnState() {
    assertChapterSnapshot(of: NavigationStack { CapturesHomeScreen(state: .drawn, actions: .none) },
                          named: "home")
  }
}
```

- The view is hosted, under `chapterRoot()` as in the app, in a `UIWindow` of 402 × 874 pt (safe
  area 62 / 34) in light appearance and drawn at scale 3; Dynamic Type with `contentSize:`
  (`.accessibilityExtraLarge` is AX3).
- **References are recorded on the iPhone 17 Pro simulator with iOS 26.0**
  (`ChapterSnapshot.referenceSystemVersion`), and ios.yml compares them on that iOS version or a
  point release of it, which the harness treats as the same system: `scripts/snapshot-simulator.sh`
  reads the version from the harness, picks the iPhone 17 Pro of that runtime on the runner image
  (26.0.1 there; 26.0 itself first when present), downloads the reference version (or, when
  Xcode does not offer it, its first point release on offer) when the image has neither, boots the device before the tests (again when a boot hangs, as the first boot of
  26.0.1 there usually does at "Waiting on BackBoard"), and never falls back to another iOS
  version. Another iOS version draws the system
  chrome differently, beyond the tolerance (iOS 18.5: the navigation bar boards differ by
  1.5–4.4 %, the switch board by 0.8 %); a failure on another runtime says so. When
  `referenceSystemVersion` moves, record again on the new runtime, or take the `*.actual.png`
  files of a failing CI run (artifact
  `xcresult-<package>`, folder `snapshots-<package>`; `snapshots-<package>-hosted` for the hosted
  tests) as the new `__Snapshots__/<test file>/<name>.png`, after looking at each.
- A snapshot fails when more than 0.5 % of its pixels differ by more than 8/255 in any channel
  (`SnapshotTolerance.phone`), or when the sizes differ.
- References live in `__Snapshots__/<test file name>/<name>.png` next to the test file; exclude
  `__Snapshots__` from the test target in `Package.swift`. A missing reference is recorded and
  the test fails; so does every test while `RECORD_SNAPSHOTS=1`.
- On a mismatch the new image, the reference and a diff (differing pixels in red) are attached to
  the test and written to `$SNAPSHOT_ARTIFACTS` (CI uploads them with the `.xcresult`).
- Package tests run in the bare `xctest` process, which has no `UIApplication`: `drawHierarchy`
  gets nothing from the render server there, so the window's layers are drawn in process
  (`layer.render(in:)`). Everything ChapterUI draws comes out, UIKit-backed views included,
  except what iOS 26 composites in the render server: the glass knob of a `Toggle` and the glass
  pill of the back button are missing, the back chevron is light, and content scrolled under the
  navigation bar comes out black.
- In a test bundle hosted by an app the harness uses `drawHierarchy(in:afterScreenUpdates:
  true)` (critique R-18d), and all of that is drawn. `HostedTests/HostedSnapshotTests` (target
  `ChapterUIHostedSnapshotTests`, host `ChapterUISnapshotHost`, scheme `ChapterUISnapshots` in
  ios/project.yml) snapshots the boards with system chrome that way: the pushed screen with its
  glass back pill, the collapsed title in the opaque standard bar (phone-capture §9 R6), the
  home header, the inline title and the switches; it shares the boards of
  `Tests/ChapterUITests/SnapshotBoards.swift`. Screens of other packages with system chrome can
  join it the same way. `SnapshotRenderer.drawsWithRenderServer` tells which path ran.
- Register fonts first: subclass `ChapterSnapshotTestCase` or call `ChapterSnapshot.prepare()`.

## Navigation bar notes

`ChapterAppearance.apply()` sets an opaque ground bar without a shadow line for the standard and
compact appearances, and a bar without a background of its own at the scroll edge (every screen
sits on ground, so it reads the same). On iOS 26 the large title lives in the screen's scroll
view, under the bar's background view: an opaque scroll-edge background would cover it.

The back chevron and bar buttons are ink. SwiftUI's `NavigationStack` takes their colour from
the SwiftUI tint and ignores `UINavigationBar.appearance().tintColor`, so put `.chapterRoot()` on
the root view (ChapterCaptureApp does): without it they are system blue on iOS 17 and 18. On
iOS 26 the chevron in its glass pill is drawn in the label colour whatever the tint.
