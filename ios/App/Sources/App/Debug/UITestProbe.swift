// UI-test probes and hooks. DEBUG ONLY: compiled only in the Debug configuration (`#if DEBUG`;
// ios/project.yml excludes `UITest*` files from Release), and used only in the UI-test mode.
#if DEBUG
  import AppCore
  import CaptureContract
  import CaptureCore
  import Foundation
  import Observation
  import PackageCore
  import StationClient
  import SwiftUI

  /// What the in-process station received, for the UI tests to read (hidden elements of
  /// `UITestProbeView`): the newest capture record uploaded (compass §13.4: schema 1.1.0 and the
  /// four heading fields) and the newest next-revision notice (phone-package §10.4).
  @MainActor
  @Observable
  final class UITestProbe {
    static let shared = UITestProbe()

    /// "schemaVersion 1.1.0 · Floor 1: heading 212.0 · accuracy 8 · source true · recorded",
    /// or "none".
    var uploadedRecord = "none"
    /// "revision 2 · Site photos (1 photo) · sent 1": the newest notice and how many the station
    /// accepted, or "none".
    var nextRevisionNotice = "none"
    private var noticesSent = 0

    func noticeSent(_ summary: String) {
      noticesSent += 1
      nextRevisionNotice = "\(summary) \u{00B7} sent \(noticesSent)"
    }

    /// The capture record the station stored, as the probe line.
    nonisolated static func summary(ofRecord data: Data) -> String {
      guard
        let record = try? CaptureContractJSON.makeDecoder().decode(CaptureRecord.self, from: data)
      else { return "unreadable" }
      let captures = record.captures.map { capture -> String in
        let heading = capture.heading.map { String(format: "%.1f", $0) } ?? "none"
        var parts = ["\(capture.label): heading \(heading)"]
        parts.append("accuracy \(capture.headingAccuracy.map(String.init) ?? "none")")
        parts.append("source \(capture.headingSource?.rawValue ?? "none")")
        parts.append(capture.headingRecordedAt == nil ? "not recorded" : "recorded")
        return parts.joined(separator: " \u{00B7} ")
      }
      return "schemaVersion \(record.schemaVersion.rawValue) \u{00B7} "
        + captures.joined(separator: "; ")
    }

    /// The notice the station stored, as the probe line.
    nonisolated static func summary(ofNotice data: Data) -> String {
      guard
        let notice = try? CaptureContractJSON.makeDecoder().decode(
          NextRevisionNoticeInput.self, from: data)
      else { return "unreadable" }
      return (["revision \(notice.revision)"] + notice.changes.map { "\($0.title) (\($0.detail))" })
        .joined(separator: " \u{00B7} ")
    }
  }

  /// The station of the UI tests, noting each next-revision notice it accepts.
  final class ProbeStationTransport: HTTPTransport, @unchecked Sendable {
    private let base: any HTTPTransport

    init(base: any HTTPTransport) {
      self.base = base
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      let answer = try await base.send(request)
      if request.httpMethod == "PUT", request.url?.path.hasSuffix("/next-revision") == true,
        answer.1.statusCode == 200, let body = request.httpBody
      {
        let line = UITestProbe.summary(ofNotice: body)
        await MainActor.run { UITestProbe.shared.noticeSent(line) }
      }
      return answer
    }
  }

  /// The blob storage of the UI tests, noting the capture record each package stored: the
  /// bytes the station holds, read back from its storage once the upload is committed.
  struct ProbeBlobTransport: BlobTransport {
    let base: UITestBlobTransport

    func putBlob(_ upload: BlobUpload) async throws {
      try await base.putBlob(upload)
      await note(upload)
    }

    func putBlock(_ upload: BlobUpload, blockId: String, offset: Int64, length: Int) async throws {
      try await base.putBlock(upload, blockId: blockId, offset: offset, length: length)
    }

    func putBlockList(_ upload: BlobUpload, blockIds: [String]) async throws {
      try await base.putBlockList(upload, blockIds: blockIds)
      await note(upload)
    }

    private func note(_ upload: BlobUpload) async {
      guard upload.file.lastPathComponent == PackageLayout.captureRecordFileName,
        let stored = base.storage.blob(at: upload.target.blobLocation)
      else { return }
      let line = UITestProbe.summary(ofRecord: stored)
      await MainActor.run { UITestProbe.shared.uploadedRecord = line }
    }
  }

  /// The probe's hidden elements, `debug.uploadedRecord` and `debug.nextRevisionNotice`.
  struct UITestProbeView: View {
    var body: some View {
      if case .uiTestReplay = LaunchModeResolver.resolve(
        arguments: ProcessInfo.processInfo.arguments, isDebugBuild: true)
      {
        let probe = UITestProbe.shared
        VStack(spacing: 0) {
          hidden("Uploaded capture record", probe.uploadedRecord, id: "debug.uploadedRecord")
          hidden("Next-revision notice", probe.nextRevisionNotice, id: "debug.nextRevisionNotice")
        }
        .allowsHitTesting(false)
      }
    }

    private func hidden(_ label: String, _ value: String, id: String) -> some View {
      Color.clear
        .frame(width: 1, height: 1)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
        .accessibilityIdentifier(id)
    }
  }

  /// Hooks the UI tests switch on with launch arguments (`UITestLaunchOptions`).
  enum UITestHooks {
    /// `-ChapterUITestNotifyDuringScan`: 1.5 s into a live scan, a "Verdict: …" notification
    /// of another capture's newest package is tapped (the same entry as the AppDelegate's,
    /// `PackageRouter.openPackage(id:)`).
    @MainActor
    static func captureStepChanged(_ step: CaptureFlowStep?, home: HomeModel) {
      guard step == .scanning,
        UITestLaunchOptions(arguments: ProcessInfo.processInfo.arguments).notifiesDuringScan,
        let open = home.visit
      else { return }
      let packageId = home.visitsOnDisk
        .filter { $0.workspace != open.workspace }
        .compactMap(\.newestPackage)
        .max { $0.manifest.sealedAt < $1.manifest.sealedAt }?
        .packageId
      guard let packageId else { return }
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        PackageRouter.shared.openPackage(id: packageId)
      }
    }
  }
#endif
