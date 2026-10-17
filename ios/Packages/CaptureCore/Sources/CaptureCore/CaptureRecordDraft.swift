import CaptureContract
import Foundation

/// Device, OS and app version, filled in automatically (never typed by the operator).
public struct DeviceInfo: Sendable, Equatable {
  public var model: String
  public var marketingName: String?
  public var osName: DeviceOSName
  public var osVersion: String
  public var hasLidar: Bool

  public init(model: String, marketingName: String? = nil, osName: DeviceOSName, osVersion: String, hasLidar: Bool) {
    self.model = model
    self.marketingName = marketingName
    self.osName = osName
    self.osVersion = osVersion
    self.hasLidar = hasLidar
  }
}

public enum CaptureRecordValidationError: Error, Hashable, Sendable, CustomStringConvertible {
  case missingProject
  case projectInvalid
  case addressNotConfirmed
  case missingFloorLabel
  case floorLabelTooLong
  case floorLabelHasNoKey
  case missingMode
  case missingOperator
  case coverageNotesTooLong
  case roomNoteInvalid
  case deviceInvalid
  case appInvalid

  /// Shown next to the field.
  public var description: String {
    switch self {
    case .missingProject: return "Choose the HUB project."
    case .projectInvalid: return "The HUB project has no usable deal id or address."
    case .addressNotConfirmed: return "Confirm that you are at this address."
    case .missingFloorLabel: return "Enter the floor or area."
    case .floorLabelTooLong: return "The floor or area name is too long (100 characters at most)."
    case .floorLabelHasNoKey: return "Use letters or numbers in the floor or area name."
    case .missingMode: return "Choose what you are scanning."
    case .missingOperator: return "No signed-in operator."
    case .coverageNotesTooLong: return "Coverage notes are too long (2000 characters at most)."
    case .roomNoteInvalid: return "A room needs a name (100 characters at most) and a short reason."
    case .deviceInvalid: return "Device information is incomplete."
    case .appInvalid: return "App version information is incomplete."
    }
  }
}

public struct CaptureRecordValidationFailure: Error, Equatable, CustomStringConvertible {
  public var errors: [CaptureRecordValidationError]

  public var description: String {
    errors.map(\.description).joined(separator: " ")
  }
}

/// The capture-record form: what the operator enters on "New capture" and "What are you
/// scanning?". `build` is the only way to a `CaptureRecord`, and it refuses a draft without a
/// project, a confirmed address, a floor label and a mode.
public struct CaptureRecordDraft: Sendable, Equatable {
  public private(set) var project: HubProjectSummary?
  /// When the operator ticked "I am at this address"; nil while unconfirmed.
  public private(set) var addressConfirmedAt: UTCTimestamp?

  public var operatorName: String
  public var operatorUserId: String?
  public var floorLabel: String
  public var mode: CaptureMode?
  public var displayUnits: DisplayUnitSystem
  public var coverageNotes: String
  /// "Rooms you will not scan".
  public var omittedRooms: [CaptureRecord.RoomNote]
  /// Rooms or spaces that could not be entered.
  public var inaccessibleRooms: [CaptureRecord.RoomNote]
  public var device: DeviceInfo
  public var app: CaptureRecord.AppInfo

  public static let maxFloorLabelLength = 100
  public static let maxCoverageNotesLength = 2000
  public static let maxRoomNameLength = 100
  public static let maxRoomReasonLength = 300

  public init(
    operatorName: String, operatorUserId: String? = nil, device: DeviceInfo, app: CaptureRecord.AppInfo,
    displayUnits: DisplayUnitSystem = .imperial
  ) {
    self.operatorName = operatorName
    self.operatorUserId = operatorUserId
    self.device = device
    self.app = app
    self.displayUnits = displayUnits
    self.floorLabel = ""
    self.mode = nil
    self.coverageNotes = ""
    self.omittedRooms = []
    self.inaccessibleRooms = []
  }

  public var isAddressConfirmed: Bool { addressConfirmedAt != nil }

  /// Picks a project. A new project has a new address, so the confirmation is cleared.
  public mutating func select(_ project: HubProjectSummary) {
    if project != self.project {
      addressConfirmedAt = nil
    }
    self.project = project
  }

  /// Ticks or unticks "I am at this address". Ticking needs a project.
  public mutating func setAddressConfirmed(_ confirmed: Bool, at time: UTCTimestamp) {
    addressConfirmedAt = (confirmed && project != nil) ? time : nil
  }

  /// Path-safe key of the floor or area: lowercase letters and digits joined by hyphens
  /// ("Floor 1" becomes "floor-1"). Nil when the label has none.
  public var areaKey: String? {
    CaptureRecordDraft.areaKey(for: floorLabel)
  }

  public static func areaKey(for label: String) -> String? {
    var key = ""
    var pendingHyphen = false
    for scalar in label.lowercased().unicodeScalars {
      let isAlphanumeric =
        (scalar.value >= 0x30 && scalar.value <= 0x39) || (scalar.value >= 0x61 && scalar.value <= 0x7A)
      if isAlphanumeric {
        if pendingHyphen && !key.isEmpty { key.append("-") }
        pendingHyphen = false
        key.unicodeScalars.append(scalar)
      } else {
        pendingHyphen = true
      }
    }
    if key.count > 64 {
      key = String(key.prefix(64))
      while key.hasSuffix("-") { key.removeLast() }
    }
    return key.isEmpty ? nil : key
  }

  /// Every problem with the draft, in the order the form shows the fields. Empty when it can be saved.
  public func validate() -> [CaptureRecordValidationError] {
    var errors: [CaptureRecordValidationError] = []
    if let project {
      let deal = project.dealId.trimmingCharacters(in: .whitespacesAndNewlines)
      let address = project.address.trimmingCharacters(in: .whitespacesAndNewlines)
      if deal.isEmpty || deal.count > 64 || address.isEmpty || address.count > 300
        || project.projectName.count > 200
      {
        errors.append(.projectInvalid)
      }
    } else {
      errors.append(.missingProject)
    }
    if !isAddressConfirmed {
      errors.append(.addressNotConfirmed)
    }
    let label = floorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    if label.isEmpty {
      errors.append(.missingFloorLabel)
    } else if label.count > Self.maxFloorLabelLength {
      errors.append(.floorLabelTooLong)
    } else if areaKey == nil {
      errors.append(.floorLabelHasNoKey)
    }
    if mode == nil {
      errors.append(.missingMode)
    }
    if operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.append(.missingOperator)
    }
    if coverageNotes.count > Self.maxCoverageNotesLength {
      errors.append(.coverageNotesTooLong)
    }
    let notes = omittedRooms + inaccessibleRooms
    if notes.contains(where: { !Self.isValid($0) }) {
      errors.append(.roomNoteInvalid)
    }
    if device.model.isEmpty || device.model.count > 64 || !Self.isDotted(device.osVersion, maxParts: 3, minParts: 1) {
      errors.append(.deviceInvalid)
    }
    if !Self.isDotted(app.version, maxParts: 3, minParts: 3) || app.build.isEmpty || app.build.count > 32 {
      errors.append(.appInvalid)
    }
    return errors
  }

  public var canSave: Bool { validate().isEmpty }

  /// The capture record of a new visit with this one capture. Throws
  /// `CaptureRecordValidationFailure` unless `validate()` is empty.
  public func build(
    visitId: LowercaseUUID = LowercaseUUID(), captureId: LowercaseUUID = LowercaseUUID(),
    visitedAt: UTCTimestamp, capturedAt: UTCTimestamp? = nil
  ) throws -> CaptureRecord {
    let errors = validate()
    guard errors.isEmpty, let project, let mode, let areaKey, let confirmedAt = addressConfirmedAt else {
      throw CaptureRecordValidationFailure(errors: errors)
    }
    let projectName = project.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    return CaptureRecord(
      visitId: visitId,
      hub: CaptureRecord.HubProject(
        dealId: project.dealId.trimmingCharacters(in: .whitespacesAndNewlines),
        projectName: projectName.isEmpty ? nil : projectName),
      address: CaptureRecord.Address(
        formatted: project.address.trimmingCharacters(in: .whitespacesAndNewlines), confirmedOnSite: true,
        confirmedAt: confirmedAt),
      operator: CaptureRecord.Operator(
        name: operatorName.trimmingCharacters(in: .whitespacesAndNewlines), userId: operatorUserId),
      device: CaptureRecord.Device(
        model: device.model, marketingName: device.marketingName, osName: device.osName,
        osVersion: device.osVersion, hasLidar: device.hasLidar),
      app: app,
      visitedAt: visitedAt,
      captures: [
        CaptureRecord.Capture(
          captureId: captureId, areaKey: areaKey,
          label: floorLabel.trimmingCharacters(in: .whitespacesAndNewlines), mode: mode,
          units: CaptureRecord.Units(display: displayUnits), capturedAt: capturedAt ?? visitedAt,
          coverageNotes: coverageNotes, omittedRooms: omittedRooms, inaccessibleRooms: inaccessibleRooms)
      ])
  }

  private static func isValid(_ note: CaptureRecord.RoomNote) -> Bool {
    let name = note.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= maxRoomNameLength else { return false }
    if let reason = note.reason {
      return !reason.isEmpty && reason.count <= maxRoomReasonLength
    }
    return true
  }

  /// "26.0.1": digits separated by dots, `minParts` to `maxParts` parts.
  private static func isDotted(_ text: String, maxParts: Int, minParts: Int) -> Bool {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    return (minParts...maxParts).contains(parts.count)
      && parts.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }
  }
}

extension CaptureRecord {
  /// This record with one more capture (another floor or area of the same visit). Throws when the
  /// capture id or area key is already in the record.
  public func appending(_ capture: Capture) throws -> CaptureRecord {
    guard !captures.contains(where: { $0.captureId == capture.captureId || $0.areaKey == capture.areaKey })
    else { throw CaptureRecordValidationFailure(errors: [.floorLabelHasNoKey]) }
    var copy = self
    copy.captures.append(capture)
    return copy
  }
}

extension CaptureRecord.AppInfo {
  /// App info from the bundle's `CFBundleShortVersionString` and `CFBundleVersion`. The contract
  /// wants `major.minor.patch`, so `1.2` becomes `1.2.0`. Nil when either value is missing or the
  /// version is not dotted numbers.
  public static func normalized(version: String?, build: String?) -> CaptureRecord.AppInfo? {
    guard let version, let build, !build.isEmpty else { return nil }
    var parts = version.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard (1...3).contains(parts.count),
      parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } })
    else { return nil }
    while parts.count < 3 { parts.append("0") }
    return CaptureRecord.AppInfo(version: parts.joined(separator: "."), build: build)
  }

  public static func from(bundle: Bundle = .main) -> CaptureRecord.AppInfo? {
    normalized(
      version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
  }
}
