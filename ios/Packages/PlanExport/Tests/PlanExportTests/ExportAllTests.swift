import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

final class ExportAllTests: XCTestCase {
  /// The five files exportAll writes for a capture, in this order (plan-sheet §2): the plan
  /// sheet is `plan-sheet.pdf` with role `plan_pdf`, and the phone writes no spatial report.
  private let fiveFiles: [(name: String, role: FileRole)] = [
    ("plan.dxf", .planDXF), ("rooms.csv", .roomsCSV), ("plan-sheet.pdf", .planPDF),
    ("plan.png", .planPNG), ("plan.svg", .planSVG),
  ]

  func testExportAllWritesTheFiveFilesForEveryFixtureCapture() throws {
    for capture in try Fixtures.all() {
      let files = try PlanExporter.exportAll(model: capture.model, record: capture.record)
      XCTAssertEqual(files.map(\.fileName), fiveFiles.map(\.name), capture.fixture)
      XCTAssertEqual(files.map(\.role), fiveFiles.map(\.role), capture.fixture)
      XCTAssertEqual(Set(files.map(\.fileName)).count, files.count, "file names are unique")
      XCTAssertEqual(files.first { $0.role == .planPDF }?.mime, "application/pdf")
      for file in files {
        XCTAssertFalse(file.data.isEmpty, file.fileName)
        XCTAssertEqual(file.generator, PlanExportInfo.generator)
        XCTAssertEqual(file.generatorVersion, PlanExportInfo.generatorVersion)
        try Repo.write(file, folder: capture.outputFolder)
      }
    }
  }

  func testNoSpatialReportIsWritten() throws {
    // The spatial report is a station output; its role is retired in manifest 1.1.0.
    XCTAssertTrue(FileRole.spatialReportPDF.isRetired)
    for capture in try Fixtures.all() {
      let files = try PlanExporter.exportAll(model: capture.model, record: capture.record)
      XCTAssertFalse(files.contains { $0.role.isRetired }, capture.fixture)
      XCTAssertFalse(files.contains { $0.fileName == "spatial-report.pdf" }, capture.fixture)
      XCTAssertFalse(files.contains { $0.fileName == "plan.pdf" }, "renamed plan-sheet.pdf")
      let pdfs = files.filter { $0.mime == "application/pdf" }
      XCTAssertEqual(pdfs.map(\.fileName), [PlanPDFWriter.fileName], capture.fixture)
    }
  }

  func testExportsAreByteStable() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let first = try PlanExporter.exportAll(model: capture.model, record: capture.record)
    let second = try PlanExporter.exportAll(model: capture.model, record: capture.record)
    XCTAssertEqual(first, second)
  }

  func testSmallCapturesExportWithoutCrashing() throws {
    // Plans narrower than the 40 mm scale bar of plan.png: a 1 x 1 m closet, a capture with
    // only one object, and a door placed past the end of its wall.
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    func matched(_ model: CaptureModel) -> CaptureModel {
      var model = model
      model.visitId = capture.model.visitId
      model.captureId = capture.model.captureId
      return model
    }
    let closet = matched(Synthetic.room(width: 1, length: 1, label: "Closet"))
    var object = matched(Synthetic.room(width: 1, length: 1))
    object.rooms = []
    object.walls = []
    object.objects = [
      CaptureModel.DetectedObject(
        id: "object-1", category: .chair,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: 0, y: 0.4, z: 0), sizeM: Vec3(x: 0.5, y: 0.8, z: 0.5)))
    ]
    var stray = matched(Synthetic.room(width: 1.2, length: 1))
    stray.doors = [
      CaptureModel.WallOpening(
        id: "door-1", wallId: "wall-1", offsetM: 3, bottomM: 0, widthM: 0.8, heightM: 2)
    ]
    for (name, model) in [("closet", closet), ("one object", object), ("stray door", stray)] {
      let files = try PlanExporter.exportAll(model: model, record: capture.record)
      XCTAssertEqual(files.map(\.fileName), fiveFiles.map(\.name), name)
      let png = try XCTUnwrap(files.first { $0.fileName == PNGWriter.fileName }, name)
      XCTAssertFalse(png.data.isEmpty, name)
    }
    // The scene of plan.png and plan.svg is wide enough for the scale bar and its last label.
    let geometry = try PlanGeometry(model: closet)
    let scene = try PlanScene.build(
      geometry: geometry, scaleDenominator: 50, units: .metric, includeScaleBar: true)
    XCTAssertGreaterThanOrEqual(
      scene.widthMM,
      PlanScene.margin + PlanScene.scaleBarPaperLength + PlanScene.scaleBarEndClearance)
  }

  func testCanvasClipsStrokesAndTextWhollyOffIt() {
    var canvas = GrayCanvas(width: 20, height: 10)
    // Past the right, the bottom, the left and the top.
    canvas.stroke(
      from: Point2(x: 40, y: 2), to: Point2(x: 60, y: 2), width: 1, gray: 0)
    canvas.stroke(
      from: Point2(x: 2, y: 40), to: Point2(x: 8, y: 50), width: 1, gray: 0)
    canvas.stroke(
      from: Point2(x: -40, y: 2), to: Point2(x: -30, y: 2), width: 1, gray: 0)
    canvas.stroke(
      from: Point2(x: 2, y: -40), to: Point2(x: 8, y: -30), width: 1, gray: 0)
    canvas.text(
      "2 M", origin: Point2(x: 60, y: 5), emPixels: 8, rotation: 0, centered: true,
      bold: false, gray: 0)
    canvas.text(
      "2 M", origin: Point2(x: 5, y: 60), emPixels: 8, rotation: 0, centered: false,
      bold: true, gray: 0)
    XCTAssertTrue(canvas.pixels.allSatisfy { $0 == 255 }, "nothing drawn")
    // A line that crosses the edge is drawn up to it.
    canvas.stroke(from: Point2(x: 10, y: 5), to: Point2(x: 40, y: 5), width: 1, gray: 0)
    XCTAssertTrue(canvas.pixels.contains { $0 < 128 })
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
