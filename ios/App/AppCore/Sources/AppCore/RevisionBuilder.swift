import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import PackageCore

/// One planned revision n ≥ 2 of a visit (phone-package §6, §9.4): the draft carrying the sealed
/// revision n − 1 over, and what changed.
public struct VisitRevisionPlan: Sendable {
  public let draft: PackageDraft
  /// The visit's capture record: the base captures and the new ones.
  public let record: CaptureRecord
  public let changes: RevisionChanges
  /// Folder of this build's generated files.
  public let draftFolder: URL
  /// Revision n − 1 on the phone.
  public let base: SealedPackage
}

extension VisitPackageBuilder {
  /// Revision n of a sealed visit, after "Add to this capture" (§9.4):
  ///
  /// 1. Every file of `base` is carried over with its fingerprint (`PackageDraft.nextRevision`;
  ///    the retired phone report of a 1.0.0 base is left out).
  /// 2. The capture record (base captures and new ones) and the field controls replace the base
  ///    files only when their bytes differ.
  /// 3. New captures get all their files, as in revision 1.
  /// 4. A base capture whose capture model, mapped again with today's room names, differs from
  ///    the sealed one gets the new model and its plan files again; its meshes, LAS and raw
  ///    originals stay carried over. A base capture with the same model keeps every file, so a
  ///    newer PlanExport never silently redraws an old floor.
  /// 5. Photos not in the base are added with their recorded fingerprints; carried-over photos
  ///    take the labels they have now (a renamed room). A base whose photos were erased on the
  ///    phone (`PhotosErasedRecord`) carries none over.
  /// 6. `RevisionChanges` compares the draft with the base; `baseNextActions` (the base
  ///    verdict's) fill `answersNextAction`.
  public func revisionPlan(
    base: SealedPackage, record: CaptureRecord, photos: [PhotoRecord], controls: FieldControls,
    roomNames: VisitRoomNames = VisitRoomNames(), baseNextActions: [String] = [],
    draftId: UUID = UUID(), packageId: LowercaseUUID = LowercaseUUID()
  ) throws -> VisitRevisionPlan {
    guard !record.captures.isEmpty else { throw VisitPackageError.noCaptures }
    guard record.visitId == base.visitId else {
      throw VisitPackageError.writeFailed("the capture record is not of the sealed visit")
    }
    let draftFolder = self.draftFolder(draftId)
    var draft = try PackageDraft.nextRevision(of: base, packageId: packageId)
    if PhotosErasedRecord.isErased(packageAt: base.root) {
      // "Delete all photos" erased the base's photos on this phone: none is carried over (only
      // the photos taken since, below).
      for entry in draft.entries where entry.input.role == .photo {
        try draft.remove(path: entry.path)
      }
    }
    let baseBytes = { (role: FileRole, captureId: LowercaseUUID?) -> Data? in
      base.manifest.files.first { $0.role == role && $0.captureId == captureId }
        .flatMap { try? Data(contentsOf: base.url(for: $0.path)) }
    }

    // Visit-wide documents, replaced only when they changed.
    if try encode(record) != baseBytes(.captureRecord, nil) {
      try draft.replace(try recordInput(record, draftFolder: draftFolder))
    }
    let controlsFile = try controlsInput(controls, record: record)
    if (try? Data(contentsOf: controlsFile.source)) != baseBytes(.fieldControls, nil) {
      if draft.entries.contains(where: { $0.input.role == .fieldControls }) {
        try draft.replace(controlsFile)
      } else {
        try draft.add(controlsFile)
      }
    }

    let baseCaptures = Set(
      (SealedPackageSummary.captureRecord(of: base)?.captures ?? []).map(\.captureId))
    for capture in record.captures {
      let names = roomNames.names(for: capture.captureId)
      if !baseCaptures.contains(capture.captureId) {
        try addCapture(capture, record: record, names: names, draftFolder: draftFolder, to: &draft)
        continue
      }
      let model = try captureModel(of: capture, visitId: record.visitId, names: names)
      guard try encode(model) != baseBytes(.captureModel, capture.captureId) else { continue }
      try redrawPlans(model, capture: capture, record: record, draftFolder: draftFolder, in: &draft)
    }

    // Photos.
    let captureIds = Set(record.captures.map(\.captureId))
    for photo in photos where captureIds.contains(photo.captureId) {
      let input = photoInput(photo)
      let path = try draft.path(role: .photo, fileName: input.fileName, capture: input.capture)
      if let carried = draft.entries.first(where: { $0.path == path }) {
        if carried.input.photo != photo.labels {
          var relabeled = carried.input
          relabeled.photo = photo.labels
          try draft.replace(relabeled)
        }
      } else {
        try draft.add(input)
      }
    }

    let changes = RevisionChanges.make(
      base: try RevisionChanges.Side(sealed: base), draft: try RevisionChanges.Side(draft: draft),
      baseNextActions: baseNextActions)
    return VisitRevisionPlan(
      draft: draft, record: record, changes: changes, draftFolder: draftFolder, base: base)
  }

  /// A full build of revision `revision` (> 1) from the visit's files, superseding `supersedes`:
  /// the re-seal after a failed upload (§4.2, Q9), which never reuses the sealed copy (it may be
  /// what failed).
  public func rebuildPlan(
    revision: Int, supersedes: LowercaseUUID, record: CaptureRecord, photos: [PhotoRecord],
    controls: FieldControls, roomNames: VisitRoomNames = VisitRoomNames(),
    draftId: UUID = UUID(), packageId: LowercaseUUID = LowercaseUUID()
  ) throws -> VisitPackagePlan {
    try build(
      try PackageDraft(
        visitId: record.visitId, packageId: packageId, revision: revision,
        supersedesPackageId: supersedes),
      record: record, photos: photos, controls: controls, roomNames: roomNames, draftId: draftId)
  }

  /// The scan originals of every capture are still in the workspace: a revision or a re-seal can
  /// be built. False when the visit's folder no longer holds them (moved or removed).
  public func hasOriginals(of record: CaptureRecord) -> Bool {
    !record.captures.isEmpty
      && record.captures.allSatisfy { capture in
        FileManager.default.fileExists(
          atPath: originalsDirectory(of: capture)
            .appendingPathComponent(RawOriginalsNaming.originals.roomPlanFileName).path)
      }
  }

  /// A base capture with a new capture model: the model and its plan files replace the carried
  /// ones; a plan file the base has under a name PlanExport no longer writes leaves the draft.
  private func redrawPlans(
    _ model: CaptureModel, capture: CaptureRecord.Capture, record: CaptureRecord,
    draftFolder: URL, in draft: inout PackageDraft
  ) throws {
    let ref = CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey)
    let exports = exportsFolder(of: capture, in: draftFolder)
    let roomPlanPath = try draft.path(
      role: .rawRoomplanJSON, fileName: RawOriginalsNaming.originals.roomPlanFileName, capture: ref)
    let modelInput = try modelInput(
      model, capture: capture, exports: exports, roomPlanPath: roomPlanPath)
    try draft.replace(modelInput)
    let modelPath = try draft.path(
      role: .captureModel, fileName: modelInput.fileName, capture: ref)

    let planRoles: Set<FileRole> = [.planDXF, .roomsCSV, .planPDF, .planPNG, .planSVG]
    var written: Set<String> = []
    for input in try planInputs(
      model, capture: capture, record: record, exports: exports, modelPath: modelPath)
    {
      let path = try draft.path(role: input.role, fileName: input.fileName, capture: ref)
      written.insert(path)
      if draft.entries.contains(where: { $0.path == path }) {
        try draft.replace(input)
      } else {
        try draft.add(input)
      }
    }
    let stale = draft.entries.filter {
      $0.input.capture?.captureId == capture.captureId && planRoles.contains($0.input.role)
        && !written.contains($0.path)
    }
    for entry in stale {
      try draft.remove(path: entry.path)
    }
  }
}
