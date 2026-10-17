#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import SwiftUI

  private typealias Palette = ChapterTokens.Palette
  private typealias Space = ChapterTokens.Space
  private typealias Radius = ChapterTokens.Radius
  private typealias Control = ChapterTokens.Control
  private typealias Typo = ChapterTokens.Typography

  /// "chapter" serif with RENOVATION letter-spaced beneath. No other mark.
  struct Wordmark: View {
    var body: some View {
      VStack(spacing: 3) {
        Text("chapter").font(Typo.serif(20))
        Text("RENOVATION").font(Typo.sans(6)).tracking(3)
      }
      .foregroundStyle(Palette.ink)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Chapter Renovation")
    }
  }

  /// Ink button, 56 pt tall.
  struct PrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Text(title)
          .font(Typo.headline)
          .foregroundStyle(Palette.surface)
          .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
          .background(Palette.ink, in: RoundedRectangle(cornerRadius: Radius.card))
      }
      .buttonStyle(.plain)
      .disabled(!isEnabled)
      .opacity(isEnabled ? 1 : 0.4)
    }
  }

  /// Label above a field: caption 13, muted.
  struct FieldLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
      Text(text).font(Typo.caption).foregroundStyle(Palette.muted)
    }
  }

  /// Surface field background: fill, 1 pt line, radius 12.
  struct FieldBackground: ViewModifier {
    func body(content: Content) -> some View {
      content
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
    }
  }

  extension View {
    func fieldBackground() -> some View { modifier(FieldBackground()) }
  }

  /// Lays chips out left to right and wraps to the next row (the "Rooms you will not scan" chips).
  struct WrapLayout: Layout {
    var spacing: CGFloat = Space.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
      layout(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(
      in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
      let result = layout(in: bounds.width, subviews: subviews)
      for (index, origin) in result.origins.enumerated() {
        subviews[index].place(
          at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
      }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
      var origins: [CGPoint] = []
      var x: CGFloat = 0
      var y: CGFloat = 0
      var rowHeight: CGFloat = 0
      var maxX: CGFloat = 0
      for subview in subviews {
        let size = subview.sizeThatFits(.unspecified)
        if x > 0, x + size.width > width {
          x = 0
          y += rowHeight + spacing
          rowHeight = 0
        }
        origins.append(CGPoint(x: x, y: y))
        x += size.width + spacing
        rowHeight = max(rowHeight, size.height)
        maxX = max(maxX, x - spacing)
      }
      return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
  }
#endif
