import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import PackageCore
import SketchSolver
import XCTest

@testable import AppCore

/// A sketch capture through the app's rules (spec F14 2.1, 2.4): the overview's floor row and
/// compass row, Before you leave's compass item, Package ready's file rows, and the package
/// built from `sketch-measurements.json` and the sketch image (once the solver is built).
final class SketchCaptureTests: XCTestCase {
  private let utc = TimeZone(identifier: "UTC")!
  private let now = UTCTimestamp(rawValue: "2026-05-16T15:00:00Z")!.date

  /// The example document of the contract (`two-rooms.json`): a bedroom and a closet.
  private static let example = Fixtures.repositoryRoot
    .appendingPathComponent("contract/examples/sketch-measurements/valid/two-rooms.json")

  private func sketchCapture(
    _ label: String, limited: Bool = false, captureId: LowercaseUUID = LowercaseUUID()
  ) -> CaptureRecord.Capture {
    var capture = Make.capture(label, captureId: captureId)
    capture.captureSource = .sketch
    capture.sketch = .init(
      measurements: limited ? .limited : .complete, wallsMeasured: limited ? 3 : 4,
      wallsEstimated: limited ? 1 : 0, ceilingHeightSource: .measured)
    return capture
  }

  private func overview(_ record: CaptureRecord, rooms: [LowercaseUUID: [String]])
    -> CaptureOverviewState
  {
    let controls = FieldControls(visitId: record.visitId)
    let checklist = ChecklistRules.evaluate(
      ChecklistInput(record: record, capturedRooms: rooms, controls: controls), policy: .shipping)
    var scans: [LowercaseUUID: OverviewBuilder.FloorScan] = [:]
    for capture in record.captures { scans[capture.captureId] = .mapped(nil) }
    return OverviewBuilder.make(
      OverviewBuilder.Input(
        record: record, rooms: rooms, scans: scans, photos: [], controls: controls,
        checklist: checklist, policy: .shipping,
        flow: VisitFlow(resuming: record, isSealed: false), now: now, timeZone: utc))
  }

  // MARK: Overview and checklist

  func testTheFloorRowSaysSketchAndLimited() {
    let complete = sketchCapture("Floor 1")
    let limited = sketchCapture("Floor 2", limited: true)
    let record = Make.record([complete, limited])
    let state = overview(
      record, rooms: [complete.captureId: ["Bedroom"], limited.captureId: ["Kitchen", "Hall"]])
    XCTAssertEqual(
      state.floors[0].subtitle,
      "Whole floor · sketch · 1 room · no photos yet · controls optional")
    XCTAssertEqual(
      state.floors[1].subtitle,
      "Whole floor · sketch · limited · 2 rooms · no photos yet · controls optional")
    XCTAssertEqual(state.floors[0].status, RowStatusValue(.missing, "Open"), "no photo yet")
  }

  func testASketchOnlyVisitAsksForNoCompass() {
    let capture = sketchCapture("Floor 1")
    let record = Make.record([capture])
    let state = overview(record, rooms: [capture.captureId: ["Bedroom"]])
    let compass = state.checks.first { $0.id == .compass }
    XCTAssertEqual(compass?.subtitle, "Sketch capture: the plan is oriented as drawn")
    XCTAssertEqual(compass?.status, RowStatusValue(.waiting, "Not needed"))

    let checklist = ChecklistRules.evaluate(
      ChecklistInput(
        record: record, capturedRooms: [capture.captureId: ["Bedroom"]],
        controls: FieldControls(visitId: record.visitId)), policy: .shipping)
    XCTAssertTrue(checklist.item(.compass).passed)
    XCTAssertEqual(checklist.item(.minimumControls).detail, "Measured from the sketch")
    XCTAssertEqual(checklist.item(.compass).detail, CompassSummary.sketchOnlyDetail)
    XCTAssertEqual(checklist.compass, [], "nothing to read on a sketch")

    // A scanned floor next to it is still graded on its own.
    let scanned = Make.capture("Floor 2", compass: Make.reading())
    let mixed = Make.record([capture, scanned])
    let entries = CompassSummary.entries(record: mixed)
    XCTAssertEqual(entries.map(\.label), ["Floor 2"])
    XCTAssertEqual(
      overview(mixed, rooms: [:]).checks.first { $0.id == .compass }?.status,
      RowStatusValue(.done, "Verified"))
  }

  // MARK: Package ready

  func testPackageReadyRowsNameTheSketchOriginals() {
    XCTAssertEqual(
      PackageReview.exportRows([
        .sketchImage, .sketchMeasurements, .captureModel, .planDXF, .meshGLB, .meshOBJ, .meshMTL,
      ]),
      [
        .init(kind: .plans, label: "Plan DXF", count: 1),
        .init(kind: .meshes, label: "Mesh GLB \u{00B7} OBJ + MTL", count: 3),
        .init(kind: .raw, label: "sketch image + measurements \u{00B7} capture model", count: 3),
      ])
    XCTAssertEqual(
      PackageReview.exportRows([.sketchMeasurements, .captureModel]),
      [.init(kind: .raw, label: "sketch measurements \u{00B7} capture model", count: 2)])
    XCTAssertEqual(
      PackageReview.compassText([sketchCapture("Floor 1")]), "compass: not needed for a sketch")
    XCTAssertEqual(
      PackageReview.compassText([sketchCapture("Floor 1"), Make.capture("Floor 2", compass: Make.reading())]),
      "compass: recorded")
  }

  // MARK: The package

  /// A workspace with one sketch capture: the example measurements and a small JPEG as
  /// `sketch.jpg` in its originals folder, the capture record naming it as a sketch.
  private func sketchVisit(in base: URL, withImage: Bool = true) throws -> (
    workspace: VisitWorkspace, record: CaptureRecord, builder: VisitPackageBuilder
  ) {
    let data = try Data(contentsOf: Self.example)
    let measurements = try CaptureContractJSON.makeDecoder().decode(SketchMeasurements.self, from: data)
    var capture = sketchCapture("Floor 2", captureId: measurements.captureId)
    capture.areaKey = measurements.areaKey
    let record = Make.record([capture], visitId: measurements.visitId)
    let workspace = try VisitWorkspace.create(in: base)
    let builder = VisitPackageBuilder(workspace: workspace, appVersion: "2.0.0")
    let originals = builder.originalsDirectory(of: capture)
    try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
    try data.write(to: originals.appendingPathComponent(PackageLayout.sketchMeasurementsFileName))
    if withImage {
      let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: 0x20, count: 64) + [0xFF, 0xD9])
      try jpeg.write(to: originals.appendingPathComponent("sketch.jpg"))
    }
    return (workspace, record, builder)
  }

  func testTheOriginalsOfASketchCaptureAreFound() throws {
    let base = try Fixtures.temporaryDirectory()
    defer { Fixtures.removeTemporaryDirectory(base) }
    let visit = try sketchVisit(in: base)
    XCTAssertTrue(visit.builder.hasOriginals(of: visit.record))
    XCTAssertEqual(try visit.builder.sketchMeasurements(of: visit.record.captures[0]).rooms.count, 2)
    XCTAssertEqual(
      VisitPackageBuilder.sketchImage(in: visit.builder.originalsDirectory(of: visit.record.captures[0]))?.mime,
      "image/jpeg")
  }

  func testASketchCaptureIsPackagedFromItsMeasurements() throws {
    let base = try Fixtures.temporaryDirectory()
    defer { Fixtures.removeTemporaryDirectory(base) }
    let visit = try sketchVisit(in: base)
    let capture = visit.record.captures[0]
    let plan: VisitPackagePlan
    do {
      plan = try visit.builder.plan(
        record: visit.record, photos: [], controls: FieldControls(visitId: visit.record.visitId))
    } catch VisitPackageError.captureModel(_, let reason)
      where reason.contains(SketchSolverError.notImplemented.description)
    {
      throw XCTSkip("the sketch solver is not built yet (F14.2)")
    }

    let folder = "Original Exports/\(capture.areaKey)/\(capture.captureId.rawValue)/"
    let paths = plan.draft.entries.map(\.path)
    for name in [
      "sketch.jpg", "sketch-measurements.json", "capture-model.json", "plan.dxf", "rooms.csv",
      "plan.png", "plan.svg", "mesh.glb", "mesh.obj", "mesh.mtl",
    ] {
      XCTAssertTrue(paths.contains(folder + name), "missing \(folder + name)")
    }
    XCTAssertFalse(paths.contains { $0.hasSuffix("roomplan.json") || $0.hasSuffix("points.las") })
    let image = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .sketchImage })
    XCTAssertEqual(image.input.generator, AppGenerators.sketchCapture)
    XCTAssertEqual(image.input.mime, "image/jpeg")
    let model = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .captureModel })
    XCTAssertEqual(
      model.input.derivedFrom, [folder + "sketch.jpg", folder + "sketch-measurements.json"])
    let mesh = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .meshGLB })
    XCTAssertEqual(mesh.input.derivedFrom, [folder + "capture-model.json"])
    XCTAssertEqual(
      plan.review.exportGroups[0].rows.map(\.kind), [.plans, .meshes, .raw])

    // The model's rooms carry the operator's labels; a rename applies by room id.
    let solved = try visit.builder.captureModel(of: capture, visitId: visit.record.visitId)
    XCTAssertEqual(solved.rooms.map(\.label), ["Bedroom", "Closet"])
    var names = VisitRoomNames()
    names.setName(
      "Primary bedroom", roomId: "room-1", derivedLabel: "Bedroom", footprint: nil,
      captureId: capture.captureId)
    let renamed = try visit.builder.captureModel(
      of: capture, visitId: visit.record.visitId, names: names.names(for: capture.captureId))
    XCTAssertEqual(renamed.rooms.map(\.label), ["Primary bedroom", "Closet"])
  }
}
