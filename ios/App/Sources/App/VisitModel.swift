import AppCore
import CaptureContract
import CaptureCore
import CaptureModelMapping
import CaptureUI
import FieldKitUI
import FieldRules
import Foundation
import Observation
import PackageCore
import PhotoStore
import PlanExport
import UIKit

/// One visit on screen: a new capture, or one reopened from the Captures home. All rules live
/// in AppCore (`VisitFlow`, `OverviewBuilder`, `VisitPackageBuilder`, `UploadCoordinator`); this
/// class owns the screen models, calls them, keeps `visit.json` current (`VisitStore`) and says
/// which screens are on the navigation stack (`routes`).
@MainActor
@Observable
final class VisitModel {
  private(set) var flow: VisitFlow
  /// New capture / What are you scanning? / Live scan of the floor being added.
  private(set) var captureModel: CaptureFlowModel?
  private(set) var photoModel: PhotoLabelingModel?
  private(set) var controlsModel: FieldControlsModel?
  /// Package ready's plan (revision 1).
  private(set) var plan: VisitPackagePlan?
  /// Revision n's plan (revision mode).
  private(set) var revisionPlan: VisitRevisionPlan?
  private(set) var isBuilding = false
  private(set) var buildError: String?
  private(set) var isSealing = false
  private(set) var sealError: String?
  private(set) var isResealing = false
  private(set) var resealError: String?
  /// An error of the capture or field screens, shown at the bottom.
  private(set) var message: String?
  /// The rooms of every capture with the operator's names (`room-names.json`).
  private(set) var rooms: VisitRooms
  /// Each capture's scan for the overview: loading, mapped, or unreadable.
  private(set) var scans: [LowercaseUUID: OverviewBuilder.FloorScan] = [:]
  /// The saved photos (copied from the store when a field screen closes, so the overview and
  /// the checklist follow).
  private(set) var photos: [PhotoRecord]
  private(set) var controls: FieldControls?
  /// The visit's sealed packages, oldest first.
  private(set) var packages: [SealedPackage]
  /// Package status was opened on its own (a Sealed row, a notification): Back leaves the visit.
  private(set) var packageAtRoot = false
  /// "Rename rooms", from the photo step (that capture) or Before you leave (every capture).
  var renaming: RoomNamingDraft?

  @ObservationIgnored let services: AppServices
  @ObservationIgnored let workspace: VisitWorkspace
  @ObservationIgnored private let operatorInfo: SignedInOperator
  @ObservationIgnored private weak var home: HomeModel?
  @ObservationIgnored private let photoStore: PhotoRecordStore
  @ObservationIgnored private let builder: VisitPackageBuilder
  @ObservationIgnored private let appInfo: CaptureRecord.AppInfo
  @ObservationIgnored private let createdAt: UTCTimestamp
  @ObservationIgnored private var revisionStartedAt: UTCTimestamp?
  @ObservationIgnored private var mapping: Task<Void, Never>?
  @ObservationIgnored private var cachedVerdicts: [LowercaseUUID: VerdictStatus] = [:]

  /// A new capture at "New capture". Its workspace folder is created by the first Start scan,
  /// so an abandoned New capture leaves nothing on the phone.
  init(
    newIn visitsRoot: URL, services: AppServices, operatorInfo: SignedInOperator, home: HomeModel
  ) throws {
    self.services = services
    self.workspace = VisitWorkspace.allocate(in: visitsRoot)
    self.operatorInfo = operatorInfo
    self.home = home
    flow = VisitFlow()
    photoStore = try PhotoRecordStore(files: DiskPhotoFileStore(root: workspace.photosRoot))
    appInfo = Self.appInfo
    builder = VisitPackageBuilder(workspace: workspace, appVersion: appInfo.version)
    rooms = VisitRooms(builder: builder)
    photos = []
    packages = []
    createdAt = .now()
    captureModel = makeCaptureModel(draft: newDraft(), existingAreaKeys: [])
  }

  /// A visit read back from its `visit.json`: at the Capture overview, its scans mapped in the
  /// background ("Loading…" until then), its controls, photos and room names from the folder.
  /// Throws when its photo index cannot be read (an empty one would hide the saved photos and
  /// put new ones beside them unlisted).
  init(
    resuming workspace: VisitWorkspace, file: VisitFile, packages: [SealedPackage],
    services: AppServices, operatorInfo: SignedInOperator, home: HomeModel
  ) throws {
    self.services = services
    self.workspace = workspace
    self.operatorInfo = operatorInfo
    self.home = home
    self.packages = packages
    flow = file.flow(sealedRevision: packages.last?.manifest.revision)
    photoStore = try PhotoRecordStore(files: DiskPhotoFileStore(root: workspace.photosRoot))
    appInfo = Self.appInfo
    builder = VisitPackageBuilder(workspace: workspace, appVersion: appInfo.version)
    rooms = VisitRooms(builder: builder)
    photos = photoStore.records
    createdAt = file.createdAt
    revisionStartedAt = file.revision?.startedAt
    controls =
      (try? VisitStore.loadControls(workspace, visitId: file.record.visitId))
      ?? FieldControlsEditor(visitId: file.record.visitId).controls
    for package in packages {
      cachedVerdicts[package.packageId] = (try? StationStatusStore(packageRoot: package.root).load())?
        .verdict
    }
    mapCaptures()
    // The station may have missed the notice of a revision begun before the app was closed.
    revisionChanged()
  }

  private static var appInfo: CaptureRecord.AppInfo {
    CaptureRecord.AppInfo.from(bundle: .main) ?? CaptureRecord.AppInfo(version: "0.0.0", build: "0")
  }

  /// Stops background work when the visit leaves the screen. A next-revision notice still
  /// waiting is sent all the same (`RevisionNoticeSchedule` belongs to the home).
  func close() {
    mapping?.cancel()
  }

  /// Work that closing the visit now would lose, so a tapped notification must not replace it
  /// (`HomeModel.openPackage`): a live scan (its originals are written at Finish floor), New
  /// capture or What are you scanning? before the scan, a photo taken and not saved, a field
  /// control or room names being typed.
  var hasWorkToLose: Bool {
    if captureModel != nil || renaming != nil { return true }
    switch flow.step {
    case .photos: return photoModel?.pendingOriginal != nil
    case .controls: return controlsModel?.entry != nil
    default: return false
    }
  }

  // MARK: Navigation (phone-capture §3.0, §5.3)

  /// The visit's screens on the NavigationStack, derived from the flow.
  var routes: [AppRoute] {
    switch flow.step {
    case .captureRecord, .scan:
      if flow.captures.isEmpty && !flow.isRevisionMode {
        let step = captureModel?.step ?? .newCapture
        return step == .newCapture ? [.newCapture] : [.newCapture, .scanSetup]
      }
      return [.overview, .scanSetup]
    case .overview:
      return [.overview]
    case .photos:
      return [.overview] + (flow.returnsToChecklist ? [.checklist] : []) + [.photos]
    case .controls:
      return [.overview] + (flow.returnsToChecklist ? [.checklist] : []) + [.controls]
    case .checklist:
      return [.overview, .checklist]
    case .packageReady:
      return [.overview, .packageReady]
    case .revisionReady:
      return [.overview, .revisionReady]
    case .packageStatus(let id):
      return packageAtRoot ? [.packageStatus(id)] : [.overview, .packageStatus(id)]
    }
  }

  /// The system back popped the stack down to `count` routes: the flow goes back with it.
  /// False when nothing of the visit is left on the stack (the home closes it).
  func popRoutes(to count: Int) -> Bool {
    guard count > 0 else { return false }
    var guardCount = 0
    while routes.count > count, guardCount < 4 {
      guardCount += 1
      switch routes.last {
      case .scanSetup:
        if flow.captures.isEmpty && !flow.isRevisionMode {
          captureModel?.back()
        } else {
          try? flow.cancelAddFloor()
          captureModel = nil
        }
      case .photos:
        photosDone()
      case .controls:
        controlsDone()
      case .checklist, .packageReady, .revisionReady, .packageStatus:
        packageAtRoot = false
        try? flow.backToOverview()
      case .newCapture, .overview, .floor, .legacyScans, .legacyScan, nil:
        return false
      }
    }
    return !routes.isEmpty
  }

  /// Follows the capture screens' own step: Start scan creates the workspace folder (the first
  /// one of a new capture), a cancelled scan goes back to step 2.
  func captureStepChanged(_ step: CaptureFlowStep?) {
    switch (step, flow.step) {
    case (.scanning?, .captureRecord):
      do {
        try workspace.createFolder()
        try flow.scanStarted()
      } catch {
        message = String(describing: error)
      }
    case (.scanSetup?, .scan), (.newCapture?, .scan):
      try? flow.scanCancelled()
    default:
      break
    }
  }

  /// True while the live scan covers the screen.
  var isScanning: Bool { captureModel?.step == .scanning }

  // MARK: Capture record and scan

  private func newDraft() -> CaptureRecordDraft {
    CaptureRecordDraft(
      operatorName: operatorInfo.name, operatorUserId: operatorInfo.userId,
      device: services.device, app: appInfo)
  }

  private func makeCaptureModel(draft: CaptureRecordDraft, existingAreaKeys: Set<String>)
    -> CaptureFlowModel
  {
    CaptureFlowModel(
      draft: draft, capabilities: services.capabilities,
      projectProvider: StationProjectProvider(store: services.projects),
      originalsRoot: workspace.originalsRoot, makeSession: services.makeSession,
      compass: services.compass, existingAreaKeys: existingAreaKeys,
      onFinished: { [weak self] result in self?.floorFinished(result) })
  }

  private func floorFinished(_ result: CaptureFlowResult) {
    do {
      if flow.step == .captureRecord { try flow.scanStarted() }
      try flow.floorFinished(result.record)
      guard let record = flow.record, let capture = record.captures.last else { return }
      if controls == nil {
        controls = FieldControlsEditor(visitId: record.visitId).controls
      }
      // The capture model with the visit's room names (a new capture has none yet; the scan's
      // own model in `result` never has them, so it is mapped here).
      if let model = try? rooms.load(capture, visitId: record.visitId) {
        scans[capture.captureId] = .mapped(ScanMeasurements(model: model))
      } else {
        scans[capture.captureId] = .failed
      }
      captureModel = nil
      plan = nil
      revisionPlan = nil
      makePhotoModel(captureId: capture.captureId, room: nil)
      message = nil
      save()
      revisionChanged()
    } catch {
      message = String(describing: error)
    }
  }

  /// "Call the PM" in the address-different alert: nothing was saved; back to the home.
  func discardNewCapture() {
    home?.closeVisit()
  }

  /// Maps every capture's scan in the background (a reopened visit), with the room names.
  private func mapCaptures() {
    guard let record = flow.record else { return }
    let start = rooms
    mapping = Task { [weak self] in
      let (mapped, results) = await Task.detached(priority: .userInitiated) {
        var rooms = start
        var results: [LowercaseUUID: OverviewBuilder.FloorScan] = [:]
        for capture in record.captures {
          if Task.isCancelled { break }
          if let model = try? rooms.load(capture, visitId: record.visitId) {
            results[capture.captureId] = .mapped(ScanMeasurements(model: model))
          } else {
            results[capture.captureId] = .failed
          }
        }
        return (rooms, results)
      }.value
      guard let self, !Task.isCancelled else { return }
      // A floor finished while mapping keeps what it has; the mapped rooms replace the empty
      // ones, or (rarely) the captures still missing are mapped here.
      for (captureId, scan) in results where self.scans[captureId] == nil {
        self.scans[captureId] = scan
      }
      if self.rooms.rooms.isEmpty {
        self.rooms = mapped
      } else {
        for capture in record.captures where self.rooms.rooms[capture.captureId] == nil {
          _ = try? self.rooms.load(capture, visitId: record.visitId)
        }
      }
    }
  }

  // MARK: Overview

  /// The Capture overview of this visit (OverviewBuilder), nil before the first floor.
  var overviewState: CaptureOverviewState? {
    guard let record = flow.record, let checklist else { return nil }
    return OverviewBuilder.make(
      OverviewBuilder.Input(
        record: record, rooms: roomLabels, scans: scans, photos: photos,
        controls: controls ?? FieldControlsEditor(visitId: record.visitId).controls,
        checklist: checklist, policy: .shipping, flow: flow,
        newestPackageHasVerdict: newestVerdict != nil))
  }

  /// A floor row: that floor's scan.
  func openFloor(areaKey: String) {
    home?.openFloor(areaKey: areaKey)
  }

  /// "Scan another floor or room" (overview, Package ready, Revision n): step 2 with the visit's
  /// project and the address confirmation carried over, the next free "Floor N", and the visit's
  /// area keys refused.
  func addFloor() {
    guard let record = flow.record else { return }
    do {
      try flow.addFloor()
    } catch {
      message = String(describing: error)
      return
    }
    plan = nil
    revisionPlan = nil
    var draft = newDraft()
    draft.select(
      HubProjectSummary(
        dealId: record.hub.dealId, projectName: record.hub.projectName ?? "",
        address: record.address.formatted))
    draft.setAddressConfirmed(true, at: UTCTimestamp.now())
    draft.displayUnits = record.captures.first?.units.display ?? draft.displayUnits
    let next = makeCaptureModel(
      draft: draft, existingAreaKeys: Set(record.captures.map(\.areaKey)))
    next.step = .scanSetup
    captureModel = next
  }

  /// A "Before you leave" row of the overview.
  func openCheck(_ check: CaptureOverviewState.CheckID) {
    do {
      switch check {
      case .photos:
        if flow.isReadOnly {
          // Sealed: the photos cannot change; Before you leave shows what was recorded.
          try flow.openChecklist(focus: .photoPerRoom)
        } else if let record = flow.record, let checklist,
          let target = OverviewBuilder.photoTarget(record: record, checklist: checklist)
        {
          try openPhotos(captureId: target.captureId, room: target.room)
        }
      case .controls:
        try flow.openControls()
        makeControlsModel()
      case .compass:
        try flow.openChecklist(focus: .compass)
      case .skippedRooms:
        try flow.openChecklist(focus: .skippedRoomsRecorded)
      }
    } catch {
      message = String(describing: error)
    }
  }

  /// The overview's bottom button.
  func review() {
    guard let state = overviewState else { return }
    switch state.button {
    case .fix:
      return
    case .reviewPackage, .reviewRevision:
      reviewPackage()
    case .uploadStatus, .openVerdict:
      guard let newest = packages.last else { return }
      showPackage(newest.packageId, atRoot: false)
    }
  }

  // MARK: Photos, controls, checklist

  private func option(for capture: CaptureRecord.Capture) -> FieldCaptureOption {
    var scan: ScanMeasurements?
    if case .mapped(let measured) = scans[capture.captureId] { scan = measured }
    return FieldCaptureOption(
      ref: FieldControls.CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey),
      label: capture.label, mode: capture.mode, capturedAt: capture.capturedAt,
      rooms: rooms.labels(of: capture.captureId), scan: scan,
      displayUnits: capture.units.display)
  }

  private var roomLabels: [LowercaseUUID: [String]] {
    var labels: [LowercaseUUID: [String]] = [:]
    for capture in flow.captures { labels[capture.captureId] = rooms.labels(of: capture.captureId) }
    return labels
  }

  private func openPhotos(captureId: LowercaseUUID, room: String?) throws {
    try flow.openPhotos(captureId: captureId, room: room)
    makePhotoModel(captureId: captureId, room: room)
  }

  private func makePhotoModel(captureId: LowercaseUUID, room: String?) {
    guard let capture = flow.captures.first(where: { $0.captureId == captureId }) else { return }
    switch services.photoSource {
    case .camera(let camera):
      photoModel = PhotoLabelingModel(
        capture: option(for: capture), store: photoStore, camera: camera, initialRoom: room,
        heading: services.photoHeading)
    case .fixed(let source):
      photoModel = PhotoLabelingModel(
        capture: option(for: capture), store: photoStore, initialRoom: room,
        heading: services.photoHeading, capturePhoto: source)
    }
  }

  /// "Done" on the viewfinder or "Done with photos": back to what opened the photo step.
  func photosDone() {
    photos = photoStore.records
    do { try flow.photosDone() } catch { message = String(describing: error) }
    revisionChanged()
  }

  private func makeControlsModel() {
    guard let record = flow.record else { return }
    let controls = self.controls ?? FieldControlsEditor(visitId: record.visitId).controls
    let refs = flow.captures.map {
      FieldControls.CaptureRef(captureId: $0.captureId, areaKey: $0.areaKey)
    }
    let root = workspace.controlsRoot
    controlsModel = FieldControlsModel(
      captures: flow.captures.map(option(for:)), controls: controls, policy: .shipping,
      isReadOnly: flow.isReadOnly, sealedRevision: flow.revision,
      persist: { [weak self] next in
        try FieldControlsFile.write(next, intoPackageRoot: root, knownCaptures: refs)
        self?.controls = next
        self?.revisionChanged()
      })
  }

  /// Back from Field controls.
  func controlsDone() {
    do { try flow.controlsDone() } catch { message = String(describing: error) }
  }

  /// FieldRules' checklist of the visit (Before you leave, and the overview's rows).
  var checklist: ChecklistReport? {
    guard let record = flow.record else { return nil }
    return ChecklistRules.evaluate(
      ChecklistInput(
        record: record, capturedRooms: roomLabels, photos: photos,
        controls: controls ?? FieldControlsEditor(visitId: record.visitId).controls,
        noRoomsSkippedConfirmed: flow.noRoomsSkippedConfirmed),
      policy: .shipping)
  }

  /// Before you leave's scroll target (the overview's Compass and Rooms not scanned rows).
  var checklistFocus: ChecklistItemID? {
    if case .checklist(let focus) = flow.step { return focus }
    return nil
  }

  /// The caption at the right of Before you leave's bar.
  var checklistCaption: String {
    flow.record.map(ChecklistRules.propertyCaption) ?? ""
  }

  /// "All rooms scanned" on Before you leave.
  func checklistConfirmNoRoomsSkipped() {
    do {
      try flow.confirmNoRoomsSkipped()
      save()
    } catch { message = String(describing: error) }
  }

  /// "Take photo" on a Before you leave row: the photo step for its first gap.
  func checklistTakePhoto(_ item: ChecklistItem) {
    var captureLabel: String?
    var room: String?
    for gap in item.gaps {
      if case .roomWithoutPhoto(let capture, let name) = gap {
        captureLabel = capture
        room = name
        break
      }
      if case .captureWithoutPhoto(let capture) = gap {
        captureLabel = capture
        break
      }
    }
    let capture = flow.captures.first { $0.label == captureLabel } ?? flow.captures.first
    guard let capture else { return }
    do { try openPhotos(captureId: capture.captureId, room: room) } catch {
      message = String(describing: error)
    }
  }

  /// "Add" on a Before you leave row: Field controls, with the entry sheet of its first gap.
  func checklistAddControls(_ item: ChecklistItem) {
    do {
      try flow.openControls()
      makeControlsModel()
      controlsModel?.focusFirstGap(of: item)
    } catch { message = String(describing: error) }
  }

  // MARK: Room names

  /// The "Rename rooms" sheet: the rooms of `captureId` (from the photo step), or of every
  /// capture (from the checklist), each marked when it still needs a photo. Nil when there is
  /// no room to rename, and after sealing.
  func roomNamingDraft(captureId: LowercaseUUID?) -> RoomNamingDraft? {
    guard !flow.isReadOnly else { return nil }
    let captures = flow.captures.filter { captureId == nil || $0.captureId == captureId }
    var focus: (captureId: LowercaseUUID, room: String)?
    if let captureId {
      if let model = photoModel, model.capture.ref.captureId == captureId,
        let room = model.targetRoom ?? model.coverage.roomsWithoutPhoto.first
      {
        focus = (captureId, room)
      }
    } else if let item = checklist?.item(.photoPerRoom) {
      for gap in item.gaps {
        guard case .roomWithoutPhoto(let captureLabel, let room) = gap,
          let capture = flow.captures.first(where: { $0.label == captureLabel })
        else { continue }
        focus = (capture.captureId, room)
        break
      }
    }
    let draft = rooms.draft(for: captures, photos: photoStore.records, focus: focus)
    return draft.isEmpty ? nil : draft
  }

  /// Saves the sheet's names: the visit's `room-names.json`, the capture models (and so the
  /// Floorplan, plans and checklist), the photos already labeled with an old name, and the field
  /// controls measured in a renamed room. Returns an error message for the sheet, nil when saved.
  func renameRooms(_ renames: [RoomRename]) -> String? {
    guard let record = flow.record, !renames.isEmpty else { return nil }
    let before = rooms.rooms
    let refs = flow.captures.map {
      FieldControls.CaptureRef(captureId: $0.captureId, areaKey: $0.areaKey)
    }
    let root = workspace.controlsRoot
    do {
      let result = try rooms.rename(
        renames, captures: record.captures, visitId: record.visitId, photos: photoStore,
        controls: controls,
        writeControls: { next in
          try FieldControlsFile.write(next, intoPackageRoot: root, knownCaptures: refs)
        })
      for (captureId, model) in result.models {
        scans[captureId] = .mapped(ScanMeasurements(model: model))
      }
      if let next = result.controls {
        controls = next
        if controlsModel != nil { makeControlsModel() }
      }
      if let photoModel {
        let captureId = photoModel.capture.ref.captureId
        photoModel.roomsRenamed(
          rooms: rooms.labels(of: captureId),
          renames: VisitRooms.labelChanges(
            before: before[captureId] ?? [], after: rooms.rooms[captureId] ?? []))
      }
      photos = photoStore.records
      plan = nil
      revisionPlan = nil
      message = nil
      revisionChanged()
      return nil
    } catch {
      return "The names could not be saved: \(String(describing: error))"
    }
  }

  // MARK: Package ready, Revision n

  /// The overview's "Review the package" / "Review revision n", or "Finish capture" on Before
  /// you leave: the checklist gate, then the plan of Package ready or Revision n.
  func reviewPackage() {
    guard let report = checklist else { return }
    do {
      try flow.reviewPackage(canFinish: report.canFinish)
    } catch {
      message = String(describing: error)
      return
    }
    buildPlan()
  }

  /// Builds the plan of the screen on top (Package ready or Revision n) off the main actor.
  func buildPlan() {
    guard let record = flow.record, !isBuilding else { return }
    let controls = self.controls ?? FieldControlsEditor(visitId: record.visitId).controls
    isBuilding = true
    buildError = nil
    sealError = nil
    let builder = self.builder
    let photos = photoStore.records
    let roomNames = rooms.names
    if flow.isRevisionMode {
      guard let base = packages.first(where: { $0.packageId == flow.basePackageId }) else {
        isBuilding = false
        buildError = "The sealed revision \(flow.revision - 1) is not on this phone."
        return
      }
      let nextActions = baseNextActions(base)
      Task {
        let result = await Task.detached(priority: .userInitiated) {
          Result {
            try builder.revisionPlan(
              base: base, record: record, photos: photos, controls: controls,
              roomNames: roomNames, baseNextActions: nextActions)
          }
        }.value
        isBuilding = false
        switch result {
        case .success(let plan):
          revisionPlan = plan
          // The review's own build: its notice goes now (phone-package §10.4).
          await home?.revisionNotices.built(
            plan.changes.notice(updatedAt: .now()), basePackageId: base.packageId)
        case .failure(let error): buildError = String(describing: error)
        }
      }
    } else {
      Task {
        let result = await Task.detached(priority: .userInitiated) {
          Result {
            try builder.plan(record: record, photos: photos, controls: controls, roomNames: roomNames)
          }
        }.value
        isBuilding = false
        switch result {
        case .success(let plan): self.plan = plan
        case .failure(let error): buildError = String(describing: error)
        }
      }
    }
  }

  /// Back from Package ready or Revision n ("Keep editing").
  func backToOverview() {
    packageAtRoot = false
    try? flow.backToOverview()
  }

  /// "Seal and upload" (revision 1) or "Seal revision n and upload": assembles the read-only
  /// package, then uploads it in the background and opens Package status.
  func seal() {
    guard !isSealing else { return }
    let draft: PackageDraft
    let dealId: String
    if flow.isRevisionMode {
      guard let revisionPlan else { return }
      draft = revisionPlan.draft
      dealId = revisionPlan.record.hub.dealId
    } else {
      guard let plan else { return }
      draft = plan.draft
      dealId = plan.record.hub.dealId
    }
    isSealing = true
    sealError = nil
    let destination = workspace.packageURL(packageId: draft.packageId.rawValue)
    let revisedBase = flow.isRevisionMode ? flow.basePackageId : nil
    Task {
      let result = await Task.detached {
        Result { try PackageAssembler().assemble(draft, at: destination) }
      }.value
      isSealing = false
      switch result {
      case .success(let sealed):
        do {
          try flow.sealed(packageId: sealed.packageId)
          packages.append(sealed)
          plan = nil
          revisionPlan = nil
          revisionStartedAt = nil
          save()
          _ = home?.coordinator(for: sealed, dealId: dealId)
          if let revisedBase {
            await home?.revisionNotices.stop(basePackageId: revisedBase)
          }
          if services.asksForNotifications { VerdictNotifier.shared.requestPermission() }
        } catch {
          sealError = SealFailureText.make(error)
        }
      case .failure(let error):
        sealError = SealFailureText.make(error)
      }
    }
  }

  /// Package ready's state: the plan's review once built, the build or seal error inline.
  var packageReadyState: PackageReadyState {
    let record = flow.record
    return PackageReadyState(
      buildingSubtitle: PackageReview.buildingSubtitle(
        address: record?.address.formatted ?? "",
        captureCountText: record.map(CaptureCountText.make) ?? "", revision: flow.revision),
      review: plan?.review, buildError: plan == nil && !isBuilding ? buildError : nil,
      isSealing: isSealing, sealError: sealError)
  }

  /// Revision n's state, once its plan is built.
  var revisionReviewState: RevisionReviewState? {
    guard let revisionPlan else { return nil }
    return RevisionReviewState(
      changes: revisionPlan.changes, projectTitle: flow.record.map(ProjectTitle.of) ?? "",
      isSealing: isSealing, sealError: sealError)
  }

  // MARK: Package status, Verdict received

  /// The newest revision's verdict, live or cached.
  var newestVerdict: VerdictStatus? {
    guard let newest = packages.last else { return nil }
    return home?.snapshot(for: newest.packageId)?.verdict ?? cachedVerdicts[newest.packageId]
  }

  /// The visit can show this package's status now (sealed, not in revision mode).
  func canShowPackage(_ packageId: LowercaseUUID) -> Bool {
    flow.isSealed && packages.contains { $0.packageId == packageId }
  }

  /// Package status (or Verdict received) of one of the visit's packages. `atRoot`: opened on
  /// its own (a Sealed row, a notification), so Back leaves the visit.
  func showPackage(_ packageId: LowercaseUUID, atRoot: Bool) {
    if flow.step != .overview { try? flow.backToOverview() }
    do {
      try flow.showPackage(packageId)
      packageAtRoot = atRoot
    } catch {
      message = String(describing: error)
    }
  }

  /// What Package status and Verdict received know about `packageId` besides its snapshot.
  func packageOptions(for packageId: LowercaseUUID, notificationsAllowed: Bool)
    -> PackageStatusOptions
  {
    var options = PackageStatusOptions()
    options.notificationsAllowed = notificationsAllowed
    options.canReseal = canReseal
    options.isResealing = isResealing
    options.resealError = resealError
    options.latestRevision = packages.last?.manifest.revision
    if flow.isRevisionMode {
      options.revision = .continueRevision(flow.revision)
    } else if packages.last?.packageId == packageId, newestVerdict != nil {
      options.revision = .add
    } else {
      options.revision = .hidden
    }
    return options
  }

  /// The visit still holds every capture's scan originals: Upload stopped can re-seal.
  var canReseal: Bool {
    guard let record = flow.record else { return false }
    return builder.hasOriginals(of: record)
  }

  /// "Add to this capture" on Verdict received (phone-package §5.2): revision n+1 of the
  /// newest sealed revision, editable at the Capture overview. "Continue revision n" when it is
  /// already open.
  func addToCapture() {
    if flow.isRevisionMode {
      packageAtRoot = false
      try? flow.backToOverview()
      return
    }
    guard let base = packages.last, newestVerdict != nil else { return }
    let record = SealedPackageSummary.captureRecord(of: base) ?? flow.record
    guard let record else { return }
    flow = VisitFlow(
      revisionOf: record, base: base.packageId, baseRevision: base.manifest.revision,
      noRoomsSkipped: flow.noRoomsSkipped)
    packageAtRoot = false
    revisionStartedAt = .now()
    controls =
      (try? VisitStore.loadControls(workspace, visitId: record.visitId)) ?? controls
    photos = photoStore.records
    save()
    revisionChanged()
  }

  /// "Re-seal as revision n+1" after Upload stopped (phone-package §4.2): a full build of the
  /// visit's files (not a carry-over: the sealed copy may be what failed), superseding the
  /// stopped package; its upload stops for good and the new one starts.
  func resealAfterFailure() {
    guard case .packageStatus(let stopped) = flow.step, !isResealing,
      let record = flow.record, let controls
    else { return }
    isResealing = true
    resealError = nil
    let builder = self.builder
    let photos = photoStore.records
    let roomNames = rooms.names
    let revision = flow.revision + 1
    let workspace = self.workspace
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        Result { () throws -> SealedPackage in
          let plan = try builder.rebuildPlan(
            revision: revision, supersedes: stopped, record: record, photos: photos,
            controls: controls, roomNames: roomNames)
          return try PackageAssembler().assemble(
            plan.draft, at: workspace.packageURL(packageId: plan.draft.packageId.rawValue))
        }
      }.value
      isResealing = false
      switch result {
      case .success(let sealed):
        do {
          try home?.runningCoordinator(for: stopped)?.supersede(by: sealed.packageId)
          try flow.resealAfterFailure(newPackageId: sealed.packageId)
          packages.append(sealed)
          save()
          _ = home?.coordinator(for: sealed, dealId: record.hub.dealId)
        } catch {
          resealError = SealFailureText.make(error)
        }
      case .failure(let error):
        resealError = SealFailureText.make(error)
      }
    }
  }

  // MARK: Next-revision notice (phone-package §10.4)

  /// Revision mode: something revision n would carry changed (a floor, a photo, a control, a
  /// room name), or the revision just began or was reopened. The home's schedule rebuilds the
  /// station's notice from the visit as it is now, 10 s after the last change; the web shows it
  /// as "Revision n · not sealed · on the phone". Best effort: never shown, never blocking.
  func revisionChanged() {
    guard flow.isRevisionMode, let record = flow.record, let baseId = flow.basePackageId,
      let base = packages.first(where: { $0.packageId == baseId }),
      let schedule = home?.revisionNotices
    else { return }
    let builder = self.builder
    let photos = photoStore.records
    let controls = self.controls ?? FieldControlsEditor(visitId: record.visitId).controls
    let roomNames = rooms.names
    let nextActions = baseNextActions(base)
    schedule.changed(basePackageId: baseId) {
      try await Task.detached(priority: .utility) {
        let plan = try builder.revisionPlan(
          base: base, record: record, photos: photos, controls: controls, roomNames: roomNames,
          baseNextActions: nextActions)
        // Only the notice is kept: Revision n builds its own files when it is reviewed.
        try? FileManager.default.removeItem(at: plan.draftFolder)
        return plan.changes.notice(updatedAt: .now())
      }.value
    }
  }

  /// The next actions of the base revision's verdict (`answersNextAction`, §10.4).
  private func baseNextActions(_ base: SealedPackage) -> [String] {
    (cachedVerdicts[base.packageId] ?? home?.snapshot(for: base.packageId)?.verdict)?
      .nextVisit.map(\.action) ?? []
  }

  // MARK: Floors

  /// One floor's scan, for the ScanViewer pushed from its overview row.
  func scanItem(areaKey: String) -> ScanItem? {
    guard let record = flow.record,
      let capture = record.captures.first(where: { $0.areaKey == areaKey })
    else { return nil }
    let item = ScanLibrary.item(
      folder: builder.originalsDirectory(of: capture), title: capture.label,
      address: record.address.formatted, displayUnits: capture.units.display,
      capturedAt: capture.capturedAt.date, captureLabel: capture.label,
      roomNames: rooms.names.names(for: capture.captureId))
    return item.map {
      var item = $0
      // The Floorplan's north symbol from the floor's own compass reading (compass §6.3).
      item.north = CompassState(capture)
      // The plan sheet's title block, as the package's plan-sheet.pdf has it.
      item.planContext = try? PlanExportContext(record: record, captureId: capture.captureId)
      return item
    }
  }

  // MARK: Persistence

  /// Writes `visit.json` (after every change of the record, the "All rooms scanned" tap, a
  /// seal or the revision mode).
  private func save() {
    guard let record = flow.record else { return }
    do {
      try VisitStore.save(
        VisitFile(
          flow: flow, record: record, createdAt: createdAt, now: .now(),
          revisionStartedAt: revisionStartedAt),
        to: workspace)
    } catch {
      message = String(describing: error)
    }
  }
}
