#if canImport(UIKit) && os(iOS)
  import CaptureContract
  import CaptureCore
  @testable import CaptureUI
  import ChapterUI
  import ChapterUISnapshotTesting
  import SwiftUI
  import XCTest

  /// Every capture screen and state (phone-capture §10.2 items 1–5, compass §13.3 phone parts),
  /// drawn with ChapterUISnapshotTesting: a 402 × 874 pt window at scale 3 on the iPhone 17 Pro
  /// simulator with iOS 26.0. Compared with the artboards of app-capture-v2 (2b) in the PR's
  /// review checklist. Record with RECORD_SNAPSHOTS=1.
  @MainActor
  final class CaptureScreenSnapshotTests: ChapterSnapshotTestCase {
    typealias F = CaptureScreenFixtures

    // MARK: 1 Captures home (2b-0)

    func testHomeDrawn() {
      assertChapterSnapshot(
        of: NavigationStack { CapturesHomeScreen(state: F.homeDrawn, actions: .none) },
        named: "home-drawn")
    }

    func testHomeEveryInProgressCase() {
      assertChapterSnapshot(
        of: NavigationStack { CapturesHomeScreen(state: F.homeEveryCase, actions: .none) },
        named: "home-every-case")
    }

    func testHomeEmpty() {
      assertChapterSnapshot(
        of: NavigationStack {
          CapturesHomeScreen(state: CapturesHomeState(rows: [], operatorName: "Dana Ruiz"), actions: .none)
        },
        named: "home-empty")
    }

    func testHomeAtAX3() {
      assertChapterSnapshot(
        of: NavigationStack { CapturesHomeScreen(state: F.homeDrawn, actions: .none) },
        named: "home-ax3", contentSize: .accessibilityExtraLarge)
    }

    // MARK: 2 New capture (2b-1, 1b, 1c)

    func testNewCaptureDrawn() async {
      let model = await F.stepOne()
      assertChapterSnapshot(of: Pushed { NewCaptureScreen(model: model) }, named: "new-capture-drawn")
    }

    func testNewCaptureOffline() async {
      let saved = Date(timeIntervalSince1970: 1_792_519_920)  // Oct 20, 14:12 New York
      let twelve = [F.project] + (2...12).map {
        HubProjectSummary(dealId: "48\($0)", projectName: "Project \($0)", address: "\($0) Main Street")
      }
      let model = await F.stepOne(
        provider: StaticHubProjectProvider(twelve, fetchedAt: saved, isOfflineCopy: true))
      assertChapterSnapshot(of: Pushed { NewCaptureScreen(model: model) }, named: "new-capture-offline")
    }

    /// 1c behind its alert: the switch off and Continue disabled. The package harness cannot draw
    /// a system alert (no UIApplication); the alert's words, button order and actions are unit
    /// tests (`AddressDifferentAlertTests`, `testAddressAlertActions`), and the app's UI tests
    /// show it (U3).
    func testNewCaptureAddressDifferent() async {
      let model = await F.stepOne(confirmed: false)
      assertChapterSnapshot(
        of: Pushed { NewCaptureScreen(model: model, showsAddressAlert: true) },
        named: "new-capture-address-different")
    }

    func testNewCaptureNoProjectChosen() async {
      let model = F.model()
      await model.loadProjects()
      assertChapterSnapshot(
        of: Pushed { NewCaptureScreen(model: model) }, named: "new-capture-no-project")
    }

    func testNewCaptureDeviceGate() async {
      let model = await F.stepOne(lidar: false)
      assertChapterSnapshot(
        of: Pushed { NewCaptureScreen(model: model) }, named: "new-capture-device-gate")
    }

    func testNewCaptureOfflineWithoutSavedList() async {
      struct Offline: HubProjectProvider {
        func projects() async throws -> [HubProjectSummary] {
          throw HubProjectListingError.offlineWithoutSavedList
        }
        func listing() async throws -> HubProjectListing {
          throw HubProjectListingError.offlineWithoutSavedList
        }
      }
      let model = F.model(provider: Offline())
      await model.loadProjects()
      assertChapterSnapshot(
        of: Pushed { NewCaptureScreen(model: model) }, named: "new-capture-offline-no-list")
    }

    func testNewCaptureProjectListError() async {
      struct Failing: HubProjectProvider {
        struct Failure: LocalizedError {
          var errorDescription: String? { "The station answered 503." }
        }
        func projects() async throws -> [HubProjectSummary] { throw Failure() }
        func listing() async throws -> HubProjectListing { throw Failure() }
      }
      let model = F.model(provider: Failing())
      await model.loadProjects()
      assertChapterSnapshot(
        of: Pushed { NewCaptureScreen(model: model) }, named: "new-capture-list-error")
    }

    func testHubProjectSheet() async {
      let model = await F.stepOne()
      assertChapterSnapshot(of: HubProjectSheet(model: model), named: "hub-project-sheet")
    }

    /// The v1 app shell hosts step 1 in `CaptureFlowView`, with its account footer under it.
    func testCaptureFlowViewHostsStepOne() async {
      let model = await F.stepOne()
      assertChapterSnapshot(
        of: CaptureFlowView(model: model, preview: { EmptyView() }) {
          Text("Signed in as Dana Ruiz · Sign out")
            .chapterTextStyle(.footnote)
            .foregroundStyle(ChapterTheme.Color.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(ChapterTheme.Color.ground)
        },
        named: "flow-view-step-one")
    }

    // MARK: 3 What are you scanning? (2b-2, compass §5.1)

    private func stepTwo(_ model: CaptureFlowModel, named name: String, contentSize: UIContentSizeCategory = .large) {
      assertChapterSnapshot(
        of: Pushed { ScanSetupScreen(model: model) }, named: name, contentSize: contentSize)
    }

    func testScanSetupDrawn() async {
      stepTwo(await F.stepTwo(), named: "scan-setup-drawn")
    }

    func testScanSetupReading() async {
      // The pre-check never ends while the snapshot is drawn.
      let model = await F.stepTwo(
        compass: F.FixedCompass(.notCalibrated, duration: .seconds(600)), readCompass: false)
      stepTwo(model, named: "scan-setup-reading")
    }

    func testScanSetupApproximateMagnetic() async {
      let model = await F.stepTwo(
        compass: FakeCompass(.approximate, clock: { F.now.addingTimeInterval(-40) }), filled: false)
      stepTwo(model, named: "scan-setup-approximate")
    }

    func testScanSetupNotVerified() async {
      let model = await F.stepTwo(
        compass: F.FixedCompass(
          .result(heading: 212.4, accuracy: 42, source: .trueNorth, readAt: F.now.addingTimeInterval(-5))),
        filled: false)
      stepTwo(model, named: "scan-setup-not-verified")
    }

    func testScanSetupNotCalibrated() async {
      let model = await F.stepTwo(compass: FakeCompass(.none), mode: nil, filled: false)
      stepTwo(model, named: "scan-setup-not-calibrated")
    }

    func testScanSetupNoCompass() async {
      let model = await F.stepTwo(compass: FakeCompass(.verified, isAvailable: false), filled: false)
      stepTwo(model, named: "scan-setup-no-compass")
    }

    func testScanSetupLocationOff() async {
      let model = await F.stepTwo(
        compass: FakeCompass(.approximate, authorization: .denied, clock: { F.now }), filled: false)
      stepTwo(model, named: "scan-setup-location-off")
    }

    func testScanSetupAddingAFloorWithADuplicateName() async {
      let model = await F.stepTwo(existingAreaKeys: ["floor-1"], filled: false)
      model.draft.floorLabel = "Floor 1"
      stepTwo(model, named: "scan-setup-duplicate")
    }

    /// Adding a floor to a project without a HUB name: the caption is the whole address (R-29),
    /// here longer than the bar, so it is cut short with "…" before it reaches the back button.
    func testScanSetupAddingAFloorWithALongProjectTitle() async {
      let unnamed = HubProjectSummary(
        dealId: "4790", projectName: "", address: "1150 Fifth Avenue, Apartment 12B, New York, NY 10128")
      let model = await F.stepTwo(project: unnamed, existingAreaKeys: ["floor-1"], filled: false)
      XCTAssertEqual(model.scanSetupCaption, unnamed.address)
      stepTwo(model, named: "scan-setup-long-caption")
    }

    /// The caption's width, measured (a few cut letters are within the snapshot tolerance): a
    /// short title keeps its own width, a long one stops at `captureCaptionMaxWidth`.
    func testTheCaptionStopsBeforeTheBackButton() {
      func width(_ text: String, capped: Bool = true) -> CGFloat {
        let caption = Text(text).chapterTextStyle(.footnote).lineLimit(1)
        let view =
          capped
          ? AnyView(CappedWidth(maxWidth: captureCaptionMaxWidth) { caption }.fixedSize())
          : AnyView(caption.fixedSize())
        return UIHostingController(rootView: view.chapterRoot())
          .sizeThatFits(in: CGSize(width: 2000, height: 200)).width
      }
      let long = "1150 Fifth Avenue, Apartment 12B, New York, NY 10128"
      XCTAssertGreaterThan(width(long, capped: false), captureCaptionMaxWidth, "too long for the bar")
      XCTAssertLessThanOrEqual(width(long), captureCaptionMaxWidth)
      XCTAssertGreaterThan(width(long), captureCaptionMaxWidth - 12, "cut at the cap, not shorter")
      XCTAssertEqual(width("618 Valley Street"), width("618 Valley Street", capped: false), accuracy: 0.5)
      XCTAssertLessThan(width("618 Valley Street"), 150)
    }

    /// The keyboard is up while the name is typed: Start scan stays visible above it. (The
    /// stand-in goes on the pushed screen, where the system's keyboard region would be: an inset
    /// outside the NavigationStack does not reach its pushed screens.)
    func testScanSetupKeyboardUp() async {
      let model = await F.stepTwo(filled: false)
      assertChapterSnapshot(
        of: Pushed { KeyboardStandIn { ScanSetupScreen(model: model) } },
        named: "scan-setup-keyboard")
    }

    /// No compass from the host (the v1 app shell): no compass row, rather than a false "No
    /// compass on this phone".
    func testScanSetupWithoutACompass() async {
      let model = await F.stepTwo(compass: .some(nil), filled: false)
      XCTAssertFalse(model.hasCompass)
      stepTwo(model, named: "scan-setup-without-compass")
    }

    func testScanSetupAtAX3() async {
      stepTwo(await F.stepTwo(), named: "scan-setup-ax3", contentSize: .accessibilityExtraLarge)
    }

    // MARK: 4 Live scan (2b-3, 3b, compass §5.2)

    private func live(
      _ model: CaptureFlowModel, named name: String, contentSize: UIContentSizeCategory = .large
    ) {
      assertChapterSnapshot(
        of: LiveScanScreen(model: model) { EmptyView() }, named: name, contentSize: contentSize)
    }

    func testLiveScanDrawn() async {
      live(await F.liveScan(), named: "live-drawn")
    }

    func testLiveScanTrackingLost() async {
      let model = await F.liveScan(
        elapsed: 408, extra: [.tracking(.lost(since: F.now.addingTimeInterval(-6)))])
      live(model, named: "live-tracking-lost")
    }

    func testLiveScanPausedByTheOperator() async {
      let model = await F.liveScan()
      await model.togglePause()
      live(model, named: "live-paused")
    }

    func testLiveScanStopped() async {
      let model = await F.liveScan(
        extra: [.stateChanged(.failed(CaptureSessionError.tooHot.description))])
      live(model, named: "live-stopped")
    }

    func testLiveScanCompassStates() async {
      live(await F.liveScan(compass: .reading), named: "live-compass-reading")
      live(await F.liveScan(compass: .notVerified), named: "live-compass-not-verified")
      live(
        await F.liveScan(
          compass: .result(.approximate(heading: 212.4, accuracy: 12, source: .magnetic), cameraBearing: 300)),
        named: "live-compass-magnetic")
    }

    func testLiveScanAtAX3() async {
      let model = await F.liveScan(
        elapsed: 408, extra: [.tracking(.lost(since: F.now.addingTimeInterval(-6)))])
      live(model, named: "live-ax3", contentSize: .accessibilityExtraLarge)
    }

    func testLiveScanBeforeTheFirstWall() async {
      let model = await F.liveScan(
        compass: .reading, elapsed: 3, counts: ScanCounts())
      live(model, named: "live-first-seconds")
    }

    // MARK: 5 Capture overview (2b-4)

    private func overview(
      _ state: CaptureOverviewState, named name: String,
      contentSize: UIContentSizeCategory = .large
    ) {
      assertChapterSnapshot(
        of: Pushed { CaptureOverviewScreen(state: state, actions: .none) }, named: name,
        contentSize: contentSize)
    }

    func testOverviewAtAX3() {
      overview(F.overview(), named: "overview-ax3", contentSize: .accessibilityExtraLarge)
    }

    func testOverviewDrawn() {
      overview(F.overview(), named: "overview-drawn")
    }

    func testOverviewAllPassing() {
      let floor2 = CaptureOverviewState.FloorRow.scanned(
        areaKey: "floor-2", label: "Floor 2", mode: .floor, rooms: 9, photos: 31,
        controls: "complete", isDone: true)
      overview(
        F.overview(
          floors: [F.floor1, floor2],
          checks: F.overviewChecks(
            photos: ("Every room has a photo", RowStatusValue(.done, "Done")),
            controls: ("Minimum set complete", RowStatusValue(.done, "Done")),
            compass: ("Every floor verified", RowStatusValue(.done, "Verified")),
            skipped: ("All rooms scanned", RowStatusValue(.done, "Recorded"))),
          button: .reviewPackage),
        named: "overview-passing")
    }

    func testOverviewOneFloor() {
      overview(
        F.overview(
          floors: [F.floor1],
          checks: F.overviewChecks(
            photos: ("Every room has a photo", RowStatusValue(.done, "Done")),
            controls: ("Floor to floor and 1 landmark missing", RowStatusValue(.missing, "Missing")),
            compass: ("Floor 1 approximate", RowStatusValue(.partly, "Approx.")),
            skipped: ("Record skipped rooms, or confirm none were skipped", RowStatusValue(.missing, "Missing"))),
          button: .fix(items: 2)),
        named: "overview-one-floor")
    }

    func testOverviewSealedUploading() {
      overview(
        F.overview(sealState: .sealed(revision: 1), canAddFloor: false, button: .uploadStatus),
        named: "overview-sealed-uploading")
    }

    func testOverviewLoadingAndUnreadableFloors() {
      overview(
        F.overview(
          floors: [
            .loading(areaKey: "floor-1", label: "Floor 1"),
            .unreadable(areaKey: "floor-2", label: "Floor 2", mode: .floor),
          ]),
        named: "overview-loading")
    }
  }
#endif
