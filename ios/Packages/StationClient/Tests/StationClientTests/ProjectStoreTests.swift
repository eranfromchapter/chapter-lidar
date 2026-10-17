import CaptureContract
import Foundation
import StationClient
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class ProjectStoreTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ProjectStoreTests-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  /// `ProjectSource` that answers each call from a list of results.
  final class StubSource: ProjectSource, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<[HubProject], Error>]
    private(set) var limits: [Int?] = []

    init(_ results: [Result<[HubProject], Error>]) {
      self.results = results
    }

    func listProjects(query: String?, limit: Int?) async throws -> [HubProject] {
      let next: Result<[HubProject], Error> = lock.withLock {
        limits.append(limit)
        return results.isEmpty
          ? .failure(StationError.unexpectedStatus(599)) : results.removeFirst()
      }
      return try next.get()
    }
  }

  static let kitchen = HubProject(
    dealId: "4821", projectName: "Kitchen and bath",
    address: .init(formatted: "345 7th Ave, New York, NY 10001"))
  static let miami = HubProject(
    dealId: "4822", address: .init(formatted: "252 NW 29th St, Miami, FL 33127"))
  static let blank = HubProject(dealId: "4823", address: .init(formatted: "   "))

  static let firstFetch = Date(timeIntervalSince1970: 1_792_245_600)  // 2026-10-17T14:00:00Z
  static let secondFetch = Date(timeIntervalSince1970: 1_792_249_200)

  private func store(_ source: any ProjectSource, at date: Date = firstFetch, limit: Int? = nil)
    -> ProjectStore
  {
    ProjectStore(source: source, cacheDirectory: directory, limit: limit, now: { date })
  }

  private var cacheFile: URL {
    directory.appendingPathComponent(ProjectStore.cacheFileName)
  }

  // MARK: - online

  func testOnlineReturnsStationListAndSavesIt() async throws {
    let source = StubSource([.success([Self.kitchen, Self.blank, Self.miami])])

    let list = try await store(source, limit: 100).projects()

    XCTAssertEqual(list.projects, [Self.kitchen, Self.miami], "only projects with an address")
    XCTAssertFalse(list.isStale)
    XCTAssertFalse(list.cacheSaveFailed)
    XCTAssertEqual(list.fetchedAt, UTCTimestamp(Self.firstFetch))
    XCTAssertEqual(source.limits, [100])
    XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
    let saved = try await store(source).cachedProjects()
    XCTAssertEqual(saved?.projects, [Self.kitchen, Self.miami])
    XCTAssertEqual(saved?.isStale, true)
  }

  func testOnlineEmptyListReplacesTheSavedList() async throws {
    let source = StubSource([
      .success([Self.kitchen]), .success([]), .failure(StationError.offline),
    ])

    _ = try await store(source).projects()
    let live = try await store(source, at: Self.secondFetch).projects()
    let offline = try await store(source).projects()

    XCTAssertEqual(live.projects, [])
    XCTAssertEqual(offline.projects, [])
    XCTAssertEqual(offline.fetchedAt, UTCTimestamp(Self.secondFetch))
  }

  func testCacheSaveFailureStillReturnsLiveListAndSaysSo() async throws {
    // The cache directory path is a regular file, so nothing can be saved under it.
    try FileManager.default.createDirectory(
      at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not a directory".utf8).write(to: directory)
    let source = StubSource([.success([Self.kitchen])])

    let list = try await store(source).projects()

    XCTAssertEqual(list.projects, [Self.kitchen])
    XCTAssertFalse(list.isStale)
    XCTAssertTrue(list.cacheSaveFailed)
  }

  // MARK: - offline

  func testOfflineReturnsLastSavedListMarkedStaleWithItsFetchTime() async throws {
    let source = StubSource([.success([Self.kitchen, Self.miami]), .failure(StationError.offline)])

    _ = try await store(source, at: Self.firstFetch).projects()
    let list = try await store(source, at: Self.secondFetch).projects()

    XCTAssertTrue(list.isStale)
    XCTAssertEqual(list.projects, [Self.kitchen, Self.miami])
    XCTAssertEqual(list.fetchedAt, UTCTimestamp(Self.firstFetch))
  }

  func testOfflineWithoutSavedListThrowsOfflineAndInventsNothing() async throws {
    let source = StubSource([.failure(StationError.offline)])

    let error = await captureError { _ = try await self.store(source).projects() }

    XCTAssertEqual(error as? StationError, .offline)
    XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
  }

  func testOfflineWithUnreadableSavedListThrowsOffline() async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{not json".utf8).write(to: cacheFile)
    let source = StubSource([.failure(StationError.offline)])

    let error = await captureError { _ = try await self.store(source).projects() }

    XCTAssertEqual(error as? StationError, .offline)
  }

  // MARK: - errors that are not offline

  func testAuthAndServerErrorsAreSurfacedNotAnsweredFromCache() async throws {
    let surfaced: [StationError] = [
      .unauthorized(nil), .forbidden(nil), .server(status: 502, problem: nil),
      .invalidResponse("listProjects"),
      .network(code: URLError.Code.serverCertificateUntrusted.rawValue),
    ]
    for expected in surfaced {
      try? FileManager.default.removeItem(at: directory)
      let source = StubSource([.success([Self.kitchen]), .failure(expected)])
      _ = try await store(source).projects()

      let error = await captureError { _ = try await self.store(source).projects() }

      XCTAssertEqual(error as? StationError, expected)
      let saved = try await store(source).cachedProjects()
      XCTAssertEqual(
        saved?.projects, [Self.kitchen], "the saved list is kept for later offline use")
    }
  }

  func testTokenProviderFailureIsSurfaced() async throws {
    try await seedCache()
    let client = try makeClient(
      transport: StubTransport([.respond(.json(200, Fixtures.projects))]),
      tokens: StubTokenProvider(fails: true))

    let error = await captureError { _ = try await self.store(client).projects() }

    XCTAssertTrue(error is StubTokenProvider.Failure, "got \(String(describing: error))")
  }

  // MARK: - with the real client

  func testWithStationClientOfflineFallsBackAndUnauthorizedIsSurfaced() async throws {
    let online = try makeClient(transport: StubTransport([.respond(.json(200, Fixtures.projects))]))
    let first = try await store(online).projects()
    XCTAssertEqual(first.projects.map(\.dealId), ["4821", "4822"])

    let offlineClient = try makeClient(transport: StubTransport([.fail(.notConnectedToInternet)]))
    let stale = try await store(offlineClient, at: Self.secondFetch).projects()
    XCTAssertTrue(stale.isStale)
    XCTAssertEqual(stale.projects, first.projects)
    XCTAssertEqual(stale.fetchedAt, UTCTimestamp(Self.firstFetch))

    let signedOut = try makeClient(
      transport: StubTransport([
        .respond(.problem(401, code: "unauthorized")),
        .respond(.problem(401, code: "unauthorized")),
      ]))
    let error = await captureError { _ = try await self.store(signedOut).projects() }
    XCTAssertEqual((error as? StationError)?.requiresSignIn, true)

    let forbidden = try makeClient(
      transport: StubTransport([.respond(.problem(403, code: "forbidden"))]))
    let forbiddenError = await captureError { _ = try await self.store(forbidden).projects() }
    guard case .forbidden? = forbiddenError as? StationError else {
      return XCTFail("expected forbidden, got \(String(describing: forbiddenError))")
    }
  }

  // MARK: - clearing

  func testClearCacheRemovesTheSavedList() async throws {
    try await seedCache()
    let source = StubSource([.failure(StationError.offline)])
    let projectStore = store(source)

    try await projectStore.clearCache()
    let saved = try await projectStore.cachedProjects()
    let error = await captureError { _ = try await projectStore.projects() }

    XCTAssertNil(saved)
    XCTAssertEqual(error as? StationError, .offline)
  }

  private func seedCache() async throws {
    _ = try await store(StubSource([.success([Self.kitchen])])).projects()
  }
}
