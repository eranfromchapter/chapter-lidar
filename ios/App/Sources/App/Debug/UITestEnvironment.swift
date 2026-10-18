// UI-test mode. DEBUG ONLY: this file is compiled only in the Debug configuration (`#if DEBUG`,
// and ios/project.yml excludes `UITest*` files from Release builds), and it is selected only
// when the app is launched with `-ChapterUITestReplay <fixture>` (LaunchModeResolver).
#if DEBUG
  import AppCore
  import CaptureContract
  import CaptureCore
  import CaptureUI
  import FieldKitUI
  import Foundation
  import StationClient
  import SwiftUI

  enum UITestEnvironment {
    /// Replay scan of the bundled fixture capture, the fixture's photo as the camera, and the
    /// in-process station and token from AppCore. Nothing leaves the simulator.
    @MainActor
    static func services(fixture: String, cacheRoot: URL) -> AppServices {
      let package = Bundle.main.resourceURL!.appendingPathComponent("package", isDirectory: true)
      let captureDirectory = firstDirectory(containing: "roomplan.json", under: package)
      let photo = firstFile(withExtension: "jpg", under: package)
      let storage = UITestBlobStorage()
      let station = StationAPI(
        configuration: try! StationClientConfiguration(stationURL: UITestStationTransport.stationURL),
        tokenProvider: UITestTokenProvider(),
        transport: UITestStationTransport(storage: storage))
      let version = ProcessInfo.processInfo.operatingSystemVersion
      let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
      return AppServices(
        station: station,
        projects: ProjectStore(
          source: station, cacheDirectory: cacheRoot.appendingPathComponent("StationCache")),
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
          return try ReplaySession(source: ReplaySource.load(directory: captureDirectory))
        },
        photoSource: .fixed({
          guard let photo else { throw CocoaError(.fileNoSuchFile) }
          return try Data(contentsOf: photo)
        }),
        fixedOperator: SignedInOperator(name: "UI Test Operator", userId: nil))
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

  /// Stand-in for the camera viewfinder in UI tests: "Take photo" returns the fixture photo, then
  /// the real labeling screen (PhotoLabelingView) is shown.
  struct UITestViewfinder: View {
    let model: PhotoLabelingModel
    let onDone: () -> Void

    var body: some View {
      if model.pendingOriginal == nil {
        VStack(spacing: 24) {
          Text(model.title).font(ChapterTokens.Typography.headline)
          Button("Take photo") { Task { await model.takePhoto() } }
            .frame(minHeight: 52)
          Button("Done", action: onDone).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChapterTokens.Palette.ground)
      } else {
        PhotoLabelingView(model: model)
      }
    }
  }
#endif
