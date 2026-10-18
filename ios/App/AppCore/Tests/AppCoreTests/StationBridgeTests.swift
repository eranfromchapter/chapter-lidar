import CaptureContract
import Foundation
import PackageCore
import XCTest

@testable import AppCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The StationClient -> PackageKit bridge, through the real StationClient.
final class StationBridgeTests: XCTestCase {
  /// Answers every request with one canned response.
  final class CannedTransport: StationAPITransport, @unchecked Sendable {
    let status: Int
    let body: String
    init(status: Int, body: String) {
      self.status = status
      self.body = body
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      (
        Data(body.utf8),
        HTTPURLResponse(
          url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/problem+json"])!
      )
    }
  }

  final class OfflineTransport: StationAPITransport, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      throw URLError(.notConnectedToInternet)
    }
  }

  private func service(_ transport: any StationAPITransport) throws -> StationUploadService {
    StationUploadService(
      client: StationAPI(
        configuration: try .init(stationURL: URL(string: "https://station.hellochapter.test")!),
        tokenProvider: UITestTokenProvider(), transport: transport))
  }

  private func problem(_ status: Int, _ code: String) -> String {
    #"{"type":"about:blank","title":"\#(code) title","status":\#(status),"code":"\#(code)","detail":"d"}"#
  }

  func testProblemAnswersBecomeStationProblemsWithTheirCode() async throws {
    for (status, code) in [(409, "upload_target_changed"), (409, "package_sealed"), (422, "x")] {
      let service = try service(CannedTransport(status: status, body: problem(status, code)))
      do {
        _ = try await service.completeFile(packageId: UUID(), path: "a")
        XCTFail("expected a problem")
      } catch let problem as StationProblem {
        XCTAssertEqual(problem.status, status)
        XCTAssertEqual(problem.code, code)
        XCTAssertEqual(problem.title, "\(code) title")
        XCTAssertEqual(problem.detail, "d")
      }
    }
  }

  func testErrorWithoutProblemBodyGetsAnHTTPCode() {
    let mapped = StationBridge.map(StationAPIError.server(status: 503, problem: nil))
    XCTAssertEqual(mapped as? StationProblem, StationProblem(status: 503, code: "http_503"))
  }

  func testOfflineStaysTransient() async throws {
    let service = try service(OfflineTransport())
    do {
      _ = try await service.seal(packageId: UUID(), manifestJSON: Data("{}".utf8))
      XCTFail("expected offline")
    } catch {
      XCTAssertFalse(error is StationProblem, "offline must not look like a station refusal")
      XCTAssertEqual(UploadErrorKind.of(error), .transient)
    }
  }

  func testUnauthorizedNeedsSignIn() async throws {
    let service = try service(CannedTransport(status: 401, body: problem(401, "unauthorized")))
    do {
      _ = try await service.completeFile(packageId: UUID(), path: "a")
      XCTFail("expected 401")
    } catch {
      XCTAssertEqual(UploadErrorKind.of(error), .signIn)
    }
    XCTAssertEqual(UploadErrorKind.of(SignInRequired()), .signIn)
  }

  func testTargetsAreCarriedOverExactly() throws {
    let url = URL(string: "https://acct.blob.core.windows.net/c/p/file-0?sv=2024-01-01&se=x&sp=cw")!
    let target = StationBridge.convert(
      StationAPIUploadTarget(
        url: url, headers: ["x-ms-blob-type": "BlockBlob"],
        expiresAt: UTCTimestamp(secondsSince1970: 1_800_000_000)))
    XCTAssertEqual(target.url, url.absoluteString)
    XCTAssertEqual(target.method, "PUT")
    XCTAssertEqual(target.headers, ["x-ms-blob-type": "BlockBlob"])
    XCTAssertFalse(String(describing: target).contains("sv="), "the SAS URL is never printed")
  }

  func testRequestConversionKeepsEveryField() {
    let request = UploadSessionRequest(
      packageId: LowercaseUUID(), visitId: LowercaseUUID(), dealId: "D-1", revision: 2,
      supersedesPackageId: LowercaseUUID(),
      files: [
        UploadFileDeclaration(
          path: "p", role: .photo, captureId: LowercaseUUID(), areaKey: "floor-1",
          sha256: String(repeating: "a", count: 64), bytes: 9)
      ])
    let converted = StationBridge.convert(request)
    XCTAssertEqual(converted.packageId, request.packageId)
    XCTAssertEqual(converted.supersedesPackageId, request.supersedesPackageId)
    XCTAssertEqual(converted.revision, 2)
    XCTAssertEqual(converted.files.first?.path, "p")
    XCTAssertEqual(converted.files.first?.areaKey, "floor-1")
    XCTAssertEqual(converted.files.first?.bytes, 9)
  }

  func testFatalErrorsStopTheUpload() {
    XCTAssertEqual(
      UploadErrorKind.of(PackageUploadError.localFileChanged(path: "x")),
      .fatal("x changed on the phone after sealing. It was not uploaded."))
    XCTAssertEqual(UploadErrorKind.of(BlobTransportError.network("lost")), .transient)
    XCTAssertEqual(UploadErrorKind.of(BlobTransportError.http(status: 503, code: nil)), .transient)
    if case .fatal = UploadErrorKind.of(StationProblem(status: 422, code: "bad")) {
    } else {
      XCTFail("422 is fatal")
    }
  }
}

final class SummaryTests: XCTestCase {
  func testByteText() {
    XCTAssertEqual(ByteText.format(312_000_000), "312 MB")
    XCTAssertEqual(ByteText.format(1_500), "1.5 KB")
    XCTAssertEqual(ByteText.format(12), "12 bytes")
    XCTAssertEqual(ByteText.progress(512_000_000, of: 768_000_000), "512 of 768 MB")
  }

  func testStationStepsNeverClaimHubPublication() {
    for stage in StationPackageStage.allCases {
      let steps = StationSteps.make(registered: true, stage: stage)
      XCTAssertEqual(steps.steps.map(\.title), ["Registered", "Checks queued", "Verdict", "Published to the HUB"])
      XCTAssertFalse(steps.steps[3].done)
    }
    XCTAssertEqual(
      StationSteps.make(registered: false, stage: nil).steps.map(\.done), [false, false, false, false])
    XCTAssertEqual(
      StationSteps.make(registered: true, stage: .verdictReady).steps.map(\.done),
      [true, true, true, false])
  }

  func testCategoriesFollowTheDesignRows() {
    XCTAssertEqual(UploadProgressSummary.Category.of(.photo), .sitePhotos)
    XCTAssertEqual(UploadProgressSummary.Category.of(.meshMTL), .meshes)
    XCTAssertEqual(UploadProgressSummary.Category.of(.rawDepth), .pointClouds)
    XCTAssertEqual(UploadProgressSummary.Category.of(.planDXF), .plansAndReports)
    XCTAssertEqual(UploadProgressSummary.Status.verified.text, "\u{25CF} Verified")
  }

  func testVerdictCarriesWordAndShape() {
    XCTAssertEqual(VerdictDisplay(outcome: .limited, summary: "s").title, "\u{25B2} Limited")
    XCTAssertEqual(VerdictDisplay(outcome: .ready, summary: "s").title, "\u{25CF} Ready")
    XCTAssertEqual(VerdictDisplay(outcome: .blocked, summary: "s").title, "\u{25A0} Blocked")
  }

  /// The UI-test stubs exist only in Debug builds of AppCore (`swift test` builds Debug). The
  /// Release side is checked by `swift build -c release` (see ios/App/README.md).
  func testStubsAreDebugOnly() {
    XCTAssertTrue(AppCoreBuild.isDebug)
  }
}
