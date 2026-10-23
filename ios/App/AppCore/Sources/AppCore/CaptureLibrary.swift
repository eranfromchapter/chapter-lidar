import CaptureContract
import CaptureCore
import Foundation
import PackageCore

/// One visit workspace on the phone as the Captures home sees it.
public struct CaptureLibraryVisit: Sendable {
  public let workspace: VisitWorkspace
  /// `visit.json` (built from a v1 workspace's package or draft when it had none); nil for a v1
  /// workspace whose scans have no capture record.
  public let file: VisitFile?
  /// The sealed packages that open, oldest first; the last is the newest revision.
  public let packages: [SealedPackage]
  /// Scans of a v1 workspace without a capture record (`VisitStore.legacyScans`).
  public let legacyScans: [VisitStore.LegacyScan]
  /// Why `visit.json` could not be read (torn, or written by a newer app): the visit is listed
  /// all the same, so it and its sealed packages do not vanish from the home (phone-capture §9
  /// R7). Nil when the file was read, or there is none.
  public let unreadable: String?

  public init(
    workspace: VisitWorkspace, file: VisitFile?, packages: [SealedPackage],
    legacyScans: [VisitStore.LegacyScan] = [], unreadable: String? = nil
  ) {
    self.workspace = workspace
    self.file = file
    self.packages = packages
    self.legacyScans = legacyScans
    self.unreadable = unreadable
  }

  /// The newest revision's package.
  public var newestPackage: SealedPackage? { packages.last }

  /// A v1 visit that has only scans: listed so its scans stay reachable, but it cannot be
  /// resumed or packaged (no HUB project, address or operator was kept).
  public var isLegacyScansOnly: Bool { file == nil && unreadable == nil && !legacyScans.isEmpty }
}

/// The Captures home from disk (phone-capture §5.4, critique R-28): one row per visit, from its
/// `visit.json`, its `packages/*`, each package's `<packageId>.upload-state.json` and
/// `<packageId>.station-status.json`, and the live upload snapshots of the coordinators running
/// in the app (they are newer than the files). Reads only; v1 workspaces get their `visit.json`
/// on the first read (`VisitStore.loadOrMigrate`).
public enum CaptureLibrary {
  /// Every workspace under `visitsRoot` with something to show, by folder name. Empty folders
  /// (the v1 app made one at every launch) are left out; one whose `visit.json` cannot be read
  /// is listed as such (`unreadable`). Nothing is deleted.
  public static func visits(visitsRoot: URL) -> [CaptureLibraryVisit] {
    let folders =
      (try? FileManager.default.contentsOfDirectory(
        at: visitsRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    return folders.sorted { $0.path < $1.path }.compactMap { folder in
      guard !folder.lastPathComponent.hasPrefix("."),
        (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
      else { return nil }
      return visit(VisitWorkspace(root: folder))
    }
  }

  /// One workspace; nil when it holds neither a visit nor a scan.
  public static func visit(_ workspace: VisitWorkspace) -> CaptureLibraryVisit? {
    let packages = VisitStore.sealedPackages(of: workspace)
    let file: VisitFile?
    do {
      file = try VisitStore.load(workspace) ?? VisitStore.migrate(workspace)
    } catch {
      // Listed with what it says, and never rewritten.
      return CaptureLibraryVisit(
        workspace: workspace, file: nil, packages: packages,
        unreadable: String(describing: error))
    }
    if file != nil {
      return CaptureLibraryVisit(workspace: workspace, file: file, packages: packages)
    }
    let scans = VisitStore.legacyScans(of: workspace)
    guard !scans.isEmpty else { return nil }
    return CaptureLibraryVisit(
      workspace: workspace, file: nil, packages: packages, legacyScans: scans)
  }

  /// The home's state: the rows of every visit, the operator for the avatar, and whether sealed
  /// packages still wait for the station (the account dialog's message).
  public static func load(
    visitsRoot: URL, live: [LowercaseUUID: UploadSnapshot] = [:], operatorName: String,
    hasPendingUploads: Bool = false, timeZone: TimeZone = .current
  ) -> CapturesHomeState {
    CapturesHomeState(
      rows: visits(visitsRoot: visitsRoot).compactMap { row(for: $0, live: live, timeZone: timeZone) },
      operatorName: operatorName, hasPendingUploads: hasPendingUploads)
  }

  /// The row of one visit (the table of critique R-28). Its id is the workspace's id.
  public static func row(
    for visit: CaptureLibraryVisit, live: [LowercaseUUID: UploadSnapshot] = [:],
    timeZone: TimeZone = .current
  ) -> CapturesHomeState.Row? {
    let id = visit.workspace.id
    if visit.unreadable != nil {
      return unreadableRow(visit, timeZone: timeZone)
    }
    guard let file = visit.file else {
      return legacyRow(id: id, scans: visit.legacyScans, timeZone: timeZone)
    }
    let title = ProjectTitle.of(file.record)
    let count = CaptureCountText.make(file.record)
    var activity = file.updatedAt.date

    if let revision = file.revision, !file.isSealed {
      return .inProgress(
        id: id, title: title, count: count, .revisionStarted(next: revision.number),
        activity: activity)
    }
    guard let package = visit.newestPackage else {
      return .inProgress(id: id, title: title, count: count, .notSealed, activity: activity)
    }
    activity = max(activity, package.manifest.sealedAt.date)
    let status = PackageProgress(package: package, live: live[package.packageId])
    if let verdict = status.verdict {
      return .sealed(
        id: id, title: title, revision: package.manifest.revision,
        sealedAt: package.manifest.sealedAt.date, verdict: Self.verdict(verdict.outcome),
        timeZone: timeZone)
    }
    return .inProgress(id: id, title: title, count: count, status.progress, activity: activity)
  }

  /// "Scan of Oct 20, 2026" / "1 scan · no HUB project recorded": a v1 visit with scans only.
  static func legacyRow(id: String, scans: [VisitStore.LegacyScan], timeZone: TimeZone)
    -> CapturesHomeState.Row?
  {
    guard let newest = scans.first else { return nil }
    return CapturesHomeState.Row(
      id: id, title: legacyTitle(newest.date, timeZone: timeZone),
      subtitle: "\(CaptureText.plural(scans.count, "scan", "scans")) \u{00B7} no HUB project recorded",
      destination: .overview, sortDate: newest.date)
  }

  /// "Scan of Oct 20, 2026".
  public static func legacyTitle(_ date: Date, timeZone: TimeZone = .current) -> String {
    "Scan of \(CaptureText.sealedDate(date, timeZone: timeZone))"
  }

  /// "Could not be read" (In progress, ■ Unreadable): a visit whose `visit.json` cannot be read.
  /// The title is the project's, from its newest sealed package or "Package ready" draft when
  /// there is one, else "Capture of Oct 21, 2026" (the file's date). Tapping it opens the newest
  /// sealed package's status, or says why it cannot be opened.
  static func unreadableRow(_ visit: CaptureLibraryVisit, timeZone: TimeZone)
    -> CapturesHomeState.Row
  {
    let record =
      visit.newestPackage.flatMap(SealedPackageSummary.captureRecord(of:))
      ?? VisitStore.newestDraftRecord(of: visit.workspace)?.record
    let date =
      (try? visit.workspace.visitURL.resourceValues(forKeys: [.contentModificationDateKey]))?
      .contentModificationDate ?? visit.newestPackage?.manifest.sealedAt.date ?? Date()
    return CapturesHomeState.Row(
      id: visit.workspace.id,
      title: record.map(ProjectTitle.of)
        ?? "Capture of \(CaptureText.sealedDate(date, timeZone: timeZone))",
      subtitle: record.map { "\(CaptureCountText.make($0)) \u{00B7} could not be read" }
        ?? "Could not be read",
      status: RowStatusValue(.missing, "Unreadable"), destination: .overview, sortDate: date)
  }

  static func verdict(_ outcome: VerdictOutcome) -> CapturesHomeState.Row.Verdict {
    switch outcome {
    case .ready: return .ready
    case .limited: return .limited
    case .blocked: return .blocked
    }
  }
}

/// Where the upload and the station are for one sealed package: from the coordinator's live
/// snapshot when one runs, else from the package's upload state and station status files.
public struct PackageProgress: Sendable {
  /// The verdict, once known.
  public let verdict: VerdictStatus?
  /// The home row's case while there is no verdict.
  public let progress: CapturesHomeState.Row.Progress

  public init(package: SealedPackage, live: UploadSnapshot?) {
    if let live {
      verdict = live.verdict
      switch live.phase {
      case .stopped: progress = .uploadStopped
      case .paused:
        progress = .paused(bytes: live.progress.bytesText, fraction: live.progress.fraction)
      case .signInRequired: progress = .signInRequired
      case .uploaded, .checksDelayed, .verdict: progress = .checking
      case .uploading:
        progress = .uploading(bytes: live.progress.bytesText, fraction: live.progress.fraction)
      }
      return
    }
    let cache = try? StationStatusStore(packageRoot: package.root).load()
    verdict = cache?.verdict
    let state =
      (try? UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root)).load())
      ?? nil
    if state?.isConfirmedByStation == true {
      progress = .checking
    } else if PhotosErasedRecord.isErased(packageAt: package.root) {
      // Its photos were erased before the station confirmed it: it is never uploaded.
      progress = .uploadStopped
    } else {
      let dealId = state?.dealId ?? SealedPackageSummary.captureRecord(of: package)?.hub.dealId ?? ""
      let summary = UploadProgressSummary.make(
        state: state ?? UploadState(package: package, dealId: dealId), manifest: package.manifest)
      progress = .uploading(bytes: summary.bytesText, fraction: summary.fraction)
    }
  }
}
