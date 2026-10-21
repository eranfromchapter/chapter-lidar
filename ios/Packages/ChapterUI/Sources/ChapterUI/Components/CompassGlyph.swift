#if canImport(SwiftUI) && os(iOS)
  import CoreText
  import SwiftUI

  /// How a compass glyph is drawn. The screens map the contract's `CompassState` to it:
  /// verified → `.verified`; approximate → `.approximate`; everything else (not verified, no
  /// reading yet, reading, no compass) → `.notVerified`, which never shows an arrow.
  public enum CompassGlyphState: String, CaseIterable, Sendable {
    case verified
    case approximate
    case notVerified
  }

  /// The 32 pt compass glyph of the compass row (phone-capture §2.4.7, compass §5.1, critique
  /// R-20), drawn in a 32 × 32 view box and scaled to `size`:
  /// - ring: circle (16, 18) r 10.5, stroke 1 ink; dashed 1.6 / 1.6 when approximate;
  /// - arrow: polygon (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5), stroke 1 ink, round joins,
  ///   filled ink (verified) or surface (approximate);
  /// - "N": Inter SemiBold 7, ink, centred on x 16 with its baseline at y 5.
  /// Not verified: only the ring, dashed 1.6 / 1.6, in muted; no arrow and no "N", ever.
  ///
  /// The glyph turns by `rotation` degrees (clockwise) about its centre; pass −(heading of the
  /// direction the phone faces) so the arrow points at north. Changes animate for 0.2 s unless
  /// Reduce Motion is on. Decorative: the row's text says the state.
  public struct CompassGlyph: View {
    public let state: CompassGlyphState
    public let rotation: Double
    public let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
      state: CompassGlyphState, rotation: Double = 0,
      size: CGFloat = ChapterTheme.Metric.compassGlyph
    ) {
      self.state = state
      self.rotation = rotation
      self.size = size
    }

    public var body: some View {
      let state = state
      Canvas { context, canvasSize in
        let s = canvasSize.width / 32
        let ring = Path(
          ellipseIn: CGRect(x: 5.5 * s, y: 7.5 * s, width: 21 * s, height: 21 * s))
        context.stroke(
          ring,
          with: .color(state == .notVerified ? ChapterTheme.Color.muted : ChapterTheme.Color.ink),
          style: StrokeStyle(lineWidth: s, dash: state == .verified ? [] : [1.6 * s, 1.6 * s]))
        guard state != .notVerified else { return }

        let arrow = ViewBoxPolygon(
          points: [
            CGPoint(x: 16, y: 6.5), CGPoint(x: 20.5, y: 25.5), CGPoint(x: 16, y: 22),
            CGPoint(x: 11.5, y: 25.5),
          ],
          viewBox: CGSize(width: 32, height: 32)
        ).path(in: CGRect(origin: .zero, size: canvasSize))
        context.fill(
          arrow,
          with: .color(state == .verified ? ChapterTheme.Color.ink : ChapterTheme.Color.surface))
        context.stroke(
          arrow, with: .color(ChapterTheme.Color.ink),
          style: StrokeStyle(lineWidth: s, lineJoin: .round))
        context.fill(
          NorthLetter.path(fontSize: 7 * s, centerX: 16 * s, baseline: 5 * s),
          with: .color(ChapterTheme.Color.ink))
      }
      .frame(width: size, height: size)
      .rotationEffect(.degrees(state == .notVerified ? 0 : rotation))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: rotation)
      .accessibilityHidden(true)
    }
  }

  /// The 14 pt arrow of the live-scan compass pill (compass §5.2): polygon (16, 4) (22, 28)
  /// (16, 23) (10, 28) in a 32 view box, in surface on the dark pill. Verified: filled.
  /// Approximate: outline, stroke 2.5 view-box units, round joins. Not verified: nothing (the
  /// pill shows text only). Turns by `rotation` like `CompassGlyph`.
  public struct CompassPillGlyph: View {
    public let state: CompassGlyphState
    public let rotation: Double
    public let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
      state: CompassGlyphState, rotation: Double = 0,
      size: CGFloat = ChapterTheme.Metric.compassPillGlyph
    ) {
      self.state = state
      self.rotation = rotation
      self.size = size
    }

    public var body: some View {
      if state != .notVerified {
        let arrow = ViewBoxPolygon(
          points: [
            CGPoint(x: 16, y: 4), CGPoint(x: 22, y: 28), CGPoint(x: 16, y: 23),
            CGPoint(x: 10, y: 28),
          ],
          viewBox: CGSize(width: 32, height: 32))
        Group {
          if state == .verified {
            arrow.fill(ChapterTheme.Color.surface)
          } else {
            arrow.stroke(
              ChapterTheme.Color.surface,
              style: StrokeStyle(lineWidth: 2.5 * size / 32, lineJoin: .round))
          }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: rotation)
        .accessibilityHidden(true)
      }
    }
  }

  /// The outline of an Inter SemiBold "N", centred on its advance like SVG
  /// `text-anchor="middle"`, with its baseline at `baseline` (y down).
  enum NorthLetter {
    static func path(fontSize: CGFloat, centerX: CGFloat, baseline: CGFloat) -> Path {
      let font = CTFontCreateWithName(ChapterFonts.interSemiBold as CFString, fontSize, nil)
      var character: UniChar = 0x4E  // "N"
      var glyph: CGGlyph = 0
      guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return Path() }
      var advance = CGSize.zero
      CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
      // Glyph outlines are y up from the baseline.
      var transform = CGAffineTransform(
        a: 1, b: 0, c: 0, d: -1, tx: centerX - advance.width / 2, ty: baseline)
      guard let outline = CTFontCreatePathForGlyph(font, glyph, &transform) else { return Path() }
      return Path(outline)
    }
  }
#endif
