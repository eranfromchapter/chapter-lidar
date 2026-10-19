#if canImport(Observation)
  import CaptureContract
  import CaptureModelMapping
  import Foundation
  import Observation

  public enum CaptureFlowStep: Sendable, Equatable {
    /// Step 1 of 3: HUB project and address.
    case newCapture
    /// Step 2 of 3: floor or area, mode, skipped rooms, coverage notes.
    case scanSetup
    /// Step 3 of 3: live scan.
    case scanning
    case finished
  }

  /// What the flow hands on when the floor is finished (F6 packages it).
  public struct CaptureFlowResult: Sendable {
    public var record: CaptureRecord
    /// `<originals root>/Original Exports/{areaKey}/{captureId}/`, where the originals were written.
    public var originalsDirectory: URL
    public var writtenFiles: [WrittenOriginal]
    public var session: CaptureSessionResult
    /// The contract capture model, or nil when mapping failed (see `mappingError`; the originals are kept).
    public var captureModel: CaptureModel?
    public var mappingError: String?
  }

  /// State and actions behind the three capture screens. Every view only reads this and calls its
  /// methods, so the whole flow runs in tests with a `ReplaySession`.
  @MainActor
  @Observable
  public final class CaptureFlowModel {
    public var step: CaptureFlowStep = .newCapture
    public var draft: CaptureRecordDraft

    public private(set) var projects: [HubProjectSummary] = []
    public private(set) var isLoadingProjects = false
    public private(set) var projectsError: String?

    public private(set) var progress = ScanProgress()
    public private(set) var instruction: ScanInstruction = .normal
    public private(set) var sessionState: CaptureSessionState = .idle
    public private(set) var errorMessage: String?
    public private(set) var result: CaptureFlowResult?

    /// The session of the scan in progress: set when Start scan made it (scanning or paused), nil
    /// before that and again after Finish floor or Cancel. Observed, so a view that reads it is
    /// redrawn when a scan starts or ends. The host uses it to show the camera feed in
    /// `CaptureFlowView`'s `preview` (`CaptureSessionPreview` in `CaptureRoomPlan`); it must not
    /// keep the session after it goes nil.
    public var currentSession: (any CaptureSession)? { session }

    /// Observed (not `@ObservationIgnored`) so `currentSession` updates its readers.
    private var session: (any CaptureSession)?

    public let gate: DeviceGateResult
    public let hasLidar: Bool

    @ObservationIgnored private let projectProvider: HubProjectProvider
    @ObservationIgnored private let originalsRoot: URL
    @ObservationIgnored private let makeSession: @MainActor (CaptureSessionConfiguration) throws -> any CaptureSession
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let onFinished: @MainActor (CaptureFlowResult) -> Void
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var builtRecord: CaptureRecord?
    @ObservationIgnored private var visitedAt: UTCTimestamp?

    public init(
      draft: CaptureRecordDraft, capabilities: DeviceCapabilities, projectProvider: HubProjectProvider,
      originalsRoot: URL,
      makeSession: @escaping @MainActor (CaptureSessionConfiguration) throws -> any CaptureSession,
      clock: @escaping @Sendable () -> Date = { Date() },
      onFinished: @escaping @MainActor (CaptureFlowResult) -> Void = { _ in }
    ) {
      self.draft = draft
      self.gate = DeviceGate.evaluate(capabilities)
      self.hasLidar = capabilities.supportsSceneReconstructionMesh
      self.projectProvider = projectProvider
      self.originalsRoot = originalsRoot
      self.makeSession = makeSession
      self.clock = clock
      self.onFinished = onFinished
    }

    // MARK: Step 1

    public func loadProjects() async {
      isLoadingProjects = true
      projectsError = nil
      do {
        projects = try await projectProvider.projects()
      } catch {
        projects = []
        projectsError = "Could not load HUB projects: \(error.localizedDescription)"
      }
      isLoadingProjects = false
    }

    public func choose(_ project: HubProjectSummary) {
      draft.select(project)
    }

    public func setAddressConfirmed(_ confirmed: Bool) {
      draft.setAddressConfirmed(confirmed, at: UTCTimestamp(clock()))
    }

    /// Continue is allowed with a project and a confirmed address, and a supported device.
    public var canContinueToSetup: Bool {
      gate.isSupported && draft.project != nil && draft.isAddressConfirmed
    }

    public func continueToSetup() {
      guard canContinueToSetup else { return }
      step = .scanSetup
    }

    public func back() {
      if step == .scanSetup { step = .newCapture }
    }

    // MARK: Step 2

    public var canStartScan: Bool { gate.isSupported && draft.canSave }

    public func addOmittedRoom(name: String, reason: String?) {
      let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
      draft.omittedRooms.append(
        CaptureRecord.RoomNote(
          name: name.trimmingCharacters(in: .whitespacesAndNewlines),
          reason: (trimmedReason?.isEmpty ?? true) ? nil : trimmedReason))
    }

    public func removeOmittedRoom(at index: Int) {
      guard draft.omittedRooms.indices.contains(index) else { return }
      draft.omittedRooms.remove(at: index)
    }

    // MARK: Step 3

    /// Builds the record (this is where an incomplete draft is refused) and starts the session.
    public func startScan() async {
      errorMessage = nil
      guard canStartScan, let mode = draft.mode else {
        errorMessage = gate.message ?? draft.validate().map(\.description).joined(separator: " ")
        return
      }
      do {
        let started = UTCTimestamp(clock())
        visitedAt = started
        builtRecord = try draft.build(visitedAt: started, capturedAt: started)
        let session = try makeSession(CaptureSessionConfiguration(mode: mode))
        self.session = session
        progress = ScanProgress()
        instruction = .normal
        sessionState = .idle
        isPaused = false
        step = .scanning
        eventTask = Task { [weak self] in
          for await event in session.events {
            self?.handle(event)
          }
        }
        try await session.start(CaptureSessionConfiguration(mode: mode))
      } catch {
        await fail(error)
        // A scan that could not start (for example the phone is too hot) shows Try again.
        if step == .scanning, let error = error as? CaptureSessionError, error.endsTheScan {
          sessionState = .failed(error.description)
        }
      }
    }

    /// Set by `togglePause` as soon as the session accepted the change; `sessionState` follows
    /// from the session's events a moment later.
    public private(set) var isPaused = false

    public func togglePause() async {
      guard let session else { return }
      do {
        if isPaused {
          try await session.resume()
          isPaused = false
        } else {
          try await session.pause()
          isPaused = true
        }
      } catch {
        await fail(error)
      }
    }

    /// Finishes the floor: stops the scan, writes the originals, maps the capture model.
    public func finishFloor() async {
      guard let session, var record = builtRecord else { return }
      do {
        let sessionResult = try await session.finish()
        record.captures[0].finishedAt = UTCTimestamp(sessionResult.finishedAt)
        let capture = record.captures[0]
        let directory = originalsDirectory(areaKey: capture.areaKey, captureId: capture.captureId)
        let written = try RawOriginalsWriter.write(sessionResult.originals, to: directory)

        var model: CaptureModel?
        var mappingError: String?
        let base = "\(PackageFolder.originalExports.name)/\(capture.areaKey)/\(capture.captureId.rawValue)/"
        let context = MappingContext(
          visitId: record.visitId, captureId: capture.captureId, areaKey: capture.areaKey,
          label: capture.label,
          refs: [
            CaptureModel.SourceRef(role: .rawRoomplanJSON, path: base + RawOriginalsNaming.originals.roomPlanFileName),
            CaptureModel.SourceRef(role: .rawDepth, path: base + RawOriginalsNaming.depthFileName),
          ])
        do {
          model = try sessionResult.captureModel(context: context)
        } catch {
          mappingError = String(describing: error)
        }
        let finished = CaptureFlowResult(
          record: record, originalsDirectory: directory, writtenFiles: written, session: sessionResult,
          captureModel: model, mappingError: mappingError)
        result = finished
        step = .finished
        eventTask?.cancel()
        eventTask = nil
        self.session = nil
        onFinished(finished)
      } catch {
        await fail(error)
      }
    }

    /// True when the session stopped with an error; the live screen then offers Try again.
    public var scanFailed: Bool {
      if case .failed = sessionState { return true }
      return false
    }

    /// "Try again" after a failed scan: drops the failed session and starts a new one with the
    /// same draft. Nothing from the failed session is kept.
    public func retryScan() async {
      guard scanFailed else { return }
      await session?.cancel()
      eventTask?.cancel()
      eventTask = nil
      session = nil
      await startScan()
    }

    /// Stops the scan without keeping anything.
    public func cancelScan() async {
      await session?.cancel()
      eventTask?.cancel()
      eventTask = nil
      session = nil
      step = .scanSetup
    }

    public func originalsDirectory(areaKey: String, captureId: LowercaseUUID) -> URL {
      originalsRoot
        .appendingPathComponent(PackageFolder.originalExports.name, isDirectory: true)
        .appendingPathComponent(areaKey, isDirectory: true)
        .appendingPathComponent(captureId.rawValue, isDirectory: true)
    }

    // MARK: Live screen text

    /// "Floor 1 · Whole floor".
    /// What the operator should do next on the live scan screen.
    public var guidance: ScanGuidance {
      ScanGuidance.next(
        counts: progress.counts, mode: draft.mode, isPaused: isPaused, instruction: instruction)
    }

    public var scanTitle: String {
      let label = draft.floorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      return "\(label) · \(draft.mode.map(CaptureFlowModel.modeTitle) ?? "")"
    }

    /// "06:42".
    public var elapsedText: String {
      let seconds = max(0, Int(progress.elapsed))
      return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Mode names as the design shows them.
    public static func modeTitle(_ mode: CaptureMode) -> String {
      switch mode {
      case .room: return "One room"
      case .floor: return "Whole floor"
      case .exterior: return "Exterior"
      }
    }

    // MARK: Private

    private func handle(_ event: CaptureSessionEvent) {
      switch event {
      case .stateChanged(let state):
        sessionState = state
        // RoomPlan stopped on its own (too hot, tracking lost): say why, so the operator is not
        // left with a frozen timer and a Finish button that can only say "Nothing was captured".
        if case .failed(let message) = state { errorMessage = message }
      case .progress(let value): progress = value
      case .instruction(let value): instruction = value
      }
    }

    private func fail(_ error: Error) async {
      if let error = error as? CaptureSessionError {
        errorMessage = error.description
      } else if let error = error as? CaptureRecordValidationFailure {
        errorMessage = error.description
      } else if let error = error as? RawOriginalsError {
        errorMessage = error.description
      } else {
        errorMessage = error.localizedDescription
      }
    }
  }
#endif
