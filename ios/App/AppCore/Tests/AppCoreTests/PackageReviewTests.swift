import CaptureContract
import Foundation
import XCTest

@testable import AppCore

/// Package ready (phone-package §3): the file kinds, counts and every string, from data.
final class PackageReviewTests: XCTestCase {
  private typealias Row = PackageReview.ExportRow

  func testPlanRowsNameEveryPlanFile() {
    XCTAssertEqual(
      PackageReview.exportRows([.planDXF, .roomsCSV, .planPDF, .planPNG, .planSVG]),
      [Row(kind: .plans, label: "Plan DXF \u{00B7} rooms CSV \u{00B7} plan sheet PDF, PNG, SVG", count: 5)])
    XCTAssertEqual(
      PackageReview.exportRows([.planSVG, .planPDF]),
      [Row(kind: .plans, label: "plan sheet PDF, SVG", count: 2)], "PDF, PNG, SVG order")
    XCTAssertEqual(
      PackageReview.exportRows([.planDXF, .roomsCSV]),
      [Row(kind: .plans, label: "Plan DXF \u{00B7} rooms CSV", count: 2)])
  }

  func testMeshRowsNeverInventAMesh() {
    XCTAssertEqual(
      PackageReview.exportRows([.meshGLB, .meshOBJ, .meshMTL]),
      [Row(kind: .meshes, label: "Mesh GLB \u{00B7} OBJ + MTL", count: 3)])
    XCTAssertEqual(
      PackageReview.exportRows([.meshGLB, .meshOBJ, .meshMTL, .texture, .texture]),
      [Row(kind: .meshes, label: "Mesh GLB \u{00B7} OBJ + MTL \u{00B7} textures", count: 5)])
    XCTAssertEqual(
      PackageReview.exportRows([.meshOBJ, .meshMTL]),
      [Row(kind: .meshes, label: "Mesh OBJ + MTL", count: 2)], "no GLB: the first part says Mesh")
    XCTAssertEqual(
      PackageReview.exportRows([.meshOBJ]), [Row(kind: .meshes, label: "Mesh OBJ", count: 1)])
    XCTAssertEqual(
      PackageReview.exportRows([.pointCloudLAS, .rawRoomplanJSON, .rawDepth]).map(\.kind), [.raw],
      "a capture without a scene mesh has no Meshes row")
  }

  func testPointCloudAndRawRows() {
    XCTAssertEqual(
      PackageReview.exportRows([.pointCloudLAS, .rawRoomplanJSON, .rawDepth, .captureModel]),
      [
        Row(
          kind: .raw, label: "Point cloud LAS \u{00B7} raw RoomPlan + depth \u{00B7} capture model",
          count: 4)
      ])
    XCTAssertEqual(
      PackageReview.exportRows([.pointCloudLAS, .rawRoomplanJSON, .rawDepth]),
      [Row(kind: .raw, label: "Point cloud LAS \u{00B7} raw RoomPlan + depth", count: 3)])
    XCTAssertEqual(
      PackageReview.exportRows([.rawRoomplanJSON, .captureModel]),
      [Row(kind: .raw, label: "raw RoomPlan \u{00B7} capture model", count: 2)])
    XCTAssertEqual(
      PackageReview.exportRows([.rawDepth]), [Row(kind: .raw, label: "raw depth", count: 1)])
    XCTAssertEqual(PackageReview.exportRows([]), [])
  }

  func testRowsComeInTheDrawnOrderAndNeverMentionTheSpatialReport() {
    let rows = PackageReview.exportRows([
      .rawRoomplanJSON, .rawDepth, .captureModel, .planDXF, .roomsCSV, .planPDF, .planPNG,
      .planSVG, .meshGLB, .meshOBJ, .meshMTL, .pointCloudLAS, .spatialReportPDF,
    ])
    XCTAssertEqual(rows.map(\.kind), [.plans, .meshes, .raw])
    XCTAssertEqual(rows.map(\.count), [5, 3, 4], "a legacy phone report is in no row")
    XCTAssertFalse(rows.contains { $0.label.localizedCaseInsensitiveContains("spatial") })
  }

  func testTheDrawnStrings() {
    let review = PackageReview(
      address: "618 Valley Street", captureCountText: "2 floors", revision: 1,
      exportGroups: [
        .init(
          areaKey: "floor-1", label: "Floor 1", fileCount: 13, bytes: 312_000_000,
          rows: [Row(kind: .plans, label: "Plan DXF", count: 1)])
      ],
      photoCount: 42, photoBytes: 188_000_000, controlCount: 9,
      compassText: "compass: Floor 1 only", manifestEntries: 74, totalBytes: 768_000_000)
    XCTAssertEqual(
      review.subtitle, "618 Valley Street \u{00B7} 2 floors \u{00B7} revision 1 \u{00B7} 74 files \u{00B7} 768 MB")
    XCTAssertEqual(review.buildingSubtitle, "618 Valley Street \u{00B7} 2 floors \u{00B7} revision 1")
    XCTAssertEqual(review.exportGroups[0].title, "Original Exports \u{00B7} Floor 1")
    XCTAssertEqual(review.exportGroups[0].countText, "13 files \u{00B7} 312 MB")
    XCTAssertEqual(
      review.exportGroups[0].accessibilityLabel, "Original Exports, Floor 1, 13 files, 312 megabytes")
    XCTAssertEqual(review.photosText, "42 \u{00B7} 188 MB")
    XCTAssertEqual(review.controlsText, "9 controls")
    XCTAssertEqual(review.manifestText, "manifest \u{00B7} 74 entries")
    XCTAssertEqual(
      review.sealNote,
      "Every file is fingerprinted (SHA-256). Sealing makes the package read-only; later changes "
        + "create revision 2. The station makes the spatial report.")
  }

  func testPluralsAndEmptyValues() {
    var review = PackageReview(
      address: "A", captureCountText: "1 room", revision: 1,
      exportGroups: [.init(areaKey: "a", label: "A", fileCount: 1, bytes: 3_200_000, rows: [])],
      photoCount: 0, photoBytes: 0, controlCount: 0, compassText: "compass: not recorded",
      manifestEntries: 1, totalBytes: 3_200_000)
    XCTAssertEqual(review.exportGroups[0].countText, "1 file \u{00B7} 3.2 MB")
    XCTAssertEqual(review.photosText, "none")
    XCTAssertEqual(review.controlsText, "no controls")
    XCTAssertEqual(review.manifestText, "manifest \u{00B7} 1 entry")
    XCTAssertEqual(review.subtitle, "A \u{00B7} 1 room \u{00B7} revision 1 \u{00B7} 1 file \u{00B7} 3.2 MB")
    review.controlCount = 1
    XCTAssertEqual(review.controlsText, "1 control")
  }

  func testCaptureCountText() {
    XCTAssertEqual(CaptureCountText.make([.floor, .floor]), "2 floors")
    XCTAssertEqual(CaptureCountText.make([.floor, .room]), "1 floor and 1 room")
    XCTAssertEqual(CaptureCountText.make([.room, .floor]), "1 floor and 1 room", "floors first")
    XCTAssertEqual(CaptureCountText.make([.room]), "1 room")
    XCTAssertEqual(CaptureCountText.make([.exterior, .exterior]), "2 exteriors")
    XCTAssertEqual(
      CaptureCountText.make([.exterior, .room, .floor, .room]), "1 floor, 2 rooms and 1 exterior")
    XCTAssertEqual(CaptureCountText.make([]), "no captures")
  }

  /// §3.3 with compass C8: a capture has a reading when it is verified or approximate.
  func testCompassText() {
    let read = Make.capture("Floor 1", compass: Make.reading())
    let approximate = Make.capture("Floor 3", compass: Make.reading(accuracy: 20, source: .magnetic))
    let inaccurate = Make.capture("Floor 4", compass: Make.reading(accuracy: 40))
    let none = Make.capture("Floor 2")
    let notCalibrated = Make.capture("Floor 5", compass: .none(issue: .notCalibrated))
    XCTAssertEqual(PackageReview.compassText([read]), "compass: recorded")
    XCTAssertEqual(PackageReview.compassText([read, approximate]), "compass: every floor")
    XCTAssertEqual(PackageReview.compassText([read, none]), "compass: Floor 1 only")
    XCTAssertEqual(
      PackageReview.compassText([read, none, approximate, inaccurate]),
      "compass: Floor 1, Floor 3 only")
    XCTAssertEqual(PackageReview.compassText([none]), "compass: not recorded")
    XCTAssertEqual(
      PackageReview.compassText([none, inaccurate, notCalibrated]), "compass: not recorded")
  }

  /// Critique R-29.
  func testProjectTitle() {
    XCTAssertEqual(
      ProjectTitle.of(Make.record([], projectName: "Kitchen and bath", address: "345 7th Ave")),
      "Kitchen and bath")
    XCTAssertEqual(ProjectTitle.of(Make.record([], projectName: nil, address: "345 7th Ave")), "345 7th Ave")
    XCTAssertEqual(ProjectTitle.of(Make.record([], projectName: "  ", address: "345 7th Ave")), "345 7th Ave")
  }

  func testPackageText() {
    XCTAssertEqual(
      PackageText.lowerFirst("Preliminary existing-condition plans"),
      "preliminary existing-condition plans")
    XCTAssertEqual(PackageText.lowerFirst("BIM model"), "BIM model", "an acronym keeps its case")
    XCTAssertEqual(PackageText.lowerFirst("3D model"), "3D model")
    XCTAssertEqual(PackageText.list(["A", "B", "C"]), "A, B and C")
    XCTAssertEqual(PackageText.list(["A", "B"]), "A and B")
    let date = Make.time("2025-01-25T09:05:00Z").date
    XCTAssertEqual(PackageText.date(date, in: Make.utc), "Jan 25, 2025")
    XCTAssertEqual(PackageText.shortDate(date, in: Make.utc), "Jan 25")
    XCTAssertEqual(PackageText.time(date, in: Make.utc), "09:05")
    XCTAssertEqual(
      PackageText.time(date, in: TimeZone(identifier: "America/New_York")!), "04:05",
      "the phone's time zone")
  }
}
