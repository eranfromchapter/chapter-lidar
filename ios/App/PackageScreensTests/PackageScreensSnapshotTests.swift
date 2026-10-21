#if canImport(UIKit) && os(iOS)
  import AppCore
  import CaptureContract
  import ChapterUI
  import ChapterUISnapshotTesting
  import PackageCore
  import SwiftUI
  import XCTest

  /// The package screens of artboard 2f (`canvas/app-package-v2.dc.html`; phone-package §13.4),
  /// drawn by the phone's one snapshot harness (critique R-18d): Package ready, Uploading paused,
  /// Uploaded, Upload stopped, Verdict received (Limited, Ready, Blocked, publishing, without the
  /// HUB link), Revision 2 and Revision 2 with nothing changed, and four screens at the
  /// accessibility text size (the long title wraps, the bar caption is whole).
  ///
  /// Hosted by ChapterUI's empty host app (target `PackageScreensSnapshotTests`, scheme
  /// `ChapterUISnapshots` in ios/project.yml), which draws the system chrome (back pill, bar
  /// caption) with `drawHierarchy`. The values are the drawn ones, as data: the screens compute
  /// every string themselves, so these images also check the wording.
  @MainActor
  final class PackageScreensSnapshotTests: ChapterSnapshotTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
      try super.setUpWithError()
      XCTAssertTrue(
        SnapshotRenderer.drawsWithRenderServer, "Run these tests hosted by ChapterUISnapshotHost")
      folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("package-screens-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
      try? FileManager.default.removeItem(at: folder)
      try super.tearDownWithError()
    }

    // MARK: Screen A · Package ready

    func testPackageReady() {
      assertChapterSnapshot(of: Pushed { PackageReadyView(state: Board.ready) }, named: "package-ready")
    }

    func testPackageReadyAtAccessibilityTextSize() {
      assertChapterSnapshot(
        of: Pushed { PackageReadyView(state: Board.ready) }, named: "package-ready-ax3",
        contentSize: .accessibilityExtraLarge)
    }

    func testPackageReadyWhileBuilding() {
      assertChapterSnapshot(
        of: Pushed {
          PackageReadyView(
            state: PackageReadyState(
              buildingSubtitle: "618 Valley Street \u{00B7} 2 floors \u{00B7} revision 1"))
        }, named: "package-ready-building")
    }

    func testPackageReadyBuildFailed() {
      assertChapterSnapshot(
        of: Pushed {
          PackageReadyView(
            state: PackageReadyState(
              buildingSubtitle: "618 Valley Street \u{00B7} 2 floors \u{00B7} revision 1",
              buildError: "The plans of Floor 2 could not be written: the model has no walls."),
            actions: PackageReadyActions(tryAgain: {}))
        }, named: "package-ready-build-failed")
    }

    /// One floor (one group, open, no chevron), so the error under the note is on screen.
    func testPackageReadySealFailed() {
      var state = Board.ready
      state.review?.exportGroups.removeLast()
      state.review?.captureCountText = "1 floor"
      state.review?.manifestEntries = 37
      state.review?.totalBytes = 500_000_000
      state.review?.compassText = "compass: not recorded"
      state.sealError = SealFailureText.make(reason: "no space left on the phone")
      assertChapterSnapshot(
        of: Pushed { PackageReadyView(state: state) }, named: "package-ready-seal-failed")
    }

    // MARK: Screen B · Package status

    func testUploadingPausedOffline() throws {
      let board = try Board.uploading(in: folder)
      assertChapterSnapshot(
        of: Pushed {
          PackageStatusView(
            packageId: board.packageId, snapshot: board, options: Board.statusOptions)
        }, named: "uploading-paused")
    }

    func testUploadingAtAccessibilityTextSize() throws {
      let board = try Board.uploading(in: folder)
      assertChapterSnapshot(
        of: Pushed {
          PackageStatusView(
            packageId: board.packageId, snapshot: board, options: Board.statusOptions)
        }, named: "uploading-paused-ax3", contentSize: .accessibilityExtraLarge)
    }

    func testUploadedChecksQueued() throws {
      let board = try Board.uploaded(in: folder, station: Board.station(.checksQueued))
      assertChapterSnapshot(
        of: Pushed {
          PackageStatusView(
            packageId: board.packageId, snapshot: board, options: Board.statusOptions)
        }, named: "uploaded")
    }

    func testUploadStopped() throws {
      let board = try Board.stopped(in: folder)
      assertChapterSnapshot(
        of: Pushed {
          PackageStatusView(
            packageId: board.packageId, snapshot: board, options: Board.statusOptions,
            actions: PackageStatusActions(retry: {}, reseal: {}))
        }, named: "upload-stopped")
    }

    // MARK: Screen C · Verdict received

    private func verdict(
      _ outcome: VerdictOutcome, published: Bool = true, hubLink: Bool = true, name: String,
      contentSize: UIContentSizeCategory = .large
    ) throws {
      var board = try Board.verdict(outcome, published: published, in: folder)
      if !hubLink { board.station?.links?.hub = nil }
      var options = Board.statusOptions
      options.now = Board.time("2026-05-20T09:00:00Z").date
      assertChapterSnapshot(
        of: Pushed {
          PackageStatusView(
            packageId: board.packageId, snapshot: board, options: options,
            actions: PackageStatusActions(addToCapture: {}, openInHub: { _ in }))
        }, named: name, contentSize: contentSize)
    }

    func testVerdictLimited() throws { try verdict(.limited, name: "verdict-limited") }
    func testVerdictAtAccessibilityTextSize() throws {
      try verdict(.limited, name: "verdict-limited-ax3", contentSize: .accessibilityExtraLarge)
    }
    func testVerdictReady() throws { try verdict(.ready, name: "verdict-ready") }
    func testVerdictBlocked() throws { try verdict(.blocked, name: "verdict-blocked") }
    func testVerdictWhilePublishing() throws {
      try verdict(.limited, published: false, name: "verdict-publishing")
    }
    /// A station without the HUB deal URL: no "Open in the HUB" (critique Q-C).
    func testVerdictWithoutTheHubLink() throws {
      try verdict(.limited, hubLink: false, name: "verdict-no-hub-link")
    }

    // MARK: Screen D · Revision n

    func testRevision2() {
      assertChapterSnapshot(
        of: Pushed {
          RevisionReviewView(
            state: RevisionReviewState(
              changes: Board.revision2, projectTitle: "424 West End Ave, Apt 4K"))
        }, named: "revision-2")
    }

    func testRevision2AtAccessibilityTextSize() {
      assertChapterSnapshot(
        of: Pushed {
          RevisionReviewView(
            state: RevisionReviewState(
              changes: Board.revision2, projectTitle: "424 West End Ave, Apt 4K"))
        }, named: "revision-2-ax3", contentSize: .accessibilityExtraLarge)
    }

    func testRevision2WithNothingChanged() {
      var changes = Board.revision2
      changes.rows = []
      changes.addedPaths = []
      changes.draftEntries = changes.baseEntries
      assertChapterSnapshot(
        of: Pushed {
          RevisionReviewView(
            state: RevisionReviewState(changes: changes, projectTitle: "424 West End Ave, Apt 4K"))
        }, named: "revision-2-empty")
    }
  }

  /// A pushed screen of the app's NavigationStack (the system back pill shows).
  private struct Pushed<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
      self.content = content()
    }

    var body: some View {
      NavigationStack(path: .constant([1])) {
        Color.clear
          .navigationDestination(for: Int.self) { _ in content }
      }
    }
  }

  /// The drawn values of artboard 2f.
  @MainActor
  private enum Board {
    static let utc = TimeZone(identifier: "UTC")!

    static func time(_ text: String) -> UTCTimestamp { UTCTimestamp(rawValue: text)! }

    static let statusOptions = PackageStatusOptions(
      notificationsAllowed: true, canReseal: true, now: time("2026-05-16T15:00:00Z").date,
      timeZone: utc)

    private static let mb: Int64 = 1_000_000

    // MARK: Package ready (screen 1)

    static var ready: PackageReadyState {
      func group(_ label: String, _ key: String, bytes: Int64) -> PackageReview.ExportGroup {
        PackageReview.ExportGroup(
          areaKey: key, label: label, fileCount: 13, bytes: bytes,
          rows: [
            .init(kind: .plans, label: "Plan DXF \u{00B7} rooms CSV \u{00B7} plan sheet PDF, PNG, SVG", count: 5),
            .init(kind: .meshes, label: "Mesh GLB \u{00B7} OBJ + MTL \u{00B7} textures", count: 4),
            .init(
              kind: .raw, label: "Point cloud LAS \u{00B7} raw RoomPlan + depth \u{00B7} capture model",
              count: 4),
          ])
      }
      return PackageReadyState(
        buildingSubtitle: "618 Valley Street \u{00B7} 2 floors \u{00B7} revision 1",
        review: PackageReview(
          address: "618 Valley Street", captureCountText: "2 floors", revision: 1,
          exportGroups: [
            group("Floor 1", "floor-1", bytes: 312 * mb), group("Floor 2", "floor-2", bytes: 268 * mb),
          ],
          photoCount: 42, photoBytes: 188 * mb, controlCount: 9, compassText: "compass: Floor 1 only",
          manifestEntries: 74, totalBytes: 768 * mb))
    }

    // MARK: Package status (screen 2)

    /// A sealed package whose manifest lists `files` (the bytes are not on disk: the screens read
    /// only the manifest and the upload state).
    private static func sealed(
      _ files: [(String, FileRole, Int64)], revision: Int = 1, sealedAt: String, in folder: URL
    ) throws -> SealedPackage {
      let visitId = LowercaseUUID()
      let manifest = PackageManifest(
        packageId: LowercaseUUID(), visitId: visitId, revision: revision,
        supersedesPackageId: revision > 1 ? LowercaseUUID() : nil, sealedAt: time(sealedAt),
        files: files.map { path, role, bytes in
          PackageManifest.FileEntry(
            path: path, role: role, sha256: String(repeating: "a", count: 64), bytes: bytes,
            mime: "application/octet-stream", generator: "chapter-capture-ios/Board",
            generatorVersion: "2.0.0")
        })
      let root = folder.appendingPathComponent(manifest.packageId.rawValue, isDirectory: true)
      let register = root.appendingPathComponent("Source Register/\(visitId.rawValue)", isDirectory: true)
      try FileManager.default.createDirectory(at: register, withIntermediateDirectories: true)
      try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(manifest)
        .write(to: register.appendingPathComponent("manifest.json"))
      return try SealedPackage.open(at: root)
    }

    /// 768 MB in four categories: plans and record 228 MB, site photos 188 MB, meshes 234 MB, point
    /// clouds 118 MB.
    private static let files: [(String, FileRole, Int64)] = [
      ("Source Register/capture-record.json", .captureRecord, 1 * mb),
      ("Original Exports/floor-1/plan-sheet.pdf", .planPDF, 120 * mb),
      ("Original Exports/floor-2/plan-sheet.pdf", .planPDF, 107 * mb),
      ("Site Photos/floor-1/photo-0001.jpg", .photo, 100 * mb),
      ("Site Photos/floor-2/photo-0001.jpg", .photo, 88 * mb),
      ("Original Exports/floor-1/mesh.glb", .meshGLB, 96 * mb),
      ("Original Exports/floor-1/mesh.obj", .meshOBJ, 138 * mb),
      ("Original Exports/floor-1/points.las", .pointCloudLAS, 118 * mb),
    ]

    private static func summary(_ package: SealedPackage, address: String, title: String)
      -> SealedPackageSummary
    {
      SealedPackageSummary(
        packageId: package.packageId, revision: package.manifest.revision,
        sealedAt: package.manifest.sealedAt, address: address, projectTitle: title,
        captureCountText: "2 floors", fileCount: 74, totalBytes: 768 * mb)
    }

    /// Screen 2 as drawn: paused offline, 512 of 768 MB, meshes 41%.
    static func uploading(in folder: URL) throws -> UploadSnapshot {
      let package = try sealed(files, sealedAt: "2026-05-16T14:01:00Z", in: folder)
      var state = UploadState(package: package, dealId: "4821")
      for index in state.files.indices {
        switch package.manifest.files[index].role {
        case .captureRecord, .planPDF, .photo: state.files[index].phase = .verified
        case .meshGLB: state.files[index].phase = .uploaded
        default: break
        }
      }
      state.registeredAt = time("2026-05-16T14:02:00Z")
      return UploadSnapshot(
        packageId: package.packageId,
        package: summary(package, address: "618 Valley Street", title: "618 Valley Street"),
        state: state, activity: .waitingToRetry(.offline), manifest: package.manifest)
    }

    static func station(
      _ stage: StationPackageStage, checks: StationPackageInfo.Checks? = nil,
      publication: StationPackageInfo.Publication? = nil, verdictId: LowercaseUUID? = nil
    ) -> StationPackageInfo {
      StationPackageInfo(
        stage: stage, createdAt: time("2026-05-16T14:02:00Z"), checks: checks,
        publication: publication,
        links: .init(
          review: "https://review.hellochapter.com/packages/1",
          hub: "https://hub.hellochapter.com/deals/4821"),
        verdictId: verdictId)
    }

    static func uploaded(
      in folder: URL, station: StationPackageInfo, verdict: VerdictStatus? = nil,
      address: String = "618 Valley Street", title: String = "618 Valley Street",
      sealedAt: String = "2026-05-16T14:01:00Z"
    ) throws -> UploadSnapshot {
      let package = try sealed(files, sealedAt: sealedAt, in: folder)
      var state = UploadState(package: package, dealId: "4821")
      for index in state.files.indices { state.files[index].phase = .verified }
      state.registeredAt = time("2026-05-16T14:02:00Z")
      state.sealResult = PackageSealResult(
        packageId: package.packageId, visitId: package.visitId, dealId: "4821", revision: 1,
        status: .checksQueued, createdAt: time("2026-05-16T14:02:00Z"), files: [])
      return UploadSnapshot(
        packageId: package.packageId, package: summary(package, address: address, title: title),
        state: state, activity: .confirmed, station: station, verdict: verdict,
        manifest: package.manifest)
    }

    static func stopped(in folder: URL) throws -> UploadSnapshot {
      var snapshot = try uploading(in: folder)
      let plan = "Original Exports/floor-2/plan-sheet.pdf"
      if let index = snapshot.state.files.firstIndex(where: { $0.path == plan }) {
        snapshot.state.files[index].phase = .pending
      }
      return UploadSnapshot(
        packageId: snapshot.packageId, package: snapshot.package, state: snapshot.state,
        activity: .failed("plan-sheet.pdf changed on the phone after sealing. It was not uploaded."),
        stoppedPath: plan,
        manifest: try SealedPackage.open(
          at: folder.appendingPathComponent(snapshot.packageId.rawValue)
        ).manifest)
    }

    // MARK: Verdict received (screen 3)

    static func verdict(_ outcome: VerdictOutcome, published: Bool, in folder: URL) throws
      -> UploadSnapshot
    {
      let actions: [VerdictStatus.NextVisit]
      switch outcome {
      case .ready:
        actions = []
      case .limited:
        actions = [
          .init(
            action: "Scan or measure Primary closet on the next visit if it is in scope.",
            reason: "Primary closet: inaccessible"),
          .init(
            action: "Tape-measure the Room 4 ceiling height.",
            reason: "Ceiling partly captured \u{00B7} height is approx."),
        ]
      case .blocked:
        actions = [
          .init(action: "Scan Floor 2 again: the scan has no walls.", reason: "Floor 2: no walls"),
          .init(action: "Tape-measure the Room 4 ceiling height.", reason: nil),
          .init(action: "Photograph the electrical panel.", reason: "No photo of the panel"),
          .init(action: "Read the compass at the start of each floor's scan.", reason: nil),
        ]
      }
      let verdict = VerdictStatus(
        verdictId: LowercaseUUID(), outcome: outcome, task: "Preliminary existing-condition plans",
        limitationCount: outcome == .limited ? 2 : 0, blockerCount: outcome == .blocked ? 1 : 0,
        nextVisit: actions, evaluatedAt: time("2026-05-16T14:02:00Z"))
      let station = station(
        .verdictReady,
        checks: .init(status: .completed, finishedAt: time("2026-05-16T14:01:00Z")),
        publication: published
          ? .init(status: .published, publishedAt: time("2026-05-16T14:03:00Z"))
          : .init(status: .publishing),
        verdictId: verdict.verdictId)
      return try uploaded(
        in: folder, station: station, verdict: verdict, address: "424 West End Ave, Apt 4K",
        title: "424 West End Ave, Apt 4K", sealedAt: "2025-01-25T15:00:00Z")
    }

    // MARK: Revision 2 (screen 4)

    static var revision2: RevisionChanges {
      RevisionChanges(
        baseRevision: 1, revision: 2,
        rows: [
          .init(
            kind: .added, subject: .capture, title: "Primary closet",
            detail: "Scanned \u{00B7} one room \u{00B7} 5 files"),
          .init(
            kind: .added, subject: .fieldControl, title: "Room 4 ceiling height",
            detail: "Field control \u{00B7} 2,490 mm \u{00B7} 8' 2\"", method: .tape),
          .init(
            kind: .added, subject: .photos, title: "3 photos",
            detail: "Primary closet \u{00B7} general, ceiling, opening"),
        ],
        addedPaths: (1...8).map { "new-\($0)" }, changedPaths: [], unchangedPaths: [],
        removedPaths: [], bytesToUpload: 12 * mb, baseEntries: 75, draftEntries: 83,
        unchanged: .init(captureLabels: ["Floor 1"], photos: 42, controls: 9))
    }
  }
#endif
