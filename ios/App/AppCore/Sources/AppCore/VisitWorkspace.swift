import Foundation

/// The folders of one site visit on the phone, all under one root
/// (`<Application Support>/Visits/<workspace id>/`).
///
/// - `originals/`: raw scan originals, `Original Exports/{areaKey}/{captureId}/` (CaptureFlowModel).
/// - `photos/`: site photo originals, `Site Photos/{areaKey}/{captureId}/` (PhotoRecordStore).
/// - `controls/`: `Field Measurements/{visitId}/field-controls.json` (FieldControlsFile).
/// - `drafts/<draft id>/`: files written when "Package ready" is built (capture record, capture
///   models, plan and mesh exports). A new draft folder per build; nothing is overwritten.
/// - `packages/<packageId>/`: sealed, read-only packages, with `<packageId>.upload-state.json`
///   next to each.
///
/// Nothing in the app deletes any of these folders (there is no delete in v1).
public struct VisitWorkspace: Equatable, Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  /// Creates a new workspace folder under `visitsRoot`.
  public static func create(in visitsRoot: URL, id: UUID = UUID()) throws -> VisitWorkspace {
    let workspace = VisitWorkspace(
      root: visitsRoot.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true))
    try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
    return workspace
  }

  public var originalsRoot: URL { folder("originals") }
  public var photosRoot: URL { folder("photos") }
  public var controlsRoot: URL { folder("controls") }
  public var draftsRoot: URL { folder("drafts") }
  public var packagesRoot: URL { folder("packages") }

  /// Where a package is assembled and sealed.
  public func packageURL(packageId: String) -> URL {
    packagesRoot.appendingPathComponent(packageId, isDirectory: true)
  }

  private func folder(_ name: String) -> URL {
    root.appendingPathComponent(name, isDirectory: true)
  }
}
