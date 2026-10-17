import CaptureContract
import Foundation

/// ASCII DXF R2013 (AC1027) floor plan, one file per capture (floor or area).
///
/// - Units are millimetres (`$INSUNITS` 4). Plan y is the model's -z.
/// - Plan geometry only: no mesh, no points. Entities are LINE, ARC, LWPOLYLINE and TEXT.
/// - Layers: `A-WALL` wall centrelines (plus an outline polyline when the wall has thickness),
///   `A-DOOR` door span and swing arc, `A-GLAZ` window spans, `A-OPEN` openings without a door
///   or window, `A-AREA` closed room outlines, `A-ANNO-TEXT` room labels and areas,
///   `A-FLOR-OBJ` object footprints.
/// - A wall listed twice at the same place (RoomPlan lists a shared partition once per room)
///   is drawn once, so the number of A-WALL lines can be smaller than the model's wall count.
public enum DXFWriter {
  public static let layers = [
    "A-WALL", "A-DOOR", "A-GLAZ", "A-OPEN", "A-AREA", "A-ANNO-TEXT", "A-FLOR-OBJ",
  ]
  public static let fileName = "plan.dxf"

  static let layerColors = [
    "A-WALL": 7, "A-DOOR": 3, "A-GLAZ": 5, "A-OPEN": 8, "A-AREA": 1, "A-ANNO-TEXT": 2,
    "A-FLOR-OBJ": 6,
  ]

  public static func write(model: CaptureModel) throws -> ExportedFile {
    let geometry = try PlanGeometry(model: model)
    let text = render(geometry: geometry)
    return ExportedFile(
      fileName: fileName, role: .planDXF, mime: "image/vnd.dxf", data: Data(text.utf8))
  }

  // MARK: Rendering

  private static let mm = 1000.0

  private struct Builder {
    private(set) var lines: [String] = []
    var handle: Int

    mutating func group(_ code: Int, _ value: String) {
      let label = String(code)
      lines.append(String(repeating: " ", count: max(0, 3 - label.count)) + label)
      lines.append(value)
    }

    mutating func group(_ code: Int, _ value: Int) { group(code, String(value)) }

    mutating func nextHandle() -> String {
      handle += 1
      return String(handle, radix: 16, uppercase: true)
    }

    var seed: String { String(handle + 1, radix: 16, uppercase: true) }

    var text: String { lines.joined(separator: "\n") + "\n" }

    mutating func entity(_ type: String, layer: String, subclass: String) {
      group(0, type)
      group(5, nextHandle())
      group(330, "1F")
      group(100, "AcDbEntity")
      group(8, layer)
      group(100, subclass)
    }

    mutating func point(_ base: Int, _ p: Point2) {
      group(base, Format.fixed(p.x, 3))
      group(base + 10, Format.fixed(p.y, 3))
    }
  }

  /// Plan point in millimetres.
  private static func mmPoint(_ p: Point2) -> Point2 { Point2(x: p.x * mm, y: p.y * mm) }

  /// DXF TEXT value: ASCII only, other characters as `\U+XXXX`.
  static func dxfText(_ text: String) -> String {
    var out = ""
    for scalar in Format.singleLine(text).unicodeScalars.prefix(250) {
      if scalar.value < 0x80 {
        out.unicodeScalars.append(scalar)
      } else if scalar.value <= 0xFFFF {
        let hex = String(scalar.value, radix: 16, uppercase: true)
        out += "\\U+" + String(repeating: "0", count: 4 - hex.count) + hex
      } else {
        out += "?"
      }
    }
    return out
  }

  private static func render(geometry: PlanGeometry) -> String {
    var body = Builder(handle: 0x2FF)
    var extent: PlanBounds?
    func grow(_ p: Point2) {
      if extent == nil {
        extent = PlanBounds(minX: p.x, minY: p.y, maxX: p.x, maxY: p.y)
      } else {
        extent?.grow(p)
      }
    }
    func line(_ layer: String, _ a: Point2, _ b: Point2) {
      grow(a)
      grow(b)
      body.entity("LINE", layer: layer, subclass: "AcDbLine")
      body.point(10, a)
      body.group(30, "0.0")
      body.point(11, b)
      body.group(31, "0.0")
    }
    func polyline(_ layer: String, _ points: [Point2]) {
      body.entity("LWPOLYLINE", layer: layer, subclass: "AcDbPolyline")
      body.group(90, points.count)
      body.group(70, 1)
      for p in points {
        grow(p)
        body.point(10, p)
      }
    }
    func label(_ at: Point2, height: Double, _ value: String) {
      grow(at)
      body.entity("TEXT", layer: "A-ANNO-TEXT", subclass: "AcDbText")
      body.point(10, at)
      body.group(30, "0.0")
      body.group(40, Format.fixed(height, 3))
      body.group(1, dxfText(value))
      body.group(7, "Standard")
      body.group(72, 1)
      body.point(11, at)
      body.group(31, "0.0")
      body.group(100, "AcDbText")
    }

    for wall in geometry.walls {
      line("A-WALL", mmPoint(wall.start), mmPoint(wall.end))
      if wall.thickness > 0, wall.length > 0 {
        let normal = (wall.end - wall.start).unit.leftNormal * (wall.thickness / 2)
        polyline(
          "A-WALL",
          [
            wall.start + normal, wall.end + normal, wall.end - normal, wall.start - normal,
          ].map(mmPoint))
      }
    }

    let roomsById = Dictionary(geometry.rooms.map { ($0.id, $0) }) { first, _ in first }
    for opening in geometry.openings {
      let from = mmPoint(opening.from)
      let to = mmPoint(opening.to)
      switch opening.kind {
      case .door:
        line("A-DOOR", from, to)
        // Swing: quarter circle around the hinge (span start), into the room the wall bounds.
        let span = to - from
        let angle = atan2(span.y, span.x) * 180 / .pi
        var leftward = true
        if let id = opening.roomIds.first, let room = roomsById[id] {
          let middle = (from + to) * 0.5
          leftward = span.leftNormal.dot(mmPoint(room.labelPoint) - middle) >= 0
        }
        let start = leftward ? angle : angle - 90
        body.entity("ARC", layer: "A-DOOR", subclass: "AcDbCircle")
        body.point(10, from)
        body.group(30, "0.0")
        body.group(40, Format.fixed(opening.widthM * mm, 3))
        body.group(100, "AcDbArc")
        body.group(50, Format.fixed(normalizedDegrees(start), 3))
        body.group(51, Format.fixed(normalizedDegrees(start + 90), 3))
        let radius = opening.widthM * mm
        grow(Point2(x: from.x - radius, y: from.y - radius))
        grow(Point2(x: from.x + radius, y: from.y + radius))
      case .window:
        line("A-GLAZ", from, to)
      case .opening:
        line("A-OPEN", from, to)
      }
    }

    for room in geometry.rooms {
      polyline("A-AREA", room.polygon.map(mmPoint))
      let at = mmPoint(room.labelPoint)
      label(at, height: 150, room.label)
      label(Point2(x: at.x, y: at.y - 250), height: 120, "\(Format.fixed(room.areaM2, 2)) m2")
    }

    for object in geometry.objects {
      polyline("A-FLOR-OBJ", object.corners.map(mmPoint))
    }

    let extentBox = extent ?? PlanBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)

    var out = Builder(handle: 0)
    out.group(0, "SECTION")
    out.group(2, "HEADER")
    out.group(9, "$ACADVER")
    out.group(1, "AC1027")
    out.group(9, "$HANDSEED")
    out.group(5, body.seed)
    out.group(9, "$EXTMIN")
    out.group(10, Format.fixed(extentBox.minX, 3))
    out.group(20, Format.fixed(extentBox.minY, 3))
    out.group(30, "0.0")
    out.group(9, "$EXTMAX")
    out.group(10, Format.fixed(extentBox.maxX, 3))
    out.group(20, Format.fixed(extentBox.maxY, 3))
    out.group(30, "0.0")
    out.group(9, "$LUNITS")
    out.group(70, 2)
    out.group(9, "$MEASUREMENT")
    out.group(70, 1)
    out.group(9, "$INSUNITS")
    out.group(70, 4)
    out.group(0, "ENDSEC")

    out.group(0, "SECTION")
    out.group(2, "CLASSES")
    out.group(0, "ENDSEC")

    out.group(0, "SECTION")
    out.group(2, "TABLES")
    func table(_ name: String, handle: String, count: Int, records: (inout Builder) -> Void) {
      out.group(0, "TABLE")
      out.group(2, name)
      out.group(5, handle)
      out.group(330, "0")
      out.group(100, "AcDbSymbolTable")
      out.group(70, count)
      records(&out)
      out.group(0, "ENDTAB")
    }
    table("LTYPE", handle: "5", count: 3) { b in
      for (handle, name, description) in [
        ("14", "ByBlock", ""), ("15", "ByLayer", ""), ("16", "Continuous", "Solid line"),
      ] {
        b.group(0, "LTYPE")
        b.group(5, handle)
        b.group(330, "5")
        b.group(100, "AcDbSymbolTableRecord")
        b.group(100, "AcDbLinetypeTableRecord")
        b.group(2, name)
        b.group(70, 0)
        b.group(3, description)
        b.group(72, 65)
        b.group(73, 0)
        b.group(40, "0.0")
      }
    }
    table("LAYER", handle: "2", count: layers.count + 1) { b in
      func layer(_ handle: String, _ name: String, color: Int) {
        b.group(0, "LAYER")
        b.group(5, handle)
        b.group(330, "2")
        b.group(100, "AcDbSymbolTableRecord")
        b.group(100, "AcDbLayerTableRecord")
        b.group(2, name)
        b.group(70, 0)
        b.group(62, color)
        b.group(6, "Continuous")
      }
      layer("10", "0", color: 7)
      for (index, name) in layers.enumerated() {
        layer(String(0x20 + index, radix: 16, uppercase: true), name, color: layerColors[name] ?? 7)
      }
    }
    table("STYLE", handle: "3", count: 1) { b in
      b.group(0, "STYLE")
      b.group(5, "11")
      b.group(330, "3")
      b.group(100, "AcDbSymbolTableRecord")
      b.group(100, "AcDbTextStyleTableRecord")
      b.group(2, "Standard")
      b.group(70, 0)
      b.group(40, "0.0")
      b.group(41, "1.0")
      b.group(50, "0.0")
      b.group(71, 0)
      b.group(42, "2.5")
      b.group(3, "txt")
      b.group(4, "")
    }
    table("APPID", handle: "9", count: 1) { b in
      b.group(0, "APPID")
      b.group(5, "12")
      b.group(330, "9")
      b.group(100, "AcDbSymbolTableRecord")
      b.group(100, "AcDbRegAppTableRecord")
      b.group(2, "ACAD")
      b.group(70, 0)
    }
    table("BLOCK_RECORD", handle: "1", count: 2) { b in
      for (handle, name) in [("1F", "*Model_Space"), ("1B", "*Paper_Space")] {
        b.group(0, "BLOCK_RECORD")
        b.group(5, handle)
        b.group(330, "1")
        b.group(100, "AcDbSymbolTableRecord")
        b.group(100, "AcDbBlockTableRecord")
        b.group(2, name)
        b.group(70, 0)
        b.group(280, 1)
        b.group(281, 0)
      }
    }
    out.group(0, "ENDSEC")

    out.group(0, "SECTION")
    out.group(2, "BLOCKS")
    for (record, name, begin, end, paper) in [
      ("1F", "*Model_Space", "20F", "210", false), ("1B", "*Paper_Space", "1C", "1D", true),
    ] {
      out.group(0, "BLOCK")
      out.group(5, begin)
      out.group(330, record)
      out.group(100, "AcDbEntity")
      if paper { out.group(67, 1) }
      out.group(8, "0")
      out.group(100, "AcDbBlockBegin")
      out.group(2, name)
      out.group(70, 0)
      out.group(10, "0.0")
      out.group(20, "0.0")
      out.group(30, "0.0")
      out.group(3, name)
      out.group(1, "")
      out.group(0, "ENDBLK")
      out.group(5, end)
      out.group(330, record)
      out.group(100, "AcDbEntity")
      if paper { out.group(67, 1) }
      out.group(8, "0")
      out.group(100, "AcDbBlockEnd")
    }
    out.group(0, "ENDSEC")

    out.group(0, "SECTION")
    out.group(2, "ENTITIES")
    let entities = body.text

    var objects = Builder(handle: 0)
    objects.group(0, "ENDSEC")
    objects.group(0, "SECTION")
    objects.group(2, "OBJECTS")
    objects.group(0, "DICTIONARY")
    objects.group(5, "C")
    objects.group(330, "0")
    objects.group(100, "AcDbDictionary")
    objects.group(281, 1)
    objects.group(0, "ENDSEC")
    objects.group(0, "EOF")
    return out.text + entities + objects.text
  }

  private static func normalizedDegrees(_ degrees: Double) -> Double {
    var value = degrees.truncatingRemainder(dividingBy: 360)
    if value < 0 { value += 360 }
    return value
  }
}
