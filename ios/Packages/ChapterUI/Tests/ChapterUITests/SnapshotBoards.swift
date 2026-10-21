#if canImport(UIKit) && os(iOS)
  import ChapterUI
  import SwiftUI

  // Component boards for the snapshot tests, one iPhone screen each, filled with the sample values
  // of the v2 artboards (2b, 2d, 2f, 2k).

  private typealias Palette = ChapterTheme.Color

  /// A screen of components on ground, under a small caption naming the board.
  struct Board<Content: View>: View {
    let title: String
    var spacing: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
      // In a scroll view, as on the screens: a board taller than the phone is cut off at the
      // bottom instead of squeezing its rows (the AX3 boards).
      ScrollView {
        VStack(alignment: .leading, spacing: spacing) {
          Text(title)
            .chapterTextStyle(.caption)
            .foregroundStyle(Palette.muted)
          content
        }
        .padding(.horizontal, ChapterTheme.Metric.screenPadding)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Palette.ground.ignoresSafeArea())
    }
  }

  /// The dark live-scan surface.
  struct DarkPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
      VStack(spacing: 12) { content }
        .padding(16)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 16))
    }
  }

  struct ButtonsBoard: View {
    var body: some View {
      Board(title: "Buttons · primary, tinted, text, row, card, on dark") {
        VStack(spacing: ChapterTheme.Metric.actionBarGap) {
          Button("Continue") {}.buttonStyle(.chapter(.primary))
          Button("Confirm the address to continue") {}.buttonStyle(.chapter(.primary))
            .disabled(true)
          Button("Scan another floor or room") {}.buttonStyle(.chapter(.tinted))
          Button("Seal revision 2") {}.buttonStyle(.chapter(.tinted)).disabled(true)
          TextButton("Done with photos") {}
          TextButton("Done with photos") {}.disabled(true)
        }
        HStack(spacing: 12) {
          Button("Read again") {}.buttonStyle(.chapter(.rowAction))
          Button("Read again") {}.buttonStyle(.chapter(.rowAction)).disabled(true)
          Button("Try again") {}.buttonStyle(.chapter(.cardAction))
        }
        DarkPanel {
          HStack(spacing: 12) {
            Button("Pause") {}.buttonStyle(.chapter(.outlineOnDark))
            Button("Finish floor") {}.buttonStyle(.chapter(.filledOnDark))
          }
          HStack(spacing: 12) {
            Button("Pause") {}.buttonStyle(.chapter(.outlineOnDark)).disabled(true)
            Button("Finish floor") {}.buttonStyle(.chapter(.filledOnDark)).disabled(true)
          }
          Button("Restart this floor instead") {}.buttonStyle(.chapter(.cardAction))
        }
      }
    }
  }

  struct NavigationRowsBoard: View {
    var body: some View {
      Board(title: "Navigation rows · progress, status, detail, compact (overview), add") {
        ChapterSection(header: "In progress") {
          ProgressNavigationRow(
            title: "618 Valley Street", subtitle: "2 floors · uploading · 512 of 768 MB",
            fraction: 0.67
          ) {}
        }
        ChapterSection(
          header: "Sealed",
          footer: "Files stay on this phone until the station confirms each one. Verdict details "
            + "are in the HUB."
        ) {
          NavigationRow(
            title: "424 West End Ave, Apt 4K", subtitle: "Revision 1 · sealed Jan 25, 2025",
            status: RowStatus(.partly, "Limited")
          ) {}
          NavigationRow(
            title: "24 Shawnee Road", subtitle: "Revision 2 · sealed Oct 20, 2026",
            status: RowStatus(.done, "Ready")
          ) {}
          NavigationRow(
            title: "11 Orchard Lane", subtitle: "Revision 1 · re-seal needed",
            status: RowStatus(.missing, "Blocked")
          ) {}
        }
        ChapterSection(header: "HUB project") {
          NavigationRow(
            title: "618 Valley Street", subtitle: "Deal 4821 · from the HUB, updated 2 min ago",
            detail: "Change"
          ) {}
          NavigationRow(
            title: "Choose a HUB project", subtitle: "Projects come from the HUB",
            detail: "Choose", isPlaceholder: true
          ) {}
        }
        ChapterSection(header: "Floors and areas") {
          NavigationRow(
            title: "Floor 1", subtitle: "Whole floor · 12 rooms · 42 photos · controls complete",
            status: RowStatus(.done, "Done"), density: .compact
          ) {}
          NavigationRow(
            title: "Compass", subtitle: "Floor 1 verified · Floor 2 not read",
            status: RowStatus(.partly, "Partly"), density: .compact
          ) {}
          AddRow(title: "Scan another floor or room") {}
        }
      }
    }
  }

  struct FormRowsBoard: View {
    @State private var confirmed = true
    @State private var notConfirmed = false

    var body: some View {
      Board(title: "Form rows · prominent text, toggle (system), value") {
        ChapterSection(
          header: "Address in the HUB",
          footer: "If the address on site is different, stop and call the PM. The station blocks "
            + "packages with a different address."
        ) {
          ProminentTextRow("618 Valley Street, Brooklyn, NY 11215")
          ToggleRow("I am at this address", isOn: $confirmed)
        }
        ChapterSection {
          ProminentTextRow("Choose a HUB project first", isPlaceholder: true)
          ToggleRow("I am at this address", isOn: $notConfirmed).disabled(true)
        }
        ChapterSection(header: "Recorded automatically") {
          ValueRow(label: "Operator", value: "Dana Ruiz")
          ValueRow(label: "Device", value: "iPhone 16 Pro · LiDAR")
          ValueRow(label: "App", value: "1.0.0 (37)")
        }
      }
    }
  }

  struct EntryRowsBoard: View {
    @State private var name = "Floor 1"
    @State private var emptyName = ""
    @State private var notes = ""

    var body: some View {
      Board(title: "Entry rows · text field, removable, add, text area") {
        ChapterSection {
          TextFieldRow(label: "Name", text: $name, accessibilityLabel: "Floor or area")
          TextFieldRow(label: "Name", text: $emptyName, prompt: "Floor 1")
        }
        ChapterSection(header: "Rooms you will not scan") {
          RemovableRow(title: "Primary closet", subtitle: "Locked") {}
          AddRow(title: "Add a room you cannot scan") {}
        }
        ChapterSection(header: "Coverage notes") {
          TextAreaRow(text: $notes, prompt: "Optional", accessibilityLabel: "Coverage notes")
        }
      }
    }
  }

  struct StatusBoard: View {
    var body: some View {
      Board(title: "Status · glyphs and words, verdict 14 pt, diff glyphs, progress, notes") {
        HStack(spacing: 16) {
          StatusLabel(kind: .done, word: "Done")
          StatusLabel(kind: .partly, word: "Partly")
          StatusLabel(kind: .missing, word: "Missing")
          StatusLabel(kind: .waiting, word: "Checking")
        }
        HStack(spacing: 16) {
          StatusLabel(kind: .done, word: "Verified", size: .small)
          StatusLabel(kind: .partly, word: "Approx.", size: .small)
          StatusLabel(kind: .missing, word: "Open", size: .small)
          StatusLabel(kind: .waiting, word: "Optional", size: .small)
        }
        HStack(spacing: 16) {
          ForEach(StatusKind.allCases, id: \.self) { kind in
            StatusGlyph(kind, size: ChapterTheme.Metric.verdictGlyph)
          }
          Text("Limited")
            .chapterTextStyle(.verdictWord)
            .foregroundStyle(StatusKind.partly.textColor)
          Spacer()
          PlusGlyph()
          EqualsGlyph()
          MinusGlyph()
          Chevron()
        }
        VStack(spacing: 10) {
          ProgressBar(fraction: 0.67)
          ProgressBar(fraction: 0.41, height: ChapterTheme.Metric.progressBarHeightLarge)
          ProgressBar(fraction: 0)
          ProgressBar(fraction: 1)
        }
        InfoNote(
          "Revision 1 stays sealed. What you change now becomes revision 2; files that did not "
            + "change are not uploaded again.")
        Banner(
          icon: .offline,
          text: "No connection. Showing the 12 projects saved on this phone (updated Oct 20, "
            + "14:12). You can scan offline; the upload waits for a connection.")
        Banner(icon: .blocked, text: "Could not load HUB projects: the station is not reachable.") {
          Button("Try again") {}.buttonStyle(.chapter(.rowAction))
        }
        Banner(icon: .partly, text: "This phone has no LiDAR, so it cannot scan.")
      }
    }
  }

  struct CompassBoard: View {
    var body: some View {
      Board(title: "Compass · 32 pt glyph (verified, approximate, not verified) and live pill") {
        HStack(spacing: 20) {
          CompassGlyph(state: .verified)
          CompassGlyph(state: .verified, rotation: -32)
          CompassGlyph(state: .approximate, rotation: -32)
          CompassGlyph(state: .notVerified, rotation: -32)
        }
        HStack(spacing: 12) {
          CompassGlyph(state: .verified, size: 112)
          CompassGlyph(state: .approximate, size: 112)
          CompassGlyph(state: .notVerified, size: 112)
        }
        ChapterSection(header: "Compass") {
          HStack(spacing: 12) {
            CompassGlyph(state: .verified, rotation: -32)
            VStack(alignment: .leading, spacing: 2) {
              Text("North 212° true · ±8°").chapterTextStyle(.body)
              StatusLabel(kind: .done, word: "Verified · read just now", size: .small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Read again") {}.buttonStyle(.chapter(.rowAction))
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .frame(minHeight: ChapterTheme.Metric.compassRowHeight)
        }
        DarkPanel {
          pill(.verified, "N · true · ±8°")
          pill(.approximate, "N · magnetic · ±12°")
          pill(.notVerified, "N · not verified")
        }
      }
    }

    private func pill(_ state: CompassGlyphState, _ text: String) -> some View {
      HStack(spacing: 6) {
        CompassPillGlyph(state: state, rotation: -32)
        Text(text)
          .chapterTextStyle(.footnote)
          .foregroundStyle(Palette.surface)
      }
      .padding(.horizontal, 10)
      .frame(height: 32)
      .background(Palette.onDarkPill, in: Capsule())
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  struct BrandBoard: View {
    var body: some View {
      Board(title: "Logo 26 pt and 40 pt, avatar", spacing: 20) {
        // The Captures home's bar: logo leading, avatar trailing, 44 pt.
        HStack {
          ChapterLogo()
          Spacer()
          AvatarButton(name: "Dana Ruiz") {}
        }
        .frame(height: 44)
        ChapterLogo(height: ChapterTheme.Metric.logoHeightLarge)
        ChapterLogo(height: 120)
        HStack(spacing: 12) {
          AvatarButton(name: "Dana Ruiz") {}
          AvatarButton(name: "Field test") {}
          AvatarButton(name: "Operator") {}
          AvatarButton(name: "") {}
        }
      }
    }
  }

  struct ControlsBoard: View {
    enum Mode: Hashable { case room, floor, exterior }

    @State private var none: Mode?
    @State private var floor: Mode? = .floor

    private var options: [ChapterSegmented<Mode>.Option] {
      [.init(.room, "One room"), .init(.floor, "Whole floor"), .init(.exterior, "Exterior")]
    }

    var body: some View {
      Board(title: "Controls · segmented, chips, captions, sheet bar") {
        ChapterSegmented("Mode", selection: $none, options: options)
        ChapterSegmented("Mode", selection: $floor, options: options)
        SectionCaption("Room", suffix: "· stays selected for the next photo", inset: 4)
        HStack(spacing: 8) {
          ChoiceChip("Kitchen", isSelected: true) {}
          ChoiceChip("Living", isSelected: false) {}
          ChoiceChip("Bath 1", isSelected: false, needsPhoto: true) {}
          ChoiceChip("Bath 2", isSelected: true, needsPhoto: true) {}
        }
        SectionCaption("Subject", inset: 4)
        HStack(spacing: 8) {
          ChoiceChip("Cabinetry", isSelected: true, kind: .subject) {}
          ChoiceChip("Fixtures", isSelected: false, kind: .subject) {}
          ChoiceChip("Ceiling", isSelected: false, kind: .subject) {}
        }
        SectionCaption("Floor 1", size: .small)
        VStack(spacing: 0) {
          SheetBar(title: "Floor to floor", onCancel: {}, actionTitle: "Save") {}
          Rectangle().fill(Palette.nude).frame(height: 1)
          SheetBar(title: "HUB project", onCancel: {}, actionTitle: "Save", isActionEnabled: false)
          Rectangle().fill(Palette.nude).frame(height: 1)
          SheetBar(title: "Rename rooms", onCancel: {})
        }
        .background(Palette.ground)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
      }
    }
  }

  struct TypeBoard: View {
    var body: some View {
      Board(title: "Type · Inter, Times New Roman for large titles, SF Mono", spacing: 6) {
        ForEach(ChapterTheme.TextStyle.all, id: \.name) { entry in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.name)
              .chapterTextStyle(.caption)
              .foregroundStyle(Palette.muted)
              .frame(width: 112, alignment: .leading)
            Text(sample(entry.name))
              .chapterTextStyle(entry.style)
              .foregroundStyle(Palette.ink)
              .lineLimit(1)
          }
        }
        Text(
          "Wrapping footnote 13/17: if the address on site is different, stop and call the PM. "
            + "The station blocks packages with a different address."
        )
        .chapterTextStyle(.footnote)
        .foregroundStyle(Palette.muted)
      }
    }

    private func sample(_ name: String) -> String {
      switch name {
      case "largeTitle": "Captures"
      case "glyphN": "N"
      case "mono", "mono13", "mono11": "06:42 · 36' 10.5\""
      case "count": "11 walls"
      case "verdictWord": "Limited"
      case "entryValue": "3,061 mm"
      default: "North 212° true · ±8° → 75…"
      }
    }
  }

  /// A pushed form screen in the system navigation bar: back chevron, large title, trailing
  /// caption, subtitle, sections and the bottom action bar.
  struct PushedScreen: View {
    var body: some View {
      NavigationStack(path: .constant([1])) {
        Color.clear
          .navigationDestination(for: Int.self) { _ in
            ScrollView {
              VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGap) {
                ScreenSubtitle("Captured today by Dana Ruiz · not sealed yet")
                ChapterSection(header: "HUB project") {
                  NavigationRow(
                    title: "618 Valley Street",
                    subtitle: "Deal 4821 · from the HUB, updated 2 min ago", detail: "Change"
                  ) {}
                }
                ChapterSection(header: "Recorded automatically") {
                  ValueRow(label: "Operator", value: "Dana Ruiz")
                  ValueRow(label: "App", value: "1.0.0 (37)")
                }
              }
              .padding(.horizontal, ChapterTheme.Metric.screenPadding)
              .padding(.top, ChapterTheme.Metric.subtitleTop)
            }
            .navigationTitle("New capture")
            .navigationBarTitleDisplayMode(.large)
            .chapterNavigationCaption("Step 1 of 3")
            .chapterBackChevronOnly()
            .chapterScreenBackground()
            .chapterActionBar {
              Button("Confirm the address to continue") {}.buttonStyle(.chapter(.primary))
                .disabled(true)
            }
          }
      }
    }
  }

  /// The Captures home's bar: logo leading, avatar trailing, large title.
  struct HomeHeaderScreen: View {
    var body: some View {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGap) {
            ChapterSection {
              ProminentTextRow("No captures on this phone yet.", isPlaceholder: true)
            } footer: {
              SectionFooter("Tap New capture to scan a floor or room.")
            }
          }
          .padding(.horizontal, ChapterTheme.Metric.screenPadding)
          .padding(.top, ChapterTheme.Metric.contentTop)
        }
        .navigationTitle("Captures")
        .toolbar {
          PlainToolbarItem(placement: .topBarLeading) { ChapterLogo() }
          PlainToolbarItem(placement: .topBarTrailing) { AvatarButton(name: "Dana Ruiz") {} }
        }
        .chapterScreenBackground()
        .chapterActionBar {
          Button("New capture") {}.buttonStyle(.chapter(.primary))
        }
      }
    }
  }

  /// An inline title (the labeling screen and sheets).
  struct InlineTitleScreen: View {
    var body: some View {
      NavigationStack {
        VStack(alignment: .leading, spacing: 6) {
          SectionCaption("Room", suffix: "· stays selected for the next photo", inset: 4)
          HStack(spacing: 8) {
            ChoiceChip("Kitchen", isSelected: true) {}
            ChoiceChip("Living", isSelected: false) {}
          }
        }
        .padding(.horizontal, ChapterTheme.Metric.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Photo 14 · Floor 1")
        .navigationBarTitleDisplayMode(.inline)
        .chapterScreenBackground()
        .chapterActionBar {
          Button("Save and take next") {}.buttonStyle(.chapter(.primary))
          TextButton("Done with photos") {}
        }
      }
    }
  }
#endif
