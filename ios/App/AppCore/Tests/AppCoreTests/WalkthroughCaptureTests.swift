import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import PackageCore
import XCTest

@testable import AppCore

/// An AR walkthrough capture through the app's rules (spec F15): the overview's floor row
/// ("walked"), the compass and controls rows, Package ready's file rows, and the package built
/// from `walkthrough-log.json`, `walkthrough.mp4` and the derived `sketch-measurements.json`.
final class WalkthroughCaptureTests: XCTestCase {
  private let utc = TimeZone(identifier: "UTC")!
  private let now = UTCTimestamp(rawValue: "2026-05-16T15:00:00Z")!.date

  private static let measurementsExample = Fixtures.repositoryRoot
    .appendingPathComponent("contract/examples/sketch-measurements/valid/two-rooms.json")
  private static let logExample = Fixtures.repositoryRoot
    .appendingPathComponent("contract/examples/walkthrough-log/valid/two-rooms.json")

  private func walkedCapture(
    _ label: String, limited: Bool = false, captureId: LowercaseUUID = LowercaseUUID()
  ) -> CaptureRecord.Capture {
    var capture = Make.capture(label, captureId: captureId)
    capture.captureSource = .walkthrough
    capture.sketch = .init(
      measurements: limited ? .limited : .complete, wallsMeasured: 4, wallsEstimated: 0,
      ceilingHeightSource: limited ? .assumed : .measured)
    capture.walkthrough = .init(
      scaleSource: .tape, scaleFactor: 0.998, loopClosureMm: 36, trackingLimitedSeconds: 0,
      recorded: true)
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

  func testTheFloorRowSaysWalkedAndNoCompassIsAsked() {
    let complete = walkedCapture("Floor 1")
    let limited = walkedCapture("Floor 2", limited: true)
    let record = Make.record([complete, limited])
    let state = overview(
      record, rooms: [complete.captureId: ["Bedroom"], limited.captureId: ["Kitchen", "Hall"]])
    XCTAssertEqual(
      state.floors[0].subtitle,
      "Whole floor · walked · 1 room · no photos yet · controls optional")
    XCTAssertEqual(
      state.floors[1].subtitle,
      "Whole floor · walked · limited · 2 rooms · no photos yet · controls optional")
    let compass = state.checks.first { $0.id == .compass }
    XCTAssertEqual(compass?.subtitle, CompassSummary.walkthroughOnlyDetail)
    XCTAssertEqual(compass?.status, RowStatusValue(.waiting, "Not needed"))

    let checklist = ChecklistRules.evaluate(
      ChecklistInput(
        record: record, capturedRooms: [complete.captureId: ["Bedroom"]],
        controls: FieldControls(visitId: record.visitId)), policy: .shipping)
    XCTAssertTrue(checklist.item(.compass).passed)
    XCTAssertEqual(checklist.item(.compass).detail, CompassSummary.walkthroughOnlyDetail)
    XCTAssertEqual(checklist.item(.minimumControls).detail, "Measured by the AR walkthrough")
    XCTAssertEqual(CompassSummary.entries(record: record), [])
  }

  func testAVisitOfASketchAndAWalkSaysBoth() {
    var sketch = Make.capture("Floor 2")
    sketch.captureSource = .sketch
    sketch.sketch = .init(
      measurements: .complete, wallsMeasured: 4, wallsEstimated: 0, ceilingHeightSource: .measured)
    let record = Make.record([walkedCapture("Floor 1"), sketch])
    let checklist = ChecklistRules.evaluate(
      ChecklistInput(record: record, capturedRooms: [:], controls: FieldControls(visitId: record.visitId)),
      policy: .shipping)
    XCTAssertEqual(checklist.item(.compass).detail, CompassSummary.measuredOnlyDetail)
    XCTAssertEqual(
      checklist.item(.minimumControls).detail, "Measured from the sketch and the AR walkthrough")
    XCTAssertEqual(PackageReview.compassText(record.captures), "compass: not needed")
  }

  // MARK: Package ready

  func testPackageReadyRowsNameTheWalkthroughOriginals() {
    XCTAssertEqual(
      PackageReview.exportRows([
        .walkthroughVideo, .walkthroughLog, .sketchMeasurements, .captureModel, .planDXF, .meshGLB,
      ]),
      [
        .init(kind: .plans, label: "Plan DXF", count: 1),
        .init(kind: .meshes, label: "Mesh GLB", count: 1),
        .init(
          kind: .raw, label: "walkthrough video + log + measurements \u{00B7} capture model",
          count: 4),
      ])
    XCTAssertEqual(
      PackageReview.exportRows([.walkthroughLog, .sketchMeasurements, .captureModel]),
      [.init(kind: .raw, label: "walkthrough log + measurements \u{00B7} capture model", count: 3)])
    XCTAssertEqual(
      PackageReview.compassText([walkedCapture("Floor 1")]), "compass: not needed for a walkthrough")
  }

  // MARK: The package

  /// A workspace with one walked capture: the example log, the example measurements (standing
  /// in for the converter's) and a small MP4 in its originals folder.
  private func walkedVisit(in base: URL, withVideo: Bool) throws -> (
    record: CaptureRecord, builder: VisitPackageBuilder
  ) {
    let data = try Data(contentsOf: Self.measurementsExample)
    let measurements = try CaptureContractJSON.makeDecoder().decode(SketchMeasurements.self, from: data)
    var capture = walkedCapture("Floor 2", captureId: measurements.captureId)
    capture.areaKey = measurements.areaKey
    let record = Make.record([capture], visitId: measurements.visitId)
    let workspace = try VisitWorkspace.create(in: base)
    let builder = VisitPackageBuilder(workspace: workspace, appVersion: "2.0.0")
    let originals = builder.originalsDirectory(of: capture)
    try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
    try data.write(to: originals.appendingPathComponent(PackageLayout.sketchMeasurementsFileName))
    try Data(contentsOf: Self.logExample).write(
      to: originals.appendingPathComponent(PackageLayout.walkthroughLogFileName))
    if withVideo {
      // An ISO base media header: size, `ftyp`, brand.
      let mp4 = Data([0, 0, 0, 24] + Array("ftypisom".utf8) + [0, 0, 2, 0] + Array("isommp41".utf8))
      try mp4.write(to: originals.appendingPathComponent(WalkthroughOriginals.videoFileName))
    }
    return (record, builder)
  }

  func testAWalkthroughIsPackagedFromItsLogVideoAndMeasurements() throws {
    let base = try Fixtures.temporaryDirectory()
    defer { Fixtures.removeTemporaryDirectory(base) }
    let visit = try walkedVisit(in: base, withVideo: true)
    let capture = visit.record.captures[0]
    XCTAssertTrue(visit.builder.hasOriginals(of: visit.record))
    let plan = try visit.builder.plan(
      record: visit.record, photos: [], controls: FieldControls(visitId: visit.record.visitId))

    let folder = "Original Exports/\(capture.areaKey)/\(capture.captureId.rawValue)/"
    let paths = plan.draft.entries.map(\.path)
    for name in [
      "walkthrough.mp4", "walkthrough-log.json", "sketch-measurements.json", "capture-model.json",
      "plan.dxf", "rooms.csv", "mesh.glb", "mesh.obj", "mesh.mtl",
    ] {
      XCTAssertTrue(paths.contains(folder + name), "missing \(folder + name)")
    }
    XCTAssertFalse(paths.contains { $0.hasSuffix("roomplan.json") || $0.hasSuffix("points.las") })
    XCTAssertFalse(paths.contains { $0.hasSuffix("sketch.jpg") })
    let video = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .walkthroughVideo })
    XCTAssertEqual(video.input.mime, "video/mp4")
    XCTAssertEqual(video.input.generator, AppGenerators.sketchCapture)
    let log = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .walkthroughLog })
    XCTAssertEqual(log.input.mime, "application/json")
    let measurements = try XCTUnwrap(
      plan.draft.entries.first { $0.input.role == .sketchMeasurements })
    XCTAssertEqual(measurements.input.derivedFrom, [folder + "walkthrough-log.json"])
    let model = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .captureModel })
    XCTAssertEqual(
      model.input.derivedFrom,
      [folder + "sketch-measurements.json", folder + "walkthrough-log.json"])
    XCTAssertEqual(
      try visit.builder.originalPaths(of: capture, in: plan.draft),
      [folder + "sketch-measurements.json", folder + "walkthrough-log.json"])
    let raw = plan.review.exportGroups[0].rows.first { $0.kind == .raw }
    XCTAssertEqual(raw?.label, "walkthrough video + log + measurements \u{00B7} capture model")
  }

  func testAWalkthroughWithoutAVideoIsPackagedWithoutOne() throws {
    let base = try Fixtures.temporaryDirectory()
    defer { Fixtures.removeTemporaryDirectory(base) }
    let visit = try walkedVisit(in: base, withVideo: false)
    let plan = try visit.builder.plan(
      record: visit.record, photos: [], controls: FieldControls(visitId: visit.record.visitId))
    XCTAssertNil(plan.draft.entries.first { $0.input.role == .walkthroughVideo })
    XCTAssertNotNil(plan.draft.entries.first { $0.input.role == .walkthroughLog })
  }
}
