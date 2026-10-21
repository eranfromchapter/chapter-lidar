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

  /// The 32 pt compass glyph of the compass row (compass §5.1 with critique R-20; the host layout
  /// of phone-capture §2.4.7), drawn in a 32 × 32 view box and scaled to `size`:
  /// - ring: circle (16, 18) r 10.5, stroke 1 ink; dashed 1.6 / 1.6 when approximate (the
  ///   north-arrow v2 vector, R-20);
  /// - arrow: polygon (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5), stroke 1 ink, round joins,
  ///   filled ink (verified) or surface (approximate);
  /// - "N": Inter SemiBold 7, ink, centred on x 16 with its baseline at y 5.
  /// Not verified: only the ring, dashed 2 / 2 (compass §5.1), in muted, north up; no arrow and no
  /// "N", ever.
  ///
  /// The glyph turns by `rotation` degrees (clockwise) about its centre; pass −(heading of the
  /// direction the phone faces) so the arrow points at north. Any value works (−359 and 1 are the
  /// same turn): the glyph always turns the short way, so crossing north (−359° → −1°) turns it
  /// 2°, not 358°. Changes animate for 0.2 s unless Reduce Motion is on; when the arrow appears
  /// or goes, the glyph turns from or to north up. Decorative: the row's text says the state.
  public struct CompassGlyph: View {
    public let state: CompassGlyphState
    public let rotation: Double
    public let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The angle last drawn, unwrapped (see `CompassRotation`).
    @State private var drawnTurn: Double = 0

    public init(
      state: CompassGlyphState, rotation: Double = 0,
      size: CGFloat = ChapterTheme.Metric.compassGlyph
    ) {
      self.state = state
      self.rotation = rotation
      self.size = size
    }

    /// The ring's dash in view-box units: none when verified, 1.6 / 1.6 when approximate (R-20),
    /// 2 / 2 when not verified (compass §5.1).
    static func ringDash(_ state: CompassGlyphState) -> [CGFloat] {
      switch state {
      case .verified: []
      case .approximate: [1.6, 1.6]
      case .notVerified: [2, 2]
      }
    }

    /// `rotation`, or north up while not verified (so the dashed ring stays still).
    private var target: Double { state == .notVerified ? 0 : rotation }

    /// The angle to draw: `target`, the short way round from the angle last drawn.
    private var turn: Double { CompassRotation.continuing(from: drawnTurn, to: target) }

    public var body: some View {
      let state = state
      Canvas { context, canvasSize in
        let s = canvasSize.width / 32
        let ring = Path(
          ellipseIn: CGRect(x: 5.5 * s, y: 7.5 * s, width: 21 * s, height: 21 * s))
        context.stroke(
          ring,
          with: .color(state == .notVerified ? ChapterTheme.Color.muted : ChapterTheme.Color.ink),
          style: StrokeStyle(lineWidth: s, dash: Self.ringDash(state).map { $0 * s }))
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
      .rotationEffect(.degrees(turn))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: turn)
      .onAppear { drawnTurn = turn }
      .onChange(of: target) { _, newTarget in
        drawnTurn = CompassRotation.continuing(from: drawnTurn, to: newTarget)
      }
      .accessibilityHidden(true)
    }
  }

  /// The 14 pt arrow of the live-scan compass pill (compass §5.2): polygon (16, 4) (22, 28)
  /// (16, 23) (10, 28) in a 32 view box, in surface on the dark pill. Verified: filled.
  /// Approximate: outline, stroke 2.5 view-box units, round joins. Not verified: nothing (the
  /// pill shows text only). Turns by `rotation` like `CompassGlyph`, the short way round; when it
  /// appears it is drawn at `rotation` straight away.
  public struct CompassPillGlyph: View {
    public let state: CompassGlyphState
    public let rotation: Double
    public let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The angle last drawn, unwrapped (see `CompassRotation`).
    @State private var drawnTurn: Double = 0

    public init(
      state: CompassGlyphState, rotation: Double = 0,
      size: CGFloat = ChapterTheme.Metric.compassPillGlyph
    ) {
      self.state = state
      self.rotation = rotation
      self.size = size
    }

    private var turn: Double { CompassRotation.continuing(from: drawnTurn, to: rotation) }

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
        .rotationEffect(.degrees(turn))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: turn)
        .onAppear { drawnTurn = turn }
        .onChange(of: rotation) { _, newRotation in
          drawnTurn = CompassRotation.continuing(from: drawnTurn, to: newRotation)
        }
        .accessibilityHidden(true)
      }
    }
  }

  /// Turning a compass glyph the short way round. A glyph keeps the angle it last drew,
  /// unwrapped (it may be −361 or 725), and draws the next `rotation` as the equal angle nearest
  /// to it: SwiftUI animates the number, so going from −359 to −1 directly would spin the arrow
  /// 358° backwards through every heading instead of turning it 2°.
  enum CompassRotation {
    /// The signed turn in degrees from `current` to an angle equal to `target` (modulo 360), the
    /// short way round: in (−180, 180], so half a turn goes clockwise. Equal angles give exactly
    /// 0, also when rounding leaves a few 1e−14 (−0.3 and −360.3), so a glyph that has arrived
    /// stays put.
    static func shortestTurn(from current: Double, to target: Double) -> Double {
      guard current.isFinite, target.isFinite else { return 0 }
      var turn = (target - current).truncatingRemainder(dividingBy: 360)
      if turn > 180 {
        turn -= 360
      } else if turn <= -180 {
        turn += 360
      }
      return abs(turn) < 1e-9 ? 0 : turn
    }

    /// The angle equal to `target` (modulo 360) that is nearest to `current`: the next angle to
    /// draw. A target that is not a number keeps `current`; a `current` that is not one gives
    /// `target`.
    static func continuing(from current: Double, to target: Double) -> Double {
      guard current.isFinite else { return target.isFinite ? target : 0 }
      return current + shortestTurn(from: current, to: target)
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
