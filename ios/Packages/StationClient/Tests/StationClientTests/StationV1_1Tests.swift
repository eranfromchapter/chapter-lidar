import CaptureContract
import Foundation
import StationClient
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The station 1.1.0 additions the phone reads and sends (phone-package §9.3, §10.2): check run,
/// publication, links and the next-revision notice on a package; `createdAt` and carry-over in
/// the session answer. All optional, so a station before 1.1.0 still decodes.
final class StationV1_1Tests: XCTestCase {
  func testPackageCarriesChecksPublicationLinksAndTheNextRevision() async throws {
    let transport = StubTransport([.respond(.json(200, Fixtures.packageV1_1))])
    let package = try await makeClient(transport: transport).getPackage(packageId: Fixtures.packageId)

    XCTAssertEqual(
      package.checks,
      CheckRunSummary(
        status: .completed, startedAt: UTCTimestamp(rawValue: "2026-10-17T14:06:00Z"),
        finishedAt: UTCTimestamp(rawValue: "2026-10-17T14:09:00Z"), rules: 13))
    XCTAssertEqual(package.publication?.status, .published)
    XCTAssertEqual(package.publication?.publishedAt?.rawValue, "2026-10-17T14:11:00Z")
    XCTAssertEqual(package.publication?.hubFolder, "Capture/\(Fixtures.visitIdText)/r2")
    XCTAssertEqual(
      package.links?.review.absoluteString, "https://review.test/packages/\(Fixtures.packageIdText)")
    XCTAssertEqual(package.links?.hub?.absoluteString, "https://hub.test/deals/4821")
    XCTAssertEqual(
      package.files.first?.carriedOverFrom?.rawValue, "44444444-5555-4666-8777-888888888888")

    let notice = try XCTUnwrap(package.nextRevision)
    XCTAssertEqual(notice.revision, 2)
    XCTAssertEqual(notice.updatedBy, "Dana Ruiz")
    XCTAssertEqual(notice.changes.map(\.subject), [.capture, .fieldControl])
    XCTAssertEqual(notice.changes[1].detail, "Field control · 2,490 mm · 8' 2\"")
    XCTAssertEqual(notice.changes[1].method, .tape)
  }

  func testAnOlderStationsPackageDecodesWithoutTheNewFields() async throws {
    let transport = StubTransport([
      .respond(.json(200, Fixtures.package)), .respond(.json(200, Fixtures.packageSummaries)),
      .respond(.json(201, Fixtures.uploadSession)),
    ])
    let client = try makeClient(transport: transport)
    let package = try await client.getPackage(packageId: Fixtures.packageId)
    XCTAssertNil(package.checks)
    XCTAssertNil(package.publication)
    XCTAssertNil(package.links)
    XCTAssertNil(package.nextRevision)
    let summaries = try await client.listPackages(dealId: "4821")
    let summary = try XCTUnwrap(summaries.first)
    XCTAssertNil(summary.checks)
    XCTAssertNil(summary.publication)
    XCTAssertNil(summary.links)
    let session = try await client.createUploadSession(
      UploadSessionRequest(
        packageId: .init(Fixtures.packageId), visitId: .init(Fixtures.visitId), dealId: "4821",
        revision: 1, files: []))
    XCTAssertNil(session.createdAt)
    XCTAssertTrue(session.files.allSatisfy { $0.carriedOverFrom == nil })
  }

  func testTheSessionAnswerGivesRegistrationTimeAndCarriedOverFiles() async throws {
    let transport = StubTransport([.respond(.json(200, Fixtures.uploadSessionV1_1))])
    let session = try await makeClient(transport: transport).createUploadSession(
      UploadSessionRequest(
        packageId: .init(Fixtures.packageId), visitId: .init(Fixtures.visitId), dealId: "4821",
        revision: 2, supersedesPackageId: LowercaseUUID(), files: []))
    XCTAssertEqual(session.createdAt?.rawValue, "2026-10-17T14:00:00Z")
    XCTAssertEqual(session.files.first?.status, .verified)
    XCTAssertNil(session.files.first?.upload)
    XCTAssertEqual(
      session.files.first?.carriedOverFrom?.rawValue, "44444444-5555-4666-8777-888888888888")
  }

  func testTheNextRevisionNoticeIsPutAsTheContractBody() async throws {
    let transport = StubTransport([.respond(.json(200, Fixtures.nextRevisionNotice))])
    let stored = try await makeClient(transport: transport).putNextRevisionNotice(
      packageId: Fixtures.packageId, Fixtures.nextRevisionNoticeInput)

    let request = try XCTUnwrap(transport.requests.first)
    XCTAssertEqual(request.httpMethod, "PUT")
    XCTAssertEqual(
      request.url?.absoluteString,
      "https://station.test/v1/packages/\(Fixtures.packageIdText)/next-revision")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(Set(json.keys), ["revision", "updatedAt", "changes"], "updatedBy is the station's")
    XCTAssertEqual(json["updatedAt"] as? String, "2026-10-18T09:30:00Z")
    let changes = try XCTUnwrap(json["changes"] as? [[String: Any]])
    XCTAssertEqual(
      changes.first?["answersNextAction"] as? String,
      "Scan or measure Primary closet on the next visit if it is in scope.")
    XCTAssertNil(changes.first?["method"], "omitted, never null")
    XCTAssertEqual(changes.last?["subject"] as? String, "field_control")
    XCTAssertEqual(changes.last?["method"] as? String, "tape")
    XCTAssertEqual(stored.updatedBy, "Dana Ruiz")
  }

  func testANoticeTheStationRefusesIsThrown() async throws {
    let transport = StubTransport([.respond(.problem(409, code: "revision_exists"))])
    let client = try makeClient(transport: transport)
    let error = await captureError {
      try await client.putNextRevisionNotice(
        packageId: Fixtures.packageId, Fixtures.nextRevisionNoticeInput)
    }
    guard case .conflict(let problem)? = error as? StationError else {
      return XCTFail("expected 409, got \(String(describing: error))")
    }
    XCTAssertEqual(problem?.code, "revision_exists")
  }
}
