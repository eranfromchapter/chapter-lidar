#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// A selectable chip (phone-field §1.3): min height 44, radius 8, padding 0 × 14 for rooms and
  /// 0 × 12 for subjects; off: nude fill, subhead ink; on: ink fill, subhead surface.
  ///
  /// `needsPhoto` puts a 7 pt dot 5 pt inside the top right corner (#8B2E2E, #FAF5EE on a selected
  /// chip) and "needs photo" in the accessibility value: a room the checklist still asks a photo
  /// of. The dot sits in the padding, so the chip is as wide as without it.
  public struct ChoiceChip: View {
    public enum Kind: Sendable {
      /// Room chips: padding 0 × 14.
      case room
      /// Subject chips: padding 0 × 12.
      case subject
    }

    let title: String
    let isSelected: Bool
    let kind: Kind
    let needsPhoto: Bool
    let action: () -> Void

    public init(
      _ title: String, isSelected: Bool, kind: Kind = .room, needsPhoto: Bool = false,
      action: @escaping () -> Void
    ) {
      self.title = title
      self.isSelected = isSelected
      self.kind = kind
      self.needsPhoto = needsPhoto
      self.action = action
    }

    public var body: some View {
      Button(action: action) {
        Text(title)
          .chapterTextStyle(.subhead)
          .foregroundStyle(isSelected ? ChapterTheme.Color.surface : ChapterTheme.Color.ink)
          .padding(
            .horizontal,
            kind == .room
              ? ChapterTheme.Metric.roomChipPadding : ChapterTheme.Metric.subjectChipPadding
          )
          .padding(.vertical, 4)
          .frame(minHeight: ChapterTheme.Metric.chipHeight)
          .background(isSelected ? ChapterTheme.Color.ink : ChapterTheme.Color.nude)
          .overlay(alignment: .topTrailing) {
            if needsPhoto {
              Circle()
                .fill(isSelected ? ChapterTheme.Color.surface : ChapterTheme.Color.blocked)
                .frame(width: 7, height: 7)
                .padding(5)
                .accessibilityHidden(true)
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: ChapterTheme.Metric.chipRadius))
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .accessibilityValue(needsPhoto ? Text("needs photo") : Text(""))
    }
  }
#endif
