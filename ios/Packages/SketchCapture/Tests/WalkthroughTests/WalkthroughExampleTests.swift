import CaptureContract
import CaptureTestSupport
import Foundation
import SketchSolver
import Walkthrough
import XCTest

/// The contract example `walkthrough-log/valid/two-rooms.json` (a bedroom walked corner by corner
/// with a closing tap and a tape check, and a closet tapped wall by wall beside it) through the
/// converter, the schemas and the solver.
final class WalkthroughExampleTests: XCTestCase {
  private let sourcePath =
    "Original Exports/floor-2/a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60/walkthrough-log.json"

  private func example() throws -> WalkthroughLog {
    let url = Fixtures.repositoryRoot.appendingPathComponent(
      "contract/examples/walkthrough-log/valid/two-rooms.json")
    return try CaptureContractJSON.makeDecoder().decode(
      WalkthroughLog.self, from: Data(contentsOf: url))
  }

  private func convert() throws -> WalkthroughConversion {
    try WalkthroughConverter.convert(
      example(), displayUnits: .imperial, sourcePath: sourcePath, recorded: true)
  }

  func testExampleConvertsAndValidates() throws {
    let conversion = try convert()
    let document = conversion.measurements
    try validate(document, schema: "sketch-measurements.schema.json")
    XCTAssertEqual(document.areaKey, "floor-2")
    XCTAssertEqual(document.visitId.rawValue, "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")
    XCTAssertEqual(document.captureId.rawValue, "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")
    XCTAssertEqual(document.source, SketchMeasurements.Source(kind: .arWalkthrough, path: sourcePath))
    XCTAssertEqual(document.displayUnits, .imperial)
    XCTAssertEqual(document.rooms.map(\.id), ["room-1", "room-2"])
    XCTAssertEqual(document.rooms.map(\.label), ["Bedroom", "Closet"])
    XCTAssertEqual(document.rooms.map(\.type), [.bedroom, .closet])
    XCTAssertEqual(document.rooms.flatMap(\.walls).map(\.id), (1...8).map { "wall-\($0)" })
    XCTAssertEqual(document.rooms.flatMap(\.openings).map(\.id), ["door-1", "window-1", "door-2"])
    XCTAssertTrue(document.rooms.allSatisfy { $0.placement != nil })
    XCTAssertTrue(document.rooms.flatMap(\.walls).allSatisfy { $0.turn == nil })

    // Bedroom loop: closing tap (0.031, 0.022) against the first corner (0.004, −0.003).
    let summary = conversion.summary
    XCTAssertEqual(summary.loopClosureMm, (27.0 * 27 + 25 * 25).squareRoot(), accuracy: 0.05)
    XCTAssertEqual(summary.scaleSource, .tape)
    let factor = try XCTUnwrap(summary.scaleFactor)
    // The drift-corrected wall 1 is within a few hundredths of a millimetre of 4001 mm.
    XCTAssertEqual(factor, 1, accuracy: 0.0005)
    XCTAssertEqual(summary.trackingLimitedSeconds, 0.5, accuracy: 1e-9)
    XCTAssertTrue(summary.recorded)
    XCTAssertEqual(document.rooms[0].walls[0].length?.valueMm ?? 0, 4001, accuracy: 0.05)
    XCTAssertEqual(document.rooms[0].walls[0].length?.enteredText, "13' 1.5\"")
    XCTAssertEqual(conversion.notes.count, 2)
    XCTAssertEqual(conversion.notes.last, "Scale checked with a tape on Bedroom wall 1: ×\(factor).")

    // Ceiling: (1.027 + 1.412) m scaled, the closet takes the bedroom's.
    XCTAssertEqual(document.ceilingHeight?.valueMm ?? 0, 2439 * factor, accuracy: 0.1)
    XCTAssertTrue(document.rooms.allSatisfy { $0.ceilingHeight == nil })

    let window = try XCTUnwrap(document.rooms[0].openings.first { $0.id == "window-1" })
    XCTAssertEqual(window.sill?.valueMm ?? 0, 914 * factor, accuracy: 1)
    XCTAssertEqual(window.height?.valueMm ?? 0, 1219 * factor, accuracy: 1)
    XCTAssertEqual(window.width?.valueMm ?? 0, 914 * factor, accuracy: 2)
    let door = try XCTUnwrap(document.rooms[0].openings.first { $0.id == "door-1" })
    XCTAssertEqual(door.wallId, "wall-3")
    XCTAssertEqual(door.height?.valueMm ?? 0, 2031 * factor, accuracy: 1)
    let closetDoor = try XCTUnwrap(document.rooms[1].openings.first)
    XCTAssertEqual(closetDoor.wallId, "wall-5")
    XCTAssertNil(closetDoor.height)
    XCTAssertEqual(closetDoor.width?.valueMm ?? 0, 700 * factor, accuracy: 1)
  }

  func testClosetSitsWhereItWasWalked() throws {
    let conversion = try convert()
    let result = try SketchSolver.solve(
      conversion.measurements, context: SketchSolveContext(label: "Floor 2"))
    let bedroom = result.model.rooms[0].polygon
    let closet = result.model.rooms[1].polygon
    let walkedBedroom = try XCTUnwrap(conversion.corners["room-1"])
    let walkedCloset = try XCTUnwrap(conversion.corners["room-2"])
    for (solved, walked) in zip(bedroom, walkedBedroom) {
      // Squared by the solver from corner 0 and wall 1; the example's taps carry a few cm of
      // tap noise, so the far corners move by up to that.
      assertPoint(solved, plan(walked), within: 0.040, "bedroom")
    }
    for (solved, walked) in zip(closet, walkedCloset) {
      assertPoint(solved, plan(walked), within: 0.010, "closet")
    }
    // The closet is beside the bedroom's wall 4 (x = 0), its inside face a partition away: no
    // overlap, and the gap no wider than an exterior wall.
    let bedroomMinX = bedroom.map(\.x).min() ?? 0
    let closetMaxX = closet.map(\.x).max() ?? 0
    XCTAssertLessThan(closetMaxX, bedroomMinX)
    XCTAssertLessThanOrEqual(bedroomMinX - closetMaxX, SketchDefaults.exteriorWallThicknessMm / 1000)
    XCTAssertEqual(result.summary.measurements, .complete, "a door height alone does not limit")
    XCTAssertTrue(
      result.notes.contains {
        if case .openingEstimated("door-2", .height) = $0.kind { return true }
        return false
      }, "door-2 has no head tap")
    XCTAssertEqual(result.summary.ceilingHeightSource, .measured)
    XCTAssertEqual(result.summary.wallsMeasured, 8)
    try validate(result.model, schema: "capture-model.schema.json")
  }

  func testCaptureRecordWithTheSummaryValidates() throws {
    let conversion = try convert()
    let solved = try SketchSolver.solve(
      conversion.measurements, context: SketchSolveContext(label: "Floor 2"))
    let log = try example()
    let record = CaptureRecord(
      visitId: log.visitId, hub: CaptureRecord.HubProject(dealId: "example-deal-0001"),
      address: CaptureRecord.Address(
        formatted: "12 Example Lane", confirmedOnSite: true, confirmedAt: log.startedAt),
      operator: CaptureRecord.Operator(name: "Test Operator"),
      device: CaptureRecord.Device(
        model: "iPhone17,3", osName: .iOS, osVersion: "26.0.1", hasLidar: false),
      app: CaptureRecord.AppInfo(version: "1.0.0", build: "42"), visitedAt: log.startedAt,
      captures: [
        CaptureRecord.Capture(
          captureId: log.captureId, areaKey: log.areaKey, label: "Floor 2", mode: .floor,
          units: CaptureRecord.Units(display: .imperial), capturedAt: log.startedAt,
          finishedAt: log.finishedAt, captureSource: .walkthrough, sketch: solved.summary,
          walkthrough: conversion.summary)
      ])
    try validate(record, schema: "capture-record.schema.json")
  }
}
