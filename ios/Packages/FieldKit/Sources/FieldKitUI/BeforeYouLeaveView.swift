#if canImport(SwiftUI) && canImport(UIKit)
  import FieldRules
  import SwiftUI

  /// Before you leave (design screen-field, 3): the five checklist rows and the finish button,
  /// which stays disabled ("Fix 2 items to finish") until every row passes.
  public struct BeforeYouLeaveView: View {
    let report: ChecklistReport
    let onTakePhoto: (ChecklistItem) -> Void
    let onAddControls: (ChecklistItem) -> Void
    let onFinish: () -> Void

    public init(
      report: ChecklistReport,
      onTakePhoto: @escaping (ChecklistItem) -> Void,
      onAddControls: @escaping (ChecklistItem) -> Void,
      onFinish: @escaping () -> Void
    ) {
      self.report = report
      self.onTakePhoto = onTakePhoto
      self.onAddControls = onAddControls
      self.onFinish = onFinish
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text("Before you leave")
          .font(FieldTheme.title30())
        Text("Photos and controls cannot be recovered later. Fix these now.")
          .font(.system(size: 15))
          .foregroundStyle(FieldTheme.muted)

        ScrollView {
          VStack(spacing: 10) {
            ForEach(report.items, id: \.id) { item in
              row(item)
            }
          }
        }

        Spacer(minLength: 0)

        PrimaryButton(title: report.finishButtonTitle, isEnabled: report.canFinish) {
          onFinish()
        }
      }
      .fieldScreen()
    }

    private func row(_ item: ChecklistItem) -> some View {
      HStack(alignment: .top, spacing: FieldTheme.space12) {
        Text(item.passed ? "\u{25CF}" : "\u{25A0}")
          .font(.system(size: 17))
          .foregroundStyle(item.passed ? FieldTheme.ready : FieldTheme.blocked)
          .accessibilityLabel(item.passed ? "Done" : "Missing")
        VStack(alignment: .leading, spacing: item.passed ? 2 : 6) {
          Text(item.title).font(FieldTheme.rowTitle)
          Text(item.detail).font(FieldTheme.caption).foregroundStyle(FieldTheme.muted)
          if !item.passed {
            switch item.id {
            case .photoPerRoom:
              OutlineButton(title: "Take photo") { onTakePhoto(item) }
            case .minimumControls:
              OutlineButton(title: "Add controls") { onAddControls(item) }
            case .floorsLabeled, .skippedRoomsRecorded, .visitDetails:
              EmptyView()
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, FieldTheme.space16)
      .padding(.vertical, 14)
      .background(FieldTheme.surface)
      .clipShape(RoundedRectangle(cornerRadius: FieldTheme.cardRadius))
      .overlay(
        RoundedRectangle(cornerRadius: FieldTheme.cardRadius)
          .stroke(
            item.passed ? FieldTheme.line : FieldTheme.blocked, lineWidth: item.passed ? 1 : 2))
    }
  }
#endif
