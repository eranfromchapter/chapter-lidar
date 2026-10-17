import CaptureContract
import Foundation
import PackageCore
import PackageTransport
import XCTest

/// F6.AC4: end to end against the local station, a fixture package uploads, registers and reaches
/// checks-queued.
///
///   station/api/scripts/local-up.sh
///   STATION_URL=http://localhost:8080 swift test --package-path ios/Packages/PackageKit --filter E2EUploadTests
///
/// Skipped unless STATION_URL is set. The token comes from the local test sign-in service at
/// http://localhost:8090 (STATION_DEV_IDP_URL overrides). Each run uploads the two-floor fixture
/// with a fresh packageId and visitId (the station allows one package per visit and revision).
final class E2EUploadTests: XCTestCase {
  private var folder: TemporaryFolder?

  override func tearDown() {
    folder?.remove()
  }

  func testFixturePackageUploadsRegistersAndReachesChecksQueued() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let stationText = environment["STATION_URL"], !stationText.isEmpty else {
      throw XCTSkip("STATION_URL is not set; start the local station and set it to run this test")
    }
    let stationBase = try XCTUnwrap(URL(string: stationText), "STATION_URL is not a URL")
    let apiBase = stationBase.path.hasSuffix("/v1") ? stationBase : stationBase.appendingPathComponent("v1")
    let idpText = environment["STATION_DEV_IDP_URL"].flatMap { $0.isEmpty ? nil : $0 } ?? "http://localhost:8090"
    let idp = try XCTUnwrap(URL(string: idpText), "STATION_DEV_IDP_URL is not a URL")

    let token = try await DevSignIn.accessToken(from: idp)
    let folder = try TemporaryFolder()
    self.folder = folder

    // The originals of a new visit: the fixture's files with its visitId replaced in the JSON
    // documents that carry it (test input preparation; packaging copies these bytes unchanged).
    let fixture = try FixturePackage("two-floor-house")
    let visitId = LowercaseUUID()
    let packageId = LowercaseUUID()
    let sources = folder.url.appendingPathComponent("sources", isDirectory: true)
    try FileManager.default.copyItem(at: fixture.root, to: sources)
    func source(_ path: String) -> URL {
      var url = sources
      for segment in path.split(separator: "/") { url.appendPathComponent(String(segment)) }
      return url
    }
    for path in fixture.filePaths() where path.hasSuffix(".json") {
      let url = source(path)
      let text = try String(contentsOf: url, encoding: .utf8)
      try text.replacingOccurrences(of: fixture.visitId.rawValue, with: visitId.rawValue)
        .write(to: url, atomically: true, encoding: .utf8)
    }
    let record = try JSON.parse(contentsOf: source("Source Register/\(fixture.visitId.rawValue)/capture-record.json"))
    let dealId = try XCTUnwrap(record["hub"]?["dealId"]?.string)
    XCTAssertEqual(dealId, "fixture-deal-0001")

    let draft = try FixtureDraft.make(
      fixture, visitId: visitId, packageId: packageId, generatorPrefix: "chapter-capture-ios/",
      source: source)
    let sealed = try PackageAssembler().assemble(
      draft, at: folder.url.appendingPathComponent("package", isDirectory: true))
    XCTAssertEqual(try Fixtures.manifestValidator().validate(jsonData: sealed.manifestData), [])

    let uploader = try PackageUploader(
      package: sealed, dealId: dealId,
      service: HTTPUploadService(baseURL: apiBase, accessToken: token),
      transport: HTTPBlobTransport(),
      store: UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: sealed.root)))
    let result = try await uploader.run()

    XCTAssertEqual(result.packageId, packageId)
    XCTAssertEqual(result.visitId, visitId)
    // checks_queued is the status sealing sets; a running checks worker may already have moved it on.
    XCTAssertTrue(
      [.checksQueued, .checking, .verdictReady].contains(result.status),
      "status \(result.status.rawValue)")
    XCTAssertEqual(result.files.count, sealed.manifest.files.count)
    XCTAssertTrue(result.files.allSatisfy { $0.status == .verified })
    XCTAssertEqual(result.manifest, sealed.manifest)
    let state = await uploader.currentState
    XCTAssertTrue(state.isConfirmedByStation)
    XCTAssertEqual(sealed.verify(), [])
  }
}
