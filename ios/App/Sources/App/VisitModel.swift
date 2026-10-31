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
import SketchEntry
import SketchReading
import SketchSolver
import UIKit
import WalkthroughUI

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
  /// How do you want to measure? of a capture without LiDAR (spec F15 2): set when the capture
  /// screens' step 1 continues with the sketch purpose, nil again at Finish floor.
  private(set) var methodModel: MeasureMethodModel?
  /// The sketch screens of the floor being drawn (spec F14): What are you drawing from?,
  /// Rooms and measurements, Check. Set when How do you want to measure? continues with
  /// "Enter from a sketch", nil again at Finish floor.
  private(set) var sketchModel: SketchEntryModel?
  /// "Photograph a sketch" of the floor being captured (spec F16): the photo, Claude's reading,
  /// the one length and Check. Set when How do you want to measure? continues with the photo,
  /// nil again at Finish floor, Back to How to measure, or "Enter it by hand".
  private(set) var sketchPhotoModel: SketchPhotoModel?
  /// The AR walkthrough of the floor being walked (spec F15): the walk (a full-screen cover),
  /// Check the scale and Check. Set when How do you want to measure? continues with the walk,
  /// nil again at Finish floor or when the walk is left.
  private(set) var walkthroughModel: WalkthroughModel?
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

  /// A new capture at "New capture". Its workspace folder is created by the first Start scan
  /// (or, for a sketch capture, when its rooms screen opens), so an abandoned New capture
  /// leaves nothing on the phone. `sketch`: the Captures home's "Capture without LiDAR".
  init(
    newIn visitsRoot: URL, services: AppServices, operatorInfo: SignedInOperator, home: HomeModel,
    sketch: Bool = false
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
    captureModel = makeCaptureModel(
      draft: newDraft(), existingAreaKeys: [], purpose: sketch ? .sketch : .scan)
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
    if captureModel != nil || methodModel != nil || sketchModel != nil || walkthroughModel != nil
      || sketchPhotoModel != nil || renaming != nil
    {
      return true
    }
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
      let first = flow.captures.isEmpty && !flow.isRevisionMode
      if captureModel?.purpose == .sketch {
        // A capture without LiDAR after step 1 (spec F15 2): How do you want to measure? as
        // soon as step 1 continues (its model follows a moment later), then the sketch screens
        // (spec F14 2.4) or the walkthrough's (the walk itself is a full-screen cover).
        if first, captureModel?.step == .newCapture { return [.newCapture] }
        let base: [AppRoute] = first ? [.newCapture, .measureMethod] : [.overview, .measureMethod]
        if let sketchModel {
          switch sketchModel.step {
          case .source: return base + [.sketchSource]
          case .rooms: return base + [.sketchSource, .sketchRooms]
          case .check, .finished: return base + [.sketchSource, .sketchRooms, .sketchCheck]
          }
        }
        if let photo = sketchPhotoModel {
          switch photo.phase {
          case .source: return base + [.photoSource]
          case .reading, .problem: return base + [.photoSource, .photoReading]
          case .oneLength: return base + [.photoSource, .photoLength]
          case .check, .finished:
            return base + [.photoSource] + (photo.needsOneLength ? [.photoLength] : []) + [.photoCheck]
          }
        }
        if let walkthroughModel {
          switch walkthroughModel.phase {
          case .walking: return base
          case .scale: return base + [.walkthroughScale]
          case .check, .finished: return base + [.walkthroughScale, .walkthroughCheck]
          }
        }
        return base
      }
      if first {
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
      case .scanSetup, .measureMethod:
        if flow.step == .scan { try? flow.scanCancelled() }
        methodModel = nil
        sketchModel = nil
        sketchPhotoModel?.cancelReading()
        sketchPhotoModel = nil
        walkthroughModel = nil
        if flow.captures.isEmpty && !flow.isRevisionMode {
          captureModel?.back()
        } else {
          try? flow.cancelAddFloor()
          captureModel = nil
        }
      case .sketchSource:
        // Back to How do you want to measure?.
        if flow.step == .scan { try? flow.scanCancelled() }
        sketchModel = nil
      case .photoSource:
        // Back to How do you want to measure?.
        sketchPhotoModel?.cancelReading()
        sketchPhotoModel = nil
      case .photoReading:
        if sketchPhotoModel?.phase == .reading {
          sketchPhotoModel?.cancelReading()
        } else {
          sketchPhotoModel?.retake()
        }
      case .photoLength:
        sketchPhotoModel?.retake()
      case .photoCheck:
        sketchPhotoModel?.backFromCheck()
      case .sketchRooms:
        sketchModel?.backToSource()
      case .sketchCheck:
        sketchModel?.backToRooms()
      case .walkthroughScale:
        walkthroughModel?.backToWalking()
      case .walkthroughCheck:
        walkthroughModel?.backToScale()
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
  /// one of a new capture), a cancelled scan goes back to step 2. Step 1 of a capture without
  /// LiDAR continues into How do you want to measure? instead (`methodModel`).
  func captureStepChanged(_ step: CaptureFlowStep?) {
    if step == .scanSetup, captureModel?.purpose == .sketch {
      makeMethodModel()
      return
    }
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

  /// Follows the sketch screens' step (spec F14 2.4): the rooms screen opening is the floor's
  /// "Start scan" (the workspace folder, `VisitFlow.scanStarted`); back to the source screen
  /// cancels it.
  func sketchStepChanged(_ step: SketchEntryStep?) {
    switch (step, flow.step) {
    case (.rooms?, .captureRecord):
      do {
        try workspace.createFolder()
        try flow.scanStarted()
      } catch {
        message = String(describing: error)
      }
    case (.source?, .scan):
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

  private func makeCaptureModel(
    draft: CaptureRecordDraft, existingAreaKeys: Set<String>, purpose: CaptureFlowPurpose = .scan
  ) -> CaptureFlowModel {
    CaptureFlowModel(
      draft: draft, capabilities: services.capabilities,
      projectProvider: StationProjectProvider(store: services.projects),
      originalsRoot: workspace.originalsRoot, makeSession: services.makeSession,
      compass: services.compass, existingAreaKeys: existingAreaKeys, purpose: purpose,
      onFinished: { [weak self] result in self?.floorRecordFinished(result.record) })
  }

  /// How do you want to measure? for the floor step 1 describes: the draft's label, mode and
  /// units, the visit's area keys and the capture record's area-key rule.
  private func makeMethodModel() {
    guard let capture = captureModel, methodModel == nil else { return }
    let draft = capture.draft
    methodModel = MeasureMethodModel(
      canWalk: services.canWalk, floorLabel: draft.floorLabel, mode: draft.mode ?? .floor,
      displayUnits: draft.displayUnits, existingAreaKeys: Set(flow.captures.map(\.areaKey)),
      areaKey: { CaptureRecordDraft.areaKey(for: $0) })
  }

  /// How do you want to measure?'s Continue: the sketch screens (spec F14), or the AR walk
  /// (spec F15), which is the floor's "Start scan" (the workspace folder, `VisitFlow`).
  func continueFromMethod() {
    guard let method = methodModel, method.canContinue else { return }
    switch method.method {
    case .photo:
      guard sketchPhotoModel == nil, let areaKey = method.areaKey,
        let interpreter = services.sketchInterpreter
      else { return }
      sketchPhotoModel = SketchPhotoModel(
        visitId: flow.record?.visitId ?? LowercaseUUID(), floorLabel: method.cleanedLabel,
        areaKey: areaKey, mode: method.mode ?? .floor, displayUnits: method.displayUnits,
        notice: services.sketchReaderNotice, interpreter: interpreter)
    case .sketch:
      makeSketchModel()
    case .walk:
      guard walkthroughModel == nil, let areaKey = method.areaKey else { return }
      do {
        try workspace.createFolder()
        if flow.step == .captureRecord { try flow.scanStarted() }
      } catch {
        message = String(describing: error)
        return
      }
      let captureId = LowercaseUUID()
      walkthroughModel = WalkthroughModel(
        visitId: flow.record?.visitId ?? LowercaseUUID(), captureId: captureId,
        floorLabel: method.cleanedLabel, areaKey: areaKey, mode: method.mode ?? .floor,
        displayUnits: method.displayUnits, session: services.makeWalkthroughSession(),
        videoURL: FileManager.default.temporaryDirectory.appendingPathComponent(
          "walkthrough-\(captureId.rawValue).mp4"))
    }
  }

  /// True while the AR walk covers the screen.
  var isWalking: Bool { walkthroughModel?.phase == .walking }

  /// "Leave" on the AR walk: the walk and its recording are dropped; How do you want to
  /// measure? again.
  func leaveWalkthrough() {
    guard let walk = walkthroughModel else { return }
    walkthroughModel = nil
    if flow.step == .scan { try? flow.scanCancelled() }
    Task { await walk.cancel() }
  }

  /// "Finish floor" on the walkthrough's Check (spec F15 2): the recording finishes, the log
  /// is converted and solved once more, the capture record of the floor gets
  /// `captureSource: walkthrough`, the solver's `sketch` summary and the converter's
  /// `walkthrough` summary (no compass field), and `walkthrough-log.json`,
  /// `sketch-measurements.json` and `walkthrough.mp4` (when recorded) are written into the
  /// capture's folder; then the visit goes on as after a scanned floor.
  func finishWalkthroughFloor() {
    guard let walk = walkthroughModel, let capture = captureModel, !walk.isFinishing else { return }
    walk.isFinishing = true
    Task { @MainActor in
      defer { walk.isFinishing = false }
      do {
        let finished = try await walk.finish()
        var draft = capture.draft
        draft.floorLabel = walk.floorLabel
        draft.mode = walk.mode
        draft.displayUnits = walk.displayUnits
        let now = UTCTimestamp.now()
        var record = try draft.build(
          visitId: walk.visitId, captureId: walk.captureId, visitedAt: finished.log.startedAt,
          capturedAt: finished.log.startedAt)
        record.captures[0].finishedAt = now
        record.captures[0].captureSource = .walkthrough
        record.captures[0].sketch = finished.result.summary
        record.captures[0].walkthrough = finished.conversion.summary
        try workspace.createFolder()
        try WalkthroughFloorWriter.write(
          log: finished.log, measurements: finished.conversion.measurements,
          video: finished.videoURL, to: builder.originalsDirectory(of: record.captures[0]))
        walk.markFinished()
        floorRecordFinished(record)
        walkthroughModel = nil
        methodModel = nil
        if let problem = finished.recordingProblem { message = problem }
      } catch {
        message = String(describing: error)
      }
    }
  }

  /// "Enter it by hand" after a photo that could not be read (spec F16 2): the F14 screens with
  /// the photo as the sketch and the floor, mode and units chosen for the photo.
  func enterSketchByHand() {
    guard let photo = sketchPhotoModel else { return }
    photo.cancelReading()
    methodModel?.choose(.sketch)
    sketchPhotoModel = nil
    makeSketchModel()
    guard let sketch = sketchModel else { return }
    sketch.floorLabel = photo.floorLabel
    sketch.mode = photo.mode
    sketch.setDisplayUnits(photo.displayUnits)
    if let image = photo.image { sketch.setImage(image, kind: photo.sourceKind) }
  }

  /// "Finish floor" on the sketch photo's Check (spec F16 2): the capture record of the floor
  /// with `captureSource: sketch` and the solver's summary; `sketch.<ext>` (the photo as
  /// taken), `sketch-interpretation.json` (what Claude read) and `sketch-measurements.json`
  /// (converted from it) written into the capture's folder; then the visit goes on as after a
  /// scanned floor.
  func finishSketchPhotoFloor() {
    guard let photo = sketchPhotoModel, let capture = captureModel, !photo.isFinishing else { return }
    guard let result = photo.result ?? photo.solve(), let measurements = photo.measurements,
      let interpretation = photo.interpretation
    else {
      message = photo.solveError ?? "The sketch has no model to finish."
      return
    }
    photo.isFinishing = true
    defer { photo.isFinishing = false }
    var draft = capture.draft
    draft.floorLabel = photo.floorLabel
    draft.mode = photo.mode
    draft.displayUnits = photo.displayUnits
    do {
      let now = UTCTimestamp.now()
      var record = try draft.build(
        visitId: photo.visitId, captureId: photo.captureId, visitedAt: now, capturedAt: now)
      record.captures[0].finishedAt = now
      record.captures[0].captureSource = .sketch
      record.captures[0].sketch = result.summary
      try workspace.createFolder()
      _ = try SketchFloorWriter.write(
        measurements: measurements, image: photo.image, interpretation: interpretation,
        to: builder.originalsDirectory(of: record.captures[0]))
      photo.markFinished()
      floorRecordFinished(record)
      sketchPhotoModel = nil
      methodModel = nil
    } catch {
      message = String(describing: error)
    }
  }

  /// The sketch screens' model for the floor step 1 describes: the capture record draft's
  /// label, mode and units, the visit's ids, and the capture record's area-key rule.
  private func makeSketchModel() {
    guard let capture = captureModel, sketchModel == nil else { return }
    let draft = capture.draft
    sketchModel = SketchEntryModel(
      visitId: flow.record?.visitId ?? LowercaseUUID(), floorLabel: draft.floorLabel,
      mode: draft.mode, displayUnits: draft.displayUnits,
      existingAreaKeys: Set(flow.captures.map(\.areaKey)),
      areaKey: { CaptureRecordDraft.areaKey(for: $0) })
  }

  /// The right-hand caption of a screen of a capture without LiDAR: "Step N of 5", or the
  /// project title when adding a floor, as step 2 of a scan has it.
  func sketchCaption(step: Int) -> String {
    flow.captures.isEmpty ? "Step \(step) of 5" : (flow.record.map(ProjectTitle.of) ?? "")
  }

  /// The fixture photo standing in for the camera on the sketch source screen (UI tests);
  /// nil on the phone, which uses its camera.
  var fixedPhoto: (@Sendable () async throws -> Data)? {
    if case .fixed(let source) = services.photoSource { return source }
    return nil
  }

  /// "Finish floor" on the Check screen (spec F14 2.4): the capture record of the floor with
  /// `captureSource: sketch` and the solver's summary, the originals (`sketch.<ext>` and
  /// `sketch-measurements.json`) written into the capture's folder, then the visit goes on as
  /// after a scanned floor (photos, the overview).
  func finishSketchFloor() {
    guard let sketch = sketchModel, let capture = captureModel, !sketch.isFinishing else { return }
    guard let result = sketch.result ?? sketch.solve() else {
      message = sketch.solveError
      return
    }
    sketch.isFinishing = true
    defer { sketch.isFinishing = false }
    var draft = capture.draft
    draft.floorLabel = sketch.floorLabel
    draft.mode = sketch.mode
    draft.displayUnits = sketch.displayUnits
    do {
      let now = UTCTimestamp.now()
      var record = try draft.build(
        visitId: sketch.visitId, captureId: sketch.captureId, visitedAt: now, capturedAt: now)
      record.captures[0].finishedAt = now
      record.captures[0].captureSource = .sketch
      record.captures[0].sketch = result.summary
      try workspace.createFolder()
      _ = try SketchFloorWriter.write(
        measurements: sketch.measurements, image: sketch.image,
        to: builder.originalsDirectory(of: record.captures[0]))
      sketch.markFinished()
      floorRecordFinished(record)
      sketchModel = nil
      methodModel = nil
    } catch {
      message = String(describing: error)
    }
  }

  /// A finished floor (a scan's `CaptureFlowResult`, or a sketch floor): its one capture joins
  /// the visit and the photo step opens.
  private func floorRecordFinished(_ floorRecord: CaptureRecord) {
    do {
      if flow.step == .captureRecord { try flow.scanStarted() }
      try flow.floorFinished(floorRecord)
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
  /// area keys refused. On a phone that cannot scan the floor is captured without LiDAR
  /// instead: How do you want to measure? (spec F14, F15: a visit can mix scanned, walked and
  /// sketched floors).
  func addFloor(sketch: Bool? = nil) {
    guard let record = flow.record else { return }
    let sketch = sketch ?? !DeviceGate.evaluate(services.capabilities).isSupported
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
      draft: draft, existingAreaKeys: Set(record.captures.map(\.areaKey)),
      purpose: sketch ? .sketch : .scan)
    next.step = .scanSetup
    captureModel = next
    methodModel = nil
    sketchModel = nil
    walkthroughModel = nil
    if sketch { makeMethodModel() }
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
