#if canImport(SwiftUI) && canImport(UIKit)
  import FieldRules
  import Foundation
  import PhotoStore
  import SwiftUI

  /// Text for an error under a screen. Known errors have their own wording; anything else uses
  /// the system description.
  func userMessage(for error: Error) -> String {
    switch error {
    case let error as PhotoStoreError: return error.description
    case let error as LengthParseError: return error.message
    case let error as FieldControlsEditError: return error.description
    case let error as FieldControlsFileError: return error.description
    #if canImport(AVFoundation)
      case let error as CameraError: return error.description
    #endif
    default: return error.localizedDescription
    }
  }

  /// Wraps chips onto several lines (design: `display: flex; flex-wrap: wrap; gap: 8px`).
  struct FlowLayout: Layout {
    var spacing: CGFloat = FieldTheme.space8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
      let maxWidth = proposal.width ?? .infinity
      var x: CGFloat = 0
      var y: CGFloat = 0
      var rowHeight: CGFloat = 0
      var widest: CGFloat = 0
      for subview in subviews {
        let size = subview.sizeThatFits(.unspecified)
        if x > 0, x + size.width > maxWidth {
          y += rowHeight + spacing
          x = 0
          rowHeight = 0
        }
        x += size.width
        widest = max(widest, x)
        x += spacing
        rowHeight = max(rowHeight, size.height)
      }
      return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(
      in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
      var x = bounds.minX
      var y = bounds.minY
      var rowHeight: CGFloat = 0
      for subview in subviews {
        let size = subview.sizeThatFits(.unspecified)
        if x > bounds.minX, x + size.width > bounds.maxX {
          y += rowHeight + spacing
          x = bounds.minX
          rowHeight = 0
        }
        subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
        rowHeight = max(rowHeight, size.height)
      }
    }
  }

  /// A selectable chip: ink with light text when selected, nude otherwise. At least 44 pt tall.
  /// `needsPhoto` puts a small dot before the title (blocked red, light on the selected chip)
  /// and "needs photo" in the accessibility value: a room the checklist still asks a photo of.
  struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    var horizontalPadding: CGFloat = 14
    var needsPhoto = false
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        HStack(spacing: 6) {
          if needsPhoto {
            Circle()
              .fill(isSelected ? FieldTheme.surface : FieldTheme.blocked)
              .frame(width: 7, height: 7)
              .accessibilityHidden(true)
          }
          Text(title)
        }
        .font(FieldTheme.chip)
        .padding(.horizontal, horizontalPadding)
        .frame(minHeight: FieldTheme.chipHeight)
        .foregroundStyle(isSelected ? FieldTheme.surface : FieldTheme.ink)
        .background(isSelected ? FieldTheme.ink : FieldTheme.nude)
        .clipShape(RoundedRectangle(cornerRadius: FieldTheme.chipRadius))
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .accessibilityValue(needsPhoto ? Text("needs photo") : Text(""))
    }
  }

  /// A quiet text action with an icon, at least 44 pt tall: "Rename rooms" next to a checklist
  /// row's main action and above the Room chips.
  struct InlineAction: View {
    let title: String
    var systemImage = "pencil"
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Label(title, systemImage: systemImage)
          .font(FieldTheme.chip)
          .foregroundStyle(FieldTheme.ink)
          .padding(.horizontal, FieldTheme.space4)
          .frame(minHeight: FieldTheme.chipHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  /// Full-width primary action: 56 pt, ink, light bold text; greyed out when disabled.
  struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Text(title)
          .font(FieldTheme.headline)
          .frame(maxWidth: .infinity)
          .frame(height: FieldTheme.primaryHeight)
          .foregroundStyle(isEnabled ? FieldTheme.surface : FieldTheme.disabledText)
          .background(isEnabled ? FieldTheme.ink : FieldTheme.line)
          .clipShape(RoundedRectangle(cornerRadius: FieldTheme.cardRadius))
      }
      .buttonStyle(.plain)
      .disabled(!isEnabled)
    }
  }

  /// Outlined 44 pt action used inside checklist rows ("Take photo", "Add controls").
  struct OutlineButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Text(title)
          .font(FieldTheme.chip)
          .padding(.horizontal, 14)
          .frame(minHeight: FieldTheme.chipHeight)
          .foregroundStyle(FieldTheme.ink)
          .overlay(
            RoundedRectangle(cornerRadius: FieldTheme.chipRadius)
              .stroke(FieldTheme.ink, lineWidth: 1))
      }
      .buttonStyle(.plain)
    }
  }

  /// Small muted label above a group of controls.
  struct FieldCaption: View {
    let text: String
    var body: some View {
      Text(text).font(FieldTheme.caption).foregroundStyle(FieldTheme.muted)
    }
  }

  extension View {
    /// Text field look from the design: surface fill, 1 pt line border, 12 pt radius, 52 pt tall.
    func fieldBox(fontSize: CGFloat = 17) -> some View {
      self
        .font(.system(size: fontSize))
        .padding(.horizontal, FieldTheme.space16)
        .frame(height: FieldTheme.fieldHeight)
        .background(FieldTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: FieldTheme.cardRadius))
        .overlay(
          RoundedRectangle(cornerRadius: FieldTheme.cardRadius)
            .stroke(FieldTheme.line, lineWidth: 1))
    }

    /// Screen background and horizontal padding shared by the three screens.
    func fieldScreen() -> some View {
      self
        .padding(.horizontal, 20)
        .padding(.top, FieldTheme.space8)
        .padding(.bottom, FieldTheme.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FieldTheme.ground.ignoresSafeArea())
        .foregroundStyle(FieldTheme.ink)
    }
  }
#endif
