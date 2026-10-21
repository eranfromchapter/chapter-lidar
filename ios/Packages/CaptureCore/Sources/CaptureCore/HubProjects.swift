import Foundation

/// A HUB project the operator can pick. Supplied by an injected provider; the station client
/// (F6) provides the real one.
public struct HubProjectSummary: Sendable, Hashable, Identifiable {
  /// HUB deal id, as returned by the HUB.
  public var dealId: String
  public var projectName: String
  /// Single-line address exactly as shown by the HUB.
  public var address: String
  /// When the HUB data was last refreshed ("updated 2 min ago" on screen).
  public var updatedAt: Date?
  /// The project manager's phone, when the HUB gives it (OpenAPI 1.1.0
  /// `HubProject.projectManager.phone`, owner question Q-C): "Call the PM" dials it. Nil hides
  /// the call; the button still discards the draft.
  public var projectManagerPhone: String?

  public var id: String { dealId }

  public init(
    dealId: String, projectName: String, address: String, updatedAt: Date? = nil,
    projectManagerPhone: String? = nil
  ) {
    self.dealId = dealId
    self.projectName = projectName
    self.address = address
    self.updatedAt = updatedAt
    self.projectManagerPhone = projectManagerPhone
  }

  /// The project title of every phone screen (critique R-29): the project name when it is not
  /// empty, else the address.
  public var title: String {
    let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? address : name
  }

  /// `tel:` with the PM's phone (digits and a leading +), nil without one.
  public var projectManagerCallURL: URL? {
    guard let phone = projectManagerPhone else { return nil }
    let dialable = phone.filter { $0.isNumber || $0 == "+" }
    guard dialable.contains(where: \.isNumber) else { return nil }
    return URL(string: "tel:\(dialable)")
  }
}

/// The HUB project list as the station gave it, or the copy saved on this phone when offline
/// (phone-capture §3.2.1).
public struct HubProjectListing: Sendable, Equatable {
  public var projects: [HubProjectSummary]
  /// When the list was fetched from the station (the saved copy's date when offline).
  public var fetchedAt: Date?
  /// True when the station could not be reached and this is the copy saved on this phone.
  public var isOfflineCopy: Bool

  public init(projects: [HubProjectSummary], fetchedAt: Date? = nil, isOfflineCopy: Bool = false) {
    self.projects = projects
    self.fetchedAt = fetchedAt
    self.isOfflineCopy = isOfflineCopy
  }
}

/// Thrown by a provider that cannot reach the station and has no saved list.
public enum HubProjectListingError: Error, Equatable, CustomStringConvertible {
  case offlineWithoutSavedList

  public var description: String {
    "No connection and no projects saved on this phone. Connect once to load the HUB projects."
  }
}

/// Where the HUB projects come from. Implement `listing()`; `projects()` is the v1 entry point,
/// kept while the app's provider still offers only it (the default `listing()` wraps it as an
/// online list). New providers return `try await listing().projects` from it.
public protocol HubProjectProvider: Sendable {
  func projects() async throws -> [HubProjectSummary]
  /// The list with its date and whether it is the offline copy. Throws
  /// `HubProjectListingError.offlineWithoutSavedList` when offline with nothing saved.
  func listing() async throws -> HubProjectListing
}

extension HubProjectProvider {
  public func listing() async throws -> HubProjectListing {
    HubProjectListing(projects: try await projects())
  }
}

/// A fixed list, for tests and previews.
public struct StaticHubProjectProvider: HubProjectProvider {
  public var list: [HubProjectSummary]
  public var fetchedAt: Date?
  public var isOfflineCopy: Bool

  public init(_ list: [HubProjectSummary], fetchedAt: Date? = nil, isOfflineCopy: Bool = false) {
    self.list = list
    self.fetchedAt = fetchedAt
    self.isOfflineCopy = isOfflineCopy
  }

  public func projects() async throws -> [HubProjectSummary] { list }

  public func listing() async throws -> HubProjectListing {
    HubProjectListing(projects: list, fetchedAt: fetchedAt, isOfflineCopy: isOfflineCopy)
  }
}
