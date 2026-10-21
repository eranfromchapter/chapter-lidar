import CaptureContract
import Foundation
import PackageCore
import XCTest

@testable import AppCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Package status (phone-package §4): the Files card, the progress, the texts of each state and
/// how upload errors are told apart.
final class UploadProgressTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    if let base { Fixtures.removeTemporaryDirectory(base) }
  }

  func testCategoriesFollowTheDrawnRows() {
    XCTAssertEqual(UploadProgressSummary.Category.of(.photo), .sitePhotos)
    XCTAssertEqual(UploadProgressSummary.Category.of(.meshMTL), .meshes)
    XCTAssertEqual(UploadProgressSummary.Category.of(.texture), .meshes)
    XCTAssertEqual(UploadProgressSummary.Category.of(.rawDepth), .pointClouds)
    XCTAssertEqual(UploadProgressSummary.Category.of(.pointCloudLAS), .pointClouds)
    for role: FileRole in [
      .captureRecord, .fieldControls, .captureModel, .rawRoomplanJSON, .planDXF, .roomsCSV,
      .planPDF, .planPNG, .planSVG, .spatialReportPDF,
    ] {
      XCTAssertEqual(UploadProgressSummary.Category.of(role), .plansAndRecord, role.rawValue)
    }
    XCTAssertEqual(UploadProgressSummary.Category.plansAndRecord.rawValue, "Plans and record")
    XCTAssertEqual(
      UploadProgressSummary.Category.allCases.map(\.identifier),
      ["plans", "photos", "meshes", "pointClouds"])
  }

  func testStatusWords() {
    XCTAssertEqual(UploadProgressSummary.Status.confirmed.text, "Confirmed")
    XCTAssertEqual(UploadProgressSummary.Status.uploading(percent: 41).text, "Uploading \u{00B7} 41%")
    XCTAssertEqual(UploadProgressSummary.Status.waiting.text, "Waiting")
    XCTAssertEqual(UploadProgressSummary.Status.stopped.text, "Stopped")
    XCTAssertEqual(
      UploadProgressSummary.Row(category: .meshes, status: .uploading(percent: 41))
        .accessibilityLabel, "Meshes, uploading, 41 percent")
  }

  /// Box room: plans and record confirmed, the LAS half staged, the photo not started.
  private func midUpload() throws -> (SealedFixture, UploadState) {
    let fixture = try SealedFixture(in: base)
    var state = UploadState(package: fixture.sealed, dealId: "D")
    let roles = Dictionary(fixture.sealed.manifest.files.map { ($0.path, $0.role) }, uniquingKeysWith: { a, _ in a })
    for index in state.files.indices {
      switch UploadProgressSummary.Category.of(roles[state.files[index].path]!) {
      case .plansAndRecord: state.files[index].phase = .verified
      case .pointClouds where roles[state.files[index].path] == .rawDepth:
        state.files[index].phase = .verified
      case .pointClouds:
        state.files[index].stagedBlockIds = ["0"]
      default: break
      }
    }
    return (fixture, state)
  }

  func testStatusesAndPercentPerCategory() throws {
    let (fixture, state) = try midUpload()
    let las = try XCTUnwrap(state.files.first { $0.path.hasSuffix("points.las") })
    let depth = try XCTUnwrap(state.files.first { $0.path.hasSuffix("depth-samples.bin") })
    let block = Int(las.bytes / 3)
    let summary = UploadProgressSummary.make(
      state: state, manifest: fixture.sealed.manifest, blockSize: block)
    XCTAssertEqual(summary.rows.map(\.category), [.plansAndRecord, .sitePhotos, .pointClouds])
    XCTAssertEqual(summary.rows[0].status, .confirmed)
    XCTAssertEqual(summary.rows[1].status, .waiting)
    let expected = Int(
      (Double(depth.bytes + Int64(block)) / Double(depth.bytes + las.bytes) * 100).rounded(.down))
    XCTAssertEqual(summary.rows[2].status, .uploading(percent: expected))
    let total = state.files.reduce(0) { $0 + $1.bytes }
    XCTAssertEqual(summary.bytesTotal, total)
    XCTAssertEqual(
      summary.percentText, "\(Int((Double(summary.bytesDone) / Double(total) * 100).rounded(.down)))%")
  }

  func testCarriedOverFilesAreNotCounted() throws {
    let (fixture, uploading) = try midUpload()
    var state = uploading
    let plans = Set(
      fixture.sealed.manifest.files.filter { UploadProgressSummary.Category.of($0.role) == .plansAndRecord }
        .map(\.path))
    state.carriedOver = plans
    let summary = UploadProgressSummary.make(state: state, manifest: fixture.sealed.manifest)
    XCTAssertEqual(
      summary.bytesTotal, state.files.filter { !plans.contains($0.path) }.reduce(0) { $0 + $1.bytes })
    XCTAssertEqual(summary.rows[0].status, .confirmed, "carried over and verified")
  }

  func testStoppedIsShownOnTheFileItStoppedOnElseTheFirstOpenCategory() throws {
    let (fixture, state) = try midUpload()
    let photo = try XCTUnwrap(fixture.sealed.manifest.files.first { $0.role == .photo }?.path)
    let onPhoto = UploadProgressSummary.make(
      state: state, manifest: fixture.sealed.manifest, stopped: true, stoppedPath: photo)
    XCTAssertEqual(onPhoto.rows.map(\.status.text), ["Confirmed", "Stopped", onPhoto.rows[2].status.text])
    XCTAssertNotEqual(onPhoto.rows[2].status, .stopped)
    let unnamed = UploadProgressSummary.make(state: state, manifest: fixture.sealed.manifest, stopped: true)
    XCTAssertEqual(unnamed.rows[1].status, .stopped, "the first category that is not confirmed")
  }

  // MARK: Errors (§4.3)

  func testOfflineAndStationUnavailableAreToldApart() {
    for code: URLError.Code in [
      .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
      .cannotFindHost, .cannotConnectToHost, .timedOut,
    ] {
      XCTAssertEqual(UploadErrorKind.of(URLError(code)), .transient(.offline), "\(code)")
    }
    XCTAssertEqual(UploadErrorKind.of(URLError(.badServerResponse)), .transient(.stationUnavailable))
    XCTAssertEqual(UploadErrorKind.of(StationAPIError.offline), .transient(.offline))
    XCTAssertEqual(UploadErrorKind.of(StationAPIError.network(code: -1200)), .transient(.stationUnavailable))
    XCTAssertEqual(UploadErrorKind.of(BlobTransportError.network("lost")), .transient(.offline))
    for status in [503, 500, 429, 408] {
      XCTAssertEqual(
        UploadErrorKind.of(StationProblem(status: status, code: "x")), .transient(.stationUnavailable))
    }
    XCTAssertEqual(
      UploadErrorKind.of(BlobTransportError.http(status: 500, code: nil)), .transient(.stationUnavailable))
    XCTAssertEqual(
      UploadErrorKind.of(PackageUploadError.targetsKeepFailing(path: "p")), .transient(.stationUnavailable))
  }

  func testFatalMessagesNameTheFile() {
    XCTAssertEqual(
      UploadErrorKind.of(StationProblem(status: 409, code: "package_conflict")),
      .fatal("The station refused the upload (409 package_conflict)."))
    XCTAssertEqual(
      UploadErrorKind.of(BlobTransportError.http(status: 403, code: "AuthorizationFailure")),
      .fatal("The storage service refused a file (403 AuthorizationFailure)."))
    let path = "Original Exports/floor-1/a/plan.pdf"
    XCTAssertEqual(
      UploadErrorKind.of(PackageUploadError.localFileChanged(path: path)),
      .fatal("plan.pdf changed on the phone after sealing. It was not uploaded.", path: path))
    XCTAssertEqual(UploadErrorKind.of(SignInRequired()), .signIn)
  }

  // MARK: Texts of each state (§4.1–4.3)

  private func snapshot(
    _ fixture: SealedFixture, state: UploadState? = nil, activity: UploadActivity,
    station: StationPackageInfo? = nil, verdict: VerdictStatus? = nil
  ) -> UploadSnapshot {
    UploadSnapshot(
      packageId: fixture.sealed.packageId, package: SealedPackageSummary.make(fixture.sealed),
      state: state ?? UploadState(package: fixture.sealed, dealId: "D"), activity: activity,
      station: station, verdict: verdict, manifest: fixture.sealed.manifest)
  }

  private func confirmed(_ fixture: SealedFixture) -> UploadState {
    var state = UploadState(package: fixture.sealed, dealId: "D")
    for index in state.files.indices { state.files[index].phase = .verified }
    state.sealResult = PackageSealResult(
      packageId: fixture.sealed.packageId, visitId: fixture.sealed.visitId, dealId: "D",
      revision: 1, status: .checksQueued, createdAt: Make.time("2026-05-16T14:02:00Z"), files: [])
    state.registeredAt = Make.time("2026-05-16T14:02:00Z")
    return state
  }

  func testTitlesAndCaptions() throws {
    let fixture = try SealedFixture(in: base)
    let uploading = snapshot(fixture, activity: .uploading)
    XCTAssertEqual(uploading.title, "Uploading")
    XCTAssertEqual(uploading.caption, "Uploads continue in the background. You can close the app.")
    XCTAssertEqual(
      snapshot(fixture, activity: .waitingToRetry(.offline)).caption,
      "Paused: no connection. Resumes on its own. You can close the app.")
    XCTAssertEqual(
      snapshot(fixture, activity: .waitingToRetry(.stationUnavailable)).caption,
      "Paused: the station is not answering. Resumes on its own. You can close the app.")
    XCTAssertEqual(
      snapshot(fixture, activity: .signInRequired).caption, "Sign in again to continue the upload.")

    let done = snapshot(fixture, state: confirmed(fixture), activity: .confirmed)
    XCTAssertEqual(done.title, "Uploaded")
    XCTAssertEqual(done.caption, "The station has every file. Checks run next.")
    let delayed = snapshot(
      fixture, state: confirmed(fixture), activity: .confirmed, station: Make.station(.checkError))
    XCTAssertEqual(delayed.phase, .checksDelayed)
    XCTAssertEqual(delayed.title, "Uploaded")
    XCTAssertEqual(
      delayed.caption, "The station has every file. Its checks are delayed; it retries on its own.")

    let stopped = snapshot(
      fixture, activity: .failed("The station refused the upload (409 package_conflict)."))
    XCTAssertEqual(stopped.title, "Upload stopped")
    XCTAssertEqual(stopped.caption, "The station refused the upload (409 package_conflict).")
    XCTAssertEqual(
      stopped.stoppedNote(canReseal: true),
      "Nothing was deleted. Try again, or re-seal to upload the files as they are on this phone "
        + "now as revision 2. Revision 1 stays on this phone.")
    XCTAssertEqual(
      stopped.stoppedNote(canReseal: false),
      "Nothing was deleted. Try again. This phone no longer has the scans to re-seal; start a new "
        + "capture.")
    XCTAssertEqual(stopped.resealTitle, "Re-seal as revision 2")
    XCTAssertEqual(stopped.resealAlertTitle, "Re-seal as revision 2?")
    XCTAssertEqual(
      stopped.resealAlertMessage,
      "The app builds revision 2 from the scans, photos and controls on this phone and uploads "
        + "it. Revision 1 stays on this phone and is not uploaded further.")
    XCTAssertEqual(
      stopped.footnote(notificationsAllowed: true),
      "Files stay on this phone until the station confirms each one.")
    XCTAssertEqual(
      uploading.footnote(notificationsAllowed: true),
      "Files stay on this phone until the station confirms each one. You will get a notification "
        + "with the verdict.")
    XCTAssertEqual(
      uploading.footnote(notificationsAllowed: false),
      "Files stay on this phone until the station confirms each one. Open the app to see the "
        + "verdict.")
    XCTAssertEqual(
      SealFailureText.make(PackageError.emptyPackage),
      "The package could not be sealed: a package needs at least one file. Nothing was uploaded.")
  }

  /// A package confirmed by an app build before v2 has no `registeredAt` in its state: the seal
  /// answer's `createdAt` says when the station registered it.
  func testRegisteredFallsBackToTheSealAnswer() throws {
    let fixture = try SealedFixture(in: base)
    var state = confirmed(fixture)
    state.registeredAt = nil
    let snapshot = snapshot(fixture, state: state, activity: .confirmed)
    XCTAssertEqual(snapshot.registeredAt, Make.time("2026-05-16T14:02:00Z"))
    let registered = snapshot.timeline(now: Make.time("2026-05-16T15:00:00Z").date, timeZone: Make.utc)
      .row(.registered)
    XCTAssertEqual(registered?.state, .done)
    XCTAssertEqual(registered?.detail, "14:02")
  }

  func testSubtitleAndCaptions() throws {
    let fixture = try SealedFixture(in: base)
    let snapshot = snapshot(fixture, activity: .uploading)
    let summary = SealedPackageSummary.make(fixture.sealed)
    XCTAssertEqual(
      snapshot.subtitle,
      "100 Example Street, Testville, NY 00000 \u{00B7} \(summary.fileCount) files \u{00B7} "
        + ByteText.format(summary.totalBytes))
    XCTAssertEqual(snapshot.navigationCaption, "Revision 1 \u{00B7} sealed")

    var verdict = VerdictStatus(Make.verdict(.ready))
    verdict.evaluatedAt = Make.time("2026-05-16T14:02:00Z")
    var withVerdict = self.snapshot(
      fixture, state: confirmed(fixture), activity: .confirmed, verdict: verdict)
    XCTAssertEqual(withVerdict.phase, .verdict)
    XCTAssertEqual(withVerdict.title, "Fixture box-room")
    XCTAssertEqual(withVerdict.navigationCaption, "Revision 1")
    XCTAssertEqual(
      withVerdict.verdictSubtitle(timeZone: Make.utc), "Sealed Jan 25, 2026 \u{00B7} checked May 16, 2026")
    withVerdict.state.supersededBy = LowercaseUUID()
    XCTAssertEqual(withVerdict.navigationCaption, "Revision 1 \u{00B7} superseded")
  }

  func testALaterRevisionCountsOnlyWhatItUploads() throws {
    let fixture = try SealedFixture(in: base)
    let draft = try PackageDraft.nextRevision(of: fixture.sealed)
    let second = try PackageAssembler().assemble(
      draft, at: fixture.visit.workspace.packageURL(packageId: draft.packageId.rawValue))
    var state = UploadState(package: second, dealId: "D")
    let photo = try XCTUnwrap(second.manifest.files.first { $0.role == .photo })
    state.carriedOver = Set(second.manifest.files.map(\.path)).subtracting([photo.path])
    let snapshot = UploadSnapshot(
      packageId: second.packageId, package: SealedPackageSummary.make(second), state: state,
      activity: .uploading, manifest: second.manifest)
    XCTAssertEqual(
      snapshot.subtitle,
      "100 Example Street, Testville, NY 00000 \u{00B7} revision 2 \u{00B7} 1 new or changed file "
        + "\u{00B7} \(ByteText.format(photo.bytes))")
    XCTAssertEqual(snapshot.resealTitle, "Re-seal as revision 3")
  }
}
