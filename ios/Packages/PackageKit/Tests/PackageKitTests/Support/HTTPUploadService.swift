import CaptureContract
import Foundation
import PackageCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Minimal `PackageUploadService` over HTTP for the end-to-end test against the local station
/// (contract/openapi/station.yaml, base path /v1). The app uses StationClient instead.
struct HTTPUploadService: PackageUploadService {
  /// Station API base, ending in /v1.
  let baseURL: URL
  let accessToken: String
  let session: URLSession

  init(baseURL: URL, accessToken: String, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.accessToken = accessToken
    self.session = session
  }

  func openSession(_ request: UploadSessionRequest) async throws -> UploadSession {
    let body = try CaptureContractJSON.makeEncoder().encode(request)
    return try await send("packages", body: body, accept: [200, 201])
  }

  func completeFile(packageId: UUID, path: String) async throws -> FileCheckResult {
    let body = try CaptureContractJSON.makeEncoder().encode(["path": path])
    return try await send(
      "packages/\(LowercaseUUID(packageId).rawValue)/files/complete", body: body, accept: [200])
  }

  func seal(packageId: UUID, manifestJSON: Data) async throws -> PackageSealResult {
    // The manifest bytes exactly as written on the phone.
    try await send(
      "packages/\(LowercaseUUID(packageId).rawValue)/seal", body: manifestJSON, accept: [200, 202])
  }

  private func send<T: Decodable>(_ path: String, body: Data, accept: Set<Int>) async throws -> T {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.upload(for: request, from: body)
    guard let http = response as? HTTPURLResponse else {
      throw StationProblem(status: 0, code: "no_http_response")
    }
    guard accept.contains(http.statusCode) else {
      let problem = try? JSONDecoder().decode(ProblemBody.self, from: data)
      throw StationProblem(
        status: http.statusCode, code: problem?.code ?? "http_\(http.statusCode)",
        title: problem?.title, detail: problem?.detail)
    }
    return try CaptureContractJSON.makeDecoder().decode(T.self, from: data)
  }

  private struct ProblemBody: Decodable {
    var code: String?
    var title: String?
    var detail: String?
  }
}

/// Gets an access token from the local test sign-in service (station/dev-idp).
enum DevSignIn {
  struct TokenResponse: Decodable {
    var access_token: String
    var token_type: String
    var expires_in: Int
  }

  static func accessToken(from idp: URL, session: URLSession = .shared) async throws -> String {
    var request = URLRequest(url: idp.appendingPathComponent("token"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body = Data(#"{"roles":["capture"],"sub":"e2e-packagekit","name":"PackageKit E2E"}"#.utf8)
    let (data, response) = try await session.upload(for: request, from: body)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw FixtureError(
        "test sign-in at \(idp.absoluteString) answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
    }
    let token = try JSONDecoder().decode(TokenResponse.self, from: data)
    guard token.token_type.lowercased() == "bearer", !token.access_token.isEmpty else {
      throw FixtureError("test sign-in returned no bearer token")
    }
    return token.access_token
  }
}
