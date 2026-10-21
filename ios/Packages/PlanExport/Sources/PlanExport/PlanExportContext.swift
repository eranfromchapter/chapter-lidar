import CaptureContract
import Foundation

/// Visit and capture metadata printed in title blocks and reports, taken from the capture record.
public struct PlanExportContext: Hashable, Sendable {
  public var address: String
  public var addressConfirmedOnSite: Bool
  public var addressConfirmedAt: UTCTimestamp?
  public var dealId: String
  public var projectName: String?
  public var visitId: String
  public var captureId: String
  public var areaKey: String
  public var floorLabel: String
  public var mode: CaptureMode
  public var capturedAt: UTCTimestamp
  public var finishedAt: UTCTimestamp?
  public var operatorName: String
  public var deviceDescription: String
  public var appVersion: String
  public var displayUnits: DisplayUnitSystem
  public var coverageNotes: String
  public var omittedRooms: [CaptureRecord.RoomNote]
  public var inaccessibleRooms: [CaptureRecord.RoomNote]
  /// The capture's compass reading as its orientation state (`CompassState(capture)`): the north
  /// symbol of every plan drawn for it. A capture without a reading (any 1.0.0 record) is not
  /// verified, "No compass reading".
  public var compass: CompassState

  public init(record: CaptureRecord, captureId: LowercaseUUID) throws {
    guard let capture = record.captures.first(where: { $0.captureId == captureId }) else {
      throw PlanExportError.captureNotInRecord(captureId: captureId.rawValue)
    }
    address = record.address.formatted
    addressConfirmedOnSite = record.address.confirmedOnSite
    addressConfirmedAt = record.address.confirmedAt
    dealId = record.hub.dealId
    projectName = record.hub.projectName
    visitId = record.visitId.rawValue
    self.captureId = capture.captureId.rawValue
    areaKey = capture.areaKey
    floorLabel = capture.label
    mode = capture.mode
    capturedAt = capture.capturedAt
    finishedAt = capture.finishedAt
    operatorName = record.operator.name
    let device = record.device
    let name = device.marketingName.map { "\($0) (\(device.model))" } ?? device.model
    deviceDescription = "\(name), \(device.osName.rawValue) \(device.osVersion)"
    appVersion = "\(record.app.version) (build \(record.app.build))"
    displayUnits = capture.units.display
    coverageNotes = capture.coverageNotes
    omittedRooms = capture.omittedRooms
    inaccessibleRooms = capture.inaccessibleRooms
    compass = CompassState(capture)
  }

  /// Title-block project line: the project name when there is one, with the HUB deal id.
  var projectLine: String {
    if let projectName, !projectName.isEmpty { return "\(projectName) (deal \(dealId))" }
    return "Deal \(dealId)"
  }

  /// Capture date, UTC, for example `2026-10-17`.
  var captureDate: String { String(capturedAt.rawValue.prefix(10)) }

  /// PDF date string for the capture time.
  var pdfDate: String { PDFDate.string(capturedAt) }
}

/// PDF date strings (`D:YYYYMMDDHHmmSSZ`, UTC).
enum PDFDate {
  static func string(_ timestamp: UTCTimestamp) -> String {
    // `YYYY-MM-DDTHH:MM:SSZ`: its fourteen digits in order.
    "D:\(String(timestamp.rawValue.filter(\.isNumber).prefix(14)))Z"
  }
}
