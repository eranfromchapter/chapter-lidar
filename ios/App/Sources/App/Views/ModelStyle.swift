import CoreGraphics
import SceneKit
import UIKit
import simd

/// Styles a RoomPlan parametric USDZ as a bright, clean model: walls tidied (scraps dropped,
/// jogs squared, gaps joined) and rebuilt as 10 cm thick boxes with mitred corners and real
/// holes for doors and windows, a pale grey plank floor on a thin slab with a soft shade along
/// the walls' feet, every object moved clear of the walls and of other furniture and rebuilt
/// from its box as a recognisable piece, soft low-contrast light, and a high three-quarter
/// camera with the plan's main axes diagonal, turned to show the plan as large as it can.
///
/// RoomPlan's parametric export draws walls, doors, windows, openings and objects as unit cubes
/// placed and scaled by their node transform (walls and openings have zero thickness), and the
/// floor as a flat mesh. Everything here is built from those boxes in code: no assets.
enum ModelStyle {
  /// A light warm grey behind the model.
  static let backgroundColor = UIColor(red: 0.961, green: 0.953, blue: 0.937, alpha: 1)

  /// Restyles `scene` in place and returns the camera that frames it. `aspect` is the view's
  /// width over its height (the default is a full-screen portrait phone). The model is framed
  /// for that aspect; a wider view shows it a little smaller, never cropped. The camera's angle
  /// above the floor suits the view's shape and the model's size (higher for a tall portrait
  /// view and for a single small room).
  static func apply(
    to scene: SCNScene, background: UIColor, aspect: Float = defaultAspect
  ) -> SCNNode {
    scene.background.contents = background
    let builder = Builder()
    builder.read(scene.rootNode)
    scene.rootNode.addChildNode(builder.build())
    let a = aspect.isFinite ? min(max(aspect, 0.3), 3) : defaultAspect
    let view = builder.view(elevation: builder.automaticElevation(aspect: a), aspect: a)
    addLights(to: scene.rootNode, view: view)
    let camera = makeCamera(view)
    scene.rootNode.addChildNode(camera)
    return camera
  }

  // MARK: - Kinds and palette

  enum Kind: String {
    case wall, floor, door, window, opening
    case bed, sofa, chair, table, storage, refrigerator, oven, stove, dishwasher, washerdryer
    case television, fireplace, toilet, sink, bathtub, stairs
    case unknown

    init(name: String) {
      let base = name.replacingOccurrences(of: "[0-9_]+$", with: "", options: .regularExpression)
      self = Kind(rawValue: base.lowercased()) ?? .unknown
    }

    var isInsert: Bool { self == .door || self == .window || self == .opening }
  }

  struct Tone {
    let r: CGFloat, g: CGFloat, b: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
      self.r = r
      self.g = g
      self.b = b
    }
  }

  /// Colours as drawn (sRGB albedo). Nothing is darker than about 0.4, so no part of the model
  /// pulls the eye away from the soft, low-contrast whole.
  enum Palette {
    static let wall = Tone(0.955, 0.953, 0.948)
    static let trim = Tone(0.985, 0.983, 0.978)
    static let door = Tone(0.95, 0.948, 0.942)
    static let windowFrame = Tone(0.935, 0.938, 0.945)
    static let glass = Tone(0.97, 0.98, 1.0)
    // Upholstery: a calm grey-lavender.
    static let soft = Tone(0.775, 0.775, 0.83)
    static let softLight = Tone(0.85, 0.85, 0.885)
    static let softMid = Tone(0.72, 0.72, 0.775)
    static let softDark = Tone(0.66, 0.66, 0.715)
    static let headboard = Tone(0.62, 0.62, 0.675)
    static let sheet = Tone(0.91, 0.91, 0.935)
    static let pillow = Tone(0.90, 0.90, 0.94)
    // Light warm wood.
    static let wood = Tone(0.775, 0.735, 0.665)
    static let woodLight = Tone(0.80, 0.765, 0.695)
    static let woodDark = Tone(0.62, 0.575, 0.51)
    static let woodLine = Tone(0.60, 0.56, 0.495)
    static let plinth = Tone(0.50, 0.49, 0.48)
    static let counter = Tone(0.90, 0.90, 0.905)
    // Bathroom fittings a touch cooler and greyer than the walls, so they stand apart.
    static let fixture = Tone(0.93, 0.935, 0.945)
    static let fixtureRim = Tone(0.97, 0.972, 0.976)
    static let fixtureInner = Tone(0.815, 0.82, 0.832)
    static let seat = Tone(0.88, 0.882, 0.89)
    static let appliance = Tone(0.85, 0.86, 0.88)
    static let applianceLine = Tone(0.68, 0.69, 0.715)
    static let handle = Tone(0.58, 0.585, 0.60)
    static let burner = Tone(0.47, 0.47, 0.49)
    static let dark = Tone(0.45, 0.45, 0.47)
    static let screen = Tone(0.58, 0.58, 0.61)
    static let screenGlass = Tone(0.50, 0.50, 0.54)
    static let ovenGlass = Tone(0.48, 0.48, 0.51)
    static let stone = Tone(0.86, 0.84, 0.81)
    static let neutral = Tone(0.84, 0.84, 0.85)
    static let slabEdge = Tone(0.885, 0.88, 0.875)
  }

  // MARK: - Geometry helpers

  /// An upright box: centre in world space, horizontal x axis as (x, z), half extents along the
  /// box's x, y (up) and z axes.
  struct OBox {
    var center: SIMD3<Float>
    var xAxis: SIMD2<Float>
    var half: SIMD3<Float>

    var zAxis: SIMD2<Float> { SIMD2(-xAxis.y, xAxis.x) }
    var bottom: Float { center.y - half.y }
    var top: Float { center.y + half.y }
    var center2: SIMD2<Float> { SIMD2(center.x, center.z) }

    /// Half extent of the footprint along a horizontal direction.
    func extent(along v: SIMD2<Float>) -> Float {
      abs(simd_dot(v, xAxis)) * half.x + abs(simd_dot(v, zAxis)) * half.z
    }

    func corners() -> [SIMD3<Float>] {
      var out: [SIMD3<Float>] = []
      for sx in [Float(-1), 1] {
        for sz in [Float(-1), 1] {
          let p = center2 + xAxis * (sx * half.x) + zAxis * (sz * half.z)
          out.append(SIMD3(p.x, bottom, p.y))
          out.append(SIMD3(p.x, top, p.y))
        }
      }
      return out
    }

    /// Distance from a point to the footprint rectangle (0 inside).
    func distance(to p: SIMD2<Float>) -> Float {
      let d = p - center2
      let local = SIMD2(abs(simd_dot(d, xAxis)) - half.x, abs(simd_dot(d, zAxis)) - half.z)
      return simd_length(simd_max(local, SIMD2(0, 0)))
    }
  }

  /// Yaw that turns local +x onto the horizontal direction `d` (given as (x, z)).
  static func yaw(along d: SIMD2<Float>) -> Float { atan2(-d.y, d.x) }

  static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }

  static func orientedBox(of node: SCNNode, geometry: SCNGeometry) -> OBox? {
    let (lo, hi) = geometry.boundingBox
    let l = SIMD3<Float>(lo), h = SIMD3<Float>(hi)
    let values = [l.x, l.y, l.z, h.x, h.y, h.z]
    guard values.allSatisfy({ $0.isFinite }), h.x >= l.x, h.y >= l.y, h.z >= l.z else { return nil }
    let m = node.simdWorldTransform
    let c4 = m * SIMD4<Float>((l + h) / 2, 1)
    let center = SIMD3(c4.x, c4.y, c4.z)
    let e = (h - l) / 2
    let cx = SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
    let cy = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)
    let cz = SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
    guard center.x.isFinite, center.y.isFinite, center.z.isFinite else { return nil }
    let ly = simd_length(cy)
    // Upright boxes (all of RoomPlan's) keep their yaw; anything tilted becomes its world
    // axis-aligned bounding box.
    if ly < 1e-6 || abs(cy.y) < 0.95 * ly {
      var low = SIMD3<Float>(repeating: .infinity), high = SIMD3<Float>(repeating: -.infinity)
      for sx in [Float(-1), 1] {
        for sy in [Float(-1), 1] {
          for sz in [Float(-1), 1] {
            let p = (l + h) / 2 + SIMD3(sx * e.x, sy * e.y, sz * e.z)
            let w = m * SIMD4<Float>(p, 1)
            low = simd_min(low, SIMD3(w.x, w.y, w.z))
            high = simd_max(high, SIMD3(w.x, w.y, w.z))
          }
        }
      }
      let span = high - low
      guard span.x.isFinite, span.y.isFinite, span.z.isFinite else { return nil }
      return sane(OBox(center: (low + high) / 2, xAxis: SIMD2(1, 0), half: span / 2))
    }
    var ax = SIMD2<Float>(cx.x, cx.z)
    if simd_length(ax) < 1e-6 { ax = SIMD2(cz.z, -cz.x) }
    if simd_length(ax) < 1e-6 { ax = SIMD2(1, 0) }
    ax = simd_normalize(ax)
    let half = SIMD3(simd_length(cx) * e.x, ly * e.y, simd_length(cz) * e.z)
    guard half.x.isFinite, half.y.isFinite, half.z.isFinite, ax.x.isFinite, ax.y.isFinite else {
      return nil
    }
    return sane(OBox(center: center, xAxis: ax, half: half))
  }

  /// The box, unless it is further out or bigger than any building (a corrupt transform can
  /// put a box kilometres away or make it kilometres across).
  private static func sane(_ b: OBox) -> OBox? {
    max(simd_reduce_max(simd_abs(b.center)), simd_reduce_max(b.half)) < 1000 ? b : nil
  }

  /// Whether a point lies within 10 km of the origin, and so is neither NaN nor infinite (a
  /// vertex further out is corrupt, not part of a room).
  static func usable(_ p: SIMD3<Float>) -> Bool {
    abs(p.x) < 10_000 && abs(p.y) < 10_000 && abs(p.z) < 10_000
  }

  /// The points and triangles of a geometry, or nil when it has none it can read.
  static func triangles(of geometry: SCNGeometry) -> (points: [SIMD3<Float>], tris: [SIMD3<Int>])? {
    guard let source = geometry.sources(for: .vertex).first, source.usesFloatComponents,
      source.componentsPerVector >= 3,
      source.bytesPerComponent == 4 || source.bytesPerComponent == 8
    else { return nil }
    let stride = source.dataStride, offset = source.dataOffset, count = source.vectorCount
    let size = source.bytesPerComponent
    guard count > 0, source.data.count >= (count - 1) * stride + offset + size * 3 else {
      return nil
    }
    var points: [SIMD3<Float>] = []
    points.reserveCapacity(count)
    source.data.withUnsafeBytes { raw in
      for i in 0..<count {
        let base = i * stride + offset
        if size == 4 {
          points.append(
            SIMD3(
              raw.loadUnaligned(fromByteOffset: base, as: Float.self),
              raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
              raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self)))
        } else {
          points.append(
            SIMD3(
              Float(raw.loadUnaligned(fromByteOffset: base, as: Double.self)),
              Float(raw.loadUnaligned(fromByteOffset: base + 8, as: Double.self)),
              Float(raw.loadUnaligned(fromByteOffset: base + 16, as: Double.self))))
        }
      }
    }
    var tris: [SIMD3<Int>] = []
    for element in geometry.elements {
      let bytes = element.bytesPerIndex
      guard bytes == 1 || bytes == 2 || bytes == 4 else { continue }
      let available = element.data.count / bytes
      var indices: [Int] = []
      indices.reserveCapacity(available)
      element.data.withUnsafeBytes { raw in
        for i in 0..<available {
          switch bytes {
          case 1: indices.append(Int(raw.load(fromByteOffset: i, as: UInt8.self)))
          case 2: indices.append(Int(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)))
          default: indices.append(Int(raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)))
          }
        }
      }
      func add(_ a: Int, _ b: Int, _ c: Int) {
        guard a < count, b < count, c < count, a >= 0, b >= 0, c >= 0 else { return }
        tris.append(SIMD3(a, b, c))
      }
      switch element.primitiveType {
      case .triangles:
        var t = 0
        while t + 2 < min(indices.count, element.primitiveCount * 3) {
          add(indices[t], indices[t + 1], indices[t + 2])
          t += 3
        }
      case .triangleStrip:
        var t = 0
        while t + 2 < indices.count {
          if t % 2 == 0 {
            add(indices[t], indices[t + 1], indices[t + 2])
          } else {
            add(indices[t + 1], indices[t], indices[t + 2])
          }
          t += 1
        }
      case .polygon:
        let polygons = element.primitiveCount
        guard indices.count >= polygons else { continue }
        var cursor = polygons
        for p in 0..<polygons {
          let n = indices[p]
          guard n >= 3, cursor + n <= indices.count else {
            cursor += max(n, 0)
            continue
          }
          for k in 1..<(n - 1) {
            add(indices[cursor], indices[cursor + k], indices[cursor + k + 1])
          }
          cursor += n
        }
      default:
        continue
      }
    }
    guard !tris.isEmpty else { return nil }
    return (points, tris)
  }

  /// A copy of `geometry` as separate triangles, each with its own face normal; with `uv`, also
  /// texture coordinates from each vertex's position; with `upward`, every face turned to face
  /// up in world space (`transform` is the node's world transform).
  static func flatShaded(
    _ geometry: SCNGeometry, transform: simd_float4x4 = matrix_identity_float4x4,
    upward: Bool = false, uv: ((SIMD3<Float>) -> CGPoint)? = nil
  ) -> SCNGeometry? {
    guard let (points, tris) = triangles(of: geometry) else { return nil }
    var positions: [SCNVector3] = [], normals: [SCNVector3] = [], coords: [CGPoint] = []
    positions.reserveCapacity(tris.count * 3)
    for t in tris {
      var a = points[t.x], b = points[t.y], c = points[t.z]
      guard usable(a), usable(b), usable(c) else { continue }
      if upward {
        let wa = transform * SIMD4(a, 1), wb = transform * SIMD4(b, 1), wc = transform * SIMD4(c, 1)
        // The world face normal's y.
        let up = (wb.z - wa.z) * (wc.x - wa.x) - (wb.x - wa.x) * (wc.z - wa.z)
        if up < 0 { swap(&b, &c) }
      }
      var n = simd_cross(b - a, c - a)
      let length = simd_length(n)
      guard length > 1e-12, length.isFinite else { continue }
      n /= length
      for p in [a, b, c] {
        positions.append(SCNVector3(p))
        normals.append(SCNVector3(n))
        if let uv {
          let w = transform * SIMD4(p, 1)
          coords.append(uv(SIMD3(w.x, w.y, w.z)))
        }
      }
    }
    guard !positions.isEmpty else { return nil }
    var sources = [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)]
    if uv != nil { sources.append(SCNGeometrySource(textureCoordinates: coords)) }
    let element = SCNGeometryElement(
      indices: (0..<Int32(positions.count)).map { $0 }, primitiveType: .triangles)
    return SCNGeometry(sources: sources, elements: [element])
  }

  /// Flat-shaded triangles collected one by one, each wound to face its given normal.
  struct Mesh {
    var positions: [SCNVector3] = []
    var normals: [SCNVector3] = []

    mutating func triangle(
      _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, normal: SIMD3<Float>
    ) {
      let n = simd_cross(b - a, c - a)
      guard simd_length(n) > 1e-10, n.x.isFinite, n.y.isFinite, n.z.isFinite else { return }
      let ordered = simd_dot(n, normal) >= 0 ? [a, b, c] : [a, c, b]
      for p in ordered {
        positions.append(SCNVector3(p))
        normals.append(SCNVector3(normal))
      }
    }

    mutating func quad(
      _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
      normal: SIMD3<Float>
    ) {
      triangle(a, b, c, normal: normal)
      triangle(a, c, d, normal: normal)
    }

    func geometry(_ material: SCNMaterial) -> SCNGeometry? {
      guard !positions.isEmpty else { return nil }
      let element = SCNGeometryElement(
        indices: (0..<Int32(positions.count)).map { $0 }, primitiveType: .triangles)
      let g = SCNGeometry(
        sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
        elements: [element])
      g.materials = [material]
      return g
    }
  }

  /// Counter-clockwise (in x, z) convex hull of a set of points.
  static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
    let sorted = points.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
    guard sorted.count >= 3 else { return sorted }
    /// Whether `p` makes no left turn after the chain's last edge.
    func noLeftTurn(_ chain: [SIMD2<Float>], _ p: SIMD2<Float>) -> Bool {
      let n = chain.count
      return cross(chain[n - 1] - chain[n - 2], p - chain[n - 2]) <= 1e-9
    }
    var lower: [SIMD2<Float>] = [], upper: [SIMD2<Float>] = []
    for p in sorted {
      while lower.count >= 2, noLeftTurn(lower, p) { lower.removeLast() }
      lower.append(p)
    }
    for p in sorted.reversed() {
      while upper.count >= 2, noLeftTurn(upper, p) { upper.removeLast() }
      upper.append(p)
    }
    return Array(lower.dropLast() + upper.dropLast())
  }

  // MARK: - Floor texture

  /// Metres covered by one tile of the floor texture.
  static let plankTile: Float = 2.4

  /// The floor's base tone (also its colour when the texture can't be drawn).
  static let floorTone = Tone(0.81, 0.81, 0.815)

  /// A matte, neutral pale grey plank floor, drawn once: 22 rows of 11 cm planks, 60 cm to
  /// 1.2 m long and staggered, each a few percent lighter or darker than the next, with thin
  /// darker seams and a little faint grain. It tiles seamlessly.
  static let plankTexture: CGImage? = {
    let size = 1024
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    var random = SeededRandom(seed: 0x5EED_F100)
    let rows = 22
    let side = CGFloat(size)
    let rowHeight = side / CGFloat(rows)
    let perMetre = side / CGFloat(plankTile)
    let base = floorTone
    let seam = (r: CGFloat(0.56), g: CGFloat(0.56), b: CGFloat(0.58))
    ctx.setFillColor(red: base.r, green: base.g, blue: base.b, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    for row in 0..<rows {
      let y = CGFloat(row) * rowHeight
      // Plank lengths that add up to the tile's width exactly, so each row wraps seamlessly.
      var lengths: [CGFloat] = []
      var used: CGFloat = 0
      while side - used > 1.2 * perMetre {
        let l = (0.6 + 0.6 * CGFloat(random.next())) * perMetre
        lengths.append(l)
        used += l
      }
      let rest = side - used
      if rest < 0.6 * perMetre, !lengths.isEmpty {
        lengths[lengths.count - 1] += rest
      } else {
        lengths.append(rest)
      }
      var x = CGFloat(random.next()) * side
      for length in lengths {
        let tone = CGFloat(random.next() * 0.036 - 0.018)
        let cool = CGFloat(random.next() * 0.006 - 0.003)
        var grain: [(y: CGFloat, x0: CGFloat, x1: CGFloat, light: Bool)] = []
        for _ in 0..<(1 + Int(random.next() * 3)) {
          let gy = 4 + CGFloat(random.next()) * (rowHeight - 8)
          let x0 = CGFloat(random.next()) * 0.35, x1 = 0.55 + CGFloat(random.next()) * 0.45
          grain.append((gy, x0, x1, random.next() < 0.45))
        }
        // Drawn twice, a tile apart, so a plank running off the right edge comes back in on
        // the left.
        for shift in [CGFloat(0), -side] {
          let px = x + shift
          ctx.setFillColor(
            red: base.r + tone, green: base.g + tone, blue: base.b + tone + cool, alpha: 1)
          ctx.fill(CGRect(x: px, y: y, width: length, height: rowHeight))
          for g in grain {
            if g.light {
              ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.045)
            } else {
              ctx.setFillColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 0.045)
            }
            ctx.fill(
              CGRect(x: px + g.x0 * length, y: y + g.y, width: (g.x1 - g.x0) * length, height: 2))
          }
          ctx.setFillColor(red: seam.r, green: seam.g, blue: seam.b, alpha: 0.45)
          ctx.fill(CGRect(x: px, y: y, width: 3, height: rowHeight))
        }
        x += length
        if x >= side { x -= side }
      }
      ctx.setFillColor(red: seam.r, green: seam.g, blue: seam.b, alpha: 0.4)
      ctx.fill(CGRect(x: 0, y: y, width: side, height: 3))
    }
    return ctx.makeImage()
  }()

  struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Double(state >> 11) / Double(UInt64(1) << 53)
    }
  }

  /// A soft contact shadow: black, opaque in the middle and fading smoothly to nothing at the
  /// edges. It is stretched as nine slices, so the fade keeps its width in metres.
  static let shadowTexture: CGImage? = {
    let size = 64
    func ramp(_ t: Float) -> Float {
      let s = min(max(min(t, 1 - t) * 2, 0), 1)
      return s * s * (3 - 2 * s)
    }
    return shade(width: size, height: size) { x, y in
      ramp((Float(x) + 0.5) / Float(size)) * ramp((Float(y) + 0.5) / Float(size))
    }
  }()

  /// The soft darkening along the foot of a wall: black, opaque at u = 0 and fading to nothing
  /// at u = 1.
  static let edgeShadeTexture: CGImage? = {
    let width = 64
    return shade(width: width, height: 4) { x, _ in
      let u = (Float(x) + 0.5) / Float(width)
      return (1 - u) * (1 - u) * (1 - u * 0.5)
    }
  }()

  /// A black image whose opacity at each pixel (x, y) is `alpha(x, y)`, from 0 to 1.
  static func shade(width: Int, height: Int, alpha: (Int, Int) -> Float) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        pixels[(y * width + x) * 4 + 3] = UInt8(min(max(alpha(x, y) * 255, 0), 255).rounded())
      }
    }
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let provider = CGDataProvider(data: Data(pixels) as CFData)
    else { return nil }
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
      intent: .defaultIntent)
  }

  // MARK: - Parts

  /// Boxes and cylinders in metres, in a frame whose origin is the bottom centre of an object,
  /// +y up and +z its front.
  final class Parts {
    let node = SCNNode()

    func box(
      _ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ z0: Float, _ z1: Float,
      _ material: SCNMaterial, chamfer: Float = 0, top: SCNMaterial? = nil
    ) {
      let w = x1 - x0, h = y1 - y0, l = z1 - z0
      guard w.isFinite, h.isFinite, l.isFinite, w > 0.002, h > 0.002, l > 0.002 else { return }
      let c = max(0, min(chamfer, min(w, min(h, l)) * 0.48))
      let geometry = SCNBox(
        width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: CGFloat(c))
      if c > 0 { geometry.chamferSegmentCount = 4 }
      // SCNBox's faces in order: front, right, back, left, top, bottom.
      geometry.materials =
        top.map { [material, material, material, material, $0, material] } ?? [material]
      let child = SCNNode(geometry: geometry)
      child.simdPosition = SIMD3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
      node.addChildNode(child)
    }

    /// An upright cylinder.
    func cylinder(
      x: Float, z: Float, y0: Float, y1: Float, radius: Float, _ material: SCNMaterial
    ) {
      let h = y1 - y0
      guard h.isFinite, radius.isFinite, h > 0.002, radius > 0.002 else { return }
      let geometry = SCNCylinder(radius: CGFloat(radius), height: CGFloat(h))
      geometry.radialSegmentCount = 24
      geometry.materials = [material]
      let child = SCNNode(geometry: geometry)
      child.simdPosition = SIMD3(x, (y0 + y1) / 2, z)
      node.addChildNode(child)
    }

    /// An upright oval: a cylinder `rx` across and `rz` front to back.
    func oval(
      x: Float, z: Float, y0: Float, y1: Float, rx: Float, rz: Float, _ material: SCNMaterial
    ) {
      let h = y1 - y0
      guard h.isFinite, rx.isFinite, rz.isFinite, h > 0.002, rx > 0.004, rz > 0.004 else { return }
      let geometry = SCNCylinder(radius: CGFloat(rx), height: CGFloat(h))
      geometry.radialSegmentCount = 32
      geometry.materials = [material]
      let child = SCNNode(geometry: geometry)
      child.simdPosition = SIMD3(x, (y0 + y1) / 2, z)
      child.simdScale = SIMD3(1, 1, rz / rx)
      node.addChildNode(child)
    }

    /// An upright oval ring (a toilet seat), `width` wide in plan.
    func ovalRing(
      x: Float, z: Float, y0: Float, y1: Float, rx: Float, rz: Float, width: Float,
      _ material: SCNMaterial
    ) {
      let h = y1 - y0
      guard h.isFinite, rx.isFinite, rz.isFinite, width.isFinite, h > 0.002, rx > width + 0.004,
        rz > width + 0.004
      else { return }
      let geometry = SCNTube(
        innerRadius: CGFloat(rx - width), outerRadius: CGFloat(rx), height: CGFloat(h))
      geometry.radialSegmentCount = 32
      geometry.materials = [material]
      let child = SCNNode(geometry: geometry)
      child.simdPosition = SIMD3(x, (y0 + y1) / 2, z)
      child.simdScale = SIMD3(1, 1, rz / rx)
      node.addChildNode(child)
    }

    /// A cylinder lying along z (a round door or knob on a front).
    func disc(x: Float, y: Float, z0: Float, z1: Float, radius: Float, _ material: SCNMaterial) {
      let h = z1 - z0
      guard h.isFinite, radius.isFinite, h > 0.001, radius > 0.002 else { return }
      let geometry = SCNCylinder(radius: CGFloat(radius), height: CGFloat(h))
      geometry.radialSegmentCount = 32
      geometry.materials = [material]
      let child = SCNNode(geometry: geometry)
      child.simdPosition = SIMD3(x, y, (z0 + z1) / 2)
      child.simdOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
      node.addChildNode(child)
    }
  }

  // MARK: - Builder

  /// Where the camera looks from and at, and the light that goes with it.
  struct View {
    var target: SIMD3<Float>
    var direction: SIMD3<Float>
    var distance: Float
    var azimuth: Float
    /// Azimuth of the light that falls square on one family of walls.
    var keyAzimuth: Float
    /// Vertical field of view, in degrees.
    var fieldOfView: Float
    var radius: Float
  }

  static let wallThickness: Float = 0.10
  /// Depth of the floor slab whose edge shows where the floor has no wall.
  static let slabDepth: Float = 0.07
  /// The camera's angle above the floor, in degrees, for a landscape view of a large plan.
  static let defaultElevation: Float = 58
  /// Width over height of a full-screen portrait phone.
  static let defaultAspect: Float = 0.46
  /// Vertical field of view, in degrees.
  static let fieldOfView: Float = 36
  /// Share of the frame's width left empty at each side, and of its height at top and bottom.
  static let sideMargin: Float = 0.055
  static let endMargin: Float = 0.04

  final class Builder {
    struct Item {
      let node: SCNNode
      let kind: Kind
      /// The object's box, moved out of walls and apart from other furniture before it is built.
      var box: OBox
      /// A near-duplicate of a larger item of the same kind, left out.
      var hidden = false
    }
    /// A door, window or opening in wall coordinates: u along the wall from its middle, v up
    /// from its foot.
    struct Hole {
      var u0: Float, u1: Float, v0: Float, v1: Float
      let kind: Kind
    }
    /// A wall as a centre line on the floor plan, from `a` to `b`.
    struct Segment {
      var a: SIMD2<Float>
      var b: SIMD2<Float>
      var bottom: Float
      var top: Float

      var length: Float { simd_length(b - a) }
      var dir: SIMD2<Float> {
        let l = length
        return l > 1e-6 ? (b - a) / l : SIMD2(1, 0)
      }
      var normal: SIMD2<Float> { SIMD2(-dir.y, dir.x) }
      var center: SIMD2<Float> { (a + b) / 2 }
      func end(_ i: Int) -> SIMD2<Float> { i == 0 ? a : b }
      mutating func setEnd(_ i: Int, _ p: SIMD2<Float>) { if i == 0 { a = p } else { b = p } }
    }

    var walls: [Item] = []
    var inserts: [Item] = []
    var objects: [Item] = []
    var floors: [(SCNNode, SCNGeometry)] = []
    var others: [(SCNNode, SCNGeometry)] = []
    var segments: [Segment] = []
    var cuts: [[Hole]] = []
    var floorTriangles: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
    /// The floor's outline, as segments on the plan.
    var floorEdges: [(SIMD2<Float>, SIMD2<Float>)] = []
    var fitPoints: [SIMD3<Float>] = []
    var dominant: Float = 0
    var floorY: Float = 0
    /// Contact shadows by strength: positions and texture coordinates of their triangles.
    var shadows: [Float: (positions: [SCNVector3], coords: [CGPoint])] = [:]
    struct FloorGrid {
      let origin: SIMD2<Float>
      let cell: Float
      let columns: Int
      let rows: Int
      let cells: [[Int]]
    }
    /// The floor's triangles bucketed by plan cell, for quick point tests.
    var floorGrid: FloorGrid?
    private var materials: [String: SCNMaterial] = [:]

    func material(_ tone: Tone, doubleSided: Bool = false) -> SCNMaterial {
      let key = String(format: "%.3f %.3f %.3f %d", tone.r, tone.g, tone.b, doubleSided ? 1 : 0)
      if let m = materials[key] { return m }
      let m = SCNMaterial()
      m.lightingModel = .lambert
      m.diffuse.contents = UIColor(red: tone.r, green: tone.g, blue: tone.b, alpha: 1)
      m.isDoubleSided = doubleSided
      materials[key] = m
      return m
    }

    /// Window glass: near white, glowing like daylight through it.
    func glass() -> SCNMaterial {
      if let m = materials["glass"] { return m }
      let m = SCNMaterial()
      m.lightingModel = .constant
      let t = Palette.glass
      m.diffuse.contents = UIColor(red: t.r, green: t.g, blue: t.b, alpha: 1)
      m.isDoubleSided = true
      materials["glass"] = m
      return m
    }

    func read(_ root: SCNNode) {
      var found: [(SCNNode, SCNGeometry)] = []
      root.enumerateHierarchy { node, _ in
        if let g = node.geometry { found.append((node, g)) }
      }
      for (node, geometry) in found {
        let kind = Kind(name: node.name ?? "")
        if kind == .floor {
          floors.append((node, geometry))
          continue
        }
        guard kind != .unknown, let box = ModelStyle.orientedBox(of: node, geometry: geometry)
        else {
          others.append((node, geometry))
          continue
        }
        let item = Item(node: node, kind: kind, box: box)
        if kind == .wall {
          walls.append(item)
        } else if kind.isInsert {
          inserts.append(item)
        } else {
          objects.append(item)
        }
      }
    }

    func build() -> SCNNode {
      let content = SCNNode()
      content.name = "ModelStyle"
      dominant = dominantDirection()
      floorY = lowestFloor()
      segments = prepareSegments()

      let wallGroup = SCNNode()
      wallGroup.name = "Walls"
      var holes: [[Hole]] = Array(repeating: [], count: segments.count)
      var attached = Set<Int>()
      for (i, insert) in inserts.enumerated() {
        guard let (s, hole) = host(of: insert.box, kind: insert.kind) else { continue }
        holes[s].append(hole)
        attached.insert(i)
      }
      cuts = segments.indices.map { clampedCuts(holes[$0], segments[$0]) }
      settleObjects()
      for (s, segment) in segments.enumerated() {
        if let node = buildWall(segment, cuts: cuts[s]) { wallGroup.addChildNode(node) }
      }
      for joint in jointPieces() { wallGroup.addChildNode(joint) }
      for wall in walls { wall.node.geometry = nil }
      for (i, insert) in inserts.enumerated() {
        insert.node.geometry = nil
        guard !attached.contains(i) else { continue }
        // An insert with no wall: its frame alone.
        let b = insert.box
        let frame = Parts()
        let hole = Hole(u0: -b.half.x, u1: b.half.x, v0: 0, v1: 2 * b.half.y, kind: insert.kind)
        addInsert(hole, to: frame)
        frame.node.simdPosition = SIMD3(b.center.x, b.bottom, b.center.z)
        frame.node.simdOrientation = simd_quatf(
          angle: ModelStyle.yaw(along: b.xAxis), axis: SIMD3(0, 1, 0))
        wallGroup.addChildNode(frame.node)
        fitPoints += b.corners()
      }
      content.addChildNode(flattened(wallGroup, castsShadow: false))

      buildFloors(into: content)
      if let shade = wallShade() { content.addChildNode(shade) }

      let objectGroup = SCNNode()
      objectGroup.name = "Objects"
      for item in objects {
        item.node.geometry = nil
        guard !item.hidden else { continue }
        if let built = buildObject(item) { objectGroup.addChildNode(built) }
        fitPoints += item.box.corners()
      }
      content.addChildNode(flattened(objectGroup, castsShadow: false))
      content.addChildNode(shadowNodes())

      let plain = material(Palette.neutral, doubleSided: true)
      for (node, geometry) in others {
        let (lo, hi) = geometry.boundingBox
        let m = node.simdWorldTransform
        let corners = [SIMD3<Float>(lo), SIMD3<Float>(hi)].map { c -> SIMD3<Float> in
          let w = m * SIMD4(c, 1)
          return SIMD3(w.x, w.y, w.z)
        }
        // Anything kilometres away or across (a corrupt transform) is left out.
        guard corners.allSatisfy(ModelStyle.usable) else {
          node.geometry = nil
          continue
        }
        let styled = ModelStyle.flatShaded(geometry) ?? geometry
        styled.materials = [plain]
        node.geometry = styled
        fitPoints += corners
      }
      return content
    }

    /// Each piece (a wall, a bed) as one mesh, so the phone draws a few dozen meshes instead of
    /// hundreds of boxes. (Flattening the whole group at once loses the pieces' own transforms.)
    private func flattened(_ group: SCNNode, castsShadow: Bool) -> SCNNode {
      let out = SCNNode()
      out.name = group.name
      for piece in group.childNodes {
        let flat: SCNNode
        if piece.childNodes.isEmpty {
          guard piece.geometry != nil else { continue }
          flat = piece
          piece.removeFromParentNode()
        } else {
          flat = piece.flattenedClone()
          flat.simdTransform = piece.simdTransform
        }
        flat.castsShadow = castsShadow
        out.addChildNode(flat)
      }
      return out
    }

    /// The walls' main direction (radians, modulo 90 degrees), weighted by wall length.
    private func dominantDirection() -> Float {
      var c: Float = 0, s: Float = 0
      let sources = walls.isEmpty ? objects : walls
      for item in sources {
        let a = atan2(item.box.xAxis.y, item.box.xAxis.x)
        let weight = max(item.box.half.x, 0.01)
        c += weight * cos(4 * a)
        s += weight * sin(4 * a)
      }
      guard abs(c) + abs(s) > 1e-6 else { return 0 }
      return atan2(s, c) / 4
    }

    private func lowestFloor() -> Float {
      var y = Float.infinity
      for (node, geometry) in floors {
        let (lo, hi) = geometry.boundingBox
        let m = node.simdWorldTransform
        for p in [SIMD3<Float>(lo), SIMD3<Float>(hi)] {
          let w = m * SIMD4(p, 1)
          if abs(w.y) < 10_000 { y = min(y, w.y) }
        }
      }
      if !y.isFinite { y = walls.map { $0.box.bottom }.min() ?? .infinity }
      if !y.isFinite { y = objects.map { $0.box.bottom }.min() ?? 0 }
      return y
    }

    // MARK: Floor

    private func buildFloors(into content: SCNNode) {
      let floorMaterial = SCNMaterial()
      floorMaterial.lightingModel = .lambert
      if let texture = ModelStyle.plankTexture {
        floorMaterial.diffuse.contents = texture
        floorMaterial.diffuse.wrapS = .repeat
        floorMaterial.diffuse.wrapT = .repeat
        floorMaterial.diffuse.mipFilter = .linear
        floorMaterial.diffuse.minificationFilter = .linear
        floorMaterial.diffuse.magnificationFilter = .linear
        floorMaterial.diffuse.maxAnisotropy = 8
      } else {
        let t = ModelStyle.floorTone
        floorMaterial.diffuse.contents = UIColor(red: t.r, green: t.g, blue: t.b, alpha: 1)
      }
      floorMaterial.isDoubleSided = true
      let along = SIMD2<Float>(cos(dominant), sin(dominant))
      let across = SIMD2<Float>(-along.y, along.x)
      let tile = ModelStyle.plankTile
      // Texture coordinates from the world position, in tiles, the planks along the main walls.
      func plankUV(_ w: SIMD3<Float>) -> CGPoint {
        let p = SIMD2(w.x, w.z) / tile
        return CGPoint(x: CGFloat(simd_dot(p, along)), y: CGFloat(simd_dot(p, across)))
      }
      var edges = Mesh()
      for (node, geometry) in floors {
        let m = node.simdWorldTransform
        let triangles = ModelStyle.triangles(of: geometry)
        if let styled = ModelStyle.flatShaded(geometry, transform: m, upward: true, uv: plankUV) {
          styled.materials = [floorMaterial]
          node.geometry = styled
        } else {
          geometry.materials = [floorMaterial]
        }
        node.castsShadow = false
        guard let (points, tris) = triangles else { continue }
        let world = points.map { p -> SIMD3<Float> in
          let w = m * SIMD4(p, 1)
          return SIMD3(w.x, w.y, w.z)
        }
        for p in world where ModelStyle.usable(p) { fitPoints.append(p) }
        addSlabEdges(world, tris, to: &edges)
      }
      if let g = edges.geometry(material(Palette.slabEdge)) {
        let node = SCNNode(geometry: g)
        node.name = "FloorEdge"
        node.castsShadow = false
        content.addChildNode(node)
      }
    }

    /// The floor's outline turned down into a thin slab edge, so floor with no wall over it ends
    /// in a clean white edge instead of a hairline.
    private func addSlabEdges(_ world: [SIMD3<Float>], _ tris: [SIMD3<Int>], to mesh: inout Mesh) {
      struct Key: Hashable { let x: Int32, z: Int32 }
      func key(_ p: SIMD3<Float>) -> Key? {
        let x = (p.x * 500).rounded(), z = (p.z * 500).rounded()
        guard x.isFinite, z.isFinite, abs(x) < 1e9, abs(z) < 1e9 else { return nil }
        return Key(x: Int32(x), z: Int32(z))
      }
      struct Edge: Hashable { let a: Key, b: Key }
      var count: [Edge: Int] = [:]
      var first: [Edge: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [:]
      var order: [Edge] = []
      for t in tris {
        let v = [world[t.x], world[t.y], world[t.z]]
        if floorTriangles.count < 20000, v.allSatisfy(ModelStyle.usable) {
          floorTriangles.append(
            (SIMD2(v[0].x, v[0].z), SIMD2(v[1].x, v[1].z), SIMD2(v[2].x, v[2].z)))
        }
        for k in 0..<3 {
          let p = v[k], q = v[(k + 1) % 3], r = v[(k + 2) % 3]
          guard let kp = key(p), let kq = key(q), kp != kq else { continue }
          let e = (kp.x, kp.z) < (kq.x, kq.z) ? Edge(a: kp, b: kq) : Edge(a: kq, b: kp)
          if count[e] == nil {
            order.append(e)
            first[e] = (p, q, r)
          }
          count[e, default: 0] += 1
        }
      }
      let depth = ModelStyle.slabDepth
      for e in order where count[e] == 1 {
        guard let (p, q, inside) = first[e], ModelStyle.usable(p), ModelStyle.usable(q) else {
          continue
        }
        let d = SIMD2(q.x - p.x, q.z - p.z)
        guard simd_length(d) > 1e-4 else { continue }
        var n = simd_normalize(SIMD2(-d.y, d.x))
        if simd_dot(n, SIMD2(inside.x - p.x, inside.z - p.z)) > 0 { n = -n }
        let low = min(p.y, q.y) - depth
        mesh.quad(p, q, SIMD3(q.x, low, q.z), SIMD3(p.x, low, p.z), normal: SIMD3(n.x, 0, n.y))
        floorEdges.append((SIMD2(p.x, p.z), SIMD2(q.x, q.z)))
        fitPoints.append(SIMD3(p.x, low, p.z))
      }
    }

    // MARK: Walls

    /// The walls as centre lines, tidied so their tops read as clean lines: endpoints that
    /// nearly meet snapped together; stray scraps and walls lying on top of longer ones
    /// dropped; skewed short connectors between parallel walls squared up; a tiny chamfer
    /// between two walls replaced by a plain corner; slight kinks straightened; and a free end
    /// that stops short of another wall, or runs just past it, joined to that wall.
    private func prepareSegments() -> [Segment] {
      var segs: [Segment] = walls.compactMap { w in
        let b = w.box
        guard b.half.x > 0.01, b.half.y > 0.01 else { return nil }
        let start = b.center2 - b.xAxis * b.half.x, end = b.center2 + b.xAxis * b.half.x
        return Segment(a: start, b: end, bottom: b.bottom, top: b.top)
      }
      snap(&segs)
      segs = segs.filter { $0.length > 0.03 }
      dropScraps(&segs)
      squareConnectors(&segs)
      dropChamfers(&segs)
      straightenKinks(&segs)
      joinFreeEnds(&segs)
      snap(&segs)
      return segs.filter { $0.length > 0.03 && $0.top - $0.bottom > 0.02 }
    }

    private static func distance(_ p: SIMD2<Float>, to s: Segment) -> Float {
      let d = s.b - s.a
      let l2 = simd_length_squared(d)
      guard l2 > 1e-10 else { return simd_distance(p, s.a) }
      let t = min(max(simd_dot(p - s.a, d) / l2, 0), 1)
      return simd_distance(p, s.a + d * t)
    }

    /// Whether the line from `p` to `q` crosses some wall other than `except` away from its
    /// two ends (a join must not run through a wall to reach its target).
    private static func cutsThrough(
      _ p: SIMD2<Float>, _ q: SIMD2<Float>, _ segs: [Segment], except: Int
    ) -> Bool {
      let v = q - p
      for (j, s) in segs.enumerated() where j != except {
        let w = s.b - s.a
        let den = ModelStyle.cross(v, w)
        guard abs(den) > 1e-6 else { continue }
        let t = ModelStyle.cross(s.a - p, w) / den
        let r = ModelStyle.cross(s.a - p, v) / den
        if t > 0.05, t < 0.95, r > 0.02, r < 0.98 { return true }
      }
      return false
    }

    /// The direction along a segment pointing away from one of its ends.
    private static func away(_ s: Segment, _ end: Int) -> SIMD2<Float> { end == 0 ? s.dir : -s.dir }

    /// Angle of a direction from the nearest of the plan's main axes, in radians (0 to pi/4).
    private func offAxis(_ d: SIMD2<Float>) -> Float {
      var a = atan2(d.y, d.x) - dominant
      a = a - (a / (.pi / 2)).rounded() * (.pi / 2)
      return abs(a)
    }

    /// Drops walls that only add noise: one lying along a longer wall (both its ends within
    /// 6 cm of it); a short wall with a free end that leaves a corner within 35 degrees of
    /// another wall there (a duplicate spur); and a short isolated scrap at an odd angle that
    /// touches another wall.
    private func dropScraps(_ segs: inout [Segment]) {
      let groups = endpointGroups(segs, within: 0.02)
      var drop = Set<Int>()
      for i in segs.indices {
        let s = segs[i]
        for (j, o) in segs.enumerated() where j != i && !drop.contains(j) {
          guard o.length > s.length || (o.length == s.length && j < i) else { continue }
          if abs(simd_dot(s.dir, o.dir)) > 0.994, Builder.distance(s.a, to: o) < 0.06,
            Builder.distance(s.b, to: o) < 0.06
          {
            drop.insert(i)
            break
          }
        }
        guard !drop.contains(i), s.length < 0.6 else { continue }
        let free = [groups[i * 2].count == 1, groups[i * 2 + 1].count == 1]
        if free[0] && free[1] {
          guard offAxis(s.dir) > 10 * .pi / 180 else { continue }
          let touches = segs.indices.contains { j in
            j != i && !drop.contains(j)
              && (Builder.distance(s.a, to: segs[j]) < 0.12
                || Builder.distance(s.b, to: segs[j]) < 0.12)
          }
          if touches { drop.insert(i) }
          continue
        }
        guard free[0] != free[1] else { continue }
        let joined = free[0] ? 1 : 0
        let out = Builder.away(s, joined)
        for e in groups[i * 2 + joined] where e / 2 != i && !drop.contains(e / 2) {
          let o = segs[e / 2]
          if simd_dot(out, Builder.away(o, e % 2)) > cos(35 * .pi / 180), o.length > 0.15 {
            drop.insert(i)
            break
          }
        }
      }
      guard !drop.isEmpty else { return }
      segs = segs.enumerated().filter { !drop.contains($0.offset) }.map { $0.element }
    }

    /// The other wall joined at an endpoint, when exactly one is.
    private func partner(_ groups: [[Int]], _ endpoint: Int) -> Int? {
      let g = groups[endpoint]
      guard g.count == 2 else { return nil }
      return g.first { $0 / 2 != endpoint / 2 }
    }

    /// A short wall joining two parallel walls at a skew (a jog drawn as a V) turned square to
    /// them, its two corners slid along the walls to meet halfway.
    private func squareConnectors(_ segs: inout [Segment]) {
      for c in segs.indices where segs[c].length < 0.8 {
        let groups = endpointGroups(segs, within: 0.02)
        guard let ea = partner(groups, c * 2), let eb = partner(groups, c * 2 + 1), ea / 2 != eb / 2
        else { continue }
        let A = ea / 2, B = eb / 2
        let d = segs[A].dir
        guard abs(simd_dot(d, segs[B].dir)) > cos(4 * .pi / 180) else { continue }
        let skew = abs(simd_dot(segs[c].dir, d))
        guard skew > sin(4 * .pi / 180), skew < cos(45 * .pi / 180) else { continue }
        let n = SIMD2(-d.y, d.x)
        guard abs(simd_dot(segs[B].center - segs[A].center, n)) > 0.05 else { continue }
        let pa = simd_dot(segs[c].a, d), pb = simd_dot(segs[c].b, d)
        let m = (pa + pb) / 2
        let newA = segs[c].a + d * (m - pa), newB = segs[c].b + d * (m - pb)
        var a = segs[A], b = segs[B]
        a.setEnd(ea % 2, newA)
        b.setEnd(eb % 2, newB)
        guard a.length > 0.1, b.length > 0.1 else { continue }
        segs[A] = a
        segs[B] = b
        segs[c].a = newA
        segs[c].b = newB
      }
    }

    /// A short wall cutting across the corner between two walls replaced by the plain corner.
    private func dropChamfers(_ segs: inout [Segment]) {
      var drop = Set<Int>()
      for c in segs.indices where segs[c].length < 0.35 {
        let groups = endpointGroups(segs, within: 0.02)
        guard let ea = partner(groups, c * 2), let eb = partner(groups, c * 2 + 1),
          ea / 2 != eb / 2, !drop.contains(ea / 2), !drop.contains(eb / 2)
        else { continue }
        let A = ea / 2, B = eb / 2
        guard segs[A].length > 2 * segs[c].length, segs[B].length > 2 * segs[c].length else {
          continue
        }
        let da = segs[A].dir, db = segs[B].dir
        let den = ModelStyle.cross(da, db)
        guard abs(den) > sin(20 * .pi / 180) else { continue }
        let pa = segs[A].end(ea % 2), pb = segs[B].end(eb % 2)
        let s = ModelStyle.cross(pb - pa, db) / den
        let corner = pa + da * s
        guard simd_distance(corner, segs[c].center) < 0.4 else { continue }
        var a = segs[A], b = segs[B]
        a.setEnd(ea % 2, corner)
        b.setEnd(eb % 2, corner)
        guard a.length > 0.1, b.length > 0.1 else { continue }
        segs[A] = a
        segs[B] = b
        drop.insert(c)
      }
      guard !drop.isEmpty else { return }
      segs = segs.enumerated().filter { !drop.contains($0.offset) }.map { $0.element }
    }

    /// Where two walls meet almost in line (within 4 degrees), the joint moved onto the line
    /// between their far ends, so the run reads as one straight wall.
    private func straightenKinks(_ segs: inout [Segment]) {
      let groups = endpointGroups(segs, within: 0.02)
      var done = Set<Int>()
      for i in 0..<groups.count where !done.contains(i) {
        let g = groups[i]
        for e in g { done.insert(e) }
        guard g.count >= 2 else { continue }
        var pair: (Int, Int)?
        for x in 0..<g.count {
          for y in (x + 1)..<g.count where g[x] / 2 != g[y] / 2 {
            let u = Builder.away(segs[g[x] / 2], g[x] % 2)
            let v = Builder.away(segs[g[y] / 2], g[y] % 2)
            if simd_dot(u, v) < -cos(4 * .pi / 180) { pair = (g[x], g[y]) }
          }
        }
        guard let (ex, ey) = pair else { continue }
        let p = segs[ex / 2].end(1 - ex % 2), q = segs[ey / 2].end(1 - ey % 2)
        let joint = segs[ex / 2].end(ex % 2)
        let line = q - p
        let l2 = simd_length_squared(line)
        guard l2 > 1e-6 else { continue }
        let onLine = p + line * (simd_dot(joint - p, line) / l2)
        guard simd_distance(onLine, joint) < 0.06 else { continue }
        for e in g { segs[e / 2].setEnd(e % 2, onLine) }
      }
    }

    /// A free wall end joined to the wall it nearly reaches: moved onto a wall's centre line it
    /// stops up to 60 cm short of (or runs up to 35 cm past); extended to a wall end up to 1 m
    /// away straight ahead; or bridged by a new piece of wall to a wall end up to 1 m away
    /// nearly ahead, so the outline has no gap to see the floor through.
    private func joinFreeEnds(_ segs: inout [Segment]) {
      let groups = endpointGroups(segs, within: 0.02)
      var bridges: [Segment] = []
      // Free ends already reached by another (so two ends facing each other join once).
      var taken = Set<Int>()
      for i in segs.indices {
        for end in 0..<2 where groups[i * 2 + end].count == 1 && !taken.contains(i * 2 + end) {
          let s = segs[i]
          let length = s.length
          guard length > 0.05 else { continue }
          let e = s.end(end)
          let out = -Builder.away(s, end)
          var hit: (t: Float, p: SIMD2<Float>)?
          for (j, o) in segs.enumerated() where j != i && o.length > 0.05 {
            let v = o.dir
            let c = ModelStyle.cross(out, v)
            guard abs(c) > 0.26 else { continue }
            let w = o.a - e
            let t = ModelStyle.cross(w, v) / c
            let r = ModelStyle.cross(w, out) / c
            guard r >= -0.06, r <= o.length + 0.06, t >= -0.35, t <= 0.6, length + t > 0.1 else {
              continue
            }
            if hit == nil || abs(t) < abs(hit!.t) - 1e-5 { hit = (t, e + out * t) }
          }
          if let hit, hit.t <= 0.2 {
            segs[i].setEnd(end, hit.p)
            continue
          }
          // A wall end ahead: straight on, or nearly.
          var target: (distance: Float, p: SIMD2<Float>, straight: Bool, id: Int)?
          for (j, o) in segs.enumerated() where j != i {
            for k in 0..<2 where !taken.contains(j * 2 + k) {
              let f = o.end(k)
              let v = f - e
              let dist = simd_length(v)
              guard dist > 0.05, dist <= 1.0 else { continue }
              let along = simd_dot(v, out), lateral = abs(ModelStyle.cross(out, v))
              guard along > 0 else { continue }
              let angle = atan2(lateral, along)
              guard angle < 15 * .pi / 180, lateral < 0.2 else { continue }
              if target == nil || dist < target!.distance - 1e-4 {
                target = (dist, f, angle < 4 * .pi / 180, j * 2 + k)
              }
            }
          }
          if let target, hit == nil || target.distance < hit!.t - 0.05,
            !Builder.cutsThrough(e, target.p, segs, except: i)
          {
            taken.insert(i * 2 + end)
            if groups[target.id].count == 1 { taken.insert(target.id) }
            let v = target.p - e
            let along = simd_dot(v, out), lateral = ModelStyle.cross(out, v)
            if target.straight {
              segs[i].setEnd(end, target.p)
            } else if abs(lateral) >= 0.08 {
              // Offset to one side: run straight on, then step across square to the end.
              let foot = e + out * along
              segs[i].setEnd(end, foot)
              bridges.append(Segment(a: foot, b: target.p, bottom: s.bottom, top: s.top))
            } else {
              bridges.append(Segment(a: e, b: target.p, bottom: s.bottom, top: s.top))
            }
          } else if let hit {
            segs[i].setEnd(end, hit.p)
          }
        }
      }
      segs += bridges
    }

    /// Ids of the endpoints (2 per segment) within `within` of each endpoint, itself included.
    private func endpointGroups(_ segs: [Segment], within: Float) -> [[Int]] {
      let n = segs.count * 2
      var out: [[Int]] = Array(repeating: [], count: n)
      for i in 0..<n {
        let p = segs[i / 2].end(i % 2)
        for j in 0..<n where simd_distance(p, segs[j / 2].end(j % 2)) <= within { out[i].append(j) }
      }
      return out
    }

    /// Moves endpoints closer than 8 cm (and chains of them) to their common middle.
    private func snap(_ segs: inout [Segment]) {
      let n = segs.count * 2
      guard n > 0 else { return }
      var parent = Array(0..<n)
      func find(_ x: Int) -> Int {
        var x = x
        while parent[x] != x {
          parent[x] = parent[parent[x]]
          x = parent[x]
        }
        return x
      }
      for i in 0..<n {
        let p = segs[i / 2].end(i % 2)
        for j in (i + 1)..<n where j / 2 != i / 2 {
          guard simd_distance(p, segs[j / 2].end(j % 2)) < 0.08 else { continue }
          let a = find(i), b = find(j)
          if a != b { parent[max(a, b)] = min(a, b) }
        }
      }
      var sum: [Int: SIMD2<Float>] = [:], count: [Int: Float] = [:]
      for i in 0..<n {
        let r = find(i)
        sum[r, default: .zero] += segs[i / 2].end(i % 2)
        count[r, default: 0] += 1
      }
      for i in 0..<n {
        let r = find(i)
        guard let c = count[r], c > 1, let s = sum[r] else { continue }
        segs[i / 2].setEnd(i % 2, s / c)
      }
    }

    /// Corner pieces where walls meet: the outer corner between each pair of neighbouring walls
    /// filled in, so corners join square at any angle without a wall poking past another.
    private func jointPieces() -> [SCNNode] {
      let t = ModelStyle.wallThickness
      let groups = endpointGroups(segments, within: 0.02)
      var done = Set<Int>()
      var mesh = Mesh()
      for i in 0..<groups.count where !done.contains(i) {
        let members = groups[i]
        for m in members { done.insert(m) }
        guard members.count >= 2 else { continue }
        let p = segments[i / 2].end(i % 2)
        var arms: [(angle: Float, d: SIMD2<Float>, s: Segment)] = []
        for m in members {
          let s = segments[m / 2]
          let d = m % 2 == 0 ? s.dir : -s.dir
          arms.append((atan2(d.y, d.x), d, s))
        }
        arms.sort { $0.angle < $1.angle }
        var points: [SIMD2<Float>] = []
        var outer = false
        for (k, arm) in arms.enumerated() {
          let n = SIMD2(-arm.d.y, arm.d.x)
          points.append(p + n * (t / 2))
          points.append(p - n * (t / 2))
          let next = arms[(k + 1) % arms.count]
          var gap = next.angle - arm.angle
          if gap <= 1e-4 { gap += 2 * .pi }
          guard gap > .pi + 0.02 else { continue }
          // Outer corner: this arm's left face meets the next arm's right face behind `p`.
          let nn = SIMD2(-next.d.y, next.d.x)
          let a0 = p + n * (t / 2), b0 = p - nn * (t / 2)
          let c = ModelStyle.cross(arm.d, next.d)
          guard abs(c) > 1e-4 else { continue }
          let s = ModelStyle.cross(b0 - a0, next.d) / c
          let miter = a0 + arm.d * s
          guard simd_distance(miter, p) < 2 * t else { continue }
          points.append(miter)
          outer = true
        }
        guard outer else { continue }
        let hull = ModelStyle.convexHull(points)
        guard hull.count >= 3 else { continue }
        let bottoms = arms.map { $0.s.bottom }, tops = arms.map { $0.s.top }
        let low = (bottoms.min() ?? floorY), y1 = tops.max() ?? low
        let y0 = low - floorY < 0.05 ? floorY - ModelStyle.slabDepth : low
        guard y1 > y0 else { continue }
        for k in 1..<(hull.count - 1) {
          let a = hull[0], b = hull[k], c = hull[k + 1]
          mesh.triangle(
            SIMD3(a.x, y1, a.y), SIMD3(b.x, y1, b.y), SIMD3(c.x, y1, c.y), normal: SIMD3(0, 1, 0))
        }
        for k in 0..<hull.count {
          let a = hull[k], b = hull[(k + 1) % hull.count]
          let e = b - a
          guard simd_length(e) > 1e-5 else { continue }
          let n = simd_normalize(SIMD2(e.y, -e.x))
          mesh.quad(
            SIMD3(a.x, y0, a.y), SIMD3(b.x, y0, b.y), SIMD3(b.x, y1, b.y), SIMD3(a.x, y1, a.y),
            normal: SIMD3(n.x, 0, n.y))
        }
      }
      guard let g = mesh.geometry(material(Palette.wall)) else { return [] }
      let node = SCNNode(geometry: g)
      node.name = "Corners"
      return [node]
    }

    /// The wall an insert sits in, and the hole it makes there in wall coordinates.
    private func host(of b: OBox, kind: Kind) -> (Int, Hole)? {
      var best: (Int, Hole, Float)?
      for (i, s) in segments.enumerated() {
        guard abs(simd_dot(b.xAxis, s.dir)) > 0.97 else { continue }
        let d = b.center2 - s.center
        let off = abs(simd_dot(d, s.normal))
        let along = simd_dot(d, s.dir)
        let half = s.length / 2
        guard off < 0.25, abs(along) < half + b.half.x * 0.5 else { continue }
        let score = off + max(0, abs(along) - half)
        if best == nil || score < best!.2 - 1e-5 {
          let hole = Hole(
            u0: along - b.half.x, u1: along + b.half.x,
            v0: b.bottom - s.bottom, v1: b.top - s.bottom, kind: kind)
          best = (i, hole, score)
        }
      }
      guard let best else { return nil }
      return (best.0, best.1)
    }

    /// Holes clipped to their wall, snapped to its foot and top when nearly there.
    private func clampedCuts(_ holes: [Hole], _ s: Segment) -> [Hole] {
      let length = s.length, height = s.top - s.bottom
      var out: [Hole] = []
      for var h in holes {
        h.u0 = max(h.u0, -length / 2)
        h.u1 = min(h.u1, length / 2)
        h.v0 = max(h.v0, 0)
        h.v1 = min(h.v1, height)
        if h.v1 > height - 0.03 { h.v1 = height }
        if h.v0 < 0.03 { h.v0 = 0 }
        guard h.u1 - h.u0 > 0.08, h.v1 - h.v0 > 0.08 else { continue }
        out.append(h)
      }
      return out
    }

    private func buildWall(_ s: Segment, cuts: [Hole]) -> SCNNode? {
      let t = ModelStyle.wallThickness
      let length = s.length, height = s.top - s.bottom
      guard length > 0.02, height > 0.02 else { return nil }
      // Down through the floor slab, so the slab's edge hides under the wall.
      let foot: Float =
        s.bottom - floorY < 0.05 ? -(ModelStyle.slabDepth + max(0, s.bottom - floorY)) : 0
      let parts = Parts()
      let wallMaterial = material(Palette.wall)
      var xs = [-length / 2, length / 2]
      for h in cuts { xs += [h.u0, h.u1] }
      xs.sort()
      var strips: [(a: Float, b: Float, solid: [(Float, Float)])] = []
      for i in 0..<(xs.count - 1) {
        let a = xs[i], b = xs[i + 1]
        guard b - a > 1e-4 else { continue }
        var solid: [(Float, Float)] = [(foot, height)]
        for h in cuts where h.u0 <= a + 1e-4 && h.u1 >= b - 1e-4 {
          // A door or opening at floor level cuts through the slab too, so no strip of wall
          // shows across the floor in the doorway.
          let v0 = h.v0 <= 0 ? foot : h.v0
          var next: [(Float, Float)] = []
          for (lo, hi) in solid {
            if h.v1 <= lo || v0 >= hi {
              next.append((lo, hi))
              continue
            }
            if v0 > lo { next.append((lo, v0)) }
            if h.v1 < hi { next.append((h.v1, hi)) }
          }
          solid = next
        }
        if let last = strips.last, last.b >= a - 1e-4, last.solid.count == solid.count,
          zip(last.solid, solid).allSatisfy({ abs($0.0 - $1.0) < 1e-4 && abs($0.1 - $1.1) < 1e-4 })
        {
          strips[strips.count - 1].b = b
        } else {
          strips.append((a, b, solid))
        }
      }
      for strip in strips {
        for (lo, hi) in strip.solid where hi - lo > 0.005 {
          parts.box(strip.a, strip.b, lo, hi, -t / 2, t / 2, wallMaterial)
        }
      }
      for h in cuts { addInsert(h, to: parts) }
      let c = s.center
      parts.node.simdPosition = SIMD3(c.x, s.bottom, c.y)
      parts.node.simdOrientation = simd_quatf(
        angle: ModelStyle.yaw(along: s.dir), axis: SIMD3(0, 1, 0))
      let box = OBox(
        center: SIMD3(c.x, (s.bottom + s.top) / 2, c.y), xAxis: s.dir,
        half: SIMD3(length / 2, height / 2, t / 2))
      fitPoints += box.corners()
      return parts.node
    }

    /// A door or window filling a hole, in the wall's frame (x along the wall, y up from its
    /// foot, z through it). Openings stay open. Nothing reaches more than 5 mm past a wall face.
    private func addInsert(_ h: Hole, to parts: Parts) {
      let t = ModelStyle.wallThickness
      let width = h.u1 - h.u0, height = h.v1 - h.v0
      switch h.kind {
      case .door:
        let trim = material(Palette.trim)
        let fw = min(0.045, width * 0.1), fd = t / 2 + 0.005
        parts.box(h.u0, h.u0 + fw, h.v0, h.v1, -fd, fd, trim)
        parts.box(h.u1 - fw, h.u1, h.v0, h.v1, -fd, fd, trim)
        parts.box(h.u0 + fw, h.u1 - fw, h.v1 - fw, h.v1, -fd, fd, trim)
        guard width > 0.3, height > 0.6 else { return }
        let inner = width - 2 * fw
        parts.box(h.u0 + fw, h.u1 - fw, h.v0, h.v1 - fw, -0.02, 0.02, material(Palette.door))
        // A wide door is a pair (or a row) of leaves.
        let leaves = inner > 1.3 ? min(4, max(2, Int((inner / 0.9).rounded()))) : 1
        let leaf = inner / Float(leaves)
        for i in 1..<leaves {
          let x = h.u0 + fw + leaf * Float(i)
          parts.box(x - 0.01, x + 0.01, h.v0, h.v1 - fw, -0.026, 0.026, trim)
        }
        let hy = h.v0 + min(1.0, height * 0.47)
        let metal = material(Palette.handle)
        for i in 0..<leaves {
          // The handle on the edge that opens: the far edge of a single door, the meeting
          // edges of a pair.
          let x0 = h.u0 + fw + leaf * Float(i), x1 = x0 + leaf
          let hx = leaves == 1 || i % 2 == 0 ? x1 - 0.09 : x0 + 0.09
          parts.box(hx - 0.045, hx + 0.045, hy - 0.012, hy + 0.012, 0.02, 0.05, metal)
          parts.box(hx - 0.045, hx + 0.045, hy - 0.012, hy + 0.012, -0.05, -0.02, metal)
        }
      case .window:
        let frame = material(Palette.windowFrame)
        let fw = min(0.05, min(width, height) * 0.12)
        let depth: Float = 0.022, proud: Float = 0.005
        // A frame on each face of the wall, the glass at its middle.
        for side in [Float(-1), 1] {
          let z0 = side * (t / 2 - depth + proud), z1 = side * (t / 2 + proud)
          let lo = min(z0, z1), hi = max(z0, z1)
          parts.box(h.u0, h.u0 + fw, h.v0, h.v1, lo, hi, frame)
          parts.box(h.u1 - fw, h.u1, h.v0, h.v1, lo, hi, frame)
          parts.box(h.u0 + fw, h.u1 - fw, h.v1 - fw, h.v1, lo, hi, frame)
          parts.box(h.u0 + fw, h.u1 - fw, h.v0, h.v0 + fw, lo, hi, frame)
        }
        parts.box(h.u0 + 0.004, h.u1 - 0.004, h.v0 + 0.004, h.v1 - 0.004, -0.005, 0.005, glass())
        if width > 1.2 {
          let m = (h.u0 + h.u1) / 2
          parts.box(m - 0.02, m + 0.02, h.v0 + 0.01, h.v1 - 0.01, -0.025, 0.025, frame)
        }
      default:
        break
      }
    }

    // MARK: Settling objects

    /// Moves each object out of any wall it crosses (RoomPlan's boxes often reach into the wall
    /// line, and the walls are now 10 cm thick), then pushes apart pieces of furniture whose
    /// boxes overlap, such as a coffee table run into a sofa or two chairs into each other.
    private func settleObjects() {
      for i in objects.indices { objects[i].box = outOfWalls(objects[i].box) }
      separateFurniture()
    }

    /// The box moved off every wall face it crosses, by at most 35 cm in all; unmoved when it
    /// would have to go further.
    private func outOfWalls(_ start: OBox) -> OBox {
      var b = start
      for _ in 0..<4 {
        var moved = false
        for k in segments.indices {
          guard let push = wallPush(b, k) else { continue }
          b.center.x += push.x
          b.center.z += push.y
          moved = true
        }
        if !moved { break }
      }
      return simd_distance(b.center2, start.center2) <= 0.35 ? b : start
    }

    /// How far (in plan) to move a box so it stops crossing wall `k`, or nil when it doesn't
    /// cross it, sits in a doorway, straddles the wall's middle or would have to move too far.
    private func wallPush(_ b: OBox, _ k: Int) -> SIMD2<Float>? {
      let s = segments[k]
      let t = ModelStyle.wallThickness
      guard b.bottom < s.top - 0.02, b.top > s.bottom + 0.02 else { return nil }
      let d = s.dir, n = s.normal
      let rel = b.center2 - s.center
      let along = simd_dot(rel, d), across = simd_dot(rel, n)
      let halfL = s.length / 2
      let eAlong = b.extent(along: d), eAcross = b.extent(along: n)
      let overlapAlong = eAlong + halfL - abs(along)
      let overlapAcross = eAcross + t / 2 - abs(across)
      guard overlapAlong > 0.005, overlapAcross > 0.005 else { return nil }
      for u in [b.xAxis, b.zAxis] {
        let rs = halfL * abs(simd_dot(d, u)) + t / 2 * abs(simd_dot(n, u))
        let rb = abs(simd_dot(u, b.xAxis)) * b.half.x + abs(simd_dot(u, b.zAxis)) * b.half.z
        if rs + rb - abs(simd_dot(rel, u)) <= 0.005 { return nil }
      }
      guard abs(across) > 0.02 else { return nil }
      // Crossing the wall only where a doorway leaves it open.
      let lo = max(along - eAlong, -halfL), hi = min(along + eAlong, halfL)
      let doorway =
        k < cuts.count
        && cuts[k].contains { h in
          h.kind != .window && h.v0 <= 0.001 && h.u0 <= lo + 0.01 && h.u1 >= hi - 0.01
        }
      if doorway { return nil }
      let faceMove = overlapAcross + 0.005, endMove = overlapAlong + 0.005
      let beyondEnd = abs(along) >= halfL
      if faceMove <= 0.3, !beyondEnd || faceMove <= endMove {
        return n * (across >= 0 ? 1 : -1) * faceMove
      }
      if beyondEnd, endMove <= 0.15 {
        return d * (along >= 0 ? 1 : -1) * endMove
      }
      return nil
    }

    /// The axis (pointing from `a` to `b`) and depth of the smallest overlap of two footprints,
    /// or nil when they don't overlap.
    private static func penetration(_ a: OBox, _ b: OBox) -> (axis: SIMD2<Float>, depth: Float)? {
      let rel = b.center2 - a.center2
      var best: (SIMD2<Float>, Float)?
      for u in [a.xAxis, a.zAxis, b.xAxis, b.zAxis] {
        let dist = simd_dot(rel, u)
        let overlap = a.extent(along: u) + b.extent(along: u) - abs(dist)
        guard overlap > 0.005 else { return nil }
        if best == nil || overlap < best!.1 - 1e-5 { best = (dist >= 0 ? u : -u, overlap) }
      }
      return best
    }

    /// Share of `a`'s footprint inside `b`'s, sampled on a grid.
    private static func coverage(_ a: OBox, by b: OBox) -> Float {
      var inside = 0, total = 0
      for i in 0..<7 {
        for j in 0..<7 {
          let sx = (Float(i) + 0.5) / 7 * 2 - 1, sz = (Float(j) + 0.5) / 7 * 2 - 1
          let p = a.center2 + a.xAxis * (sx * a.half.x) + a.zAxis * (sz * a.half.z)
          total += 1
          if b.distance(to: p) <= 0 { inside += 1 }
        }
      }
      return Float(inside) / Float(total)
    }

    private func crossesWall(_ b: OBox) -> Bool {
      segments.indices.contains { wallPush(b, $0) != nil }
    }

    /// Pairs of overlapping furniture boxes pushed apart: the smaller piece moves out by the
    /// least distance (up to 25 cm) plus a 2 cm gap, or, when that would put it in a wall or
    /// is too far, shrinks back from the overlap. Two chairs each move half. A near-duplicate
    /// of a larger piece of the same kind is left out. Chairs at tables, cabinets in a run and
    /// tables pushed together stay as they are.
    private func separateFurniture() {
      let movable: Set<Kind> = [.sofa, .chair, .bed, .table, .storage]
      func eligible(_ a: Kind, _ b: Kind) -> Bool {
        guard movable.contains(a), movable.contains(b) else { return false }
        if Set([a, b]) == [.table, .chair] { return false }
        if a == b && (a == .storage || a == .table) { return false }
        return true
      }
      for _ in 0..<2 {
        for i in objects.indices {
          for j in objects.indices where j > i {
            guard !objects[i].hidden, !objects[j].hidden, eligible(objects[i].kind, objects[j].kind)
            else { continue }
            let a = objects[i].box, b = objects[j].box
            guard a.bottom - floorY < 0.3, b.bottom - floorY < 0.3,
              min(a.top, b.top) - max(a.bottom, b.bottom) > 0.1,
              let (axis, depth) = Builder.penetration(a, b)
            else { continue }
            let areaA = a.half.x * a.half.z, areaB = b.half.x * b.half.z
            let small = areaA <= areaB ? i : j
            let other = small == i ? j : i
            // Pointing from the other piece to the one that moves.
            let out = small == j ? axis : -axis
            if objects[i].kind == objects[j].kind,
              Builder.coverage(objects[small].box, by: objects[other].box) > 0.6
            {
              objects[small].hidden = true
              continue
            }
            let move = depth + 0.02
            if objects[i].kind == .chair && objects[j].kind == .chair && move <= 0.3 {
              var mi = objects[i].box, mj = objects[j].box
              mi.center.x -= axis.x * move / 2
              mi.center.z -= axis.y * move / 2
              mj.center.x += axis.x * move / 2
              mj.center.z += axis.y * move / 2
              if !crossesWall(mi), !crossesWall(mj) {
                objects[i].box = mi
                objects[j].box = mj
                continue
              }
            }
            var moved = objects[small].box
            moved.center.x += out.x * move
            moved.center.z += out.y * move
            if move <= 0.25, !crossesWall(moved) {
              objects[small].box = moved
              continue
            }
            // Shrink back from the overlap along one of its own axes.
            var shrunk = objects[small].box
            for (axisIndex, own) in [shrunk.xAxis, shrunk.zAxis].enumerated() {
              guard abs(simd_dot(own, out)) > 0.95 else { continue }
              let half = axisIndex == 0 ? shrunk.half.x : shrunk.half.z
              let newHalf = half - move / 2
              guard newHalf >= half * 0.6 else { break }
              let shift = out * (move / 2)
              shrunk.center.x += shift.x
              shrunk.center.z += shift.y
              if axisIndex == 0 { shrunk.half.x = newHalf } else { shrunk.half.z = newHalf }
              objects[small].box = shrunk
              break
            }
          }
        }
      }
    }

    // MARK: Wall shade

    /// A soft darkening of the floor along the foot of each wall face with floor in front of it
    /// (not across doorways), so floor and walls meet in a gentle shadow and inside corners
    /// read a little darker.
    private func wallShade() -> SCNNode? {
      guard let texture = ModelStyle.edgeShadeTexture, !floorTriangles.isEmpty else { return nil }
      let t = ModelStyle.wallThickness
      let width: Float = 0.26
      let y = floorY + 0.003
      var positions: [SCNVector3] = [], coords: [CGPoint] = []
      for (k, s) in segments.enumerated() where s.bottom - floorY < 0.1 && k < cuts.count {
        let length = s.length
        guard length > 0.05 else { continue }
        var spans: [(Float, Float)] = [(-length / 2, length / 2)]
        for h in cuts[k] where h.v0 <= 0.001 && h.kind != .window {
          spans = spans.flatMap { span -> [(Float, Float)] in
            let (lo, hi) = span
            if h.u1 <= lo || h.u0 >= hi { return [span] }
            var out: [(Float, Float)] = []
            if h.u0 > lo { out.append((lo, h.u0)) }
            if h.u1 < hi { out.append((h.u1, hi)) }
            return out
          }
        }
        for side in [Float(-1), 1] {
          let n = s.normal * side
          for (lo, hi) in spans where hi - lo > 0.04 {
            let pieces = max(1, Int(((hi - lo) / 0.5).rounded(.up)))
            let step = (hi - lo) / Float(pieces)
            for q in 0..<pieces {
              let u0 = lo + step * Float(q), u1 = u0 + step
              let probe = t / 2 + 0.12
              let onFloor = [u0 + 0.02, (u0 + u1) / 2, u1 - 0.02].allSatisfy { u in
                floorContains(s.center + s.dir * u + n * probe)
              }
              guard onFloor else { continue }
              let a0 = s.center + s.dir * u0 + n * (t / 2), a1 = s.center + s.dir * u1 + n * (t / 2)
              let b0 = a0 + n * width, b1 = a1 + n * width
              let corners: [(SIMD2<Float>, CGFloat)] = [
                (a0, 0), (a1, 0), (b1, 1), (a0, 0), (b1, 1), (b0, 1),
              ]
              for (p, u) in corners {
                positions.append(SCNVector3(p.x, y, p.y))
                coords.append(CGPoint(x: u, y: 0.5))
              }
            }
          }
        }
      }
      guard !positions.isEmpty else { return nil }
      let normals = [SCNVector3](repeating: SCNVector3(0, 1, 0), count: positions.count)
      let element = SCNGeometryElement(
        indices: (0..<Int32(positions.count)).map { $0 }, primitiveType: .triangles)
      let geometry = SCNGeometry(
        sources: [
          SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
          SCNGeometrySource(textureCoordinates: coords),
        ], elements: [element])
      let m = SCNMaterial()
      m.lightingModel = .constant
      m.diffuse.contents = texture
      m.diffuse.wrapS = .clamp
      m.diffuse.wrapT = .clamp
      m.blendMode = .alpha
      m.transparency = 0.075
      m.writesToDepthBuffer = false
      m.isDoubleSided = true
      geometry.materials = [m]
      let node = SCNNode(geometry: geometry)
      node.name = "WallShade"
      node.castsShadow = false
      node.renderingOrder = 9
      return node
    }

    /// Whether a plan point lies on the floor, using a coarse grid of the floor's triangles.
    private func floorContains(_ p: SIMD2<Float>) -> Bool {
      if floorGrid == nil { buildFloorGrid() }
      guard let grid = floorGrid else { return false }
      let cx = Int(((p.x - grid.origin.x) / grid.cell).rounded(.down))
      let cz = Int(((p.y - grid.origin.y) / grid.cell).rounded(.down))
      guard cx >= 0, cz >= 0, cx < grid.columns, cz < grid.rows else { return false }
      for index in grid.cells[cz * grid.columns + cx] {
        let (a, b, c) = floorTriangles[index]
        if ModelStyle.inside(p, a, b, c) { return true }
      }
      return false
    }

    private func buildFloorGrid() {
      var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
      for (a, b, c) in floorTriangles {
        lo = simd_min(lo, simd_min(a, simd_min(b, c)))
        hi = simd_max(hi, simd_max(a, simd_max(b, c)))
      }
      guard lo.x.isFinite, lo.y.isFinite, hi.x.isFinite, hi.y.isFinite else { return }
      let cell = max(0.5, max(hi.x - lo.x, hi.y - lo.y) / 64)
      func step(_ v: Float, from origin: Float) -> Int { Int(((v - origin) / cell).rounded(.down)) }
      let columns = step(hi.x, from: lo.x) + 1, rows = step(hi.y, from: lo.y) + 1
      guard columns > 0, rows > 0, columns * rows <= 10_000 else { return }
      var cells = [[Int]](repeating: [], count: columns * rows)
      for (index, (a, b, c)) in floorTriangles.enumerated() {
        let tlo = simd_min(a, simd_min(b, c)), thi = simd_max(a, simd_max(b, c))
        let x0 = max(0, step(tlo.x, from: lo.x)), x1 = min(columns - 1, step(thi.x, from: lo.x))
        let z0 = max(0, step(tlo.y, from: lo.y)), z1 = min(rows - 1, step(thi.y, from: lo.y))
        guard x0 <= x1, z0 <= z1 else { continue }
        for z in z0...z1 {
          for x in x0...x1 { cells[z * columns + x].append(index) }
        }
      }
      floorGrid = FloorGrid(origin: lo, cell: cell, columns: columns, rows: rows, cells: cells)
    }

    // MARK: Objects

    /// Which way an object faces: the yaw that turns local +z to its front, and its width and
    /// depth in that frame.
    struct Facing {
      var yaw: Float
      var width: Float
      var depth: Float
    }

    enum SideSet { case all, shortEnds, longFaces }

    /// Outward normals of the candidate back sides, in a fixed order.
    private func sides(_ b: OBox, _ set: SideSet) -> [SIMD2<Float>] {
      let z = b.zAxis, x = b.xAxis
      let all = [-z, z, -x, x]
      let ratio = max(b.half.x, b.half.z) / max(min(b.half.x, b.half.z), 1e-4)
      guard ratio > 1.08 else { return all }
      let xLonger = b.half.x > b.half.z
      switch set {
      case .all: return all
      case .shortEnds: return xLonger ? [-x, x] : [-z, z]
      case .longFaces: return xLonger ? [-z, z] : [-x, x]
      }
    }

    private func facing(_ b: OBox, back n: SIMD2<Float>) -> Facing {
      let front = -n
      let across = SIMD2(-n.y, n.x)
      return Facing(
        yaw: atan2(front.x, front.y), width: 2 * b.extent(along: across),
        depth: 2 * b.extent(along: n))
    }

    /// Distance from a point to the nearest wall roughly parallel to `normal` (any wall when
    /// `normal` is nil).
    private func wallDistance(_ p: SIMD2<Float>, normal: SIMD2<Float>?) -> Float {
      var best = Float.infinity
      for s in segments {
        if let normal, abs(simd_dot(normal, s.normal)) < 0.8 { continue }
        let d = p - s.center
        let along = min(max(simd_dot(d, s.dir), -s.length / 2), s.length / 2)
        best = min(best, simd_length(p - (s.center + s.dir * along)))
      }
      return best
    }

    /// Extra distance counted against a side with a window or door in the wall behind it, so
    /// a bed's head or a wardrobe's back goes against a plain wall when there is one.
    private func openingPenalty(_ b: OBox, side n: SIMD2<Float>) -> Float {
      let p = b.center2 + n * b.extent(along: n)
      let across = SIMD2(-n.y, n.x)
      let half = b.extent(along: across)
      for (k, s) in segments.enumerated() where abs(simd_dot(n, s.normal)) > 0.8 && k < cuts.count {
        guard Builder.distance(p, to: s) < 0.45 else { continue }
        let mid = simd_dot(p - s.center, s.dir)
        for h in cuts[k] where h.kind == .window || h.kind == .door {
          if min(mid + half, h.u1) - max(mid - half, h.u0) > 0.15 { return 0.5 }
        }
      }
      return 0
    }

    /// Back against the nearest wall, among the candidate sides.
    private func backToWall(_ b: OBox, _ set: SideSet) -> Facing {
      let candidates = sides(b, set)
      var bestSide = candidates[0], bestScore = Float.infinity
      for n in candidates {
        let p = b.center2 + n * b.extent(along: n)
        let score = wallDistance(p, normal: n) + openingPenalty(b, side: n)
        if score < bestScore - 1e-4 {
          bestScore = score
          bestSide = n
        }
      }
      return facing(b, back: bestSide)
    }

    /// A chair faces the nearest table within 1.5 m (the table's side nearest to it), otherwise
    /// has its back to the nearest wall.
    private func chairFacing(_ b: OBox) -> Facing {
      var nearest: (OBox, Float)?
      for item in objects where item.kind == .table {
        let d = item.box.distance(to: b.center2)
        if d < 1.5, nearest == nil || d < nearest!.1 - 1e-5 { nearest = (item.box, d) }
      }
      guard let (table, _) = nearest else { return backToWall(b, .all) }
      // The table side the chair is at: the one its centre is furthest out past, or (tucked
      // in) nearest to.
      let d = b.center2 - table.center2
      let lx = simd_dot(d, table.xAxis), lz = simd_dot(d, table.zAxis)
      let past = [abs(lx) - table.half.x, abs(lz) - table.half.z]
      let outward =
        past[0] >= past[1] ? table.xAxis * (lx >= 0 ? 1 : -1) : table.zAxis * (lz >= 0 ? 1 : -1)
      let toward = -outward
      var front = sides(b, .all)[0], best = -Float.infinity
      for n in sides(b, .all) where simd_dot(n, toward) > best + 1e-4 {
        best = simd_dot(n, toward)
        front = n
      }
      return facing(b, back: -front)
    }

    private func buildObject(_ item: Item) -> SCNNode? {
      let b = item.box
      let height = 2 * b.half.y
      guard height > 0.01, b.half.x > 0.005, b.half.z > 0.005 else { return nil }
      let parts = Parts()
      let f: Facing
      switch item.kind {
      case .bed:
        f = backToWall(b, .shortEnds)
        bed(parts, f.width, height, f.depth)
      case .sofa:
        f = backToWall(b, .longFaces)
        sofa(parts, f.width, height, f.depth)
      case .chair:
        f = chairFacing(b)
        if f.width >= 0.6, f.depth >= 0.6, height > 0.55 {
          sofa(parts, f.width, height, f.depth)
        } else {
          chair(parts, f.width, height, f.depth)
        }
      case .table:
        f = facing(b, back: -b.zAxis)
        table(parts, f.width, height, f.depth)
      case .storage:
        f = backToWall(b, .longFaces)
        let raised = b.bottom - floorY > 0.25
        storage(parts, f.width, height, f.depth, raised: raised, kitchen: nearKitchen(b))
      case .refrigerator:
        f = backToWall(b, .all)
        refrigerator(parts, f.width, height, f.depth)
      case .oven:
        f = backToWall(b, .all)
        oven(parts, f.width, height, f.depth)
      case .stove:
        f = backToWall(b, .all)
        stove(parts, f.width, height, f.depth)
      case .dishwasher:
        f = backToWall(b, .all)
        dishwasher(parts, f.width, height, f.depth)
      case .washerdryer:
        f = backToWall(b, .all)
        washer(parts, f.width, height, f.depth)
      case .television:
        f = backToWall(b, .longFaces)
        television(parts, f.width, height, f.depth, standing: supported(b, except: item.node))
      case .toilet:
        f = backToWall(b, .shortEnds)
        toilet(parts, f.width, height, f.depth)
      case .sink:
        f = backToWall(b, .all)
        sink(parts, f.width, height, f.depth)
      case .bathtub:
        f = backToWall(b, .longFaces)
        bathtub(parts, f.width, height, f.depth)
      case .fireplace:
        f = backToWall(b, .longFaces)
        fireplace(parts, f.width, height, f.depth)
      case .stairs:
        f = backToWall(b, .shortEnds)
        stairs(parts, f.width, height, f.depth)
      default:
        f = facing(b, back: -b.zAxis)
        let w = f.width / 2, d = f.depth / 2
        parts.box(-w, w, 0, height, -d, d, material(Palette.neutral))
      }
      parts.node.simdPosition = SIMD3(b.center.x, b.bottom, b.center.z)
      parts.node.simdOrientation = simd_quatf(angle: f.yaw, axis: SIMD3(0, 1, 0))
      if b.bottom - floorY < 0.15 {
        let strength: Float
        switch item.kind {
        case .chair where !(f.width >= 0.6 && f.depth >= 0.6 && height > 0.55), .table:
          strength = 0.13
        case .television: strength = 0.08
        default: strength = 0.24
        }
        addShadow(
          center: b.center2, yaw: f.yaw, width: f.width, depth: f.depth, height: height,
          strength: strength)
      }
      return parts.node
    }

    /// How far the floor runs from `p` along `n` before a wall face or the floor's edge, looking
    /// along three parallel lines `spread` apart either side.
    private func room(
      from p: SIMD2<Float>, along n: SIMD2<Float>, spread: Float, limit: Float
    ) -> Float {
      let t = ModelStyle.wallThickness
      let across = SIMD2(-n.y, n.x)
      var best = limit
      for offset in [-spread, 0, spread] {
        let o = p + across * offset
        func hit(_ a: SIMD2<Float>, _ b: SIMD2<Float>, pad: Float, face: Float) {
          let v = b - a
          let length = simd_length(v)
          guard length > 1e-4 else { return }
          let d = v / length
          let den = ModelStyle.cross(n, d)
          guard abs(den) > 0.1 else { return }
          let w = a - o
          let s = ModelStyle.cross(w, d) / den
          let r = ModelStyle.cross(w, n) / den
          guard r >= -pad, r <= length + pad, s > -0.5 else { return }
          // The face is `face` short of the line, measured along the ray.
          best = min(best, s - face / abs(den))
        }
        for seg in segments { hit(seg.a, seg.b, pad: t / 2, face: t / 2 + 0.005) }
        for e in floorEdges { hit(e.0, e.1, pad: 0, face: 0.005) }
      }
      return best
    }

    /// A soft shadow on the floor under an object's footprint, fading out a little past it, and
    /// never past a wall face or the floor's edge.
    private func addShadow(
      center: SIMD2<Float>, yaw: Float, width: Float, depth: Float, height: Float, strength: Float
    ) {
      let front = SIMD2(sin(yaw), cos(yaw)), right = SIMD2(cos(yaw), -sin(yaw))
      let blur = min(0.2, 0.06 + 0.12 * height), inset = min(0.03, min(width, depth) * 0.2)
      func side(_ n: SIMD2<Float>, half: Float, spread: Float) -> (outer: Float, inner: Float) {
        let outer = room(from: center, along: n, spread: spread * 0.8, limit: half + blur)
        return (outer, min(half - inset, outer - 0.03))
      }
      let l = side(-right, half: width / 2, spread: depth / 2)
      let r = side(right, half: width / 2, spread: depth / 2)
      let b = side(-front, half: depth / 2, spread: width / 2)
      let f = side(front, half: depth / 2, spread: width / 2)
      guard l.outer > 0.02 || r.outer > 0.02, b.outer > 0.02 || f.outer > 0.02,
        -l.inner < r.inner, -b.inner < f.inner, l.outer + r.outer > 0.1, b.outer + f.outer > 0.1
      else { return }
      let xs = [-l.outer, -l.inner, r.inner, r.outer]
      let zs = [-b.outer, -b.inner, f.inner, f.outer]
      let ts: [CGFloat] = [0, 0.5, 0.5, 1]
      let y = floorY + 0.004
      var entry = shadows[strength] ?? ([], [])
      func vertex(_ i: Int, _ j: Int) {
        let p = center + right * xs[i] + front * zs[j]
        entry.positions.append(SCNVector3(p.x, y, p.y))
        entry.coords.append(CGPoint(x: ts[i], y: ts[j]))
      }
      for i in 0..<3 {
        for j in 0..<3 {
          // Wound to face up whichever way the footprint is turned.
          let flip = ModelStyle.cross(right, front) > 0
          let quad =
            flip
            ? [(i, j), (i, j + 1), (i + 1, j + 1), (i, j), (i + 1, j + 1), (i + 1, j)]
            : [(i, j), (i + 1, j), (i + 1, j + 1), (i, j), (i + 1, j + 1), (i, j + 1)]
          for (a, c) in quad { vertex(a, c) }
        }
      }
      shadows[strength] = entry
    }

    private func shadowNodes() -> SCNNode {
      let group = SCNNode()
      group.name = "Shadows"
      guard let texture = ModelStyle.shadowTexture else { return group }
      for strength in shadows.keys.sorted() {
        guard let entry = shadows[strength], !entry.positions.isEmpty else { continue }
        let normals = [SCNVector3](repeating: SCNVector3(0, 1, 0), count: entry.positions.count)
        let element = SCNGeometryElement(
          indices: (0..<Int32(entry.positions.count)).map { $0 }, primitiveType: .triangles)
        let geometry = SCNGeometry(
          sources: [
            SCNGeometrySource(vertices: entry.positions), SCNGeometrySource(normals: normals),
            SCNGeometrySource(textureCoordinates: entry.coords),
          ], elements: [element])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = texture
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.blendMode = .alpha
        m.transparency = CGFloat(strength)
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.castsShadow = false
        node.renderingOrder = 10
        group.addChildNode(node)
      }
      return group
    }

    /// Whether a kitchen fitting stands within reach (a base cabinet there gets a stone
    /// worktop rather than a wooden top).
    private func nearKitchen(_ b: OBox) -> Bool {
      let reach = 1.2 + max(b.half.x, b.half.z)
      for item in objects {
        switch item.kind {
        case .sink, .stove, .oven, .dishwasher, .refrigerator, .washerdryer:
          if item.box.distance(to: b.center2) < reach { return true }
        default:
          continue
        }
      }
      return false
    }

    /// Whether something stands under the box (the floor or another object's top).
    private func supported(_ b: OBox, except node: SCNNode) -> Bool {
      if b.bottom - floorY < 0.08 { return true }
      for item in objects where item.node !== node {
        if abs(item.box.top - b.bottom) < 0.1, item.box.distance(to: b.center2) < 0.05 {
          return true
        }
      }
      return false
    }

    // MARK: Furniture (W across, H up, D front to back; front is +z)
    //
    // Parts meet face to face or sit clearly inside one another, never with two faces a few
    // millimetres apart, so no seam flickers.

    /// A bed that reads as one from any side: a darker headboard standing well above the
    /// mattress, a darker frame showing as a lip all round, a bevelled sheet-white mattress, a
    /// duvet over the lower two thirds with a lighter turned-down band at its head and a darker
    /// runner across its foot, and pillows.
    private func bed(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let frame = material(Palette.softDark), headboard = material(Palette.headboard)
      let sheet = material(Palette.sheet), cover = material(Palette.soft),
        band = material(Palette.softLight)
      let pillow = material(Palette.pillow)
      let head = min(max(d * 0.035, 0.05), 0.08)
      let baseTop = min(max(h * 0.4, 0.12), 0.3)
      let mattressTop = max(
        baseTop + 0.12, min(baseTop + min(max(h * 0.3, 0.16), 0.24), max(h, baseTop + 0.16)))
      p.box(-w / 2, w / 2, 0, baseTop, -d / 2 + head, d / 2, frame, chamfer: 0.015)
      p.box(
        -w / 2 + 0.06, w / 2 - 0.06, baseTop - 0.01, mattressTop, -d / 2 + head, d / 2 - 0.06,
        sheet, chamfer: 0.05)
      // The duvet drapes over the mattress's sides from about a quarter of the way down,
      // leaving the frame's top showing as a lip.
      let coverStart = -d / 2 + head + max(0.42, (d - head) * 0.27)
      let coverTop = mattressTop + 0.03
      p.box(
        -w / 2 + 0.045, w / 2 - 0.045, mattressTop - 0.12, coverTop, coverStart, d / 2 - 0.045,
        cover, chamfer: 0.035)
      p.box(
        -w / 2 + 0.04, w / 2 - 0.04, mattressTop - 0.1, coverTop + 0.02, coverStart - 0.012,
        coverStart + 0.17, band, chamfer: 0.03)
      let runnerEnd = d / 2 - 0.045 - min(0.22, d * 0.1)
      let runnerStart = max(coverStart + 0.3, runnerEnd - min(0.42, d * 0.2))
      if runnerEnd - runnerStart > 0.1 {
        p.box(
          -w / 2 + 0.04, w / 2 - 0.04, mattressTop - 0.1, coverTop + 0.008, runnerStart, runnerEnd,
          frame, chamfer: 0.02)
      }
      let headTop = max(h, min(1.0, mattressTop + 0.7), mattressTop + 0.3)
      p.box(-w / 2, w / 2, 0, headTop, -d / 2, -d / 2 + head, headboard, chamfer: 0.02)
      let count = w > 1.25 ? 2 : 1
      let gap: Float = 0.08
      let pw = (w - 0.16 - gap * Float(count - 1)) / Float(count)
      let pd = min(0.4, d * 0.17), z0 = -d / 2 + head + 0.05
      for i in 0..<count {
        let x0 = -w / 2 + 0.08 + Float(i) * (pw + gap)
        p.box(
          x0, x0 + pw, mattressTop - 0.01, mattressTop + 0.12, z0, z0 + pd, pillow, chamfer: 0.05)
      }
    }

    private func sofa(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let body = material(Palette.softMid), cushion = material(Palette.soft),
        dark = material(Palette.softDark)
      let arm = min(max(w * 0.09, 0.08), 0.2)
      let back = min(max(d * 0.22, 0.12), 0.25)
      let seat = min(max(h * 0.52, 0.3), 0.48)
      let base = seat - min(0.14, seat * 0.4)
      let armTop = min(h, seat + min(max(h * 0.25, 0.12), 0.22))
      // Base and back sit between the arms (their ends buried 1 cm in them); the back's rear
      // face stays 5 mm in front of the arms' rear faces.
      p.box(
        -w / 2 + arm - 0.01, w / 2 - arm + 0.01, 0, base, -d / 2 + back, d / 2 - 0.03, body,
        chamfer: 0.02)
      p.box(
        -w / 2 + arm - 0.01, w / 2 - arm + 0.01, 0, h, -d / 2 + 0.005, -d / 2 + back, dark,
        chamfer: 0.04)
      p.box(-w / 2, -w / 2 + arm, 0, armTop, -d / 2, d / 2, body, chamfer: 0.04)
      p.box(w / 2 - arm, w / 2, 0, armTop, -d / 2, d / 2, body, chamfer: 0.04)
      let inner = w - 2 * arm
      let count = inner > 1.8 ? 3 : (inner > 1.05 ? 2 : 1)
      let gap: Float = 0.015
      let cw = (inner - gap * Float(count + 1)) / Float(count)
      let backCushion = min(0.16, (d - back) * 0.3)
      let backTop = min(h - 0.03, seat + (h - seat) * 0.9)
      for i in 0..<count {
        let x0 = -w / 2 + arm + gap + Float(i) * (cw + gap)
        p.box(
          x0, x0 + cw, base, seat, -d / 2 + back + backCushion, d / 2 - 0.02, cushion, chamfer: 0.04
        )
        if backTop > seat + 0.1 {
          p.box(
            x0, x0 + cw, base, backTop, -d / 2 + back, -d / 2 + back + backCushion, cushion,
            chamfer: 0.05)
        }
      }
    }

    private func chair(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let seatMaterial = material(Palette.soft), dark = material(Palette.softDark)
      let seat = min(max(h * 0.5, 0.25), 0.48)
      let seatT: Float = 0.04
      let backT = min(max(d * 0.08, 0.03), 0.05)
      let leg = min(max(min(w, d) * 0.09, 0.032), 0.05)
      let ix = w / 2 - leg / 2 - 0.015, iz = d / 2 - leg / 2 - 0.015
      for (sx, sz) in [(Float(-1), Float(-1)), (1, -1), (-1, 1), (1, 1)] {
        let x = sx * ix, z = sz * iz
        p.box(x - leg / 2, x + leg / 2, 0, seat - seatT, z - leg / 2, z + leg / 2, dark)
      }
      p.box(-w / 2, w / 2, seat - seatT, seat, -d / 2 + backT, d / 2, seatMaterial, chamfer: 0.012)
      // A solid back, darker than the seat and well above it, so its side reads from above.
      let top = max(h, seat + 0.3)
      p.box(
        -w / 2 + 0.01, w / 2 - 0.01, seat - seatT, top, -d / 2, -d / 2 + backT, dark, chamfer: 0.012
      )
    }

    private func table(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let top = material(Palette.wood), legMaterial = material(Palette.woodDark)
      let topT = min(max(h * 0.05, 0.025), 0.045)
      let leg = min(max(min(w, d) * 0.05, 0.035), 0.06)
      let inset = min(0.05, min(w, d) * 0.06)
      p.box(-w / 2, w / 2, h - topT, h, -d / 2, d / 2, top, chamfer: 0.006)
      for (sx, sz) in [(Float(-1), Float(-1)), (1, -1), (-1, 1), (1, 1)] {
        let x = sx * (w / 2 - inset - leg / 2), z = sz * (d / 2 - inset - leg / 2)
        p.box(x - leg / 2, x + leg / 2, 0, h - topT, z - leg / 2, z + leg / 2, legMaterial)
      }
    }

    /// Lines on a front at z = `z`: vertical ones at `xs` from `y0` to `y1`, horizontal ones
    /// across the front at `ys`.
    private func frontLines(
      _ p: Parts, _ w: Float, z: Float, xs: [Float], ys: [Float], y0: Float, y1: Float,
      _ line: SCNMaterial
    ) {
      let lw: Float = 0.012
      for x in xs { p.box(x - lw / 2, x + lw / 2, y0, y1, z - 0.003, z + 0.004, line) }
      for y in ys {
        p.box(-w / 2 + 0.02, w / 2 - 0.02, y - lw / 2, y + lw / 2, z - 0.003, z + 0.004, line)
      }
    }

    /// The x of the lines between `doors` equal doors across a front `w` wide, left to right
    /// (none for one door): -w / 2 + w * i / doors for i in 1..<doors. Spelled out with typed
    /// steps because the one-line closure (`(1..<doors).map { -w / 2 + w * Float($0) /
    /// Float(doors) }`) is too slow for Xcode 26's type checker ("unable to type-check this
    /// expression in reasonable time"); same operations in the same order, so the same values.
    private func doorLines(_ w: Float, doors: Int) -> [Float] {
      let left: Float = -w / 2
      let count = Float(doors)
      var xs: [Float] = []
      for i in 1..<doors {
        let offset: Float = w * Float(i) / count
        xs.append(left + offset)
      }
      return xs
    }

    private func handle(
      _ p: Parts, x: Float, y: Float, z: Float, vertical: Bool, length: Float, _ m: SCNMaterial
    ) {
      let half = length / 2, t: Float = 0.012
      if vertical {
        p.box(x - t, x + t, y - half, y + half, z, z + 0.025, m)
      } else {
        p.box(x - half, x + half, y - t, y + t, z, z + 0.025, m)
      }
    }

    private func storage(
      _ p: Parts, _ w: Float, _ h: Float, _ d: Float, raised: Bool, kitchen: Bool
    ) {
      let body = material(Palette.wood), line = material(Palette.woodLine),
        metal = material(Palette.handle)
      let lip = material(Palette.woodLight)
      if d < 0.12 {
        // A panel (a wardrobe front or a cupboard door seen alone).
        p.box(-w / 2, w / 2, 0, h, -d / 2, d / 2, body)
        let doors = max(1, Int((w / 0.5).rounded()))
        let xs = doorLines(w, doors: doors)
        frontLines(p, w, z: d / 2, xs: xs, ys: [], y0: 0.02, y1: h - 0.02, line)
        return
      }
      if h > 1.1, d < 0.45, !raised {
        // Open shelving.
        let side: Float = 0.025
        let back = material(Palette.woodDark)
        p.box(-w / 2, -w / 2 + side, 0, h - side, -d / 2, d / 2, body)
        p.box(w / 2 - side, w / 2, 0, h - side, -d / 2, d / 2, body)
        p.box(-w / 2, w / 2, h - side, h, -d / 2, d / 2, lip)
        p.box(
          -w / 2 + side, w / 2 - side, 0, 0.08, -d / 2, d / 2 - 0.02, material(Palette.woodDark))
        p.box(-w / 2 + side, w / 2 - side, 0.08, h - side, -d / 2, -d / 2 + 0.012, back)
        let shelves = max(2, Int((h - 0.1) / 0.36))
        for i in 1..<shelves {
          let y = 0.08 + (h - 0.08 - side) * Float(i) / Float(shelves)
          p.box(
            -w / 2 + side, w / 2 - side, y - 0.012, y + 0.012, -d / 2 + 0.012, d / 2 - 0.01, body)
        }
        return
      }
      let counter = !raised && h > 0.7 && h < 1.1 && d >= 0.4
      let stone = counter && kitchen
      // A top slab in a lighter tone overhanging the front: a stone worktop in a kitchen, a
      // pale wooden top elsewhere.
      let topT: Float = stone ? 0.035 : min(0.025, h * 0.08)
      let overhang: Float = counter ? 0.02 : 0.012
      let bodyTop = h - topT
      let front = d / 2 - overhang
      let plinth: Float = raised || h < 0.35 ? 0 : min(0.09, h * 0.1)
      if plinth > 0 {
        let recess: Float = 0.05
        p.box(
          -w / 2 + 0.005, w / 2 - 0.005, 0, plinth, -d / 2, front - recess,
          material(stone ? Palette.plinth : Palette.woodDark))
      }
      p.box(-w / 2, w / 2, plinth, bodyTop, -d / 2, front, body)
      p.box(-w / 2, w / 2, bodyTop, h, -d / 2, d / 2, stone ? material(Palette.counter) : lip)
      if plinth > 0 {
        // The underside of the doors, a shadow line over the recessed plinth.
        p.box(-w / 2, w / 2, plinth, plinth + 0.012, -d / 2, front + 0.004, line)
      }
      let y0 = plinth + 0.012, y1 = bodyTop - 0.01
      guard y1 - y0 > 0.08 else { return }
      if !raised, h <= 1.1, w >= 0.6, !stone {
        // Drawers.
        let rows = min(max(Int((y1 - y0) / 0.2), 2), 6)
        let columns = w > 1.3 ? 2 : 1
        let rowH = (y1 - y0) / Float(rows)
        let ys: [Float] = (1..<rows).map { (r: Int) -> Float in y0 + rowH * Float(r) }
        frontLines(p, w, z: front, xs: columns == 2 ? [0] : [], ys: ys, y0: y0, y1: y1, line)
        for r in 0..<rows {
          let y = y0 + rowH * (Float(r) + 0.55)
          for c in 0..<columns {
            let x = columns == 1 ? 0 : (c == 0 ? -w / 4 : w / 4)
            handle(
              p, x: x, y: y, z: front, vertical: false, length: min(0.16, w / Float(columns) * 0.3),
              metal)
          }
        }
        return
      }
      // Doors (with a drawer row under a kitchen worktop).
      let doors = max(1, Int((w / 0.55).rounded()))
      let doorTop = stone ? y1 - min(0.17, y1 * 0.2) : y1
      let xs = doorLines(w, doors: doors)
      frontLines(p, w, z: front, xs: xs, ys: stone ? [doorTop] : [], y0: y0, y1: y1, line)
      let doorW = w / Float(doors)
      for i in 0..<doors {
        let x0 = -w / 2 + doorW * Float(i)
        let hx = i % 2 == 0 ? x0 + doorW - 0.06 : x0 + 0.06
        let hy = raised ? y0 + 0.1 : (h > 1.1 ? min(doorTop - 0.1, 1.0) : doorTop - 0.1)
        handle(
          p, x: hx, y: hy, z: front, vertical: true, length: min(0.16, (doorTop - y0) * 0.25), metal
        )
        if stone {
          handle(
            p, x: x0 + doorW / 2, y: (doorTop + y1) / 2, z: front, vertical: false,
            length: min(0.14, doorW * 0.4), metal)
        }
      }
    }

    private func refrigerator(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let body = material(Palette.appliance), line = material(Palette.applianceLine),
        metal = material(Palette.handle)
      p.box(-w / 2, w / 2, 0, h, -d / 2, d / 2, body, chamfer: 0.015)
      let split = h > 1.2 ? h * 0.62 : h * 0.5
      frontLines(p, w, z: d / 2, xs: [], ys: [split], y0: 0, y1: h, line)
      let hx = w / 2 - 0.07
      handle(
        p, x: hx, y: split - min(0.35, split * 0.3), z: d / 2, vertical: true,
        length: min(0.5, split * 0.4), metal)
      handle(
        p, x: hx, y: split + 0.2, z: d / 2, vertical: true, length: min(0.3, (h - split) * 0.4),
        metal)
    }

    private func oven(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let body = material(Palette.appliance), metal = material(Palette.handle),
        dark = material(Palette.ovenGlass)
      p.box(-w / 2, w / 2, 0, h, -d / 2, d / 2, body, chamfer: 0.01)
      let top = h - min(0.12, h * 0.15)
      p.box(
        -w / 2 + 0.03, w / 2 - 0.03, top, h - 0.02, d / 2 - 0.003, d / 2 + 0.004,
        material(Palette.applianceLine))
      let wy0 = h * 0.18, wy1 = top - 0.12
      if wy1 > wy0 + 0.1 {
        p.box(-w / 2 + 0.08, w / 2 - 0.08, wy0, wy1, d / 2 - 0.003, d / 2 + 0.004, dark)
      }
      handle(p, x: 0, y: top - 0.05, z: d / 2, vertical: false, length: w * 0.7, metal)
    }

    private func stove(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let body = material(Palette.appliance), burner = material(Palette.burner)
      if h > 0.5 {
        oven(p, w, h, d)
      } else {
        p.box(-w / 2, w / 2, 0, h, -d / 2, d / 2, body, chamfer: 0.005)
      }
      p.box(
        -w / 2 + 0.02, w / 2 - 0.02, h, h + 0.008, -d / 2 + 0.02, d / 2 - 0.02,
        material(Palette.applianceLine))
      let r = min(w, d) * 0.13
      for (sx, sz) in [(Float(-1), Float(-1)), (1, -1), (-1, 1), (1, 1)] {
        let x = sx * w / 4, z = sz * d / 4
        p.cylinder(x: x, z: z, y0: h + 0.008, y1: h + 0.024, radius: r, burner)
        p.cylinder(
          x: x, z: z, y0: h + 0.024, y1: h + 0.03, radius: r * 0.45, material(Palette.applianceLine)
        )
      }
    }

    private func dishwasher(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let body = material(Palette.appliance), line = material(Palette.applianceLine),
        metal = material(Palette.handle)
      p.box(-w / 2, w / 2, 0, h, -d / 2, d / 2, body, chamfer: 0.01)
      let strip = h - min(0.12, h * 0.14)
      frontLines(p, w, z: d / 2, xs: [], ys: [strip, min(0.1, h * 0.1)], y0: 0, y1: h, line)
      handle(p, x: 0, y: strip - 0.06, z: d / 2, vertical: false, length: w * 0.6, metal)
    }

    private func washer(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let body = material(Palette.appliance), line = material(Palette.applianceLine)
      p.box(-w / 2, w / 2, 0, h, -d / 2, d / 2, body, chamfer: 0.02)
      let strip = h - min(0.14, h * 0.16)
      frontLines(p, w, z: d / 2, xs: [], ys: [strip], y0: 0, y1: h, line)
      let r = min(w, strip) * 0.32
      let cy = strip / 2 + 0.02
      p.disc(x: 0, y: cy, z0: d / 2, z1: d / 2 + 0.02, radius: r, material(Palette.handle))
      p.disc(
        x: 0, y: cy, z0: d / 2 + 0.02, z1: d / 2 + 0.03, radius: r * 0.75,
        material(Palette.ovenGlass))
    }

    private func television(_ p: Parts, _ w: Float, _ h: Float, _ d: Float, standing: Bool) {
      let panel = material(Palette.screen), glass = material(Palette.screenGlass)
      let t = min(d, 0.05)
      if standing {
        let footD = min(d, 0.22)
        let panelBottom = min(h * 0.15, 0.12)
        p.box(-w * 0.18, w * 0.18, 0, 0.02, -footD / 2, footD / 2, panel)
        p.box(-0.03, 0.03, 0.02, panelBottom + 0.05, -0.02, 0.02, panel)
        p.box(-w / 2, w / 2, panelBottom, h, -t / 2, t / 2, panel, chamfer: 0.006)
        p.box(
          -w / 2 + 0.012, w / 2 - 0.012, panelBottom + 0.012, h - 0.012, t / 2, t / 2 + 0.004, glass
        )
      } else {
        p.box(-w / 2, w / 2, 0, h, -d / 2, -d / 2 + t, panel, chamfer: 0.006)
        p.box(
          -w / 2 + 0.012, w / 2 - 0.012, 0.012, h - 0.012, -d / 2 + t, -d / 2 + t + 0.004, glass)
      }
    }

    /// A tank against the wall and, in front of it, an oval bowl narrower than the tank with a
    /// light grey seat ring and a darker inside.
    private func toilet(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let white = material(Palette.fixture), lid = material(Palette.fixtureRim)
      let seatMaterial = material(Palette.seat), inner = material(Palette.fixtureInner)
      let tankD = min(max(d * 0.26, 0.13), 0.22)
      let seat = min(max(h * 0.52, 0.34), 0.44)
      let tankTop = max(h, seat + 0.22)
      let tankW = min(w * 0.92, 0.52)
      p.box(
        -tankW / 2, tankW / 2, seat - 0.08, tankTop - 0.025, -d / 2, -d / 2 + tankD, white,
        chamfer: 0.025)
      p.box(
        -tankW / 2 - 0.008, tankW / 2 + 0.008, tankTop - 0.03, tankTop, -d / 2 - 0.004,
        -d / 2 + tankD + 0.012, lid, chamfer: 0.01)
      let rx = max(0.08, min(w * 0.42, w / 2 - 0.012, 0.2))
      let rz = max(0.1, min((d - tankD) * 0.55, 0.27))
      let cz = min(-d / 2 + tankD + rz - 0.04, d / 2 - rz - 0.012)
      p.oval(x: 0, z: cz - rz * 0.2, y0: 0, y1: 0.16, rx: rx * 0.62, rz: rz * 0.62, white)
      p.oval(x: 0, z: cz, y0: 0.12, y1: seat - 0.03, rx: rx, rz: rz, white)
      p.ovalRing(
        x: 0, z: cz, y0: seat - 0.03, y1: seat, rx: rx + 0.008, rz: rz + 0.008, width: 0.055,
        seatMaterial)
      p.oval(x: 0, z: cz, y0: seat - 0.06, y1: seat - 0.024, rx: rx - 0.045, rz: rz - 0.045, inner)
    }

    /// A rim around a recessed basin from `y0` to `y1`: the rim's top lighter than the body,
    /// the inside a visibly darker grey.
    private func basin(
      _ p: Parts, _ w: Float, _ d: Float, y0: Float, y1: Float, rim: Float, depth: Float
    ) {
      let body = material(Palette.fixture), top = material(Palette.fixtureRim),
        inner = material(Palette.fixtureInner)
      let floor = max(y0, y1 - depth)
      p.box(-w / 2, w / 2, y0, floor, -d / 2, d / 2, body)
      p.box(-w / 2, w / 2, floor, y1, -d / 2, -d / 2 + rim, body, top: top)
      p.box(-w / 2, w / 2, floor, y1, d / 2 - rim, d / 2, body, top: top)
      p.box(-w / 2, -w / 2 + rim, floor, y1, -d / 2 + rim, d / 2 - rim, body, top: top)
      p.box(w / 2 - rim, w / 2, floor, y1, -d / 2 + rim, d / 2 - rim, body, top: top)
      // A thin liner just inside the rim, so the recess's walls read darker too.
      let l: Float = 0.004, liner = y1 - 0.008
      p.box(-w / 2 + rim, w / 2 - rim, floor, liner, -d / 2 + rim, -d / 2 + rim + l, inner)
      p.box(-w / 2 + rim, w / 2 - rim, floor, liner, d / 2 - rim - l, d / 2 - rim, inner)
      p.box(-w / 2 + rim, -w / 2 + rim + l, floor, liner, -d / 2 + rim + l, d / 2 - rim - l, inner)
      p.box(w / 2 - rim - l, w / 2 - rim, floor, liner, -d / 2 + rim + l, d / 2 - rim - l, inner)
      p.box(
        -w / 2 + rim, w / 2 - rim, floor - 0.01, floor + 0.006, -d / 2 + rim, d / 2 - rim, inner)
    }

    private func sink(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let top = h < 0.35 ? Float(0) : h - 0.16
      if top > 0 {
        let body = material(Palette.wood), line = material(Palette.woodLine)
        p.box(-w / 2, w / 2, 0, top, -d / 2, d / 2 - 0.02, body)
        let doors = max(1, Int((w / 0.5).rounded()))
        let xs = doorLines(w, doors: doors)
        frontLines(p, w, z: d / 2 - 0.02, xs: xs, ys: [], y0: 0.02, y1: top - 0.02, line)
      }
      let rim = min(0.06, min(w, d) * 0.15)
      basin(p, w, d, y0: top, y1: h, rim: rim, depth: min(0.12, (h - top) * 0.7))
      let metal = material(Palette.handle)
      p.cylinder(x: 0, z: -d / 2 + min(0.04, d * 0.1), y0: h, y1: h + 0.12, radius: 0.015, metal)
      p.box(
        -0.012, 0.012, h + 0.1, h + 0.125, -d / 2 + 0.03, -d / 2 + 0.03 + min(0.12, d * 0.3), metal)
    }

    private func bathtub(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      basin(p, w, d, y0: 0, y1: h, rim: min(max(min(w, d) * 0.08, 0.05), 0.1), depth: h * 0.75)
      let metal = material(Palette.handle)
      let x = -w / 2 + min(0.04, w * 0.05)
      p.box(x - 0.012, x + min(0.14, w * 0.1), h, h + 0.025, -0.012, 0.012, metal)
    }

    private func fireplace(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let stone = material(Palette.stone), dark = material(Palette.dark)
      p.box(-w / 2, w / 2, 0, h - 0.05, -d / 2, d / 2, stone)
      p.box(-w / 2 - 0.03, w / 2 + 0.03, h - 0.05, h, -d / 2, d / 2 + 0.03, stone)
      p.box(-w * 0.28, w * 0.28, 0.05, min(h * 0.55, h - 0.15), d / 2 - 0.003, d / 2 + 0.004, dark)
    }

    private func stairs(_ p: Parts, _ w: Float, _ h: Float, _ d: Float) {
      let wood = material(Palette.wood)
      let steps = max(3, Int(h / 0.18))
      let run = d / Float(steps)
      for i in 0..<steps {
        let z1 = d / 2 - run * Float(i)
        p.box(-w / 2, w / 2, 0, h * Float(i + 1) / Float(steps), z1 - run, z1, wood)
      }
    }

    // MARK: View

    /// The plan's size: the diagonal of the walls' and floor's extent, in metres.
    private func planDiagonal() -> Float {
      var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
      for p in fitPoints where ModelStyle.usable(p) {
        lo = simd_min(lo, SIMD2(p.x, p.z))
        hi = simd_max(hi, SIMD2(p.x, p.z))
      }
      guard lo.x.isFinite, hi.x.isFinite else { return 10 }
      return simd_length(hi - lo)
    }

    /// The camera's height angle for a view of this shape: 58 degrees for a landscape view,
    /// up to 63 for a tall portrait one (the plan then stretches up the screen), and higher
    /// still, up to 70, for a single small room, so its near walls hide less of it.
    func automaticElevation(aspect: Float) -> Float {
      let portrait = min(max((0.8 - aspect) / 0.35, 0), 1)
      var e = ModelStyle.defaultElevation + 5 * portrait
      let small = min(max(70 - (planDiagonal() - 5) * 3, 0), 70)
      e = max(e, small)
      return min(max(e, 10), 89)
    }

    func view(elevation: Float, aspect: Float) -> View {
      var points = fitPoints.filter(ModelStyle.usable)
      if points.isEmpty { points = [SIMD3(-1, 0, -1), SIMD3(1, 1, 1)] }
      var low = points[0], high = points[0]
      for p in points {
        low = simd_min(low, p)
        high = simd_max(high, p)
      }
      func direction(_ azimuth: Float, _ elevation: Float) -> SIMD3<Float> {
        let e = elevation * .pi / 180
        return SIMD3(cos(e) * sin(azimuth), sin(e), cos(e) * cos(azimuth))
      }
      // Views with the plan's axes diagonal on screen: the four 45 degree views, and each
      // turned up to 15 degrees either way (the axes stay between 30 and 60 degrees). The
      // camera's horizontal direction is (sin azimuth, cos azimuth) in (x, z), so a direction
      // at angle phi has azimuth pi/2 - phi.
      let samples = visibilitySamples()
      var candidates: [(azimuth: Float, distance: Float, seen: Float, turn: Float)] = []
      for k in 0..<4 {
        for turn in [Float(0), -7.5, 7.5, -15, 15] {
          let phi = dominant + .pi / 4 + Float(k) * .pi / 2 + turn * .pi / 180
          let azimuth = .pi / 2 - phi
          let dir = direction(azimuth, elevation)
          let (target, distance) = ModelStyle.fit(points, direction: dir, aspect: aspect)
          let seen = visibility(samples, from: target + dir * distance)
          candidates.append((azimuth, distance, seen, turn))
        }
      }
      // The view that shows the plan largest, traded against how much of the floor and
      // furniture the near walls hide, with a slight preference for the plain 45 degree views.
      // Ties keep the first.
      let closest = candidates.map { $0.distance }.min()!
      var best = candidates[0]
      var bestScore = -Float.infinity
      for c in candidates {
        let score = 0.5 * c.seen - 2 * log(c.distance / closest) - 0.002 * abs(c.turn)
        if score > bestScore + 1e-4 {
          bestScore = score
          best = c
        }
      }
      let chosen = direction(best.azimuth, elevation)
      let (target, distance) = ModelStyle.fit(points, direction: chosen, aspect: aspect)
      // The key light falls square on the family of walls facing the camera's right.
      var keyAzimuth = best.azimuth + .pi / 4
      var bestGap = Float.infinity
      for k in 0..<4 {
        let a = .pi / 2 - dominant - Float(k) * .pi / 2
        var gap = (a - (best.azimuth + .pi / 4)).truncatingRemainder(dividingBy: 2 * .pi)
        if gap > .pi { gap -= 2 * .pi }
        if gap < -.pi { gap += 2 * .pi }
        if abs(gap) < bestGap - 1e-5 {
          bestGap = abs(gap)
          keyAzimuth = a
        }
      }
      return View(
        target: target, direction: chosen, distance: distance, azimuth: best.azimuth,
        keyAzimuth: keyAzimuth, fieldOfView: ModelStyle.fieldOfView,
        radius: simd_length(high - low) / 2)
    }

    /// Points whose view the near walls may block: five on the top of each object, and a grid
    /// over the floor. Objects and floor count the same in all.
    private func visibilitySamples() -> [(SIMD3<Float>, Float)] {
      var objectPoints: [SIMD3<Float>] = []
      for item in objects where !item.hidden && item.box.bottom - floorY < 1.5 {
        let b = item.box
        objectPoints.append(SIMD3(b.center.x, b.top, b.center.z))
        for (sx, sz) in [(Float(-0.7), Float(-0.7)), (0.7, -0.7), (-0.7, 0.7), (0.7, 0.7)] {
          let p = b.center2 + b.xAxis * (sx * b.half.x) + b.zAxis * (sz * b.half.z)
          objectPoints.append(SIMD3(p.x, b.top, p.y))
        }
      }
      var floorPoints: [SIMD3<Float>] = []
      if !floorTriangles.isEmpty {
        var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
        for (a, b, c) in floorTriangles {
          lo = simd_min(lo, simd_min(a, simd_min(b, c)))
          hi = simd_max(hi, simd_max(a, simd_max(b, c)))
        }
        if lo.x.isFinite, hi.x.isFinite, lo.y.isFinite, hi.y.isFinite {
          let step = max(0.4, max(hi.x - lo.x, hi.y - lo.y) / 40)
          var x = lo.x + step / 2
          while x < hi.x {
            var z = lo.y + step / 2
            while z < hi.y {
              let p = SIMD2(x, z)
              if floorContains(p) {
                floorPoints.append(SIMD3(x, floorY + 0.05, z))
              }
              z += step
            }
            x += step
          }
        }
      }
      let objectWeight: Float = objectPoints.isEmpty ? 0 : 1 / Float(objectPoints.count)
      let floorWeight: Float = floorPoints.isEmpty ? 0 : 1 / Float(floorPoints.count)
      return objectPoints.map { ($0, objectWeight) } + floorPoints.map { ($0, floorWeight) }
    }

    /// Weighted share of the samples with a clear line to the camera (only openings let the
    /// view through: doors are drawn shut and windows as frosted light).
    private func visibility(
      _ samples: [(SIMD3<Float>, Float)], from camera: SIMD3<Float>
    ) -> Float {
      var seen: Float = 0, total: Float = 0
      for (p, weight) in samples {
        total += weight
        if !blocked(p, camera) { seen += weight }
      }
      return total > 0 ? seen / total : 1
    }

    private func blocked(_ p: SIMD3<Float>, _ camera: SIMD3<Float>) -> Bool {
      let p2 = SIMD2(p.x, p.z), c2 = SIMD2(camera.x, camera.z)
      let ray = c2 - p2
      for (i, s) in segments.enumerated() {
        let v = s.b - s.a
        let den = ModelStyle.cross(ray, v)
        guard abs(den) > 1e-6 else { continue }
        let w = s.a - p2
        let t = ModelStyle.cross(w, v) / den
        let r = ModelStyle.cross(w, ray) / den
        guard t > 1e-3, t < 1, r >= 0, r <= 1 else { continue }
        let y = p.y + (camera.y - p.y) * t
        guard y >= s.bottom, y <= s.top else { continue }
        let u = r * s.length - s.length / 2, h = y - s.bottom
        let open = cuts[i].contains { c in
          c.kind == .opening && u >= c.u0 && u <= c.u1 && h >= c.v0 && h <= c.v1
        }
        if open { continue }
        return true
      }
      return false
    }
  }

  static func inside(
    _ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>
  ) -> Bool {
    let d1 = cross(b - a, p - a), d2 = cross(c - b, p - b), d3 = cross(a - c, p - c)
    let negative = d1 < 0 || d2 < 0 || d3 < 0, positive = d1 > 0 || d2 > 0 || d3 > 0
    return !(negative && positive)
  }

  /// Where to aim and how far back to stand so every point is on screen, leaving the side and
  /// end margins of the frame empty, in a view of the given aspect (the vertical field of view
  /// is fixed).
  static func fit(
    _ points: [SIMD3<Float>], direction: SIMD3<Float>, aspect: Float
  ) -> (target: SIMD3<Float>, distance: Float) {
    let forward = -simd_normalize(direction)
    let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
    let up = simd_cross(right, forward)
    let tanFull = tan(fieldOfView / 2 * .pi / 180)
    let tanV = tanFull * (1 - 2 * endMargin)
    let tanH = tanFull * aspect * (1 - 2 * sideMargin)
    var low = points[0], high = points[0]
    for p in points {
      low = simd_min(low, p)
      high = simd_max(high, p)
    }
    var target = (low + high) / 2
    func distance(for target: SIMD3<Float>) -> Float {
      var d: Float = 0.5
      for p in points {
        let q = p - target
        let z = simd_dot(q, forward)
        d = max(d, abs(simd_dot(q, right)) / tanH - z, abs(simd_dot(q, up)) / tanV - z)
      }
      return d
    }
    var d = distance(for: target)
    for _ in 0..<6 {
      var minX = Float.infinity, maxX = -Float.infinity
      var minY = Float.infinity, maxY = -Float.infinity
      for p in points {
        let q = p - target
        let depth = d + simd_dot(q, forward)
        guard depth > 1e-3 else { continue }
        let x = simd_dot(q, right) / depth, y = simd_dot(q, up) / depth
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
      }
      guard minX.isFinite, minY.isFinite else { break }
      target += right * ((minX + maxX) / 2 * d) + up * ((minY + maxY) / 2 * d)
      d = distance(for: target)
    }
    return (target, d)
  }

  // MARK: - Light and camera

  /// Bright, soft, low-contrast light: a strong ambient; a key falling square on one family of
  /// walls, so the two families of wall faces read clearly apart (about 0.96 against 0.80, as
  /// in Polycam's views); and a light from almost overhead that whitens the tops. No shadow
  /// maps: furniture gets a soft contact shadow of its own and walls a soft shade at their foot.
  static func addLights(to root: SCNNode, view: View) {
    let ambient = SCNNode()
    ambient.name = "ModelStyleAmbient"
    ambient.light = SCNLight()
    ambient.light!.type = .ambient
    ambient.light!.intensity = 660
    ambient.light!.color = UIColor(white: 1, alpha: 1)
    root.addChildNode(ambient)

    let reach = max(view.radius * 3, 5)
    func directional(_ name: String, azimuth: Float, elevation: Float, intensity: CGFloat) {
      let e = elevation * .pi / 180
      let dir = SIMD3(cos(e) * sin(azimuth), sin(e), cos(e) * cos(azimuth))
      let node = SCNNode()
      node.name = name
      let light = SCNLight()
      light.type = .directional
      light.intensity = intensity
      light.color = UIColor(red: 1, green: 1, blue: 0.99, alpha: 1)
      node.light = light
      node.simdPosition = view.target + dir * reach
      node.simdLook(at: view.target)
      root.addChildNode(node)
    }
    directional("ModelStyleKey", azimuth: view.keyAzimuth, elevation: 35, intensity: 440)
    directional("ModelStyleTop", azimuth: view.azimuth - 0.4, elevation: 80, intensity: 170)
  }

  static func makeCamera(_ view: View) -> SCNNode {
    let camera = SCNCamera()
    camera.projectionDirection = .vertical
    camera.fieldOfView = CGFloat(view.fieldOfView)
    camera.automaticallyAdjustsZRange = true
    camera.zNear = 0.05
    camera.zFar = Double(view.distance + view.radius * 4 + 10)
    let node = SCNNode()
    node.name = "ModelStyleCamera"
    node.camera = camera
    node.simdPosition = view.target + view.direction * view.distance
    node.simdLook(at: view.target)
    return node
  }
}
