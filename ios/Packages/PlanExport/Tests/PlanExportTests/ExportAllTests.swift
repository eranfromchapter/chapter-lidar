import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

final class ExportAllTests: XCTestCase {
  func testExportAllWritesTheSixFilesForEveryFixtureCapture() throws {
    for capture in try Fixtures.all() {
      let files = try PlanExporter.exportAll(model: capture.model, record: capture.record)
      XCTAssertEqual(
        files.map(\.fileName),
        ["plan.dxf", "rooms.csv", "plan.pdf", "spatial-report.pdf", "plan.png", "plan.svg"])
      XCTAssertEqual(
        files.map(\.role),
        [.planDXF, .roomsCSV, .planPDF, .spatialReportPDF, .planPNG, .planSVG])
      for file in files {
        XCTAssertFalse(file.data.isEmpty, file.fileName)
        XCTAssertEqual(file.generator, PlanExportInfo.generator)
        XCTAssertEqual(file.generatorVersion, PlanExportInfo.generatorVersion)
        try Repo.write(file, folder: capture.outputFolder)
      }
    }
  }

  func testExportsAreByteStable() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let first = try PlanExporter.exportAll(model: capture.model, record: capture.record)
    let second = try PlanExporter.exportAll(model: capture.model, record: capture.record)
    XCTAssertEqual(first, second)
  }

  func testGeneratorNamesFitTheManifestSchema() {
    XCTAssertEqual(PlanExportInfo.generator, "chapter-capture-ios/PlanExport")
    XCTAssertLessThanOrEqual(PlanExportInfo.generator.count, 100)
    XCTAssertFalse(PlanExportInfo.generatorVersion.isEmpty)
    XCTAssertLessThanOrEqual(PlanExportInfo.generatorVersion.count, 50)
  }
}

final class PlanGeometryTests: XCTestCase {
  func testCoincidentWallsAreMergedAndShareRooms() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let geometry = try PlanGeometry(model: capture.model)
    XCTAssertEqual(capture.model.walls.count, 8)
    XCTAssertEqual(geometry.walls.count, 7)
    let partition = try XCTUnwrap(geometry.walls.first { $0.id == "wall-3" })
    XCTAssertEqual(Set(partition.roomIds), ["room-1", "room-2"])
  }

  func testRoomMeasurementsMatchTruth() throws {
    for capture in try Fixtures.all() {
      let geometry = try PlanGeometry(model: capture.model)
      for room in capture.truth.rooms {
        let measured = try XCTUnwrap(geometry.rooms.first { $0.id == room.id })
        XCTAssertEqual(measured.widthM, room.widthM, accuracy: 0.0005)
        XCTAssertEqual(measured.lengthM, room.lengthM, accuracy: 0.0005)
        XCTAssertEqual(measured.areaM2, room.areaM2, accuracy: 0.001)
        XCTAssertEqual(measured.perimeterM, room.perimeterM, accuracy: 0.0005)
      }
    }
  }

  func testLabelPointIsInsideAConcaveRoom() throws {
    let capture = try XCTUnwrap(Fixtures.load("l-shaped-room").first)
    let geometry = try PlanGeometry(model: capture.model)
    let room = try XCTUnwrap(geometry.rooms.first)
    XCTAssertTrue(PlanGeometry.contains(room.polygon, room.labelPoint))
    // A U shape whose centroid lies in the notch.
    let u = [(0.0, 0.0), (0.0, 6.0), (1.0, 6.0), (1.0, 1.0), (5.0, 1.0), (5.0, 6.0), (6.0, 6.0), (6.0, 0.0)]
      .map { Point2(x: $0.0, y: $0.1) }
    XCTAssertTrue(PlanGeometry.contains(u, PlanGeometry.labelPoint(of: u)))
  }

  func testObjectsGetARoomAndFootprint() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let geometry = try PlanGeometry(model: capture.model)
    XCTAssertEqual(geometry.objects.count, 2)
    for object in geometry.objects {
      XCTAssertEqual(object.corners.count, 4)
      XCTAssertNotNil(object.roomId)
    }
    let sofa = try XCTUnwrap(geometry.objects.first { $0.category == .sofa })
    XCTAssertEqual(sofa.roomId, "room-1")
    let xs = sofa.corners.map(\.x)
    XCTAssertEqual(xs.max()! - xs.min()!, 2.0, accuracy: 1e-9)
  }

  func testRotatedObjectFootprint() throws {
    var model = Synthetic.room(width: 4, length: 3)
    let half = (2.0).squareRoot() / 2
    model.objects = [
      CaptureModel.DetectedObject(
        id: "o", category: .table,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: 2, y: 0.4, z: 1.5), sizeM: Vec3(x: 2, y: 0.8, z: 1),
          rotation: Quaternion(x: 0, y: half, z: 0, w: half)))
    ]
    let geometry = try PlanGeometry(model: model)
    let corners = try XCTUnwrap(geometry.objects.first).corners
    // Turned 90 degrees about Y: 1 m along x, 2 m along z.
    XCTAssertEqual(corners.map(\.x).max()! - corners.map(\.x).min()!, 1, accuracy: 1e-9)
    XCTAssertEqual(corners.map(\.y).max()! - corners.map(\.y).min()!, 2, accuracy: 1e-9)
  }
}
