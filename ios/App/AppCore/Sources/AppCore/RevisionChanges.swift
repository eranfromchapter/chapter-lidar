import CaptureContract
import FieldRules
import Foundation
import PackageCore

/// What revision n changes against the sealed revision n − 1 (phone-package §6.4) and every
/// string of the Revision n screen (§6.1, artboard 2f screen 4). Pure: built from two
/// `RevisionChanges.Side`s, which read the files once.
///
/// File level, by manifest path: added (not in the base), changed (another SHA-256 or size),
/// unchanged (same SHA-256 and size; the station carries them over), removed (in the base only:
/// the retired phone report, or a plan export now written under another name). k = added +
/// changed is what revision n uploads.
public struct RevisionChanges: Equatable, Sendable {
  public enum Kind: String, CaseIterable, Sendable {
    case added
    case changed
    case removed
  }

  /// The subjects of `NextRevisionChange` (contract/openapi/station.yaml).
  public enum Subject: String, CaseIterable, Sendable {
    case capture
    case roomNames = "room_names"
    case fieldControl = "field_control"
    case photos
    case retiredFile = "retired_file"
  }

  /// One row of "What changed".
  public struct Row: Equatable, Sendable {
    public var kind: Kind
    public var subject: Subject
    public var title: String
    public var detail: String
    /// A next action of the base verdict, verbatim, that this change answers (§10.4).
    public var answersNextAction: String?
    /// Instrument of a field-control change.
    public var method: MeasurementMethod?

    public init(
      kind: Kind, subject: Subject, title: String, detail: String,
      answersNextAction: String? = nil, method: MeasurementMethod? = nil
    ) {
      self.kind = kind
      self.subject = subject
      self.title = title
      self.detail = detail
      self.answersNextAction = answersNextAction
      self.method = method
    }

    /// "Added, Primary closet, Scanned · one room · 5 files".
    public var accessibilityLabel: String {
      let word: String
      switch kind {
      case .added: word = "Added"
      case .changed: word = "Changed"
      case .removed: word = "Removed"
      }
      return "\(word), \(title), \(detail)"
    }
  }

  /// One revision as the comparison needs it: its files with their fingerprints, its capture
  /// record, its field controls and the room labels of its capture models.
  public struct Side: Equatable, Sendable {
    public struct File: Equatable, Sendable {
      public var path: String
      public var role: FileRole
      public var captureId: LowercaseUUID?
      public var sha256: String
      public var bytes: Int64
      public var photo: PackageManifest.PhotoLabels?

      public init(
        path: String, role: FileRole, captureId: LowercaseUUID? = nil, sha256: String,
        bytes: Int64, photo: PackageManifest.PhotoLabels? = nil
      ) {
        self.path = path
        self.role = role
        self.captureId = captureId
        self.sha256 = sha256
        self.bytes = bytes
        self.photo = photo
      }
    }

    public var revision: Int
    /// In manifest (or draft) order.
    public var files: [File]
    public var record: CaptureRecord
    public var controls: FieldControls?
    /// Room id to room label, per capture, from each capture model.
    public var roomLabels: [LowercaseUUID: [String: String]]

    public init(
      revision: Int, files: [File], record: CaptureRecord, controls: FieldControls?,
      roomLabels: [LowercaseUUID: [String: String]] = [:]
    ) {
      self.revision = revision
      self.files = files
      self.record = record
      self.controls = controls
      self.roomLabels = roomLabels
    }

    /// A sealed package: the manifest's fingerprints and the documents it holds.
    public init(sealed: SealedPackage) throws {
      let manifest = sealed.manifest
      let files = manifest.files.map {
        File(
          path: $0.path, role: $0.role, captureId: $0.captureId, sha256: $0.sha256, bytes: $0.bytes,
          photo: $0.photo)
      }
      try self.init(
        revision: manifest.revision, files: files,
        read: { path in try Data(contentsOf: sealed.url(for: path)) })
    }

    /// A draft: fingerprints of its sources (the expected ones of carried-over files and photos,
    /// else read).
    public init(draft: PackageDraft) throws {
      var sources: [String: URL] = [:]
      var files: [File] = []
      for entry in draft.entries {
        let input = entry.input
        let digest = try input.expected ?? FileDigest.of(fileAt: input.source)
        sources[entry.path] = input.source
        files.append(
          File(
            path: entry.path, role: input.role, captureId: input.capture?.captureId,
            sha256: digest.sha256, bytes: digest.bytes, photo: input.photo))
      }
      try self.init(
        revision: draft.revision, files: files,
        read: { path in
          guard let url = sources[path] else { throw PackageError.unknownPath(path) }
          return try Data(contentsOf: url)
        })
    }

    private init(revision: Int, files: [File], read: (String) throws -> Data) throws {
      let decoder = CaptureContractJSON.makeDecoder()
      guard let recordFile = files.first(where: { $0.role == .captureRecord }) else {
        throw PackageError.captureRecordCount(0)
      }
      let record = try decoder.decode(CaptureRecord.self, from: try read(recordFile.path))
      let controls = try files.first(where: { $0.role == .fieldControls }).map {
        try decoder.decode(FieldControls.self, from: try read($0.path))
      }
      var labels: [LowercaseUUID: [String: String]] = [:]
      for file in files where file.role == .captureModel {
        guard let captureId = file.captureId,
          let model = try? decoder.decode(CaptureModel.self, from: try read(file.path))
        else { continue }
        labels[captureId] = Dictionary(
          model.rooms.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
      }
      self.init(
        revision: revision, files: files, record: record, controls: controls, roomLabels: labels)
    }
  }

  /// "Unchanged": captures none of whose files changed, the photos and the controls carried
  /// over.
  public struct Unchanged: Equatable, Sendable {
    public var captureLabels: [String]
    public var photos: Int
    public var controls: Int

    public init(captureLabels: [String], photos: Int, controls: Int) {
      self.captureLabels = captureLabels
      self.photos = photos
      self.controls = controls
    }
  }

  /// Revision n − 1.
  public var baseRevision: Int
  /// Revision n.
  public var revision: Int
  /// "What changed", in the order of §6.1: new captures, room-name changes, field controls,
  /// photos, retired files.
  public var rows: [Row]
  public var addedPaths: [String]
  public var changedPaths: [String]
  public var unchangedPaths: [String]
  public var removedPaths: [String]
  /// Bytes of the added and changed files.
  public var bytesToUpload: Int64
  public var baseEntries: Int
  public var draftEntries: Int
  public var unchanged: Unchanged

  public init(
    baseRevision: Int, revision: Int, rows: [Row], addedPaths: [String], changedPaths: [String],
    unchangedPaths: [String], removedPaths: [String], bytesToUpload: Int64, baseEntries: Int,
    draftEntries: Int, unchanged: Unchanged
  ) {
    self.baseRevision = baseRevision
    self.revision = revision
    self.rows = rows
    self.addedPaths = addedPaths
    self.changedPaths = changedPaths
    self.unchangedPaths = unchangedPaths
    self.removedPaths = removedPaths
    self.bytesToUpload = bytesToUpload
    self.baseEntries = baseEntries
    self.draftEntries = draftEntries
    self.unchanged = unchanged
  }

  /// Files revision n uploads (k).
  public var uploadCount: Int { addedPaths.count + changedPaths.count }

  /// Nothing to seal: no added or changed file.
  public var hasNoChanges: Bool { uploadCount == 0 }

  // MARK: Strings (§6.1)

  /// "Revision 2".
  public var title: String { "Revision \(revision)" }

  public var subtitle: String {
    "You changed the capture after sealing revision \(baseRevision). Sealing again creates "
      + "revision \(revision). Revision \(baseRevision) stays as it was; the station checks "
      + "revision \(revision) from the start."
  }

  /// The only row of an empty "What changed".
  public var nothingChangedText: String { "Nothing changed since revision \(baseRevision)." }

  /// "75 → 83 entries".
  public var manifestDetail: String {
    "\(baseEntries) \u{2192} \(PackageText.plural(draftEntries, "entry", "entries"))"
  }

  /// "Floor 1 scan, 42 photos, 9 controls"; nil when nothing is unchanged.
  public var unchangedTitle: String? {
    var parts: [String] = []
    if !unchanged.captureLabels.isEmpty {
      let scans = unchanged.captureLabels.count == 1 ? "scan" : "scans"
      parts.append("\(PackageText.list(unchanged.captureLabels)) \(scans)")
    }
    if unchanged.photos > 0 { parts.append(PackageText.plural(unchanged.photos, "photo", "photos")) }
    if unchanged.controls > 0 {
      parts.append(PackageText.plural(unchanged.controls, "control", "controls"))
    }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }

  /// "Same fingerprints as revision 1 · not uploaded again".
  public var unchangedSubtitle: String {
    "Same fingerprints as revision \(baseRevision) \u{00B7} not uploaded again"
  }

  /// "Only the 8 new files are uploaded. …" ("new or changed" once a file changed).
  public var footnote: String {
    let k = uploadCount
    let what = changedPaths.isEmpty ? "new" : "new or changed"
    let first =
      k == 1 ? "Only the 1 \(what) file is uploaded." : "Only the \(k) \(what) files are uploaded."
    return "\(first) The station checks the whole package and issues a new verdict and spatial report."
  }

  /// The primary button: "Seal revision 2 and upload", or "No changes to seal" (disabled).
  public var sealButtonTitle: String {
    hasNoChanges ? "No changes to seal" : "Seal revision \(revision) and upload"
  }

  /// What the station keeps as the next-revision notice while the operator edits (§10.4).
  public func notice(updatedAt: UTCTimestamp) -> NextRevisionNoticeDraft {
    NextRevisionNoticeDraft(revision: revision, updatedAt: updatedAt, rows: rows)
  }

  // MARK: Comparison

  /// - baseNextActions: the base verdict's next actions, for `answersNextAction` (§10.4).
  public static func make(base: Side, draft: Side, baseNextActions: [String] = []) -> RevisionChanges {
    let baseFiles = Dictionary(base.files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    let draftPaths = Set(draft.files.map(\.path))
    var added: [String] = []
    var changed: [String] = []
    var unchangedPaths: [String] = []
    for file in draft.files {
      guard let earlier = baseFiles[file.path] else {
        added.append(file.path)
        continue
      }
      if earlier.sha256 == file.sha256 && earlier.bytes == file.bytes {
        unchangedPaths.append(file.path)
      } else {
        changed.append(file.path)
      }
    }
    let removed = base.files.map(\.path).filter { !draftPaths.contains($0) }
    let touched = Set(added + changed + removed)
    let draftByPath = Dictionary(draft.files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    let bytes = (added + changed).reduce(Int64(0)) { $0 + (draftByPath[$1]?.bytes ?? 0) }

    var rows: [Row] = []
    let baseCaptureIds = Set(base.record.captures.map(\.captureId))
    let skippedRooms = base.record.captures.flatMap { $0.omittedRooms + $0.inaccessibleRooms }
      .map(\.name)

    // New captures.
    for capture in draft.record.captures where !baseCaptureIds.contains(capture.captureId) {
      let files = draft.files.filter { $0.captureId == capture.captureId && $0.role != .photo }
      let label = Self.normalized(capture.label)
      let answers =
        skippedRooms.contains { Self.normalized($0) == label }
        ? baseNextActions.first { $0.lowercased().contains(label) } : nil
      rows.append(
        Row(
          kind: .added, subject: .capture, title: capture.label,
          detail: "Scanned \u{00B7} \(Self.modeWord(capture.mode)) \u{00B7} "
            + PackageText.plural(files.count, "file", "files"),
          answersNextAction: answers))
    }

    // Room names of sealed captures (their capture model changed).
    for capture in draft.record.captures where baseCaptureIds.contains(capture.captureId) {
      let modelChanged = draft.files.contains {
        $0.captureId == capture.captureId && $0.role == .captureModel && changed.contains($0.path)
      }
      guard modelChanged else { continue }
      let before = base.roomLabels[capture.captureId] ?? [:]
      let after = draft.roomLabels[capture.captureId] ?? [:]
      let renames = after.keys.sorted { Self.roomOrder($0, $1) }.compactMap { id -> String? in
        guard let old = before[id], let new = after[id], old != new else { return nil }
        return "\(old) \u{2192} \(new)"
      }
      // The capture's plan files that change; photos and the retired phone report have rows of
      // their own.
      let files = touched.filter { path in
        guard let file = draftByPath[path] ?? baseFiles[path] else { return false }
        return file.captureId == capture.captureId && file.role != .photo && !file.role.isRetired
      }.count
      var detail = renames.prefix(2).joined(separator: ", ")
      if renames.count > 2 { detail += ", +\(renames.count - 2) more" }
      detail += (detail.isEmpty ? "" : " \u{00B7} ") + PackageText.plural(files, "file", "files")
      rows.append(
        Row(kind: .changed, subject: .roomNames, title: "\(capture.label) room names", detail: detail))
    }

    // Field controls, by id.
    let controls = Self.controlRows(base: base, draft: draft, nextActions: baseNextActions)
    rows += controls.rows

    // New photos, one row per capture and room, in order of first appearance.
    var groups: [(key: String, captureId: LowercaseUUID?, room: String, subjects: [String], count: Int)] = []
    for file in draft.files where file.role == .photo && baseFiles[file.path] == nil {
      let room = file.photo?.room ?? ""
      let key = "\(file.captureId?.rawValue ?? "")/\(room)"
      let subject = file.photo?.subject.rawValue.lowercased() ?? ""
      if let index = groups.firstIndex(where: { $0.key == key }) {
        groups[index].count += 1
        if !subject.isEmpty, !groups[index].subjects.contains(subject) {
          groups[index].subjects.append(subject)
        }
      } else {
        groups.append((key, file.captureId, room, subject.isEmpty ? [] : [subject], 1))
      }
    }
    for group in groups {
      rows.append(
        Row(
          kind: .added, subject: .photos, title: PackageText.plural(group.count, "photo", "photos"),
          detail: "\(group.room) \u{00B7} \(group.subjects.joined(separator: ", "))"))
    }

    // The retired phone report of a manifest 1.0.0 base.
    let retired = removed.filter { baseFiles[$0]?.role.isRetired == true }
    if !retired.isEmpty {
      rows.append(
        Row(
          kind: .removed, subject: .retiredFile, title: "Spatial report PDF from the phone",
          detail: "Retired \u{00B7} the station makes the spatial report \u{00B7} "
            + PackageText.plural(retired.count, "file", "files")))
    }

    // Unchanged.
    let unchangedCaptures = draft.record.captures.filter { capture in
      baseCaptureIds.contains(capture.captureId)
        && !touched.contains { path in
          guard let file = draftByPath[path] ?? baseFiles[path] else { return false }
          return file.captureId == capture.captureId && file.role != .photo && !file.role.isRetired
        }
    }
    let unchangedPhotos = unchangedPaths.filter { draftByPath[$0]?.role == .photo }.count

    return RevisionChanges(
      baseRevision: base.revision, revision: draft.revision, rows: rows, addedPaths: added,
      changedPaths: changed, unchangedPaths: unchangedPaths, removedPaths: removed,
      bytesToUpload: bytes, baseEntries: base.files.count, draftEntries: draft.files.count,
      unchanged: Unchanged(
        captureLabels: unchangedCaptures.map(\.label), photos: unchangedPhotos,
        controls: controls.unchanged))
  }

  /// "one room", "whole floor", "exterior".
  static func modeWord(_ mode: CaptureMode) -> String {
    switch mode {
    case .room: return "one room"
    case .floor: return "whole floor"
    case .exterior: return "exterior"
    }
  }

  private static func normalized(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// `room-2` before `room-10`.
  private static func roomOrder(_ first: String, _ second: String) -> Bool {
    first.compare(second, options: .numeric) == .orderedAscending
  }

  /// One control as Revision n names it.
  private struct Control: Equatable {
    var id: String
    var title: String
    var valueMm: Double?
    var method: MeasurementMethod?
    var detailSuffix: String?
    var room: String?
    var isCeilingHeight: Bool
    /// The whole control, to tell an unchanged one from a changed one.
    var fingerprint: String
  }

  private static func controls(of side: Side) -> [Control] {
    guard let controls = side.controls else { return [] }
    let labels = Dictionary(
      side.record.captures.map { ($0.captureId, $0.label) }, uniquingKeysWith: { first, _ in first })
    func label(_ ref: FieldControls.CaptureRef) -> String {
      labels[ref.captureId] ?? ref.areaKey
    }
    func fingerprint<T: Encodable>(_ value: T) -> String {
      (try? CaptureContractJSON.makeEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) }
        ?? ""
    }
    var result: [Control] = []
    for distance in controls.distances {
      result.append(
        Control(
          id: distance.id, title: "\(label(distance.capture)) long distance \(distance.axis.rawValue)",
          valueMm: distance.measurement.valueMm, method: distance.measurement.method,
          isCeilingHeight: false, fingerprint: fingerprint(distance)))
    }
    for height in controls.ceilingHeights {
      result.append(
        Control(
          id: height.id, title: "\(height.room) ceiling height",
          valueMm: height.measurement.valueMm, method: height.measurement.method, room: height.room,
          isCeilingHeight: true, fingerprint: fingerprint(height)))
    }
    for opening in controls.openings {
      result.append(
        Control(
          id: opening.id, title: "\(opening.room) \(opening.label) width",
          valueMm: opening.width.valueMm, method: opening.width.method, isCeilingHeight: false,
          fingerprint: fingerprint(opening)))
    }
    for level in controls.floorToFloor {
      result.append(
        Control(
          id: level.id, title: "Floor to floor, \(label(level.lower)) to \(label(level.upper))",
          valueMm: level.measurement.valueMm, method: level.measurement.method,
          isCeilingHeight: false, fingerprint: fingerprint(level)))
    }
    for landmark in controls.landmarks {
      result.append(
        Control(
          id: landmark.id, title: "Landmark \(landmark.label)", valueMm: nil, method: nil,
          detailSuffix: PackageText.plural(landmark.captures.count, "floor", "floors"),
          isCeilingHeight: false, fingerprint: fingerprint(landmark)))
    }
    return result
  }

  private static func controlRows(base: Side, draft: Side, nextActions: [String]) -> (
    rows: [Row], unchanged: Int
  ) {
    let before = Dictionary(controls(of: base).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var rows: [Row] = []
    var unchanged = 0
    for control in controls(of: draft) {
      let value = control.valueMm.map(LengthFormatter.both) ?? control.detailSuffix ?? ""
      guard let earlier = before[control.id] else {
        var answers: String?
        if control.isCeilingHeight, let room = control.room.map(normalized) {
          answers = nextActions.first {
            $0.lowercased().contains(room) && $0.lowercased().contains("ceiling")
          }
        }
        rows.append(
          Row(
            kind: .added, subject: .fieldControl, title: control.title,
            detail: "Field control \u{00B7} \(value)", answersNextAction: answers,
            method: control.method))
        continue
      }
      if earlier.fingerprint == control.fingerprint {
        unchanged += 1
      } else {
        rows.append(
          Row(
            kind: .changed, subject: .fieldControl, title: control.title,
            detail: control.valueMm == nil
              ? "Field control \u{00B7} \(value)" : "Field control \u{00B7} changed to \(value)",
            method: control.method))
      }
    }
    return (rows, unchanged)
  }
}

/// The next-revision notice the phone keeps the station informed with (phone-package §10.4):
/// the "What changed" rows of `RevisionChanges`, worded exactly as the Revision n screen.
public struct NextRevisionNoticeDraft: Equatable, Sendable {
  public var revision: Int
  public var updatedAt: UTCTimestamp
  public var rows: [RevisionChanges.Row]

  public init(revision: Int, updatedAt: UTCTimestamp, rows: [RevisionChanges.Row]) {
    self.revision = revision
    self.updatedAt = updatedAt
    self.rows = rows
  }
}
