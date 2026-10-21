#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import ChapterUI
  import FieldRules
  import SwiftUI

  /// "Before you leave" (design v2, artboard 2d-4; phone-field §6): the six checklist rows in one
  /// card, and "Finish capture", disabled as `Fix 2 items to finish` while a blocking row fails.
  /// The compass row is advisory (▲): it is shown and never blocks.
  ///
  /// Failing rows offer their fix: "All rooms scanned" (only with `onConfirmNoRoomsSkipped`),
  /// "Take photo", "Add" (field controls) and "Read" (only with `onReadCompass`; the app passes
  /// nil, critique R-22). "Rename rooms" sits under the photo row, passed or failing, when
  /// `onRenameRooms` is given.
  ///
  /// `focus` scrolls a row into view and flashes it (the capture overview's Compass and Rooms not
  /// scanned rows). `isReadOnly` (a sealed visit): no buttons, and a footnote instead of Finish.
  public struct BeforeYouLeaveView: View {
    let report: ChecklistReport
    let headerCaption: String
    let focus: ChecklistItemID?
    let isReadOnly: Bool
    let sealedRevision: Int
    let onTakePhoto: (ChecklistItem) -> Void
    let onAddControls: (ChecklistItem) -> Void
    let onReadCompass: ((LowercaseUUID) -> Void)?
    let onConfirmNoRoomsSkipped: (() -> Void)?
    let onRenameRooms: (() -> Void)?
    let onFinish: () -> Void
    @State private var highlighted: ChecklistItemID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The glyph grows with the text (10 pt at the default size).
    @ScaledMetric(relativeTo: .body) private var glyphSize = ChapterTheme.Metric.statusGlyph

    /// - Parameters:
    ///   - headerCaption: the HUB project name (else the address up to the first comma), at the
    ///     right of the navigation bar.
    ///   - focus: the row to scroll to and flash on appear.
    ///   - isReadOnly: the visit is sealed and not in revision mode.
    ///   - sealedRevision: the sealed revision, for the read-only footnote.
    public init(
      report: ChecklistReport,
      headerCaption: String = "",
      focus: ChecklistItemID? = nil,
      isReadOnly: Bool = false,
      sealedRevision: Int = 1,
      onTakePhoto: @escaping (ChecklistItem) -> Void,
      onAddControls: @escaping (ChecklistItem) -> Void,
      onReadCompass: ((LowercaseUUID) -> Void)? = nil,
      onConfirmNoRoomsSkipped: (() -> Void)? = nil,
      onRenameRooms: (() -> Void)? = nil,
      onFinish: @escaping () -> Void
    ) {
      self.report = report
      self.headerCaption = headerCaption
      self.focus = focus
      self.isReadOnly = isReadOnly
      self.sealedRevision = sealedRevision
      self.onTakePhoto = onTakePhoto
      self.onAddControls = onAddControls
      self.onReadCompass = onReadCompass
      self.onConfirmNoRoomsSkipped = onConfirmNoRoomsSkipped
      self.onRenameRooms = onRenameRooms
      self.onFinish = onFinish
    }

    public var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ScreenSubtitle("Photos and controls cannot be recovered later. Fix these now.")
              .padding(.top, FieldTheme.Metric.subtitleTop)
            VStack(alignment: .leading, spacing: FieldMetric.checklistGap) {
              ChapterCard {
                ForEach(report.items, id: \.id) { item in
                  row(item).id(item.id)
                }
              }
              FieldFootnote(
                text: isReadOnly
                  ? ReadOnlyText.sealed(revision: sealedRevision)
                  : "Red items block the package. The compass is recommended, not required.")
              .accessibilityIdentifier("checklist.footnote")
            }
            .padding(.top, FieldMetric.checklistCardTop)
          }
          .padding(.horizontal, FieldTheme.Metric.screenPadding)
          .padding(.bottom, FieldTheme.Metric.screenPadding)
          .chapterContentWidth()
        }
        .onAppear { reveal(proxy) }
      }
      .navigationTitle("Before you leave")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        PlainToolbarItem(placement: .topBarTrailing) {
          Text(headerCaption)
            .chapterTextStyle(.footnote)
            .foregroundStyle(FieldTheme.Color.muted)
            .lineLimit(1)
            .accessibilityIdentifier("checklist.property")
        }
      }
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if !isReadOnly {
          ChapterActionBar {
            Button(report.finishButtonTitle, action: onFinish)
              .buttonStyle(.chapter(.primary))
              .disabled(!report.canFinish)
              .accessibilityIdentifier("checklist.finish")
          }
        }
      }
    }

    /// Scrolls the focused row into view and fills it nude for 0.6 s (no fade with Reduce
    /// Motion).
    private func reveal(_ proxy: ScrollViewProxy) {
      guard let focus else { return }
      DispatchQueue.main.async {
        proxy.scrollTo(focus, anchor: .center)
        highlighted = focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
          if reduceMotion {
            highlighted = nil
          } else {
            withAnimation(.easeOut(duration: 0.3)) { highlighted = nil }
          }
        }
      }
    }

    // MARK: Rows

    private func row(_ item: ChecklistItem) -> some View {
      let action = isReadOnly || item.passed ? nil : trailingAction(item)
      // At accessibility text sizes the button goes under the detail, so the text keeps the
      // row's width.
      let stacked = dynamicTypeSize.isAccessibilitySize
      return HStack(spacing: FieldTheme.Metric.rowGap) {
        // VoiceOver reads the status, the title, the detail, then the row's button.
        StatusGlyph(glyph(item), size: glyphSize, accessibilityLabel: statusWord(item))
        VStack(alignment: .leading, spacing: FieldTheme.Metric.rowTitleGap) {
          Text(item.title)
            .chapterTextStyle(.body)
            .foregroundStyle(FieldTheme.Color.ink)
          Text(item.detail)
            .chapterTextStyle(.footnote)
            .foregroundStyle(detailColor(item))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("checklist.detail.\(item.id.rawValue)")
          if item.id == .photoPerRoom, let onRenameRooms, !isReadOnly {
            // The 44 pt target reaches into the row's padding, so the row stays compact.
            InlineAction(title: "Rename rooms", action: onRenameRooms)
              .padding(.vertical, -8)
              .padding(.top, 4)
              .accessibilityIdentifier("checklist.renameRooms")
          }
          if stacked, let action {
            actionButton(action).padding(.top, 6)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if !stacked, let action {
          actionButton(action)
        }
      }
      .padding(.horizontal, FieldTheme.Metric.rowPadding)
      .padding(.vertical, 8)
      .frame(
        maxWidth: .infinity,
        minHeight: action == nil
          ? FieldMetric.checklistRowHeight : FieldMetric.checklistRowWithButtonHeight,
        alignment: .leading
      )
      .background(highlighted == item.id ? FieldTheme.Color.nude : Color.clear)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("checklist.row.\(item.id.rawValue)")
    }

    private struct RowAction {
      let title: String
      let identifier: String
      let perform: () -> Void
    }

    private func actionButton(_ action: RowAction) -> some View {
      Button(action.title, action: action.perform)
        .buttonStyle(.chapter(.rowAction))
        .fixedSize()
        .accessibilityIdentifier(action.identifier)
    }

    private func trailingAction(_ item: ChecklistItem) -> RowAction? {
      switch item.id {
      case .skippedRoomsRecorded:
        guard let onConfirmNoRoomsSkipped, item.gaps.contains(.skippedRoomsNotRecorded) else {
          return nil
        }
        return RowAction(
          title: "All rooms scanned", identifier: "checklist.allRoomsScanned",
          perform: onConfirmNoRoomsSkipped)
      case .photoPerRoom:
        return RowAction(
          title: "Take photo", identifier: "checklist.takePhoto", perform: { onTakePhoto(item) })
      case .minimumControls:
        return RowAction(
          title: "Add", identifier: "checklist.addControls", perform: { onAddControls(item) })
      case .compass:
        guard let onReadCompass, let capture = report.firstCaptureWithoutVerifiedCompass else {
          return nil
        }
        return RowAction(
          title: "Read", identifier: "checklist.readCompass", perform: { onReadCompass(capture) })
      case .floorsLabeled, .visitDetails:
        return nil
      }
    }

    /// ● passed, ■ a failing blocking row, ▲ the failing compass.
    private func glyph(_ item: ChecklistItem) -> StatusKind {
      if item.passed { return .done }
      return item.severity == .advisory ? .partly : .missing
    }

    private func detailColor(_ item: ChecklistItem) -> Color {
      if item.passed { return FieldTheme.Color.muted }
      return item.severity == .advisory ? FieldTheme.Color.limitedText : FieldTheme.Color.blocked
    }

    private func statusWord(_ item: ChecklistItem) -> String {
      if item.passed { return "Done" }
      return item.severity == .advisory ? "Recommended" : "Missing"
    }
  }
#endif
