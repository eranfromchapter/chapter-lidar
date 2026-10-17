import Foundation

public struct ExportOptions: Sendable {
  /// Mesh face budget per floor (default 1.5 million).
  public var faceBudget: Int
  public var thinning: ThinningOptions
  public var generatorVersion: String
  public var creationDate: Date
  /// Base name of the files: `mesh.glb`, `mesh.obj`, `mesh.mtl`.
  public var meshBaseName: String
  public var lasFileName: String

  public init(
    faceBudget: Int = MeshDecimator.defaultFaceBudget,
    thinning: ThinningOptions = ThinningOptions(),
    generatorVersion: String = ExportInfo.version,
    creationDate: Date = Date(),
    meshBaseName: String = "mesh",
    lasFileName: String = "points.las"
  ) {
    self.faceBudget = faceBudget
    self.thinning = thinning
    self.generatorVersion = generatorVersion
    self.creationDate = creationDate
    self.meshBaseName = meshBaseName
    self.lasFileName = lasFileName
  }
}

public struct ExportReport: Sendable {
  public var glbURL: URL
  public var objURL: URL
  public var mtlURL: URL
  /// Nil when no depth samples were given.
  public var lasURL: URL?
  public var decimation: [DecimationResult]
  public var thinning: ThinningResult?
  public var las: LASSummary?
}

/// Writes the 3D files of one capture (or several floors) into a folder:
/// `mesh.glb`, `mesh.obj` + `mesh.mtl`, and `points.las` when depth samples are given.
/// Meshes above the face budget are decimated first; depth samples are voxel-thinned first.
public enum CaptureExporter {
  public static func export(
    floors: [FloorMesh], depthSamples: [DepthSample]? = nil, to directory: URL,
    options: ExportOptions = ExportOptions()
  ) throws -> ExportReport {
    guard !floors.isEmpty else { throw MeshExportError.emptyMesh }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var decimations: [DecimationResult] = []
    var prepared: [FloorMesh] = []
    for floor in floors {
      let result = try MeshDecimator.decimate(floor.mesh, faceBudget: options.faceBudget)
      decimations.append(result)
      prepared.append(FloorMesh(areaKey: floor.areaKey, label: floor.label, mesh: result.mesh))
    }

    let glbURL = directory.appendingPathComponent("\(options.meshBaseName).glb")
    try GLBWriter.write(floors: prepared, to: glbURL, generatorVersion: options.generatorVersion)
    let package = try OBJWriter.write(
      floors: prepared, to: directory, baseName: options.meshBaseName,
      generatorVersion: options.generatorVersion)

    var lasURL: URL?
    var thinned: ThinningResult?
    var lasSummary: LASSummary?
    if let depthSamples, !depthSamples.isEmpty {
      let result = try PointThinning.thin(depthSamples, options: options.thinning)
      let url = directory.appendingPathComponent(options.lasFileName)
      lasSummary = try LASWriter.write(
        points: result.points, to: url,
        options: LASOptions(
          generatorVersion: options.generatorVersion, creationDate: options.creationDate))
      thinned = result
      lasURL = url
    }
    return ExportReport(
      glbURL: glbURL, objURL: package.objURL, mtlURL: package.mtlURL, lasURL: lasURL,
      decimation: decimations, thinning: thinned, las: lasSummary)
  }
}
