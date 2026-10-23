import AppCore
import CaptureContract
import CaptureCore
import Foundation
import Observation
import PackageCore
import UIKit

/// One screen pushed on the app's NavigationStack (phone-capture §3.0). The Captures home is
/// the stack's root; a visit's routes come from its `VisitFlow` (`VisitModel.routes`), and a
/// floor's scan or a v1 visit's scans are pushed on top (`HomeModel.extra`).
enum AppRoute: Hashable {
  /// New capture, step 1 of a new visit.
  case newCapture
  /// What are you scanning?, step 2 (a new visit's, or a further floor's).
  case scanSetup
  /// The Capture overview.
  case overview
  /// The photo step (viewfinder, then Label a photo).
  case photos
  /// Field controls.
  case controls
  /// Before you leave.
  case checklist
  /// Package ready (revision 1).
  case packageReady
  /// Revision n.
  case revisionReady
  /// Package status, then Verdict received.
  case packageStatus(LowercaseUUID)
  /// One floor's scan (`ScanViewer`), by area key, from the overview's floor row.
  case floor(String)
  /// The scans of a v1 visit without a capture record, by workspace id.
  case legacyScans(String)
  /// One of those scans: its workspace id and its folder path.
  case legacyScan(workspaceId: String, path: String)
}

/// The Captures home and the navigation from it: which visit is open, the routes pushed on top
/// of it, the uploads' latest snapshots and the rows read from disk (`CaptureLibrary`).
@MainActor
@Observable
final class HomeModel {
  private(set) var state: CapturesHomeState
  /// The visit on screen (its overview, field screens, package screens), if any.
  private(set) var visit: VisitModel?
  /// Routes pushed beyond the visit's own: a floor's scan, or a v1 visit's scans.
  private(set) var extra: [AppRoute] = []
  /// The newest snapshot of each package's upload, as the coordinators report them.
  private(set) var snapshots: [LowercaseUUID: UploadSnapshot] = [:]
  /// The operator allowed the verdict notification (the package screens' footnote).
  private(set) var notificationsAllowed = true
  /// A visit that could not be opened, said in an alert on the home.
  var alertMessage: String?

  @ObservationIgnored let services: AppServices
  @ObservationIgnored let operatorInfo: SignedInOperator
  /// The station's next-revision notices of the visits in revision mode (phone-package §10.4).
  /// The home's, not a visit's: a change made just before its visit closes is still sent.
  @ObservationIgnored let revisionNotices: RevisionNoticeSchedule
  @ObservationIgnored private weak var app: AppModel?
  @ObservationIgnored private var visits: [CaptureLibraryVisit] = []
  @ObservationIgnored private var isRefreshing = false

  init(app: AppModel, services: AppServices, operatorInfo: SignedInOperator) {
    self.app = app
    self.services = services
    self.operatorInfo = operatorInfo
    revisionNotices = RevisionNoticeSchedule(
      sender: StationNextRevisionNotices(client: services.station),
      delay: services.revisionNoticeDelay)
    state = CapturesHomeState(rows: [], operatorName: operatorInfo.name, isLoading: true)
    snapshots = app.liveSnapshots
    reload()
  }

  var visitsRoot: URL { app?.visitsRoot ?? FileManager.default.temporaryDirectory }

  // MARK: Navigation

  /// The NavigationStack's path: the open visit's routes, then the ones pushed on top.
  var path: [AppRoute] { (visit?.routes ?? []) + extra }

  /// The stack popped (system back, swipe): the routes left are a prefix of `path`. Pops of the
  /// routes on top only drop them; a pop into the visit's routes is the visit's own back
  /// (`VisitModel.popRoutes`); popping all of it closes the visit.
  func setPath(_ newPath: [AppRoute]) {
    let current = path
    guard newPath.count < current.count, Array(current.prefix(newPath.count)) == newPath else {
      return
    }
    let visitCount = visit?.routes.count ?? 0
    if newPath.count >= visitCount {
      extra = Array(newPath.dropFirst(visitCount))
      return
    }
    extra = []
    guard let visit else { return }
    if newPath.isEmpty || !visit.popRoutes(to: newPath.count) {
      closeVisit()
    }
  }

  /// "New capture": step 1 of a new visit. Nothing is written until its first Start scan.
  func newCapture() {
    extra = []
    visit?.close()
    do {
      visit = try VisitModel(
        newIn: visitsRoot, services: services, operatorInfo: operatorInfo, home: self)
    } catch {
      alertMessage = "A new capture could not be started: \(error)"
    }
  }

  /// A Captures home row: the Capture overview (in progress), Verdict received (sealed), or the
  /// scans of a v1 visit that kept no capture record.
  func open(_ row: CapturesHomeState.Row) {
    guard let entry = visits.first(where: { $0.workspace.id == row.id }) else { return }
    extra = []
    if entry.isLegacyScansOnly {
      visit?.close()
      visit = nil
      extra = [.legacyScans(entry.workspace.id)]
      return
    }
    if let reason = entry.unreadable {
      // Its newest sealed package stays reachable (its upload and verdict go on); else why.
      visit?.close()
      visit = nil
      if let newest = entry.newestPackage {
        extra = [.packageStatus(newest.packageId)]
      } else {
        alertMessage = "This capture could not be read: \(reason). Its files stay on this phone."
      }
      return
    }
    guard let opened = openVisit(entry) else { return }
    if row.destination == .verdict, let newest = entry.newestPackage {
      opened.showPackage(newest.packageId, atRoot: true)
    }
  }

  /// A tapped "Verdict: …" notification (`PackageRouter.openPackage(id:)`): that package's
  /// Package status, or Verdict received once the verdict is known. The open visit is never
  /// closed under the operator's hands (`PackageOpening`): while it has work to lose (a live
  /// scan, an unsaved New capture, a photo not saved) or is being revised, the package goes on
  /// top of the screen and Back returns to it; during a live scan it is there once the scan ends.
  func openPackage(id: LowercaseUUID) {
    if visits.allSatisfy({ !$0.packages.contains { $0.packageId == id } }) { reload() }
    guard let entry = visits.first(where: { $0.packages.contains { $0.packageId == id } }) else {
      return
    }
    let open = visit
    let holdsIt = open?.workspace == entry.workspace
    switch PackageOpening.decide(
      hasOpenVisit: open != nil, openVisitHoldsIt: holdsIt,
      openVisitShowsIt: holdsIt && open?.canShowPackage(id) == true,
      openVisitHasWorkToLose: open?.hasWorkToLose == true)
    {
    case .inOpenVisit:
      extra = []
      open?.showPackage(id, atRoot: false)
    case .onTop:
      if extra.last != .packageStatus(id) { extra.append(.packageStatus(id)) }
    case .openItsVisit:
      extra = []
      if let opened = openVisit(entry) {
        if opened.canShowPackage(id) {
          opened.showPackage(id, atRoot: true)
        } else {
          // Its visit is being revised: the package over its overview.
          extra = [.packageStatus(id)]
        }
      } else {
        // Its visit cannot be opened (an unreadable visit.json): the package on its own.
        visit = nil
        extra = [.packageStatus(id)]
      }
    }
  }

  /// A package pushed on top of the visit's own screens (`openPackage`) is closed: back to
  /// what was under it ("Continue revision n" on it, or Back).
  func closePackageOnTop(_ id: LowercaseUUID) {
    extra.removeAll { $0 == .packageStatus(id) }
  }

  /// The app came back to the foreground: the next-revision notices go again (§10.4).
  func appBecameActive() {
    Task { await revisionNotices.flush() }
  }

  /// Closes the open visit and lists the captures again.
  func closeVisit() {
    visit?.close()
    visit = nil
    extra = []
    reload()
  }

  /// Pushes a floor's scan on top of the overview.
  func openFloor(areaKey: String) {
    extra = [.floor(areaKey)]
  }

  /// Pushes one scan of a v1 visit.
  func openLegacyScan(_ scan: ScanItem, workspaceId: String) {
    extra.append(.legacyScan(workspaceId: workspaceId, path: scan.folder.path))
  }

  private func openVisit(_ entry: CaptureLibraryVisit) -> VisitModel? {
    guard let file = entry.file else { return nil }
    visit?.close()
    do {
      let opened = try VisitModel(
        resuming: entry.workspace, file: file, packages: entry.packages, services: services,
        operatorInfo: operatorInfo, home: self)
      visit = opened
      return opened
    } catch {
      alertMessage =
        "This capture could not be opened: \(error). Its files stay on this phone."
      return nil
    }
  }

  // MARK: Rows

  /// The visits as last read from disk.
  var visitsOnDisk: [CaptureLibraryVisit] { visits }

  /// Re-reads the visits from disk and builds the rows with the live snapshots.
  func reload() {
    visits = CaptureLibrary.visits(visitsRoot: visitsRoot)
    rebuildRows()
  }

  private func rebuildRows() {
    let rows = visits.compactMap { CaptureLibrary.row(for: $0, live: snapshots) }
    state = CapturesHomeState(
      rows: rows, operatorName: operatorInfo.name,
      hasPendingUploads: (app?.pendingUploadCount ?? 0) > 0)
  }

  /// On appear, when the app becomes active and on pull to refresh: the disk, then the station
  /// about every package it confirmed that has no verdict yet (its status cache and the
  /// notification), then the disk again.
  func refresh() async {
    reload()
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    notificationsAllowed = await VerdictNotifier.shared.notificationsAllowed()
    let items = StationStatusRefresh.followed(visitsRoot: visitsRoot)
    guard !items.isEmpty else { return }
    let outcome = await StationStatusRefresh.refresh(
      items, source: StationStatusSource(client: services.station))
    for notification in outcome.notifications {
      VerdictNotifier.shared.post(notification)
      let store = items.first { $0.package.packageId == notification.packageId }?.store
      try? store?.markNotified(notification.verdictId)
    }
    reload()
  }

  /// A coordinator's new snapshot: the rows, the package screens and the open visit follow.
  func uploadChanged(_ snapshot: UploadSnapshot) {
    snapshots[snapshot.packageId] = snapshot
    rebuildRows()
  }

  // MARK: Packages

  /// The package's latest snapshot (nil until `preparePackage` ran).
  func snapshot(for packageId: LowercaseUUID) -> UploadSnapshot? {
    snapshots[packageId]
  }

  /// Makes sure the package's coordinator runs (it resumes the upload, or follows the station
  /// until the verdict and its publication), so its screen has a snapshot.
  func preparePackage(_ packageId: LowercaseUUID) {
    guard let app else { return }
    if let running = app.runningCoordinator(for: packageId) {
      snapshots[packageId] = running.snapshot
      return
    }
    guard let package = visits.lazy.flatMap(\.packages).first(where: { $0.packageId == packageId })
      ?? visit?.packages.first(where: { $0.packageId == packageId })
    else { return }
    let dealId = SealedPackageSummary.captureRecord(of: package)?.hub.dealId ?? ""
    snapshots[packageId] = app.coordinator(for: package, dealId: dealId).snapshot
  }

  /// The coordinator of a sealed package (sealing starts it).
  func coordinator(for package: SealedPackage, dealId: String) -> UploadCoordinator? {
    guard let app else { return nil }
    let coordinator = app.coordinator(for: package, dealId: dealId)
    snapshots[package.packageId] = coordinator.snapshot
    return coordinator
  }

  func runningCoordinator(for packageId: LowercaseUUID) -> UploadCoordinator? {
    app?.runningCoordinator(for: packageId)
  }

  // MARK: v1 scans

  /// The scans of a v1 visit kept without a capture record, newest first.
  func legacyScans(workspaceId: String) -> [ScanItem] {
    guard let entry = visits.first(where: { $0.workspace.id == workspaceId }) else { return [] }
    let names = (try? VisitRoomNames.load(from: entry.workspace)) ?? VisitRoomNames()
    return entry.legacyScans.compactMap { scan in
      ScanLibrary.item(
        folder: scan.folder, title: ScanLibrary.title(areaKey: scan.areaKey),
        roomNames: names.captures[scan.folder.lastPathComponent] ?? [])
    }
  }

  /// The home row's title of a v1 visit kept without a capture record.
  func legacyTitle(workspaceId: String) -> String {
    state.inProgress.first { $0.id == workspaceId }?.title ?? "Scan"
  }

  // MARK: Account

  func signOut() {
    guard let app else { return }
    Task { await app.signOut() }
  }

  #if DEBUG
    /// The account dialog offers "Delete all photos" (field-test and UI-test modes only).
    var offersPhotoDeletion: Bool { app?.photoDeletion != nil }

    /// "Delete all photos", confirmed: erases them (`AppModel.deleteAllPhotos`) and lists the
    /// captures again. Returns the line to show.
    func deleteAllPhotos() async -> String {
      guard let app else { return DeletePhotosText.result(deleted: 0) }
      let message = await app.deleteAllPhotos()
      snapshots = app.liveSnapshots
      reload()
      return message
    }
  #endif
}
