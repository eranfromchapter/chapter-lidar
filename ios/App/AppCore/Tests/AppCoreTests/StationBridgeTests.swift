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
      XCTAssertEqual(UploadErrorKind.of(error), .transient(.offline))
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
      .fatal("x changed on the phone after sealing. It was not uploaded.", path: "x"))
    XCTAssertEqual(UploadErrorKind.of(BlobTransportError.network("lost")), .transient(.offline))
    XCTAssertEqual(
      UploadErrorKind.of(BlobTransportError.http(status: 503, code: nil)),
      .transient(.stationUnavailable))
    if case .fatal = UploadErrorKind.of(StationProblem(status: 422, code: "bad")) {
    } else {
      XCTFail("422 is fatal")
    }
  }

  func testCarriedOverFilesAndTheRegistrationTimeCrossTheBridge() throws {
    let previous = LowercaseUUID()
    let session = try StationBridge.convert(
      StationAPIUploadSession(
        packageId: LowercaseUUID(), visitId: LowercaseUUID(), dealId: "D-1", revision: 2,
        status: .uploading, createdAt: UTCTimestamp(secondsSince1970: 1_800_000_000),
        files: [
          StationAPIUploadSessionFile(path: "a", status: .verified, carriedOverFrom: previous),
          StationAPIUploadSessionFile(path: "b", status: .pending),
        ]))
    XCTAssertEqual(session.createdAt, UTCTimestamp(secondsSince1970: 1_800_000_000))
    XCTAssertEqual(session.files.map(\.carriedOverFrom), [previous, nil])
  }
}

final class SummaryTests: XCTestCase {
  func testByteText() {
    XCTAssertEqual(ByteText.format(312_000_000), "312 MB")
    XCTAssertEqual(ByteText.format(1_500), "1.5 KB")
    XCTAssertEqual(ByteText.format(12), "12 bytes")
    XCTAssertEqual(ByteText.progress(512_000_000, of: 768_000_000), "512 of 768 MB")
    XCTAssertEqual(ByteText.spoken(312_000_000), "312 megabytes")
    XCTAssertEqual(ByteText.spoken(3_200_000), "3.2 megabytes")
  }

  /// The UI-test stubs exist only in Debug builds of AppCore (`swift test` builds Debug). The
  /// Release side is checked by `swift build -c release` (see ios/App/README.md).
  func testStubsAreDebugOnly() {
    XCTAssertTrue(AppCoreBuild.isDebug)
  }
}
