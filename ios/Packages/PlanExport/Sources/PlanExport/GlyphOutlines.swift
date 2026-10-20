import Foundation

/// Glyph outlines of a TrueType font, read from its `head`, `maxp`, `hhea`, `hmtx`, `cmap`
/// (format 4), `loca` and `glyf` tables (composite glyphs resolved). The PNG preview draws its
/// labels with them in Inter, the Chapter sans the PDFs embed (`ChapterBrandAssets`).
struct GlyphOutlines: Sendable {
  /// A contour point in font units, y up. Off-curve points are quadratic control points.
  struct ContourPoint: Sendable {
    var x: Double
    var y: Double
    var onCurve: Bool
  }

  static let interRegular = GlyphOutlines(data: ChapterBrandAssets.interRegular.data)
  static let interSemiBold = GlyphOutlines(data: ChapterBrandAssets.interSemiBold.data)

  let unitsPerEm: Double
  /// Contours of each glyph, by glyph index.
  let glyphs: [[[ContourPoint]]]
  /// Advance width of each glyph, font units.
  let advances: [Double]
  /// Unicode scalar value to glyph index (glyph 0, `.notdef`, is left out).
  let characters: [UInt32: Int]

  init(data: Data) {
    let font = Reader(bytes: [UInt8](data))
    var tables: [String: Int] = [:]
    for index in 0..<font.u16(4) {
      let record = 12 + 16 * index
      let tag = String(decoding: (0..<4).map { font.u8(record + $0) }, as: UTF8.self)
      tables[tag] = font.u32(record + 8)
    }
    let head = tables["head"] ?? -1
    unitsPerEm = Double(max(1, font.u16(head + 18)))
    let longOffsets = font.i16(head + 50) == 1
    let glyphCount = font.u16((tables["maxp"] ?? -1) + 4)

    let metricsCount = font.u16((tables["hhea"] ?? -1) + 34)
    let hmtx = tables["hmtx"] ?? -1
    var advances: [Double] = []
    for index in 0..<glyphCount {
      advances.append(Double(font.u16(hmtx + 4 * min(index, max(0, metricsCount - 1)))))
    }
    self.advances = advances

    let loca = tables["loca"] ?? -1
    let offsets = (0...glyphCount).map {
      longOffsets ? font.u32(loca + 4 * $0) : 2 * font.u16(loca + 2 * $0)
    }
    let glyf = tables["glyf"] ?? -1
    func outline(_ index: Int, depth: Int) -> [[ContourPoint]] {
      guard index >= 0, index < glyphCount, depth < 8, offsets[index + 1] > offsets[index],
        glyf >= 0
      else { return [] }  // out of range, or no outline (the space)
      let start = glyf + offsets[index]
      let contourCount = font.i16(start)
      if contourCount >= 0 { return font.simpleGlyph(at: start, contours: contourCount) }
      var contours: [[ContourPoint]] = []
      var p = start + 10
      while true {
        let flags = font.u16(p)
        let component = font.u16(p + 2)
        p += 4
        var dx: Double
        var dy: Double
        if flags & 0x0001 != 0 {
          dx = Double(font.i16(p))
          dy = Double(font.i16(p + 2))
          p += 4
        } else {
          dx = Double(Int8(bitPattern: font.u8(p)))
          dy = Double(Int8(bitPattern: font.u8(p + 1)))
          p += 2
        }
        // Without ARGS_ARE_XY_VALUES the arguments are points to match, which Inter never uses.
        if flags & 0x0002 == 0 {
          dx = 0
          dy = 0
        }
        // Component transform: x' = a x + c y + dx, y' = b x + d y + dy.
        var (a, b, c, d) = (1.0, 0.0, 0.0, 1.0)
        func f2dot14(_ at: Int) -> Double { Double(font.i16(at)) / 16384 }
        if flags & 0x0008 != 0 {
          a = f2dot14(p)
          d = a
          p += 2
        } else if flags & 0x0040 != 0 {
          a = f2dot14(p)
          d = f2dot14(p + 2)
          p += 4
        } else if flags & 0x0080 != 0 {
          (a, b, c, d) = (f2dot14(p), f2dot14(p + 2), f2dot14(p + 4), f2dot14(p + 6))
          p += 8
        }
        for contour in outline(component, depth: depth + 1) {
          contours.append(
            contour.map {
              ContourPoint(
                x: a * $0.x + c * $0.y + dx, y: b * $0.x + d * $0.y + dy, onCurve: $0.onCurve)
            })
        }
        if flags & 0x0020 == 0 || p >= font.bytes.count { break }  // no MORE_COMPONENTS
      }
      return contours
    }
    glyphs = (0..<glyphCount).map { outline($0, depth: 0) }
    characters = font.characterMap(at: tables["cmap"] ?? -1)
  }

  /// The glyph index of `scalar`, `?` when the font has none.
  func glyph(for scalar: Unicode.Scalar) -> Int {
    characters[scalar.value] ?? characters[UInt32(UInt8(ascii: "?"))] ?? 0
  }

  /// Glyph `index` as closed polygons: curves split until they stray less than `tolerance`
  /// font units from the curve, each point then mapped by `place` from font units (y up).
  func polygons(glyph index: Int, tolerance: Double, place: (Double, Double) -> Point2)
    -> [[Point2]]
  {
    guard index >= 0, index < glyphs.count else { return [] }
    return glyphs[index].compactMap { contour in
      guard contour.count >= 2 else { return nil }
      // Start on an on-curve point, or between the first and last when every point is off.
      var points = contour
      var start: ContourPoint
      if let first = contour.firstIndex(where: \.onCurve) {
        points = Array(contour[(first + 1)...] + contour[..<first])
        start = contour[first]
      } else {
        let last = contour[contour.count - 1]
        start = ContourPoint(
          x: (last.x + contour[0].x) / 2, y: (last.y + contour[0].y) / 2, onCurve: true)
      }
      points.append(start)
      var polygon = [place(start.x, start.y)]
      var current = start
      var control: ContourPoint?
      func curve(to end: ContourPoint, via middle: ContourPoint) {
        // A quadratic strays at most |p0 - 2 p1 + p2| / 4 from its chord, n^2 times less when
        // split into n equal steps.
        let deviation =
          hypot(current.x - 2 * middle.x + end.x, current.y - 2 * middle.y + end.y) / 4
        let split = (deviation / max(tolerance, 1e-9)).squareRoot().rounded(.up)
        let steps = min(16, max(1, Int(split)))
        for step in 1...steps {
          let t = Double(step) / Double(steps)
          let u = 1 - t
          polygon.append(
            place(
              u * u * current.x + 2 * u * t * middle.x + t * t * end.x,
              u * u * current.y + 2 * u * t * middle.y + t * t * end.y))
        }
      }
      for point in points {
        if point.onCurve {
          if let middle = control {
            curve(to: point, via: middle)
          } else {
            polygon.append(place(point.x, point.y))
          }
          current = point
          control = nil
        } else {
          if let middle = control {
            // Two off-curve points in a row imply an on-curve point halfway between them.
            let implied = ContourPoint(
              x: (middle.x + point.x) / 2, y: (middle.y + point.y) / 2, onCurve: true)
            curve(to: implied, via: middle)
            current = implied
          }
          control = point
        }
      }
      return polygon
    }
  }

  /// Big-endian reads that return 0 outside the data, so a damaged font draws nothing rather
  /// than crashing.
  private struct Reader {
    let bytes: [UInt8]

    func u8(_ at: Int) -> UInt8 { at >= 0 && at < bytes.count ? bytes[at] : 0 }
    func u16(_ at: Int) -> Int { Int(u8(at)) << 8 | Int(u8(at + 1)) }
    func i16(_ at: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(at)))) }
    func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }

    /// Contours of a simple glyph whose header starts at `start`.
    func simpleGlyph(at start: Int, contours count: Int) -> [[ContourPoint]] {
      let ends = (0..<count).map { u16(start + 10 + 2 * $0) }
      let pointCount = (ends.last ?? -1) + 1
      var p = start + 10 + 2 * count
      p += 2 + u16(p)  // instructions
      var flags: [UInt8] = []
      while flags.count < pointCount && p < bytes.count {
        let flag = u8(p)
        p += 1
        flags.append(flag)
        if flag & 0x08 != 0 {  // REPEAT_FLAG
          flags += [UInt8](repeating: flag, count: Int(u8(p)))
          p += 1
        }
      }
      flags = Array(flags.prefix(pointCount))
      guard flags.count == pointCount else { return [] }
      // Coordinates are deltas: one unsigned byte with its sign in `same` when `short` is set,
      // else a signed 16-bit value, or no change when `same` is set.
      func coordinates(short: UInt8, same: UInt8) -> [Double] {
        var value = 0
        var out: [Double] = []
        for flag in flags {
          if flag & short != 0 {
            value += flag & same != 0 ? Int(u8(p)) : -Int(u8(p))
            p += 1
          } else if flag & same == 0 {
            value += i16(p)
            p += 2
          }
          out.append(Double(value))
        }
        return out
      }
      let xs = coordinates(short: 0x02, same: 0x10)
      let ys = coordinates(short: 0x04, same: 0x20)
      var contours: [[ContourPoint]] = []
      var first = 0
      for end in ends {
        guard end >= first, end < pointCount else { break }
        contours.append(
          (first...end).map {
            ContourPoint(x: xs[$0], y: ys[$0], onCurve: flags[$0] & 0x01 != 0)
          })
        first = end + 1
      }
      return contours
    }

    /// Unicode to glyph index from the `cmap` table at `start`: its Windows Unicode (3, 1) or
    /// Unicode (0, x) format 4 subtable.
    func characterMap(at start: Int) -> [UInt32: Int] {
      guard start >= 0 else { return [:] }
      var subtable: Int?
      for index in 0..<u16(start + 2) {
        let record = start + 4 + 8 * index
        let platform = u16(record)
        let encoding = u16(record + 2)
        let offset = start + u32(record + 4)
        guard u16(offset) == 4, platform == 0 || (platform == 3 && encoding == 1) else {
          continue
        }
        subtable = offset
        if platform == 3 { break }
      }
      guard let table = subtable else { return [:] }
      let segments = u16(table + 6) / 2
      let ends = table + 14
      let starts = ends + 2 * segments + 2
      let deltas = starts + 2 * segments
      let rangeOffsets = deltas + 2 * segments
      var map: [UInt32: Int] = [:]
      for segment in 0..<segments {
        let first = u16(starts + 2 * segment)
        let last = u16(ends + 2 * segment)
        let delta = u16(deltas + 2 * segment)
        let rangeOffset = u16(rangeOffsets + 2 * segment)
        guard first <= last, first != 0xFFFF else { continue }
        for code in first...last {
          var glyph: Int
          if rangeOffset == 0 {
            glyph = (code + delta) & 0xFFFF
          } else {
            glyph = u16(rangeOffsets + 2 * segment + rangeOffset + 2 * (code - first))
            if glyph != 0 { glyph = (glyph + delta) & 0xFFFF }
          }
          if glyph != 0 { map[UInt32(code)] = glyph }
        }
      }
      return map
    }
  }
}
