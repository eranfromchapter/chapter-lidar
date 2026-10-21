#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// A polygon or polyline given in the coordinates of a design view box (y down), scaled to the
  /// rectangle it is drawn in: the status triangle, the chevron and the compass arrows.
  struct ViewBoxPolygon: Shape {
    let points: [CGPoint]
    let viewBox: CGSize
    var closed = true

    func path(in rect: CGRect) -> Path {
      let sx = rect.width / viewBox.width
      let sy = rect.height / viewBox.height
      var path = Path()
      path.addLines(points.map { CGPoint(x: rect.minX + $0.x * sx, y: rect.minY + $0.y * sy) })
      if closed { path.closeSubpath() }
      return path
    }
  }

  extension View {
    /// Sets the accessibility identifier when there is one.
    @ViewBuilder
    func accessibilityIdentifier(ifPresent identifier: String?) -> some View {
      if let identifier {
        accessibilityIdentifier(identifier)
      } else {
        self
      }
    }
  }
#endif
