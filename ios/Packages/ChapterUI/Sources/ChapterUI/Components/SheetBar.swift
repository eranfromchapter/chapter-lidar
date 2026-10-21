#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  private typealias Metric = ChapterTheme.Metric

  /// The top of a sheet (phone-field §1.3): the grabber (36 × 5, radius 3, line colour, 6 pt from
  /// the top), then a 52 pt bar, padding 0 × 16: "Cancel" (body ink, leading, min width 60), the
  /// title (navTitle, centred) and the action (bodyEmphasis ink, trailing, min width 60; #B9AFA2
  /// when disabled). Present the sheet with `.chapterSheet()`, which hides the system grabber.
  public struct SheetBar: View {
    let title: String
    let cancelTitle: String
    let onCancel: () -> Void
    let actionTitle: String?
    let isActionEnabled: Bool
    let onAction: () -> Void

    public init(
      title: String, cancelTitle: String = "Cancel", onCancel: @escaping () -> Void,
      actionTitle: String? = nil, isActionEnabled: Bool = true,
      onAction: @escaping () -> Void = {}
    ) {
      self.title = title
      self.cancelTitle = cancelTitle
      self.onCancel = onCancel
      self.actionTitle = actionTitle
      self.isActionEnabled = isActionEnabled
      self.onAction = onAction
    }

    public var body: some View {
      VStack(spacing: 0) {
        RoundedRectangle(cornerRadius: 3)
          .fill(ChapterTheme.Color.line)
          .frame(width: Metric.grabberWidth, height: Metric.grabberHeight)
          .padding(.top, Metric.grabberTop)
          .accessibilityHidden(true)
        ZStack {
          Text(title)
            .chapterTextStyle(.navTitle)
            .foregroundStyle(ChapterTheme.Color.ink)
            .lineLimit(1)
            .padding(.horizontal, Metric.sheetBarButtonWidth + Metric.rowGap)
            .accessibilityAddTraits(.isHeader)
          HStack {
            Button(action: onCancel) {
              Text(cancelTitle)
                .chapterTextStyle(.body)
                .foregroundStyle(ChapterTheme.Color.ink)
                .frame(
                  minWidth: Metric.sheetBarButtonWidth, minHeight: Metric.touchTarget,
                  alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if let actionTitle {
              Button(action: onAction) {
                Text(actionTitle)
                  .chapterTextStyle(.bodyEmphasis)
                  .foregroundStyle(
                    isActionEnabled ? ChapterTheme.Color.ink : ChapterTheme.Color.chevron
                  )
                  .frame(
                    minWidth: Metric.sheetBarButtonWidth, minHeight: Metric.touchTarget,
                    alignment: .trailing
                  )
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .disabled(!isActionEnabled)
            }
          }
        }
        .padding(.horizontal, Metric.screenPadding)
        .frame(minHeight: Metric.sheetBarHeight)
      }
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
