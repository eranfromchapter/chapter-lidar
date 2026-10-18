import CaptureContract
import FieldRules
import Foundation
import XCTest

final class ScanMeasurementsTests: XCTestCase {
  /// The generated box room: 4.000 x 3.000 m, ceiling 2.700 m, one door and one window.
  private func boxRoomModel() throws -> CaptureModel {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().appendingPathComponent("../../../../../fixtures/generated/box-room/package/Original Exports/floor-1")
      .standardizedFileURL
    let capture = try XCTUnwrap(
      try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
    let data = try Data(contentsOf: capture.appendingPathComponent("capture-model.json"))
    return try JSONDecoder().decode(CaptureModel.self, from: data)
  }

  func testBoxRoomGivesLongDistancesCeilingAndOpenings() throws {
    let scan = ScanMeasurements(model: try boxRoomModel())
    XCTAssertEqual(scan.distanceAMm, 4000)
    XCTAssertEqual(scan.distanceBMm, 3000)
    XCTAssertEqual(scan.ceilingHeights, [.init(room: "Test Room", heightMm: 2700)])
    XCTAssertEqual(scan.openingsSummary, "1 door \u{00B7} 1 window")
  }

  func testRotatedFloorStillMeasuresAlongItsWalls() throws {
    var model = try boxRoomModel()
    let angle = 0.5
    func rotate(_ p: Vec3) -> Vec3 {
      Vec3(x: p.x * cos(angle) - p.z * sin(angle), y: p.y, z: p.x * sin(angle) + p.z * cos(angle))
    }
    model.walls = model.walls.map { var w = $0; w.start = rotate(w.start); w.end = rotate(w.end); return w }
    let scan = ScanMeasurements(model: model)
    XCTAssertEqual(scan.distanceAMm, 4000)
    XCTAssertEqual(scan.distanceBMm, 3000)
  }

  func testNoWallsGivesNoDistances() throws {
    var model = try boxRoomModel()
    model.walls = []
    model.doors = []
    model.windows = []
    let scan = ScanMeasurements(model: model)
    XCTAssertNil(scan.distanceAMm)
    XCTAssertNil(scan.distanceBMm)
    XCTAssertEqual(scan.openingsSummary, "None found")
  }
}
