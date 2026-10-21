import CaptureContract
import Foundation
import PackageCore

/// Byte counts as the design writes them: "312 MB", "512 of 768 MB" (decimal units).
public enum ByteText {
  private static let units: [(String, Double, String)] = [
    ("GB", 1e9, "gigabytes"), ("MB", 1e6, "megabytes"), ("KB", 1e3, "kilobytes"),
  ]

  public static func format(_ bytes: Int64) -> String {
    let unit = unit(for: bytes)
    return "\(number(bytes, unit.1)) \(unit.0)"
  }

  /// "512 of 768 MB": both numbers in the unit of `total`.
  public static func progress(_ done: Int64, of total: Int64) -> String {
    let unit = unit(for: total)
    return "\(number(done, unit.1)) of \(number(total, unit.1)) \(unit.0)"
  }

  /// What VoiceOver reads: "312 megabytes".
  public static func spoken(_ bytes: Int64) -> String {
    let unit = unit(for: bytes)
    return "\(number(bytes, unit.1)) \(unit.2)"
  }

  private static func unit(for bytes: Int64) -> (String, Double, String) {
    units.first { Double(bytes) >= $0.1 } ?? ("bytes", 1, "bytes")
  }

  private static func number(_ bytes: Int64, _ scale: Double) -> String {
    let value = Double(bytes) / scale
    if scale > 1, value < 10, value.rounded() != value {
      return String(format: "%.1f", value)
    }
    return String(Int64(value.rounded()))
  }
}

/// Words, numbers, dates and times of the package screens (phone-package §2.6). Locale
/// independent (en_US_POSIX month names, 24-hour times); dates and times in the phone's time
/// zone unless a test passes another.
public enum PackageText {
  private static let months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]

  /// "1 file" / "2 files".
  public static func plural(_ count: Int, _ one: String, _ many: String) -> String {
    "\(count) \(count == 1 ? one : many)"
  }

  /// "Preliminary existing-condition plans" → "preliminary existing-condition plans". A word that
  /// starts with two capitals ("BIM model") or whose second character has no case is kept, as
  /// the web's and the report's `lowerFirst` does (contract/ts review-text.ts).
  public static func lowerFirst(_ text: String) -> String {
    let characters = Array(text)
    guard characters.count >= 2 else { return text }
    let second = String(characters[1])
    guard second.lowercased() == second, second.uppercased() != second else { return text }
    return String(characters[0]).lowercased() + String(characters.dropFirst())
  }

  /// "A", "A and B", "A, B and C".
  public static func list(_ items: [String]) -> String {
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
  }

  /// "14:02".
  public static func time(_ date: Date, in timeZone: TimeZone = .current) -> String {
    let parts = calendar(timeZone).dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
  }

  /// "Jan 25, 2025".
  public static func date(_ date: Date, in timeZone: TimeZone = .current) -> String {
    let parts = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
    return "\(months[(parts.month ?? 1) - 1]) \(parts.day ?? 1), \(parts.year ?? 1970)"
  }

  /// "May 16".
  public static func shortDate(_ date: Date, in timeZone: TimeZone = .current) -> String {
    let parts = calendar(timeZone).dateComponents([.month, .day], from: date)
    return "\(months[(parts.month ?? 1) - 1]) \(parts.day ?? 1)"
  }

  public static func isSameDay(_ first: Date, _ second: Date, in timeZone: TimeZone = .current)
    -> Bool
  {
    calendar(timeZone).isDate(first, inSameDayAs: second)
  }

  private static func calendar(_ timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }
}

/// The captures of a visit counted by mode (phone-package §2.6, critique R-28): floors, then
/// rooms, then exteriors, "2 floors", "1 floor and 1 room", "1 floor, 2 rooms and 1 exterior".
/// Used by Package ready and by the Captures home rows (`{count}`).
public enum CaptureCountText {
  public static func make(_ modes: [CaptureMode]) -> String {
    let parts: [(CaptureMode, String, String)] = [
      (.floor, "floor", "floors"), (.room, "room", "rooms"), (.exterior, "exterior", "exteriors"),
    ]
    let counted = parts.compactMap { mode, one, many -> String? in
      let count = modes.filter { $0 == mode }.count
      return count > 0 ? PackageText.plural(count, one, many) : nil
    }
    return counted.isEmpty ? "no captures" : PackageText.list(counted)
  }

  public static func make(_ record: CaptureRecord) -> String {
    make(record.captures.map(\.mode))
  }
}

/// The project's name on the phone (critique R-29): the HUB project name when it has one, else
/// the confirmed address. Verdict received's title, the Revision n caption, the notification.
public enum ProjectTitle {
  public static func of(_ record: CaptureRecord) -> String {
    let name = record.hub.projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return name.isEmpty ? record.address.formatted : name
  }
}

/// A sealed package as the package screens and the notification name it, read once from its
/// manifest and its capture record.
public struct SealedPackageSummary: Equatable, Sendable {
  public var packageId: LowercaseUUID
  public var revision: Int
  public var supersedesPackageId: LowercaseUUID?
  public var sealedAt: UTCTimestamp
  /// The capture record's confirmed address; empty when the record cannot be read.
  public var address: String
  /// `ProjectTitle` (critique R-29); the address when the record has no project name.
  public var projectTitle: String
  public var dealId: String?
  /// "2 floors".
  public var captureCountText: String
  /// Files the manifest lists.
  public var fileCount: Int
  public var totalBytes: Int64

  public init(
    packageId: LowercaseUUID, revision: Int, supersedesPackageId: LowercaseUUID? = nil,
    sealedAt: UTCTimestamp, address: String, projectTitle: String, dealId: String? = nil,
    captureCountText: String, fileCount: Int, totalBytes: Int64
  ) {
    self.packageId = packageId
    self.revision = revision
    self.supersedesPackageId = supersedesPackageId
    self.sealedAt = sealedAt
    self.address = address
    self.projectTitle = projectTitle
    self.dealId = dealId
    self.captureCountText = captureCountText
    self.fileCount = fileCount
    self.totalBytes = totalBytes
  }

  public static func make(_ package: SealedPackage) -> SealedPackageSummary {
    let manifest = package.manifest
    let record = captureRecord(of: package)
    return SealedPackageSummary(
      packageId: manifest.packageId, revision: manifest.revision,
      supersedesPackageId: manifest.supersedesPackageId, sealedAt: manifest.sealedAt,
      address: record?.address.formatted ?? "",
      projectTitle: record.map(ProjectTitle.of) ?? "", dealId: record?.hub.dealId,
      captureCountText: record.map(CaptureCountText.make) ?? "",
      fileCount: manifest.files.count, totalBytes: manifest.files.reduce(0) { $0 + $1.bytes })
  }

  /// The package's own capture record; nil when it cannot be read.
  public static func captureRecord(of package: SealedPackage) -> CaptureRecord? {
    guard let entry = package.manifest.files.first(where: { $0.role == .captureRecord }),
      let data = try? Data(contentsOf: package.url(for: entry.path))
    else { return nil }
    return try? CaptureContractJSON.makeDecoder().decode(CaptureRecord.self, from: data)
  }
}

/// What "Package ready" shows (phone-package §3, artboard 2f screen 1).
public struct PackageReview: Equatable, Sendable {
  /// One sub-row of an "Original Exports" group.
  public struct ExportRow: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
      case plans
      case meshes
      case raw
    }

    public var kind: Kind
    /// "Plan DXF · rooms CSV · plan sheet PDF, PNG, SVG".
    public var label: String
    public var count: Int

    public init(kind: Kind, label: String, count: Int) {
      self.kind = kind
      self.label = label
      self.count = count
    }
  }

  /// One "Original Exports · Floor 1" group: every file of the capture except its photos.
  public struct ExportGroup: Equatable, Sendable {
    public var areaKey: String
    public var label: String
    public var fileCount: Int
    public var bytes: Int64
    /// Only the kinds the capture has files of.
    public var rows: [ExportRow]

    public init(areaKey: String, label: String, fileCount: Int, bytes: Int64, rows: [ExportRow]) {
      self.areaKey = areaKey
      self.label = label
      self.fileCount = fileCount
      self.bytes = bytes
      self.rows = rows
    }

    /// "Original Exports · Floor 1".
    public var title: String { "Original Exports \u{00B7} \(label)" }

    /// "13 files · 312 MB".
    public var countText: String {
      "\(PackageText.plural(fileCount, "file", "files")) \u{00B7} \(ByteText.format(bytes))"
    }

    /// "Original Exports, Floor 1, 13 files, 312 megabytes".
    public var accessibilityLabel: String {
      "Original Exports, \(label), \(PackageText.plural(fileCount, "file", "files")), "
        + ByteText.spoken(bytes)
    }
  }

  /// Confirmed address of the visit.
  public var address: String
  /// "2 floors" (`CaptureCountText`).
  public var captureCountText: String
  public var revision: Int
  public var exportGroups: [ExportGroup]
  public var photoCount: Int
  public var photoBytes: Int64
  public var controlCount: Int
  /// "compass: Floor 1 only" (§3.3).
  public var compassText: String
  /// Files the manifest lists (it does not list itself).
  public var manifestEntries: Int
  public var totalBytes: Int64

  public init(
    address: String, captureCountText: String, revision: Int, exportGroups: [ExportGroup],
    photoCount: Int, photoBytes: Int64, controlCount: Int, compassText: String,
    manifestEntries: Int, totalBytes: Int64
  ) {
    self.address = address
    self.captureCountText = captureCountText
    self.revision = revision
    self.exportGroups = exportGroups
    self.photoCount = photoCount
    self.photoBytes = photoBytes
    self.controlCount = controlCount
    self.compassText = compassText
    self.manifestEntries = manifestEntries
    self.totalBytes = totalBytes
  }

  /// "618 Valley Street · 2 floors · revision 1 · 74 files · 768 MB".
  public var subtitle: String {
    "\(buildingSubtitle) \u{00B7} \(PackageText.plural(manifestEntries, "file", "files")) \u{00B7} "
      + ByteText.format(totalBytes)
  }

  /// While the plans are written: "618 Valley Street · 2 floors · revision 1".
  public var buildingSubtitle: String {
    Self.buildingSubtitle(address: address, captureCountText: captureCountText, revision: revision)
  }

  public static func buildingSubtitle(address: String, captureCountText: String, revision: Int)
    -> String
  {
    "\(address) \u{00B7} \(captureCountText) \u{00B7} revision \(revision)"
  }

  /// "42 · 188 MB"; "none" without photos.
  public var photosText: String {
    photoCount == 0 ? "none" : "\(photoCount) \u{00B7} \(ByteText.format(photoBytes))"
  }

  /// "9 controls"; "no controls".
  public var controlsText: String {
    controlCount == 0 ? "no controls" : PackageText.plural(controlCount, "control", "controls")
  }

  /// "manifest · 74 entries".
  public var manifestText: String {
    "manifest \u{00B7} \(PackageText.plural(manifestEntries, "entry", "entries"))"
  }

  /// The lock note.
  public var sealNote: String {
    "Every file is fingerprinted (SHA-256). Sealing makes the package read-only; later changes "
      + "create revision \(revision + 1). The station makes the spatial report."
  }

  /// Summarises a draft. File sizes are read from the source files.
  public static func make(
    draft: PackageDraft, record: CaptureRecord, controls: FieldControls
  ) throws -> PackageReview {
    var sizes: [String: Int64] = [:]
    for entry in draft.entries {
      sizes[entry.path] = try size(of: entry.input.source)
    }
    let groups = record.captures.map { capture -> ExportGroup in
      let entries = draft.entries.filter {
        $0.input.capture?.captureId == capture.captureId && $0.input.role != .photo
      }
      return ExportGroup(
        areaKey: capture.areaKey, label: capture.label, fileCount: entries.count,
        bytes: entries.reduce(0) { $0 + (sizes[$1.path] ?? 0) },
        rows: exportRows(entries.map(\.input.role)))
    }
    let photos = draft.entries.filter { $0.input.role == .photo }
    return PackageReview(
      address: record.address.formatted, captureCountText: CaptureCountText.make(record),
      revision: draft.revision, exportGroups: groups, photoCount: photos.count,
      photoBytes: photos.reduce(0) { $0 + (sizes[$1.path] ?? 0) },
      controlCount: controlCount(controls), compassText: compassText(record.captures),
      manifestEntries: draft.entries.count, totalBytes: sizes.values.reduce(0, +))
  }

  /// Distances, ceiling heights, openings, floor-to-floor and landmarks.
  public static func controlCount(_ controls: FieldControls) -> Int {
    controls.distances.count + controls.ceilingHeights.count + controls.openings.count
      + controls.floorToFloor.count + controls.landmarks.count
  }

  /// The sub-rows of one capture's files (§3.1): Plans, Meshes, Point cloud and raw, each only
  /// when the capture has files of it, with the real number of files.
  public static func exportRows(_ roles: [FileRole]) -> [ExportRow] {
    let present = Set(roles)
    func count(_ kinds: Set<FileRole>) -> Int { roles.filter { kinds.contains($0) }.count }
    var rows: [ExportRow] = []

    let planRoles: Set<FileRole> = [.planDXF, .roomsCSV, .planPDF, .planPNG, .planSVG]
    var plans: [String] = []
    if present.contains(.planDXF) { plans.append("Plan DXF") }
    if present.contains(.roomsCSV) { plans.append("rooms CSV") }
    let sheet = [(FileRole.planPDF, "PDF"), (.planPNG, "PNG"), (.planSVG, "SVG")]
      .filter { present.contains($0.0) }.map(\.1)
    if !sheet.isEmpty { plans.append("plan sheet " + sheet.joined(separator: ", ")) }
    if !plans.isEmpty {
      rows.append(ExportRow(kind: .plans, label: joined(plans), count: count(planRoles)))
    }

    let meshRoles: Set<FileRole> = [.meshGLB, .meshOBJ, .meshMTL, .texture]
    var meshes: [String] = []
    if present.contains(.meshGLB) { meshes.append("GLB") }
    if present.contains(.meshOBJ) {
      meshes.append(present.contains(.meshMTL) ? "OBJ + MTL" : "OBJ")
    } else if present.contains(.meshMTL) {
      meshes.append("MTL")
    }
    if present.contains(.texture) { meshes.append("textures") }
    if !meshes.isEmpty {
      meshes[0] = "Mesh " + meshes[0]
      rows.append(ExportRow(kind: .meshes, label: joined(meshes), count: count(meshRoles)))
    }

    let rawRoles: Set<FileRole> = [.pointCloudLAS, .rawRoomplanJSON, .rawDepth, .captureModel]
    var raw: [String] = []
    if present.contains(.pointCloudLAS) { raw.append("Point cloud LAS") }
    switch (present.contains(.rawRoomplanJSON), present.contains(.rawDepth)) {
    case (true, true): raw.append("raw RoomPlan + depth")
    case (true, false): raw.append("raw RoomPlan")
    case (false, true): raw.append("raw depth")
    case (false, false): break
    }
    if present.contains(.captureModel) { raw.append("capture model") }
    if !raw.isEmpty {
      rows.append(ExportRow(kind: .raw, label: joined(raw), count: count(rawRoles)))
    }
    return rows
  }

  /// The Capture record row (§3.3, compass C8): "compass: recorded" (one capture, read),
  /// "compass: every floor" (all of two or more), "compass: Floor 1, Floor 3 only" (some),
  /// "compass: not recorded" (none). A capture has a reading when its state is verified or
  /// approximate (`CompassState.isUsable`).
  public static func compassText(_ captures: [CaptureRecord.Capture]) -> String {
    let read = captures.filter { CompassState($0).isUsable }
    if read.isEmpty { return "compass: not recorded" }
    if read.count == captures.count {
      return captures.count == 1 ? "compass: recorded" : "compass: every floor"
    }
    return "compass: \(read.map(\.label).joined(separator: ", ")) only"
  }

  private static func joined(_ parts: [String]) -> String {
    parts.joined(separator: " \u{00B7} ")
  }

  private static func size(of url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }
}

/// The "Files" card and the progress card of Package status (phone-package §4.1).
public struct UploadProgressSummary: Equatable, Sendable {
  public enum Status: Equatable, Sendable {
    /// Every file of the category verified by the station.
    case confirmed
    case uploading(percent: Int)
    /// Nothing of the category started.
    case waiting
    /// The upload stopped on a file of this category (Upload stopped only).
    case stopped

    /// "Confirmed", "Uploading · 41%", "Waiting", "Stopped" (the glyph is drawn, not typed).
    public var text: String {
      switch self {
      case .confirmed: return "Confirmed"
      case .uploading(let percent): return "Uploading \u{00B7} \(percent)%"
      case .waiting: return "Waiting"
      case .stopped: return "Stopped"
      }
    }

    /// "uploading, 41 percent".
    public var spoken: String {
      switch self {
      case .confirmed: return "confirmed"
      case .uploading(let percent): return "uploading, \(percent) percent"
      case .waiting: return "waiting"
      case .stopped: return "stopped"
      }
    }
  }

  public enum Category: String, CaseIterable, Equatable, Sendable {
    case plansAndRecord = "Plans and record"
    case sitePhotos = "Site photos"
    case meshes = "Meshes"
    case pointClouds = "Point clouds"

    /// Which row a file is counted in. Capture record, field controls, capture model, the raw
    /// RoomPlan JSON, the plans and the legacy phone report count with the plans and record;
    /// raw depth with the point clouds.
    public static func of(_ role: FileRole) -> Category {
      switch role {
      case .photo: return .sitePhotos
      case .meshGLB, .meshOBJ, .meshMTL, .texture: return .meshes
      case .pointCloudLAS, .rawDepth: return .pointClouds
      default: return .plansAndRecord
      }
    }

    /// `upload.category.<identifier>`.
    public var identifier: String {
      switch self {
      case .plansAndRecord: return "plans"
      case .sitePhotos: return "photos"
      case .meshes: return "meshes"
      case .pointClouds: return "pointClouds"
      }
    }
  }

  public struct Row: Equatable, Sendable {
    public var category: Category
    public var status: Status

    public init(category: Category, status: Status) {
      self.category = category
      self.status = status
    }

    /// "Meshes, uploading, 41 percent".
    public var accessibilityLabel: String { "\(category.rawValue), \(status.spoken)" }
  }

  /// Bytes this package uploads that are done (carried-over files are not counted).
  public var bytesDone: Int64
  public var bytesTotal: Int64
  public var rows: [Row]

  public init(bytesDone: Int64, bytesTotal: Int64, rows: [Row]) {
    self.bytesDone = bytesDone
    self.bytesTotal = bytesTotal
    self.rows = rows
  }

  /// 0...1.
  public var fraction: Double {
    bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 0
  }

  /// "67%".
  public var percentText: String { "\(Self.percent(bytesDone, of: bytesTotal))%" }
  /// "512 of 768 MB".
  public var bytesText: String { ByteText.progress(bytesDone, of: bytesTotal) }

  /// Bytes count as done when the station verified the file, or when the blob service confirmed
  /// them (staged blocks, uploaded files waiting for the station's check). Files the station
  /// carried over from the superseded revision are left out of both numbers.
  ///
  /// `stopped`: the upload stopped for good (Upload stopped); `stoppedPath` names the file it
  /// stopped on, when known. That file's category shows "Stopped", else the first category that
  /// is not confirmed.
  public static func make(
    state: UploadState, manifest: PackageManifest, blockSize: Int = BlobBlocks.blockSize,
    stopped: Bool = false, stoppedPath: String? = nil
  ) -> UploadProgressSummary {
    let roles = Dictionary(
      manifest.files.map { ($0.path, $0.role) }, uniquingKeysWith: { first, _ in first })
    func done(_ file: FileUploadState) -> Int64 {
      switch file.phase {
      case .verified, .uploaded: return file.bytes
      case .pending, .sending: return min(file.bytes, Int64(file.stagedBlockIds.count) * Int64(blockSize))
      }
    }
    func category(_ file: FileUploadState) -> Category {
      Category.of(roles[file.path] ?? .captureRecord)
    }
    let uploaded = state.files.filter { !state.carriedOver.contains($0.path) }
    var perCategory: [Category: [FileUploadState]] = [:]
    for file in state.files {
      perCategory[category(file), default: []].append(file)
    }

    var rows = Category.allCases.compactMap { category -> Row? in
      guard let files = perCategory[category], !files.isEmpty else { return nil }
      if files.allSatisfy({ $0.phase == .verified }) {
        return Row(category: category, status: .confirmed)
      }
      // A later revision: the files the station carried over are confirmed at once and say
      // nothing about this package's own upload, so "started" and the percent count only its
      // own files.
      let own = files.filter { !state.carriedOver.contains($0.path) }
      let counted = own.isEmpty ? files : own
      let started = counted.contains {
        $0.phase != .pending || !$0.stagedBlockIds.isEmpty || $0.lastCheck != nil
      }
      guard started else { return Row(category: category, status: .waiting) }
      return Row(
        category: category,
        status: .uploading(
          percent: percent(
            counted.reduce(0) { $0 + done($1) }, of: counted.reduce(0) { $0 + $1.bytes })))
    }
    if stopped {
      let named = stoppedPath.flatMap { path in
        state.files.first { $0.path == path }.map(category)
      }
      let index =
        rows.firstIndex { $0.category == named && $0.status != .confirmed }
        ?? rows.firstIndex { $0.status != .confirmed }
      if let index { rows[index].status = .stopped }
    }
    return UploadProgressSummary(
      bytesDone: uploaded.reduce(0) { $0 + done($1) },
      bytesTotal: uploaded.reduce(0) { $0 + $1.bytes }, rows: rows)
  }

  /// floor(done / total × 100); 0 for an empty total.
  static func percent(_ done: Int64, of total: Int64) -> Int {
    guard total > 0 else { return 0 }
    return Int((min(1, Double(done) / Double(total)) * 100).rounded(.down))
  }
}

/// The "Station" card of Package status and Verdict received (phone-package §4.1, §5.1): what
/// the station did, each row done only when the station said so.
public struct StationTimeline: Equatable, Sendable {
  public enum RowID: String, CaseIterable, Sendable {
    case registered
    case checks
    case verdict
    case published
  }

  public enum State: Equatable, Sendable {
    case pending
    case inProgress
    case done
    case problem
  }

  /// The drawn shape before the title: ● done, ▲ partly or delayed, ■ blocked, ○ waiting.
  public enum Shape: Equatable, Sendable {
    case filled
    case triangle
    case square
    case ring
  }

  public struct Row: Equatable, Sendable {
    public var id: RowID
    public var state: State
    public var shape: Shape
    /// "Registered", "Checks run", "Verdict · Limited".
    public var title: String
    /// "14:02", "May 16 · 14:01", "After upload", "—".
    public var detail: String
    /// The detail is a time (drawn with monospaced digits).
    public var isTime: Bool

    public init(
      id: RowID, state: State, shape: Shape, title: String, detail: String, isTime: Bool = false
    ) {
      self.id = id
      self.state = state
      self.shape = shape
      self.title = title
      self.detail = detail
      self.isTime = isTime
    }

    /// "Registered, done, 14:02"; "Checks, not yet, after upload"; "Verdict, not yet".
    public var accessibilityLabel: String {
      let word: String
      switch state {
      case .done: word = "done"
      case .pending, .inProgress: word = "not yet"
      case .problem: word = "delayed"
      }
      var spoken = detail
      let delayed = "Delayed \u{00B7} "
      if state == .problem, spoken.hasPrefix(delayed) { spoken.removeFirst(delayed.count) }
      let spokenDetail = detail == "\u{2014}" ? nil : (isTime ? spoken : PackageText.lowerFirst(spoken))
      return ([title, word] + (spokenDetail.map { [$0] } ?? [])).joined(separator: ", ")
    }
  }

  public var rows: [Row]

  public init(rows: [Row]) {
    self.rows = rows
  }

  public func row(_ id: RowID) -> Row? { rows.first { $0.id == id } }

  /// - registeredAt: when the station registered the package (nil before it answered).
  /// - isConfirmed: the station verified every file and accepted the seal.
  /// - includeRegistered: false on Verdict received, which starts with the checks.
  /// - now, timeZone: for "today" and the times (the phone's by default).
  public static func make(
    registeredAt: UTCTimestamp?, isConfirmed: Bool, station: StationPackageInfo?,
    verdict: VerdictStatus?, includeRegistered: Bool = true, now: Date = Date(),
    timeZone: TimeZone = .current
  ) -> StationTimeline {
    var times = TimeColumn(now: now, timeZone: timeZone)
    var rows: [Row] = []
    let dash = "\u{2014}"

    if includeRegistered {
      if let registeredAt {
        rows.append(
          Row(
            id: .registered, state: .done, shape: .filled, title: "Registered",
            detail: times.next(registeredAt.date), isTime: true))
      } else {
        rows.append(
          Row(
            id: .registered, state: .pending, shape: .ring, title: "Registered",
            detail: "When online"))
      }
    }

    let stage: StationPackageStage? = isConfirmed ? (station?.stage ?? .checksQueued) : nil
    switch stage {
    case nil, .uploading?:
      rows.append(
        Row(id: .checks, state: .pending, shape: .ring, title: "Checks", detail: "After upload"))
    case .checksQueued?:
      rows.append(
        Row(id: .checks, state: .inProgress, shape: .ring, title: "Checks", detail: "Queued"))
    case .checking?:
      rows.append(
        Row(id: .checks, state: .inProgress, shape: .ring, title: "Checks", detail: "Running"))
    case .checkError?:
      rows.append(
        Row(
          id: .checks, state: .problem, shape: .triangle, title: "Checks",
          detail: "Delayed \u{00B7} the station retries"))
    case .verdictReady?:
      let finished = station?.checks?.finishedAt ?? verdict?.evaluatedAt
      rows.append(
        Row(
          id: .checks, state: .done, shape: .filled, title: "Checks run",
          detail: finished.map { times.next($0.date) } ?? dash, isTime: finished != nil))
    }

    if let verdict {
      let shape: Shape
      switch verdict.outcome {
      case .ready: shape = .filled
      case .limited: shape = .triangle
      case .blocked: shape = .square
      }
      rows.append(
        Row(
          id: .verdict, state: .done, shape: shape, title: "Verdict \u{00B7} \(verdict.word)",
          detail: times.next(verdict.evaluatedAt.date), isTime: true))
    } else {
      rows.append(Row(id: .verdict, state: .pending, shape: .ring, title: "Verdict", detail: dash))
    }

    let title = "Published to the HUB"
    switch station?.publication?.status {
    case .published?:
      let published = station?.publication?.publishedAt
      rows.append(
        Row(
          id: .published, state: .done, shape: .filled, title: title,
          detail: published.map { times.next($0.date) } ?? dash, isTime: published != nil))
    case .publishFailed?:
      rows.append(
        Row(id: .published, state: .problem, shape: .triangle, title: title, detail: "Not yet"))
    case .pending?, .publishing?:
      rows.append(
        verdict == nil
          ? Row(id: .published, state: .pending, shape: .ring, title: title, detail: dash)
          : Row(id: .published, state: .inProgress, shape: .ring, title: title, detail: "Publishing"))
    case nil:
      // No publication state from the station: never claimed, never guessed.
      rows.append(Row(id: .published, state: .pending, shape: .ring, title: title, detail: dash))
    }
    return StationTimeline(rows: rows)
  }

  /// The times down the card: the first shows "HH:mm" when it is today, else "MMM d · HH:mm";
  /// each later one "HH:mm" when on the same day as the time above it, else with the date.
  private struct TimeColumn {
    let now: Date
    let timeZone: TimeZone
    var previous: Date?

    mutating func next(_ date: Date) -> String {
      let reference = previous ?? now
      previous = date
      let time = PackageText.time(date, in: timeZone)
      guard !PackageText.isSameDay(date, reference, in: timeZone) else { return time }
      return "\(PackageText.shortDate(date, in: timeZone)) \u{00B7} \(time)"
    }
  }
}
