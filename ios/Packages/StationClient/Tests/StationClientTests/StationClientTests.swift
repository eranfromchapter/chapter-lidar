import CaptureContract
import Foundation
import StationClient
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class StationClientTests: XCTestCase {
  // MARK: - auth header

  func testAuthorizedOperationSendsBearerTokenFromProvider() async throws {
    let transport = StubTransport([.respond(.json(200, Fixtures.projects))])
    let tokens = StubTokenProvider(tokens: ["token-1"])
    let client = try makeClient(transport: transport, tokens: tokens)

    let projects = try await client.listProjects()

    XCTAssertEqual(projects.map(\.dealId), ["4821", "4822"])
    XCTAssertEqual(projects[0].address.formatted, "345 7th Ave, New York, NY 10001")
    XCTAssertNil(projects[1].projectName)
    XCTAssertEqual(tokens.forceRefreshCalls, [false])
    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.url?.absoluteString, "https://station.test/v1/projects")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Accept"), "application/json, application/problem+json")
    XCTAssertNil(request.httpBody)
  }

  func testHealthSendsNoTokenAndAsksForNone() async throws {
    let transport = StubTransport([.respond(.json(200, Fixtures.health))])
    let tokens = StubTokenProvider()
    let client = try makeClient(transport: transport, tokens: tokens)

    let health = try await client.getHealth()

    XCTAssertEqual(health, Health(status: "ok", version: "1.4.0"))
    XCTAssertEqual(tokens.forceRefreshCalls, [])
    XCTAssertNil(transport.requests.first?.value(forHTTPHeaderField: "Authorization"))
    XCTAssertEqual(transport.requests.first?.url?.absoluteString, "https://station.test/v1/health")
  }

  func testHealth503IsServerError() async throws {
    let transport = StubTransport([.respond(.problem(503, code: "registry_unavailable"))])
    let client = try makeClient(transport: transport)

    let error = await captureError { _ = try await client.getHealth() }

    guard case .server(503, let problem)? = error as? StationError else {
      return XCTFail("expected server 503, got \(String(describing: error))")
    }
    XCTAssertEqual(problem?.code, "registry_unavailable")
  }

  // MARK: - 401 refresh once

  func testUnauthorizedRefreshesTokenOnceAndRetries() async throws {
    let transport = StubTransport([
      .respond(.problem(401, code: "unauthorized")),
      .respond(.json(200, Fixtures.project)),
    ])
    let tokens = StubTokenProvider(tokens: ["expired-token", "fresh-token"])
    let client = try makeClient(transport: transport, tokens: tokens)

    let project = try await client.getProject(dealId: "4821")

    XCTAssertEqual(project.dealId, "4821")
    XCTAssertEqual(tokens.forceRefreshCalls, [false, true])
    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertEqual(
      transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") },
      ["Bearer expired-token", "Bearer fresh-token"])
    XCTAssertEqual(transport.requests[0].url, transport.requests[1].url)
  }

  func testSecondUnauthorizedFailsWithUnauthorizedAndDoesNotRetryAgain() async throws {
    let transport = StubTransport([
      .respond(.problem(401, code: "unauthorized")),
      .respond(.problem(401, code: "unauthorized")),
      .respond(.json(200, Fixtures.project)),
    ])
    let tokens = StubTokenProvider()
    let client = try makeClient(transport: transport, tokens: tokens)

    let error = await captureError { _ = try await client.getProject(dealId: "4821") }

    let stationError = try XCTUnwrap(error as? StationError)
    XCTAssertTrue(stationError.requiresSignIn)
    XCTAssertEqual(stationError.problem?.code, "unauthorized")
    XCTAssertEqual(tokens.forceRefreshCalls, [false, true])
    XCTAssertEqual(transport.requests.count, 2)
  }

  func testRetryAfterUnauthorizedResendsTheSameBody() async throws {
    let manifest = try Fixtures.manifestBytes()
    let transport = StubTransport([
      .respond(.problem(401, code: "unauthorized")),
      .respond(.json(202, Fixtures.package)),
    ])
    let client = try makeClient(transport: transport)

    _ = try await client.sealPackage(packageId: Fixtures.packageId, manifestJSON: manifest)

    XCTAssertEqual(transport.requests.map(\.httpBody), [manifest, manifest])
  }

  func testForbiddenIsNotRetried() async throws {
    let transport = StubTransport([.respond(.problem(403, code: "forbidden"))])
    let tokens = StubTokenProvider()
    let client = try makeClient(transport: transport, tokens: tokens)

    let error = await captureError { _ = try await client.listProjects() }

    XCTAssertEqual(
      error as? StationError,
      .forbidden(Problem(type: "about:blank", title: "Error", status: 403, code: "forbidden")))
    XCTAssertEqual(tokens.forceRefreshCalls, [false])
    XCTAssertEqual(transport.requests.count, 1)
  }

  func testTokenProviderErrorIsPassedThroughAndNothingIsSent() async throws {
    let transport = StubTransport([.respond(.json(200, Fixtures.projects))])
    let client = try makeClient(transport: transport, tokens: StubTokenProvider(fails: true))

    let error = await captureError { _ = try await client.listProjects() }

    XCTAssertTrue(error is StubTokenProvider.Failure, "got \(String(describing: error))")
    XCTAssertEqual(transport.requests.count, 0)
  }

  func testUnusableTokenIsUnauthorizedAndNothingIsSent() async throws {
    for token in ["", "two words", "line\r\nX-Injected: 1"] {
      let transport = StubTransport([.respond(.json(200, Fixtures.projects))])
      let client = try makeClient(transport: transport, tokens: StubTokenProvider(tokens: [token]))

      let error = await captureError { _ = try await client.listProjects() }

      XCTAssertEqual(error as? StationError, .unauthorized(nil))
      XCTAssertEqual(transport.requests.count, 0)
    }
  }

  // MARK: - error mapping

  func testHTTPErrorsMapToTypedErrors() async throws {
    let cases: [(StubResponse, (StationError) -> Bool)] = [
      (
        .problem(400, code: "bad_request"),
        { if case .validation(400, _) = $0 { true } else { false } }
      ),
      (
        .problem(404, code: "project_not_found"), { if case .notFound = $0 { true } else { false } }
      ),
      (.problem(409, code: "package_conflict"), { if case .conflict = $0 { true } else { false } }),
      (
        .problem(422, code: "invalid_upload_session"),
        { if case .validation(422, _) = $0 { true } else { false } }
      ),
      (
        .problem(502, code: "hub_unavailable"),
        { if case .server(502, _) = $0 { true } else { false } }
      ),
      (
        .problem(503, code: "storage_unavailable"),
        { if case .server(503, _) = $0 { true } else { false } }
      ),
    ]
    for (response, matches) in cases {
      let transport = StubTransport([.respond(response)])
      let client = try makeClient(transport: transport)

      let error = await captureError { _ = try await client.getProject(dealId: "4821") }

      let stationError = try XCTUnwrap(error as? StationError, "status \(response.status)")
      XCTAssertTrue(matches(stationError), "status \(response.status) gave \(stationError)")
      XCTAssertEqual(stationError.problem?.status, response.status)
      XCTAssertFalse(stationError.requiresSignIn)
    }
  }

  func testProblemDetailsAreDecodedWithFieldErrors() async throws {
    let body = """
      {"type":"about:blank","title":"Unprocessable Content","status":422,\
      "code":"invalid_upload_session","detail":"The upload session request breaks a contract rule.",\
      "errors":[{"pointer":"/files/0/captureId","message":"must be omitted for field_controls"}]}
      """
    let transport = StubTransport([
      .respond(
        StubResponse(status: 422, body: Data(body.utf8), contentType: "application/problem+json"))
    ])
    let client = try makeClient(transport: transport)

    let error = await captureError {
      _ = try await client.createUploadSession(Self.sessionRequest())
    }

    let problem = try XCTUnwrap((error as? StationError)?.problem)
    XCTAssertEqual(problem.code, "invalid_upload_session")
    XCTAssertEqual(problem.detail, "The upload session request breaks a contract rule.")
    XCTAssertEqual(
      problem.errors,
      [.init(pointer: "/files/0/captureId", message: "must be omitted for field_controls")])
  }

  func testErrorWithoutProblemBodyStillMaps() async throws {
    let transport = StubTransport([
      .respond(StubResponse(status: 404, body: Data(), contentType: "text/plain")),
      .respond(StubResponse(status: 409, body: Data("<html>".utf8), contentType: "text/html")),
    ])
    let client = try makeClient(transport: transport)

    let notFound = await captureError {
      _ = try await client.getPackage(packageId: Fixtures.packageId)
    }
    let conflict = await captureError {
      _ = try await client.getPackage(packageId: Fixtures.packageId)
    }

    XCTAssertEqual(notFound as? StationError, .notFound(nil))
    XCTAssertEqual(conflict as? StationError, .conflict(nil))
  }

  func testUndocumentedStatusesAreUnexpected() async throws {
    // 201 is not a documented success for getPackage; redirects are never followed.
    for status in [201, 204, 302, 418] {
      let transport = StubTransport([.respond(.json(status, Fixtures.package))])
      let client = try makeClient(transport: transport)

      let error = await captureError {
        _ = try await client.getPackage(packageId: Fixtures.packageId)
      }

      XCTAssertEqual(error as? StationError, .unexpectedStatus(status))
    }
  }

  func testTransportErrorsMapToOfflineOrNetwork() async throws {
    let offline: [URLError.Code] = [
      .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
      .cannotConnectToHost, .dnsLookupFailed,
    ]
    for code in offline {
      let client = try makeClient(transport: StubTransport([.fail(code)]))
      let error = await captureError { _ = try await client.listProjects() }
      XCTAssertEqual(error as? StationError, .offline, "URLError \(code.rawValue)")
    }
    let client = try makeClient(transport: StubTransport([.fail(.serverCertificateUntrusted)]))
    let error = await captureError { _ = try await client.listProjects() }
    XCTAssertEqual(
      error as? StationError, .network(code: URLError.Code.serverCertificateUntrusted.rawValue))

    let cancelled = try makeClient(transport: StubTransport([.fail(.cancelled)]))
    let cancelError = await captureError { _ = try await cancelled.listProjects() }
    XCTAssertTrue(cancelError is CancellationError, "got \(String(describing: cancelError))")
  }

  func testUnreachableLocalStationIsOfflineThroughURLSession() async throws {
    // Nothing listens on port 1; the real URLSession transport reports it as offline.
    let client = StationClient(
      configuration: try StationClientConfiguration(stationURL: URL(string: "http://127.0.0.1:1")!),
      tokenProvider: StubTokenProvider(), transport: URLSessionTransport(timeout: 5))

    let error = await captureError { _ = try await client.listProjects() }

    XCTAssertEqual(error as? StationError, .offline)
  }

  func testSuccessBodyThatBreaksTheDocumentIsInvalidResponse() async throws {
    let transport = StubTransport([.respond(.json(200, #"{"projects":[{"dealId":"4821"}]}"#))])
    let client = try makeClient(transport: transport)

    let error = await captureError { _ = try await client.listProjects() }

    guard case .invalidResponse(let message)? = error as? StationError else {
      return XCTFail("expected invalidResponse, got \(String(describing: error))")
    }
    XCTAssertTrue(message.contains("listProjects"), message)
    XCTAssertTrue(message.contains("address"), message)
  }

  // MARK: - raw manifest seal body

  func testSealSendsManifestBytesExactlyAsGiven() async throws {
    // Unusual but valid JSON formatting (tabs, key order, escaped slash): a decode/re-encode
    // would change these bytes.
    let original = try Fixtures.manifestBytes()
    var manifest = Data("\t".utf8)
    manifest.append(original)
    manifest.append(Data("\n\n".utf8))
    let transport = StubTransport([.respond(.json(202, Fixtures.package))])
    let client = try makeClient(transport: transport)

    let package = try await client.sealPackage(
      packageId: Fixtures.packageId, manifestJSON: manifest)

    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
      request.url?.absoluteString,
      "https://station.test/v1/packages/\(Fixtures.packageIdText)/seal")
    XCTAssertEqual(request.httpBody, manifest)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(package.status, .checksQueued)
    XCTAssertEqual(package.files.first?.status, .verified)
  }

  func testSealAcceptsAlreadySealed200AndDecodesManifest() async throws {
    let manifestText = String(decoding: try Fixtures.manifestBytes(), as: UTF8.self)
    let body = Fixtures.package.replacingOccurrences(
      of: #""files":"#, with: #""manifest":\#(manifestText),"files":"#)
    let transport = StubTransport([.respond(.json(200, body))])
    let client = try makeClient(transport: transport)

    let package = try await client.sealPackage(
      packageId: Fixtures.packageId, manifestJSON: try Fixtures.manifestBytes())

    XCTAssertEqual(package.manifest?.revision, 1)
    XCTAssertEqual(package.manifest?.files.isEmpty, false)
  }

  // MARK: - other operations

  func testCreateUploadSessionSendsContractBodyAndAcceptsCreatedAndResumed() async throws {
    let transport = StubTransport([
      .respond(.json(201, Fixtures.uploadSession)),
      .respond(.json(200, Fixtures.uploadSession)),
    ])
    let client = try makeClient(transport: transport)

    let created = try await client.createUploadSession(Self.sessionRequest())
    let resumed = try await client.createUploadSession(Self.sessionRequest())

    XCTAssertEqual(created, resumed)
    XCTAssertEqual(created.status, .uploading)
    XCTAssertEqual(created.files.count, 2)
    let target = try XCTUnwrap(created.files[0].upload)
    XCTAssertEqual(target.method, .put)
    XCTAssertEqual(target.headers, ["x-ms-blob-type": "BlockBlob"])
    XCTAssertEqual(target.expiresAt.rawValue, "2026-10-17T14:32:11Z")
    XCTAssertNil(created.files[1].upload)

    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "https://station.test/v1/packages")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    XCTAssertEqual(json["packageId"] as? String, Fixtures.packageIdText)
    XCTAssertEqual(json["visitId"] as? String, Fixtures.visitIdText)
    XCTAssertEqual(json["dealId"] as? String, "4821")
    XCTAssertEqual(json["revision"] as? Int, 1)
    XCTAssertNil(json["supersedesPackageId"], "optional fields are omitted, never null")
    let files = try XCTUnwrap(json["files"] as? [[String: Any]])
    XCTAssertEqual(
      Set(files[0].keys), ["path", "role", "sha256", "bytes"], "visit-wide file omits capture")
    XCTAssertEqual(Set(files[1].keys), ["path", "role", "captureId", "areaKey", "sha256", "bytes"])
    XCTAssertEqual(files[1]["captureId"] as? String, Fixtures.captureId.uuidString.lowercased())
  }

  func testSecretURLsAreRedactedInDescriptions() throws {
    let session = try JSONDecoder().decode(
      UploadSession.self, from: Data(Fixtures.uploadSession.utf8))
    let link = try JSONDecoder().decode(DownloadLink.self, from: Data(Fixtures.downloadLink.utf8))
    let target = try XCTUnwrap(session.files[0].upload)

    var dumped = ""
    dump(target, to: &dumped)
    dump(link, to: &dumped)
    for text in [
      String(describing: target), String(reflecting: target), String(describing: link),
      String(reflecting: link), dumped,
    ] {
      XCTAssertFalse(text.contains("blob.test"), text)
    }
  }

  func testCompleteFileSendsPathAndDecodesNotUploaded() async throws {
    let transport = StubTransport([.respond(.json(200, Fixtures.fileCheckNotUploaded))])
    let client = try makeClient(transport: transport)

    let result = try await client.completeFile(
      packageId: Fixtures.packageId, path: "Field Measurements/field-controls.json")

    XCTAssertEqual(result.status, .notUploaded)
    XCTAssertNil(result.actualSha256)
    XCTAssertNil(result.actualBytes)
    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(
      request.url?.absoluteString,
      "https://station.test/v1/packages/\(Fixtures.packageIdText)/files/complete")
    XCTAssertEqual(
      request.httpBody.map { String(decoding: $0, as: UTF8.self) },
      #"{"path":"Field Measurements/field-controls.json"}"#)
  }

  func testPathAndQueryValuesAreEncodedSoTheyCannotChangeTheRoute() async throws {
    let transport = StubTransport { request, _ in
      if request.url?.path.contains("/files/download") == true {
        return .respond(.json(200, Fixtures.downloadLink))
      }
      if request.url?.path.hasSuffix("/projects") == true {
        return .respond(.json(200, Fixtures.projects))
      }
      if request.url?.path.hasSuffix("/packages") == true {
        return .respond(.json(200, Fixtures.packageSummaries))
      }
      return .respond(.json(200, Fixtures.project))
    }
    let client = try makeClient(transport: transport)

    _ = try await client.getProject(dealId: "a/b c?d#e")
    _ = try await client.getProject(dealId: "..")
    _ = try await client.getFileDownloadLink(
      packageId: Fixtures.packageId, path: "Site Photos/a+b&c=d.heic")
    _ = try await client.listProjects(query: "7th Ave & 29th", limit: 50)
    _ = try await client.listPackages(dealId: "4821", visitId: Fixtures.visitId)

    XCTAssertEqual(
      transport.requests.map { $0.url?.absoluteString },
      [
        "https://station.test/v1/projects/a%2Fb%20c%3Fd%23e",
        "https://station.test/v1/projects/%2E%2E",
        "https://station.test/v1/packages/\(Fixtures.packageIdText)/files/download"
          + "?path=Site%20Photos%2Fa%2Bb%26c%3Dd.heic",
        "https://station.test/v1/projects?q=7th%20Ave%20%26%2029th&limit=50",
        "https://station.test/v1/packages?dealId=4821&visitId=\(Fixtures.visitIdText)",
      ])
  }

  func testEmptyDealIdIsRefusedBeforeSending() async throws {
    let transport = StubTransport([.respond(.json(200, Fixtures.project))])
    let client = try makeClient(transport: transport)

    let error = await captureError { _ = try await client.getProject(dealId: "") }

    guard case .invalidRequest? = error as? StationError else {
      return XCTFail("expected invalidRequest, got \(String(describing: error))")
    }
    XCTAssertEqual(transport.requests.count, 0)
  }

  func testVerdictPackagesAndDecisionsDecode() async throws {
    let transport = StubTransport([
      .respond(.json(200, try Fixtures.verdict())),
      .respond(.json(200, Fixtures.packageSummaries)),
      .respond(.json(200, Fixtures.decisions)),
      .respond(.json(201, Fixtures.decision)),
      .respond(.problem(404, code: "verdict_not_ready")),
    ])
    let client = try makeClient(transport: transport)

    let verdict = try await client.getVerdict(packageId: Fixtures.packageId)
    let packages = try await client.listPackages(dealId: "4821")
    let decisions = try await client.listModelingDecisions(packageId: Fixtures.packageId)
    let input = ModelingDecisionInput(
      element: "Floor 1 kitchen north wall", decision: "Wall length taken from tape distance A",
      sources: [DecisionSource(path: "Field Measurements/field-controls.json", controlId: "dist-a")]
    )
    let created = try await client.createModelingDecision(packageId: Fixtures.packageId, input)
    let notReady = await captureError {
      _ = try await client.getVerdict(packageId: Fixtures.packageId)
    }

    XCTAssertEqual(verdict.outcome, .limited)
    XCTAssertEqual(packages.first?.verdict?.outcome, .limited)
    XCTAssertEqual(decisions.first?.decidedBy.name, "BIM Operator")
    XCTAssertEqual(created.sources.first?.controlId, "dist-a")
    XCTAssertEqual((notReady as? StationError)?.problem?.code, "verdict_not_ready")
    let body = try XCTUnwrap(transport.requests[3].httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(Set(json.keys), ["element", "decision", "sources"])
  }

  // MARK: - configuration

  func testStationURLMustBeHTTPSExceptLocalhost() throws {
    for accepted in [
      "https://station.example.com", "https://station.example.com/", "http://localhost:8080",
      "http://127.0.0.1:8080", "HTTPS://Station.Example.com",
    ] {
      XCTAssertNoThrow(try StationClientConfiguration(stationURL: URL(string: accepted)!), accepted)
    }
    for refused in [
      "http://station.example.com", "http://10.0.0.5:8080", "ftp://station.example.com",
      "https://" + ["user", "pw"].joined(separator: ":") + "@station.example.com",
      "https://station.example.com/?x=1",
      "https://station.example.com/#frag", "file:///tmp/station", "station.example.com",
    ] {
      XCTAssertThrowsError(
        try StationClientConfiguration(stationURL: URL(string: refused)!), refused)
    }
  }

  func testStationURLWithPathPrefixAndTrailingSlash() async throws {
    let transport = StubTransport([.respond(.json(200, Fixtures.health))])
    let client = try makeClient(transport: transport, stationURL: "https://gateway.test/station/")

    _ = try await client.getHealth()

    XCTAssertEqual(
      transport.requests.first?.url?.absoluteString, "https://gateway.test/station/v1/health")
  }

  // MARK: - helpers

  static func sessionRequest() -> UploadSessionRequest {
    UploadSessionRequest(
      packageId: LowercaseUUID(Fixtures.packageId), visitId: LowercaseUUID(Fixtures.visitId),
      dealId: "4821", revision: 1,
      files: [
        UploadFileDeclaration(
          path: "Field Measurements/field-controls.json", role: .fieldControls,
          sha256: Fixtures.sha, bytes: 512),
        UploadFileDeclaration(
          path: "Original Exports/floor-1/\(Fixtures.captureId.uuidString.lowercased())/plan.dxf",
          role: .planDXF, captureId: LowercaseUUID(Fixtures.captureId), areaKey: "floor-1",
          sha256: Fixtures.sha, bytes: 2048),
      ])
  }
}
