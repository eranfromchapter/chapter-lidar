import CaptureContract
import Foundation
import PackageCore

/// What the phone last learned from the station about one sealed package (critique R-27,
/// phone-package §9.1): `<packageId>.station-status.json` next to the package folder and its
/// `<packageId>.upload-state.json`. App-private, not part of the package.
///
/// Written only by `UploadCoordinator` and the background refresh (`StationStatusRefresh`), so
/// the screens (Package status, Verdict received) and the Captures home (phone-capture's
/// `CaptureLibrary`, which only reads it) can show the status offline. A Captures home row's
/// outcome is `verdict?.outcome`.
public struct StationStatusCache: Codable, Equatable, Sendable {
  public static let currentFormatVersion = 1

  public var formatVersion: Int
  public var packageId: LowercaseUUID
  public var stage: StationPackageStage
  public var checks: StationPackageInfo.Checks?
  public var publication: StationPackageInfo.Publication?
  public var links: StationPackageInfo.Links?
  /// The current verdict, once the station has one.
  public var verdict: VerdictStatus?
  /// When the phone asked the station.
  public var fetchedAt: UTCTimestamp
  /// When the station registered the package.
  public var createdAt: UTCTimestamp?
  /// The verdict the "Verdict: …" notification was posted for: never more than one per verdict
  /// (phone-package §7).
  public var notifiedVerdictId: LowercaseUUID?

  public init(
    packageId: LowercaseUUID, station: StationPackageInfo, verdict: VerdictStatus?,
    fetchedAt: UTCTimestamp, notifiedVerdictId: LowercaseUUID? = nil
  ) {
    formatVersion = Self.currentFormatVersion
    self.packageId = packageId
    stage = station.stage
    checks = station.checks
    publication = station.publication
    links = station.links
    self.verdict = verdict
    self.fetchedAt = fetchedAt
    createdAt = station.createdAt
    self.notifiedVerdictId = notifiedVerdictId
  }

  /// The station record kept here (nil only for a cache written without `createdAt`).
  public var station: StationPackageInfo? {
    guard let createdAt else { return nil }
    return StationPackageInfo(
      stage: stage, createdAt: createdAt, checks: checks, publication: publication, links: links,
      verdictId: verdict?.verdictId)
  }

  /// A verdict is known and its notification has not been posted yet.
  public var needsVerdictNotification: Bool {
    guard let verdict else { return false }
    return notifiedVerdictId != verdict.verdictId
  }

  /// Nothing more to learn: a verdict and a publication the station finished (published or
  /// failed).
  public var isSettled: Bool {
    verdict != nil && publication?.status.isFinal == true
  }

  /// Still asked about at `now` (the background refresh): no verdict yet, or a publication not
  /// final yet within `StationStatusRefresh.publicationFollowLimit` of the verdict.
  public func isFollowed(at now: Date) -> Bool {
    StationStatusRefresh.isFollowed(verdict: verdict, publication: publication, at: now)
  }
}

public enum StationStatusCacheError: Error, Equatable, Sendable, CustomStringConvertible {
  case unreadable(String)
  case unwritable(String)

  public var description: String {
    switch self {
    case .unreadable(let reason): return "cannot read the station status: \(reason)"
    case .unwritable(let reason): return "cannot save the station status: \(reason)"
    }
  }
}

/// Reads and writes `<packageId>.station-status.json`, with the folder rules and file protection
/// of `UploadStateStore`: atomic writes, owner only (0600) and, on iOS, protected until first
/// unlock (the background refresh runs while the phone is locked).
public struct StationStatusStore: Sendable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// The store of the package folder `root` (`packages/<packageId>/`).
  public init(packageRoot root: URL) {
    self.init(url: Self.defaultURL(forPackageAt: root))
  }

  /// `<package folder name>.station-status.json` next to the package folder.
  public static func defaultURL(forPackageAt root: URL) -> URL {
    root.deletingLastPathComponent()
      .appendingPathComponent("\(root.lastPathComponent).station-status.json")
  }

  /// Nil when the phone has not heard from the station about the package yet.
  public func load() throws -> StationStatusCache? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      let cache = try CaptureContractJSON.makeDecoder().decode(
        StationStatusCache.self, from: Data(contentsOf: url))
      guard cache.formatVersion == StationStatusCache.currentFormatVersion else {
        throw StationStatusCacheError.unreadable("unknown format version \(cache.formatVersion)")
      }
      return cache
    } catch let error as StationStatusCacheError {
      throw error
    } catch {
      throw StationStatusCacheError.unreadable(String(describing: error))
    }
  }

  public func save(_ cache: StationStatusCache) throws {
    do {
      let data = try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(cache)
      #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      #else
        try data.write(to: url, options: .atomic)
      #endif
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
    } catch {
      throw StationStatusCacheError.unwritable(String(describing: error))
    }
  }

  /// Writes what the station said now, keeping which verdict was notified. Returns the cache.
  @discardableResult
  public func record(
    packageId: LowercaseUUID, station: StationPackageInfo, verdict: VerdictStatus?, at date: Date
  ) throws -> StationStatusCache {
    let previous = try? load()
    let cache = StationStatusCache(
      packageId: packageId, station: station, verdict: verdict ?? previous?.verdict,
      fetchedAt: UTCTimestamp(date), notifiedVerdictId: previous?.notifiedVerdictId)
    try save(cache)
    return cache
  }

  /// Notes that the notification of `verdictId` was posted.
  public func markNotified(_ verdictId: LowercaseUUID) throws {
    guard var cache = try load() else { return }
    cache.notifiedVerdictId = verdictId
    try save(cache)
  }
}

/// The local notification "verdict received" (phone-package §7, addendum C10): title
/// `Verdict: {Word}`, body `{project title} · revision {n}. Details: spatial report in the
/// HUB.`, grouped by package; a tap opens Verdict received for that package.
public struct VerdictNotification: Equatable, Sendable {
  /// `userInfo` key of the package id.
  public static let packageIdKey = "packageId"
  /// Category of the notification (no actions).
  public static let category = "verdict"

  public var packageId: LowercaseUUID
  public var verdictId: LowercaseUUID
  public var title: String
  public var body: String

  public init(
    packageId: LowercaseUUID, verdict: VerdictStatus, projectTitle: String, revision: Int
  ) {
    self.packageId = packageId
    verdictId = verdict.verdictId
    title = "Verdict: \(verdict.word)"
    body = "\(projectTitle) \u{00B7} revision \(revision). Details: spatial report in the HUB."
  }

  /// One thread per package.
  public var threadIdentifier: String { packageId.rawValue }
  /// Posting the same verdict twice replaces the first (never two banners for one verdict).
  public var requestIdentifier: String { "verdict-\(verdictId.rawValue)" }
  public var userInfo: [String: String] { [Self.packageIdKey: packageId.rawValue] }

  /// The package a tapped notification is about.
  public static func packageId(from userInfo: [AnyHashable: Any]) -> LowercaseUUID? {
    (userInfo[packageIdKey] as? String).flatMap(LowercaseUUID.init(rawValue:))
  }
}

/// The background refresh of phone-package §7 (`BGAppRefreshTask`
/// `com.hellochapter.capture.verdict-refresh`): for every package on the phone the station
/// confirmed and still followed (no verdict yet, or a verdict whose publication is not final and
/// at most `publicationFollowLimit` old), ask the station, update the cache and collect the
/// verdict notifications still to post.
public enum StationStatusRefresh {
  /// The task identifier, registered at launch and listed in Info.plist
  /// (`BGTaskSchedulerPermittedIdentifiers`).
  public static let taskIdentifier = "com.hellochapter.capture.verdict-refresh"
  /// Earliest start of the next refresh.
  public static let interval: TimeInterval = 15 * 60
  /// How long after the verdict a publication that is not final is still followed (§7: "at
  /// most 30 minutes after the verdict"), in the background and by `UploadCoordinator`.
  public static let publicationFollowLimit: TimeInterval = 30 * 60

  /// The station still has something to tell about a package at `now`: its verdict, or the
  /// publication of a verdict at most `publicationFollowLimit` old (by the station's
  /// `evaluatedAt`). A publication that never ends (the publish worker or the HUB is down, or a
  /// station that reports none) is not asked about for ever; the status the phone last saw stays
  /// in the cache.
  public static func isFollowed(
    verdict: VerdictStatus?, publication: StationPackageInfo.Publication?, at now: Date
  ) -> Bool {
    guard let verdict else { return true }
    guard publication?.status.isFinal != true else { return false }
    return now.timeIntervalSince(verdict.evaluatedAt.date) < publicationFollowLimit
  }

  public struct Item: Sendable {
    public let package: SealedPackage
    public let store: StationStatusStore
    public let cache: StationStatusCache?
    public let summary: SealedPackageSummary
  }

  public struct Outcome: Sendable {
    /// Notifications of verdicts not notified yet (post them, then `markNotified`).
    public var notifications: [VerdictNotification] = []
    /// Some package is still followed: schedule the next refresh.
    public var stillFollowing = false
    /// Packages the station could not be asked about (offline, error); kept as they were.
    public var failed = 0
  }

  /// Sealed packages on the phone that the station confirmed (their upload state says so) and
  /// that are still followed at `now` (`isFollowed`); superseded packages are left out.
  public static func followed(visitsRoot: URL, now: Date = Date()) -> [Item] {
    SealedPackageFolders.all(visitsRoot: visitsRoot).compactMap { folder, package in
      let state = try? UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: folder))
        .load()
      guard let state, state.isConfirmedByStation, state.supersededBy == nil else { return nil }
      let store = StationStatusStore(packageRoot: folder)
      let cache = try? store.load()
      guard cache?.isFollowed(at: now) != false else { return nil }
      return Item(
        package: package, store: store, cache: cache, summary: SealedPackageSummary.make(package))
    }
  }

  /// Asks the station about each item (`getPackage`, and `getVerdict` when a new verdict is
  /// ready), writes the caches and returns the notifications to post. Never throws: a package
  /// the station cannot be asked about now is tried at the next refresh.
  public static func refresh(
    _ items: [Item], source: any PackageStatusSource, now: @Sendable () -> Date = { Date() }
  ) async -> Outcome {
    var outcome = Outcome()
    for item in items {
      if Task.isCancelled { break }
      do {
        let station = try await source.package(packageId: item.package.packageId.uuid)
        var verdict: VerdictStatus?
        if station.stage == .verdictReady, let id = station.verdictId,
          item.cache?.verdict?.verdictId != id
        {
          verdict = try await source.verdict(packageId: item.package.packageId.uuid)
        }
        let cache = try item.store.record(
          packageId: item.package.packageId, station: station, verdict: verdict, at: now())
        if cache.needsVerdictNotification, let known = cache.verdict {
          outcome.notifications.append(
            VerdictNotification(
              packageId: item.package.packageId, verdict: known,
              projectTitle: item.summary.projectTitle, revision: item.summary.revision))
        }
        if cache.isFollowed(at: now()) { outcome.stillFollowing = true }
      } catch {
        outcome.failed += 1
        outcome.stillFollowing = true
      }
    }
    return outcome
  }
}

/// The sealed package folders of every visit workspace under `visitsRoot`.
enum SealedPackageFolders {
  static func all(visitsRoot: URL) -> [(URL, SealedPackage)] {
    let fileManager = FileManager.default
    guard
      let workspaces = try? fileManager.contentsOfDirectory(
        at: visitsRoot, includingPropertiesForKeys: nil)
    else { return [] }
    var result: [(URL, SealedPackage)] = []
    for workspace in workspaces.sorted(by: { $0.path < $1.path }) {
      let packages = VisitWorkspace(root: workspace).packagesRoot
      guard let folders = try? fileManager.contentsOfDirectory(at: packages, includingPropertiesForKeys: nil)
      else { continue }
      for folder in folders.sorted(by: { $0.path < $1.path })
      where !folder.lastPathComponent.hasPrefix(".") {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
          isDirectory.boolValue, let package = try? SealedPackage.open(at: folder)
        else { continue }
        result.append((folder, package))
      }
    }
    return result
  }
}
