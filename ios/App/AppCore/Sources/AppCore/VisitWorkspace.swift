import Foundation

/// The folders of one site visit on the phone, all under one root
/// (`<Application Support>/Visits/<workspace id>/`).
///
/// - `visit.json`: the visit in progress (`VisitStore`): its capture record, the operator's
///   "All rooms scanned" tap, whether it is sealed and, in revision mode, which revision it
///   builds. App-private: not in the package, not in the contract. The Captures home lists the
///   visits from it, and a visit resumes from it after a relaunch.
/// - `originals/`: raw scan originals, `Original Exports/{areaKey}/{captureId}/` (CaptureFlowModel).
/// - `photos/`: site photo originals, `Site Photos/{areaKey}/{captureId}/` (PhotoRecordStore).
/// - `controls/`: `Field Measurements/{visitId}/field-controls.json` (FieldControlsFile).
/// - `drafts/<draft id>/`: files written when "Package ready" is built (capture record, capture
///   models, plan and mesh exports). A new draft folder per build; nothing is overwritten.
/// - `packages/<packageId>/`: sealed, read-only packages, with `<packageId>.upload-state.json`
///   and `<packageId>.station-status.json` (what the station last said) next to each.
/// - `room-names.json`: the operator's names for rooms of the captures (`VisitRoomNames`).
///   App-private: it is not in the package, whose capture models and photo labels carry the
///   names.
///
/// The folder is created by the first Start scan of a new capture (an abandoned New capture
/// leaves nothing on disk). Nothing in the app deletes any of these folders; "Delete all photos"
/// (field-test and UI-test modes, `PhotoEraser`) deletes only photo files in them.
public struct VisitWorkspace: Equatable, Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  /// Creates a new workspace folder under `visitsRoot`.
  public static func create(in visitsRoot: URL, id: UUID = UUID()) throws -> VisitWorkspace {
    let workspace = allocate(in: visitsRoot, id: id)
    try workspace.createFolder()
    return workspace
  }

  /// A workspace under `visitsRoot` that is not on disk yet (a New capture before its first
  /// Start scan).
  public static func allocate(in visitsRoot: URL, id: UUID = UUID()) -> VisitWorkspace {
    VisitWorkspace(
      root: visitsRoot.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true))
  }

  /// The workspace's id: its folder name.
  public var id: String { root.lastPathComponent }

  /// True once the folder exists.
  public var exists: Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  /// Creates the folder (and its parents) when it is not there yet.
  public func createFolder() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  public var originalsRoot: URL { folder("originals") }
  public var photosRoot: URL { folder("photos") }
  public var controlsRoot: URL { folder("controls") }
  public var draftsRoot: URL { folder("drafts") }
  public var packagesRoot: URL { folder("packages") }
  /// The operator's room names (`VisitRoomNames`).
  public var roomNamesURL: URL { root.appendingPathComponent(VisitRoomNames.fileName) }
  /// The visit in progress (`VisitStore`).
  public var visitURL: URL { root.appendingPathComponent(VisitStore.fileName) }

  /// Where a package is assembled and sealed.
  public func packageURL(packageId: String) -> URL {
    packagesRoot.appendingPathComponent(packageId, isDirectory: true)
  }

  /// What the station last said about a sealed package (`StationStatusStore`).
  public func stationStatusURL(packageId: String) -> URL {
    StationStatusStore.defaultURL(forPackageAt: packageURL(packageId: packageId))
  }

  private func folder(_ name: String) -> URL {
    root.appendingPathComponent(name, isDirectory: true)
  }
}
