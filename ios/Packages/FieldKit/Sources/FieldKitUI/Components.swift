#if canImport(SwiftUI) && canImport(UIKit)
  import ChapterUI
  import FieldRules
  import Foundation
  import PhotoStore
  import SwiftUI

  // The few pieces the field screens share that ChapterUI does not have. Buttons, chips, the
  // segmented control, cards, captions, status glyphs, the chevron and the sheet bar are
  // ChapterUI's (critique R-18).

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
    var spacing: CGFloat = FieldMetric.chipGap

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

  /// A quiet text action with an icon, at least 44 pt tall (phone-field §1.3): pencil and
  /// "Rename rooms" in subhead 15 ink.
  struct InlineAction: View {
    let title: String
    var systemImage = "pencil"
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Label(title, systemImage: systemImage)
          .chapterTextStyle(.subhead)
          .foregroundStyle(FieldTheme.Color.ink)
          .frame(minHeight: FieldTheme.Metric.touchTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  /// A row that is a button: nude while pressed, dimmed when disabled.
  struct FieldRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .contentShape(Rectangle())
        .background(configuration.isPressed ? FieldTheme.Color.nude : Color.clear)
    }
  }

  /// A footnote under a card or list (13/17, 16 pt inset, wrapping): muted, or blocked for an
  /// error.
  struct FieldFootnote: View {
    let text: String
    var isError = false

    var body: some View {
      Text(text)
        .chapterTextStyle(.footnote)
        .foregroundStyle(isError ? FieldTheme.Color.blocked : FieldTheme.Color.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, FieldTheme.Metric.sectionInset)
    }
  }

  /// "No photo yet" with the chips' 7 pt dot, footnote blocked: a room the checklist still asks
  /// a photo of.
  struct NoPhotoYetLabel: View {
    var body: some View {
      HStack(spacing: 6) {
        Circle().fill(FieldTheme.Color.blocked).frame(width: 7, height: 7)
        Text("No photo yet")
          .chapterTextStyle(.footnote)
          .foregroundStyle(FieldTheme.Color.blocked)
      }
      .fixedSize()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("No photo yet")
    }
  }

  /// The back button of a screen that must ask before leaving ("Label a photo", phone-field
  /// §1.3): a leading toolbar button with the system `chevron.left`. iOS 26 puts it in the glass
  /// pill like the system back button; earlier versions get the drawn pill (44 pt, surface at
  /// 80 %, hairline border, two soft shadows).
  struct InterceptedBackButton: View {
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        if #available(iOS 26.0, *) {
          chevron
        } else {
          chevron
            .frame(width: 44, height: 44)
            .background(
              Circle().fill(FieldTheme.Color.surface.opacity(0.8))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.07), radius: 1.5, y: 1)
                .shadow(color: .black.opacity(0.06), radius: 5, y: 3))
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Back")
      .accessibilityIdentifier("photo.back")
    }

    private var chevron: some View {
      Image(systemName: "chevron.left")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(FieldTheme.Color.ink)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
  }

  /// The footnote of a screen opened after the visit was sealed (phone-field addendum B4).
  enum ReadOnlyText {
    static func sealed(revision: Int) -> String {
      "Revision \(revision) is sealed. To change it, use Add to this capture on the verdict screen."
    }
  }
#endif
