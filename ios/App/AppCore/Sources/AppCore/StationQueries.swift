// HUB project list and package status from the station. Imports StationClient (not PackageCore).
import CaptureContract
import CaptureCore
import Foundation
import StationClient

/// `HubProjectProvider` (what the "New capture" screen asks) over StationClient's `ProjectStore`:
/// the live list when online, the last saved list when offline (never invented projects).
public struct StationProjectProvider: HubProjectProvider {
  public let store: ProjectStore

  public init(store: ProjectStore) {
    self.store = store
  }

  public func projects() async throws -> [HubProjectSummary] {
    let list = try await store.projects()
    return Self.summaries(of: list)
  }

  /// The address is copied exactly as the HUB shows it; `updatedAt` is when the station returned
  /// the list (older when the list is the offline copy).
  public static func summaries(of list: ProjectList) -> [HubProjectSummary] {
    list.projects.map { project in
      HubProjectSummary(
        dealId: project.dealId, projectName: project.projectName ?? "",
        address: project.address.formatted, updatedAt: list.fetchedAt.date)
    }
  }
}

/// Where a sealed package is at the station (PackageStatus).
public enum StationPackageStage: String, Sendable, Equatable, CaseIterable {
  case uploading
  case checksQueued = "checks_queued"
  case checking
  case verdictReady = "verdict_ready"
  case checkError = "check_error"
}

/// What the "Uploading" screen shows of a finished verdict.
public struct VerdictDisplay: Equatable, Sendable {
  public var outcome: VerdictOutcome
  public var summary: String
  /// The first next action the station recommends, if any.
  public var nextAction: String?

  public init(outcome: VerdictOutcome, summary: String, nextAction: String? = nil) {
    self.outcome = outcome
    self.summary = summary
    self.nextAction = nextAction
  }

  /// Word and shape, never colour alone: "● Ready", "▲ Limited", "■ Blocked".
  public var title: String {
    switch outcome {
    case .ready: return "\u{25CF} Ready"
    case .limited: return "\u{25B2} Limited"
    case .blocked: return "\u{25A0} Blocked"
    }
  }
}

/// Reads a sealed package's state and verdict from the station.
public protocol PackageStatusSource: Sendable {
  func stage(packageId: UUID) async throws -> StationPackageStage
  func verdict(packageId: UUID) async throws -> VerdictDisplay
}

/// `PackageStatusSource` over StationClient (`getPackage`, `getVerdict`).
public struct StationStatusSource: PackageStatusSource {
  public let client: StationClient

  public init(client: StationClient) {
    self.client = client
  }

  public func stage(packageId: UUID) async throws -> StationPackageStage {
    let package = try await client.getPackage(packageId: packageId)
    guard let stage = StationPackageStage(rawValue: package.status.rawValue) else {
      throw StationError.invalidResponse("unknown package status \(package.status.rawValue)")
    }
    return stage
  }

  public func verdict(packageId: UUID) async throws -> VerdictDisplay {
    let verdict = try await client.getVerdict(packageId: packageId)
    return VerdictDisplay(
      outcome: verdict.outcome, summary: verdict.summary, nextAction: verdict.nextActions.first)
  }
}

/// Errors that mean the operator must sign in again (interactive sign-in). The MSAL token
/// provider throws `SignInRequired`; the station answers 401 after one forced refresh.
public struct SignInRequired: Error, Equatable, Sendable, CustomStringConvertible {
  public init() {}
  public var description: String { "Sign in again to continue." }
}

public enum StationErrorClassifier {
  /// True for StationClient's offline and transport errors (retry later).
  public static func isOffline(_ error: Error) -> Bool {
    guard let error = error as? StationError else { return false }
    switch error {
    case .offline, .network: return true
    default: return false
    }
  }

  /// True when the error means interactive sign-in is needed.
  public static func requiresSignIn(_ error: Error) -> Bool {
    if error is SignInRequired { return true }
    if let error = error as? StationError { return error.requiresSignIn }
    return false
  }

  /// A short message for the screen. Never includes tokens or URLs.
  public static func message(_ error: Error) -> String {
    if let error = error as? StationError {
      switch error {
      case .offline: return "The station cannot be reached. Check the connection."
      case .network(let code): return "Network error \(code)."
      case .unauthorized: return "Sign in again to continue."
      case .forbidden: return "Your account has no access to the station."
      case .notFound(let problem): return problem?.title ?? "Not found at the station."
      case .conflict(let problem): return problem?.title ?? "The station refused the request."
      case .validation(_, let problem): return problem?.title ?? "The station refused the request."
      case .server(let status, let problem): return problem?.title ?? "Station error \(status)."
      case .unexpectedStatus(let status): return "Unexpected station answer \(status)."
      case .invalidResponse: return "The station sent an answer the app does not understand."
      case .invalidRequest: return "The app could not form the request."
      }
    }
    return String(describing: error)
  }
}
