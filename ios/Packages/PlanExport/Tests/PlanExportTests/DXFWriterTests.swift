import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

final class DXFWriterTests: XCTestCase {
  private func dxf(_ capture: FixtureCapture) throws -> (DXFFile, ExportedFile) {
    let file = try DXFWriter.write(model: capture.model)
    try Repo.write(file, folder: capture.outputFolder)
    return (DXFFile(String(decoding: file.data, as: UTF8.self)), file)
  }

  func testTwoRoomFixtureHasSevenLayersAndWallLengthsWithinOneMillimetre() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let (file, exported) = try dxf(capture)

    XCTAssertEqual(DXFWriter.layers.count, 7)
    for layer in DXFWriter.layers {
      XCTAssertTrue(file.layerNames.contains(layer), "layer table lacks \(layer)")
      XCTAssertFalse(file.entities(on: layer).isEmpty, "no entities on \(layer)")
    }
    XCTAssertEqual(exported.fileName, "plan.dxf")

    // Wall centrelines: one LINE per distinct wall. The partition is listed twice in the model
    // (wall-3 and wall-5) and drawn once.
    let lines = file.entities(on: "A-WALL").filter { $0.type == "LINE" }
    XCTAssertEqual(lines.count, capture.truth.walls.count - 1)
    let drawn = lines.map { file.lineLength($0) }
    for wall in capture.truth.walls {
      let expectedMM = wall.lengthM * 1000
      XCTAssertTrue(
        drawn.contains { abs($0 - expectedMM) <= 1 },
        "no wall line within 1 mm of \(wall.id) (\(expectedMM) mm); drawn \(drawn)")
    }
    for length in drawn {
      XCTAssertTrue(
        capture.truth.walls.contains { abs($0.lengthM * 1000 - length) <= 1 },
        "drawn wall \(length) mm is not in truth.json")
    }
  }

  func testWallLengthsWithinOneMillimetreForEveryFixtureCapture() throws {
    for capture in try Fixtures.all() {
      let (file, _) = try dxf(capture)
      let drawn = file.entities(on: "A-WALL").filter { $0.type == "LINE" }.map(file.lineLength)
      for wall in capture.truth.walls {
        XCTAssertTrue(
          drawn.contains { abs($0 - wall.lengthM * 1000) <= 1 },
          "\(capture.fixture) \(capture.truth.areaKey) \(wall.id)")
      }
    }
  }

  func testRoomOutlinesAreClosedAndMatchTruthArea() throws {
    for capture in try Fixtures.all() {
      let (file, _) = try dxf(capture)
      let outlines = file.entities(on: "A-AREA")
      XCTAssertEqual(outlines.count, capture.truth.rooms.count)
      for (outline, room) in zip(outlines, capture.truth.rooms) {
        XCTAssertEqual(outline.type, "LWPOLYLINE")
        XCTAssertEqual(outline.value(70), "1", "outline is closed")
        let points = file.vertices(of: outline)
        var twice = 0.0
        for index in points.indices {
          let a = points[index]
          let b = points[(index + 1) % points.count]
          twice += a.0 * b.1 - b.0 * a.1
        }
        XCTAssertEqual(abs(twice) / 2 / 1_000_000, room.areaM2, accuracy: 0.01)
      }
    }
  }

  func testHeaderIsR2013InMillimetresAndFileIsPlanGeometryOnly() throws {
    for capture in try Fixtures.all() {
      let (file, exported) = try dxf(capture)
      XCTAssertEqual(file.header["$ACADVER"]?.first?.value, "AC1027")
      XCTAssertEqual(file.header["$INSUNITS"]?.first?.value, "4")
      XCTAssertTrue(file.endsWithEOF)
      XCTAssertEqual(file.sections, ["HEADER", "CLASSES", "TABLES", "BLOCKS", "ENTITIES", "OBJECTS"])
      let allowed: Set<String> = ["LINE", "ARC", "LWPOLYLINE", "TEXT"]
      XCTAssertTrue(Set(file.entities.map(\.type)).isSubset(of: allowed))
      XCTAssertFalse(file.entities.isEmpty)
      let text = String(decoding: exported.data, as: UTF8.self)
      for banned in ["MESH", "POINT", "3DFACE", "POLYLINE\n"] {
        XCTAssertFalse(text.contains("\n\(banned)\n"), "found \(banned)")
      }
      XCTAssertTrue(text.utf8.allSatisfy { $0 < 0x80 }, "DXF is ASCII")
    }
  }

  func testOneFilePerFloor() throws {
    let captures = try Fixtures.load("two-floor-house")
    XCTAssertEqual(captures.count, 2)
    let files = try captures.map { try DXFWriter.write(model: $0.model) }
    XCTAssertNotEqual(files[0].data, files[1].data)
    // Floor 2 is written in its own (turned) frame: its extent is 5 m by 6 m.
    let second = DXFFile(String(decoding: files[1].data, as: UTF8.self))
    let xs = second.entities(on: "A-WALL").flatMap { [$0.number(10), $0.number(11)] }
    let ys = second.entities(on: "A-WALL").flatMap { [$0.number(20), $0.number(21)] }
    XCTAssertEqual((xs.max()! - xs.min()!), 5000, accuracy: 1)
    XCTAssertEqual((ys.max()! - ys.min()!), 6000, accuracy: 1)
  }

  func testPlanYIsMinusModelZ() throws {
    let model = Synthetic.room(width: 4, length: 3)
    let file = DXFFile(String(decoding: try DXFWriter.write(model: model).data, as: UTF8.self))
    let ys = file.entities(on: "A-WALL").flatMap { [$0.number(20), $0.number(21)] }
    XCTAssertEqual(ys.min()!, -3000, accuracy: 0.001)
    XCTAssertEqual(ys.max()!, 0, accuracy: 0.001)
  }

  func testRoomLabelsAndAreasAreText() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let file = DXFFile(String(decoding: try DXFWriter.write(model: capture.model).data, as: UTF8.self))
    let texts = file.entities(on: "A-ANNO-TEXT").compactMap { $0.value(1) }
    XCTAssertTrue(texts.contains("Living Room"))
    XCTAssertTrue(texts.contains("Bedroom"))
    XCTAssertTrue(texts.contains("20.00 m2"))
    XCTAssertTrue(texts.contains("12.00 m2"))
  }

  func testNonAsciiTextIsEscaped() {
    XCTAssertEqual(DXFWriter.dxfText("Caf\u{00E9} 2"), "Caf\\U+00E9 2")
    XCTAssertEqual(DXFWriter.dxfText("a\nb"), "a b")
    XCTAssertEqual(DXFWriter.dxfText(String(repeating: "x", count: 400)).count, 250)
  }

  func testThickWallsAlsoGetAnOutline() throws {
    var model = Synthetic.room(width: 4, length: 3)
    model.walls = model.walls.map {
      var wall = $0
      wall.thicknessM = 0.2
      return wall
    }
    let file = DXFFile(String(decoding: try DXFWriter.write(model: model).data, as: UTF8.self))
    XCTAssertEqual(file.entities(on: "A-WALL").filter { $0.type == "LINE" }.count, 4)
    let outlines = file.entities(on: "A-WALL").filter { $0.type == "LWPOLYLINE" }
    XCTAssertEqual(outlines.count, 4)
    let first = file.vertices(of: outlines[0])
    // 4 m wall, 0.2 m thick: a 4000 x 200 mm rectangle around the centreline.
    let xs = first.map(\.0)
    let ys = first.map(\.1)
    let spans = [xs.max()! - xs.min()!, ys.max()! - ys.min()!].sorted()
    XCTAssertEqual(spans[0], 200, accuracy: 0.01)
  }

  func testDoorSwingIsAnArcOnTheDoorLayerIntoTheRoom() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let file = DXFFile(String(decoding: try DXFWriter.write(model: capture.model).data, as: UTF8.self))
    let door = file.entities(on: "A-DOOR")
    XCTAssertEqual(door.filter { $0.type == "LINE" }.count, 1)
    let arc = try XCTUnwrap(door.first { $0.type == "ARC" })
    XCTAssertEqual(arc.number(40), 900, accuracy: 0.001)
    XCTAssertEqual((arc.number(51) - arc.number(50) + 360).truncatingRemainder(dividingBy: 360), 90, accuracy: 0.001)
  }

  func testUnknownWallAndNonFiniteCoordinatesThrow() {
    var model = Synthetic.room(width: 4, length: 3)
    model.doors = [
      CaptureModel.WallOpening(
        id: "door-x", wallId: "wall-99", offsetM: 1, bottomM: 0, widthM: 0.9, heightM: 2.1)
    ]
    XCTAssertThrowsError(try DXFWriter.write(model: model)) { error in
      XCTAssertEqual(
        error as? PlanExportError, .unknownWall(openingId: "door-x", wallId: "wall-99"))
    }
    var bad = Synthetic.room(width: 4, length: 3)
    bad.walls[0].start = Vec3(x: .nan, y: 0, z: 0)
    XCTAssertThrowsError(try DXFWriter.write(model: bad))
  }

  func testGeneratorFieldsForManifest() throws {
    let model = Synthetic.room(width: 4, length: 3)
    let file = try DXFWriter.write(model: model)
    XCTAssertEqual(file.generator, "chapter-capture-ios/PlanExport")
    XCTAssertEqual(file.generatorVersion, PlanExportInfo.generatorVersion)
    XCTAssertEqual(file.role, .planDXF)
    XCTAssertEqual(file.mime, "image/vnd.dxf")
  }

  func testOutputIsDeterministic() throws {
    let model = Synthetic.room(width: 4, length: 3)
    XCTAssertEqual(try DXFWriter.write(model: model).data, try DXFWriter.write(model: model).data)
  }
}
