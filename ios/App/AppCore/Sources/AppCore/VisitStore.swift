import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import PackageCore

/// `<workspace>/visit.json` (phone-capture §5.2, critique R-26): the visit in progress, so the
/// Captures home can list it and reopen it after the app is relaunched. App-private: not in the
/// package and not in the contract. `formatVersion` stays 1; later fields are additive.
///
/// ```json
/// { "formatVersion": 1,
///   "createdAt": "2026-10-21T13:02:11Z",
///   "updatedAt": "2026-10-21T14:40:03Z",
///   "record": { /* CaptureRecord */ },
///   "noRoomsSkipped": { "confirmedCaptureIds": ["…"] },
///   "isSealed": false,
///   "revision": { "number": 2, "basePackageId": "…", "startedAt": "…" } }
/// ```
///
/// `revision` is present only in revision mode (revision n ≥ 2 started by "Add to this
/// capture" and not sealed yet); `isSealed` is false while it is.
public struct VisitFile: Codable, Equatable, Sendable {
  public static let currentFormatVersion = 1

  /// Revision mode: which revision is being captured, on which sealed package.
  public struct Revision: Codable, Equatable, Sendable {
    public var number: Int
    public var basePackageId: LowercaseUUID
    public var startedAt: UTCTimestamp

    public init(number: Int, basePackageId: LowercaseUUID, startedAt: UTCTimestamp) {
      self.number = number
      self.basePackageId = basePackageId
      self.startedAt = startedAt
    }
  }

  public var formatVersion: Int
  public var createdAt: UTCTimestamp
  public var updatedAt: UTCTimestamp
  public var record: CaptureRecord
  public var noRoomsSkipped: NoRoomsSkippedConfirmation
  public var isSealed: Bool
  public var revision: Revision?

  public init(
    createdAt: UTCTimestamp, updatedAt: UTCTimestamp, record: CaptureRecord,
    noRoomsSkipped: NoRoomsSkippedConfirmation = NoRoomsSkippedConfirmation(),
    isSealed: Bool, revision: Revision? = nil
  ) {
    formatVersion = Self.currentFormatVersion
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.record = record
    self.noRoomsSkipped = noRoomsSkipped
    self.isSealed = isSealed
    self.revision = revision
  }

  /// The file of a visit as `flow` has it now. `revisionStartedAt`: when revision mode began
  /// (kept from the previous file; `now` for a revision that starts now).
  public init(
    flow: VisitFlow, record: CaptureRecord, createdAt: UTCTimestamp, now: UTCTimestamp,
    revisionStartedAt: UTCTimestamp? = nil
  ) {
    var revision: Revision?
    if flow.isRevisionMode, let base = flow.basePackageId {
      revision = Revision(
        number: flow.revision, basePackageId: base, startedAt: revisionStartedAt ?? now)
    }
    self.init(
      createdAt: createdAt, updatedAt: now, record: record, noRoomsSkipped: flow.noRoomsSkipped,
      isSealed: flow.isSealed, revision: revision)
  }

  /// The flow this file resumes at (the Capture overview). `sealedRevision` is the newest sealed
  /// package's revision on the phone (the revision a sealed visit shows).
  public func flow(sealedRevision: Int?) -> VisitFlow {
    if let revision, !isSealed {
      return VisitFlow(
        resuming: record, noRoomsSkipped: noRoomsSkipped, isSealed: false,
        revision: revision.number, basePackageId: revision.basePackageId, isRevisionMode: true)
    }
    return VisitFlow(
      resuming: record, noRoomsSkipped: sealedConfirmation, isSealed: isSealed,
      revision: sealedRevision ?? 1)
  }

  /// "All rooms scanned" as a sealed visit has it. Sealing needs "Rooms not scanned" to pass, so
  /// a sealed visit without the tap is one migrated from the v1 app before the migration kept it
  /// (the v1 app held the tap in memory only): it counts as confirmed for its captures, so the
  /// read-only overview never shows a ■ that cannot be fixed. A recorded skipped room still
  /// wins (`NoRoomsSkippedConfirmation.isConfirmed`).
  var sealedConfirmation: NoRoomsSkippedConfirmation {
    guard isSealed, noRoomsSkipped.confirmedCaptureIds == nil else { return noRoomsSkipped }
    var confirmed = noRoomsSkipped
    confirmed.confirm(for: record)
    return confirmed
  }
}

public enum VisitStoreError: Error, Equatable, Sendable, CustomStringConvertible {
  case unreadable(String)
  case unwritable(String)

  public var description: String {
    switch self {
    case .unreadable(let reason): return "The visit could not be read: \(reason)"
    case .unwritable(let reason): return "The visit could not be saved: \(reason)"
    }
  }
}

/// Reads and writes `visit.json`, and builds it for a workspace written by the v1 app.
public enum VisitStore {
  public static let fileName = "visit.json"

  private struct FormatVersion: Decodable {
    var formatVersion: Int
  }

  /// The visit's file; nil when the workspace has none (a v1 workspace, or an empty folder).
  public static func load(_ workspace: VisitWorkspace) throws -> VisitFile? {
    let url = workspace.visitURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      let data = try Data(contentsOf: url)
      let decoder = CaptureContractJSON.makeDecoder()
      // The version first: a file of a newer app says so, rather than a missing field.
      if let version = try? decoder.decode(FormatVersion.self, from: data).formatVersion,
        version != VisitFile.currentFormatVersion
      {
        throw VisitStoreError.unreadable("unknown format version \(version)")
      }
      return try decoder.decode(VisitFile.self, from: data)
    } catch let error as VisitStoreError {
      throw error
    } catch {
      throw VisitStoreError.unreadable(String(describing: error))
    }
  }

  /// Writes the file atomically (the folder is created when missing), protected until the first
  /// unlock on iOS: a torn write never replaces the previous file.
  public static func save(_ file: VisitFile, to workspace: VisitWorkspace) throws {
    do {
      try workspace.createFolder()
      let data = try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(file)
      #if os(iOS)
        try data.write(
          to: workspace.visitURL,
          options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      #else
        try data.write(to: workspace.visitURL, options: .atomic)
      #endif
    } catch {
      throw VisitStoreError.unwritable(String(describing: error))
    }
  }

  /// The visit's file, or for a workspace of the v1 app (no `visit.json`) one built from what it
  /// holds, and saved (`migrate`). Nil when there is neither, and when `visit.json` is there but
  /// cannot be read (it is never overwritten; `load` says why).
  public static func loadOrMigrate(_ workspace: VisitWorkspace) -> VisitFile? {
    if let file = try? load(workspace) { return file }
    guard !FileManager.default.fileExists(atPath: workspace.visitURL.path) else { return nil }
    return migrate(workspace)
  }

  /// The `visit.json` of a workspace the v1 app wrote, built from what it holds, and saved: the
  /// capture record of its newest sealed package (then the visit is sealed, and "All rooms
  /// scanned" counts as confirmed: the v1 app sealed only after that checklist item passed),
  /// else of its newest "Package ready" draft (not sealed; "All rooms scanned" is asked again).
  /// Nil when there is neither (an empty folder, or scans without a capture record:
  /// `legacyScans`). Nothing is deleted or moved.
  static func migrate(_ workspace: VisitWorkspace) -> VisitFile? {
    let packages = sealedPackages(of: workspace)
    let source: (record: CaptureRecord, date: Date, sealed: Bool)?
    if let newest = packages.last, let record = SealedPackageSummary.captureRecord(of: newest) {
      source = (record, newest.manifest.sealedAt.date, true)
    } else if let draft = newestDraftRecord(of: workspace) {
      source = (draft.record, draft.date, false)
    } else {
      source = nil
    }
    guard let source else { return nil }
    let created = folderDate(workspace.root) ?? source.record.visitedAt.date
    var noRoomsSkipped = NoRoomsSkippedConfirmation()
    if source.sealed { noRoomsSkipped.confirm(for: source.record) }
    let file = VisitFile(
      createdAt: UTCTimestamp(min(created, source.date)), updatedAt: UTCTimestamp(source.date),
      record: source.record, noRoomsSkipped: noRoomsSkipped, isSealed: source.sealed)
    // Best effort: a workspace that cannot be written to still lists from memory.
    try? save(file, to: workspace)
    return file
  }

  /// The workspace's field controls (`controls/Field Measurements/{visitId}/field-controls.json`),
  /// nil before the first saved control.
  public static func loadControls(_ workspace: VisitWorkspace, visitId: LowercaseUUID) throws
    -> FieldControls?
  {
    let url = workspace.controlsRoot.appendingPathComponent(
      FieldControlsFile.relativePath(visitId: visitId))
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      return try CaptureContractJSON.makeDecoder().decode(
        FieldControls.self, from: Data(contentsOf: url))
    } catch {
      throw VisitStoreError.unreadable("field-controls.json: \(error)")
    }
  }

  /// The workspace's sealed packages that open, oldest first (by revision, then sealing time):
  /// the last is the newest revision.
  public static func sealedPackages(of workspace: VisitWorkspace) -> [SealedPackage] {
    let fileManager = FileManager.default
    guard
      let folders = try? fileManager.contentsOfDirectory(
        at: workspace.packagesRoot, includingPropertiesForKeys: nil)
    else { return [] }
    return folders.compactMap { folder -> SealedPackage? in
      var isDirectory: ObjCBool = false
      guard !folder.lastPathComponent.hasPrefix("."),
        fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { return nil }
      return try? SealedPackage.open(at: folder)
    }
    .sorted {
      ($0.manifest.revision, $0.manifest.sealedAt, $0.packageId.rawValue)
        < ($1.manifest.revision, $1.manifest.sealedAt, $1.packageId.rawValue)
    }
  }

  /// A scan the v1 app wrote before any capture record was kept for its visit.
  public struct LegacyScan: Hashable, Sendable {
    /// `<workspace>/originals/Original Exports/{areaKey}/{captureId}/`.
    public var folder: URL
    public var areaKey: String
    /// When its `roomplan.json` was written.
    public var date: Date
  }

  /// The scans of a v1 workspace for which `loadOrMigrate` found no capture record (the v1 app
  /// kept it only in memory until "Package ready"), newest first. Empty for a workspace with a
  /// `visit.json`, a sealed package or a draft.
  public static func legacyScans(of workspace: VisitWorkspace) -> [LegacyScan] {
    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: workspace.visitURL.path),
      sealedPackages(of: workspace).isEmpty, newestDraftRecord(of: workspace) == nil
    else { return [] }
    let exports = workspace.originalsRoot.appendingPathComponent(
      PackageFolder.originalExports.name, isDirectory: true)
    var scans: [LegacyScan] = []
    for area in children(of: exports) {
      for capture in children(of: area) {
        let file = capture.appendingPathComponent(
          RawOriginalsNaming.originals.roomPlanFileName)
        guard
          let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        else { continue }
        scans.append(LegacyScan(folder: capture, areaKey: area.lastPathComponent, date: date))
      }
    }
    return scans.sorted { $0.date != $1.date ? $0.date > $1.date : $0.folder.path < $1.folder.path }
  }

  // MARK: Private

  /// The newest capture record written by "Package ready" (`drafts/<draft>/Source
  /// Register/<visitId>/capture-record.json`).
  static func newestDraftRecord(of workspace: VisitWorkspace) -> (record: CaptureRecord, date: Date)? {
    var newest: (record: CaptureRecord, date: Date)?
    for draft in children(of: workspace.draftsRoot) {
      let register = draft.appendingPathComponent(PackageFolder.sourceRegister.name)
      for folder in children(of: register) {
        let url = folder.appendingPathComponent(PackageLayout.captureRecordFileName)
        guard
          let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate,
          newest == nil || date > newest!.date,
          let data = try? Data(contentsOf: url),
          let record = try? CaptureContractJSON.makeDecoder().decode(CaptureRecord.self, from: data)
        else { continue }
        newest = (record, date)
      }
    }
    return newest
  }

  private static func folderDate(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
  }

  private static func children(of folder: URL) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
      ?? []).filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.path < $1.path }
  }
}
