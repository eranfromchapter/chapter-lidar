#if canImport(UIKit) && os(iOS)
  import CaptureContract
  import CaptureCore
  import ChapterUI
  import Foundation
  import SwiftUI

  /// The sample values of the v2 artboards (app-capture-v2, 2b): 618 Valley Street, Dana Ruiz,
  /// deal 4821, an iPhone 16 Pro, app 1.0.0 (37). The clock is fixed so every "ago" and timer
  /// is the same on every run.
  @MainActor
  enum CaptureScreenFixtures {
    /// Tue Oct 21, 2026 14:40:03 in New York.
    nonisolated static let now = Date(timeIntervalSince1970: 1_792_608_003)
    nonisolated static let newYork = TimeZone(identifier: "America/New_York")!

    static let project = HubProjectSummary(
      dealId: "4821", projectName: "618 Valley Street",
      address: "618 Valley Street, Montclair, NJ 07042", updatedAt: now.addingTimeInterval(-120))

    static let otherProjects = [
      HubProjectSummary(
        dealId: "4790", projectName: "424 West End Ave, Apt 4K",
        address: "424 West End Ave, Apt 4K, New York, NY 10024"),
      HubProjectSummary(dealId: "4802", projectName: "", address: "24 Shawnee Road, Ardmore, PA 19003"),
    ]

    /// A session that emits what a test gives it, so the live scan can be put in any state.
    final class ScriptedSession: CaptureSession, @unchecked Sendable {
      let events: AsyncStream<CaptureSessionEvent>
      private let continuation: AsyncStream<CaptureSessionEvent>.Continuation
      private let script: [CaptureSessionEvent]

      init(_ script: [CaptureSessionEvent]) {
        (events, continuation) = AsyncStream.makeStream(of: CaptureSessionEvent.self)
        self.script = script
      }

      func start(_ configuration: CaptureSessionConfiguration) async throws {
        for event in script { continuation.yield(event) }
      }
      func pause() async throws { continuation.yield(.stateChanged(.paused)) }
      func resume() async throws { continuation.yield(.stateChanged(.running)) }
      func finish() async throws -> CaptureSessionResult { throw CaptureSessionError.noRoomsCaptured }
      func cancel() async { continuation.finish() }
    }

    /// A compass whose pre-check returns `state` (FakeCompass only scripts its three cases).
    final class FixedCompass: CompassProviding {
      let state: CompassPrecheckState
      var isAvailable: Bool
      var authorization: CompassAuthorization
      let duration: Duration?

      init(
        _ state: CompassPrecheckState, isAvailable: Bool = true,
        authorization: CompassAuthorization = .authorized, duration: Duration? = nil
      ) {
        self.state = state
        self.isAvailable = isAvailable
        self.authorization = authorization
        self.duration = duration
      }

      func requestAuthorization() {}
      func precheck() async -> CompassPrecheckState {
        if let duration { try? await Task.sleep(for: duration) }
        return state
      }
      func openSettings() {}
      func startCameraHeading() {}
      func stopCameraHeading() {}
      func cameraSample() -> CompassCameraSample? { nil }
    }

    static func model(
      lidar: Bool = true, provider: HubProjectProvider? = nil,
      compass: (any CompassProviding)? = nil, existingAreaKeys: Set<String> = [],
      session: [CaptureSessionEvent] = []
    ) -> CaptureFlowModel {
      let draft = CaptureRecordDraft(
        operatorName: "Dana Ruiz",
        device: DeviceInfo(
          model: "iPhone17,1", marketingName: "iPhone 16 Pro", osName: .iOS, osVersion: "26.0.1",
          hasLidar: lidar),
        app: CaptureRecord.AppInfo(version: "1.0.0", build: "37"))
      return CaptureFlowModel(
        draft: draft,
        capabilities: DeviceCapabilities(
          model: "iPhone17,1", osName: .iOS, osVersion: "26.0.1",
          supportsSceneReconstructionMesh: lidar, roomPlanSupported: lidar),
        projectProvider: provider ?? StaticHubProjectProvider([project] + otherProjects, fetchedAt: now),
        originalsRoot: FileManager.default.temporaryDirectory.appendingPathComponent("CaptureUITests"),
        makeSession: { _ in ScriptedSession(session) }, compass: compass,
        existingAreaKeys: existingAreaKeys, clock: { now }, timeZone: newYork)
    }

    /// Step 1 with the project chosen and the address confirmed (artboard 2b-1).
    static func stepOne(
      provider: HubProjectProvider? = nil, confirmed: Bool = true, lidar: Bool = true
    ) async -> CaptureFlowModel {
      let model = model(lidar: lidar, provider: provider)
      await model.loadProjects()
      model.choose(project)
      if confirmed { model.setAddressConfirmed(true) }
      return model
    }

    /// Step 2 as drawn (artboard 2b-2): Floor 1, Whole floor, Primary closet · Locked, the
    /// coverage note and the compass pre-check of `compass`.
    static func stepTwo(
      compass: (any CompassProviding)?? = .none,
      existingAreaKeys: Set<String> = [], mode: CaptureMode? = .floor, filled: Bool = true,
      readCompass: Bool = true
    ) async -> CaptureFlowModel {
      // By default the drawn reading: verified 212° ±8° true, read 12 s ago.
      let compass = compass ?? FakeCompass(.verified, clock: { now.addingTimeInterval(-12) })
      let model = model(compass: compass, existingAreaKeys: existingAreaKeys)
      await model.loadProjects()
      model.choose(project)
      model.setAddressConfirmed(true)
      model.continueToSetup()
      model.draft.mode = mode
      if filled {
        model.addOmittedRoom(name: "Primary closet", reason: "locked")
        model.draft.coverageNotes = "Furniture covers the south wall of the living room."
      }
      if readCompass { await model.readCompassAgain() }
      return model
    }

    /// The live scan as drawn (artboard 2b-3): Floor 1 · Whole floor, 06:42, 11 walls, 4 doors,
    /// 6 windows, 3 rooms, the compass verified ±8° true; plus `extra` events (tracking lost…).
    static func liveScan(
      compass: CompassLiveState = .result(.verified(heading: 212.4, accuracy: 8), cameraBearing: 300),
      elapsed: TimeInterval = 402, extra: [CaptureSessionEvent] = [],
      counts: ScanCounts = ScanCounts(walls: 11, doors: 4, windows: 6, rooms: 3, openings: 2, objects: 14)
    ) async -> CaptureFlowModel {
      let progress = ScanProgress(
        counts: counts, elapsed: elapsed, depthSampleCount: 48_000, meshAnchorCount: 36)
      let model = model(
        session: [.stateChanged(.running), .compass(compass), .progress(progress)] + extra)
      await model.loadProjects()
      model.choose(project)
      model.setAddressConfirmed(true)
      model.draft.mode = .floor
      await model.startScan()
      for _ in 0..<500 where model.progress != progress || model.liveCompass != compass {
        await Task.yield()
      }
      for _ in 0..<200 { await Task.yield() }
      return model
    }

    // MARK: Captures home

    /// Artboard 2b-0: 618 Valley Street uploading 67 %, and three sealed captures.
    static var homeDrawn: CapturesHomeState {
      CapturesHomeState(
        rows: [
          .inProgress(
            id: "valley", title: "618 Valley Street", count: "2 floors",
            .uploading(bytes: "512 of 768 MB", fraction: 0.67), activity: now),
          .sealed(
            id: "west-end", title: "424 West End Ave, Apt 4K", revision: 1,
            sealedAt: Date(timeIntervalSince1970: 1_737_820_800), verdict: .limited,
            timeZone: newYork),
          .sealed(
            id: "shawnee", title: "24 Shawnee Road", revision: 2,
            sealedAt: Date(timeIntervalSince1970: 1_737_734_400), verdict: .ready,
            timeZone: newYork),
          .sealed(
            id: "maple", title: "17 Maple Court", revision: 1,
            sealedAt: Date(timeIntervalSince1970: 1_737_648_000), verdict: .blocked,
            timeZone: newYork),
        ],
        operatorName: "Dana Ruiz")
    }

    /// Every "In progress" case of critique R-28.
    static var homeEveryCase: CapturesHomeState {
      let cases: [(String, String, String, CapturesHomeState.Row.Progress)] = [
        ("a", "618 Valley Street", "2 floors", .notSealed),
        ("b", "424 West End Ave, Apt 4K", "1 floor and 1 room", .paused(bytes: "512 of 768 MB", fraction: 0.67)),
        ("c", "24 Shawnee Road", "1 floor", .signInRequired),
        ("d", "17 Maple Court", "3 floors", .uploadStopped),
        ("e", "9 Harbor View", "2 floors", .checking),
        ("f", "88 Linden Street", "2 floors", .revisionStarted(next: 2)),
      ]
      return CapturesHomeState(
        rows: cases.enumerated().map { index, item in
          .inProgress(
            id: item.0, title: item.1, count: item.2, item.3,
            activity: now.addingTimeInterval(-Double(index) * 60))
        },
        operatorName: "Dana Ruiz")
    }

    // MARK: Capture overview

    nonisolated static func overviewChecks(
      photos: (String, RowStatusValue) = ("Bath 2 has no photo", RowStatusValue(.missing, "Missing")),
      controls: (String, RowStatusValue) = (
        "Floor to floor and 1 landmark missing", RowStatusValue(.missing, "Missing")
      ),
      compass: (String, RowStatusValue) = (
        "Floor 1 verified · Floor 2 not read", RowStatusValue(.partly, "Partly")
      ),
      skipped: (String, RowStatusValue) = ("Primary closet · locked", RowStatusValue(.done, "Recorded"))
    ) -> [CaptureOverviewState.CheckRow] {
      [
        .init(.photos, subtitle: photos.0, status: photos.1),
        .init(.controls, subtitle: controls.0, status: controls.1),
        .init(.compass, subtitle: compass.0, status: compass.1),
        .init(.skippedRooms, subtitle: skipped.0, status: skipped.1),
      ]
    }

    nonisolated static let floor1 = CaptureOverviewState.FloorRow.scanned(
      areaKey: "floor-1", label: "Floor 1", mode: .floor, rooms: 12, photos: 42,
      controls: "complete", isDone: true)
    nonisolated static let floor2 = CaptureOverviewState.FloorRow.scanned(
      areaKey: "floor-2", label: "Floor 2", mode: .floor, rooms: 9, photos: 0,
      controls: "missing", isDone: false)

    static func overview(
      floors: [CaptureOverviewState.FloorRow] = [floor1, floor2],
      checks: [CaptureOverviewState.CheckRow] = overviewChecks(),
      sealState: CaptureOverviewState.SealState = .notSealed, canAddFloor: Bool = true,
      button: CaptureOverviewState.ReviewButton = .fix(items: 2)
    ) -> CaptureOverviewState {
      CaptureOverviewState(
        title: "618 Valley Street", dealId: "4821",
        subtitle: CaptureOverviewState.subtitle(
          visitedAt: now.addingTimeInterval(-5400), now: now, operatorName: "Dana Ruiz",
          sealState: sealState, timeZone: newYork),
        floors: floors, canAddFloor: canAddFloor, checks: checks, button: button)
    }
  }

  /// A screen pushed on a NavigationStack, as the app shows it (system back chevron, large
  /// title).
  struct Pushed<Screen: View>: View {
    let screen: Screen

    init(@ViewBuilder _ screen: () -> Screen) {
      self.screen = screen()
    }

    var body: some View {
      NavigationStack(path: .constant([1])) {
        Color.clear
          .navigationDestination(for: Int.self) { _ in screen }
      }
    }
  }
#endif
