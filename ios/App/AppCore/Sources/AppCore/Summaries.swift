import CaptureContract
import Foundation
import PackageCore

/// Byte counts as the design writes them: "312 MB", "512 of 768 MB" (decimal units).
public enum ByteText {
  private static let units: [(String, Double)] = [("GB", 1e9), ("MB", 1e6), ("KB", 1e3)]

  public static func format(_ bytes: Int64) -> String {
    let unit = unit(for: bytes)
    return "\(number(bytes, unit.1)) \(unit.0)"
  }

  /// "512 of 768 MB": both numbers in the unit of `total`.
  public static func progress(_ done: Int64, of total: Int64) -> String {
    let unit = unit(for: total)
    return "\(number(done, unit.1)) of \(number(total, unit.1)) \(unit.0)"
  }

  private static func unit(for bytes: Int64) -> (String, Double) {
    units.first { Double(bytes) >= $0.1 } ?? ("bytes", 1)
  }

  private static func number(_ bytes: Int64, _ scale: Double) -> String {
    let value = Double(bytes) / scale
    if scale > 1, value < 10, value.rounded() != value {
      return String(format: "%.1f", value)
    }
    return String(Int64(value.rounded()))
  }
}

/// What "Package ready" shows (design screen-package, 1).
public struct PackageReview: Equatable, Sendable {
  /// One "Original Exports · Floor 1" row.
  public struct CaptureGroup: Equatable, Sendable {
    public var label: String
    /// "Plan DXF · Rooms CSV · ... · raw RoomPlan + depth".
    public var kinds: String
    public var fileCount: Int
    public var bytes: Int64

    /// "14 files · 312 MB".
    public var countText: String {
      "\(fileCount) \(fileCount == 1 ? "file" : "files") \u{00B7} \(ByteText.format(bytes))"
    }
  }

  public var address: String
  public var captureCount: Int
  public var revision: Int
  public var captures: [CaptureGroup]
  public var photoCount: Int
  public var photoBytes: Int64
  public var controlCount: Int
  /// Files the manifest lists.
  public var manifestEntries: Int
  public var totalBytes: Int64

  /// "618 Valley Street · 2 floors · revision 1".
  public var subtitle: String {
    "\(address) \u{00B7} \(captureCount) \(captureCount == 1 ? "floor" : "floors") \u{00B7} revision \(revision)"
  }

  /// "42 · 188 MB".
  public var photosText: String { "\(photoCount) \u{00B7} \(ByteText.format(photoBytes))" }
  /// "18 controls".
  public var controlsText: String { "\(controlCount) \(controlCount == 1 ? "control" : "controls")" }
  /// "manifest · 75 entries".
  public var manifestText: String {
    "manifest \u{00B7} \(manifestEntries) \(manifestEntries == 1 ? "entry" : "entries")"
  }
  /// "Every file is fingerprinted (SHA-256). Sealing makes the package read-only; changes create
  /// revision 2."
  public var sealNote: String {
    "Every file is fingerprinted (SHA-256). Sealing makes the package read-only; changes create revision \(revision + 1)."
  }

  /// Summarises a draft. File sizes are read from the source files.
  public static func make(
    draft: PackageDraft, record: CaptureRecord, controls: FieldControls
  ) throws -> PackageReview {
    var sizes: [String: Int64] = [:]
    for entry in draft.entries {
      sizes[entry.path] = try size(of: entry.input.source)
    }
    let groups = record.captures.map { capture -> CaptureGroup in
      let entries = draft.entries.filter {
        $0.input.capture?.captureId == capture.captureId && $0.input.role != .photo
      }
      return CaptureGroup(
        label: capture.label, kinds: kinds(Set(entries.map(\.input.role))),
        fileCount: entries.count, bytes: entries.reduce(0) { $0 + (sizes[$1.path] ?? 0) })
    }
    let photos = draft.entries.filter { $0.input.role == .photo }
    return PackageReview(
      address: record.address.formatted, captureCount: record.captures.count,
      revision: draft.revision, captures: groups, photoCount: photos.count,
      photoBytes: photos.reduce(0) { $0 + (sizes[$1.path] ?? 0) },
      controlCount: controls.distances.count + controls.ceilingHeights.count
        + controls.openings.count + controls.floorToFloor.count + controls.landmarks.count,
      manifestEntries: draft.entries.count, totalBytes: sizes.values.reduce(0, +))
  }

  /// The design's order and wording of the file kinds of one capture.
  static func kinds(_ roles: Set<FileRole>) -> String {
    var parts: [String] = []
    if roles.contains(.planDXF) { parts.append("Plan DXF") }
    if roles.contains(.roomsCSV) { parts.append("Rooms CSV") }
    if roles.contains(.planPDF) { parts.append("Plan PDF") }
    if roles.contains(.spatialReportPDF) { parts.append("Spatial Report PDF") }
    switch (roles.contains(.planPNG), roles.contains(.planSVG)) {
    case (true, true): parts.append("Plan PNG and SVG")
    case (true, false): parts.append("Plan PNG")
    case (false, true): parts.append("Plan SVG")
    case (false, false): break
    }
    if roles.contains(.meshGLB) { parts.append("GLB") }
    if roles.contains(.meshOBJ) { parts.append(roles.contains(.meshMTL) ? "OBJ + MTL" : "OBJ") }
    if roles.contains(.pointCloudLAS) { parts.append("LAS") }
    switch (roles.contains(.rawRoomplanJSON), roles.contains(.rawDepth)) {
    case (true, true): parts.append("raw RoomPlan + depth")
    case (true, false): parts.append("raw RoomPlan")
    case (false, true): parts.append("raw depth")
    case (false, false): break
    }
    return parts.joined(separator: " \u{00B7} ")
  }

  private static func size(of url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }
}

/// What "Uploading" shows (design screen-package, 2).
public struct UploadProgressSummary: Equatable, Sendable {
  public enum Status: Equatable, Sendable {
    case verified
    case uploading
    case waiting

    /// "● Verified" (word and shape), "Uploading", "Waiting".
    public var text: String {
      switch self {
      case .verified: return "\u{25CF} Verified"
      case .uploading: return "Uploading"
      case .waiting: return "Waiting"
      }
    }
  }

  public enum Category: String, CaseIterable, Equatable, Sendable {
    case plansAndReports = "Plans and reports"
    case sitePhotos = "Site photos"
    case meshes = "Meshes"
    case pointClouds = "Point clouds"

    /// Which row a file is counted in. Capture record, field controls, capture model and the raw
    /// RoomPlan JSON count with the plans and reports; raw depth with the point clouds.
    public static func of(_ role: FileRole) -> Category {
      switch role {
      case .photo: return .sitePhotos
      case .meshGLB, .meshOBJ, .meshMTL, .texture: return .meshes
      case .pointCloudLAS, .rawDepth: return .pointClouds
      default: return .plansAndReports
      }
    }
  }

  public struct Row: Equatable, Sendable {
    public var category: Category
    public var status: Status
  }

  public var bytesDone: Int64
  public var bytesTotal: Int64
  public var rows: [Row]

  /// 0...1.
  public var fraction: Double {
    bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 0
  }

  /// "67%".
  public var percentText: String { "\(Int((fraction * 100).rounded(.down)))%" }
  /// "512 of 768 MB".
  public var bytesText: String { ByteText.progress(bytesDone, of: bytesTotal) }

  /// Bytes count as done when the station verified the file, or when the blob service confirmed
  /// them (staged blocks, uploaded files waiting for the station's check).
  public static func make(
    state: UploadState, manifest: PackageManifest, blockSize: Int = BlobBlocks.blockSize
  ) -> UploadProgressSummary {
    let roles = Dictionary(
      manifest.files.map { ($0.path, $0.role) }, uniquingKeysWith: { first, _ in first })
    var done: Int64 = 0
    var perCategory: [Category: [FileUploadState]] = [:]
    for file in state.files {
      switch file.phase {
      case .verified, .uploaded:
        done += file.bytes
      case .pending, .sending:
        done += min(file.bytes, Int64(file.stagedBlockIds.count) * Int64(blockSize))
      }
      let category = Category.of(roles[file.path] ?? .captureRecord)
      perCategory[category, default: []].append(file)
    }
    let rows = Category.allCases.compactMap { category -> Row? in
      guard let files = perCategory[category], !files.isEmpty else { return nil }
      if files.allSatisfy({ $0.phase == .verified }) {
        return Row(category: category, status: .verified)
      }
      let started = files.contains {
        $0.phase != .pending || !$0.stagedBlockIds.isEmpty || $0.lastCheck != nil
      }
      return Row(category: category, status: started ? .uploading : .waiting)
    }
    return UploadProgressSummary(
      bytesDone: done, bytesTotal: state.files.reduce(0) { $0 + $1.bytes }, rows: rows)
  }
}

/// The "Station" steps of the Uploading screen.
public struct StationSteps: Equatable, Sendable {
  public struct Step: Equatable, Sendable {
    public var title: String
    public var done: Bool
  }

  public var steps: [Step]

  /// - registered: the station sealed (registered) the package with every file verified.
  /// - stage: the package's status at the station, once known.
  ///
  /// "Published to the HUB" is never shown as done: the station API has no publication state
  /// the phone can read, so the app does not claim it.
  public static func make(registered: Bool, stage: StationPackageStage?) -> StationSteps {
    let queued: Bool
    switch stage {
    case .checksQueued, .checking, .verdictReady, .checkError: queued = registered
    case .uploading, .none: queued = false
    }
    return StationSteps(steps: [
      Step(title: "Registered", done: registered),
      Step(title: "Checks queued", done: queued),
      Step(title: "Verdict", done: registered && stage == .verdictReady),
      Step(title: "Published to the HUB", done: false),
    ])
  }
}
