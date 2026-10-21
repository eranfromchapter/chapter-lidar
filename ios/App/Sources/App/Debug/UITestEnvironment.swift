// UI-test mode. DEBUG ONLY: this file is compiled only in the Debug configuration (`#if DEBUG`,
// and ios/project.yml excludes `UITest*` files from Release builds), and it is selected only
// when the app is launched with `-ChapterUITestReplay <fixture>` (LaunchModeResolver).
#if DEBUG
  import AppCore
  import CaptureContract
  import CaptureCore
  import CaptureUI
  import ChapterUI
  import FieldKitUI
  import Foundation
  import StationClient
  import SwiftUI

  enum UITestEnvironment {
    /// Replay scan of the bundled fixture capture, played step by step; the fixture's photo as
    /// the camera; the scripted compass (`-ChapterUITestCompass`, critique R-24); and the
    /// in-process station and token from AppCore. Nothing leaves the simulator.
    @MainActor
    static func services(fixture: String, cacheRoot: URL, options: UITestLaunchOptions)
      -> AppServices
    {
      let package = Bundle.main.resourceURL!.appendingPathComponent("package", isDirectory: true)
      let captureDirectory = firstDirectory(containing: "roomplan.json", under: package)
      let photo = firstFile(withExtension: "jpg", under: package)
      // -ChapterUITestVerdict, -ChapterUITestOffline, -ChapterUITestRefuse (phone-package §9.1).
      let stationOptions = UITestStationOptions(arguments: ProcessInfo.processInfo.arguments)
      let storage = UITestBlobStorage(offlineSeconds: stationOptions.offlineSeconds)
      var transport: any HTTPTransport = UITestStationTransport(
        storage: storage, options: stationOptions)
      if options.projectsOffline {
        transport = OfflineProjectsTransport(base: transport)
      }
      let station = StationAPI(
        configuration: try! StationClientConfiguration(stationURL: UITestStationTransport.stationURL),
        tokenProvider: UITestTokenProvider(), transport: transport)
      let projects = ProjectStore(
        source: station, cacheDirectory: cacheRoot.appendingPathComponent("StationCache"))
      if options.projectsOffline {
        // The list is saved once (as a phone that was online earlier), then the station is
        // offline: New capture shows the copy saved on this phone (phone-capture §10.3 U4).
        Task { _ = try? await projects.projects() }
      }
      // The pre-check takes a moment, as on the phone, so "Reading the compass…" can be seen.
      let compass = FakeCompass(
        FakeCompass.Script(rawValue: options.compass) ?? .verified,
        precheckDuration: .milliseconds(1200))
      let version = ProcessInfo.processInfo.operatingSystemVersion
      let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
      return AppServices(
        station: station, projects: projects,
        blobTransport: UITestBlobTransport(storage: storage), signIn: nil,
        // The simulator has no LiDAR; the replay stands in for the scanner.
        capabilities: DeviceCapabilities(
          model: "UITestReplay", osName: .iOS, osVersion: osVersion,
          supportsSceneReconstructionMesh: true, roomPlanSupported: true),
        device: DeviceInfo(
          model: "UITestReplay", marketingName: "Simulator replay", osName: .iOS,
          osVersion: osVersion, hasLidar: false),
        makeSession: { _ in
          guard let captureDirectory else { throw CaptureSessionError.scanFailed("no fixture") }
          let replay = try ReplaySession(
            source: ReplaySource.load(directory: captureDirectory), autoPlay: false,
            compass: compass.replayCompass, trackingLost: options.trackingLost)
          return PacedReplaySession(replay: replay, step: options.scanStep)
        },
        photoSource: .fixed({
          guard let photo else { throw CocoaError(.fileNoSuchFile) }
          return try Data(contentsOf: photo)
        }),
        compass: compass,
        fixedOperator: SignedInOperator(name: UITestTokenProvider.operatorName, userId: nil),
        asksForNotifications: false)
    }

    private static func firstDirectory(containing name: String, under root: URL) -> URL? {
      let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
        if url.lastPathComponent == name { return url.deletingLastPathComponent() }
      }
      return nil
    }

    private static func firstFile(withExtension ext: String, under root: URL) -> URL? {
      let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
        if url.pathExtension.lowercased() == ext { return url }
      }
      return nil
    }
  }

  /// The replay played one step every `step` seconds while it runs, so the live scan's states
  /// (the compass chip reading, tracking lost, the counts) can be seen and tapped in UI tests.
  /// Finish floor plays the rest at once.
  actor PacedReplaySession: CaptureSession {
    nonisolated let events: AsyncStream<CaptureSessionEvent>
    private let replay: ReplaySession
    private let step: TimeInterval
    private var driver: Task<Void, Never>?

    init(replay: ReplaySession, step: TimeInterval) {
      self.replay = replay
      self.step = step
      events = replay.events
    }

    func start(_ configuration: CaptureSessionConfiguration) async throws {
      try await replay.start(configuration)
      drive()
    }

    func pause() async throws {
      driver?.cancel()
      try await replay.pause()
    }

    func resume() async throws {
      try await replay.resume()
      drive()
    }

    func finish() async throws -> CaptureSessionResult {
      driver?.cancel()
      return try await replay.finish()
    }

    func cancel() async {
      driver?.cancel()
      await replay.cancel()
    }

    private func drive() {
      driver?.cancel()
      let replay = self.replay
      let nanoseconds = UInt64(step * 1_000_000_000)
      driver = Task {
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: nanoseconds)
          guard !Task.isCancelled, await replay.advance() else { return }
        }
      }
    }
  }

  /// The stub station with the HUB project list offline after its first answer
  /// (`-ChapterUITestOffline`).
  final class OfflineProjectsTransport: HTTPTransport, @unchecked Sendable {
    private let base: any HTTPTransport
    private let lock = NSLock()
    private var answered = 0

    init(base: any HTTPTransport) {
      self.base = base
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      if request.url?.path.hasSuffix("/projects") == true {
        let count = lock.withLock { () -> Int in
          answered += 1
          return answered
        }
        if count > 1 { throw URLError(.notConnectedToInternet) }
      }
      return try await base.send(request)
    }
  }

  /// The camera viewfinder in UI tests: the real viewfinder screen (`PhotoViewfinder`: title,
  /// Rooms, Done, the rooms that still need a photo, the shutter) over a stand-in for the camera
  /// image; "Take photo" returns the fixture photo, then the real labeling screen is shown.
  struct UITestViewfinder: View {
    let model: PhotoLabelingModel
    let onDone: () -> Void
    let onRenameRooms: (() -> Void)?

    var body: some View {
      if model.pendingOriginal == nil {
        PhotoViewfinder(model: model, onDone: onDone, onRenameRooms: onRenameRooms) {
          ZStack {
            LinearGradient(
              colors: [Color(white: 0.30), Color(white: 0.16)], startPoint: .top,
              endPoint: .bottom)
            Label("Simulator: the fixture photo stands in for the camera", systemImage: "camera")
              .chapterTextStyle(.footnote)
              .foregroundStyle(Color.white.opacity(0.7))
          }
        }
      } else {
        PhotoLabelingView(model: model, onDone: onDone, onRenameRooms: onRenameRooms)
      }
    }
  }
#endif
