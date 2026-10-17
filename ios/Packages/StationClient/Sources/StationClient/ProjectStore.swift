import CaptureContract
import Foundation

/// Where the project list comes from. `StationClient` conforms; tests inject a stub.
public protocol ProjectSource: Sendable {
  func listProjects(query: String?, limit: Int?) async throws -> [HubProject]
}

extension StationClient: ProjectSource {}

/// The HUB project list shown to the operator.
public struct ProjectList: Hashable, Sendable {
  /// Projects with a confirmed address, in the station's order (most recently updated first).
  public let projects: [HubProject]
  /// When the station returned this list.
  public let fetchedAt: UTCTimestamp
  /// True when the station could not be reached and this is the last saved list.
  public let isStale: Bool
  /// True when the list came live from the station but could not be saved for offline use. The
  /// list itself is correct; the offline copy is older than it.
  public let cacheSaveFailed: Bool

  public init(
    projects: [HubProject], fetchedAt: UTCTimestamp, isStale: Bool, cacheSaveFailed: Bool = false
  ) {
    self.projects = projects
    self.fetchedAt = fetchedAt
    self.isStale = isStale
    self.cacheSaveFailed = cacheSaveFailed
  }
}

/// The project list with an offline copy of the last list the station returned.
///
/// - Online: asks the station, keeps only projects with a usable address, saves the list as JSON
///   in the injected directory (project names and addresses are not secrets) and returns it.
/// - Offline (`StationError.offline`): returns the last saved list, marked stale, with the time
///   the station returned it. No saved list: the offline error is thrown. Projects are never
///   invented.
/// - Every other error (401 sign in again, 403, 5xx, invalid response, token provider errors) is
///   thrown unchanged, never answered from the cache.
public actor ProjectStore {
  /// Name of the cache file inside the cache directory.
  public static let cacheFileName = "station-projects.json"

  private let source: any ProjectSource
  private let cacheDirectory: URL
  private let limit: Int?
  private let now: @Sendable () -> Date

  /// - Parameters:
  ///   - source: the station client.
  ///   - cacheDirectory: directory for the offline copy (for example Application Support). It is
  ///     created when missing.
  ///   - limit: how many projects to ask for (1 to 100); nil uses the station default (25).
  ///   - now: clock, for tests.
  public init(
    source: any ProjectSource, cacheDirectory: URL, limit: Int? = nil,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.source = source
    self.cacheDirectory = cacheDirectory
    self.limit = limit
    self.now = now
  }

  private var cacheURL: URL {
    cacheDirectory.appendingPathComponent(Self.cacheFileName, isDirectory: false)
  }

  /// The current list: live from the station, or the last saved list when offline.
  public func projects() async throws -> ProjectList {
    let live: [HubProject]
    do {
      live = try await source.listProjects(query: nil, limit: limit)
    } catch StationError.offline {
      guard let cached = try? cachedProjects() else {
        throw StationError.offline
      }
      return cached
    }
    let projects = live.filter(\.hasUsableAddress)
    let fetchedAt = UTCTimestamp(now())
    var saveFailed = false
    do {
      try save(CacheFile(fetchedAt: fetchedAt, projects: projects))
    } catch {
      saveFailed = true
    }
    return ProjectList(
      projects: projects, fetchedAt: fetchedAt, isStale: false, cacheSaveFailed: saveFailed)
  }

  /// The last saved list, marked stale, or nil when nothing is saved. Throws when the saved file
  /// exists but cannot be read.
  public func cachedProjects() throws -> ProjectList? {
    guard FileManager.default.fileExists(atPath: cacheURL.path) else {
      return nil
    }
    let data = try Data(contentsOf: cacheURL)
    let file = try CaptureContractJSON.makeDecoder().decode(CacheFile.self, from: data)
    guard file.cacheVersion == CacheFile.currentVersion else {
      return nil
    }
    return ProjectList(
      projects: file.projects.filter(\.hasUsableAddress), fetchedAt: file.fetchedAt, isStale: true)
  }

  /// Deletes the offline copy, for example at sign-out.
  public func clearCache() throws {
    if FileManager.default.fileExists(atPath: cacheURL.path) {
      try FileManager.default.removeItem(at: cacheURL)
    }
  }

  private func save(_ file: CacheFile) throws {
    try FileManager.default.createDirectory(
      at: cacheDirectory, withIntermediateDirectories: true)
    let data = try CaptureContractJSON.makeEncoder().encode(file)
    #if os(iOS)
      try data.write(
        to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #else
      try data.write(to: cacheURL, options: .atomic)
    #endif
  }

  /// On-disk shape of the offline copy.
  struct CacheFile: Codable {
    static let currentVersion = 1

    var cacheVersion: Int = CacheFile.currentVersion
    var fetchedAt: UTCTimestamp
    var projects: [HubProject]
  }
}
