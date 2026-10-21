#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// The disclosure chevron of a navigation row: 8 × 14, path `M1 1 L7 7 L1 13`, stroke 2, round
  /// caps and joins, #B9AFA2. Decorative.
  public struct Chevron: View {
    public let color: Color

    public init(color: Color = ChapterTheme.Color.chevron) {
      self.color = color
    }

    public var body: some View {
      ViewBoxPolygon(
        points: [CGPoint(x: 1, y: 1), CGPoint(x: 7, y: 7), CGPoint(x: 1, y: 13)],
        viewBox: CGSize(width: 8, height: 14), closed: false
      )
      .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
      .frame(width: ChapterTheme.Metric.chevronWidth, height: ChapterTheme.Metric.chevronHeight)
      .accessibilityHidden(true)
    }
  }

  /// A 22 pt circle with #FAF5EE bars: the shared drawing of the plus, equals and minus glyphs.
  private struct CircleBars: View {
    let fill: Color
    /// Bars as (width, height, y offset from the centre).
    let bars: [(CGFloat, CGFloat, CGFloat)]
    let accessibilityLabel: String?

    var body: some View {
      ZStack {
        Circle().fill(fill)
        ForEach(bars.indices, id: \.self) { index in
          let bar = bars[index]
          Rectangle()
            .fill(ChapterTheme.Color.surface)
            .frame(width: bar.0, height: bar.1)
            .offset(y: bar.2)
        }
      }
      .frame(width: ChapterTheme.Metric.circleGlyph, height: ChapterTheme.Metric.circleGlyph)
      .accessibilityElement(children: .ignore)
      .accessibilityHidden(accessibilityLabel == nil)
      .accessibilityLabel(Text(accessibilityLabel ?? ""))
    }
  }

  /// Added item (and the "add" row): a 22 pt #2E5E2E circle with a centred plus (bars 10 × 2 and
  /// 2 × 10). Pass `accessibilityLabel: nil` where the row already says it.
  public struct PlusGlyph: View {
    public let accessibilityLabel: String?

    public init(accessibilityLabel: String? = "Added") {
      self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
      CircleBars(
        fill: ChapterTheme.Color.ready, bars: [(10, 2, 0), (2, 10, 0)],
        accessibilityLabel: accessibilityLabel)
    }
  }

  /// Changed item: a 22 pt ink circle with two 10 × 2 bars, 2 pt apart.
  public struct EqualsGlyph: View {
    public let accessibilityLabel: String?

    public init(accessibilityLabel: String? = "Changed") {
      self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
      CircleBars(
        fill: ChapterTheme.Color.ink, bars: [(10, 2, -2), (10, 2, 2)],
        accessibilityLabel: accessibilityLabel)
    }
  }

  /// Removed item (and the "remove" button): a 22 pt #8B2E2E circle with one 10 × 2 bar.
  public struct MinusGlyph: View {
    public let accessibilityLabel: String?

    public init(accessibilityLabel: String? = "Removed") {
      self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
      CircleBars(
        fill: ChapterTheme.Color.blocked, bars: [(10, 2, 0)],
        accessibilityLabel: accessibilityLabel)
    }
  }

  /// A progress bar: track #E8DDD0, fill ink, fully rounded. 4 pt in rows, 8 pt on Package
  /// status. Hidden from accessibility: the text next to it carries the value.
  public struct ProgressBar: View {
    public let fraction: Double
    public let height: CGFloat

    public init(fraction: Double, height: CGFloat = ChapterTheme.Metric.progressBarHeight) {
      self.fraction = fraction
      self.height = height
    }

    public var body: some View {
      let shape = RoundedRectangle(cornerRadius: height / 2)
      shape
        .fill(ChapterTheme.Color.nude)
        .overlay(alignment: .leading) {
          GeometryReader { proxy in
            shape
              .fill(ChapterTheme.Color.ink)
              .frame(width: proxy.size.width * min(max(fraction, 0), 1))
          }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
  }

  /// The 16 pt lock of the info note: stroke ink 1.5, no fill; rect (3, 7, 10, 7) radius 1.5 and
  /// the shackle `M5 7 V5 a3 3 0 0 1 6 0 v2`.
  struct LockIcon: View {
    var body: some View {
      Canvas { context, size in
        let s = size.width / 16
        var path = Path(
          roundedRect: CGRect(x: 3 * s, y: 7 * s, width: 10 * s, height: 7 * s),
          cornerRadius: 1.5 * s)
        path.move(to: CGPoint(x: 5 * s, y: 7 * s))
        path.addLine(to: CGPoint(x: 5 * s, y: 5 * s))
        path.addArc(
          center: CGPoint(x: 8 * s, y: 5 * s), radius: 3 * s, startAngle: .degrees(180),
          endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: 11 * s, y: 7 * s))
        context.stroke(path, with: .color(ChapterTheme.Color.ink), lineWidth: 1.5 * s)
      }
      .frame(width: ChapterTheme.Metric.infoNoteIcon, height: ChapterTheme.Metric.infoNoteIcon)
      .accessibilityHidden(true)
    }
  }
#endif
