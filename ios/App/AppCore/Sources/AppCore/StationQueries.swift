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
public enum StationPackageStage: String, Sendable, Equatable, CaseIterable, Codable {
  case uploading
  case checksQueued = "checks_queued"
  case checking
  case verdictReady = "verdict_ready"
  case checkError = "check_error"
}

/// What the phone keeps of a package's station record (`getPackage`, station 1.1.0): its stage,
/// the check run, the HUB publication and the web links. The fields 1.1.0 added are nil from an
/// older station.
public struct StationPackageInfo: Codable, Equatable, Sendable {
  /// The latest check run (CheckRunSummary).
  public struct Checks: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable, CaseIterable {
      case queued
      case running
      case completed
      case failed
    }

    public var status: Status
    public var startedAt: UTCTimestamp?
    /// Present when completed or failed.
    public var finishedAt: UTCTimestamp?

    public init(status: Status, startedAt: UTCTimestamp? = nil, finishedAt: UTCTimestamp? = nil) {
      self.status = status
      self.startedAt = startedAt
      self.finishedAt = finishedAt
    }
  }

  /// The HUB publication of the revision (PublicationSummary).
  public struct Publication: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable, CaseIterable {
      case pending
      case publishing
      case published
      case publishFailed = "publish_failed"

      /// Published or failed: the station stops trying, so the phone stops asking.
      public var isFinal: Bool { self == .published || self == .publishFailed }
    }

    public var status: Status
    /// Present exactly when published.
    public var publishedAt: UTCTimestamp?

    public init(status: Status, publishedAt: UTCTimestamp? = nil) {
      self.status = status
      self.publishedAt = publishedAt
    }
  }

  /// The package's web pages (PackageLinks), as URL strings.
  public struct Links: Codable, Equatable, Sendable {
    /// The review screen's package page.
    public var review: String
    /// The HUB page of the deal; nil when the station has none configured.
    public var hub: String?

    public init(review: String, hub: String? = nil) {
      self.review = review
      self.hub = hub
    }

    /// What "Open in the HUB" opens: the HUB page when the station has one, else the review page
    /// (phone-package Q2).
    public var openInHub: URL? { URL(string: hub ?? review) }
  }

  public var stage: StationPackageStage
  /// When the station registered the package (opened its upload session).
  public var createdAt: UTCTimestamp
  public var sealedAt: UTCTimestamp?
  public var checks: Checks?
  public var publication: Publication?
  public var links: Links?
  /// The current verdict's id, present when the stage is verdict_ready.
  public var verdictId: LowercaseUUID?

  public init(
    stage: StationPackageStage, createdAt: UTCTimestamp, sealedAt: UTCTimestamp? = nil,
    checks: Checks? = nil, publication: Publication? = nil, links: Links? = nil,
    verdictId: LowercaseUUID? = nil
  ) {
    self.stage = stage
    self.createdAt = createdAt
    self.sealedAt = sealedAt
    self.checks = checks
    self.publication = publication
    self.links = links
    self.verdictId = verdictId
  }

  /// The phone's copy of a station package.
  public init(_ package: Package) throws {
    guard let stage = StationPackageStage(rawValue: package.status.rawValue) else {
      throw StationError.invalidResponse("unknown package status \(package.status.rawValue)")
    }
    self.init(
      stage: stage, createdAt: package.createdAt, sealedAt: package.sealedAt,
      checks: package.checks.flatMap { checks in
        Checks.Status(rawValue: checks.status.rawValue).map {
          Checks(status: $0, startedAt: checks.startedAt, finishedAt: checks.finishedAt)
        }
      },
      publication: package.publication.flatMap { publication in
        Publication.Status(rawValue: publication.status.rawValue).map {
          Publication(status: $0, publishedAt: publication.publishedAt)
        }
      },
      links: package.links.map {
        Links(review: $0.review.absoluteString, hub: $0.hub?.absoluteString)
      },
      verdictId: package.verdict?.verdictId)
  }
}

/// What the phone shows of a verdict (phone-package §5): the outcome as word and shape, one
/// sentence, the next visit's actions and when it was checked. Never the findings themselves
/// ("Details: spatial report in the HUB").
public struct VerdictStatus: Codable, Equatable, Sendable {
  /// One "For the next visit" row: the station's next action verbatim, and why.
  public struct NextVisit: Codable, Equatable, Sendable {
    /// The next action exactly as the station wrote it (same words as the report and the web).
    public var action: String
    /// `measured` of the first finding with this next action, else its `message`; nil when no
    /// finding names the action.
    public var reason: String?

    public init(action: String, reason: String? = nil) {
      self.action = action
      self.reason = reason
    }
  }

  public var verdictId: LowercaseUUID
  public var outcome: VerdictOutcome
  /// The task the outcome applies to, as the station wrote it.
  public var task: String
  public var limitationCount: Int
  public var blockerCount: Int
  /// Every next action of the verdict, in the station's order.
  public var nextVisit: [NextVisit]
  public var evaluatedAt: UTCTimestamp

  /// At most this many next actions are shown; the rest are counted in a footnote.
  public static let shownNextVisitLimit = 3

  public init(
    verdictId: LowercaseUUID, outcome: VerdictOutcome, task: String, limitationCount: Int,
    blockerCount: Int, nextVisit: [NextVisit], evaluatedAt: UTCTimestamp
  ) {
    self.verdictId = verdictId
    self.outcome = outcome
    self.task = task
    self.limitationCount = limitationCount
    self.blockerCount = blockerCount
    self.nextVisit = nextVisit
    self.evaluatedAt = evaluatedAt
  }

  public init(_ verdict: Verdict) {
    self.init(
      verdictId: verdict.verdictId, outcome: verdict.outcome, task: verdict.task,
      limitationCount: verdict.limitations.count,
      blockerCount: verdict.findings.filter { $0.severity == .blocker }.count,
      nextVisit: verdict.nextActions.map { action in
        let finding = verdict.findings.first { $0.nextAction == action }
        return NextVisit(action: action, reason: finding.map { $0.measured ?? $0.message })
      },
      evaluatedAt: verdict.evaluatedAt)
  }

  /// "Ready", "Limited", "Blocked".
  public var word: String { Self.word(outcome) }

  public static func word(_ outcome: VerdictOutcome) -> String {
    switch outcome {
    case .ready: return "Ready"
    case .limited: return "Limited"
    case .blocked: return "Blocked"
    }
  }

  /// The verdict card's sentence. `published`: the station published the revision (and its
  /// spatial report) to the HUB.
  public func sentence(published: Bool) -> String {
    let task = PackageText.lowerFirst(self.task)
    let details =
      published
      ? "Details: spatial report in the HUB." : "Details: spatial report in the HUB once it is published."
    switch outcome {
    case .ready:
      return "Ready for \(task). \(details)"
    case .limited:
      let limitations = PackageText.plural(limitationCount, "limitation", "limitations")
      return "Usable for \(task), with \(limitations). \(details)"
    case .blocked:
      let blockers = PackageText.plural(blockerCount, "blocker", "blockers")
      return "Not usable yet for \(task): \(blockers). \(details)"
    }
  }

  /// The "For the next visit" rows shown (at most 3, station order).
  public var shownNextVisit: [NextVisit] { Array(nextVisit.prefix(Self.shownNextVisitLimit)) }

  /// "{m} more in the spatial report." when more next actions exist than are shown.
  public var moreNextVisitText: String? {
    let more = nextVisit.count - shownNextVisit.count
    return more > 0 ? "\(more) more in the spatial report." : nil
  }
}

/// Reads a sealed package's state and verdict from the station.
public protocol PackageStatusSource: Sendable {
  func package(packageId: UUID) async throws -> StationPackageInfo
  func verdict(packageId: UUID) async throws -> VerdictStatus
}

extension PackageStatusSource {
  /// The package's stage at the station.
  public func stage(packageId: UUID) async throws -> StationPackageStage {
    try await package(packageId: packageId).stage
  }
}

/// `PackageStatusSource` over StationClient (`getPackage`, `getVerdict`).
public struct StationStatusSource: PackageStatusSource {
  public let client: StationClient

  public init(client: StationClient) {
    self.client = client
  }

  public func package(packageId: UUID) async throws -> StationPackageInfo {
    try StationPackageInfo(try await client.getPackage(packageId: packageId))
  }

  public func verdict(packageId: UUID) async throws -> VerdictStatus {
    VerdictStatus(try await client.getVerdict(packageId: packageId))
  }
}

/// Sends what the next revision changes so far (phone-package §10.4), so the web can show
/// "Revision 2 · not sealed · on the phone". Best effort: callers ignore every failure.
public protocol NextRevisionNoticeSending: Sendable {
  func send(_ notice: NextRevisionNoticeDraft, basePackageId: LowercaseUUID) async throws
}

/// `NextRevisionNoticeSending` over StationClient (`putNextRevisionNotice`).
public struct StationNextRevisionNotices: NextRevisionNoticeSending {
  public let client: StationClient

  public init(client: StationClient) {
    self.client = client
  }

  public func send(_ notice: NextRevisionNoticeDraft, basePackageId: LowercaseUUID) async throws {
    try await client.putNextRevisionNotice(
      packageId: basePackageId.uuid, Self.input(notice))
  }

  /// The contract body of a notice. Titles and details are cut to the contract's lengths (200
  /// and 300 characters) and the list to 50 rows; the phone's rows are far shorter.
  public static func input(_ notice: NextRevisionNoticeDraft) -> NextRevisionNoticeInput {
    NextRevisionNoticeInput(
      revision: notice.revision, updatedAt: notice.updatedAt,
      changes: notice.rows.prefix(50).map { row in
        NextRevisionChange(
          kind: NextRevisionChange.Kind(rawValue: row.kind.rawValue) ?? .changed,
          subject: NextRevisionChange.Subject(rawValue: row.subject.rawValue) ?? .capture,
          title: String(row.title.prefix(200)), detail: String(row.detail.prefix(300)),
          answersNextAction: row.answersNextAction.map { String($0.prefix(500)) },
          method: row.method)
      })
  }
}

/// Keeps the station's next-revision notice current while the operator edits revision n
/// (phone-package §10.4): each change is sent 10 s after the last one (debounced), and again
/// when the app comes back to the foreground (`flush()`). Failures are ignored: never shown,
/// never blocking; the next change or foreground tries again.
public actor NextRevisionNotifier {
  private let sender: any NextRevisionNoticeSending
  private let delay: TimeInterval
  private let sleep: @Sendable (TimeInterval) async throws -> Void
  private var latest: (notice: NextRevisionNoticeDraft, base: LowercaseUUID)?
  private var pending: Task<Void, Never>?
  /// Notices the station accepted (tests).
  public private(set) var sentCount = 0

  public init(
    sender: any NextRevisionNoticeSending, delay: TimeInterval = 10,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
      try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
  ) {
    self.sender = sender
    self.delay = delay
    self.sleep = sleep
  }

  /// Revision n changed: send `notice` once nothing changed for `delay`.
  public func changed(_ notice: NextRevisionNoticeDraft, basePackageId: LowercaseUUID) {
    latest = (notice, basePackageId)
    pending?.cancel()
    let delay = self.delay
    let sleep = self.sleep
    pending = Task { [weak self] in
      do { try await sleep(delay) } catch { return }
      guard !Task.isCancelled else { return }
      await self?.sendLatest()
    }
  }

  /// Sends the latest notice now (the app came back to the foreground).
  public func flush() async {
    pending?.cancel()
    pending = nil
    await sendLatest()
  }

  /// Revision n was sealed (the station drops the notice itself): nothing more is sent.
  public func stop() {
    pending?.cancel()
    pending = nil
    latest = nil
  }

  /// Waits for a scheduled send (tests).
  public func waitUntilIdle() async {
    await pending?.value
  }

  private func sendLatest() async {
    guard let latest else { return }
    do {
      try await sender.send(latest.notice, basePackageId: latest.base)
      sentCount += 1
    } catch {
      // Best effort (§10.4).
    }
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
