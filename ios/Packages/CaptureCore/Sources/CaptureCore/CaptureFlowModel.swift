#if canImport(Observation)
  import CaptureContract
  import CaptureModelMapping
  import Foundation
  import Observation

  public enum CaptureFlowStep: Sendable, Equatable {
    /// Step 1 of 3: HUB project and address.
    case newCapture
    /// Step 2 of 3: floor or area, mode, skipped rooms, coverage notes, compass.
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

  /// What the live scan shows (phone-capture §3.4): the normal scan or one of its states.
  public enum LiveScanPhase: Sendable, Equatable {
    case scanning
    /// Paused by the operator.
    case paused
    /// ARKit lost tracking; RoomPlan keeps running.
    case trackingLost
    /// RoomPlan ended the scan on its own or could not start (`message` says why).
    case stopped(String)
  }

  /// State and actions behind the capture screens (New capture, What are you scanning?, Live
  /// scan). Every view only reads this and calls its methods, so the whole flow runs in tests
  /// with a `ReplaySession` and a `FakeCompass`.
  ///
  /// The compass (compass §3.2, §3.3, §10.2): `compassPrecheck` is the pre-check on step 2 (never
  /// stored), `liveCompass` the chip of the scan, and `finishFloor()` writes the scan's own
  /// reading (`CaptureSessionResult.compass`) into the capture. No API takes a heading from the
  /// screens.
  @MainActor
  @Observable
  public final class CaptureFlowModel {
    public var step: CaptureFlowStep = .newCapture
    public var draft: CaptureRecordDraft

    /// The HUB projects (or the copy saved on this phone); nil before loading or after an error.
    public private(set) var listing: HubProjectListing?
    public private(set) var isLoadingProjects = false
    public private(set) var projectsError: String?
    /// Offline and no project list saved on this phone (New capture cannot continue).
    public private(set) var isOfflineWithoutList = false

    public private(set) var progress = ScanProgress()
    public private(set) var instruction: ScanInstruction = .normal
    public private(set) var sessionState: CaptureSessionState = .idle
    public private(set) var errorMessage: String?
    public private(set) var result: CaptureFlowResult?

    /// The step 2 pre-check (compass §3.2); `.reading` until it has run.
    public private(set) var compassPrecheck: CompassPrecheckState = .reading
    /// Location authorisation as of the last pre-check.
    public private(set) var locationAuthorization: CompassAuthorization = .notDetermined
    /// The compass chip of the scan in progress (compass §5.2).
    public private(set) var liveCompass: CompassLiveState = .reading
    /// ARKit tracking of the scan in progress.
    public private(set) var tracking: TrackingStatus = .normal
    /// Set by `togglePause` as soon as the session accepted the change; `sessionState` follows
    /// from the session's events a moment later.
    public private(set) var isPaused = false
    /// When the operator paused ("Paused · 00:12").
    public private(set) var pausedAt: Date?
    /// Finish floor is writing the originals.
    public private(set) var isFinishing = false

    /// The session of the scan in progress: set when Start scan made it (scanning or paused), nil
    /// before that and again after Finish floor or Cancel. Observed, so a view that reads it is
    /// redrawn when a scan starts or ends. The host shows the camera feed with it
    /// (`CaptureSessionPreview` in `CaptureRoomPlan`); it must not keep the session after it goes
    /// nil.
    public var currentSession: (any CaptureSession)? { session }

    /// Observed (not `@ObservationIgnored`) so `currentSession` updates its readers.
    private var session: (any CaptureSession)?

    public let gate: DeviceGateResult
    public let hasLidar: Bool

    /// Area keys already captured in this visit, set by the host when adding a floor: Start scan
    /// refuses a name whose key is one of them, and the name is prefilled with the next free
    /// "Floor N".
    public var existingAreaKeys: Set<String> {
      get { areaKeys }
      set {
        let previousSuggestion = Self.suggestedFloorName(existing: areaKeys)
        areaKeys = newValue
        let label = draft.floorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty || label == previousSuggestion {
          draft.floorLabel = Self.suggestedFloorName(existing: newValue)
        }
      }
    }
    private var areaKeys: Set<String>

    @ObservationIgnored private let projectProvider: HubProjectProvider
    @ObservationIgnored private let originalsRoot: URL
    @ObservationIgnored private let makeSession: @MainActor (CaptureSessionConfiguration) throws -> any CaptureSession
    @ObservationIgnored private let compass: (any CompassProviding)?
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored public let timeZone: TimeZone
    @ObservationIgnored private let onFinished: @MainActor (CaptureFlowResult) -> Void
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var builtRecord: CaptureRecord?
    @ObservationIgnored private var visitedAt: UTCTimestamp?
    @ObservationIgnored private var precheckGeneration = 0
    @ObservationIgnored private var askedForLocation = false

    /// `compass` is the app's one compass (`CompassService`), or a `FakeCompass`; without one
    /// there is no pre-check (`hasCompass`). `existingAreaKeys`: see the property.
    public init(
      draft: CaptureRecordDraft, capabilities: DeviceCapabilities, projectProvider: HubProjectProvider,
      originalsRoot: URL,
      makeSession: @escaping @MainActor (CaptureSessionConfiguration) throws -> any CaptureSession,
      compass: (any CompassProviding)? = nil, existingAreaKeys: Set<String> = [],
      clock: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current,
      onFinished: @escaping @MainActor (CaptureFlowResult) -> Void = { _ in }
    ) {
      var draft = draft
      if draft.floorLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        draft.floorLabel = Self.suggestedFloorName(existing: existingAreaKeys)
      }
      self.draft = draft
      self.areaKeys = existingAreaKeys
      self.gate = DeviceGate.evaluate(capabilities)
      self.hasLidar = capabilities.supportsSceneReconstructionMesh
      self.projectProvider = projectProvider
      self.originalsRoot = originalsRoot
      self.makeSession = makeSession
      self.compass = compass
      self.clock = clock
      self.timeZone = timeZone
      self.onFinished = onFinished
      self.locationAuthorization = compass?.authorization ?? .notDetermined
    }

    /// The model's clock (injected in tests), for every "ago" and timer on the screens.
    public func now() -> Date { clock() }

    // MARK: Step 1

    /// The projects of the listing (empty before loading or after an error).
    public var projects: [HubProjectSummary] { listing?.projects ?? [] }

    /// True when the listing is the copy saved on this phone.
    public var isOffline: Bool { listing?.isOfflineCopy ?? false }

    public func loadProjects() async {
      isLoadingProjects = true
      projectsError = nil
      isOfflineWithoutList = false
      do {
        listing = try await projectProvider.listing()
      } catch HubProjectListingError.offlineWithoutSavedList {
        listing = nil
        isOfflineWithoutList = true
      } catch {
        listing = nil
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

    /// The "I am at this address" switch changed. Returns true when it went from on to off: the
    /// screen then shows "Address is different on site?". Off → on records the time.
    public func addressToggleChanged(isOn: Bool) -> Bool {
      let wasOn = draft.isAddressConfirmed
      setAddressConfirmed(isOn)
      return wasOn && !isOn
    }

    /// A button of "Address is different on site?" (`AddressDifferentAlert`). Go back changes
    /// nothing: the switch stays off and the project stays chosen. Call the PM dials the PM's
    /// `tel:` URL when the HUB project has a phone number, then calls `discard` (the host drops
    /// the draft and goes back to the Captures home; nothing was saved).
    public func addressAlert(
      _ action: AddressDifferentAlert.Action, dial: (URL) -> Void, discard: () -> Void
    ) {
      switch action {
      case .goBack:
        return
      case .callProjectManager:
        if let url = draft.project?.projectManagerCallURL { dial(url) }
        discard()
      }
    }

    /// Why Continue is disabled, as its label says it (phone-capture §3.2); nil when enabled.
    public var continueBlocker: String? {
      if !gate.isSupported { return "This phone cannot scan" }
      if draft.project == nil {
        return isOfflineWithoutList ? "Connect to load projects" : "Choose a HUB project to continue"
      }
      if !draft.isAddressConfirmed { return "Confirm the address to continue" }
      return nil
    }

    /// The Continue button's label: the blocker, else "Continue offline" with the saved list.
    public var continueTitle: String {
      continueBlocker ?? (isOffline ? "Continue offline" : "Continue")
    }

    /// Continue is allowed with a project and a confirmed address, and a supported device.
    public var canContinueToSetup: Bool { continueBlocker == nil }

    public func continueToSetup() {
      guard canContinueToSetup else { return }
      step = .scanSetup
    }

    public func back() {
      if step == .scanSetup { step = .newCapture }
    }

    /// The HUB project row's title: the project title, or "Choose a HUB project".
    public var projectRowTitle: String { draft.project?.title ?? "Choose a HUB project" }

    /// The HUB project row's subtitle (phone-capture §3.2, §3.2.1).
    public var projectRowSubtitle: String {
      guard let project = draft.project else {
        return isLoadingProjects ? "Loading projects from the HUB…" : "Projects come from the HUB"
      }
      if isOffline { return "Deal \(project.dealId) · saved on this phone" }
      guard let updated = project.updatedAt ?? listing?.fetchedAt else {
        return "Deal \(project.dealId) · from the HUB"
      }
      let age = CaptureText.relativeAge(from: updated, now: clock(), timeZone: timeZone)
      return "Deal \(project.dealId) · from the HUB, updated \(age)"
    }

    /// The offline banner, nil when online.
    public var offlineBanner: String? {
      if isOfflineWithoutList { return HubProjectListingError.offlineWithoutSavedList.description }
      guard let listing, listing.isOfflineCopy else { return nil }
      let count = listing.projects.count
      let what = count == 1 ? "the 1 project" : "the \(count) projects"
      let updated = listing.fetchedAt.map {
        " (updated \(CaptureText.offlineStamp($0, timeZone: timeZone)))"
      }
      return "No connection. Showing \(what) saved on this phone\(updated ?? ""). You can scan "
        + "offline; the upload waits for a connection."
    }

    /// "iPhone 16 Pro · LiDAR" (the model identifier when the name is unknown).
    public var deviceText: String {
      let device = draft.device
      return "\(device.marketingName ?? device.model) · \(hasLidar ? "LiDAR" : "no LiDAR")"
    }

    /// "1.0.0 (37)".
    public var appText: String { "\(draft.app.version) (\(draft.app.build))" }

    // MARK: Step 2

    /// "Floor N": N = the captures in the visit + 1, raised until its area key is unused.
    public static func suggestedFloorName(existing: Set<String>) -> String {
      var number = existing.count + 1
      while existing.contains("floor-\(number)") { number += 1 }
      return "Floor \(number)"
    }

    /// The right-hand caption of step 2: "Step 2 of 3", or the project title when adding a floor.
    public var scanSetupCaption: String {
      areaKeys.isEmpty ? "Step 2 of 3" : (draft.project?.title ?? "")
    }

    /// Why Start scan is disabled, as its label says it (phone-capture §3.3); nil when enabled.
    /// The compass never blocks.
    public var startScanBlocker: String? {
      if !gate.isSupported { return "This phone cannot scan" }
      let label = draft.floorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      if label.isEmpty { return "Enter the floor or area" }
      guard let key = draft.areaKey else { return "Use letters or numbers in the name" }
      if areaKeys.contains(key) { return "\(label) is already captured. Use another name" }
      if draft.mode == nil { return "Choose what you are scanning" }
      if let other = draft.validate().first {
        return CaptureText.withoutFinalPeriod(other.description)
      }
      return nil
    }

    /// The Start scan button's label.
    public var startScanTitle: String { startScanBlocker ?? "Start scan" }

    public var canStartScan: Bool { startScanBlocker == nil }

    public func addOmittedRoom(name: String, reason: String?) {
      let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedName.isEmpty else { return }
      let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
      draft.omittedRooms.append(
        CaptureRecord.RoomNote(
          name: trimmedName, reason: (trimmedReason?.isEmpty ?? true) ? nil : trimmedReason))
    }

    public func removeOmittedRoom(at index: Int) {
      guard draft.omittedRooms.indices.contains(index) else { return }
      draft.omittedRooms.remove(at: index)
    }

    /// True when the host gave a compass. Without one (the v1 app shell until it passes its
    /// `CompassService`) step 2 shows no compass row: nothing is read, and "No compass on this
    /// phone" would be false on a phone that has one. The scan then records no reading, and the
    /// plans say north is not verified.
    public var hasCompass: Bool { compass != nil }

    /// Runs the compass pre-check (on appear, and for Read again). The first call asks for the
    /// location permission when it is not determined (compass §3.1). A newer call wins over one
    /// still running; a cancelled call leaves the row reading. Without a compass it does nothing.
    public func readCompassAgain() async {
      guard let compass else { return }
      if !askedForLocation {
        askedForLocation = true
        if compass.authorization == .notDetermined { compass.requestAuthorization() }
      }
      locationAuthorization = compass.authorization
      guard compass.isAvailable else {
        compassPrecheck = .unavailable
        return
      }
      precheckGeneration += 1
      let generation = precheckGeneration
      compassPrecheck = .reading
      let state = await compass.precheck()
      guard generation == precheckGeneration, !Task.isCancelled else { return }
      compassPrecheck = state
      locationAuthorization = compass.authorization
    }

    /// Location is denied or restricted: north is magnetic (the note with Open Settings).
    public var isLocationOff: Bool { locationAuthorization == .denied }

    public func openLocationSettings() {
      compass?.openSettings()
    }

    // MARK: Step 3

    /// Builds the record (this is where an incomplete draft is refused) and starts the session.
    public func startScan() async {
      errorMessage = nil
      guard canStartScan, let mode = draft.mode else {
        errorMessage = startScanBlocker.map { "\($0)." }
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
        liveCompass = .reading
        tracking = .normal
        isPaused = false
        pausedAt = nil
        isFinishing = false
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

    /// Pause is allowed while scanning with tracking, Resume while paused.
    public var canTogglePause: Bool {
      session != nil && !isFinishing && !scanFailed && (isPaused || !tracking.isLost)
    }

    public func togglePause() async {
      guard let session, canTogglePause else { return }
      do {
        if isPaused {
          try await session.resume()
          isPaused = false
          pausedAt = nil
        } else {
          try await session.pause()
          isPaused = true
          pausedAt = clock()
        }
      } catch {
        await fail(error)
      }
    }

    /// Finish floor is offered once a wall was found (an empty scan cannot be finished).
    public var canFinishFloor: Bool {
      session != nil && !isFinishing && !scanFailed && progress.counts.walls > 0
    }

    /// Finishes the floor: stops the scan, writes the originals, records the scan's compass
    /// reading in the capture (or why there is none; nothing when the session read no compass,
    /// `CompassResult`), maps the capture model.
    public func finishFloor() async {
      guard let session, var record = builtRecord, !isFinishing else { return }
      isFinishing = true
      defer { isFinishing = false }
      do {
        let sessionResult = try await session.finish()
        record.captures[0].finishedAt = UTCTimestamp(sessionResult.finishedAt)
        record.captures[0].setCompass(sessionResult.compass)
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
        // "Nothing was captured" (a race with RoomPlan's last update) shows the stopped card
        // with Back and Try again, as a scan RoomPlan ended does.
        if let error = error as? CaptureSessionError, error.endsTheScan || error == .noRoomsCaptured {
          sessionState = .failed(error.description)
        }
      }
    }

    /// True when the session stopped with an error; the live screen then offers Try again.
    public var scanFailed: Bool {
      if case .failed = sessionState { return true }
      return false
    }

    /// "Try again" after a failed scan: drops the failed session and starts a new one with the
    /// same draft. Nothing from the failed session is kept, its compass reading included.
    public func retryScan() async {
      guard scanFailed else { return }
      await dropSession()
      await startScan()
    }

    /// "Restart this floor instead" (tracking lost, after the confirmation): cancels the scan —
    /// nothing is written — and starts a new one with the same draft, which reads the compass
    /// again (compass addendum G3).
    public func restartFloor() async {
      guard session != nil, !isFinishing else { return }
      await dropSession()
      await startScan()
    }

    /// Stops the scan without keeping anything.
    public func cancelScan() async {
      await dropSession()
      liveCompass = .reading
      tracking = .normal
      isPaused = false
      pausedAt = nil
      step = .scanSetup
    }

    public func originalsDirectory(areaKey: String, captureId: LowercaseUUID) -> URL {
      originalsRoot
        .appendingPathComponent(PackageFolder.originalExports.name, isDirectory: true)
        .appendingPathComponent(areaKey, isDirectory: true)
        .appendingPathComponent(captureId.rawValue, isDirectory: true)
    }

    // MARK: Live screen text

    /// What the live scan shows: stopped, paused by the operator, tracking lost, or scanning.
    public var livePhase: LiveScanPhase {
      if case .failed(let message) = sessionState { return .stopped(message) }
      if isPaused { return .paused }
      if tracking.isLost { return .trackingLost }
      return .scanning
    }

    /// What the operator should do next on the live scan screen.
    public var guidance: ScanGuidance {
      ScanGuidance.next(
        counts: progress.counts, mode: draft.mode, isPaused: isPaused, instruction: instruction)
    }

    /// "Paused · 00:06": since the pause, or since tracking was lost; nil while scanning.
    public func pausedText(now: Date) -> String? {
      let since: Date?
      switch livePhase {
      case .paused: since = pausedAt
      case .trackingLost:
        if case .lost(let lostSince) = tracking { since = lostSince } else { since = nil }
      case .scanning, .stopped: return nil
      }
      guard let since else { return nil }
      return "Paused · \(CaptureText.elapsed(now.timeIntervalSince(since)))"
    }

    /// The recording line under the scan and the colour of its dot.
    public var recordingStatus: (text: String, dot: RowStatusValue.Kind?) {
      switch livePhase {
      case .stopped:
        return ("Recording stopped", .missing)
      case .paused, .trackingLost:
        return ("Recording paused · \(CaptureText.plural(progress.counts.walls, "wall", "walls")) kept", .partly)
      case .scanning:
        // Five seconds without any depth sample or mesh anchor: say only the outline is kept.
        if progress.elapsed >= 5, progress.depthSampleCount == 0, progress.meshAnchorCount == 0 {
          return ("Recording the room outline only · saved on this phone", nil)
        }
        return ("Recording LiDAR depth and mesh · saved on this phone", nil)
      }
    }

    /// "Floor 1 · Whole floor".
    public var scanTitle: String {
      let label = draft.floorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      return "\(label) · \(draft.mode.map(CaptureFlowModel.modeTitle) ?? "")"
    }

    /// "06:42".
    public var elapsedText: String { CaptureText.elapsed(progress.elapsed) }

    /// Mode names as the design shows them.
    public static func modeTitle(_ mode: CaptureMode) -> String {
      CaptureText.modeTitle(mode)
    }

    // MARK: Private

    private func dropSession() async {
      await session?.cancel()
      eventTask?.cancel()
      eventTask = nil
      session = nil
    }

    private func handle(_ event: CaptureSessionEvent) {
      switch event {
      case .stateChanged(let state):
        sessionState = state
        // RoomPlan stopped on its own (too hot, tracking lost): say why, so the operator is not
        // left with a frozen timer and a Finish button that can only say "Nothing was captured".
        if case .failed(let message) = state { errorMessage = message }
      case .progress(let value): progress = value
      case .instruction(let value): instruction = value
      case .compass(let value): liveCompass = value
      case .tracking(let value): tracking = value
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
