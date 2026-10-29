import CaptureContract
import CaptureCore
import CaptureModelMapping
import FieldRules
import Foundation
import MeshExport
import PackageCore
import PlanExport
import SketchMesh
import SketchSolver

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
  /// The originals of a sketch capture (spec F14): the sketch image and the measurements.
  public static let sketchCapture = "chapter-capture-ios/SketchCapture"
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
/// visit's ids; the PlanExport files (DXF, CSV, the plan sheet PDF, PNG, SVG) derived from the
/// capture model; and, when the scan recorded them, the MeshExport files (`mesh.glb`, `mesh.obj` +
/// `mesh.mtl` from the scene mesh, `points.las` derived from `depth-samples.bin`). A sketch
/// capture (spec F14, `captureSource == .sketch`) has the sketch image and
/// `sketch-measurements.json` as its originals, its model solved from the measurements with
/// both in `derivedFrom`, the same plan files, and the mesh extruded from the model (no point
/// cloud). Visit-wide: `capture-record.json` and `field-controls.json`. Then every saved photo,
/// with its recorded SHA-256 and size as the expected fingerprint (assembly fails if a photo
/// changed).
///
/// No Spatial Report PDF: the spatial report is made by the station after its checks, and a
/// manifest 1.1.0 package never holds the retired role (a PlanExport that still writes the phone
/// report has it left out here).
///
/// Generated files go into a new `drafts/<id>/` folder; originals are only read. A later
/// revision is built by `revisionPlan(base:…)` (RevisionBuilder.swift).
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

  /// The sketch measurements of a sketch capture, read from its originals folder.
  public func sketchMeasurements(of capture: CaptureRecord.Capture) throws -> SketchMeasurements {
    let url = originalsDirectory(of: capture)
      .appendingPathComponent(PackageLayout.sketchMeasurementsFileName)
    return try CaptureContractJSON.makeDecoder().decode(
      SketchMeasurements.self, from: try Data(contentsOf: url))
  }

  /// The capture model of one capture, mapped from its RoomPlan original with the visit's ids
  /// and the operator's room `names` (`RoomNaming`); a sketch capture's is solved again from
  /// its measurements.
  public func captureModel(
    of capture: CaptureRecord.Capture, visitId: LowercaseUUID, names: [RoomName] = []
  ) throws -> CaptureModel {
    try namedCaptureModel(of: capture, visitId: visitId, names: names).model
  }

  /// `captureModel(of:visitId:names:)` with the labels the scan gives its rooms without names.
  public func namedCaptureModel(
    of capture: CaptureRecord.Capture, visitId: LowercaseUUID, names: [RoomName]
  ) throws -> NamedCaptureModel {
    if capture.source == .sketch {
      return try namedSketchModel(of: capture, names: names)
    }
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

  /// A sketch capture's model, solved from `sketch-measurements.json` (spec F14 2.1). The
  /// operator's room names are the solver's labels already; a later rename (`VisitRoomNames`)
  /// applies by room id and footprint as it does to a scan, so the rooms are relabelled here
  /// without mapping anything.
  func namedSketchModel(of capture: CaptureRecord.Capture, names: [RoomName]) throws
    -> NamedCaptureModel
  {
    let solved: CaptureModel
    do {
      let measurements = try sketchMeasurements(of: capture)
      solved = try SketchSolver.solve(measurements, context: SketchSolveContext(label: capture.label))
        .model
    } catch {
      throw VisitPackageError.captureModel(label: capture.label, reason: String(describing: error))
    }
    let scanned = RoomNaming.scannedRooms(of: solved)
    var model = solved
    for (index, room) in scanned.enumerated() {
      guard let name = names.first(where: { RoomNaming.applies($0, to: room) }) else { continue }
      model.rooms[index].label = name.name
    }
    return NamedCaptureModel(model: model, scannedRooms: scanned)
  }

  /// Builds the draft. `photosRoot` is the root of the photo store (record paths are relative).
  /// Every capture model, and the plans and reports drawn from it, carries the operator's
  /// `roomNames`.
  public func plan(
    record: CaptureRecord, photos: [PhotoRecord], controls: FieldControls,
    roomNames: VisitRoomNames = VisitRoomNames(),
    draftId: UUID = UUID(), packageId: LowercaseUUID = LowercaseUUID()
  ) throws -> VisitPackagePlan {
    try build(
      PackageDraft(visitId: record.visitId, packageId: packageId), record: record, photos: photos,
      controls: controls, roomNames: roomNames, draftId: draftId)
  }

  /// Every file of the visit into `start` (a draft with no files yet).
  func build(
    _ start: PackageDraft, record: CaptureRecord, photos: [PhotoRecord], controls: FieldControls,
    roomNames: VisitRoomNames, draftId: UUID
  ) throws -> VisitPackagePlan {
    guard !record.captures.isEmpty else { throw VisitPackageError.noCaptures }
    let draftFolder = self.draftFolder(draftId)
    var draft = start

    // Visit-wide documents.
    try draft.add(try recordInput(record, draftFolder: draftFolder))
    try draft.add(try controlsInput(controls, record: record))

    // Per capture.
    for capture in record.captures {
      try addCapture(
        capture, record: record, names: roomNames.names(for: capture.captureId),
        draftFolder: draftFolder, to: &draft)
    }

    // Photos, with the fingerprint recorded when each was saved.
    let captureIds = Set(record.captures.map(\.captureId))
    for photo in photos where captureIds.contains(photo.captureId) {
      try draft.add(photoInput(photo))
    }

    let review = try PackageReview.make(draft: draft, record: record, controls: controls)
    return VisitPackagePlan(draft: draft, record: record, review: review, draftFolder: draftFolder)
  }

  /// A new `drafts/<id>/` folder for one build's generated files.
  func draftFolder(_ draftId: UUID) -> URL {
    workspace.draftsRoot.appendingPathComponent(draftId.uuidString.lowercased(), isDirectory: true)
  }

  /// `capture-record.json`, written into the draft folder.
  func recordInput(_ record: CaptureRecord, draftFolder: URL) throws -> PackageFileInput {
    let recordURL = try write(
      try encode(record),
      to: draftFolder.appendingPathComponent(
        "\(PackageFolder.sourceRegister.name)/\(record.visitId.rawValue)/\(PackageLayout.captureRecordFileName)"
      ))
    return PackageFileInput(
      source: recordURL, role: .captureRecord, fileName: PackageLayout.captureRecordFileName,
      mime: "application/json", generator: AppGenerators.captureCore, generatorVersion: appVersion)
  }

  /// `field-controls.json`, written into the visit's controls folder (FieldControlsFile).
  func controlsInput(_ controls: FieldControls, record: CaptureRecord) throws -> PackageFileInput {
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
    return PackageFileInput(
      source: controlsURL, role: .fieldControls, fileName: FieldControlsFile.fileName,
      mime: "application/json", generator: AppGenerators.fieldKit, generatorVersion: appVersion)
  }

  /// A saved photo with its labels and the fingerprint recorded when it was saved (assembly fails
  /// if the photo changed since).
  func photoInput(_ photo: PhotoRecord) -> PackageFileInput {
    PackageFileInput(
      source: url(under: workspace.photosRoot, path: photo.path), role: .photo,
      fileName: String(photo.path.split(separator: "/").last ?? ""),
      capture: CaptureRef(captureId: photo.captureId, areaKey: photo.areaKey), mime: photo.mime,
      generator: AppGenerators.fieldKit, generatorVersion: appVersion, photo: photo.labels,
      expected: FileDigest(sha256: photo.sha256, bytes: photo.bytes))
  }

  func addCapture(
    _ capture: CaptureRecord.Capture, record: CaptureRecord, names: [RoomName], draftFolder: URL,
    to draft: inout PackageDraft
  ) throws {
    if capture.source == .sketch {
      try addSketchCapture(capture, record: record, names: names, draftFolder: draftFolder, to: &draft)
      return
    }
    let ref = CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey)
    let originals = originalsDirectory(of: capture)
    let exports = exportsFolder(of: capture, in: draftFolder)

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
    let modelPath = try draft.add(
      try modelInput(model, capture: capture, exports: exports, derivedFrom: [roomPlanPath]))
    for input in try planInputs(
      model, capture: capture, record: record, exports: exports, modelPath: modelPath)
    {
      try draft.add(input)
    }

    try addMeshExports(
      capture, ref: ref, originals: originals, depthURL: depthURL, depthPath: depthPath,
      exports: exports, to: &draft)
  }

  /// A sketch capture (spec F14 2.1): the sketch image (when there is one) and the measurements
  /// as originals, the model solved from the measurements (`derivedFrom` both), the plan files,
  /// and `mesh.glb`, `mesh.obj` + `mesh.mtl` extruded from the model. No point cloud.
  func addSketchCapture(
    _ capture: CaptureRecord.Capture, record: CaptureRecord, names: [RoomName], draftFolder: URL,
    to draft: inout PackageDraft
  ) throws {
    let ref = CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey)
    let originals = originalsDirectory(of: capture)
    let exports = exportsFolder(of: capture, in: draftFolder)

    var originalPaths: [String] = []
    if let image = Self.sketchImage(in: originals) {
      originalPaths.append(
        try draft.add(
          PackageFileInput(
            source: image.url, role: .sketchImage, fileName: image.url.lastPathComponent,
            capture: ref, mime: image.mime, generator: AppGenerators.sketchCapture,
            generatorVersion: appVersion)))
    }
    originalPaths.append(
      try draft.add(
        PackageFileInput(
          source: originals.appendingPathComponent(PackageLayout.sketchMeasurementsFileName),
          role: .sketchMeasurements, fileName: PackageLayout.sketchMeasurementsFileName,
          capture: ref, mime: "application/json", generator: AppGenerators.sketchCapture,
          generatorVersion: appVersion)))

    let model = try captureModel(of: capture, visitId: record.visitId, names: names)
    let modelPath = try draft.add(
      try modelInput(model, capture: capture, exports: exports, derivedFrom: originalPaths))
    for input in try planInputs(
      model, capture: capture, record: record, exports: exports, modelPath: modelPath)
    {
      try draft.add(input)
    }

    let created = capture.finishedAt?.date ?? capture.capturedAt.date
    let version = ExportInfo.version
    let report: ExportReport
    do {
      let mesh = try SketchMesh.extrude(model)
      report = try CaptureExporter.export(
        floors: [FloorMesh(areaKey: capture.areaKey, label: capture.label, mesh: mesh)],
        depthSamples: nil, to: exports,
        options: ExportOptions(generatorVersion: version, creationDate: created))
    } catch {
      throw VisitPackageError.meshExport(label: capture.label, reason: String(describing: error))
    }
    for (url, role, mime) in [
      (report.glbURL, FileRole.meshGLB, "model/gltf-binary"), (report.objURL, .meshOBJ, "model/obj"),
      (report.mtlURL, .meshMTL, "model/mtl"),
    ] {
      try draft.add(
        PackageFileInput(
          source: url, role: role, fileName: url.lastPathComponent, capture: ref, mime: mime,
          generator: AppGenerators.meshExport, generatorVersion: version, derivedFrom: [modelPath]))
    }
  }

  /// The sketch image of a sketch capture's originals folder: `sketch.jpg`, `.png`, `.heic` or
  /// `.pdf`, whichever exists (one per capture); nil for a capture without a sketch.
  static func sketchImage(in originals: URL) -> (url: URL, mime: String)? {
    let kinds = [
      ("jpg", "image/jpeg"), ("png", "image/png"), ("heic", "image/heic"), ("pdf", "application/pdf"),
    ]
    for (ext, mime) in kinds {
      let url = originals.appendingPathComponent("sketch.\(ext)")
      if FileManager.default.fileExists(atPath: url.path) { return (url, mime) }
    }
    return nil
  }

  /// The package paths of a capture's originals as the draft holds them: the raw RoomPlan file
  /// of a scan; the sketch image (when listed) and the measurements of a sketch capture.
  func originalPaths(of capture: CaptureRecord.Capture, in draft: PackageDraft) throws -> [String] {
    let ref = CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey)
    guard capture.source == .sketch else {
      return [
        try draft.path(
          role: .rawRoomplanJSON, fileName: RawOriginalsNaming.originals.roomPlanFileName,
          capture: ref)
      ]
    }
    return draft.entries
      .filter { $0.input.capture == ref && $0.input.role.isSketchRole }
      .sorted { $0.input.role == .sketchImage && $1.input.role != .sketchImage }
      .map(\.path)
  }

  /// Folder of one capture's generated files in a draft folder.
  func exportsFolder(of capture: CaptureRecord.Capture, in draftFolder: URL) -> URL {
    draftFolder.appendingPathComponent(
      "\(PackageFolder.originalExports.name)/\(capture.areaKey)/\(capture.captureId.rawValue)",
      isDirectory: true)
  }

  /// `capture-model.json` of one capture, written into `exports`; `derivedFrom` lists the
  /// originals it was mapped or solved from.
  func modelInput(
    _ model: CaptureModel, capture: CaptureRecord.Capture, exports: URL, derivedFrom: [String]
  ) throws -> PackageFileInput {
    let modelURL = try write(
      try encode(model), to: exports.appendingPathComponent(PackageLayout.captureModelFileName))
    return PackageFileInput(
      source: modelURL, role: .captureModel, fileName: PackageLayout.captureModelFileName,
      capture: CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey),
      mime: "application/json", generator: AppGenerators.captureCore,
      generatorVersion: appVersion, derivedFrom: derivedFrom)
  }

  /// The PlanExport files of one capture model, written into `exports`. The retired phone report
  /// is left out, whatever PlanExport writes.
  func planInputs(
    _ model: CaptureModel, capture: CaptureRecord.Capture, record: CaptureRecord, exports: URL,
    modelPath: String
  ) throws -> [PackageFileInput] {
    let planFiles: [ExportedFile]
    do {
      planFiles = try PlanExporter.exportAll(model: model, record: record)
    } catch {
      throw VisitPackageError.planExport(label: capture.label, reason: String(describing: error))
    }
    return try planFiles.filter { !$0.role.isRetired }.map { file in
      let fileURL = try write(file.data, to: exports.appendingPathComponent(file.fileName))
      return PackageFileInput(
        source: fileURL, role: file.role, fileName: file.fileName,
        capture: CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey),
        mime: file.mime, generator: file.generator, generatorVersion: file.generatorVersion,
        derivedFrom: [modelPath])
    }
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

  func encode<T: Encodable>(_ value: T) throws -> Data {
    do {
      return try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(value)
    } catch {
      throw VisitPackageError.writeFailed(String(describing: error))
    }
  }

  /// Writes a generated file into the draft folder; never over an existing file.
  func write(_ data: Data, to url: URL) throws -> URL {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .withoutOverwriting)
      return url
    } catch {
      throw VisitPackageError.writeFailed("\(url.lastPathComponent): \(error.localizedDescription)")
    }
  }

  func url(under root: URL, path: String) -> URL {
    var url = root
    for segment in path.split(separator: "/") {
      url.appendPathComponent(String(segment))
    }
    return url
  }
}
