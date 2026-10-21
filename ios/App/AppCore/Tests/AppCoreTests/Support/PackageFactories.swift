import CaptureContract
import Foundation
import PackageCore
import XCTest

@testable import AppCore

/// Small values for the package screens' tests.
enum Make {
  /// 2026-05-16 14:02:00 UTC.
  static let t1402 = UTCTimestamp(rawValue: "2026-05-16T14:02:00Z")!
  static let utc = TimeZone(identifier: "UTC")!

  static func time(_ text: String) -> UTCTimestamp {
    UTCTimestamp(rawValue: text)!
  }

  static func capture(
    _ label: String, mode: CaptureMode = .floor, captureId: LowercaseUUID = LowercaseUUID(),
    compass: CompassResultValue? = nil, omitted: [String] = [], inaccessible: [String] = []
  ) -> CaptureRecord.Capture {
    var capture = CaptureRecord.Capture(
      captureId: captureId, areaKey: label.lowercased().replacingOccurrences(of: " ", with: "-"),
      label: label, mode: mode, units: .init(display: .imperial),
      capturedAt: time("2026-05-16T13:00:00Z"), finishedAt: time("2026-05-16T13:20:00Z"),
      omittedRooms: omitted.map { CaptureRecord.RoomNote(name: $0) },
      inaccessibleRooms: inaccessible.map { CaptureRecord.RoomNote(name: $0, reason: "locked") })
    if let compass { capture.setCompass(compass) }
    return capture
  }

  /// A true-north reading of ±`accuracy`°, inside the scan.
  static func reading(accuracy: Int = 8, source: HeadingSource = .trueNorth) -> CompassResultValue {
    .reading(
      heading: 212.4, accuracy: accuracy, source: source,
      recordedAt: time("2026-05-16T13:01:00Z"))
  }

  static func record(
    _ captures: [CaptureRecord.Capture], projectName: String? = nil,
    address: String = "618 Valley Street", visitId: LowercaseUUID = LowercaseUUID()
  ) -> CaptureRecord {
    CaptureRecord(
      visitId: visitId, hub: .init(dealId: "4821", projectName: projectName),
      address: .init(formatted: address, confirmedOnSite: true),
      operator: .init(name: "Dana Ruiz"),
      device: .init(model: "iPhone17,1", osName: .iOS, osVersion: "26.0", hasLidar: true),
      app: .init(version: "2.0.0", build: "1"), visitedAt: time("2026-05-16T12:55:00Z"),
      captures: captures)
  }

  static func verdict(
    _ outcome: VerdictOutcome, task: String = "Preliminary existing-condition plans",
    limitations: [String] = [], nextActions: [String] = [], findings: [Verdict.Finding] = [],
    evaluatedAt: UTCTimestamp = t1402
  ) -> Verdict {
    Verdict(
      verdictId: LowercaseUUID(), packageId: LowercaseUUID(), visitId: LowercaseUUID(),
      revision: 1, outcome: outcome, task: task, summary: "s", evaluatedAt: evaluatedAt,
      evaluator: .init(name: "chapter-capture-station/checks", version: "1.1.0"), checks: [],
      findings: findings, limitations: limitations, nextActions: nextActions)
  }

  static func finding(
    _ severity: FindingSeverity, _ message: String, measured: String? = nil, nextAction: String
  ) -> Verdict.Finding {
    Verdict.Finding(
      ruleId: "rule", severity: severity, message: message, measured: measured,
      nextAction: nextAction)
  }

  static func station(
    _ stage: StationPackageStage, checks: StationPackageInfo.Checks? = nil,
    publication: StationPackageInfo.Publication? = nil, verdictId: LowercaseUUID? = nil
  ) -> StationPackageInfo {
    StationPackageInfo(
      stage: stage, createdAt: time("2026-05-16T14:00:00Z"), checks: checks,
      publication: publication,
      links: .init(review: "https://review.test/packages/1", hub: nil), verdictId: verdictId)
  }
}

/// A sealed box-room package in `base`, as revision 1 of a visit (`FixtureVisit`).
struct SealedFixture {
  let visit: FixtureVisit
  let builder: VisitPackageBuilder
  let plan: VisitPackagePlan
  let sealed: SealedPackage

  init(_ name: String = "box-room", in base: URL) throws {
    visit = try FixtureVisit(name, in: base)
    builder = VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0")
    plan = try builder.plan(record: visit.record, photos: visit.photos, controls: visit.controls)
    sealed = try PackageAssembler().assemble(
      plan.draft, at: visit.workspace.packageURL(packageId: plan.draft.packageId.rawValue),
      sealedAt: Make.time("2026-01-25T15:00:00Z"))
  }
}

/// A `PackageStatusSource` answering from a script: one `StationPackageInfo` per call (the last
/// one repeats), and verdicts by id.
final class ScriptedStatusSource: PackageStatusSource, @unchecked Sendable {
  private let lock = NSLock()
  private var answers: [Result<StationPackageInfo, Error>]
  private var verdicts: [LowercaseUUID: VerdictStatus]
  private var last: StationPackageInfo?
  private(set) var packageCalls = 0
  private(set) var verdictCalls = 0

  init(_ answers: [Result<StationPackageInfo, Error>], verdicts: [VerdictStatus] = []) {
    self.answers = answers
    self.verdicts = Dictionary(verdicts.map { ($0.verdictId, $0) }, uniquingKeysWith: { a, _ in a })
  }

  func package(packageId: UUID) async throws -> StationPackageInfo {
    try lock.withLock { () throws -> StationPackageInfo in
      packageCalls += 1
      let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
      let station = try answer.get()
      last = station
      return station
    }
  }

  /// The verdict of the last package answer.
  func verdict(packageId: UUID) async throws -> VerdictStatus {
    try lock.withLock { () throws -> VerdictStatus in
      verdictCalls += 1
      guard let id = last?.verdictId, let verdict = verdicts[id] else {
        throw StationAPIError.notFound(nil)
      }
      return verdict
    }
  }

  var calls: (package: Int, verdict: Int) { lock.withLock { (packageCalls, verdictCalls) } }
}
