// File roles and package folder layout from contract/schema/manifest.schema.json and
// contract/schema/layout.json. One package is one site visit; each floor or area scan in it is a
// separate capture. SchemaParityTests checks every value here against those files.

/// Closed set of manifest file roles from the intake guide, plus `capture_model`.
public enum FileRole: String, CaseIterable, Codable, Sendable {
  case captureRecord = "capture_record"
  case rawRoomplanJSON = "raw_roomplan_json"
  case rawDepth = "raw_depth"
  case captureModel = "capture_model"
  case planDXF = "plan_dxf"
  case roomsCSV = "rooms_csv"
  case planPDF = "plan_pdf"
  case spatialReportPDF = "spatial_report_pdf"
  case planPNG = "plan_png"
  case planSVG = "plan_svg"
  case meshGLB = "mesh_glb"
  case meshOBJ = "mesh_obj"
  case meshMTL = "mesh_mtl"
  case texture
  case pointCloudLAS = "point_cloud_las"
  case photo
  case fieldControls = "field_controls"

  /// Roles of visit-wide files. Their manifest entries carry no `captureId` or `areaKey`;
  /// entries of every other role carry both.
  public static let visitRoles: [FileRole] = [.captureRecord, .fieldControls]

  public var isVisitWide: Bool {
    FileRole.visitRoles.contains(self)
  }

  /// The one folder files of this role are stored in.
  public var folder: PackageFolder {
    PackageFolder.allCases.first { $0.roles.contains(self) }!
  }
}

/// Whether a folder groups files per capture or per visit.
public enum FolderScope: String, CaseIterable, Codable, Sendable {
  case capture
  case visit
}

/// Who writes into a folder. The capture app never writes `downstream` folders.
public enum FolderProducer: String, CaseIterable, Codable, Sendable {
  case captureApp = "capture_app"
  case downstream
}

/// Path template placeholders a folder groups by.
public enum FolderGroupKey: String, CaseIterable, Codable, Sendable {
  case areaKey
  case captureId
  case visitId
}

/// Top-level folders of an intake package, in the order of layout.json.
public enum PackageFolder: String, CaseIterable, Codable, Sendable {
  case originalExports = "original_exports"
  case sitePhotos = "site_photos"
  case fieldMeasurements = "field_measurements"
  case sourceRegister = "source_register"
  case workingConversions = "working_conversions"
  case issuedOutputs = "issued_outputs"

  /// Folder name as it appears in package paths.
  public var name: String {
    switch self {
    case .originalExports: return "Original Exports"
    case .sitePhotos: return "Site Photos"
    case .fieldMeasurements: return "Field Measurements"
    case .sourceRegister: return "Source Register"
    case .workingConversions: return "Working Conversions"
    case .issuedOutputs: return "Issued Outputs"
    }
  }

  public var scope: FolderScope {
    switch self {
    case .fieldMeasurements, .sourceRegister: return .visit
    case .originalExports, .sitePhotos, .workingConversions, .issuedOutputs: return .capture
    }
  }

  /// Placeholders in `pathTemplate`, outermost first.
  public var groupBy: [FolderGroupKey] {
    switch scope {
    case .visit: return [.visitId]
    case .capture: return [.areaKey, .captureId]
    }
  }

  /// Folder for a file of this folder's roles, with `{areaKey}`, `{captureId}` or `{visitId}`
  /// placeholders. The file name (which may contain subfolders, for mesh companions) follows it.
  public var pathTemplate: String {
    switch scope {
    case .visit: return "\(name)/{visitId}/"
    case .capture: return "\(name)/{areaKey}/{captureId}/"
    }
  }

  public var producedBy: FolderProducer {
    switch self {
    case .originalExports, .sitePhotos, .fieldMeasurements, .sourceRegister: return .captureApp
    case .workingConversions, .issuedOutputs: return .downstream
    }
  }

  /// Manifest roles stored in this folder. Each role belongs to exactly one folder.
  public var roles: [FileRole] {
    switch self {
    case .originalExports:
      return [
        .rawRoomplanJSON, .rawDepth, .captureModel, .planDXF, .roomsCSV, .planPDF,
        .spatialReportPDF, .planPNG, .planSVG, .meshGLB, .meshOBJ, .meshMTL, .texture,
        .pointCloudLAS,
      ]
    case .sitePhotos: return [.photo]
    case .fieldMeasurements: return [.fieldControls]
    case .sourceRegister: return [.captureRecord]
    case .workingConversions, .issuedOutputs: return []
    }
  }
}

/// Fixed layout constants from layout.json.
public enum PackageLayout {
  /// `layoutVersion` of layout.json these constants follow.
  public static let version = LayoutVersion.current.rawValue

  /// Where the manifest is written. The manifest does not list itself.
  public static let manifestPathTemplate = "Source Register/{visitId}/manifest.json"

  /// File name of the capture record in its folder.
  public static let captureRecordFileName = "capture-record.json"
  /// File name of a capture model in its capture's folder.
  public static let captureModelFileName = "capture-model.json"
  /// File name of the field controls in their folder.
  public static let fieldControlsFileName = "field-controls.json"
  /// File name of the manifest in its folder.
  public static let manifestFileName = "manifest.json"
}
