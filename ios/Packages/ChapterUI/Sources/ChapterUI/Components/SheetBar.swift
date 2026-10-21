#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  private typealias Metric = ChapterTheme.Metric

  /// The top of a sheet (phone-field §1.3): the grabber (36 × 5, radius 3, line colour, 6 pt from
  /// the top), then a 52 pt bar, padding 0 × 16: "Cancel" (body ink, leading, min width 60), the
  /// title (navTitle, centred) and the action (bodyEmphasis ink, trailing, min width 60; #B9AFA2
  /// when disabled). Present the sheet with `.chapterSheet()`, which hides the system grabber.
  ///
  /// The title is never cut: it wraps between the buttons, and at accessibility text sizes it
  /// takes a row of its own, the full width of the sheet, under Cancel and the action.
  public struct SheetBar: View {
    let title: String
    let cancelTitle: String
    let onCancel: () -> Void
    let actionTitle: String?
    let isActionEnabled: Bool
    let onAction: () -> Void
    let cancelAccessibilityIdentifier: String?
    let actionAccessibilityIdentifier: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
      title: String, cancelTitle: String = "Cancel", onCancel: @escaping () -> Void,
      actionTitle: String? = nil, isActionEnabled: Bool = true,
      onAction: @escaping () -> Void = {}, cancelAccessibilityIdentifier: String? = nil,
      actionAccessibilityIdentifier: String? = nil
    ) {
      self.title = title
      self.cancelTitle = cancelTitle
      self.onCancel = onCancel
      self.actionTitle = actionTitle
      self.isActionEnabled = isActionEnabled
      self.onAction = onAction
      self.cancelAccessibilityIdentifier = cancelAccessibilityIdentifier
      self.actionAccessibilityIdentifier = actionAccessibilityIdentifier
    }

    public var body: some View {
      VStack(spacing: 0) {
        RoundedRectangle(cornerRadius: 3)
          .fill(ChapterTheme.Color.line)
          .frame(width: Metric.grabberWidth, height: Metric.grabberHeight)
          .padding(.top, Metric.grabberTop)
          .accessibilityHidden(true)
        if dynamicTypeSize.isAccessibilitySize {
          // VoiceOver keeps the order of the one-row bar: Cancel, the title, the action.
          VStack(spacing: 0) {
            HStack(spacing: Metric.rowGap) {
              cancelButton.accessibilitySortPriority(3)
              Spacer(minLength: 0)
              if actionTitle != nil {
                actionButton.accessibilitySortPriority(1)
              }
            }
            titleText
              .frame(maxWidth: .infinity)
              .padding(.bottom, Metric.rowGap)
              .accessibilitySortPriority(2)
          }
          .accessibilityElement(children: .contain)
          .padding(.horizontal, Metric.screenPadding)
        } else {
          // The title takes the room between the two buttons (at least 60 pt each, so it is
          // centred at the default text size) and wraps rather than run into them.
          HStack(spacing: Metric.rowGap) {
            cancelButton
            titleText.frame(maxWidth: .infinity)
            if actionTitle != nil {
              actionButton
            } else {
              Color.clear
                .frame(width: Metric.sheetBarButtonWidth, height: 1)
                .accessibilityHidden(true)
            }
          }
          .padding(.horizontal, Metric.screenPadding)
          .frame(minHeight: Metric.sheetBarHeight)
        }
      }
    }

    private var titleText: some View {
      Text(title)
        .chapterTextStyle(.navTitle)
        .foregroundStyle(ChapterTheme.Color.ink)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
    }

    private var cancelButton: some View {
      Button(action: onCancel) {
        Text(cancelTitle)
          .chapterTextStyle(.body)
          .foregroundStyle(ChapterTheme.Color.ink)
          .lineLimit(1)
          .frame(
            minWidth: Metric.sheetBarButtonWidth, minHeight: Metric.touchTarget,
            alignment: .leading
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .fixedSize()
      .accessibilityIdentifier(ifPresent: cancelAccessibilityIdentifier)
    }

    private var actionButton: some View {
      Button(action: onAction) {
        Text(actionTitle ?? "")
          .chapterTextStyle(.bodyEmphasis)
          .foregroundStyle(isActionEnabled ? ChapterTheme.Color.ink : ChapterTheme.Color.chevron)
          .lineLimit(1)
          .frame(
            minWidth: Metric.sheetBarButtonWidth, minHeight: Metric.touchTarget,
            alignment: .trailing
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .fixedSize()
      .disabled(!isActionEnabled)
      .accessibilityIdentifier(ifPresent: actionAccessibilityIdentifier)
    }
  }

  extension View {
    /// A sheet in the Chapter look: radius 16, ground background, and no system grabber (the
    /// `SheetBar` draws its own).
    public func chapterSheet() -> some View {
      presentationCornerRadius(ChapterTheme.Metric.sheetRadius)
        .presentationDragIndicator(.hidden)
        .presentationBackground(ChapterTheme.Color.ground)
    }
  }
#endif
