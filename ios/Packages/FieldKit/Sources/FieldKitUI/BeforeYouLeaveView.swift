#if canImport(SwiftUI) && canImport(UIKit)
  import FieldRules
  import SwiftUI

  /// Before you leave (design screen-field, 3): the five checklist rows and the finish button,
  /// which stays disabled ("Fix 2 items to finish") until every row passes.
  ///
  /// "No rooms skipped" appears on the skipped-rooms row only when no room note exists and the
  /// operator has not confirmed yet, and only when `onConfirmNoRoomsSkipped` is given. The caller
  /// records the tap (`NoRoomsSkippedConfirmation.confirm(for:)`) and rebuilds the report.
  ///
  /// "Rename rooms" sits on the photo row, failed or passed, when `onRenameRooms` is given: a room
  /// the scan named wrong ("Closet" that is a shower) is renamed instead of photographed under
  /// the wrong name.
  public struct BeforeYouLeaveView: View {
    let report: ChecklistReport
    let onTakePhoto: (ChecklistItem) -> Void
    let onAddControls: (ChecklistItem) -> Void
    let onConfirmNoRoomsSkipped: (() -> Void)?
    let onRenameRooms: (() -> Void)?
    let onFinish: () -> Void

    public init(
      report: ChecklistReport,
      onTakePhoto: @escaping (ChecklistItem) -> Void,
      onAddControls: @escaping (ChecklistItem) -> Void,
      onConfirmNoRoomsSkipped: (() -> Void)? = nil,
      onRenameRooms: (() -> Void)? = nil,
      onFinish: @escaping () -> Void
    ) {
      self.report = report
      self.onTakePhoto = onTakePhoto
      self.onAddControls = onAddControls
      self.onConfirmNoRoomsSkipped = onConfirmNoRoomsSkipped
      self.onRenameRooms = onRenameRooms
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
          if item.passed, item.id == .photoPerRoom, let onRenameRooms {
            // The 44 pt target reaches into the row's padding, so the row stays as compact as
            // the others.
            InlineAction(title: "Rename rooms", action: onRenameRooms)
              .padding(.leading, -FieldTheme.space4)
              .padding(.vertical, -FieldTheme.space8)
              .padding(.top, FieldTheme.space4)
              .accessibilityIdentifier("checklist.renameRooms")
          }
          if !item.passed {
            switch item.id {
            case .photoPerRoom:
              HStack(spacing: FieldTheme.space12) {
                OutlineButton(title: "Take photo") { onTakePhoto(item) }
                if let onRenameRooms {
                  InlineAction(title: "Rename rooms", action: onRenameRooms)
                    .accessibilityIdentifier("checklist.renameRooms")
                }
              }
            case .minimumControls:
              OutlineButton(title: "Add controls") { onAddControls(item) }
            case .skippedRoomsRecorded:
              if let onConfirmNoRoomsSkipped, item.gaps.contains(.skippedRoomsNotRecorded) {
                OutlineButton(title: "No rooms skipped") { onConfirmNoRoomsSkipped() }
              }
            case .floorsLabeled, .visitDetails:
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
