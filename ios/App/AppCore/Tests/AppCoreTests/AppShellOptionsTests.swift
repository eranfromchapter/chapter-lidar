import CaptureContract
import CaptureCore
import Foundation
import StationClient
import XCTest

@testable import AppCore

/// The app shell's small pieces: the HUB project listing of New capture (offline copy, phone-
/// capture §3.2.1) and the UI-test launch options (critique R-24, phone-capture §10.3).
final class AppShellOptionsTests: XCTestCase {
  // MARK: StationProjectProvider.listing()

  private final class Source: ProjectSource, @unchecked Sendable {
    var offline = false
    func listProjects(query: String?, limit: Int?) async throws -> [HubProject] {
      if offline { throw StationError.offline }
      return [
        HubProject(
          dealId: "4821", projectName: "Valley Street",
          address: .init(formatted: "618 Valley Street, Springfield, NJ 07081"))
      ]
    }
  }

  func testListingOnlineThenTheSavedCopyOffline() async throws {
    let cache = try Fixtures.temporaryDirectory()
    defer { Fixtures.removeTemporaryDirectory(cache) }
    let source = Source()
    let fetched = Date(timeIntervalSince1970: 1_800_000_000)
    let provider: any HubProjectProvider = StationProjectProvider(
      store: ProjectStore(source: source, cacheDirectory: cache, now: { fetched }))

    let online = try await provider.listing()
    XCTAssertFalse(online.isOfflineCopy)
    XCTAssertEqual(online.fetchedAt, fetched)
    XCTAssertEqual(online.projects.map(\.dealId), ["4821"])
    XCTAssertEqual(online.projects.first?.title, "Valley Street")

    source.offline = true
    let offline = try await provider.listing()
    XCTAssertTrue(offline.isOfflineCopy, "the copy saved on this phone")
    XCTAssertEqual(offline.fetchedAt, fetched)
    XCTAssertEqual(offline.projects.count, 1)
  }

  func testListingOfflineWithNothingSaved() async throws {
    let cache = try Fixtures.temporaryDirectory()
    defer { Fixtures.removeTemporaryDirectory(cache) }
    let source = Source()
    source.offline = true
    let provider: any HubProjectProvider = StationProjectProvider(
      store: ProjectStore(source: source, cacheDirectory: cache))
    do {
      _ = try await provider.listing()
      XCTFail("expected offlineWithoutSavedList")
    } catch {
      XCTAssertEqual(error as? HubProjectListingError, .offlineWithoutSavedList)
    }
  }

  // MARK: UITestLaunchOptions

  func testUITestLaunchOptions() {
    let defaults = UITestLaunchOptions(arguments: ["-ChapterUITestReplay", "box-room"])
    XCTAssertEqual(defaults, UITestLaunchOptions())
    XCTAssertEqual(defaults.compass, "verified")
    XCTAssertNil(defaults.visitsRoot)
    XCTAssertFalse(defaults.projectsOffline)
    XCTAssertNil(defaults.trackingLost)
    XCTAssertEqual(defaults.scanStep, 0.5)
    XCTAssertFalse(defaults.seedsV1Visits)
    XCTAssertFalse(defaults.notifiesDuringScan)

    let options = UITestLaunchOptions(arguments: [
      "-ChapterUITestReplay", "box-room", "-ChapterUITestCompass", "none",
      "-ChapterUITestVisitsRoot", "stable-1", "-ChapterUITestOffline",
      "-ChapterUITestTrackingLost", "2", "4", "-ChapterUITestScanStep", "1.5",
      "-ChapterUITestV1Visits", "-ChapterUITestNotifyDuringScan",
    ])
    XCTAssertEqual(options.compass, "none")
    XCTAssertEqual(options.visitsRoot, "stable-1")
    XCTAssertEqual(options.visitsFolderName(), "UITestVisits-stable-1")
    XCTAssertTrue(options.projectsOffline)
    XCTAssertEqual(options.trackingLost, 2...4)
    XCTAssertEqual(options.scanStep, 1.5)
    XCTAssertTrue(options.seedsV1Visits)
    XCTAssertTrue(options.notifiesDuringScan)

    // Unknown or unsafe values fall back.
    let odd = UITestLaunchOptions(arguments: [
      "-ChapterUITestCompass", "north", "-ChapterUITestVisitsRoot", "../etc",
      "-ChapterUITestTrackingLost", "4", "2", "-ChapterUITestScanStep", "-1",
    ])
    XCTAssertEqual(odd.compass, "verified")
    XCTAssertNil(odd.visitsRoot)
    XCTAssertNil(odd.trackingLost)
    XCTAssertEqual(odd.scanStep, 0.5)
    let fresh = UUID()
    XCTAssertEqual(odd.visitsFolderName(fresh: fresh), "UITestVisits-\(fresh.uuidString)")
  }
}
