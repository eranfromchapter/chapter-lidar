/// Every operation of contract/openapi/station.yaml, one case per `operationId`.
///
/// OpenAPIParityTests reads the OpenAPI document and fails when an operation, method, path or
/// security rule here differs from it, and when the client sends a request that matches none of
/// these operations.
public enum StationOperation: String, CaseIterable, Sendable {
  case getHealth
  case listProjects
  case getProject
  case createUploadSession
  case listPackages
  case getPackage
  case completeFile
  case getFileDownloadLink
  case sealPackage
  case getVerdict
  case listModelingDecisions
  case createModelingDecision
  case putNextRevisionNotice
  case createSketchInterpretation

  /// The document's server URL: the API base path relative to the station host.
  public static let serverBasePath = "/v1"

  /// The document's `operationId`.
  public var operationId: String { rawValue }

  /// HTTP method, uppercase.
  public var method: String {
    switch self {
    case .getHealth, .listProjects, .getProject, .listPackages, .getPackage,
      .getFileDownloadLink, .getVerdict, .listModelingDecisions:
      return "GET"
    case .createUploadSession, .completeFile, .sealPackage, .createModelingDecision,
      .createSketchInterpretation:
      return "POST"
    case .putNextRevisionNotice:
      return "PUT"
    }
  }

  /// Path template exactly as written in the document, relative to `serverBasePath`.
  public var pathTemplate: String {
    switch self {
    case .getHealth: return "/health"
    case .listProjects: return "/projects"
    case .getProject: return "/projects/{dealId}"
    case .createUploadSession, .listPackages: return "/packages"
    case .getPackage: return "/packages/{packageId}"
    case .completeFile: return "/packages/{packageId}/files/complete"
    case .getFileDownloadLink: return "/packages/{packageId}/files/download"
    case .sealPackage: return "/packages/{packageId}/seal"
    case .getVerdict: return "/packages/{packageId}/verdict"
    case .listModelingDecisions, .createModelingDecision:
      return "/packages/{packageId}/modeling-decisions"
    case .putNextRevisionNotice: return "/packages/{packageId}/next-revision"
    case .createSketchInterpretation: return "/sketch-interpretations"
    }
  }

  /// False only for `GET /health` (`security: []` in the document). Every other operation sends
  /// the Entra bearer token.
  public var requiresAuthorization: Bool {
    self != .getHealth
  }

  /// HTTP statuses the document lists as success for this operation.
  public var successStatuses: Set<Int> {
    switch self {
    case .createUploadSession: return [200, 201]
    case .sealPackage: return [200, 202]
    case .createModelingDecision: return [201]
    default: return [200]
    }
  }
}
