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
  /// The capture's place in the record, from 1: the plan sheet's "SHEET n".
  public var sheetNumber: Int
  /// The device's marketing name, or its model identifier when it has none.
  public var deviceName: String
  public var hasLidar: Bool
  /// The app's version without the build, for example `1.0.0`.
  public var appShortVersion: String
  /// False for a scan kept without a capture record (`init(unrecordedScan:capturedAt:)`): the
  /// plan sheet then prints "not recorded" for what only the record knows.
  public private(set) var isRecorded = true

  public init(record: CaptureRecord, captureId: LowercaseUUID) throws {
    guard let index = record.captures.firstIndex(where: { $0.captureId == captureId }) else {
      throw PlanExportError.captureNotInRecord(captureId: captureId.rawValue)
    }
    let capture = record.captures[index]
    sheetNumber = index + 1
    deviceName = record.device.marketingName ?? record.device.model
    hasLidar = record.device.hasLidar
    appShortVersion = record.app.version
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

  /// The context of a scan kept without a capture record: a v1 scan on the phone, or a raw scan
  /// drawn alone by tools/plan-render. Nothing the record would give is made up: the sheet
  /// prints "not recorded" for the HUB deal, the capture id, the operator, the device and the
  /// mode, "Address not recorded" unless an `address` is known, "No compass reading" unless a
  /// `compass` state is known, and no rooms not scanned. `label` is the scan's title (the
  /// sheet's "SHEET 1 · LABEL"); `capturedAt` is when the scan was made as far as it is known
  /// (its file's date). The plan is drawn on the room and floor ladder (1:50 to 1:200).
  public init(
    unrecordedScan label: String, capturedAt: UTCTimestamp, address: String? = nil,
    compass: CompassState? = nil
  ) {
    let notRecorded = "not recorded"
    isRecorded = false
    sheetNumber = 1
    deviceName = notRecorded
    hasLidar = false
    appShortVersion = notRecorded
    let known = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.address = known.isEmpty ? "Address not recorded" : known
    addressConfirmedOnSite = false
    addressConfirmedAt = nil
    dealId = notRecorded
    projectName = nil
    visitId = notRecorded
    captureId = notRecorded
    areaKey = "scan"
    floorLabel = label
    mode = .floor
    self.capturedAt = capturedAt
    finishedAt = nil
    operatorName = "operator \(notRecorded)"
    deviceDescription = notRecorded
    appVersion = notRecorded
    displayUnits = .imperial
    coverageNotes = ""
    omittedRooms = []
    inaccessibleRooms = []
    self.compass = compass ?? .notVerified(.noReading, accuracy: nil)
  }

  /// Title-block project line: the project name when there is one, with the HUB deal id.
  var projectLine: String {
    if let projectName, !projectName.isEmpty { return "\(projectName) (deal \(dealId))" }
    return "Deal \(dealId)"
  }

  /// Capture date, UTC, for example `2026-10-17`.
  var captureDate: String { String(capturedAt.rawValue.prefix(10)) }

  /// The project's title on the plan sheet: the HUB project name, or the address when there is
  /// none.
  var projectTitle: String {
    if let projectName, !projectName.trimmingCharacters(in: .whitespaces).isEmpty {
      return projectName
    }
    return address
  }

  /// True when there is no project name, so the sheet's title shows the address in its place
  /// (on line 1 when it fits there, see `PlanSheetLayout`).
  var titleShowsAddress: Bool {
    projectName.map { $0.trimmingCharacters(in: .whitespaces).isEmpty } ?? true
  }

  /// The capture date as printed, in `ChapterBrand.printTimeZone` (America/New_York), for
  /// example `Oct 17, 2026`: English three-letter month, no leading zero, locale independent.
  var capturedDateText: String { PrintDate.text(capturedAt) }

  /// PDF date string for the capture time.
  var pdfDate: String { PDFDate.string(capturedAt) }
}

/// Dates as the plans print them (critique R-34): the day in America/New_York, the time zone
/// of the station's spatial report, as `Oct 17, 2026`.
enum PrintDate {
  static let months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]

  static func text(_ timestamp: UTCTimestamp, timeZone: TimeZone = ChapterBrand.printTimeZone)
    -> String
  {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp.secondsSince1970))
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    let month = months[max(0, min(11, (parts.month ?? 1) - 1))]
    return "\(month) \(parts.day ?? 1), \(parts.year ?? 1970)"
  }
}

/// PDF date strings (`D:YYYYMMDDHHmmSSZ`, UTC).
enum PDFDate {
  static func string(_ timestamp: UTCTimestamp) -> String {
    // `YYYY-MM-DDTHH:MM:SSZ`: its fourteen digits in order.
    "D:\(String(timestamp.rawValue.filter(\.isNumber).prefix(14)))Z"
  }
}
