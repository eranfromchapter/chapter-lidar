import CaptureContract
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Where the station is. HTTPS is required; plain HTTP is accepted only for `localhost` and
/// `127.0.0.1` (local station for tests).
public struct StationClientConfiguration: Sendable, Equatable {
  /// The station host, for example `https://station.example.com`. The client appends the
  /// document's server path (`/v1`) and the operation path.
  public let stationURL: URL

  public enum ConfigurationError: Error, Sendable, Equatable {
    /// The URL is not HTTPS (and not a local http URL), has no host, or carries credentials,
    /// a query or a fragment.
    case invalidStationURL(String)
  }

  public init(stationURL: URL) throws {
    guard let components = URLComponents(url: stationURL, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(),
      let host = components.host?.lowercased(), !host.isEmpty
    else {
      throw ConfigurationError.invalidStationURL("the station URL needs a scheme and a host")
    }
    let isLocal = host == "localhost" || host == "127.0.0.1"
    guard scheme == "https" || (scheme == "http" && isLocal) else {
      throw ConfigurationError.invalidStationURL(
        "the station URL must use https (http only for localhost or 127.0.0.1)")
    }
    guard components.user == nil, components.password == nil, components.query == nil,
      components.fragment == nil
    else {
      throw ConfigurationError.invalidStationURL(
        "the station URL must not carry credentials, a query or a fragment")
    }
    self.stationURL = stationURL
  }
}

/// Client for every operation of contract/openapi/station.yaml.
///
/// - Authorized operations send `Authorization: Bearer <token>` from the `AccessTokenProvider`.
///   On 401 the client asks once for a fresh token (`forceRefresh: true`) and retries once; a
///   second 401 is `StationError.unauthorized` (sign in again).
/// - HTTP errors map to `StationError` with the station's problem details.
/// - Nothing is logged. Tokens, Authorization headers and SAS URLs never appear in errors.
public struct StationClient: Sendable {
  public let configuration: StationClientConfiguration
  private let tokenProvider: any AccessTokenProvider
  private let transport: any HTTPTransport

  public init(
    configuration: StationClientConfiguration,
    tokenProvider: any AccessTokenProvider,
    transport: any HTTPTransport = URLSessionTransport()
  ) {
    self.configuration = configuration
    self.tokenProvider = tokenProvider
    self.transport = transport
  }

  // MARK: - health

  /// `GET /health` (getHealth). Unauthenticated: no token is requested or sent.
  public func getHealth() async throws -> Health {
    try await call(.getHealth, as: Health.self)
  }

  // MARK: - projects

  /// `GET /projects` (listProjects): HUB deals with a confirmed address, most recently updated
  /// first. `query` matches the project name or address; `limit` is 1 to 100 (station default
  /// 25). Both are omitted from the request when nil.
  public func listProjects(query: String? = nil, limit: Int? = nil) async throws -> [HubProject] {
    var items: [(String, String)] = []
    if let query { items.append(("q", query)) }
    if let limit { items.append(("limit", String(limit))) }
    return try await call(.listProjects, query: items, as: ProjectListResponse.self).projects
  }

  /// `GET /projects/{dealId}` (getProject).
  public func getProject(dealId: String) async throws -> HubProject {
    guard !dealId.isEmpty else {
      throw StationError.invalidRequest("dealId must not be empty")
    }
    return try await call(.getProject, path: ["dealId": dealId], as: HubProject.self)
  }

  // MARK: - packages

  /// `POST /packages` (createUploadSession): opens or resumes the upload session. 200 (resumed)
  /// and 201 (created) both return the session with fresh upload targets.
  public func createUploadSession(_ request: UploadSessionRequest) async throws -> UploadSession {
    try await call(.createUploadSession, body: try encode(request), as: UploadSession.self)
  }

  /// `GET /packages?dealId=&visitId=` (listPackages): packages of a HUB project, newest first.
  public func listPackages(dealId: String, visitId: UUID? = nil) async throws -> [PackageSummary] {
    var items: [(String, String)] = [("dealId", dealId)]
    if let visitId { items.append(("visitId", LowercaseUUID(visitId).rawValue)) }
    return try await call(.listPackages, query: items, as: PackageListResponse.self).packages
  }

  /// `GET /packages/{packageId}` (getPackage).
  public func getPackage(packageId: UUID) async throws -> Package {
    try await call(.getPackage, path: packagePath(packageId), as: Package.self)
  }

  /// `POST /packages/{packageId}/files/complete` (completeFile): the station checks the stored
  /// blob and returns the result with 200 whether or not it matches. The caller marks a file
  /// done only when `status` is `.verified`.
  public func completeFile(packageId: UUID, path: String) async throws -> FileCheckResult {
    try await call(
      .completeFile, path: packagePath(packageId),
      body: try encode(CompleteFileRequest(path: path)),
      as: FileCheckResult.self)
  }

  /// `GET /packages/{packageId}/files/download?path=` (getFileDownloadLink). The returned URL is a
  /// secret until it expires: do not log or share it.
  public func getFileDownloadLink(packageId: UUID, path: String) async throws -> DownloadLink {
    try await call(
      .getFileDownloadLink, path: packagePath(packageId), query: [("path", path)],
      as: DownloadLink.self)
  }

  /// `POST /packages/{packageId}/seal` (sealPackage). `manifestJSON` is sent byte for byte as the
  /// request body (the manifest exactly as written on the phone); it is never decoded or
  /// re-encoded here.
  public func sealPackage(packageId: UUID, manifestJSON: Data) async throws -> Package {
    try await call(.sealPackage, path: packagePath(packageId), body: manifestJSON, as: Package.self)
  }

  // MARK: - verdicts

  /// `GET /packages/{packageId}/verdict` (getVerdict). `StationError.notFound` with problem code
  /// `verdict_not_ready` while the checks are running.
  public func getVerdict(packageId: UUID) async throws -> Verdict {
    try await call(.getVerdict, path: packagePath(packageId), as: Verdict.self)
  }

  // MARK: - modeling decisions

  /// `GET /packages/{packageId}/modeling-decisions` (listModelingDecisions), oldest first.
  public func listModelingDecisions(packageId: UUID) async throws -> [ModelingDecision] {
    try await call(
      .listModelingDecisions, path: packagePath(packageId), as: ModelingDecisionListResponse.self
    ).decisions
  }

  /// `POST /packages/{packageId}/modeling-decisions` (createModelingDecision).
  public func createModelingDecision(packageId: UUID, _ input: ModelingDecisionInput)
    async throws -> ModelingDecision
  {
    try await call(
      .createModelingDecision, path: packagePath(packageId), body: try encode(input),
      as: ModelingDecision.self)
  }

  // MARK: - next revision

  /// `PUT /packages/{packageId}/next-revision` (putNextRevisionNotice): replaces the notice of
  /// the sealed package `packageId` with what its next revision (`notice.revision`, the
  /// package's revision + 1) changes so far. Best effort for the caller: 409
  /// (`package_not_sealed`, `revision_exists`) and 422 (`revision_mismatch`) are thrown as usual.
  @discardableResult
  public func putNextRevisionNotice(packageId: UUID, _ notice: NextRevisionNoticeInput)
    async throws -> NextRevisionNotice
  {
    try await call(
      .putNextRevisionNotice, path: packagePath(packageId), body: try encode(notice),
      as: NextRevisionNotice.self)
  }

  // MARK: - sketch interpretations

  /// `POST /sketch-interpretations` (createSketchInterpretation, spec F16): the station has Claude
  /// read a photo of a floor-plan sketch and answers what it read. A photo that is not a plan
  /// or cannot be read (422) throws `SketchInterpretationRejected` with the station's problem
  /// and, when it sent one, its interpretation (the reading's `problem` says why). Any other
  /// error status throws `StationError` as usual (503: the station cannot read sketches now).
  /// Reading takes 10 to 40 s; give this client a transport with a long timeout (150 s).
  public func createSketchInterpretation(_ request: SketchInterpretationRequest) async throws
    -> SketchInterpretation
  {
    let operation = StationOperation.createSketchInterpretation
    let (data, status) = try await sendRaw(
      operation, path: [:], query: [], body: try encode(request))
    if operation.successStatuses.contains(status) {
      do {
        return try CaptureContractJSON.makeDecoder().decode(SketchInterpretation.self, from: data)
      } catch let error as DecodingError {
        throw StationError.invalidResponse(
          "\(operation.operationId): \(Self.describe(error)) (SketchInterpretation)")
      }
    }
    if status == 422 {
      let rejection = try? CaptureContractJSON.makeDecoder().decode(
        SketchInterpretationRejectionBody.self, from: data)
      throw SketchInterpretationRejected(
        problem: Self.problem(from: data), interpretation: rejection?.interpretation)
    }
    throw StationError.from(status: status, problem: Self.problem(from: data))
  }

  // MARK: - plumbing

  private func packagePath(_ packageId: UUID) -> [String: String] {
    ["packageId": LowercaseUUID(packageId).rawValue]
  }

  private func encode<T: Encodable>(_ value: T) throws -> Data {
    try CaptureContractJSON.makeEncoder().encode(value)
  }

  private func call<T: Decodable>(
    _ operation: StationOperation,
    path: [String: String] = [:],
    query: [(String, String)] = [],
    body: Data? = nil,
    as type: T.Type
  ) async throws -> T {
    let data = try await send(operation, path: path, query: query, body: body)
    do {
      return try CaptureContractJSON.makeDecoder().decode(T.self, from: data)
    } catch let error as DecodingError {
      throw StationError.invalidResponse(
        "\(operation.operationId): \(Self.describe(error)) (\(T.self))")
    }
  }

  /// Sends the request (with the bearer token when the operation needs one) and returns the body
  /// of a documented success status. Everything else throws `StationError`.
  private func send(
    _ operation: StationOperation,
    path: [String: String],
    query: [(String, String)],
    body: Data?
  ) async throws -> Data {
    let (data, status) = try await sendRaw(operation, path: path, query: query, body: body)
    if operation.successStatuses.contains(status) {
      return data
    }
    throw StationError.from(status: status, problem: Self.problem(from: data))
  }

  /// Sends the request (with the bearer token when the operation needs one, retried once with a
  /// fresh token on 401) and returns the body and status, whatever the status.
  private func sendRaw(
    _ operation: StationOperation,
    path: [String: String],
    query: [(String, String)],
    body: Data?
  ) async throws -> (Data, Int) {
    var request = URLRequest(url: try url(for: operation, path: path, query: query))
    request.httpMethod = operation.method
    request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    var (data, response) = try await attempt(request, operation: operation, forceRefresh: false)
    if response.statusCode == 401 && operation.requiresAuthorization {
      (data, response) = try await attempt(request, operation: operation, forceRefresh: true)
    }

    return (data, response.statusCode)
  }

  private func attempt(
    _ request: URLRequest, operation: StationOperation, forceRefresh: Bool
  ) async throws -> (Data, HTTPURLResponse) {
    var request = request
    if operation.requiresAuthorization {
      let token = try await tokenProvider.accessToken(forceRefresh: forceRefresh)
      guard Self.isUsableToken(token) else {
        // An empty or malformed token cannot authenticate: the caller must sign in again.
        throw StationError.unauthorized(nil)
      }
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    do {
      return try await transport.send(request)
    } catch {
      throw StationError.fromTransport(error)
    }
  }

  /// Non-empty, printable ASCII without spaces (a JWT or other bearer token), so it cannot break
  /// the header.
  static func isUsableToken(_ token: String) -> Bool {
    !token.isEmpty && token.utf8.allSatisfy { $0 > 0x20 && $0 < 0x7F }
  }

  private static func problem(from data: Data) -> Problem? {
    guard !data.isEmpty else { return nil }
    return try? CaptureContractJSON.makeDecoder().decode(Problem.self, from: data)
  }

  private static func describe(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String {
      let keys = context.codingPath.map { key in
        key.intValue.map { "[\($0)]" } ?? key.stringValue
      }
      return keys.isEmpty ? "body" : keys.joined(separator: ".")
    }
    switch error {
    case .keyNotFound(let key, let context):
      return "missing \(key.stringValue) at \(path(context))"
    case .typeMismatch(_, let context), .valueNotFound(_, let context),
      .dataCorrupted(let context):
      return "invalid value at \(path(context))"
    @unknown default:
      return "body does not match the document"
    }
  }

  // MARK: - URLs

  /// stationURL + `/v1` + the operation path with encoded parameters + the encoded query.
  func url(
    for operation: StationOperation, path parameters: [String: String], query: [(String, String)]
  ) throws -> URL {
    var path = operation.pathTemplate
    for (name, value) in parameters {
      path = path.replacingOccurrences(
        of: "{\(name)}", with: Self.percentEncodePathSegment(value))
    }
    guard !path.contains("{") else {
      throw StationError.invalidRequest("\(operation.operationId): missing path parameter")
    }
    var base = configuration.stationURL.absoluteString
    while base.hasSuffix("/") { base.removeLast() }
    var text = base + StationOperation.serverBasePath + path
    if !query.isEmpty {
      text +=
        "?"
        + query.map { "\(Self.percentEncode($0.0))=\(Self.percentEncode($0.1))" }
        .joined(separator: "&")
    }
    guard let url = URL(string: text) else {
      throw StationError.invalidRequest("\(operation.operationId): cannot form the request URL")
    }
    return url
  }

  /// Like `percentEncode`, and a segment that is only dots is encoded too, so `.` or `..` can
  /// never be resolved as a relative path segment.
  static func percentEncodePathSegment(_ value: String) -> String {
    if !value.isEmpty && value.allSatisfy({ $0 == "." }) {
      return String(repeating: "%2E", count: value.count)
    }
    return percentEncode(value)
  }

  /// Percent-encodes everything except RFC 3986 unreserved characters, so `/`, `+`, `&`, `?`,
  /// `#` and spaces in a dealId or file path can never change the route or the query.
  static func percentEncode(_ value: String) -> String {
    var result = ""
    for byte in value.utf8 {
      switch byte {
      case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
        UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
        UInt8(ascii: "_"), UInt8(ascii: "~"):
        result.append(Character(UnicodeScalar(byte)))
      default:
        let hex = String(byte, radix: 16, uppercase: true)
        result += "%" + (hex.count == 1 ? "0" + hex : hex)
      }
    }
    return result
  }
}
