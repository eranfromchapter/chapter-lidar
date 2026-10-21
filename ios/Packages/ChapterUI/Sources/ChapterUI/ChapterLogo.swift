#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// The real Chapter logo, "chapter" over "RENOVATION", drawn from the vector paths of
  /// `ChapterLogoData` (generated from tools/brand/chapter-logo.svg, the paths PlanExport draws on
  /// the plans) in brand black #231F20. It replaces the typed serif wordmark of v1, which must
  /// not be drawn anywhere.
  ///
  /// One accessibility element, "Chapter Renovation". Sizes: 26 pt tall (about 72 pt wide) in the
  /// Captures home's navigation bar, 40 pt on the sign-in screen.
  public struct ChapterLogo: View {
    /// Width over height of the logo (1756 : 635).
    public nonisolated static let aspectRatio =
      ChapterLogoData.logoWidth / ChapterLogoData.logoHeight

    /// Width of the logo drawn `height` tall.
    public nonisolated static func width(forHeight height: CGFloat) -> CGFloat {
      height * aspectRatio
    }

    public let height: CGFloat

    public init(height: CGFloat = ChapterTheme.Metric.logoHeight) {
      self.height = height
    }

    public var body: some View {
      Canvas { context, size in
        let scale = size.height / ChapterLogoData.logoHeight
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        // One fill per path (nonzero), as the logo is drawn on the plans.
        for path in ChapterLogoPaths.paths {
          context.fill(path.applying(transform), with: .color(ChapterTheme.Color.logo))
        }
      }
      .frame(width: Self.width(forHeight: height), height: height)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text("Chapter Renovation"))
      .accessibilityAddTraits(.isImage)
    }
  }

  /// The logo's paths in logo units, y down from the top left of the ink, parsed once.
  enum ChapterLogoPaths {
    static let paths: [Path] = ChapterLogoData.logoPaths.map { path(from: $0) }

    /// Parses `M x y`, `C x1 y1 x2 y2 x y` and `Z` commands (y up) into a path with y down.
    static func path(from text: String, height: Double = ChapterLogoData.logoHeight) -> Path {
      var path = Path()
      var command: Character = "M"
      var numbers: [Double] = []
      func point(_ i: Int) -> CGPoint { CGPoint(x: numbers[i], y: height - numbers[i + 1]) }
      func flush() {
        switch command {
        case "M":
          for i in stride(from: 0, to: numbers.count - 1, by: 2) { path.move(to: point(i)) }
        case "C":
          for i in stride(from: 0, to: numbers.count - 5, by: 6) {
            path.addCurve(to: point(i + 4), control1: point(i), control2: point(i + 2))
          }
        default:
          break
        }
        numbers.removeAll(keepingCapacity: true)
      }
      for token in text.split(whereSeparator: \.isWhitespace) {
        if let value = Double(token) {
          numbers.append(value)
        } else if let letter = token.first {
          flush()
          command = letter
          if letter == "Z" { path.closeSubpath() }
        }
      }
      flush()
      return path
    }
  }
#endif
