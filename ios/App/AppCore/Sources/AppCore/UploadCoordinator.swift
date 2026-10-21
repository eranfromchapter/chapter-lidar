import CaptureContract
import Foundation
import PackageCore

/// Why a transient failure paused the upload (phone-package §4.3).
public enum PauseReason: String, Equatable, Sendable {
  /// No connection: offline, the connection was lost, or the host cannot be reached.
  case offline
  /// The station or the storage service answered with an error it may recover from (5xx, 408,
  /// 429), or kept refusing the upload targets.
  case stationUnavailable
}

/// What the upload of one sealed package is doing.
public enum UploadActivity: Equatable, Sendable {
  case starting
  case uploading
  /// A transient failure. Retries on its own.
  case waitingToRetry(PauseReason)
  /// The station refused the token. Uploading continues after the operator signed in again
  /// (`UploadCoordinator.retry()`).
  case signInRequired
  /// A failure that retrying cannot fix (for example a package file no longer matches its
  /// fingerprint). The package and its state stay on the phone.
  case failed(String)
  /// The station verified every file and registered the package.
  case confirmed
}

/// Everything Package status and Verdict received show for one package (phone-package §4, §5).
public struct UploadSnapshot: Equatable, Sendable {
  /// Where the package is, as Package status draws it.
  public enum Phase: Equatable, Sendable {
    /// Uploading (or starting).
    case uploading
    case paused(PauseReason)
    case signInRequired
    /// Every file confirmed, no verdict yet.
    case uploaded
    /// Every file confirmed; the station's checks failed and it retries.
    case checksDelayed
    /// Upload stopped (fatal).
    case stopped(String)
    /// The station's verdict is known: Verdict received.
    case verdict
  }

  public var packageId: LowercaseUUID
  public var package: SealedPackageSummary
  public var state: UploadState
  public var activity: UploadActivity
  /// What the station said last (live, or from the status cache).
  public var station: StationPackageInfo?
  public var verdict: VerdictStatus?
  /// The file the upload stopped on, when the fatal error names one.
  public var stoppedPath: String?

  public var progress: UploadProgressSummary

  public init(
    packageId: LowercaseUUID, package: SealedPackageSummary, state: UploadState,
    activity: UploadActivity, station: StationPackageInfo? = nil, verdict: VerdictStatus? = nil,
    stoppedPath: String? = nil, manifest: PackageManifest
  ) {
    self.packageId = packageId
    self.package = package
    self.state = state
    self.activity = activity
    self.station = station
    self.verdict = verdict
    self.stoppedPath = stoppedPath
    var stopped = false
    if case .failed = activity { stopped = true }
    progress = UploadProgressSummary.make(
      state: state, manifest: manifest, stopped: stopped, stoppedPath: stoppedPath)
  }

  /// True only when the station confirmed every file and registered the package. Only then may
  /// anything of the package ever leave the phone (v1 has no delete at all).
  public var isConfirmedByStation: Bool { state.isConfirmedByStation }

  /// Re-sealed as a later revision after a failed upload; never resumed.
  public var isSuperseded: Bool { state.supersededBy != nil }

  /// The package's stage at the station, once known.
  public var stage: StationPackageStage? {
    station?.stage ?? state.sealResult.flatMap { StationPackageStage(rawValue: $0.status.rawValue) }
  }

  public var phase: Phase {
    if case .failed(let message) = activity { return .stopped(message) }
    if verdict != nil { return .verdict }
    if isConfirmedByStation { return stage == .checkError ? .checksDelayed : .uploaded }
    switch activity {
    case .waitingToRetry(let reason): return .paused(reason)
    case .signInRequired: return .signInRequired
    default: return .uploading
    }
  }

  /// "Uploading", "Uploaded", "Upload stopped" (Verdict received has the project title).
  public var title: String {
    switch phase {
    case .stopped: return "Upload stopped"
    case .uploaded, .checksDelayed: return "Uploaded"
    case .verdict: return package.projectTitle
    case .uploading, .paused, .signInRequired: return "Uploading"
    }
  }

  /// The caption under the progress bar (§4.3). Upload stopped: the fatal message.
  public var caption: String {
    switch phase {
    case .uploading: return "Uploads continue in the background. You can close the app."
    case .paused(.offline): return "Paused: no connection. Resumes on its own. You can close the app."
    case .paused(.stationUnavailable):
      return "Paused: the station is not answering. Resumes on its own. You can close the app."
    case .signInRequired: return "Sign in again to continue the upload."
    case .uploaded, .verdict: return "The station has every file. Checks run next."
    case .checksDelayed:
      return "The station has every file. Its checks are delayed; it retries on its own."
    case .stopped(let message): return message
    }
  }

  /// Revision 1: "618 Valley Street · 74 files · 768 MB". A later revision counts only what it
  /// uploads (files the station carried over are not): "424 West End Ave, Apt 4K · revision 2 ·
  /// 8 new or changed files · 120 MB".
  public var subtitle: String {
    guard package.revision > 1 else {
      return "\(package.address) \u{00B7} \(PackageText.plural(package.fileCount, "file", "files"))"
        + " \u{00B7} \(ByteText.format(package.totalBytes))"
    }
    let own = state.files.filter { !state.carriedOver.contains($0.path) }
    let files = PackageText.plural(own.count, "new or changed file", "new or changed files")
    return "\(package.address) \u{00B7} revision \(package.revision) \u{00B7} \(files) \u{00B7} "
      + ByteText.format(own.reduce(0) { $0 + $1.bytes })
  }

  /// "Revision 1 · sealed" (Package status), "Revision 1" or "Revision 1 · superseded" (Verdict
  /// received).
  public var navigationCaption: String {
    switch phase {
    case .verdict:
      return isSuperseded
        ? "Revision \(package.revision) \u{00B7} superseded" : "Revision \(package.revision)"
    default:
      return "Revision \(package.revision) \u{00B7} sealed"
    }
  }

  /// Verdict received: "Sealed Jan 25, 2025 · checked May 16, 2026".
  public func verdictSubtitle(timeZone: TimeZone = .current) -> String? {
    guard let verdict else { return nil }
    return "Sealed \(PackageText.date(package.sealedAt.date, in: timeZone)) \u{00B7} checked "
      + PackageText.date(verdict.evaluatedAt.date, in: timeZone)
  }

  /// The station published the revision to the HUB.
  public var isPublished: Bool { station?.publication?.status == .published }

  /// The Station card: with "Registered" on Package status, without it on Verdict received.
  public func timeline(now: Date = Date(), timeZone: TimeZone = .current) -> StationTimeline {
    StationTimeline.make(
      registeredAt: state.registeredAt, isConfirmed: isConfirmedByStation, station: station,
      verdict: verdict, includeRegistered: phase != .verdict, now: now, timeZone: timeZone)
  }

  /// The muted line under the fatal message of Upload stopped. `canReseal`: the visit's
  /// originals are still on the phone.
  public func stoppedNote(canReseal: Bool) -> String {
    guard canReseal else {
      return "Nothing was deleted. Try again. This phone no longer has the scans to re-seal; "
        + "start a new capture."
    }
    let next = package.revision + 1
    return "Nothing was deleted. Try again, or re-seal to upload the files as they are on this "
      + "phone now as revision \(next). Revision \(package.revision) stays on this phone."
  }

  /// "Re-seal as revision 2".
  public var resealTitle: String { "Re-seal as revision \(package.revision + 1)" }
  /// "Re-seal as revision 2?".
  public var resealAlertTitle: String { "\(resealTitle)?" }
  public var resealAlertMessage: String {
    let next = package.revision + 1
    return "The app builds revision \(next) from the scans, photos and controls on this phone and "
      + "uploads it. Revision \(package.revision) stays on this phone and is not uploaded further."
  }

  /// The footnote under the Station card. `notificationsAllowed`: the operator allowed the
  /// verdict notification.
  public func footnote(notificationsAllowed: Bool) -> String {
    let stays = "Files stay on this phone until the station confirms each one."
    if case .stopped = phase { return stays }
    return notificationsAllowed
      ? "\(stays) You will get a notification with the verdict."
      : "\(stays) Open the app to see the verdict."
  }

  /// The local notification of the known verdict.
  public var verdictNotification: VerdictNotification? {
    verdict.map {
      VerdictNotification(
        packageId: packageId, verdict: $0, projectTitle: package.projectTitle,
        revision: package.revision)
    }
  }
}

/// "The package could not be sealed: {reason}. Nothing was uploaded." (Package ready, Revision n,
/// Upload stopped).
public enum SealFailureText {
  public static func make(_ error: Error) -> String {
    make(reason: String(describing: error))
  }

  public static func make(reason: String) -> String {
    var reason = reason
    while reason.hasSuffix(".") { reason.removeLast() }
    return "The package could not be sealed: \(reason). Nothing was uploaded."
  }
}

/// How an upload error is handled.
public enum UploadErrorKind: Equatable, Sendable {
  case transient(PauseReason)
  case signIn
  /// `path`: the package file the failure is about, when one is named.
  case fatal(String, path: String? = nil)

  /// URLError codes that mean the phone has no connection to the station (phone-package §4.3).
  static let offlineURLErrors: Set<URLError.Code> = [
    .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
    .cannotFindHost, .cannotConnectToHost, .timedOut,
  ]

  public static func of(_ error: Error) -> UploadErrorKind {
    if StationErrorClassifier.requiresSignIn(error) { return .signIn }
    if StationErrorClassifier.isOffline(error) {
      if case .offline? = error as? StationAPIError { return .transient(.offline) }
      return .transient(.stationUnavailable)
    }
    if let urlError = error as? URLError {
      return .transient(offlineURLErrors.contains(urlError.code) ? .offline : .stationUnavailable)
    }
    if let problem = error as? StationProblem {
      if problem.status == 401 { return .signIn }
      if problem.status >= 500 || problem.status == 408 || problem.status == 429 {
        return .transient(.stationUnavailable)
      }
      return .fatal("The station refused the upload (\(problem.status) \(problem.code)).")
    }
    if let transport = error as? BlobTransportError {
      switch transport {
      case .network: return .transient(.offline)
      case .http(let status, _) where status >= 500 || status == 408 || status == 429:
        return .transient(.stationUnavailable)
      case .http(let status, let code):
        return .fatal("The storage service refused a file (\(status) \(code ?? "")).")
      case .unreadable: return .fatal("A package file could not be read.")
      }
    }
    if let upload = error as? PackageUploadError {
      switch upload {
      case .targetsKeepFailing, .sealNotConfirmed: return .transient(.stationUnavailable)
      case .localFileChanged(let path):
        return .fatal(
          "\(Self.fileName(path)) changed on the phone after sealing. It was not uploaded.",
          path: path)
      case .tooManyRejectedUploads(let path, _), .checkMismatch(let path, _):
        return .fatal(upload.description, path: path)
      default: return .fatal(upload.description)
      }
    }
    return .fatal(StationErrorClassifier.message(error))
  }

  /// The last part of a package path ("plan.pdf").
  static func fileName(_ path: String) -> String {
    String(path.split(separator: "/").last ?? Substring(path))
  }
}

/// Runs the upload of one sealed package to the end and then follows its station status:
/// resumes from the saved state, retries transient failures with back-off ("Paused"), stops for
/// sign-in or a fatal error, and after registration polls the station until the verdict is ready
/// and the HUB publication is final (at most `verdictFollowLimit` after the verdict). Every
/// station answer is written to the package's status cache. Never deletes anything.
public final class UploadCoordinator: @unchecked Sendable {
  public let package: SealedPackage
  public let dealId: String

  private let service: any PackageUploadService
  private let transport: any BlobTransport
  private let statusSource: any PackageStatusSource
  private let store: UploadStateStore
  private let statusStore: StationStatusStore
  private let sleep: @Sendable (TimeInterval) async throws -> Void
  private let now: @Sendable () -> Date
  private let retryDelays: [TimeInterval]
  private let pollInterval: TimeInterval
  private let verdictFollowLimit: TimeInterval
  private let onChange: @Sendable (UploadSnapshot) -> Void
  private let onVerdict: (@Sendable (VerdictNotification) -> Void)?

  /// Guarded by `lock`.
  private let lock = NSLock()
  private var snapshotValue: UploadSnapshot
  private var task: Task<Void, Never>?

  /// - statusStore: where the station status is cached (default: next to the package).
  /// - verdictFollowLimit: how long after the verdict the HUB publication is still followed.
  /// - onVerdict: called once per verdict that has no notification yet, to post it; the cache
  ///   then remembers it was posted (phone-package §7).
  public init(
    package: SealedPackage, dealId: String, service: any PackageUploadService,
    transport: any BlobTransport, statusSource: any PackageStatusSource,
    store: UploadStateStore? = nil, statusStore: StationStatusStore? = nil,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
      try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    },
    now: @escaping @Sendable () -> Date = { Date() },
    retryDelays: [TimeInterval] = [2, 5, 15, 30, 60, 120, 300],
    pollInterval: TimeInterval = 15,
    verdictFollowLimit: TimeInterval = 30 * 60,
    onChange: @escaping @Sendable (UploadSnapshot) -> Void = { _ in },
    onVerdict: (@Sendable (VerdictNotification) -> Void)? = nil
  ) {
    self.package = package
    self.dealId = dealId
    self.service = service
    self.transport = transport
    self.statusSource = statusSource
    let store = store ?? UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root))
    self.store = store
    let statusStore = statusStore ?? StationStatusStore(packageRoot: package.root)
    self.statusStore = statusStore
    self.sleep = sleep
    self.now = now
    self.retryDelays = retryDelays.isEmpty ? [5] : retryDelays
    self.pollInterval = pollInterval
    self.verdictFollowLimit = verdictFollowLimit
    self.onChange = onChange
    self.onVerdict = onVerdict
    let state = (try? store.load()) ?? UploadState(package: package, dealId: dealId)
    let cached = try? statusStore.load()
    snapshotValue = UploadSnapshot(
      packageId: package.packageId, package: SealedPackageSummary.make(package), state: state,
      activity: .starting, station: cached?.station, verdict: cached?.verdict,
      manifest: package.manifest)
  }

  public var snapshot: UploadSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return snapshotValue
  }

  /// Starts (or, after sign-in or a fatal error, restarts) the upload. Does nothing while running
  /// or once the package is superseded.
  public func start() {
    lock.lock()
    defer { lock.unlock() }
    guard task == nil, snapshotValue.state.supersededBy == nil else { return }
    task = Task { [weak self] in
      await self?.run()
      self?.finished()
    }
  }

  /// Same as `start()`: call after sign-in, for "Try again", or when the app comes back to the
  /// foreground.
  public func retry() { start() }

  /// Stops the run (the state is saved; `start()` resumes).
  public func cancel() {
    lock.lock()
    let running = task
    task = nil
    lock.unlock()
    running?.cancel()
  }

  /// "Re-seal as revision n+1" sealed `packageId`: this package stops for good. Its upload state
  /// records the revision that replaced it, so it is never resumed (`PendingUploads`). Nothing is
  /// deleted.
  public func supersede(by packageId: LowercaseUUID) throws {
    cancel()
    var state = (try store.load()) ?? snapshot.state
    state.supersededBy = packageId
    try store.save(state)
    update { $0.state = state }
  }

  /// Waits until the current run ends (tests).
  public func waitUntilIdle() async {
    await currentTask()?.value
  }

  private func currentTask() -> Task<Void, Never>? {
    lock.withLock { task }
  }

  private func finished() {
    lock.lock()
    task = nil
    lock.unlock()
  }

  // MARK: Run

  private func run() async {
    guard await upload() else { return }
    await followStation()
  }

  /// Uploads until the station registered the package. False when stopped (sign-in, fatal,
  /// cancelled).
  private func upload() async -> Bool {
    var attempt = 0
    while !Task.isCancelled {
      do {
        let uploader = try PackageUploader(
          package: package, dealId: dealId, service: service, transport: transport, store: store,
          now: now, progress: { [weak self] state in self?.update { $0.state = state } })
        update {
          $0.activity = .uploading
          $0.stoppedPath = nil
        }
        _ = try await uploader.run()
        let state = await uploader.currentState
        update {
          $0.state = state
          $0.activity = .confirmed
        }
        return true
      } catch is CancellationError {
        return false
      } catch {
        switch UploadErrorKind.of(error) {
        case .transient(let reason):
          update { $0.activity = .waitingToRetry(reason) }
          let delay = retryDelays[min(attempt, retryDelays.count - 1)]
          attempt += 1
          do { try await sleep(delay) } catch { return false }
        case .signIn:
          update { $0.activity = .signInRequired }
          return false
        case .fatal(let message, let path):
          update {
            $0.activity = .failed(message)
            $0.stoppedPath = path
          }
          return false
        }
      }
    }
    return false
  }

  /// Polls the package's station record until the verdict is known and its HUB publication is
  /// final, or `verdictFollowLimit` after the verdict. A new verdict (the checks ran again)
  /// replaces the old one. Through check errors it keeps asking: the station retries.
  private func followStation() async {
    var attempt = 0
    var verdictSince: Date? = snapshot.verdict == nil ? nil : now()
    notifyIfNew()
    while !Task.isCancelled {
      let current = snapshot
      if current.verdict != nil {
        if current.station?.publication?.status.isFinal == true { return }
        if let since = verdictSince, now().timeIntervalSince(since) >= verdictFollowLimit { return }
      }
      do {
        try await sleep(attempt == 0 ? 0 : pollInterval)
        attempt += 1
        let station = try await statusSource.package(packageId: package.packageId.uuid)
        var verdict = current.verdict
        if station.stage == .verdictReady,
          verdict == nil || (station.verdictId != nil && station.verdictId != verdict?.verdictId)
        {
          verdict = try await statusSource.verdict(packageId: package.packageId.uuid)
          if verdictSince == nil { verdictSince = now() }
        }
        update {
          $0.station = station
          $0.verdict = verdict
        }
        _ = try? statusStore.record(
          packageId: package.packageId, station: station, verdict: verdict, at: now())
        notifyIfNew()
      } catch is CancellationError {
        return
      } catch {
        if case .signIn = UploadErrorKind.of(error) {
          update { $0.activity = .signInRequired }
          return
        }
        // Status reads are retried quietly; the package itself is already confirmed.
        do { try await sleep(pollInterval) } catch { return }
      }
    }
  }

  /// Posts the verdict notification once per verdict (`onVerdict`), remembered in the cache.
  private func notifyIfNew() {
    guard let onVerdict, let notification = snapshot.verdictNotification,
      let cache = try? statusStore.load(), cache.notifiedVerdictId != notification.verdictId,
      cache.verdict?.verdictId == notification.verdictId
    else { return }
    onVerdict(notification)
    try? statusStore.markNotified(notification.verdictId)
  }

  private func update(_ change: (inout UploadSnapshot) -> Void) {
    lock.lock()
    var next = snapshotValue
    change(&next)
    next = UploadSnapshot(
      packageId: next.packageId, package: next.package, state: next.state,
      activity: next.activity, station: next.station, verdict: next.verdict,
      stoppedPath: next.stoppedPath, manifest: package.manifest)
    snapshotValue = next
    lock.unlock()
    onChange(next)
  }
}

/// Sealed packages on the phone whose upload the station has not confirmed yet, newest first,
/// without the packages re-sealed as a later revision. The HUB deal id is read from each
/// package's own capture record. Packages sealed by app builds before v2 (manifest 1.0.0) are
/// found too, so their uploads resume after the app update.
public enum PendingUploads {
  public struct Item: Sendable {
    public let package: SealedPackage
    public let dealId: String
    public let state: UploadState?
  }

  public static func find(visitsRoot: URL) -> [Item] {
    var items: [(Date, Item)] = []
    for (folder, package) in SealedPackageFolders.all(visitsRoot: visitsRoot) {
      let state = try? UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: folder))
        .load()
      if state?.isConfirmedByStation == true || state?.supersededBy != nil { continue }
      guard let dealId = state?.dealId ?? dealId(of: package) else { continue }
      items.append(
        (package.manifest.sealedAt.date, Item(package: package, dealId: dealId, state: state)))
    }
    return items.sorted { $0.0 > $1.0 }.map(\.1)
  }

  static func dealId(of package: SealedPackage) -> String? {
    SealedPackageSummary.captureRecord(of: package)?.hub.dealId
  }
}
