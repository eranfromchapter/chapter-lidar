import CaptureContract
import CaptureCore
import CaptureModelMapping
import Foundation
import PackageCore
import XCTest

@testable import AppCore

/// Every manifest role a visit package carries today is still produced (floorplan report plan,
/// phase 1). Later phases add files; none of today's may go, except the roles the contract
/// retires (`FileRole.retiredRoles`: the phone's spatial report, design v2), which no package may
/// hold any more.
final class ManifestRoleTests: XCTestCase {
  /// The roles the app writes today. New roles may be added to this list, but none removed.
  /// (`texture` is a contract role the app has never written; `spatial_report_pdf` is retired:
  /// the station makes the spatial report.)
  private let todaysRoles: Set<FileRole> = [
    .captureRecord, .fieldControls,
    .rawRoomplanJSON, .rawDepth, .captureModel,
    .planDXF, .roomsCSV, .planPDF, .planPNG, .planSVG,
    .meshGLB, .meshOBJ, .meshMTL, .pointCloudLAS,
    .photo,
  ]

  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    if let base { try? FileManager.default.removeItem(at: base) }
  }

  func testTwoRoomVisitStillHasEveryRoleOfToday() throws {
    let visit = try FixtureVisit("two-room-apartment", in: base)
    let builder = VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0")
    // The fixture recording has no scene mesh. Store one triangle the way a scan stores its mesh
    // anchors, so the mesh files are written too.
    for capture in visit.record.captures {
      let anchor = RawMeshAnchor(
        identifier: UUID().uuidString.lowercased(), transform: .identity,
        vertices: [0, 0, 0, 1, 0, 0, 0, 0, 1], triangles: [0, 1, 2])
      try MeshAnchorsCodec.encode([anchor]).write(
        to: builder.originalsDirectory(of: capture)
          .appendingPathComponent(RawOriginalsNaming.meshAnchorsFileName))
    }
    let plan = try builder.plan(
      record: visit.record, photos: visit.photos, controls: visit.controls)

    let roles = Set(plan.draft.entries.map(\.input.role))
    XCTAssertTrue(
      todaysRoles.isSubset(of: roles),
      "missing roles: \(todaysRoles.subtracting(roles).map(\.rawValue).sorted())")
    XCTAssertTrue(
      roles.isDisjoint(with: FileRole.retiredRoles),
      "retired roles in the draft: \(roles.filter(\.isRetired).map(\.rawValue).sorted())")
    XCTAssertTrue(todaysRoles.isDisjoint(with: FileRole.retiredRoles))
    // Every capture still has each per-capture role.
    for capture in visit.record.captures {
      let captureRoles = Set(
        plan.draft.entries.filter { $0.input.capture?.captureId == capture.captureId }
          .map(\.input.role))
      let expected = todaysRoles.filter { !$0.isVisitWide }
      XCTAssertTrue(
        expected.isSubset(of: captureRoles),
        "\(capture.label) misses \(expected.subtracting(captureRoles).map(\.rawValue).sorted())")
    }
  }
}
