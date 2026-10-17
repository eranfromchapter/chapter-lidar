import CaptureContract
import FieldRules
import Foundation

/// Shared builders for the rule and controls tests. Ids match contract/examples.
enum Fixtures {
  /// The repository root (this file is ios/Packages/FieldKit/Tests/FieldRulesTests/Support/).
  static let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Support
    .deletingLastPathComponent()  // FieldRulesTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // FieldKit
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // ios
    .deletingLastPathComponent()  // repository root

  static let visitId = LowercaseUUID(rawValue: "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")!
  static let floor1Id = LowercaseUUID(rawValue: "3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35")!
  static let floor2Id = LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!

  static let floor1 = FieldControls.CaptureRef(captureId: floor1Id, areaKey: "floor-1")
  static let floor2 = FieldControls.CaptureRef(captureId: floor2Id, areaKey: "floor-2")

  static let t0 = UTCTimestamp(rawValue: "2026-10-17T14:02:11Z")!
  static let t1 = UTCTimestamp(rawValue: "2026-10-17T15:10:00Z")!

  static func capture(
    _ id: LowercaseUUID, areaKey: String, label: String, mode: CaptureMode = .floor,
    at: UTCTimestamp = t0, omitted: [CaptureRecord.RoomNote] = [],
    inaccessible: [CaptureRecord.RoomNote] = []
  ) -> CaptureRecord.Capture {
    CaptureRecord.Capture(
      captureId: id, areaKey: areaKey, label: label, mode: mode,
      units: CaptureRecord.Units(display: .imperial), capturedAt: at,
      omittedRooms: omitted, inaccessibleRooms: inaccessible)
  }

  static func record(
    captures: [CaptureRecord.Capture], operatorName: String = "Alex Rivera",
    deviceModel: String = "iPhone17,1", osVersion: String = "26.0",
    visitedAt: UTCTimestamp = t0
  ) -> CaptureRecord {
    CaptureRecord(
      visitId: visitId,
      hub: CaptureRecord.HubProject(dealId: "deal-1"),
      address: CaptureRecord.Address(
        formatted: "618 Valley Street", confirmedOnSite: true, confirmedAt: t0),
      operator: CaptureRecord.Operator(name: operatorName),
      device: CaptureRecord.Device(
        model: deviceModel, osName: .iOS, osVersion: osVersion, hasLidar: true),
      app: CaptureRecord.AppInfo(version: "1.0.0", build: "1"),
      visitedAt: visitedAt,
      captures: captures)
  }

  static func measurement(_ text: String, _ unit: EnteredUnit) throws -> FieldControls.Measurement {
    try FieldMeasurement.make(text: text, unit: unit, method: .tape, recordedAt: t0)
  }

  static func photo(
    capture: FieldControls.CaptureRef, room: String, sequence: Int = 1,
    direction: PhotoDirection = .north, subject: PhotoSubject = .general
  ) -> PhotoRecord {
    PhotoRecord(
      captureId: capture.captureId, areaKey: capture.areaKey, sequence: sequence,
      path: "Site Photos/\(capture.areaKey)/\(capture.captureId.rawValue)/photo-000\(sequence).jpg",
      format: .jpeg, sha256: String(repeating: "0", count: 64), bytes: 10,
      labels: PackageManifest.PhotoLabels(
        room: room, direction: direction, subject: subject, takenAt: t0))
  }
}
