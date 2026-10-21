import CaptureContract
import CaptureCore
import CaptureModelMapping
import FieldRules
import Foundation
import MeshExport
import PackageCore
import PlanExport

/// Why "Package ready" could not be built. The originals stay where they are.
public enum VisitPackageError: Error, Equatable, Sendable, CustomStringConvertible {
  case noCaptures
  /// A floor's RoomPlan original could not be read or turned into a capture model.
  case captureModel(label: String, reason: String)
  case planExport(label: String, reason: String)
  case meshExport(label: String, reason: String)
  case fieldControls(String)
  case writeFailed(String)

  public var description: String {
    switch self {
    case .noCaptures: return "Nothing has been captured yet."
    case .captureModel(let label, let reason):
      return "\(label) could not be turned into a plan: \(reason)"
    case .planExport(let label, let reason): return "The plans of \(label) could not be written: \(reason)"
    case .meshExport(let label, let reason): return "The 3D files of \(label) could not be written: \(reason)"
    case .fieldControls(let reason): return "The field controls could not be written: \(reason)"
    case .writeFailed(let reason): return "A package file could not be written: \(reason)"
    }
  }
}

/// Manifest generator names of the files the app writes.
public enum AppGenerators {
  public static let captureCore = "chapter-capture-ios/CaptureCore"
  public static let meshExport = "chapter-capture-ios/MeshExport"
  public static let fieldKit = "chapter-capture-ios/FieldKit"
}

/// One planned package: the draft (not yet sealed) and what the "Package ready" screen shows.
public struct VisitPackagePlan: Sendable {
  public let draft: PackageDraft
  public let record: CaptureRecord
  public let review: PackageReview
  /// Folder of this build's generated files (capture record, models, exports).
  public let draftFolder: URL
}

/// Builds the package draft of a visit from the files on the phone.
///
/// Per capture (in capture order): the raw originals `roomplan.json` and `depth-samples.bin`
/// exactly as the scan wrote them; `capture-model.json` mapped from `roomplan.json` with the
/// visit's ids; the PlanExport files (DXF, CSV, plan PDF, Spatial Report PDF, PNG, SVG) derived
/// from the capture model; and, when the scan recorded them, the MeshExport files (`mesh.glb`,
/// `mesh.obj` + `mesh.mtl` from the scene mesh, `points.las` derived from `depth-samples.bin`).
/// Visit-wide: `capture-record.json` and `field-controls.json`. Then every saved photo, with its
/// recorded SHA-256 and size as the expected fingerprint (assembly fails if a photo changed).
///
/// Generated files go into a new `drafts/<id>/` folder; originals are only read.
public struct VisitPackageBuilder: Sendable {
  public let workspace: VisitWorkspace
  /// App version, used as generatorVersion of the files CaptureCore and FieldKit wrote.
  public let appVersion: String
  public let now: @Sendable () -> Date

  public init(
    workspace: VisitWorkspace, appVersion: String, now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.workspace = workspace
    self.appVersion = appVersion
    self.now = now
  }

  /// Folder of the raw originals of one capture (as CaptureFlowModel writes them).
  public func originalsDirectory(of capture: CaptureRecord.Capture) -> URL {
    workspace.originalsRoot
      .appendingPathComponent(PackageFolder.originalExports.name, isDirectory: true)
      .appendingPathComponent(capture.areaKey, isDirectory: true)
      .appendingPathComponent(capture.captureId.rawValue, isDirectory: true)
  }

  /// The capture model of one capture, mapped from its RoomPlan original with the visit's ids
  /// and the operator's room `names` (`RoomNaming`).
  public func captureModel(
    of capture: CaptureRecord.Capture, visitId: LowercaseUUID, names: [RoomName] = []
  ) throws -> CaptureModel {
    try namedCaptureModel(of: capture, visitId: visitId, names: names).model
  }

  /// `captureModel(of:visitId:names:)` with the labels the scan gives its rooms without names.
  public func namedCaptureModel(
    of capture: CaptureRecord.Capture, visitId: LowercaseUUID, names: [RoomName]
  ) throws -> NamedCaptureModel {
    let directory = originalsDirectory(of: capture)
    let roomPlanURL = directory.appendingPathComponent(RawOriginalsNaming.originals.roomPlanFileName)
    do {
      let document = try RoomPlanDocument.decode(from: try Data(contentsOf: roomPlanURL))
      let base = try PackagePaths.folder(
        role: .rawRoomplanJSON, visitId: visitId,
        capture: CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey))
      return try RoomNaming.map(
        document,
        context: MappingContext(
          visitId: visitId, captureId: capture.captureId, areaKey: capture.areaKey,
          label: capture.label,
          refs: [
            CaptureModel.SourceRef(
              role: .rawRoomplanJSON, path: base + RawOriginalsNaming.originals.roomPlanFileName),
            CaptureModel.SourceRef(role: .rawDepth, path: base + RawOriginalsNaming.depthFileName),
          ]),
        names: names)
    } catch {
      throw VisitPackageError.captureModel(label: capture.label, reason: String(describing: error))
    }
  }

  /// Builds the draft. `photosRoot` is the root of the photo store (record paths are relative).
  /// Every capture model, and the plans and reports drawn from it, carries the operator's
  /// `roomNames`.
  public func plan(
    record: CaptureRecord, photos: [PhotoRecord], controls: FieldControls,
    roomNames: VisitRoomNames = VisitRoomNames(),
    draftId: UUID = UUID(), packageId: LowercaseUUID = LowercaseUUID()
  ) throws -> VisitPackagePlan {
    guard !record.captures.isEmpty else { throw VisitPackageError.noCaptures }
    let draftFolder = workspace.draftsRoot.appendingPathComponent(
      draftId.uuidString.lowercased(), isDirectory: true)
    var draft = PackageDraft(visitId: record.visitId, packageId: packageId)

    // Visit-wide documents.
    let recordURL = try write(
      try encode(record),
      to: draftFolder.appendingPathComponent(
        "\(PackageFolder.sourceRegister.name)/\(record.visitId.rawValue)/\(PackageLayout.captureRecordFileName)"
      ))
    try draft.add(
      PackageFileInput(
        source: recordURL, role: .captureRecord, fileName: PackageLayout.captureRecordFileName,
        mime: "application/json", generator: AppGenerators.captureCore,
        generatorVersion: appVersion))

    let controlsURL: URL
    do {
      controlsURL = try FieldControlsFile.write(
        controls, intoPackageRoot: workspace.controlsRoot,
        knownCaptures: record.captures.map {
          FieldControls.CaptureRef(captureId: $0.captureId, areaKey: $0.areaKey)
        })
    } catch {
      throw VisitPackageError.fieldControls(String(describing: error))
    }
    try draft.add(
      PackageFileInput(
        source: controlsURL, role: .fieldControls, fileName: FieldControlsFile.fileName,
        mime: "application/json", generator: AppGenerators.fieldKit, generatorVersion: appVersion))

    // Per capture.
    for capture in record.captures {
      try addCapture(
        capture, record: record, names: roomNames.names(for: capture.captureId),
        draftFolder: draftFolder, to: &draft)
    }

    // Photos, with the fingerprint recorded when each was saved.
    let captureIds = Set(record.captures.map(\.captureId))
    for photo in photos where captureIds.contains(photo.captureId) {
      try draft.add(
        PackageFileInput(
          source: url(under: workspace.photosRoot, path: photo.path), role: .photo,
          fileName: String(photo.path.split(separator: "/").last ?? ""),
          capture: CaptureRef(captureId: photo.captureId, areaKey: photo.areaKey), mime: photo.mime,
          generator: AppGenerators.fieldKit, generatorVersion: appVersion, photo: photo.labels,
          expected: FileDigest(sha256: photo.sha256, bytes: photo.bytes)))
    }

    let review = try PackageReview.make(draft: draft, record: record, controls: controls)
    return VisitPackagePlan(draft: draft, record: record, review: review, draftFolder: draftFolder)
  }

  private func addCapture(
    _ capture: CaptureRecord.Capture, record: CaptureRecord, names: [RoomName], draftFolder: URL,
    to draft: inout PackageDraft
  ) throws {
    let ref = CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey)
    let originals = originalsDirectory(of: capture)
    let exports = draftFolder.appendingPathComponent(
      "\(PackageFolder.originalExports.name)/\(capture.areaKey)/\(capture.captureId.rawValue)",
      isDirectory: true)

    let roomPlanPath = try draft.add(
      PackageFileInput(
        source: originals.appendingPathComponent(RawOriginalsNaming.originals.roomPlanFileName),
        role: .rawRoomplanJSON, fileName: RawOriginalsNaming.originals.roomPlanFileName,
        capture: ref, mime: "application/json", generator: AppGenerators.captureCore,
        generatorVersion: appVersion))
    let depthURL = originals.appendingPathComponent(RawOriginalsNaming.depthFileName)
    let depthPath = try draft.add(
      PackageFileInput(
        source: depthURL, role: .rawDepth, fileName: RawOriginalsNaming.depthFileName,
        capture: ref, mime: "application/octet-stream", generator: AppGenerators.captureCore,
        generatorVersion: appVersion))

    let model = try captureModel(of: capture, visitId: record.visitId, names: names)
    let modelURL = try write(
      try encode(model), to: exports.appendingPathComponent(PackageLayout.captureModelFileName))
    let modelPath = try draft.add(
      PackageFileInput(
        source: modelURL, role: .captureModel, fileName: PackageLayout.captureModelFileName,
        capture: ref, mime: "application/json", generator: AppGenerators.captureCore,
        generatorVersion: appVersion, derivedFrom: [roomPlanPath]))

    let planFiles: [ExportedFile]
    do {
      planFiles = try PlanExporter.exportAll(model: model, record: record)
    } catch {
      throw VisitPackageError.planExport(label: capture.label, reason: String(describing: error))
    }
    for file in planFiles {
      let fileURL = try write(file.data, to: exports.appendingPathComponent(file.fileName))
      try draft.add(
        PackageFileInput(
          source: fileURL, role: file.role, fileName: file.fileName, capture: ref, mime: file.mime,
          generator: file.generator, generatorVersion: file.generatorVersion,
          derivedFrom: [modelPath]))
    }

    try addMeshExports(
      capture, ref: ref, originals: originals, depthURL: depthURL, depthPath: depthPath,
      exports: exports, to: &draft)
  }

  /// GLB, OBJ + MTL from the recorded scene mesh (when there is one) and LAS from the depth
  /// samples (when there are any). The meshes are the phone's own mesh export (their source,
  /// `mesh-anchors.bin`, has no manifest role and stays on the phone), so they list no
  /// `derivedFrom`; the LAS is derived from `depth-samples.bin`.
  private func addMeshExports(
    _ capture: CaptureRecord.Capture, ref: CaptureRef, originals: URL, depthURL: URL,
    depthPath: String, exports: URL, to draft: inout PackageDraft
  ) throws {
    let anchors: [RawMeshAnchor]
    let samples: [MeshExport.DepthSample]
    do {
      anchors = try RawOriginalsWriter.read(from: originals).meshAnchors
      samples = try DepthSampleFile.read(contentsOf: depthURL)
    } catch {
      throw VisitPackageError.meshExport(label: capture.label, reason: String(describing: error))
    }
    let created = capture.finishedAt?.date ?? capture.capturedAt.date
    let version = ExportInfo.version
    let meshDirectory = exports
    var written: [(url: URL, role: FileRole, mime: String, derived: [String])] = []
    do {
      if let mesh = Self.mesh(from: anchors) {
        let report = try CaptureExporter.export(
          floors: [FloorMesh(areaKey: capture.areaKey, label: capture.label, mesh: mesh)],
          depthSamples: samples.isEmpty ? nil : samples, to: meshDirectory,
          options: ExportOptions(generatorVersion: version, creationDate: created))
        written.append((report.glbURL, .meshGLB, "model/gltf-binary", []))
        written.append((report.objURL, .meshOBJ, "model/obj", []))
        written.append((report.mtlURL, .meshMTL, "model/mtl", []))
        if let las = report.lasURL {
          written.append((las, .pointCloudLAS, "application/vnd.las", [depthPath]))
        }
      } else if !samples.isEmpty {
        try FileManager.default.createDirectory(at: meshDirectory, withIntermediateDirectories: true)
        let thinned = try PointThinning.thin(samples)
        let url = meshDirectory.appendingPathComponent("points.las")
        _ = try LASWriter.write(
          points: thinned.points, to: url,
          options: LASOptions(generatorVersion: version, creationDate: created))
        written.append((url, .pointCloudLAS, "application/vnd.las", [depthPath]))
      }
    } catch {
      throw VisitPackageError.meshExport(label: capture.label, reason: String(describing: error))
    }
    for file in written {
      try draft.add(
        PackageFileInput(
          source: file.url, role: file.role, fileName: file.url.lastPathComponent, capture: ref,
          mime: file.mime, generator: AppGenerators.meshExport, generatorVersion: version,
          derivedFrom: file.derived))
    }
  }

  /// One triangle mesh in the capture frame from the recorded mesh anchors (each anchor's
  /// transform applied). Nil when no anchor has a triangle.
  public static func mesh(from anchors: [RawMeshAnchor]) -> TriangleMesh? {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    for anchor in anchors where !anchor.triangles.isEmpty {
      let columns = anchor.transform.columns
      let base = UInt32(positions.count)
      var index = 0
      while index + 2 < anchor.vertices.count {
        let x = Double(anchor.vertices[index])
        let y = Double(anchor.vertices[index + 1])
        let z = Double(anchor.vertices[index + 2])
        var point = SIMD3<Float>(repeating: 0)
        for axis in 0..<3 {
          let value =
            columns[0][axis] * x + columns[1][axis] * y + columns[2][axis] * z + columns[3][axis]
          point[axis] = Float(value)
        }
        positions.append(point)
        index += 3
      }
      indices.append(contentsOf: anchor.triangles.map { $0 + base })
    }
    guard !indices.isEmpty else { return nil }
    return TriangleMesh(positions: positions, indices: indices)
  }

  // MARK: Files

  private func encode<T: Encodable>(_ value: T) throws -> Data {
    do {
      return try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(value)
    } catch {
      throw VisitPackageError.writeFailed(String(describing: error))
    }
  }

  /// Writes a generated file into the draft folder; never over an existing file.
  private func write(_ data: Data, to url: URL) throws -> URL {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .withoutOverwriting)
      return url
    } catch {
      throw VisitPackageError.writeFailed("\(url.lastPathComponent): \(error.localizedDescription)")
    }
  }

  private func url(under root: URL, path: String) -> URL {
    var url = root
    for segment in path.split(separator: "/") {
      url.appendPathComponent(String(segment))
    }
    return url
  }
}
