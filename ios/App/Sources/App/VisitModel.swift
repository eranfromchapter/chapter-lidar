import AppCore
import CaptureContract
import CaptureCore
import CaptureModelMapping
import FieldKitUI
import FieldRules
import Foundation
import Observation
import PackageCore
import PhotoStore

/// One site visit on screen. All rules live in AppCore (`VisitFlow`, `VisitPackageBuilder`,
/// `UploadCoordinator`); this class owns the screen models and calls them.
@MainActor
@Observable
final class VisitModel {
  private(set) var flow = VisitFlow()
  private(set) var captureModel: CaptureFlowModel? = nil
  private(set) var photoModel: PhotoLabelingModel? = nil
  private(set) var controlsModel: FieldControlsModel? = nil
  private(set) var plan: VisitPackagePlan? = nil
  private(set) var isBuilding = false
  private(set) var isSealing = false
  private(set) var message: String? = nil
  private(set) var upload: UploadSnapshot? = nil
  /// The rooms of every capture with the operator's names (kept in the visit's
  /// `room-names.json`). Observed: a rename redraws the checklist and the photo step.
  private(set) var rooms: VisitRooms

  @ObservationIgnored let services: AppServices
  @ObservationIgnored let workspace: VisitWorkspace
  @ObservationIgnored private let operatorInfo: SignedInOperator
  @ObservationIgnored private weak var app: AppModel?
  @ObservationIgnored private let photoStore: PhotoRecordStore
  @ObservationIgnored private let builder: VisitPackageBuilder
  @ObservationIgnored private let appInfo: CaptureRecord.AppInfo
  @ObservationIgnored private var controls: FieldControls? = nil
  @ObservationIgnored private var scans: [LowercaseUUID: ScanMeasurements?] = [:]
  @ObservationIgnored private var uploadPackageId: LowercaseUUID? = nil

  init(
    services: AppServices, workspace: VisitWorkspace, operatorInfo: SignedInOperator,
    app: AppModel
  ) throws {
    self.services = services
    self.workspace = workspace
    self.operatorInfo = operatorInfo
    self.app = app
    photoStore = try PhotoRecordStore(files: DiskPhotoFileStore(root: workspace.photosRoot))
    appInfo =
      CaptureRecord.AppInfo.from(bundle: .main)
      ?? CaptureRecord.AppInfo(version: "0.0.0", build: "0")
    builder = VisitPackageBuilder(workspace: workspace, appVersion: appInfo.version)
    // Names already given in this visit's folder (none for a new visit).
    rooms = VisitRooms(builder: builder)
    captureModel = makeCaptureModel(draft: newDraft())
  }

  // MARK: Capture record and scan

  private func newDraft() -> CaptureRecordDraft {
    CaptureRecordDraft(
      operatorName: operatorInfo.name, operatorUserId: operatorInfo.userId,
      device: services.device, app: appInfo)
  }

  private func makeCaptureModel(draft: CaptureRecordDraft) -> CaptureFlowModel {
    CaptureFlowModel(
      draft: draft, capabilities: services.capabilities,
      projectProvider: StationProjectProvider(store: services.projects),
      originalsRoot: workspace.originalsRoot, makeSession: services.makeSession,
      onFinished: { [weak self] result in self?.floorFinished(result) })
  }

  /// Follows the capture screens' own step (Start scan / cancel).
  func captureStepChanged(_ step: CaptureFlowStep) {
    switch (step, flow.step) {
    case (.scanning, .captureRecord): try? flow.scanStarted()
    case (.scanSetup, .scan): try? flow.scanCancelled()
    default: break
    }
  }

  /// Where every visit on this phone is kept ("My scans").
  var visitsRoot: URL? { app?.visitsRoot }

  /// This visit's scans, in capture order, for review before upload, with the operator's room
  /// names.
  var scanItems: [ScanItem] {
    let address = flow.record?.address.formatted
    return (flow.record?.captures ?? []).compactMap { capture in
      ScanLibrary.item(
        folder: workspace.originalsRoot
          .appendingPathComponent("Original Exports", isDirectory: true)
          .appendingPathComponent(capture.areaKey, isDirectory: true)
          .appendingPathComponent(capture.captureId.rawValue, isDirectory: true),
        title: capture.label, address: address, displayUnits: capture.units.display,
        capturedAt: capture.capturedAt.date,
        roomNames: rooms.names.names(for: capture.captureId))
    }
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
      let model = try? rooms.load(capture, visitId: record.visitId)
      scans[capture.captureId] = model.map(ScanMeasurements.init(model:))
      openPhotos(captureId: capture.captureId, room: nil)
      message = nil
    } catch {
      message = String(describing: error)
    }
  }

  // MARK: Photos, controls, checklist

  private func option(for capture: CaptureRecord.Capture) -> FieldCaptureOption {
    FieldCaptureOption(
      ref: FieldControls.CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey),
      label: capture.label, mode: capture.mode, capturedAt: capture.capturedAt,
      rooms: rooms.labels(of: capture.captureId), scan: scans[capture.captureId] ?? nil)
  }

  // MARK: Room names

  /// The "Rename rooms" sheet: the rooms of `captureId` (from the photo step), or of every
  /// capture (from the checklist), each marked when it still needs a photo. From the photo
  /// step it opens at the room the camera was opened for, else at the first room without a
  /// photo; from the checklist at the first room "A photo for every room" names ("Closet has no
  /// photo"). Nil when there is no room to rename.
  func roomNamingDraft(captureId: LowercaseUUID?) -> RoomNamingDraft? {
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
  /// Floorplan, reports and checklist), the photos already labeled with an old name, and the
  /// field controls measured in a renamed room (`field-controls.json`). The photo step's chips
  /// follow at once. Returns an error message for the sheet, nil when saved.
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
        scans[captureId] = ScanMeasurements(model: model)
      }
      if let next = result.controls {
        controls = next
        // The controls screen is rebuilt from the controls whenever it opens; one built
        // already gets the new rooms and names now.
        if controlsModel != nil { openControls() }
      }
      if let photoModel {
        let captureId = photoModel.capture.ref.captureId
        photoModel.roomsRenamed(
          rooms: rooms.labels(of: captureId),
          renames: VisitRooms.labelChanges(
            before: before[captureId] ?? [], after: rooms.rooms[captureId] ?? []))
      }
      message = nil
      return nil
    } catch {
      return "The names could not be saved: \(String(describing: error))"
    }
  }

  private func openPhotos(captureId: LowercaseUUID, room: String?) {
    guard let capture = flow.captures.first(where: { $0.captureId == captureId }) else { return }
    switch services.photoSource {
    case .camera(let camera):
      photoModel = PhotoLabelingModel(
        capture: option(for: capture), store: photoStore, camera: camera, initialRoom: room)
    case .fixed(let source):
      photoModel = PhotoLabelingModel(
        capture: option(for: capture), store: photoStore, initialRoom: room, capturePhoto: source)
    }
  }

  func photosDone() {
    do {
      try flow.photosDone()
      if flow.step == .controls { openControls() }
    } catch { message = String(describing: error) }
  }

  private func openControls() {
    guard let controls else { return }
    let refs = flow.captures.map {
      FieldControls.CaptureRef(captureId: $0.captureId, areaKey: $0.areaKey)
    }
    let root = workspace.controlsRoot
    controlsModel = FieldControlsModel(
      captures: flow.captures.map(option(for:)), controls: controls,
      persist: { [weak self] next in
        try FieldControlsFile.write(next, intoPackageRoot: root, knownCaptures: refs)
        self?.controls = next
      })
  }

  func controlsDone() {
    do { try flow.controlsDone() } catch { message = String(describing: error) }
  }

  var checklist: ChecklistReport? {
    guard let record = flow.record, let controls else { return nil }
    var capturedRooms: [LowercaseUUID: [String]] = [:]
    for capture in record.captures {
      capturedRooms[capture.captureId] = rooms.labels(of: capture.captureId)
    }
    return ChecklistRules.evaluate(
      ChecklistInput(
        record: record, capturedRooms: capturedRooms, photos: photoStore.records,
        controls: controls, noRoomsSkippedConfirmed: flow.noRoomsSkippedConfirmed))
  }

  /// "No rooms skipped" on the checklist. The tap is kept in `flow` (observed), so the checklist
  /// is evaluated again; it stops counting when a new floor or a skipped room is added.
  func checklistConfirmNoRoomsSkipped() {
    do { try flow.confirmNoRoomsSkipped() } catch { message = String(describing: error) }
  }

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
    do {
      try flow.takePhoto(captureId: capture.captureId, room: room)
      openPhotos(captureId: capture.captureId, room: room)
    } catch { message = String(describing: error) }
  }

  func checklistAddControls() {
    do {
      try flow.addControls()
      openControls()
    } catch { message = String(describing: error) }
  }

  /// "Before you leave" passed: build the package plan for "Package ready".
  func checklistFinished() {
    guard let report = checklist, let record = flow.record, let controls else { return }
    do {
      try flow.checklistFinished(canFinish: report.canFinish)
    } catch {
      message = String(describing: error)
      return
    }
    isBuilding = true
    message = nil
    let builder = self.builder
    let photos = photoStore.records
    let roomNames = rooms.names
    Task {
      let result = await Task.detached {
        Result {
          try builder.plan(
            record: record, photos: photos, controls: controls, roomNames: roomNames)
        }
      }.value
      isBuilding = false
      switch result {
      case .success(let plan): self.plan = plan
      case .failure(let error): message = String(describing: error)
      }
    }
  }

  // MARK: Package

  func addMoreRooms() {
    guard let record = flow.record, let current = captureModel else { return }
    do {
      try flow.addMoreRooms()
    } catch {
      message = String(describing: error)
      return
    }
    plan = nil
    var draft = newDraft()
    if let project = current.draft.project { draft.select(project) }
    draft.setAddressConfirmed(true, at: UTCTimestamp.now())
    draft.displayUnits = record.captures.first?.units.display ?? draft.displayUnits
    let next = makeCaptureModel(draft: draft)
    // The next free "Floor N", and Start scan refuses a floor this visit already has.
    next.existingAreaKeys = Set(record.captures.map(\.areaKey))
    next.step = .scanSetup
    captureModel = next
  }

  /// "Seal and upload": assemble the read-only package, then upload it in the background.
  func sealAndUpload() {
    guard let plan, !isSealing, let app else { return }
    isSealing = true
    message = nil
    let destination = workspace.packageURL(packageId: plan.draft.packageId.rawValue)
    let draft = plan.draft
    let dealId = plan.record.hub.dealId
    Task {
      let result = await Task.detached {
        Result { try PackageAssembler().assemble(draft, at: destination) }
      }.value
      isSealing = false
      switch result {
      case .success(let sealed):
        do {
          try flow.sealed()
          showUpload(of: sealed, coordinator: app.coordinator(for: sealed, dealId: dealId))
        } catch {
          message = String(describing: error)
        }
      case .failure(let error):
        message = String(describing: error)
      }
    }
  }

  /// Shows the Uploading screen for a sealed package (this visit's, or one resumed at launch).
  func showUpload(of package: SealedPackage, coordinator: UploadCoordinator) {
    uploadPackageId = package.packageId
    upload = coordinator.snapshot
  }

  func uploadChanged(_ snapshot: UploadSnapshot) {
    guard snapshot.packageId == uploadPackageId else { return }
    upload = snapshot
  }

  func startNewCapture() {
    app?.startNewVisit(showPendingUpload: false)
  }

  // MARK: Account

  /// Display name of the signed-in account (MSAL `name` claim, else the username). Never a token.
  var signedInName: String { operatorInfo.name }

  /// "Sign out" is offered only on New capture of a visit with no capture yet.
  var canSignOut: Bool {
    upload == nil && flow.allowsSignOut && captureModel?.step == .newCapture
  }

  /// Sealed packages on the phone the station has not confirmed yet. They stay on disk and
  /// resume after the next sign-in.
  var hasPendingUploads: Bool { (app?.pendingUploadCount ?? 0) > 0 }

  /// Removes the MSAL accounts and the offline project list, then shows the sign-in screen.
  /// Deletes no file.
  func signOut() {
    guard canSignOut, let app else { return }
    Task { await app.signOut() }
  }
}
