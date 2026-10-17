import Foundation

public enum RawOriginalsError: Error, Equatable, CustomStringConvertible {
  case truncated
  case badMagic(String)
  case unsupportedVersion(UInt32)
  case invalidIdentifier(String)
  case invalidMesh(String)
  case directoryNotEmpty(String)
  case emptyRoomPlanJSON

  public var description: String {
    switch self {
    case .truncated: return "The file is shorter than its header says."
    case .badMagic(let expected): return "The file does not start with \(expected)."
    case .unsupportedVersion(let version): return "Unsupported file format version \(version)."
    case .invalidIdentifier(let id): return "Mesh anchor identifier \(id) is not a UUID."
    case .invalidMesh(let id): return "Mesh anchor \(id) has inconsistent vertex or triangle data."
    case .directoryNotEmpty(let path): return "\(path) already holds originals; they are never overwritten."
    case .emptyRoomPlanJSON: return "There is no RoomPlan JSON to write."
    }
  }
}

/// Everything a scan keeps as originals. Never edited after the scan.
public struct RawOriginals: Sendable, Equatable {
  /// `CapturedRoom` or `CapturedStructure` JSON exactly as encoded by RoomPlan's Codable.
  public var roomPlanJSON: Data
  /// Depth points with confidence of medium or better (the session filters when sampling).
  public var depthSamples: [DepthSample]
  public var cameraPoses: CameraPoseLog
  /// Scene reconstruction mesh geometry. Empty for a replay without a mesh.
  public var meshAnchors: [RawMeshAnchor]

  public init(
    roomPlanJSON: Data, depthSamples: [DepthSample] = [], cameraPoses: CameraPoseLog = CameraPoseLog(),
    meshAnchors: [RawMeshAnchor] = []
  ) {
    self.roomPlanJSON = roomPlanJSON
    self.depthSamples = depthSamples
    self.cameraPoses = cameraPoses
    self.meshAnchors = meshAnchors
  }
}

/// File names of the raw originals in a folder.
public enum RawOriginalsNaming: Sendable, Equatable {
  /// The on-device originals folder. `roomplan.json` and `depth-samples.bin` are the names the
  /// intake package uses for the roles `raw_roomplan_json` and `raw_depth`.
  case originals
  /// The debug export, in the layout of fixtures/recorded/README.md: exactly three files.
  case debugExport

  public var roomPlanFileName: String {
    switch self {
    case .originals: return "roomplan.json"
    case .debugExport: return "raw-roomplan.json"
    }
  }

  public static let depthFileName = "depth-samples.bin"
  public static let cameraPosesFileName = "camera-poses.json"
  public static let meshAnchorsFileName = "mesh-anchors.bin"
}

public struct WrittenOriginal: Sendable, Equatable {
  public var fileName: String
  public var byteCount: Int
}

/// Writes raw originals. The RoomPlan JSON bytes are written exactly as given.
public enum RawOriginalsWriter {
  /// Writes into `directory` (created when missing). Refuses a folder that already holds any of
  /// the files, so an original is never overwritten. Each file is written atomically.
  @discardableResult
  public static func write(
    _ originals: RawOriginals, to directory: URL, naming: RawOriginalsNaming = .originals,
    fileManager: FileManager = .default
  ) throws -> [WrittenOriginal] {
    guard !originals.roomPlanJSON.isEmpty else { throw RawOriginalsError.emptyRoomPlanJSON }
    var files: [(name: String, data: Data)] = [
      (naming.roomPlanFileName, originals.roomPlanJSON),
      (RawOriginalsNaming.depthFileName, DepthSamplesCodec.encode(originals.depthSamples)),
      (RawOriginalsNaming.cameraPosesFileName, try originals.cameraPoses.encoded()),
    ]
    // The debug export is exactly the three README files; the mesh original stays on the phone.
    if naming == .originals, !originals.meshAnchors.isEmpty {
      files.append((RawOriginalsNaming.meshAnchorsFileName, try MeshAnchorsCodec.encode(originals.meshAnchors)))
    }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    for file in files
    where fileManager.fileExists(atPath: directory.appendingPathComponent(file.name).path) {
      throw RawOriginalsError.directoryNotEmpty(directory.path)
    }
    var written: [WrittenOriginal] = []
    for file in files {
      try file.data.write(to: directory.appendingPathComponent(file.name), options: .atomic)
      written.append(WrittenOriginal(fileName: file.name, byteCount: file.data.count))
    }
    return written
  }

  /// Reads a folder written by `write` (either naming) back into originals. Mesh anchors are
  /// read when `mesh-anchors.bin` is present.
  public static func read(from directory: URL, fileManager: FileManager = .default) throws
    -> RawOriginals
  {
    func load(_ name: String) throws -> Data? {
      let url = directory.appendingPathComponent(name)
      return fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }
    guard
      let roomPlan = try load(RawOriginalsNaming.originals.roomPlanFileName)
        ?? load(RawOriginalsNaming.debugExport.roomPlanFileName)
    else { throw RawOriginalsError.emptyRoomPlanJSON }
    let depth = try load(RawOriginalsNaming.depthFileName).map(DepthSamplesCodec.decode) ?? []
    let poses = try load(RawOriginalsNaming.cameraPosesFileName).map(CameraPoseLog.decode) ?? CameraPoseLog()
    let mesh = try load(RawOriginalsNaming.meshAnchorsFileName).map(MeshAnchorsCodec.decode) ?? []
    return RawOriginals(roomPlanJSON: roomPlan, depthSamples: depth, cameraPoses: poses, meshAnchors: mesh)
  }
}

/// The debug build's "Export raw originals": a new folder with exactly the three files of
/// fixtures/recorded/README.md (`raw-roomplan.json`, `depth-samples.bin`, `camera-poses.json`).
public enum DebugOriginalsExport {
  /// Writes the export into `parent/folderName` and returns the folder.
  public static func export(
    _ originals: RawOriginals, to parent: URL, folderName: String, fileManager: FileManager = .default
  ) throws -> URL {
    let folder = parent.appendingPathComponent(folderName, isDirectory: true)
    try RawOriginalsWriter.write(originals, to: folder, naming: .debugExport, fileManager: fileManager)
    return folder
  }
}
