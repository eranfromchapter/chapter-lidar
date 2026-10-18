import CaptureContract
import Foundation
import PackageCore

/// What the upload of one sealed package is doing.
public enum UploadActivity: Equatable, Sendable {
  case starting
  case uploading
  /// A transient failure (offline, station or blob service unavailable). Retries on its own.
  case waitingToRetry
  /// The station refused the token. Uploading continues after the operator signed in again
  /// (`UploadCoordinator.retry()`).
  case signInRequired
  /// A failure that retrying cannot fix (for example a package file no longer matches its
  /// fingerprint). The package and its state stay on the phone.
  case failed(String)
  /// The station verified every file and registered the package.
  case confirmed
}

/// Everything the Uploading screen shows for one package.
public struct UploadSnapshot: Equatable, Sendable {
  public var packageId: LowercaseUUID
  public var state: UploadState
  public var activity: UploadActivity
  public var stage: StationPackageStage?
  public var verdict: VerdictDisplay?

  public var progress: UploadProgressSummary
  public var station: StationSteps

  /// True only when the station confirmed every file and registered the package. Only then may
  /// anything of the package ever leave the phone (v1 has no delete at all).
  public var isConfirmedByStation: Bool { state.isConfirmedByStation }

  /// The caption under the progress bar.
  public var caption: String {
    switch activity {
    case .waitingToRetry: return "Paused while offline. Resumes on its own. You can close the app."
    case .signInRequired: return "Sign in again to continue the upload."
    case .failed(let message): return message
    case .confirmed: return "The station has every file."
    case .starting, .uploading: return "Uploads continue in the background. You can close the app."
    }
  }
}

/// How an upload error is handled.
public enum UploadErrorKind: Equatable, Sendable {
  case transient
  case signIn
  case fatal(String)

  public static func of(_ error: Error) -> UploadErrorKind {
    if StationErrorClassifier.requiresSignIn(error) { return .signIn }
    if StationErrorClassifier.isOffline(error) { return .transient }
    if error is URLError { return .transient }
    if let problem = error as? StationProblem {
      if problem.status == 401 { return .signIn }
      if problem.status >= 500 || problem.status == 408 || problem.status == 429 {
        return .transient
      }
      return .fatal("The station refused the upload (\(problem.status) \(problem.code)).")
    }
    if let transport = error as? BlobTransportError {
      switch transport {
      case .network: return .transient
      case .http(let status, _) where status >= 500 || status == 408 || status == 429:
        return .transient
      case .http(let status, let code):
        return .fatal("The storage service refused a file (\(status) \(code ?? "")).")
      case .unreadable: return .fatal("A package file could not be read.")
      }
    }
    if let upload = error as? PackageUploadError {
      switch upload {
      case .targetsKeepFailing, .sealNotConfirmed: return .transient
      case .localFileChanged(let path):
        return .fatal("\(path) changed on the phone after sealing. It was not uploaded.")
      default: return .fatal(upload.description)
      }
    }
    return .fatal(StationErrorClassifier.message(error))
  }
}

/// Runs the upload of one sealed package to the end and then follows its station status:
/// resumes from the saved state, retries transient failures with back-off ("paused while
/// offline"), stops for sign-in or a fatal error, and after registration polls the station until
/// the verdict is ready. Never deletes anything.
public final class UploadCoordinator: @unchecked Sendable {
  public let package: SealedPackage
  public let dealId: String

  private let service: any PackageUploadService
  private let transport: any BlobTransport
  private let statusSource: any PackageStatusSource
  private let store: UploadStateStore
  private let sleep: @Sendable (TimeInterval) async throws -> Void
  private let retryDelays: [TimeInterval]
  private let pollInterval: TimeInterval
  private let onChange: @Sendable (UploadSnapshot) -> Void

  /// Guarded by `lock`.
  private let lock = NSLock()
  private var snapshotValue: UploadSnapshot
  private var task: Task<Void, Never>?

  public init(
    package: SealedPackage, dealId: String, service: any PackageUploadService,
    transport: any BlobTransport, statusSource: any PackageStatusSource,
    store: UploadStateStore? = nil,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
      try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    },
    retryDelays: [TimeInterval] = [2, 5, 15, 30, 60, 120, 300],
    pollInterval: TimeInterval = 15,
    onChange: @escaping @Sendable (UploadSnapshot) -> Void = { _ in }
  ) {
    self.package = package
    self.dealId = dealId
    self.service = service
    self.transport = transport
    self.statusSource = statusSource
    let store = store ?? UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root))
    self.store = store
    self.sleep = sleep
    self.retryDelays = retryDelays.isEmpty ? [5] : retryDelays
    self.pollInterval = pollInterval
    self.onChange = onChange
    let state = (try? store.load()) ?? UploadState(package: package, dealId: dealId)
    snapshotValue = Self.makeSnapshot(
      package: package, state: state, activity: .starting, stage: nil, verdict: nil)
  }

  public var snapshot: UploadSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return snapshotValue
  }

  /// Starts (or, after sign-in or a fatal error, restarts) the upload. Does nothing while running.
  public func start() {
    lock.lock()
    defer { lock.unlock() }
    guard task == nil else { return }
    task = Task { [weak self] in
      await self?.run()
      self?.finished()
    }
  }

  /// Same as `start()`: call after sign-in or when the app comes back to the foreground.
  public func retry() { start() }

  /// Stops the run (the state is saved; `start()` resumes).
  public func cancel() {
    lock.lock()
    let running = task
    task = nil
    lock.unlock()
    running?.cancel()
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
          progress: { [weak self] state in self?.update { $0.state = state } })
        update { $0.activity = .uploading }
        let result = try await uploader.run()
        let state = await uploader.currentState
        update {
          $0.state = state
          $0.activity = .confirmed
          $0.stage = StationPackageStage(rawValue: result.status.rawValue)
        }
        return true
      } catch is CancellationError {
        return false
      } catch {
        switch UploadErrorKind.of(error) {
        case .transient:
          update { $0.activity = .waitingToRetry }
          let delay = retryDelays[min(attempt, retryDelays.count - 1)]
          attempt += 1
          do { try await sleep(delay) } catch { return false }
        case .signIn:
          update { $0.activity = .signInRequired }
          return false
        case .fatal(let message):
          update { $0.activity = .failed(message) }
          return false
        }
      }
    }
    return false
  }

  /// Polls the package status until the verdict is ready (or the checks failed), then reads the
  /// verdict.
  private func followStation() async {
    var attempt = 0
    while !Task.isCancelled {
      let current = snapshot.stage
      if current == .checkError || (current == .verdictReady && snapshot.verdict != nil) {
        return
      }
      do {
        if current == .verdictReady {
          let verdict = try await statusSource.verdict(packageId: package.packageId.uuid)
          update { $0.verdict = verdict }
          return
        }
        try await sleep(attempt == 0 ? 0 : pollInterval)
        attempt += 1
        let stage = try await statusSource.stage(packageId: package.packageId.uuid)
        update { $0.stage = stage }
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

  private func update(_ change: (inout UploadSnapshot) -> Void) {
    lock.lock()
    var next = snapshotValue
    change(&next)
    next = Self.makeSnapshot(
      package: package, state: next.state, activity: next.activity, stage: next.stage,
      verdict: next.verdict)
    snapshotValue = next
    lock.unlock()
    onChange(next)
  }

  private static func makeSnapshot(
    package: SealedPackage, state: UploadState, activity: UploadActivity,
    stage: StationPackageStage?, verdict: VerdictDisplay?
  ) -> UploadSnapshot {
    UploadSnapshot(
      packageId: package.packageId, state: state, activity: activity, stage: stage,
      verdict: verdict,
      progress: UploadProgressSummary.make(state: state, manifest: package.manifest),
      station: StationSteps.make(registered: state.isConfirmedByStation, stage: stage))
  }
}

/// Sealed packages on the phone whose upload the station has not confirmed yet, newest first.
/// The HUB deal id is read from each package's own capture record.
public enum PendingUploads {
  public struct Item: Sendable {
    public let package: SealedPackage
    public let dealId: String
    public let state: UploadState?
  }

  public static func find(visitsRoot: URL) -> [Item] {
    let fileManager = FileManager.default
    guard
      let workspaces = try? fileManager.contentsOfDirectory(
        at: visitsRoot, includingPropertiesForKeys: nil)
    else { return [] }
    var items: [(Date, Item)] = []
    for workspace in workspaces {
      let packages = VisitWorkspace(root: workspace).packagesRoot
      guard
        let folders = try? fileManager.contentsOfDirectory(
          at: packages, includingPropertiesForKeys: [.creationDateKey])
      else { continue }
      for folder in folders where !folder.lastPathComponent.hasPrefix(".") {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
          isDirectory.boolValue, let package = try? SealedPackage.open(at: folder)
        else { continue }
        let state = try? UploadStateStore(
          url: UploadStateStore.defaultURL(forPackageAt: folder)
        ).load()
        if state?.isConfirmedByStation == true { continue }
        guard let dealId = state?.dealId ?? dealId(of: package) else { continue }
        items.append(
          (package.manifest.sealedAt.date, Item(package: package, dealId: dealId, state: state)))
      }
    }
    return items.sorted { $0.0 > $1.0 }.map(\.1)
  }

  static func dealId(of package: SealedPackage) -> String? {
    guard let entry = package.manifest.files.first(where: { $0.role == .captureRecord }),
      let data = try? Data(contentsOf: package.url(for: entry.path)),
      let record = try? CaptureContractJSON.makeDecoder().decode(CaptureRecord.self, from: data)
    else { return nil }
    return record.hub.dealId
  }
}
