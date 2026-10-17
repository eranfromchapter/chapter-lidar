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

  public var id: String { dealId }

  public init(dealId: String, projectName: String, address: String, updatedAt: Date? = nil) {
    self.dealId = dealId
    self.projectName = projectName
    self.address = address
    self.updatedAt = updatedAt
  }
}

public protocol HubProjectProvider: Sendable {
  func projects() async throws -> [HubProjectSummary]
}

/// A fixed list, for tests and previews.
public struct StaticHubProjectProvider: HubProjectProvider {
  public var list: [HubProjectSummary]

  public init(_ list: [HubProjectSummary]) {
    self.list = list
  }

  public func projects() async throws -> [HubProjectSummary] { list }
}
