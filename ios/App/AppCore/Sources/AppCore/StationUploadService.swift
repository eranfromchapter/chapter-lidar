// The bridge between StationClient and PackageKit: StationClient satisfies PackageKit's
// `PackageUploadService`. Imports only PackageCore; StationClient types are reached through the
// aliases in StationAliases.swift (both packages use the same type names).
import CaptureContract
import Foundation
import PackageCore

/// `PackageUploadService` over StationClient.
///
/// - Models are converted field by field (both packages mirror the same OpenAPI schemas). A value
///   that has no counterpart (an unknown status) fails with `StationBridgeError.unexpectedValue`;
///   nothing is guessed.
/// - HTTP errors become PackageKit's `StationProblem` with the station's status and problem code,
///   so the uploader can act on `upload_target_changed` and `package_sealed`. A 4xx/5xx without a
///   problem body gets the code `http_<status>`.
/// - Offline, transport and token-provider errors are passed through unchanged: the uploader treats
///   any error that is not a `StationProblem` as transient and keeps its saved state.
/// - The seal body is the manifest bytes exactly as given (StationClient sends them unchanged).
public struct StationUploadService: PackageUploadService {
  public let client: StationAPI

  public init(client: StationAPI) {
    self.client = client
  }

  public func openSession(_ request: UploadSessionRequest) async throws -> UploadSession {
    do {
      let session = try await client.createUploadSession(StationBridge.convert(request))
      return try StationBridge.convert(session)
    } catch {
      throw StationBridge.map(error)
    }
  }

  public func completeFile(packageId: UUID, path: String) async throws -> FileCheckResult {
    do {
      return try StationBridge.convert(
        try await client.completeFile(packageId: packageId, path: path))
    } catch {
      throw StationBridge.map(error)
    }
  }

  public func seal(packageId: UUID, manifestJSON: Data) async throws -> PackageSealResult {
    do {
      return try StationBridge.convert(
        try await client.sealPackage(packageId: packageId, manifestJSON: manifestJSON))
    } catch {
      throw StationBridge.map(error)
    }
  }
}

/// A station answer that has no counterpart in PackageKit's model.
public struct StationBridgeError: Error, Equatable, Sendable, CustomStringConvertible {
  public let field: String
  public let value: String

  public var description: String { "unexpected \(field) '\(value)' from the station" }
}

/// Model and error conversion between StationClient and PackageKit.
public enum StationBridge {
  // MARK: Errors

  /// StationClient errors with an HTTP status become `StationProblem`; everything else is
  /// returned unchanged.
  public static func map(_ error: Error) -> Error {
    guard let stationError = error as? StationAPIError else { return error }
    let status: Int
    switch stationError {
    case .unauthorized: status = 401
    case .forbidden: status = 403
    case .notFound: status = 404
    case .conflict: status = 409
    case .validation(let code, _): status = code
    case .server(let code, _): status = code
    case .unexpectedStatus(let code): status = code
    case .offline, .network, .invalidResponse, .invalidRequest:
      return stationError
    }
    let problem = stationError.problem
    return StationProblem(
      status: status, code: problem?.code ?? "http_\(status)", title: problem?.title,
      detail: problem?.detail)
  }

  // MARK: Requests

  public static func convert(_ request: UploadSessionRequest) -> StationAPIUploadSessionRequest {
    StationAPIUploadSessionRequest(
      packageId: request.packageId, visitId: request.visitId, dealId: request.dealId,
      revision: request.revision, supersedesPackageId: request.supersedesPackageId,
      files: request.files.map {
        StationAPIUploadFileDeclaration(
          path: $0.path, role: $0.role, captureId: $0.captureId, areaKey: $0.areaKey,
          sha256: $0.sha256, bytes: $0.bytes)
      })
  }

  // MARK: Responses

  public static func convert(_ session: StationAPIUploadSession) throws -> UploadSession {
    UploadSession(
      packageId: session.packageId, visitId: session.visitId, dealId: session.dealId,
      revision: session.revision, status: try convert(session.status),
      files: try session.files.map { file in
        UploadSessionFile(
          path: file.path, status: try convert(file.status),
          upload: file.upload.map(convert))
      })
  }

  /// The SAS URL is passed on exactly as the station issued it (`absoluteString` of the URL
  /// StationClient decoded from the response). It is never logged.
  public static func convert(_ target: StationAPIUploadTarget) -> UploadTarget {
    UploadTarget(
      url: target.url.absoluteString, method: target.method.rawValue, headers: target.headers,
      expiresAt: target.expiresAt)
  }

  public static func convert(_ result: StationAPIFileCheckResult) throws -> FileCheckResult {
    FileCheckResult(
      path: result.path, status: try convert(result.status), expectedSha256: result.expectedSha256,
      actualSha256: result.actualSha256, expectedBytes: result.expectedBytes,
      actualBytes: result.actualBytes, checkedAt: result.checkedAt)
  }

  public static func convert(_ package: StationAPIPackage) throws -> PackageSealResult {
    PackageSealResult(
      packageId: package.packageId, visitId: package.visitId, dealId: package.dealId,
      revision: package.revision, supersedesPackageId: package.supersedesPackageId,
      status: try convert(package.status), createdAt: package.createdAt,
      sealedAt: package.sealedAt,
      files: try package.files.map { file in
        PackageFileStatus(
          path: file.path, role: file.role, captureId: file.captureId, areaKey: file.areaKey,
          sha256: file.sha256, bytes: file.bytes, status: try convert(file.status),
          checkedAt: file.checkedAt)
      },
      manifest: package.manifest, captureRecord: package.captureRecord,
      verdict: package.verdict.map {
        VerdictSummary(verdictId: $0.verdictId, outcome: $0.outcome, evaluatedAt: $0.evaluatedAt)
      })
  }

  public static func convert(_ status: StationAPIFileStatus) throws -> FileStatus {
    guard let value = FileStatus(rawValue: status.rawValue) else {
      throw StationBridgeError(field: "file status", value: status.rawValue)
    }
    return value
  }

  public static func convert(_ status: StationAPIPackageStatus) throws -> PackageStatus {
    guard let value = PackageStatus(rawValue: status.rawValue) else {
      throw StationBridgeError(field: "package status", value: status.rawValue)
    }
    return value
  }
}
