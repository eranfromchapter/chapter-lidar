import Foundation

/// The station operations the uploader needs (contract/openapi/station.yaml). The app's
/// StationClient conforms to this protocol; tests use fakes.
///
/// Implementations should throw `StationProblem` for problem+json answers (4xx/5xx), so the
/// uploader can react to the codes it knows (for example `upload_target_changed`). Any other
/// error is treated as transient: the upload stops with its state saved and can be resumed.
public protocol PackageUploadService: Sendable {
  /// `POST /packages` (createUploadSession), answered with 200 (resumed) or 201 (created).
  /// Idempotent: the same body returns the same session with fresh upload targets.
  func openSession(_ request: UploadSessionRequest) async throws -> UploadSession
  /// `POST /packages/{id}/files/complete`: the station hashes the stored blob and compares it
  /// with the declaration.
  func completeFile(packageId: UUID, path: String) async throws -> FileCheckResult
  /// `POST /packages/{id}/seal`. The body is the manifest bytes exactly as written on the phone;
  /// implementations must send them unchanged (never re-encode).
  func seal(packageId: UUID, manifestJSON: Data) async throws -> PackageSealResult
}

/// An RFC 9457 problem answer from the station.
public struct StationProblem: Error, Hashable, Sendable, CustomStringConvertible {
  /// HTTP status.
  public var status: Int
  /// Stable machine-readable code, for example upload_target_changed.
  public var code: String
  public var title: String?
  public var detail: String?

  public init(status: Int, code: String, title: String? = nil, detail: String? = nil) {
    self.status = status
    self.code = code
    self.title = title
    self.detail = detail
  }

  public var description: String {
    "station problem \(status) \(code)" + (detail.map { ": \($0)" } ?? "")
  }
}
