import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// Swift ↔ TypeScript parity goldens (spatial-report §11.2, critique R-35): the station's
/// spatial report ports PlanExport's measurements, formats, room fill rule and north symbol to
/// TypeScript, and must print the same numbers as the phone's plan sheet. This test writes what
/// PlanExport computes for every good fixture capture to `fixtures/report-parity/
/// {fixture}-{areaKey}.json`, and the rule cases to `fixtures/report-parity/rules.json`;
/// the station's `metrics-parity.test.ts` compares its port with them (numbers within 1e-9
/// relative, strings exactly).
///
/// Run with `UPDATE_PARITY_GOLDENS=1` to rewrite the goldens after a deliberate change to
/// `RoomMetrics`, `PlanTotals`, `UnitFormatter`, the fill rule or the north symbol; otherwise
/// a difference fails the test.
final class ReportParityGoldenTests: XCTestCase {
  static let folder = Repo.root.appendingPathComponent("fixtures/report-parity")
  static var updating: Bool { ProcessInfo.processInfo.environment["UPDATE_PARITY_GOLDENS"] == "1" }

  // MARK: Golden shape

  struct Size: Codable, Equatable {
    var widthM: Double
    var heightM: Double
    var depthM: Double
  }

  struct Opening: Codable, Equatable {
    var id: String
    var type: String
    var widthM: Double
    var heightM: Double
    var areaM2: Double
  }

  struct Object: Codable, Equatable {
    var id: String
    var category: String
    var sizeM: Size
  }

  struct Rectangle: Codable, Equatable {
    var alongM: Double
    var acrossM: Double
    var angleRadians: Double?
  }

  struct Ceiling: Codable, Equatable {
    var heightM: Double
    var approximate: Bool
    var reasons: [String]
  }

  struct RoomFormats: Codable, Equatable {
    /// `UnitFormatter.sheetArea`, the sheet's and the report's room area.
    var floorArea: String
    var floorAreaMetric: String
    /// Bounding box and inscribed rectangle, larger side first, ft-in to 0.1 in.
    var boundingBox: String
    var inscribed: String
    var perimeter: String
    var ceiling: String
    /// The plan sheet's room dimension values (`UnitFormatter.dimension`).
    var alongDimension: String
    var acrossDimension: String
  }

  struct Room: Codable, Equatable {
    var id: String
    var label: String
    var type: String?
    var fillClass: String
    var floorAreaM2: Double
    var perimeterM: Double
    var bbox: Rectangle
    var inscribed: Rectangle
    var ceiling: Ceiling
    var volumeM3: Double
    var wallAreaInclM2: Double
    var wallAreaExclM2: Double
    var openings: [Opening]
    var objects: [Object]
    var formatted: RoomFormats
  }

  struct Totals: Codable, Equatable {
    var roomCount: Int
    var scannedRooms: Int
    var bedrooms: Int
    var bathrooms: Int
    var livableAreaM2: Double
    var wallAreaM2: Double
    var windowAreaM2: Double
    var volumeM3: Double
    var volumeIsApproximate: Bool
    var perimeterM: Double
    /// The sheet's "Floor area, sum of rooms" value and the report's floor area.
    var floorArea: String
  }

  struct Symbol: Codable, Equatable {
    var kind: String
    var angleCcw: Double?
    var approximate: Bool?
    var lines: [String]?
    var box: String?
    var caption: String?

    init(_ symbol: NorthSymbol) {
      switch symbol {
      case .arrow(let angle, let approximate, let line1, let line2):
        kind = "arrow"
        angleCcw = angle
        self.approximate = approximate
        lines = [line1, line2]
      case .notVerified(let box, let caption):
        kind = "not_verified"
        self.box = box
        self.caption = caption
      }
    }
  }

  struct North: Codable, Equatable {
    /// `compassState(capture)`: verified, approximate or not_verified, with the reason.
    var state: String
    var reason: String?
    /// The floor's dominant angle (`MetricsGeometry.dominantAngle` of its rooms), degrees
    /// counter-clockwise: the spatial report squares the floor by turning it clockwise by it.
    var dominantAngleDeg: Double
    /// The symbol on an unturned drawing, and on the report's drawing (ρ = −dominant angle).
    var unturned: Symbol
    var report: Symbol
  }

  struct Capture: Codable, Equatable {
    var fixture: String
    var captureId: String
    var areaKey: String
    var label: String
    var mode: String
    var rooms: [Room]
    var totals: Totals
    var north: North
  }

  // MARK: Building

  /// The good fixtures (`index.json` fixtures and samples; the legacy package is left out).
  static func fixtureNames() throws -> [String] {
    struct Index: Decodable {
      struct Entry: Decodable { var name: String }
      var fixtures: [Entry]
      var samples: [Entry]?
    }
    let index = try JSONDecoder().decode(
      Index.self,
      from: Data(contentsOf: Repo.root.appendingPathComponent("fixtures/generated/index.json")))
    return index.fixtures.map(\.name) + (index.samples ?? []).map(\.name)
  }

  static func feetInches(_ metres: Double) -> String {
    UnitFormatter.length(metres, style: .feetInchesTenths)
  }

  /// A rectangle's sides, larger first, ` × ` between.
  static func pair(_ rectangle: MeasuredRectangle) -> String {
    "\(feetInches(rectangle.longM)) \u{D7} \(feetInches(rectangle.shortM))"
  }

  static func capture(_ fixture: FixtureCapture) throws -> Capture {
    let model = fixture.model
    let metrics = try PlanMetrics(model)
    let geometry = try PlanGeometry(model: model)
    let recordCapture = try XCTUnwrap(
      fixture.record.captures.first { $0.captureId == model.captureId })
    let rooms = metrics.rooms.map { room -> Room in
      let objects = geometry.objects.filter { $0.roomId == room.roomId }.map(\.category)
      let modelType = model.rooms.first { $0.id == room.roomId }?.type
      let fillClass = RoomFillClass.of(
        label: room.label, type: modelType, objects: objects, mode: recordCapture.mode)
      return Room(
        id: room.roomId, label: room.label, type: modelType?.rawValue,
        fillClass: fillClass.rawValue, floorAreaM2: room.floorAreaM2, perimeterM: room.perimeterM,
        bbox: Rectangle(
          alongM: room.boundingBox.alongM, acrossM: room.boundingBox.acrossM,
          angleRadians: room.boundingBox.angleRadians),
        inscribed: Rectangle(
          alongM: room.inscribed.alongM, acrossM: room.inscribed.acrossM, angleRadians: nil),
        ceiling: Ceiling(
          heightM: room.ceiling.heightM, approximate: room.ceiling.isApproximate,
          reasons: room.ceiling.approximateReasons.map(\.rawValue)),
        volumeM3: room.volumeM3, wallAreaInclM2: room.wallAreaIncludingOpeningsM2,
        wallAreaExclM2: room.wallAreaExcludingOpeningsM2,
        openings: room.openings.map {
          Opening(
            id: $0.id, type: $0.type.rawValue, widthM: $0.widthM, heightM: $0.heightM,
            areaM2: $0.areaM2)
        },
        objects: room.objects.map {
          Object(
            id: $0.id, category: $0.category.rawValue,
            sizeM: Size(widthM: $0.widthM, heightM: $0.heightM, depthM: $0.depthM))
        },
        formatted: RoomFormats(
          floorArea: UnitFormatter.sheetArea(room.floorAreaM2),
          floorAreaMetric: UnitFormatter.sheetMetricArea(room.floorAreaM2),
          boundingBox: pair(room.boundingBox), inscribed: pair(room.inscribed),
          perimeter: feetInches(room.perimeterM), ceiling: feetInches(room.ceiling.heightM),
          alongDimension: UnitFormatter(system: .imperial).dimension(room.boundingBox.alongM),
          acrossDimension: UnitFormatter(system: .imperial).dimension(room.boundingBox.acrossM)))
    }
    let totals = metrics.totals
    let summary = PlanSheetSummary(metrics: metrics)
    let state = CompassState(recordCapture)
    let dominant =
      MetricsGeometry.dominantAngle(of: geometry.rooms.map(\.polygon)) * 180 / .pi
    let stateName: String
    switch state {
    case .verified: stateName = "verified"
    case .approximate: stateName = "approximate"
    case .notVerified: stateName = "not_verified"
    }
    return Capture(
      fixture: fixture.fixture, captureId: model.captureId.rawValue, areaKey: model.areaKey,
      label: recordCapture.label, mode: recordCapture.mode.rawValue, rooms: rooms,
      totals: Totals(
        roomCount: totals.roomCount, scannedRooms: summary.scannedRooms,
        bedrooms: totals.bedrooms, bathrooms: totals.bathrooms,
        livableAreaM2: totals.livableAreaM2, wallAreaM2: totals.wallAreaM2,
        windowAreaM2: totals.windowAreaM2, volumeM3: totals.volumeM3,
        volumeIsApproximate: totals.volumeIsApproximate, perimeterM: totals.perimeterM,
        floorArea: summary.floorAreaM2.map {
          "\(UnitFormatter.sheetArea($0)) \u{B7} \(UnitFormatter.sheetMetricArea($0))"
        } ?? "not captured"),
      north: North(
        state: stateName, reason: state.reason?.rawValue, dominantAngleDeg: dominant,
        unturned: Symbol(NorthSymbol(state: state)),
        report: Symbol(NorthSymbol(state: state, drawingRotationCCW: -dominant))))
  }

  // MARK: Rules

  struct FillCase: Codable, Equatable {
    var label: String
    var type: String?
    var objects: [String]
    var mode: String
    var fillClass: String
  }

  struct FormatCase: Codable, Equatable {
    var metres: Double
    var length: String
    var dimension: String
  }

  struct AreaCase: Codable, Equatable {
    var squareMetres: Double
    var area: String
    var metric: String
  }

  struct Rules: Codable, Equatable {
    var description: String
    var fill: [FillCase]
    var lengths: [FormatCase]
    var areas: [AreaCase]
  }

  static func rules() -> Rules {
    let fillInputs: [(String, RoomType?, [ObjectCategory], CaptureMode)] = [
      ("Bedroom 2", .bedroom, [], .floor), ("Living Room", nil, [], .floor),
      ("Study", nil, [], .floor), ("Lounge", nil, [], .floor), ("Bathroom", .bathroom, [], .floor),
      ("Kitchen", nil, [], .floor), ("Laundry", .laundry, [], .floor), ("WC", nil, [], .floor),
      ("Shower", nil, [], .floor), ("Shower", .bathroom, [], .floor),
      ("Shower", .closet, [], .floor), ("Closet", .closet, [.toilet], .floor),
      ("Pantry", nil, [.stove], .floor), ("Hallway", .hallway, [], .floor),
      ("Room 3", nil, [], .floor), ("Room 3", nil, [.bed], .floor),
      ("Room 3", .other, [.toilet], .floor), ("Room 4", nil, [.washerDryer, .bed], .floor),
      ("Room 5", nil, [.storage, .sofa], .floor), ("Balcony", nil, [], .floor),
      ("Roof terrace", .livingRoom, [], .floor), ("Bedroom", .bedroom, [], .exterior),
      ("Room Mexico", .bedroom, [.bed], .room), ("Guest suite", nil, [.bed], .floor),
    ]
    let fill = fillInputs.map { label, type, objects, mode in
      FillCase(
        label: label, type: type?.rawValue, objects: objects.map(\.rawValue), mode: mode.rawValue,
        fillClass: RoomFillClass.of(label: label, type: type, objects: objects, mode: mode)
          .rawValue)
    }
    let formatter = UnitFormatter(system: .imperial)
    let lengths = [0.0, 0.0254, 0.12954, 0.303784, 0.3048, 1.2192, 3.299, 4.0, 4.3048, 6.237, 10.7,
      0.0012700, 0.00127001,
    ].map {
      FormatCase(metres: $0, length: feetInches($0), dimension: formatter.dimension($0))
    }
    let areas = [0.0, 1.291, 12.0, 17.409293, 74.97, 203.9, 1000.0, 0.0046452].map {
      AreaCase(
        squareMetres: $0, area: UnitFormatter.sheetArea($0),
        metric: UnitFormatter.sheetMetricArea($0))
    }
    return Rules(
      description:
        "Room fill rule (plan-sheet 3.4.1 + exterior captures, critique R-35), with the 1.0.0 "
        + "type taken from the label when the model has none (FloorPlanStyle.type(fromLabel:)); "
        + "lengths UnitFormatter feet-inches to 0.1 in and the plan sheet dimension (inches "
        + "alone under a foot); areas in sq ft and m2 to one decimal with thousands separators.",
      fill: fill, lengths: lengths, areas: areas)
  }

  // MARK: Comparing

  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  /// Writes `value` to `name` when updating; otherwise compares it with the golden: every
  /// string and flag equal, every number within 1e-9 relative (1e-12 absolute).
  func check<T: Codable>(
    _ value: T, name: String, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let url = Self.folder.appendingPathComponent(name)
    let data = try Self.encoder().encode(value)
    if Self.updating {
      try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
      try (data + Data("\n".utf8)).write(to: url)
      return
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      XCTFail("\(name) is missing: run with UPDATE_PARITY_GOLDENS=1", file: file, line: line)
      return
    }
    let golden = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let actual = try JSONSerialization.jsonObject(with: data)
    var differences: [String] = []
    Self.compare(golden, actual, path: name, into: &differences)
    XCTAssertTrue(
      differences.isEmpty, differences.prefix(20).joined(separator: "\n"), file: file, line: line)
  }

  static func compare(_ a: Any, _ b: Any, path: String, into differences: inout [String]) {
    switch (a, b) {
    case (let a as [String: Any], let b as [String: Any]):
      for key in Set(a.keys).union(b.keys).sorted() {
        guard let x = a[key], let y = b[key] else {
          differences.append("\(path).\(key): only in one")
          continue
        }
        compare(x, y, path: "\(path).\(key)", into: &differences)
      }
    case (let a as [Any], let b as [Any]):
      guard a.count == b.count else {
        differences.append("\(path): \(a.count) items, now \(b.count)")
        return
      }
      for (index, pair) in zip(a, b).enumerated() {
        compare(pair.0, pair.1, path: "\(path)[\(index)]", into: &differences)
      }
    case (let a as String, let b as String):
      if a != b { differences.append("\(path): \(a) -> \(b)") }
    case (let a as NSNumber, let b as NSNumber):
      let x = a.doubleValue
      let y = b.doubleValue
      if abs(x - y) > max(1e-12, 1e-9 * max(abs(x), abs(y))) {
        differences.append("\(path): \(x) -> \(y)")
      }
    case (is NSNull, is NSNull):
      break
    default:
      differences.append("\(path): \(a) -> \(b)")
    }
  }

  // MARK: Tests

  func testEveryGoodFixtureCaptureMatchesItsGolden() throws {
    let names = try Self.fixtureNames()
    XCTAssertTrue(names.contains("sample-424"))
    var written: [String] = []
    for name in names {
      for fixture in try Fixtures.load(name) {
        let value = try Self.capture(fixture)
        let file = "\(name)-\(fixture.truth.areaKey).json"
        written.append(file)
        try check(value, name: file)
      }
    }
    try check(Self.rules(), name: "rules.json")
    // No stale golden is left behind.
    let present = try FileManager.default.contentsOfDirectory(atPath: Self.folder.path)
      .filter { $0.hasSuffix(".json") }
    XCTAssertEqual(Set(present), Set(written + ["rules.json"]))
  }

  func testTheSampleGoldensCarryTheRuleCases() throws {
    let sample = try Self.capture(Fixtures.sample424())
    XCTAssertEqual(sample.rooms.count, 12)
    XCTAssertEqual(sample.north.state, "verified")
    XCTAssertEqual(sample.north.unturned.lines?.last, "\u{B1}8\u{B0} \u{B7} 212\u{B0}")
    XCTAssertEqual(
      Set(sample.rooms.map(\.fillClass)), [RoomFillClass.habitable, .wet, .other].map(\.rawValue)
        .reduce(into: Set<String>()) { $0.insert($1) })
    let rules = Self.rules()
    let shower = try XCTUnwrap(rules.fill.first { $0.label == "Shower" && $0.type == nil })
    XCTAssertEqual(shower.fillClass, "wet")
    XCTAssertTrue(rules.areas.contains { $0.area == "10,763.9 sq ft" && $0.metric == "1,000.0 m\u{B2}" })
    XCTAssertTrue(rules.lengths.contains { $0.length == "0' 5.1\"" && $0.dimension == "5.1\"" })
  }
}
